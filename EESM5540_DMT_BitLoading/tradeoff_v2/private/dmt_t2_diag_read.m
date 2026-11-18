function [tables, completed] = dmt_t2_diag_read(outDir,protocol)
%DMT_T2_DIAG_READ Audit diagnostic content and reconstruct tables from disk.
settings = protocol.settings;
calibrations = cell(settings.calibration_count,1);
training = cell(settings.calibration_count,4);
runs = cell(settings.calibration_count,4,settings.payload_repeats);
completed = 0;
for c = 1:settings.calibration_count
    calibrations{c} = readRecord(sprintf('calibration_%02d',c));
    for arm = 1:4
        training{c,arm} = readRecord(sprintf('training_%02d_%02d',c,arm));
        for slot = 1:settings.payload_repeats
            runs{c,arm,slot} = readRecord(sprintf('payload_%02d_%02d_%02d',c,arm,slot));
            completed = completed+1;
        end
    end
end
assert(completed==sum(protocol.plan.role=="payload"));
tables = dmt_t2_diag_tables(protocol.cfg,settings,protocol.plan,calibrations,training,runs);

    function body = readRecord(stem)
        path = fullfile(outDir,'checkpoints',[stem '.mat']);
        assert(isfile(path),'DMT:T2DiagnosticIncomplete','Missing diagnostic checkpoint %s.',stem);
        saved = load(path,'checkpoint');
        ck = saved.checkpoint;
        assert(strcmp(ck.protocol_hash,protocol.protocol_hash) && ...
            strcmp(ck.record_hash,dmt_v13_hash(ck.body)), ...
            'DMT:T2DiagnosticCheckpoint','Diagnostic checkpoint identity or content differs: %s.',stem);
        body = ck.body;
    end
end
