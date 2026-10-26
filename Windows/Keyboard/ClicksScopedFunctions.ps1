function Initialize-ClicksDeviceApi {
    if ('ThreeEClicksDevice' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public static class ThreeEClicksDevice {
 [StructLayout(LayoutKind.Sequential)] struct DeviceInfo { public uint Size; public Guid Class; public uint DevInst; public UIntPtr Reserved; }
 [DllImport("setupapi.dll",SetLastError=true)] static extern IntPtr SetupDiCreateDeviceInfoList(IntPtr cls,IntPtr parent);
 [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetupDiOpenDeviceInfo(IntPtr set,string id,IntPtr parent,uint flags,ref DeviceInfo info);
 [DllImport("setupapi.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetupDiSetDeviceRegistryProperty(IntPtr set,ref DeviceInfo info,uint prop,byte[] value,uint size);
 [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr set);
 public static void SetUpperFilters(string id,string[] filters) {
   if(!id.StartsWith("HID\\",StringComparison.OrdinalIgnoreCase)||id.IndexOf("VID&0107D7_PID&0000",StringComparison.OrdinalIgnoreCase)<0)
     throw new ArgumentException("Refusing to change a device other than the Clicks Power Keyboard.");
   IntPtr set=SetupDiCreateDeviceInfoList(IntPtr.Zero,IntPtr.Zero);
   if(set==new IntPtr(-1))throw new Win32Exception();
   try {
     var info=new DeviceInfo {Size=(uint)Marshal.SizeOf(typeof(DeviceInfo))};
     if(!SetupDiOpenDeviceInfo(set,id,IntPtr.Zero,0,ref info))throw new Win32Exception();
     if(info.Class!=new Guid("4d36e96b-e325-11ce-bfc1-08002be10318"))throw new ArgumentException("Not a keyboard device.");
     byte[] bytes=(filters==null||filters.Length==0)?null:Encoding.Unicode.GetBytes(string.Join("\0",filters)+"\0\0");
     if(!SetupDiSetDeviceRegistryProperty(set,ref info,0x11,bytes,bytes==null?0:(uint)bytes.Length))throw new Win32Exception();
   } finally {SetupDiDestroyDeviceInfoList(set);}
 }
}
'@
}

function Get-ClicksKeyboardDevices {
    # Require both the HID vendor/product and the Bluetooth product name.
    foreach ($device in @(Get-PnpDevice -Class Keyboard -ErrorAction Stop | Where-Object InstanceId -match '^HID\\.*VID&0107D7_PID&0000')) {
        $ancestor = $device.InstanceId
        for ($depth = 0; $depth -lt 6 -and $ancestor; $depth++) {
            $node = Get-PnpDevice -InstanceId $ancestor -ErrorAction SilentlyContinue
            if ($node.FriendlyName -like 'Power Keyboard*') { $device; break }
            $ancestor = (Get-PnpDeviceProperty -InstanceId $ancestor -KeyName 'DEVPKEY_Device_Parent' -ErrorAction SilentlyContinue).Data
        }
    }
}

function Assert-ClicksClassIsolation {
    foreach ($entry in @(
        @{Class='{4D36E96B-E325-11CE-BFC1-08002BE10318}';Forbidden=@('keyboard','3EWindowsClicks','3EWindowsInterceptionSupport')},
        @{Class='{4D36E96F-E325-11CE-BFC1-08002BE10318}';Forbidden=@('mouse','3EWindowsClicks','3EWindowsInterceptionSupport')}
    )) {
        $filters = @((Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Control\Class\' + $entry.Class) -Name UpperFilters).UpperFilters)
        foreach ($filter in $entry.Forbidden) {
            if ($filters -contains $filter) { throw 'A class-wide input filter is still installed. Remove the legacy Interception installation and restart before restoring Clicks-only mapping.' }
        }
    }
}

function Get-ClicksHardwareIdBytes($Device) {
    $ids = @((Get-PnpDeviceProperty -InstanceId $Device.InstanceId -KeyName 'DEVPKEY_Device_HardwareIds' -ErrorAction Stop).Data)
    if (-not ($ids -match '^HID\\.*VID&0107D7_PID&0000')) { throw 'Clicks hardware identity could not be verified.' }
    $encoded = [Text.Encoding]::Unicode.GetBytes(($ids -join "`0") + "`0`0")
    # The installed Kanata wintercept version compares a zero-filled 1024-byte buffer.
    if ($encoded.Length -gt 1024) { throw 'The Clicks hardware ID is too large for this remapper.' }
    $buffer = New-Object byte[] 1024
    [Array]::Copy($encoded,$buffer,$encoded.Length)
    return ,$buffer
}

function Install-ClicksHelpers {
    $keyboardFolder = Join-Path $root 'Keyboard'
    $guardExe = Join-Path $keyboardFolder 'ClicksReconnectGuard.exe'
    $guardState = Join-Path $env:ProgramData '3EWindows\ClicksReconnectGuard'
    New-Item -ItemType Directory -Path $guardState -Force | Out-Null
    $stopPath = Join-Path $guardState 'stop'
    if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath -Force }
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew -StartWhenAvailable
    $action = New-ScheduledTaskAction -Execute $guardExe -Argument ('"' + $guardState + '"')
    $triggers = @((New-ScheduledTaskTrigger -AtStartup),(New-ScheduledTaskTrigger -AtLogOn))
    $principal = New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName '3EWindows Clicks Reconnect Guard' -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description 'Prevents Clicks driver keyboard-ID exhaustion after Bluetooth reconnects. No key capture.' -Force | Out-Null
    $ready = Join-Path $guardState 'ready'
    $running = @(Get-CimInstance Win32_Process -Filter "Name='ClicksReconnectGuard.exe'" | Where-Object ExecutablePath -eq $guardExe)
    if (-not $running) { Start-ScheduledTask -TaskName '3EWindows Clicks Reconnect Guard' }
    $guardReady = $false
    for($attempt=0;$attempt -lt 50;$attempt++) {
        if (Test-Path -LiteralPath $ready) {
            $value = [IO.File]::ReadAllText($ready)
            if ($value -match 'PID=(\d+)') {
                $guardPid = [int]$Matches[1]
                $running = Get-CimInstance Win32_Process -Filter "ProcessId=$guardPid" -ErrorAction SilentlyContinue
                if ($running.ExecutablePath -eq $guardExe) { $guardReady=$true; break }
            }
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not $guardReady) { throw 'The Clicks reconnect protection could not start. Mapping will not be enabled.' }
    # The live keyboard engine launches the accent UI with its elevated token.
    # Task Scheduler's HighestAvailable token can still be medium integrity.
    if (Get-ScheduledTask -TaskName '3EWindows Clicks Accents' -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName '3EWindows Clicks Accents' -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName '3EWindows Clicks Accents' -Confirm:$false
        $legacyHelpers = @(Get-Process -Name ClicksAccents -ErrorAction SilentlyContinue | Where-Object Path -eq (Join-Path $keyboardFolder 'ClicksAccents.exe'))
        $legacyHelpers | Stop-Process -Force
        foreach($helper in $legacyHelpers) { if(-not $helper.WaitForExit(5000)) { throw 'The old accent launcher did not exit.' } }
    }
}

function Restore-ClicksKeyboard {
    param([switch]$PreserveEnableState)
    $suspensionPath = Join-Path $data 'ClicksMappingSuspended.json'
    if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne 'X64') {
        Write-Warning 'Clicks-specific mapping currently requires x64 Windows.'
        return
    }
    Assert-ClicksClassIsolation
    $devices = @(Get-ClicksKeyboardDevices)
    if ($devices.Count -eq 0) { Write-Warning 'Pair the Clicks Power Keyboard with this PC, then run this installer again.'; return }
    $legacy = @(Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -in @('keyboard','mouse') -and $_.State -eq 'Running' })
    if ($legacy.Count) { throw 'Restart Windows to finish unloading the old Interception driver, then run this installer again.' }
    Initialize-ClicksDeviceApi
    $keyboardFolder = Join-Path $root 'Keyboard'
    $manifestPath = Join-Path $data 'ClicksDeviceMapping.json'
    $settingsPath = Join-Path $data 'settings.json'
    $enabledBefore = (Test-Path -LiteralPath $settingsPath) -and ([IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json).Keyboard -eq $true
    $backupFolder = Join-Path $data ('ClicksRestoreBackup-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
    New-Item -ItemType Directory -Path $keyboardFolder,$backupFolder -Force | Out-Null
    $before = @($devices | ForEach-Object {
        [pscustomobject]@{InstanceId=$_.InstanceId;Filters=@((Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_UpperFilters' -ErrorAction SilentlyContinue).Data | Where-Object {$_})}
    })
    $before | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backupFolder 'device-filters.json') -Encoding UTF8
    foreach ($file in @($settingsPath,$manifestPath,(Join-Path $keyboardFolder '3EWindows.kbd'),(Join-Path $keyboardFolder '3EWindows.Keyboard.exe'),(Join-Path $keyboardFolder 'interception.dll'),(Join-Path $keyboardFolder 'interception_upstream.dll'))) {
        if (Test-Path -LiteralPath $file) { Copy-Item -LiteralPath $file -Destination $backupFolder }
    }
    $suiteWasRunning = $null -ne (Get-Process -Name '3£','3e','3£Windows' -ErrorAction SilentlyContinue)
    $suiteStopped = $false
    $createdServices = @()
    $changedDevices = @()
    try {
        # Decode and verify everything before changing device registration.
        foreach ($asset in $EmbeddedClicksAssets.GetEnumerator()) {
            $assetPath = Join-Path $keyboardFolder $asset.Key
            $bytes = [Convert]::FromBase64String($asset.Value.Data)
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $digest = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
            if ($digest -ne $asset.Value.SHA256) { throw "Embedded Clicks asset checksum mismatch: $($asset.Key)" }
            if ((Test-Path -LiteralPath $assetPath) -and (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash -eq $digest) { continue }
            if ($asset.Key -in @('3EWindows.Keyboard.exe','interception.dll','interception_upstream.dll','ClicksReconnectGuard.exe','ClicksAccents.exe')) {
                $stopping = @(Get-Process -Name '3£','3e','3£Windows','3EWindows.Keyboard' -ErrorAction SilentlyContinue)
                $stopping | Stop-Process -Force
                foreach ($process in $stopping) { if (-not $process.WaitForExit(5000)) { throw 'Keyboard process did not exit for update.' } }
                $suiteStopped = $true
                if ($asset.Key -eq 'ClicksReconnectGuard.exe') {
                    Stop-ScheduledTask -TaskName '3EWindows Clicks Reconnect Guard' -ErrorAction SilentlyContinue
                    $helpers = @(Get-Process -Name ClicksReconnectGuard -ErrorAction SilentlyContinue)
                    $helpers | Stop-Process -Force
                    foreach($helper in $helpers) { if(-not $helper.WaitForExit(5000)) { throw 'Reconnect guard did not exit for update.' } }
                }
                if ($asset.Key -eq 'ClicksAccents.exe') {
                    Stop-ScheduledTask -TaskName '3EWindows Clicks Accents' -ErrorAction SilentlyContinue
                    $helpers = @(Get-Process -Name ClicksAccents -ErrorAction SilentlyContinue)
                    $helpers | Stop-Process -Force
                    foreach($helper in $helpers) { if(-not $helper.WaitForExit(5000)) { throw 'Accent picker did not exit for update.' } }
                }
            }
            [IO.File]::WriteAllBytes($assetPath,$bytes)
        }
        # Create and verify reconnect protection before attaching the keyboard filter.
        Install-ClicksHelpers
        foreach ($driver in @('3EWindowsClicks.sys','3EWindowsInterceptionSupport.sys')) {
            $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $keyboardFolder $driver)
            if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike '*Francisco Lopes da Silva*') { throw "Invalid Clicks driver signature: $driver" }
        }
        $hwids = @($devices | ForEach-Object { (Get-ClicksHardwareIdBytes $_) -join ', ' } | Select-Object -Unique)
        $profile = $EmbeddedKeyboardTemplate.Replace('"{{POWER_KEYBOARD_HWID}}"',(('    "' + ($hwids -join "`"`r`n    `"") + '"').TrimStart()))
        # Compensate for the existing system map without changing other keyboards.
        $scanMap = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' -Name 'Scancode Map' -ErrorAction SilentlyContinue).'Scancode Map'
        $swapAlt = $false
        $swapCtrl = $false
        if ($scanMap -and $scanMap.Length -ge 16) {
            for ($offset=12; $offset -le $scanMap.Length-8; $offset+=4) {
                $entry = [BitConverter]::ToUInt32($scanMap,$offset)
                if ($entry -eq 0x0038001D) { $swapAlt = $true }
                if ($entry -eq 0x001D0038) { $swapCtrl = $true }
            }
        }
        if ($swapAlt -ne $swapCtrl) { throw 'A partial Alt/Ctrl system remap was found; the Clicks profile needs an explicit matching configuration.' }
        # Right Alt avoids the existing left-Alt shortcut remaps (Alt+Tab -> Ctrl+Tab).
        # It is unaffected by the system's left Alt/Ctrl scan-code swap.
        $ctrlOutput = 'ralt'
        $commandOutput = 'rctl'
        $profile = $profile.Replace('{{CTRL_AS_ALT}}',$ctrlOutput).Replace('{{COMMAND_AS_CTRL}}',$commandOutput)
        $profilePath = Join-Path $keyboardFolder '3EWindows.kbd'
        $profileMatches = (Test-Path -LiteralPath $profilePath) -and [IO.File]::ReadAllText($profilePath) -ceq $profile
        $allScoped = @($before | Where-Object { $_.Filters -notcontains '3EWindowsClicks' }).Count -eq 0
        $servicesReady = $true
        foreach ($serviceName in @('3EWindowsClicks','3EWindowsInterceptionSupport')) {
            $saved = Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $serviceName) -ErrorAction SilentlyContinue
            if (-not $saved -or $saved.Type -ne 1 -or $saved.Start -ne 1 -or $saved.ImagePath -ne ('\SystemRoot\System32\drivers\' + $serviceName + '.sys') -or
                (Get-Service -Name $serviceName -ErrorAction SilentlyContinue).Status -ne 'Running') { $servicesReady = $false }
        }
        $enabled = (Test-Path -LiteralPath $settingsPath) -and ([IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json).Keyboard -eq $true
        if ($profileMatches -and $allScoped -and $servicesReady -and $enabled -and (Test-Path -LiteralPath $manifestPath)) {
            if (Test-Path -LiteralPath $suspensionPath) { Move-Item -LiteralPath $suspensionPath -Destination (Join-Path $backupFolder 'ClicksMappingSuspended-resolved.json') }
            Write-Host 'Clicks-only mapping is already configured. Command/Ctrl and voice shortcuts are preserved.'
            return
        }
        Get-Process -Name '3£','3e','3£Windows','3EWindows.Keyboard' -ErrorAction SilentlyContinue | Stop-Process -Force
        $suiteStopped = $true
        [IO.File]::WriteAllText($profilePath,$profile,[Text.UTF8Encoding]::new($false))
        $check = Start-Process -FilePath (Join-Path $keyboardFolder '3EWindows.Keyboard.exe') -ArgumentList ('--check --cfg "' + $profilePath + '"') -WindowStyle Hidden -Wait -PassThru
        if ($check.ExitCode -ne 0) { throw "Clicks keyboard profile validation failed ($($check.ExitCode))." }

        foreach ($serviceName in @('3EWindowsClicks','3EWindowsInterceptionSupport')) {
            $sourcePath = Join-Path $keyboardFolder ($serviceName + '.sys')
            $driverPath = Join-Path $env:WINDIR ('System32\drivers\' + $serviceName + '.sys')
            $imagePath = '\SystemRoot\System32\drivers\' + $serviceName + '.sys'
            if (-not (Test-Path -LiteralPath $driverPath)) { Copy-Item -LiteralPath $sourcePath -Destination $driverPath }
            elseif ((Get-FileHash -LiteralPath $driverPath).Hash -ne (Get-FileHash -LiteralPath $sourcePath).Hash) { throw "Unexpected existing driver at $driverPath" }
            $servicePath = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $serviceName
            if (Test-Path -LiteralPath $servicePath) {
                $saved = Get-ItemProperty -LiteralPath $servicePath
                if ($saved.ImagePath -ne $imagePath -or $saved.Type -ne 1) { throw "Unexpected service configuration: $serviceName" }
                if ($saved.Start -ne 1) {
                    & sc.exe config $serviceName start= system | Out-Host
                    if ($LASTEXITCODE -ne 0) { throw "Could not restore $serviceName startup" }
                }
            } else {
                & sc.exe create $serviceName type= kernel start= system binPath= $imagePath | Out-Host
                if ($LASTEXITCODE -ne 0) { throw "Could not register $serviceName" }
                $createdServices += $serviceName
            }
        }
        # The compatibility DLL requires both control-device banks. The support
        # driver is loaded without attachment to ANY mouse or keyboard device.
        foreach ($serviceName in @('3EWindowsInterceptionSupport','3EWindowsClicks')) {
            if ((Get-Service -Name $serviceName -ErrorAction Stop).Status -ne 'Running') {
                & sc.exe start $serviceName | Out-Host
                if ($LASTEXITCODE -ne 0) { throw "Could not start $serviceName" }
            }
        }
        foreach ($device in $devices) {
            $previous = @($before | Where-Object InstanceId -eq $device.InstanceId)[0]
            if ($previous.Filters -notcontains '3EWindowsClicks') {
                [ThreeEClicksDevice]::SetUpperFilters($device.InstanceId,[string[]](@($previous.Filters) + '3EWindowsClicks'))
                $changedDevices += $device.InstanceId
                # Exact instance ID only. Never restart the keyboard class or other devices.
                if ($device.Status -eq 'OK') {
                    & pnputil.exe /restart-device $device.InstanceId | Out-Host
                    if ($LASTEXITCODE -notin @(0,3010)) { throw 'Windows could not refresh the Clicks keyboard.' }
                }
            }
        }
        Assert-ClicksClassIsolation
        [pscustomobject]@{Version=1;Devices=@($devices.InstanceId);Backend='device-filter';KeyboardService='3EWindowsClicks';SupportService='3EWindowsInterceptionSupport';Backup=$backupFolder} |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
        Edit-Json $settingsPath { param($j) Set-JsonProperty $j 'Keyboard' $(if($PreserveEnableState) {$enabledBefore} else {$true}) }
        if (Test-Path -LiteralPath $suspensionPath) { Move-Item -LiteralPath $suspensionPath -Destination (Join-Path $backupFolder 'ClicksMappingSuspended-resolved.json') }
        Write-Host 'Clicks mapping restored: Command = Ctrl; Ctrl = Alt; six-dot key = Windows; red Clicks key = Tab; double-tap Command = dictation.'
        Write-Host "Only the Clicks device is filtered. Backup: $backupFolder"
        Write-Host 'Reconnect protection and numbered hold-to-accent picker are enabled.'
    } catch {
        $failure = $_
        foreach ($id in $changedDevices) {
            $previous = @($before | Where-Object InstanceId -eq $id)[0]
            [ThreeEClicksDevice]::SetUpperFilters($id,[string[]]$previous.Filters)
            & pnputil.exe /restart-device $id | Out-Host
        }
        foreach ($serviceName in $createdServices) { & sc.exe stop $serviceName | Out-Null; & sc.exe delete $serviceName | Out-Null }
        if (Test-Path -LiteralPath (Join-Path $backupFolder 'settings.json')) { Copy-Item -LiteralPath (Join-Path $backupFolder 'settings.json') -Destination $settingsPath -Force }
        else { Edit-Json $settingsPath { param($j) Set-JsonProperty $j 'Keyboard' $false } }
        if (Test-Path -LiteralPath (Join-Path $backupFolder 'ClicksDeviceMapping.json')) { Copy-Item -LiteralPath (Join-Path $backupFolder 'ClicksDeviceMapping.json') -Destination $manifestPath -Force }
        else { Remove-Item -LiteralPath $manifestPath -Force -ErrorAction SilentlyContinue }
        foreach ($name in @('3EWindows.kbd','3EWindows.Keyboard.exe','interception.dll','interception_upstream.dll')) {
            if (Test-Path -LiteralPath (Join-Path $backupFolder $name)) { Copy-Item -LiteralPath (Join-Path $backupFolder $name) -Destination (Join-Path $keyboardFolder $name) -Force }
        }
        throw $failure
    } finally {
        if ($suiteWasRunning -and $suiteStopped -and (Test-Path -LiteralPath $appExe)) { Start-Process -FilePath $appExe -WorkingDirectory $root -WindowStyle Hidden | Out-Null }
    }
}

function Remove-ClicksDeviceMapping {
    $manifestPath = Join-Path $data 'ClicksDeviceMapping.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { return }
    Initialize-ClicksDeviceApi
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($id in @($manifest.Devices)) {
        if (-not (Get-PnpDevice -InstanceId $id -ErrorAction SilentlyContinue)) { continue }
        $filters = @((Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_UpperFilters' -ErrorAction SilentlyContinue).Data | Where-Object { $_ -and $_ -ne '3EWindowsClicks' })
        [ThreeEClicksDevice]::SetUpperFilters($id,[string[]]$filters)
        & pnputil.exe /restart-device $id | Out-Host
    }
    foreach ($serviceName in @('3EWindowsClicks','3EWindowsInterceptionSupport')) {
        if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) { & sc.exe stop $serviceName | Out-Null; & sc.exe delete $serviceName | Out-Null }
    }
    foreach ($task in @('3EWindows Clicks Accents','3EWindows Clicks Reconnect Guard')) {
        Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
    }
    Get-Process -Name ClicksAccents,ClicksReconnectGuard -ErrorAction SilentlyContinue | Stop-Process -Force
    Remove-Item -LiteralPath $manifestPath -Force
}
