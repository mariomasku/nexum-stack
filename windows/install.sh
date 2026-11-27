#!/bin/bash
# Installs a private LF snapshot, reusing the Linux package and its update policy.
set -euo pipefail
source_dir=$1
[[ $(uname -r) == *[Mm]icrosoft* ]] || { echo 'Se necesita WSL2.' >&2; exit 1; }
[[ -S /mnt/wslg/.X11-unix/X0 ]] || { echo 'WSLg no disponible. Actualiza WSL: wsl --update' >&2; exit 1; }
[[ $(ps -p 1 -o comm=) == systemd ]] || { echo 'Activa systemd en /etc/wsl.conf y reinicia esta distribucion.' >&2; exit 1; }
as_root() {
    /mnt/c/Windows/System32/wsl.exe -d "$WSL_DISTRO_NAME" -u root --exec "$@"
}
as_root apt-get update
as_root apt-get install -y python3 python3-gi python3-gi-cairo gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1 \
    xdg-utils xdg-user-dirs whiptail curl openssl libnss3-tools dpkg-dev libsecret-tools gnome-keyring sudo
# Ubuntu 26 selects sudo-rs, which does not honor the GUI's SUDO_PROMPT marker.
# Use Ubuntu's packaged classic implementation, retaining normal authentication.
if sudo --version 2>/dev/null | head -1 | grep -q '^sudo-rs '; then
    [[ -x /usr/bin/sudo.ws ]] || { echo 'Se necesita sudo clasico (/usr/bin/sudo.ws).' >&2; exit 1; }
    as_root update-alternatives --set sudo /usr/bin/sudo.ws
fi
work=$(mktemp -d "$HOME/.nexum-windows-install.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
python3 - "$source_dir" "$work" <<'PY'
import pathlib, shutil, sys
source, target = map(pathlib.Path, sys.argv[1:])
for name in ('src', 'ayuda', 'windows'):
    shutil.copytree(source / name, target / name, ignore=shutil.ignore_patterns('windows-audit', '__pycache__'))
for name in ('construir.sh', 'empaquetar-deb.sh'):
    shutil.copy2(source / name, target / name)
(target / 'macos').mkdir()
for path in target.rglob('*'):
    if path.is_file() and path.suffix in ('.sh', '.py', '.swift', '.md', '.ps1', '.html', '.css', '.js', '.svg', '.txt'):
        path.write_bytes(path.read_bytes().replace(b'\r\n', b'\n'))
    if path.is_file() and path.suffix == '.sh':
        path.chmod(0o755)
PY
bash "$work/construir.sh"
bash "$work/empaquetar-deb.sh" "$work/packages"
# Install explicitly selects this checkout, even after a newer Linux release
# was installed by Nexum's updater. Keep downgrade permission local to this
# invocation; do not change APT policy or the shared application version.
as_root apt-get install --reinstall --allow-downgrades -y "$work"/packages/nexum_*_all.deb
# Keep domains managed by Nexum when WSL restarts, and recover the standard
# project domain if WSL already regenerated /etc/hosts before this installation.
as_root /usr/bin/python3 "$work/windows/configure-hosts.py"
as_root install -d -m 755 /opt/nexum/windows
as_root install -m 755 "$work/windows/integration.py" /opt/nexum/windows/integration.py
as_root install -m 755 "$work/windows/open.py" /opt/nexum/windows/open.py
as_root install -m 755 "$work/windows/vscode.py" /opt/nexum/windows/vscode.py
as_root install -m 755 "$work/windows/window.py" /opt/nexum/windows/window.py
source_commit=$(git -C "$source_dir" rev-parse HEAD 2> /dev/null || echo unknown)
python3 - "$work" "$source_commit" <<'PY'
import json, pathlib, re, sys
work = pathlib.Path(sys.argv[1])
header = (work / 'src/linux/bash/01-cabecera.sh').read_text()
version = re.search(r'^APP_VERSION="([0-9.]+)"', header, re.M).group(1)
(work / 'build-info.json').write_text(json.dumps(dict(
    platform='Windows WSL preview', engine_version=version, source_commit=sys.argv[2]
), indent=2) + '\n')
PY
as_root install -m 644 "$work/build-info.json" /opt/nexum/windows/build-info.json
mkdir -p "$HOME/.local/share/applications"
vscode_icon_dir="$HOME/.local/share/icons"
if vscode_icon_source=$(/usr/bin/python3 /opt/nexum/windows/vscode.py --icon 2> /dev/null); then
    mkdir -p "$vscode_icon_dir"
    rm -f "$vscode_icon_dir/nexum-windows-vscode.svg" "$vscode_icon_dir/nexum-windows-vscode.png"
    vscode_icon="$vscode_icon_dir/nexum-windows-vscode.${vscode_icon_source##*.}"
    install -m 644 "$vscode_icon_source" "$vscode_icon"
    cat > "$HOME/.local/share/applications/nexum-windows-vscode.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Visual Studio Code (Windows / WSL)
Exec=/usr/bin/python3 /opt/nexum/windows/vscode.py %f
Icon=$vscode_icon
Terminal=false
NoDisplay=true
EOF
else
    rm -f "$HOME/.local/share/applications/nexum-windows-vscode.desktop"
    rm -f "$vscode_icon_dir/nexum-windows-vscode.svg" "$vscode_icon_dir/nexum-windows-vscode.png"
    echo 'VS Code Windows no encontrado. Instala VS Code y su extension WSL; vuelve a ejecutar Install.'
fi
cat > "$HOME/.local/share/applications/nexum-windows-open.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Windows browser and Explorer
Exec=/opt/nexum/windows/open.py %u
Terminal=false
MimeType=x-scheme-handler/http;x-scheme-handler/https;inode/directory;
NoDisplay=true
EOF
for mime in x-scheme-handler/http x-scheme-handler/https inode/directory; do
    xdg-mime default nexum-windows-open.desktop "$mime"
done
if [[ -n ${2:-} ]]; then
    # Configure this user's pickers/exports using Windows Known Folders, not C:\\Users guesses.
    python3 - "$2" <<'PY'
import base64, json, pathlib, re, subprocess, sys
folders = json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))
config = pathlib.Path.home() / '.config' / 'user-dirs.dirs'
config.parent.mkdir(parents=True, exist_ok=True)
text = config.read_text(encoding='utf-8') if config.exists() else ''
for name in ('DOWNLOAD', 'DOCUMENTS', 'DESKTOP'):
    value = folders.get(name)
    if not value:
        continue
    path = subprocess.check_output(['/usr/bin/wslpath', '-a', '-u', value], text=True).strip()
    if not pathlib.Path(path).is_dir():
        continue
    escaped = path.replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$').replace('`', '\\`')
    key = 'XDG_' + name + '_DIR'
    text = re.sub(r'^' + key + r'=.*\n?', '', text, flags=re.M)
    text = text.rstrip('\n') + '\n' + key + '="' + escaped + '"\n'
config.write_text(text, encoding='utf-8')
PY
fi
echo 'Motor Linux instalado. Datos y proyectos: /opt/htdocs, dentro de WSL.'
echo 'Docker: usa el motor rootless de Nexum o habilita integracion WSL en Docker Desktop.'
