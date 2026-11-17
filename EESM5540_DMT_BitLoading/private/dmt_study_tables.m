function [seedTable, pooledTable, roundSummary, profileFrequency, robustness] = dmt_study_tables(cfg, rounds, runs)
%DMT_STUDY_TABLES Keep inference inside calibration_id/scheme/k only.
% Only complete 100000-symbol groups enter count tables. Incomplete or
% infeasible strategies have no fabricated BER/CI rows; their status and
% reason remain visible in the per-calibration summary.
if isfield(cfg,'NumCalibrations')
    nRounds = cfg.NumCalibrations;
else
    nRounds = 10;
end
planned = 1:nRounds;
labels = cfg.seeds(:).';
names = ["Uniform" "Loaded" "Fixed16"];
assert(cfg.mainSymbols==100000 && isequal(labels,[11 22 33]));
assert(isequal(cfg.k(:),(1:24).') && isequal(cfg.Mset,[4 16 64]));
if ~isempty(rounds)
    ids = [rounds.calibration_id];
    assert(numel(unique(ids))==numel(ids) && all(ismember(ids,planned)), ...
        'DMT:StudyRounds','Calibration records must be unique new rounds, excluding reference 0.');
end
if ~isempty(runs)
    assert(all(isfield(runs,{'calibration_id','initialization_id','scheme','seed', ...
        'phase','symbols','tested_bits','error_bits','data_seed','noise_seed'})));
    keys = string([runs.calibration_id])+":"+string({runs.scheme})+":"+string([runs.seed]);
    assert(numel(unique(keys))==numel(keys),'DMT:DuplicateStudyRun','Duplicate completed group.');
    assert(all(ismember([runs.calibration_id],planned)) && ...
        all(ismember(string({runs.scheme}),names)) && all(strcmp({runs.phase},'main')) && ...
        all(ismember([runs.seed],labels)),'DMT:StudyRunScope','Unexpected round/strategy/seed/phase.');
end
seedTable = emptyCarrierTable();
pooledTable = emptyCarrierTable();
summaryRows = cell(nRounds*3,1);
summaryIndex = 0;
selection = zeros(nRounds,3,numel(cfg.k));
known = false(nRounds,1);
infeasible = false(nRounds,1);
for id = planned
    position = [];
    if ~isempty(rounds)
        position = find([rounds.calibration_id]==id);
    end
    available = false;
    if ~isempty(position)
        round = rounds(position);
        available = isscalar(round.feasible) && isfinite(double(round.feasible));
    end
    if available
        known(id) = true;
        infeasible(id) = ~logical(round.feasible);
    end
    ratio = NaN;
    if available && round.feasible
        assert(numel(round.profiles)==3 && isequal(string({round.profiles.name}),names));
        validateCalibration(round.calibration,cfg);
        ratio = round.profiles(2).B/round.profiles(1).B;
        for s = 1:3
            p = round.profiles(s);
            assert(isequal(size(p.M),[24 1]) && all(ismember(p.M,cfg.Mset)));
            assert(isequal(p.bits_per_symbol,log2(p.M)) && p.B==sum(log2(p.M)));
            assert(abs(p.R_payload-p.B/cfg.Ts)<=1e-10*max(1,p.R_payload));
            selection(id,s,:) = reshape(p.M,1,1,[]);
        end
    end
    for s = 1:3
        summaryIndex = summaryIndex+1;
        row = blankSummary(id,names(s));
        selected = struct([]);
        if ~isempty(runs)
            selected = runs([runs.calibration_id]==id & strcmp({runs.scheme},char(names(s))));
        end
        if ~available
            assert(isempty(selected),'DMT:MissingCalibration','A completed run has no calibration record.');
            row.reason = "calibration_not_available";
        elseif ~round.feasible
            assert(isempty(selected),'DMT:InfeasibleCounts','Infeasible calibration cannot have payload counts.');
            row.status = "infeasible";
            row.reason = string(round.reason);
            row.initialization_id = string(round.initialization_id);
        else
            profile = round.profiles(s);
            row.feasible = true;
            row.initialization_id = string(round.initialization_id);
            row.B = profile.B;
            row.R_payload = profile.R_payload;
            row.loaded_to_uniform_B_ratio = ratio;
            pooledBits = zeros(24,1);
            pooledErrors = pooledBits;
            for r = 1:numel(selected)
                one = selected(r);
                validateRun(cfg,round,profile,s,one);
                seedTable = [seedTable;carrierRows(cfg,round,profile,one.tested_bits, ...
                    one.error_bits,one.seed,1,one.symbols)]; %#ok<AGROW>
                pooledBits = pooledBits+one.tested_bits;
                pooledErrors = pooledErrors+one.error_bits;
            end
            row.test_seed_count = numel(selected);
            if ~isempty(selected)
                row.test_symbols = sum([selected.symbols]);
            end
            row.test_duration_s = row.test_symbols*cfg.Ts;
            complete = numel(selected)==3 && isequal(sort([selected.seed]),labels);
            if complete
                rows = carrierRows(cfg,round,profile,pooledBits,pooledErrors,NaN,3,row.test_symbols);
                pooledTable = [pooledTable;rows]; %#ok<AGROW>
                row.total_tested_bits = sum(pooledBits);
                row.total_error_bits = sum(pooledErrors);
                row.total_BER = row.total_error_bits/row.total_tested_bits;
                row.worst_subcarrier_BER = max(rows.BER);
                row.max_normalized_CI_high = max(rows.normalized_CI_high);
                row.failed_k = string(mat2str(rows.k(rows.CI_low>cfg.targetBER).'));
                crossing = rows.CI_low<=cfg.targetBER & rows.CI_high>=cfg.targetBER;
                row.inconclusive_k = string(mat2str(rows.k(crossing).'));
                row.observed_above_target_k = string(mat2str(rows.k(rows.BER>cfg.targetBER).'));
                row.status = "inconclusive";
                if any(rows.CI_low>cfg.targetBER)
                    row.status = "failed";
                elseif all(rows.CI_high<cfg.targetBER)
                    row.status = "supported";
                end
                row.reason = "three_fixed_payload_seeds_completed";
                row.mean_useful_energy = sum([selected.useful_energy_sum])/row.test_symbols;
                row.mean_CP_energy = sum([selected.cp_energy_sum])/row.test_symbols;
                row.mean_including_CP_symbol_energy = sum([selected.total_energy_sum])/row.test_symbols;
                row.mean_including_CP_power = row.mean_including_CP_symbol_energy/(cfg.NFFT+cfg.NCP);
                row.useful_energy_relative_difference = row.mean_useful_energy/48-1;
                row.CP_energy_relative_difference = row.mean_CP_energy/6-1;
                row.total_energy_relative_difference = row.mean_including_CP_symbol_energy/54-1;
            else
                row.reason = "payload_seed_groups_incomplete";
            end
        end
        summaryRows{summaryIndex} = struct2table(row);
    end
end
roundSummary = vertcat(summaryRows{:});
profileFrequency = makeProfileFrequency(cfg,names,selection,known,infeasible);
robustness = makeRobustness(names,roundSummary,nRounds);
if height(seedTable)>0
    seedTable = sortrows(seedTable,{'calibration_id','scheme','payload_seed','k'});
end
if height(pooledTable)>0
    pooledTable = sortrows(pooledTable,{'calibration_id','scheme','k'});
end
assert(height(roundSummary)==3*nRounds);
assert(height(seedTable)==24*numel(runs));
assert(height(pooledTable)==24*sum(roundSummary.test_seed_count==3));
if all(roundSummary.status~="incomplete" & roundSummary.status~="infeasible")
    assert(height(seedTable)==nRounds*216 && height(pooledTable)==nRounds*72);
end
end

function rows = emptyCarrierTable()
names = {'calibration_id','scheme','payload_seed','k','frequency_Hz','SNR_est_dB', ...
    'M','bits_per_symbol','tested_bits','error_bits','BER','CI_low','CI_high', ...
    'normalized_CI_high','BER_design','BER_nominal','test_seed_count','test_symbols','initialization_id'};
types = [{'double','string'} repmat({'double'},1,16) {'string'}];
rows = table('Size',[0 numel(names)],'VariableTypes',types,'VariableNames',names);
end

function rows = carrierRows(cfg,round,profile,bits,errors,payloadSeed,seedCount,symbols)
bits = double(bits(:)); errors = double(errors(:));
[lo,hi] = dmt_wilson(errors,bits);
template = emptyCarrierTable();
rows = table(repmat(round.calibration_id,24,1),repmat(string(profile.name),24,1), ...
    repmat(payloadSeed,24,1),cfg.k(:),cfg.k(:)*cfg.Fs/cfg.NFFT, ...
    round.calibration.gamma_hat_dB(:),profile.M,profile.bits_per_symbol,bits,errors, ...
    errors./bits,lo,hi,hi/cfg.targetBER, ...
    dmt_qam_ber(profile.M,round.calibration.gamma_hat/10^(cfg.margin_dB/10)), ...
    dmt_qam_ber(profile.M,round.calibration.gamma_hat), ...
    repmat(seedCount,24,1),repmat(symbols,24,1),repmat(string(round.initialization_id),24,1), ...
    'VariableNames',template.Properties.VariableNames);
end

function row = blankSummary(id,name)
row = struct('calibration_id',id,'scheme',name,'initialization_id',"", ...
    'feasible',false,'status',"incomplete",'reason',"",'test_seed_count',0, ...
    'test_symbols',0,'test_duration_s',NaN,'B',NaN,'R_payload',NaN, ...
    'total_tested_bits',NaN,'total_error_bits',NaN,'total_BER',NaN, ...
    'worst_subcarrier_BER',NaN,'max_normalized_CI_high',NaN,'failed_k',"", ...
    'inconclusive_k',"",'observed_above_target_k',"",'mean_useful_energy',NaN, ...
    'mean_CP_energy',NaN,'mean_including_CP_symbol_energy',NaN, ...
    'mean_including_CP_power',NaN,'useful_energy_relative_difference',NaN, ...
    'CP_energy_relative_difference',NaN,'total_energy_relative_difference',NaN, ...
    'loaded_to_uniform_B_ratio',NaN);
end

function validateCalibration(cal,cfg)
assert(isequal(size(cal.H_hat),[24 1]) && all(isfinite(cal.H_hat)) && all(abs(cal.H_hat)>0));
assert(isequal(size(cal.gamma_hat),[24 1]) && all(isfinite(cal.gamma_hat) & cal.gamma_hat>0));
assert(isequal(size(cal.gamma_hat_dB),[24 1]) && all(isfinite(cal.gamma_hat_dB)));
assert(max(abs(cal.gamma_hat_dB-10*log10(cal.gamma_hat)))<1e-10);
assert(cfg.NFFT==64 && cfg.NCP==8 && cfg.Fs==64e6 && cfg.Es==1);
end

function validateRun(cfg,round,profile,s,one)
assert(one.symbols==100000 && strcmp(one.phase,'main'));
assert(strcmp(string(one.initialization_id),string(round.initialization_id)), ...
    'DMT:StudyFrozenProfile','Run initialization identity does not match its calibration.');
assert(isequal(size(one.tested_bits),[24 1]) && isequal(size(one.error_bits),[24 1]));
assert(all(one.tested_bits==100000*log2(profile.M)));
assert(all(isfinite(one.error_bits) & one.error_bits>=0 & ...
    one.error_bits<=one.tested_bits & one.error_bits==fix(one.error_bits)));
slot = find(cfg.seeds==one.seed);
assert(numel(slot)==1);
base = 2000000+100000*round.calibration_id;
assert(one.data_seed==base+1000*s+10*slot+1 && one.noise_seed==base+1000*s+10*slot+2, ...
    'DMT:StudySeedMapping','Payload stream does not match the independent-calibration mapping.');
energy = [one.useful_energy_sum one.cp_energy_sum one.total_energy_sum];
assert(all(isfinite(energy) & energy>=0));
assert(abs(one.total_energy_sum-one.useful_energy_sum-one.cp_energy_sum)<=1e-8*max(1,one.total_energy_sum));
end

function result = makeProfileFrequency(cfg,names,selection,known,infeasible)
rows = cell(3*24*3,1);
index = 0;
for s = 1:3
    for k = 1:24
        chosen = reshape(selection(:,s,k),[],1);
        counts = arrayfun(@(m)sum(chosen==m),cfg.Mset);
        assert(sum(counts)+sum(infeasible)+sum(~known)==numel(known));
        for j = 1:numel(cfg.Mset)
            index = index+1;
            rows{index} = table(names(s),cfg.k(k),cfg.k(k)*cfg.Fs/cfg.NFFT,cfg.Mset(j), ...
                counts(j),sum(infeasible),sum(~known),numel(known), ...
                'VariableNames',{'scheme','k','frequency_Hz','M','selection_count', ...
                'infeasible_count','uncalibrated_count','planned_calibrations'});
        end
    end
end
result = vertcat(rows{:});
end

function result = makeRobustness(names,summary,nRounds)
rows = cell(3,1);
for s = 1:3
    data = summary(summary.scheme==names(s),:);
    feasibleProfiles = data.feasible & isfinite(data.B);
    b = data.B(feasibleProfiles);
    rate = data.R_payload(feasibleProfiles);
    ratio = data.loaded_to_uniform_B_ratio(feasibleProfiles);
    [bmin,bmed,bmax] = rangeStats(b);
    [rmin,rmed,rmax] = rangeStats(rate);
    [gmin,gmed,gmax] = rangeStats(ratio);
    supported = sum(data.status=="supported");
    failed = sum(data.status=="failed");
    inconclusive = sum(data.status=="inconclusive");
    notFeasible = sum(data.status=="infeasible");
    incomplete = sum(data.status=="incomplete");
    assert(supported+failed+inconclusive+notFeasible+incomplete==nRounds);
    rows{s} = table(names(s),nRounds,supported,failed,inconclusive,notFeasible,incomplete, ...
        sum(feasibleProfiles),sum(data.test_seed_count),sum(data.test_symbols), ...
        bmin,bmed,bmax,rmin,rmed,rmax,gmin,gmed,gmax, ...
        'VariableNames',{'scheme','planned_calibrations','supported_rounds','failed_rounds', ...
        'inconclusive_rounds','infeasible_rounds','incomplete_rounds','profiled_rounds', ...
        'completed_payload_groups','completed_payload_symbols','B_min','B_median','B_max', ...
        'R_payload_min','R_payload_median','R_payload_max', ...
        'loaded_uniform_ratio_min','loaded_uniform_ratio_median','loaded_uniform_ratio_max'});
end
result = vertcat(rows{:});
end

function [minimum,med,maximum] = rangeStats(values)
values = values(isfinite(values));
minimum = NaN; med = NaN; maximum = NaN;
if ~isempty(values)
    minimum = min(values); med = median(values); maximum = max(values);
end
end
