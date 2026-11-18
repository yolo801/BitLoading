#!/usr/bin/env python3
"""Approximate the two published 50 m magnitudes by real, causal FIRs."""

import argparse
import csv
import hashlib
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


FS_HZ = 128e9
NFFT = 512
ACTIVE_K = np.arange(1, 241)
ACTIVE_GHZ = ACTIVE_K * FS_HZ / NFFT / 1e9
MAX_INTERPOLATION_GAP_GHZ = 3.0
ORDERS = (9, 13, 17, 21, 25, 33, 41, 49, 65)
ACTIVE_RMS_LIMIT_DB = 1.0
NOTCH_DEPTH_TOLERANCE_DB = 1.0
NOTCH_LOCATION_TOLERANCE_GHZ = 2 * FS_HZ / NFFT / 1e9
NOTCH_WINDOW_GHZ = (15.0, 32.0)
RECOVERY_WINDOW_GHZ = (32.0, 53.0)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_csv(path, fields, rows):
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(fields)
        writer.writerows(rows)


def read_traces(path):
    with path.open(newline="", encoding="utf-8-sig") as stream:
        records = list(csv.DictReader(stream))
    traces = {}
    for case in (1, 2):
        series = np.array(
            [
                (float(row["frequency_GHz"]), float(row["gain_dB"]))
                for row in records
                if int(row["case"]) == case
            ],
            dtype=float,
        )
        if series.ndim != 2 or not len(series) or not np.isfinite(series).all():
            raise ValueError(f"Case {case} lacks finite vector coordinates")
        order = np.argsort(series[:, 0])
        frequency, levels = series[order].T
        unique, membership = np.unique(frequency, return_inverse=True)
        db = np.bincount(membership, weights=levels) / np.bincount(membership)
        if unique[0] > ACTIVE_GHZ[0] or unique[-1] < ACTIVE_GHZ[-1]:
            raise ValueError(f"Case {case} does not bracket the active DMT band")
        if abs(db[np.argmin(abs(unique))]) > 0.4:
            raise ValueError(f"Case {case} near-DC reference differs from nominal 0 dB")
        traces[case] = unique, db
    return traces


def reliable_interpolation(frequency, trace):
    x, y = trace
    right = np.searchsorted(x, frequency, side="left")
    i = np.clip(right, 1, len(x) - 1)
    between = (frequency >= x[0]) & (frequency <= x[-1])
    short_gap = x[i] - x[i - 1] <= MAX_INTERPOLATION_GAP_GHZ
    at_vertex = (frequency == x[i]) | (frequency == x[i - 1])
    valid = between & (short_gap | at_vertex)
    values = np.interp(frequency, x, y)
    return np.where(valid, values, np.nan)


def basis(frequency, half_length):
    angles = 2 * np.pi * np.asarray(frequency) / (FS_HZ / 1e9)
    return 2 * (np.cos(np.outer(angles, np.arange(1, half_length + 1))) - 1)


def dc_unity_taps(side):
    return np.r_[side[::-1], 1 - 2 * side.sum(), side]


def response(taps, frequency):
    half_length = len(taps) // 2
    return 1 + basis(frequency, half_length) @ taps[half_length + 1 :]


def db_response(taps, frequency):
    return 20 * np.log10(np.maximum(abs(response(taps, frequency)), np.finfo(float).tiny))


def rms(values):
    return float(np.sqrt(np.mean(np.square(values))))


def feature(frequency, db):
    notch_region = np.flatnonzero(
        (frequency >= NOTCH_WINDOW_GHZ[0]) & (frequency <= NOTCH_WINDOW_GHZ[1])
    )
    recovery_region = np.flatnonzero(
        (frequency >= RECOVERY_WINDOW_GHZ[0]) & (frequency <= RECOVERY_WINDOW_GHZ[1])
    )
    if np.any(~np.isfinite(db[np.r_[notch_region, recovery_region]])):
        raise ValueError("Incomplete digitized coverage in Case 2 notch/recovery windows")
    trough = notch_region[np.argmin(db[notch_region])]
    peak = recovery_region[np.argmax(db[recovery_region])]
    depth = db[trough]
    recovery = db[peak]
    half_level = (depth + recovery) / 2
    left = np.flatnonzero(db[:trough] >= half_level)
    right = np.flatnonzero(db[trough:peak + 1] >= half_level) + trough
    width = None
    if left.size and right.size and left[-1] < trough < right[0]:
        a, b = left[-1], right[0]
        x_left = np.interp(half_level, db[a:a + 2][::-1], frequency[a:a + 2][::-1])
        x_right = np.interp(half_level, db[b - 1:b + 1], frequency[b - 1:b + 1])
        width = float(x_right - x_left)
    return {
        "notch_GHz": float(frequency[trough]),
        "notch_dB": float(depth),
        "recovery_GHz": float(frequency[peak]),
        "recovery_dB": float(recovery),
        "recovery_rise_dB": float(recovery - depth),
        "half_rise_width_GHz": width,
        "notch_interior": bool(trough not in (notch_region[0], notch_region[-1])),
        "recovery_interior": bool(peak not in (recovery_region[0], recovery_region[-1])),
    }


