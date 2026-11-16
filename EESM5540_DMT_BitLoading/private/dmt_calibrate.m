function calibration = dmt_calibrate(cfg)
% No test payload is used here. A and B have independent data/noise streams.
M = 4*ones(numel(cfg.k),1);
dataA = RandStream(cfg.streamType,'Seed',cfg.trainDataSeed);
noiseA = RandStream(cfg.streamType,'Seed',cfg.trainNoiseSeed);
numerator = complex(zeros(numel(cfg.k),1));
denominator = zeros(numel(cfg.k),1);
state = [];
done = 0;
while done < cfg.trainSymbols
    count = min(cfg.chunkSize,cfg.trainSymbols-done);
    X = dmt_random_frame(cfg,M,count,dataA);
    [Y,~,state] = dmt_transceive(cfg,X,state,noiseA,true);
    XA = X(cfg.k+1,:);
    numerator = numerator + sum(Y.*conj(XA),2);
    denominator = denominator + sum(abs(XA).^2,2);
    done = done + count;
end
calibration.H_hat = numerator./denominator;
assert(all(isfinite(calibration.H_hat)) && all(abs(calibration.H_hat)>0));
dataB = RandStream(cfg.streamType,'Seed',cfg.probeDataSeed);
noiseB = RandStream(cfg.streamType,'Seed',cfg.probeNoiseSeed);
signalSum = zeros(numel(cfg.k),1);
residualSum = zeros(numel(cfg.k),1);
state = []; % Independent probe run; a full CP protects the first symbol.
done = 0;
while done < cfg.probeSymbols
    count = min(cfg.chunkSize,cfg.probeSymbols-done);
    X = dmt_random_frame(cfg,M,count,dataB);
    [Y,~,state] = dmt_transceive(cfg,X,state,noiseB,true);
    XB = X(cfg.k+1,:);
    ZB = Y./calibration.H_hat;
    signalSum = signalSum + sum(abs(XB).^2,2);
    residualSum = residualSum + sum(abs(ZB-XB).^2,2);
    done = done + count;
end
calibration.gamma_hat = signalSum./residualSum;
calibration.gamma_hat_dB = 10*log10(calibration.gamma_hat);
calibration.probeSignalSum = signalSum;
calibration.probeResidualSum = residualSum;
calibration.trainingDenominator = denominator;
% True channel is attached ONLY for diagnostics/plotting, never loading/ZF.
Hfull = fft(cfg.h,cfg.NFFT).';
calibration.H_true = Hfull(cfg.k+1);
calibration.gamma_true_dB = 10*log10( ...
    cfg.Es*abs(calibration.H_true).^2/cfg.sigma_w2);
assert(all(isfinite(calibration.gamma_hat)) && all(calibration.gamma_hat>0));
end
