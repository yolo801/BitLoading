function [profiles, feasible, diagnostics] = dmt_load_profiles(cfg, calibration)
% Loading uses only gamma_hat frozen from independent probe B.
gammaEff = calibration.gamma_hat/10^(cfg.margin_dB/10);
predictedBER = zeros(numel(cfg.k),numel(cfg.Mset));
for j = 1:numel(cfg.Mset)
    predictedBER(:,j) = dmt_qam_ber(cfg.Mset(j),gammaEff);
end
allowed = predictedBER <= cfg.targetBER;
diagnostics.gamma_eff = gammaEff;
diagnostics.predictedBER = predictedBER;
diagnostics.infeasible_k = cfg.k(~allowed(:,1));
feasible = isempty(diagnostics.infeasible_k);
profiles = struct('name',{},'M',{},'bits_per_symbol',{},'B',{},'R_payload',{},'role',{});
if ~feasible
    return; % Never silently deactivate tones or redistribute energy.
end
loaded = zeros(numel(cfg.k),1);
for c = 1:numel(cfg.k)
    loaded(c) = max(cfg.Mset(allowed(c,:)));
end
uniformM = max(cfg.Mset(all(allowed,1)));
names = {'Uniform','Loaded','Fixed16'};
roles = {'formal_baseline','formal_loaded','diagnostic'};
orders = {uniformM*ones(numel(cfg.k),1),loaded,16*ones(numel(cfg.k),1)};
for j = 1:numel(names)
    profiles(j).name = names{j};
    profiles(j).M = orders{j};
    profiles(j).bits_per_symbol = log2(orders{j});
    profiles(j).B = sum(profiles(j).bits_per_symbol);
    profiles(j).R_payload = profiles(j).B/cfg.Ts;
    profiles(j).role = roles{j};
end
diagnostics.BER_design = predictedBER;
diagnostics.Mset = cfg.Mset;
end
