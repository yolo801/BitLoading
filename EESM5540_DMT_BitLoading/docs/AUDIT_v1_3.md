# v1.3 源码与独立协议审计

## 证据范围

本次沿用现有 `EESM5540_DMT_BitLoading` 项目。提示词是待执行规格，不是实验完成证明。当前可用工具没有 MATLAB MCP，终端也未发现 MATLAB；本审计不声称执行了 MATLAB、Communications Toolbox、正式载荷、图导出或 ACK 端到端运行。

`tools/verify_v13_contracts.py` 是可复跑的独立 Python/NumPy 协议和数学恒等式诊断，不调用 MATLAB 实现或 `qammod/qamdemod`，不测实验 BER。任意复数输入、固定数值向量和合成区间例子明确不属于 DMT 实验数据。实际检查值、容差与状态在 `validation/v13_contract_checks.json`。

## 独立数值核对

本次实际运行 `python3 tools/verify_v13_contracts.py`，63 项检查通过：

- 正式40轮校准的1120个A/B/C/payload随机流种子互不冲突；四场景preflight另112个种子，与正式及诊断命名空间分开。
- scenario 0 的正式映射刻意沿用 v1.2 的种子公式，有220个种子编号重合。不能把旧v1.2与新v1.3称为两套统计独立样本；新代码路径必须有新真实记录，不能补旧 ACK 日志。
- rho4小信号增益 `g4=1/(4*sqrt(0.75))` 满足 `sigma_ext_sq=sigma0_sq*g4^2`。相同任意输入和原始噪声的旁路削波接收量除以g4，与线性链路在双精度容差内一致。
- 稳态DC初始化与 `h*(p-1)` 交流实现一致；跨块FIR状态、单位酉能量恒等式及Hermitian实波形一致。
- 三个IM/DD幅限固定为[0,2]，成对对称输入的均值为1，无人为归一化；`E[p]` 与 `E[p^2]` 不相同，信号不能再平方一次。
- 削波可在未用频点再生能量，不能通过重新掩蔽频点消除。AC PAPR在全局增益下不变；超越数按真实整数记录，零次仍为0/N。
- symbol-first的比特矩阵切片在分块变化下保持一致。该数学检查不等同于已验证 MATLAB RandStream 的运行时批量行为；MATLAB回归检查仍由新代码实际执行。
- 严格Wilson分类在等于阈值时为inconclusive，`u>1`不自动等于failed；Fixed16的性能失败仍是应保留的数据。
- 全部可配置时的计划预算是360组/36000000载荷符号，seed/pooled/summary/robustness分别8640/2880/120/12行。C不计入载荷，也不将三个载荷种子计为三次选阶。

## 已核对的新源码

| 范围 | 实际源码核对，不代表已执行MATLAB |
| --- | --- |
| 原有实现及历史结果 | 项目保留`run_v1_2.m`和`run_dmt_calibration_study.m`。当前本地文件搜索只发现`evidence/imported_smoke/final_results.mat`，没有完成的`final_study_results.mat`。不能把已有入口、源码或提示词提供的reference核对值称为本环境已执行结果。 |
| 配置和场景 | `dmt_v13_config.m`保留原物理规格1.0，新增协议1.3和IM/DD等效规格；三个rho只改变g及幅限条件，P0/Pmax固定1/2，三个场景共用sigma0/(16*0.75)。线性噪声方差不变。 |
| Chunk不变的比特次序 | `dmt_v13_make_frame.m`先生成B×Nsymbols的按符号比特矩阵，再按载波切片并使用一致Gray/unit-average QAM。旧v1.1/v1.2映射函数没有修改；新v1.3噪声通过固定NormalTransform=Inversion创建，另有MATLAB整块/分块回归代码。 |
| 实波形与前端 | `dmt_v13_link.m`先核对IFFT虚部再real、CP串行化、跨块保存FIR状态。IM/DD采用clip(1+g*x)后直接过滤p-1，不把p再平方作信号；p²只用于记录二阶矩。削波后没有重新屏蔽频点。线性模型的光功率量记为不适用，不伪造光功率。 |
| 估计数据隔离 | `dmt_v13_training_probe.m`独立产生A/B，块内跨chunk保存状态，块间独立重置；只保存小型已知与接收频域矩阵。`dmt_v13_rx_estimate.m`只以A估H_hat、以B估残差gamma_B，不接收C、payload或真信道。 |
| 显式理想控制路径 | `dmt_v13_exchange.m`的SNR反馈只有估计质量和身份信息，没有H_hat/H_true/噪声。发端分配函数只接收反馈和公共规则；独立重算与实际M/bit表匹配。配置通过值复制发送，Rx逐字段核对并记录ACK/hash，双方本地副本分别保存；未建模信令时延/量化/编码开销。 |
| 逐策略不可行 | Uniform/Loaded无完整表时配置为空且不可行；Fixed16始终保留24个16-QAM，继续独立C及诊断载荷。不能沿用v1.2“整轮不可行后全跳过”的处理来删除Fixed16。 |
| 独立C | `dmt_v13_probe_c.m`在ACK后用实际M及独立流发送2048符号；使用原H_hat计算gamma_C、EVM和B/C差异及候选近似。发送/接收配置和receiver在前后核对冻结，没有把C用于重新估计或选阶。差异解释同时保留有限探测波动与估计残差。 |
| 正式载荷 | `dmt_v13_payload.m`分别使用txConfig映射、rxConfig解映射，启动前要求ACK/hash及接收端scenario/calibration身份一致；使用独立数据/噪声流，按实际M逐位计数。计数累积不反向提供给发端加载。 |
| 功率/削波/PAPR | 前端记录含CP样本的p均值、二阶矩、极值、上下削波与幅限误差；PAPR仅在有用NFFT样本、偏置前AC波形上按符号统计，分母不用于缩放。payload保留实际p均值偏差及超过1%的调查标记；不能用缩放或换种子消除偏差。 |
| MATLAB回归代码 | `dmt_v13_frontend_checks.m`确有无噪声三种QAM、整块/分块数据/位序/滤波/噪声/削波计数/PAPR一致性、rho4同原始噪声旁路一致性及复频点噪声方差检查。这里核对的是代码存在与计算职责，未声称这些MATLAB检查已经通过。 |
| 内容及恢复校验辅助 | `dmt_v13_hash.m`对普通值含类型、形状、复实部编码，不包含运行时句柄。`dmt_v13_validate_run.m`核对cfg/source/map/record/config/ACK标识、实际100000符号、位/错计数、槽位种子、光功率/削波和PAPR整数计数，不以性能达标为恢复条件。 |

