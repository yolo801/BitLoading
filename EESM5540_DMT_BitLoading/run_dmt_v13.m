function result=run_dmt_v13(mode,varargin)
%RUN_DMT_V13 Explicit control loop and fixed linear/IMDD experiment budgets.
% Modes: preflight, linear(90), imdd(270), all(360 formal planned slots).
% A formal mode always validates the isolated four-scenario preflight first.
if nargin<1,mode='all';end
mode=validatestring(mode,{'preflight','linear','imdd','all'});
parser=inputParser;isText=@(x)ischar(x)||(isstring(x)&&isscalar(x));
addParameter(parser,'ResumeDirectory','',isText);
addParameter(parser,'ReferenceDirectory','',isText);
parse(parser,varargin{:});
root=fileparts(mfilename('fullpath'));
cfg=dmt_v13_config();
if strcmp(mode,'linear'),cfg.requested_scenarios=0;
elseif strcmp(mode,'imdd'),cfg.requested_scenarios=1:3;end
configID=dmt_v13_config_id(cfg);
[sourceManifest,sourceID]=dmt_source_manifest(root);
resume=char(parser.Results.ResumeDirectory);
referenceDir=char(parser.Results.ReferenceDirectory);
if isempty(referenceDir)
    candidates={'20261117_160931_509_main_tp95fc34e7_f0f6_453d_92d2_16759118ed52', ...
        '20261116_194846_246_main_tp96b36639_d14e_4dbc_8956_3651acfb6fa8'};
    for j=1:numel(candidates)
        candidate=fullfile(root,'results',candidates{j});
        if isfolder(candidate),referenceDir=candidate;break;end
    end
end
if isempty(resume)
    outputRoot=fullfile(root,'results');
    if ~isempty(referenceDir) && isfolder(referenceDir)
        f=java.io.File(referenceDir);referenceCanonical=char(f.getCanonicalPath());
        f=java.io.File(outputRoot);outputCanonical=char(f.getCanonicalPath());
        assert(~strcmp(outputCanonical,referenceCanonical) && ...
            ~startsWith(outputCanonical,[referenceCanonical filesep],'IgnoreCase',ispc), ...
            'DMT:V13ReferenceOverlap','New output cannot be inside original reference data.');
    end
    if ~isfolder(outputRoot),mkdir(outputRoot);end
    [~,tag]=fileparts(tempname(outputRoot));
    outDir=fullfile(outputRoot,['v1_3_' stamp() '_' tag]);
else
    assert(isfolder(resume),'DMT:V13MissingResume','ResumeDirectory not found.');
    f=java.io.File(resume);outDir=char(f.getCanonicalPath());
end
if ~isempty(referenceDir) && isfolder(referenceDir)
    f=java.io.File(referenceDir);referenceDir=char(f.getCanonicalPath());
    assert(~strcmp(outDir,referenceDir) && ...
        ~startsWith(outDir,[referenceDir filesep],'IgnoreCase',ispc), ...
        'DMT:V13ReferenceOverlap','Output must be outside old reference data.');
