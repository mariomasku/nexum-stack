#!/bin/bash
# Crea el paquete .deb de Nexum Dev Stack (nexum_<version>_all.deb) a partir de lvm-instalador.sh (la
# version sale de su APP_VERSION, el icono de su ICON_PNG_B64 y la clave de las firmas de su
# UPDATE_KEY_B64). Doble clic sobre el .deb = instalar o actualizar.
#
# Uso: ./empaquetar-deb.sh [carpeta de salida]     (por defecto ~/Descargas)
#
# El paquete instala:
#   /opt/nexum/nexum.sh                                      el script
#   /usr/share/applications/nexum.desktop                    icono del menu para todos los usuarios
#   /usr/share/icons/hicolor/256x256/apps/nexum.png
#   /opt/nexum/nexum-actualizar                              instala un nexum_*.deb nuevo
#   /opt/nexum/nexum-stack-firma.gpg                         clave publica de las firmas (.sig)
#   /usr/share/polkit-1/actions/io.github.mariomasku.nexum.policy
#                                    mensaje en español de la contraseña al actualizar (pkexec)
# Lleva Conflicts y Replaces del paquete de antes (lvm-instalador, hasta la 1.57.10): al instalarlo, se
# quita el viejo solo. Al instalarse (postinst):
#   - /usr/local/bin/nexum apunta al script (si ya hay otro nexum que no es de este programa, no se toca)
#   - se quitan /usr/local/bin/lvm-instalador y pvm-instalador, si son enlaces a un *-instalador.sh, y
#     /usr/local/bin/lvm solo si es un enlace a un lvm-instalador.sh (cualquier otro lvm no se toca)
#   - los iconos del menu de cada usuario (~/.local/share/applications/lampp-version-manager.desktop)
#     que abren un [lp]vm-instalador.sh se quitan (esta el del paquete) o pasan a nexum.desktop
#   - el temporizador de Docker sin visitas de cada usuario (nexum-reposo.service) pasa a la orden nexum

set -e -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/lvm-instalador.sh
OUT=${1:-$HOME/Descargas}
PKG=nexum
DEST=/opt/nexum
# El paquete de antes (hasta la 1.57.10): se quita solo al instalar este
OLD_PKG=lvm-instalador
POLICY=io.github.mariomasku.nexum

VERSION=$(grep -m1 '^APP_VERSION=' "$SRC" | cut -d'"' -f2)
[ -n "$VERSION" ] || { echo "No se encuentra APP_VERSION en $SRC"; exit 1; }
bash -n "$SRC"
# Al cargarse no debe escribir nada en stderr (p. ej. comillas sin escapar en ABOUT_TEXT, que
# ejecutarian parte del texto) y la lista de cambios no puede salir vacia
ERRORS=$(bash "$SRC" version 2>&1 > /dev/null)
[ -z "$ERRORS" ] || { echo "El script da errores al cargarse:"; echo "$ERRORS"; exit 1; }
# (la salida entera antes de mirarla: con «| grep -q» la lista se corta a medias en cuanto aparece la
# linea, y con pipefail eso falla a veces, segun lo cargado que este el equipo)
NOVEDADES=$(bash "$SRC" novedades)
grep -q "^## $VERSION " <<< "$NOVEDADES" || { echo "Novedades no empieza por la $VERSION"; exit 1; }

BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
ROOT=$BUILD/$PKG

mkdir -p "$ROOT/DEBIAN" "$ROOT$DEST" "$ROOT/usr/share/applications" \
    "$ROOT/usr/share/icons/hicolor/256x256/apps" "$ROOT/usr/share/polkit-1/actions"
install -m 755 "$SRC" "$ROOT$DEST/nexum.sh"

