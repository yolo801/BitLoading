function design = dmt_to_design(cfg,condition,calID,scheme,shared,plan)
%DMT_TO_DESIGN Candidate power/A_r/D_r loop without any payload input.
% Every candidate gets a full independent A_r and D_r after its own TX-only
% power calibration. Scientific rejection is a retained result, not an error.
assert(isstruct(shared) && strcmp(shared.status,'complete') && ...
    isequaln(shared.condition,condition) && shared.calibration_id==calID);
scheme=char(string(scheme));assert(any(strcmp(scheme,cfg.scheme_names)));
assert(numel(unique(string(plan.phase)))==1 && strcmp(shared.phase,char(string(plan.phase(1)))));
sharedHash=dmt_v13_hash(shared);
assert(isequaln(shared.feedback_sent,shared.feedback_received) && ...
    strcmp(dmt_v13_hash(shared.feedback_sent),shared.feedback_hash_sent) && ...
    strcmp(shared.feedback_hash_sent,shared.feedback_hash_received));
assert(isequal(shared.gamma_B,shared.feedback_received.gamma_B) && ...
    all(isfinite(shared.gamma_B) & shared.gamma_B>0));
timer=tic;loadingTimer=tic;
[M,predictions,allowed]=initialAllocation(shared.feedback_received.gamma_B, ...
    cfg.Mset,cfg.margin_dB,cfg.targetBER,scheme);
loadingSeconds=toc(loadingTimer);
roundTemplate=struct('round',0,'M',zeros(0,1),'candidate_tx',struct(), ...
    'candidate_rx',struct(),'candidate_ack',struct(),'power',struct(), ...
    'Ar',struct(),'Dr',struct(),'CI_low',zeros(0,1),'CI_high',zeros(0,1), ...
    'supported_k',false(0,1),'status','','proposed_next_M',zeros(0,1));
costs=struct('loading_seconds',loadingSeconds,'power_seconds',0, ...
    'training_seconds',0,'validation_seconds',0,'design_seconds',0);
feedback=struct('initial_quality_scalar_count',numel(cfg.k), ...
    'validation_status_entries',0,'loading_table_entries',0, ...
    'configuration_ack_count',0,'serialized_bits',NaN);
design=struct('condition',condition,'calibration_id',calID,'phase',shared.phase, ...
    'scheme',scheme,'initial_shared_hash',sharedHash,'initial_gamma_B',shared.gamma_B, ...
    'initial_M',M,'predicted_BER_design',predictions,'initial_allowed',allowed, ...
    'status','no_initial_candidate','rounds',repmat(roundTemplate,1,0), ...
    'M',zeros(0,1),'b',zeros(0,1),'H_hat',complex(zeros(0,1)), ...
    'final_tx',struct(),'final_rx',struct(),'ack',struct(), ...
    'costs',costs,'feedback',feedback);
if isempty(M)
    design.costs.design_seconds=toc(timer);
    assert(strcmp(sharedHash,dmt_v13_hash(shared)));return;
