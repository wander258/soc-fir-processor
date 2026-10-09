@echo off
rem ============================================================
rem Usage:  wave.bat 01_counter
rem         wave.bat 02_delayline
rem         wave.bat 03_mac
rem         wave.bat 04_fir9
rem         wave.bat 05_fir81
rem
rem Draws the saved VCD waveform as an ASCII timing diagram in the
rem terminal. Use this when GTKWave feels overwhelming.
rem
rem Options after the lab name are passed straight to vcd_wave.py:
rem     wave.bat 05_fir81 --radix dec --sig clk,din,dout --from 1500 --to 2300
rem     wave.bat 01_counter --list
rem ============================================================
setlocal

set "LAB=%~1"
if "%LAB%"=="" (
    echo Usage: wave.bat ^<lab^> [options]
    echo   labs: 01_counter 02_delayline 03_mac 04_fir9 05_fir81
    echo   e.g.  wave.bat 05_fir81 --radix dec --sig clk,din,dout
    exit /b 1
)

set "VCD=%LAB%\tb_counter.vcd"
if /i "%LAB%"=="02_delayline" set "VCD=%LAB%\tb_delay_line.vcd"
if /i "%LAB%"=="03_mac"       set "VCD=%LAB%\tb_mac.vcd"
if /i "%LAB%"=="04_fir9"      set "VCD=%LAB%\tb_fir.vcd"
if /i "%LAB%"=="05_fir81"     set "VCD=%LAB%\tb_fir.vcd"

if not exist "%VCD%" (
    echo Waveform not found: %VCD%
    echo Run  sim.bat %LAB%  first to generate it.
    exit /b 1
)

rem NOTE: cmd splits %1..%9 on commas, so "clk,din,dout" would break into
rem three arguments. %* keeps the raw string, so drop the first token from
rem %* instead. for /f only treats space and tab as delimiters by default.
set "REST="
for /f "tokens=1,*" %%a in ("%*") do set "REST=%%b"

python "%~dp0vcd_wave.py" "%VCD%" %REST%
