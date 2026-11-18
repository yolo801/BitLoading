function dmt_fb_promotion_check(record,cfg,cond,cal,branch,shared,plan)
%DMT_FB_PROMOTION_CHECK Reconstruct the control path and audit saved blocks.
assert(isstruct(record) && isscalar(record) && strcmp(record.branch,branch) && ...
    isequaln(record.condition,cond) && record.calibration_id==cal && strcmp(record.phase,shared.phase), ...
    'DMT:FBPromotionIdentity','Promotion record has no matching case/branch.');
[base,predicted,allowed]=dmt_fb_promotion_initial(cfg,shared);
[~,~,eligibility]=dmt_fb_promotion_route(branch,base,cfg.k,'','');
assert(isequal(record.initial_M,base) && strcmp(record.eligibility_reason,eligibility) && ...
    record.promotion_eligible==strcmp(eligibility,'eligible_k23_16qam'));
scheme='ValidatedLoading';
paths={'promotion','standard'};
seen=repmat(record.events,1,0);
failure=record.failure;
hasFailed=any(strcmp(record.status,{'power_error','execution_error'}));
if hasFailed
    assert(isstruct(failure) && isscalar(failure) && any(strcmp(failure.attempt_path,paths)) && ...
        isscalar(failure.round) && isfinite(failure.round) && failure.round==fix(failure.round) && ...
        failure.round>=1 && failure.round<=cfg.max_rounds && ...
        any(strcmp(failure.role,{'configuration','power','Ar','Dr','decision','accepted_configuration'})) && ...
        (strcmp(record.status,'power_error')==any(strcmp(failure.identifier, ...
            {'DMT:TOPowerUnreachable','DMT:TOPowerCalibration'}))) && strlength(string(failure.detail))>0);
else
    assert(isempty(failure) && isempty(record.partial_attempt));
end
if isempty(base)
    assert(~hasFailed && isempty(record.promotion) && isempty(record.final) && isempty(record.events) && ...
        strcmp(record.status,'no_initial_candidate') && strcmp(record.promotion_state,'no_initial_candidate') && ...
        strcmp(record.standard.status,'no_initial_candidate'));
    view=dmt_fb_promotion_plan_for(plan,branch,'standard');
    dmt_t2_check('Design',record.standard,cfg,cond,cal,scheme,NaN,record.phase,view,shared);
    return;
end
attempt='';
fallback='';
if record.promotion_eligible
    assert(~isempty(record.promotion));
    attempt=record.promotion.status;
else
    assert(isempty(record.promotion));
end
[~,runStandard]=dmt_fb_promotion_route(branch,base,cfg.k,attempt,'');
if runStandard
    assert(~isempty(record.standard));
    fallback=record.standard.status;
else
    assert(isempty(record.standard));
