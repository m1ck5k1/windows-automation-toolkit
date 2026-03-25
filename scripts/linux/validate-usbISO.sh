#!/bin/bash

set -euo pipefail

# --- Configuration ---
PROJECT_ROOT="/home/m1ck5k1/dev/windows-automation-toolkit"
TMP_DIR="${PROJECT_ROOT}/.gemini/tmp"
EFI_PART_MOUNT_POINT="${TMP_DIR}/usb_efi_validate_mount"
WIN_PART_MOUNT_POINT="${TMP_DIR}/usb_win_validate_mount"
USB_DEVICE_PATH="" # Declared globally to be accessible by cleanup trap

# --- Functions ---

# Function to check for required dependencies
check_dependencies() {
    local dependencies=("lsblk" "sudo" "mount" "umount" "mountpoint" "readlink" "grep" "awk" "basename" "dirname" "head" "tail" "wc" "test" "fuser" "blockdev")
    local missing_deps=""

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=" $dep"
        fi
    done

    if [ -n "$missing_deps" ]; then
        echo "Error: The following required commands are not installed:$missing_deps" >&2
        echo "Please install them and try again." >&2
        exit 1
    fi
}

# Function to confirm an action
confirm_action() {
    read -p "Are you sure you want to proceed? (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            true
            ;;
        *)
            false
            ;;
    esac
}

# Function to safely mount a partition
safe_mount() {
    local device="$1"
    local mount_point="$2"
    local options="$3"
    local description="$4" # Added for better warning messages

    if grep -qs "^${mount_point} " /proc/mounts; then
        echo "Warning: ${description} (${device}) is already mounted at ${mount_point}. Skipping mount." >&2
        return 0
    fi

    echo "Attempting to mount ${description} (${device}) to ${mount_point} with options '$options'..." >&2
    if sudo mount -o "$options" "$device" "$mount_point"; then
        echo "Successfully mounted ${description} (${device}) to ${mount_point}." >&2
        return 0
    else
        echo "Error: Failed to mount ${description} (${device}) to ${mount_point}." >&2
        return 1
    fi
}

# Function to mount partitions for validation purposes
mount_partitions_and_iso_for_validation() {
    local efi_part="$1"
    local win_part="$2"

    echo "Creating temporary mount points..." >&2
    sudo mkdir -p "${EFI_PART_MOUNT_POINT}" || { echo "Error: Failed to create EFI mount point."; exit 1; }
    sudo mkdir -p "${WIN_PART_MOUNT_POINT}" || { echo "Error: Failed to create Windows mount point."; exit 1; }

    echo "Mounting partitions for validation..." >&2
    if ! safe_mount "${efi_part}" "${EFI_PART_MOUNT_POINT}" "ro" "EFI Partition"; then
        exit 1
    fi

    if ! safe_mount "${win_part}" "${WIN_PART_MOUNT_POINT}" "ro" "Windows Partition"; then # Mount read-only for validation
        exit 1
    fi
}

