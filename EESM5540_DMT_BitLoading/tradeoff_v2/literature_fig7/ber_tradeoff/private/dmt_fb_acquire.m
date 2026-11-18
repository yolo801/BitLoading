function dmt_fb_acquire(root,folder,p)
% Execute only missing work under the frozen protocol and role seeds.
if strcmp(p.study,'scan')
    scan(root,folder,p);
else
    promotion(folder,p);
end
end

function scan(root,folder,p)
cfg=p.cfg;plan=p.plan;
layout=dmt_t2_layout(cfg,plan);
if ~p.test_only, importReference(root,folder,p,layout); end
fixed=cell(numel(cfg.P_targets),numel(layout.calibrations),numel(cfg.fixed_M));
% The q=8 historical treatment can precede q=6 in genuine TX calibration
% time. Recover its TX-only calibration before measuring the q=6 counterpart.
for ci=1:numel(layout.conditions)
    cond=layout.conditions(ci);
    ip=find(cfg.P_targets==cond.P_target);
    for ic=1:numel(layout.calibrations)
        a=sharedIndex(ci,ic,layout);
        for s=1:numel(cfg.fixed_M)
            record=getRecord(folder,p,'Design',(a-1)*layout.nSchemes+s);
            if ~isempty(record) && strcmp(record.status,'fixed_authorized')
                earlier=fixed{ip,ic,s};
                assert(isempty(earlier)||isequaln(earlier,record.power), ...
                    'DMT:FBPowerPair','Saved fixed-strategy TX calibrations disagree.');
                fixed{ip,ic,s}=record.power;
            end
        end
    end
end
for ci=1:numel(layout.conditions)
    cond=layout.conditions(ci);
    ip=find(cfg.P_targets==cond.P_target);
    for ic=1:numel(layout.calibrations)
        cal=layout.calibrations(ic);
        a=sharedIndex(ci,ic,layout);
        initial=sharedCalibration(folder,p,a,cond,cal,plan);
        for s=1:layout.nSchemes
            scheme=cfg.scheme_names{s};
            d=(a-1)*layout.nSchemes+s;
            design=getRecord(folder,p,'Design',d);
            if isempty(design)
                reused=[];
                if s<=numel(cfg.fixed_M), reused=fixed{ip,ic,s}; end
                fprintf('Scan condition %d cal %d %s design\n',cond.condition_id,cal,scheme);
                try
                    design=dmt_t2_design(cfg,cond,cal,scheme,initial,plan,reused);
                catch ME
                    if any(strcmp(ME.identifier,{'DMT:TOPowerUnreachable','DMT:TOPowerCalibration'}))
                        failure=struct('condition',cond,'calibration_id',cal,'phase',p.phase, ...
                            'scheme',scheme,'status','power_error','M',zeros(0,1), ...
                            'reason',getReport(ME,'extended','hyperlinks','off'));
                        dmt_t2_check('Design',failure,cfg,cond,cal,scheme,NaN,p.phase,plan,initial);
                        saveRecord(folder,p,'Design',d,failure);
                    end
                    rethrow(ME);
                end
                dmt_t2_check('Design',design,cfg,cond,cal,scheme,NaN,p.phase,plan,initial);
                saveRecord(folder,p,'Design',d,design);
            end
            fprintf('Scan condition %d cal %d %s | %s\n',cond.condition_id,cal,scheme,design.status);
            assert(~strcmp(design.status,'power_error'),'DMT:FBPowerError','Saved TX power error: %s', ...
                designReason(design));
            if ~any(strcmp(design.status,{'fixed_authorized','accepted'})),continue;end
            if s<=numel(cfg.fixed_M),fixed{ip,ic,s}=design.power;end
            payloads(folder,p,cond,cal,scheme,scheme,d,design,plan);
        end
    end
end
end

function promotion(folder,p)
cfg=p.cfg;plan=p.plan;
cond=table2struct(unique(plan(:,{'condition_id','P_target','q'}),'rows'));
calibrations=unique(plan.calibration_id).';
names={'OriginalVerifiedLoading','PromotionFirstLoading'};
for a=1:numel(calibrations)
    cal=calibrations(a);
    pathPlan=dmt_fb_promotion_plan_for(plan,names{1},'standard');
    initial=sharedCalibration(folder,p,a,cond,cal,pathPlan);
    for s=1:numel(names)
        branch=names{s};d=(a-1)*numel(names)+s;
        record=getRecord(folder,p,'Design',d);
        if isempty(record)
            fprintf('Promotion cal %d %s design\n',cal,branch);
            progress=@(event)logAttempt(cal,branch,event);
            record=dmt_fb_promotion_design(cfg,cond,cal,branch,initial,plan,progress);
            dmt_fb_promotion_check(record,cfg,cond,cal,branch,initial,plan);
            saveRecord(folder,p,'Design',d,record);
        end
        fprintf('Promotion cal %d %s | %s | %s\n',cal,branch,record.status,record.promotion_state);
        if any(strcmp(record.status,{'power_error','execution_error'}))
            failureID='DMT:FBPromotionDesign';
            if strcmp(record.status,'power_error'),failureID='DMT:FBPowerError';end
            error(failureID,'%s: %s\n%s', ...
                record.status,record.failure.identifier,record.failure.detail);
        end
        if ~strcmp(record.status,'accepted'),continue;end
        path='standard';
        if strcmp(record.promotion_state,'promotion_accepted'),path='promotion';end
        pathPlan=dmt_fb_promotion_plan_for(plan,branch,path);
        payloads(folder,p,cond,cal,branch,'ValidatedLoading',d,record.final,pathPlan);
    end
