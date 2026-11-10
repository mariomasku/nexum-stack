# ===========================================================================
# Arranque: macOS trae bash 3.2, sin whiptail. Esta parte funciona con bash 3.2: comprueba las
# herramientas de Apple y Homebrew, instala whiptail (newt) y se vuelve a lanzar con el bash del gestor.
#
# Lo que se ejecuta como root sale solo de carpetas de root (1.39.3): el gestor esta en
# /Library/Nexum/gestor (lvm-instalador.sh y un bash 5.3 compilado aqui desde el codigo de GNU, con su
# sha256 fijado, todo de root:wheel). Una copia en otra carpeta (la de ~/lvm-instalador de antes, la
# del .dmg, una descargada) no ejecuta nada como root: usa la instalada o, si es mas nueva, se instala
# (pide la contraseña una vez). Ni el bash ni el sudo de Homebrew (que son de tu usuario) se usan.
# ===========================================================================

BREW=/opt/homebrew/bin/brew
# (lo de esta parte, con los programas del sistema primero: los de Homebrew son de tu usuario)
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin

# Carpetas de root: el gestor (gestor/) y las versiones (XAMPP-X.Y.Z y XAMPP-compartido). /Library es
# de root y el grupo admin (tu usuario) no puede escribir en ella, al contrario que en /Applications
NEXUM_DIR=/Library/Nexum
TRUSTED_DIR=$NEXUM_DIR/gestor
TRUSTED_SCRIPT=$TRUSTED_DIR/lvm-instalador.sh
TRUSTED_BASH=$TRUSTED_DIR/bash
# bash del gestor: bash 5.3 con sus parches oficiales (los mismos que el de Homebrew, 5.3.20), con
# la suma sha256 de cada fichero de ftp.gnu.org. Se compila como root con las herramientas de Xcode
TRUSTED_BASH_VERSION=5.3.20
TRUSTED_BASH_FILES="bash-5.3.tar.gz|0d5cd86965f869a26cf64f4b71be7b96f90a3ba8b3d74e27e8e9d9d5550f31ba
bash53-001|1f608434364af86b9b45c8b0ea3fb3b165fb830d27697e6cdfc7ac17dee3287f
bash53-002|e385548a00130765ec7938a56fbdca52447ab41fabc95a25f19ade527e282001
bash53-003|f245d9c7dc3f5a20d84b53d249334747940936f09dc97e1dcb89fc3ab37d60ed
bash53-004|9591d245045529f32f0812f94180b9d9ce9023f5a765c039b852e5dfc99747d0
bash53-005|cca1ef52dbbf433bc98e33269b64b2c814028efe2538be1e2c9a377da90bc99d
bash53-006|29119addefed8eff91ae37fd51822c31780ee30d4a28376e96002706c995ff10
bash53-007|c0976bbfffa1453c7cfdd62058f206a318568ff2d690f5d4fa048793fa3eb299
bash53-008|097cd723cbfb8907674ac32214063a3fd85282657ec5b4e544d2c0f719653fb4
bash53-009|eee30fe78a4b0cb2fe20e010e00308899cfc613e0774ebb3c8557a1552f24f8c
bash53-010|cf76f1cce2ea300c18bff9f002d21f280cc931acd17c28518110b93fe6e72569
bash53-011|0298df8f5ea2a31d3be43ed7d269c5b3c7c342dd5b570bea7f64d66dcbbe7531
bash53-012|d71379b39bebaedaf123414414e77fb458a0a43b9ad3116594c6df7ca6754573
bash53-013|042f9cda967e24bf4211944697441e93d06ff42b4b998629a98a1b249279f200
bash53-014|bd4360b401d38507e358783dcad8536a99c6789f0d3a5bd0cfb8c4a34144696c
bash53-015|55b79ceee2fc27f6767eed697e939a7eb2fe2a28c01556bd75f18d581014f46e
bash53-016|9ea29b266b7d24cb34d0ff3f1c4631e4d527bfe2d1ef15d17cdb924bf31ef767
bash53-017|443b927b45c1558ca72052410f8b8f6e5152b617ed707061a2781d4375b0d1c3
bash53-018|ae715d76c50341d7d7095e9a8d2eeed1ca9546152c2ac7289206f90cf30ac697
bash53-019|a25c581e4d0057dea3833918438a930e2e86ee4c6dc17fe15267b7f04cbc4e3d
bash53-020|df217ed3a9122aa2286d9b67bbe348661b6a9db262b580c29150dae55d532896"

# Ruta real de un fichero. readlink -f no existe antes de macOS 12.3: alli se usa el python3 del
# sistema (el de las herramientas de Xcode, que ya hacen falta para compilar la ventana)
# (como readlink -f del Mac: nada si la ruta no existe)
if /usr/bin/readlink -f / > /dev/null 2>&1; then
    function realpath_f() { /usr/bin/readlink -f "$1"; }
else
    function realpath_f() {
        /usr/bin/python3 -I -c 'import os, sys
p = os.path.realpath(sys.argv[1])
if os.path.exists(p):
    print(p)
else:
    sys.exit(1)' "$1"
    }
fi

