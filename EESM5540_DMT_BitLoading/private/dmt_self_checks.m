function dmt_self_checks(cfg, outDir)
% Stage 1 must pass before noisy calibration or any payload statistics.
M = 4*ones(numel(cfg.k),1);
stream = RandStream(cfg.streamType,'Seed',cfg.selfTrainSeed);
X = dmt_random_frame(cfg,M,cfg.trainSymbols,stream);
[Y,stats] = dmt_transceive(cfg,X,[],[],false);
XA = X(cfg.k+1,:);
Hls = sum(Y.*conj(XA),2)./sum(abs(XA).^2,2);
Hfull = fft(cfg.h,cfg.NFFT).';
Htrue = Hfull(cfg.k+1);
analyticH = exp(-1i*2*pi*cfg.k/cfg.NFFT).*cos(pi*cfg.k/cfg.NFFT).^2;
record('FIR FFT versus analytic response',max(abs(Htrue-analyticH)),0,1e-13);
record('noiseless LS channel estimate',max(abs(Hls-Htrue)),0,1e-12);
record('CP memory coverage (observed NCP >= expected FIR memory)',cfg.NCP,numel(cfg.h)-1,0, ...
    cfg.NCP >= numel(cfg.h)-1);
record('CP length (samples)',cfg.NCP,8,0);
for j = 1:numel(cfg.Mset)
    M = cfg.Mset(j)*ones(numel(cfg.k),1);
    stream = RandStream(cfg.streamType,'Seed',cfg.selfPayloadSeeds(j));
    [X,bits] = dmt_random_frame(cfg,M,1000,stream);
    [Y,stats] = dmt_transceive(cfg,X,[],[],false);
    label = sprintf('M=%d ',cfg.Mset(j));
    mirror = conj(X([1 cfg.NFFT:-1:2],:));
    record([label 'Hermitian full-matrix residual'],max(abs(X(:)-mirror(:))),0,1e-13);
    record([label 'time waveform imaginary residual'],stats.maxImag,0,1e-12);
    record([label 'unitary Parseval maximum energy residual'],stats.parsevalError,0,1e-10);
    expected = Htrue.*X(cfg.k+1,:);
    record([label 'linear FIR FFT relation residual'],max(abs(Y(:)-expected(:))),0,1e-11);
    [errors,tested] = dmt_demod_errors(cfg,Y./Hls,bits,M);
    record([label 'noiseless bit errors'],sum(errors),0,0);
    record([label 'tested bits'],sum(tested),1000*sum(log2(M)),0);
    % Compare one long linear convolution with two chunks, same X and state.
    [Y1,~,state] = dmt_transceive(cfg,X(:,1:317),[],[],false);
    Y2 = dmt_transceive(cfg,X(:,318:end),state,[],false);
    joined = [Y1 Y2];
    record([label 'FIR chunk-state continuity residual'],max(abs(Y(:)-joined(:))),0,1e-13);
    x = real(sqrt(cfg.NFFT)*ifft(X,[],1));
    tx = [x(end-cfg.NCP+1:end,:);x];
    diffCP = tx(1:cfg.NCP,:)-x(end-cfg.NCP+1:end,:);
    record([label 'CP tail-copy residual'],max(abs(diffCP(:))),0,0);
end
% Independent real-noise diagnostic, at most 2000 symbols allocated at once.
noise = RandStream(cfg.streamType,'Seed',cfg.selfNoiseSeed);
complexSum = zeros(numel(cfg.k),1);
realSum = complexSum;
imagSum = complexSum;
sampleSum = 0;
nNoiseSymbols = 20000;
for first = 1:cfg.chunkSize:nNoiseSymbols
    count = min(cfg.chunkSize,nNoiseSymbols-first+1);
    w = sqrt(cfg.sigma_w2)*randn(noise,cfg.NFFT,count);
    Wfull = fft(w,[],1)/sqrt(cfg.NFFT);
    W = Wfull(cfg.k+1,:);
    complexSum = complexSum + sum(abs(W).^2,2);
    realSum = realSum + sum(real(W).^2,2);
    imagSum = imagSum + sum(imag(W).^2,2);
    sampleSum = sampleSum + sum(w(:).^2);
end
v = complexSum/nNoiseSymbols;
vr = realSum/nNoiseSymbols;
vi = imagSum/nNoiseSymbols;
record('positive FFT complex-noise second moment: max relative error', ...
    max(abs(v/cfg.sigma_w2-1)),0,0.04);
record('positive FFT real-noise component: max relative error', ...
    max(abs(vr/(cfg.sigma_w2/2)-1)),0,0.05);
record('positive FFT imag-noise component: max relative error', ...
    max(abs(vi/(cfg.sigma_w2/2)-1)),0,0.05);
record('time real-noise variance relative error', ...
    abs(sampleSum/(cfg.NFFT*nNoiseSymbols)/cfg.sigma_w2-1),0,0.01);
% Check the zero-count interval used for the logarithmic BER plot.
[lo,hi] = dmt_wilson(0,10000);
record('zero-error Wilson lower limit',lo,0,1e-15);
record('zero-error Wilson upper limit formula',hi,1.96^2/(10000+1.96^2),1e-15);

    function record(name, observed, expected, tolerance, passed)
        if nargin < 5
            passed = isfinite(observed) && abs(observed-expected)<=tolerance;
        end
        dmt_record_check(outDir,name,observed,expected,tolerance,passed);
    end
end
