@echo off
setlocal EnableExtensions

set "WUD_ROOT=%~dp0"
set "WUD_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if defined PROCESSOR_ARCHITEW6432 (
  set "WUD_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
)

if not exist "%WUD_PS%" (
  echo Windows PowerShell could not be found.
  pause
  exit /b 50
)

"%WUD_PS%" -NoProfile -ExecutionPolicy Bypass -File "%WUD_ROOT%Invoke-Win11UpgradeDiag.ps1" %*

set "WUD_EXIT=%ERRORLEVEL%"
if not "%WUD_EXIT%"=="0" if not "%WUD_EXIT%"=="10" if not "%WUD_EXIT%"=="20" (
  echo.
  echo Win11UpgradeDiag exited with code %WUD_EXIT%.
  pause
)
exit /b %WUD_EXIT%
