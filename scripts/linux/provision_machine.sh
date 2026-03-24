#!/bin/bash

# Usage: ./provision_machine.sh <TARGET_IP> [NEW_HOSTNAME]
TARGET_IP=$1
NEW_HOSTNAME=$2
USER="ds"
PASS="547Mark!"
PORT="65122"
MSI_FILE="incidium-remote-access.msi"
ARGUS_EXE="../argus/argus.exe"
ARGUS_CMD="../argus/run_argus.cmd"

if [ -z "$TARGET_IP" ]; then
    echo "Usage: $0 <TARGET_IP> [NEW_HOSTNAME]"
    exit 1
fi

echo "=========================================================="
if [ -n "$NEW_HOSTNAME" ]; then
    echo "Starting Provisioning for: $TARGET_IP -> $NEW_HOSTNAME"
else
    echo "Starting Updates (No Rename) for: $TARGET_IP"
fi
echo "=========================================================="

# 1. Check Connectivity
echo "[1/5] Checking SSH Connection..."
sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no -o ConnectTimeout=5 $USER@$TARGET_IP "echo Connection OK" 
if [ $? -ne 0 ]; then
    echo "Error: Could not connect to $TARGET_IP. Is OpenSSH installed?"
    exit 1
fi

# 2. Create Temp Dir & Transfer Files
echo "[2/5] Transferring Files (MSI + Scripts)..."
sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no $USER@$TARGET_IP "powershell -Command \"New-Item -Path 'C:/Temp' -ItemType Directory -Force | Out-Null\""

# Transfer MSI
if [ -f "$MSI_FILE" ]; then
    sshpass -p "$PASS" scp -P $PORT -o StrictHostKeyChecking=no "$MSI_FILE" $USER@$TARGET_IP:C:/Temp/incidium-remote-access.msi
else
    echo "Warning: MSI file '$MSI_FILE' not found locally! Skipping RustDesk transfer."
fi

# 2.5. Transfer Argus binaries (if exist) & Consolidated Script
echo "[2.5/5] Transferring Argus Payload & Consolidated Script..."

if [ -f "$ARGUS_EXE" ]; then
    echo "Installing Argus..."
    sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no $USER@$TARGET_IP "powershell -Command \"New-Item -Path 'C:/Temp/Argus' -ItemType Directory -Force | Out-Null\""
    sshpass -p "$PASS" scp -P $PORT -o StrictHostKeyChecking=no "$ARGUS_EXE" $USER@$TARGET_IP:C:/Temp/Argus/argus.exe
    sshpass -p "$PASS" scp -P $PORT -o StrictHostKeyChecking=no "$ARGUS_CMD" $USER@$TARGET_IP:C:/Temp/Argus/run_argus.cmd
    sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no $USER@$TARGET_IP "powershell -Command \"New-Item -Path 'C:/Program Files/Argus' -ItemType Directory -Force | Out-Null; Copy-Item -Path 'C:/Temp/Argus/*' -Destination 'C:/Program Files/Argus/' -Recurse -Force\""

else
    echo "Warning: $ARGUS_EXE not found locally. Skipping Argus transfer."
fi

# Transfer Consolidated Script and Custom Power Plan
sshpass -p "$PASS" scp -P $PORT -o StrictHostKeyChecking=no post-os-install.ps1 $USER@$TARGET_IP:C:/Temp/post-os-install.ps1
if [ -f "SnakeSpeareV6/engine/Incidium.pow" ]; then
    sshpass -p "$PASS" scp -P $PORT -o StrictHostKeyChecking=no SnakeSpeareV6/engine/Incidium.pow $USER@$TARGET_IP:C:/Temp/incidium.pow
else
    echo "Warning: SnakeSpeareV6/engine/Incidium.pow not found locally. Custom power plan import will be skipped."
fi

# 3. Run Post-OS Installation Script
echo "[3/5] Running Consolidated Post-OS Installation Script..."
sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no $USER@$TARGET_IP "powershell -ExecutionPolicy Bypass -File C:/Temp/post-os-install.ps1"

# 4. Transfer SnakeSpeareV6
echo "[4/5] Transferring SnakeSpeareV6 to C:\SnakeSpeareV6..."
sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no $USER@$TARGET_IP "powershell -Command \"New-Item -Path 'C:/SnakeSpeareV6' -ItemType Directory -Force | Out-Null\""
sshpass -p "$PASS" scp -P $PORT -r -o StrictHostKeyChecking=no SnakeSpeareV6/ $USER@$TARGET_IP:C:/SnakeSpeareV6/

# 5. Check RustDesk ID & Argus
echo "[5/5] Checking RustDesk & Argus Status..."
sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no $USER@$TARGET_IP "powershell -Command \"Write-Host '--- STATUS ---'; Get-Service RustDesk, 'Incidium-Remote-Access', Argus* -ErrorAction SilentlyContinue | Format-Table -AutoSize; \$cfg = 'C:\Users\ds\AppData\Roaming\RustDesk\config\RustDesk.toml'; if (Test-Path \$cfg) { Select-String -Path \$cfg -Pattern 'id = ' } else { Write-Warning 'RustDesk Config not found (Run manually to generate ID)' }\""

# 5. Rename & Restart (Optional)
if [ -n "$NEW_HOSTNAME" ]; then
    echo "[6/6] Renaming to '$NEW_HOSTNAME' and Restarting..."
    sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no $USER@$TARGET_IP "powershell -Command \"Rename-Computer -NewName '$NEW_HOSTNAME' -Force; Restart-Computer -Force\""
    echo "Provisioning Complete! Machine is rebooting."
else
    echo "[5/5] Skipping Rename/Restart (No hostname provided)."
    echo "Updates Complete!"
fi
echo "=========================================================="
