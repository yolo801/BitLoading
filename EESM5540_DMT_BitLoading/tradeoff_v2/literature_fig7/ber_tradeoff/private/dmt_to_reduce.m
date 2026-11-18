function [nextM,minimumBlocked,changed] = dmt_to_reduce(cfg,M,supported,scheme)
%DMT_TO_REDUCE One-level fallback, preserving the strategy's definition.
% A single unsupported minimum-order tone prevents a complete 24-tone table.
% This is a loading-rule rejection, not a proof of physical impossibility.
M=M(:);supported=supported(:);
assert(numel(M)==numel(cfg.k) && all(ismember(M,cfg.Mset)));
assert(islogical(supported) && isequal(size(supported),size(M)));
scheme=char(string(scheme));
assert(any(strcmp(scheme,{'UniformAdaptive','ValidatedLoading'})));
minimumBlocked=false;changed=false;nextM=M;
if strcmp(scheme,'UniformAdaptive')
    assert(all(M==M(1)),'DMT:TradeoffUniform','Uniform must use one common order.');
end
if all(supported),return;end
bad=~supported;
if any(M(bad)==cfg.Mset(1))
    nextM=zeros(0,1);minimumBlocked=true;return;
end
if strcmp(scheme,'UniformAdaptive'),bad(:)=true;end
for k=find(bad).'
    index=find(cfg.Mset==M(k));
    assert(isscalar(index) && index>1);
    nextM(k)=cfg.Mset(index-1);
end
changed=any(nextM~=M);
assert(changed && all(ismember(nextM,cfg.Mset)));
if strcmp(scheme,'UniformAdaptive'),assert(all(nextM==nextM(1)));end
end
