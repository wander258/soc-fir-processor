# fir_soc —— 从零到 81 阶 FIR + SoC 的起步工程

> 这个目录里没有"计划"，只有**能跑的东西**。
> 八个实验全部已在你机器上实测通过（iverilog 14.0 + GTKWave，见第 7 节）。
>
> 实验 05 就是**赛题第一项要求的完整实现**：81 阶、系数 16bit 定点、数据 16bit、
> 1 sample/cycle，输出与软件黄金模型逐位一致。
>
> **⚠️ 新增（SoC 部分）**：实验 06/07/08 把 FIR 挂上 AXI 总线、拼成完整 SoC
> （FIR + UART + SRAM + 总线互连），并配了 C 驱动（`sw/`）。
> **完整的完成思路、学习路线、赛题对照，请看 [`学习指南.md`](学习指南.md)。**
>
> **看不懂波形？** 先看 `GTKWave入门.md`，再跑 `wave.bat 01_counter`
> —— 它会在终端里直接把波形画成 ASCII 图，不需要开 GTKWave。

---

## 1. 工具链（你已经装好了）

你已经把 OSS CAD Suite 解压到：

```
E:\FPGA\OSS-CAD-suite\oss-cad-suite
```

`sim.ps1` **已经配好这个路径**，不需要再设环境变量、不需要改 PATH。
想确认一下的话：

```powershell
E:\FPGA\OSS-CAD-suite\oss-cad-suite\bin\iverilog.exe -V
```

> 以后如果换了安装位置，只改 `sim.ps1` 里这一行：
> `$OssCadSuite = "E:\FPGA\OSS-CAD-suite\oss-cad-suite"`

**另外注意一个坑**（我第一次实测就踩到了）：
`sim.ps1` 必须存成 **UTF-8 with BOM**。Windows PowerShell 5.1 读没有 BOM 的
`.ps1` 会按 GBK 解码，中文注释会把字符串括号截断，报一堆
`The string is missing the terminator` 这种莫名其妙的语法错。现在已经处理好了，
**你以后自己改这个文件时，编辑器要选 "UTF-8 with BOM"**，不要选 "UTF-8"。
`sim.bat` 则相反，里面**只能写英文注释**（cmd.exe 按 OEM 代码页读 .bat）。

---

## 2. 跑起来（三条命令）

```powershell
cd "E:\Deepseek Harness\fir_soc"
.\sim.bat 01_counter
```

`sim.bat` 会：自动找到 iverilog → 编译 → 运行仿真 → 打印 PASS/FAIL → 自动打开 GTKWave。

**统一用 `sim.bat`，不要直接跑 `.ps1`**，否则会撞上 PowerShell 的脚本执行策略。

---

## 3. 五个实验，难度递进

| 实验 | 内容 | 学到什么 | 和赛题的关系 |
|---|---|---|---|
| `01_counter` | 4 位计数器 + 自校验 TB | 时钟、复位、`posedge`、非阻塞赋值、看波形 | 所有时序电路的地基 |
| `02_delayline` | 移位寄存器延迟线 | 寄存器数组、`en` 使能、延迟与流水线 | **FIR 的骨架**，81 阶 = 80 级延迟线 |
| `03_mac` | 有符号乘累加器 | 16×16→32 位、**符号扩展**、为什么累加器要 40 位 | FIR 的算术核心，也是初赛最常见的翻车点 |
| `04_fir9` | 9 阶 FIR + 软件黄金模型比对 | 系数设计、Q1.15 定点、并行乘法、饱和截位 | 81 阶的缩小版，架构完全一样 |
| `05_fir81` | **81 阶 FIR** | 同上，但规模到赛题要求 | **赛题第 1 项要求的完整答案** |
| `06_axi_lite` | AXI-Lite 总线握手 + SRAM 从设备 | **valid/ready 握手**、写/读通道、按字节写 | 赛题 AXI 互连/桥的地基 |
| `07_fir_axi` | FIR 挂上总线当外设（9 阶调试） | 寄存器映射、系数可配置、FIFO 缓冲 | CPU 通过总线配置 FIR |
| `08_soc` | **完整 SoC**（81 阶 FIR+UART+SRAM+互连） | 总线互连、地址译码、软硬协同、UART | **赛题"模块说明"整张图的代码版** |

全部跑一遍：

```powershell
.\sim.bat 01_counter
.\sim.bat 02_delayline
.\sim.bat 03_mac
.\sim.bat 04_fir9
.\sim.bat 05_fir81
.\sim.bat 06_axi_lite
.\sim.bat 07_fir_axi
.\sim.bat 08_soc
```

