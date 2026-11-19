function result = dmt_vm_three_order_execute(mode,project,module,context,output)
%DMT_VM_THREE_ORDER_EXECUTE Use the existing acquisition chain in isolation.
evidence=fullfile(project,'evidence');
[base,fit]=dmt_vm_config(evidence);
[originalManifest,originalID]=dmt_source_manifest(project);
[moduleManifest,moduleID]=dmt_source_manifest(module);
[stagedManifest,stagedID]=dmt_source_manifest(context);
auditStagedSources(originalManifest,moduleManifest,stagedManifest);
environment=dmt_vm_runtime(context);
names=sources(originalManifest,originalID,moduleManifest,moduleID,stagedManifest,stagedID);
codes=(55:70).';
minPerOrder=5;
if strcmp(mode,'selfcheck')
    result=selfcheck(base,fit,evidence,codes,minPerOrder,names);
    fprintf('VCSEL THREE-ORDER SELFCHECK COMPLETE | scan=0 | formal=0\n');
    return
end

output=newRunDirectory(project,module,output);
diary(fullfile(output,'run.log'));
stopDiary=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('VCSEL three-order experiment | %s\n',output);
writetable(names.original_manifest,fullfile(output,'original_source_manifest.csv'));
writetable(names.module_manifest,fullfile(output,'three_order_source_manifest.csv'));
writetable(names.staged_manifest,fullfile(output,'executed_source_manifest.csv'));
dmt_v13_atomic_save(fullfile(output,'source_provenance.mat'),names);
[ok,detail]=copyfile(evidence,fullfile(output,'channel_evidence'));
assert(ok,'DMT:VMThreeOrderEvidence','%s',detail);
evidence=fullfile(output,'channel_evidence');
[copiedCfg,copiedFit]=dmt_vm_config(evidence);
assert(isequaln(copiedCfg,base) && isequaln(copiedFit,fit), ...
    'DMT:VMThreeOrderEvidence','Channel evidence changed during the snapshot.');

try
    first=runBand(output,base,fit,evidence,60,codes,minPerOrder,names,environment);
    bands=first;
    % Only the result of candidate validation can authorize a wider-band
    % scan. A failed or inconclusive formal payload never triggers fallback.
    if strcmp(first.status,'candidate_not_found')
        bands(2)=runBand(output,base,fit,evidence,62,codes,minPerOrder,names,environment);
    end
    last=bands(end);
    result=struct('status',last.status,'output_dir',output,'bands',bands, ...
        'selected_band_GHz',last.selected_band_GHz,'selected_swing',last.selected_swing, ...
        'formal_payloads_completed',sum([bands.formal_payloads_completed]), ...
        'figure_1_saved',last.figure_1_saved);
    dmt_v13_atomic_save(fullfile(output,'result.mat'),result);
    fprintf('VCSEL THREE-ORDER COMPLETE | %s | formal=%d\n', ...
        result.status,result.formal_payloads_completed);
catch err
    writeFailure(output,err);
    rethrow(err)
end
end

function result=runBand(output,base,fit,evidence,band,codes,minPerOrder,names,environment)
folder=fullfile(output,sprintf('band_%d_GHz',band));
makeDirectory(folder);
fprintf('Band %d GHz | independent gate and seed range\n',band);
[cfg,gate]=dmt_vm_three_order_band_gate(base,fit,evidence,band,mechanicalSeed(band));
dmt_v13_atomic_save(fullfile(folder,'band_gate.mat'),gate);
result=struct('band_GHz',band,'status','band_gate_rejected','output_dir',folder, ...
    'selected_band_GHz',NaN,'selected_swing',NaN,'formal_payloads_completed',0, ...
    'figure_1_saved',false);
if ~gate.passed
    fprintf('Band %d GHz rejected by gate: %s\n',band,gate.status);
    dmt_v13_atomic_save(fullfile(folder,'band_result.mat'),result);
    return
