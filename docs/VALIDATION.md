# 0.3.0 验证与源码计数

## 统计口径

运行 `python tools/source-lines.py`。只计算项目自身非测试 `.mbt` 文件中的代码行，排除空行、纯注释行和 `#|` JavaScript FFI 内容；不计 `.mbti`、配置、Python、Verilog、VCD、文档、依赖或构建产物。此结果是可复核的项目统计，不代表赛事方的内部统计口径。

| 文件 | MoonBit 代码行 |
|---|---:|
| vcd-regression.mbt | 310 |
| report.mbt | 256 |
| cmd/main/main.mbt | 211 |
| 合计 | 777 |

核心库合计 566 行。新增 report.mbt 实现周期区间、有上限的差异收集、全区间统计、逐信号摘要及可移植 JSON/文本序列化。CLI 只保留文件读取和退出状态的 JavaScript 外部接口。

## 验证范围

- JS、WasmGC、Native 各 9 组库测试，覆盖采样、位宽变化、重复信号、非法逻辑值、截断、周期窗口、长度变化和 JSON 转义。
- `demo/verify-oracle.py` 用 VCDVCD 独立解析计数器与 UART，检查原有首次差异，再枚举全部差异，对拍完整窗口及局部窗口的明细、总数、差异周期数、逐信号首次/最后周期和截断行为。
- `demo/verify-cli.py` 检查兼容 JSON、退出码、非法选项/数值和帮助输出。
- `demo/verify-consumer.py` 从独立 MoonBit 模块调用库；工作区使用本地待发布源码，不作为外部用户采用证明。

完整报告限制的是保留的差异明细量，输入文本与逐拍样本仍在内存中；未做大规模内存或性能保证。被用户排除的周期及采样沿之间的瞬态不参与比较。
