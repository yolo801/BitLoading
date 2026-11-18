function design=dmt_vm_design(cfg,condition,calID,scheme,shared,plan)
% Train and validate each complete candidate before authorizing payload.
assert(isstruct(shared) && strcmp(shared.status,'complete') && ...
    isequaln(shared.condition,condition) && shared.calibration_id==calID);
scheme=validatestring(scheme,cfg.scheme_names);
assert(all(plan.phase==string(shared.phase)));
sharedHash=dmt_v13_hash(shared);
assert(isequaln(shared.feedback_sent,shared.feedback_received) && ...
    strcmp(dmt_v13_hash(shared.feedback_sent),shared.feedback_hash_sent) && ...
    strcmp(shared.feedback_hash_sent,shared.feedback_hash_received));
assert(isequal(shared.gamma_B,shared.feedback_received.gamma_B));
timer=tic;
loadingTimer=tic;
proposal=dmt_vm_decisions(cfg,scheme,shared.feedback_received.gamma_B);
M=proposal.M;
template=struct('round',0,'M',zeros(0,1),'candidate_tx',struct(), ...
    'candidate_rx',struct(),'candidate_ack',struct(),'power',struct(), ...
    'Ar',struct(),'Dr',struct(),'CI_low',zeros(0,1),'CI_high',zeros(0,1), ...
    'supported_k',false(0,1),'status','','reason','','proposed_next_M',zeros(0,1));
costs=struct('loading_seconds',toc(loadingTimer),'power_seconds',0, ...
    'training_seconds',0,'validation_seconds',0,'design_seconds',0);
feedback=struct('initial_quality_scalar_count',numel(cfg.k), ...
    'validation_status_entries',0,'loading_table_entries',0, ...
    'configuration_ack_count',0,'serialized_bits',NaN);
design=struct('condition',condition,'calibration_id',calID,'phase',shared.phase, ...
    'scheme',scheme,'initial_shared_hash',sharedHash,'initial_gamma_B',shared.gamma_B, ...
    'initial_M',M,'predicted_BER_design',proposal.predicted,'initial_allowed',proposal.allowed, ...
    'status','','reason','','rounds',repmat(template,1,0), ...
    'M',zeros(0,1),'b',zeros(0,1),'H_hat',complex(zeros(0,1)), ...
    'final_tx',struct(),'final_rx',struct(),'ack',struct(), ...
    'costs',costs,'feedback',feedback);
for r=1:cfg.max_rounds
    one=template;
    one.round=r;
    one.M=M;
    candidate=configuration('candidate',M,r);
    candidate.profile_id=profileID(candidate);
    [one.candidate_tx,one.candidate_rx,one.candidate_ack]=dmt_vm_agree(cfg,candidate);
    powerSeed=dmt_to_seed(plan,condition.condition_id,calID,scheme,r,'power',NaN);
    assert(isnan(powerSeed.noise_seed));
    one.power=dmt_vm_power_cal(cfg,condition,M,powerSeed.data_seed);
    trainingSeed=dmt_to_seed(plan,condition.condition_id,calID,scheme,r,'Ar',NaN);
    validationSeed=dmt_to_seed(plan,condition.condition_id,calID,scheme,r,'Dr',NaN);
    one.Ar=dmt_vm_measure(cfg,condition,M,one.power.b,cfg.design_A_symbols,trainingSeed,'Ar',[]);
    H=one.Ar.H_hat;
    hHash=dmt_v13_hash(H);
    one.Dr=dmt_vm_measure(cfg,condition,M,one.power.b,cfg.design_D_symbols,validationSeed,'Dr',H);
    assert(isequal(one.Ar.M,M) && isequal(one.Dr.M,M) && isequaln(one.Dr.H_used,H) && ...
        strcmp(hHash,dmt_v13_hash(H)) && all(one.Dr.tested_bits==cfg.design_D_symbols*log2(M)));
    [one.CI_low,one.CI_high]=dmt_wilson(one.Dr.error_bits,one.Dr.tested_bits);
    costs.power_seconds=costs.power_seconds+one.power.compute_seconds;
    costs.training_seconds=costs.training_seconds+one.Ar.compute_seconds;
    costs.validation_seconds=costs.validation_seconds+one.Dr.compute_seconds;
    decisionTimer=tic;
    outcome=dmt_vm_decisions(cfg,scheme,[],M,one.CI_low,one.CI_high,r);
    costs.loading_seconds=costs.loading_seconds+toc(decisionTimer);
    one.supported_k=outcome.supported_k;
    one.status=outcome.status;
    one.reason=outcome.reason;
    one.proposed_next_M=outcome.next_M;
    design.rounds(end+1)=one; %#ok<AGROW>
    feedback.validation_status_entries=feedback.validation_status_entries+numel(cfg.k);
    feedback.loading_table_entries=feedback.loading_table_entries+numel(cfg.k);
    feedback.configuration_ack_count=feedback.configuration_ack_count+1;
    if outcome.accepted
        final=configuration('accepted',M,r);
        final.b=one.power.b;
        final.H_hash=hHash;
        final.power_hash=dmt_v13_hash(one.power);
        final.validation_hash=dmt_v13_hash(one.Dr);
        final.channel_training_hash=dmt_v13_hash(one.Ar);
        final.profile_id=profileID(final);
        [design.final_tx,design.final_rx,design.ack]=dmt_vm_agree(cfg,final);
        design.M=M;
        design.b=one.power.b;
        design.H_hat=H;
        feedback.loading_table_entries=feedback.loading_table_entries+numel(cfg.k);
        feedback.configuration_ack_count=feedback.configuration_ack_count+1;
    end
    if outcome.terminal
        design.status=outcome.status;
        design.reason=outcome.reason;
        break;
    end
    M=outcome.next_M;
end
costs.design_seconds=toc(timer);
design.costs=costs;
design.feedback=feedback;
assert(strcmp(sharedHash,dmt_v13_hash(shared)),'DMT:VMChangedProbe','Shared probe changed during design.');
assert(ismember(string(design.status),["accepted","design_rejected"]));

    function cfgRecord=configuration(stage,order,round)
        cfgRecord=struct('protocol',cfg.protocol,'condition_id',condition.condition_id, ...
            'P_target',condition.P_target,'q',condition.q,'calibration_id',calID, ...
            'scheme',scheme,'phase',shared.phase,'stage',stage,'round',round,'profile_id','', ...
            'M',order,'bits_k',log2(order),'Es_reference',cfg.Es, ...
            'targetBER',cfg.targetBER,'margin_dB',cfg.margin_dB,'adc_range',cfg.adc_range, ...
            'initial_shared_hash',sharedHash,'case_id',condition.case_id,'swing',condition.swing, ...
            'channel_hash',dmt_v13_hash(condition.h));
    end
end

function id=profileID(tx)
digest=dmt_v13_hash(rmfield(tx,'profile_id'));
id=sprintf('c%02d_cal%02d_%s_r%02d_%s_%s',tx.condition_id,tx.calibration_id, ...
    tx.scheme,tx.round,tx.stage,digest(1:12));
end
