<#
.SYNOPSIS
Sets up TypeFix, the offline AI correction for the Clicks keyboard (double-tap the red key).
.DESCRIPTION
Downloads, into %LOCALAPPDATA%\3EWindows\AI (per user, no admin):
  - llama.cpp's Vulkan server (runs on Intel, AMD and NVIDIA graphics),
  - Google's Gemma 4 26B-A4B instruct model, Q4 (about 16 GB),
  - English, Spanish and French word-frequency lists (MIT, hermitdave/FrequencyWords) for keyboard hints,
then writes typefix.json, which the Clicks helper (ClicksAccents.exe) reads. Files already present are
kept. Text never leaves the PC: the server listens on 127.0.0.1 only.
#>
[CmdletBinding()]
param(
    [string]$LlamaBuild = 'b12521',
    [string]$ModelUrl = 'https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/resolve/main/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf',
    [int]$Port = 8089
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Join-Path $env:LOCALAPPDATA '3EWindows\AI'
$llama = Join-Path $root 'llama'
$models = Join-Path $root 'models'
$words = Join-Path $root 'words'
New-Item -ItemType Directory -Force -Path $llama, $models, $words | Out-Null

function Get-File([string]$Url, [string]$Path) {
    if (Test-Path -LiteralPath $Path) { return }
    Write-Host "Downloading $(Split-Path -Leaf $Path)..."
    & curl.exe -fsSL --retry 3 -o "$Path.part" $Url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
    Move-Item -LiteralPath "$Path.part" -Destination $Path -Force
}

$server = Join-Path $llama 'llama-server.exe'
if (-not (Test-Path -LiteralPath $server)) {
    $zip = Join-Path $root "llama-$LlamaBuild-vulkan.zip"
    Get-File "https://github.com/ggml-org/llama.cpp/releases/download/$LlamaBuild/llama-$LlamaBuild-bin-win-vulkan-x64.zip" $zip
    Expand-Archive -LiteralPath $zip -DestinationPath $llama -Force
    Remove-Item -LiteralPath $zip
}
$model = Join-Path $models (Split-Path -Leaf ([Uri]$ModelUrl).AbsolutePath)
Get-File $ModelUrl $model
foreach ($lang in 'en', 'es', 'fr') {
    Get-File "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/$lang/${lang}_50k.txt" (Join-Path $words "$lang.txt")
}

# Use every graphics device. With a small dedicated NVIDIA card next to integrated graphics, give the
# NVIDIA card a third of the model (what fits in 8 GB) and integrated graphics the rest.
$devices = @(& $server --list-devices 2>&1 | Select-String '^\s+(Vulkan\d+): (.+)$' | ForEach-Object { [pscustomobject]@{Id = $_.Matches[0].Groups[1].Value; Name = $_.Matches[0].Groups[2].Value} })
$gpu = ''
$nvidia = @($devices | Where-Object Name -match 'NVIDIA')
$others = @($devices | Where-Object Name -notmatch 'NVIDIA')
if ($nvidia.Count -eq 1 -and $others.Count -ge 1) { $gpu = "--device $($nvidia[0].Id),$($others[0].Id) -ngl 99 --tensor-split 1,2" }
elseif ($devices.Count -ge 1) { $gpu = '-ngl 99' }
$arguments = "-m `"$model`" -c 4096 --host 127.0.0.1 --port $Port $gpu"

$config = [ordered]@{ url = "http://127.0.0.1:$Port"; server = $server; arguments = $arguments }
$config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'typefix.json') -Encoding UTF8
Write-Host "TypeFix is set up ($($devices.Count) graphics device(s): $(($devices.Name) -join ', '))."
Write-Host 'Restart the Clicks keyboard from the 3£ tray (or sign out and in) to start it. The first correction loads the model (about 30 s).'
