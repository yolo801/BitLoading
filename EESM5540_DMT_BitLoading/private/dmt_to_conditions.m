function conditions=dmt_to_conditions(cfg)
%DMT_TO_CONDITIONS Fixed ordering; all quantities derive from frozen lists.
template=struct('condition_id',0,'P_target',0,'q',0);
conditions=repmat(template,1,numel(cfg.P_targets)*numel(cfg.adc_bits));
n=0;
for power=cfg.P_targets
    for bits=cfg.adc_bits
        n=n+1;conditions(n)=struct('condition_id',n,'P_target',power,'q',bits);
    end
end
end