end
expectedState=dmt_fb_promotion_route(branch,base,cfg.k,attempt,fallback);
assert(strcmp(record.promotion_state,expectedState));
expectedStatus='no_initial_candidate';
authorized=[];
for pi=1:numel(paths)
    path=paths{pi};
    d=record.(path);
    if isempty(d),continue;end
    expectedStatus=d.status;
    assert(isequaln(d.condition,cond) && d.calibration_id==cal && strcmp(d.phase,record.phase) && ...
        strcmp(d.scheme,scheme) && strcmp(d.initial_shared_hash,dmt_v13_hash(shared)) && ...
        isequal(d.initial_gamma_B,shared.gamma_B) && isequal(d.initial_M,base) && ...
        isequal(d.predicted_BER_design,predicted) && isequal(d.initial_allowed,allowed));
    view=dmt_fb_promotion_plan_for(plan,branch,path);
    candidate=base;
    cap=cfg.max_rounds;
    if strcmp(path,'promotion'),candidate(cfg.k==23)=64;cap=1;end
    failed=hasFailed && strcmp(failure.attempt_path,path);
    assert(numel(d.rounds)<=cap && ...
        (failed && numel(d.rounds)<cap || ~failed && ~isempty(d.rounds)));
    decision=[];
    for r=1:numel(d.rounds)
        one=d.rounds(r);
        auditAttempt(one,view,path,r,candidate);
        assert(nonempty(one.Dr));
        [lo,hi]=dmt_wilson(double(one.Dr.error_bits),double(one.Dr.tested_bits));
        near(one.CI_low,lo); near(one.CI_high,hi);
        supported=hi<cfg.targetBER;
        assert(isequal(one.supported_k,supported));
        decision=dmt_to_decide(cfg,candidate,supported,scheme,r);
        if strcmp(path,'promotion') && ~decision.accepted
            decision.status='promotion_rejected';decision.terminal=true;decision.next_M=base;
        end
        assert(strcmp(one.status,decision.status) && isequal(one.proposed_next_M,decision.next_M) && ...
            (~decision.terminal || r==numel(d.rounds) && ~failed));
        candidate=decision.next_M;
    end
    if failed
        assert(strcmp(d.status,record.status) && failure.round==numel(d.rounds)+1 && ...
            failure.round<=cap && isstruct(record.partial_attempt));
        auditAttempt(record.partial_attempt,view,path,failure.round,candidate);
        if strcmp(record.status,'power_error'),assert(strcmp(failure.role,'power'));end
    else
        assert(decision.terminal && strcmp(d.status,decision.status));
        auditFeedback(d);
        if strcmp(path,'standard')
            dmt_t2_check('Design',d,cfg,cond,cal,scheme,NaN,record.phase,view,shared);
        elseif decision.accepted
            last=d.rounds(end);
            assert(isequal(d.M,last.M) && d.b==last.power.b && isequal(d.H_hat,last.Ar.H_hat));
            auditAgreement(d.final_tx,d.final_rx,d.ack,last.M,'accepted',1);
            tx=d.final_tx;
            assert(tx.b==last.power.b && strcmp(tx.H_hash,dmt_v13_hash(last.Ar.H_hat)) && ...
                strcmp(tx.power_hash,dmt_v13_hash(last.power)) && ...
                strcmp(tx.validation_hash,dmt_v13_hash(last.Dr)) && ...
                strcmp(tx.channel_training_hash,dmt_v13_hash(last.Ar)));
        end
    end
    if strcmp(d.status,'accepted')
        authorized=d;
    else
        assert(isempty(d.M) && isempty(d.b) && isempty(d.H_hat) && ...
            ~nonempty(d.final_tx) && ~nonempty(d.final_rx) && ~nonempty(d.ack));
    end
