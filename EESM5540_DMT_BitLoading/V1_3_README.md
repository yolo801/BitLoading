# v1.3：显式反馈、独立校准与采样点IM/DD扩展

本次在现有项目内增量实现协议1.3。线性场景仍使用物理规格1.0；三个归一化IM/DD等效场景使用单列的模型版本。原v1.1/v1.2入口、结果和校准不覆盖。不得把新增源码或本说明当作实验已经执行的证明。

**当前尚未在MATLAB执行这份v1.3代码。** 本环境未发现MATLAB，也没有暴露MATLAB MCP工具；正式完成量与原始启动错误以根目录`EXECUTION_STATUS.md`和`execution_attempts/`为准。没有预制新的BER、功率/削波统计、MATLAB PASS日志或正式结果段。

## 环境及入口

目标为MATLAB R2026a、Base MATLAB和Communications Toolbox，使用正常JVM以保存SHA-256和文件锁。不要以Octave或Python结果冒充MATLAB执行。进入解压后的项目目录，不需要修改全局路径。

先做四场景独立短预检：

```matlab
preflight = run_dmt_v13('preflight');
```

完整正式预算：

```matlab
result = run_dmt_v13('all');
```

若需要分阶段运行：

```matlab
linear = run_dmt_v13('linear');
imdd = run_dmt_v13('imdd');
```

每次未提供恢复目录的调用会创建新的`results/v1_3_*`目录。正式模式先执行四场景的独立preflight，共36个短组；已有同一研究目录内且完整核验的preflight可复用。预检不混入正式样本，也不能只完成预检就称正式实验完成。

在同一目录继续其余场景，或在确认原MATLAB进程已经退出后恢复：

```matlab
continued = run_dmt_v13('all', ...
    'ResumeDirectory','C:/work/results/v1_3_existing');
```

工具等待超时不是MATLAB停止的证据。先观察原进程及原目录的`run.log`，不要启动第二份指向同一目录的任务。源码、科学配置、校准、profile、ACK和计数标识必须匹配；不完整计数按原固定种子整组重跑，不把旧部分计数累加到新整组。

完成后只读核对：

```matlab
check = verify_dmt_v13('all','ResultDirectory',result.output_dir);
```

按请求范围核对也支持`'linear'`、`'imdd'`或`'preflight'`。`'linear'`只对应90个正式计划组，`'imdd'`对应270组；它们都不能称完成全部360组。未请求场景在完整360槽位状态表中保持incomplete，而不是补0误码。

Windows批处理示例：

```powershell
matlab -batch "cd('C:/work/BitLoading/EESM5540_DMT_BitLoading'); run_dmt_v13('all')"
```

## Reference 0与历史结果

可明确指定原正式main目录：

```matlab
result = run_dmt_v13('all','ReferenceDirectory', ...
    'C:/work/old_project/results/20261117_160931_509_main_tp95fc34e7_f0f6_453d_92d2_16759118ed52');
```

未指定时，入口只在当前项目`results/`下查找提示词给定的两个reference main目录名。若找不到，记录reference 0未核实，不用`evidence/imported_smoke/`或提示词中的核对数字猜造正式数据。缺少旧reference不妨碍执行新的独立校准，但不能声称旧结果已复核。

提示词说明两个给定reference目录核心计数相同，代表一次校准；本次仍须从真实文件核对，不合计成两个独立实验。旧v1.2结果若存在，仅作为如实标注的历史证据；没有经过本轮反馈/配置接口的旧运行，不能补日志后声称验证了新接口。

新的线性主图固定使用**本轮linear/calibration 1**，不是从十轮挑最好的一轮，也不与reference 0图表拼接。原正式结果、图、报告和摘要不自动覆盖。

## 显式的软件控制路径

1. Tx生成双方已知A/B并通过真实场景前向链路。
2. Rx仅以A估计H_hat，再以独立B计算残差质量gamma_B。
3. Rx制作反馈对象，经过理想复制及校验；反馈只含估计质量和身份等必要字段，H_hat留在接收端，Tx不读取H_true、实际噪声或测试BER。
4. Tx仅根据反馈、候选QAM、目标和余量选阶；将配置发送给Rx，双方保存独立值副本，逐项核对M_k、bits_k、profile_id和哈希后记录ACK。
5. 已ACK的每个策略生成独立C，使用实际配置、冻结H_hat计算有效质量迁移；C不重估H、不改表、不调参。
6. 正式payload的Tx映射和Rx解映射分别读取各自的本地配置；未ACK不能开始。

这些是明确的数据对象和复制/校验功能假设，不是可变全局表。没有建模反馈时延、量化、编码或物理反馈信道，不能声称反馈开销已验证为零。

