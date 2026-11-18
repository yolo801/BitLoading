function layout = dmt_t2_layout(cfg,plan)
%DMT_T2_LAYOUT Fixed flattening order for plans, checkpoints, and tables.
conditionRows=unique(plan(:,{'condition_id','P_target','q'}),'rows');
conditions=table2struct(sortrows(conditionRows,'condition_id'));
layout=struct('conditions',conditions,'calibrations',unique(plan.calibration_id).', ...
    'nSchemes',numel(cfg.scheme_names),'nRepeats',cfg.payload_repeats);
layout.nShared=numel(conditions)*numel(layout.calibrations);
layout.nDesigns=layout.nShared*layout.nSchemes;
layout.nRuns=layout.nDesigns*layout.nRepeats;
assert(sum(plan.role=="payload")==layout.nRuns);
end
