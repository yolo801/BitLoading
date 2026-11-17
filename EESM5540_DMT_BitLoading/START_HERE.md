# 本地 MATLAB 运行入口

**tradeoff_v1任务请看[TRADEOFF_START_HERE.md](TRADEOFF_START_HERE.md)，完整入口为`result = run_dmt_tradeoff('all');`。** 本轮代码由你在本地运行，新增预检及正式实验尚未执行。

**v1.3任务请看[V1_3_README.md](V1_3_README.md)，入口为`run_dmt_v13('all')`。** 旧入口保留以便复核历史；它们不会执行新增IM/DD与显式反馈路径。

**v1.2的新任务请先看[V1_2_README.md](V1_2_README.md)，使用`run_v1_2(referenceDir)`。** 下文是保留的v1.1单校准main入口，不会执行新增十轮研究。

你负责在本地 MATLAB 运行实验；本次交付提供代码、运行入口和自动验收。物理参数、校准和随机流沿用已检查的 v1.1，不增加实验或调整样本数。

## 最短操作

1. 解压整个项目，保留 `private/` 和 `evidence/imported_smoke/`。
2. 在 MATLAB R2026a 中进入项目目录；需要 Communications Toolbox，正常 JVM 模式启动。
3. 在命令窗口输入：

```matlab
result = run_main;
```

入口使用包内校准，先做自检和三策略 smoke，然后继续全部九组正式测试。每个策略使用11、22、33三个种子，每个种子100000个载荷符号，分块2000，不因BER调整试验。

九组结束后，入口自动调用 `verify_main_results`，交叉核对 MAT、逐种子CSV、pooled CSV、汇总、Wilson区间、代码/初始化标识、结束日志及输出文件。Fixed16超出目标不会被当成数据完整性失败。

## 可选命令

单独做程序预检：

```matlab
run_smoke
```

复核已经完成的某次 main，不重跑载荷：

```matlab
check = verify_main_results('C:/work/your_main_result_directory');
```

Windows批处理（修改项目路径）：

```powershell
matlab -batch "cd('C:/work/BitLoading/EESM5540_DMT_BitLoading'); run_main"
```

Linux/macOS从项目目录：

```sh
matlab -batch "run_main"
```

## 结果与验收

成功后 `result.output_dir` 给出唯一的新结果目录。正式图为该目录根部的 `dmt_comparison.png/.pdf/.fig`，正式表为 `summary.csv`、`per_subcarrier_seed.csv`（216行）、`per_subcarrier_pooled.csv`（72行）和 `nominal_vs_measured.csv`；MAT、配置、校准来源、种子、哈希、运行日志和中英文说明一并保存。

`main_completion_check.mat` 是 `run_main` 追加保存的独立完成核对；逐项数值日志另存为`main_completion_check.txt`，不覆盖原`run.log`。数据核对成功不等于性能必然达标；Uniform/Loaded的目标证据及Fixed16的诊断状态仍以实际区间为准。零误码也有非零上界。

历史 smoke 与之前的云端启动记录完整保留；它们不进入新main统计。当前交付包没有预置新的正式结果。详细参数、物理边界与输出口径见 `README.md`。
