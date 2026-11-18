#!/usr/bin/env python3
"""Bind the repaired exports to the independent audit of the original run."""

import argparse
import csv
import hashlib
import io
import json
from pathlib import Path

import fitz
from PIL import Image


FIGURES = {
    "fig_A_qualified_cycle_rate": ("summary.csv", "scenario.csv", "overhead.csv", "status.csv", "pair_gains.csv"),
    "fig_B_frequency_selectivity": ("snr.csv", "profiles.csv", "pool.csv", "summary.csv", "status.csv"),
}
COUNTS = {"planned": 120, "completed": 100, "design_rejected": 20,
          "payload_samples": 1_320_000_000, "tx_clipped_samples": 47}
TEXT_REPORTS = ("results_zh.md", "figure_captions_en.txt", "raw_checkpoint_audit.json")
AUDITED_TABLES = (
    "source_manifest.csv", "seed_plan.csv", "status.csv", "summary.csv", "scenario.csv",
    "seed.csv", "pool.csv", "design_rounds.csv", "profiles.csv", "snr.csv",
    "overhead.csv", "events.csv", "power_adc.csv", "pair_gains.csv", "length_sensitivity.csv",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def identity(entries):
    lines = (f"{name} {value}" for name, value in sorted(entries.items()))
    return hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest()


def postprocessor_source():
    root = Path(__file__).resolve().parents[1]
    files = [*root.glob("*.m"), *root.glob("private/*.m"), *root.glob("tools/*.py")]
    return {path.relative_to(root).as_posix(): digest(path) for path in files}


def image_pair(output, stem):
    png, pdf = output / f"{stem}.png", output / f"{stem}.pdf"
    with Image.open(png) as image:
        require(image.format == "PNG" and min(image.size) >= 1500, f"{stem}: PNG geometry")
        dpi = image.info.get("dpi", (0, 0))
        require(all(number >= 299 for number in dpi), f"{stem}: PNG resolution")
        image.verify()
    with fitz.open(pdf) as document:
        require(len(document) == 1 and not document[0].get_images() and
                document[0].get_text().strip(), f"{stem}: expected vector PDF with text")
    return png, pdf


def check_notes(output):
    note = (output / "results_zh.md").read_text(encoding="utf-8")
    marker = "<!-- VCSEL_POSTPROCESS_COMPLETE -->"
    require(note.rstrip().endswith(marker) and note.count(marker) == 1,
            "Chinese report is incomplete")
    for text in ("Case 1", "Case 2", "0.25", "0.50", "120", "100", "20", "47", "硬件成本"):
        require(text in note, f"Chinese report missing {text!r}")
    caption = (output / "figure_captions_en.txt").read_text(encoding="utf-8")
    require("Fig. A" in caption and "Fig. B" in caption and "Wilson" in caption,
            "English captions are incomplete")


def write_or_compare(path, content, verify):
    if verify:
        require(path.read_bytes() == content, f"Saved attestation differs: {path.name}")
    else:
        path.write_bytes(content)


def table_bytes(rows):
    content = io.StringIO(newline="")
    writer = csv.DictWriter(content, fieldnames=list(rows[0]), lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return content.getvalue().encode("utf-8")


def verify_outputs(source, output, verify, require_tables_mat=False):
    source = source.resolve()
    output = output.resolve()
    require(source != output and source not in output.parents,
            "Exports must be kept outside the original run folder")
    audit_path = output / "raw_checkpoint_audit.json"
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    require(audit["valid"] and all(audit[key] == value for key, value in COUNTS.items()),
            "Independent raw checkpoint audit did not attest the uploaded batch")
    source_hashes = {
        path.relative_to(source).as_posix(): digest(path)
        for path in source.rglob("*") if path.is_file()
    }
    require(audit["original_artifact_manifest_id"] == identity(source_hashes),
            "Original files differ from the independently audited archive")
    check_notes(output)
    report_files = list(TEXT_REPORTS)
    mat_proof_path = output / "tables_mat_export_check.json"
    has_mat_proof = mat_proof_path.is_file()
    require(has_mat_proof or not require_tables_mat, "Missing tables.mat export check")
    if has_mat_proof:
        proof = json.loads(mat_proof_path.read_text(encoding="utf-8"))
        require(proof["valid"] and proof["complete_utf8_report"] and
                proof["report_generated_from"] == "tables.mat" and
                proof["tables_mat_sha256"] == source_hashes["tables.mat"] and
                proof["source_id"] == audit["source_id"] and proof["seed_id"] == audit["seed_id"] and
                proof["config_id"] == audit["config_id"] and
                proof["results_zh_sha256"] == digest(output / "results_zh.md"),
                "tables.mat export proof does not match the audited batch and report")
        for name, info in proof["tables_csv_parity"].items():
            require(info["rows"] == audit["csv_row_counts"][name], f"{name}: MAT audit row count differs")
        expected_tables = {name.removesuffix(".csv") for name in AUDITED_TABLES} - {"source_manifest", "seed_plan"}
        require(set(proof["tables_csv_parity"]) == expected_tables, "Incomplete tables.mat comparison")
        report_files.append(mat_proof_path.name)

    provenance = json.loads((output / "fig_A_render_provenance.json").read_text(encoding="utf-8"))
    for name, sha in provenance["source_csv_sha256"].items():
        require(sha == digest(source / name), f"Figure A source digest differs: {name}")
    for name, sha in provenance["outputs_sha256"].items():
        require(sha == digest(output / name), f"Figure A export digest differs: {name}")
    manifest = []
    for stem, inputs in FIGURES.items():
        png, pdf = image_pair(output, stem)
        manifest.append({
            "figure": stem, "png_file": png.name, "pdf_file": pdf.name,
            "data_sha256": identity({name: digest(source / name) for name in inputs}),
            "png_sha256": digest(png), "pdf_sha256": digest(pdf),
        })
    write_or_compare(output / "figure_manifest.csv", table_bytes(manifest), verify)
    report_manifest = [{"report_file": name, "sha256": digest(output / name)} for name in report_files]
    write_or_compare(output / "report_manifest.csv", table_bytes(report_manifest), verify)
    input_rows = [{"relative_path": name, "sha256": sha} for name, sha in sorted(source_hashes.items())]
    write_or_compare(output / "original_input_manifest.csv", table_bytes(input_rows), verify)
    tables = output / "audited_tables"
    if not verify:
        tables.mkdir(exist_ok=True)
    for name in AUDITED_TABLES:
        write_or_compare(tables / name, (source / name).read_bytes(), verify)
        require(digest(tables / name) == source_hashes[name], f"Audited table changed: {name}")
    result = {
        "valid": True,
        "native_matlab_verifier_executed": False,
        "acquisition_raw_checkpoint_audit_valid": True,
        "python_exports_valid": True,
        "tables_mat_report_validated": has_mat_proof,
        "new_payload_runs": 0,
        "postprocess_version": "vcsel_mmf_2025_postprocess_v1",
        "postprocess_source_id": identity(postprocessor_source()),
        "original_source_id": audit["source_id"],
        "original_artifact_manifest_id": audit["original_artifact_manifest_id"],
        "raw_checkpoint_audit_sha256": digest(audit_path),
        "counts": COUNTS,
        "figure_manifest_sha256": digest(output / "figure_manifest.csv"),
        "report_manifest_sha256": digest(output / "report_manifest.csv"),
        "original_input_manifest_sha256": digest(output / "original_input_manifest.csv"),
        "audited_tables": list(AUDITED_TABLES),
        "scope": "Original raw checkpoint audit and repaired Python exports. The native MATLAB receipt is separate.",
    }
    write_or_compare(output / "postprocess_verification.json",
                     (json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode("utf-8"), verify)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("formal_folder", type=Path)
    parser.add_argument("output_folder", type=Path)
    parser.add_argument("--verify", action="store_true", help="Check a written attestation without modifying any files")
    parser.add_argument("--require-tables-mat", action="store_true",
                        help="Require the UTF-8 report to come directly from the archived tables.mat")
    args = parser.parse_args()
    print(json.dumps(verify_outputs(args.formal_folder, args.output_folder, args.verify, args.require_tables_mat), indent=2))


if __name__ == "__main__":
    main()
