function result=redraw_dmt_tradeoff(resultDirectory,varargin)
%REDRAW_DMT_TRADEOFF Read saved counters only; never transmits new symbols.
% All exports go into a new redraw directory. Original checkpoints, tables,
% figures and protocol are not overwritten. Incomplete-but-valid records may
% be redrawn, retaining every incomplete/rejected/scientific state.
parser=inputParser;
isText=@(x)ischar(x)||(isstring(x)&&isscalar(x));
addRequired(parser,'resultDirectory',isText);
addParameter(parser,'Phase','formal',isText);
parse(parser,resultDirectory,varargin{:});
sourceDir=char(parser.Results.resultDirectory);
phase=validatestring(char(parser.Results.Phase),{'preflight','formal'});
assert(isfolder(sourceDir),'DMT:TradeoffRedrawDirectory', ...
    'Supply an existing tradeoff result directory.');
canonical=java.io.File(sourceDir);sourceDir=char(canonical.getCanonicalPath());
statePath=fullfile(sourceDir,'study_state.mat');
assert(isfile(statePath),'DMT:TradeoffRedrawState','Missing original study_state.mat.');
loaded=load(statePath,'checkpoint');
assert(isfield(loaded,'checkpoint'),'DMT:TradeoffRedrawState','Incomplete original study state.');
state=loaded.checkpoint;
required={'cfg','config_id','source_id','source_manifest','formal_plan','preflight_plan'};
assert(isstruct(state) && isscalar(state) && all(isfield(state,required)), ...
    'DMT:TradeoffRedrawState','Missing original configuration/source/seed identities.');
cfg=state.cfg;
assert(strcmp(cfg.protocol,'tradeoff_v1') && ...
    strcmp(state.config_id,dmt_v13_hash(cfg)), ...
    'DMT:TradeoffRedrawIdentity','Original scientific configuration identity differs.');
phaseDir=fullfile(sourceDir,phase);
assert(isfolder(phaseDir),'DMT:TradeoffRedrawPhase', ...
    'No saved %s phase. Use Phase=preflight explicitly for preflight-only records.',phase);
report=verify_dmt_tradeoff(sourceDir,'WriteReport',false,'Phase',phase);
assert(isstruct(report) && isfield(report,'data_integrity_valid') && ...
    report.data_integrity_valid,'DMT:TradeoffRedrawIntegrity', ...
    'Saved data failed independent integrity checks; no redraw was created.');

plan=state.formal_plan;
if strcmp(phase,'preflight'),plan=state.preflight_plan;end
meta=dmt_to_meta(state,phase);
assert(strcmp(meta.config_id,state.config_id) && strcmp(meta.source_id,state.source_id) && ...
    strcmp(meta.phase,phase) && strcmp(meta.seed_id,dmt_v13_hash(plan)), ...
    'DMT:TradeoffRedrawIdentity','Phase identities do not match the saved original plan.');
[shared,designs,runs]=dmt_to_collect(sourceDir,phase,cfg,meta,plan);
tables=dmt_to_tables(cfg,phase,plan,shared,designs,runs);

tag=char(datetime('now','TimeZone','UTC','Format','yyyyMMdd_HHmmss_SSS'));
[~,uniqueTag]=fileparts(tempname(sourceDir));
outDir=fullfile(sourceDir,['redraw_' tag '_' uniqueTag]);
assert(~isfolder(outDir),'DMT:TradeoffRedrawCollision','New redraw directory already exists.');
mkdir(outDir);
provenance=struct('source_directory',sourceDir,'phase',phase, ...
    'created_utc',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss.SSS Z')), ...
    'config_id',meta.config_id,'source_id',meta.source_id,'seed_id',meta.seed_id, ...
    'read_only_source',true,'new_training_or_payload_symbols',0, ...
    'note','Read-only counter reconstruction. Scope and scientific states remain in the exported tables.');
save(fullfile(outDir,'redraw_provenance.mat'),'provenance','cfg','meta','plan');
fid=fopen(fullfile(outDir,'redraw_provenance.json'),'w','n','UTF-8');
assert(fid>=0,'DMT:TradeoffRedrawWrite','Cannot write redraw provenance.');
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(provenance));
clear cleanup;
dmt_to_export(cfg,tables,outDir,phase);
manifest=dmt_to_plot(cfg,tables,outDir);
save(fullfile(outDir,'redraw_tables.mat'),'tables','provenance','manifest');
result=struct('source_directory',sourceDir,'phase',phase,'output_dir',outDir, ...
    'data_integrity_valid',true,'new_training_or_payload_symbols',0,'manifest',manifest);
fprintf('Read-only %s redraw: %s\n',phase,outDir);
end
