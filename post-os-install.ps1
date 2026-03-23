# post-os-install.ps1
# This script consolidates all post-OS installation and configuration steps.
# It is designed to be run once a fresh Windows installation is complete,
# typically by the 'provision_machine.sh' script.

# Ensure script is run with Administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as Administrator!"
    Break
}

# Suppress progress bars for silent execution
$ProgressPreference = 'SilentlyContinue'

Write-Host "===========================================================" -ForegroundColor Green
Write-Host " Starting Consolidated Post-OS Installation Script" -ForegroundColor Green
Write-Host "===========================================================" -ForegroundColor Green
Write-Host ""

# --- Initial File Staging from USB (for local automation) ---
Write-Host "[Section 1/10] Staging necessary files from USB to local directories..." -ForegroundColor Cyan

$UsbScriptRoot = $PSScriptRoot # This is the directory of post-os-install.ps1 on the USB

# Create C:\Temp if it doesn't exist
$LocalTempPath = "C:\\Temp"
if (-not (Test-Path $LocalTempPath)) {
    New-Item -Path $LocalTempPath -ItemType Directory -Force | Out-Null
    Write-Host "Created $LocalTempPath." -ForegroundColor Gray
}

# Copy incidium-remote-access.msi
$SourceMsi = Join-Path $UsbScriptRoot "incidium-remote-access.msi"
$DestMsi = Join-Path $LocalTempPath "incidium-remote-access.msi"
if (Test-Path $SourceMsi) {
    Copy-Item -Path $SourceMsi -Destination $DestMsi -Force -ErrorAction SilentlyContinue
    Write-Host "Copied incidium-remote-access.msi to $LocalTempPath." -ForegroundColor Green
} else {
    Write-Warning "incidium-remote-access.msi not found on USB at $SourceMsi. RustDesk installation might fail."
}

# Copy Incidium.pow
$SourcePow = Join-Path $UsbScriptRoot "SnakeSpeareV6/engine/Incidium.pow"
$DestPow = Join-Path $LocalTempPath "incidium.pow" # Renaming to lowercase for consistency as per script's expectation
if (Test-Path $SourcePow) {
    Copy-Item -Path $SourcePow -Destination $DestPow -Force -ErrorAction SilentlyContinue
    Write-Host "Copied Incidium.pow to $LocalTempPath." -ForegroundColor Green
} else {
    Write-Warning "Incidium.pow not found on USB at $SourcePow. Custom power plan might not be applied."
}

# Copy SnakeSpeareV6 directory
$SourceSnakeSpeareV6 = Join-Path $UsbScriptRoot "SnakeSpeareV6"
$DestSnakeSpeareV6 = "C:\\SnakeSpeareV6"
if (Test-Path $SourceSnakeSpeareV6) {
    Copy-Item -Path $SourceSnakeSpeareV6 -Destination $DestSnakeSpeareV6 -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Copied SnakeSpeareV6 to $DestSnakeSpeareV6." -ForegroundColor Green
} else {
    Write-Warning "SnakeSpeareV6 folder not found on USB at $SourceSnakeSpeareV6. SnakeSpeareV6 installation might be incomplete."
}
Write-Host "Initial file staging from USB completed." -ForegroundColor Green
Write-Host ""

# --- Phase 1: Basic Setup (from install_openssh.ps1) ---
Write-Host "[Section 2/10] Installing OpenSSH Server and Creating Users..." -ForegroundColor Cyan

# Install OpenSSH Server and Client
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -ErrorAction SilentlyContinue

# Create Required Users
$Users = @(
    @{ Username="ds"; Password="547Mark!"; FullName="Digital Signage"; Description="Primary AutoLogin User" },
    @{ Username="m1ck5k1"; Password="Kal1L1nux!"; FullName="System Admin"; Description="Administrator" },
    @{ Username="support"; Password="1nc1d1um2006!"; FullName="Incidium Support"; Description="IT Support" }
)

foreach ($u in $Users) {
    $UserExists = Get-LocalUser -Name $u.Username -ErrorAction SilentlyContinue
    if (-not $UserExists) {
        Write-Host "Creating user $($u.Username)..." -ForegroundColor Cyan
        $SecurePassword = ConvertTo-SecureString $u.Password -AsPlainText -Force
        New-LocalUser -Name $u.Username -Password $SecurePassword -FullName $u.FullName -Description $u.Description
        Add-LocalGroupMember -Group "Administrators" -Member $u.Username
    } else {
        Write-Host "User $($u.Username) already exists. Skipping creation." -ForegroundColor Yellow
    }
}

