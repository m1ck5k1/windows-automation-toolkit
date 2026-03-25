#!/bin/bash

# --- Configuration ---
# This script assumes TARGET_DISK is passed as an argument.

# --- Functions ---

# Function to check for required tools
check_dependencies() {
    echo "Checking dependencies..."
    REQUIRED_TOOLS="sudo mkfs.fat mkfs.ntfs lsblk"
    for tool in $REQUIRED_TOOLS; do
        if ! command -v "$tool" &> /dev/null; then
            echo "Error: Required tool '$tool' is not installed. Please install it (e.g., 'sudo apt install $tool' or 'sudo apt install dosfstools ntfs-3g') and try again." >&2
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

# Assuming partitions are already created as ${TARGET_DISK}1 (EFI) and ${TARGET_DISK}2 (Windows)
EFI_PARTITION="${TARGET_DISK}1"
WINDOWS_PARTITION="${TARGET_DISK}2"

# Validate partitions exist
if ! [ -b "${EFI_PARTITION}" ]; then
    echo "Error: EFI partition ${EFI_PARTITION} does not exist. Please ensure partitions are created before running this script." >&2
    exit 1
fi
if ! [ -b "${WINDOWS_PARTITION}" ]; then
    echo "Error: Windows partition ${WINDOWS_PARTITION} does not exist. Please ensure partitions are created before running this script." >&2
    exit 1
fi

echo "Formatting partitions on ${TARGET_DISK}..."
sudo mkfs.ntfs -f -L "WIN10_INSTALL" "${WINDOWS_PARTITION}"

# --- Verification ---
echo "Verifying partition formats..."

# Verify EFI partition (already formatted and verified by create_gpt_partitions.sh)
EFI_FSTYPE=$(lsblk -n -o FSTYPE "${EFI_PARTITION}")
if [ "${EFI_FSTYPE}" != "vfat" ]; then
    echo "Error: EFI partition ${EFI_PARTITION} is not FAT32. Partitioning/Formatting in previous step failed." >&2
    exit 1
fi
echo "Verification: EFI partition ${EFI_PARTITION} is FAT32. [SUCCESS]"

# Verify Windows partition
WIN_FSTYPE=$(lsblk -n -o FSTYPE "${WINDOWS_PARTITION}")
if [ "${WIN_FSTYPE}" != "ntfs" ]; then
    echo "Error: Windows partition ${WINDOWS_PARTITION} is not formatted as NTFS (detected as ${WIN_FSTYPE}). Formatting failed." >&2
    exit 1
fi
echo "Verification: Windows partition ${WINDOWS_PARTITION} is NTFS. [SUCCESS]"

echo "Successfully formatted partitions on ${TARGET_DISK}."
