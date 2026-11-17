function output = dmt_write_study_summary(cfg, rounds, runs, outDir)
%DMT_WRITE_STUDY_SUMMARY Export actual v1.2 counts without cross-profile CIs.
% Called after checkpoints or completion; missing groups remain missing.
assert(isfolder(outDir),'DMT:StudyOutputDirectory','Output directory must exist.');
[seed,pooled,summary,frequency,robustness] = dmt_study_tables(cfg,rounds,runs);
writetable(seed,fullfile(outDir,'per_calibration_seed.csv'));
writetable(pooled,fullfile(outDir,'per_calibration_pooled.csv'));
writetable(summary,fullfile(outDir,'per_calibration_summary.csv'));
writetable(frequency,fullfile(outDir,'profile_frequency.csv'));
writetable(robustness,fullfile(outDir,'robustness_summary.csv'));
profileRows = profileTable(cfg,rounds);
writetable(profileRows,fullfile(outDir,'per_calibration_profile.csv'));
plannedGroups = 9*cfg.NumCalibrations;
completedGroups = numel(runs);
infeasibleRounds = sum(arrayfun(@(x)isfinite(double(x.feasible)) && ~x.feasible,rounds));
allComplete = completedGroups==plannedGroups && cfg.NumCalibrations==10 && ...
    height(seed)==2160 && height(pooled)==720 && height(summary)==30 && ...
    all(summary.status~="incomplete" & summary.status~="infeasible");
output = struct('seed',seed,'pooled',pooled,'per_calibration_summary',summary, ...
    'profile_frequency',frequency,'robustness_summary',robustness, ...
    'per_calibration_profile',profileRows,'completed_groups',completedGroups, ...
    'planned_groups',plannedGroups,'infeasible_rounds',infeasibleRounds, ...
    'all_90_groups_complete',allComplete,'reference_available',false);
if isfield(cfg,'referenceSummary') && istable(cfg.referenceSummary) && ~isempty(cfg.referenceSummary)
    reference = cfg.referenceSummary;
    assert(height(reference)==3 && all(ismember({'scheme','B','R_payload','total_BER'}, ...
        reference.Properties.VariableNames)));
    assert(numel(unique(string(reference.scheme)))==3 && ...
        all(ismember(string(reference.scheme),["Uniform" "Loaded" "Fixed16"])));
    assert(all(isfinite(reference.B) & reference.B>0) && ...
        all(isfinite(reference.R_payload) & reference.R_payload>0) && ...
        all(isfinite(reference.total_BER) & reference.total_BER>=0 & reference.total_BER<=1));
    output.reference_available = true;
    writetable(reference,fullfile(outDir,'reference_summary.csv'));
end
writeChinese(cfg,output,outDir);
if allComplete
    writeEnglish(cfg,output,outDir);
elseif isfile(fullfile(outDir,'results_paragraph_en.txt'))
    error('DMT:StaleStudyParagraph', ...
        'A formal English paragraph exists but current actual counts are incomplete. Preserve and inspect the directory.');
end
if all(arrayfun(@(r)isfinite(double(r.feasible)),rounds)) && any(summary.feasible)
    try
        plotStability(cfg,summary,outDir);
    catch ME
        % This optional diagnostic must not abort the fixed payload schedule.
        fid=fopen(fullfile(outDir,'optional_stability_plot_error.txt'),'a');
        if fid>=0
            fprintf(fid,'%s\n',getReport(ME,'extended','hyperlinks','off'));
            fclose(fid);
        end
        fprintf(2,'Optional stability plot failed; actual counts/CSVs retained: %s\n',ME.message);
    end
end
fprintf('Study export: %d/%d actual completed groups; seed rows %d; pooled rows %d.\n', ...
    completedGroups,plannedGroups,height(seed),height(pooled));
end

function rows = profileTable(cfg,rounds)
names = {'calibration_id','scheme','k','frequency_Hz','SNR_est_dB','M', ...
    'bits_per_symbol','B','R_payload','initialization_id'};
rows = table('Size',[0 numel(names)],'VariableTypes', ...
    [{'double','string'} repmat({'double'},1,7) {'string'}],'VariableNames',names);
for j = 1:numel(rounds)
    one = rounds(j);
    if ~isfinite(double(one.feasible)) || ~one.feasible
        continue;
    end
    for s = 1:3
        p = one.profiles(s);
        added = table(repmat(one.calibration_id,24,1),repmat(string(p.name),24,1), ...
            cfg.k(:),cfg.k(:)*cfg.Fs/cfg.NFFT,one.calibration.gamma_hat_dB(:),p.M, ...
            log2(p.M),repmat(p.B,24,1),repmat(p.R_payload,24,1), ...
            repmat(string(one.initialization_id),24,1),'VariableNames',names);
        rows = [rows;added]; %#ok<AGROW>
    end
