function [points,requirements,pairs]=dmt_fb_graphics_scan(cfg,tables)
%DMT_FB_GRAPHICS_SCAN Derive report rows from audited acquisition tables.
points=sortrows(tables.scenario,{'P_target','q','scheme'});
assert(height(points)==24 && height(tables.status)==240 && ...
    all(~points.test_only & points.phase=="formal" & points.planned_calibrations==5), ...
    'DMT:FBGraphicsScope','Fig. B expects the complete formal eight-condition scan.');
measured={'observed_power_min','observed_power_max','qualified_power_min','qualified_power_max', ...
    'supported_power_min','supported_power_max','observed_transmitted_slots', ...
    'supported_transmitted_slots','mean_bits_observed','mean_setup_symbols_observed', ...
    'observed_sample_count','tx_clip_count','tx_clip_rate','adc_oob_count','adc_oob_rate'};
for j=1:numel(measured),points.(measured{j})=nan(height(points),1);end
points.qualified_rate_min_Mbps=points.R_cycle_min/1e6;
points.qualified_rate_median_Mbps=points.R_cycle_median/1e6;
points.qualified_rate_max_Mbps=points.R_cycle_max/1e6;
for j=1:height(points)
    item=points(j,:);
    summary=selectRows(tables.summary,item);
    status=selectRows(tables.status,item);
    power=selectRows(tables.power_adc,item);
    sent=status(status.status=="completed",:);
    accepted=summary.calibration_id(summary.state=="supported");
    qualifying=sent(ismember(sent.calibration_id,accepted),:);
    assert(height(summary)==5 && height(status)==10 && height(power)==height(sent) && ...
        height(qualifying)==2*item.supported_count);
    points.observed_transmitted_slots(j)=height(sent);
    points.supported_transmitted_slots(j)=height(qualifying);
    if ~isempty(sent)
        assert(all(isfinite(sent.P_actual)));
        points.observed_power_min(j)=min(sent.P_actual);
        points.observed_power_max(j)=max(sent.P_actual);
        assert(points.observed_power_max(j)==item.P_actual_max);
        counts=power.samples;
        allSamples=sum(counts);
        assert(all(counts>0));
        txClipped=sum(power.tx_low_count+power.tx_high_count);
        adcOutside=sum(power.adc_low_count+power.adc_high_count);
        points.observed_sample_count(j)=allSamples;
        points.tx_clip_count(j)=txClipped;
        points.tx_clip_rate(j)=txClipped/allSamples;
        points.adc_oob_count(j)=adcOutside;
        points.adc_oob_rate(j)=adcOutside/allSamples;
        measuredDesign=summary(ismember(summary.calibration_id,sent.calibration_id),:);
        points.mean_bits_observed(j)=mean(measuredDesign.bits_per_symbol);
        points.mean_setup_symbols_observed(j)=mean(measuredDesign.setup_symbols);
    end
    if ~isempty(qualifying)
        assert(all(qualifying.power_match));
        points.supported_power_min(j)=min(qualifying.P_actual);
        points.supported_power_max(j)=max(qualifying.P_actual);
    end
    if item.qualified
        assert(height(qualifying)==10 && all(qualifying.power_match) && ...
            isfinite(item.R_cycle_min) && item.R_cycle_min<=item.R_cycle_max);
        points.qualified_power_min(j)=min(qualifying.P_actual);
        points.qualified_power_max(j)=max(qualifying.P_actual);
    end
end
requirements=minMeasuredPower(points,cfg.scheme_names);
pairs=compareADC(points,tables.status,cfg);
end

function t=selectRows(t,r)
t=t(t.condition_id==r.condition_id & t.scheme==r.scheme,:);
end

function t=minMeasuredPower(points,schemes)
template=struct('q',NaN,'scheme',"",'required_rate_Mbps',75,'status',"", ...
    'selected_condition_id',NaN,'selected_P_target',NaN, ...
    'measured_power_min',NaN,'measured_power_max',NaN,'qualified_rate_min_Mbps',NaN, ...
    'qualified_rate_median_Mbps',NaN,'qualified_rate_max_Mbps',NaN);
result=repmat(template,2*numel(schemes),1);
count=0;
for q=[6 8]
    for s=1:numel(schemes)
        count=count+1;
        r=template;r.q=q;r.scheme=string(schemes{s});
        one=points(points.q==q & points.scheme==r.scheme,:);
        assert(height(one)==4);
        candidates=one(one.qualified & one.qualified_rate_min_Mbps>=r.required_rate_Mbps,:);
        r.status="no_qualified_tested_point";
        if ~isempty(candidates)
            candidates=sortrows(candidates,{'qualified_power_max','P_target','condition_id'});
            best=candidates(1,:);
            r.status="qualified_tested_point";
            r.selected_condition_id=best.condition_id;
            r.selected_P_target=best.P_target;
            r.measured_power_min=best.qualified_power_min;
            r.measured_power_max=best.qualified_power_max;
            r.qualified_rate_min_Mbps=best.qualified_rate_min_Mbps;
            r.qualified_rate_median_Mbps=best.qualified_rate_median_Mbps;
            r.qualified_rate_max_Mbps=best.qualified_rate_max_Mbps;
        end
        result(count)=r;
    end
end
t=struct2table(result);
end

function t=compareADC(points,status,cfg)
template=struct('P_target',NaN,'scheme',"",'condition_6bit',NaN,'condition_8bit',NaN, ...
    'paired_slots',0,'largest_power_gap',NaN,'supported_calibrations_6bit',0, ...
    'supported_calibrations_8bit',0,'status',"",'qualified_rate_median_6bit_Mbps',NaN, ...
    'qualified_rate_median_8bit_Mbps',NaN,'qualified_rate_delta_8minus6_Mbps',NaN);
result=repmat(template,height(points)/2,1);
one=points(points.q==6,:);
for j=1:height(one)
    low=one(j,:);
    high=points(points.q==8 & points.P_target==low.P_target & points.scheme==low.scheme,:);
    assert(height(high)==1);
    left=selectRows(status,low);right=selectRows(status,high);
    key={'calibration_id','payload_slot'};
    left=sortrows(left,key);right=sortrows(right,key);
    assert(height(left)==10 && isequal(left(:,key),right(:,key)));
    observed=left.status=="completed" & right.status=="completed";
    gap=abs(left.P_actual-right.P_actual);
    matched=observed & left.power_match & right.power_match & ...
        gap<=cfg.pair_power_tolerance*low.P_target;
    r=template;
    r.P_target=low.P_target;r.scheme=low.scheme;
    r.condition_6bit=low.condition_id;r.condition_8bit=high.condition_id;
    r.paired_slots=sum(matched);
    r.supported_calibrations_6bit=low.supported_count;
    r.supported_calibrations_8bit=high.supported_count;
    r.qualified_rate_median_6bit_Mbps=low.qualified_rate_median_Mbps;
    r.qualified_rate_median_8bit_Mbps=high.qualified_rate_median_Mbps;
    if any(observed),r.largest_power_gap=max(gap(observed));end
    r.status="no_complete_payload_pair";
    if all(observed)
        r.status="power_pair_mismatch";
        if all(matched)
            r.status="matched_without_two_qualified_rates";
            if low.qualified && high.qualified
                r.status="qualified_power_matched_adc_comparison";
                r.qualified_rate_delta_8minus6_Mbps=r.qualified_rate_median_8bit_Mbps- ...
                    r.qualified_rate_median_6bit_Mbps;
            end
        end
    end
    result(j)=r;
end
t=struct2table(result);
end