Uniform与Loaded按同一含1dB余量的近邻QAM BER近似选择最大可行阶数。Fixed16始终作为诊断配置保留，不要求其预测或实测达标。若Uniform/Loaded的最低QPSK不可行，相应策略记infeasible、不发送伪造载荷；Fixed16仍按计划测试。没有按k=15或21写死分界，也不强迫120bits或2.5倍。

## 物理模型与四个场景

共用NFFT64、CP8、Fs64MHz、k1:24、h=[0.25,0.5,0.25]、Gray方形QAM及星座平均Es1。保留Hermitian映射、单位酉FFT、CP、跨分块FIR状态和训练估计ZF。噪声在FIR后加入实高斯样本；不使用测量功率awgn、不逐帧归一化、不关闭弱子载波、不做功率加载。

| idx / id | 模型与固定量 |
| --- | --- |
| 0 / `linear` | 原线性电域模型，sigma0_sq=10^(-29/10) |
| 1 / `imdd_rho4` | rho=4，P0=1，Pmax=2 |
| 2 / `imdd_rho2p5` | rho=2.5，P0=1，Pmax=2 |
| 3 / `imdd_rho1p5` | rho=1.5，P0=1，Pmax=2 |

IM/DD使用固定理论sigma_x=sqrt(0.75)，g=1/(rho*sigma_x)，p_raw=1+g*x，再在每个采样点截到[0,2]。`p`是归一化光功率而非光场，理想探测电流与p成比例，不在接收信号路径再次平方。实现使用等效稳态交流路径`filter(h,1,p-1)+w`，明确已去除稳态DC1，避免零初值DC启动瞬态被误当作损伤。削波谱再生真实通过h，不重新清零非活动频点。

三个IM/DD场景接收噪声都固定为sigma_ext_sq=sigma0_sq/(16*0.75)。这使rho4旁路削波小信号回归在输入折算后与原线性模型一致，是预先固定尺度，绝不根据BER调整。rho越小同时增加交流驱动和削波程度，不能预设性能单调变差或变好，也不能说P0随rho改变。

这里只是归一化、sampled/discrete-time clipping强度链路，不模拟真实光器件、连续时间峰值、散粒噪声、RIN、啁啾、色散、Kerr、量化或FEC。29dB只是Es/sigma0_sq参考比，不是OSNR。

## 固定预算、流映射与chunk不变性

A1024、独立B2048个QPSK DMT符号；每个已配置策略独立C2048个实际加载符号。每场景10轮校准，每个可配置策略每轮三个载荷标签11/22/33，各100000正式符号，chunk<=2000，串行，不使用parpool/GPU或保存长载荷全波形。

全部可配置时正式预算为linear90组、IM/DD270组，共360组、36000000载荷符号。A/B/C、预检和reference 0均不计入。

```text
base = 2000000 + 10000000*scenario_idx + 100000*calibration_id
A data/noise = base+101 / base+102
B data/noise = base+201 / base+202
C data/noise = base+5000+100*s+1 / +2
payload data/noise = base+1000*s+10*j+1 / +2
s = Uniform1, Loaded2, Fixed16 3
j = 1,2,3 对应标签11,22,33
```

四场景正式A/B/C/payload共1120个不同seed；四个preflight/calibration1使用相应base再加100000000的独立命名空间。代码把标签与真正流种子分别保存。v1.3新比特生成按符号优先顺序，并冻结mt19937ar及Inversion正态变换，保证任意合法chunk拆分的正式序列不因分块或恢复顺序改变。

线性scenario0的编号公式与v1.2部分seed编号相同，因此不能据此声称跨版本统计独立；旧v1.1/v1.2输入次序和正态生成路径保留。新增代码路径的执行必须有本轮真实记录，不能把旧计数或一次故意回放充当新的独立样本。

## 功率、削波、PAPR与B/C诊断

每组保存电有用段、CP及总能量；IM/DD保存p的实际均值、峰值、二阶矩和AC方差，分别列E[p]与E[p^2]。实际平均光功率相对1的偏差要报告；长载荷超过1%时先保留该组检查点并调查统计/实现原因，再继续，不作事后缩放。

保存上下削波次数、总采样数、削波率和mean((p-p_raw)^2)。后者是采样点幅限误差功率，不等于全部接收失真。线性场景的光功率量不适用，不把缺失光学指标当作0测量值。

PAPR在偏置/削波前、每符号有用64点上计算max(abs(x).^2)/mean(abs(x).^2)，只用于统计、不用于缩放。保存固定阈值的超越计数和总符号数。零超越保留0/N，不用epsilon伪造对数概率；它不是加DC后max(p)/mean(p)，也不是优化目标。

