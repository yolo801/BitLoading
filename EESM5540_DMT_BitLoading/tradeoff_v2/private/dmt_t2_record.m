function data = dmt_t2_record(action,folder,protocol,kind,index,data)
%DMT_T2_RECORD Save/read one atomic, phase-bound record without replay.
path=fullfile(folder,'checkpoints',sprintf('%s_%04d.mat',lower(kind),index));
identity = struct('kind',kind,'index',index,'phase',protocol.phase, ...
    'source_id',protocol.source_id,'config_id',protocol.config_id, ...
    'seed_id',protocol.seed_id);
if strcmp(action,'save')
    assert(~isfile(path),'DMT:V2Overwrite','Checkpoint already exists: %s',path);
    record=struct('identity',identity,'data',data,'data_hash',dmt_v13_hash(data));
    dmt_v13_atomic_save(path,record);
elseif strcmp(action,'load')
    data=[];
    if ~isfile(path),return;end
    saved=load(path,'checkpoint');record=saved.checkpoint;
    assert(isequaln(record.identity,identity) && strcmp(record.data_hash,dmt_v13_hash(record.data)), ...
        'DMT:V2Checkpoint','Checkpoint identity or hash mismatch: %s.',path);
    data=record.data;
else
    error('DMT:V2Action','Unknown checkpoint action.');
end
end
