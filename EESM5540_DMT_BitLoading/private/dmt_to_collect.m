function [shared,designs,runs]=dmt_to_collect(root,phase,cfg,meta,plan)
%DMT_TO_COLLECT Read-only checkpoint reconstruction, including incomplete scope.
conditions=dmt_to_conditions(cfg);nc=cfg.calibration_count;
if strcmp(phase,'preflight'),nc=1;end
ns=numel(cfg.scheme_names);nj=cfg.payload_repeats;
shared=cell(numel(conditions)*nc,1);designs=cell(numel(shared)*ns,1);runs=cell(numel(designs)*nj,1);
folder=fullfile(root,phase);
for condition=conditions
    for c=1:nc
        a=(condition.condition_id-1)*nc+c;
        key=sprintf('shared_c%02d_cal%02d',condition.condition_id,c);
        path=fullfile(folder,'shared',[key '.mat']);
        if isfile(path)
            shared{a}=dmt_to_checkpoint('read',path,'Shared',key,meta,[]);
            validate('Shared',shared{a},'',NaN);
        end
        for s=1:ns
            b=(a-1)*ns+s;scheme=cfg.scheme_names{s};
            key=sprintf('design_c%02d_cal%02d_s%02d',condition.condition_id,c,s);
            path=fullfile(folder,'designs',[key '.mat']);
            if isfile(path)
                assert(~isempty(shared{a}),'DMT:TradeoffOrphan','Design without shared initial record.');
                designs{b}=dmt_to_checkpoint('read',path,'Design',key,meta,[]);
                validate('Design',designs{b},scheme,NaN);
                assert(strcmp(designs{b}.initial_shared_hash,dmt_v13_hash(shared{a})) && ...
                    isequaln(designs{b}.initial_gamma_B,shared{a}.gamma_B), ...
                    'DMT:TradeoffShared','Design is not bound to the actual shared initial record.');
            end
            for j=1:nj
                n=(b-1)*nj+j;
                key=sprintf('payload_c%02d_cal%02d_s%02d_j%02d',condition.condition_id,c,s,j);
                path=fullfile(folder,'payload',[key '.mat']);
                if ~isfile(path),continue;end
                assert(~isempty(designs{b}) && strcmp(designs{b}.status,'accepted'), ...
                    'DMT:TradeoffOrphan','Payload without a D-accepted actual design.');
                runs{n}=dmt_to_checkpoint('read',path,'Payload',key,meta,[]);
                validate('Payload',runs{n},scheme,j);
                assert(strcmp(runs{n}.design_hash,dmt_v13_hash(designs{b})) && ...
                    strcmp(runs{n}.configuration_hash,dmt_v13_hash(designs{b}.final_tx)) && ...
                    isequal(runs{n}.M(:),designs{b}.M(:)) && runs{n}.b==designs{b}.b && ...
                    isequaln(runs{n}.H_used,designs{b}.H_hat), ...
                    'DMT:TradeoffPayloadIdentity','Payload differs from the actual accepted frozen design.');
            end
        end
    end
end
    function validate(kind,value,scheme,slot)
        [ok,reason]=dmt_to_validate(kind,value,cfg,condition,c,scheme,slot,phase,plan);
        assert(ok,'DMT:TradeoffInvalidRecord','%s: %s',kind,reason);
    end
end
