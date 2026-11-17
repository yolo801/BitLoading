function run = dmt_v13_payload(cfg,scenario,receiver,txConfig,rxConfig,ack,seeds,nSymbols)
%DMT_V13_PAYLOAD Read separately accepted TX/RX configurations, then freeze.
% No receiver quality or payload errors are sent back into the allocator.
required={'scenario_id','calibration_id','profile_id','scheme','active_k', ...
    'M_k','bits_k','Gray_mapping_version','Es_reference','targetBER','margin_dB'};
assert(all(isfield(txConfig,required)) && all(isfield(rxConfig,required)), ...
    'DMT:InvalidConfiguration','Incomplete local configuration.');
txHash=dmt_v13_hash(txConfig);
rxHash=dmt_v13_hash(rxConfig);
assert(isstruct(ack) && isfield(ack,'accepted') && isscalar(ack.accepted) && ...
    (islogical(ack.accepted) || isnumeric(ack.accepted)) && ack.accepted==1 && ...
    isfield(ack,'configuration_hash') && ...
    strcmp(txHash,rxHash) && strcmp(txHash,char(string(ack.configuration_hash))), ...
    'DMT:MissingACK','Payload cannot start without matching local configurations and ACK.');
assert(strcmp(string(txConfig.scenario_id),string(scenario.scenario_id)) && ...
    isequal(txConfig.active_k(:),cfg.k(:)) && txConfig.Es_reference==cfg.Es && ...
    txConfig.targetBER==cfg.targetBER && txConfig.margin_dB==cfg.margin_dB);
assert(strcmp(string(txConfig.Gray_mapping_version),string(cfg.gray_mapping_version)) && ...
    strcmp(string(rxConfig.Gray_mapping_version),string(cfg.gray_mapping_version)), ...
    'DMT:MappingVersion','Accepted configuration does not identify the implemented Gray QAM mapping.');
Mtx=txConfig.M_k(:);
Mrx=rxConfig.M_k(:);
assert(numel(Mtx)==24 && all(ismember(Mtx,cfg.Mset)) && ...
    isequal(txConfig.bits_k(:),log2(Mtx)) && isequal(rxConfig.bits_k(:),log2(Mrx)));
assert(all(isfield(receiver,{'H_hat','scenario_id','calibration_id','active_k'})) && ...
    strcmp(string(receiver.scenario_id),string(txConfig.scenario_id)) && ...
    isequal(receiver.calibration_id,txConfig.calibration_id) && ...
    isequal(receiver.active_k(:),cfg.k(:)), ...
    'DMT:ReceiverIdentity','Receiver estimate belongs to another scenario/calibration.');
assert(isequal(size(receiver.H_hat),[24 1]) && ...
    all(isfinite(receiver.H_hat)) && all(abs(receiver.H_hat)>0));
if isfield(txConfig,'calibration_hash')
    assert(isfield(receiver,'calibration_hash') && ...
        strcmp(string(receiver.calibration_hash),string(txConfig.calibration_hash)), ...
        'DMT:ReceiverIdentity','Receiver calibration hash differs from the accepted configuration.');
end
assert(all(isfield(seeds,{'data_seed','noise_seed','label','phase'})) && ...
    ismember(seeds.label,[11 22 33]) && ...
    any(strcmp(string(seeds.phase),["formal" "preflight"])));
assert(nSymbols>=1 && nSymbols==fix(nSymbols) && cfg.chunkSize>=1 && cfg.chunkSize<=2000);
if strcmp(string(seeds.phase),'formal')
    assert(nSymbols==100000,'DMT:PayloadBudget','Formal groups require exactly 100000 symbols.');
end
dataStream=dmt_v13_stream(cfg,seeds.data_seed);
noiseStream=dmt_v13_stream(cfg,seeds.noise_seed);
assert(seeds.data_seed~=seeds.noise_seed,'Data and noise seeds must differ.');
run=struct('scenario_idx',scenario.scenario_idx,'scenario_id',scenario.scenario_id, ...
    'calibration_id',txConfig.calibration_id,'scheme',txConfig.scheme, ...
    'profile_id',txConfig.profile_id,'configuration_hash',txHash, ...
    'data_seed',seeds.data_seed,'noise_seed',seeds.noise_seed,'seed',seeds.label, ...
    'phase',char(string(seeds.phase)),'symbols',0,'tested_bits',zeros(24,1), ...
    'error_bits',zeros(24,1),'started_utc',utcNow());
