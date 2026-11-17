function id = dmt_hash_file_streamed(path)
% Hash input bytes with bounded memory, retaining TLS/artifact verification.
assert(usejava('jvm'),'SHA-256 requires the normal MATLAB JVM.');
fid = fopen(path,'rb');
assert(fid>=0,'Cannot read file: %s',path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
digest = java.security.MessageDigest.getInstance('SHA-256');
while true
    bytes = fread(fid,1024*1024,'*uint8');
    if isempty(bytes)
        break;
    end
    digest.update(typecast(bytes(:),'int8'));
end
raw = typecast(digest.digest(),'uint8');
id = lower(reshape(dec2hex(raw,2).',1,[]));
end
