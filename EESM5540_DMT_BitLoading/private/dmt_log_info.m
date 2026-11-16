function dmt_log_info(outDir, message)
% Non-acceptance observations must not be misrepresented as PASS records.
fid = fopen(fullfile(outDir,'verification_checks.txt'),'a');
assert(fid>=0);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'INFO | %s\n',message);
fprintf('INFO | %s\n',message);
end
