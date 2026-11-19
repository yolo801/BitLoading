function report = postprocess_dmt_vcsel_mmf_2025(sourceFolder,varargin)
%POSTPROCESS_DMT_VCSEL_MMF_2025 Reaudit and render the archived formal run.
% The acquisition verifier runs from its original, fingerprinted tree.
args=inputParser;
addParameter(args,'Mode','draw');
addParameter(args,'OutputDirectory','');
addParameter(args,'OriginalProject','');
parse(args,varargin{:});
options=args.Results;
mode=validatestring(options.Mode,{'draw','verify'});
root=fileparts(mfilename('fullpath'));
sourceFolder=canonical(sourceFolder);
originalFolder=canonical(options.OriginalProject);
if isempty(originalFolder),originalFolder=fileparts(root);end
outputFolder=canonical(options.OutputDirectory);
if isempty(outputFolder)
    assert(strcmp(mode,'draw'),'DMT:VMPostDestination','Verify requires an existing OutputDirectory.');
    [parent,study]=fileparts(sourceFolder);
    [~,tag]=fileparts(tempname(parent));
    outputFolder=fullfile(parent,[study '_postprocess_' tag]);
end
assert(isfolder(sourceFolder) && isfile(fullfile(sourceFolder,'Protocol.mat')), ...
    'DMT:VMPostSource','Supply the formal folder containing the original Protocol.mat.');
assert(~startsWith([outputFolder filesep],[sourceFolder filesep],'IgnoreCase',ispc), ...
    'DMT:VMPostDestination','Output must be outside the original result folder.');
assert((strcmp(mode,'draw') && ~isfolder(outputFolder) && ~isfile(outputFolder)) || ...
    (strcmp(mode,'verify') && isfolder(outputFolder)), ...
    'DMT:VMPostDestination','Draw requires a fresh output folder, verify an existing one.');

[manifest,sourceID]=dmt_source_manifest(root);
before=fileInventory(sourceFolder);
[original,tables]=auditOriginal(originalFolder,sourceFolder);
assert(original.valid && original.data_integrity_valid && original.acquisition_complete && ...
    strcmp(original.phase,'formal'), ...
    'DMT:VMPostOriginalAudit','Original acquisition audit did not pass. %s',original.detail);
saved=load(fullfile(sourceFolder,'Protocol.mat'),'checkpoint');
cfg=saved.checkpoint.cfg;
counts=batchCounts(original,tables,cfg);
assert(isequaln(fileInventory(sourceFolder),before), ...
    'DMT:VMPostSourceChanged','Original evidence changed during the acquisition audit.');
identity=struct('version','vcsel_mmf_2025_postprocess_v1_1','source_id',sourceID, ...
    'source_manifest',manifest,'original_source_id',original.source_id, ...
    'original_config_id',original.config_id,'original_artifact_manifest',before, ...
    'audited_tables_hash',dmt_v13_hash(tables),'counts',counts);

if strcmp(mode,'draw')
    [ok,message]=mkdir(outputFolder);
    assert(ok,'DMT:VMPostDestination','Cannot create output folder: %s',message);
    dmt_v13_atomic_save(fullfile(outputFolder,'PostprocessProtocol.mat'),identity);
    dmt_v13_atomic_save(fullfile(outputFolder,'original_data_audit_receipt.mat'),original);
    writetable(before,fullfile(outputFolder,'original_input_manifest.csv'),'Encoding','UTF-8');
    writetable(manifest,fullfile(outputFolder,'postprocess_source_manifest.csv'),'Encoding','UTF-8');
    exportTables(outputFolder,tables,true);
    dmt_vm_graphics(outputFolder,cfg,tables,'draw');
else
    saved=load(fullfile(outputFolder,'PostprocessProtocol.mat'),'checkpoint');
    assert(isequaln(saved.checkpoint,identity),'DMT:VMPostIdentity', ...
        'The original evidence, reconstructed tables or postprocess source differs.');
    archived=load(fullfile(outputFolder,'original_data_audit_receipt.mat'),'checkpoint');
    assert(isequaln(rmfield(archived.checkpoint,'output_dir'),rmfield(original,'output_dir')), ...
        'DMT:VMPostReceipt','The archived acquisition audit differs from the current audit.');
end

dmt_fb_audit_csv(fullfile(outputFolder,'original_input_manifest.csv'),before);
dmt_fb_audit_csv(fullfile(outputFolder,'postprocess_source_manifest.csv'),manifest);
exportTables(outputFolder,tables,false);
figures=dmt_vm_graphics(outputFolder,cfg,tables,'verify');
checkNotes(fullfile(outputFolder,'results_zh.md'),counts);
[~,currentID]=dmt_source_manifest(root);
assert(strcmp(currentID,sourceID) && isequaln(fileInventory(sourceFolder),before), ...
    'DMT:VMPostSourceChanged','Input or postprocess source changed during export.');
artifacts=fileInventory(outputFolder);
artifacts(ismember(artifacts.relative_path,["postprocess_verification_receipt.mat", ...
    "postprocess_verification_receipt.json"]),:)=[];
report=struct('valid',true,'original_data_integrity_valid',true, ...
    'original_acquisition_complete',true,'new_exports_valid',true, ...
    'original_figures_audited',false,'new_payload_runs',0,'counts',counts, ...
    'original_source_id',original.source_id,'original_config_id',original.config_id, ...
    'postprocess_version',identity.version,'postprocess_source_id',sourceID, ...
    'output_dir',outputFolder,'original_dir',sourceFolder,'artifacts',artifacts,'figure_manifest',figures);
