# 本地代码交付：实际检查命令与范围

本次提供代码文件，由用户本地运行MATLAB实验。没有执行新增MATLAB入口，也没有生成新的实验计数、正式结果图或结果段。

## 实际完成的检查

在项目目录执行并逐一核对退出码：

```sh
PYTHONPATH=/tmp/eesm5540_lint python3 -m miss_hit.mh_lint --input-encoding utf-8 --brief --single .
python3 tools/verify_implementation.py
python3 tools/audit_uploaded_smoke.py
git diff --check
```

各命令退出码均为0：

- MISS_HIT 0.9.44：24个MATLAB文件通过语法/静态检查。见`matlab_static_lint.txt`。
- 75项独立公式与源码约定诊断通过。见`python_diagnostics.txt`。这些Python检查不调用MATLAB或qammod，不测本实验BER。
- 211项用户上传历史smoke一致性检查通过，包括14个原文件SHA-256、配置、profile、计数与统计口径。见`uploaded_smoke_audit.md/.json`。这是读取原有结果，不是生成新的MATLAB实验结果。
- 新增文本的尾随空格和结尾换行检查通过。原始历史证据按字节保留，.gitattributes防止Git换行转换；未更改原14文件内容。

`source_manifest_v1_1.csv`记录当前26个代码文件（24个MATLAB文件及2个可选Python诊断脚本）的SHA-256与字节数。真正本地运行时，MATLAB仍会为当次运行保存实际源码清单与初始化标识。

## 新增代码的核对范围

新增`run_main.m`、`run_smoke.m`和`verify_main_results.m`经过源码审查及静态检查。主入口使用包内校准并自动做独立验收；验收函数不改动结果或重跑载荷，并将实际计数、统计状态与文件完整性分开。

main新增导出前`payload_counts.mat`保护九组计数；状态为待导出，不能单独当作完成证明。只有实际完整main及全部结果文件、结束日志经核对，run_main才输出完成报告。

本次未在MATLAB执行，因此Communications Toolbox调用、Java哈希的MATLAB运行时、图导出以及新验收函数的运行仍由本地实验验证。旧云端启动记录保存在execution_attempts/，不再是本次代码交付的前提。

## 用户本地命令

```matlab
result = run_main;
```

可选预检为`run_smoke`。复核已有正式目录而不重跑：

```matlab
check = verify_main_results('C:/work/your_main_result_directory');
```

详细操作见START_HERE.md。数据完整性核对成功不预设Uniform/Loaded必须达标，也不因Fixed16性能失败判定数据无效。
