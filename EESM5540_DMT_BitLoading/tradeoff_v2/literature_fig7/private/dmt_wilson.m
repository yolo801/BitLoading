function [low, high] = dmt_wilson(errors, tested)
% Pointwise 95% binomial approximation; NOT simultaneous 95% coverage.
assert(all(tested(:) > 0) && all(errors(:) >= 0) && ...
    all(errors(:) <= tested(:)));
p = errors./tested;
z = 1.96;
d = 1 + z^2./tested;
center = (p + z^2./(2*tested))./d;
radius = z*sqrt(p.*(1-p)./tested + z^2./(4*tested.^2))./d;
low = max(0,center-radius);
high = min(1,center+radius);
end
