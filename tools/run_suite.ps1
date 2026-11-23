# Run from any directory with PowerShell 5.1+ on Windows. Each invocation has
# its own logs and Godot profile under evidence/suite (or a fresh -OutputDirectory).
# Use -RerunFailures to retry the latest tally, or pass -PreviousSummary <summary.tsv>.
[CmdletBinding()]
param(
    [string]$Godot = 'Godot_v4.7.1-stable_win64_console.exe',
    [string]$Project,
    [string]$OutputDirectory,
    [switch]$RerunFailures,
    [string]$PreviousSummary,
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'
if (!$Project) { $Project = Join-Path $PSScriptRoot '../godot' }
$projectPath = (Resolve-Path -LiteralPath $Project).ProviderPath
$engine = (Get-Command -Name $Godot -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$tests = @(Get-ChildItem -LiteralPath (Join-Path $projectPath 'tests') -File -Filter 'test_*.gd' | Sort-Object Name)
if (!$tests.Count) { throw "No test_*.gd scripts found in $projectPath/tests" }
$suiteRoot = Join-Path $projectPath '../evidence/suite'
if ($PreviousSummary -and !$RerunFailures) { throw '-PreviousSummary requires -RerunFailures.' }
if ($RerunFailures) {
    if (!$PreviousSummary) {
        $prior = Get-ChildItem -LiteralPath $suiteRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'summary.tsv') -ErrorAction SilentlyContinue } |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if (!$prior) { throw "No previous summary.tsv under $suiteRoot. Use -PreviousSummary to specify one." }
        $PreviousSummary = $prior.FullName
    }
    $previous = (Resolve-Path -LiteralPath $PreviousSummary).ProviderPath
    $priorRows = @(Import-Csv -LiteralPath $previous -Delimiter "`t" -Encoding UTF8)
    if ((Get-Content -LiteralPath $previous -TotalCount 1) -cne "test`tmode`texit`tstatus`tverdict" -or
            @($priorRows | Where-Object { !$_.test -or $_.status -cnotin @('PASS', 'FAIL') }).Count) {
        throw "Invalid suite tally: $previous"
    }
    $retry = @($priorRows | Where-Object status -ceq 'FAIL' | ForEach-Object { $_.test })
    $missing = @($retry | Where-Object { $_ -notin $tests.BaseName })
    if ($missing.Count) { throw ('Failed tests missing from this checkout: ' + ($missing -join ', ')) }
    $tests = @($tests | Where-Object { $_.BaseName -in $retry })
    if (!$tests.Count) {
        Write-Host "No failed tests in $previous."
        exit 0
    }
}
if (!$OutputDirectory) {
    $OutputDirectory = Join-Path $suiteRoot (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
}
$runPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
# New-Item without -Force also rejects a reused directory and its stale logs.
$null = New-Item -ItemType Directory -Path $runPath
$profile = (New-Item -ItemType Directory -Path (Join-Path $runPath 'profile')).FullName
$localProfile = (New-Item -ItemType Directory -Path (Join-Path $runPath 'profile/local')).FullName
$summary = Join-Path $runPath 'summary.tsv'

# Read the leading comment block only. Some tests mention running other tests
# windowed in their body, or offer optional screenshots on a separate invocation.
function Test-RequiresWindow([string]$TestPath) {
    foreach ($line in [IO.File]::ReadLines($TestPath)) {
        if ($line -match '^\s*#+\s*Run windowed\b') { return $true }
        if ($line -notmatch '^\s*(#|$)') { break }
    }
    return $false
}

# The console launcher starts the actual engine as a child. A Windows job
# terminates both on timeout, including under PowerShell 5.1 without WMI.
if (!('Phaethon.SuiteJob' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Phaethon {
    public static class SuiteJob {
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern SafeFileHandle CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool AssignProcessToJobObject(SafeFileHandle job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool TerminateJobObject(SafeFileHandle job, uint exitCode);
        public static SafeFileHandle OpenJob() {
            var job = CreateJobObject(IntPtr.Zero, null);
            if (job.IsInvalid) throw new Win32Exception();
            return job;
        }
        public static void Add(SafeFileHandle job, IntPtr process) {
            if (!AssignProcessToJobObject(job, process)) throw new Win32Exception();
        }
        public static void Stop(SafeFileHandle job) {
            if (!TerminateJobObject(job, 124)) throw new Win32Exception();
        }
    }
}
'@
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
    $flights = @(Get-Process -ErrorAction Stop | Where-Object { $_.ProcessName -match 'PhaethonVR|BendingVR' })
    if ($flights.Count) { throw ('Flight active, suite stopped before launch: ' + ($flights.ProcessName -join ', ')) }
    $job = [Phaethon.SuiteJob]::OpenJob()
    $process = $null
    try {
        $process = [Diagnostics.Process]::Start($start)
        if (!$process.HasExited) {
            try { [Phaethon.SuiteJob]::Add($job, $process.Handle) }
            catch { if (!$process.HasExited) { throw } }
        }
        if ($process.WaitForExit($TimeoutSeconds * 1000)) { return $process.ExitCode }
        return 124
    } finally {
        try {
            [Phaethon.SuiteJob]::Stop($job)
            if ($process -and !$process.WaitForExit(1000)) {
                $process.Kill()
                $process.WaitForExit()
            }
        } finally {
            if ($process) { $process.Dispose() }
            $job.Dispose()
        }
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
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($summary, "test`tmode`texit`tstatus`tverdict`r`n", $utf8)
$failed = 0
foreach ($test in $tests) {
    $name = $test.BaseName
    $mode = 'headless'
    $options = @('--headless')
    if (Test-RequiresWindow $test.FullName) {
        $mode = 'windowed'
        $options = @('--resolution', '1280x720')
    }
    if ($name -eq 'test_chase') { $options += @('--fixed-fps', '120') }
    $options += @('-s', "res://tests/$name.gd", '--')
    if ($name -eq 'test_shudder') { $options += '--track=range' } else { $options += '--mute' }
    $log = Join-Path $runPath "$name.log"
    $exitCode = Invoke-Godot $log $options
    $lines = @(if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Encoding UTF8 })
    # The title is the test's own uppercase label, sometimes different from
    # its filename. Per-check lines start with PASS/FAIL, and are never verdicts.
    $prefix = '^(?!(?:PASS|FAIL)\b)[A-Z][A-Z0-9 -]* '
    $verdicts = @($lines -cmatch ($prefix + '(PASS|FAIL)\b'))
    $hasError = $lines -cmatch '^\s*(?:(?:SCRIPT ERROR|ERROR):|FAIL\b)'
    $status = 'PASS'
    if ($exitCode -ne 0 -or $verdicts.Count -ne 1 -or $verdicts[0] -cnotmatch ($prefix + 'PASS\b') -or $hasError) {
        $status = 'FAIL'
        $failed++
    }
    $verdict = $verdicts -join ' | '
    if ($exitCode -eq 124) { $verdict = "TIMEOUT after $TimeoutSeconds seconds" }
    elseif (!$verdict) { $verdict = 'MISSING VERDICT' }
    [IO.File]::AppendAllText($summary, "$name`t$mode`t$exitCode`t$status`t$verdict`r`n", $utf8)
    Write-Host "[$status] $name ($mode, exit $exitCode) $verdict"
}
Write-Host "$($tests.Count) tests, $failed failed. $summary"
if ($failed) { exit 1 }
exit 0