end
assert(strcmp(record.status,expectedStatus) && isequaln(record.final,authorized) && ...
    isequaln(record.events,seen),'DMT:FBPromotionEvidence', ...
    'Final selection or event ledger differs from the actual attempted blocks.');

    function auditAttempt(one,view,path,r,M)
        assert(isscalar(one) && one.round==r && isequal(one.M,M));
        assert((~nonempty(one.Ar) || nonempty(one.power)) && ...
            (~nonempty(one.Dr) || nonempty(one.Ar)));
        if nonempty(one.candidate_tx)
            auditAgreement(one.candidate_tx,one.candidate_rx,one.candidate_ack,M,'candidate',r);
        else
            assert(~nonempty(one.power));
        end
        if nonempty(one.power)
            power=one.power;
            seed=dmt_to_seed(view,cond.condition_id,cal,scheme,r,'power',NaN);
            assert(isnan(seed.noise_seed) && power.seed==seed.data_seed && isequal(power.M,M) && ...
                power.symbols==cfg.power_cal_symbols && power.sample_count==power.symbols*(cfg.NFFT+cfg.NCP) && ...
                power.target==cond.P_target && power.reachable && power.monotone && ...
                abs(power.actual_mean/cond.P_target-1)<=cfg.power_cal_tolerance && ...
                power.b>=cfg.b_bounds(1) && power.b<=cfg.b_bounds(2) && ...
                ~isempty(regexp(power.waveform_hash,'^[a-f0-9]{64}$','once')));
            add('power',power.symbols,seed,path,r);
        end
        if nonempty(one.Ar)
            seed=dmt_to_seed(view,cond.condition_id,cal,scheme,r,'Ar',NaN);
            auditBlock(one.Ar,M,one.power.b,cfg.design_A_symbols,seed,'Ar');
            assert(one.Ar.training && isempty(one.Ar.H_used) && ...
                all(isnan(one.Ar.error_bits)) && all(isnan(one.Ar.tested_bits)));
            near(one.Ar.H_hat,one.Ar.received_cross_sum./one.Ar.known_energy_sum);
            assert(all(abs(one.Ar.H_hat)>0));
            add('Ar',one.Ar.symbols,seed,path,r);
        end
        if nonempty(one.Dr)
            seed=dmt_to_seed(view,cond.condition_id,cal,scheme,r,'Dr',NaN);
            auditBlock(one.Dr,M,one.power.b,cfg.design_D_symbols,seed,'Dr');
            assert(~one.Dr.training && isequal(one.Dr.H_used,one.Ar.H_hat) && ...
                isequal(one.Dr.H_hat,one.Ar.H_hat));
            H=one.Ar.H_hat;
            residual=one.Dr.received_energy_sum./abs(H).^2+one.Dr.known_energy_sum- ...
                2*real(one.Dr.received_cross_sum./H);
            near(one.Dr.residual_sum_sq,residual);
            near(one.Dr.gamma,one.Dr.known_energy_sum./one.Dr.residual_sum_sq);
            [ok,why]=dmt_to_count_valid(one.Dr.error_bits,one.Dr.tested_bits,M,cfg.design_D_symbols);
            assert(ok,'DMT:FBPromotionCounts','%s',why);
            add('Dr',one.Dr.symbols,seed,path,r);
        end
    end

    function auditBlock(m,M,b,n,seed,role)
        assert(isequaln(m.condition,cond) && strcmp(m.role,role) && strcmp(m.phase,record.phase) && ...
            isequal(m.M,M) && isequal(m.M_rx,M) && m.b==b && m.q==cond.q && ...
            m.symbols==n && m.nSymbols_requested==n && isequaln(m.seeds,seed) && ...
            m.add_noise && m.noise_variance==cfg.noise_variance && ...
            ~m.adc_bypass && isequal(m.adc_range,cfg.adc_range) && ...
            m.metrics.symbols==n && m.metrics.sample_count==n*(cfg.NFFT+cfg.NCP) && ...
            isequal(size(m.known_energy_sum),size(M)) && all(m.known_energy_sum>0) && ...
            isequal(size(m.received_cross_sum),size(M)) && all(isfinite(m.received_cross_sum)) && ...
            isequal(size(m.received_energy_sum),size(M)) && all(m.received_energy_sum>=0));
        limits=[m.metrics.lower_clip_count m.metrics.upper_clip_count ...
            m.metrics.adc_low_count m.metrics.adc_high_count];
        assert(all(isfinite(limits) & limits>=0 & limits==fix(limits)) && ...
            sum(limits(1:2))<=m.metrics.sample_count && sum(limits(3:4))<=m.metrics.sample_count && ...
            m.metrics.tx_min>=0 && m.metrics.tx_max<=cfg.P_peak && m.metrics.tx_min<=m.metrics.tx_max);
    end

    function auditAgreement(tx,rx,ack,M,stage,r)
        [expectedTx,expectedRx,expectedAck]=dmt_to_agree(cfg,tx);
        digest=dmt_v13_hash(rmfield(tx,'profile_id'));
        expectedID=sprintf('c%02d_cal%02d_%s_r%02d_%s_%s',cond.condition_id,cal,scheme,r,stage,digest(1:12));
        assert(isequaln(tx,expectedTx) && isequaln(rx,expectedRx) && isequaln(ack,expectedAck) && ...
            tx.condition_id==cond.condition_id && tx.P_target==cond.P_target && tx.q==cond.q && ...
            tx.calibration_id==cal && strcmp(tx.scheme,scheme) && strcmp(tx.phase,record.phase) && ...
            strcmp(tx.stage,stage) && tx.round==r && isequal(tx.M,M) && ...
            strcmp(tx.profile_id,expectedID) && strcmp(tx.initial_shared_hash,dmt_v13_hash(shared)) && ...
            ~any(isfield(tx,{'H_hat','H_true','noise','error_bits','tested_bits'})));
    end

    function auditFeedback(d)
        n=numel(d.rounds);accepted=strcmp(d.status,'accepted');
        c=d.costs; f=d.feedback;
        assert(all(isfinite([c.loading_seconds c.power_seconds c.training_seconds ...
            c.validation_seconds c.design_seconds])) && ...
            all([c.loading_seconds c.power_seconds c.training_seconds c.validation_seconds c.design_seconds]>=0));
        assert(f.initial_quality_scalar_count==numel(cfg.k) && ...
            f.validation_status_entries==n*numel(cfg.k) && ...
            f.loading_table_entries==(n+accepted)*numel(cfg.k) && ...
            f.configuration_ack_count==n+accepted && isnan(f.serialized_bits));
    end

    function add(role,n,seed,path,r)
        seen(end+1)=struct('attempt_path',path,'round',r,'role',role,'symbols',n, ...
            'data_seed',seed.data_seed,'noise_seed',seed.noise_seed,'status','complete');
    end
end

function yes=nonempty(s)
yes=~isempty(fieldnames(s));
end

function near(a,b)
assert(isequal(size(a),size(b)) && all(isfinite(a(:))) && all(isfinite(b(:))) && ...
    all(abs(a(:)-b(:))<=1e-9*max(1,max(abs(b(:))))),'DMT:FBPromotionNumeric', ...
    'Saved training or validation statistic differs from its independent recalculation.');
end