if strcmp(mode,'draw')
    dmt_v13_atomic_save(fullfile(outputFolder,'postprocess_verification_receipt.mat'),report);
    jsonReport=rmfield(report,{'artifacts','figure_manifest'});
    writeText(fullfile(outputFolder,'postprocess_verification_receipt.json'),jsonencode(jsonReport,'PrettyPrint',true));
else
    saved=load(fullfile(outputFolder,'postprocess_verification_receipt.mat'),'checkpoint');
    assert(isequaln(saved.checkpoint.artifacts,artifacts) && ...
        isequaln(saved.checkpoint.counts,counts) && ...
        strcmp(saved.checkpoint.original_source_id,original.source_id) && ...
        strcmp(saved.checkpoint.postprocess_source_id,sourceID) && ...
        isequaln(saved.checkpoint.figure_manifest,figures), ...
        'DMT:VMPostReceipt','Saved artifact hashes or verification results differ.');
end
end

function [report,tables]=auditOriginal(project,sourceFolder)
expected=fullfile(project,'verify_dmt_vcsel_mmf_2025.m');
assert(isfile(expected),'DMT:VMPostOriginalProject','Supply the original acquisition project root.');
previous=pwd;
cd(project);
restore=onCleanup(@()cd(previous)); %#ok<NASGU>
actual=which('verify_dmt_vcsel_mmf_2025');
assert(strcmp(canonical(actual),canonical(expected)) || ...
    (ispc && strcmpi(canonical(actual),canonical(expected))), ...
    'DMT:VMPostOriginalProject','Unexpected original verifier path: %s',actual);
[report,tables]=verify_dmt_vcsel_mmf_2025(sourceFolder,false);
end

function counts=batchCounts(r,t,cfg)
expected=[120 100 20 0 0 0];
state=string(t.status.status);
assert(isequal([r.planned r.completed r.design_rejected r.incomplete r.power_error r.execution_error],expected) && ...
    height(t.status)==120 && sum(state=="completed")==100 && sum(state=="design_rejected")==20, ...
    'DMT:VMPostBatch','This repair expects the 120-slot archived formal batch.');
sent=state=="completed";
assert(all(t.status.actual_symbols(sent)==cfg.payload_symbols) && ...
    all(isnan(t.status.actual_symbols(~sent))) && all(isnan(t.status.error_bits(~sent))) && ...
    all(isnan(t.status.tested_bits(~sent))) && height(t.power_adc)==100, ...
    'DMT:VMPostBatch','Completed or normally rejected slots have invalid counters.');
samples=sum(t.power_adc.samples);
clip=sum(t.power_adc.tx_low_count+t.power_adc.tx_high_count);
assert(samples==1320000000 && clip==47 && ...
    samples==sum(t.status.actual_symbols(sent))*(cfg.NFFT+cfg.NCP), ...
    'DMT:VMPostBatch','The archived payload sample or clipping count differs.');
counts=struct('planned',r.planned,'completed',r.completed,'design_rejected',r.design_rejected, ...
    'incomplete',r.incomplete,'power_error',r.power_error,'execution_error',r.execution_error, ...
    'payload_samples',samples,'tx_clipped_samples',clip);
end

function exportTables(folder,tables,write)
for field=fieldnames(tables).'
    name=field{1};
    path=fullfile(folder,[name '.csv']);
    if write
        writetable(tables.(name),path,'Delimiter',',','Encoding','UTF-8');
    else
        dmt_fb_audit_csv(path,tables.(name));
    end
end
end

function checkNotes(path,counts)
fid=fopen(path,'rt','n','UTF-8');
assert(fid>=0,'DMT:VMPostNotes','Cannot read exported Chinese results.');
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
contents=fscanf(fid,'%c');
marker='<!-- VCSEL_POSTPROCESS_COMPLETE -->';
required={'Case 1','Case 2','0.25','0.50',num2str(counts.tx_clipped_samples),'硬件成本'};
assert(endsWith(strtrim(contents),marker) && numel(strfind(contents,marker))==1 && ...
    all(cellfun(@(item)contains(contents,item),required)), ...
    'DMT:VMPostNotes','Chinese report is incomplete or lacks batch-specific evidence.');
end

function manifest=fileInventory(folder)
files=dir(fullfile(folder,'**','*'));
files=files(~[files.isdir]);
names=strings(numel(files),1);
hashes=names;
bytes=zeros(numel(files),1);
for j=1:numel(files)
    path=fullfile(files(j).folder,files(j).name);
    names(j)=strrep(path(numel(folder)+2:end),filesep,'/');
    hashes(j)=dmt_fb_filehash(path);
    bytes(j)=files(j).bytes;
end
manifest=sortrows(table(names,hashes,bytes,'VariableNames',{'relative_path','sha256','bytes'}),'relative_path');
end

function writeText(path,text)
fid=fopen(path,'wt','n','UTF-8');
assert(fid>=0,'DMT:VMPostReceipt','Cannot write receipt: %s',path);
closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',text);
end

function path=canonical(path)
path=char(string(path));
if ~isempty(path)
    file=java.io.File(path);
    path=char(file.getCanonicalPath());
end
end
