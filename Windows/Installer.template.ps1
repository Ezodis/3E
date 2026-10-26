<#
.SYNOPSIS
3£: one tray menu for three-finger drag, Clicks keyboard, PowerToys,
automatic light/dark mode and dynamic wallpaper.
.NOTES
Phone/watch trackpad is optional and off at startup. Left-click the tray icon
and scan its QR code on iPhone. Email the same link to open it on Apple Watch.
The devices use the same trusted Wi-Fi; the trackpad needs no internet.
Missing Wi-Fi or a disconnected device never stops other suite components.
.DESCRIPTION
Portable single-file installer. The application and keyboard rules are embedded.
Copy this .ps1 alone to another Windows PC. Internet is needed to install signed
third-party dependencies not already present. Requires Windows 10 1809+ / 11,
administrator approval, and a Precision Touchpad for dragging. Clicks mapping on x64
uses a device-specific filter; no class-wide keyboard or mouse filter is installed.
Setup preserves personal wallpaper and drag preferences. Existing Edy startup
tasks are migrated to 3£Windows. Updates use only Ezodis/3E windows-v releases.
.PARAMETER Install
Reinstall explicitly. Without switches, an existing installation starts the suite.
.PARAMETER Down
Remove 3£ and its startup tasks; restore backed-up input preferences.
Third-party PowerToys, WinDynamicDesktop and .NET installations are retained.
.PARAMETER KeyboardOnly
Legacy switch: use the Mac keyboard layout tray toggle instead.
.PARAMETER RepairKeyboard
Restore the Clicks-only Command/Ctrl mapping and double-tap voice shortcut.
.PARAMETER AppOnly
Update the app and startup integration without changing keyboard, touchpad or
PowerToys module preferences. Used by the built-in updater.
#>
[CmdletBinding()]
param([switch]$Down, [switch]$KeyboardOnly, [switch]$AppOnly, [switch]$Install, [switch]$RepairKeyboard)
$ErrorActionPreference = 'Stop'
$Version = '{{VERSION}}'
# Existing installations launch without rerunning setup. Use -Install to reinstall.
$EmbeddedLauncher = @'
{{LAUNCHER}}
'@
# A current installation launches directly. A newer portable file updates the
# app and existing Clicks components without resetting personal input settings.
if (-not ($Down -or $KeyboardOnly -or $AppOnly -or $Install -or $RepairKeyboard) -and ((Test-Path -LiteralPath (Join-Path $env:ProgramFiles '3EWindows\3£.exe')) -or (Test-Path -LiteralPath (Join-Path $env:ProgramFiles '3EWindows\3e.exe')) -or (Test-Path -LiteralPath (Join-Path $env:ProgramFiles '3EWindows\3£Windows.exe')))) {
    $assembly = Join-Path $env:ProgramFiles '3EWindows\ThreeEWindows.dll'
    # Keyboard helper fixes can ship without changing the main app version.
    $accentExe = Join-Path $env:ProgramFiles '3EWindows\Keyboard\ClicksAccents.exe'
    $accentCurrent = -not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA '3EWindows\ClicksDeviceMapping.json')) -or
        ((Test-Path -LiteralPath $accentExe) -and (Get-FileHash -LiteralPath $accentExe -Algorithm SHA256).Hash -eq '{{CLICKS_ACCENTS_SHA256}}')
    if ((Test-Path -LiteralPath (Join-Path $env:ProgramFiles '3EWindows\3£.exe')) -and $accentCurrent -and (Test-Path -LiteralPath $assembly) -and [Diagnostics.FileVersionInfo]::GetVersionInfo($assembly).ProductVersion.Split('+')[0] -eq $Version) {
        & ([scriptblock]::Create($EmbeddedLauncher))
        exit
    }
    $AppOnly = $true
}

$EmbeddedPowerToysKeyboardConfig = @'
{{POWERTOYS_CONFIG}}
'@
$EmbeddedKeyboardTemplate = @'
{{KEYBOARD_CONFIG}}
'@
{{CLICKS_ASSETS}}

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
    if ($Install) { $arguments += ' -Install' }
    if ($RepairKeyboard) { $arguments += ' -RepairKeyboard' }
    Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $arguments
    exit
}
$root = Join-Path $env:ProgramFiles '3EWindows'
$data = Join-Path $env:LOCALAPPDATA '3EWindows'
$appExe = Join-Path $root '3£.exe'
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
    Get-Process -Name '3£','3e','3£Windows','ThreeEWindows','3EWindows.Keyboard','ClicksAccents','EdyPowerKeyboard','ThreeFingerDragOnWindows','WinDynamicDesktop' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 700
    # Restore the temporary keyboard profile before replacing/removing files.
    $recovery = Join-Path $root 'ThreeE.KeyboardRecovery.exe'
    if (Test-Path -LiteralPath $recovery) {
        $restored = Start-Process -FilePath $recovery -ArgumentList '--restore' -Wait -PassThru -WindowStyle Hidden
        if ($restored.ExitCode -ne 0) { throw 'Could not restore the previous keyboard configuration; setup stopped.' }
        # A crash watcher may have performed the restoration first. Let it exit
        # before replacing its executable and DLLs during an update.
        foreach ($watcher in @(Get-Process -Name 'ThreeE.KeyboardRecovery' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $recovery })) {
            if (-not $watcher.WaitForExit(5000)) { throw 'Keyboard recovery is still running; retry setup after it finishes.' }
        }
    }
    # Forced shutdown/update may bypass the optional receiver's normal cleanup.
    $phoneFirewall = $null
    try { $phoneFirewall = New-Object -ComObject HNetCfg.FwPolicy2; $phoneFirewall.Rules.Remove('3EWindows Phone Trackpad') } catch { }
    finally { if ($null -ne $phoneFirewall) { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($phoneFirewall) | Out-Null } }
}

