function [errors, tested] = dmt_demod_errors(cfg, Z, bits, M)
% Each column of Z is a symbol; reshape restores qammod's serial order.
errors = zeros(numel(cfg.k),1);
tested = zeros(numel(cfg.k),1);
for c = 1:numel(cfg.k)
    receivedBits = qamdemod(reshape(Z(c,:),[],1),M(c),'gray', ...
        'OutputType','bit','UnitAveragePower',true);
    assert(numel(receivedBits) == numel(bits{c}));
    errors(c) = sum(receivedBits(:) ~= bits{c}(:));
    tested(c) = numel(bits{c});
end
end
