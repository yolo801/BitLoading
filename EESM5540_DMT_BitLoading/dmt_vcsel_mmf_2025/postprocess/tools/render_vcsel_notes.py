"""Read the formal archive's CSV tables and regenerate the two report texts."""

import argparse
import csv
import json
import math
from collections import Counter, defaultdict
from pathlib import Path
from statistics import median

STRATEGIES = ("UniformValidated", "PerToneValidated")
FOCUS = ((1, 0.25), (2, 0.50))
TOKEN = "<!-- VCSEL_POSTPROCESS_COMPLETE -->"


def table(archive, name):
    with (archive / f"{name}.csv").open(encoding="utf-8-sig", newline="") as file:
        entries = list(csv.DictReader(file))
    assert all(row["phase"] == "formal" for row in entries), name
    return entries


def design_key(row):
    return int(row["condition_id"]), int(row["calibration_id"]), row["strategy"]


def slot_key(row):
    return (*design_key(row), int(row["payload_slot"]))


def point(row):
    return int(row["case_id"]), float(row["swing"])


def close(left, right):
    return math.isclose(float(left), float(right), rel_tol=5e-12, abs_tol=5e-12)


def span(values, decimals, suffix=""):
    assert values and all(math.isfinite(value) for value in values)
    center = f"{median(values):.{decimals}f}{suffix}"
    low, high = f"{min(values):.{decimals}f}", f"{max(values):.{decimals}f}"
    if low != high:
        center += f" [{low}–{high}{suffix}]"
    return center


def collect(archive):
    fit = json.loads((archive / "channel_evidence/channel_fit.json").read_text(encoding="utf-8"))
    assert fit["passed"] and (fit["NFFT"], fit["NCP"], fit["Fs_Hz"]) == (512, 16, 128_000_000_000)
    occupied = set(fit["active_k"])
    Ts = (fit["NFFT"] + fit["NCP"]) / fit["Fs_Hz"]
    slots, power = table(archive, "status"), table(archive, "power_adc")
    tallies = Counter(row["status"] for row in slots)
    assert len(slots) == len({slot_key(row) for row in slots}) == 120
    assert {int(row["planned_symbols"]) for row in slots} == {25000}
    assert tallies == Counter(completed=100, design_rejected=20), tallies
    sent = {slot_key(row): row for row in slots if row["status"] == "completed"}
    assert len(sent) == len(power) == len({slot_key(row) for row in power}) == 100
    assert set(sent) == {slot_key(row) for row in power}
    clips = samples = 0
    mean_powers = []
    for row in power:
        planned = sent[slot_key(row)]
        assert int(planned["actual_symbols"]) == 25_000
        n = int(row["samples"])
        assert n == int(planned["actual_symbols"]) * (fit["NFFT"] + fit["NCP"])
        low, high = int(row["tx_low_count"]), int(row["tx_high_count"])
        assert low >= 0 and high >= 0 and low + high <= n
        mean = float(row["tx_sum"]) / n
        assert close(mean, row["P_actual"]) and close(mean, planned["P_actual"])
        assert row["power_match"] == planned["power_match"] == "1"
        assert abs(mean - 1) <= 0.01
        mean_powers.append(mean)
        clips += low + high
        samples += n
    assert (clips, samples) == (47, 1_320_000_000)
    summary = table(archive, "summary")
    assert len(summary) == len({design_key(row) for row in summary}) == 60
    assert Counter(row["state"] for row in summary) == Counter(supported=50, design_rejected=10)
    assert all(point(row) == (2, .25) for row in summary if row["state"] == "design_rejected")
    overhead = {design_key(row): row for row in table(archive, "overhead")}
    assert set(overhead) == {design_key(row) for row in summary}
    profiles = defaultdict(list)
    for row in table(archive, "profiles"):
        profiles[design_key(row)].append(row)
    derived = {}
    for row in summary:
        key = design_key(row)
        setup_row = overhead[key]
        attempts = int(setup_row["attempts"])
        assert attempts == int(row["attempts"]) and 1 <= attempts <= 3
        blocks = [int(setup_row[f"{name}_symbols"]) for name in ("A0", "B0", "Ar", "Dr")]
        assert blocks == [1024, 2048, attempts * 1024, attempts * 8192]
        setup_symbols = sum(blocks)
        assert setup_symbols == int(row["setup_symbols"]) == int(setup_row["setup_symbols"])
        setup = setup_symbols * Ts
        assert close(setup, row["T_setup_s"]) and close(setup, setup_row["T_setup_s"])
        emitted = [(*key, slot) in sent for slot in (1, 2)]
        if row["state"] == "design_rejected":
            assert not any(emitted) and key not in profiles
            continue
        assert all(emitted) and int(row["payload_slots_completed"]) == 2
        tones = profiles[key]
        assert len(tones) == len(occupied) and {int(tone["k"]) for tone in tones} == occupied
        orders = [int(tone["M"]) for tone in tones]
        assert all(order in {4, 16, 64} for order in orders)
        bits = sum(order.bit_length()-1 for order in orders)
        assert bits == int(row["bits_per_symbol"])
        nominal = bits / Ts
        cycle = 25_000 * bits / (25_000 * Ts + setup)
        assert close(nominal, row["R_nominal"]) and close(cycle, row["R_cycle"])
        derived[key] = (bits, nominal, cycle, setup, attempts)
    pairs = table(archive, "pair_gains")
    assert len(pairs) == 30
    qualified_pairs = [row for row in pairs if row["pair_qualified"] == "1"]
    assert len(qualified_pairs) == 25
    for row in qualified_pairs:
        c, cal = int(row["condition_id"]), int(row["calibration_id"])
        u, p = (derived[c, cal, strategy] for strategy in STRATEGIES)
        assert row["resource_match"] == "1"
        assert row["uniform_state"] == row["pertone_state"] == "supported"
        assert (int(row["uniform_bits_per_symbol"]), int(row["pertone_bits_per_symbol"])) == (u[0], p[0])
        assert close(row["uniform_R_cycle"], u[2]) and close(row["pertone_R_cycle"], p[2])
        assert close(row["validated_delta_R_cycle"], p[2]-u[2])
        assert close(row["uniform_T_setup_s"], u[3]) and close(row["pertone_T_setup_s"], p[3])
    log = (archive / "run.log").read_text(encoding="utf-8-sig")
    failure = (archive / "failure_status.txt").read_text(encoding="utf-8-sig")
    assert "VCSEL ACQUISITION COMPLETE | formal | sent=100 rejected=20 planned=120" in log
    assert "MATLAB:printf:invalidInputType" in failure and "formal graphics" in failure
    return fit, Ts, tallies, samples, clips, mean_powers, summary, profiles, derived, qualified_pairs


