function design = dmt_t2_design(cfg,condition,calibrationID,scheme,shared,plan,reusedPower)
%DMT_T2_DESIGN Freeze a fixed profile or run the existing loading design.
if nargin<7
    reusedPower=[];
end
scheme=char(string(scheme));
if strcmp(scheme,'ValidatedLoading')
    assert(isempty(reusedPower),'DMT:T2LoadedPowerReuse', ...
        'Each adaptive design round needs its own TX calibration.');
    design=dmt_to_design(cfg,condition,calibrationID,scheme,shared,plan);
    return;
end

started=tic;
order=fixedOrder(scheme);
M=order*ones(numel(cfg.k),1);
phase=char(string(plan.phase(1)));
powerSeed=dmt_to_seed(plan,condition.condition_id,calibrationID,scheme,1,'power',NaN);
assert(isnan(powerSeed.noise_seed),'DMT:T2TXNoise','TX-only calibration has no receiver noise.');
if isempty(reusedPower)
    power=dmt_to_power_cal(cfg,condition,M,powerSeed.data_seed);
    performedPowerSeconds=power.compute_seconds;
else
    power=reusedPower;
    performedPowerSeconds=0;
    assert(power.seed==powerSeed.data_seed && isequal(power.M,M) && ...
        power.target==condition.P_target && power.symbols==cfg.power_cal_symbols && ...
        abs(power.actual_mean-condition.P_target)/condition.P_target<=cfg.power_cal_tolerance, ...
        'DMT:T2FixedPowerReuse','An ADC pair must share the planned fixed TX calibration.');
end

trainSeed=dmt_to_seed(plan,condition.condition_id,calibrationID,scheme,1,'Ar',NaN);
Ar=dmt_to_measure(cfg,condition,M,power.b,cfg.fixed_train_symbols,trainSeed,'Ar',[]);
authorization='fixed_profile_sync';
configuration=struct('protocol',cfg.protocol,'condition_id',condition.condition_id, ...
    'P_target',condition.P_target,'q',condition.q,'calibration_id',calibrationID, ...
    'scheme',scheme,'phase',phase,'stage','fixed','round',1, ...
    'M',M,'bits_k',log2(M),'Es_reference',cfg.Es,'targetBER',cfg.targetBER, ...
    'margin_dB',cfg.margin_dB,'adc_range',cfg.adc_range,'b',power.b, ...
    'H_hash',dmt_v13_hash(Ar.H_hat),'power_hash',dmt_v13_hash(power), ...
    'channel_training_hash',dmt_v13_hash(Ar),'authorization_basis',authorization);
configuration.profile_id=['fixed_' dmt_v13_hash(configuration)];
tx=configuration;
rx=tx;
txHash=dmt_v13_hash(tx);
assert(isequaln(tx,rx) && strcmp(dmt_v13_hash(rx),txHash));
ack=struct('accepted',true,'configuration_hash',txHash,'stage',rx.stage, ...
    'profile_id',rx.profile_id,'condition_id',rx.condition_id, ...
    'calibration_id',rx.calibration_id,'scheme',rx.scheme);
costs=struct('loading_seconds',0,'power_seconds',performedPowerSeconds, ...
    'training_seconds',Ar.compute_seconds,'validation_seconds',0,'design_seconds',toc(started));
feedback=struct('initial_quality_scalar_count',0,'validation_status_entries',0, ...
    'loading_table_entries',0,'configuration_ack_count',1,'serialized_bits',NaN);
design=struct('condition',condition,'calibration_id',calibrationID,'phase',phase, ...
    'scheme',scheme,'status','fixed_authorized','authorization_basis',authorization, ...
    'M',M,'b',power.b,'H_hat',Ar.H_hat,'final_tx',tx,'final_rx',rx,'ack',ack, ...
    'power',power,'Ar',Ar,'power_reused',~isempty(reusedPower),'costs',costs,'feedback',feedback);
end

function order=fixedOrder(scheme)
switch scheme
    case 'FixedQPSK'
        order=4;
    case 'Fixed64QAM'
        order=64;
    otherwise
        error('DMT:T2UnknownStrategy','Unknown modulation strategy: %s.',scheme);
end
end
