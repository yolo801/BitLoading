function plan = dmt_t2_plan(cfg,phase)
%DMT_T2_PLAN Predeclare shared and independent roles for the main study.
phase = validatestring(phase,{'preflight','formal'});
calCount = cfg.calibration_count;
if strcmp(phase,'preflight'), calCount=1; end
rows = cell(numel(cfg.P_targets)*numel(cfg.adc_bits)*calCount,1);
i = 0;
for p = 1:numel(cfg.P_targets)
    for qi = 1:numel(cfg.adc_bits)
        target=cfg.P_targets(p); q=cfg.adc_bits(qi);
        condition=(p-1)*numel(cfg.adc_bits)+qi;
        if strcmp(phase,'preflight') && ~ismember([target q],cfg.preflight_points,'rows'),continue;end
        for cal = 1:calCount
            base = cfg.seed_base.(phase)+1000000*p+10000*cal;
            uniqueBase = base+1000*qi;
            group = sprintf('P%d_C%d',p,cal);
            records = {};
            append('Shared',0,'initial_power',NaN,uniqueBase+1,NaN,"","");
            append('Shared',0,'A0',NaN,uniqueBase+11,uniqueBase+12,"","");
            append('Shared',0,'B0',NaN,uniqueBase+21,uniqueBase+22,"","");
            for s = 1:numel(cfg.fixed_M)
                scheme=cfg.scheme_names{s}; fixedBase=base+100*s;
                append(scheme,1,'power',NaN,fixedBase+1,NaN,key('power',s,0),"");
                append(scheme,1,'Ar',NaN,fixedBase+11,fixedBase+12,key('Ar_data',s,0),key('Ar_noise',s,0));
                for slot = 1:cfg.payload_repeats
                    append(scheme,0,'payload',slot,fixedBase+20+slot,base+300+slot, ...
                        key('payload_data',s,slot),key('payload_noise',0,slot));
                end
            end
            scheme=cfg.scheme_names{end};
            for r = 1:cfg.max_rounds
                rBase=uniqueBase+100*r;
                append(scheme,r,'power',NaN,rBase+1,NaN,"","");
                append(scheme,r,'Ar',NaN,rBase+11,rBase+12,"","");
                append(scheme,r,'Dr',NaN,rBase+21,rBase+22,"","");
            end
            for slot = 1:cfg.payload_repeats
                append(scheme,0,'payload',slot,uniqueBase+500+slot,base+300+slot,"",key('payload_noise',0,slot));
            end
            i=i+1; rows{i}=vertcat(records{:});
        end
    end
end
plan=vertcat(rows{1:i});
validateSeeds(plan);
    function append(scheme,r,role,slot,ds,ns,dk,nk)
        records{end+1,1}=table(string(phase),condition,target,q,cal,string(scheme),r, ...
            string(role),slot,ds,ns,string(dk),string(nk),'VariableNames', ...
            {'phase','condition_id','P_target','q','calibration_id','scheme','round', ...
             'role','payload_slot','data_seed','noise_seed','data_pair_key','noise_pair_key'});
    end
    function k = key(role,scheme,slot)
        k=string(sprintf('%s_%s_S%d_J%d',role,group,scheme,slot));
    end
end

function validateSeeds(plan)
assert(isempty(intersect(plan.data_seed,plan.noise_seed)), ...
    'DMT:V2SeedCollision','Data and noise stream identities overlap.');
for name = {'data','noise'}
    role = name{1};
    stream = plan.([role '_seed']); groups = plan.([role '_pair_key']);
    assert(all(isfinite(stream) | (isnan(stream) & groups=="")));
    for value = unique(stream(isfinite(stream))).'
        selected = groups(stream==value);
        if numel(selected)>1
            assert(all(selected~="") && numel(unique(selected))==1, ...
                'DMT:V2SeedCollision','Unplanned reuse of seed %.0f.',value);
        end
    end
    for group = unique(groups(groups~="")).'
        assert(numel(unique(stream(groups==group)))==1, ...
            'DMT:V2SeedPair','Broken common-random-number pairing.');
    end
end
end