def fit_candidate(case, count, active, fitted_frequencies, fitted_db, dense, observed_feature):
    target = 10 ** (fitted_db / 20)
    system = basis(fitted_frequencies, (count - 1) // 2)
    # Weight relative amplitude errors as the first-order equivalent of dB errors.
    side = np.linalg.lstsq(system / target[:, None], (target - 1) / target, rcond=None)[0]
    taps = dc_unity_taps(side)
    active_error = db_response(taps, ACTIVE_GHZ) - active
    fit_error = db_response(taps, fitted_frequencies) - fitted_db
    centered = response(taps, dense)
    slope_bound = 4 * np.pi / (FS_HZ / 1e9) * np.sum(abs(side) * np.arange(1, len(side) + 1))
    lower_bound = centered.min() - slope_bound * (dense[1] - dense[0]) / 2
    detail = {
        "case_id": case,
        "taps": taps.tolist(),
        "number_of_taps": count,
        "fir_memory_samples": count - 1,
        "group_delay_samples": (count - 1) // 2,
        "dc_gain": float(taps.sum()),
        "active_rms_error_dB": rms(active_error),
        "active_max_abs_error_dB": float(np.max(np.abs(active_error))),
        "fit_band_rms_error_dB": rms(fit_error),
        "fit_band_max_abs_error_dB": float(np.max(np.abs(fit_error))),
        "simulated_band_min_amplitude_lower_bound": float(lower_bound),
    }
    shape_ok = True
    if case == 2:
        f = feature(dense, db_response(taps, dense))
        delta_f = abs(f["notch_GHz"] - observed_feature["notch_GHz"])
        delta_depth = abs(f["notch_dB"] - observed_feature["notch_dB"])
        shape_ok = (
            f["notch_interior"] and f["recovery_interior"]
            and delta_f <= NOTCH_LOCATION_TOLERANCE_GHZ
            and delta_depth <= NOTCH_DEPTH_TOLERANCE_DB
            and f["half_rise_width_GHz"] is not None
            and f["recovery_rise_dB"] >= observed_feature["recovery_rise_dB"] - 1.0
        )
        detail.update(
            source_notch=observed_feature,
            fitted_notch=f,
            notch_frequency_error_GHz=delta_f,
            notch_depth_error_dB=delta_depth,
            notch_and_recovery_passed=bool(shape_ok),
        )
    detail["passed"] = bool(
        detail["active_rms_error_dB"] <= ACTIVE_RMS_LIMIT_DB and lower_bound > 0 and shape_ok
    )
    return detail


def measure_source(traces, dense):
    data = {case: reliable_interpolation(ACTIVE_GHZ, trace) for case, trace in traces.items()}
    if any(np.any(~np.isfinite(values)) for values in data.values()):
        raise ValueError("An active frequency falls outside a reliable digitized interval")
    active_features = feature(dense, reliable_interpolation(dense, traces[2]))
    width = active_features["half_rise_width_GHz"]
    if (
        not active_features["notch_interior"]
        or not active_features["recovery_interior"]
        or width is None
        or width < 4 * FS_HZ / NFFT / 1e9
        or active_features["recovery_rise_dB"] <= 2.0
    ):
        raise ValueError("The active tone spacing does not adequately resolve the source feature")
    return data, active_features


def plot(traces, cases, dense, path):
    colors = ("#004683", "#a73c12")
    plt.rcParams.update(
        {"font.size": 10, "svg.fonttype": "none", "svg.hashsalt": "fig2a-vcsel-2025"}
    )
    fig, axes = plt.subplots(2, 2, sharex=True, figsize=(8.7, 5.1),
                             gridspec_kw={"height_ratios": [2.0, 1.0]})
    fig.subplots_adjust(left=.105, right=.982, top=.88, bottom=.18, wspace=.25, hspace=.26)
    fig.suptitle("50 m VCSEL–MMF channel magnitude and FIR fit", fontweight="bold", y=.975)
    for j, fit in enumerate(cases):
        case = fit["case_id"]
        top, lower = axes[:, j]
        f, db = traces[case]
        taps = np.asarray(fit["taps"])
        mask = (f >= 0) & (f <= dense[-1])
        top.plot(f[mask], db[mask], ".", color=colors[j], markersize=2.6, label="Fig. 2(a) vector trace")
        top.plot(dense, db_response(taps, dense), color="#272727", lw=1.2, label="Equivalent FIR")
        top.set_title(f"Case {case} · {len(taps)} taps")
        top.set_ylim(-9.5, .8)
        if case == 2:
            for key, marker in (("notch", "v"), ("recovery", "^")):
                f0 = fit["source_notch"][key + "_GHz"]
                y0 = fit["source_notch"][key + "_dB"]
                top.scatter(f0, y0, marker=marker, color=colors[j], s=27, zorder=5)
                label = f"{key.capitalize()} {f0:.1f} GHz"
                top.annotate(label, (f0, y0), xytext=(0, 9 if key == "recovery" else -16),
                             textcoords="offset points", ha="center", color=colors[j], fontsize=9)
        top.legend(loc="lower left", fontsize=8, frameon=False)
        error = db_response(taps, ACTIVE_GHZ) - reliable_interpolation(ACTIVE_GHZ, traces[case])
        lower.plot(ACTIVE_GHZ, error, color=colors[j], lw=1.25)
        lower.axhline(0, color="#424242", lw=.7)
        lower.set_xlabel("Physical frequency (GHz)")
        lower.set_title(f"Active RMS: {fit['active_rms_error_dB']:.3f} dB", pad=5, fontsize=9)
        for ax in (top, lower):
            ax.axvspan(ACTIVE_GHZ[0], ACTIVE_GHZ[-1], color="#dfeaf3", alpha=.43, zorder=-5)
            ax.grid(color="#ddd", linewidth=.5)
            ax.set_xlim(0, 64)
    axes[0, 0].set_ylabel("Normalized magnitude (dB)")
    axes[1, 0].set_ylabel("Fit − source (dB)")
    fig.text(.5, .045,
             "Shading marks the common active band. Source: Rosa Brusin et al., SPPCom 2025, Fig. 2(a).",
             ha="center", fontsize=9)
    fig.savefig(path / "Fig2a_Channel_Fit.png", dpi=320, facecolor="white")
    svg = path / "Fig2a_Channel_Fit.svg"
    fig.savefig(svg, facecolor="white", metadata={"Date": None})
    svg.write_text("\n".join(row.rstrip() for row in svg.read_text().splitlines()) + "\n", encoding="utf-8")
    plt.close(fig)


def fit(evidence):
    trace_path = evidence / "Fig2a_digitized.csv"
    provenance = evidence / "Fig2a_provenance.json"
    traces = read_traces(trace_path)
    dense = np.linspace(0, FS_HZ / 2e9, 5121)
    active, source_feature = measure_source(traces, dense)
    summary = []
    all_candidates = []
    for case, trace in traces.items():
        extended = reliable_interpolation(dense, trace)
        fit_mask = np.isfinite(extended)
        candidates = [
            fit_candidate(case, count, active[case], dense[fit_mask], extended[fit_mask],
                          dense, source_feature)
            for count in ORDERS
        ]
        all_candidates += candidates
        best = next((trial for trial in candidates if trial["passed"]), None)
        if best is None:
            best = min(candidates, key=lambda trial: trial["active_rms_error_dB"])
        summary.append(best)
    cp = max(c["fir_memory_samples"] for c in summary)
    common_pass = all(c["passed"] for c in summary)
    case2 = summary[1]
    shape = {}
    for role, values in (("source", source_feature), ("fit", case2["fitted_notch"])):
        shape.update({f"{role}_{field}": value for field, value in values.items()})
    result = {
        "schema": "dmt-vcsel-mmf-channel-fit-v1",
        "source_DOI": "10.1364/SPPCOM.2025.SpTh3E.4",
        "source_figure": "Fig. 2(a), supplied public PDF page 3",
        "source_csv": trace_path.name,
        "digitized_sha256": sha(trace_path),
        "source_provenance": provenance.name,
        "provenance_sha256": sha(provenance),
        "Fs_Hz": int(FS_HZ),
        "NFFT": NFFT,
        "NCP": cp,
        "active_k": ACTIVE_K.tolist(),
        "active_band_GHz": [float(ACTIVE_GHZ[0]), float(ACTIVE_GHZ[-1])],
        "active_tone_spacing_GHz": FS_HZ / NFFT / 1e9,
        "near_dc_normalization": "Published normalized dB is used as plotted. Each FIR has unity DC gain.",
        "fit_method": "Odd symmetric real FIR, relative-amplitude weighted least squares, minimum passing tested length per case.",
        "phase_assumption": "Linear phase (causal integer group delay). Magnitude-only source supplies no phase.",
        "frequency_mapping": "Physical frequency in GHz from public figure with 128 GS/s sample rate; its 64 GHz Nyquist limit bounds the model.",
        "guard_reason": "Use the same 0.25 to 60 GHz active band for both cases; tones above 60 GHz and the Nyquist bin are guard bins.",
        "notch_half_rise_width_definition": "Distance between crossings at halfway between notch minimum and its next recovery peak, in dB.",
        "max_source_interpolation_gap_GHz": MAX_INTERPOLATION_GAP_GHZ,
        "active_rms_limit_dB": ACTIVE_RMS_LIMIT_DB,
        "notch_frequency_tolerance_GHz": NOTCH_LOCATION_TOLERANCE_GHZ,
        "notch_depth_tolerance_dB": NOTCH_DEPTH_TOLERANCE_DB,
        "passed": common_pass,
        "cases": summary,
        "case2_features": shape,
    }
    write_csv(
        evidence / "FIR_taps.csv", ("case_id", "tap_index", "tap"),
        [(c["case_id"], i, v) for c in summary for i, v in enumerate(c["taps"])],
    )
    active_rows = []
    full_rows = []
    for c in summary:
        case = c["case_id"]
        taps = np.array(c["taps"])
        model = db_response(taps, ACTIVE_GHZ)
        active_rows.extend(zip(np.full(len(ACTIVE_K), case), ACTIVE_K, ACTIVE_GHZ,
                               active[case], model, model - active[case]))
        f = dense[np.isfinite(reliable_interpolation(dense, traces[case]))]
        source = reliable_interpolation(f, traces[case])
        model = db_response(taps, f)
        full_rows.extend(zip(np.full(len(f), case), f, source, model, model - source))
    active_response = evidence / "active_response.csv"
    write_csv(active_response,
              ("case_id", "k", "frequency_GHz", "source_dB", "fit_dB", "residual_dB"), active_rows)
    result["active_response_sha256"] = sha(active_response)
    write_csv(evidence / "covered_response_fit.csv",
              ("case_id", "frequency_GHz", "source_dB", "fit_dB", "residual_dB"), full_rows)
    fields = ("case_id", "number_of_taps", "active_rms_error_dB", "active_max_abs_error_dB",
              "fit_band_rms_error_dB", "fit_band_max_abs_error_dB",
              "simulated_band_min_amplitude_lower_bound", "notch_frequency_error_GHz",
              "notch_depth_error_dB", "notch_and_recovery_passed", "passed")
    write_csv(evidence / "fir_candidate_audit.csv", fields,
              [[c.get(field, "") for field in fields] for c in all_candidates])
    plot(traces, summary, dense, evidence)
    (evidence / "channel_fit.json").write_text(
        json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8"
    )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", type=Path,
                        default=Path(__file__).resolve().parent.parent / "evidence")
    path = parser.parse_args().evidence_dir
    result = fit(path)
    print(f"FIR fit gate: {result['passed']}, FFT {NFFT}, CP {result['NCP']} samples, "
          f"{len(ACTIVE_K)} active tones.")
    for case in result["cases"]:
        print(f"Case {case['case_id']}: {case['number_of_taps']} taps, "
              f"active RMS {case['active_rms_error_dB']:.4f} dB, gate {case['passed']}.")


if __name__ == "__main__":
    main()
