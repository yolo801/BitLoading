function report=verify_dmt_tradeoff(resultDirectory,varargin)
%VERIFY_DMT_TRADEOFF Independent read-only reconstruction of saved counters.
% Science failure/power mismatch is distinct from mechanical integrity.
% WriteReport=false performs no filesystem writes (used by read-only redraw).
parser=inputParser;
addParameter(parser,'WriteReport',true,@(x)islogical(x)&&isscalar(x));
addParameter(parser,'Phase','formal',@(x)ischar(x)||(isstring(x)&&isscalar(x)));
parse(parser,varargin{:});phase=validatestring(char(parser.Results.Phase),{'preflight','formal'});
folder=char(resultDirectory);root=fileparts(mfilename('fullpath'));
report=struct('protocol','tradeoff_v1','phase',phase,'result_directory',folder, ...
    'checked_utc',utcNow(),'data_integrity_valid',false,'exports_integrity_valid',false, ...
    'protocol_frozen_valid',false,'scope_resolved',false,'all_payloads_completed',false, ...
    'valid',false,'errors',{{}},'report_directory','','completion',struct());
recognized=false;rawError='';exportError='';tables=[];rawReady=false;frozenEvidence=false;
try
    saved=load(fullfile(folder,'study_state.mat'),'checkpoint');state=saved.checkpoint;cfg=state.cfg;
    check(isfield(cfg,'protocol') && strcmp(cfg.protocol,'tradeoff_v1'), ...
        'This is not a tradeoff_v1 directory.');recognized=true;
    check(strcmp(state.config_id,dmt_v13_hash(cfg)) && isequaln(cfg,dmt_to_config()), ...
        'Frozen scientific configuration differs from this implementation.');
    [currentManifest,currentID]=dmt_source_manifest(root);
    check(strcmp(currentID,state.source_id) && isequaln(currentManifest,state.source_manifest), ...
        'Use the original source snapshot/package to verify this study; installed source differs.');
    manifest=readtable(fullfile(folder,'source_manifest.csv'),'TextType','string');
    compareTable(manifest,state.source_manifest,'source_manifest.csv');
    for j=1:height(manifest)
        path=fullfile(folder,'source_snapshot',char(manifest.relative_path(j)));
        fid=fopen(path,'rb');check(fid>=0,['Missing source snapshot ' path]);
        cleanup=onCleanup(@()fclose(fid));bytes=fread(fid,Inf,'*uint8');clear cleanup;
        check(numel(bytes)==manifest.bytes(j) && ...
            strcmp(dmt_sha256(bytes),char(manifest.sha256(j))),'Snapshot bytes differ from original source manifest.');
    end
    check(isequaln(state.formal_plan,dmt_to_plan(cfg,'formal')) && ...
        isequaln(state.preflight_plan,dmt_to_plan(cfg,'preflight')),'Original role/seed plans differ.');
    compareTable(readtable(fullfile(folder,'seed_plan_formal.csv'),'TextType','string'), ...
        state.formal_plan,'formal role/seed CSV');
    compareTable(readtable(fullfile(folder,'seed_plan_preflight.csv'),'TextType','string'), ...
        state.preflight_plan,'preflight role/seed CSV');
    seeds=[state.formal_plan.data_seed;state.formal_plan.noise_seed; ...
        state.preflight_plan.data_seed;state.preflight_plan.noise_seed];seeds=seeds(isfinite(seeds));
    check(numel(seeds)==numel(unique(seeds)) && all(seeds<cfg.seed_base.diagnostic), ...
        'Role streams overlap or enter the mechanical namespace.');
    plan=state.([phase '_plan']);meta=dmt_to_meta(state,phase);
    [shared,designs,runs]=dmt_to_collect(folder,phase,cfg,meta,plan);
    completion=dmt_to_completion(cfg,phase,shared,designs,runs);
    tables=dmt_to_tables(cfg,phase,plan,shared,designs,runs);
    check(tables.completed_groups==completion.completed_payload_slots && ...
        tables.rejected_groups==completion.design_rejected_payload_slots && ...
        tables.incomplete_groups==completion.incomplete_payload_slots && ...
        tables.planned_groups==completion.planned_payload_slots,'Independent actual/planned counts disagree.');
    auditPooling(cfg,tables,phase);
    rawReady=true;
    report.completion=completion;report.scope_resolved=completion.scope_resolved;
    report.all_payloads_completed=completion.all_payloads_completed;
    report.config_id=state.config_id;report.source_id=state.source_id;report.seed_id=meta.seed_id;
    report.raw_seed_rows=height(tables.seed);report.raw_pooled_rows=height(tables.pooled);
    report.BER_supported_cases=sum(tables.summary.BER_state=="supported");
    report.power_mismatch_slots=completion.power_mismatch_payload_slots;
    report.data_integrity_valid=true;

    % Freeze proof is separate from valid but incomplete/rejected raw data.
    if isfile(fullfile(folder,'Protocol.mat'))
        frozen=load(fullfile(folder,'Protocol.mat'),'checkpoint');protocol=frozen.checkpoint;
        mechanical=load(fullfile(folder,'mechanical_checks.mat'),'report');mechanical=mechanical.report;
        binding=load(fullfile(folder,'mechanical_identity.mat'),'checkpoint');binding=binding.checkpoint;
        check(mechanical.passed && ~isempty(mechanical.checks) && all(mechanical.checks.passed) && ...
            strcmp(mechanical.config_id,state.config_id) && mechanical.formal_payload_symbols_executed==0 && ...
            strcmp(binding.report_hash,dmt_v13_hash(mechanical)) && ...
            strcmp(binding.config_id,state.config_id) && strcmp(binding.source_id,state.source_id), ...
            'Actual mechanical report or its source/config binding is invalid.');
        preMeta=dmt_to_meta(state,'preflight');
        [ps,pd,pr]=dmt_to_collect(folder,'preflight',cfg,preMeta,state.preflight_plan);
        pc=dmt_to_completion(cfg,'preflight',ps,pd,pr);
        check(protocol.frozen && strcmp(protocol.name,cfg.protocol) && isequaln(protocol.cfg,cfg) && ...
            strcmp(protocol.config_id,state.config_id) && strcmp(protocol.source_id,state.source_id) && ...
            strcmp(protocol.formal_seed_id,dmt_v13_hash(state.formal_plan)) && ...
            strcmp(protocol.preflight_seed_id,dmt_v13_hash(state.preflight_plan)) && ...
            strcmp(protocol.mechanical_hash,dmt_v13_hash(mechanical)) && ...
            strcmp(protocol.preflight_data_hash,dmt_v13_hash({ps,pd,pr})) && ...
            isequaln(protocol.preflight_completion,pc) && pc.scope_resolved, ...
            'Protocol is not bound to the complete, actual independent preflight.');
        frozenEvidence=true;
        document=jsondecode(fileread(fullfile(folder,'Protocol.json')));
        check(isequaln(document,jsondecode(jsonencode(protocol))), ...
            'Human-readable Protocol.json differs from the frozen MAT identity.');
        report.protocol_frozen_valid=true;
    end
    if strcmp(phase,'formal') && any(~cellfun(@isempty,runs))
        check(report.protocol_frozen_valid,'Formal payload exists without actual verified preflight/protocol.');
    end