end
end

function initial=sharedCalibration(folder,p,a,cond,cal,plan)
initial=getRecord(folder,p,'Shared',a);
if isempty(initial)
    fprintf('Condition %d cal %d shared A0/B0\n',cond.condition_id,cal);
    initial=dmt_to_initial(p.cfg,cond,cal,plan);
    dmt_t2_check('Shared',initial,p.cfg,cond,cal,'',NaN,p.phase,plan,[]);
    saveRecord(folder,p,'Shared',a,initial);
end
end

function payloads(folder,p,cond,cal,label,scheme,d,design,plan)
for slot=1:p.cfg.payload_repeats
    j=(d-1)*p.cfg.payload_repeats+slot;
    if ~isempty(getRecord(folder,p,'Payload',j)),continue;end
    seeds=dmt_to_seed(plan,cond.condition_id,cal,scheme,0,'payload',slot);
    item=dmt_t2_payload(p.cfg,cond,design,seeds,p.symbols_per_slot);
    dmt_t2_check('Payload',item,p.cfg,cond,cal,scheme,slot,p.phase,plan,design);
    saveRecord(folder,p,'Payload',j,item);
    fprintf('Condition %d cal %d %s slot %d | actual=%d | power=%.9g | match=%d\n', ...
        cond.condition_id,cal,label,slot,item.symbols,item.power_actual,item.power_match);
end
end

function importReference(root,folder,p,layout)
path=fullfile(folder,'reuse_evidence.mat');
if isfile(path)
    saved=load(path,'checkpoint');frozen=saved.checkpoint;
    if ~strcmp(frozen.status,'reused_verified'),return;end
    if completeImport(folder,p,layout,frozen),return;end
else
    frozen=[];
end
[shared,designs,runs,evidence]=dmt_fb_reuse(root,p.historical_folder,p.cfg,p.plan);
if strcmp(evidence.status,'reused_verified')
    model=p.fit.historical_model;
    if ~strcmp(evidence.protocol_sha256,model.protocol_sha256) || ...
            ~strcmp(evidence.receipt_sha256,model.verification_receipt_sha256)
        evidence.status='incompatible';
        evidence.detail='Protocol or MATLAB receipt bytes differ from the nominated historical batch.';
    end
end
if isempty(frozen)
    dmt_v13_atomic_save(path,evidence);
else
    assert(strcmp(evidence.status,'reused_verified') && ...
        isequaln(evidence.frozen_record_hashes,frozen.frozen_record_hashes), ...
        'DMT:FBImportResume','Resume a partial import with the original historical directory.');
end
fprintf('Historical condition 9 | %s\n%s\n',evidence.status,evidence.detail);
if ~strcmp(evidence.status,'reused_verified'),return;end
ci=find([layout.conditions.condition_id]==9);
for i=1:numel(layout.calibrations)
    a=sharedIndex(ci,i,layout);
    importItem(folder,p,'Shared',a,shared{i});
    for s=1:layout.nSchemes
        oldD=(i-1)*layout.nSchemes+s;
        newD=(a-1)*layout.nSchemes+s;
        importItem(folder,p,'Design',newD,designs{oldD});
        for slot=1:layout.nRepeats
            oldP=(oldD-1)*layout.nRepeats+slot;
            newP=(newD-1)*layout.nRepeats+slot;
            importItem(folder,p,'Payload',newP,runs{oldP});
        end
    end
end
assert(completeImport(folder,p,layout,evidence),'DMT:FBImport','Historical import is incomplete.');
end

function yes=completeImport(folder,p,layout,evidence)
yes=true;
ci=find([layout.conditions.condition_id]==9);
proof=evidence.frozen_record_hashes;
for i=1:height(proof)
    kind=char(proof.kind(i));original=proof.index(i);
    switch kind
        case 'Shared'
            offset=(ci-1)*numel(layout.calibrations);
        case 'Design'
            offset=(ci-1)*numel(layout.calibrations)*layout.nSchemes;
        case 'Payload'
            offset=(ci-1)*numel(layout.calibrations)*layout.nSchemes*layout.nRepeats;
    end
    record=getRecord(folder,p,kind,offset+original);
    if isempty(record)
        yes=false;
    else
        assert(strcmp(dmt_v13_hash(record),proof.data_hash(i)), ...
            'DMT:FBImportHash','Imported %s %d differs from the audited source.',kind,original);
    end
end
end

function importItem(folder,p,kind,index,data)
saved=getRecord(folder,p,kind,index);
if isempty(saved)
    saveRecord(folder,p,kind,index,data);
else
    assert(isequaln(saved,data),'DMT:FBImportIdentity','Cannot replace %s %d with historical data.',kind,index);
end
end

function index=sharedIndex(condition,calibration,layout)
index=(condition-1)*numel(layout.calibrations)+calibration;
end

function logAttempt(cal,branch,event)
fprintf('Promotion cal %d %s | %s %d %s | symbols=%d | data=%.0f | noise=%.0f | %s\n', ...
    cal,branch,event.attempt_path,event.round,event.role,event.symbols, ...
    event.data_seed,event.noise_seed,event.status);
end

function record=getRecord(folder,p,kind,index)
record=dmt_t2_record('load',folder,p,kind,index,[]);
end

function saveRecord(folder,p,kind,index,data)
dmt_t2_record('save',folder,p,kind,index,data);
end

function reason=designReason(design)
reason=char(string(design.status));
if isfield(design,'reason'),reason=char(string(design.reason));end
end