end
cfg=sweepConfig(cfg,codes);
plan=dmt_vm_three_order_plan(cfg,band);
planHash=dmt_v13_hash(plan);
protocol=struct('version','vcsel_three_order_v1','cfg',cfg,'config_hash',dmt_v13_hash(cfg), ...
    'band_end_GHz',band,'calibration_id',1,'min_tones_per_order',minPerOrder, ...
    'target_swing',.625,'swing_codes',codes,'plan_hash',planHash,'plan',plan, ...
    'original_source_id',names.original_id,'module_source_id',names.module_id, ...
    'executed_source_id',names.staged_id,'band_gate_hash',dmt_v13_hash(gate),'environment',environment);
dmt_v13_atomic_save(fullfile(folder,'Protocol.mat'),protocol);
writetable(plan,fullfile(folder,'seed_plan.csv'));
recordsDir=fullfile(folder,'candidates');
makeDirectory(recordsDir);

n=numel(codes);
accepted=false(n,1);
credit=zeros(n,3);
proposed=zeros(n,3);
attempts=zeros(n,1);
worst=nan(n,1);
state=strings(n,1);
reason=strings(n,1);
hashes=strings(n,1);
chosen=false(n,1);
scheme='PerToneValidated';
for j=1:n
    condition=cfg.conditions(j);
    probe=dmt_vm_initial(cfg,condition,1,plan);
    design=dmt_vm_design(cfg,condition,1,scheme,probe,plan);
    accepted(j)=strcmp(design.status,'accepted');
    proposed(j,:)=countOrders(design.initial_M,cfg.Mset);
    credit(j,:)=countOrders(design.rounds(end).M,cfg.Mset);
    attempts(j)=numel(design.rounds);
    worst(j)=max(design.rounds(end).CI_high);
    state(j)=string(design.status);
    reason(j)=string(design.reason);
    hashes(j)=string(auditCalibration(cfg,condition,probe,design,plan));
    record=struct('condition',condition,'plan_hash',planHash,'probe',probe,'design',design, ...
        'configuration_hash',char(hashes(j)));
    dmt_v13_atomic_save(candidateFile(recordsDir,codes(j)),record);
    fprintf('Band %d GHz | swing %.2f | %s | order counts [%d %d %d]\n', ...
        band,condition.swing,design.status,credit(j,1),credit(j,2),credit(j,3));
end
index=dmt_vm_three_order_select(codes,accepted,credit,minPerOrder);
if ~isempty(index),chosen(index)=true;end
eligible=accepted & all(credit>=minPerOrder,2);
scan=table(codes/100,state,reason,attempts,proposed(:,1),proposed(:,2),proposed(:,3), ...
    credit(:,1),credit(:,2),credit(:,3),worst,hashes,eligible,chosen,'VariableNames', ...
    {'swing','design_status','reason','attempts','proposed_QPSK','proposed_16QAM','proposed_64QAM', ...
    'last_candidate_QPSK','last_candidate_16QAM','last_candidate_64QAM','validation_max_CI_high', ...
    'configuration_hash','eligible','selected'});
writetable(scan,fullfile(folder,'swing_scan.csv'));

if isempty(index)
    result.status='candidate_not_found';
else
    record=load(candidateFile(recordsDir,codes(index)),'checkpoint');
    record=record.checkpoint;
    assert(strcmp(record.plan_hash,planHash) && isequaln(record.condition,cfg.conditions(index)) && ...
        strcmp(record.configuration_hash,hashes(index)), ...
        'DMT:VMThreeOrderCandidate','The selected candidate does not match its saved identity.');
    frozen=struct('cfg',cfg,'condition',record.condition,'probe',record.probe,'design',record.design, ...
        'plan_hash',planHash,'configuration_hash',record.configuration_hash,'band_end_GHz',band, ...
        'model_notch_GHz',gate.FIR_notch.notch_GHz,'source_notch_GHz',gate.source_notch.notch_GHz, ...
        'minimum_tones_per_order',minPerOrder);
    frozenPath=fullfile(folder,'frozen_candidate.mat');
    dmt_v13_atomic_save(frozenPath,frozen);
    saved=load(frozenPath,'checkpoint');
    assert(isequaln(saved.checkpoint,frozen),'DMT:VMThreeOrderFreeze', ...
        'Saved frozen candidate differs from the selected record.');
    [status,nPayload,figureSaved]=formal(folder,saved.checkpoint,plan);
    result.status=status;
    result.selected_band_GHz=band;
    result.selected_swing=record.condition.swing;
    result.formal_payloads_completed=nPayload;
    result.figure_1_saved=figureSaved;
