function report = redraw_dmt_constraint_check(referenceDir)
%REDRAW_DMT_CONSTRAINT_CHECK Replot verified reference 0 without new samples.
% All three panels use the same preselected completed v1.1 calibration.
% No input file, historical graph, report or count is overwritten.
if nargin~=1 || ~(ischar(referenceDir) || (isstring(referenceDir) && isscalar(referenceDir)))
    error('DMT:ReferenceRequired','Supply the completed reference-calibration-0 main directory.');
end
referenceDir = char(referenceDir);
assert(isfolder(referenceDir),'DMT:MissingReference','Reference main directory not found: %s',referenceDir);
referenceFile = java.io.File(referenceDir);
referenceDir = char(referenceFile.getCanonicalPath());
before = inputManifest(referenceDir);
verification = verify_main_results(referenceDir);
data = load(fullfile(referenceDir,'final_results.mat'), ...
    'cfg','calibration','profiles','pooled','summary','integrity','calibrationProvenance');
referenceCfg = data.cfg;
assert(strcmp(referenceCfg.runMode,'main') && verification.completed_groups==9);
projectDir = fileparts(mfilename('fullpath'));
resultsRoot = fullfile(projectDir,'results');
rootFile = java.io.File(resultsRoot);
canonicalResultsRoot = char(rootFile.getCanonicalPath());
assert(~strcmp(canonicalResultsRoot,referenceDir) && ...
    ~startsWith(canonicalResultsRoot,[referenceDir filesep],'IgnoreCase',ispc), ...
    'DMT:ReferenceOutputOverlap','Output root must be outside the original reference directory.');
if ~isfolder(resultsRoot)
    mkdir(resultsRoot);
end
[~,tag] = fileparts(tempname(resultsRoot));
stamp = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
outDir = fullfile(resultsRoot,['v1_2_reference_0_' stamp '_' tag]);
candidateFile = java.io.File(outDir);
candidate = char(candidateFile.getCanonicalPath());
assert(~strcmp(candidate,referenceDir) && ...
    ~startsWith(candidate,[referenceDir filesep],'IgnoreCase',ispc), ...
    'DMT:ReferenceOutputOverlap','Redraw output must be outside the old reference directory.');
