function report = verify_dmt_tradeoff_v2(folder)
%VERIFY_DMT_TRADEOFF_V2 Read checkpoints/exports and recompute without sending.
folder=char(string(folder));
root=fileparts(mfilename('fullpath'));
report=struct('output_dir',folder,'phase','','test_only',false,'valid',false, ...
    'data_integrity_valid',false,'acquisition_complete',false,'detail','', ...
    'planned',0,'completed',0,'design_rejected',0,'power_error',0,'incomplete',0,'qualified',0);
try
    loaded=load(fullfile(folder,'Protocol.mat'),'checkpoint'); p=loaded.checkpoint;
    report.phase=p.phase;report.test_only=p.test_only;
    cfg=dmt_t2_config(); plan=dmt_t2_plan(cfg,p.phase);
    [manifest,sourceID]=dmt_source_manifest(root);
    assert(strcmp(p.version,cfg.protocol) && strcmp(p.source_id,sourceID) && ...
        isequaln(p.cfg,cfg) && isequaln(p.plan,plan) && isequaln(p.source_manifest,manifest) && ...
        strcmp(p.config_id,dmt_v13_hash(cfg)) && strcmp(p.seed_id,dmt_v13_hash(plan)) && ...
        p.test_only==strcmp(p.phase,'preflight'), ...
        'DMT:V2Identity','Use the original v2 source, configuration, and phase plan.');
    compareCSV(fullfile(folder,'source_manifest.csv'),manifest);
    compareCSV(fullfile(folder,'seed_plan.csv'),plan);
    layout=dmt_t2_layout(cfg,plan);
    assert(p.planned_payload_slots==layout.nRuns);
    expectedSymbols=cfg.payload_symbols;
    if p.test_only,expectedSymbols=cfg.preflight_payload_symbols;end
    assert(p.symbols_per_slot==expectedSymbols);
    [shared,designs,runs]=readRecords(folder,p,layout);
    tables=dmt_t2_tables(cfg,p.phase,plan,shared,designs,runs);
    report.planned=layout.nRuns;
    report.completed=sum(~cellfun(@isempty,runs));
    report.design_rejected=sum(tables.status.status=="design_rejected");
    report.power_error=sum(tables.status.status=="power_error");
    report.incomplete=report.planned-report.completed-report.design_rejected-report.power_error;
    assert(height(tables.status)==report.planned && report.incomplete>=0 && ...
        report.completed==sum(tables.status.status=="completed"));
    report.qualified=sum(tables.scenario.qualified);
    report.data_integrity_valid=true;
    report.acquisition_complete=report.incomplete==0 && report.power_error==0 && ...
        all(~cellfun(@isempty,shared)) && all(~cellfun(@isempty,designs));
    if ~report.acquisition_complete
        report.detail='Acquisition incomplete. Available checkpoint counts were audited.';
        return;
    end
    assert(~isfile(fullfile(folder,'failure_status.txt')),'DMT:V2FailedStudy', ...
        'Study has an original failure receipt.');
    mechanical=load(fullfile(folder,'mechanical_checks.mat'),'checkpoint');
    assert(mechanical.checkpoint.passed,'DMT:V2Mechanical','Mechanical check receipt did not pass.');
    export=load(fullfile(folder,'tables.mat'),'checkpoint');
    assert(strcmp(export.checkpoint.phase,p.phase) && ...
        isequaln(export.checkpoint.tables,tables) && ...
        strcmp(export.checkpoint.tables_hash,dmt_v13_hash(tables)), ...
        'DMT:V2Tables','MAT export differs from recomputed source tables.');
    names=fieldnames(tables);
    for j=1:numel(names)
        compareCSV(fullfile(folder,[names{j} '.csv']),tables.(names{j}));
    end
    auditFigures(folder,p.phase,cfg,tables);
    assert(contains(fileread(fullfile(folder,'run.log')),'TRADEOFF V2 ACQUISITION COMPLETE'));
    report.valid=true;report.detail='Checkpoint, counts, phase, tables, and figure identities verified.';
