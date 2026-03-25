#!/bin/bash

# --- Functions ---

# Function to check for required tools
check_dependencies() {
    echo "Checking dependencies..."
    REQUIRED_TOOLS="lsblk sudo rsync mount umount findmnt cp find mkdir fsck.vfat"
    for tool in $REQUIRED_TOOLS; do
        if ! command -v "$tool" &> /dev/null; then
            echo "Error: Required tool '$tool' is not installed. Please install it (e.g., 'sudo apt install $tool' or 'sudo apt install rsync findutils') and try again." >&2
            exit 1
        fi
    done
    echo "All dependencies checked."
}

# --- Main Script ---

# Exit immediately if a command exits with a non-zero status.
set -e



check_dependencies

if [ -z "$5" ]; then
    echo "Usage: $0 PROJECT_ROOT TARGET_DISK EFI_PART_MOUNT_POINT WIN_PART_MOUNT_POINT ISO_MOUNT_POINT"
    echo "  Example: $0 /home/user/project /dev/sdX /mnt/efi /mnt/win /mnt/iso" >&2
    exit 1
fi

PROJECT_ROOT="$1"
TARGET_DISK="$2"
EFI_PART_MOUNT_POINT="$3"
WIN_PART_MOUNT_POINT="$4"
ISO_MOUNT_POINT="$5"

EFI_PARTITION="${TARGET_DISK}1"
WINDOWS_PARTITION="${TARGET_DISK}2" # Assuming 2nd partition for Windows

UNATTEND_XML_SOURCE="${PROJECT_ROOT}/sysprep/unattend.xml"
AUTOMATION_KIT_DIR_SOURCE="${PROJECT_ROOT}/AutomationKit"

# Pre-checks for source files/directories
# ISO is now mounted by orchestrator, so no need to check WINDOWS_ISO_PATH

if [ ! -f "${UNATTEND_XML_SOURCE}" ]; then
    echo "Error: unattend.xml not found at "${UNATTEND_XML_SOURCE}". Please ensure it is restored to the project root before running this script." >&2
    exit 1
fi
if [ ! -d "${AUTOMATION_KIT_DIR_SOURCE}" ]; then
    echo "Error: The "AutomationKit" directory was not found at "${AUTOMATION_KIT_DIR_SOURCE}". Please ensure it is restored to the project root before running this script." >&2
    exit 1
fi

# No need to create mount directories or mount ISO/partitions here, as orchestrator does it.

echo "Dynamically discovering EFI boot files within the ISO..."

# Discover EFI directory (case-insensitive)
EFI_SOURCE_PATH=$(find "${ISO_MOUNT_POINT}" -maxdepth 1 -type d -iname "efi" | head -n 1)
if [ -z "${EFI_SOURCE_PATH}" ]; then
    echo "Error: EFI directory not found in ${ISO_MOUNT_POINT}/. Cannot proceed." >&2
    exit 1
fi
echo "Found EFI directory: ${EFI_SOURCE_PATH}"

# Discover Boot directory (case-insensitive)
BOOT_SOURCE_PATH=$(find "${ISO_MOUNT_POINT}" -maxdepth 1 -type d -iname "boot" | head -n 1)
if [ -z "${BOOT_SOURCE_PATH}" ]; then
    echo "Error: Boot directory not found in ${ISO_MOUNT_POINT}/. Cannot proceed." >&2
    exit 1
fi
echo "Found Boot directory: ${BOOT_SOURCE_PATH}"

# Discover bootmgr file (case-insensitive)
BOOTMGR_FILE_ISO_PATH=$(find "${ISO_MOUNT_POINT}" -maxdepth 1 -type f -iname "bootmgr" | head -n 1)
if [ -z "${BOOTMGR_FILE_ISO_PATH}" ]; then
    echo "Error: bootmgr file not found in ${ISO_MOUNT_POINT}/. Cannot proceed." >&2
    exit 1
fi
echo "Found bootmgr file: ${BOOTMGR_FILE_ISO_PATH}"

# Discover bootmgfw.efi and bootx64.efi (case-insensitive) for primary UEFI bootloader
BOOTMGFW_EFI_SOURCE_PATH=$(find "${EFI_SOURCE_PATH}" -type f -iname "bootmgfw.efi" | head -n 1 || true)
BOOTX64_EFI_SOURCE_PATH=$(find "${EFI_SOURCE_PATH}" -type f -iname "bootx64.efi" | head -n 1 || true)

# Final check for at least one critical EFI bootloader path
if [ -z "${BOOTMGFW_EFI_SOURCE_PATH}" ] && [ -z "${BOOTX64_EFI_SOURCE_PATH}" ]; then
    echo "Error: Neither bootmgfw.efi nor bootx64.efi found in common EFI paths within ISO. UEFI boot might fail." >&2
    exit 1
fi

echo "Copying Windows installation files to USB..."

