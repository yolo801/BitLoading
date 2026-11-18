#!/usr/bin/env python3
"""Independent design arithmetic and optional CSV seed-plan audit.

The default run uses numeric fixtures and an independent enumeration. It
does not run MATLAB or synthesize experiment outcomes. Add --plan and
--phase to compare an actual MATLAB-exported seed plan after a run.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import csv
from dataclasses import dataclass
from hashlib import sha256
import math
from pathlib import Path

POWERS = (0.6, 0.8, 1.0, 1.2, 1.4)
ADCS = (4, 6, 8)
SCHEMES = ("FixedQPSK", "Fixed64QAM", "ValidatedLoading")
NATIVE_BASE = {"formal": 900_000_000, "preflight": 1_100_000_000}
CHECKS: list[str] = []


def check(label: str, ok: bool) -> None:
    if not ok:
        raise AssertionError(label)
    CHECKS.append(label)


@dataclass(frozen=True)
class SeedRow:
    condition: int
    power: float
    q: int
    calibration: int
    scheme: str
    round: int
    role: str
    slot: int | None
    data: int
    noise: int | None

    def identity(self) -> tuple:
        return (self.condition, self.calibration, self.scheme, self.round, self.role, self.slot)


def enumerate_rows(phase: str) -> list[SeedRow]:
    rows = []
    for pidx, p in enumerate(POWERS, 1):
        for qidx, q in enumerate(ADCS, 1):
            if phase == "preflight" and (p, q) not in {(1.0, 8), (1.2, 6)}:
                continue
            cid = (pidx - 1) * len(ADCS) + qidx
            for c in range(1, 6 if phase == "formal" else 2):
                common = NATIVE_BASE[phase] + 1_000_000 * pidx + 10_000 * c
                specific = common + 1_000 * qidx

                def record(scheme, r, role, slot, data, noise=None):
                    rows.append(SeedRow(cid, p, q, c, scheme, r, role, slot, data, noise))

                record("Shared", 0, "initial_power", None, specific + 1)
                record("Shared", 0, "A0", None, specific + 11, specific + 12)
                record("Shared", 0, "B0", None, specific + 21, specific + 22)
                for sidx, scheme in enumerate(SCHEMES[:2], 1):
                    branch = common + 100 * sidx
                    record(scheme, 1, "power", None, branch + 1)
                    record(scheme, 1, "Ar", None, branch + 11, branch + 12)
                    for j in (1, 2):
                        record(scheme, 0, "payload", j, branch + 20 + j, common + 300 + j)
                for r in range(1, 5):
                    branch = specific + 100 * r
                    for role, offset in (("power", 1), ("Ar", 11), ("Dr", 21)):
                        record(SCHEMES[2], r, role, None, branch + offset,
                               None if role == "power" else branch + offset + 1)
                for j in (1, 2):
                    record(SCHEMES[2], 0, "payload", j, specific + 500 + j, common + 300 + j)
    return rows


def pairing_key(row: SeedRow, lane: str) -> tuple:
    if lane == "noise" and row.role == "payload":
        return ("common_payload_noise", row.power, row.calibration, row.slot)
    if row.scheme in SCHEMES[:2]:
        if (lane == "data" and row.role in {"power", "Ar", "payload"}) or (
                lane == "noise" and row.role == "Ar"):
            return ("fixed_cross_adc", row.power, row.calibration, row.scheme, row.role, row.slot)
    return row.identity()


def verify_pairing(phase: str, rows: list[SeedRow]) -> set[int]:
    payload_counts = Counter(r.scheme for r in rows if r.role == "payload")
    slots = 150 if phase == "formal" else 4
    check(f"{phase}: expected slots per strategy", payload_counts == {s: slots for s in SCHEMES})
    check(f"{phase}: unique logical rows", len({r.identity() for r in rows}) == len(rows))
    seeds_by_lane = {}
    for lane in ("data", "noise"):
        seeds_by_key = defaultdict(set)
        keys_by_seed = defaultdict(set)
        for row in rows:
            value = getattr(row, lane)
            if value is None:
                continue
            key = pairing_key(row, lane)
            seeds_by_key[key].add(value)
            keys_by_seed[value].add(key)
        check(f"{phase} {lane}: all intended pairings share one stream",
              all(len(v) == 1 for v in seeds_by_key.values()))
        check(f"{phase} {lane}: all repeats are intentional",
              all(len(v) == 1 for v in keys_by_seed.values()))
        seeds_by_lane[lane] = set(keys_by_seed)
    check(f"{phase}: data and noise separated", not seeds_by_lane["data"] & seeds_by_lane["noise"])
    check(f"{phase}: noise omitted only on TX calibration",
          all((r.noise is None) == (r.role in {"power", "initial_power"}) for r in rows))
    return seeds_by_lane["data"] | seeds_by_lane["noise"]


def check_actual_csv(path: Path, phase: str, expected: list[SeedRow]) -> None:
    loaded = []
    labels = {lane: defaultdict(set) for lane in ("data", "noise")}

    def optional_int(value: str) -> int | None:
        return None if value.strip().lower() in {"", "nan"} else int(float(value))

    with path.open(encoding="utf-8-sig", newline="") as handle:
        for r in csv.DictReader(handle):
            if r["phase"] != phase:
                raise AssertionError("CSV phase differs")
            row = SeedRow(int(r["condition_id"]), float(r["P_target"]), int(r["q"]),
                          int(r["calibration_id"]), r["scheme"], int(r["round"]), r["role"],
                          optional_int(r["payload_slot"]), int(r["data_seed"]),
                          optional_int(r["noise_seed"]))
            loaded.append(row)
            for lane in labels:
                value = getattr(row, lane)
                if value is not None:
                    labels[lane][value].add(r[f"{lane}_pair_key"])
    check("loaded plan matches the independent enumeration", Counter(loaded) == Counter(expected))
    for lane, mapping in labels.items():
        seed_counts = Counter(getattr(r, lane) for r in loaded)
        check(f"loaded {lane}: every recurring stream has one explicit label",
              all(len(keys) == 1 and "" not in keys
                  for seed, keys in mapping.items() if seed_counts[seed] > 1))


def wilson(error_count: int, total: int) -> tuple[float, float]:
    p = error_count / total
    z = 1.96
    d = 1 + z*z/total
    center = (p + z*z/(2*total))/d
    radius = z*math.sqrt(p*(1-p)/total + z*z/(4*total*total))/d
    return max(0.0, center-radius), min(1.0, center+radius)


def arithmetic_checks() -> None:
    lo, hi = -0.1, 2.1
    for q in ADCS:
        d = (hi-lo) / (2**q)

        def quantize(value: float) -> float:
            index = min(max(math.floor((value-lo)/d), 0), 2**q-1)
            return lo + (index+0.5)*d

        centers = [lo + (i+0.5)*d for i in range(2**q)]
        check(f"q{q}: ideal step and midpoint count", d == 2.2/(2**q) and
              {quantize(v) for v in centers} == set(centers))
        samples = [lo-1, lo, hi, hi+1]
        check(f"q{q}: saturated levels and strict out-of-range count",
              [quantize(y) for y in samples] == [centers[0]]*2 + [centers[-1]]*2 and
              sum(not lo <= y <= hi for y in samples) == 2)
    l, u = wilson(0, 600_000)
    check("zero error retains positive upper bound", l < 1e-18 and
          math.isclose(u, 1.96**2/(600_000+1.96**2), abs_tol=1e-18))
    check("strict equality cannot support a configuration", not u < u)
    e = 1_030 + 2_297
    n = 300_000 + 300_000
    check("bit counters pool as integers before the rule", (e, n) == (3327, 600_000) and wilson(e, n)[0] > 1e-3)
    check("individual power matches do not imply pair match",
          all(abs(p-1) <= .01 for p in (.991, 1.009)) and abs(.991-1.009) > .01)
    ts = 72/64e6
    check("single-cycle fixed overhead and nominal symbol duration", ts == 1.125e-6 and
          50_000*144/((50_000+1024)*ts) < 144/ts)
    check("main and diagnostic designs have separate slot budgets",
          (5*3*5*3*2, 2*2*5*2) == (450, 40))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path)
    parser.add_argument("--phase", choices=NATIVE_BASE)
    args = parser.parse_args()
    if bool(args.plan) != bool(args.phase):
        parser.error("--plan and --phase are used together")
    plans = {phase: enumerate_rows(phase) for phase in NATIVE_BASE}
    formal = verify_pairing("formal", plans["formal"])
    preflight = verify_pairing("preflight", plans["preflight"])
    check("formal, preflight and diagnostic namespaces separated",
          not formal & preflight and max(formal | preflight) < 1_300_000_000 and min(formal) >= 900_000_000)
    arithmetic_checks()
    if args.plan:
        check_actual_csv(args.plan, args.phase, plans[args.phase])
    root = Path(__file__).resolve().parents[1]
    manifest = root.parent / "validation" / "source_manifest_tradeoff_v1.csv"
    if manifest.is_file():
        with manifest.open(encoding="utf-8", newline="") as handle:
            source_rows = list(csv.DictReader(handle))
        for row in source_rows:
            path = root.parent / row["relative_path"]
            previous = path.read_bytes()
            if sha256(previous).hexdigest() != row["sha256"] or len(previous) != int(row["bytes"]):
                raise AssertionError(f"v1 source no longer matches recorded bytes: {path}")
        check("v1 source still matches its recorded manifest", bool(source_rows))
    adapted = {"dmt_to_validate.m"}  # Isolated arithmetic-order fix at power boundary.
    copied = [p for p in (root/"private").glob("*.m")
              if p.name not in adapted and (root.parent/"private"/p.name).is_file()]
    if copied:
        for path in copied:
            baseline = (root.parent / "private" / path.name).read_bytes()
            if path.name == "dmt_to_validate.m":
                baseline = baseline.replace(
                    b"relative=meanPower/condition.P_target-1;",
                    b"relative=(meanPower-condition.P_target)/condition.P_target;",
                )
            check(f"{path.name}: matches the documented v1 baseline or adaptation",
                  sha256(path.read_bytes()).digest() == sha256(baseline).digest())
    for label in CHECKS:
        print(f"PASS {label}")
    print(f"{len(CHECKS)} checks passed. MATLAB and experiment payloads were not run by this script.")


if __name__ == "__main__":
    main()
