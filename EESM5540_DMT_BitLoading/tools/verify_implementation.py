#!/usr/bin/env python3
"""Independent formula/source audit; NEVER a replacement for running MATLAB.

Uses Python/NumPy only to check identities and source-level frozen conventions.
It does not call the MATLAB implementation, qammod/qamdemod, estimate its
loading profile, measure BER, or generate the requested experiment results.
Run from the project directory: python3 tools/verify_implementation.py
"""

from __future__ import annotations

import math
from pathlib import Path
import re

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
NFFT, NCP = 64, 8
K = np.arange(1, 25)
FIR = np.array([0.25, 0.5, 0.25])
SIGMA_W2 = 10 ** (-29 / 10)
TARGET, MARGIN_DB = 1e-3, 1
MSET = (4, 16, 64)
RNG = np.random.default_rng(5540001)
LINES = [
    "Python diagnostic only; NOT MATLAB execution or experiment results.",
    "未在 MATLAB 执行。No MATLAB qammod/qamdemod, estimated profile or BER was tested.",
    "Independent RNG: NumPy default_rng seed 5540001 (not MATLAB streams).",
]


def check(name: str, observed: float, expected: float, tolerance: float) -> None:
    ok = bool(np.isfinite(observed) and abs(observed - expected) <= tolerance)
    LINES.append(
        f"{'PASS' if ok else 'FAIL'} | {name} | observed={observed:.16g} "
        f"| expected={expected:.16g} | tolerance={tolerance:.16g}"
    )
    if not ok:
        raise AssertionError(LINES[-1])


def source_checks() -> None:
    cfg = (ROOT / "private/dmt_default_config.m").read_text()
    expectations = {
        "NFFT": r"64", "NCP": r"8", "Fs": r"64e6", "Es": r"1",
        "Mset": r"\[4 16 64\]", "h": r"\[0\.25 0\.5 0\.25\]",
        "sigma_w2": r"10\^\(-29/10\)", "targetBER": r"1e-3",
        "margin_dB": r"1", "trainSymbols": r"1024",
        "probeSymbols": r"2048", "mainSymbols": r"100000",
        "smokeSymbols": r"2000", "chunkSize": r"2000",
        "seeds": r"\[11 22 33\]", "trainDataSeed": r"1701",
        "probeDataSeed": r"1702", "trainNoiseSeed": r"2701",
        "probeNoiseSeed": r"2702",
    }
    for field, value in expectations.items():
        matched = re.search(rf"cfg\.{field}\s*=\s*{value}\s*;", cfg) is not None
        check(f"source frozen cfg.{field}", float(matched), 1, 0)
    check("source frozen independent k1:24", float("cfg.k = (1:24).'" in cfg), 1, 0)

    tx = (ROOT / "private/dmt_transceive.m").read_text()
    frame = (ROOT / "private/dmt_random_frame.m").read_text()
    demod = (ROOT / "private/dmt_demod_errors.m").read_text()
    calibration = (ROOT / "private/dmt_calibrate.m").read_text()
    loading = (ROOT / "private/dmt_load_profiles.m").read_text()
    simulate = (ROOT / "private/dmt_simulate.m").read_text()
    required = {
        "unitary IFFT": "sqrt(cfg.NFFT)*ifft(X,[],1)" in tx,
        "unitary FFT": "fft(y,[],1)/sqrt(cfg.NFFT)" in tx,
        "serial FIR with state": "filter(cfg.h,1,tx(:),state)" in tx,
        "real receiver noise": "sqrt(cfg.sigma_w2)" in tx and "randn(noiseStream" in tx,
        "imaginary-part check precedes real": tx.index("stats.maxImag <=") < tx.index("x = real(xComplex)"),
        "conjugate MATLAB negative row": "X(cfg.NFFT-cfg.k(c)+1,:) = conj(X(cfg.k(c)+1,:))" in frame,
        "Gray QAM bit input": "'gray','InputType','bit'" in frame,
        "Gray QAM bit output": "'gray'" in demod and "'OutputType','bit'" in demod,
        "unit average constellation energy": "'UnitAveragePower',true" in frame and "'UnitAveragePower',true" in demod,
        "independent calibration data streams": "cfg.trainDataSeed" in calibration and "cfg.probeDataSeed" in calibration,
        "independent calibration noise streams": "cfg.trainNoiseSeed" in calibration and "cfg.probeNoiseSeed" in calibration,
        "probe residual uses estimated H": "ZB = Y./calibration.H_hat" in calibration,
        "loader uses gamma_hat": "gammaEff = calibration.gamma_hat/10^(cfg.margin_dB/10)" in loading,
        "payload ZF uses estimated H": "Z = Y./calibration.H_hat" in simulate,
        "formal receiver/loader do not use H_true": "H_true" not in loading + simulate,
        "chunked payload preserves FIR state": "[Y,stats,state] = dmt_transceive(cfg,X,state,noiseStream,true)" in simulate,
    }
    for name, matched in required.items():
        check(f"source {name}", float(matched), 1, 0)
    all_code = "\n".join(
        line for path in ROOT.rglob("*.m") for line in path.read_text().splitlines()
        if not line.lstrip().startswith("%")
    )
    for forbidden in (r"\bawgn\s*\(", r"\bparpool\s*\(", r"\bparfor\b", r"\bgpuArray\s*\("):
        check(f"source excludes {forbidden}", float(re.search(forbidden, all_code) is None), 1, 0)


