# SoC-FIR-Processor

带高阶 FIR 数字滤波器的 SoC 处理器设计（ARM 核 · 纯仿真验证）。

## 项目简介

- **处理器核**：ARM 架构
- **外设/加速器**：高阶 FIR 数字滤波器
- **验证方式**：Icarus Verilog / Verilator + GTKWave 纯仿真

## 目录结构

> 项目尚在起步阶段，目录随开发推进逐步补充。

```
工作区/
├── rtl/          # Verilog / SystemVerilog 源码
├── tb/           # 测试平台 (testbench)
├── fir/          # FIR 滤波器设计与系数生成 (MATLAB / Python)
├── sw/           # 处理器上运行的软件 / 测试程序
├── sim/          # 仿真脚本与 Makefile
└── docs/         # 文档、设计说明、报告
```

## 团队协作规范

1. 每个功能一个分支，完成后提交 Pull Request。
2. 提交信息格式：`<类型>: <说明>`，例如 `feat: 添加 FIR 滤波器模块`、`fix: 修正时序问题`。
3. 合并到 `main` 前需至少一名队友 review。
4. 不要提交仿真产物（`.vcd`、`.vvp`、`obj_dir/` 等），已写入 `.gitignore`。

## 环境依赖

- Icarus Verilog（`iverilog` + `vvp`）
- GTKWave（波形查看）
- Python 3（`numpy` / `scipy` / `matplotlib` 用于 FIR 系数生成）
- GNU make / CMake（构建）

> 建议安装 VSCode 推荐插件：打开项目后 VSCode 会根据 `.vscode/extensions.json` 自动提示安装。
