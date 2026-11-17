# EESM5540 — DMT Bit Loading 与 tradeoff_v1 权衡实验

最新新增功率／ADC／速率／协议代价研究入口为 `run_dmt_tradeoff('all')`，详见 [TRADEOFF_START_HERE.md](TRADEOFF_START_HERE.md)。本轮交付代码，由用户本地运行MATLAB；新增代码未在MATLAB执行。真实机械预检和独立预检通过后，入口才冻结Protocol并继续正式矩阵。所有新结果进入独立目录。代码交付状态见 [CODE_DELIVERY_STATUS.md](docs/tradeoff_v1/CODE_DELIVERY_STATUS.md)。

以下保留v1.3及更早版本说明，用于历史复核。

v1.3入口为`run_dmt_v13('all')`，独立核对为`verify_dmt_v13('all','ResultDirectory',outDir)`。该版含显式SNR反馈、Tx/Rx配置副本与ACK、独立C探测和四场景固定预算，完整说明见[V1_3_README.md](V1_3_README.md)。原线性物理规格1.0及旧v1.1/v1.2入口、结果均保留。该版执行量及原始错误见`EXECUTION_STATUS.md`；代码和计划不代表360组已经运行。

以下保留v1.2及v1.1说明，不能当成新v1.3运行证据。

新增v1.2入口为`run_v1_2(referenceDir)`：固定reference 0同源重绘`CI_high/targetBER`，再执行十轮全新校准、90组固定载荷。详细规则、恢复及输出见[V1_2_README.md](V1_2_README.md)。原v1.1主实验接口和历史结果保留，物理规格始终为1.0。云端尚未执行v1.2，当时执行状态保留于`docs/HISTORICAL_EXECUTION_STATUS_before_v1_3.md`。

下文保留原v1.1单校准主实验说明，便于复核reference 0；新增研究不复用旧profile作为十轮新校准。

这是作者的**简化 DMT 数字基带 Monte Carlo 仿真**：检验在相同独立子载波、平均电符号能量、采样率、符号时间和接收噪声条件下，按估计质量加载 QAM 阶数，能否在逐子载波 BER 目标内承载更多比特。协议为 **1.1**，物理参数规格仍为 **1.0**。

项目路径 `/workspace/BitLoading/EESM5540_DMT_BitLoading/`，入口 `run_dmt_experiment.m`。在项目目录直接运行，无须修改全局路径。使用现有源码增量修改，没有另建第二套算法，不改动 ISAC、原 report、abstract 或 Figure 1。

**本次交付范围是代码，由你在本地 MATLAB 执行实验。** 从项目目录输入 `result = run_main;`，会自动完成主实验并核对实际九组计数。最短操作见 [START_HERE.md](START_HERE.md)。这份新增代码未在MATLAB执行；静态检查和Python诊断的范围见[执行状态](EXECUTION_STATUS.md)。历史本地smoke保存于 `evidence/imported_smoke/`，不会进入新main统计。

## 历史 smoke 的真实范围

上传配置与完成日志标记为 smoke，每方案 2000 个载荷 DMT 符号：

| 历史策略 | B，bits/DMT symbol | R_payload，Mbit/s | 观察误码 / 测试比特 | 总 BER |
| --- | ---: | ---: | ---: | ---: |
| Uniform | 48 | 42.6667 | 0 / 96000 | 0 observed |
| Loaded | 120 | 106.6667 | 10 / 240000 | 4.1667e-5 |

历史 Loaded 为 k1:15 采用64-QAM、k16:21采用16-QAM、k22:24采用QPSK。k21 的实际估计 SNR 约17.5554dB，靠近选阶边界；120 是由实际估计得到的合法结果，不应改成解析示例118。

这不是三个种子、每种子100000符号的正式统计。旧 CSV 的 seed=0 和 pooled 是同一批数据的两个层级，不能相加。不能仅去掉旧图的 smoke 标题就用于正式报告。历史14个文件按原字节保留，`evidence/imported_smoke/import_manifest.csv` 记录上传ID、字节数及SHA-256；新结果使用独立目录，不覆盖、重命名或删除旧输出。历史导入的英文段落也不代表完成 main。上传证据复核见 `validation/uploaded_smoke_audit.md`（Python读取已有结果，不执行 MATLAB）。