def dmt_identities() -> None:
    # Arbitrary complex values deliberately avoid pretending to test MATLAB QAM.
    n_symbols = 137
    positive = (RNG.standard_normal((24, n_symbols)) +
                1j * RNG.standard_normal((24, n_symbols))) / math.sqrt(2)
    frequency = np.zeros((NFFT, n_symbols), complex)
    frequency[K] = positive
    frequency[NFFT - K] = positive.conj()
    mirror = np.r_[0, np.arange(NFFT - 1, 0, -1)]
    check("Hermitian relationship", np.max(np.abs(frequency - frequency[mirror].conj())), 0, 1e-13)
    time_complex = math.sqrt(NFFT) * np.fft.ifft(frequency, axis=0)
    check("IFFT imaginary part before real()", np.max(np.abs(time_complex.imag)), 0, 1e-13)
    time = time_complex.real
    check("unitary Parseval maximum symbol error", np.max(np.abs(np.sum(time**2, axis=0) - np.sum(abs(frequency)**2, axis=0))), 0, 1e-12)
    cp_time = np.vstack([time[-NCP:], time])
    check("CP sample count", cp_time.shape[0] - NFFT, NCP, 0)
    check("CP memory coverage", float(NCP >= len(FIR) - 1), 1, 0)
    serial = cp_time.ravel(order="F")
    filtered = np.convolve(serial, FIR, mode="full")[:len(serial)]
    received = filtered.reshape((NFFT + NCP, n_symbols), order="F")[NCP:]
    observed = np.fft.fft(received, axis=0) / math.sqrt(NFFT)
    true_h = np.fft.fft(FIR, n=NFFT)
    check("linear FIR + CP: Y=H_true*X", np.max(abs(observed - true_h[:, None] * frequency)), 0, 1e-12)

    # Independent causal direct-form state implementation, split mid-stream.
    history = np.zeros(len(FIR) - 1)
    chunks = []
    for part in np.array_split(serial, [72 * 17, 72 * 83]):
        extended = np.concatenate([history, part])
        full = np.convolve(extended, FIR, mode="full")
        chunks.append(full[len(history):len(history) + len(part)])
        history = extended[-(len(FIR) - 1):].copy()
    check("FIR chunk-state continuity", np.max(abs(np.concatenate(chunks) - filtered)), 0, 1e-13)
    formula_h = np.exp(-1j * 2 * np.pi * K / NFFT) * np.cos(np.pi * K / NFFT) ** 2
    check("FIR FFT vs closed-form response", np.max(abs(true_h[K] - formula_h)), 0, 1e-14)


def noise_identity() -> None:
    # Independent transform-variance check, NOT a QAM/BER experiment.
    complex_sum = np.zeros(24)
    real_sum = np.zeros(24)
    imag_sum = np.zeros(24)
    count = 0
    for _ in range(10):
        noise = math.sqrt(SIGMA_W2) * RNG.standard_normal((NFFT, 2000))
        spectrum = np.fft.fft(noise, axis=0)[K] / math.sqrt(NFFT)
        complex_sum += np.sum(abs(spectrum)**2, axis=1)
        real_sum += np.sum(spectrum.real**2, axis=1)
        imag_sum += np.sum(spectrum.imag**2, axis=1)
        count += spectrum.shape[1]
    for name, sums, expected in (
        ("positive complex FFT-noise variance", complex_sum, SIGMA_W2),
        ("positive real FFT-noise variance", real_sum, SIGMA_W2 / 2),
        ("positive imaginary FFT-noise variance", imag_sum, SIGMA_W2 / 2),
    ):
        check(f"{name}: max relative error over 24 bins", np.max(abs(sums / count / expected - 1)), 0, 0.04)


