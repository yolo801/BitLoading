function report = verify_main_results(resultDir)
%VERIFY_MAIN_RESULTS Read-only audit of a completed nine-run MATLAB main.
% report = verify_main_results(result.output_dir)
% This checks actual saved counts and artifacts, not merely mainSymbols.
% A Fixed16 performance failure is valid data and does not fail this audit.
% Nothing is written, changed, regenerated or simulated by this function.
if nargin ~= 1 || ~(ischar(resultDir) || (isstring(resultDir) && isscalar(resultDir)))
    error('DMT:InvalidResultDirectory','Supply one completed main result directory.');
end
resultDir = char(resultDir);
assert(isfolder(resultDir),'DMT:InvalidResultDirectory','Directory not found: %s',resultDir);
checks = strings(0,1);
atol = 1e-12;
rtol = 1e-10;
fprintf('Read-only main verification: %s\n',resultDir);
files = {'final_results.mat','config_snapshot.mat','initialization.mat', ...
    'source_manifest.csv','integrity.json','seed_mapping.csv','environment.txt', ...
    'run.log','verification_checks.txt','per_subcarrier_seed.csv', ...
    'per_subcarrier_pooled.csv','nominal_vs_measured.csv','summary.csv', ...
    'dmt_comparison.png','dmt_comparison.pdf','dmt_comparison.fig', ...
    'report_notes_zh.md','results_paragraph_en.txt','figure_caption_en.txt'};
for j = 1:numel(files)
    info = dir(fullfile(resultDir,files{j}));
    require(numel(info)==1 && ~info.isdir && info.bytes>0, ...
        ['nonempty artifact ' files{j}]);
end
require(~isfile(fullfile(resultDir,'failure_status.txt')),'no failure_status.txt');
data = load(fullfile(resultDir,'final_results.mat'));
required = {'cfg','calibration','profiles','runs','pooled','nominal','summary', ...
    'seedMapping','sourceManifest','integrity','calibrationProvenance'};
require(all(isfield(data,required)),'complete final MAT fields');
cfg = data.cfg;
cal = data.calibration;
profiles = data.profiles;
runs = data.runs;
require(isstruct(cfg) && isscalar(cfg) && all(isfield(cfg, ...
    {'runMode','specVersion','protocolVersion','sourceManifestID','initializationID','streamType'})), ...
    'complete scalar run configuration');
require(isstruct(cal) && isscalar(cal) && all(isfield(cal, ...
    {'H_hat','gamma_hat','gamma_hat_dB','probeSignalSum','probeResidualSum'})), ...
    'required numerical calibration fields');
require(isstruct(profiles) && all(isfield(profiles, ...
    {'name','M','bits_per_symbol','B','R_payload'})), 'required profile fields');
require(isstruct(runs) && all(isfield(runs,{'scheme','phase','seed','symbols', ...
    'tested_bits','error_bits','data_seed','noise_seed','signal_duration_s', ...
    'useful_energy_sum','cp_energy_sum','total_energy_sum'})), 'required actual-run fields');
require(strcmp(cfg.runMode,'main'),'cfg.runMode is main');
require(strcmp(cfg.specVersion,'1.0') && strcmp(cfg.protocolVersion,'1.1'), ...
    'physical specification 1.0 and execution protocol 1.1');
frozen = dmt_default_config();
frozenFields = {'NFFT','NCP','Fs','k','h','Es','sigma_w2','Mset','targetBER', ...
    'margin_dB','trainSymbols','probeSymbols','mainSymbols','smokeSymbols','seeds','chunkSize', ...
    'trainDataSeed','trainNoiseSeed','probeDataSeed','probeNoiseSeed', ...
    'mainSeedBase','smokeSeedBase','Tu','TCP','Ts'};
for j = 1:numel(frozenFields)
    field = frozenFields{j};
    require(isfield(cfg,field),['cfg contains ' field]);
    require(isequal(double(cfg.(field)),double(frozen.(field))), ...
        ['frozen cfg.' field]);
end
require(strcmp(cfg.streamType,frozen.streamType),'frozen random stream algorithm');
snapshot = load(fullfile(resultDir,'config_snapshot.mat'),'cfg','seedMapping','sourceManifest');
initial = load(fullfile(resultDir,'initialization.mat'), ...
    'calibration','profiles','integrity','calibrationProvenance');