## 依赖与模型边界

目标兼容 **MATLAB R2026a，Base MATLAB + Communications Toolbox**，需要 qammod/qamdemod 与有效许可。SHA-256 使用 MATLAB 随附 Java，正常 JVM 模式启动，不加 `-nojvm`。不需要其他额外付费工具箱、parpool 或 GPU；Q函数用 Base MATLAB 的 erfc 计算。

链路包含 Hermitian 映射、单位酉 IFFT、CP、时域串行因果 FIR、接收实高斯噪声、去 CP、FFT、独立训练/探测、ZF 和逐位 Gray QAM 解调。负频点只放共轭，不再计入比特。

FIR 是教学用端到端电域低通响应，不是实测器件或完整光链路。未增加光器件、直流光偏置、光功率、削峰、量化、非线性、色散、FEC、功率加载、PAPR、SNR扫描或机器学习。不声称复现光学硬件、100Gb/s光传输或完整Chow能量调整算法。PAPR限制仍引用原报告文献。

## 冻结物理规格 v1.0

| 项目 | 固定值及口径 |
| --- | --- |
| FFT、CP、采样率 | NFFT=64、NCP=8、Fs=64e6Hz |
| 独立数据子载波 | 数学k=1:24、MATLAB行k+1、频率1–24MHz |
| 频点映射 | DC、Nyquist及未用频点为0；行NFFT-k+1放共轭镜像 |
| 因果实FIR | h=[0.25 0.5 0.25]，DC增益1，不做能量归一化 |
| QAM及能量 | Gray、Mset=[4 16 64]、UnitAveragePower=true、每独立子载波平均Es=1 |
| 接收实噪声方差 | sigma_w2=10^(-29/10)=0.0012589254117941675 |
| 参考量 | rho_ref=Es/sigma_w2=29dB，不是波形SNR、Eb/N0或OSNR |
| 逐子载波BER目标、裕量 | 1e-3、1dB |
| 训练A / 独立探测B | 1024 / 2048个已知QPSK DMT符号 |
| smoke | 每策略2000个载荷符号，不进入正式统计 |
| main | 标签[11 22 33]，每策略每标签固定100000个载荷符号 |
| 执行与内存 | chunkSize<=2000、串行，只累计计数和能量、不存长期全波形 |

所有策略固定使用相同24个独立子载波，不关闭弱载波、不转移能量、不改变噪声或样本数以求通过。若QPSK也不可行，保留诊断并报告当前规格不可行。

## 三个策略

| 策略 | 用途及定义 |
| --- | --- |
| Uniform | 正式基线：全部24个载波均满足保守规则的最高公共M，不硬编码QPSK。 |
| Loaded | 正式待验证方案：逐载波选择满足相同保守规则的最高M，不硬编码118或120bits。 |
| Fixed16 | 诊断对照：全部24个载波16-QAM、平均Es仍为1，解释统一提高阶数的误码代价。 |

Fixed16按定义承载96bits/DMT symbol、计数载荷速率85.3333Mbit/s；BER及合规性必须测量，不能硬编码失败。其超标不是实现错误，不得删除策略或中止其余测试。未验证合规的速率不能称为满足可靠性约束的吞吐量。

三策略共享H_hat、子载波集合、Es、时序、信道和噪声分布；接收端已知profile、反馈正确且开销未建模。改变的是比特分配，不做功率加载。

## 运行方法与校准复用

Windows MATLAB命令窗口：

```matlab
cd('C:\work\BitLoading\EESM5540_DMT_BitLoading')
result = run_main;
```

`run_main.m`固定使用包内已检查校准，调用原有main后运行`verify_main_results`交叉核对MAT、CSV和日志，并保存`main_completion_check.mat/.txt`。可选`run_smoke`仅做预检；main本身会先做完整预检，无需单独先调用smoke。核对已有结果时使用`verify_main_results('你的main结果目录')`，不会重新发送载荷或改动结果。

