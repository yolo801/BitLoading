function scale = dmt_vm_drive_scale(cfg,condition)
%DMT_VM_DRIVE_SCALE Scale the input to the physical optical clipper.
% With Es=1 and N positive-frequency bins, the useful time-domain DMT
% waveform has reference RMS sqrt(2*N/NFFT). The hypothetical waveform
% with peaks at +/-rho times that RMS defines the command reference.
% The bias b is an independently calibrated additive offset.
assert(cfg.Es==1 && isscalar(cfg.rho) && cfg.rho>0 && ...
    isscalar(condition.swing) && isfinite(condition.swing) && condition.swing>=0 && ...
    isscalar(condition.P_target) && isfinite(condition.P_target) && condition.P_target>0, ...
    'DMT:VMDrive','Invalid energy, reference RMS multiplier, swing or power target.');
sigmaRef=sqrt(2*numel(cfg.k)*cfg.Es/cfg.NFFT);
scale=condition.swing*condition.P_target/(cfg.rho*sigmaRef);
end