# Function to cleanup validation mounts and temporary directories
cleanup_validation_mounts() {
    echo "Performing validation cleanup..." >&2
    local all_unmounts_successful=true

    local -a mount_points_to_check=("${EFI_PART_MOUNT_POINT}" "${WIN_PART_MOUNT_POINT}")

    for mp in "${mount_points_to_check[@]}"; do
        if grep -qs "^${mp} " /proc/mounts; then
            echo "Attempting to unmount ${mp}..." >&2
            if sudo umount -f -l "${mp}"; then
                echo "Successfully unmounted ${mp}." >&2
            else
                local UMOUNT_EXIT_CODE=$?
                if [ ${UMOUNT_EXIT_CODE} -ne 0 ] && [ ${UMOUNT_EXIT_CODE} -ne 32 ]; then
                    echo "Warning: Forceful unmount of ${mp} failed (exit code ${UMOUNT_EXIT_CODE}). Checking for lingering processes." >&2
                    if fuser -m "${mp}" &>/dev/null; then
                        echo "Killing processes using ${mp}... (fuser -mk)" >&2
                        sudo fuser -mk "${mp}" || true
                        sleep 1
                        echo "Retrying unmount of ${mp} after killing processes..." >&2
                        if sudo umount -f -l "${mp}"; then
                            echo "Successfully unmounted ${mp} after killing processes." >&2
                        else
                            echo "Error: Failed to unmount ${mp} even after killing processes." >&2
                            all_unmounts_successful=false
                        fi
                    else
                        echo "Error: Failed to unmount ${mp}. No lingering processes found." >&2
                        all_unmounts_successful=false
                    fi
                fi
            fi
        else
            echo "${mp} is not mounted." >&2
        fi
    done

    sync
    sleep 1

    # Aggressive pre-loop device release attempts for the main USB device
    if [ -n "${USB_DEVICE_PATH}" ]; then
        sudo umount -f -l "${USB_DEVICE_PATH}" >/dev/null 2>&1 || true
        sudo fuser -mk "${USB_DEVICE_PATH}" >/dev/null 2>&1 || true
        sudo partprobe "${USB_DEVICE_PATH}" >/dev/null 2>&1 || true
        sync
        sleep 1

        echo "Ensuring complete device release for ${USB_DEVICE_PATH}... (Max 15 retries)" >&2
        local MAX_UNMOUNT_RETRIES=15
        local UNMOUNT_RETRY_COUNT=0
        local DEVICE_TRULY_FREE=false
        while [ ${UNMOUNT_RETRY_COUNT} -lt ${MAX_UNMOUNT_RETRIES} ]; do
            # Attempt aggressive unmounts and process killing
            sudo umount -f -l "${USB_DEVICE_PATH}" >/dev/null 2>&1 || true
            sudo fuser -mk "${USB_DEVICE_PATH}" >/dev/null 2>&1 || true
            sudo partprobe "${USB_DEVICE_PATH}" >/dev/null 2>&1 || true

            # Check to break the loop: if lsblk can query the device AND it's truly free
            if sudo lsblk -b "${USB_DEVICE_PATH}" &>/dev/null; then # Check if lsblk can successfully query the device
                if [ -z "$(sudo lsblk -rno MOUNTPOINT,FSTYPE "${USB_DEVICE_PATH}" | awk '$1 != "" || $2 != ""' || true)" ]; then
                    DEVICE_TRULY_FREE=true
                    break
                fi
            fi

            echo "Warning: ${USB_DEVICE_PATH} or its partitions still appear to be in use. Retrying in 2 seconds... (Attempt $((UNMOUNT_RETRY_COUNT + 1))/${MAX_UNMOUNT_RETRIES})" >&2
            sleep 2
            UNMOUNT_RETRY_COUNT=$((UNMOUNT_RETRY_COUNT + 1))
        done

        if [ "$DEVICE_TRULY_FREE" = "false" ]; then
            echo "Error: ${USB_DEVICE_PATH} remains busy after aggressive cleanup attempts. Cannot ensure complete device release." >&2
            all_unmounts_successful=false # Mark as overall failure if device stays busy
        else
            echo "Successfully ensured complete device release for ${USB_DEVICE_PATH}."
        fi
    fi

    # Attempt to remove temporary mount directories only if device is free
    if [ "$DEVICE_TRULY_FREE" = true ]; then
        for mp in "${mount_points_to_check[@]}"; do # Corrected: use mount_points_to_check
            if [ -d "${mp}" ]; then
                echo "Removing temporary directory ${mp}..." >&2
                sudo rmdir "${mp}" || echo "Warning: Could not remove ${mp}. It might not be empty (due to device busy or other error)." >&2
            fi
        done
    else
        echo "Warning: Not removing temporary mount directories due to device remaining busy. Please check and remove manually if necessary." >&2
    fi

    echo "Cleanup complete."
}

# Trap to ensure cleanup runs on exit
trap cleanup_validation_mounts EXIT

# --- Main Script ---

check_dependencies

echo "----------------------------------------------------" >&2
echo "  USB ISO Validation Script" >&2
echo "----------------------------------------------------" >&2

# 1. Select USB Drive
echo "----------------------------------------------------" >&2
echo "  Step 1/5: Selecting USB Device" >&2
echo "----------------------------------------------------" >&2
echo "Scanning for connected USB devices..." >&2
declare -a USB_DEVICES_PATHS
declare -a USB_DEVICES_DISPLAY

