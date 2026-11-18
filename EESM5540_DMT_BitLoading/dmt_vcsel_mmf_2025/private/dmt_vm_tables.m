function [tables,stats]=dmt_vm_tables(cfg,plan,records)
%DMT_VM_TABLES Rebuild audit tables from checkpoint values, without modulation.
phase=char(string(plan.phase(1)));
assert(numel(unique(plan.phase))==1 && any(strcmp(phase,{'pilot','formal'})));
formal=strcmp(phase,'formal');
nSymbols=cfg.pilot_payload_symbols;
if formal,nSymbols=cfg.payload_symbols;end
calibrations=unique(plan.calibration_id).';
conditions=cfg.conditions(:).';
conditions=conditions(ismember([conditions.condition_id],plan.condition_id));
nCal=numel(calibrations);
nShared=numel(conditions)*nCal;
nScheme=numel(cfg.scheme_names);
nDesign=nShared*nScheme;
slots=cfg.payload_repeats;
nPlanned=nDesign*slots;
k=cfg.k(:);
frequency=k*cfg.Fs/cfg.NFFT/1e9;
T=(cfg.NFFT+cfg.NCP)/cfg.Fs;
assert(slots==2 && nScheme==2 && numel(records.initial)==nShared && ...
    numel(records.design)==nDesign && numel(records.payload)==nPlanned && ...
    sum(plan.role=="payload")==nPlanned, ...
    'DMT:VMTablePlan','Record counts do not match the planned design dimensions.');
key=struct('phase',string(phase),'condition_id',NaN,'case_id',NaN,'swing',NaN, ...
    'q',NaN,'P_target',NaN,'calibration_id',NaN,'strategy',"");
template=makeTemplates(key);
names=fieldnames(template);
groups=cell2struct(repmat({{}},numel(names),1),names,1);
noisePairs=containers.Map('KeyType','char','ValueType','any');

