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

    echo "Attempting to mount ${description} (${device}) to ${mount_point} with options '$options'..."
    if sudo mount -o "$options" "$device" "$mount_point"; then
        echo "Successfully mounted ${description} (${device}) to ${mount_point}."
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

    echo "Creating temporary mount points..."
    sudo mkdir -p "${EFI_PART_MOUNT_POINT}" || { echo "Error: Failed to create EFI mount point."; exit 1; }
    sudo mkdir -p "${WIN_PART_MOUNT_POINT}" || { echo "Error: Failed to create Windows mount point."; exit 1; }

    echo "Mounting partitions for validation..."
    if ! safe_mount "${efi_part}" "${EFI_PART_MOUNT_POINT}" "ro" "EFI Partition"; then
        exit 1
    fi

    if ! safe_mount "${win_part}" "${WIN_PART_MOUNT_POINT}" "ro" "Windows Partition"; then # Mount read-only for validation
        exit 1
    fi
}

# Function to cleanup validation mounts and temporary directories
cleanup_validation_mounts() {
    echo "Performing validation cleanup..."
    local all_unmounts_successful=true

    local -a mount_points_to_check=("${EFI_PART_MOUNT_POINT}" "${WIN_PART_MOUNT_POINT}")

    for mp in "${mount_points_to_check[@]}"; do
        if grep -qs "^${mp} " /proc/mounts; then
            echo "Attempting to unmount ${mp}..."
            if sudo umount -f -l "${mp}"; then
                echo "Successfully unmounted ${mp}."
            else
                local UMOUNT_EXIT_CODE=$?
                if [ ${UMOUNT_EXIT_CODE} -ne 0 ] && [ ${UMOUNT_EXIT_CODE} -ne 32 ]; then
                    echo "Warning: Forceful unmount of ${mp} failed (exit code ${UMOUNT_EXIT_CODE}). Checking for lingering processes." >&2
                    if fuser -m "${mp}" &>/dev/null; then
                        echo "Killing processes using ${mp}... (fuser -mk)"
                        sudo fuser -mk "${mp}" || true
                        sleep 1
                        echo "Retrying unmount of ${mp} after killing processes..."
                        if sudo umount -f -l "${mp}"; then
                            echo "Successfully unmounted ${mp} after killing processes."
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
            echo "${mp} is not mounted."
        fi
    done

    sync
    sleep 1

    if [ -n "${USB_DEVICE_PATH}" ]; then
        echo "Flushing block device buffers for ${USB_DEVICE_PATH}..."
        sudo blockdev --flushbufs "${USB_DEVICE_PATH}" || true
    fi
    sleep 2

    if [ "$all_unmounts_successful" = true ]; then
        for mp in "${mount_points_to_check[@]}"; do
            if [ -d "${mp}" ]; then
                echo "Removing temporary directory ${mp}..."
                sudo rmdir "${mp}" || true
            fi
        done
    else
        echo "Warning: Not removing temporary mount directories due to unmount failures. Please check and remove manually if necessary." >&2
    fi

    echo "Cleanup complete."
}

# Trap to ensure cleanup runs on exit
trap cleanup_validation_mounts EXIT

# --- Main Script ---

check_dependencies

echo "--- USB ISO Validation Script ---"

# 1. Select USB Drive
echo "Scanning for connected USB devices..."
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
    echo "No USB devices found. Exiting."
    exit 1
fi

echo "Available USB devices:"
for i in "${!USB_DEVICES[@]}"; do
    echo "$((i+1)). ${USB_DEVICES[$i]}"
done

while true; do
    read -p "Enter the number of the USB device to validate: " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#USB_DEVICES[@]}" ]; then
        USB_DEVICE_PATH="${USB_DEVICES_PATHS[$((selection-1))]}"
        echo "Selected USB device: $USB_DEVICE_PATH"
        break
    else
        echo "Invalid selection. Please enter a number between 1 and ${#USB_DEVICES[@]}."
    fi
done

# Ensure the selected USB device is unmounted before proceeding
echo "Ensuring selected USB device ${USB_DEVICE_PATH} is unmounted to start with a clean state."
sudo "${PROJECT_ROOT}/scripts/linux/unmount_target_disk.sh" "${USB_DEVICE_PATH}" || {
    echo "Error: Failed to unmount ${USB_DEVICE_PATH}. Please ensure no files are open on the device and try again." >&2
    exit 1
}

echo "Proceeding to validate the USB device $USB_DEVICE_PATH. This will attempt to mount partitions."
if ! confirm_action; then
    echo "Action cancelled. Exiting."
    exit 0
fi

# 2. Identify Partitions
EFI_PARTITION=""
WIN_PARTITION=""

