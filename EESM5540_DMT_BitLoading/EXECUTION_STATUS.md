# v1.2 实际状态：尚未执行MATLAB

## 实际启动结果

本次实际调用`matlab -batch`运行`run_v1_2(referenceDir)`，启动器返回127：`exec: matlab: not found`。当前聊天没有暴露可调用的MATLAB MCP工具，错误发生在MATLAB进程启动之前。

精确命令、用户参考路径、时间与原始错误保存在：

`execution_attempts/v1_2_20261117_154357_255883_launch/launcher.log`

机器可读记录：同目录`attempt_status.json`。这只是启动诊断，不是实验结果目录。没有MATLAB进程需要继续等待，没有重复启动90组。

## 已完成与剩余

| 内容 | 实际完成 | 剩余或原因 |
| --- | ---: | --- |
| reference 0 正式数据核对 | 未执行 | Windows本机目录当前不可访问 |
| Figure 2 同源重绘 | 0张 | 未读取参考计数、未调用MATLAB绘图 |
| 新独立校准 | 0/10轮 | MATLAB未启动 |
| 新正式载荷 | 0/90组 | 10轮×3策略×3种子全部待运行 |
| 新逐轮统计/合规轮数/英文正式结果段 | 未生成 | 不用提示词数值、smoke或独立Python诊断冒充结果 |

用户提供的参考目录是：

```text
C:\Users\Lenovo\Documents\MATLAB\BitLoading-07082cb7bdb034357bc80da358a5f3ec5d411c48\EESM5540_DMT_BitLoading\results\20261116_194846_246_main_tp96b36639_d14e_4dbc_8956_3651acfb6fa8
```

目前只记录了路径，未声称验证该目录及提示词中的参考数值。旧imported_smoke保持原字节，不能替代reference 0。

## 已完成的独立工作

- 实现任务A、十轮/90组入口、精确新种子映射、校准冻结、完整检查点和恢复校验、逐轮统计及只读完成核对。
- 文献映射与访问记录已保存；8次DOI/原文/元数据访问均在代理隧道阶段被403阻断，0篇PDF取得或阅读，指定原文段落尚未独立核实。
- 静态检查、独立算术/公式诊断及旧smoke一致性核对的实际命令和当前计数见`validation/commands_and_scope.md`。这些都不是MATLAB实验通过记录。

## 继续执行的前提

需要让当前会话能调用已连接Windows机器的MATLAB MCP，并访问上述reference 0，或在可访问该目录的授权MATLAB+Communications Toolbox环境运行`run_v1_2(referenceDir)`。本次代码不更改物理参数、固定种子或选阶规则来换取通过。

完整入口、恢复命令、预期输出及统计边界见`V1_2_README.md`。旧v1.1代码和历史记录保留，前一次交付状态归档于`docs/HISTORICAL_EXECUTION_STATUS_before_v1_2.md`。