# Actualizar desde la ventana: pkexec ejecuta este programa (no «env apt-get», que sacaba el
# mensaje generico de polkit en ingles) y la accion de polkit pone el texto en español
cat > "$ROOT$DEST/nexum-actualizar" <<'EOF'
#!/bin/sh
# Instala una version nueva de Nexum Stack. Lo ejecuta la ventana con pkexec.
# Uso: nexum-actualizar /ruta/nexum_X.Y.Z_all.deb <sha256 que se ha mostrado>
# (con su firma al lado: /ruta/nexum_X.Y.Z_all.deb.sig)
#
# El paquete esta en una carpeta tuya (Descargas o la de las descargas de GitHub): se copia con su
# firma (sin seguir enlaces y solo si son ficheros normales) a una carpeta de root y todo se
# comprueba e instala desde esa copia:
#   - la huella SHA-256 que se te ha mostrado (obligatoria)
#   - la firma, hecha con la clave de quien publica el programa (la de nexum-stack-firma.gpg)
#   - que es una version mas nueva que la instalada (una vieja, aunque este firmada, podria traer
#     fallos ya corregidos)
#   - su contenido, leido con tarfile: solo ficheros y carpetas normales (sin enlaces ni
#     dispositivos), solo los de nexum, de root y con sus permisos (755 o 644, sin setuid
#     ni escritura para otros), y este ayudante, la clave de las firmas y la accion de polkit
#     iguales a los instalados (si no, cualquier paquete podria darse permisos de root)
#   - sus scripts de instalacion (que se ejecutan como root): ficheros normales (no enlaces), de
#     root, 755 e iguales a los del paquete instalado
#   - sus dependencias (Depends, Recommends, Suggests y Enhances) y sus Conflicts y Replaces (los del
#     paquete de antes, lvm-instalador), iguales a los del paquete instalado, y sin Pre-Depends,
#     Breaks ni Provides (apt podria instalar o quitar otros paquetes); y apt sin instalar los
#     recomendados (--no-install-recommends)
# Si algo de esto cambia en una version, se instala a mano en la terminal: sudo apt install <deb>
set -e
deb=$1 want=$2
case "$deb" in
    /*/nexum_*_all.deb) ;;
    *) echo "No es un paquete de Nexum Stack: $deb" >&2; exit 2 ;;
esac
if ! printf '%s' "$want" | grep -qE '^[0-9a-f]{64}$'; then
    echo "Falta la huella SHA-256 del paquete (o no es valida)" >&2; exit 2
fi
tmp=$(mktemp -d /tmp/nexum-actualizar.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
chmod 700 "$tmp"
pkg=$tmp/paquete.deb
python3 -I - "$deb" "$pkg" "$want" "$deb.sig" "$tmp/paquete.sig" <<'PY'
import hashlib, os, stat, sys
src, dst, want, sig_src, sig_dst = sys.argv[1:6]
def copy(src, dst, limit, what):
    try:
        fd = os.open(src, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        sys.exit("%s no es un fichero normal (es un enlace, no esta o no se puede abrir)" % what)
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode) or st.st_size > limit:
        sys.exit("%s no es un fichero normal (o es demasiado grande)" % what)
    h = hashlib.sha256()
    with os.fdopen(fd, "rb") as f, open(dst, "wb") as out:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
            out.write(chunk)
    return h.hexdigest()
if copy(src, dst, 50 * 1024 * 1024, "El paquete") != want:
    sys.exit("El paquete ha cambiado desde que se te mostro: su huella SHA-256 ya no es la misma.")
copy(sig_src, sig_dst, 64 * 1024, "Su firma (" + sig_src + ")")
PY
# Firmado por quien publica el programa: gpgv solo mira la clave instalada y ademas se exige su
# huella en el resultado (por si el fichero de la clave llevara otra)
if ! GNUPGHOME=$tmp gpgv --status-fd 1 --keyring /opt/nexum/nexum-stack-firma.gpg \
        "$tmp/paquete.sig" "$pkg" 2> /dev/null | grep -q '^\[GNUPG:\] VALIDSIG @UPDATE_KEY_FPR@ '; then
    echo "La firma del paquete no es valida: no lo ha publicado quien hace el programa. No se instala." >&2; exit 2
fi
if [ "$(dpkg-deb -f "$pkg" Package 2>/dev/null)" != nexum ]; then
    echo "El fichero no es un paquete de Nexum Stack: $deb" >&2; exit 2
fi
new=$(dpkg-deb -f "$pkg" Version 2>/dev/null)
installed=$(dpkg-query -W -f='${Version}' nexum 2>/dev/null)
if [ -z "$new" ] || ! dpkg --compare-versions "$new" gt "${installed:-0}"; then
    echo "El paquete es la ${new:-?} y tienes la ${installed:-?}: solo se instalan versiones mas nuevas." >&2; exit 2
fi
for field in Pre-Depends Breaks Provides Essential; do
    value=$(dpkg-deb -f "$pkg" "$field" 2>/dev/null)
    # (dpkg-deb da «no» en Essential aunque no lo lleve)
    if [ -n "$value" ] && [ "$value" != no ]; then
        echo "El paquete trae $field: no se instala desde la ventana." >&2; exit 2
    fi
done
# (Conflicts y Replaces: los del paquete de antes, lvm-instalador, y nada mas que lo instalado)
for field in Depends Recommends Suggests Enhances Conflicts Replaces; do
    if [ "$(dpkg-deb -f "$pkg" "$field" 2>/dev/null)" != "$(dpkg-query -W -f="\${$field}" nexum 2>/dev/null)" ]; then
        echo "El paquete trae otras dependencias ($field): instalalo en la terminal con: sudo apt install $deb" >&2; exit 2
    fi
done
# (el codigo va en -c: la entrada es el tar del paquete)
check=$(cat <<'PY'
import posixpath, sys, tarfile
files = {"opt/nexum/nexum.sh", "opt/nexum/nexum-actualizar",
         "opt/nexum/nexum-stack-firma.gpg",
         "usr/share/applications/nexum.desktop",
         "usr/share/icons/hicolor/256x256/apps/nexum.png",
         "usr/share/polkit-1/actions/io.github.mariomasku.nexum.policy"}
same = {"opt/nexum/nexum-actualizar": "/opt/nexum/nexum-actualizar",
        "opt/nexum/nexum-stack-firma.gpg": "/opt/nexum/nexum-stack-firma.gpg",
        "usr/share/polkit-1/actions/io.github.mariomasku.nexum.policy":
            "/usr/share/polkit-1/actions/io.github.mariomasku.nexum.policy"}
dirs = {""}
for f in files:
    parts = f.split("/")
    for i in range(1, len(parts)):
        dirs.add("/".join(parts[:i]))
seen = set()
with tarfile.open(fileobj=sys.stdin.buffer, mode="r|") as tar:
    for m in tar:
        name = m.name[2:] if m.name.startswith("./") else m.name
        name = name.rstrip("/")
        if name.startswith("/") or ".." in name.split("/") or name != posixpath.normpath(name or "."):
            if name not in ("", "."):
                sys.exit("Ruta no valida en el paquete: %r" % m.name)
        name = "" if name == "." else name
        # De root y con los permisos de siempre: dpkg los respeta (un setuid seria root permanente)
        exe = name in ("opt/nexum/nexum.sh", "opt/nexum/nexum-actualizar")
        if m.uid != 0 or m.gid != 0 or m.uname not in ("root", "") or m.gname not in ("root", "") or (m.mode & 0o7777) != (0o755 if m.isdir() or exe else 0o644):
            sys.exit("Permisos o dueño no validos en el paquete: %s" % m.name)
        if m.isdir():
            if name not in dirs:
                sys.exit("Carpeta no esperada en el paquete: %s" % m.name)
        elif m.isreg():
            if name not in files:
                sys.exit("Fichero no esperado en el paquete: %s" % m.name)
            if name in same:
                data = tar.extractfile(m).read()
                if data != open(same[name], "rb").read():
                    sys.exit("El paquete trae otro %s: instalalo en la terminal (sudo apt install)" % same[name])
            seen.add(name)
        else:
            sys.exit("El paquete lleva enlaces o ficheros especiales (%s): no se instala." % m.name)
if seen != files:
    sys.exit("Al paquete le faltan ficheros de Nexum Stack")
PY
)
dpkg-deb --fsys-tarfile "$pkg" | python3 -I -c "$check"
# Scripts de instalacion, leidos tambien con tarfile: un postinst que fuera un enlace a un fichero
# tuyo se compararia con lo que hubiera en ese momento y despues dpkg ejecutaria lo que pusieras
control=$(cat <<'PY'
import os, stat, sys, tarfile
deb = sys.argv[1]
seen = set()
with tarfile.open(fileobj=sys.stdin.buffer, mode="r|") as tar:
    for m in tar:
        name = (m.name[2:] if m.name.startswith("./") else m.name).rstrip("/")
        if name in ("", "."):
            continue
        if not m.isreg() or "/" in name or name in seen or m.uid != 0 or m.gid != 0 or m.uname not in ("root", "") or m.gname not in ("root", ""):
            sys.exit("El paquete trae un script de instalacion no valido (%s): no se instala." % m.name)
        seen.add(name)
        if name in ("control", "md5sums"):
            if m.mode & 0o7777 != 0o644:
                sys.exit("Permisos no validos en %s del paquete" % name)
        elif name in ("postinst", "postrm"):
            data = tar.extractfile(m).read()
            installed = "/var/lib/dpkg/info/nexum." + name
            try:
                fd = os.open(installed, os.O_RDONLY | os.O_NOFOLLOW)
                with os.fdopen(fd, "rb") as f:
                    ok = stat.S_ISREG(os.fstat(f.fileno()).st_mode) and f.read() == data
            except OSError:
                ok = False
            if m.mode & 0o7777 != 0o755 or not ok:
                print("El paquete trae un %s distinto del instalado: no se instala desde la ventana." % name, file=sys.stderr)
                sys.exit("Si es una version tuya, instalala en la terminal con: sudo apt install " + deb)
        else:
            sys.exit("El paquete trae un script de instalacion inesperado (%s): no se instala." % name)
if "control" not in seen:
    sys.exit("Al paquete le falta su control")
PY
)
dpkg-deb --ctrl-tarfile "$pkg" | python3 -I -c "$control" "$deb"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$pkg"
EOF

cat > "$ROOT/usr/share/polkit-1/actions/$POLICY.policy" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <vendor>Nexum Dev Stack</vendor>
  <icon_name>nexum</icon_name>
  <action id="$POLICY.actualizar">
    <description>Actualizar Nexum Stack</description>
    <message>Para instalar la versión nueva de Nexum Stack hace falta tu contraseña.</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">$DEST/nexum-actualizar</annotate>
  </action>
</policyconfig>
EOF

# Icono: el mismo PNG que lleva el script dentro
sed -n "/^ICON_PNG_B64='/,/^'$/p" "$SRC" | sed '1s/^ICON_PNG_B64=.//; $d' | base64 -d \
    > "$ROOT/usr/share/icons/hicolor/256x256/apps/nexum.png"
file "$ROOT/usr/share/icons/hicolor/256x256/apps/nexum.png" | grep -q 'PNG image' \
    || { echo "No se ha podido sacar el icono del script"; exit 1; }

# Clave publica de las firmas: la que lleva el script, y en el ayudante su huella
KEY_FPR=$(grep -m1 '^UPDATE_KEY_FPR=' "$SRC" | cut -d'"' -f2)
[[ $KEY_FPR =~ ^[0-9A-F]{40}$ ]] || { echo "No se encuentra UPDATE_KEY_FPR en $SRC"; exit 1; }
sed -n "/^UPDATE_KEY_B64='/,/^'$/p" "$SRC" | sed '1s/^UPDATE_KEY_B64=.//; $d' | base64 -d \
    > "$ROOT$DEST/nexum-stack-firma.gpg"
mkdir -m 700 "$BUILD/gnupg"
KEYS=$(gpg --homedir "$BUILD/gnupg" --show-keys --with-colons "$ROOT$DEST/nexum-stack-firma.gpg" 2> /dev/null)
grep -qx "fpr:::::::::$KEY_FPR:" <<< "$KEYS" || { echo "La clave de UPDATE_KEY_B64 no es la de $KEY_FPR"; exit 1; }
sed -i "s/@UPDATE_KEY_FPR@/$KEY_FPR/" "$ROOT$DEST/nexum-actualizar"

cat > "$ROOT/usr/share/applications/nexum.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Nexum Dev Stack
Comment=Instalar, cambiar y desinstalar versiones de XAMPP y PHP
Exec=$DEST/nexum.sh ventana
Terminal=false
StartupWMClass=dev.hexer.LamppVersionManager
Icon=nexum
Categories=Development;
EOF

cat > "$ROOT/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Section: devel
Priority: optional
Architecture: all
Depends: bash, curl, python3, sudo, openssl, binutils, gpgv
Conflicts: $OLD_PKG
Replaces: $OLD_PKG
Recommends: python3-gi, gir1.2-gtk-3.0, whiptail, gir1.2-ayatanaappindicator3-0.1, gir1.2-webkit2-4.1
Installed-Size: $(du -ks "$ROOT" | cut -f1)
Maintainer: Nexum Dev Stack <https://github.com/mariomasku/nexum-stack>
Description: Nexum Dev Stack: varias versiones de PHP con su LAMPP
 Gestor e instalador de versiones LAMPP y PHP para Linux. Monta un LAMPP
 (Apache, PHP-FPM, MariaDB, ProFTPD, Perl y phpMyAdmin) por cada version de
 PHP en /opt/lampp-X.Y, cambia la version activa, carga y descarga bases de
 datos y carga proyectos de /opt/htdocs. Ventana grafica (GTK 3) y panel de
 terminal. No instala PHP ni MariaDB en el sistema.
EOF

# postinst y postrm, como root. Las rutas van al principio, una por linea (las pruebas las cambian por
# las de una carpeta falsa). En las carpetas de cada usuario, todo con el usuario dueño del fichero (no
# como root) y sin seguir enlaces: un enlace en la carpeta de un usuario no puede hacer que root
# escriba en otro sitio
cat > "$ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
SCRIPT=/opt/nexum/nexum.sh
NEXUM_CMD=/usr/local/bin/nexum
OPT=/opt
BIN=/usr/local/bin
APPS=/usr/share/applications
ICONS=/usr/share/icons/hicolor
HOMES="/home/* /root"
RUNDIR=/run/user

# Deja en run_as lo que hay que poner delante de una orden para hacerla como el dueño de <fichero>
# (nada si ya lo es). Sin runuser no se toca nada suyo
as_owner() {
    owner=$(stat -c %U "$1") || return 1
    run_as=""
    [ "$owner" = "$(id -un)" ] && return 0
    command -v runuser > /dev/null || return 1
    run_as="runuser -u $owner --"
}

if [ "$1" = "configure" ]; then
    # /opt del administrador: si es de un usuario, cualquier programa suyo (el PHP de una web)
    # podria cambiar /opt/lampp o /opt/nexum. Solo /opt; sus carpetas no cambian
    if [ "$(id -u)" = 0 ] && [ -d "$OPT" ] && [ ! -L "$OPT" ] && [ "$(stat -c %u "$OPT")" != 0 ]; then
        chown root:root "$OPT"
        chmod 755 "$OPT"
    fi

    # La orden de la terminal: nexum. Si ya hay un nexum que no es un enlace a un nexum.sh (o al
    # lvm-instalador.sh de una copia de este programa), es de otro programa: no se toca y se avisa
    mkdir -p "$BIN"
    if [ -L "$BIN/nexum" ]; then
        case "$(readlink "$BIN/nexum")" in
            */nexum.sh|*/lvm-instalador.sh) ln -sfn "$SCRIPT" "$BIN/nexum" ;;
            *) echo "Aviso: $BIN/nexum ya existe y no es de Nexum Dev Stack: no se cambia. El programa esta en $SCRIPT" >&2 ;;
        esac
    elif [ -e "$BIN/nexum" ]; then
        echo "Aviso: $BIN/nexum ya existe y no es de Nexum Dev Stack: no se cambia. El programa esta en $SCRIPT" >&2
    else
        ln -s "$SCRIPT" "$BIN/nexum"
    fi
    # Las ordenes de antes (lvm-instalador hasta la 1.57.10, pvm-instalador hasta la 1.7), si son
    # enlaces a un *-instalador.sh
    for link in "$BIN/lvm-instalador" "$BIN/pvm-instalador"; do
        if [ -L "$link" ]; then
            case "$(readlink "$link")" in
                *-instalador.sh) rm -f "$link" ;;
            esac
        fi
    done
    # lvm, solo si es un enlace a un lvm-instalador.sh (el de este programa, que ya no existe). Cualquier
    # otro lvm (de otro programa) no se toca nunca
    if [ -L "$BIN/lvm" ]; then
        case "$(readlink "$BIN/lvm")" in
            *lvm-instalador.sh) rm -f "$BIN/lvm" ;;
        esac
    fi

    for home in $HOMES; do
        [ -d "$home" ] && [ ! -L "$home" ] || continue

        # Iconos del menu de antes (lampp-version-manager.desktop) que abren un [lp]vm-instalador.sh:
        # con el del paquete se quitan; si no, pasan a nexum.desktop y abren el script de /opt
        f=$home/.local/share/applications/lampp-version-manager.desktop
        if [ -f "$f" ] && [ ! -L "$f" ] && grep -q '^Exec=.*[lp]vm-instalador\.sh' "$f" && as_owner "$f"; then
            if [ -f "$APPS/nexum.desktop" ]; then
                $run_as rm -f "$f" || true
            else
                $run_as python3 -I - "$f" "$SCRIPT" <<'PY' || true
