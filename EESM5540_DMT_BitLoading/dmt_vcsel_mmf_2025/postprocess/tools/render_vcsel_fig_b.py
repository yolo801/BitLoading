#!/usr/bin/env python3
"""Render Figure B from the saved formal calibration, without simulation."""

import argparse
import csv
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.lines import Line2D
from matplotlib.ticker import LogLocator


STRATEGIES = (
    ("UniformValidated", "Uniform validated", "#205d95"),
    ("PerToneValidated", "Per-tone validated", "#aa491d"),
)
CASE_ID, SWING, ADC_BITS, CALIBRATION = 2, 0.50, 8, 1
BER_TARGET = 1e-3
STEM = "fig_B_frequency_selectivity"


def require(condition, explanation):
    if not condition:
        raise ValueError(explanation)


def read_point(folder, name):
    with (folder / f"{name}.csv").open(newline="", encoding="utf-8-sig") as handle:
        return [
            row for row in csv.DictReader(handle)
            if row["phase"] == "formal"
            and int(row["case_id"]) == CASE_ID
            and float(row["swing"]) == SWING
            and int(row["q"]) == ADC_BITS
            and int(row["calibration_id"]) == CALIBRATION
            and float(row["P_target"]) == 1.0
        ]


def column(rows, key, cast=float):
    return np.array([cast(row[key]) for row in rows])


def sorted_tones(rows, grid, frequency):
    rows = sorted(rows, key=lambda row: int(row["k"]))
    require(np.array_equal(column(rows, "k", int), grid), "Expected one row per active tone.")
    require(np.allclose(column(rows, "frequency_GHz"), frequency, rtol=0, atol=1e-10),
            "Active-tone frequencies differ from the frozen model.")
    return rows


def wilson(errors, tested):
    estimate = errors / tested
    z = 1.96
    denominator = 1 + z*z/tested
    center = (estimate + z*z/(2*tested))/denominator
    radius = z*np.sqrt(estimate*(1-estimate)/tested + z*z/(4*tested*tested))/denominator
    return estimate, np.maximum(center-radius, 0), np.minimum(center+radius, 1)


def read_data(folder):
    fit = json.loads((folder / "channel_evidence/channel_fit.json").read_text(encoding="utf-8"))
    grid = np.asarray(fit["active_k"], dtype=int)
    frequency = grid * (fit["Fs_Hz"] / fit["NFFT"] / 1e9)
    spacing = fit["Fs_Hz"] / fit["NFFT"] / 1e9
    notch = fit["case2_features"]["source_notch_GHz"]
    require(fit["passed"] and frequency[0] < notch < frequency[-1],
            "The validated source-curve notch is outside the active band.")
    plots = {}
    snr_rows = read_point(folder, "snr")
    require(all(row["strategy"] == "Shared" for row in snr_rows),
            "Expected only the shared independent B0 probe.")
    snr_rows = sorted_tones(snr_rows, grid, frequency)
    quality = column(snr_rows, "gamma_B0")
    snr = column(snr_rows, "SNR_dB")
    require(np.all(quality > 0) and np.allclose(snr, 10*np.log10(quality), rtol=0, atol=1e-10),
            "Probe SNR does not agree with the stored effective quality.")

    arrays = {name: read_point(folder, name) for name in ("summary", "profiles", "pool", "status")}
    for name, _, _ in STRATEGIES:
        summary = [row for row in arrays["summary"] if row["strategy"] == name]
        require(len(summary) == 1, f"Expected one formal summary for {name}.")
        summary = summary[0]
        state = summary["state"].replace("_", " ")
        profile = [row for row in arrays["profiles"] if row["strategy"] == name]
        pooled = [row for row in arrays["pool"] if row["strategy"] == name]
        slots = [row for row in arrays["status"] if row["strategy"] == name]
        require(sorted(int(row["payload_slot"]) for row in slots) == [1, 2],
                f"Expected exactly two planned payload slots for {name}.")
        complete = [row for row in slots if row["status"] == "completed"]
        require(len(complete) == int(summary["payload_slots_completed"]),
                f"Payload status conflicts with summary for {name}.")
        profile_bits = None
        ber = None
        if profile:
            profile = sorted_tones(profile, grid, frequency)
            order = column(profile, "M", int)
            profile_bits = column(profile, "bits_k", int)
            require(np.all(np.isin(order, (4, 16, 64)))
                    and np.array_equal(profile_bits, np.log2(order))
                    and all(row["configuration_hash"] == summary["configuration_hash"] for row in profile),
                    f"The modulation table or configuration identity differs for {name}.")
        if pooled:
            require(profile_bits is not None and len(complete) == 2
                    and all(int(row["actual_symbols"]) == 25000 for row in complete),
                    f"Pooled BER for {name} requires two complete formal payloads and a saved table.")
            pooled = sorted_tones(pooled, grid, frequency)
            errors = column(pooled, "error_bits", int)
            tested = column(pooled, "tested_bits", int)
            require(np.all(column(pooled, "actual_symbols", int) == 50000)
                    and np.array_equal(tested, 50000*profile_bits)
                    and np.array_equal(column(pooled, "M", int), order)
                    and np.all((0 <= errors) & (errors <= tested))
                    and errors.sum() == sum(int(row["error_bits"]) for row in complete)
                    and tested.sum() == sum(int(row["tested_bits"]) for row in complete)
                    and all(row["configuration_hash"] == summary["configuration_hash"] for row in pooled + complete),
                    f"Invalid or conflicting formal bit counters for {name}.")
            observed, lower, upper = wilson(errors, tested)
            require(all(np.allclose(expected, column(pooled, source), rtol=0, atol=1e-13)
                        for expected, source in ((observed, "BER"), (lower, "CI_low"), (upper, "CI_high"))),
                    f"Saved Wilson intervals disagree with the formal counts for {name}.")
            ber = (errors > 0, observed, lower, upper)
        else:
            require(len(complete) < 2, f"Complete payloads have no pooled counts for {name}.")
        plots[name] = (state, profile_bits, ber)
    return frequency, spacing, notch, snr, plots


