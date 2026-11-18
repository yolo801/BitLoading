function [shared,designs,runs,evidence] = dmt_fb_reuse(moduleRoot,historicalFolder,cfg,plan)
%DMT_FB_REUSE Admit one complete, compatible Fig. 7 point after read-only audit.
shared=[];
designs=[];
runs=[];
evidence=struct('status','not_provided','detail','No historical Fig. 7 folder supplied.', ...
    'folder','','source_id','','config_id','','seed_id','','protocol_sha256','', ...
    'receipt_sha256','','source_manifest_sha256','','frozen_record_hashes',table(), ...
    'verification',struct());
historicalFolder=char(string(historicalFolder));
if isempty(historicalFolder), return; end
evidence.folder=canonicalPath(historicalFolder);
if ~isfolder(evidence.folder)
    evidence.status='missing_directory';
    evidence.detail='The supplied historical Fig. 7 result directory does not exist.';
    return;
end

origin=fileparts(moduleRoot);
folder=evidence.folder;
evidence.status='incompatible';
try
    protocolFile=fullfile(folder,'Protocol.mat');
    receiptFile=fullfile(folder,'verification_receipt.mat');
    sourceManifestFile=fullfile(folder,'source_manifest.csv');
    evidence.protocol_sha256=fileHash(protocolFile);
    evidence.receipt_sha256=fileHash(receiptFile);
    evidence.source_manifest_sha256=fileHash(sourceManifestFile);
    saved=load(protocolFile,'checkpoint');
    p=saved.checkpoint;
    evidence.source_id=p.source_id;
    evidence.config_id=p.config_id;
    evidence.seed_id=p.seed_id;
    fullPoint=plan(plan.condition_id==9 & plan.P_target==1 & plan.q==8,:);
    assert(strcmp(p.study,'literature_fig7') && strcmp(p.version,'tradeoff_v2') && ...
        strcmp(p.phase,'formal') && ~p.test_only && p.planned_payload_slots==30 && ...
        p.symbols_per_slot==50000 && sum(fullPoint.role=="payload")==30 && ...
        isequaln(p.cfg,cfg) && isequaln(p.plan,fullPoint), ...
        'DMT:Fig7BERReuseProtocol','Historical phase, configuration, budget or per-role plan differs.');
    expectedSource='57fa231c55f2d7683fe1bc09cff206eb8bae7502d70f83692a6a2e22eaadde20';
    assert(strcmp(evidence.source_id,expectedSource), ...
        'DMT:Fig7BERReuseSource','Historical source manifest is not the verified Fig. 7 release.');
    assert(p.fit.passed && isequal(reshape(p.fit.taps,1,[]),cfg.h) && ...
        isreal(cfg.h) && numel(cfg.h)==9 && cfg.NCP==8 && abs(sum(cfg.h)-1)<=1e-12, ...
        'DMT:Fig7BERReuseFIR','Historical FIR differs from the frozen nine-tap response.');
    checkNumericalCore(moduleRoot,p.source_manifest);

    saved=load(receiptFile,'checkpoint');
    receipt=saved.checkpoint;
    assert(completeReceipt(receipt),'DMT:Fig7BERReuseReceipt', ...
        'The saved historical verification receipt does not attest a complete formal point.');
    [names,kinds,indices]=recordPaths();
    rawHashes=hashRecords(folder,names);
    checked=verifyOriginal(origin,folder);
    evidence.verification=checked;
    assert(completeReceipt(checked) && checked.qualified==receipt.qualified && ...
        isequaln(checked.scenario,receipt.scenario), ...
        'DMT:Fig7BERReuseAudit','Historical re-verification did not agree with the original receipt: %s',checked.detail);

    data=cell(numel(names),1);
    recordHashes=strings(numel(names),1);
    for i=1:numel(names)
        data{i}=dmt_t2_record('load',folder,p,char(kinds(i)),indices(i),[]);
        assert(~isempty(data{i}),'DMT:Fig7BERReuseRecord','Missing historical record: %s',names(i));
        recordHashes(i)=string(dmt_v13_hash(data{i}));
    end
    importedRuns=data(21:end);
    assert(all(cellfun(@(one)one.symbols==50000 && one.power_match,importedRuns)), ...
        'DMT:Fig7BERReusePower','Historical payloads do not all match the required length and power.');
    assert(isequal(rawHashes,hashRecords(folder,names)) && ...
        strcmp(evidence.protocol_sha256,fileHash(protocolFile)) && ...
        strcmp(evidence.receipt_sha256,fileHash(receiptFile)) && ...
        strcmp(evidence.source_manifest_sha256,fileHash(sourceManifestFile)), ...
        'DMT:Fig7BERReuseChanged','Historical files changed while they were being audited.');
    evidence.frozen_record_hashes=table(kinds,indices,names,rawHashes,recordHashes, ...
        'VariableNames',{'kind','index','relative_path','file_sha256','data_hash'});
    evidence.status='reused_verified';
    evidence.detail='Original receipt and fresh Fig. 7 verification agree. All 30 historical slots matched.';
    shared=data(1:5);
    designs=data(6:20);
    runs=importedRuns;
