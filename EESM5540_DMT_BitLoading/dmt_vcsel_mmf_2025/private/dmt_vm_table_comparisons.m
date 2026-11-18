function [scenario,pairs,sensitivity]=dmt_vm_table_comparisons(cfg,summary,status,formal,T)
%DMT_VM_TABLE_COMPARISONS Qualification and paired conditional interpretations.
caseKey=struct('phase',summary.phase(1),'condition_id',NaN,'case_id',NaN, ...
    'swing',NaN,'q',NaN,'P_target',NaN);
blankScene=addFields(caseKey,struct('strategy',"",'status',"",'planned_calibrations',NaN, ...
    'supported_count',NaN,'ber_failed_count',NaN,'inconclusive_count',NaN, ...
    'power_mismatch_count',NaN,'design_rejected_count',NaN,'power_error_count',NaN, ...
    'execution_error_count',NaN,'incomplete_count',NaN,'qualified',false, ...
    'R_cycle_min',NaN,'R_cycle_median',NaN,'R_cycle_max',NaN, ...
    'observed_R_cycle_min',NaN,'observed_R_cycle_median',NaN,'observed_R_cycle_max',NaN, ...
    'observed_rate_rounds',0,'P_actual_min',NaN,'P_actual_max',NaN, ...
    'attempt_median',NaN,'setup_median_s',NaN,'tx_clip_rate_max',NaN,'adc_oob_rate_max',NaN, ...
    'uniform_M_min',NaN,'uniform_M_max',NaN,'bits_per_symbol_median',NaN));
blankPair=addFields(caseKey,struct('calibration_id',NaN,'uniform_state',"",'pertone_state',"", ...
    'resource_match',false,'pair_qualified',false,'status',"",'uniform_R_cycle',NaN, ...
    'pertone_R_cycle',NaN,'validated_delta_R_cycle',NaN,'validated_rate_ratio',NaN, ...
    'uniform_bits_per_symbol',NaN,'pertone_bits_per_symbol',NaN, ...
    'uniform_T_setup_s',NaN,'pertone_T_setup_s',NaN));
blankLength=addFields(caseKey,struct('calibration_id',NaN,'L',NaN,'pair_qualified',false, ...
    'uniform_R_cycle',NaN,'pertone_R_cycle',NaN,'validated_delta_R_cycle',NaN, ...
    'cross_over_L',NaN,'cross_over_status',"",'is_main_L',false));
