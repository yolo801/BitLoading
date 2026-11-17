function tables=dmt_to_tables(cfg,phase,plan,shared,designs,runs)
%DMT_TO_TABLES Rebuild all outputs from actual, separately stratified records.
% Design rejection, BER evidence and power matching are separate properties.
phase=validatestring(phase,{'preflight','formal'});
assert(iscell(shared)&&iscell(designs)&&iscell(runs));
assert(istable(plan)&&all(string(plan.phase)==string(phase)));
calIDs=unique(plan.calibration_id).';
nCal=numel(calIDs); nK=numel(cfg.k); nSchemes=numel(cfg.scheme_names);
assert(nK==24 && nCal>=1);
L=cfg.payload_symbols;
if strcmp(phase,'preflight'),L=cfg.preflight_payload_symbols;end
conditions=unique(plan(:,{'condition_id','P_target','q'}),'rows');
conditions=sortrows(conditions,'condition_id');
seed=carrierTemplate(); pooled=seed; summaryRows={}; statusRows={};
metricRows={}; powerRows={}; roundRows={}; costRows={}; feedbackRows={}; profileRows={};
seenRunKeys=strings(0,1);
for ci=1:height(conditions)
    cond=table2struct(conditions(ci,:));
    for cal=calIDs
        initial=findRecord(shared,cond.condition_id,cal,'',NaN);
        if ~isempty(initial)
            powerRows{end+1}=powerRow(phase,cond,cal,'Shared',0,'initial_power',initial.power0); %#ok<AGROW>
        end
        for si=1:nSchemes
            scheme=cfg.scheme_names{si};
            design=findRecord(designs,cond.condition_id,cal,scheme,NaN);
            row=summaryTemplate(phase,cond,cal,scheme,cfg.payload_repeats,L);
            row.initial_calibration_available=~isempty(initial);
            if ~isempty(design)
                assert(strcmp(design.phase,phase));
                row.design_status=string(design.status);
                row.design_round_count=numel(design.rounds);
                row.design_processed=true;
                accepted=strcmp(design.status,'accepted');
                row.design_accepted=accepted;
                if ~accepted
                    assert(ismember(string(design.status),["no_initial_candidate", ...
                        "no_accepted_profile_min_order","round_budget_exhausted"]));
                    row.payload_state="design_rejected";
                    row.BER_state="design_rejected";
                else
                    assert(numel(design.M)==nK && all(ismember(design.M,cfg.Mset)));
                    row.b=design.b;row.B_DMT=sum(log2(design.M));
                    row.R_nominal=row.B_DMT/cfg.Ts;
                    row.configuration_hash=string(dmt_v13_hash(design.final_tx));
                    for k=1:nK
                        p=struct('phase',string(phase),'condition_id',cond.condition_id, ...
                            'P_target',cond.P_target,'q',cond.q,'calibration_id',cal, ...
                            'scheme',string(scheme),'k',cfg.k(k),'M',design.M(k), ...
                            'bits_k',log2(design.M(k)),'b',design.b, ...
                            'configuration_hash',row.configuration_hash);
                        profileRows{end+1}=p; %#ok<AGROW>
                    end
                end
                for ri=1:numel(design.rounds)
                    r=design.rounds(ri);
                    powerRows{end+1}=powerRow(phase,cond,cal,scheme,r.round,'power',r.power); %#ok<AGROW>
                    [lo,hi]=dmt_wilson(r.Dr.error_bits,r.Dr.tested_bits);
                    for k=1:nK
                        rr=struct('phase',string(phase),'condition_id',cond.condition_id, ...
                            'P_target',cond.P_target,'q',cond.q,'calibration_id',cal, ...
                            'scheme',string(scheme),'round',r.round,'k',cfg.k(k), ...
                            'M',r.M(k),'b',r.power.b,'A_symbols',r.Ar.symbols, ...
                            'D_symbols',r.Dr.symbols,'tested_bits',double(r.Dr.tested_bits(k)), ...
                            'error_bits',double(r.Dr.error_bits(k)), ...
                            'BER',double(r.Dr.error_bits(k))/double(r.Dr.tested_bits(k)), ...
                            'CI_low',lo(k),'CI_high',hi(k),'CI_upper_over_target',hi(k)/cfg.targetBER, ...
                            'supported',hi(k)<cfg.targetBER,'round_status',string(r.status), ...
                            'power_data_seed',r.power.seed,'A_data_seed',r.Ar.seeds.data_seed, ...
                            'A_noise_seed',r.Ar.seeds.noise_seed,'D_data_seed',r.Dr.seeds.data_seed, ...
                            'D_noise_seed',r.Dr.seeds.noise_seed);
                        roundRows{end+1}=rr; %#ok<AGROW>
                    end
                end
            end
            cost=makeCost(cfg,phase,cond,cal,scheme,initial,design,L);
            costRows{end+1}=cost; %#ok<AGROW>
            row.shared_A0_symbols=cost.A0_symbols;row.shared_B0_symbols=cost.B0_symbols;
            row.design_A_symbols=cost.Ar_symbols;row.design_D_symbols=cost.Dr_symbols;
            row.setup_link_symbols=cost.setup_link_symbols;
            row.TX_power_cal_symbols=cost.TX_power_cal_symbols;
            row.setup_optical_energy_norm=cost.setup_optical_energy_norm;
            if row.design_accepted
                row.R_cycle=L*row.B_DMT/((cost.setup_link_symbols+L)*cfg.Ts+cfg.control_delay);
            end
            if ~isempty(design)
                feedbackRows{end+1}=makeFeedback(phase,cond,cal,scheme,design,nK); %#ok<AGROW>
            end
            selected={}; bits=zeros(nK,1);errors=bits;
            for slot=1:cfg.payload_repeats
                one=findRecord(runs,cond.condition_id,cal,scheme,slot);
                status=runTemplate(phase,cond,cal,scheme,slot,L);
                status.design_status=row.design_status;
                if row.payload_state=="design_rejected"
                    assert(isempty(one),'DMT:TradeoffRejectedPayload','Rejected design has payload.');
                    status.status="design_rejected";status.reason=row.design_status;
                elseif ~isempty(one)
                    assert(row.design_accepted && ~isempty(initial));
                    validatePayload(cfg,phase,cond,cal,scheme,slot,design,one,L);
                    key=sprintf('%d:%d:%s:%d',cond.condition_id,cal,scheme,slot);
                    assert(~any(seenRunKeys==string(key)),'DMT:TradeoffDuplicatePayload','Duplicate payload key.');
                    seenRunKeys(end+1,1)=string(key); %#ok<AGROW>
                    selected{end+1}=one; %#ok<AGROW>
                    bits=bits+double(one.tested_bits(:));errors=errors+double(one.error_bits(:));
                    seed=[seed;carrierRows(cfg,phase,cond,cal,scheme,slot,design, ...
                        one.tested_bits,one.error_bits,one.symbols,1,one.power_actual,one.power_match, ...
                        one.seeds.data_seed,one.seeds.noise_seed)]; %#ok<AGROW>
                    status.status="completed";status.reason="full_fixed_payload_completed";
                    status.actual_symbols=one.symbols;status.tested_bits=sum(double(one.tested_bits));
                    status.error_bits=sum(double(one.error_bits));status.P_actual=one.power_actual;
                    status.power_match=logical(one.power_match);status.configuration_hash=row.configuration_hash;
                    status.data_seed=one.seeds.data_seed;status.noise_seed=one.seeds.noise_seed;
                    metricRows{end+1}=payloadMetric(cfg,phase,cond,cal,scheme,slot,one,design,cost); %#ok<AGROW>
                elseif ~row.design_processed
                    status.reason="design_not_evaluated";
                else
                    status.reason="accepted_design_payload_not_completed";
                end
                statusRows{end+1}=status; %#ok<AGROW>
            end
            row.test_seed_count=numel(selected);
            if ~isempty(selected)
                row.actual_payload_symbols=sum(cellfun(@(x)x.symbols,selected));
                row.partial_tested_bits=sum(bits);row.partial_error_bits=sum(errors);
                powers=cellfun(@(x)x.power_actual,selected);
                row.P_actual_min=min(powers);row.P_actual_median=median(powers);row.P_actual_max=max(powers);
                row.all_payload_power_match=all(cellfun(@(x)logical(x.power_match),selected));
                row.power_state="matched";
                if ~row.all_payload_power_match,row.power_state="power_mismatch";end
            end
            if numel(selected)==cfg.payload_repeats
                row.payload_state="completed";
                row.total_tested_bits=sum(bits);row.total_error_bits=sum(errors);
                row.overall_BER=sum(errors)/sum(bits);row.worst_subcarrier_BER=max(errors./bits);
                [lo,hi]=dmt_wilson(errors,bits);
                row.max_CI_upper_over_target=max(hi)/cfg.targetBER;
                row.BER_state=classify(lo,hi,cfg.targetBER);
                row.failed_k=string(mat2str(cfg.k(lo>cfg.targetBER).'));
                row.inconclusive_k=string(mat2str(cfg.k(lo<=cfg.targetBER & hi>=cfg.targetBER).'));
                row.supported_gain_eligible=strcmp(phase,'formal') && row.BER_state=="supported" && ...
                    row.all_payload_power_match;
                pooled=[pooled;carrierRows(cfg,phase,cond,cal,scheme,NaN,design,bits,errors, ...
                    cfg.payload_repeats*L,cfg.payload_repeats,mean(powers), ...
                    row.all_payload_power_match,NaN,NaN)]; %#ok<AGROW>
            end
            summaryRows{end+1}=row; %#ok<AGROW>
        end
    end
end
assert(numel(seenRunKeys)==sum(~cellfun(@isempty,runs)), ...
    'DMT:TradeoffUnexpectedPayload','A payload record is outside the planned matrix or duplicated.');
summary=rowsToTable(summaryRows,summaryTemplate(phase,table2struct(conditions(1,:)),calIDs(1),cfg.scheme_names{1},cfg.payload_repeats,L));
runStatus=rowsToTable(statusRows,runTemplate(phase,table2struct(conditions(1,:)),calIDs(1),cfg.scheme_names{1},1,L));
payloadMetrics=rowsToTable(metricRows,metricTemplate());
scenario=makeScenario(cfg,phase,conditions,summary,nCal,payloadMetrics);
requirements=makeRequirements(cfg,scenario);
budget=makeEnvelope(cfg,scenario);
comparisons=makeComparisons(cfg,summary);
tables=struct('seed',seed,'pooled',pooled,'summary',summary,'run_status',runStatus, ...
    'power_cal',rowsToTable(powerRows,powerTemplate()),'design_rounds',rowsToTable(roundRows,roundTemplate()), ...
    'costs',rowsToTable(costRows,costTemplate()),'scenario',scenario,'requirements',requirements, ...
    'feedback',rowsToTable(feedbackRows,feedbackTemplate()), ...
    'payload_metrics',payloadMetrics, ...
    'profiles',rowsToTable(profileRows,profileTemplate()),'budget_envelope',budget,'comparisons',comparisons, ...
    'phase',phase,'planned_groups',height(runStatus), ...
    'completed_groups',sum(runStatus.status=="completed"), ...
    'rejected_groups',sum(runStatus.status=="design_rejected"), ...
    'incomplete_groups',sum(runStatus.status=="incomplete"), ...
    'design_cases_planned',height(summary),'design_cases_processed',sum(summary.design_processed), ...
    'design_cases_accepted',sum(summary.design_accepted),'shared_calibrations_completed',sum(~cellfun(@isempty,shared)));
assert(height(runStatus)==height(conditions)*nCal*nSchemes*cfg.payload_repeats);
assert(tables.completed_groups+tables.rejected_groups+tables.incomplete_groups==tables.planned_groups);
assert(height(seed)==nK*tables.completed_groups);
assert(height(pooled)==nK*sum(summary.payload_state=="completed"));
end

function record=findRecord(records,cid,cal,scheme,slot)
record=[];
for j=1:numel(records)
    one=records{j};if isempty(one),continue;end
    if one.condition.condition_id~=cid || one.calibration_id~=cal,continue;end
    if ~isempty(scheme) && ~strcmp(one.scheme,scheme),continue;end
    if isfinite(slot) && one.payload_slot~=slot,continue;end
    assert(isempty(record),'DMT:TradeoffDuplicateRecord','Repeated planned record.');record=one;
end
end

function validatePayload(cfg,phase,cond,cal,scheme,slot,design,run,L)
assert(strcmp(run.phase,phase)&&strcmp(run.scheme,scheme)&&run.calibration_id==cal&&run.payload_slot==slot);
assert(isequaln(run.condition,cond)&&run.symbols==L);
assert(isequal(size(run.error_bits),[numel(cfg.k) 1])&&isequal(size(run.tested_bits),[numel(cfg.k) 1]));
e=double(run.error_bits);n=double(run.tested_bits);
assert(all(isfinite(e)&e>=0&e<=n&e==fix(e))&&all(n==L*log2(design.M(:))));
assert(run.metrics.sample_count==(cfg.NFFT+cfg.NCP)*L);
assert(strcmp(run.configuration_hash,dmt_v13_hash(design.final_tx)));
assert(strcmp(dmt_v13_hash(design.final_tx),dmt_v13_hash(design.final_rx))&&design.ack.accepted);
assert(abs(run.power_actual-run.metrics.tx_sum/run.metrics.sample_count)<1e-12);
assert(logical(run.power_match)==(abs(run.power_actual/cond.P_target-1)<=cfg.payload_power_tolerance));
end

function state=classify(lo,hi,target)
state="inconclusive";
if any(lo>target),state="failed";elseif all(hi<target),state="supported";end
end

function t=carrierTemplate()
t=table('Size',[0 23],'VariableTypes',{'string','double','double','double','double','string', ...
    'double','double','double','double','double','double','double','double','double','double', ...
    'double','double','double','logical','string','double','double'},'VariableNames', ...
    {'phase','condition_id','P_target','q','calibration_id','scheme','payload_slot','k','M','b', ...
    'actual_symbols','test_seed_count','tested_bits','error_bits','BER','CI_low','CI_high', ...
    'CI_upper_over_target','P_actual','power_match','configuration_hash','data_seed','noise_seed'});
end

function t=carrierRows(cfg,phase,cond,cal,scheme,slot,design,bits,errors,symbols,repeats,power,match,ds,ns)
bits=double(bits(:));errors=double(errors(:));[lo,hi]=dmt_wilson(errors,bits);n=numel(cfg.k);z=carrierTemplate();
t=table(repmat(string(phase),n,1),repmat(cond.condition_id,n,1),repmat(cond.P_target,n,1), ...
    repmat(cond.q,n,1),repmat(cal,n,1),repmat(string(scheme),n,1),repmat(slot,n,1),cfg.k(:), ...
    design.M(:),repmat(design.b,n,1),repmat(symbols,n,1),repmat(repeats,n,1),bits,errors, ...
    errors./bits,lo,hi,hi/cfg.targetBER,repmat(power,n,1),repmat(logical(match),n,1), ...
    repmat(string(dmt_v13_hash(design.final_tx)),n,1),repmat(ds,n,1),repmat(ns,n,1), ...
    'VariableNames',z.Properties.VariableNames);
end

function r=summaryTemplate(phase,c,cal,scheme,repeats,L)
r=struct('phase',string(phase),'condition_id',c.condition_id,'P_target',c.P_target,'q',c.q, ...
    'calibration_id',cal,'scheme',string(scheme),'initial_calibration_available',false, ...
    'design_processed',false,'design_accepted',false,'design_status',"not_evaluated", ...
    'payload_state',"incomplete",'BER_state',"incomplete",'power_state',"not_measured", ...
    'supported_gain_eligible',false,'planned_payloads',repeats,'test_seed_count',0, ...
    'cycle_payload_symbols',L,'actual_payload_symbols',0,'design_round_count',0, ...
    'b',NaN,'B_DMT',NaN,'R_nominal',NaN,'R_cycle',NaN,'shared_A0_symbols',0, ...
    'shared_B0_symbols',0,'design_A_symbols',0,'design_D_symbols',0,'setup_link_symbols',0, ...
    'TX_power_cal_symbols',0,'setup_optical_energy_norm',NaN,'partial_tested_bits',NaN, ...
    'partial_error_bits',NaN,'total_tested_bits',NaN,'total_error_bits',NaN,'overall_BER',NaN, ...
    'worst_subcarrier_BER',NaN,'max_CI_upper_over_target',NaN,'failed_k',"",'inconclusive_k',"", ...
    'P_actual_min',NaN,'P_actual_median',NaN,'P_actual_max',NaN,'all_payload_power_match',false, ...
    'configuration_hash',"");
end

function r=runTemplate(phase,c,cal,scheme,slot,L)
r=struct('phase',string(phase),'condition_id',c.condition_id,'P_target',c.P_target,'q',c.q, ...
    'calibration_id',cal,'scheme',string(scheme),'payload_slot',slot,'status',"incomplete", ...
    'reason',"design_not_evaluated",'design_status',"not_evaluated",'planned_symbols',L, ...
    'actual_symbols',0,'tested_bits',NaN,'error_bits',NaN,'P_actual',NaN,'power_match',false, ...
    'configuration_hash',"",'data_seed',NaN,'noise_seed',NaN);
end

function r=powerTemplate()
r=struct('phase',"",'condition_id',NaN,'P_target',NaN,'q',NaN,'calibration_id',NaN, ...
    'scheme',"",'round',NaN,'role',"",'b',NaN,'actual_mean',NaN,'relative_error',NaN, ...
    'iterations',NaN,'reachable',false,'monotone',false,'data_seed',NaN,'compute_seconds',NaN, ...
    'waveform_hash',"",'record_hash',"");
end

function r=powerRow(phase,c,cal,scheme,round,role,p)
r=powerTemplate();r.phase=string(phase);r.condition_id=c.condition_id;r.P_target=c.P_target;r.q=c.q;
r.calibration_id=cal;r.scheme=string(scheme);r.round=round;r.role=string(role);r.b=p.b;
r.actual_mean=p.actual_mean;r.relative_error=p.relative_error;r.iterations=p.iterations;
r.reachable=logical(p.reachable);r.monotone=logical(p.monotone);r.data_seed=p.seed;
r.compute_seconds=p.compute_seconds;r.waveform_hash=string(p.waveform_hash);r.record_hash=string(dmt_v13_hash(p));
end

function r=roundTemplate()
r=struct('phase',"",'condition_id',NaN,'P_target',NaN,'q',NaN,'calibration_id',NaN, ...
    'scheme',"",'round',NaN,'k',NaN,'M',NaN,'b',NaN,'A_symbols',NaN,'D_symbols',NaN, ...
    'tested_bits',NaN,'error_bits',NaN,'BER',NaN,'CI_low',NaN,'CI_high',NaN, ...
    'CI_upper_over_target',NaN,'supported',false,'round_status',"",'power_data_seed',NaN, ...
    'A_data_seed',NaN,'A_noise_seed',NaN,'D_data_seed',NaN,'D_noise_seed',NaN);
end

function r=costTemplate()
r=struct('phase',"",'condition_id',NaN,'P_target',NaN,'q',NaN,'calibration_id',NaN,'scheme',"", ...
    'design_status',"not_evaluated",'A0_symbols',0,'B0_symbols',0,'Ar_symbols',0,'Dr_symbols',0, ...
    'setup_link_symbols',0,'TX_power_cal_symbols',0,'cycle_payload_symbols',NaN, ...
    'T_control_seconds',NaN,'setup_link_seconds',NaN,'setup_optical_energy_norm',NaN, ...
    'initial_power_compute_seconds',NaN,'initial_link_compute_seconds',NaN,'loading_compute_seconds',NaN, ...
    'candidate_power_compute_seconds',NaN,'candidate_training_compute_seconds',NaN, ...
    'validation_compute_seconds',NaN,'design_compute_seconds',NaN, ...
    'quality_feedback_scalars',0,'D_support_feedback_entries',0,'loading_table_entries',0,'ACK_count',0, ...
    'serialized_control_bits',NaN);
end

function r=makeCost(cfg,phase,c,cal,scheme,shared,design,L)
r=costTemplate();r.phase=string(phase);r.condition_id=c.condition_id;r.P_target=c.P_target;r.q=c.q;
r.calibration_id=cal;r.scheme=string(scheme);r.cycle_payload_symbols=L;r.T_control_seconds=cfg.control_delay;
txSum=0;
if ~isempty(shared)
    r.A0_symbols=shared.A0.symbols;r.B0_symbols=shared.B0.symbols;
    r.TX_power_cal_symbols=cfg.power_cal_symbols;
    txSum=shared.A0.metrics.tx_sum+shared.B0.metrics.tx_sum;
    r.initial_power_compute_seconds=shared.power0.compute_seconds;
    r.initial_link_compute_seconds=shared.A0.compute_seconds+shared.B0.compute_seconds;
end
if ~isempty(design)
    r.design_status=string(design.status);
    for i=1:numel(design.rounds)
        one=design.rounds(i);r.Ar_symbols=r.Ar_symbols+one.Ar.symbols;r.Dr_symbols=r.Dr_symbols+one.Dr.symbols;
        r.TX_power_cal_symbols=r.TX_power_cal_symbols+cfg.power_cal_symbols;
        txSum=txSum+one.Ar.metrics.tx_sum+one.Dr.metrics.tx_sum;
    end
    r.loading_compute_seconds=design.costs.loading_seconds;
    r.candidate_power_compute_seconds=design.costs.power_seconds;
    r.candidate_training_compute_seconds=design.costs.training_seconds;
    r.validation_compute_seconds=design.costs.validation_seconds;
    r.design_compute_seconds=design.costs.design_seconds;
    r.quality_feedback_scalars=numel(cfg.k);
    r.D_support_feedback_entries=numel(cfg.k)*numel(design.rounds);
    r.loading_table_entries=numel(cfg.k)*(numel(design.rounds)+strcmp(design.status,'accepted'));
    r.ACK_count=numel(design.rounds)+strcmp(design.status,'accepted');
end
r.setup_link_symbols=r.A0_symbols+r.B0_symbols+r.Ar_symbols+r.Dr_symbols;
r.setup_link_seconds=r.setup_link_symbols*cfg.Ts;
if ~isempty(shared),r.setup_optical_energy_norm=txSum/cfg.Fs;end
end

function r=feedbackTemplate()
r=struct('phase',"",'condition_id',NaN,'P_target',NaN,'q',NaN,'calibration_id',NaN,'scheme',"", ...
    'quality_SNR_scalars',0,'D_support_entries',0,'candidate_M_entries',0,'accepted_M_entries',0, ...
    'candidate_ACK_count',0,'accepted_ACK_count',0,'serialized_bits',NaN, ...
    'assumption',"Ideal error-free control; no serialization width or signaling delay modeled.");
end

function r=makeFeedback(phase,c,cal,scheme,d,nK)
r=feedbackTemplate();r.phase=string(phase);r.condition_id=c.condition_id;r.P_target=c.P_target;r.q=c.q;
r.calibration_id=cal;r.scheme=string(scheme);r.quality_SNR_scalars=nK;
r.D_support_entries=nK*numel(d.rounds);r.candidate_M_entries=nK*numel(d.rounds);
r.accepted_M_entries=nK*strcmp(d.status,'accepted');r.candidate_ACK_count=numel(d.rounds);
r.accepted_ACK_count=strcmp(d.status,'accepted');
end

function r=metricTemplate()
r=struct('phase',"",'condition_id',NaN,'P_target',NaN,'q',NaN,'calibration_id',NaN,'scheme',"", ...
    'payload_slot',NaN,'symbols',NaN,'sample_count',NaN,'b',NaN,'P_actual',NaN, ...
    'P_actual_relative_dB',NaN,'power_relative_error',NaN,'power_match',false,'mean_p_squared',NaN, ...
    'p_peak',NaN,'p_min',NaN,'AC_drive_mean_square',NaN,'TX_lower_clip_count',NaN, ...
    'TX_upper_clip_count',NaN,'TX_clipping_rate',NaN,'clip_error_mean_square',NaN, ...
    'ADC_low_count',NaN,'ADC_high_count',NaN,'ADC_out_of_range_rate',NaN, ...
    'useful_electrical_energy_sum',NaN,'CP_electrical_energy_sum',NaN, ...
    'payload_optical_energy_norm',NaN,'setup_optical_energy_norm',NaN,'cycle_optical_energy_per_payload_bit_norm',NaN, ...
    'payload_compute_seconds',NaN);
end

function r=payloadMetric(cfg,phase,c,cal,scheme,slot,run,design,cost)
r=metricTemplate();r.phase=string(phase);r.condition_id=c.condition_id;r.P_target=c.P_target;r.q=c.q;
r.calibration_id=cal;r.scheme=string(scheme);r.payload_slot=slot;r.symbols=run.symbols;
m=run.metrics;n=m.sample_count;r.sample_count=n;r.b=design.b;r.P_actual=run.power_actual;
r.P_actual_relative_dB=10*log10(r.P_actual);r.power_relative_error=run.power_relative_error;
r.power_match=logical(run.power_match);r.mean_p_squared=m.tx_sum_sq/n;r.p_peak=m.tx_max;r.p_min=m.tx_min;
r.AC_drive_mean_square=m.drive_ac_sq_sum/n;r.TX_lower_clip_count=m.lower_clip_count;
r.TX_upper_clip_count=m.upper_clip_count;r.TX_clipping_rate=(m.lower_clip_count+m.upper_clip_count)/n;
r.clip_error_mean_square=m.clip_error_sq_sum/n;r.ADC_low_count=m.adc_low_count;r.ADC_high_count=m.adc_high_count;
r.ADC_out_of_range_rate=(m.adc_low_count+m.adc_high_count)/n;
r.useful_electrical_energy_sum=m.useful_energy_sum;r.CP_electrical_energy_sum=m.cp_energy_sum;
r.payload_optical_energy_norm=m.tx_sum/cfg.Fs;r.setup_optical_energy_norm=cost.setup_optical_energy_norm;
r.cycle_optical_energy_per_payload_bit_norm=(r.payload_optical_energy_norm+r.setup_optical_energy_norm)/sum(double(run.tested_bits));
r.payload_compute_seconds=run.compute_seconds;
end

function r=profileTemplate()
r=struct('phase',"",'condition_id',NaN,'P_target',NaN,'q',NaN,'calibration_id',NaN, ...
    'scheme',"",'k',NaN,'M',NaN,'bits_k',NaN,'b',NaN,'configuration_hash',"");
end

function t=makeScenario(cfg,phase,conditions,summary,nCal,metrics)
rows={};
for i=1:height(conditions)
    c=table2struct(conditions(i,:));
    for s=1:numel(cfg.scheme_names)
        scheme=string(cfg.scheme_names{s});x=summary(summary.condition_id==c.condition_id & summary.scheme==scheme,:);
        actual=metrics.P_actual(metrics.condition_id==c.condition_id & metrics.scheme==scheme);
        nominal=finiteStats(x.R_nominal);cycle=finiteStats(x.R_cycle);power=finiteStats(actual);
        mins=finiteStats(x.P_actual_min);maxs=finiteStats(x.P_actual_max);
        eligible=x.BER_state=="supported" & x.payload_state=="completed" & x.all_payload_power_match;
        resolved=x.payload_state=="completed" | x.payload_state=="design_rejected";
        r=struct('phase',string(phase),'condition_id',c.condition_id,'P_target',c.P_target,'q',c.q, ...
            'scheme',scheme,'planned_calibrations',nCal,'design_processed',sum(x.design_processed), ...
            'accepted_designs',sum(x.design_accepted),'design_rejected',sum(x.payload_state=="design_rejected"), ...
            'no_initial_candidate',sum(x.design_status=="no_initial_candidate"), ...
            'no_accepted_profile_min_order',sum(x.design_status=="no_accepted_profile_min_order"), ...
            'round_budget_exhausted',sum(x.design_status=="round_budget_exhausted"), ...
            'BER_supported_rounds',sum(x.BER_state=="supported"),'BER_failed_rounds',sum(x.BER_state=="failed"), ...
            'BER_inconclusive_rounds',sum(x.BER_state=="inconclusive"),'incomplete_rounds',sum(x.payload_state=="incomplete"), ...
            'power_mismatch_rounds',sum(x.power_state=="power_mismatch"),'supported_rounds',sum(eligible), ...
            'scan_point_resolved',all(resolved),'all_rounds_supported',strcmp(phase,'formal')&&all(eligible), ...
            'P_actual_min',mins(1),'P_actual_median',power(2),'P_actual_max',maxs(3), ...
            'R_nominal_min',nominal(1),'R_nominal_median',nominal(2),'R_nominal_max',nominal(3), ...
            'R_cycle_min',cycle(1),'R_cycle_median',cycle(2),'R_cycle_max',cycle(3), ...
            'rate_range_scope',"All accepted designs, including BER-failed/incomplete; min-max is not a CI.");
        rows{end+1}=r; %#ok<AGROW>
    end
end
t=struct2table([rows{:}]);
end

function t=makeRequirements(cfg,scenario)
rows={};
for q=cfg.adc_bits
    for si=1:numel(cfg.scheme_names)
        scheme=string(cfg.scheme_names{si});x=scenario(scenario.q==q & scenario.scheme==scheme,:);
        scanComplete=all(x.scan_point_resolved);
        for metric=["R_cycle","R_nominal"]
            for req=cfg.R_req
                r=struct('phase',scenario.phase(1),'q',q,'scheme',scheme,'metric',metric,'R_required',req,'scan_complete',scanComplete, ...
                    'status',"scan_incomplete_not_assessable",'P_target_selected',NaN, ...
                    'P_actual_min',NaN,'P_actual_median',NaN,'P_actual_max',NaN,'all_calibrations_min_rate',NaN);
                if scenario.phase(1)=="preflight"
                    r.status="preflight_diagnostic_only";
                elseif scanComplete
                    r.status="not_found_in_completed_scan";
                    values=x.([char(metric) '_min']);
                    ok=x.all_rounds_supported & values>=req;
                    candidates=x(ok,:);
                    if ~isempty(candidates)
                        candidates=sortrows(candidates,'P_target');best=candidates(1,:);r.status="found";
                        r.P_target_selected=best.P_target;r.P_actual_min=best.P_actual_min;
                        r.P_actual_median=best.P_actual_median;r.P_actual_max=best.P_actual_max;
                        r.all_calibrations_min_rate=best.([char(metric) '_min']);
                    end
                end
                rows{end+1}=r; %#ok<AGROW>
            end
        end
    end
end
t=struct2table([rows{:}]);
end

function t=makeEnvelope(cfg,scenario)
rows={};
for q=cfg.adc_bits
    for si=1:numel(cfg.scheme_names)
        scheme=string(cfg.scheme_names{si});x=scenario(scenario.q==q & scenario.scheme==scheme,:);
        for budget=cfg.P_targets
            r=struct('phase',scenario.phase(1),'q',q,'scheme',scheme,'power_budget',budget,'status',"no_supported_measured_point", ...
                'P_target_selected',NaN,'P_actual_max',NaN,'R_cycle_min',NaN,'R_cycle_median',NaN, ...
                'R_nominal_min',NaN,'scope',"Empirical sampled points; not theoretical capacity/Pareto boundary.");
            ok=x.all_rounds_supported & x.P_actual_max<=budget;
            chosen=x(ok,:);
            if scenario.phase(1)=="preflight"
                r.status="preflight_diagnostic_only";
            elseif ~isempty(chosen)
                [~,j]=max(chosen.R_cycle_min);best=chosen(j,:);r.status="found";
                r.P_target_selected=best.P_target;r.P_actual_max=best.P_actual_max;
                r.R_cycle_min=best.R_cycle_min;r.R_cycle_median=best.R_cycle_median;r.R_nominal_min=best.R_nominal_min;
            elseif ~all(x.scan_point_resolved)
                r.status="scan_incomplete_no_supported_measured_point";
            end
            rows{end+1}=r; %#ok<AGROW>
        end
    end
end
t=struct2table([rows{:}]);
end

function t=makeComparisons(cfg,summary)
assert(numel(cfg.scheme_names)==2);rows={};
keys=unique(summary(:,{'phase','condition_id','P_target','q','calibration_id'}),'rows');
for i=1:height(keys)
    x=summary(summary.condition_id==keys.condition_id(i)&summary.calibration_id==keys.calibration_id(i),:);
    u=x(x.scheme==string(cfg.scheme_names{1}),:);l=x(x.scheme==string(cfg.scheme_names{2}),:);
    assert(height(u)==1&&height(l)==1);
    r=table2struct(keys(i,:));r.Uniform_BER_state=u.BER_state;r.Loaded_BER_state=l.BER_state;
    r.Uniform_power_state=u.power_state;r.Loaded_power_state=l.power_state;
    r.reliability_supported=u.supported_gain_eligible&&l.supported_gain_eligible;
    r.nominal_allocated_ratio=NaN;r.cycle_allocated_ratio=NaN;r.nominal_delta_rate=NaN;
    r.cycle_delta_rate=NaN;r.nominal_gain_minus_cycle_gain=NaN;
    if isfinite(u.R_nominal)&&isfinite(l.R_nominal)
        r.nominal_allocated_ratio=l.R_nominal/u.R_nominal;r.cycle_allocated_ratio=l.R_cycle/u.R_cycle;
        r.nominal_delta_rate=l.R_nominal-u.R_nominal;r.cycle_delta_rate=l.R_cycle-u.R_cycle;
        r.nominal_gain_minus_cycle_gain=r.nominal_delta_rate-r.cycle_delta_rate;
    end
    rows{end+1}=r; %#ok<AGROW>
end
t=struct2table([rows{:}]);
end

function result=finiteStats(x)
x=x(isfinite(x));result=[NaN NaN NaN];
if ~isempty(x),result=[min(x) median(x) max(x)];end
end

function t=rowsToTable(rows,template)
if isempty(rows),t=struct2table(template);t=t([],:);else,t=struct2table([rows{:}]);end
end