> `sim.bat` 跑完会**自动在终端里打印 ASCII 波形**，然后再打开 GTKWave。
> 只想看波形不开 GTKWave：`.\sim.bat 01_counter -NoWave`
> 事后单独看波形：`.\wave.bat 01_counter`（详见 `GTKWave入门.md`）

### 看波形（这是能不能学会的分水岭）

```powershell
.\wave.bat 01_counter                                  # 终端 ASCII 波形
.\wave.bat 01_counter --list                           # 先列出有哪些信号
.\wave.bat 01_counter --radix dec                      # 十进制 + 有符号
.\wave.bat 05_fir81 --radix dec --sig clk,din,dout --from 1500 --to 2300
```

**强烈建议：先在终端把波形看懂，再进 GTKWave 练操作。**
详细的界面说明、快捷键、五个实验各自"该看到什么"，都在 `GTKWave入门.md` 里。

### 完整工作流（这套流程直接搬到赛题上用）

```powershell
# 1) 用 Python 设计滤波器系数 + 生成测试向量
python gen_fir_vectors.py --taps 81 --cutoff 0.12 --nsamp 256 --outdir 05_fir81

# 2) 跑 RTL 仿真：TB 自动和黄金模型逐位比对，并导出 got.hex
.\sim.bat 05_fir81

# 3) 用 Python 再独立复核一遍（双保险）
python gen_fir_vectors.py --taps 81 --cutoff 0.12 --check 05_fir81\got.hex --outdir 05_fir81
```

实测输出：

```
===== PASS: 336 个样本与软件黄金模型逐位一致 =====      ← 来自于 TB 自校验
===== PASS: 前 336 个样本与黄金模型逐位一致 =====        ← 来自于 Python 复核
```

赛题要求的"误差 < 0.1%"，我们这里做到的是**逐位一致（误差 = 0）**。

### ⚠️ 05_fir81 的两个已知局限（这是下一步要做的）

1. **时序大概率不收敛**。`fir.v` 里 81 项加法串成一条组合链
   （`sum = sum + ...` 循环 81 次），组合路径太长，50MHz 跑不过。
   功能是对的，但这是"能不能上板"的问题。
   → 下一步：把累加改成**流水线加法树**（成对相加，每级打拍），或者接受
   更多拍的延迟换频率。
2. **81 个乘法器全并行**，占 81 个 DSP。决赛要求做**对称优化**：
   `h[k] == h[80-k]`，先 `x[k] + x[80-k]` 再乘，乘法器降到 **41 个**，
   面积和时序都会明显改善。这是决赛"架构创新 20 分"明示的加分项。

---

## 4. 学习路径（"不知道去哪学"的答案）

按这个顺序，**每天 6 小时，两周**能到"能自己写 FIR + 自校验 TB"的水平。
配合上面的实验做，不要只看不写。

### 第 1～2 天：Verilog 语法（只刷题，别看书）

**平台：HDLBits** <https://hdlbits.01xz.net/wiki/Main_Page>
（在线做题，写完立刻能验证对错。中文题解搜"HDLBits 中文"就有一堆）

按这个顺序做，不要跳：

1. `Getting Started`
2. `Verilog Language → Basics`
3. `Verilog Language → Vectors`
4. `Verilog Language → Modules: Hierarchy`
5. `Verilog Language → Procedures`（**重点：always 块、阻塞 vs 非阻塞**）
6. `Verilog Language → More Verilog Features`

**这两天唯一的目标**：能不查资料写出一个带 `always @(posedge clk)` 和 `if (!rst_n)` 的模块。

### 第 3～4 天：组合 + 时序电路

1. `Circuits → Combinational Logic → Basic Gates` / `Multiplexers` / `Arithmetic Circuits`
2. `Circuits → Sequential Logic → Latches and Flip-Flops`（**重点：latch 是怎么意外产生的**）
3. `Circuits → Sequential Logic → Counters`
4. `Circuits → Sequential Logic → Shift Registers`（← 就是实验 02）

**目标**：理解这条铁律——
组合逻辑用 `assign` / `always @(*)` + 阻塞赋值；
时序逻辑用 `always @(posedge clk)` + 非阻塞赋值 `<=`。

### 第 5 天：写 testbench

1. `Verification → Writing Testbenches`
2. 把实验 01/02/03 的 TB 抄一遍、改一遍、故意改错一遍，看报错长什么样

**目标**：会写"给定激励 → 检查输出 → 打印 PASS/FAIL"的自校验 TB。
这是赛题 10% 代码分 + 15% 报告分的基础。

### 第 6～7 天：定点数 + FIR 原理

