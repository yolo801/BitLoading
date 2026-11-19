# VCSEL–MMF 三档调制实验

在 MATLAB 的当前文件夹中进入 `EESM5540_DMT_BitLoading/dmt_vcsel_mmf_2025/three_order`。本入口使用父目录中既有的 MATLAB 链路和 Fig. 2(a) 信道证据。需要 MATLAB、Communications Toolbox 和 JVM。

```matlab
s = run_dmt_vcsel_three_order('selfcheck');
assert(s.valid)
disp(s.expanded_band_gate.status)

r = run_dmt_vcsel_three_order('run');
disp(r.status)
disp(r.output_dir)
```

`selfcheck` 核对频响、CP、无噪声三档 QAM 链路、短光功率标定、种子隔离、摆幅排序和 Wilson 判据。候选扫描与正式载荷计数均为零。扩带门控的完整状态位于 `s.expanded_band_gate`。

`run` 先扫描 0.25–60 GHz、8-bit ADC 的 Case 2，摆幅为 0.55–0.70，步进 0.01。每档使用新的独立流做 A0、B0、候选标定、Ar 和 Dr。B0 提案和候选降阶沿用 `PerToneValidated`。同一最终表须通过全频带独立候选验证，且 QPSK、16-QAM、64-QAM 各至少有五个载波。选择离 0.625 最近的合格摆幅，同距取较低者。

若首轮扫描无合格候选，程序先核对 62 GHz 扩带门控，再用独立种子启动该频带的扫描。扩带仍使用原 Case 2 17 抽头 FIR、16 点 CP 和原功率模型，按 248 个活跃载波计算参考交流能量。62 GHz 位于公开 Fig. 2(a) 数字化样点范围内，增益由两侧样点线性内插。门控失败或扫描无合格候选时保存相应状态。选定配置后出现正式 BER 或功率不达标时保留结果并结束。

每次运行最多发送同一冻结配置的两个独立正式载荷，每个 25,000 个含 CP 的 DMT 符号。该长度和重复数沿用原项目。逐载波合并两份整数计数，采用严格的逐点 95% Wilson 上限小于 10⁻³ 判据，同时核对实际发射平均光功率。合格才导出 `Figure_1_three_order_DMT.png`、矢量 `Figure_1_three_order_DMT.pdf` 及 `Figure_1_three_order_DMT_caption_en.txt`。图中竖线是仿真 FIR 的实际陷波，图注另列公开曲线的数字化陷波。

输出默认位于 `three_order/results/` 下新建的运行目录。每个频带有各自的目录、门控回执和种子表。可用 `'OutputDirectory'` 提供一个尚不存在且父目录已经存在的输出路径。主要记录包括 `swing_scan.csv`、逐摆幅候选记录、`frozen_candidate.mat`、正式逐槽与合并计数、正式验证回执以及源码清单。生成图时，三幅子图共享同一工作点、同一校准记录和同一冻结配置的指纹。
