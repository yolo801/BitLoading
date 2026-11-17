# v1.3启动记录：未执行MATLAB

本目录是实际batch启动诊断，不是实验结果目录。命令调用run_dmt_v13('all')，本应完成独立preflight后继续完整固定预算；启动器在MATLAB启动前返回127：matlab: not found。

当前会话也没有可调用的MATLAB MCP。没有MATLAB进程继续运行或等待，没有重复启动第二份实验。

实际完成：reference0未核实，preflight0/36，正式校准0/40，正式载荷0/360（linear0/90，三个IM/DD共0/270）。全部正式组仍待运行。

没有生成新BER、SNDR、B/C差异、功率／削波／PAPR实测统计、正式图或带虚构数字的结果段。旧smoke及提示词核对值不能代替这些数据。

原始命令、时间、路径与错误见launcher.log及attempt_status.json。继续真实运行需要可用MATLAB与Communications Toolbox（或向本会话暴露可调用的Windows MATLAB MCP），以及可访问的真实reference0文件。不得在聊天中发送许可证或令牌。
