# EESM5540 — DMT Bit Loading

这是作者的**简化 DMT 数字基带 Monte Carlo 仿真**。它比较：在相同的独立数据子载波集合、采样率、符号周期、平均电符号能量和接收噪声条件下，按估计子载波质量选择 QAM 阶数，能否在逐子载波 BER 目标内承载更多载荷比特。

**当前状态：未在 MATLAB 执行。** 当前云环境没有可用的 MATLAB，也没有 Octave。本目录提供 MATLAB 实现与运行说明；现阶段没有 MATLAB 实测 BER、正式统计结论或可用于报告的实验结果图。执行状态见 [EXECUTION_STATUS.md](EXECUTION_STATUS.md)。解析预期不能替代测量，其他语言的公式核对也不能证明 MATLAB 收发链路通过。

## 模型、边界和依赖

代码执行 Hermitian 映射、单位酉 IFFT、CP、时域串行 FIR 线性卷积、接收端实高斯噪声、去 CP、单位酉 FFT、独立训练与探测、ZF 均衡和逐位 Gray QAM 解调。负频点仅携带正频点的共轭镜像，不重复计入独立比特。

FIR 只代表一个简化端到端电域低通频率响应，不是器件实测响应，也不是完整光链路物理模型。不包含激光器、光探测器、光功率、直流偏置、削峰、量化、非线性、色散、FEC、功率加载或 PAPR 研究。本实验不复现 100 Gb/s 光学硬件实验，也不完整复现 Chow 的含能量调整算法。PAPR 限制仍应根据报告引用的文献讨论。

目标兼容 **MATLAB R2026a，Base MATLAB + Communications Toolbox**。需要 `qammod`、`qamdemod`；不需要 Statistics and Machine Learning Toolbox、Parallel Computing Toolbox、GPU 或其他付费工具箱。程序串行运行，不创建 `parpool`。`Q(x)` 用 `0.5*erfc(x/sqrt(2))` 计算。

本目录是独立项目，直接从该目录运行；无需 `savepath` 或修改 MATLAB 全局路径。原报告、abstract、ISAC 及其他项目不属于修改范围。历史结果保留，每次运行使用新的结果目录。

交付时的方法和答辩说明见 [report_notes_zh.md](report_notes_zh.md)，明确标为未执行；实际运行的观察说明将另存到该次结果目录。

## 冻结规格 v1.0

| 项目 | 固定值与口径 |
| --- | --- |
| FFT、CP | `NFFT=64`，`NCP=8` |
| 采样率 | `Fs=64e6` Hz |
| 独立数据子载波 | 数学 `k=1:24`，MATLAB 行 `k+1`，频率 1–24 MHz |
| 其余频点 | DC、Nyquist、未用频点为零；行 `NFFT-k+1` 为共轭镜像 |
| 因果实 FIR | `h=[0.25 0.5 0.25]`，直流增益 1，不做滤波器能量归一化 |
| 平均电符号能量 | 各独立数据子载波 `Es=1` |
| QAM | `Mset=[4 16 64]`，Gray，`UnitAveragePower=true` |
| 接收时域实噪声方差 | `sigma_w2=10^(-29/10)=0.0012589254117941675` |
| 参考量 | `rho_ref=Es/sigma_w2=29 dB`，不是波形 SNR、Eb/N0 或 OSNR |
| BER 目标、加载裕量 | 未编码逐子载波 `1e-3`，`margin_dB=1` |
| 训练 A | 1024 个已知 QPSK DMT 符号，用于 LS 信道估计 |
| 探测 B | 独立 2048 个已知 QPSK DMT 符号，用于残差质量估计 |
| smoke | 每方案 2000 个载荷 DMT 符号，不进入正式计数 |
| 正式测试 | 种子标签 `[11 22 33]`，每方案每标签 100000 个载荷 DMT 符号 |
| 分块 | 每块最多 2000 个符号，串行，不保存长期全波形 |

两方案固定使用全部 24 个独立子载波，不关闭弱子载波，不重新分配能量，不改变接收噪声。若任一子载波按规则连 QPSK 都不可用，程序保留诊断并报告当前规格不可行。

## 运行方法

先把整个目录放到有上述许可的 MATLAB 机器。Windows MATLAB 命令窗口示例：

```matlab
cd('C:\work\BitLoading\EESM5540_DMT_BitLoading')
smoke = run_dmt_experiment('smoke');
% 检查 smoke 目录的日志、自检、数据表和图，然后运行固定正式实验：
result = run_dmt_experiment('main');
```