echo "Identifying partitions on $USB_DEVICE_PATH..."
mapfile -t PARTITIONS < <(lsblk -fn -o NAME,FSTYPE,MOUNTPOINT "$USB_DEVICE_PATH" | grep -v '^loop')

for part_info in "${PARTITIONS[@]}"; do
    PART_NAME="/dev/$(echo "$part_info" | awk '{print $1}' | sed -e 's/^[├└─ ]*//')"
    FSTYPE=$(echo "$part_info" | awk '{print $2}')
    
    if [[ "$FSTYPE" == "vfat" ]]; then # EFI partition is typically FAT32 (vfat)
        EFI_PARTITION="$PART_NAME"
        echo "Found EFI (FAT32) partition: $EFI_PARTITION"
    elif [[ "$FSTYPE" == "ntfs" ]]; then # Windows partition is typically NTFS
        WIN_PARTITION="$PART_NAME"
        echo "Found Windows (NTFS) partition: $WIN_PARTITION"
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

# Call mount function
mount_partitions_and_iso_for_validation "${EFI_PARTITION}" "${WIN_PARTITION}"

echo "--- Starting Validation Checks ---"
VALIDATION_FAILURES=0

# Helper function for checks
perform_check() {
    local type="$1"
    local path="$2"
    local description="$3"
    
    echo -n "Checking $description: "
    if [ "$type" == "file" ]; then
        if [ -f "$path" ]; then
            echo "[SUCCESS]"
        else
            echo "[FAILURE] File not found: $path" >&2
            VALIDATION_FAILURES=$((VALIDATION_FAILURES + 1))
        fi
    elif [ "$type" == "dir" ]; then
        if [ -d "$path" ]; then
            echo "[SUCCESS]"
        else
            echo "[FAILURE] Directory not found: $path" >&2
            VALIDATION_FAILURES=$((VALIDATION_FAILURES + 1))
        fi
    else
        echo "[ERROR] Invalid check type: $type" >&2
    fi
}

# 5. Perform EFI Partition Checks (FAT32)
echo ""
echo "--- EFI Partition Checks ($EFI_MOUNT_POINT) ---"
perform_check "dir" "$EFI_MOUNT_POINT/EFI" "Presence of EFI/ directory"
perform_check "file" "$EFI_MOUNT_POINT/EFI/BOOT/bootx64.efi" "Presence of EFI/BOOT/bootx64.efi"
perform_check "file" "$EFI_MOUNT_POINT/EFI/Microsoft/Boot/BCD" "Presence of EFI/Microsoft/Boot/BCD"

# 6. Perform Windows Partition Checks (NTFS)
echo ""
echo "--- Windows Partition Checks ($WIN_MOUNT_POINT) ---"
perform_check "dir" "$WIN_MOUNT_POINT/sources" "Presence of sources/ directory"
if [ -f "$WIN_MOUNT_POINT/sources/install.wim" ] || [ -f "$WIN_MOUNT_POINT/sources/install.esd" ]; then
    echo "Checking Presence of sources/install.wim OR sources/install.esd: [SUCCESS]"
else
    echo "Checking Presence of sources/install.wim OR sources/install.esd: [FAILURE] Neither install.wim nor install.esd found in sources/" >&2
    VALIDATION_FAILURES=$((VALIDATION_FAILURES + 1))
fi
perform_check "file" "${WIN_MOUNT_POINT}/Windows/Panther/unattend.xml" "Presence of unattend.xml"
perform_check "dir" "$WIN_MOUNT_POINT/AutomationKit" "Presence of AutomationKit/ directory"
perform_check "dir" "$WIN_MOUNT_POINT/AutomationKit/common" "Presence of AutomationKit/common/"
perform_check "dir" "$WIN_MOUNT_POINT/AutomationKit/sysprep" "Presence of AutomationKit/sysprep/"
perform_check "dir" "$WIN_MOUNT_POINT/AutomationKit/drivers" "Presence of AutomationKit/drivers/"
perform_check "dir" "$WIN_MOUNT_POINT/AutomationKit/tools" "Presence of AutomationKit/tools/"
perform_check "file" "$WIN_MOUNT_POINT/AutomationKit/tools/incidium-remote-access.msi" "Presence of AutomationKit/tools/incidium-remote-access.msi"

echo ""
echo "--- Validation Summary ---"
if [ "$VALIDATION_FAILURES" -eq 0 ]; then
    echo "[VALIDATION SUCCESS] All checks passed."
else
    echo "[VALIDATION FAILURE] $VALIDATION_FAILURES checks failed." >&2
    exit 1
fi

exit 0
