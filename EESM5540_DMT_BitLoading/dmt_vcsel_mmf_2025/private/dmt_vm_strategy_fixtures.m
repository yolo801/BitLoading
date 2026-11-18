function checks=dmt_vm_strategy_fixtures(cfg)
% Deterministic counter-rule checks, excluded from formal evidence.
k=numel(cfg.k);
assert(k>=3);
M64=64*ones(k,1);
weakPower=.1*10^(cfg.margin_dB/10);
gamma=1e4*10^(cfg.margin_dB/10)*ones(k,1);
gamma(1)=weakPower;
gamma(2)=64*10^(cfg.margin_dB/10);
uniform=dmt_vm_decisions(cfg,'UniformValidated',gamma);
perTone=dmt_vm_decisions(cfg,'PerToneValidated',gamma);
checks.initial_orders=isequal(uniform.M,M64) && isequal(perTone.M(1:3),[4;16;64]) && ...
    ~perTone.allowed(1,1);
lo=zeros(k,1);
good=cfg.targetBER/2*ones(k,1);
border=good;
border(1)=cfg.targetBER;
first=dmt_vm_decisions(cfg,'UniformValidated',[],uniform.M,lo,border,1);
second=dmt_vm_decisions(cfg,'UniformValidated',[],first.next_M,lo,border,2);
third=dmt_vm_decisions(cfg,'UniformValidated',[],second.next_M,lo,good,3);
checks.uniform_fallback=~first.terminal && all(first.next_M==16) && ~second.terminal && ...
    all(second.next_M==4) && third.accepted && all(third.next_M==4);
floorUnknown=dmt_vm_decisions(cfg,'UniformValidated',[],second.next_M,lo,border,3);
confirmed=lo;
confirmed(1)=cfg.targetBER*1.1;
badUpper=border;
badUpper(1)=cfg.targetBER*2;
floorFailed=dmt_vm_decisions(cfg,'UniformValidated',[],second.next_M,confirmed,badUpper,3);
checks.floor_status=~floorUnknown.accepted && ~floorUnknown.supported_k(1) && ...
    strcmp(floorUnknown.reason,'minimum_order_inconclusive') && ...
    strcmp(floorFailed.reason,'minimum_order_ber_failed');
some=good;
some(2:3)=cfg.targetBER*2;
adopt=dmt_vm_decisions(cfg,'PerToneValidated',[],perTone.M,lo,some,1);
finish=dmt_vm_decisions(cfg,'PerToneValidated',[],adopt.next_M,lo,good,2);
budget=dmt_vm_decisions(cfg,'PerToneValidated',[],adopt.next_M,lo,badUpper,3);
some(1)=good(1);
exhausted=dmt_vm_decisions(cfg,'PerToneValidated',[],adopt.next_M,lo, ...
    [good(1:2);some(3);good(4:end)],3);
checks.per_tone_fallback=~adopt.terminal && isequal(adopt.next_M(1:3),[4;4;16]) && ...
    isequal(adopt.next_M(4:end),perTone.M(4:end)) && finish.accepted && ...
    strcmp(budget.reason,'minimum_order_inconclusive') && ...
    strcmp(exhausted.reason,'round_budget_exhausted');
checks.passed=all(structfun(@(value)value,checks));
end
