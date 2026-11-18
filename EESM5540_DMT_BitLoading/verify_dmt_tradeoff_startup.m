function environment = verify_dmt_tradeoff_startup()
%VERIFY_DMT_TRADEOFF_STARTUP Check private resolution and the startup MAT save.
root = fileparts(mfilename('fullpath'));
runtime = @dmt_to_runtime;
identity = functions(runtime);
assertSameFile(identity.file, fullfile(root,'private','dmt_to_runtime.m'));
runner = which('run_dmt_tradeoff');
assertSameFile(runner, fullfile(root,'run_dmt_tradeoff.m'));
fprintf('Runner: %s\nRuntime recorder: %s\n',runner,identity.file);

environment = runtime(root);
records = environment.resolved_functions;
assert(isrow(records) && numel(records)==16 && ...
    isequal(fieldnames(records),{'name';'first';'all'}), ...
    'DMT:TradeoffStartupFields','Expected sixteen function path records with a common schema.');
for item = records
    assert(~isempty(item.name) && ~isempty(item.first) && iscell(item.all), ...
        'DMT:TradeoffStartupPaths','Incomplete function path metadata.');
end

folder = tempname();
[created,message] = mkdir(folder);
assert(created,'DMT:TradeoffStartupTempDir','Cannot create temporary directory: %s',message);
cleanup = onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
path = fullfile(folder,'environment.mat');
dmt_v13_atomic_save(path,environment);
saved = load(path,'checkpoint');
assert(isequaln(saved.checkpoint,environment), ...
    'DMT:TradeoffStartupReadback','Environment fields differ after the existing MAT save and readback.');
fprintf('TRADEOFF STARTUP VERIFIED | MATLAB %s | %d path records saved and read back\n', ...
    environment.version,numel(records));
end

function assertSameFile(actual,expected)
assert(~isempty(actual),'DMT:TradeoffStartupMissing','Cannot resolve %s.',expected);
actualFile = java.io.File(actual);
expectedFile = java.io.File(expected);
match = strcmp(char(actualFile.getCanonicalPath()),char(expectedFile.getCanonicalPath()));
if ispc
    match = strcmpi(char(actualFile.getCanonicalPath()),char(expectedFile.getCanonicalPath()));
end
assert(match,'DMT:TradeoffStartupShadowed','Expected %s, resolved %s.',expected,actual);
end
