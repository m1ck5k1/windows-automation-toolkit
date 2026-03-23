### Argus Test Plan (`docs/argus_test_plan.md`)

**Objective:** Verify the correct and hidden operation of the Argus telemetry agent on provisioned Windows machines.

**Test Environment:** A newly provisioned Windows 10/11 machine using `provision_machine.sh`.

**Pre-requisites:**
*   Machine has completed `provision_machine.sh` execution.
*   User `ds` is configured for autologin.
*   SSH access to the target machine is functional.

**Test Cases:**

1.  **Verify Argus Installation Path:**
    *   **Description:** Confirm that `argus.exe` and `run_argus.cmd` are present in `C:\Program Files\Argus`.
    *   **Steps (via SSH/PowerShell):**
        ```powershell
        Test-Path "C:\Program Files\Argus\argus.exe"
        Test-Path "C:\Program Files\Argusun_argus.cmd"
        ```
    *   **Expected Result:** Both commands return `True`.

2.  **Verify VBScript Launcher Creation:**
    *   **Description:** Confirm the `launch_argus.vbs` script exists and contains the correct content to launch `run_argus.cmd` invisibly.
    *   **Steps (via SSH/PowerShell):}
        ```powershell
        Test-Path "C:\Program Files\Argus\launch_argus.vbs"
        Get-Content "C:\Program Files\Argus\launch_argus.vbs" | Select-String -Pattern "WshShell.Run chr(34) & ""C:\Program Files\Argusun_argus.cmd"" & chr(34), 0"
        ```
    *   **Expected Result:** `Test-Path` returns `True`. `Select-String` finds the expected line in the VBScript content.

3.  **Verify Scheduled Task Configuration:**
    *   **Description:** Confirm that the "ArgusAgent" scheduled task exists, is enabled, triggers on user login (`ds`), and executes `wscript.exe` with the VBScript launcher.
    *   **Steps (via SSH/PowerShell):}
        ```powershell
        Get-ScheduledTask -TaskName "ArgusAgent"
        (Get-ScheduledTask -TaskName "ArgusAgent").Triggers | Where-Object {$_.RepetitionInterval -eq (New-TimeSpan -Days 0) -and $_.Enabled -eq $True -and $_.LogonType -eq "S-1-5-21-..."} # Check for AtLogOn
        (Get-ScheduledTask -TaskName "ArgusAgent").Actions | Where-Object {$_.Execute -eq "wscript.exe" -and $_.Arguments -like "*launch_argus.vbs*"}
        ```
    *   **Expected Result:** Task exists and is configured as expected (especially `wscript.exe` running the VBScript at login for user `ds`).

4.  **Verify Hidden Process Execution:**
    *   **Description:** After a system reboot (or re-login), confirm that the Argus process is running but *without* a visible console window.
    *   **Steps (via SSH/PowerShell):}
        ```powershell
        Get-Process -Name "argus" -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, MainWindowHandle
        ```
    *   **Expected Result:** An `argus` process is listed, and its `MainWindowHandle` property should be `0` (or empty/null), indicating no visible window.

5.  **Verify No Legacy Startup Item (if applicable):**
    *   **Description:** Confirm that `run_argus.cmd` is *not* present in standard Windows startup folders if it was ever placed there manually or by older scripts. (The `fix_argus_window.ps1` script implicitly handles this by not creating one there).
    *   **Steps (via SSH/PowerShell):}
        ```powershell
        Test-Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startupun_argus.cmd"
        Test-Path "$env:PROGRAMDATA\Microsoft\Windows\Start Menu\Programs\Startupun_argus.cmd"
        ```
    *   **Expected Result:** Both commands return `False`.
