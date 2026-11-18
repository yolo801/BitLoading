function result = run_dmt_tradeoff_v2(phase)
%RUN_DMT_TRADEOFF_V2 Run a single explicitly selected phase in a new directory.
if nargin<1, phase='preflight'; end
phase=validatestring(phase,{'preflight','formal'});
root=fileparts(mfilename('fullpath'));
cfg=dmt_t2_config(); plan=dmt_t2_plan(cfg,phase);
layout=dmt_t2_layout(cfg,plan);
nSymbols=cfg.payload_symbols;
if strcmp(phase,'preflight'), nSymbols=cfg.preflight_payload_symbols; end
[manifest,sourceID]=dmt_source_manifest(root);
base=fullfile(root,'results');
if ~isfolder(base), mkdir(base); end
[~,tag]=fileparts(tempname(base));
folder=fullfile(base,['tradeoff_v2_' phase '_' tag]);
assert(~isfolder(folder),'DMT:V2Directory','Study directory already exists.');
mkdir(folder);mkdir(fullfile(folder,'checkpoints'));
lock=dmt_study_lock(folder); %#ok<NASGU>
diary(fullfile(folder,'run.log'));
cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('tradeoff_v2 %s | planned payload slots=%d | symbols/slot=%d | %s\n', ...
    phase,layout.nRuns,nSymbols,folder);
shared=cell(layout.nShared,1); designs=cell(layout.nDesigns,1); runs=cell(layout.nRuns,1);
fixedPower=cell(numel(cfg.P_targets),numel(layout.calibrations),numel(cfg.fixed_M));
location='startup';
try
    protocol=struct('version',cfg.protocol,'phase',phase,'test_only',strcmp(phase,'preflight'), ...
        'cfg',cfg,'config_id',dmt_v13_hash(cfg),'plan',plan,'seed_id',dmt_v13_hash(plan), ...
        'source_id',sourceID,'source_manifest',manifest,'environment',dmt_t2_runtime(root), ...
        'planned_payload_slots',layout.nRuns,'symbols_per_slot',nSymbols);
    dmt_v13_atomic_save(fullfile(folder,'Protocol.mat'),protocol);
    writetable(manifest,fullfile(folder,'source_manifest.csv'));
    writetable(plan,fullfile(folder,'seed_plan.csv'));
    location='mechanical checks';
    mechanical=dmt_t2_checks(cfg,phase,plan);
    dmt_v13_atomic_save(fullfile(folder,'mechanical_checks.mat'),mechanical);
    a=0;
    for ci=1:numel(layout.conditions)
        condition=layout.conditions(ci);
        ip=find(cfg.P_targets==condition.P_target);
        for ic=1:numel(layout.calibrations)
            c=layout.calibrations(ic);a=a+1;
            location=sprintf('condition %d cal %d shared A0/B0',condition.condition_id,c);
            initial=dmt_to_initial(cfg,condition,c,plan);
            dmt_t2_check('Shared',initial,cfg,condition,c,'',NaN,phase,plan,[]);
            shared{a}=dmt_t2_record('save',folder,protocol,'Shared',a,initial);
            for s=1:layout.nSchemes
                scheme=cfg.scheme_names{s}; d=(a-1)*layout.nSchemes+s;
                location=sprintf('condition %d cal %d %s design',condition.condition_id,c,scheme);
                reused=[];
                if s<=numel(cfg.fixed_M), reused=fixedPower{ip,ic,s}; end
                try
                    design=dmt_t2_design(cfg,condition,c,scheme,initial,plan,reused);
                catch designError
                    if any(strcmp(designError.identifier,{'DMT:TOPowerUnreachable','DMT:TOPowerCalibration'}))
                        failed=struct('condition',condition,'calibration_id',c,'phase',phase, ...
                            'scheme',scheme,'status','power_error','M',zeros(0,1), ...
                            'reason',getReport(designError,'extended','hyperlinks','off'));
                        dmt_t2_check('Design',failed,cfg,condition,c,scheme,NaN,phase,plan,initial);
                        designs{d}=dmt_t2_record('save',folder,protocol,'Design',d,failed);
                    end
                    rethrow(designError);
                end
                dmt_t2_check('Design',design,cfg,condition,c,scheme,NaN,phase,plan,initial);
                designs{d}=dmt_t2_record('save',folder,protocol,'Design',d,design);
                fprintf('%s | %s\n',location,design.status);
                if s<=numel(cfg.fixed_M) && strcmp(design.status,'fixed_authorized')
                    fixedPower{ip,ic,s}=design.power;
                end
                if ~any(strcmp(design.status,{'fixed_authorized','accepted'})), continue; end
                for slot=1:layout.nRepeats
                    j=(d-1)*layout.nRepeats+slot;
                    location=sprintf('condition %d cal %d %s payload %d',condition.condition_id,c,scheme,slot);
                    seeds=dmt_to_seed(plan,condition.condition_id,c,scheme,0,'payload',slot);
                    meas=dmt_t2_payload(cfg,condition,design,seeds,nSymbols);
                    dmt_t2_check('Payload',meas,cfg,condition,c,scheme,slot,phase,plan,design);
                    runs{j}=dmt_t2_record('save',folder,protocol,'Payload',j,meas);
                    fprintf('%s | actual=%d | power_match=%d\n',location,meas.symbols,meas.power_match);
                end
            end
        end
    end
    location='rebuild tables and export figures';
    [~,currentID]=dmt_source_manifest(root);
    assert(strcmp(sourceID,currentID),'DMT:V2SourceChanged','Source changed during acquisition.');
    tables=dmt_t2_export(folder,cfg,phase,plan,shared,designs,runs);
    dmt_t2_plot(cfg,phase,tables,folder);
    fprintf('TRADEOFF V2 ACQUISITION COMPLETE | %s | %d/%d transmitted\n',phase, ...
        sum(~cellfun(@isempty,runs)),layout.nRuns);
    diary('off');diary(fullfile(folder,'run.log'));
    location='read-only verification';
    result=verify_dmt_tradeoff_v2(folder);
    dmt_v13_atomic_save(fullfile(folder,'verification_receipt.mat'),result);
    assert(result.valid,'DMT:V2Verification','V2 verification failed: %s',result.detail);
catch ME
    if exist('protocol','var') && ~isfile(fullfile(folder,'tables.mat'))
        try
            dmt_t2_export(folder,cfg,phase,plan,shared,designs,runs);
        catch exportError
            fprintf(2,'Partial export error: %s\n',exportError.message);
        end
    end
    writeFailure(folder,location,ME);
    fprintf(2,'First failed stage: %s. Evidence directory: %s\n',location,folder);
    rethrow(ME);
end
end

function writeFailure(folder,location,exception)
assert(~isfile(fullfile(folder,'failure_status.txt')));
fid=fopen(fullfile(folder,'failure_status.txt'),'w','n','UTF-8');
assert(fid>=0,'DMT:V2FailureReceipt','Cannot write failure receipt.');
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
classification='execution_error';
if strcmp(location,'read-only verification'), classification='verification_error'; end
if any(strcmp(exception.identifier,{'DMT:TOPowerUnreachable','DMT:TOPowerCalibration'}))
    classification='power_calibration_error';
end
fprintf(fid,'Class: %s\nStage: %s\nIdentifier: %s\n%s\n',classification,location, ...
    exception.identifier,getReport(exception,'extended','hyperlinks','off'));
end
