function scenarios = dmt_v13_scenarios(cfg)
% Fixed P0/Pmax: rho changes AC drive and clipping, not average/peak budgets.
names = {'linear','imdd_rho4','imdd_rho2p5','imdd_rho1p5'};
rhos = [NaN 4 2.5 1.5];
scenarios = repmat(struct('scenario_idx',0,'scenario_id','','model_version','', ...
    'imdd',false,'rho',NaN,'g',1,'P0',1,'Pmax',2,'sigma_w2',cfg.sigma_w2),1,4);
for s=1:4
    scenarios(s).scenario_idx=s-1;
    scenarios(s).scenario_id=names{s};
    scenarios(s).rho=rhos(s);
    scenarios(s).imdd=s>1;
    scenarios(s).model_version='linear-1.0';
    if s>1
        scenarios(s).model_version='imdd-equivalent-1.0';
        scenarios(s).g=1/(rhos(s)*sqrt(0.75));
        scenarios(s).sigma_w2=cfg.sigma_w2/(4^2*0.75);
    end
end
end