require(isequaln(snapshot.cfg,cfg),'final and snapshot configuration identical');
require(isequaln(initial.calibration,cal) && isequaln(initial.profiles,profiles), ...
    'final calibration/profiles equal frozen initialization');
require(isequaln(initial.calibrationProvenance,data.calibrationProvenance), ...
    'calibration provenance unchanged');
names = ["Uniform" "Loaded" "Fixed16"];
roles = ["formal_baseline" "formal_loaded" "diagnostic"];
require(numel(profiles)==3 && isequal(string({profiles.name}),names), ...
    'three profiles in fixed stream order');
require(numel(runs)==9 && all(ismember(string({runs.scheme}),names)), ...
    'exactly nine formal runs');
require(all(strcmp({runs.phase},'main')) && ~any([runs.seed]==0), ...
    'main phase only; no seed-zero smoke');
require(isequal(size(cal.H_hat),[24 1]) && isequal(size(cal.gamma_hat),[24 1]) && ...
    all(isfinite(cal.H_hat)) && all(abs(cal.H_hat)>0) && ...
    all(isfinite(cal.gamma_hat) & cal.gamma_hat>0),'finite 24-carrier calibration');
near(cal.gamma_hat_dB,10*log10(cal.gamma_hat),'linear/dB estimated SNR consistency');
near(cal.gamma_hat,cal.probeSignalSum./cal.probeResidualSum,'independent probe sum identity');
% Rebuild the loading rule independently from the saved estimated quality.
designAllowed = false(24,numel(cfg.Mset));
for j = 1:numel(cfg.Mset)
    designAllowed(:,j) = qamApprox(cfg.Mset(j), ...
        cal.gamma_hat/10^(cfg.margin_dB/10)) <= cfg.targetBER;
end
require(all(designAllowed(:,1)),'QPSK remains feasible on all 24 carriers');
expectedLoaded = zeros(24,1);
for c = 1:24
    expectedLoaded(c) = max(cfg.Mset(designAllowed(c,:)));
end
expectedUniform = max(cfg.Mset(all(designAllowed,1)));
require(isequal(profiles(1).M,expectedUniform*ones(24,1)), ...
    'Uniform equals highest feasible common order');
require(isequal(profiles(2).M,expectedLoaded),'Loaded equals estimated-SNR rule');
require(isequal(profiles(3).M,16*ones(24,1)),'Fixed16 profile definition');

seedRows = readtable(fullfile(resultDir,'per_subcarrier_seed.csv'),'TextType','string');
pooled = readtable(fullfile(resultDir,'per_subcarrier_pooled.csv'),'TextType','string');
nominal = readtable(fullfile(resultDir,'nominal_vs_measured.csv'),'TextType','string');
summary = readtable(fullfile(resultDir,'summary.csv'),'TextType','string');
carrierFields = {'scheme','seed','k','frequency_Hz','SNR_est_dB','M', ...
    'bits_per_symbol','tested_bits','error_bits','BER','CI_low','CI_high','record_type'};
require(all(ismember(carrierFields,seedRows.Properties.VariableNames)) && ...
    all(ismember(carrierFields,pooled.Properties.VariableNames)) && ...
    all(ismember([carrierFields {'BER_design','BER_nominal'}],nominal.Properties.VariableNames)), ...
    'required carrier CSV columns');
require(height(seedRows)==216 && height(pooled)==72 && height(nominal)==72, ...
    'CSV row counts: seed=216, pooled=72, nominal=72');
require(height(summary)==3 && numel(unique(string(summary.scheme)))==3 && ...
    all(ismember(string(summary.scheme),names)),'summary has one row for each strategy');
seedNumbers = str2double(string(seedRows.seed));
require(all(ismember(seedNumbers,[11 22 33])) && ...
    all(string(seedRows.record_type)=="seed"),'seed CSV labels and statistical level');
require(all(string(pooled.seed)=="pooled") && all(string(pooled.record_type)=="pooled") && ...
    all(string(nominal.seed)=="pooled") && all(string(nominal.record_type)=="pooled"), ...
    'pooled and prediction CSV contain pooled rows only');
seedKeys = string(seedRows.scheme)+":"+string(seedNumbers)+":"+string(seedRows.k);
require(numel(unique(seedKeys))==216,'unique scheme/seed/k CSV keys');
require(numel(unique(string(pooled.scheme)+":"+string(pooled.k)))==72 && ...
    numel(unique(string(nominal.scheme)+":"+string(nominal.k)))==72, ...
    'unique pooled and prediction scheme/k keys');
