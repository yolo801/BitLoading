function run = dmt_simulate(cfg, calibration, profile, schemeIndex, seedLabel, phase, streamSeeds)
% Serial bounded-memory payload test. Never updates calibration or profile.
if strcmp(phase,'main')
    base = cfg.mainSeedBase;
    nSymbols = cfg.mainSymbols;
else
    base = cfg.smokeSeedBase;
    nSymbols = cfg.smokeSymbols;
end
run.scheme = profile.name;
run.started_utc = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss Z'));
runTimer = tic;
run.seed = seedLabel;
run.phase = phase;
run.data_seed = base+1000*schemeIndex+10*seedLabel+1;
run.noise_seed = base+1000*schemeIndex+10*seedLabel+2;
if nargin >= 7
    % v1.2 supplies slot-based streams explicitly; v1.1 mapping stays intact.
    required = {'data_seed','noise_seed','calibration_id','initialization_id'};
    assert(isstruct(streamSeeds) && all(isfield(streamSeeds,required)));
    supplied = [streamSeeds.data_seed streamSeeds.noise_seed];
    assert(all(isfinite(supplied) & supplied==fix(supplied) & ...
        supplied>=0 & supplied<2^32) && supplied(1)~=supplied(2));
    run.data_seed = streamSeeds.data_seed;
    run.noise_seed = streamSeeds.noise_seed;
    run.calibration_id = streamSeeds.calibration_id;
    run.initialization_id = streamSeeds.initialization_id;
end
dataStream = RandStream(cfg.streamType,'Seed',run.data_seed);
noiseStream = RandStream(cfg.streamType,'Seed',run.noise_seed);
run.tested_bits = zeros(numel(cfg.k),1);
run.error_bits = zeros(numel(cfg.k),1);
run.symbols = 0;
run.useful_energy_sum = 0;
run.cp_energy_sum = 0;
run.total_energy_sum = 0;
state = [];
while run.symbols < nSymbols
    count = min(cfg.chunkSize,nSymbols-run.symbols);
    [X,bits] = dmt_random_frame(cfg,profile.M,count,dataStream);
    [Y,stats,state] = dmt_transceive(cfg,X,state,noiseStream,true);
    Z = Y./calibration.H_hat;
    [errors,tested] = dmt_demod_errors(cfg,Z,bits,profile.M);
    run.tested_bits = run.tested_bits + tested;
    run.error_bits = run.error_bits + errors;
    run.symbols = run.symbols + count;
    run.useful_energy_sum = run.useful_energy_sum+stats.useful_energy_sum;
    run.cp_energy_sum = run.cp_energy_sum+stats.cp_energy_sum;
    run.total_energy_sum = run.total_energy_sum+stats.total_energy_sum;
    if mod(run.symbols,20000) == 0 || run.symbols == nSymbols
        if isfield(run,'calibration_id')
            fprintf('calibration_id=%d | ',run.calibration_id);
        end
        fprintf('%s | %s %s seed=%d: %d/%d DMT symbols; elapsed %.3f s\n', ...
            char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss Z')), ...
            phase,profile.name,seedLabel,run.symbols,nSymbols,toc(runTimer));
    end
end
assert(all(run.tested_bits == nSymbols*profile.bits_per_symbol));
assert(all(run.error_bits >= 0 & run.error_bits <= run.tested_bits));
run.elapsed_seconds = toc(runTimer);
run.signal_duration_s = run.symbols*cfg.Ts;
end
