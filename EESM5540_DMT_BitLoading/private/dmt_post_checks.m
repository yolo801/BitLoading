function dmt_post_checks(cfg, calibration, profiles, runs, outDir, phase)
% Numeric postconditions. Statistical BER acceptance is reported, not forced.
record('finite estimated SNR count',sum(isfinite(calibration.gamma_hat_dB)),24,0);
for s = 1:numel(profiles)
    p = profiles(s);
    record([p.name ' active independent carriers'],numel(p.M),24,0);
    record([p.name ' profile order membership'],sum(ismember(p.M,cfg.Mset)),24,0);
    predicted = dmt_qam_ber(p.M,calibration.gamma_hat/10^(cfg.margin_dB/10));
    record([p.name ' max design BER <= target (approximation + margin)'], ...
        max(predicted),cfg.targetBER,0,max(predicted)<=cfg.targetBER);
    selected = runs(strcmp({runs.scheme},p.name));
    symbols = sum([selected.symbols]);
    tested = sum(cat(2,selected.tested_bits),2);
    record([p.name ' bit accounting maximum error'], ...
        max(abs(tested-symbols*p.bits_per_symbol)),0,0);
    record([p.name ' rate time-accounting error'],p.R_payload*cfg.Ts,p.B,1e-10);
    tolerance = 0.02;
    if strcmp(phase,'smoke')
        tolerance = 0.10;
    end
    useful = sum([selected.useful_energy_sum])/symbols;
    cp = sum([selected.cp_energy_sum])/symbols;
    total = sum([selected.total_energy_sum])/symbols;
    record([p.name ' useful energy relative difference (expected 48)'], ...
        abs(useful/cfg.expectedUsefulEnergy-1),0,tolerance);
    record([p.name ' CP energy relative difference (expected 6)'], ...
        abs(cp/cfg.expectedCPEnergy-1),0,tolerance);
    record([p.name ' total energy relative difference (expected 54)'], ...
        abs(total/cfg.expectedTotalEnergy-1),0,tolerance);
    record([p.name ' sample-power relative difference (expected 0.75)'], ...
        abs(total/(cfg.NFFT+cfg.NCP)/cfg.expectedPower-1),0,tolerance);
end
% Both profiles share cfg, noise law and the same frozen initialization.
record('common data subcarrier set count',numel(cfg.k),24,0);
record('common constellation-average Es',cfg.Es,1,0);
record('common receiver real-noise variance',cfg.sigma_w2,10^(-29/10),1e-17);
record('loaded minus uniform payload bit difference >= 0',profiles(2).B-profiles(1).B, ...
    0,0,profiles(2).B >= profiles(1).B);
% Strictly greater is a mechanism outcome, not a prerequisite forced to pass.
fprintf('Observed loading gain in bits/symbol: %d (strict gain: %d).\n', ...
    profiles(2).B-profiles(1).B,profiles(2).B>profiles(1).B);

    function record(name, observed, expected, tolerance, passed)
        if nargin < 5
            passed = isfinite(observed) && abs(observed-expected)<=tolerance;
        end
        dmt_record_check(outDir,[phase ' | ' name],observed,expected,tolerance,passed);
    end
end
