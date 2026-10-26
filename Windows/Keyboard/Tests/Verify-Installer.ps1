param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
if($errors.Count) {throw ($errors.Message -join [Environment]::NewLine)}
function Read-EmbeddedValue([string]$Name) {
    $assignment=$ast.Find({param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq ('$'+$Name)},$true)
    if(-not $assignment) {throw "Missing embedded value: $Name"}
    # Evaluate literal AST values only, never execute the installer.
    return $assignment.Right.Expression.SafeGetValue()
}
$assets=Read-EmbeddedValue 'EmbeddedClicksAssets'
$required=@('3EWindows.Keyboard.exe','3EWindowsClicks.sys','3EWindowsInterceptionSupport.sys','interception.dll','interception_upstream.dll','ClicksAccents.exe','ClicksReconnectGuard.exe','ClicksAccents.cs','ClicksReconnectGuard.cs','clicks-output-router.c','Kanata-LICENSE.txt','Interception-LICENSE.txt','ReconnectGuard-LICENSE.txt','ThirdParty.txt')
if($assets.Count -ne $required.Count) {throw 'Unexpected embedded keyboard asset count.'}
foreach($name in $required) {
    if(-not $assets.ContainsKey($name)) {throw "Missing keyboard asset: $name"}
    $bytes=[Convert]::FromBase64String($assets[$name].Data)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {$digest=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')} finally {$sha.Dispose()}
    if($digest -ne $assets[$name].SHA256) {throw "Embedded checksum mismatch: $name"}
    if($name -match '\.(cs|c|txt)$' -and [Text.Encoding]::UTF8.GetString($bytes) -match '(?i)C:\\Users\\|DEV_[0-9A-F]{12}') {throw "Machine-specific data in $name"}
}
$profile=Read-EmbeddedValue 'EmbeddedKeyboardTemplate'
if($profile -notmatch '\{\{POWER_KEYBOARD_HWID\}\}' -or $profile -notmatch 'one-shot-release 5000' -or $profile -notmatch 'tap-dance-eager 350') {throw 'Portable keyboard rules are incomplete.'}
$picker=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($assets['ClicksAccents.cs'].Data))
if($picker -notmatch '✓ ✗ ★ ♥ ☀ ☂ ☕ ⌘ ⚡' -or $picker -match 'keyCalls|taggedCalls|public string Diagnostics') {throw 'Wrong hold-3 menu or leftover picker diagnostics.'}
Add-Type -AssemblyName System.IO.Compression
foreach($name in @('EmbeddedAppX64','EmbeddedAppArm64')) {
    $bytes=[Convert]::FromBase64String((Read-EmbeddedValue $name))
    $memory=[IO.MemoryStream]::new($bytes,$false)
    $zip=[IO.Compression.ZipArchive]::new($memory,[IO.Compression.ZipArchiveMode]::Read)
    try {
        foreach($module in @('3e.exe','MacKeyboard.json','ThreeE.KeyboardRecovery.exe','ThreeE.KeyboardRecovery.dll','ThreeE.KeyboardRecovery.runtimeconfig.json','ThreeEWindows.dll','ThreeE.PhoneBar.Windows.dll','ThreeE.PhoneControl.dll','QRCoder.dll')) {
            if(-not $zip.GetEntry($module)) {throw "Base application archive $name is missing $module"}
        }
    } finally {$zip.Dispose();$memory.Dispose()}
}
Write-Host "PASS: PowerShell $($PSVersionTable.PSVersion); 14 verified embedded assets, both app archives, portable key rules and final hold menus."
