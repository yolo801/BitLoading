# 上传的历史 smoke 结果一致性审计

**当前云端未在 MATLAB 执行，main 未完成。** 本文仅复核用户上传的真实 MATLAB smoke 文件，不生成新的实验数据。

命令：`python3 tools/audit_uploaded_smoke.py`。211 项一致性检查通过；14 个原始文件逐一匹配导入 SHA-256 与字节数。

| 上传的历史方案 | DMT 符号 | B | 观察误码 / 测试比特 | 观察总 BER |
| --- | ---: | ---: | ---: | ---: |
| Uniform | 2000 | 48 | 0 / 96000 | 0 |
| Loaded | 2000 | 120 | 10 / 240000 | 4.16666667e-05 |

旧 CSV 的 `seed=0` 与 `pooled` 是同一批计数，审计逐项核对一致，未将两层重复相加。旧 MAT 的 `runs` 与 `smokeRuns` 也记录同一批 smoke；main 种子映射只是一份计划表，不表示已执行。

`config_snapshot.mat` 与 `final_results.mat` 的 cfg 完全匹配且 runMode 都是 smoke；初始化与最终 MAT 的全部保存校准/profile 一致。由保存探测残差重算 gamma_hat、由估计 SNR 和 1 dB 裕量重算 profile、CSV 的比特/误码/加权 BER/Wilson 区间及能量/时长口径均通过一致性检查。

Loaded 的实际冻结分配为 k1:15 的 64-QAM、k16:21 的 16-QAM 和 k22:24 的 QPSK，共 120 bits。k21 的估计 SNR 为 17.5553733 dB，其 16-QAM 保守近邻 BER 预测约 0.00098601825；无需手调成解析示例的 118 bits。

Fixed16 尚无实测数据。仅将上传 gamma_hat 代入近邻公式时，名义及保守预测中 k22:24 超过目标；这是解释用预测，不能当作正式 BER 或统计不合规证据。其 96 bits/符号与 85.3333 Mbit/s 只是 profile 的计数速率，不是经验证的可靠吞吐量。

使用 SciPy 时只读取明确列出的数值结构；未解码 MATLAB table 对象。完整检查名、数值与容差见 `uploaded_smoke_audit.json`。此次文件一致性审计不能证明 v1.1 新代码已在 MATLAB 运行，不能替代三策略的固定 main。
