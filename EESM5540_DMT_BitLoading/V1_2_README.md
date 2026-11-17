# v1.2：固定参考图与独立校准重复试验

物理规格仍为1.0；新增研究协议为1.2。原`run_main`、v1.1正式统计和历史文件保留。新流程只研究同一固定电域FIR下的校准/选阶稳定性，不扩展成跨信道、光器件、功率加载或SNR扫描研究。

## 当前真实执行状态

本次代码已实现，但**未在MATLAB执行，新增正式组数为0/90**。当前聊天没有可调用的MATLAB MCP，云端未找到`matlab`程序。用户提供的reference 0路径位于Windows本机，当前云文件系统不可直接访问，尚未核实该目录数据或生成新正式图。最终启动诊断和验证记录见`EXECUTION_STATUS.md`及`validation/`。

不能用包内`evidence/imported_smoke/`替代reference 0。提示词给出的48/120/96或最大归一化上端点仅是待核对信息，代码不硬编码这些结果。

## 一次完成A和B

在有MATLAB R2026a、Communications Toolbox及正常JVM的机器，进入此项目目录。用户指定的参考路径为：

```matlab
refDir = 'C:\Users\Lenovo\Documents\MATLAB\BitLoading-07082cb7bdb034357bc80da358a5f3ec5d411c48\EESM5540_DMT_BitLoading\results\20261116_194846_246_main_tp96b36639_d14e_4dbc_8956_3651acfb6fa8';
result = run_v1_2(refDir);
```

入口先只读验证并重绘reference 0，然后执行10轮全新校准和90组固定载荷，最后独立检查实际计数。新结果保存在项目`results/`下的两个独立目录：`v1_2_reference_0_*`及`v1_2_study_*`，不会写入参考目录。

如果原参考目录恰好位于当前项目`results/`下且目录名不变，可直接输入`run_v1_2`；否则明确传入`refDir`。

## 分步入口与恢复

```matlab
figResult = redraw_dmt_constraint_check(refDir);
study = run_dmt_calibration_study('main','NumCalibrations',10, ...
    'ReferenceDirectory',refDir);
check = verify_dmt_calibration_study(study.output_dir);
```

任务B也能在不提供ReferenceDirectory时独立执行，但不会声称任务A完成，不会重建或猜测reference 0。完整结果段会明确参考数据不可用。

中断后，先确认原MATLAB进程是否仍在运行并观察原`run.log`；等待超时不代表它已停止。进程确已退出时，用原目录恢复：

```matlab
study = run_dmt_calibration_study('main','NumCalibrations',10, ...
    'ResumeDirectory','C:/work/results/v1_2_study_existing', ...
    'ReferenceDirectory',refDir);
```

同一目录使用操作系统文件锁，阻止两个进程并发恢复。只跳过配置、源码、种子映射、校准/profile标识、计数哈希和100000实际符号全部核对一致的完整组。旧部分或损坏记录移入带时间标记的`.rejected_*.mat`，按同一固定种子完整重跑；绝不把旧部分计数加到重跑计数上。源码或科学配置变化会阻止恢复，应保留旧目录并用独立目录处理新版本。

## 不变的模型与新随机流

NFFT64、CP8、Fs64MHz、k1:24、因果FIR`[0.25 0.5 0.25]`、各独立子载波星座平均Es1、实接收噪声方差`10^(-29/10)`、BER目标`1e-3`、裕量1dB保持不变。单位酉FFT、真实CP/FIR、训练估计的ZF、Gray QAM、无帧功率重归一化及全部24载波沿用原实现。

新calibration_id为1…10，reference 0不计入十轮。每轮重新调用训练/探测：A1024个、独立B2048个QPSK DMT符号；载荷不参与估计或选阶。之后三策略共享本轮冻结估计/profile。每策略三个标签11/22/33，各100000符号，分块2000，串行，不使用parpool/GPU或全长波形数组。

新流映射严格为：

```text
base = 2000000 + 100000*calibration_id
A data/noise = base+101 / base+102
B data/noise = base+201 / base+202
scheme s = Uniform1, Loaded2, Fixed16 3
label 11/22/33 对应 slot j=1/2/3
payload data/noise = base+1000*s+10*j+1 / +2
```

10轮共有220个不同随机流种子，与旧训练、旧载荷和自检流均不冲突。原v1.1的标签映射不变；新映射通过`dmt_simulate`可选显式流参数使用，收发数学链路没有另建一套实现。

## Figure 2(c)的精确含义

图(a)(b)在上方并排，(c)在下方通栏，三者均来自同一个预先指定的reference 0。

