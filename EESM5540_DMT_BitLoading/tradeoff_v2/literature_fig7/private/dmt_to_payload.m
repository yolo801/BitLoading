function run = dmt_to_payload(cfg,condition,design,seeds,nSymbols)
%DMT_TO_PAYLOAD Accepted, ACK-confirmed frozen configuration only.
% Power mismatches are recorded without rescaling or adaptive intervention.
assert(isstruct(design) && isscalar(design) && isfield(design,'status') && ...
    strcmp(string(design.status),"accepted"),'DMT:TONoAcceptedProfile', ...
    'No payload may start before independent D validation accepts a profile.');
assert(all(isfield(design,{'condition','M','b','H_hat','final_tx','final_rx','ack'})), ...
    'DMT:TOInvalidConfiguration','Accepted design is incomplete.');
assert(isequaln(design.condition,condition),'DMT:TOConditionIdentity', ...
    'The accepted design belongs to a different power/ADC condition.');
tx=design.final_tx; rx=design.final_rx; ack=design.ack;
txHash=dmt_v13_hash(tx); rxHash=dmt_v13_hash(rx);
assert(isstruct(ack) && isfield(ack,'accepted') && isscalar(ack.accepted) && ...
    ack.accepted==1 && isfield(ack,'configuration_hash') && ...
    strcmp(txHash,rxHash) && strcmp(txHash,char(string(ack.configuration_hash))), ...
    'DMT:TOMissingACK','Payload requires identical local configurations and their ACK.');
assert(all(isfield(tx,{'M','b','q','adc_range','H_hash','power_hash','validation_hash','profile_id'})));
assert(isequal(tx.M(:),design.M(:)) && tx.b==design.b && tx.q==condition.q && ...
    isequal(tx.adc_range,cfg.adc_range) && ...
    strcmp(char(string(tx.H_hash)),dmt_v13_hash(design.H_hat)), ...
    'DMT:TOFrozenConfiguration','Accepted configuration differs from frozen receiver or front end.');
assert(nSymbols==cfg.payload_symbols || nSymbols==cfg.preflight_payload_symbols, ...
    'DMT:TOPayloadBudget','Payload length is not a declared formal/preflight budget.');
if isfield(seeds,'phase')
    if isfield(design,'phase')
        assert(strcmp(string(seeds.phase),string(design.phase)), ...
            'DMT:TOPhase','Payload seed phase differs from its accepted design.');
    end
    if strcmp(string(seeds.phase),'formal')
        assert(nSymbols==cfg.payload_symbols,'DMT:TOPayloadBudget','Formal symbols differ from the frozen budget.');
    elseif strcmp(string(seeds.phase),'preflight')
        assert(nSymbols==cfg.preflight_payload_symbols,'DMT:TOPayloadBudget','Preflight symbols differ from its budget.');
    else
        error('DMT:TOPhase','Unknown payload stream phase.');
    end
end
Hhash=dmt_v13_hash(design.H_hat);
run=dmt_to_measure(cfg,condition,tx.M,tx.b,nSymbols,seeds,'payload',design.H_hat,false,rx.M);
run.power_actual=run.metrics.tx_sum/run.metrics.sample_count;
run.power_relative_error=(run.power_actual-condition.P_target)/condition.P_target;
run.power_match=abs(run.power_relative_error)<=cfg.payload_power_tolerance;
run.configuration_hash=txHash;
run.profile_id=tx.profile_id;
run.M_hash=dmt_v13_hash(tx.M);
run.H_hash=Hhash;
assert(strcmp(txHash,dmt_v13_hash(tx)) && strcmp(rxHash,dmt_v13_hash(rx)) && ...
    strcmp(Hhash,dmt_v13_hash(design.H_hat)), ...
    'DMT:TOFrozenConfiguration','Payload modified its accepted local state.');
end
