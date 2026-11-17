function exchange = dmt_v13_exchange(cfg,scenario,receiver,varargin)
%DMT_V13_EXCHANGE Explicit receiver feedback, Tx allocation, config and ACK.
% MATLAB structs have value semantics. The ideal transfer functions copy a
% packet into separate local objects, and receiver acceptance checks hashes.
% The optional fourth argument is accepted for caller provenance only; the
% caller owns persistence so no historical or output files are written here.
assert(isempty(varargin) || (numel(varargin)==1 && ...
    (ischar(varargin{1}) || isstring(varargin{1}))));
assert(isequal(cfg.Mset,[4 16 64]) && isequal(cfg.k(:),(1:24).'));
assert(receiver.scenario_idx==scenario.scenario_idx && ...
    strcmp(receiver.scenario_id,scenario.scenario_id));
assert(isequal(receiver.active_k,cfg.k(:)) && receiver.Es_reference==cfg.Es);
assert(isequal(size(receiver.gamma_B),[24 1]) && ...
    all(isfinite(receiver.gamma_B) & receiver.gamma_B>0));
assert(isfield(receiver,'calibration_hash') && ...
    strcmp(receiver.calibration_hash,dmt_v13_hash(rmfield(receiver,'calibration_hash'))), ...
    'DMT:V13CalibrationHash','Receiver estimates changed after their calibration hash was frozen.');
receiverBefore = dmt_v13_hash(receiver);

% rx_make_snr_feedback: channel estimates and raw samples stay at the Rx.
sent = struct('scenario_idx',scenario.scenario_idx, ...
    'scenario_id',char(string(scenario.scenario_id)), ...
    'calibration_id',receiver.calibration_id,'active_k',receiver.active_k, ...
    'gamma_hat_linear',receiver.gamma_B,'Es_reference',receiver.Es_reference, ...
    'estimator_version',receiver.estimator_version, ...
    'calibration_hash',receiver.calibration_hash,'phase',receiver.phase);
received = idealFeedback(sent);
sentHash = dmt_v13_hash(sent);
receivedHash = dmt_v13_hash(received);
assert(strcmp(sentHash,receivedHash) && isequaln(sent,received), ...
    'DMT:V13FeedbackMismatch','Ideal feedback altered the receiver quality packet.');

% tx_allocate sees only the received feedback and public loading settings.
[txProfiles,predictions] = txAllocate(received,cfg.Mset,cfg.targetBER, ...
    cfg.margin_dB,cfg.Ts,cfg.gray_mapping_version);
rebuilt = independentlyRebuild(received,cfg.Mset,cfg.targetBER,cfg.margin_dB);
for s = 1:3
    assert(txProfiles(s).feasible==rebuilt(s).feasible && ...
        isequal(txProfiles(s).M_k,rebuilt(s).M_k) && ...
        isequal(txProfiles(s).bits_k,rebuilt(s).bits_k), ...
        'DMT:V13AllocationMismatch','Independent feedback allocation does not match the Tx table.');
end
rxProfiles = txProfiles;
acks = repmat(struct('accepted',false,'configuration_hash','','scenario_id','', ...
    'scenario_idx',0,'calibration_id',0,'profile_id','','reason',''),1,3);
for s = 1:3
    outbound = txProfiles(s);
    advertisedHash = dmt_v13_hash(outbound);
    inbound = idealConfiguration(outbound);
    [rxProfiles(s),acks(s)] = rxAccept(cfg,scenario,receiver,inbound,advertisedHash);
    assert(isequaln(txProfiles(s),rxProfiles(s)) && ...
        strcmp(dmt_v13_hash(txProfiles(s)),dmt_v13_hash(rxProfiles(s))), ...
        'DMT:V13ConfigurationMismatch','Tx/Rx local configurations differ.');
    assert(acks(s).accepted==txProfiles(s).feasible);
end
assert(strcmp(receiverBefore,dmt_v13_hash(receiver)), ...
    'DMT:V13ReceiverChanged','The feedback/configuration path modified the frozen receiver.');
exchange = struct('scenario_idx',scenario.scenario_idx,'scenario_id',scenario.scenario_id, ...
    'calibration_id',receiver.calibration_id,'feedback_sent',sent, ...
    'feedback_received',received,'feedback_hash_sent',sentHash, ...
    'feedback_hash_received',receivedHash,'tx_profiles',txProfiles, ...
    'rx_profiles',rxProfiles,'acks',acks,'candidate_predictions',predictions, ...
    'allocation_recomputed',true, ...
    'assumption','Ideal error-free control transfer; signaling delay, quantization and coding overhead are not modeled.');
end

function received = idealFeedback(sent)
received = sent; % Value copy, not a shared mutable global or handle.
end

function received = idealConfiguration(sent)
received = sent; % Separate receiver-local value object, then independently checked.
end

function [profiles,predictions] = txAllocate(feedback,Mset,target,margin,Ts,mappingVersion)
% No H_hat, H_true, noise, C, or payload result is an argument to the Tx.
gamma = feedback.gamma_hat_linear;
gammaDesign = gamma/10^(margin/10);
design = zeros(24,numel(Mset)); nominal = design;
for j = 1:numel(Mset)
    design(:,j) = dmt_qam_ber(Mset(j),gammaDesign);
    nominal(:,j) = dmt_qam_ber(Mset(j),gamma);
end
allowed = design<=target;
feasible = all(allowed(:,1)); % QPSK must be usable on every required tone.
uniform = zeros(0,1); loaded = uniform;
if feasible
    uniform = max(Mset(all(allowed,1)))*ones(24,1);
    loaded = zeros(24,1);
    for k = 1:24, loaded(k)=max(Mset(allowed(k,:))); end
end
names = {'Uniform','Loaded','Fixed16'};
orders = {uniform,loaded,16*ones(24,1)};
template = struct('scenario_id',feedback.scenario_id,'scenario_idx',feedback.scenario_idx, ...
    'calibration_id',feedback.calibration_id,'profile_id','','scheme','', ...
    'active_k',feedback.active_k,'M_k',zeros(0,1),'bits_k',zeros(0,1), ...
    'Gray_mapping_version',mappingVersion, ...
    'Es_reference',feedback.Es_reference,'targetBER',target,'margin_dB',margin, ...
    'calibration_hash',feedback.calibration_hash,'feasible',false,'reason','', ...
    'B',NaN,'R_payload',NaN,'phase',feedback.phase);
profiles = repmat(template,1,3);
for s = 1:3
    profiles(s).scheme = names{s};
    profiles(s).profile_id = sprintf('%s_calibration_%02d_%s_%s', ...
        feedback.scenario_id,feedback.calibration_id,names{s},feedback.calibration_hash(1:12));
    profiles(s).feasible = s==3 || feasible;
    profiles(s).M_k = orders{s};
    profiles(s).bits_k = log2(orders{s});
    if profiles(s).feasible
        profiles(s).B = sum(profiles(s).bits_k);
        profiles(s).R_payload = profiles(s).B/Ts;
    else
        bad = feedback.active_k(~any(allowed,2));
        profiles(s).reason = ['No complete feasible table: QPSK unavailable on k=' mat2str(bad.') ...
            '. No tones disabled; Fixed16 remains a diagnostic configuration.'];
    end
end
predictions = table();
for j = 1:numel(Mset)
    rows = table(feedback.active_k,repmat(Mset(j),24,1),gamma,10*log10(gamma), ...
        design(:,j),nominal(:,j),allowed(:,j),'VariableNames', ...
        {'k','M','gamma_B','gamma_B_dB','BER_design','BER_nominal','design_feasible'});
    if isempty(predictions), predictions=rows; else, predictions=[predictions;rows]; end %#ok<AGROW>
end
end

function profiles = independentlyRebuild(feedback,Mset,target,margin)
% Acceptance reconstruction reads the saved quality packet, not Tx state.
gamma = feedback.gamma_hat_linear/10^(margin/10);
legal = false(24,numel(Mset));
for k = 1:24
    for j = 1:numel(Mset)
        M = Mset(j);
        predicted = 4/log2(M)*(1-1/sqrt(M))* ...
            0.5*erfc(sqrt(3*gamma(k)/(M-1))/sqrt(2));
        legal(k,j) = predicted<=target;
    end
end
feasible = all(legal(:,1));
profiles = repmat(struct('feasible',false,'M_k',zeros(0,1),'bits_k',zeros(0,1)),1,3);
if feasible
    profiles(1).M_k = max(Mset(all(legal,1)))*ones(24,1);
    profiles(2).M_k = zeros(24,1);
    for k = 1:24, profiles(2).M_k(k)=max(Mset(legal(k,:))); end
    profiles(1).feasible = true; profiles(2).feasible = true;
end
profiles(3).feasible = true; profiles(3).M_k=16*ones(24,1);
for s = 1:3, profiles(s).bits_k=log2(profiles(s).M_k); end
end

function [local,ack] = rxAccept(cfg,scenario,receiver,configuration,advertisedHash)
required = {'scenario_id','scenario_idx','calibration_id','profile_id','scheme', ...
    'active_k','M_k','bits_k','Gray_mapping_version','Es_reference','targetBER', ...
    'margin_dB','calibration_hash','feasible','reason','B','R_payload','phase'};
assert(all(isfield(configuration,required)));
assert(strcmp(configuration.scenario_id,scenario.scenario_id) && ...
    configuration.scenario_idx==scenario.scenario_idx && ...
    configuration.calibration_id==receiver.calibration_id && ...
    strcmp(configuration.calibration_hash,receiver.calibration_hash));
assert(isequal(configuration.active_k,cfg.k(:)) && ...
    configuration.Es_reference==cfg.Es && configuration.targetBER==cfg.targetBER && ...
    configuration.margin_dB==cfg.margin_dB && ...
    strcmp(configuration.Gray_mapping_version,cfg.gray_mapping_version));
assert(strcmp(advertisedHash,dmt_v13_hash(configuration)), ...
    'DMT:V13ConfigurationHash','Configuration changed during ideal transfer.');
if configuration.feasible
    assert(isequal(size(configuration.M_k),[24 1]) && ...
        all(ismember(configuration.M_k,cfg.Mset)) && ...
        isequal(configuration.bits_k,log2(configuration.M_k)));
    assert(configuration.B==sum(configuration.bits_k) && ...
        configuration.R_payload==configuration.B/cfg.Ts);
else
    assert(isempty(configuration.M_k) && isempty(configuration.bits_k) && ...
        isnan(configuration.B) && isnan(configuration.R_payload));
    assert(~strcmp(configuration.scheme,'Fixed16'),'Fixed16 must remain configured.');
end
local = configuration;
ack = struct('accepted',logical(local.feasible),'configuration_hash',dmt_v13_hash(local), ...
    'scenario_id',local.scenario_id,'scenario_idx',local.scenario_idx, ...
    'calibration_id',local.calibration_id,'profile_id',local.profile_id,'reason',local.reason);
end