catch ME
    rawError=ME.message;report.errors{end+1}=rawError;
    % A failed freeze proof must not prevent inspection/redraw of preflight
    % counters; actual formal transmission still requires a valid protocol.
    if rawReady && (strcmp(phase,'preflight') || frozenEvidence)
        report.data_integrity_valid=true;
    else
        report.data_integrity_valid=false;
    end
end

if report.data_integrity_valid
    try
        phaseDir=fullfile(folder,phase);snapshot=load(fullfile(phaseDir,'phase_results.mat'));
        check(isequaln(snapshot.cfg,cfg) && strcmp(snapshot.phase,phase) && ...
            isequaln(snapshot.plan,plan) && isequaln(snapshot.meta,meta) && ...
            isequaln(snapshot.shared,shared) && isequaln(snapshot.designs,designs) && ...
            isequaln(snapshot.runs,runs) && isequaln(snapshot.tables,tables) && ...
            isequaln(snapshot.completion,completion),'Phase MAT does not equal raw-checkpoint reconstruction.');
        compareTable(readtable(fullfile(phaseDir,'seed_plan.csv'),'TextType','string'),plan,'Phase seed plan');
        mapping=dmt_to_output_files();
        for j=1:size(mapping,1)
            observed=readtable(fullfile(phaseDir,mapping{j,2}),'TextType','string');
            compareTable(observed,tables.(mapping{j,1}),mapping{j,2});
        end
        writtenCompletion=jsondecode(fileread(fullfile(phaseDir,'completion_check.txt')));
        check(isequaln(writtenCompletion,completion),'Completion document differs from actual counts.');
        nonempty(fullfile(phaseDir,'field_dictionary.csv'));nonempty(fullfile(phaseDir,'field_dictionary.md'));
        nonempty(fullfile(phaseDir,'report_notes_zh.md'));
        figures=readtable(fullfile(phaseDir,'figure_manifest.csv'),'TextType','string');
        check(ismember('data_hash',figures.Properties.VariableNames) && ...
            all(string(figures.data_hash)==string(dmt_v13_hash(tables))), ...
            'Figure manifest belongs to a different set of actual tables.');
        expected=["rate_vs_actual_power";"required_tested_power";"nominal_vs_cycle_rate"; ...
            "BER_vs_actual_power";"representative_loading_BER"];
        check(isequal(sort(string(figures.figure)),sort(expected)),'Figure manifest misses a declared plot or duplicates it.');
        for j=1:height(figures)
            status=char(figures.status(j));
            check(any(strcmp(status,{'written','not_available'})),'Plot export failed or has an unknown state.');
            if strcmp(status,'written')
                for ext={'png','pdf','svg','fig'}
                    nonempty(fullfile(phaseDir,[char(figures.figure(j)) '.' ext{1}]));
                end
            else
                check(~ismissing(figures.reason(j)) && strlength(figures.reason(j))>0, ...
                    'Unavailable scientific plot must explain its actual missing evidence.');
            end
        end
        if completion.scope_resolved && strcmp(phase,'formal')
            savedFinal=load(fullfile(folder,'final_result.mat'),'checkpoint');final=savedFinal.checkpoint;
            check(isequaln(final.completion,completion) && strcmp(final.phase,'formal') && final.protocol_frozen && ...
                strcmp(final.config_id,state.config_id) && strcmp(final.source_id,state.source_id) && ...
                strcmp(final.protocol_hash,dmt_v13_hash(protocol)), ...
                'Root final result is inconsistent with actual counters.');
            log=fileread(fullfile(folder,'run.log'));
            marker=sprintf('TRADEOFF FORMAL FINISHED | completed=%d rejected=%d incomplete=%d planned=%d', ...
                completion.completed_payload_slots,completion.design_rejected_payload_slots, ...
                completion.incomplete_payload_slots,completion.planned_payload_slots);
            check(contains(log,marker),'No actual formal end-of-traversal count record.');
        end
        report.exports_integrity_valid=true;
    catch ME
        exportError=ME.message;report.errors{end+1}=exportError;
    end
