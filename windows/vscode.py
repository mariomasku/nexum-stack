#!/usr/bin/python3
"""Launch Windows VS Code against this distribution through Remote WSL."""
import base64
import json
import os
import pathlib
import subprocess
import sys
import urllib.parse


def main():
    distro = os.environ.get('WSL_DISTRO_NAME')
    if not distro:
        raise ValueError('Se necesita una distribucion WSL.')
    checking = sys.argv[1:] == ['--check']
    if not checking and len(sys.argv) != 2:
        raise ValueError('Uso: vscode.py <carpeta>|--check')
    folder = pathlib.Path(sys.argv[1]).resolve() if not checking else pathlib.Path('/')
    if not folder.is_dir():
        raise ValueError('No existe la carpeta del proyecto.')
    remote = 'wsl+' + distro
    uri = 'vscode-remote://' + urllib.parse.quote(remote, safe='+') + urllib.parse.quote(str(folder), safe='/')
    payload = base64.b64encode(json.dumps(dict(remote=remote, uri=uri, check=checking)).encode()).decode('ascii')
    command = r'''
$ErrorActionPreference = 'Stop'
$data = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('PAYLOAD')) | ConvertFrom-Json
$candidates = @()
foreach ($key in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\Code.exe',
                 'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\Code.exe') {
    $entry = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    if ($entry) { $candidates += $entry.'(default)' }
}
foreach ($base in $env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)}) {
    if ($base) {
        $candidates += Join-Path $base 'Microsoft VS Code\Code.exe'
        $candidates += Join-Path $base 'Programs\Microsoft VS Code\Code.exe'
    }
}
$code = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (!$code) { throw 'Instala Visual Studio Code en Windows y su extension WSL; despues reinstala la integracion Nexum.' }
if (!$data.check) { & $code --remote $data.remote --folder-uri $data.uri; exit $LASTEXITCODE }
'''.replace('PAYLOAD', payload)
    encoded = base64.b64encode(command.encode('utf-16le')).decode('ascii')
    return subprocess.call([
        '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe',
        '-NoProfile', '-NonInteractive', '-EncodedCommand', encoded,
    ], cwd='/mnt/c/Windows')


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
