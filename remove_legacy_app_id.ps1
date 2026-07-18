$ErrorActionPreference = 'Stop'

$legacyPackagePath = Join-Path $PSScriptRoot 'android\app\src\main\kotlin\com\example\eway_link'

if (Test-Path $legacyPackagePath) {
    Remove-Item -Path $legacyPackagePath -Recurse -Force
}

Write-Host 'EWAY LINK permanent application ID migration completed.' -ForegroundColor Green
