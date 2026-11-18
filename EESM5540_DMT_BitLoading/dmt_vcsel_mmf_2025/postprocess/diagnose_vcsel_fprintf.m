function report=diagnose_vcsel_fprintf(sourceFolder,varargin)
%DIAGNOSE_VCSEL_FPRINTF Reproduce the original type error on archived tables.
% This helper does not call the acquisition entry or modify the formal batch.
options=inputParser;
addParameter(options,'OutputDirectory','');
addParameter(options,'OriginalProject','');
parse(options,varargin{:});
root=fileparts(mfilename('fullpath'));
sourceFolder=canonical(sourceFolder);
original=canonical(options.Results.OriginalProject);
if isempty(original),original=fileparts(root);end
output=canonical(options.Results.OutputDirectory);
if isempty(output)
    output=[tempname 'VCSEL_fprintf_diagnostic'];
end
assert(isfolder(sourceFolder) && isfile(fullfile(sourceFolder,'Protocol.mat')) && ...
    isfile(fullfile(sourceFolder,'tables.mat')), ...
    'DMT:VMFprintfSource','Supply the original formal folder with Protocol.mat and tables.mat.');
assert(~startsWith([output filesep],[sourceFolder filesep],'IgnoreCase',ispc) && ...
    ~isfolder(output) && ~isfile(output), ...
    'DMT:VMFprintfDestination','Choose a fresh destination outside the formal folder.');
assert(isfile(fullfile(original,'verify_dmt_vcsel_mmf_2025.m')) && ...
    isfile(fullfile(original,'private','dmt_vm_graphics_notes.m')), ...
    'DMT:VMFprintfProject','Supply the original acquisition project.');
[ok,message]=mkdir(output);
assert(ok,'DMT:VMFprintfDestination','Unable to create diagnostic folder: %s',message);
logPath=fullfile(output,'matlab_fprintf_diagnostic.log');
fid=fopen(logPath,'wt','n','UTF-8');
assert(fid>=0,'DMT:VMFprintfLog','Cannot open the UTF-8 diagnostic log.');
closeLog=onCleanup(@()fclose(fid)); %#ok<NASGU>
previous=pwd;
restore=onCleanup(@()cd(previous)); %#ok<NASGU>
fprintf(fid,'MATLAB %s\nArchive %s\n',version,sourceFolder);
protocolFile=fullfile(sourceFolder,'Protocol.mat');
tableFile=fullfile(sourceFolder,'tables.mat');
identity={dmt_fb_filehash(protocolFile),dmt_fb_filehash(tableFile)};

cd(original);
fprintf(fid,'\nBase resolution with acquisition root as current folder: %s\n',pwd);
acquisition=baseResolution('run_dmt_vcsel_mmf_2025');
verifier=baseResolution('verify_dmt_vcsel_mmf_2025');
writeResolution(fid,'run_dmt_vcsel_mmf_2025',acquisition);
writeResolution(fid,'verify_dmt_vcsel_mmf_2025',verifier);
expectPath(acquisition,fullfile(original,'run_dmt_vcsel_mmf_2025.m'));
expectPath(verifier,fullfile(original,'verify_dmt_vcsel_mmf_2025.m'));
actual=which('verify_dmt_vcsel_mmf_2025');
expectPath(string(actual),fullfile(original,'verify_dmt_vcsel_mmf_2025.m'));
[verified,rebuilt]=verify_dmt_vcsel_mmf_2025(sourceFolder,false);
assert(verified.valid && verified.data_integrity_valid && verified.acquisition_complete && ...
    strcmp(verified.phase,'formal'), ...
    'DMT:VMFprintfAudit','Original read-only acquisition audit did not pass. %s',verified.detail);
fprintf(fid,'Original read-only acquisition verification: valid=true, source ID %s\n',verified.source_id);

cd(fullfile(original,'private'));
fprintf(fid,'\nBase resolution with original private directory as current folder: %s\n',pwd);
legacy=baseResolution('dmt_vm_graphics_notes');
writeResolution(fid,'dmt_vm_graphics_notes',legacy);
legacyFile=fullfile(original,'private','dmt_vm_graphics_notes.m');
expectPath(legacy,legacyFile);
legacyNotes=evalin('base','@dmt_vm_graphics_notes');
legacyBinding=functions(legacyNotes);
if ~isempty(legacyBinding.file),expectPath(string(legacyBinding.file),legacyFile);end

