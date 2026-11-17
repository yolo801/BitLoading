# v1.2真实启动诊断：任务尚未执行

本目录仅记录batch启动尝试，不是MATLAB实验结果目录。

实际调用run_v1_2(referenceDir)前，启动器返回127：matlab: not found。当前会话也没有暴露MATLAB MCP工具，因此没有MATLAB进程需要继续等待，没有重复启动90组任务。

- Task A：未读取或验证Windows本机reference 0，未生成新Figure 2。
- Task B：新校准0/10，正式载荷0/90，剩余90组全部待运行。
- 没有生成新的逐轮实验CSV、合规结论、正式结果段或MATLAB PASS记录。

Windows参考路径、精确命令、原始错误见launcher.log及attempt_status.json。提示词给出的参考数值未当成实测数据。原smoke保留，但不能替代reference 0或本次90组。

继续执行需要将Windows MATLAB MCP工具连接到当前会话，或让本任务能访问已授权的MATLAB+Communications Toolbox环境和reference 0目录。代码与实际检查范围见V1_2_README.md及validation/。
