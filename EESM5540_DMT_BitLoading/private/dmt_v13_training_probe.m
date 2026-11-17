function observations = dmt_v13_training_probe(cfg,scenario,calibrationID,seedPlan)
%DMT_V13_TRAINING_PROBE Known A/B through the actual scenario forward model.
% Only small frequency-domain training/probe records are retained. Each stage
% is a separate stream/run; FIR state is retained within a stage's chunks.
assert(cfg.chunkSize>=1 && cfg.chunkSize<=2000);
assert(cfg.trainSymbols==1024 && cfg.probeSymbols==2048);
assert(istable(seedPlan) && all(ismember( ...
    {'stage','scenario_idx','calibration_id','data_seed','noise_seed'}, ...
    seedPlan.Properties.VariableNames)));
selected = seedPlan.scenario_idx==scenario.scenario_idx & ...
    seedPlan.calibration_id==calibrationID;
a = seedPlan(selected & string(seedPlan.stage)=="A",:);
b = seedPlan(selected & string(seedPlan.stage)=="B",:);
assert(height(a)==1 && height(b)==1,'DMT:V13TrainingSeeds', ...
    'Supply exactly one A and B stream pair for this scenario/calibration.');
allSeeds = [a.data_seed;a.noise_seed;b.data_seed;b.noise_seed];
assert(all(isfinite(allSeeds) & allSeeds>=0 & allSeeds<2^32 & allSeeds==fix(allSeeds)) && ...
    numel(unique(allSeeds))==4,'DMT:V13TrainingSeeds', ...
    'A/B data and noise streams must be distinct valid seeds.');
phase = 'formal';
if ismember('phase',seedPlan.Properties.VariableNames)
    assert(string(a.phase)==string(b.phase),'A and B must share the same phase.');
    phase = char(string(a.phase));
end
assert(ismember(string(phase),["formal" "preflight"]));
base = 2000000+10000000*scenario.scenario_idx+100000*calibrationID;
if strcmp(phase,'preflight'), base=base+100000000; end
assert(a.data_seed==base+101 && a.noise_seed==base+102 && ...
    b.data_seed==base+201 && b.noise_seed==base+202,'DMT:V13TrainingSeeds', ...
    'A/B seeds do not match the frozen scenario/calibration/phase mapping.');
[XA,YA] = makeBlock(cfg.trainSymbols,a.data_seed,a.noise_seed);
[XB,YB] = makeBlock(cfg.probeSymbols,b.data_seed,b.noise_seed);
observations = struct('scenario_idx',scenario.scenario_idx, ...
    'scenario_id',char(string(scenario.scenario_id)),'calibration_id',calibrationID, ...
    'active_k',cfg.k(:),'Es_reference',cfg.Es,'symbols_A',cfg.trainSymbols, ...
    'symbols_B',cfg.probeSymbols,'X_A',XA,'Y_A',YA,'X_B',XB,'Y_B',YB, ...
    'seeds',struct('A_data_seed',a.data_seed,'A_noise_seed',a.noise_seed, ...
    'B_data_seed',b.data_seed,'B_noise_seed',b.noise_seed));
observations.phase = phase;
observations.sample_hash = dmt_v13_hash(observations);

    function [known,received] = makeBlock(nSymbols,dataSeed,noiseSeed)
        dataStream = dmt_v13_stream(cfg,dataSeed);
        noiseStream = dmt_v13_stream(cfg,noiseSeed);
        known = complex(zeros(numel(cfg.k),nSymbols));
        received = known;
        state = [];
        done = 0;
        while done<nSymbols
            count = min(cfg.chunkSize,nSymbols-done);
            X = dmt_v13_make_frame(cfg,4*ones(numel(cfg.k),1),count,dataStream);
            [Y,~,state] = dmt_v13_link(cfg,scenario,X,state,noiseStream,true);
            columns = done+(1:count);
            known(:,columns) = X(cfg.k+1,:);
            received(:,columns) = Y;
            done = done+count;
        end
        assert(all(isfinite(known(:))) && all(isfinite(received(:))));
    end
end
