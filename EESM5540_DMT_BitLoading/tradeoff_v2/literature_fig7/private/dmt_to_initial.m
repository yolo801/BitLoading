function shared = dmt_to_initial(cfg,condition,calID,plan)
%DMT_TO_INITIAL Shared initial QPSK power calibration and independent A0/B0.
% This object is immutable input to two alternative strategy designs. The
% initial LS estimate remains receiver-local; feedback transfers quality.
assert(istable(plan) && numel(unique(string(plan.phase)))==1);
phase=char(string(plan.phase(1)));
assert(any(strcmp(phase,{'preflight','formal'})));
assert(isscalar(calID) && calID>=1 && calID==fix(calID));
M0=cfg.Mset(1)*ones(numel(cfg.k),1);
powerSeed=dmt_to_seed(plan,condition.condition_id,calID,'Shared',0,'initial_power',NaN);
assert(isnan(powerSeed.noise_seed),'TX-only calibration has no noise stream.');
power0=dmt_to_power_cal(cfg,condition,M0,powerSeed.data_seed);
aSeed=dmt_to_seed(plan,condition.condition_id,calID,'Shared',0,'A0',NaN);
bSeed=dmt_to_seed(plan,condition.condition_id,calID,'Shared',0,'B0',NaN);
A0=dmt_to_measure(cfg,condition,M0,power0.b,cfg.initial_A_symbols,aSeed,'A0',[]);
H0=A0.H_hat;
assert(isequal(size(H0),[numel(cfg.k) 1]) && all(isfinite(H0) & abs(H0)>0));
B0=dmt_to_measure(cfg,condition,M0,power0.b,cfg.initial_B_symbols,bSeed,'B0',H0);
assert(all(isfinite(B0.gamma) & B0.gamma>0));
feedbackSent=struct('condition_id',condition.condition_id,'P_target',condition.P_target, ...
    'q',condition.q,'calibration_id',calID,'phase',phase,'active_k',cfg.k(:), ...
    'Es_reference',cfg.Es,'gamma_B',B0.gamma(:));
feedbackReceived=feedbackSent; % Ideal value-copy transport, not shared state.
assert(isequaln(feedbackSent,feedbackReceived));
shared=struct('phase',phase,'condition',condition,'calibration_id',calID, ...
    'M0',M0,'power0',power0,'A0',A0,'B0',B0,'H0',H0, ...
    'gamma_B',B0.gamma(:),'status','complete', ...
    'feedback_sent',feedbackSent,'feedback_received',feedbackReceived, ...
    'feedback_hash_sent',dmt_v13_hash(feedbackSent), ...
    'feedback_hash_received',dmt_v13_hash(feedbackReceived));
end
