function dmt_fb_graphics_notes(folder,study,cfg,tables,data)
%DMT_FB_GRAPHICS_NOTES State conclusions from audited formal evidence.
fid=fopen(fullfile(folder,'results_zh.md'),'wt','n','UTF-8');
assert(fid>=0,'DMT:FBGraphicsNotes','Cannot write the Chinese results summary.');
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
switch study
    case 'promotion'
        writePromotion(fid,tables);
    case 'scan'
        writeScan(fid,tables.status,data);
end
fprintf(fid,['\n## 适用范围\n\n所有结果均基于公开实测幅度曲线的归一化等效信道，结论限于本批采样工作点。' ...
    '原文扫描接收光功率。本仿真控制归一化平均发射光功率并保留削波。' ...
    '周期速率按 %d 个载荷符号和实际前向设置开销计算，反馈时延设为 %.3g 秒。\n\n' ...
    'ADSL2 和 VDSL2 是按音调分配比特的实际例子。质量较好的音调可分配更多比特，' ...
    '较差的音调可少分配或停用。本实验始终保持 %d 个载波活跃。' ...
    'ADC 位数表征量化级数与实现要求，训练和验证开销以实发符号量与周期速率表达。\n'], ...
    cfg.payload_symbols,cfg.control_delay,numel(cfg.k));
end

