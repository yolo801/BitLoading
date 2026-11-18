# Fig. 7 文献频响对照

补充实验固定在归一化平均发射光功率 1.0、8 bit ADC。它考查基于公开实测幅度曲线的归一化等效信道下，验证式比特加载能否满足原 v2 的 BER 判据并获得高于固定 QPSK 的周期载荷速率。Fixed64QAM 保留为诊断对照。

## 当前执行状态

已经提取原始频响并完成 FIR 数值拟合和绘图。独立的 NumPy 索引检查通过。云端 MATLAB 启动返回 `matlab: command not found`，退出码 127。实际 MATLAB 收发预检、正式载荷和采集核验仍待执行。30 个计划槽位中，完成 0、正常设计拒绝 0、未完成 30。工作区中也缺少原 v2 正式基准目录。

- [实际启动日志](validation/matlab_attempt.log)
- [拟合结果与完整指标](evidence/fit_summary.json)
- [独立 NumPy 样本和索引检查](validation/independent_numpy_link_check.json)
- [冻结的计划种子表](validation/planned_seed_plan.csv)

## 频响来源与模型

原始资料为 K. Zhong et al., *Experimental study of PAM-4, CAP-16, and DMT for 100 Gb/s short reach optical transmission systems*, *Optics Express* 23(2), 1176–1189 (2015)，印刷页 1183 的 Fig. 7。PDF 第 8 页的图内曲线由 671×426 原生栅格保存，可直接提取蓝色轨迹。DOI [10.1364/OE.23.001176](https://doi.org/10.1364/OE.23.001176)。

518 个可读曲线点覆盖 0.111–30.036 GHz，映射为 0.113–30.512 MHz。以 63 GSa/s DMT 发端 AWG 和 64 MHz 仿真采样率做归一化频率映射。活跃载波 1–24 MHz 对应 0.984375–23.625 GHz，均在实测曲线覆盖内。接收示波器使用 80 GSa/s。原文报告的约 17 GHz 对应约 17.27 MHz。对归一化数字化轨迹独立读出首次 −3 dB 交点为 17.70 GHz，映射为 17.98 MHz。

纵轴为 S21（dB）。以首个近 DC 可见点的 −0.0263 dB 作为归一化参考，按 `10^(G_dB/20)` 转为电幅度比。归一化参考延至数学 DC 属于建模假设。提取 CSV 保留读到的曲线频率、原始 dB、归一化数据和栅格坐标。横轴读图误差估计为 ±0.0644 GHz。活跃频带内纵向读图误差估计中位数 0.211 dB、最大 0.474 dB，另有 0.079 dB 的低频参考读数误差。坐标锚点、完整覆盖带读数误差和 PDF SHA-256 见 [提取记录](evidence/Fig7_provenance.json)。

采用实值因果 9 抽头对称 FIR，DC 增益为 1，长度减一等于 CP 8 点。线性相位是建模假设。24 个活跃点的 RMS 误差为 0.330 dB，最大为 0.621 dB。全实测覆盖带的 RMS 误差为 0.511 dB，最大为 2.172 dB。新 FIR 在活跃频带的连续幅频响应最小为 −6.462 dB，频率为 24 MHz。拟合标准属于本补充实验。

| 频响 | −3 dB 带宽（仿真 MHz） | 24 MHz 相对增益（dB） |
| --- | ---: | ---: |
| 原三抽头 | 11.631 | −16.686 |
| Fig. 7 数字化 | 17.978 | −5.963 |
| Fig. 7 等效 FIR | 19.415 | −6.462 |

[英文频响对比 PNG](evidence/Channel_Response_Comparison.png) · [SVG](evidence/Channel_Response_Comparison.svg) · [FIR 系数](evidence/FIR_coefficients.csv) · [24 点误差](evidence/active_subcarrier_response.csv) · [全覆盖带误差](evidence/covered_frequency_response.csv)

## 用 MATLAB 运行

使用 GitHub 源码 ZIP 解压后的完整目录。模块依赖同一工作树中的原 v2 文件及其字节级源码哈希。运行时需要 MATLAB、Communications Toolbox 和 JVM。以下命令在 MATLAB 中执行，`cd` 到本说明所在目录后运行。

```matlab
cd('你的解压路径/EESM5540_DMT_BitLoading/tradeoff_v2/literature_fig7')
result = run_dmt_tradeoff_v2_fig7('BaselineDirectory', ...
    '原 v2 已通过验证的完整正式结果目录');
audit = verify_dmt_tradeoff_v2_fig7(result.output_dir)
```

暂时无法访问原正式基准时，可执行 `result = run_dmt_tradeoff_v2_fig7();` 以运行新信道。基准认证使用原 v2 验证器和回执，要求原始三抽头、相同正式配置、条件编号 9 的相同角色种子和源码版本 `418996d`。旧预检无法作为基准。

运行器在 `literature_fig7/results/tradeoff_v2_fig7_*` 新目录冻结拟合证据与配置。先复核曲线覆盖和误差限，再在实际生产收发函数上作无噪、无幅限事件、量化旁路的测试。检查包括 QPSK 训练的复数信道响应、1,024 符号块及后续 13 符号块的连续卷积状态、FFT 取样窗口和 ZF 符号恢复。随后基于新 FIR 每轮重新训练、选阶和验证。按原 v2 计划进行 5 轮、每轮 3 策略、每策略 2 槽，实际发送的一槽含 50,000 个 DMT 符号。所有角色种子和 v2 预先定义的配对保留。

结果目录保存 `Protocol.mat`、`seed_plan.csv`、`run.log`、原始检查点、`seed.csv`、`pool.csv`、`status.csv`、`summary.csv` 和 `verification_receipt.mat`。逐轮使用该轮两槽的逐子载波误码计数计算 95% 逐点 Wilson 近似区间。功率、BER 和采集状态分别保留。正常设计拒绝没有载荷与 BER。

通过采集验证后，输出 `channel_calibrations.csv` 和 `channel_summary.csv`。周期速率范围使用全五轮，仅在五轮均实际完成两个发送槽位时报告。比较的资格另外要求两种策略全五轮均达标且满足原 v2 配对功率规则。基准认证通过后，输出 `Subcarrier_Channel_Comparison.png` 和矢量 PDF，使用预先确定的正式第 1 轮展示 B0 有效质量、冻结比特加载表及 BER 上界／目标。

结果只适用于本工作点与两条等效响应。频响替换同时改变滚降程度与形状。论文通过光衰减器扫描接收光功率，这里控制归一化发射光功率，并包含模型内发射削波。

## 重现数字化与拟合

在模块目录中执行。数字化脚本需要 PyMuPDF、NumPy 和 Pillow，拟合脚本需要 NumPy、SciPy 和 Matplotlib。论文 PDF 由用户提供，附带证据已经可直接交给 MATLAB。

```bash
python tools/digitize_fig7.py "/path/to/Zhong2015.pdf" --output-dir evidence
python tools/fit_fig7_fir.py --evidence-dir evidence
python validation/check_cp_fir_numpy.py evidence/fit_summary.json
```