# --- Step 5.1: Copy ALL files from mounted ISO to the main Windows partition (NTFS) ---
echo "Copying ALL ISO contents to WIN10_INSTALL partition (${WINDOWS_PARTITION})... (This includes install.wim)"
sudo rsync -a --info=progress2 "${ISO_MOUNT_POINT}/" "${WIN_PART_MOUNT_POINT}/"

# --- Step 5.2: Copy ONLY essential EFI boot files from ISO to the EFI partition (FAT32) ---
echo "Copying essential EFI boot files to BOOT_EFI partition (${EFI_PARTITION})..."

# Copy EFI directory content (EFI/boot, EFI/microsoft/boot etc.)
sudo rsync -rlptD --info=progress2 "${EFI_SOURCE_PATH}/" "${EFI_PART_MOUNT_POINT}/efi/"

# Copy the /boot directory content (e.g., BCD, boot.sdi, etc.)
sudo rsync -rlptD --info=progress2 "${BOOT_SOURCE_PATH}/" "${EFI_PART_MOUNT_POINT}/boot/"

# Copy bootmgr from ISO root to EFI partition root
sudo rsync -rlptD --info=progress2 "${BOOTMGR_FILE_ISO_PATH}" "${EFI_PART_MOUNT_POINT}/"

# Ensure EFI/Boot/bootx64.efi is correctly established as the primary UEFI bootloader.
# If bootmgfw.efi is found, copy it to bootx64.efi. Otherwise, use bootx64.efi from ISO/efi/boot.
BOOTX64_EFI_DEST_PATH="${EFI_PART_MOUNT_POINT}/efi/Boot/bootx64.efi"
sudo mkdir -p "$(dirname "${BOOTX64_EFI_DEST_PATH}")"

if [ -n "${BOOTMGFW_EFI_SOURCE_PATH}" ]; then
    echo "Copying bootmgfw.efi from ISO to create bootx64.efi..."
    sudo rsync -rlptD --info=progress2 "${BOOTMGFW_EFI_SOURCE_PATH}" "${BOOTX64_EFI_DEST_PATH}"
elif [ -n "${BOOTX64_EFI_SOURCE_PATH}" ]; then
    echo "Copying bootx64.efi from ISO..."
    sudo rsync -rlptD --info=progress2 "${BOOTX64_EFI_SOURCE_PATH}" "${BOOTX64_EFI_DEST_PATH}"
else
    echo "Error: Neither bootmgfw.efi nor bootx64.efi could be found in ISO to create primary UEFI bootloader. Cannot proceed." >&2
    exit 1
fi


# --- Step 6: Copy unattend.xml and AutomationKit ---

# Copy unattend.xml
# The pre-check for UNATTEND_XML_SOURCE is done at the beginning of the script
echo "Copying unattend.xml to Windows partition..."
sudo cp "${UNATTEND_XML_SOURCE}" "${WIN_PART_MOUNT_POINT}/autounattend.xml"

# Copy scripts/ folder
echo "Copying scripts/ folder to Windows partition..."
sudo rsync -a --info=progress2 "${PROJECT_ROOT}/scripts/" "${WIN_PART_MOUNT_POINT}/Scripts/"
if [ $? -ne 0 ]; then
    echo "Error: rsync failed to copy scripts/ to ${WIN_PART_MOUNT_POINT}/Scripts/." >&2
    exit 1
fi

echo "Copying AutomationKit (excluding SnakeSpeareV6) to Windows partition..."
sudo mkdir -p "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR_SOURCE##*/}"
sudo rsync -a --info=progress2 "${AUTOMATION_KIT_DIR_SOURCE}/" "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR_SOURCE##*/}/" --exclude='SnakeSpeareV6/'
if [ $? -ne 0 ]; then
    echo "Error: rsync failed to copy AutomationKit to ${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR_SOURCE##*/}/." >&2
    exit 1
fi

echo "Copying SnakeSpeareV6 self-extracting installer to Windows partition..."
SFX_INSTALLER_PATH="${PROJECT_ROOT}/.gemini/tmp/sfx_build/SnakeSpeareV6_Installer.exe"
if [ ! -f "${SFX_INSTALLER_PATH}" ]; then
    echo "Error: SnakeSpeareV6 SFX installer not found at ${SFX_INSTALLER_PATH}. Please ensure it is created before running this script." >&2
    exit 1
fi
sudo cp "${SFX_INSTALLER_PATH}" "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR_SOURCE##*/}/SnakeSpeareV6_Installer.exe"
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy SnakeSpeareV6 SFX installer to USB." >&2
    exit 1
fi

echo "Warning: The original SnakeSpeareV6 directory was installed via SFX installer. Ensure it is executed on Windows." >&2

echo "Successfully created Windows 10 UEFI bootable USB on ${TARGET_DISK}!"
echo "Please safely eject the USB drive."

