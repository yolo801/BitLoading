function result = run_dmt_experiment(mode)
%RUN_DMT_EXPERIMENT Simplified digital-baseband CP-DMT Monte Carlo experiment.
% From this project folder: run_dmt_experiment('smoke') or ('main').
% All runs get unique directories; no historical measurements are overwritten.
if nargin < 1
    mode = 'smoke';
end
mode = validatestring(mode,{'smoke','main'},mfilename,'mode');
projectDir = fileparts(mfilename('fullpath'));
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
    haveQAM = ~isempty(which('qammod')) && ~isempty(which('qamdemod'));
    haveComm = ~isempty(ver('comm'));
    dmt_record_check(outDir,'qammod and qamdemod available',double(haveQAM),1,0,haveQAM);
    dmt_record_check(outDir,'Communications Toolbox installed',double(haveComm),1,0,haveComm);
    fprintf('rho_ref = %.6f dB (electrical Es / receiver noise variance).\n',cfg.rho_ref_dB);
    fprintf('Initialization: %d symbols, %.9g s; no payload counted.\n', ...
        cfg.trainSymbols+cfg.probeSymbols,(cfg.trainSymbols+cfg.probeSymbols)*cfg.Ts);
    fprintf('\nStage 1: noiseless end-to-end and noise-scaling checks.\n');
    dmt_self_checks(cfg,outDir);
    fprintf('\nStage 2: noisy LS block A; independent residual-SNR probe B.\n');
    calibration = dmt_calibrate(cfg);
    fprintf('Measured probe Es/N0 estimate range: %.6f to %.6f dB.\n', ...
        min(calibration.gamma_hat_dB),max(calibration.gamma_hat_dB));
    fprintf('\nStage 3: freeze profiles using probe SNR and 1 dB margin.\n');
    [profiles,feasible,loadingDiagnostics] = dmt_load_profiles(cfg,calibration);
    save(fullfile(outDir,'initialization.mat'), ...
        'calibration','profiles','loadingDiagnostics','seedMapping');
    if ~feasible
        fid = fopen(fullfile(outDir,'infeasible_profile.txt'),'w');
        assert(fid>=0);
        fprintf(fid,'Frozen v1.0 is infeasible: QPSK unavailable on k =');
        fprintf(fid,' %d',loadingDiagnostics.infeasible_k);
        fprintf(fid,'\nNo tones disabled; no parameters changed.\n');
        fclose(fid);
        error('DMT:InfeasibleProfile', ...
            'QPSK is infeasible on k=%s. See initialization.mat.', ...
            mat2str(loadingDiagnostics.infeasible_k.'));
    end
    for s = 1:2
        fprintf('%s: B=%d bits/DMT symbol, R_payload=%.9g bit/s, M=%s\n', ...
            profiles(s).name,profiles(s).B,profiles(s).R_payload,mat2str(profiles(s).M.'));
    end
    frozenCalibration = calibration;
    frozenProfiles = profiles;
    fprintf('\nStage 4: independent 2000-symbol smoke run per scheme.\n');
    smokeRuns = struct([]);
    for s = 1:2
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
            for s = 1:2
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
        fprintf('\nStage 6: pooled counts, Wilson intervals and reports.\n');
        [perCarrier,summary] = dmt_write_outputs(cfg,calibration,profiles,runs,outDir,'main');
        verifyArtifacts(outDir,outDir,'main');
    else
        runs = smokeRuns;
        perCarrier = readtable(fullfile(outDir,'per_subcarrier_results.csv'));
        summary = readtable(fullfile(outDir,'summary.csv'));
    end
    unchanged = isequaln(calibration,frozenCalibration) && isequaln(profiles,frozenProfiles);
    dmt_record_check(outDir,'initialization and profiles unchanged after all payloads', ...
        double(unchanged),1,0,unchanged);
    save(fullfile(outDir,'final_results.mat'),'cfg','calibration','profiles', ...
        'loadingDiagnostics','runs','smokeRuns','perCarrier','summary','seedMapping');
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
files = {'per_subcarrier_results.csv','summary.csv','dmt_comparison.png', ...
    'dmt_comparison.pdf','dmt_comparison.fig','report_notes_zh.md','results_paragraph_en.txt'};
for j = 1:numel(files)
    info = dir(fullfile(folder,files{j}));
    ok = numel(info)==1 && info.bytes>0;
    dmt_record_check(outDir,[phase ' | nonempty artifact ' files{j}],double(ok),1,0,ok);
end
end
