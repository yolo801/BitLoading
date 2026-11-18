function cfg=dmt_to_config()
%DMT_TO_CONFIG Complete, predeclared tradeoff_v1 protocol (no payload tuning).
base=dmt_default_config();
names={'NFFT','NCP','Fs','k','Es','Mset','h','targetBER','margin_dB','streamType','Ts'};
cfg=struct();
for j=1:numel(names),cfg.(names{j})=base.(names{j});end
cfg.protocol='tradeoff_v1';cfg.protocolVersion='tradeoff_v1';
cfg.algorithm_version='1.0';cfg.P_targets=[.6 .8 1 1.2 1.4];
cfg.adc_bits=[4 6 8];cfg.scheme_names={'UniformAdaptive','ValidatedLoading'};
cfg.calibration_count=5;cfg.payload_repeats=2;cfg.payload_symbols=50000;
cfg.preflight_payload_symbols=2000;cfg.initial_A_symbols=1024;cfg.initial_B_symbols=2048;
cfg.power_cal_symbols=8192;cfg.design_A_symbols=1024;cfg.design_D_symbols=8192;
cfg.max_rounds=4;cfg.rho=4;cfg.sigma_ref=sqrt(2*numel(cfg.k)/cfg.NFFT);
cfg.P_peak=2;cfg.noise_variance=1.0491e-4;cfg.adc_range=[-.1 2.1];
cfg.power_cal_tolerance=.002;cfg.payload_power_tolerance=.01;
cfg.b_bounds=[0 4];cfg.power_cal_max_iterations=40;cfg.chunkSize=1024;
cfg.normal_transform='Inversion';cfg.R_req=[25 50 75]*1e6;cfg.control_delay=0;
cfg.seed_base=struct('formal',500000000,'preflight',700000000,'diagnostic',1800000000);
cfg.Wilson_z=1.96;cfg.feedback_serialization_bits=NaN;
cfg.representative=struct('P_target',1,'q',8,'calibration_id',1);
cfg.diagnostic_symbols_retained=16;
assert(cfg.NCP>=numel(cfg.h)-1 && sum(cfg.h)==1 && cfg.chunkSize<=2000);
end
