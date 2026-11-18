function tables=dmt_t2_tables(cfg,phase,plan,shared,designs,runs)
%DMT_T2_TABLES Build v2 reports from authenticated design and payload records.
% Conditions and calibration IDs are planned; observations retain exact
% denominators, with one pooled row per carrier only after both repeats.
conditions=unique(plan(:,{'condition_id','P_target','q'}),'rows','sorted');
cals=unique(plan.calibration_id).';
nCal=numel(cals);nSchemes=numel(cfg.scheme_names);nSlots=cfg.payload_repeats;
assert(nSlots==2 && numel(shared)==height(conditions)*nCal && ...
    numel(designs)==numel(shared)*nSchemes && numel(runs)==numel(designs)*nSlots);
nSymbols=cfg.payload_symbols;
if strcmp(phase,'preflight'),nSymbols=cfg.preflight_payload_symbols;end
identity=struct('protocol',string(cfg.protocol),'phase',string(phase), ...
    'test_only',strcmp(phase,'preflight'),'condition_id',NaN,'P_target',NaN, ...
    'q',NaN,'calibration_id',NaN,'scheme',"");
templates=makeTemplates(identity);
names=fieldnames(templates);
rows=cell2struct(repmat({{}},numel(names),1),names,1);

for ci=1:height(conditions)
    c=table2struct(conditions(ci,:));
    for ca=1:nCal
        cal=cals(ca);
        initialIndex=(ci-1)*nCal+ca;
        initial=shared{initialIndex};
        if ~isempty(initial)
            key=makeKey(identity,c,cal,'Shared');
            addPowerCalibration(key,0,"initial_power",initial.power0,false);
            [threshold4,threshold16,threshold64]=thresholds(cfg);
            for k=1:numel(cfg.k)
                ss=makeRow(templates.snr,key);
                ss.k=cfg.k(k);ss.gamma_B0=initial.gamma_B(k);
                ss.SNR_dB=10*log10(ss.gamma_B0);
                ss.threshold_M4_dB=threshold4;
                ss.threshold_M16_dB=threshold16;
                ss.threshold_M64_dB=threshold64;
                ss.data_seed=initial.B0.seeds.data_seed;
                ss.noise_seed=initial.B0.seeds.noise_seed;
                add('snr',ss);
            end
        end
        for si=1:nSchemes
            scheme=cfg.scheme_names{si};
            key=makeKey(identity,c,cal,scheme);
            designIndex=(initialIndex-1)*nSchemes+si;
            d=designs{designIndex};
            measured=runs((designIndex-1)*nSlots+(1:nSlots));
            row=makeRow(templates.summary,key);
            cost=makeRow(templates.overhead,key);
            if ~isempty(d)
                row.design_status=string(d.status);
                authorized=ismember(row.design_status,["fixed_authorized","accepted"]);
                if ismember(row.design_status,["power_error","execution_error"])
                    row.state=row.design_status;
                    row.design_reason=string(d.reason);
                elseif ~authorized
                    row.state="design_rejected";
                    row.design_reason=row.design_status;
                end
                cost=actualCost(cost,cfg,initial,d);
                if authorized
                    row.bits_per_symbol=sum(log2(d.M));
                    row.R_nominal=row.bits_per_symbol/cfg.Ts;
                    row.R_cycle=dmt_t2_cycle_rate(cfg,row.bits_per_symbol,cost.setup_symbols);
                    row.configuration_hash=string(dmt_v13_hash(d.final_tx));
                    row.setup_symbols=cost.setup_symbols;
                    for k=1:numel(cfg.k)
                        p=makeRow(templates.profiles,key);
                        p.k=cfg.k(k);p.M=d.M(k);p.bits_k=log2(p.M);p.b=d.b;
                        p.profile_source=row.design_status;
                        p.configuration_hash=row.configuration_hash;
                        add('profiles',p);
                    end
                end
                if isfield(d,'rounds')
                    for attempt=d.rounds
                        addPowerCalibration(key,attempt.round,"power",attempt.power,false);
                        [~,~,lo,hi]=dmt_t2_adjudicate(cfg,attempt.Dr.error_bits,attempt.Dr.tested_bits,true,true);
                        for k=1:numel(cfg.k)
                            evidence=makeRow(templates.design_rounds,key);
                            evidence.round=attempt.round;evidence.k=cfg.k(k);evidence.M=attempt.M(k);
                            evidence.b=attempt.power.b;
                            evidence.design_status=string(attempt.status);
                            evidence.tested_bits=attempt.Dr.tested_bits(k);evidence.error_bits=attempt.Dr.error_bits(k);
                            evidence.CI_low=lo(k);evidence.CI_high=hi(k);
                            evidence.power_seed=attempt.power.seed;
                            evidence.A_r_data_seed=attempt.Ar.seeds.data_seed;
                            evidence.A_r_noise_seed=attempt.Ar.seeds.noise_seed;
                            evidence.D_r_data_seed=attempt.Dr.seeds.data_seed;
                            evidence.D_r_noise_seed=attempt.Dr.seeds.noise_seed;
                            add('design_rounds',evidence);
                        end
                    end
                elseif isfield(d,'power')
                    addPowerCalibration(key,1,"power",d.power,d.power_reused);
                end
            else
                authorized=false;
            end
            add('overhead',cost);
            actualPower=nan(1,nSlots);
            matched=false(1,nSlots);
            e=zeros(numel(cfg.k),1);n=e;
            for slot=1:nSlots
                s=makeRow(templates.status,key);
                seeds=dmt_to_seed(plan,c.condition_id,cal,scheme,0,'payload',slot);
                s.payload_slot=slot;s.data_seed=seeds.data_seed;s.noise_seed=seeds.noise_seed;
                s.planned_symbols=nSymbols;s.design_status=row.design_status;
                s.status=row.state;s.reason=row.design_reason;
                r=measured{slot};
                if ~isempty(r)
                    assert(authorized && isequaln(r.seeds,seeds) && r.symbols==nSymbols && ...
                        r.payload_slot==slot && strcmp(r.scheme,scheme), ...
                        'DMT:V2UnexpectedPayload','Observed payload lacks a matching authorized slot.');
                    [ok,reason]=dmt_to_count_valid(r.error_bits,r.tested_bits,d.M,nSymbols);
                    assert(ok,'DMT:V2PayloadCount','%s',reason);
                    actualPower(slot)=r.metrics.tx_sum/r.metrics.sample_count;
                    matched(slot)=abs((actualPower(slot)-c.P_target)/c.P_target)<=cfg.payload_power_tolerance;
                    assert(actualPower(slot)==r.power_actual && matched(slot)==r.power_match);
                    e=e+double(r.error_bits);n=n+double(r.tested_bits);
                    s.status="completed";s.actual_symbols=r.symbols;s.reason="";
                    s.tested_bits=sum(r.tested_bits);s.error_bits=sum(r.error_bits);
                    s.P_actual=actualPower(slot);s.power_match=matched(slot);
                    s.configuration_hash=row.configuration_hash;
                    add('power_adc',powerRow(makeRow(templates.power_adc,key),r,slot,matched(slot)));
                    addCounts('seed',key,d.M,double(r.error_bits),double(r.tested_bits), ...
                        slot,r.symbols,seeds.data_seed,seeds.noise_seed);
                elseif authorized
                    s.reason="authorized_payload_not_measured";
                elseif isempty(d)
                    s.reason="no_saved_design";
                end
                add('status',s);
            end
            row.payload_slots_completed=sum(isfinite(actualPower));
            row.power_match=row.payload_slots_completed==nSlots && all(matched);
            if row.payload_slots_completed>0
                valid=actualPower(isfinite(actualPower));
                row.P_actual_min=min(valid);row.P_actual_max=max(valid);
                row.power_state="matched_measured_slots";
                if any(~matched(isfinite(actualPower))),row.power_state="power_mismatch";end
            end
            if row.payload_slots_completed==nSlots
                [row.state,row.BER_state,lo,hi]=dmt_t2_adjudicate(cfg,e,n,true,row.power_match);
                row.Umax=max(hi);row.Umax_over_target=row.Umax/cfg.targetBER;
                row.total_tested_bits=sum(n);row.total_error_bits=sum(e);
                row.overall_BER=sum(e)/sum(n);
                row.lower_exceeds_target_count=sum(lo>cfg.targetBER);
                addCounts('pool',key,d.M,e,n,NaN,nSlots*nSymbols,NaN,NaN);
            end
            add('summary',row);
        end
    end
