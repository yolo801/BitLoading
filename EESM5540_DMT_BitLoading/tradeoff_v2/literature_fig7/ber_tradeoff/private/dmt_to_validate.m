function [ok,reason] = dmt_to_validate(kind,data,cfg,condition,calID,scheme,slot,phase,plan)
%DMT_TO_VALIDATE Read-only semantic audit of saved tradeoff_v1 records.
% Hash/envelope/source identities and parent-record joins are audited by the
% public verifier. This routine never sends a new signal or retunes a table.
% BER failure and a genuine payload power mismatch remain valid evidence.
ok=false; reason='';
try
    require(any(strcmp(string(phase),["preflight" "formal"])), 'Unknown phase.');
    nCal=cfg.calibration_count;
    if strcmp(string(phase),'preflight'), nCal=1; end
    require(integerScalar(calID) && ismember(calID,1:nCal),'Calibration ID is outside this phase.');
    require(isstruct(condition) && isscalar(condition) && ...
        all(isfield(condition,{'condition_id','P_target','q'})), 'Missing condition identity.');
    conditionCount=numel(cfg.P_targets)*numel(cfg.adc_bits);
    require(integerScalar(condition.condition_id) && ismember(condition.condition_id,1:conditionCount), ...
        'Unknown condition index.');
    ip=floor((condition.condition_id-1)/numel(cfg.adc_bits))+1;
    iq=mod(condition.condition_id-1,numel(cfg.adc_bits))+1;
    require(condition.P_target==cfg.P_targets(ip) && condition.q==cfg.adc_bits(iq), ...
        'Condition power or ADC bits differs from the configured scan.');
    require(istable(plan) && all(string(plan.phase)==string(phase)), ...
        'Record must use its own phase plan.');
    require(isstruct(data) && isscalar(data),'Record must be a scalar structure.');
    identity(data);
    switch char(string(kind))
        case 'Shared'
            validateShared(data);
        case 'Design'
            require(any(strcmp(string(scheme),string(cfg.scheme_names))),'Unknown strategy.');
            require(textEqual(data.scheme,scheme),'Design strategy differs.');
            validateDesign(data);
        case 'Payload'
            require(any(strcmp(string(scheme),string(cfg.scheme_names))),'Unknown strategy.');
            require(integerScalar(slot) && ismember(slot,1:cfg.payload_repeats),'Unknown payload repeat slot.');
            require(textEqual(data.scheme,scheme) && data.payload_slot==slot,'Payload strategy/slot differs.');
            validatePayload(data);
        otherwise
            error('DMT:TradeoffValidation','Unknown checkpoint kind: %s',char(string(kind)));
    end
    ok=true; reason='Saved record passed read-only semantic checks.';
catch ME
    reason=ME.message;
