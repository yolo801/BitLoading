function value = dmt_t2_diag_file_hash(path)
%DMT_T2_DIAG_FILE_HASH Read and hash one artifact without changing it.
fid = fopen(path,'rb');
assert(fid>=0 && isfile(path),'DMT:T2DiagnosticArtifact','Missing file: %s',path);
closer = onCleanup(@()fclose(fid)); %#ok<NASGU>
bytes = fread(fid,Inf,'*uint8');
assert(~isempty(bytes),'DMT:T2DiagnosticArtifact','Empty file: %s',path);
value = string(dmt_sha256(bytes));
end
