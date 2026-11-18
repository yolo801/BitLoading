function [records,timing] = dmt_vm_records(folder,p,action)
%DMT_VM_RECORDS Walk the same frozen indices for acquisition and audit.
acquire=strcmp(action,'acquire');
assert(acquire || strcmp(action,'audit'));
cfg=p.cfg;
plan=p.plan;
calibrations=unique(plan.calibration_id).';
nCal=numel(calibrations);
nSchemes=numel(cfg.scheme_names);
nRepeats=cfg.payload_repeats;
nShared=numel(cfg.conditions)*nCal;
nDesign=nShared*nSchemes;
nPayload=nDesign*nRepeats;
assert(nPayload==p.planned_payload_slots);
records=struct('initial',{cell(nShared,1)},'design',{cell(nDesign,1)}, ...
    'payload',{cell(nPayload,1)},'failure',{cell(nDesign,1)});
timing=struct('initial_seconds',0,'design_seconds',0,'payload_seconds',0);
noisePairs=containers.Map('KeyType','double','ValueType','any');
count=0;
for c=cfg.conditions
    for ic=1:nCal
        cal=calibrations(ic);
        a=(c.condition_id-1)*nCal+ic;
        initial=dmt_t2_record('load',folder,p,'Shared',a,[]);
        if isempty(initial) && acquire
            fprintf('Case %d swing %.2f cal %d | shared A0/B0\n',c.case_id,c.swing,cal);
            timer=tic;
            initial=dmt_vm_initial(cfg,c,cal,plan);
            dmt_vm_check('Shared',initial,cfg,c,cal,'',NaN,p.phase,plan,[]);
            dmt_t2_record('save',folder,p,'Shared',a,initial);
            timing.initial_seconds=timing.initial_seconds+toc(timer);
        elseif ~isempty(initial)
            dmt_vm_check('Shared',initial,cfg,c,cal,'',NaN,p.phase,plan,[]);
        end
        records.initial{a}=initial;
        count=count+~isempty(initial);
        for s=1:nSchemes
            scheme=cfg.scheme_names{s};
            d=(a-1)*nSchemes+s;
            design=dmt_t2_record('load',folder,p,'Design',d,[]);
            failed=dmt_t2_record('load',folder,p,'Failure',d,[]);
            if ~isempty(failed)
                assert(isempty(design) && ~isempty(initial) && ...
                    isequaln(failed.condition,c) && failed.calibration_id==cal && ...
                    strcmp(failed.scheme,scheme) && strcmp(failed.phase,p.phase) && ...
                    strcmp(failed.status,'power_error') && strlength(string(failed.reason))>0, ...
                    'DMT:VMDesignFailure','Saved design failure has inconsistent provenance.');
                if acquire,error('DMT:VMPowerError','Saved design power error: %s',failed.reason);end
            end
            if isempty(design) && isempty(failed) && acquire
                fprintf('Case %d swing %.2f cal %d %s | design\n',c.case_id,c.swing,cal,scheme);
                timer=tic;
                try
                    design=dmt_vm_design(cfg,c,cal,scheme,initial,plan);
                catch ME
                    if any(strcmp(ME.identifier,{'DMT:VMPowerUnreachable','DMT:VMPowerCalibration', ...
                            'DMT:TOPowerUnreachable','DMT:TOPowerCalibration'}))
                        failed=struct('condition',c,'calibration_id',cal,'scheme',scheme,'phase',p.phase, ...
                            'status','power_error','reason',getReport(ME,'extended','hyperlinks','off'));
                        dmt_t2_record('save',folder,p,'Failure',d,failed);
                    end
                    rethrow(ME);
                end
                dmt_vm_check('Design',design,cfg,c,cal,scheme,NaN,p.phase,plan,initial);
                dmt_t2_record('save',folder,p,'Design',d,design);
                timing.design_seconds=timing.design_seconds+toc(timer);
                fprintf('Case %d swing %.2f cal %d %s | %s (%s)\n', ...
                    c.case_id,c.swing,cal,scheme,design.status,design.reason);
            elseif ~isempty(design)
                assert(~isempty(initial),'DMT:VMRecordParent','Design lacks the shared A0/B0 record.');
                dmt_vm_check('Design',design,cfg,c,cal,scheme,NaN,p.phase,plan,initial);
            end
            records.design{d}=design;
            records.failure{d}=failed;
            count=count+~isempty(design)+~isempty(failed);
            authorized=~isempty(design) && strcmp(design.status,'accepted');
            for slot=1:nRepeats
                j=(d-1)*nRepeats+slot;
                measured=dmt_t2_record('load',folder,p,'Payload',j,[]);
                seeds=dmt_to_seed(plan,c.condition_id,cal,scheme,0,'payload',slot);
                if isempty(measured) && acquire && authorized
                    timer=tic;
                    measured=dmt_vm_payload(cfg,c,design,seeds,p.symbols_per_slot);
                    dmt_vm_payload_check(measured,cfg,c,design,seeds,p.symbols_per_slot);
                    dmt_t2_record('save',folder,p,'Payload',j,measured);
                    timing.payload_seconds=timing.payload_seconds+toc(timer);
                    fprintf('Case %d swing %.2f cal %d %s slot %d | %d | P=%.9g match=%d\n', ...
                        c.case_id,c.swing,cal,scheme,slot,measured.symbols, ...
                        measured.power_actual,measured.power_match);
                elseif ~isempty(measured)
                    assert(authorized,'DMT:VMRecordParent','Payload lacks an accepted design.');
                    dmt_vm_payload_check(measured,cfg,c,design,seeds,p.symbols_per_slot);
                end
                if ~isempty(measured),auditPairedNoise(measured);end
                records.payload{j}=measured;
                count=count+~isempty(measured);
            end
        end
    end
end
files=dir(fullfile(folder,'checkpoints','*.mat'));
assert(numel(files)==count,'DMT:VMCheckpointCount','Unexpected checkpoint files.');

    function auditPairedNoise(m)
        if strlength(string(m.seeds.noise_pair_key))==0,return;end
        key=m.seeds.noise_seed;
        metrics=m.metrics;
        values=[metrics.sample_count metrics.noise_sum metrics.noise_sum_sq];
        if isKey(noisePairs,key)
            assert(isequal(noisePairs(key),values),'DMT:VMNoisePair','Paired payload noise evidence differs.');
        else
            noisePairs(key)=values;
        end
    end
end
