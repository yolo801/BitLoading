function [Y,metrics,state,debug] = dmt_v13_link(cfg,scenario,X,state,noiseStream,addNoise,bypassClip)
%DMT_V13_LINK Real serial CP-DMT through linear or sampled IM/DD front end.
% IM/DD uses h*(p-P0)+w, the AC-equivalent of a steady known DC input P0.
% Zero AC filter state means the corresponding physical DC filter was at
% steady state before the first symbol; startup DC transients are excluded.
% p is optical power, not field amplitude: it is never squared as a signal.
if nargin<7, bypassClip=false; end
assert(size(X,1)==cfg.NFFT && size(X,2)>=1 && size(X,2)<=2000);
assert(cfg.NCP>=numel(cfg.h)-1 && cfg.NCP<=cfg.NFFT);
assert(isscalar(bypassClip) && islogical(bypassClip));
if isempty(state), state=zeros(numel(cfg.h)-1,1); end
xc=sqrt(cfg.NFFT)*ifft(X,[],1);
metrics.max_imag=max(abs(imag(xc(:))));
assert(metrics.max_imag<=1e-12*max(1,max(abs(xc(:)))), ...
    'DMT:Hermitian','Check the complex waveform before real().');
x=real(xc);
cp=x(end-cfg.NCP+1:end,:);
serial=[cp;x];
serial=serial(:);
metrics.useful_energy_sum=sum(x(:).^2);
metrics.cp_energy_sum=sum(cp(:).^2);
metrics.total_energy_sum=metrics.useful_energy_sum+metrics.cp_energy_sum;
metrics.parseval_error=max(abs(sum(abs(X).^2,1)-sum(x.^2,1)));
metrics.sample_count=numel(serial);
metrics.optical_applicable=logical(scenario.imdd);
if scenario.imdd
    assert(scenario.P0==1 && scenario.Pmax==2 && scenario.g>0);
    pRaw=scenario.P0+scenario.g*serial;
    if bypassClip
        p=pRaw; % Only the declared fixed-sequence implementation regression.
    else
        p=min(scenario.Pmax,max(0,pRaw));
        assert(all(p>=-1e-13 & p<=scenario.Pmax+1e-13), ...
            'DMT:OpticalRange','Sampled optical power left [0,Pmax].');
    end
    drive=p-scenario.P0;
    metrics.optical_sum=sum(p);
    metrics.optical_sum_sq=sum(p.^2);
    metrics.optical_peak=max(p);
    metrics.optical_min=min(p);
    if bypassClip
        metrics.lower_clip_count=0;
        metrics.upper_clip_count=0;
    else
        metrics.lower_clip_count=sum(pRaw<0);
        metrics.upper_clip_count=sum(pRaw>scenario.Pmax);
    end
    metrics.clip_error_sq_sum=sum((p-pRaw).^2);
else
    drive=serial;
    % A linear electrical model has no defined normalized optical power p.
    metrics.optical_sum=NaN;
    metrics.optical_sum_sq=NaN;
    metrics.optical_peak=NaN;
    metrics.optical_min=NaN;
    metrics.lower_clip_count=0;
    metrics.upper_clip_count=0;
    metrics.clip_error_sq_sum=0;
end
[rxSerial,state]=filter(cfg.h,1,drive,state);
if addNoise
    assert(~isempty(noiseStream),'DMT:MissingNoiseStream','Independent noise stream required.');
    rxSerial=rxSerial+sqrt(scenario.sigma_w2)*randn(noiseStream,numel(rxSerial),1);
end
rx=reshape(rxSerial,cfg.NFFT+cfg.NCP,[]);
y=rx(cfg.NCP+1:end,:); % H_hat includes the FIR phase; no delay compensation.
fullY=fft(y,[],1)/sqrt(cfg.NFFT);
Y=fullY(cfg.k+1,:);
assert(all(isfinite(Y(:))),'DMT:NonfiniteReceiver','Nonfinite received FFT bins.');
% The sampled AC PAPR is measured before bias/clipping on useful samples.
denominator=mean(x.^2,1);
assert(all(denominator>0),'DMT:ZeroSignal','PAPR requires nonzero useful energy.');
paprDB=10*log10(max(x.^2,[],1)./denominator);
metrics.papr_thresholds_dB=cfg.papr_thresholds_dB(:);
metrics.papr_exceed_counts=sum(paprDB>metrics.papr_thresholds_dB,2);
metrics.papr_symbols=size(X,2);
if nargout>=4
    debug=struct('serial_rx_ac',rxSerial,'tx_useful',x,'tx_serial',serial);
end
end
