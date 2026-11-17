function dmt_to_export(cfg,tables,outDir,phase)
%DMT_TO_EXPORT Actual raw counts, statuses and costs; no payload transmission.
assert(strcmp(tables.phase,phase));
if ~isfolder(outDir),mkdir(outDir);end
mapping=dmt_to_output_files();
dictionaryRows={};
for j=1:size(mapping,1)
    value=tables.(mapping{j,1});assert(istable(value));
    writetable(value,fullfile(outDir,mapping{j,2}));
    fields=value.Properties.VariableNames;
    for k=1:numel(fields)
        [meaning,unit]=describe(fields{k});
        dictionaryRows{end+1}=struct('file',string(mapping{j,2}),'field',string(fields{k}), ...
            'meaning',string(meaning),'unit',string(unit)); %#ok<AGROW>
    end
end
dictionary=struct2table([dictionaryRows{:}]);
writetable(dictionary,fullfile(outDir,'field_dictionary.csv'));
writeDictionary(outDir,mapping);
writeNotes(cfg,tables,outDir,phase);
end

function writeDictionary(outDir,mapping)
fid=fopen(fullfile(outDir,'field_dictionary.md'),'w','n','UTF-8');assert(fid>=0);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# tradeoff_v1 字段与统计口径\n\n');
fprintf(fid,'逐字段字典见field_dictionary.csv；以下说明跨表共同语义。\n\n');
fprintf(fid,'- phase明确formal/preflight，预检的短载荷不进入正式统计。\n');
fprintf(fid,'- condition_id对应固定(P_target,q)，calibration_id独立校准，scheme为策略，payload_slot为统计重复槽位，k为独立正频率载波。\n');
fprintf(fid,'- 逐seed与pooled是同一数据的层级，不能重复相加。pooled仅在同条件/校准/策略内累加全部固定payload重复；跨校准不同M不混合证明合规。\n');
fprintf(fid,'- error_bits/tested_bits是原始整数计数；总BER=sum(error_bits)/sum(tested_bits)。零观察误码不是BER真实为零。\n');
fprintf(fid,'- CI_low/CI_high为z=1.96近似95%%逐点Wilson区间；相关误码/量化/非线性下不声称严格二项覆盖，也不是跨载波联合95%%保证。\n');
fprintf(fid,'- BER_state优先任一CI_low>target为failed，全部CI_high<target为supported，其余inconclusive；未完成/设计拒绝单列。\n');
fprintf(fid,'- design_status是设计流程结果，不代表正式BER通过；no_initial_candidate等不等于全局物理不可行。\n');
fprintf(fid,'- power_state和BER_state独立；power_mismatch保留计数但排除受支持功率/速率比较，不做事后缩放。\n');
fprintf(fid,'- b是偏置/驱动控制量，P_actual才是含CP的实际平均光功率。P_actual_relative_dB=10log10(P_actual/1)，不是dBm。mean_p_squared与光功率均值分开。\n');
fprintf(fid,'- AC_drive_mean_square是b*x/(rho*sigma_ref)的均方值；不按该值重新缩放波形。\n');
fprintf(fid,'- TX_clipping_rate与ADC_out_of_range_rate分开；后者是ADC前含DC加噪样本超出固定输入范围的比例。分母全部含CP。\n');
fprintf(fid,'- q为理想ADC量化位数，不能称实际ENOB、器件报价或整机功耗。\n');
fprintf(fid,'- R_nominal=B_DMT/T_DMT已计CP，但未计初始化；R_cycle按一个L符号周期扣实际A0/B0和所有尝试轮A_r/D_r。两个payload重复不组成2L周期。\n');
fprintf(fid,'- TX_power_cal_symbols为离线发送波形校准量，不计光链路训练时长；compute_seconds为当前软件计算参考，不含导出/绘图，也不是ASIC功耗。\n');
fprintf(fid,'- initial_quality_scalar_count/quality_SNR_scalars等为显式理想控制对象数量；未声明序列化位宽，因此serialized_bits为NaN，不把MATLAB字节当线路位数。\n');
fprintf(fid,'- optical_energy_norm及其每bit量是归一化光功率单位乘秒，来自实际sum(p)/Fs；不是J/bit或整机能效。每个重复周期都包含同一实际setup的成本。\n');
fprintf(fid,'- scenario速率min/median/max覆盖全部已接受设计，包括BER失败/未完成；实心/受支持结论仅5/5轮BER-supported且所有payload功率匹配。min-max不是CI。\n');
fprintf(fid,'- rate_requirements的found仅表示完整扫描中，全部轮的最小R_cycle达到最低业务门槛的最低已测试功率点；门槛不是所有策略实际速率相同，不作阈值插值。\n');
fprintf(fid,'- budget_envelope只选择全部payload最大实测功率<=预算的受支持点，以五轮最小R_cycle形成经验包络；不是容量或理论Pareto边界。\n\n');
fprintf(fid,'## CSV输出\n\n');
for j=1:size(mapping,1),fprintf(fid,'- %s：内部表%s。\n',mapping{j,2},mapping{j,1});end
end

