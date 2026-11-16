# 作者的简化数字基带仿真：结果说明

本文件仅由已完成的 MATLAB 载荷运行生成；数值来自本目录计数，不是文献数据。
运行模式：smoke。

## 实际观察与验收

本次仅为 smoke 程序检查，不纳入正式 BER 统计，不能作为目标 BER 验收或性能优势证据。

Uniform：B=48 bits/DMT symbol，R_payload=42666666.7 bit/s，测试 2000 符号（0.00225 s），0 / 96000 bit errors，加权总 BER=0，最差子载波 BER=0，最大区间上界=0.000959478517，状态=smoke_only_not_formal_evidence。
实际归一化电能量：有用段均值 48，CP 段均值 6.00537815，含 CP 平均功率 0.750074696，含 CP 平均符号能量 54.0053781；对应期望为 48、6、0.75、54。
Loaded：B=120 bits/DMT symbol，R_payload=106666667 bit/s，测试 2000 符号（0.00225 s），10 / 240000 bit errors，加权总 BER=4.16666667e-05，最差子载波 BER=0.000416666667，最大区间上界=0.000975112336，状态=smoke_only_not_formal_evidence。
实际归一化电能量：有用段均值 47.8885333，CP 段均值 5.93581404，含 CP 平均功率 0.74756038，含 CP 平均符号能量 53.8243474；对应期望为 48、6、0.75、54。

Loaded/Uniform 的载荷比为 2.5；估计电符号 SNR 范围 12.1442 至 28.9622 dB。
一次初始化为 3072 个 DMT 符号，持续 0.003456 s；不计为载荷。

低通 FIR 使高频子载波衰减较大，加载器根据独立探测块得到的实际估计选择阶数。低频通常允许更多比特，但必须以本次 profile 为准，不能手改为理论 118 bits。
Loaded 的 BER 未必比 Uniform 低：它在质量较好的子载波采用更密集星座，用误码余量换取更多比特。比较目标是同等平均 Es 和噪声条件下满足目标时的承载量，不是要求总 BER 更低。

## 零误码与统计范围

CSV 中 BER=0 只表示零次观察误码；对数图仅在 Wilson 上界位置画倒三角（Uniform 空心，Loaded 实心），绝不把上界当作 BER 点估计。以下逐一保留计数与上界。
Uniform k=1: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=2: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=3: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=4: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=5: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=6: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=7: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=8: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=9: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=10: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=11: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=12: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=13: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=14: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=15: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=16: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=17: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=18: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=19: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=20: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=21: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=22: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=23: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Uniform k=24: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Loaded k=1: 0 observed errors / 12000 tested bits; pointwise 95% Wilson upper=0.000320030881.
Loaded k=2: 0 observed errors / 12000 tested bits; pointwise 95% Wilson upper=0.000320030881.
Loaded k=3: 0 observed errors / 12000 tested bits; pointwise 95% Wilson upper=0.000320030881.
Loaded k=4: 0 observed errors / 12000 tested bits; pointwise 95% Wilson upper=0.000320030881.
Loaded k=5: 0 observed errors / 12000 tested bits; pointwise 95% Wilson upper=0.000320030881.
Loaded k=6: 0 observed errors / 12000 tested bits; pointwise 95% Wilson upper=0.000320030881.
Loaded k=7: 0 observed errors / 12000 tested bits; pointwise 95% Wilson upper=0.000320030881.
Loaded k=8: 0 observed errors / 12000 tested bits; pointwise 95% Wilson upper=0.000320030881.
Loaded k=9: 0 observed errors / 12000 tested bits; pointwise 95% Wilson upper=0.000320030881.
Loaded k=10: 0 observed errors / 12000 tested bits; pointwise 95% Wilson upper=0.000320030881.
Loaded k=11: 0 observed errors / 12000 tested bits; pointwise 95% Wilson upper=0.000320030881.
Loaded k=12: 0 observed errors / 12000 tested bits; pointwise 95% Wilson upper=0.000320030881.
Loaded k=13: 0 observed errors / 12000 tested bits; pointwise 95% Wilson upper=0.000320030881.
Loaded k=16: 0 observed errors / 8000 tested bits; pointwise 95% Wilson upper=0.000479969519.
Loaded k=17: 0 observed errors / 8000 tested bits; pointwise 95% Wilson upper=0.000479969519.
Loaded k=18: 0 observed errors / 8000 tested bits; pointwise 95% Wilson upper=0.000479969519.
Loaded k=19: 0 observed errors / 8000 tested bits; pointwise 95% Wilson upper=0.000479969519.
Loaded k=22: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Loaded k=23: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.
Loaded k=24: 0 observed errors / 4000 tested bits; pointwise 95% Wilson upper=0.000959478517.

95% Wilson 区间是常用二项近似、逐子载波的 pointwise 区间，不表示 24 个子载波同时有 95% 联合覆盖率。主实验三个种子共享一次冻结的信道估计和 profile，只验证该条件下的性能，未验证跨信道或跨初始化鲁棒性。
总 BER 按所有测试比特加权；不能直接平均变阶子载波的 BER。smoke 不计入 main 的计数。

## 单位、速率及模型局限

rho_ref=Es/sigma_w2=29 dB 只是电符号参考量；图的 SNR 是均衡后 Es/N0 口径的误差估计，不是 Eb/N0、OSNR 或时域波形 SNR。所有能量是归一化电能量，并非光功率。
R_payload=B/Ts 已包括 CP 时间；不扣一次初始化、反馈或 FEC，不能标为含全部开销的净吞吐量，也不能再次扣 CP。平均 Es 固定不代表峰值或含直流偏置的功率公平性。
该因果实 FIR 只代表端到端电域频率响应，不是器件实测数据。未建模光器件、直流光偏置、非线性、削峰、量化、色散、FEC、功率加载或 PAPR。PAPR 限制仍由报告引用的文献说明。它不是光学硬件实验、100 Gb/s 光传输复现或完整 Chow 算法。

## 老师可能问的三个问题

1. 为什么负频率不重复计入比特？Hermitian 镜像由正频率唯一确定，只用于产生实波形，独立载荷只有 k=1:24。
2. 为什么训练与探测分开？块 A 估计 H_hat，独立块 B 测量均衡残差，避免重复使用拟合数据低估残差；正式载荷不参与任何估计或调参。
3. 能否推论真实短距光链路也有相同比例增益？不能。这里只验证固定电域 FIR 与 AWGN 下的机制，未包括器件、光功率或完整开销，且仅共享一次冻结校准。

## 报告与文献

保留报告 Figure 1 的收发框图。本目录组合图可替换纯解析 Figure 2；原 abstract/report 未自动改动，最终仍需自行控制四页与四分钟。标注为作者的简化数字基带仿真，不得标为文献 Fig. 6 数据。文献 Fig. 6 绿色矩形表示功率分配，本图 (b) 只表示比特分配。
背景/方法参考：Zhong et al., JLT 2018, DOI 10.1109/JLT.2018.2793881；Xia et al., COMST 2017, DOI 10.1109/COMST.2016.2626784；Chow et al., TCOM 1995, DOI 10.1109/26.380108；Zhong et al., OE 2015, DOI 10.1364/OE.23.001176。本参数不是从这些文献抽取的实验参数。