import os, re, sys
old, script = sys.argv[1], sys.argv[2]
new = os.path.join(os.path.dirname(old), "nexum.desktop")
with open(old, encoding="utf-8") as fh:
    text = fh.read()
token = re.compile(r'"[^"\n]*[lp]vm-instalador\.sh"|[^\s=]*[lp]vm-instalador\.sh')
text = "\n".join(token.sub(script, l) if l.startswith("Exec=") else l for l in text.split("\n"))
# (si ya hay un nexum.desktop, es el tuyo: se queda)
if not os.path.lexists(new):
    fd = os.open(new, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o755)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)
os.remove(old)
PY
            fi
            $run_as touch "$(dirname "$f")" || true
        fi

        # Temporizador de los proyectos de Docker sin visitas: llamaba a la orden de antes
        f=$home/.config/systemd/user/nexum-reposo.service
        if [ -f "$f" ] && [ ! -L "$f" ] && grep -q '^ExecStart=.*lvm-instalador' "$f" && as_owner "$f"; then
            $run_as python3 -I - "$f" "$NEXUM_CMD" <<'PY' || true
import os, re, sys
path, cmd = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    text = fh.read()
new = re.sub(r"(?m)^ExecStart=(/usr/local/bin/lvm-instalador|/opt/lvm-instalador/lvm-instalador\.sh) (docker-reposo comprobar)$",
             lambda m: "ExecStart=%s %s" % (cmd, m.group(2)), text)
