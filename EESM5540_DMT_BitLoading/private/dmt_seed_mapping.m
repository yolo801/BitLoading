function seeds = dmt_seed_mapping(cfg)
stage = ["self_train"; "self_QPSK"; "self_16QAM"; "self_64QAM"; ...
    "self_noise_variance"; "calibration_A"; "probe_B"];
scheme = repmat("initialization",numel(stage),1);
label = nan(numel(stage),1);
dataSeed = [cfg.selfTrainSeed; cfg.selfPayloadSeeds(:); NaN; ...
    cfg.trainDataSeed; cfg.probeDataSeed];
noiseSeed = [NaN; NaN; NaN; NaN; cfg.selfNoiseSeed; ...
    cfg.trainNoiseSeed; cfg.probeNoiseSeed];
for phase = 1:2
    if phase == 1
        base = cfg.smokeSeedBase;
        labels = 0;
        phaseName = "smoke";
    else
        base = cfg.mainSeedBase;
        labels = cfg.seeds;
        phaseName = "main";
    end
    names = ["Uniform" "Loaded" "Fixed16"];
    for s = 1:numel(names)
        for tag = labels
            stage(end+1,1) = phaseName; %#ok<AGROW>
            scheme(end+1,1) = names(s); %#ok<AGROW>
            label(end+1,1) = tag; %#ok<AGROW>
            dataSeed(end+1,1) = base+1000*s+10*tag+1; %#ok<AGROW>
            noiseSeed(end+1,1) = base+1000*s+10*tag+2; %#ok<AGROW>
        end
    end
end
seeds = table(stage,scheme,label,dataSeed,noiseSeed);
allSeeds = [dataSeed(isfinite(dataSeed));noiseSeed(isfinite(noiseSeed))];
assert(numel(unique(allSeeds)) == numel(allSeeds),'Random stream seed collision.');
end