cd(root);
fprintf(fid,'\nPostprocess caller resolution with patched parent as current folder: %s\n',pwd);
patchedEntry=paths(which('postprocess_dmt_vcsel_mmf_2025','-all'));
patchedNotes=paths(which('dmt_vm_graphics_notes','-all'));
writeResolution(fid,'postprocess_dmt_vcsel_mmf_2025',patchedEntry);
writeResolution(fid,'dmt_vm_graphics_notes',patchedNotes);
expectPath(patchedEntry,fullfile(root,'postprocess_dmt_vcsel_mmf_2025.m'));
patchedFile=fullfile(root,'private','dmt_vm_graphics_notes.m');
expectPath(patchedNotes,patchedFile);
fprintf(fid,'Original helper SHA-256: %s\nPatched helper SHA-256: %s\n', ...
    dmt_fb_filehash(legacyFile),dmt_fb_filehash(patchedFile));

p=load(protocolFile,'checkpoint');
p=p.checkpoint;
m=load(tableFile,'checkpoint');
assert(strcmp(m.checkpoint.source_id,p.source_id) && ...
    strcmp(m.checkpoint.config_id,p.config_id) && strcmp(m.checkpoint.seed_id,p.seed_id) && ...
    strcmp(m.checkpoint.tables_hash,dmt_v13_hash(m.checkpoint.tables)) && ...
    isequaln(m.checkpoint.tables,rebuilt), ...
    'DMT:VMFprintfTableIdentity','Saved formal tables differ from the independently rebuilt tables.');
cfg=p.cfg;
t=m.checkpoint.tables;
legacyStackPath=runOriginalNotes(fid,legacyNotes,legacyFile,fullfile(output,'legacy_notes_probe.md'),cfg,t);

% Rebuild the exact arguments used by the original writeSelectivity line 43.
ref=cfg.representative;
target=t.summary(t.summary.case_id==ref.case_id & t.summary.swing==ref.swing & ...
    t.summary.calibration_id==ref.calibration_id,:);
profiles=t.profiles(t.profiles.case_id==ref.case_id & t.profiles.swing==ref.swing & ...
    t.profiles.calibration_id==ref.calibration_id,:);
