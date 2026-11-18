function result = run_dmt_fig7_ber_tradeoff(mode,varargin)
%RUN_DMT_FIG7_BER_TRADEOFF Preflight, ordered studies and safe resumption.
if nargin==0, mode='all'; end
mode=validatestring(mode,{'all','preflight','promotion','scan','resume'});
args=inputParser;
for name={'HistoricalDirectory','PreflightDirectory','PromotionDirectory','OutputDirectory'}
    addParameter(args,name{1},'',@(x)ischar(x)||(isstring(x)&&isscalar(x)));
end
parse(args,varargin{:});
opt=args.Results;
root=fileparts(mfilename('fullpath'));
historical=canonical(opt.HistoricalDirectory);
switch mode
    case {'all','preflight'}
        result.promotion_preflight=start(root,'promotion','preflight','','','');
        result.scan_preflight=start(root,'scan','preflight','','','');
        if strcmp(mode,'all')
            result.promotion=start(root,'promotion','formal','','',result.promotion_preflight.output_dir);
            result.scan=start(root,'scan','formal',historical,result.promotion.output_dir, ...
                result.scan_preflight.output_dir);
        end
    case {'promotion','scan'}
        result=start(root,mode,'formal',historical,canonical(opt.PromotionDirectory), ...
            canonical(opt.PreflightDirectory));
    case 'resume'
        folder=canonical(opt.OutputDirectory);
        assert(isfile(fullfile(folder,'Protocol.mat')),'DMT:FBResume','Pass the unfinished study folder.');
        saved=load(fullfile(folder,'Protocol.mat'),'checkpoint');
        result=finish(root,folder,saved.checkpoint,true);
end
end

function result=start(root,study,phase,historical,promotionDirectory,preflightDirectory)
[cfg,plan,fit]=dmt_fb_setup(root,study,phase);
[manifest,sourceID]=dmt_source_manifest(root);
testOnly=strcmp(phase,'preflight');
symbols=cfg.payload_symbols;
if testOnly, symbols=cfg.preflight_payload_symbols; end
preflightGate=struct();promotionGate=struct();
if ~testOnly
    preflightGate=verifyGate(preflightDirectory,study,'preflight',sourceID);
    if strcmp(study,'scan')
        promotionGate=verifyGate(promotionDirectory,'promotion','formal',sourceID);
    end
end
if testOnly || ~strcmp(study,'scan'), historical=''; end
p=struct('version','fig7_ber_tradeoff_v1','study',study,'phase',phase,'test_only',testOnly, ...
    'cfg',cfg,'config_id',dmt_v13_hash(cfg),'plan',plan,'seed_id',dmt_v13_hash(plan), ...
    'fit',fit,'source_id',sourceID,'source_manifest',manifest, ...
    'planned_payload_slots',sum(plan.role=="payload"),'symbols_per_slot',symbols, ...
    'historical_folder',historical,'preflight_gate',preflightGate,'promotion_gate',promotionGate);
base=fullfile(root,'results');
if ~isfolder(base),mkdir(base);end
[~,tag]=fileparts(tempname(base));
folder=fullfile(base,sprintf('fig7_ber_%s_%s_%s',study,phase,tag));
assert(~isfolder(folder),'DMT:FBNewDirectory','Study directory already exists.');
mkdir(folder);
mkdir(fullfile(folder,'checkpoints'));
diary(fullfile(folder,'run.log'));
diaryGuard=onCleanup(@()diary('off'));
fprintf('Fig. 7 BER tradeoff %s/%s | planned %d x %d | %s\n', ...
    study,phase,p.planned_payload_slots,symbols,folder);
