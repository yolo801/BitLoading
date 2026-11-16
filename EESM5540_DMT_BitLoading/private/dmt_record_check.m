function dmt_record_check(outDir, name, observed, expected, tolerance, passed)
% Append numerical evidence before raising an error, preserving failed runs.
fid = fopen(fullfile(outDir,'verification_checks.txt'),'a');
assert(fid >= 0, 'Cannot open verification log.');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
status = 'FAIL';
if passed
    status = 'PASS';
end
line = sprintf('%s | %s | observed=%.16g | expected=%.16g | tolerance=%.16g\n', ...
    status,name,observed,expected,tolerance);
fprintf(fid,'%s',line);
fprintf('%s',line);
if ~passed
    error('DMT:VerificationFailed','Verification failed: %s',name);
end
end
