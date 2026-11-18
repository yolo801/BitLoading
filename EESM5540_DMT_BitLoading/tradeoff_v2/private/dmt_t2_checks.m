function report = dmt_t2_checks(cfg,phase,plan)
%DMT_T2_CHECKS Mechanical checks for v2. The small fixture is not a scan.
phase = validatestring(phase,{'preflight','formal'});
assert(strcmp(cfg.protocol,'tradeoff_v2') && cfg.NFFT==64 && cfg.NCP==8 && ...
    cfg.Fs==64e6 && isequal(cfg.k(:),(1:24).') && cfg.Es==1 && ...
    isequal(cfg.h,[.25 .5 .25]) && cfg.noise_variance==1.0491e-4 && ...
    cfg.rho==4 && cfg.P_peak==2 && isequal(cfg.adc_range,[-.1 2.1]) && ...
    isequal(cfg.P_targets,[.6 .8 1 1.2 1.4]) && isequal(cfg.adc_bits,[4 6 8]) && ...
    cfg.targetBER==1e-3 && cfg.Wilson_z==1.96 && cfg.margin_dB==1 && ...
    cfg.chunkSize==1024 && cfg.payload_symbols==50000 && ...
    cfg.preflight_payload_symbols==2000 && cfg.payload_repeats==2 && ...
    cfg.calibration_count==5 && cfg.max_rounds==4 && cfg.control_delay==0 && ...
    cfg.fixed_train_symbols==1024, ...
    'DMT:T2FrozenConstants','Scientific configuration differs from the declared design.');
assert(isequal(string(cfg.scheme_names(:)),["FixedQPSK";"Fixed64QAM";"ValidatedLoading"]), ...
    'DMT:T2FrozenSchemes','Unexpected strategy names or order.');

checkADC(cfg);
checkPlan(cfg,phase,plan);
checkChunks(cfg);
checkCounts(cfg);
checkDesignGate(cfg,plan);
report = struct('stage',phase,'passed',true,'scope','mechanical checks and synthetic counter fixtures', ...
    'checks',["frozen_constants";"actual_midrise_adc";"seed_plan_and_allowed_pairing"; ...
    "fixed_waveform_noise_and_chunk_alignment";"integer_counters_wilson_power_and_cycle_arithmetic"; ...
    "fixed_authorization_high_error_retention_loading_rejection_and_missing_state"]);
end

function checkADC(cfg)
lo = cfg.adc_range(1);
hi = cfg.adc_range(2);
for q = cfg.adc_bits
    step = (hi-lo)/2^q;
    centers = lo+((0:2^q-1)+0.5)*step;
    [actual,adc] = dmt_to_quantize([lo-1 lo centers hi hi+1],q,cfg,false);
    expected = [centers(1) centers(1) centers centers(end) centers(end)];
    assert(adc.levels==2^q && adc.step==step && adc.low_count==1 && ...
        adc.high_count==1 && adc.sample_count==numel(expected) && ...
        numel(unique(actual))==2^q && max(abs(actual-expected))<10*eps(hi), ...
        'DMT:T2ADCLevels','ADC level count, endpoint saturation or strict range count differs.');
end
end

function checkPlan(cfg,phase,plan)
required = {'phase','condition_id','P_target','q','calibration_id','scheme','round', ...
    'role','payload_slot','data_seed','noise_seed','data_pair_key','noise_pair_key'};
assert(istable(plan) && all(ismember(required,plan.Properties.VariableNames)) && ...
    all(string(plan.phase)==string(phase)), ...
    'DMT:T2PlanShape','Unexpected plan schema or phase.');
payload = plan(string(plan.role)=="payload",:);
if strcmp(phase,'formal')
    budget = 450;
    validIDs = (1:15).';
    cals = (1:5).';
else
    budget = 12;
    validIDs = [9;11];
    cals = 1;
end
assert(height(payload)==budget && isequal(unique(plan.condition_id),validIDs) && ...
    isequal(unique(plan.calibration_id),cals), ...
    'DMT:T2PlanBudget','Unexpected power/ADC conditions, calibration count, or slot budget.');

slots = payload(:,{'condition_id','calibration_id','scheme','payload_slot'});
assert(height(unique(slots,'rows'))==budget && ...
    all(ismember(payload.payload_slot,1:cfg.payload_repeats)) && ...
    all(ismember(string(payload.scheme),string(cfg.scheme_names))), ...
    'DMT:T2PlanSlots','Duplicate, missing or invalid payload slot identity.');
for j = 1:height(plan)
    [adcIndex,powerIndex] = ind2sub([numel(cfg.adc_bits) numel(cfg.P_targets)],plan.condition_id(j));
    assert(plan.P_target(j)==cfg.P_targets(powerIndex) && plan.q(j)==cfg.adc_bits(adcIndex), ...
        'DMT:T2PlanCondition','Power/ADC values do not correspond to the condition identity.');
end
for conditionID = validIDs.'
    for calibrationID = cals.'
        selected = plan(plan.condition_id==conditionID & plan.calibration_id==calibrationID,:);
        shared = selected(string(selected.scheme)=="Shared",:);
        assert(isequal(sort(string(shared.role)),sort(["initial_power";"A0";"B0"])) && ...
            all(shared.round==0 & isnan(shared.payload_slot)), ...
            'DMT:T2PlanShared','Shared A0/B0 streams do not match the declared block roles.');
        for scheme = string(cfg.scheme_names(:)).'
            rows = selected(string(selected.scheme)==scheme,:);
            tx = rows(string(rows.role)=="payload",:);
            assert(isequal(sort(tx.payload_slot),(1:cfg.payload_repeats).') && all(tx.round==0), ...
                'DMT:T2PlanSlots','Expected two payload slots per strategy and calibration.');
            rounds = 1;
            roles = ["power";"Ar"];
            if scheme=="ValidatedLoading"
                rounds = cfg.max_rounds;
                roles(end+1,1) = "Dr";
            end
            assert(height(rows)==cfg.payload_repeats+numel(roles)*rounds, ...
                'DMT:T2PlanRoles','Unexpected strategy design block count.');
            for r = 1:rounds
                trial = rows(rows.round==r,:);
                assert(isequal(sort(string(trial.role)),sort(roles)) && ...
                    all(isnan(trial.payload_slot)), ...
                    'DMT:T2PlanRoles','Fixed and loaded design roles or round identities differ.');
            end
        end
        assert(all(ismember(string(selected.scheme),["Shared";string(cfg.scheme_names(:))])), ...
            'DMT:T2PlanRoles','Unknown strategy in seed plan.');
    end
end

finiteNoise = isfinite(plan.noise_seed);
txOnly = ismember(string(plan.role),["power","initial_power"]);
assert(all(finiteNoise==~txOnly) && all(isnan(plan.noise_seed(txOnly))) && ...
    all(isfinite(plan.data_seed)) && isempty(intersect(plan.data_seed,plan.noise_seed(finiteNoise))), ...
    'DMT:T2PlanRoles','TX-only/noise declarations or separation of data and noise streams differ.');
allSeeds = [plan.data_seed;plan.noise_seed(finiteNoise)];
if strcmp(phase,'formal')
    lower = 900000000;
    upper = 1100000000;
else
    lower = 1100000000;
    upper = 1300000000;
end
assert(all(allSeeds>=lower & allSeeds<upper & allSeeds==fix(allSeeds)), ...
    'DMT:T2PlanNamespaces','A seed is outside its reserved v2 phase namespace.');

% Build expected equivalence classes independently of seed values and plan keys.
% Fixed tables pair power/training/payload input across ADC resolution. All
% payload treatments at the same target/calibration/slot also pair noise.
[dataIdentity,noiseIdentity] = expectedIdentities(plan);
checkEquivalence(plan.data_seed,string(plan.data_pair_key),dataIdentity);
checkEquivalence(plan.noise_seed(finiteNoise),string(plan.noise_pair_key(finiteNoise)), ...
    noiseIdentity(finiteNoise));
end

function [data,noise] = expectedIdentities(plan)
data = strings(height(plan),1);
noise = data;
for j = 1:height(plan)
    row = plan(j,:);
    role = string(row.role);
    strategy = string(row.scheme);
    fixed = ismember(strategy,["FixedQPSK","Fixed64QAM"]);
    condition = sprintf('c%d-cal%d',row.condition_id,row.calibration_id);
    powerCalibration = sprintf('p%.17g-cal%d',row.P_target,row.calibration_id);
    suffix = sprintf('-r%d-s%g',row.round,row.payload_slot);
    identity = string(condition)+"-"+strategy+"-"+role+suffix;
    data(j) = identity;
    noise(j) = identity;
    if fixed && ismember(role,["power","Ar","payload"])
        data(j) = string(powerCalibration)+"-"+strategy+"-"+role+suffix;
    end
    if fixed && role=="Ar"
        noise(j) = string(powerCalibration)+"-"+strategy+"-Ar"+suffix;
    elseif role=="payload"
        noise(j) = string(powerCalibration)+"-payload"+suffix;
    end
end
end

function checkEquivalence(seeds,keys,identity)
[~,~,seedGroup] = unique(seeds);
[~,~,expectedGroup] = unique(identity);
groups = unique([seedGroup expectedGroup],'rows');
assert(size(groups,1)==numel(unique(seeds)) && ...
    size(groups,1)==numel(unique(identity)), ...
    'DMT:T2PlanPairing','Expected shared seeds or stream separation differ.');
for j = 1:size(groups,1)
    select = seedGroup==groups(j,1);
    if nnz(select)>1
        assert(all(~ismissing(keys(select)) & strlength(keys(select))>0) && ...
            numel(unique(keys(select)))==1, ...
            'DMT:T2PlanPairLabel','A repeated stream must have one explicit pairing key.');
    end
end
labeled = ~ismissing(keys) & strlength(keys)>0;
assert(size(unique(table(keys(labeled),seeds(labeled)),'rows'),1)==numel(unique(keys(labeled))), ...
    'DMT:T2PlanPairLabel','One pairing key labels several different streams.');
end

function checkChunks(cfg)
% A short frozen mechanical fixture uses a seed namespace outside all scans.
M = 64*ones(numel(cfg.k),1);
symbols = 37;
head = 15;
seed = 1500000001;
noiseSeed = 1500000002;
[whole,wholeBits] = dmt_v13_make_frame(cfg,M,symbols,dmt_v13_stream(cfg,seed));
data = dmt_v13_stream(cfg,seed);
[partA,bitsA] = dmt_v13_make_frame(cfg,M,head,data);
[partB,bitsB] = dmt_v13_make_frame(cfg,M,symbols-head,data);
assert(isequal(whole,[partA partB]) && ...
    all(cellfun(@(a,b,c)isequal(a,[b;c]),wholeBits,bitsA,bitsB)), ...
    'DMT:T2ChunkFrames','Fixed-order symbols or original bits changed with chunk boundaries.');
q6 = struct('q',6);
q8 = struct('q',8);
[Y6,~,~,debug6] = dmt_to_link(cfg,q6,whole,1,[],dmt_v13_stream(cfg,noiseSeed),true,false);
[~,~,~,debug8] = dmt_to_link(cfg,q8,whole,1,[],dmt_v13_stream(cfg,noiseSeed),true,false);
assert(isequal(debug6.tx_serial,debug8.tx_serial) && ...
    isequal(debug6.p,debug8.p) && isequal(debug6.noise,debug8.noise) && ...
    isequal(debug6.rx_before_adc,debug8.rx_before_adc), ...
    'DMT:T2ChunkPair','Changing ADC resolution changed a physical input upstream of the ADC.');
noise = dmt_v13_stream(cfg,noiseSeed);
[Yfirst,~,state,debugFirst] = dmt_to_link(cfg,q6,partA,1,[],noise,true,false);
[Yrest,~,~,debugRest] = dmt_to_link(cfg,q6,partB,1,state,noise,true,false);
assert(isequal(debug6.noise,[debugFirst.noise;debugRest.noise]) && ...
    max(abs(Y6-[Yfirst Yrest]),[],'all')<1e-12, ...
    'DMT:T2ChunkNoise','The noise or signal is not aligned across chunk lengths.');
end

function checkCounts(cfg)
% Exact synthetic counters are kept separate from produced scan artifacts.
nTones = numel(cfg.k);
M = 64*ones(nTones,1);
N = cfg.payload_symbols;
tested = N*log2(M);
e1 = zeros(nTones,1);
e2 = zeros(nTones,1);
e1(1) = 1030;
e2(1) = 2297;
assert(dmt_to_count_valid(e1,tested,M,N) && dmt_to_count_valid(e2,tested,M,N), ...
    'DMT:T2ExactCounts','Counter validation incorrectly rejects a complete high-error run.');
[state,berState,lo,hi] = dmt_t2_adjudicate(cfg,e1+e2,tested+tested,true,true);
[independentLo,independentHi] = dmt_wilson(e1+e2,tested+tested);
assert(sum(e1+e2)==3327 && all(tested+tested==600000) && ...
    state=="ber_failed" && berState=="ber_failed" && ...
    isequal(lo,independentLo) && isequal(hi,independentHi) && ...
    lo(1)>cfg.targetBER && lo(2)<10*eps(hi(2)) && hi(2)>0, ...
    'DMT:T2WilsonPool','Integer pool, failing lower bound or zero-count upper bound differs.');
assert(abs(hi(2)-1.96^2/(600000+1.96^2))<10*eps(hi(2)), ...
    'DMT:T2WilsonStrict','Invalid zero-error upper bound or strict threshold.');
[state,~,lower,upper] = dmt_t2_adjudicate(cfg,e1*0,tested+tested,true,true);
assert(state=="supported" && all(lower<10*eps(upper)) && all(upper>0), ...
    'DMT:T2WilsonZero','Zero observed errors must retain a positive Wilson upper bound.');
edge = cfg;
edge.targetBER = upper(1);
assert(dmt_t2_adjudicate(edge,e1*0,tested+tested,true,true)=="inconclusive", ...
    'DMT:T2WilsonStrict','A Wilson upper bound equal to target cannot pass.');
[state,berState] = dmt_t2_adjudicate(cfg,e1*0,tested+tested,true,false);
assert(state=="power_mismatch" && berState=="supported" && ...
    dmt_t2_adjudicate(cfg,[],[],false,false)=="incomplete", ...
    'DMT:T2Incomplete','Power mismatch or missing observations lost their distinct status.');
assert(abs(1.009/1-1)<=cfg.payload_power_tolerance && ...
    abs(1.011/1-1)>cfg.payload_power_tolerance && ...
    abs(.991-1.009)>cfg.payload_power_tolerance, ...
    'DMT:T2PowerTolerance','Target and pairwise power matches must be distinct.');
L = cfg.payload_symbols;
expected = L*144/((L+1024)*1.125e-6);
actual = dmt_t2_cycle_rate(cfg,sum(log2(M)),1024);
assert(abs(actual-expected)<1e-6 && actual<128e6 && ...
    cfg.initial_A_symbols==1024 && cfg.initial_B_symbols==2048 && ...
    cfg.design_D_symbols==8192 && cfg.power_cal_symbols==8192, ...
    'DMT:T2CycleRate','Fixed allocation rate or actual setup budgeting differs.');
end

function checkDesignGate(cfg,plan)
% Fixed synthetic fixture deliberately uses heavy noise, shortened training
% and a shortened payload to cover the high-error path. Nothing is saved,
% no scan phase or experiment parameter is changed, and no seed is reused
% by the main or diagnostic experiment.
fixture = cfg;
fixture.noise_variance = 0.5;
fixture.power_cal_symbols = 64;
fixture.initial_A_symbols = 64;
fixture.initial_B_symbols = 64;
fixture.design_A_symbols = 64;
fixture.fixed_train_symbols = 64;
fixture.preflight_payload_symbols = 37;
condition = struct('condition_id',9,'P_target',1,'q',8);
fixturePlan = plan(plan.condition_id==9 & plan.calibration_id==1,:);
fixturePlan.phase(:) = "preflight";
noise = isfinite(fixturePlan.noise_seed);
fixturePlan.data_seed = 1500000100+(1:height(fixturePlan)).';
[~,~,noiseGroups] = unique(fixturePlan.noise_seed(noise));
fixturePlan.noise_seed(noise) = 1500000200+noiseGroups;
design = dmt_t2_design(fixture,condition,1,'Fixed64QAM',[],fixturePlan);
first = measureFixtureSlot(fixture,condition,design,fixturePlan,1);
second = measureFixtureSlot(fixture,condition,design,fixturePlan,2);
expectedErrors = first.error_bits+second.error_bits;
expectedBits = first.tested_bits+second.tested_bits;
[~,berState] = dmt_t2_adjudicate(cfg,expectedErrors,expectedBits,true, ...
    first.power_match && second.power_match);
assert(strcmp(design.status,'fixed_authorized') && ~isfield(design,'rounds') && ...
    first.symbols==37 && second.symbols==37 && ...
    dmt_to_count_valid(first.error_bits,first.tested_bits,design.M,37) && ...
    dmt_to_count_valid(second.error_bits,second.tested_bits,design.M,37) && ...
    berState=="ber_failed", ...
    'DMT:T2FixedCounts','Fixed 64-QAM did not preserve the full synthetic high-error block.');
initial = dmt_to_initial(fixture,condition,1,fixturePlan);
rejected = dmt_t2_design(fixture,condition,1,'ValidatedLoading',initial,fixturePlan);
assert(strcmp(rejected.status,'no_initial_candidate') && isempty(rejected.rounds), ...
    'DMT:T2RejectedFixture','The high-noise fixture must exercise loading rejection.');
tables = dmt_t2_tables(fixture,'preflight',fixturePlan,{initial}, ...
    {[];design;rejected},{[];[];first;second;[];[]});
fixed = tables.summary(tables.summary.scheme=="Fixed64QAM",:);
assert(height(fixed)==1 && fixed.setup_symbols==64 && ...
    fixed.R_cycle==dmt_t2_cycle_rate(fixture,144,64) && ...
    fixed.BER_state=="ber_failed" && ...
    isequal(tables.pool.error_bits,expectedErrors) && ...
    isequal(tables.pool.tested_bits,expectedBits) && ...
    all(isnan(tables.status.tested_bits(tables.status.scheme~="Fixed64QAM"))) && ...
    all(tables.summary.test_only) && ~any(tables.scenario.qualified), ...
    'DMT:T2CounterRetention','Fixed counts/rate or unmeasured/test-only table semantics differ.');

fixedSlots = tables.status(tables.status.scheme=="Fixed64QAM",:);
rejectedSlots = tables.status(tables.status.scheme=="ValidatedLoading",:);
missingSlots = tables.status(tables.status.scheme=="FixedQPSK",:);
assert(height(fixedSlots)==2 && all(fixedSlots.status=="completed") && ...
    all(fixedSlots.design_status=="fixed_authorized") && ...
    height(rejectedSlots)==2 && all(rejectedSlots.status=="design_rejected") && ...
    all(rejectedSlots.design_status=="no_initial_candidate") && ...
    all(rejectedSlots.reason=="no_initial_candidate") && ...
    height(missingSlots)==2 && all(missingSlots.status=="incomplete") && ...
    all(missingSlots.design_status=="unmeasured") && ...
    all(missingSlots.reason=="no_saved_design"), ...
    'DMT:T2DesignSummary','Authorized, rejected and unsaved designs must retain distinct slot states.');

% Negative case uses the production dispatch before any possible emission.
payloadSeed = dmt_to_seed(fixturePlan,9,1,'ValidatedLoading',0,'payload',1);
stop = false;
try
    dmt_t2_payload(fixture,condition,rejected,payloadSeed,fixture.preflight_payload_symbols);
catch failure
    stop = any(strcmp(failure.identifier,{'DMT:TONoAcceptedProfile','DMT:T2NoAuthorizedProfile'}));
    if ~stop
        rethrow(failure);
    end
end
assert(stop,'DMT:T2RejectedEmitted','A rejected loading table reached payload dispatch.');
end

function run = measureFixtureSlot(cfg,condition,design,plan,slot)
seed = dmt_to_seed(plan,condition.condition_id,design.calibration_id,design.scheme,0,'payload',slot);
run = dmt_t2_payload(cfg,condition,design,seed,cfg.preflight_payload_symbols);
end
