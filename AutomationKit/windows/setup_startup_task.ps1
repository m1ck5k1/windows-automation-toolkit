$TaskName = "SnakeCharmer"
$User = "ds"
$ExePath = "C:\SnakeSpeareV6\SnakeCharmer.exe"
$WorkDir = "C:\SnakeSpeareV6"

Write-Host "Creating Startup Task for $TaskName..." -ForegroundColor Cyan

# Unregister if exists
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

# Create Trigger (Logon)
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $User

# Create Action
$Action = New-ScheduledTaskAction -Execute $ExePath -WorkingDirectory $WorkDir

# Create Settings (High Priority, No Stop on Battery)
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0) -Priority 1

# Register Task (Run as Admin - Highest Available)
# Note: To run purely as the user (interactively), we use the user context.
Register-ScheduledTask -TaskName $TaskName -Trigger $Trigger -Action $Action -Settings $Settings -User $User -RunLevel Highest

Write-Host "Task '$TaskName' Registered Successfully." -ForegroundColor Green
