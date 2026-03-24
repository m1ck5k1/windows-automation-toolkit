#!/bin/bash

# --- Configuration ---
PROJECT_ROOT="/home/m1ck5k1/dev/windows-automation-toolkit"
export VENTOY_DIR="${PROJECT_ROOT}/tools/ventoy-1.1.10"
VENTOY_INSTALL_SCRIPT="${VENTOY_DIR}/Ventoy2Disk.sh"

# --- Functions ---

# Function to check for required tools
check_dependencies() {
    echo "Checking dependencies..."
    REQUIRED_TOOLS="lsblk sudo parted mkfs.fat"
    for tool in $REQUIRED_TOOLS; do
        if ! command -v "$tool" &> /dev/null; then
            echo "Error: Required tool '$tool' is not installed. Please install it (e.g., 'sudo apt install $tool' or 'sudo apt install dosfstools parted') and try again."
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

echo "----------------------------------------------------"
echo "  Dedicated Ventoy Installation Script"
echo "----------------------------------------------------"
echo "WARNING: This script will erase all data on ${TARGET_DISK}."
echo "Please ensure you have selected the correct device."
echo

# List block devices to help user confirm
echo "Current block devices:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "disk|part|${TARGET_DISK##*/}" || true
echo

confirm_action "Do you want to proceed with installing Ventoy (GPT/UEFI) to ${TARGET_DISK}? (This will erase all data!)"

echo "Installing Ventoy to ${TARGET_DISK} with GPT partitioning..."
sudo "${VENTOY_INSTALL_SCRIPT}" -I -g "${TARGET_DISK}"

echo "Ventoy installation complete for ${TARGET_DISK}."
echo "You can now safely remove the USB drive or proceed to copy ISOs."