end
end

function writeChinese(cfg,output,outDir)
summary = output.per_calibration_summary;
robustness = output.robustness_summary;
lines = ["# v1.2 独立校准重复试验：实际状态"; ""; ...
    string(sprintf('计划 %d 组，实际完整载荷组 %d；不可行校准轮数 %d。', ...
    output.planned_groups,output.completed_groups,output.infeasible_rounds)); ...
    "这些表只包含新 calibration_id=1…10；reference calibration 0 不并入重复试验。没有把不同轮 profile 的比特混合后计算一个用于证明单个 profile 合规的区间。"; ""];
if output.reference_available
    reference = cfg.referenceSummary;
    lines(end+1,1) = "已验证的reference calibration 0单独保存在reference_summary.csv，不并入以下新轮次。";
    for name = ["Uniform" "Loaded" "Fixed16"]
        r = reference(string(reference.scheme)==name,:);
        lines(end+1,1) = string(sprintf('reference 0 %s：B=%.9g，载荷速率=%.9g Mbit/s，观察总BER=%.9g；以上是已有基准，不是新增十轮汇总。', ...
            char(name),r.B,r.R_payload/1e6,r.total_BER)); %#ok<AGROW>
    end
else
    lines(end+1,1) = "本次导出未取得已验证的reference 0汇总，不能声称已完成参考图重绘；以下只报告新增校准实际计数。";
end
lines = [lines; ""; "## 各轮状态"; ""; ...
    "| calibration_id | scheme | B | R_payload (Mbit/s) | 完成种子数 | 观察总 BER | 最大 CI 上端点/目标 | 状态 |"; ...
    "| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |"];
for j = 1:height(summary)
    r = summary(j,:);
    lines(end+1,1) = string(sprintf('| %d | %s | %s | %s | %d | %s | %s | %s |', ...
        r.calibration_id,char(r.scheme),numberOrMissing(r.B),numberOrMissing(r.R_payload/1e6), ...
        r.test_seed_count,numberOrMissing(r.total_BER), ...
        numberOrMissing(r.max_normalized_CI_high),char(r.status))); %#ok<AGROW>
    if r.status=="failed" || r.status=="inconclusive"
        lines(end+1,1) = string(sprintf('轮%d %s：CI下界超目标 k=%s；区间跨越/触及目标 k=%s。', ...
            r.calibration_id,char(r.scheme),char(r.failed_k),char(r.inconclusive_k))); %#ok<AGROW>
    elseif r.status=="incomplete" || r.status=="infeasible"
        lines(end+1,1) = string(sprintf('轮%d %s 未提供完整性能统计，原因：%s。', ...
            r.calibration_id,char(r.scheme),char(r.reason))); %#ok<AGROW>
    end
end
lines = [lines; ""; "## 跨校准摘要的解释"; ""];
for j = 1:height(robustness)
    r = robustness(j,:);
    lines(end+1,1) = string(sprintf(['%s：supported=%d，failed=%d，inconclusive=%d，' ...
        'infeasible=%d，incomplete=%d；已记录profile轮数=%d。B最小/中位/最大=%s/%s/%s，' ...
        '载荷速率Mbit/s最小/中位/最大=%s/%s/%s。'], ...
        char(r.scheme),r.supported_rounds,r.failed_rounds,r.inconclusive_rounds, ...
        r.infeasible_rounds,r.incomplete_rounds,r.profiled_rounds, ...
        numberOrMissing(r.B_min),numberOrMissing(r.B_median),numberOrMissing(r.B_max), ...
        numberOrMissing(r.R_payload_min/1e6),numberOrMissing(r.R_payload_median/1e6), ...
        numberOrMissing(r.R_payload_max/1e6))); %#ok<AGROW>