require(istable(data.seedMapping) && all(ismember({'stage','scheme','label','dataSeed','noiseSeed'}, ...
    data.seedMapping.Properties.VariableNames)), 'saved random-stream mapping schema');
mainMapping = data.seedMapping(string(data.seedMapping.stage)=="main",:);
require(height(mainMapping)==9,'exactly nine main stream-mapping rows');
for s = 1:3
    profile = profiles(s);
    name = names(s);
    selected = runs(strcmp({runs.scheme},profile.name));
    require(numel(selected)==3 && isequal(sort([selected.seed]),[11 22 33]), ...
        [char(name) ' exactly three distinct seeds']);
    require(all([selected.symbols]==100000) && sum([selected.symbols])==300000, ...
        [char(name) ' actual symbols: each 100000, pooled 300000']);
    require(isequal(size(profile.M),[24 1]) && all(ismember(profile.M,cfg.Mset)), ...
        [char(name) ' 24 valid QAM orders']);
    near(profile.bits_per_symbol,log2(profile.M),[char(name) ' bits per carrier']);
    near(profile.B,sum(log2(profile.M)),[char(name) ' payload B']);
    near(profile.R_payload,profile.B/cfg.Ts,[char(name) ' payload rate including CP']);
    pooledBits = zeros(24,1);
    pooledErrors = pooledBits;
    for r = 1:3
        one = selected(r);
        label = sprintf('%s seed=%d',profile.name,one.seed);
        require(isequal(size(one.tested_bits),[24 1]) && ...
            isequal(size(one.error_bits),[24 1]),[label ' count column dimensions']);
        require(all(one.tested_bits==100000*log2(profile.M)) && ...
            all(isfinite(one.error_bits) & one.error_bits>=0 & ...
            one.error_bits<=one.tested_bits & one.error_bits==fix(one.error_bits)), ...
            [label ' exact bit accounting and integer errors']);
        require(one.data_seed==cfg.mainSeedBase+1000*s+10*one.seed+1 && ...
            one.noise_seed==cfg.mainSeedBase+1000*s+10*one.seed+2, ...
            [label ' original independent stream mapping']);
        mapped = mainMapping(string(mainMapping.scheme)==name & mainMapping.label==one.seed,:);
        require(height(mapped)==1 && mapped.dataSeed==one.data_seed && ...
            mapped.noiseSeed==one.noise_seed,[label ' saved mapping agrees with actual run']);
        near(one.signal_duration_s,100000*cfg.Ts,[label ' signal duration']);
        energy = [one.useful_energy_sum one.cp_energy_sum one.total_energy_sum];
        require(all(isfinite(energy) & energy>=0),[label ' finite nonnegative energy']);
        near(one.total_energy_sum,one.useful_energy_sum+one.cp_energy_sum, ...
            [label ' total energy equals useful plus CP']);
        rows = sortrows(seedRows(string(seedRows.scheme)==name & seedNumbers==one.seed,:),'k');
        verifyCarrierRows(rows,profile,one.tested_bits,one.error_bits,label);
        pooledBits = pooledBits+one.tested_bits;
        pooledErrors = pooledErrors+one.error_bits;
    end
    rows = sortrows(pooled(string(pooled.scheme)==name,:),'k');
    verifyCarrierRows(rows,profile,pooledBits,pooledErrors,[char(name) ' pooled']);
    require(all(rows.tested_bits==300000*log2(profile.M)), ...
        [char(name) ' pooled counts equal exactly three formal seeds']);
    prediction = sortrows(nominal(string(nominal.scheme)==name,:),'k');
    verifyCarrierRows(prediction,profile,pooledBits,pooledErrors,[char(name) ' prediction data']);
    near(prediction.BER_design,qamApprox(profile.M,cal.gamma_hat/10^(cfg.margin_dB/10)), ...
        [char(name) ' design approximation']);
    near(prediction.BER_nominal,qamApprox(profile.M,cal.gamma_hat), ...
        [char(name) ' nominal approximation']);
    sr = summary(string(summary.scheme)==name,:);
    summaryFields = {'test_seed_count','test_symbols','test_duration_s','B','R_payload', ...
        'total_tested_bits','total_error_bits','total_BER','worst_subcarrier_BER', ...
        'maximum_CI_upper','statistical_status','interval_status','role', ...
        'mean_useful_energy','mean_CP_energy','mean_including_CP_symbol_energy', ...
        'mean_including_CP_power','initialization_symbols','initialization_duration_s', ...
        'failed_target_k','inconclusive_k','observed_above_target_k', ...
        'expected_useful_energy','expected_CP_energy','expected_including_CP_power', ...
        'expected_including_CP_symbol_energy','useful_energy_relative_difference', ...
        'CP_energy_relative_difference','total_energy_relative_difference','power_relative_difference', ...
        'loaded_to_uniform_B_ratio','loaded_increase_percent','main_mechanism_supported'};
    require(all(ismember(summaryFields,sr.Properties.VariableNames)), ...
        [char(name) ' required summary columns']);
    require(sr.test_seed_count==3 && sr.test_symbols==300000, ...
        [char(name) ' summary actual seed/symbol counts']);
    require(string(sr.role)==roles(s),[char(name) ' formal or diagnostic role']);
    require(sr.total_tested_bits==sum(pooledBits) && sr.total_error_bits==sum(pooledErrors), ...
        [char(name) ' summary exact pooled bit/error counts']);
    near(sr.total_BER,sum(pooledErrors)/sum(pooledBits),[char(name) ' bit-weighted total BER']);
    near(sr.worst_subcarrier_BER,max(rows.BER),[char(name) ' worst observed carrier BER']);
    near(sr.maximum_CI_upper,max(rows.CI_high),[char(name) ' maximum Wilson upper']);
    near(sr.B,profile.B,[char(name) ' summary B']);
    near(sr.R_payload,profile.B/cfg.Ts,[char(name) ' summary payload rate']);
    near(sr.test_duration_s,300000*cfg.Ts,[char(name) ' pooled signal duration']);
    require(sr.initialization_symbols==3072,[char(name) ' initialization is separate']);
    near(sr.initialization_duration_s,3072*cfg.Ts,[char(name) ' initialization duration']);
    meanUseful = sum([selected.useful_energy_sum])/300000;
    meanCP = sum([selected.cp_energy_sum])/300000;
    near(sr.mean_useful_energy,meanUseful,[char(name) ' measured useful energy']);
    near(sr.mean_CP_energy,meanCP,[char(name) ' measured CP energy']);
    near(sr.mean_including_CP_symbol_energy,meanUseful+meanCP,[char(name) ' measured total energy']);
    near(sr.mean_including_CP_power,(meanUseful+meanCP)/(cfg.NFFT+cfg.NCP), ...
        [char(name) ' measured sample power']);
    near([sr.expected_useful_energy sr.expected_CP_energy ...
        sr.expected_including_CP_power sr.expected_including_CP_symbol_energy], ...
        [48 6 0.75 54],[char(name) ' energy and power expectations']);
    near([sr.useful_energy_relative_difference sr.CP_energy_relative_difference ...
        sr.total_energy_relative_difference sr.power_relative_difference], ...
        [meanUseful/48-1 meanCP/6-1 (meanUseful+meanCP)/54-1 ...
        (meanUseful+meanCP)/(cfg.NFFT+cfg.NCP)/0.75-1], ...
        [char(name) ' energy and power relative differences']);
    require(abs(meanUseful/48-1)<=0.02 && abs(meanCP/6-1)<=0.02 && ...
        abs((meanUseful+meanCP)/54-1)<=0.02,[char(name) ' energy expectation tolerance 2 percent']);
    status = "insufficient_evidence";
    if any(rows.CI_low>cfg.targetBER)
        status = "failed_target";
    elseif all(rows.CI_high<cfg.targetBER)
        status = "supported_fixed_profile";
    end
    require(string(sr.statistical_status)==status && string(sr.interval_status)==status, ...
        [char(name) ' recomputed pointwise target status']);
    require(string(sr.failed_target_k)==string(mat2str(rows.k(rows.CI_low>cfg.targetBER).')) && ...
        string(sr.inconclusive_k)==string(mat2str(rows.k(rows.CI_low<=cfg.targetBER & rows.CI_high>=cfg.targetBER).')) && ...
        string(sr.observed_above_target_k)==string(mat2str(rows.k(rows.BER>cfg.targetBER).')), ...
        [char(name) ' affected carrier lists']);
end
% Verify the frozen run's own manifest. Do not compare to today's source tree:
% an old valid result may be inspected after the local code has been updated.
manifest = readtable(fullfile(resultDir,'source_manifest.csv'),'TextType','string');
require(all(ismember({'relative_path','sha256','bytes'},manifest.Properties.VariableNames)), ...
    'source manifest schema');
require(numel(unique(string(manifest.relative_path)))==height(manifest) && ...
    all(manifest.bytes>0 & manifest.bytes==fix(manifest.bytes)), ...
    'source manifest unique paths and positive byte counts');
require(all(cellfun(@(x) ~isempty(regexp(x,'^[0-9a-f]{64}$','once')), ...
    cellstr(string(manifest.sha256)))),'source manifest valid SHA-256 text');
compareTable(manifest,data.sourceManifest,{'relative_path'},'saved source manifest');
require(isequaln(snapshot.sourceManifest,data.sourceManifest),'snapshot manifest unchanged');
manifest = sortrows(manifest,'relative_path');
sourceID = dmt_sha256(join(string(manifest.relative_path)+" "+string(manifest.sha256),newline));
initialID = dmt_initialization_id(cfg,cal,profiles);
integrityJSON = jsondecode(fileread(fullfile(resultDir,'integrity.json')));
require(strcmp(sourceID,cfg.sourceManifestID) && ...
    strcmp(sourceID,data.integrity.source_manifest_sha256) && ...
    strcmp(sourceID,initial.integrity.source_manifest_sha256) && ...
    strcmp(sourceID,integrityJSON.source_manifest_sha256),'source manifest identity agrees across snapshots');
require(strcmp(initialID,cfg.initializationID) && ...
    strcmp(initialID,data.integrity.initialization_profile_sha256) && ...
    strcmp(initialID,initial.integrity.initialization_profile_sha256) && ...
    strcmp(initialID,integrityJSON.initialization_profile_sha256),'frozen calibration/profile identity');
compareTable(pooled,data.pooled,{'scheme','k'},'pooled CSV versus MAT');
compareTable(nominal,data.nominal,{'scheme','k'},'prediction CSV versus MAT');
compareTable(summary,data.summary,{'scheme'},'summary CSV versus MAT');
seedMapping = readtable(fullfile(resultDir,'seed_mapping.csv'),'TextType','string');
compareTable(seedMapping,data.seedMapping,{'stage','scheme','label'},'seed CSV versus MAT');
require(isequaln(snapshot.seedMapping,data.seedMapping),'snapshot seed mapping unchanged');
allSeeds = [data.seedMapping.dataSeed;data.seedMapping.noiseSeed];
allSeeds = allSeeds(isfinite(allSeeds));
require(numel(allSeeds)==numel(unique(allSeeds)),'all recorded data/noise seeds are distinct');
u = summary(string(summary.scheme)=="Uniform",:);
l = summary(string(summary.scheme)=="Loaded",:);
gain = l.B/u.B;
formalSupport = gain>1 && string(u.statistical_status)=="supported_fixed_profile" && ...
    string(l.statistical_status)=="supported_fixed_profile";
near(summary.loaded_to_uniform_B_ratio,repmat(gain,3,1),'summary payload ratio');
near(summary.loaded_increase_percent,repmat(100*(gain-1),3,1),'summary payload increase percent');
require(all(booleanColumn(summary.main_mechanism_supported, ...
    'main_mechanism_supported')==formalSupport), ...
    'main comparison uses Uniform/Loaded only');
logText = fileread(fullfile(resultDir,'run.log'));
require(~isempty(regexp(logText,'(?m)^Completed main at .+','once')), ...
    'run log contains actual Completed main record');
verification = fileread(fullfile(resultDir,'verification_checks.txt'));
require(isempty(regexp(verification,'(?m)^FAIL\s*\|','once')), ...
    'verification log has no failed implementation checks');
require(~isempty(regexp(verification,'(?m)^PASS\s*\|','once')), ...
    'verification log contains executed checks');
paragraph = strtrim(fileread(fullfile(resultDir,'results_paragraph_en.txt')));
wordCount = numel(regexp(paragraph,'\s+','split'));
require(wordCount>=150 && wordCount<=200,'formal English paragraph contains 150--200 words');
report = struct('output_dir',resultDir,'valid',true,'completed_groups',9, ...
    'summary',summary,'status','complete_main_data_verified', ...
    'main_mechanism_supported',formalSupport,'checks',checks, ...
    'note','Integrity verified; statistical performance states remain as observed.');
fprintf('Verified 9/9 completed main groups; %d data checks passed.\n',numel(checks));
fprintf('Fixed16 target failure is retained as a diagnostic result. No results were changed.\n');
disp(summary(:,{'scheme','B','R_payload','total_tested_bits','total_error_bits', ...
    'total_BER','worst_subcarrier_BER','statistical_status'}));

    function require(condition,label)
        passed = isscalar(condition) && logical(condition);
        if ~passed
            error('DMT:InvalidMainResults','Main verification failed: %s',label);
        end
        checks(end+1,1) = string(label);
        fprintf('PASS | %s | observed=1 | expected=1 | tolerance=0\n',label);
    end

    function near(observed,expected,label)
        require(isequal(size(observed),size(expected)),[label ' dimensions']);
        require(all(isfinite(observed(:))) && all(isfinite(expected(:))),[label ' finite values']);
        if isempty(expected)
            ratio = 0;
            delta = 0;
        else
            difference = abs(double(observed(:))-double(expected(:)));
            delta = max(difference);
            ratio = max(difference./(atol+rtol*abs(double(expected(:)))));
        end
        if ~isfinite(ratio) || ratio>1
            error('DMT:InvalidMainResults', ...
                '%s: maximum abs error %.16g; scaled error %.16g > 1 (atol=%g rtol=%g).', ...
                label,delta,ratio,atol,rtol);
        end
        checks(end+1,1) = string(label);
        fprintf('PASS | %s | max_abs_error=%.16g | scaled_error=%.16g <= 1 | atol=%g rtol=%g\n', ...
            label,delta,ratio,atol,rtol);
    end

    function verifyCarrierRows(rows,profile,bits,errors,label)
        require(height(rows)==24 && isequal(rows.k,(1:24).'),[label ' carrier k1:24 exactly once']);
        require(isequal(rows.tested_bits,bits) && isequal(rows.error_bits,errors), ...
            [label ' CSV counts match formal MAT counts']);
        near(rows.M,profile.M,[label ' modulation orders']);
        near(rows.bits_per_symbol,log2(profile.M),[label ' bits per symbol']);
        near(rows.frequency_Hz,cfg.k*cfg.Fs/cfg.NFFT,[label ' frequency units']);
        near(rows.SNR_est_dB,cal.gamma_hat_dB,[label ' frozen SNR estimate']);
        p = errors./bits;
        z = 1.96;
        d = 1+z^2./bits;
        center = (p+z^2./(2*bits))./d;
        radius = z*sqrt(p.*(1-p)./bits+z^2./(4*bits.^2))./d;
        near(rows.BER,p,[label ' observed BER']);
        near(rows.CI_low,max(0,center-radius),[label ' pointwise Wilson lower']);
        near(rows.CI_high,min(1,center+radius),[label ' pointwise Wilson upper']);
    end

    function compareTable(csvTable,matTable,keys,label)
        require(istable(matTable) && height(csvTable)==height(matTable) && ...
            isequal(csvTable.Properties.VariableNames,matTable.Properties.VariableNames), ...
            [label ' table schema']);
        left = sortrows(csvTable,keys);
        right = sortrows(matTable,keys);
        for column = 1:width(left)
            name = left.Properties.VariableNames{column};
            a = left.(name); b = right.(name);
            if islogical(a) || islogical(b)
                require(isequal(booleanColumn(a,[label ' ' name]), ...
                    booleanColumn(b,[label ' ' name])),[label ' ' name ' boolean values']);
            elseif isnumeric(a) && isnumeric(b)
                nanMatch = isequal(isnan(a),isnan(b));
                require(nanMatch,[label ' ' name ' missing values']);
                finite = ~isnan(a);
                near(double(a(finite)),double(b(finite)),[label ' ' name]);
            else
                require(isequal(string(a),string(b)),[label ' ' name ' values']);
            end
        end
    end

    function value = booleanColumn(input,label)
        if isnumeric(input) || islogical(input)
            require(all(isfinite(input(:))) && all(ismember(input(:),[0 1])), ...
                [label ' boolean encoding 0/1']);
            value = logical(input);
        else
            text = lower(string(input));
            require(all(ismember(text(:),["true" "false" "1" "0"])), ...
                [label ' boolean text encoding']);
            value = text=="true" | text=="1";
        end
    end
end

function p = qamApprox(M,gamma)
% Independent reconstruction of the documented near-neighbour approximation.
p = 4./log2(M).*(1-1./sqrt(M)).*0.5.*erfc(sqrt(3*gamma./(M-1))/sqrt(2));
end
