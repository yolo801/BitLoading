function [valid, reason] = dmt_study_validate_group(checkpoint, cfg, expected)
%DMT_STUDY_VALIDATE_GROUP Resume only an intact, fully completed fixed group.
% Malformed or partial records return false: their counters must never be
% added to a fresh replay of the same fixed stream.
valid = false;
reason = '';
try
    require(isstruct(checkpoint) && isscalar(checkpoint),'Checkpoint is not a scalar struct.');
    require(isstruct(expected) && isscalar(expected),'Expected metadata is not a scalar struct.');
    fields = {'state','config_id','source_id','seed_mapping_id', ...
        'initialization_id','count_id','run'};
    require(all(isfield(checkpoint,fields)),'Missing checkpoint metadata or complete counts.');
    require(textEquals(checkpoint.state,'complete'),'Checkpoint state is not complete.');
    identifiers = {'config_id','source_id','seed_mapping_id','initialization_id'};
    for j = 1:numel(identifiers)
        field = identifiers{j};
        require(isfield(expected,field),['Missing expected.' field '.']);
        require(textEquals(checkpoint.(field),expected.(field)), ...
            ['Checkpoint ' field ' does not match this run.']);
    end
    require(cfg.mainSymbols==100000,'The fixed main length must be 100000 symbols.');
    require(all(isfield(expected,{'calibration_id','scheme','seed','data_seed','noise_seed','M'})), ...
        'Incomplete expected group metadata.');
    M = expected.M;
    require(isequal(size(M),[numel(cfg.k) 1]) && all(ismember(M,cfg.Mset)), ...
        'Expected profile is not a valid 24-carrier order vector.');
    run = checkpoint.run;
    require(isstruct(run) && isscalar(run),'Run is not a scalar struct.');
    runFields = {'scheme','phase','calibration_id','initialization_id','seed', ...
        'data_seed','noise_seed','symbols','tested_bits','error_bits', ...
        'useful_energy_sum','cp_energy_sum','total_energy_sum','signal_duration_s'};
    require(all(isfield(run,runFields)),'The run is missing required count or identity fields.');
    require(textEquals(run.phase,'main'),'Run phase is not main.');
    require(textEquals(run.scheme,expected.scheme),'Run strategy does not match its group.');
    require(textEquals(run.initialization_id,expected.initialization_id), ...
        'Run calibration/profile identity does not match.');
    numericMetadata = {'calibration_id','seed','data_seed','noise_seed'};
    for j = 1:numel(numericMetadata)
        field = numericMetadata{j};
        value = run.(field);
        require(isnumeric(value) && isscalar(value) && isfinite(value) && ...
            isequal(double(value),double(expected.(field))), ...
            ['Run ' field ' does not match its fixed plan.']);
    end
    require(ismember(run.seed,[11 22 33]) && run.seed~=0,'Payload label must be 11, 22, or 33.');
    require(run.calibration_id>=1 && run.calibration_id<=10 && ...
        run.calibration_id==fix(run.calibration_id),'Invalid calibration ID.');
    schemeNames = {'Uniform','Loaded','Fixed16'};
    schemeIndex = find(strcmp(schemeNames,char(string(run.scheme))));
    slot = find([11 22 33]==run.seed);
    require(isscalar(schemeIndex) && isscalar(slot),'Unknown strategy or payload seed slot.');
    base = 2000000+100000*run.calibration_id;
    require(run.data_seed==base+1000*schemeIndex+10*slot+1 && ...
        run.noise_seed==base+1000*schemeIndex+10*slot+2, ...
        'The v1.2 data/noise stream mapping is incorrect.');
    require(isnumeric(run.symbols) && isscalar(run.symbols) && run.symbols==100000, ...
        'Run did not actually complete 100000 payload symbols.');
    bits = run.tested_bits;
    errors = run.error_bits;
    require(isnumeric(bits) && isreal(bits) && isequal(size(bits),[numel(cfg.k) 1]) && ...
        all(isfinite(bits)) && all(bits==100000*log2(M)), ...
        'Tested-bit counters do not match the fixed symbol count and profile.');
    require(isnumeric(errors) && isreal(errors) && isequal(size(errors),size(bits)) && ...
        all(isfinite(errors)) && all(errors>=0 & errors<=bits & errors==fix(errors)), ...
        'Error counters are not valid completed-group integer counts.');
    energyFields = {'useful_energy_sum','cp_energy_sum','total_energy_sum'};
    for j = 1:numel(energyFields)
        value = run.(energyFields{j});
        require(isnumeric(value) && isreal(value) && isscalar(value) && ...
            isfinite(value) && value>=0,'Energy counts must be finite nonnegative scalars.');
    end
    near(run.total_energy_sum,run.useful_energy_sum+run.cp_energy_sum, ...
        'Useful and CP energies do not sum to the saved total.');
    near(run.signal_duration_s,100000*cfg.Ts,'Saved signal duration is inconsistent.');
    require(textEquals(checkpoint.count_id,dmt_study_count_id(run)), ...
        'The saved group count digest does not match its data.');
    valid = true;
    reason = 'complete fixed group; metadata, streams, count digest and counters verified';
catch ME
    reason = ME.message;
end
end

function require(condition,message)
assert(isscalar(condition) && logical(condition),'DMT:InvalidCheckpoint','%s',message);
end

function same = textEquals(a,b)
a = string(a); b = string(b);
same = isscalar(a) && isscalar(b) && ~ismissing(a) && ~ismissing(b) && a==b;
end

function near(a,b,message)
require(isnumeric(a) && isnumeric(b) && isreal(a) && isreal(b) && ...
    isequal(size(a),size(b)) && all(isfinite(a(:))) && all(isfinite(b(:))),message);
require(all(abs(double(a(:))-double(b(:))) <= 1e-12+1e-10*abs(double(b(:)))),message);
end
