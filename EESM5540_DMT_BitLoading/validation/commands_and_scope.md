# v1.1 实际命令、结果与范围

**当前云端未在 MATLAB 执行，未完成 main。** 用户上传的本地历史 smoke 是已有运行证据，不是本次新运行。

## 工具探测

`command -v matlab` 与 `command -v octave` 均未找到可执行文件；常见 /usr/local/MATLAB*、/opt/MATLAB*、/opt/matlab* 也未发现安装。未调用 MATLAB 执行入口；没有生成新的 MATLAB 运行时间、PASS 日志、正式 CSV 或图。

## 实际完成的检查

在项目目录执行：

```sh
PYTHONPATH=/tmp/eesm5540_lint python3 -m miss_hit.mh_lint --input-encoding utf-8 --brief --single .
python3 tools/verify_implementation.py
python3 tools/audit_uploaded_smoke.py
git diff --check
```

以上各命令单独捕获退出码，全部为 0。MISS_HIT 0.9.44 分析 21 个 MATLAB 文件；75 项独立数学/源码约定诊断通过；211 项上传历史 smoke 数据一致性检查通过。前两种检查不执行 MATLAB；第三种只读取用户上传的 MATLAB 数值结构和 CSV，不生成实验 BER。

- `matlab_static_lint.txt`：语法/静态检查。
- `python_diagnostics.txt`：独立 Python 恒等式、噪声 FFT 方差和解析诊断值，不是 MATLAB 结果。
- `uploaded_smoke_audit.md/.json`：14 个原始文件的哈希、配置、profile、计数、区间、能量与随机流复核，不将 seed 与 pooled 重复计数。
- `source_manifest_v1_1.csv`：本次交付源码的 SHA-256/字节数（用 Python 读取实际源码字节，非 MATLAB 执行）。真正运行时 MATLAB 还会生成当次的 source_manifest.csv 与 integrity.json。

另外检查了新增文本换行和尾随空格；历史上传文件不参与文字格式修正，保持原字节。核心收发/校准/自检等未修改函数与原提交 ca26355 相同；本次变更范围见 docs/AUDIT_v1_1.md。

提交前完整检查发现历史CSV的Windows CRLF和日志尾随空格会触发通用空白检查。未修改历史内容；`.gitattributes`将原始证据按字节保存并按二进制差异展示，避免Git换行转换。新建的两个清单CSV使用LF；最终暂存检查通过。历史14文件的SHA-256再次核对，不受展示属性影响。

## 尚未完成

v1.1 的 MATLAB 基础自检、三策略 smoke、9 次 main、Java SHA-256 MATLAB 调用、实际图导出和新结果段都未执行。当前检查不能证明这些运行时操作已成功。

有 MATLAB + Communications Toolbox 的机器上，从项目目录运行：

```matlab
run_dmt_experiment('smoke')
run_dmt_experiment('main')
```

默认核对并复用包内 historical smoke 的一次冻结校准。main 成功后才使用该次结果目录根部正式图及英文结果段；preflight_smoke/ 始终不参与正式计数。