end

checkFixedPairs(cfg,conditions,cals,designs,runs);
tables=struct();
for j=1:numel(names)
    name=names{j};tables.(name)=rowTable(rows.(name),templates.(name));
end
tables.scenario=scenarioTable(conditions,identity,cfg,tables.summary,nCal);
tables.requirements=requirementTable(cfg,identity,tables.scenario);
tables.pair_gains=pairTable(cfg,identity,tables.summary,tables.status,tables.scenario);

    function add(name,row)
        rows.(name){end+1,1}=row;
    end

    function addCounts(name,key,M,err,bits,slot,symbols,dataSeed,noiseSeed)
        [~,~,lo,hi]=dmt_t2_adjudicate(cfg,err,bits,true,true);
        for carrier=1:numel(cfg.k)
            one=makeRow(templates.(name),key);
            one.k=cfg.k(carrier);one.M=M(carrier);one.payload_slot=slot;
            one.actual_symbols=symbols;one.data_seed=dataSeed;one.noise_seed=noiseSeed;
            one.tested_bits=bits(carrier);one.error_bits=err(carrier);
            one.BER=err(carrier)/bits(carrier);one.CI_low=lo(carrier);one.CI_high=hi(carrier);
            one.CI_upper_over_target=hi(carrier)/cfg.targetBER;
            add(name,one);
        end
    end

    function addPowerCalibration(key,round,role,p,reused)
        % A nested assignment to row would replace the parent summary row.
        powerRecord=makeRow(templates.power_cal,key);
        powerRecord.round=round;powerRecord.role=role;powerRecord.reused=reused;
        powerRecord.data_seed=p.seed;powerRecord.symbols=p.symbols;powerRecord.samples=p.sample_count;
        powerRecord.b=p.b;powerRecord.P_actual=p.actual_mean;powerRecord.relative_error=p.relative_error;
        powerRecord.waveform_hash=string(p.waveform_hash);
        powerRecord.lower_clip_count=p.lower_clip_count;powerRecord.upper_clip_count=p.upper_clip_count;
        powerRecord.optical_second_moment=p.mean_square;
        if reused,powerRecord.compute_seconds=0;else,powerRecord.compute_seconds=p.compute_seconds;end
        add('power_cal',powerRecord);
    end