end
loaded = robustness(robustness.scheme=="Loaded",:);
lines = [lines; string(sprintf('各轮Loaded/Uniform的承载量比最小/中位/最大为%s/%s/%s；不是把10轮比特合并后得到的单profile性能。', ...
    numberOrMissing(loaded.loaded_uniform_ratio_min),numberOrMissing(loaded.loaded_uniform_ratio_median), ...
    numberOrMissing(loaded.loaded_uniform_ratio_max))); ...
    "profile_frequency.csv每个scheme/k只按每轮的一次冻结profile计数，不按三个载荷种子重复计数。三种QAM选择次数之和，加该scheme/k的不可行及尚未校准次数，必须等于计划校准轮数；后两列在三个M行重复列示，不能再对M求和。"; ...
    "k21靠近选阶边界，可由各轮真实探测估计选择不同阶数；既不强制变化，也不强制118或120bits。具体值见per_calibration_profile.csv和profile_frequency.csv。"; ""; ...
    "## 图、区间与物理边界"; ""; ...
    "论文Figure 2必须固定使用预先指定的reference calibration 0，不能从这10轮挑选最有利的一轮。新(c)的统一统计量是逐点95% Wilson近似区间上端点除以BER目标；u<1表示通过该上端点判据，并非保证真实BER必然小于目标。u>1也不自动表示确定失败，只有CI_low>target才赋failed。零误码也保留真实测试比特数对应的非零上界。"; ...
    "本目录calibration_stability图若存在，只是各轮profile和归一化上端点的诊断；跨10轮的范围不是95%置信带。不得将10个上端点的均值当作新的95%置信上界。"; ...
    "每轮区间只在同一calibration_id/scheme/k内合并三个载荷种子，采用常用二项近似，非所有子载波联合95%覆盖。10/10仅是本次10轮观察，不等于未来成功概率100%。"; ...
    "Fixed16为统一提高QAM阶数的诊断，允许其不满足目标；主比较关注Uniform与Loaded在目标约束内的承载量，Loaded的总BER不必更低。"; ...
    "R_payload包含CP时间，未扣初始化、反馈或FEC，不是完整净吞吐量。三策略固定相同活跃子载波和星座平均电能量；实际随机能量不事后缩放。"; ...
    "本项目是受文献思想启发、作者预设参数的简化电域DMT验证；未复现完整Chow能量调整、光学硬件或100Gb/s实验，也未验证跨物理信道或光器件鲁棒性。10轮数、训练长度、裕量、目标、Wilson和归一化上端点图均不是所引文献规定。文献核实与映射见literature_mapping.md。" ];
if ~output.all_90_groups_complete
    lines = [lines; ""; "**正式90组尚未完整完成；不生成新的正式英文结果段，不能用未完成或不可行行的NaN当作BER=0。**"];
end
writeText(fullfile(outDir,'report_notes_zh.md'),join(lines,newline));
end

function writeEnglish(cfg,output,outDir)
r = output.robustness_summary;
u = r(r.scheme=="Uniform",:);
l = r(r.scheme=="Loaded",:);
f = r(r.scheme=="Fixed16",:);
referenceText = ['Reference calibration 0 was unavailable to this export; these new results do not replace ' ...
    'or reconstruct its benchmark data.'];
if output.reference_available
    ref = cfg.referenceSummary;
    ru = ref(string(ref.scheme)=="Uniform",:);
    rl = ref(string(ref.scheme)=="Loaded",:);
    rf = ref(string(ref.scheme)=="Fixed16",:);
    referenceText = sprintf(['Separately, reference 0 carried %g/%g/%g bits at %.6g/%.6g/%.6g Mbit/s, ' ...
        'with observed BERs %.6g/%.6g/%.6g in Uniform/Loaded/Fixed16 order; its samples are excluded here.'], ...
        ru.B,rl.B,rf.B,ru.R_payload/1e6,rl.R_payload/1e6,rf.R_payload/1e6, ...
        ru.total_BER,rl.total_BER,rf.total_BER);
end
paragraph = sprintf(['Ten new independent calibrations were evaluated in the author''s simplified electrical-baseband DMT model. ' ...
    'Each calibration used independent QPSK training and probing, followed by one frozen channel estimate and three modulation profiles. ' ...
    'Every strategy used three payload seeds with 100000 DMT symbols per seed, completing 90 groups. ' ...
    'The physical FIR, receiver-noise variance, mean subcarrier energy, target BER, and loading margin remained unchanged. ' ...
    'Uniform, Loaded, and diagnostic Fixed16 met the pointwise upper-endpoint criterion in %d, %d, and %d of ten calibrations, respectively. ' ...
    'Loaded carried between %g and %g bits per DMT symbol, with median %g; its per-calibration payload ratio to Uniform ranged from %.6g to %.6g. ' ...
    'Counts were pooled only across the three payload seeds within each calibration and subcarrier, preserving separate profiles and approximate 95%% Wilson intervals. ' ...
    'These intervals do not provide simultaneous coverage, and zero observed errors do not establish zero true BER. ' ...
    '%s ' ...
    'Payload rates include cyclic-prefix time but exclude initialization, feedback, and FEC overhead. ' ...
    'The observed stability concerns calibration and loading for this fixed electrical channel, not optical hardware or future success probabilities.'], ...
    u.supported_rounds,l.supported_rounds,f.supported_rounds,l.B_min,l.B_max,l.B_median, ...
    l.loaded_uniform_ratio_min,l.loaded_uniform_ratio_max,referenceText);
