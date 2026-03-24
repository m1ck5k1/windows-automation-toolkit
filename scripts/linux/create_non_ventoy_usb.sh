#!/bin/bash

# --- Configuration ---
PROJECT_ROOT="/home/m1ck5k1/dev/windows-automation-toolkit"
WINDOWS_ISO="${PROJECT_ROOT}/win10_x64.iso"
UNATTEND_XML_SOURCE="${PROJECT_ROOT}/sysprep/unattend.xml"
# New mount points for the two partitions
EFI_PART_MOUNT_POINT="${PROJECT_ROOT}/.gemini/tmp/windows-automation-toolkit/efi_mount"
WIN_PART_MOUNT_POINT="${PROJECT_ROOT}/.gemini/tmp/windows-automation-toolkit/win_mount"
ISO_MOUNT_POINT="${PROJECT_ROOT}/.gemini/tmp/windows-automation-toolkit/iso_mount"
AUTOMATION_KIT_DIR="AutomationKit" # Directory on the USB drive

# --- Functions ---

# Function to check for required tools
check_dependencies() {
    echo "Checking dependencies..."
    REQUIRED_TOOLS="lsblk sudo rsync parted mkfs.ntfs mkfs.fat partprobe findmnt" # Added findmnt
    for tool in $REQUIRED_TOOLS; do
        if ! command -v "$tool" &> /dev/null; then
            echo "Error: Required tool '$tool' is not installed. Please install it (e.g., 'sudo apt install $tool' or 'sudo apt install ntfs-3g dosfstools parted util-linux' for mkfs.ntfs/mkfs.fat/parted/findmnt) and try again."
            exit 1
        fi
    done
    echo "All dependencies checked."
}

# Function to get user confirmation
confirm_action() {
    read -p "$1 (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled by user."
        exit 1
    fi
}

# Function to cleanup mount points and temporary directories
cleanup_mounts() {
    echo "Performing cleanup..."
    if mountpoint -q "${EFI_PART_MOUNT_POINT}"; then
        echo "Unmounting EFI partition..."
        sudo umount -l "${EFI_PART_MOUNT_POINT}" || echo "Warning: Could not unmount ${EFI_PART_MOUNT_POINT}"
    fi
    if mountpoint -q "${WIN_PART_MOUNT_POINT}"; then
        echo "Unmounting Windows partition..."
        sudo umount -l "${WIN_PART_MOUNT_POINT}" || echo "Warning: Could not unmount ${WIN_PART_MOUNT_POINT}"
    fi
    if mountpoint -q "${ISO_MOUNT_POINT}"; then
        echo "Unmounting Windows ISO..."
        sudo umount -l "${ISO_MOUNT_POINT}" || echo "Warning: Could not unmount ${ISO_MOUNT_POINT}"
    fi

    rmdir "${EFI_PART_MOUNT_POINT}" 2>/dev/null || true
    rmdir "${WIN_PART_MOUNT_POINT}" 2>/dev/null || true
    rmdir "${ISO_MOUNT_POINT}" 2>/dev/null || true
}

# --- Main Script ---

# Exit immediately if a command exits with a non-zero status.
set -e

# Trap to ensure cleanup on exit or error
trap cleanup_mounts EXIT

check_dependencies

if [ -z "$1" ]; then
    echo "Usage: $0 /dev/sdX"
    echo "  Where /dev/sdX is your USB drive (e.g., /dev/sdb)."
    exit 1
fi

TARGET_DISK="$1"
EFI_PARTITION="${TARGET_DISK}1"
WINDOWS_PARTITION="${TARGET_DISK}2" # Assuming 2nd partition for Windows

echo "----------------------------------------------------"
echo "  Non-Ventoy Windows 10 USB Creation Script"
echo "----------------------------------------------------"
echo "WARNING: This script will erase all data on ${TARGET_DISK}."
echo "Please ensure you have selected the correct device."
echo

