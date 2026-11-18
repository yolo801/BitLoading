function [state,berState,lower,upper]=dmt_t2_adjudicate(cfg,errors,tested,complete,matched)
%DMT_T2_ADJUDICATE Apply the strict per-carrier criterion to observed counts.
lower=[];upper=[];
if ~complete
    state="incomplete";
    berState="incomplete";
    return;
end
assert(iscolumn(errors) && isequal(size(errors),size(tested)) && ...
    all(isfinite(errors) & isfinite(tested) & errors==fix(errors) & tested==fix(tested) & ...
    errors>=0 & tested>0 & errors<=tested), ...
    'DMT:V2CountIdentity','Expected observed nonnegative integer counts with positive tested bits.');
z=1.96;
p=errors./tested;
d=1+z^2./tested;
center=(p+z^2./(2*tested))./d;
radius=z*sqrt(p.*(1-p)./tested+z^2./(4*tested.^2))./d;
lower=max(0,center-radius);
upper=min(1,center+radius);
berState="inconclusive";
if any(lower>cfg.targetBER)
    berState="ber_failed";
elseif all(upper<cfg.targetBER)
    berState="supported";
end
state=berState;
if ~matched,state="power_mismatch";end
end
