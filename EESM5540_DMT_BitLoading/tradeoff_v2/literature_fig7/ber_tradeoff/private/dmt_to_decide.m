function decision = dmt_to_decide(cfg,M,supported,scheme,roundNumber)
%DMT_TO_DECIDE Pure complete-table state transition after one full D block.
% Mechanical tests may use synthetic support flags. Production supplies only
% flags from the actual independent D Wilson upper endpoints.
assert(isscalar(roundNumber) && roundNumber>=1 && ...
    roundNumber<=cfg.max_rounds && roundNumber==fix(roundNumber));
decision=struct('status','accepted','accepted',true,'terminal',true, ...
    'minimum_rejected',false,'next_M',M(:));
% Always enforce the Uniform invariant, even on an accepted table.
[nextM,minimumBlocked,~]=dmt_to_reduce(cfg,M,supported,scheme);
if all(supported),return;end
decision.accepted=false;
if minimumBlocked
    decision.status='no_accepted_profile_min_order';
    decision.minimum_rejected=true;decision.next_M=zeros(0,1);
elseif roundNumber==cfg.max_rounds
    decision.status='round_budget_exhausted';decision.next_M=zeros(0,1);
else
    decision.status='retest';decision.terminal=false;decision.next_M=nextM;
end
end
