function result = run_dmt_experiment(mode, varargin)
%RUN_DMT_EXPERIMENT Simplified digital-baseband CP-DMT Monte Carlo experiment.
% Optional: 'CalibrationDirectory',oldSmokeDir,'CalibrationMode','reuse'/'recompute'.
% All runs get unique directories; no historical measurements are overwritten.
if nargin < 1
    mode = 'smoke';
end
mode = validatestring(mode,{'smoke','main'},mfilename,'mode');
projectDir = fileparts(mfilename('fullpath'));
parser = inputParser;
isText = @(x) ischar(x) || (isstring(x) && isscalar(x));
addParameter(parser,'CalibrationDirectory','',isText);
addParameter(parser,'CalibrationMode','reuse',isText);
parse(parser,varargin{:});
calibrationMode = validatestring(parser.Results.CalibrationMode,{'reuse','recompute'});
referenceDir = char(parser.Results.CalibrationDirectory);
if isempty(referenceDir) && isfolder(fullfile(projectDir,'evidence','imported_smoke'))
    referenceDir = fullfile(projectDir,'evidence','imported_smoke');
end
resultsRoot = fullfile(projectDir,'results');
if ~isfolder(resultsRoot)
    mkdir(resultsRoot);
end
[~,uniqueTag] = fileparts(tempname(resultsRoot));
stamp = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
outDir = fullfile(resultsRoot,[stamp '_' mode '_' uniqueTag]);
mkdir(outDir);
diary(fullfile(outDir,'run.log'));
diaryCleanup = onCleanup(@() diary('off')); %#ok<NASGU>
fprintf('Author-created simplified digital-baseband DMT simulation.\n');
fprintf('Command: run_dmt_experiment(''%s'')\n',mode);
fprintf('Start time (machine local): %s\n',char(datetime('now')));
fprintf('Results: %s\n',outDir);
cfg = dmt_default_config();
cfg.runMode = mode;
cfg.command = sprintf('run_dmt_experiment(''%s'')',mode);
cfg.calibrationMode = calibrationMode;
cfg.calibrationDirectory = referenceDir;
cfg.command = sprintf(['run_dmt_experiment(''%s'',''CalibrationDirectory'',''%s'',' ...
    '''CalibrationMode'',''%s'')'],mode,strrep(referenceDir,'''',''''''),calibrationMode);
cfg.startedAt = char(datetime('now','TimeZone','UTC', ...
    'Format','yyyy-MM-dd HH:mm:ss Z'));
cfg.MATLABVersion = version;
cfg.MATLABRelease = version('-release');
cfg.computer = computer;
toolboxes = ver;
seedMapping = dmt_seed_mapping(cfg);
save(fullfile(outDir,'config_snapshot.mat'),'cfg','seedMapping','toolboxes');
writetable(seedMapping,fullfile(outDir,'seed_mapping.csv'));
writeEnvironment(outDir,cfg,toolboxes);
try
    fprintf('\nStage 0: environment and frozen specification.\n');
    fprintf('Execution: %s\nProtocol %s; physical spec %s.\n', ...
        cfg.command,cfg.protocolVersion,cfg.specVersion);
    [sourceManifest,sourceID] = dmt_source_manifest(projectDir);
    cfg.sourceManifestID = sourceID;
    writetable(sourceManifest,fullfile(outDir,'source_manifest.csv'));
    save(fullfile(outDir,'config_snapshot.mat'),'cfg','seedMapping','toolboxes','sourceManifest');
    haveQAM = ~isempty(which('qammod')) && ~isempty(which('qamdemod'));
    haveComm = ~isempty(ver('comm'));
    dmt_record_check(outDir,'qammod and qamdemod available',double(haveQAM),1,0,haveQAM);
    dmt_record_check(outDir,'Communications Toolbox installed',double(haveComm),1,0,haveComm);
    fprintf('rho_ref = %.6f dB (electrical Es / receiver noise variance).\n',cfg.rho_ref_dB);
    fprintf('Initialization: %d symbols, %.9g s; no payload counted.\n', ...
        cfg.trainSymbols+cfg.probeSymbols,(cfg.trainSymbols+cfg.probeSymbols)*cfg.Ts);
    fprintf('\nStage 1: noiseless end-to-end and noise-scaling checks.\n');
    dmt_self_checks(cfg,outDir);
    fprintf('\nStage 2: validated reference reuse or reproducible A/B calibration.\n');
    [calibration,calibrationProvenance] = dmt_prepare_calibration( ...
        cfg,referenceDir,calibrationMode,outDir);
    fprintf('Measured probe Es/N0 estimate range: %.6f to %.6f dB.\n', ...
        min(calibration.gamma_hat_dB),max(calibration.gamma_hat_dB));
    fprintf('\nStage 3: freeze profiles using probe SNR and 1 dB margin.\n');
    [profiles,feasible,loadingDiagnostics] = dmt_load_profiles(cfg,calibration);
    save(fullfile(outDir,'initialization.mat'), ...
        'calibration','profiles','loadingDiagnostics','seedMapping','calibrationProvenance');
    if ~feasible
        fid = fopen(fullfile(outDir,'infeasible_profile.txt'),'w');
        assert(fid>=0);
        fprintf(fid,'Physical spec v1.0 is infeasible: QPSK unavailable on k =');
        fprintf(fid,' %d',loadingDiagnostics.infeasible_k);
        fprintf(fid,'\nNo tones disabled; no parameters changed.\n');
        fclose(fid);
        error('DMT:InfeasibleProfile', ...
            'QPSK is infeasible on k=%s. See initialization.mat.', ...
            mat2str(loadingDiagnostics.infeasible_k.'));
    end
    cfg.initializationID = dmt_initialization_id(cfg,calibration,profiles);
    save(fullfile(outDir,'config_snapshot.mat'),'cfg','seedMapping','toolboxes','sourceManifest');
    integrity = struct('protocol_version',cfg.protocolVersion,'physical_spec_version',cfg.specVersion, ...
        'source_manifest_sha256',sourceID,'initialization_profile_sha256',cfg.initializationID, ...
        'calibration_provenance',calibrationProvenance);
    save(fullfile(outDir,'initialization.mat'), ...
        'calibration','profiles','loadingDiagnostics','seedMapping','calibrationProvenance','integrity');
    writeIntegrity(outDir,integrity);
    for s = 1:numel(profiles)
        fprintf('%s: B=%d bits/DMT symbol, R_payload=%.9g bit/s, M=%s\n', ...
            profiles(s).name,profiles(s).B,profiles(s).R_payload,mat2str(profiles(s).M.'));
    end
    frozenCalibration = calibration;
    frozenProfiles = profiles;
    fprintf('\nStage 4: independent 2000-symbol smoke run per scheme.\n');
    smokeRuns = struct([]);
    for s = 1:numel(profiles)
        r = dmt_simulate(cfg,calibration,profiles(s),s,0,'smoke');
        if isempty(smokeRuns)
            smokeRuns = r;
        else
            smokeRuns(end+1) = r; %#ok<AGROW>
        end
        save(fullfile(outDir,'runs_partial.mat'),'smokeRuns');
    end
    dmt_post_checks(cfg,calibration,profiles,smokeRuns,outDir,'smoke');
    smokeDir = outDir;
    if strcmp(mode,'main')
        smokeDir = fullfile(outDir,'preflight_smoke');
        mkdir(smokeDir);
    end
    dmt_write_outputs(cfg,calibration,profiles,smokeRuns,smokeDir,'smoke');
    verifyArtifacts(smokeDir,outDir,'smoke');
    if strcmp(mode,'main')
        fprintf('\nStage 5: formal fixed-length Monte Carlo (smoke excluded).\n');
        runs = struct([]);
        for tag = cfg.seeds
            for s = 1:numel(profiles)
                r = dmt_simulate(cfg,calibration,profiles(s),s,tag,'main');
                if isempty(runs)
                    runs = r;
                else
                    runs(end+1) = r; %#ok<AGROW>
                end
                save(fullfile(outDir,'runs_partial.mat'),'runs','smokeRuns');
            end
        end
        dmt_post_checks(cfg,calibration,profiles,runs,outDir,'main');
        % Preserve all expensive payload counts before any graphics/export call.
        % This state is deliberately NOT a claim that final export completed.
        payloadState = 'payload_complete_exports_pending';
        save(fullfile(outDir,'payload_counts.mat'),'cfg','calibration','profiles', ...
            'loadingDiagnostics','runs','smokeRuns','seedMapping','sourceManifest', ...
            'integrity','calibrationProvenance','payloadState');
        fprintf('\nStage 6: pooled counts, Wilson intervals and reports.\n');
        [perCarrier,summary,pooled,nominal] = dmt_write_outputs( ...
            cfg,calibration,profiles,runs,outDir,'main');
        verifyArtifacts(outDir,outDir,'main');
    else
        runs = smokeRuns;
        perCarrier = readtable(fullfile(outDir,'per_subcarrier_results.csv'));
        summary = readtable(fullfile(outDir,'summary.csv'));
        pooled = readtable(fullfile(outDir,'per_subcarrier_pooled.csv'));
        nominal = readtable(fullfile(outDir,'nominal_vs_measured.csv'));
    end
    unchanged = isequaln(calibration,frozenCalibration) && isequaln(profiles,frozenProfiles);
    dmt_record_check(outDir,'initialization and profiles unchanged after all payloads', ...
        double(unchanged),1,0,unchanged);
    finalInitializationID = dmt_initialization_id(cfg,calibration,profiles);
    [~,finalSourceID] = dmt_source_manifest(projectDir);
    idsMatch = strcmp(cfg.initializationID,finalInitializationID) && strcmp(sourceID,finalSourceID);
    dmt_record_check(outDir,'source and initialization SHA-256 unchanged after payload', ...
        double(idsMatch),1,0,idsMatch);
    save(fullfile(outDir,'final_results.mat'),'cfg','calibration','profiles', ...
        'loadingDiagnostics','runs','smokeRuns','perCarrier','pooled','nominal','summary', ...
        'seedMapping','sourceManifest','integrity','calibrationProvenance');
    result = struct('output_dir',outDir,'mode',mode, ...
        'execution_status','completed','summary',summary);
    fprintf('Completed %s at %s.\n',mode,char(datetime('now')));
    disp(summary);
catch ME
    fid = fopen(fullfile(outDir,'failure_status.txt'),'w');
    if fid >= 0
        fprintf(fid,'FAILED, not a completed experiment. Historical output preserved.\n');
        fprintf(fid,'%s\n',getReport(ME,'extended','hyperlinks','off'));
        fclose(fid);
    end
    fprintf(2,'Run failed. Evidence retained in %s\n%s\n',outDir,ME.message);
    rethrow(ME);
end
end

function writeEnvironment(outDir,cfg,toolboxes)
fid = fopen(fullfile(outDir,'environment.txt'),'w');
assert(fid>=0);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'Command: %s\nUTC start: %s\nMATLAB: %s (%s)\nComputer: %s\n', ...
    cfg.command,cfg.startedAt,cfg.MATLABVersion,cfg.MATLABRelease,cfg.computer);
for j = 1:numel(toolboxes)
    fprintf(fid,'Toolbox: %s | %s\n',toolboxes(j).Name,toolboxes(j).Version);
end
fprintf(fid,'Stream: %s; see seed_mapping.csv for independent stream mapping.\n',cfg.streamType);
end

function verifyArtifacts(folder,outDir,phase)
files = {'per_subcarrier_seed.csv','per_subcarrier_pooled.csv','per_subcarrier_results.csv', ...
    'nominal_vs_measured.csv','summary.csv','dmt_comparison.png','figure_caption_en.txt', ...
    'dmt_comparison.pdf','dmt_comparison.fig','report_notes_zh.md'};
if strcmp(phase,'main')
    files{end+1} = 'results_paragraph_en.txt';
else
    files{end+1} = 'smoke_notes_en.txt';
end
for j = 1:numel(files)
    info = dir(fullfile(folder,files{j}));
    ok = numel(info)==1 && info.bytes>0;
    dmt_record_check(outDir,[phase ' | nonempty artifact ' files{j}],double(ok),1,0,ok);
end
end

function writeIntegrity(outDir,integrity)
fid = fopen(fullfile(outDir,'integrity.json'),'w','n','UTF-8');
assert(fid>=0);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(integrity,'PrettyPrint',true));
end
