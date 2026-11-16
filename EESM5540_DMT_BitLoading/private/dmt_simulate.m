function run = dmt_simulate(cfg, calibration, profile, schemeIndex, seedLabel, phase)
% Serial bounded-memory payload test. Never updates calibration or profile.
if strcmp(phase,'main')
    base = cfg.mainSeedBase;
    nSymbols = cfg.mainSymbols;
else
    base = cfg.smokeSeedBase;
    nSymbols = cfg.smokeSymbols;
end
run.scheme = profile.name;
run.seed = seedLabel;
run.phase = phase;
run.data_seed = base+1000*schemeIndex+10*seedLabel+1;
run.noise_seed = base+1000*schemeIndex+10*seedLabel+2;
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
        fprintf('%s %s seed=%d: %d/%d DMT symbols\n', ...
            phase,profile.name,seedLabel,run.symbols,nSymbols);
    end
end
assert(all(run.tested_bits == nSymbols*profile.bits_per_symbol));
assert(all(run.error_bits >= 0 & run.error_bits <= run.tested_bits));
end
