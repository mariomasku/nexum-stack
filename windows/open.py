#!/usr/bin/python3
"""Open Linux application links in the Windows desktop without shell interpolation."""
import base64
import os
import pathlib
import re
import subprocess
import sys
import urllib.parse


def windows_target(target):
    # A native path may contain literal #, ? or %; only decode actual file URIs.
    if not target.startswith('/'):
        parsed = urllib.parse.urlsplit(target)
        if parsed.scheme in ('http', 'https') and parsed.netloc:
            return target
        if parsed.scheme == 'file' and parsed.netloc in ('', 'localhost'):
            target = urllib.parse.unquote(parsed.path)
        else:
            raise ValueError('Solo enlaces HTTP/HTTPS o archivos locales.')
    path = pathlib.Path(target)
    if not path.is_absolute() or not path.exists():
        raise ValueError('Ruta local inexistente o relativa.')
    return subprocess.check_output(['/usr/bin/wslpath', '-w', str(path.resolve())], text=True).strip()


def main():
    if sys.argv[1:] == ['--terminal']:
        distro = os.environ.get('WSL_DISTRO_NAME', '')
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', distro):
            raise ValueError('Distribucion WSL no valida.')
        command = ("Start-Process -FilePath ($env:WINDIR + '\\System32\\wsl.exe') "
                   "-ArgumentList '-d " + distro + " --exec /opt/nexum/nexum.sh'")
    elif len(sys.argv) == 2 or (len(sys.argv) == 3 and sys.argv[1] == '--text'):
        text_file = sys.argv[1] == '--text'
        target = windows_target(sys.argv[2] if text_file else sys.argv[1])
        if text_file and not target.startswith(('\\\\',)) and not re.match(r'^[A-Za-z]:\\', target):
            raise ValueError('El editor necesita un archivo local.')
        encoded_target = base64.b64encode(target.encode('utf-8')).decode('ascii')
        command = ("$ErrorActionPreference='Stop'; "
                   "$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"
                   + encoded_target + "')); ")
        if text_file:
            command += "Start-Process -FilePath ($env:WINDIR + '\\System32\\notepad.exe') -ArgumentList ('\"' + $target + '\"')"
        else:
            command += "Start-Process -FilePath $target"
    else:
        raise ValueError('Uso: open.py <enlace o archivo>|--text <archivo>|--terminal')
    encoded_command = base64.b64encode(command.encode('utf-16le')).decode('ascii')
    powershell = '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
    # Explicit path: no dependency on WSL's imported Windows PATH.
    return subprocess.call([powershell, '-NoProfile', '-NonInteractive', '-EncodedCommand', encoded_command],
                           cwd='/mnt/c/Windows', stdout=subprocess.DEVNULL)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