for ci=1:numel(conditions)
    c=conditions(ci);
    for ca=1:nCal
        cal=calibrations(ca);
        a=(ci-1)*nCal+ca;
        initial=records.initial{a};
        caseKey=key;
        caseKey.condition_id=c.condition_id;
        caseKey.case_id=c.case_id;
        caseKey.swing=c.swing;
        caseKey.q=c.q;
        caseKey.P_target=c.P_target;
        caseKey.calibration_id=cal;
        caseKey.strategy="Shared";
        if ~isempty(initial)
            dmt_vm_check('Shared',initial,cfg,c,cal,'',NaN,phase,plan,[]);
            quality=initial.B0.known_energy_sum./initial.B0.residual_sum_sq;
            assert(isequal(size(quality),size(k)) && all(isfinite(quality) & quality>0) && ...
                max(abs(quality-initial.gamma_B))<=1e-10*max(1,max(quality)));
            snr=carrierTable(template.snr,caseKey);
            snr.gamma_B0=quality;
            snr.SNR_dB=10*log10(quality);
            snr.probe_data_seed(:)=initial.B0.seeds.data_seed;
            snr.probe_noise_seed(:)=initial.B0.seeds.noise_seed;
            add('snr',snr);
            addPower(caseKey,initial.power0,0,"initial_power");
            addBlock(caseKey,initial.A0,0,NaN,"A0");
            addBlock(caseKey,initial.B0,0,NaN,"B0");
        end
        for si=1:nScheme
            scheme=cfg.scheme_names{si};
            designIdx=(a-1)*nScheme+si;
            design=records.design{designIdx};
            failure=[];
            if isfield(records,'failure'),failure=records.failure{designIdx};end
            assert(isempty(failure) || isempty(design),'DMT:VMTableFailure','Two terminal records for one design.');
            branch=caseKey;
            branch.strategy=string(scheme);
            s=bind(template.summary,branch);
            o=bind(template.overhead,branch);
            if ~isempty(initial)
                % A0/B0 are acquired once per pair and counted once in each
                % hypothetical standalone cycle.
                o.A0_symbols=initial.A0.symbols;
                o.B0_symbols=initial.B0.symbols;
                o.tx_only_symbols=initial.power0.symbols;
                o.tx_only_seconds=initial.power0.compute_seconds;
                o.training_compute_s=initial.A0.compute_seconds;
                o.probe_compute_s=initial.B0.compute_seconds;
            end
            accepted=false;
            if ~isempty(design)
                assert(~isempty(initial),'DMT:VMTableParent','A design lacks its shared A0/B0.');
                dmt_vm_check('Design',design,cfg,c,cal,scheme,NaN,phase,plan,initial);
                s.design_state=string(design.status);
                s.design_reason=string(design.reason);
                accepted=s.design_state=="accepted";
                if ~accepted
                    assert(s.design_state=="design_rejected" && strlength(s.design_reason)>0);
                    s.state="design_rejected";
                end
                for trial=reshape(design.rounds,1,[])
                    r=trial.round;
                    addPower(branch,trial.power,r,"power");
                    addBlock(branch,trial.Ar,r,NaN,"Ar");
                    addBlock(branch,trial.Dr,r,NaN,"Dr");
                    o.Ar_symbols=o.Ar_symbols+trial.Ar.symbols;
                    o.Dr_symbols=o.Dr_symbols+trial.Dr.symbols;
                    o.tx_only_symbols=o.tx_only_symbols+trial.power.symbols;
                    o.tx_only_seconds=o.tx_only_seconds+trial.power.compute_seconds;
                    o.training_compute_s=o.training_compute_s+trial.Ar.compute_seconds;
                    o.validation_compute_s=o.validation_compute_s+trial.Dr.compute_seconds;
                    rtable=integerTable(template.design_rounds,branch,trial.Dr,NaN);
                    rtable.round(:)=r;
                    rtable.round_state(:)=string(trial.status);
                    rtable.round_reason(:)=string(trial.reason);
                    rtable.supported=rtable.CI_high<cfg.targetBER;
                    rtable.candidate_b(:)=trial.power.b;
                    rtable.power_seed(:)=trial.power.seed;
                    rtable.training_data_seed(:)=trial.Ar.seeds.data_seed;
                    rtable.training_noise_seed(:)=trial.Ar.seeds.noise_seed;
                    rtable.validation_data_seed(:)=trial.Dr.seeds.data_seed;
                    rtable.validation_noise_seed(:)=trial.Dr.seeds.noise_seed;
                    add('design_rounds',rtable);
                end
                o.attempts=numel(design.rounds);
                o.feedback_scalars=design.feedback.initial_quality_scalar_count;
                o.validation_status_elements=design.feedback.validation_status_entries;
                o.loading_table_elements=design.feedback.loading_table_entries;
                o.acknowledgements=design.feedback.configuration_ack_count;
                o.loading_compute_s=design.costs.loading_seconds;
                o.design_compute_s=design.costs.design_seconds;
            elseif ~isempty(failure)
                s.state=string(failure.status);
                s.design_state=s.state;
                s.design_reason=string(failure.reason);
                assert(ismember(s.state,["power_error","execution_error"]) && strlength(s.design_reason)>0);
            end
            o.setup_symbols=o.A0_symbols+o.B0_symbols+o.Ar_symbols+o.Dr_symbols;
            o.T_setup_s=o.setup_symbols*T+cfg.control_delay;
            s.setup_symbols=o.setup_symbols;
            s.T_setup_s=o.T_setup_s;
            s.attempts=o.attempts;
            if accepted
                M=design.M(:);
                s.bits_per_symbol=sum(log2(M));
                s.R_nominal=s.bits_per_symbol/T;
                s.R_cycle=nCycle(s.bits_per_symbol,cfg.payload_symbols,T,s.T_setup_s);
                s.configuration_hash=string(dmt_v13_hash(design.final_tx));
                profile=carrierTable(template.profiles,branch);
                profile.M=M;
                profile.bits_k=log2(M);
                profile.b(:)=design.b;
                profile.configuration_hash(:)=s.configuration_hash;
                add('profiles',profile);
            end
            e=zeros(size(k));
            n=zeros(size(k));
            powers=nan(1,slots);
            matched=false(1,slots);
            clip=zeros(1,slots);
            oob=zeros(1,slots);
            sampleCounts=zeros(1,slots);
            papr=nan(1,slots);
            swingObserved=nan(1,slots);
            for slot=1:slots
                seed=dmt_to_seed(plan,c.condition_id,cal,scheme,0,'payload',slot);
                x=bind(template.status,branch);
                x.payload_slot=slot;
                x.planned_symbols=nSymbols;
                x.data_seed=seed.data_seed;
                x.noise_seed=seed.noise_seed;
                x.noise_pair_key=string(seed.noise_pair_key);
                x.status=s.state;
                x.reason=s.design_reason;
                payload=records.payload{(designIdx-1)*slots+slot};
                if ~isempty(payload)
                    assert(accepted,'DMT:VMTablePayload','No payload is permitted before D validation accepted.');
                    dmt_vm_payload_check(payload,cfg,c,design,seed,nSymbols);
                    [physical,power]=dmt_vm_table_metrics(cfg,c,payload);
                    addNoisePair(payload);
                    e=e+double(payload.error_bits);
                    n=n+double(payload.tested_bits);
                    powers(slot)=power;
                    matched(slot)=abs((power-c.P_target)/c.P_target)<=cfg.payload_power_tolerance;
                    assert(payload.power_match==matched(slot) && payload.power_actual==power);
                    clip(slot)=physical.tx_low_count+physical.tx_high_count;
                    oob(slot)=physical.adc_low_count+physical.adc_high_count;
                    sampleCounts(slot)=physical.samples;
                    papr(slot)=physical.drive_papr_dB;
                    swingObserved(slot)=physical.observed_swing;
                    x.status="completed";
                    x.reason="";
                    x.actual_symbols=payload.symbols;
                    x.error_bits=sum(payload.error_bits);
                    x.tested_bits=sum(payload.tested_bits);
                    x.P_actual=power;
                    x.power_match=matched(slot);
                    x.configuration_hash=s.configuration_hash;
                    physRow=bind(bind(template.power_adc,branch),physical);
                    physRow.payload_slot=slot;
                    physRow.power_match=matched(slot);
                    add('power_adc',scalarTable(physRow));
                    counts=integerTable(template.seed,branch,payload,slot);
                    counts.data_seed(:)=seed.data_seed;
                    counts.noise_seed(:)=seed.noise_seed;
                    counts.configuration_hash(:)=s.configuration_hash;
                    add('seed',counts);
                    addBlock(branch,payload,0,slot,"payload");
                end
                add('status',scalarTable(x));
            end
            sent=isfinite(powers);
            s.payload_slots_completed=sum(sent);
            if any(sent)
                s.P_actual_min=min(powers(sent));
                s.P_actual_max=max(powers(sent));
                s.tx_clip_rate=sum(clip)/sum(sampleCounts);
                s.adc_oob_rate=sum(oob)/sum(sampleCounts);
                s.papr_dB_max=max(papr(sent));
                s.observed_swing_mean=mean(swingObserved(sent));
            end
            if all(sent)
                pooled=struct('M',design.M,'symbols',slots*nSymbols,'error_bits',e,'tested_bits',n);
                rows=integerTable(template.pool,branch,pooled,NaN);
                rows.configuration_hash(:)=s.configuration_hash;
                s.BER_state="inconclusive";
                if any(rows.CI_low>cfg.targetBER)
                    s.BER_state="ber_failed";
                elseif all(rows.CI_high<cfg.targetBER)
                    s.BER_state="supported";
                end
                s.state=s.BER_state;
                s.power_match=all(matched);
                if ~s.power_match,s.state="power_mismatch";end
                s.Umax=max(rows.CI_high);
                s.Umax_over_target=s.Umax/cfg.targetBER;
                s.total_error_bits=sum(e);
                s.total_tested_bits=sum(n);
                s.overall_BER=sum(e)/sum(n);
                add('pool',rows);
            end
            add('summary',scalarTable(s));
            add('overhead',scalarTable(o));
        end
    end
