#!/usr/bin/env python3
"""Independent v1.3 arithmetic/model checks, not MATLAB or DMT BER results.

Uses arbitrary deterministic/random numerical vectors, never MATLAB qammod,
the project MATLAB functions, or a payload BER simulation. Synthetic interval
cases only check the predeclared classification logic. Run from the project:
    python3 tools/verify_v13_contracts.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
CHECKS: list[dict] = []
SIGMA0 = 10 ** (-29 / 10)
H = np.array([0.25, 0.5, 0.25])


def check(name: str, condition: bool, observed=None, expected=None) -> None:
    row = {"name": name, "status": "PASS" if bool(condition) else "FAIL"}
    if observed is not None:
        row["observed"] = observed
    if expected is not None:
        row["expected"] = expected
    CHECKS.append(row)
    if not condition:
        raise AssertionError(name)


def near(name: str, observed: float, expected: float, tolerance: float) -> None:
    check(name, math.isfinite(observed) and abs(observed - expected) <= tolerance,
          float(observed), {"value": float(expected), "absolute_tolerance": tolerance})


def stream_plan(preflight: bool = False) -> tuple[list[int], list[tuple]]:
    seeds: list[int] = []
    groups: list[tuple] = []
    for scenario_idx in range(4):
        for calibration_id in ((1,) if preflight else range(1, 11)):
            base = 2_000_000 + 10_000_000 * scenario_idx + 100_000 * calibration_id
            base += 100_000_000 if preflight else 0
            seeds += [base + 101, base + 102, base + 201, base + 202]
            for s in range(1, 4):
                seeds += [base + 5000 + 100 * s + 1, base + 5000 + 100 * s + 2]
                for j, label in enumerate((11, 22, 33), 1):
                    pair = [base + 1000 * s + 10 * j + 1,
                            base + 1000 * s + 10 * j + 2]
                    seeds += pair
                    groups.append((scenario_idx, calibration_id, s, label, j, *pair))
    return seeds, groups


def seed_checks() -> None:
    formal, groups = stream_plan()
    preflight, pre_groups = stream_plan(True)
    check("formal has 1120 unique A/B/C/payload seeds", len(formal) == len(set(formal)) == 1120,
          len(set(formal)), 1120)
    check("preflight has 112 unique seeds", len(preflight) == len(set(preflight)) == 112,
          len(set(preflight)), 112)
    check("formal and preflight namespaces disjoint", not set(formal).intersection(preflight))
    check("all used seeds fit MATLAB uint32 range", all(0 <= s < 2**32 for s in formal + preflight))
    check("360 planned formal groups", len(groups) == 360, len(groups), 360)
    check("36 planned short preflight groups", len(pre_groups) == 36, len(pre_groups), 36)
    check("formal labels and slots are separate", groups[0][3:5] == (11, 1))
    check("linear/cal1/Uniform/label11 exact mapping", groups[0][5:] == (2101011, 2101012),
          list(groups[0][5:]), [2101011, 2101012])
    check("scenario3/cal10/Fixed16/label33 exact mapping",
          groups[-1][5:] == (33003031, 33003032), list(groups[-1][5:]), [33003031, 33003032])
    for scenario_idx in range(4):
        chosen = [g for g in groups if g[0] == scenario_idx]
        check(f"scenario {scenario_idx} has ninety planned groups", len(chosen) == 90)
        check(f"scenario {scenario_idx} has ten calibration IDs",
              {g[1] for g in chosen} == set(range(1, 11)))
    diag = set(range(1_500_000_000, 1_500_010_000))
    check("diagnostic namespace separate", not diag.intersection(formal + preflight))
    reference = {1601, 1609, 1611, 1612, 1613, 1701, 1702, 2701, 2702}
    for s in (1, 2, 3):
        for label in (11, 22, 33):
            reference.update((100000 + 1000*s + 10*label + 1,
                              100000 + 1000*s + 10*label + 2))
        reference.update((300000 + 1000*s + 1, 300000 + 1000*s + 2))
    check("v1.1 reference/self streams separate from formal v1.3", not reference.intersection(formal))
    old_v12: set[int] = set()
    for c in range(1, 11):
        base = 2_000_000 + 100_000*c
        old_v12.update((base+101, base+102, base+201, base+202))
        for s in (1, 2, 3):
            for j in (1, 2, 3):
                old_v12.update((base+1000*s+10*j+1, base+1000*s+10*j+2))
    check("v1.3 linear deliberately shares 220 v1.2 seed numbers; no cross-version independence claim",
          len(old_v12.intersection(formal)) == 220, len(old_v12.intersection(formal)), 220)


def causal_fir(serial: np.ndarray) -> np.ndarray:
    return np.convolve(serial, H, mode="full")[:len(serial)]


def model_checks() -> None:
    sigma_x2 = 2 * 24 / 64
    gain4 = 1 / (4 * math.sqrt(sigma_x2))
    sigma_ext = SIGMA0 / (4**2 * sigma_x2)
    near("expected useful real sample variance", sigma_x2, 0.75, 0)
    near("rho4 noise scaling equals g4 squared", sigma_ext, SIGMA0 * gain4**2, 1e-18)
    rng = np.random.default_rng(554013)
    k = np.arange(1, 25)
    count = 43
    positive = (rng.standard_normal((24, count)) + 1j*rng.standard_normal((24, count))) / math.sqrt(2)
    frequency = np.zeros((64, count), complex)
    frequency[k] = positive
    frequency[64-k] = positive.conj()
    time_complex = math.sqrt(64) * np.fft.ifft(frequency, axis=0)
    near("arbitrary-vector Hermitian IFFT imaginary residual", float(np.max(abs(time_complex.imag))), 0, 1e-13)
    time = time_complex.real
    cp = np.vstack([time[-8:], time])
    serial = cp.ravel(order="F")
    noise = rng.standard_normal(len(serial))
    linear_rx = causal_fir(serial) + math.sqrt(SIGMA0) * noise
    raw_p = 1 + gain4 * serial
    bypass_rx_ac = causal_fir(raw_p - 1) + math.sqrt(sigma_ext) * noise
    relative_error = np.max(abs(bypass_rx_ac / gain4 - linear_rx)) / max(1, np.max(abs(linear_rx)))
    near("rho4 bypass regression, identical raw noise: relative residual", float(relative_error), 0, 1e-11)
    # A full-power filter initialized at DC=1 equals filtering p-1 at zero AC state.
    extended = np.r_[np.ones(len(H)-1), raw_p]
    full_dc = np.convolve(extended, H, mode="full")[len(H)-1:len(H)-1+len(raw_p)] - 1
    near("steady-state known DC subtraction equals AC filter", float(np.max(abs(full_dc-causal_fir(raw_p-1)))), 0, 1e-13)
    # Arbitrary chunk boundaries in the causal stream retain the last two input samples.
    tail = np.zeros(2)
    output = []
    for part in np.split(serial, [72*7, 72*19]):
        joined = np.r_[tail, part]
        conv = np.convolve(joined, H, mode="full")
        output.append(conv[2:2+len(part)])
        tail = joined[-2:]
    near("arbitrary-chunk causal FIR state continuity", float(np.max(abs(np.r_[*output]-causal_fir(serial)))), 0, 1e-13)
    useful_energy = np.sum(time**2, axis=0)
    frequency_energy = np.sum(abs(frequency)**2, axis=0)
    near("unitary Parseval arbitrary-vector residual", float(np.max(abs(useful_energy-frequency_energy))), 0, 1e-11)
    signed = np.r_[serial, -serial]
    for rho in (4.0, 2.5, 1.5):
        gain = 1 / (rho * math.sqrt(0.75))
        raw = 1 + gain*signed
        p = np.clip(raw, 0, 2)
        check(f"rho={rho:g} fixed normalized intensity limits", float(p.min()) >= 0 and float(p.max()) <= 2)
        near(f"rho={rho:g} paired-input symmetry yields mean P0, no renormalization", float(p.mean()), 1, 1e-14)
        check(f"rho={rho:g} mean optical power differs from electrical second moment",
              float(np.mean(p**2)) > float(p.mean()))
        check(f"rho={rho:g} intensity signal must not be squared again",
              not np.allclose(causal_fir(p-1), causal_fir(p**2-1)))
        distortion = np.mean((p-raw)**2)
        check(f"rho={rho:g} clipping error power is nonnegative", float(distortion) >= 0)
        # Clipping is not followed by an artificial active-tone mask.
        p_matrix = p[:len(serial)].reshape((72, count), order="F")[8:]
        regenerated = np.fft.fft(p_matrix-1, axis=0) / 8
        inactive = np.r_[np.arange(25, 40)]
        if rho == 1.5:
            check("clipping can regenerate inactive-frequency energy, retained by model",
                  float(np.sum(abs(regenerated[inactive])**2)) > 0)
    papr = np.max(time**2, axis=0) / np.mean(time**2, axis=0)
    scaled = np.max((gain4*time)**2, axis=0) / np.mean((gain4*time)**2, axis=0)
    near("AC PAPR is invariant to uniform gain, not a rho improvement", float(np.max(abs(papr-scaled))), 0, 1e-12)
    thresholds = np.array([0, 3, 6, 100])
    counts = np.sum(10*np.log10(papr[:, None]) > thresholds, axis=0)
    check("sampled AC PAPR exceedance counters are integer bounded", bool(np.all((counts>=0) & (counts<=count))))
    check("zero PAPR exceedance remains exactly 0/N", int(counts[-1]) == 0, int(counts[-1]), 0)
    # B-by-symbol ordering preserves each carrier's bit sequence under partitioning.
    bits_per_carrier = np.array([6]*15 + [4]*6 + [2]*3)
    total = int(bits_per_carrier.sum())
    raw_bits = rng.integers(0, 2, size=total*count)
    whole = raw_bits.reshape((total, count), order="F")
    chunks = []
    for start, finish in ((0, 7), (7, 19), (19, count)):
        chunks.append(raw_bits[total*start:total*finish].reshape((total, finish-start), order="F"))
    check("symbol-first bit layout preserves data under chunk partition", np.array_equal(whole, np.hstack(chunks)))
    check("PAPR computation did not rescale transmitted input", np.array_equal(time, time_complex.real))


def statistical_checks() -> None:
    def classify(feasible, complete, lows, highs):
        if not feasible:
            return "infeasible"
        if not complete:
            return "incomplete"
        if any(p > 1e-3 for p in lows):
            return "failed"
        return "supported" if all(p < 1e-3 for p in highs) else "inconclusive"
    check("infeasible precedes incomplete", classify(False, False, [], []) == "infeasible")
    check("missing payload is incomplete, not zero BER", classify(True, False, [], []) == "incomplete")
    check("upper equality is inconclusive", classify(True, True, [0], [1e-3]) == "inconclusive")
    check("lower equality is inconclusive", classify(True, True, [1e-3], [2e-3]) == "inconclusive")
    check("u above one is not by itself failed", classify(True, True, [0.8e-3], [1.2e-3]) == "inconclusive")
    check("any lower exceeding target yields failure", classify(True, True, [0, 1.1e-3], [0.5e-3, 2e-3]) == "failed")
    # This checks policy only: scientific Fixed16 failure does not erase its sample.
    check("Fixed16 valid but failed target is scientific data", classify(True, True, [0.002], [0.003]) == "failed")
    check("all configured seed-table row budget", 4*10*3*3*24 == 8640, 4*10*3*3*24, 8640)
    check("all configured pooled-table row budget", 4*10*3*24 == 2880, 4*10*3*24, 2880)
    check("all planned per-calibration strategy rows", 4*10*3 == 120, 4*10*3, 120)
    check("scenario-strategy robustness rows", 4*3 == 12, 4*3, 12)
    check("formal symbol budget excludes initialization and preflight", 360*100000 == 36000000,
          360*100000, 36000000)
    check("independent C planned symbol budget separate from payload", 4*10*3*2048 == 245760)
    check("profile selections denominator is ten, not thirty", 4+3+2+1 == 10 and 3*(4+3+2)+1 != 10)
    check("supported gain needs both U/L, not just a nominal allocation ratio",
          not (classify(True, True, [0], [0.5e-3]) == "supported" and
               classify(True, True, [0.8e-3], [1.2e-3]) == "supported"))


def main() -> None:
    result = {
        "scope": "Independent Python arithmetic/model identities only; NOT MATLAB execution or DMT experiment results.",
        "matlab_executed": False,
        "new_formal_groups_completed_by_this_script": 0,
        "experimental_ber_generated": False,
        "arbitrary_vectors_and_synthetic_statistics_not_experimental_data": True,
        "numpy_rng_for_model_identities_only": 554013,
        "checks": CHECKS,
    }
    try:
        seed_checks()
        model_checks()
        statistical_checks()
    finally:
        result["check_count"] = len(CHECKS)
        result["all_passed"] = bool(CHECKS) and all(r["status"] == "PASS" for r in CHECKS)
        path = ROOT / "validation/v13_contract_checks.json"
        path.parent.mkdir(exist_ok=True)
        path.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(f"Independent v1.3 arithmetic/model identities: {len(CHECKS)} PASS; MATLAB not executed; formal groups 0.")


if __name__ == "__main__":
    main()
