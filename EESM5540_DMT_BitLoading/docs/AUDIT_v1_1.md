# v1.1 有限源码审计

## 范围和证据等级

- 实际项目：`/workspace/BitLoading/EESM5540_DMT_BitLoading`；入口：`run_dmt_experiment.m`。
- 初始审计以提交 `ca26355` 的现有实现为基础，逐项阅读 `.m` 源码，不从结果文件重新猜造收发算法。
- 本文的“源码核对”表示代码检查结论，不表示 MATLAB 运行 PASS。当前云端没有可用 MATLAB，**本次增量未在 MATLAB 执行**；Communications Toolbox 调用、正式 BER 和图导出必须由实际 MATLAB 运行验证。
- 用户上传的旧记录属于 `smoke`，每方案 2000 个符号。上传结果可以作为已有运行证据及冻结校准候选，但不能作为 v1.1 main；不会通过改标题把预检变成正式统计。

## 原有核心实现核对

| 事项 | 实际源码与核对结果 |
| --- | --- |
| Hermitian 映射 | `private/dmt_random_frame.m` 创建 `NFFT × Nsymbols` 零矩阵，正频率行 `k+1`，镜像行 `NFFT-k+1` 为其共轭；DC、Nyquist 与未分配行保持为零。只对 24 个独立子载波生成比特。 |
| QAM 分组与恢复 | 每个子载波生成 `log2(M)*Nsymbols` 的列向量，`qammod` 采用 Gray、bit 输入和 `UnitAveragePower=true`，其符号按行填入频域。`dmt_demod_errors.m` 将接收符号重新转成列向量，以一致参数逐位解调并逐比特比较；镜像不参与计数。 |
| 单位酉变换及实信号检查 | `private/dmt_transceive.m` 采用 `sqrt(NFFT)*ifft(X,[],1)`，先检查虚部阈值再取 `real`；接收采用 `fft(y,[],1)/sqrt(NFFT)`。没有用取实部掩盖映射错误。 |
| 真实 CP/FIR 链路 | 每列前缀复制最后 8 个样本，按列串行化后执行因果 `filter(h,1,tx(:),state)`；输出状态回传并在载荷/校准各自运行内跨块保存。按固定边界去 CP，不使用 `conv(...,'same')` 或群时延补偿。 |
| 噪声与归一化 | `sqrt(sigma_w2)*randn(...)` 在 FIR 后加入实噪声。未使用 `awgn(...,'measured')`、逐帧功率归一化或滤波器能量归一化；正频率复噪声方差口径为 `sigma_w2`。 |
| 独立训练与探测 | `private/dmt_calibrate.m` 用 A 的 LS 估计 `H_hat`，独立 B 的 `Y./H_hat-X` 残差估计质量；A/B 数据和噪声具有分别固定的种子。正式载荷不参与校准。 |
| 真信道的用途 | `H_true=fft(h,NFFT)` 仅附加为诊断值；`private/dmt_load_profiles.m` 使用 `gamma_hat`，`private/dmt_simulate.m` 使用 `H_hat`。正式接收机未替换为真值。 |
| 选阶与能量 | 原有 Uniform/Loaded 均依据含 1 dB 裕量的近邻近似选取最大合法阶数；不存在硬编码 118/120 bits 或关闭子载波。各活跃独立子载波只做星座平均能量归一化。 |
| 分块与存储 | 校准和载荷以不超过 2000 符号的块执行，载荷只保留累计计数和能量；没有长期载荷全波形。未使用 parpool/GPU。 |
| 基础自检确有实现 | `private/dmt_self_checks.m` 实际调用三种 QAM 无噪声链路、训练估计和逐位恢复，并计算 Hermitian、虚部、Parseval、CP、线性卷积/FFT、跨块状态和独立噪声 FFT 二阶矩诊断；并非仅写输出标签。 |
| BER 与区间 | `private/dmt_wilson.m` 使用给定 `z=1.96` 公式；整体 BER 由总错误/总比特计算。严格上界低于目标、任一下界高于目标、其余证据不足三类状态区分正确；不是联合 95% 覆盖保证。 |

未在上述核心源码中发现要求废弃已有校准的 DSP 实现错误。该判断不替代完整保存数据匹配、重复计算比对或 MATLAB 运行验证。

## v1.1 必须处理的增量事项

