#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param([string]$Distribution = 'Ubuntu', [switch]$Watch, [int]$ParentPid = 0, [string]$SessionFile)
$ErrorActionPreference = 'Stop'
if ($Distribution -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'Distribucion no valida.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (!$admin -and !$WhatIfPreference) {
    throw 'Sincronizar hosts necesita PowerShell como administrador. Ejecuta nexum.ps1 Sync desde esa terminal.'
}
function Get-NexumLeafCertificate {
    param($Entry, [string[]]$ActiveNames)
    $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new([Convert]::FromBase64String($Entry.der))
    $constraints = @($cert.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.19' })
    if ($constraints.Count -ne 1) { return }
    $basic = New-Object Security.Cryptography.X509Certificates.X509BasicConstraintsExtension
    $basic.CopyFrom($constraints[0])
    if ($basic.CertificateAuthority -or $cert.Subject -ne $cert.Issuer -or $cert.NotAfter -lt (Get-Date) -or $cert.NotBefore -gt (Get-Date)) { return }
    if (@($Entry.domains).Count -eq 0 -or @($Entry.domains | Where-Object { $_ -notin $ActiveNames }).Count -gt 0) { return }
    return $cert
}
function Update-NexumIntegration {
$raw = & "$env:WINDIR\System32\wsl.exe" -d $Distribution --exec python3 /opt/nexum/windows/integration.py manifest
if ($LASTEXITCODE -ne 0) { throw 'No se pudo leer manifiesto Linux.' }
$manifest = ($raw | Out-String) | ConvertFrom-Json
if ($manifest.schema -ne 1) { throw 'Manifiesto incompatible.' }
$names = @($manifest.hosts.PSObject.Properties | ForEach-Object { $_.Name })
foreach ($name in $names) {
    if ($name -notmatch '^[a-z0-9][a-z0-9.-]{0,251}[a-z0-9]$' -or $manifest.hosts.$name -ne '127.0.0.1') {
        throw 'Manifiesto contiene host no valido.'
    }
}
$hostsPath = Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
$begin = '# BEGIN NEXUM WSL'
$end = '# END NEXUM WSL'
$original = [IO.File]::ReadAllText($hostsPath)
$pattern = '(?ms)^' + [regex]::Escape($begin) + '\r?\n.*?^' + [regex]::Escape($end) + '\r?\n?'
$base = [regex]::Replace($original, $pattern, '')
# Existing manual entries take precedence; refuse conflicting DNS rather than silently override.
foreach ($line in ($base -split '\r?\n')) {
    $parts = (($line -split '#',2)[0].Trim() -split '\s+')
    if ($parts.Length -gt 1) {
        foreach ($name in $parts[1..($parts.Length-1)]) {
            if ($name -in $names -and $parts[0] -notin @('127.0.0.1','::1')) { throw "Host Windows en conflicto: $name" }
        }
    }
}
$lines = @($begin) + @($names | Sort-Object | ForEach-Object { "127.0.0.1`t$_" }) + @($end)
$updated = $base.TrimEnd("`r","`n") + "`r`n" + ($lines -join "`r`n") + "`r`n"
if ($updated -ne $original -and $PSCmdlet.ShouldProcess($hostsPath, 'Actualizar bloque Nexum')) {
    $backup = $hostsPath + '.nexum-' + (Get-Date -Format 'yyyyMMddHHmmssfff') + '.bak'
    Copy-Item -LiteralPath $hostsPath -Destination $backup
    [IO.File]::WriteAllText($hostsPath, $updated, (New-Object Text.UTF8Encoding($false)))
}
$stateDir = Join-Path $env:LOCALAPPDATA 'Nexum'
$statePath = Join-Path $stateDir ('certificates-' + $Distribution + '.json')
$previous = @()
if (Test-Path -LiteralPath $statePath) { $previous = @((Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json)) }
$desired = @()
$owned = @()
$store = New-Object Security.Cryptography.X509Certificates.X509Store('Root','CurrentUser')
$store.Open([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
try {
    foreach ($entry in $manifest.certificates) {
        $cert = Get-NexumLeafCertificate -Entry $entry -ActiveNames $names
        if (!$cert) { continue }
        $desired += $cert.Thumbprint
        $exists = @($store.Certificates | Where-Object Thumbprint -eq $cert.Thumbprint).Count -gt 0
        if (!$exists -and $PSCmdlet.ShouldProcess($cert.Subject, 'Confiar certificado servidor autofirmado, no CA')) {
            $store.Add($cert)
            $owned += $cert.Thumbprint
        } elseif ($cert.Thumbprint -in $previous) { $owned += $cert.Thumbprint }
    }
    foreach ($thumbprint in $previous) {
        if ($thumbprint -notin $desired) {
            foreach ($cert in @($store.Certificates | Where-Object Thumbprint -eq $thumbprint)) {
                if ($PSCmdlet.ShouldProcess($cert.Subject, 'Retirar confianza Nexum')) { $store.Remove($cert) }
            }
        }
    }
} finally { $store.Close() }
if ($PSCmdlet.ShouldProcess($statePath, 'Guardar certificados gestionados')) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    ConvertTo-Json -InputObject @($owned | Sort-Object -Unique) | Set-Content -LiteralPath $statePath -Encoding UTF8
}
if (!$Watch) { Write-Host ("Hosts sincronizados: " + $names.Count + '; certificados gestionados: ' + $owned.Count) }
}
do {
    try { Update-NexumIntegration } catch { if (!$Watch) { throw }; Write-Warning $_ }
    if (!$Watch) { break }
    Start-Sleep -Seconds 3
} while ($ParentPid -gt 0 -and (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) -and $SessionFile -and (Test-Path -LiteralPath $SessionFile))
