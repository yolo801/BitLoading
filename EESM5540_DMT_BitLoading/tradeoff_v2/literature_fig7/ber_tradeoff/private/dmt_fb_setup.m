function [cfg,plan,fit] = dmt_fb_setup(root,study,phase)
% Reuse the published Fig. 7 fit and v2 physics without changing either.
parent = fileparts(root);
[upstream,upstreamID] = dmt_source_manifest(parent);
model = jsondecode(fileread(fullfile(root,'evidence','historical_model.json')));
assert(strcmp(upstreamID,model.source_id) && ...
    strcmp(upstreamID,'57fa231c55f2d7683fe1bc09cff206eb8bae7502d70f83692a6a2e22eaadde20'), ...
    'DMT:FBParentSource','Expected the frozen Fig. 7 sources at 004cc6d.');
for j=1:height(upstream)
    name = upstream.relative_path(j);
    if startsWith(name,"private/") && name~="private/dmt_t2_tables.m" && isfile(fullfile(root,name))
        assert(strcmp(dmt_fb_filehash(fullfile(root,name)),upstream.sha256(j)), ...
            'DMT:FBCoreChanged','Copied v2 implementation differs: %s',name);
    end
end
fitDir = fullfile(parent,'evidence');
assert(strcmp(dmt_fb_filehash(fullfile(fitDir,'fit_summary.json')),model.fit_summary_sha256), ...
    'DMT:FBModel','Frozen historical Fig. 7 fit differs.');
[cfg,~,fit] = dmt_lit7_setup(parent,fitDir);
fit.historical_model = model;
assert(fit.passed && isequal(cfg.h,model.fir_taps(:).') && ...
    numel(cfg.h)==9 && cfg.NCP==8 && cfg.P_peak==2 && cfg.rho==4 && ...
    cfg.noise_variance==1.0491e-4 && isequal(cfg.adc_range,[-.1 2.1]), ...
    'DMT:FBModel','Frozen physical settings or exact FIR differ.');
switch study
    case 'promotion'
        plan = dmt_fb_promotion_plan(cfg,phase);
        assert(all(plan.condition_id==9 & plan.P_target==1 & plan.q==8));
        slots = 20;
        if strcmp(phase,'preflight'),slots=4;end
    case 'scan'
        plan = dmt_t2_plan(cfg,phase);
        plan = plan(ismember(plan.condition_id,[5 6 8 9 11 12 14 15]),:);
        slots = 240;
        if strcmp(phase,'preflight'),slots=12;end
        if strcmp(phase,'formal')
            assert(isequal(unique(plan.condition_id).',[5 6 8 9 11 12 14 15]));
        end
    otherwise
        error('DMT:FBStudy','Unknown Fig. 7 study: %s.',study);
end
assert(sum(plan.role=="payload")==slots && cfg.payload_symbols==50000 && ...
    cfg.payload_repeats==2 && cfg.calibration_count==5, ...
    'DMT:FBPlan','Unexpected study plan or payload budget.');
end