sceneRows=repmat(blankScene,0,1);
pairRows=repmat(blankPair,0,1);
lengthRows=repmat(blankLength,0,1);
for cid=unique(summary.condition_id).'
    one=summary(summary.condition_id==cid,:);
    key=table2struct(one(1,fieldnames(caseKey)));
    for scheme=string(cfg.scheme_names)
        rows=one(one.strategy==scheme,:);
        r=addFields(blankScene,key);
        r.strategy=scheme;
        r.planned_calibrations=height(rows);
        r.supported_count=sum(rows.state=="supported");
        r.ber_failed_count=sum(rows.state=="ber_failed");
        r.inconclusive_count=sum(rows.state=="inconclusive");
        r.power_mismatch_count=sum(rows.state=="power_mismatch");
        r.design_rejected_count=sum(rows.state=="design_rejected");
        r.power_error_count=sum(rows.state=="power_error");
        r.execution_error_count=sum(rows.state=="execution_error");
        r.incomplete_count=sum(rows.state=="incomplete");
        r.qualified=formal && height(rows)==cfg.calibration_count && all(rows.state=="supported");
        r.status="not_qualified";
        if ~formal
            r.status="pilot";
        elseif r.power_error_count+r.execution_error_count+r.incomplete_count>0
            r.status="incomplete";
        elseif r.qualified
            r.status="qualified";
        end
        sent=rows.payload_slots_completed==cfg.payload_repeats;
        r.observed_rate_rounds=sum(sent);
        if any(sent)
            observed=rows.R_cycle(sent);
            r.observed_R_cycle_min=min(observed);
            r.observed_R_cycle_median=median(observed);
            r.observed_R_cycle_max=max(observed);
        end
        if r.qualified
            assert(all(sent));
            r.R_cycle_min=r.observed_R_cycle_min;
            r.R_cycle_median=r.observed_R_cycle_median;
            r.R_cycle_max=r.observed_R_cycle_max;
        end
        measured=rows.payload_slots_completed>0;
        if any(measured)
            r.P_actual_min=min(rows.P_actual_min(measured));
            r.P_actual_max=max(rows.P_actual_max(measured));
            r.tx_clip_rate_max=max(rows.tx_clip_rate(measured));
            r.adc_oob_rate_max=max(rows.adc_oob_rate(measured));
        end
        attempted=ismember(rows.design_state,["accepted","design_rejected"]);
        if any(attempted)
            r.attempt_median=median(rows.attempts(attempted));
            r.setup_median_s=median(rows.T_setup_s(attempted));
        end
        accepted=rows.design_state=="accepted";
        if any(accepted)
            B=rows.bits_per_symbol(accepted);
            r.bits_per_symbol_median=median(B);
            if scheme=="UniformValidated"
                uniform=2.^(B/numel(cfg.k));
                assert(all(ismember(uniform,cfg.Mset)));
                r.uniform_M_min=min(uniform);
                r.uniform_M_max=max(uniform);
            end
        end
        sceneRows(end+1,1)=r;
    end
    for ca=unique(one.calibration_id).'
        rows=one(one.calibration_id==ca,:);
        U=rows(rows.strategy=="UniformValidated",:);
        P=rows(rows.strategy=="PerToneValidated",:);
        assert(height(U)==1 && height(P)==1);
        allSlots=status(status.condition_id==cid & status.calibration_id==ca,:);
        Us=sortrows(allSlots(allSlots.strategy=="UniformValidated",:),'payload_slot');
        Ps=sortrows(allSlots(allSlots.strategy=="PerToneValidated",:),'payload_slot');
        assert(isequal(Us.payload_slot,(1:cfg.payload_repeats).') && ...
            isequal(Ps.payload_slot,Us.payload_slot) && isequal(U.q,P.q) && isequal(U.swing,P.swing));
        pair=addFields(blankPair,key);
        pair.calibration_id=ca;
        pair.uniform_state=U.state;
        pair.pertone_state=P.state;
        pair.uniform_T_setup_s=U.T_setup_s;
        pair.pertone_T_setup_s=P.T_setup_s;
        pair.uniform_bits_per_symbol=U.bits_per_symbol;
        pair.pertone_bits_per_symbol=P.bits_per_symbol;
        complete=all(Us.status=="completed" & Ps.status=="completed");
        pairTol=cfg.payload_power_tolerance;
        if isfield(cfg,'pair_power_tolerance'),pairTol=cfg.pair_power_tolerance;end
        pair.resource_match=complete && all(Us.power_match & Ps.power_match & ...
            abs(Us.P_actual-Ps.P_actual)<=U.P_target*pairTol);
        pair.pair_qualified=formal && pair.resource_match && U.state=="supported" && P.state=="supported";
        pair.status="not_both_supported";
        if ~formal
            pair.status="pilot";
        elseif ~complete
            pair.status="pair_unsent_or_incomplete";
        elseif ~pair.resource_match
            pair.status="power_pair_mismatch";
        elseif pair.pair_qualified
            pair.status="qualified_pair";
        end
        if U.payload_slots_completed==cfg.payload_repeats,pair.uniform_R_cycle=U.R_cycle;end
        if P.payload_slots_completed==cfg.payload_repeats,pair.pertone_R_cycle=P.R_cycle;end
        if pair.pair_qualified
            pair.validated_delta_R_cycle=P.R_cycle-U.R_cycle;
            pair.validated_rate_ratio=P.R_cycle/U.R_cycle;
        end
        pairRows(end+1,1)=pair;
        if pair.case_id==2 && pair.swing==.5 && pair.q==8
            length=expandLengths(blankLength,key,pair,T,cfg.payload_symbols);
            lengthRows=[lengthRows;length];
        end
    end
end
scenario=rowsTable(sceneRows,blankScene);
pairs=rowsTable(pairRows,blankPair);
sensitivity=rowsTable(lengthRows,blankLength);
end

function result=expandLengths(blank,key,pair,T,mainL)
row=addFields(blank,key);
row.calibration_id=pair.calibration_id;
row.pair_qualified=pair.pair_qualified;
row.cross_over_status="insufficient_paired_evidence";
L=unique([round(logspace(3,5,61)) mainL]);
if row.pair_qualified
    [row.cross_over_L,row.cross_over_status]=crossing(pair,T);
end
result=repmat(row,numel(L),1);
for j=1:numel(L)
    result(j).L=L(j);
    result(j).is_main_L=L(j)==mainL;
    if row.pair_qualified
        u=L(j)*pair.uniform_bits_per_symbol/(L(j)*T+pair.uniform_T_setup_s);
        p=L(j)*pair.pertone_bits_per_symbol/(L(j)*T+pair.pertone_T_setup_s);
        result(j).uniform_R_cycle=u;
        result(j).pertone_R_cycle=p;
        result(j).validated_delta_R_cycle=p-u;
    end
end
end

function [L,state]=crossing(pair,T)
% Rate equality for positive L, with both setup times and tables held fixed.
U=pair.uniform_bits_per_symbol;
P=pair.pertone_bits_per_symbol;
Su=pair.uniform_T_setup_s;
Sp=pair.pertone_T_setup_s;
L=NaN;
state="no_positive_crossover";
if P==U
    if Su==Sp,state="identical_cycle_rates";end
    return;
end
x=(U*Sp-P*Su)/((P-U)*T);
if isfinite(x) && x>0
    L=x;
    state="positive_crossover";
end
end

function output=addFields(output,values)
f=fieldnames(values);
for j=1:numel(f),output.(f{j})=values.(f{j});end
end

function output=rowsTable(rows,template)
if isempty(rows)
    output=struct2table(template,'AsArray',true);
    output=output([],:);
else
    output=struct2table(rows);
end
end
