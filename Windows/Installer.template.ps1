<#
.SYNOPSIS
3£Windows: one tray menu for three-finger drag, Clicks keyboard, PowerToys,
automatic light/dark mode and dynamic wallpaper.
.DESCRIPTION
Portable single-file installer. The application and keyboard rules are embedded.
Copy this .ps1 alone to another Windows PC. Internet is needed to install signed
third-party dependencies not already present. Requires Windows 10 1809+ / 11,
administrator approval, and a Precision Touchpad for dragging. The Clicks driver
is supported on x64 only. ARM64 supports the other features.
Setup preserves personal wallpaper and drag preferences. Existing Edy startup
tasks are migrated to 3£Windows. Updates use only Ezodis/3E windows-v releases.
.PARAMETER Down
Remove 3£Windows and its startup tasks; restore backed-up input preferences.
Third-party PowerToys, WinDynamicDesktop and .NET installations are retained.
.PARAMETER KeyboardOnly
Apply only the left Alt/Ctrl swap (or remove it with -Down); restart required.
.PARAMETER AppOnly
Update the app and startup integration without changing keyboard, touchpad or
PowerToys module preferences. Used by the built-in updater.
#>
[CmdletBinding()]
param([switch]$Down, [switch]$KeyboardOnly, [switch]$AppOnly)
$ErrorActionPreference = 'Stop'
$Version = '{{VERSION}}'
$EmbeddedPowerToysKeyboardConfig = @'
{{POWERTOYS_CONFIG}}
'@
$EmbeddedKeyboardTemplate = @'
{{KEYBOARD_CONFIG}}
'@
$EmbeddedAppX64 = @'
{{APP_X64}}
'@
$EmbeddedAppArm64 = @'
{{APP_ARM64}}
'@

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    if ($Down) { $arguments += ' -Down' }
    if ($KeyboardOnly) { $arguments += ' -KeyboardOnly' }
    if ($AppOnly) { $arguments += ' -AppOnly' }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments
    exit
}
$root = Join-Path $env:ProgramFiles '3EWindows'
$data = Join-Path $env:LOCALAPPDATA '3EWindows'
$appExe = Join-Path $root '3£Windows.exe'
$backupPath = Join-Path $data 'input-backup.clixml'
$scanKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
$touchpadKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad'
$gestureNames = @('ThreeFingerSlideEnabled','ThreeFingerTapEnabled','FourFingerSlideEnabled','FourFingerTapEnabled')

function Stop-Suite {
    param([switch]$RemoveTasks)
    foreach ($task in @('3£Windows','3£Windows Resume Recovery','Edy PowerToys Startup','Edy Power Keyboard','Edy Three Finger Drag','Edy Input Resume Recovery')) {
        Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        if ($RemoveTasks) { Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue }
    }
    Get-Process -Name '3£Windows','ThreeEWindows','3EWindows.Keyboard','EdyPowerKeyboard','ThreeFingerDragOnWindows','PowerToys','PowerToys.KeyboardManagerEngine','WinDynamicDesktop' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 700
}

function Set-LeftModifierSwap {
    if ($Down) {
        Remove-ItemProperty -LiteralPath $scanKey -Name 'Scancode Map' -ErrorAction SilentlyContinue
    } else {
        [byte[]]$map = @(0,0,0,0, 0,0,0,0, 3,0,0,0, 0x1D,0,0x38,0, 0x38,0,0x1D,0, 0,0,0,0)
        Set-ItemProperty -LiteralPath $scanKey -Name 'Scancode Map' -Value $map -Type Binary
    }
}
if ($KeyboardOnly) { Set-LeftModifierSwap; Write-Host 'Restart Windows to activate the modifier change.'; exit }

