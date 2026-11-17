# tradeoff_v1：本地 MATLAB 运行与交付说明

本次按你的最新指示交付代码，由你在本地运行MATLAB。新入口研究固定rho=4时，平均光发射功率、理想ADC位数、未编码BER与速率/协议代价的关系；不复用旧实验计数，也不覆盖历史结果。

**这份新增代码未在MATLAB执行。** 当前代码交付没有新预检PASS、正式BER、接受加载表或新结果图。静态检查和独立Python算术仅检查源码/协议，不能替代真实MATLAB机械预检。正式协议必须在你的MATLAB实际预检及核对通过后才冻结。

## 环境和最短命令

需要MATLAB（目标兼容R2026a）、Communications Toolbox与正常JVM启动。Gray-QAM用`qammod/qamdemod`，哈希和OS文件锁使用MATLAB附带Java。不需要GPU、并行工具箱或Statistics Toolbox。不要使用`-nojvm`。

解压完整项目并进入含`run_dmt_tradeoff.m`的目录；保留`private/`及原有代码。完整顺序运行：

```matlab
result = run_dmt_tradeoff('all');
```

入口先运行机械自检和独立预检，核对后冻结tradeoff_v1配置/源码/随机流计划，再继续正式矩阵。`result.output_dir`给出独立的新`results/tradeoff_v1_*`目录。新模式不会进入旧v1.3结果目录，不会把smoke/预检计数加入正式统计。

若分开运行：

```matlab
pre = run_dmt_tradeoff('preflight');
result = run_dmt_tradeoff('formal', 'ResultDirectory', pre.output_dir);
```

`formal`必须使用同一份已通过实际预检并冻结协议的新研究目录。单独完成preflight不是正式测试完成。

从Windows批处理启动（请改项目路径）：

```powershell
matlab -batch "cd('C:/work/BitLoading/EESM5540_DMT_BitLoading'); run_dmt_tradeoff('all')"
```

## 中断、恢复与只读核对

工具等待超时不等于MATLAB已退出。先检查原进程与原目录日志；不要启动第二个同时写同一目录的任务。OS锁会拒绝同一研究目录中的并发运行。

确认原MATLAB进程已退出后：

```matlab
continued = run_dmt_tradeoff('resume', ...
    'ResultDirectory', 'C:/work/your_tradeoff_result_directory');
```

恢复核对原始源码/配置/种子身份及完整检查点，只复用已完成的共享校准、策略设计和载荷组。未完成单元使用原种子重放，不把旧部分计数与整组计数相加。身份或完整性不匹配时停止诊断；不要手改检查点或清除失败记录后继续。

恢复还核对MATLAB发行版、Communications Toolbox版本和计算平台；改变运行引擎须新建协议目录。运行时会记录实际`which -all`函数解析路径，私有函数应来自本工程，QAM函数应来自已安装工具箱。

科学拒绝不构成机械失败。若整个预检矩阵均无接受表，入口保留全部状态，回放固定机械诊断并独立复核保存记录，写`preflight_investigation.txt`；检查通过后仍继续原定正式矩阵，不改参数或种子来追求接受结果。

只读核对和只读重绘：

```matlab
report = verify_dmt_tradeoff(result.output_dir);
redraw_dmt_tradeoff(result.output_dir);
```

只有预检数据时须明确选择阶段，不能把预检图重标为正式图：

```matlab
report = verify_dmt_tradeoff(pre.output_dir, 'Phase', 'preflight');
redraw_dmt_tradeoff(pre.output_dir, 'Phase', 'preflight');
```

verify根据实际检查点重建和核对统计，区分数据完整性、完成量与科学表现；保存`verification_report.mat/.json/.txt`，不改计数。redraw仅读取已有记录重绘，在独立`redraw_<timestamp>/`保存图件，不运行新训练、探测或载荷。编辑过源代码后应创建新研究目录，不能在同一批次看正式结果后改算法/参数。

## 实际运行后产生的目录

根目录保存`Protocol.mat/.json`（真实预检通过后才写）、`mechanical_checks.mat/.txt`、`environment.mat/.txt`、`source_manifest.csv`、`source_snapshot/`及`run.log`。环境文件记录真正的MATLAB版本和工具箱，而不是本代码包作者的云环境。

