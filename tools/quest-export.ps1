# Offline Windows debug export. All generated assets, credentials and licensed SDK files stay outside Git.
param(
    [Parameter(Mandatory)][string]$QuestProject,
    [Parameter(Mandatory)][string]$Sdk,
    [Parameter(Mandatory)][string]$Godot,
    [Parameter(Mandatory)][string]$Templates,
    [Parameter(Mandatory)][string]$DebugKeystore,
    [string]$OpenXRHeaders,
    [string]$Jdk = (Split-Path -Parent (Split-Path -Parent (Get-Command javac.exe).Source)),
    [switch]$KeepStage
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root 'build/quest'
$stage = Join-Path $out ('stage-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$project = Join-Path $stage 'project'
$localSdk = Join-Path $stage 'sdk'
$profile = Join-Path $stage 'profile'
$editor = Join-Path $profile 'Godot'
$export = Join-Path $stage 'PhaethonQuestFlight.apk'
$utf8 = [Text.UTF8Encoding]::new($false)
$previous = @{}
foreach ($name in @('PATH','ANDROID_HOME','ANDROID_SDK_ROOT','APPDATA','LOCALAPPDATA','JAVA_HOME','JAVA_OPTS')) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name)
}

function Copy-Tree($From, $To, [string[]]$Exclude = @()) {
    if (!(Test-Path -LiteralPath $From -PathType Container)) { throw "Missing directory: $From" }
    $options = @('/E','/R:1','/W:1','/NFL','/NDL','/NJH','/NJS','/NP')
    if ($Exclude.Count) { $options += '/XD'; $options += $Exclude }
    & robocopy.exe $From $To @options | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "robocopy $From failed ($LASTEXITCODE)" }
}

$base = @('--headless','--xr-mode','off','--audio-driver','Dummy','--path',$project)
function Invoke-Godot([string]$Name, [string[]]$Arguments) {
    $log = Join-Path $stage "$Name.log"
    # Wait even for the Win32 GUI binary. Pass --headless and keep its console hidden.
    $all = $base + @('--log-file',$log) + $Arguments
    $quoted = @($all | ForEach-Object { '"' + $_ + '"' })
    $proc = Start-Process -FilePath $Godot -ArgumentList $quoted -NoNewWindow -PassThru -Wait -RedirectStandardOutput "$log.stdout" -RedirectStandardError "$log.stderr"
    if ($proc.ExitCode -ne 0 -or !(Test-Path -LiteralPath $log)) {
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 25 }
        Get-Content -LiteralPath "$log.stderr" -Tail 12
        throw "$Name failed ($($proc.ExitCode))"
    }
    if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR:|Parse Error:|Failed to load script') {
        throw "$Name logged script errors in $log"
    }
}

