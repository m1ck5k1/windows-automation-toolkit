@echo off
:: Wrapper to bypass Execution Policy for the PowerShell script
echo Launching Consolidated Post-OS Installation Script...
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0post-os-install.ps1"
pause
