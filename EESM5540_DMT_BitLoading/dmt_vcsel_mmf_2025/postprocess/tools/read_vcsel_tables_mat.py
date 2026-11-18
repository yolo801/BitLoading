"""Read the v7 R2026a table layout in the archived VCSEL tables.mat.

The decoder accepts the saved table/string layouts seen in this study only.
Every decoded column is compared with the already independently audited CSV.
It does not evaluate MATLAB code or recreate MATLAB's serialization hash.
"""

import csv
import hashlib
import io
import math
from pathlib import PureWindowsPath

import numpy as np
from scipy.io import loadmat
from scipy.io.matlab._mio5 import MatFile5Reader


MAGIC = 3707764736


def require(condition, message):
    if not condition:
        raise ValueError(message)


def snapshot_data(path):
    saved = loadmat(path, simplify_cells=True)
    snapshot = saved["checkpoint"]
    workspace = saved["__function_workspace__"].tobytes()
    with path.open("rb") as stream:
        header = stream.read(124)
    require(workspace[:8] == b"\x00\x01IM\x00\x00\x00\x00", "Unsupported MAT workspace format")
    reader = MatFile5Reader(io.BytesIO(header + workspace[:4] + workspace[8:]), mat_dtype=True)
    reader.initialize_read()
    reader.read_file_header()
    variable, _ = reader.read_var_header()
    block = reader.read_var_array(variable, True)
    mcos = block["MCOS"].item()
    require(mcos["s2"].item() == b"FileWrapper__", "Unsupported MATLAB object wrapper")
    return snapshot, mcos["arr"].item().ravel()


def object_ref(block, object_class):
    values = block.ravel()
    require(values.dtype == np.uint32 and len(values) == 6 and
            values[:4].tolist() == [MAGIC, 2, 1, 1] and int(values[-1]) == object_class,
            "Unsupported table/string reference")
    return int(values[4])


def strings(block, height):
    data = block.ravel()
    require(data[:4].tolist() == [1, 2, height, 1],
            "Unsupported MATLAB string-array shape")
    lengths = [int(n) for n in data[4:4+height]]
    encoded = data[4+height:].astype("<u8", copy=False).tobytes()
    units = sum(lengths)
    require(len(lengths) == height and len(encoded) - 2 * units in (0, 2, 4, 6),
            "String lengths do not match the serialized data")
    values = []
    cursor = 0
    for size in lengths:
        next_cursor = cursor + 2 * size
        values.append(encoded[cursor:next_cursor].decode("utf-16-le"))
        cursor = next_cursor
    return values


def decode_tables(snapshot, block):
    cursor, next_object = 2, 1
    for name, table in snapshot["tables"].items():
        table_id = object_ref(table["arr"].item(), 2)
        require(table_id == next_object, f"{name}: unexpected MATLAB table object order")
        pending = {}
        while block[cursor].dtype == np.uint64:
            pending[table_id + len(pending) + 1] = block[cursor]
            cursor += 1
        values, version, height, row_names, width, names, properties = block[cursor:cursor+7]
        height, width = int(height.item()), int(width.item())
        require(version.item() == 2 and row_names.size == 0 and values.shape == names.shape == (1, width)
                and "VariableNamesOriginal" in properties.dtype.names,
                f"{name}: unsupported saved table dimensions or properties")
        columns, types = {}, {}
        for var, data in zip(names.ravel(), values.ravel()):
            label = str(var.item())
            if data.dtype == np.uint32:
                identifier = object_ref(data, 1)
                columns[label] = strings(pending.pop(identifier), height)
                types[label] = "string"
            else:
                require(data.dtype in (np.float64, np.bool_) and data.shape == (height, 1),
                        f"{name}.{label}: unsupported numeric/logical column")
                columns[label] = data.ravel().tolist()
                types[label] = "logical" if data.dtype == np.bool_ else "double"
        require(not pending and len(columns) == width, f"{name}: unused objects or duplicate columns")
        cursor += 7
        next_object = table_id + 1 + sum(kind == "string" for kind in types.values())
        yield name, columns, types
    require(len(block) - cursor == 3, "Unexpected extra serialized objects")


