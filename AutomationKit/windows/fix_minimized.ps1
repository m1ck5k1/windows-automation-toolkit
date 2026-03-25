$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut("C:\SnakeSpeareV6\SnakeCharmer.lnk")
$Shortcut.TargetPath = "C:\SnakeSpeareV6\SnakeCharmer.exe"
$Shortcut.WorkingDirectory = "C:\SnakeSpeareV6"
$Shortcut.WindowStyle = 7 # 7 = Minimized, 3 = Maximized, 1 = Normal
$Shortcut.Save()

Write-Host "Shortcut Created." -ForegroundColor Green

# Update Task to run the LNK (via cmd /c start)
# Note: Task Scheduler can't run .lnk directly reliably, so we use explorer or cmd
$TaskName = "SnakeCharmer"
$User = "ds"
$Action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start /min C:\SnakeSpeareV6\SnakeCharmer.lnk"

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $User
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0) -Priority 1
Register-ScheduledTask -TaskName $TaskName -Trigger $Trigger -Action $Action -Settings $Settings -User $User -RunLevel Highest

Write-Host "Task Updated to run Shortcut." -ForegroundColor Green
