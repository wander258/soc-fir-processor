@echo off
rem ============================================================
rem sim/sim.cmd —— 一键仿真（sim.ps1 的包装器）
rem
rem 为什么要包一层：Windows 默认执行策略禁止直接运行 .ps1，
rem 这里用 -ExecutionPolicy Bypass 绕过，双击或命令行都能跑。
rem 参数原样透传给 sim.ps1，例如：  sim\sim.cmd -Only dma
rem ============================================================
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sim.ps1" %*
exit /b %ERRORLEVEL%
