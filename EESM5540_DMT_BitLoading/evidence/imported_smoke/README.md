# 保留的历史 smoke 证据

本目录保存用户上传的 14 个 MATLAB 原始输出文件，均按原始字节复制；SHA-256 与字节数记录于 `import_manifest.csv`。没有修改、删除、重命名原始结果内容。`README.md` 与 `import_manifest.csv` 是本次新增的归档说明。

**这些是 smoke，不是 v1.1 main。** MATLAB 快照中的 `cfg.runMode='smoke'`；每方案只有 2000 个载荷符号。Uniform 为 `0/96000` 观察误码，Loaded 为 `10/240000`。原 `per_subcarrier_results.csv` 的 seed=0 与 pooled 是相同一批计数，只能取一种统计层级，不得相加。

这里的原 `.fig/.pdf` 使用旧深色绘图样式；原英文段落也保留不动。它们都不能改标签后作为正式主实验结果。v1.1 的正式图和英文结果段仅在新的 main 真实完成后产生。

默认运行 v1.1 时，程序审查这些配置和初始化字段，复用其冻结 `H_hat/gamma_hat`，按同一规则重建并比对原 Uniform/Loaded profile，再追加 Fixed16。原 smoke 载荷计数不进入任何新运行的正式统计。

独立数据一致性审计见 `../../validation/uploaded_smoke_audit.md`。该审计是在云端读取用户提供文件，不能证明历史源码的密码学来源，也不是云端执行 MATLAB；原运行没有提供历史代码 SHA-256 清单。v1.1 新运行会记录新的源码清单与初始化标识。
