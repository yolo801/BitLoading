function baseline = dmt_lit7_baseline(v2Dir, baselineDir, cfg, plan)
%DMT_LIT7_BASELINE Authenticate a published v2 formal reference read-only.
baseline = struct('status','not_provided','detail','No v2 formal folder supplied.', ...
    'folder','','source_id','','verification',struct(),'tables',struct());
baselineDir = char(string(baselineDir));
if isempty(baselineDir), return; end
baseline.folder = char(java.io.File(baselineDir).getCanonicalPath());
if ~isfolder(baseline.folder)
    baseline.status = 'missing_directory';
    baseline.detail = 'The specified v2 formal directory does not exist.';
    return;
end
baseline.status = 'invalid';
frozenSource = 'c68ae10ae98ce6d78b94fda5b18cb7bbb601ddc6ff4cebbd4a777c6c00580fc8';
try
    saved = load(fullfile(baseline.folder,'Protocol.mat'),'checkpoint');
    p = saved.checkpoint;
    baseline.source_id = p.source_id;
    assert(strcmp(p.phase,'formal') && ~p.test_only && ...
        p.planned_payload_slots==450 && p.symbols_per_slot==50000, ...
        'DMT:Lit7BaselinePhase','Reference must be a 450-slot v2 formal study.');
    assert(strcmp(p.source_id,frozenSource), ...
        'DMT:Lit7BaselineSource','Reference is not from the frozen v2 source at 418996d.');
    assert(isequal(p.cfg.h,[.25 .5 .25]) && ...
        isequaln(rmfield(p.cfg,'h'),rmfield(cfg,'h')), ...
        'DMT:Lit7BaselineConfig','Reference configuration differs outside the channel FIR.');
    point = p.plan.P_target==1 & p.plan.q==8;
    assert(isequaln(p.plan(point,:),plan), ...
        'DMT:Lit7BaselineSeeds','Reference role and seed plan differs at the paired point.');

    [~, currentSource] = dmt_source_manifest(v2Dir);
    assert(strcmp(currentSource,frozenSource), ...
        'DMT:Lit7BaselineSource','Installed original v2 source differs from 418996d.');
    receipt = load(fullfile(baseline.folder,'verification_receipt.mat'),'checkpoint');
    assert(passed(receipt.checkpoint), ...
        'DMT:Lit7BaselineReceipt','The original v2 formal verification did not pass.');
    previous = pwd;
    cd(v2Dir);
    restore = onCleanup(@()cd(previous)); %#ok<NASGU>
    originalVerifier = char(java.io.File(fullfile(pwd,'verify_dmt_tradeoff_v2.m')).getCanonicalPath());
    resolvedVerifier = which('verify_dmt_tradeoff_v2');
    assert(strcmp(resolvedVerifier,originalVerifier) || (ispc && strcmpi(resolvedVerifier,originalVerifier)), ...
        'DMT:Lit7BaselineVerifier','Unexpected v2 verifier resolved at %s.',resolvedVerifier);
    checked = verify_dmt_tradeoff_v2(baseline.folder);
    baseline.verification = checked;
    assert(passed(checked), ...
        'DMT:Lit7BaselineVerification','Fresh original v2 verification failed. %s',checked.detail);
    fields = {'planned','completed','design_rejected','power_error','incomplete','qualified'};
    for j = 1:numel(fields)
        name = fields{j};
        assert(isequal(checked.(name),receipt.checkpoint.(name)), ...
            'DMT:Lit7BaselineReceipt','Original v2 receipt differs on %s.',name);
    end

    saved = load(fullfile(baseline.folder,'tables.mat'),'checkpoint');
    export = saved.checkpoint;
    assert(strcmp(export.phase,'formal') && strcmp(export.tables_hash,dmt_v13_hash(export.tables)), ...
        'DMT:Lit7BaselineTables','Reference table snapshot is inconsistent.');
    tables = struct();
    names = {'snr','profiles','pool','summary','scenario','status','pair_gains'};
    for j = 1:numel(names)
        name = names{j};
        allRows = export.tables.(name);
        tables.(name) = allRows(allRows.P_target==1 & allRows.q==8,:);
        assert(all(~tables.(name).test_only & tables.(name).phase=="formal"), ...
            'DMT:Lit7BaselineTables','Unexpected phase rows in %s.',name);
    end
    assert(height(tables.status)==30 && height(tables.summary)==15 && ...
        height(tables.scenario)==3 && all(tables.status.planned_symbols==50000));
    baseline.tables = tables;
    baseline.status = 'verified';
    baseline.detail = 'The original receipt and fresh v2 verification agree. Baseline is paired by role.';
catch ME
    baseline.detail = getReport(ME,'extended','hyperlinks','off');
end
end

function answer = passed(receipt)
answer = strcmp(receipt.phase,'formal') && ~receipt.test_only && receipt.valid && ...
    receipt.data_integrity_valid && receipt.acquisition_complete;
end
