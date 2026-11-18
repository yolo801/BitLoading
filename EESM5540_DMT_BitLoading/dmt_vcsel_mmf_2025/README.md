# 2025 VCSEL–MMF DMT 选阶对照

分支 `experiment/dmt-vcsel-mmf-2025` 基于 `7a1331c1ee81c098bf6da071840474f8c73effb8`。两种策略共用实值 IM/DD DMT、公开 50 m 模型曲线的近似信道、三个摆幅工作点和统一的接收与 BER 判据。

## 已产生的信道证据

来源为 A. M. Rosa Brusin et al., *Comparing PAM and DMT for VCSELs-modulated Links over MMF*, SPPCom 2025, Fig. 2(a)，上传 PDF 的第 3 页。提取原生矢量路径中的 Case 1 和 Case 2，分别保留 121 与 471 个点，图示覆盖 0–120 GHz。Case 2 的虚线间隙和坐标校准单列在来源记录中。相位采用实值对称 FIR 的线性相位建模假设。[论文 DOI](https://doi.org/10.1364/SPPCOM.2025.SpTh3E.4) · [来源记录](evidence/Fig2a_provenance.json)

采用 128 GS/s、512 点 FFT、16 点 CP。两条信道共同激活 0.25–60 GHz 的 240 个正频率载波，保留 DC、Nyquist 和高频保护带。Case 1 用 9 抽头，活跃频点 RMS／最大误差为 0.117／0.319 dB。Case 2 用 17 抽头，误差为 0.129／0.439 dB，首个陷波由 24.213 GHz 拟合到 24.363 GHz。短横坐标差是按数字化路径和插值估计，原图虚线断点对真实陷波位置有更大的不确定性。源曲线与拟合曲线的回升分别为 3.742 与 3.485 dB，拟合回升峰频率为 40.375 GHz，源曲线为 43.838 GHz。CP 覆盖两条 FIR 的完整有限记忆。[方法图 PNG](evidence/Fig2a_Channel_Fit.png) · [可编辑 SVG](evidence/Fig2a_Channel_Fit.svg) · [FIR 系数](evidence/FIR_taps.csv) · [频点误差](evidence/active_response.csv)

两条公布曲线均为含端到端模型响应的归一化幅频模型。实验固定发端平均光功率目标 1，固定裁剪边界 [0, 2]、8-bit ADC 范围 [−0.1, 2.1] 和接收实噪声方差 1.0491e−4。模型时钟为 128 GS/s。速率、削波与 ADC 等指标用于仿真比较，课程报告中的物理范围限于该模型。

## 仿真与判据

若活跃载波数为 (K)，单位平均 QAM 能量下参考 DMT 交流 RMS 为 `sqrt(2*K/NFFT)`。发端把实际 DMT 时域波形乘以 `commanded_swing * P_target / (4*sigma_ref)`，再加候选表独立标定的偏置，通过固定裁剪边界后发送。命令摆幅 0.25／0.50／0.75 对应同一 ±4σ 参考。观测摆幅以含 CP 的裁剪后光功率样本 `(p99-p01)/(2*P_actual)` 表示，分位数取 4096 个等宽直方图区间的中点。逐块另记录裁剪前交流 RMS、PAPR、裁剪样本分数、ADC 越界分数与实际平均光功率。

UniformValidated 依次对整带 64-QAM、16-QAM、QPSK 做独立候选验证。PerToneValidated 从共享 B0 有效 SNR 提出初始表，每次将未获支持的频点降一级，最多验证三次。两种策略每次均独立标定偏置、估计信道、验证整表，再确认收发配置。拒绝的候选开销也计入。当前配置的控制延迟为理想的 0 秒。TX-only 计算和标定另报。

正式每轮每策略计划两段各 25,000 个 DMT 符号。两段仅用于该轮该表的 BER 合并，周期速率的载荷长度为 25,000。每载波 Wilson 上限均严格小于 10⁻³且载荷功率匹配才支持该轮。五轮全部支持才进入达标速率曲线。Case 2、0.50、8 bit 是预先固定的代表条件，子载波图使用第 1 轮。代表工作点的载荷长度曲线从冻结表和已发送设置时长重算。

## 运行方法

需要 MATLAB、Communications Toolbox 和 JVM。解压完整源码包，进入本目录。

```matlab
fit = run_dmt_vcsel_mmf_2025('channel-fit');
r = run_dmt_vcsel_mmf_2025('all');
```

`channel-fit` 核对已提取的来源、系数、频点误差和 Case 2 陷波。重新数字化和拟合的实际命令见下方。 `all` 依次执行生产链路预检、24 槽的 2,000 符号 pilot 和 120 槽的 25,000 符号正式计划。正式要求相同源码和模型的预检、pilot 有效回执。pilot 使用独立种子，数据仅用于核对流程和估算时间。未获支持的候选保留拒绝状态。

```matlab
pf = run_dmt_vcsel_mmf_2025('preflight');
pl = run_dmt_vcsel_mmf_2025('pilot','PreflightDirectory',pf.output_dir);
f = run_dmt_vcsel_mmf_2025('formal','PreflightDirectory',pf.output_dir, ...
    'PilotDirectory',pl.output_dir);
a = run_dmt_vcsel_mmf_2025('verify','OutputDirectory',f.output_dir);
images = run_dmt_vcsel_mmf_2025('redraw','OutputDirectory',f.output_dir);
```

用 `run_dmt_vcsel_mmf_2025('resume','OutputDirectory',folder)` 恢复指定的同版运行，已提交的校准、设计和载荷检查点直接核验并跳过。若在原子提交前中断，未完成的单元按冻结种子重跑。每批次写到独立 `results/dmt_vcsel_mmf_2025_*` 目录，包含原始检查点、源和种子清单、正式计数、实际设置事件和验证回执。正式后从审计表写英文 PNG／矢量 PDF、图注、中文说明和哈希清单。重绘从已校验的 CSV 读回数据，在原目录下另建输出子目录。

复现已完成的数字化和频响拟合需要 Python、PyMuPDF、NumPy、SciPy 与 Matplotlib。PDF 由用户提供。可以向独立目录写出复现数据。

```bash
python tools/digitize_fig2a.py "/path/to/2025_SPPCOM_DMTvsPAM.pdf" --output-dir "/path/to/new-evidence"
python tools/fit_fig2a.py --evidence-dir "/path/to/new-evidence"
```

云端 MATLAB 启动日志见 [matlab_attempt.log](validation/matlab_attempt.log)。模型拟合可独立复核。正式结果需由 MATLAB 实跑后产生。