# Configure SSH Service (Start service first to generate keys and config)
Write-Host "Configuring SSH Service..." -ForegroundColor Cyan
Start-Service sshd -ErrorAction SilentlyContinue # Start if not running
Set-Service -Name sshd -StartupType 'Automatic'

# Change Port to 65122
$ConfigPath = "$env:ProgramData\ssh\sshd_config"
if (-not (Test-Path $ConfigPath)) {
    # If config doesn't exist, restart service to generate it
    Restart-Service sshd
    Start-Sleep -Seconds 5
}

Write-Host "Updating sshd_config to Port 65122..." -ForegroundColor Cyan
if (Test-Path $ConfigPath) {
    Copy-Item $ConfigPath "$ConfigPath.bak" -Force

    $Content = Get-Content $ConfigPath
    $Content = $Content | Where-Object { $_ -notmatch "^\s*#?Port\s+\d+" }
    $NewContent = @("Port 65122") + $Content
    $NewContent | Set-Content $ConfigPath
} else {
    Write-Warning "sshd_config not found at $ConfigPath"
}

# Open Firewall Port
Write-Host "Opening Firewall Port 65122..." -ForegroundColor Cyan
Remove-NetFirewallRule -DisplayName "OpenSSH Server (TCP-65122)" -ErrorAction SilentlyContinue
New-NetFirewallRule -Name "OpenSSH-Server-In-TCP-65122" -DisplayName "OpenSSH Server (TCP-65122)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 65122

# Restart Service to apply changes
Write-Host "Restarting SSH Service..." -ForegroundColor Cyan
Restart-Service sshd

# Configure AutoLogin for user 'ds'
Write-Host "Configuring AutoLogin for user 'ds'..." -ForegroundColor Cyan
$RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty -Path $RegistryPath -Name "AutoAdminLogon" -Value "1"
Set-ItemProperty -Path $RegistryPath -Name "DefaultUserName" -Value "ds"
Set-ItemProperty -Path $RegistryPath -Name "DefaultPassword" -Value "547Mark!"
Set-ItemProperty -Path $RegistryPath -Name "DefaultDomainName" -Value "."
Write-Host "AutoLogin Enabled." -ForegroundColor Green
Write-Host ""

# --- Phase 2: Software Installation (from install_software.ps1) ---
Write-Host "[Section 3/10] Installing Chocolatey and Core Software..." -ForegroundColor Cyan

# Order of Operations Check: Chocolatey must be installed before 'choco install' commands.

