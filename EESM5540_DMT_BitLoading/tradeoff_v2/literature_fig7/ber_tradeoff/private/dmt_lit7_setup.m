function [cfg,plan,fit] = dmt_lit7_setup(root,fitDir)
%DMT_LIT7_SETUP Recompute the fit gate from the frozen raster extraction.
cfg=dmt_t2_config();
fit=jsondecode(fileread(fullfile(fitDir,'fit_summary.json')));
assert(strcmp(fit.digitized_file,'Fig7_digitized.csv') && ...
    strcmp(fit.provenance_file,'Fig7_provenance.json'),'DMT:Lit7Input','Unexpected source filenames.');
assert(strcmp(fileSHA(fullfile(fitDir,fit.digitized_file)),fit.digitized_sha256) && ...
    strcmp(fileSHA(fullfile(fitDir,fit.provenance_file)),fit.provenance_sha256), ...
    'DMT:Lit7Input','The digitization or provenance file differs from the fitted input.');

files=dir(fitDir);
files=files(~[files.isdir]);
names=sort(string({files.name}));
fit.evidence_files=reshape(names,[],1);
fit.evidence_sha256=strings(numel(names),1);
for j=1:numel(names)
    fit.evidence_sha256(j)=fileSHA(fullfile(fitDir,names(j)));
end
% Verify the copied private implementations against the frozen v2 source.
[parent,parentID]=dmt_source_manifest(fileparts(root));
expectedID='c68ae10ae98ce6d78b94fda5b18cb7bbb601ddc6ff4cebbd4a777c6c00580fc8';
assert(strcmp(parentID,expectedID),'DMT:Lit7V2Source', ...
    'This module requires the original v2 source at commit 418996d.');
same=startsWith(parent.relative_path,"private/") & ~startsWith(parent.relative_path,"private/dmt_lit7_");
present=arrayfun(@(name)isfile(fullfile(root,name)),parent.relative_path);
for j=find(same & present).'
    assert(strcmp(fileSHA(fullfile(root,parent.relative_path(j))),parent.sha256(j)), ...
        'DMT:Lit7Copy','Frozen v2 helper differs: %s',parent.relative_path(j));
end
fit.v2_source_id=parentID;

points=readtable(fullfile(fitDir,fit.digitized_file),'VariableNamingRule','preserve');
paperGHz=points.frequency_GHz;
normalized=points.normalized_dB;
assert(all(isfinite(paperGHz)) && all(diff(paperGHz)>0) && all(isfinite(normalized)) && ...
    max(abs(points.frequency_sim_MHz-paperGHz*(64/63)))<1e-8 && ...
    max(abs(points.amplitude_ratio-10.^(normalized/20)))<1e-8, ...
    'DMT:Lit7Input','Invalid frequency or normalized S21 samples.');
h=reshape(fit.taps,1,[]);
assert(cfg.Fs==64e6 && cfg.NFFT==64 && cfg.NCP==8 && isequal(cfg.k(:),(1:24).') && ...
    isreal(h) && all(isfinite(h)) && ismember(numel(h),[1 3 5 7 9]) && ...
    max(abs(h-fliplr(h)))<=1e-12 && abs(sum(h)-1)<=1e-12 && numel(h)-1<=cfg.NCP, ...
    'DMT:Lit7FIR','Geometry, FIR symmetry or DC/CP constraint failed.');
cfg.h=h;
paperFsGHz=63;
activeGHz=paperFsGHz*cfg.k(:)/cfg.NFFT;
assert(activeGHz(1)>=paperGHz(1) && activeGHz(end)<=paperGHz(end), ...
    'DMT:Lit7Coverage','Measured Fig. 7 coverage does not enclose all active carriers.');
activeMeasured=interp1(paperGHz,normalized,activeGHz,'linear');
activeModeled=firDb(activeGHz,paperFsGHz,h);
fit.matlab_active_error_dB=activeModeled-activeMeasured;
fit.matlab_covered_rms_dB=rmsError(firDb(paperGHz,paperFsGHz,h)-normalized);
fit.matlab_active_rms_dB=rmsError(fit.matlab_active_error_dB);
fit.matlab_active_max_dB=max(abs(fit.matlab_active_error_dB));
assert(abs(fit.matlab_active_rms_dB-fit.active_rms_error_dB)<1e-6 && ...
    abs(fit.matlab_active_max_dB-fit.active_max_abs_error_dB)<1e-6 && ...
    abs(fit.matlab_covered_rms_dB-fit.covered_rms_error_dB)<1e-6, ...
    'DMT:Lit7FitEvidence','Exported fit discrepancies differ from recomputation.');
% Lower bound the full-band sampled minimum using the centered response's
% derivative bound so a zero between sampling points cannot evade the check.
activeGrid=linspace(activeGHz(1),activeGHz(end),4097).';
offset=-(numel(h)-1)/2:(numel(h)-1)/2;
linearResponse=cos(2*pi*activeGrid/paperFsGHz*offset)*h(:);
slopeBound=(2*pi/paperFsGHz)*sum(abs(offset.*h));
minGainBound=min(linearResponse)-slopeBound*(activeGrid(2)-activeGrid(1))/2;
fit.matlab_min_active_amplitude_bound=minGainBound;
fit.passed=logical(fit.passed) && fit.matlab_active_rms_dB<=1 && ...
    fit.matlab_active_max_dB<=2 && minGainBound>0;

originalPlan=dmt_t2_plan(cfg,'formal');
plan=originalPlan(originalPlan.P_target==1 & originalPlan.q==8,:);
layout=dmt_t2_layout(cfg,plan);
assert(isscalar(layout.conditions) && layout.conditions.condition_id==9 && ...
    isequal(layout.calibrations,1:5) && layout.nRuns==30 && cfg.payload_symbols==50000, ...
    'DMT:Lit7Plan','Frozen v2 plan for P=1, q=8 differs.');
end

function db=firDb(f,paperFsGHz,h)
response=exp(-2i*pi*f(:)/paperFsGHz*(0:numel(h)-1))*h(:);
db=20*log10(abs(response));
end

function value=rmsError(errorDb)
value=sqrt(mean(errorDb.^2));
end

function hash=fileSHA(path)
fid=fopen(path,'rb');
assert(fid>=0,'DMT:Lit7Evidence','Cannot read %s.',path);
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
hash=dmt_sha256(fread(fid,Inf,'*uint8'));
end
