function power = dmt_vm_power_cal(cfg,condition,M,dataSeed)
%DMT_VM_POWER_CAL Calibrate bias on one independent TX-only waveform.
% The AC command is fixed throughout bisection. Only the additive optical
% bias changes, and every trial is evaluated after the common clipper.
timer=tic;
M=M(:);
assert(numel(M)==numel(cfg.k) && all(ismember(M,cfg.Mset)));
assert(cfg.power_cal_symbols>=1 && cfg.power_cal_symbols==fix(cfg.power_cal_symbols));
assert(isscalar(condition.P_target) && isfinite(condition.P_target) && condition.P_target>0);
assert(cfg.b_bounds(1)>=0 && cfg.b_bounds(2)>cfg.b_bounds(1));
dataStream=dmt_v13_stream(cfg,dataSeed);
nSamples=cfg.power_cal_symbols*(cfg.NFFT+cfg.NCP);
serial=zeros(nSamples,1); done=0;
while done<cfg.power_cal_symbols
    count=min(cfg.chunkSize,cfg.power_cal_symbols-done);
    X=dmt_v13_make_frame(cfg,M,count,dataStream);
    xc=sqrt(cfg.NFFT)*ifft(X,[],1);
    assert(max(abs(imag(xc(:))))<=1e-12*max(1,max(abs(xc(:)))));
    x=real(xc); withCP=[x(end-cfg.NCP+1:end,:);x];
    offset=done*(cfg.NFFT+cfg.NCP);
    serial(offset+(1:numel(withCP)))=withCP(:);
    done=done+count;
end
% This drive remains unchanged for every trial b.
drive=dmt_vm_drive_scale(cfg,condition)*serial;
grid=linspace(cfg.b_bounds(1),cfg.b_bounds(2),9).';
gridMean=zeros(size(grid));
for j=1:numel(grid), gridMean(j)=mean(mapped(grid(j))); end
monotone=all(diff(gridMean)>=-1e-13*max(1,cfg.P_peak));
assert(monotone,'DMT:TOPowerMonotonicity','Fixed-waveform mean power is not monotone in b.');
target=condition.P_target;
reachable=target>=gridMean(1) && target<=gridMean(end);
assert(reachable,'DMT:TOPowerUnreachable','Target is outside the declared b interval for this waveform.');
lo=cfg.b_bounds(1); hi=cfg.b_bounds(2);
historyB=[lo;hi]; historyMean=[gridMean(1);gridMean(end)];
b=lo; actual=gridMean(1); iterations=0;
if abs(actual-target)/target>cfg.power_cal_tolerance
    b=hi; actual=gridMean(end);
end
while abs(actual-target)/target>cfg.power_cal_tolerance && iterations<cfg.power_cal_max_iterations
    b=(lo+hi)/2; actual=mean(mapped(b));
    iterations=iterations+1;
    historyB(end+1,1)=b; historyMean(end+1,1)=actual; %#ok<AGROW>
    if actual<target, lo=b; else, hi=b; end
end
relative=(actual-target)/target;
assert(abs(relative)<=cfg.power_cal_tolerance,'DMT:TOPowerCalibration', ...
    'Fixed-waveform bisection did not meet the declared power tolerance.');
p=mapped(b); raw=b+drive;
power=struct('b',b,'actual_mean',actual,'target',target,'relative_error',relative, ...
    'iterations',iterations,'reachable',reachable,'monotone',monotone, ...
    'seed',dataSeed,'data_seed',dataSeed,'M',M, ...
    'symbols',cfg.power_cal_symbols,'sample_count',nSamples, ...
    'waveform_hash',dmt_sha256(typecast(serial,'uint8')), ...
    'history_b',historyB,'history_mean',historyMean, ...
    'monotonic_b_grid',grid,'monotonic_mean_grid',gridMean, ...
    'history',table(historyB,historyMean,'VariableNames',{'b','actual_mean'}), ...
    'mean_square',mean(p.^2),'peak',max(p),'minimum',min(p), ...
    'lower_clip_count',sum(raw<0),'upper_clip_count',sum(raw>cfg.P_peak), ...
    'tx_sum',sum(p),'drive_ac_sum',sum(drive),'drive_ac_sq_sum',sum(drive.^2), ...
    'drive_ac_peak_abs',max(abs(drive)), ...
    'drive_ac_mean_square',mean(drive.^2), ...
    'commanded_swing',condition.swing,'commanded_peak',condition.swing*condition.P_target, ...
    'compute_seconds',toc(timer));
power=dmt_vm_tx_summary(power,p,cfg.P_peak);

    function p=mapped(value)
        p=min(cfg.P_peak,max(0,value+drive));
    end
end
