function seeds=dmt_to_seed(plan,conditionID,calID,scheme,round,role,slot)
%DMT_TO_SEED Exact one-row lookup; TX-only calibration has no noise stream.
mask=plan.condition_id==conditionID & plan.calibration_id==calID & ...
    plan.scheme==string(scheme) & plan.round==round & plan.role==string(role);
if isnan(slot),mask=mask & isnan(plan.payload_slot);else,mask=mask & plan.payload_slot==slot;end
row=plan(mask,:);assert(height(row)==1,'DMT:TradeoffSeed','One exact role seed required.');
seeds=table2struct(row);seeds.phase=char(seeds.phase);seeds.scheme=char(seeds.scheme);seeds.role=char(seeds.role);
end
