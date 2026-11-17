function checks = dmt_v13_frontend_checks(cfg,outDir)
%DMT_V13_FRONTEND_CHECKS Executed MATLAB checks, not performance acceptance.
% Noisy bypass is an electrical implementation regression, not an achievable
% nonnegative optical-output comparison. All streams are diagnostic only.
checks=strings(0,1);
legacy=cfg;
legacy.selfTrainSeed=cfg.diag_base+101;
legacy.selfPayloadSeeds=cfg.diag_base+[111 112 113];
legacy.selfNoiseSeed=cfg.diag_base+119;
dmt_self_checks(legacy,outDir);
scenarios=dmt_v13_scenarios(cfg);
linear=scenarios([scenarios.scenario_idx]==0);
rho4=scenarios([scenarios.scenario_idx]==1);
assert(isscalar(linear) && isscalar(rho4));
record('v1.3 fixed sigma_x^2',2*numel(cfg.k)/cfg.NFFT,0.75,0);
record('v1.3 rho4 gain',rho4.g,1/(4*sqrt(0.75)),1e-15);
record('v1.3 external-noise scale',rho4.sigma_w2,linear.sigma_w2*rho4.g^2,1e-18);
M4=4*ones(24,1);
train=dmt_v13_stream(cfg,cfg.diag_base+201);
XA=dmt_v13_make_frame(cfg,M4,128,train);
YA=dmt_v13_link(cfg,linear,XA,[],[],false);
known=XA(cfg.k+1,:);
Hls=sum(YA.*conj(known),2)./sum(abs(known).^2,2);
H=fft(cfg.h,cfg.NFFT).';
record('v1.3 noiseless receiver estimate',max(abs(Hls-H(cfg.k+1))),0,1e-12);
for q=1:numel(cfg.Mset)
    M=cfg.Mset(q)*ones(24,1);
    dataSeed=cfg.diag_base+210+q;
    stream=dmt_v13_stream(cfg,dataSeed);
    [X,bits]=dmt_v13_make_frame(cfg,M,257,stream);
    stream=dmt_v13_stream(cfg,dataSeed);
    [X1,bits1]=dmt_v13_make_frame(cfg,M,113,stream);
    [X2,bits2]=dmt_v13_make_frame(cfg,M,144,stream);
    joined=[X1 X2];
    label=sprintf('v1.3 M%d ',cfg.Mset(q));
    record([label 'symbol-first chunk-invariant frequency data'],max(abs(X(:)-joined(:))),0,0);
    bitMismatch=0;
    for k=1:24
        bitMismatch=bitMismatch+sum(bits{k}~=[bits1{k};bits2{k}]);
    end
    record([label 'chunk-invariant bit grouping'],bitMismatch,0,0);
    mirror=conj(X([1 cfg.NFFT:-1:2],:));
    record([label 'Hermitian residual'],max(abs(X(:)-mirror(:))),0,1e-13);
    [Y,metrics]=dmt_v13_link(cfg,linear,X,[],[],false);
    record([label 'unitary Parseval residual'],metrics.parseval_error,0,1e-10);
    record([label 'imaginary residual before real'],metrics.max_imag,0,1e-12);
    expected=H(cfg.k+1).*X(cfg.k+1,:);
    record([label 'serial FIR/CP FFT residual'],max(abs(Y(:)-expected(:))),0,1e-11);
    errors=dmt_demod_errors(cfg,Y./Hls,bits,M);
    record([label 'noiseless linear bit errors'],sum(errors),0,0);
    Yb=dmt_v13_link(cfg,rho4,X,[],[],false,true);
    errors=dmt_demod_errors(cfg,Yb./(rho4.g*Hls),bits,M);
    record([label 'noiseless bypass bit errors'],sum(errors),0,0);
    n1=dmt_v13_stream(cfg,cfg.diag_base+300+q);
    n2=dmt_v13_stream(cfg,cfg.diag_base+300+q);
    [~,~,~,a]=dmt_v13_link(cfg,linear,X,[],n1,true);
    [~,~,~,b]=dmt_v13_link(cfg,rho4,X,[],n2,true,true);
    relative=norm(b.serial_rx_ac/rho4.g-a.serial_rx_ac)/max(norm(a.serial_rx_ac),realmin);
    record([label 'same-raw-noise rho4 bypass relative residual'],relative,0,1e-11);