# ¿Es de root <ruta>, sin escritura para el grupo ni los demas, y tambien cada carpeta hasta /, sin
# enlaces? Lo que cumple esto no lo puede cambiar ningun programa de tu usuario (bash 3.2)
function boot_root_owned() {
    local p=$1 st
    case "$p" in /*) ;; *) return 1 ;; esac
    while :; do
        [ -L "$p" ] && return 1
        [ -e "$p" ] || return 1
        st=$(/usr/bin/stat -f '%u %Lp' "$p" 2> /dev/null) || return 1
        [ "${st%% *}" == 0 ] || return 1
        [ $(( 8#${st##* } & 8#022 )) -eq 0 ] || return 1
        [ "$p" == / ] && return 0
        p=$(/usr/bin/dirname "$p")
    done
}

function boot_version_of() { /usr/bin/grep -m1 '^APP_VERSION=' "$1" 2> /dev/null | /usr/bin/cut -d'"' -f2; }

# ¿Es la version <a> mas nueva que <b>? (numeros con puntos; bash 3.2)
function boot_version_gt() {
    local a b i x y v
    # (sin =~: el bash 3.2 de macOS no admite parentesis en la expresion)
    for v in "$1" "$2"; do
        case "$v" in ""|*[!0-9.]*|.*|*.|*..*) return 1 ;; esac
    done
    IFS=. read -r -a a <<< "$1"
    IFS=. read -r -a b <<< "$2"
    for i in 0 1 2 3 4; do
        x=$(( 10#${a[$i]:-0} )) y=$(( 10#${b[$i]:-0} ))
        [ $x -gt $y ] && return 0
        [ $x -lt $y ] && return 1
    done
    return 1
}

# El bash del gestor, de root y de esta version (TRUSTED_BASH_VERSION)
function boot_bash_ok() {
    boot_root_owned "$TRUSTED_BASH" && boot_root_owned "$TRUSTED_DIR/bash.version" \
        && [ "$(/bin/cat "$TRUSTED_DIR/bash.version" 2> /dev/null)" == "$TRUSTED_BASH_VERSION" ]
}

# ¿Se puede pedir la contraseña? En Terminal o en una tarea de la ventana (que tiene su terminal)
function boot_can_ask() { [ -t 0 ] && [ -t 1 ]; }

# Abre Terminal con este script y <argumentos> (desde la ventana o Finder no hay donde pedir la
# contraseña). El .command, en una carpeta tuya nueva
function boot_open_terminal() {
    local dir
    dir=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/lvm-instalar.XXXXXX") || return 1
    { printf '#!/bin/bash\nexec /bin/bash'; printf ' %q' "$BOOT_ME" "$@"; printf '\n'; } > "$dir/instalar.command"
    /bin/chmod 755 "$dir/instalar.command"
    /usr/bin/xattr -c "$dir/instalar.command" 2> /dev/null
    /usr/bin/open -a Terminal "$dir/instalar.command"
}

# Sin terminal (la ventana pidiendo datos, o abierta desde Finder) no se puede pedir la contraseña:
# para abrir la ventana se sigue en Terminal; lo demas falla diciendo como terminar
function boot_without_terminal() {
    case "$BOOT_CMD" in
        ""|ventana|gui)
            echo "Hay que terminar de instalar Nexum Dev Stack: se abre Terminal (pide tu contraseña de administrador)."
            boot_open_terminal "$@" && exit 0
            ;;
    esac
    echo "ERROR|Falta terminar de instalar Nexum Dev Stack en $TRUSTED_DIR (de root). Abre Terminal y escribe: lvm-instalador"
    exit 1
}

# Compila el bash del gestor como root: descarga (sha256 fijado), parches, configure y make en una
# carpeta de root de /private/tmp, con el entorno limpio y los programas del sistema
BOOT_BASH_SH='
set -e
tmp=$1 dest=$2 jobs=$3 version=$4
shift 4
cd "$tmp"
trap "/bin/rm -rf \"$tmp\"" EXIT
for item in "$@"; do
    name=${item%%|*} sum=${item#*|}
    case $name in bash-*.tar.gz) rel=$name ;; *) rel=bash-5.3-patches/$name ;; esac
    ok=0
    for base in https://ftp.gnu.org/gnu/bash https://ftpmirror.gnu.org/bash; do
        if /usr/bin/curl -q --proto =https --proto-redir =https -fsSL --retry 2 --max-time 120 -o "$name" "$base/$rel" \
                && [ "$(/usr/bin/shasum -a 256 "$name" | /usr/bin/cut -d" " -f1)" = "$sum" ]; then
            ok=1
            break
        fi
    done
    [ $ok -eq 1 ] || { echo "  No se ha podido descargar $name con su suma sha256 de ftp.gnu.org"; exit 1; }
done
/usr/bin/tar -xzf bash-5.3.tar.gz
cd bash-5.3
for item in "$@"; do
    name=${item%%|*}
    case $name in bash-*) continue ;; esac
    /usr/bin/patch -p0 -s -f < "../$name" > /dev/null || { echo "  El parche $name no se aplica"; exit 1; }
done
echo "  Compilando bash $version (un minuto)..."
if ! { ./configure --prefix="$dest" --disable-nls --without-bash-malloc > ../configure.log 2>&1 \
        && /usr/bin/make -j"$jobs" > ../make.log 2>&1; }; then
    echo "  No se ha podido compilar bash. Ultimas lineas:"
    /usr/bin/tail -15 ../configure.log ../make.log 2> /dev/null | /usr/bin/sed "s/^/    /"
    exit 1
fi
# Solo con librerias del sistema (nada de /opt/homebrew, que es de tu usuario)
for lib in $(/usr/bin/otool -L bash | /usr/bin/tail -n +2 | /usr/bin/awk "{ print \$1 }"); do
    case $lib in /usr/lib/*|/System/*) ;; *) echo "  bash usa $lib (fuera del sistema): no se instala"; exit 1 ;; esac
done
[ "$(./bash -c "echo \${BASH_VERSINFO[0]}")" = 5 ] || { echo "  El bash compilado no funciona"; exit 1; }
/usr/bin/install -o root -g wheel -m 755 bash "$dest/bash.nuevo"
/bin/mv -f "$dest/bash.nuevo" "$dest/bash"
printf "%s\n" "$version" > "$dest/bash.version.nuevo"
/usr/sbin/chown root:wheel "$dest/bash.version.nuevo"
/bin/chmod 644 "$dest/bash.version.nuevo"
/bin/mv -f "$dest/bash.version.nuevo" "$dest/bash.version"
'
function boot_build_bash() {
    local tmp jobs line
    local -a files
    files=()
    echo "Preparando el bash del gestor ($TRUSTED_BASH, de root): bash $TRUSTED_BASH_VERSION de ftp.gnu.org"
    jobs=$(/usr/sbin/sysctl -n hw.ncpu 2> /dev/null || echo 4)
    while IFS= read -r line; do [ -n "$line" ] && files+=("$line"); done <<< "$TRUSTED_BASH_FILES"
    tmp=$(/usr/bin/sudo /usr/bin/mktemp -d /private/tmp/lvm-bash.XXXXXX) || return 1
    /usr/bin/sudo /bin/chmod 700 "$tmp" || return 1
    /usr/bin/sudo /usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/root TMPDIR="$tmp/" LANG=C \
        /bin/sh -c "$BOOT_BASH_SH" sh "$tmp" "$TRUSTED_DIR" "$jobs" "$TRUSTED_BASH_VERSION" "${files[@]}" \
        || { echo "No se ha podido preparar el bash del gestor."; return 1; }
    boot_bash_ok || { echo "El bash del gestor no ha quedado bien en $TRUSTED_BASH."; return 1; }
}

# Instala esta copia en TRUSTED_SCRIPT (de root). Nunca una version mas vieja que la instalada
function boot_install_self() {
    local mine theirs new_v
    mine=$(boot_version_of "$BOOT_ME") theirs=$(boot_version_of "$TRUSTED_SCRIPT")
    if [ -n "$theirs" ] && boot_version_gt "$theirs" "$mine"; then
        echo "Ya tienes la $theirs en $TRUSTED_SCRIPT, mas nueva que esta ($mine): no se cambia."
        return 0
    fi
    if [ "$theirs" == "$mine" ] && /usr/bin/cmp -s "$BOOT_ME" "$TRUSTED_SCRIPT" && boot_bash_ok; then
        return 0
    fi
    if [ "$BOOT_DRY" == 1 ]; then
        echo "  [simulacion] se instalaria la $mine en $TRUSTED_SCRIPT (de root) y su bash en $TRUSTED_BASH"
        exit 0
    fi
    boot_can_ask || boot_without_terminal instalar-gestor
    echo "Nexum Dev Stack $mine se instala en $TRUSTED_DIR, una carpeta de root: lo que se ejecuta"
    echo "como administrador ya no sale de ficheros que pueda cambiar un programa de tu usuario."
    echo "Pide tu contraseña de administrador (una vez)."
    /usr/bin/sudo -v || return 1
    if [ -L "$NEXUM_DIR" ] || [ -L "$TRUSTED_DIR" ]; then
        echo "$NEXUM_DIR o $TRUSTED_DIR es un enlace: no se instala nada. Revisalo a mano."
        return 1
    fi
    /usr/bin/sudo /usr/bin/install -d -o root -g wheel -m 755 "$NEXUM_DIR" "$TRUSTED_DIR" || return 1
    /usr/bin/sudo /bin/chmod 755 "$NEXUM_DIR" "$TRUSTED_DIR" && /usr/bin/sudo /usr/sbin/chown root:wheel "$NEXUM_DIR" "$TRUSTED_DIR" \
        || return 1
    boot_root_owned "$TRUSTED_DIR" || { echo "$TRUSTED_DIR no ha quedado de root: no se instala nada."; return 1; }
    boot_bash_ok || boot_build_bash || return 1
    # Se copia y se comprueba la copia (de root): la version y que bash la entiende entera
    /usr/bin/sudo /usr/bin/install -o root -g wheel -m 755 "$BOOT_ME" "$TRUSTED_SCRIPT.nuevo" || return 1
    # (sin la cuarentena de la descarga)
    /usr/bin/sudo /usr/bin/xattr -c "$TRUSTED_SCRIPT.nuevo" 2> /dev/null
    new_v=$(boot_version_of "$TRUSTED_SCRIPT.nuevo")
    if [ "$new_v" != "$mine" ] || ! "$TRUSTED_BASH" -n "$TRUSTED_SCRIPT.nuevo" 2> /dev/null; then
        /usr/bin/sudo /bin/rm -f "$TRUSTED_SCRIPT.nuevo"
        echo "La copia de $BOOT_ME no es la $mine o esta dañada: no se instala."
        return 1
    fi
    /usr/bin/sudo /bin/mv -f "$TRUSTED_SCRIPT.nuevo" "$TRUSTED_SCRIPT" || return 1
    echo "Instalado en $TRUSTED_SCRIPT"
}

# Vuelve a lanzar el gestor con su bash y el entorno limpio: solo estas variables de la sesion (las
# demas podrian cambiar lo que hace bash: BASH_ENV, SHELLOPTS, funciones exportadas, DYLD_*...)
function boot_clean_exec() {
    local n
    local -a keep
    keep=()
    for n in $(compgen -e); do
        case "$n" in
            HOME|USER|LOGNAME|LANG|LC_*|TMPDIR|SHELL|TERM|COLUMNS|LINES|SSH_AUTH_SOCK|PHP_TIMEZONE|MYSQL_PWD) ;;
            __CF_USER_TEXT_ENCODING|SUDO_PROMPT|SUDO_USER|SUDO_UID|SUDO_GID|NEWT_COLORS|EDITOR|VISUAL|SUDO_EDITOR) ;;
            http_proxy|https_proxy|no_proxy|all_proxy|HTTP_PROXY|HTTPS_PROXY|NO_PROXY|ALL_PROXY|LVM_*) ;;
            *) continue ;;
        esac
        [ "$n" == LVM_GESTOR ] || keep+=("$n=${!n}")
    done
    exec /usr/bin/env -i "${keep[@]}" PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin \
        LVM_GESTOR=1 "$TRUSTED_BASH" "$TRUSTED_SCRIPT" "$@"
}

# Herramientas de Xcode, Homebrew (para las librerias con las que se compila) y whiptail (newt)
function boot_prereqs() {
    if ! /usr/bin/xcode-select -p > /dev/null 2>&1; then
        echo "Hacen falta las herramientas de linea de comandos de Xcode (compilador, make, python3)."
        echo "Se abre la ventana para instalarlas. Cuando terminen, vuelve a abrir este instalador."
        /usr/bin/xcode-select --install > /dev/null 2>&1
        exit 1
    fi

    if [ ! -x "$BREW" ]; then
        boot_can_ask || { echo "ERROR|Hace falta Homebrew: abre Terminal y escribe: lvm-instalador"; exit 1; }
        echo "Hace falta Homebrew (https://brew.sh) para instalar las librerias con las que se compila."
        echo "Homebrew no instala PHP: solo se usa para las librerias."
        printf "¿Instalar Homebrew ahora? [s/N]: "
        read answer
        case "$answer" in s|S|y|Y) ;; *) exit 1 ;; esac
        /bin/bash -c "$(/usr/bin/curl -q --proto =https --proto-redir =https -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || exit 1
    fi

    # (sin whiptail, el panel va en texto)
    if [ ! -x /opt/homebrew/bin/whiptail ] && boot_can_ask; then
        echo "Instalando con Homebrew whiptail (ventanas del panel)..."
        "$BREW" install --quiet newt || echo "No se ha podido instalar whiptail: el panel ira en texto."
    fi
}

BOOT_ME=$(realpath_f "$0")
# (la misma ruta si llega por el volumen de datos: /System/Volumes/Data/Library es /Library)
BOOT_ME=${BOOT_ME#/System/Volumes/Data}
BOOT_DRY=0 BOOT_CMD=$1
[ "$1" == --simular ] && BOOT_DRY=1 BOOT_CMD=$2
if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
    echo "Este instalador es para Mac con Apple Silicon (M1 o posterior)."
    exit 1
fi

if [ -n "$LVM_PRUEBA" ]; then
    # Pruebas sin sudo (LVM_PRUEBA): como hasta la 1.39.2, con el bash de Homebrew. Nada va como root
    # (SUDO vacio, y el sudo de abajo no ejecuta nada fuera del gestor de root)
    if [ -z "${BASH_VERSINFO[0]}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
        [ -x /opt/homebrew/bin/bash ] || { echo "Las pruebas (LVM_PRUEBA) usan el bash de Homebrew: brew install bash"; exit 1; }
        exec /opt/homebrew/bin/bash "$0" "$@"
    fi
elif [ "$BOOT_ME" == "$TRUSTED_SCRIPT" ]; then
    if [ "$LVM_GESTOR" != 1 ] || [ "$BASH" != "$TRUSTED_BASH" ] || [ -z "${BASH_VERSINFO[0]}" ] || [ "${BASH_VERSINFO[0]}" -lt 5 ]; then
        boot_prereqs
        if ! boot_bash_ok; then
            [ "$BOOT_DRY" == 1 ] && { echo "  [simulacion] se prepararia el bash del gestor en $TRUSTED_BASH"; exit 0; }
            boot_can_ask || boot_without_terminal "$@"
            /usr/bin/sudo -v && boot_build_bash || exit 1
        fi
        boot_clean_exec "$@"
    fi
else
    # Una copia fuera de la carpeta del gestor: la instalada, si es igual o mas nueva; si no, se instala
    # esta (instalar-gestor la instala aunque sea la misma version con cambios, y sigue con migrar)
    # (si el gestor instalado vuelve a llegar aqui, algo no cuadra con su ruta: se para, sin dar vueltas)
    if [ -n "$LVM_ARRANQUE_GESTOR" ]; then
        echo "ERROR|$TRUSTED_SCRIPT no se reconoce como el gestor de root ($BOOT_ME): revisa esa carpeta"
        exit 1
    fi
    export LVM_ARRANQUE_GESTOR=1
    boot_prereqs
    if [ "$BOOT_CMD" != instalar-gestor ] && boot_root_owned "$TRUSTED_SCRIPT" \
            && ! boot_version_gt "$(boot_version_of "$BOOT_ME")" "$(boot_version_of "$TRUSTED_SCRIPT")"; then
        exec /bin/bash "$TRUSTED_SCRIPT" "$@"
    fi
    boot_install_self || exit 1
    if [ "$BOOT_CMD" == instalar-gestor ]; then
        [ "$BOOT_DRY" == 1 ] && exec /bin/bash "$TRUSTED_SCRIPT" --simular migrar --ventana
        exec /bin/bash "$TRUSTED_SCRIPT" migrar --ventana
    fi
    exec /bin/bash "$TRUSTED_SCRIPT" "$@"
fi

# Desde aqui, bash moderno: el del gestor (de root), salvo en las pruebas. Las rutas de Homebrew, fijas
# (antes salian de "brew shellenv", un programa de tu usuario cuya salida se ejecutaba aqui)
export HOMEBREW_PREFIX=/opt/homebrew HOMEBREW_CELLAR=/opt/homebrew/Cellar HOMEBREW_REPOSITORY=/opt/homebrew
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin
unset LVM_ARRANQUE_GESTOR
set -o pipefail
# Los rangos de las expresiones ([A-Za-z0-9]) siguen el orden del idioma: con es_ES aceptarian letras
# con tilde, ², ½... en carpetas, bases y dominios. En orden C, solo ASCII. (LC_ALL manda sobre
# LC_COLLATE: si esta puesto, pasa a LANG)
[ -n "${LC_ALL:-}" ] && export LANG=$LC_ALL && unset LC_ALL
export LC_COLLATE=C

# sudo con su ruta (no el primero del PATH: /opt/homebrew/bin es de tu usuario y un sudo falso ahi
# se llevaria la contraseña) y lo que ejecuta como root con el PATH del sistema: el sudo de macOS no
# trae secure_path y buscaria python3, sed, seq... primero en Homebrew. Con -u otro usuario, sin
# cambios (no es root); -v y -k no ejecutan nada; -e edita como tu usuario.
# Como root, con HOME=/var/root: el sudo de macOS deja tu HOME, y lo que lee de ahi (~/.my.cnf de
# los clientes de MariaDB, ~/.curlrc...) lo puede cambiar cualquier programa tuyo. Y solo programas
# del sistema o del gestor de root (root_command): nunca uno de Homebrew ni de una carpeta tuya
ROOT_PATH=/usr/bin:/bin:/usr/sbin:/sbin
function sudo() {
    case "$1" in
        -v|-k|-e|-u) /usr/bin/sudo "$@" ;;
        -n) shift; root_command "$@" || return 1; /usr/bin/sudo -n /usr/bin/env PATH="$ROOT_PATH" HOME=/var/root "${ROOT_RUN[@]}" ;;
        *) root_command "$@" || return 1; /usr/bin/sudo /usr/bin/env PATH="$ROOT_PATH" HOME=/var/root "${ROOT_RUN[@]}" ;;
    esac
}

# Comprueba, ya como root y justo antes de ejecutarlo, que un programa de /Library/Nexum es de root
# y no lo pueden cambiar otros, el y cada carpeta hasta / (sin enlaces), y lo ejecuta. Mirarlo antes
# sin sudo no basta si algo de por medio se puede cambiar entre la comprobacion y el uso.
# Uso: <carpeta de root> <programa> [argumentos...]
ROOT_EXEC_PY='
import os, stat, sys
top, cmd = sys.argv[1], sys.argv[2]
def no(why):
    sys.stderr.write("No se ejecuta como administrador %s: %s\n" % (cmd, why))
    sys.exit(126)
if not cmd.startswith(top + "/") or os.path.realpath(cmd) != cmd:
    no("tiene que estar en %s, sin enlaces" % top)
p = cmd
while True:
    try:
        st = os.lstat(p)
    except OSError:
        no("no existe %s" % p)
    if stat.S_ISLNK(st.st_mode) or st.st_uid != 0 or st.st_mode & 0o022:
        no("%s no es de root o lo pueden cambiar otros" % p)
    if p == "/":
        break
    p = os.path.dirname(p)
if not stat.S_ISREG(os.lstat(cmd).st_mode) or not os.access(cmd, os.X_OK):
    no("no es un programa")
os.execv(cmd, [cmd] + sys.argv[3:])
'

# ¿Como se ejecuta <orden...> como root? Deja la orden en ROOT_RUN: un programa del sistema (SIP no
# deja cambiarlos) tal cual; uno de /Library/Nexum, a traves de ROOT_EXEC_PY. Cualquier otro (de
# Homebrew, de una carpeta tuya o de /Applications, que la puede cambiar el grupo admin), no: devuelve
# 1. Tampoco nada si este script no es el gestor de root (una copia tuya no ejecuta nada como root)
function root_command() {
    local cmd=$1 path i
    ROOT_RUN=()
    if [ -z "$TEST_DIR" ] && [ "$SELF" != "$TRUSTED_SCRIPT" ]; then
        echo "No se ejecuta nada como administrador desde $SELF: el gestor es $TRUSTED_SCRIPT, de root (instalalo con: bash $SELF instalar-gestor)" >&2
        return 1
    fi
    # (env VAR=valor orden: lo que se ejecuta es la orden)
    if [ "$cmd" == env ] || [ "$cmd" == /usr/bin/env ]; then
        for (( i = 2; i <= $#; i++ )); do
            [[ "${!i}" == *=* ]] || [[ "${!i}" == -* ]] || { cmd=${!i}; break; }
        done
        [ "$cmd" == env ] || [ "$cmd" == /usr/bin/env ] && cmd=/usr/bin/env
    fi
    case "$cmd" in
        */*) path=$cmd ;;
        *) path=$(PATH=$ROOT_PATH; type -P -- "$cmd") || path="" ;;
    esac
    if [ -z "$path" ] || [[ "$path" != /* ]] || [[ "$path" == *"/../"* ]] || [[ "$path" == *"/./"* ]]; then
        echo "No se ejecuta como administrador ${cmd}: no es un programa del sistema" >&2
        return 1
    fi
    case "$path" in
        /usr/bin/*|/bin/*|/usr/sbin/*|/sbin/*|/usr/libexec/*|/System/*)
            ROOT_RUN=("$@") ;;
        "$NEXUM_DIR"/*)
            # (detras de env, solo programas del sistema)
            if [ "$cmd" != "$1" ]; then
                echo "No se ejecuta como administrador $path detras de env" >&2
                return 1
            fi
            ROOT_RUN=(/usr/bin/python3 -I -c "$ROOT_EXEC_PY" "$NEXUM_DIR" "$@") ;;
        *)
            echo "No se ejecuta como administrador $path: no es del sistema ni de $NEXUM_DIR (de root)" >&2
            return 1 ;;
    esac
}

SELF=$(realpath_f "$0")
LOG_DIR="$HOME/.lvm-instalador"
# Hasta la 1.0.0 la carpeta era ~/.pvm-instalador: se renombra la primera vez
[ -d "$HOME/.pvm-instalador" ] && [ ! -e "$LOG_DIR" ] && mv "$HOME/.pvm-instalador" "$LOG_DIR"
# Solo tuya: lleva registros, copias de los vhosts y configuraciones con contraseñas
[ -d "$LOG_DIR" ] && [ ! -L "$LOG_DIR" ] && [ -O "$LOG_DIR" ] && chmod 700 "$LOG_DIR" 2> /dev/null
# Las copias de seguridad (BBDD de clientes, vhosts, /etc/hosts anteriores): solo las que se piden
# (--copia) y, las de los ficheros que cambia el programa, si esta el ajuste COPIES_FILES_FLAG
COPIES_DIR="$HOME/nexum-backups"
COPIES_FILES_FLAG="$LOG_DIR/copias-ficheros"
# (actualizar, rehacer y componentes-actualizar con --copia: las BBDD de una version que empieza vacia)
STACK_DB_COPY=0
# (hasta la 1.57.6 era ~/lvm-copias: copies_migrate la renombra al arrancar, salvo con --simular)
# Igual que la de los registros: solo tuya, aunque la carpeta ya existiera con otros permisos
[ -d "$COPIES_DIR" ] && [ ! -L "$COPIES_DIR" ] && [ -O "$COPIES_DIR" ] && chmod 700 "$COPIES_DIR" 2> /dev/null
LOG="$LOG_DIR/instalacion-$(date +%Y%m%d-%H%M%S).log"
PHP_TIMEZONE=${PHP_TIMEZONE:-Europe/Madrid}
# Va al php.ini de cada pila (y lo lee el maestro de PHP-FPM, que es root): solo un nombre de zona
# horaria, sin saltos de linea que metan otras directivas (extension=...)
if ! [[ "$PHP_TIMEZONE" =~ ^[A-Za-z][A-Za-z0-9_+/-]{0,63}$ ]]; then
    echo "PHP_TIMEZONE no es una zona horaria valida: se usa Europe/Madrid" >&2
    PHP_TIMEZONE=Europe/Madrid
fi
PMA_VERSION="5.2.3"
SPACE_STACK_GB=8

# Librerias de Homebrew para compilar (nunca PHP, Apache ni MariaDB de Homebrew)
STACK_BUILD_DEPS="pkgconf cmake bison openssl@3 pcre2 nghttp2 brotli oniguruma libzip libpng jpeg-turbo freetype webp icu4c libsodium argon2 readline gettext libiconv zlib sqlite fmt zstd lz4 xz"

# Pila propia de cada rama de PHP: rama PHP|Apache|MariaDB|ProFTPD|Perl
# Las ramas nuevas suben un escalon (MariaDB LTS y Perl mas modernos), para que los proyectos
# evolucionen con todo compatible entre si. Apache y ProFTPD solo tienen una rama estable.
# Se instala siempre el ultimo parche de cada rama, consultado en las webs oficiales, en su carpeta
# con la version completa (XAMPP-8.4.27; hasta la 1.36, XAMPP-8.4).
STACK_MATRIX=(
    "7.4|2.4|10.11|1.3.9|5.40"
    "8.0|2.4|10.11|1.3.9|5.40"
    "8.1|2.4|10.11|1.3.9|5.40"
    "8.2|2.4|10.11|1.3.9|5.40"
    "8.3|2.4|11.4|1.3.9|5.40"
    "8.4|2.4|11.8|1.3.9|5.42"
    "8.5|2.4|12.3|1.3.9|5.44"
)

# PHP 7.4 y 8.0 no compilan con OpenSSL 3, y PHP 7.4-8.1 no compilan con ICU 75 o posterior (exige
# C++17). Para esas ramas se compilan aparte OpenSSL 1.1.1w e ICU 72.1, estaticos (quedan dentro de PHP).
OPENSSL11_VERSION="1.1.1w"
OPENSSL11_SHA="cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8"
ICU72_SHA="a2d2d38217092a7ed56635e34467f92f976b370e20182ad325edea6681a71d68"

function needs_openssl11() { [[ "$1" == "7.4" || "$1" == "8.0" ]]; }
function needs_icu72() { [[ "$1" == "7.4" || "$1" == "8.0" || "$1" == "8.1" ]]; }

# PHP2Shell (CVE-2026-109618 y CVE-2026-109619) en las ramas que ya no tienen soporte: el equipo de
# seguridad de PHP publico un parche minimo para su ultima version (7.4.33, 8.0.30 y 8.1.34), en las
# ramas PHP-X.Y-CVE-2026-109618-109619 de php-src, pero no una version nueva (no hay 7.4.34). Va aqui
# (el diff de cada rama, en xz y base64) y se comprueba su sha256 antes de aplicarlo al compilar.
# La version queda con el mismo numero y la marca PHP2SHELL_MARK; sin ella, sigue siendo vulnerable
PHP2SHELL_MARK=xamppfiles/etc/lvm-parche-php2shell
PHP2SHELL_DATE="oct 2026"
# Primer parche de cada rama con soporte que ya lo corrige
PHP2SHELL_FIXED="8.2.35 8.3.36 8.4.27 8.5.12"
# rama|version a la que se aplica|commit de php-src|sha256 del diff
PHP2SHELL_BACKPORTS=(
    "7.4|7.4.33|712e60f9edfd03f0960fc4fc3c2c375f42b90aa2|d059c1b4ea0f9023a1e1c17f6eddee82e3c2e029c60dd0a08fc5466764b5eaa4"
    "8.0|8.0.30|82f8f31b16a035c1b67cc253e79f7cc288f4cc20|4cda6e04266d0799c546cd0d79e1161eec82810da62252c164fc19ee00571b54"
    "8.1|8.1.34|1d7dec178a094e6e75b229ce22754045f8c6070a|5bd88c386523dde98fefaa7bac97ec80f754b84cc58d6511c01dfde39ce1fbe2"
)
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
PHP2SHELL_XZ_74='
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
'
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
PHP2SHELL_XZ_80='
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
VwABsC+1tAIAm/XDQLHEZ/sCAAAAAARZWg==
'
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
PHP2SHELL_XZ_81='
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
'

# Linea de PHP2SHELL_BACKPORTS de una version de PHP (nada si no tiene parche)
function php2shell_backport() {
    local row
    for row in "${PHP2SHELL_BACKPORTS[@]}"; do
        [ "$(cut -d'|' -f2 <<< "$row")" == "$1" ] && { echo "$row"; return 0; }
    done
    return 1
}

# php2shell_diff <version> <fichero>: escribe el diff de esa version y comprueba su sha256
function php2shell_diff() {
    local row var data
    row=$(php2shell_backport "$1") || return 1
    var=PHP2SHELL_XZ_$(cut -d'|' -f1 <<< "$row" | tr -d .)
    data=${!var}
    [ -n "$data" ] || return 1
    # (xz con el python3 del sistema; si no trae lzma, con el xz de Homebrew)
    printf '%s' "$data" | /usr/bin/python3 -I -c 'import base64, lzma, sys
sys.stdout.buffer.write(lzma.decompress(base64.b64decode(sys.stdin.read())))' > "$2" 2> /dev/null \
        || printf '%s' "$data" | base64 -D 2> /dev/null | "$(brew --prefix xz 2> /dev/null)/bin/xz" -dc > "$2" 2> /dev/null \
        || { echo "  No se ha podido descomprimir el parche de seguridad de PHP $1"; return 1; }
    if [ "$(sha256_of "$2")" != "$(cut -d'|' -f4 <<< "$row")" ]; then
        echo "  El parche de seguridad de PHP $1 no coincide con su sha256. Se cancela."
        return 1
    fi
}

# Estado de una version frente a PHP2Shell: ok (corregida), parche (7.4.33, 8.0.30 o 8.1.34 con el
# parche), parcheable (de esas, sin el: se arregla actualizandola), actualizable (rama con soporte y
# un parche mas antiguo que el que lo corrige) o sin-arreglo (ramas anteriores a la 7.4).
# php2shell_state <php> [carpeta de la version]
function php2shell_state() {
    local php=$1 dir=$2 short=${1%.*} fixed
    if php2shell_backport "$php" > /dev/null; then
        [ -n "$dir" ] && [ -f "$dir/$PHP2SHELL_MARK" ] && { echo parche; return 0; }
        echo parcheable
        return 0
    fi
    case "$short" in
        7.4|8.0|8.1) echo parcheable; return 0 ;;
    esac
    for fixed in $PHP2SHELL_FIXED; do
        if [ "${fixed%.*}" == "$short" ]; then
            [ "$(printf '%s\n%s\n' "$fixed" "$php" | vsort | head -1)" == "$fixed" ] && echo ok || echo actualizable
            return 0
        fi
    done
    # (ramas mas nuevas que las de la lista: ya salieron corregidas)
    [ "$(printf '%s\n%s\n' "$short" "8.5" | vsort | tail -1)" == "$short" ] && [ "$short" != "8.5" ] && { echo ok; return 0; }
    echo sin-arreglo
}

# Firmas de lo que se descarga para compilar (ademas de su sha256): PHP, Apache y APR, MariaDB y
# phpMyAdmin publican la firma GPG de cada paquete. Se comprueba con SIG_VERIFY_PY (sin gnupg) contra
# estas claves publicas, puestas aqui (las de los responsables de publicar cada uno, sacadas de
# php.net/distributions/php-keyring.gpg, downloads.apache.org/httpd/KEYS y apr/KEYS,
# supplychain.mariadb.com/MariaDB-Server-GPG-KEY y files.phpmyadmin.net/phpmyadmin.keyring), y solo
# vale una firma buena de una de estas huellas. Si no, no se instala nada. Perl y ProFTPD no
# publican firmas (solo su sha256); OpenSSL 1.1.1w e ICU 72.1 llevan su sha256 puesto aqui
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
GPG_FPRS_PHP="1198C0117593497A5EC5C199286AF1F9897469DC 39B641343D8C104B2B146DC3F9C39DC0B9698544 5A52880781F755608BF815FC910DEB46F53EA312 E60913E4DF209907D8E30D96659A97C9CF2A795A AFD8691FDAEDF03BDF6E460563F15A9B715376CA C28D937575603EB4ABB725861C0779DC5C0A9DE4 F1F692238FBC1666E5A5CCD4199F9DFEF6FFBAFD 1729F83938DA44E27BA0F4D3DBDB397470D12172 528995BFEDFBA7191D46839EF9BA0ADA31CBD89E 2C16C765DBE54A088130F1BC4B9B5F600B55F3B4 BFDDD28642824F8118EF77909B67A5C12229118F 9D7F99A0CB8F05C8A6958D6256A97AF7600A39A6 0616E93D95AF471243E26761770426E17EBBB3DD D95C03BC702BE9515344AE3374E44BC9067701A5 49D9AF6BC72A80D6691719C8AA23F5BE9C7097D4"
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
GPG_FPRS_APACHE="65B2D44FE74BD5E3DE3AC3F082781DE46D5954FA CBA1525BAA7A47BE28FF23DDD3B13FCA2CE60BED 26F51EF9A82F4ACB43F1903ED377C9E7D1944C66 A93D62ECC3C8EA12DB220EC934EA76E6791485A8"
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
GPG_FPRS_MARIADB="177F4010FE56CA3336300305F1656F24C74CD1D8"
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
GPG_FPRS_PMA="3D06A59ECE730EB71B511C17CE752F178259BD92 63CB1DF1EF12CF2AC0EE5A329C27B31342B7511D 436FF1884B1A0C3FDCBF0D79FEFC65D181AF644A"
# (las claves, en binario y base64)
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
GPG_KEYS_PHP='
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
0x3ZzZxzzbBTQSpNFFLg2vZLYJJb5Ak=
'
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
GPG_KEYS_APACHE='
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
'
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
GPG_KEYS_MARIADB='
mQINBFb8EKsBEADwGmleOSVThrbCyCVUdCreMTKpmD5p5aPz/0jc66050MAb71HvTVcfuMqHYO8O66qXLpEdqZpuk4D+rw1oKyC+
d8uPD2PSHRqBXnR0Qf+LVTZvtO923R7pYnC2x6V6iVGpKQYFP8cwh2B1qgIa+9y/N8cQIqfD+0ghyiUjjTYek3YFBnqaL/2h2V0M
t0DkBrDK80LqEY10PAFDfJjINAW9XNHZzi2KqUx5w1z8rItokXV6fYE5ItyGMR6WVajJg5D4VCiZd0ymuQP2bGkrRbl6FH5vofVS
kahKMJeHs2lbvMvNyS3cn8vxoBvbbcwSAV1gvB1uzXXxv0kdkFZjhU1Tss4+Dak8qeEmIrC5qYycLxIdVEhTZ8N8+P7Dll+QGOZK
u9+OzhQ+byzpLFhUHKys53eXo/HrfWtw3DdP21yyb5P3QcgFscxfZHzZtFNUL6XaVnauZM2lqquUW+lMNdKKGCBJ6co4Qxjocsxf
ISyarcFj6ZR05Hf6VU3Y7AyuFZdL0SQWPv9BSu/swBOimrSiiVHbtE49Nx1x/d1wn1peYl07WRUvC10eF36ZoqEuSGmDz59mWlwB
3daIYAsAAiBwgcmN7aSB8XD4ZPUVSEZvwSm/IwuSRkpde+kIhTLjyv5bRGqU2P/Mi56dB4VFmMJaF26CiRXatxhXOAIAF9dXCwAR
AQABtC1NYXJpYURCIFNpZ25pbmcgS2V5IDxzaWduaW5nLWtleUBtYXJpYWRiLm9yZz6JAjgEEwEIACIFAlb8EKsCGwMGCwkIBwMC
BhUIAgkKCwQWAgMBAh4BAheAAAoJEPFlbyTHTNHYJZ0P/2Z2RURRkSTHLKZ/GqSvPReReeB7AI+ZrDapkpG/26xp1Yw1isCOy99p
vQ7hjTFhdZQ7xSRUiT/e27wJxR7s4G/ck5VOVjuJzGnByNLmwMjdN1ONIO9PhQAs2iF3uoIbVTxzXof2F8C0WSbKgEWbtqlCWlaa
pDpN8jKAWdsQsNMdXcdpJ2osWiacQRxLREBGjVRkAiqdjYkegQ4BZ0GtPULKjZWCUNkaat51b7O7V19nSy/T7MM7n+kqYQLMIHCF
8LGd3QQsNppRnolWVRzXMdtR2+9iI21qv6gtHcMiAg6QcKA7halLkCdIS2nWR8g7nZeZjq5XhckeNGrGX/3w/m/lwczYjMUer+qs
2ww5expZJ7qhtStalE3EtL/l7zE4RlknqwDZ0IXtxCNPu2UovCzZmdZm8UWfMSKk/3VgL8HgzYRr8fo0yj0XkckJ7snXvuhoviW2
tjm46PyHPWRKgW4iEzUrB+hiXpy3ikt4rLRg/iMqKjyfmvcE/VdmFVtsfbfRVvlaWiIWCndRTVBkAaTu8DwrGyugQsbjEcK+4E25
/SaKIJIwqfxpyBVhru21ypgEMAw1Y8KC7KntB7jzpFotE4wpv1jZKUZuy71ofr7g3/2O+7nWLrR1mncbuT6yXo316r56dfKzOxQJ
BnYFwTjXfa65yBArjQBUCPNYOKr0uQINBFb8EKsBEADDfCMsu2U1CdJhr4xp6z4J89/tMnpCQASC8DQhtZ6bWG/ksyKt2DnDQ050
XBEng+7epzHWA2UgT0liY05zZmFs1X7QeZr16B7JANq6fnHOdZB0ThS7JEYbProkMxcqAFLAZJCpZT534GpzW7qHwzjV+d13IziC
Hdi6+DD5eavYzBqY8QzjlOXbmIlY7dJUCwXTECUfirc6kH86CS8fXZTke4QYZ55VnrOomB4QGqP371kwBETnhlhi74+pvi3jW05Z
5x1tVMwuugyzzkseZp1VYmJq5SHNFZ/pnAQLE9gUDTb6UWcPBwQh9Sw+7ahSK74lJKYm3wktyvZhzAxbNyzs1M56yeFP6uFwJTBf
NByyMAa6TGUhNkxlLcYjxKbVmoAnKCVM8t41TlLv/a0ki8iQxqvphVLufksR9IpN6d3F15j6GeyVtxBEv04iv4vbuKthWytb+gjX
4bI8CAo9jGHevmtdiw/SbeKx2YBM1MF6eua37rFMooOBj4X7VfQCyS+crNsOQn8nJGahYbzUDCCgnX+pqN9iZvXisMS79wVyD5Dy
ISFDvT/5jY7IXxPibxr10P/8lfW1d72uxyI2UiZKZpyHCt4k47yMq4KQGLGuhxJ6q6O3bi2aXRuz8bLqTBLca9dmx9wZFvRh6jS/
SKEg7eFcY0xbb6RVIv1UwGDYfQARAQABiQIfBBgBCAAJBQJW/BCrAhsMAAoJEPFlbyTHTNHYEBIQAJhFTh1u34Q+5bnfiM2dAdCr
6T6w4Y1v9ePiIYdSImeseJS2yRglpLcMjW0uEA9KXiRtC/Nm/ClnqYJzCKeIaweHqH6dIgJKaXZFt1Uaia7X9tDDwqALGu97irUr
rV1Kh9IkM0J29Vid5amakrdS4mwt2uEISSnCi7pfVoEro+S7tYQ9iH6APVIwqWvcaty3cANdwKWfUQZ6a9IQ08xqzaMhMp2VzhVr
Wkq3B0j2aRoZR7BNLH2I7Z0giIM8ARjZs99aTRL+SfMEQ3sUxNLb3KWP/n1lSFbrk4HGzqUBBfczESlNc0970C6znK0H0HD11/3B
TkMuPqww+Tzex4dpMQllMEKZ3wEyd9v6ba+nj/P1FHSEy/VN6IXzd82s1lYOonKTdmXAIROcHnb0QUzwsd/mhB3jKhEDOV2ZcBTD
3yHv8m7C9G9y4hV+7yQlnPlSg3DjBp3SS5r+sOObCIy2Ad32upoXkilWa9g7GZSuhY9kyKqeEba1lgXXaQykEeqx0pexkWavNnb9
JaPrAZHDjUGcXrREmjEyXyElRoD4CrWXySe46jCuNhVVlkLGo7osefynXa/+PNjQjURtx8en7M9A1FkQuRAxE8KIZgZzYxkGl5o5
POSFCA4JUoRPDcrl/sI3fuq2dIOE/BJ2r8dV+LddiR+iukhXRwJXH8RVVEUS
'
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
GPG_KEYS_PMA='
mQINBEo4qPwBEACyTlxl0/LY2tZPBllpzIcbYyz0/Zacf0j8wSDGJvUXMWreeKfqwBY03maJQpPTewJABmF/l/oLiFLHWM5KN2Jd
4l2fyYdIAHG4E9ErCcaaXfokV0uhA1zH9fqL9lkygZ7vse/Rbp1zfvNRCSTRHQ0PIE00UA1XEzRw4aWxDUfrNG1vKDHN+g8wx9oZ
8h60655r8+nhNshhpbcxI/U60+HXoNHxQxo6sRdbxyfVkdDc8CPDOQLLmRMEcTJzzrznxM8V771UgEMbh8IHrf5VWiwgN+M/sAyC
TB8WjiHpqsmGqMtsMHtSZ9IzVPRlmgW4zTJiGLmPM318fRIg5cjPNnQLwYDFx4S8+eIOZI97EKn/GsOmnb3vaUECQHr1TXYT+Ug3
oM5maJNqcxHdg96OnVjk0kHE9/IX1Ywmmedkepn/wSFSEczIXyPzimUA6DFwlRY929v7kAudOTyHVZhJg1yO3hqiAjXN9p/ULkII
U+XN4aVnZS8/nIxzghi7qkXUxd5lnpr5uLR1pjX4Yhr6g4IH/vT8ckfMsXKnF8AiLDaG3wlAYKg1O9DoT2eqxyfhXpj9cUg7BsPT
zHBINaRfMEjCNOM3WhnsxbMCNg/1dG3mOnaTVtuYjm75Cg1vQ3sTFktWLbG98hmL0ugQ+m51H8gRyqIRA9Ri7miM0VZokYQO6wAR
AQABtCFNaWNoYWwgxIxpaGHFmSA8bWljaGFsQGNpaGFyLmNvbT6JAjoEEwEIACQCGwMFCwkIBwMFFQoJCAsFFgIDAQACHgECF4AF
Ako45+gCGQEACgkQnCezE0K3UR236Q/6A0g1A64lc6bkfIpcW9KB6HlIID6IWLcidvgC5updbW3DU5PgOkTNT+ywPAHvn0lqp7tN
acDLI9gmHcz5hb3k5BEWaz33Yszx6zBiDLLXxj8NIHR9HJp/jtRlmfPyaP4isS6vnbRRRuokO8IRviIlKV0RV4V6xP0PP5fIIiTm
WyatS2lO4ij5Oudao/a4SA6ikKwOkXFX8Y7Jfx1YgSUmNNtWmGNTqHFposhMCPoaxVDny3/qYLWi0MeGlKamldCsi8W/HZxhds27
L9rNaG3Q9/JnAJIt7GzQnV6XqZ4RsoqOAH77ZfkvlKHTFKljo4QTqWrkWukD2KhlNJ5WDLmsO1AHIJmxy/djngadNU29X+qHSgVB
2gEX/pZYY59MboU3W2qN8G5KrS7tjrMN/A/PWALkXy9hPRy45UO/Cke9WJ7hPmZ6rW/BOYbGRdBuvqDzVj04pRbNvw8lCytHEPxs
vPxMWgk2e3QCIIVlxNfVxqhHt0mdXt4HjXmchsol8UixmGRUGkmyVmzVvEapPTcC14YwM0EFAUIoMKoROgUECebbG79TFPTST+9Z
fow6uypOgQTZHfXUyni8wQ/THRGrNMywTP9yuVHe0cZQHGIZERS1dUZa1Bd9vwJv7qvQsvPK+Lu0wisMOuklWb0Nl9K/cKp5HiFP
VlLSOqSsEa+qy620LE1pY2hhbCDEjGloYcWZIDxuaWplbEB1c2Vycy5zb3VyY2Vmb3JnZS5uZXQ+iQI3BBMBCAAhBQJKOOdOAhsD
BQsJCAcDBRUKCQgLBRYCAwEAAh4BAheAAAoJEJwnsxNCt1EdRR0P/2OXjW/8Z59jDjvbYe8hBneurFh033yRDBZTsaeOVOQQtHug
CYGD5vik7/1L18oNnUjQjWnyvPkPbDU+FgKPJhb9F77Hlxa+qf8MafceucK5t586a2IY0JzgY/OshA70cG8MAePm/5ZzLf8xfcMN
Bqq1vzqCSXBcjz2MtTXDndnJo1vAwTXzrwToUBKPQdsPXprbtFye110ZE5L/b+8Z27GTShzKXK8AH8EMPUl0Vpqh+X+8qpc5W/GG
6zYWG+Y/Ea2BI7WuGUhYwbU7+4Rt9FddI+5unZStdpQ4AznVJHVHSVbnjgDDrVnAMO79gj5kmY7I9b9D4l+P7DiE03EN9fOocm6a
oAj/YuF1Ovp8ry4TYgWaBvnO5c5m5rcwnsoUdc9DR6eNo11AfM0X4TpUznJqOwHNPUUs9lnDFjxshFVANDl9tY6cBcBb1Nn0e+11
ZQO+OIW2ouzpaFZEVys+amx7fAhLoF1CqNMftfW4fbnaxbMKJz+3reVRaI+gLnkVbtl2j/mc+lvBCFLxF8WKaEzqqCVV4tSOu94y
6w7e0NccDeMQ/JFBS8DcCIpQliRsIczXOHVadGzhIlst/lGIpbGzPbEEfqV3qdo+o5tkewuY6hHu5JTwICIw+nlZzlEiosccor2r
iiUvXlfskvUvcP4Z4rAvYO+dWiBK3Yie+C9ztCFNaWNoYWwgxIxpaGHFmSA8bmlqZWxAZGViaWFuLm9yZz6JAjcEEwEIACEFAko4
5wkCGwMFCwkIBwMFFQoJCAsFFgIDAQACHgECF4AACgkQnCezE0K3UR27TRAAkyq56M3V7H9Og/hXLUziCSw1QOyZfSJs2IsBNF9z
triZDYMO7Yx6VWAc6F+lQ7eJZlBQI0C+Q4GXbEr4GCA9UZblwwllHRfoNUgLNXpjXl7DEzH3J8kOH7XX7ZY5Dlc62hLgZhFEQ4Wj
sm+mTArEs2typweQ7VNPvZCpySzSfsypQQj04H9ATxfL3W+wMkjqGSdJaXQ4u7DYFtwOf2Ye956/8DOv0hNGEGrgdPBKj5qfmVFs
8oMoOClpIczSLZnTyThKEzMP1cXYi1XaTAL7bXKfLZaflKv56HJru2KF7F/TV9Dg9Op5GDGQjNbIrP2NzFikwviuVtKisIsj4K9g
1DPBRothdbvDGBDezqzP5ud/slQ9X1XbQ+8xQJOHcoMF/m/FkBrBbSkH9MuQAup7PzTAa3OREGMPP8nfG+m90SLbS5sDs5lY5sxb
4uVovVBSTjnJtImtz8Pzg8ZM+s4gqyoXA6YmaLDB8hbnuExw1DAAkA1T+F9tp+wRPxB4eIYZLk84ACr/CRevPqShS+GxzXqSOZ1D
yetcfc+gKiOCxxJGWBcGJ66FE2Dop9VOYHTUWzL5OGTZklJLyzEowVXLVlsxOASs+p2D7ZObStuqLFlVaMNlS+9RhjezLR9RDORX
tMvtQ1jRsJle0qUhtbHTvpaHy49hv8Zwh4qrTfDZfoq0H01pY2hhbCDEjGloYcWZIDxtY2loYXJAc3VzZS5jej6JAjcEEwEIACEF
Ako45yYCGwMFCwkIBwMFFQoJCAsFFgIDAQACHgECF4AACgkQnCezE0K3UR0u9w//dkFCjSTs1T831uVaeJqIJ4+wcc0liIvU9tHQ
EEq/qLVUCnDqjHelrh/u21YNDt/iAnpynlhPpQ9QHgw/pwMj07vZkJQqe1wE6cnVm6ImSvLANSRHOPEOvl2u51hHQRbubvGbOQB3
62fAsPvkJsi2ivdz5dpo3XxMKKI1z4qgTTZfE8IboDfOR2KoqlQ3UGIIARV8pSNT+grcvw3O302BdgK5zbioXisHu8BpJZsgi97N
sW4fjaeAUwTh5f/r0oRQBD9vXr7AGS0F0xFYXHNAZacs5cwTLdpAwTalJqX1Ts9F0hGdILnUc+zrB98pkBmDG1Jv0fMSuqZIlHmX
jct0wPLKLRBmE+QIpsLefzzdP7ZkWqtvksH33fZjR7uN9sk+UTdJYwWe3lOQJu2zfpPInNGOvCOHtBBeWpq1MYn5+KBxKuN03Sux
2pT3h2BWfTUTvav+L5Pkoq8euUTp1e9MRCupmwP41/HHkcvCDwbHcT4TXIfGIRWQa8Qj+6qcil2ZlBc27MXy/NTXslZkuIw5oVwv
6x4ViQob2QduzulEAFGPsulllWgnDrLu7UT+xu+LHllqXQQ7GuGFSPzGKON4+2W8q3RkAeGS9qCjyG4WsJe2bkZ53Ekfyc24Pszu
mwNkMKB7SQUiJxZqyXRgLVKvWy5TQM1x136aXgIse5/GmuW0Ik1pY2hhbCDEjGloYcWZIDxtY2loYXJAbm92ZWxsLmNvbT6JAjcE
EwEIACEFAko45zICGwMFCwkIBwMFFQoJCAsFFgIDAQACHgECF4AACgkQnCezE0K3UR1pUw/+O0Mt9ElVSjZ+GGLFTLz4LPNo7P4b
NyyzfJ0zrizNnd8MKRRRnXfxjsikyPhD8LJiegxPscy9cMcTYurJ0hhFjdX9TWEn44TZqeJnhY8/zYpUKJ/h63FFVzkD3RZZ+cnB
c9cKk7OZDm+PaGq4nXP6iAyE4CSWV/VJKfTGtcfe1LGs3hc7iOlUfkXa9cyXg1YcGtN/7rEdhgJyGPepWZ8gWvXYo0IJ4g2NiE80
N7++3NCs4ZSOlPYuFtoEbZ/DXhwbnNh4co5JDGdvpGzjkVSZ8Z5X1PwOH/O2FbVJy/K3a+g/5tmtprg9301yBzIuXgR+HDFowug/
gR36XAgPaIObQj50TdP4+TCQmZQHUj0qi1iqlQpx0cflPKIMbSviplaNyk1liQWxFHy5vyzPUCyKEexM016864VVt4m3v7V6JnVT
gYDfNy82Lj0vtyKreRDnwvEvf0SVUCuhUbpZycU9KKpKWm1ZNa0PBvaB9jECg8eX7yISmp66wb8MEELonXr7PDGPBrvRIQRtv34f
dTbiTyL9+GFzhCqD8RWPJKHofw6xDDSZfoDRdDHWTdLPSmKOnUPazRLz0v/HRqLnazF30OAsLOOz4vwmP5Kj1ejEFftRZCkOLlep
p2FTcRFBY94WS4ZSzGE3/zuOIfqfAjcdK/n1EOT5Ix4uKKZeL50dVgPR/wAAIqb/AAAioQEQAAEBAAAAAAAAAAAAAAAA/9j/4AAQ
SkZJRgABAQEASABIAAD//gA7Q1JFQVRPUjogZ2QtanBlZyB2MS4wICh1c2luZyBJSkcgSlBFRyB2NjIpLCBxdWFsaXR5ID0gODUK
/9sAQwAIBgYHBgUIBwcHCQkICgwUDQwLCwwZEhMPFB0aHx4dGhwcICQuJyAiLCMcHCg3KSwwMTQ0NB8nOT04MjwuMzQy/9sAQwEJ
CQkMCwwYDQ0YMiEcITIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIy/8AAEQgBCgDIAwEi
AAIRAQMRAf/EABsAAAEFAQEAAAAAAAAAAAAAAAQAAgMFBgEH/8QAOBABAAEDAgUCBAUCBAcBAAAAAQIAAxEEIQUSMUFRYXEGEyKB
FDKRobEH0RUjUsEzNEJDYnLw4f/EABkBAAMBAQEAAAAAAAAAAAAAAAECAwQABf/EACIRAAICAgICAwEBAAAAAAAAAAABAhEDIRIx
QVEEEyIUYf/aAAwDAQACEQMRAD8A8oNUJhDNTRvxyOf3oOWi1EMrbl/NNlbmH1RTbxU6Oasso6i0mM7085J4cDt4qoGQYxvUkLso
xEUKFMDRcWbcYXY3YASOlWJrrzgYEvas1DVXDck0Rb4jcI7u9BpvsDTNCauey2ZI+K7O5DUhHlRHKJiqSHFZGMkj2at+F6iOtlPq
8pvmlkqVoME+QZbuWoW4RZwEMBmo9ZbLvyURByYqjvx5NZKF7IMnlmO3s+KudPalDhgklYZRzvQt0mwwX6YVjHpSkC7tUrxa+byn
J27g1W67X6lkTWUXsilFb0I07NYxO1N5HNZ3gvFb93Vlm9NnGRgXqNaYMlc006BVEfK5riKpUwb0kHKGN+ldZxAqFQ3dPYvH+ZZt
y9WJmipBh2pvL6da6zk6K2fCNFLKW5QX/RJP2oefBIZWF6R4JA1ccm9c5O9dSfgpHLKPTKCfBtQZYyhMPDhoeeg1UOtmSemGtORZ
KAr6b1wij0c0OCfgqvlTXezJyhOD9UZR9xKbj7+1a9iJ9QPuVBPRaabmVmD64xSPGvBWPzPaMvnHUSlWhnwjSy3iSg+R/vSofWyn
9cRn4bVhjkz7NNbN6B9VlT2zVzNOXA4qt196VuG0v3xWx6PPTsBlCyuJ2gfbFMdJpZmDJ6FG2tFqp2S7O3LEtxSunDr8hSzJx1wU
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
fHifDrullLlZH0y8Pb+a8k1eku6LVXNNeixuW3lT27/evYyTLo+1Zj4z4F+L0zxHTxW9ZjiYH5o+fVKyTi1s2wlao8+OhUsTpUQ9
DCYqSCLUWMkTQOhSrsHb1pUox7NnKj1rimE3Hx5psfzu9Pxkzk/SvQS0edLsEvQLhySMxkInketeD/E3CJ8G47qNMiQJc0HHWLuP
6V75I/zB8VjP6icBlxLhZxCzDN/SjzAZZQ7/AHOvtmg0Vxyp0zJfBvERtz0c5bxeaOfD1K2Aib15JotVc0Gshegowcp0yeK9N4dr
7Wt0sLsJCSB2e/isObHTtHpYZ2qYZMWK9qhQcj0qWT9KZ3ai2z3qKRYFu2t9wTNDz0+VkR3qwkCqg1HLbdo0GysnphM8m7Ql3SgK
Bnvmri5LBsUJKHOmcdelDyGkwSzpI7y3ANs9qynEbjxbjluxBzajMt2w7qmX/wC8FaL4g4iaDQtqDi9dGMQeh3arfgjhzq+OxvzF
t6aLcV/1O0T9VftWz42Nt2zJ8rLxVI9H01iFvW2bFuIRtxAD0MVc3FwG2KreHHPq71zw4PtVlPKFelLtI8aPTfsbE/SmX8PKHmpo
nTNRTMzO3alQeh2BjA7BmptNJbHupUF15bcnvjBU9sIQtmMYDPvXSWjk9hsZELY+dqnjEnaYyBJGEe5QVybiAPVxR1o+wGKzTijV
ils8n+LdLpvh7irCenvNi8Mrc4Jjrue5VGcZ4dJeS1eMdOZN69d+KuAW/iLg1zSnLG+fVZmmxI7Po9K8st/A3F4MjGiyZNr44fG+
GsU4JOzWpNrSA3jdmdyDCwwjKWMMs49aVFW/gbi0rluN2NiMGX1ML8VDvjLvSpbivIKl6PbI45mnS3Kbvl2p3UK9FdnnvoiTEt3d
702QSZQkZimEeieKdNB3a5JwEsZonXR4v8afDcuC8SlctRXSXllbQ2HuPtVRwfjN3hd/EllZk/VE7Pkr27i3DtNxXRT0uqgShI2T
ZHsnhrxn4j+GNXwO+ylFuaZfpuhtjsPhpZQTVM1Y8vSNvpdfa1dgu2pkoyOzU+SvLtBxTU8Ouc1qSxzvFdn+1avQfFWlvBG6tqfc
l0+zWSeBp6NkMy6ZpVPFRzxnfeg48TsXAY3Yo+GuT19gFbkT3ai4taoqmnuyW452KH1Wos6DTTv3pARM+q9g9+lBan4g0GkipP5t
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
'

# Solo para probar el instalador sin sudo: LVM_PRUEBA=/ruta instala las pilas en /ruta/XAMPP-X.Y
# con puertos altos y sin tocar /Applications
TEST_DIR=${LVM_PRUEBA:-}
# Las variables de prueba solo valen con LVM_PRUEBA: si no, una variable de tu sesion (que puede
# poner cualquier programa tuyo) cambiaria que ficheros toca el gestor con sudo
if [ -z "$TEST_DIR" ]; then
    unset LVM_HTDOCS LVM_VHOSTS LVM_VHOSTS_ACTIVO LVM_SSL_CERTS LVM_SSL_KEYS LVM_HOSTS LVM_BD_CLIENTE \
        LVM_BD_VOLCADO LVM_ENLACE LVM_PS LVM_PRUEBA_CAS LVM_PRUEBA_CLAVES LVM_PRUEBA_SSL LVM_DOCKER LVM_DOCKER_DIR \
        LVM_DOCKER_HOST LVM_MAILPIT_URL LVM_MAILPIT_SHA LVM_CLOUDFLARED_URL LVM_CLOUDFLARED_SHA LVM_LOOPBACK_PLIST \
        LVM_LO0_FILE LVM_DNS_SCRIPT LVM_DNS_PLIST LVM_DNS_RESOLVER
fi
# Las versiones (XAMPP-X.Y.Z) y XAMPP-compartido van en /Library/Nexum, de root: en /Applications
# puede escribir el grupo admin (tu usuario), y un programa tuyo podria cambiar una carpeta por otra
# entre que el gestor la comprueba y root la usa. En /Applications quedan el enlace a la version
# activa (/Applications/XAMPP, como en XAMPP), el XAMPP oficial y, de las versiones de antes de la
# 1.39.3, enlaces para lo tuyo que use sus rutas viejas (root no pasa nunca por ellos)
if [ -n "$TEST_DIR" ]; then
    SUDO="" PORT_HTTP=8080 PORT_HTTPS=8443 PORT_MYSQL=3307 PORT_FTP=2121
    BASE_DIR=$TEST_DIR
    APPS_DIR=$TEST_DIR
else
    SUDO=sudo PORT_HTTP=80 PORT_HTTPS=443 PORT_MYSQL=3306 PORT_FTP=21
    BASE_DIR=/Library/Nexum
    APPS_DIR=/Applications
fi
# Donde estaban las versiones hasta la 1.39.2 (lvm-instalador migrar las pasa a BASE_DIR)
LEGACY_DIR=/Applications

# /Applications/XAMPP: enlace a la version activa. XAMPP-compartido: htdocs y vhosts de todas.
LINK=$APPS_DIR/XAMPP
COMMON=$BASE_DIR/XAMPP-compartido
# Cache de descargas de las pilas propias (de root; descargas_cache.sh)
DL_CACHE_DIR=$BASE_DIR/descargas
# Proyectos y vhosts compartidos (LVM_HTDOCS/LVM_VHOSTS solo para pruebas)
HTDOCS_DIR=${LVM_HTDOCS:-$COMMON/htdocs}
VHOSTS_FILE=${LVM_VHOSTS:-$COMMON/httpd-vhosts.conf}
PROJECTS_FILE="$HOME/.lvm-instalador/proyectos"
# Vhost que se crea para cargar proyectos si no hay ninguno (LVM_HOSTS solo para pruebas)
PROJECT_VHOST=web.local
HOSTS_FILE=${LVM_HOSTS:-/etc/hosts}
# Fichero de vhosts que se edita desde la ventana: el real de XAMPP-compartido, el mismo que usa
# cargar-proyecto (el de xamppfiles/etc/extra es un enlace a el a traves de /Applications/XAMPP,
# que no existe si no hay version activa). LVM_VHOSTS_ACTIVO solo para pruebas
ACTIVE_VHOSTS=${LVM_VHOSTS_ACTIVO:-$VHOSTS_FILE}

DRY=0
PROGRESS=""

# Firma del panel principal
SIGNATURE="By M.Mascuñano"

# Version del instalador: sale debajo de la firma y en "Acerca de", con la lista de cambios
APP_VERSION="1.57.9"

# Actualizaciones: las publicaciones (Releases) del repositorio de GitHub. Las que traen la version
# de Mac llevan lvm-instalador-mac-<version>.zip y su firma (.zip.sig), hecha con la clave de
# UPDATE_KEY_FPR (la misma que la de los paquetes de Linux); su parte publica va aqui
UPDATE_REPO="mariomasku/nexum-stack"
UPDATE_KEY_FPR="3506F1EB091AD4A23F40081FF24FD5CC07557404"
UPDATE_KEY_B64='
mDMEatoqkhYJKwYBBAHaRw8BAQdAxAut0to4730sesIdm2rZyf1OW711qSJX0I1R05RzfS+0M05l
eHVtIFN0YWNrIC0gZmlybWEgZGUgcGFxdWV0ZXMgPHNvcG9ydGVAaGV4ZXIuZGV2PoiTBBMWCgA7
FiEENQbx6wka1KI/QAgf8k/VzAdVdAQFAmraKpICGwMFCwkIBwICIgIGFQoJCAsCBBYCAwECHgcC
F4AACgkQ8k/VzAdVdARhwgD+PjUtI6Bn7GLlySuGZHPldPSF2YKPk32jWFsUZXRtHLIBAPO+uAx+
lARQvnHUnZRmG9VdnoUuRq5Phb/RhBOXrqIA
'

# Logo de hexer abajo a la izquierda, fuera de las ventanas: '#' en blanco y '/' en verde #45A57C
LOGO=(
    "##  //"
    " ##//"
    "  ##"
    " ####"
    "##  ##"
)