end
tables=struct();
for j=1:numel(names)
    name=names{j};
    values=groups.(name);
    if isempty(values)
        blank=scalarTable(template.(name));
        tables.(name)=blank([],:);
    else
        tables.(name)=vertcat(values{:});
    end
end
[tables.scenario,tables.pair_gains,tables.length_sensitivity]= ...
    dmt_vm_table_comparisons(cfg,tables.summary,tables.status,formal,T);
status=tables.status.status;
stats=struct('planned',nPlanned,'completed',sum(status=="completed"), ...
    'design_rejected',sum(status=="design_rejected"),'power_error',sum(status=="power_error"), ...
    'execution_error',sum(status=="execution_error"),'incomplete',sum(status=="incomplete"), ...
    'qualified',sum(tables.scenario.qualified),'data_integrity_valid',true,'acquisition_complete',false);
assert(height(tables.status)==nPlanned && stats.completed+stats.design_rejected+ ...
    stats.power_error+stats.execution_error+stats.incomplete==nPlanned, ...
    'DMT:VMTableStatus','Slot states do not exactly partition the frozen plan.');
stats.acquisition_complete=stats.power_error+stats.execution_error+stats.incomplete==0 && ...
    all(~cellfun(@isempty,records.initial)) && all(~cellfun(@isempty,records.design));

    function add(name,value)
        groups.(name){end+1}=value;
    end

    function frame=carrierTable(base,identity)
        frame=scalarTable(bind(base,identity));
        frame=frame(ones(numel(k),1),:);
        frame.k=k;
        frame.frequency_GHz=frequency;
    end

    function frame=integerTable(base,identity,m,slot)
        frame=carrierTable(base,identity);
        frame.M=double(m.M(:));
        frame.error_bits=double(m.error_bits);
        frame.tested_bits=double(m.tested_bits);
        assert(iscolumn(frame.error_bits) && all(frame.error_bits>=0 & ...
            frame.error_bits==fix(frame.error_bits) & frame.error_bits<=frame.tested_bits) && ...
            all(frame.tested_bits==m.symbols*log2(frame.M)));
        frame.payload_slot(:)=slot;
        frame.actual_symbols(:)=m.symbols;
        frame.BER=frame.error_bits./frame.tested_bits;
        z=cfg.Wilson_z;
        den=frame.tested_bits+z*z;
        center=(frame.error_bits+z*z/2)./den;
        radius=z*sqrt(frame.error_bits.*(1-frame.BER)+z*z/4)./den;
        frame.CI_low=max(0,center-radius);
        frame.CI_high=min(1,center+radius);
    end

    function addBlock(identity,m,round,slot,role)
        [metric,~]=dmt_vm_table_metrics(cfg,c,m);
        add('events',scalarTable(event(bind(template.events,identity),metric,m.symbols, ...
            round,slot,role,m.seeds.data_seed,m.seeds.noise_seed,m.compute_seconds)));
    end

    function addPower(identity,power,round,role)
        [metric,~]=dmt_vm_table_metrics(cfg,c,power);
        add('events',scalarTable(event(bind(template.events,identity),metric,power.symbols, ...
            round,NaN,role,power.seed,NaN,power.compute_seconds)));
    end

    function addNoisePair(payload)
        name=char(string(payload.seeds.noise_pair_key));
        if isempty(name),return;end
        m=payload.metrics;
        signature=[payload.seeds.noise_seed,m.sample_count,m.noise_sum,m.noise_sum_sq];
        if isKey(noisePairs,name)
            assert(isequal(noisePairs(name),signature),'DMT:VMNoisePair','Actual paired noise summaries differ.');
        else
            noisePairs(name)=signature;
        end
    end
