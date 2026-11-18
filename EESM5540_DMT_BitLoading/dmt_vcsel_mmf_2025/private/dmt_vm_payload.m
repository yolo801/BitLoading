function m = dmt_vm_payload(cfg,c,design,seeds,n)
%DMT_VM_PAYLOAD Send only a validated, ACK-confirmed frozen configuration.
assert(strcmp(design.status,'accepted') && isequaln(design.condition,c) && ...
    strcmp(design.phase,seeds.phase) && strcmp(design.scheme,seeds.scheme), ...
    'DMT:VMPayloadAuthorization','Payload requires its own accepted design.');
tx=design.final_tx;rx=design.final_rx;ack=design.ack;
assert(isequaln(tx,rx) && ack.accepted && strcmp(dmt_v13_hash(tx),ack.configuration_hash) && ...
    isequal(tx.M,design.M) && tx.b==design.b && tx.q==c.q && ...
    strcmp(tx.H_hash,dmt_v13_hash(design.H_hat)), ...
    'DMT:VMPayloadConfiguration','The Tx/Rx table, bias or receiver estimate changed.');
m=dmt_vm_measure(cfg,c,tx.M,tx.b,n,seeds,'payload',design.H_hat,false,rx.M);
m.scheme=design.scheme;
m.payload_slot=seeds.payload_slot;
m.calibration_id=seeds.calibration_id;
m.design_hash=dmt_v13_hash(design);
m.configuration_hash=dmt_v13_hash(tx);
m.profile_id=tx.profile_id;
m.power_actual=m.metrics.tx_sum/m.metrics.sample_count;
m.power_relative_error=(m.power_actual-c.P_target)/c.P_target;
m.power_match=abs(m.power_relative_error)<=cfg.payload_power_tolerance;
end
