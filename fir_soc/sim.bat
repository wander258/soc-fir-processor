@echo off
rem ============================================================
rem Usage:  sim.bat 01_counter
rem         sim.bat 02_delayline
rem         sim.bat 03_mac
rem         sim.bat 04_fir9
rem         sim.bat 05_fir81
rem
rem This wrapper calls sim.ps1 with -ExecutionPolicy Bypass so you
rem do not have to change the system script execution policy.
rem (ASCII only on purpose: cmd.exe reads .bat files in the OEM
rem  codepage, and non-ASCII bytes here can break parsing.)
rem ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sim.ps1" %*
