function checks=dmt_fb_promotion_fixtures(cfg)
%DMT_FB_PROMOTION_FIXTURES Deterministic pilot-only route and budget cases.
branch='PromotionFirstLoading';
M=64*ones(numel(cfg.k),1);
boundary=cfg.k==23;
M(boundary)=16;
M(cfg.k==24)=16;
promoted=M;
promoted(boundary)=64;
counts=cfg.design_D_symbols*log2(promoted);
good=zeros(size(M));
bad=good;
bad(boundary)=ceil(2*cfg.targetBER*counts(boundary));
[~,hiGood]=dmt_wilson(good,counts);
[~,hiBad]=dmt_wilson(bad,counts);
accept=dmt_to_decide(cfg,promoted,hiGood<cfg.targetBER,'ValidatedLoading',1);
reject=dmt_to_decide(cfg,promoted,hiBad<cfg.targetBER,'ValidatedLoading',1);
[pending,standard]=dmt_fb_promotion_route(branch,M,cfg.k,'','');
checks.accepted=strcmp(pending,'promotion_pending') && ~standard && accept.accepted && ...
    isequal(accept.next_M,promoted) && nnz(promoted~=M)==1 && ...
    strcmp(dmt_fb_promotion_route(branch,M,cfg.k,accept.status,''),'promotion_accepted');
[fallback,run]=dmt_fb_promotion_route(branch,M,cfg.k,'promotion_rejected','');
checks.rejected_then_accepted=~reject.accepted && strcmp(fallback,'promotion_rejected_fallback_pending') && ...
    run && strcmp(dmt_fb_promotion_route(branch,M,cfg.k,'promotion_rejected','accepted'), ...
        'promotion_rejected_fallback_accepted');
minimum=M;minimum(cfg.k==24)=4;
support=true(size(M));support(cfg.k==24)=false;
cannot=dmt_to_decide(cfg,minimum,support,'ValidatedLoading',1);
checks.rejected_then_rejected=cannot.terminal && ~cannot.accepted && ...
    strcmp(dmt_fb_promotion_route(branch,M,cfg.k,'promotion_rejected',cannot.status), ...
        'promotion_rejected_fallback_rejected');
[already,runExisting,reason]=dmt_fb_promotion_route(branch,promoted,cfg.k,'','');
[none,runNone]=dmt_fb_promotion_route(branch,zeros(0,1),cfg.k,'','');
checks.without_candidate=strcmp(already,'not_eligible') && runExisting && ...
    strcmp(reason,'k23_already_64qam') && strcmp(none,'no_initial_candidate') && ~runNone;
[failed,runFailed]=dmt_fb_promotion_route(branch,M,cfg.k,'power_error','');
checks.power_failed=strcmp(failed,'power_error') && ~runFailed && ...
    strcmp(dmt_fb_promotion_route(branch,M,cfg.k,'promotion_rejected','power_error'),'power_error');
[errored,runErrored]=dmt_fb_promotion_route(branch,M,cfg.k,'execution_error','');
checks.execution_failed=strcmp(errored,'execution_error') && ~runErrored && ...
    strcmp(dmt_fb_promotion_route(branch,M,cfg.k,'promotion_rejected','execution_error'),'execution_error');
checks.passed=all(structfun(@(x)x,checks));
end
