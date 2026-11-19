function result = run_dmt_vcsel_three_order(mode,varargin)
%RUN_DMT_VCSEL_THREE_ORDER Scan and, if qualified, test one mixed-QAM point.
% Selfcheck does not sweep candidates or acquire formal payloads.
if nargin==0,mode='selfcheck';end
mode=validatestring(mode,{'selfcheck','run'});
inputs=inputParser;
addParameter(inputs,'OutputDirectory','',@(x)ischar(x)||(isstring(x)&&isscalar(x)));
parse(inputs,varargin{:});
module=fileparts(mfilename('fullpath'));
project=fileparts(module);
output=char(inputs.Results.OutputDirectory);
assert(~strcmp(mode,'selfcheck') || isempty(output), ...
    'DMT:VMThreeOrderOutput','Selfcheck does not write an output directory.');

% MATLAB private functions are lexical. Stage the exact existing helpers in
% a uniquely named package, so the historical source manifest stays intact.
stage=canonical(tempname);
ensureDirectory(stage);
removeStage=onCleanup(@()rmdir(stage,'s')); %#ok<NASGU>
[~,tag]=fileparts(stage);
package=matlab.lang.makeValidName(['vm_three_order_' tag]);
context=fullfile(stage,['+' package]);
ensureDirectory(context);
helpers=fullfile(context,'private');
ensureDirectory(helpers);
copyMatlabFiles(fullfile(project,'private'),helpers);
copyMatlabFiles(fullfile(module,'private'),helpers);
copyOne(fullfile(module,'dmt_vm_three_order_execute.m'),context);
copyOne(fullfile(module,'dmt_vm_three_order_figure.m'),helpers);

previousPath=path;
restorePath=onCleanup(@()path(previousPath)); %#ok<NASGU>
addpath(stage,'-begin');
rehash
name=[package '.dmt_vm_three_order_execute'];
resolved=which(name);
expected=fullfile(context,'dmt_vm_three_order_execute.m');
assert(strcmp(resolved,expected) || (ispc && strcmpi(resolved,expected)), ...
    'DMT:VMThreeOrderResolution','Could not resolve the isolated runner at %s.',expected);
runIsolated=str2func(name);
result=runIsolated(mode,project,module,context,output);
end

function ensureDirectory(folder)
[ok,detail]=mkdir(folder);
assert(ok,'DMT:VMThreeOrderMkdir','%s',detail);
end

function path=canonical(path)
file=java.io.File(path);
path=char(file.getCanonicalPath());
end

function copyMatlabFiles(source,destination)
files=dir(fullfile(source,'*.m'));
assert(~isempty(files),'DMT:VMThreeOrderStage','Missing MATLAB sources in %s.',source);
for j=1:numel(files)
    copyOne(fullfile(files(j).folder,files(j).name),destination);
end
end

function copyOne(path,destination)
[~,name,ext]=fileparts(path);
assert(~isfile(fullfile(destination,[name ext])), ...
    'DMT:VMThreeOrderStage','Duplicate staged source %s.',[name ext]);
[ok,detail]=copyfile(path,destination);
assert(ok,'DMT:VMThreeOrderStage','%s',detail);
end
