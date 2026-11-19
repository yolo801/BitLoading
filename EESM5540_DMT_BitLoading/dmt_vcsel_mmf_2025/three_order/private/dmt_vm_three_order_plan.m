function plan = dmt_vm_three_order_plan(cfg,bandEndGHz)
%DMT_VM_THREE_ORDER_PLAN Freeze independent streams before observing B0.
assert(ismember(bandEndGHz,[60 62]));
namespace=3200000000+1000000*(bandEndGHz-60);
scheme='PerToneValidated';
rows=cell(0,1);
for j=1:numel(cfg.conditions)
    c=cfg.conditions(j);
    group=namespace+10000*c.condition_id;
    append('Shared',0,'initial_power',NaN,group+1,NaN);
    append('Shared',0,'A0',NaN,group+11,group+12);
    append('Shared',0,'B0',NaN,group+21,group+22);
    for r=1:cfg.max_rounds
        trial=group+100*r;
        append(scheme,r,'power',NaN,trial+1,NaN);
        append(scheme,r,'Ar',NaN,trial+11,trial+12);
        append(scheme,r,'Dr',NaN,trial+21,trial+22);
    end
    for slot=1:cfg.payload_repeats
        append(scheme,0,'payload',slot,group+501+slot,group+601+slot);
    end
end
plan=vertcat(rows{:});
hasNoise=isfinite(plan.noise_seed);
assert(isequal(hasNoise,~ismember(plan.role,["initial_power","power"])));
allSeeds=[plan.data_seed;plan.noise_seed(hasNoise)];
assert(numel(unique(allSeeds))==numel(allSeeds) && ...
    all(allSeeds>namespace & allSeeds<namespace+1000000) && ...
    all(allSeeds==fix(allSeeds) & allSeeds<=2^32-1), ...
    'DMT:VMThreeOrderSeeds','Data and noise seeds must be unique across all roles.');

    function append(name,attempt,role,slot,dataSeed,noiseSeed)
        rows{end+1,1}=table("formal",c.condition_id,c.P_target,c.q,1,string(name), ...
            attempt,string(role),slot,dataSeed,noiseSeed,"","",c.case_id,c.swing, ...
            'VariableNames',{'phase','condition_id','P_target','q','calibration_id', ...
            'scheme','round','role','payload_slot','data_seed','noise_seed', ...
            'data_pair_key','noise_pair_key','case_id','swing'});
    end
end