入口默认优先查找项目内 `evidence/imported_smoke/` 并复用已验证匹配的冻结校准。明确指定旧目录时，该目录须含完整匹配的 `config_snapshot.mat` 和 `initialization.mat`：

```matlab
result = run_dmt_experiment('main', ...
    'CalibrationDirectory','C:/work/old_smoke');
```

需要以相同种子重算并核对原初始化时：

```matlab
result = run_dmt_experiment('main', ...
    'CalibrationMode','recompute', ...
    'CalibrationDirectory','C:/work/old_smoke');
```

默认 `CalibrationMode='reuse'`。复用前检查物理参数、归一化、所需字段及Uniform/Loaded选阶是否匹配，拒绝不匹配数据，不静默换成更有利校准。recompute保持原数据/噪声种子，按绝对容差1e-12、相对容差1e-10核对保存值，profile必须完全一致；不一致停止诊断。没有参考目录时，记录该事实并按冻结种子新建一次校准，三策略共享。校准来源、核对与profile标识随结果保存；历史载荷计数始终不复用为正式测试。

批处理示例：

```powershell
matlab -batch "cd('C:/work/BitLoading/EESM5540_DMT_BitLoading'); run_dmt_experiment('main')"
```

```sh
cd /path/to/BitLoading/EESM5540_DMT_BitLoading
matlab -batch "run_dmt_experiment('smoke')"
matlab -batch "run_dmt_experiment('main')"
```

不在外层吞掉错误，失败保留非零退出码与失败目录。smoke执行自检、校准核对、三策略profile冻结和每策略2000符号程序检查。main先预检，再以同一次冻结初始化执行 **3策略×3种子，共9次正式运行**；其预检结果在 `preflight_smoke/`，正式结果在当次目录根部，计数互不混合。程序不根据BER更换种子、重选profile或延长测试。

## 源码约定、自检与估计

发送 `x=sqrt(NFFT)*ifft(X,[],1)`，先核对虚部为舍入量再real；接收 `Y=fft(y,[],1)/sqrt(NFFT)`。CP复制最后8样本。含CP波形按列串行化，用 `filter(h,1,txSerial,state)` 因果滤波，跨chunk保留状态。新独立运行可重置；完整CP保护首个有用符号。按已知起点去CP，不额外补偿群时延。

噪声在FIR后加入 `sqrt(sigma_w2)*randn(...)`；不使用awgn measured、不按实测帧功率归一化。正频点复噪声E|W_k|^2=sigma_w2，实/虚部各sigma_w2/2。

基础检查包括三种QAM无噪声逐位恢复、Hermitian、虚部、CP、Parseval、线性卷积/FFT关系、跨chunk状态及FFT噪声方差。日志记录观测值、期望值、容差和状态；失败停止并保留证据。源码审计见 `docs/AUDIT_v1_1.md`，源码检查不是本次MATLAB自检通过的证据。

```text
H_hat = sum(Y_A .* conj(X_A),2) ./ sum(abs(X_A).^2,2)
Z_B = Y_B ./ H_hat
gamma_hat = sum(abs(X_B).^2,2) ./ sum(abs(Z_B-X_B).^2,2)
```

A/B数据与噪声独立；教学残差估计包含有限H_hat误差。正式载荷不参与估计、加载或调参。H_true=fft(h,NFFT)仅作诊断，不替代接收机H_hat或加载器gamma_hat。

## 设计BER与工作点预测分开

```text
Pb(M,gamma) = 4/log2(M)*(1-1/sqrt(M))*0.5*erfc(sqrt(3*gamma/(M-1))/sqrt(2))
BER_design  = Pb(M, gamma_hat/10^(1/10))
BER_nominal = Pb(M, gamma_hat)
```

BER_design含1dB裕量，用于Uniform/Loaded保守选阶；BER_nominal是当前工作点的近邻近似诊断。不能要求design曲线与实际BER吻合，也不要求所有近似预测落在统计区间内；有限估计误差、近邻近似与有限计数会影响吻合，不因此自动修改参数。

