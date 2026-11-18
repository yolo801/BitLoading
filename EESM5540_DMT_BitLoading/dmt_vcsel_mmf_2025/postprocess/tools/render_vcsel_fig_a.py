#!/usr/bin/env python3
"""Render Figure A from the archived formal CSVs without touching its source."""

import argparse
import csv
import hashlib
import json
from math import isclose, isfinite
from pathlib import Path
from statistics import median

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.ticker import MaxNLocator


CONDITIONS = [(case, swing) for case in (1, 2) for swing in (0.25, 0.50, 0.75)]
FOCUS = [(1, 0.25), (2, 0.50)]
STRATEGIES = (
    ("UniformValidated", "Uniform validated", "U", "#185caa", "o", -0.16),
    ("PerToneValidated", "Per-tone validated", "P", "#c64e23", "s", 0.16),
)
TABLES = ("scenario.csv", "summary.csv", "pair_gains.csv", "overhead.csv", "status.csv")
CALIBRATIONS = set(range(1, 6))
FIGURE = "fig_A_qualified_cycle_rate"


def require(condition, description):
    if not condition:
        raise ValueError(description)


def group_key(row):
    return (int(row["case_id"]), float(row["swing"]), row["strategy"])


def calibration_key(row):
    return (*group_key(row), int(row["calibration_id"]))


def unique_rows(rows, key, label):
    indexed = {key(row): row for row in rows}
    require(len(indexed) == len(rows), f"Duplicate identity in {label}")
    return indexed


def load_rows(path):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    require(rows and all(row["phase"] == "formal" and int(row["q"]) == 8 for row in rows),
            f"Expected 8-bit formal rows in {path.name}")
    return rows


def verify_tables(source):
    scenario, summary, pairs, overhead, slots = [load_rows(source / name) for name in TABLES]
    groups = unique_rows(scenario, group_key, "scenario.csv")
    summaries = unique_rows(summary, calibration_key, "summary.csv")
    costs = unique_rows(overhead, calibration_key, "overhead.csv")
    status = unique_rows(slots, lambda row: (*calibration_key(row), int(row["payload_slot"])), "status.csv")
    paired = unique_rows(
        pairs, lambda row: (int(row["case_id"]), float(row["swing"]), int(row["calibration_id"])),
        "pair_gains.csv",
    )
    expected_groups = {(case, swing, setting[0]) for case, swing in CONDITIONS for setting in STRATEGIES}
    expected_rounds = {(*key, cal) for key in expected_groups for cal in CALIBRATIONS}
    require(set(groups) == expected_groups and set(summaries) == set(costs) == expected_rounds
            and set(status) == {(*key, slot) for key in expected_rounds for slot in (1, 2)}
            and set(paired) == {(*key, cal) for key in CONDITIONS for cal in CALIBRATIONS},
            "The formal strategy/work-point/calibration/slot matrix is incomplete")
    lengths = {int(row["planned_symbols"]) for row in slots}
    require(lengths == {25000}, "The saved payload-slot plan is not the 25,000-symbol experiment")
    payload_length = lengths.pop()

    grouped = {}
    for key, scenario_row in groups.items():
        recorded = [summaries[(*key, cal)] for cal in sorted(CALIBRATIONS)]
        sent = []
        measured_costs = []
        require(int(scenario_row["planned_calibrations"]) == 5, f"Unexpected count for {key}")
        supported = sum(row["state"] == "supported" for row in recorded)
        require(supported == int(scenario_row["supported_count"])
                and bool(int(scenario_row["qualified"])) == (supported == 5),
                f"Inconsistent qualification for {key}")
        for row in recorded:
            identity = calibration_key(row)
            cost = costs[identity]
            n_slots = [status[(*identity, i)] for i in (1, 2)]
            completed = [slot for slot in n_slots if slot["status"] == "completed"]
            require(len(completed) == int(row["payload_slots_completed"])
                    and all(int(slot["actual_symbols"]) == payload_length for slot in completed),
                    f"Payload-slot count disagrees for {identity}")
            attempts = int(cost["attempts"])
            symbols = sum(int(cost[f"{role}_symbols"]) for role in ("A0", "B0", "Ar", "Dr"))
            elapsed = float(cost["T_setup_s"])
            require(symbols == int(cost["setup_symbols"]) == int(row["setup_symbols"])
                    and attempts == int(row["attempts"]) and elapsed == float(row["T_setup_s"])
                    and attempts >= 0 and isfinite(elapsed) and elapsed >= 0,
                    f"Actual setup records disagree for {identity}")
            if row["design_state"] in ("accepted", "design_rejected"):
                measured_costs.append((row["design_state"], elapsed * 1e6, attempts))
            if len(completed) != 2:
                continue
            bits = int(row["bits_per_symbol"])
            nominal = float(row["R_nominal"])
            cycle = float(row["R_cycle"])
            require(bits > 0 and isfinite(nominal) and isfinite(cycle) and 0 < cycle <= nominal,
                    f"Invalid formal capacity or rate for {identity}")
            require(all(int(slot["tested_bits"]) == bits * payload_length for slot in completed),
                    f"Formal tested-bit counts disagree for {identity}")
            require(isclose(cycle, payload_length * bits / (payload_length * bits / nominal + elapsed),
                            rel_tol=1e-11), f"Cycle rate and actual setup disagree for {identity}")
            sent.append((bits, nominal / 1e9, cycle / 1e9))
        require(len(sent) == int(scenario_row["observed_rate_rounds"]),
                f"Observed rates lack complete payload pairs for {key}")
        if supported == 5:
            require(len(sent) == 5, f"Qualified rate requires all five payload pairs for {key}")
            cycle_rates = [item[2] * 1e9 for item in sent]
            for statistic, computed in (("min", min(cycle_rates)), ("median", median(cycle_rates)),
                                        ("max", max(cycle_rates))):
                require(isclose(computed, float(scenario_row[f"R_cycle_{statistic}"]), rel_tol=1e-11),
                        f"Qualified cycle rate disagrees with the five rounds for {key}")
        grouped[key] = (sent, measured_costs, supported, int(scenario_row["design_rejected_count"]))
    pair_deltas = {}
    for point in FOCUS:
        gains = []
        for cal in sorted(CALIBRATIONS):
            pair = paired[(*point, cal)]
            if int(pair["pair_qualified"]):
                uniform, pertone = [summaries[(*point, strategy[0], cal)] for strategy in STRATEGIES]
                require(int(pair["resource_match"]) == 1
                        and uniform["state"] == pertone["state"] == "supported"
                        and int(uniform["bits_per_symbol"]) == int(pair["uniform_bits_per_symbol"])
                        and int(pertone["bits_per_symbol"]) == int(pair["pertone_bits_per_symbol"]),
                        f"Paired comparison disagrees with its supported calibrations for {point}")
                gains.append(int(pertone["bits_per_symbol"]) - int(uniform["bits_per_symbol"]))
        pair_deltas[point] = gains
    return grouped, pair_deltas, payload_length


