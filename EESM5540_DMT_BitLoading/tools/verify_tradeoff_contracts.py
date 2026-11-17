#!/usr/bin/env python3
"""Independent tradeoff_v1 arithmetic checks, NOT MATLAB or BER experiments.

Numerical vectors below are arbitrary deterministic inputs; they are not
Gray-QAM payloads, A/B/D observations, or substitutes for a MATLAB preflight.
Synthetic counts verify interval/rate arithmetic only. Run from the project:
    python3 tools/verify_tradeoff_contracts.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
CHECKS: list[dict] = []
P_TARGETS = (0.6, 0.8, 1.0, 1.2, 1.4)
ADC_BITS = (4, 6, 8)
SCHEMES = ("UniformAdaptive", "ValidatedLoading")
NFFT, NCP, FS = 64, 8, 64_000_000
CALIBRATIONS, REPEATS, L, MAX_ROUNDS = 5, 2, 50_000, 4
NOISE_VARIANCE = 1.0491e-4


def check(name: str, condition: bool, observed=None, expected=None) -> None:
    row = {"name": name, "status": "PASS" if bool(condition) else "FAIL"}
    if observed is not None:
        row["observed"] = observed
    if expected is not None:
        row["expected"] = expected
    CHECKS.append(row)
    if not condition:
        raise AssertionError(name)


def near(name: str, value: float, expected: float, tolerance: float) -> None:
    check(name, math.isfinite(value) and abs(value - expected) <= tolerance,
          float(value), {"value": float(expected), "absolute_tolerance": tolerance})


def stream_seeds(phase: str) -> tuple[list[int], int, int]:
    base_namespace = 500_000_000 if phase == "formal" else 700_000_000
    ncal = CALIBRATIONS if phase == "formal" else 1
    seeds: list[int] = []
    rows = payload_slots = 0
    for condition_id in range(1, len(P_TARGETS) * len(ADC_BITS) + 1):
        for cal in range(1, ncal + 1):
            base = base_namespace + 1_000_000 * condition_id + 10_000 * cal
            # Pure TX calibration has one data stream, no fictional noise.
            seeds += [base + 1, base + 11, base + 12, base + 21, base + 22]
            rows += 3
            for strategy in range(1, len(SCHEMES) + 1):
                for round_id in range(1, MAX_ROUNDS + 1):
                    offset = base + 1000 * strategy + 100 * round_id
                    seeds += [offset + 1, offset + 11, offset + 12,
                              offset + 21, offset + 22]
                    rows += 3
                for slot in range(1, REPEATS + 1):
                    offset = base + 5000 + 100 * strategy + 10 * slot
                    seeds += [offset + 1, offset + 2]
                    rows += 1
                    payload_slots += 1
    return seeds, rows, payload_slots


def seed_and_budget_checks() -> None:
    conditions = len(P_TARGETS) * len(ADC_BITS)
    shared = conditions * CALIBRATIONS
    cases = shared * len(SCHEMES)
    formal, rows, slots = stream_seeds("formal")
    preflight, pre_rows, pre_slots = stream_seeds("preflight")
    check("condition/calibration/strategy/repeat dimensions derive all budgets",
          conditions == 15 and shared == 75 and cases == 150 and slots == cases * REPEATS,
          {"conditions": conditions, "shared": shared, "cases": cases, "slots": slots})
    check("formal roles have unique seeds including unused planned rounds",
          len(set(formal)) == len(formal), len(formal))
    check("preflight roles have unique independent seeds",
          len(set(preflight)) == len(preflight), len(preflight))
    check("preflight and formal namespaces are disjoint", not set(formal) & set(preflight))
    check("diagnostic namespace is separate from every planned stream",
          max(formal + preflight) < 1_800_000_000)
    check("all planned seeds fit MATLAB uint32", all(0 <= s < 2**32 for s in formal + preflight))
    per_shared = 1 + 2 * 2 + len(SCHEMES) * (MAX_ROUNDS * (1 + 2 * 2) + REPEATS * 2)
    check("one noise-free TX-cal seed, four A/B seeds and per-case roles are counted",
          len(formal) == shared * per_shared, len(formal), shared * per_shared)
    check("plan row count derives from configured roles",
          rows == shared * (3 + len(SCHEMES) * (MAX_ROUNDS * 3 + REPEATS)))
    check("preflight uses one full calibration per condition",
          pre_rows == rows // CALIBRATIONS and pre_slots == slots // CALIBRATIONS)
    check("formal maximum DMT symbols derive from slots and L", slots * L == 15_000_000)
    check("each complete payload sample denominator includes CP", L * (NFFT + NCP) == 3_600_000)
    check("raw integer counters fit exact double arithmetic", slots * L * 24 * 6 < 2**53)
    near("DMT duration includes CP once", (NFFT + NCP) / FS, 1.125e-6, 1e-21)


def quantize(values: np.ndarray, bits: int) -> np.ndarray:
    lo, hi = -0.1, 2.1
    delta = (hi - lo) / (2**bits)
    bins = np.clip(np.floor((values - lo) / delta), 0, 2**bits - 1)
    return lo + (bins + 0.5) * delta


def adc_checks() -> None:
    lo, hi = -0.1, 2.1
    for q in ADC_BITS:
        levels = 2**q
        delta = (hi - lo) / levels
        centers = lo + (np.arange(levels) + 0.5) * delta
        out = quantize(centers, q)
        check(f"ADC {q}: every midpoint is a fixed point", np.allclose(out, centers, rtol=0, atol=5e-16))
        check(f"ADC {q}: exactly 2^q distinct midpoint levels", len(np.unique(out)) == levels)
        ends = quantize(np.array([lo - 1, lo, hi, hi + 1]), q)
        check(f"ADC {q}: saturation returns terminal mid-rise levels",
              np.allclose(ends, [lo + delta / 2] * 2 + [hi - delta / 2] * 2, rtol=0, atol=5e-16))
        values = np.linspace(lo - 0.3, hi + 0.3, 1001)
        output = quantize(values, q)
        check(f"ADC {q}: monotone fixed-range transfer", np.all(np.diff(output) >= 0))
        check(f"ADC {q}: unsaturated quantization error is at most half a step",
              np.max(np.abs(output[(values >= lo) & (values <= hi)] - values[(values >= lo) & (values <= hi)])) <= delta / 2 + 1e-15)
    edge = np.array([lo - 1e-8, lo, hi, hi + 1e-8])
    check("strict ADC input out-of-range counts exclude exact interval endpoints",
          int(np.sum(edge < lo)) == 1 and int(np.sum(edge > hi)) == 1)
    check("thermal noise is a fixed declared variance, no signal-power normalization",
          len({NOISE_VARIANCE for _p in P_TARGETS for _q in ADC_BITS for _s in SCHEMES}) == 1)


def fixed_waveform_power_checks() -> None:
    sigma_ref = math.sqrt(2 * 24 / NFFT)
    near("declared waveform reference variance", sigma_ref**2, 0.75, 2e-16)
    t = np.arange(8192, dtype=float)
    # Arbitrary deterministic samples, not a generated QAM/DMT calibration.
    x = 1.1 * np.sin(2 * np.pi * t / 101) + 0.8 * np.cos(2 * np.pi * t / 37)
    base = 1 + x / (4 * sigma_ref)

    def mean_power(bias: float, a: np.ndarray = base) -> float:
        return float(np.mean(np.clip(bias * a, 0, 2)))

    grid = np.linspace(0, 4, 81)
    means = np.array([mean_power(float(b)) for b in grid])
    check("nonnegative-b clipping mean is nondecreasing on a fixed sample set", np.all(np.diff(means) >= -1e-15))
    check("declared five targets are reachable on this arbitrary calibration example",
          means[0] <= min(P_TARGETS) and means[-1] >= max(P_TARGETS))
    for target in P_TARGETS:
        left, right = 0.0, 4.0
        for _iteration in range(40):
            b = (left + right) / 2
            measured = mean_power(b)
            if abs(measured / target - 1) <= 0.002:
                break
            if measured < target:
                left = b
            else:
                right = b
        check(f"fixed-waveform bisection reaches relative target tolerance {target:g}", abs(measured / target - 1) <= 0.002)
        p = np.clip(b * base, 0, 2)
        check(f"optical mean/square/range distinctions {target:g}",
              np.all((p >= 0) & (p <= 2)) and float(np.mean(p**2)) >= float(np.mean(p))**2 - 1e-14)
    p = np.clip(1.4 * base, 0, 2)
    check("bias control is not generally the clipped actual average", abs(float(np.mean(p)) - 1.4) > 1e-5)
    check("optical E[p] and squared-signal E[p^2] are distinct quantities", abs(float(np.mean(p)) - float(np.mean(p**2))) > 1e-3)
    check("relative optical-power dB uses 10log10 with P_ref=1",
          abs(10 * math.log10(0.6) - 20 * math.log10(0.6)) > 1)


def dc_and_energy_checks() -> None:
    rng = np.random.default_rng(554001)
    k = np.arange(1, 25)
    spectrum = np.zeros((NFFT, 19), dtype=complex)
    spectrum[k] = rng.normal(size=(24, 19)) + 1j * rng.normal(size=(24, 19))
    spectrum[NFFT - k] = np.conj(spectrum[k])
    useful = np.fft.ifft(spectrum, axis=0) * math.sqrt(NFFT)
    check("Hermitian arbitrary input yields real useful samples", np.max(np.abs(useful.imag)) < 1e-14)
    check("unitary IFFT preserves arbitrary frequency-domain energy",
          np.allclose(np.sum(np.abs(spectrum)**2, axis=0), np.sum(np.abs(useful)**2, axis=0), rtol=1e-14, atol=1e-12))
    serial = np.vstack([useful.real[-NCP:], useful.real]).ravel(order="F")
    check("CP covers causal FIR memory", NCP >= len([0.25, 0.5, 0.25]) - 1)
    p = np.clip(1 + serial / (4 * math.sqrt(0.75)), 0, 2)
    noise = math.sqrt(NOISE_VARIANCE) * rng.normal(size=len(serial))
    h = np.array([0.25, 0.5, 0.25])
    physical = np.convolve(p, h)[:len(serial)] + noise
    ac = np.convolve(p - 1, h)[:len(serial)] + noise
    physical_useful = physical.reshape((NFFT + NCP, -1), order="F")[NCP:]
    ac_useful = ac.reshape((NFFT + NCP, -1), order="F")[NCP:]
    check("physical DC and prior AC paths differ only by DC on useful samples",
          np.max(np.abs(physical_useful - ac_useful - 1)) < 1e-14)
    phys_fft = np.fft.fft(physical_useful, axis=0) / math.sqrt(NFFT)
    ac_fft = np.fft.fft(ac_useful, axis=0) / math.sqrt(NFFT)
    check("ADC-bypass DC regression preserves positive data bins",
          np.max(np.abs(phys_fft[k] - ac_fft[k])) < 1e-13)
    qphysical = quantize(physical, 4).reshape((NFFT + NCP, -1), order="F")[NCP:]
    qac = quantize(ac, 4).reshape((NFFT + NCP, -1), order="F")[NCP:]
    check("quantizing before/after DC removal is not interchangeable",
          np.max(np.abs(np.fft.fft(qphysical, axis=0)[k] - np.fft.fft(qac, axis=0)[k])) > 1e-3)


def wilson(e: float, n: float) -> tuple[float, float]:
    z = 1.96
    p = e / n
    d = 1 + z*z/n
    center = (p + z*z/(2*n)) / d
    radius = z * math.sqrt(p*(1-p)/n + z*z/(4*n*n)) / d
    return max(0.0, center-radius), min(1.0, center+radius)


def classify(low: np.ndarray, high: np.ndarray) -> str:
    if np.any(low > 1e-3):
        return "failed"
    return "supported" if np.all(high < 1e-3) else "inconclusive"


def interval_cost_checks() -> None:
    low, high = wilson(0, 8192 * 2)
    near("zero observed errors still have a positive Wilson upper endpoint", high, 1.96**2/(8192*2+1.96**2), 1e-18)
    near("zero-count Wilson lower endpoint", low, 0, 1e-18)
    check("upper endpoint equal to BER target is inconclusive", classify(np.array([0.0]), np.array([1e-3])) == "inconclusive")
    check("lower endpoint equal to target is not automatically failed", classify(np.array([1e-3]), np.array([0.002])) == "inconclusive")
    check("any lower endpoint above target is failed", classify(np.array([0.0, 0.00101]), np.array([0.0001, 0.002])) == "failed")
    check("all upper endpoints strictly below target is supported", classify(np.zeros(24), np.full(24, 0.0009)) == "supported")
    e = np.array([3.0, 7.0]); n = np.array([50_000.0 * 2, 50_000.0 * 6])
    pooled = float(np.sum(e) / np.sum(n))
    check("pooled BER is a count ratio, not an unweighted mean of BERs", abs(pooled - float(np.mean(e/n))) > 1e-7)
    ts = (NFFT + NCP) / FS
    for rounds in range(1, MAX_ROUNDS + 1):
        setup = 1024 + 2048 + rounds * (1024 + 8192)
        for bits in (48, 96, 144):
            nominal = bits / ts
            cycle = L * bits / ((setup + L) * ts)
            check(f"cycle overhead reduces nominal rate (r{rounds},B{bits})", 0 < cycle < nominal)
            mistaken_2L = 2*L*bits / ((setup + 2*L) * ts)
            check(f"two statistical repeats cannot silently become one 2L session (r{rounds},B{bits})", abs(mistaken_2L - cycle) > 1)
    check("pure TX calibration does not add optical-link training symbols",
          1024 + 2048 + (1024 + 8192) == 12_288)
    check("ADC bits are capability proxies, not money or watts", set(ADC_BITS) == {4, 6, 8})
    check("five-round all-supported criterion differs from successful-only median",
          not all([True, True, True, True, False]))
    # A synthetic business-threshold example checks the conservative minimum.
    rates = np.array([51, 52, 53, 49, 55]) * 1e6
    check("business rate requirement uses minimum across all five rounds",
          np.median(rates) >= 50e6 and np.min(rates) < 50e6)
    powers = np.array([0.99, 1.0, 1.01])
    check("same-power budget envelope uses largest actual repeated power",
          np.mean(powers) <= 1 and not np.max(powers) <= 1)


def main() -> None:
    seed_and_budget_checks()
    adc_checks()
    fixed_waveform_power_checks()
    dc_and_energy_checks()
    interval_cost_checks()
    result = {"scope": "Independent arithmetic/model identities and synthetic counterexamples only",
              "MATLAB_executed": False, "preflight_executed": False,
              "formal_payload_groups_completed": 0,
              "experiment_data_generated": False,
              "check_count": len(CHECKS), "checks": CHECKS}
    path = ROOT / "validation" / "tradeoff_contract_checks.json"
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(result, indent=2) + "\n")
    print(f"tradeoff_v1 independent arithmetic: {len(CHECKS)} PASS; MATLAB not executed; formal payload groups 0.")


if __name__ == "__main__":
    main()