end

function rows=makeTemplates(id)
profile=bind(id,struct('k',NaN,'frequency_GHz',NaN,'M',NaN,'bits_k',NaN,'b',NaN,'configuration_hash',""));
count=bind(id,struct('k',NaN,'frequency_GHz',NaN,'M',NaN,'payload_slot',NaN, ...
    'actual_symbols',NaN,'error_bits',NaN,'tested_bits',NaN,'BER',NaN,'CI_low',NaN,'CI_high',NaN, ...
    'configuration_hash',""));
rawMetric=dmt_vm_table_metrics();
rows=struct();
rows.profiles=profile;
rows.snr=bind(id,struct('k',NaN,'frequency_GHz',NaN,'gamma_B0',NaN,'SNR_dB',NaN, ...
    'probe_data_seed',NaN,'probe_noise_seed',NaN));
rows.seed=bind(count,struct('data_seed',NaN,'noise_seed',NaN));
rows.pool=count;
rows.design_rounds=bind(count,struct('round',NaN,'round_state',"",'round_reason',"",'supported',false, ...
    'candidate_b',NaN,'power_seed',NaN,'training_data_seed',NaN,'training_noise_seed',NaN, ...
    'validation_data_seed',NaN,'validation_noise_seed',NaN));
rows.summary=bind(id,struct('state',"incomplete",'design_state',"unmeasured",'design_reason',"", ...
    'BER_state',"unmeasured",'power_match',false,'bits_per_symbol',NaN,'R_nominal',NaN,'R_cycle',NaN, ...
    'setup_symbols',0,'T_setup_s',0,'attempts',0,'configuration_hash',"",'payload_slots_completed',0, ...
    'Umax',NaN,'Umax_over_target',NaN,'total_error_bits',NaN,'total_tested_bits',NaN,'overall_BER',NaN, ...
    'P_actual_min',NaN,'P_actual_max',NaN,'tx_clip_rate',NaN,'adc_oob_rate',NaN, ...
    'papr_dB_max',NaN,'observed_swing_mean',NaN));
