function [quantized,adc] = dmt_to_quantize(y,q,cfg,bypass)
%DMT_TO_QUANTIZE Fixed-range, saturating uniform mid-rise receiver ADC.
% The exact upper endpoint maps to the highest level, but is not counted
% as an input outside the declared closed interval [lo,hi].
if nargin<4, bypass=false; end
assert(~isempty(y) && isreal(y) && all(isfinite(y(:))), ...
    'DMT:TOADCInput','ADC input must be nonempty finite real samples.');
assert(isscalar(q) && q==fix(q) && q>=1 && q<=16,'DMT:TOADCBits','Invalid ideal ADC bit count.');
assert(numel(cfg.adc_range)==2 && all(isfinite(cfg.adc_range)) && ...
    cfg.adc_range(2)>cfg.adc_range(1));
assert(islogical(bypass) && isscalar(bypass));
lo=cfg.adc_range(1); hi=cfg.adc_range(2);
levels=2^q; step=(hi-lo)/levels;
adc=struct('low_count',sum(y(:)<lo),'high_count',sum(y(:)>hi), ...
    'sample_count',numel(y),'step',step,'levels',levels, ...
    'input_min',min(y(:)),'input_max',max(y(:)), ...
    'range',cfg.adc_range,'bypass',bypass);
if bypass
    quantized=y;
else
    index=floor((y-lo)/step);
    index=min(levels-1,max(0,index));
    quantized=lo+(index+0.5)*step;
end
end
