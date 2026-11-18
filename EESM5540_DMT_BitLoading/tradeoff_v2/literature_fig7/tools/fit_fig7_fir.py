#!/usr/bin/env python3
"""Fit and plot an equivalent FIR using the extracted Fig. 7 magnitude only."""

import argparse
import csv
import hashlib
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from numpy.polynomial import Chebyshev
from scipy.optimize import LinearConstraint, NonlinearConstraint, brentq, minimize


FS_SIM_MHZ = 64.0
FS_PAPER_GHZ = 63.0
CP_SAMPLES = 8
CARRIERS = np.arange(1, 25)
ACTIVE_RMS_DB = 1.0
ACTIVE_MAX_DB = 2.0
ORIGINAL_H = np.array([0.25, 0.5, 0.25])
FIG7_FILE = "Fig7_digitized.csv"
PROVENANCE_FILE = "Fig7_provenance.json"


def sim_frequency(paper_ghz):
    return paper_ghz * FS_SIM_MHZ / FS_PAPER_GHZ


def response_db(taps, paper_ghz):
    theta = 2 * np.pi * np.asarray(paper_ghz) / FS_PAPER_GHZ
    response = np.exp(-1j * np.outer(theta, np.arange(len(taps)))) @ taps
    # A true zero, such as the original channel at Nyquist, has -inf dB gain.
    with np.errstate(divide="ignore"):
        return 20 * np.log10(np.abs(response))


def cosine_basis(paper_ghz, half_order):
    theta = 2 * np.pi * np.asarray(paper_ghz) / FS_PAPER_GHZ
    distances = np.arange(1, half_order + 1)
    # The center tap is chosen so that the zero-phase response equals 1 at DC.
    return 2 * (np.cos(np.outer(theta, distances)) - 1)


def symmetric_taps(side_taps):
    return np.r_[side_taps[::-1], 1 - 2 * np.sum(side_taps), side_taps]


def band_extrema(taps, lower_ghz, upper_ghz):
    """Evaluate every stationary point of the continuous zero-phase response."""
    center = len(taps) // 2
    coefficients = np.r_[taps[center], 2 * taps[center + 1 :]]
    polynomial = Chebyshev(coefficients)
    x_low, x_high = np.cos(2 * np.pi * np.array([upper_ghz, lower_ghz]) / FS_PAPER_GHZ)
    roots = polynomial.deriv().roots()
    real_roots = roots.real[np.isclose(roots.imag, 0, atol=1e-12)]
    interior = real_roots[(x_low < real_roots) & (real_roots < x_high)]
    candidates = np.r_[x_low, interior, x_high]
    amplitude = polynomial(candidates)
    index = np.argmin(amplitude)
    frequency = FS_PAPER_GHZ * np.arccos(candidates[index]) / (2 * np.pi)
    return float(amplitude[index]), float(frequency)


def db_error_stats(errors):
    return float(np.sqrt(np.mean(errors**2))), float(np.max(np.abs(errors)))


