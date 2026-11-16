# v1.1 执行状态

**当前云端 v1.1 未在 MATLAB 执行，未完成 main。** 这不代表没有真实MATLAB数据：用户已上传本地历史smoke输出，保存在evidence/imported_smoke/。当前云端无可用MATLAB，不能调用Communications Toolbox或完成三策略正式统计。

## 最新实际启动尝试

北京时间2026年11月16日19:27，在项目目录实际调用了`matlab -batch`，执行用户指定的`CalibrationDirectory=evidence/imported_smoke`与`CalibrationMode='reuse'`命令。启动器返回127：`exec: matlab: not found`，错误发生在MATLAB启动前。

完整记录位于[execution_attempts/20261116_192724_486203_main_launch/](execution_attempts/20261116_192724_486203_main_launch/)。其中`launcher.log`保存命令、工作目录、校准位置和原错误；`attempt_status.json`列出0/9完成及九个剩余组。此目录是启动诊断，不是正式结果目录。

Uniform、Loaded、Fixed16均为0/3正式组；没有可继续跟踪的MATLAB进程，没有生成正式汇总、Fixed16实测BER、主实验图或新英文结果段。已检查环境配置和变量名称，未发现现有MathWorks执行绑定；未读取或导出凭据值。下一步必须为本任务接入可用的MATLAB与Communications Toolbox执行环境，许可状态需在该环境中验证。

## 已有真实结果：仅历史 smoke

配置及完成日志为smoke，每方案2000载荷DMT符号。旧CSV的seed=0与pooled是同一批数据，不重复累计：

| 策略 | B，bits/DMT symbol | R_payload，Mbit/s | 观察误码 / 测试比特 | 观察 BER |
| --- | ---: | ---: | ---: | ---: |
| Uniform | 48 | 42.6667 | 0 / 96000 | 0 observed |
| Loaded | 120 | 106.6667 | 10 / 240000 | 4.1667e-5 |
| Fixed16 | 定义为96 | 计数速率85.3333 | 尚未运行 | 尚无结果 |

Fixed16的B/速率是由策略定义推得的量，不是测量。历史Loaded为64-QAM k1:15、16-QAM k16:21、QPSK k22:24；k21约17.5554dB，在边界附近，120而非解析诊断118不代表错误。120/48比率2.5，不能据smoke宣称正式性能优势。

上传数据一致性复核见validation/uploaded_smoke_audit.md及.json：211项检查通过，包括14个原文件的字节哈希、配置/profile、统计层级及计数。这是读取已有真实MATLAB输出的Python检查，不执行MATLAB，不生成新正式BER。evidence/imported_smoke/import_manifest.csv记录原上传ID、字节数和SHA-256。

## 本次代码与证据范围

协议v1.1保留物理规格v1.0，增加Fixed16诊断、历史校准验证/复用、独立seed/pooled文件、design/nominal预测区分、代码SHA-256与冻结标识、显式白底论文图和main-only英文结果段。源码有限审计见docs/AUDIT_v1_1.md。

validation/保存实际静态/独立Python检查及命令。它们不等于新MATLAB链路自检通过，不验证当前QAM许可、运行时API、图导出或正式BER。没有为v1.1预制虚构CSV、MATLAB PASS日志、main图、执行时间或英文结果数字。

本次实际检查退出码均为0：21个MATLAB文件通过MISS_HIT静态检查，75项独立公式/源码诊断通过，211项上传历史smoke一致性检查通过。`validation/source_manifest_v1_1.csv`记录23个交付源码文件的实际SHA-256和字节数；这是文件检查，不是MATLAB运行记录。完整命令见`validation/commands_and_scope.md`。

停在的步骤：**完成代码与可执行说明，但缺少MATLAB，尚未运行v1.1基础自检、三策略smoke及main**。历史文件保持原字节；新三策略正式汇总仍待执行。

## 在有 MATLAB 的机器继续

1. 安装并许可MATLAB（目标R2026a）及Communications Toolbox，正常JVM模式启动。
2. 在项目目录运行 `run_dmt_experiment('smoke')`，默认验证并复用evidence/imported_smoke/的冻结校准，检查三策略程序和输出。
3. 执行 `run_dmt_experiment('main')`：先自检与冻结校准核对，再三策略各3个固定种子×100000符号；内部smoke计数独立。
4. 如需重算核对，执行 `run_dmt_experiment('main','CalibrationMode','recompute','CalibrationDirectory','C:/path/to/old_smoke')`；保持旧种子，保存值须在容差内一致，profile完全一致，不匹配停止诊断。
5. 用该次per_subcarrier_pooled.csv及summary.csv判断U/L证据和Fixed16状态；仅完整main后使用当次正式图、英文段落和图注，不复用历史smoke数字。

完整命令和模型边界见README.md。本状态说明保留以区分交付时云端未执行、历史本地smoke和后续真实main。
