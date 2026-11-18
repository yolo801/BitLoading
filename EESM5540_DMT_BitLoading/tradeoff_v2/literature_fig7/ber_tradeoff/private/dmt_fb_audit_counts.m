function dmt_fb_audit_counts(cfg,tables)
%DMT_FB_AUDIT_COUNTS Check raw repeat denominators, Wilson tests and rates.
summary=tables.summary;
for j=1:height(summary)
    s=summary(j,:);
    status=sortrows(group(tables.status,s),'payload_slot');
    seed=group(tables.seed,s);
    pool=sortrows(group(tables.pool,s),'k');
    assert(isequal(sort(status.payload_slot),(1:cfg.payload_repeats).'), ...
        'DMT:FBAuditSlotIdentity','A planned repeat is absent or duplicated.');
    sent=status.status=="completed";
    assert(s.payload_slots_completed==sum(sent) && height(seed)==sum(sent)*numel(cfg.k), ...
        'DMT:FBAuditSlotCount','Actual repeat summaries and carrier counters disagree.');
    power=group(tables.power_adc,s);
    assert(height(power)==sum(sent),'DMT:FBAuditOpticalPower','Power metric rows do not match completed slots.');
    if any(sent)
        measured=status(sent,:);
        ordered=sortrows(power,'payload_slot');
        measured=sortrows(measured,'payload_slot');
        assert(isequal(ordered.payload_slot,measured.payload_slot) && ...
            isequal(ordered.P_actual,measured.P_actual) && ...
            isequal(measured.power_match,abs((measured.P_actual-s.P_target)/s.P_target)<=cfg.payload_power_tolerance) && ...
            s.P_actual_min==min(measured.P_actual) && s.P_actual_max==max(measured.P_actual), ...
            'DMT:FBAuditOpticalPower','Matched mean power or actual extrema differ.');
    end
    errors=zeros(numel(cfg.k),1);
    tested=errors;
    for slot=find(sent).'
        repeat=sortrows(seed(seed.payload_slot==slot,:),'k');
        assert(isequal(repeat.k,cfg.k(:)) && all(repeat.actual_symbols==status.actual_symbols(slot)) && ...
            all(repeat.tested_bits==status.actual_symbols(slot)*log2(repeat.M)) && ...
            all(repeat.error_bits==fix(repeat.error_bits) & repeat.error_bits>=0 & ...
                repeat.error_bits<=repeat.tested_bits) && ...
            sum(repeat.error_bits)==status.error_bits(slot) && ...
            sum(repeat.tested_bits)==status.tested_bits(slot), ...
            'DMT:FBAuditSlotCount','Integer carrier BER counters or denominators differ.');
        checkWilson(repeat);
        errors=errors+repeat.error_bits;
        tested=tested+repeat.tested_bits;
    end
    if all(sent)
        assert(isequal(pool.k,cfg.k(:)) && isequal(pool.error_bits,errors) && ...
            isequal(pool.tested_bits,tested) && s.total_error_bits==sum(errors) && ...
            s.total_tested_bits==sum(tested) && s.overall_BER==sum(errors)/sum(tested), ...
            'DMT:FBAuditPooledCounts','A pooled count differs from its exact two constituent slots.');
        [lower,upper]=checkWilson(pool);
        berState="inconclusive";
        if all(upper<cfg.targetBER),berState="supported";end
        if any(lower>cfg.targetBER),berState="ber_failed";end
        state=berState;
        match=all(status.power_match);
        if ~match,state="power_mismatch";end
        assert(s.BER_state==berState && s.state==state && s.power_match==match && ...
            abs(s.Umax-max(upper))<=5e-14 && s.lower_exceeds_target_count==sum(lower>cfg.targetBER), ...
            'DMT:FBAuditBERDecision','Whole-profile status differs from the strict pointwise criterion.');
    else
        assert(isempty(pool) && isnan(s.overall_BER), ...
            'DMT:FBAuditPooledCounts','An incomplete or unsent pair has fabricated pooled BER.');
    end
    p=sortrows(group(tables.profiles,s),'k');
    if ~isempty(p)
        overhead=group(tables.overhead,s);
        setup=overhead.A0_symbols+overhead.B0_symbols+overhead.Ar_symbols+overhead.Dr_symbols;
        assert(isequal(p.k,cfg.k(:)) && all(ismember(p.M,cfg.Mset)) && sum(log2(p.M))==s.bits_per_symbol && ...
            setup==s.setup_symbols && setup==overhead.setup_symbols, ...
            'DMT:FBAuditRateInputs','Frozen table capacity or transmitted setup count differs.');
        Ts=(cfg.NFFT+cfg.NCP)/cfg.Fs;
        rate=cfg.payload_symbols*s.bits_per_symbol/((cfg.payload_symbols+setup)*Ts+cfg.control_delay);
        assert(abs(s.R_cycle-rate)<=1e-12*rate && abs(s.R_nominal-s.bits_per_symbol/Ts)<=1e-12*s.R_nominal, ...
            'DMT:FBAuditRate','Nominal or cycle payload rate differs from the frozen profile and transmitted setup.');
    end
end
for j=1:height(tables.scenario)
    s=tables.scenario(j,:);
    rounds=summary(summary.condition_id==s.condition_id & summary.scheme==s.scheme,:);
    expected=~s.test_only && height(rounds)==cfg.calibration_count && all(rounds.state=="supported");
    assert(s.qualified==expected && s.supported_count==sum(rounds.state=="supported"), ...
        'DMT:FBAuditScenario','Condition eligibility differs from its separate calibration statuses.');
    if expected
        assert(isequal([s.R_cycle_min s.R_cycle_median s.R_cycle_max], ...
            [min(rounds.R_cycle) median(rounds.R_cycle) max(rounds.R_cycle)]), ...
            'DMT:FBAuditScenarioRate','Condition rate spread differs from its complete calibration set.');
    end
end
end

function t=group(t,summary)
t=t(t.condition_id==summary.condition_id & t.scheme==summary.scheme & ...
    t.calibration_id==summary.calibration_id,:);
end

function [low,high]=checkWilson(rows)
% Algebraic form using the observed counts directly.
e=rows.error_bits;
n=rows.tested_bits;
z=1.96;
center=(e+z*z/2)./(n+z*z);
radius=z.*sqrt(e.*(1-e./n)+z*z/4)./(n+z*z);
low=max(0,center-radius);
high=min(1,center+radius);
assert(all(abs(rows.BER-e./n)<=5e-14) && all(abs(rows.CI_low-low)<=5e-14) && ...
    all(abs(rows.CI_high-high)<=5e-14), ...
    'DMT:FBAuditWilson','Observed BER or approximate 95%% pointwise Wilson endpoints differ.');
end
