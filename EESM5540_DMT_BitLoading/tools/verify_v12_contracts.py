#!/usr/bin/env python3
"""Independent protocol arithmetic checks; does not execute MATLAB or measure BER.

The seed map is reconstructed from the user-specified v1.2 equations. Synthetic
interval/count cases below test statistical logic only and are not experimental
data. Run from the project folder: python3 tools/verify_v12_contracts.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHECKS: list[dict] = []


def check(name: str, condition: bool, observed=None, expected=None) -> None:
    record = {"name": name, "status": "PASS" if condition else "FAIL"}
    if observed is not None:
        record["observed"] = observed
    if expected is not None:
        record["expected"] = expected
    CHECKS.append(record)
    if not condition:
        raise AssertionError(name)


def wilson(errors: int, bits: int) -> tuple[float, float]:
    p, z = errors / bits, 1.96
    d = 1 + z*z/bits
    center = (p+z*z/(2*bits))/d
    radius = z*math.sqrt(p*(1-p)/bits+z*z/(4*bits*bits))/d
    return max(0, center-radius), min(1, center+radius)


def status(feasible: bool, complete: bool, lows: list[float], highs: list[float]) -> str:
    if not feasible:
        return "infeasible"
    if not complete:
        return "incomplete"
    if any(low > 1e-3 for low in lows):
        return "failed"
    if all(high < 1e-3 for high in highs):
        return "supported"
    return "inconclusive"


def seed_checks() -> None:
    used: list[int] = []
    payload = []
    calibration = []
    for calibration_id in range(1, 11):
        base = 2_000_000 + 100_000*calibration_id
        init = [base+101, base+102, base+201, base+202]
        calibration.extend(init)
        used.extend(init)
        for s in range(1, 4):
            for j, label in enumerate((11, 22, 33), 1):
                pair = [base+1000*s+10*j+1, base+1000*s+10*j+2]
                used.extend(pair)
                payload.append((calibration_id, s, label, j, *pair))
    old = {1601, 1611, 1612, 1613, 1609, 1701, 2701, 1702, 2702}
    for s in (1, 2, 3):
        for tag in (11, 22, 33):
            old.update((100000+1000*s+10*tag+1, 100000+1000*s+10*tag+2))
        old.update((300000+1000*s+1, 300000+1000*s+2))
    check("ten rounds contain forty independent initialization seeds", len(calibration)==40, len(calibration), 40)
    check("ninety payload groups planned", len(payload)==90, len(payload), 90)
    check("all 220 new stream seeds distinct", len(set(used))==220, len(set(used)), 220)
    check("new seeds disjoint from historical and self-check seeds", not set(used).intersection(old))
    check("MATLAB uint32 seed range", min(used)>=0 and max(used)<2**32)
    first = payload[0]
    check("round1 Uniform label11 uses slot1", first[4:]==(2101011,2101012), list(first[4:]), [2101011,2101012])
    last = payload[-1]
    check("round10 Fixed16 label33 uses slot3", last[4:]==(3003031,3003032), list(last[4:]), [3003031,3003032])
    check("payload uses slot instead of literal label", first[4]!=2100000+1000+10*11+1)
    for round_id in range(1, 11):
        group = [row for row in payload if row[0]==round_id]
        check(f"round {round_id}: nine unique scheme-label groups", len({(g[1],g[2]) for g in group})==9)


def statistical_checks() -> None:
    check("status priority: infeasible before incomplete", status(False,False,[],[])=="infeasible")
    check("status: incomplete is not BER zero", status(True,False,[],[])=="incomplete")
    check("strict upper equality remains inconclusive", status(True,True,[0],[1e-3])=="inconclusive")
    check("strict lower equality remains inconclusive", status(True,True,[1e-3],[2e-3])=="inconclusive")
    check("any lower beyond target dominates support elsewhere", status(True,True,[0,1.1e-3],[0.5e-3,2e-3])=="failed")
    check("u above one alone cannot imply target failure", status(True,True,[0.8e-3],[1.2e-3])=="inconclusive")
    for bits in (600000,1200000,1800000):
        low, high = wilson(0,bits)
        expected = 1.96**2/(bits+1.96**2)
        check(f"synthetic zero-count upper remains positive n={bits}", low==0 and high>0)
        check(f"synthetic zero-count Wilson identity n={bits}", abs(high-expected)<1e-15, high, expected)
        check(f"u is Wilson upper divided by target n={bits}", abs(high/1e-3-1000*expected)<1e-12)
    # A pure statistics counterexample: cross-round pooling can erase a failed
    # calibration. These are synthetic counts, not DMT test results.
    a = wilson(0,600000)
    b = wilson(1000,600000)
    combined = wilson(1000,1200000)
    check("synthetic round A passes", status(True,True,[a[0]],[a[1]])=="supported")
    check("synthetic round B fails", status(True,True,[b[0]],[b[1]])=="failed")
    check("synthetic mixed pool passes despite failed B: do not pool profiles", status(True,True,[combined[0]],[combined[1]])=="supported")
    check("planned seed table rows", 10*3*3*24==2160, 10*3*3*24, 2160)
    check("planned per-round pooled rows", 10*3*24==720, 10*3*24, 720)
    check("planned per-round scheme rows", 10*3==30, 10*3, 30)
    check("planned per-strategy symbols", 10*3*100000==3000000, 10*3*100000, 3000000)
    check("planned all-strategy symbols", 10*3*3*100000==9000000, 10*3*3*100000, 9000000)
    # A profile is selected once per round, not once per payload seed.
    counts = {4: 2,16: 3,64: 4}
    infeasible = 1
    check("synthetic per-tone frequency denominator is ten calibrations", sum(counts.values())+infeasible==10)
    check("three payload seeds must not triple selection frequency", 3*sum(counts.values())+infeasible!=10)


def main() -> None:
    result = {
        "scope": "Independent Python protocol arithmetic only; NOT MATLAB execution or experiment results.",
        "matlab_executed": False,
        "experimental_ber_generated": False,
        "synthetic_statistics_examples_not_experiment": True,
        "checks": CHECKS,
    }
    try:
        seed_checks()
        statistical_checks()
    finally:
        result["check_count"] = len(CHECKS)
        result["all_passed"] = bool(CHECKS) and all(row["status"]=="PASS" for row in CHECKS)
        file = ROOT/"validation/v12_contract_checks.json"
        file.parent.mkdir(exist_ok=True)
        file.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"Independent v1.2 arithmetic: {len(CHECKS)} checks PASS; no MATLAB or experimental BER.")


if __name__ == "__main__":
    main()
