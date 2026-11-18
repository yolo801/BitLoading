function [report,tables] = dmt_fb_audit_records(folder,p)
%DMT_FB_AUDIT_RECORDS Verify checkpoints and derive all aggregate evidence.
report = struct('output_dir',folder,'study',p.study,'phase',p.phase, ...
    'test_only',p.test_only,'source_id',p.source_id,'valid',false, ...
    'data_integrity_valid',false,'acquisition_complete',false, ...
    'figures_valid',false,'planned',p.planned_payload_slots,'completed',0, ...
    'reused',0,'design_rejected',0,'power_error',0,'execution_error',0, ...
    'incomplete',p.planned_payload_slots,'qualified',0,'reuse_status','not_applicable', ...
    'detail','');
matFiles = dir(fullfile(folder,'checkpoints','*.mat'));
savedCount = 0;
pairing = containers.Map('KeyType','char','ValueType','any');
switch p.study
    case 'scan'
        [tables,terminal]=readScan();
        dmt_fb_audit_counts(p.cfg,tables);
        status=tables.status;
        report.qualified=sum(tables.scenario.qualified);
    case 'promotion'
        [tables,terminal]=readPromotion();
        dmt_fb_audit_counts(p.cfg,tables.original);
        dmt_fb_audit_counts(p.cfg,tables.promotion);
        status=[tables.original.status;tables.promotion.status];
        report.qualified=sum(tables.original.scenario.qualified)+sum(tables.promotion.scenario.qualified);
    otherwise
        error('DMT:FBAuditStudy','Unrecognized study %s.',p.study);
end
assert(numel(matFiles)==savedCount,'DMT:FBAuditCheckpointSet','Unexpected checkpoint files.');
report.completed=sum(status.status=="completed");
report.design_rejected=sum(status.status=="design_rejected");
report.power_error=sum(status.status=="power_error");
report.execution_error=sum(status.status=="execution_error");
report.incomplete=sum(status.status=="incomplete");
assert(height(status)==report.planned && report.completed+report.design_rejected+ ...
    report.power_error+report.execution_error+report.incomplete==report.planned, ...
    'DMT:FBAuditStatus','Reported slot categories do not partition the plan.');
report.data_integrity_valid=true;
report.acquisition_complete=terminal && report.incomplete==0 && ...
    report.power_error==0 && report.execution_error==0;
