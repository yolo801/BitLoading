function [cfg,fit] = dmt_vm_config(folder)
%DMT_VM_CONFIG Load the sampled source response and freeze the experiment.
fit=jsondecode(fileread(fullfile(folder,'channel_fit.json')));
if isstruct(fit.cases),fit.cases=num2cell(fit.cases);end
ids=cellfun(@(one)one.case_id,fit.cases);
assert(isscalar(fit) && fit.passed && isequal(sort(ids(:)).',[1 2]), ...
    'DMT:VMFitGate','Both authenticated Case 1 and Case 2 fits must pass.');
assert(fit.Fs_Hz==128e9 && ismember(fit.NFFT,[512 1024]) && ...
    fit.NCP==fix(fit.NCP) && fit.NCP>=0 && fit.NCP<fit.NFFT, ...
    'DMT:VMFitGeometry','Geometry differs from the accepted channel fit.');
cfg=struct();
cfg.protocol='dmt_vcsel_mmf_2025';
cfg.protocolVersion=cfg.protocol;
cfg.baseline_commit='7a1331c1ee81c098bf6da071840474f8c73effb8';
cfg.Fs=fit.Fs_Hz;
cfg.NFFT=fit.NFFT;
cfg.NCP=fit.NCP;
cfg.Ts=(cfg.NFFT+cfg.NCP)/cfg.Fs;
cfg.k=reshape(fit.active_k,1,[]);
assert(numel(cfg.k)>1 && all(diff(cfg.k)>0) && ...
    all(cfg.k==fix(cfg.k) & cfg.k>0 & cfg.k<cfg.NFFT/2), ...
    'DMT:VMActiveBins','Active bins must be distinct positive-frequency data bins.');
cfg.Es=1;
cfg.Mset=[4 16 64];
cfg.targetBER=1e-3;
cfg.margin_dB=1;
cfg.Wilson_z=1.96;
cfg.streamType='mt19937ar';
cfg.normal_transform='Inversion';
cfg.chunkSize=1024;
cfg.diagnostic_symbols_retained=16;
cfg.rho=4;
cfg.sigma_ref=sqrt(2*numel(cfg.k)*cfg.Es/cfg.NFFT);
cfg.P_targets=1;
cfg.P_peak=2;
cfg.noise_variance=1.0491e-4;
cfg.adc_bits=8;
cfg.adc_range=[-.1 2.1];
cfg.b_bounds=[0 4];
cfg.power_cal_symbols=8192;
cfg.power_cal_max_iterations=40;
cfg.power_cal_tolerance=.002;
cfg.payload_power_tolerance=.01;
cfg.pair_power_tolerance=.01;
cfg.initial_A_symbols=1024;
cfg.initial_B_symbols=2048;
cfg.design_A_symbols=1024;
cfg.design_D_symbols=8192;
cfg.max_rounds=3;
cfg.calibration_count=5;
cfg.payload_repeats=2;
cfg.payload_symbols=25000;
cfg.pilot_payload_symbols=2000;
cfg.control_delay=0;
cfg.feedback_serialization_bits=NaN;
cfg.scheme_names={'UniformValidated','PerToneValidated'};
cfg.swings=[.25 .5 .75];
cfg.representative=struct('case_id',2,'swing',.5,'q',8,'calibration_id',1);
cfg.case2_notch_GHz=fit.case2_features.source_notch_GHz;

definition=struct('condition_id',0,'case_id',0,'swing',0,'P_target',1,'q',8,'h',[]);
cfg.conditions=repmat(definition,1,6);
for id=1:2
    one=fit.cases{ids==id};
    h=reshape(one.taps,1,[]);
    assert(isscalar(one) && one.passed && isreal(h) && all(isfinite(h)) && ...
        numel(h)-1<=cfg.NCP && abs(sum(h)-1)<1e-12 && one.active_rms_error_dB<=1, ...
        'DMT:VMFitCase','Case %d does not meet the FIR acceptance conditions.',id);
    for s=1:numel(cfg.swings)
        c=(id-1)*numel(cfg.swings)+s;
        cfg.conditions(c).condition_id=c;
        cfg.conditions(c).case_id=id;
        cfg.conditions(c).swing=cfg.swings(s);
        cfg.conditions(c).h=h;
    end
end
fit=dmt_vm_fit_audit(folder,cfg,fit);
end
