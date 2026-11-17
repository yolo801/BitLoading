function report = verify_dmt_v13(mode,varargin)
%VERIFY_DMT_V13 Read-only audit of actual v1.3 checkpoints and exported data.
% Verification of all after a linear-only run reports the unrun slots; it
% never relabels preflight, infeasible strategies or partial groups complete.
if nargin<1, mode='all'; end
mode=validatestring(mode,{'preflight','linear','imdd','all'});
parser=inputParser;
addParameter(parser,'ResultDirectory','',@(x)ischar(x)||(isstring(x)&&isscalar(x)));
parse(parser,varargin{:});
outDir=char(parser.Results.ResultDirectory);
check(isfolder(outDir),'Supply an existing ResultDirectory.');
phase='formal'; if strcmp(mode,'preflight'), phase='preflight'; end
phaseDir=fullfile(outDir,phase);
rootFiles={'study_state.mat','config_snapshot.mat','source_manifest.csv', ...
    'seed_mapping_formal.csv','seed_mapping_preflight.csv','run.log', ...
    'verification_checks.txt','literature_mapping.md','literature_access.json'};
for j=1:numel(rootFiles), nonempty(fullfile(outDir,rootFiles{j})); end
if isfile(fullfile(outDir,'failure_status.txt')) && isfile(fullfile(outDir,'power_mean_investigation.txt'))
    error('DMT:V13PowerInvestigation','Counts are retained, but the recorded optical-power investigation is unresolved.');
end
check(~isfile(fullfile(outDir,'failure_status.txt')),'No unresolved traversal failure_status.txt.');
nonempty(fullfile(phaseDir,'phase_results.mat'));
data=load(fullfile(phaseDir,'phase_results.mat'));
check(all(isfield(data,{'cfg','records','runs','tables','phase','meta','plan'})), ...
    'Phase snapshot contains actual records, counts and provenance.');
cfg=data.cfg; records=data.records; runs=data.runs; meta=data.meta;
if strcmp(phase,'formal')
    nonempty(fullfile(outDir,'final_v13_results.mat'));
    final=load(fullfile(outDir,'final_v13_results.mat'),'cfg','records','runs','tables','result','configID','sourceID');
    check(isequaln(final.cfg,cfg) && isequaln(final.records,records) && isequaln(final.runs,runs) && ...
        isequaln(final.tables,data.tables),'Root final MAT equals the actual formal phase snapshot.');
    check(final.result.formal_completed_groups==numel(runs) && ...
        final.result.formal_planned_groups==360 && strcmp(final.result.status,'requested_scope_finished'), ...
        'Root completion result counts actual payload groups.');
end
check(strcmp(data.phase,phase),'Phase identity matches the requested verification.');
check(strcmp(cfg.protocolVersion,'1.3') && strcmp(cfg.specVersion,'1.0') && ...
    strcmp(cfg.imddSpecVersion,'1.0'),'Protocol and two physical-model versions.');
check(strcmp(dmt_v13_config_id(cfg),dmt_v13_config_id(dmt_v13_config())), ...
    'Frozen physical parameters, budgets, mapping and normal transform.');
stateFile=load(fullfile(outDir,'study_state.mat'),'checkpoint'); state=stateFile.checkpoint;
snapshot=load(fullfile(outDir,'config_snapshot.mat'));
check(strcmp(state.config_id,dmt_v13_config_id(state.cfg)) && ...
    strcmp(state.config_id,dmt_v13_config_id(cfg)) && ...
    strcmp(state.config_id,dmt_v13_config_id(snapshot.cfg)) && ...
    strcmp(meta.config_id,state.config_id),'State and phase scientific configuration identities.');
manifest=readtable(fullfile(outDir,'source_manifest.csv'),'TextType','string');
sameTable(manifest,state.source_manifest,{'relative_path'},'Original source manifest');
sameTable(manifest,snapshot.sourceManifest,{'relative_path'},'Source snapshot');
manifest=sortrows(manifest,'relative_path');
check(height(manifest)>0 && numel(unique(string(manifest.relative_path)))==height(manifest), ...
    'Source manifest has unique original paths.');
check(all(manifest.bytes>0 & manifest.bytes==fix(manifest.bytes)) && ...
    all(cellfun(@(x)~isempty(regexp(x,'^[0-9a-f]{64}$','once')), ...
    cellstr(string(manifest.sha256)))),'Source byte counts and SHA-256 encodings.');
sourceID=dmt_sha256(join(string(manifest.relative_path)+" "+string(manifest.sha256),newline));
check(strcmp(sourceID,state.source_id) && strcmp(sourceID,snapshot.sourceID) && ...
    strcmp(sourceID,meta.source_id),'Original source identity; current installation is not substituted.');
