#!/bin/bash
set -e

# --- Configuration ---
export PROJECT_ROOT="/home/m1ck5k1/dev/windows-automation-toolkit"
WINDOWS_ISO="${PROJECT_ROOT}/win10_x64.iso"

# --- Functions ---

# Global Mount Points
EFI_PART_MOUNT_POINT="${PROJECT_ROOT}/.gemini/tmp/usb_efi_validate_mount"
WIN_PART_MOUNT_POINT="${PROJECT_ROOT}/.gemini/tmp/usb_win_validate_mount"
ISO_MOUNT_POINT="${PROJECT_ROOT}/.gemini/tmp/windows-automation-toolkit"
TARGET_DISK=""

# Function to mount all necessary partitions and the ISO
mount_all_partitions_and_iso() {
    echo "Mounting all partitions and ISO..."

    # Create mount directories
    sudo mkdir -p "${EFI_PART_MOUNT_POINT}" || { echo "Error: Failed to create EFI mount point."; exit 1; }
    sudo mkdir -p "${WIN_PART_MOUNT_POINT}" || { echo "Error: Failed to create Windows mount point."; exit 1; }
    sudo mkdir -p "${ISO_MOUNT_POINT}" || { echo "Error: Failed to create ISO mount point."; exit 1; }

    # Determine partition paths based on TARGET_DISK
    # Assuming standard partition numbering: 1 for EFI, 2 for Windows
    EFI_PARTITION="${TARGET_DISK}1"
    WINDOWS_PARTITION="${TARGET_DISK}2"

    # Mount Windows ISO (read-only)
    echo "Mounting Windows ISO from ${WINDOWS_ISO} to ${ISO_MOUNT_POINT}..."
    sudo mount -o loop,ro "${WINDOWS_ISO}" "${ISO_MOUNT_POINT}" || { echo "Error: Failed to mount Windows ISO."; exit 1; }
    echo "Windows ISO mounted successfully."

    # Mount EFI partition
    echo "Mounting EFI partition ${EFI_PARTITION} to ${EFI_PART_MOUNT_POINT}..."
    sudo mount -o rw "${EFI_PARTITION}" "${EFI_PART_MOUNT_POINT}" || { echo "Error: Failed to mount EFI partition."; exit 1; }
    echo "EFI partition mounted successfully."

    # Mount Windows partition
    echo "Mounting Windows partition ${WINDOWS_PARTITION} to ${WIN_PART_MOUNT_POINT}..."
    sudo mount "${WINDOWS_PARTITION}" "${WIN_PART_MOUNT_POINT}" || { echo "Error: Failed to mount Windows partition."; exit 1; }
    echo "Windows partition mounted successfully."
}

