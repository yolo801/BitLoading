function output=dmt_fb_audit_promotion(cfg,phase,plan,branches,cond,cals,shared,records,runs)
%DMT_FB_AUDIT_PROMOTION Derive both branch reports and the paired interpretation.
oneCfg=cfg;
oneCfg.scheme_names={'ValidatedLoading'};
oneCfg.fixed_M=[];
nCal=numel(cals);
events=repmat(eventRow(cond,0,''),0,1);
candidates=repmat(candidateRow(cond,0,''),0,1);
base=repmat(baseRow(cond,0,''),0,1);
keys={'original','promotion'};
for b=1:2
    branch=branches{b};
    projection=cell(nCal,1);
    for a=1:nCal
        record=records{a,b};
        initial=shared{a};
        projection{a}=projectDesign(record);
        key=eventRow(cond,cals(a),branch);
        if ~isempty(initial)
            seed=dmt_to_seed(plan,cond.condition_id,cals(a),'Shared',0,'initial_power',NaN);
            events(end+1,1)=actualEvent(key,'shared',0,'initial_power',initial.power0.symbols, ...
                seed.data_seed,seed.noise_seed,'complete');
            for role={'A0','B0'}
                v=initial.(role{1});
                events(end+1,1)=actualEvent(key,'shared',0,role{1},v.symbols, ...
                    v.seeds.data_seed,v.seeds.noise_seed,'complete');
            end
        end
        if isempty(record),continue;end
        for e=reshape(record.events,1,[])
            events(end+1,1)=actualEvent(key,e.attempt_path,e.round,e.role,e.symbols, ...
                e.data_seed,e.noise_seed,e.status);
        end
        for slot=1:cfg.payload_repeats
            v=runs{(a-1)*cfg.payload_repeats+slot,b};
            if isempty(v),continue;end
            row=actualEvent(key,'payload',0,'payload',v.symbols, ...
                v.seeds.data_seed,v.seeds.noise_seed,'complete');
            row.payload_slot=slot;
            events(end+1,1)=row;
        end
        for k=1:numel(record.initial_M)
            row=baseRow(cond,cals(a),branch);
            row.k=cfg.k(k);
            row.M_base=record.initial_M(k);
            row.promotion_eligible=record.promotion_eligible;
            row.promotion_state=string(record.promotion_state);
            base(end+1,1)=row;
        end
        for kind={'promotion','standard'}
            attempt=record.(kind{1});
            if isempty(attempt) || ~isfield(attempt,'rounds'),continue;end
            for one=reshape(attempt.rounds,1,[])
                for k=1:numel(cfg.k)
                    row=candidateRow(cond,cals(a),branch);
                    row.attempt_path=string(kind{1});
                    row.round=one.round;
                    row.k=cfg.k(k);
                    row.M=one.M(k);
                    row.bias=one.power.b;
                    row.error_bits=one.Dr.error_bits(k);
                    row.tested_bits=one.Dr.tested_bits(k);
                    [row.CI_low,row.CI_high]=dmt_wilson(row.error_bits,row.tested_bits);
                    row.supported=row.CI_high<cfg.targetBER;
                    row.decision=string(one.status);
                    row.power_seed=one.power.seed;
                    row.channel_training_seed=one.Ar.seeds.data_seed;
                    row.validation_seed=one.Dr.seeds.data_seed;
                    candidates(end+1,1)=row;
                end
            end
        end
    end
    smallPlan=dmt_fb_promotion_plan_for(plan,branch,'standard');
    t=dmt_t2_tables(oneCfg,phase,smallPlan,shared,projection,runs(:,b));
    t=rmfield(t,'pair_gains');
    details=rowsTable(events,eventRow(cond,0,''));
    for a=1:nCal
        cal=cals(a);
        s=details.calibration_id==cal & details.scheme==string(branch);
        use=details(s,:);
        t.overhead.A0_symbols(a)=sum(use.forward_symbols(use.role=="A0"));
        t.overhead.B0_symbols(a)=sum(use.forward_symbols(use.role=="B0"));
        t.overhead.Ar_symbols(a)=sum(use.forward_symbols(use.role=="Ar"));
        t.overhead.Dr_symbols(a)=sum(use.forward_symbols(use.role=="Dr"));
        t.overhead.setup_symbols(a)=sum(use.forward_symbols);
        t.overhead.tx_power_cal_symbols(a)=sum(use.tx_only_symbols);
        t.summary.setup_symbols(a)=t.overhead.setup_symbols(a);
        if isfinite(t.summary.bits_per_symbol(a))
            rate=dmt_t2_cycle_rate(cfg,t.summary.bits_per_symbol(a),t.overhead.setup_symbols(a));
            assert(abs(t.summary.R_cycle(a)-rate)<=1e-9*rate,'DMT:FBSetupSymbols', ...
                'Round records and raw attempted-block events disagree on cycle overhead.');
        end
    end
    candidateRows=candidates(string({candidates.scheme})==string(branch));
    t.design_rounds=rowsTable(candidateRows,candidateRow(cond,0,''));
    t.power_cal.attempt_path=repmat("shared",height(t.power_cal),1);
    for j=1:height(t.power_cal)
        if t.power_cal.role(j)=="power"
            matches=details.data_seed==t.power_cal.data_seed(j) & details.role=="power" & details.scheme==string(branch);
            assert(sum(matches)==1,'DMT:FBPowerEvent','TX-only power calibration lacks a unique event.');
            t.power_cal.attempt_path(j)=details.attempt_path(matches);
        end
    end
    names=fieldnames(t);
    for j=1:numel(names)
        if ismember('scheme',t.(names{j}).Properties.VariableNames)
            n=t.(names{j}).scheme=="ValidatedLoading";
            t.(names{j}).scheme(n)=string(branch);
        end
    end
    output.(keys{b})=t;