end
failure=isfile(fullfile(folder,'failure_status.txt'));
report.unresolved_traversal_failure=failure;
report.valid=report.data_integrity_valid && report.exports_integrity_valid && ...
    report.protocol_frozen_valid && report.scope_resolved && ~failure && isempty(rawError) && isempty(exportError);
if parser.Results.WriteReport && recognized
    [~,unique]=fileparts(tempname(folder));
    auditDir=fullfile(folder,'verification_reports',[stamp() '_' unique]);mkdir(auditDir);
    report.report_directory=auditDir;
    save(fullfile(auditDir,'verification_report.mat'),'report','tables');
    fid=fopen(fullfile(auditDir,'verification_report.json'),'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));fclose(fid);
    fid=fopen(fullfile(auditDir,'verification_report.txt'),'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'Data integrity=%d; export integrity=%d; protocol=%d; scope resolved=%d; valid=%d\n', ...
        report.data_integrity_valid,report.exports_integrity_valid,report.protocol_frozen_valid,report.scope_resolved,report.valid);
    fprintf(fid,'Science BER/power failure is not an integrity error. No symbols were transmitted by this verifier.\n');
    fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));fclose(fid);
end
fprintf('Tradeoff audit | %s | data=%d exports=%d frozen=%d resolved=%d valid=%d\n', ...
    phase,report.data_integrity_valid,report.exports_integrity_valid,report.protocol_frozen_valid,report.scope_resolved,report.valid);
end

function auditPooling(cfg,tables,phase)
seed=tables.seed;pool=tables.pooled;L=cfg.payload_symbols;
if strcmp(phase,'preflight'),L=cfg.preflight_payload_symbols;end
check(height(seed)==numel(cfg.k)*tables.completed_groups,'Seed row count does not derive from actual complete groups.');
for j=1:height(pool)
    p=pool(j,:);mask=seed.condition_id==p.condition_id & seed.calibration_id==p.calibration_id & ...
        seed.scheme==p.scheme & seed.k==p.k;part=seed(mask,:);
    check(height(part)==cfg.payload_repeats && numel(unique(part.payload_slot))==cfg.payload_repeats, ...
        'Pooled row lacks exactly the declared independent payload repeats.');
    check(all(part.tested_bits==L*log2(p.M)) && sum(part.error_bits)==p.error_bits && ...
        sum(part.tested_bits)==p.tested_bits,'Pooled counts do not exactly sum raw payload records.');
    near(p.BER,p.error_bits/p.tested_bits,'Pooled BER is not total errors/total bits.');
    [low,high]=wilsonIndependent(p.error_bits,p.tested_bits,cfg.Wilson_z);
    near([p.CI_low p.CI_high],[low high],'Pooled Wilson endpoints differ.');