end

function key=makeKey(key,c,cal,scheme)
key.condition_id=c.condition_id;key.P_target=c.P_target;key.q=c.q;
key.calibration_id=cal;key.scheme=string(scheme);
end

function row=makeRow(row,key)
names=fieldnames(key);
for j=1:numel(names)
    name=names{j};row.(name)=key.(name);
end
end

function t=makeTemplates(key)
t=struct();
t.seed=extend(key,struct('k',NaN,'M',NaN,'payload_slot',NaN,'actual_symbols',NaN, ...
    'data_seed',NaN,'noise_seed',NaN,'tested_bits',NaN,'error_bits',NaN,'BER',NaN, ...
    'CI_low',NaN,'CI_high',NaN,'CI_upper_over_target',NaN));
t.pool=t.seed;
t.summary=extend(key,struct('state',"incomplete",'BER_state',"incomplete",'power_state',"unmeasured", ...
    'design_status',"unmeasured",'design_reason',"",'payload_slots_completed',0,'power_match',false, ...
    'P_actual_min',NaN,'P_actual_max',NaN,'Umax',NaN,'Umax_over_target',NaN, ...
    'total_tested_bits',NaN,'total_error_bits',NaN,'overall_BER',NaN,'lower_exceeds_target_count',NaN, ...
    'bits_per_symbol',NaN,'R_nominal',NaN,'R_cycle',NaN,'setup_symbols',NaN,'configuration_hash',""));
