# DMT tradeoff_v2

本工程基于 `f2f889e` 的修订版 v1。进入 `EESM5540_DMT_BitLoading/tradeoff_v2` 即可运行。需要有 JVM 的 MATLAB 与 Communications Toolbox。运行时会记录 MATLAB 版本、工具箱与 `which -all` 路径。本次交付状态见 `validation/runtime_attempt.txt`。

`validation/plans/` 提供三个阶段的计划 CSV 供审阅。运行入口会依据冻结常量重新生成对应计划，并把实际采用的计划写入该次协议身份。预先列出的载荷槽表示计划发送量。

```matlab
pre = run_dmt_tradeoff_v2('preflight');
check = verify_dmt_tradeoff_v2(pre.output_dir);
```

预检保存为 `test_only`，只包含 `(1.0,8)`、`(1.2,6)`，每点一轮、两重复，每个授权槽 2000 符号，共 12 个计划槽。它检验流程、实际计数和身份。科学判定仍取自对应计数，预检结果不进入正式合格工况。

已有批次的图表清单可单独只读复核：

```matlab
figures = verify_dmt_tradeoff_v2_figures('填写原预检结果目录的完整路径');
```

该入口记录清单绝对路径、第一行、导入选项、导入尺寸和列名，复核保存的表哈希与图件哈希。结果字段是 `figure_audit_passed`。完整预检仍由 `verify_dmt_tradeoff_v2` 检查原源码身份、检查点和失败回执，最终结果字段为 `valid`。如果源码已换版或原目录留有失败回执，完整复验需要新目录中的预检。

手动启动正式扫描，完成后可单独只读复核。每次运行生成新的 `results/tradeoff_v2_<phase>_*` 目录。

```matlab
main = run_dmt_tradeoff_v2('formal');
check = verify_dmt_tradeoff_v2(main.output_dir);
```

正式计划含 5 个目标平均光功率、3 档 ADC、5 轮校准、3 种策略、2 个载荷重复，共 450 槽，每槽 50000 符号。固定 QPSK 和固定 64-QAM 在各自调制表与功率下用 1024 个已知符号训练，配置同步后完整发送。加载组的 QPSK A0/B0、逐载波初选、独立 D 验证与最多四轮回退沿用当前接线。真实加载拒绝保留未发送状态，运行故障保留首个完整堆栈及已完成记录。

正式目录通过只读复核后，可手动执行独立 2×2 诊断，每个授权槽 50000 符号，共 40 个计划槽。诊断按配对锁定交流增益，分别求解两个峰值限制下的直流偏置。6-bit 与连续参考共用输入饱和范围。诊断写到单独目录。

```matlab
diagResult = run_dmt_tradeoff_v2_diagnostic(main.output_dir);
diagCheck = verify_dmt_tradeoff_v2_diagnostic(diagResult.output_dir);
```

## 读取结果

- `Protocol.mat`、`source_manifest.csv`、`seed_plan.csv` 记录阶段、源码、模型、机器及配对随机流身份。数据和噪声键明确标记允许的复用。固定策略跨 ADC 配对使用同一发射数据与同一功率校准，接收端各自训练。三策略跨 ADC 的载荷噪声按功率、校准、重复配对，加载组的数据流独立于固定组。
- `checkpoints/` 保留共享探测、每策略设计和完整载荷。`status.csv` 保留全部计划槽。`seed.csv` 和 `pool.csv` 分别是逐重复的真实整数计数与两个完整重复的池化计数。
- `summary.csv` 给出逐轮 BER 和功率状态、最差 Wilson 上界、实际配置及周期速率。`scenario.csv` 给出五轮各状态和合格周期速率范围。`pair_gains.csv` 给出逐重复功率差，满足点内同目标功率条件和科学判据后才读配对增益。`requirements.csv` 按已测试合格点列出业务速率所需功率。
- `profiles.csv`、`snr.csv`、`design_rounds.csv`、`power_adc.csv`、`overhead.csv` 分别提供加载表、B0 有效 SNR、各轮 D 计数、发射削波及 ADC 越界、训练和软件开销。`R_cycle` 以单次 50000 符号载荷周期计算，固定组只计自身训练，加载组计实际训练与探测和验证。热噪声、功率和 ADC 范围按附件冻结。
- 英文图以 PDF/SVG/PNG 导出，`figure_manifest.csv` 将成图文件与重建表哈希配对。无实测数据或无合格点时保存原因。预检图显示 `TEST ONLY`。诊断图与主实验图各自读取独立记录。

Wilson 区间是逐载波的近似区间。光功率采用归一化单位，五轮范围是观测极值。ADC 位数是简化接收模型的量化参数。`verification_receipt.mat` 报告采集是否完整及验收是否通过，科学未达标通过 `summary.csv` 和 `scenario.csv` 理解。

在 Windows MATLAB 已进入该目录时，入口可从命令窗口直接调用。也可从终端在该目录批处理执行 `matlab -batch "run_dmt_tradeoff_v2('preflight')"`。查看错误请保留首个 `failure_status.txt`、`run.log` 与原结果目录。

## 源码差异

新增 `run_dmt_tradeoff_v2.m`、`verify_dmt_tradeoff_v2.m` 及两个诊断入口。`private/dmt_t2_*` 封装新协议、种子、固定组授权、计数和图表。现有调制、信道、训练、独立验证和计数原语从修订版 v1 复制进子工程。隔离副本 `dmt_to_validate.m` 用与载荷一致的减法除法顺序计算相对功率误差，以统一容差边界的浮点判定。v1 原路径各文件的字节一致性及实际检查记录见 `validation/`。