`preflight/`与`formal/`分别保存本阶段`phase_results.mat`、`seed_plan.csv`、逐层CSV及`shared/`、`designs/`、`payload/`检查点，不能混合两个目录的计数。全量源快照和真实数据身份用于恢复和独立核对；检查点文件不是仅凭配置写出的“完成证明”。

`resource_observation.mat`记录阶段墙钟时间及可用的阶段结束内存查询；不是实测峰值内存。各模块的纯计算时间与包含I/O/绘图的墙钟时间分开记录。每个独立发送块从零FIR状态开始，首个CP覆盖滤波启动记忆；块内跨chunk保持滤波和随机流状态，避免分块改变数据结果。

功率校准、每轮Ar/Dr、双方配置和ACK、小型逐载波原始位/错计数均随该次研究保存。统计CSV、字段字典和图件以当次实际导出文件为准；没有完成/接受的case保留状态，不补BER=0，不挑选成功轮隐藏失败轮。

| 文件 | 内容 |
| --- | --- |
| `per_subcarrier_seed.csv` / `per_subcarrier_pooled.csv` | 实际逐重复原始位/错计数；只在同条件/校准/策略内合并两个重复 |
| `per_calibration_summary.csv` / `run_status.csv` | 每个策略设计case的状态及所有计划载荷槽位的完成/拒绝/未完成原因 |
| `power_calibration.csv` / `design_rounds.csv` | 每份独立TX波形校准的b和实际功率；每轮当前M的Ar/Dr来源及逐载波Dr区间 |
| `protocol_costs.csv` / `feedback_costs.csv` | 实际训练、验证和计算代价；质量标量/判定反馈/加载表条目/ACK数量 |
| `payload_power_adc_metrics.csv` / `loading_profiles.csv` | 实际功率/削波/ADC越界、归一化能量指标与最终加载表 |
| `scenario_summary.csv` / `rate_requirements.csv` | 每个功率/q/策略的全部五轮状态；满足预设业务速率的最低已测试功率 |
| `budget_envelope.csv` / `strategy_comparisons.csv` | 按最大实测功率约束的经验工作点包络；同轮两策略名义/周期速率比较 |

另有`field_dictionary.md`解释单位、层级和缺失值，`report_notes_zh.md`依据本次真实状态解释结果。只查看`per_subcarrier_seed.csv`或只看名义速率不能代替完整完成/合规验收。

实际记录可用时导出五组图，每组均有300dpi PNG、矢量PDF/SVG和可编辑MATLAB FIG：

- `rate_vs_actual_power`：实际功率与名义/周期速率，含全部轮的支持状态及min–max。
- `required_tested_power`：满足最低业务周期速率所需的最低已测试、受支持功率。
- `nominal_vs_cycle_rate`：初始训练和全部验证轮抵消的速率部分。
- `BER_vs_actual_power`：不平滑的每校准总体误码诊断；零误码显示区间上端，不能替代逐载波判据。
- `representative_loading_BER`：固定P_target=1、q=8、cal=1的最终加载表与逐载波BER；拒绝/缺测保留原状态。

`figure_manifest.csv`区分已写出、无实际数据可用及导出失败；图的英文说明见`figure_captions_en.txt`。没有实际记录时不从配置猜曲线。预检图均明确标为诊断，不用来声明正式性能。

## 冻结物理模型与实验规模

| 项目 | tradeoff_v1固定值 |
| --- | --- |
| FFT / CP / Fs | 64 / 8 / 64MHz；单位酉FFT/IFFT、Hermitian；k=1:24全部活跃 |
| 信道及星座 | h=[0.25 0.5 0.25]；Gray QAM M={4,16,64}；每载波平均星座Es=1 |
| 发送光功率 | p=clip(b*(1+x/(4*sqrt(0.75))),0,2)，含CP；固定rho=4 |
| 目标实际平均功率 | P_target=[0.6,0.8,1.0,1.2,1.4]，归一化单位 |
| 接收及ADC | y=h*p+w；固定实热噪声方差1.0491e-4；噪声后ADC、再去CP/FFT |
| ADC | q=[4,6,8]；固定范围[-0.1,2.1]；饱和均匀mid-rise，无AGC |
| 目标及余量 | 未编码逐载波BER目标1e-3；预测选阶余量1dB |
| 初始校准 | 每个(P,q,cal)共享QPSK A0=1024、独立B0=2048 DMT符号 |
| 每候选表 | 独立TX-power-cal=8192，当前M下独立Ar=1024，再独立Dr=8192；最多4轮 |
| 两个策略 | UniformAdaptive整表选阶/降阶；ValidatedLoading逐载波选阶，仅不支持载波降阶 |
| 正式矩阵 | 5P×3q×2策略×5校准×2载荷重复，300个计划载荷槽位 |
| 每载荷组 | 50000 DMT符号，含CP共3600000个时间样本；固定chunkSize=1024 |
| 预检 | 每个(P,q,策略)一轮校准，共30个设计case；两个载荷重复各2000符号；A0/B0/Ar/Dr预算不缩短 |

