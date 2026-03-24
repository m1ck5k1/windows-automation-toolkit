#!/bin/bash

# --- Configuration ---
PROJECT_ROOT="/home/m1ck5k1/dev/windows-automation-toolkit"
VENTOY_DIR="${PROJECT_ROOT}/tools/ventoy-1.1.10"
VENTOY_INSTALL_SCRIPT="${VENTOY_DIR}/Ventoy2Disk.sh"
MOUNT_POINT="${PROJECT_ROOT}/.gemini/tmp/windows-automation-toolkit/ventoy_mount"
AUTOMATION_KIT_DIR="AutomationKit" # Directory on the USB drive

# --- Functions ---

# Function to check for required tools
check_dependencies() {
    echo "Checking dependencies..."
    REQUIRED_TOOLS="lsblk sudo rsync"
    for tool in $REQUIRED_TOOLS; do
        if ! command -v "$tool" &> /dev/null; then
            echo "Error: Required tool '$tool' is not installed. Please install it and try again."
            exit 1
        fi
    done
    
    # Check for exfatprogs explicitly, as mkexfatfs is part of it
    if ! dpkg -s exfatprogs &> /dev/null; then
        echo "Error: 'exfatprogs' is not installed. Please install it (e.g., 'sudo apt install exfatprogs') and try again."
        exit 1
    fi
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

# --- Main Script ---

# Exit immediately if a command exits with a non-zero status.
set -e

check_dependencies

if [ -z "$1" ]; then
    echo "Usage: $0 /dev/sdX"
    echo "  Where /dev/sdX is your USB drive (e.g., /dev/sdb)."
    exit 1
fi

TARGET_DISK="$1"
TARGET_PARTITION_MAIN="${TARGET_DISK}1"

echo "----------------------------------------------------"
echo "  Ventoy USB Creation Script"
echo "----------------------------------------------------"
echo "WARNING: This script will erase all data on ${TARGET_DISK}."
echo "Please ensure you have selected the correct device."
echo

# List block devices to help user confirm
echo "Current block devices:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "disk|part|${TARGET_DISK##*/}" || true
echo

confirm_action "Do you want to proceed with installing Ventoy to ${TARGET_DISK}? (This will erase all data!)"

# 1. Install Ventoy
echo "Installing Ventoy to ${TARGET_DISK}..."
# IMPORTANT: This step assumes the Ventoy scripts (ventoy_lib.sh and VentoyWorker.sh)
# have been pre-patched as described in the session to fix mkexfatfs and vtoycli issues.
# If using a fresh Ventoy distribution, these patches must be applied first.
sudo "${VENTOY_INSTALL_SCRIPT}" -I -g "${TARGET_DISK}"

echo "Ventoy installation complete."

# 2. Prepare for file copying
echo "Creating mount point: ${MOUNT_POINT}"
mkdir -p "${MOUNT_POINT}"

echo "Mounting ${TARGET_PARTITION_MAIN} to ${MOUNT_POINT}"
sudo mount "${TARGET_PARTITION_MAIN}" "${MOUNT_POINT}"

# 3. Create AutomationKit directory on USB
echo "Creating ${AUTOMATION_KIT_DIR} directory on the USB drive..."
sudo mkdir -p "${MOUNT_POINT}/${AUTOMATION_KIT_DIR}"
echo "Creating ${AUTOMATION_KIT_DIR}/logs directory on the USB drive for persistent logs..."
sudo mkdir -p "${MOUNT_POINT}/${AUTOMATION_KIT_DIR}/logs"

# 4. Copy files to USB
echo "Copying win10_x64.iso..."
sudo cp "${PROJECT_ROOT}/win10_x64.iso" "${MOUNT_POINT}/"

echo "Copying sysprep/unattend.xml to the root of the USB drive..."
sudo cp "${PROJECT_ROOT}/sysprep/unattend.xml" "${MOUNT_POINT}/"

echo "Copying root-level scripts and files to ${AUTOMATION_KIT_DIR}..."
sudo cp "${PROJECT_ROOT}/"*.{sh,ps1,msi,bat,md,py} "${MOUNT_POINT}/${AUTOMATION_KIT_DIR}/"
# Also copy unattend.xml to AutomationKit for C:\AutomationKit\ access later
sudo cp "${PROJECT_ROOT}/sysprep/unattend.xml" "${MOUNT_POINT}/${AUTOMATION_KIT_DIR}/"


echo "Copying SnakeSpeareV6 directory to ${AUTOMATION_KIT_DIR}..."
# Use -rlptD for rsync to avoid chown errors on exFAT (no owner/group preservation)
sudo rsync -rlptD --exclude='_archive/' "${PROJECT_ROOT}/SnakeSpeareV6/" "${MOUNT_POINT}/${AUTOMATION_KIT_DIR}/SnakeSpeareV6/"

echo "Copying scripts/ directory to ${AUTOMATION_KIT_DIR}..."
sudo rsync -rlptD "${PROJECT_ROOT}/scripts/" "${MOUNT_POINT}/${AUTOMATION_KIT_DIR}/scripts/"

echo "Copying sysprep/ directory to ${AUTOMATION_KIT_DIR}..."
sudo rsync -rlptD "${PROJECT_ROOT}/sysprep/" "${MOUNT_POINT}/${AUTOMATION_KIT_DIR}/sysprep/"

echo "Copying docs/ directory to ${AUTOMATION_KIT_DIR}..."
sudo rsync -rlptD "${PROJECT_ROOT}/docs/" "${MOUNT_POINT}/${AUTOMATION_KIT_DIR}/docs/"

echo "All files copied to the USB drive."

# 5. Cleanup
echo "Unmounting ${TARGET_PARTITION_MAIN}"
sudo umount "${MOUNT_POINT}"

echo "Removing temporary mount point: ${MOUNT_POINT}"
rmdir "${MOUNT_POINT}" # Use rmdir for empty dir, -rf for force if needed (not here)

echo "USB drive setup complete for ${TARGET_DISK}."
echo "You can now safely remove the USB drive."
