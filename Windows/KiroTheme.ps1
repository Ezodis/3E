$ErrorActionPreference = 'Stop'
$settingsPath = Join-Path $env:APPDATA 'Kiro\User\settings.json'
$lightThemes = @('Kiro Light','Light+','Quiet Light','Solarized Light','VS Code Light')
$darkThemes = @('Abyss','Dark+','Kimbie Dark','Kiro Dark','Monokai','Monokai Dimmed','Red','Solarized Dark','Tomorrow Night Blue','VS Code Dark')
$hour = (Get-Date).Hour
$themes = if ($hour -ge 12 -and $hour -lt 20) { $lightThemes } else { $darkThemes }
if (Test-Path -LiteralPath $settingsPath) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
} else {
    $folder = Split-Path -Parent $settingsPath
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $settings = [pscustomobject]@{}
}
$current = if ($settings.PSObject.Properties.Name -contains 'workbench.colorTheme') { $settings.'workbench.colorTheme' } else { $null }
$choices = @($themes | Where-Object { $_ -ne $current })
if (-not $choices) { $choices = $themes }
$selected = Get-Random -InputObject $choices
if ($settings.PSObject.Properties.Name -contains 'workbench.colorTheme') {
    $settings.'workbench.colorTheme' = $selected
} else {
    $settings | Add-Member -NotePropertyName 'workbench.colorTheme' -NotePropertyValue $selected
}
$json = $settings | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))