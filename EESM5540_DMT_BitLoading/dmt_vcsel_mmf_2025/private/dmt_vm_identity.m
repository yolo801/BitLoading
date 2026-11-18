function dmt_vm_identity(root,folder,p)
% Confirm the saved transport, fit, source, budgets and seed plan.
[cfg,fit]=dmt_vm_config(fullfile(folder,'channel_evidence'));
[manifest,sourceID]=dmt_source_manifest(root);
phase=validatestring(p.phase,{'preflight','pilot','formal'});
plan=table();
budget=0;
n=0;
if ~strcmp(phase,'preflight')
    plan=dmt_vm_plan(cfg,phase);
    budget=sum(plan.role=="payload");
    n=cfg.pilot_payload_symbols;
    if strcmp(phase,'formal'),n=cfg.payload_symbols;end
end
assert(strcmp(p.version,cfg.protocol) && ...
    p.test_only==~strcmp(phase,'formal') && p.planned_payload_slots==budget && p.symbols_per_slot==n && ...
    isequaln(cfg,p.cfg) && isequaln(fit,p.fit) && strcmp(p.source_id,sourceID) && ...
    isequaln(manifest,p.source_manifest) && isequaln(p.plan,plan) && ...
    strcmp(p.config_id,dmt_v13_hash(cfg)) && strcmp(p.seed_id,dmt_v13_hash(plan)), ...
    'DMT:VMIdentity','Use the original source, channel and frozen protocol when reading this run.');
dmt_fb_audit_csv(fullfile(folder,'source_manifest.csv'),manifest);
if ~isempty(plan),dmt_fb_audit_csv(fullfile(folder,'seed_plan.csv'),plan);end
end
