function [X, bits] = dmt_random_frame(cfg, M, nSymbols, dataStream)
% X is NFFT-by-nSymbols; each cell holds one carrier's serial bit vector.
M = M(:);
assert(numel(M) == numel(cfg.k) && all(ismember(M,cfg.Mset)));
X = complex(zeros(cfg.NFFT,nSymbols));
bits = cell(numel(cfg.k),1);
for c = 1:numel(cfg.k)
    b = log2(M(c));
    bits{c} = randi(dataStream,[0 1],b*nSymbols,1);
    s = qammod(bits{c},M(c),'gray','InputType','bit', ...
        'UnitAveragePower',true);
    X(cfg.k(c)+1,:) = reshape(s,1,nSymbols);
    X(cfg.NFFT-cfg.k(c)+1,:) = conj(X(cfg.k(c)+1,:));
end
% DC, Nyquist and all unassigned rows stay zero. Mirrors add no new bits.
end