function Edit-Json([string]$Path, [scriptblock]$Change) {
    $json = if (Test-Path -LiteralPath $Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    & $Change $json
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, ($json | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
}
function Set-JsonProperty($Object, [string]$Name, $Value) {
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}

function Get-InstalledApp([string]$Pattern) {
    foreach ($registry in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $app = Get-ItemProperty -Path $registry -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $Pattern } | Select-Object -First 1
        if ($app) { return $app }
    }
}
function Install-ReleaseApp([string]$Repository, [string]$AssetPattern, [string]$DisplayName, [string]$Arguments) {
    if (Get-InstalledApp $DisplayName) { return }
    $release = Invoke-RestMethod "https://api.github.com/repos/$Repository/releases/latest" -Headers @{ 'User-Agent'='3EWindows-Setup' }
    $asset = $release.assets | Where-Object name -match $AssetPattern | Select-Object -First 1
    if (-not $asset) { throw "No $DisplayName installer for this architecture." }
    $installer = Join-Path $env:TEMP ([Guid]::NewGuid().ToString('N') + '.exe')
    try {
        Invoke-WebRequest $asset.browser_download_url -OutFile $installer -UseBasicParsing
        if ((Get-AuthenticodeSignature -LiteralPath $installer).Status -ne 'Valid') { throw "$DisplayName installer signature is invalid." }
        $process = Start-Process -FilePath $installer -ArgumentList $Arguments -Wait -PassThru
        if ($process.ExitCode -notin @(0,3010)) { throw "$DisplayName installation failed ($($process.ExitCode))." }
    } finally { Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if ($Down) {
    Stop-Suite -RemoveTasks
    Unregister-ScheduledTask -TaskName '3£Windows Kiro Theme' -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'Edy Kiro Theme' -Confirm:$false -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $backupPath) {
        $backup = Import-Clixml -LiteralPath $backupPath
        foreach ($item in $backup) {
            if ($item.Exists) { Set-ItemProperty -LiteralPath $item.Path -Name $item.Name -Value $item.Value }
            else { Remove-ItemProperty -LiteralPath $item.Path -Name $item.Name -ErrorAction SilentlyContinue }
        }
    } else { Set-LeftModifierSwap }
    foreach ($driver in @((Join-Path $root 'Keyboard\install-interception.exe'),(Join-Path $env:ProgramFiles 'EdyMacKeyboard\PowerKeyboard\install-interception.exe'))) {
        if (Test-Path -LiteralPath $driver) { & $driver /uninstall | Out-Host; break }
    }
    foreach ($folder in @($root, (Join-Path $env:ProgramFiles 'EdyMacKeyboard'))) {
        $resolved = [IO.Path]::GetFullPath($folder)
        if ($resolved -notin @([IO.Path]::GetFullPath((Join-Path $env:ProgramFiles '3EWindows')),[IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'EdyMacKeyboard')))) { throw 'Unsafe uninstall path.' }
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
    $ptSettings = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\settings.json'
    if (Test-Path -LiteralPath $ptSettings) { Edit-Json $ptSettings { param($j) Set-JsonProperty $j 'show_tray_icon' $true } }
    $wallSettings = Join-Path $env:LOCALAPPDATA 'Programs\WinDynamicDesktop\settings.json'
    if (Test-Path -LiteralPath $wallSettings) { Edit-Json $wallSettings { param($j) Set-JsonProperty $j 'hideTrayIcon' $false } }
    Write-Host '3£Windows removed. Restart Windows to restore the original keyboard layout.'
    exit
}

$architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
if ($architecture -notin @('X64','Arm64')) { throw '3£Windows supports x64 and ARM64 Windows.' }
$arch = if ($architecture -eq 'Arm64') { 'arm64' } else { 'x64' }

# Install the Microsoft runtimes only when missing; no SDK or companion files.
$dotnet = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'
$hasRuntime = $false
if (Test-Path -LiteralPath $dotnet) { $hasRuntime = @(& $dotnet --list-runtimes) -match '^Microsoft.NETCore.App 10\.' }
if (-not $hasRuntime) {
    $metadata = Invoke-RestMethod 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json'
    $runtime = $metadata.releases[0].runtime.files | Where-Object { $_.rid -eq "win-$arch" -and $_.name -like '*.exe' } | Select-Object -First 1
    if (-not $runtime) { throw 'The official .NET 10 runtime installer was not found.' }
    $runtimePath = Join-Path $env:TEMP ('3EWindows-runtime-' + [Guid]::NewGuid().ToString('N') + '.exe')
    try {
        Invoke-WebRequest $runtime.url -OutFile $runtimePath -UseBasicParsing
        if ((Get-FileHash -LiteralPath $runtimePath -Algorithm SHA512).Hash -ne $runtime.hash) { throw '.NET runtime checksum mismatch.' }
        if ((Get-AuthenticodeSignature -LiteralPath $runtimePath).Status -ne 'Valid') { throw '.NET runtime signature is invalid.' }
        $process = Start-Process $runtimePath -ArgumentList '/install /quiet /norestart' -Wait -PassThru
        if ($process.ExitCode -notin @(0,3010)) { throw '.NET runtime installation failed.' }
    } finally { Remove-Item -LiteralPath $runtimePath -Force -ErrorAction SilentlyContinue }
}

if (-not (Get-AppxPackage -Name Microsoft.WindowsAppRuntime.1.8 -ErrorAction SilentlyContinue)) {
    $runtimePath = Join-Path $env:TEMP ('3EWindows-app-runtime-' + [Guid]::NewGuid().ToString('N') + '.exe')
    try {
        Invoke-WebRequest "https://aka.ms/windowsappsdk/1.8/latest/windowsappruntimeinstall-$arch.exe" -OutFile $runtimePath -UseBasicParsing
        if ((Get-AuthenticodeSignature -LiteralPath $runtimePath).Status -ne 'Valid') { throw 'Windows App Runtime signature is invalid.' }
        $process = Start-Process $runtimePath -ArgumentList '--quiet' -Wait -PassThru
        if ($process.ExitCode -notin @(0,3010)) { throw 'Windows App Runtime installation failed.' }
    } finally { Remove-Item -LiteralPath $runtimePath -Force -ErrorAction SilentlyContinue }
}

$previousTasks = @()
foreach ($taskName in @('3£Windows','3£Windows Resume Recovery','3£Windows Kiro Theme','Edy PowerToys Startup','Edy Power Keyboard','Edy Three Finger Drag','Edy Input Resume Recovery','Edy Kiro Theme')) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        $previousTasks += [pscustomobject]@{Name=$taskName;Xml=(Export-ScheduledTask -TaskName $taskName)}
    }
}
$rollback = Join-Path $env:TEMP ('3EWindows-rollback-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $rollback -Force | Out-Null
if (Test-Path -LiteralPath $root) { Copy-Item -LiteralPath $root -Destination (Join-Path $rollback 'App') -Recurse }
$previousJson = @{}
foreach ($path in @((Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\settings.json'),(Join-Path $env:LOCALAPPDATA 'Programs\WinDynamicDesktop\settings.json'))) {
    if (Test-Path -LiteralPath $path) { $previousJson[$path] = [IO.File]::ReadAllText($path) }
}
$suiteStopped = $false
trap {
    $failure = $_
    if ($suiteStopped) {
        Get-Process -Name '3£Windows','3EWindows.Keyboard' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath (Join-Path $rollback 'App')) { Copy-Item -Path (Join-Path $rollback 'App\*') -Destination $root -Recurse -Force -ErrorAction SilentlyContinue }
        foreach ($path in $previousJson.Keys) { [IO.File]::WriteAllText($path,$previousJson[$path],[Text.UTF8Encoding]::new($false)) }
        foreach ($task in $previousTasks) { Register-ScheduledTask -TaskName $task.Name -Xml $task.Xml -Force -ErrorAction SilentlyContinue | Out-Null }
        foreach ($name in @('3£Windows','Edy PowerToys Startup','Edy Power Keyboard','Edy Three Finger Drag')) {
            if ($previousTasks.Name -contains $name) { Start-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue }
        }
        Write-Warning "Setup failed; the previous app/startup registrations were restored. Backup: $rollback"
    }
    throw $failure
}
Stop-Suite
$suiteStopped = $true
New-Item -ItemType Directory -Path $root,$data -Force | Out-Null
if (-not $AppOnly -and -not (Test-Path -LiteralPath $backupPath)) {
    $backup = foreach ($entry in @(@{Path=$scanKey;Name='Scancode Map'}) + @($gestureNames | ForEach-Object { @{Path=$touchpadKey;Name=$_} })) {
        $property = Get-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
        [pscustomobject]@{Path=$entry.Path;Name=$entry.Name;Exists=($null -ne $property);Value=$(if ($property) { $property.($entry.Name) } else { $null })}
    }
    $backup | Export-Clixml -LiteralPath $backupPath
}

$payload = if ($arch -eq 'arm64') { $EmbeddedAppArm64 } else { $EmbeddedAppX64 }
$archive = Join-Path $env:TEMP ('3EWindows-' + [Guid]::NewGuid().ToString('N') + '.zip')
try {
    [IO.File]::WriteAllBytes($archive, [Convert]::FromBase64String($payload))
    Expand-Archive -LiteralPath $archive -DestinationPath $root -Force
} finally { Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue }
if (-not (Test-Path -LiteralPath $appExe)) { throw 'The embedded 3£Windows app was not extracted.' }
if ([IO.Path]::GetFullPath($PSCommandPath) -ne [IO.Path]::GetFullPath((Join-Path $root '3£Windows.ps1'))) {
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $root '3£Windows.ps1') -Force
}

Install-ReleaseApp 'microsoft/PowerToys' "^PowerToysUserSetup-.+-$arch\.exe$" 'PowerToys*' '/install /quiet /norestart'
Install-ReleaseApp 't1m0thyj/WinDynamicDesktop' "^WinDynamicDesktop_.+_$arch`_Setup\.exe$" 'WinDynamicDesktop*' '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /TASKS="registerddw"'

$ptSettings = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\settings.json'
Edit-Json $ptSettings {
    param($j)
    Set-JsonProperty $j 'startup' $false
    Set-JsonProperty $j 'run_elevated' $false
    Set-JsonProperty $j 'show_tray_icon' $false
    Set-JsonProperty $j 'enable_quick_access' $false
    if (-not $j.enabled) { Set-JsonProperty $j 'enabled' ([pscustomobject]@{}) }
    if (-not $AppOnly) {
        foreach ($feature in $j.enabled.PSObject.Properties) { $feature.Value = $false }
        foreach ($feature in @('Keyboard Manager','Workspaces')) { Set-JsonProperty $j.enabled $feature $true }
    }
    Set-JsonProperty $j.enabled 'LightSwitch' $false
}
if (-not $AppOnly) {
    Set-LeftModifierSwap
    New-Item -Path $touchpadKey -Force | Out-Null
    foreach ($gesture in $gestureNames) { Set-ItemProperty -LiteralPath $touchpadKey -Name $gesture -Value 0 -Type DWord }
    $keyboardSettings = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\Keyboard Manager'
    New-Item -ItemType Directory -Path $keyboardSettings -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $keyboardSettings 'default.json'), $EmbeddedPowerToysKeyboardConfig, [Text.UTF8Encoding]::new($false))
    Edit-Json (Join-Path $keyboardSettings 'settings.json') { param($j) Set-JsonProperty $j 'name' 'Keyboard Manager'; Set-JsonProperty $j 'version' '1.0'; Set-JsonProperty $j 'properties' ([pscustomobject]@{activeConfiguration=[pscustomobject]@{value='default'}}) }
    $winlogon = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
    New-Item -Path $winlogon -Force | Out-Null
    Set-ItemProperty -LiteralPath $winlogon -Name RestartApps -Type DWord -Value 1
}