report.detail='Checkpoint envelopes, frozen joins, acquired counts and statuses rederived.';

    function [output,completeParents]=readScan()
        cfg=p.cfg;
        plan=p.plan;
        layout=dmt_t2_layout(cfg,plan);
        shared=cell(layout.nShared,1);
        designs=cell(layout.nDesigns,1);
        runs=cell(layout.nRuns,1);
        receipt=struct('status','not_applicable');
        if ~p.test_only
            reusePath=fullfile(folder,'reuse_evidence.mat');
            if isfile(reusePath)
                allSaved=load(reusePath,'checkpoint');
                receipt=allSaved.checkpoint;
                assert(any(strcmp(receipt.status,{'reused_verified','not_provided', ...
                    'missing_directory','incompatible'})),'DMT:FBReuseStatus','Unknown historical point state.');
            else
                assert(isempty(matFiles),'DMT:FBReuseMissing','A started scan lacks its historical reuse record.');
                receipt.status='not_acquired';
            end
        end
        report.reuse_status=receipt.status;
        didReuse=strcmp(receipt.status,'reused_verified');
        if didReuse, checkReuse(receipt,layout,p.fit.historical_model); end
        nCal=numel(layout.calibrations);
        for ci=1:numel(layout.conditions)
            cond=layout.conditions(ci);
            isReused=didReuse && cond.condition_id==9;
            for ca=1:nCal
                cal=layout.calibrations(ca);
                localShared=(ci-1)*nCal+ca;
                initial=read('Shared',localShared);
                shared{localShared}=initial;
                if isReused, compareHistory(receipt,'Shared',ca,initial); end
                if ~isempty(initial)
                    dmt_t2_check('Shared',initial,cfg,cond,cal,'',NaN,p.phase,plan,[]);
                end
                for s=1:layout.nSchemes
                    scheme=cfg.scheme_names{s};
                    localDesign=(localShared-1)*layout.nSchemes+s;
                    originalDesign=(ca-1)*layout.nSchemes+s;
                    design=read('Design',localDesign);
                    designs{localDesign}=design;
                    if isReused, compareHistory(receipt,'Design',originalDesign,design); end
                    if ~isempty(design)
                        assert(~isempty(initial),'DMT:FBAuditParent','Design lacks its shared calibration.');
                        dmt_t2_check('Design',design,cfg,cond,cal,scheme,NaN,p.phase,plan,initial);
                        if strcmp(design.status,'fixed_authorized')
                            auditPair(design.Ar);
                        end
                    end
                    for slot=1:layout.nRepeats
                        localRun=(localDesign-1)*layout.nRepeats+slot;
                        item=read('Payload',localRun);
                        runs{localRun}=item;
                        if isReused
                            index=(originalDesign-1)*layout.nRepeats+slot;
                            compareHistory(receipt,'Payload',index,item);
                        end
                        if ~isempty(item)
                            assert(~isempty(design),'DMT:FBAuditParent','Payload lacks its design.');
                            dmt_t2_check('Payload',item,cfg,cond,cal,scheme,slot,p.phase,plan,design);
                            auditPair(item);
                        end
                    end
                end
            end
        end
        output=dmt_t2_tables(cfg,p.phase,plan,shared,designs,runs);
        origin=repmat("new",height(output.status),1);
        origin(didReuse & output.status.condition_id==9)="reused_verified";
        output.status.data_source=origin;
        report.reused=sum(origin=="reused_verified" & output.status.status=="completed");
        output.scenario.P_actual_min=nan(height(output.scenario),1);
        for pt=1:height(output.scenario)
            relevant=output.status.condition_id==output.scenario.condition_id(pt) & ...
                output.status.scheme==output.scenario.scheme(pt);
            measured=output.status.P_actual(relevant & output.status.status=="completed");
            if ~isempty(measured),output.scenario.P_actual_min(pt)=min(measured);end
        end
        output.events=dmt_fb_audit_scan_events(cfg,layout,shared,designs,runs,didReuse);
        completeParents=all(~cellfun(@isempty,shared)) && all(~cellfun(@isempty,designs));
    end

    function [output,completeParents]=readPromotion()
        cfg=p.cfg;
        plan=p.plan;
        cond=table2struct(unique(plan(:,{'condition_id','P_target','q'}),'rows'));
        assert(isscalar(cond) && cond.condition_id==9 && cond.P_target==1 && cond.q==8);
        cals=unique(plan.calibration_id).';
        nCal=numel(cals);
        branches={'OriginalVerifiedLoading','PromotionFirstLoading'};
        shared=cell(nCal,1);
        designs=cell(nCal,2);
        runs=cell(nCal*cfg.payload_repeats,2);
        for a=1:nCal
            cal=cals(a);
            initial=read('Shared',a);
            shared{a}=initial;
            onePlan=dmt_fb_promotion_plan_for(plan,branches{1},'standard');
            if ~isempty(initial)
                dmt_t2_check('Shared',initial,cfg,cond,cal,'',NaN,p.phase,onePlan,[]);
            end
            for b=1:2
                d=(a-1)*2+b;
                record=read('Design',d);
                designs{a,b}=record;
                branch=branches{b};
                usePath='standard';
                if ~isempty(record)
                    assert(~isempty(initial),'DMT:FBAuditParent','Promotion design lacks shared A0/B0.');
                    dmt_fb_promotion_check(record,cfg,cond,cal,branch,initial,plan);
                    if strcmp(record.promotion_state,'promotion_accepted'),usePath='promotion';end
                end
                branchPlan=dmt_fb_promotion_plan_for(plan,branch,usePath);
                for slot=1:cfg.payload_repeats
                    item=read('Payload',(d-1)*cfg.payload_repeats+slot);
                    runs{(a-1)*cfg.payload_repeats+slot,b}=item;
                    if ~isempty(item)
                        assert(~isempty(record) && strcmp(record.status,'accepted') && ~isempty(record.final), ...
                            'DMT:FBAuditParent','Payload has no accepted branch configuration.');
                        dmt_t2_check('Payload',item,cfg,cond,cal,'ValidatedLoading',slot,p.phase,branchPlan,record.final);
                        auditPair(item);
                    end
                end
            end
        end
        output=dmt_fb_audit_promotion(cfg,p.phase,plan,branches,cond,cals,shared,designs,runs);
        completeParents=all(~cellfun(@isempty,shared)) && all(~cellfun(@isempty,designs(:)));
    end

    function data=read(kind,index)
        data=dmt_t2_record('load',folder,p,kind,index,[]);
        savedCount=savedCount+~isempty(data);
    end

    function auditPair(item)
        seeds=item.seeds;
        metrics=item.metrics;
        one(seeds.noise_pair_key,'noise',seeds.noise_seed, ...
            [metrics.sample_count,metrics.noise_sum,metrics.noise_sum_sq]);
        fields={'tx_sum','tx_sum_sq','drive_ac_sq_sum','lower_clip_count','upper_clip_count', ...
            'clip_error_sq_sum','useful_energy_sum','cp_energy_sum','tx_min','tx_max'};
        one(seeds.data_pair_key,'data',seeds.data_seed, ...
            {item.M,item.b,item.diagnostic_X,cellfun(@(n)metrics.(n),fields)});
    end

    function one(pairKey,domain,seed,signature)
        if strlength(string(pairKey))==0,return;end
        id=sprintf('%s_%s',domain,char(pairKey));
        signature={seed,signature};
        if isKey(pairing,id)
            assert(isequaln(pairing(id),signature),'DMT:FBAuditSeedPair','Mismatch for paired stream %s.',id);
        else
            pairing(id)=signature;
        end
    end
