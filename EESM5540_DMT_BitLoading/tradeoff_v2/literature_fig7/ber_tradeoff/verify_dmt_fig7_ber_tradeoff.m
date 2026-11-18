function [report,tables]=verify_dmt_fig7_ber_tradeoff(folder,requireFigures)
%VERIFY_DMT_FIG7_BER_TRADEOFF Audit evidence and figures without simulation.
if nargin<2,requireFigures=true;end
assert(islogical(requireFigures) && isscalar(requireFigures));
folder=char(string(folder));
root=fileparts(mfilename('fullpath'));
tables=struct();
report=struct('output_dir',folder,'study','','phase','','test_only',false,'source_id','', ...
    'valid',false,'data_integrity_valid',false,'acquisition_complete',false, ...
    'figures_valid',false,'planned',0,'completed',0,'reused',0, ...
    'design_rejected',0,'power_error',0,'execution_error',0,'incomplete',0, ...
    'qualified',0,'reuse_status','not_applicable','detail','');
try
    saved=load(fullfile(folder,'Protocol.mat'),'checkpoint');
    p=saved.checkpoint;
    [cfg,plan,fit]=dmt_fb_setup(root,p.study,p.phase);
    [manifest,sourceID]=dmt_source_manifest(root);
    testOnly=strcmp(p.phase,'preflight');
    symbols=cfg.payload_symbols;
    if testOnly,symbols=cfg.preflight_payload_symbols;end
    assert(strcmp(p.version,'fig7_ber_tradeoff_v1') && strcmp(p.source_id,sourceID) && ...
        isequaln(p.source_manifest,manifest) && isequaln(p.cfg,cfg) && ...
        isequaln(p.fit,fit) && fit.passed && isequaln(p.plan,plan) && ...
        strcmp(p.config_id,dmt_v13_hash(cfg)) && strcmp(p.seed_id,dmt_v13_hash(plan)) && ...
        p.test_only==testOnly && p.symbols_per_slot==symbols && ...
        p.planned_payload_slots==sum(plan.role=="payload"),'DMT:FBAuditProtocol', ...
        'Protocol, source, fitted channel, recorded budget or frozen role streams differ.');
    checkArtifact(folder,'fit_summary.json',fit.historical_model.fit_summary_sha256);
    checkArtifact(folder,'historical_model.json',dmt_fb_filehash(fullfile(root,'evidence','historical_model.json')));
    [report,tables]=dmt_fb_audit_records(folder,p);
    report.symbols_per_slot=symbols;
    report.mechanical_sha256=dmt_fb_audit_gates(folder,p);
    if ~report.acquisition_complete
        report.detail='Available checkpoints audited. Acquisition is incomplete.';
        return;
    end
    if strcmp(report.reuse_status,'reused_verified')
        assert(report.reused==30,'DMT:FBAuditReuseBudget','Exactly 30 compatible slots must be imported.');
    end
    report.data_integrity_valid=false;
    dmt_fb_audit_exports(folder,p,tables,'verify');
    report.data_integrity_valid=true;
    marker=sprintf('FIG7 BER ACQUISITION COMPLETE | %s/%s | actual %d | rejected %d | planned %d', ...
        p.study,p.phase,report.completed,report.design_rejected,report.planned);
    assert(contains(fileread(fullfile(folder,'run.log')),marker), ...
        'DMT:FBAuditLog','Study log lacks its complete, count-matched acquisition marker.');
    if ~testOnly && requireFigures
        dmt_fb_graphics(folder,p.study,cfg,tables,'verify');
        report.figures_valid=true;
    end
    report.valid=true;
    report.detail='Frozen protocol, preflight gate, checkpoints and count-derived exports verified.';
    if report.figures_valid
        report.detail=[report.detail ' Figure data and output hashes verified.'];
    end
catch ME
    report.detail=getReport(ME,'extended','hyperlinks','off');
end
end

function checkArtifact(folder,name,hash)
assert(strcmp(dmt_fb_filehash(fullfile(folder,name)),hash),'DMT:FBAuditArtifact', ...
    'Frozen study evidence differs: %s.',name);
end
