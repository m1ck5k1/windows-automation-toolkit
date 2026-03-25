#!/bin/bash

# --- Configuration ---
PROJECT_ROOT="/home/m1ck5k1/dev/windows-automation-toolkit"
WINDOWS_ISO="${PROJECT_ROOT}/win10_x64.iso"
UNATTEND_XML_SOURCE="${PROJECT_ROOT}/sysprep/unattend.xml"

# Mount points for partitions and ISO
EFI_PART_MOUNT_POINT="${PROJECT_ROOT}/.gemini/tmp/windows-automation-toolkit/efi_manual_mount"
WIN_PART_MOUNT_POINT="${PROJECT_ROOT}/.gemini/tmp/windows-automation-toolkit/win_manual_mount"
ISO_MOUNT_POINT="${PROJECT_ROOT}/.gemini/tmp/windows-automation-toolkit/iso_manual_mount"

AUTOMATION_KIT_DIR="AutomationKit" # Directory on the USB drive

# --- Functions ---

# Function to check for required tools
check_dependencies() {
    echo "Checking dependencies..."
    REQUIRED_TOOLS="lsblk sudo parted mkfs.ntfs mkfs.fat rsync mount umount findmnt partprobe"
    for tool in $REQUIRED_TOOLS; do
        if ! command -v "$tool" &> /dev/null; then
            echo "Error: Required tool '$tool' is not installed. Please install it (e.g., 'sudo apt install $tool' or 'sudo apt install ntfs-3g dosfstools parted util-linux wimtools') and try again."
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

# Check for AutomationKit directory early
if [ ! -d "${PROJECT_ROOT}/${AUTOMATION_KIT_DIR}" ]; then
    echo "Error: The \"${AUTOMATION_KIT_DIR}\" directory was not found at \"${PROJECT_ROOT}/${AUTOMATION_KIT_DIR}\". Please ensure it is restored to the project root before running this script." >&2
    exit 1
fi

check_dependencies

TARGET_DISK=""
SELECTED_BY_ID=""

echo "----------------------------------------------------"
echo "  Select Target USB Drive"
echo "----------------------------------------------------"
echo "Available Removable Disks:"

declare -a DISK_OPTIONS
declare -a DISK_BY_ID_MAP
declare -i OPTION_NUM=1

# Populate DISK_OPTIONS and DISK_BY_ID_MAP arrays
for sys_device in /sys/block/sd*; do
    DEVICE_NAME=$(basename "${sys_device}")
    TARGET_DEV_CANDIDATE="/dev/${DEVICE_NAME}"

    # Check if it's a removable device
    if [[ -f "${sys_device}/removable" ]] && [[ "$(cat "${sys_device}/removable")" -eq 1 ]]; then
        # Check if it's a whole disk (not a partition) and get size
        DEVICE_TYPE=$(lsblk -dn -o TYPE "${TARGET_DEV_CANDIDATE}" 2>/dev/null || true)
        if [[ "${DEVICE_TYPE}" == "disk" ]]; then
            # Ensure it's not the OS root disk
            if findmnt -n / | grep -q "${TARGET_DEV_CANDIDATE}"; then
                continue # Skip if it's the OS root disk
            fi

            DEVICE_SIZE=$(lsblk -dn -o SIZE "${TARGET_DEV_CANDIDATE}" 2>/dev/null || true)

            # Find the persistent /dev/disk/by-id path
            BY_ID_PATH=""
            for BY_ID_ENTRY in /dev/disk/by-id/*; do
                LINK_TARGET=$(readlink -f "${BY_ID_ENTRY}")
                if [ "${LINK_TARGET}" == "${TARGET_DEV_CANDIDATE}" ]; then
                    if [[ ! "${BY_ID_ENTRY}" =~ (part[0-9]|loop) ]]; then
                        BY_ID_PATH="${BY_ID_ENTRY}"
                        break
                    fi
                fi
            done

            if [ -n "${BY_ID_PATH}" ]; then
                DISK_OPTIONS+=("${TARGET_DEV_CANDIDATE}")
                DISK_BY_ID_MAP+=("${BY_ID_PATH}")
                echo "${OPTION_NUM}) ${BY_ID_PATH} (-> ${TARGET_DEV_CANDIDATE}) - ${DEVICE_SIZE}"
                OPTION_NUM=$((OPTION_NUM+1))
            fi
        fi
    fi
done

if [ ${#DISK_OPTIONS[@]} -eq 0 ]; then
    echo "Error: No suitable removable disk drives found. Please ensure your USB is connected and is not your main OS drive." >&2
    exit 1
fi

SELECTED_NUM=""
VALID_SELECTION=0
while [ "${VALID_SELECTION}" -eq 0 ]; do
    read -p "Enter the number of your TARGET USB drive: " SELECTED_NUM
    if [[ "$SELECTED_NUM" =~ ^[0-9]+$ ]] && [ "$SELECTED_NUM" -ge 1 ] && [ "$SELECTED_NUM" -le ${#DISK_OPTIONS[@]} ]; then
        TARGET_DISK="${DISK_OPTIONS[SELECTED_NUM-1]}"
        SELECTED_BY_ID="${DISK_BY_ID_MAP[SELECTED_NUM-1]}"
        echo "Selected target disk: ${TARGET_DISK} (via ${SELECTED_BY_ID})"
        echo ""
        echo "****************************************************"
        echo "  ATTENTION: PHYSICAL LABELING REQUIRED!"
        echo "****************************************************"
        echo ""
        echo "For physical labeling, please use this ID:"
        echo ">>> ${SELECTED_BY_ID} <<<"
        echo ""
        VALID_SELECTION=1
    else
        echo "Error: Invalid selection. Please enter a number from 1 to ${#DISK_OPTIONS[@]} ."
        VALID_SELECTION=0
    fi
done

confirm_action "\n\n=====================================================\n>>> PLEASE PHYSICALLY LABEL THIS USB DRIVE NOW <<<\n  Persistent ID: ${SELECTED_BY_ID}\n=====================================================\n\nAre you SURE you want to proceed with creating a Windows 10 UEFI bootable USB on ${TARGET_DISK}? (This will erase all data!)\nNOTE: This will create two partitions: a FAT32 EFI partition and a large NTFS Windows installation partition."

EFI_PARTITION="${TARGET_DISK}1"
WINDOWS_PARTITION="${TARGET_DISK}2" # Assuming 2nd partition for Windows

echo "Unmounting any existing partitions on ${TARGET_DISK}..."
# Get a list of all partition names associated with TARGET_DISK
# Use a more robust way to get partitions, filtering out the disk itself
PARTITIONS=$(lsblk -lno NAME "${TARGET_DISK}" | awk '/^[^[:digit:]]+[[:digit:]]+$/ {print $1}')

UNMOUNT_FAILED=0 # Flag to track if any unmount failed

# Attempt to unmount each partition forcefully
for part in $PARTITIONS; do
    MOUNT_POINT="/dev/${part}"
    if mountpoint -q "${MOUNT_POINT}"; then
        echo "Attempting to forcefully unmount ${MOUNT_POINT}..."
        if ! sudo umount -f -l "${MOUNT_POINT}"; then
            echo "Warning: Initial unmount of ${MOUNT_POINT} failed. Checking for open files..." >&2
            # Identify and kill processes holding files open on the partition
            PIDS_HOLDING_PARTITION=$(sudo lsof -t "${MOUNT_POINT}" 2>/dev/null)
            if [ -n "${PIDS_HOLDING_PARTITION}" ]; then
                echo "Found processes holding ${MOUNT_POINT} open. Killing them: ${PIDS_HOLDING_PARTITION}" >&2
                sudo kill -9 ${PIDS_HOLDING_PARTITION}
                sleep 1 # Give time for processes to terminate
                echo "Retrying unmount of ${MOUNT_POINT} after killing processes..." >&2
                if ! sudo umount -f -l "${MOUNT_POINT}"; then
                    echo "Warning: Still failed to unmount ${MOUNT_POINT} after killing processes." >&2
                    UNMOUNT_FAILED=1
                fi
            else
                echo "Warning: Failed to forcefully unmount ${MOUNT_POINT}. No processes found holding it open." >&2
                UNMOUNT_FAILED=1
            fi
        fi
    fi
done

if [ ${UNMOUNT_FAILED} -eq 1 ]; then
    echo "Error: One or more partitions failed to unmount. Please ensure no files are open on this device and try again." >&2
    exit 1
fi

# Unmount the target disk itself, if for some reason it's mounted
if mountpoint -q "${TARGET_DISK}"; then
    echo "Attempting to forcefully unmount ${TARGET_DISK} itself..."
    if ! sudo umount -f -l "${TARGET_DISK}"; then
        echo "Error: Failed to forcefully unmount ${TARGET_DISK}. Please ensure no files are open on this device and try again." >&2
        exit 1
    fi
fi

# Last-resort unmount for the entire disk
echo "Attempting final brute-force unmount of ${TARGET_DISK}..."
sudo umount -f -l "${TARGET_DISK}" 2>/dev/null || true # Ignore errors, it might already be unmounted

# Flush kernel buffers
echo "Flushing kernel buffers for ${TARGET_DISK}..."
sudo blockdev --flushbufs "${TARGET_DISK}"

# Flush filesystem buffers and wait for kernel to release device handles
echo "Flushing filesystem buffers and waiting for device handles to release..."
sync
sleep 2

# Verify that all partitions are unmounted after forceful attempts
for part in $PARTITIONS; do
    MOUNT_POINT="/dev/${part}"
    if mountpoint -q "${MOUNT_POINT}"; then
        echo "Error: Partition ${MOUNT_POINT} is still mounted after forceful unmount attempts. Exiting." >&2
        exit 1
    fi
done
# Also verify if the disk itself is still mounted
if mountpoint -q "${TARGET_DISK}"; then
    echo "Error: Disk ${TARGET_DISK} is still mounted after forceful unmount attempts. Exiting." >&2
    exit 1
fi

sudo partprobe "${TARGET_DISK}" || true # Refresh partition table

echo "Creating temporary mount directories..."
mkdir -p "${EFI_PART_MOUNT_POINT}"
mkdir -p "${WIN_PART_MOUNT_POINT}"
mkdir -p "${ISO_MOUNT_POINT}"

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

echo "Mounting Windows ISO: ${WINDOWS_ISO}"
sudo mount -o loop "${WINDOWS_ISO}" "${ISO_MOUNT_POINT}"

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

# Discover bootmgfw.efi (case-insensitive)
BOOTMGFW_EFI_ISO_PATH=$(find "${ISO_MOUNT_POINT}/efi/microsoft/boot" -type f -iname "bootmgfw.efi" | head -n 1)
BOOTX64_EFI_ISO_PATH=$(find "${ISO_MOUNT_POINT}/efi/boot" -type f -iname "bootx64.efi" | head -n 1)



# Copy unattend.xml
if [ -f "${UNATTEND_XML_SOURCE}" ]; then
    echo "Copying unattend.xml to Windows partition..."
    sudo mkdir -p "${WIN_PART_MOUNT_POINT}/Windows/Panther"
    sudo cp "${UNATTEND_XML_SOURCE}" "${WIN_PART_MOUNT_POINT}/Windows/Panther/unattend.xml"
else
    echo "Error: unattend.xml not found at ${UNATTEND_XML_SOURCE}. Cannot proceed." >&2
    exit 1
fi

# Copy AutomationKit directory
if [ -d "${PROJECT_ROOT}/${AUTOMATION_KIT_DIR}" ]; then
    echo "Copying AutomationKit to Windows partition..."
    sudo rsync -ah "${PROJECT_ROOT}/${AUTOMATION_KIT_DIR}/" "${WIN_PART_MOUNT_POINT}/${AUTOMATION_KIT_DIR}/"
else
    echo "Error: AutomationKit directory not found at ${PROJECT_ROOT}/${AUTOMATION_KIT_DIR}. This should have been caught by the pre-check. Exiting." >&2
    exit 1
fi


echo "Successfully created Windows 10 UEFI bootable USB on ${TARGET_DISK}!"
echo "Please safely eject the USB drive."