t.status=extend(key,struct('payload_slot',NaN,'status',"incomplete",'reason',"",'design_status',"unmeasured", ...
    'planned_symbols',NaN,'actual_symbols',NaN,'data_seed',NaN,'noise_seed',NaN, ...
    'tested_bits',NaN,'error_bits',NaN,'P_actual',NaN,'power_match',false,'configuration_hash',""));
t.profiles=extend(key,struct('k',NaN,'M',NaN,'bits_k',NaN,'b',NaN,'profile_source',"",'configuration_hash',""));
t.snr=extend(key,struct('k',NaN,'gamma_B0',NaN,'SNR_dB',NaN,'threshold_M4_dB',NaN, ...
    'threshold_M16_dB',NaN,'threshold_M64_dB',NaN,'data_seed',NaN,'noise_seed',NaN));
t.overhead=extend(key,struct('A0_symbols',NaN,'B0_symbols',NaN,'Ar_symbols',NaN,'Dr_symbols',NaN, ...
    'setup_symbols',NaN,'cycle_payload_symbols',NaN,'control_delay_s',NaN, ...
    'initial_quality_scalars',NaN,'validation_status_entries',NaN,'loading_table_entries',NaN, ...
    'configuration_acks',NaN,'serialized_control_bits',NaN, ...
    'tx_power_cal_symbols',NaN,'tx_power_reused',false, ...
    'tx_power_seconds',NaN,'training_seconds',NaN,'validation_seconds',NaN, ...
    'loading_seconds',NaN,'design_seconds',NaN));
t.power_adc=extend(key,struct('payload_slot',NaN,'samples',NaN,'P_actual',NaN, ...
    'power_match',false,'power_relative_error',NaN,'optical_second_moment',NaN, ...
    'drive_mean_square',NaN,'optical_min',NaN,'optical_peak',NaN,'clip_error_mean_square',NaN, ...
    'tx_low_count',NaN,'tx_high_count',NaN,'tx_clip_rate',NaN, ...
    'adc_low_count',NaN,'adc_high_count',NaN,'adc_oob_rate',NaN,'compute_seconds',NaN));
t.power_cal=extend(key,struct('round',NaN,'role',"",'reused',false,'data_seed',NaN, ...
    'symbols',NaN,'samples',NaN,'b',NaN,'P_actual',NaN,'relative_error',NaN, ...
    'waveform_hash',"",'lower_clip_count',NaN,'upper_clip_count',NaN, ...
    'optical_second_moment',NaN,'compute_seconds',NaN));
t.design_rounds=extend(key,struct('round',NaN,'k',NaN,'M',NaN,'b',NaN, ...
    'design_status',"",'tested_bits',NaN,'error_bits',NaN,'CI_low',NaN,'CI_high',NaN, ...
    'power_seed',NaN,'A_r_data_seed',NaN,'A_r_noise_seed',NaN,'D_r_data_seed',NaN,'D_r_noise_seed',NaN));
end

function row=extend(row,fields)
row=makeRow(row,fields);
end

function t=rowTable(rows,template)
if isempty(rows)
    t=struct2table(template,'AsArray',true);t=t([],:);
else
    t=struct2table(vertcat(rows{:}));
end
end

function [a,b,c]=thresholds(cfg)
order=[4 16 64];
factor=4./log2(order).*(1-1./sqrt(order));
gamma=2*(order-1)/3.*erfcinv(2*cfg.targetBER./factor).^2;
db=10*log10(gamma)+cfg.margin_dB;
a=db(1);b=db(2);c=db(3);
end

