# v1.3实际命令与证据范围

**未在MATLAB执行：独立preflight 0/36，正式校准0/40，正式载荷0/360，剩余360组。**

## 实际启动

从项目目录尝试调用`matlab -batch`，实际MATLAB语句为：

```matlab
run_dmt_v13('all','ReferenceDirectory','C:\Users\Lenovo\Documents\MATLAB\BitLoading-07082cb7bdb034357bc80da358a5f3ec5d411c48\EESM5540_DMT_BitLoading\results\20261116_194846_246_main_tp96b36639_d14e_4dbc_8956_3651acfb6fa8');
```

启动器在创建MATLAB进程前退出127，原始错误：

```text
bash: line 1: exec: matlab: not found
```

当前工具发现没有MATLAB/MathWorks MCP匹配。完整shell命令、北京时间2026年11月17日17:41的启动时间、路径及输出保留于`execution_attempts/v1_3_20261117_174133_665607_launch/launcher.log`和`attempt_status.json`。这是启动诊断，不是MATLAB结果。没有运行中的MATLAB任务，也没有启动重复任务。

Windows reference0当前不能由云文件系统读取，未核实其文件、哈希或提示词中的参考数值。旧smoke不能替代reference0或v1.3实测数据。没有在results/创建新的实验CSV、图或MATLAB PASS记录。

## 实际完成的代码与独立检查

以下命令分别捕获并核对退出码，均为0：

```sh
PYTHONPATH=/tmp/eesm5540_lint python3 -m miss_hit.mh_lint --input-encoding utf-8 --brief --single .
python3 tools/verify_implementation.py
python3 tools/audit_uploaded_smoke.py
python3 tools/verify_v12_contracts.py
python3 tools/verify_v13_contracts.py
git diff --check
```

- MISS_HIT 0.9.44：62个MATLAB文件语法/静态检查通过，见`matlab_static_lint.txt`。不验证MATLAB运行时、Java接口或工具箱调用。
- 75项原公式/源码约定诊断通过，见`python_diagnostics.txt`。不是新DMT载荷或BER结果。
- 211项旧上传smoke一致性检查通过，见`uploaded_smoke_audit.md/.json`。只读取既有真实文件，不替代未提供的正式reference0。
- 43项v1.2独立协议算术检查通过，见`v12_contract_checks.json`。
- 63项v1.3独立数学/协议检查通过，见`v13_contract_checks.json`。包含固定1120正式/112预检种子、跨版本编号重合边界、IM/DD采样点与稳态DC公式、rho4旁路尺度关系、PAPR和严格区间状态。任意确定性/随机数值向量与合成区间反例不是MATLAB实验数据。

`v1_3_code_check_status.json`记录上述五个检查退出码、未执行标志和实际文件数。当前`source_manifest_v1_3.csv`包含66个代码文件（62.m、4.py）的真实字节数与SHA-256。v1.1/v1.2清单保持历史意义，不将其标为当前版本。

历史14个上传文件按字节保留，`.gitattributes`阻止Git换行转换；本次不更改其校准、smoke、原报告或摘要。旧检查命令范围保留于`docs/HISTORICAL_commands_and_scope_v1_2.md`。

## 文献访问

13次DOI、MDPI/Optica及Crossref HTTPS请求全部在代理CONNECT阶段返回403，未取得PDF、摘要或元数据。真实URL、时间与原错误见`docs/literature_access_v1_3.json`；映射见`docs/literature_mapping_v1_3.md`。提示词给定文献位置尚未独立核实，不声称阅读原文或复现实验性能。

## 剩余实际工作

需要可调用MATLAB+Communications Toolbox并能读取reference0的环境，运行v1.3实现回归、独立preflight36组、40轮真实A/B/C和360组正式载荷。真实选阶、合规状态、功率/削波/PAPR统计和图文结论均待实际测量。

源码/静态检查不能替代MATLAB运行验收。入口、恢复、输出路径和统计边界见`V1_3_README.md`。
