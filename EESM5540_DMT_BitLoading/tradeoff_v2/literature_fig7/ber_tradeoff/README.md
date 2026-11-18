# Fig. 7 信道的 BER、周期速率与验证开销

本模块在冻结的九抽头 Fig. 7 等效信道上完成两项独立研究。冻结信道及 v2 数值核心由原版 Fig. 7 实验和上传的正式批次确认。旧结果目录保持只读。

## 执行顺序

需要 MATLAB、Communications Toolbox 和 JVM。解压完整 GitHub 源码 ZIP，进入本目录。将上传的历史结果 ZIP 另行解压成完整目录，传入包含 `Protocol.mat` 的这一层。

```matlab
cd('你的解压路径/EESM5540_DMT_BitLoading/tradeoff_v2/literature_fig7/ber_tradeoff')
r = run_dmt_fig7_ber_tradeoff('all','HistoricalDirectory','历史结果目录的完整路径');
```

`all` 先在隔离目录执行两项短数据预检。通过后先运行实验二，再审核实验二并启动实验一。两个正式实验的实际发送槽位各含 50,000 个 DMT 符号。

- 实验二为 `promotion`。20 个计划槽位。在 1.0／8-bit 的五轮新校准比较原验证流程与第 23 个子载波优先升阶的流程。每个尝试做独立 TX 标定、A_r 训练和 D_r 验证。整张候选表通过才允许发送正式载荷。失败后以该分支自己的新种子回退。
- 实验一为 `scan`。240 个计划槽位。条件编号为 5、6、8、9、11、12、14、15。每个工作点比较固定 QPSK、固定 64-QAM 和原验证式加载，不使用升阶分支。历史条件 9 只有通过原验证器和完整身份核查才复用 30 槽。省略 `HistoricalDirectory` 或历史数据不兼容时，重新测量这个工作点。

可以分步运行。下面的 `promotion` 和 `scan` 命令要求本版本的已验证门控目录。

```matlab
pf = run_dmt_fig7_ber_tradeoff('preflight');
p = run_dmt_fig7_ber_tradeoff('promotion','PreflightDirectory',pf.promotion_preflight.output_dir);
s = run_dmt_fig7_ber_tradeoff('scan','PreflightDirectory',pf.scan_preflight.output_dir, ...
    'PromotionDirectory',p.output_dir,'HistoricalDirectory','历史结果目录的完整路径');
```

中断时保留失败日志和所有检查点，并在相同、完整的源码工作树中恢复指定目录。已提交的共享校准、策略配置或载荷检查点保持原样。进程若在一个配置或载荷的原子检查点提交前中断，恢复时按冻结种子重新执行该未提交单元。

```matlab
r = run_dmt_fig7_ber_tradeoff('resume','OutputDirectory','未完成结果目录');
audit = verify_dmt_fig7_ber_tradeoff(r.output_dir);
redrawFolder = redraw_dmt_fig7_ber_tradeoff(r.output_dir);
```

## 输出

每次正式采集写入 `results/fig7_ber_promotion_formal_*` 或 `results/fig7_ber_scan_formal_*`。包含冻结协议、源清单、种子表、运行日志、历史复用凭据、实际检查点、逐槽和逐载波计数、验证回执及图表清单。图 A 使用实验二预先固定的第 1 轮。图 B 使用实验一各点的最大实测平均发射光功率与全五轮达标周期速率，同时输出 75 Mbit/s 判据表。PNG 和矢量 PDF 可从通过验证的正式结果重绘。

逐点 95% Wilson 区间从同一轮两个独立正式载荷的合并计数计算。每轮每载波上限均低于 BER 目标时，该轮才达标。五轮之间保持各自的统计。周期分母从真实训练和验证开销加 50,000 个载荷符号计算。TX-only 标定的符号和耗时另记。理想反馈时延为零。

ADSL2 和 VDSL2 展示了逐频点加载的实际用途，高质量频点可分配较多比特，较差频点可减少承载或停用。本仿真始终保留 24 个活跃子载波。此处的 ADC 位数描述量化与实现要求，训练和验证开销通过实际发送符号数及周期速率表达。Fig. 7 等效幅度模型代表指定工作点的简化仿真；论文的接收功率扫描采用不同的物理量。

本目录的 `validation/matlab_attempt.log` 保存云端启动原始结果。历史正式批次的数据身份见 `evidence/historical_model.json`。