MATLAB `-batch` 示例，按实际目录调整路径：

```powershell
matlab -batch "cd('C:/work/BitLoading/EESM5540_DMT_BitLoading'); run_dmt_experiment('smoke')"
matlab -batch "cd('C:/work/BitLoading/EESM5540_DMT_BitLoading'); run_dmt_experiment('main')"
```

Linux/macOS 示例：

```sh
cd /path/to/BitLoading/EESM5540_DMT_BitLoading
matlab -batch "run_dmt_experiment('smoke')"
matlab -batch "run_dmt_experiment('main')"
```

不使用 `try/catch` 吞掉外层错误；批处理失败应保留非零退出状态。运行耗时取决于机器和 MATLAB 版本，程序不根据 BER 临时延长测试或改变种子。

`smoke` 执行环境记录、无噪声基础链路自检、一次训练/探测及 profile 冻结，再运行每方案 2000 个符号并检查输出。`main` 先完成同样的 smoke，随后在**同一次冻结校准和 profile 下**执行 6 次正式载荷测试。main 内部 smoke 与正式统计分开存储；独立的 smoke 调用也不进入 main 的计数。入口的返回值用于定位本次结果和状态，详细内容以目录内日志、快照和表格为准。

`main` 内部的 smoke 表格、图及说明位于当次目录的 `preflight_smoke/`；正式结果位于当次目录根部。`runs_partial.mat` 与 `final_results.mat` 也会把 `smokeRuns` 和正式 `runs` 分开保存。

## 接收机、加载与公平性

发送变换为 `x=sqrt(NFFT)*ifft(X,[],1)`，先检查虚部仅为浮点舍入量，再取实部。接收为 `Y=fft(y,[],1)/sqrt(NFFT)`。CP 复制每个符号最后 8 个样本。含 CP 的符号按列串行化，通过 `filter(h,1,txSerial)`；同一测试运行跨块保留滤波器状态，新的独立运行可重置。CP 8 大于 FIR 记忆 2，首个有用符号也受完整保护。按已知符号起点去 CP，不额外补偿群时延。

噪声在 FIR 后加入：`sqrt(sigma_w2)*randn(...)`。不用 `awgn(...,'measured')`，不按随机块功率归一化，不对不同 QAM 阶数重算噪声。单位酉 FFT 后，各正频点复噪声的 `E|W_k|^2=sigma_w2`，实部和虚部各为其一半。

训练 A 给出逐子载波最小二乘估计：

```text
H_hat = sum(Y_A .* conj(X_A), 2) ./ sum(abs(X_A).^2, 2)
Z_B = Y_B ./ H_hat
gamma_hat = sum(abs(X_B).^2, 2) ./ sum(abs(Z_B-X_B).^2, 2)
gamma_eff = gamma_hat / 10^(margin_dB/10)
```

探测 B 与 A 独立。这个教学残差估计包含有限信道估计误差，不等于某论文的具体质量估计器。正式载荷不参与重新估计或调参。`fft(h,NFFT)` 只用于诊断，不替代正式接收机和加载器的 `H_hat`。

采用常用近邻近似：

```text
Pb(M,gamma) = 4/log2(M) * (1-1/sqrt(M)) * Q(sqrt(3*gamma/(M-1)))
```

Loaded 在每个子载波上选择满足近似目标的最大 M；Uniform 选择能在全部 24 个子载波上同时满足同一规则的最大公共 M。两者共享估计、集合、Es、时序、信道和噪声方差。接收端预先知道 profile，反馈无误，反馈开销未建模。改变的只有比特加载。

## 随机流与可复现性

数据与噪声使用独立 `RandStream('mt19937ar',...)`，不依赖命令窗口的全局 `rng` 状态：

| 阶段 | 数据种子 | 噪声种子 |
| --- | --- | --- |
| 训练 A | 1701 | 2701 |
| 独立探测 B | 1702 | 2702 |
| smoke / 正式载荷 | 下述映射的 `+1` | 下述映射的 `+2` |

载荷映射为 `base + 1000*schemeIndex + 10*label + offset`。`schemeIndex=1` 为 Uniform，`2` 为 Loaded；main `base=100000`、`label=11,22,33`；smoke `base=300000`、`label=0`；数据 `offset=1`、噪声 `offset=2`。基础自检使用训练种子 1601、三种 QAM 载荷种子 1611/1612/1613，以及噪声方差检查种子 1609。本次实际映射写入 `seed_mapping.csv`。不同方案允许使用独立载荷数据和噪声流，分布与固定噪声方差相同。固定分块大小是可复现配置的一部分，不承诺修改 chunk 大小后载荷序列逐样本相同。

