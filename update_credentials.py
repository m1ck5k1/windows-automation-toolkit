import re

# 1. Update install_openssh.ps1
with open('/home/m1ck5k1/dev/clonezilla/install_openssh.ps1', 'r') as f:
    ps1 = f.read()

user_block_old = """# 2. Create User 'incidium' if not exists
$Username = "incidium"
$Password = "547Mark!"
$UserExists = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue

if (-not $UserExists) {
    Write-Host "Creating user $Username..." -ForegroundColor Cyan
    $SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    New-LocalUser -Name $Username -Password $SecurePassword -FullName "Incidium SSH User" -Description "SSH Access User"
    Add-LocalGroupMember -Group "Administrators" -Member $Username
} else {
    Write-Host "User $Username already exists. Skipping creation." -ForegroundColor Yellow
}"""

user_block_new = """# 2. Create Required Users
$Users = @(
    @{ Username="ds"; Password="547Mark!"; FullName="Digital Signage"; Description="Primary AutoLogin User" },
    @{ Username="m1ck5k1"; Password="Kal1L1nux"; FullName="System Admin"; Description="Administrator" },
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
}"""

ps1 = ps1.replace(user_block_old, user_block_new)

ps1 = ps1.replace("Configuring AutoLogin for user 'incidium'...", "Configuring AutoLogin for user 'ds'...")
ps1 = ps1.replace('-Name "DefaultUserName" -Value "incidium"', '-Name "DefaultUserName" -Value "ds"')

ps1 = ps1.replace('Write-Host "User: $Username" -ForegroundColor Green\nWrite-Host "Password: $Password" -ForegroundColor Green', 'Write-Host "Primary User: ds" -ForegroundColor Green\nWrite-Host "Primary Password: 547Mark!" -ForegroundColor Green')

with open('/home/m1ck5k1/dev/clonezilla/install_openssh.ps1', 'w') as f:
    f.write(ps1)

# 2. Update setup_startup_task.ps1
with open('/home/m1ck5k1/dev/clonezilla/setup_startup_task.ps1', 'r') as f:
    task_ps1 = f.read()

task_ps1 = task_ps1.replace('$User = "incidium"', '$User = "ds"')

with open('/home/m1ck5k1/dev/clonezilla/setup_startup_task.ps1', 'w') as f:
    f.write(task_ps1)

# 3. Update provision_machine.sh
with open('/home/m1ck5k1/dev/clonezilla/provision_machine.sh', 'r') as f:
    prov_sh = f.read()

prov_sh = prov_sh.replace('USER="incidium"', 'USER="ds"')
prov_sh = prov_sh.replace(r'C:\Users\incidium\AppData', r'C:\Users\ds\AppData')

with open('/home/m1ck5k1/dev/clonezilla/provision_machine.sh', 'w') as f:
    f.write(prov_sh)

# 4. Update SOP.md
with open('/home/m1ck5k1/dev/clonezilla/SOP.md', 'r') as f:
    sop = f.read()

sop = sop.replace('Creates user `incidium` (Pass: `547Mark!`)', 'Creates users `ds`, `m1ck5k1`, and `support`')
sop = sop.replace('User: `incidium`', 'User: `ds` (AutoLogin) | `m1ck5k1` | `support`')
sop = sop.replace('*   **Pass:** `547Mark!`', '*   **Pass:** `547Mark!` | `Kal1L1nux` | `1nc1d1um2006!`')
sop = sop.replace('Pass `Kal1L1nux!`', 'Pass `Kal1L1nux`')

with open('/home/m1ck5k1/dev/clonezilla/SOP.md', 'w') as f:
    f.write(sop)

print("Update complete.")