end

    function identity(record)
        require(all(isfield(record,{'condition','calibration_id','phase'})), ...
            'Missing condition/calibration/phase identity.');
        require(isequaln(record.condition,condition) && record.calibration_id==calID && ...
            textEqual(record.phase,phase),'Record belongs to another planned condition or phase.');
    end

    function validateShared(record)
        require(all(isfield(record,{'status','M0','power0','A0','B0','H0','gamma_B', ...
            'feedback_sent','feedback_received','feedback_hash_sent','feedback_hash_received'})), ...
            'Incomplete shared initial calibration.');
        require(textEqual(record.status,'complete'),'Shared initial calibration is not complete.');
        M0=min(cfg.Mset)*ones(numel(cfg.k),1);
        require(isequal(record.M0,M0),'A0/B0 must use the predetermined minimum-order QPSK table.');
        validatePower(record.power0,M0,seedFor('Shared',0,'initial_power',NaN));
        validateMeasurement(record.A0,M0,record.power0.b,cfg.initial_A_symbols, ...
            seedFor('Shared',0,'A0',NaN),'A0',[]);
        near(record.H0,record.A0.H_hat,'Shared H0 must be the actual A0-only LS estimate.');
        validateMeasurement(record.B0,M0,record.power0.b,cfg.initial_B_symbols, ...
            seedFor('Shared',0,'B0',NaN),'B0',record.H0);
        near(record.gamma_B,record.B0.gamma,'Shared initial quality must come from independent B0.');
        sent=record.feedback_sent; received=record.feedback_received;
        fields={'condition_id','P_target','q','calibration_id','phase','active_k','Es_reference','gamma_B'};
        require(isstruct(sent) && isscalar(sent) && isequal(sort(fieldnames(sent)),sort(fields(:))) && ...
            isequaln(sent,received),'Quality-only feedback copies differ or contain receiver-private data.');
        require(sent.condition_id==condition.condition_id && sent.P_target==condition.P_target && ...
            sent.q==condition.q && sent.calibration_id==calID && textEqual(sent.phase,phase) && ...
            isequal(sent.active_k,cfg.k(:)) && sent.Es_reference==cfg.Es, 'Initial feedback identity differs.');
        near(sent.gamma_B,record.gamma_B,'Initial feedback does not equal the observed B0 quality.');
        require(textEqual(record.feedback_hash_sent,dmt_v13_hash(sent)) && ...
            textEqual(record.feedback_hash_received,dmt_v13_hash(received)) && ...
            textEqual(record.feedback_hash_sent,record.feedback_hash_received),'Ideal quality feedback hash differs.');
    end

    function validateDesign(record)
        fields={'status','rounds','initial_shared_hash','initial_gamma_B','initial_M', ...
            'predicted_BER_design','initial_allowed','M','b','H_hat','final_tx','final_rx','ack', ...
            'costs','feedback'};
        require(all(isfield(record,fields)),'Incomplete strategy design record.');
        require(hashText(record.initial_shared_hash),'Missing parent shared-calibration identity.');
        vector(record.initial_gamma_B,numel(cfg.k),'Initial quality');
        require(isreal(record.initial_gamma_B) && all(record.initial_gamma_B>0), ...
            'Initial quality must be positive linear symbol quality.');
        predicted=zeros(numel(cfg.k),numel(cfg.Mset));
        for m=1:numel(cfg.Mset)
            predicted(:,m)=qamApprox(cfg.Mset(m),record.initial_gamma_B/10^(cfg.margin_dB/10));
        end
        allowed=predicted<=cfg.targetBER;
        near(record.predicted_BER_design,predicted,'Stored design BER predictions differ from the fixed approximation.');
        require(isequal(record.initial_allowed,allowed),'Stored initial feasibility differs.');
        candidate=zeros(0,1);
        feasible=all(allowed(:,1));
        if feasible
            if textEqual(scheme,cfg.scheme_names{1})
                candidate=max(cfg.Mset(all(allowed,1)))*ones(numel(cfg.k),1);
            else
                candidate=zeros(numel(cfg.k),1);
                for k=1:numel(cfg.k), candidate(k)=max(cfg.Mset(allowed(k,:))); end
            end
        end
        require(isequal(record.initial_M,candidate),'Initial candidate does not follow the saved B0 quality.');
        require(isstruct(record.rounds) && numel(record.rounds)<=cfg.max_rounds, ...
            'Design attempts exceed the fixed round budget.');
        states=["accepted" "no_initial_candidate" "no_accepted_profile_min_order" "round_budget_exhausted"];
        require(any(strcmp(string(record.status),states)),'Design has no completed terminal status.');
        if ~feasible
            require(textEqual(record.status,'no_initial_candidate') && isempty(record.rounds), ...
                'No initial QPSK candidate must not fabricate D attempts.');
            rejectedFinal(record);
            validateCosts(record);
            return;
        end
        require(~isempty(record.rounds),'A feasible initial candidate requires an actual attempt.');
        terminal='';
        for r=1:numel(record.rounds)
            one=record.rounds(r);
            fields={'round','M','candidate_tx','candidate_rx','candidate_ack','power','Ar','Dr', ...
                'CI_low','CI_high','supported_k','status','proposed_next_M'};
            require(all(isfield(one,fields)) && one.round==r,'Missing or nonsequential design attempt.');
            require(isequal(one.M,candidate),'A complete candidate table was changed without retesting.');
            validateM(one.M);
            if textEqual(scheme,cfg.scheme_names{1})
                require(all(one.M==one.M(1)),'Uniform Adaptive lost its common modulation order.');
            end
            validateAgreement(one.candidate_tx,one.candidate_rx,one.candidate_ack,one.M,'candidate',r);
            require(textEqual(one.candidate_tx.initial_shared_hash,record.initial_shared_hash), ...
                'Candidate configuration refers to another initial calibration.');
            validatePower(one.power,one.M,seedFor(scheme,r,'power',NaN));
            validateMeasurement(one.Ar,one.M,one.power.b,cfg.design_A_symbols, ...
                seedFor(scheme,r,'Ar',NaN),'Ar',[]);
            validateMeasurement(one.Dr,one.M,one.power.b,cfg.design_D_symbols, ...
                seedFor(scheme,r,'Dr',NaN),'Dr',one.Ar.H_hat);
            [lo,hi]=wilson(one.Dr.error_bits,one.Dr.tested_bits);
            near(one.CI_low,lo,'D lower Wilson endpoint differs.');
            near(one.CI_high,hi,'D upper Wilson endpoint differs.');
            supported=hi<cfg.targetBER;
            require(isequal(one.supported_k,supported),'D support mask differs from strict upper-endpoint criterion.');
            if all(supported)
                terminal='accepted';
                require(textEqual(one.status,terminal) && isequal(one.proposed_next_M,one.M), ...
                    'Accepted attempt must retain its actually tested table.');
                require(r==numel(record.rounds),'Accepted D configuration cannot be changed by another attempt.');
            else
                [next,minRejected]=independentReduce(one.M,supported);
                if minRejected
                    terminal='no_accepted_profile_min_order';
                    require(textEqual(one.status,terminal) && isempty(one.proposed_next_M), ...
                        'Minimum-order rejection cannot advertise an untested next table.');
                    require(r==numel(record.rounds),'A failed minimum-order carrier cannot be repaired by an unplanned attempt.');
                elseif r==cfg.max_rounds
                    terminal='round_budget_exhausted';
                    require(textEqual(one.status,terminal) && isempty(one.proposed_next_M), ...
                        'Round-budget rejection cannot advertise an untested next table.');
                    require(r==numel(record.rounds),'Attempts continue after the fixed budget.');
                else
                    require(textEqual(one.status,'retest') && isequal(one.proposed_next_M,next), ...
                        'Fallback does not follow the strategy rule.');
                    require(r<numel(record.rounds),'Completed design omits its required retest or terminal reason.');
                    candidate=next;
                end
            end
        end
        require(textEqual(record.status,terminal),'Design terminal status does not follow the actual D attempts.');
        if textEqual(terminal,'accepted')
            last=record.rounds(end);
            require(isequal(record.M,last.M) && record.b==last.power.b,'Accepted M/b must be the last actually tested table.');
            near(record.H_hat,last.Ar.H_hat,'Accepted receiver estimate differs from the last current-M A_r.');
            validateAgreement(record.final_tx,record.final_rx,record.ack,record.M,'accepted',numel(record.rounds));
            final=record.final_tx;
            require(textEqual(final.initial_shared_hash,record.initial_shared_hash), ...
                'Final configuration refers to another initial calibration.');
            require(all(isfield(final,{'b','q','adc_range','H_hash','power_hash','validation_hash','channel_training_hash'})), ...
                'Final agreement omits complete operating-point identities.');
            require(final.b==record.b && final.q==condition.q && isequal(final.adc_range,cfg.adc_range), ...
                'Final b/q/ADC range differs from the actually validated operating point.');
            require(textEqual(final.H_hash,dmt_v13_hash(record.H_hat)) && ...
                textEqual(final.power_hash,dmt_v13_hash(last.power)) && ...
                textEqual(final.validation_hash,dmt_v13_hash(last.Dr)) && ...
                textEqual(final.channel_training_hash,dmt_v13_hash(last.Ar)), ...
                'Final operating-point identities are detached from power/A_r/D records.');
        else
            rejectedFinal(record);
        end
        validateCosts(record);
    end

    function validatePayload(record)
        fields={'M','b','q','symbols','metrics','error_bits','tested_bits','H_used','H_hat', ...
            'configuration_hash','design_hash','power_actual','power_relative_error','power_match'};
        require(all(isfield(record,fields)),'Incomplete completed payload record.');
        n=cfg.payload_symbols;
        if strcmp(string(phase),'preflight'), n=cfg.preflight_payload_symbols; end
        validateMeasurement(record,record.M,record.b,n,seedFor(scheme,0,'payload',slot), ...
            'payload',record.H_used);
        require(hashText(record.configuration_hash) && hashText(record.design_hash), ...
            'Payload is missing accepted configuration/parent design identities.');
        meanPower=record.metrics.tx_sum/record.metrics.sample_count;
        relative=(meanPower-condition.P_target)/condition.P_target;
        near(record.power_actual,meanPower,'Payload optical mean differs from raw sample sums.');
        near(record.power_relative_error,relative,'Payload power deviation differs from raw samples.');
        require(logicalScalar(record.power_match) && ...
            logical(record.power_match)==(abs(relative)<=cfg.payload_power_tolerance), ...
            'Payload matched-power status differs; never erase a mismatch or rescale it.');
    end

    function validatePower(power,M,seeds)
        fields={'b','actual_mean','target','relative_error','iterations','reachable','monotone', ...
            'seed','M','waveform_hash','compute_seconds','symbols','sample_count', ...
            'history_b','history_mean','monotonic_b_grid','monotonic_mean_grid'};
        require(isstruct(power) && isscalar(power) && all(isfield(power,fields)), ...
            'Incomplete TX-only power calibration record.');
        require(isequal(power.M,M) && power.seed==seeds.data_seed, ...
            'Power-calibration waveform belongs to another M table or independent stream.');
        require(isnan(seeds.noise_seed),'TX-only power calibration must have no fabricated noise stream.');
        if isfield(power,'noise_seed'), require(isnan(power.noise_seed),'TX-only power calibration acquired a noise stream.'); end
        if isfield(power,'data_seed'), require(power.data_seed==seeds.data_seed,'TX calibration data seed aliases disagree.'); end
        require(power.symbols==cfg.power_cal_symbols && ...
            power.sample_count==cfg.power_cal_symbols*(cfg.NFFT+cfg.NCP), ...
            'Power-calibration sample budget does not include the exact CP samples.');
        require(scalarFinite(power.b) && power.b>=cfg.b_bounds(1) && power.b<=cfg.b_bounds(2), ...
            'Power-calibration bias is outside its fixed search interval.');
        require(power.target==condition.P_target && scalarFinite(power.actual_mean) && ...
            power.actual_mean>=0 && power.actual_mean<=cfg.P_peak, 'Invalid calibration target/actual optical mean.');
        near(power.relative_error,power.actual_mean/condition.P_target-1,'Power-calibration relative error differs.');
        require(abs(power.relative_error)<=cfg.power_cal_tolerance && ...
            logicalScalar(power.reachable) && power.reachable && logicalScalar(power.monotone) && power.monotone, ...
            'TX calibration did not meet reachability/monotonicity/target tolerance.');
        require(integerScalar(power.iterations) && power.iterations<=cfg.power_cal_max_iterations && ...
            scalarFinite(power.compute_seconds) && power.compute_seconds>=0 && hashText(power.waveform_hash), ...
            'Invalid calibration iteration, timing or fixed-waveform identity.');
        bs=power.monotonic_b_grid(:); ms=power.monotonic_mean_grid(:);
        require(numel(bs)>=2 && numel(bs)==numel(ms) && all(isfinite(bs)) && all(isfinite(ms)) && ...
            all(diff(bs)>0) && all(diff(ms)>=-1e-12) && bs(1)==cfg.b_bounds(1) && bs(end)==cfg.b_bounds(2), ...
            'Saved power-calibration monotonicity grid is invalid.');
        require(ms(1)<=condition.P_target && ms(end)>=condition.P_target, ...
            'Target was not bracketed on the saved fixed calibration waveform.');
        hb=power.history_b(:); hm=power.history_mean(:);
        require(~isempty(hb) && numel(hb)==numel(hm) && all(isfinite(hb)) && ...
            all(hb>=cfg.b_bounds(1) & hb<=cfg.b_bounds(2)) && ...
            all(isfinite(hm) & hm>=0 & hm<=cfg.P_peak), 'Invalid bisection observation history.');
        near(hb(end),power.b,'Published bias is not the final observed bisection point.');
        near(hm(end),power.actual_mean,'Published mean is not the final observed bisection mean.');
        require(numel(hb)==power.iterations+2 && isequal(hb(1:2),cfg.b_bounds(:)), ...
            'Bisection history does not contain the two declared endpoint observations and actual iterations.');
        near(hm(1:2),[ms(1);ms(end)],'Bisection endpoint means differ from the fixed-waveform reachability grid.');
        lo=cfg.b_bounds(1); hi=cfg.b_bounds(2);
        for j=3:numel(hb)
            near(hb(j),(lo+hi)/2,'Bias search did not follow the declared fixed-waveform bisection.');
            if hm(j)<condition.P_target, lo=hb(j); else, hi=hb(j); end
            if j<numel(hb)
                require(abs(hm(j)/condition.P_target-1)>cfg.power_cal_tolerance, ...
                    'Power search continued after its fixed convergence criterion.');
            end
        end
        extra={'mean_square','peak','minimum','lower_clip_count','upper_clip_count','drive_ac_mean_square'};
        require(all(isfield(power,extra)),'Power calibration omits actual optical/drive/clipping statistics.');
        require(scalarFinite(power.mean_square) && power.mean_square>=power.actual_mean^2-1e-10 && ...
            power.mean_square<=cfg.P_peak*power.actual_mean+1e-10 && ...
            power.minimum>=-1e-12 && power.peak<=cfg.P_peak+1e-12 && power.peak>=power.minimum && ...
            power.actual_mean>=power.minimum-1e-12 && power.actual_mean<=power.peak+1e-12 && ...
            scalarFinite(power.drive_ac_mean_square) && power.drive_ac_mean_square>=0, ...
            'Invalid power-calibration first/second moments or sampled optical extrema.');
        clips=[power.lower_clip_count power.upper_clip_count];
        require(all(isfinite(clips) & clips>=0 & clips==fix(clips)) && sum(clips)<=power.sample_count, ...
            'Invalid TX-only calibration clipping counters.');
    end

    function validateMeasurement(m,M,b,n,seeds,role,H)
        fields={'condition','role','M','M_rx','b','q','seeds','symbols','nSymbols_requested','training', ...
            'H_hat','H_used','gamma','known_energy_sum','received_cross_sum','received_energy_sum', ...
            'residual_sum_sq','metrics','error_bits','tested_bits','add_noise','noise_variance', ...
            'adc_bypass','adc_range','compute_seconds'};
        require(isstruct(m) && isscalar(m) && all(isfield(m,fields)), ...
            'Incomplete actual forward measurement record.');
        validateM(M);
        require(isequaln(m.condition,condition) && textEqual(m.role,role) && ...
            isequal(m.M,M) && m.b==b && m.q==condition.q && ...
            m.symbols==n && m.nSymbols_requested==n, ...
            'Measurement condition/current modulation/bias/role/actual budget differs.');
        require(isequal(m.M_rx,M),'Receiver demapping table differs from the actually transmitted table.');
        require(isstruct(m.seeds) && all(isfield(m.seeds,{'data_seed','noise_seed'})) && ...
            m.seeds.data_seed==seeds.data_seed && m.seeds.noise_seed==seeds.noise_seed && ...
            m.seeds.data_seed~=m.seeds.noise_seed && isequaln(m.seeds,seeds), ...
            'Measurement did not use its complete independent planned role/stream identity.');
        if isfield(m,'phase'), require(textEqual(m.phase,phase),'Measured block phase differs.'); end
        require(logicalScalar(m.add_noise) && m.add_noise && m.noise_variance==cfg.noise_variance && ...
            logicalScalar(m.adc_bypass) && ~m.adc_bypass && isequal(m.adc_range,cfg.adc_range), ...
            'Measured operating point changed thermal noise, ADC range or quantizer bypass.');
        require(scalarFinite(b) && b>=cfg.b_bounds(1) && b<=cfg.b_bounds(2) && ...
            scalarFinite(m.compute_seconds) && m.compute_seconds>=0, 'Invalid bias or measurement compute time.');
        vector(m.known_energy_sum,numel(cfg.k),'Known symbol energy sum');
        vector(m.received_cross_sum,numel(cfg.k),'Received/known cross sum');
        vector(m.received_energy_sum,numel(cfg.k),'Received energy sum');
        require(isreal(m.known_energy_sum) && all(m.known_energy_sum>0) && ...
            isreal(m.received_energy_sum) && all(m.received_energy_sum>=0), 'Invalid sufficient energy sums.');
        scale=2*(M-1)/3;
        minimum=2./scale; maximum=2*(sqrt(M)-1).^2./scale;
        require(all(m.known_energy_sum>=n*minimum-1e-8 & ...
            m.known_energy_sum<=n*maximum+1e-8), 'Known symbols are inconsistent with their current unit-average QAM order.');
        if isempty(H)
            require(logicalScalar(m.training) && m.training && isempty(m.H_used), ...
                'A training block cannot reuse a preexisting channel estimate.');
            estimated=m.received_cross_sum./m.known_energy_sum;
            vector(estimated,numel(cfg.k),'Recomputed LS estimate');
            require(all(abs(estimated)>0),'Current-M LS produced a zero channel estimate.');
            near(m.H_hat,estimated,'LS channel is not the actual current-M training estimate.');
            require(isequal(size(m.error_bits),[numel(cfg.k) 1]) && all(isnan(m.error_bits)) && ...
                isequal(size(m.tested_bits),[numel(cfg.k) 1]) && all(isnan(m.tested_bits)), ...
                'Training errors are not formal D/payload counts.');
        else
            require(logicalScalar(m.training) && ~m.training,'D/B/payload cannot fit its own channel estimate.');
            vector(H,numel(cfg.k),'Frozen receiver estimate');
            require(all(abs(H)>0),'Frozen estimate has a zero response.');
            near(m.H_used,H,'Measurement used a different receiver estimate.');
            near(m.H_hat,H,'A frozen measurement changed its channel estimate.');
            expected=m.received_energy_sum./abs(H).^2+m.known_energy_sum- ...
                2*real(m.received_cross_sum./H);
            require(all(expected>=-1e-7*max(1,max(m.known_energy_sum))), ...
                'Recomputed equalized residual energy is invalid.');
            vector(m.residual_sum_sq,numel(cfg.k),'Residual energy');
            require(isreal(m.residual_sum_sq) && all(m.residual_sum_sq>0), ...
                'Actual noisy/quantized residual energy must be positive.');
            near(m.residual_sum_sq,max(0,expected),'Residual energy differs from frozen-H sufficient sums.',1e-7);
            near(m.gamma,m.known_energy_sum./m.residual_sum_sq,'Effective quality differs from the observed residual.');
            [countsValid,why]=dmt_to_count_valid(m.error_bits,m.tested_bits,M,n);
            require(countsValid,['Actual bit-error counters: ' why]);
        end
        validateMetrics(m.metrics,n);
        require(all(isfield(m,{'diagnostic_X','diagnostic_Y'})) && ...
            size(m.diagnostic_X,1)==numel(cfg.k) && ...
            size(m.diagnostic_X,2)==min(cfg.diagnostic_symbols_retained,n) && ...
            isequal(size(m.diagnostic_Y),size(m.diagnostic_X)) && ...
            all(isfinite(m.diagnostic_X(:))) && all(isfinite(m.diagnostic_Y(:))), ...
            'Declared small frequency-domain diagnostic samples are missing or oversized.');
    end

    function validateMetrics(m,n)
        fields={'symbols','sample_count','tx_sum','tx_sum_sq','drive_ac_sq_sum','lower_clip_count', ...
            'upper_clip_count','clip_error_sq_sum','adc_low_count','adc_high_count', ...
            'useful_energy_sum','cp_energy_sum','total_energy_sum','tx_min','tx_max','max_imag','parseval_error'};
        require(isstruct(m) && isscalar(m) && all(isfield(m,fields)), 'Incomplete raw power/ADC/energy counters.');
        samples=n*(cfg.NFFT+cfg.NCP);
        require(m.symbols==n && m.sample_count==samples,'Raw sample count omits CP or actual symbols.');
        numbers=cellfun(@(name)m.(name),fields);
        require(isreal(numbers) && all(isfinite(numbers)), 'Nonfinite physical sample metrics.');
        counts=[m.lower_clip_count m.upper_clip_count m.adc_low_count m.adc_high_count];
        require(all(counts>=0 & counts==fix(counts)) && ...
            sum(counts(1:2))<=samples && sum(counts(3:4))<=samples, 'TX clipping or ADC range counts are invalid.');
        require(m.tx_min>=-1e-12 && m.tx_max<=cfg.P_peak+1e-12 && m.tx_max>=m.tx_min, ...
            'Transmitted sampled optical power is outside the declared peak interval.');
        mean=m.tx_sum/samples; second=m.tx_sum_sq/samples;
        require(mean>=m.tx_min-1e-12 && mean<=m.tx_max+1e-12 && ...
            second>=mean^2-1e-10 && second<=cfg.P_peak*mean+1e-10, ...
            'Raw optical first/second moments are inconsistent.');
        energy=[m.useful_energy_sum m.cp_energy_sum m.total_energy_sum m.drive_ac_sq_sum m.clip_error_sq_sum];
        require(all(energy>=0),'Negative raw energy/drive/clipping-error sum.');
        near(m.total_energy_sum,m.useful_energy_sum+m.cp_energy_sum,'Electrical useful/CP energies do not sum.');
        require(m.max_imag>=0 && m.max_imag<=1e-10*max(1,sqrt(m.useful_energy_sum)) && ...
            m.parseval_error>=0 && m.parseval_error<=1e-9*max(1,m.useful_energy_sum/n), ...
            'Hermitian real-waveform or unitary-transform residual exceeds tolerance.');
    end

    function validateAgreement(tx,rx,ack,M,stage,r)
        require(isstruct(tx) && isscalar(tx) && isstruct(rx) && isscalar(rx) && isequaln(tx,rx), ...
            'Transmitter and receiver local configurations differ.');
        require(all(isfield(tx,{'M','protocol','condition_id','P_target','q','calibration_id','scheme','phase','stage','round', ...
            'profile_id','initial_shared_hash','bits_k','Es_reference','targetBER','margin_dB','adc_range'})), ...
            'Configuration omits the operating-point identity.');
        require(isequal(tx.M,M) && textEqual(tx.protocol,cfg.protocol) && ...
            tx.condition_id==condition.condition_id && tx.P_target==condition.P_target && tx.q==condition.q && ...
            tx.calibration_id==calID && textEqual(tx.scheme,scheme) && textEqual(tx.phase,phase) && ...
            textEqual(tx.stage,stage) && tx.round==r && hashText(tx.initial_shared_hash), ...
            'Configuration belongs to another case/attempt.');
        require(isequal(tx.bits_k,log2(M)) && tx.Es_reference==cfg.Es && ...
            tx.targetBER==cfg.targetBER && tx.margin_dB==cfg.margin_dB && ...
            isequal(tx.adc_range,cfg.adc_range),'Configuration changed mapping energy or fixed selection/ADC settings.');
        hash=dmt_v13_hash(rmfield(tx,'profile_id'));
        expectedID=sprintf('c%02d_cal%02d_%s_r%02d_%s_%s',condition.condition_id,calID, ...
            char(string(scheme)),r,char(string(stage)),hash(1:12));
        require(textEqual(tx.profile_id,expectedID),'Configuration profile ID is detached from its complete contents.');
        require(~any(isfield(tx,{'H_hat','H_true','noise','error_bits','tested_bits'})), ...
            'Transmitter-local configuration contains receiver channel/raw results.');
        require(isstruct(ack) && isscalar(ack) && all(isfield(ack,{'accepted','configuration_hash'})) && ...
            logicalScalar(ack.accepted) && ack.accepted && textEqual(ack.configuration_hash,dmt_v13_hash(tx)), ...
            'Payload/candidate use requires a valid receiver ACK for the same complete configuration.');
        require(all(isfield(ack,{'stage','profile_id','condition_id','calibration_id','scheme'})) && ...
            textEqual(ack.stage,stage) && textEqual(ack.profile_id,tx.profile_id) && ...
            ack.condition_id==condition.condition_id && ack.calibration_id==calID && textEqual(ack.scheme,scheme), ...
            'Receiver acknowledgment belongs to another configuration/case.');
    end

    function validateCosts(record)
        fields={'loading_seconds','power_seconds','training_seconds','validation_seconds','design_seconds'};
        require(isstruct(record.costs) && all(isfield(record.costs,fields)), 'Missing separated design compute timings.');
        values=cellfun(@(f)record.costs.(f),fields);
        require(isreal(values) && all(isfinite(values) & values>=0),'Invalid software compute timings.');
        fields={'initial_quality_scalar_count','validation_status_entries','loading_table_entries', ...
            'configuration_ack_count','serialized_bits'};
        require(isstruct(record.feedback) && all(isfield(record.feedback,fields)), 'Missing explicit protocol-cost counters.');
        accepted=textEqual(record.status,'accepted'); nRounds=numel(record.rounds);
        require(record.feedback.initial_quality_scalar_count==numel(cfg.k) && ...
            record.feedback.validation_status_entries==numel(cfg.k)*nRounds && ...
            record.feedback.loading_table_entries==numel(cfg.k)*(nRounds+accepted) && ...
            record.feedback.configuration_ack_count==nRounds+accepted && isnan(record.feedback.serialized_bits), ...
            'Control-cost counters differ from actual attempts or invent serialization bits.');
    end

    function rejectedFinal(record)
        require(isempty(record.M) && isempty(record.b) && isempty(record.H_hat) && ...
            isstruct(record.final_tx) && isempty(fieldnames(record.final_tx)) && ...
            isstruct(record.final_rx) && isempty(fieldnames(record.final_rx)) && ...
            isstruct(record.ack) && isempty(fieldnames(record.ack)), ...
            'Rejected design cannot advertise an untested accepted configuration.');
    end

    function [next,minRejected]=independentReduce(M,supported)
        next=M;
        failed=~supported;
        [~,indices]=ismember(M,cfg.Mset);
        minRejected=any(failed & indices==1);
        if minRejected, next=zeros(0,1); return; end
        if textEqual(scheme,cfg.scheme_names{1})
            next(:)=cfg.Mset(indices(1)-1);
        else
            next(failed)=cfg.Mset(indices(failed)-1);
        end
    end

    function seed=seedFor(strategy,r,role,j)
        seed=dmt_to_seed(plan,condition.condition_id,calID,strategy,r,role,j);
    end

    function validateM(M)
        require(isequal(size(M),[numel(cfg.k) 1]) && isreal(M) && all(ismember(M,cfg.Mset)), ...
            'A complete current modulation table must keep every configured data carrier active.');
    end