end

function checkReuse(evidence,layout,model)
check=evidence.verification;
assert(strcmp(evidence.source_id,'57fa231c55f2d7683fe1bc09cff206eb8bae7502d70f83692a6a2e22eaadde20') && ...
    strcmp(evidence.protocol_sha256,model.protocol_sha256) && ...
    strcmp(evidence.receipt_sha256,model.verification_receipt_sha256) && ...
    check.valid && check.data_integrity_valid && check.acquisition_complete && ...
    strcmp(check.phase,'formal') && ~check.test_only && check.planned==30 && check.completed==30 && ...
    any([layout.conditions.condition_id]==9),'DMT:FBReuseEvidence','Historical receipt cannot attest point 9.');
values={evidence.config_id,evidence.seed_id,evidence.protocol_sha256,evidence.receipt_sha256,evidence.source_manifest_sha256};
assert(all(cellfun(@hexDigest,values)),'DMT:FBReuseEvidence','Historical receipt lacks required identity hashes.');
t=evidence.frozen_record_hashes;
assert(height(t)==50 && sum(t.kind=="Shared")==5 && sum(t.kind=="Design")==15 && ...
    sum(t.kind=="Payload")==30 && all(arrayfun(@hexDigest,t.file_sha256)) && ...
    all(arrayfun(@hexDigest,t.data_hash)), ...
    'DMT:FBReuseEvidence','Historical checkpoint manifest has unexpected schema or coverage.');
end

function yes=hexDigest(value)
yes=~isempty(regexp(char(value),'^[0-9a-f]{64}$','once'));
end

function compareHistory(evidence,kind,index,data)
if isempty(data),return;end
t=evidence.frozen_record_hashes;
one=t(t.kind==string(kind) & t.index==index,:);
name=string(sprintf('checkpoints/%s_%04d.mat',lower(kind),index));
assert(height(one)==1 && one.relative_path==name && ...
    one.data_hash==string(dmt_v13_hash(data)),'DMT:FBReuseRecord','Imported %s differs from the verified original.',name);
end
