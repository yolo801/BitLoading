function result = run_dmt_tradeoff_v2_diagnostic(formalDir)
%RUN_DMT_TRADEOFF_V2_DIAGNOSTIC Start a new 40-slot impairment diagnostic.
% Requires independent acceptance of the formal scan. Always run explicitly.
assert(isfolder(formalDir),'DMT:T2DiagnosticFormalDir','Supply the completed formal result directory.');
formal = java.io.File(char(formalDir));
formalDir = char(formal.getCanonicalPath());
formalReport = verify_dmt_tradeoff_v2(formalDir);
assert(formalReport.valid && strcmp(formalReport.phase,'formal'), ...
    'DMT:T2DiagnosticFormalGate','The formal scan must pass the independent read-only audit first.');
root = fileparts(mfilename('fullpath'));
cfg = dmt_t2_config();
[settings,plan] = dmt_t2_diag_config(cfg);
[sourceManifest,sourceID] = dmt_source_manifest(root);
parent = fileparts(formalDir);
[~,suffix] = fileparts(tempname(parent));
stamp = char(datetime('now','TimeZone','UTC','Format','yyyyMMdd_HHmmss_SSS'));
outDir = fullfile(parent,['tradeoff_v2_impairment_diagnostic_' stamp '_' suffix]);
assert(~isfolder(outDir));
mkdir(outDir);
lock = dmt_study_lock(outDir); %#ok<NASGU>
mkdir(fullfile(outDir,'checkpoints'));
diary(fullfile(outDir,'run.log'));
logCloser = onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('Independent impairment diagnostic started in %s\n',outDir);
try
    environment = dmt_t2_runtime(root);
    protocol = struct('phase',settings.phase,'cfg',cfg,'settings',settings, ...
        'plan',plan,'source_manifest',sourceManifest,'source_id',sourceID, ...
        'formal_directory',formalDir,'formal_audit_valid',formalReport.valid, ...
        'formal_audit',formalReport,'formal_protocol_sha256', ...
        dmt_t2_diag_file_hash(fullfile(formalDir,'Protocol.mat')), ...
        'environment',environment,'created_utc',stamp);
    protocol.protocol_hash = dmt_v13_hash(protocol);
    dmt_v13_atomic_save(fullfile(outDir,'protocol.mat'),protocol);
    writetable(plan,fullfile(outDir,'seed_plan.csv'));
    writetable(sourceManifest,fullfile(outDir,'source_manifest.csv'));
    for c = 1:settings.calibration_count
        cal = dmt_t2_diag_calibrate(cfg,settings,plan,c);
        saveRecord(sprintf('calibration_%02d',c),cal);
        for arm = 1:4
            fprintf('Diagnostic pair %d/%d, %s\n',c,settings.calibration_count, ...
                settings.treatment_names{arm});
            tr = planRow(c,arm,"training",0);
            training = dmt_t2_diag_measure(cfg,settings,tr,cal,[]);
            saveRecord(sprintf('training_%02d_%02d',c,arm),training);
            trainingHash = dmt_v13_hash(training);
            for slot = 1:settings.payload_repeats
                payload = planRow(c,arm,"payload",slot);
                record = dmt_t2_diag_measure(cfg,settings,payload,cal,training.H_hat);
                record.training_hash = trainingHash;
                saveRecord(sprintf('payload_%02d_%02d_%02d',c,arm,slot),record);
            end
        end
    end
    [tables,n] = dmt_t2_diag_read(outDir,protocol);
    names = fieldnames(tables);
    for j = 1:numel(names)
        writetable(tables.(names{j}),fullfile(outDir,[names{j} '.csv']));
    end
    [figManifest,caption] = dmt_t2_diag_plot(settings,tables.summary,outDir);
    writetable(figManifest,fullfile(outDir,'figure_manifest.csv'));
    saveCaption(fullfile(outDir,'figure_caption_en.txt'),caption);
    [afterManifest,afterID] = dmt_source_manifest(root);
    assert(strcmp(afterID,sourceID) && isequal(afterManifest,sourceManifest), ...
        'DMT:T2DiagnosticSourceChanged','Diagnostic source changed during execution.');
    artifactNames = [{'seed_plan.csv';'source_manifest.csv';'figure_manifest.csv';'figure_caption_en.txt'}; ...
        strcat(names,'.csv')];
    for ext = [".png" ".pdf" ".svg"]
        artifactNames{end+1,1} = char(figManifest.figure(1)+ext); %#ok<AGROW>
    end
    paths = string(artifactNames);
    hashes = strings(size(paths));
    for k = 1:numel(paths)
        hashes(k) = dmt_t2_diag_file_hash(fullfile(outDir,paths(k)));
    end
    artifacts = table(paths,hashes,'VariableNames',{'relative_path','sha256'});
    result = struct('output_dir',outDir,'phase',settings.phase,'completed_slots',n, ...
        'planned_slots',sum(plan.role=="payload"),'protocol_hash',protocol.protocol_hash, ...
        'tables',tables,'figure_manifest',figManifest,'artifact_manifest',artifacts);
    dmt_v13_atomic_save(fullfile(outDir,'diagnostic_result.mat'),result);
    audit = verify_dmt_tradeoff_v2_diagnostic(outDir);
    assert(audit.valid,'DMT:T2DiagnosticVerification','%s',audit.message);
    result.verification = audit;
    fprintf('Diagnostic complete: %d/%d slots. Power-mismatched slots: %d.\n', ...
        n,result.planned_slots,sum(~tables.slot_status.power_match));
catch exception
    failure = struct('identifier',exception.identifier,'report', ...
        getReport(exception,'extended','hyperlinks','off'));
    fprintf(2,'%s\n',failure.report);
    try
        dmt_v13_atomic_save(fullfile(outDir,'failure_receipt.mat'),failure);
    catch saveException
        fprintf(2,'Could not save the failure receipt: %s\n',saveException.message);
    end
    rethrow(exception);
end

    function row = planRow(c,arm,role,slot)
        row = plan(plan.calibration_id==c & plan.treatment_id==arm & ...
            plan.role==role & plan.payload_slot==slot,:);
        assert(height(row)==1);
    end

    function saveRecord(stem,body)
        checkpoint = struct('protocol_hash',protocol.protocol_hash, ...
            'record_hash',dmt_v13_hash(body),'body',body);
        dmt_v13_atomic_save(fullfile(outDir,'checkpoints',[stem '.mat']),checkpoint);
    end
end

function saveCaption(path,caption)
fid = fopen(path,'wt','n','UTF-8');
assert(fid>=0);
closer = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',caption);
end
