# v1.3 文献映射与核实范围

本项目是作者的简化数字基带及归一化、离散时间 IM/DD 等效仿真。以下映射区分**提示词指定的文献定位/方法边界**与**本次实际取得的证据**。文献编号沿用报告的[1]–[6]，[2]仅保留原数据中心背景用途。

## 实际访问结果

本次对[1][3][4][5][6]的 DOI 入口、Crossref 元数据及[4][5]的出版社全文候选进行了13次只读 HTTPS 访问。全部在代理 CONNECT 隧道阶段返回原始错误：

```text
<urlopen error Tunnel connection failed: 403 Forbidden>
```

这是建立出版社/DOI连接之前的代理错误，不能表述为论文不存在或出版社拒绝开放获取。TLS证书验证没有关闭，没有替换校验值，也未绕过认证。**实际取得PDF为0篇，实际阅读原文为0篇，摘要及元数据也未取得或独立核实。** URL、实际UTC时间、请求类型和原错误见`literature_access_v1_3.json`。项目目前只有既有实验图PDF，不能把它当作论文原文。

因此，下表中的“原文支持的思想”均是提示词给定、尚待原文核实的映射，不声称已独立阅读相关段落。源码职责与模型边界可以从本项目代码检查；文献主张必须待原文可访问后复核。

## 思想—实现—未复现内容—定位

| 编号及原文 | 提示词指定的思想（原文未取得） | 本项目实现 | 未复现或不能归因的内容 | 原文位置及核实状态 |
| --- | --- | --- | --- | --- |
| [1] K. Zhong et al., *Digital Signal Processing for Short-Reach Optical Communications: A Review of Current Technologies and Future Trends*, JLT36(2),377–400,2018. DOI:10.1109/JLT.2018.2793881 | 按逐子载波质量进行DMT调制选择；器件带宽、线性度与DSP复杂度约束 | 用已知A/B探测估计质量，发端通过理想反馈选择QAM；IM/DD前端只表示非负与峰值约束 | 不复现综述涉及的具体器件或完整光学系统。Fig.6绿色矩形按提示词应解释为功率，不能把本项目bits图说成该文功率图的复现 | 提示词给定Section III DMT、Fig.6及线性度/复杂度讨论；本次未核实原文 |
| [2] W. Xia et al., *A Survey on Data Center Networking (DCN): Infrastructure and Operations*, IEEE COMST19(1),640–656,2017. DOI:10.1109/COMST.2016.2626784 | 数据中心网络背景，编号保持原报告不变 | 仅为报告背景，不作为本实验参数或算法依据 | 不由该综述推导DMT阶数、噪声、IM/DD尺度或统计预算 | 沿用报告背景文献；不属于本次指定技术段落核实范围 |
| [3] P. S. Chow, J. M. Cioffi, J. A. C. Bingham, *A Practical Discrete Multitone Transceiver Loading Algorithm for Data Transmission over Spectrally Shaped Channels*, IEEE TCOM43(2–4),773–775,1995. DOI:10.1109/26.380108 | 有限星座、比特分配和性能余量的思想 | 每独立载波平均Es固定为1；在[4,16,64]内按含1dB余量的近邻BER近似选最大可行阶数 | 不含逐子载波能量调整，不是完整Chow比特/功率联合加载；本项目Gray-QAM近邻BER公式不能称为直接摘自该文SNR-gap公式 | 提示词及前版指定Section II、步骤10–11；本次未核实原文 |
| [4] K. Zhong et al., *Experimental Study of PAM-4, CAP-16, and DMT for 100 Gb/s Short Reach Optical Transmission Systems*, Optics Express23(2),1176–1189,2015. DOI:10.1364/OE.23.001176 | 收发DSP、探测辅助选阶以及共同链路条件下的格式比较 | 在相同固定物理条件下比较Uniform/Loaded/Fixed16，使用独立探测及已知QPSK | 不声称复制该文具体探测格式、器件限制或100Gb/s硬件实验；本项目无实际光器件 | 提示词指定Section2.3与Section4；本次出版社PDF候选也被代理阻断，未读原文 |
| [5] S. A. Gebrewold et al., *Bit- and Power-Loading—A Comparative Study on Maximizing the Capacity of RSOA Based Colorless DMT Transmitters*, Applied Sciences7(10),999,2017. DOI:10.3390/app7100999 | 按提示词，Section4用等功率QPSK探测、接收EVM测量计算逐子载波SNR | 独立QPSK块B测量均衡残差质量；ACK后用实际配置生成独立C，检查B到已加载波形的质量迁移 | 不是RSOA器件实验，不包含该文的功率加载或器件模型；本项目C诊断和理想ACK不是声称从该文照搬的实现 | 提示词指定Section4；DOI、MDPI HTML和PDF均未取得，QPSK/EVM细节仍未独立核实 |
| [6] R. Jiang, Q. Wang, F. Wang, L. Dai, Z. Wang, *An Optimal Scaling Scheme for DCO-OFDM Based Visible Light Communications*, Optics Communications356,136–140,2015. DOI:10.1016/j.optcom.2015.07.053 | 在固定偏置/功率约束下，交流驱动与削波失真的权衡 | 固定P0=1、Pmax=2，以rho预设三种交流驱动g，再作采样点幅限，记录功率、幅限误差及实际BER | 不采用VLC LED参数，不将其结果作为光纤器件参数依据；不声称执行原文最优缩放求解或完整连续时间峰值模型 | 提示词给定题名/DOI及限定用途；本次DOI/元数据均未取得，原文具体推导未核实 |

