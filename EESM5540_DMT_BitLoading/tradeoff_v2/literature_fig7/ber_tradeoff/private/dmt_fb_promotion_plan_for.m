function canonical=dmt_fb_promotion_plan_for(plan,branch,path)
%DMT_FB_PROMOTION_PLAN_FOR Adapt one isolated branch to the v2 role schema.
path=validatestring(path,{'shared','standard','promotion'});
mask=plan.scheme=="Shared";
if ~strcmp(path,'shared')
    branch=validatestring(branch,{'OriginalVerifiedLoading','PromotionFirstLoading'});
    assert(~strcmp(path,'promotion') || strcmp(branch,'PromotionFirstLoading'));
    mask=mask | (plan.scheme==string(branch) & ...
        (plan.attempt_path==string(path) | plan.attempt_path=="payload"));
end
canonical=removevars(plan(mask,:),'attempt_path');
canonical.scheme(canonical.scheme~="Shared")="ValidatedLoading";
end