function writeNotes(cfg,t,outDir,phase)
fid=fopen(fullfile(outDir,'report_notes_zh.md'),'w','n','UTF-8');assert(fid>=0);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'# tradeoff_v1 实际结果说明\n\n');
if strcmp(phase,'preflight')
    fprintf(fid,'**本文件只说明独立预检接线数据，不是正式BER或业务速率验收。**\n\n');
else
    fprintf(fid,'本文件由当次正式记录重算，不预设所有工作点受支持。\n\n');
end
fprintf(fid,'实际完成%d/%d个计划payload槽；设计拒绝%d槽；未完成%d槽。实际设计处理%d/%d case，接受%d case。\n\n', ...
    t.completed_groups,t.planned_groups,t.rejected_groups,t.incomplete_groups, ...
    t.design_cases_processed,t.design_cases_planned,t.design_cases_accepted);
fprintf(fid,'已完成载荷的seed/pooled逐载波行数为%d/%d。未完成BER保持NaN；设计拒绝与科学BER失败分开。\n\n',height(t.seed),height(t.pooled));
fprintf(fid,'## 每个扫描点的全部校准状态\n\n');
fprintf(fid,'|P_target|q|策略|BER支持|BER失败|不确定|设计拒绝|未完成|功率不匹配|受支持轮数|\n');
fprintf(fid,'|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|\n');
for j=1:height(t.scenario)
    r=t.scenario(j,:);
    fprintf(fid,'|%.3g|%d|%s|%d|%d|%d|%d|%d|%d|%d/%d|\n',r.P_target,r.q,char(r.scheme), ...
        r.BER_supported_rounds,r.BER_failed_rounds,r.BER_inconclusive_rounds,r.design_rejected, ...
        r.incomplete_rounds,r.power_mismatch_rounds,r.supported_rounds,r.planned_calibrations);
end
fprintf(fid,'\n只有正式数据的全部校准均BER-supported且全部payload功率匹配，才将该点视为受支持。速率范围是全部已接受设计的min–max，不是置信带；拒绝和未完成轮不被隐藏。\n\n');
fprintf(fid,'## 1 同一平均光功率预算能多传多少\n\n');
foundPairs=0;
if strcmp(phase,'formal')
    for q=cfg.adc_bits
        for budget=cfg.P_targets
            x=t.budget_envelope(t.budget_envelope.q==q & t.budget_envelope.power_budget==budget,:);
            u=x(x.scheme==string(cfg.scheme_names{1}),:);l=x(x.scheme==string(cfg.scheme_names{2}),:);
            if u.status=="found" && l.status=="found"
                foundPairs=foundPairs+1;
                fprintf(fid,'- q=%d、预算%.3g：两个经验包络的五轮最小R_cycle分别为%.6g、%.6g Mbit/s，Loaded/Uniform=%.6g；差为%.6g Mbit/s。各点所有payload最大实测功率均不超过预算。\n', ...
                    q,budget,u.R_cycle_min/1e6,l.R_cycle_min/1e6,l.R_cycle_min/u.R_cycle_min, ...
                    (l.R_cycle_min-u.R_cycle_min)/1e6);
            end
        end
    end
