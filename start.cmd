@echo off
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7.4 or newer is required. Install Microsoft.PowerShell, then open this launcher again.
  echo https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows
  pause
  exit /b 1
)
pwsh.exe -NoLogo -NoProfile -File "%~dp0Connect.ps1" -Action Launch
if errorlevel 1 pause