end
% Check all real front ends, including clipping, retain filter/noise streams
% and PAPR/clipping counters over arbitrary chunk boundaries.
for index=1:numel(scenarios)
    scenario=scenarios(index);
    noiseSeed=cfg.diag_base+400+index;
    noise=dmt_v13_stream(cfg,noiseSeed);
    [Y,metrics,~,whole]=dmt_v13_link(cfg,scenario,X,[],noise,true);
    noise=dmt_v13_stream(cfg,noiseSeed);
    [Y1,m1,state,a]=dmt_v13_link(cfg,scenario,X(:,1:113),[],noise,true);
    [Y2,m2,~,b]=dmt_v13_link(cfg,scenario,X(:,114:end),state,noise,true);
    joined=[Y1 Y2];
    rx=[a.serial_rx_ac;b.serial_rx_ac];
    label=['v1.3 ' char(string(scenario.scenario_id)) ' '];
    record([label 'received chunks relative residual'], ...
        norm(whole.serial_rx_ac-rx)/max(norm(whole.serial_rx_ac),realmin),0,1e-12);
    record([label 'FFT chunks maximum residual'],max(abs(Y(:)-joined(:))),0,1e-12);
    record([label 'PAPR exceedance chunk count difference'], ...
        max(abs(metrics.papr_exceed_counts-m1.papr_exceed_counts-m2.papr_exceed_counts)),0,0);
    record([label 'sample count accounting'],metrics.sample_count,(cfg.NFFT+cfg.NCP)*257,0);
    record([label 'PAPR symbol count'],metrics.papr_symbols,257,0);
    record([label 'lower clipping chunk count'], ...
        metrics.lower_clip_count,m1.lower_clip_count+m2.lower_clip_count,0);
    record([label 'upper clipping chunk count'], ...
        metrics.upper_clip_count,m1.upper_clip_count+m2.upper_clip_count,0);
    if scenario.imdd
        record([label 'bounded sampled power minimum'],metrics.optical_min,0,1e-13,metrics.optical_min>=-1e-13);
        record([label 'bounded sampled power maximum'],metrics.optical_peak,2,1e-13,metrics.optical_peak<=2+1e-13);
        record([label 'second optical moment split relative residual'], ...
            abs(metrics.optical_sum_sq-m1.optical_sum_sq-m2.optical_sum_sq)/max(1,metrics.optical_sum_sq),0,1e-12);
    end
end
% A deliberately varied diagnostic profile tests per-carrier bit recovery.
% This is not an allocator result, a calibration round or a formal payload.
orders=cfg.Mset(mod((0:23),numel(cfg.Mset))+1).';
tx=struct('scenario_id',linear.scenario_id,'calibration_id',1, ...
    'profile_id','diagnostic_chunk_replay','scheme','Loaded','active_k',cfg.k, ...
    'M_k',orders,'bits_k',log2(orders),'Gray_mapping_version',cfg.gray_mapping_version, ...
    'Es_reference',cfg.Es,'targetBER',cfg.targetBER,'margin_dB',cfg.margin_dB);
rx=tx; % MATLAB value copies, not shared mutable global configuration.
ack=struct('accepted',true,'configuration_hash',dmt_v13_hash(tx));
seeds=struct('data_seed',cfg.diag_base+601,'noise_seed',cfg.diag_base+602, ...
    'label',11,'phase','preflight');
receiver=struct('H_hat',Hls,'scenario_id',linear.scenario_id,'calibration_id',1,'active_k',cfg.k);
badAck=ack; badAck.accepted=false;
refused=false;
try
    dmt_v13_payload(cfg,linear,receiver,tx,rx,badAck,seeds,257);
catch ME
    refused=strcmp(ME.identifier,'DMT:MissingACK');
end
record('v1.3 unacknowledged payload refused before transmission',double(refused),1,0);
cfgA=cfg; cfgA.chunkSize=73;
cfgB=cfg; cfgB.chunkSize=199;
one=dmt_v13_payload(cfgA,linear,receiver,tx,rx,ack,seeds,257);
two=dmt_v13_payload(cfgB,linear,receiver,tx,rx,ack,seeds,257);
record('v1.3 diagnostic payload replay chunk-invariant bit counts', ...
    max(abs(one.tested_bits-two.tested_bits)),0,0);
record('v1.3 diagnostic payload replay chunk-invariant errors', ...
    max(abs(one.error_bits-two.error_bits)),0,0);
record('v1.3 diagnostic payload replay chunk-invariant PAPR counts', ...
    max(abs(one.papr_exceed_counts-two.papr_exceed_counts)),0,0);
% Validate the chosen Gaussian transform and the positive-bin noise scaling.
noise=dmt_v13_stream(cfg,cfg.diag_base+501);
record('v1.3 noise stream NormalTransform', ...
    double(strcmp(noise.NormalTransform,cfg.normal_transform)),1,0);
sums=zeros(24,1); nNoise=20000;
for first=1:2000:nNoise
    count=min(2000,nNoise-first+1);
    w=sqrt(linear.sigma_w2)*randn(noise,cfg.NFFT,count);
    spectrum=fft(w,[],1)/sqrt(cfg.NFFT);
    sums=sums+sum(abs(spectrum(cfg.k+1,:)).^2,2);
end
record('v1.3 positive-bin complex noise variance max relative error', ...
    max(abs(sums/nNoise/linear.sigma_w2-1)),0,0.04);

    function record(name,observed,expected,tolerance,passed)
        if nargin<5
            passed=isscalar(observed) && isfinite(observed) && abs(observed-expected)<=tolerance;
        end
        dmt_record_check(outDir,name,observed,expected,tolerance,passed);
        checks(end+1,1)=string(name);
    end
end
