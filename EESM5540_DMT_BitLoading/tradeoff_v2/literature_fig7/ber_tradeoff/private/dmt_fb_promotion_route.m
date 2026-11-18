function [state,runStandard,eligibility]=dmt_fb_promotion_route(branch,M,k,attempt,standard)
%DMT_FB_PROMOTION_ROUTE Pure policy for candidate-first and fallback routing.
branch=validatestring(branch,{'OriginalVerifiedLoading','PromotionFirstLoading'});
runStandard=false;
if isempty(M)
    state='no_initial_candidate';eligibility='no_initial_candidate';
    return;
end
assert(numel(M)==numel(k) && nnz(k==23)==1);
if strcmp(branch,'OriginalVerifiedLoading')
    eligibility='not_a_promotion_branch';
    state='original';
    runStandard=true;
elseif M(k==23)~=16
    eligibility='k23_is_qpsk';
    if M(k==23)==64,eligibility='k23_already_64qam';end
    state='not_eligible';
    runStandard=true;
else
    eligibility='eligible_k23_16qam';
    switch attempt
        case ''
            state='promotion_pending';
        case 'accepted'
            state='promotion_accepted';
        case 'promotion_rejected'
            runStandard=true;
            switch standard
                case ''
                    state='promotion_rejected_fallback_pending';
                case 'accepted'
                    state='promotion_rejected_fallback_accepted';
                otherwise
                    state='promotion_rejected_fallback_rejected';
            end
        case {'power_error','execution_error'}
            state=attempt;
        otherwise
            error('DMT:FBPromotionRoute','Unknown promotion attempt status: %s.',attempt);
    end
end
if ismember(string(standard),["power_error","execution_error"])
    state=standard;
end
end