# Cleanup Corrupted Install
$ChocoDir = "C:\ProgramData\chocolatey"
$ChocoBin = "$ChocoDir\bin\choco.exe"
if ((Test-Path $ChocoDir) -and -not (Test-Path $ChocoBin)) {
    Write-Warning "Corrupted Chocolatey install detected. Cleaning up..."
    Remove-Item -Path $ChocoDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Install Chocolatey
Write-Host "Installing Chocolatey..." -ForegroundColor Cyan
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Define Choco Path Explicitly (Fixes SSH Path issues for some environments)
if (-not (Test-Path $ChocoBin)) {
    Write-Warning "Chocolatey binary not found at $ChocoBin. Attempting standard 'choco' command."
    $ChocoBin = "choco"
}

# Install Chrome, VLC, Git
Write-Host "Installing Chrome, VLC, and Git..." -ForegroundColor Cyan
& $ChocoBin install googlechrome vlc git -y --force

# Install TightVNC (Latest) with Custom Config
Write-Host "Installing TightVNC with custom password..." -ForegroundColor Cyan
$VncArgs = 'ADDLOCAL="Server,Viewer" VIEWER_ASSOCIATE_VNC_EXTENSION=1 SERVER_REGISTER_AS_SERVICE=1 SERVER_ADD_FIREWALL_EXCEPTION=1 VIEWER_ADD_FIREWALL_EXCEPTION=1 SERVER_ALLOW_SAS=1 SET_USEVNCAUTHENTICATION=1 VALUE_OF_USEVNCAUTHENTICATION=1 SET_PASSWORD=1 VALUE_OF_PASSWORD=547Mark! SET_USECONTROLAUTHENTICATION=1 VALUE_OF_USECONTROLAUTHENTICATION=1 SET_CONTROLPASSWORD=1 VALUE_OF_CONTROLPASSWORD=547Mark!'
& $ChocoBin install tightvnc -y --install-arguments $VncArgs

# Install Custom RustDesk (MSI)
Write-Host "Installing Custom RustDesk..." -ForegroundColor Cyan
$MsiPath = "C:/Temp/incidium-remote-access.msi"
if (Test-Path $MsiPath) {
    Start-Process "msiexec.exe" -ArgumentList "/i `"$MsiPath`" /qn /norestart" -Wait
    Write-Host "RustDesk Installed." -ForegroundColor Green
} else {
    Write-Warning "RustDesk MSI not found at $MsiPath. Skipping installation."'
}
Write-Host ""

# --- Phase 2: System Debloating (from debloat_win10.ps1) ---
Write-Host "[Section 4/10] Starting Windows Debloat..." -ForegroundColor Cyan

# Apps to KEEP (Whitelist)
$Whitelist = @(
    "Microsoft.WindowsCalculator",
    "Microsoft.WindowsStore",
    "Microsoft.Windows.Photos",
    "Microsoft.WindowsCamera",
    "Microsoft.WindowsAlarms",
    "Microsoft.Paint",
    "Microsoft.MicrosoftStickyNotes",
    "Microsoft.DesktopAppInstaller", # App Installer (WinGet)
    "Microsoft.StorePurchaseApp",    # Store Purchase Support
    "Microsoft.WindowsSoundRecorder"
)

# Get All Provisioned Apps (For New Users)
$Provisioned = Get-AppxProvisionedPackage -Online
foreach ($App in $Provisioned) {
    $PackageName = $App.DisplayName
    if ($PackageName -in $Whitelist) {
        Write-Host "Skipping Whitelisted App: $PackageName" -ForegroundColor Gray
    }
    else {
        Write-Host "Removing Provisioned App: $PackageName" -ForegroundColor Yellow
        Remove-AppxProvisionedPackage -Online -PackageName $App.PackageName -ErrorAction SilentlyContinue
    }
}

# Get Current User Apps
$UserApps = Get-AppxPackage
foreach ($App in $UserApps) {
    $PackageName = $App.Name
    if ($App.IsFramework -or $PackageName -match "Microsoft.NET" -or $PackageName -match "Microsoft.VCLibs" -or $PackageName -match "Microsoft.UI.Xaml") {
        continue
    }

    if ($PackageName -in $Whitelist) {
        Write-Host "Skipping Whitelisted App: $PackageName" -ForegroundColor Gray
    }
    else {
        if ($App.NonRemovable) {
            Write-Host "Skipping System App: $PackageName" -ForegroundColor DarkGray
        } else {
            Write-Host "Removing User App: $PackageName" -ForegroundColor Magenta
            Remove-AppxPackage -Package $App.PackageFullName -ErrorAction SilentlyContinue
        }
    }
}

# Disable Consumer Features (Cloud Content / Sponsored Apps)
Write-Host "Disabling Consumer Features (Candy Crush etc.)..." -ForegroundColor Cyan
$RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (-not (Test-Path $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }
Set-ItemProperty -Path $RegistryPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord

# Disable Telemetry (Optional - Safe Level)
Write-Host "Setting Telemetry to Security Only..." -ForegroundColor Cyan
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord

# Remove OneDrive
Write-Host "Removing OneDrive..." -ForegroundColor Cyan
Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$OneDriveSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
if (-not (Test-Path $OneDriveSetup)) {
    $OneDriveSetup = "$env:SystemRoot\System32\OneDriveSetup.exe"
}
if (Test-Path $OneDriveSetup) {
    Start-Process $OneDriveSetup -ArgumentList "/uninstall" -Wait
    Start-Sleep -Seconds 5
}
Remove-Item -Path "$env:UserProfile\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:LocalAppData\Microsoft\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:ProgramData\Microsoft OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""

# --- Phase 2: Presentation Mode (from presentation_mode.ps1) ---
Write-Host "[Section 5/10] Configuring Presentation Mode (Power Settings)..." -ForegroundColor Cyan

# Set High Performance Power Plan
$HighPerf = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
powercfg -setactive $HighPerf

# Disable Sleep & Screen Off (AC + DC)
powercfg -change -monitor-timeout-ac 0
powercfg -change -monitor-timeout-dc 0
powercfg -change -standby-timeout-ac 0
powercfg -change -standby-timeout-dc 0
powercfg -change -hibernate-timeout-ac 0
powercfg -change -hibernate-timeout-dc 0

# Disable Hibernate File
powercfg -h off

# Disable Screensaver (Registry)
$RegPath = "HKCU:\Control Panel\Desktop"
if (-not (Test-Path $RegPath)) { New-Item -Path $RegPath -Force | Out-Null }
Set-ItemProperty -Path $RegPath -Name "ScreenSaveActive" -Value "0"
Set-ItemProperty -Path $RegPath -Name "ScreenSaverIsSecure" -Value "0"
if ((Get-ItemProperty -Path $RegPath).SCRNSAVE_EXE) {
    Remove-ItemProperty -Path $RegPath -Name "SCRNSAVE_EXE" -ErrorAction SilentlyContinue
}

# Prevent Sleep on Lid Close (If Laptop)
powercfg -setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg -setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg -SetActive SCHEME_CURRENT
Write-Host "Presentation Mode Active: No Sleep, No Screensaver, High Performance." -ForegroundColor Green
Write-Host ""

# --- Phase 2: Wi-Fi Setup (from setup_wifi.ps1) ---
Write-Host "[Section 6/10] Configuring Wi-Fi Profile..." -ForegroundColor Cyan

$SSID = "m1ck5k1"
$Password = "Kal1L1nux!"
$HexSSID = ($SSID.ToCharArray() | ForEach-Object { "{0:X2}" -f [int]$_ }) -join ""

$XmlProfile = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$SSID</name>
    <SSIDConfig>
        <SSID>
            <hex>$HexSSID</hex>
            <name>$SSID</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$Password</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@

$ProfilePath = "C:\Temp\wifi_profile.xml"
$XmlProfile | Out-File -FilePath $ProfilePath -Encoding ASCII
netsh wlan add profile filename="$ProfilePath"
Write-Host "Wi-Fi Profile '$SSID' Added." -ForegroundColor Green
Write-Host ""

# --- Phase 3: Argus Application Deployment (from fix_argus_window.ps1) ---
Write-Host "[Section 7/10] Configuring Argus Startup Task (Hidden)..." -ForegroundColor Cyan

# Create the VBScript Launcher (Forces Window Hide)
$VbsPath = "C:\Program Files\Argus\launch_argus.vbs"
if (-not (Test-Path "C:\Program Files\Argus")) { New-Item -Path "C:\Program Files\Argus" -ItemType Directory -Force | Out-Null }
$CmdPath = "C:\Program Files\Argusun_argus.cmd"

$VbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run chr(34) & "$CmdPath" & chr(34), 0
Set WshShell = Nothing
"@

Set-Content -Path $VbsPath -Value $VbsContent -Encoding Ascii
Write-Host "Created VBS Launcher at $VbsPath" -ForegroundColor Cyan

# Re-Register Task to use WScript (Invisible)
$TaskName = "ArgusAgent"
$User = "ds"

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $User
$Action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$VbsPath`""
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0) -Priority 1

Register-ScheduledTask -TaskName $TaskName -Trigger $Trigger -Action $Action -Settings $Settings -User $User -RunLevel Highest
Write-Host "Task Updated to use VBS (Invisible)." -ForegroundColor Green

# Kill Existing Process & Restart
Write-Host "Closing visible Argus window..." -ForegroundColor Cyan
Stop-Process -Name "argus" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "cmd" -Force -ErrorAction SilentlyContinue

Start-Sleep -Seconds 1
Start-ScheduledTask -TaskName $TaskName
Write-Host "Argus Restarted (Hidden)." -ForegroundColor Green
Write-Host ""

# --- Phase 4 (Partial): Network Configuration ---
Write-Host "[Section 8/10] Configuring Network Category for Ethernet Adapters..." -ForegroundColor Cyan

# Find all Ethernet adapters that are currently 'Public' and set them to 'Private'
Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' -and $_.InterfaceAlias -like '*Ethernet*' } | ForEach-Object {
    Write-Host "Setting 'Public' NetworkCategory to 'Private' for Interface: $($_.InterfaceAlias)" -ForegroundColor Yellow
    Set-NetConnectionProfile -InterfaceAlias $_.InterfaceAlias -NetworkCategory Private -ErrorAction SilentlyContinue
}
Write-Host "Network category configuration attempted." -ForegroundColor Green
Write-Host ""

