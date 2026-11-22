# Run from any directory with PowerShell 5.1+ on Windows. Each invocation has
# its own logs and Godot profile under evidence/suite (or a fresh -OutputDirectory).
[CmdletBinding()]
param(
    [string]$Godot = 'Godot_v4.7.1-stable_win64_console.exe',
    [string]$Project = (Join-Path $PSScriptRoot '../godot'),
    [string]$OutputDirectory,
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'
$projectPath = (Resolve-Path -LiteralPath $Project).ProviderPath
$engine = (Get-Command -Name $Godot -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$tests = @(Get-ChildItem -LiteralPath (Join-Path $projectPath 'tests') -File -Filter 'test_*.gd' | Sort-Object Name)
if (!$tests.Count) { throw "No test_*.gd scripts found in $projectPath/tests" }
if (!$OutputDirectory) {
    $OutputDirectory = Join-Path $projectPath ('../evidence/suite/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
}
$runPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
# New-Item without -Force also rejects a reused directory and its stale logs.
$null = New-Item -ItemType Directory -Path $runPath
$profile = (New-Item -ItemType Directory -Path (Join-Path $runPath 'profile')).FullName
$localProfile = (New-Item -ItemType Directory -Path (Join-Path $runPath 'profile/local')).FullName
$summary = Join-Path $runPath 'summary.tsv'

$windowed = @(
    'test_canopy_contrast_render', 'test_effect_exclusion', 'test_exit_lanes',
    'test_network_shaft_mesh', 'test_network_streaming_render', 'test_quick_menu_render',
    'test_screen_reflection', 'test_speed_guide_shader', 'test_traffic_fleet', 'test_traffic_lamps'
)
# Most tests print their filename as words followed by PASS or FAIL.
$titles = @{
    test_canopy_contrast_render = 'CANOPY CONTRAST'
    test_network_approach_paint = 'APPROACH PAINT'
    test_network_chunk_seams = 'CHUNK SEAMS'
    test_network_exit_guidance = 'EXIT GUIDANCE'
    test_network_paint_surface = 'PAINT SURFACE'
    test_pressure_line = 'AURORA PRESSURE LINE'
    test_release_vr = 'RELEASE VR STARTUP'
    test_traffic_oneway = 'TRAFFIC ONE-WAY'
}

function Invoke-Godot([string]$Log, [string[]]$Options) {
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $engine
    $start.WorkingDirectory = $projectPath
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.EnvironmentVariables['APPDATA'] = $profile
    $start.EnvironmentVariables['LOCALAPPDATA'] = $localProfile
    # The working directory supplies --path. The only filesystem argument is
    # a log filename, which Windows forbids from containing double quotes.
    $start.Arguments = '--log-file "' + $Log + '" --xr-mode off --audio-driver Dummy ' + ($Options -join ' ')
    $process = [Diagnostics.Process]::Start($start)
    try {
        if ($process.WaitForExit($TimeoutSeconds * 1000)) { return $process.ExitCode }
        return 124
    } finally {
        # The console launcher starts the actual engine as a child process.
        if (!$process.HasExited) {
            & taskkill.exe /PID $process.Id /T /F | Out-Null
            $process.WaitForExit()
        }
        $process.Dispose()
    }
}

Write-Host "Suite logs: $runPath"
$importLog = Join-Path $runPath 'import.log'
$importExit = Invoke-Godot $importLog @('--headless', '--editor', '--import')
if ($importExit -ne 0 -or !(Test-Path -LiteralPath $importLog) -or
        (Select-String -LiteralPath $importLog -CaseSensitive -Pattern '^(SCRIPT ERROR|ERROR):' -Quiet)) {
    throw "Godot import failed (exit $importExit). See $importLog"
}
# A few render tests write evidence at a fixed path relative to the project.
$null = New-Item -ItemType Directory -Path (Join-Path $projectPath '../evidence') -Force
"test`tmode`texit`tstatus`tverdict" | Set-Content -LiteralPath $summary -Encoding utf8
$failed = 0
foreach ($test in $tests) {
    $name = $test.BaseName
    $mode = 'headless'
    $options = @('--headless')
    if ($name -in $windowed) {
        $mode = 'windowed'
        $options = @('--resolution', '1280x720')
    }
    if ($name -eq 'test_chase') { $options += @('--fixed-fps', '120') }
    $options += @('-s', "res://tests/$name.gd", '--')
    if ($name -eq 'test_shudder') { $options += '--track=range' } else { $options += '--mute' }
    $log = Join-Path $runPath "$name.log"
    $exitCode = Invoke-Godot $log $options
    $lines = @(if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log })
    $title = $name.Substring(5).Replace('_', ' ').ToUpperInvariant()
    if ($titles.ContainsKey($name)) { $title = $titles[$name] }
    $prefix = '^' + [regex]::Escape($title) + ' '
    $verdicts = @($lines -cmatch ($prefix + '(PASS|FAIL)\b'))
    $hasError = $lines -cmatch '^\s*(?:(?:SCRIPT ERROR|ERROR):|FAIL\b)'
    $status = 'PASS'
    if ($exitCode -ne 0 -or $verdicts.Count -ne 1 -or $verdicts[0] -cnotmatch ($prefix + 'PASS\b') -or $hasError) {
        $status = 'FAIL'
        $failed++
    }
    $verdict = $verdicts -join ' | '
    "$name`t$mode`t$exitCode`t$status`t$verdict" | Add-Content -LiteralPath $summary -Encoding utf8
    Write-Host "[$status] $name ($mode, exit $exitCode) $verdict"
}
Write-Host "$($tests.Count) tests, $failed failed. $summary"
if ($failed) { exit 1 }
exit 0
