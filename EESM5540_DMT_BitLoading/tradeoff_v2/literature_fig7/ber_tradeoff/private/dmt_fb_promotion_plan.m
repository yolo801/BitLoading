function plan=dmt_fb_promotion_plan(cfg,phase)
%DMT_FB_PROMOTION_PLAN Fresh seed namespace, with noise pairing only by slot.
phase=validatestring(phase,{'preflight','formal'});
pointPlan=dmt_t2_plan(cfg,phase);
point=unique(pointPlan(pointPlan.P_target==1 & pointPlan.q==8, ...
    {'condition_id','P_target','q','calibration_id'}),'rows','sorted');
assert(all(point.condition_id==9) && ~isempty(point));
base=2000000000;
if strcmp(phase,'preflight'),base=2100000000;end
branches=["OriginalVerifiedLoading","PromotionFirstLoading"];
rows=cell(0,1);
for j=1:height(point)
    calibration=point.calibration_id(j);
    group=base+10000*calibration;
    append("Shared","shared",0,"initial_power",NaN,group+1,NaN,"");
    append("Shared","shared",0,"A0",NaN,group+11,group+12,"");
    append("Shared","shared",0,"B0",NaN,group+21,group+22,"");
    for b=1:numel(branches)
        branch=branches(b);
        branchBase=group+b*1000;
        if b==2
            attempt(branch,"promotion",1,branchBase+500);
        end
        for round=1:cfg.max_rounds
            attempt(branch,"standard",round,branchBase+100*round);
        end
        for slot=1:cfg.payload_repeats
            key=string(sprintf('fig7_promotion_%s_cal%d_slot%d',phase,calibration,slot));
            append(branch,"payload",0,"payload",slot,branchBase+600+slot,group+900+slot,key);
        end
    end
end
plan=vertcat(rows{:});
assert(sum(plan.role=="payload")==2*height(point)*cfg.payload_repeats && ...
    numel(unique(plan.data_seed))==height(plan));
assert(isempty(intersect(plan.data_seed,plan.noise_seed(isfinite(plan.noise_seed)))));
for seed=unique(plan.noise_seed(isfinite(plan.noise_seed))).'
    same=plan(plan.noise_seed==seed,:);
    if height(same)==1
        assert(same.noise_pair_key=="");
    else
        assert(height(same)==2 && all(same.role=="payload") && ...
            all(same.noise_pair_key~="") && numel(unique(same.noise_pair_key))==1 && ...
            numel(unique(same.scheme))==2 && numel(unique(same.calibration_id))==1 && ...
            numel(unique(same.payload_slot))==1);
    end
end
for key=unique(plan.noise_pair_key(plan.noise_pair_key~="")).'
    assert(numel(unique(plan.noise_seed(plan.noise_pair_key==key)))==1);
end
assert(all(plan.data_seed>base & plan.data_seed<base+100000) && ...
    all(plan.noise_seed(isfinite(plan.noise_seed))>base & ...
        plan.noise_seed(isfinite(plan.noise_seed))<base+100000));

    function attempt(branch,path,round,seed)
        append(branch,path,round,"power",NaN,seed+1,NaN,"");
        append(branch,path,round,"Ar",NaN,seed+11,seed+12,"");
        append(branch,path,round,"Dr",NaN,seed+21,seed+22,"");
    end

    function append(scheme,path,round,role,slot,ds,ns,noiseKey)
        rows{end+1,1}=table(string(phase),point.condition_id(j),point.P_target(j), ...
            point.q(j),calibration,scheme,round,role,slot,ds,ns,"",noiseKey,path, ...
            'VariableNames',{'phase','condition_id','P_target','q','calibration_id', ...
            'scheme','round','role','payload_slot','data_seed','noise_seed','data_pair_key', ...
            'noise_pair_key','attempt_path'});
    end
end
