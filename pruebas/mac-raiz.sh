#!/bin/bash
# Pruebas del Mac (1.39.3), sin root ni red: lo que se ejecuta como root sale solo de carpetas de root.
#   - el arranque (bash 3.2): sin nada de bash 4 antes del bash del gestor, versiones, carpetas de root
#     (boot_root_owned, con un stat de mentira), entorno limpio (boot_clean_exec) y los ficheros del
#     bash de GNU con su sha256
#   - sudo: solo programas del sistema o de /Library/Nexum (root_command, ROOT_EXEC_PY), HOME de root
#   - el paso de /Applications a /Library/Nexum (MIGRATE_PY con otool, install_name_tool y codesign de
#     mentira): rutas, enlaces, librerias, PHP-FPM, deshacer, fallos, diario a medias, repetir
#   - las librerias que cargan los programas de una version (MACHO_AUDIT_PY)
#   - rutas nuevas en VHOSTS_CHECK_PY, OLD_LOGS_SED, vhosts_open_listen, procesos, Docker, el .dmg y
#     la ventana; la copia vieja que se queda en aviso y los comandos
# Uso: mac-raiz.sh <macos/lvm-instalador.sh> [macos/empaquetar-dmg.sh]
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
DMG=${2:-$(dirname "$SRC")/empaquetar-dmg.sh}
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-macraiz.XXXX") || exit 1
trap 'chmod -R u+w "$W" 2> /dev/null; rm -rf "$W"' EXIT
if ! grep -q '^function root_command() {' "$SRC"; then
    echo "  ok    (este script del Mac aun no instala el gestor en /Library/Nexum)"
    exit 0
fi
getvar() { ( eval "$(sed -n "/^$1='/,/^'\$/p" "$SRC")"; printf '%s.' "${!1}" ); }
for v in MIGRATE_PY MACHO_AUDIT_PY ROOT_EXEC_PY VHOSTS_CHECK_PY OLD_LOGS_SED BOOT_BASH_SH; do
    eval "$v=\$(getvar $v)"; eval "$v=\${$v%.}"
done
eval "$(sed -n '/^NEXUM_DIR=/p; /^TRUSTED_DIR=/p; /^TRUSTED_SCRIPT=/p; /^TRUSTED_BASH=/p; /^TRUSTED_BASH_VERSION=/p' "$SRC")"
eval "$(sed -n '/^TRUSTED_BASH_FILES="/,/"$/p' "$SRC")"

# --- El arranque, con bash 3.2 (el del sistema): hasta el bash del gestor, nada de bash 4 ---
BOOT=$(awk '/^# Arranque: macOS trae bash 3.2/ {p = 1} p {print} /^# Desde aqui, bash moderno/ {exit}' "$SRC")
check "arranque: esta antes que todo lo demas" '[ -n "$BOOT" ] && [ "$(grep -n "^# Arranque: macOS trae bash 3.2" "$SRC" | cut -d: -f1)" -lt "$(grep -n "^function sudo() {" "$SRC" | cut -d: -f1)" ]'
check "arranque: sin nada de bash 4 (declare -A, \${x,,}, mapfile, ;&, |&, local -n, [[ -v)" '! grep -nE "declare -A|local -A|\\$\\{[A-Za-z_]+(,,|\\^\\^)|mapfile|readarray|;;&|;&|\\|&|local -n|\\[\\[ -v|\\$\\{[A-Za-z_]+@" <<< "$BOOT"'
# (ni =~ con parentesis, que el bash 3.2 de macOS no entiende; ni arrays con valor en local)
check "arranque: sin =~ ni local x=(...) (bash 3.2)" '! grep -nE "=~|local [^=]*=\\(" <<< "$(grep -v "^ *#" <<< "$BOOT")"'
B32=${LVM_BASH32:-}
if [ -n "$B32" ] && [ -x "$B32" ]; then
    check "arranque: bash 3.2 ($B32) lo entiende" '"$B32" -n <<< "$BOOT"'
fi
check "arranque: los programas, del sistema (PATH del sistema primero)" 'grep -q "^export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" <<< "$BOOT" && ! grep -q "exec /opt/homebrew/bin/bash \"\$0\"" <<< "$(sed "/LVM_PRUEBA/,/^elif/d" <<< "$BOOT")"'
check "arranque: el bash de Homebrew solo en las pruebas (LVM_PRUEBA)" '[ "$(grep -c "/opt/homebrew/bin/bash" <<< "$BOOT")" -le 2 ] && sed -n "/^if \[ -n \"\$LVM_PRUEBA\" \]; then/,/^elif/p" <<< "$BOOT" | grep -q "exec /opt/homebrew/bin/bash"'
check "arranque: ya no ejecuta la salida de brew shellenv" '! grep -q "brew\" shellenv" "$SRC" && grep -q "^export HOMEBREW_PREFIX=/opt/homebrew" "$SRC"'
check "arranque: gestor en /Library/Nexum/gestor" '[ "$TRUSTED_SCRIPT" = /Library/Nexum/gestor/lvm-instalador.sh ] && [ "$TRUSTED_BASH" = /Library/Nexum/gestor/bash ]'
if command -v bash > /dev/null; then
    check "arranque: bash entiende el arranque por separado" 'bash -n <<< "$BOOT"'