def checked_rows(path, columns, types):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        require(reader.fieldnames == list(columns), f"{path.name}: column schema differs")
        reference = list(reader)
    decoded = []
    for index, data in enumerate(zip(*columns.values(), strict=True)):
        require(index < len(reference), f"{path.name}: extra rows in tables.mat")
        row = {}
        for (name, kind), value in zip(types.items(), data, strict=True):
            expected = reference[index][name]
            if kind == "string":
                match = value == expected
                row[name] = value
            elif kind == "logical":
                match = expected in ({"1", "true"} if value else {"0", "false"})
                row[name] = str(int(value))
            else:
                number = float(expected) if expected else math.nan
                match = math.isclose(value, number, rel_tol=2e-12, abs_tol=2e-15) or (
                    math.isnan(value) and math.isnan(number))
                row[name] = format(value, ".17g")
            require(match, f"{path.name}:{index + 2} {name}: MAT value differs from CSV")
        decoded.append(row)
    require(len(decoded) == len(reference), f"{path.name}: missing rows in tables.mat")
    return decoded


def file_sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def archived_context(formal, protocol, tables):
    with (formal / "source_manifest.csv").open(encoding="utf-8-sig", newline="") as stream:
        notes = next(row for row in csv.DictReader(stream)
                     if row["relative_path"] == "private/dmt_vm_graphics_notes.m")
    environment = protocol["environment"]
    project = PureWindowsPath(environment["pwd"])
    runlog = (formal / "run.log").read_text(encoding="utf-8-sig")
    require(str(project) in runlog and "MATLAB:printf:invalidInputType" in
            (formal / "failure_status.txt").read_text(encoding="utf-8-sig"),
            "Archived source path or failure identifier is missing")
    ref = protocol["cfg"]["representative"]
    notch = protocol["cfg"]["case2_notch_GHz"]
    matches = lambda row: all(float(row[key]) == ref[key] for key in ("case_id", "swing", "calibration_id"))
    values = []
    for row in tables["summary"]:
        if not matches(row):
            continue
        profile = [tone for tone in tables["profiles"]
                   if matches(tone) and tone["strategy"] == row["strategy"]]
        if profile:
            closest = min(profile, key=lambda tone: abs(float(tone["frequency_GHz"]) - notch))
            values.append({
                "strategy": row["strategy"], "state": row["state"],
                "frequency_GHz": float(closest["frequency_GHz"]),
                "M": int(closest["M"]), "bits_per_symbol": int(row["bits_per_symbol"]),
                "profile_orders": sorted({int(tone["M"]) for tone in profile}),
            })
    require(len(values) == 2, "Expected both representative archived profiles")
    return {
        "recorded_matlab_version": environment["version"],
        "recorded_project_directory": str(project),
        "original_entry_path_from_project": str(project / "run_dmt_vcsel_mmf_2025.m"),
        "original_notes_path_from_private_resolution": str(project / notes["relative_path"]),
        "original_notes_manifest_sha256": notes["sha256"],
        "original_error_identifier": "MATLAB:printf:invalidInputType",
        "archive_path_basis": "Recorded project directory, original private source manifest and stack; not live which -all.",
        "representative_arguments_from_tables_mat": values,
    }


def inspect_tables(formal):
    mat_path = formal / "tables.mat"
    snapshot, block = snapshot_data(mat_path)
    protocol = loadmat(formal / "Protocol.mat", simplify_cells=True)["checkpoint"]
    require(snapshot["phase"] == protocol["phase"] == "formal" and
            snapshot["study"] == protocol["version"] == "dmt_vcsel_mmf_2025" and
            all(snapshot[key] == protocol[key] for key in ("source_id", "config_id", "seed_id")),
            "tables.mat does not belong to this formal protocol")
    tables = {}
    metadata = {}
    for name, columns, types in decode_tables(snapshot, block):
        tables[name] = checked_rows(formal / f"{name}.csv", columns, types)
        metadata[name] = {"rows": len(tables[name]), "columns": types}
    proof = {
        "valid": True,
        "engine": "SciPy MAT v7 deserialization of the archived R2026a table/string layout",
        "native_matlab_execution": False,
        "tables_mat_sha256": file_sha(mat_path),
        "archived_matlab_tables_hash": snapshot["tables_hash"],
        "source_id": snapshot["source_id"],
        "config_id": snapshot["config_id"],
        "seed_id": snapshot["seed_id"],
        "tables_csv_parity": metadata,
        "archived_context": archived_context(formal, protocol, tables),
        "line_43_type_diagnosis": {
            "strategy": metadata["summary"]["columns"]["strategy"],
            "state": metadata["summary"]["columns"]["state"],
            "frequency_GHz": metadata["profiles"]["columns"]["frequency_GHz"],
            "M": metadata["profiles"]["columns"]["M"],
            "bits_per_symbol": metadata["summary"]["columns"]["bits_per_symbol"],
            "description": "Cell array of character vectors from compose with char format and join (MATLAB API semantics).",
        },
    }
    return tables, proof
