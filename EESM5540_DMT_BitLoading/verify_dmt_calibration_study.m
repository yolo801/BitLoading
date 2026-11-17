function report = verify_dmt_calibration_study(outDir)
%VERIFY_DMT_CALIBRATION_STUDY Read-only audit of actual v1.2 study completion.
% No simulation, plotting, result rewriting or cross-profile pooling occurs.
assert(nargin==1 && (ischar(outDir) || (isstring(outDir) && isscalar(outDir))), ...
    'DMT:InvalidStudyDirectory','Supply one completed study directory.');
outDir = char(outDir);
assert(isfolder(outDir),'DMT:InvalidStudyDirectory','Study directory not found.');
files = {'final_study_results.mat','study_state.mat','config_snapshot.mat', ...
    'source_manifest.csv','seed_mapping.csv','environment.txt','run.log', ...
    'verification_checks.txt','completion_check.txt','literature_mapping.md', ...
    'literature_access.json','per_calibration_seed.csv','per_calibration_pooled.csv', ...
    'per_calibration_summary.csv','profile_frequency.csv','robustness_summary.csv', ...
    'per_calibration_profile.csv','report_notes_zh.md'};
for j=1:numel(files)
    info=dir(fullfile(outDir,files{j}));
    check(numel(info)==1 && ~info.isdir && info.bytes>0,['nonempty artifact ' files{j}]);
end
check(~isfile(fullfile(outDir,'failure_status.txt')),'no unresolved failure_status.txt');
data=load(fullfile(outDir,'final_study_results.mat'));
required={'cfg','rounds','runs','output','sourceManifest','configID','sourceID', ...
    'seedMapping','seedMappingID','referenceManifest','completedGroups','all90Complete','status'};
check(all(isfield(data,required)),'complete final study fields');
cfg=data.cfg; rounds=data.rounds; runs=data.runs;
check(strcmp(cfg.runMode,'main') && strcmp(cfg.protocolVersion,'1.2') && ...
    strcmp(cfg.specVersion,'1.0') && cfg.NumCalibrations==10,'main protocol1.2, physical1.0, ten rounds');
baseline=dmt_default_config();
fields={'NFFT','NCP','Fs','k','h','Es','sigma_w2','Mset','targetBER','margin_dB', ...
    'trainSymbols','probeSymbols','mainSymbols','chunkSize','seeds','Tu','TCP','Ts', ...
    'streamType','selfTrainSeed','selfPayloadSeeds','selfNoiseSeed'};
for j=1:numel(fields)
    field=fields{j}; check(isequaln(cfg.(field),baseline.(field)),['frozen cfg.' field]);
end
check(strcmp(dmt_study_config_id(cfg),data.configID),'scientific configuration identity');
mapping=dmt_study_seed_mapping(cfg);
sameTable(readCSV('seed_mapping.csv'),mapping,{'calibration_id','stage','scheme','slot'},'seed CSV');
check(isequaln(mapping,data.seedMapping),'stored exact independent stream plan');
mapID=dmt_sha256(jsonencode(table2struct(mapping)));
check(strcmp(mapID,data.seedMappingID),'stream-plan identity');
manifest=readCSV('source_manifest.csv');
sameTable(manifest,data.sourceManifest,{'relative_path'},'source manifest');
check(height(manifest)>0 && numel(unique(string(manifest.relative_path)))==height(manifest), ...
    'source paths are unique');
check(all(manifest.bytes>0 & manifest.bytes==fix(manifest.bytes)) && ...
    all(cellfun(@(x)~isempty(regexp(x,'^[0-9a-f]{64}$','once')),cellstr(string(manifest.sha256)))), ...
    'source byte counts and SHA-256 encodings');
manifest=sortrows(manifest,'relative_path');
sourceID=dmt_sha256(join(string(manifest.relative_path)+" "+string(manifest.sha256),newline));
check(strcmp(sourceID,data.sourceID) && strcmp(sourceID,cfg.sourceManifestID),'original source identity');
snapshot=load(fullfile(outDir,'config_snapshot.mat'));
check(isequaln(snapshot.cfg,cfg) && isequaln(snapshot.sourceManifest,data.sourceManifest), ...
    'configuration/source snapshots unchanged');
state=load(fullfile(outDir,'study_state.mat'),'checkpoint');
check(strcmp(state.checkpoint.config_id,data.configID) && ...
    strcmp(state.checkpoint.source_id,sourceID) && strcmp(state.checkpoint.seed_mapping_id,mapID), ...
    'resume-state identities');
check(strcmp(dmt_study_config_id(state.checkpoint.cfg),data.configID), ...
    'resume-state configuration contents match their identity');
check(strcmp(state.checkpoint.cfg.sourceManifestID,sourceID),'resume-state source identity');
check(numel(rounds)==10 && isequal([rounds.calibration_id],1:10),'ten unique planned calibration records');
if ~isempty(runs)
    keys=string([runs.calibration_id])+":"+string({runs.scheme})+":"+string([runs.seed]);
    check(numel(unique(keys))==numel(runs),'no duplicated actual payload groups');
