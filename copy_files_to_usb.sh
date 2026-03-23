#!/bin/bash
set -e

USB_DEV="/dev/sdb1"
MOUNT_POINT="/mnt/ventoy_usb_temp"

echo "Checking USB device..."
if [ ! -b "$USB_DEV" ]; then
    echo "Error: Device $USB_DEV not found. Is the USB plugged in?"
    exit 1
fi

echo "Mounting $USB_DEV..."
mkdir -p $MOUNT_POINT
mount $USB_DEV $MOUNT_POINT

echo "Copying files..."
cp -v install_openssh.ps1 $MOUNT_POINT/
cp -v run_me.bat $MOUNT_POINT/

# Check for Win10 ISO if present
if [ -f "win10.iso" ]; then
    echo "Copying Windows 10 ISO..."
    cp -v win10.iso $MOUNT_POINT/
fi

echo "Syncing data (Wait for it)..."
sync

echo "Unmounting..."
umount $MOUNT_POINT
rmdir $MOUNT_POINT

echo "----------------------------------------"
echo "Success! Files copied to USB."
echo "----------------------------------------"
