# 实际执行命令与检查范围

**未在 MATLAB 执行。** 以下是静态/独立公式检查，不是正式实验结果。

## 工具探测

- `command -v matlab`：退出码 1，未找到可执行文件。
- `command -v octave`：退出码 1，未找到可执行文件。
- `command -v python3`：退出码 0，/opt/codex/runtimes/codex-primary-runtime/dependencies/python/bin/python3。

## MATLAB 静态检查

`python3 -m pip install --target /tmp/eesm5540_lint miss_hit` 安装了 MISS_HIT 0.9.44（仅当前检查工具，不是项目依赖）。

在项目目录执行：

```sh
PYTHONPATH=/tmp/eesm5540_lint python3 -m miss_hit.mh_lint --input-encoding utf-8 --brief --single .
```

退出码 0；MISS_HIT Lint Summary: 16 file(s) analysed, everything seems fine。完整输出见 `matlab_static_lint.txt`。

## 独立公式和源码诊断

```sh
python3 tools/verify_implementation.py
```

退出码 0；75 项检查通过。全部数值和容差见 `python_diagnostics.txt`。

Python 检查使用独立的 NumPy 随机流和任意复数输入，核对 FFT/CP/FIR、噪声方差、解析选阶与 Wilson 公式；不执行 MATLAB 代码、不测试 qammod/qamdemod、不估计实验 profile，也不产生 BER。

## 文件检查与未运行项

`git diff --check` 退出码为 0；另对本次新增文本检查尾随空格和文件结尾换行。

MATLAB smoke、MATLAB main、Communications Toolbox 许可/QAM 调用、结果 CSV/MAT/PNG/PDF/FIG 和论文结果段均未运行/未生成。

当前可引用的是仿真方法与明确标记的解析诊断；不能引用任何实测优势结论。
