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
    xdg-utils whiptail curl openssl libnss3-tools dpkg-dev libsecret-tools gnome-keyring sudo
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
as_root apt-get install --reinstall -y "$work"/packages/nexum_*_all.deb
as_root install -d -m 755 /opt/nexum/windows
as_root install -m 755 "$work/windows/integration.py" /opt/nexum/windows/integration.py
as_root install -m 755 "$work/windows/open.py" /opt/nexum/windows/open.py
mkdir -p "$HOME/.local/share/applications"
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
echo 'Motor Linux instalado. Datos y proyectos: /opt/htdocs, dentro de WSL.'
echo 'Docker: usa el motor rootless de Nexum o habilita integracion WSL en Docker Desktop.'