削波中的gamma_B/gamma_C是包含失真、估计误差和有限样本波动的effective SNR/SNDR，不应称纯AWGN SNR。线性也计算B/C差异；不能把差异全部归于高阶QAM或削波。C不进入正式BER统计，不反向修改H_hat或配置。

## 验收和结果解释

实现检查与科学性能分开：基础无噪声映射、CP/FFT/FIR、跨chunk、噪声尺度、rho4旁路削波同原始噪声的线性回归、反馈复制、配置一致性和ACK等必须正确。Fixed16或Loaded的科学BER失败不自动成为实现失败，不触发换种子或调参。

统计只在同scenario/calibration/scheme/k内合并三个正式载荷种子。总BER为总错误/总测试比特；按infeasible→incomplete→任一CI_low>target为failed→全部CI_high<target为supported→其余inconclusive给唯一状态。Wilson是统一的近似逐点证据，不宣称相关误码/非线性下严格二项覆盖，也不是所有载波联合95%保证。零误码有非零上界。

只有同轮Uniform和Loaded均supported时，才把承载比称为本判据支持的收益；其他情况仅是名义分配比。Loaded不必比Uniform BER更低。不同profile不混合证明逐轮合规，十轮上端点不平均成新置信上界，10/10不等于未来成功率100%。

## 输出结构

所有新文件进入独立的`results/v1_3_*`目录，实际数字以该次日志与表为准：

根目录保存配置、源码／种子清单、文献映射、总运行日志及`final_v13_results.mat`。表中校准、控制、载荷CSV、图及`completion_check.txt`分别位于`preflight/`和`formal/`，两者绝不混合；正式图表取`formal/`，各阶段原始计数与表另保存在各自的`phase_results.mat`。`configured_pending`文件保留C之前已接受的配置，不会被当成完整可恢复校准。

| 输出 | 内容与完整预算下行数 |
| --- | --- |
| 配置、源码、文献、种子和完整日志 | 实际输入/代码/配置身份，线性与IM/DD模型版本分列 |
| `calibration_records/` | 每轮真实A/B来源/哈希、H_hat与gamma_B |
| `feedback_records/`、`tx_profiles/`、`rx_profiles/`、`configuration_ack/` | 双方独立对象及反馈/配置校验和ACK |
| `validation_probe_C.csv` | 实际策略/k的C/B质量、差值及来源；不计入payload |
| `per_calibration_seed.csv` | 所有组完整可配置时8640行 |
| `per_calibration_pooled.csv` | 所有组完整可配置时2880行，只合并同轮三个seed |
| `per_calibration_summary.csv` | 120个计划场景/校准/策略组合及唯一状态 |
| `run_status.csv` | 360个计划载荷槽位，实际完成符号数/不可行或未完成原因 |
| `robustness_summary.csv` | 12个场景/策略汇总，状态轮数、承载量范围与支持的收益范围 |
| `profile_frequency.csv` | 每场景/策略/k的M次数、infeasible和not_configured；每轮只计一次 |
| `power_clipping_metrics.csv` | 逐组实际功率、幅限次数/率与误差，不混淆光学均值和电平方量 |
| `papr_ccdf_counts.csv` | 阈值、实际超越次数及符号总数，包含真实零计数 |
| 小型逐组计数MAT及`completion_check.txt` | 计划与实际量、哈希/冻结配置、数据隔离及计数核对 |

部分模式、不可行或中断时，有效seed/pooled行数会减少，计划状态表仍保留未执行槽位与原因。不能把缺失BER补0。

图按真实数据导出白底PNG、矢量PDF、FIG，支持时加SVG：显式信号/理想控制路径图；固定linear/calibration1的质量、bits及CI_high/target图；详细BER+CI；三个rho的实际削波/承载量分布/supported轮数；固定calibration1的sampled AC PAPR CCDF与B/C差异补充图。min–max范围不是95%置信带；名义速率不自动是合规净吞吐量。结构图是模型职责图，不是实测反馈传输记录。

R_payload=B/((64+8)/64e6)计入CP时间，未扣A/B/C、反馈或FEC；不再次扣CP，不虚构未建模的反馈时延。报告仍保留核心结果与能解释硬件权衡的图，其他作为补充；不自动改摘要或报告。

## 文献核实状态

新的映射在`docs/literature_mapping_v1_3.md`，真实访问记录在`docs/literature_access_v1_3.json`。本次13次HTTPS请求均在代理CONNECT阶段失败，0篇原文阅读、摘要和元数据也未取得。给定Fig.6/Section4定位明确标为提示词提供而未独立核实。结果目录中的对应副本不改变这一限制。

所有360组的实际完成、逐场景科学状态、加载表变化与功率/削波统计，必须由真实MATLAB执行后给出；本文件和源码都不作为运行成功的证明。