# --- Phase 4: Service Optimization ---
Write-Host "[Section 9/10] Optimizing Windows Services (Disabling unnecessary services)..." -ForegroundColor Cyan

$ServicesToOptimize = @(
    "Spooler",           # Print Spooler
    "Fax",               # Fax
    "RemoteRegistry",    # Remote Registry
    "WSearch",           # Windows Search
    "WerSvc",            # Problem Reports and Solutions Control Panel Support
    "lfsvc",             # Geolocation Service
    "bthserv",           # Bluetooth Support Service
    "SensrSvc",          # Sensor Monitoring Service
    "TabletInputService",# TabletInputService
    "TabletInputService",# Touch Keyboard and Handwriting Panel Service (same service name, but for clarity)
    "WbioSrvc",          # Windows Biometric Service
    "SCardSvr",          # Smart Card
    "SCPolicySvc",       # Smart Card Device Enumeration Service
    "HomeGroupProvider", # HomeGroup Provider
    "p2pimsvc",          # Peer Networking Grouping
    "pnrpsvc",           # Peer Name Resolution Protocol
    "p2psvc",            # Peer Networking Identity Manager
    "SSDPSRV",           # SSDP Discovery
    "upnphost",          # UPnP Device Host
    "XboxGipSvc",        # Xbox Accessory Management Service
    "GamingServices",    # Gaming Services
    "dozs",              # Delivery Optimization
    "dmwappushsvc",      # WAP Push Message Routing Service
    "CDPUserSvc",        # Connected Devices Platform User Service
    "MapsBroker"         # Downloaded Maps Manager
)

