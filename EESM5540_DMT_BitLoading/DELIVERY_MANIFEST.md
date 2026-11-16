# v1.1 交付与结果路径

项目 `/workspace/BitLoading/EESM5540_DMT_BitLoading/`，入口run_dmt_experiment.m。协议1.1、冻结物理规格1.0，不改原报告、abstract、ISAC和历史结果。

**本次云端 v1.1 未在 MATLAB 执行，未完成 main。** 区分源码、历史实测和未来正式输出：

| 路径 | 用途及状态 |
| --- | --- |
| README.md | 参数、三策略、校准复用、Windows/批处理命令、统计及结果口径 |
| EXECUTION_STATUS.md | 云端未执行、历史本地smoke与未来main的边界 |
| execution_attempts/20261116_192724_486203_main_launch/ | 本次真实batch启动记录：退出127、MATLAB未启动、正式0/9组，不是实验结果 |
| report_notes_zh.md | 方法、历史观察、Fixed16意义及答辩问题，不是正式结果段 |
| docs/AUDIT_v1_1.md | 有限源码审计，不替代MATLAB运行检查 |
| run_dmt_experiment.m | 分阶段入口、一次冻结校准、三策略九次正式测试、独立目录和异常留痕 |
| private/dmt_default_config.m | 物理规格及协议配置 |
| private/dmt_random_frame.m、dmt_transceive.m、dmt_demod_errors.m | QAM/Hermitian、CP/FIR/噪声/FFT与逐位计数 |
| private/dmt_calibrate.m、dmt_load_profiles.m、dmt_qam_ber.m | 独立校准、Uniform/Loaded规则、Fixed16诊断profile与BER近似 |
| private/dmt_seed_mapping.m、dmt_simulate.m | 旧U/L流映射不变、追加Fixed16、串行分块累积 |
| private/dmt_self_checks.m、dmt_post_checks.m、dmt_record_check.m、dmt_wilson.m | 数值检查、计数/公平条件、日志与逐点Wilson；Fixed16性能失败不作为实现失败 |
| private/dmt_write_outputs.m、dmt_plot_results.m | 分离统计表、预测诊断、main-only英文段落及白底三策略图 |
| private/dmt_prepare_calibration.m | 参考配置和字段检查、旧U/L profile匹配、复用或相同种子重算比较 |
| private/dmt_sha256.m、dmt_source_manifest.m、dmt_initialization_id.m | 字节SHA-256、入口/private.m/tools.py清单及冻结校准/profile标识 |
| private/dmt_log_info.m | 非验收性质的校准及诊断信息，不伪装为PASS |
| evidence/imported_smoke/ | 用户真实本地旧smoke原文件和导入追踪，包括MAT、CSV、FIG、PDF、日志/说明；不是main |
| evidence/imported_smoke/import_manifest.csv | 14个上传原文件的ID、字节数及SHA-256 |
| tools/audit_uploaded_smoke.py | 可选Python+NumPy+SciPy读取旧输出一致性，未执行MATLAB |
| validation/uploaded_smoke_audit.md、.json | 上传字节哈希、MAT/CSV/profile、计数层级等复核 |
| tools/verify_implementation.py、validation/ | 静态与独立公式检查、实际命令及输出，不产生MATLAB BER |
| validation/source_manifest_v1_1.csv | 当前23个交付源码文件的真实SHA-256与字节数 |
| validation/commands_and_scope.md | 实际工具探测、21文件静态检查、75项独立诊断与211项历史结果核对的命令及范围 |
| .gitignore | 生成结果和MATLAB自动保存文件的版本管理规则 |
| .gitattributes | 原始历史证据保持字节、禁用换行转换；归档元数据仍按文本展示 |

每次新结果 `results/<timestamp>_<mode>_<unique>/`，main预检位于preflight_smoke/。源代码SHA-256写入source_manifest.csv，配置与初始化保存冻结标识、来源和一致性记录。历史文件原字节保留，不将其smoke计数用于新main。

## 实际运行后才产生的新输出

| 文件 | 完整 main 的结构 |
| --- | --- |
| source_manifest.csv、config_snapshot.mat、initialization.mat、seed_mapping.csv | 源码、运行配置、一次冻结估计/profile、随机流及完整性追踪 |
| integrity.json | source_manifest_sha256、initialization_profile_sha256及calibration_provenance |
| reference_config_snapshot.mat、reference_initialization.mat | 使用历史参考时复制的两份原MAT文件 |
| environment.txt、run.log、verification_checks.txt | 实际MATLAB版本、命令、时间、进度、数值与容差 |
| per_subcarrier_seed.csv | 216行，三策略×三seed×24载波 |
| per_subcarrier_pooled.csv | 72行，三策略×24载波，正式验收入口 |
| nominal_vs_measured.csv | 72行design/nominal预测、真实计数/BER/CI |
| summary.csv | 3行，均由pooled求得；状态、超标载波、能量和时长 |
| per_subcarrier_results.csv | 如保留兼容混合CSV，含record_type，不能重复相加seed与pooled |
| runs_partial.mat、final_results.mat | 计数、配置、冻结估计/profile和统计，main/smoke分开，无长期波形 |
| dmt_comparison.png/.pdf/.fig | 真实main白底论文图，PNG≥300dpi、PDF矢量、FIG可编辑 |
| report_notes_zh.md、results_paragraph_en.txt、figure_caption_en.txt | 当次真实main观察和独立图注，英文正式段落仅完整main后生成 |
| smoke_notes_en.txt | smoke-only说明，不是正式结果段 |
| failure_status.txt | 错误及堆栈，保留失败但不标为main完成 |

当前没有新三策略main表、Fixed16实测BER或正式白底图。历史smoke真实数值在README中单独列出，不能改标题充当尚未完成的正式结果。