## 分阶段验证与统计解释

基础自检必须在正式统计前通过，包括：三种 QAM 的无噪声训练估计、均衡和零观察误码；Hermitian 关系；IFFT 虚部；CP 长度；FIR 线性卷积对应的 `Y=H_true.*X`；单位酉 Parseval 能量；独立实噪声经 FFT 的正频点复方差。自检输出实际数值、容差与通过状态，不只写 “all passed”。失败时保留目录并停止，不跳过失败继续正式统计。

数值容差见 `private/dmt_self_checks.m`：线性卷积关系绝对误差不超过 `1e-11`，Parseval 不超过 `1e-10`；独立 20000 符号噪声诊断的复方差最大相对偏差不超过 4%，实/虚分量各不超过 5%。这些是检查程序错误的容差，不用于调整 BER 验收。载荷能量与理论期望的相对偏差容差为 smoke 10%、main 2%，不会据此归一化或改变 Es。

逐子载波 BER 为 `error_bits/tested_bits`，总 BER 为总错误比特除以总测试比特，不能平均不同比特数子载波的 BER。使用 `z=1.96` 的逐点 95% Wilson 二项近似区间，正式判断基于 3 个 seed 的汇总计数：

- 全部独立子载波区间上界均低于 `1e-3`：该固定 profile 和模型下的统计证据支持。
- 任一子载波区间下界高于目标：该方案未满足目标。
- 其他情况，包括区间碰到或跨越目标：证据不足。

两方案各自的目标判断与 Loaded 是否携带更多 bits/DMT symbol 分开核对；只有两方案目标均受支持且 Loaded 的 B 更高时，才支持题设的比较结论。Wilson 区间不是所有子载波的 95% 联合置信保证，也不是独立重复初始化下的鲁棒性验证。

零误码记录为 `0 observed errors / n tested bits` 并给出上界，不能声称真实 BER 为零。对数图用专用符号在区间上界标记零观察误码，不人为添加极小的“实测 BER”。加载方案的 BER 不必低于 Uniform：更高阶 QAM 用更密集星座换取载荷，目标是在约束内提高 B，不是最小化 BER。

## 能量和速率单位

归一化电能量的理论期望是：有用段每符号 `2*24*Es=48`；平均输入时域功率 `48/64=0.75`；CP 段期望能量 `6`；含 CP 每符号期望能量 `54`。表格记录各方案实际有用段、CP、含 CP 平均能量和功率，有限样本允许小幅偏差，不人为缩放。它们不能证明光学发射功率或峰值功率公平。

`Tu=1 us`，`TCP=0.125 us`，`Ts=1.125 us`；`B=sum(log2(M_k))` 只计独立正频点；`R_payload=B/Ts` 是**已计 CP 时间的未编码载荷速率**。不能再扣一次 CP，也不能称为含全部开销的净吞吐量。一次初始化的 3072 个 DMT 符号持续 `3.456 ms`，另列为非载荷开销，不包含在该速率中；反馈和 FEC 开销同样未扣除。

仅用于诊断的解析参考是 `H_true(k)=exp(-j*2*pi*k/64)*cos(pi*k/64)^2`、`gamma_true=cos(pi*k/64)^4/sigma_w2`。理论子载波 SNR 范围约 12.3135864–28.9790623 dB。若用理论而非估计 SNR 选阶，预期 64-QAM 的 k1:15、16-QAM 的 k16:20、QPSK 的 k21:24，共 118 bits/DMT symbol；理论 Uniform 为 48，比率约 2.4583，速率约 104.8889 和 42.6667 Mbit/s。**这些是解析诊断值，不是实验结果或硬性验收值。** k21 靠近边界，有限探测可能选择 16-QAM；输出必须服从实际估计，不能手工改为 118。平均输入波形 SNR 的理论参考约 27.7506 dB，与 `rho_ref=29 dB` 不同。

## 输出文件与历史保留

每次运行写入 `results/<timestamp>_<mode>_<unique suffix>/`，不覆盖既有目录。失败保留已写入的快照、日志和诊断；不会删除失败运行来伪装首轮成功。文件在执行到对应阶段后产生，MATLAB 未执行时不会预制带伪数据的文件。