catch ME
    evidence.detail=getReport(ME,'extended','hyperlinks','off');
end
end

function valid=completeReceipt(r)
valid=strcmp(r.phase,'formal') && ~r.test_only && r.valid && ...
    r.data_integrity_valid && r.acquisition_complete && r.fit_passed && ...
    r.link_preflight_passed && r.planned==30 && r.completed==30 && ...
    r.design_rejected==0 && r.power_error==0 && r.incomplete==0;
end

function report=verifyOriginal(origin,folder)
before=pwd;
cd(origin);
restore=onCleanup(@()cd(before)); %#ok<NASGU>
entry='verify_dmt_tradeoff_v2_fig7';
resolved=which(entry);
expected=canonicalPath(fullfile(origin,[entry '.m']));
assert(~isempty(resolved) && (strcmp(canonicalPath(resolved),expected) || ...
    (ispc && strcmpi(canonicalPath(resolved),expected))), ...
    'DMT:Fig7BERReuseVerifier','Unexpected original Fig. 7 verifier resolved at %s.',resolved);
report=verify_dmt_tradeoff_v2_fig7(folder);
end

function checkNumericalCore(root,manifest)
names=["dmt_default_config","dmt_demod_errors","dmt_qam_ber","dmt_t2_adjudicate", ...
    "dmt_t2_config","dmt_t2_cycle_rate","dmt_t2_design","dmt_t2_payload", ...
    "dmt_t2_plan","dmt_to_agree","dmt_to_config","dmt_to_count_valid", ...
    "dmt_to_decide","dmt_to_design","dmt_to_initial","dmt_to_link","dmt_to_measure", ...
    "dmt_to_payload","dmt_to_power_cal","dmt_to_quantize","dmt_to_reduce", ...
    "dmt_to_seed","dmt_v13_make_frame","dmt_v13_stream","dmt_wilson"];
for file="private/"+names+".m"
    row=manifest.relative_path==file;
    assert(nnz(row)==1 && strcmp(fileHash(fullfile(root,file)),manifest.sha256(row)), ...
        'DMT:Fig7BERReuseCore','The current numerical core differs from historical %s.',file);
end
end

function [names,kinds,indices]=recordPaths()
kinds=[repmat("Shared",5,1);repmat("Design",15,1);repmat("Payload",30,1)];
indices=[(1:5)';(1:15)';(1:30)'];
names=compose("checkpoints/%s_%04d.mat",lower(kinds),indices);
end

function hashes=hashRecords(folder,files)
hashes=strings(numel(files),1);
for i=1:numel(files)
    hashes(i)=fileHash(fullfile(folder,files(i)));
end
end

function hash=fileHash(path)
fid=fopen(path,'rb');
assert(fid>=0,'DMT:Fig7BERReuseFile','Cannot read %s.',path);
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
hash=dmt_sha256(fread(fid,Inf,'*uint8'));
end

function path=canonicalPath(path)
file=java.io.File(path);
path=char(file.getCanonicalPath());
end