end
if foundPairs==0
    fprintf(fid,'当前没有同时满足预算和正式证据判据的可比较包络对；不能据此声称正增益或全局不可行。若扫描未完成，应继续原任务。\n');
end
fprintf(fid,'\n这些是本方法采样工作点的经验比较，不是理论容量/Pareto边界。比特加载不要求BER低于Uniform。\n\n');
fprintf(fid,'## 2 满足最低业务速率需要多少已测试功率\n\n');
cycle=t.requirements(t.requirements.metric=="R_cycle",:);
for j=1:height(cycle)
    r=cycle(j,:);
    if r.status=="found"
        fprintf(fid,'- q=%d、%s、R_req=%.0f Mbit/s：最低已测试目标功率%.3g，实际范围[%.6g, %.6g]；五轮最小R_cycle=%.6g Mbit/s。\n', ...
            r.q,char(r.scheme),r.R_required/1e6,r.P_target_selected,r.P_actual_min,r.P_actual_max,r.all_calibrations_min_rate/1e6);
    elseif r.status=="not_found_in_completed_scan"
        fprintf(fid,'- q=%d、%s、R_req=%.0f Mbit/s：本扫描范围内未找到。\n',r.q,char(r.scheme),r.R_required/1e6);
    else
        fprintf(fid,'- q=%d、%s、R_req=%.0f Mbit/s：%s，尚不能作完整正式扫描的最低功率结论。\n', ...
            r.q,char(r.scheme),r.R_required/1e6,char(r.status));
    end
end
fprintf(fid,'\n门槛表示“至少达到”，不是各方案实际速率完全相同；没有未经验证的插值功率节省。名义速率对照另见rate_requirements.csv的R_nominal行。\n\n');
fprintf(fid,'## 3 最低已测试ADC能力\n\n');
for req=cfg.R_req
    eligible=cycle(cycle.R_required==req & cycle.status=="found",:);
    if isempty(eligible)
        fprintf(fid,'- 对%.0f Mbit/s，尚无可报告的受支持最低理想量化位数。\n',req/1e6);
    else
        minQ=min(eligible.q);
        fprintf(fid,'- 对%.0f Mbit/s，已有受支持工作点的最低已测试理想量化位数为%d；相应策略/功率范围见rate_requirements.csv。\n',req/1e6,minQ);
    end
end
fprintf(fid,'\nq仅为理想器件能力代理，不是ENOB、价格或完整ADC/整机功耗；固定输入范围[%.3g,%.3g]且没有AGC。\n\n',cfg.adc_range(1),cfg.adc_range(2));
fprintf(fid,'## 4 探测成本是否抵消加载收益\n\n');
paired=t.comparisons(t.comparisons.reliability_supported,:);
if isempty(paired)
    fprintf(fid,'尚无同条件/同校准的双策略正式受支持配对，不能给出已验证的净收益结论。\n');
else
    fprintf(fid,'有%d个同目标功率/q/校准的双策略受支持配对。名义分配比中位数%.6g（范围[%.6g,%.6g]），R_cycle比中位数%.6g（范围[%.6g,%.6g]）。\n', ...
        height(paired),median(paired.nominal_allocated_ratio),min(paired.nominal_allocated_ratio),max(paired.nominal_allocated_ratio), ...
        median(paired.cycle_allocated_ratio),min(paired.cycle_allocated_ratio),max(paired.cycle_allocated_ratio));
    fprintf(fid,'名义速率增量减去周期速率增量的中位数为%.6g Mbit/s；符号可正可负，未强迫加载具有正净收益。详细配对见strategy_comparisons.csv。\n', ...
        median(paired.nominal_gain_minus_cycle_gain)/1e6);