end
dmt_v13_atomic_save(fullfile(folder,'band_result.mat'),result);
end

function [status,nPayload,figureSaved]=formal(folder,frozen,plan)
cfg=frozen.cfg;
condition=frozen.condition;
probe=frozen.probe;
design=frozen.design;
hash=frozen.configuration_hash;
assert(strcmp(hash,auditCalibration(cfg,condition,probe,design,plan)) && ...
    strcmp(frozen.plan_hash,dmt_v13_hash(plan)) && ...
    all(countOrders(design.M,cfg.Mset)>=frozen.minimum_tones_per_order), ...
    'DMT:VMThreeOrderFreeze','Frozen profile, candidate counts or seed identity changed.');
symbols=cfg.payload_symbols;
raw=cell(cfg.payload_repeats,1);
for slot=1:cfg.payload_repeats
    seed=dmt_to_seed(plan,condition.condition_id,1,'PerToneValidated',0,'payload',slot);
    m=dmt_vm_payload(cfg,condition,design,seed,symbols);
    dmt_vm_payload_check(m,cfg,condition,design,seed,symbols);
    assert(strcmp(m.configuration_hash,hash));
    raw{slot}=m;
    dmt_v13_atomic_save(fullfile(folder,sprintf('formal_payload_%02d.mat',slot)),m);
    fprintf('Formal slot %d/%d | %d DMT symbols | power_match=%d\n', ...
        slot,cfg.payload_repeats,m.symbols,m.power_match);
end
nPayload=numel(raw);
for slot=1:nPayload
    saved=load(fullfile(folder,sprintf('formal_payload_%02d.mat',slot)),'checkpoint');
    assert(isequaln(saved.checkpoint,raw{slot}),'DMT:VMThreeOrderSavedPayload', ...
        'Saved formal payload counters differ from their audited record.');
end
errs=cellfun(@(m)m.error_bits,raw,'UniformOutput',false);
bits=cellfun(@(m)m.tested_bits,raw,'UniformOutput',false);
errors=sum(cat(2,errs{:}),2);
tested=sum(cat(2,bits{:}),2);
[ok,why]=dmt_to_count_valid(errors,tested,design.M,nPayload*symbols);
assert(ok,'DMT:VMThreeOrderCounts','%s',why);
[low,high]=dmt_wilson(errors,tested);
qualifies=all(high<cfg.targetBER);
powerMatch=all(cellfun(@(m)m.power_match,raw));
figureSaved=false;
status='formal_qualified';
if ~powerMatch
    status='formal_power_mismatch';
elseif ~qualifies
    status='formal_ber_not_supported';
end
profile=design.final_tx;
figureInput=struct('frequency_GHz',cfg.k(:)*cfg.Fs/cfg.NFFT/1e9, ...
    'snr_dB',10*log10(probe.gamma_B(:)),'order',design.M(:),'errors',errors,'bits',tested, ...
    'ci_low',low,'ci_high',high,'target_ber',cfg.targetBER,'notch_GHz',frozen.model_notch_GHz, ...
    'source_notch_GHz',frozen.source_notch_GHz, ...
    'swing',condition.swing,'candidate_id',profile.profile_id,'profile_hash',hash, ...
    'band_end_GHz',frozen.band_end_GHz);
exportFormalCounters(folder,figureInput,raw);
receipt=struct('status',status,'formal_payload_count',nPayload,'symbols_per_payload',symbols, ...
    'configuration_hash',hash,'profile_id',profile.profile_id,'condition',condition, ...
    'calibration_id',design.calibration_id,'B0_feedback_hash',probe.feedback_hash_sent, ...
    'candidate_validation_hash',profile.validation_hash,'seed_plan_hash',frozen.plan_hash, ...
    'power_match',powerMatch,'all_tones_strict_Wilson_pass',qualifies, ...
    'worst_Wilson_upper',max(high),'total_errors',sum(errors),'total_bits',sum(tested), ...
    'total_BER',sum(errors)/sum(tested),'figure_1_saved',false);