if strcmp(phase,'formal')
    check(strcmp(final.configID,state.config_id) && strcmp(final.sourceID,sourceID), ...
        'Root final MAT retains the same frozen configuration and source identities.');
end
formalPlan=dmt_v13_seed_mapping(cfg,'formal'); prePlan=dmt_v13_seed_mapping(cfg,'preflight');
check(isequaln(snapshot.formalPlan,formalPlan) && isequaln(snapshot.preflightPlan,prePlan), ...
    'Original plan snapshots match both exact independent namespaces.');
keys={'phase','scenario_idx','calibration_id','stage','scheme','slot'};
sameTable(readtable(fullfile(outDir,'seed_mapping_formal.csv'),'TextType','string'),formalPlan,keys,'Formal stream plan');
sameTable(readtable(fullfile(outDir,'seed_mapping_preflight.csv'),'TextType','string'),prePlan,keys,'Preflight stream plan');
plan=formalPlan; nCal=cfg.calibrationCount;
if strcmp(phase,'preflight'), plan=prePlan; nCal=1; end
check(isequaln(data.plan,plan) && strcmp(meta.seed_map_id,dmt_v13_hash(plan)), ...
    'Phase uses exactly its independent stream namespace.');
check(numel(records)==4*nCal,'All scenario/calibration slots retained.');
recordKeys=string([records.scenario_idx])+":"+string([records.calibration_id]);
check(numel(unique(recordKeys))==numel(records),'Unique calibration slots.');
if ~isempty(runs)
    runKeys=string([runs.scenario_idx])+":"+string([runs.calibration_id])+":"+ ...
        string({runs.scheme})+":"+string([runs.seed]);
    check(numel(unique(runKeys))==numel(runs),'No duplicated actual payload group.');
end
traceFolders={'feedback_records','tx_profiles','rx_profiles','configuration_ack','validation_probe_records'};
checkedRuns=0;
for q=1:4
    scenario=cfg.scenarios(q);
    for c=1:nCal
        position=find([records.scenario_idx]==scenario.scenario_idx & [records.calibration_id]==c);
        check(numel(position)==1,'Exactly one planned scenario/calibration record.');
        record=records(position);
        selected=[];
        if ~isempty(runs), selected=find([runs.scenario_idx]==scenario.scenario_idx & [runs.calibration_id]==c); end
        if ~record.configured
            check(isempty(selected),'No payload is attributed to an unconfigured calibration.');
            continue;
        end
        key=sprintf('sc_%d_cal_%02d',scenario.scenario_idx,c);
        saved=load(fullfile(phaseDir,'calibration_records',[key '.mat']),'checkpoint');
        [valid,reason]=dmt_v13_validate_record(saved.checkpoint,cfg,scenario,c,phase,meta);
        check(valid,['Frozen explicit-control record: ' reason]);
        check(isequaln(saved.checkpoint.record,record),'Phase snapshot equals the executed calibration record.');
        hash=saved.checkpoint.record_hash;
        objects={struct('sent',record.exchange.feedback_sent,'received',record.exchange.feedback_received), ...
            record.exchange.tx_profiles,record.exchange.rx_profiles,record.exchange.acks,record.probes};
        for t=1:numel(traceFolders)
            trace=load(fullfile(phaseDir,traceFolders{t},[key '.mat']),'checkpoint'); value=trace.checkpoint;
            check(strcmp(value.config_id,meta.config_id) && strcmp(value.source_id,meta.source_id) && ...
                strcmp(value.seed_map_id,meta.seed_map_id) && strcmp(value.record_hash,hash) && ...
                isequaln(value.object,objects{t}),['Saved separate local trace: ' traceFolders{t}]);
        end
        for s=1:3
            tx=record.exchange.tx_profiles(s);
            for j=1:3
                chosen=[];
                if ~isempty(runs), chosen=find([runs.scenario_idx]==scenario.scenario_idx & ...
                    [runs.calibration_id]==c & strcmp({runs.scheme},tx.scheme) & [runs.seed]==cfg.seeds(j)); end
                if ~tx.feasible
                    check(isempty(chosen),'Infeasible strategy has no fabricated payload counters.');
                    continue;
                end
                if isempty(chosen), continue; end % An unrun slot remains incomplete in the rebuilt table.
                check(numel(chosen)==1,'One actual group for each completed planned slot.');
                file=fullfile(phaseDir,'payload_counts',sprintf('%s_%s_seed_%d.mat',key,tx.scheme,cfg.seeds(j)));
                group=load(file,'checkpoint'); expected=meta; expected.record_hash=hash;
                [valid,reason]=dmt_v13_validate_run(group.checkpoint,cfg,scenario,record,s,cfg.seeds(j),phase,expected);
                check(valid,['Complete actual payload group: ' reason]);
                check(isequaln(group.checkpoint.run,runs(chosen)),'Saved group matches the phase count record.');
                checkedRuns=checkedRuns+1;
            end
        end
    end
