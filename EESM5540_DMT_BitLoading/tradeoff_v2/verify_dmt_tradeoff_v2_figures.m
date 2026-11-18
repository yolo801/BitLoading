function report = verify_dmt_tradeoff_v2_figures(folder)
%VERIFY_DMT_TRADEOFF_V2_FIGURES Audit saved figure artifacts without writing.
% This result covers the figure manifest, saved table hash and figure files.
% Use verify_dmt_tradeoff_v2 for the complete protocol/checkpoint audit.
folder=char(string(folder));
protocolFile=load(fullfile(folder,'Protocol.mat'),'checkpoint');
protocol=protocolFile.checkpoint;
snapshotFile=load(fullfile(folder,'tables.mat'),'checkpoint');
snapshot=snapshotFile.checkpoint;
cfg=dmt_t2_config();
assert(strcmp(protocol.version,cfg.protocol) && isequaln(protocol.cfg,cfg) && ...
    strcmp(protocol.config_id,dmt_v13_hash(cfg)) && strcmp(snapshot.phase,protocol.phase), ...
    'DMT:V2FigureProtocol','Saved figure tables do not match the v2 configuration and phase.');
assert(strcmp(snapshot.tables_hash,dmt_v13_hash(snapshot.tables)), ...
    'DMT:V2FigureTables','Saved figure table content hash does not match.');
info=dmt_t2_audit_figures(folder,protocol.phase,cfg,snapshot.tables);
report=struct('phase',protocol.phase,'test_only',protocol.test_only, ...
    'figure_audit_passed',true,'manifest_info',info);
end