OPTION_NUM=1
for sys_device in /sys/block/sd*; do
    DEVICE_NAME=$(basename "${sys_device}")
    TARGET_DEV_CANDIDATE="/dev/${DEVICE_NAME}"

    # Check if it's a removable device
    if [[ -f "${sys_device}/removable" ]] && [[ "$(cat "${sys_device}/removable")" -eq 1 ]]; then
        # Check if it's a whole disk (not a partition)
        DEVICE_TYPE=$(lsblk -dn -o TYPE "${TARGET_DEV_CANDIDATE}" 2>/dev/null || true)
        if [[ "${DEVICE_TYPE}" == "disk" ]]; then
            # Ensure it's not the OS root disk
            ROOT_DEV=$(df -P / | awk 'NR==2 {print $1}')
            if [[ "${ROOT_DEV}" == "${TARGET_DEV_CANDIDATE}"* ]]; then
                continue # Skip if it\'s the OS root disk or a partition of it
            fi

            DEVICE_SIZE=$(lsblk -dn -o SIZE "${TARGET_DEV_CANDIDATE}" 2>/dev/null || true)
            DEVICE_VENDOR=$(lsblk -dn -o VENDOR "${TARGET_DEV_CANDIDATE}" 2>/dev/null || true)
            DEVICE_MODEL=$(lsblk -dn -o MODEL "${TARGET_DEV_CANDIDATE}" 2>/dev/null || true)

            # Find the persistent /dev/disk/by-id path for a more stable identification
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
                USB_DEVICES_PATHS+=("${TARGET_DEV_CANDIDATE}")
                USB_DEVICES_DISPLAY+=("${OPTION_NUM}) ${BY_ID_PATH} (-> ${TARGET_DEV_CANDIDATE}) - ${DEVICE_SIZE} ${DEVICE_VENDOR} ${DEVICE_MODEL}")
                OPTION_NUM=$((OPTION_NUM+1))
            fi
        fi
    fi
done

mapfile -t USB_DEVICES < <(printf "%s\n" "${USB_DEVICES_DISPLAY[@]}")


