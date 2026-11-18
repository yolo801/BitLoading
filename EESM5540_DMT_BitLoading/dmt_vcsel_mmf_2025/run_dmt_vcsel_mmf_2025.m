function result = run_dmt_vcsel_mmf_2025(mode,varargin)
%RUN_DMT_VCSEL_MMF_2025 Run the independently gated VCSEL–MMF DMT study.
if nargin==0,mode='all';end
mode=validatestring(mode,{'channel-fit','preflight','pilot','formal','all','resume','verify','redraw'});
inputs=inputParser;
for key={'PreflightDirectory','PilotDirectory','OutputDirectory'}
    addParameter(inputs,key{1},'',@(x)ischar(x)||(isstring(x)&&isscalar(x)));
end
parse(inputs,varargin{:});
opt=inputs.Results;
root=fileparts(mfilename('fullpath'));
folder=canonical(opt.OutputDirectory);
switch mode
    case 'channel-fit'
        [cfg,fit]=dmt_vm_config(fullfile(root,'evidence'));
        result=struct('channel_fit_passed',true,'cfg',cfg,'fit',fit);
    case 'all'
        result.preflight=start(root,'preflight','','');
        result.pilot=start(root,'pilot',result.preflight.output_dir,'');
        result.formal=start(root,'formal',result.preflight.output_dir,result.pilot.output_dir);
    case {'preflight','pilot','formal'}
        result=start(root,mode,canonical(opt.PreflightDirectory),canonical(opt.PilotDirectory));
    case 'resume'
        p=loadProtocol(folder);
        result=runSaved(root,folder,p,true);
    case 'verify'
        result=verify_dmt_vcsel_mmf_2025(folder);
    case 'redraw'
        result=redraw(root,folder);
end
end

function result=start(root,phase,preflightFolder,pilotFolder)
evidence=fullfile(root,'evidence');
[cfg,fit]=dmt_vm_config(evidence);
[manifest,sourceID]=dmt_source_manifest(root);
preflight=struct();pilot=struct();
plan=table();
symbols=0;
if ~strcmp(phase,'preflight')
    preflight=verifiedGate(preflightFolder,'preflight',cfg,sourceID);
    plan=dmt_vm_plan(cfg,phase);
    symbols=cfg.pilot_payload_symbols;
    if strcmp(phase,'formal')
        pilot=verifiedGate(pilotFolder,'pilot',cfg,sourceID);
        symbols=cfg.payload_symbols;
    end
end
budget=0;
if ~isempty(plan),budget=sum(plan.role=="payload");end
assert((strcmp(phase,'preflight') && budget==0) || (strcmp(phase,'pilot') && budget==24) || ...
    (strcmp(phase,'formal') && budget==120),'DMT:VMPlanBudget','Unexpected plan budget.');
base=fullfile(root,'results');
if ~isfolder(base),mkdir(base);end
[~,tag]=fileparts(tempname(base));
folder=fullfile(base,['dmt_vcsel_mmf_2025_' phase '_' tag]);
assert(~isfolder(folder),'DMT:VMFolder','Study directory already exists.');
mkdir(folder);mkdir(fullfile(folder,'checkpoints'));
diary(fullfile(folder,'run.log'));
stopDiary=onCleanup(@()diary('off'));
fprintf('VCSEL–MMF %s | planned=%d | symbols/slot=%d | %s\n',phase,budget,symbols,folder);
try
    copyChecked(evidence,fullfile(folder,'channel_evidence'));
    [savedCfg,savedFit]=dmt_vm_config(fullfile(folder,'channel_evidence'));
    assert(isequaln(savedCfg,cfg) && isequaln(savedFit,fit),'DMT:VMFitCopy','Channel files changed during copy.');
    if ~strcmp(phase,'preflight')
        saveGate(folder,preflight,'preflight');
        copyChecked(fullfile(preflight.folder,'mechanical_checks.mat'),fullfile(folder,'mechanical_checks.mat'));
    end
    if strcmp(phase,'formal'),saveGate(folder,pilot,'pilot');end
    p=struct('version',cfg.protocol,'phase',phase,'test_only',~strcmp(phase,'formal'), ...
        'cfg',cfg,'fit',fit,'config_id',dmt_v13_hash(cfg),'plan',plan,'seed_id',dmt_v13_hash(plan), ...
        'source_id',sourceID,'source_manifest',manifest,'environment',dmt_vm_runtime(root), ...
        'planned_payload_slots',budget,'symbols_per_slot',symbols,'preflight_gate',preflight,'pilot_gate',pilot);
    writetable(manifest,fullfile(folder,'source_manifest.csv'));
    if ~isempty(plan),writetable(plan,fullfile(folder,'seed_plan.csv'));end
    dmt_v13_atomic_save(fullfile(folder,'Protocol.mat'),p);
