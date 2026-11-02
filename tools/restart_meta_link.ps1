# restart_meta_link.ps1 -- restart Meta's OpenXR runtime service (OVRService).
# Use when Meta Link reports the headset 'NotDetected' while it is plugged in and Link is on,
# or when the service log shows "mDNS discovery is stalled" (Air Link can't find the headset).
# Needs admin: run it and click Yes on the UAC prompt.
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}
Restart-Service -Name OVRService -Force
Start-Sleep -Seconds 3
Get-Service OVRService | Select-Object Status, Name, DisplayName
