function [M,predictions,allowed]=dmt_fb_promotion_initial(cfg,shared)
%DMT_FB_PROMOTION_INITIAL Original v2 nonuniform allocation from B0 quality.
gamma=shared.feedback_received.gamma_B(:)/10^(cfg.margin_dB/10);
predictions=zeros(numel(gamma),numel(cfg.Mset));
for j=1:numel(cfg.Mset),predictions(:,j)=dmt_qam_ber(cfg.Mset(j),gamma);end
allowed=predictions<=cfg.targetBER;
M=zeros(0,1);
if all(allowed(:,1))
    M=zeros(numel(gamma),1);
    for j=1:numel(gamma),M(j)=max(cfg.Mset(allowed(j,:)));end
end
end
