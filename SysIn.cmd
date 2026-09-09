@echo off
setlocal

set "_sysin_host="

if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "_sysin_host=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined _sysin_host if exist "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe" set "_sysin_host=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
if not defined _sysin_host if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "_sysin_host=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not defined _sysin_host if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "_sysin_host=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"

if not defined _sysin_host (
    echo SysIn could not find PowerShell 7 or Windows PowerShell 5.1. 1>&2
    endlocal
    exit /b 69
)

"%_sysin_host%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\SysIn.ps1" %*
set "_sysin_exit=%errorlevel%"
endlocal & exit /b %_sysin_exit%
