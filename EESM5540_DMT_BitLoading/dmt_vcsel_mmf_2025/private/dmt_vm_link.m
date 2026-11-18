function [Y,metrics,state,debug] = dmt_vm_link(cfg,condition,X,b,state,noiseStream,addNoise,adcBypass)
%DMT_VM_LINK Transmit commanded swing, clip optical power, filter/noise/ADC.
% No centering, AGC, rescaling, or inactive-bin masking precedes the ADC.
% FIR state is carried across chunks and reset only for a new block.
if nargin<7, addNoise=true; end
if nargin<8, adcBypass=false; end
assert(size(X,1)==cfg.NFFT && size(X,2)>=1 && size(X,2)<=cfg.chunkSize);
assert(isreal(condition.h) && isvector(condition.h) && all(isfinite(condition.h)) && ...
    cfg.chunkSize<=2000 && cfg.NCP>=numel(condition.h)-1 && cfg.NCP<=cfg.NFFT);
assert(isreal(b) && isscalar(b) && isfinite(b) && b>=cfg.b_bounds(1) && b<=cfg.b_bounds(2));
assert(cfg.rho>0 && cfg.P_peak>0 && cfg.noise_variance>=0);
assert(islogical(addNoise) && isscalar(addNoise) && islogical(adcBypass) && isscalar(adcBypass));
assert(isscalar(condition.q) && ismember(condition.q,cfg.adc_bits));
assert(all(isfinite(X(:))));
if isempty(state), state=zeros(numel(condition.h)-1,1); end
xc=sqrt(cfg.NFFT)*ifft(X,[],1);
maxImag=max(abs(imag(xc(:))));
assert(maxImag<=1e-12*max(1,max(abs(xc(:)))),'DMT:TOHermitian','IFFT waveform is not real.');
x=real(xc); cp=x(end-cfg.NCP+1:end,:);
serial=[cp;x]; serial=serial(:);
drive=dmt_vm_drive_scale(cfg,condition)*serial;
pRaw=b+drive;
p=min(cfg.P_peak,max(0,pRaw));
assert(all(p>=0 & p<=cfg.P_peak));
[analog,state]=filter(condition.h,1,p,state);
if addNoise
    assert(~isempty(noiseStream),'DMT:TOMissingNoise','An independent receiver-noise stream is required.');
    noise=sqrt(cfg.noise_variance)*randn(noiseStream,numel(analog),1);
else
    noise=zeros(size(analog));
end
analog=analog+noise;
[quantized,adc]=dmt_to_quantize(analog,condition.q,cfg,adcBypass);
rx=reshape(quantized,cfg.NFFT+cfg.NCP,[]);
useful=rx(cfg.NCP+1:end,:);
fullY=fft(useful,[],1)/sqrt(cfg.NFFT);
Y=fullY(cfg.k+1,:); % DC is ignored as data only after the actual ADC.
assert(all(isfinite(Y(:))));
metrics=struct('symbols',size(X,2),'sample_count',numel(p), ...
    'tx_sum',sum(p),'tx_sum_sq',sum(p.^2),'drive_ac_sq_sum',sum(drive.^2), ...
    'lower_clip_count',sum(pRaw<0),'upper_clip_count',sum(pRaw>cfg.P_peak), ...
    'clip_error_sq_sum',sum((p-pRaw).^2), ...
    'adc_low_count',adc.low_count,'adc_high_count',adc.high_count, ...
    'useful_energy_sum',sum(x(:).^2),'cp_energy_sum',sum(cp(:).^2), ...
    'total_energy_sum',sum(serial.^2),'tx_min',min(p),'tx_max',max(p), ...
    'max_imag',maxImag, ...
    'parseval_error',max(abs(sum(abs(X).^2,1)-sum(x.^2,1))), ...
    'noise_sum',sum(noise),'noise_sum_sq',sum(noise.^2), ...
    'drive_ac_sum',sum(drive),'drive_ac_peak_abs',max(abs(drive)), ...
    'commanded_swing',condition.swing,'commanded_peak',condition.swing*condition.P_target);
metrics=dmt_vm_tx_summary(metrics,p,cfg.P_peak);
assert(metrics.sample_count==(cfg.NFFT+cfg.NCP)*metrics.symbols);
if nargout>=4
    debug=struct('tx_serial',serial,'tx_useful',x,'p_raw',pRaw,'p',p, ...
        'rx_before_adc',analog,'adc_output',quantized,'noise',noise);
end
end