def render(folder, output):
    frequency, spacing, notch, snr, plots = read_data(folder)
    plt.rcParams.update({
        "font.family": "DejaVu Sans",
        "font.size": 10,
        "text.color": "#202934",
        "axes.labelcolor": "#202934",
        "axes.edgecolor": "#aeb8c2",
        "xtick.color": "#202934",
        "ytick.color": "#202934",
        "pdf.fonttype": 42,
    })
    fig, (probe, loading, observed) = plt.subplots(
        3, 1, sharex=True, figsize=(8.4, 7.9), gridspec_kw={"height_ratios": [1, 1, 1.65]},
    )
    fig.subplots_adjust(left=.12, right=.97, top=.875, bottom=.18, hspace=.37)
    fig.text(.12, .981, "How Frequency Selectivity Changes Bit Allocation",
             ha="left", va="top", fontweight="bold", fontsize=18)
    fig.text(.12, .935, "Case 2  |  Commanded swing 0.50  |  8-bit ADC  |  Formal calibration 1",
             ha="left", va="top", fontsize=10.3, color="#475667")

    probe.plot(frequency, snr, color="#273a4e", linewidth=1.25)
    probe.set_title("Shared B0 probe", loc="left", fontweight="bold", fontsize=11, pad=8)
    probe.set_ylabel("Effective SNR (dB)")
    probe.text(.98, .10, f"Source-curve notch at {notch:.2f} GHz", transform=probe.transAxes,
               ha="right", va="bottom", fontsize=8.4, color="#475667",
               bbox={"facecolor": "white", "edgecolor": "none", "alpha": .9, "pad": 2})
    loading.set_title("Frozen modulation profiles", loc="left", fontweight="bold", fontsize=11, pad=8)
    loading.set_ylabel("Bits per subcarrier")
    loading.set_yticks([2, 4, 6])
    loading.set_ylim(1.55, 6.45)
    observed.set_title("Observed BER and pointwise 95% Wilson intervals",
                       loc="left", fontweight="bold", fontsize=11, pad=8)
    observed.set_ylabel("Observed BER")
    observed.set_xlabel("Physical frequency (GHz)")
    observed.set_yscale("log")
    observed.yaxis.set_major_locator(LogLocator(base=10))
    observed.axhline(BER_TARGET, color="#475667", linestyle=(0, (2, 3)), linewidth=.95, zorder=1)
    observed.text(.013, BER_TARGET, r"BER target $10^{-3}$", transform=observed.get_yaxis_transform(),
                  ha="left", va="bottom", fontsize=8.6, color="#475667")
    lowest, highest = BER_TARGET/12, BER_TARGET
    missing_profiles, missing_ber = [], []
    for i, (strategy, label, color) in enumerate(STRATEGIES):
        state, profile, ber = plots[strategy]
        if profile is not None:
            loading.step(frequency, profile, where="mid", color=color,
                         linestyle=(0, (4, 2)) if i == 0 else "-", linewidth=1.55, label=label,
                         zorder=4 if i == 0 else 3)
        else:
            missing_profiles.append(f"{label} ({state})")
        if ber is not None:
            nonzero, value, low, high = ber
            if np.any(nonzero):
                observed.errorbar(frequency[nonzero], value[nonzero],
                                  yerr=np.array([value[nonzero]-low[nonzero], high[nonzero]-value[nonzero]]),
                                  fmt="o", linestyle="none", color=color, markersize=2.2,
                                  capsize=1.0, elinewidth=.53, capthick=.56, alpha=.86, zorder=3)
                lowest = min(lowest, np.min(low[nonzero]))
            zero = ~nonzero
            if np.any(zero):
                observed.plot(frequency[zero], high[zero], linestyle="none", marker="v",
                              markerfacecolor="white", markeredgecolor=color, markeredgewidth=.55,
                              markersize=2.85 if i == 0 else 2.35, alpha=.8, zorder=2+i)
                lowest = min(lowest, np.min(high[zero]))
            highest = max(highest, np.max(high))
        else:
            missing_ber.append(f"{label} ({state})")
    if loading.get_legend_handles_labels()[0]:
        loading.legend(loc="upper right", frameon=False, ncols=2, fontsize=8)
    for axes, missing in ((loading, missing_profiles), (observed, missing_ber)):
        if missing:
            axes.text(.018, .09, "\n".join(missing), transform=axes.transAxes, va="bottom",
                      fontsize=9, color="#475667", bbox={"facecolor": "white", "edgecolor": "none"})
    observed.set_ylim(.6*lowest, 1.9*highest)

    for axes in (probe, loading, observed):
        axes.set_axisbelow(True)
        axes.grid(axis="both", color="#e3e8ec", linewidth=.65)
        axes.axvline(notch, color="#6b7a87", linestyle=(0, (4, 3)), linewidth=1.0, zorder=1.5)
        axes.spines[["top", "right"]].set_visible(False)
        axes.tick_params(length=2.4)
        axes.set_xlim(frequency[0]-.5*spacing, frequency[-1]+.5*spacing)
    legend = [
        Line2D([0], [0], color=color, linewidth=1.8, label=label)
        for _, label, color in STRATEGIES
    ]
    legend += [
        Line2D([0], [0], marker="v", markerfacecolor="white", color="#475667", markersize=5,
               linestyle="none", label="Zero errors shown at the Wilson upper bound"),
    ]
    fig.legend(handles=legend, loc="lower left", bbox_to_anchor=(.115, .075),
               ncols=3, frameon=False, fontsize=8.4, columnspacing=1.15, handletextpad=.35)
    fig.text(.12, .055, "Intervals pool only the two formal payloads within calibration 1.",
             fontsize=8.6, color="#475667")

    output.mkdir(parents=True, exist_ok=True)
    fig.savefig(output / f"{STEM}.png", dpi=300, facecolor="white")
    fig.savefig(output / f"{STEM}.pdf", facecolor="white",
                metadata={"Title": "How Frequency Selectivity Changes Bit Allocation",
                          "Creator": "Matplotlib", "CreationDate": None})
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("formal_folder", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    require(args.formal_folder.resolve() != args.output_dir.resolve(),
            "Write the new figure to a directory separate from the historical formal archive.")
    render(args.formal_folder, args.output_dir)


if __name__ == "__main__":
    main()
