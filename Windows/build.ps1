[CmdletBinding()]
param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent $PSScriptRoot
$version = (Get-Content (Join-Path $PSScriptRoot 'version.json') -Raw | ConvertFrom-Json).version
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid Windows release version.' }
$project = Join-Path $PSScriptRoot 'DragEngine\ThreeFingerDragOnWindows\ThreeFingerDragOnWindows.csproj'
$hubSource = Join-Path (Split-Path -Parent $project) 'WindowsHub.cs'
$source = [IO.File]::ReadAllText($hubSource)
$source = [regex]::Replace($source, 'public const string Version = "[^"]+";', ('public const string Version = "' + $version + '";'))
[IO.File]::WriteAllText($hubSource,$source,[Text.UTF8Encoding]::new($false))
$build = Join-Path $repository 'build\windows'
New-Item -ItemType Directory -Path $build -Force | Out-Null
& (Join-Path $PSScriptRoot 'Keyboard\build.ps1')
if (-not $?) { throw 'Keyboard build or offline verification failed.' }
$assetLines = @('$EmbeddedClicksAssets = @{')
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $build 'keyboard') -File | Where-Object { $_.Extension -in @('.exe','.dll','.sys','.cs','.c','.txt') } | Sort-Object Name) {
    $hash = (Get-FileHash -LiteralPath $file.FullName).Hash
    $encoded = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))
    $assetLines += "    '$($file.Name)' = @{ SHA256='$hash'; Data='$encoded' }"
}
$assetLines += '}'
$payloads = @{}
foreach ($arch in @('x64','arm64')) {
    $output = Join-Path $build "framework-$arch"
    if (-not $SkipBuild) {
        dotnet publish $project -c Release -r "win-$arch" "-p:Platform=$arch" '-p:WindowsPackageType=None' '-p:WindowsAppSDKSelfContained=false' '-p:WindowsAppSdkBootstrapInitialize=true' "-p:Version=$version" "-p:AssemblyVersion=$version.0" "-p:RestoreConfigFile=$(Join-Path $PSScriptRoot 'NuGet.Config')" --self-contained false -o $output
        if ($LASTEXITCODE -ne 0) { throw "Windows $arch build failed." }
    }
    $appHost = Join-Path $output 'ThreeEWindows.exe'
    if (Test-Path -LiteralPath $appHost) { Move-Item -LiteralPath $appHost -Destination (Join-Path $output '3£Windows.exe') -Force }
    # WinUI locates its PRI by the apphost filename, including the pound sign.
    Copy-Item -LiteralPath (Join-Path $output 'ThreeEWindows.pri') -Destination (Join-Path $output '3£Windows.pri') -Force
    if (-not (Test-Path -LiteralPath (Join-Path $output '3£Windows.exe'))) { throw "Missing $arch application." }
    foreach ($symbols in Get-ChildItem -LiteralPath $output -Filter '*.pdb') { Remove-Item -LiteralPath $symbols.FullName }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'DragEngine\LICENSE') -Destination (Join-Path $output 'THIRD-PARTY-LICENSE-ThreeFingerDragOnWindows.txt') -Force
    $archive = Join-Path $build "3EWindows-$arch.zip"
    Compress-Archive -Path (Join-Path $output '*') -DestinationPath $archive -Force
    $payloads[$arch] = [Convert]::ToBase64String([IO.File]::ReadAllBytes($archive))
}

# Exercise the compiled release without starting input hooks or changing settings.
$report = Join-Path $build 'self-test.json'
$testProcess = Start-Process -FilePath (Join-Path $build 'framework-x64\3£Windows.exe') -ArgumentList ('--self-test "' + $report + '"') -Wait -PassThru -WindowStyle Hidden
if ($testProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $report) -or -not (Get-Content -LiteralPath $report -Raw | ConvertFrom-Json).passed) { throw 'Release self-test failed.' }

$kiroSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'KiroTheme.ps1'))
$kiroEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($kiroSource))
$kiroTemplate = @'
Unregister-ScheduledTask -TaskName 'Edy Kiro Theme' -Confirm:$false -ErrorAction SilentlyContinue
$kiroAction = New-ScheduledTaskAction -Execute powershell.exe -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand {{KIRO_ENCODED}}'
$kiroTriggers = @((New-ScheduledTaskTrigger -AtLogOn -User $user),(New-ScheduledTaskTrigger -Daily -At '12:00'),(New-ScheduledTaskTrigger -Daily -At '20:00'))
Register-ScheduledTask -TaskName '3£Windows Kiro Theme' -Action $kiroAction -Trigger $kiroTriggers -Principal $taskPrincipal -Settings $taskSettings -Force | Out-Null
'@
$installer = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Installer.template.ps1'))
$installer = $installer.Replace('{{LAUNCHER}}',[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Launcher.ps1')))
$installer = $installer.Replace('{{CLICKS_FUNCTIONS}}',[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Keyboard\ClicksScopedFunctions.ps1'))).Replace('{{CLICKS_ASSETS}}',($assetLines -join "`r`n"))
$installer = $installer.Replace('{{VERSION}}',$version).Replace('{{POWERTOYS_CONFIG}}',[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PowerToys.json'))).Replace('{{KEYBOARD_CONFIG}}',[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Keyboard.template.kbd')))
$installer = $installer.Replace('{{APP_X64}}',$payloads.x64).Replace('{{APP_ARM64}}',$payloads.arm64).Replace('{{KIRO_TASK}}',$kiroTemplate.Replace('{{KIRO_ENCODED}}',$kiroEncoded))
if ($installer -match '{{(APP_|VERSION|KIRO_|POWERTOYS_|KEYBOARD_CONFIG|LAUNCHER|CLICKS_)') { throw 'Unresolved installer placeholders.' }
if ($installer -match '(?i)C:\\Users\\|DEV_[0-9A-F]{12}|capture-clicks|button-tester|\.py\b') { throw 'A machine-specific path, hardware identity, or diagnostic dependency leaked into the installer.' }
$recovery = [regex]::Match($installer, "(?s)\`$recovery = @'\r?\n(.*?)\r?\n'@").Groups[1].Value
if (-not $recovery -or $recovery -match '\$(data|rollback|suiteStopped|statusPath)\b') { throw 'The recovery task must be self-contained and independent of installer variables.' }
$tokens = $null; $errors = $null
[Management.Automation.Language.Parser]::ParseInput($installer,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count) { throw ($errors.Message -join "`n") }
$installerPath = Join-Path $repository '3£Windows.ps1'
# Windows PowerShell 5.1 needs the BOM for the pound sign in file/task names.
[IO.File]::WriteAllText($installerPath,$installer,[Text.UTF8Encoding]::new($true))
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Keyboard\Tests\Verify-Installer.ps1') -Path $installerPath
if ($LASTEXITCODE -ne 0) { throw 'Single-file installer verification failed under Windows PowerShell 5.1.' }
$release = Join-Path $build 'release'
New-Item -ItemType Directory -Path $release -Force | Out-Null
$oldReleaseScript = Join-Path $release '3£Windows.ps1'
if (Test-Path -LiteralPath $oldReleaseScript) { Remove-Item -LiteralPath $oldReleaseScript }
$releaseArchive = Join-Path $release '3EWindows.zip'
Compress-Archive -LiteralPath $installerPath -DestinationPath $releaseArchive -Force
$zip = [IO.Compression.ZipFile]::OpenRead($releaseArchive)
try {
    if ($zip.Entries.Count -ne 1 -or $zip.Entries[0].FullName -ne '3£Windows.ps1') { throw 'The release ZIP must preserve the exact installer filename.' }
} finally { $zip.Dispose() }
$checksum = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
$archiveChecksum = (Get-FileHash -LiteralPath $releaseArchive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $release 'SHA256SUMS.txt'),"$archiveChecksum  3EWindows.zip`n$checksum  3£Windows.ps1`n",[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $release 'release.json'),(@{version=$version;edition='windows';repository='Ezodis/3E';architectures=@('x64','arm64');asset='3EWindows.zip';installerSha256=$checksum;archiveSha256=$archiveChecksum} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Write-Host "Built 3£Windows $version : $installerPath"