end
for r=1:cfg.max_rounds
    one=roundTemplate;one.round=r;one.M=M;
    candidate=makeConfiguration(cfg,condition,calID,scheme,shared.phase,M,r,sharedHash,'candidate');
    [one.candidate_tx,one.candidate_rx,one.candidate_ack]=dmt_to_agree(cfg,candidate);
    assert(isequal(one.candidate_tx.M,one.candidate_rx.M) && one.candidate_ack.accepted);
    powerSeed=dmt_to_seed(plan,condition.condition_id,calID,scheme,r,'power',NaN);
    assert(isnan(powerSeed.noise_seed));
    one.power=dmt_to_power_cal(cfg,condition,M,powerSeed.data_seed);
    costs.power_seconds=costs.power_seconds+one.power.compute_seconds;
    aSeed=dmt_to_seed(plan,condition.condition_id,calID,scheme,r,'Ar',NaN);
    dSeed=dmt_to_seed(plan,condition.condition_id,calID,scheme,r,'Dr',NaN);
    one.Ar=dmt_to_measure(cfg,condition,M,one.power.b,cfg.design_A_symbols,aSeed,'Ar',[]);
    assert(isequal(one.Ar.M,M),'Every changed complete table needs current-M training.');
    H=one.Ar.H_hat;
    hHash=dmt_v13_hash(H);
    one.Dr=dmt_to_measure(cfg,condition,M,one.power.b,cfg.design_D_symbols,dSeed,'Dr',H);
    assert(strcmp(hHash,dmt_v13_hash(H)),'D cannot update the receiver estimate.');
    assert(isequal(one.Dr.M,M) && all(one.Dr.tested_bits==cfg.design_D_symbols*log2(M)));
    [one.CI_low,one.CI_high]=dmt_wilson(one.Dr.error_bits,one.Dr.tested_bits);
    one.supported_k=one.CI_high<cfg.targetBER;
    costs.training_seconds=costs.training_seconds+one.Ar.compute_seconds;
    costs.validation_seconds=costs.validation_seconds+one.Dr.compute_seconds;
    decisionTimer=tic;
    decision=dmt_to_decide(cfg,M,one.supported_k,scheme,r);
    costs.loading_seconds=costs.loading_seconds+toc(decisionTimer);
    one.status=decision.status;one.proposed_next_M=decision.next_M;
    design.rounds(end+1)=one; %#ok<AGROW>
    feedback.validation_status_entries=feedback.validation_status_entries+numel(cfg.k);
    feedback.loading_table_entries=feedback.loading_table_entries+numel(cfg.k);
    feedback.configuration_ack_count=feedback.configuration_ack_count+1;
    if decision.accepted
        final=makeConfiguration(cfg,condition,calID,scheme,shared.phase,M,r,sharedHash,'accepted');
        final.b=one.power.b;final.H_hash=hHash;
        final.power_hash=dmt_v13_hash(one.power);
        final.validation_hash=dmt_v13_hash(one.Dr);
        final.channel_training_hash=dmt_v13_hash(one.Ar);
        final.profile_id=makeID(final);
        [design.final_tx,design.final_rx,design.ack]=dmt_to_agree(cfg,final);
        design.status='accepted';design.M=M;design.b=one.power.b;design.H_hat=H;
        feedback.loading_table_entries=feedback.loading_table_entries+numel(cfg.k);
        feedback.configuration_ack_count=feedback.configuration_ack_count+1;
        break;
    elseif decision.terminal
        design.status=decision.status;break;
    end
    M=decision.next_M; % This untested table is not accepted; next loop tests it.
end
costs.design_seconds=toc(timer);
design.costs=costs;design.feedback=feedback;
assert(strcmp(sharedHash,dmt_v13_hash(shared)),'Shared initial A0/B0 changed during strategy design.');
assert(numel(design.rounds)<=cfg.max_rounds);
if strcmp(design.status,'accepted')
    assert(all(design.rounds(end).CI_high<cfg.targetBER) && design.ack.accepted);
else
    assert(isempty(design.M) && isempty(design.b) && isempty(design.H_hat));
end
end

function [M,predictions,allowed]=initialAllocation(gamma,Mset,margin,target,scheme)
% The Tx allocation sees quality and public settings, never H or payload.
gammaDesign=gamma(:)/10^(margin/10);
predictions=zeros(numel(gamma),numel(Mset));
for j=1:numel(Mset),predictions(:,j)=dmt_qam_ber(Mset(j),gammaDesign);end
allowed=predictions<=target;M=zeros(0,1);
if ~all(allowed(:,1)),return;end
if strcmp(scheme,'UniformAdaptive')
    M=max(Mset(all(allowed,1)))*ones(numel(gamma),1);
else
    M=zeros(numel(gamma),1);
    for k=1:numel(gamma),M(k)=max(Mset(allowed(k,:)));end
end
end

function configuration=makeConfiguration(cfg,condition,calID,scheme,phase,M,r,sharedHash,stage)
configuration=struct('protocol',cfg.protocol,'condition_id',condition.condition_id, ...
    'P_target',condition.P_target,'q',condition.q,'calibration_id',calID, ...
    'scheme',scheme,'phase',phase,'stage',stage,'round',r,'profile_id','', ...
    'M',M(:),'bits_k',log2(M(:)),'Es_reference',cfg.Es, ...
    'targetBER',cfg.targetBER,'margin_dB',cfg.margin_dB,'adc_range',cfg.adc_range, ...
    'initial_shared_hash',sharedHash);
configuration.profile_id=makeID(configuration);
end

function id=makeID(configuration)
unsigned=rmfield(configuration,'profile_id');hash=dmt_v13_hash(unsigned);
id=sprintf('c%02d_cal%02d_%s_r%02d_%s_%s',configuration.condition_id, ...
    configuration.calibration_id,configuration.scheme,configuration.round,configuration.stage,hash(1:12));
end
