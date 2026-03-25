#!/bin/bash

# --- Configuration ---
# This script assumes PROJECT_ROOT is already set if needed by other functions, but for unmounting, it's not directly used.
# We will only use TARGET_DISK passed as an argument.

# --- Functions ---

# Function to check for required tools
check_dependencies() {
    echo "Checking dependencies..."
    REQUIRED_TOOLS="lsblk sudo grep awk mount umount fuser blockdev"
    for tool in $REQUIRED_TOOLS; do
        if ! command -v "$tool" &> /dev/null; then
            echo "Error: Required tool '$tool' is not installed. Please install it (e.g., 'sudo apt install $tool' or 'sudo apt install util-linux psmisc') and try again." >&2
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
    echo "  Where /dev/sdX is the target USB drive (e.g., /dev/sda)." >&2
    exit 1
fi

TARGET_DISK="$1"

# --- Device Readiness Check ---
echo "Performing device readiness check for ${TARGET_DISK}..."
MAX_RETRIES=5
RETRY_COUNT=0
DEVICE_READY=false
while [ ${RETRY_COUNT} -lt ${MAX_RETRIES} ]; do
    # Use lsblk -b to check if it's a block device and exists
    if sudo lsblk -b "${TARGET_DISK}" &>/dev/null; then
        DEVICE_READY=true
        break
    else
        echo "Warning: ${TARGET_DISK} is not yet available as a block device. Retrying in 2 seconds... (Attempt $((RETRY_COUNT + 1))/${MAX_RETRIES})" >&2
        sleep 2
        RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
done

if [ "$DEVICE_READY" = "false" ]; then
    echo "Error: ${TARGET_DISK} remains unavailable as a block device after ${MAX_RETRIES} attempts. Please check physical connection." >&2
    exit 1
fi
echo "${TARGET_DISK} is ready."


# Validate TARGET_DISK is a whole disk (not a partition) and removable
DEVICE_NAME_BASE=$(basename "${TARGET_DISK}")
if [[ ! -f "/sys/block/${DEVICE_NAME_BASE}/removable" ]] || [[ "$(cat "/sys/block/${DEVICE_NAME_BASE}/removable")" -eq 0 ]]; then
    echo "Error: ${TARGET_DISK} is not identified as a removable device." >&2
    echo "Please ensure you have selected a USB drive, not a permanent internal disk." >&2
    exit 1
fi
if echo "${TARGET_DISK}" | grep -qE '[0-9]$'; then
    echo "Error: You provided a partition as an argument (${TARGET_DISK}), please provide the whole disk (e.g., /dev/sda, not /dev/sda1)." >&2
    exit 1
fi

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

# Aggressive post-cleanup device release check
echo "Performing aggressive post-cleanup device release check for ${TARGET_DISK}..."
sleep 2 # Initial sleep before retry loop

MAX_UNMOUNT_RETRIES=15
UNMOUNT_RETRY_COUNT=0
DEVICE_FREE=false
while [ ${UNMOUNT_RETRY_COUNT} -lt ${MAX_UNMOUNT_RETRIES} ]; do
    # Attempt aggressive unmounts and process killing
    sudo umount -f -l "${TARGET_DISK}" >/dev/null 2>&1 || true
    sudo fuser -mk "${TARGET_DISK}" >/dev/null 2>&1 || true
    sudo partprobe "${TARGET_DISK}" >/dev/null 2>&1 || true

    # Check to break the loop: if lsblk can query the device AND it's truly free
    if sudo lsblk -b "${TARGET_DISK}" &>/dev/null; then # Check if lsblk can successfully query the device
        if [ -z "$(sudo lsblk -rno MOUNTPOINT,FSTYPE "${TARGET_DISK}" | awk '$1 != "" || $2 != ""' || true)" ]; then
        DEVICE_FREE=true
        break
    fi
    fi
    echo "Warning: ${TARGET_DISK} or its partitions still appear to be in use. Retrying in 2 seconds... (Attempt $((UNMOUNT_RETRY_COUNT + 1))/${MAX_UNMOUNT_RETRIES})" >&2
    sleep 2
    UNMOUNT_RETRY_COUNT=$((UNMOUNT_RETRY_COUNT + 1))
done

if [ "$DEVICE_FREE" = "false" ]; then
    echo "Error: ${TARGET_DISK} remains busy after aggressive unmounts. Cannot proceed." >&2
    exit 1
fi

echo "Successfully unmounted and prepared ${TARGET_DISK} for partitioning."