def draw_range(axis, x, values, color, marker, fill=True):
    center = median(values)
    axis.errorbar(x, center, yerr=[[center - min(values)], [max(values) - center]],
                  fmt=marker, markerfacecolor=color if fill else "white", markeredgecolor=color,
                  markersize=5.8, markeredgewidth=1.25, ecolor=color, elinewidth=1.1, capsize=3,
                  linestyle="none", zorder=4)


def draw_setup(axis, x, costs, column, color, marker):
    if not costs:
        return
    width = 0.106 / max(1, len(costs) - 1)
    for index, item in enumerate(costs):
        jitter = (index - (len(costs) - 1) / 2) * width
        symbol = "x" if item[0] == "design_rejected" else marker
        axis.plot(x + jitter, item[column], marker=symbol, markersize=3.8, color=color,
                  markerfacecolor="white", markeredgewidth=0.98, zorder=3)
    center = median(item[column] for item in costs)
    axis.hlines(center, x - 0.073, x + 0.073, color=color, linewidth=1.55, zorder=4)


def render(grouped, deltas, payload_length, output):
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9, "pdf.fonttype": 42})
    fig, axes = plt.subplots(2, 2, figsize=(11.7, 7.45), facecolor="white")
    bit_ax, rate_ax, setup_ax, trial_ax = axes.flat
    fig.subplots_adjust(left=0.075, right=0.98, top=0.855, bottom=0.185, hspace=0.43, wspace=0.22)
    fig.suptitle("DMT capacity, qualified cycle rate, and setup", y=0.963, fontsize=16, fontweight="semibold")
    fig.text(0.5, 0.916, f"Normalized 50 m VCSEL–MMF  |  8-bit ADC  |  {payload_length:,} payload symbols per cycle",
             ha="center", color="#405060", fontsize=10)

    names = ("Payload capacity", "Nominal and qualified cycle rates",
             "Actual forward-link setup", "Actual candidate validations")
    units = ("bit/DMT symbol", "Rate (Gbit/s)", "Setup time (µs)", "Validation attempts")
    xticks = [f"Case {case}\n{swing:.2f}" for case, swing in CONDITIONS]
    for axis, name, unit in zip(axes.flat, names, units):
        axis.set_title(name, loc="left", pad=8, fontweight="semibold")
        axis.set_ylabel(unit)
        axis.set(xlim=(-0.55, len(CONDITIONS) - 0.45), xticks=range(len(CONDITIONS)), xticklabels=xticks)
        axis.yaxis.set_major_locator(MaxNLocator(5))
        axis.tick_params(axis="x", length=0, pad=5)
        axis.spines[["right", "top"]].set_visible(False)
        axis.spines[["left", "bottom"]].set_color("#9aa4ac")
        axis.set_axisbelow(True)
        axis.grid(axis="y", color="#e0e5ea", linewidth=0.65)
        for point in FOCUS:
            position = CONDITIONS.index(point)
            axis.axvspan(position - 0.46, position + 0.46, color="#fff3d7", zorder=0)

    all_sent = [item for sent, _, _, _ in grouped.values() for item in sent]
    all_costs = [item for _, costs, _, _ in grouped.values() for item in costs]
    bits_limit = max([1, *(item[0] for item in all_sent)])
    rate_limit = max([1, *(item[1] for item in all_sent)])
    setup_limit = max([1, *(item[1] for item in all_costs)])
    attempts_limit = max([1, *(item[2] for item in all_costs)])
    bit_ax.set_ylim(0, 1.245 * bits_limit)
    rate_ax.set_ylim(0, 1.23 * rate_limit)
    setup_ax.set_ylim(0, 1.16 * setup_limit)
    trial_ax.set_ylim(-0.18, attempts_limit + 0.47)
    trial_ax.set_yticks(range(attempts_limit + 1))

    for position, point in enumerate(CONDITIONS):
        status = []
        for strategy, _, short, color, marker, offset in STRATEGIES:
            sent, costs, supported, rejected = grouped[(*point, strategy)]
            x = position + offset
            status.append(f"{short} {supported}/5" if sent else f"{short} {supported}/5, " +
                          ("rejected" if rejected == 5 else "no payload"))
            if sent:
                bits, nominal, cycle = map(list, zip(*sent))
                draw_range(bit_ax, x, bits, color, marker)
                if supported == 5:
                    rate_ax.plot([x, x], [median(cycle), median(nominal)], color=color, linewidth=1.7,
                                 zorder=3)
                    draw_range(rate_ax, x, cycle, color, marker)
                draw_range(rate_ax, x, nominal, color, marker, fill=False)
            draw_setup(setup_ax, x, costs, 1, color, marker)
            draw_setup(trial_ax, x, costs, 2, color, marker)
        if all(grouped[(*point, strategy[0])][3] == 5 for strategy in STRATEGIES):
            rate_ax.text(position, 0.63 * rate_limit, "Both rejected\nNo payload", ha="center",
                         color="#586470", fontsize=8)
            bit_ax.text(position, 0.55 * bits_limit, "No payload", ha="center", color="#586470", fontsize=8)
        else:
            rate_ax.text(position, 1.13 * rate_limit, "\n".join(status), ha="center", va="center",
                         color="#485463", fontsize=7.4)
        if point in deltas:
            gain = deltas[point]
            label = f"P−U {median(gain):+.0f} bit\n({len(gain)}/5 pairs)" if gain else "No supported pair"
            bit_ax.text(position, 1.14 * bits_limit, label, ha="center", va="center",
                        color="#6a4822", fontsize=8, fontweight="medium")

    handles = [Line2D([], [], marker=marker, color=color, linestyle="none", label=label, markersize=6)
               for _, label, _, color, marker, _ in STRATEGIES]
    handles.extend([
        Line2D([], [], marker="o", markerfacecolor="white", markeredgecolor="#354253", linestyle="none",
               label="Nominal rate"),
        Line2D([], [], marker="o", color="#354253", linestyle="none", label="Qualified cycle rate"),
        Line2D([], [], marker="x", color="#354253", linestyle="none", label="Rejected design (setup)"),
    ])
    fig.legend(handles=handles, loc="lower center", bbox_to_anchor=(0.5, 0.088), ncols=5, frameon=False)
    fig.text(0.5, 0.064, "Work points show the case and commanded swing. Shading marks the two focus points.",
             ha="center", color="#485463", fontsize=8.5)
    fig.text(0.5, 0.041, "Rate connectors show the same strategy before and after setup. Error bars show min–max ranges.",
             ha="center", color="#485463", fontsize=8.5)
    fig.text(0.5, 0.018, "Setup symbols mark individual calibrations. Horizontal lines mark medians.",
             ha="center", color="#485463", fontsize=8.5)
    png = output / f"{FIGURE}.png"
    pdf = output / f"{FIGURE}.pdf"
    fig.savefig(png, dpi=300)
    fig.savefig(pdf, metadata={"CreationDate": None, "ModDate": None})
    plt.close(fig)
    return png, pdf


def file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Read-only formal results directory")
    parser.add_argument("output", type=Path, help="Separate postprocessing output directory")
    args = parser.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    require(output != source and source not in output.parents, "Use an output directory outside the formal archive")
    data = verify_tables(source)
    output.mkdir(parents=True, exist_ok=True)
    artifacts = render(*data, output)
    provenance = {
        "source_batch": source.name,
        "source_csv_sha256": {name: file_hash(source / name) for name in TABLES},
        "renderer_sha256": file_hash(Path(__file__)),
        "outputs_sha256": {path.name: file_hash(path) for path in artifacts},
        "focus_cases_and_swings": FOCUS,
        "source_plot_archive_modified": False,
    }
    (output / "fig_A_render_provenance.json").write_text(json.dumps(provenance, indent=2) + "\n",
                                                         encoding="utf-8")
    for path in artifacts:
        print(path)


if __name__ == "__main__":
    main()
