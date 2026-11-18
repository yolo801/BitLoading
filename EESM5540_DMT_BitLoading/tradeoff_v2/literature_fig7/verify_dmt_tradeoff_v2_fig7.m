function report = verify_dmt_tradeoff_v2_fig7(folder)
%VERIFY_DMT_TRADEOFF_V2_FIG7 Audit saved supplemental records without replay.
folder = char(string(folder));
root = fileparts(mfilename('fullpath'));
report = struct('output_dir',folder,'phase','formal','test_only',false, ...
    'valid',false,'data_integrity_valid',false,'acquisition_complete',false, ...
    'fit_passed',false,'link_preflight_passed',false,'detail','', ...
    'planned',30,'completed',0,'design_rejected',0,'power_error',0, ...
    'incomplete',30,'qualified',0,'scenario',table());
try
    loaded = load(fullfile(folder,'Protocol.mat'),'checkpoint');
    p = loaded.checkpoint;
    [cfg,plan,fit] = dmt_lit7_setup(root,fullfile(folder,'channel_evidence'));
    [manifest,sourceID] = dmt_source_manifest(root);
    assert(strcmp(p.study,'literature_fig7') && strcmp(p.phase,'formal') && ...
        ~p.test_only && strcmp(p.version,cfg.protocol) && ...
        strcmp(p.source_id,sourceID) && isequaln(p.source_manifest,manifest) && ...
        isequaln(p.cfg,cfg) && strcmp(p.config_id,dmt_v13_hash(cfg)) && ...
        isequaln(p.plan,plan) && strcmp(p.seed_id,dmt_v13_hash(plan)) && ...
        isequaln(p.fit,fit), ...
        'DMT:Fig7Identity','Use the saved supplemental protocol, channel evidence and source.');
    compareCSV(fullfile(folder,'source_manifest.csv'),manifest);
    compareCSV(fullfile(folder,'seed_plan.csv'),plan);
    layout = dmt_t2_layout(cfg,plan);
    assert(numel(layout.conditions)==1 && layout.conditions.P_target==1 && ...
        layout.conditions.q==8 && isequal(layout.calibrations,1:5) && ...
        layout.nSchemes==3 && layout.nRepeats==2 && layout.nRuns==report.planned && ...
        p.planned_payload_slots==layout.nRuns && ...
        cfg.payload_symbols==50000 && p.symbols_per_slot==cfg.payload_symbols, ...
        'DMT:Fig7Design','Formal acquisition must use the single frozen point and 30 planned slots.');
    report.fit_passed = fit.passed;
    assert(report.fit_passed,'DMT:Fig7FitGate','The frozen fit did not meet the channel gate.');

    mechanical = load(fullfile(folder,'mechanical_checks.mat'),'checkpoint');
    link = mechanical.checkpoint;
    tolerance = 5e-11;
    report.link_preflight_passed = isequal(link.passed,true) && ...
        isequal(link.fir_coefficients,cfg.h(:)) && isequal(link.active_k,cfg.k(:)) && ...
        link.fft_length==cfg.NFFT && link.cp_length==cfg.NCP && ...
        link.first_fft_sample==cfg.NCP+1 && link.adc_bits_selected==layout.conditions.q && ...
        isequal(link.check_chunk_symbols,[cfg.chunkSize 13]) && ...
        link.added_noise_energy==0 && link.clipped_samples==0 && ...
        link.clip_error_energy==0 && isequal(link.adc_bypassed,true) && ...
        link.convolution_max_abs_error<=tolerance && ...
        (numel(cfg.h)==1 || link.tail_reset_max_abs_difference>tolerance) && ...
        carrierBound(link.training_complex_response_error,cfg.k,tolerance) && ...
        carrierBound(link.check_max_complex_response_error,cfg.k,tolerance) && ...
        carrierBound(link.check_max_zf_error,cfg.k,tolerance) && ...
        carrierBound(link.error_bits,cfg.k,0) && ...
        isequal(link.tested_bits,2*sum(link.check_chunk_symbols)*ones(numel(cfg.k),1));
    assert(report.link_preflight_passed,'DMT:Fig7LinkGate','The MATLAB link preflight did not pass.');
    [shared,designs,runs] = readRecords(folder,p,layout);
    tables = dmt_t2_tables(cfg,p.phase,plan,shared,designs,runs);
    report.completed = sum(~cellfun(@isempty,runs));
    report.design_rejected = sum(tables.status.status=="design_rejected");
    report.power_error = sum(tables.status.status=="power_error");
    report.incomplete = sum(tables.status.status=="incomplete");
    assert(height(tables.status)==report.planned && ...
        report.completed==sum(tables.status.status=="completed") && ...
        report.completed+report.design_rejected+report.power_error+report.incomplete==report.planned, ...
        'DMT:Fig7Slots','The saved slot counts and statuses disagree.');
    report.scenario = tables.scenario;
    report.qualified = sum(tables.scenario.qualified);
    report.data_integrity_valid = true;
    report.acquisition_complete = report.incomplete==0 && report.power_error==0 && ...
        all(~cellfun(@isempty,shared)) && all(~cellfun(@isempty,designs));
    if ~report.acquisition_complete
        report.detail = 'Acquisition incomplete. Available checkpoint counts were audited.';
        return;
    end
    assert(~isfile(fullfile(folder,'failure_status.txt')), ...
        'DMT:Fig7FailedStudy','The acquisition directory contains a failure receipt.');
    exported = load(fullfile(folder,'tables.mat'),'checkpoint');
    assert(strcmp(exported.checkpoint.phase,p.phase) && ...
        isequaln(exported.checkpoint.tables,tables) && ...
        strcmp(exported.checkpoint.tables_hash,dmt_v13_hash(tables)), ...
        'DMT:Fig7Tables','The MAT export differs from the recomputed checkpoint tables.');
    names = fieldnames(tables);
    for j=1:numel(names)
        compareCSV(fullfile(folder,[names{j} '.csv']),tables.(names{j}));
    end
    assert(contains(fileread(fullfile(folder,'run.log')),'FIG7 ACQUISITION COMPLETE'), ...
        'DMT:Fig7CompletionLog','The MATLAB log lacks its acquisition end marker.');
    report.valid = true;
    report.detail = 'Frozen channel, MATLAB preflight, all formal slots and count exports audited.';