words = regexp(strtrim(paragraph),'\s+','split');
assert(numel(words)>=150 && numel(words)<=220,'DMT:StudyParagraphLength', ...
    'Formal study paragraph must contain 150--220 words; observed %d.',numel(words));
writeText(fullfile(outDir,'results_paragraph_en.txt'),paragraph);
end

function plotStability(cfg,summary,outDir)
fig = figure('Visible','off','Units','inches','Position',[1 1 6.7 5.4]);
cleanup = onCleanup(@()close(fig)); %#ok<NASGU>
if isprop(fig,'Theme'), fig.Theme = 'light'; end
set(fig,'Color','w','InvertHardcopy','off');
layout = tiledlayout(fig,2,1,'TileSpacing','compact','Padding','compact');
names = ["Uniform" "Loaded" "Fixed16"];
styles = {'-o','--s','-.d'};
colors = [0 0.28 0.55;0.72 0.23 0.03;0.15 0.15 0.15];
ax1 = nexttile(layout); hold(ax1,'on');
ax2 = nexttile(layout); hold(ax2,'on');
limits = 1;
for s = 1:3
    data = sortrows(summary(summary.scheme==names(s),:),'calibration_id');
    plot(ax1,data.calibration_id,data.B,styles{s},'Color',colors(s,:), ...
        'LineWidth',1.1,'MarkerSize',4,'DisplayName',names(s));
    measured = isfinite(data.max_normalized_CI_high);
    values = data.max_normalized_CI_high;
    values(~measured) = NaN;
    plot(ax2,data.calibration_id,values,styles{s},'Color',colors(s,:), ...
        'LineWidth',1.1,'MarkerSize',4,'DisplayName',names(s));
    limits = [limits;values(measured)]; %#ok<AGROW>
end
ylabel(ax1,'Bits / DMT symbol');
title(ax1,'Frozen profiles across independent calibrations');
ylabel(ax2,'Maximum CI upper endpoint / target'); xlabel(ax2,'Calibration ID');
title(ax2,'Separate per-calibration checks; no cross-profile confidence interval');
set(ax2,'YScale','log');
yline(ax2,1,':k','Upper-endpoint criterion = 1','HandleVisibility','off');
positive = limits(isfinite(limits) & limits>0);
ylim(ax2,[10^floor(log10(min(positive)))/1.5 10^ceil(log10(max(positive)))*1.5]);
for ax = [ax1 ax2]
    set(ax,'Color','w','XColor','k','YColor','k','FontSize',8.5, ...
        'GridColor',[0.8 0.8 0.8],'Box','on');
    ax.Title.Color = 'k'; ax.XLabel.Color = 'k'; ax.YLabel.Color = 'k';
    xticks(ax,1:cfg.NumCalibrations); xlim(ax,[0.5 cfg.NumCalibrations+0.5]); grid(ax,'on');
end
leg = legend(ax1,'Location','southoutside','Orientation','horizontal');
set(leg,'Color','w','TextColor','k','Box','off');
drawnow;
exportgraphics(fig,fullfile(outDir,'calibration_stability.png'),'Resolution',300,'BackgroundColor','white');
exportgraphics(fig,fullfile(outDir,'calibration_stability.pdf'),'ContentType','vector','BackgroundColor','white');
savefig(fig,fullfile(outDir,'calibration_stability.fig'));
writeText(fullfile(outDir,'calibration_stability_caption_en.txt'), ...
    ['Diagnostic variation across the planned independent calibrations. Each point uses its own frozen profile; ' ...
    'missing or infeasible rounds remain gaps. The lower panel shows the maximum of that calibration''s ' ...
    'pointwise Wilson upper endpoints divided by the BER target. Any range across calibrations is an observed ' ...
    'range, not a 95% confidence band or a cross-profile confidence interval.']);
end

function text = numberOrMissing(value)
text = 'not available';
if isfinite(value), text = sprintf('%.9g',value); end
end

function writeText(path,text)
fid = fopen(path,'w','n','UTF-8');
assert(fid>=0,'DMT:StudyNarrativeFile','Cannot open %s.',path);
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',char(text));
end
