@echo off
:: Project: Unified Digital Signage Imaging Workflow (2026)
:: File: setupcomplete.cmd
:: Location: C:\Windows\Setup\Scripts\setupcomplete.cmd
:: Description: Post-Sysprep Driver Injection.
::             Runs as SYSTEM during the "Specialize" phase (before login).

:: Set Logging
SET LOGFILE=C:\Windows\Panther\setupcomplete.log
echo %DATE% %TIME% : [START] Digital Signage Post-Imaging Setup >> %LOGFILE%

:: ---------------------------------------------------------------------------
:: 1. HARDWARE DETECTION
:: ---------------------------------------------------------------------------
echo %DATE% %TIME% : Detecting Manufacturer... >> %LOGFILE%
wmic computersystem get manufacturer > C:\Windows\Temp\mfg.txt
type C:\Windows\Temp\mfg.txt >> %LOGFILE%

:: Check for Lenovo
findstr /I "Lenovo" C:\Windows\Temp\mfg.txt > nul
IF %ERRORLEVEL% EQU 0 (
    set TARGET_DIR=C:\DRIVERS\Lenovo
    goto :INJECT
)

:: Check for Dell
findstr /I "Dell" C:\Windows\Temp\mfg.txt > nul
IF %ERRORLEVEL% EQU 0 (
    set TARGET_DIR=C:\DRIVERS\Dell
    goto :INJECT
)

:: Check for HPE
findstr /I "HPE" C:\Windows\Temp\mfg.txt > nul
IF %ERRORLEVEL% EQU 0 (
    set TARGET_DIR=C:\DRIVERS\HPE
    goto :INJECT
)

:: Fallback (Unknown Hardware) - Scan Root
echo %DATE% %TIME% : [WARN] Manufacturer not matched. Defaulting to C:\DRIVERS root. >> %LOGFILE%
set TARGET_DIR=C:\DRIVERS
goto :INJECT

:: ---------------------------------------------------------------------------
:: 2. DRIVER INJECTION
:: ---------------------------------------------------------------------------
:INJECT
echo %DATE% %TIME% : Target Driver Path: %TARGET_DIR% >> %LOGFILE%

IF EXIST "%TARGET_DIR%" (
    echo %DATE% %TIME% : Folder exists. Starting PnPUtil injection... >> %LOGFILE%
    :: /add-driver: Adds driver package to driver store
    :: /subdirs:    Traverses subdirectories
    :: /install:    Installs driver on matching devices immediately
    pnputil.exe /add-driver "%TARGET_DIR%\*.inf" /subdirs /install >> %LOGFILE% 2>&1
) ELSE (
    echo %DATE% %TIME% : [ERROR] Target directory not found! >> %LOGFILE%
)

:: ---------------------------------------------------------------------------
:: 3. CLEANUP & FINALIZE
:: ---------------------------------------------------------------------------
:: Clean up temp file
del C:\Windows\Temp\mfg.txt

echo %DATE% %TIME% : [END] Setup Complete. >> %LOGFILE%
exit 0
