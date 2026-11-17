function mapping = dmt_study_seed_mapping(cfg)
% Exactly eleven stream pairs per calibration: A, B, and nine payload groups.
assert(cfg.NumCalibrations==10 && isequal(cfg.seeds,[11 22 33]));
calibration_id = zeros(0,1); stage = strings(0,1); scheme = stage;
payload_seed = zeros(0,1); slot = payload_seed; base = payload_seed;
data_seed = payload_seed; noise_seed = payload_seed;
names = ["Uniform" "Loaded" "Fixed16"];
for c = 1:cfg.NumCalibrations
    currentBase = 2000000+100000*c;
    append(c,"A","",NaN,NaN,currentBase,currentBase+101,currentBase+102);
    append(c,"B","",NaN,NaN,currentBase,currentBase+201,currentBase+202);
    for s = 1:3
        for j = 1:3
            append(c,"payload",names(s),cfg.seeds(j),j,currentBase, ...
                currentBase+1000*s+10*j+1,currentBase+1000*s+10*j+2);
        end
    end
end
mapping = table(calibration_id,stage,scheme,payload_seed,slot,base,data_seed,noise_seed);
allSeeds = [data_seed;noise_seed];
assert(numel(allSeeds)==220 && numel(unique(allSeeds))==220);
assert(all(allSeeds>=0 & allSeeds<2^32));
old = dmt_seed_mapping(cfg); % Also ensure no collision with reference streams.
oldSeeds = [old.dataSeed;old.noiseSeed];
oldSeeds = oldSeeds(isfinite(oldSeeds));
assert(isempty(intersect(allSeeds,oldSeeds)));

    function append(c,kind,name,label,j,b,d,n)
        calibration_id(end+1,1) = c;
        stage(end+1,1) = kind;
        scheme(end+1,1) = name;
        payload_seed(end+1,1) = label;
        slot(end+1,1) = j;
        base(end+1,1) = b;
        data_seed(end+1,1) = d;
        noise_seed(end+1,1) = n;
    end
end