function Edit-Json([string]$Path, [scriptblock]$Change) {
    $json = if (Test-Path -LiteralPath $Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    & $Change $json
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, ($json | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
}
function Set-JsonProperty($Object, [string]$Name, $Value) {
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}

function Remove-OwnedAppShortcuts([switch]$LegacyOnly) {
    $names = @('3e.lnk','3£Windows.lnk','3EWindows.lnk')
    if (-not $LegacyOnly) { $names += '3£.lnk' }
    $launcher = Join-Path $root 'Launch-3EWindows.ps1'
    $shell = New-Object -ComObject WScript.Shell
    try {
        foreach ($folder in @([Environment]::GetFolderPath('CommonPrograms'),[Environment]::GetFolderPath('Programs'),[Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))) {
            foreach ($name in $names) {
                $path = Join-Path $folder $name
                if (-not (Test-Path -LiteralPath $path)) { continue }
                $link = $shell.CreateShortcut($path)
                if ($link.TargetPath.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase) -or $link.Arguments.Contains($launcher)) { Remove-Item -LiteralPath $path }
            }
        }
    } finally { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null }
}

{{CLICKS_FUNCTIONS}}

if ($RepairKeyboard) {
    Restore-ClicksKeyboard
    $installedScript = Join-Path $root '3£Windows.ps1'
    if ([IO.Path]::GetFullPath($PSCommandPath) -ne [IO.Path]::GetFullPath($installedScript)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript -Force
    }
    if (Test-Path -LiteralPath $appExe) { & ([scriptblock]::Create($EmbeddedLauncher)) }
    exit
}
if ($KeyboardOnly) {
    Write-Host 'Use the Mac keyboard layout toggle in the 3£ tray menu. No registry swap or restart is needed.'
    exit
}

function Get-InstalledApp([string]$Pattern) {
    foreach ($registry in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $app = Get-ItemProperty -Path $registry -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $Pattern } | Select-Object -First 1
        if ($app) { return $app }
    }
}
function Install-ReleaseApp([string]$Repository, [string]$AssetPattern, [string]$DisplayName, [string]$Arguments, [bool]$RequireSignature = $true) {
    if (Get-InstalledApp $DisplayName) { return }
    $release = Invoke-RestMethod "https://api.github.com/repos/$Repository/releases/latest" -Headers @{ 'User-Agent'='3EWindows-Setup' }
    $asset = $release.assets | Where-Object name -match $AssetPattern | Select-Object -First 1
    if (-not $asset) { throw "No $DisplayName installer for this architecture." }
    $installer = Join-Path $env:TEMP ([Guid]::NewGuid().ToString('N') + '.exe')
    try {
        Invoke-WebRequest $asset.browser_download_url -OutFile $installer -UseBasicParsing
        $hasDigest = $asset.digest -match '^sha256:([a-fA-F0-9]{64})$'
        if ($hasDigest -and (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne $Matches[1]) { throw "$DisplayName installer checksum mismatch." }
        if ($RequireSignature -and (Get-AuthenticodeSignature -LiteralPath $installer).Status -ne 'Valid') { throw "$DisplayName installer signature is invalid." }
        if (-not $RequireSignature -and -not $hasDigest) { throw "$DisplayName official release checksum is missing." }
        $process = Start-Process -FilePath $installer -ArgumentList $Arguments -Wait -PassThru
        if ($process.ExitCode -notin @(0,3010)) { throw "$DisplayName installation failed ($($process.ExitCode))." }
    } finally { Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if ($Down) {
    Stop-Suite -RemoveTasks
    Remove-OwnedAppShortcuts
    & netsh.exe http delete urlacl url="http://+:17833/" 2>&1 | Out-Null
    $phoneRules = $null
    try { $phoneRules = New-Object -ComObject HNetCfg.FwPolicy2; foreach ($n in @('3EWindows Phone Bar (installed)','3EWindows Phone Bar name (installed)')) { try { $phoneRules.Rules.Remove($n) } catch { } } } catch { }
    finally { if ($null -ne $phoneRules) { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($phoneRules) | Out-Null } }
    Remove-ClicksDeviceMapping
    Unregister-ScheduledTask -TaskName '3£Windows Kiro Theme' -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName 'Edy Kiro Theme' -Confirm:$false -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $backupPath) {
        $backup = Import-Clixml -LiteralPath $backupPath
        foreach ($item in $backup) {
            if ($item.Exists) { Set-ItemProperty -LiteralPath $item.Path -Name $item.Name -Value $item.Value }
            else { Remove-ItemProperty -LiteralPath $item.Path -Name $item.Name -ErrorAction SilentlyContinue }
        }
    }
    foreach ($driver in @((Join-Path $root 'Keyboard\install-interception.exe'),(Join-Path $env:ProgramFiles 'EdyMacKeyboard\PowerKeyboard\install-interception.exe'))) {
        if (Test-Path -LiteralPath $driver) { & $driver /uninstall | Out-Host; break }
    }
    foreach ($folder in @($root, (Join-Path $env:ProgramFiles 'EdyMacKeyboard'))) {
        $resolved = [IO.Path]::GetFullPath($folder)
        if ($resolved -notin @([IO.Path]::GetFullPath((Join-Path $env:ProgramFiles '3EWindows')),[IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'EdyMacKeyboard')))) { throw 'Unsafe uninstall path.' }
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
    $wallSettings = Join-Path $env:LOCALAPPDATA 'Programs\WinDynamicDesktop\settings.json'
    if (Test-Path -LiteralPath $wallSettings) { Edit-Json $wallSettings { param($j) Set-JsonProperty $j 'hideTrayIcon' $false } }
    Write-Host '3£ removed. Restart Windows to restore the original keyboard layout.'
    exit
}

$architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
if ($architecture -notin @('X64','Arm64')) { throw '3£ supports x64 and ARM64 Windows.' }
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
        Get-Process -Name '3£','3e','3£Windows','3EWindows.Keyboard' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
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
    $backup = foreach ($entry in @($gestureNames | ForEach-Object { @{Path=$touchpadKey;Name=$_} })) {
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
if (-not (Test-Path -LiteralPath $appExe)) { throw 'The embedded 3£ app was not extracted.' }
foreach ($legacyName in @('3e.exe','3e.pri','3£Windows.exe','3£Windows.pri')) {
    $legacyFile = Join-Path $root $legacyName
    if (Test-Path -LiteralPath $legacyFile) { Remove-Item -LiteralPath $legacyFile }
}
if ([IO.Path]::GetFullPath($PSCommandPath) -ne [IO.Path]::GetFullPath((Join-Path $root '3£Windows.ps1'))) {
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $root '3£Windows.ps1') -Force
}

Install-ReleaseApp 'microsoft/PowerToys' "^PowerToysUserSetup-.+-$arch\.exe$" 'PowerToys*' '/install /quiet /norestart'
Install-ReleaseApp 't1m0thyj/WinDynamicDesktop' "^WinDynamicDesktop_.+_$arch`_Setup\.exe$" 'WinDynamicDesktop*' '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /TASKS="registerddw"' $false

# The tray owns a temporary Mac layout profile. Never overwrite the computer's
# PowerToys profiles, module preferences, or system Scancode Map during setup.
if (-not $AppOnly) {
    New-Item -Path $touchpadKey -Force | Out-Null
    foreach ($gesture in $gestureNames) { Set-ItemProperty -LiteralPath $touchpadKey -Name $gesture -Value 0 -Type DWord }
    $winlogon = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
    New-Item -Path $winlogon -Force | Out-Null
    Set-ItemProperty -LiteralPath $winlogon -Name RestartApps -Type DWord -Value 1
}

# Bind the signed filter only to confirmed Clicks keyboard device instances.
# App-only updates preserve the existing input configuration and enable state.
if (-not $AppOnly) { Restore-ClicksKeyboard }
elseif (Test-Path -LiteralPath (Join-Path $data 'ClicksDeviceMapping.json')) { Restore-ClicksKeyboard -PreserveEnableState }
$wallSettings = Join-Path $env:LOCALAPPDATA 'Programs\WinDynamicDesktop\settings.json'
Edit-Json $wallSettings { param($j) Set-JsonProperty $j 'hideTrayIcon' $true }
foreach ($name in @('ThreeFingerDrag','WinDynamicDesktop','Edy Mac Keyboard')) { Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $name -ErrorAction SilentlyContinue }

# Preserve the tested drag preferences across the rename.
$oldPrefs = Join-Path $env:LOCALAPPDATA 'EdyMacKeyboard\ThreeFingerDrag\preferences.json'
$newPrefs = Join-Path $data 'Drag\preferences.json'
if ((Test-Path -LiteralPath $oldPrefs) -and -not (Test-Path -LiteralPath $newPrefs)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $newPrefs) -Force | Out-Null
    Copy-Item -LiteralPath $oldPrefs -Destination $newPrefs
}

# Phone Bar must work even when 3£Windows is not running as administrator
# (for example after some updates or restarts). Reserve its port for normal
# users and allow it through the firewall once, here, where we are elevated.
$phonePort = 17833
& netsh.exe http delete urlacl url="http://+:$phonePort/" 2>&1 | Out-Null
& netsh.exe http add urlacl url="http://+:$phonePort/" sddl="D:(A;;GX;;;WD)" 2>&1 | Out-Null
$phoneRules = $null
try {
    $phoneRules = New-Object -ComObject HNetCfg.FwPolicy2
    foreach ($spec in @(@('3EWindows Phone Bar (installed)', 6, "$phonePort"), @('3EWindows Phone Bar name (installed)', 17, '5353'))) {
        try { $phoneRules.Rules.Remove($spec[0]) } catch { }
        $rule = New-Object -ComObject HNetCfg.FWRule
        $rule.Name = $spec[0]; $rule.Description = 'Lets your iPhone reach 3£ Phone Bar on this local network.'
        $rule.Protocol = $spec[1]; $rule.LocalPorts = $spec[2]; $rule.RemoteAddresses = 'LocalSubnet'
        $rule.Direction = 1; $rule.Action = 1; $rule.Profiles = 0x7FFFFFFF; $rule.EdgeTraversal = $false; $rule.Enabled = $true
        $phoneRules.Rules.Add($rule)
    }
} catch { Write-Warning ('Phone Bar firewall rule: ' + $_.Exception.Message) }
finally { if ($null -ne $phoneRules) { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($phoneRules) | Out-Null } }

$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
foreach ($name in @('Edy PowerToys Startup','Edy Power Keyboard','Edy Three Finger Drag','Edy Input Resume Recovery')) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
}
$taskPrincipal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) -LogonType Interactive -RunLevel Highest
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$trigger.Delay = 'PT10S'
$launcherPath = Join-Path $root 'Launch-3EWindows.ps1'
[IO.File]::WriteAllText($launcherPath, $EmbeddedLauncher, [Text.UTF8Encoding]::new($true))
$action = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcherPath + '" -Wait') -WorkingDirectory $root
Register-ScheduledTask -TaskName '3£Windows' -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $taskSettings -Force | Out-Null

