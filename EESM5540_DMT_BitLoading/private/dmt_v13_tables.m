function tables = dmt_v13_tables(cfg,records,runs,phase)
%DMT_V13_TABLES Actual counts stay inside scenario/calibration/profile strata.
% Unconfigured/infeasible/incomplete records never acquire fabricated BERs.
phase = validatestring(phase,{'formal','preflight'});
nCal = cfg.calibrationCount;
groupSymbols = cfg.payloadSymbols;
if strcmp(phase,'preflight'), nCal=1; groupSymbols=cfg.preflightSymbols; end
assert(nCal>=1 && groupSymbols>0 && isequal(cfg.k(:),(1:24).'));
names = ["Uniform" "Loaded" "Fixed16"];
scenarios = cfg.scenarios;
assert(numel(scenarios)==4 && isequal([scenarios.scenario_idx],0:3));
if ~isempty(records)
    keys=string([records.scenario_idx])+":"+string([records.calibration_id]);
    assert(numel(unique(keys))==numel(records),'DMT:DuplicateCalibration','Duplicate calibration record.');
end
if ~isempty(runs)
    keys=string([runs.scenario_idx])+":"+string([runs.calibration_id])+":"+ ...
        string({runs.scheme})+":"+string([runs.seed]);
    assert(numel(unique(keys))==numel(runs),'DMT:DuplicateRun','Duplicate payload group.');
    assert(all(strcmp({runs.phase},phase)) && all(ismember([runs.seed],cfg.seeds)));
    assert(all(ismember([runs.scenario_idx],0:3)) && all(ismember([runs.calibration_id],1:nCal)));
end
seedRows=carrierTemplate(); pooledRows=carrierTemplate();
statusRows=cell(4*nCal*9,1); summaryRows=cell(4*nCal*3,1);
powerRows={}; paprRows={}; probeRows={};
statusIndex=0; summaryIndex=0;
selection=zeros(4,nCal,3,24); configured=false(4,nCal,3); infeasible=configured;
for q=1:4
    scenario=scenarios(q);
    for c=1:nCal
        record=[];
        if ~isempty(records)
            chosen=find([records.scenario_idx]==scenario.scenario_idx & [records.calibration_id]==c);
            if ~isempty(chosen), record=records(chosen); end
        end
        available=~isempty(record) && isscalar(record.configured) && logical(record.configured);
        if available
            assert(numel(record.exchange.tx_profiles)==3 && numel(record.exchange.rx_profiles)==3 && ...
                numel(record.exchange.acks)==3);
        end
        for s=1:3
            summaryIndex=summaryIndex+1;
            row=summaryTemplate(scenario,c,names(s),phase);
            if isfield(cfg,'requested_scenarios')
                row.requested_scope=ismember(scenario.scenario_idx,cfg.requested_scenarios);
            end
            config=[]; rxConfig=[]; ack=[];
            if available
                configured(q,c,s)=true;
                config=record.exchange.tx_profiles(s);
                rxConfig=record.exchange.rx_profiles(s);
                ack=record.exchange.acks(s);
                assert(strcmp(config.scheme,names(s)) && strcmp(config.scenario_id,scenario.scenario_id) && ...
                    config.calibration_id==c);
                row.configured=true;
                row.profile_id=string(config.profile_id);
                row.configuration_hash=string(dmt_v13_hash(config));
                row.calibration_hash=string(record.receiver.calibration_hash);
                row.feasible=logical(config.feasible);
                infeasible(q,c,s)=~row.feasible;
                if row.feasible
                    assert(isequal(size(config.M_k),[24 1]) && all(ismember(config.M_k,cfg.Mset)));
                    assert(isequal(config.bits_k,log2(config.M_k)) && logical(ack.accepted));
                    assert(strcmp(dmt_v13_hash(config),dmt_v13_hash(rxConfig)) && ...
                        strcmp(ack.configuration_hash,dmt_v13_hash(config)), ...
                        'DMT:ConfigurationMismatch','Tx/Rx/ACK configurations disagree.');
                    selection(q,c,s,:)=reshape(config.M_k,1,1,1,[]);
                    row.B=sum(config.bits_k);
                    row.R_payload=row.B/cfg.Ts;
                    if iscell(record.probes) && numel(record.probes)>=s && ~isempty(record.probes{s})
                        probeRows{end+1,1}=makeProbeRows(cfg,scenario,c,config,record.probes{s}); %#ok<AGROW>
                    end
                else
                    row.status="infeasible"; row.reason=string(config.reason);
                    assert(~logical(ack.accepted),'DMT:InvalidACK','An infeasible table cannot be ACKed.');
                end
            end
            selected=struct([]);
            if ~isempty(runs)
                selected=runs([runs.scenario_idx]==scenario.scenario_idx & ...
                    [runs.calibration_id]==c & strcmp({runs.scheme},char(names(s))));
            end
            assert(isempty(selected) || (available && row.feasible), ...
                'DMT:UnexpectedPayload','Payload exists without an accepted feasible configuration.');
            if ~isempty(selected)
                assert(iscell(record.probes) && numel(record.probes)>=s && ~isempty(record.probes{s}), ...
                    'DMT:MissingValidationProbe','A completed payload group requires the independent diagnostic C record.');
            end
            bits=zeros(24,1); errors=bits;
            for r=1:numel(selected)
                one=selected(r);
                validateRun(cfg,scenario,c,config,rxConfig,ack,one,phase,groupSymbols);
                seedRows=[seedRows;makeCarrierRows(cfg,scenario,c,record.receiver,config, ...
                    one.tested_bits,one.error_bits,one.seed,1,one.symbols,phase)]; %#ok<AGROW>
                bits=bits+one.tested_bits; errors=errors+one.error_bits;
                powerRows{end+1,1}=makePowerRow(cfg,scenario,one); %#ok<AGROW>
                paprRows{end+1,1}=makePAPRRows(one); %#ok<AGROW>
            end
            row.test_seed_count=numel(selected);
            if ~isempty(selected)
                row.test_symbols=sum([selected.symbols]);
                row.partial_tested_bits=sum(bits); row.partial_error_bits=sum(errors);
            end
            row.test_duration_s=row.test_symbols*cfg.Ts;
            if row.feasible && numel(selected)==3 && isequal(sort([selected.seed]),cfg.seeds)
                pooled=makeCarrierRows(cfg,scenario,c,record.receiver,config,bits,errors,NaN,3, ...
                    3*groupSymbols,phase);
                pooledRows=[pooledRows;pooled]; %#ok<AGROW>
                row.total_tested_bits=sum(bits); row.total_error_bits=sum(errors);
                row.total_BER=sum(errors)/sum(bits); row.worst_subcarrier_BER=max(pooled.BER);
                row.max_CI_upper_over_target=max(pooled.CI_upper_over_target);
                row.failed_k=string(mat2str(pooled.k(pooled.CI_low>cfg.targetBER).'));
                crossing=pooled.CI_low<=cfg.targetBER & pooled.CI_high>=cfg.targetBER;
                row.inconclusive_k=string(mat2str(pooled.k(crossing).'));
                row.observed_above_target_k=string(mat2str(pooled.k(pooled.BER>cfg.targetBER).'));
                row.status="inconclusive";
                if any(pooled.CI_low>cfg.targetBER)
                    row.status="failed";
                elseif all(pooled.CI_high<cfg.targetBER)
                    row.status="supported";
                end
                row.reason="three_fixed_payload_seeds_completed";
                row.mean_useful_energy=sum([selected.useful_energy_sum])/row.test_symbols;
                row.mean_CP_energy=sum([selected.cp_energy_sum])/row.test_symbols;
                row.mean_including_CP_symbol_energy=sum([selected.total_energy_sum])/row.test_symbols;
                row.mean_including_CP_power=sum([selected.total_energy_sum])/sum([selected.sample_count]);
                if scenario.imdd
                    n=sum([selected.sample_count]);
                    row.mean_optical_power=sum([selected.optical_sum])/n;
                    row.mean_optical_square=sum([selected.optical_sum_sq])/n;
                    row.optical_AC_variance=max(0,row.mean_optical_square-row.mean_optical_power^2);
                    row.optical_peak=max([selected.optical_peak]);
                    row.clipping_rate=sum([selected.lower_clip_count]+[selected.upper_clip_count])/n;
                    row.clip_error_power=sum([selected.clip_error_sq_sum])/n;
                    row.mean_optical_relative_difference=row.mean_optical_power/scenario.P0-1;
                end
            elseif row.feasible
                row.reason="payload_groups_incomplete";
            end
            summaryRows{summaryIndex}=struct2table(row);
            for j=1:3
                statusIndex=statusIndex+1;
                group=runStatusTemplate(scenario,c,names(s),cfg.seeds(j),phase,groupSymbols);
                group.requested_scope=row.requested_scope;
                group.profile_id=row.profile_id; group.configuration_hash=row.configuration_hash;
                if ~available
                    group.reason="calibration_not_configured";
                elseif ~row.feasible
                    group.status="infeasible"; group.reason=row.reason; group.actual_symbols=0;
                else
                    runIndex=[];
                    if ~isempty(selected), runIndex=find([selected.seed]==cfg.seeds(j)); end
                    if ~isempty(runIndex)
                        assert(numel(runIndex)==1);
                        one=selected(runIndex);
                        group.status="completed"; group.reason="fixed_group_complete";
                        group.actual_symbols=one.symbols;
                        group.data_seed=one.data_seed; group.noise_seed=one.noise_seed;
                        group.tested_bits=sum(one.tested_bits); group.error_bits=sum(one.error_bits);
                    else
                        group.reason="payload_group_not_complete";
                    end
                end
                statusRows{statusIndex}=struct2table(group);
            end
        end
    end
end
summary=vertcat(summaryRows{:}); runStatus=vertcat(statusRows{:});
for q=1:4
    for c=1:nCal
        u=find(summary.scenario_idx==scenarios(q).scenario_idx & summary.calibration_id==c & summary.scheme=="Uniform");
        l=find(summary.scenario_idx==scenarios(q).scenario_idx & summary.calibration_id==c & summary.scheme=="Loaded");
        allRows=summary.scenario_idx==scenarios(q).scenario_idx & summary.calibration_id==c;
        if summary.feasible(u) && summary.feasible(l)
            ratio=summary.B(l)/summary.B(u);
            summary.allocated_Loaded_Uniform_ratio(allRows)=ratio;
            if summary.status(u)=="supported" && summary.status(l)=="supported"
                summary.reliability_supported_ratio(allRows)=ratio;
                summary.supported_loading_gain(allRows)=ratio>1;
            end
        end
    end
end
frequency=makeFrequency(cfg,scenarios,selection,configured,infeasible,nCal);
robustness=makeRobustness(scenarios,summary,nCal);
power=concatOrEmpty(powerRows,powerTemplate());
papr=concatOrEmpty(paprRows,paprTemplate());
probe=concatOrEmpty(probeRows,probeTemplate());
tables=struct('seed',seedRows,'pooled',pooledRows,'summary',summary,'run_status',runStatus, ...
    'robustness',robustness,'profile_frequency',frequency,'power',power,'papr',papr,'probe_C',probe, ...
    'phase',phase,'completed_groups',numel(runs),'planned_groups',4*nCal*9, ...
    'infeasible_groups',sum(runStatus.status=="infeasible"), ...
    'incomplete_groups',sum(runStatus.status=="incomplete"), ...
    'requested_planned_groups',sum(runStatus.requested_scope), ...
    'requested_completed_groups',sum(runStatus.requested_scope & runStatus.status=="completed"), ...
    'requested_infeasible_groups',sum(runStatus.requested_scope & runStatus.status=="infeasible"), ...
    'requested_incomplete_groups',sum(runStatus.requested_scope & runStatus.status=="incomplete"), ...
    'mean_power_alert_groups',sum(power.investigate_mean_power));
assert(height(seedRows)==24*numel(runs));
assert(height(pooledRows)==24*sum(summary.test_seed_count==3));
assert(height(summary)==4*nCal*3 && height(runStatus)==4*nCal*9 && height(robustness)==12);
assert(tables.completed_groups+tables.infeasible_groups+tables.incomplete_groups==tables.planned_groups);
if strcmp(phase,'formal') && numel(runs)==360
    assert(height(seedRows)==8640 && height(pooledRows)==2880 && height(summary)==120);
end
end

function t=carrierTemplate()
names={'scenario_idx','scenario_id','calibration_id','scheme','payload_seed','k','frequency_Hz', ...
    'quality_B_dB','M','bits_k','tested_bits','error_bits','BER','CI_low','CI_high', ...
    'CI_upper_over_target','BER_design','BER_nominal','test_seed_count','test_symbols', ...
    'profile_id','configuration_hash','calibration_hash','phase'};
types=[{'double','string','double','string'} repmat({'double'},1,16) repmat({'string'},1,4)];
t=table('Size',[0 numel(names)],'VariableTypes',types,'VariableNames',names);
end

function t=makeCarrierRows(cfg,scenario,c,receiver,p,bits,errors,label,seeds,symbols,phase)
[lo,hi]=dmt_wilson(errors,bits); template=carrierTemplate();
t=table(repmat(scenario.scenario_idx,24,1),repmat(string(scenario.scenario_id),24,1), ...
    repmat(c,24,1),repmat(string(p.scheme),24,1),repmat(label,24,1),cfg.k(:), ...
    cfg.k(:)*cfg.Fs/cfg.NFFT,receiver.gamma_B_dB(:),p.M_k,p.bits_k,bits,errors,errors./bits, ...
    lo,hi,hi/cfg.targetBER,dmt_qam_ber(p.M_k,receiver.gamma_B/10^(cfg.margin_dB/10)), ...
    dmt_qam_ber(p.M_k,receiver.gamma_B),repmat(seeds,24,1),repmat(symbols,24,1), ...
    repmat(string(p.profile_id),24,1),repmat(string(dmt_v13_hash(p)),24,1), ...
    repmat(string(receiver.calibration_hash),24,1),repmat(string(phase),24,1), ...
    'VariableNames',template.Properties.VariableNames);
end

function r=summaryTemplate(scenario,c,name,phase)
r=struct('scenario_idx',scenario.scenario_idx,'scenario_id',string(scenario.scenario_id), ...
    'calibration_id',c,'scheme',name,'phase',string(phase),'requested_scope',true,'configured',false,'feasible',false, ...
    'status',"incomplete",'reason',"calibration_not_configured",'profile_id',"", ...
    'configuration_hash',"",'calibration_hash',"",'B',NaN,'R_payload',NaN, ...
    'test_seed_count',0,'test_symbols',0,'test_duration_s',0, ...
    'partial_tested_bits',0,'partial_error_bits',0,'total_tested_bits',NaN,'total_error_bits',NaN, ...
    'total_BER',NaN,'worst_subcarrier_BER',NaN,'max_CI_upper_over_target',NaN, ...
    'failed_k',"",'inconclusive_k',"",'observed_above_target_k',"", ...
    'mean_useful_energy',NaN,'mean_CP_energy',NaN,'mean_including_CP_symbol_energy',NaN, ...
    'mean_including_CP_power',NaN,'mean_optical_power',NaN,'mean_optical_square',NaN, ...
    'optical_AC_variance',NaN,'optical_peak',NaN,'clipping_rate',NaN,'clip_error_power',NaN, ...
    'mean_optical_relative_difference',NaN,'allocated_Loaded_Uniform_ratio',NaN, ...
    'reliability_supported_ratio',NaN,'supported_loading_gain',false);
end

function r=runStatusTemplate(scenario,c,name,label,phase,symbols)
r=struct('scenario_idx',scenario.scenario_idx,'scenario_id',string(scenario.scenario_id), ...
    'calibration_id',c,'scheme',name,'payload_seed',label,'phase',string(phase), ...
    'status',"incomplete",'reason',"",'requested_scope',true,'actual_symbols',NaN,'planned_symbols',symbols, ...
    'tested_bits',NaN,'error_bits',NaN,'data_seed',NaN,'noise_seed',NaN, ...
    'profile_id',"",'configuration_hash',"");
end

function validateRun(cfg,scenario,c,tx,rx,ack,run,phase,symbols)
assert(run.symbols==symbols && strcmp(run.phase,phase) && run.calibration_id==c && ...
    run.scenario_idx==scenario.scenario_idx && strcmp(run.scenario_id,scenario.scenario_id));
assert(strcmp(run.scheme,tx.scheme) && strcmp(run.profile_id,tx.profile_id));
id=dmt_v13_hash(tx);
assert(ack.accepted && strcmp(id,dmt_v13_hash(rx)) && strcmp(id,ack.configuration_hash) && ...
    strcmp(id,run.configuration_hash),'DMT:MissingACK','Payload requires matching accepted local profiles.');
assert(isequal(size(run.tested_bits),[24 1]) && isequal(size(run.error_bits),[24 1]));
assert(all(run.tested_bits==symbols*tx.bits_k) && all(isfinite(run.error_bits) & ...
    run.error_bits>=0 & run.error_bits<=run.tested_bits & run.error_bits==fix(run.error_bits)));
s=find(strcmp({'Uniform','Loaded','Fixed16'},tx.scheme)); j=find(cfg.seeds==run.seed);
base=2000000+10000000*scenario.scenario_idx+100000*c;
if strcmp(phase,'preflight'), base=base+100000000; end
assert(isscalar(s) && isscalar(j) && run.data_seed==base+1000*s+10*j+1 && ...
    run.noise_seed==base+1000*s+10*j+2,'DMT:PayloadStream','Actual payload stream differs from fixed plan.');
assert(run.sample_count==(cfg.NFFT+cfg.NCP)*symbols && run.papr_symbols==symbols);
energy=[run.useful_energy_sum run.cp_energy_sum run.total_energy_sum];
assert(all(isfinite(energy) & energy>=0));
assert(abs(energy(3)-sum(energy(1:2)))<=1e-10*max(1,energy(3)));
assert(isequal(run.papr_thresholds_dB(:),cfg.papr_thresholds_dB(:)) && ...
    all(run.papr_exceed_counts>=0 & run.papr_exceed_counts<=symbols & ...
    run.papr_exceed_counts==fix(run.papr_exceed_counts)) && ...
    all(diff(run.papr_exceed_counts)<=0));
if scenario.imdd
    assert(run.optical_applicable && isfinite(run.optical_sum) && isfinite(run.optical_sum_sq));
    assert(run.optical_min>=-1e-12 && run.optical_peak<=scenario.Pmax+1e-12);
    counts=[run.lower_clip_count run.upper_clip_count];
    assert(all(isfinite(counts) & counts>=0 & counts==fix(counts)) && sum(counts)<=run.sample_count);
    assert(isfinite(run.clip_error_sq_sum) && run.clip_error_sq_sum>=0);
end
end

function t=powerTemplate()
names={'scenario_idx','scenario_id','calibration_id','scheme','payload_seed','symbols','sample_count', ...
    'optical_applicable','mean_useful_energy','mean_CP_energy','mean_including_CP_symbol_energy', ...
    'mean_electrical_power','mean_optical_power','optical_peak','optical_min','optical_second_moment', ...
    'optical_AC_variance','lower_clip_count','upper_clip_count','clipping_rate','clip_error_power', ...
    'mean_optical_relative_difference','investigate_mean_power','phase'};
types=[{'double','string','double','string'} repmat({'double'},1,3) {'logical'} ...
    repmat({'double'},1,14) {'logical','string'}];
t=table('Size',[0 numel(names)],'VariableTypes',types,'VariableNames',names);
end

function t=makePowerRow(cfg,scenario,run)
template=powerTemplate(); n=run.sample_count;
meanP=NaN; second=NaN; variance=NaN; rate=NaN; clipError=NaN; difference=NaN;
investigate=false;
if scenario.imdd
    meanP=run.optical_sum/n; second=run.optical_sum_sq/n;
    variance=max(0,second-meanP^2);
    rate=(run.lower_clip_count+run.upper_clip_count)/n;
    clipError=run.clip_error_sq_sum/n; difference=meanP/scenario.P0-1;
    investigate=strcmp(run.phase,'formal') && abs(difference)>0.01;
end
t=table(run.scenario_idx,string(run.scenario_id),run.calibration_id,string(run.scheme),run.seed, ...
    run.symbols,n,logical(scenario.imdd),run.useful_energy_sum/run.symbols, ...
    run.cp_energy_sum/run.symbols,run.total_energy_sum/run.symbols,run.total_energy_sum/n, ...
    meanP,run.optical_peak,run.optical_min,second,variance,run.lower_clip_count,run.upper_clip_count, ...
    rate,clipError,difference,investigate,string(run.phase),'VariableNames',template.Properties.VariableNames);
assert(abs(run.signal_duration_s-run.symbols*cfg.Ts)<1e-12);
end

function t=paprTemplate()
names={'scenario_idx','scenario_id','calibration_id','scheme','payload_seed', ...
    'threshold_dB','exceed_count','tested_symbols','observed_exceedance','phase'};
types=[{'double','string','double','string'} repmat({'double'},1,5) {'string'}];
t=table('Size',[0 numel(names)],'VariableTypes',types,'VariableNames',names);
end

function t=makePAPRRows(run)
threshold=run.papr_thresholds_dB(:); n=numel(threshold); template=paprTemplate();
t=table(repmat(run.scenario_idx,n,1),repmat(string(run.scenario_id),n,1), ...
    repmat(run.calibration_id,n,1),repmat(string(run.scheme),n,1),repmat(run.seed,n,1), ...
    threshold,run.papr_exceed_counts(:),repmat(run.papr_symbols,n,1), ...
    run.papr_exceed_counts(:)/run.papr_symbols,repmat(string(run.phase),n,1), ...
    'VariableNames',template.Properties.VariableNames);
end

function t=probeTemplate()
names={'scenario_idx','scenario_id','calibration_id','scheme','k','gamma_B_linear','gamma_C_linear', ...
    'gamma_B_dB','gamma_C_dB','delta_dB','EVM_rms','BER_nominal_B','BER_nominal_C', ...
    'BER_design_B','BER_design_C','symbols','data_seed','noise_seed','configuration_hash','calibration_hash'};
types=[{'double','string','double','string'} repmat({'double'},1,14) {'string','string'}];
t=table('Size',[0 numel(names)],'VariableTypes',types,'VariableNames',names);
end

function t=makeProbeRows(cfg,scenario,c,config,p)
assert(p.symbols==cfg.validationSymbols && strcmp(p.configuration_hash,dmt_v13_hash(config)));
assert(isequal(size(p.gamma_B),[24 1]) && isequal(size(p.gamma_C),[24 1]) && ...
    all(isfinite(p.gamma_C) & p.gamma_C>0));
template=probeTemplate();
t=table(repmat(scenario.scenario_idx,24,1),repmat(string(scenario.scenario_id),24,1), ...
    repmat(c,24,1),repmat(string(config.scheme),24,1),cfg.k(:),p.gamma_B,p.gamma_C, ...
    p.gamma_B_dB,p.gamma_C_dB,p.delta_dB,p.EVM_rms,p.BER_nominal_B,p.BER_nominal_C, ...
    p.BER_design_B,p.BER_design_C,repmat(p.symbols,24,1),repmat(p.data_seed,24,1), ...
    repmat(p.noise_seed,24,1),repmat(string(p.configuration_hash),24,1), ...
    repmat(string(p.calibration_hash),24,1),'VariableNames',template.Properties.VariableNames);
end

function t=makeFrequency(cfg,scenarios,selection,configured,infeasible,nCal)
rows=cell(4*3*24*3,1); index=0;
names=["Uniform" "Loaded" "Fixed16"];
for q=1:4
    for s=1:3
        unknown=sum(~configured(q,:,s)); bad=sum(infeasible(q,:,s));
        for k=1:24
            chosen=reshape(selection(q,:,s,k),[],1);
            counts=arrayfun(@(m)sum(chosen==m),cfg.Mset);
            assert(sum(counts)+bad+unknown==nCal);
            for j=1:3
                index=index+1;
                rows{index}=table(scenarios(q).scenario_idx,string(scenarios(q).scenario_id), ...
                    names(s),cfg.k(k),cfg.Mset(j),counts(j),bad,unknown,nCal, ...
                    'VariableNames',{'scenario_idx','scenario_id','scheme','k','M','selection_count', ...
                    'infeasible_count','not_configured_count','planned_calibrations'});
            end
        end
    end
end
t=vertcat(rows{:});
end

function t=makeRobustness(scenarios,summary,nCal)
rows=cell(12,1); index=0; names=["Uniform" "Loaded" "Fixed16"];
for q=1:4
    for s=1:3
        index=index+1;
        x=summary(summary.scenario_idx==scenarios(q).scenario_idx & summary.scheme==names(s),:);
        states=[sum(x.status=="supported") sum(x.status=="failed") sum(x.status=="inconclusive") ...
            sum(x.status=="infeasible") sum(x.status=="incomplete")];
        assert(sum(states)==nCal);
        b=finiteStats(x.B); rate=finiteStats(x.R_payload);
        ratio=finiteStats(x.allocated_Loaded_Uniform_ratio);
        supportedRatio=finiteStats(x.reliability_supported_ratio);
        rows{index}=table(scenarios(q).scenario_idx,string(scenarios(q).scenario_id),names(s),nCal, ...
            states(1),states(2),states(3),states(4),states(5),sum(x.feasible),sum(x.test_seed_count), ...
            sum(x.test_symbols),b(1),b(2),b(3),rate(1),rate(2),rate(3),ratio(1),ratio(2),ratio(3), ...
            supportedRatio(1),supportedRatio(2),supportedRatio(3),sum(x.supported_loading_gain), ...
            'VariableNames',{'scenario_idx','scenario_id','scheme','planned_calibrations', ...
            'supported','failed','inconclusive','infeasible','incomplete','configured_feasible_rounds', ...
            'completed_groups','payload_symbols','B_min','B_median','B_max','R_payload_min','R_payload_median', ...
            'R_payload_max','allocated_ratio_min','allocated_ratio_median','allocated_ratio_max', ...
            'supported_ratio_min','supported_ratio_median','supported_ratio_max','supported_gain_rounds'});
    end
end
t=vertcat(rows{:});
end

function value=finiteStats(x)
x=x(isfinite(x)); value=[NaN NaN NaN];
if ~isempty(x), value=[min(x) median(x) max(x)]; end
end

function t=concatOrEmpty(rows,template)
if isempty(rows), t=template; else, t=vertcat(rows{:}); end
end
