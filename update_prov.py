import os

file_path = '/home/m1ck5k1/dev/clonezilla/provision_machine.sh'

with open(file_path, 'r') as f:
    content = f.read()

# Add Argus payload variables to the top
old_vars = """MSI_FILE="incidium-remote-access.msi\""""
new_vars = """MSI_FILE="incidium-remote-access.msi"
ARGUS_EXE="../argus/argus.exe"
ARGUS_CMD="../argus/run_argus.cmd\""""

content = content.replace(old_vars, new_vars)

# Inject the Argus file transfer and setup right before fix_argus_window.ps1 execution
old_argus_block = """# 4.6. Setup Wi-Fi
echo "[4.6/5] Configuring Wi-Fi Profile 'm1ck5k1'..."
sshpass -p "$PASS" scp -P $PORT -o StrictHostKeyChecking=no setup_wifi.ps1 $USER@$TARGET_IP:C:/Temp/setup_wifi.ps1
sshpass -p "$PASS" scp -P $PORT -o StrictHostKeyChecking=no fix_argus_window.ps1 $USER@$TARGET_IP:C:/Temp/fix_argus_window.ps1
sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no $USER@$TARGET_IP "powershell -ExecutionPolicy Bypass -File C:/Temp/setup_wifi.ps1\""""

new_argus_block = """# 4.6. Setup Wi-Fi & Argus Payload
echo "[4.6/5] Transferring Argus Payload & Configuring Wi-Fi..."
sshpass -p "$PASS" scp -P $PORT -o StrictHostKeyChecking=no setup_wifi.ps1 $USER@$TARGET_IP:C:/Temp/setup_wifi.ps1
sshpass -p "$PASS" scp -P $PORT -o StrictHostKeyChecking=no fix_argus_window.ps1 $USER@$TARGET_IP:C:/Temp/fix_argus_window.ps1
sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no $USER@$TARGET_IP "powershell -ExecutionPolicy Bypass -File C:/Temp/setup_wifi.ps1"

# Transfer Argus binaries if they exist locally
if [ -f "$ARGUS_EXE" ]; then
    echo "Installing Argus..."
    sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no $USER@$TARGET_IP "powershell -Command \\"New-Item -Path 'C:/Temp/Argus' -ItemType Directory -Force | Out-Null\\""
    sshpass -p "$PASS" scp -P $PORT -o StrictHostKeyChecking=no "$ARGUS_EXE" $USER@$TARGET_IP:C:/Temp/Argus/argus.exe
    sshpass -p "$PASS" scp -P $PORT -o StrictHostKeyChecking=no "$ARGUS_CMD" $USER@$TARGET_IP:C:/Temp/Argus/run_argus.cmd
    sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no $USER@$TARGET_IP "powershell -Command \\"New-Item -Path 'C:/Program Files/Argus' -ItemType Directory -Force | Out-Null; Copy-Item -Path 'C:/Temp/Argus/*' -Destination 'C:/Program Files/Argus/' -Recurse -Force\\""
    sshpass -p "$PASS" ssh -p $PORT -o StrictHostKeyChecking=no $USER@$TARGET_IP "powershell -ExecutionPolicy Bypass -File C:/Temp/fix_argus_window.ps1"
else
    echo "Warning: $ARGUS_EXE not found locally. Skipping Argus transfer."
fi"""

content = content.replace(old_argus_block, new_argus_block)

with open(file_path, 'w') as f:
    f.write(content)
