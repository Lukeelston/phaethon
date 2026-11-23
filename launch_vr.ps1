# launch_vr.ps1 -- Phaethon in the Quest 3 over Meta Link.
#   .\launch_vr.ps1                  launch now (Quest must already be in Link mode)
#   .\launch_vr.ps1 -WaitForHeadset  wait until Meta Link reports the headset ready, then launch
# Same runtime recipe as launch_nafworld_vr.ps1: Meta's OpenXR runtime via XR_RUNTIME_JSON,
# a supervised Godot process, and a per-session log in %TEMP%.
# Controls: four Touch schemes, selected in the quick menu (trigger throttles, throttle +
# steer, grab the levers, stick levers); A reignite, B arm ramjet, X repair, Y tap restart,
# the MODE switch (or Y hold) flips SPEEDCRAFT / STARFIGHTER live, thumbstick click recenters,
# a menu tap opens the quick menu (driving partner, control scheme, map selection);
# menu hold 1.5 s returns to the release map selector and ends the run.
#   .\launch_vr.ps1 -Partner          the driving partner on (it's on the main menu too)
#   .\launch_vr.ps1 -Handling starfighter   start in the tight ~1,200 mph handling mode
#   .\launch_vr.ps1 -Track gp              the grand prix: 29 km for STARFIGHTER at ~1,000 mph
#   .\launch_vr.ps1 -Track eridanus        the dual-purpose course: 199 km, SPEEDCRAFT loop + STARFIGHTER towns
#   .\launch_vr.ps1 -Job emergency         the emergency run on Eridanus: out to the lake town, home before the dawn
#   .\launch_vr.ps1 -Track network         the Network: a country of highways, five cities (A: next target city)
#   .\launch_vr.ps1 -Track range     the 100-mile test range (jump lane +400 m left, twisty lane right)
#   .\launch_vr.ps1 -Track range -StartMile 95   start further down the range
param([switch]$WaitForHeadset, [int]$WaitMinutes = 30, [ValidateSet("circuit", "range", "gp", "eridanus", "network")][string]$Track = "circuit", [double]$StartMile = 0, [ValidateSet("", "speed", "starfighter")][string]$Handling = "", [ValidateSet("", "emergency")][string]$Job = "", [switch]$HeavyPod, [switch]$Partner)

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fffffff'
$log = Join-Path $env:TEMP "phaethon_vr_${stamp}_${PID}.log"
Write-Host "Phaethon VR -> log $log"
"$(Get-Date -Format o) Source launch requested" | Out-File -LiteralPath $log

function Get-SourceSupervisor {
    $source = Join-Path $PSScriptRoot 'tools\PcvrBoot.cs'
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($source))).Replace('-', '') }
    finally { $sha.Dispose() }
    $cache = Join-Path $PSScriptRoot ('.tools\pcvr-source\' + $hash.Substring(0, 24))
    $null = [IO.Directory]::CreateDirectory($cache)
    $launcher = Join-Path $cache 'PcvrSource.exe'
    if (Test-Path -LiteralPath $launcher -PathType Leaf) { return $launcher }

    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $temporary = Join-Path $cache ([guid]::NewGuid().ToString('N').Substring(0, 12) + '.exe')
    try {
        & $compiler /nologo /target:winexe /optimize+ /reference:System.Windows.Forms.dll "/out:$temporary" $source >> $log
        if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $temporary -PathType Leaf)) {
            throw "C# compiler failed building the source boot watchdog. See $log"
        }
        # Concurrent launches can both compile; publish one complete executable.
        try { [IO.File]::Move($temporary, $launcher) }
        catch [IO.IOException] { if (!(Test-Path -LiteralPath $launcher -PathType Leaf)) { throw } }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
    return $launcher
}

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
    if (-not (Test-QuestLinked)) { "HEADSET NOT LINKED after $WaitMinutes min, not launching." | Tee-Object -FilePath $log -Append; exit 2 }
    Write-Host "HEADSET LINKED"
    Start-Sleep -Seconds 3   # let Link finish bringing up the compositor
}

$userArgs = @()
if ($Track -eq "range") { $userArgs = @("--track=range", "--startx=$([int]($StartMile * 1609.344))") }
if ($Track -in "gp", "eridanus", "network") { $userArgs = @("--track=$Track") }
if ($Job -eq "emergency") { $userArgs = @("--track=eridanus", "--job=emergency") }   # the job flies Eridanus
if ($Handling) { $userArgs += "--handling=$Handling" }
if ($Partner) { $userArgs += "--partner" }
if ($HeavyPod) { $userArgs += "--pod=heavy" }

$priorRuntime = $env:XR_RUNTIME_JSON
try {
    $installed = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot_v*win64.exe"
    $godot = Get-ChildItem $installed -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (!$godot) { throw "Could not find the Windows Godot executable at $installed" }
    $launcher = Get-SourceSupervisor
    $env:XR_RUNTIME_JSON = 'C:\Program Files\Meta Horizon\Support\oculus-runtime\oculus_openxr_64.json'
    $engineArgs = @('--source-engine', $godot.FullName, '--path', (Join-Path $PSScriptRoot 'godot'),
                    '--xr-mode', 'on', 'res://release/vr_boot.tscn', '--', '--source-direct-flight') + $userArgs
    & $launcher @engineArgs 2>&1 | Tee-Object -FilePath $log -Append
    $code = $LASTEXITCODE
} catch {
    $_.Exception.Message | Tee-Object -FilePath $log -Append
    $code = 1
} finally {
    $env:XR_RUNTIME_JSON = $priorRuntime
}
exit $code
