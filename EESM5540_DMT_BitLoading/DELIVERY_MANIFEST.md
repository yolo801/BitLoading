# 交付文件清单

项目位于 `/workspace/BitLoading/EESM5540_DMT_BitLoading/`。所有新增工作均在该独立项目目录中；未修改既有其他项目、原报告或 abstract。

| 文件 | 用途 |
| --- | --- |
| `README.md` | 参数、模型、依赖、Windows/批处理命令、统计解释及输出定义 |
| `EXECUTION_STATUS.md` | 未在 MATLAB 执行的限制与已完成检查 |
| `report_notes_zh.md` | 未执行状态下的方法、局限及三个答辩问题 |
| `run_dmt_experiment.m` | smoke/main 入口、分阶段执行、独立结果目录和日志 |
| `private/dmt_default_config.m` | 冻结规格 v1.0 |
| `private/dmt_random_frame.m` | 逐子载波 Gray QAM 与 Hermitian 映射 |
| `private/dmt_transceive.m` | IFFT/CP、串行 FIR 状态、实噪声及接收 FFT |
| `private/dmt_demod_errors.m` | 按实际 QAM 阶数逐位解调及计数 |
| `private/dmt_calibrate.m` | 独立 A/B 的 LS 信道估计与残差 SNR |
| `private/dmt_load_profiles.m` | Uniform/Loaded 选阶及不可行诊断 |
| `private/dmt_qam_ber.m` | 近邻 QAM BER 近似，Base MATLAB erfc |
| `private/dmt_seed_mapping.m` | 数据/噪声独立随机流映射与种子冲突检查 |
| `private/dmt_simulate.m` | 固定长度、串行分块载荷测试与累积能量 |
| `private/dmt_self_checks.m` | 无噪声链路、FFT/CP/FIR/能量/噪声自检 |
| `private/dmt_post_checks.m` | 计数、冻结条件、选阶及能量核对 |
| `private/dmt_record_check.m` | 带数值与容差的验证日志 |
| `private/dmt_wilson.m` | 逐点 95% Wilson 区间 |
| `private/dmt_write_outputs.m` | 实际运行后的 CSV、中文观察与英文结果段 |
| `private/dmt_plot_results.m` | 实际运行后的三联图与 PNG/PDF/FIG 导出 |
| `tools/verify_implementation.py` | 独立 Python 数学/源码诊断，不测实验 BER |
| `validation/python_diagnostics.txt` | 75 项独立诊断的数值、容差与状态 |
| `validation/matlab_static_lint.txt` | 16 个 MATLAB 文件的静态检查输出 |
| `validation/commands_and_scope.md` | 实际检查命令与范围 |
| `.gitignore` | 不把生成结果与 MATLAB 自动保存文件加入版本管理 |

**尚未生成实验结果。** 配置 MAT、初始化 MAT、随机种子 CSV、逐子载波 CSV、汇总 CSV、运行日志、验证日志、三联图及数据驱动说明将在真实 MATLAB 执行后保存于 `results/<timestamp>_<mode>_<unique>/`；其具体名称见 README。没有预制虚构结果。未来 `main` 的 `preflight_smoke/` 只保存预检结果，不混入正式统计。
