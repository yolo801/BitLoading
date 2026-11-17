function result=run_dmt_tradeoff(mode,varargin)
%RUN_DMT_TRADEOFF Power/ADC/rate study with real preflight-before-freeze gate.
% Default all: mechanical checks, independent preflight, freeze, formal.
% Resume only after the original MATLAB process has exited; never launch two.
if nargin<1,mode='all';end
mode=validatestring(mode,{'preflight','formal','all','resume'});
parser=inputParser;
addParameter(parser,'ResultDirectory','',@(x)ischar(x)||(isstring(x)&&isscalar(x)));
parse(parser,varargin{:});root=fileparts(mfilename('fullpath'));cfg=dmt_to_config();
configID=dmt_v13_hash(cfg);[manifest,sourceID]=dmt_source_manifest(root);
outDir=char(parser.Results.ResultDirectory);
if isempty(outDir)
    assert(~any(strcmp(mode,{'formal','resume'})),'DMT:TradeoffDirectory', ...
        'formal/resume requires the existing tradeoff ResultDirectory.');
    parent=fullfile(root,'results');if ~isfolder(parent),mkdir(parent);end
    [~,unique]=fileparts(tempname(parent));
    outDir=fullfile(parent,['tradeoff_v1_' stamp() '_' unique]);
end
file=java.io.File(outDir);outDir=char(file.getCanonicalPath());
statePath=fullfile(outDir,'study_state.mat');fresh=~isfile(statePath);
if fresh
    assert(~any(strcmp(mode,{'formal','resume'})),'DMT:TradeoffNoPreflight', ...
        'No frozen tradeoff study exists here; run all or preflight in a new directory.');
    assertSafeNewDirectory(outDir);
    if ~isfolder(outDir),mkdir(outDir);end
else
    % Reject old protocols/mismatched sources before any lock, diary or write.
    existing=load(statePath,'checkpoint');candidate=existing.checkpoint;
    required={'cfg','config_id','source_id','source_manifest','formal_plan','preflight_plan'};
    assert(isstruct(candidate) && all(isfield(candidate,required)) && ...
        isfield(candidate.cfg,'protocol') && strcmp(candidate.cfg.protocol,cfg.protocol) && ...
        strcmp(candidate.config_id,configID) && strcmp(candidate.source_id,sourceID) && ...
        isequaln(candidate.source_manifest,manifest) && ...
        isequaln(candidate.formal_plan,dmt_to_plan(cfg,'formal')) && ...
        isequaln(candidate.preflight_plan,dmt_to_plan(cfg,'preflight')), ...
        'DMT:TradeoffReadOnlyRejection', ...
        'This is not the same tradeoff protocol/source. Original directory was not modified.');
    checkEnvironment(candidate.environment);
