function plan=dmt_to_plan(cfg,phase)
%DMT_TO_PLAN Role-specific streams, shared A0/B0, separate preflight namespace.
phase=validatestring(phase,{'preflight','formal'});
calCount=cfg.calibration_count;if strcmp(phase,'preflight'),calCount=1;end
conditions=dmt_to_conditions(cfg);rows={};
for condition=conditions
    for c=1:calCount
        base=cfg.seed_base.(phase)+1000000*condition.condition_id+10000*c;
        add('Shared',0,'initial_power',NaN,base+1,NaN);
        add('Shared',0,'A0',NaN,base+11,base+12);
        add('Shared',0,'B0',NaN,base+21,base+22);
        for s=1:numel(cfg.scheme_names)
            scheme=cfg.scheme_names{s};
            for r=1:cfg.max_rounds
                offset=base+1000*s+100*r;
                add(scheme,r,'power',NaN,offset+1,NaN);
                add(scheme,r,'Ar',NaN,offset+11,offset+12);
                add(scheme,r,'Dr',NaN,offset+21,offset+22);
            end
            for j=1:cfg.payload_repeats
                offset=base+5000+100*s+10*j;
                add(scheme,0,'payload',j,offset+1,offset+2);
            end
        end
    end
end
plan=vertcat(rows{:});
allSeeds=[plan.data_seed;plan.noise_seed(isfinite(plan.noise_seed))];
assert(numel(unique(allSeeds))==numel(allSeeds) && all(allSeeds>=0 & allSeeds<2^32));
assert(all(isnan(plan.noise_seed(ismember(plan.role,["power","initial_power"])))));
    function add(scheme,r,role,slot,data,noise)
        rows{end+1,1}=table(string(phase),condition.condition_id,condition.P_target,condition.q,c, ...
            string(scheme),r,string(role),slot,data,noise,'VariableNames', ...
            {'phase','condition_id','P_target','q','calibration_id','scheme','round','role', ...
            'payload_slot','data_seed','noise_seed'});
    end
end
