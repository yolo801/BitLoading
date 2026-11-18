#!/usr/bin/env python3
"""Independently verify numeric VCSEL formal checkpoints and matching exports."""

import argparse
import csv
import hashlib
import json
import math
import re
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
from scipy.io import loadmat
from scipy.special import erfc


SCHEMES = ('UniformValidated', 'PerToneValidated')
ORDERS = np.array([4, 16, 64])
NAN = float('nan')


def require(condition, context):
    if not condition:
        raise ValueError(context)


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def mat(path):
    return loadmat(path, simplify_cells=True)['checkpoint']


def number(value):
    return float(value) if value not in ('', None) else NAN


def numeric(actual, expected, context):
    np.testing.assert_allclose(actual, expected, rtol=1e-10, atol=5e-13,
                               equal_nan=True, err_msg=context)


def row_matches(row, fields, context):
    for name, expected in fields.items():
        message = f'{context}.{name}'
        if isinstance(expected, str):
            require(row[name] == expected, message)
        elif isinstance(expected, (int, np.integer, bool, np.bool_)):
            require(number(row[name]) == expected, message)
        else:
            actual = number(row[name])
            require((math.isnan(actual) and math.isnan(expected)) or
                    math.isclose(actual, expected, rel_tol=1e-10, abs_tol=5e-13),
                    f'{message}: {actual} != {expected}')


def csv_rows(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.DictReader(stream))


def key_for(row, extra=()):
    numeric_fields = ('condition_id', 'calibration_id', *extra)
    values = [number(row[f]) for f in numeric_fields]
    base = tuple(int(v) if math.isfinite(v) else None for v in values)
    return (*base, row.get('strategy', ''), row.get('role', '') if 'role' in row else '')


class Export:
    """Require every checked key once and reject extra CSV rows."""

    def __init__(self, folder, name, extras=(), by_condition_only=False):
        self.name = name
        self.extras = extras
        self.by_condition_only = by_condition_only
        all_rows = csv_rows(folder / f'{name}.csv')
        self.rows = {self.key(row): row for row in all_rows}
        self.total = len(all_rows)
        require(len(self.rows) == self.total, f'{name}: duplicate CSV keys')

    def key(self, row):
        if self.by_condition_only:
            return int(row['condition_id']), row['strategy']
        return key_for(row, self.extras)

    def take(self, fields):
        key = self.key(fields)
        row = self.rows.pop(key)
        row_matches(row, fields, f'{self.name}{key}')
        return row

    def done(self):
        require(not self.rows, f'{self.name}: {len(self.rows)} unverified CSV rows')


def check_archive(run, archive):
    if archive is None:
        return None
    with zipfile.ZipFile(archive) as z:
        files = {i.filename: i for i in z.infolist() if not i.is_dir()}
        require(len(files) == sum(not i.is_dir() for i in z.infolist()), 'duplicate ZIP members')
        existing = {f'{run.name}/{f.relative_to(run).as_posix()}': f
                    for f in run.rglob('*') if f.is_file()}
        formal_members = {name for name in files if name.startswith(run.name+'/')}
        require(formal_members == set(existing), 'extracted formal file set differs from ZIP')
        other = sorted(set(files)-formal_members)
        require(z.testzip() is None, 'a member of the outer ZIP failed its CRC check')
        for name, f in existing.items():
            with z.open(files[name]) as stream:
                require(hashlib.file_digest(stream, 'sha256').hexdigest() == sha(f), name)
    return {'name': archive.name, 'sha256': sha(archive), 'files': len(files),
            'extracted_formal_files_verified': len(existing), 'other_members': other}


def check_sources(run, checkout, p):
    manifest = csv_rows(run / 'source_manifest.csv')
    patterns = ('*.m', 'private/*.m', 'tools/*.py')
    expected = sorted(f.relative_to(checkout).as_posix()
                      for pattern in patterns for f in checkout.glob(pattern))
    require([row['relative_path'] for row in manifest] == expected, 'production source file set differs')
    entries = []
    for row in manifest:
        name = row['relative_path']
        f = checkout / name
        digest = sha(f)
        require(digest == row['sha256'] and f.stat().st_size == int(row['bytes']), name)
        entries.append(f'{name} {digest}')
    actual = hashlib.sha256('\n'.join(entries).encode()).hexdigest()
    require(actual == p['source_id'], 'canonical source ID differs')
    channel = run / 'channel_evidence'
    source_channel = checkout / 'evidence'
    archived = {f.name: sha(f) for f in sorted(channel.iterdir()) if f.is_file()}
    require(archived == {f.name: sha(f) for f in source_channel.iterdir() if f.is_file()},
            'archived channel evidence differs from original source tree')
    fit = json.loads((channel / 'channel_fit.json').read_text())
    require(fit['passed'] and (fit['Fs_Hz'], fit['NFFT'], fit['NCP']) ==
            (p['cfg']['Fs'], p['cfg']['NFFT'], p['cfg']['NCP']), 'fit geometry/flag')
    np.testing.assert_array_equal(fit['active_k'], p['cfg']['k'])
    for name, digest in ((fit['source_csv'], fit['digitized_sha256']),
                         (fit['source_provenance'], fit['provenance_sha256']),
                         ('active_response.csv', fit['active_response_sha256'])):
        require(archived[name] == digest, 'fit input identity')
    h = {r['case_id']: r['taps'] for r in fit['cases']}
    for c in p['cfg']['conditions']:
        np.testing.assert_array_equal(c['h'], h[c['case_id']])
    return len(entries), archived