- 跑 `gen_fir_vectors.py`，把 `--taps` 从 9 改到 81，看系数怎么变
- 自己画一遍系数的**幅频响应**（Python + matplotlib，或手算几个点）
- 想清楚 3 个问题（想不清楚就说明还没懂）：
  1. 为什么系数是对称的？对称带来什么好处？（→ 线性相位 + 乘法器减半）
  2. 为什么 16bit × 16bit 的结果要右移 15 位才回到 Q1.15？
  3. 为什么 81 阶的累加器要 40 位，32 位为什么不够？

**参考**：<https://www.dspguide.com/>（免费在线教材，第 14～16 章讲 FIR）
或 Oppenheim《离散时间信号处理》第 6～7 章（你信号与系统课的内容直接对上）

### 第 8～14 天：AXI 协议（最难，也是决定成败的地方）

- 先读 **AMBA APB**（最简单，半天）：<https://developer.arm.com/documentation/ihi0024/latest/>
- 再读 **AMBA AHB-Lite**（M0 用的就是这个）：<https://developer.arm.com/documentation/ihi0033/latest/>
- 最后啃 **AMBA AXI**（重点，3～4 天）：<https://developer.arm.com/documentation/ihi0022/latest/>

读 AXI **不要通读**，只抓这 4 件事：
1. 5 个通道分别是什么（AW / W / B / AR / R）
2. VALID / READY 握手的铁律（谁等谁、什么时候能撤）
3. `AxLEN` / `AxSIZE` / `AxBURST` 怎么决定一次传多少、传多宽、怎么跳地址
4. 为什么突发不能跨 4KB 边界

**目标**：能默画一次 INCR 写 + 一次 INCR 读的完整时序图。

---

## 5. 目录结构

```
fir_soc\
├── README.md               ← 你正在看的这个
├── iverilog使用说明.md      ← iverilog 在哪、怎么用、报错怎么读（新手先看这个）
├── GTKWave入门.md          ← GTKWave 界面/快捷键/"该看到什么"
├── sim.ps1                 ← 一键编译+仿真+看波形（必须存成 UTF-8 with BOM）
├── sim.bat                 ← 外壳，绕开执行策略（只能写英文注释）
├── vcd_wave.py             ← 把 VCD 画成终端 ASCII 波形（纯标准库）
├── wave.bat                ← 单独看波形：wave.bat 01_counter
├── gen_fir_vectors.py      ← 系数设计 + 向量生成 + 黄金模型（纯标准库，无需 pip）
├── 学习指南.md              ← ★ SoC 完整完成思路 + 学习路线 + 赛题对照（先看这个）
├── 赛题原文.txt             ← 赛题 PDF 提取出的文字版（参考）
├── PATH备份_改之前.txt      ← 你改系统 PATH 前的原始值（要还原时用）
├── 01_counter\             ← counter.v      tb_counter.v
├── 02_delayline\           ← delay_line.v   tb_delay_line.v
├── 03_mac\                 ← mac.v          tb_mac.v
├── 04_fir9\                ← fir.v  tb_fir.v  + coeffs.vh / stim.hex / exp.hex
├── 05_fir81\               ← fir.v  tb_fir.v  + coeffs.vh / stim.hex / exp.hex
├── 06_axi_lite\            ← tb_axi_sram.v（学 AXI-Lite 握手）
├── 07_fir_axi\             ← tb_fir_axi.v（FIR 挂总线，9 阶）+ coeffs.hex/stim.hex/exp.hex
├── 08_soc\                 ← tb_soc.v（完整 SoC，81 阶）+ coeffs.hex/stim.hex/exp.hex
├── rtl\                    ← SoC 的可综合 RTL 源码（fir_cfg/fir_axi/xbar/uart/sram/soc_top）
└── sw\                     ← C 驱动（fir_regs.h / fir_driver.c / main.c）
```

`coeffs.vh`、`stim.hex`、`exp.hex` 都是 `gen_fir_vectors.py` 生成的，**不要手改**；
改了系数就重新跑一遍生成命令。

---

## 6. 常见报错速查

