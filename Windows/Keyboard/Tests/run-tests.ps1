param([Parameter(Mandatory=$true)][string]$TestRoot)
$ErrorActionPreference='Stop'
$cases=@(
    @{Name='command-once'; Input=@('100 5B 02','160 5B 03','700 2E 00','760 2E 01','900 20 00','960 20 01'); Expect=@('1D:02','2E:00','2E:01','1D:03','20:00','20:01')},
    @{Name='shift-once'; Input=@('100 2A 00','160 2A 01','700 2E 00','760 2E 01','900 20 00','960 20 01'); Expect=@('2A:00','2E:00','2E:01','2A:01','20:00','20:01')},
    @{Name='command-then-shift'; Input=@('100 5B 02','160 5B 03','700 2A 00','760 2A 01','1100 2E 00','1160 2E 01','1300 20 00','1360 20 01'); Expect=@('1D:02','2A:00','2E:00','2E:01','1D:03','2A:01','20:00','20:01')},
    @{Name='shift-then-command'; Input=@('100 2A 00','160 2A 01','700 5B 02','760 5B 03','1100 2E 00','1160 2E 01','1300 20 00','1360 20 01'); Expect=@('2A:00','1D:02','2E:00','2E:01','2A:01','1D:03','20:00','20:01')},
    @{Name='double-command-dictation'; Input=@('100 5B 02','160 5B 03','240 5B 02','300 5B 03','700 2E 00','760 2E 01'); Expect=@('1D:02','1D:03','5B:02','23:00','5B:03','23:01','2E:00','2E:01')},
    @{Name='shift-then-dictation'; Input=@('100 2A 00','160 2A 01','700 5B 02','760 5B 03','840 5B 02','900 5B 03','1300 2E 00','1360 2E 01'); Expect=@('2A:00','1D:02','2A:01','1D:03','5B:02','23:00','5B:03','23:01','2E:00','2E:01')},
    @{Name='command-timeout'; Input=@('100 5B 02','160 5B 03','5400 2E 00','5460 2E 01'); Expect=@('1D:02','1D:03','2E:00','2E:01')},
    @{Name='shift-timeout'; Input=@('100 2A 00','160 2A 01','5400 2E 00','5460 2E 01'); Expect=@('2A:00','2A:01','2E:00','2E:01')},
    @{Name='held-command'; Input=@('100 5B 02','700 2E 00','760 2E 01','900 20 00','960 20 01','1100 5B 03','1500 12 00','1560 12 01'); Expect=@('1D:02','2E:00','2E:01','20:00','20:01','1D:03','12:00','12:01')},
    @{Name='held-shift'; Input=@('100 2A 00','700 2E 00','760 2E 01','900 20 00','960 20 01','1100 2A 01','1500 12 00','1560 12 01'); Expect=@('2A:00','2E:00','2E:01','20:00','20:01','2A:01','12:00','12:01')},
    @{Name='rapid-command-shift'; Input=@('100 5B 02','160 5B 03','200 2A 00','260 2A 01','300 2E 00','360 2E 01','500 20 00','560 20 01'); Expect=@('1D:02','2A:00','2E:00','2E:01','1D:03','2A:01','20:00','20:01')},
    @{Name='ctrl-alt-red-tab'; Input=@('100 1D 00','300 0F 00','360 0F 01','500 1D 01'); Expect=@('38:02','0F:00','0F:01','38:03')},
    @{Name='labeled-ctrl-alone'; Input=@('100 1D 00','180 1D 01'); Expect=@('38:02','38:03')},
    @{Name='red-unchanged'; Input=@('100 0F 00','180 0F 01'); Expect=@('0F:00','0F:01')},
    @{Name='six-dot-unchanged'; Input=@('100 38 00','120 25 00','180 25 01','200 38 01'); Expect=@('5B:02','5B:03')},
    @{Name='command-red-tab-once'; Input=@('100 5B 02','160 5B 03','700 0F 00','760 0F 01','900 20 00','960 20 01'); Expect=@('1D:02','0F:00','0F:01','1D:03','20:00','20:01')},
    @{Name='stack-restarts-timeout'; Input=@('100 5B 02','160 5B 03','4400 2A 00','4460 2A 01','5500 2E 00','5560 2E 01','5700 20 00','5760 20 01'); Expect=@('1D:02','2A:00','2E:00','2E:01','1D:03','2A:01','20:00','20:01')}
)
$jobs=@()
foreach($case in $cases){
    $inputPath=Join-Path $testRoot ($case.Name+'.input.txt')
    $outputPath=Join-Path $testRoot ($case.Name+'.output.txt')
    [IO.File]::WriteAllLines($inputPath,$case.Input)
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $testRoot 'kanata.exe'
    $start.Arguments='--quiet --no-wait --nodelay --cfg "'+(Join-Path $testRoot 'candidate.kbd')+'"'
    $start.WorkingDirectory=$testRoot
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $start.EnvironmentVariables['CLICKS_TEST_INPUT']=$inputPath
    $start.EnvironmentVariables['CLICKS_TEST_OUTPUT']=$outputPath
    $process=[Diagnostics.Process]::Start($start)
    $jobs+=@{Case=$case;Process=$process;Out=$process.StandardOutput.ReadToEndAsync();Err=$process.StandardError.ReadToEndAsync();Result=$outputPath}
}
$failures=0
foreach($job in $jobs){
    $p=$job.Process
    if(-not $p.WaitForExit(12000)){$p.Kill();throw 'Offline keyboard test timed out.'}
    $log=$job.Out.Result+$job.Err.Result
    [IO.File]::WriteAllText((Join-Path $testRoot ($job.Case.Name+'.log.txt')),$log)
    if($p.ExitCode -ne 0 -or -not(Test-Path -LiteralPath $job.Result)){Write-Output ('FAIL '+$job.Case.Name+': '+$log);$failures++;continue}
    $events=@(Get-Content -LiteralPath $job.Result | ForEach-Object {$fields=$_ -split ' ';$fields[2]+':'+$fields[3]})
    if(($events -join ',') -eq ($job.Case.Expect -join ',')){Write-Output ('PASS '+$job.Case.Name)}
    else {Write-Output ('FAIL '+$job.Case.Name+' expected '+($job.Case.Expect -join ',')+' actual '+($events -join ','));$failures++}
}
if($failures){throw "$failures offline keyboard tests failed."}