catch ME
    report.detail=getReport(ME,'extended','hyperlinks','off');
end
end

function [shared,designs,runs] = readRecords(folder,p,layout)
cfg=p.cfg;phase=p.phase;plan=p.plan;
shared=cell(layout.nShared,1);designs=cell(layout.nDesigns,1);runs=cell(layout.nRuns,1);
fixedPower=cell(numel(cfg.P_targets),numel(layout.calibrations),numel(cfg.fixed_M));
waveforms=containers.Map('KeyType','double','ValueType','any');
noises=containers.Map('KeyType','double','ValueType','any');
a=0;
for ci=1:numel(layout.conditions)
    cond=layout.conditions(ci);ip=find(cfg.P_targets==cond.P_target);
    for ic=1:numel(layout.calibrations)
        c=layout.calibrations(ic);a=a+1;
        initial=dmt_t2_record('load',folder,p,'Shared',a,[]);shared{a}=initial;
        if ~isempty(initial)
            dmt_t2_check('Shared',initial,cfg,cond,c,'',NaN,phase,plan,[]);
        end
        for s=1:layout.nSchemes
            d=(a-1)*layout.nSchemes+s;scheme=cfg.scheme_names{s};
            design=dmt_t2_record('load',folder,p,'Design',d,[]);designs{d}=design;
            if ~isempty(design)
                assert(~isempty(initial),'DMT:V2MissingParent','Design has no shared case checkpoint.');
                dmt_t2_check('Design',design,cfg,cond,c,scheme,NaN,phase,plan,initial);
                if s<=numel(cfg.fixed_M) && strcmp(design.status,'fixed_authorized')
                    earlier=fixedPower{ip,ic,s};
                    assert(isempty(earlier) || isequaln(earlier,design.power), ...
                        'DMT:V2TXReuse','Paired fixed strategy did not reuse its TX calibration.');
                    fixedPower{ip,ic,s}=design.power;
                    auditPairs(design.Ar,waveforms,noises);
                end
            end
            for slot=1:layout.nRepeats
                j=(d-1)*layout.nRepeats+slot;
                item=dmt_t2_record('load',folder,p,'Payload',j,[]);runs{j}=item;
                if isempty(item),continue;end
                assert(~isempty(design),'DMT:V2MissingParent','Payload has no design checkpoint.');
                dmt_t2_check('Payload',item,cfg,cond,c,scheme,slot,phase,plan,design);
                auditPairs(item,waveforms,noises);
            end
        end
    end
end
records=dir(fullfile(folder,'checkpoints','*.mat'));
assert(numel(records)==sum(~cellfun(@isempty,[shared;designs;runs])), ...
    'DMT:V2ExtraRecord','Unexpected checkpoint files found.');
end

function auditPairs(item,waveforms,noises)
metrics=item.metrics; seeds=item.seeds;
if strlength(string(seeds.data_pair_key))>0
    ds=seeds.data_seed;
    signature={item.M,item.b,item.diagnostic_X,metrics.tx_sum,metrics.tx_sum_sq, ...
        metrics.lower_clip_count,metrics.upper_clip_count};
    if isKey(waveforms,ds)
        assert(isequaln(waveforms(ds),signature),'DMT:V2PairedData','Observed paired TX summaries disagree.');
    else
        waveforms(ds)=signature;
    end
end
if strlength(string(seeds.noise_pair_key))>0
    ns=seeds.noise_seed;
    signature=[metrics.sample_count,metrics.noise_sum,metrics.noise_sum_sq];
    if isKey(noises,ns)
        assert(isequaln(noises(ns),signature),'DMT:V2PairedNoise','Observed paired noise summaries disagree.');
    else
        noises(ns)=signature;
    end
end
end

