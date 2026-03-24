$TaskName = "SnakeCharmer"
$User = "ds"
$ExePath = "C:\SnakeSpeareV6\SnakeCharmer.exe"
$WorkDir = "C:\SnakeSpeareV6"

Write-Host "Updating Startup Task to Run Minimized..." -ForegroundColor Cyan

# Unregister if exists
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

# Create Trigger (Logon)
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $User

# Create Action (Use CMD /c start /min to minimize console window)
$Action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start /min `"`" `"$ExePath`"" -WorkingDirectory $WorkDir

# Create Settings
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0) -Priority 1

# Register Task
Register-ScheduledTask -TaskName $TaskName -Trigger $Trigger -Action $Action -Settings $Settings -User $User -RunLevel Highest

Write-Host "Task '$TaskName' Updated to Run Minimized." -ForegroundColor Green
