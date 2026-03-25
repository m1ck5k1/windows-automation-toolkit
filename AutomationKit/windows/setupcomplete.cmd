@echo off
:: Project: Unified Digital Signage Imaging Workflow (2026)
:: File: setupcomplete.cmd
:: Location: C:\Windows\Setup\Scripts\setupcomplete.cmd
:: Description: Post-Sysprep Driver Injection.
::             Runs as SYSTEM during the "Specialize" phase (before login).

:: Set Logging
SET LOGFILE=C:\AutomationKit\logs\setupcomplete.log
IF NOT EXIST "C:\AutomationKit\logs" MD "C:\AutomationKit\logs"
echo %DATE% %TIME% : [START] Digital Signage Post-Imaging Setup >> %LOGFILE%

:: ---------------------------------------------------------------------------
:: 0. COPY AUTOMATION KIT FROM USB
:: ---------------------------------------------------------------------------
echo %DATE% %TIME% : Searching for AutomationKit on USB... >> %LOGFILE%
SET AUTOMATION_KIT_SOURCE=

:: Iterate through common drive letters for USB drives
FOR %%D IN (D E F G H I J K L M N O P Q R S T U V W X Y Z) DO (
    IF EXIST "%%D:\AutomationKit" (
        SET AUTOMATION_KIT_SOURCE=%%D:\AutomationKit
        echo %DATE% %TIME% : Found AutomationKit at %%D:\AutomationKit >> %LOGFILE%
        GOTO :COPY_AUTOMATION_KIT_FOUND
    )
)

:COPY_AUTOMATION_KIT_FOUND
IF NOT DEFINED AUTOMATION_KIT_SOURCE (
    echo %DATE% %TIME% : [ERROR] AutomationKit not found on any removable drive. Skipping copy. >> %LOGFILE%
) ELSE (
    echo %DATE% %TIME% : Copying AutomationKit to C:\AutomationKit\... >> %LOGFILE%
    xcopy "%AUTOMATION_KIT_SOURCE%" "C:\AutomationKit" /E /H /C /I /Y >> %LOGFILE% 2>&1
    IF %ERRORLEVEL% NEQ 0 (
        echo %DATE% %TIME% : [ERROR] Failed to copy AutomationKit. Error: %ERRORLEVEL% >> %LOGFILE%
    ) ELSE (
        echo %DATE% %TIME% : AutomationKit copied successfully. >> %LOGFILE%
    )
)

:: ---------------------------------------------------------------------------
:: 1. SET COMPUTER NAME (DS-{Serial Number})
:: ---------------------------------------------------------------------------
echo %DATE% %TIME% : Setting Computer Name (DS-Serial Number)... >> %LOGFILE%

FOR /F "tokens=2 delims==" %%S IN ('wmic bios get serialnumber /value ^| find "="') DO (
    SET "SERIAL=%%S"
)

IF DEFINED SERIAL (
    SET "NEW_COMPUTER_NAME=DS-%SERIAL%"
    echo %DATE% %TIME% : New Computer Name: %NEW_COMPUTER_NAME% >> %LOGFILE%

    :: Set the computer name in the registry
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v Hostname /t REG_SZ /d "%NEW_COMPUTER_NAME%" /f >> %LOGFILE% 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "SyncHostNameWithDnscfg" /t REG_DWORD /d 1 /f >> %LOGFILE% 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" /v ComputerName /t REG_SZ /d "%NEW_COMPUTER_NAME%" /f >> %LOGFILE% 2>&1
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" /v ComputerName /t REG_SZ /d "%NEW_COMPUTER_NAME%" /f >> %LOGFILE% 2>&1
    echo %DATE% %TIME% : Registry entries for computer name updated. >> %LOGFILE%
) ELSE (
    echo %DATE% %TIME% : [ERROR] Could not retrieve serial number. Computer name will remain random or default. >> %LOGFILE%
)

:: ---------------------------------------------------------------------------
:: 2. HARDWARE DETECTION
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
:: 3. DRIVER INJECTION
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
:: 4. CLEANUP & FINALIZE
:: ---------------------------------------------------------------------------
:: Clean up temp file
del C:\Windows\Temp\mfg.txt

:: Persistent Logging: Copy setupcomplete.log back to USB
echo %DATE% %TIME% : Copying setupcomplete.log to USB for persistence... >> %LOGFILE%
SET USB_DRIVE_LETTER=
FOR %%D IN (D E F G H I J K L M N O P Q R S T U V W X Y Z) DO (
    IF EXIST "%%D:\AutomationKit\logs" (
        SET USB_DRIVE_LETTER=%%D:
        GOTO :USB_DRIVE_FOUND_LOG_COPY
    )
)

:USB_DRIVE_FOUND_LOG_COPY
IF DEFINED USB_DRIVE_LETTER (
    FOR /F "tokens=1-4 delims=/ " %%i in ('%DATE%') do (
        SET CurrentDate=%%k%%j%%i
    )
    FOR /F "tokens=1-3 delims=:." %%i in ('%TIME%') do (
        SET CurrentTime=%%i%%j%%k
    )
    SET LOG_FILENAME=setupcomplete_%CurrentDate%_%CurrentTime%.log
    xcopy "C:\AutomationKit\logs\setupcomplete.log" "%USB_DRIVE_LETTER%\AutomationKit\logs\%LOG_FILENAME%" /Y /R /H >> %LOGFILE% 2>&1
    IF %ERRORLEVEL% NEQ 0 (
        echo %DATE% %TIME% : [ERROR] Failed to copy setupcomplete.log to USB. Error: %ERRORLEVEL% >> %LOGFILE%
    ) ELSE (
        echo %DATE% %TIME% : setupcomplete.log copied successfully to USB. >> %LOGFILE%
    )
) ELSE (
    echo %DATE% %TIME% : [ERROR] USB drive with AutomationKit\logs not found. Cannot save setupcomplete.log persistently. >> %LOGFILE%
)

echo %DATE% %TIME% : [END] Setup Complete. >> %LOGFILE%
exit 0
