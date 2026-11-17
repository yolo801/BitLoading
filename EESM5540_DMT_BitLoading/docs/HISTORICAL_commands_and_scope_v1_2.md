# v1.2 实际命令与证据范围

**未在MATLAB执行：Task A未开始，新独立校准0/10，正式载荷0/90，剩余90组。**

## 实际启动

在项目目录实际调用`matlab -batch`，MATLAB语句为：

```matlab
referenceDir = 'C:\Users\Lenovo\Documents\MATLAB\BitLoading-07082cb7bdb034357bc80da358a5f3ec5d411c48\EESM5540_DMT_BitLoading\results\20261116_194846_246_main_tp96b36639_d14e_4dbc_8956_3651acfb6fa8';
run_v1_2(referenceDir);
```

启动器退出127，原始错误`bash: line 1: exec: matlab: not found`。当前工具发现也没有MATLAB/MathWorks MCP匹配；没有MATLAB服务端返回，因为没有可调用工具。Windows参考目录当前不能由云文件系统读取，不能核实提示词给出的参考数值。

完整shell命令、实际时间和状态见`execution_attempts/v1_2_20261117_154357_255883_launch/launcher.log`及`attempt_status.json`。此目录不是正式结果目录；没有在results/创建伪造的实验表、图或MATLAB PASS记录。

## 实际完成的代码与独立检查

下列命令分别捕获并核对退出码，均为0：

```sh
PYTHONPATH=/tmp/eesm5540_lint python3 -m miss_hit.mh_lint --input-encoding utf-8 --brief --single .
python3 tools/verify_implementation.py
python3 tools/audit_uploaded_smoke.py
python3 tools/verify_v12_contracts.py
git diff --check
```

- MISS_HIT 0.9.44：40个MATLAB文件语法/静态检查通过，见`matlab_static_lint.txt`。不验证MATLAB运行时或工具箱调用。
- 75项独立公式/原源码约定诊断通过，见`python_diagnostics.txt`。任意复输入FFT/CP/FIR及解析量不是MATLAB实验结果。
- 211项旧上传smoke一致性检查通过，见`uploaded_smoke_audit.md/.json`。只读取既有真实smoke文件，不能替代未提供的正式reference 0。
- 43项v1.2独立协议算术检查通过，见`v12_contract_checks.json`：220流不冲突、标签到槽位映射、严格区间边界、禁止混合profile的统计反例。合成计数只用于数学反例，不是DMT测试数据。

`v1_2_code_check_status.json`记录上述各命令退出码及未执行标志。`source_manifest_v1_2.csv`为当前43个代码文件（40.m、3.py）的实际SHA-256及字节数。`source_manifest_v1_1.csv`保留原v1.1交付清单，不将其标为当前版本。

新增文本换行/尾随空格检查通过；历史14个原文件按字节保留，.gitattributes阻止Git换行转换。没有更改既有校准、smoke、原报告或摘要。

## 文献访问

8次DOI、Optica原文候选及Crossref元数据请求在代理CONNECT阶段返回403；没有取得或阅读三篇原文。真实URL、时间与原错误见`docs/literature_access.json`，映射见`docs/literature_mapping.md`。不将用户给出的页码/段落位置声称为独立核实。

## 未完成的实际工作

reference 0核对与Figure 2重绘；十轮新A/B训练/探测、90组载荷、逐轮统计/真实合规轮数、正式图和英文结果段均未执行或生成。Java文件锁、原子MAT恢复、MATLAB新绘图API和工具箱代码只有源码/静态核对，仍需实际MATLAB运行验证。

要继续真实执行，需将可访问用户Windows参考目录的MATLAB MCP暴露到当前会话，或在可访问该目录的授权MATLAB+Communications Toolbox环境调用`run_v1_2(referenceDir)`。精确命令、恢复规则及统计边界见`V1_2_README.md`。
