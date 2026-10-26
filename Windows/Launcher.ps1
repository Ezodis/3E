[CmdletBinding()]
param([switch]$Wait)
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:ProgramFiles '3EWindows'
$app = Join-Path $root '3e.exe'
if (-not (Test-Path -LiteralPath $app)) { throw 'Install 3e before launching it.' }
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ThreeEPermission {
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr p,uint access,out IntPtr token);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr t,int cls,out int info,int size,out int used);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 public static bool Elevated(int pid) { IntPtr p=OpenProcess(0x1000,false,pid); if(p==IntPtr.Zero) throw new System.ComponentModel.Win32Exception(); try { IntPtr t; if(!OpenProcessToken(p,8,out t)) throw new System.ComponentModel.Win32Exception(); try { int v,n; if(!GetTokenInformation(t,20,out v,4,out n)) throw new System.ComponentModel.Win32Exception(); return v!=0; } finally {CloseHandle(t);} } finally {CloseHandle(p);} }
}
"@
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$gate = [Threading.Mutex]::new($false, ('Local\3EWindows-Launch-' + $sid))
$locked = $false
try {
    try { $locked = $gate.WaitOne(30000) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'Another 3e launch is still awaiting approval.' }
    $running = @(Get-Process -Name '3e','3£Windows' -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq (Get-Process -Id $PID).SessionId })
    $process = $running | Where-Object { [ThreeEPermission]::Elevated($_.Id) } | Select-Object -First 1
    if (-not $process) {
        # One elevation starts the tray app and all input engines together.
        foreach ($name in @('3e','3£Windows','3EWindows.Keyboard')) {
            Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq (Get-Process -Id $PID).SessionId } | Stop-Process -Force
        }
        $process = Start-Process -FilePath $app -WorkingDirectory $root -Verb RunAs -WindowStyle Hidden -PassThru
        Start-Sleep -Seconds 2
        if ((-not (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) -or -not [ThreeEPermission]::Elevated($process.Id)) { throw 'Windows did not grant administrator permission to 3e.' }
    }
} finally {
    if ($locked) { $gate.ReleaseMutex() }
    $gate.Dispose()
}
if ($Wait -and $process) { while (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 2 } }