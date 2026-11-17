# VCD 仿真回归比较

比较同一测试场景在两次 RTL 仿真中的行为。指定时钟、低有效复位和观测信号，工具会报告第一个不同的采样周期、信号值和两份 VCD 的时间戳。需要 MoonBit 和 Node.js 22.3+。

```powershell
moon run cmd/main -- baseline.vcd candidate.vcd tb.clk tb.rst_n tb.q
```

退出码为 0 表示匹配，1 表示值或周期数不同，2 表示输入有误。信号名使用 VCD 中的完整层级路径。时钟和复位必须各为一位。第一个观察到的低电平复位之后，从第一个复位已释放的上升沿起编号为 1。按时间戳内最后写入的值采样，保留 X 和 Z。后续复位期间跳过采样，周期号继续累计。比较适用于同一刺激、同一采样语义的单时钟仿真。仅在采样沿之间出现的瞬态超出检测范围。

## Lab 9 演示

`demo` 含原始、等价改写和故障版本的 XSim 波形，以及生成波形所用的 RTL 和 testbench。用下面两条命令复验，无需安装 Vivado。

```powershell
moon run cmd/main -- demo/baseline.vcd demo/equivalent.vcd tb_hex_counter_top.clk tb_hex_counter_top.rst_n tb_hex_counter_top.count
moon run cmd/main -- demo/baseline.vcd demo/faulty.vcd tb_hex_counter_top.clk tb_hex_counter_top.rst_n tb_hex_counter_top.count
```

等价改写把计数加数的位宽显式写为 4 位，986 拍一致。故障版本把终值提前一位，第一处差异发生在第 828 拍，计数期望 `1111`，实际 `0000`。如需重新生成波形，运行 `demo/generate.ps1` 并传入 Vivado 的 `bin` 目录。

`moon test` 覆盖时间尺度、复位时刻差异、短向量规范化、未知值和跨文件位宽变化。

## 独立 UART 案例与外部对拍

`demo/uart` 使用 Alex Forencich 的 MIT UART 发送器，保留原始版权。
等价改写得到相同的 664 拍。强制停止位为低的故障在第 146 拍首次出现。
该案例与 Lab 9 分别覆盖多位计数输出和串行协议输出。

```powershell
moon build
python -m pip install vcdvcd==2.6.0
python demo/verify-oracle.py _build/js/debug/build/cmd/main/main.js
```

脚本通过独立的 VCDVCD 解析器计算两种设计的采样序列，对拍首次差异及等价版本。
实际回执位于 `demo/oracle-verification.json`。重建 UART 波形可运行
`demo/uart/generate.ps1 -VivadoBin 'D:\Xilinx\Vivado\2018.3\bin'`。
算法取舍、复用基线和 AI 使用情况见 DESIGN.md。

## CI 中读取 JSON 结果

在文件参数前加 `--json` 可输出单行 JSON，退出码仍为 0 / 1 / 2。
`status` 为 `match`、`different`、`length_mismatch` 或 `invalid`；
`cycles` 在匹配时表示采样数，在差异时表示首次不同的周期。
`baseline_fs` 和 `candidate_fs` 使用十进制字符串，避免 JavaScript 大整数精度损失。
`length_mismatch` 的 `expected`、`actual` 是两份文件的采样数。
文件系统读取失败与参数不足仍输出原来的诊断信息，不属于 JSON 结果。

```powershell
moon run cmd/main -- --json demo/baseline.vcd demo/faulty.vcd tb_hex_counter_top.clk tb_hex_counter_top.rst_n tb_hex_counter_top.count
```

## 在自己的 MoonBit 项目中调用

运行 `moon add Sam-Hui-dot/vcd-regression@0.3.0`，在 `moon.pkg` 中导入
`"Sam-Hui-dot/vcd-regression" @vcd`。分别调用
`@vcd.capture(text, clock, reset, signals)` 得到两份 Trace，再调用
`@vcd.compare(baseline, candidate)`。可匹配的结果为：

- `@vcd.Match(count)`：全部采样周期一致。
- `@vcd.Different(cycle, signal, expected, actual, baseline_fs, candidate_fs)`：首次值差异。
- `@vcd.LengthMismatch(expected_count, actual_count)`：共同前缀一致，但采样数不同。

`capture` 和 `compare` 均可能抛出 `@vcd.InvalidTrace(message)`，调用者应处理输入错误。
预期与实际仅表示传入参数的顺序，工具不会判定哪一版设计符合规格。
同一 Trace 选择的信号顺序也必须相同。时间戳以飞秒表示；周期从 1 开始。

`python demo/verify-consumer.py` 会建立独立模块，通过工作区依赖调用公开 API，
验证调用者无需访问库的私有数据结构。这项检查使用本地源码；发布版本可以通过上述
`moon add` 命令安装。核心库适用 JS、WasmGC 和 Native；文件 CLI 使用 Node.js。

## 完整回归报告与周期区间（0.3.0）

```powershell
moon run cmd/main -- --report --json --max-diffs 20 demo/baseline.vcd demo/faulty.vcd tb_hex_counter_top.clk tb_hex_counter_top.rst_n tb_hex_counter_top.count
moon run cmd/main -- --skip-cycles 820 --cycles 20 --max-diffs 10 demo/baseline.vcd demo/faulty.vcd tb_hex_counter_top.clk tb_hex_counter_top.rst_n tb_hex_counter_top.count
```

`--report` 扫描选定区间的全部采样，返回总差异值数、不同周期数、逐信号首次与最后差异周期及有上限的差异列表。
`--max-diffs` 仅限制保留的明细，统计仍覆盖整个区间；`truncated` 表示明细被截断。
`--skip-cycles` 从复位后的第一拍开始跳过，`--cycles` 限定之后最多检查多少拍，报告仍使用原始、从 1 开始的周期号。
这些区间选项自动启用报告模式。未选区间默认比较完整采样；指定前缀时不会检查被排除的尾部。
共同区间没有值差异但采样数不同会返回 `length_mismatch`，并列出两侧采样数。

完整 JSON 与旧的首次差异 JSON 是两种模式。完整报告的 `difference_count` 和时间戳使用十进制字符串；
`differences` 按周期、所选信号的顺序排列；没有差异的信号，其 `first_cycle`、`last_cycle` 为 null。
文本模式也能输出完整报告。核心库入口为
`regression_report(base, candidate, skip_cycles=0, cycles=20, max_differences=100)`，
返回的报告提供 `to_json()` 和 `to_text()`；报告计算及 JSON 序列化均由 MoonBit 实现。

源码统计命令为 `python tools/source-lines.py`。它排除测试、空行、纯注释、JS FFI 内容和构建产物；
详细计数与验证说明见 [docs/VALIDATION.md](docs/VALIDATION.md)。