# Device IDs are discovered here, never copied from the exporting machine.
$device = Get-PnpDevice -Class Keyboard -ErrorAction SilentlyContinue | Where-Object {
    $ids = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction SilentlyContinue).Data
    @($ids) -match '^HID\\VID_07D7&UP:0001_U:0006$'
} | Select-Object -First 1
$keyboardFolder = Join-Path $root 'Keyboard'
if ($device -and $arch -eq 'x64') {
    New-Item -ItemType Directory -Path $keyboardFolder -Force | Out-Null
    $ids = @((Get-PnpDeviceProperty -InstanceId $device.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds').Data)
    $meaningful = [Text.Encoding]::Unicode.GetBytes(($ids -join "`0") + "`0`0")
    if ($meaningful.Length -gt 1024) { throw 'Clicks hardware ID is too long.' }
    $buffer = [byte[]]::new(1024)
    [Array]::Copy($meaningful,$buffer,$meaningful.Length)
    $config = $EmbeddedKeyboardTemplate.Replace('{{POWER_KEYBOARD_HWID}}', ($buffer -join ', '))
    [IO.File]::WriteAllText((Join-Path $keyboardFolder '3EWindows.kbd'), $config, [Text.UTF8Encoding]::new($false))
    $temporary = Join-Path $env:TEMP ('3EWindows-keyboard-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    try {
        $kanata = Invoke-RestMethod 'https://api.github.com/repos/jtroo/kanata/releases/latest' -Headers @{'User-Agent'='3EWindows-Setup'}
        $asset = $kanata.assets | Where-Object name -eq 'windows-binaries-x64.zip' | Select-Object -First 1
        if (-not $asset) { throw 'The Kanata x64 asset is missing.' }
        $zip = Join-Path $temporary 'kanata.zip'
        Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
        $sumsAsset = $kanata.assets | Where-Object name -eq 'sha256sums' | Select-Object -First 1
        if (-not $sumsAsset) { throw 'Kanata release checksums are missing.' }
        $sums = (Invoke-WebRequest $sumsAsset.browser_download_url -UseBasicParsing).Content
        if ($sums -is [byte[]]) { $sums = [Text.Encoding]::UTF8.GetString($sums) }
        $checksum = [regex]::Match($sums, '(?m)^([a-fA-F0-9]{64})\s+\*?windows-binaries-x64\.zip\s*$').Groups[1].Value
        if (-not $checksum -or (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $checksum) { throw 'Kanata archive checksum mismatch.' }
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $temporary 'kanata')
        $binary = Get-ChildItem -LiteralPath (Join-Path $temporary 'kanata') -Recurse -Filter 'kanata_windows_tty_wintercept_x64.exe' | Select-Object -First 1
        if (-not $binary) { throw 'The headless Kanata Interception binary is missing.' }
        Copy-Item -LiteralPath $binary.FullName -Destination (Join-Path $keyboardFolder '3EWindows.Keyboard.exe') -Force
        $interception = Invoke-RestMethod 'https://api.github.com/repos/oblitum/Interception/releases/latest' -Headers @{'User-Agent'='3EWindows-Setup'}
        $asset = $interception.assets | Where-Object name -eq 'Interception.zip' | Select-Object -First 1
        if (-not $asset) { throw 'The Interception asset is missing.' }
        $zip = Join-Path $temporary 'interception.zip'
        Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $temporary 'interception')
        $dll = Get-ChildItem -LiteralPath (Join-Path $temporary 'interception') -Recurse -Filter interception.dll | Where-Object FullName -like '*library*x64*' | Select-Object -First 1
        $driver = Get-ChildItem -LiteralPath (Join-Path $temporary 'interception') -Recurse -Filter install-interception.exe | Select-Object -First 1
        Copy-Item -LiteralPath $dll.FullName -Destination $keyboardFolder -Force
        Copy-Item -LiteralPath $driver.FullName -Destination $keyboardFolder -Force
        if (-not (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\keyboard')) {
            & (Join-Path $keyboardFolder 'install-interception.exe') /install | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'Clicks driver installation failed.' }
            Write-Warning 'Restart Windows to activate the Clicks keyboard driver.'
        }
    } finally {
        $resolved = [IO.Path]::GetFullPath($temporary)
        if (-not $resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\3EWindows-keyboard-', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe temporary path.' }
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
} elseif ($arch -eq 'arm64' -and $device) { Write-Warning 'Clicks Interception driver is not supported on ARM64; the other features are available.' }
else { Write-Host 'Connect the Clicks keyboard and run this installer again to add its device-specific layout.' }

$wallSettings = Join-Path $env:LOCALAPPDATA 'Programs\WinDynamicDesktop\settings.json'
Edit-Json $wallSettings { param($j) Set-JsonProperty $j 'hideTrayIcon' $true }
Get-ScheduledTask -TaskPath '\PowerToys\' -ErrorAction SilentlyContinue | Where-Object TaskName -like 'Autorun*' | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
foreach ($name in @('ThreeFingerDrag','WinDynamicDesktop','Edy Mac Keyboard')) { Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $name -ErrorAction SilentlyContinue }

# Preserve the tested drag preferences across the rename.
$oldPrefs = Join-Path $env:LOCALAPPDATA 'EdyMacKeyboard\ThreeFingerDrag\preferences.json'
$newPrefs = Join-Path $data 'Drag\preferences.json'
if ((Test-Path -LiteralPath $oldPrefs) -and -not (Test-Path -LiteralPath $newPrefs)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $newPrefs) -Force | Out-Null
    Copy-Item -LiteralPath $oldPrefs -Destination $newPrefs
}

$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
foreach ($name in @('Edy PowerToys Startup','Edy Power Keyboard','Edy Three Finger Drag','Edy Input Resume Recovery')) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
}
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$trigger.Delay = 'PT10S'
$action = New-ScheduledTaskAction -Execute $appExe -WorkingDirectory $root
Register-ScheduledTask -TaskName '3£Windows' -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $taskSettings -Force | Out-Null

