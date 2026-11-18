#!/usr/bin/env python3
"""Digitize the two named 50 m link-model traces from the supplied Fig. 2(a)."""

import argparse
import csv
import hashlib
import json
from pathlib import Path

import fitz
import numpy as np


PDF_PAGE = 3
PAPER_DOI = "10.1364/SPPCOM.2025.SpTh3E.4"
REPOSITORY_URL = (
    "https://iris.polito.it/retrieve/38f0bac4-b804-4762-b4e3-ebb980760c8b/"
    "2025_SPPCOM_DMTvsPAM.pdf"
)
X_GRID = range(130, 137)
Y_GRID = range(137, 142)
TRACE_ONE = 185
TRACE_TWO = 186
STROKE_PT = 0.72774
SAMPLE_STEP_PT = 0.08
FIELDS = ("case", "frequency_GHz", "gain_dB", "pdf_x_pt", "pdf_y_pt", "path_seq", "segment_id")


def path_sections(items):
    """Read consecutive PDF line items and keep separate subpaths."""
    sections = []
    previous = None
    for operator, start, end in items:
        if operator != "l":
            raise ValueError(f"Unexpected PDF panel operator {operator!r}")
        if previous is None or previous != start:
            sections.append([(start.x, start.y)])
        sections[-1].append((end.x, end.y))
        previous = end
    return [np.asarray(section) for section in sections]


def colored_path(drawings, sequence, paint, expected):
    path = drawings[sequence]
    if path["seqno"] != sequence or not np.allclose(path[paint], expected, atol=0.002):
        raise ValueError(f"Unexpected trace drawing at PDF sequence {sequence}")
    return path_sections(path["items"])


def dash_centerline(points):
    """Measure flat cap centers and midsections in a filled dash outline."""
    if not np.array_equal(points[0], points[-1]):
        raise ValueError("Expected a closed vector dash outline.")
    ends_a = points[:-1]
    ends_b = points[1:]
    length = np.linalg.norm(ends_b - ends_a, axis=1)
    mids = (ends_a + ends_b) / 2
    cap_like = np.flatnonzero(abs(length - STROKE_PT) <= 0.004)
    if len(cap_like) < 2:
        raise ValueError("Could not locate both stroke-width dash cap edges.")
    left = cap_like[np.argmin(mids[cap_like, 0])]
    right = cap_like[np.argmax(mids[cap_like, 0])]
    first, last = mids[[left, right]]
    inside_lo = max(ends_a[left, 0], ends_b[left, 0])
    inside_hi = min(ends_a[right, 0], ends_b[right, 0])
    interior = []
    if inside_hi > inside_lo:
        count = int(np.ceil((inside_hi - inside_lo) / SAMPLE_STEP_PT))
        interior_x = np.linspace(inside_lo, inside_hi, count + 2)[1:-1]
        for x in interior_x:
            crosses = (ends_a[:, 0] <= x) != (ends_b[:, 0] <= x)
            a, b = ends_a[crosses], ends_b[crosses]
            y = a[:, 1] + (x - a[:, 0]) * (b[:, 1] - a[:, 1]) / (b[:, 0] - a[:, 0])
            if len(y) < 2:
                raise ValueError("Dash outline has fewer than two vertical intersections.")
            interior.append((x, (min(y) + max(y)) / 2))
    return np.vstack([first, *interior, last])


def trim_box(points, x_min, x_max):
    """Remove geometry outside the panel, with its intersection at the border."""
    if np.any(np.diff(points[:, 0]) <= 0):
        raise ValueError("Each digitized trace segment must be increasing in frequency.")
    inside = points[(points[:, 0] >= x_min) & (points[:, 0] <= x_max)]
    if points[0, 0] < x_min < points[-1, 0] and not np.any(points[:, 0] == x_min):
        inside = np.vstack([[x_min, np.interp(x_min, points[:, 0], points[:, 1])], inside])
    if points[0, 0] < x_max < points[-1, 0] and not np.any(points[:, 0] == x_max):
        inside = np.vstack([inside, [x_max, np.interp(x_max, points[:, 0], points[:, 1])]])
    return inside