function writePromotion(fid,tables)
fprintf(fid,'# 实验二 · 第一轮优先验证升阶候选\n\n');
writeSlots(fid,[tables.original.status;tables.promotion.status]);
rows=sortrows(tables.pairs,'calibration_id');
assert(isequal(rows.calibration_id,(1:5).'));
accepted=sum(rows.promotion_accepted);
attempted=sum(rows.promotion_attempted);
matched=isfinite(rows.delta_supported_R_cycle_Mbps);
improved=matched & rows.delta_supported_R_cycle_Mbps>0;
gains=rows.delta_supported_R_cycle_Mbps(matched);
fprintf(fid,['固定工作点为归一化目标平均发射光功率 1.0、8 bit ADC。' ...
    '原验证式加载达标 %d/5 轮，优先升阶达标 %d/5 轮。' ...
    '优先升阶分支实际尝试 %d 次，整表验证接受 %d 次。\n\n'], ...
    sum(rows.a_state=="supported"),sum(rows.b_state=="supported"),attempted,accepted);
if isempty(gains)
    fprintf(fid,'本批没有同时满足两分支 BER 判据与配对功率要求的轮次，未获得可验证的净速率差。\n\n');
else
    fprintf(fid,['两分支均达到 BER 判据且载荷功率匹配的轮次为 %d/5，' ...
        '其中优先升阶周期速率更高的轮次为 %d。' ...
        '这些可比轮次的速率差范围为 %+.3f 至 %+.3f Mbit/s。\n\n'], ...
        sum(matched),sum(improved),min(gains),max(gains));
end
fprintf(fid,['| 轮次 | A / B 候选状态 | A / B 载荷状态 | B 是否接受升阶 | ' ...
    'A / B 设置符号 | A / B 周期速率 (Mbit/s) | B−A 达标速率差 (Mbit/s) |\n' ...
    '| ---: | --- | --- | --- | ---: | ---: | ---: |\n']);
for j=1:height(rows)
    r=rows(j,:);
    acceptedLabel="否";
    if r.promotion_accepted,acceptedLabel="是";end
    fprintf(fid,'| %d | %s / %s | %s / %s | %s | %s / %s | %s / %s | %s |\n', ...
        r.calibration_id,r.a_candidate_state,r.b_candidate_state,r.a_state,r.b_state, ...
        acceptedLabel,num(r.a_setup_symbols,0),num(r.b_setup_symbols,0), ...
        num(r.a_R_cycle_Mbps,3),num(r.b_R_cycle_Mbps,3),num(r.delta_supported_R_cycle_Mbps,3));
end
fprintf(fid,['\n每轮载荷统计合并该分支的两个独立槽位。逐点 Wilson 区间用于载波 BER 判定。' ...
    '设置符号计入已发送的候选验证和回退步骤。图 A 采用事先指定的第 1 轮。\n']);
end

function writeScan(fid,status,data)
fprintf(fid,'# 实验一 · 功率与 ADC 扫描\n\n');
writeSlots(fid,status);
fprintf(fid,['下表在五轮均满足 BER 与功率判据且五轮最低周期速率达到 75 Mbit/s 的条件中，' ...
    '按最大实测平均发射光功率选取最低测试点。\n\n']);
fprintf(fid,['| ADC | 策略 | 最低达标测试点 | 目标功率 | 十槽实测功率范围 | ' ...
    '合格速率范围 (Mbit/s) |\n' ...
    '| ---: | --- | --- | ---: | ---: | ---: |\n']);
for j=1:height(data.requirements)
    r=data.requirements(j,:);
    result='本次扫描未找到';
    if r.status=="qualified_tested_point",result='达到要求';end
    fprintf(fid,'| %d bit | %s | %s | %s | %s | %s |\n', ...
        r.q,r.scheme,result,num(r.selected_P_target,1), ...
        numRange(r.measured_power_min,r.measured_power_max,6), ...
        numRange(r.qualified_rate_min_Mbps,r.qualified_rate_max_Mbps,3));
end
adc=data.adc_comparisons;
matched=adc.status=="qualified_power_matched_adc_comparison";
fprintf(fid,'\n同一目标功率下，可用来比较同功率 ADC 速率的策略与功率组合共有 %d 项。\n',sum(matched));
for j=find(matched).'
    r=adc(j,:);
    fprintf(fid,'\n- 目标 %.1f，%s。8 bit 相比 6 bit 的合格周期速率中位数变化为 %+.3f Mbit/s。', ...
        r.P_target,r.scheme,r.qualified_rate_delta_8minus6_Mbps);
end
fprintf(fid,'\n\n## 较高功率下的削波与开销\n\n');
for q=[6 8]
    view=data.points(data.points.q==q & data.points.scheme=="ValidatedLoading" & ...
        ismember(data.points.P_target,[1.2 1.4]),:);
    view=sortrows(view,'P_target');
    assert(height(view)==2);
    if any(view.observed_transmitted_slots==0)
        fprintf(fid,['- %d bit，目标功率 1.2 和 1.4 的实发载荷槽数为 %d 和 %d，' ...
            '合格轮数为 %d/5 和 %d/5。本批缺少两点共有的载荷诊断。\n'], ...
            q,view.observed_transmitted_slots(1),view.observed_transmitted_slots(2), ...
            view.supported_count(1),view.supported_count(2));
        continue;
    end
    fprintf(fid,['- %d bit，目标功率由 1.2 到 1.4。载荷削波率由 %s%% 到 %s%%，' ...
        'ADC 越界率由 %s%% 到 %s%%。已发送轮次平均承载由 %s 到 %s bit/符号，' ...
        '平均前向设置开销由 %s 到 %s 符号。'],q,num(100*view.tx_clip_rate(1),4), ...
        num(100*view.tx_clip_rate(2),4),num(100*view.adc_oob_rate(1),4), ...
        num(100*view.adc_oob_rate(2),4),num(view.mean_bits_observed(1),2), ...
        num(view.mean_bits_observed(2),2),num(view.mean_setup_symbols_observed(1),1), ...
        num(view.mean_setup_symbols_observed(2),1));
    if all(view.qualified)
        change=diff(view.qualified_rate_median_Mbps);
        fprintf(fid,' 达标周期速率中位数变化为 %+.3f Mbit/s。\n',change);
    else
        fprintf(fid,' 两点合格轮数分别为 %d/5 和 %d/5。\n', ...
            view.supported_count(1),view.supported_count(2));
    end
end
fprintf(fid,['\n图 B 仅展示 5/5 达标点的合格周期速率。横坐标取十个载荷槽的实测平均发射光功率最大值。' ...
    '纵向范围取五轮最小值到最大值。\n']);
end

function writeSlots(fid,status)
done=sum(status.status=="completed");
rejected=sum(status.status=="design_rejected");
powerError=sum(status.status=="power_error");
executionError=sum(status.status=="execution_error");
other=height(status)-done-rejected-powerError-executionError;
fprintf(fid,['本批按已审计的正式记录写成。计划 %d 个槽位，实际发送 %d 个，' ...
    '正常设计拒绝 %d 个，功率错误 %d 个，执行错误 %d 个，其他未完成 %d 个。\n\n'], ...
    height(status),done,rejected,powerError,executionError,other);
end

function text=numRange(lo,hi,precision)
text='—';
if isfinite(lo) && isfinite(hi),text=[num(lo,precision) '–' num(hi,precision)];end
end

function text=num(value,precision)
text='—';
if isfinite(value),text=sprintf('%.*f',precision,value);end
end
