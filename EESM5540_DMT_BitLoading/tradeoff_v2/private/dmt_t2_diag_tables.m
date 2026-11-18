function tables = dmt_t2_diag_tables(cfg,settings,plan,calibrations,training,runs)
%DMT_T2_DIAG_TABLES Validate paired raw transmissions and reconstruct counts.
phase = string(settings.phase);
seed = cell(height(plan(plan.role=="payload",:)),1);
pooled = cell(settings.calibration_count*4,1);
summary = pooled;
runStatus = seed;
n = 0;
m = 0;
for c = 1:settings.calibration_count
    cal = calibrations{c};
    assert(strcmp(cal.phase,settings.phase) && cal.calibration_id==c && isequal(cal.M,settings.M));
    assert(cal.g==cal.gain_calibration.b/(cfg.rho*cfg.sigma_ref));
    assert(abs(cal.gain_calibration.actual_mean-settings.P_target)<=cfg.power_cal_tolerance*settings.P_target);
    assert(isequal([cal.offsets.P_peak],settings.P_peaks));
    assert(all(abs([cal.offsets.mean_power]-settings.P_target)<=cfg.power_cal_tolerance*settings.P_target));
    assert(cal.offset_symbols==cfg.power_cal_symbols && ...
        cal.offset_sample_count==cfg.power_cal_symbols*(cfg.NFFT+cfg.NCP));
    gainRow = plan(plan.calibration_id==c & plan.treatment_id==1 & plan.role=="tx_gain_calibration",:);
    offsetRow = plan(plan.calibration_id==c & plan.treatment_id==1 & plan.role=="tx_dc_calibration",:);
    assert(cal.gain_calibration.seed==gainRow.data_seed && cal.offset_data_seed==offsetRow.data_seed);
    powers = cellfun(@(r)r.P_measured,squeeze(runs(c,:,:)));
    powerMatched = abs(powers-settings.P_target)<=cfg.payload_power_tolerance*settings.P_target;
    pairMatched = all(powerMatched,1) & ...
        (max(powers,[],1)-min(powers,[],1)<=cfg.pair_power_tolerance*settings.P_target);
    for arm = 1:4
        t = training{c,arm};
        expected = plan(plan.calibration_id==c & plan.treatment_id==arm & plan.role=="training",:);
        checkRecord(t,expected,cfg,settings,cal);
        assert(isempty(t.tested_bits) && isempty(t.error_bits));
        assert(isequaln(t.H_hat,t.cross_sum./t.known_energy));
        checkRxPair(t,training{c,otherMode(arm)});
        totalBits = zeros(numel(cfg.k),1,'uint64');
        totalErrors = totalBits;
        samples = 0;
        txLow = 0;
        txHigh = 0;
        adcLow = 0;
        adcHigh = 0;
        for slot = 1:settings.payload_repeats
            r = runs{c,arm,slot};
            expected = plan(plan.calibration_id==c & plan.treatment_id==arm & ...
                plan.role=="payload" & plan.payload_slot==slot,:);
            checkRecord(r,expected,cfg,settings,cal);
            assert(isequal(r.H_hat,t.H_hat) && strcmp(r.training_hash,dmt_v13_hash(t)));
            assert(isequal(r.tested_bits,uint64(expected.symbols*log2(settings.M))));
            assert(isa(r.error_bits,'uint64') && isequal(size(r.error_bits),size(r.tested_bits)));
            assert(all(r.error_bits<=r.tested_bits));
            checkRxPair(r,runs{c,otherMode(arm),slot});
            totalBits = totalBits+r.tested_bits;
            totalErrors = totalErrors+r.error_bits;
            samples = samples+r.samples;
            txLow = txLow+r.tx_lower_clip_count;
            txHigh = txHigh+r.tx_upper_clip_count;
            adcLow = adcLow+r.adc_low_count;
            adcHigh = adcHigh+r.adc_high_count;
            n = n+1;
            seed{n}=toneTable(cfg,settings,c,arm,slot,r.tested_bits,r.error_bits);
            status = "complete";
            if ~powerMatched(arm,slot), status="power_mismatch"; end
            runStatus{n}=table(phase,c,arm,slot,status,r.identity.data_seed,r.identity.noise_seed, ...
                uint64(r.samples),r.P_measured,powerMatched(arm,slot),pairMatched(slot), ...
                uint64(r.tx_lower_clip_count),uint64(r.tx_upper_clip_count), ...
                uint64(r.adc_low_count),uint64(r.adc_high_count),r.g,r.d,r.compute_seconds, ...
                'VariableNames',{'phase','calibration_id','treatment_id','payload_slot', ...
                'state','data_seed','noise_seed','sample_count','P_measured','power_match', ...
                'paired_power_match','tx_low_clip_count','tx_high_clip_count','adc_low_count', ...
                'adc_high_count','ac_gain','dc_offset','compute_seconds'});
        end
        m = m+1;
        pooled{m}=toneTable(cfg,settings,c,arm,0,totalBits,totalErrors);
        lo = pooled{m}.wilson_lower;
        hi = pooled{m}.wilson_upper;
        uMax = max(hi);
        individualOK = all(powerMatched(arm,:));
        pairedOK = all(pairMatched);
        state = "inconclusive";
        if ~individualOK, state="power_mismatch";
        elseif any(lo>cfg.targetBER), state="ber_failed";
        elseif all(hi<cfg.targetBER), state="supported"; end
        summary{m}=table(phase,c,arm,expected.treatment,expected.P_peak,expected.adc_mode, ...
            settings.P_target,mean(powers(arm,:)), max(powers(arm,:)), ...
            individualOK,pairedOK,state,uint64(samples),uint64(txLow),uint64(txHigh), ...
            uint64(adcLow),uint64(adcHigh),(txLow+txHigh)/samples,(adcLow+adcHigh)/samples, ...
            uMax,uMax/cfg.targetBER, ...
            'VariableNames',{'phase','calibration_id','treatment_id','treatment','P_peak',...
            'adc_mode','P_target','P_measured_mean','P_measured_max','power_match', ...
            'paired_power_match','state','sample_count','tx_low_clip_count','tx_high_clip_count',...
            'adc_low_count','adc_high_count','tx_clip_rate','adc_out_of_range_rate', ...
            'wilson_Umax','Umax_over_target'});
    end
