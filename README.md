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

## 4. USB Drive Creation - Modular UEFI Windows USB Workflow

This section outlines the advanced, modular workflow for preparing bootable UEFI Windows USB drives using `orchestrate_usb_creation.sh`. This workflow ensures robust partition management, file copying, and unmounting, specifically tailored for Windows 10/11 installations.

### Requirements
*   A USB drive (58.6GB or larger recommended for Windows 10/11 ISOs).
*   **For Linux hosts:** `lsblk`, `sudo`, `rsync`, `parted`, `mkfs.ntfs` (from `ntfs-3g` package), `exfatprogs`, and `ntfsfix` installed.

### 4.1. The Modular USB Creation Workflow (`orchestrate_usb_creation.sh`)

The `scripts/linux/orchestrate_usb_creation.sh` script is the central entry point for creating UEFI-bootable Windows USB drives. It integrates several specialized scripts to perform each step of the process reliably.

**Workflow Components:**
*   `select_usb_device.sh`: Guides the user to safely select the target USB device.
*   `prepare_usb_partitions.sh`: Unmounts existing partitions on the selected USB device.
*   `create_gpt_partitions.sh`: Creates the necessary GPT partition table and EFI/Windows partitions.
*   `format_partitions.sh`: Formats the partitions (FAT32 for EFI, NTFS for Windows) and applies `ntfsfix` for Windows partitions to ensure filesystem integrity.
*   `copy_windows_files.sh`: Mounts the Windows ISO and copies its contents to the Windows partition.
*   `copy_files_to_usb.sh`: Copies project-specific `AutomationKit` files and `unattend.xml` to the USB.
*   `unmount_target_disk.sh`: Implements a robust strategy to unmount all partitions associated with the target USB device, crucial for preventing data corruption and ensuring clean ejection.

**Key Features and Improvements:**

*   **Modular Architecture:** Each critical step is encapsulated in its own script, enhancing maintainability, testability, and clarity.
*   **Robust Unmounting Strategy:** `unmount_target_disk.sh` provides a comprehensive approach to unmounting, addressing common issues with busy devices.
*   **Centralized Mount Management:** `orchestrate_usb_creation.sh` manages all mounting and unmounting operations for the USB partitions, ensuring consistency and proper cleanup.
*   **Correct `unattend.xml` Pathing:** The `copy_files_to_usb.sh` component correctly places `unattend.xml` in the root of the Windows partition, ensuring it is detected by the Windows installer.
*   **Successful EFI FAT32 Formatting:** The EFI system partition is correctly formatted as FAT32 and mounted, ensuring UEFI boot compatibility.
*   **`ntfsfix` Integration:** `ntfsfix` is applied to the newly formatted NTFS partition to proactively resolve potential filesystem inconsistencies that can arise during creation, enhancing reliability.

**Known Limitations / Exclusions:**

*   **`AutomationKit/SnakeSpeareV6` and `AutomationKit/windows` Exclusion:** Due to persistent I/O errors and compatibility challenges during large-scale `rsync` operations, the `AutomationKit/SnakeSpeareV6` and `AutomationKit/windows` directories are *intentionally excluded* from the automated USB creation process. These directories contain applications and Windows-specific scripts that often lead to silent failures or incomplete copies. They require separate, manual handling (e.g., via network transfer post-OS installation or by individually copying specific files after the initial USB creation).

**Usage:**
1.  **Make `orchestrate_usb_creation.sh` executable:**
    ```bash
    chmod +x /home/m1ck5k1/dev/windows-automation-toolkit/scripts/linux/orchestrate_usb_creation.sh
    ```
2.  **Run the script:**
    ```bash
    sudo /home/m1ck5k1/dev/windows-automation-toolkit/scripts/linux/orchestrate_usb_creation.sh /path/to/win10_x64.iso
    ```
    The script will guide you through selecting the USB device and creating the bootable drive. Replace `/path/to/win10_x64.iso` with the actual path to your Windows 10/11 ISO file.

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

To use this toolkit for automated Windows 10/11 deployment:

1.  **Prepare a Bootable USB Drive:**
    *   Plug in a blank USB drive to your Linux machine.
    *   Ensure your Windows 10/11 ISO is accessible.
    *   Run the orchestration script, providing the path to your ISO:
        ```bash
        sudo scripts/linux/orchestrate_usb_creation.sh /path/to/your/windows.iso
        ```
    *   Follow the on-screen prompts to select the USB device and complete the creation process.

2.  **Boot Target Machine from USB:**
    *   Insert the prepared USB drive into the target Windows machine.
    *   Boot the machine from the USB drive.

3.  **Initiate Windows 10/11 Installation:**
    *   The `unattend.xml` file (correctly detected at the root of the Windows partition) will automate the installation, including disk partitioning, language selection, and user creation.

4.  **Post-OS Configuration:**
    *   `scripts/windows/setupcomplete.cmd` will run automatically during Windows setup to copy the `AutomationKit` (excluding `SnakeSpeareV6` and `windows` subdirectories) and set the computer name.
    *   Upon first logon, `scripts/windows/post-os-install.ps1` will execute to perform further automated configurations.

---