| 文件 | 内容 |
| --- | --- |
| `config_snapshot.mat` | 冻结规格、种子及运行配置 |
| `environment.txt`、`run.log` | 实际版本、依赖检查、调用模式、时间和运行日志 |
| `seed_mapping.csv` | 校准、探测及载荷数据/噪声随机流映射 |
| `initialization.mat` | 冻结 `H_hat`、`gamma_hat` 与两种 profile、诊断量 |
| `verification_checks.txt` | 逐项自检、比较条件、数值及容差 |
| `runs_partial.mat` | 已完成运行的累计计数检查点；失败时也保留 |
| `final_results.mat` | 完成运行后的汇总 MATLAB 数据 |
| `per_subcarrier_results.csv` | 每 seed 和 pooled 的子载波计数、BER、Wilson 区间 |
| `summary.csv` | 方案 B、载荷速率、总计数/BER、最差 BER、统计状态、实际能量与测试时长 |
| `dmt_comparison.png/.pdf/.fig` | 估计 SNR、比特分配、BER 与逐点区间；PNG 至少 300 dpi，PDF 为矢量 |
| `report_notes_zh.md` | 本次真实观察的中文说明、局限与三个答辩问题 |
| `results_paragraph_en.txt` | 本次真实结果的约 150–200 词英文段落与简洁图注 |
| `failure_status.txt` | 发生异常时的错误及堆栈；存在失败记录不等于完成正式实验 |

`per_subcarrier_results.csv` 的字段包括 `scheme, seed, k, frequency_Hz, SNR_est_dB, M, bits_per_symbol, tested_bits, error_bits, BER, CI_low, CI_high`。`seed=pooled` 行用于正式验收。smoke 数据明确标记，仅用于程序验证；即使 smoke 区间看起来有利，也不替代固定的正式测试。

`summary.csv` 的 `statistical_status` 值为 `supported_fixed_profile`、`failed_target` 或 `insufficient_evidence`；smoke 为 `smoke_only_not_formal_evidence`。状态只反映该方案的逐子载波目标判断，比较结论还必须核对 Loaded 的 B 是否更高。

## 报告使用和参考

在已有报告中保留 Figure 1 收发框图，实际运行后用本项目的组合图替换纯解析 Figure 2；报告仍需不超过 4 页、汇报约 4 分钟。程序不自动修改原报告或 abstract。组合图中的 bits 面板表示比特分配，不表示功率分配；不能称数据来自文献 Figure 6。引用时写“作者的简化数字基带仿真”。

目前可写的只有模型与方法描述，以及明确标为解析诊断的量；未执行前不能写“仿真表明加载满足 BER 并提高吞吐量”。真实运行后，根据 `summary.csv` 和逐子载波区间决定能否写该固定校准、profile 和模型下的受限结论；若失败或证据不足，保留并准确报告。

以下文献提供背景/方法，不代表冻结参数来自它们：

1. K. Zhong et al., “Digital Signal Processing for Short-Reach Optical Communications: A Review of Current Technologies and Future Trends,” JLT 36(2), 377–400, 2018. DOI: 10.1109/JLT.2018.2793881.
2. W. Xia et al., “A Survey on Data Center Networking (DCN): Infrastructure and Operations,” IEEE COMST 19(1), 640–656, 2017. DOI: 10.1109/COMST.2016.2626784.
3. P. S. Chow, J. M. Cioffi, J. A. C. Bingham, “A Practical Discrete Multitone Transceiver Loading Algorithm for Data Transmission over Spectrally Shaped Channels,” IEEE TCOM 43(2–4), 773–775, 1995. DOI: 10.1109/26.380108.
4. K. Zhong et al., “Experimental Study of PAM-4, CAP-16, and DMT for 100 Gb/s Short Reach Optical Transmission Systems,” Optics Express 23(2), 1176–1189, 2015. DOI: 10.1364/OE.23.001176.

MATLAB 官方参考：[qammod](https://www.mathworks.com/help/comm/ref/qammod.html)、[qamdemod](https://www.mathworks.com/help/comm/ref/qamdemod.html)、[CP、卷积与均衡](https://www.mathworks.com/help/comm/gs/equalization-convolution-and-cyclic-prefix-addition.html)。

## 本次云端检查的证据

`validation/python_diagnostics.txt` 记录了 75 项独立数学关系及源码约定检查。可选诊断命令为 `python3 tools/verify_implementation.py`，需要 Python + NumPy；它不是 MATLAB 运行依赖，也不测 QAM BER，不生成本实验数据。`validation/matlab_static_lint.txt` 是 MISS_HIT 0.9.44 对 16 个 `.m` 文件的语法/静态检查输出；其通过不代表 MATLAB 执行、许可或图导出已经验证。实际命令和工具探测结果见 [validation/commands_and_scope.md](validation/commands_and_scope.md)。