function cost=actualCost(cost,cfg,initial,d)
cost.cycle_payload_symbols=cfg.payload_symbols;
cost.control_delay_s=cfg.control_delay;
if any(strcmp(d.status,{'power_error','execution_error'})),return;end
cost.A0_symbols=0;cost.B0_symbols=0;cost.Ar_symbols=0;cost.Dr_symbols=0;
cost.tx_power_reused=false;
cost.tx_power_cal_symbols=0;
cost.tx_power_seconds=d.costs.power_seconds;
cost.training_seconds=d.costs.training_seconds;
cost.validation_seconds=d.costs.validation_seconds;
cost.loading_seconds=d.costs.loading_seconds;
cost.design_seconds=d.costs.design_seconds;
if strcmp(d.scheme,'ValidatedLoading')
    cost.A0_symbols=initial.A0.symbols;
    cost.B0_symbols=initial.B0.symbols;
    cost.tx_power_cal_symbols=initial.power0.symbols;
    cost.tx_power_seconds=cost.tx_power_seconds+initial.power0.compute_seconds;
    for one=d.rounds
        cost.Ar_symbols=cost.Ar_symbols+one.Ar.symbols;
        cost.Dr_symbols=cost.Dr_symbols+one.Dr.symbols;
        cost.tx_power_cal_symbols=cost.tx_power_cal_symbols+one.power.symbols;
    end
else
    cost.Ar_symbols=d.Ar.symbols;
    cost.tx_power_cal_symbols=d.power.symbols;
    cost.tx_power_reused=d.power_reused;
end
cost.setup_symbols=cost.A0_symbols+cost.B0_symbols+cost.Ar_symbols+cost.Dr_symbols;
cost.initial_quality_scalars=d.feedback.initial_quality_scalar_count;
cost.validation_status_entries=d.feedback.validation_status_entries;
cost.loading_table_entries=d.feedback.loading_table_entries;
cost.configuration_acks=d.feedback.configuration_ack_count;
end

function p=powerRow(p,r,slot,matched)
m=r.metrics;
p.payload_slot=slot;p.samples=m.sample_count;p.P_actual=m.tx_sum/m.sample_count;
p.power_match=matched;p.power_relative_error=p.P_actual/p.P_target-1;
p.optical_second_moment=m.tx_sum_sq/m.sample_count;
p.drive_mean_square=m.drive_ac_sq_sum/m.sample_count;
p.optical_min=m.tx_min;p.optical_peak=m.tx_max;
p.clip_error_mean_square=m.clip_error_sq_sum/m.sample_count;
p.tx_low_count=m.lower_clip_count;p.tx_high_count=m.upper_clip_count;
p.tx_clip_rate=(p.tx_low_count+p.tx_high_count)/m.sample_count;
p.adc_low_count=m.adc_low_count;p.adc_high_count=m.adc_high_count;
p.adc_oob_rate=(p.adc_low_count+p.adc_high_count)/m.sample_count;
p.compute_seconds=r.compute_seconds;
end

