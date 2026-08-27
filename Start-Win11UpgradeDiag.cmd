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

if not exist "%WUD_ROOT%Prepare-Win11UpgradeDiag.cmd" goto WUD_LAUNCH

call "%WUD_ROOT%Prepare-Win11UpgradeDiag.cmd" -Check
set "WUD_PREP_EXIT=%ERRORLEVEL%"
if "%WUD_PREP_EXIT%"=="10" goto WUD_PREP_REQUIRED
if not "%WUD_PREP_EXIT%"=="0" goto WUD_PREP_FAILED
goto WUD_LAUNCH

:WUD_PREP_REQUIRED
echo.
echo The extracted bundle carries Windows download-security markers.
echo Win11UpgradeDiag can remove those markers from this verified folder only.
call "%WUD_ROOT%Prepare-Win11UpgradeDiag.cmd"
set "WUD_PREP_EXIT=%ERRORLEVEL%"
if not "%WUD_PREP_EXIT%"=="0" goto WUD_PREP_FAILED
goto WUD_LAUNCH

:WUD_PREP_FAILED
>>"%WUD_BOOTSTRAP%" echo %DATE% %TIME% [ERROR] Bundle preparation stopped with exit code %WUD_PREP_EXIT%.
echo.
echo Win11UpgradeDiag did not start because bundle preparation returned code %WUD_PREP_EXIT%.
echo If AllSigned, WDAC, or AppLocker is enforced, use an organization-signed and allowlisted build.
echo Review the launcher log: "%WUD_BOOTSTRAP%"
pause
exit /b %WUD_PREP_EXIT%

:WUD_LAUNCH

"%WUD_PS%" -NoProfile -ExecutionPolicy Bypass -File "%WUD_ROOT%Invoke-Win11UpgradeDiag.ps1" -BootstrapLogPath "%WUD_BOOTSTRAP%" %*

set "WUD_EXIT=%ERRORLEVEL%"
if not "%WUD_EXIT%"=="0" if not "%WUD_EXIT%"=="10" if not "%WUD_EXIT%"=="20" (
  echo.
  echo Win11UpgradeDiag exited with code %WUD_EXIT%.
  echo Review the launcher log: "%WUD_BOOTSTRAP%"
  pause
)
exit /b %WUD_EXIT%
