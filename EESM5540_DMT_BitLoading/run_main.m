function result = run_main()
%RUN_MAIN Local MATLAB entry: fixed main experiment, then independent checks.
% From the project folder, type run_main. No parameter editing is needed.
projectDir = fileparts(mfilename('fullpath'));
calDir = fullfile(projectDir,'evidence','imported_smoke');
assert(isfile(fullfile(calDir,'config_snapshot.mat')) && ...
    isfile(fullfile(calDir,'initialization.mat')), ...
    'DMT:MissingReference','Keep evidence/imported_smoke with the code package.');
result = run_dmt_experiment('main', ...
    'CalibrationDirectory',calDir,'CalibrationMode','reuse');
% Validate actual saved counts and artifacts, not just the requested settings.
diary(fullfile(result.output_dir,'main_completion_check.txt'));
checkDiaryCleanup = onCleanup(@() diary('off')); %#ok<NASGU>
completion = verify_main_results(result.output_dir);
save(fullfile(result.output_dir,'main_completion_check.mat'),'completion');
result.validation = completion;
fprintf('\nFormal result directory: %s\n',result.output_dir);
fprintf('All 9 groups completed and independently checked.\n');
fprintf('Target compliance is reported separately for each strategy.\n');
end