dmt_v13_atomic_save(fullfile(folder,'formal_verification.mat'),receipt);
if strcmp(status,'formal_qualified')
    dmt_v13_atomic_save(fullfile(folder,'figure_1_evidence.mat'),figureInput);
    files=dmt_vm_three_order_figure(folder,figureInput);
    figureSaved=true;
    receipt.figure_1_saved=true;
    receipt.figure_sha256=struct('png',dmt_fb_filehash(files.png), ...
        'pdf',dmt_fb_filehash(files.pdf),'caption',dmt_fb_filehash(files.caption));
    dmt_v13_atomic_save(fullfile(folder,'formal_verification.mat'),receipt);
end
end

function exportFormalCounters(folder,d,raw)
frequency=d.frequency_GHz;
M=d.order;
hash=repmat(string(d.profile_hash),numel(M),1);
pooled=table(frequency,d.snr_dB,M,log2(M),d.errors,d.bits,d.errors./d.bits,d.ci_low,d.ci_high, ...
    d.ci_high<d.target_ber,hash,'VariableNames',{'frequency_GHz','B0_SNR_dB','M','bits_per_symbol', ...
    'error_bits','tested_bits','BER','CI_low','CI_high','strict_Wilson_pass','configuration_hash'});
writetable(pooled,fullfile(folder,'formal_per_tone_pooled.csv'));
rows=cell(numel(raw),1);
for j=1:numel(raw)
    m=raw{j};
    [lo,hi]=dmt_wilson(m.error_bits,m.tested_bits);
    rows{j}=table(repmat(j,numel(M),1),frequency,M,m.error_bits,m.tested_bits, ...
        m.error_bits./m.tested_bits,lo,hi,hash,'VariableNames', ...
        {'slot','frequency_GHz','M','error_bits','tested_bits','BER','CI_low','CI_high', ...
        'configuration_hash'});
end
writetable(vertcat(rows{:}),fullfile(folder,'formal_per_tone_seed.csv'));
end

function hash=auditCalibration(cfg,condition,probe,design,plan)
dmt_vm_check('Shared',probe,cfg,condition,1,'Shared',NaN,'formal',plan,[]);
dmt_vm_check('Design',design,cfg,condition,1,'PerToneValidated',NaN,'formal',plan,probe);
hash='';
if strcmp(design.status,'accepted')
    hash=dmt_v13_hash(design.final_tx);
    assert(strcmp(hash,design.ack.configuration_hash), ...
        'DMT:VMThreeOrderProfileHash','Accepted profile differs from the receiver ACK.');
end
end

function result=selfcheck(base,fit,evidence,codes,minPerOrder,names)
cfg=sweepConfig(base,codes);
plan60=dmt_vm_three_order_plan(cfg,60);
plan62=dmt_vm_three_order_plan(cfg,62);
seed60=[plan60.data_seed;plan60.noise_seed(isfinite(plan60.noise_seed))];
seed62=[plan62.data_seed;plan62.noise_seed(isfinite(plan62.noise_seed))];
assert(isempty(intersect(seed60,seed62)) && all([seed60;seed62]>3101000000) && ...
    sum(plan60.role=="payload")==numel(codes)*base.payload_repeats);
counts=repmat([6 6 6],numel(codes),1);
valid=ismember(codes,[61 62 63 64]);
assert(codes(dmt_vm_three_order_select(codes,valid,counts,minPerOrder))==62);
counts(codes==62,3)=4;
assert(codes(dmt_vm_three_order_select(codes,valid,counts,minPerOrder))==63);
assert(isempty(dmt_vm_three_order_select(codes,false(size(valid)),counts,minPerOrder)));
M=[4;16;64];
[lo,hi]=dmt_wilson([0;10;1000],50000*log2(M));
assert(all(lo<=hi) && lo(1)==0 && hi(1)>0 && all(hi(1:2)<base.targetBER) && ...
    hi(3)>base.targetBER);
