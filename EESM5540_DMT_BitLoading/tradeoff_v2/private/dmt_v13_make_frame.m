function [X,bits] = dmt_v13_make_frame(cfg,M,nSymbols,dataStream)
%DMT_V13_MAKE_FRAME Symbol-first draws make frozen profiles chunk invariant.
% Each column draws all independent payload bits for one DMT symbol, before
% carrier slicing. Different chunk sizes therefore retain the same bit order.
M=M(:);
assert(numel(M)==numel(cfg.k) && all(ismember(M,cfg.Mset)));
assert(isscalar(nSymbols) && nSymbols>=1 && nSymbols==fix(nSymbols));
b=log2(M);
raw=randi(dataStream,[0 1],sum(b),nSymbols);
X=complex(zeros(cfg.NFFT,nSymbols));
bits=cell(numel(cfg.k),1);
offset=0;
for c=1:numel(cfg.k)
    carrierBits=raw(offset+(1:b(c)),:);
    bits{c}=carrierBits(:);
    symbols=qammod(bits{c},M(c),'gray','InputType','bit','UnitAveragePower',true);
    X(cfg.k(c)+1,:)=reshape(symbols,1,nSymbols);
    X(cfg.NFFT-cfg.k(c)+1,:)=conj(X(cfg.k(c)+1,:));
    offset=offset+b(c);
end
% DC, Nyquist and every unassigned frequency stay zero. Mirrors add no bits.
end
