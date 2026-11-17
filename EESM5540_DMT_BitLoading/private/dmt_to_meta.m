function meta=dmt_to_meta(state,phase)
%DMT_TO_META Phase identity is independent of traversal/resume ordering.
plan=state.([phase '_plan']);
meta=struct('config_id',state.config_id,'source_id',state.source_id, ...
    'seed_id',dmt_v13_hash(plan),'phase',phase);
end
