@echo off
setlocal EnableExtensions

set "WUD_ROOT=%~dp0"
set "WUD_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "WUD_BOOTSTRAP_DIR=%PUBLIC%\Documents"

if not defined PUBLIC set "WUD_BOOTSTRAP_DIR=%TEMP%"
if not exist "%WUD_BOOTSTRAP_DIR%" md "%WUD_BOOTSTRAP_DIR%" >nul 2>&1
set "WUD_BOOTSTRAP=%WUD_BOOTSTRAP_DIR%\Win11UpgradeDiag-Launcher.log"

if defined PROCESSOR_ARCHITEW6432 (
  set "WUD_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
)

if not exist "%WUD_PS%" (
  echo Windows PowerShell could not be found.
  pause
  exit /b 50
)

>>"%WUD_BOOTSTRAP%" echo.
>>"%WUD_BOOTSTRAP%" echo %DATE% %TIME% [CMD] Launcher started from "%WUD_ROOT%".
echo Win11UpgradeDiag launcher log: "%WUD_BOOTSTRAP%"

"%WUD_PS%" -NoProfile -ExecutionPolicy Bypass -File "%WUD_ROOT%Invoke-Win11UpgradeDiag.ps1" -BootstrapLogPath "%WUD_BOOTSTRAP%" %*

set "WUD_EXIT=%ERRORLEVEL%"
if not "%WUD_EXIT%"=="0" if not "%WUD_EXIT%"=="10" if not "%WUD_EXIT%"=="20" (
  echo.
  echo Win11UpgradeDiag exited with code %WUD_EXIT%.
  echo Review the launcher log: "%WUD_BOOTSTRAP%"
  pause
)
exit /b %WUD_EXIT%