## 最终集成源码核对

| 范围 | 实际源码核对，不代表已执行MATLAB |
| --- | --- |
| 独立入口和作用域 | `run_dmt_v13.m`只调用新的v1.3路径。`executePhase`是入口的嵌套函数；保存、完成记录、输入复核和失败归档等辅助函数分别为文件局部函数。导出函数的六参数调用与`dmt_v13_export.m`接口一致；`seed/pooled/summary/run_status`字段与统计函数一致。 |
| 运行计划与阶段 | `preflight/linear/imdd/all`明确选择请求范围；每次正式路径先核对四场景preflight。preflight共36个短载荷组、每组2000符号，正式完整计划360组、每组100000符号；阶段目录、流命名空间和统计分开。仅linear完成不能称为360组完成。 |
| 原结果保护 | 原reference0只读核对和记录输入哈希，运行前检查输出目录不能位于原reference目录内；运行末再次核对原文件。不可访问时明确记录缺失，不使用smoke或提示词数值补成正式原结果，不补写旧ACK。 |
| 校准和恢复 | A/B、估计、反馈、两个配置副本、ACK、C及其内容哈希逐字段校验。已选择的profile在C前保存，C中断仍能保留已知承载量，但不将不完整校准记为可恢复完成。组恢复必须具有complete状态和冻结cfg/source/record/ACK/profile/种子/计数一致性；不完整或不匹配文件保留隔离后按原种子重跑整组，不将部分计数重复累加。 |
| 真实状态 | 所有计划槽位保留completed/infeasible/incomplete；只有实际100000符号且内容验证通过的正式组进入计数。恢复先加载已有其他场景的记录，分场景继续不会清空既有计数。超1%光功率均值偏差保留原组并标记调查、停止本次遍历，不缩放或换种子。 |
| 分层统计 | `dmt_v13_tables.m`只在相同scenario/calibration/scheme内汇集三个独立载荷种子，按总错误数/总比特数形成BER和逐载波Wilson近似区间。C/preflight/reference不进入正式BER。状态优先级为infeasible、incomplete、任一CI下端超过目标则failed、全部CI上端严格低于目标则supported、其余inconclusive；不同profile不混合证明合规。 |
| 跨轮承载量 | 各轮选阶频数每轮只计一次，未配置与不可行分开；跨轮承载量min/median/max没有冒充置信带。只在同轮Uniform与Loaded均supported时填写可靠性支持的承载量比值；Fixed16的误码代价单列，性能failed不阻止其他组。 |
| 正式图表 | `dmt_v13_plots.m`固定选新linear/calibration1，三个面板共享该轮gamma_B、profile和载荷计数；第三面板从实际Wilson上端/目标重算，判据1。原BER+CI另存。IM/DD图使用实际削波和各轮状态；PAPR使用calibration1整数超越计数，真实0/N不改epsilon，四场景标记与三策略线型组合可灰度区分。 |
| 输出有效期 | 中间保存只写实际表格，明确figure manifest为deferred；输入/源码冻结复核后才最终绘图。图导出异常保留原始计数、写failed manifest，入口不标记最终成功。旧范围的英文段落在新范围未完成时归档，不能把之前的说明误当当前状态。 |
| 独立结果复核入口 | `verify_dmt_v13.m`只读重建实际表格，核对完整组、配置/ACK/记录/计数哈希、独立流、种子CSV、逐槽完成文本、图文件和正式结束日志；正式复核同时递归复核preflight。其valid必须同时满足完整性和请求范围已解决，另报告实际完成数、剩余数及是否全部360组完成，不以配置中的符号数代替实际计数。 |

源码核对未发现尚未解决的集成阻断项，但这不是MATLAB运行验收。此环境实际完成的v1.3正式组数仍为0；360组正式载荷、36组preflight、MATLAB前端回归、实际数据图导出和结果复核均待可用MATLAB执行。独立Python诊断不生成实验BER或替代正式CSV。

## 科学边界

IM/DD是归一化、离散时间、采样点幅限的理想强度等效链路；不包含器件速率方程、啁啾、色散、Kerr、散粒噪声、RIN、量化、FEC或真实反馈信令开销。含削波时残差质量为effective SNR/SNDR，近邻QAM公式只是选阶启发式，必须由独立载荷检验。

跨rho变化同时包含交流驱动和削波变化，不能预设单调好坏；PAPR不作为优化目标，也不声称比特加载必然降低PAPR。相关误码与非线性下Wilson仅为统一近似逐点证据，不是联合95%保证。10/10不代表未来成功概率100%。
