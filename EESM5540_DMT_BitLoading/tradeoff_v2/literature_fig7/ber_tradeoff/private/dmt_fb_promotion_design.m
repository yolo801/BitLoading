function record=dmt_fb_promotion_design(cfg,cond,cal,branch,shared,plan,progress)
%DMT_FB_PROMOTION_DESIGN Test one optional promotion, then the v2 fallback.
% Shared probe evidence and formal payload are outside the attempt loop.
if nargin<7,progress=[];end
assert(isempty(progress) || isa(progress,'function_handle'));
branch=validatestring(branch,{'OriginalVerifiedLoading','PromotionFirstLoading'});
assert(strcmp(shared.status,'complete') && isequaln(shared.condition,cond) && ...
    shared.calibration_id==cal && isequaln(shared.feedback_sent,shared.feedback_received) && ...
    strcmp(dmt_v13_hash(shared.feedback_received),shared.feedback_hash_received) && ...
    isequal(shared.gamma_B,shared.feedback_received.gamma_B) && ...
    all(isfinite(shared.gamma_B) & shared.gamma_B>0));
sharedHash=dmt_v13_hash(shared);
allocationTimer=tic;
[base,predictions,allowed]=dmt_fb_promotion_initial(cfg,shared);
allocationSeconds=toc(allocationTimer);
scheme='ValidatedLoading';
phase=shared.phase;
template=struct('round',0,'M',zeros(0,1),'candidate_tx',struct(), ...
    'candidate_rx',struct(),'candidate_ack',struct(),'power',struct(), ...
    'Ar',struct(),'Dr',struct(),'CI_low',zeros(0,1),'CI_high',zeros(0,1), ...
    'supported_k',false(0,1),'status','','proposed_next_M',zeros(0,1));
costs=struct('loading_seconds',allocationSeconds,'power_seconds',0, ...
    'training_seconds',0,'validation_seconds',0,'design_seconds',0);
feedback=struct('initial_quality_scalar_count',numel(cfg.k), ...
    'validation_status_entries',0,'loading_table_entries',0, ...
    'configuration_ack_count',0,'serialized_bits',NaN);
emptyDesign=struct('condition',cond,'calibration_id',cal,'phase',phase, ...
    'scheme',scheme,'initial_shared_hash',sharedHash,'initial_gamma_B',shared.gamma_B, ...
    'initial_M',base,'predicted_BER_design',predictions,'initial_allowed',allowed, ...
    'status','no_initial_candidate','rounds',repmat(template,1,0), ...
    'M',zeros(0,1),'b',zeros(0,1),'H_hat',complex(zeros(0,1)), ...
    'final_tx',struct(),'final_rx',struct(),'ack',struct(),'costs',costs,'feedback',feedback);
eventTemplate=struct('attempt_path','','round',0,'role','','symbols',0, ...
    'data_seed',NaN,'noise_seed',NaN,'status','');
[state,runStandard,eligibility]=dmt_fb_promotion_route(branch,base,cfg.k,'','');
record=struct('branch',branch,'condition',cond,'calibration_id',cal,'phase',phase, ...
    'status','no_initial_candidate','initial_M',base, ...
    'promotion_eligible',strcmp(eligibility,'eligible_k23_16qam'), ...
    'eligibility_reason',eligibility,'promotion_state',state, ...
    'promotion',[],'standard',[],'final',[],'events',repmat(eventTemplate,1,0), ...
    'failure',[],'partial_attempt',[]);
if isempty(base)
    emptyDesign.costs.design_seconds=allocationSeconds;
    record.standard=emptyDesign;
    return;
end
if record.promotion_eligible
    promoted=base;
    promoted(cfg.k==23)=64;
    testedPromotion=execute('promotion',promoted,1);
    record.promotion=testedPromotion;
    [record.promotion_state,runStandard]=dmt_fb_promotion_route( ...
        branch,base,cfg.k,record.promotion.status,'');
    record.status=record.promotion.status;
    if strcmp(record.status,'accepted'),record.final=record.promotion;end
end
if runStandard
    testedStandard=execute('standard',base,cfg.max_rounds);
    record.standard=testedStandard;
    status='';
    if ~isempty(record.promotion),status=record.promotion.status;end
    record.promotion_state=dmt_fb_promotion_route(branch,base,cfg.k,status,record.standard.status);
    record.status=record.standard.status;
    if strcmp(record.status,'accepted'),record.final=record.standard;end
