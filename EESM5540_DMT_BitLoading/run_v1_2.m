function result = run_v1_2(referenceDir)
%RUN_V1_2 Task A reference-only redraw, then all ten new calibrations.
% You may supply the full original Windows reference directory explicitly.
if nargin<1 || isempty(referenceDir)
    projectDir=fileparts(mfilename('fullpath'));
    referenceDir=fullfile(projectDir,'results', ...
        '20261116_194846_246_main_tp96b36639_d14e_4dbc_8956_3651acfb6fa8');
end
assert(isfolder(referenceDir),'DMT:MissingReference', ...
    'Supply the actual reference-0 main directory; smoke is not a substitute.');
reference=redraw_dmt_constraint_check(referenceDir);
study=run_dmt_calibration_study('main','NumCalibrations',10, ...
    'ReferenceDirectory',referenceDir);
verification=verify_dmt_calibration_study(study.output_dir);
result=struct('reference',reference,'study',study,'verification',verification);
save(fullfile(study.output_dir,'v1_2_completion.mat'),'result');
fprintf('Task A directory: %s\nTask B directory: %s\n',reference.output_dir,study.output_dir);
fprintf('Actual new groups: %d/90. All 90 complete: %d\n', ...
    study.completed_groups,study.all_90_groups_complete);
end
