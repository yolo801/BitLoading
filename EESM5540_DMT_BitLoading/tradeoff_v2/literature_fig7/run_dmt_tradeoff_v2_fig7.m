function result = run_dmt_tradeoff_v2_fig7(varargin)
%RUN_DMT_TRADEOFF_V2_FIG7 Refit gate, production preflight, then one v2 point.
args=inputParser;
addParameter(args,'BaselineDirectory','',@(x)ischar(x)||(isstring(x)&&isscalar(x)));
parse(args,varargin{:});
baselineDir=char(args.Results.BaselineDirectory);
root=fileparts(mfilename('fullpath'));
base=fullfile(root,'results');
if ~isfolder(base),mkdir(base);end
[~,tag]=fileparts(tempname(base));
folder=fullfile(base,['tradeoff_v2_fig7_' tag]);
assert(~isfolder(folder),'DMT:Lit7Directory','Study directory already exists.');
mkdir(folder);
mkdir(fullfile(folder,'checkpoints'));
lock=dmt_study_lock(folder); %#ok<NASGU>
logFile=fullfile(folder,'run.log');
diary(logFile);
closer=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('Fig. 7 literature-response supplement | P=1.0 | ADC=8 | planned 30 x 50000 | %s\n',folder);

phase='formal';
completed=0;
rejected=0;
stage='freeze channel fit and original v2 condition';
try
    evidenceDir=fullfile(folder,'channel_evidence');
    [ok,why]=copyfile(fullfile(root,'evidence'),evidenceDir);
    assert(ok,'DMT:Lit7Evidence','Cannot freeze fit evidence: %s',why);
    [cfg,plan,fit]=dmt_lit7_setup(root,evidenceDir);
    layout=dmt_t2_layout(cfg,plan);
    cond=layout.conditions;
    [manifest,sourceID]=dmt_source_manifest(root);
    writetable(manifest,fullfile(folder,'source_manifest.csv'));
    writetable(plan,fullfile(folder,'seed_plan.csv'));
    fprintf('Fit gate | active RMS %.6f dB | active max %.6f dB | pass=%d\n', ...
        fit.matlab_active_rms_dB,fit.matlab_active_max_dB,fit.passed);
    assert(fit.passed,'DMT:Lit7FitGate','FIR fit gate failed before any payload.');
    stage='MATLAB environment and source resolution';
    protocol=struct('study','literature_fig7','version',cfg.protocol,'phase',phase,'test_only',false, ...
        'cfg',cfg,'config_id',dmt_v13_hash(cfg),'plan',plan,'seed_id',dmt_v13_hash(plan), ...
        'source_id',sourceID,'source_manifest',manifest,'environment',dmt_t2_runtime(root), ...
        'planned_payload_slots',layout.nRuns,'symbols_per_slot',cfg.payload_symbols,'fit',fit);
    dmt_v13_atomic_save(fullfile(folder,'Protocol.mat'),protocol);
    stage='production noiseless link preflight';
    link=dmt_lit7_check_link(cfg);
    dmt_v13_atomic_save(fullfile(folder,'mechanical_checks.mat'),link);
    writeText(fullfile(folder,'mechanical_checks.json'),jsonencode(link,'PrettyPrint',true));
    fprintf('MATLAB link preflight pass=%d, maximum ZF error %.3g\n',link.passed,max(link.check_max_zf_error));
    assert(link.passed,'DMT:Lit7LinkGate','Production link preflight failed before any payload.');

    shared=cell(layout.nShared,1);
    designs=cell(layout.nDesigns,1);
    runs=cell(layout.nRuns,1);
    for a=1:layout.nShared
        c=layout.calibrations(a);
        stage=sprintf('calibration %d shared A0/B0',c);
        initial=dmt_to_initial(cfg,cond,c,plan);
        dmt_t2_check('Shared',initial,cfg,cond,c,'',NaN,phase,plan,[]);
        shared{a}=dmt_t2_record('save',folder,protocol,'Shared',a,initial);
        for s=1:layout.nSchemes
            scheme=cfg.scheme_names{s};
            d=(a-1)*layout.nSchemes+s;
            stage=sprintf('calibration %d %s design',c,scheme);
            try
                design=dmt_t2_design(cfg,cond,c,scheme,initial,plan,[]);
            catch designError
                if any(strcmp(designError.identifier,{'DMT:TOPowerUnreachable','DMT:TOPowerCalibration'}))
                    failure=struct('condition',cond,'calibration_id',c,'phase',phase, ...
                        'scheme',scheme,'status','power_error','M',zeros(0,1), ...
                        'reason',getReport(designError,'extended','hyperlinks','off'));
                    dmt_t2_check('Design',failure,cfg,cond,c,scheme,NaN,phase,plan,initial);
                    designs{d}=dmt_t2_record('save',folder,protocol,'Design',d,failure);
                end
                rethrow(designError);
            end
            dmt_t2_check('Design',design,cfg,cond,c,scheme,NaN,phase,plan,initial);
            designs{d}=dmt_t2_record('save',folder,protocol,'Design',d,design);
            fprintf('%s | %s\n',stage,design.status);
            if ~any(strcmp(design.status,{'fixed_authorized','accepted'}))
                rejected=rejected+layout.nRepeats;
                continue;
            end
            for slot=1:layout.nRepeats
                stage=sprintf('calibration %d %s payload %d',c,scheme,slot);
                j=(d-1)*layout.nRepeats+slot;
                seeds=dmt_to_seed(plan,cond.condition_id,c,scheme,0,'payload',slot);
                measured=dmt_t2_payload(cfg,cond,design,seeds,cfg.payload_symbols);
                dmt_t2_check('Payload',measured,cfg,cond,c,scheme,slot,phase,plan,design);
                runs{j}=dmt_t2_record('save',folder,protocol,'Payload',j,measured);
                completed=completed+1;
                fprintf('%s | actual=%d | power_match=%d\n',stage,measured.symbols,measured.power_match);
            end
        end
    end
    stage='rebuild tables from exact recorded counts';
    [~,currentID]=dmt_source_manifest(root);
    assert(strcmp(sourceID,currentID),'DMT:Lit7SourceChanged','Supplement source changed during acquisition.');
    tables=dmt_t2_export(folder,cfg,phase,plan,shared,designs,runs);
    fprintf('FIG7 ACQUISITION COMPLETE | %d transmitted | %d normal design rejection | 30 planned\n', ...
        completed,rejected);
    diary('off');
    diary(logFile);
    stage='read-only acquisition verification';
    result=verify_dmt_tradeoff_v2_fig7(folder);
    dmt_v13_atomic_save(fullfile(folder,'verification_receipt.mat'),result);
    assert(result.valid,'DMT:Lit7Verification','Acquisition audit failed: %s',result.detail);
    fprintf('Fig. 7 acquisition audit | valid=%d\n',result.valid);
