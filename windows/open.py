#!/usr/bin/python3
"""Open Linux application links in the Windows desktop without shell interpolation."""
import base64
import os
import pathlib
import subprocess
import sys
import urllib.parse


def windows_target(target):
    parsed = urllib.parse.urlsplit(target)
    if parsed.scheme in ('http', 'https') and parsed.netloc:
        return target
    if parsed.scheme == 'file' and parsed.netloc in ('', 'localhost'):
        target = urllib.parse.unquote(parsed.path)
    elif parsed.scheme:
        raise ValueError('Solo enlaces HTTP/HTTPS o archivos locales.')
    path = pathlib.Path(target)
    if not path.is_absolute() or not path.exists():
        raise ValueError('Ruta local inexistente o relativa.')
    return subprocess.check_output(['/usr/bin/wslpath', '-w', str(path)], text=True).strip()


def main():
    target = windows_target(sys.argv[1])
    encoded_target = base64.b64encode(target.encode('utf-8')).decode('ascii')
    command = ("$target=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"
               + encoded_target + "')); Start-Process -FilePath $target")
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
