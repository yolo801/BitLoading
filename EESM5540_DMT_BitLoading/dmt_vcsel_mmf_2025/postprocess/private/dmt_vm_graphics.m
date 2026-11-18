function manifest=dmt_vm_graphics(folder,cfg,tables,action)
%DMT_VM_GRAPHICS Export and audit the two formal figures, without acquisition.
if nargin<4,action='draw';end
action=validatestring(action,{'draw','verify'});
rate=struct('scenario',tables.scenario,'summary',tables.summary, ...
    'pairs',tables.pair_gains,'overhead',tables.overhead,'payload_symbols',cfg.payload_symbols, ...
    'representative',cfg.representative,'k',cfg.k(:));
subcarrier=representative(cfg,tables);
stems=["fig_A_qualified_cycle_rate";"fig_B_frequency_selectivity"];
png=stems+".png";
pdf=stems+".pdf";
dataHash=string({dmt_v13_hash(rate);dmt_v13_hash(subcarrier)});
paths=["figure_captions_en.txt";"results_zh.md"];
if strcmp(action,'draw')
    if ~isfolder(folder),mkdir(folder);end
    exportFigure(folder,png(1),pdf(1),@dmt_vm_graphics_rate,rate,[11.2 7.4]);
    exportFigure(folder,png(2),pdf(2),@dmt_vm_graphics_subcarrier,subcarrier,[9.5 7.4]);
    writeCaptions(fullfile(folder,paths(1)),cfg);
    dmt_vm_graphics_notes(fullfile(folder,paths(2)),cfg,tables);
end
manifest=table(stems,png,pdf,dataHash,pathHashes(folder,png),pathHashes(folder,pdf), ...
    'VariableNames',{'figure','png_file','pdf_file','data_sha256','png_sha256','pdf_sha256'});
reports=table(paths,pathHashes(folder,paths),'VariableNames',{'report_file','sha256'});
publishManifest(fullfile(folder,'report_manifest.csv'),reports,action);
publishManifest(fullfile(folder,'figure_manifest.csv'),manifest,action);
end

function data=representative(cfg,tables)
ref=cfg.representative;
assert(isequal([ref.case_id ref.swing ref.q ref.calibration_id],[2 .5 8 1]), ...
    'DMT:VMFigurePoint','Fig. B uses the predeclared Case 2 medium-drive calibration.');
assert(isfinite(cfg.case2_notch_GHz),'DMT:VMFigureNotch','The supported Case 2 notch reference is required.');
data=struct('frequency_GHz',cfg.k(:)*cfg.Fs/cfg.NFFT/1e9, ...
    'targetBER',cfg.targetBER,'notch_GHz',cfg.case2_notch_GHz,'ref',ref, ...
    'snr',sortrows(select(tables.snr,ref),'k'),'profile',{{[],[]}}, ...
    'pool',{{[],[]}},'state',strings(1,2));
assert(isequal(data.snr.k,cfg.k(:)) && ...
    all(abs(data.snr.frequency_GHz-data.frequency_GHz)<1e-10), ...
    'DMT:VMFigureProbe','The representative probe must cover the common active band.');
assert(data.notch_GHz>=min(data.frequency_GHz) && data.notch_GHz<=max(data.frequency_GHz));
summary=select(tables.summary,ref);
profile=select(tables.profiles,ref);
pool=select(tables.pool,ref);
keys=["UniformValidated" "PerToneValidated"];
for j=1:numel(keys)
    row=summary(summary.strategy==keys(j),:);
    assert(height(row)==1,'DMT:VMFigurePoint','Representative calibration summary is absent.');
    state=string(row.state);
    assert(isscalar(state) && ~ismissing(state) && strlength(state)>0, ...
        'DMT:VMFigurePoint','Representative state must be a scalar text value.');
    data.state(j)=state;
    data.profile{j}=sortrows(profile(profile.strategy==keys(j),:),'k');
    data.pool{j}=sortrows(pool(pool.strategy==keys(j),:),'k');
end
end

function t=select(t,ref)
t=t(t.case_id==ref.case_id & t.swing==ref.swing & t.calibration_id==ref.calibration_id,:);
end

function exportFigure(folder,png,pdf,draw,data,dims)
fig=figure('Visible','off','Color','white','Units','inches','Position',[1 1 dims], ...
    'InvertHardcopy','off','PaperPositionMode','auto');
closeFigure=onCleanup(@()close(fig)); %#ok<NASGU>
draw(fig,data);
exportgraphics(fig,fullfile(folder,png),'Resolution',300,'BackgroundColor','white');
exportgraphics(fig,fullfile(folder,pdf),'ContentType','vector','BackgroundColor','white');
end

function publishManifest(path,expected,action)
if strcmp(action,'draw')
    writetable(expected,path,'Delimiter',',','Encoding','UTF-8');
else
    dmt_fb_audit_csv(path,expected);
end
end

function hashes=pathHashes(folder,files)
hashes=strings(size(files));
for j=1:numel(files)
    path=fullfile(folder,files(j));
    details=dir(path);
    assert(isscalar(details) && details.bytes>0,'DMT:VMFigureArtifact', ...
        'Missing or empty report artifact: %s.',path);
    hashes(j)=string(dmt_fb_filehash(path));
end
end

function writeCaptions(path,cfg)
fid=fopen(path,'wt','n','UTF-8');
assert(fid>=0,'DMT:VMFigureCaption','Cannot write English figure captions.');
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,['Fig. A. Payload and setup accounting for both normalized 50 m ' ...
    'VCSEL–MMF model responses (A. M. Rosa Brusin et al., SPPCom 2025, ' ...
    'doi:10.1364/SPPCOM.2025.SpTh3E.4). Bit capacity and nominal payload rate use ' ...
    'the frozen profiles of transmitted rounds. Qualified cycle rates require all ' ...
    'five calibrations to pass and include the observed forward setup for L = %d. ' ...
    'A strategy''s nominal-to-cycle rate difference shows its setup overhead. The ' ...
    'difference in bits per DMT symbol between strategies shows the allocation gain. ' ...
    'The bottom panels use actual setup time and candidate validation counts, including ' ...
    'performed attempts for rejected designs. Shaded points highlight Case 1 at 0.25 ' ...
    'and Case 2 at 0.50. Attempt counts reflect the validation rules and this batch.\n\n'], ...
    cfg.payload_symbols);
fprintf(fid,['Fig. B. Shared probe SNR, frozen bit allocation and observed payload BER over ' ...
    'the common active band of Case 2 at commanded swing %.2f, %d-bit ADC, calibration %d. ' ...
    'The notch marker comes from the public 50 m magnitude curve. Error bars are approximate ' ...
    'pointwise 95%% Wilson intervals from the two payload slots within this calibration. ' ...
    'Downward triangles locate the upper bounds for zero observed errors. ' ...
    'Missing payload data are identified by their acquisition or rejection status.\n'], ...
    cfg.representative.swing,cfg.representative.q,cfg.representative.calibration_id);
end