# Function to unmount all partitions and ISO, and clean up
cleanup_all_mounts() {
    echo "Initiating cleanup of all mounts and temporary directories."

    # Attempt to unmount ISO
    if grep -qs "${ISO_MOUNT_POINT}" /proc/mounts; then
        echo "Unmounting ISO from ${ISO_MOUNT_POINT}..."
        if ! sudo umount -f -l "${ISO_MOUNT_POINT}"; then
            UMOUNT_EXIT_CODE=$?
            if [ ${UMOUNT_EXIT_CODE} -ne 0 ] && [ ${UMOUNT_EXIT_CODE} -ne 32 ]; then # 32 usually means not mounted, which is fine
                echo "Warning: Failed to unmount ISO from ${ISO_MOUNT_POINT} (exit code ${UMOUNT_EXIT_CODE}). Attempting fuser kill."
                sudo fuser -mk "${ISO_MOUNT_POINT}" || true # Kill processes using the mount point
                if ! sudo umount -f -l "${ISO_MOUNT_POINT}"; then
                    echo "Error: Failed to unmount ISO even after fuser kill. Device or resource busy." >&2
                fi
            fi
        fi
    fi

    # Attempt to unmount EFI partition
    if grep -qs "${EFI_PART_MOUNT_POINT}" /proc/mounts; then
        echo "Unmounting EFI partition from ${EFI_PART_MOUNT_POINT}..."
        if ! sudo umount -f -l "${EFI_PART_MOUNT_POINT}"; then
            UMOUNT_EXIT_CODE=$?
            if [ ${UMOUNT_EXIT_CODE} -ne 0 ] && [ ${UMOUNT_EXIT_CODE} -ne 32 ]; then
                echo "Warning: Failed to unmount EFI partition from ${EFI_PART_MOUNT_POINT} (exit code ${UMOUNT_EXIT_CODE}). Attempting fuser kill."
                sudo fuser -mk "${EFI_PART_MOUNT_POINT}" || true
                if ! sudo umount -f -l "${EFI_PART_MOUNT_POINT}"; then
                    echo "Error: Failed to unmount EFI partition even after fuser kill. Device or resource busy." >&2
                fi
            fi
        fi
    fi

    # Attempt to unmount Windows partition
    if grep -qs "${WIN_PART_MOUNT_POINT}" /proc/mounts; then
        echo "Unmounting Windows partition from ${WIN_PART_MOUNT_POINT}..."
        if ! sudo umount -f -l "${WIN_PART_MOUNT_POINT}"; then
            UMOUNT_EXIT_CODE=$?
            if [ ${UMOUNT_EXIT_CODE} -ne 0 ] && [ ${UMOUNT_EXIT_CODE} -ne 32 ]; then
                echo "Warning: Failed to unmount Windows partition from ${WIN_PART_MOUNT_POINT} (exit code ${UMOUNT_EXIT_CODE}). Attempting fuser kill."
                sudo fuser -mk "${WIN_PART_MOUNT_POINT}" || true
                if ! sudo umount -f -l "${WIN_PART_MOUNT_POINT}"; then
                    echo "Error: Failed to unmount Windows partition even after fuser kill. Device or resource busy." >&2
                fi
            fi
        fi
    fi

    # Remove mount directories
    if [ -d "${EFI_PART_MOUNT_POINT}" ]; then
        echo "Removing EFI mount directory ${EFI_PART_MOUNT_POINT}."
        sudo rmdir "${EFI_PART_MOUNT_POINT}" || echo "Warning: Could not remove ${EFI_PART_MOUNT_POINT}. It might not be empty."
    fi
    if [ -d "${WIN_PART_MOUNT_POINT}" ]; then
        echo "Removing Windows mount directory ${WIN_PART_MOUNT_POINT}."
        sudo rmdir "${WIN_PART_MOUNT_POINT}" || echo "Warning: Could not remove ${WIN_PART_MOUNT_POINT}. It might not be empty."
    fi
    if [ -d "${ISO_MOUNT_POINT}" ]; then
        echo "Removing ISO mount directory ${ISO_MOUNT_POINT}."
        sudo rmdir "${ISO_MOUNT_POINT}" || echo "Warning: Could not remove ${ISO_MOUNT_POINT}. It might not be empty."
    fi

    # Robust process-killing and buffer flushing for TARGET_DISK
    if [ -n "${TARGET_DISK}" ]; then
        echo "Ensuring complete device release for ${TARGET_DISK}..."
        if sudo fuser -mk "${TARGET_DISK}" &> /dev/null; then
            echo "Killed processes using ${TARGET_DISK}."
        fi
        if sudo blockdev --flushbufs "${TARGET_DISK}"; then
            echo "Flushed buffers for ${TARGET_DISK}."
        else
            echo "Warning: Failed to flush buffers for ${TARGET_DISK}."
        fi
    fi

    echo "Cleanup complete."
}