end
accepted=t.summary(t.summary.design_accepted,:);
if ~isempty(accepted)
    fraction=accepted.setup_link_symbols./(accepted.setup_link_symbols+accepted.cycle_payload_symbols);
    fprintf(fid,'实际接受表的链路训练/验证符号开销占比为[%.6g%%,%.6g%%]。R_cycle包括初始A0/B0及全部失败/成功候选A_r/D_r；两个payload统计重复不拼成2L。\n',100*min(fraction),100*max(fraction));
end
fprintf(fid,'\n纯TX功率校准不经过链路，计算量单列，不计光链路训练时长。控制时延理想设为0，反馈SNR标量、状态项与M条目分别计数；未声明序列化宽度，不虚构线路bit数。计时为本软件实现参考，不是ASIC功耗。\n\n');
fprintf(fid,'## 模型与证据边界\n\n');
fprintf(fid,'P_actual为含CP的实际归一化平均光功率，b不是实际功率；没有换算mW/dBm。归一化光能量/bit包括实际链路setup和一个payload周期，不是J/bit或整机能效。TX削波与ADC输入越界分开记录。\n\n');
fprintf(fid,'零观察误码具有非零Wilson上端点；逐点近似区间不是跨载波/轮次联合95%%保证。自适应升阶后BER不必随功率单调，未平滑或调整原始计数。代表诊断点固定P_target=1、q=8、cal=1，没有改选最好种子。\n\n');
fprintf(fid,'模型是固定热噪声和理想均匀量化的简化IM/DD等效链路，不包含实际光器件、完整色散、FEC、ARQ、真实反馈时延或整机能耗。\n');
end