def analytical_diagnostics() -> None:
    gamma = np.cos(np.pi * K / NFFT)**4 / SIGMA_W2
    db = 10 * np.log10(gamma)
    check("analytic SNR minimum dB (not measured)", db.min(), 12.3135864, 1e-7)
    check("analytic SNR maximum dB (not measured)", db.max(), 28.9790623, 1e-7)
    gamma_eff = gamma / 10**(MARGIN_DB / 10)
    allowed = np.empty((24, 3), bool)
    for c, value in enumerate(gamma_eff):
        for j, order in enumerate(MSET):
            q = 0.5 * math.erfc(math.sqrt(3 * value / (order - 1)) / math.sqrt(2))
            ber_approx = 4 / math.log2(order) * (1 - 1 / math.sqrt(order)) * q
            allowed[c, j] = ber_approx <= TARGET
    theory_profile = np.array([max(m for m, ok in zip(MSET, row) if ok) for row in allowed])
    uniform = max(m for m, ok in zip(MSET, allowed.all(axis=0)) if ok)
    expected_profile = np.array([64] * 15 + [16] * 5 + [4] * 4)
    check("analytic-only profile diagnostic (not estimated profile)", float(np.array_equal(theory_profile, expected_profile)), 1, 0)
    loaded_b = np.log2(theory_profile).sum()
    uniform_b = 24 * math.log2(uniform)
    check("analytic loaded bits/DMT symbol", loaded_b, 118, 0)
    check("analytic uniform bits/DMT symbol", uniform_b, 48, 0)
    symbol_time = (NFFT + NCP) / 64e6
    LINES.append(f"DIAGNOSTIC ONLY | analytic payload rates Mbit/s: {loaded_b / symbol_time / 1e6:.10g}, {uniform_b / symbol_time / 1e6:.10g}")
    check("expected useful electrical energy", 2 * len(K), 48, 0)
    check("expected CP electrical energy", NCP * 2 * len(K) / NFFT, 6, 0)
    check("expected total electrical energy", (NFFT + NCP) * 2 * len(K) / NFFT, 54, 0)
    check("expected sample power", 2 * len(K) / NFFT, 0.75, 0)
    check("symbol time seconds", symbol_time, 1.125e-6, 1e-20)
    check("one-time initialization duration seconds", 3072 * symbol_time, 0.003456, 1e-15)


def wilson_diagnostics() -> None:
    z = 1.96

    def wilson(errors: int, count: int) -> tuple[float, float]:
        p = errors / count
        d = 1 + z*z / count
        center = (p + z*z / (2 * count)) / d
        radius = z * math.sqrt(p * (1-p) / count + z*z / (4 * count*count)) / d
        return max(0, center-radius), min(1, center+radius)

    for n in (4000, 600000, 1800000):
        low, high = wilson(0, n)
        check(f"Wilson zero-error lower bound n={n}", low, 0, 1e-15)
        check(f"Wilson zero-error upper bound n={n}", high, z*z / (n + z*z), 1e-15)
        reversed_low, reversed_high = wilson(n, n)
        check(f"Wilson count complement low n={n}", reversed_low, 1-high, 1e-15)
        check(f"Wilson count complement high n={n}", reversed_high, 1, 1e-15)
    low, high = wilson(10, 10000)
    check("Wilson nonzero count covers observed fraction", float(low < 0.001 < high), 1, 0)


def main() -> None:
    try:
        source_checks()
        dmt_identities()
        noise_identity()
        analytical_diagnostics()
        wilson_diagnostics()
        LINES.append("PASS: all independent checks completed. MATLAB readiness and experiment results remain UNVERIFIED.")
    finally:
        output = ROOT / "validation/python_diagnostics.txt"
        output.parent.mkdir(exist_ok=True)
        output.write_text("\n".join(LINES) + "\n", encoding="utf-8")
        print("\n".join(LINES))


if __name__ == "__main__":
    main()
