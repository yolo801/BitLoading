function report = verify_dmt_tradeoff_v2_diagnostic(outDir)
%VERIFY_DMT_TRADEOFF_V2_DIAGNOSTIC Recompute paired evidence without writing.
assert(isfolder(outDir));
report = struct('phase','impairment_diagnostic','valid',false, ...
    'completed_slots',0,'planned_slots',0,'paired_power_mismatch_slots',0,'message','');
try
    saved = load(fullfile(outDir,'protocol.mat'),'checkpoint');
    protocol = saved.checkpoint;
    assert(strcmp(protocol.phase,report.phase) && protocol.formal_audit_valid);
    assert(protocol.formal_audit.valid && strcmp(protocol.formal_audit.phase,'formal'));
    assert(~isfile(fullfile(outDir,'failure_receipt.mat')), ...
        'DMT:T2DiagnosticFailure','The diagnostic has an original failure receipt.');
    assert(strcmp(protocol.protocol_hash,dmt_v13_hash(rmfield(protocol,'protocol_hash'))));
    cfg = dmt_t2_config();
    [settings,plan] = dmt_t2_diag_config(cfg);
    assert(isequaln(protocol.cfg,cfg) && isequaln(protocol.settings,settings) && isequaln(protocol.plan,plan));
    report.planned_slots = sum(plan.role=="payload");
    root = fileparts(mfilename('fullpath'));
    [sourceManifest,sourceID] = dmt_source_manifest(root);
    assert(strcmp(protocol.source_id,sourceID) && isequaln(protocol.source_manifest,sourceManifest));
    [tables,completed] = dmt_t2_diag_read(outDir,protocol);
    report.completed_slots = completed;
    saved = load(fullfile(outDir,'diagnostic_result.mat'),'checkpoint');
    result = saved.checkpoint;
    assert(strcmp(result.phase,report.phase) && strcmp(result.protocol_hash,protocol.protocol_hash));
    assert(result.completed_slots==completed && result.planned_slots==report.planned_slots);
    assert(isequaln(result.tables,tables));
    manifest = result.figure_manifest;
    assert(height(manifest)==1 && manifest.phase==report.phase && manifest.status=="written");
    assert(manifest.figure=="fig4_separating_tx_clipping_and_adc_quantization");
    assert(manifest.data_hash==string(dmt_v13_hash(tables.summary)));
    assert(manifest.source_csv_sha256==dmt_t2_diag_file_hash(fullfile(outDir,'summary.csv')));
    for ext = ["png" "pdf" "svg"]
        path = fullfile(outDir,manifest.figure+"."+ext);
        assert(manifest.(ext+"_sha256")==dmt_t2_diag_file_hash(path));
    end
    artifacts = result.artifact_manifest;
    expectedPaths = ["seed_plan.csv";"source_manifest.csv";"figure_manifest.csv";"figure_caption_en.txt"; ...
        string(fieldnames(tables))+".csv"; manifest.figure+"."+["png";"pdf";"svg"]];
    assert(isequal(sort(artifacts.relative_path),sort(expectedPaths)));
    for k = 1:height(artifacts)
        assert(artifacts.sha256(k)==dmt_t2_diag_file_hash(fullfile(outDir,artifacts.relative_path(k))));
    end
    slots = tables.slot_status;
    pairRows = slots(~slots.paired_power_match,{'calibration_id','payload_slot'});
    report.paired_power_mismatch_slots = height(unique(pairRows));
    report.valid = true;
    report.message = 'Verified diagnostic counters, within-calibration pooling, paired power status and figure source hashes.';
catch exception
    report.message = getReport(exception,'extended','hyperlinks','off');
end
fprintf('Diagnostic integrity: %d, complete payload slots %d/%d\n%s\n', ...
    report.valid,report.completed_slots,report.planned_slots,report.message);
end
