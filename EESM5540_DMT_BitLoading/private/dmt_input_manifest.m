function manifest = dmt_input_manifest(directory)
% Full reference-tree byte hashes; input files are never rewritten.
assert(isfolder(directory),'DMT:MissingReference','Input directory not found: %s',directory);
directory = char(java.io.File(directory).getCanonicalPath());
files = dir(fullfile(directory,'**','*'));
files = files(~[files.isdir]);
relative_path = strings(numel(files),1);
sha256 = relative_path;
bytes = zeros(numel(files),1);
for j = 1:numel(files)
    path = fullfile(files(j).folder,files(j).name);
    relative_path(j) = strrep(path(numel(directory)+2:end),filesep,'/');
    sha256(j) = string(dmt_hash_file_streamed(path));
    bytes(j) = files(j).bytes;
end
manifest = sortrows(table(relative_path,sha256,bytes),'relative_path');
end