end
output.events=rowsTable(events,eventRow(cond,0,''));
output.initial_profiles=rowsTable(base,baseRow(cond,0,''));
output.pairs=makePairs(cfg,cals,output,records);
end

function d=projectDesign(record)
% Adapt completed rounds for the ordinary v2 table reporter without altering evidence.
d=[];
if isempty(record),return;end
if any(strcmp(record.status,{'power_error','execution_error'}))
    d=struct('status',record.status,'scheme','ValidatedLoading','M',zeros(0,1), ...
        'reason',record.failure.detail);
    return;
end
if strcmp(record.status,'accepted')
    d=record.final;
else
    d=record.standard;
end
if isempty(d)
    error('DMT:FBReportDesign','Terminal branch lacks its canonical completed design.');
end
if hasRound(record.promotion) && ...
        ~isempty(record.standard)
    d.rounds=[reshape(record.promotion.rounds,1,[]) reshape(record.standard.rounds,1,[])];
    for j=1:numel(d.rounds),d.rounds(j).round=j;end
    fields=fieldnames(d.costs);
    for j=1:numel(fields)
        key=fields{j};
        d.costs.(key)=record.promotion.costs.(key)+record.standard.costs.(key);
    end
    for key={'validation_status_entries','loading_table_entries','configuration_ack_count'}
        name=key{1};
        d.feedback.(name)=record.promotion.feedback.(name)+record.standard.feedback.(name);
    end
end
end

function t=makePairs(cfg,cals,output,records)
rows=cell(numel(cals),1);
for a=1:numel(cals)
    left=output.original;
    right=output.promotion;
    A=left.summary(a,:);
    B=right.summary(a,:);
    rA=records{a,1};
    rB=records{a,2};
    rates=nan(1,2);
    if A.payload_slots_completed==cfg.payload_repeats,rates(1)=A.R_cycle/1e6;end
    if B.payload_slots_completed==cfg.payload_repeats,rates(2)=B.R_cycle/1e6;end
    [a23,a24]=finalOrders(left.profiles,cals(a));
    [b23,b24]=finalOrders(right.profiles,cals(a));
    P1=sortrows(left.status(left.status.calibration_id==cals(a),:),'payload_slot');
    P2=sortrows(right.status(right.status.calibration_id==cals(a),:),'payload_slot');
    measured=all(P1.status=="completed" & P2.status=="completed");
    matched=measured && all(P1.power_match & P2.power_match & ...
        abs(P1.P_actual-P2.P_actual)<=cfg.pair_power_tolerance*A.P_target);
    both=A.state=="supported" && B.state=="supported";
    observed=rates(2)-rates(1);
    net=NaN;
    state="awaiting_complete_pair";
    if any(ismember([A.state B.state],["power_error","execution_error"]))
        state="power_or_execution_error";
    elseif any([A.state B.state]=="design_rejected")
        state="one_or_both_design_rejected";
    end
    if measured
        state="one_or_both_not_supported";
        if ~matched
            state="pair_power_mismatch";
        elseif both && A.test_only
            state="test_only";
        elseif both
            state="supported_pair_no_positive_gain";
            net=observed;
            if net>0,state="supported_pair_positive_gain";end
        end
    end
    eligible=false;attempted=false;accepted=false;
    maxD=NaN;
    aState="unmeasured";bState="unmeasured";eligibilityReason="unmeasured";
    if ~isempty(rA),aState=string(rA.status);end
    if ~isempty(rB)
        bState=string(rB.promotion_state);
        eligibilityReason=string(rB.eligibility_reason);
        eligible=rB.promotion_eligible;
        accepted=bState=="promotion_accepted";
        attempted=hasRound(rB.promotion);
        if attempted,maxD=max(rB.promotion.rounds(1).CI_high);end
        if ~isempty(rB.failure) && isfield(rB.failure,'attempt_path')
            attempted=attempted || strcmp(rB.failure.attempt_path,'promotion');
        end
    end
    leftEvents=output.events.scheme=="OriginalVerifiedLoading" & ...
        output.events.calibration_id==cals(a) & output.events.role=="Dr" & output.events.forward_symbols>0;
    rightEvents=output.events.scheme=="PromotionFirstLoading" & ...
        output.events.calibration_id==cals(a) & output.events.role=="Dr" & output.events.forward_symbols>0;
    rows{a}=table(cals(a),aState,bState,eligible,eligibilityReason,attempted,accepted,maxD,a23,a24,b23,b24, ...
        A.state,B.state,A.BER_state,B.BER_state,A.Umax,B.Umax,sum(leftEvents),sum(rightEvents), ...
        A.setup_symbols,B.setup_symbols,A.bits_per_symbol,B.bits_per_symbol,B.bits_per_symbol-A.bits_per_symbol, ...
        rates(1),rates(2),observed,net,matched,right.overhead.Ar_symbols(a)-left.overhead.Ar_symbols(a), ...
        right.overhead.Dr_symbols(a)-left.overhead.Dr_symbols(a),state,'VariableNames', ...
        {'calibration_id','a_candidate_state','b_candidate_state','promotion_eligible','promotion_eligibility_reason','promotion_attempted', ...
        'promotion_accepted','promotion_D_max_CI_high','a_final_M23','a_final_M24','b_final_M23','b_final_M24', ...
        'a_state','b_state','a_BER_state','b_BER_state','a_Umax','b_Umax','a_validation_count','b_validation_count', ...
        'a_setup_symbols','b_setup_symbols','a_bits_per_symbol','b_bits_per_symbol','delta_bits_per_symbol', ...
        'a_R_cycle_Mbps','b_R_cycle_Mbps','delta_observed_R_cycle_Mbps','delta_supported_R_cycle_Mbps', ...
        'pair_power_match','b_additional_Ar_symbols','b_additional_Dr_symbols','comparison_status'});
