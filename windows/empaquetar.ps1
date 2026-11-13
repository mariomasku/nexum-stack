#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (!$OutputDirectory) { $OutputDirectory = Join-Path $root 'dist' }
$versionLine = Get-Content -LiteralPath (Join-Path $root 'src\linux\bash\01-cabecera.sh') | Where-Object { $_ -match '^APP_VERSION=' } | Select-Object -First 1
if ($versionLine -notmatch '^APP_VERSION="([0-9.]+)"') { throw 'No se encuentra APP_VERSION.' }
$version = $Matches[1]
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$destination = Join-Path (Resolve-Path -LiteralPath $OutputDirectory) "nexum-windows-$version.zip"
$stage = Join-Path ([IO.Path]::GetTempPath()) ('nexum-windows-package-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    foreach ($folder in 'src','ayuda','windows') {
        Copy-Item -LiteralPath (Join-Path $root $folder) -Destination $stage -Recurse
    }
    foreach ($report in 'installation.json','verification.json') {
        $reportPath = [IO.Path]::GetFullPath((Join-Path $stage ('windows\' + $report)))
        if (!$reportPath.StartsWith([IO.Path]::GetFullPath($stage) + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Ruta informe inesperada.' }
        if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath -Force }
    }
    # Audit artifacts are local measurements, not product resources.
    $audit = Join-Path $stage 'ayuda\windows-audit'
    if (![IO.Path]::GetFullPath($audit).StartsWith([IO.Path]::GetFullPath($stage) + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Ruta audit inesperada.' }
    if (Test-Path -LiteralPath $audit) { Remove-Item -LiteralPath $audit -Recurse -Force }
    Get-ChildItem -LiteralPath $stage -Filter __pycache__ -Recurse -Directory | ForEach-Object {
        if (!$_.FullName.StartsWith([IO.Path]::GetFullPath($stage) + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Ruta cache inesperada.' }
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
    foreach ($file in 'construir.sh','empaquetar-deb.sh','.gitattributes') {
        Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage
    }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $destination -Force
    Get-FileHash -LiteralPath $destination -Algorithm SHA256
} finally {
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (!$resolvedStage.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or !(Split-Path $resolvedStage -Leaf).StartsWith('nexum-windows-package-')) { throw 'Ruta temporal inesperada.' }
    if (Test-Path -LiteralPath $resolvedStage) { Remove-Item -LiteralPath $resolvedStage -Recurse -Force }
}
