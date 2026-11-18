function sha = dmt_fb_filehash(path)
fid = fopen(path,'rb');
assert(fid>=0,'DMT:FBFile','Cannot open %s.',path);
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
sha = dmt_sha256(fread(fid,Inf,'*uint8'));
end