end
names={'Uniform','Loaded','Fixed16'}; completed=0;
completion=fileread(fullfile(outDir,'completion_check.txt'));
check(numel(regexp(completion,'(?m)^calibration_id=','match'))==90,'90 completion-plan records');
for c=1:10
    roundCfg=cfg; roundCfg.calibration_id=c; base=2000000+100000*c;
    roundCfg.trainDataSeed=base+101; roundCfg.trainNoiseSeed=base+102;
    roundCfg.probeDataSeed=base+201; roundCfg.probeNoiseSeed=base+202;
    expected=struct('config_id',data.configID,'source_id',sourceID,'seed_mapping_id',mapID, ...
        'calibration_id',c,'round_cfg',roundCfg);
    saved=load(fullfile(outDir,'calibrations',sprintf('calibration_%02d.mat',c)),'checkpoint');
    [valid,reason]=dmt_study_validate_round(saved.checkpoint,cfg,expected);
    check(valid,sprintf('calibration %d checkpoint: %s',c,reason));
    check(isequaln(saved.checkpoint.round,rounds(c)),sprintf('calibration %d final/checkpoint identical',c));
    for s=1:3
        for j=1:3
            chosen=[];
            if ~isempty(runs)
                chosen=find([runs.calibration_id]==c & strcmp({runs.scheme},names{s}) & [runs.seed]==cfg.seeds(j));
            end
            if ~rounds(c).feasible
                check(isempty(chosen),sprintf('calibration %d infeasible: no fabricated group',c));
                status='INFEASIBLE_NOT_RUN';
            else
                check(numel(chosen)==1,sprintf('calibration %d %s seed%d exists once',c,names{s},cfg.seeds(j)));
                expected.initialization_id=rounds(c).initialization_id;
                expected.scheme=names{s}; expected.seed=cfg.seeds(j);
                expected.data_seed=base+1000*s+10*j+1; expected.noise_seed=base+1000*s+10*j+2;
                expected.M=rounds(c).profiles(s).M;
                path=fullfile(outDir,'groups',sprintf('cal_%02d_%s_seed_%d.mat',c,names{s},cfg.seeds(j)));
                group=load(path,'checkpoint');
                [valid,reason]=dmt_study_validate_group(group.checkpoint,cfg,expected);
                check(valid,sprintf('calibration %d %s seed%d: %s',c,names{s},cfg.seeds(j),reason));
                check(isequaln(group.checkpoint.run,runs(chosen)),'group checkpoint equals actual final count record');
                completed=completed+1; status='COMPLETE_100000';
            end
            line=sprintf('calibration_id=%d | scheme=%s | seed=%d | %s',c,names{s},cfg.seeds(j),status);
            check(any(string(splitlines(completion))==string(line)), ...
                'completion log agrees exactly with each actual group');
        end
    end
end
check(completed==numel(runs) && completed==data.completedGroups,'actual completed-group totals');
check(contains(completion,sprintf('Actual complete groups=%d/90.',completed)), ...
    'completion log actual count');
[seed,pooled,summary,frequency,robustness]=dmt_study_tables(cfg,rounds,runs);
sameTable(readCSV('per_calibration_seed.csv'),seed,{'calibration_id','scheme','payload_seed','k'},'seed data');
sameTable(readCSV('per_calibration_pooled.csv'),pooled,{'calibration_id','scheme','k'},'pooled data');
sameTable(readCSV('per_calibration_summary.csv'),summary,{'calibration_id','scheme'},'round summaries');
sameTable(readCSV('profile_frequency.csv'),frequency,{'scheme','k','M'},'profile selection frequencies');
sameTable(readCSV('robustness_summary.csv'),robustness,{'scheme'},'robustness summaries');
tables={seed,pooled,summary,frequency,robustness};
fields={'seed','pooled','per_calibration_summary','profile_frequency','robustness_summary'};
for j=1:5, check(isequaln(data.output.(fields{j}),tables{j}),['saved output.' fields{j}]); end
profileCSV=readCSV('per_calibration_profile.csv');
sameTable(profileCSV,data.output.per_calibration_profile, ...
    {'calibration_id','scheme','k'},'saved profile table');
for c=1:10
    if ~rounds(c).feasible, continue; end
    for s=1:3
        rows=sortrows(profileCSV(profileCSV.calibration_id==c & ...
            string(profileCSV.scheme)==string(names{s}),:),'k');
        p=rounds(c).profiles(s);
        check(height(rows)==24 && isequal(rows.k,cfg.k) && isequal(rows.M,p.M), ...
            'profile table is the actual frozen per-round selection');
        check(all(abs(rows.SNR_est_dB-rounds(c).calibration.gamma_hat_dB)<1e-10) && ...
            all(rows.bits_per_symbol==log2(p.M)) && all(rows.B==p.B) && ...
            all(abs(rows.R_payload-p.R_payload)<=1e-10*max(1,p.R_payload)) && ...
            all(string(rows.initialization_id)==string(rounds(c).initialization_id)), ...
            'profile table estimates/bits/rates and calibration identity');
    end
