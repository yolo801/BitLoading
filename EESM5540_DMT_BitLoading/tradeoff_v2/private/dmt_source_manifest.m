function [manifest, id] = dmt_source_manifest(projectDir)
% Hash actual source bytes, including entry/helper/validation code.
files = [dir(fullfile(projectDir,'*.m')); ...
    dir(fullfile(projectDir,'private','*.m')); ...
    dir(fullfile(projectDir,'tools','*.py'))];
paths = strings(numel(files),1);
hashes = paths;
sizes = zeros(numel(files),1);
for j = 1:numel(files)
    path = fullfile(files(j).folder,files(j).name);
    paths(j) = strrep(path(numel(projectDir)+2:end),filesep,'/');
    fid = fopen(path,'rb');
    assert(fid>=0,'Cannot read source file: %s',path);
    cleanup = onCleanup(@() fclose(fid));
    bytes = fread(fid,Inf,'*uint8');
    hashes(j) = string(dmt_sha256(bytes));
    sizes(j) = numel(bytes);
    clear cleanup;
end
manifest = sortrows(table(paths,hashes,sizes, ...
    'VariableNames',{'relative_path','sha256','bytes'}),'relative_path');
id = dmt_sha256(join(manifest.relative_path+" "+manifest.sha256,newline));
end