try
    p.environment=dmt_t2_runtime(root);
    if ~testOnly
        copyGate(preflightGate,folder,'preflight_gate_receipt.mat');
        mechanicalPath=fullfile(folder,'mechanical_checks.mat');
        copyChecked(fullfile(preflightGate.folder,'mechanical_checks.mat'),mechanicalPath);
        assert(strcmp(dmt_fb_filehash(mechanicalPath),preflightGate.mechanical_sha256), ...
            'DMT:FBGateMutation','Mechanical preflight receipt changed during copy.');
        if strcmp(study,'scan')
            copyGate(promotionGate,folder,'promotion_gate_receipt.mat');
        end
    end
    writetable(plan,fullfile(folder,'seed_plan.csv'));
    writetable(manifest,fullfile(folder,'source_manifest.csv'));
    copyChecked(fullfile(fileparts(root),'evidence','fit_summary.json'),fullfile(folder,'fit_summary.json'));
    copyChecked(fullfile(root,'evidence','historical_model.json'),fullfile(folder,'historical_model.json'));
    dmt_v13_atomic_save(fullfile(folder,'Protocol.mat'),p);
catch ME
    writeFailure(folder,'startup',ME);
    rethrow(ME);
end
clear diaryGuard
result=finish(root,folder,p,false);
end

function result=finish(root,folder,p,resume)
lock=dmt_study_lock(folder); %#ok<NASGU>
logPath=fullfile(folder,'run.log');
diary(logPath);
closer=onCleanup(@()diary('off')); %#ok<NASGU>
if resume, fprintf('RESUME %s\n',char(datetime('now','TimeZone','UTC'))); end
stage='verify frozen execution identity';
try
    [cfg,plan,fit]=dmt_fb_setup(root,p.study,p.phase);
    [manifest,sourceID]=dmt_source_manifest(root);
    testOnly=strcmp(p.phase,'preflight');
    symbols=cfg.payload_symbols;
    if testOnly,symbols=cfg.preflight_payload_symbols;end
    assert(strcmp(p.version,'fig7_ber_tradeoff_v1') && strcmp(p.source_id,sourceID) && ...
        isequaln(p.source_manifest,manifest) && isequaln(p.cfg,cfg) && isequaln(p.fit,fit) && ...
        isequaln(p.plan,plan) && strcmp(p.config_id,dmt_v13_hash(cfg)) && strcmp(p.seed_id,dmt_v13_hash(plan)) && ...
        p.test_only==testOnly && p.symbols_per_slot==symbols && p.planned_payload_slots==sum(plan.role=="payload"), ...
        'DMT:FBResumeIdentity','Use the same frozen source, model and role seed plan.');
    if resume
        archiveInterruptedStaging(folder);
        current=verify_dmt_fig7_ber_tradeoff(folder);
        if current.valid, result=current; return; end
        dmt_fb_audit_records(folder,p);
    end
    stage='MATLAB production preflight';
    mechanicalPath=fullfile(folder,'mechanical_checks.mat');
    if ~isfile(mechanicalPath)
        assert(p.test_only,'DMT:FBMissingPreflight','Formal run requires a mechanical preflight receipt.');
        checks=dmt_fb_preflight(cfg);
        dmt_v13_atomic_save(mechanicalPath,checks);
    end
    dmt_fb_audit_gates(folder,p);
    stage='acquisition';
    dmt_fb_acquire(root,folder,p);
    [~,currentSourceID]=dmt_source_manifest(root);
    assert(strcmp(currentSourceID,p.source_id),'DMT:FBSourceChanged','Source changed during acquisition.');
    stage='rebuild reports from saved records';
    [counts,tables]=dmt_fb_audit_records(folder,p);
    assert(counts.acquisition_complete,'DMT:FBIncomplete','Not all planned slots were resolved.');
    dmt_fb_audit_exports(folder,p,tables,'write');
    fprintf('FIG7 BER ACQUISITION COMPLETE | %s/%s | actual %d | rejected %d | planned %d\n', ...
        p.study,p.phase,counts.completed,counts.design_rejected,p.planned_payload_slots);
    if ~p.test_only
        stage='report figures';
        dmt_fb_graphics(folder,p.study,p.cfg,tables);
    end
    diary('off');
    diary(logPath);
    stage='read-only verification';
    result=verify_dmt_fig7_ber_tradeoff(folder);
    dmt_v13_atomic_save(fullfile(folder,'verification_receipt.mat'),result);
    assert(result.valid,'DMT:FBVerification','Study audit failed. %s',result.detail);
    fprintf('FIG7 BER AUDIT COMPLETE | valid=%d | %s\n',result.valid,folder);