## 随机流与复现

使用独立RandStream('mt19937ar',...)，不依赖全局rng。训练A数据/噪声为1701/2701、探测B为1702/2702；基础自检另用1601、1611/1612/1613及噪声诊断1609。

载荷映射不变：`base+1000*schemeIndex+10*label+offset`。Uniform index1、Loaded index2保持原值，Fixed16追加index3；main base100000、label11/22/33；smoke base300000、label0；数据offset1、噪声offset2。seed_mapping.csv记录映射并检查冲突。三策略可用独立样本，但噪声方差和分布相同。固定chunkSize是复现配置的一部分，不承诺改变它后逐样本序列相同。

每次保存配置、MATLAB版本、命令、时间、源代码SHA-256清单及冻结校准/profile标识。source_manifest.csv覆盖入口、private中的.m和tools中的.py实际字节；integrity.json保存source_manifest_sha256、initialization_profile_sha256及calibration_provenance，配置快照也嵌入标识。若使用参考校准，其两份MAT快照复制为reference_config_snapshot.mat和reference_initialization.mat，原文件不变。这些是复核依据，不是性能结果。

## 验收与统计口径

实现验收检查基础链路、计数、能量口径、种子隔离、冻结状态和输出完整性。每seed/k测试比特严格为100000*log2(M_k)；每策略pooled是三个seed的和，恰有300000载荷符号。不把seed行和pooled行重复相加，也不把smoke或训练加入。总BER=sum(errors)/sum(bits)，不能平均不同比特数载波的BER。

pooled逐载波用z=1.96的pointwise 95% Wilson二项近似区间：全部上界低于目标为supported_fixed_profile；任一下界高于目标为failed_target；其余为insufficient_evidence。此为逐点证据，不是所有载波95%联合覆盖，也不验证跨信道/初始化鲁棒性。

Uniform/Loaded分别判断；只有二者全部逐点上界低于目标且Loaded的B更高，才支持本固定模型下主比较。Fixed16独立报告目标状态和超标/证据不足载波，性能失败不是实现失败。Loaded的BER不要求低于Uniform，它可用误码余量换承载量。

零误码记录0 observed errors / n tested bits和非零上界；不声称真实BER=0。对数图在上界放专用倒三角，不填伪造极小BER。

## 能量、速率与持续时间

固定星座平均Es不要求随机块能量完全相同。有用/CP/总符号能量期望48/6/54、平均样本功率0.75；记录实际量与偏差，不事后缩放。它们是归一化电量，不证明相同光功率、峰值或含DC偏置功率。

B=sum(log2(M_k))只计24个独立载波；Tu=1us、TCP=0.125us、Ts=1.125us。R_payload=B/Ts已计CP时间，未扣初始化、反馈或FEC，不称含全部开销净吞吐量，也不再扣CP。一次初始化3072符号为3.456ms；每seed的100000载荷符号为112.5ms；每策略pooled300000符号为337.5ms。这是信号持续时间，不是代码耗时。若正式仍为120对48bits，比率2.5即增加150%，不是增加250%，需由正式profile计算。

解析诊断H_true=exp(-j*2*pi*k/64)*cos(pi*k/64)^2、gamma_true=cos(pi*k/64)^4/sigma_w2，理论SNR约12.3135864–28.9790623dB；理论SNR选阶为118/48bits，不是实际profile硬性验收值。平均输入波形SNR约27.7506dB，与29dB参考量不同。

## 新结果文件与论文图

每次新建 `results/<timestamp>_<mode>_<unique>/`；失败也保留快照、诊断与堆栈。下列文件只在实际执行到相应阶段后产生，不预填虚构数字：

