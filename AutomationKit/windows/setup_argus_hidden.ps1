$TaskName = "ArgusAgent"
$User = "ds"
$CmdPath = "C:\Program Files\Argus\run_argus.cmd"
$WorkDir = "C:\Program Files\Argus"

Write-Host "Updating Argus Task to run via CMD (with Env Vars)..." -ForegroundColor Cyan

# Unregister Old Task
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

# Trigger (Logon)
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $User

# Action: Run CMD /c run_argus.cmd
# This ensures Env Vars are set correctly before launch.
$Action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$CmdPath`"" -WorkingDirectory $WorkDir

# Settings: Hidden, Priority
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0) -Priority 1 -Hidden

# Register
Register-ScheduledTask -TaskName $TaskName -Trigger $Trigger -Action $Action -Settings $Settings -User $User -RunLevel Highest

Write-Host "Argus Task Updated." -ForegroundColor Green