rows.overhead=bind(id,struct('A0_symbols',0,'B0_symbols',0,'Ar_symbols',0,'Dr_symbols',0, ...
    'setup_symbols',0,'T_setup_s',0,'tx_only_symbols',0,'tx_only_seconds',0,'attempts',0, ...
    'training_compute_s',0,'probe_compute_s',0,'validation_compute_s',0,'loading_compute_s',0, ...
    'design_compute_s',0,'feedback_scalars',0,'validation_status_elements',0, ...
    'loading_table_elements',0,'acknowledgements',0));
rows.status=bind(id,struct('payload_slot',NaN,'planned_symbols',NaN,'actual_symbols',NaN, ...
    'status',"incomplete",'reason',"",'data_seed',NaN,'noise_seed',NaN,'noise_pair_key',"", ...
    'error_bits',NaN,'tested_bits',NaN,'P_actual',NaN,'power_match',false,'configuration_hash',""));
rows.power_adc=bind(bind(id,rawMetric),struct('payload_slot',NaN,'power_match',false));
rows.events=bind(bind(id,rawMetric),struct('role',"",'round',NaN,'payload_slot',NaN,'symbols',NaN, ...
    'data_seed',NaN,'noise_seed',NaN,'compute_seconds',NaN,'forward_setup_symbols',0, ...
    'forward_payload_symbols',0,'tx_only_symbols',0));
end

function output=bind(output,values)
keys=fieldnames(values);
for j=1:numel(keys),output.(keys{j})=values.(keys{j});end
end

function output=scalarTable(record)
output=struct2table(record,'AsArray',true);
end

function r=event(r,metric,symbols,round,slot,role,dataSeed,noiseSeed,seconds)
r=bind(r,metric);
r.symbols=symbols;
r.round=round;
r.payload_slot=slot;
r.role=role;
r.data_seed=dataSeed;
r.noise_seed=noiseSeed;
r.compute_seconds=seconds;
if role=="payload"
    r.forward_payload_symbols=symbols;
elseif any(role==["power","initial_power"])
    r.tx_only_symbols=symbols;
else
    r.forward_setup_symbols=symbols;
end
end

function rate=nCycle(bits,L,T,setup)
rate=L*bits/(L*T+setup);
end
