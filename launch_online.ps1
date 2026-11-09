# Open the multiplayer lobby. Existing launch_vr.ps1 remains the direct solo launcher.
param([switch]$VR, [string]$Godot = '')
$ErrorActionPreference = 'Stop'
if (-not $Godot) {
    $candidate = Get-Command godot -ErrorAction SilentlyContinue
    if ($candidate) { $Godot = $candidate.Source }
    else {
        $Godot = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot_v*win64_console.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    }
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) { throw 'Godot 4.7.1 is required. Use the Windows download, or pass -Godot with the path to Godot.' }
$gameArgs = @('--path', (Join-Path $PSScriptRoot 'godot'))
if ($VR) {
    $meta = 'C:\Program Files\Meta Horizon\Support\oculus-runtime\oculus_openxr_64.json'
    if (Test-Path -LiteralPath $meta) { $env:XR_RUNTIME_JSON = $meta }
    $gameArgs += @('--xr-mode', 'on', '--', '--vr')
}
& $Godot @gameArgs
exit $LASTEXITCODE
