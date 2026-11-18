function cfg = dmt_t2_config()
%DMT_T2_CONFIG Declare v2 while retaining the physical baseline from v1.
cfg = dmt_to_config();
cfg.protocol = 'tradeoff_v2';
cfg.protocolVersion = cfg.protocol;
cfg.algorithm_version = '2.0';
cfg.scheme_names = {'FixedQPSK','Fixed64QAM','ValidatedLoading'};
cfg.fixed_M = [4 64];
cfg.fixed_train_symbols = 1024;
cfg.preflight_points = [1.0 8; 1.2 6];
cfg.seed_base = struct('formal',900000000,'preflight',1100000000, ...
    'impairment_diagnostic',1300000000,'diagnostic',1500000000);
cfg.pair_power_tolerance = 0.01;
cfg.diagnostic_symbols_retained = 16;
end