# List block devices to help user confirm
echo "Current block devices:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "disk|part|${TARGET_DISK##*/}" || true
echo

#confirm_action "Do you want to proceed with creating a non-Ventoy Windows 10 bootable USB on ${TARGET_DISK}? (This will erase all data!)
#NOTE: This will create two partitions: a small FAT32 EFI partition and a large NTFS Windows partition."

# 1. Unmount any existing partitions or loop devices associated with the target disk
echo "Searching for and unmounting any existing partitions or loop devices on ${TARGET_DISK}..."
# Find all mount points related to the target disk's partitions
MOUNTED_PARTS=$(findmnt -n -l -o TARGET,SOURCE -S "${TARGET_DISK}" | awk '{print $1}')

if [ -n "${MOUNTED_PARTS}" ]; then
    echo "Found mounted partitions for ${TARGET_DISK}:"
    echo "${MOUNTED_PARTS}"
    for mount_point in ${MOUNTED_PARTS}; do
        echo "Attempting to unmount ${mount_point}..."
        sudo umount -l "${mount_point}" # Use lazy unmount
        if [ $? -ne 0 ]; then
            echo "Error: Failed to unmount ${mount_point}. Please ensure no files are open on the device and try again."
            exit 1
        fi
    done
else
    echo "No mounted partitions found for ${TARGET_DISK}."
fi

# Also check if the ISO itself is mounted as a loop device elsewhere and unmount it
if findmnt -n -S "${WINDOWS_ISO}" > /dev/null; then
    echo "Windows ISO (${WINDOWS_ISO}) is currently mounted as a loop device."
    ISO_CURRENT_MOUNT=$(findmnt -n -S "${WINDOWS_ISO}" -o TARGET)
    echo "Unmounting ISO from ${ISO_CURRENT_MOUNT}..."
    sudo umount -l "${ISO_CURRENT_MOUNT}"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to unmount ISO from ${ISO_CURRENT_MOUNT}. Please unmount manually and try again."
        exit 1
    fi
else
    echo "Windows ISO is not currently mounted."
fi


# 2. Partition and format the USB drive for UEFI boot
echo "Partitioning and formatting ${TARGET_DISK} for UEFI boot (FAT32 EFI + NTFS Windows partitions)..."
# Clear existing partition table
sudo parted -s "${TARGET_DISK}" mklabel gpt
# Create EFI System Partition (FAT32, 500MB)
sudo parted -s "${TARGET_DISK}" mkpart primary fat32 1MB 501MB
sudo parted -s "${TARGET_DISK}" set 1 boot on
sudo parted -s "${TARGET_DISK}" set 1 esp on
# Create Windows Data Partition (NTFS, rest of disk)
sudo parted -s "${TARGET_DISK}" mkpart primary ntfs 501MB 100%

sudo parted -s "${TARGET_DISK}" set 2 msftdata on

# Inform kernel about new partitions
echo "Informing kernel about new partitions on ${TARGET_DISK}..."
sudo partprobe "${TARGET_DISK}"
sleep 5 # Give kernel time to create device nodes

echo "Formatting partitions..."
sudo mkfs.fat -F 32 -n EFI_SYSTEM "${EFI_PARTITION}"
sudo mkfs.ntfs -f -L "WIN10_INSTALL" "${WINDOWS_PARTITION}"


# 3. Create mount points
echo "Creating mount points: ${EFI_PART_MOUNT_POINT}, ${WIN_PART_MOUNT_POINT}, and ${ISO_MOUNT_POINT}"
mkdir -p "${EFI_PART_MOUNT_POINT}"
mkdir -p "${WIN_PART_MOUNT_POINT}"
mkdir -p "${ISO_MOUNT_POINT}"

# 4. Mount partitions and ISO
echo "Mounting ${EFI_PARTITION} to ${EFI_PART_MOUNT_POINT}..."
sudo mount "${EFI_PARTITION}" "${EFI_PART_MOUNT_POINT}"

echo "Mounting ${WINDOWS_PARTITION} to ${WIN_PART_MOUNT_POINT}..."
sudo mount "${WINDOWS_PARTITION}" "${WIN_PART_MOUNT_POINT}"

echo "Mounting Windows ISO: ${WINDOWS_ISO} to ${ISO_MOUNT_POINT}..."
sudo mount -o loop "${WINDOWS_ISO}" "${ISO_MOUNT_POINT}"

# 5. Copy ISO contents to USB partitions
echo "Copying Windows ISO contents to USB partitions..."

# --- Step 5.1: Copy all files from ISO to the main Windows partition (NTFS) ---
echo "Copying all files from ISO to Windows partition (${WINDOWS_PARTITION})..."
sudo rsync -rlptD --info=progress2 "${ISO_MOUNT_POINT}/" "${WIN_PART_MOUNT_POINT}/"

# --- Step 5.2: Ensure EFI boot files are on the EFI partition (FAT32) ---
# The Windows ISO's EFI directory contains the necessary boot files.
# We need to copy these from the ISO (or where rsync put them on NTFS) to the FAT32 EFI partition.
echo "Copying EFI boot files from ISO's EFI directory to EFI partition (${EFI_PARTITION})..."
# Ensure the target EFI directory exists on the FAT32 partition
sudo mkdir -p "${EFI_PART_MOUNT_POINT}/EFI/Boot"
# Copy the boot files from the ISO's EFI directory to the EFI partition
sudo rsync -rlptD "${ISO_MOUNT_POINT}/efi/" "${EFI_PART_MOUNT_POINT}/EFI/"
# Rename the bootloader for generic UEFI (if not already bootx64.efi)
if [ -f "${EFI_PART_MOUNT_POINT}/EFI/BOOT/bootx64.efi" ]; then
    echo "bootx64.efi already present on EFI partition."
elif [ -f "${EFI_PART_MOUNT_POINT}/EFI/Microsoft/Boot/bootx64.efi" ]; then
    echo "Copying Microsoft EFI bootloader to generic path..."
    sudo mkdir -p "${EFI_PART_MOUNT_POINT}/EFI/BOOT"
    sudo cp "${EFI_PART_MOUNT_POINT}/EFI/Microsoft/Boot/bootx64.efi" "${EFI_PART_MOUNT_POINT}/EFI/BOOT/bootx64.efi"
else
    echo "Warning: No standard bootx64.efi found in EFI partition after copy. UEFI boot may fail."
fi


# 6. Copy unattend.xml to USB root (Windows Partition root)
echo "Copying unattend.xml to the root of the Windows partition (${WINDOWS_PARTITION})..."
sudo cp "${UNATTEND_XML_SOURCE}" "${WIN_PART_MOUNT_POINT}/"

# 7. Create AutomationKit directory on USB and copy contents
echo "Creating ${AUTOMATION_KIT_DIR} directory on the Windows partition and copy contents..."
sudo mkdir -p "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}"
echo "Creating ${AUTOMATION_KIT_DIR}/logs directory on the USB drive for persistent logs..."
sudo mkdir -p "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/logs"


echo "Creating ${AUTOMATION_KIT_DIR}/scripts/common directory..."
sudo mkdir -p "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/scripts/common"
echo "Creating ${AUTOMATION_KIT_DIR}/scripts/windows directory..."
sudo mkdir -p "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/scripts/windows"
echo "Creating ${AUTOMATION_KIT_DIR}/SnakeSpeareV6 directory..."
sudo mkdir -p "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/SnakeSpeareV6"
echo "Creating ${AUTOMATION_KIT_DIR}/sysprep directory..."
sudo mkdir -p "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/sysprep"
echo "Creating ${AUTOMATION_KIT_DIR}/docs directory..."
sudo mkdir -p "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/docs"
echo "Creating ${AUTOMATION_KIT_DIR}/tools directory..."
sudo mkdir -p "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/tools"
echo "Creating ${AUTOMATION_KIT_DIR}/DRIVERS directory..."
sudo mkdir -p "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/DRIVERS"

echo "Copying project AutomationKit files to ${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/..."
# Copy Python scripts (common)
sudo rsync -rlptD "${PROJECT_ROOT}/scripts/common/" "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/scripts/common/"
# Copy Windows-specific scripts
sudo rsync -rlptD "${PROJECT_ROOT}/scripts/windows/" "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/scripts/windows/"
# Copy SnakeSpeareV6 directory (excluding _archive)
sudo rsync -rlptD --exclude='_archive/' "${PROJECT_ROOT}/SnakeSpeareV6/" "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/SnakeSpeareV6/"
# Copy sysprep/ directory (excluding unattend.xml as it's already copied to root and we don't want a duplicate) but we will need the full sysprep folder with unattend.xml to be copied. The original setupcomplete cmd also copies the sysprep folder to C:\AutomationKit\sysprep
sudo rsync -rlptD --exclude='unattend.xml' "${PROJECT_ROOT}/sysprep/" "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/sysprep/"
# Copy docs/ directory
sudo rsync -rlptD "${PROJECT_ROOT}/docs/" "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/docs/"
# Copy tools that might be needed on Windows (e.g., .msi)
sudo rsync -rlptD "${PROJECT_ROOT}/tools/incidium-remote-access.msi" "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/tools/"
# Copy the drivers directory structure
sudo rsync -rlptD "${PROJECT_ROOT}/drivers/" "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/DRIVERS/" # Copy to DRIVERS as expected by setupcomplete.cmd


echo "All necessary files copied to the USB drive."

echo "Non-Ventoy USB drive setup complete for ${TARGET_DISK}. The USB is now UEFI bootable."
echo "You can now safely remove the USB drive."
