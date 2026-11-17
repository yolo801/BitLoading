# v1.3实际执行状态

**本次未在MATLAB执行。正式载荷0/360组，独立preflight0/36组，正式校准0/40。**

实际batch调用了`run_dmt_v13('all','ReferenceDirectory',...)`，启动器在MATLAB进程创建前返回127：

```text
bash: line 1: exec: matlab: not found
```

当前会话没有暴露可调用MATLAB MCP工具。没有运行中的MATLAB实验需要继续等待，没有重复启动另一份360组任务。

原始命令、北京时间2026年11月17日17:41的启动时间、路径、输出和退出码见：

`execution_attempts/v1_3_20261117_174133_665607_launch/launcher.log`

机器可读实际状态为同目录`attempt_status.json`。这是启动诊断，不是MATLAB实验结果。

| 场景 | 正式计划 | 实际完成 | 仍待执行 |
| --- | ---: | ---: | ---: |
| linear | 90 | 0 | 90 |
| imdd_rho4 | 90 | 0 | 90 |
| imdd_rho2p5 | 90 | 0 | 90 |
| imdd_rho1p5 | 90 | 0 | 90 |

旧reference0位于用户Windows目录，当前云文件系统无法读取；本次没有核实其主实验文件、哈希或提示词给出的核对数值。只发现原imported_smoke，保持原字节，未用它替代正式reference0。

## 已完成的独立工作

- 已实现显式Rx估计、理想SNR反馈、Tx选阶、配置交换／ACK、独立C和按本端配置处理载荷。
- 已实现固定四场景、归一化采样点IM/DD前端、功率／削波／PAPR计数、完整检查点及恢复、分层统计与真实数据导出／独立验收代码。
- 实际代码检查计数、退出码及源码SHA-256见`validation/commands_and_scope.md`与`validation/v1_3_code_check_status.json`；这些不等于MATLAB运行验收。
- 13次文献HTTPS访问全部在代理CONNECT阶段被403阻断，未取得PDF、摘要或元数据。边界见`docs/literature_mapping_v1_3.md`及实际请求JSON，没有声称阅读原文。

## 尚未得到的实验材料

新的实现回归、A/B/C真实测量、360组正式BER、逐场景合规轮数、加载表变化、光功率／削波／PAPR统计、正式图和结果段均尚未运行或生成。不能用代码、提示词数值、独立Python算术或旧smoke替代这些结果。

继续需要可调用MATLAB+Communications Toolbox（或将Windows MATLAB MCP暴露到当前聊天），并能访问真实reference0目录。参数、预算、种子和选阶规则不为通过而调整。实际入口、恢复及输出结构见`V1_3_README.md`。
