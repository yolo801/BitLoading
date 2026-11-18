function dmt_vm_graphics_notes(path,cfg,tables)
%DMT_VM_GRAPHICS_NOTES Summarize the formal comparison from audited evidence.
fid=fopen(path,'wt','n','UTF-8');
assert(fid>=0,'DMT:VMFigureNotes','Cannot write Chinese results.');
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# VCSEL–MMF DMT 正式结果\n\n');
status=tables.status.status;
sent=sum(status=="completed");
rejected=sum(status=="design_rejected");
powerError=sum(status=="power_error");
executionError=sum(status=="execution_error");
fprintf(fid,['正式计划 %d 槽。已发送 %d 槽，设计正常拒绝 %d 槽，功率错误 %d 槽，' ...
    '执行错误 %d 槽，其他未完成 %d 槽。\n\n'],numel(status),sent,rejected,powerError, ...
    executionError,numel(status)-sent-rejected-powerError-executionError);
writeSelectivity(fid,cfg,tables);
writeCycle(fid,cfg,tables);
writeConditionTable(fid,tables.scenario);
fprintf(fid,['\n信道采用公开的 50 m VCSEL–MMF 模型响应幅度近似。速率使用模型采样时钟，' ...
    '且每种冻结表的每符号承载量保留在 `summary.csv`。结果只涵盖本协议的频带、' ...
    '摆幅、噪声、固定 8 bit ADC 量化和两种 DMT 选阶策略。\n']);
end

function writeSelectivity(fid,cfg,tables)
ref=cfg.representative;
target=tables.summary(tables.summary.case_id==ref.case_id & tables.summary.swing==ref.swing & ...
    tables.summary.calibration_id==ref.calibration_id,:);
assert(height(target)==2);
profiles=tables.profiles(tables.profiles.case_id==ref.case_id & ...
    tables.profiles.swing==ref.swing & tables.profiles.calibration_id==ref.calibration_id,:);
fprintf(fid,'## 频率选择性与实发结果\n\n');
fprintf(fid,['图 B 使用事先约定的 Case %d、中档摆幅 %.2f、第 %d 轮，' ...
    '预先记录的公开幅度曲线陷波位于约 %.2f GHz。'], ...
    ref.case_id,ref.swing,ref.calibration_id,cfg.case2_notch_GHz);