def render(archive):
    fit, Ts, tallies, samples, clips, p, summary, profiles, values, pairs = collect(archive)
    sections = [
        "# VCSEL–MMF DMT 正式结果",
        f"本说明由 Python 从正式归档只读重建。120 个计划槽中实发 {tallies['completed']} 槽，"
        f"正常设计拒绝 {tallies['design_rejected']} 槽，功率错误、执行错误和未完成载荷槽均为 0。"
        "50 个实发校准轮满足逐子载波 BER 判据。Case 2、摆幅 0.25 的两策略各有 5 个校准轮在设计阶段拒绝。"
        "这些轮未经正式载荷检验。原批次在生成中文报告时退出，未写出 MATLAB 最终整体验证回执。",
        f"100 个实发槽的平均归一化发射光功率均匹配目标 1，实测范围为 {min(p):.9f}–{max(p):.9f}。"
        f"正式载荷的 {samples:,} 个含 CP 发射样本（约 {samples/1e8:.3g} 亿个）中观察到 {clips} 个 TX 削波样本，"
        f"比例为 {clips/samples:.6g}（{100*clips/samples:.6g}%）。这组观察不足以单独评估削波的 BER 或速率惩罚。"
        "实验没有测量硬件成本或电功耗。",
        "## 两个工作点的承载量、速率与配置开销",
        f"含 CP 的 DMT 符号时长为 {Ts*1e9:.3f} ns。名义载荷速率是每符号比特数除以该时长。"
        "周期速率按每次配置后 25,000 个载荷符号计算，计入共享探测和实际发出的全部训练、验证及重试。"
        "两槽独立载荷用于统计重复。发射机本地标定另列，控制延迟采用 0 秒理想模型。",
    ]
    rows_out = [
        "| 频响、摆幅 | 策略 | BER 达标轮数 | bit/DMT 符号 | 名义速率 (Gbit/s) | 周期速率 (Gbit/s) | 从名义到周期的下降 (Gbit/s) | 下降比例 | 配置时间 (µs) | 候选尝试 |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    observations = []
    setup_symbols = defaultdict(set)
    for case_id, swing in FOCUS:
        for strategy in STRATEGIES:
            work = [row for row in summary if point(row) == (case_id, swing) and row["strategy"] == strategy]
            assert len(work) == 5 and all(row["state"] == "supported" for row in work)
            bits, nominal, cycle, setup, attempts = map(list, zip(*(values[design_key(row)] for row in work)))
            setup_symbols[strategy].update(round(value / Ts) for value in setup)
            reductions = [n - c for n, c in zip(nominal, cycle)]
            percents = [100 * (n - c) / n for n, c in zip(nominal, cycle)]
            rows_out.append(
                f"| Case {case_id}，{swing:.2f} | {strategy} | 5/5 | {span(bits,0)} | "
                f"{span([n/1e9 for n in nominal],3)} | {span([c/1e9 for c in cycle],3)} | "
                f"{span([r/1e9 for r in reductions],3)} | {span(percents,2,'%')} | "
                f"{span([s*1e6 for s in setup],3)} | {span(attempts,0)} |"
            )
        relevant = [row for row in pairs if point(row) == (case_id, swing)]
        assert len(relevant) == 5
        delta = [int(row["pertone_bits_per_symbol"]) - int(row["uniform_bits_per_symbol"]) for row in relevant]
        percent = [100*d/int(row["uniform_bits_per_symbol"]) for d, row in zip(delta, relevant)]
        delta_rate = [float(row["validated_delta_R_cycle"])/1e9 for row in relevant]
        if case_id == 1:
            shared_bits = {int(row["uniform_bits_per_symbol"]) for row in relevant}
            assert delta == [0]*5 and len(shared_bits) == 1
            observations.append(
                f"Case 1、0.25 的两策略均冻结为 {next(iter(shared_bits))} bit/DMT 符号，承载量差为 {span(delta,0)}。"
                f"逐载波策略的周期速率高 {span(delta_rate,3)} Gbit/s，来自本批按实发配置块折算的开销差异。"
            )
        else:
            assert sorted(delta) == [386, 386, 386, 388, 388]
            observations.append(
                f"Case 2、0.50 的逐载波策略多承载 {min(delta)}–{max(delta)} bit/DMT 符号（{min(percent):.2f}%–{max(percent):.2f}%），"
                f"周期速率多 {span(delta_rate,3)} Gbit/s。该点的净速率差同时包含承载量和配置开销的差异。"
            )
    assert all(len(setup_symbols[name]) == 1 for name in STRATEGIES)
    u_setup, p_setup = (next(iter(setup_symbols[name])) for name in STRATEGIES)
    sections.extend(["\n".join(rows_out), *observations,
                     "表内若有范围，先给五轮中位数，再以方括号给最小值–最大值。两处工作点的统一选阶发送 "
                     f"{u_setup:,} 个设置符号，逐载波选阶发送 {p_setup:,} 个。"
                     "本批统一策略尝试三次、逐载波策略尝试一次的差异取决于预设协议、工作点及实测验证路径。"])
    notch = fit["case2_features"]["source_notch_GHz"]
    ref = {row["strategy"]: row for row in summary if point(row) == (2, .5) and row["calibration_id"] == "1"}
    notes = []
    for strategy in STRATEGIES:
        tones = profiles[design_key(ref[strategy])]
        nearest = min(tones, key=lambda tone: abs(float(tone["frequency_GHz"])-notch))
        mix = "、".join(f"{m}-QAM×{n}" for m,n in sorted(Counter(int(tone["M"]) for tone in tones).items()))
        notes.append(f"{strategy} 的冻结表为 {mix}，最接近陷波的 {float(nearest['frequency_GHz']):.2f} GHz 活跃载波使用 {nearest['M']}-QAM。")
    sensitivity = table(archive, "length_sensitivity")
    assert all(row["pair_qualified"] == "1" and row["cross_over_status"] == "no_positive_crossover" for row in sensitivity)
    scenarios = table(archive, "scenario")
    assert len(scenarios) == 12
    all_rows = [
        "| Case | 摆幅 | 策略 | 达标轮数 | 设计拒绝轮数 | 其余轮次 |",
        "| ---: | ---: | --- | ---: | ---: | ---: |",
    ]
    for row in sorted(scenarios, key=lambda row: (*point(row), STRATEGIES.index(row["strategy"]))):
        case_id, swing = point(row)
        strategy = row["strategy"]
        expected_states = Counter(item["state"] for item in summary if point(item) == (case_id, swing) and item["strategy"] == strategy)
        planned = int(row["planned_calibrations"])
        passed = int(row["supported_count"])
        rejected = int(row["design_rejected_count"])
        assert planned == sum(expected_states.values()) == 5
        assert (passed, rejected) == (expected_states["supported"], expected_states["design_rejected"])
        assert row["qualified"] == str(int(passed == 5))
        all_rows.append(f"| {case_id} | {swing:.2f} | {strategy} | {passed}/{planned} | {rejected} | {planned-passed-rejected} |")
    sections.extend([
        "## 图表判读",
        f"图 B 固定 Case 2、摆幅 0.50、第 1 个校准实例，公开幅频曲线的预定陷波约为 {notch:.2f} GHz。"
        + "".join(notes)
        + "图中 BER 合并该轮两个正式载荷的整数计数。零观察误码点显示逐点 95% Wilson 上限。",
        "图 A 上排比较每符号承载、名义速率和达标周期速率，下排给出实际配置时间和候选验证次数。"
        "达标周期速率覆盖 12 个策略×工作点中的 10 个，全部要求五轮达标。"
        "另按 Case 2、摆幅 0.50 已冻结的表和配置时间，在 1,000–100,000 载荷符号间重算周期速率，未发现正交叉点。",
        "\n".join(all_rows),
        "结论适用于本实验的两条公开 50 m 模型响应、公共频带、摆幅、噪声模型和固定 8 bit ADC。"
        "报告速率使用仿真采样时钟。此处的比较考察同一 DMT 链路的统一与逐载波选阶。",
        TOKEN,
    ])
    zh = "\n\n".join(sections) + "\n"
    en = (
        "Fig. A. DMT capacity, rates and actual setup for two normalized 50 m VCSEL–MMF model responses "
        "(A. M. Rosa Brusin et al., SPPCom 2025, doi:10.1364/SPPCOM.2025.SpTh3E.4). "
        "Open rate markers denote nominal payload rates. Filled rate markers denote cycle rates supported "
        "in all five calibrations at L = 25,000 DMT symbols. Within-strategy rate gaps quantify setup overhead. "
        "Between-strategy bit capacity differences show the allocation gain. The lower panels show actual "
        "forward setup time and candidate validation attempts, including performed attempts for rejected designs. "
        "Shading highlights Case 1 at swing 0.25 and Case 2 at swing 0.50. "
        "Both strategies rejected all calibrations of Case 2 at swing 0.25.\n\n"
        f"Fig. B. Shared-probe SNR, frozen bit allocations and observed payload BER for formal calibration 1 "
        f"of Case 2 at commanded swing 0.50 and 8-bit ADC. The vertical marker is the first public-curve "
        f"notch at approximately {notch:.2f} GHz. Approximate pointwise 95% Wilson intervals are computed from "
        "pooled counts of the two independent payload slots. Downward triangles indicate upper bounds "
        "for zero observed errors.\n"
    )
    check(zh, en)
    return zh, en


def check(chinese, english):
    assert chinese.strip().endswith(TOKEN) and chinese.count(TOKEN) == 1
    assert all(word in chinese for word in ("100 槽", "20 槽", "1,320,000,000", "47 个 TX", "Case 1，0.25", "Case 2，0.50", "126.720", "50.688", "55.13%", "32.95%", "52.209", "78.017", "140.755", "386–388"))
    assert english.startswith("Fig. A.") and "\n\nFig. B." in english
    for text in (chinese, english):
        data = text.encode("utf-8", errors="strict")
        assert data.decode("utf-8", errors="strict") == text and "\ufffd" not in text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    src, out = args.archive.resolve(strict=True), args.output.resolve()
    if out == src or src in out.parents:
        parser.error("Choose an output directory outside the formal archive.")
    zh, en = render(src)
    out.mkdir(parents=True, exist_ok=True)
    texts = {"results_zh.md": zh, "figure_captions_en.txt": en}
    for name, text in texts.items():
        path = out / name
        if path.exists():
            assert path.read_bytes() == text.encode("utf-8"), f"Refusing to replace {path}."
        else:
            with path.open("x", encoding="utf-8", newline="\n") as file:
                file.write(text)
    check(*( (out / name).read_text(encoding="utf-8", errors="strict") for name in texts))
    print("Python report reconstruction completed from archive; no simulation was run.")


if __name__ == "__main__":
    main()