catch ME
    writeFailure(folder,stage,ME);
    if strcmp(stage,'acquisition')
        try
            [partial,tables]=dmt_fb_audit_records(folder,p);
            dmt_fb_audit_exports(folder,p,tables,'write');
            dmt_v13_atomic_save(fullfile(folder,'partial_audit.mat'),partial);
        catch partialError
            fprintf(2,'Partial record audit failed: %s\n',partialError.message);
        end
    end
    rethrow(ME);
end
end

function gate=verifyGate(folder,study,phase,sourceID)
assert(~isempty(folder) && isfolder(folder),'DMT:FBGateDirectory', ...
    'Pass the verified %s %s directory.',study,phase);
fresh=verify_dmt_fig7_ber_tradeoff(folder);
path=fullfile(folder,'verification_receipt.mat');
saved=load(path,'checkpoint');receipt=saved.checkpoint;
assert(fresh.valid && fresh.acquisition_complete && receipt.valid && receipt.acquisition_complete && ...
    fresh.data_integrity_valid && receipt.data_integrity_valid && ...
    strcmp(fresh.study,study) && strcmp(receipt.study,study) && ...
    strcmp(fresh.phase,phase) && strcmp(receipt.phase,phase) && ...
    strcmp(fresh.source_id,sourceID) && strcmp(receipt.source_id,sourceID) && ...
    strcmp(fresh.mechanical_sha256,receipt.mechanical_sha256), ...
    'DMT:FBGate','Gate %s/%s failed. %s',study,phase,fresh.detail);
gate=struct('folder',folder,'study',study,'phase',phase,'source_id',sourceID, ...
    'receipt_sha256',dmt_fb_filehash(path),'mechanical_sha256',fresh.mechanical_sha256);
end

function copyGate(gate,folder,name)
dest=fullfile(folder,name);
copyChecked(fullfile(gate.folder,'verification_receipt.mat'),dest);
assert(strcmp(dmt_fb_filehash(dest),gate.receipt_sha256),'DMT:FBGateMutation','Gate changed during copy.');
end

function copyChecked(source,dest)
[ok,detail]=copyfile(source,dest);
assert(ok,'DMT:FBCopy','Cannot copy %s: %s',source,detail);
end

function path=canonical(path)
path=char(path);
if ~isempty(path),path=char(java.io.File(path).getCanonicalPath());end
end

function archiveInterruptedStaging(folder)
staging=dir(fullfile(folder,'checkpoints','tp*.mat'));
for j=1:numel(staging)
    name=staging(j).name;
    if isempty(regexp(name,'^tp[0-9A-Fa-f_]+\.mat$','once')),continue;end
    destination=fullfile(folder,'interrupted_staging',name);
    container=fileparts(destination);
    if ~isfolder(container),mkdir(container);end
    assert(~isfile(destination),'DMT:FBExistingStaging','Staging archive already contains %s.',name);
    [ok,reason]=movefile(fullfile(staging(j).folder,name),destination);
    assert(ok,'DMT:FBStaging','Could not preserve interrupted staging file: %s',reason);
    fprintf('Preserved uncommitted staging file %s\n',destination);
end
end

function writeFailure(folder,stage,exception)
path=fullfile(folder,'failure_status.txt');
details=getReport(exception,'extended','hyperlinks','off');
if ~isfile(path)
    fid=fopen(path,'w','n','UTF-8');
    if fid>=0
        fileCloser=onCleanup(@()fclose(fid)); %#ok<NASGU>
        failureClass='execution_error';
        if any(strcmp(exception.identifier,{'DMT:TOPowerUnreachable','DMT:TOPowerCalibration','DMT:FBPowerError'}))
            failureClass='power_error';
        end
        fprintf(fid,'Class: %s\nStage: %s\nIdentifier: %s\n%s\n', ...
            failureClass,stage,exception.identifier,details);
    end
end
fprintf(2,'Fig. 7 BER study failed at %s | %s\n%s\n',stage,folder,details);
end