end
assert(strcmp(sharedHash,dmt_v13_hash(shared)),'DMT:FBSharedChanged','Shared probe changed.');

    function design=execute(path,M,nRounds)
        view=dmt_fb_promotion_plan_for(plan,branch,path);
        design=emptyDesign;
        started=tic;
        for r=1:nRounds
            one=template;one.round=r;one.M=M;
            stage='configuration';
            try
                offer=makeConfiguration(M,r,'candidate');
                [one.candidate_tx,one.candidate_rx,one.candidate_ack]=dmt_to_agree(cfg,offer);
                assert(one.candidate_ack.accepted && isequal(one.candidate_tx.M,one.candidate_rx.M));
                stage='power';
                powerSeed=dmt_to_seed(view,cond.condition_id,cal,scheme,r,'power',NaN);
                assert(isnan(powerSeed.noise_seed));
                one.power=dmt_to_power_cal(cfg,cond,M,powerSeed.data_seed);
                design.costs.power_seconds=design.costs.power_seconds+one.power.compute_seconds;
                emit(path,r,'power',one.power.symbols,powerSeed);
                stage='Ar';
                aSeed=dmt_to_seed(view,cond.condition_id,cal,scheme,r,'Ar',NaN);
                one.Ar=dmt_to_measure(cfg,cond,M,one.power.b,cfg.design_A_symbols,aSeed,'Ar',[]);
                design.costs.training_seconds=design.costs.training_seconds+one.Ar.compute_seconds;
                emit(path,r,'Ar',one.Ar.symbols,aSeed);
                stage='Dr';
                dSeed=dmt_to_seed(view,cond.condition_id,cal,scheme,r,'Dr',NaN);
                H=one.Ar.H_hat;
                hHash=dmt_v13_hash(H);
                one.Dr=dmt_to_measure(cfg,cond,M,one.power.b,cfg.design_D_symbols,dSeed,'Dr',H);
                design.costs.validation_seconds=design.costs.validation_seconds+one.Dr.compute_seconds;
                emit(path,r,'Dr',one.Dr.symbols,dSeed);
                assert(isequal(one.Ar.M,M) && isequal(one.Dr.M,M) && ...
                    strcmp(hHash,dmt_v13_hash(H)) && ...
                    all(double(one.Dr.tested_bits)==cfg.design_D_symbols*log2(M)));
                stage='decision';
                decisionTimer=tic;
                [one.CI_low,one.CI_high]=dmt_wilson(double(one.Dr.error_bits),double(one.Dr.tested_bits));
                one.supported_k=one.CI_high<cfg.targetBER;
                decision=dmt_to_decide(cfg,M,one.supported_k,scheme,r);
                if strcmp(path,'promotion') && ~decision.accepted
                    decision.status='promotion_rejected';
                    decision.terminal=true;
                    decision.next_M=base;
                end
                design.costs.loading_seconds=design.costs.loading_seconds+toc(decisionTimer);
                one.status=decision.status;one.proposed_next_M=decision.next_M;
                design.feedback.validation_status_entries=design.feedback.validation_status_entries+numel(cfg.k);
                design.feedback.loading_table_entries=design.feedback.loading_table_entries+numel(cfg.k);
                design.feedback.configuration_ack_count=design.feedback.configuration_ack_count+1;
                if decision.accepted
                    stage='accepted_configuration';
                    final=makeConfiguration(M,r,'accepted');
                    final.b=one.power.b;final.H_hash=hHash;
                    final.power_hash=dmt_v13_hash(one.power);
                    final.validation_hash=dmt_v13_hash(one.Dr);
                    final.channel_training_hash=dmt_v13_hash(one.Ar);
                    final.profile_id=profileID(final);
                    [design.final_tx,design.final_rx,design.ack]=dmt_to_agree(cfg,final);
                    design.M=M;design.b=one.power.b;design.H_hat=H;
                    design.feedback.loading_table_entries=design.feedback.loading_table_entries+numel(cfg.k);
                    design.feedback.configuration_ack_count=design.feedback.configuration_ack_count+1;
                end
                design.rounds(end+1)=one;
                design.status=decision.status;
                if decision.terminal,break;end
                M=decision.next_M;
            catch ME
                design.status='execution_error';
                if any(strcmp(ME.identifier,{'DMT:TOPowerUnreachable','DMT:TOPowerCalibration'}))
                    design.status='power_error';
                end
                record.failure=struct('attempt_path',path,'round',r,'role',stage, ...
                    'identifier',ME.identifier,'detail',getReport(ME,'extended','hyperlinks','off'));
                record.partial_attempt=one;
                break;
            end
        end
        design.costs.design_seconds=toc(started)+allocationSeconds;
    end

    function emit(path,round,role,symbols,seeds)
        event=struct('attempt_path',path,'round',round,'role',role,'symbols',symbols, ...
            'data_seed',seeds.data_seed,'noise_seed',seeds.noise_seed,'status','complete');
        record.events(end+1)=event;
        if ~isempty(progress),progress(event);end
    end

    function offer=makeConfiguration(M,round,stage)
        offer=struct('protocol',cfg.protocol,'condition_id',cond.condition_id, ...
            'P_target',cond.P_target,'q',cond.q,'calibration_id',cal, ...
            'scheme',scheme,'phase',phase,'stage',stage,'round',round, ...
            'profile_id','','M',M(:),'bits_k',log2(M(:)),'Es_reference',cfg.Es, ...
            'targetBER',cfg.targetBER,'margin_dB',cfg.margin_dB, ...
            'adc_range',cfg.adc_range,'initial_shared_hash',sharedHash);
        offer.profile_id=profileID(offer);
    end

    function id=profileID(configuration)
        digest=dmt_v13_hash(rmfield(configuration,'profile_id'));
        id=sprintf('c%02d_cal%02d_%s_r%02d_%s_%s',cond.condition_id,cal,scheme, ...
            configuration.round,configuration.stage,digest(1:12));
    end
end