runTimer=tic;
state=[];
sumFields={'useful_energy_sum','cp_energy_sum','total_energy_sum','sample_count', ...
    'optical_sum','optical_sum_sq','lower_clip_count','upper_clip_count', ...
    'clip_error_sq_sum','papr_exceed_counts','papr_symbols'};
while run.symbols<nSymbols
    count=min(cfg.chunkSize,nSymbols-run.symbols);
    [X,bits]=dmt_v13_make_frame(cfg,Mtx,count,dataStream);
    [Y,metrics,state]=dmt_v13_link(cfg,scenario,X,state,noiseStream,true);
    Z=Y./receiver.H_hat;
    [errors,tested]=dmt_demod_errors(cfg,Z,bits,Mrx);
    run.tested_bits=run.tested_bits+tested;
    run.error_bits=run.error_bits+errors;
    if run.symbols==0
        for j=1:numel(sumFields), run.(sumFields{j})=metrics.(sumFields{j}); end
        run.optical_peak=metrics.optical_peak;
        run.optical_min=metrics.optical_min;
        run.max_imag=metrics.max_imag;
        run.parseval_error=metrics.parseval_error;
        run.optical_applicable=metrics.optical_applicable;
        run.papr_thresholds_dB=metrics.papr_thresholds_dB;
    else
        for j=1:numel(sumFields)
            field=sumFields{j}; run.(field)=run.(field)+metrics.(field);
        end
        if run.optical_applicable
            run.optical_peak=max(run.optical_peak,metrics.optical_peak);
            run.optical_min=min(run.optical_min,metrics.optical_min);
        end
        run.max_imag=max(run.max_imag,metrics.max_imag);
        run.parseval_error=max(run.parseval_error,metrics.parseval_error);
        assert(isequal(run.papr_thresholds_dB,metrics.papr_thresholds_dB));
    end
    run.symbols=run.symbols+count;
    if mod(run.symbols,20000)==0 || run.symbols==nSymbols
        fprintf('%s | scenario=%s calibration=%d %s seed=%d | %d/%d symbols | %.3f s\n', ...
            utcNow(),char(string(run.scenario_id)),run.calibration_id, ...
            char(string(run.scheme)),run.seed,run.symbols,nSymbols,toc(runTimer));
    end
end
run.elapsed_seconds=toc(runTimer);
run.signal_duration_s=run.symbols*cfg.Ts;
assert(all(run.tested_bits==run.symbols*log2(Mtx)) && ...
    all(run.error_bits>=0 & run.error_bits<=run.tested_bits));
assert(run.sample_count==(cfg.NFFT+cfg.NCP)*run.symbols && run.papr_symbols==run.symbols);
if run.optical_applicable
    run.optical_mean=run.optical_sum/run.sample_count;
    run.optical_second_moment=run.optical_sum_sq/run.sample_count;
    run.optical_ac_variance=max(0,run.optical_second_moment-run.optical_mean^2);
    run.optical_mean_relative_deviation=run.optical_mean/scenario.P0-1;
    % Preserve this flag and all data for investigation; never power-rescale.
    run.power_mean_investigation_required=abs(run.optical_mean_relative_deviation)>0.01;
else
    run.optical_mean=NaN;
    run.optical_second_moment=NaN;
    run.optical_ac_variance=NaN;
    run.optical_mean_relative_deviation=NaN;
    run.power_mean_investigation_required=false;
end
run.clipping_rate=(run.lower_clip_count+run.upper_clip_count)/run.sample_count;
run.clip_error_mean_square=run.clip_error_sq_sum/run.sample_count;
assert(strcmp(txHash,dmt_v13_hash(txConfig)) && strcmp(rxHash,dmt_v13_hash(rxConfig)), ...
    'DMT:ConfigurationChanged','Local configurations changed during the payload.');
end

function value=utcNow()
value=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss.SSS Z'));
end