每个点都由正式pooled误码/比特计数重新计算逐点95% Wilson近似区间，并绘制`u=CI_high/targetBER`。纵轴对数、判据线1，全部24点保留；零误码仍有非零上端点。不混入BER点估计、误差棒或零误码三角。

`u<1`仅表示通过本次上端点判据，不保证真实BER必然低于目标。`u>=1`是未通过，只有`CI_low>targetBER`才有区间证据判为失败；跨线或刚好触线为证据不足。三条曲线不能用来比较真实BER大小；零误码平台也可能只是测试比特数相同。

输出`figure2_constraint_check.png`（300dpi）、矢量PDF和FIG，支持时加SVG。原完整BER+区间图在原参考目录保留。所有面板白底黑字，约6.7英寸宽；图注说明逐点近似不等于全部子载波联合95%覆盖。

## 统计层级与不可行轮

统计层级为`calibration_id → scheme → payload_seed → k`。只在同一轮/策略/载波内合并三个载荷种子；总观察BER按总错误/总比特加权。不混合十个profile的比特来证明每个profile合规，也不把十轮上端点均值称为新置信上界。

每个完整可行策略的唯一状态按以下优先级：任一`CI_low>target`为`failed`；否则全部`CI_high<target`为`supported`；其余为`inconclusive`。缺失载荷为`incomplete`，没有用0填补缺失BER。

若某轮连QPSK都无法满足选阶条件，本实现将其记为**匹配比较协议不可行**，保留该轮估计和原因，九组不执行、不替换该轮，并继续其余轮。三个汇总行的`infeasible`表示本轮协议未运行，不表示Fixed16星座在物理上无法发送。正常可行轮中，Fixed16的BER不达标绝不会导致停止或丢弃数据。

选阶次数每轮只计一次，不按三个载荷种子重复。`profile_frequency.csv`对每个scheme/k列出三个M的`selection_count`；三者之和加一次`infeasible_count`和一次`uncalibrated_count`应为10。后两列在三个M行重复显示，不可再按M相加。

10/10只是本次十轮观察，不代表未来成功概率100%。可选稳定性图只显示实际轮次数据及范围，不称95%置信带。主Figure 2固定使用reference 0，不挑最好一轮。

## 实际完成后输出

| 输出 | 全部可行并完成时 |
| --- | --- |
| `per_calibration_seed.csv` | 2160行，只有真实完整组的逐载波计数 |
| `per_calibration_pooled.csv` | 720行，只在同一轮内合并 |
| `per_calibration_summary.csv` | 30行，缺失/不可行明确状态及NaN |
| `robustness_summary.csv` | 每策略一行，五种状态轮数及B/速率/承载比范围 |
| `profile_frequency.csv` | 各scheme/k/M的按轮选阶次数，另列不可行/未校准次数 |
| `per_calibration_profile.csv` | 每轮冻结估计质量、M、B及载荷速率 |
| `calibrations/calibration_01.mat`…`10.mat` | 十份真实新校准、配置和初始化标识 |
| `groups/cal_01_Uniform_seed_11.mat`等 | 最多90份完整计数检查点，各自有源码/配置/校准/计数哈希 |
| `completion_check.txt` | 90个计划组的真实完成或不可行状态，不靠mainSymbols判完成 |
| `final_study_results.mat` | 实际计数、轮记录、独立统计及实际完成数 |
| 配置、种子、源码/参考输入清单、日志与文献映射 | 实际运行来源和核对证据 |
| 中文说明及英文结果段 | 英文仅在90组真实完成后生成，150–220词 |

reference 0的实际结果会单独列为`reference_summary.csv`，不混入新十轮。载荷速率B/Ts已含CP，未扣初始化、反馈或FEC，不称完整净吞吐量。可选`calibration_stability`诊断图不自动加入四页报告。

## 文献边界

见`docs/literature_mapping.md`和`docs/literature_access.json`。本次原文/元数据访问在代理隧道阶段遇到403，尚未独立核实三篇PDF指定段落；定位与方法边界明确标为提示词提供，未声称已读原文。

固定Es的近邻BER选阶不是完整Chow能量调整算法；BER近似也不是直接摘自Chow的SNR-gap公式。Fig.6绿色矩形表示功率，不是比特。QPSK探测是简化教学选择，不复现100Gb/s硬件探测。10轮、训练长度、裕量、目标、Wilson及新图都是项目预设。文献编号仍为[1][3][4]，背景[2]不改动。不覆盖报告、摘要或Figure1。