catch ME
    writeFailure(folder,'startup',ME);
    rethrow(ME)
end
clear stopDiary
result=runSaved(root,folder,p,false);
end

function result=runSaved(root,folder,p,resume)
assert(isfolder(folder));
lock=dmt_study_lock(folder); %#ok<NASGU>
diaryPath=fullfile(folder,'run.log');
diary(diaryPath);
stopDiary=onCleanup(@()diary('off')); %#ok<NASGU>
stage='frozen protocol';
try
    dmt_vm_identity(root,folder,p);
    dmt_vm_runtime(root);
    if resume
        preserveStaging(folder);
        existing=verify_dmt_vcsel_mmf_2025(folder);
        if existing.valid,result=existing;return;end
        fprintf('RESUME %s\n',folder);
        if ~strcmp(p.phase,'preflight'),dmt_vm_records(folder,p,'audit');end
    end
    stage='production mechanical preflight';
    path=fullfile(folder,'mechanical_checks.mat');
    if ~isfile(path)
        assert(strcmp(p.phase,'preflight'),'DMT:VMPreflightGate','Mechanical preflight receipt is missing.');
        checks=dmt_vm_preflight(p.cfg,p.cfg.conditions);
        dmt_v13_atomic_save(path,checks);
    end
    dmt_vm_gates(folder,p);
    if strcmp(p.phase,'preflight')
        fprintf('VCSEL PREFLIGHT COMPLETE\n');
    else
        stage='acquisition';
        acquisitionTimer=tic;
        [records,timing]=dmt_vm_records(folder,p,'acquire');
        wall=toc(acquisitionTimer);
        stage='rebuild verified counters';
        [tables,stats]=dmt_vm_tables(p.cfg,p.plan,records);
        assert(stats.data_integrity_valid && stats.acquisition_complete,'DMT:VMAcquisition','Planned slots remain unresolved.');
        dmt_vm_exports(folder,p,tables,'write');
        if strcmp(p.phase,'pilot')
            timing.wall_seconds=wall;
            % Scale actual phase components for a planning estimate. A pilot
            % design rejection can reduce transmissions and biases this estimate.
            timing.formal_seconds_estimate=5*(timing.initial_seconds+timing.design_seconds)+ ...
                5*p.cfg.payload_symbols/p.cfg.pilot_payload_symbols*timing.payload_seconds;
            timing.pilot_sent=stats.completed;
            timing.planning_only=true;
            timing.resumed=resume;
            if resume,timing.formal_seconds_estimate=NaN;end
            dmt_v13_atomic_save(fullfile(folder,'pilot_timing.mat'),timing);
        end
        fprintf('VCSEL ACQUISITION COMPLETE | %s | sent=%d rejected=%d planned=%d\n', ...
            p.phase,stats.completed,stats.design_rejected,p.planned_payload_slots);
        if strcmp(p.phase,'formal')
            stage='formal graphics';
            dmt_vm_graphics(folder,p.cfg,tables,'draw');
        end
    end
    diary('off');diary(diaryPath);
    stage='read-only result verification';
    result=verify_dmt_vcsel_mmf_2025(folder);
    dmt_v13_atomic_save(fullfile(folder,'verification_receipt.mat'),result);
    assert(result.valid,'DMT:VMVerification','%s',result.detail);
    fprintf('VCSEL AUDIT COMPLETE | %s | %s\n',p.phase,folder);