mkdir(outDir);
diary(fullfile(outDir,'run.log'));
cleanup = onCleanup(@() diary('off')); %#ok<NASGU>
fprintf('Task A only: verified reference calibration 0; no new payload samples.\n');
fprintf('Reference directory: %s\nNew output directory: %s\n',referenceDir,outDir);
try
    [sourceManifest,sourceID] = dmt_source_manifest(projectDir);
    writetable(sourceManifest,fullfile(outDir,'source_manifest.csv'));
    writetable(before,fullfile(outDir,'input_manifest.csv'));
    copyfile(fullfile(projectDir,'docs','literature_mapping.md'),fullfile(outDir,'literature_mapping.md'));
    copyfile(fullfile(projectDir,'docs','literature_access.json'),fullfile(outDir,'literature_access.json'));
    inputID = manifestID(before);
    cfg = struct('protocolVersion','1.2','specVersion','1.0','calibration_id',0, ...
        'runMode','reference_redraw_only','reference_directory',referenceDir, ...
        'reference_initialization_id',referenceCfg.initializationID, ...
        'reference_source_manifest_id',referenceCfg.sourceManifestID, ...
        'source_manifest_id',sourceID,'input_manifest_id',inputID, ...
        'command',sprintf('redraw_dmt_constraint_check(''%s'')',strrep(referenceDir,'''','''''')), ...
        'MATLABVersion',version,'MATLABRelease',version('-release'), ...
        'started_utc',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss Z')));
    save(fullfile(outDir,'config_snapshot.mat'),'cfg','referenceCfg','verification');
    rows = dmt_plot_constraint_check(referenceCfg,data.calibration,data.profiles,data.pooled,outDir);
    writetable(rows,fullfile(outDir,'constraint_check.csv'));
    referenceSummary = data.summary;
    referenceSummary.calibration_id = zeros(height(referenceSummary),1);
    referenceSummary.max_CI_upper_over_target = zeros(height(referenceSummary),1);
    referenceSummary.reference_status = repmat("inconclusive",height(referenceSummary),1);
    for s = 1:height(referenceSummary)
        one = rows(rows.scheme==string(referenceSummary.scheme(s)),:);
        referenceSummary.max_CI_upper_over_target(s) = max(one.CI_upper_over_target);
        if any(one.CI_low>referenceCfg.targetBER)
            referenceSummary.reference_status(s) = "failed";
        elseif all(one.CI_high<referenceCfg.targetBER)
            referenceSummary.reference_status(s) = "supported";
        end
    end
    writetable(referenceSummary,fullfile(outDir,'reference_summary.csv'));
    writeReferenceNotes(outDir,referenceCfg,referenceSummary,rows);
    after = inputManifest(referenceDir);
    assert(isequal(before,after),'DMT:ReferenceChanged', ...
        'Reference inputs changed during redraw; do not accept the figure.');
    writetable(after,fullfile(outDir,'input_manifest_after.csv'));
    fid = fopen(fullfile(outDir,'completion_check.txt'),'w','n','UTF-8');
    assert(fid>=0);
    closeFile = onCleanup(@() fclose(fid));
    fprintf(fid,'PASS | verified existing formal main groups | observed=%d | expected=9 | tolerance=0\n', ...
        verification.completed_groups);
    fprintf(fid,'PASS | constraint table rows | observed=%d | expected=72 | tolerance=0\n',height(rows));
    fprintf(fid,'PASS | all panels reference calibration id | observed=0 | expected=0 | tolerance=0\n');
    fprintf(fid,'PASS | new payload groups in redraw | observed=0 | expected=0 | tolerance=0\n');
    fprintf(fid,'PASS | original reference file bytes and paths unchanged | observed=1 | expected=1 | tolerance=0\n');
    fprintf(fid,'Input manifest SHA-256: %s\n',inputID);
    fprintf(fid,'Reference initialization id: %s\n',referenceCfg.initializationID);
    clear closeFile;
    save(fullfile(outDir,'redraw_results.mat'),'cfg','referenceCfg','rows','referenceSummary', ...
        'verification','sourceManifest','before','after');
    report = struct('output_dir',outDir,'reference_directory',referenceDir, ...
        'calibration_id',0,'new_payload_groups',0,'status','reference_redraw_complete', ...
        'summary',referenceSummary);
    fprintf('Completed reference-0 redraw. All original reference files retained.\n');
    disp(referenceSummary(:,{'scheme','B','R_payload','total_BER','max_CI_upper_over_target','reference_status'}));
catch ME
    fid = fopen(fullfile(outDir,'failure_status.txt'),'w','n','UTF-8');
    if fid>=0
        fprintf(fid,'Reference redraw did not complete. No new payload samples were generated.\n');
        fprintf(fid,'%s\n',getReport(ME,'extended','hyperlinks','off'));
        fclose(fid);
    end
    rethrow(ME);
end
end

function manifest = inputManifest(root)
manifest = dmt_input_manifest(root);
end

function id = manifestID(manifest)
id = dmt_sha256(join(manifest.relative_path+" "+manifest.sha256,newline));
end

function writeReferenceNotes(outDir,cfg,summary,rows)
caption = ['Figure 2. Author''s simplified electrical-baseband DMT simulation, using the preselected reference calibration 0 ' ...
    'in all panels: (a) independent-probe electrical symbol SNR (analytical FIR curve for diagnosis only); ' ...
    '(b) bit allocation at equal mean electrical symbol energy; ' ...
    '(c) the pointwise 95% Wilson approximate upper endpoint divided by the BER target. ' ...
    'Values below 1 meet the upper-endpoint criterion; values at or above 1 do not by themselves establish a true BER violation. ' ...
    'Zero-error points use their nonzero upper endpoints. These are pointwise intervals, not simultaneous 95% coverage.'];
writeText(fullfile(outDir,'figure_caption_en.txt'),caption);
u = find(string(summary.scheme)=="Uniform",1);
l = find(string(summary.scheme)=="Loaded",1);
f = find(string(summary.scheme)=="Fixed16",1);
assert(all([numel(u) numel(l) numel(f)]==1));
fixedFailed = rows.k(rows.scheme=="Fixed16" & rows.CI_low>cfg.targetBER).';
lines = ["# Reference calibration 0：Figure 2 重绘"; ""; ...
    "本目录只重用已经验证的reference 0正式main计数，不产生新样本。图(a)(b)(c)共享同一校准、质量估计和profile；未从新增重复轮次挑选有利数据。"; ...
    "(c)每个点统一为逐点95% Wilson近似区间的上端点除以目标BER，判据线为1。它不是Observed BER图；不能用该比值判断哪个策略真实BER更低。"; ...
    "u<1仅说明通过该上端点判据，不保证真实BER必然低于目标；u>=1尚未通过。只有CI_low>target才能报告该子载波有区间证据超过目标；区间跨线应写证据不足。"; ...
    "零误码平台使用实际非零区间上端点，主要受测试比特数影响，不表示各子载波的真实BER相同。区间是常用二项逐点近似，不是全部子载波联合95%保证。"; ""];
for s = 1:height(summary)
    one = summary(s,:);
    lines(end+1) = string(sprintf(['%s：B=%g bits/DMT symbol，R_payload=%.9g bit/s，' ...
        '观察总BER=%.9g，max(CI_high/target)=%.9g，reference状态=%s。'], ...
        char(string(one.scheme)),one.B,one.R_payload,one.total_BER, ...
        one.max_CI_upper_over_target,char(one.reference_status))); %#ok<AGROW>
end
lines = [lines; ""; "Fixed16只有在保存计数的CI_low>target时才被图中文字标作超标。对应k="+string(mat2str(fixedFailed))+"。"; ...
    "Loaded用更密集星座交换误码余量与承载量，不要求BER比Uniform低。载荷速率已计CP时间，未扣初始化、反馈和FEC，不能称完整净吞吐量。"; ...
    "这是作者的简化电域DMT模型，固定教学FIR，不代表光器件、实测响应、100 Gb/s硬件实验或完整Chow算法。原完整BER+区间图保留于reference目录，没有覆盖。"; ...
    "本目录没有新增10轮校准统计，不能把重绘状态当成90组实验完成。跨校准结果由独立study目录报告。"];
writeText(fullfile(outDir,'report_notes_zh.md'),join(lines,newline));
paragraph = sprintf(['The author''s simplified DMT electrical-baseband simulation is shown using the preselected reference calibration 0. ' ...
    'All three panels share its independently estimated channel, probe quality, frozen profiles, and completed formal counts; no new samples are generated by this redraw. ' ...
    'Uniform, Loaded, and diagnostic Fixed16 carry %g, %g, and %g bits per DMT symbol, with payload rates of %.6g, %.6g, and %.6g Mbit/s, respectively. ' ...
    'Their observed bit-weighted BERs are %.6g, %.6g, and %.6g. ' ...
    'Panel (c) consistently plots the pointwise Wilson upper endpoint divided by the BER target, with maxima %.6g, %.6g, and %.6g. ' ...
    'A value below one meets this endpoint criterion; a larger value alone does not establish a true target violation. ' ...
    'Zero-error points retain their nonzero upper limits, and pointwise approximate intervals provide no simultaneous 95%% coverage guarantee. ' ...
    'Rates include cyclic-prefix time but exclude initialization, feedback, and FEC. This fixed electrical FIR model does not establish optical-hardware performance or robustness across physical channels. ' ...
    'New independent-calibration experiments are reported separately and are not inferred from this reference figure.'], ...
    summary.B(u),summary.B(l),summary.B(f),summary.R_payload(u)/1e6, ...
    summary.R_payload(l)/1e6,summary.R_payload(f)/1e6,summary.total_BER(u), ...
    summary.total_BER(l),summary.total_BER(f),summary.max_CI_upper_over_target(u), ...
    summary.max_CI_upper_over_target(l),summary.max_CI_upper_over_target(f));
wordCount = numel(regexp(strtrim(paragraph),'\s+','split'));
assert(wordCount>=150 && wordCount<=220,'DMT:ParagraphLength', ...
    'Reference-only paragraph has %d words; expected 150--220.',wordCount);
writeText(fullfile(outDir,'reference_results_paragraph_en.txt'),paragraph);
end

function writeText(path,text)
fid = fopen(path,'w','n','UTF-8');
assert(fid>=0,'DMT:OutputWrite','Cannot write %s',path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',char(text));
end