end
t=vertcat(rows{:});
end

function [m23,m24]=finalOrders(profiles,cal)
m23=NaN;m24=NaN;
p=profiles(profiles.calibration_id==cal,:);
if ~isempty(p)
    m23=p.M(p.k==23);
    m24=p.M(p.k==24);
end
end

function yes=hasRound(value)
yes=isstruct(value) && isfield(value,'rounds') && ~isempty(value.rounds);
end

function r=eventRow(cond,cal,branch)
r=struct('condition_id',cond.condition_id,'P_target',cond.P_target,'q',cond.q, ...
    'calibration_id',cal,'scheme',string(branch),'attempt_path',"",'round',NaN, ...
    'role',"",'payload_slot',NaN,'symbols',NaN,'data_seed',NaN,'noise_seed',NaN,'status',"", ...
    'forward_symbols',0,'forward_payload_symbols',0,'tx_only_symbols',0);
end

function r=actualEvent(r,path,round,role,symbols,dataSeed,noiseSeed,status)
r.attempt_path=string(path);
r.round=round;
r.role=string(role);
r.symbols=symbols;
r.data_seed=dataSeed;
r.noise_seed=noiseSeed;
r.status=string(status);
assert(isscalar(symbols) && isfinite(symbols) && symbols==fix(symbols) && symbols>=0);
if ismember(r.role,["A0","B0","Ar","Dr"]),r.forward_symbols=symbols;end
if r.role=="payload",r.forward_payload_symbols=symbols;end
if ismember(r.role,["initial_power","power"]),r.tx_only_symbols=symbols;end
end

function r=candidateRow(cond,cal,branch)
r=struct('condition_id',cond.condition_id,'P_target',cond.P_target,'q',cond.q, ...
    'calibration_id',cal,'scheme',string(branch),'attempt_path',"",'round',NaN, ...
    'k',NaN,'M',NaN,'bias',NaN,'error_bits',NaN,'tested_bits',NaN,'CI_low',NaN, ...
    'CI_high',NaN,'supported',false,'decision',"",'power_seed',NaN, ...
    'channel_training_seed',NaN,'validation_seed',NaN);
end

function r=baseRow(cond,cal,branch)
r=struct('condition_id',cond.condition_id,'P_target',cond.P_target,'q',cond.q, ...
    'calibration_id',cal,'scheme',string(branch),'k',NaN,'M_base',NaN, ...
    'promotion_eligible',false,'promotion_state',"");
end

function t=rowsTable(rows,template)
if isempty(rows)
    t=struct2table(template,'AsArray',true);
    t=t([],:);
else
    t=struct2table(rows);
end
end
