# Point the existing desktop game entry at an exported PC VR release.
# Example: ./tools/install_desktop_shortcut.ps1 -ReleaseDirectory ./build/Phaethon-Experimental-0.2.9-Windows-PCVR
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory,
    [string]$ShortcutPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'AI Builds\VR\Phaethon.lnk')
)
$ErrorActionPreference = 'Stop'
$releasePath = (Resolve-Path -LiteralPath $ReleaseDirectory).Path
$gameExe = Join-Path $releasePath 'PhaethonVR.exe'
$gamePack = Join-Path $releasePath 'PhaethonVR.pck'
if (!(Test-Path -LiteralPath $gameExe -PathType Leaf) -or !(Test-Path -LiteralPath $gamePack -PathType Leaf)) {
    throw 'Select an extracted PC VR release containing PhaethonVR.exe and PhaethonVR.pck.'
}
$linkPath = [IO.Path]::GetFullPath($ShortcutPath)
if ([IO.Path]::GetExtension($linkPath) -ne '.lnk') { throw 'ShortcutPath must end in .lnk.' }
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $linkPath) -Force
$shortcutShell = New-Object -ComObject WScript.Shell
$shortcut = $shortcutShell.CreateShortcut($linkPath)
$shortcut.TargetPath = $gameExe
$shortcut.WorkingDirectory = $releasePath
$shortcut.Arguments = '-- --track=network'
$shortcut.IconLocation = "$gameExe,0"
$shortcut.Description = 'Phaethon PC VR - connect Quest Link or Air Link, then open to play.'
$shortcut.WindowStyle = 1
$shortcut.Save()
$saved = $shortcutShell.CreateShortcut($linkPath)
if ($saved.TargetPath -ne $gameExe -or $saved.WorkingDirectory -ne $releasePath -or $saved.Arguments -ne '-- --track=network') {
    throw 'Saved shortcut does not match the requested release.'
}
[pscustomobject]@{ Shortcut = $linkPath; Executable = $saved.TargetPath; Arguments = $saved.Arguments } | ConvertTo-Json