foreach ($serviceName in $ServicesToOptimize) {
    try {
        $service = Get-Service -Name $serviceName -ErrorAction Stop
        if ($service.Status -ne "Stopped") {
            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
            Write-Host "Stopped service: $serviceName" -ForegroundColor Yellow
        }
        Set-Service -Name $serviceName -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "Disabled service: $serviceName" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Service '$serviceName' not found or could not be processed. $($_.Exception.Message)"
    }
}
Write-Host \"Windows service optimization attempted.\" -ForegroundColor Green\nWrite-Host \"\"\n\n# --- Custom Configuration: Registry Tweaks, Time Sync, Custom Power Plan, Firewall Rules, Shortcuts ---\nWrite-Host \"[Section 9/9] Applying Custom Registry Tweaks, Time Sync, Power Plan, Firewall Rules, and Shortcuts...\" -ForegroundColor Cyan\n\n# Registry Tweaks\n# Change Start Menu Power Button to default to Restart\nSet-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\" -Name \"Start_PowerButtonAction\" -Value 4 -Force -ErrorAction SilentlyContinue\n# Disable Action Center Icon\nSet-ItemProperty -Path \"HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer\" -Name \"HideSCAHealth\" -Value 1 -Force -ErrorAction SilentlyContinue\n# Disable AdobeAIR Updates\nSet-ItemProperty -Path \"HKLM:\\Software\\Policies\\Adobe\\AIR\" -Name \"UpdateDisabled\" -Value 1 -Force -ErrorAction SilentlyContinue\n# Disable Balloon Notifications\nSet-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\" -Name \"EnableBalloonTips\" -Value 0 -Force -ErrorAction SilentlyContinue\n# Disable Error Reporting\nSet-ItemProperty -Path \"HKLM:\\SOFTWARE\\Microsoft\\Windows\\Windows Error Reporting\" -Name \"Disabled\" -Value 1 -Force -ErrorAction SilentlyContinue\n# Disable Error Reporting UI\nSet-ItemProperty -Path \"HKCU:\Software\\Microsoft\\Windows\\Windows Error Reporting\" -Name \"DontShowUI\" -Value 1 -Force -ErrorAction SilentlyContinue\n# Disable Icons & Notifications on the Taskbar\nSet-ItemProperty -Path \"HKCU:\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\" -Name \"EnableAutoTray\" -Value 0 -Force -ErrorAction SilentlyContinue\n# Disable Gratuitous ARP\nSet-ItemProperty -Path \"HKLM:\SYSTEM\\CurrentControlSet\\Services\\Tcpip\\Parameters\" -Name \"ArpRetryCount\" -Value 0 -Force -ErrorAction SilentlyContinue\n# Disable Notification Center\nSet-ItemProperty -Path \"HKLM:\Software\\Policies\\Microsoft\\Windows\\Explorer\" -Name \"DisableNotificationCenter\" -Value 1 -Force -ErrorAction SilentlyContinue\n# Disable All Notifications from Apps and Other Senders\nSet-ItemProperty -Path \"HKCU:\Software\\Microsoft\\Windows\\CurrentVersion\\PushNotifications\" -Name \"ToastEnabled\" -Value 0 -Force -ErrorAction SilentlyContinue\n# Disable UAC\nSet-ItemProperty -Path \"HKLM:\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System\" -Name \"EnableLUA\" -Value 0 -Force -ErrorAction SilentlyContinue\n# Disable Flicks\nSet-ItemProperty -Path \"HKCU:\Software\\Microsoft\\Wisp\\Pen\\SysEventParameters\" -Name \"Flickmode\" -Value 0 -Force -ErrorAction SilentlyContinue\n# Disable On-Screen Keyboard\nSet-ItemProperty -Path \"HKLM:\Software\\Policies\\Microsoft\\TabletTip\\1.7\" -Name \"DisableEdgeTarget\" -Value 1 -Force -ErrorAction SilentlyContinue\n# Disable Windows Updates (Note: This is a significant security decision)\nSet-ItemProperty -Path \"HKLM:\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\WindowsUpdate\\Auto Update\" -Name \"AUOptions\" -Value 1 -Force -ErrorAction SilentlyContinue\n# Set Wallpaper To Null\nSet-ItemProperty -Path \"HKCU:\Control Panel\\Desktop\" -Name \"Wallpaper\" -Value \"\" -Force -ErrorAction SilentlyContinue\n# Set Desktop to Black\nSet-ItemProperty -Path \"HKCU:\Control Panel\\colors\" -Name \"Background\" -Value \"0 0 0\" -Force -ErrorAction SilentlyContinue\n# Set Taskbar Icons Small\nSet-ItemProperty -Path \"HKCU:\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\" -Name \"TaskbarSmallIcons\" -Value 1 -Force -ErrorAction SilentlyContinue\n# Set Desktop Icons Size 16px - Small\nSet-ItemProperty -Path \"HKCU:\Control Panel\\Desktop\\WindowMetrics\" -Name \"Shell Icon Size\" -Value \"16\" -Force -ErrorAction SilentlyContinue\n\n\n# Time Synchronization\nWrite-Host \"Configuring Time Synchronization...\" -ForegroundColor Cyan\n# Start Time Sync Service\nStart-Service w32time -ErrorAction SilentlyContinue\nSet-Service -Name w32time -StartupType Automatic -ErrorAction SilentlyContinue\n# Set NTP Servers to pool.ntp.org and Trigger Resync\nw32tm /config /update /manualpeerlist:pool.ntp.org /syncfromflags:MANUAL\nw32tm.exe /resync\nWrite-Host \"Time synchronization configured.\" -ForegroundColor Green\n\n# Custom Power Plan (Requires Incidium.pow to be present in C:\\Temp\\)\nWrite-Host \"Importing and Activating Incidium Power Plan...\" -ForegroundColor Cyan\n$IncidiumPowPath = \"C:\\Temp\\incidium.pow\"\nif (Test-Path $IncidiumPowPath) {\n    # Delete existing power scheme if it matches the GUID to prevent duplicates\n    # This GUID needs to match the one in _SnakespeareV6_Installer.bat\n    $IncidiumPowerPlanGUID = \"7dbcfff5-c58a-4e67-b8ec-df9a2f6eddbc\"\n    powercfg /delete $IncidiumPowerPlanGUID -ErrorAction SilentlyContinue\n\n    powercfg /import $IncidiumPowPath $IncidiumPowerPlanGUID\n    powercfg /setactive $IncidiumPowerPlanGUID\n    Write-Host \"Incidium Power Plan imported and activated.\" -ForegroundColor Green\n} else {\n    Write-Warning \"Incidium Power Plan file ($IncidiumPowPath) not found. Skipping custom power plan import.\"\n}\n\n\n# Delete Google Scheduled Tasks\nWrite-Host \"Deleting Google Scheduled Tasks...\" -ForegroundColor Cyan\nUnregister-ScheduledTask -TaskName \"GoogleUpdateTaskMachineCore\" -Confirm:$false -ErrorAction SilentlyContinue\nUnregister-ScheduledTask -TaskName \"GoogleUpdateTaskMachineUA\" -Confirm:$false -ErrorAction SilentlyContinue\nWrite-Host \"Google scheduled tasks deleted.\" -ForegroundColor Green\n\n\n# Firewall Exceptions\nWrite-Host \"Configuring Firewall Exceptions...\" -ForegroundColor Cyan\n# Open Incoming FTP Ports - TCP 20-21\nRemove-NetFirewallRule -DisplayName \"Open Port 20\" -ErrorAction SilentlyContinue\nNew-NetFirewallRule -Name \"Open Port 20\" -DisplayName \"Open Port 20\" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 20 -ErrorAction SilentlyContinue\nRemove-NetFirewallRule -DisplayName \"Open Port 21\" -ErrorAction SilentlyContinue\nNew-NetFirewallRule -Name \"Open Port 21\" -DisplayName \"Open Port 21\" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 21 -ErrorAction SilentlyContinue\n\n# SnakeCharmer Firewall Exception\nRemove-NetFirewallRule -DisplayName \"SnakeCharmer\" -ErrorAction SilentlyContinue\nNew-NetFirewallRule -Name \"SnakeCharmer\" -DisplayName \"SnakeCharmer\" -Enabled True -Direction Inbound -Protocol Any -Action Allow -Program \"C:\\SnakeSpeareV6\\SnakeCharmer.exe\" -ErrorAction SilentlyContinue\n\n# VLC (x86) Firewall Exception\nRemove-NetFirewallRule -DisplayName \"VLC x86\" -ErrorAction SilentlyContinue\nNew-NetFirewallRule -Name \"VLC x86\" -DisplayName \"VLC x86\" -Enabled True -Direction Inbound -Protocol Any -Action Allow -Program \"C:\\Program Files (x86)\\VideoLAN\\VLC\\vlc.exe\" -ErrorAction SilentlyContinue\n\n# VLC (x64) Firewall Exception\nRemove-NetFirewallRule -DisplayName \"VLC x64\" -ErrorAction SilentlyContinue\nNew-NetFirewallRule -Name \"VLC x64\" -DisplayName \"VLC x64\" -Enabled True -Direction Inbound -Protocol Any -Action Allow -Program \"C:\\Program Files\\VideoLAN\\VLC\\vlc.exe\" -ErrorAction SilentlyContinue\nWrite-Host \"Firewall exceptions configured.\" -ForegroundColor Green\n\n# SnakeCharmer Startup Shortcut\nWrite-Host \"Creating SnakeCharmer Startup Shortcut...\" -ForegroundColor Cyan\n$SnakeCharmerTarget = 'C:\\SnakeSpeareV6\\SnakeCharmer.exe'\n$SnakeCharmerStartupShortcut = 'C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\SnakeCharmer.lnk'\n# Use PowerShell to create the shortcut robustly\n$ws = New-Object -ComObject WScript.Shell\n$s = $ws.CreateShortcut($SnakeCharmerStartupShortcut)\n$s.TargetPath = $SnakeCharmerTarget\n$s.Save()\nWrite-Host \"SnakeCharmer startup shortcut created.\" -ForegroundColor Green\nWrite-Host \"\"\n\nWrite-Host \"===========================================================\" -ForegroundColor Green\nWrite-Host \" Consolidated Post-OS Installation Script Finished\" -ForegroundColor Green\nWrite-Host \"===========================================================\" -ForegroundColor Green