end

function p=qamApprox(M,gamma)
p=4/log2(M)*(1-1/sqrt(M))*0.5*erfc(sqrt(3*gamma/(M-1))/sqrt(2));
end

function [lo,hi]=wilson(e,n)
require(all(n>0 & e>=0 & e<=n),'Wilson input counts are invalid.');
z=1.96; p=e./n; d=1+z^2./n;
c=(p+z^2./(2*n))./d;
r=z*sqrt(p.*(1-p)./n+z^2./(4*n.^2))./d;
lo=max(0,c-r); hi=min(1,c+r);
end

function near(a,b,message,tolerance)
if nargin<4, tolerance=1e-10; end
require(isnumeric(a) && isnumeric(b) && isequal(size(a),size(b)) && ...
    all(isfinite(a(:))) && all(isfinite(b(:))) && ...
    all(abs(a(:)-b(:))<=tolerance*max(1,max(abs(b(:))))),message);
end

function vector(value,n,name)
require(isnumeric(value) && isequal(size(value),[n 1]) && all(isfinite(value(:))), ...
    [name ' must be a finite numeric carrier column.']);
end

function yes=integerScalar(value)
yes=isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value) && value>=0 && value==fix(value);
end

function yes=scalarFinite(value)
yes=isnumeric(value) && isreal(value) && isscalar(value) && isfinite(value);
end

function yes=logicalScalar(value)
yes=isscalar(value) && (islogical(value) || isnumeric(value)) && isreal(value) && isfinite(value) && ismember(value,[0 1]);
end

function yes=textEqual(a,b)
yes=(ischar(a)||(isstring(a)&&isscalar(a))) && (ischar(b)||(isstring(b)&&isscalar(b))) && strcmp(string(a),string(b));
end

function yes=hashText(value)
yes=(ischar(value)||(isstring(value)&&isscalar(value))) && ...
    ~isempty(regexp(char(string(value)),'^[0-9a-f]{64}$','once'));
end

function require(condition,message)
if ~all(condition(:)), error('DMT:TradeoffValidation','%s',message); end
end
