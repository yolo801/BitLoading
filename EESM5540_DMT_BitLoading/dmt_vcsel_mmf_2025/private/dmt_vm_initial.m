function shared=dmt_vm_initial(cfg,condition,calID,plan)
% Use separate known QPSK A0 and B0 blocks. Only quality is fed back.
phase=char(plan.phase(1));
assert(istable(plan) && all(plan.phase==string(phase)) && ismember(string(phase),["pilot","formal"]));
assert(isscalar(calID) && calID>=1 && calID==fix(calID));
M0=cfg.Mset(1)*ones(numel(cfg.k),1);
powerSeed=dmt_to_seed(plan,condition.condition_id,calID,'Shared',0,'initial_power',NaN);
assert(isnan(powerSeed.noise_seed),'DMT:VMInitialPower','TX-only calibration has no noise stream.');
power0=dmt_vm_power_cal(cfg,condition,M0,powerSeed.data_seed);
aSeed=dmt_to_seed(plan,condition.condition_id,calID,'Shared',0,'A0',NaN);
bSeed=dmt_to_seed(plan,condition.condition_id,calID,'Shared',0,'B0',NaN);
A0=dmt_vm_measure(cfg,condition,M0,power0.b,cfg.initial_A_symbols,aSeed,'A0',[]);
H0=A0.H_hat;
assert(isequal(size(H0),[numel(cfg.k) 1]) && all(isfinite(H0) & abs(H0)>0));
B0=dmt_vm_measure(cfg,condition,M0,power0.b,cfg.initial_B_symbols,bSeed,'B0',H0);
assert(all(isfinite(B0.gamma) & B0.gamma>0));
feedbackSent=struct('condition_id',condition.condition_id,'P_target',condition.P_target, ...
    'case_id',condition.case_id,'swing',condition.swing,'q',condition.q,'calibration_id',calID, ...
    'phase',phase,'active_k',cfg.k(:),'Es_reference',cfg.Es,'gamma_B',B0.gamma(:));
feedbackReceived=feedbackSent;
shared=struct('phase',phase,'condition',condition,'calibration_id',calID, ...
    'M0',M0,'power0',power0,'A0',A0,'B0',B0,'H0',H0,'gamma_B',B0.gamma(:), ...
    'status','complete','feedback_sent',feedbackSent,'feedback_received',feedbackReceived, ...
    'feedback_hash_sent',dmt_v13_hash(feedbackSent),'feedback_hash_received',dmt_v13_hash(feedbackReceived));
end
