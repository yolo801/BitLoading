#!/usr/bin/env python3
"""Audit supplied MATLAB smoke artifacts without running a MATLAB simulation.

Run from this project: python3 tools/audit_uploaded_smoke.py
Requires NumPy and SciPy solely for this optional evidence audit. No empirical
BER is generated: all measured counts below come from user-uploaded files.
MATLAB table objects are intentionally not decoded; selected numeric structs
are read using variable_names to avoid opaque table serialization artifacts.
"""

from __future__ import annotations

import csv
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from scipy.io import loadmat


ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "evidence/imported_smoke"
CHECKS: list[dict] = []


def check(name: str, passed: bool, observed=None, expected=None, tolerance=None) -> None:
    row = {"name": name, "status": "PASS" if bool(passed) else "FAIL"}
    for key, value in (("observed", observed), ("expected", expected), ("tolerance", tolerance)):
        if value is not None:
            row[key] = value
    CHECKS.append(row)
    if not passed:
        raise AssertionError(name)


def close(name: str, observed, expected, tolerance: float = 1e-12) -> None:
    left, right = np.asarray(observed), np.asarray(expected)
    shape_ok = left.shape == right.shape
    if shape_ok and left.dtype.kind in "biufc" and right.dtype.kind in "biufc":
        delta = float(np.max(np.abs(left.astype(complex)-right.astype(complex)))) if left.size else 0.0
        check(name, math.isfinite(delta) and delta <= tolerance, delta, 0, tolerance)
    else:
        check(name, shape_ok and bool(np.array_equal(left, right)))


def read_csv(name: str) -> list[dict[str, str]]:
    with (EVIDENCE / name).open(newline="", encoding="utf-8-sig") as file:
        return list(csv.DictReader(file))


def qam_ber(order: int, gamma: float) -> float:
    return 4/math.log2(order)*(1-1/math.sqrt(order))*0.5*math.erfc(math.sqrt(3*gamma/(order-1))/math.sqrt(2))


def wilson(errors: int, bits: int) -> tuple[float, float]:
    p, z = errors/bits, 1.96
    d = 1+z*z/bits
    center = (p+z*z/(2*bits))/d
    radius = z*math.sqrt(p*(1-p)/bits+z*z/(4*bits*bits))/d
    return max(0, center-radius), min(1, center+radius)


def selected_mat(name: str, *variables: str) -> dict:
    return loadmat(EVIDENCE / name, variable_names=list(variables), simplify_cells=True)