| 文件 | 内容及使用方法 |
| --- | --- |
| source_manifest.csv | 本次源代码SHA-256清单 |
| integrity.json | 源码清单及初始化/profile SHA-256标识、校准来源 |
| config_snapshot.mat、initialization.mat | 物理/协议配置、运行模式、冻结校准/profile、来源与一致性/完整性标识 |
| reference_config_snapshot.mat、reference_initialization.mat | 使用历史参考时复制的原配置和初始化，不覆盖历史文件 |
| seed_mapping.csv、environment.txt、run.log | 随机流、实际MATLAB版本、命令、时间与scheme/seed进度 |
| verification_checks.txt | 带数值、容差与状态的具体检查 |
| per_subcarrier_seed.csv | main共216行，3策略×3seed×24载波；复核各seed计数 |
| per_subcarrier_pooled.csv | main共72行，3策略×24载波；正式验收入口 |
| summary.csv | 每策略一行共3行，仅由pooled求得；状态、超标载波、计数、能量与时长 |
| nominal_vs_measured.csv | 72行design/nominal近似预测与实际计数、BER、CI |
| per_subcarrier_results.csv | 如保留兼容混合表，必须按record_type选seed或pooled，不能混加 |
| runs_partial.mat、payload_counts.mat、final_results.mat | 逐组检查点、九组完成后导出前的计数快照、完整正式结果；main和smoke分开，不存长期波形 |
| main_completion_check.mat/.txt | run_main在独立完成核对后保存的报告与逐项日志；数据完整性与性能达标分开判断 |
| dmt_comparison.png/.pdf/.fig | 白底三联图，PNG至少300dpi、PDF矢量、FIG可编辑 |
| report_notes_zh.md、figure_caption_en.txt | 当次真实观察、模型限制与独立英文图注 |
| results_paragraph_en.txt | 仅完整main后生成，约150–200词真实正式结果段 |
| smoke_notes_en.txt | smoke-only说明，不是正式结果段 |
| failure_status.txt | 异常和堆栈，不能把部分运行标为main完成 |

正式图只用main pooled数据。Figure/axes/legend显式白底，坐标、标题与标签黑字，浅灰网格、可区分线型和标记，图例避免遮挡。对数范围包括Fixed16不利结果与所有有意义上界，不裁去超标数据；宽约6.8英寸。图(b)表示比特而非功率。

`payload_counts.mat`的状态为`payload_complete_exports_pending`：即使后续绘图失败，已完成的九组计数也不会丢失，但单有该文件不能算完整main。`verify_main_results`要求完整final MAT、正式表/图及结束日志；Fixed16统计超标不会导致完成核对失败。

保留Figure1；真实main后用该次组合图替换解析Figure2，报告仍不超过四页、汇报四分钟。标注作者的简化数字基带仿真，不标成文献Figure6，不推广为真实数据中心光链路普遍有相同倍数收益。

## 检查证据与背景文献

validation/记录实际静态与独立Python检查；它们不运行MATLAB、不测qammod BER。可选命令 `python3 tools/verify_implementation.py` 需要Python+NumPy，仅作公式/源码诊断。命令与范围以validation/commands_and_scope.md及EXECUTION_STATUS.md为准。

静态检查、独立公式诊断及历史上传结果一致性核对的当前结果见`validation/commands_and_scope.md`。可选历史证据复核命令`python3 tools/audit_uploaded_smoke.py`另需NumPy+SciPy；这些Python依赖不是MATLAB仿真依赖。历史v1.1源码清单为`validation/source_manifest_v1_1.csv`，当前v1.2清单为`validation/source_manifest_v1_2.csv`。

背景/方法参考，不代表本参数来自这些文献：

1. K. Zhong et al., JLT36(2),377–400,2018，DOI10.1109/JLT.2018.2793881。
2. W. Xia et al., IEEE COMST19(1),640–656,2017，DOI10.1109/COMST.2016.2626784。
3. P. S. Chow et al., IEEE TCOM43(2–4),773–775,1995，DOI10.1109/26.380108。
4. K. Zhong et al., Optics Express23(2),1176–1189,2015，DOI10.1364/OE.23.001176。

MATLAB官方：[qammod](https://www.mathworks.com/help/comm/ref/qammod.html)、[qamdemod](https://www.mathworks.com/help/comm/ref/qamdemod.html)、[CP与均衡](https://www.mathworks.com/help/comm/gs/equalization-convolution-and-cyclic-prefix-addition.html)。