end
tables = struct('seed_counts',vertcat(seed{:}),'pooled_counts',vertcat(pooled{:}), ...
    'summary',vertcat(summary{:}),'slot_status',vertcat(runStatus{:}));
end

function p = otherMode(arm)
if mod(arm,2)==1, p=arm+1; else, p=arm-1; end
end

function checkRxPair(r,peer)
% Within each cap the ADC processing mode is the only treatment change.
fields = {'P_measured','samples','optical_sum','tx_lower_clip_count', ...
    'tx_upper_clip_count','adc_low_count','adc_high_count'};
for k = 1:numel(fields)
    key = fields{k};
    assert(r.(key)==peer.(key),'DMT:T2DiagnosticPairDrift', ...
        'Changing ADC mode changed a pre-ADC observable in its matched pair.');
end
end

function checkRecord(r,row,cfg,settings,cal)
assert(height(row)==1 && isequaln(r.identity,table2struct(row)));
assert(isequal(r.M,settings.M) && r.g==cal.g && isequal(size(r.H_hat),size(settings.M)));
assert(all(isfinite(r.H_hat) & abs(r.H_hat)>0));
offset = cal.offsets([cal.offsets.P_peak]==row.P_peak);
assert(r.d==offset.d && r.samples==row.symbols*(cfg.NFFT+cfg.NCP));
assert(r.optical_sum>=0 && r.optical_sum<=row.P_peak*r.samples && ...
    r.P_measured==r.optical_sum/r.samples);
counts = [r.tx_lower_clip_count,r.tx_upper_clip_count,r.adc_low_count,r.adc_high_count];
assert(all(counts>=0 & counts==fix(counts)));
assert(sum(counts(1:2))<=r.samples && sum(counts(3:4))<=r.samples);
end

function output = toneTable(cfg,settings,c,arm,slot,tested,errors)
n = numel(cfg.k);
[lo,hi] = dmt_wilson(double(errors),double(tested));
output = table(repmat(string(settings.phase),n,1),repmat(c,n,1), ...
    repmat(arm,n,1),repmat(slot,n,1),cfg.k(:),settings.M, ...
    tested,errors,double(errors)./double(tested),lo,hi, ...
    'VariableNames',{'phase','calibration_id','treatment_id','payload_slot', ...
    'subcarrier','M','tested_bits','error_bits','BER','wilson_lower','wilson_upper'});
end