## 本项目自主预设，不是文献规定

- 线性物理规格1.0：NFFT64、CP8、Fs64MHz、k1:24、h=[0.25,0.5,0.25]、星座平均Es1和sigma0_sq=10^(-29/10)。29dB是参考Es/噪声方差，不是OSNR。
- 每场景10次校准；A1024、独立B2048、各配置独立C2048；每个可配置策略三个载荷标签，各100000符号，分块不超过2000；全计划360组。
- 目标BER1e-3、加载余量1dB、候选[4,16,64]、Gray映射和近邻BER启发式规则。
- 归一化离散时间IM/DD：P0=1、Pmax=2、rho为4/2.5/1.5，g=1/(rho*sqrt(0.75))，三个场景固定sigma_ext_sq=sigma0_sq/(16*0.75)。该噪声尺度预先声明，不能依据最终BER重调。
- 理想SNR反馈、双方配置副本和ACK是软件功能假设，不是经过物理反馈信道验证的协议。没有建模的时延、编码或量化不能表述为已验证开销为零。
- 逐点95% Wilson近似、归一化区间上端点图、profile选择次数和完成状态规则均为统一教学证据口径，不是文献指定的性能门限或联合覆盖保证。
- 交流PAPR统计在偏置/削波前的每符号有用样本上计算，只作为诊断，不优化或声称比特加载必然降低PAPR。
- v1.3使用冻结的`mt19937ar`与`Inversion`正态变换，并按符号优先的比特生成顺序实现chunk不变性；这是实现选择，不是光学模型参数或文献结论。

## 解释结果时必须保留的边界

`p`是归一化发射光功率，理想探测电流与其成比例；不能在接收信号路径再次平方p。`E[p]`与`E[p^2]`是不同量，不能混成平均光功率。

削波场景的B/C残差质量是effective SNR/SNDR，包含估计误差和失真；近邻QAM公式只作启发式选阶。B/C差异也含有限样本波动，不能全部归因于削波或高阶QAM。C不更新H_hat、加载表或场景，正式payload不参与选阶。

rho变化同时改变交流驱动和幅限程度，P0始终不变；不能预设性能必须单调变化。采样点削波不代表完整连续时间峰值。仅同场景/同校准/同策略/同k合并三个载荷种子；不混合profile证明每轮合规，也不把十轮观察比例当作未来成功率。

本模型不含真实激光器速率方程、啁啾、色散、Kerr非线性、散粒噪声、RIN、量化、FEC或真实反馈信道。结论限于固定电域FIR与归一化理想强度前端，不推广为实际数据中心光链路有同一倍数收益。
