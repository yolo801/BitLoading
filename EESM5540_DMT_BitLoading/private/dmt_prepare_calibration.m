function [calibration, provenance] = dmt_prepare_calibration(cfg, directory, mode, outDir)
% Reuse a validated historical calibration, or recompute with identical seeds.
% Reference data are never payload input or added to formal BER statistics.
provenance = struct('mode',mode,'reference_directory',directory, ...
    'absolute_tolerance',1e-12,'relative_tolerance',1e-10);
if isempty(directory)
    calibration = dmt_calibrate(cfg);
    provenance.action = 'fresh_calibration_no_reference_available';
    dmt_log_info(outDir,'No reference directory: one fresh calibration using frozen seeds.');
    return;
end
configFile = fullfile(directory,'config_snapshot.mat');
initFile = fullfile(directory,'initialization.mat');
assert(isfile(configFile) && isfile(initFile),'DMT:MissingReference', ...
    'CalibrationDirectory needs config_snapshot.mat and initialization.mat.');
manifestFile = fullfile(directory,'import_manifest.csv');
if isfile(manifestFile)
    imported = readtable(manifestFile,'TextType','string');
    assert(all(ismember({'file','sha256','bytes'},imported.Properties.VariableNames)));
    for j = 1:height(imported)
        path = fullfile(directory,char(imported.file(j)));
        info = dir(path);
        ok = numel(info)==1 && info.bytes==imported.bytes(j) && ...
            strcmp(fileHash(path),char(imported.sha256(j)));
        dmt_record_check(outDir,['reference original bytes/SHA-256 ' char(imported.file(j))], ...
            double(ok),1,0,ok);
    end
    provenance.import_manifest_sha256 = fileHash(manifestFile);
end
referenceConfig = load(configFile,'cfg');
reference = load(initFile,'calibration','profiles');
assert(isfield(referenceConfig,'cfg') && isfield(reference,'calibration') && ...
    isfield(reference,'profiles'),'DMT:InvalidReference','Incomplete reference MAT data.');
required = {'NFFT','NCP','Fs','k','Es','h','sigma_w2','Mset','targetBER', ...
    'margin_dB','trainSymbols','probeSymbols','chunkSize', ...
    'trainDataSeed','trainNoiseSeed','probeDataSeed','probeNoiseSeed'};
for j = 1:numel(required)
    name = required{j};
    assert(isfield(referenceConfig.cfg,name),'Missing reference cfg.%s',name);
    a = double(cfg.(name));
    b = double(referenceConfig.cfg.(name));
    same = isequal(a(:),b(:));
    dmt_record_check(outDir,['reference physical/estimator cfg.' name],double(same),1,0,same);
end
same = isfield(referenceConfig.cfg,'streamType') && ...
    strcmp(cfg.streamType,referenceConfig.cfg.streamType);
dmt_record_check(outDir,'reference random-stream algorithm unchanged',double(same),1,0,same);
assert(strcmp(referenceConfig.cfg.specVersion,cfg.specVersion),'Physical spec version mismatch.');
validateCalibration(reference.calibration);
[expectedProfiles,feasible] = dmt_load_profiles(cfg,reference.calibration);
assert(feasible,'DMT:InfeasibleReference','Reference calibration is infeasible.');
compareProfiles(expectedProfiles,reference.profiles);
% If the user supplied a completed snapshot as well, verify its calibration.
finalFile = fullfile(directory,'final_results.mat');
if isfile(finalFile)
    finalReference = load(finalFile,'calibration','profiles','cfg');
    assert(isfield(finalReference,'calibration') && isfield(finalReference,'profiles'));
    compareCalibration(finalReference.calibration,reference.calibration,'reference final vs initialization');
    compareProfiles(expectedProfiles,finalReference.profiles);
    for j = 1:numel(required)
        name = required{j};
        assert(isfield(finalReference.cfg,name));
        a = double(finalReference.cfg.(name));
        b = double(referenceConfig.cfg.(name));
        same = isequal(a(:),b(:));
        dmt_record_check(outDir,['reference final/snapshot cfg.' name],double(same),1,0,same);
    end
    same = strcmp(finalReference.cfg.streamType,referenceConfig.cfg.streamType) && ...
        strcmp(finalReference.cfg.runMode,referenceConfig.cfg.runMode);
    dmt_record_check(outDir,'reference final/snapshot stream and mode',double(same),1,0,same);
