function id = dmt_sha256(bytes)
% Base MATLAB's bundled JVM; no third-party MATLAB toolbox is required.
assert(usejava('jvm'),'DMT:JVMRequired', ...
    'SHA-256 manifests require MATLAB with its JVM; do not use -nojvm.');
if ischar(bytes) || isstring(bytes)
    bytes = unicode2native(char(bytes),'UTF-8');
end
digest = java.security.MessageDigest.getInstance('SHA-256');
digest.update(typecast(uint8(bytes(:)),'int8'));
raw = typecast(digest.digest(),'uint8');
id = lower(reshape(dec2hex(raw,2).',1,[]));
end
