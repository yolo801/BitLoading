"""Independent numerical check of the v2 CP/FIR/FFT indexing, using NumPy and SciPy."""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from scipy.signal import lfilter

fit_path = Path(sys.argv[1])
h = np.array(json.loads(fit_path.read_text())["taps"])
N, CP = 64, 8
k = np.arange(1, 25)
bias = 1.0
sigma_ref = np.sqrt(2 * k.size / N)
gain = 0.25 * bias / (4 * sigma_ref)
group_sizes = (7, 1024, 13)
assert CP >= len(h) - 1
assert abs(h.sum() - 1) < 1e-12

def generate(group_size, stream):
    box = stream.choice([-1, 1], (2, len(k), group_size))
    return (box[0] + 1j * box[1]) / np.sqrt(2)

def transmitter(symbols):
    bins = np.zeros((N, symbols.shape[1]), dtype=np.complex128)
    bins[k] = symbols
    bins[-k] = symbols.conj()
    samples = np.sqrt(N) * np.fft.ifft(bins, axis=0)
    assert np.max(np.abs(samples.imag)) < 1e-12
    cp_waveform = np.concatenate((samples[-CP:].real, samples.real), axis=0)
    optical = bias + gain * cp_waveform.ravel(order='F')
    assert np.min(optical) >= 0 and np.max(optical) <= 2
    return optical

def receiver(samples):
    symbols = samples.reshape((N + CP, -1), order='F')
    frequency = np.fft.fft(symbols[CP:], axis=0) / np.sqrt(N)
    return frequency[k]

training = np.random.default_rng(1500000001)
check = np.random.default_rng(1500000002)
sources = [generate(size, rng) for size, rng in zip(group_sizes, [training, check, check])]
serialized = list(map(transmitter, sources))
state = np.zeros(len(h) - 1)
analog = []
for samples in serialized:
    result, state = lfilter(h, [1.0], samples, zi=state)
    analog.append(result)
sample_error = np.max(np.abs(np.concatenate(analog) - np.convolve(np.concatenate(serialized), h)[:sum(map(len, serialized))]))
reset_difference = np.max(np.abs(analog[-1] - lfilter(h, [1.0], serialized[-1])))
observations = list(map(receiver, analog))
actual_H = gain * (np.exp(-2j * np.pi * np.outer(k, np.arange(len(h))) / N) @ h)
training_H = (observations[0] * sources[0].conj()).sum(axis=1) / (np.abs(sources[0]) ** 2).sum(axis=1)
training_error = np.max(np.abs(actual_H - training_H))
payload = np.concatenate(sources[1:], axis=1)
observation = np.concatenate(observations[1:], axis=1)
observed_response_error = np.max(np.abs(observation / payload - actual_H[:, None]))
zf = observation / training_H[:, None]
recovery_error = np.max(np.abs(zf - payload))
bit_errors = (np.sign(zf.real) != np.sign(payload.real)).sum() + (np.sign(zf.imag) != np.sign(payload.imag)).sum()
assert max(sample_error, training_error, observed_response_error, recovery_error) <= 5e-11
assert reset_difference > 5e-11 and bit_errors == 0
print(json.dumps({
    "engine": "Independent NumPy and SciPy indexing check",
    "scope": "Mathematical analogue. No MATLAB code, MATLAB preflight, or formal payload ran.",
    "fit_summary_sha256": hashlib.sha256(fit_path.read_bytes()).hexdigest(),
    "group_sizes_symbols": group_sizes,
    "CP_samples": CP,
    "fft": N,
    "one_based_first_fft_sample": CP+1,
    "total_tested_fixture_bits": 2 * payload.size,
    "fixture_bit_errors": int(bit_errors),
    "max_tx_sample": max(map(np.max, serialized)),
    "min_tx_sample": min(map(np.min, serialized)),
    "max_streamed_sample_difference": sample_error,
    "max_tail_carried_state_vs_reset_difference": reset_difference,
    "max_training_complex_gain_error": training_error,
    "max_observed_complex_gain_error": observed_response_error,
    "max_equalized_symbol_error": recovery_error,
}, indent=2))