| 原状态 | 增量要求及原因 |
| --- | --- |
| 仅 Uniform/Loaded 两个 profile 和固定的两策略循环、样式数组 | 添加第三个 Fixed16 诊断策略；原两策略的流编号必须保持 1/2，Fixed16 追加为 3，避免改变旧流映射。 |
| `dmt_post_checks.m` 对每个 profile 强制设计 BER 可行 | 只对 Uniform/Loaded 做选阶可行性断言。Fixed16 可能不满足目标，必须记录真实结果而不是中止或删去。 |
| 原混合 CSV 同时含 seed 与 pooled | 物理分离逐 seed 和 pooled 文件；若保留兼容表，必须带 `record_type`，不能把两个统计层级重复求和。 |
| 设计近似与工作点近似未并列输出 | 分别输出 `BER_design=Pb(gamma_hat/margin)`、`BER_nominal=Pb(gamma_hat)`。两者均为近似诊断，不能要求预测必然落入测量区间。 |
| 只显式设置 figure 白底，axes/legend/字体仍可能继承深色主题 | 对 figure、axes、legend、标题、标签、刻度及目标线文字显式设置颜色，并保留不同线型/标记；图范围必须包含 Fixed16 的全部不利结果。 |
| smoke 也生成英文 results 段 | v1.1 正式英文结果段仅在 main 的 9 次完整正式载荷运行确实完成后生成；smoke 说明单独命名。 |
| 旧配置/初始化没有代码与校准身份清单 | 新运行应保存代码 SHA-256 清单、冻结参数和校准/profile 标识，复用旧校准前严格核对匹配；不能因想得到 118/120 而重选。 |

## 原 smoke 的解释边界

上传 `summary.csv` 中 Uniform 为 `0/96000`，Loaded 为 `10/240000`，均为每方案 2000 符号的预检计数；`seed=0` 与 `pooled` 是同一批数据，不能合计。当前 120 bits 的 profile 对应 k1:15 为 64-QAM、k16:21 为 16-QAM、k22:24 为 QPSK，和解析 118 的差异可由边界 k21 的有限质量估计引起，不是需要手动修正的错误。

这些 smoke 数据不提供三策略正式比较，也没有 Fixed16 的实测 BER。即使主实验最终仍得到 120/48，其载荷比是 2.5，对应增加 150%，而非增加 250%；目标合规必须另外由正式逐点区间判断。

## v1.1 核心增量源码核对

| 文件/事项 | 源码核对结果与限制 |
| --- | --- |
| `dmt_default_config.m` | 使用 `protocolVersion='1.1'`，保留 `specVersion='1.0'` 及冻结物理参数、A/B 种子、正式标签和分块长度；没有调参追求图形或验收通过。 |
| `dmt_load_profiles.m` | Uniform 和 Loaded 仍由估计 SNR 与原有规则计算，Fixed16 追加为第三个 profile，24 个独立子载波均为 16-QAM。它的 `role` 为 diagnostic，不被当成已达标基线。 |
| `dmt_seed_mapping.m`、`dmt_simulate.m` | Uniform/Loaded 仍按索引 1/2 和原公式映射，Fixed16 追加索引 3。全部声明的数据与噪声种子进行冲突检查；载荷仍按固定长度串行执行并传递 FIR 状态。 |
| `dmt_post_checks.m` | Fixed16 只跳过“保守选阶必须可行”的断言，明确写 INFO；仍检查子载波、种子标签、固定符号数、比特计数、速率和能量。未把它的目标失败变成实现失败。 |
| `run_dmt_experiment.m` | smoke 和 main 的循环均使用实际 profile 数；main 单独构造正式 `runs`，不加上 `smokeRuns`。每策略三个固定标签、每标签 100000 符号的总数在 postchecks 中核对；结果写入独立时间戳目录。 |
| `dmt_prepare_calibration.m` | 默认优先复用配套历史证据目录；存在导入清单时先逐文件核对字节数与 SHA-256，然后核对物理/估计配置、随机算法、24×1 有限校准字段、探测残差恒等式、理论诊断和原 Uniform/Loaded 分配。存在 final MAT 时，还核对其全部冻结配置、模式、校准/profile 与初始化一致。不会从旧载荷估计信道或把旧计数加入新统计。 |
| 同种子复算模式 | `CalibrationMode='recompute'` 调用原 A/B 估计器，并按 `atol=1e-12, rtol=1e-10` 与保存校准比较，且核对原两种 profile 完全一致；失败时中止并保留证据，不为追求 118/120 自动重试。默认 reuse 不额外消耗初始化数据流。 |
| `dmt_sha256.m` | 使用 Base MATLAB 配套 JVM 的 SHA-256，输入 uint8 按位转换为 Java int8，digest 转回 uint8 并输出十六进制。需要默认 JVM，不能使用 `-nojvm`；这项 Java 调用尚未在本云环境的 MATLAB 验证。 |
| `dmt_source_manifest.m` | 对真实入口、private `.m` 和 tools `.py` 的原始字节生成按相对路径排序的 SHA-256 清单。清单身份和逐文件哈希保存于新运行；运行后再次核对代码身份未变化。 |
| `dmt_initialization_id.m` | 将冻结配置、数据/噪声种子、H_hat 实/虚部、gamma_hat 和全部 M 分配编码为稳定文本并哈希；运行前后比较。它不是跨初始化鲁棒性证据。 |

