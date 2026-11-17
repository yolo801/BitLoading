function counts=dmt_to_completion(cfg,phase,shared,designs,runs)
%DMT_TO_COMPLETION Count actual complete units, not requested symbol settings.
nc=cfg.calibration_count;if strcmp(phase,'preflight'),nc=1;end
conditions=dmt_to_conditions(cfg);
counts=struct('phase',phase,'planned_shared',numel(conditions)*nc, ...
    'completed_shared',sum(~cellfun(@isempty,shared)), ...
    'planned_designs',numel(conditions)*nc*numel(cfg.scheme_names), ...
    'completed_designs',sum(~cellfun(@isempty,designs)), ...
    'accepted_designs',0,'rejected_designs',0,'planned_payload_slots',0, ...
    'completed_payload_slots',sum(~cellfun(@isempty,runs)), ...
    'design_rejected_payload_slots',0,'incomplete_payload_slots',0,'power_mismatch_payload_slots',0);
for j=1:numel(designs)
    if isempty(designs{j}),continue;end
    if strcmp(designs{j}.status,'accepted'),counts.accepted_designs=counts.accepted_designs+1;
    else,counts.rejected_designs=counts.rejected_designs+1;end
end
for j=1:numel(runs)
    if ~isempty(runs{j}) && ~runs{j}.power_match
        counts.power_mismatch_payload_slots=counts.power_mismatch_payload_slots+1;
    end
end
counts.planned_payload_slots=counts.planned_designs*cfg.payload_repeats;
counts.design_rejected_payload_slots=counts.rejected_designs*cfg.payload_repeats;
counts.incomplete_payload_slots=counts.planned_payload_slots-counts.completed_payload_slots- ...
    counts.design_rejected_payload_slots;
assert(counts.incomplete_payload_slots>=0);
counts.scope_resolved=counts.completed_shared==counts.planned_shared && ...
    counts.completed_designs==counts.planned_designs && counts.incomplete_payload_slots==0;
counts.all_payloads_completed=counts.completed_payload_slots==counts.planned_payload_slots;
end