assert(height(target)==2);
names=["UniformValidated" "PerToneValidated"];
name="";
for j=1:numel(names)
    row=target(target.strategy==names(j),:);
    profile=profiles(profiles.strategy==names(j),:);
    assert(height(row)==1);
    if isempty(profile),continue;end
    name=names(j);
    [~,i]=min(abs(profile.frequency_GHz-cfg.case2_notch_GHz));
    description=join(compose('%d-QAM',unique(profile.M).'),'、');
    args={name,description,profile.frequency_GHz(i),profile.M(i),row.bits_per_symbol,row.state};
    break;
end
assert(strlength(name)>0,'DMT:VMFprintfProfile','The archived representative point has no usable profile.');
labels={'strategy','description','frequency_GHz','M','bits_per_symbol','state'};
formatSpec=[' %s 使用 %s，陷波最近的活跃载波为 %.2f GHz、%d-QAM，' ...
    '冻结表承载 %d bit/符号，载荷状态为 %s。'];
fprintf(fid,'\nNative argument classes and values from actual tables.mat:\n');
types=cell(1,numel(args));
for j=1:numel(args)
    types{j}=class(args{j});
    printValue(fid,labels{j},args{j});
end

legacyPath=fullfile(output,'legacy_fprintf_probe.txt');
errorID=probeLegacy(fid,legacyPath,formatSpec,args);
fprintf(fid,'Original fprintf reproduction identifier: %s\n',errorID);
if ~isempty(errorID)
    assert(strcmp(errorID,'MATLAB:printf:invalidInputType'), ...
        'DMT:VMFprintfUnexpected','The exact old format failed with unexpected identifier %s.',errorID);
end

notesPath=fullfile(output,'results_zh.md');
dmt_vm_graphics_notes(notesPath,cfg,t);
contents=readUTF8(notesPath);
token='<!-- VCSEL_POSTPROCESS_COMPLETE -->';
assert(endsWith(strtrim(contents),token) && numel(strfind(contents,token))==1 && ...
    all(cellfun(@(word)contains(contents,word),{'Case 1','Case 2','0.25','0.50','47','硬件成本'})), ...
    'DMT:VMFprintfNotes','The patched UTF-8 report is incomplete.');
assert(isequal(identity,{dmt_fb_filehash(protocolFile),dmt_fb_filehash(tableFile)}), ...
    'DMT:VMFprintfArchiveChanged','Original MAT files changed during the read-only diagnosis.');
fprintf(fid,'Patched notes reached the terminal marker. Original MAT hashes are unchanged.\n');
report=struct('original_data_audit_passed',true, ...
    'legacy_error_reproduced',strcmp(errorID,'MATLAB:printf:invalidInputType'), ...
    'legacy_error_identifier',errorID,'argument_names',{labels},'argument_classes',{types}, ...
    'legacy_notes_path',legacy(1),'patched_notes_path',patchedNotes(1), ...
    'legacy_notes_path_at_error',legacyStackPath, ...
    'patched_notes_complete',true,'new_payload_runs',0,'output_dir',output, ...
    'log',logPath,'results_zh',notesPath);
end

function path=runOriginalNotes(log,notes,expected,output,cfg,tables)
path='';
try
    notes(output,cfg,tables);
catch ME
    fprintf(log,'\nOriginal report helper stack:\n%s\n',getReport(ME,'extended','hyperlinks','off'));
    match=contains(string({ME.stack.name}),'writeSelectivity') & [ME.stack.line]==43;
    assert(strcmp(ME.identifier,'MATLAB:printf:invalidInputType') && nnz(match)==1, ...
        'DMT:VMFprintfUnexpected','Original helper did not produce the archived line-43 failure.');
    path=ME.stack(match).file;
    expectPath(string(path),expected);
    fprintf(log,'Path at the original fprintf exception: %s\n',path);
end
if isempty(path),fprintf(log,'Original report helper returned without the archived exception.\n');end
end

function found=baseResolution(name)
% The caller supplies only literal MATLAB identifiers, never user input.
assert(~isempty(regexp(name,'^[a-zA-Z]\w*$','once')));
found=paths(evalin('base',sprintf('which(''%s'',''-all'')',name)));
end

function found=paths(raw)
if isempty(raw)
    found=strings(0,1);
else
    if ischar(raw),raw=cellstr(raw);end
    found=string(raw(:));
end
end

function writeResolution(fid,name,found)
fprintf(fid,'which -all %s\n',name);
for j=1:numel(found),fprintf(fid,'  %s\n',char(found(j)));end
end

function expectPath(found,expected)
assert(~isempty(found),'DMT:VMFprintfResolution','MATLAB could not resolve %s.',expected);
actual=canonical(found(1));
expected=canonical(expected);
assert(strcmp(actual,expected) || (ispc && strcmpi(actual,expected)), ...
    'DMT:VMFprintfResolution','Expected %s, but MATLAB picked %s.',expected,actual);
end

function printValue(fid,label,value)
fprintf(fid,'  %s: class=%s, size=%s, iscell=%d\n',label,class(value), ...
    mat2str(size(value)),iscell(value));
if iscell(value)
    for j=1:numel(value)
        printValue(fid,sprintf('%s{%d}',label,j),value{j});
    end
elseif isnumeric(value) || islogical(value)
    fprintf(fid,'    %s\n',mat2str(value,17));
elseif (isstring(value)&&isscalar(value)) || (ischar(value)&&isrow(value))
    fprintf(fid,'    %s\n',char(value));
else
    fprintf(fid,'    %s\n',evalc('disp(value)'));
end
end

function id=probeLegacy(log,output,formatSpec,args)
fid=fopen(output,'wt','n','UTF-8');
assert(fid>=0,'DMT:VMFprintfProbe','Cannot create legacy probe output.');
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
id='';
try
    fprintf(fid,formatSpec,args{:});
catch ME
    id=ME.identifier;
    fprintf(log,'%s\n',getReport(ME,'extended','hyperlinks','off'));
end
end

function text=readUTF8(path)
fid=fopen(path,'rb');
assert(fid>=0,'DMT:VMFprintfNotes','Cannot read patched Chinese text.');
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
bytes=fread(fid,Inf,'*uint8').';
text=native2unicode(bytes,'UTF-8');
assert(isequal(unicode2native(text,'UTF-8'),bytes), ...
    'DMT:VMFprintfNotes','The patched report does not round-trip as UTF-8.');
end

function result=canonical(path)
result=char(string(path));
if ~isempty(result)
    file=java.io.File(result);
    result=char(file.getCanonicalPath());
end
end
