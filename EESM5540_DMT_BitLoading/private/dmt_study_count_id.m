function id = dmt_study_count_id(run)
%DMT_STUDY_COUNT_ID Canonical identity of one complete payload count record.
% Hash numeric dimensions/values and stream/profile identity, not MAT encoding.
assert(isstruct(run) && isscalar(run),'DMT:InvalidCheckpoint','Run must be a scalar struct.');
parts = "DMT v1.2 complete-group count record";
textFields = {'scheme','phase','initialization_id'};
for j = 1:numel(textFields)
    field = textFields{j};
    assert(isfield(run,field),'DMT:InvalidCheckpoint','Missing run.%s.',field);
    value = string(run.(field));
    assert(isscalar(value) && ~ismissing(value),'DMT:InvalidCheckpoint','Invalid run.%s.',field);
    parts(end+1,1) = string(field)+"="+value; %#ok<AGROW>
end
numericFields = {'calibration_id','seed','data_seed','noise_seed','symbols', ...
    'tested_bits','error_bits','useful_energy_sum','cp_energy_sum', ...
    'total_energy_sum','signal_duration_s'};
for j = 1:numel(numericFields)
    field = numericFields{j};
    assert(isfield(run,field),'DMT:InvalidCheckpoint','Missing run.%s.',field);
    value = run.(field);
    assert(isnumeric(value) && isreal(value) && all(isfinite(value(:))), ...
        'DMT:InvalidCheckpoint','Invalid numeric run.%s.',field);
    dimensions = string(sprintf('%d,',size(value)));
    parts(end+1,1) = string(field)+"["+dimensions+"]="+ ...
        string(sprintf('%.17g,',double(value(:)))); %#ok<AGROW>
end
id = dmt_sha256(join(parts,newline));
end
