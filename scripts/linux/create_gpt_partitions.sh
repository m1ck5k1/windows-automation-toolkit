#!/bin/bash

# --- Configuration ---
# This script assumes TARGET_DISK is passed as an argument.

# --- Functions ---

# Function to check for required tools
check_dependencies() {
    echo "Checking dependencies..."
    REQUIRED_TOOLS="sudo parted lsblk mkfs.fat"
    for tool in $REQUIRED_TOOLS; do
        if ! command -v "$tool" &> /dev/null; then
            echo "Error: Required tool '$tool' is not installed. Please install it (e.g., 'sudo apt install $tool' or 'sudo apt install parted') and try again." >&2
            exit 1
        fi
    done
    echo "All dependencies checked."
}

# --- Main Script ---

# Exit immediately if a command exits with a non-zero status.
set -e

check_dependencies

if [ -z "$1" ]; then
    echo "Usage: $0 /dev/sdX"
    echo "  Where /dev/sdX is the target USB drive (e.g., /dev/sda)." >&2
    exit 1
fi

TARGET_DISK="$1"

# Validate TARGET_DISK is a whole disk (not a partition) and removable
# (Assuming previous script (select_usb_device.sh) has already validated this)
DEVICE_NAME_BASE=$(basename "${TARGET_DISK}")
if echo "${TARGET_DISK}" | grep -qE '[0-9]$'; then
    echo "Error: You provided a partition as an argument (${TARGET_DISK}), please provide the whole disk (e.g., /dev/sda, not /dev/sda1)." >&2
    exit 1
fi

EFI_PARTITION="${TARGET_DISK}1"
WINDOWS_PARTITION="${TARGET_DISK}2" # Assuming 2nd partition for Windows

echo "Partitioning ${TARGET_DISK}..."
# Clear existing partition table and create new GPT
sudo parted -s ${TARGET_DISK} mklabel gpt

# Create EFI System Partition (ESP) - 500MiB, FAT32
sudo parted -s ${TARGET_DISK} mkpart primary fat32 0% 500MiB
sudo parted -s ${TARGET_DISK} set 1 esp on
sudo mkfs.fat -F 32 -n "BOOT_EFI" "${EFI_PARTITION}"

# Create Windows Partition - remaining space, NTFS
sudo parted -s ${TARGET_DISK} mkpart primary ntfs 500MiB 100%
sudo parted -s ${TARGET_DISK} set 2 msftdata on # Flag for Windows data partition

echo "Waiting for partition changes to propagate..."
sudo partprobe ${TARGET_DISK}
sleep 5 # Give the kernel time to recognize new partitions

echo "Successfully created GPT partitions on ${TARGET_DISK}."
