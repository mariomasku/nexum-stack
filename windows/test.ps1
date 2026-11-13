#requires -Version 5.1
[CmdletBinding()]
param([switch]$SyntaxOnly)
$ErrorActionPreference = 'Stop'
foreach ($name in 'nexum.ps1','sync.ps1','empaquetar.ps1') {
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $name), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    Write-Host "PASS PowerShell syntax: $name"
}
$tokens = $null
$errors = $null
$syncAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'sync.ps1'), [ref]$tokens, [ref]$errors)
$validator = $syncAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-NexumLeafCertificate'}, $true)
Invoke-Expression $validator.Extent.Text
$rsa = [Security.Cryptography.RSA]::Create(2048)
try {
    foreach ($isCA in @($false,$true)) {
        $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=nexum.test',$rsa,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($isCA,$false,0,$true))
        $fixture = $request.CreateSelfSigned([DateTimeOffset]::Now.AddMinutes(-1),[DateTimeOffset]::Now.AddHours(1))
        $entry = [pscustomobject]@{der=[Convert]::ToBase64String($fixture.RawData);domains=@('nexum.test')}
        $accepted = Get-NexumLeafCertificate -Entry $entry -ActiveNames @('nexum.test')
        if ([bool]$accepted -eq $isCA) { throw 'Certificate CA policy failed.' }
        if (Get-NexumLeafCertificate -Entry $entry -ActiveNames @('other.test')) { throw 'Unmapped certificate accepted.' }
        $fixture.Dispose()
    }
    Write-Host 'PASS Windows certificate leaf/CA/unmapped policy'
} finally { $rsa.Dispose() }
if ($SyntaxOnly) { return }
# Validate exact native argv transport, including spaces, apostrophes and quotes.
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'nexum.ps1'), [ref]$tokens, [ref]$errors)
$function = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Linux'}, $true)
Invoke-Expression $function.Extent.Text
$wsl = Join-Path $env:WINDIR 'System32\wsl.exe'
$Distribution = 'Ubuntu'
$code = 'import sys;assert sys.argv[1]=="space apostrophe' + "'" + ' quote\" backslash\\";print("PASS native argv transport")'
Invoke-Linux -LinuxArgs @('python3','-c',$code,('space apostrophe' + "'" + ' quote" backslash\'))