end
if strcmp(mode,'recompute')
    calibration = dmt_calibrate(cfg);
    compareCalibration(calibration,reference.calibration,'recomputed vs saved calibration');
    [recomputedProfiles,feasible] = dmt_load_profiles(cfg,calibration);
    assert(feasible);
    compareProfiles(recomputedProfiles,reference.profiles);
    provenance.action = 'recomputed_same_seeds_and_matched_reference';
else
    calibration = reference.calibration;
    provenance.action = 'reused_validated_reference';
end
provenance.reference_config_sha256 = fileHash(configFile);
provenance.reference_initialization_sha256 = fileHash(initFile);
provenance.reference_run_mode = referenceConfig.cfg.runMode;
copyfile(configFile,fullfile(outDir,'reference_config_snapshot.mat'));
copyfile(initFile,fullfile(outDir,'reference_initialization.mat'));
dmt_log_info(outDir,sprintf('Calibration action: %s; source: %s',provenance.action,directory));

    function validateCalibration(c)
        fields = {'H_hat','gamma_hat','gamma_hat_dB','probeSignalSum', ...
            'probeResidualSum','trainingDenominator','H_true','gamma_true_dB'};
        for index = 1:numel(fields)
            name = fields{index};
            assert(isfield(c,name),'Missing reference calibration.%s',name);
            value = c.(name);
            ok = isequal(size(value),[numel(cfg.k) 1]) && all(isfinite(value(:)));
            dmt_record_check(outDir,['reference finite column calibration.' name], ...
                double(ok),1,0,ok);
        end
        assert(all(abs(c.H_hat)>0) && all(c.gamma_hat>0) && all(c.probeResidualSum>0));
        compareValue(c.gamma_hat,c.probeSignalSum./c.probeResidualSum,'gamma from independent probe sums');
        compareValue(c.gamma_hat_dB,10*log10(c.gamma_hat),'linear versus dB probe SNR');
        compareValue(c.trainingDenominator,cfg.trainSymbols*ones(numel(cfg.k),1), ...
            'QPSK block-A known energy');
        compareValue(c.probeSignalSum,cfg.probeSymbols*ones(numel(cfg.k),1), ...
            'QPSK block-B known energy');
        trueH = fft(cfg.h,cfg.NFFT).';
        compareValue(c.H_true,trueH(cfg.k+1),'reference theory diagnostic only');
        compareValue(c.gamma_true_dB,10*log10(abs(trueH(cfg.k+1)).^2/cfg.sigma_w2), ...
            'reference theory SNR diagnostic only');
    end

    function compareCalibration(a,b,label)
        fields = {'H_hat','gamma_hat','gamma_hat_dB','probeSignalSum', ...
            'probeResidualSum','trainingDenominator'};
        for index = 1:numel(fields)
            name = fields{index};
            assert(isfield(a,name) && isfield(b,name));
            compareValue(a.(name),b.(name),[label ' ' name]);
        end
    end

    function compareProfiles(current,saved)
        % Old v1.0 saved two strategies; Fixed16 is appended, never substituted.
        for index = 1:2
            match = find(strcmp({saved.name},current(index).name));
            assert(numel(match)==1,'Missing or duplicate reference profile.');
            same = isequal(double(current(index).M(:)),double(saved(match).M(:)));
            dmt_record_check(outDir,['reference profile unchanged ' current(index).name], ...
                double(same),1,0,same);
            compareValue(current(index).bits_per_symbol,saved(match).bits_per_symbol, ...
                ['profile bits ' current(index).name]);
            compareValue(current(index).B,saved(match).B,['profile B ' current(index).name]);
            compareValue(current(index).R_payload,saved(match).R_payload, ...
                ['profile rate ' current(index).name]);
        end
    end

    function compareValue(a,b,label)
        assert(isequal(size(a),size(b)) && all(isfinite(a(:))) && all(isfinite(b(:))));
        ratio = max(abs(a(:)-b(:))./ ...
            (provenance.absolute_tolerance+provenance.relative_tolerance*abs(b(:))));
        dmt_record_check(outDir,[label ' scaled error <= 1 (atol=1e-12 rtol=1e-10)'], ...
            ratio,1,0,ratio<=1);
    end
end

function id = fileHash(path)
fid = fopen(path,'rb');
assert(fid>=0);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
id = dmt_sha256(fread(fid,Inf,'*uint8'));
end
