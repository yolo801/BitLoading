function t=dmt_fb_audit_scan_events(cfg,layout,shared,designs,runs,didReuse)
%DMT_FB_AUDIT_SCAN_EVENTS Keep completed setup and payload blocks separate.
blank=struct('condition_id',NaN,'P_target',NaN,'q',NaN,'calibration_id',NaN, ...
    'scheme',"",'round',NaN,'role',"",'payload_slot',NaN,'symbols',NaN, ...
    'data_seed',NaN,'noise_seed',NaN,'forward_setup_symbols',0, ...
    'forward_payload_symbols',0,'tx_only_generated_symbols',0, ...
    'tx_only_calibration_reused',false,'data_source',"");
list=repmat(blank,0,1);
ci=0;
for cond=reshape(layout.conditions,1,[])
    ci=ci+1;
    ca=0;
    for cal=layout.calibrations
        ca=ca+1;
        k=(ci-1)*numel(layout.calibrations)+ca;
        row=blank;
        row.condition_id=cond.condition_id;
        row.P_target=cond.P_target;
        row.q=cond.q;
        row.calibration_id=cal;
        row.data_source="new";
        if didReuse && cond.condition_id==9,row.data_source="reused_verified";end
        row.scheme="Shared";
        one=shared{k};
        if ~isempty(one)
            addPower(row,0,"initial_power",one.power0,false);
            addBlock(row,0,"A0",NaN,one.A0);
            addBlock(row,0,"B0",NaN,one.B0);
        end
        for s=1:layout.nSchemes
            index=(k-1)*layout.nSchemes+s;
            design=designs{index};
            if isempty(design),continue;end
            row.scheme=string(cfg.scheme_names{s});
            if strcmp(design.status,'fixed_authorized')
                addPower(row,1,"power",design.power,design.power_reused);
                addBlock(row,1,"Ar",NaN,design.Ar);
            elseif isfield(design,'rounds')
                for candidate=reshape(design.rounds,1,[])
                    addPower(row,candidate.round,"power",candidate.power,false);
                    addBlock(row,candidate.round,"Ar",NaN,candidate.Ar);
                    addBlock(row,candidate.round,"Dr",NaN,candidate.Dr);
                end
            end
            for slot=1:layout.nRepeats
                payload=runs{(index-1)*layout.nRepeats+slot};
                if ~isempty(payload),addBlock(row,0,"payload",slot,payload);end
            end
        end
    end
end
if isempty(list)
    t=struct2table(blank,'AsArray',true);
    t=t([],:);
else
    t=struct2table(list);
end

    function addPower(record,round,role,p,reused)
        record.round=round;
        record.role=role;
        record.symbols=p.symbols;
        record.data_seed=p.seed;
        record.tx_only_calibration_reused=reused;
        if ~reused,record.tx_only_generated_symbols=p.symbols;end
        list(end+1,1)=record;
    end

    function addBlock(record,round,role,slot,block)
        record.round=round;
        record.role=role;
        record.payload_slot=slot;
        record.symbols=block.symbols;
        record.data_seed=block.seeds.data_seed;
        record.noise_seed=block.seeds.noise_seed;
        if role=="payload"
            record.forward_payload_symbols=block.symbols;
        else
            record.forward_setup_symbols=block.symbols;
        end
        list(end+1,1)=record;
    end
end