function compareCSV(path,expected)
a=readtable(path,'TextType','string','VariableNamingRule','preserve');
assert(height(a)==height(expected) && isequal(a.Properties.VariableNames,expected.Properties.VariableNames), ...
    'DMT:V2CSV','CSV schema or row count differs: %s',path);
if height(expected)==0,return;end
for j=1:width(expected)
    name=expected.Properties.VariableNames{j};
    observed=a.(name); wanted=expected.(name);
    if isnumeric(wanted) || islogical(wanted)
        if isnumeric(observed) || islogical(observed)
            observed=double(observed);
        else
            observed=lower(string(observed));
            observed(observed=="true")="1";observed(observed=="false")="0";
            observed=str2double(observed);
        end
        wanted=double(wanted);
        finite=isfinite(wanted);
        if all(wanted(finite)==fix(wanted(finite)))
            equal=isequaln(observed,wanted);
        else
            equal=isequaln(observed(~finite),wanted(~finite)) && ...
                all(abs(observed(finite)-wanted(finite))<=2e-12*max(1,abs(wanted(finite))));
        end
    else
        if isnumeric(observed)
            absent=isnan(observed);observed=string(observed);observed(absent)="";
        else
            observed=string(observed);
        end
        wanted=string(wanted);
        observed(ismissing(observed))="";wanted(ismissing(wanted))="";
        equal=isequal(observed,wanted);
    end
    assert(equal,'DMT:V2CSV','CSV column %s differs in %s.',name,path);
end
end

function auditFigures(folder,phase,cfg,tables)
manifest=readtable(fullfile(folder,'figure_manifest.csv'),'TextType','string','VariableNamingRule','preserve');
stems=["subcarrier_snr_bit_allocation_ber_margin";"supported_calibrations_power_adc"; ...
    "qualified_cycle_rate_measured_power"];
assert(isequal(sort(string(manifest.figure)),sort(stems)) && ...
    all(string(manifest.phase)==string(phase)) && ...
    all(string(manifest.data_hash)==string(dmt_v13_hash(tables))), ...
    'DMT:V2Plots','Figure plan or table identity differs.');
point=cfg.representative;
referenceRows=@(t)t.P_target==point.P_target & t.q==point.q & t.calibration_id==point.calibration_id;
hasReference=any(referenceRows(tables.snr)) || any(referenceRows(tables.profiles)) || ...
    any(referenceRows(tables.pool)) || any(referenceRows(tables.summary) & tables.summary.state~="incomplete");
hasRecords=~isempty(tables.profiles) || ~isempty(tables.seed) || ~isempty(tables.snr) || ...
    any(tables.summary.state~="incomplete");
planned=[hasReference;hasRecords;any(tables.scenario.qualified)];
for j=1:height(manifest)
    stem=char(manifest.figure(j));
    status=string(manifest.status(j));
    assert(planned(stems==string(stem))==(status=="written"), ...
        'DMT:V2PlotAvailability','Figure status differs from its saved data: %s.',stem);
    if status=="written"
        for format={'png','pdf','svg'}
            ext=format{1}; name=[ext '_sha256'];
            path=fullfile(folder,[stem '.' ext]);
            fid=fopen(path,'rb');assert(fid>=0,'DMT:V2MissingFigure','Missing %s.',path);
            closer=onCleanup(@()fclose(fid));
            raw=fread(fid,Inf,'*uint8');clear closer;
            assert(~isempty(raw) && strcmp(dmt_sha256(raw),char(manifest.(name)(j))), ...
                'DMT:V2FigureHash','Figure file differs: %s.',path);
        end
    else
        assert(status=="not_available" && ~ismissing(manifest.reason(j)) && ...
            strlength(string(manifest.reason(j)))>0,'DMT:V2FigureStatus','Invalid plot status.');
        for format={'png','pdf','svg'}
            assert(~isfile(fullfile(folder,[stem '.' format{1}])));
        end
    end
end
end