end
check(checkedRuns==numel(runs),'Every actual count record belongs to a validated checkpoint.');
rebuilt=dmt_v13_tables(cfg,records,runs,phase);
fields={'seed','pooled','summary','run_status','robustness','profile_frequency','power','papr','probe_C'};
files={'per_calibration_seed.csv','per_calibration_pooled.csv','per_calibration_summary.csv', ...
    'run_status.csv','robustness_summary.csv','profile_frequency.csv','power_clipping_metrics.csv', ...
    'papr_ccdf_counts.csv','validation_probe_C.csv'};
sortKeys={{'scenario_idx','calibration_id','scheme','payload_seed','k'}, ...
    {'scenario_idx','calibration_id','scheme','k'},{'scenario_idx','calibration_id','scheme'}, ...
    {'scenario_idx','calibration_id','scheme','payload_seed'},{'scenario_idx','scheme'}, ...
    {'scenario_idx','scheme','k','M'},{'scenario_idx','calibration_id','scheme','payload_seed'}, ...
    {'scenario_idx','calibration_id','scheme','payload_seed','threshold_dB'}, ...
    {'scenario_idx','calibration_id','scheme','k'}};
for j=1:numel(fields)
    nonempty(fullfile(phaseDir,files{j}));
    sameTable(readtable(fullfile(phaseDir,files{j}),'TextType','string'),rebuilt.(fields{j}),sortKeys{j},files{j});
    check(isequaln(rebuilt.(fields{j}),data.tables.(fields{j})),['MAT table equals actual reconstruction: ' fields{j}]);
end
check(height(rebuilt.run_status)==4*nCal*9 && height(rebuilt.summary)==4*nCal*3 && ...
    height(rebuilt.seed)==24*checkedRuns,'Planned/actual rows derive from complete counters.');
if strcmp(phase,'formal') && checkedRuns==360
    check(height(rebuilt.seed)==8640 && height(rebuilt.pooled)==2880 && height(rebuilt.summary)==120, ...
        'All completed formal groups yield 8640/2880/120 rows.');
end
nonempty(fullfile(phaseDir,'completion_check.txt'));
completion=fileread(fullfile(phaseDir,'completion_check.txt'));
check(contains(completion,['Phase=' phase]),'Completion record names the actual phase.');
check(numel(regexp(completion,'(?m)^scenario=','match'))==height(rebuilt.run_status), ...
    'Completion record contains every planned group exactly once.');
completionLines=string(splitlines(completion));
for j=1:height(rebuilt.run_status)
    r=rebuilt.run_status(j,:);
    line=sprintf('scenario=%s | calibration=%d | scheme=%s | seed=%d | status=%s | symbols=%.0f | reason=%s', ...
        char(r.scenario_id),r.calibration_id,char(r.scheme),r.payload_seed, ...
        char(r.status),r.actual_symbols,char(r.reason));
    check(sum(completionLines==string(line))==1,'Completion status/counters/reason match each actual planned slot.');
end
nonempty(fullfile(phaseDir,'report_notes_zh.md')); nonempty(fullfile(phaseDir,'figure_caption_en.txt'));
figuresComplete=isfield(data.tables,'plots_completed') && data.tables.plots_completed;
if figuresComplete
    nonempty(fullfile(phaseDir,'figure_manifest.csv'));
    figures=readtable(fullfile(phaseDir,'figure_manifest.csv'),'TextType','string');
    sameTable(figures,data.tables.figures,{'figure'},'Actual figure manifest');
    for j=1:height(figures)
        if string(figures.status(j))~="written", continue; end
        for extension={'.png','.pdf','.fig'}
            nonempty(fullfile(phaseDir,[char(string(figures.figure(j))) extension{1}]));
        end
    end
end
verification=fileread(fullfile(outDir,'verification_checks.txt'));
historicalFailures=~isempty(regexp(verification,'(?m)^FAIL\s*\|','once'));
markers=strfind(verification,'INFO | V13_TRAVERSAL_BEGIN ');
if ~isempty(markers), verification=verification(markers(end):end); end
check(~isempty(regexp(verification,'(?m)^PASS\s*\|','once')) && ...
    isempty(regexp(verification,'(?m)^FAIL\s*\|','once')),'Latest implementation-check traversal has no unresolved FAIL.');
log=fileread(fullfile(outDir,'run.log'));
if strcmp(phase,'formal')
    check(~isempty(regexp(log,['V13 FORMAL SCOPE FINISHED[^\n]*actual completed=' num2str(checkedRuns) '/360'],'once')), ...
        'Formal finished log names the actual completed-group count.');
else
    check(contains(log,'V13 PREFLIGHT FINISHED') || contains(log,'V13 FORMAL SCOPE FINISHED'), ...
        'Preflight belongs to an actually finished traversal.');
