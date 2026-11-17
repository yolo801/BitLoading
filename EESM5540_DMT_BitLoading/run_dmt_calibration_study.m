function report = run_dmt_calibration_study(mode,varargin)
%RUN_DMT_CALIBRATION_STUDY Ten independent calibrations and 90 fixed groups.
% run_dmt_calibration_study('main','NumCalibrations',10)
% Resume only an existing, identical study:
% run_dmt_calibration_study('main','ResumeDirectory',studyDirectory)
% ReferenceDirectory is optional for B; it never supplies the new calibrations.
if nargin<1
    mode = 'main';
end
validatestring(mode,{'main'},mfilename,'mode');
parser = inputParser;
isText = @(x)ischar(x) || (isstring(x) && isscalar(x));
addParameter(parser,'NumCalibrations',10,@(x)isnumeric(x) && isscalar(x) && x==10);
addParameter(parser,'ResumeDirectory','',isText);
addParameter(parser,'ReferenceDirectory','',isText);
parse(parser,varargin{:});
projectDir = fileparts(mfilename('fullpath'));
cfg = dmt_default_config(); % Physical v1.0; preserve the original main entry.
cfg.protocolVersion = '1.2';
cfg.NumCalibrations = parser.Results.NumCalibrations;
cfg.plannedRounds = 1:10;
cfg.runMode = 'main';
cfg.studyKind = 'independent_calibration_stability';
cfg.referenceDirectory = char(parser.Results.ReferenceDirectory);
if ~isempty(cfg.referenceDirectory)
    assert(isfolder(cfg.referenceDirectory),'DMT:MissingReference', ...
        'ReferenceDirectory must be the actual accessible reference-0 formal main directory.');
    referenceFile = java.io.File(cfg.referenceDirectory);
    referenceRoot = char(referenceFile.getCanonicalPath());
    outputFile = java.io.File(fullfile(projectDir,'results'));
    outputRoot = char(outputFile.getCanonicalPath());
    assert(~strcmp(outputRoot,referenceRoot) && ...
        ~startsWith(outputRoot,[referenceRoot filesep],'IgnoreCase',ispc), ...
        'DMT:ReferenceOutputOverlap','Study output must be outside the original reference directory.');
end
[sourceManifest,sourceID] = dmt_source_manifest(projectDir);
configID = dmt_study_config_id(cfg);
seedMapping = dmt_study_seed_mapping(cfg);
seedMappingID = dmt_sha256(jsonencode(table2struct(seedMapping)));
resumeDir = char(parser.Results.ResumeDirectory);
if isempty(resumeDir)
    resultsRoot = fullfile(projectDir,'results');
    if ~isfolder(resultsRoot), mkdir(resultsRoot); end
    [~,tag] = fileparts(tempname(resultsRoot));
    outDir = fullfile(resultsRoot,['v1_2_study_' stamp() '_' tag]);
    mkdir(outDir);
else
    assert(isfolder(resumeDir),'DMT:MissingStudy','ResumeDirectory does not exist.');
    outDir = char(java.io.File(resumeDir).getCanonicalPath());
    if ~isempty(cfg.referenceDirectory)
        assert(~strcmp(outDir,referenceRoot) && ...
            ~startsWith(outDir,[referenceRoot filesep],'IgnoreCase',ispc), ...
            'DMT:ReferenceOutputOverlap','Resume directory must be outside the reference input.');
    end
