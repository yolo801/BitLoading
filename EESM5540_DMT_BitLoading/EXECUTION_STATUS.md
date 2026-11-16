# 执行状态

**未在 MATLAB 执行。**

当前云环境的可执行文件检查未找到 `matlab` 或 `octave`。因此，本次不能调用 Communications Toolbox 的 `qammod/qamdemod`，不能验证 MATLAB 运行兼容性，也不能完成真实 smoke 或 3 × 100000 符号/方案的正式 Monte Carlo 统计。

仓库提供实现与运行说明。基础链路测试、正式 BER、Wilson 区间、实际 profile、实际能量、载荷速率、PNG/PDF/FIG 结果图和数据驱动英文结果段，必须由真实 MATLAB 运行产生。任何静态检查或独立公式核对只证明其各自检查的内容，不是 MATLAB 实验已执行的证据。

## 已完成的非 MATLAB 检查

- MISS_HIT 0.9.44 对全部 16 个 `.m` 文件的语法/静态检查通过，退出码 0。
- `python3 tools/verify_implementation.py` 的 75 项独立公式及源码约定诊断通过，退出码 0。
- 独立 Python 诊断中的线性 FIR/CP/FFT 恒等式最大残差约 `7.02e-16`，单位酉 Parseval 残差约 `5.68e-14`；这些不是 MATLAB 收发机的实测误差。
- 项目新增文本的尾随空格、结尾换行及 `git diff --check` 检查通过。

实际命令与范围见 [validation/commands_and_scope.md](validation/commands_and_scope.md)，完整诊断值与容差见 [validation/python_diagnostics.txt](validation/python_diagnostics.txt)。没有用这些检查替代 MATLAB smoke 或正式 Monte Carlo。

当前没有可以据此声称“Loaded 在目标 BER 内优于 Uniform”的测量结论。README 中的 118/48 bits、理论速率、SNR 与能量参考均为明确标记的解析诊断，不是实验数据；实际加载规则可能在靠近边界的子载波上给出不同结果。

## 在有 MATLAB 的机器继续

1. 确认安装 MATLAB（目标 R2026a）与 Communications Toolbox，并有可用许可。
2. 在项目目录运行 `run_dmt_experiment('smoke')`，检查新结果目录中的逐项自检、计数、表格和图；失败时保留原目录并诊断。
3. 运行 `run_dmt_experiment('main')`。入口再次进行校准、自检和 smoke，冻结 profile 后执行两方案各 3 个固定 seed 的正式测试。不要根据初步 BER 更换种子、参数或样本数。
4. 依据该次目录的 `summary.csv` 与 pooled 子载波 Wilson 区间给出结论，并使用该次自动生成的图和说明；将这份状态说明与实际运行目录的日志一并保留，以免混淆本次云端未执行和后续本地执行。

完整命令、模型边界、随机流映射及输出说明见 [README.md](README.md)。未执行前，不创建含虚构数字的结果表、图或论文结果段。
