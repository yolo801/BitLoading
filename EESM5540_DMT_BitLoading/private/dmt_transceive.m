function [Y, stats, state] = dmt_transceive(cfg, X, state, noiseStream, addNoise)
% Genuine serial CP-DMT and causal FIR; state persists across chunks.
% Positive FFT bins have complex noise variance sigma_w2, not 2*sigma_w2.
assert(size(X,1) == cfg.NFFT);
if isempty(state)
    state = zeros(numel(cfg.h)-1,1);
end
xComplex = sqrt(cfg.NFFT)*ifft(X,[],1);
stats.maxImag = max(abs(imag(xComplex(:))));
scale = max(1,max(abs(xComplex(:))));
assert(stats.maxImag <= 1e-12*scale, 'DMT:Hermitian', ...
    'Time-domain waveform is not real before taking real().');
x = real(xComplex);
cp = x(end-cfg.NCP+1:end,:);
tx = [cp; x];
[rxSerial,state] = filter(cfg.h,1,tx(:),state);
if addNoise
    assert(~isempty(noiseStream), 'A separate noise stream is required.');
    rxSerial = rxSerial + sqrt(cfg.sigma_w2)* ...
        randn(noiseStream,size(rxSerial));
end
rx = reshape(rxSerial,cfg.NFFT+cfg.NCP,[]);
y = rx(cfg.NCP+1:end,:); % No group-delay compensation: H includes phase.
allY = fft(y,[],1)/sqrt(cfg.NFFT);
Y = allY(cfg.k+1,:);
stats.useful_energy_sum = sum(x(:).^2);
stats.cp_energy_sum = sum(cp(:).^2);
stats.total_energy_sum = stats.useful_energy_sum + stats.cp_energy_sum;
stats.parsevalError = max(abs(sum(abs(X).^2,1)-sum(x.^2,1)));
assert(all(isfinite(Y(:))), 'Nonfinite received FFT data.');
end
