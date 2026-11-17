function data=dmt_to_checkpoint(action,path,kind,key,meta,value)
%DMT_TO_CHECKPOINT Atomic complete-unit storage bound to source/config/plan.
if strcmp(action,'write')
    checkpoint=meta;checkpoint.kind=kind;checkpoint.key=key;
    checkpoint.data=value;checkpoint.data_hash=dmt_v13_hash(value);
    dmt_v13_atomic_save(path,checkpoint);data=value;return;
end
assert(strcmp(action,'read'));loaded=load(path,'checkpoint');cp=loaded.checkpoint;
fields={'kind','key','phase','config_id','source_id','seed_id','data','data_hash'};
assert(isstruct(cp) && isscalar(cp) && all(isfield(cp,fields)), ...
    'DMT:TradeoffCheckpoint','Incomplete checkpoint: %s',path);
assert(strcmp(cp.kind,kind) && strcmp(cp.key,key) && strcmp(cp.phase,meta.phase) && ...
    strcmp(cp.config_id,meta.config_id) && strcmp(cp.source_id,meta.source_id) && ...
    strcmp(cp.seed_id,meta.seed_id) && strcmp(cp.data_hash,dmt_v13_hash(cp.data)), ...
    'DMT:TradeoffIdentity','Checkpoint identity/content mismatch; retain file, use original code/config: %s',path);
data=cp.data;
end
