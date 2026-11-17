function receiver = dmt_v13_rx_estimate(cfg,observations)
%DMT_V13_RX_ESTIMATE Receiver-only LS from A and residual quality from B.
% No payload, validation-C, analytical response or actual noise is available
% to this estimator. IM/DD residual quality includes clipping/estimation loss.
required = {'scenario_idx','scenario_id','calibration_id','active_k', ...
    'Es_reference','symbols_A','symbols_B','X_A','Y_A','X_B','Y_B','sample_hash'};
assert(isstruct(observations) && isscalar(observations) && all(isfield(observations,required)));
unsigned = rmfield(observations,'sample_hash');
assert(strcmp(dmt_v13_hash(unsigned),observations.sample_hash), ...
    'DMT:V13ObservationHash','Saved A/B observations do not match their source hash.');
assert(isequal(observations.active_k,cfg.k(:)) && observations.Es_reference==cfg.Es);
assert(observations.symbols_A==cfg.trainSymbols && observations.symbols_B==cfg.probeSymbols);
XA = observations.X_A; YA = observations.Y_A;
XB = observations.X_B; YB = observations.Y_B;
assert(isequal(size(XA),[numel(cfg.k) cfg.trainSymbols]) && isequal(size(YA),size(XA)));
assert(isequal(size(XB),[numel(cfg.k) cfg.probeSymbols]) && isequal(size(YB),size(XB)));
assert(all(isfinite(XA(:))) && all(isfinite(YA(:))) && ...
    all(isfinite(XB(:))) && all(isfinite(YB(:))));
trainingDenominator = sum(abs(XA).^2,2);
assert(all(trainingDenominator>0));
Hhat = sum(YA.*conj(XA),2)./trainingDenominator;
assert(all(isfinite(Hhat)) && all(abs(Hhat)>0));
ZB = YB./Hhat;
signalSum = sum(abs(XB).^2,2);
residualSum = sum(abs(ZB-XB).^2,2);
assert(all(isfinite(signalSum) & signalSum>0) && ...
    all(isfinite(residualSum) & residualSum>0));
gammaB = signalSum./residualSum;
receiver = struct('scenario_idx',observations.scenario_idx, ...
    'scenario_id',char(string(observations.scenario_id)), ...
    'calibration_id',observations.calibration_id,'active_k',cfg.k(:), ...
    'Es_reference',cfg.Es,'H_hat',Hhat,'gamma_B',gammaB, ...
    'gamma_B_dB',10*log10(gammaB),'training_denominator',trainingDenominator, ...
    'probe_signal_sum',signalSum,'probe_residual_sum',residualSum, ...
    'estimator_version','LS_A_independent_B_residual_v1.3', ...
    'observation_hash',observations.sample_hash);
if observations.scenario_idx==0
    receiver.quality_kind = 'electrical symbol SNR estimate';
else
    receiver.quality_kind = 'residual effective SNR / SNDR estimate';
end
if isfield(observations,'phase'), receiver.phase=observations.phase; else, receiver.phase='formal'; end
receiver.calibration_hash = dmt_v13_hash(receiver);
end
