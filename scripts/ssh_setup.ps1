# 1. Install OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# 2. Update Configuration to Port 65122
$configPath = "$env:ProgramData\ssh\sshd_config"
if (Test-Path $configPath) {
    (Get-Content $configPath) -replace '#Port 22', 'Port 65122' -replace 'Port 22', 'Port 65122' | Set-Content $configPath
}

# 3. Configure Windows Firewall
New-NetFirewallRule -Name "OpenSSH-65122" -DisplayName "OpenSSH Server (Port 65122)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 65122

# 4. Cleanup default Port 22 rule for security
Disable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue

# 5. Start Services
Set-Service -Name sshd -StartupType 'Automatic'
Start-Service sshd