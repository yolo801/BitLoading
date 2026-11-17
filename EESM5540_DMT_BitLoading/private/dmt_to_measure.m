function measurement = dmt_to_measure(cfg,condition,M,b,nSymbols,seeds,role,H,adcBypass,Mdecode)
%DMT_TO_MEASURE Stream a known block; retain exact counters/sufficient sums.
% Empty H fits LS from this block. Nonempty H is frozen throughout the block.
% No full time-domain block or long payload waveform is retained.
if nargin<9, adcBypass=false; end
if nargin<10, Mdecode=M; end
timer=tic;
M=M(:); Mdecode=Mdecode(:); training=isempty(H);
assert(numel(M)==numel(cfg.k) && all(ismember(M,cfg.Mset)));
assert(numel(Mdecode)==numel(cfg.k) && all(ismember(Mdecode,cfg.Mset)));
assert(isscalar(nSymbols) && nSymbols>=1 && nSymbols==fix(nSymbols));
assert(all(isfield(seeds,{'data_seed','noise_seed'})) && ...
    isfinite(seeds.data_seed) && isfinite(seeds.noise_seed) && seeds.data_seed~=seeds.noise_seed);
if ~training
    H=H(:);
    assert(numel(H)==numel(cfg.k) && all(isfinite(H)) && all(abs(H)>0));
end
inputH=H;
dataStream=dmt_v13_stream(cfg,seeds.data_seed);
noiseStream=dmt_v13_stream(cfg,seeds.noise_seed);
nCarriers=numel(cfg.k);
retained=cfg.diagnostic_symbols_retained;
assert(isscalar(retained) && retained>=0 && retained==fix(retained));
knownEnergy=zeros(nCarriers,1); receivedEnergy=knownEnergy;
crossSum=complex(knownEnergy); residual=knownEnergy;
errors=knownEnergy; tested=knownEnergy;
diagnosticX=complex(zeros(nCarriers,0)); diagnosticY=diagnosticX;
state=[]; metrics=[]; done=0;
while done<nSymbols
    count=min(cfg.chunkSize,nSymbols-done);
    [X,bits]=dmt_v13_make_frame(cfg,M,count,dataStream);
    [Y,one,state]=dmt_to_link(cfg,condition,X,b,state,noiseStream,true,adcBypass);
    known=X(cfg.k+1,:);
    knownEnergy=knownEnergy+sum(abs(known).^2,2);
    receivedEnergy=receivedEnergy+sum(abs(Y).^2,2);
    crossSum=crossSum+sum(Y.*conj(known),2);
    if ~training
        Z=Y./H;
        residual=residual+sum(abs(Z-known).^2,2);
        [e,n]=dmt_demod_errors(cfg,Z,bits,Mdecode);
        errors=errors+e; tested=tested+n;
    end
    keep=min(retained-size(diagnosticX,2),count);
    if keep>0
        diagnosticX=[diagnosticX known(:,1:keep)]; %#ok<AGROW>
        diagnosticY=[diagnosticY Y(:,1:keep)]; %#ok<AGROW>
    end
    metrics=mergeMetrics(metrics,one);
    done=done+count;
end
assert(all(knownEnergy>0) && metrics.sample_count==nSymbols*(cfg.NFFT+cfg.NCP));
if training
    Hhat=crossSum./knownEnergy;
    assert(all(isfinite(Hhat)) && all(abs(Hhat)>0));
    errors=nan(nCarriers,1); tested=errors; gamma=errors;
    residual=errors;
else
    Hhat=H;
    assert(isequaln(H,inputH),'DMT:TOEstimateChanged','Receiver estimate changed within a measured block.');
    assert(all(tested==nSymbols*log2(M)) && all(errors>=0 & errors<=tested));
    assert(all(residual>=0 & isfinite(residual)));
    gamma=knownEnergy./residual; % Infinite quality only for exact noiseless regression.
end
measurement=struct('condition',condition,'role',char(string(role)), ...
    'M',M,'M_rx',Mdecode,'b',b,'q',condition.q,'seeds',seeds,'symbols',done, ...
    'nSymbols_requested',nSymbols,'training',training,'H_hat',Hhat,'H_used',inputH, ...
    'gamma',gamma,'known_energy_sum',knownEnergy,'received_cross_sum',crossSum, ...
    'received_energy_sum',receivedEnergy,'residual_sum_sq',residual, ...
    'error_bits',errors,'tested_bits',tested,'metrics',metrics, ...
    'add_noise',true,'noise_variance',cfg.noise_variance, ...
    'adc_bypass',adcBypass,'adc_range',cfg.adc_range, ...
    'diagnostic_X',diagnosticX,'diagnostic_Y',diagnosticY, ...
    'compute_seconds',toc(timer));
if isfield(seeds,'phase'), measurement.phase=char(string(seeds.phase)); end
end

function total=mergeMetrics(total,part)
if isempty(total), total=part; return; end
additive={'symbols','sample_count','tx_sum','tx_sum_sq','drive_ac_sq_sum', ...
    'lower_clip_count','upper_clip_count','clip_error_sq_sum', ...
    'adc_low_count','adc_high_count','useful_energy_sum','cp_energy_sum', ...
    'total_energy_sum','noise_sum','noise_sum_sq'};
for j=1:numel(additive)
    field=additive{j}; total.(field)=total.(field)+part.(field);
end
total.tx_min=min(total.tx_min,part.tx_min);
total.tx_max=max(total.tx_max,part.tx_max);
total.max_imag=max(total.max_imag,part.max_imag);
total.parseval_error=max(total.parseval_error,part.parseval_error);
end
