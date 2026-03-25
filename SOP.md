# Standard Operating Procedures (SOP) - Machine Provisioning
**Project:** Incidium Digital Signage / Argus Telemetry
**Date:** March 3, 2026

## Phase 1: Physical Setup & Bootstrapping
**Goal:** Take a bare metal machine and make it SSH-accessible.

1.  **Boot from USB:**
    *   Insert the prepared USB drive (created using `scripts/linux/orchestrate_usb_creation.sh`).
    *   Boot into **Windows 10 / 11 ISO**.
    *   Install Windows (Create Offline Account if prompted, or bypass network).

2.  **Run Initial Setup (run_me.bat):**
    *   Once at Desktop, browse the USB drive.
    *   Right-Click `run_me.bat` > **Run as Administrator**.
    *   **What this does:**
        *   Installs OpenSSH Server (Port 65122).
        *   Creates users `ds`, `m1ck5k1`, and `support`.
        *   Enables AutoLogin.
        *   Opens Firewall.

3.  **Network Connection:**
    *   Plug in **Ethernet** (Onboard or USB Adapter).
    *   Identify IP Address (e.g., `192.168.9.41` via USB Adapter).

---

## Phase 2: Remote Provisioning
**Goal:** Deploy software, config, and settings via Linux Control Node.

1.  **Run Provisioning Script:**
    From your control terminal (`~/dev/clonezilla/`):
    ```bash
    ./provision_machine.sh <TARGET_IP> <NEW_HOSTNAME>
    # Example: ./provision_machine.sh 192.168.9.41 John-03
    ```

2.  **Automated Actions (Performed by Script):**
    *   **Connectivity:** Verifies SSH Access.
    *   **File Transfer:** Pushes `incidium-remote-access.msi` and helper scripts.
    *   **Software Install:** 
        *   Chocolatey (Package Manager).
        *   Google Chrome, VLC.
        *   TightVNC (Custom Password/Config).
        *   RustDesk (Custom MSI).
    *   **Debloat:** Removes Windows Bloatware & OneDrive.
    *   **Presentation Mode:** Disables Sleep, Screensaver, Sets High Performance.
    *   **Wi-Fi:** Adds `m1ck5k1` Profile (Auto-Connect).

---

## Phase 3: Application Deployment
**Goal:** Install specialized applications (SnakeSpeare / Argus).

1.  **Transfer SnakeSpeareV6:**
    *   Currently manual or via script if needed.
    *   Destination: `C:\SnakeSpeareV6`

2.  **Configure Startup Tasks (Argus - Hidden):**
    *   **Objective:** Argus must run invisibly (no console window).
    *   **Method:** Use a VBScript wrapper (`launch_argus.vbs`) launched by `wscript.exe`.
    *   **Script:** Run `fix_argus_window.ps1` to deploy:
        1.  Creates `C:\Program Files\Argus\launch_argus.vbs` (which calls `run_argus.cmd` with window style 0).
        2.  Registers Scheduled Task `ArgusAgent` -> `wscript.exe "C:\Program Files\Argus\launch_argus.vbs"`.
        3.  Deletes legacy `run_argus.cmd` from Startup folder.

---

## Phase 4: Network & Finalization
**Goal:** Switch to Onboard NIC and Wireless.

1.  **Onboard NIC Activation:**
    *   If using USB Adapter for setup, the Onboard NIC might default to "Public" network (Blocking SSH).
    *   Run: `Set-NetConnectionProfile -InterfaceAlias 'Ethernet' -NetworkCategory Private` via SSH.
    *   Unplug USB Adapter.
    *   Connect Ethernet to Onboard port.
    *   Find new IP (DHCP).

2.  **Wi-Fi Verification:**
    *   Unplug Ethernet.
    *   Verify connectivity to Wi-Fi IP (e.g., `192.168.9.10x`).

3.  **Final Reboot:**
    *   Ensure AutoLogin works.
    *   Ensure Argus runs (Hidden).
    *   Ensure No Sleep/Screensaver.

---

## Reference Credentials
*   **User:** `ds` | `m1ck5k1` | `support`
*   **Pass:** `547Mark!` | `Kal1L1nux!` | `1nc1d1um2006!`
*   **SSH Port:** `65122`
*   **Wi-Fi:** SSID `m1ck5k1` | Pass `Kal1L1nux!`
