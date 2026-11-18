function plan=dmt_vm_plan(cfg,phase)
% Freeze all role seeds before any waveform has been generated.
phase=validatestring(phase,{'pilot','formal'});
count=cfg.calibration_count;
namespace=3100000000;
if strcmp(phase,'pilot')
    count=1;
    namespace=3000000000;
end
conditions=cfg.conditions;
assert(isequal([conditions.condition_id],1:6) && all([conditions.P_target]==1) && ...
    all([conditions.q]==8) && cfg.max_rounds==3 && cfg.calibration_count==5 && ...
    cfg.payload_repeats==2 && isequal(cfg.scheme_names,{'UniformValidated','PerToneValidated'}), ...
    'DMT:VMPlan','Frozen work-point, strategy or repeat budget differs.');
rows=cell(0,1);
for c=1:numel(conditions)
    cond=conditions(c);
    for cal=1:count
        group=namespace+100000*cond.condition_id+10000*cal;
        append('Shared',0,'initial_power',NaN,group+1,NaN,"");
        append('Shared',0,'A0',NaN,group+11,group+12,"");
        append('Shared',0,'B0',NaN,group+21,group+22,"");
        for s=1:numel(cfg.scheme_names)
            name=cfg.scheme_names{s};
            schemeBase=group+1000*s;
            for attempt=1:cfg.max_rounds
                candidate=schemeBase+100*attempt;
                append(name,attempt,'power',NaN,candidate+1,NaN,"");
                append(name,attempt,'Ar',NaN,candidate+11,candidate+12,"");
                append(name,attempt,'Dr',NaN,candidate+21,candidate+22,"");
            end
            for slot=1:cfg.payload_repeats
                key=sprintf('%s_C%d_R%d_S%d',phase,cond.condition_id,cal,slot);
                append(name,0,'payload',slot,schemeBase+500+slot,group+900+slot,key);
            end
        end
    end
end
plan=vertcat(rows{:});
assert(sum(plan.role=="payload")==numel(conditions)*count*numel(cfg.scheme_names)*cfg.payload_repeats);
validatePlan(plan,namespace);

    function append(scheme,attempt,role,slot,ds,ns,key)
        rows{end+1,1}=table(string(phase),cond.condition_id,cond.P_target,cond.q,cal,string(scheme), ...
            attempt,string(role),slot,ds,ns,"",string(key),cond.case_id,cond.swing,'VariableNames', ...
            {'phase','condition_id','P_target','q','calibration_id','scheme','round','role','payload_slot', ...
            'data_seed','noise_seed','data_pair_key','noise_pair_key','case_id','swing'});
    end
end

function validatePlan(plan,namespace)
data=plan.data_seed;
noise=plan.noise_seed;
finiteNoise=isfinite(noise);
txOnly=ismember(plan.role,["initial_power","power"]);
assert(isequal(finiteNoise,~txOnly) && all(isnan(noise(txOnly))) && ...
    all(data>namespace & data<namespace+1000000) && ...
    all(noise(finiteNoise)>namespace & noise(finiteNoise)<namespace+1000000) && ...
    numel(unique(data))==height(plan) && isempty(intersect(data,noise(finiteNoise))), ...
    'DMT:VMSeeds','Seed namespace or role independence differs.');
paired=plan.noise_pair_key~="";
assert(isequal(paired,plan.role=="payload") && all(plan.data_pair_key==""));
% Each duplicate receive noise is declared for exactly the two strategies
% of one payload slot. No training, validation or local calibration pairs.
for seed=unique(noise(finiteNoise)).'
    same=plan(noise==seed,:);
    if height(same)==1
        assert(same.noise_pair_key=="");
    else
        assert(height(same)==2 && all(same.role=="payload") && ...
            all(same.noise_pair_key~="") && numel(unique(same.noise_pair_key))==1 && ...
            numel(unique(same.condition_id))==1 && numel(unique(same.calibration_id))==1 && ...
            numel(unique(same.payload_slot))==1 && numel(unique(same.scheme))==2);
    end
end
for key=unique(plan.noise_pair_key(paired)).'
    assert(numel(unique(noise(plan.noise_pair_key==key)))==1);
end
end
