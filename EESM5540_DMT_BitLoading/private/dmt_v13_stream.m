function stream = dmt_v13_stream(cfg,seed)
% Frozen inversion transform gives serial, chunk-independent Gaussian draws.
assert(isscalar(seed) && isfinite(seed) && seed==fix(seed) && seed>=0 && seed<2^32);
stream=RandStream(cfg.streamType,'Seed',seed);
stream.NormalTransform=cfg.normal_transform;
end