function tableOut=scenarioTable(conditions,identity,cfg,summary,nCal)
rows={};
for ci=1:height(conditions)
    c=table2struct(conditions(ci,:));
    for si=1:numel(cfg.scheme_names)
        scheme=cfg.scheme_names{si};
        one=summary(summary.condition_id==c.condition_id & summary.scheme==string(scheme),:);
        key=makeKey(identity,c,NaN,scheme);key=rmfield(key,'calibration_id');
        r=extend(key,struct('planned_calibrations',nCal,'supported_count',sum(one.state=="supported"), ...
            'ber_failed_count',sum(one.state=="ber_failed"), ...
            'inconclusive_count',sum(one.state=="inconclusive"), ...
            'design_rejected_count',sum(one.state=="design_rejected"), ...
            'power_mismatch_count',sum(one.state=="power_mismatch"), ...
            'power_error_count',sum(one.state=="power_error"), ...
            'execution_error_count',sum(one.state=="execution_error"), ...
            'incomplete_count',sum(one.state=="incomplete"), ...
            'qualified',false,'P_actual_max',NaN,'R_cycle_min',NaN,'R_cycle_median',NaN,'R_cycle_max',NaN, ...
            'measured_rate_calibrations',0,'observed_R_cycle_min',NaN, ...
            'observed_R_cycle_median',NaN,'observed_R_cycle_max',NaN, ...
            'observed_R_nominal_min',NaN,'observed_R_nominal_median',NaN,'observed_R_nominal_max',NaN));
        assert(height(one)==nCal);
        if any(isfinite(one.P_actual_max)),r.P_actual_max=max(one.P_actual_max,[],'omitnan');end
        observed=one.payload_slots_completed==cfg.payload_repeats;
        r.measured_rate_calibrations=sum(observed);
        if any(observed)
            cycle=one.R_cycle(observed);
            nominal=one.R_nominal(observed);
            r.observed_R_cycle_min=min(cycle);
            r.observed_R_cycle_median=median(cycle);
            r.observed_R_cycle_max=max(cycle);
            r.observed_R_nominal_min=min(nominal);
            r.observed_R_nominal_median=median(nominal);
            r.observed_R_nominal_max=max(nominal);
        end
        r.qualified=~key.test_only && nCal==cfg.calibration_count && r.supported_count==nCal;
        if r.qualified
            assert(all(isfinite(one.R_cycle)) && all(isfinite(one.P_actual_max)));
            r.R_cycle_min=min(one.R_cycle);r.R_cycle_median=median(one.R_cycle);r.R_cycle_max=max(one.R_cycle);
        end
        rows{end+1,1}=r; %#ok<AGROW>
    end
end
tableOut=struct2table(vertcat(rows{:}));
end

function t=requirementTable(cfg,identity,scenario)
identity=rmfield(identity,{'condition_id','P_target','calibration_id'});
rows={};
for q=unique(scenario.q).'
    for si=1:numel(cfg.scheme_names)
        for threshold=cfg.R_req
            r=identity;r.q=q;r.scheme=string(cfg.scheme_names{si});
            r.required_rate_bps=threshold;
            r.status="no_qualified_tested_point";r.P_target_selected=NaN;r.P_actual_max=NaN;
            r.R_cycle_min=NaN;r.R_cycle_median=NaN;
            searched=scenario(scenario.q==q & scenario.scheme==r.scheme,:);
            incomplete=any(searched.incomplete_count>0 | searched.power_error_count>0 | ...
                searched.execution_error_count>0);
            if incomplete,r.status="incomplete_scan";end
            if identity.test_only,r.status="test_only";end
            choices=searched(searched.qualified & searched.R_cycle_min>=threshold,:);
            if ~isempty(choices)
                choices=sortrows(choices,{'P_actual_max','P_target'});
                best=choices(1,:);
                r.P_target_selected=best.P_target;r.P_actual_max=best.P_actual_max;
                r.R_cycle_min=best.R_cycle_min;r.R_cycle_median=best.R_cycle_median;
                r.status="qualified_tested_point";
                if incomplete,r.status="qualified_observed_incomplete_scan";end
            end
            rows{end+1,1}=r; %#ok<AGROW>
        end
    end
end
t=struct2table(vertcat(rows{:}));
end

function t=pairTable(cfg,key,summary,status,scenario)
if numel(cfg.scheme_names)==1
    t=table();
    return;