names=["UniformValidated" "PerToneValidated"];
for j=1:numel(names)
    row=target(target.strategy==names(j),:);
    profile=profiles(profiles.strategy==names(j),:);
    if isempty(profile)
        fprintf(fid,' %s 状态为 %s，未保存可发送的调制表。',names(j),row.state);
    else
        [~,i]=min(abs(profile.frequency_GHz-cfg.case2_notch_GHz));
        description=join(compose('%d-QAM',unique(profile.M).'), '、');
        fprintf(fid,[' %s 使用 %s，陷波最近的活跃载波为 %.2f GHz、%d-QAM，' ...
            '冻结表承载 %d bit/符号，载荷状态为 %s。'],names(j),description, ...
            profile.frequency_GHz(i),profile.M(i),row.bits_per_symbol,row.state);
    end
end
fprintf(fid,[' 图中 BER 来自该轮实发载荷的整数计数。误码数为零时显示逐点 95%% Wilson 上限。' ...
    '同轮的两槽合并用于 BER 判定，跨轮结果保留独立状态。\n\n']);

pairs=tables.pair_gains;
eligible=pairs.pair_qualified;
gains=pairs.validated_delta_R_cycle(eligible)/1e9;
assert(all(isfinite(gains)));
if isempty(gains)
    fprintf(fid,['这六个工作点的配对轮次中，没有同时满足两策略 BER 判据和资源匹配的轮次，' ...
        '可验证的净速率差尚无数据。\n\n']);
else
    fprintf(fid,['%d/%d 轮同时满足两策略 BER 判据和资源匹配，其中逐载波选阶更快 %d 轮，' ...
        '统一选阶更快 %d 轮，速率相同 %d 轮。已支持、资源匹配的轮次中，' ...
        '逐载波选阶相对统一选阶的周期速率差为 %+.3f 到 %+.3f Gbit/s。\n\n'], ...
        numel(gains),height(pairs),sum(gains>0),sum(gains<0),sum(gains==0),min(gains),max(gains));
end
end

function writeCycle(fid,cfg,tables)
fprintf(fid,'## 配置时间、载荷长度与削波\n\n');
fprintf(fid,['图 A 的达标周期速率按每次配置后 %d 个载荷符号计算，正式两槽是计数重复。' ...
    '所有实际发送的探测、训练和候选验证均计入配置时间。' ...
    '每个符号含 CP 的时长为 %.3f ns。发射机本地功率标定开销在事件表单列。'], ...
    cfg.payload_symbols,1e9*cfg.Ts);
if cfg.control_delay==0
    fprintf(fid,' 控制延迟采用 0 秒理想模型。');
end
s=tables.length_sensitivity;
valid=s(s.pair_qualified,:);
[cals,first]=unique(valid.calibration_id,'stable');
if isempty(cals)
    fprintf(fid,' 代表点缺少两策略均达标且资源匹配的轮次，载荷长度面板只报告状态。');
else
    cross=valid.cross_over_L(first);
    cross=cross(isfinite(cross) & cross>0);
    coincident=sum(valid.cross_over_status(first)=="identical_cycle_rates");
    if isempty(cross)
        fprintf(fid,' 代表点 %d 个配对轮次没有孤立的正交叉点。',numel(cals));
    else
        fprintf(fid,[' 代表点 %d 个配对轮次中，%d 轮有有限正交叉点，' ...
            '范围为 %.0f 至 %.0f 个载荷符号。'],numel(cals),numel(cross),min(cross),max(cross));
    end
    if coincident>0,fprintf(fid,' %d 轮的两条周期速率曲线完全重合。',coincident);end
    fprintf(fid,[' 载荷长度曲线固定已保存的调制表与配置时间，' ...
        '在 10³–10⁵ 符号之间作算术敏感性分析。']);
end
high=tables.scenario(tables.scenario.swing==.75,:);
rates=high.tx_clip_rate_max(isfinite(high.tx_clip_rate_max));
if isempty(rates)
    fprintf(fid,' 高档驱动没有可用的正式载荷削波统计。\n\n');
elseif max(rates)==0
    fprintf(fid,' 高档驱动已发送的正式载荷中未观察到发射削波。\n\n');
else
    fprintf(fid,[' 高档驱动各条件的最大逐轮合并削波率在 %.4g%% 到 %.4g%%。' ...
        'BER、速率和削波一同报告，峰值限制的独立影响需要受控诊断。\n\n'], ...
        100*min(rates),100*max(rates));
end
end

function writeConditionTable(fid,scenario)
fprintf(fid,['| 频响 | 摆幅 | 策略 | 达标轮数 | 周期速率范围 (Gbit/s) | 候选次数中位数 | ' ...
    '配置时间中位数 (µs) | 最大发射削波率 (%%) | 最大 ADC 越界率 (%%) |\n' ...
    '| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |\n']);
rows=sortrows(scenario,{'case_id','swing','strategy'});
for j=1:height(rows)
    r=rows(j,:);
    rate='—';
    if r.qualified
        rate=sprintf('%.3f–%.3f',r.R_cycle_min/1e9,r.R_cycle_max/1e9);
    end
    fprintf(fid,'| %d | %.2f | %s | %d/%d | %s | %s | %s | %s | %s |\n', ...
        r.case_id,r.swing,r.strategy,r.supported_count,r.planned_calibrations,rate, ...
        number(r.attempt_median,1),number(r.setup_median_s*1e6,3), ...
        number(r.tx_clip_rate_max*100,4),number(r.adc_oob_rate_max*100,4));
end
end

function text=number(value,precision)
text='—';
if isfinite(value),text=sprintf('%.*f',precision,value);end
end