def extract(pdf, output):
    output.mkdir(parents=True, exist_ok=True)
    with fitz.open(pdf) as doc:
        page = doc[PDF_PAGE - 1]
        caption = "Normalized transfer functions at 50 m of the analyzed VCSEL-MMF links"
        if caption not in page.get_text():
            raise ValueError("Expected Fig. 2 caption absent from physical PDF page 3.")
        drawings = page.get_drawings()
    x_marks = np.asarray([drawings[i]["rect"].x0 for i in X_GRID])
    y_marks = np.asarray([drawings[i]["rect"].y0 for i in Y_GRID][::-1])
    x_labels = np.arange(0, 121, 20)
    y_labels = np.arange(0, -13, -3)
    # Endpoints define the affine mapping. Intermediate grid ticks test it.
    x_scale = 120 / (x_marks[-1] - x_marks[0])
    y_scale = -12 / (y_marks[-1] - y_marks[0])
    x_error = float(np.max(abs((x_marks - x_marks[0]) * x_scale - x_labels)))
    y_error = float(np.max(abs((y_marks - y_marks[0]) * y_scale - y_labels)))
    if x_error > 0.001 or y_error > 0.001:
        raise ValueError("PDF panel grid is inconsistent with the labeled axes.")
    line, = colored_path(drawings, TRACE_ONE, "color", (0.102, 0.200, 0.702))
    orange = colored_path(drawings, TRACE_TWO, "fill", (0.851, 0.325, 0.098))
    orange.sort(key=lambda points: min(points[:, 0]))
    segments = {1: [line], 2: [dash_centerline(points) for points in orange]}
    csv_path = output / "Fig2a_digitized.csv"
    counts = {}
    coverage = {}
    for_write = []
    for case, case_segments in segments.items():
        ranges = []
        case_rows = []
        for segment, points in enumerate(case_segments, 1):
            points = trim_box(points, x_marks[0], x_marks[-1])
            f = (points[:, 0] - x_marks[0]) * x_scale
            g = (points[:, 1] - y_marks[0]) * y_scale
            ranges.append([float(f[0]), float(f[-1])])
            sequence = TRACE_ONE if case == 1 else TRACE_TWO
            for j, (x, y) in enumerate(points):
                case_rows.append((case, f[j], g[j], x, y, sequence, segment))
        if any(a[3] >= b[3] for a, b in zip(case_rows, case_rows[1:])):
            raise ValueError(f"Case {case} samples overlap in PDF x coordinates.")
        counts[str(case)] = len(case_rows)
        coverage[str(case)] = ranges
        for_write.extend(case_rows)
    with csv_path.open("w", encoding="ascii", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(FIELDS)
        writer.writerows(
            (case, f"{f:.10f}", f"{g:.10f}", f"{x:.10f}", f"{y:.10f}", seq, segment)
            for case, f, g, x, y, seq, segment in for_write
        )
    legend = drawings[188]["rect"]
    orange_ranges = coverage["2"]
    provenance = {
        "paper": {
            "title": "Comparing PAM and DMT for VCSELs-modulated Links over MMF",
            "authors": "A. M. Rosa Brusin et al.",
            "conference": "SPPCom 2025",
            "doi": PAPER_DOI,
            "public_pdf": REPOSITORY_URL,
            "pdf_sha256": hashlib.sha256(pdf.read_bytes()).hexdigest(),
            "pdf_page": PDF_PAGE,
            "figure": "Fig. 2(a)",
            "caption_excerpt": caption,
            "scope": "Normalized 50 m link-model transfer functions for selected VCSEL–MMF dataset cases.",
        },
        "axes": {
            "x_label": "Frequency [GHz]",
            "y_label": "Normalized link transfer function [dB]",
            "pdf_coordinate_origin": "Physical page top-left; x rightward, y downward; PDF points.",
            "frequency_anchors_pt_GHz": list(zip(x_marks.tolist(), x_labels.tolist())),
            "gain_anchors_pt_dB": list(zip(y_marks.tolist(), y_labels.tolist())),
            "frequency_max_anchor_residual_GHz": x_error,
            "gain_max_anchor_residual_dB": y_error,
            "panel_range_GHz": [0, 120],
            "panel_range_dB": [-12, 0],
        },
        "extraction": {
            "library": "PyMuPDF",
            "vector_method": "Read native PDF line operators. Case 1 is its solid stroke centerline. "
            "Case 2 is flattened into dashed filled polygons. Recover cap midpoints using edges "
            "of nominal stroke width, then take the midpoint of vertical outline intersections "
            "between the caps. No samples are inserted across dash gaps.",
            "case_1": {"drawing_sequence": TRACE_ONE, "legend": "Case 1", "style": "solid blue"},
            "case_2": {"drawing_sequence": TRACE_TWO, "legend": "Case 2", "style": "dashed orange"},
            "trace_width_pdf_points": STROKE_PT,
            "reader_gain_error_floor_dB": float(STROKE_PT * abs(y_scale) / 2),
            "reader_frequency_error_floor_GHz": float(STROKE_PT * x_scale / 2),
            "precision_scope": "Conservative half-stroke coordinate scale, not original model uncertainty. "
            "An extremum inside a dash gap can be less certain. The CSV retains native PDF coordinates to audit the mapping.",
            "occlusion": "Case 2 passes behind the white legend around its high-frequency notch near "
            "100 GHz. The drawing operators retain the orange polygons before the legend draws over them. "
            "No raster extrapolation was needed.",
            "legend_rectangle_pdf_points": list(legend),
            "plot_clipping": "Samples are limited to the 0–120 GHz axes. The deep lobes stay above the displayed −12 dB floor.",
            "interpolation": "Digitized CSV gives samples and dash IDs. Any interpolation across dashes is a separate fitting operation.",
        },
        "coverage": {
            "common_range_GHz": [0, 120],
            "samples_by_case": counts,
            "segment_ranges_GHz_by_case": coverage,
            "maximum_case_2_dash_gap_GHz": max(b[0] - a[1] for a, b in zip(orange_ranges, orange_ranges[1:])),
        },
        "data_file": {"filename": csv_path.name, "sha256": hashlib.sha256(csv_path.read_bytes()).hexdigest()},
    }
    (output / "Fig2a_provenance.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path, help="Supplied proof-format public paper PDF")
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "evidence")
    args = parser.parse_args()
    extract(args.pdf, args.output_dir)


if __name__ == "__main__":
    main()