end
check(height(summary)==30 && height(seed)==24*completed,'summary/actual seed row counts');
check(all(summary.status~="incomplete"),'final study has no interrupted calibration');
all90=completed==90 && all([rounds.feasible]);
check(logical(data.all90Complete)==all90 && logical(data.output.all_90_groups_complete)==all90, ...
    'all-90 flag derives from actual complete groups');
if all90
    check(height(seed)==2160 && height(pooled)==720,'complete-study 2160/720 rows');
    info=dir(fullfile(outDir,'results_paragraph_en.txt'));
    check(numel(info)==1 && info.bytes>0,'formal English paragraph after 90 groups');
    words=regexp(strtrim(fileread(fullfile(outDir,'results_paragraph_en.txt'))),'\s+','split');
    check(numel(words)>=150 && numel(words)<=220,'formal paragraph 150--220 words');
    check(strcmp(data.status,'complete_90_groups'),'complete study status');
else
    check(strcmp(data.status,'finished_with_infeasible_calibrations'),'finished infeasible study status');
end
referenceVerified=false;
if ~isempty(data.referenceManifest)
    sameTable(readCSV('reference_input_manifest.csv'),data.referenceManifest,{'relative_path'},'reference input record');
    if isfolder(cfg.referenceDirectory)
        sameTable(dmt_input_manifest(cfg.referenceDirectory),data.referenceManifest,{'relative_path'},'reference input bytes now');
        referenceVerified=true;
    else
        fprintf('INFO | Reference path unavailable now; stored manifest checked, current input bytes not reverified.\n');
    end
end
log=fileread(fullfile(outDir,'run.log'));
check(contains(log,sprintf('STUDY FINISHED | actual completed=%d/90 | status=%s', ...
    completed,data.status)),'study finished log records the actual count/status');
checks=fileread(fullfile(outDir,'verification_checks.txt'));
historicalFailures=~isempty(regexp(checks,'(?m)^FAIL\s*\|','once'));
starts=strfind(checks,'INFO | STUDY_TRAVERSAL_BEGIN ');
if ~isempty(starts), checks=checks(starts(end):end); end
check(isempty(regexp(checks,'(?m)^FAIL\s*\|','once')) && ...
    ~isempty(regexp(checks,'(?m)^PASS\s*\|','once')), ...
    'current executed checks without unresolved failure; previous traversal evidence retained');
report=struct('valid',true,'output_dir',outDir,'completed_groups',completed, ...
    'planned_groups',90,'all_90_groups_complete',all90,'per_calibration_summary',summary, ...
    'robustness_summary',robustness,'reference_bytes_reverified',referenceVerified, ...
    'historical_check_failures_retained',historicalFailures);
fprintf('Verified actual study groups=%d/90; no counters or input files were changed.\n',completed);

    function value=readCSV(name)
        value=readtable(fullfile(outDir,name),'TextType','string');
    end
end

function check(condition,label)
assert(isscalar(condition) && logical(condition),'DMT:InvalidStudyResults','%s',label);
fprintf('PASS | %s\n',label);
end

function sameTable(a,b,keys,label)
check(istable(a) && istable(b) && height(a)==height(b) && ...
    isequal(a.Properties.VariableNames,b.Properties.VariableNames),[label ' schema']);
a=sortrows(a,keys); b=sortrows(b,keys);
for j=1:width(a)
    field=a.Properties.VariableNames{j}; x=a.(field); y=b.(field);
    if islogical(x) || islogical(y)
        check(isequal(bool(x),bool(y)),[label ' ' field ' logical values']);
    elseif isnumeric(x) && isnumeric(y)
        check(isequal(isnan(x),isnan(y)),[label ' ' field ' missing values']);
        present=~isnan(y); x=double(x(present)); y=double(y(present));
        check(all(isfinite(x)) && all(isfinite(y)) && ...
            all(abs(x-y)<=1e-12+1e-10*abs(y)),[label ' ' field ' numeric values']);
    else
        x=string(x); y=string(y); x(ismissing(x))=""; y(ismissing(y))="";
        check(isequal(x,y),[label ' ' field ' text values']);
    end
end
end

function value=bool(input)
if isnumeric(input) || islogical(input)
    check(all(isfinite(input(:))) && all(ismember(input(:),[0 1])),'valid logical numeric encoding');
    value=logical(input);
else
    text=lower(string(input));
    check(all(ismember(text(:),["true" "false" "0" "1"])),'valid logical text encoding');
    value=text=="true" | text=="1";
end
end