def fit_candidate(half_order, paper_ghz, measured_db, active_ghz, active_target):
    active_basis = cosine_basis(active_ghz, half_order)
    full_basis = cosine_basis(paper_ghz, half_order)
    positivity_grid = np.linspace(0, paper_ghz[-1], 2001)
    positivity_basis = cosine_basis(positivity_grid, half_order)

    def mse_and_grad(side, basis, target):
        amplitude = np.maximum(1 + basis @ side, 1e-9)
        error = 20 * np.log10(amplitude) - target
        gradient = 40 / np.log(10) * (error / amplitude) @ basis / len(error)
        return np.mean(error**2), gradient

    # Small numerical slack toward the interior avoids roundoff at a hard gate.
    active_limit = ACTIVE_MAX_DB - 1e-7
    max_lower = 10 ** ((active_target - active_limit) / 20) - 1
    max_upper = 10 ** ((active_target + active_limit) / 20) - 1
    positivity = LinearConstraint(positivity_basis, -1 + 1e-5, np.inf)
    active_bounds = LinearConstraint(active_basis, max_lower, max_upper)
    rms_constraint = NonlinearConstraint(
        lambda side: mse_and_grad(side, active_basis, active_target)[0],
        0,
        (ACTIVE_RMS_DB - 1e-7) ** 2,
        jac=lambda side: mse_and_grad(side, active_basis, active_target)[1],
    )
    seed = np.linalg.lstsq(full_basis, 10 ** (measured_db / 20) - 1, rcond=None)[0]
    solution = minimize(
        mse_and_grad,
        seed,
        args=(full_basis, measured_db),
        jac=True,
        method="SLSQP",
        constraints=[positivity, active_bounds, rms_constraint],
        options={"ftol": 1e-12, "maxiter": 500},
    )
    if not solution.success:
        # Preserve a useful active-band error diagnostic if the constrained fit fails.
        fallback = minimize(
            mse_and_grad,
            np.zeros(half_order),
            args=(active_basis, active_target),
            jac=True,
            method="SLSQP",
            constraints=[positivity],
            options={"ftol": 1e-12, "maxiter": 500},
        )
        side_taps = fallback.x
    else:
        side_taps = solution.x
    taps = symmetric_taps(side_taps)
    active_rms, active_max = db_error_stats(response_db(taps, active_ghz) - active_target)
    covered_rms, covered_max = db_error_stats(response_db(taps, paper_ghz) - measured_db)
    min_amplitude, min_ghz = band_extrema(taps, active_ghz[0], active_ghz[-1])
    model_min, _ = band_extrema(taps, 0, paper_ghz[-1])
    passes = (
        active_rms <= ACTIVE_RMS_DB
        and active_max <= ACTIVE_MAX_DB
        and min_amplitude > 0
        and model_min > 0
    )
    return {
        "tap_count": len(taps),
        "taps": taps.tolist(),
        "passed": passes,
        "constrained_solver_success": bool(solution.success),
        "constrained_solver_message": str(solution.message),
        "active_rms_error_dB": active_rms,
        "active_max_abs_error_dB": active_max,
        "covered_rms_error_dB": covered_rms,
        "covered_max_abs_error_dB": covered_max,
        "active_band_min_zero_phase_amplitude": min_amplitude,
        "active_band_min_frequency_GHz": min_ghz,
        "active_band_min_gain_dB": float(20 * np.log10(min_amplitude))
        if min_amplitude > 0
        else None,
        "dc_to_coverage_end_min_zero_phase_amplitude": model_min,
    }


def first_downcrossing(freq_ghz, values_db):
    """Return the first downward -3 dB crossing bracket, or None."""
    hits = np.flatnonzero((values_db[:-1] > -3) & (values_db[1:] <= -3))
    return (freq_ghz[hits[0]], freq_ghz[hits[0] + 1]) if hits.size else None


def bandwidth_summary(paper_ghz, measured_db, taps):
    bracket = first_downcrossing(paper_ghz, measured_db)
    measured = (
        brentq(lambda f: np.interp(f, paper_ghz, measured_db) + 3, *bracket)
        if bracket
        else None
    )
    grid = np.linspace(0, FS_PAPER_GHZ / 2, 4001)
    summary = {"definition": "First downward crossing of -3 dB relative to low-frequency/DC reference"}
    for key, model in (("fig7", None), ("original_FIR", ORIGINAL_H), ("fig7_FIR", taps)):
        crossing = measured
        if model is not None:
            bracket = first_downcrossing(grid, response_db(model, grid))
            crossing = (
                brentq(lambda f: response_db(model, [f])[0] + 3, *bracket)
                if bracket
                else None
            )
        summary[key] = {
            "frequency_GHz": crossing,
            "frequency_sim_MHz": sim_frequency(crossing) if crossing is not None else None,
        }
    return summary


def write_columns(path, fields, rows):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(fields)
        writer.writerows(rows)


def write_response_tables(output, paper_ghz, measured_db, active_ghz, target, taps):
    columns = (
        "frequency_GHz",
        "frequency_sim_MHz",
        "fig7_normalized_dB",
        "original_FIR_dB",
        "new_FIR_dB",
        "new_FIR_minus_fig7_dB",
    )
    for path, frequencies, source in [
        ("covered_frequency_response.csv", paper_ghz, measured_db),
        ("active_subcarrier_response.csv", active_ghz, target),
    ]:
        original_db = response_db(ORIGINAL_H, frequencies)
        fit_db = response_db(taps, frequencies)
        values = (frequencies, sim_frequency(frequencies), source, original_db, fit_db, fit_db - source)
        if path.startswith("active_"):
            write_columns(output / path, ("subcarrier_k", *columns), zip(CARRIERS, *values))
        else:
            write_columns(output / path, columns, zip(*values))