def audit() -> dict:
    manifest = read_csv("import_manifest.csv")
    check("fourteen original uploaded files retained", len(manifest) == 14, len(manifest), 14)
    check("import manifest has unique names", len({r["file"] for r in manifest}) == len(manifest))
    for row in manifest:
        file = EVIDENCE / row["file"]
        check("original SHA256: "+file.name, hashlib.sha256(file.read_bytes()).hexdigest() == row["sha256"])
        check("original byte count: "+file.name, file.stat().st_size == int(row["bytes"]))

    cfg = selected_mat("config_snapshot.mat", "cfg")["cfg"]
    final = selected_mat("final_results.mat", "cfg", "calibration", "profiles", "runs", "smokeRuns")
    initial = selected_mat("initialization.mat", "calibration", "profiles", "loadingDiagnostics")
    partial = selected_mat("runs_partial.mat", "smokeRuns")
    check("cfg key set identical in snapshot and final", set(cfg) == set(final["cfg"]))
    for field, value in cfg.items():
        close("cfg consistency: "+field, value, final["cfg"][field])
    check("uploaded run mode is smoke, not main", cfg["runMode"] == "smoke", cfg["runMode"], "smoke")
    check("command is smoke", cfg["command"] == "run_dmt_experiment('smoke')")
    frozen = {"NFFT": 64, "NCP": 8, "Fs": 64e6, "Es": 1,
              "sigma_w2": 10**(-29/10), "targetBER": 1e-3, "margin_dB": 1,
              "trainSymbols": 1024, "probeSymbols": 2048, "mainSymbols": 100000,
              "smokeSymbols": 2000, "chunkSize": 2000}
    for field, value in frozen.items():
        close("frozen physical/config field: "+field, cfg[field], value)
    close("independent active carriers", cfg["k"], np.arange(1, 25), 0)
    close("FIR coefficients", cfg["h"], [0.25, 0.5, 0.25], 0)
    close("formal seed labels are only a schedule", cfg["seeds"], [11, 22, 33], 0)
    close("QAM set", cfg["Mset"], [4, 16, 64], 0)

    calibration = initial["calibration"]
    for field, value in calibration.items():
        check("calibration shape/finite: "+field, np.asarray(value).shape == (24,) and bool(np.all(np.isfinite(value))))
        close("unchanged calibration in final: "+field, value, final["calibration"][field], 0)
    close("residual SNR reconstructed from independent probe sums", calibration["gamma_hat"],
          calibration["probeSignalSum"]/calibration["probeResidualSum"], 1e-10)
    close("SNR dB reconstructed", calibration["gamma_hat_dB"], 10*np.log10(calibration["gamma_hat"]), 1e-12)
    close("probe QPSK signal counts", calibration["probeSignalSum"], np.full(24, 2048), 0)
    close("LS QPSK denominators", calibration["trainingDenominator"], np.full(24, 1024), 0)
    true_h = np.fft.fft(cfg["h"], n=64)[np.arange(1, 25)]
    close("saved diagnostic H_true vs FIR FFT", calibration["H_true"], true_h, 1e-14)
    close("saved diagnostic SNR vs FIR", calibration["gamma_true_dB"], 10*np.log10(abs(true_h)**2/cfg["sigma_w2"]), 1e-12)

    gamma = np.asarray(calibration["gamma_hat"], dtype=float)
    gamma_eff = gamma/10**(cfg["margin_dB"]/10)
    predicted = np.array([[qam_ber(order, value) for order in (4, 16, 64)] for value in gamma_eff])
    allowed = predicted <= cfg["targetBER"]
    check("every carrier feasible at QPSK", bool(np.all(allowed[:, 0])))
    close("stored conservative gamma_eff", initial["loadingDiagnostics"]["gamma_eff"], gamma_eff, 1e-10)
    close("stored conservative BER approximation", initial["loadingDiagnostics"]["predictedBER"], predicted, 1e-14)
    uniform = max(order for order, ok in zip((4, 16, 64), allowed.all(axis=0)) if ok)
    loaded = np.array([max(order for order, ok in zip((4, 16, 64), row) if ok) for row in allowed])
    profiles = {p["name"]: p for p in initial["profiles"]}
    final_profiles = {p["name"]: p for p in final["profiles"]}
    check("only original Uniform and Loaded profiles", set(profiles) == {"Uniform", "Loaded"})
    for name, expected in (("Uniform", np.full(24, uniform)), ("Loaded", loaded)):
        profile = profiles[name]
        close(name+" regenerated from saved estimated SNR", profile["M"], expected, 0)
        close(name+" B from independent carriers", profile["B"], float(np.log2(expected).sum()), 0)
        close(name+" bit grouping per carrier", profile["bits_per_symbol"], np.log2(expected), 0)
        close(name+" rate from B/Ts", profile["R_payload"], profile["B"]/cfg["Ts"], 1e-7)
        for field, value in profile.items():
            close(name+" profile frozen in final: "+field, value, final_profiles[name][field], 0)

    rows = read_csv("per_subcarrier_results.csv")
    summary = {row["scheme"]: row for row in read_csv("summary.csv")}
    check("old mixed CSV has 96 rows", len(rows) == 96, len(rows), 96)
    check("old CSV contains only seed0 and pooled", {row["seed"] for row in rows} == {"0", "pooled"})
    outcomes = []
    for index, name in enumerate(("Uniform", "Loaded"), start=1):
        seed_rows = sorted((r for r in rows if r["scheme"] == name and r["seed"] == "0"), key=lambda r: int(r["k"]))
        pooled_rows = sorted((r for r in rows if r["scheme"] == name and r["seed"] == "pooled"), key=lambda r: int(r["k"]))
        check(name+" has 24 unique carriers per layer", len(seed_rows) == len(pooled_rows) == 24 and [int(r["k"]) for r in seed_rows] == list(range(1,25)))
        check(name+" seed and pooled represent same data, never summed together", seed_rows == [dict(r, seed="0") for r in pooled_rows])
        bits = np.array([int(r["tested_bits"]) for r in seed_rows])
        errors = np.array([int(r["error_bits"]) for r in seed_rows])
        close(name+" tested bits from symbols x modulation", bits, 2000*np.log2(profiles[name]["M"]), 0)
        close(name+" CSV estimated SNR", np.array([float(r["SNR_est_dB"]) for r in seed_rows]), calibration["gamma_hat_dB"], 1e-12)
        close(name+" CSV modulation", np.array([int(r["M"]) for r in seed_rows]), profiles[name]["M"], 0)
        observed_ber = errors/bits
        close(name+" CSV BER from counts", np.array([float(r["BER"]) for r in seed_rows]), observed_ber, 1e-15)
        intervals = np.array([wilson(int(e), int(n)) for e,n in zip(errors,bits)])
        close(name+" CSV Wilson lower bounds", np.array([float(r["CI_low"]) for r in seed_rows]), intervals[:,0], 1e-15)
        close(name+" CSV Wilson upper bounds", np.array([float(r["CI_high"]) for r in seed_rows]), intervals[:,1], 1e-15)
        for run_label, data in (("runs",final["runs"]), ("smokeRuns",final["smokeRuns"]), ("checkpoint",partial["smokeRuns"])):
            run = next(r for r in data if r["scheme"] == name)
            check(name+" "+run_label+" is a 2000-symbol smoke run", run["phase"] == "smoke" and run["seed"] == 0 and run["symbols"] == 2000)
            close(name+" "+run_label+" bit counts", run["tested_bits"], bits, 0)
            close(name+" "+run_label+" errors", run["error_bits"], errors, 0)
        run = next(r for r in final["runs"] if r["scheme"] == name)
        row = summary[name]
        close(name+" summary bits (one layer only)", float(row["total_tested_bits"]), float(bits.sum()), 0)
        close(name+" summary errors", float(row["total_error_bits"]), float(errors.sum()), 0)
        close(name+" weighted total BER", float(row["total_BER"]), float(errors.sum()/bits.sum()), 1e-15)
        close(name+" summary worst carrier BER", float(row["worst_subcarrier_BER"]), float(observed_ber.max()), 1e-15)
        close(name+" summary maximum upper bound", float(row["maximum_CI_upper"]), float(intervals[:,1].max()), 1e-15)
        check(name+" summary remains smoke-only evidence", row["statistical_status"] == "smoke_only_not_formal_evidence")
        for field, expected in (("B",profiles[name]["B"]), ("R_payload",profiles[name]["R_payload"]),
                                ("test_symbols",2000), ("test_duration_s",2000*cfg["Ts"]),
                                ("initialization_symbols",3072), ("initialization_duration_s",3072*cfg["Ts"]),
                                ("mean_useful_energy",run["useful_energy_sum"]/2000),
                                ("mean_CP_energy",run["cp_energy_sum"]/2000),
                                ("mean_including_CP_power",run["total_energy_sum"]/2000/72),
                                ("mean_including_CP_symbol_energy",run["total_energy_sum"]/2000)):
            close(name+" summary consistency: "+field, float(row[field]), float(expected), max(1e-12,abs(expected)*1e-14))
        outcomes.append({"scheme": name, "scope": "uploaded historical smoke only", "symbols": 2000,
                         "B": int(profiles[name]["B"]), "R_payload_bit_s": float(profiles[name]["R_payload"]),
                         "tested_bits": int(bits.sum()), "error_bits": int(errors.sum()),
                         "observed_BER": float(errors.sum()/bits.sum()), "maximum_Wilson_upper": float(intervals[:,1].max())})

    seeds = read_csv("seed_mapping.csv")
    recorded = []
    for row in seeds:
        if row["stage"] in ("smoke", "main"):
            index = {"Uniform":1, "Loaded":2}[row["scheme"]]
            base = 300000 if row["stage"] == "smoke" else 100000
            tag = int(row["label"])
            check("preserved stream mapping "+row["stage"]+" "+row["scheme"]+" "+str(tag),
                  int(row["dataSeed"]) == base+1000*index+10*tag+1 and int(row["noiseSeed"]) == base+1000*index+10*tag+2)
        for field in ("dataSeed", "noiseSeed"):
            if row[field] != "NaN": recorded.append(int(row[field]))
    check("all recorded streams unique", len(recorded) == len(set(recorded)))
    return {
        "scope": "Consistency audit of user-uploaded historical MATLAB smoke artifacts; not cloud MATLAB execution or a new simulation.",
        "cloud_MATLAB_executed": False, "formal_main_completed": False,
        "original_files_preserved": len(manifest), "original_MATLAB_version": cfg["MATLABVersion"],
        "old_smoke_summaries": outcomes,
        "loaded_profile": {"k1_15": 64, "k16_21": 16, "k22_24": 4},
        "k21_estimated_SNR_dB": float(calibration["gamma_hat_dB"][20]),
        "k21_16QAM_BER_design_approximation": qam_ber(16, float(gamma_eff[20])),
        "fixed16_diagnostic": {
            "scope": "Approximate predictions from imported gamma_hat, NOT measured BER or main data.",
            "B": 96, "R_payload_bit_s": 96/cfg["Ts"],
            "nominal_predicted_above_target_k": [k+1 for k,v in enumerate(gamma) if qam_ber(16,float(v))>cfg["targetBER"]],
            "design_predicted_above_target_k": [k+1 for k,v in enumerate(gamma_eff) if qam_ber(16,float(v))>cfg["targetBER"]],
            "measured_BER": None},
        "mat_read_scope": "Selected numeric structs only; MATLAB table objects were not decoded. Seed mapping CSV lists planned main streams, not proof of main execution.",
        "checks": CHECKS,
    }