catch ME
    if exist('runs','var') && ~isfile(fullfile(folder,'tables.mat'))
        try
            dmt_t2_export(folder,cfg,phase,plan,shared,designs,runs);
        catch exportError
            fprintf(2,'Partial table export: %s\n',exportError.message);
        end
    end
    details=sprintf('Stage: %s\nPlanned: 30\nCompleted: %d\nNormal design rejection: %d\nUnfinished: %d\n%s\n', ...
        stage,completed,rejected,30-completed-rejected,getReport(ME,'extended','hyperlinks','off'));
    writeText(fullfile(folder,'failure_status.txt'),details);
    fprintf(2,'%sEvidence directory: %s\n',details,folder);
    rethrow(ME);
end

try
    baseline=dmt_lit7_baseline(fileparts(root),baselineDir,cfg,plan);
    dmt_v13_atomic_save(fullfile(folder,'baseline_verification.mat'),rmfield(baseline,'tables'));
    result.comparison=dmt_lit7_compare(folder,baseline,cfg,tables);
    dmt_v13_atomic_save(fullfile(folder,'comparison_receipt.mat'),result.comparison);
    fprintf('Fig. 7 supplement complete | baseline status=%s | %s\n',baseline.status,folder);
catch ME
    writeText(fullfile(folder,'comparison_failure_status.txt'),getReport(ME,'extended','hyperlinks','off'));
    fprintf(2,'Acquisition is audited. Comparison failed in %s: %s\n',folder,ME.message);
    rethrow(ME);
end
end

function writeText(path,data)
fid=fopen(path,'w','n','UTF-8');
assert(fid>=0,'DMT:Lit7Evidence','Cannot write %s.',path);
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',data);
end