def draw_comparison(output, paper_ghz, measured_db, active_ghz, target, taps, summary):
    plt.rcParams.update(
        {
            "font.size": 10, "axes.labelsize": 10, "axes.titlesize": 11,
            "svg.fonttype": "none", "svg.hashsalt": "dmt-tradeoff-v2-fig7",
        }
    )
    fig, axes = plt.subplots(
        2, 1, sharex=True, figsize=(8.0, 5.25),
        gridspec_kw={"height_ratios": [1.6, 1.0]}, layout="constrained",
    )
    magnitude, residual = axes
    fig.suptitle("Channel response comparison")
    for ax in axes:
        ax.axvspan(1, 24, color="#e8f2f3", alpha=0.75, lw=0)
        ax.grid(axis="y", color="#a8a8a8", lw=0.5, alpha=0.55)
        ax.set_axisbelow(True)
        ax.spines[["top", "right"]].set_visible(False)
    grid = np.linspace(0, paper_ghz[-1], 1001)
    magnitude.plot(
        sim_frequency(paper_ghz), measured_db, ".", ms=2.4, color="#145b8c",
        label="Zhong et al. (2015), Fig. 7",
    )
    magnitude.plot(
        sim_frequency(grid), response_db(ORIGINAL_H, grid), "--", color="#444444",
        lw=1.5, label="Original 3-tap FIR",
    )
    magnitude.plot(
        sim_frequency(grid), response_db(taps, grid), color="#ae4519", lw=1.7,
        label=f"Fig. 7 equivalent FIR ({len(taps)} taps)",
    )
    magnitude.set_ylabel("Relative magnitude (dB)")
    magnitude.legend(loc="lower left", fontsize=9, framealpha=0.95)
    paper_scale = magnitude.secondary_xaxis(
        "top",
        functions=(lambda sim_mhz: sim_mhz * FS_PAPER_GHZ / FS_SIM_MHZ, sim_frequency),
    )
    paper_scale.set_xlabel("Paper frequency (GHz)")
    residual.plot(
        sim_frequency(paper_ghz), response_db(taps, paper_ghz) - measured_db,
        color="#ae4519", lw=1.0, label="All digitized frequencies",
    )
    residual.scatter(
        sim_frequency(active_ghz), response_db(taps, active_ghz) - target,
        s=14, color="#7b2c10", zorder=4, label="24 active subcarriers",
    )
    residual.axhline(0, color="#444444", lw=0.65)
    residual.hlines([-ACTIVE_MAX_DB, ACTIVE_MAX_DB], 1, 24, color="#4c6970", lw=0.8, ls="--")
    residual.set_xlabel("Simulation frequency (MHz)")
    residual.set_ylabel("Fit minus Fig. 7 (dB)")
    residual.legend(loc="upper left", fontsize=9, ncols=2, framealpha=0.96)
    rms = summary["active_rms_error_dB"]
    peak = summary["active_max_abs_error_dB"]
    residual.set_title(f"Active-carrier error   RMS {rms:.2f} dB   |   Maximum {peak:.2f} dB", loc="left")
    residual.set_xlim(0, sim_frequency(paper_ghz[-1]) + 0.12)
    fig.savefig(output / "Channel_Response_Comparison.png", dpi=300, facecolor="white")
    svg_path = output / "Channel_Response_Comparison.svg"
    fig.savefig(svg_path, facecolor="white", metadata={"Date": None})
    svg = svg_path.read_text(encoding="utf-8")
    svg_path.write_text(
        "\n".join(line.rstrip() for line in svg.splitlines()) + "\n",
        encoding="utf-8",
    )
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", type=Path, default=Path(__file__).resolve().parents[1] / "evidence")
    args = parser.parse_args()
    output = args.evidence_dir
    source = output / FIG7_FILE
    metadata = output / PROVENANCE_FILE
    data = np.genfromtxt(source, delimiter=",", names=True, encoding="utf-8")
    paper_ghz = data["frequency_GHz"]
    measured_db = data["normalized_dB"]
    if not np.all(np.isfinite(paper_ghz)) or not np.all(np.isfinite(measured_db)):
        raise ValueError("Fig. 7 extraction contains nonfinite coordinates")
    if np.any(np.diff(paper_ghz) <= 0) or paper_ghz[0] < 0 or paper_ghz[-1] > FS_PAPER_GHZ / 2:
        raise ValueError("Fig. 7 frequencies must increase within the paper transmitter Nyquist band")
    if not np.allclose(data["amplitude_ratio"], 10 ** (measured_db / 20), rtol=1e-6):
        raise ValueError("Extracted normalized amplitude disagrees with the dB column")
    if not np.allclose(data["frequency_sim_MHz"], sim_frequency(paper_ghz), atol=1e-7):
        raise ValueError("Extracted frequencies disagree with the transmitter sampling-rate mapping")
    active_ghz = CARRIERS * FS_PAPER_GHZ / FS_SIM_MHZ
    summary = {
        "digitized_file": FIG7_FILE,
        "provenance_file": PROVENANCE_FILE,
        "digitized_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "provenance_sha256": hashlib.sha256(metadata.read_bytes()).hexdigest(),
        "coverage_GHz": [float(paper_ghz[0]), float(paper_ghz[-1])],
        "coverage_sim_MHz": sim_frequency(paper_ghz[[0, -1]]).tolist(),
        "predicted_paper_17GHz_sim_MHz": sim_frequency(17),
        "active_frequency_GHz": active_ghz.tolist(),
        "active_rms_limit_dB": ACTIVE_RMS_DB,
        "active_max_abs_limit_dB": ACTIVE_MAX_DB,
    }
    summary_file = output / "fit_summary.json"
    if paper_ghz[0] > active_ghz[0] or paper_ghz[-1] < active_ghz[-1]:
        summary.update(passed=False, failure="The extracted frequency range misses an active carrier.")
        summary_file.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        raise SystemExit(summary["failure"])
    target = np.interp(active_ghz, paper_ghz, measured_db)
    candidates = [
        fit_candidate(half_order, paper_ghz, measured_db, active_ghz, target)
        for half_order in range(1, CP_SAMPLES // 2 + 1)
    ]
    passing = [candidate for candidate in candidates if candidate["passed"]]
    if passing:
        chosen = min(passing, key=lambda candidate: candidate["covered_rms_error_dB"])
    else:
        chosen = min(candidates, key=lambda candidate: candidate["active_rms_error_dB"])
    taps = np.array(chosen["taps"])
    summary.update(chosen)
    summary.update(
        fs_sim_MHz=FS_SIM_MHZ,
        fs_paper_GSa_per_s=FS_PAPER_GHZ,
        cp_samples=CP_SAMPLES,
        dc_gain=float(taps.sum()),
        group_delay_samples=len(taps) // 2,
        fit_method=(
            "Symmetric real FIR with unity DC. Minimize covered sample squared dB error "
            "subject to the active dB gates; choose the lowest covered RMS passing order. "
            "Use linear interpolation in digitized relative dB for active targets."
        ),
        phase_assumption="The symmetric causal FIR assumes linear phase; Fig. 7 supplies no phase.",
        band_edge={
            "frequency_GHz": float(active_ghz[-1]),
            "frequency_sim_MHz": int(CARRIERS[-1]),
            "fig7_dB": float(target[-1]),
            "original_FIR_dB": float(response_db(ORIGINAL_H, active_ghz[-1:])[0]),
            "new_FIR_dB": float(response_db(taps, active_ghz[-1:])[0]),
        },
        bandwidth=bandwidth_summary(paper_ghz, measured_db, taps),
    )
    if not passing:
        summary["failure"] = "No fitted symmetric FIR within the CP met the engineering gate."
    summary_file.write_text(json.dumps(summary, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    write_columns(output / "FIR_coefficients.csv", ("tap_index_n", "h"), enumerate(taps))
    candidate_fields = tuple(key for key in chosen if key != "taps")
    write_columns(
        output / "fit_order_candidates.csv", candidate_fields,
        ([candidate[key] for key in candidate_fields] for candidate in candidates),
    )
    write_response_tables(output, paper_ghz, measured_db, active_ghz, target, taps)
    draw_comparison(output, paper_ghz, measured_db, active_ghz, target, taps, summary)
    if not passing:
        raise SystemExit(summary["failure"])
    print(
        f"{len(taps)} taps. Active RMS {summary['active_rms_error_dB']:.4f} dB, "
        f"maximum {summary['active_max_abs_error_dB']:.4f} dB. Results in {output.resolve()}"
    )


if __name__ == "__main__":
    main()
