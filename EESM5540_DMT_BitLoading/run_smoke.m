function result = run_smoke()
%RUN_SMOKE Optional 2000-symbol-per-strategy local MATLAB preflight.
% Main runs its own preflight; a separate smoke invocation is not required.
projectDir = fileparts(mfilename('fullpath'));
calDir = fullfile(projectDir,'evidence','imported_smoke');
assert(isfile(fullfile(calDir,'config_snapshot.mat')) && ...
    isfile(fullfile(calDir,'initialization.mat')), ...
    'DMT:MissingReference','Keep evidence/imported_smoke with the code package.');
result = run_dmt_experiment('smoke', ...
    'CalibrationDirectory',calDir,'CalibrationMode','reuse');
fprintf('Smoke only; these counts are excluded from formal statistics.\n');
end