end
key=rmfield(key,'scheme');
rows={};
for j=1:height(summary)
    baseline=summary(j,:);
    si=find(strcmp(cfg.scheme_names,baseline.scheme),1);
    for comparison=si+1:numel(cfg.scheme_names)
        name=string(cfg.scheme_names{comparison});
        cid=baseline.condition_id;cal=baseline.calibration_id;
        other=summary(summary.condition_id==cid & summary.calibration_id==cal & summary.scheme==name,:);
        op=scenario(scenario.condition_id==cid & scenario.scheme==name,:);
        bp=scenario(scenario.condition_id==cid & scenario.scheme==baseline.scheme,:);
        for slot=1:cfg.payload_repeats
            block=status(status.condition_id==cid & status.calibration_id==cal & status.payload_slot==slot,:);
            first=block(block.scheme==baseline.scheme,:);second=block(block.scheme==name,:);
            r=key;r.condition_id=cid;r.q=baseline.q;r.P_target=baseline.P_target;
            r.calibration_id=cal;r.payload_slot=slot;r.baseline=baseline.scheme;r.comparison=name;
            r.baseline_state=baseline.state;r.comparison_state=other.state;
            r.baseline_power=first.P_actual;r.comparison_power=second.P_actual;
            r.noise_seed=first.noise_seed;
            assert(first.noise_seed==second.noise_seed,'DMT:V2PairedNoise','Paired payload noise mismatch in plan.');
            r.pair_power_match=first.power_match && second.power_match && ...
                abs(first.P_actual-second.P_actual)<=cfg.pair_power_tolerance*r.P_target;
            r.status="unmeasured_pair";r.R_cycle_delta_bps=NaN;r.R_cycle_relative_gain=NaN;
            if first.status=="completed" && second.status=="completed"
                if ~r.pair_power_match
                    r.status="pair_power_mismatch";
                elseif ~(op.qualified && bp.qualified)
                    r.status="no_qualified_comparison";
                else
                    r.status="qualified_paired_comparison";
                    r.R_cycle_delta_bps=other.R_cycle-baseline.R_cycle;
                    r.R_cycle_relative_gain=other.R_cycle/baseline.R_cycle-1;
                end
            end
            rows{end+1,1}=r; %#ok<AGROW>
        end
    end
end
t=struct2table(vertcat(rows{:}));
end

function checkFixedPairs(cfg,conditions,cals,designs,runs)
% Verify reused TX power record and invariant measured optical quantities
% when different ADCs act on the same fixed payload waveform.
nSchemes=numel(cfg.scheme_names);nSlots=cfg.payload_repeats;nCal=numel(cals);
for power=unique(conditions.P_target).'
    indices=find(conditions.P_target==power).';
    for ca=1:nCal
        for si=1:numel(cfg.fixed_M)
            reference=[];
            txReference=cell(1,nSlots);
            for ci=indices
                idx=((ci-1)*nCal+ca-1)*nSchemes+si;
                design=designs{idx};
                if isempty(design) || ~strcmp(design.status,'fixed_authorized'),continue;end
                if isempty(reference)
                    reference=design;
                else
                    assert(isequaln(design.power,reference.power) && isequal(design.M,reference.M), ...
                        'DMT:V2FixedPairPower','Fixed ADC comparison does not use one TX power calibration.');
                    assert(isequaln(design.Ar.diagnostic_X,reference.Ar.diagnostic_X) && ...
                        design.Ar.seeds.data_seed==reference.Ar.seeds.data_seed && ...
                        design.Ar.seeds.noise_seed==reference.Ar.seeds.noise_seed, ...
                        'DMT:V2FixedPairTraining','Fixed training input or noise changed across ADC resolution.');
                end
                for slot=1:nSlots
                    r=runs{(idx-1)*nSlots+slot};
                    if isempty(r),continue;end
                    fields={'tx_sum','tx_sum_sq','drive_ac_sq_sum','lower_clip_count','upper_clip_count', ...
                        'clip_error_sq_sum','useful_energy_sum','cp_energy_sum','tx_min','tx_max'};
                    tx=cellfun(@(f)r.metrics.(f),fields);
                    identity={tx,r.seeds.data_seed,r.seeds.noise_seed,r.diagnostic_X};
                    if isempty(txReference{slot})
                        txReference{slot}=identity;
                    else
                        assert(isequaln(txReference{slot},identity),'DMT:V2FixedPairWaveform', ...
                            'Fixed payload waveform or common-noise seed changed across ADC resolution.');
                    end
                end
            end
        end
    end
end
end