function [meaning,unit]=describe(name)
meaning='原始记录派生字段；结合所属CSV及field_dictionary.md解释。';unit='dimensionless/status';
switch name
    case 'phase',meaning='formal正式或preflight独立预检；两者不混合。';
    case 'condition_id',meaning='固定P_target/q扫描条件编号。';unit='index';
    case 'calibration_id',meaning='独立共享初始A0/B0校准编号。';unit='index';
    case 'scheme',meaning='UniformAdaptive或ValidatedLoading，独立候选设计。';
    case 'payload_slot',meaning='固定独立载荷统计重复编号，不是会话长度乘数。';unit='index';
    case 'k',meaning='独立正频率数据载波数学编号。';unit='index';
    case 'q',meaning='理想ADC量化位数，不是ENOB/价格/功耗。';unit='ideal bits/sample';
    case {'P_target','P_target_selected','power_budget'},meaning='预先固定的归一化平均光功率目标或预算；不是b。';unit='normalized optical power';
    case {'P_actual','P_actual_min','P_actual_median','P_actual_max','actual_mean'},meaning='含CP样本实际mean(p)或跨实际载荷的统计量。';unit='normalized optical power';
    case 'b',meaning='由独立TX波形二分校准的偏置/驱动系数，不是实际mean(p)。';
    case 'P_actual_relative_dB',meaning='10*log10(P_actual/1)，未标定成dBm。';unit='relative dB';
    case {'M','bits_k'},meaning='最终或当前完整候选表的调制阶数M/每载波log2(M)。';
    case 'B_DMT',meaning='sum(log2(M_k))，仅独立载波，不重复计Hermitian镜像。';unit='bits/DMT symbol';
    case {'BER','overall_BER','worst_subcarrier_BER'},meaning='原始误码数除测试比特；总BER按总计数之比，非子载波BER均值。';
    case {'CI_low','CI_high'},meaning='z=1.96近似95%逐点Wilson区间端点。';unit='BER probability';
    case {'CI_upper_over_target','max_CI_upper_over_target'},meaning='逐点Wilson上端点/固定BER目标，或载波最大值。';
    case 'power_match',meaning='单载荷实际mean(p)相对目标偏差不超过冻结1%门槛。';unit='logical';
    case 'all_payload_power_match',meaning='该校准/策略全部实际payload均满足功率匹配；未完整时不得证明完整点。';unit='logical';
    case {'power_relative_error','relative_error'},meaning='(实际功率-目标功率)/目标功率；绝对值用于门槛。';unit='relative fraction';
    case 'R_cycle',meaning='一个L符号周期扣实际A0/B0及全部Ar/Dr的有效载荷速率，理想T_control=0。';unit='bits/s';
    case 'R_nominal',meaning='B_DMT/T_DMT，计CP但未扣训练与验证的名义数据段速率。';unit='bits/s';
    case 'R_required',meaning='最低业务速率要求，不表示各方案实际速率完全相等。';unit='bits/s';
    case {'sample_count','TX_lower_clip_count','TX_upper_clip_count','ADC_low_count','ADC_high_count'},meaning='包含CP时间样本的实际整数计数。';unit='samples';
    case {'TX_clipping_rate','ADC_out_of_range_rate'},meaning='分别为发射削波/ADC前越界次数除含CP总样本数，二者不可混同。';unit='fraction';
    case 'mean_p_squared',meaning='含CP的mean(p.^2)，不同于光功率均值mean(p)。';unit='normalized squared optical power';
    case 'AC_drive_mean_square',meaning='含CP的mean((b*x/(rho*sigma_ref)).^2)，仅统计不回缩放。';unit='normalized squared drive';
    case {'serialized_bits','serialized_control_bits'},meaning='未声明线路序列化宽度，固定为NaN；不把MATLAB内存字节当线路开销。';unit='not modeled';
    case 'supported_gain_eligible',meaning='仅正式、全部重复完成、BER-supported且所有payload功率匹配。';unit='logical';
    case 'all_rounds_supported',meaning='正式点全部预定校准均受支持及功率匹配，才可作实心支持点。';unit='logical';
    case 'rate_range_scope',meaning='范围包含所有已接受表；不是只取成功轮，也不是置信带。';
    case 'configuration_hash',meaning='实际ACK确认完整配置的规范SHA-256身份。';unit='SHA-256';
    otherwise
        if contains(name,'seed'),meaning='已预先登记的数据/噪声流种子；纯TX校准没有噪声流。';unit='RNG seed';
        elseif contains(name,'hash'),meaning='规范内容或原始字节SHA-256身份。';unit='SHA-256';
        elseif contains(name,'energy'),meaning='实际sum(p)/Fs的归一化光能量或注明的电样本平方和；不是物理J/bit。';unit='see field_dictionary.md';
        elseif contains(name,'compute_seconds'),meaning='实际当前软件计算耗时，排除导出/绘图，不是硬件功耗。';unit='seconds';
        elseif contains(name,'seconds'),meaning='按实际符号时长或预声明控制时延计的时间；见字段语义。';unit='seconds';
        elseif contains(name,'symbols'),meaning='实际/计划DMT符号数；传输时长按含CP的T_DMT。';unit='DMT symbols';
        elseif contains(name,'bits'),meaning='原始测试/错误整数比特计数，或明确注明的位数。';unit='bits';
        elseif startsWith(name,'R_')||contains(name,'delta_rate')||contains(name,'gain_minus'),meaning='跨实际已接受设计派生的名义或周期速率；min-max非CI。';unit='bits/s';
        elseif contains(name,'status')||contains(name,'state')||strcmp(name,'reason'),meaning='实际状态/原因；缺测和设计拒绝不填BER=0。';
        elseif contains(name,'entries')||contains(name,'scalars')||contains(name,'ACK_count'),meaning='显式理想控制对象条目数，未折算线路位数。';unit='entries/scalars/ACKs';
        end
end
end
