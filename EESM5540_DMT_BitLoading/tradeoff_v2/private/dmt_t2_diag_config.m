function [settings, plan] = dmt_t2_diag_config(cfg)
%DMT_T2_DIAG_CONFIG Predeclare four treatments and intentional seed pairs.
settings = struct('phase','impairment_diagnostic', 'P_target',1.4, ...
    'P_peaks',[2 3], 'q',6, 'calibration_count',5, ...
    'payload_repeats',2, 'seed_base',cfg.seed_base.impairment_diagnostic, ...
    'M',[64*ones(15,1);16*ones(5,1);4*ones(4,1)], ...
    'treatment_names',{{'Peak 2 / 6-bit','Peak 2 / continuous', ...
                        'Peak 3 / 6-bit','Peak 3 / continuous'}});
assert(cfg.chunkSize<=1024 && cfg.payload_symbols==50000 && cfg.initial_A_symbols==1024);
assert(isequal(cfg.adc_range,[-0.1 2.1]) && numel(cfg.k)==numel(settings.M));
phase = strings(0,1);
calibration_id = zeros(0,1);
treatment_id = zeros(0,1);
treatment = strings(0,1);
P_peak = zeros(0,1);
adc_mode = strings(0,1);
role = strings(0,1);
payload_slot = zeros(0,1);
symbols = zeros(0,1);
data_seed = zeros(0,1);
noise_seed = zeros(0,1);
pair_id = strings(0,1);
for c = 1:settings.calibration_count
    base = settings.seed_base + 1000*c;
    for arm = 1:numel(settings.treatment_names)
        peak = settings.P_peaks(ceil(arm/2));
        mode = "quantized";
        if mod(arm,2)==0, mode="continuous_saturated"; end
        addRow("tx_gain_calibration",0,cfg.power_cal_symbols,base+1,NaN);
        addRow("tx_dc_calibration",0,cfg.power_cal_symbols,base+2,NaN);
        addRow("training",0,cfg.initial_A_symbols,base+3,base+4);
        for j = 1:settings.payload_repeats
            addRow("payload",j,cfg.payload_symbols,base+10+2*j,base+11+2*j);
        end
    end
end
plan = table(phase,calibration_id,treatment_id,treatment,P_peak,adc_mode, ...
    role,payload_slot,symbols,data_seed,noise_seed,pair_id);
[group,keys] = findgroups(plan.pair_id);
assert(numel(keys)==settings.calibration_count*(3+settings.payload_repeats));
seeds = zeros(0,1);
for p = 1:numel(keys)
    rows = plan(group==p,:);
    assert(isequal(rows.treatment_id,(1:4).') && numel(unique(rows.data_seed))==1);
    assert(isequaln(rows.noise_seed,repmat(rows.noise_seed(1),height(rows),1)));
    seeds(end+1,1)=rows.data_seed(1); %#ok<AGROW>
    if isfinite(rows.noise_seed(1))
        seeds(end+1,1)=rows.noise_seed(1); %#ok<AGROW>
    end
end
assert(numel(seeds)==numel(unique(seeds)), 'DMT:T2DiagnosticSeedCollision', ...
    'An undeclared diagnostic seed collision occurred.');

    function addRow(stage,slot,n,data,noise)
        phase(end+1,1) = string(settings.phase);
        calibration_id(end+1,1) = c;
        treatment_id(end+1,1) = arm;
        treatment(end+1,1) = string(settings.treatment_names{arm});
        P_peak(end+1,1) = peak;
        adc_mode(end+1,1) = mode;
        role(end+1,1) = stage;
        payload_slot(end+1,1) = slot;
        symbols(end+1,1) = n;
        data_seed(end+1,1) = data;
        noise_seed(end+1,1) = noise;
        pair_id(end+1,1) = compose('cal%02d_%s_slot%02d',c,stage,slot);
    end
end
