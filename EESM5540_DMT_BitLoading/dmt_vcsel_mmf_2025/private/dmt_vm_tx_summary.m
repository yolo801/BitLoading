function metrics = dmt_vm_tx_summary(metrics,p,peak)
%DMT_VM_TX_SUMMARY Add TX waveform summaries from exact sums and a histogram.
% Histogram counts include every clipped optical sample and are mergeable.
% Each percentile is a nearest-rank order statistic, represented by the
% midpoint of its bin; the absolute power error is at most half a bin.
if nargin>1
    metrics.tx_hist_bins=4096;
    metrics.tx_hist_max=peak;
    metrics.tx_hist_counts=histcounts(p,linspace(0,peak,metrics.tx_hist_bins+1));
end
counts=metrics.tx_hist_counts;
assert(numel(counts)==metrics.tx_hist_bins && sum(counts)==metrics.sample_count && ...
    metrics.sample_count>0,'DMT:VMTxHistogram','Invalid TX histogram count.');
accumulated=cumsum(counts);
binWidth=metrics.tx_hist_max/metrics.tx_hist_bins;
q01=find(accumulated>=ceil(.01*metrics.sample_count),1);
q99=find(accumulated>=ceil(.99*metrics.sample_count),1);
metrics.tx_p01=(q01-.5)*binWidth;
metrics.tx_p99=(q99-.5)*binWidth;
metrics.drive_ac_rms=sqrt(metrics.drive_ac_sq_sum/metrics.sample_count);
if metrics.drive_ac_rms>0
    metrics.drive_papr_dB=20*log10(metrics.drive_ac_peak_abs/metrics.drive_ac_rms);
else
    metrics.drive_papr_dB=NaN;
end
meanPower=metrics.tx_sum/metrics.sample_count;
if meanPower>0
    metrics.observed_swing=(metrics.tx_p99-metrics.tx_p01)/(2*meanPower);
else
    metrics.observed_swing=NaN;
end
end