def check_receipts(run, p):
    mech_path = run / 'mechanical_checks.mat'
    m = mat(mech_path)
    mh = sha(mech_path)
    require(m['passed'] and m['config_hash'] == p['config_id'], 'mechanical receipt')
    require(all(q['passed'] for q in m['link'] + m['power']) and
            all(m[name]['passed'] for name in ('physical', 'adc', 'unreachable_power',
                                               'counters', 'checkpoint', 'strategy')),
            'mechanical subchecks')
    receipts = {}
    for phase, planned in (('preflight', 0), ('pilot', 24)):
        path = run / f'{phase}_gate_receipt.mat'
        digest = sha(path)
        r = mat(path)
        gate = p[f'{phase}_gate']
        require(digest == gate['receipt_sha256'] and mh == gate['mechanical_sha256'], 'gate hash')
        require(r['phase'] == phase and r['planned'] == planned and bool(r['valid']) and
                bool(r['data_integrity_valid']) and bool(r['acquisition_complete']) and
                r['source_id'] == p['source_id'] and r['config_id'] == p['config_id'] and
                r['mechanical_sha256'] == mh and r['incomplete'] == 0 and
                r['completed'] + r['design_rejected'] == planned, f'{phase} receipt')
        receipts[phase] = {'sha256': digest, 'planned': planned,
                           'completed': int(r['completed']), 'design_rejected': int(r['design_rejected'])}
    snapshot = mat(run / 'tables.mat')
    for name in ('phase', 'source_id', 'config_id', 'seed_id'):
        require(snapshot[name] == p[name], f'tables envelope {name}')
    return mh, receipts


def frozen_seeds(run, conditions, cfg):
    rows = csv_rows(run / 'seed_plan.csv')
    expected = []
    for c in conditions:
        for cal in range(1, cfg['calibration_count'] + 1):
            group = 3_100_000_000 + 100_000*c['condition_id'] + 10_000*cal

            def add(scheme, attempt, role, data, noise=NAN, slot=NAN, key=''):
                expected.append({'phase': 'formal', 'condition_id': int(c['condition_id']),
                                 'case_id': int(c['case_id']), 'swing': float(c['swing']),
                                 'P_target': int(c['P_target']), 'q': int(c['q']),
                                 'calibration_id': cal, 'scheme': scheme, 'round': attempt,
                                 'role': role, 'payload_slot': slot, 'data_seed': data,
                                 'noise_seed': noise, 'data_pair_key': '', 'noise_pair_key': key})

            add('Shared', 0, 'initial_power', group + 1)
            add('Shared', 0, 'A0', group + 11, group + 12)
            add('Shared', 0, 'B0', group + 21, group + 22)
            for index, scheme in enumerate(SCHEMES, 1):
                base = group + 1000*index
                for attempt in range(1, cfg['max_rounds'] + 1):
                    trial = base + 100*attempt
                    add(scheme, attempt, 'power', trial + 1)
                    add(scheme, attempt, 'Ar', trial + 11, trial + 12)
                    add(scheme, attempt, 'Dr', trial + 21, trial + 22)
                for slot in (1, 2):
                    add(scheme, 0, 'payload', base + 500 + slot, group + 900 + slot, slot,
                        f"formal_C{c['condition_id']}_R{cal}_S{slot}")
    require(len(expected) == len(rows), 'seed plan row count')
    for j, (actual, wanted) in enumerate(zip(rows, expected), 1):
        row_matches(actual, wanted, f'seed plan row {j}')
    return { (r['condition_id'], r['calibration_id'], r['scheme'], r['round'], r['role'],
              int(r['payload_slot']) if math.isfinite(r['payload_slot']) else None): r
            for r in expected }


def condition_matches(actual, c):
    for name in ('condition_id', 'case_id', 'swing', 'q', 'P_target'):
        require(actual[name] == c[name], f'condition {name}')
    np.testing.assert_array_equal(actual['h'], c['h'])


def wilson(e, n, z):
    rate = e/n
    denom = n + z*z
    middle = (e+z*z/2)/denom
    radius = z*np.sqrt(e*(1-rate)+z*z/4)/denom
    return rate, np.maximum(0, middle-radius), np.minimum(1, middle+radius)


def counts(m, M, n, z):
    e = np.asarray(m['error_bits'], dtype=float)
    tested = np.asarray(m['tested_bits'], dtype=float)
    np.testing.assert_array_equal(tested, n*np.log2(np.asarray(M,dtype=float)))
    require(np.all((0 <= e) & (e <= tested) & (e == np.floor(e))), 'integer BER numerator')
    return e.astype(np.int64), tested.astype(np.int64), *wilson(e, tested, z)