# Sleep recovery reopens the same app and refreshes all device hooks together.
$recovery = @'
Stop-ScheduledTask -TaskName '3£Windows' -ErrorAction SilentlyContinue
Get-Process -Name '3£Windows','3EWindows.Keyboard','PowerToys.KeyboardManagerEngine' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$launchTime = [DateTime]::UtcNow
Start-ScheduledTask -TaskName '3£Windows'
$statusPath = Join-Path $data 'status.json'
$deadline = [DateTime]::UtcNow.AddSeconds(15)
$started = $false
do {
    Start-Sleep -Seconds 1
    if ((Get-Process -Name '3£Windows' -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $statusPath) -and (Get-Item -LiteralPath $statusPath).LastWriteTimeUtc -ge $launchTime) { $started = $true; break }
} while ([DateTime]::UtcNow -lt $deadline)
if (-not $started) { throw '3£Windows did not complete startup; see Windows Application events and the local 3EWindows logs.' }
$suiteStopped = $false
$resolvedRollback = [IO.Path]::GetFullPath($rollback)
if ($resolvedRollback.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\3EWindows-rollback-', [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolvedRollback -Recurse -Force -ErrorAction SilentlyContinue }
'@
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($recovery))
$xmlUser = [Security.SecurityElement]::Escape($user)
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
<Triggers>
<EventTrigger><Enabled>true</Enabled><Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=507]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription><Delay>PT8S</Delay></EventTrigger>
<EventTrigger><Enabled>true</Enabled><Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription><Delay>PT8S</Delay></EventTrigger>
</Triggers>
<Principals><Principal id="Author"><UserId>$xmlUser</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
<Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries><StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><StartWhenAvailable>true</StartWhenAvailable><ExecutionTimeLimit>PT1M</ExecutionTimeLimit></Settings>
<Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encoded</Arguments></Exec></Actions>
</Task>
"@
Register-ScheduledTask -TaskName '3£Windows Resume Recovery' -Xml $xml -Force | Out-Null

{{KIRO_TASK}}

Start-ScheduledTask -TaskName '3£Windows'
Write-Host "3£Windows $Version installed. One tray menu owns keyboard, drag, themes and wallpaper."
Write-Host 'Copy 3£Windows.ps1 alone to another PC to install the same setup.'
if (-not $AppOnly) { Write-Host 'Restart Windows to activate the left Alt/Ctrl swap and any newly installed keyboard driver.' }