end
referenceAvailable=isfield(snapshot,'reference') && snapshot.reference.available;
referenceReverified=false;
if referenceAvailable
    ref=snapshot.reference; sameTable(readtable(fullfile(outDir,'reference_input_manifest.csv'),'TextType','string'), ...
        ref.manifest,{'relative_path'},'Recorded reference inputs');
    if isfolder(ref.directory)
        sameTable(dmt_input_manifest(ref.directory),ref.manifest,{'relative_path'},'Reference bytes now'); referenceReverified=true;
    else, fprintf('INFO | Reference path unavailable now; current bytes were not reverified.\n'); end
end
requestedCfg=cfg; requestedCfg.requested_scenarios=0:3;
if strcmp(mode,'linear'), requestedCfg.requested_scenarios=0;
elseif strcmp(mode,'imdd'), requestedCfg.requested_scenarios=1:3; end
requested=dmt_v13_tables(requestedCfg,records,runs,phase);
powerPending=rebuilt.mean_power_alert_groups>0;
preflightGroups=checkedRuns; formalGroups=0;
if strcmp(phase,'formal')
    preflight=verify_dmt_v13('preflight','ResultDirectory',outDir);
    check(preflight.valid && preflight.requested_scope_resolved,'Independent preflight counts and exports verified.');
    preflightGroups=preflight.completed_groups; formalGroups=checkedRuns;
end
integrityValid=~powerPending && figuresComplete;
scopeResolved=requested.requested_incomplete_groups==0;
report=struct('valid',integrityValid && scopeResolved,'integrity_valid',integrityValid, ...
    'data_integrity_valid',true,'phase',phase,'output_dir',outDir, ...
    'completed_groups',checkedRuns,'planned_groups',rebuilt.planned_groups, ...
    'formal_completed_groups',formalGroups,'preflight_completed_groups',preflightGroups, ...
    'requested_completed_groups',requested.requested_completed_groups, ...
    'requested_planned_groups',requested.requested_planned_groups, ...
    'requested_infeasible_groups',requested.requested_infeasible_groups, ...
    'requested_incomplete_groups',requested.requested_incomplete_groups, ...
    'requested_scope_resolved',scopeResolved, ...
    'all_360_completed',strcmp(phase,'formal') && checkedRuns==360, ...
    'figures_complete',figuresComplete,'power_investigation_required',powerPending, ...
    'reference_available',referenceAvailable,'reference_bytes_reverified',referenceReverified, ...
    'historical_failures_retained',historicalFailures,'robustness',rebuilt.robustness);
fprintf('Verified %s actual groups=%d/%d; requested completed=%d, infeasible=%d, incomplete=%d.\n', ...
    phase,checkedRuns,rebuilt.planned_groups,requested.requested_completed_groups, ...
    requested.requested_infeasible_groups,requested.requested_incomplete_groups);
if powerPending, fprintf(2,'DMT:V13PowerInvestigation | Counts retained, but the optical-power budget needs investigation.\n'); end
if ~figuresComplete, fprintf(2,'DMT:V13FiguresIncomplete | Counts verified; figure exports are incomplete.\n'); end
end

function nonempty(path)
info=dir(path); check(numel(info)==1 && ~info.isdir && info.bytes>0,['Nonempty file: ' path]);
end
function check(condition,label)
assert(isscalar(condition) && logical(condition),'DMT:InvalidV13Results','%s',label);
fprintf('PASS | %s\n',label);
end
function sameTable(a,b,keys,label)
check(istable(a) && istable(b) && height(a)==height(b) && ...
    isequal(a.Properties.VariableNames,b.Properties.VariableNames),[label ' schema']);
a=sortrows(a,keys); b=sortrows(b,keys);
for j=1:width(a)
    field=a.Properties.VariableNames{j}; x=a.(field); y=b.(field);
    if islogical(x) || islogical(y), equal=isequal(asLogical(x),asLogical(y));
    elseif isnumeric(x) && isnumeric(y)
        check(isequal(isnan(x),isnan(y)),[label ' ' field ' missing values']);
        present=~isnan(y); x=double(x(present)); y=double(y(present));
        equal=all(isfinite(x)) && all(isfinite(y)) && all(abs(x-y)<=1e-12+1e-10*abs(y));
    else
        x=string(x); y=string(y); x(ismissing(x))=""; y(ismissing(y))=""; equal=isequal(x,y);
    end
    check(equal,[label ' ' field ' values']);
end
end
function value=asLogical(input)
if isnumeric(input) || islogical(input)
    check(all(isfinite(input(:))) && all(ismember(input(:),[0 1])),'Logical numeric encoding'); value=logical(input);
else
    text=lower(string(input)); check(all(ismember(text(:),["true" "false" "1" "0"])),'Logical text encoding');
    value=text=="true" | text=="1";
end
end