def physical(block, c, cfg):
    measured = 'metrics' in block
    m = block['metrics'] if measured else block
    size = int(block['symbols'])*(cfg['NFFT']+cfg['NCP'])
    peak = cfg['P_peak']
    bins = np.array(m['tx_hist_counts'])
    require(size > 0 and int(m['sample_count']) == size and len(bins) == m['tx_hist_bins'] == 4096 and
            m['tx_hist_max'] == peak and np.all((bins >= 0) & (bins == np.floor(bins))) and
            bins.sum() == size, 'physical counts/histogram do not account for CP')
    require(m['commanded_swing'] == c['swing'] and m['commanded_peak'] == c['P_target']*c['swing'],
            'drive command differs')
    mean = m['tx_sum']/size
    relative = (mean - c['P_target'])/c['P_target']
    width = peak/len(bins)
    lo, hi = (np.searchsorted(bins.cumsum(), np.ceil(size*np.array([.01, .99]))) + .5)*width
    swing = (hi-lo)/(2*mean)
    rms = np.sqrt(m['drive_ac_sq_sum']/size)
    papr = 10*np.log10((m['drive_ac_peak_abs']/rms)**2)
    require(math.isfinite(mean) and 0 < mean <= peak and math.isfinite(rms) and rms > 0, 'optical or drive mean')
    numeric([lo, hi, swing, rms, papr], [m['tx_p01'], m['tx_p99'], m['observed_swing'],
                                        m['drive_ac_rms'], m['drive_papr_dB']], 'physical summary')
    low_clip, high_clip = m['lower_clip_count'], m['upper_clip_count']
    require(low_clip >= 0 and high_clip >= 0 and low_clip+high_clip <= size and
            low_clip == int(low_clip) and high_clip == int(high_clip), 'clip counters')
    sq = m['tx_sum_sq'] if measured else m['mean_square']*size
    low = m['tx_min'] if measured else m['minimum']
    high = m['tx_max'] if measured else m['peak']
    require(0 <= low <= mean + 1e-12 and mean - 1e-12 <= high <= peak and
            mean*mean - 1e-12 <= sq/size <= peak*mean + 1e-12, 'optical moments')
    r = {'samples': size, 'P_actual': mean, 'P_relative_error': relative, 'tx_sum': m['tx_sum'],
         'tx_sum_sq': sq, 'optical_second_moment': sq/size, 'P_min': low, 'P_max': high,
         'commanded_swing': c['swing'], 'commanded_peak': m['commanded_peak'],
         'observed_swing': swing, 'tx_p01': lo, 'tx_p99': hi, 'tx_hist_bin_width': width,
         'drive_ac_mean': m['drive_ac_sum']/size, 'drive_ac_rms': rms,
         'drive_ac_peak_abs': m['drive_ac_peak_abs'], 'drive_papr_dB': papr,
         'tx_low_count': int(low_clip), 'tx_high_count': int(high_clip),
         'tx_clip_rate': (low_clip+high_clip)/size, 'clip_error_sq_sum': NAN,
         'clip_error_rms': NAN, 'clip_excess_rms_when_clipped': NAN,
         'adc_low_count': NAN, 'adc_high_count': NAN, 'adc_oob_rate': NAN,
         'noise_mean': NAN, 'noise_second_moment': NAN}
    if measured:
        lows, highs = m['adc_low_count'], m['adc_high_count']
        clip_sq = m['clip_error_sq_sum']
        require(lows == int(lows) and highs == int(highs) and lows >= 0 and highs >= 0 and
                lows+highs <= size and clip_sq >= 0 and (low_clip+high_clip or clip_sq == 0),
                'ADC or clipping excess counters')
        r.update(adc_low_count=int(lows), adc_high_count=int(highs), adc_oob_rate=(lows+highs)/size,
                 noise_mean=m['noise_sum']/size, noise_second_moment=m['noise_sum_sq']/size,
                 clip_error_sq_sum=clip_sq, clip_error_rms=np.sqrt(clip_sq/size),
                 clip_excess_rms_when_clipped=np.sqrt(clip_sq/(low_clip+high_clip))
                 if low_clip+high_clip else NAN)
    else:
        numeric(mean, block['actual_mean'], 'TX calibrated optical power')
        require(abs(relative) <= cfg['power_cal_tolerance'], 'TX power calibration tolerance')
    return r


