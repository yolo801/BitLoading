function cfg = dmt_v13_config()
%DMT_V13_CONFIG Frozen protocol; original linear physical specification stays1.0.
cfg = dmt_default_config();
cfg.protocolVersion = '1.3';
cfg.imddSpecVersion = '1.0';
cfg.calibrationCount = 10;
cfg.payloadSymbols = 100000;
cfg.preflightSymbols = 2000;
cfg.validationSymbols = 2048;
cfg.normal_transform = 'Inversion';
cfg.gray_mapping_version = 'MATLAB_qammod_gray_bit_UnitAveragePower_v1';
cfg.diag_base = 1500000000;
cfg.papr_thresholds_dB = (0:0.5:18).';
cfg.scenarios = dmt_v13_scenarios(cfg);
cfg.requested_scenarios = 0:3;
end