end
if ~isfolder(outDir),mkdir(outDir);end
lock=dmt_study_lock(outDir); %#ok<NASGU>
diary(fullfile(outDir,'run.log'));diaryCleanup=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('\n%s | v1.3 mode=%s | output=%s\n',utcNow(),mode,outDir);
fprintf('Command: run_dmt_v13(''%s'',''ResumeDirectory'',''%s'',''ReferenceDirectory'',''%s'')\n', ...
    mode,strrep(resume,'''',''''''),strrep(referenceDir,'''',''''''));
formalPlan=dmt_v13_seed_mapping(cfg,'formal');
preflightPlan=dmt_v13_seed_mapping(cfg,'preflight');
allSeeds=[formalPlan.data_seed;formalPlan.noise_seed;preflightPlan.data_seed;preflightPlan.noise_seed];
assert(numel(unique(allSeeds))==1232 && all(allSeeds<cfg.diag_base));
statePath=fullfile(outDir,'study_state.mat');
try
    if isempty(resume)
        state=struct('cfg',cfg,'config_id',configID,'source_id',sourceID, ...
            'source_manifest',sourceManifest,'created_utc',utcNow(), ...
            'reference_directory',referenceDir);
        dmt_v13_atomic_save(statePath,state);
    else
        old=load(statePath,'checkpoint');state=old.checkpoint;
        assert(strcmp(state.config_id,configID) && strcmp(state.source_id,sourceID) && ...
            strcmp(dmt_v13_config_id(state.cfg),configID), ...
            'DMT:V13ResumeMismatch','Source or frozen configuration changed; start a new directory.');
        if isempty(referenceDir),referenceDir=state.reference_directory;end
    end
    writetable(sourceManifest,fullfile(outDir,'source_manifest.csv'));
    writetable(formalPlan,fullfile(outDir,'seed_mapping_formal.csv'));
    writetable(preflightPlan,fullfile(outDir,'seed_mapping_preflight.csv'));
    copyfile(fullfile(root,'docs','literature_mapping_v1_3.md'),fullfile(outDir,'literature_mapping.md'));
    copyfile(fullfile(root,'docs','literature_access_v1_3.json'),fullfile(outDir,'literature_access.json'));
    copyfile(fullfile(root,'V1_3_README.md'),fullfile(outDir,'README.md'));
    reference=establishReference(referenceDir,outDir);
    environment=struct('MATLABVersion',version,'MATLABRelease',version('-release'), ...
        'computer',computer,'observed_utc',utcNow(),'toolboxes',ver);
    save(fullfile(outDir,'config_snapshot.mat'),'cfg','configID','sourceID','sourceManifest', ...
        'formalPlan','preflightPlan','mode','environment','reference');
    dmt_log_info(outDir,['V13_TRAVERSAL_BEGIN ' utcNow()]);
    haveQAM=~isempty(which('qammod')) && ~isempty(which('qamdemod')) && ~isempty(ver('comm'));
    dmt_record_check(outDir,'v1.3 Communications Toolbox available',double(haveQAM),1,0,haveQAM);
    dmt_record_check(outDir,'unique formal+preflight stream seeds',numel(unique(allSeeds)),1232,0, ...
        numel(unique(allSeeds))==1232);
    dmt_v13_frontend_checks(cfg,outDir);
    [preRecords,preRuns,preTables]=executePhase('preflight',0:3);
    finishInputChecks(root,sourceID,reference,outDir);
    preCfg=cfg;preCfg.requested_scenarios=0:3;
    preTables=dmt_v13_export(preCfg,preRecords,preRuns,fullfile(outDir,'preflight'),'preflight',true);
    replacePhaseTables(fullfile(outDir,'preflight'),preTables);
    assert(preTables.requested_incomplete_groups==0 && preTables.plots_completed, ...
        'DMT:V13IncompletePreflight','Preflight checks/counts/exports are not complete.');
    if strcmp(mode,'preflight')
        result=struct('output_dir',outDir,'mode',mode,'preflight',preTables, ...
            'formal_completed_groups',0,'formal_planned_groups',360, ...
            'status','preflight_only_not_formal_results');
        save(fullfile(outDir,'preflight_result.mat'),'cfg','preRecords','preRuns','result');
        archiveFailure(outDir);
        fprintf('%s | V13 PREFLIGHT FINISHED | formal groups executed=0\n',utcNow());
        return;
    end
    [records,runs,tables]=executePhase('formal',cfg.requested_scenarios);
    finishInputChecks(root,sourceID,reference,outDir);
    tables=dmt_v13_export(cfg,records,runs,fullfile(outDir,'formal'),'formal',true);
    replacePhaseTables(fullfile(outDir,'formal'),tables);
    assert(tables.requested_incomplete_groups==0 && tables.plots_completed, ...
        'DMT:V13IncompleteExports','Counts are preserved, but final requested data/exports are incomplete.');
    result=struct('output_dir',outDir,'mode',mode,'status','requested_scope_finished', ...
        'formal_planned_groups',360,'formal_completed_groups',numel(runs), ...
        'reference_available',reference.available,'tables',tables);
    save(fullfile(outDir,'final_v13_results.mat'),'cfg','records','runs','tables','result', ...
        'configID','sourceID','sourceManifest','formalPlan','preflightPlan','reference','environment');
    archiveFailure(outDir);
    fprintf('%s | V13 FORMAL SCOPE FINISHED | mode=%s | actual completed=%d/360\n', ...
        utcNow(),mode,numel(runs));
catch ME
    fid=fopen(fullfile(outDir,'failure_status.txt'),'w','n','UTF-8');
    if fid>=0
        fprintf(fid,['INCOMPLETE v1.3 traversal. Complete checkpoint files are retained.\n' ...
            'A group not yet revalidated on resume is not claimed complete by this traversal.\n%s\n'], ...
            getReport(ME,'extended','hyperlinks','off'));fclose(fid);
    end
    fprintf(2,'v1.3 stopped; retain directory and follow the original log: %s\n%s\n',outDir,ME.message);
    rethrow(ME);
end

    function [records,runs,tables]=executePhase(phase,requested)
        phaseCfg=cfg;phaseCfg.requested_scenarios=requested;
        phaseDir=fullfile(outDir,phase);if ~isfolder(phaseDir),mkdir(phaseDir);end
        folders={'calibration_records','feedback_records','tx_profiles','rx_profiles', ...
            'configuration_ack','validation_probe_records','payload_counts'};
        for q=1:numel(folders)
            if ~isfolder(fullfile(phaseDir,folders{q})),mkdir(fullfile(phaseDir,folders{q}));end
        end
        plan=formalPlan;count=cfg.calibrationCount;nSymbols=cfg.payloadSymbols;
        if strcmp(phase,'preflight'),plan=preflightPlan;count=1;nSymbols=cfg.preflightSymbols;end
        mapID=dmt_v13_hash(plan);
        meta=struct('config_id',configID,'source_id',sourceID,'seed_map_id',mapID);
        template=struct('scenario_idx',0,'scenario_id','','calibration_id',0, ...
            'configured',false,'receiver',struct(),'exchange',struct(), ...
            'probes',{cell(1,3)},'observations',struct());
        records=repmat(template,1,4*count);runs=struct([]);
        for si=1:4
            for c=1:count
                index=(si-1)*count+c;
                records(index).scenario_idx=cfg.scenarios(si).scenario_idx;
                records(index).scenario_id=cfg.scenarios(si).scenario_id;
                records(index).calibration_id=c;
            end
        end
        % Load every retained record/group, including unrequested scenarios,
        % so a later partitioned mode never erases prior complete evidence.
        try
        for si=1:4
            scenario=cfg.scenarios(si);isRequested=ismember(scenario.scenario_idx,requested);
            for c=1:count
                index=(si-1)*count+c;
                key=sprintf('sc_%d_cal_%02d',scenario.scenario_idx,c);
                recordPath=fullfile(phaseDir,'calibration_records',[key '.mat']);
                [cp,exists]=readCheckpoint(recordPath);
                [valid,reason]=dmt_v13_validate_record(cp,cfg,scenario,c,phase,meta);
                if ~valid && ~isRequested
                    if exists,fprintf('Unrequested checkpoint not counted: %s | %s\n',recordPath,reason);end
                    continue;
                end
                if ~valid
                    if exists,quarantine(recordPath,reason);end
                    fprintf('%s | phase=%s scenario=%s calibration=%d | fresh A/B and explicit control path\n', ...
                        utcNow(),phase,scenario.scenario_id,c);
                    record=records(index);
                    record.observations=dmt_v13_training_probe(cfg,scenario,c,plan);
                    record.receiver=dmt_v13_rx_estimate(cfg,record.observations);
                    record.exchange=dmt_v13_exchange(cfg,scenario,record.receiver);
                    % Selection already happened, even if independent C is interrupted.
                    record.configured=true;records(index)=record;
                    pending=meta;pending.state='configured_validation_C_pending';
                    pending.record=record;pending.record_hash=dmt_v13_hash(record);
                    dmt_v13_atomic_save(fullfile(phaseDir,'calibration_records', ...
                        [key '.configured_pending.mat']),pending);
                    for s=1:3
                        tx=record.exchange.tx_profiles(s);rx=record.exchange.rx_profiles(s);
                        ack=record.exchange.acks(s);
                        if tx.feasible
                            row=plan(plan.scenario_idx==scenario.scenario_idx & plan.calibration_id==c & ...
                                plan.stage=="C" & plan.scheme==string(tx.scheme),:);
                            assert(height(row)==1);
                            seeds=struct('data_seed',row.data_seed,'noise_seed',row.noise_seed);
                            record.probes{s}=dmt_v13_probe_c(cfg,scenario,record.receiver,tx,rx,ack,seeds);
                        end
                    end
                    cp=meta;cp.record=record;cp.record_hash=dmt_v13_hash(record);
                    [valid,reason]=dmt_v13_validate_record(cp,cfg,scenario,c,phase,meta);
                    assert(valid,'DMT:V13InvalidNewRecord','%s',reason);
                    dmt_v13_atomic_save(recordPath,cp);
                else
                    fprintf('%s | phase=%s scenario=%s calibration=%d | verified frozen record reused\n', ...
                        utcNow(),phase,scenario.scenario_id,c);
                end
                record=cp.record;records(index)=record;
                persistTrace(phaseDir,key,cp,meta);
                for s=1:3
                    tx=record.exchange.tx_profiles(s);rx=record.exchange.rx_profiles(s);ack=record.exchange.acks(s);
                    if ~tx.feasible
                        fprintf('INFEASIBLE | phase=%s scenario=%s calibration=%d scheme=%s | %s\n', ...
                            phase,scenario.scenario_id,c,tx.scheme,tx.reason);continue;
                    end
                    for j=1:3
                        label=cfg.seeds(j);
                        runPath=fullfile(phaseDir,'payload_counts',sprintf('%s_%s_seed_%d.mat',key,tx.scheme,label));
                        [group,hasGroup]=readCheckpoint(runPath);
                        expected=meta;expected.record_hash=cp.record_hash;
                        [groupValid,why]=dmt_v13_validate_run(group,cfg,scenario,record,s,label,phase,expected);
                        if ~groupValid && ~isRequested,continue;end
                        if ~groupValid
                            if hasGroup,quarantine(runPath,why);end
                            row=plan(plan.scenario_idx==scenario.scenario_idx & plan.calibration_id==c & ...
                                plan.stage=="payload" & plan.scheme==string(tx.scheme) & plan.seed_label==label,:);
                            assert(height(row)==1);
                            seeds=struct('data_seed',row.data_seed,'noise_seed',row.noise_seed, ...
                                'label',label,'phase',phase);
                            run=dmt_v13_payload(cfg,scenario,record.receiver,tx,rx,ack,seeds,nSymbols);
                            run.record_hash=cp.record_hash;
                            group=meta;group.state='complete';group.record_hash=cp.record_hash;
                            group.run=run;group.run_hash=dmt_v13_hash(run);
                            [groupValid,why]=dmt_v13_validate_run(group,cfg,scenario,record,s,label,phase,expected);
                            assert(groupValid,'DMT:V13InvalidNewRun','%s',why);
                            dmt_v13_atomic_save(runPath,group);
                        end
                        run=group.run;
                        if isempty(runs),runs=run;else,runs(end+1)=run;end %#ok<AGROW>
                        if strcmp(phase,'formal') && run.power_mean_investigation_required
                            dmt_v13_export(phaseCfg,records,runs,phaseDir,phase,false);
                            fid=fopen(fullfile(outDir,'power_mean_investigation.txt'),'a');
                            if fid>=0
                                fprintf(fid,['UNRESOLVED | scenario=%s cal=%d scheme=%s seed=%d mean=%.17g ' ...
                                    'deviation=%.17g samples=%d min=%.17g max=%.17g second=%.17g\n'], ...
                                    run.scenario_id,c,run.scheme,label,run.optical_mean, ...
                                    run.optical_mean_relative_deviation,run.sample_count,run.optical_min, ...
                                    run.optical_peak,run.optical_second_moment);fclose(fid);
                            end
                            error('DMT:V13PowerInvestigation', ...
                                'Long-payload mean optical power deviates over1%%. Counts retained; investigate without rescaling or reseeding.');
                        end
                    end
                end
                dmt_v13_export(phaseCfg,records,runs,phaseDir,phase,false);
            end
        end
        catch phaseError
            interruption=phaseError.message;
            partial=struct('cfg',phaseCfg,'records',records,'runs',runs,'phase',phase, ...
                'meta',meta,'plan',plan,'interruption',interruption);
            save(fullfile(phaseDir,'interrupted_phase.mat'),'-struct','partial');
            try
                dmt_v13_export(phaseCfg,records,runs,phaseDir,phase,false);
            catch exportError
                fprintf(2,'Partial table export failed; raw phase/checkpoints retained: %s\n',exportError.message);
            end
            rethrow(phaseError);
        end
        tables=dmt_v13_export(phaseCfg,records,runs,phaseDir,phase,false);
        snapshot=struct('cfg',phaseCfg,'records',records,'runs',runs,'tables',tables, ...
            'phase',phase,'meta',meta,'plan',plan);
        save(fullfile(phaseDir,'phase_results.mat'),'-struct','snapshot');
        writeCompletion(phaseDir,tables,phase);
    end
end

function persistTrace(folder,key,cp,meta)
record=cp.record;
names={'feedback_records','tx_profiles','rx_profiles','configuration_ack','validation_probe_records'};
values={struct('sent',record.exchange.feedback_sent,'received',record.exchange.feedback_received), ...
    record.exchange.tx_profiles,record.exchange.rx_profiles,record.exchange.acks,record.probes};
for j=1:numel(names)
    value=meta;value.record_hash=cp.record_hash;value.object=values{j};
    path=fullfile(folder,names{j},[key '.mat']);
    [old,exists]=readCheckpoint(path);
    if exists && strcmp(dmt_v13_hash(old),dmt_v13_hash(value)),continue;end
    if exists,quarantine(path,'Trace differs from verified executed v1.3 record.');end
    dmt_v13_atomic_save(path,value);
end
end

function reference=establishReference(directory,outDir)
reference=struct('available',false,'directory',directory,'reason','reference_not_accessible', ...
    'manifest',table(),'summary',table());
if isempty(directory) || ~isfolder(directory)
    fprintf('Reference0 not accessible; no old statistics guessed or combined with new paths.\n');return;
end
before=dmt_input_manifest(directory);verified=verify_main_results(directory);
after=dmt_input_manifest(directory);assert(isequal(before,after));
reference.available=true;reference.reason='one verified historical calibration, not a new code-path execution';
reference.manifest=before;reference.summary=verified.summary;
path=fullfile(outDir,'reference_input_manifest.csv');
if isfile(path)
    old=readtable(path,'TextType','string');
    assert(isequal(string(old.relative_path),string(before.relative_path)) && ...
        isequal(string(old.sha256),string(before.sha256)) && isequal(old.bytes,before.bytes), ...
        'DMT:V13ReferenceChanged','Original reference bytes differ from saved input manifest.');
else,writetable(before,path);end
writetable(reference.summary,fullfile(outDir,'reference_0_summary.csv'));
end

function writeCompletion(folder,tables,phase)
fid=fopen(fullfile(folder,'completion_check.txt'),'w','n','UTF-8');assert(fid>=0);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'Phase=%s. Complete groups derive from validated saved counters, not requested settings.\n',phase);
status=tables.run_status;
for j=1:height(status)
    r=status(j,:);
    fprintf(fid,'scenario=%s | calibration=%d | scheme=%s | seed=%d | status=%s | symbols=%.0f | reason=%s\n', ...
        char(r.scenario_id),r.calibration_id,char(r.scheme),r.payload_seed, ...
        char(r.status),r.actual_symbols,char(r.reason));
end

fprintf(fid,'Expected/actual row counts: run_status=%d; seed=%d; pooled=%d; summary=%d.\n', ...
    height(status),height(tables.seed),height(tables.pooled),height(tables.summary));
fprintf(fid,'Each completed group hash, ACK/profile, independent stream and counters checked before use.\n');
fprintf(fid,'Only within scenario/calibration/scheme pooling; C/preflight/oldreference excluded from formal BER.\n');
end

function finishInputChecks(root,sourceID,reference,outDir)
[~,current]=dmt_source_manifest(root);
assert(strcmp(sourceID,current),'DMT:V13SourceChanged','Source changed during execution.');
if reference.available
    after=dmt_input_manifest(reference.directory);
    assert(isequal(after,reference.manifest),'DMT:V13ReferenceChanged','Old reference bytes changed.');
    writetable(after,fullfile(outDir,'reference_input_manifest_after.csv'));
end
end

function replacePhaseTables(folder,tables)
path=fullfile(folder,'phase_results.mat');snapshot=load(path);snapshot.tables=tables;
save(path,'-struct','snapshot');
end

function archiveFailure(outDir)
path=fullfile(outDir,'failure_status.txt');
if isfile(path),movefile(path,fullfile(outDir,['previous_failure_' stamp() '.txt']));end
end

function [cp,exists]=readCheckpoint(path)
exists=isfile(path);cp=struct();
if exists
    try,loaded=load(path,'checkpoint');if isfield(loaded,'checkpoint'),cp=loaded.checkpoint;end
    catch ME,fprintf('Unreadable checkpoint retained: %s | %s\n',path,ME.message);end
end
end

function quarantine(path,reason)
backup=[path '.rejected_' stamp() '.mat'];movefile(path,backup);
fprintf('Retained rejected checkpoint %s | %s\n',backup,reason);
end

function value=stamp()
value=char(datetime('now','TimeZone','UTC','Format','yyyyMMdd_HHmmss_SSS'));
end

function value=utcNow()
value=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss.SSS Z'));
end
