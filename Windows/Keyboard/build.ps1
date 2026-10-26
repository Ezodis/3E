[CmdletBinding()]
param([string]$ZigPath = $env:THREEE_ZIG)
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$output = Join-Path $repository 'build\windows\keyboard'
New-Item -ItemType Directory -Path $output -Force | Out-Null

# This compiler is a build dependency only; it is never installed with the app.
if (-not $ZigPath) {
    $tools = Join-Path $repository 'build\tools'
    $ZigPath = Join-Path $tools 'zig-windows-x86_64-0.13.0\zig.exe'
    if (-not (Test-Path -LiteralPath $ZigPath)) {
        New-Item -ItemType Directory -Path $tools -Force | Out-Null
        $archive = Join-Path $tools 'zig-0.13.0.zip'
        Invoke-WebRequest 'https://ziglang.org/download/0.13.0/zig-windows-x86_64-0.13.0.zip' -OutFile $archive
        if ((Get-FileHash -LiteralPath $archive).Hash -ne 'D859994725EF9402381E557C60BB57497215682E355204D754EE3DF75EE3C158') { throw 'Zig compiler checksum mismatch.' }
        Expand-Archive -LiteralPath $archive -DestinationPath $tools -Force
        Remove-Item -LiteralPath $archive
    }
}
if (-not (Test-Path -LiteralPath $ZigPath)) { throw 'The configured Zig compiler does not exist.' }
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '.NET Framework 4 compiler is required to build the small keyboard helpers.' }
function Compile-CSharp([string]$Name, [string]$Main, [string[]]$Sources, [string]$Kind = 'winexe') {
    & $compiler /nologo /codepage:65001 /optimize+ "/target:$Kind" /platform:x64 /r:System.Windows.Forms.dll /r:System.Drawing.dll "/main:$Main" "/out:$Name" @Sources
    if ($LASTEXITCODE -ne 0) { throw "C# build failed: $Main" }
}
function Compile-Native([string]$Name, [string]$Source, [switch]$Dll) {
    $arguments = @('cc','-target','x86_64-windows-gnu','-O2','-Wall','-Wextra')
    if ($Dll) { $arguments += '-shared' }
    & $ZigPath @arguments -o $Name $Source
    if ($LASTEXITCODE -ne 0) { throw "Native build failed: $Source" }
}

$hashes = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'vendor\sha256.json') -Raw | ConvertFrom-Json
foreach ($entry in $hashes.PSObject.Properties) {
    $source = Join-Path $PSScriptRoot ('vendor\' + $entry.Name)
    if ((Get-FileHash -LiteralPath $source).Hash -ne $entry.Value) { throw "Vendor checksum mismatch: $($entry.Name)" }
    Copy-Item -LiteralPath $source -Destination $output -Force
}
foreach ($driver in @('3EWindowsClicks.sys','3EWindowsInterceptionSupport.sys')) {
    $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $output $driver)
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike '*Francisco Lopes da Silva*') { throw "Invalid driver signature: $driver" }
}
foreach ($name in @('ClicksAccents','ClicksReconnectGuard')) {
    Compile-CSharp (Join-Path $output "$name.exe") ($name.Replace('ClicksAccents','AccentProgram')) @((Join-Path $PSScriptRoot "$name.cs"))
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "$name.cs") -Destination $output -Force
}
Compile-Native (Join-Path $output 'interception.dll') (Join-Path $PSScriptRoot 'clicks-output-router.c') -Dll
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'clicks-output-router.c') -Destination $output -Force
Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*LICENSE.txt' | Copy-Item -Destination $output -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'ThirdParty.txt') -Destination $output -Force

# These tests use a simulated Interception ABI, never a physical keyboard.
$tests = Join-Path $PSScriptRoot 'Tests'
$testOutput = Join-Path $repository 'build\windows\keyboard-tests'
$routing = Join-Path $testOutput 'routing'
$sticky = Join-Path $testOutput 'sticky'
New-Item -ItemType Directory -Path $routing,$sticky -Force | Out-Null
$accentTests = Join-Path $testOutput 'AccentTests.exe'
Compile-CSharp $accentTests 'AccentTests' @((Join-Path $PSScriptRoot 'ClicksAccents.cs'),(Join-Path $tests 'AccentTests.cs')) 'exe'
$results = @(& $accentTests)
if ($LASTEXITCODE -ne 0) { throw ($results -join [Environment]::NewLine) }
Write-Host "PASS: $($results.Count) accent, number, Unicode, and isolation checks."
Compile-Native (Join-Path $routing 'interception_upstream.dll') (Join-Path $tests 'router-test-upstream.c') -Dll
Compile-Native (Join-Path $routing 'router-test.exe') (Join-Path $tests 'router-test.c')
Copy-Item -LiteralPath (Join-Path $output 'interception.dll') -Destination $routing -Force
Push-Location $routing
try { & '.\router-test.exe'; if ($LASTEXITCODE -ne 0) { throw 'Output routing tests failed.' } } finally { Pop-Location }
Compile-Native (Join-Path $sticky 'interception.dll') (Join-Path $tests 'fake-interception.c') -Dll
Copy-Item -LiteralPath (Join-Path $output '3EWindows.Keyboard.exe') -Destination (Join-Path $sticky 'kanata.exe') -Force
$hwid = New-Object byte[] 1024
$identity = [Text.Encoding]::Unicode.GetBytes("HID\{00001812-0000-1000-8000-00805f9b34fb}_Dev_VID&0107d7_PID&0000_REV&0110`0`0")
[Array]::Copy($identity,$hwid,$identity.Length)
[IO.File]::WriteAllBytes((Join-Path $sticky 'hwid.bin'),$hwid)
$profile = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'Keyboard.template.kbd')).Replace('{{POWER_KEYBOARD_HWID}}',($hwid -join ', ')).Replace('{{CTRL_AS_ALT}}','ralt').Replace('{{COMMAND_AS_CTRL}}','rctl')
[IO.File]::WriteAllText((Join-Path $sticky 'candidate.kbd'),$profile,[Text.UTF8Encoding]::new($false))
& (Join-Path $tests 'run-tests.ps1') -TestRoot $sticky
if (-not $?) { throw 'Keyboard mapping tests failed.' }
