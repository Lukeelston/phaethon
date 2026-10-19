# launch_vr.ps1 -- Phaethon in the Quest 3 over Meta Link.
#   .\launch_vr.ps1                  launch now (Quest must already be in Link mode)
#   .\launch_vr.ps1 -WaitForHeadset  wait until Meta Link reports the headset ready, then launch
# Same runtime recipe as launch_nafworld_vr.ps1: Meta's OpenXR runtime via XR_RUNTIME_JSON,
# the CONSOLE exe so stdout is capturable, and a per-session log in %TEMP%.
# Controls: four Touch schemes, cycled with the left menu button (trigger throttles, throttle +
# steer, grab the levers, stick levers); A reignite, B arm ramjet, X repair, Y tap restart,
# the MODE switch (or Y hold) flips SPEEDCRAFT / STARFIGHTER live, thumbstick click recenters,
# menu hold 1.5 s steps track (range -> grand prix -> Eridanus) without relaunching.
#   .\launch_vr.ps1 -Handling starfighter   start in the tight ~1,200 mph handling mode
#   .\launch_vr.ps1 -Track gp              the grand prix: 29 km for STARFIGHTER at ~1,000 mph
#   .\launch_vr.ps1 -Track eridanus        the dual-purpose course: 199 km, SPEEDCRAFT loop + STARFIGHTER towns
#   .\launch_vr.ps1 -Track range     the 100-mile test range (jump lane +400 m left, twisty lane right)
#   .\launch_vr.ps1 -Track range -StartMile 95   start further down the range
param([switch]$WaitForHeadset, [int]$WaitMinutes = 30, [ValidateSet("circuit", "range", "gp", "eridanus")][string]$Track = "circuit", [double]$StartMile = 0, [ValidateSet("", "speed", "starfighter")][string]$Handling = "")

function Test-QuestLinked {
    # Meta's service log is the ground truth. A Quest over Link streams through the RemoteHeadset
    # plugin, which logs "ActiveSession::..." lines throughout a live session. Do NOT key on
    # "HMD Reporting state change": that is the legacy Rift HMD manager and it reports
    # 'NotDetected' for a Quest even while Link is running (found 2026-10-17).
    $svc = Get-ChildItem (Join-Path $env:LOCALAPPDATA "Oculus") -Filter "Service_*.txt" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $svc) { return $false }
    $line = Get-Content $svc.FullName -Tail 3000 | Select-String "ActiveSession::" | Select-Object -Last 1
    if (-not $line) { return $false }
    try { $t = [datetime]::ParseExact($line.Line.Substring(0, 18), "dd/MM HH:mm:ss.fff", $null) } catch { return $false }
    return ((Get-Date) - $t).TotalSeconds -lt 60
}

if ($WaitForHeadset) {
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    Write-Host "Waiting for an active Quest Link session (up to $WaitMinutes min)..."
    while ((Get-Date) -lt $deadline -and -not (Test-QuestLinked)) { Start-Sleep -Seconds 2 }
    if (-not (Test-QuestLinked)) { Write-Host "HEADSET NOT LINKED after $WaitMinutes min, not launching."; exit 2 }
    Write-Host "HEADSET LINKED"
    Start-Sleep -Seconds 3   # let Link finish bringing up the compositor
}

$env:XR_RUNTIME_JSON = 'C:\Program Files\Meta Horizon\Support\oculus-runtime\oculus_openxr_64.json'
$godot = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot_v*win64_console.exe" | Select-Object -First 1).FullName
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$log = "$env:TEMP\phaethon_vr_$stamp.log"
Write-Host "Phaethon VR -> log $log"
$userArgs = @()
if ($Track -eq "range") { $userArgs = @("--", "--track=range", "--startx=$([int]($StartMile * 1609.344))") }
if ($Track -eq "gp" -or $Track -eq "eridanus") { $userArgs = @("--", "--track=$Track") }
if ($Handling -ne "") { if ($userArgs.Count -eq 0) { $userArgs = @("--") }; $userArgs += "--handling=$Handling" }
& $godot --path "$PSScriptRoot\godot" --xr-mode on res://vr.tscn @userArgs 2>&1 | Tee-Object -FilePath $log
