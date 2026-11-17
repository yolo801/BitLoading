function mapping = dmt_v13_seed_mapping(cfg,phase)
% Labels11/22/33 use slots1/2/3; A/B/C and all payload streams are distinct.
phase=validatestring(phase,{'formal','preflight'});
count=cfg.calibrationCount; extra=0;
if strcmp(phase,'preflight'),count=1;extra=100000000;end
rows=cell(4*count*14,1); n=0;
names={'Uniform','Loaded','Fixed16'};
for scenario=cfg.scenarios
    for c=1:count
        base=2000000+10000000*scenario.scenario_idx+100000*c+extra;
        add('A','',NaN,NaN,base+101,base+102);
        add('B','',NaN,NaN,base+201,base+202);
        for s=1:3
            add('C',names{s},NaN,NaN,base+5000+100*s+1,base+5000+100*s+2);
            for j=1:3
                add('payload',names{s},cfg.seeds(j),j,base+1000*s+10*j+1,base+1000*s+10*j+2);
            end
        end
    end
end
mapping=vertcat(rows{:});
seeds=[mapping.data_seed;mapping.noise_seed];
assert(numel(seeds)==numel(unique(seeds)) && all(seeds>=0 & seeds<2^32));

    function add(stage,scheme,label,slot,data,noise)
        n=n+1;
        rows{n}=table(string(phase),scenario.scenario_idx,string(scenario.scenario_id),c, ...
            string(stage),string(scheme),label,slot,data,noise, ...
            'VariableNames',{'phase','scenario_idx','scenario_id','calibration_id','stage', ...
            'scheme','seed_label','slot','data_seed','noise_seed'});
    end
end