if [ ${#USB_DEVICES[@]} -eq 0 ]; then
    echo "Error: No USB devices found. Exiting." >&2
    exit 1
fi

echo "Available USB devices:" >&2
for i in "${!USB_DEVICES[@]}"; do
    echo "$((i+1)). ${USB_DEVICES[$i]}" >&2
done

while true; do
    read -p "Enter the number of the USB device to validate: " selection >&2
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#USB_DEVICES[@]}" ]; then
        USB_DEVICE_PATH="${USB_DEVICES_PATHS[$((selection-1))]}"
        echo "Selected USB device: $USB_DEVICE_PATH" >&2
        break
    else
        echo "Error: Invalid selection. Please enter a number between 1 and ${#USB_DEVICES[@]}." >&2
    fi
done

# Ensure the selected USB device is unmounted before proceeding
echo "Ensuring selected USB device ${USB_DEVICE_PATH} is unmounted to start with a clean state." >&2
sudo "${PROJECT_ROOT}/scripts/linux/unmount_target_disk.sh" "${USB_DEVICE_PATH}" || {
    echo "Error: Failed to unmount ${USB_DEVICE_PATH}. Please ensure no files are open on the device and try again." >&2
    exit 1
}

echo "Proceeding to validate the USB device $USB_DEVICE_PATH. This will attempt to mount partitions." >&2
if ! confirm_action; then
    echo "Action cancelled. Exiting." >&2
    exit 0
fi

# 2. Identify Partitions
echo "----------------------------------------------------" >&2
echo "  Step 2/5: Identifying Partitions" >&2
echo "----------------------------------------------------" >&2
EFI_PARTITION=""
WIN_PARTITION=""

echo "Identifying partitions on $USB_DEVICE_PATH..." >&2
mapfile -t PARTITIONS < <(lsblk -fn -o NAME,FSTYPE,MOUNTPOINT "$USB_DEVICE_PATH" | grep -v '^loop')

for part_info in "${PARTITIONS[@]}"; do
    PART_NAME="/dev/$(echo "$part_info" | awk '{print $1}' | sed -e 's/^[├└─ ]*//')"
    FSTYPE=$(echo "$part_info" | awk '{print $2}')
    
    if [[ "$FSTYPE" == "vfat" ]]; then # EFI partition is typically FAT32 (vfat)
        EFI_PARTITION="$PART_NAME"
        echo "Found EFI (FAT32) partition: $EFI_PARTITION" >&2
    elif [[ "$FSTYPE" == "ntfs" ]]; then # Windows partition is typically NTFS
        WIN_PARTITION="$PART_NAME"
        echo "Found Windows (NTFS) partition: $WIN_PARTITION" >&2
    fi
done

if [ -z "$EFI_PARTITION" ]; then
    echo "Error: Could not find an EFI (FAT32) partition on $USB_DEVICE_PATH. Exiting." >&2
    exit 1
fi

if [ -z "$WIN_PARTITION" ]; then
    echo "Error: Could not find a Windows (NTFS) partition on $USB_DEVICE_PATH. Exiting." >&2
    exit 1
fi

# 3. Mount Partitions for Validation
echo "----------------------------------------------------" >&2
echo "  Step 3/5: Mounting Partitions for Validation" >&2
echo "----------------------------------------------------" >&2
mount_partitions_and_iso_for_validation "${EFI_PARTITION}" "${WIN_PARTITION}"

echo "----------------------------------------------------" >&2
echo "  Step 4/5: Starting Validation Checks" >&2
echo "----------------------------------------------------" >&2
VALIDATION_FAILURES=0

# Helper function for checks
perform_check() {
    local type="$1"
    local path="$2"
    local description="$3"
    
    echo -n "Checking $description: " >&2
    if [ "$type" == "file" ]; then
        if [ -f "$path" ]; then
            echo "[SUCCESS]" >&2
        else
            echo "[FAILURE] File not found: $path" >&2
            VALIDATION_FAILURES=$((VALIDATION_FAILURES + 1))
        fi
    elif [ "$type" == "dir" ]; then
        if [ -d "$path" ]; then
            echo "[SUCCESS]" >&2
        else
            echo "[FAILURE] Directory not found: $path" >&2
            VALIDATION_FAILURES=$((VALIDATION_FAILURES + 1))
        fi
    else
        echo "[ERROR] Invalid check type: $type" >&2
    fi
}

# 4. Perform EFI Partition Checks (FAT32)
echo "" >&2
echo "----------------------------------------------------" >&2
echo "  Sub-step 4.1: EFI Partition Checks ($EFI_PART_MOUNT_POINT)" >&2
echo "----------------------------------------------------" >&2
perform_check "dir" "$EFI_PART_MOUNT_POINT/EFI" "Presence of EFI/ directory"
perform_check "file" "$EFI_PART_MOUNT_POINT/EFI/BOOT/bootx64.efi" "Presence of EFI/BOOT/bootx64.efi"
perform_check "file" "$EFI_PART_MOUNT_POINT/EFI/Microsoft/Boot/BCD" "Presence of EFI/Microsoft/Boot/BCD"

# 5. Perform Windows Partition Checks (NTFS)
echo "" >&2
echo "----------------------------------------------------" >&2
echo "  Sub-step 4.2: Windows Partition Checks ($WIN_PART_MOUNT_POINT)" >&2
echo "----------------------------------------------------" >&2
perform_check "dir" "$WIN_PART_MOUNT_POINT/sources" "Presence of sources/ directory"
if [ -f "$WIN_PART_MOUNT_POINT/sources/install.wim" ] || [ -f "$WIN_PART_MOUNT_POINT/sources/install.esd" ]; then
    echo "Checking Presence of sources/install.wim OR sources/install.esd: [SUCCESS]" >&2
else
    echo "Checking Presence of sources/install.wim OR sources/install.esd: [FAILURE] Neither install.wim nor install.esd found in sources/" >&2
    VALIDATION_FAILURES=$((VALIDATION_FAILURES + 1))
fi
perform_check "file" "${WIN_PART_MOUNT_POINT}/Windows/Panther/unattend.xml" "Presence of unattend.xml"
perform_check "dir" "$WIN_PART_MOUNT_POINT/AutomationKit" "Presence of AutomationKit/ directory"
perform_check "dir" "$WIN_PART_MOUNT_POINT/AutomationKit/common" "Presence of AutomationKit/common/"
perform_check "dir" "$WIN_PART_MOUNT_POINT/AutomationKit/sysprep" "Presence of AutomationKit/sysprep/"
perform_check "dir" "$WIN_PART_MOUNT_POINT/AutomationKit/drivers" "Presence of AutomationKit/drivers/"
perform_check "dir" "$WIN_PART_MOUNT_POINT/AutomationKit/tools" "Presence of AutomationKit/tools/"
perform_check "file" "$WIN_PART_MOUNT_POINT/AutomationKit/tools/incidium-remote-access.msi" "Presence of AutomationKit/tools/incidium-remote-access.msi"

echo "" >&2
echo "----------------------------------------------------" >&2
echo "  Step 5/5: Validation Summary" >&2
echo "----------------------------------------------------" >&2
if [ "$VALIDATION_FAILURES" -eq 0 ]; then
    echo "[VALIDATION SUCCESS] All checks passed." >&2
else
    echo "[VALIDATION FAILURE] $VALIDATION_FAILURES checks failed." >&2
    exit 1
fi

exit 0
