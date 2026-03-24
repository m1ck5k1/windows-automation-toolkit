#!/bin/bash
set -e

# Configuration
ISO_FILE="Win11_25H2_EnglishInternational_x64.iso"
USB_DEVICE="/dev/sda"
MOUNT_POINT="/mnt/ventoy_usb"

# Check if ISO exists
if [ ! -f "$ISO_FILE" ]; then
    echo "Error: ISO file '$ISO_FILE' not found!"
    exit 1
fi

# Check if Ventoy directory exists
if [ ! -d "ventoy-1.1.10" ]; then
    echo "Error: Ventoy directory not found. Please extract it first."
    exit 1
fi

echo "========================================================"
echo "WARNING: This will ERASE ALL DATA on $USB_DEVICE"
echo "========================================================"
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Install Ventoy
echo "Installing Ventoy..."
cd ventoy-1.1.10
# -i installs, will prompt user for double confirmation
sudo ./Ventoy2Disk.sh -i $USB_DEVICE
cd ..

# Mount and Copy
echo "Mounting partition 1..."
sudo mkdir -p $MOUNT_POINT
# Ventoy partition 1 is usually exFAT
sudo mount ${USB_DEVICE}1 $MOUNT_POINT

echo "Copying ISO file (This may take 5-10 minutes)..."
sudo cp -v "$ISO_FILE" "$MOUNT_POINT/"

echo "Syncing data to disk..."
sync

echo "Unmounting..."
sudo umount $MOUNT_POINT
sudo rmdir $MOUNT_POINT

echo "--------------------------------------------------------"
echo "SUCCESS! Windows 11 Boot USB created."
echo "You can now boot from this USB to install Windows 11."
echo "--------------------------------------------------------"
