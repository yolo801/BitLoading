function id = dmt_initialization_id(cfg, calibration, profiles)
% Canonical text encodes values in caller-validated shapes, not MAT compression.
% Include measured H and SNR plus every profile. Theory is diagnostic only.
parts = ["DMT initialization v"+string(cfg.protocolVersion)+ ...
    "; physical spec "+string(cfg.specVersion); ...
    "stream="+string(cfg.streamType)];
fields = {'NFFT','NCP','Fs','k','Es','h','sigma_w2','Mset','targetBER', ...
    'margin_dB','trainSymbols','probeSymbols','chunkSize', ...
    'trainDataSeed','trainNoiseSeed','probeDataSeed','probeNoiseSeed'};
for j = 1:numel(fields)
    value = cfg.(fields{j});
    parts(end+1,1) = string(fields{j})+"="+string(sprintf('%.17g,',value(:))); %#ok<AGROW>
end
parts(end+1,1) = "Hreal="+string(sprintf('%.17g,',real(calibration.H_hat(:))));
parts(end+1,1) = "Himag="+string(sprintf('%.17g,',imag(calibration.H_hat(:))));
parts(end+1,1) = "gamma="+string(sprintf('%.17g,',calibration.gamma_hat(:)));
for j = 1:numel(profiles)
    parts(end+1,1) = string(profiles(j).name)+"="+ ...
        string(sprintf('%.17g,',profiles(j).M(:))); %#ok<AGROW>
end
id = dmt_sha256(join(parts,newline));
end