foreach ($file in @($Godot,$DebugKeystore,(Join-Path $Templates 'android_debug.apk'),(Join-Path $QuestProject 'android/.build_version'),(Join-Path $QuestProject 'addons/godotopenxrvendors/plugin.gdextension'))) {
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing input: $file" }
}
$version = (Get-Content -LiteralPath (Join-Path $QuestProject 'android/.build_version') -Raw).Trim()
if ($version -ne '4.7.1.stable') { throw "Unexpected Godot Android template: $version" }
New-Item -Path $stage -ItemType Directory -Force | Out-Null
try {
    Copy-Tree (Join-Path $root 'godot') $project @('.godot','android','addons','shots')
    # The Windows editor needs mobile textures during this import and the later Android export.
    # Enable them in the staged project so a normal PC import keeps its original texture formats.
    $stagedConfig = Join-Path $project 'project.godot'
    $config = [IO.File]::ReadAllText($stagedConfig)
    $rendering = [regex]'(?m)^\[rendering\]\r?$'
    if ($rendering.Matches($config).Count -ne 1) { throw 'Expected one rendering section in staged project.godot' }
    [IO.File]::WriteAllText($stagedConfig, $rendering.Replace($config, "[rendering]`ntextures/vram_compression/import_etc2_astc=true"), $utf8)
    Copy-Tree (Join-Path $QuestProject 'addons/godotopenxrvendors') (Join-Path $project 'addons/godotopenxrvendors')
    $donor = Join-Path $QuestProject 'android/build'
    Copy-Tree (Join-Path $QuestProject 'android') (Join-Path $project 'android') @('.gradle',(Join-Path $donor 'build'),(Join-Path $donor 'assetPackInstallTime/build'),(Join-Path $donor 'src/main/assets'))
    $gradlew = Join-Path $project 'android/build/gradlew.bat'
    $wrapper = [IO.File]::ReadAllText($gradlew)
    if (!$wrapper.Contains('GradleWrapperMain %*')) { throw 'Unrecognized Gradle wrapper' }
    # Match the template JVM so Gradle can build in-process even when localhost IPC is unavailable.
    $wrapper = $wrapper.Replace('"-Xmx64m" "-Xms64m"','"-Xmx4536m"')
    [IO.File]::WriteAllText($gradlew,$wrapper.Replace('GradleWrapperMain %*','GradleWrapperMain --offline --no-daemon --max-workers=2 %*'),$utf8)
    $env:JAVA_OPTS = '-Dfile.encoding=UTF-8 -Duser.country=US -Duser.language=en -Duser.variant= -Dorg.gradle.internal.instrumentation.agent=false'
    [IO.File]::AppendAllText((Join-Path $project 'android/build/gradle.properties'),"`nkotlin.compiler.execution.strategy=in-process`nandroid.builder.sdkDownload=false`n",$utf8)
    # Ask Gradle to invoke javac directly; its worker-daemon compiler uses a loopback socket.
    $javac = @'
tasks.withType(JavaCompile).configureEach {
    options.fork = true
    options.forkOptions.executable = new File(System.getenv("JAVA_HOME"), "bin/javac.exe").absolutePath
}
'@
    [IO.File]::AppendAllText((Join-Path $project 'android/build/build.gradle'),"`n$javac`n",$utf8)

    # Godot polls adb even during an editor import. Only the build packages are visible here.
    # A local stand-in answers discovery with an empty list and rejects all device operations.
    $platformTools = Join-Path $localSdk 'platform-tools'
    New-Item -Path $platformTools -ItemType Directory -Force | Out-Null
    foreach ($package in @('build-tools/36.1.0','platforms/android-36','licenses','ndk/29.0.14206865')) {
        Copy-Tree (Join-Path $Sdk $package) (Join-Path $localSdk $package)
    }
    if (!$OpenXRHeaders) {
        $gradleHome = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { Join-Path $env:USERPROFILE '.gradle' }
        $cache = Join-Path $gradleHome 'caches/modules-2/files-2.1/org.khronos.openxr/openxr_loader_for_android/1.1.54'
        $aar = Get-ChildItem -LiteralPath $cache -Filter '*.aar' -Recurse | Select-Object -First 1
        if (!$aar) { throw 'Pass -OpenXRHeaders pointing at the include directory containing openxr/openxr.h' }
        $headers = Join-Path $stage 'headers'
        New-Item -Path $headers -ItemType Directory | Out-Null
        & tar.exe -xf $aar.FullName -C $headers 'prefab/modules/headers/include'
        if ($LASTEXITCODE) { throw 'Khronos header extraction failed' }
        $OpenXRHeaders = Join-Path $headers 'prefab/modules/headers/include'
    }
    $jni = Join-Path $project 'android/build/libs/debug/arm64-v8a'
    New-Item -Path $jni -ItemType Directory -Force | Out-Null
    $clang = Join-Path $localSdk 'ndk/29.0.14206865/toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe'
    & $clang --target=aarch64-linux-android24 -shared -fPIC -Wall -Werror -O2 "-I$OpenXRHeaders" '-Wl,-z,max-page-size=16384' -o "$jni/libquest_projection.so" "$PSScriptRoot/quest/quest_projection.c"
    if ($LASTEXITCODE) { throw 'Android projection reader compilation failed' }
    Copy-Item -LiteralPath "$PSScriptRoot/quest/QuestProjection.java" -Destination "$project/android/build/src/main/java/com/godot/game"
    $shim = Join-Path $stage 'OfflineAdb.cs'
    [IO.File]::WriteAllText($shim, 'class OfflineAdb { static int Main(string[] args) { if (args.Length > 0 && args[0] == "devices") { System.Console.WriteLine("List of devices attached"); return 0; } return 1; } }', $utf8)
    $csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    & $csc /nologo /target:exe "/out:$platformTools/adb.exe" $shim
    if ($LASTEXITCODE) { throw 'Could not create the device-free adb stand-in' }
    $env:PATH = "$platformTools;$env:PATH"
    $env:ANDROID_HOME = $localSdk
    $env:ANDROID_SDK_ROOT = $localSdk
    $env:JAVA_HOME = $Jdk
    $env:APPDATA = $profile
    $env:LOCALAPPDATA = $profile
    New-Item -Path (Join-Path $editor 'export_templates'),(Join-Path $editor 'keystores') -ItemType Directory -Force | Out-Null
    Copy-Tree $Templates (Join-Path $editor "export_templates/$version")
    $key = Join-Path $editor 'keystores/debug.keystore'
    Copy-Item -LiteralPath $DebugKeystore -Destination $key
    $settings = @(
        '[gd_resource type="EditorSettings" format=3]', '', '[resource]',
        ('export/android/android_sdk_path = "' + $localSdk.Replace('\','/') + '"'),
        ('export/android/java_sdk_path = "' + $Jdk.Replace('\','/') + '"'),
        ('export/android/debug_keystore = "' + $key.Replace('\','/') + '"'),
        'export/android/shutdown_adb_on_exit = false'
    )
    [IO.File]::WriteAllLines((Join-Path $editor 'editor_settings-4.7.tres'),[string[]]$settings,$utf8)
    [IO.File]::WriteAllText((Join-Path $project 'override.cfg'),"[threading]`nworker_pool/max_threads=1`n",$utf8)
    Write-Output "Importing $project"
    Invoke-Godot 'import' @('--editor','--import')
    Remove-Item -LiteralPath (Join-Path $project 'override.cfg')
    Invoke-Godot 'runtime-check' @('--script','res://tests/test_quest_flight.gd')
    Write-Output 'Exporting arm64 Quest debug APK'
    Invoke-Godot 'export' @('--export-debug','Quest 3 Test',$export)
    $tools = Join-Path $Sdk 'build-tools/36.1.0'
    & (Join-Path $tools 'apksigner.bat') verify --verbose $export
    if ($LASTEXITCODE) { throw 'APK signature verification failed' }
    & (Join-Path $tools 'zipalign.exe') -c -P 16 4 $export
    if ($LASTEXITCODE) { throw 'APK zip alignment failed' }
    $badging = & (Join-Path $tools 'aapt2.exe') dump badging $export
    if ($LASTEXITCODE -or !($badging -match "package: name='com.elstonworks.phaethon.questtest' versionCode='2'") -or !($badging -match "^native-code: 'arm64-v8a'$")) {
        throw 'Unexpected Quest package identity or architecture'
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($export)
    try {
        foreach ($entry in @('assets/vr/quest_flight.gdc','assets/vr/quest_flight.tscn.remap','assets/audio/ramjet/manifest.json','lib/arm64-v8a/libopenxr_loader.so','lib/arm64-v8a/libgodotopenxrvendors.so','lib/arm64-v8a/libquest_projection.so')) {
            if (!$zip.GetEntry($entry)) { throw "Missing APK member: $entry" }
        }
        foreach ($format in @('astc', 'etc2')) {
            if (!($zip.Entries.FullName -like "assets/.godot/imported/*.$format.ctex")) {
                throw "Missing Quest $format textures in APK"
            }
        }
    } finally { $zip.Dispose() }
    $build = Join-Path $out 'PhaethonQuestFlight.apk'
    Copy-Item -LiteralPath $export -Destination $build -Force
    Get-FileHash -Algorithm SHA256 -LiteralPath $build
} finally {
    foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name,$previous[$name]) }
    if (!$KeepStage -and ((Split-Path -Parent (Resolve-Path $stage).Path) -eq (Resolve-Path $out).Path)) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}