if new != text:
    tmp = path + ".nuevo"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(new)
    os.replace(tmp, path)
PY
            # (si tiene la sesion abierta, su systemd lo relee ya; si no, al entrar)
            uid=$(stat -c %u "$f")
            if [ -S "$RUNDIR/$uid/bus" ]; then
                $run_as env XDG_RUNTIME_DIR="$RUNDIR/$uid" systemctl --user daemon-reload > /dev/null 2>&1 || true
            fi
        fi
    done

    command -v update-desktop-database > /dev/null && update-desktop-database -q "$APPS" || true
    command -v gtk-update-icon-cache > /dev/null && gtk-update-icon-cache -q -t "$ICONS" || true
fi
exit 0
EOF

cat > "$ROOT/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
SCRIPT=/opt/nexum/nexum.sh
BIN=/usr/local/bin
APPS=/usr/share/applications
HOMES="/home/* /root"

# Como en el postinst: run_as, para hacerlo como el dueño de <fichero>
as_owner() {
    owner=$(stat -c %U "$1") || return 1
    run_as=""
    [ "$owner" = "$(id -un)" ] && return 0
    command -v runuser > /dev/null || return 1
    run_as="runuser -u $owner --"
}

if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    # La orden nexum, si es la de este paquete (lvm no es suyo: no se toca)
    if [ -L "$BIN/nexum" ] && [ "$(readlink "$BIN/nexum")" = "$SCRIPT" ]; then
        rm -f "$BIN/nexum"
    fi
    # Iconos de usuario que abrian el script desinstalado
    for home in $HOMES; do
        f=$home/.local/share/applications/nexum.desktop
        if [ -f "$f" ] && [ ! -L "$f" ] && grep -q "^Exec=.*$SCRIPT" "$f" && as_owner "$f"; then
            $run_as rm -f "$f" || true
        fi
    done
    command -v update-desktop-database > /dev/null && update-desktop-database -q "$APPS" || true
fi
exit 0
EOF
# Permisos normales de un paquete (sin escritura para el grupo, aunque la umask sea 002)
chmod -R u=rwX,go=rX "$ROOT"
chmod 755 "$ROOT$DEST/nexum.sh" "$ROOT$DEST/nexum-actualizar" "$ROOT/DEBIAN/postinst" \
    "$ROOT/DEBIAN/postrm"

mkdir -p "$OUT"
DEB=$OUT/${PKG}_${VERSION}_all.deb
fakeroot dpkg-deb --build -Zxz "$ROOT" "$DEB" > /dev/null
echo "$DEB"
