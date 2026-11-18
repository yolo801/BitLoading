function [row,meanPower]=dmt_vm_table_metrics(cfg,condition,block)
%DMT_VM_TABLE_METRICS Recompute archived physical statistics from raw sums.
row=struct('samples',NaN,'P_actual',NaN,'P_relative_error',NaN,'tx_sum',NaN, ...
    'tx_sum_sq',NaN,'optical_second_moment',NaN,'P_min',NaN,'P_max',NaN, ...
    'commanded_swing',NaN,'commanded_peak',NaN,'observed_swing',NaN, ...
    'tx_p01',NaN,'tx_p99',NaN,'tx_hist_bin_width',NaN, ...
    'drive_ac_mean',NaN,'drive_ac_rms',NaN,'drive_ac_peak_abs',NaN,'drive_papr_dB',NaN, ...
    'tx_low_count',NaN,'tx_high_count',NaN,'tx_clip_rate',NaN, ...
    'clip_error_sq_sum',NaN,'clip_error_rms',NaN,'clip_excess_rms_when_clipped',NaN, ...
    'adc_low_count',NaN,'adc_high_count',NaN,'adc_oob_rate',NaN, ...
    'noise_mean',NaN,'noise_second_moment',NaN);
meanPower=NaN;
if nargin==0,return;end
received=isfield(block,'metrics');
if received
    m=block.metrics;
    assert(m.symbols==block.symbols);
    row.tx_sum_sq=m.tx_sum_sq;
    row.P_min=m.tx_min;
    row.P_max=m.tx_max;
else
    m=block;
    row.tx_sum_sq=m.mean_square*m.sample_count;
    row.P_min=m.minimum;
    row.P_max=m.peak;
end
samples=block.symbols*(cfg.NFFT+cfg.NCP);
assert(m.sample_count==samples && samples>0 && ...
    m.commanded_swing==condition.swing && m.commanded_peak==condition.P_target*condition.swing, ...
    'DMT:VMHistogramAccounting','Sent sample counts must include CP and keep the frozen command.');
counts=double(m.tx_hist_counts(:));
assert(numel(counts)==m.tx_hist_bins && m.tx_hist_bins==4096 && m.tx_hist_max==cfg.P_peak && ...
    all(isfinite(counts) & counts>=0 & counts==fix(counts)) && sum(counts)==samples, ...
    'DMT:VMHistogramAccounting','Optical power histogram does not account for all samples.');
power=m.tx_sum/samples;
assert(isfinite(power) && power>0 && power<=cfg.P_peak && ...
    row.P_min>=0 && row.P_max<=cfg.P_peak && ...
    power>=row.P_min-1e-12 && power<=row.P_max+1e-12 && ...
    row.tx_sum_sq>=samples*(power^2-1e-12) && ...
    row.tx_sum_sq<=m.tx_sum*cfg.P_peak+1e-12*samples, ...
    'DMT:VMOpticalMoments','Saved optical extrema and moments violate physical clipping bounds.');
if ~received
    assert(abs(power-m.actual_mean)<=1e-12 && abs((power-condition.P_target)/condition.P_target) ...
        <=cfg.power_cal_tolerance+1e-12,'DMT:VMOpticalMoments','TX-only power did not meet its caliper.');
end
levels=cumsum(counts);
width=cfg.P_peak/numel(counts);
low=(find(levels>=ceil(.01*samples),1,'first')-.5)*width;
high=(find(levels>=ceil(.99*samples),1,'first')-.5)*width;
obs=(high-low)/(2*power);
rms=sqrt(m.drive_ac_sq_sum/samples);
assert(isfinite(rms) && rms>0 && m.drive_ac_peak_abs>=rms && ...
    abs(m.drive_ac_sum/samples)<=rms+1e-12,'DMT:VMDriveMoments','Invalid AC moments.');
papr=10*log10((m.drive_ac_peak_abs/rms)^2);
assert(max(abs([m.tx_p01 m.tx_p99 m.observed_swing m.drive_ac_rms m.drive_papr_dB]- ...
    [low high obs rms papr]))<=5e-12,'DMT:VMOpticalStats', ...
    'Saved percentile swing or pre-clip PAPR differs from raw histogram and sums.');

counts=[m.lower_clip_count m.upper_clip_count];
assert(all(isfinite(counts) & counts>=0 & counts==fix(counts)) && sum(counts)<=samples, ...
    'DMT:VMClipCount','Invalid integer optical clipping counters.');
row.samples=samples;
row.P_actual=power;
row.P_relative_error=(power-condition.P_target)/condition.P_target;
row.tx_sum=m.tx_sum;
row.optical_second_moment=row.tx_sum_sq/samples;
row.commanded_swing=condition.swing;
row.commanded_peak=m.commanded_peak;
row.observed_swing=obs;
row.tx_p01=low;
row.tx_p99=high;
row.tx_hist_bin_width=width;
row.drive_ac_mean=m.drive_ac_sum/samples;
row.drive_ac_rms=rms;
row.drive_ac_peak_abs=m.drive_ac_peak_abs;
row.drive_papr_dB=papr;
row.tx_low_count=counts(1);
row.tx_high_count=counts(2);
row.tx_clip_rate=sum(counts)/samples;
meanPower=power;
if received
    adc=[m.adc_low_count m.adc_high_count];
    assert(all(isfinite(adc) & adc>=0 & adc==fix(adc)) && sum(adc)<=samples && ...
        isfinite(m.clip_error_sq_sum) && m.clip_error_sq_sum>=0 && ...
        (sum(counts)>0 || m.clip_error_sq_sum==0) && ...
        isfinite(m.noise_sum_sq) && m.noise_sum_sq>=0 && isfinite(m.noise_sum), ...
        'DMT:VMAdcCount','Invalid ADC counts, noise moments or optical clipping excess.');
    row.adc_low_count=adc(1);
    row.adc_high_count=adc(2);
    row.adc_oob_rate=sum(adc)/samples;
    row.clip_error_sq_sum=m.clip_error_sq_sum;
    row.clip_error_rms=sqrt(m.clip_error_sq_sum/samples);
    if sum(counts)>0
        row.clip_excess_rms_when_clipped=sqrt(m.clip_error_sq_sum/sum(counts));
    end
    row.noise_mean=m.noise_sum/samples;
    row.noise_second_moment=m.noise_sum_sq/samples;
end
end