end
for j=1:height(tables.summary)
    s=tables.summary(j,:);if s.payload_state~="completed",continue;end
    p=pool(pool.condition_id==s.condition_id & pool.calibration_id==s.calibration_id & pool.scheme==s.scheme,:);
    check(height(p)==numel(cfg.k) && sum(p.tested_bits)==s.total_tested_bits && ...
        sum(p.error_bits)==s.total_error_bits,'Summary counter totals double count or omit data.');
    near(s.overall_BER,sum(p.error_bits)/sum(p.tested_bits),'Overall BER must be a bit-weighted ratio.');
    state="inconclusive";if any(p.CI_low>cfg.targetBER),state="failed";
    elseif all(p.CI_high<cfg.targetBER),state="supported";end
    check(s.BER_state==state,'Formal statistical state differs from strict pointwise rule.');
    expectedRate=L*s.B_DMT/((s.setup_link_symbols+L)*cfg.Ts+cfg.control_delay);
    near(s.R_cycle,expectedRate,'R_cycle incorrectly combines repeats or omits setup.');
end
end

function [lo,hi]=wilsonIndependent(e,n,z)
p=e/n;d=1+z*z/n;c=(p+z*z/(2*n))/d;r=z*sqrt(p*(1-p)/n+z*z/(4*n*n))/d;
lo=max(0,c-r);hi=min(1,c+r);
end
function compareTable(observed,expected,name)
check(istable(observed) && istable(expected) && ...
    isequal(observed.Properties.VariableNames,expected.Properties.VariableNames) && ...
    height(observed)==height(expected),['Table dimensions/fields differ: ' name]);
for j=1:width(expected)
    a=observed.(j);b=expected.(j);
    if isnumeric(b) || islogical(b)
        if isstring(a) || iscellstr(a) %#ok<ISCLSTR>
            a=string(a);a(a=="true")="1";a(a=="false")="0";a=str2double(a);
        end
        check(isequal(size(a),size(b)),['Column shape differs: ' name]);
        a=double(a);b=double(b);mask=isfinite(b);
        check(all(isnan(a(isnan(b)))) && all(a(isinf(b))==b(isinf(b))),['Missing/infinite numeric values differ: ' name]);
        field=expected.Properties.VariableNames{j};
        integerNames={'condition_id','calibration_id','q','payload_slot','k','M','bits_k','B_DMT', ...
            'tested_bits','error_bits','round','iterations','sample_count','data_seed','noise_seed', ...
            'power_data_seed','A_data_seed','A_noise_seed','D_data_seed','D_noise_seed'};
        integerColumn=any(strcmp(field,integerNames)) || ...
            ~isempty(regexp(field,'(_count|_entries|_scalars|_symbols|_rounds|_calibrations|_groups|_slots)$','once'));
        if integerColumn
            % Actual integer counters/identities remain exact through CSV.
            check(all(a(mask)==b(mask)),['Integer counter/identity differs: ' name]);
        else
            check(all(abs(a(mask)-b(mask))<=1e-11*max(1,abs(b(mask)))),['Numeric value differs: ' name]);
        end
    else
        if isnumeric(a)
            absent=isnan(a);a=string(a);a(absent)="";
        else
            a=string(a);
        end
        b=string(b);a(ismissing(a))="";b(ismissing(b))="";
        check(isequal(a,b),['Text column differs: ' name]);
    end
end
end
function near(a,b,message)
check(isequal(size(a),size(b)) && all(abs(double(a(:))-double(b(:)))<=1e-11*max(1,abs(double(b(:))))),message);
end
function check(ok,message)
assert(isscalar(ok) && ok,'DMT:TradeoffIndependentVerification','%s',message);
end
function nonempty(path)
info=dir(path);check(~isempty(info) && info.bytes>0,['Missing/empty export: ' path]);
end
function value=stamp()
value=char(datetime('now','TimeZone','UTC','Format','yyyyMMdd_HHmmss_SSS'));
end
function value=utcNow()
value=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss.SSS Z'));
end