没有发现需要废弃旧校准的核心 DSP 缺陷。旧 v1.0 文件本身没有当时执行源码的 SHA-256 清单；现在对上传字节的哈希和数值一致性审计能够确认保存数据之间匹配，不能追溯证明原机器执行代码的密码学身份。新增的源码清单从 v1.1 的实际运行开始记录。

## v1.1 输出层增量源码核对

| 文件/事项 | 源码核对结果与限制 |
| --- | --- |
| `dmt_write_outputs.m` 完整性入口 | 导出前核对三策略顺序及 phase，main 必须恰好包含 9 次运行、标签 11/22/33、每次 100000 符号和逐子载波对应的整数比特计数；smoke 仅接受三次 2000 符号运行。未完成或混合阶段不能导出正式段落/图。 |
| 统计层级 | 逐种子表与汇总表分别写入 `per_subcarrier_seed.csv` 和 `per_subcarrier_pooled.csv`；main 行数断言分别为 216、72。兼容混合表增加 `record_type`；汇总计数只由运行计数累积一次，并逐 scheme/k 核对 pooled 恰好等于 seed 之和。 |
| 预测与验收 | `nominal_vs_measured.csv` 并列保存含裕量的设计 BER 及无裕量的名义 BER，不利用理论 FIR SNR 替代估计。各策略分别报告状态及超标/跨目标 k 清单。主机制支持标志只考虑 Uniform/Loaded 的区间及 B 优势，不把 Fixed16 失败作为支持或否定主比较的条件。 |
| 报告材料 | 新正式英文结果段只有 main 完整性检查通过后生成，并按实际计数计算 150–200 词正文；smoke 单独写 `smoke_notes_en.txt`。中文说明解释三图、边界 k21、120/118、Fixed16、能量、统计适用范围和模型局限。独立英文图注由实际模式标记。 |
| `dmt_plot_results.m` | 只接受 `record_type=pooled` 的输入；main 进一步核对 72 行和完整测试比特数。显式设置 figure/axes/legend 白底及黑色文字，网格浅灰；三策略具有不同标记/线型，图例置外。不是截图反色。 |
| BER 显示和范围 | 正误码项显示逐点 Wilson 区间，零误码仅在非零上界处显示倒三角，不添加伪 BER 下限；纵轴上界由全部三策略的 CI_high 决定，保留 Fixed16 不利数据。目标线文字设为黑色。 |
| 图导出 | 保存 300 dpi PNG、矢量 PDF 及 FIG；导出显式白色背景。当前只能确认调用和样式代码存在，不能声称无 MATLAB 环境已经验证导出文件外观。 |

本轮输出层源码核对未发现阻断性接口或统计口径问题。`run_dmt_experiment.m` 与输出函数的四返回值接口匹配；源代码总计 21 个 MATLAB 文件。该结论仍是有限静态审查，不是正式性能验收。

## 上传 smoke 的文件一致性证据

`evidence/imported_smoke/` 保留 14 个用户上传的原始输出文件与导入清单，不对其进行改名改值、覆盖或把状态改成 main。上传的 `environment.txt` 记录 MATLAB R2026a Update 5、PCWIN64；这只描述原运行，不能推断本云环境也具有 MATLAB。

`validation/uploaded_smoke_audit.md` 和配套 JSON 记录 211 项文件/数值一致性检查，覆盖导入哈希、两个 MAT 中的配置/校准/profile、已保存残差导出的 SNR、选阶和 CSV/计数/能量/时长/Wilson 复算。该 Python 审计只读取上传数值，未模拟新的载荷，不等于 v1.1 MATLAB 运行。

## 尚未完成的运行验证

当前云端 **未在 MATLAB 执行 v1.1 smoke 或 main**。因此 Java SHA-256 调用、Communications Toolbox 运行、三策略正式 BER、白底图的实际导出及报告段均须在有 MATLAB 的机器按 README 完成；没有为未运行阶段伪造 PASS。