end
lock=dmt_study_lock(outDir); %#ok<NASGU>
diary(fullfile(outDir,'run.log'));cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('\n%s | TRADEOFF TRAVERSAL BEGIN | mode=%s | %s\n',nowText(),mode,outDir);
fprintf('Command: run_dmt_tradeoff(''%s'',''ResultDirectory'',''%s'')\n', ...
    mode,strrep(outDir,'''',''''''));
try
    if fresh
        state=struct('cfg',cfg,'config_id',configID,'source_id',sourceID, ...
            'source_manifest',manifest,'formal_plan',dmt_to_plan(cfg,'formal'), ...
            'preflight_plan',dmt_to_plan(cfg,'preflight'),'created_utc',nowText(), ...
            'environment',dmt_to_runtime(root));
        seeds=[state.formal_plan.data_seed;state.formal_plan.noise_seed; ...
            state.preflight_plan.data_seed;state.preflight_plan.noise_seed];seeds=seeds(isfinite(seeds));
        assert(numel(seeds)==numel(unique(seeds)) && all(seeds<cfg.seed_base.diagnostic));
        dmt_v13_atomic_save(statePath,state);
        writetable(manifest,fullfile(outDir,'source_manifest.csv'));
        writetable(state.formal_plan,fullfile(outDir,'seed_plan_formal.csv'));
        writetable(state.preflight_plan,fullfile(outDir,'seed_plan_preflight.csv'));
        saveSource(root,outDir,manifest);
        dmt_v13_atomic_save(fullfile(outDir,'environment.mat'),state.environment);
        fid=fopen(fullfile(outDir,'environment.txt'),'w','n','UTF-8');assert(fid>=0);
        fprintf(fid,'MATLAB %s\nRoot: %s\nWorking directory: %s\n%s\n', ...
            version,matlabroot,pwd,evalc('ver'));
        for j=1:numel(state.environment.resolved_functions)
            item=state.environment.resolved_functions(j);
            fprintf(fid,'Resolved %s: %s\n',item.name,item.first);
        end
        fclose(fid);
        copyfile(fullfile(root,'TRADEOFF_START_HERE.md'),fullfile(outDir,'README.md'));
    else
        loaded=load(statePath,'checkpoint');state=loaded.checkpoint;
        assert(strcmp(state.config_id,configID) && strcmp(state.source_id,sourceID) && ...
            strcmp(state.config_id,dmt_v13_hash(state.cfg)) && isequaln(state.source_manifest,manifest) && ...
            isequaln(state.formal_plan,dmt_to_plan(cfg,'formal')) && ...
            isequaln(state.preflight_plan,dmt_to_plan(cfg,'preflight')), ...
            'DMT:TradeoffResumeIdentity','Source/config/plan changed. Retain old results and start a new protocol directory.');
    end
    assert(~isempty(which('qammod')) && ~isempty(which('qamdemod')) && ~isempty(ver('comm')), ...
        'DMT:TradeoffToolbox','Communications Toolbox with qammod/qamdemod is required.');
    mechanical=mechanicalGate(cfg,state,outDir);
    if strcmp(mode,'formal')
        assert(isfile(fullfile(outDir,'Protocol.mat')),'DMT:TradeoffNotFrozen', ...
            'formal requires the completed independently checked preflight and frozen Protocol.');
    elseif ~isfile(fullfile(outDir,'Protocol.mat'))
        pre=executePhase('preflight');
        assert(pre.scope_resolved,'DMT:TradeoffPreflightIncomplete','Preflight scope is unresolved.');
        if pre.accepted_designs==0
            % Scientific rejection is not a mechanical failure. Diagnose an
            % all-rejected matrix by replaying fixed mechanical inputs and
            % independently rechecking every saved design, without tuning.
            mechanical=investigateRejections(cfg,state,outDir);
        end
        freezeProtocol(state,mechanical,outDir);
    end
    protocol=checkProtocol(state,outDir,mechanical);
    if strcmp(mode,'preflight')
        result=struct('output_dir',outDir,'phase','preflight','protocol_frozen',true, ...
            'formal_executed_by_this_call',false,'preflight',protocol.preflight_completion);
        archiveFailure(outDir);
        fprintf('%s | TRADEOFF PREFLIGHT FINISHED | formal payload executed by this call=0\n',nowText());return;
    end
    complete=executePhase('formal');
    assert(complete.scope_resolved,'DMT:TradeoffIncomplete','Formal planned scope remains incomplete.');
    currentSource(root,sourceID);
    result=struct('output_dir',outDir,'phase','formal','protocol_frozen',true,'completion',complete, ...
        'config_id',state.config_id,'source_id',state.source_id,'protocol_hash',dmt_v13_hash(protocol), ...
        'status','formal_scope_resolved_not_necessarily_scientifically_supported');
    dmt_v13_atomic_save(fullfile(outDir,'final_result.mat'),result);archiveFailure(outDir);
    fprintf('%s | TRADEOFF FORMAL FINISHED | completed=%d rejected=%d incomplete=%d planned=%d\n', ...
        nowText(),complete.completed_payload_slots,complete.design_rejected_payload_slots, ...
        complete.incomplete_payload_slots,complete.planned_payload_slots);
    diary('off');diary(fullfile(outDir,'run.log')); % Flush the real end record before read-only audit.
    % Independent audit recomputes from complete checkpoints and exported CSV.
    checked=verify_dmt_tradeoff(outDir);
    assert(checked.valid,'DMT:TradeoffFinalVerification','Counts saved, but independent completion/export verification did not pass.');
    result.verification=checked;
catch ME
    fid=fopen(fullfile(outDir,'failure_status.txt'),'w','n','UTF-8');
    if fid>=0,fprintf(fid,'INCOMPLETE traversal; valid checkpoint units retained.\n%s\n', ...
            getReport(ME,'extended','hyperlinks','off'));fclose(fid);end
    fprintf(2,'Tradeoff traversal stopped; original directory/log retained: %s\n%s\n',outDir,ME.message);
    rethrow(ME);
end

    function completion=executePhase(phase)
        phaseTimer=tic;
        folder=fullfile(outDir,phase);if ~isfolder(folder),mkdir(folder);end
        for f={'shared','designs','payload'}
            if ~isfolder(fullfile(folder,f{1})),mkdir(fullfile(folder,f{1}));end
        end
        plan=state.([phase '_plan']);meta=dmt_to_meta(state,phase);
        writetable(plan,fullfile(folder,'seed_plan.csv'));
        [shared,designs,runs]=dmt_to_collect(outDir,phase,cfg,meta,plan);
        nc=cfg.calibration_count;nSymbols=cfg.payload_symbols;
        if strcmp(phase,'preflight'),nc=1;nSymbols=cfg.preflight_payload_symbols;end
        ns=numel(cfg.scheme_names);conditions=dmt_to_conditions(cfg);
        try
            for condition=conditions
                for c=1:nc
                    a=(condition.condition_id-1)*nc+c;
                    if isempty(shared{a})
                        fprintf('%s | %s P=%.3g q=%d cal=%d | independent initial power/A0/B0\n', ...
                            nowText(),phase,condition.P_target,condition.q,c);
                        data=dmt_to_initial(cfg,condition,c,plan);
                        validate('Shared',data,condition,c,'',NaN);
                        key=sprintf('shared_c%02d_cal%02d',condition.condition_id,c);
                        shared{a}=dmt_to_checkpoint('write',fullfile(folder,'shared',[key '.mat']), ...
                            'Shared',key,meta,data);
                    end
                    for s=1:ns
                        b=(a-1)*ns+s;scheme=cfg.scheme_names{s};
                        if isempty(designs{b})
                            fprintf('%s | %s P=%.3g q=%d cal=%d scheme=%s | design\n', ...
                                nowText(),phase,condition.P_target,condition.q,c,scheme);
                            immutable=dmt_v13_hash(shared{a});
                            data=dmt_to_design(cfg,condition,c,scheme,shared{a},plan);
                            assert(strcmp(immutable,dmt_v13_hash(shared{a})) && strcmp(immutable,data.initial_shared_hash) && ...
                                isequaln(data.initial_gamma_B,shared{a}.gamma_B));
                            validate('Design',data,condition,c,scheme,NaN);
                            key=sprintf('design_c%02d_cal%02d_s%02d',condition.condition_id,c,s);
                            designs{b}=dmt_to_checkpoint('write',fullfile(folder,'designs',[key '.mat']), ...
                                'Design',key,meta,data);
                        end
                        if ~strcmp(designs{b}.status,'accepted')
                            fprintf('DESIGN REJECTED | %s c=%d cal=%d %s | %s\n', ...
                                phase,condition.condition_id,c,scheme,designs{b}.status);continue;
                        end
                        for j=1:cfg.payload_repeats
                            index=(b-1)*cfg.payload_repeats+j;if ~isempty(runs{index}),continue;end
                            seeds=dmt_to_seed(plan,condition.condition_id,c,scheme,0,'payload',j);
                            data=dmt_to_payload(cfg,condition,designs{b},seeds,nSymbols);
                            data.condition=condition;data.calibration_id=c;data.scheme=scheme;
                            data.payload_slot=j;data.phase=phase;data.design_hash=dmt_v13_hash(designs{b});
                            validate('Payload',data,condition,c,scheme,j);
                            key=sprintf('payload_c%02d_cal%02d_s%02d_j%02d',condition.condition_id,c,s,j);
                            runs{index}=dmt_to_checkpoint('write',fullfile(folder,'payload',[key '.mat']), ...
                                'Payload',key,meta,data);
                            fprintf('%s | %s c=%d cal=%d %s j=%d | actual symbols=%d power_match=%d\n', ...
                                nowText(),phase,condition.condition_id,c,scheme,j,data.symbols,data.power_match);
                        end
                    end
                end
                snapshot(false); % Bounded progress exports, never performance feedback.
            end
        catch phaseError
            try,snapshot(false);catch exportError,fprintf(2,'Partial export error; raw checkpoints retained: %s\n',exportError.message);end
            rethrow(phaseError);
        end
        currentSource(root,sourceID);snapshot(true);
        resources=struct('phase',phase,'wall_seconds',toc(phaseTimer),'memory_query_available',false, ...
            'memory_query_error','','memory_at_phase_end',struct());
        try
            [userMemory,systemMemory]=memory;
            resources.memory_query_available=true;
            resources.memory_at_phase_end=struct('MATLAB',userMemory,'system',systemMemory);
        catch memoryError
            resources.memory_query_error=memoryError.message;
        end
        resources.note='Observed end-of-phase memory only, not measured peak. Wall time includes I/O/plots; component compute timers exclude them.';
        dmt_v13_atomic_save(fullfile(folder,'resource_observation.mat'),resources);
        fprintf('%s | TRADEOFF PHASE FINISHED | phase=%s | completed=%d rejected=%d planned=%d\n', ...
            nowText(),phase,completion.completed_payload_slots,completion.design_rejected_payload_slots,completion.planned_payload_slots);

        function snapshot(render)
            completion=dmt_to_completion(cfg,phase,shared,designs,runs);
            tables=dmt_to_tables(cfg,phase,plan,shared,designs,runs);
            dmt_to_export(cfg,tables,folder,phase);
            save(fullfile(folder,'phase_results.mat'),'cfg','phase','plan','meta','shared','designs','runs','tables','completion');
            fid=fopen(fullfile(folder,'completion_check.txt'),'w','n','UTF-8');assert(fid>=0);
            fprintf(fid,'%s\n',jsonencode(completion,'PrettyPrint',true));fclose(fid);
            if render,dmt_to_plot(cfg,tables,folder);end
        end
    end

    function validate(kind,data,condition,c,scheme,slot)
        [ok,reason]=dmt_to_validate(kind,data,cfg,condition,c,scheme,slot,metaFor(kind,data),planFor(data));
        if ~ok
            diagnosticDir=fullfile(outDir,char(data.phase),'invalid_new_records');
            if ~isfolder(diagnosticDir),mkdir(diagnosticDir);end
            invalid=struct('state','invalid_not_completed_not_resumable','kind',kind, ...
                'reason',reason,'config_id',state.config_id,'source_id',state.source_id,'raw_data',data);
            [~,tag]=fileparts(tempname(diagnosticDir));
            dmt_v13_atomic_save(fullfile(diagnosticDir,[kind '_' tag '.mat']),invalid);
            error('DMT:TradeoffRecord','%s: %s. Raw rejected record retained in %s',kind,reason,diagnosticDir);
        end
    end
    function phase=metaFor(~,data)
        phase=char(data.phase);
    end
    function plan=planFor(data)
        plan=state.([char(data.phase) '_plan']);
    end
end

function report=mechanicalGate(cfg,state,folder)
path=fullfile(folder,'mechanical_checks.mat');bound=fullfile(folder,'mechanical_identity.mat');
if isfile(path) && isfile(bound)
    saved=load(path,'report');identity=load(bound,'checkpoint');report=saved.report;value=identity.checkpoint;
    assert(report.passed && all(report.checks.passed) && strcmp(report.config_id,state.config_id) && ...
        strcmp(value.report_hash,dmt_v13_hash(report)) && ...
        strcmp(value.config_id,state.config_id) && strcmp(value.source_id,state.source_id), ...
        'DMT:TradeoffMechanicalIdentity','Mechanical check identity differs.');return;
end
fprintf('Mechanical diagnostic namespace; reruns are explicit replay, never formal samples.\n');
report=dmt_to_checks(cfg,folder);assert(report.passed);
value=struct('config_id',state.config_id,'source_id',state.source_id,'report_hash',dmt_v13_hash(report));
dmt_v13_atomic_save(bound,value);
end

function freezeProtocol(state,mechanical,folder)
cfg=state.cfg;phase='preflight';plan=state.preflight_plan;meta=dmt_to_meta(state,phase);
[shared,designs,runs]=dmt_to_collect(folder,phase,cfg,meta,plan);
counts=dmt_to_completion(cfg,phase,shared,designs,runs);
assert(mechanical.passed && counts.scope_resolved);
protocol=struct('name',cfg.protocol,'frozen',true,'config_id',state.config_id, ...
    'source_id',state.source_id,'preflight_seed_id',meta.seed_id, ...
    'formal_seed_id',dmt_v13_hash(state.formal_plan),'mechanical_hash',dmt_v13_hash(mechanical), ...
    'preflight_data_hash',dmt_v13_hash({shared,designs,runs}), ...
    'preflight_completion',counts,'cfg',cfg,'frozen_utc',nowText(), ...
    'rule','Real mechanical checks and all planned independent preflight cases resolved before formal.');
dmt_v13_atomic_save(fullfile(folder,'Protocol.mat'),protocol);
fid=fopen(fullfile(folder,'Protocol.json'),'w','n','UTF-8');assert(fid>=0);
fprintf(fid,'%s\n',jsonencode(protocol,'PrettyPrint',true));fclose(fid);
fprintf('%s | TRADEOFF PROTOCOL FROZEN | independent formal streams are now eligible\n',nowText());
end

function protocol=checkProtocol(state,folder,mechanical)
saved=load(fullfile(folder,'Protocol.mat'),'checkpoint');protocol=saved.checkpoint;
phase='preflight';meta=dmt_to_meta(state,phase);
[shared,designs,runs]=dmt_to_collect(folder,phase,state.cfg,meta,state.preflight_plan);
counts=dmt_to_completion(state.cfg,phase,shared,designs,runs);
assert(protocol.frozen && strcmp(protocol.name,state.cfg.protocol) && isequaln(protocol.cfg,state.cfg) && ...
    isequaln(protocol.preflight_completion,counts) && ...
    strcmp(protocol.config_id,state.config_id) && ...
    strcmp(protocol.source_id,state.source_id) && strcmp(protocol.preflight_seed_id,meta.seed_id) && ...
    strcmp(protocol.formal_seed_id,dmt_v13_hash(state.formal_plan)) && ...
    strcmp(protocol.mechanical_hash,dmt_v13_hash(mechanical)) && ...
    strcmp(protocol.preflight_data_hash,dmt_v13_hash({shared,designs,runs})) && counts.scope_resolved, ...
    'DMT:TradeoffProtocolIdentity','Frozen protocol or actual verified preflight changed.');
path=fullfile(folder,'Protocol.json');
if ~isfile(path)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(protocol,'PrettyPrint',true));fclose(fid);
else
    document=jsondecode(fileread(path));
    assert(isequaln(document,jsondecode(jsonencode(protocol))), ...
        'DMT:TradeoffProtocolDocument','Protocol.json differs from its original MAT identity.');
end
end

function report=investigateRejections(cfg,state,folder)
fprintf('All preflight designs rejected: fixed diagnostic replay and saved-record audit, no parameter/seed changes.\n');
for ext={'mat','csv','txt'}
    old=fullfile(folder,['mechanical_checks.' ext{1}]);
    if isfile(old),copyfile(old,fullfile(folder,['mechanical_checks_before_investigation.' ext{1}]));end
end
report=dmt_to_checks(cfg,folder);assert(report.passed && all(report.checks.passed));
identity=struct('config_id',state.config_id,'source_id',state.source_id,'report_hash',dmt_v13_hash(report));
dmt_v13_atomic_save(fullfile(folder,'mechanical_identity.mat'),identity);
meta=dmt_to_meta(state,'preflight');
[shared,designs,runs]=dmt_to_collect(folder,'preflight',cfg,meta,state.preflight_plan);
counts=dmt_to_completion(cfg,'preflight',shared,designs,runs);assert(counts.scope_resolved);
fid=fopen(fullfile(folder,'preflight_investigation.txt'),'w','n','UTF-8');assert(fid>=0);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'All preflight design cases rejected; retained as scientific observations, not global physical infeasibility.\n');
fprintf(fid,'Fixed mechanical diagnostic input replay passed. Every saved shared/design checkpoint was independently revalidated.\n');
fprintf(fid,'No physical parameter, noise, ADC range, candidate rule, sample budget or experiment seed was changed.\n');
fprintf(fid,'Proceeding with the predeclared formal matrix. Zero acceptance is not a performance gate.\n');
for j=1:numel(designs)
    d=designs{j};fprintf(fid,'condition=%d cal=%d scheme=%s state=%s rounds=%d\n', ...
        d.condition.condition_id,d.calibration_id,d.scheme,d.status,numel(d.rounds));
end
end

function saveSource(root,folder,manifest)
for j=1:height(manifest)
    relative=char(manifest.relative_path(j));target=fullfile(folder,'source_snapshot',relative);
    parent=fileparts(target);if ~isfolder(parent),mkdir(parent);end
    copyfile(fullfile(root,relative),target);
end
end

function currentSource(root,expected)
[~,observed]=dmt_source_manifest(root);
assert(strcmp(observed,expected),'DMT:TradeoffSourceChanged','Source changed during traversal; start a new protocol.');
end

function checkEnvironment(previous)
current=ver('comm');saved=previous.toolboxes;
selected=strcmp({saved.Name},'Communications Toolbox');saved=saved(selected);
assert(strcmp(previous.version,version) && strcmp(previous.release,version('-release')) && ...
    strcmp(previous.computer,computer) && ...
    numel(saved)==numel(current) && isequal({saved.Version},{current.Version}), ...
    'DMT:TradeoffRuntimeChanged','MATLAB or Communications Toolbox changed; start a new protocol directory.');
end

function assertSafeNewDirectory(folder)
if isfolder(folder)
    contents=dir(folder);contents=contents(~ismember({contents.name},{'.','..'}));
    assert(isempty(contents),'DMT:TradeoffNonempty','A new study requires an empty unique directory.');
end
parent=fileparts(folder);
while ~isempty(parent)
    forbidden={'config_snapshot.mat','final_results.mat','initialization.mat','study_state.mat','import_manifest.csv'};
    for j=1:numel(forbidden)
        assert(~isfile(fullfile(parent,forbidden{j})),'DMT:TradeoffHistoricalDirectory', ...
            'New output cannot be nested inside historical experiment data.');
    end
    next=fileparts(parent);if strcmp(parent,next),break;end;parent=next;
end
end

function archiveFailure(folder)
path=fullfile(folder,'failure_status.txt');
if isfile(path),movefile(path,fullfile(folder,['previous_failure_' stamp() '.txt']));end
end
function text=stamp()
text=char(datetime('now','TimeZone','UTC','Format','yyyyMMdd_HHmmss_SSS'));
end
function text=nowText()
text=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss.SSS Z'));
end
