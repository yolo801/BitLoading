# VCSEL–MMF 2025 正式批次后处理修复

用于正式批次 `dmt_vcsel_mmf_2025_formal_tpd8044631_6100_4e65_ae1e_c0877c79f2a1`。采集基线是 `104f12e9cd78f85ffa5f6a3cab5f9b4b7d80b498`。新后处理的源码和产物使用独立指纹。原正式代码的清单不包含本子目录。

批次完成传输后在原说明的 `writeSelectivity` 步骤遇到 `MATLAB:printf:invalidInputType`。原流程以字符格式调用 `compose`，将所得的字符元胞数组送入 `join` 后仍可能得到元胞。新的说明逐项提取并校验表格值，并通过 `sprintf` 和 `strjoin` 生成单行字符。导出验证要求 UTF-8 报告具有完整的结尾标记，并含该批次的两个工作点与样本统计。

修复图 A 同时显示承载比特、名义载荷速率、达标周期速率、实际前向配置时间与候选验证次数。图 B 固定原代表轮次，保留整个活跃频带。正式设计拒绝只在状态及实际配置开销中出现。

## MATLAB 只读后处理

从 GitHub 下载完整源码 ZIP 并解压，进入本目录。使用能通过原版源码哈希检查的 MATLAB 环境。下面的目标目录应当是独立且尚不存在的目录。

```matlab
formal = '含原始 Protocol.mat 的正式目录完整路径';
out = '新后处理目录完整路径';
r = postprocess_dmt_vcsel_mmf_2025(formal,'OutputDirectory',out);
disp(r)
```

入口先调用原版 `verify_dmt_vcsel_mmf_2025(formal,false)` 重建原始批次的计数和 CSV，只跳过原图件验证。这段只读验证仍使用原版源码和所有原来的指纹约束。可用 `OriginalProject` 指向另一个已解压的原版源码根目录。完整结果输出后，使用下列命令再核对文件。

```matlab
r = postprocess_dmt_vcsel_mmf_2025(formal,'Mode','verify','OutputDirectory',out);
disp(r.valid)
```

`original_data_audit_receipt.mat` 保存原始采集的校验结果，`postprocess_verification_receipt.mat` 和对应 JSON 保存新版导出校验的结果。整个流程只读原正式批次。

## Python 复核和实际重绘

使用 Python 3.11 或更新版本及 NumPy、SciPy、Matplotlib、Pillow、PyMuPDF。在本目录执行以下命令。若保留原始正式 ZIP，可加 `--archive` 逐文件核对解包文件与归档。直接传入的需是含 `Protocol.mat` 的正式目录。

```bash
python tools/audit_vcsel_run.py "FORMAL_FOLDER" ".." "OUTPUT_FOLDER" --archive "ORIGINAL_FORMAL_ZIP"
python tools/render_vcsel_fig_a.py "FORMAL_FOLDER" "OUTPUT_FOLDER"
python tools/render_vcsel_fig_b.py "FORMAL_FOLDER" --output-dir "OUTPUT_FOLDER"
python tools/render_vcsel_notes.py "FORMAL_FOLDER" "OUTPUT_FOLDER"
python tools/verify_vcsel_exports.py "FORMAL_FOLDER" "OUTPUT_FOLDER"
python tools/verify_vcsel_exports.py "FORMAL_FOLDER" "OUTPUT_FOLDER" --verify
```

Python 的 `raw_checkpoint_audit.json` 与 `postprocess_verification.json` 分别保存原始证据及新版 Python 导出核验。Python 复核与 MATLAB 原生回执分开记录。云端启动 MATLAB 的实际结果见 [matlab_native_attempt.log](validation/matlab_native_attempt.log)。