catch ME
    writeFailure(folder,stage,ME);
    if strcmp(stage,'acquisition')
        try
            records=dmt_vm_records(folder,p,'audit');
            [partial,stats]=dmt_vm_tables(p.cfg,p.plan,records);
            dmt_vm_exports(folder,p,partial,'write');
            dmt_v13_atomic_save(fullfile(folder,'partial_audit.mat'),stats);
        catch auditError
            fprintf(2,'Partial audit: %s\n',auditError.message);
        end
    end
    rethrow(ME)
end
end

function proof=verifiedGate(folder,phase,cfg,sourceID)
assert(isfolder(folder),'DMT:VMGateDirectory','Provide a verified %s directory.',phase);
r=verify_dmt_vcsel_mmf_2025(folder);
path=fullfile(folder,'verification_receipt.mat');
receipt=load(path,'checkpoint');
s=receipt.checkpoint;
assert(r.valid && r.acquisition_complete && s.valid && s.acquisition_complete && ...
    strcmp(r.phase,phase) && strcmp(s.phase,phase) && strcmp(r.source_id,sourceID) && ...
    strcmp(s.source_id,sourceID) && strcmp(r.config_id,dmt_v13_hash(cfg)) && ...
    strcmp(s.config_id,r.config_id) && strcmp(s.mechanical_sha256,r.mechanical_sha256), ...
    'DMT:VMGate','%s gate did not pass with this source and channel. %s',phase,r.detail);
proof=struct('folder',folder,'phase',phase,'receipt_sha256',dmt_fb_filehash(path), ...
    'mechanical_sha256',r.mechanical_sha256);
end

function saveGate(folder,receipt,phase)
path=fullfile(folder,[phase '_gate_receipt.mat']);
copyChecked(fullfile(receipt.folder,'verification_receipt.mat'),path);
assert(strcmp(dmt_fb_filehash(path),receipt.receipt_sha256),'DMT:VMGateCopy','Gate receipt changed.');
end

function output=redraw(root,folder)
p=loadProtocol(folder);
[r,tables]=verify_dmt_vcsel_mmf_2025(folder,false);
assert(r.valid && strcmp(p.phase,'formal'),'DMT:VMRedraw','Use a verified formal data folder. %s',r.detail);
outputTables=dmt_vm_exports(folder,p,tables,'read');
[~,tag]=fileparts(tempname(folder));
output=fullfile(folder,['redraw_' tag]);
assert(~isfolder(output));
mkdir(output);
dmt_vm_identity(root,folder,p);
dmt_vm_graphics(output,p.cfg,outputTables,'draw');
dmt_vm_graphics(output,p.cfg,outputTables,'verify');
end

function p=loadProtocol(folder)
saved=load(fullfile(folder,'Protocol.mat'),'checkpoint');
p=saved.checkpoint;
end

function path=canonical(path)
path=char(path);
if ~isempty(path)
    file=java.io.File(path);
    path=char(file.getCanonicalPath());
end
end

function copyChecked(source,destination)
[ok,msg]=copyfile(source,destination);
assert(ok,'DMT:VMCopy','Cannot copy %s: %s',source,msg);
end

function preserveStaging(folder)
files=dir(fullfile(folder,'checkpoints','tp*.mat'));
for j=1:numel(files)
    f=files(j);
    if isempty(regexp(f.name,'^tp[0-9a-fA-F_]+\.mat$','once')),continue;end
    output=fullfile(folder,'interrupted_staging');
    if ~isfolder(output),mkdir(output);end
    target=fullfile(output,f.name);
    assert(~isfile(target),'DMT:VMStaging','Staging file already archived.');
    [ok,msg]=movefile(fullfile(f.folder,f.name),target);
    assert(ok,'DMT:VMStaging','%s',msg);
end
end

function writeFailure(folder,stage,exception)
path=fullfile(folder,'failure_status.txt');
details=getReport(exception,'extended','hyperlinks','off');
if ~isfile(path)
    fid=fopen(path,'w','n','UTF-8');
    assert(fid>=0);
    closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
    fprintf(fid,'Stage: %s\nIdentifier: %s\n%s\n',stage,exception.identifier,details);
end
fprintf(2,'VCSEL–MMF failure | %s | %s\n%s\n',stage,folder,details);
end