fi
extract "$SRC" boot_version_gt boot_version_of boot_root_owned boot_bash_ok || exit 1
check "version: 1.39.10 > 1.39.9" 'boot_version_gt 1.39.10 1.39.9'
check "version: 1.40 > 1.39.3" 'boot_version_gt 1.40 1.39.3'
check "version: la misma no es mas nueva" '! boot_version_gt 1.39.3 1.39.3'
check "version: 1.39.3 no es mas nueva que 1.39.3.1" '! boot_version_gt 1.39.3 1.39.3.1'
check "version: con 08 (no octal)" 'boot_version_gt 1.39.08 1.39.7'
check "version: rara no vale" '! boot_version_gt "1.39;x" 1.0 && ! boot_version_gt "" 1.0'
printf '#!/bin/bash\nAPP_VERSION="1.39.3"\n' > "$W/v.sh"
check "version de un script" '[ "$(boot_version_of "$W/v.sh")" = 1.39.3 ]'
# boot_root_owned con un stat de mentira: de root todo, salvo lo que tenga "tuyo" (tu usuario) o
# "grupo" (escribible por el grupo) en la ruta
eval "$(sed -n '/^function boot_root_owned() {/,/^}/p' "$SRC" | sed "s#/usr/bin/stat -f '%u %Lp'#stat_bsd#")"
stat_bsd() { case "$1" in *tuyo*) echo "501 755" ;; *grupo*) echo "0 775" ;; *sticky*) echo "0 1777" ;; *) echo "0 755" ;; esac; }
mkdir -p "$W/raiz/gestor" "$W/tuyo/gestor" "$W/raiz/grupo/x" "$W/raiz/sticky"; touch "$W/raiz/gestor/bash" "$W/tuyo/gestor/bash" "$W/raiz/grupo/x/bash" "$W/raiz/sticky/bash"
ln -s "$W/raiz/gestor" "$W/raiz/enlace"
check "carpeta de root: todo de root, si" 'boot_root_owned "$W/raiz/gestor/bash"'
check "carpeta de root: una carpeta de encima tuya, no" '! boot_root_owned "$W/tuyo/gestor/bash"'
check "carpeta de root: una carpeta de encima con escritura del grupo, no" '! boot_root_owned "$W/raiz/grupo/x/bash"'
check "carpeta de root: con escritura de todos (1777), no" '! boot_root_owned "$W/raiz/sticky/bash"'
check "carpeta de root: por un enlace, no" '! boot_root_owned "$W/raiz/enlace/bash"'
check "carpeta de root: ruta relativa o que no existe, no" '! boot_root_owned raiz/gestor/bash && ! boot_root_owned "$W/raiz/gestor/no-esta"'
TRUSTED_DIR=$W/raiz/gestor TRUSTED_BASH=$W/raiz/gestor/bash TRUSTED_BASH_VERSION=5.3.20
echo 5.3.20 > "$W/raiz/gestor/bash.version"
check "bash del gestor: de root y de la version, vale" 'boot_bash_ok'
echo 5.2.37 > "$W/raiz/gestor/bash.version"
check "bash del gestor: de otra version, se rehace" '! boot_bash_ok'
eval "$(sed -n '/^TRUSTED_DIR=/p; /^TRUSTED_BASH=/p; /^TRUSTED_BASH_VERSION=/p' "$SRC")"
# Los ficheros del bash de GNU: el de 5.3 y sus 20 parches, cada uno con su sha256
check "bash de GNU: bash-5.3.tar.gz y los parches 001 a 020 con su sha256" '[ "$(grep -cE "^(bash-5\.3\.tar\.gz|bash53-0[0-2][0-9])\|[0-9a-f]{64}$" <<< "$TRUSTED_BASH_FILES")" = 21 ] && [ "$TRUSTED_BASH_VERSION" = 5.3.20 ] && grep -q "^bash-5.3.tar.gz|0d5cd86965f869a26cf64f4b71be7b96f90a3ba8b3d74e27e8e9d9d5550f31ba$" <<< "$TRUSTED_BASH_FILES"'
check "bash de GNU: se compila como root con el entorno limpio y solo con librerias del sistema" 'grep -q "otool -L bash" <<< "$BOOT_BASH_SH" && grep -q "/usr/lib/\*|/System/\*" <<< "$BOOT_BASH_SH" && grep -q "shasum -a 256" <<< "$BOOT_BASH_SH" && sed -n "/^function boot_build_bash() {/,/^}/p" "$SRC" | grep -q "/usr/bin/sudo /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/root"'
# BOOT_BASH_SH de verdad, con curl y shasum de mentira: si un fichero no es el de la suma, se para
mkdir -p "$W/bb/bin" "$W/bb/t" "$W/bb/dest"
cat > "$W/bb/bin/curl" <<'EOF'
#!/bin/sh
while [ $# -gt 1 ]; do [ "$1" = -o ] && out=$2; shift; done
echo "falso de $1" > "$out"
EOF
chmod +x "$W/bb/bin/curl"
out=$(cd "$W/bb" && sed 's#/usr/bin/curl#curl#; s#/usr/bin/shasum -a 256#sha256sum#' <<< "$BOOT_BASH_SH" > s.sh && PATH=$W/bb/bin:$PATH sh s.sh "$W/bb/t" "$W/bb/dest" 2 5.3.20 "bash-5.3.tar.gz|0000000000000000000000000000000000000000000000000000000000000000" 2>&1); rc=$?
check "bash de GNU: un fichero que no es el de su sha256 no se compila ni se instala" '[ $rc -ne 0 ] && grep -q "con su suma sha256" <<< "$out" && [ ! -e "$W/bb/dest/bash" ] && [ ! -e "$W/bb/t" ]'

# --- Entorno limpio al volver a lanzar el gestor ---
extract "$SRC" boot_clean_exec || exit 1
printf '#!/bin/sh\nenv > "%s/env.txt"\n' "$W" > "$W/dump"; chmod +x "$W/dump"
( export BASH_ENV=/tmp/x SHELLOPTS=xtrace PS4='$(id)' DYLD_INSERT_LIBRARIES=/tmp/x.dylib LVM_PROGRESO=/tmp/p SUDO_PROMPT=marca PHP_TIMEZONE=Europe/Madrid LVM_GESTOR=0 OTRA=1
  f() { :; }; export -f f
  TRUSTED_BASH=$W/dump TRUSTED_SCRIPT=$W/x.sh boot_clean_exec arrancar ) 2> /dev/null
E=$(cat "$W/env.txt" 2> /dev/null)
check "entorno: sin BASH_ENV, SHELLOPTS, PS4, DYLD_* ni funciones exportadas" '[ -n "$E" ] && ! grep -qE "^(BASH_ENV|SHELLOPTS|PS4|DYLD_INSERT_LIBRARIES|OTRA)=|BASH_FUNC" <<< "$E"'
check "entorno: con las LVM_*, SUDO_PROMPT (la ventana), HOME y PHP_TIMEZONE" 'grep -qx "LVM_PROGRESO=/tmp/p" <<< "$E" && grep -qx "SUDO_PROMPT=marca" <<< "$E" && grep -q "^HOME=" <<< "$E" && grep -qx "PHP_TIMEZONE=Europe/Madrid" <<< "$E"'
check "entorno: PATH del sistema primero y la marca del gestor" 'grep -qx "PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin" <<< "$E" && grep -qx "LVM_GESTOR=1" <<< "$E"'

# --- sudo: solo programas del sistema o de /Library/Nexum, con HOME de root ---
extract "$SRC" root_command || exit 1
eval "$(sed -n '/^function sudo() {/,/^}/p' "$SRC" | sed 's#/usr/bin/sudo#fake_sudo#g')"
fake_sudo() { printf '%s\n' "$@" > "$W/sudo.txt"; }
ROOT_PATH=/usr/bin:/bin:/usr/sbin:/sbin TEST_DIR="" SELF=$TRUSTED_SCRIPT NEXUM_DIR=/Library/Nexum
ok_root() { rm -f "$W/sudo.txt"; sudo "$@" 2> /dev/null && [ -s "$W/sudo.txt" ]; }
no_root() { rm -f "$W/sudo.txt"; ! sudo "$@" 2> /dev/null && [ ! -e "$W/sudo.txt" ]; }
check "sudo: programa del sistema por su nombre (con el PATH del sistema)" 'ok_root cp a b && grep -qx "HOME=/var/root" "$W/sudo.txt" && grep -qx "PATH=$ROOT_PATH" "$W/sudo.txt" && grep -qx cp "$W/sudo.txt"'
check "sudo: /usr/bin/python3 y env VAR=... /usr/bin/python3, si" 'ok_root /usr/bin/python3 -I -c x && ok_root env LVM_SECURE_APPLY=1 /usr/bin/python3 -I -c x'
check "sudo: python3 de Homebrew, no" 'no_root /opt/homebrew/bin/python3 -c x'
check "sudo: el script xampp de /Applications (lo puede cambiar el grupo admin), no" 'no_root /Applications/XAMPP-8.4.27/xamppfiles/xampp start && no_root /Applications/XAMPP/xamppfiles/xampp start'
check "sudo: un programa de tu carpeta, no" 'no_root "$HOME/bin/x" && no_root ./x'
check "sudo: una ruta con .., no" 'no_root /usr/bin/../../tmp/x && no_root /Library/Nexum/../../tmp/x'
check "sudo: uno de /Library/Nexum, a traves de ROOT_EXEC_PY (root lo vuelve a mirar)" 'ok_root /Library/Nexum/XAMPP-8.4.27/xamppfiles/xampp start && [ "$(sed -n 4p "$W/sudo.txt")" = /usr/bin/python3 ] && grep -qx -- "-I" "$W/sudo.txt" && grep -qx /Library/Nexum "$W/sudo.txt" && tail -2 "$W/sudo.txt" | head -1 | grep -qx /Library/Nexum/XAMPP-8.4.27/xamppfiles/xampp'
check "sudo: uno de /Library/Nexum detras de env, no" 'no_root env X=1 /Library/Nexum/XAMPP-8.4.27/xamppfiles/xampp start'
check "sudo -n: igual" 'rm -f "$W/sudo.txt"; sudo -n /Library/Nexum/a/b 2> /dev/null; grep -qx -- -n "$W/sudo.txt" && ! { rm -f "$W/sudo.txt"; sudo -n /opt/homebrew/bin/x 2> /dev/null; } && [ ! -e "$W/sudo.txt" ]'
check "sudo -u otro usuario: tal cual (no es root)" 'rm -f "$W/sudo.txt"; sudo -u pepe /opt/homebrew/bin/x; [ "$(head -1 "$W/sudo.txt")" = -u ] && ! grep -q HOME= "$W/sudo.txt"'
SELF=$W/lvm-instalador/lvm-instalador.sh
check "sudo: desde una copia que no es el gestor de root, nada" 'no_root cp a b && out=$(sudo cp a b 2>&1); grep -q "gestor es $TRUSTED_SCRIPT" <<< "$out"'
SELF=$TRUSTED_SCRIPT
S0=$(grep -n "^function sudo() {" "$SRC" | cut -d: -f1)
check "sudo: despues del arranque, /usr/bin/sudo solo en la funcion sudo (y con -u, que no es root)" '[ -z "$(awk -v s="$S0" "NR > s + 6 && /\/usr\/bin\/sudo/ && !/\/usr\/bin\/sudo -u/ && !/^ *#/ && !/path == / && !/^ *\/\//" "$SRC")" ]'
# ROOT_EXEC_PY: lo vuelve a mirar como root y lo ejecuta
check "ROOT_EXEC_PY: uno de root (en una carpeta de root) se ejecuta con sus argumentos" '[ "$(python3 -I -c "$ROOT_EXEC_PY" /usr /usr/bin/printf %s hola)" = hola ]'
check "ROOT_EXEC_PY: fuera de la carpeta, no" '! python3 -I -c "$ROOT_EXEC_PY" /Library/Nexum /usr/bin/true 2> /dev/null'
mkdir -p "$W/nx/bin"; printf '#!/bin/sh\necho mal\n' > "$W/nx/bin/x"; chmod 755 "$W/nx/bin/x"; ln -s "$W/nx/bin/x" "$W/nx/bin/y"
check "ROOT_EXEC_PY: uno tuyo, no (126)" 'out=$(python3 -I -c "$ROOT_EXEC_PY" "$W/nx" "$W/nx/bin/x" 2>&1); [ $? -eq 126 ] && ! grep -q mal <<< "$out"'
check "ROOT_EXEC_PY: por un enlace, no" '! python3 -I -c "$ROOT_EXEC_PY" "$W/nx" "$W/nx/bin/y" > /dev/null 2>&1'

# --- Rutas: /Library/Nexum para las versiones, /Applications solo para el enlace y el oficial ---
check "rutas: versiones y compartido en /Library/Nexum; el enlace y el oficial en /Applications" 'grep -q "^    BASE_DIR=/Library/Nexum$" "$SRC" && grep -q "^    APPS_DIR=/Applications$" "$SRC" && grep -q "^LINK=\$APPS_DIR/XAMPP$" "$SRC" && grep -q "^COMMON=\$BASE_DIR/XAMPP-compartido$" "$SRC" && ! grep -q "\$BASE_DIR\"\{0,1\}/XAMPP-oficial" "$SRC"'
extract "$SRC" trusted_version_dir || exit 1
check "trusted_version_dir: las de /Applications, no (aunque sean de root)" '! trusted_version_dir /Applications/XAMPP-8.4.27 && ! trusted_version_dir /Applications/XAMPP'
vc() { printf '<VirtualHost *:443>\n    ServerName a.local\n    %b\n</VirtualHost>\n' "$1" > "$W/v.conf"; python3 -I -c "$VHOSTS_CHECK_PY" "$W/v.conf" ${2:+"$2"} > /dev/null; }
check "vhosts: certificados y registros de /Library/Nexum, si" 'vc "SSLCertificateFile \"/Library/Nexum/XAMPP-compartido/ssl/a.crt\"\n    SSLCertificateKeyFile /Library/Nexum/XAMPP-8.5.12/xamppfiles/etc/ssl.key/a.key\n    ErrorLog \"/Library/Nexum/XAMPP-8.5.12/xamppfiles/logs/a\""'
check "vhosts: los de /Applications de antes de la 1.39.3, no" '! vc "SSLCertificateFile /Applications/XAMPP-compartido/ssl/a.crt" && ! vc "ErrorLog /Applications/XAMPP-8.5.12/xamppfiles/logs/a"'
printf 'SSLCertificateFile /Applications/XAMPP-compartido/ssl/a.crt\nSSLCertificateFile /opt/otra/b.crt\n' > "$W/antes.conf"
check "vhosts: ni aunque ya se usara (por /Applications); otro que ya se usaba, si" '! vc "SSLCertificateFile /Applications/XAMPP-compartido/ssl/a.crt" "$W/antes.conf" && vc "SSLCertificateFile /opt/otra/b.crt" "$W/antes.conf"'
check "vhosts: el Include de la clave de Docker, solo el de /Library/Nexum" 'vc "Include \"/Library/Nexum/XAMPP-compartido/docker-claves/tienda.conf\"" && ! vc "Include \"/Applications/XAMPP-compartido/docker-claves/tienda.conf\""'
printf '  ErrorLog "/Applications/XAMPP/xamppfiles/logs/a"\n  SSLCertificateFile "/Applications/XAMPP-compartido/ssl/a.crt"\n  Include "/Applications/XAMPP-compartido/docker-claves/t.conf"\n  CustomLog /Applications/XAMPP-8.5.12/xamppfiles/logs/b common\n  DocumentRoot "/Applications/XAMPP/xamppfiles/htdocs/p"\n' > "$W/viejo.conf"
sed -E "$OLD_LOGS_SED" "$W/viejo.conf" > "$W/nuevo.conf"
check "vhosts: al aplicarlos, las rutas de antes pasan a las de /Library/Nexum (y se admiten)" '! grep -qE "/Applications/XAMPP-(compartido|8)" "$W/nuevo.conf" && grep -q "/Library/Nexum/XAMPP-compartido/ssl/a.crt" "$W/nuevo.conf" && grep -q "Include \"/Library/Nexum/XAMPP-compartido/docker-claves/t.conf\"" "$W/nuevo.conf" && grep -q "/Library/Nexum/XAMPP-8.5.12/xamppfiles/logs/b" "$W/nuevo.conf" && grep -q "DocumentRoot \"/Applications/XAMPP/xamppfiles/htdocs/p\"" "$W/nuevo.conf" && python3 -I -c "$VHOSTS_CHECK_PY" <(printf "<VirtualHost *:443>\n"; cat "$W/nuevo.conf"; printf "</VirtualHost>\n") > /dev/null'
extract "$SRC" vhosts_open_listen || exit 1
realpath_f() { readlink -f "$1"; }
printf 'Include "/Library/Nexum/XAMPP-compartido/docker-claves/t.conf"\n' > "$W/vh1"; printf 'Include "/Applications/XAMPP-compartido/docker-claves/t.conf"\n' > "$W/vh2"
check "vhosts_open_listen: la clave de Docker de /Library/Nexum no se avisa; la de /Applications, si" '[ -z "$(VHOSTS_FILE=$W/vh1 vhosts_open_listen)" ] && [ -n "$(VHOSTS_FILE=$W/vh2 vhosts_open_listen)" ]'
DK=$(grep -m1 '^DOCKER_KEYS_DIR=' "$SRC" | cut -d= -f2)
check "Docker: las claves en /Library/Nexum/XAMPP-compartido/docker-claves" '[ "$DK" = /Library/Nexum/XAMPP-compartido/docker-claves ]'

# --- Procesos: los de /Library/Nexum, los del oficial y los de antes de la 1.39.3 ---
extract "$SRC" lampp_processes || exit 1
mkdir -p "$W/lib/XAMPP-8.5.12/xamppfiles/logs" "$W/apps"; ln -s "$W/lib/XAMPP-8.5.12" "$W/apps/XAMPP"; ln -s "$W/lib/XAMPP-8.5.12" "$W/apps/XAMPP-8.5.12"
d=$(LC_ALL=C date -d "+2 minutes" "+%a %b %d %H:%M:%S %Y")
cat > "$W/ps" <<P
  500     1 root     $d $W/lib/XAMPP-8.5.12/xamppfiles/apache2/bin/httpd -f $W/lib/XAMPP-8.5.12/xamppfiles/etc/httpd.conf
  600     1 root     $d $W/apps/XAMPP-7.4/xamppfiles/apache2/bin/httpd -f x
  700     1 root     $d /usr/sbin/httpd -D FOREGROUND
P
out=$(DRY=0 BASE_DIR=$W/lib APPS_DIR=$W/apps LEGACY_DIR=$W/apps LINK=$W/apps/XAMPP LVM_PS=$W/ps lampp_processes)
check "procesos: el de /Library/Nexum es de su version (la montada, no sobra)" 'grep -q "^P|500|1|root|8.5.12|0|httpd$" <<< "$out"'
check "procesos: uno de /Applications de antes de la 1.39.3 se reconoce (y sobra)" 'grep -q "^P|600|1|root|7.4|1|httpd$" <<< "$out"'
check "procesos: el Apache de macOS no" '! grep -q "^P|700|" <<< "$out"'
check "lampp_running: tambien /Applications (oficial y de antes)" 'sed -n "/^function lampp_running() {/,/^}/p" "$SRC" | grep -qF "^(\$BASE_DIR|\$APPS_DIR|\$LEGACY_DIR)/XAMPP"'

# --- MIGRATE_PY: de /Applications a /Library/Nexum, con herramientas de mentira ---
T=$W/m; mkdir -p "$T/tools"
cat > "$T/tools/otool" <<'EOF'
#!/usr/bin/python3
import sys
data = open(sys.argv[-1], "rb").read()[4:].decode()
print(sys.argv[-1] + ":")
for line in data.splitlines():
    if line.startswith("LC|"):
        _, cmd, val = line.split("|", 2)
        print("Load command")
        print("          cmd %s" % cmd)
        print("      cmdsize 56")
        print("         %s %s (offset 24)" % ("path" if cmd == "LC_RPATH" else "name", val))
EOF
cat > "$T/tools/install_name_tool" <<'EOF'
#!/usr/bin/python3
import sys
args, f = sys.argv[1:-1], sys.argv[-1]
raw = open(f, "rb").read(); magic, lines = raw[:4], raw[4:].decode().split("\n")
i = 0
while i < len(args):
    a = args[i]
    if a == "-id":
        lines = ["LC|LC_ID_DYLIB|" + args[i + 1] if l.startswith("LC|LC_ID_DYLIB|") else l for l in lines]; i += 2
    elif a == "-change":
        lines = [l.rsplit("|", 1)[0] + "|" + args[i + 2] if l.startswith("LC|") and not l.startswith("LC|LC_RPATH|") and l.rsplit("|", 1)[1] == args[i + 1] else l for l in lines]; i += 3
    elif a == "-rpath":
        lines = ["LC|LC_RPATH|" + args[i + 2] if l == "LC|LC_RPATH|" + args[i + 1] else l for l in lines]; i += 3
    else:
        sys.exit("opcion desconocida " + a)
if any("NO-CABE" in l for l in lines):
    sys.exit("no cabe")
open(f, "wb").write(magic + "\n".join(lines).encode())
EOF
printf '#!/bin/sh\necho "$*" >> "%s/firmas"\n' "$T" > "$T/tools/codesign"
chmod +x "$T/tools/"*
A=$T/Applications N=$T/Library/Nexum J=$N/.migracion
mkstack() {  # mkstack <version>
    local root=$A/XAMPP-$1 d=$A/XAMPP-$1/xamppfiles
    mkdir -p "$d/etc/extra" "$d/bin" "$d/lib" "$d/apache2/bin" "$d/var/mysql/wp" "$d/php/etc/conf.d" "$d/php/lib/php/extensions/no-debug-20240924" "$d/logs" "$d/mysql/bin"
    echo "$1|2.4.65|11.8.3|1.3.9|5.42|5.2.3" > "$d/etc/pvm-stack"; echo "$1" > "$d/etc/pvm-php"
    printf 'ServerRoot "%s"\nDocumentRoot "%s/XAMPP/xamppfiles/htdocs"\nSSLSessionCache "shmcb:%s/logs/ssl_scache(512000)"\n' "$d" "$A" "$d" > "$d/etc/httpd.conf"
    printf 'DefaultRoot %s/XAMPP/xamppfiles/htdocs\n<Directory %s/XAMPP/xamppfiles/htdocs/*>\n' "$A" "$A" > "$d/etc/proftpd.conf"
    printf '[mysqld]\nbasedir = %s/mysql\nsocket = %s/var/mysql/mysql.sock\n' "$d" "$d" > "$d/etc/my.cnf"
    printf '#!/bin/bash\nROOT=%s\n' "$d" > "$d/xampp"; chmod 755 "$d/xampp"
    printf '#!/bin/bash\n# PHP-FPM %s\nFPM=%s/php/sbin/php-fpm\nrunning || env -i "$FPM" --fpm-config "$CONF"\n' "$1" "$d" > "$d/bin/pvm-php-fpm"
    printf '\xcf\xfa\xed\xfe\nLC|LC_LOAD_DYLIB|%s/lib/libssl.3.dylib\nLC|LC_LOAD_DYLIB|/usr/lib/libSystem.B.dylib\nconfig %s/etc\n' "$d" "$d" > "$d/apache2/bin/httpd"
    printf '\xcf\xfa\xed\xfe\nLC|LC_ID_DYLIB|%s/lib/libssl.3.dylib\n' "$d" > "$d/lib/libssl.3.dylib"
    printf '\xcf\xfa\xed\xfe\nLC|LC_LOAD_DYLIB|/usr/lib/libz.1.dylib\nLC|LC_RPATH|%s/mysql/lib\nsolo una cadena %s\n' "$d" "$d" > "$d/mysql/bin/mariadbd"
    mkdir -p "$d/php/bin"; printf '\xcf\xfa\xed\xfe\nLC|LC_LOAD_DYLIB|/usr/lib/libSystem.B.dylib\nruta compilada %s/php/etc\n' "$d" > "$d/php/bin/php-cgi"
    mkdir -p "$d/mysql/lib"; printf '!<arch>\n\0plugin_dir %s/mysql/lib/plugin\0' "$d" > "$d/mysql/lib/libmariadbclient.a"
    printf 'tabla con %s dentro\n' "$d" > "$d/var/mysql/wp/wp_options.ibd"
    printf 'registro de %s\n' "$d" > "$d/logs/error_log"
    ln -s "$A/XAMPP-compartido/htdocs" "$d/htdocs"; ln -s "$A/XAMPP-compartido/httpd-vhosts.conf" "$d/etc/extra/httpd-vhosts.conf"
    ln -s ../php/bin/php "$d/bin/php"; ln -s xamppfiles/htdocs "$root/htdocs"
}
mkdir -p "$A" "$N"; chmod 755 "$N"
mkstack 7.4; mkstack 8.5.12
mkdir -p "$A/XAMPP-compartido/htdocs/tienda" "$A/XAMPP-compartido/docker-claves" "$A/XAMPP-compartido/ssl"; chmod 775 "$A/XAMPP-compartido"
echo "<?php // $A/XAMPP-compartido/htdocs" > "$A/XAMPP-compartido/htdocs/tienda/index.php"
printf '<VirtualHost *:443>\n    DocumentRoot "%s/XAMPP-compartido/htdocs/tienda"\n    SSLCertificateFile "%s/XAMPP-compartido/ssl/t.crt"\n    ErrorLog "%s/XAMPP-8.5.12/xamppfiles/logs/t"\n    Include "%s/XAMPP-compartido/docker-claves/t.conf"\n</VirtualHost>\n' "$A" "$A" "$A" "$A" > "$A/XAMPP-compartido/httpd-vhosts.conf"
echo "# $A/XAMPP-compartido/ (clave)" > "$A/XAMPP-compartido/docker-claves/t.conf"
ln -s "$A/XAMPP-8.5.12" "$A/XAMPP"
mkdir -p "$A/XAMPP-9.9/xamppfiles"; echo otra > "$A/XAMPP-9.9/xamppfiles/x"   # sin pvm-stack: no es del gestor
mkdir -p "$A/XAMPP-oficial-20260101/xamppfiles"
cp -a "$A" "$T/antes"
TMPL=$(sed -n "/^function fpm_script_template() {/,/^}/p" "$SRC" | sed '1,2d;$d' | sed '$d')
mig() { LVM_PRUEBA_HERRAMIENTAS=$T/tools python3 -I -c "$MIGRATE_PY" "$1" "$A" "$N" "$J" "$A/XAMPP" "$TMPL"; }
out=$(mig migrar); rc=$?
F=$N/XAMPP-8.5.12/xamppfiles
check "migrar: termina bien y dice que mueve 7.4, 8.5.12 y XAMPP-compartido" '[ $rc -eq 0 ] && grep -qx "M|7.4" <<< "$out" && grep -qx "M|8.5.12" <<< "$out" && grep -qx "M|XAMPP-compartido" <<< "$out"'
check "migrar: las carpetas estan en /Library/Nexum, y en /Applications un enlace a cada una" '[ -d "$F" ] && [ ! -L "$N/XAMPP-8.5.12" ] && [ "$(readlink "$A/XAMPP-8.5.12")" = "$N/XAMPP-8.5.12" ] && [ "$(readlink "$A/XAMPP-7.4")" = "$N/XAMPP-7.4" ] && [ "$(readlink "$A/XAMPP-compartido")" = "$N/XAMPP-compartido" ]'
check "migrar: /Applications/XAMPP lleva a la carpeta nueva" '[ "$(readlink "$A/XAMPP")" = "$N/XAMPP-8.5.12" ]'
check "migrar: lo que no es una version del gestor y el XAMPP oficial no se tocan" '[ -d "$A/XAMPP-9.9" ] && [ ! -L "$A/XAMPP-9.9" ] && [ ! -e "$N/XAMPP-9.9" ] && grep -q "^S|$A/XAMPP-9.9|" <<< "$out" && [ -d "$A/XAMPP-oficial-20260101" ] && [ ! -L "$A/XAMPP-oficial-20260101" ]'
check "migrar: la configuracion y los scripts con las rutas nuevas" 'grep -qx "ServerRoot \"$F\"" "$F/etc/httpd.conf" && grep -q "shmcb:$F/logs/ssl_scache" "$F/etc/httpd.conf" && grep -qx "ROOT=$F" "$F/xampp" && grep -qx "basedir = $F/mysql" "$F/etc/my.cnf" && [ -x "$F/xampp" ]'
check "migrar: DocumentRoot por /Applications/XAMPP sigue (lo usan los trabajadores, no root)" 'grep -qx "DocumentRoot \"$A/XAMPP/xamppfiles/htdocs\"" "$F/etc/httpd.conf"'
check "migrar: el FTP (chroot como root) entra por la ruta de su version, no por /Applications/XAMPP" 'grep -qx "DefaultRoot $F/htdocs" "$F/etc/proftpd.conf" && grep -q "^<Directory $F/htdocs/\*>" "$F/etc/proftpd.conf"'
check "migrar: los enlaces de la version, a XAMPP-compartido nuevo" '[ "$(readlink "$F/htdocs")" = "$N/XAMPP-compartido/htdocs" ] && [ "$(readlink "$F/etc/extra/httpd-vhosts.conf")" = "$N/XAMPP-compartido/httpd-vhosts.conf" ] && [ "$(readlink "$F/bin/php")" = ../php/bin/php ] && [ "$(readlink "$N/XAMPP-8.5.12/htdocs")" = xamppfiles/htdocs ]'
check "migrar: las librerias de los programas (install_name_tool) y su firma local otra vez" 'grep -q "^LC|LC_LOAD_DYLIB|$F/lib/libssl.3.dylib$" "$F/apache2/bin/httpd" && grep -q "^LC|LC_ID_DYLIB|$F/lib/libssl.3.dylib$" "$F/lib/libssl.3.dylib" && grep -q "^LC|LC_RPATH|$F/mysql/lib$" "$F/mysql/bin/mariadbd" && grep -q -- "--force --sign - --identifier httpd" "$T/firmas"'
check "migrar: las cadenas compiladas no se tocan (las rehace actualizar)" 'grep -q "^config $A/XAMPP-8.5.12/xamppfiles/etc$" "$F/apache2/bin/httpd" && grep -q "^solo una cadena $A/" "$F/mysql/bin/mariadbd"'
check "migrar: un programa con la ruta solo en sus cadenas no se cambia ni se vuelve a firmar" '! grep -q "identifier php-cgi " "$T/firmas" && grep -q "^ruta compilada $A/XAMPP-8.5.12/xamppfiles/php/etc$" "$F/php/bin/php-cgi"'
check "migrar: otros binarios (.a) no se tocan (cambiar la longitud de una ruta los romperia)" 'grep -qa "plugin_dir $A/XAMPP-8.5.12/xamppfiles/mysql/lib/plugin" "$F/mysql/lib/libmariadbclient.a"'
check "migrar: las BBDD y los registros, tal cual" 'grep -qx "tabla con $A/XAMPP-8.5.12/xamppfiles dentro" "$F/var/mysql/wp/wp_options.ibd" && grep -qx "registro de $A/XAMPP-8.5.12/xamppfiles" "$F/logs/error_log"'
check "migrar: los proyectos de htdocs, tal cual" 'grep -qx "<?php // $A/XAMPP-compartido/htdocs" "$N/XAMPP-compartido/htdocs/tienda/index.php"'
check "migrar: los vhosts y la clave de Docker, con las rutas nuevas" '! grep -q "$A/XAMPP-" "$N/XAMPP-compartido/httpd-vhosts.conf" && grep -q "Include \"$N/XAMPP-compartido/docker-claves/t.conf\"" "$N/XAMPP-compartido/httpd-vhosts.conf" && grep -q "SSLCertificateFile \"$N/XAMPP-compartido/ssl/t.crt\"" "$N/XAMPP-compartido/httpd-vhosts.conf" && grep -q "$N/XAMPP-compartido/" "$N/XAMPP-compartido/docker-claves/t.conf"'
check "migrar: XAMPP-compartido sin escritura para el grupo (de root)" '[ "$(stat -c %a "$N/XAMPP-compartido")" = 755 ]'
check "migrar: PHP-FPM con el php.ini y conf.d de la carpeta nueva" 'grep -qx "INI=$F/php/etc/php.ini" "$F/bin/pvm-php-fpm" && grep -q "PHP_INI_SCAN_DIR=\"\${INI%/php.ini}/conf.d\"" "$F/bin/pvm-php-fpm" && grep -q "\"\$FPM\" -c \"\$INI\" --fpm-config \"\$CONF\"" "$F/bin/pvm-php-fpm" && grep -q "OPENSSL_MODULES=" "$F/bin/pvm-php-fpm" && grep -q "^# PHP-FPM 8.5.12 " "$F/bin/pvm-php-fpm" && bash -n "$F/bin/pvm-php-fpm"'
check "migrar: extension_dir de la carpeta nueva (el compilado es el de antes)" 'grep -qx "extension_dir = \"$F/php/lib/php/extensions/no-debug-20240924\"" "$F/php/etc/conf.d/00-lvm-rutas.ini"'
check "migrar: no quedan ficheros a medias" '[ -z "$(find "$N" "$A" -name "*.lvm-migracion" 2> /dev/null)" ]'
check "migrar: deja el diario hasta terminar" '[ -f "$J/diario.json" ] && [ "$(stat -c %a "$J")" = 700 ]'
out=$(mig deshacer)
check "deshacer: todo como estaba (ficheros, enlaces y carpetas)" 'diff -r --no-dereference "$A" "$T/antes" > /dev/null && [ ! -e "$N/XAMPP-8.5.12" ] && [ ! -e "$J" ] && [ "$(readlink "$A/XAMPP")" = "$A/XAMPP-8.5.12" ] && [ "$(stat -c %a "$A/XAMPP-compartido")" = 775 ]'
# Un programa en el que no cabe la ruta nueva: se para y se deja todo como estaba
printf '\xcf\xfa\xed\xfe\nLC|LC_LOAD_DYLIB|%s/XAMPP-8.5.12/xamppfiles/lib/NO-CABE.dylib\n' "$A" > "$A/XAMPP-8.5.12/xamppfiles/lib/zz.dylib"; cp -a "$A" "$T/antes2"
out=$(mig migrar); rc=$?
check "migrar con un fallo a mitad: error y todo como estaba, sin restos" '[ $rc -ne 0 ] && grep -q "^E|.*no cabe" <<< "$out" && diff -r --no-dereference "$A" "$T/antes2" > /dev/null && [ ! -e "$N/XAMPP-7.4" ] && [ ! -e "$J" ] && [ -z "$(find "$A" -name "*.lvm-migracion")" ]'
rm -f "$A/XAMPP-8.5.12/xamppfiles/lib/zz.dylib"
# Ya existe la de destino: no se mueve nada
mkdir "$N/XAMPP-7.4"
out=$(mig migrar); rc=$?
check "migrar: si ya existe la de /Library/Nexum, no se mueve nada" '[ $rc -ne 0 ] && grep -q "^E|ya existe $N/XAMPP-7.4" <<< "$out" && [ -d "$A/XAMPP-8.5.12" ] && [ ! -L "$A/XAMPP-8.5.12" ]'
rmdir "$N/XAMPP-7.4"
# /Library/Nexum que no es de root (o con escritura del grupo): no se mueve nada
chmod 775 "$N"; out=$(mig migrar); rc=$?; chmod 755 "$N"
check "migrar: si /Library/Nexum lo puede cambiar el grupo, no se mueve nada" '[ $rc -ne 0 ] && grep -q "^E|.*no es una carpeta de root" <<< "$out" && [ ! -L "$A/XAMPP-7.4" ]'
# Un diario a medias (se corto la otra vez): se deshace antes de empezar
out=$(mig migrar)
python3 -I -c 'import json, sys; p = sys.argv[1]; s = json.load(open(p)); s["done"] = False; json.dump(s, open(p, "w"))' "$J/diario.json"
out=$(mig migrar); rc=$?
check "migrar: lo que quedo a medias la otra vez se deshace y se vuelve a hacer" '[ $rc -eq 0 ] && grep -q "^I|Se deshace lo que quedo a medias" <<< "$out" && grep -qx "M|8.5.12" <<< "$out" && [ "$(readlink "$A/XAMPP-8.5.12")" = "$N/XAMPP-8.5.12" ] && grep -qx "ServerRoot \"$F\"" "$F/etc/httpd.conf"'
out=$(mig terminar)
check "terminar: borra el diario (y las copias de lo de antes)" '[ ! -e "$J" ]'
out=$(mig migrar); rc=$?
check "migrar otra vez: no hace nada" '[ $rc -eq 0 ] && ! grep -q "^M|" <<< "$out" && [ ! -e "$J" ] && [ "$(readlink "$A/XAMPP-8.5.12")" = "$N/XAMPP-8.5.12" ]'
check "migrar: sin herramientas de prueba como root (LVM_PRUEBA_HERRAMIENTAS solo sin root)" 'grep -q "os.getuid() != 0 and os.environ.get(\"LVM_PRUEBA_HERRAMIENTAS\")" <<< "$MIGRATE_PY" && grep -q "os.getuid() != 0 and os.environ.get(\"LVM_PRUEBA_HERRAMIENTAS\")" <<< "$MACHO_AUDIT_PY"'

# --- MACHO_AUDIT_PY: solo librerias de la version o del sistema ---
aud() { LVM_PRUEBA_HERRAMIENTAS=$T/tools python3 -I -c "$MACHO_AUDIT_PY" "$1"; }
check "librerias: una version bien, sin avisos" '[ -z "$(aud "$N/XAMPP-8.5.12")" ] && aud "$N/XAMPP-8.5.12"'
X=$N/XAMPP-8.5.12/xamppfiles
printf '\xcf\xfa\xed\xfe\nLC|LC_LOAD_DYLIB|/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib\n' > "$X/lib/brew.dylib"
check "librerias: una de /opt/homebrew, no" 'out=$(aud "$N/XAMPP-8.5.12"); [ $? -ne 0 ] && grep -q "lib/brew.dylib -> /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib" <<< "$out"'
printf '\xcf\xfa\xed\xfe\nLC|LC_LOAD_WEAK_DYLIB|/usr/local/lib/libx.dylib\n' > "$X/lib/brew.dylib"
check "librerias: una debil de /usr/local, no (dyld la cargaria si alguien la pone)" '! aud "$N/XAMPP-8.5.12" > /dev/null'
printf '\xcf\xfa\xed\xfe\nLC|LC_LOAD_DYLIB|@loader_path/../lib/libssl.3.dylib\n' > "$X/lib/brew.dylib"
check "librerias: @loader_path dentro de la version, si" 'aud "$N/XAMPP-8.5.12" > /dev/null'
printf '\xcf\xfa\xed\xfe\nLC|LC_LOAD_DYLIB|@loader_path/../../../../../tmp/x.dylib\n' > "$X/lib/brew.dylib"
check "librerias: @loader_path que sale de la version, no" '! aud "$N/XAMPP-8.5.12" > /dev/null'
printf '\xcf\xfa\xed\xfe\nLC|LC_LOAD_DYLIB|@rpath/libssl.3.dylib\nLC|LC_RPATH|/opt/homebrew/lib\n' > "$X/lib/brew.dylib"
check "librerias: @rpath con un LC_RPATH de /opt/homebrew, no" 'out=$(aud "$N/XAMPP-8.5.12"); [ $? -ne 0 ] && grep -q "LC_RPATH /opt/homebrew/lib" <<< "$out"'
printf '\xcf\xfa\xed\xfe\nLC|LC_LOAD_DYLIB|@rpath/libssl.3.dylib\nLC|LC_RPATH|@loader_path/../lib\n' > "$X/lib/brew.dylib"
check "librerias: @rpath con LC_RPATH dentro de la version, si" 'aud "$N/XAMPP-8.5.12" > /dev/null'
rm -f "$X/lib/brew.dylib"; ln -s /opt/homebrew/lib/libssl.3.dylib "$X/lib/fuera.dylib"
printf '\xcf\xfa\xed\xfe\nLC|LC_LOAD_DYLIB|%s/lib/fuera.dylib\n' "$X" > "$X/lib/usa.dylib"
check "librerias: por un enlace que lleva fuera de la version, no" '! aud "$N/XAMPP-8.5.12" > /dev/null'
rm -f "$X/lib/fuera.dylib" "$X/lib/usa.dylib"
check "install_stack: root mira las librerias de lo que copia antes de instalarlo" 'sed -n "/^function install_stack() {/,/^}/p" "$SRC" | grep -q "audit=\$(\$SUDO /usr/bin/python3 -I -c \"\$MACHO_AUDIT_PY\" \"\$root\")"'

# --- Lo de alrededor del paso: legacy_dirs, la copia vieja, los comandos, Docker ---
extract "$SRC" legacy_dirs retire_old_copies point_commands docker_refresh_compose script_is_newer || exit 1
realpath_f() { readlink -f "$1"; }
# (ln -h del Mac: en Linux, -n)
ln() { if [ "$1" = -sfh ]; then shift; command ln -sfn "$@"; else command ln "$@"; fi; }
L=$W/leg; mkdir -p "$L/XAMPP-8.4.27/xamppfiles/etc" "$L/XAMPP-7.4/xamppfiles" "$L/XAMPP-compartido" "$L/XAMPP-oficial-1"; touch "$L/XAMPP-8.4.27/xamppfiles/etc/pvm-stack"; ln -s "$N/XAMPP-8.5.12" "$L/XAMPP-8.5.12"
out=$(TEST_DIR="" LEGACY_DIR=$L legacy_dirs)
check "legacy_dirs: las versiones del gestor (carpetas) y XAMPP-compartido, no los enlaces ni el oficial" '[ "$(printf "%s\n" "$out" | sort | tr "\n" " ")" = "$L/XAMPP-8.4.27 $L/XAMPP-compartido " ]'
check "legacy_dirs: en las pruebas (LVM_PRUEBA), nada" '[ -z "$(TEST_DIR=$W LEGACY_DIR=$L legacy_dirs)" ]'
H=$W/casa; mkdir -p "$H/lvm-instalador" "$H/otra" "$W/bin"
printf '#!/bin/bash\nAPP_VERSION="1.39.2"\necho vieja\n' > "$H/lvm-instalador/lvm-instalador.sh"
printf '#!/bin/bash\nAPP_VERSION="1.40.0"\necho nueva\n' > "$H/otra/lvm-instalador.sh"
printf '#!/bin/bash\nAPP_VERSION="1.39.0"\n' > "$W/fuera.sh"
ln -s "$H/otra/lvm-instalador.sh" "$W/bin/lvm"; ln -s "$W/fuera.sh" "$W/bin/lvm-instalador"
( HOME=$H CMD_DIR=$W/bin APP_BUNDLE=$W/no.app OLD_APP_BUNDLES=() SELF=$TRUSTED_SCRIPT APP_VERSION=1.39.3; retire_old_copies ) > /dev/null 2>&1
check "copia vieja: la de ~/lvm-instalador se queda en un aviso que abre el gestor de root" '! grep -q "^APP_VERSION=" "$H/lvm-instalador/lvm-instalador.sh" && grep -qx "exec /bin/bash $TRUSTED_SCRIPT \"\$@\"" "$H/lvm-instalador/lvm-instalador.sh" && bash -n "$H/lvm-instalador/lvm-instalador.sh" && [ -x "$H/lvm-instalador/lvm-instalador.sh" ]'
check "copia vieja: una mas nueva o fuera de tu carpeta no se toca" 'grep -q "echo nueva" "$H/otra/lvm-instalador.sh" && grep -q "^APP_VERSION=\"1.39.0\"" "$W/fuera.sh"'
mkdir -p "$W/bin2"; ln -s "$H/lvm-instalador/lvm-instalador.sh" "$W/bin2/lvm-instalador"; ln -s /usr/bin/true "$W/bin2/lvm"
# (en Linux hay un lvm del sistema: el PATH, solo con ln y readlink)
mkdir -p "$W/pb"; for c in ln readlink; do command ln -s "$(type -P $c)" "$W/pb/$c"; done
( DRY=0 CMD_DIR=$W/bin2 SELF=$TRUSTED_SCRIPT; point_commands ); mkdir -p "$W/bin3"; ( DRY=0 CMD_DIR=$W/bin3 SELF=$TRUSTED_SCRIPT; PATH=$W/pb; point_commands )
check "comandos: el de la copia vieja pasa al gestor de root; uno de otro programa no se toca" '[ "$(readlink "$W/bin2/lvm-instalador")" = "$TRUSTED_SCRIPT" ] && [ "$(readlink "$W/bin2/lvm")" = /usr/bin/true ]'
check "comandos: si no estan, se crean (como hacia el .dmg)" '[ "$(readlink "$W/bin3/lvm-instalador")" = "$TRUSTED_SCRIPT" ] && [ "$(readlink "$W/bin3/lvm")" = "$TRUSTED_SCRIPT" ]'
D=$W/docker/tienda; mkdir -p "$D"; printf 'services:\n  php:\n    volumes:\n      - "%s/XAMPP-compartido/htdocs/tienda:/Applications/XAMPP/xamppfiles/htdocs/tienda"\n' "$L" > "$D/compose.yaml"; chmod 600 "$D/compose.yaml"
( DOCKER_DIR=$W/docker LEGACY_DIR=$L COMMON=$N/XAMPP-compartido HTDOCS_DIR=$N/XAMPP-compartido/htdocs; docker_refresh_compose ) > /dev/null
check "Docker: compose.yaml con la carpeta de /Library/Nexum (la de dentro del contenedor, igual)" 'grep -qF "\"$N/XAMPP-compartido/htdocs/tienda:/Applications/XAMPP/xamppfiles/htdocs/tienda\"" "$D/compose.yaml" && [ "$(stat -c %a "$D/compose.yaml")" = 600 ]'

# --- Las ordenes de root de alrededor ---
# (hasta la funcion siguiente: dentro de los heredocs puede haber lineas con solo })
body() { awk -v f="^function $1\\(\\) \\{" '$0 ~ f {p = 1; print; next} p && /^function / {exit} p' "$SRC"; }
check "xampp_ctl: una de /Applications dice que se pase con migrar" 'body xampp_ctl | grep -q "lvm-instalador migrar"'
check "use y asegurar: una de /Applications de antes, que se pase con migrar" 'body use_version | grep -q "lvm-instalador migrar" && body secure_command | grep -q "lvm-instalador migrar"'
check "asegurar --todas (Protegerlas): primero las pasa a /Library/Nexum" 'body secure_command | grep -q "stacks_migrate || moved=1"'
check "avisos (U|): las de /Applications salen como sin proteger" 'body unsecured_versions | grep -q "legacy_dirs"'
check "migrar: para con kill (nada de /Applications como root), comprueba y deshace si falla" 'body stacks_migrate | grep -q "close_processes --todos" && body stacks_migrate | grep -q "MIGRATE_PY\" deshacer" && body stacks_migrate | grep -q "stack_check" && ! body stacks_migrate | grep -q "xampp_ctl"'
check "migrar: comprueba cada version (librerias como root y sus programas)" 'body stack_check | grep -q "MACHO_AUDIT_PY" && body stack_check | grep -q "mariadbd --no-defaults --version"'
check "desinstalar: quita tambien su enlace de /Applications" 'body remove_version | grep -q "LEGACY_DIR/XAMPP-\$version"'
check "PHP-FPM: con -c y PHP_INI_SCAN_DIR de su carpeta (pilas nuevas)" 'grep -qF "    fpm_script_template | sed -e \"s|@ROOT@|\$target|g\" -e \"s|@VERSION@|\$version|g\" > \"\$S/bin/pvm-php-fpm\"" "$SRC" && body fpm_script_template | grep -q -- "-c \"\$INI\" --fpm-config"'
check "FTP: DefaultRoot por la ruta de la version (pilas nuevas)" 'body write_stack_files | grep -q "^DefaultRoot \$ftp_root$" && body install_stack | grep -q "local ftp_root=\$target/htdocs"'
check "actualizar-gestor: root copia el .zip a su carpeta y comprueba alli la firma" 'body install_update | grep -q "\$SUDO install -m 644 \"\$zip\" \"\$work/nuevo.zip\"" && body install_update | grep -q "UPDATE_VERIFY_PY\" \"\$work/nuevo.zip\" \"\$work/nuevo.zip.sig\"" && body install_update | grep -q "dest=\$TRUSTED_SCRIPT"'
check "actualizar-gestor: ya sin gpgv de Homebrew" '! body install_update | grep -q GPGV && ! body update_signed | grep -q GPGV && ! body github_update | grep -q "G|"'

# --- 1.39.5: sin gnupg, cerrar la ventana sin salir, barra de arriba ---
check "1.39.5: Buscar actualizaciones ya no ofrece instalar gnupg (ni preparar-firma)" '! grep -q "Falta gnupg\|Instalar gnupg\|\"preparar-firma\"\]" "$SRC"'
check "1.39.5: cerrar la ventana no sale de la aplicacion" 'grep -q "func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return false }" "$SRC" && ! grep -q "applicationShouldTerminateAfterLastWindowClosed.*return true" "$SRC"'
check "1.39.5: el icono del Dock vuelve a traer la ventana" 'grep -A6 "func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {" "$SRC" | grep -q "makeKeyAndOrderFront(nil)" && grep -A6 "func applicationShouldHandleReopen" "$SRC" | grep -q "return true"'
check "1.39.5: sin ventana, no se leen los datos cada 20 s" 'grep -A4 "Timer.scheduledTimer(withTimeInterval: 20" "$SRC" | grep -q "NSApp.windows.contains(where: { \$0.isVisible && \$0.canBecomeMain })"'
check "1.39.5: Salir y relaunchApp siguen cerrando la aplicacion" 'grep -A10 "^func relaunchApp()" "$SRC" | grep -q "NSApp.terminate(nil)" && grep -q "CommandGroup(replacing: .newItem) {}" "$SRC"'
check "1.39.5: la barra de arriba sin phpMyAdmin (sigue en Bases de datos y en el menu Gestor)" '! sed -n "/^struct TopBar: View {/,/^    func menuButton/p" "$SRC" | grep -q "phpmyadmin" && grep -q "Button(\"Abrir phpMyAdmin\") { openURL(\"http://127.0.0.1/phpmyadmin/\") }" "$SRC" && grep -B2 -A6 "PageTitle(title: \"Bases de datos\"" "$SRC" | grep -q "openURL(\"http://127.0.0.1/phpmyadmin/\")"'
check "1.39.5: al entrar en un apartado, Bases de datos y Docker plegados" 'grep -A8 "^    func openTab(_ key: String) {" "$SRC" | grep -q "expanded = expanded.filter { !\$0.hasPrefix(\"@db\") }" && grep -A8 "^    func openTab(_ key: String) {" "$SRC" | grep -q "dkOpen = \[\]" && ! grep -q "dbOpenedActive\|dkClosed" "$SRC"'
check "1.39.5: Docker, un proyecto desplegado a la vez (o los de la busqueda)" 'grep -q "model.dkOpen = model.dkOpen.contains(g.id) ? \[\] : \[g.id\]" "$SRC" && grep -q "return model.dkOpen.contains(g.id) || !model.dkQuery.trimmingCharacters(in: .whitespaces).isEmpty" "$SRC"'
check "1.39.5: el nombre, Nexum en negrita y Dev Stack normal y en azul" 'sed -n "/^struct TopBar: View {/,/^    func menuButton/p" "$SRC" | grep -q "Text(\"Nexum\").bold() + Text(String(name.dropFirst(5))).fontWeight(.regular).foregroundColor(blue)" && grep -q "let blue = scheme == .dark ? hexColor(0x4C9DFF) : hexColor(0x0A6FD6)" "$SRC"'

# --- La ventana y el .dmg ---
check "ventana: el script, siempre el de root (no el de su Info.plist)" 'grep -q "^let TRUSTED_SCRIPT = \"/Library/Nexum/gestor/lvm-instalador.sh\"$" "$SRC" && grep -q "^let SCRIPT: String = TRUSTED_SCRIPT$" "$SRC" && ! grep -q "forInfoDictionaryKey: \"LVMScript\"" "$SRC"'
check "ventana: htdocs y vhosts de /Library/Nexum" 'grep -q "?? \"/Library/Nexum/XAMPP-compartido/htdocs\"" "$SRC" && grep -q "var vhosts = \"/Library/Nexum/XAMPP-compartido/httpd-vhosts.conf\"" "$SRC"'
check "ventana: el entorno de las tareas sin BASH_ENV ni DYLD_* (solo las de la lista)" 'sed -n "/^func scriptEnv/,/^}/p" "$SRC" | grep -q "keep.contains(k)" && ! sed -n "/^func scriptEnv/,/^}/p" "$SRC" | grep -A3 "let keep" | grep -q "BASH_ENV\|DYLD"'
if [ -f "$DMG" ]; then
    INST=$(sed -n "/^cat > \"\$APP\/Contents\/Resources\/instalar.sh\" <<'EOF'$/,/^EOF$/p" "$DMG" | sed '1d;$d')
    check ".dmg: el instalador usa instalar-gestor (de root), sin copiar el script a tu carpeta" 'grep -q "/bin/bash \"\$NEW\" instalar-gestor" <<< "$INST" && ! grep -q "lvm-instalador/lvm-instalador.sh\|ln -s" <<< "$INST" && bash -n <<< "$INST"'
fi
check "ayuda: instalar-gestor y migrar" 'sed -n "3,/^$/p" "$SRC" | grep -q "lvm-instalador instalar-gestor" && sed -n "3,/^$/p" "$SRC" | grep -q "lvm-instalador migrar" && grep -q "^    migrar) gestor_migrate \"\$2\" ;;$" "$SRC" && grep -q "^    instalar-gestor) gestor_migrate --ventana ;;$" "$SRC"'
# (la 1.39.3 o una posterior, con las novedades de la 1.39.3 y las de la suya)
check "version 1.39.3 o posterior con sus novedades" 'v=$(sed -n "s/^APP_VERSION=\"\(.*\)\"$/\1/p" "$SRC"); [ "$(printf "1.39.3\n%s\n" "$v" | sort -V | head -1)" == "1.39.3" ] && grep -q "^1.39.3 (24 oct 2026)$" "$SRC" && grep -q "^${v//./\\.} (" "$SRC"'
# --- 1.39.7: la tarea no se queda en el 98 % (servicios sin la terminal de la tarea) ---
check "1.39.7: MariaDB, PHP-FPM, Apache y ProFTPD arrancan con < /dev/null" 'grep -qF "my.cnf\" < /dev/null > /dev/null 2>&1 &)" "$SRC" && grep -qF "pvm-php-fpm\" start < /dev/null" "$SRC" && grep -qF -- "-k start < /dev/null >> " "$SRC" && grep -qF "proftpd.conf\" < /dev/null 2> /dev/null &&" "$SRC"'
check "1.39.7: los scripts xampp instalados se corrigen al protegerlos" 'grep -q "Los servicios arrancan sin quedarse con la terminal de la tarea" "$SRC"'
check "1.39.7: la ventana acaba la tarea con la marca de fin" 'grep -q "private var finSeen = false" "$SRC" && grep -q "if !finished && !finSeen, FIN.firstMatch" "$SRC"'
check "1.39.7: fuera de la carpeta de compilacion antes de borrarla" '[ "$(grep -c "cd / && rm -rf \"\$build\"" "$SRC")" -ge 2 ]'
exit $fail
