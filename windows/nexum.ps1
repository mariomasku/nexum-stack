#requires -Version 5.1
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Install','Open','Run','Doctor','Sync')]
    [string]$Action = 'Open',
    [string]$Distribution = 'Ubuntu',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)
$ErrorActionPreference = 'Stop'
$wsl = Join-Path $env:WINDIR 'System32\wsl.exe'
if (!(Test-Path -LiteralPath $wsl)) { throw 'Instala WSL2: wsl --install -d Ubuntu' }
if ($Distribution -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'Nombre de distribucion no valido.' }

function Invoke-Linux {
    param([string[]]$LinuxArgs)
    # Use CRT quoting explicitly: Windows PowerShell 5.1 otherwise strips quotes
    # embedded in Python -c arguments and corrupts paths containing spaces.
    $all = @('-d', $Distribution, '--exec') + $LinuxArgs
    $quoted = foreach ($argument in $all) {
        if ($argument -and $argument -notmatch '[\s"]') { $argument }
        else { '"' + [regex]::Replace([regex]::Replace($argument, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"' }
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $wsl
    $start.Arguments = $quoted -join ' '
    Write-Verbose ($start.FileName + ' ' + $start.Arguments)
    $start.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($start)
    try {
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "Comando Linux termino con codigo $($process.ExitCode)." }
    } finally { $process.Dispose() }
}

switch ($Action) {
    'Install' {
        $source = Split-Path $PSScriptRoot -Parent
        $linuxSource = (& $wsl -d $Distribution --exec wslpath -a -u $source)
        if ($LASTEXITCODE -ne 0) { throw 'Ubuntu no disponible. Ejecuta wsl --install -d Ubuntu y completa su primer arranque.' }
        $linuxSource = ($linuxSource | Out-String).Trim()
        # bash reads the checkout script without requiring executable bits on NTFS.
        # Strip CR only on this stream; bootstrap normalizes its private snapshot.
        $bootstrap = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'install.sh')).Replace("`r`n", "`n")
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bootstrap))
        $loader = 'import base64,os,sys;os.execv("/bin/bash",["bash","-c",base64.b64decode(sys.argv[1]).decode(),"nexum-install",sys.argv[2]])'
        Invoke-Linux -LinuxArgs @('python3','-c',$loader,$encoded,$linuxSource)
        $destination = Join-Path $env:LOCALAPPDATA 'Nexum'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'nexum.ps1') -Destination $destination -Force
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'sync.ps1') -Destination $destination -Force
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Nexum Dev Stack.lnk'))
        $shortcut.TargetPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $destination 'nexum.ps1') + '" -Action Open -Distribution ' + $Distribution
        $shortcut.WorkingDirectory = $destination
        $shortcut.Save()
        Write-Host 'Nexum instalado. Abre Nexum Dev Stack desde Inicio.'
    }
    'Open' {
        $sync = Join-Path $PSScriptRoot 'sync.ps1'
        $sessions = Join-Path $env:LOCALAPPDATA 'Nexum\sessions'
        New-Item -ItemType Directory -Path $sessions -Force | Out-Null
        $session = Join-Path $sessions ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType File -Path $session | Out-Null
        $syncArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + $sync + '" -Distribution ' + $Distribution + ' -Watch -ParentPid ' + $PID + ' -SessionFile "' + $session + '"'
        try {
            $companion = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $syncArgs -Verb RunAs -WindowStyle Hidden -PassThru
            Invoke-Linux -LinuxArgs @('/opt/nexum/nexum.sh','ventana')
        }
        finally {
            Remove-Item -LiteralPath $session -Force -ErrorAction SilentlyContinue
            if ($companion) {
                $null = $companion.WaitForExit(15000)
                $companion.Dispose()
            }
            Write-Host 'Ventana cerrada. Servicios se pueden parar con nexum.ps1 Run parar.'
        }
    }
    'Run' {
        if (!$CommandArgs) { throw 'Indica comando Linux. Ejemplo: .\nexum.ps1 Run version' }
        Invoke-Linux -LinuxArgs (@('/opt/nexum/nexum.sh') + $CommandArgs)
    }
    'Doctor' { Invoke-Linux -LinuxArgs @('python3','/opt/nexum/windows/integration.py','doctor') }
    'Sync' { & (Join-Path $PSScriptRoot 'sync.ps1') -Distribution $Distribution }
}
