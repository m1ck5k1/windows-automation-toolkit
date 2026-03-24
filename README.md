# Windows Automation Toolkit

This project provides a comprehensive toolkit for automating the deployment and initial configuration of Windows 10 machines. It includes scripts for preparing bootable USB drives and an `unattend.xml` file to automate the Windows installation process, along with post-installation scripts for further customization.

## Table of Contents
1. [Project Setup](#1-project-setup)
2. [Folder Structure](#2-folder-structure)
3. [Cross-Platform Considerations](#3-cross-platform-considerations)
4. [USB Drive Creation](#4-usb-drive-creation)
    *   [4.1. Ventoy USB Creation](#41-ventoy-usb-creation)
    *   [4.2. Non-Ventoy Windows 10 USB Creation (for `unattend.xml` debugging)](#42-non-ventoy-windows-10-usb-creation-for-unattendxml-debugging)
5. [Windows 10 Installation Automation (unattend.xml)](#5-windows-10-installation-automation-unattendxml)
6. [Post-Installation Scripts](#6-post-installation-scripts)
7. [Usage Guide](#7-usage-guide)

---

## 1. Project Setup

**Project Name:** `windows-automation-toolkit`
**Location:** `/home/m1ck5k1/dev/windows-automation-toolkit`

The project uses Git for version control.

### Git Repository Initialization
The repository has been initialized, and a `.gitignore` file has been created to exclude large binaries, ISOs, and other non-source files.

---

## 2. Folder Structure

This project is organized to separate platform-specific scripts and tools, enhancing clarity and maintainability, especially for users on different operating systems.

```
/windows-automation-toolkit/
├── .env                      # Environment variables
├── .gitignore                # Files/directories ignored by Git
├── README.md                 # Project documentation (this file)
├── SOP.md                    # Standard Operating Procedures
├── win10_x64.iso             # Windows 10 installation ISO
├── docs/                     # General project documentation
├── drivers/                  # OEM-specific driver packages for Windows setup
│   ├── Dell/                 # Dell drivers
│   ├── HPE/                  # HPE drivers
│   └── Lenovo/               # Lenovo drivers
├── logs/                     # Runtime logs
├── scripts/
│   ├── common/               # Scripts/tools usable across platforms (e.g., Python scripts)
│   │   ├── update_credentials.py
│   │   └── update_prov.py
│   ├── linux/                # Scripts designed for Linux hosts (e.g., USB creation)
│   │   ├── build_usb.sh      # Unified entry for Linux USB creation (Ventoy/Non-Ventoy)
│   │   ├── create_ventoy_usb.sh
│   │   ├── create_non_ventoy_usb.sh
│   │   ├── copy_files_to_usb.sh
│   │   ├── create_win11_usb.sh
│   │   ├── provision_machine.sh
│   │   └── setup_gh_auth.sh
│   ├── windows/              # Scripts designed for Windows targets or Windows hosts (PowerShell, Batch)
│   │   ├── setupcomplete.cmd
│   │   ├── post-os-install.ps1
│   │   ├── fix_minimized.ps1
│   │   ├── run_me.bat
│   │   ├── setup_argus_hidden.ps1
│   │   ├── setup_startup_minimized.ps1
│   │   ├── setup_startup_task.ps1
│   │   └── setup_repo.sh     # (Note: This is a shell script, consider PowerShell equivalent for Windows hosts)
│   └── _archive/             # Historical or deprecated scripts
├── SnakeSpeareV6/            # Application files to be deployed
├── sysprep/
│   └── unattend.xml          # Windows Unattended installation answer file
└── tools/                    # Third-party tools and binaries
    ├── ventoy-1.1.10/        # Linux Ventoy binaries and scripts
    ├── ventoy-windows/       # Placeholder for Ventoy Windows GUI/CLI
    └── incidium-remote-access.msi # MSI installer for remote access
```

---

## 3. Cross-Platform Considerations

This toolkit is primarily developed on Linux, but efforts have been made to support deployment *to* Windows. For users intending to *build and run* the USB creation process from a Windows host, consider the following:

*   **Shell Scripts (`.sh`):** Linux-specific shell scripts located in `scripts/linux/` will require a Linux environment (e.g., [Windows Subsystem for Linux (WSL)](https://docs.microsoft.com/en-us/windows/wsl/install) or [Git Bash](https://git-scm.com/downloads)) to execute.
*   **Linux Disk Tools:** Tools like `parted`, `mkfs.ntfs`, `lsblk` used in `scripts/linux/` have no direct native Windows equivalents. Creating bootable USBs on Windows typically involves `DiskPart` or PowerShell cmdlets.
*   **PowerShell (`.ps1`) and Batch (`.bat`) Scripts:** Scripts in `scripts/windows/` are designed for native execution on Windows systems.
*   **Path Separators:** Be mindful of path separators (`/` on Linux, `` on Windows) when writing or adapting scripts for cross-platform use.

To fully support Windows users for USB creation, new PowerShell scripts (`scripts/windows/build_usb.ps1`) would be needed to replicate the functionality of `scripts/linux/create_ventoy_usb.sh` and `create_non_ventoy_usb.sh` using native Windows tools.

---

## 4. USB Drive Creation

This section details the methods for preparing bootable Windows 10 USB drives.

### Requirements
*   A USB drive (58.6GB or larger recommended, identical size/make for batch processing).
*   **For Linux hosts:** `lsblk`, `sudo`, `rsync`, `parted`, `mkfs.ntfs` (from `ntfs-3g` package), and `exfatprogs` installed.

### 4.1. Ventoy USB Creation

This method uses Ventoy to create a multi-boot USB drive, allowing you to place multiple ISOs on a single drive without re-flashing.

**Location:** `scripts/linux/create_ventoy_usb.sh`

**Usage:**
1.  **Make the script executable:**
    ```bash
    chmod +x /home/m1ck5k1/dev/windows-automation-toolkit/scripts/linux/create_ventoy_usb.sh
    ```
2.  **Run the script:**
    ```
    sudo /home/m1ck5k1/dev/windows-automation-toolkit/scripts/linux/create_ventoy_usb.sh /dev/sdX
    ```
    Replace `/dev/sdX` with the actual device path of your USB drive (e.g., `/dev/sdb`, `/dev/sdc`). The script includes a confirmation prompt to prevent accidental data loss. This script copies `unattend.xml` to **both the root of the Ventoy partition and inside the `AutomationKit` directory** for seamless Windows Setup integration and post-installation script access.

**Ventoy Script Patches:**
During the development of this toolkit, specific modifications were made to the bundled Ventoy scripts (`tools/ventoy-1.1.10/tool/ventoy_lib.sh` and `tools/ventoy-1.1.10/tool/VentoyWorker.sh`) to resolve compatibility issues with `mkexfatfs` and `vtoycli` commands. These patches are now integrated into the `tools/ventoy-1.1.10` directory within this project and are crucial for the `scripts/linux/create_ventoy_usb.sh` script to function correctly.

### 4.2. Non-Ventoy Windows 10 USB Creation (for `unattend.xml` debugging)

This method creates a standard bootable Windows 10 USB drive by directly copying the ISO contents. This is generally more reliable for `unattend.xml` detection and is recommended for debugging `unattend.xml` issues, but it does **not** offer multi-ISO boot capabilities.

**Location:** `scripts/linux/create_non_ventoy_usb.sh`

**Usage:**
1.  **Make the script executable:**
    ```bash
    chmod +x /home/m1ck5k1/dev/windows-automation-toolkit/scripts/linux/create_non_ventoy_usb.sh
    ```
2.  **Run the script:**
    ```
    sudo /home/m1ck5k1/dev/windows-automation-toolkit/scripts/linux/create_non_ventoy_usb.sh /dev/sdX
    ```
    Replace `/dev/sdX` with the actual device path of your USB drive (e.g., `/dev/sdb`, `/dev/sdc`). The script includes a confirmation prompt to prevent accidental data loss. This script copies the `win10_x64.iso` contents and `unattend.xml` directly to the root of the USB drive.

---

## 5. Windows 10 Installation Automation (unattend.xml)

The `sysprep/unattend.xml` file has been configured to automate key aspects of the Windows 10 installation:

*   **Language Selection:** Set to `en-US`.
*   **Custom: Delete all existing partitions:** The `windowsPE` pass is configured to automatically wipe the target disk and create a new primary partition, then format it.
*   **Local Account Setup:** A local administrator account is created with the following credentials:
    *   **Username:** `incidium`
    *   **Password:** `547Mark!`
*   **Computer Name Customization:** The computer name will be dynamically set to `DS-{PC-Serial-Number}`.
*   **Time Zone:** Set to `Eastern Standard Time`.
*   **Workgroup Join:** Machines will automatically join the `INCIDIUM` workgroup.

---

## 6. Post-Installation Scripts

### `scripts/windows/setupcomplete.cmd`
This batch script is executed early in the Windows setup process to perform critical post-installation tasks:

*   **Copy Automation Kit:** The entire `AutomationKit` folder (containing all scripts and files copied from the USB) is copied from the USB drive to `C:\AutomationKit` on the target Windows system. This ensures all necessary post-installation resources are available.
*   **Dynamic Computer Naming:** Retrieves the PC's serial number and sets the computer name to `DS-{Serial-Number}` (overriding `unattend.xml`'s `ComputerName` if `*` is used).
*   **Driver Injection:** Includes logic to detect the manufacturer and inject drivers from `C:\DRIVERS`.
*   **Persistent Logging:** All output from this script is logged to `C:\AutomationKit\logs\setupcomplete.log`. At the end of the script, this log file is copied back to the USB drive under `AutomationKit\logs\` with a timestamped filename (e.g., `setupcomplete_YYYYMMDD_HHMMSS.log`).

### `scripts/windows/post-os-install.ps1`
This PowerShell script is executed via `FirstLogonCommands` in `unattend.xml` after the initial Windows setup and first logon (with PowerShell's execution policy bypassed). It's intended for further system configuration and software installation, leveraging the files copied to `C:\AutomationKit`.

*   **Persistent Logging:** All console output from this PowerShell script is captured to a timestamped log file in `C:\AutomationKit\logs\` (e.g., `post-os-install_YYYYMMDD_HHMMSS.log`). After script execution, this log is copied back to the USB drive under `AutomationKit\logs/`.

---

## 7. Usage Guide

To use this toolkit for automated Windows 10 deployment:

1.  **Prepare a Bootable USB Drive:**
    *   Plug in a blank USB drive to your Linux machine.
    *   Identify its device path (e.g., `/dev/sdb`) using `lsblk`.
    *   Choose your desired method and run the corresponding script:
        *   For Ventoy: `sudo scripts/linux/create_ventoy_usb.sh /dev/sdX`
        *   For Non-Ventoy: `sudo scripts/linux/create_non_ventoy_usb.sh /dev/sdX`
    *   Repeat for all desired USB drives.
2.  **Add Drivers (Recommended):**
    *   Place specific drivers for your target hardware into the `drivers/` directory, organized by manufacturer (e.g., `drivers/Lenovo/`).
    *   Ensure your chosen USB creation script (e.g., `scripts/linux/create_non_ventoy_usb.sh`) is updated to copy these `drivers/` folders into the `AutomationKit` on the USB (if not already implemented).
    *   The `scripts/windows/setupcomplete.cmd` expects drivers to be available at `C:\DRIVERS\ManufacturerName`.
3.  **Boot Target Machine from USB:**
    *   Insert the prepared USB drive into the target Windows machine.
    *   Boot the machine from the USB drive (select the Windows ISO from the Ventoy menu if using a Ventoy USB).
4.  **Initiate Windows 10 Installation:**
    *   The `unattend.xml` file (if correctly detected) will automate the installation, including disk partitioning, language selection, and user creation.
5.  **Post-OS Configuration:**
    *   `scripts/windows/setupcomplete.cmd` will run automatically during Windows setup to copy the `AutomationKit` and set the computer name.
    *   Upon first logon, `scripts/windows/post-os-install.ps1` will execute to perform further automated configurations.

---
