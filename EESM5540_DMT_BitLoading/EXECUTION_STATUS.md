# 代码交付状态：本地 MATLAB 运行

本次职责已调整：提供代码文件、入口、自动核对与运行说明；实验由你在本地 MATLAB 执行。不需要为此聊天配置 MATLAB 执行环境。

## 本次新增与整理

- `run_main.m`：固定使用包内校准，调用main，随后独立检查真实完成计数。
- `run_smoke.m`：可选程序预检；main本身会先做预检。
- `verify_main_results.m`：独立核对九组、216/72行、MAT/CSV一致性、Wilson区间、标识、图和结束日志，不重新发送载荷。
- `START_HERE.md`：本地最短运行步骤。
- `payload_counts.mat`：main在九组完成、正式导出前保存的计数快照；它不单独代表完整main。

物理规格1.0、协议1.1、三策略、校准和随机流规则保持不变。历史smoke、旧源码提交及启动记录保留。

## 代码检查与实验运行的区分

新增代码未在MATLAB执行。语法/静态检查与独立公式、历史文件一致性检查的实际命令和结果保存在`validation/`；它们不能代替本地MATLAB运行验证。

包内`evidence/imported_smoke/`是用户原先的真实本地smoke（每方案2000符号），不是新main。没有预制本次正式BER、正式图或带虚构结果的英文段落。正式性能结论由你运行后的真实计数产生。

## 本地继续

在项目目录输入：

```matlab
result = run_main;
```

成功后读取`result.output_dir`中的正式输出与`main_completion_check.mat`。独立复核已有目录：

```matlab
check = verify_main_results('C:/work/your_main_result_directory');
```

Fixed16超过BER目标属于诊断性能结果，不是数据完整性失败；Uniform/Loaded的可靠性证据和承载量优势仍按真实区间分别判断。

此前云端启动尝试仅属历史记录，见`docs/HISTORICAL_EXECUTION_STATUS_before_handoff.md`及`execution_attempts/`，不再作为本次代码交付的前提。
