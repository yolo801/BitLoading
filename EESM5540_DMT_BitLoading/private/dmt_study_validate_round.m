function [valid, reason] = dmt_study_validate_round(saved, cfg, expected)
%DMT_STUDY_VALIDATE_ROUND Verify a frozen fresh calibration before resume.
% An intact infeasible round is valid evidence and must not be replaced in
% search of a feasible profile. Invalid saved data are replayed with the same
% preassigned calibration streams by the caller, never with new seeds.
valid = false;
reason = '';
try
    require(isstruct(saved) && isscalar(saved),'Saved calibration is not a scalar struct.');
    fields = {'config_id','source_id','seed_mapping_id','round'};
    require(all(isfield(saved,fields)),'Missing saved calibration metadata.');
    identifiers = {'config_id','source_id','seed_mapping_id'};
    for j = 1:numel(identifiers)
        field = identifiers{j};
        require(isfield(expected,field) && textEquals(saved.(field),expected.(field)), ...
            ['Saved calibration ' field ' does not match this study.']);
    end
    require(all(isfield(expected,{'calibration_id','round_cfg'})), ...
        'Missing expected calibration ID or configuration.');
    round = saved.round;
    roundFields = {'calibration_id','feasible','calibration','profiles', ...
        'initialization_id','reason','config_snapshot'};
    require(isstruct(round) && isscalar(round) && all(isfield(round,roundFields)), ...
        'Incomplete saved calibration record.');
    require(isnumeric(round.calibration_id) && isscalar(round.calibration_id) && ...
        round.calibration_id==expected.calibration_id && ...
        ismember(round.calibration_id,1:10),'Saved calibration ID differs from its fixed slot.');
    require(isscalar(round.feasible) && (islogical(round.feasible) || ...
        (isnumeric(round.feasible) && isfinite(round.feasible) && ismember(round.feasible,[0 1]))), ...
        'Feasible must be one explicit logical value.');
    roundCfg = round.config_snapshot;
    targetCfg = expected.round_cfg;
    configFields = {'NFFT','NCP','Fs','k','h','Es','sigma_w2','Mset','targetBER', ...
        'margin_dB','trainSymbols','probeSymbols','mainSymbols','chunkSize','seeds', ...
        'trainDataSeed','trainNoiseSeed','probeDataSeed','probeNoiseSeed', ...
        'Tu','TCP','Ts','streamType','specVersion','protocolVersion'};
    require(isstruct(roundCfg) && isscalar(roundCfg) && isstruct(targetCfg), ...
        'Invalid round configuration snapshot.');
    for j = 1:numel(configFields)
        field = configFields{j};
        require(isfield(roundCfg,field) && isfield(targetCfg,field), ...
            ['Missing round configuration ' field '.']);
        require(isequaln(roundCfg.(field),targetCfg.(field)), ...
            ['Round configuration ' field ' changed.']);
    end
    require(textEquals(roundCfg.specVersion,'1.0') && ...
        textEquals(roundCfg.protocolVersion,'1.2'),'Unexpected physical or protocol version.');
    require(roundCfg.mainSymbols==100000 && roundCfg.chunkSize<=2000 && ...
        isequal(roundCfg.k(:),(1:24).') && isequal(roundCfg.seeds,[11 22 33]), ...
        'Frozen payload dimensions or seed labels changed.');
    physicalFields = {'NFFT','NCP','Fs','k','h','Es','sigma_w2','Mset', ...
        'targetBER','margin_dB','trainSymbols','probeSymbols','mainSymbols','chunkSize'};
    for j = 1:numel(physicalFields)
        field = physicalFields{j};
        require(isfield(cfg,field) && isequaln(roundCfg.(field),cfg.(field)), ...
            ['Round physical configuration differs from the study: ' field '.']);
    end
    base = 2000000+100000*round.calibration_id;
    require(roundCfg.trainDataSeed==base+101 && roundCfg.trainNoiseSeed==base+102 && ...
        roundCfg.probeDataSeed==base+201 && roundCfg.probeNoiseSeed==base+202, ...
        'Round A/B random streams do not match the independent v1.2 mapping.');
    calibration = round.calibration;
    calFields = {'H_hat','gamma_hat','gamma_hat_dB','probeSignalSum', ...
        'probeResidualSum','trainingDenominator','H_true','gamma_true_dB'};
    require(isstruct(calibration) && isscalar(calibration) && all(isfield(calibration,calFields)), ...
        'Missing saved calibration estimates or probe sums.');
    for j = 1:numel(calFields)
        value = calibration.(calFields{j});
        require(isnumeric(value) && isequal(size(value),[24 1]) && ...
            all(isfinite(value(:))),'Calibration quantities must be finite 24-by-1 columns.');
    end
    require(all(abs(calibration.H_hat)>0) && isreal(calibration.gamma_hat) && ...
        all(calibration.gamma_hat>0) && isreal(calibration.probeResidualSum) && ...
        all(calibration.probeResidualSum>0),'Invalid channel or positive residual-SNR values.');
    near(calibration.gamma_hat,calibration.probeSignalSum./calibration.probeResidualSum, ...
        'Probe-sum SNR identity is inconsistent.');
    near(calibration.gamma_hat_dB,10*log10(calibration.gamma_hat), ...
        'Linear and dB estimated SNR differ.');
    near(calibration.trainingDenominator,roundCfg.trainSymbols*ones(24,1), ...
        'Known QPSK training energy differs.');
    near(calibration.probeSignalSum,roundCfg.probeSymbols*ones(24,1), ...
        'Known independent QPSK probe energy differs.');
    trueH = fft(roundCfg.h,roundCfg.NFFT).';
    near(calibration.H_true,trueH(roundCfg.k+1),'Diagnostic FIR response differs.');
    near(calibration.gamma_true_dB,10*log10(abs(trueH(roundCfg.k+1)).^2/roundCfg.sigma_w2), ...
        'Diagnostic theoretical SNR differs.');
    [profiles,feasible] = dmt_load_profiles(roundCfg,calibration);
    require(logical(round.feasible)==feasible,'Saved feasibility differs from its own frozen estimate.');
    if feasible
        require(numel(round.profiles)==3,'A feasible round must preserve all three profiles.');
        for j = 1:3
            fields = {'name','M','bits_per_symbol','B','R_payload','role'};
            require(all(isfield(round.profiles(j),fields)),'Saved profile is incomplete.');
            for q = 1:numel(fields)
                field = fields{q};
                a = round.profiles(j).(field); b = profiles(j).(field);
                if isnumeric(a) && isnumeric(b)
                    near(a,b,['Frozen profile value changed: ' field '.']);
                else
                    require(textEquals(a,b),['Frozen profile label changed: ' field '.']);
                end
            end
        end
    else
        require(isempty(round.profiles),'An infeasible round must not invent usable profiles.');
        value = string(round.reason);
        require(isscalar(value) && ~ismissing(value) && strlength(value)>0, ...
            'An infeasible round must record its reason.');
    end
    require(textEquals(round.initialization_id, ...
        dmt_initialization_id(roundCfg,calibration,round.profiles)), ...
        'Frozen calibration/profile digest does not match its values.');
    valid = true;
    reason = 'frozen independent calibration, streams, estimates and profile identity verified';
catch ME
    reason = ME.message;
end
end

function require(condition,message)
assert(isscalar(condition) && logical(condition),'DMT:InvalidCalibrationCheckpoint','%s',message);
end

function same = textEquals(a,b)
a = string(a); b = string(b);
same = isscalar(a) && isscalar(b) && ~ismissing(a) && ~ismissing(b) && a==b;
end

function near(a,b,message)
require(isnumeric(a) && isnumeric(b) && isequal(size(a),size(b)) && ...
    all(isfinite(a(:))) && all(isfinite(b(:))),message);
require(all(abs(double(a(:))-double(b(:))) <= 1e-12+1e-10*abs(double(b(:)))),message);
end
