function dmt_study_atomic_save(path, value)
%DMT_STUDY_ATOMIC_SAVE Publish one complete small MAT checkpoint by rename.
% A crash during save leaves only a temporary file; that file cannot be
% mistaken for the final group path by the resume validators.
assert(ischar(path) || (isstring(path) && isscalar(path)), ...
    'DMT:InvalidCheckpointPath','Supply one checkpoint path.');
path = char(path);
folder = fileparts(path);
if isempty(folder)
    folder = pwd;
end
assert(isfolder(folder),'DMT:InvalidCheckpointPath','Checkpoint directory must already exist.');
temporary = [tempname(folder) '.mat'];
cleanup = onCleanup(@() removeTemporary(temporary)); %#ok<NASGU>
checkpoint = value; %#ok<NASGU>
save(temporary,'checkpoint','-v7');
[ok,message] = movefile(temporary,path,'f');
assert(ok,'DMT:CheckpointSave','Could not publish checkpoint: %s',message);
end

function removeTemporary(path)
if isfile(path)
    delete(path);
end
end