# A stable public app name in Start/Search; old shortcuts are removed only if
# they point into this installation. Internal task/data names remain compatible.
$programs = [Environment]::GetFolderPath('CommonPrograms')
Remove-OwnedAppShortcuts -LegacyOnly
$shell = New-Object -ComObject WScript.Shell
try {
    $link = $shell.CreateShortcut((Join-Path $programs '3£.lnk'))
    $link.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $link.Arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcherPath + '"'
    $link.WorkingDirectory = $root
    $link.IconLocation = $appExe + ',0'
    $link.Description = '3£'
    $link.WindowStyle = 7
    $link.Save()
} finally { [Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null }


# Sleep recovery reuses the elevated suite; the hub refreshes device hooks after waking.
$recovery = @'
& (Join-Path $env:ProgramFiles '3EWindows\Launch-3EWindows.ps1')
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

$launchTime = [DateTime]::UtcNow
# Setup already has the elevated token required by the input engines. Starting
# through Task Scheduler can instead yield a medium token and wait on a UAC UI.
& ([scriptblock]::Create($EmbeddedLauncher))
$statusPath = Join-Path $data 'status.json'
$deadline = [DateTime]::UtcNow.AddSeconds(15)
$started = $false
do {
    Start-Sleep -Seconds 1
    if ((Get-Process -Name '3£','3e','3£Windows' -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $statusPath) -and (Get-Item -LiteralPath $statusPath).LastWriteTimeUtc -ge $launchTime) { $started = $true; break }
} while ([DateTime]::UtcNow -lt $deadline)
if (-not $started) { throw '3£ did not complete startup; see Windows Application events and the local 3EWindows logs.' }
$suiteStopped = $false
$resolvedRollback = [IO.Path]::GetFullPath($rollback)
if ($resolvedRollback.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\3EWindows-rollback-', [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolvedRollback -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "3£ $Version installed. One tray menu owns keyboard, drag, themes and wallpaper."
Write-Host 'Copy 3£Windows.ps1 alone to another PC to install the same setup.'
if (-not $AppOnly) { Write-Host 'Turn on Mac keyboard layout from the 3£ tray menu. A newly installed Clicks device driver may require a restart.' }
