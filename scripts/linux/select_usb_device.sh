#!/bin/bash

# --- Configuration ---
PROJECT_ROOT="/home/m1ck5k1/dev/windows-automation-toolkit"

# --- Functions ---

# Function to check for required tools
check_dependencies() {
    echo "Checking dependencies..." >&2
    REQUIRED_TOOLS="lsblk sudo readlink grep awk basename dirname head tail wc test"
    for tool in $REQUIRED_TOOLS; do
        if ! command -v "$tool" &> /dev/null; then
            echo "Error: Required tool '$tool' is not installed. Please install it (e.g., 'sudo apt install $tool' or 'sudo apt install util-linux') and try again." >&2
            exit 1
        fi
    done
    echo "All dependencies checked." >&2
}

# --- Main Script ---

# Exit immediately if a command exits with a non-zero status.
set -e

check_dependencies

TARGET_DISK=""
SELECTED_BY_ID=""

echo "----------------------------------------------------" >&2
echo "  Select Target USB Drive" >&2
echo "----------------------------------------------------" >&2
echo "Available Removable Disks:" >&2

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
                echo "${OPTION_NUM}) ${BY_ID_PATH} (-> ${TARGET_DEV_CANDIDATE}) - ${DEVICE_SIZE}" >&2
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
    read -p "Enter the number of your TARGET USB drive: " SELECTED_NUM >&2
    if [[ "$SELECTED_NUM" =~ ^[0-9]+$ ]] && [ "$SELECTED_NUM" -ge 1 ] && [ "$SELECTED_NUM" -le ${#DISK_OPTIONS[@]} ]; then
        TARGET_DISK="${DISK_OPTIONS[SELECTED_NUM-1]}"
        SELECTED_BY_ID="${DISK_BY_ID_MAP[SELECTED_NUM-1]}"
        echo "Selected target disk: ${TARGET_DISK} (via ${SELECTED_BY_ID})" >&2
        echo "For physical labeling, please use this ID: ${SELECTED_BY_ID}" >&2
        VALID_SELECTION=1
    else
        echo "Error: Invalid selection. Please enter a number from 1 to ${#DISK_OPTIONS[@]} ." >&2
        VALID_SELECTION=0
    fi
done

echo "${TARGET_DISK}"
echo "${SELECTED_BY_ID}" # Raw output for orchestrator

