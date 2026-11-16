# main 实际启动尝试：未启动 MATLAB

**未在 MATLAB 执行，正式 main 未完成。** 本目录是启动器诊断记录，不是实验结果目录。

实际工作目录：`/workspace/BitLoading/EESM5540_DMT_BitLoading`。校准目录：`/workspace/BitLoading/EESM5540_DMT_BitLoading/evidence/imported_smoke`，两份所需 MAT 文件均存在，参数、源码和旧 smoke 没有修改。

实际调用命令见 `launcher.log`。启动器返回 **127**：`matlab: not found`。错误发生在 MATLAB 进程创建之前，因此没有 MATLAB 自检、smoke 或任何正式载荷组运行。

- Uniform：0/3 正式组；种子11、22、33均待运行。
- Loaded：0/3 正式组；种子11、22、33均待运行。
- Fixed16：0/3 正式组；种子11、22、33均待运行。

没有生成新的正式汇总、逐子载波BER、Wilson区间、正式图或英文结果段。包内 `evidence/imported_smoke/` 仍仅是原先的2000符号预检，不能替代 main。Fixed16 尚无实测超标子载波结论。

当前没有 MATLAB 进程可继续等待；未重复启动另一份主实验。要继续，需要为本任务接入已安装 MATLAB 和 Communications Toolbox、具备有效授权的执行环境。许可可用性尚未通过 MATLAB 检查；不要在聊天中发送许可证或令牌。接入后应保持同一套参数、校准及随机流，运行固定九组并复核实际计数。