def decision(scheme, attempt, M, lo, hi, target, cap):
    support = hi < target
    if support.all():
        return 'accepted', 'validated', M
    at_floor = ~support & (M == 4)
    if at_floor.any():
        why = 'minimum_order_ber_failed' if (lo[at_floor] > target).any() else 'minimum_order_inconclusive'
        return 'design_rejected', why, []
    if attempt == cap:
        return 'design_rejected', 'round_budget_exhausted', []
    if scheme == SCHEMES[0]:
        return 'retest', 'try_next_uniform_order', np.full(M.shape, ORDERS[-1-attempt])
    return 'retest', 'lower_unsupported_tones', np.where(support, M, M//4)


class Audit:
    def __init__(self, folder, cfg, p):
        self.folder = folder
        self.cfg = cfg
        self.p = p
        self.conditions = cfg['conditions']
        self.k = np.asarray(cfg['k'])
        self.freq = self.k*cfg['Fs']/cfg['NFFT']/1e9
        self.T = (cfg['NFFT']+cfg['NCP'])/cfg['Fs']
        self.z = cfg['Wilson_z']
        self.target = cfg['targetBER']
        self.plan = frozen_seeds(folder, self.conditions, cfg)
        definitions = {'status': ('payload_slot',), 'summary': (), 'overhead': (),
                       'seed': ('payload_slot', 'k'), 'pool': ('k',), 'snr': ('k',),
                       'design_rounds': ('round', 'k'), 'power_adc': ('payload_slot',),
                       'profiles': ('k',), 'events': ('round', 'payload_slot'),
                       'scenario': (), 'pair_gains': ()}
        self.exports = {name: Export(folder, name, extra, name == 'scenario')
                        for name, extra in definitions.items()}
        self.counted_files = set()
        self.acc = Counter()
        self.frames = []
        self.payloads = []
        self.support_pairs = []
        self.noise = {}
        self.frame_lookup = {}

    def emit(self, name, fields):
        return self.exports[name].take(fields)

    def checkpoint(self, kind, index):
        file = self.folder / 'checkpoints' / f'{kind.lower()}_{index:04d}.mat'
        r = mat(file)
        identity = {'kind': kind, 'index': index, **{f: self.p[f] for f in
                    ('phase', 'source_id', 'config_id', 'seed_id')}}
        require(r['identity'] == identity and re.fullmatch('[0-9a-f]{64}', r['data_hash']), file.name)
        self.counted_files.add(file.name)
        return r['data'], r['data_hash']

    @staticmethod
    def identity(c, cal, scheme):
        return {'phase': 'formal', 'condition_id': int(c['condition_id']), 'case_id': int(c['case_id']),
                'swing': float(c['swing']), 'q': int(c['q']), 'P_target': c['P_target'],
                'calibration_id': cal, 'strategy': scheme}

    def select(self, c, cal, scheme, role, attempt, slot):
        return self.plan[(c['condition_id'], cal, scheme, attempt, role, slot)]

    def event(self, c, cal, scheme, role, round_, slot, b, M, size, bias=None, H=None):
        identity = self.identity(c, cal, scheme)
        seed = self.select(c, cal, scheme, role, round_, slot)
        tx = role in ('power', 'initial_power')
        require(b['symbols'] == size, f'{identity} {role}: actual symbol count')
        np.testing.assert_array_equal(b['M'], M)
        if tx:
            require(b['seed'] == b['data_seed'] == seed['data_seed'] and
                    b['target'] == c['P_target'] and b['reachable'] and b['monotone'], 'TX seed/caliper')
        else:
            condition_matches(b['condition'], c)
            s = b['seeds']
            for f in ('phase', 'condition_id', 'case_id', 'swing', 'q', 'P_target', 'calibration_id',
                      'scheme', 'round', 'role', 'payload_slot', 'data_seed', 'noise_seed'):
                expected = seed[f]
                require(s[f] == expected or (isinstance(expected, float) and math.isnan(expected) and
                        math.isnan(s[f])), f'{identity} {role}: seed {f}')
            require(b['phase'] == 'formal' and b['role'] == role and b['q'] == c['q'] and
                    b['b'] == bias and b['nSymbols_requested'] == size and not b['adc_bypass'] and
                    b['add_noise'] and b['noise_variance'] == self.cfg['noise_variance'], 'measurement settings')
            np.testing.assert_array_equal(b['adc_range'], self.cfg['adc_range'])
            np.testing.assert_array_equal(b['M_rx'], M)
            if H is None:
                require(b['training'] and not np.size(b['H_used']) and
                        np.isnan(b['error_bits']).all() and np.isnan(b['tested_bits']).all(), 'LS training scope')
                numeric(b['H_hat'], b['received_cross_sum']/b['known_energy_sum'], 'LS estimate')
            else:
                require(not b['training'], 'payload/validation cannot train H')
                np.testing.assert_array_equal(b['H_used'], H)
                np.testing.assert_array_equal(b['H_hat'], H)
                residual = b['received_energy_sum']/np.abs(H)**2 + b['known_energy_sum'] - \
                    2*np.real(b['received_cross_sum']/H)
                np.testing.assert_allclose(b['residual_sum_sq'], residual, rtol=1e-8, atol=5e-10)
                numeric(b['gamma'], b['known_energy_sum']/b['residual_sum_sq'], 'effective SNR')
        m = physical(b, c, self.cfg)
        payload = role == 'payload'
        self.emit('events', {**identity, **m, 'role': role, 'round': round_,
                  'payload_slot': slot if slot is not None else NAN, 'symbols': size,
                  'data_seed': seed['data_seed'], 'noise_seed': seed['noise_seed'],
                  'compute_seconds': b['compute_seconds'], 'forward_setup_symbols': 0 if tx or payload else size,
                  'forward_payload_symbols': size if payload else 0, 'tx_only_symbols': size if tx else 0})
        return m

    def initial(self, c, cal, index):
        a, digest = self.checkpoint('Shared', index)
        condition_matches(a['condition'], c)
        require(a['status'] == 'complete' and a['phase'] == 'formal' and a['calibration_id'] == cal,
                'shared calibration identity')
        M = np.full(self.k.shape, 4)
        np.testing.assert_array_equal(a['M0'], M)
        self.event(c, cal, 'Shared', 'initial_power', 0, None, a['power0'], M, self.cfg['power_cal_symbols'])
        self.event(c, cal, 'Shared', 'A0', 0, None, a['A0'], M, self.cfg['initial_A_symbols'], a['power0']['b'])
        H = a['A0']['H_hat']
        np.testing.assert_array_equal(H, a['H0'])
        self.event(c, cal, 'Shared', 'B0', 0, None, a['B0'], M, self.cfg['initial_B_symbols'], a['power0']['b'], H)
        gamma = a['B0']['known_energy_sum']/a['B0']['residual_sum_sq']
        numeric(a['gamma_B'], gamma, 'shared B0 gamma')
        for field in ('feedback_sent', 'feedback_received'):
            numeric(a[field]['gamma_B'], gamma, 'shared quality feedback')
        require(a['feedback_hash_sent'] == a['feedback_hash_received'], 'shared quality feedback identity')
        id_ = self.identity(c, cal, 'Shared')
        snr = 10*np.log10(gamma)
        for j, (tone, f) in enumerate(zip(self.k, self.freq)):
            self.emit('snr', {**id_, 'k': int(tone), 'frequency_GHz': f, 'gamma_B0': gamma[j], 'SNR_dB': snr[j],
                      'probe_data_seed': a['B0']['seeds']['data_seed'], 'probe_noise_seed': a['B0']['seeds']['noise_seed']})
        return a, digest, gamma

    def counter_rows(self, export, identity, M, length, slot, count_arrays, columns=None):
        e, n, ber, lo, hi = count_arrays
        for j, (tone, f) in enumerate(zip(self.k, self.freq)):
            self.emit(export, {**identity, 'k': int(tone), 'frequency_GHz': f, 'M': int(M[j]),
                      'payload_slot': slot, 'actual_symbols': length,
                      'error_bits': int(e[j]), 'tested_bits': int(n[j]), 'BER': ber[j],
                      'CI_low': lo[j], 'CI_high': hi[j], **(columns(j) if columns else {})})

    def design(self, c, cal, scheme, index, initial, a_hash, gamma):
        d, digest = self.checkpoint('Design', index)
        id_ = self.identity(c, cal, scheme)
        condition_matches(d['condition'], c)
        require(d['phase'] == 'formal' and d['calibration_id'] == cal and d['scheme'] == scheme and
                d['initial_shared_hash'] == a_hash, 'design origin')
        numeric(d['initial_gamma_B'], gamma, 'frozen design B0')
        scale = gamma[:, None]/10**(self.cfg['margin_dB']/10)
        prediction = 2/np.log2(ORDERS)*(1-1/np.sqrt(ORDERS)) * erfc(np.sqrt(3*scale/(ORDERS-1))/np.sqrt(2))
        allowed = prediction <= self.target
        numeric(d['predicted_BER_design'], prediction, 'initial BER approximation')
        np.testing.assert_array_equal(d['initial_allowed'], allowed)
        M = np.full(self.k.shape, 64) if scheme == SCHEMES[0] else np.where(allowed[:, 2], 64, np.where(allowed[:, 1], 16, 4))
        np.testing.assert_array_equal(d['initial_M'], M)
        rounds = d['rounds'] if isinstance(d['rounds'], list) else [d['rounds']]
        o = {'A0_symbols': initial['A0']['symbols'], 'B0_symbols': initial['B0']['symbols'],
             'Ar_symbols': 0, 'Dr_symbols': 0, 'tx_only_symbols': initial['power0']['symbols'],
             'tx_only_seconds': initial['power0']['compute_seconds'], 'attempts': len(rounds),
             'training_compute_s': initial['A0']['compute_seconds'], 'probe_compute_s': initial['B0']['compute_seconds'],
             'validation_compute_s': 0., 'loading_compute_s': d['costs']['loading_seconds'],
             'design_compute_s': d['costs']['design_seconds'], 'feedback_scalars': len(self.k),
             'validation_status_elements': len(rounds)*len(self.k)}
        require(1 <= len(rounds) <= self.cfg['max_rounds'], 'real validation budget')
        for j, r in enumerate(rounds, 1):
            require(r['round'] == j, 'actual sequential D rounds')
            np.testing.assert_array_equal(r['M'], M)
            self.agreement(r['candidate_tx'], r['candidate_rx'], r['candidate_ack'], id_, M, 'candidate', j, a_hash)
            b = r['power']['b']
            self.event(c, cal, scheme, 'power', j, None, r['power'], M, self.cfg['power_cal_symbols'])
            self.event(c, cal, scheme, 'Ar', j, None, r['Ar'], M, self.cfg['design_A_symbols'], b)
            self.event(c, cal, scheme, 'Dr', j, None, r['Dr'], M, self.cfg['design_D_symbols'], b, r['Ar']['H_hat'])
            for name, block, field in (('Ar_symbols', 'Ar', 'symbols'), ('Dr_symbols', 'Dr', 'symbols'),
                                       ('tx_only_symbols', 'power', 'symbols'), ('tx_only_seconds', 'power', 'compute_seconds'),
                                       ('training_compute_s', 'Ar', 'compute_seconds'), ('validation_compute_s', 'Dr', 'compute_seconds')):
                o[name] += r[block][field]
            e, n, ber, lo, hi = counts(r['Dr'], M, self.cfg['design_D_symbols'], self.z)
            numeric(r['CI_low'], lo, 'Dr Wilson lower')
            numeric(r['CI_high'], hi, 'Dr Wilson upper')
            np.testing.assert_array_equal(r['supported_k'], hi < self.target)
            state, why, next_M = decision(scheme, j, M, lo, hi, self.target, self.cfg['max_rounds'])
            np.testing.assert_array_equal(next_M, r['proposed_next_M'])
            require(r['status'] == state and r['reason'] == why and (state == 'retest') == (j < len(rounds)),
                    'candidate order, strict Dr support or terminal cause')
            extra = {'round': j, 'round_state': state, 'round_reason': why, 'candidate_b': b,
                     'power_seed': r['power']['seed'], 'training_data_seed': r['Ar']['seeds']['data_seed'],
                     'training_noise_seed': r['Ar']['seeds']['noise_seed'], 'configuration_hash': '',
                     'validation_data_seed': r['Dr']['seeds']['data_seed'], 'validation_noise_seed': r['Dr']['seeds']['noise_seed']}
            self.counter_rows('design_rounds', id_, M, r['Dr']['symbols'], NAN, (e, n, ber, lo, hi),
                              lambda k: {**extra, 'supported': bool(hi[k] < self.target)})
            M = next_M
        accepted = state == 'accepted'
        require(d['status'] == state and d['reason'] == why, 'terminal design does not match last round')
        o['loading_table_elements'] = (len(rounds)+accepted)*len(self.k)
        o['acknowledgements'] = len(rounds)+accepted
        o['setup_symbols'] = sum(o[n] for n in ('A0_symbols','B0_symbols','Ar_symbols','Dr_symbols'))
        o['T_setup_s'] = o['setup_symbols']*self.T+self.cfg['control_delay']
        for f in ('loading_table_elements', 'acknowledgements', 'validation_status_elements', 'feedback_scalars'):
            a = {'loading_table_elements': 'loading_table_entries', 'acknowledgements': 'configuration_ack_count',
                 'validation_status_elements': 'validation_status_entries', 'feedback_scalars': 'initial_quality_scalar_count'}
            require(d['feedback'][a[f]] == o[f], f'feedback counts {f}')
        self.emit('overhead', {**id_, **o})
        if accepted:
            np.testing.assert_array_equal(d['M'], M)
            np.testing.assert_array_equal(d['H_hat'], r['Ar']['H_hat'])
            require(d['b'] == r['power']['b'] == d['final_tx']['b'], 'accepted bias')
            self.agreement(d['final_tx'], d['final_rx'], d['ack'], id_, M, 'accepted', len(rounds), a_hash)
        else:
            require(not np.size(d['M']) and not d['final_tx'] and not d['final_rx'], 'rejected design is authorized')
        return d, digest, o

    @staticmethod
    def agreement(tx, rx, ack, identity, M, stage, round_, shared_hash):
        require(tx.keys() == rx.keys() and ack['accepted'] and ack['profile_id'] == tx['profile_id'] and
                tx['initial_shared_hash'] == shared_hash, 'Tx/Rx configuration and ACK')
        for name in tx:
            if isinstance(tx[name], np.ndarray):
                np.testing.assert_array_equal(tx[name], rx[name])
            else:
                require(tx[name] == rx[name], f'Tx/Rx {name}')
        for name in ('condition_id', 'case_id', 'swing', 'q', 'calibration_id', 'P_target', 'phase'):
            require(tx[name] == identity[name], f'Tx/Rx case {name}')
        require(tx['scheme'] == identity['strategy'] and tx['stage'] == stage and tx['round'] == round_,
                'Tx/Rx branch/stage/round')
        np.testing.assert_array_equal(tx['M'], M)
        np.testing.assert_array_equal(tx['bits_k'], np.log2(M))

    def payload(self, c, cal, scheme, index, d, d_hash, o):
        id_ = self.identity(c, cal, scheme)
        accepted = d['status'] == 'accepted'
        M = np.asarray(d['M'],dtype=float)
        config = d['ack']['configuration_hash'] if accepted else ''
        length = self.cfg['payload_symbols']
        sums = {'error_bits': np.zeros(self.k.shape, np.int64), 'tested_bits': np.zeros(self.k.shape, np.int64)}
        measured = []
        for slot in (1, 2):
            path = self.folder / 'checkpoints' / f'payload_{(index-1)*2+slot:04d}.mat'
            seed = self.select(c, cal, scheme, 'payload', 0, slot)
            status = {**id_, 'payload_slot': slot, 'planned_symbols': length,
                      'data_seed': seed['data_seed'], 'noise_seed': seed['noise_seed'],
                      'noise_pair_key': seed['noise_pair_key'], 'actual_symbols': NAN,
                      'tested_bits': NAN, 'error_bits': NAN, 'P_actual': NAN, 'power_match': False,
                      'configuration_hash': config, 'status': 'design_rejected', 'reason': d['reason']}
            require(path.is_file() == accepted, f'payload authorization {path.name}')
            if accepted:
                m, _ = self.checkpoint('Payload', (index-1)*2+slot)
                require(m['design_hash'] == d_hash and m['configuration_hash'] == config and
                        m['profile_id'] == d['final_tx']['profile_id'] and m['scheme'] == scheme and
                        m['calibration_id'] == cal and m['payload_slot'] == slot, 'frozen payload identity')
                physical_data = self.event(c, cal, scheme, 'payload', 0, slot, m, M, length, d['b'], d['H_hat'])
                p = physical_data['P_actual']
                match = abs((p-c['P_target'])/c['P_target']) <= self.cfg['payload_power_tolerance']
                require(bool(m['power_match']) == match, 'payload power decision')
                numeric([m['power_actual'], m['power_relative_error']], [p, (p-c['P_target'])/c['P_target']], 'payload power')
                signature = tuple(m['metrics'][f] for f in ('sample_count', 'noise_sum', 'noise_sum_sq'))
                old = self.noise.setdefault(seed['noise_seed'], signature)
                require(old == signature, 'observed paired noise differs')
                c_arrays = counts(m, M, length, self.z)
                e, n = c_arrays[:2]
                sums['error_bits'] += e
                sums['tested_bits'] += n
                data = {name: seed[name] for name in ('data_seed','noise_seed')}
                data['configuration_hash'] = config
                self.counter_rows('seed', id_, M, length, slot, c_arrays, lambda k: data)
                status.update(actual_symbols=length, status='completed', reason='',
                              error_bits=int(e.sum()), tested_bits=int(n.sum()), P_actual=p,
                              power_match=match)
                observed = {**id_, **physical_data, 'payload_slot': slot, 'power_match': match}
                self.emit('power_adc', observed)
                self.payloads.append(observed)
                measured.append(observed)
                self.acc['payload_samples'] += physical_data['samples']
                self.acc['tx_clipped_samples'] += physical_data['tx_low_count'] + physical_data['tx_high_count']
                self.acc['adc_oob_samples'] += physical_data['adc_low_count'] + physical_data['adc_high_count']
                self.acc['tested_bits'] += int(n.sum())
                self.acc['error_bits'] += int(e.sum())
            self.emit('status', status)
            self.acc[status['status']] += 1
        summary = {**id_, 'state': 'design_rejected', 'design_state': d['status'], 'design_reason': d['reason'],
                   'BER_state': 'unmeasured', 'power_match': False, 'bits_per_symbol': NAN, 'R_nominal': NAN,
                   'R_cycle': NAN, 'configuration_hash': config, 'payload_slots_completed': len(measured),
                   'Umax': NAN, 'Umax_over_target': NAN, 'total_error_bits': NAN, 'total_tested_bits': NAN,
                   'overall_BER': NAN, 'P_actual_min': NAN, 'P_actual_max': NAN, 'tx_clip_rate': NAN,
                   'adc_oob_rate': NAN, 'papr_dB_max': NAN, 'observed_swing_mean': NAN,
                   **{f:o[f] for f in ('setup_symbols', 'T_setup_s', 'attempts')}}
        if accepted:
            bits = int(np.log2(M).sum())
            for j, (tone, f) in enumerate(zip(self.k, self.freq)):
                self.emit('profiles', {**id_, 'k': int(tone), 'frequency_GHz': f, 'M': int(M[j]),
                          'bits_k': int(np.log2(M[j])), 'b': d['b'], 'configuration_hash': config})
            pooled = counts(sums, M, length*2, self.z)
            e, n, _, low, high = pooled
            self.counter_rows('pool', id_, M, length*2, NAN, pooled, lambda k: {'configuration_hash': config})
            ber = 'ber_failed' if (low>self.target).any() else 'supported' if (high<self.target).all() else 'inconclusive'
            match = all(r['power_match'] for r in measured)
            samples = sum(r['samples'] for r in measured)
            summary.update(state=ber if match else 'power_mismatch', BER_state=ber, power_match=match,
                           bits_per_symbol=bits, R_nominal=bits/self.T, R_cycle=length*bits/(length*self.T+o['T_setup_s']),
                           Umax=float(high.max()), Umax_over_target=float(high.max()/self.target),
                           total_error_bits=int(e.sum()), total_tested_bits=int(n.sum()), overall_BER=e.sum()/n.sum(),
                           P_actual_min=min(r['P_actual'] for r in measured), P_actual_max=max(r['P_actual'] for r in measured),
                           tx_clip_rate=sum(r['tx_low_count']+r['tx_high_count'] for r in measured)/samples,
                           adc_oob_rate=sum(r['adc_low_count']+r['adc_high_count'] for r in measured)/samples,
                           papr_dB_max=max(r['drive_papr_dB'] for r in measured),
                           observed_swing_mean=float(np.mean([r['observed_swing'] for r in measured])))
        self.emit('summary', summary)
        self.frames.append(summary)
        self.frame_lookup[(int(c['condition_id']), cal, scheme)] = (summary, measured)

    def scenario(self):
        scenarios = []
        for c in self.conditions:
            for scheme in SCHEMES:
                rows = [r for r in self.frames if r['condition_id'] == c['condition_id'] and r['strategy'] == scheme]
                counts_ = Counter(r['state'] for r in rows)
                state_fields = ('supported', 'ber_failed', 'inconclusive', 'power_mismatch', 'design_rejected',
                                'power_error', 'execution_error', 'incomplete')
                qualify = len(rows)==self.cfg['calibration_count'] and counts_['supported']==len(rows)
                observed = [r for r in rows if r['payload_slots_completed']==2]
                rates = [r['R_cycle'] for r in observed]
                capacity = [r['bits_per_symbol'] for r in observed]
                low, median, high = (min(rates), float(np.median(rates)), max(rates)) if rates else (NAN, NAN, NAN)
                r = {k:v for k,v in rows[0].items() if k in ('phase','condition_id','case_id','swing','q','P_target','strategy')}
                r.update({state+'_count':int(counts_[state]) for state in state_fields})
                r.update(status='qualified' if qualify else 'not_qualified', planned_calibrations=len(rows), qualified=qualify,
                         R_cycle_min=low if qualify else NAN, R_cycle_median=median if qualify else NAN,
                         R_cycle_max=high if qualify else NAN, observed_R_cycle_min=low,
                         observed_R_cycle_median=median, observed_R_cycle_max=high,
                         observed_rate_rounds=len(observed), P_actual_min=min((x['P_actual_min'] for x in observed),default=NAN),
                         P_actual_max=max((x['P_actual_max'] for x in observed),default=NAN),
                         attempt_median=float(np.median([x['attempts'] for x in rows])),
                         setup_median_s=float(np.median([x['T_setup_s'] for x in rows])),
                         tx_clip_rate_max=max((x['tx_clip_rate'] for x in observed),default=NAN),
                         adc_oob_rate_max=max((x['adc_oob_rate'] for x in observed),default=NAN),
                         bits_per_symbol_median=float(np.median(capacity)) if capacity else NAN)
                uniform = [2**(b/len(self.k)) for b in capacity] if scheme==SCHEMES[0] else []
                r.update(uniform_M_min=min(uniform,default=NAN), uniform_M_max=max(uniform,default=NAN))
                self.emit('scenario', r)
                scenarios.append(r)
        return scenarios

    def compare(self):
        for c in self.conditions:
            for cal in range(1, self.cfg['calibration_count']+1):
                u, u_slots = self.frame_lookup[(int(c['condition_id']), cal, SCHEMES[0])]
                p, p_slots = self.frame_lookup[(int(c['condition_id']), cal, SCHEMES[1])]
                complete=len(u_slots)==len(p_slots)==2
                matched=complete and all(a['power_match'] and b['power_match'] and
                    abs(a['P_actual']-b['P_actual'])<=c['P_target']*self.cfg['pair_power_tolerance']
                    for a,b in zip(u_slots,p_slots))
                qualifies=matched and u['state']==p['state']=='supported'
                r={k:u[k] for k in ('phase','condition_id','case_id','swing','q','P_target','calibration_id')}
                r.update(uniform_state=u['state'],pertone_state=p['state'],resource_match=matched,pair_qualified=qualifies,
                         status='qualified_pair' if qualifies else 'pair_unsent_or_incomplete' if not complete
                         else 'power_pair_mismatch' if not matched else 'not_both_supported',
                         uniform_R_cycle=u['R_cycle'],pertone_R_cycle=p['R_cycle'],
                         validated_delta_R_cycle=p['R_cycle']-u['R_cycle'] if qualifies else NAN,
                         validated_rate_ratio=p['R_cycle']/u['R_cycle'] if qualifies else NAN,
                         uniform_bits_per_symbol=u['bits_per_symbol'],pertone_bits_per_symbol=p['bits_per_symbol'],
                         uniform_T_setup_s=u['T_setup_s'],pertone_T_setup_s=p['T_setup_s'])
                self.emit('pair_gains',r)
                if qualifies:
                    self.support_pairs.append(r)
        raw = csv_rows(self.folder / 'length_sensitivity.csv')
        seen=set()
        crosses={}
        for row in raw:
            cal=int(row['calibration_id'])
            L=int(row['L'])
            require((cal,L) not in seen and 1000<=L<=100_000,'representative L grid')
            seen.add((cal,L))
            u,_=self.frame_lookup[(5,cal,SCHEMES[0])]
            p,_=self.frame_lookup[(5,cal,SCHEMES[1])]
            good=any(r['condition_id']==5 and r['calibration_id']==cal for r in self.support_pairs)
            u_rate=p_rate=cross=NAN
            state='insufficient_paired_evidence'
            if good:
                U,P,S_u,S_p=u['bits_per_symbol'],p['bits_per_symbol'],u['T_setup_s'],p['T_setup_s']
                u_rate=L*U/(L*self.T+S_u)
                p_rate=L*P/(L*self.T+S_p)
                state='no_positive_crossover'
                if P==U and S_u==S_p: state='identical_cycle_rates'
                if P!=U:
                    x=(U*S_p-P*S_u)/((P-U)*self.T)
                    if x>0 and math.isfinite(x):
                        cross=x
                        state='positive_crossover'
            row_matches(row,{'phase':'formal','condition_id':5,'case_id':2,'swing':.5,'q':8,'P_target':1,
                        'calibration_id':cal,'L':L,'pair_qualified':good,'uniform_R_cycle':u_rate,
                        'pertone_R_cycle':p_rate,'validated_delta_R_cycle':p_rate-u_rate,
                        'cross_over_L':cross,'cross_over_status':state,'is_main_L':L==self.cfg['payload_symbols']},
                        f'representative {cal}/{L}')
            crosses[cal]={'calibration_id':cal,'cross_over_L':cross,'state':state}
        grid = sorted(set(np.rint(np.logspace(3,5,61)).astype(int))|{self.cfg['payload_symbols']})
        require(seen=={(n,L) for n in range(1,self.cfg['calibration_count']+1) for L in grid},'representative grid completeness')
        return len(raw), list(crosses.values())

    def run(self):
        for c in self.conditions:
            for cal in range(1,self.cfg['calibration_count']+1):
                shared=(c['condition_id']-1)*self.cfg['calibration_count']+cal
                a,a_hash,gamma=self.initial(c,cal,shared)
                for j,scheme in enumerate(SCHEMES,1):
                    idx=(shared-1)*len(SCHEMES)+j
                    d,d_hash,overhead=self.design(c,cal,scheme,idx,a,a_hash,gamma)
                    self.payload(c,cal,scheme,idx,d,d_hash,overhead)
        all_scens=self.scenario()
        n_lengths,cross=self.compare()
        for data in self.exports.values(): data.done()
        have={f.name for f in (self.folder/'checkpoints').glob('*.mat')}
        require(have==self.counted_files,'extra or missing checkpoint file')
        return all_scens,n_lengths,cross


def clean_numbers(value):
    if isinstance(value, dict):
        return {k:clean_numbers(v) for k,v in value.items()}
    if isinstance(value, list):
        return [clean_numbers(v) for v in value]
    if isinstance(value, (bool, np.bool_)):
        return bool(value)
    if isinstance(value, (int, np.integer)):
        return int(value)
    if isinstance(value, (float, np.floating)):
        return float(value) if math.isfinite(value) else None
    return value


def execute(folder, checkout, archive):
    source_zip=check_archive(folder,archive)
    p=mat(folder/'Protocol.mat')
    require(p['phase']=='formal' and not p['test_only'] and p['version']=='dmt_vcsel_mmf_2025','formal protocol')
    cfg=p['cfg']
    require(cfg['Fs']==128_000_000_000 and cfg['NFFT']==512 and cfg['NCP']==16 and cfg['calibration_count']==5 and
            cfg['payload_repeats']==2 and cfg['payload_symbols']==25_000 and cfg['targetBER']==.001 and
            cfg['Wilson_z']==1.96 and tuple(cfg['scheme_names'])==SCHEMES and p['planned_payload_slots']==120 and
            p['symbols_per_slot']==cfg['payload_symbols'], 'formal geometry, budget or strategy')
    n_sources, channel_hashes=check_sources(folder,checkout,p)
    mech_hash, phases=check_receipts(folder,p)
    a=Audit(folder,cfg,p)
    scenes,n_lengths,cross=a.run()
    done=a.acc['completed']
    rejected=a.acc['design_rejected']
    planned=p['planned_payload_slots']
    marker=f'VCSEL ACQUISITION COMPLETE | formal | sent={done} rejected={rejected} planned={planned}'
    log=(folder/'run.log').read_text(encoding='utf-8-sig')
    require(done+rejected==planned and marker in log,'formal acquisition completion')
    failure_path=folder/'failure_status.txt'
    failure=failure_path.read_text(encoding='utf-8-sig') if failure_path.is_file() else ''
    payloads=a.payloads
    clip_max=max(r['tx_clip_rate'] for r in payloads)
    inventory=sorted((f.relative_to(folder).as_posix(),sha(f))
                     for f in folder.rglob('*') if f.is_file())
    artifact_id=hashlib.sha256('\n'.join(f'{name} {digest}' for name,digest in inventory).encode()).hexdigest()
    return clean_numbers({'schema_version':1, 'valid':True, 'audit_engine':'Python / SciPy independent raw numerical audit',
        'formal_matlab_verifier_rerun':False,'recorded_matlab_version':p['environment']['version'],
        'original_formal_matlab_receipt_present':(folder/'verification_receipt.mat').is_file(),
        'original_postprocess_failure_stage': failure.splitlines()[0][len('Stage: '):] if failure else None,
        'original_postprocess_failure_identifier':failure.splitlines()[1][len('Identifier: '):] if failure else None,
        'recorded_acquisition_marker':marker,'original_folder':folder.name,'archive':source_zip,
        'original_artifact_manifest_id':artifact_id,
        'archive_source_and_extraction_verified':source_zip is not None,'source_manifest_files':n_sources,
        'source_id':p['source_id'],'config_id':p['config_id'],'seed_id':p['seed_id'],
        'channel_file_hashes':channel_hashes,'mechanical_checks_sha256':mech_hash,'stage_gate_receipts':phases,
        'planned':planned,'completed':done,'design_rejected':rejected,'incomplete':planned-done-rejected,
        'symbols_per_slot':p['symbols_per_slot'],'payload_symbols':done*p['symbols_per_slot'],
        **{name:a.acc[name] for name in ('payload_samples','tx_clipped_samples','adc_oob_samples','tested_bits','error_bits')},
        'qualified_conditions':sum(r['qualified'] for r in scenes),'qualified_pairs':len(a.support_pairs),
        'original_checkpoint_counts':dict(Counter(name.split('_')[0] for name in sorted(a.counted_files))),
        'csv_row_counts':{**{name:table.total for name,table in a.exports.items()},'seed_plan':len(a.plan),
                          'length_sensitivity':n_lengths,'source_manifest':n_sources},
        'scenario':scenes,'paired_formal_results':a.support_pairs,'representative_crossovers':cross,
        'payload_statistics':{'power_min':min(r['P_actual'] for r in payloads),
                              'power_max':max(r['P_actual'] for r in payloads),
                              'max_tx_clip_fraction':clip_max,'max_adc_oob_fraction':max(r['adc_oob_rate'] for r in payloads),
                              'observed_swing_min':min(r['observed_swing'] for r in payloads),
                              'observed_swing_max':max(r['observed_swing'] for r in payloads),
                              'drive_papr_dB_min':min(r['drive_papr_dB'] for r in payloads),
                              'drive_papr_dB_max':max(r['drive_papr_dB'] for r in payloads)},
        'limitations':['MATLAB was not run for this audit and no waveforms were generated.',
                       'MATLAB MCOS table/string internals and canonical MATLAB data/config/seed hashes were not reconstructed. Stored hash joins, exact source and archive hashes, independent role seeds and decoded raw numeric values were checked.',
                       'Original PNG/PDF and the failed Chinese report are excluded from formal raw-data validity.']})


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('formal_directory', type=Path)
    parser.add_argument('original_source_directory', type=Path)
    parser.add_argument('output_directory', type=Path)
    parser.add_argument('--archive', type=Path)
    args=parser.parse_args()
    folder=args.formal_directory.resolve()
    output=args.output_directory.resolve()
    require(folder not in (output,*output.parents),'output must be outside the original formal folder')
    report=execute(folder,args.original_source_directory.resolve(),args.archive)
    output.mkdir(parents=True,exist_ok=True)
    (output/'raw_checkpoint_audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(f"{report['completed']} transmitted + {report['design_rejected']} rejected = {report['planned']} planned; "
          f"{report['qualified_conditions']} qualified cases/strategy and {report['qualified_pairs']} qualified pairs")


if __name__=='__main__':
    main()
