#!/bin/bash

# --- Configuration ---
PROJECT_ROOT="/home/m1ck5k1/dev/windows-automation-toolkit"
EFI_PART_MOUNT_POINT=""
WIN_PART_MOUNT_POINT=""
ISO_MOUNT_POINT=""

# --- Functions ---

# Function to check for required tools
check_dependencies() {
    echo "Checking dependencies..."
    REQUIRED_TOOLS="lsblk sudo parted mkfs.ntfs mkfs.fat grep awk mount umount readlink basename dirname head tail wc test findmnt blockdev"
    for tool in $REQUIRED_TOOLS; do
        if ! command -v "$tool" &> /dev/null; then
            echo "Error: Required tool '$tool' is not installed. Please install it (e.g., 'sudo apt install $tool' or 'sudo apt install ntfs-3g dosfstools parted util-linux') and try again." >&2
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

# Function to cleanup mount points (for safety, though this script should be run in a clean state)
cleanup_mounts_safe() {
    echo "Performing safe cleanup..."
    # Only unmount if actually mounted by this script or explicitly known to be temporary
    if [ -n "${EFI_PART_MOUNT_POINT}" ] && grep -qs "${EFI_PART_MOUNT_POINT}" /proc/mounts; then
        echo "Unmounting EFI partition..."
        sudo umount -f -l "${EFI_PART_MOUNT_POINT}" || true
    fi
    if [ -n "${WIN_PART_MOUNT_POINT}" ] && grep -qs "${WIN_PART_MOUNT_POINT}" /proc/mounts; then
        echo "Unmounting Windows partition..."
        sudo umount -f -l "${WIN_PART_MOUNT_POINT}" || true
    fi
    if [ -n "${ISO_MOUNT_POINT}" ] && grep -qs "${ISO_MOUNT_POINT}" /proc/mounts; then
        echo "Unmounting Windows ISO..."
        sudo umount -f -l "${ISO_MOUNT_POINT}" || true
    fi
    
    # Remove temporary mount directories only if empty
    rmdir "${EFI_PART_MOUNT_POINT}" 2>/dev/null || true
    rmdir "${WIN_PART_MOUNT_POINT}" 2>/dev/null || true
    rmdir "${ISO_MOUNT_POINT}" 2>/dev/null || true
}

# --- Main Script ---

# Exit immediately if a command exits with a non-zero status.
set -e

# Trap to ensure cleanup on exit or error
trap cleanup_mounts_safe EXIT

check_dependencies

if [ -z "$1" ]; then
    echo "Usage: $0 /dev/sdX"
    echo "  Where /dev/sdX is the target USB drive (e.g., /dev/sda)." >&2
    exit 1
fi

TARGET_DISK="$1"

EFI_PARTITION="${TARGET_DISK}1"
WINDOWS_PARTITION="${TARGET_DISK}2" # Assuming 2nd partition for Windows

# Display WARNING before destructive operations
echo "----------------------------------------------------"
echo "  WARNING: DESTRUCTIVE OPERATION AHEAD!"
echo "----------------------------------------------------"
echo "This script will **ERASE ALL DATA** on ${TARGET_DISK}."
echo "It will partition and format it for a Windows UEFI installation."
confirm_action "Are you absolutely SURE you want to proceed?"

# --- Device Readiness Check ---
echo "Performing device readiness check for ${TARGET_DISK}..."
MAX_RETRIES=5
RETRY_COUNT=0
DEVICE_READY=false
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if sudo lsblk -b "${TARGET_DISK}" &>/dev/null; then
        DEVICE_READY=true
        break
    else
        echo "${TARGET_DISK} not yet ready. Retrying in 2 seconds..."
        sleep 2
        RETRY_COUNT=$((RETRY_COUNT+1))
    fi
done

if [ "$DEVICE_READY" = "false" ]; then
    echo "Error: ${TARGET_DISK} is not recognized as a block device by lsblk after multiple retries. Please check physical connection and retry." >&2
    exit 1
fi
echo "${TARGET_DISK} is ready."



echo "Unmounting any existing partitions on ${TARGET_DISK}..."
# Get a list of all partitions (e.g., sda1, sda2) on the target disk
PARTITIONS_TO_UNMOUNT=$(lsblk -lno NAME "${TARGET_DISK}" | grep -v "${TARGET_DISK##*/}" | grep -E '[0-9]$' || true)

if [ -n "${PARTITIONS_TO_UNMOUNT}" ]; then
    echo "Found partitions to unmount on ${TARGET_DISK}: ${PARTITIONS_TO_UNMOUNT}"
    for part_name in ${PARTITIONS_TO_UNMOUNT}; do
        PART_PATH="/dev/${part_name}"
        # Check if partition is actually mounted using grep on /proc/mounts (more robust)
        if grep -qs "${PART_PATH}" /proc/mounts; then
            echo "Attempting to unmount ${PART_PATH}..."
            sudo umount -f -l "${PART_PATH}"
            if [ $? -ne 0 ]; then
                echo "Error: Failed to unmount ${PART_PATH} even after forceful attempt. Device is busy. Cannot proceed." >&2
                exit 1
            fi
        else
            echo "${PART_PATH} is not mounted."
        fi
    done
else
    echo "No partitions found to explicitly unmount on ${TARGET_DISK}."
fi

# Also unmount if the disk itself is somehow mounted
echo "Attempting to unmount ${TARGET_DISK} itself..."
if ! sudo umount -f -l "${TARGET_DISK}"; then
    UMOUNT_EXIT_CODE=$?
    if [ ${UMOUNT_EXIT_CODE} -ne 0 ]; then # If it's not 0 (success or 'not mounted'), then it's a real error
        echo "Error: Failed to unmount ${TARGET_DISK} itself. Device is busy. Cannot proceed." >&2
        exit 1
    fi
fi

# Kill any processes still using the device (last resort)
echo "Checking for and killing any lingering processes using ${TARGET_DISK}..."
# Use fuser -m to find processes using a mount point or block device
# -k for kill, -l for lazy, -i for interactive (skip -i for automation)
# We need to find processes on partitions first, then the whole disk

for part_name in $(lsblk -lno NAME "${TARGET_DISK}" | grep -v "${TARGET_DISK##*/}" | grep -E '[0-9]$' || true); do
    if [ -n "${part_name}" ]; then
        if fuser -m "/dev/${part_name}" &>/dev/null; then
            echo "Killing processes on /dev/${part_name}..."
            sudo fuser -mk "/dev/${part_name}"
            sleep 1 # Give time for processes to die
        fi
    fi
done

if fuser -m "${TARGET_DISK}" &>/dev/null; then
    echo "Killing processes on ${TARGET_DISK} itself..."
    sudo fuser -mk "${TARGET_DISK}"
    sleep 1
fi

sync # Flush filesystem buffers
sudo blockdev --flushbufs "${TARGET_DISK}"
sleep 2 # Give kernel time to release device handles
sudo partprobe "${TARGET_DISK}" || true # Refresh partition table (non-critical if it fails)


echo "Partitioning and formatting ${TARGET_DISK}..."
# Clear existing partition table and create new GPT
sudo parted -s ${TARGET_DISK} mklabel gpt

# Create EFI System Partition (ESP) - 500MiB, FAT32
sudo parted -s ${TARGET_DISK} mkpart primary fat32 0% 500MiB
sudo parted -s ${TARGET_DISK} set 1 esp on

# Create Windows Partition - remaining space, NTFS
sudo parted -s ${TARGET_DISK} mkpart primary ntfs 500MiB 100%

echo "Waiting for partition changes to propagate..."
sudo partprobe ${TARGET_DISK}
sleep 5 # Give the kernel time to recognize new partitions

echo "Formatting partitions..."
sudo mkfs.fat -F 32 ${EFI_PARTITION}
sudo mkfs.ntfs -f ${WINDOWS_PARTITION}

echo "USB Partitioning and Formatting complete for ${TARGET_DISK}."