# Function to confirm manual actions
confirm_action() {
    read -p "$1" response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Function to check for necessary dependencies (for this orchestrator script)
check_orchestrator_dependencies() {
    echo "Checking orchestrator dependencies..."
    local dependencies=(
        "lsblk" "sudo" "readlink" "grep" "awk" "basename" "dirname" "head" "tail" "wc" "test" "blockdev" "fuser" "umount" "ntfsfix"
        "scripts/linux/select_usb_device.sh" 
        "scripts/linux/unmount_target_disk.sh" 
        "scripts/linux/create_gpt_partitions.sh" 
        "scripts/linux/format_partitions.sh" 
        "scripts/linux/copy_windows_files.sh"
    )
    local missing_dependencies=""


    for dep in "${dependencies[@]}"; do
        if [[ "$dep" == scripts/linux/* ]]; then # Check if it's a script path
            if [ ! -f "${PROJECT_ROOT}/$dep" ] || [ ! -x "${PROJECT_ROOT}/$dep" ]; then
                missing_dependencies+=" $dep (missing or not executable)"
            fi
        else # Assume it's a system command
            if ! command -v "$dep" &> /dev/null; then
                missing_dependencies+=" $dep"
            fi
        fi
    done

    if [ -n "$missing_dependencies" ]; then
        echo "Error: The following orchestrator dependencies are missing or not executable: $missing_dependencies" >&2
        exit 1
    fi
    echo "All orchestrator dependencies checked."
}

# --- Main Script ---

# Trap for cleanup operations on exit
trap cleanup_all_mounts EXIT

echo "Starting USB creation orchestration..."

# Check for required tools and component scripts
check_orchestrator_dependencies

# 1. Select USB device
echo "----------------------------------------------------"
echo "  Step 1/6: Selecting USB Device"
echo "----------------------------------------------------"
echo "Please interact with the prompts below to select your target USB drive."
DEVICE_INFO=$(sudo "${PROJECT_ROOT}/scripts/linux/select_usb_device.sh")
SELECT_USB_STATUS=$?
if [ ${SELECT_USB_STATUS} -ne 0 ]; then
    echo "Error: Failed to select a USB device. Exiting." >&2
    exit ${SELECT_USB_STATUS}
fi

# Extract the last two lines which contain TARGET_DISK and SELECTED_BY_ID
TARGET_DISK=$(echo "$DEVICE_INFO" | tail -n 2 | head -n 1)
SELECTED_BY_ID=$(echo "$DEVICE_INFO" | tail -n 1)

if [ -z "$TARGET_DISK" ]; then
    echo "Error: TARGET_DISK not found in select_usb_device.sh output. Exiting." >&2
    exit 1
fi

echo "Selected USB device: ${TARGET_DISK}"
echo "Persistent ID: ${SELECTED_BY_ID}"

# Determine partition paths based on TARGET_DISK
# Assuming standard partition numbering: 1 for EFI, 2 for Windows
EFI_PARTITION="${TARGET_DISK}1"
WINDOWS_PARTITION="${TARGET_DISK}2"

# 2. Unmount target disk
echo "----------------------------------------------------"
echo "  Step 2/8: Unmounting Target Disk"
echo "----------------------------------------------------"
sudo "${PROJECT_ROOT}/scripts/linux/unmount_target_disk.sh" "${TARGET_DISK}"
if [ $? -ne 0 ]; then
    echo "Error: Failed to unmount ${TARGET_DISK}. Exiting." >&2
    exit 1
fi
echo "Target disk unmounted successfully."

# 3. Manual USB Reconnection
echo "----------------------------------------------------"
echo "  Step 3/8: Manual USB Reconnection"
echo "----------------------------------------------------"
# --- MANUAL ACTION REQUIRED ---
echo "" >&2
echo "================================================================================" >&2
echo "!!! MANUAL INTERVENTION REQUIRED !!!" >&2
echo "Please PHYSICALLY UNPLUG the USB device (${TARGET_DISK}) from your computer." >&2
echo "Then, REPLUG the USB device (${TARGET_DISK}) into a USB port." >&2
echo "This step is crucial to resolve persistent kernel-level device busy issues." >&2
echo "================================================================================" >&2
echo "" >&2

if ! confirm_action "Please unplug and then replug the USB device (${TARGET_DISK}) NOW. Confirm when done (y/n): " >&2; then
    echo "Error: Manual intervention cancelled. Exiting." >&2
    exit 1
fi
echo "USB device reconnected and confirmed."

# 4. Create GPT partitions
echo "----------------------------------------------------"
echo "  Step 4/8: Creating GPT Partitions"
echo "----------------------------------------------------"
sudo "${PROJECT_ROOT}/scripts/linux/create_gpt_partitions.sh" "${TARGET_DISK}"
if [ $? -ne 0 ]; then
    echo "Error: Failed to create GPT partitions on ${TARGET_DISK}. Exiting." >&2
    exit 1
fi
echo "GPT partitions created successfully."

# 5. Format partitions
echo "----------------------------------------------------"
echo "  Step 5/8: Formatting Partitions"
echo "----------------------------------------------------"
sudo "${PROJECT_ROOT}/scripts/linux/format_partitions.sh" "${TARGET_DISK}"
if [ $? -ne 0 ]; then
    echo "Error: Failed to format partitions on ${TARGET_DISK}. Exiting." >&2
    exit 1
fi
echo "Partitions formatted successfully."

# 6. Run ntfsfix on the Windows partition
echo "----------------------------------------------------"
echo "  Step 6/8: Running ntfsfix on Windows Partition"
echo "----------------------------------------------------"
echo "Running ntfsfix on ${WINDOWS_PARTITION}..."
sudo ntfsfix -d "${WINDOWS_PARTITION}"
if [ $? -ne 0 ]; then
    echo "Error: ntfsfix failed on ${WINDOWS_PARTITION}. Exiting." >&2
    exit 1
fi
echo "ntfsfix completed successfully."

# 7. Mount partitions and ISO
echo "----------------------------------------------------"
echo "  Step 7/8: Mounting Partitions and ISO"
echo "----------------------------------------------------"
mount_all_partitions_and_iso
if [ $? -ne 0 ]; then
    echo "Error: Failed to mount partitions and ISO. Exiting." >&2
    exit 1
fi
echo "All partitions and ISO mounted successfully."

# 8. Copy Windows and AutomationKit files
echo "----------------------------------------------------"
echo "  Step 8/8: Copying Windows and AutomationKit Files"
echo "----------------------------------------------------"
sudo "${PROJECT_ROOT}/scripts/linux/copy_windows_files.sh" "${PROJECT_ROOT}" "${TARGET_DISK}" "${EFI_PART_MOUNT_POINT}" "${WIN_PART_MOUNT_POINT}" "${ISO_MOUNT_POINT}"
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy Windows and AutomationKit files to ${TARGET_DISK}. Exiting." >&2
    exit 1
fi
echo "All files copied successfully."

echo "----------------------------------------------------"
echo "  USB creation orchestration completed successfully!"
echo "----------------------------------------------------"
echo "The UEFI bootable USB for ${TARGET_DISK} is ready."
echo "Please safely eject the USB drive."
