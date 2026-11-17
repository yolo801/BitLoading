function cleanup = dmt_study_lock(outDir)
% OS file lock prevents a second MATLAB process from resuming a live study.
% The harmless lock file may remain after exit; the OS releases the held lock.
file = java.io.RandomAccessFile(fullfile(outDir,'study.lock'),'rw');
channel = file.getChannel();
try
    held = channel.tryLock();
    if isempty(held)
        error('DMT:StudyAlreadyRunning','Another process holds this study lock.');
    end
catch ME
    channel.close();
    file.close();
    error('DMT:StudyAlreadyRunning', ...
        'Cannot acquire study lock. Follow the original process/log. Details: %s',ME.message);
end
cleanup = onCleanup(@release);
    function release()
        held.release();
        channel.close();
        file.close();
    end
end
