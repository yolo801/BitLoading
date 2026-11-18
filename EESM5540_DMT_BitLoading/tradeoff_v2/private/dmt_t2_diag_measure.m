function measured = dmt_t2_diag_measure(cfg,settings,planRow,calibration,H)
%DMT_T2_DIAG_MEASURE Stream one paired training or payload transmission.
timer = tic;
isTraining = planRow.role=="training";
assert(isscalar(isTraining) && isTraining==isempty(H));
nSymbols = planRow.symbols;
bitsPerTone = log2(settings.M);
offset = calibration.offsets([calibration.offsets.P_peak]==planRow.P_peak);
assert(isscalar(offset));
g = calibration.g;
d = offset.d;
peak = offset.P_peak;
mode = planRow.adc_mode;
dataStream = dmt_v13_stream(cfg,planRow.data_seed);
noiseStream = dmt_v13_stream(cfg,planRow.noise_seed);
counts = zeros(numel(cfg.k),1,'uint64');
errors = counts;
knownEnergy = zeros(numel(cfg.k),1);
cross = complex(knownEnergy);
samples = 0;
opticalSum = 0;
clipLower = 0;
clipUpper = 0;
rxLower = 0;
rxUpper = 0;
state = zeros(numel(cfg.h)-1,1);
for start = 1:cfg.chunkSize:nSymbols
    count = min(cfg.chunkSize,nSymbols-start+1);
    [X,bits] = dmt_v13_make_frame(cfg,settings.M,count,dataStream);
    x = sqrt(cfg.NFFT)*ifft(X,[],1);
    assert(max(abs(imag(x(:))))<=1e-12*max(1,max(abs(x(:)))));
    x = real(x);
    cpWave = [x(end-cfg.NCP+1:end,:);x];
    pRaw = d+g*cpWave(:);
    p = min(max(pRaw,0),peak);
    [analog,state] = filter(cfg.h,1,p,state);
    analog = analog+sqrt(cfg.noise_variance)*randn(noiseStream,numel(analog),1);
    [quantized,adc] = dmt_to_quantize(analog,settings.q,cfg,false);
    if mode=="continuous_saturated"
        adcOut = min(max(analog,cfg.adc_range(1)),cfg.adc_range(2));
    else
        assert(mode=="quantized");
        adcOut = quantized;
    end
    adcFrame = reshape(adcOut,cfg.NFFT+cfg.NCP,[]);
    Y = fft(adcFrame(cfg.NCP+1:end,:),[],1)/sqrt(cfg.NFFT);
    Y = Y(cfg.k+1,:);
    if isTraining
        Xactive = X(cfg.k+1,:);
        knownEnergy = knownEnergy+sum(abs(Xactive).^2,2);
        cross = cross+sum(Y.*conj(Xactive),2);
    else
        [chunkErrors,chunkCounts] = dmt_demod_errors(cfg,Y./H,bits,settings.M);
        assert(all(chunkCounts==count*bitsPerTone) && ...
            all(chunkErrors>=0 & chunkErrors<=chunkCounts & chunkErrors==fix(chunkErrors)));
        counts = counts+uint64(chunkCounts);
        errors = errors+uint64(chunkErrors);
    end
    samples = samples+numel(p);
    opticalSum = opticalSum+sum(p);
    clipLower = clipLower+sum(pRaw<0);
    clipUpper = clipUpper+sum(pRaw>peak);
    rxLower = rxLower+adc.low_count;
    rxUpper = rxUpper+adc.high_count;
end
assert(samples==nSymbols*(cfg.NFFT+cfg.NCP));
if isTraining
    H = cross./knownEnergy;
    assert(all(isfinite(H) & abs(H)>0),'DMT:T2DiagnosticEstimate','Invalid diagnostic LS estimate.');
    counts = zeros(0,1,'uint64');
    errors = counts;
else
    assert(all(counts==uint64(nSymbols*bitsPerTone)));
end
measured = struct('identity',table2struct(planRow),'H_hat',H, ...
    'M',settings.M,'g',g,'d',d,'samples',samples, ...
    'optical_sum',opticalSum,'P_measured',opticalSum/samples, ...
    'tx_lower_clip_count',clipLower,'tx_upper_clip_count',clipUpper, ...
    'adc_low_count',rxLower,'adc_high_count',rxUpper, ...
    'tested_bits',counts,'error_bits',errors,'known_energy',knownEnergy, ...
    'cross_sum',cross,'compute_seconds',toc(timer));
end
