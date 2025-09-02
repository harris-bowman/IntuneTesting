$script = @"
Write-Host "Autopilot hash upload script starting..."

Write-Host "Setting TLS Level:"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "Setting Execution policy:"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
Write-Host "Downloading Get-WindowsAutopilotInfo Script:"
Install-Script -Name Get-WindowsAutopilotInfo -Force
Write-Host "Enrolling device in Autopilot, Please login with a Intune Administrator account:"
Get-WindowsAutoPilotInfo -Online -GroupTag 'SmarT User'
Write-Host "Hardware Hash uploaded to Autopilot. Restarting...."
Wait 5

shutdown /r /t 0
"@

$path = "C:\OSDCloud\ap.ps1"
New-Item -Path $path -ItemType File -Force | Out-Null
Set-Content -Path $path -Value $script