| 报错 | 原因 | 怎么办 |
|---|---|---|
| `无法加载文件 ... 禁止运行脚本` | PowerShell 执行策略 | 用 `.\sim.bat`，别直接跑 `.ps1` |
| `The string is missing the terminator` | `.ps1` 存成了无 BOM 的 UTF-8 | 另存为 **UTF-8 with BOM** |
| `'xxx' 不是内部或外部命令`（在 .bat 里） | `.bat` 里写了中文注释 | `.bat` 只写英文 |
| `error: Unable to bind wire/reg/memory` | 模块实例化时端口名写错 | 检查 `.端口名(信号名)` 和模块定义是否一致 |
| `warning: implicit definition of wire 'xxx'` | 用了没声明的信号 | **危险警告**，一定是拼写错了，必须改掉 |
| `error: Unknown module type: xxx` | 源文件没加进编译列表 | 在 `sim.ps1` 的 `$src` 里补上文件名 |
| `error: 'xxx' is not a valid l-value` | 给 wire 赋值了 | wire 只能被 `assign` 驱动，要赋值就改成 `reg` |
| 波形里信号全是 X | 没复位 / 时钟没连上 | 检查 `rst_n` 和 `clk` 有没有接对 |
| `got.hex` 里出现 `xxxx` | `$writememh` 导出了未初始化的数组项 | TB 里先把数组清零（已修好，见 `tb_fir.v`） |
| GTKWave 打开是空的 | 信号还没加进来（不是软件坏了） | 双击左侧 SST 里的信号名，见 `GTKWave入门.md` |
| GTKWave 里波形挤成一条红线 | 没缩放 | `Time → Zoom Best Fit` |
| GTKWave 里负数显示成 `FC18` | 默认十六进制 | 点中信号 → `Edit → Data Format → Signed` |
| TB 里没 `$dumpvars` 的信号找不到 | 没被记录进 VCD | 改 `$dumpvars(0, tb_xxx)` 或在里面加上该信号 |

---

## 7. 实测记录（不是"应该能跑"，是真跑过了）

环境：Windows PowerShell 5.1 + OSS CAD Suite 的 Icarus Verilog 14.0 + GTKWave。

| 实验 | 结果 |
|---|---|
| `01_counter` | PASS：复位检查 + 20 拍回绕检查都通过 |
| `02_delayline` | PASS：`d0=8`、`dout=5`，延迟 3 拍正确 |
| `03_mac` | PASS：4 组有符号用例（含正数/负数/最大正/最负）全部正确 |
| `04_fir9` | PASS：72 个样本与黄金模型逐位一致 |
| `05_fir81` | PASS：336 个样本与黄金模型逐位一致；Python 复核同样 PASS |

波形工具也实测过：

| 工具 | 结果 |
|---|---|
| `vcd_wave.py` | 五个实验的 VCD 都能正确解析并画出 ASCII 波形 |
| `wave.bat` | 无参数返回 1 并打印用法；带 6 个参数调用退出码 0 |
| `sim.ps1` | 端到端跑通：编译 → 仿真 → 终端波形 → 打开 GTKWave |

过程中真实踩到并已修掉的 6 个问题（留个记录，你以后可能也会遇到）：

1. `.bat` 里写中文注释 → cmd 按 GBK 解析，把 `powershell -ExecutionPolicy`
   拆坏了，报 `'-ExecutionPolicy' 不是内部或外部命令`。→ 改纯英文。
2. `.ps1` 存成无 BOM 的 UTF-8 → PowerShell 5.1 按 GBK 读，中文字符串把
   引号"吃掉"，报一堆 `missing the terminator` 语法错。→ 加 BOM。
3. `$writememh` 导出未初始化数组项写成 `xxxx` → Python 解析 `got.hex` 报
   `invalid literal for int() with base 16: 'xxxx'`。→ TB 里先清零 + Python 跳过未知项。
4. **VCD 里同一个标识符会在不同层次重复声明**（`tb.clk` 和 `tb.dut.clk` 共用一个 `#`），
   按标识符存字典会把顶层那份覆盖掉，导致顶层 `clk` 在波形里消失。→ 存成"标识符 → 声明列表"。
5. `$timescale` 的值**可能在下一行**，只读同一行会解析不到。→ 往下找一行。
6. **cmd 的 `%1`~`%9` 会把逗号当分隔符**，`--sig clk,din,dout` 被拆成 3 个参数，
   导致 `--sig` 后面的选项全部错位。→ 用 `%*` 再用 `for /f "tokens=1,*"` 去掉第一个词。

---

## 8. 方向上的实话

- 赛题是**研究生难度**，1 个月对大二非常紧张。但初赛只看功能，不看性能，
  所以目标是"做出一个功能完整的版本"。
- 最花时间的**不是 FIR**（实验 05 已经把功能部分做完了），而是
  **AXI 总线 + Cortex-M0 联调 + C 驱动**。第 8～14 天那一段才是真正的战场。
- 建议节奏：这一周把实验 01→05 全部跑通并**读懂每一行**（约 1 周），
  有了赛题 20 分的那一块；接着 2 周全力啃总线，最后 1 周做集成和文档。
