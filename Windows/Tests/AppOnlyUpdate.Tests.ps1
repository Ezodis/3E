$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $sourceRoot 'AppOnlyUpdate.ps1')
$testRoot = Join-Path $env:TEMP ('3EWindows-UpdateTest-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$script:checks = 0
function Check($condition, [string]$message) {
    if (-not $condition) { throw $message }
    $script:checks++
}
function Must-Fail([scriptblock]$action, [string]$message) {
    $failed = $false
    try { & $action } catch { $failed = $true }
    Check $failed $message
}
function Stop-ThreeEUpdateProcesses([string]$Root) { $script:stops++ }
function New-TestInstall([string]$Name) {
    $dir = Join-Path $testRoot $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'ThreeEWindows.dll'), 'old application')
    [IO.File]::WriteAllText((Join-Path $dir '3£.exe'), 'old apphost')
    foreach ($name in @('network-policy.json','settings.json','Launch-3EWindows.ps1','Launch-3EWindows.vbs')) {
        [IO.File]::WriteAllText((Join-Path $dir $name), 'preserve exactly')
    }
    return $dir
}
function New-TestPayload([hashtable]$Extra = @{}) {
    $stream = [IO.MemoryStream]::new()
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
    $entries = [ordered]@{'3£.exe'=[Text.Encoding]::UTF8.GetBytes('new apphost');'ThreeEWindows.dll'=[IO.File]::ReadAllBytes($script:fixture)}
    foreach ($key in $Extra.Keys) { $entries[$key] = [Text.Encoding]::UTF8.GetBytes($Extra[$key]) }
    try {
        foreach ($key in $entries.Keys) {
            $entry = $zip.CreateEntry($key); $writer = $entry.Open()
            try { $writer.Write($entries[$key],0,$entries[$key].Length) } finally { $writer.Dispose() }
        }
    } finally { $zip.Dispose() }
    try { return [Convert]::ToBase64String($stream.ToArray()) } finally { $stream.Dispose() }
}
try {
    Add-Type -AssemblyName System.IO.Compression
    $script:fixture = Join-Path $testRoot 'fixture.dll'
    Add-Type -TypeDefinition 'using System.Reflection; [assembly: AssemblyFileVersion("3.0.999.0")] public class AppOnlyFixture {}' -OutputAssembly $fixture
    $payload = New-TestPayload @{'new-module.txt'='new module'}
    $script:stops = 0
    $dir = New-TestInstall 'success'
    $installer = Join-Path $testRoot 'installer.ps1'
    [IO.File]::WriteAllText($installer, '# reviewed installer')
    Invoke-ThreeEAppOnlyUpdate -Root $dir -Payload $payload -Version '3.0.999' -InstallerPath $installer
    Check ([IO.File]::ReadAllText((Join-Path $dir '3£.exe')) -eq 'new apphost') 'Apphost was not updated.'
    Check ((Get-FileHash (Join-Path $dir 'ThreeEWindows.dll')).Hash -eq (Get-FileHash $fixture).Hash) 'DLL hash mismatch.'
    Check ($script:stops -eq 1) 'Expected one owned-process stop.'
    foreach ($name in @('network-policy.json','settings.json','Launch-3EWindows.ps1','Launch-3EWindows.vbs')) {
        Check ([IO.File]::ReadAllText((Join-Path $dir $name)) -eq 'preserve exactly') "Changed deployment file: $name"
    }
    Check ([IO.File]::ReadAllText((Join-Path $dir '3£Windows.ps1')) -eq '# reviewed installer') 'Reviewed installer was not retained.'

    foreach ($bad in @('..\escape.txt','dir\..\alias.txt','C:\escape.txt','file:stream','settings.json','network-policy.json','Launch-3EWindows.ps1')) {
        $dir = New-TestInstall ([Guid]::NewGuid().ToString('N'))
        $before = $script:stops
        Must-Fail { Invoke-ThreeEAppOnlyUpdate -Root $dir -Payload (New-TestPayload @{$bad='bad'}) -Version '3.0.999' } "Accepted unsafe payload: $bad"
        Check ($script:stops -eq $before) 'Invalid payload stopped the app before validation.'
        Check ([IO.File]::ReadAllText((Join-Path $dir 'ThreeEWindows.dll')) -eq 'old application') 'Invalid payload changed app files.'
    }
    $dir = New-TestInstall 'wrong-version'
    Must-Fail { Invoke-ThreeEAppOnlyUpdate -Root $dir -Payload $payload -Version '3.0.998' } 'Accepted wrong release version.'
    Check ([IO.File]::ReadAllText((Join-Path $dir '3£.exe')) -eq 'old apphost') 'Wrong version changed app files.'
    Must-Fail { Invoke-ThreeEAppOnlyUpdate -Root (Join-Path $testRoot 'absent') -Payload $payload -Version '3.0.999' } 'AppOnly performed a fresh install.'

    # An actual sharing violation after the first write must restore existing files.
    $dir = New-TestInstall 'rollback'
    $locked = [IO.File]::Open((Join-Path $dir 'ThreeEWindows.dll'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try { Must-Fail { Invoke-ThreeEAppOnlyUpdate -Root $dir -Payload $payload -Version '3.0.999' } 'Expected locked-file failure.' }
    finally { $locked.Dispose() }
    Check ([IO.File]::ReadAllText((Join-Path $dir '3£.exe')) -eq 'old apphost') 'Rollback left the new apphost installed.'
    Check ([IO.File]::ReadAllText((Join-Path $dir 'ThreeEWindows.dll')) -eq 'old application') 'Rollback damaged the locked file.'

    # Verify the whole installer routes AppOnly before full setup, not just the helper.
    $template = [IO.File]::ReadAllText((Join-Path $sourceRoot 'Installer.template.ps1'))
    $helper = [IO.File]::ReadAllText((Join-Path $sourceRoot 'AppOnlyUpdate.ps1'))
    Check ($template.IndexOf('if ($AppOnly) {') -lt $template.IndexOf('function Stop-Suite')) 'AppOnly does not exit before full setup.'
    Check ($template -match '(?s)Invoke-ThreeEAppOnlyUpdate.*?\bexit\s*\}') 'AppOnly falls through to full setup.'
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($helper,[ref]$tokens,[ref]$errors)
    Check (-not $errors.Count) 'AppOnly helper parse error.'
    $commands = $ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true) | ForEach-Object { $_.GetCommandName() }
    foreach ($forbidden in @('Register-ScheduledTask','Unregister-ScheduledTask','Enable-ScheduledTask','Disable-ScheduledTask','Start-ScheduledTask','Set-ItemProperty','Remove-ItemProperty','New-NetFirewallRule','Remove-NetFirewallRule','netsh.exe','Start-Process','Invoke-WebRequest','Invoke-RestMethod','Set-ExecutionPolicy')) {
        Check ($commands -notcontains $forbidden) "AppOnly calls forbidden configuration command: $forbidden"
    }
    Check ($helper -notmatch 'HNetCfg|ScriptBlock\]::Create|Invoke-Expression|Restore-ClicksKeyboard') 'AppOnly invokes full-setup side effects.'
    Check (-not $template.Contains('$arguments = ''-NoProfile -ExecutionPolicy Bypass')) 'Manual elevation bypasses execution policy.'
    Check (-not $template.Contains('$accentCurrent')) 'Preserved device helpers cause repeated app-only installs.'
    Write-Host "PASS: $checks app-only update, preservation, preflight and rollback checks."
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $prefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\3EWindows-UpdateTest-'
    if ($resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