def main() -> None:
    report = audit()
    report["passed_checks"] = sum(r["status"] == "PASS" for r in CHECKS)
    report["failed_checks"] = sum(r["status"] == "FAIL" for r in CHECKS)
    folder = ROOT / "validation"
    folder.mkdir(exist_ok=True)
    (folder / "uploaded_smoke_audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    lines = ["# 上传的历史 smoke 结果一致性审计", "", "**当前云端未在 MATLAB 执行，main 未完成。** 本文仅复核用户上传的真实 MATLAB smoke 文件，不生成新的实验数据。", "",
             f"命令：`python3 tools/audit_uploaded_smoke.py`。{report['passed_checks']} 项一致性检查通过；14 个原始文件逐一匹配导入 SHA-256 与字节数。", "",
             "| 上传的历史方案 | DMT 符号 | B | 观察误码 / 测试比特 | 观察总 BER |", "| --- | ---: | ---: | ---: | ---: |"]
    for r in report["old_smoke_summaries"]:
        lines.append(f"| {r['scheme']} | {r['symbols']} | {r['B']} | {r['error_bits']} / {r['tested_bits']} | {r['observed_BER']:.9g} |")
    lines += ["", "旧 CSV 的 `seed=0` 与 `pooled` 是同一批计数，审计逐项核对一致，未将两层重复相加。旧 MAT 的 `runs` 与 `smokeRuns` 也记录同一批 smoke；main 种子映射只是一份计划表，不表示已执行。", "",
              "`config_snapshot.mat` 与 `final_results.mat` 的 cfg 完全匹配且 runMode 都是 smoke；初始化与最终 MAT 的全部保存校准/profile 一致。由保存探测残差重算 gamma_hat、由估计 SNR 和 1 dB 裕量重算 profile、CSV 的比特/误码/加权 BER/Wilson 区间及能量/时长口径均通过一致性检查。", "",
              f"Loaded 的实际冻结分配为 k1:15 的 64-QAM、k16:21 的 16-QAM 和 k22:24 的 QPSK，共 120 bits。k21 的估计 SNR 为 {report['k21_estimated_SNR_dB']:.9g} dB，其 16-QAM 保守近邻 BER 预测约 {report['k21_16QAM_BER_design_approximation']:.9g}；无需手调成解析示例的 118 bits。", "",
              "Fixed16 尚无实测数据。仅将上传 gamma_hat 代入近邻公式时，名义及保守预测中 k22:24 超过目标；这是解释用预测，不能当作正式 BER 或统计不合规证据。其 96 bits/符号与 85.3333 Mbit/s 只是 profile 的计数速率，不是经验证的可靠吞吐量。", "",
              "使用 SciPy 时只读取明确列出的数值结构；未解码 MATLAB table 对象。完整检查名、数值与容差见 `uploaded_smoke_audit.json`。此次文件一致性审计不能证明 v1.1 新代码已在 MATLAB 运行，不能替代三策略的固定 main。", ""]
    (folder / "uploaded_smoke_audit.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"Uploaded historical smoke audit: {report['passed_checks']} checks PASS; main_completed=False; cloud_MATLAB_executed=False")
    for r in report["old_smoke_summaries"]:
        print(r)
    print("k21 SNR dB:", report["k21_estimated_SNR_dB"])


if __name__ == "__main__":
    main()