end
studyLock = dmt_study_lock(outDir); %#ok<NASGU>
diary(fullfile(outDir,'run.log'));
diaryCleanup = onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('\n%s | v1.2 calibration study; directory=%s\n',utcNow(),outDir);
fprintf('Command: run_dmt_calibration_study(''main'',''NumCalibrations'',10, ...\n');
fprintf('  ''ReferenceDirectory'',''%s'',''ResumeDirectory'',''%s'')\n', ...
    strrep(cfg.referenceDirectory,'''',''''''),strrep(resumeDir,'''',''''''));
fprintf('Plan: 10 NEW calibrations x 3 strategies x 3 payload seeds = 90 groups.\n');
rounds = repmat(struct('calibration_id',0,'feasible',NaN,'calibration',struct(), ...
    'profiles',struct([]),'initialization_id','','reason','not_calibrated', ...
    'config_snapshot',struct()),1,10);
for c = 1:10, rounds(c).calibration_id = c; end
runs = struct([]);
referenceManifest = table();
stateFile = fullfile(outDir,'study_state.mat');
try
    if isempty(resumeDir)
        cfg.startedAt = utcNow();
        cfg.MATLABVersion = version;
        cfg.MATLABRelease = version('-release');
        cfg.sourceManifestID = sourceID;
        state = struct('cfg',cfg,'config_id',configID,'source_id',sourceID, ...
            'seed_mapping_id',seedMappingID);
        dmt_study_atomic_save(stateFile,state);
    else
        assert(isfile(stateFile),'DMT:MissingStudy','Missing study_state.mat.');
        old = load(stateFile,'checkpoint');
        assert(isfield(old,'checkpoint'),'DMT:InvalidStudy','Invalid study state.');
        state = old.checkpoint;
        assert(strcmp(state.config_id,configID) && strcmp(state.source_id,sourceID) && ...
            strcmp(state.seed_mapping_id,seedMappingID),'DMT:StudyMismatch', ...
            'Configuration/source/stream plan changed: preserve this study and start a new directory.');
        assert(strcmp(dmt_study_config_id(state.cfg),state.config_id) && ...
            strcmp(state.cfg.sourceManifestID,state.source_id),'DMT:StudyMismatch', ...
            'Saved configuration contents do not match their recorded identity.');
        suppliedReference = cfg.referenceDirectory;
        cfg = state.cfg;
        if ~isempty(suppliedReference), cfg.referenceDirectory = suppliedReference; end
        fprintf('Resume requested: validate every calibration and completed group; never add partial counts.\n');
    end
    if ~isfolder(fullfile(outDir,'calibrations')), mkdir(fullfile(outDir,'calibrations')); end
    if ~isfolder(fullfile(outDir,'groups')), mkdir(fullfile(outDir,'groups')); end
    writetable(sourceManifest,fullfile(outDir,'source_manifest.csv'));
    writetable(seedMapping,fullfile(outDir,'seed_mapping.csv'));
    copyfile(fullfile(projectDir,'docs','literature_mapping.md'),fullfile(outDir,'literature_mapping.md'));
    copyfile(fullfile(projectDir,'docs','literature_access.json'),fullfile(outDir,'literature_access.json'));
    if ~isempty(cfg.referenceDirectory)
        referenceReport = verify_main_results(cfg.referenceDirectory);
        cfg.referenceSummary = referenceReport.summary;
        referenceManifest = dmt_input_manifest(cfg.referenceDirectory);
        referenceFile = fullfile(outDir,'reference_input_manifest.csv');
        if isfile(referenceFile)
            savedInput = readtable(referenceFile,'TextType','string');
            assert(sameManifest(savedInput,referenceManifest),'DMT:ReferenceChanged', ...
                'Reference input bytes changed since the study started.');
        else
            writetable(referenceManifest,referenceFile);
        end
        fprintf('Reference 0 is metadata only; its samples/calibration are excluded from new rounds.\n');
    else
        fprintf('Reference 0 not supplied to task B; task A must be handled separately.\n');
    end
    toolboxes = ver;
    save(fullfile(outDir,'config_snapshot.mat'),'cfg','sourceManifest','configID', ...
        'sourceID','seedMapping','seedMappingID','toolboxes');
    writeEnvironment(outDir,cfg);
    dmt_log_info(outDir,['STUDY_TRAVERSAL_BEGIN ' utcNow()]);
    haveQAM = ~isempty(which('qammod')) && ~isempty(which('qamdemod')) && ~isempty(ver('comm'));
    dmt_record_check(outDir,'Communications Toolbox QAM functions available',double(haveQAM),1,0,haveQAM);
    nNewSeeds = numel(unique([seedMapping.data_seed;seedMapping.noise_seed]));
    dmt_record_check(outDir,'220 new independent streams',nNewSeeds,220,0,nNewSeeds==220);
    dmt_self_checks(cfg,outDir);
    for c = 1:10
        roundCfg = cfg;
        roundCfg.calibration_id = c;
        base = 2000000+100000*c;
        roundCfg.trainDataSeed = base+101;
        roundCfg.trainNoiseSeed = base+102;
        roundCfg.probeDataSeed = base+201;
        roundCfg.probeNoiseSeed = base+202;
        expectedRound = struct('config_id',configID,'source_id',sourceID, ...
            'seed_mapping_id',seedMappingID,'calibration_id',c,'round_cfg',roundCfg);
        roundPath = fullfile(outDir,'calibrations',sprintf('calibration_%02d.mat',c));
        [saved,exists] = readCheckpoint(roundPath);
        [valid,reason] = dmt_study_validate_round(saved,cfg,expectedRound);
        if valid
            one = saved.round;
            fprintf('%s | calibration_id=%d | reused VALID frozen calibration checkpoint\n',utcNow(),c);
        else
            if exists, quarantine(roundPath,reason); end
            fprintf('%s | calibration_id=%d | fresh independent training A and probe B\n',utcNow(),c);
            calibration = dmt_calibrate(roundCfg);
            [profiles,feasible,loading] = dmt_load_profiles(roundCfg,calibration);
            why = '';
            if ~feasible
                why = ['Round protocol infeasible: no feasible QPSK baseline on k=' ...
                    mat2str(loading.infeasible_k.') ...
                    '; all nine matched groups unrun, estimates retained; not a claim that Fixed16 cannot transmit'];
            end
            one = struct('calibration_id',c,'feasible',feasible,'calibration',calibration, ...
                'profiles',profiles,'initialization_id', ...
                dmt_initialization_id(roundCfg,calibration,profiles),'reason',why, ...
                'config_snapshot',roundCfg);
            saved = struct('config_id',configID,'source_id',sourceID, ...
                'seed_mapping_id',seedMappingID,'round',one);
            [valid,reason] = dmt_study_validate_round(saved,cfg,expectedRound);
            assert(valid,'DMT:InvalidNewCalibration','New calibration rejected: %s',reason);
            dmt_study_atomic_save(roundPath,saved);
        end
        rounds(c) = one;
        if ~one.feasible
            fprintf('%s | calibration_id=%d | INFEASIBLE: %s\n',utcNow(),c,one.reason);
            dmt_write_study_summary(cfg,rounds,runs,outDir);
            continue;
        end
        frozenID = one.initialization_id;
        for s = 1:3
            for j = 1:3
                seed = cfg.seeds(j);
                expected = struct('config_id',configID,'source_id',sourceID, ...
                    'seed_mapping_id',seedMappingID,'initialization_id',frozenID, ...
                    'calibration_id',c,'scheme',one.profiles(s).name,'seed',seed, ...
                    'data_seed',base+1000*s+10*j+1,'noise_seed',base+1000*s+10*j+2, ...
                    'M',one.profiles(s).M);
                path = fullfile(outDir,'groups',sprintf('cal_%02d_%s_seed_%d.mat', ...
                    c,one.profiles(s).name,seed));
                [group,exists] = readCheckpoint(path);
                [valid,reason] = dmt_study_validate_group(group,cfg,expected);
                if valid
                    run = group.run;
                    fprintf('%s | calibration_id=%d %s seed=%d | verified complete: 100000 symbols; skip\n', ...
                        utcNow(),c,run.scheme,seed);
                else
                    if exists, quarantine(path,reason); end
                    streams = struct('data_seed',expected.data_seed,'noise_seed',expected.noise_seed, ...
                        'calibration_id',c,'initialization_id',frozenID);
                    run = dmt_simulate(roundCfg,one.calibration,one.profiles(s),s,seed,'main',streams);
                    group = struct('state','complete','config_id',configID,'source_id',sourceID, ...
                        'seed_mapping_id',seedMappingID,'initialization_id',frozenID, ...
                        'count_id',dmt_study_count_id(run),'run',run);
                    [valid,reason] = dmt_study_validate_group(group,cfg,expected);
                    assert(valid,'DMT:InvalidNewGroup','New group rejected: %s',reason);
                    dmt_study_atomic_save(path,group);
                end
                if isempty(runs), runs=run; else, runs(end+1)=run; end %#ok<AGROW>
                fprintf('%s | actual completed groups now %d/90\n',utcNow(),numel(runs));
            end
        end
        currentRuns = runs([runs.calibration_id]==c);
        dmt_post_checks(roundCfg,one.calibration,one.profiles,currentRuns,outDir,'main');
        same = strcmp(frozenID,dmt_initialization_id(roundCfg,one.calibration,one.profiles));
        dmt_record_check(outDir,sprintf('calibration %d profile remained frozen',c),double(same),1,0,same);
        dmt_write_study_summary(cfg,rounds,runs,outDir);
    end
    output = dmt_write_study_summary(cfg,rounds,runs,outDir);
    [~,afterSourceID] = dmt_source_manifest(projectDir);
    assert(strcmp(sourceID,afterSourceID),'DMT:SourceChanged','Source changed during the study.');
    if ~isempty(cfg.referenceDirectory)
        afterInput = dmt_input_manifest(cfg.referenceDirectory);
        assert(sameManifest(referenceManifest,afterInput),'DMT:ReferenceChanged','Reference bytes changed.');
    end
    completedGroups = writeCompletion(outDir,cfg,rounds,runs,configID,sourceID,seedMappingID);
    all90Complete = completedGroups==90 && output.all_90_groups_complete;
    status = 'finished_with_infeasible_calibrations';
    if all90Complete, status='complete_90_groups'; end
    save(fullfile(outDir,'final_study_results.mat'),'cfg','rounds','runs','output','sourceManifest', ...
        'configID','sourceID','seedMapping','seedMappingID','referenceManifest','completedGroups','all90Complete','status');
    if isfile(fullfile(outDir,'failure_status.txt'))
        movefile(fullfile(outDir,'failure_status.txt'),fullfile(outDir,['previous_failure_' stamp() '.txt']));
    end
    fprintf('%s | STUDY FINISHED | actual completed=%d/90 | status=%s\n',utcNow(),completedGroups,status);
    report = struct('output_dir',outDir,'completed_groups',completedGroups, ...
        'planned_groups',90,'all_90_groups_complete',all90Complete,'status',status,'tables',output);
catch ME
    fid = fopen(fullfile(outDir,'failure_status.txt'),'w');
    if fid>=0
        fprintf(fid,['INCOMPLETE study; verified/collected groups in this traversal=%d/90.\n' ...
            'Other retained checkpoints may not yet have been visited or verified; no global completion claim.\n%s\n'], ...
            numel(runs),getReport(ME,'extended','hyperlinks','off'));
        fclose(fid);
    end
    fprintf(2,'Study interrupted. Keep this directory and follow its log: %s\n%s\n',outDir,ME.message);
    rethrow(ME);
end
end

function [value,exists] = readCheckpoint(path)
exists = isfile(path); value = struct();
if exists
    try
        loaded = load(path,'checkpoint');
        if isfield(loaded,'checkpoint'), value=loaded.checkpoint; end
    catch ME
        fprintf('Unreadable checkpoint retained for quarantine: %s | %s\n',path,ME.message);
    end
end
end

function quarantine(path,reason)
backup = [path '.rejected_' stamp() '.mat'];
movefile(path,backup);
fprintf('Retained rejected checkpoint: %s | reason: %s\n',backup,reason);
end

function count = writeCompletion(outDir,cfg,rounds,runs,configID,sourceID,mapID)
fid = fopen(fullfile(outDir,'completion_check.txt'),'w');
assert(fid>=0); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'Plan=90 groups; physical v1.0; protocol v1.2; reference 0 excluded.\n');
count=0;
for c=1:10
    for s=1:3
        names={'Uniform','Loaded','Fixed16'};
        for j=1:3
            if ~isfinite(rounds(c).feasible)
                status='MISSING_CALIBRATION';
            elseif ~rounds(c).feasible
                status='INFEASIBLE_NOT_RUN';
            else
                chosen=find([runs.calibration_id]==c & strcmp({runs.scheme},names{s}) & [runs.seed]==cfg.seeds(j));
                assert(numel(chosen)==1,'DMT:CompletionCounts','Missing/duplicate actual group.');
                run=runs(chosen);
                base=2000000+100000*c;
                expected=struct('config_id',configID,'source_id',sourceID,'seed_mapping_id',mapID, ...
                    'initialization_id',rounds(c).initialization_id,'calibration_id',c, ...
                    'scheme',names{s},'seed',cfg.seeds(j),'data_seed',base+1000*s+10*j+1, ...
                    'noise_seed',base+1000*s+10*j+2,'M',rounds(c).profiles(s).M);
                path=fullfile(outDir,'groups',sprintf('cal_%02d_%s_seed_%d.mat',c,names{s},cfg.seeds(j)));
                loaded=load(path,'checkpoint');
                [valid,reason]=dmt_study_validate_group(loaded.checkpoint,cfg,expected);
                assert(valid,'DMT:CompletionCounts','Saved group failed: %s',reason);
                assert(isequaln(run,loaded.checkpoint.run));
                status='COMPLETE_100000'; count=count+1;
            end
            fprintf(fid,'calibration_id=%d | scheme=%s | seed=%d | %s\n',c,names{s},cfg.seeds(j),status);
        end
    end
end
assert(count==numel(runs));
fprintf(fid,'Actual complete groups=%d/90. Remaining/unrun=%d.\n',count,90-count);
fprintf(fid,'Pooled counts only within calibration_id/scheme/k. Profile counted once per calibration.\n');
fprintf(fid,'Reference input SHA-256 checked before/after when supplied. Source identity unchanged.\n');
end

function same = sameManifest(a,b)
a=sortrows(a,'relative_path'); b=sortrows(b,'relative_path');
same=height(a)==height(b) && isequal(string(a.relative_path),string(b.relative_path)) && ...
    isequal(string(a.sha256),string(b.sha256)) && isequal(a.bytes,b.bytes);
end

function writeEnvironment(outDir,cfg)
fid=fopen(fullfile(outDir,'environment.txt'),'w'); assert(fid>=0);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['Current MATLAB %s (%s)\nInitial MATLAB %s (%s)\n' ...
    'Initial UTC start: %s\nProtocol1.2, physical1.0\n'], ...
    version,version('-release'),cfg.MATLABVersion,cfg.MATLABRelease,cfg.startedAt);
fprintf(fid,'Ten new A/B calibrations. NumCalibrations=10; mainSymbols=100000; chunkSize=%d.\n',cfg.chunkSize);
installed=ver;
for j=1:numel(installed), fprintf(fid,'%s | %s\n',installed(j).Name,installed(j).Version); end
end

function value=stamp()
value=char(datetime('now','TimeZone','UTC','Format','yyyyMMdd_HHmmss_SSS'));
end

function value=utcNow()
value=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss.SSS Z'));
end
