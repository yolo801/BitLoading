function calibration = dmt_t2_diag_calibrate(cfg,settings,plan,c)
%DMT_T2_DIAG_CALIBRATE Find a common AC gain, then match separate DC offsets.
timer = tic;
gainSeed = getSeed(plan,c,"tx_gain_calibration");
offsetSeed = getSeed(plan,c,"tx_dc_calibration");
condition = struct('P_target',settings.P_target,'q',settings.q);
baseCfg = cfg;
baseCfg.P_peak = settings.P_peaks(1);
gainCalibration = dmt_to_power_cal(baseCfg,condition,settings.M,gainSeed);
g = gainCalibration.b/(cfg.rho*cfg.sigma_ref);

% One independent reference waveform is reused for the two DC fits and is
% discarded before transmission. Both ADC modes use each cap's same fit.
n = cfg.power_cal_symbols;
samplesPerSymbol = cfg.NFFT+cfg.NCP;
waveform = zeros(samplesPerSymbol*n,1);
data = dmt_v13_stream(cfg,offsetSeed);
for start = 1:cfg.chunkSize:n
    count = min(cfg.chunkSize,n-start+1);
    X = dmt_v13_make_frame(cfg,settings.M,count,data);
    x = sqrt(cfg.NFFT)*ifft(X,[],1);
    assert(max(abs(imag(x(:))))<=1e-12*max(1,max(abs(x(:)))));
    x = real(x);
    cpWave = [x(end-cfg.NCP+1:end,:);x];
    first = (start-1)*samplesPerSymbol+1;
    waveform(first:first+numel(cpWave)-1)=cpWave(:);
end
offsetWaveformHash = dmt_sha256(typecast(waveform,'uint8'));
ac = g*waveform;
offsets = cell(1,numel(settings.P_peaks));
for j = 1:numel(settings.P_peaks)
    offsets{j} = fitOffset(ac,settings.P_peaks(j),settings.P_target,cfg);
end
calibration = struct('phase',settings.phase,'calibration_id',c,'M',settings.M, ...
    'P_target',settings.P_target,'gain_calibration',gainCalibration, ...
    'g',g,'offset_data_seed',offsetSeed,'offset_waveform_hash',offsetWaveformHash, ...
    'offset_symbols',n,'offset_sample_count',numel(waveform), ...
    'offsets',[offsets{:}],'compute_seconds',toc(timer));
end

function seed = getSeed(plan,c,role)
row = plan(plan.calibration_id==c & plan.treatment_id==1 & plan.role==role,:);
assert(height(row)==1 && isnan(row.noise_seed));
seed = row.data_seed;
end

function fitted = fitOffset(ac,peak,target,cfg)
clip = @(d)min(max(d+ac,0),peak);
lo = -max(ac);
hi = peak-min(ac);
assert(mean(clip(lo))<=target && mean(clip(hi))>=target, ...
    'DMT:T2DiagnosticUnreachable','DC offset cannot match the diagnostic power target.');
history = nan(cfg.power_cal_max_iterations,2);
% Solve more tightly than the existing maximum matching tolerance so that
% numerical solve error does not dominate the cap-to-cap comparison.
for step = 1:cfg.power_cal_max_iterations
    d = (lo+hi)/2;
    p = clip(d);
    value = mean(p);
    history(step,:) = [d value];
    if abs(value-target)<=min(cfg.power_cal_tolerance,1e-6)*target
        break
    end
    if value<target, lo=d; else, hi=d; end
end
assert(abs(value-target)<=cfg.power_cal_tolerance*target, ...
    'DMT:T2DiagnosticPowerCalibration','DC fit exceeds the TX calibration tolerance.');
pRaw = d+ac;
fitted = struct('P_peak',peak,'d',d,'mean_power',value, ...
    'relative_error',(value-target)/target,'iterations',step, ...
    'offset_power_history',history(1:step,:), ...
    'lower_clip_count',sum(pRaw<0),'upper_clip_count',sum(pRaw>peak));
end
