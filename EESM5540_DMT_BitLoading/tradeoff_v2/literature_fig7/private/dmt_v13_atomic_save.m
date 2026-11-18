function dmt_v13_atomic_save(path,checkpoint)
%DMT_V13_ATOMIC_SAVE Publish a complete small record by same-folder rename.
% The final path is never a partial MAT file. Inputs/reference files are not
% changed; callers supply only the new study's own checkpoint paths.
assert(ischar(path) || (isstring(path) && isscalar(path)), ...
    'DMT:InvalidCheckpointPath','Supply one checkpoint path.');
path=char(path);
folder=fileparts(path);
if isempty(folder), folder=pwd; end
assert(isfolder(folder),'DMT:InvalidCheckpointPath','Checkpoint folder does not exist.');
temporary=[tempname(folder) '.mat'];
cleanup=onCleanup(@()removeTemporary(temporary)); %#ok<NASGU>
save(temporary,'checkpoint','-v7');
[ok,message]=movefile(temporary,path,'f');
assert(ok,'DMT:CheckpointSave','Cannot publish complete checkpoint: %s',message);
end

function removeTemporary(path)
if isfile(path), delete(path); end
end
