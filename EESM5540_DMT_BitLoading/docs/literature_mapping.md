# v1.2 文献映射与核实状态

## 本次证据范围

**本次未取得、未阅读以下三篇论文的原文PDF，也未独立核实DOI对应的出版元数据。** 下面的题名、编号、原文定位和文献边界来自用户提供的v1.2任务说明；它们不应被误写成已经由本次工具访问确认的引文。项目实现一栏则根据实际`.m`源码核对。

项目中搜索到的PDF只有`evidence/imported_smoke/dmt_comparison.pdf`，它是仿真图而非文献。2026年11月17日实际尝试了三条DOI链接、Optica全文/PDF候选入口和三条Crossref元数据入口，共8次请求。全部在代理隧道阶段失败，原始错误均为：

```text
URLError: <urlopen error Tunnel connection failed: 403 Forbidden>
```

这是代理CONNECT返回的错误，尚未收到DOI解析器、出版社正文或Crossref元数据响应，不能据此宣称论文付费墙拒绝或原文不存在。访问全过程使用默认TLS验证，没有关闭校验、改动网络配置或绕过登录。逐请求URL、UTC时间和原错误见`literature_access.json`。

## 思想—实现—边界—原文定位

| 原编号与任务给定的思想 | 本项目实际实现 | 未复现或不能据此宣称的内容 | 用户给定的原文定位与本次核实状态 |
| --- | --- | --- | --- |
| [1] 将子载波质量探测作为不同QAM阶数选择的依据；此处先作为待核实的思想背景 | `private/dmt_calibrate.m`用独立QPSK块A估计`H_hat`，再用独立块B的均衡残差得到`gamma_hat`；`private/dmt_load_profiles.m`据该估计选阶，真实信道FFT只供诊断 | 不是完整光DSP链路或器件实测；不复制图中的功率分配。任务指出Fig.6绿色矩形表示功率，本项目bits/subcarrier面板只表示比特，不能互相替代或标成原文数据 | **未核实原文**：任务指定PDF第5页Fig.6、第6页Section III中DMT段。需取得PDF后核对探测/选阶描述与图例，不声称本次已经看过该图或该节 |
| [3] 有限星座、比特分配与性能裕量思想；具体步骤及能量调整内容按任务给定边界暂列 | 候选`M=[4,16,64]`，各活跃子载波星座平均`Es=1`，`gamma_hat/10^(1/10)`用于含1dB裕量的保守近邻BER选阶；Uniform取最高可行公共阶数，Loaded逐子载波取最大可行阶数 | **不是完整Chow算法复现**：没有逐子载波能量调整、功率加载或完整SNR-gap优化。`private/dmt_qam_ber.m`中的Gray square-QAM近邻BER公式是本教学规格采用的近似，不能写成直接摘自Chow的SNR-gap公式 | **未核实原文**：任务指定Section II、步骤10—11。未取得原文，因此不补造步骤原文或把“性能裕量”扩写成已核实的具体算法等价性 |
| [4] 探测辅助选阶、共同链路条件对照和硬件限制讨论；此处先作为待核实背景 | 项目使用已知QPSK训练/探测、真实CP/FIR数字基带收发、相同子载波集合/平均电能量/噪声和时长下的Uniform、Loaded与Fixed16；正式载荷不参与校准或调参 | **不是该文100Gb/s硬件实验的复现**；没有光器件、光功率、直流光偏置、削峰、量化、非线性、色散、FEC或PAPR实验。任务描述该文使用不同调制格式探测，本项目的QPSK加近邻BER规则不能声称等同于该文具体探测实现 | **未核实原文**：任务指定PDF第5页Section 2.3和第10页Section 4。尚未确认具体探测调制、实验对照或硬件限制的原句，不根据题名猜测 |

以上三条映射用于约束本项目如何表述方法，**不表示本次已经从原文提取或验证这些内容**。正式报告若保留对应的具体页码/步骤论述，应由可访问的原文补核；在此之前可准确写“本项目按预先给定教学规格实现”，不能写“本次已核实原文并复现该方法”。

## 本项目自行预先设定的内容

下列设置是本项目实验设计，不应归因于[1]、[3]或[4]规定：

- 10轮独立校准，reference calibration 0另存且不计入新10轮。
- 每轮1024个训练符号、2048个独立探测符号，1dB裕量、目标未编码逐子载波BER `1e-3`。
- 三策略各3个种子、每种子100000个载荷DMT符号，固定FIR、接收实噪声和星座平均电能量。
- pointwise 95% Wilson二项近似区间，以及`u_k=CI_high/targetBER`、判据线1的新Figure 2(c)。这是约束检查量，不是Observed BER，也不是全部子载波的联合95%覆盖保证。
- 校准轮内按同一profile合并三个载荷种子；跨轮只报告状态次数、承载量范围及选阶频数，不混合不同profile的计数来证明单个profile合规，不把范围称为95%置信带。

10/10只是这10轮观察结果，不能外推为未来总体成功概率100%；固定物理信道下的校准/选阶稳定性，也不能称为跨物理信道或真实光器件鲁棒性。

## 保留原报告编号

- [1] K. Zhong et al., “Digital Signal Processing for Short-Reach Optical Communications: A Review of Current Technologies and Future Trends,” *Journal of Lightwave Technology*, 36(2), 377–400, 2018. 任务给定DOI：[10.1109/JLT.2018.2793881](https://doi.org/10.1109/JLT.2018.2793881)。
- [2] W. Xia et al.的Data Center Networking背景综述继续保留原编号；本次不把它当作QAM加载、Wilson区间或重复校准规则的来源。
- [3] P. S. Chow, J. M. Cioffi, and J. A. C. Bingham, “A Practical Discrete Multitone Transceiver Loading Algorithm for Data Transmission over Spectrally Shaped Channels,” *IEEE Transactions on Communications*, 43(2–4), 773–775, 1995. 任务给定DOI：[10.1109/26.380108](https://doi.org/10.1109/26.380108)。
- [4] K. Zhong et al., “Experimental Study of PAM-4, CAP-16, and DMT for 100 Gb/s Short Reach Optical Transmission Systems,” *Optics Express*, 23(2), 1176–1189, 2015. 任务给定DOI：[10.1364/OE.23.001176](https://doi.org/10.1364/OE.23.001176)。

书目信息保持用户任务给定内容，没有因访问失败重新编号或推测替换。报告原Figure 1、摘要与正文未由本映射文件修改；参考0主图与10轮稳定性结果应分别解释，不能宣称普遍2.5倍光链路收益。