b是偏置/驱动控制量，**不是削波后实际平均光功率**。每张完整候选表用一次固定8192符号TX波形二分校准b，误差不超过目标的0.2%；迭代不换波形、不用噪声/D错误/正式载荷调整。表改变后重做功率校准及当前M下的Ar和整个Dr。

正式期间b、M、Hhat和ADC范围冻结。每组实际平均功率与目标偏差超过1%时保留原计数，标记`power_mismatch`并排除匹配功率的受支持比较；不事后补缩放。光发射削波计数与ADC输入越界计数分开，均含CP。

## 预检、接受与完成状态

两个策略都必须以真实Dr计数满足：全部24个近似95%逐点Wilson上界严格低于1e-3。若不支持，Uniform全表统一降一级，Loaded只降低不支持载波；改变表后完整复测，不复用其他载波的旧通过状态。接受表经最终双方配置与ACK核对后才进入正式载荷。

没有接受表时不发送伪造载荷。`no_initial_candidate`、`no_accepted_profile_min_order`和`round_budget_exhausted`是这套加载/验证规则的设计状态，不能解释成所有可能方案物理不可行。科学BER失败、区间不确定或功率不匹配也不等于机械实现出错，不应据此换种子、噪声、ADC范围、余量或载荷预算。

计划300槽不等于实际完成300组。完整遍历可以含“设计拒绝”槽位；必须同时看实际完成、设计拒绝和未完成数量。跨校准的M表可能不同，不能合并各轮计数证明每轮合规。

## 速率、功率和代价的解释

名义载荷段速率`R_nominal=B_DMT/T_DMT`已计CP，尚未扣初始化/验证开销。周期有效速率使用独立一个载荷周期L=50000：

```text
R_cycle = L*B_DMT / ((A0+B0+sum_r(Ar+Dr)+L)*T_DMT + T_control)
```

失败候选的Ar/Dr也算实际训练时间。两个载荷种子是统计重复，各自对应一个L周期，不自动组成2L周期。发送端离线功率校准没有经过链路，计算时间单列，不加入光链路训练时长。控制时延T_control=0是理想假设；质量标量数、D判定反馈和加载表条目单列，不以MATLAB内存大小冒充线路bit数。

归一化光功率不是mW/dBm。归一化光能量/bit不是实际J/bit或整机能效；q是理想量化能力代理，不是ENOB、器件采购价或整机瓦数。软件计算时间不是ASIC功耗。

场景曲线只有5/5轮均正式BER-supported且所有正式载荷功率匹配时才用实心点表示受支持结果。min–max是实际跨轮范围，不是置信带。业务门槛25/50/75Mbit/s以五轮最小`R_cycle`判断最低**已测试**功率点；不能用名义速率代替、不能插值宣称精确节电，也不能把扫描内未找到写成全局不可行。预选代表例固定为P_target=1、q=8、cal=1，不挑最好轮。

## 与旧工程和交付检查的关系

新的`private/dmt_to_*.m`基于实际核对过的v1.3组帧、解调、BER公式、Wilson、哈希/保存和流接口接入；旧v1.1/v1.2/v1.3源码及计数保留。当前可访问工程没有附件所指三个v15参考文件，本交付不伪造其接口或声称已复现v15旧结果。

本次源码、静态和独立数学检查状态见`docs/tradeoff_v1/CODE_DELIVERY_STATUS.md`。当你运行后，只有新结果目录中的原始计数、完整日志、协议身份和独立验证报告可作为本轮实验完成证据。没有实际数据前，不预先承诺功率节省或加载收益，不改写论文正文。