catch ME
    report.detail = getReport(ME,'extended','hyperlinks','off');
end
end

function valid = carrierBound(values,k,limit)
valid = isequal(size(values),[numel(k) 1]) && all(values>=0 & values<=limit);
end

function [shared,designs,runs] = readRecords(folder,p,layout)
cfg = p.cfg;
plan = p.plan;
cond = layout.conditions;
shared = cell(layout.nShared,1);
designs = cell(layout.nDesigns,1);
runs = cell(layout.nRuns,1);
noise = containers.Map('KeyType','double','ValueType','any');
for a=1:numel(layout.calibrations)
    c = layout.calibrations(a);
    initial = dmt_t2_record('load',folder,p,'Shared',a,[]);
    shared{a} = initial;
    if ~isempty(initial)
        dmt_t2_check('Shared',initial,cfg,cond,c,'',NaN,p.phase,plan,[]);
    end
    for s=1:layout.nSchemes
        d = (a-1)*layout.nSchemes+s;
        scheme = cfg.scheme_names{s};
        design = dmt_t2_record('load',folder,p,'Design',d,[]);
        designs{d} = design;
        if ~isempty(design)
            assert(~isempty(initial),'DMT:Fig7Parent','A design lacks its saved shared calibration.');
            dmt_t2_check('Design',design,cfg,cond,c,scheme,NaN,p.phase,plan,initial);
            if strcmp(design.status,'fixed_authorized')
                assert(~design.power_reused,'DMT:Fig7TXReuse','This point requires its own fixed power calibration.');
                auditNoisePair(design.Ar,noise);
            end
        end
        for slot=1:layout.nRepeats
            j = (d-1)*layout.nRepeats+slot;
            payload = dmt_t2_record('load',folder,p,'Payload',j,[]);
            runs{j} = payload;
            if ~isempty(payload)
                assert(~isempty(design),'DMT:Fig7Parent','A payload lacks its saved design.');
                dmt_t2_check('Payload',payload,cfg,cond,c,scheme,slot,p.phase,plan,design);
                auditNoisePair(payload,noise);
            end
        end
    end
end
records = dir(fullfile(folder,'checkpoints','*.mat'));
assert(numel(records)==sum(~cellfun(@isempty,[shared;designs;runs])), ...
    'DMT:Fig7ExtraRecord','Unexpected files found in the checkpoint directory.');
end

function auditNoisePair(item,noise)
seeds = item.seeds;
if strlength(string(seeds.noise_pair_key))==0, return; end
ns = seeds.noise_seed;
m = item.metrics;
signature = [m.sample_count,m.noise_sum,m.noise_sum_sq];
if isKey(noise,ns)
    assert(isequaln(noise(ns),signature),'DMT:Fig7PairedNoise', ...
        'Saved summaries disagree for one planned common-noise stream.');
else
    noise(ns) = signature;
end
end

function compareCSV(path,expected)
observed = readtable(path,'TextType','string','VariableNamingRule','preserve');
assert(height(observed)==height(expected) && ...
    isequal(observed.Properties.VariableNames,expected.Properties.VariableNames), ...
    'DMT:Fig7CSV','CSV schema or row count differs: %s',path);
if isempty(expected), return; end
for j=1:width(expected)
    name = expected.Properties.VariableNames{j};
    a = observed.(name);
    b = expected.(name);
    if isnumeric(b) || islogical(b)
        if isnumeric(a) || islogical(a)
            a = double(a);
        else
            a = lower(string(a));
            a(a=="true") = "1";
            a(a=="false") = "0";
            a = str2double(a);
        end
        b = double(b);
        finite = isfinite(b);
        integer = finite & b==fix(b);
        realValue = finite & ~integer;
        matches = isequaln(a(~finite),b(~finite)) && isequal(a(integer),b(integer)) && ...
            all(abs(a(realValue)-b(realValue))<=2e-12*max(1,abs(b(realValue))));
    else
        if isnumeric(a)
            missing = isnan(a);
            a = string(a);
            a(missing) = "";
        else
            a = string(a);
        end
        b = string(b);
        a(ismissing(a)) = "";
        b(ismissing(b)) = "";
        matches = isequal(a,b);
    end
    assert(matches,'DMT:Fig7CSV','CSV column %s differs in %s.',name,path);
end
end
