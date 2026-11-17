function id=dmt_v13_config_id(cfg)
% Scope selects fixed planned slots; it does not change their scientific model.
science=cfg;
if isfield(science,'requested_scenarios'),science=rmfield(science,'requested_scenarios');end
id=dmt_v13_hash(science);
end