[~,baseGate]=dmt_vm_three_order_band_gate(base,fit,evidence,60,mechanicalSeed(60));
assert(baseGate.passed,'DMT:VMThreeOrderSelfcheck','Original band failed its link selfcheck.');
[~,expanded]=dmt_vm_three_order_band_gate(base,fit,evidence,62,mechanicalSeed(62));
result=struct('valid',true,'scan_conditions_executed',0,'formal_payloads_completed',0, ...
    'base_band_gate',baseGate,'expanded_band_gate',expanded,'tie_break_checked',true, ...
    'seed_roles_checked',true,'strict_Wilson_checked',true,'source_id',names.module_id);
end

function cfg=sweepConfig(cfg,codes)
template=cfg.conditions(find([cfg.conditions.case_id]==2,1));
assert(template.q==8 && template.P_target==1 && cfg.targetBER==1e-3 && ...
    cfg.payload_repeats==2 && cfg.payload_symbols==25000 && isequal(cfg.Mset,[4 16 64]));
cfg.swings=(codes/100).';
cfg.conditions=repmat(template,1,numel(codes));
for j=1:numel(codes)
    cfg.conditions(j).condition_id=j;
    cfg.conditions(j).swing=cfg.swings(j);
end
end

function counts=countOrders(M,set)
counts=arrayfun(@(order)nnz(M==order),set);
end

function path=candidateFile(folder,code)
path=fullfile(folder,sprintf('swing_%02d.mat',code));
end

function seed=mechanicalSeed(band)
seed=3190000000+100*band;
end

function output=newRunDirectory(project,module,output)
base=fullfile(module,'results');
if isempty(output)
    if ~isfolder(base),makeDirectory(base);end
    [~,tag]=fileparts(tempname(base));
    output=fullfile(base,['vcsel_three_order_' tag]);
end
output=canonical(output);
archive=canonical(fullfile(project,'results'));
assert(~startsWith([output filesep],[archive filesep],'IgnoreCase',ispc) && ...
    ~isfolder(output) && ~isfile(output), ...
    'DMT:VMThreeOrderOutput','Use a new output directory outside the historical results tree.');
assert(isfolder(fileparts(output)),'DMT:VMThreeOrderOutput','The output parent must exist.');
destination=java.io.File(output);
assert(destination.mkdir(),'DMT:VMThreeOrderMkdir','Cannot create the new run at %s.',output);
end

function path=canonical(path)
file=java.io.File(path);
path=char(file.getCanonicalPath());
end

function makeDirectory(folder)
[ok,detail]=mkdir(folder);
assert(ok,'DMT:VMThreeOrderMkdir','%s',detail);
end

function names=sources(orig,origID,module,moduleID,staged,stagedID)
names=struct('original_manifest',orig,'original_id',origID,'module_manifest',module, ...
    'module_id',moduleID,'staged_manifest',staged,'staged_id',stagedID);
end

function auditStagedSources(orig,module,staged)
existing=orig(startsWith(orig.relative_path,"private/"),:);
extra=module(startsWith(module.relative_path,"private/") | ...
    ismember(module.relative_path,["dmt_vm_three_order_execute.m","dmt_vm_three_order_figure.m"]),:);
extra.relative_path(extra.relative_path=="dmt_vm_three_order_figure.m")= ...
    "private/dmt_vm_three_order_figure.m";
assert(isequaln(sortrows([existing;extra],'relative_path'),staged), ...
    'DMT:VMThreeOrderStagedSource','Staged code differs from the original and new module manifests.');
end

function writeFailure(folder,err)
fid=fopen(fullfile(folder,'failure_status.txt'),'wt','n','UTF-8');
assert(fid>=0,'DMT:VMThreeOrderFailureLog','Could not retain the error report.');
closeLog=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n%s\n',err.identifier,getReport(err,'extended','hyperlinks','off'));
end
