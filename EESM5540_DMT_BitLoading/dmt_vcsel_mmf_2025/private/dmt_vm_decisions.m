function result=dmt_vm_decisions(cfg,scheme,gamma,M,lower,upper,attempt)
% Pure strategy rule. Initial quality proposes orders. Actual Dr admits them.
scheme=validatestring(scheme,{'UniformValidated','PerToneValidated'});
assert(isequal(cfg.Mset,[4 16 64]) && cfg.max_rounds==3);
orders=cfg.Mset;
if nargin==3
    assert(iscolumn(gamma) && numel(gamma)==numel(cfg.k) && all(isfinite(gamma) & gamma>0));
    designGamma=gamma/10^(cfg.margin_dB/10);
    predicted=zeros(numel(gamma),numel(orders));
    for j=1:numel(orders)
        predicted(:,j)=dmt_qam_ber(orders(j),designGamma);
    end
    allowed=predicted<=cfg.targetBER;
    M=repmat(orders(1),numel(gamma),1);
    if strcmp(scheme,'UniformValidated')
        M(:)=orders(end);
    else
        % QPSK is the lowest proposal even when its SNR estimate is weak.
        % Independent Dr can reject this full table. No carriers are dropped.
        for j=2:numel(orders)
            M(allowed(:,j))=orders(j);
        end
    end
    result=struct('M',M,'predicted',predicted,'allowed',allowed);
    return;
end
assert(nargin==7 && isscalar(attempt) && ismember(attempt,1:cfg.max_rounds));
assert(iscolumn(M) && numel(M)==numel(cfg.k) && all(ismember(M,orders)) && ...
    isequal(size(lower),size(M),size(upper)) && all(lower>=0 & lower<=upper & upper<=1));
supported=upper<cfg.targetBER;
result=struct('accepted',false,'terminal',true,'status','design_rejected','reason','', ...
    'next_M',zeros(0,1),'supported_k',supported);
if strcmp(scheme,'UniformValidated')
    assert(all(M==orders(end+1-attempt)),'DMT:VMUniform','Uniform trials follow 64, 16, 4.');
end
if all(supported)
    result.accepted=true;
    result.status='accepted';
    result.reason='validated';
    result.next_M=M;
    return;
end
floorBlocked=~supported & M==orders(1);
if any(floorBlocked)
    if any(lower(floorBlocked)>cfg.targetBER)
        result.reason='minimum_order_ber_failed';
    else
        result.reason='minimum_order_inconclusive';
    end
    return;
end
if attempt==cfg.max_rounds
    result.reason='round_budget_exhausted';
    return;
end
result.terminal=false;
result.status='retest';
result.next_M=M;
if strcmp(scheme,'UniformValidated')
    result.reason='try_next_uniform_order';
    result.next_M(:)=orders(end-attempt);
else
    result.reason='lower_unsupported_tones';
    result.next_M(~supported & M==16)=4;
    result.next_M(~supported & M==64)=16;
end
assert(~isequal(result.next_M,M),'DMT:VMUnchanged','Retest must change the full candidate.');
end
