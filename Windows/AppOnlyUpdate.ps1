# Embedded into the portable installer. This path only replaces application files;
# it never runs the full installer's setup, recovery, dependency or launcher code.
function Get-ThreeEUpdatePath([string]$Base, [string]$Relative) {
    $basePath = [IO.Path]::GetFullPath($Base).TrimEnd('\') + '\'
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative.Contains(':') -or $Relative -match '(^|[\\/])\.{1,2}([\\/]|$)') { throw 'Unsafe update entry.' }
    $path = [IO.Path]::GetFullPath((Join-Path $basePath $Relative))
    if (-not $path.StartsWith($basePath, [StringComparison]::OrdinalIgnoreCase)) { throw 'Update entry escapes its directory.' }
    # Never follow an existing junction/symlink into another installation or data directory.
    $parent = $path
    while ($parent -and $parent.Length -ge $basePath.TrimEnd('\').Length) {
        if ((Test-Path -LiteralPath $parent) -and ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Update path contains a reparse point: $parent"
        }
        $parent = Split-Path -Parent $parent
    }
    return $path
}

function Stop-ThreeEUpdateProcesses([string]$Root) {
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $session = (Get-Process -Id $PID).SessionId
    $owned = @(Get-Process | Where-Object {
        $_.Id -ne $PID -and $_.SessionId -eq $session -and $_.Path -and
        $_.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
    })
    foreach ($process in $owned) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction Stop }
    }
    foreach ($process in $owned) {
        if (-not $process.WaitForExit(10000)) { throw 'An application file is still in use. Close 3£ and retry.' }
    }
}

function Assert-ThreeEUpdateVersion([string]$Directory, [string]$Version) {
    foreach ($name in @('3£.exe','ThreeEWindows.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Directory $name) -PathType Leaf)) { throw "Incomplete app update: $name" }
    }
    $actual = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $Directory 'ThreeEWindows.dll')).FileVersion
    if ([version]$actual -ne [version]($Version + '.0')) { throw "Unexpected app version: $actual" }
}

function Invoke-ThreeEAppOnlyUpdate {
    param([string]$Root, [string]$Payload, [string]$Version, [string]$InstallerPath)
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'ThreeEWindows.dll'))) {
        throw '-AppOnly requires an existing installation. It does not install prerequisites or configure Windows.'
    }
    # Validate root before creating staging files or stopping anything.
    $null = Get-ThreeEUpdatePath $Root 'ThreeEWindows.dll'
    $work = Join-Path $env:TEMP ('3EWindows-AppOnly-' + [Guid]::NewGuid().ToString('N'))
    $stage = Join-Path $work 'stage'
    $backup = Join-Path $work 'backup'
    New-Item -ItemType Directory -Path $stage,$backup -Force | Out-Null
    $files = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $changed = [Collections.Generic.List[object]]::new()
    $committed = $false
    try {
        Add-Type -AssemblyName System.IO.Compression
        $memory = [IO.MemoryStream]::new([Convert]::FromBase64String($Payload), $false)
        $zip = [IO.Compression.ZipArchive]::new($memory, [IO.Compression.ZipArchiveMode]::Read)
        try {
            foreach ($entry in $zip.Entries) {
                if (-not $entry.Name) { continue }
                $relative = $entry.FullName.Replace('/', '\')
                if (-not $seen.Add($relative)) { throw 'Duplicate update entry.' }
                # These files belong to the deployment, not the app release.
                if ([IO.Path]::GetFileName($relative) -match '^(network-policy\.json|settings\.json|input-backup\.clixml|Launch-3EWindows\.(ps1|vbs))$') {
                    throw "App-only update cannot replace deployment settings: $relative"
                }
                $destination = Get-ThreeEUpdatePath $stage $relative
                $null = Get-ThreeEUpdatePath $Root $relative
                New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                $entryStream = $entry.Open()
                $outputStream = [IO.File]::Create($destination)
                try { $entryStream.CopyTo($outputStream) } finally { $outputStream.Dispose(); $entryStream.Dispose() }
                $files.Add($relative)
            }
        } finally { $zip.Dispose(); $memory.Dispose() }
        Assert-ThreeEUpdateVersion $stage $Version
        # Retain the reviewed installer for future manual updates, without changing launchers.
        if ($InstallerPath -and [IO.Path]::GetFullPath($InstallerPath) -ne [IO.Path]::GetFullPath((Join-Path $Root '3£Windows.ps1'))) {
            Copy-Item -LiteralPath $InstallerPath -Destination (Join-Path $stage '3£Windows.ps1')
            $files.Add('3£Windows.ps1')
        }
        # Back up before stopping the app. Nothing outside its installation is written.
        foreach ($relative in $files) {
            $destination = Get-ThreeEUpdatePath $Root $relative
            if (Test-Path -LiteralPath $destination) {
                $saved = Get-ThreeEUpdatePath $backup $relative
                New-Item -ItemType Directory -Path (Split-Path -Parent $saved) -Force | Out-Null
                Copy-Item -LiteralPath $destination -Destination $saved
            }
        }
        Stop-ThreeEUpdateProcesses $Root
        foreach ($relative in $files) {
            $destination = Get-ThreeEUpdatePath $Root $relative
            $existed = Test-Path -LiteralPath $destination
            $changed.Add([pscustomobject]@{Relative=$relative;Existed=$existed})
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $stage $relative) -Destination $destination -Force -ErrorAction Stop
            if ((Get-FileHash -LiteralPath $destination).Hash -ne (Get-FileHash -LiteralPath (Join-Path $stage $relative)).Hash) {
                throw "App file verification failed: $relative"
            }
        }
        Assert-ThreeEUpdateVersion $Root $Version
        $committed = $true
        Write-Host "3£ $Version updated. Network rules, startup registrations, drivers and preferences were not configured."
        Write-Host 'Start 3£ when ready. Existing launchers and task enable states are preserved.'
    } catch {
        $failure = $_
        $restoreErrors = @()
        foreach ($item in $changed) {
            try {
                $destination = Get-ThreeEUpdatePath $Root $item.Relative
                if ($item.Existed) {
                    $saved = Join-Path $backup $item.Relative
                    if (-not (Test-Path -LiteralPath $destination) -or (Get-FileHash -LiteralPath $destination).Hash -ne (Get-FileHash -LiteralPath $saved).Hash) {
                        Copy-Item -LiteralPath $saved -Destination $destination -Force -ErrorAction Stop
                    }
                }
                elseif (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force -ErrorAction Stop }
            } catch { $restoreErrors += $_.Exception.Message }
        }
        if ($restoreErrors.Count) { Write-Warning ("File rollback needs attention. Backup: $backup. " + ($restoreErrors -join '; ')) }
        throw $failure
    } finally {
        # Retain failure evidence/backups. Successful staging is confined to this generated folder.
        $resolved = [IO.Path]::GetFullPath($work)
        $prefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\3EWindows-AppOnly-'
        if ($committed -and $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
