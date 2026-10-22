#!/bin/bash

# lvm-instalador - Nexum Stack: gestor e instalador de versiones LAMPP y PHP para Linux en un solo archivo.
#
# Gestiona varias instalaciones de LAMPP en /opt/lampp-<version>, de las que solo una
# esta activa (/opt/lampp es un enlace a ella). Puede instalar:
#   - Versiones completas de XAMPP (Apache, PHP, MariaDB, ProFTPD, Perl, phpMyAdmin),
#     descargadas de SourceForge, para proyectos antiguos (PHP 7.x y 8.1).
#   - Versiones nuevas de PHP (php.net) con su pila propia, sin XAMPP: Apache, PHP (PHP-FPM),
#     Perl y ProFTPD compilados y MariaDB oficial, todo dentro de /opt/lampp-X.Y. Cada rama de
#     PHP lleva componentes mas modernos y compatibles entre si (STACK_MATRIX), y sus propias
#     bases de datos (vacias al instalar).
# No instala PHP ni MariaDB en el sistema: cada version solo funciona cuando esta activa.
#
# COMANDOS: lvm-instalador <comando> [opciones]
#
# Cada comando va en su linea, con lo que hace debajo. <...> es un dato obligatorio y [...]
# uno opcional; a | b son alternativas.
#
#
# === VENTANA Y PANEL =========================================================================
#
#   lvm-instalador
#       Sin comando: abre la ventana (desde el menu) o el panel en la terminal
#
#   lvm-instalador ventana
#       Ventana grafica (la abre el acceso del menu)
#
#   lvm-instalador instalador
#       Panel de la terminal, directo a la lista para instalar
#
#   lvm-instalador --simular <comando>
#       Delante de cualquier comando: muestra lo que haria sin cambiar nada (tambien sin
#       comando: el panel en simulacion)
#
#
# === VERSIONES DE LAMPP ======================================================================
#
#   lvm-instalador list
#       Versiones instaladas (/opt/lampp-<version>)
#
#   lvm-instalador estado
#       Version activa, si esta en marcha y lo que tiene cada una
#
#   lvm-instalador use <version>
#       Monta una version: para la actual, cierra lo que quede en memoria y arranca la nueva
#       (ej.: use 8.4)
#
#   lvm-instalador arrancar | parar | reiniciar
#       La version montada. Parar no deja ningun proceso en memoria
#
#   lvm-instalador disable
#       Para la version montada y la desmonta (quita /opt/lampp)
#
#   lvm-instalador procesos
#       Procesos de LAMPP en memoria y de que version es cada uno
#
#   lvm-instalador cerrar-procesos [--todos]
#       Cierra los que no son de la version montada (--todos: todos)
#
#
# === INSTALAR, ACTUALIZAR Y DESINSTALAR ======================================================
#
#   lvm-instalador instalar [--xampp 8.2.4,8.1] [--php 7.4,8.4,8.3.10] [--si]
#       Instala sin preguntas. 8.4 = ultimo parche de la rama en lampp-8.4; 8.3.10 = ese
#       parche en lampp-8.3.10; --si confirma
#
#   lvm-instalador add-php <version>
#       Instala una version de PHP con su pila propia
#
#   lvm-instalador add-xampp <version>
#       Instala un XAMPP oficial (7.1.33, 7.4, 8.1 u 8.2.4)
#
#   lvm-instalador actualizar <version>
#       Vuelve a compilar una version con la ultima pila de su rama (las basadas en XAMPP
#       pasan a pila propia)
#
#   lvm-instalador desinstalar <version> [--copia]
#       Borra una version (no la activa ni una cuyas bases usen otras); --copia guarda antes
#       sus bases en ~/lvm-copias
#
#   lvm-instalador add <nombre>
#       Registra como version un XAMPP instalado a mano en /opt/lampp (activa los vhosts,
#       Apache con tu usuario y htdocs tuyo)
#
#
# === BASES DE DATOS ==========================================================================
#
#   (en la version montada y en marcha; si root tiene contraseña: MYSQL_PWD=...)
#
#   lvm-instalador list-db
#       Bases de datos de cada version
#
#   lvm-instalador crear-bd <base>
#       Crea una base vacia (utf8mb4_general_ci)
#
#   lvm-instalador importar-bd <fichero> <base> [--crear] [--sin-copia] [--proyecto <carpeta>]
#       Carga un .sql, .sql.gz o .zip; --crear crea la base si no existe. Si ya existe, antes se
#       borran todas sus tablas (con una copia en ~/lvm-copias si tenia alguna; --sin-copia, sin
#       ella); --proyecto la deja como base de esa carpeta: WordPress, rehace su wp-config.php
#       con la plantilla; PrestaShop, su parameters.php pasa a usarla
#
#   lvm-instalador exportar-bd <base> <fichero.zip|.sql|.sql.gz> [version]
#       Descarga una copia de una base (sin version, de la montada)
#
#   lvm-instalador copiar-bd <base> <origen> <destino> [--sustituir]
#       Copia una BBDD a otra version (para probar el proyecto con otro PHP); la de origen no se
#       toca. Si la de destino ya la tiene, solo con --sustituir: antes guarda una copia suya en
#       ~/lvm-copias
#
#   lvm-instalador borrar-bd <base> [--copia]
#       Borra una base; --copia guarda antes una copia en ~/lvm-copias
#
#
# === PROYECTOS Y DOMINIOS ====================================================================
#
#   lvm-instalador cargar-proyecto <carpeta> [version] [base]
#       Apunta web.local a /opt/htdocs/<carpeta> (y monta antes esa version). Tienda
#       PrestaShop o proyecto nuevo: crea lo que falte de su vhost y su certificado y falsea
#       su dominio en /etc/hosts; los demas dominios dejan de estar falseados. Tienda sin base
#       en app/config/parameters.php (recien clonada): lo crea con la base (la indicada, la
#       recordada o ps_<final de la carpeta>); la primera vez vacia su var/cache. Si su
#       configuracion usa otra base (codigo de produccion volcado encima), vuelve a la de la
#       carpeta
#
#   lvm-instalador montar-proyecto <url de git> <carpeta> <version> <base> [volcado]
#       Proyecto nuevo desde GitHub (u otro repositorio): lo clona en /opt/htdocs/<carpeta>
#       con tu usuario (solo https o ssh, sin submodulos), lo carga en esa version, crea su
#       base y, si se indica, carga en ella el volcado (.sql, .sql.gz o .zip) con la carga
#       protegida
#
#   lvm-instalador desmontar-proyecto
#       web.local deja de apuntar al proyecto cargado y enseña una pagina vacia; los dominios
#       falseados de una tienda PrestaShop dejan de estarlo
#
#   lvm-instalador usuario-pruebas <base> [carpeta]
#       Crea o deja al dia el administrador de pruebas del panel (WordPress o PrestaShop):
#       local@local.test con contraseña local. Se hace solo al cargar una BBDD
#
#   lvm-instalador wp-config <carpeta> [base]
#       WordPress: comprueba que wp-config.php usa la base de la carpeta (la indicada o la
#       recordada) y entra en el MariaDB local; si no (codigo de produccion pegado encima), lo
#       rehace con la plantilla de este equipo, con WP_SITEURL y WP_HOME en la direccion
#       local. Cargar proyecto lo hace solo
#
#   lvm-instalador vaciar-cache <carpeta> | --bd <base>
#       Vacia var/cache de una tienda PrestaShop (por carpeta o base)
#
#   lvm-instalador nuevo-dominio <dominio> <carpeta> [base]
#       Proyecto nuevo con su dominio de produccion falseado: carpeta (la usa si existe),
#       vhost con certificado, base vacia con ese nombre en la version montada (si no existe)
#
#   lvm-instalador hosts-falsear <dominio> si|no
#       Falsea (127.0.0.1) o deja de falsear el dominio de un vhost
#
#   lvm-instalador vhosts
#       Edita una copia de los vhosts y la aplica con sudo: se comprueba antes, se guarda el
#       anterior en ~/lvm-copias y se recarga Apache
#
#   lvm-instalador hosts
#       Edita /etc/hosts (con sudoedit)
#
#
# === SERVICIOS Y SEGURIDAD ===================================================================
#
#   lvm-instalador servicio apache|mariadb|ftp arrancar|parar|reiniciar
#       Un servicio de la version montada. El FTP no arranca con la version: se activa asi (o
#       en la pestaña Servicios) y sigue activo hasta que se pare
#
#   lvm-instalador asegurar [version]
#       Deja Apache, MariaDB y el FTP solo para este equipo (no se puede entrar desde la red)
#       y los vhosts del administrador. Se hace solo al montar o arrancar una version
#
#   lvm-instalador arreglar-certificados
#       Los vhosts https con certificados en los que confia todo el equipo (en /etc/ssl/certs,
#       de CA o de una CA local sin limite de dominios) pasan a uno propio, y esa CA deja de
#       ser de confianza
#
#   lvm-instalador confiar-certificados [dominio|--quitar]
#       Chrome, Chromium y Firefox aceptan sin aviso el certificado propio de cada proyecto
#       https (o solo el de ese dominio): solo ese certificado, no una CA. Sin el aviso, las
#       herramientas que manejan el navegador (Claude in Chrome) pueden abrir los proyectos.
#       Los de una tienda con dominio real, solo mientras este falseada en /etc/hosts: al
#       dejar de falsearla, el navegador deja de aceptarlo (se hace solo al cambiar hosts).
#       --quitar: solo deja de aceptar los que ya no deberia
#
#
# === INFORMACION =============================================================================
#
#   lvm-instalador version | acerca | novedades
#       Version del programa / que hace / lista de cambios
#
#   lvm-instalador --ayuda
#       Esta ayuda
#
# Variables opcionales: PHP_TIMEZONE (por defecto Europe/Madrid), LVM_UI=text (panel sin ventanas)

set -o pipefail
# Los rangos de las expresiones ([A-Za-z0-9]) siguen el orden del idioma: con es_ES aceptarian letras
# con tilde, ², ½... en carpetas, bases y dominios. En orden C, solo ASCII. (LC_ALL manda sobre
# LC_COLLATE: si esta puesto, pasa a LANG)
[ -n "${LC_ALL:-}" ] && export LANG=$LC_ALL && unset LC_ALL
export LC_COLLATE=C

SELF=$(readlink -f "$0")
LOG_DIR="$HOME/.lvm-instalador"
# Solo tuya: lleva registros, copias de los vhosts y configuraciones con contraseñas
[ -d "$LOG_DIR" ] && [ ! -L "$LOG_DIR" ] && [ -O "$LOG_DIR" ] && chmod 700 "$LOG_DIR" 2> /dev/null
# Las copias (BBDD de clientes, vhosts, /etc/hosts anteriores), igual: solo tuyas, aunque la carpeta
# ya existiera con otros permisos
[ -d "$HOME/lvm-copias" ] && [ ! -L "$HOME/lvm-copias" ] && [ -O "$HOME/lvm-copias" ] \
    && chmod 700 "$HOME/lvm-copias" 2> /dev/null
LOG="$LOG_DIR/instalacion-$(date +%Y%m%d-%H%M%S).log"
PHP_TIMEZONE=${PHP_TIMEZONE:-Europe/Madrid}
# Va al php.ini de cada pila (y lo lee el maestro de PHP-FPM, que es root): solo un nombre de zona
# horaria, sin saltos de linea que metan otras directivas (extension=...)
if ! [[ "$PHP_TIMEZONE" =~ ^[A-Za-z][A-Za-z0-9_+/-]{0,63}$ ]]; then
    echo "PHP_TIMEZONE no es una zona horaria valida: se usa Europe/Madrid" >&2
    PHP_TIMEZONE=Europe/Madrid
fi
PMA_VERSION="5.2.3"
SPACE_XAMPP_GB=2
SPACE_STACK_GB=5

# Solo librerias para compilar (nunca PHP, Apache ni MariaDB del sistema)
STACK_BUILD_DEPS="build-essential pkg-config libxml2-dev libssl-dev libsqlite3-dev zlib1g-dev libcurl4-openssl-dev libonig-dev libzip-dev libpng-dev libjpeg-dev libfreetype-dev libwebp-dev libicu-dev libsodium-dev libargon2-dev libreadline-dev libpcre2-dev libexpat1-dev libnghttp2-dev libbrotli-dev patchelf"
XAMPP_DEPS="net-tools"
# Solo en equipos que no son x86_64 (ARM...): MariaDB no publica binarios y se compila
MARIADB_BUILD_DEPS="cmake bison libncurses-dev liblz4-dev libzstd-dev"

# MariaDB y XAMPP solo publican binarios para x86_64. En el resto (ARM, como una maquina virtual
# en un Mac con Apple Silicon) MariaDB se compila desde el codigo fuente y no se ofrece XAMPP.
function native_binaries() {
    [ "$(uname -m)" == "x86_64" ]
}

# Pila propia de cada rama de PHP: rama PHP|Apache|MariaDB|ProFTPD|Perl
# Cada rama nueva sube un escalon (MariaDB LTS y Perl mas modernos), para que los proyectos
# evolucionen con todo compatible entre si. Apache y ProFTPD solo tienen una rama estable.
# Las ramas sin soporte de php.net (7.4-8.1) son para proyectos antiguos y usan la pila de 8.2.
# Se instala el ultimo parche de cada rama (en /opt/lampp-X.Y) o uno concreto (en /opt/lampp-X.Y.Z).
# Los componentes son siempre los ultimos parches de su rama, consultados en las webs oficiales.
STACK_MATRIX=(
    "7.4|2.4|10.11|1.3.9|5.40"
    "8.0|2.4|10.11|1.3.9|5.40"
    "8.1|2.4|10.11|1.3.9|5.40"
    "8.2|2.4|10.11|1.3.9|5.40"
    "8.3|2.4|11.4|1.3.9|5.40"
    "8.4|2.4|11.8|1.3.9|5.42"
    "8.5|2.4|12.3|1.3.9|5.44"
)

# PHP 7.4 y 8.0 no funcionan con OpenSSL 3: llevan OpenSSL 1.1.1w compartido en /opt/lampp-X.Y/openssl
# (compartido y no estatico, para que sus simbolos no se mezclen con los del OpenSSL 3 que usa libcurl).
# PHP 7.4-8.1 no compilan con ICU 75 o posterior (exige C++17): llevan ICU 72.1 estatico.
OPENSSL11_VERSION="1.1.1w"
OPENSSL11_SHA="cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8"
ICU72_SHA="a2d2d38217092a7ed56635e34467f92f976b370e20182ad325edea6681a71d68"

function needs_openssl11() { [[ "$1" == "7.4" || "$1" == "8.0" ]]; }
function needs_icu72() { [[ "$1" == "7.4" || "$1" == "8.0" || "$1" == "8.1" ]]; }

# Solo para probar el instalador sin sudo: LVM_PRUEBA=/ruta instala las pilas en /ruta/lampp-X.Y
# con puertos altos y sin tocar /opt/lampp, /opt/htdocs, /opt/config ni apt
TEST_DIR=${LVM_PRUEBA:-}
# Las variables de prueba solo valen con LVM_PRUEBA: si no, una variable de tu sesion (que puede
# poner cualquier programa tuyo) cambiaria que ficheros toca el gestor con sudo
if [ -z "$TEST_DIR" ]; then
    unset LVM_HTDOCS LVM_VHOSTS LVM_VHOSTS_ACTIVO LVM_SSL_CERTS LVM_SSL_KEYS LVM_HOSTS LVM_BD_CLIENTE \
        LVM_BD_VOLCADO LVM_ENLACE LVM_PS LVM_PRUEBA_CAS LVM_PRUEBA_CLAVES LVM_PRUEBA_SSL
fi
# Proyectos y vhosts compartidos por todas las versiones (LVM_HTDOCS/LVM_VHOSTS solo para pruebas)
HTDOCS_DIR=${LVM_HTDOCS:-/opt/htdocs}
VHOSTS_FILE=${LVM_VHOSTS:-/opt/config/httpd-vhosts.conf}
PROJECTS_FILE="$HOME/.lvm-instalador/proyectos"
# Vhost que se crea para cargar proyectos si no hay ninguno (LVM_HOSTS solo para pruebas)
PROJECT_VHOST=web.local
HOSTS_FILE=${LVM_HOSTS:-/etc/hosts}
# Fichero de vhosts de la version activa, el que se edita desde la ventana (LVM_VHOSTS_ACTIVO solo para pruebas)
ACTIVE_VHOSTS=${LVM_VHOSTS_ACTIVO:-/opt/lampp/etc/extra/httpd-vhosts.conf}
if [ -n "$TEST_DIR" ]; then
    SUDO="" PORT_HTTP=8080 PORT_HTTPS=8443 PORT_MYSQL=3307 PORT_FTP=2121
else
    SUDO=sudo PORT_HTTP=80 PORT_HTTPS=443 PORT_MYSQL=3306 PORT_FTP=21
fi

# Versiones de XAMPP disponibles
# carpeta|release|PHP|Apache|MariaDB|ProFTPD|Perl|phpMyAdmin|md5 del instalador|sha256 del instalador
# (la sha256 se saco el 20/10/2026 de los instaladores de SourceForge, con su md5 igual al de aqui:
# el md5 solo no basta, se pueden fabricar dos ficheros con el mismo)
XAMPP_CATALOG=(
    "7.1.33|7.1.33-1|7.1.33|2.4.41|10.4.10|1.3.6|5.16.3|4.9.2|896394f65873a2b14eca63b3c6d7f1ac|15b46deccb8a81946e9c1e26eade6c19481108906effb4bdbdfc55895c7c5da8"
    "7.4|7.4.33-0|7.4.33|2.4.54|10.4.27|1.3.6|5.34.1|5.2.0|8467421af9ee1f04464b3e439199480c|8785db581be53d6126e2f400112cb86ae3ab9119d73e18f619231c33231302d0"
    "8.1|8.1.25-0|8.1.25|2.4.58|10.4.32|1.3.6|5.34.1|5.2.1|e380a45f13e1dbe6b0544c9a304e153c|0e3940cb7315ea3432e6925a60e6d6cd6705d5b116f0c7398aa585e4a5081b5c"
    "8.2.4|8.2.4-0|8.2.4|2.4.56|10.4.28|1.3.6|5.34.1|5.2.1|89c473a88eaaea0b00f530bee7cf40f5|80649062144fbe2d71e534e82d3043176a040b1a952abf06c73f168c4c4c4b8b"
)

DRY=0
PROGRESS=""

# Firma del panel principal
SIGNATURE="By M.Mascuñano - HEXER"

# Version del instalador: sale debajo de la firma y en "Acerca de", con la lista de cambios
APP_VERSION="1.49.0"

# Logo de hexer abajo a la izquierda, fuera de las ventanas: '#' en blanco y '/' en verde #45A57C
LOGO=(
    "##  //"
    " ##//"
    "  ##"
    " ####"
    "##  ##"
)

# ===========================================================================
# Interfaz: ventanas con whiptail si hay terminal, texto en caso contrario
# ===========================================================================

APP_NAME="Nexum Stack"
TITLE="$APP_NAME"
UI=text
if [ "$LVM_UI" != "text" ] && [ -t 0 ] && [ -t 1 ] && command -v whiptail > /dev/null; then
    UI=whiptail
fi

# Abierto desde el acceso del menu (el script es el primer proceso de su terminal, no lo lanzo
# una shell): si la terminal es menor de 100x32 se le pide ese tamaño con CSI 8 t (GNOME Terminal,
# xterm, Konsole...), para que el panel principal deje sitio al logo. Desde una terminal propia
# no se toca su tamaño.
if [ "$UI" == "whiptail" ] && [ "$(ps -o sid= -p $$ 2> /dev/null | tr -d ' ')" == "$$" ]; then
    size=$(stty size < /dev/tty 2> /dev/null)
    if [ -n "$size" ] && { (( ${size% *} < 32 )) || (( ${size#* } < 100 )); }; then
        printf '\033[8;32;100t' > /dev/tty
        # La terminal tarda un poco en cambiar; se espera hasta un segundo
        for i in 1 2 3 4 5 6 7 8 9 10; do
            [ "$(stty size < /dev/tty 2> /dev/null)" != "$size" ] && break
            sleep 0.1
        done
    fi
    unset size i
fi

# Colores de las ventanas: fondo oscuro y el elemento seleccionado en blanco (los colores por
# defecto, rojo sobre gris/rosa, apenas se distinguen). Se respeta un NEWT_COLORS propio.
# La barra de progreso rellena va en verde #45A57C con el % en blanco (newt ignora el color de texto
# de emptyscale/fullscale). El color exacto solo sale con COLORTERM=truecolor (GNOME Terminal,
# Konsole...); sin el, slang lo aproxima y pone el % en negro, asi que se usa el verde basico.
OWN_COLORS=1
if [ -z "$NEWT_COLORS" ]; then
    OWN_COLORS=0
    case "$COLORTERM" in
        truecolor|24bit) BAR_COLOR='#45A57C' ;;
        *) BAR_COLOR=green ;;
    esac
    export NEWT_COLORS='
        root=white,black
        roottext=white,black
        helpline=white,black
        shadow=black,black
        border=white,black
        window=white,black
        title=brightcyan,black
        textbox=white,black
        acttextbox=black,white
        listbox=white,black
        actlistbox=black,lightgray
        sellistbox=black,lightgray
        actsellistbox=black,white
        checkbox=white,black
        actcheckbox=black,white
        entry=white,black
        disentry=gray,black
        label=white,black
        button=black,white
        actbutton=black,white
        compactbutton=white,black
        emptyscale=,black
        fullscale=,'"$BAR_COLOR"'
    '
fi

# Tamano de la ventana ajustado al contenido: ui_size "texto" [ancho de la lista] [elementos de la lista]
function ui_size() {
    local text=$1 list_w=${2:-0} items=${3:-0}
    local cols=$(tput cols 2> /dev/null || echo 80)
    local lines=$(tput lines 2> /dev/null || echo 24)
    local longest=0 text_lines=0 line

    while IFS= read -r line; do
        (( ${#line} > longest )) && longest=${#line}
    done <<< "$(echo -e "$text")"

    W=$(( longest + 4 > list_w ? longest + 4 : list_w ))
    (( W < 60 )) && W=60
    (( W > cols - 2 )) && W=$(( cols - 2 ))

    # Lineas que ocupa el texto, contando las que whiptail parte por no caber
    while IFS= read -r line; do
        text_lines=$(( text_lines + (${#line} > W - 4 ? (${#line} + W - 5) / (W - 4) : 1) ))
    done <<< "$(echo -e "$text")"

    # La lista ocupa como minimo 3 lineas
    H=$(( text_lines + (items > 0 && items < 3 ? 3 : items) + 7 ))
    SCROLL=()
    (( H > lines - 2 )) && SCROLL=(--scrolltext)
    (( H > lines - 2 )) && H=$(( lines - 2 ))
    L=$(( H - text_lines - 7 ))
    (( L > items )) && L=$items
    (( L < 3 )) && L=3
}

# Rellena con espacios hasta el ancho indicado (el printf de bash cuenta bytes, no caracteres)
function pad() {
    local text=$1 width=$2

    printf '%s%*s' "$text" $(( width > ${#text} ? width - ${#text} : 0 )) ""
}

# fmt_row "anchos" campo [campo ...]: fila de una tabla con columnas de ancho fijo
function fmt_row() {
    local widths=($1) row="" i=0 field
    shift

    for field in "$@"; do
        row+=$(pad "$field" "${widths[i]:-0}")
        i=$((i + 1))
    done

    echo "$row"
}

# wt: whiptail con la firma abajo a la derecha de la pantalla y el logo abajo a la izquierda,
# fuera de la ventana.
# whiptail borra la pantalla al abrirse, asi que la firma se escribe en la terminal justo despues
# de que dibuje; como no vuelve a tocar esa linea, se queda ahi. El proceso que la escribe no
# hereda la salida (se capturan con $(...)) y se detiene en cuanto whiptail termina.
# logo_escape filas columnas [argumentos de whiptail]: secuencia que pinta el logo abajo a la
# izquierda, o nada si la ventana (centrada, con su sombra) llegaria a taparlo
function logo_escape() {
    local lines=$1 cols=$2; shift 2
    local h=0 w=0 n=${#LOGO[@]} logo_w=0 row
    for row in "${LOGO[@]}"; do (( ${#row} > logo_w )) && logo_w=${#row}; done

    while [ $# -gt 0 ]; do
        case "$1" in
            --msgbox|--yesno|--infobox|--inputbox|--passwordbox|--textbox|--menu|--checklist|--radiolist|--gauge)
                h=${3:-0}; w=${4:-0}; break ;;
        esac
        shift
    done
    (( h > lines )) && h=$lines
    (( w > cols )) && w=$cols
    local top=$(( (lines - h) / 2 )) left=$(( (cols - w) / 2 ))
    # Sitio libre: la ventana empieza a la derecha del logo o acaba (sombra incluida) por encima
    if (( left <= logo_w + 3 )) && (( top + h + 1 >= lines - n + 1 )); then
        return 0
    fi

    local green='\033[32m' out="" i ch y
    case "$COLORTERM" in truecolor|24bit) green='\033[38;2;69;165;124m' ;; esac
    for (( i = 0; i < n; i++ )); do
        row=${LOGO[$i]}
        y=$(( lines - n + 1 + i ))
        out+="\033[${y};2H\033[0;1;40m"
        for (( ch = 0; ch < ${#row}; ch++ )); do
            case "${row:$ch:1}" in
                '#') out+='\033[97m#' ;;
                '/') out+="${green}/" ;;
                *) out+=' ' ;;
            esac
        done
    done
    printf '%s' "$out"
}

# green_escape filas columnas [argumentos de whiptail]: secuencia que repinta en verde el texto
# $WT_GREEN dentro de la ventana (whiptail no permite colorear una parte del texto). Calcula su
# posicion igual que whiptail centra la ventana: el texto empieza una fila por debajo del borde
# y dos columnas a su derecha. No pinta nada con un NEWT_COLORS propio (el fondo podria no ser
# negro), con texto que se desplaza (--scrolltext) o si la linea no cabe entera.
function green_escape() {
    local lines=$1 cols=$2; shift 2
    [ -z "$WT_GREEN" ] || [ "$OWN_COLORS" -eq 1 ] && return 0

    local text="" h=0 w=0 gap=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --scrolltext) return 0 ;;
            # Las ventanas de mensaje dejan una fila en blanco encima del texto; las listas no
            --msgbox|--yesno|--infobox)
                text=$2; h=${3:-0}; w=${4:-0}; gap=1; break ;;
            --inputbox|--textbox|--menu|--checklist|--radiolist)
                text=$2; h=${3:-0}; w=${4:-0}; break ;;
        esac
        shift
    done
    (( h > lines )) && h=$lines
    (( w > cols )) && w=$cols
    local top=$(( (lines - h) / 2 )) left=$(( (cols - w) / 2 ))

    # Fila del texto (contando las lineas que whiptail parte por no caber)
    local row=$(( top + 1 + gap )) line found=0
    while IFS= read -r line; do
        [[ "$line" == *"$WT_GREEN"* ]] && found=1 && break
        row=$(( row + (${#line} > w - 4 ? (${#line} + w - 5) / (w - 4) : 1) ))
    done <<< "$(echo -e "$text")"
    (( found == 1 && ${#line} <= w - 4 && row < top + h - 1 )) || return 0

    local prefix=${line%%"$WT_GREEN"*} green='\033[32m'
    case "$COLORTERM" in truecolor|24bit) green='\033[38;2;69;165;124m' ;; esac
    printf '%s' "\033[$(( row + 1 ));$(( left + 3 + ${#prefix} ))H\033[0;1;40m${green}${WT_GREEN}"
}

# signature_escape filas columnas [argumentos de whiptail]: secuencia que pinta la firma abajo a la
# derecha con la version del instalador debajo. Si la ventana llega a la penultima fila, firma y
# version van juntas en la ultima.
function signature_escape() {
    local lines=$1 cols=$2; shift 2
    local version="v$APP_VERSION" h=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --msgbox|--yesno|--infobox|--inputbox|--passwordbox|--textbox|--menu|--checklist|--radiolist|--gauge)
                h=${3:-0}; break ;;
        esac
        shift
    done
    (( h > lines )) && h=$lines
    local top=$(( (lines - h) / 2 )) col=$(( cols - ${#SIGNATURE} - 1 ))
    (( col > 0 )) || return 0

    if (( top + h < lines - 1 )); then
        printf '%s' "\033[$(( lines - 1 ));${col}H\033[0;37;40m$SIGNATURE"
        printf '%s' "\033[${lines};$(( cols - ${#version} - 1 ))H\033[0;37;40m$version"
    else
        local both="$SIGNATURE  $version"
        (( ${#both} + 1 < cols )) || both=$SIGNATURE
        printf '%s' "\033[${lines};$(( cols - ${#both} - 1 ))H\033[0;37;40m$both"
    fi
}

function wt() {
    local signer=""

    if [ -w /dev/tty ]; then
        (
            # Se repite mientras whiptail este abierto: al principio por si tarda en dibujar y
            # despues cada 2 segundos, por si la terminal cambia de tamaño (GNOME Terminal puede
            # ajustarla justo despues de abrirse) y whiptail lo borra al redibujar. El tamaño se
            # lee cada vez. ESC 7 / ESC 8 guardan y restauran la posicion del cursor y los
            # colores, para no alterar lo que dibuja whiptail.
            # Se para si el script ya no existe ($$ es su PID tambien aqui) o la terminal se cierra.
            local delay=0.15 lines cols sign logo size
            while kill -0 $$ 2> /dev/null; do
                sleep $delay
                case $delay in 0.15) delay=0.4 ;; 0.4) delay=1 ;; *) delay=2 ;; esac
                size=$(stty size < /dev/tty 2> /dev/null) || size="24 80"
                lines=${size% *} cols=${size#* }
                sign=$(signature_escape "$lines" "$cols" "$@")
                [ -n "$sign" ] || continue
                logo=$(logo_escape "$lines" "$cols" "$@")$(green_escape "$lines" "$cols" "$@")
                printf "\0337${sign}${logo}\0338" > /dev/tty || break
            done
        ) < /dev/null > /dev/null 2>&1 &
        signer=$!
    fi

    whiptail "$@"
    local rc=$?

    [ -n "$signer" ] && kill "$signer" 2> /dev/null && wait "$signer" 2> /dev/null
    return $rc
}

# with_signature "texto" ancho: pone la firma alineada a la derecha en la ultima linea del texto
function with_signature() {
    local text=$(echo -e "$1") width=$2
    local last=${text##*$'\n'}
    local rest=""
    [ "$last" != "$text" ] && rest="${text%$'\n'*}\n"

    if (( ${#last} + ${#SIGNATURE} + 2 > width )); then
        echo "$1\n$(printf '%*s' $(( width - ${#SIGNATURE} > 0 ? width - ${#SIGNATURE} : 0 )) "")$SIGNATURE"
    else
        echo "$rest$(pad "$last" $(( width - ${#SIGNATURE} )))$SIGNATURE"
    fi
}

function ui_msg() {
    if [ "$UI" == "whiptail" ]; then
        ui_size "$1"
        wt --title "$TITLE" "${SCROLL[@]}" --ok-button "Continuar" --msgbox "$1" $H $W
    else
        echo "" >&2
        echo -e "$1" >&2
        echo "" >&2
        [ -t 0 ] && read -p "Pulsa Intro para continuar... " _ >&2
    fi
}

function ui_yesno() {
    if [ "$UI" == "whiptail" ]; then
        ui_size "$1"
        wt --title "$TITLE" --yes-button "Si" --no-button "No" --defaultno "${SCROLL[@]}" --yesno "$1" $H $W
    else
        local answer
        echo "" >&2
        echo -e "$1" >&2
        read -p "[s/N]: " answer >&2
        [[ "$answer" =~ ^[sSyY]$ ]]
    fi
}

# ui_list menu|checklist "texto" "opcion por defecto" "cabecera" tag descripcion [tag descripcion ...]
# Con cabecera, las descripciones son filas de una tabla (todas del mismo ancho, ver fmt_row) y se
# ocultan los tags; la cabecera se alinea encima de las columnas.
function ui_list() {
    local kind=$1 text=$2 default=$3 header=$4
    shift 4

    local tags=() descs=() n=0 longest=0 longest_tag=0
    while [ $# -gt 0 ]; do
        tags+=("$1")
        descs+=("$2")
        n=$((n + 1))
        (( ${#1} > longest_tag )) && longest_tag=${#1}
        (( ${#2} > longest )) && longest=${#2}
        shift 2
    done

    if [ "$UI" == "whiptail" ]; then
        local args=() i list_w
        for (( i = 0; i < n; i++ )); do
            args+=("${tags[i]}" "${descs[i]}")
            [ "$kind" == "checklist" ] && args+=(OFF)
        done

        # Ancho que ocupa la lista dentro de la ventana (casillas, tags, marco y barra de desplazamiento)
        local boxes=0
        [ "$kind" == "checklist" ] && boxes=4
        if [ -n "$header" ]; then
            list_w=$(( longest + boxes + 8 ))
        else
            list_w=$(( longest_tag + longest + boxes + 10 ))
        fi

        local help=""
        [ "$kind" == "checklist" ] && help="\n(Espacio = marcar/desmarcar, Intro = aceptar)"

        local full="$text$help"
        [ -n "$header" ] && full+="\n\n$header\n$header"
        ui_size "$full" "$list_w" "$n"

        if [ -n "$header" ]; then
            # El menu centra la lista en la ventana; la lista de casillas empieza siempre en la columna 5
            local indent=5
            [ "$kind" == "menu" ] && indent=$(( (W - 4 - longest) / 2 - 1 ))
            (( n > L )) && [ "$kind" == "menu" ] && indent=$(( (W - 6 - longest) / 2 - 1 ))
            (( indent < 0 )) && indent=0
            local margin=$(printf '%*s' $indent "")
            local rule=$(printf '%*s' ${#header} "" | tr ' ' '-')
            text+="$help\n\n$margin$header\n$margin$rule"
            args=(--notags "${args[@]}")
        else
            text+="$help"
        fi

        if [ "$kind" == "menu" ]; then
            wt --title "$TITLE" --ok-button "Aceptar" --cancel-button "Volver" \
                --default-item "$default" --menu "$text" $H $W $L "${args[@]}" 3>&1 1>&2 2>&3
        else
            wt --title "$TITLE" --separate-output --ok-button "Aceptar" --cancel-button "Volver" \
                --checklist "$text" $H $W $L "${args[@]}" 3>&1 1>&2 2>&3
        fi
        return
    fi

    local i choice
    echo "" >&2
    echo -e "$text" >&2
    if [ -n "$header" ]; then
        echo "" >&2
        echo "      $header" >&2
        echo "      $(printf '%*s' ${#header} "" | tr ' ' '-')" >&2
    fi
    for (( i = 0; i < n; i++ )); do
        local mark=""
        [ "$kind" == "menu" ] && [ "${tags[i]}" == "$default" ] && mark="  (por defecto)"
        printf '  %2d) %s%s\n' $((i + 1)) "${descs[i]}" "$mark" >&2
    done

    if [ "$kind" == "menu" ]; then
        read -p "Numero [Intro = por defecto, v = volver]: " choice >&2

        [ "$choice" == "v" ] && return 1
        if [ -z "$choice" ]; then
            [ -n "$default" ] && echo "$default" && return 0
            return 1
        fi
        [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $n ] || return 1
        echo "${tags[$((choice - 1))]}"
    else
        read -p "Numeros separados por espacios (Intro = volver): " choice >&2
        [ -z "$choice" ] && return 1

        for c in $choice; do
            [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le $n ] && echo "${tags[$((c - 1))]}"
        done
    fi
}

# ui_menu "texto" "opcion por defecto" tag descripcion [tag descripcion ...]
function ui_menu() {
    ui_list menu "$1" "$2" "" "${@:3}"
}

# ui_table_menu "texto" "opcion por defecto" "cabecera" tag fila [tag fila ...]
function ui_table_menu() {
    ui_list menu "$@"
}

# ui_table_checklist "texto" "cabecera" tag fila [tag fila ...] -> una opcion elegida por linea
function ui_table_checklist() {
    ui_list checklist "$1" "" "${@:2}"
}

function ui_input() {
    local text=$1 default=$2

    if [ "$UI" == "whiptail" ]; then
        ui_size "$text"
        wt --title "$TITLE" --ok-button "Aceptar" --cancel-button "Volver" \
            --inputbox "$text" $((H + 2)) $W "$default" 3>&1 1>&2 2>&3
    else
        local answer
        echo "" >&2
        echo -e "$text" >&2
        read -p "> " answer >&2
        echo "${answer:-$default}"
    fi
}

function say() {
    echo ""
    echo "==> $*"
}

# ===========================================================================
# Deteccion de lo instalado
# ===========================================================================

function lampp_dirs() {
    find /opt -maxdepth 1 -type d -name "lampp-*" 2> /dev/null | sort -V
}

# Version de PHP nueva (PHP-FPM): pila propia o, las antiguas, copiada de un XAMPP
function is_fpm_install() {
    [ -d "$1/php/sbin" ]
}

function is_stack_install() {
    [ -f "$1/etc/lvm-stack" ]
}

function php_version() {
    if [ -f "$1/etc/lvm-php" ]; then
        cat "$1/etc/lvm-php"
    else
        readlink "$1/bin/php" | sed -n 's|^php-\([0-9.]*\)$|\1|p'
    fi
}

# Versiones de los componentes: "php|apache|mariadb|proftpd|perl|phpmyadmin"
# Se leen de las cabeceras de cada instalacion. Los binarios de XAMPP buscan sus librerias en
# /opt/lampp/lib, asi que solo se ejecutan como ultimo recurso y con LD_LIBRARY_PATH propio.
function stack_fields() {
    local dir=$1

    # Las pilas propias guardan sus versiones al instalarse
    if is_stack_install "$dir"; then
        cat "$dir/etc/lvm-stack"

        return 0
    fi

    local php=$(php_version "$dir")

    local apache=$(awk '/define AP_SERVER_(MAJORVERSION|MINORVERSION|PATCHLEVEL)_NUMBER/ {v = v (v == "" ? "" : ".") $3} END {print v}' \
        "$dir/include/ap_release.h" 2> /dev/null)
    [ -z "$apache" ] && apache=$(LD_LIBRARY_PATH="$dir/lib" "$dir/bin/httpd" -v 2> /dev/null | sed -n 's|.*Apache/\([0-9.]*\).*|\1|p')

    local mariadb=$(grep -hoE 'MYSQL_SERVER_VERSION[[:space:]]+"[0-9.]+' "$dir/include/mariadb_version.h" "$dir/include/server/mysql_version.h" 2> /dev/null \
        | head -1 | grep -oE '[0-9.]+$')
    [ -z "$mariadb" ] && mariadb=$(LD_LIBRARY_PATH="$dir/lib" "$dir/bin/mysql" --version 2> /dev/null | sed -n 's|.*Distrib \([0-9.]*\)-MariaDB.*|\1|p')

    local ftp=$(grep -hoE 'PROFTPD_VERSION_TEXT[[:space:]]+"[0-9.a-z]+' "$dir/include/proftpd/version.h" 2> /dev/null | grep -oE '[0-9][0-9.a-z]*$')
    [ -z "$ftp" ] && ftp=$(LD_LIBRARY_PATH="$dir/lib" "$dir/sbin/proftpd" -v 2> /dev/null | sed -n 's|.*Version \([0-9.a-z]*\).*|\1|p')

    local perl=$(ls -d "$dir"/lib/perl5/5.* 2> /dev/null | sort -V | tail -1 | sed 's|.*/||')
    [ -z "$perl" ] && perl=$(LD_LIBRARY_PATH="$dir/lib" "$dir/bin/perl" -e 'print substr($^V, 1)' 2> /dev/null)

    local pma=$(grep -hoE "(VERSION = |PMA_VERSION', )'[0-9.]+'" "$dir/phpmyadmin/libraries/classes/Version.php" \
        "$dir/phpmyadmin/libraries/classes/Config.php" "$dir/phpmyadmin/libraries/Config.php" 2> /dev/null | head -1 | grep -oE "[0-9][0-9.]+")
    [ -z "$pma" ] && pma=$(grep -rhoE "(VERSION = |PMA_VERSION', )'[0-9.]+'" "$dir/phpmyadmin/libraries" 2> /dev/null | head -1 | grep -oE "[0-9][0-9.]+")

    echo "${php:--}|${apache:--}|${mariadb:--}|${ftp:--}|${perl:--}|${pma:--}"
}

# Tabla de versiones: columna "Version", los seis componentes y una columna final variable
STACK_WIDTHS="11 8 8 9 9 8 12 8"
STACK_HEADER_FIELDS=("Version" "PHP" "Apache" "MariaDB" "ProFTPD" "Perl" "phpMyAdmin")

function stack_header() {
    fmt_row "$STACK_WIDTHS" "${STACK_HEADER_FIELDS[@]}" "$1"
}

# stack_row <carpeta> [texto de la ultima columna] [nombre a mostrar]
function stack_row() {
    local dir=$1 extra=$2 name=${3:-${1#/opt/lampp-}}
    local fields

    IFS='|' read -r -a fields <<< "$(stack_fields "$dir")"
    fmt_row "$STACK_WIDTHS" "$name" "${fields[@]}" "$extra"
}

# Fila de un XAMPP del catalogo que aun no esta instalado
function catalog_row() {
    local entry=$(catalog_entry "$1") extra=$2
    local folder release php apache mariadb ftp perl pma md5 sha

    IFS='|' read -r folder release php apache mariadb ftp perl pma md5 sha <<< "$entry"
    fmt_row "$STACK_WIDTHS" "$folder" "$php" "$apache" "$mariadb" "$ftp" "$perl" "$pma" "$extra"
}

# Componentes de un XAMPP instalado o del catalogo: "php|apache|mariadb|proftpd|perl|phpmyadmin"
function xampp_fields() {
    local folder=$1

    if [ -d "/opt/lampp-$folder" ]; then
        stack_fields "/opt/lampp-$folder"
    else
        catalog_entry "$folder" | awk -F'|' '{print $3"|"$4"|"$5"|"$6"|"$7"|"$8}'
    fi
}

# Versiones que usan las bases de datos de otra (separadas por espacios)
function data_users() {
    local version=$1 dir

    for dir in $(lampp_dirs); do
        [ "$dir" == "/opt/lampp-$version" ] && continue
        [ "$(data_owner "$dir")" == "$version" ] && echo -n "${dir#/opt/lampp-} "
    done
}

# Bases de datos de una instalacion, sin las del sistema. MariaDB guarda en la carpeta los
# caracteres especiales del nombre como @XXXX (wp_mi@002dweb es wp_mi-web): se decodifican
function db_names() {
    local name code char
    find "$1/var/mysql/" -mindepth 1 -maxdepth 1 -type d \
        -not -name mysql -not -name performance_schema -not -name phpmyadmin -not -name test -not -name sys \
        -printf "%f\n" 2> /dev/null | while IFS= read -r name; do
            while [[ "$name" =~ @([0-9a-f]{4}) ]]; do
                code=${BASH_REMATCH[1]}
                printf -v char "\\u$code"
                name=${name//"@$code"/$char}
            done
            # Solo nombres que se pueden usar (sin | ni saltos de linea)
            [[ "$name" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$ ]] && echo "$name"
        done | sort -f
}

# Nombres repartidos en columnas que caben en el ancho indicado
function columns() {
    local width=${1:-72} names=() name longest=0

    while IFS= read -r name; do
        [ -z "$name" ] && continue
        names+=("$name")
        (( ${#name} > longest )) && longest=${#name}
    done

    [ ${#names[@]} -eq 0 ] && return 0

    local col_w=$(( longest + 3 ))
    local ncols=$(( width / col_w ))
    (( ncols < 1 )) && ncols=1
    local nrows=$(( (${#names[@]} + ncols - 1) / ncols ))
    local r c line

    # Orden por columnas (de arriba abajo), como ls
    for (( r = 0; r < nrows; r++ )); do
        line=""
        for (( c = 0; c < ncols; c++ )); do
            local i=$(( c * nrows + r ))
            [ $i -lt ${#names[@]} ] && line+=$(pad "${names[i]}" $col_w)
        done
        echo "  ${line%"${line##*[! ]}"}"
    done
}

function active_dir() {
    [ -L /opt/lampp ] && readlink -f /opt/lampp
}

# Version cuyas bases de datos usa una instalacion
function data_owner() {
    readlink -f "$1/var/mysql" | sed -n 's|^/opt/lampp-\(.*\)/var/mysql$|\1|p'
}

# XAMPP del que se copio una version de PHP antigua (o la propia version si es un XAMPP)
function base_of() {
    local dir=$1

    if [ -f "$dir/etc/lvm-base" ]; then
        cat "$dir/etc/lvm-base"
    elif is_fpm_install "$dir"; then
        data_owner "$dir"
    else
        echo "${dir#/opt/lampp-}"
    fi
}

function xampp_bases() {
    for dir in $(lampp_dirs); do
        is_fpm_install "$dir" || echo "${dir#/opt/lampp-}"
    done
}

function status_text() {
    local active=$(active_dir) rows="" dir name mark old=0

    for dir in $(lampp_dirs); do
        name=${dir#/opt/lampp-}
        mark="  "
        [ "$dir" == "$active" ] && mark="* "
        is_fpm_install "$dir" && ! is_stack_install "$dir" && old=1

        rows+="$(stack_row "$dir" "$(install_type "$dir")" "$mark$name")\n"
    done

    local text=""
    if [ -z "$rows" ]; then
        text="No hay ninguna version instalada en /opt/lampp-*\n"
    else
        local header=$(fmt_row "$STACK_WIDTHS" "  ${STACK_HEADER_FIELDS[0]}" "${STACK_HEADER_FIELDS[@]:1}" "Tipo")
        text+="$header\n$(printf '%*s' ${#header} "" | tr ' ' '-')\n$rows\n"
        [ -n "$active" ] && text+="* = version activa\n"
        text+="Tipo: 'XAMPP' (paquete oficial) o 'propia' (pila propia de esa rama de PHP).\n"
        text+="Todas tienen sus propias bases de datos.\n"
        [ $old -eq 1 ] && text+="'sobre X': PHP nuevo con el resto copiado del XAMPP X. Se puede pasar a pila propia\ncon 'Actualizar versiones de PHP'.\n"
    fi

    if [ -e /opt/lampp ] && [ ! -L /opt/lampp ]; then
        text+="\nAVISO: /opt/lampp es una instalacion de XAMPP sin registrar.\n"
        text+="Hay que registrarla antes de instalar versiones de XAMPP (opcion del panel principal).\n"
    elif [ -z "$active" ]; then
        text+="\nNinguna version activa.\n"
    fi

    echo "$text"
}

# Tipo de instalacion para las tablas: XAMPP, pila propia o PHP sobre un XAMPP (antiguas)
function install_type() {
    local dir=$1

    if is_stack_install "$dir"; then
        echo "propia"
    elif is_fpm_install "$dir"; then
        local text="sobre $(base_of "$dir")"
        [ -L "$dir/var/mysql" ] && text+=", BBDD de $(data_owner "$dir")"
        echo "$text"
    else
        echo "XAMPP"
    fi
}

function catalog_entry() {
    local entry

    for entry in "${XAMPP_CATALOG[@]}"; do
        [ "${entry%%|*}" == "$1" ] && echo "$entry" && return 0
    done

    return 1
}

# Todas las versiones publicadas de PHP 7 y 8, de la mas nueva a la mas antigua: "version fecha
# seguridad" (fecha AAAA-MM-DD; seguridad: "seguridad" si php.net la marca como parche de seguridad,
# si no "-"). Solo las que tienen el codigo fuente .tar.xz con su suma sha256.
function php_all_releases() {
    local major

    for major in 7 8 9; do
        # Una rama mayor que aun no existe (9) devuelve {"error": ...} y no cuenta como fallo
        fetch "https://www.php.net/releases/index.php?json&version=$major&max=1000" | python3 -I -c 'import json, re, sys, datetime
data = json.load(sys.stdin)
for version, info in (data.items() if "error" not in data else []):
    # (solo X.Y.Z: con un | o un salto de linea descolocaria las lineas de la ventana)
    if re.match(r"^\d+\.\d+\.\d+$", version) and any(s["filename"].endswith(".tar.xz") and s.get("sha256") for s in info.get("source", [])):
        try:
            date = datetime.datetime.strptime(info.get("date", ""), "%d %b %Y").strftime("%Y-%m-%d")
        except ValueError:
            date = "-"
        print(version, date, "seguridad" if "security" in (info.get("tags") or []) else "-")' 2> /dev/null || true
    done | sort -rV
}

# Ramas de PHP con soporte oficial (las demas se marcan como antiguas en el panel)
function php_supported() {
    fetch "https://www.php.net/releases/active.php" | python3 -I -c 'import json, re, sys
for branches in json.load(sys.stdin).values():
    for branch in branches:
        if re.match(r"^\d+\.\d+$", str(branch)):
            print(branch)' 2> /dev/null
}

# Estado de cada rama en php.net: rama|estado|fin del soporte activo|fin de los parches de seguridad
#   estado: stable (correcciones de errores y de seguridad), security (solo de seguridad) o eol
function php_branch_states() {
    fetch "https://www.php.net/releases/branches.php" | python3 -I -c 'import json, re, sys
for b in json.load(sys.stdin):
    if not re.match(r"^\d+\.\d+$", str(b.get("branch", ""))) or b.get("state") not in ("stable", "security", "eol"):
        continue
    print("%s|%s|%s|%s" % (b.get("branch", ""), b.get("state", ""),
                           (b.get("active_support_end") or "")[:10], (b.get("security_support_end") or "")[:10]))' 2> /dev/null
}

# Texto del estado de una rama para el panel: estable, solo seguridad o sin soporte
function branch_state_text() {
    local st=$(grep "^$1|" <<< "$2" | cut -d'|' -f2)
    case "$st" in
        stable) echo "estable" ;;
        security) echo "solo seguridad" ;;
        eol) echo "sin soporte" ;;
        *) grep -qxF "$1" <<< "$3" && echo "con soporte" || echo "sin soporte" ;;
    esac
}

# Ramas que ofrece el instalador: las de STACK_MATRIX y las nuevas con soporte (usan la ultima fila)
function php_branches() {
    { printf '%s\n' "${STACK_MATRIX[@]%%|*}"; php_supported; } | sort -uV
}

# Ultima version publicada de cada rama que ofrece el instalador: "8.4 8.4.26"
function php_releases() {
    local all=$(php_all_releases) branch latest

    for branch in $(php_branches); do
        latest=$(awk -v b="$branch." 'index($1, b) == 1 {print $1; exit}' <<< "$all")
        [ -n "$latest" ] && echo "$branch $latest"
    done
}

# Parches publicados de una rama, del mas nuevo al mas antiguo: "8.4.26 2026-09-24"
function php_patches() {
    php_all_releases | awk -v b="$1." 'index($1, b) == 1'
}

# Elemento del plan para instalar una version de PHP: el ultimo parche de su rama va en
# /opt/lampp-X.Y (php:); uno anterior, o si la carpeta de la rama ya existe, en /opt/lampp-X.Y.Z (parche:)
function php_item() {
    local full=$1 latest=$2

    if [ "$full" == "$latest" ] && [ ! -e "${TEST_DIR:-/opt}/lampp-${full%.*}" ]; then
        echo "php:$full"
    else
        echo "parche:$full"
    fi
}

# Version de PHP nueva (no XAMPP) que ya tiene una version exacta de PHP (vacio si ninguna).
# Un XAMPP con la misma version de PHP no cuenta: la pila propia lleva otros componentes.
function php_installed_in() {
    local dir

    for dir in $(lampp_dirs); do
        is_fpm_install "$dir" && [ "$(php_version "$dir")" == "$1" ] && echo "$dir" && return 0
    done

    return 1
}

# Carpeta (lampp-<carpeta>) en la que se instala un elemento del plan
function item_folder() {
    local name=${1#*:}

    case "${1%%:*}" in
        php|rehacer) echo "${name%.*}" ;;
        *) echo "$name" ;;
    esac
}

function lampp_running() {
    pgrep -f "^/opt/lampp(-[^/]+)?/(bin/httpd|sbin/mysqld|sbin/proftpd|apache2/bin/httpd|mysql/bin/mariadbd|proftpd/sbin/proftpd)( |$)" > /dev/null
}

function run() {
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $*"
    else
        "$@"
    fi
}

# ===========================================================================
# Acciones de lvm
# ===========================================================================

# Los vhosts son del administrador: Apache los lee como root al arrancar, y si fueran tuyos
# cualquier programa que se ejecute con tu usuario (un plugin de una web, por ejemplo) podria
# añadirles una orden que se ejecutaria como root (ErrorLog "|orden", LoadModule...). Se edita una
# copia (VHOSTS_COPY) y vhosts --aplicar la comprueba y la escribe con sudo.
VHOSTS_COPY="$HOME/.lvm-instalador/httpd-vhosts.conf"

# Directivas que solo cambian como se sirve cada web. El resto (LoadModule, Include, Listen,
# PidFile, User, RewriteMap, SSLPassPhraseDialog...) se aplicaria como root a todo Apache: no se
# admite en los vhosts (se puede seguir poniendo a mano con sudoedit). Los registros, sin tuberias
# (|orden) y dentro de la carpeta logs.
VHOSTS_CHECK_PY='
import re, sys
allowed = {d.lower() for d in """
VirtualHost IfModule IfDefine IfVersion Directory DirectoryMatch Location LocationMatch Files
FilesMatch Proxy ProxyMatch Limit LimitExcept RequireAll RequireAny RequireNone If ElseIf Else
ServerName ServerAlias ServerAdmin ServerPath DocumentRoot UseCanonicalName ServerSignature
ErrorLog CustomLog TransferLog LogLevel LogFormat
SSLEngine SSLCertificateFile SSLCertificateKeyFile SSLCertificateChainFile SSLCACertificateFile
SSLProtocol SSLCipherSuite SSLHonorCipherOrder SSLProxyEngine SSLProxyVerify SSLProxyCheckPeerName
SSLProxyCheckPeerCN SSLProxyCheckPeerExpire SSLOptions
Header RequestHeader Options AllowOverride AllowOverrideList Require Order Allow Deny Satisfy
DirectoryIndex DirectorySlash FallbackResource AcceptPathInfo ErrorDocument
RewriteEngine RewriteRule RewriteCond RewriteBase RewriteOptions
Redirect RedirectMatch RedirectPermanent RedirectTemp Alias AliasMatch ScriptAlias ScriptAliasMatch
ProxyPass ProxyPassReverse ProxyPassMatch ProxyPreserveHost ProxyRequests ProxyTimeout ProxyAddHeaders
SetEnv SetEnvIf SetEnvIfNoCase UnsetEnv PassEnv BrowserMatch BrowserMatchNoCase
SetHandler AddHandler RemoveHandler AddType ForceType AddDefaultCharset AddCharset AddEncoding
AddOutputFilterByType SetOutputFilter SetInputFilter DeflateCompressionLevel
ExpiresActive ExpiresByType ExpiresDefault
php_value php_admin_value php_flag php_admin_flag
KeepAlive KeepAliveTimeout MaxKeepAliveRequests Timeout LimitRequestBody LimitRequestFields
AllowEncodedSlashes Protocols H2Direct H2Push EnableSendfile EnableMMAP FileETag
AuthType AuthName AuthUserFile AuthGroupFile AuthBasicProvider NameVirtualHost
""".split()}
logs = {"errorlog", "customlog", "transferlog"}
ssl_files = {"sslcertificatefile", "sslcertificatekeyfile", "sslcertificatechainfile", "sslcacertificatefile"}
bad = []
# Primer argumento de una directiva, entero, como lo lee Apache: entre comillas puede llevar espacios
# ("logs/x /../../etc/y" es una sola ruta, que Apache resuelve con los ..). Se devuelve entero
# (Apache solo separa por espacios ASCII: uno Unicode, como U+00A0, va dentro de la ruta. Las \
# se dejan tal cual: clean_path no las admite)
def first_arg(value):
    value = value.strip(" \t\r\n\v\f")
    if value[:1] in ("\"", "\x27"):
        end = value.find(value[0], 1)
        return value[1:end] if end > 0 else value[1:]
    words = re.split(r"[ \t\r\n\v\f]+", value)
    return words[0] if words else ""
# Una ruta sin espacios ni .. ni /./ ni // (lo que Apache resolveria fuera de la carpeta)
def clean_path(path):
    return path != "" and path.isascii() and not any(c.isspace() for c in path) and "\\" not in path \
        and ".." not in path and "/./" not in path and "//" not in path and not path.startswith("./")
# Los certificados que ya usan los vhosts de ahora (segundo argumento) se siguen admitiendo aunque
# esten en otra carpeta: solo se rechaza una ruta nueva fuera de las del gestor
known = set()
if len(sys.argv) > 2:
    try:
        for l in open(sys.argv[2], encoding="utf-8", errors="replace"):
            w = l.split()
            if len(w) >= 2 and w[0].lower() in ssl_files:
                known.add(first_arg(l.strip()[len(w[0]):]))
    except OSError:
        pass
# Se lee como Apache: por bytes, cada linea hasta \n. Un byte de control (como \0, que corta la
# linea para Apache pero no para Python) haria que los dos vieran lineas distintas: no se admite
data = open(sys.argv[1], "rb").read()
for n, raw in enumerate(data.split(b"\n"), 1):
    if any(c < 32 and c not in (9, 13) or c == 127 for c in raw):
        print("Linea %d: lleva caracteres de control (como \\0): no se admite" % n)
        sys.exit(1)
lines = [l[:-1] if l.endswith("\r") else l for l in data.decode("utf-8", "replace").split("\n")]
i = 0
while i < len(lines):
    n, line = i + 1, lines[i]
    # Lineas partidas con \ al final
    while line.endswith("\\") and i + 1 < len(lines):
        i += 1
        line = line[:-1] + lines[i]
    i += 1
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    # Apache sustituye ${VAR} antes de leer la linea: una ruta que parece buena podria ser otra
    if "${" in s:
        bad.append("Linea %d: las variables ${...} no se admiten en los vhosts" % n)
        continue
    m = re.match(r"<?/?\s*([A-Za-z_][\w-]*)\s*(.*?)>?$", s)
    name, value = (m.group(1), m.group(2).strip()) if m else (s, "")
    if name.lower() not in allowed:
        bad.append("Linea %d: %s no se admite en los vhosts" % (n, name))
        continue
    if name.lower() in logs:
        path = first_arg(value)
        # Solo un fichero dentro de logs (sin subcarpetas ni ..) o syslog
        # (y no con el nombre de un fichero de control de Apache: el .pid lo lee el script lampp)
        if not (re.match(r"^(logs/|/opt/lampp(-[A-Za-z0-9._-]+)?/logs/)[A-Za-z0-9._-]+$", path)
                and clean_path(path) and not re.search(r"(?i)(\.pid|\.sock|\.lock|cgisock.*|ssl_mutex.*)$", path)) \
                and not re.match(r"^syslog(:[a-z0-9]+)?$", path):
            bad.append("Linea %d: %s %s: los registros van en la carpeta logs (sin |orden)" % (n, name, path))
    # Certificados y claves solo de las carpetas del gestor: con otra ruta, Apache (que arranca como
    # root) cargaria la clave de otro servicio del equipo
    if name.lower() in ssl_files:
        path = first_arg(value)
        if not clean_path(path) or path not in known and (not re.match(r"^(/opt/config/ssl/|etc/ssl\.(crt|key)/|/opt/lampp(-[A-Za-z0-9._-]+)?/etc/ssl\.(crt|key)/)[A-Za-z0-9._+-]+$", path) or ".." in path):
            bad.append("Linea %d: %s %s: los certificados van en /opt/config/ssl (los que ya tenias valen; los nuevos, ahi)" % (n, name, path))
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
'

# Abre una copia de los vhosts en el editor ($VISUAL, $EDITOR o nano) y la aplica. Con --aplicar
# <copia>, la ventana ya la ha editado: se comprueba (vhosts_check y httpd -t), se guarda el
# anterior en ~/lvm-copias, se escribe con sudo y se recarga Apache si esta en marcha. Si Apache
# no acepta la configuracion nueva, se vuelve a la anterior.
function edit_vhosts() {
    local mode=$1 copy=${2:-$VHOSTS_COPY} real backup answer
    if [ ! -e "$ACTIVE_VHOSTS" ]; then
        echo "No hay ninguna version activa con $ACTIVE_VHOSTS. Activa una version primero."
        return 1
    fi
    real=$(readlink -f "$ACTIVE_VHOSTS")
    # Las ventanas de versiones anteriores pedian permiso para hacerlo tuyo: ya no hace falta
    [ "$mode" == "--permiso" ] && return 0
    if [ "$mode" != "--aplicar" ]; then
        mkdir -p -m 700 "$(dirname "$copy")" && cp "$real" "$copy" || return 1
        run ${VISUAL:-${EDITOR:-nano}} "$copy"
        if cmp -s "$copy" "$real"; then
            echo "No hay cambios en los vhosts."
            return 0
        fi
        read -r -p "¿Aplicar los cambios? [s/N]: " answer
        [[ "$answer" =~ ^[sSyY]$ ]] || { echo "No se ha cambiado nada (la copia queda en $copy)"; return 0; }
    fi
    if [ ! -s "$copy" ]; then
        echo "La copia editada ($copy) no existe o esta vacia: no se cambian los vhosts."
        return 1
    fi
    if cmp -s "$copy" "$real"; then
        echo "No hay cambios en los vhosts."
        return 0
    fi
    if [ "$DRY" -eq 1 ]; then
        python3 -I -c "$VHOSTS_CHECK_PY" "$copy" "$real" || return 1
        echo "  [simulacion] copia de root, comprobacion, sudo install en $real, httpd -t y recarga de Apache"
        return 0
    fi
    # La copia editada es tuya y cualquier programa con tu usuario puede cambiarla mientras se
    # escribe la contraseña: se lee una sola vez (con tu usuario) a una carpeta de root, y lo que se
    # comprueba es exactamente lo que se escribe. La version anterior queda tambien en esa carpeta
    # (la de ~/lvm-copias es solo para ti: no se vuelve a escribir desde ahi)
    local snap
    sudo -v || return 1
    snap=$(sudo mktemp -d /tmp/lvm-vhosts.XXXXXX) || return 1
    sudo chmod 700 "$snap"
    if ! sudo sh -c 'umask 077; cat > "$1"' sh "$snap/nuevo" < "$copy" \
            || ! sudo cp "$real" "$snap/anterior"; then
        sudo rm -rf "$snap"
        return 1
    fi
    if ! sudo python3 -I -c "$VHOSTS_CHECK_PY" "$snap/nuevo" "$snap/anterior"; then
        sudo rm -rf "$snap"
        echo "No se aplican: esas lineas cambiarian todo Apache, que arranca como administrador."
        echo "Si de verdad las necesitas, ponlas a mano: sudoedit $real"
        return 1
    fi
    backup="$HOME/lvm-copias/httpd-vhosts.conf-$(date +%Y%m%d-%H%M%S)"
    mkdir -p -m 700 "$HOME/lvm-copias" && cp "$real" "$backup" \
        && echo "Copia de los vhosts anteriores: $backup"
    if ! sudo install -o root -g root -m 644 "$snap/nuevo" "$real"; then
        sudo rm -rf "$snap"
        return 1
    fi
    vhosts_root > /dev/null
    if ! apache_configtest; then
        echo "Apache no acepta los vhosts nuevos: se deja como estaba."
        sudo install -o root -g root -m 644 "$snap/anterior" "$real"
        sudo rm -rf "$snap"
        return 1
    fi
    sudo rm -rf "$snap"
    echo "Vhosts actualizados ($real)"
    if [ -f /opt/lampp/logs/httpd.pid ]; then
        echo "Recargando Apache..."
        sudo /opt/lampp/lampp reloadapache > /dev/null || { echo "No se ha podido recargar Apache. Reinicia la version activa."; return 1; }
    fi
}

# Comprueba la configuracion de Apache de la version montada (httpd -t, como root porque lee las
# claves de los certificados). Si no la acepta, muestra el error.
function apache_configtest() {
    local httpd=/opt/lampp/bin/httpd out
    [ -x /opt/lampp/apache2/bin/httpd ] && httpd=/opt/lampp/apache2/bin/httpd
    [ -x "$httpd" ] || return 0
    out=$(sudo "$httpd" -f /opt/lampp/etc/httpd.conf -t 2>&1) && return 0
    sed 's/^/  /' <<< "$out" | tail -5
    return 1
}

# /opt tiene que ser del administrador: si es tuyo, cualquier programa con tu usuario (el PHP de
# una web) puede cambiar el enlace /opt/lampp, una version o /opt/lvm-instalador, y lo siguiente que
# se arranque con sudo seria suyo. Solo se cambia /opt; sus carpetas (htdocs, programas) siguen
# siendo de quien eran. Devuelve 0 si ha cambiado algo.
function opt_root() {
    [ -n "$TEST_DIR" ] && return 1
    [ -d /opt ] && [ ! -L /opt ] || return 1
    [ "$(stat -c %u /opt)" == 0 ] && [ -z "$(find /opt -maxdepth 0 -perm /022)" ] && return 1
    echo "/opt vuelve a ser del administrador (sus carpetas siguen siendo de quien eran)"
    run sudo chown root:root /opt || return 1
    run sudo chmod 755 /opt
    return 0
}

# Los vhosts compartidos (y su carpeta, con los certificados de web.local) vuelven a ser del
# administrador si alguna version anterior los hizo tuyos. Tambien /opt (opt_root). Devuelve 0 si
# ha cambiado algo.
function vhosts_root() {
    local real dir changed=1
    opt_root && changed=0
    real=$(readlink -f "$VHOSTS_FILE")
    [ -f "$real" ] && [[ "$real" == /opt/* ]] || return $changed
    dir=$(dirname "$real")
    [ "$(stat -c %u "$real")" == 0 ] && [ "$(stat -c %u "$dir")" == 0 ] && return $changed
    echo "Los vhosts ($real) vuelven a ser del administrador: Apache los lee como root al arrancar"
    run sudo chown root:root "$dir" "$real" || return 1
    run sudo chmod 755 "$dir"
    run sudo chmod 644 "$real"
    [ -d "$dir/ssl" ] && run sudo chown -R root:root "$dir/ssl"
    return 0
}

# Edita /etc/hosts. Sin argumentos, con sudoedit (sudo -e). Con --aplicar <copia>, la ventana ya
# ha editado una copia: comprueba que sigue teniendo localhost, guarda el /etc/hosts actual en
# ~/lvm-copias y escribe la copia encima (con sudo si hace falta; se conservan dueño y permisos)
function edit_hosts() {
    local s=""
    [ -w "$HOSTS_FILE" ] || s=sudo
    if [ "$1" != "--aplicar" ]; then
        local rc
        if [ -n "$s" ]; then
            run sudo -e "$HOSTS_FILE"
        else
            run ${VISUAL:-${EDITOR:-nano}} "$HOSTS_FILE"
        fi
        rc=$?
        # (el navegador deja de aceptar las tiendas que ya no estan falseadas: browser_trust)
        browser_trust --hosts || true
        return $rc
    fi
    local copy=$2 backup="$HOME/lvm-copias/hosts-$(date +%Y%m%d-%H%M%S)" snap="" check
    # (aparte: en la misma linea, $copy aun seria el de fuera)
    check=$copy
    if [ ! -s "$copy" ]; then
        echo "La copia editada ($copy) no existe o esta vacia: no se cambia $HOSTS_FILE."
        return 1
    fi
    # Con sudo, la copia (tuya) se lee una sola vez a una carpeta de root: lo que se comprueba es lo
    # que se escribe, aunque otro programa con tu usuario la cambie mientras escribes la contraseña
    if [ -n "$s" ] && [ "$DRY" -eq 0 ]; then
        sudo -v || return 1
        snap=$(sudo mktemp -d /tmp/lvm-hosts.XXXXXX) || return 1
        sudo chmod 755 "$snap"
        if ! sudo sh -c 'umask 022; cat > "$1"' sh "$snap/hosts" < "$copy"; then
            sudo rm -rf "$snap"
            return 1
        fi
        check=$snap/hosts
        LVM_HOSTS_SNAP=$snap
        trap 'sudo rm -rf "$LVM_HOSTS_SNAP"; trap - RETURN' RETURN
    fi
    if ! grep -qE '^[[:space:]]*(127\.0\.0\.1|::1)[[:space:]].*\blocalhost\b' "$check"; then
        echo "La copia editada no tiene la linea de localhost (127.0.0.1 localhost): no se cambia"
        echo "$HOSTS_FILE, porque el equipo dejaria de encontrarse a si mismo."
        return 1
    fi
    if cmp -s "$check" "$HOSTS_FILE"; then
        echo "No hay cambios en $HOSTS_FILE."
        return 0
    fi
    # La copia se puede cambiar con tu usuario: solo se aceptan lineas nuevas que lleven a este
    # equipo (lo que usa la aplicacion). Una que lleve un dominio a otra direccion (por ejemplo,
    # github.com a un servidor falso) se pone a mano con: lvm-instalador hosts
    local other
    other=$(python3 -I - "$HOSTS_FILE" "$check" <<'EOF'
import sys
def active(path):
    out = set()
    # Las lineas, solo por \n (como las lee el sistema: un \r suelto no corta la linea)
    for line in open(path, encoding="utf-8", errors="replace", newline="\n"):
        f = line.split("#", 1)[0].split()
        if len(f) >= 2:
            out.add((f[0], tuple(f[1:])))
    return out
old = active(sys.argv[1])
for ip, names in sorted(active(sys.argv[2]) - old):
    if not (ip.startswith("127.") or ip in ("::1", "0.0.0.0")):
        print("  %s %s" % (ip, " ".join(names)))
EOF
)
    # Caracteres de control (como \0, que corta la linea para el sistema pero no para Python, o un \r
    # que no va antes de \n: Python cortaria ahi la linea y el sistema no)
    if ! python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read().replace(b"\r\n", b"\n")
sys.exit(1 if any(c < 32 and c not in (9, 10) or c == 127 for c in d) else 0)' "$check"; then
        echo "La copia editada lleva caracteres de control: no se cambia $HOSTS_FILE."
        return 1
    fi
    if [ -n "$other" ]; then
        echo "La copia editada lleva dominios a otros equipos:"
        echo "$other"
        echo "No se cambia $HOSTS_FILE. Si son tuyas, ponlas en la terminal con: lvm-instalador hosts"
        return 1
    fi
    run mkdir -p -m 700 "$HOME/lvm-copias"
    run cp "$HOSTS_FILE" "$backup" || return 1
    echo "Copia del $HOSTS_FILE anterior: $backup"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $s tee $HOSTS_FILE < $copy"
    else
        $s tee "$HOSTS_FILE" < "$check" > /dev/null || return 1
    fi
    echo "$HOSTS_FILE actualizado"
    browser_trust --hosts || true
}

# Nombre de version valido (8.4, 8.2.4, 7.1.33...): sin barras ni .. que lleven a otra carpeta
function valid_version_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && [[ "$1" != *..* ]]
}

function use_lampp() {
    local version=$1

    if ! valid_version_name "$version" || [ ! -d "/opt/lampp-$version" ] || [ -L "/opt/lampp-$version" ]; then
        echo "No existe la version $version de lampp en el sistema"

        return 1
    fi

    if [ -d "/opt/lampp" ] && [ ! -L "/opt/lampp" ]; then
        echo "La carpeta /opt/lampp es una instalacion completa y no un enlace. Registrala primero con: lvm-instalador add <nombre>"

        return 1
    fi

    [ -L /opt/lampp ] && run sudo /opt/lampp/lampp stop
    [ -L /opt/lampp ] && run sudo unlink /opt/lampp
    # Lo que no se haya cerrado al parar (de esta version o de otras anteriores) no puede seguir en
    # memoria al montar la nueva
    close_processes --todos
    # Solo para este equipo (lo que falte), antes de arrancarla. Tambien las demas versiones, por si
    # se arrancan a mano. Si no se puede, no se arranca: quedaria abierta a la red
    secure_all
    if [ $? -eq 2 ] && [ "$DRY" -eq 0 ]; then
        echo "No se arranca lampp-$version: no se ha podido dejar solo para este equipo."
        echo "Prueba con: lvm-instalador asegurar --todas"
        return 1
    fi
    vhosts_root
    run sudo ln -s "/opt/lampp-$version" /opt/lampp
    run sudo /opt/lampp/lampp start
    # MariaDB de XAMPP: sin el usuario anonimo ni los permisos de cualquiera en las bases test
    [ "$DRY" -eq 0 ] && wait_mariadb && secure_mariadb

    echo "Usando lampp $version"
}

# ===========================================================================
# Procesos en memoria: solo los de la version montada
# ===========================================================================
# Todos los LAMPP se arrancan por el enlace /opt/lampp, asi que sus procesos se llaman igual
# ("/opt/lampp/bin/httpd", "/opt/lampp/sbin/mysqld"...) sea cual sea la version. Si al parar una
# version algo se queda vivo (el lampp de XAMPP solo cierra lo que encuentra en sus .pid), sigue en
# memoria aunque se monte otra. De que version es cada proceso se sabe por, en este orden:
#   - la ruta real en su orden (/opt/lampp-8.4/...) o en el .pid de una version (httpd, proftpd,
#     php-fpm, mariadb),
#   - la de su proceso padre (los hijos de Apache, PHP-FPM, ProFTPD y mysqld_safe),
#   - y si solo pone /opt/lampp/: es de la version montada si arranco despues de montarla (el
#     enlace se crea al montar), y si no, de una version anterior.
# (LVM_ENLACE solo para pruebas: sin LVM_PRUEBA no se hace caso)
LAMPP_LINK=/opt/lampp
[ -n "$TEST_DIR" ] && [ -n "$LVM_ENLACE" ] && LAMPP_LINK=$LVM_ENLACE

# P|pid|padre|usuario|version|sobra (1/0)|nombre. Sobran los que no son de la version montada (todos
# si no hay ninguna).
function lampp_processes() {
    python3 -I - "$LAMPP_LINK" <<'EOF'
import glob, os, pwd, re, sys
link = sys.argv[1]
base = os.path.dirname(link)
active, link_time = "", 0
if os.path.islink(link):
    active = os.path.basename(os.path.realpath(link))[len("lampp-"):]
    link_time = os.lstat(link).st_mtime
btime = 0
for line in open("/proc/stat"):
    if line.startswith("btime"):
        btime = int(line.split()[1])
hz = os.sysconf("SC_CLK_TCK")

# .pid de cada version (los de MariaDB de XAMPP no se pueden leer sin ser root: los sustituye la
# regla del padre, mysqld_safe)
by_pidfile = {}
for d in glob.glob(os.path.join(base, "lampp-*")):
    ver = os.path.basename(d)[len("lampp-"):]
    for rel in ("logs/httpd.pid", "var/proftpd.pid", "var/proftpd/proftpd.pid",
                "var/run/php-fpm.pid", "logs/php-fpm.pid", "var/mysql/*.pid"):
        for f in glob.glob(os.path.join(d, rel)):
            # Solo .pid de root: los de daemon o mysql los podria escribir ese usuario (o MariaDB
            # con INTO OUTFILE) para que se cerrara un proceso de la version montada
            try:
                fd = os.open(f, os.O_RDONLY | os.O_NOFOLLOW)
                with os.fdopen(fd) as fh:
                    if os.fstat(fh.fileno()).st_uid == 0:
                        by_pidfile[int(fh.read(64).split()[0])] = ver
            except (OSError, ValueError, IndexError):
                pass

rx = re.compile(re.escape(link) + r"(-[^/\s)|]+)?/")
def clean(s):
    return re.sub(r"[\x00-\x1f\x7f-\x9f|]", "?", s)
procs = {}
for p in os.listdir("/proc"):
    if not p.isdigit():
        continue
    try:
        argv = open("/proc/%s/cmdline" % p, "rb").read().split(b"\0")
        argv = [a.decode("utf-8", "replace") for a in argv if a]
        stat = open("/proc/%s/stat" % p).read()
        uid = os.stat("/proc/%s" % p).st_uid
    except OSError:
        continue
    if not argv:
        continue
    fields = stat[stat.rindex(")") + 2:].split()
    procs[int(p)] = {"argv": argv, "ppid": int(fields[1]),
                     "start": btime + int(fields[19]) / hz, "uid": uid}

# Programas de LAMPP. Un .pid lo puede escribir el usuario con el que corre su servicio (daemon,
# mysql): solo se cree si el proceso es uno de estos (nunca el 1 ni otro programa del sistema, que
# se cerraria con sudo kill) y no dice ya en su ruta de que version es
NAMES = {"httpd", "mysqld", "mariadbd", "mysqld_safe", "mariadbd-safe", "proftpd", "php-fpm"}
def name_of(argv):
    a0 = argv[0]
    if a0.startswith("php-fpm:"):
        return "php-fpm"
    if a0.startswith("proftpd:"):
        return "proftpd"
    n = os.path.basename(a0.split()[0]) if a0.split() else ""
    if n in ("sh", "bash", "dash", "perl") and len(argv) > 1:
        n = os.path.basename(argv[1])
    return n
by_pidfile = {pid: v for pid, v in by_pidfile.items()
              if pid > 1 and pid in procs and name_of(procs[pid]["argv"]) in NAMES
              and not rx.match(procs[pid]["argv"][0])}

def own(pid):
    """None si no es de ningun LAMPP; si lo es, la version de su ruta ('' si solo /opt/lampp/)."""
    a = procs[pid]["argv"]
    # El propio programa (o el script que ejecuta sh/perl) esta en un LAMPP; PHP-FPM cambia su
    # nombre a «php-fpm: master process (/opt/lampp-8.4/php/etc/php-fpm.conf)»
    cands = [a[0]]
    if os.path.basename(a[0]) in ("sh", "bash", "dash", "perl") and len(a) > 1:
        cands.append(a[1])
    if a[0].startswith("php-fpm: master process"):
        cands.append(a[0][a[0].find("(") + 1:])
    for c in cands:
        m = rx.match(c)
        if m:
            return (m.group(1) or "-")[1:]
    if pid in by_pidfile:
        return by_pidfile[pid]
    return None

lampp = {}
for pid in procs:
    v = own(pid)
    if v is not None:
        lampp[pid] = v
# Hijos (trabajadores de Apache, PHP-FPM y ProFTPD, mysqld de mysqld_safe), aunque se llamen distinto
changed = True
while changed:
    changed = False
    for pid, p in procs.items():
        # Solo programas de LAMPP (trabajadores con otro nombre: «php-fpm: pool», «proftpd: ...»)
        if pid not in lampp and p["ppid"] > 1 and p["ppid"] in lampp and name_of(p["argv"]) in NAMES:
            lampp[pid] = ""
            changed = True

def version(pid, seen=()):
    if by_pidfile.get(pid):
        return by_pidfile[pid]
    v = lampp[pid]
    if v:
        return v
    parent = procs[pid]["ppid"]
    if parent in lampp and parent not in seen:
        return version(parent, seen + (pid,))
    # Solo /opt/lampp/: de la montada si arranco despues de montarla
    if active and procs[pid]["start"] >= link_time - 1:
        return active
    return "?"

for pid in sorted(lampp):
    p = procs[pid]
    v = version(pid)
    try:
        user = pwd.getpwuid(p["uid"]).pw_name
    except KeyError:
        user = str(p["uid"])
    a0 = p["argv"][0]
    name = a0.split(":")[0] if ":" in a0 and not a0.startswith("/") else os.path.basename(a0)
    if name in ("sh", "bash", "dash", "perl") and len(p["argv"]) > 1:
        name = os.path.basename(p["argv"][1])
    # Cualquier proceso elige su propio nombre: sin saltos de linea ni «|», que meterian lineas o
    # campos falsos (un pid que despues se cierra con sudo kill)
    print("P|%d|%d|%s|%s|%d|%s" % (pid, p["ppid"], clean(user), clean(v), int(v != active),
                                   clean(name or a0)))
EOF
}

# Resumen de los procesos que sobran: «lampp-8.4: httpd ×3, mysqld; version anterior: ...»
function stray_summary() {
    lampp_processes | awk -F'|' '$6 == 1 {
        v = ($5 == "?") ? "version anterior" : "lampp-" $5
        n[v "|" $7]++; if (!(v in seen)) { seen[v] = 1; order[++k] = v }
    } END {
        for (i = 1; i <= k; i++) {
            out = ""
            for (key in n) { split(key, f, "|"); if (f[1] == order[i]) out = out (out ? ", " : "") f[2] (n[key] > 1 ? " ×" n[key] : "") }
            printf "%s%s: %s", (i > 1 ? "; " : ""), order[i], out
        }
    }'
}

# cerrar-procesos [--todos]: cierra los procesos de LAMPP que no son de la version montada (con
# --todos, tambien los de la montada: se usa justo despues de pararla o desmontarla). Primero les da
# unos segundos por si estan terminando solos; despues TERM (MariaDB y Apache se cierran bien con
# el) empezando por los vigilantes (mysqld_safe volveria a arrancar mysqld), y KILL a los que sigan.
function close_processes() {
    local all=$1 list pids wait sure
    function _stray() {
        lampp_processes | awk -F'|' -v all="$all" '$6 == 1 || all == "--todos"'
    }
    list=$(_stray)
    [ -z "$list" ] && return 0
    if [ "$all" == "--todos" ] && [ "$DRY" -eq 0 ]; then
        for wait in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
            sleep 1
            list=$(_stray)
            [ -z "$list" ] && return 0
        done
    fi
    echo "Procesos de LAMPP que siguen en memoria y no deberian:"
    awk -F'|' '{ printf "  %s (%s, pid %s, %s)\n", $7, ($5 == "?" ? "version anterior" : "lampp-" $5), $2, $4 }' <<< "$list"
    # Primero los vigilantes que vuelven a arrancar lo que se cierra
    pids=$(awk -F'|' '$7 ~ /^(mysqld_safe|mariadbd-safe)$/ { print $2 }' <<< "$list")
    pids="$pids $(awk -F'|' '$7 !~ /^(mysqld_safe|mariadbd-safe)$/ { print $2 }' <<< "$list")"
    pids=$(kill_pids $pids)
    [ -z "$pids" ] && return 1
    echo "Cerrandolos..."
    run sudo kill -TERM -- $pids 2> /dev/null
    [ "$DRY" -eq 1 ] && return 0
    # 15 s; MariaDB, hasta 90 s (con TERM guarda todo antes de salir: no se le corta a medias)
    for wait in $(seq 1 90); do
        sleep 1
        list=$(_stray)
        [ -z "$list" ] && { close_done "$all"; return 0; }
        [ "$wait" -ge 15 ] && ! awk -F'|' '$7 ~ /^(mysqld|mariadbd)$/ { f = 1 } END { exit !f }' <<< "$list" && break
        [ "$wait" -eq 15 ] && echo "Esperando a que MariaDB termine de guardar y se cierre..."
    done
    # Los que no han atendido a TERM (solo si siguen siendo los mismos procesos)
    sure=$(kill_pids $(awk -F'|' '{ print $2 }' <<< "$list"))
    [ -z "$sure" ] && return 1
    echo "Forzando el cierre de: $sure"
    sudo kill -KILL -- $sure 2> /dev/null
    sleep 1
    list=$(_stray)
    if [ -n "$list" ]; then
        echo "No se han podido cerrar:"
        awk -F'|' '{ printf "  %s (pid %s)\n", $7, $2 }' <<< "$list"
        return 1
    fi
    close_done "$all"
}

# Solo numeros de proceso de verdad (sin signo, ni 0 ni 1) antes de pasarlos a sudo kill: un -1
# cerraria todos los procesos del equipo. kill_pids <pid>...
function kill_pids() {
    local p out=""
    for p in "$@"; do
        [[ "$p" =~ ^[1-9][0-9]{0,9}$ ]] && [ "$p" -gt 1 ] && out="$out $p"
    done
    echo "${out# }"
}

function close_done() {
    if [ "$1" == "--todos" ]; then
        echo "Cerrados: no queda ningun proceso de LAMPP en memoria."
    else
        echo "Cerrados: solo queda en memoria la version montada."
    fi
}

function list_lampp() {
    echo "Estas son las versiones disponibles"

    lampp_dirs
}

# ===========================================================================
# Proyectos de /opt/htdocs
# ===========================================================================

# Enlace de htdocs al que apunta el DocumentRoot de un vhost (por ejemplo web.local). Vacio si no hay.
function project_link() {
    local name

    [ -f "$VHOSTS_FILE" ] || return 1
    for name in $(grep -v '^[[:space:]]*#' "$VHOSTS_FILE" \
        | grep -oP 'DocumentRoot\s+"?[^"\s]*/htdocs/\K[^/"\s]+' | awk '!seen[$0]++'); do
        [ -L "$HTDOCS_DIR/$name" ] && echo "$name" && return 0
    done

    return 1
}

# Para la ventana: E|enlace|carpeta a la que apunta, P|carpeta|base de datos|.php-version|tipo por
# cada proyecto (base leida de wp-config.php, PrestaShop o .env; tipo ps o wp) y R|base|carpeta
# recordadas
function gui_projects() {
    local link=$(project_link)

    # Sin vhost: se creara web.local al cargar el primer proyecto (cuarto campo N)
    if [ -z "$link" ]; then
        echo "E|$PROJECT_VHOST||N"
    else
        # (sin proyecto cargado, el enlace apunta a la pagina vacia: carpeta vacia para la ventana)
        echo "E|$link|$(readlink "$HTDOCS_DIR/$link" | sed 's:/*$::' | grep -vxF "$EMPTY_PROJECT")"
    fi
    python3 -I - "$HTDOCS_DIR" <<'EOF'
import os, re, sys
root = sys.argv[1]
rules = [
    ("wp-config.php", r"""^[ \t]*define\(\s*['"]DB_NAME['"]\s*,\s*['"]([^'"]+)"""),
    ("app/config/parameters.php", r"""['"]database_name['"]\s*=>\s*['"]([^'"]+)"""),
    ("config/settings.inc.php", r"""define\(\s*['"]_DB_NAME_['"]\s*,\s*['"]([^'"]+)"""),
    (".env", r"""^\s*DB_DATABASE\s*=\s*["']?([^"'\s#]+)"""),
]
for name in sorted(os.listdir(root), key=str.lower):
    path = os.path.join(root, name)
    # Un nombre con | o saltos de linea romperia las lineas que lee la ventana
    if name.startswith(".") or re.search(r"[|\x00-\x1f]", name) or os.path.islink(path) \
            or not os.path.isdir(path):
        continue
    db = ""
    for rel, rx in rules:
        try:
            if not os.path.isfile(os.path.join(path, rel)) or os.path.getsize(os.path.join(path, rel)) > 2000000:
                raise OSError("no es un fichero normal")
            with open(os.path.join(path, rel), errors="replace") as f:
                m = re.search(rx, f.read(), re.M)
        except OSError:
            continue
        if m:
            db = m.group(1)
            break
    # Solo nombres de base validos (la configuracion la trae el proyecto)
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", db):
        db = ""
    ver = ""
    try:
        if not os.path.isfile(os.path.join(path, ".php-version")) or os.path.getsize(os.path.join(path, ".php-version")) > 2000000:
            raise OSError("no es un fichero normal")
        with open(os.path.join(path, ".php-version")) as f:
            ver = re.sub(r"[^0-9.]", "", f.read().strip())[:16]
    except OSError:
        pass
    # Tipo: ps (tienda PrestaShop, como is_prestashop) o wp (WordPress)
    kind = ""
    if "prestashop" in name.lower() or os.path.isdir(os.path.join(path, "src/PrestaShopBundle")) \
            or os.path.isfile(os.path.join(path, "classes/PrestaShopAutoload.php")):
        kind = "ps"
    elif os.path.isfile(os.path.join(path, "wp-config.php")) or \
            os.path.isdir(os.path.join(path, "wp-includes")):
        kind = "wp"
    print("P|%s|%s|%s|%s" % (name, db, ver, kind))
EOF
    [ -f "$PROJECTS_FILE" ] && grep -E '^[A-Za-z0-9_][A-Za-z0-9_-]*=[^|]+$' "$PROJECTS_FILE" | sed 's/^\([^=]*\)=/R|\1|/'
    return 0
}

# Crea el vhost web.local (http y https, sin cache en el navegador) con DocumentRoot en el enlace
# htdocs/web.local, su certificado autofirmado y su linea en /etc/hosts. Lo usa load_project cuando
# ningun vhost apunta a un enlace de htdocs (equipos sin vhosts propios).
function create_project_vhost() {
    local name=$PROJECT_VHOST s="" ssl=$(dirname "$VHOSTS_FILE")/ssl

    if [ -e "$HTDOCS_DIR/$name" ] && [ ! -L "$HTDOCS_DIR/$name" ]; then
        echo "$HTDOCS_DIR/$name ya existe y no es un enlace. Cambiale el nombre para poder crear el vhost $name."

        return 1
    fi
    if [ -f "$VHOSTS_FILE" ] && grep -v '^[[:space:]]*#' "$VHOSTS_FILE" \
        | grep -qiE "^[[:space:]]*ServerName[[:space:]]+${name//./\\.}(:[0-9]+)?[[:space:]]*$"; then
        echo "Ya hay un vhost $name en $VHOSTS_FILE, pero su DocumentRoot no es el enlace $HTDOCS_DIR/$name."
        echo "Cambia su DocumentRoot a \"/opt/lampp/htdocs/$name\" y vuelve a cargar el proyecto."

        return 1
    fi

    echo "Creando el vhost $name (http y https) en $VHOSTS_FILE..."
    [ -w "$(dirname "$VHOSTS_FILE")" ] || s=sudo
    make_selfsigned "$name" "www.$name" "$ssl/$name.crt" "$ssl/$name.key" || return 1

    local admin=$(server_admin)
    local block="
# $name: apunta al proyecto cargado (enlace $HTDOCS_DIR/$name), creado por lvm-instalador
<VirtualHost *:$PORT_HTTP>
    ServerAdmin $admin
    DocumentRoot \"/opt/lampp/htdocs/$name\"
    ServerName $name
    ServerAlias www.$name
    # Sin cache en el navegador: al cambiar de proyecto no sale el anterior
    <IfModule headers_module>
        Header always set Cache-Control \"no-store\"
    </IfModule>
</VirtualHost>

<VirtualHost *:$PORT_HTTPS>
    ServerAdmin $admin
    DocumentRoot \"/opt/lampp/htdocs/$name\"
    ServerName $name
    ServerAlias www.$name
    SSLEngine on
    SSLCertificateFile \"$ssl/$name.crt\"
    SSLCertificateKeyFile \"$ssl/$name.key\"
    <IfModule headers_module>
        Header always set Cache-Control \"no-store\"
    </IfModule>
</VirtualHost>"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] añadir a $VHOSTS_FILE:$block"
    else
        printf '%s\n' "$block" | $s tee -a "$VHOSTS_FILE" > /dev/null || return 1
    fi

    if ! grep -qE "^[^#]*[[:space:]]${name//./\\.}([[:space:]]|$)" "$HOSTS_FILE" 2> /dev/null; then
        echo "Añadiendo $name a $HOSTS_FILE..."
        [ -w "$HOSTS_FILE" ] && s="" || s=sudo
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] 127.0.0.1 $name www.$name en $HOSTS_FILE"
        else
            printf '127.0.0.1 %s www.%s\n' "$name" "$name" | $s tee -a "$HOSTS_FILE" > /dev/null || return 1
        fi
    fi
    # (si no se puede, el aviso de la ventana tiene el boton Confiar)
    browser_trust "$name" || true

    return 0
}

# Carpeta de proyecto valida: existe en htdocs, no es un enlace y su nombre solo lleva letras sin
# acentos, numeros, espacios, punto, _ y - (se escribe entre comillas en los vhosts: unas comillas
# o un salto de linea en el nombre meterian directivas en la configuracion de Apache)
function valid_project() {
    local folder=$1 rx='^[A-Za-z0-9_][A-Za-z0-9 ._-]*$'
    if [ -z "$folder" ] || [ ! -d "$HTDOCS_DIR/$folder" ] || [ -L "$HTDOCS_DIR/$folder" ] || [[ "$folder" == */* ]]; then
        echo "No existe el proyecto $HTDOCS_DIR/$folder"

        return 1
    fi
    if ! [[ "$folder" =~ $rx ]]; then
        echo "El nombre de la carpeta $folder lleva caracteres que no se admiten (solo letras sin"
        echo "acentos, numeros, espacios, punto, _ y -). Cambiale el nombre y vuelve a intentarlo."

        return 1
    fi
}

# ¿Se puede escribir este fichero sin salirse de la carpeta del proyecto? Ni el fichero ni las
# carpetas de su ruta pueden ser enlaces que lleven fuera: un repositorio podria traer wp-config.php
# como enlace a un fichero del sistema, y con sudo se escribiria encima.
function project_path_ok() {
    local root=$1 path=$2 real_root real_dir
    [ -L "$path" ] && return 1
    real_root=$(readlink -f "$root") real_dir=$(readlink -f "$(dirname "$path")")
    [ -n "$real_root" ] && [[ "$real_dir" == "$real_root" || "$real_dir" == "$real_root"/* ]]
}

# Escribe un fichero de un proyecto, con sudo si es de otro usuario (los que creo Apache como daemon).
# Con sudo, root recorre la ruta carpeta a carpeta sin seguir enlaces (si entre medias cambiaran una
# carpeta por un enlace, falla en lugar de escribir en otro sitio), borra el fichero y lo crea de
# nuevo, tuyo. El contenido lo lee tu usuario (root no abre el fichero de origen).
PROJECT_WRITE_PY='
import os, sys
dest, uid, gid, top = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
data = sys.stdin.buffer.read()
# La carpeta se resuelve aqui (como root, no antes con tu usuario) y tiene que quedar dentro de
# htdocs: si un proyecto se cambia por un enlace a otra carpeta del sistema, no se escribe alli
top = os.path.realpath(top)
real = os.path.join(os.path.realpath(os.path.dirname(dest)), os.path.basename(dest))
if not (real.startswith(top + "/") and os.path.basename(dest) not in ("", ".", "..")):
    sys.exit("%s no esta dentro de %s: no se escribe" % (dest, top))
parts = [p for p in real.split("/") if p]
fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
for p in parts[:-1]:
    nfd = os.open(p, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
    os.close(fd)
    fd = nfd
name = parts[-1]
try:
    os.unlink(name, dir_fd=fd)
except FileNotFoundError:
    pass
out = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644, dir_fd=fd)
os.write(out, data)
os.fchown(out, uid, gid)
os.close(out)
'
function project_write() {
    local src=$1 dest=$2
    if [ -w "$dest" ] || { [ ! -e "$dest" ] && [ -w "$(dirname "$dest")" ]; }; then
        run cp "$src" "$dest"
    else
        [ -d "$(dirname "$dest")" ] || return 1
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] sudo (sin seguir enlaces, dentro de $HTDOCS_DIR) $dest < $src"
            return 0
        fi
        sudo python3 -I -c "$PROJECT_WRITE_PY" "$dest" "$(id -u)" "$(id -g)" "$HTDOCS_DIR" < "$src"
    fi
}

# Carpeta oculta de htdocs a la que apunta el enlace del vhost de los proyectos (web.local) cuando no
# hay ninguno cargado: una pagina que lo dice (no sale en la lista de proyectos)
EMPTY_PROJECT=.lvm-sin-proyecto

# desmontar-proyecto: el vhost de los proyectos (web.local) deja de apuntar al proyecto cargado y
# apunta a una pagina que dice que no hay ninguno. El enlace sigue existiendo: si se borrara, el
# gestor ya no reconoceria el vhost y al cargar otro proyecto intentaria crearlo de nuevo. Los
# dominios falseados de una tienda PrestaShop dejan de estarlo (vuelven a llevar a la web real)
function unload_project() {
    local link sudo="" dir=$HTDOCS_DIR/$EMPTY_PROJECT page

    link=$(project_link)
    if [ -z "$link" ]; then
        echo "No hay ningun vhost de proyectos (como $PROJECT_VHOST): no hay nada que desmontar"

        return 1
    fi
    if [ "$(readlink "$HTDOCS_DIR/$link" | sed 's:/*$::')" == "$EMPTY_PROJECT" ]; then
        echo "No hay ningun proyecto cargado en $link"

        return 0
    fi
    if [ -L "$dir" ] || { [ -e "$dir" ] && [ ! -d "$dir" ]; }; then
        echo "$dir no es una carpeta: borrala o cambiale el nombre y vuelve a intentarlo"

        return 1
    fi
    [ -w "$HTDOCS_DIR" ] || sudo=sudo
    if [ ! -d "$dir" ]; then
        run $sudo mkdir -m 755 "$dir" || return 1
    fi
    if [ ! -f "$dir/index.html" ] && [ "$DRY" -eq 0 ]; then
        page=$(mktemp) || return 1
        cat > "$page" <<'HTML'
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Sin proyecto</title>
<style>body{font-family:sans-serif;background:#2b2b2b;color:#ddd;display:flex;align-items:center;
justify-content:center;height:90vh;margin:0}div{text-align:center}h1{font-weight:500}p{color:#999}</style>
</head><body><div><h1>No hay ningún proyecto cargado</h1>
<p>Carga uno en lvm-instalador: Versiones, Cargar proyecto.</p></div></body></html>
HTML
        project_write "$page" "$dir/index.html"
        rm -f "$page"
    fi
    run $sudo unlink "$HTDOCS_DIR/$link" || return 1
    run $sudo ln -s "$EMPTY_PROJECT/" "$HTDOCS_DIR/$link" || return 1
    # (sin dominios falseados: los de una tienda PrestaShop vuelven a llevar a la web real)
    hosts_fake cargar || return 1
    # Cada proceso de PHP recuerda a donde apuntaba el enlace (realpath_cache, 120 s)
    if [ -f /opt/lampp/logs/httpd.pid ]; then
        echo "Recargando Apache para que PHP deje de servir el proyecto..."
        run sudo /opt/lampp/lampp reloadapache > /dev/null || { echo "No se ha podido recargar Apache. Reinicia la version activa."; return 1; }
    fi
    echo "Proyecto desmontado: $link ya no apunta a ningun proyecto"
}

# ¿Direccion de un repositorio que se puede clonar? Solo https:// o ssh (git@servidor:ruta o
# ssh://git@servidor/ruta), con servidor y ruta sin caracteres raros ni un - al principio (git los
# tomaria como opciones). Nada de file://, ext:: ni rutas locales
function git_url_ok() {
    local host='[A-Za-z0-9][A-Za-z0-9.-]*' path='[A-Za-z0-9_~][A-Za-z0-9._~/-]*'
    [[ "$1" =~ ^https://$host(:[0-9]{1,5})?/$path$ ]] || [[ "$1" =~ ^git@$host:$path$ ]] \
        || [[ "$1" =~ ^ssh://git@$host(:[0-9]{1,5})?/$path$ ]]
}

# montar-proyecto <url de git> <carpeta> <version> <base> [volcado]: proyecto nuevo desde un
# repositorio (GitHub u otro). Lo clona en htdocs, lo carga en esa version de PHP, crea su BBDD y,
# si se indica, carga en ella el volcado (con la carga protegida de importar-bd). El clon va con tu
# usuario (sin sudo), sin submodulos ni ganchos y solo por https o ssh; sin preguntas: un
# repositorio privado por https falla (se usa la direccion SSH con tu clave)
function mount_project() {
    local url=$1 folder=$2 version=$3 db=$4 file=$5 dest dir owner
    if [ -z "$url" ] || [ -z "$folder" ] || [ -z "$version" ] || [ -z "$db" ]; then
        echo "Uso: lvm-instalador montar-proyecto <url de git> <carpeta> <version> <base de datos> [volcado]"

        return 1
    fi
    if ! git_url_ok "$url"; then
        echo "La direccion del repositorio no es valida: usa https://servidor/usuario/repositorio(.git)"
        echo "o git@servidor:usuario/repositorio.git"

        return 1
    fi
    if ! [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$ ]] || [ "$folder" == "$EMPTY_PROJECT" ]; then
        echo "El nombre de la carpeta solo puede llevar letras sin acentos, numeros, punto, _ y -"

        return 1
    fi
    dest=$HTDOCS_DIR/$folder
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        echo "Ya existe $dest: elige otro nombre para la carpeta"

        return 1
    fi
    dir="${TEST_DIR:-/opt}/lampp-$version"
    if ! valid_version_name "$version" || [ ! -d "$dir" ] || [ -L "$dir" ]; then
        echo "No existe la version $version"

        return 1
    fi
    db_valid_name "$db" || return 1
    owner=$(data_owner "$dir"); owner="${TEST_DIR:-/opt}/lampp-${owner:-$version}"
    if db_names "$owner" | grep -qxF "$db"; then
        echo "Ya hay una BBDD $db en esa version: elige otro nombre"

        return 1
    fi
    if [ -n "$file" ] && { [ ! -f "$file" ] || [ -L "$file" ]; }; then
        echo "No existe el fichero $file"

        return 1
    fi
    if ! command -v git > /dev/null; then
        echo "Hace falta git para clonar el repositorio: sudo apt install git"

        return 1
    fi
    if [ ! -w "$HTDOCS_DIR" ]; then
        echo "No puedes escribir en $HTDOCS_DIR: el proyecto se clona con tu usuario, sin sudo"

        return 1
    fi

    echo "1/3 Clonando $url en $dest..."
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] git clone --no-recurse-submodules -- $url $dest"
        echo "2/3 [simulacion] cargar-proyecto $folder $version $db"
        echo "3/3 [simulacion] BBDD $db: $([ -n "$file" ] && echo "importar-bd $file $db --crear" || echo "crear-bd $db")"

        return 0
    fi
    # Por ssh, solo servidores cuya clave ya conoces (~/.ssh/known_hosts) o las publicadas de GitHub,
    # GitLab y Bitbucket: un servidor nuevo no se acepta sin mirar (en una red ajena o con /etc/hosts
    # cambiado te darian otro repositorio, y su PHP corre con tu usuario)
    local known
    # (en /tmp y no en $TMPDIR, que viene de la sesion: va entre comillas en GIT_SSH_COMMAND)
    known=$(mktemp /tmp/lvm-conocidos.XXXXXX) || return 1
    printf '%s\n' "$GIT_KNOWN_HOSTS" > "$known"
    # Sin terminal (git y ssh leen tu configuracion: no pueden usar el permiso de sudo recordado ni
    # quedarse leyendola) y sin git-lfs (su .lfsconfig llevaria las descargas a otro servidor)
    if ! GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false GIT_LFS_SKIP_SMUDGE=1 \
        GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o 'UserKnownHostsFile=~/.ssh/known_hosts $known'" \
        no_tty git -c protocol.allow=never -c protocol.https.allow=always -c protocol.ssh.allow=always \
            -c core.hooksPath=/dev/null -c credential.helper= \
            -c filter.lfs.process= -c filter.lfs.smudge= -c filter.lfs.required=false \
            clone --no-recurse-submodules -- "$url" "$dest"; then
        rm -f "$known"
        echo "No se ha podido clonar el repositorio. Si es privado, usa su direccion SSH"
        echo "(git@github.com:usuario/repositorio.git) con tu clave SSH ya configurada en GitHub."
        echo "Si es por SSH a un servidor que no es GitHub, GitLab ni Bitbucket y dice «Host key"
        echo "verification failed», conectate una vez a mano para comprobar y aceptar su clave"
        echo "(ssh -T git@servidor) y vuelve a intentarlo."

        return 1
    fi
    rm -f "$known"
    htdocs_close_world "$dest"
    # Apuntada como montada desde un repositorio: el dominio de su base no se falsea solo (ver
    # load_project_domain)
    mkdir -p "$HOME/.lvm-instalador" && { grep -qxF -- "$folder" "$REPO_PROJECTS_FILE" 2> /dev/null \
        || printf '%s\n' "$folder" >> "$REPO_PROJECTS_FILE"; }

    echo "2/3 Cargando $folder en lampp-$version..."
    load_project "$folder" "$version" "$db" || { echo "El proyecto esta clonado en $dest, pero no se ha podido cargar."; return 1; }

    echo "3/3 BBDD $db..."
    if [ -n "$file" ]; then
        import_database "$file" "$db" --crear || return 1
    else
        create_database "$db" || return 1
    fi
    # Tienda PrestaShop: su dominio esta en la base (shop_url), que al cargarla aun no existia. Ahora
    # que esta, su vhost, su certificado y el dominio falseado
    if [ -n "$file" ] && is_prestashop "$folder"; then
        load_project_domain "$folder" "$db" || return 1
    fi
    echo "Proyecto nuevo montado: $folder en lampp-$version con la BBDD $db"
}

# Carga un proyecto: activa la version (si se indica y no es la activa) y apunta el enlace del vhost
# a la carpeta del proyecto (lo mismo que unlink web.local; ln -s <carpeta>/ web.local)
function load_project() {
    local folder=${1%/} version=$2 link sudo="" secured=1

    valid_project "$folder" || return 1
    if [ -n "$version" ] && { ! valid_version_name "$version" || [ ! -d "/opt/lampp-$version" ]; }; then
        echo "No existe la version $version de lampp en el sistema"

        return 1
    fi

    link=$(project_link)
    if [ -z "$link" ]; then
        create_project_vhost || return 1
        link=$PROJECT_VHOST
    fi

    if [ "$folder" == "$link" ]; then
        echo "$folder es el propio enlace del vhost, no un proyecto"

        return 1
    fi
    htdocs_close_world "$HTDOCS_DIR/$folder"

    [ -w "$HTDOCS_DIR" ] || sudo=sudo
    if [ -L "$HTDOCS_DIR/$link" ]; then
        run $sudo unlink "$HTDOCS_DIR/$link" || return 1
    fi
    run $sudo ln -s "$folder/" "$HTDOCS_DIR/$link" || return 1

    # Apache con tu usuario (User/Group), si la version no lo tiene: se aplica al arrancar o recargar
    local web_dir=$(active_dir)
    [ -n "$version" ] && web_dir=/opt/lampp-$version
    [ -n "$web_dir" ] && ensure_web_user "$web_dir"
    # Solo para este equipo: si cambia algo con la version en marcha, se reinicia para aplicarlo
    if [ -n "$web_dir" ]; then
        secure_lampp "$web_dir"
        case $? in
            0) secured=0 ;;
            2) secure_failed 2 "$web_dir" && return 1 ;;
        esac
        vhosts_root && secured=0
    fi

    if [ -n "$version" ] && [ "$(readlink /opt/lampp)" != "/opt/lampp-$version" ]; then
        echo "Activando lampp-$version..."
        use_lampp "$version" || return 1
    elif [ -L /opt/lampp ] && ! lampp_running; then
        echo "Arrancando $(readlink /opt/lampp | sed 's:^/opt/::')..."
        run sudo /opt/lampp/lampp start
    elif [ $secured -eq 0 ]; then
        echo "Reiniciando $(readlink /opt/lampp | sed 's:^/opt/::') para que solo se pueda entrar desde este equipo..."
        run sudo /opt/lampp/lampp restart > /dev/null || { echo "No se ha podido reiniciar. Reinicia la version activa."; return 1; }
    elif [ -f /opt/lampp/logs/httpd.pid ]; then
        # Cada proceso de PHP recuerda a donde apuntaba el enlace (realpath_cache, 120 s) y seguiria
        # sirviendo el proyecto anterior: recarga suave de Apache (y PHP-FPM en las pilas propias)
        echo "Recargando Apache para que PHP no siga sirviendo el proyecto anterior..."
        run sudo /opt/lampp/lampp reloadapache > /dev/null || { echo "No se ha podido recargar Apache. Reinicia la version activa."; return 1; }
    fi

    # Tienda PrestaShop: su dominio con vhost, certificado y falseado en /etc/hosts. Otro proyecto:
    # ningun dominio falseado
    # La base con la que se carga queda asociada a la carpeta (wp-config.php la usa la proxima vez)
    [[ "$3" =~ ^[A-Za-z0-9_-]+$ ]] && remember_project "$3" "$folder"
    load_project_domain "$folder" "$3" || return 1

    echo "Proyecto cargado: $link -> $folder$([ -L /opt/lampp ] && echo " ($(readlink /opt/lampp | sed 's:^/opt/::'))")"
}

# ===========================================================================
# Tiendas PrestaShop: dominio propio, certificado y /etc/hosts falseado
# ===========================================================================
# PrestaShop redirige siempre al dominio guardado en su base (tabla shop_url), asi que no se puede
# ver por web.local. Se monta como en el manual de XAMPP del equipo: un vhost por dominio (http y
# https) con DocumentRoot en la carpeta del proyecto, un certificado autofirmado en /opt/config/ssl
# (junto al de web.local) y el dominio falseado en /etc/hosts (127.0.0.1). Al cargar otro proyecto,
# el dominio deja de estar falseado y vuelve a llevar a la web real. Hasta la 1.39 iban en
# /etc/ssl/certs, donde el sistema los toma como certificados de confianza (los pasa
# arreglar-certificados). (LVM_SSL_CERTS/LVM_SSL_KEYS solo para pruebas)
SSL_CERTS_DIR=${LVM_SSL_CERTS:-$(dirname "$VHOSTS_FILE")/ssl}
SSL_KEYS_DIR=${LVM_SSL_KEYS:-$(dirname "$VHOSTS_FILE")/ssl}
OWN_SSL_DIR=$(dirname "$VHOSTS_FILE")/ssl

# Base de datos y prefijo de tablas de una tienda PrestaShop: base|prefijo. Nada si no lo es.
function ps_config() {
    python3 -I - "$HTDOCS_DIR/$1" <<'EOF'
import os, re, sys
root = sys.argv[1]
rules = [
    ("app/config/parameters.php",
     r"""['"]database_name['"]\s*=>\s*['"]([^'"]+)""", r"""['"]database_prefix['"]\s*=>\s*['"]([^'"]*)"""),
    ("config/settings.inc.php",
     r"""define\(\s*['"]_DB_NAME_['"]\s*,\s*['"]([^'"]+)""", r"""define\(\s*['"]_DB_PREFIX_['"]\s*,\s*['"]([^'"]*)"""),
]
for rel, rx_db, rx_prefix in rules:
    try:
        if not os.path.isfile(os.path.join(root, rel)) or os.path.getsize(os.path.join(root, rel)) > 2000000:
            raise OSError("no es un fichero normal")
        with open(os.path.join(root, rel), errors="replace") as f:
            text = f.read()
    except OSError:
        continue
    db, prefix = re.search(rx_db, text), re.search(rx_prefix, text)
    if db:
        print("%s|%s" % (db.group(1), prefix.group(1) if prefix else "ps_"))
        break
EOF
}

# Virtual hosts sin comentar de VHOSTS_FILE: puerto|carpeta de htdocs|ServerName|alias|certificado|clave
function vhosts_info() {
    [ -f "$VHOSTS_FILE" ] || return 0
    python3 -I - "$VHOSTS_FILE" <<'EOF'
import re, sys
block = None
for raw in open(sys.argv[1], errors="replace"):
    line = raw.split("#", 1)[0].strip() if raw.lstrip().startswith("#") else raw.strip()
    if not line:
        continue
    m = re.match(r"<VirtualHost\s+[^>]*:(\d+)\s*>", line, re.I)
    if m:
        block = {"port": m.group(1), "folder": "", "name": "", "alias": [], "crt": "", "key": ""}
        continue
    if block is None:
        continue
    if re.match(r"</VirtualHost>", line, re.I):
        if block["name"]:
            print("|".join([block["port"], block["folder"], block["name"].lower(),
                            " ".join(a.lower() for a in block["alias"]), block["crt"], block["key"]]))
        block = None
        continue
    key, value = (re.split(r"\s+", line, 1) + [""])[:2]
    value = value.strip().strip('"')
    key = key.lower()
    if key == "documentroot":
        m = re.search(r"/htdocs/([^/\s]+)", value)
        block["folder"] = m.group(1) if m else ""
    elif key == "servername":
        block["name"] = value.split(":")[0]
    elif key == "serveralias":
        block["alias"] += value.split()
    elif key == "sslcertificatefile":
        block["crt"] = value
    elif key == "sslcertificatekeyfile":
        block["key"] = value
EOF
}

function valid_domain() {
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$ ]]
}

# Certificado autofirmado (no de CA) de <dominio> y <alias> en <crt> y su clave en <key>:
# make_selfsigned <dominio> <alias> <crt> <key>. Si la carpeta es de root, openssl corre como root en
# una carpeta temporal de root (si no, con tu usuario en una tuya), y solo si <crt> y <key> estan en las
# carpetas de certificados del gestor: las rutas de un vhost las puede haber escrito cualquier programa
# tuyo (la copia de los vhosts es tuya) y root no debe crear ni machacar ficheros donde digan.
function make_selfsigned() {
    local cn=$1 alt=$2 crt=$3 key=$4 tmp s="" d ok_crt=0 ok_key=0
    for d in "$SSL_CERTS_DIR" "$OWN_SSL_DIR"; do [ "$(dirname "$crt")" == "$d" ] && ok_crt=1; done
    for d in "$SSL_KEYS_DIR" "$OWN_SSL_DIR"; do [ "$(dirname "$key")" == "$d" ] && ok_key=1; done
    if [ $ok_crt -eq 0 ] || [ $ok_key -eq 0 ] || ! [[ "$(basename "$crt")" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.(crt|pem)$ ]] \
            || ! [[ "$(basename "$key")" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.(key|pem)$ ]] || ! valid_domain "$cn"; then
        echo "El certificado de $cn ($crt) no esta en la carpeta de certificados del gestor ($OWN_SSL_DIR): no se crea."
        echo "Pulsa Arreglarlos en el aviso de certificados (Versiones) o: lvm-instalador arreglar-certificados"
        return 1
    fi
    { [ -d "$(dirname "$crt")" ] && [ -w "$(dirname "$crt")" ] && [ -w "$(dirname "$key")" ]; } || s=sudo
    [ -d "$(dirname "$crt")" ] && [ -d "$(dirname "$key")" ] || run $s mkdir -p "$(dirname "$crt")" "$(dirname "$key")" || return 1
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] certificado autofirmado de $cn en $crt (clave en $key)"
        return 0
    fi
    # Con sudo, el certificado y la clave los crea root en una carpeta de root: en una tuya, otro
    # programa tuyo podria cambiarlos por los suyos antes de que root los copie
    if [ -n "$s" ]; then
        tmp=$(sudo mktemp -d /tmp/lvm-cert.XXXXXX) && sudo chmod 700 "$tmp" || return 1
    else
        tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-cert.XXXXXX") || return 1
    fi
    if ! $s sh -c 'umask 077; exec openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/CN=$2" \
            -addext "basicConstraints=critical,CA:FALSE" -addext "subjectAltName=$3" \
            -keyout "$1/key" -out "$1/crt"' sh "$tmp" "$cn" "DNS:$cn${alt:+,DNS:$alt}" > /dev/null 2>&1; then
        $s rm -rf "$tmp"
        echo "No se ha podido crear el certificado de $cn"
        return 1
    fi
    if [ -n "$s" ]; then
        # (install cambia el fichero por otro: si el de destino fuera un enlace, no lo sigue)
        $s install -o 0 -g 0 -m 644 "$tmp/crt" "$crt" && $s install -o 0 -g 0 -m 600 "$tmp/key" "$key"
    else
        install -m 644 "$tmp/crt" "$crt" && install -m 600 "$tmp/key" "$key"
    fi || { $s rm -rf "$tmp"; echo "No se ha podido guardar el certificado de $cn"; return 1; }
    $s rm -rf "$tmp"
    return 0
}

# ===========================================================================
# Certificados de los vhosts en los que confia todo el equipo
# ===========================================================================
# Un certificado de proyecto que el equipo da por bueno para todo (en /etc/ssl/certs, o de CA, o
# firmado por una CA local sin limite de dominios cuya clave esta en tu carpeta) deja que quien
# consiga su clave falsifique cualquier web real (el banco, Google) en este equipo. Ver CERTS_PY.
CERTS_PY='# Revisa los certificados de los vhosts https. Imprime:
#   C|dominio|crt|key|motivo   un vhost cuyo certificado hay que cambiar (motivo: falta = no existe;
#                              sistema = esta en
#                              /etc/ssl/certs, donde el sistema lo toma como de confianza; ca = es de
#                              CA y su clave podria firmar cualquier web; firmado = lo firmo una CA
#                              local sin limite de dominios)
#   A|nombre|sha256|sha1|donde una CA local de confianza, sin limite de dominios, que firma
#                              certificados de los vhosts (donde: file:<ruta>, nss:<carpeta>:<nombre>
#                              o llavero:<ruta>)
#   K|ruta                     la clave privada de esa CA en tu carpeta personal (sin ella no se
#                              avisa de la CA: lo que firme no puede salir de este equipo)
# CERTS_PY <linux|mac> <puerto https>; los vhosts en LVM_INFO (vhosts_info)
import base64, glob, hashlib, os, re, subprocess, sys, tempfile
osname, https = sys.argv[1], sys.argv[2]
HOME = os.path.expanduser("~")
def run(args, data=None):
    # En su sesion, sin terminal: certutil carga los modulos de pkcs11.txt de tu nssdb, y la terminal
    # de la tarea tiene el permiso de sudo recordado
    kw = {"input": data} if data is not None else {"stdin": subprocess.DEVNULL}
    try:
        r = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=20,
                           start_new_session=True, **kw)
        return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""
def pems(text):
    return re.findall(r"-----BEGIN CERTIFICATE-----[A-Za-z0-9+/=\s]+?-----END CERTIFICATE-----", text)
def info(pem):
    out = run(["openssl", "x509", "-noout", "-subject_hash", "-issuer_hash", "-text"], pem.encode())
    lines = out.splitlines()
    if len(lines) < 3:
        return None
    der = base64.b64decode("".join(l for l in pem.splitlines() if not l.startswith("-----")))
    cn = re.search(r"Subject:.*?CN\s*=\s*([^,/\n]+)", out)
    return {"subj": lines[0].strip(), "iss": lines[1].strip(), "ca": "CA:TRUE" in out,
            "nc": "Name Constraints" in out, "cn": (cn.group(1).strip() if cn else "?"),
            "sha256": hashlib.sha256(der).hexdigest(), "sha1": hashlib.sha1(der).hexdigest(), "pem": pem}
def read(path):
    try:
        if os.path.isfile(path) and os.path.getsize(path) <= 1 << 20:
            return open(path, errors="replace").read()
    except OSError:
        pass
    return ""
store = None
def trust_store():
    # CAs añadidas a mano en este equipo (las del sistema operativo no se miran). LVM_PRUEBA_CAS: una
    # carpeta con mas, solo para las pruebas
    found = []
    for f in sorted(glob.glob(os.path.join(os.environ.get("LVM_PRUEBA_CAS", "/nonexistent"), "*.crt"))):
        for p in pems(read(f)):
            found.append((p, "file:" + f))
    if osname == "linux":
        for f in sorted(glob.glob("/usr/local/share/ca-certificates/**/*.crt", recursive=True)):
            for p in pems(read(f)):
                found.append((p, "file:" + f))
        dbs = [os.path.join(HOME, ".pki/nssdb")]
        dbs += glob.glob(os.path.join(HOME, ".mozilla/firefox/*/"))
        dbs += glob.glob(os.path.join(HOME, "snap/firefox/common/.mozilla/firefox/*/"))
        for d in dbs:
            d = d.rstrip("/")
            if not os.path.isfile(os.path.join(d, "cert9.db")):
                continue
            for line in run(["certutil", "-L", "-d", "sql:" + d]).splitlines()[4:]:
                m = re.match(r"^(.*?)\s+([CcTtPpu]*,[CcTtPpu]*,[CcTtPpu]*)\s*$", line)
                if not m or "|" in m.group(1) or "\n" in m.group(1):
                    continue
                if not re.search(r"[CT]", m.group(2).split(",")[0]):
                    continue
                for p in pems(run(["certutil", "-L", "-d", "sql:" + d, "-n", m.group(1), "-a"])):
                    found.append((p, "nss:%s:%s" % (d, m.group(1))))
    else:
        for kc in ("/Library/Keychains/System.keychain", os.path.join(HOME, "Library/Keychains/login.keychain-db")):
            if os.path.exists(kc):
                for p in pems(run(["security", "find-certificate", "-a", "-p", kc])):
                    found.append((p, "llavero:" + kc))
    out = []
    for p, where in found:
        i = info(p)
        if i and i["ca"]:
            out.append((i, where))
    return out
def signed_by(cert, ca):
    # La firma de verdad (no solo el nombre del emisor, que cualquiera puede copiar en un certificado)
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, "ca"), "w").write(ca["pem"] + "\n")
        open(os.path.join(d, "crt"), "w").write(cert["pem"] + "\n")
        out = run(["openssl", "verify", "-CAfile", os.path.join(d, "ca"), os.path.join(d, "crt")])
    return out.strip().endswith("OK")
cas, rows, keys = {}, [], {}
for row in os.environ.get("LVM_INFO", "").splitlines():
    f = row.split("|")
    if len(f) < 6 or f[0] != https or not f[4] or not re.fullmatch(r"[a-z0-9.-]+", f[2]):
        continue
    dom, crt, key = f[2], f[4], f[5]
    if "|" in crt + key:
        continue
    try:
        os.lstat(crt)
    except FileNotFoundError:
        # Sin certificado Apache no arranca: Arreglarlos le pone uno propio
        rows.append((dom, crt, key, "falta", ""))
        continue
    except OSError:
        continue
    text = read(crt)
    p = pems(text)
    i = info(p[0]) if p else None
    if not i:
        continue
    why, by = "", ""
    if osname == "linux" and os.path.dirname(os.path.realpath(crt)) == "/etc/ssl/certs":
        why = "sistema"
    if i["ca"] or i["subj"] != i["iss"]:
        if store is None:
            store = trust_store()
    # De CA solo importa si el equipo confia en el (si no, nadie acepta lo que firme su clave) y si
    # su clave la puede leer un programa tuyo. Entonces tambien se quita su confianza (fila A)
    if i["ca"] and os.access(key, os.R_OK):
        for ca, where in store or []:
            if ca["sha256"] == i["sha256"]:
                why = why or "ca"
                cas.setdefault(ca["sha256"], (ca, set()))[1].add(where)
                keys.setdefault(ca["sha256"], [])
                if key not in keys[ca["sha256"]]:
                    keys[ca["sha256"]].append(key)
    if i["subj"] != i["iss"]:
        for ca, where in store:
            if ca["subj"] == i["iss"] and not ca["nc"] and signed_by(i, ca):
                by = ca["sha256"]
                cas.setdefault(by, (ca, set()))[1].add(where)
    rows.append((dom, crt, key, why, by))
# Las CAs que firman esos certificados solo son un peligro si su clave esta al alcance de un programa
# tuyo (en tu carpeta personal): entonces se avisa y Arreglarlos las quita. Una CA de empresa cuya
# clave no esta en este equipo no se toca
if cas:
    pubs = {}
    for sha, (ca, _) in cas.items():
        pub = run(["openssl", "x509", "-noout", "-pubkey"], ca["pem"].encode()).strip()
        if pub:
            pubs[pub] = sha
    seen = 0
    for top in [HOME] + [d for d in [os.environ.get("LVM_PRUEBA_CLAVES", "")] if d]:
        for root, dirs, files in os.walk(top):
            dirs[:] = [d for d in dirs if not d.startswith(".") or d in (".ssh", ".local", ".config")]
            if root.count(os.sep) - top.count(os.sep) >= 3:
                dirs[:] = []
            for n in files:
                if not re.search(r"(?i)(\.key|key\.pem)$", n):
                    continue
                path = os.path.join(root, n)
                seen += 1
                if seen > 2000 or os.path.islink(path) or "|" in path:
                    continue
                k = read(path)
                if "PRIVATE KEY" not in k:
                    continue
                pub = run(["openssl", "pkey", "-pubout", "-passin", "pass:"], k.encode()).strip()
                if pub in pubs:
                    keys.setdefault(pubs[pub], []).append(path)
for dom, crt, key, why, by in rows:
    if not why and by in keys:
        why = "firmado"
    if why:
        print("C|%s|%s|%s|%s" % (dom, crt, key, why))
# Linux: certificados viejos del gestor en /etc/ssl/certs que ya no usa ningun vhost (y sus copias
# .bak): siguen siendo de confianza para el sistema. S|ruta
if osname == "linux":
    used = {os.path.realpath(r.split("|")[4]) for r in os.environ.get("LVM_INFO", "").splitlines()
            if len(r.split("|")) >= 6 and r.split("|")[4]}
    # Solo los que no usa ningun servicio del sistema (apache2, nginx, correo): un
    # apache-selfsigned.crt que use el apache2 del sistema se queda
    others = ""
    for d in ("/etc/apache2", "/etc/nginx", "/etc/postfix", "/etc/dovecot", "/etc/lighttpd"):
        for root, _, files in os.walk(d):
            for n in files:
                others += read(os.path.join(root, n))
    for f in sorted(glob.glob(os.path.join(os.environ.get("LVM_PRUEBA_SSL", "/etc/ssl/certs"), "*-selfsigned.crt*"))):
        n = os.path.basename(f)
        m = re.fullmatch(r"([A-Za-z0-9][A-Za-z0-9._-]*)-selfsigned\.crt(\.bak[A-Za-z0-9._-]*)?", n)
        if not m or not os.path.isfile(f) or os.path.islink(f) or os.path.realpath(f) in used \
                or n in others or "-selfsigned.crt" in n and n.split(".bak")[0] in others:
            continue
        # (si no lo usa nada se aparta, no se borra)
        if pems(read(f)):
            print("S|" + f)
for sha, (ca, wheres) in cas.items():
    if sha not in keys:
        continue
    for where in sorted(wheres):
        print("A|%s|%s|%s|%s" % (ca["cn"].replace("|", "/"), sha, ca["sha1"], where))
    for path in keys[sha]:
        print("K|" + path)
'

# Lineas C|dominio|crt|key|motivo, A|CA|sha256|sha1|donde y (con --clave) K|ruta. Ver CERTS_PY.
# Para la ventana se guarda el resultado mientras no cambien los vhosts ni los almacenes de CAs
function cert_audit() {
    local stamp cache=$LOG_DIR/certificados f
    [ -f "$VHOSTS_FILE" ] || return 0
    stamp=$(for f in "$VHOSTS_FILE" "$OWN_SSL_DIR" /usr/local/share/ca-certificates /etc/ssl/certs "$HOME/.pki/nssdb/cert9.db" "$HOSTS_FILE"; do
        [ -e "$f" ] && echo "$f $(stat -c %Y "$f")"; done; echo "$1 $APP_VERSION")
    if [ "$1" != "--clave" ] && [ -f "$cache" ] && [ "$(head -1 "$cache")" == "#$(echo "$stamp" | md5sum)" ]; then
        tail -n +2 "$cache"
        return 0
    fi
    local out info
    info=$(vhosts_info)
    # (y, para la ventana, los certificados propios con T|... y U|...: TRUST_PY)
    out=$(LVM_INFO=$info python3 -I -c "$CERTS_PY" linux "$PORT_HTTPS" "$@"
          [ "$1" == "--clave" ] || LVM_INFO=$info LVM_HOSTS_FILE=$HOSTS_FILE python3 -I -c "$TRUST_PY" linux "$PORT_HTTPS" "$OWN_SSL_DIR" | grep '^[TU]|')
    if [ "$1" != "--clave" ] && [ -d "$LOG_DIR" ]; then
        { echo "#$(echo "$stamp" | md5sum)"; [ -n "$out" ] && echo "$out"; } > "$cache"
    fi
    [ -n "$out" ] && echo "$out"
    return 0
}

# arreglar-certificados: cada vhost con un certificado de los de arriba pasa a uno autofirmado
# propio en la carpeta de certificados del gestor (no de CA, solo para su dominio), y las CAs locales
# sin limite de dominios que los firmaban dejan de ser de confianza en este equipo. La clave de la CA no
# se borra (puede que la quieras): se dice donde esta
function fix_certs() {
    local audit t dom crt key why copy n=0 cas=0 failed=0 old_files=() keyfile
    audit=$(cert_audit --clave)
    if ! grep -qE '^(C|A|S)\|' <<< "$audit"; then
        echo "Los certificados de los vhosts ya estan bien: ninguno es de confianza para todo este equipo."
        return 0
    fi
    copy=$(mktemp "${TMPDIR:-/tmp}/lvm-vhosts-cert.XXXXXX") || return 1
    cp "$VHOSTS_FILE" "$copy" || { rm -f "$copy"; return 1; }
    # Certificados viejos del gestor que ya no usa nadie (S): se apartan con los demas
    while IFS='|' read -r t crt; do
        [ "$t" == S ] || continue
        echo "${crt##*/}: certificado viejo en /etc/ssl/certs que no usa ningun vhost"
        old_files+=("$crt")
        # (su clave, si esta: /etc/ssl/private solo la ve root, se mira con sudo al apartar)
        [[ "$crt" == *.crt ]] && old_files+=("/etc/ssl/private/$(basename "${crt%.crt}").key")
    done <<< "$audit"
    while IFS='|' read -r t dom crt key why; do
        [ "$t" == C ] || continue
        local new_crt="$OWN_SSL_DIR/$dom-selfsigned.crt" new_key="$OWN_SSL_DIR/$dom-selfsigned.key"
        case $why in
            sistema) echo "$dom: su certificado esta en /etc/ssl/certs (el sistema lo da por bueno para todo)" ;;
            ca) echo "$dom: su certificado es de CA (con su clave se firmaria cualquier web)" ;;
            firmado) echo "$dom: su certificado lo firma una CA de confianza sin limite de dominios" ;;
            falta) echo "$dom: su certificado ($crt) no existe" ;;
        esac
        echo "  -> certificado propio en $new_crt"
        make_selfsigned "$dom" "$(domain_alias "$dom")" "$new_crt" "$new_key" || { failed=$((failed + 1)); continue; }
        # El viejo, si lo hizo el gestor en /etc/ssl (nombre-selfsigned): se quita al final
        [[ "$crt" == /etc/ssl/certs/*-selfsigned.crt ]] && old_files+=("$crt")
        [[ "$key" == /etc/ssl/private/*-selfsigned.key ]] && old_files+=("$key")
        [ "$DRY" -eq 1 ] && { n=$((n + 1)); continue; }
        if ! LVM_DOM=$dom LVM_CRT=$new_crt LVM_KEY=$new_key python3 -I - "$copy" <<'PY'
import os, re, sys
path = sys.argv[1]
dom, crt, key = os.environ["LVM_DOM"], os.environ["LVM_CRT"], os.environ["LVM_KEY"]
lines = open(path, encoding="utf-8", errors="surrogateescape").read().split("\n")
out, block, start = [], None, 0
for line in lines:
    s = line.strip()
    if re.match(r"(?i)<VirtualHost\b", s):
        block, start = [], len(out)
    out.append(line)
    if block is not None:
        block.append(len(out) - 1)
        if re.match(r"(?i)</VirtualHost>", s):
            names = [re.split(r"\s+", out[i].strip(), 1)[1].split(":")[0].lower() for i in block
                     if re.match(r"(?i)\s*ServerName\s+\S", out[i])]
            if dom in names:
                for i in block:
                    m = re.match(r"(?i)(\s*)(SSLCertificateFile|SSLCertificateKeyFile)(\s+)\S.*$", out[i])
                    if m:
                        out[i] = m.group(1) + m.group(2) + m.group(3) + "\"%s\"" % (crt if m.group(2).lower() == "sslcertificatefile" else key)
            block = None
open(path, "w", encoding="utf-8", errors="surrogateescape").write("\n".join(out))
PY
        then
            failed=$((failed + 1))
            continue
        fi
        n=$((n + 1))
    done <<< "$audit"
    if [ $n -gt 0 ]; then
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] los vhosts pasan a usar esos certificados (copia de root, comprobacion y recarga de Apache)"
        else
            edit_vhosts --aplicar "$copy" || { rm -f "$copy"; echo "No se han cambiado los vhosts: los certificados viejos siguen en uso."; return 1; }
            rm -f "$LOG_DIR/certificados"
        fi
    fi
    rm -f "$copy"
    # Los certificados viejos del gestor en /etc/ssl, ya sin usar, y la lista de confianza del sistema
    # rehecha sin ellos (update-ca-certificates --fresh quita los enlaces que les daban confianza)
    # (no se borran: se guardan en una carpeta solo de root fuera de /etc/ssl/certs, por si acaso)
    local f fresh=0 aside=/etc/ssl/lvm-anteriores-$(date +%Y%m%d-%H%M%S)
    for f in "${old_files[@]}"; do
        # Solo nombre-selfsigned directamente en /etc/ssl/certs o /etc/ssl/private (sin / ni .. de mas)
        [[ "$f" =~ ^/etc/ssl/(certs|private)/[A-Za-z0-9][A-Za-z0-9._-]*-selfsigned\.(crt|key)(\.bak[A-Za-z0-9._-]*)?$ ]] \
            && [[ "$f" != *..* ]] || continue
        [ "$DRY" -eq 0 ] && grep -qF "$f" "$VHOSTS_FILE" 2> /dev/null && continue
        if [[ "$f" == /etc/ssl/private/* ]]; then
            [ "$DRY" -eq 1 ] || { sudo test -f "$f" && ! sudo test -L "$f"; } || continue
        else
            [ -f "$f" ] && [ ! -L "$f" ] || continue
        fi
        { [ -d "$aside" ] || run sudo mkdir -m 700 "$aside"; } && run sudo mv "$f" "$aside/" && fresh=1
    done
    [ $fresh -eq 1 ] && echo "Los certificados viejos quedan guardados en $aside (solo root)"

    if [ $failed -gt 0 ] && grep -q '^A|' <<< "$audit"; then
        echo "No se quita la confianza a la CA: $failed proyecto(s) no se han podido pasar a su certificado"
        echo "propio y dejarian de funcionar. Revisa sus vhosts y vuelve a pulsar Arreglarlos."
        audit=$(grep -v '^A|' <<< "$audit")
    fi
    while IFS='|' read -r t _ _ sha1 where; do
        [ "$t" == A ] || continue
        cas=1
        case $where in
            file:/usr/local/share/ca-certificates/*)
                f=${where#file:}
                if [ -f "$f" ] && [ ! -L "$f" ] && [[ "$f" != *..* ]]; then
                    echo "Quitando la CA de confianza del sistema ($f)..."
                    run sudo rm -f "$f" && fresh=1
                fi ;;
            nss:*)
                local db=${where#nss:} nick
                nick=${db#*:} db=${db%%:*}
                echo "Quitando la CA de confianza del navegador ($db)..."
                run no_tty certutil -D -d "sql:$db" -n "$nick" ;;
        esac
    done <<< "$audit"
    if [ "${fresh:-0}" -eq 1 ]; then
        echo "Rehaciendo la lista de certificados de confianza del sistema..."
        run sudo update-ca-certificates --fresh > /dev/null
    fi
    keyfile=$(grep '^K|' <<< "$audit" | cut -d'|' -f2- | head -5)
    if [ -n "$keyfile" ]; then
        echo
        echo "La clave privada de esa CA sigue en tu carpeta:"
        sed 's/^/  /' <<< "$keyfile"
        echo "Ya no vale para falsificar webs en este equipo, pero si la usas en otros equipos, bórrala de aqui"
        echo "o guardala cifrada fuera de tu carpeta personal."
    fi
    rm -f "$LOG_DIR/certificados"
    echo
    echo "Certificados arreglados. El navegador acepta el propio de cada proyecto (solo vale para su dominio):"
    browser_trust || echo "El navegador avisara en esos proyectos: pulsa Confiar en el aviso de la ventana."
    return 0
}

# ===========================================================================
# Que el navegador acepte el certificado propio de cada proyecto
# ===========================================================================
# Con el aviso de certificado (La conexion no es privada) el navegador no deja entrar a las
# herramientas que lo manejan (Claude in Chrome y parecidas): no pueden aceptar el aviso. Se confia en
# el certificado de cada proyecto, no en una CA, y solo en uno que no le valga a nadie para otra web.
TRUST_PY='# Certificados propios de los proyectos https y si el navegador ya confia en ellos. Imprime:
#   T|dominio|crt|sha1|1 o 0|real   se puede confiar en el (1: el navegador ya confia; real: 1 si
#                                   es el dominio real de una tienda, falseado en hosts)
#   X|dominio|motivo                no se confia en el
#   U|dominio (Linux)               el navegador acepta uno nuestro con ese nombre en el que ya no
#   U|dominio|copia|sha1|1 o 0 (Mac)  se puede confiar: hay que quitarlo (Mac: 0, ya no lo acepta)
# Solo vale uno autofirmado que no es de CA, solo para su dominio y su alias (www), de root en la
# carpeta de certificados del gestor y con la clave solo para root: confiar en el no deja falsificar
# ninguna otra web. El de un dominio real (una tienda), solo mientras el y su alias esten falseados en
# hosts: Apache corre con tu usuario y tiene la clave en memoria, donde la puede leer el PHP de
# cualquier web, y con ella se podria suplantar la web de verdad; mientras esta falseado, el navegador
# no va a la web de verdad, y al dejar de falsearlo sale con U (se quita)
# TRUST_PY <linux|mac> <puerto https> <carpeta de certificados> [dominio]; los vhosts en LVM_INFO,
# hosts en LVM_HOSTS_FILE y (Mac) las copias de los que se han confiado en LVM_TRUST_DIR
import base64, glob, hashlib, os, plistlib, re, stat, subprocess, sys, tempfile
osname, https, ssldir = sys.argv[1], sys.argv[2], os.path.realpath(sys.argv[3])
only = sys.argv[4] if len(sys.argv) > 4 else ""
HOME = os.path.expanduser("~")
# (LVM_PRUEBA_DUENO: el usuario que hace de root, solo para las pruebas)
ROOT = int(os.environ.get("LVM_PRUEBA_DUENO", "") or 0)
def run(args, data=None):
    kw = {"input": data} if data is not None else {"stdin": subprocess.DEVNULL}
    try:
        r = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=20,
                           start_new_session=True, **kw)
        return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""
def pems(text):
    return re.findall(r"-----BEGIN CERTIFICATE-----[A-Za-z0-9+/=\s]+?-----END CERTIFICATE-----", text)
def sha1(pem):
    der = base64.b64decode("".join(l for l in pem.splitlines() if not l.startswith("-----")))
    return hashlib.sha1(der).hexdigest().upper()
# En los que ya confia el navegador. Linux: los de confianza P (la de un servidor) del almacen de
# Chrome y Chromium. Mac: los de tus ajustes de confianza (los que pone add-trusted-cert)
trusted = set()
if osname == "linux":
    db = os.path.join(HOME, ".pki/nssdb")
    if os.path.isfile(os.path.join(db, "cert9.db")):
        for line in run(["certutil", "-L", "-d", "sql:" + db]).splitlines()[4:]:
            m = re.match(r"^(.*?)\s+([CcTtPpu]*,[CcTtPpu]*,[CcTtPpu]*)\s*$", line)
            if m and "P" in m.group(2).split(",")[0] and "|" not in m.group(1):
                for p in pems(run(["certutil", "-L", "-d", "sql:" + db, "-n", m.group(1), "-a"])):
                    trusted.add(sha1(p))
else:
    with tempfile.TemporaryDirectory() as t:
        run(["security", "trust-settings-export", os.path.join(t, "ajustes.plist")])
        try:
            with open(os.path.join(t, "ajustes.plist"), "rb") as f:
                trusted = {k.upper() for k in plistlib.load(f).get("trustList", {})}
        except Exception:
            pass
def own(path, bad_bits):
    # De root, fichero normal (no enlace) directamente en la carpeta de certificados del gestor
    try:
        st = os.lstat(path)
    except OSError:
        return False
    return stat.S_ISREG(st.st_mode) and st.st_uid == ROOT and not st.st_mode & bad_bits \
        and os.path.dirname(os.path.realpath(path)) == ssldir
try:
    sd = os.stat(ssldir)
    dir_ok = sd.st_uid == ROOT and not sd.st_mode & 0o022
except OSError:
    dir_ok = False
# Falseado: todas las lineas sin comentar de hosts que lo llevan, a este equipo (127.x o ::1)
where = {}
try:
    for line in open(os.environ.get("LVM_HOSTS_FILE") or "/etc/hosts", errors="replace"):
        w = line.split("#")[0].split()
        for n in w[1:]:
            where.setdefault(n.lower(), set()).add(w[0])
except OSError:
    pass
def faked(name):
    ips = where.get(name)
    return bool(ips) and all(ip.startswith("127.") or ip == "::1" for ip in ips)
seen, good = set(), {}
for row in os.environ.get("LVM_INFO", "").splitlines():
    f = row.split("|")
    if len(f) < 6 or f[0] != https or not re.fullmatch(r"[a-z0-9.-]+", f[2]) or not f[4]:
        continue
    dom, crt, key = f[2], f[4], f[5]
    if only and dom != only or dom in seen:
        continue
    seen.add(dom)
    alias = dom[4:] if dom.startswith("www.") else "www." + dom
    real = dom.rsplit(".", 1)[-1] not in ("local", "test", "localhost", "example", "invalid", "internal",
                                          "lan", "localdomain") and not dom.endswith(".home.arpa")
    if real and not (faked(dom) and faked(alias)):
        print("X|%s|es un dominio real y no esta falseado en hosts: con su clave (Apache la tiene en memoria) se podria suplantar la web de verdad; se confia en el solo mientras este falseado (pestaña Hosts)" % dom)
        continue
    if not dir_ok or not own(crt, 0o022) or not own(key, 0o077) or ROOT == 0 and os.access(key, os.R_OK):
        print("X|%s|no usa un certificado propio del gestor (pulsa Arreglarlos en el aviso de certificados)" % dom)
        continue
    try:
        with open(crt, errors="replace") as fh:
            p = pems(fh.read(1 << 16))
    except OSError:
        continue
    out = run(["openssl", "x509", "-noout", "-subject_hash", "-issuer_hash", "-text"], p[0].encode()) \
        if len(p) == 1 else ""
    lines = out.splitlines()
    san = re.search(r"Subject Alternative Name:.*\n\s*(.+)", out)
    names = {n.strip() for n in san.group(1).split(",")} if san else set()
    if len(lines) < 3 or lines[0].strip() != lines[1].strip() or "CA:TRUE" in out \
            or not re.search(r"Basic Constraints:.*\n\s*CA:FALSE", out) \
            or not names or not names <= {"DNS:" + dom, "DNS:" + alias}:
        print("X|%s|su certificado no es uno autofirmado solo para %s (pulsa Arreglarlos en el aviso de certificados)" % (dom, dom))
        continue
    s = sha1(p[0])
    good[dom] = s
    print("T|%s|%s|%s|%d|%d" % (dom, crt, s, s in trusted, real))
# Los nuestros que acepta el navegador y en los que ya no se puede confiar (una tienda que ya no esta
# falseada, un vhost que ya no esta...). Linux: por su nombre (lvm-instalador <dominio>) en cada
# almacen. Mac: por las copias que se guardan al confiar (<dominio>.<sha1>.crt)
if osname == "linux":
    gone = set()
    for db in [os.path.join(HOME, ".pki/nssdb"), os.path.join(HOME, "snap/chromium/current/.pki/nssdb")] \
            + glob.glob(HOME + "/.mozilla/firefox/*/") + glob.glob(HOME + "/snap/firefox/common/.mozilla/firefox/*/"):
        if not os.path.isfile(os.path.join(db, "cert9.db")):
            continue
        for line in run(["certutil", "-L", "-d", "sql:" + db]).splitlines()[4:]:
            m = re.match(r"^lvm-instalador ([a-z0-9.-]+)\s+[CcTtPpu]*,[CcTtPpu]*,[CcTtPpu]*\s*$", line)
            if m and m.group(1) not in good and (not only or m.group(1) == only):
                gone.add(m.group(1))
    for d in sorted(gone):
        print("U|" + d)
else:
    rec = os.environ.get("LVM_TRUST_DIR", "")
    for name in sorted(os.listdir(rec)) if rec and os.path.isdir(rec) else []:
        m = re.fullmatch(r"([a-z0-9.-]+)\.([0-9A-F]{40})\.crt", name)
        if m and (not only or m.group(1) == only) and good.get(m.group(1)) != m.group(2):
            print("U|%s|%s|%s|%d" % (m.group(1), os.path.join(rec, name), m.group(2), m.group(2) in trusted))
'

# confiar-certificados [dominio|--hosts|--quitar]: Chrome, Chromium y Firefox aceptan sin aviso el
# certificado propio de cada proyecto https (o solo el de ese dominio). Va a sus almacenes
# (~/.pki/nssdb, el del Chromium snap y los perfiles de Firefox) con confianza P, la de un servidor y
# no la de una CA: no vale para ninguna otra web. Solo los que da por buenos TRUST_PY (los de una
# tienda con dominio real, mientras este falseada en hosts), y los que ya no (U|) se quitan.
# --hosts (al cambiar hosts): solo las tiendas falseadas y las que ya no lo estan. --quitar: solo quita
function browser_trust() {
    local only=$1 mode=todo out t dom crt sha1 ok real cur d db dbs=() nick added n=0 failed=0 i
    case "$only" in
        --hosts) mode=hosts only="" ;;
        --quitar) mode=quitar only="" ;;
    esac
    if [ -n "$only" ] && ! valid_domain "$only"; then
        echo "Dominio no valido: $only"
        return 1
    fi
    if ! command -v certutil > /dev/null; then
        # (sin certutil no se ha podido añadir ninguno: no hay nada que quitar)
        [ $mode == todo ] || return 0
        echo "Falta certutil (el programa que añade certificados a Chrome y Firefox). Instalalo con:"
        echo "  sudo apt install libnss3-tools"
        echo "y vuelve a pulsar Confiar."
        return 1
    fi
    out=$(LVM_INFO=$(vhosts_info) LVM_HOSTS_FILE=$HOSTS_FILE python3 -I -c "$TRUST_PY" linux "$PORT_HTTPS" "$OWN_SSL_DIR" "$only")
    [ $mode == todo ] && grep '^X|' <<< "$out" | cut -d'|' -f2- | sed 's/|/: no se confia en el: /'
    db=$HOME/.pki/nssdb
    for d in "$db" "$HOME"/snap/chromium/current/.pki/nssdb "$HOME"/.mozilla/firefox/*/ "$HOME"/snap/firefox/common/.mozilla/firefox/*/; do
        d=${d%/}
        [ -f "$d/cert9.db" ] && dbs+=("$d")
    done
    # Los que el navegador acepta y ya no se puede confiar en ellos (una tienda que ya no esta
    # falseada: el navegador va a la web de verdad, y con su clave se la podria suplantar)
    while IFS='|' read -r t dom; do
        [ "$t" == U ] || continue
        nick="lvm-instalador $dom"
        for d in "${dbs[@]}"; do
            # (puede haber mas de uno con ese nombre)
            for i in 1 2 3 4 5; do
                no_tty certutil -L -d "sql:$d" -n "$nick" > /dev/null || break
                if ! run no_tty certutil -D -d "sql:$d" -n "$nick"; then
                    echo "$dom: no se ha podido quitar su certificado de $d"
                    failed=$((failed + 1))
                    break
                fi
                [ "$DRY" -eq 0 ] || break
            done
        done
        echo "$dom: el navegador ya no acepta su certificado (ya no esta falseado, o su certificado o su vhost han cambiado)"
        n=$((n + 1))
    done <<< "$out"
    # --hosts: de los que se pueden confiar, solo las tiendas con dominio real
    [ $mode == hosts ] && out=$(grep '^T|.*|1$' <<< "$out")
    if [ $mode != quitar ] && grep -q '^T|' <<< "$out"; then
        if [ ! -f "$db/cert9.db" ]; then
            echo "Creando el almacen de certificados de Chrome ($db)..."
            run mkdir -p -m 700 "$db" && run no_tty certutil -N -d "sql:$db" --empty-password || return 1
            dbs=("$db" "${dbs[@]}")
        fi
        while IFS='|' read -r t dom crt sha1 ok real; do
            [ "$t" == T ] || continue
            nick="lvm-instalador $dom" added=0
            for d in "${dbs[@]}"; do
                # El que ya tenga ese nombre: si es otro (el certificado se ha vuelto a crear), se cambia
                cur=$(no_tty certutil -L -d "sql:$d" -n "$nick" -a | openssl x509 -noout -fingerprint -sha1 2> /dev/null)
                cur=${cur##*=}
                [ "${cur//:/}" == "$sha1" ] && continue
                [ -n "$cur" ] && run no_tty certutil -D -d "sql:$d" -n "$nick" > /dev/null
                if run no_tty certutil -A -d "sql:$d" -n "$nick" -t "P,," -i "$crt"; then
                    added=1
                else
                    echo "$dom: no se ha podido añadir su certificado a $d"
                    failed=$((failed + 1))
                fi
            done
            if [ $added -eq 1 ]; then
                echo "$dom: el navegador ya acepta su certificado$([ "$real" == 1 ] && echo " (mientras este falseado en hosts)")"
                n=$((n + 1))
            elif [ $mode == todo ]; then
                echo "$dom: el navegador ya lo aceptaba"
            fi
        done <<< "$out"
    elif [ $mode == todo ] && ! grep -q '^U|' <<< "$out"; then
        echo "No hay ningun proyecto https${only:+ $only} con un certificado propio en el que confiar."
        [ -z "$only" ] || return 1
    fi
    rm -f "$LOG_DIR/certificados"
    [ $failed -eq 0 ] || return 1
    [ $n -gt 0 ] || return 0
    echo
    echo "Si Chrome o Firefox estaban abiertos y aun avisan en algun proyecto (o aun aceptan uno que ya no"
    echo "esta falseado), cierralos del todo y vuelve a abrirlos."
    return 0
}

# Alias del dominio: www.dominio, o el dominio sin www si ya lo lleva
function domain_alias() {
    if [[ "$1" == www.* ]]; then echo "${1#www.}"; else echo "www.$1"; fi
}

# Dominio de una tienda PrestaShop. Primero el de su base (tabla shop_url, tienda principal), que es
# al que redirige; si la base no se puede leer (MariaDB parado o root con contraseña), el ServerName
# del vhost que ya apunte a la carpeta.
function ps_domain() {
    local folder=$1 config db prefix domain
    config=$(ps_config "$folder")
    db=${config%%|*} prefix=${config#*|}
    if [ -n "$db" ] && [[ "$db$prefix" =~ ^[A-Za-z0-9_-]+$ ]] && [ -x "$DB_CLIENT" ] \
            && db_base_table root "${MYSQL_PWD:-}" "$db" "${prefix}shop_url"; then
        # Si MariaDB se acaba de arrancar (cambio de version), se le dan unos segundos
        local try
        for try in 1 2 3 4 5 6; do
            domain=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT domain FROM \`$db\`.\`${prefix}shop_url\` ORDER BY main DESC, active DESC, id_shop_url LIMIT 1" < /dev/null 2>&1) && break
            [[ "$domain" == *"Can't connect"* ]] && [ "$DRY" -eq 0 ] || break
            sleep 1
        done
        domain=$(tr 'A-Z' 'a-z' <<< "${domain%%:*}")
        valid_domain "$domain" && echo "$domain" && return 0
    fi
    domain=$(vhosts_info | awk -F'|' -v f="$folder" -v l="$(project_link)" '$2 == f && $3 != l { print $3; exit }')
    [ -n "$domain" ] && echo "$domain"
}

# ¿Hay ya un vhost con ese dominio que apunte a la carpeta?
function vhost_points_to() {
    vhosts_info | awk -F'|' -v d="$1" -v f="$2" '$3 == d && $2 == f { found = 1 } END { exit !found }'
}

# ¿Se parece el dominio a la carpeta? Su nombre registrable (lo de antes de la terminacion:
# mitienda en www.mitienda.com, ejemplo en tienda.ejemplo.com, cliente en
# cliente.com.es), de 4 letras o mas, va en el nombre de la carpeta sin sus palabras genericas
# (dob, prestashop, wordpress...): asi prestashop.com no vale para dob-prestashop-x
function domain_fits_folder() {
    local domain=${1#www.} folder label w n parts
    folder=$(tr 'A-Z' 'a-z' <<< "$2")
    for w in dob prestashop wordpress tienda shop html php web wp ps; do folder=${folder//$w/}; done
    folder=$(tr -d '._-' <<< "$folder")
    IFS=. read -r -a parts <<< "$(tr 'A-Z' 'a-z' <<< "$domain")"
    n=${#parts[@]}
    (( n >= 2 )) || return 1
    label=${parts[n-2]}
    if (( n >= 3 )) && [[ "$label" =~ ^(com|co|org|net|gob|edu|ac|nom)$ ]]; then label=${parts[n-3]}; fi
    label=$(tr -d '_-' <<< "$label")
    [ ${#label} -ge 4 ] && [[ "$folder" == *"$label"* ]]
}

# ¿Es <tabla> de <base> una tabla de verdad (no una vista, que podria ejecutar funciones del volcado
# con los permisos de quien la lee)? db_base_table <usuario> <contraseña> <base> <tabla>
function db_base_table() {
    local n
    if [ -n "$2" ]; then
        n=$(MYSQL_PWD=$2 "${DB_SAFE[@]}" "$DB_CLIENT" -u"$1" -N -e "SELECT COUNT(*) FROM information_schema.TABLES
            WHERE TABLE_SCHEMA='$3' AND TABLE_NAME='$4' AND TABLE_TYPE='BASE TABLE'" < /dev/null 2> /dev/null)
    else
        n=$(env -u MYSQL_PWD "${DB_SAFE[@]}" "$DB_CLIENT" -u"$1" -N -e "SELECT COUNT(*) FROM information_schema.TABLES
            WHERE TABLE_SCHEMA='$3' AND TABLE_NAME='$4' AND TABLE_TYPE='BASE TABLE'" < /dev/null 2> /dev/null)
    fi
    [ "$n" == 1 ]
}

# Correo del ServerAdmin de los vhosts que se crean: el de git del usuario (user.email) o usuario@localhost
function server_admin() {
    local user=${SUDO_USER:-$USER} mail
    mail=$(sudo_user_git_email "$user")
    # (va como root en los vhosts: sin \ al final, que uniria la linea con la siguiente, ni comillas)
    [[ "$user" =~ ^[A-Za-z0-9._-]+$ ]] || user=webmaster
    [[ "$mail" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]] && echo "$mail" || echo "$user@localhost"
}

function sudo_user_git_email() {
    local home
    home=$(getent passwd "$1" | cut -d: -f6)
    HOME=${home:-$HOME} git config --global user.email 2> /dev/null
}

# Comprueba que el dominio tiene vhost http y https apuntando a la carpeta y certificado. Lo que
# falte se crea como en el manual: certificado <dominio>-selfsigned en /etc/ssl y bloques al final
# de VHOSTS_FILE (se guarda copia en ~/lvm-copias). Deja PS_RELOAD=1 si ha cambiado algo.
function ps_vhost() {
    local folder=$1 domain=$2 alias info http https crt key other s="" block=""
    # El dominio va en el vhost, en /etc/hosts y en el nombre del certificado: solo uno valido
    valid_domain "$domain" || { echo "Dominio no valido: $domain"; return 1; }
    alias=$(domain_alias "$domain")
    info=$(vhosts_info)
    http=$(awk -F'|' -v p="$PORT_HTTP" -v d="$domain" '$1 == p && $3 == d' <<< "$info" | head -1)
    https=$(awk -F'|' -v p="$PORT_HTTPS" -v d="$domain" '$1 == p && $3 == d' <<< "$info" | head -1)

    other=$(printf '%s\n%s\n' "$http" "$https" | awk -F'|' -v f="$folder" '$0 != "" && $2 != f { print $2; exit }')
    if [ -n "$other" ]; then
        echo "Aviso: el vhost de $domain apunta a $HTDOCS_DIR/$other, no a $folder. No se cambia:"
        echo "revisalo en Editar vhosts si no es lo que quieres."
    fi

    crt=$(cut -d'|' -f5 <<< "$https") key=$(cut -d'|' -f6 <<< "$https")
    if [ -z "$https" ]; then
        crt="$SSL_CERTS_DIR/$domain-selfsigned.crt" key="$SSL_KEYS_DIR/$domain-selfsigned.key"
    fi
    if [ -n "$crt" ] && [ -n "$key" ] && [ ! -f "$crt" ]; then
        echo "Creando el certificado autofirmado de $domain ($crt)..."
        make_selfsigned "$domain" "$alias" "$crt" "$key" || return 1
        PS_RELOAD=1
    fi

    if [ -z "$http" ]; then
        block+="
<VirtualHost *:$PORT_HTTP>
    ServerAdmin $(server_admin)
    DocumentRoot \"/opt/lampp/htdocs/$folder\"
    ServerName $domain
    ServerAlias $alias
    ErrorLog \"logs/$domain-error_log\"
</VirtualHost>
"
    fi
    if [ -z "$https" ]; then
        block+="
<VirtualHost *:$PORT_HTTPS>
    ServerAdmin $(server_admin)
    DocumentRoot \"/opt/lampp/htdocs/$folder\"
    ServerName $domain
    ServerAlias $alias

    SSLEngine on
    SSLCertificateFile $crt
    SSLCertificateKeyFile $key
</VirtualHost>
"
    fi
    [ -z "$block" ] && return 0

    block="

######################### URL $(tr 'a-z' 'A-Z' <<< "$domain") (lvm-instalador) #########################
$block"
    echo "Añadiendo el vhost de $domain ($([ -z "$http" ] && echo -n "http ")$([ -z "$https" ] && echo -n "https")) a $VHOSTS_FILE..."
    s=""
    [ -w "$VHOSTS_FILE" ] || s=sudo
    if [ -f "$VHOSTS_FILE" ]; then
        run mkdir -p -m 700 "$HOME/lvm-copias"
        run cp "$VHOSTS_FILE" "$HOME/lvm-copias/httpd-vhosts.conf-$(date +%Y%m%d-%H%M%S)" || return 1
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] añadir a $VHOSTS_FILE:$block"
    else
        printf '%s' "$block" | $s tee -a "$VHOSTS_FILE" > /dev/null || return 1
    fi
    PS_RELOAD=1
    browser_trust "$domain" || true
}

# Falsea dominios en /etc/hosts. Modo carga: falsea los indicados (puede no haber ninguno) y deja de
# falsear el resto de dominios de los vhosts. Modo si/no: solo falsea o deja de falsear uno.
# Solo toca lineas 127.0.0.1 cuyos nombres sean todos dominios de vhosts de proyectos (nunca
# localhost, web.local ni el nombre del equipo): las comenta o les quita el # (y añade la linea
# si no existia). Se escribe con edit_hosts --aplicar (copia del anterior en ~/lvm-copias).
function hosts_fake() {
    local mode=$1 copy rc
    shift
    copy=$(mktemp "${TMPDIR:-/tmp}/lvm-hosts.XXXXXX") || return 1
    LVM_INFO=$(vhosts_info) python3 -I - "$HOSTS_FILE" "$copy" "$mode" "$PROJECT_VHOST $(project_link)" "$@" <<'EOF'
import os, re, sys
src, dst, mode, links = sys.argv[1:5]
wanted = [d.lower() for d in sys.argv[5:]]
skip = {"localhost"}
for l in links.lower().split():
    skip |= {l, "www." + l}
managed = set()
for row in os.environ.get("LVM_INFO", "").splitlines():
    f = row.split("|")
    if len(f) >= 4:
        managed |= {n.lower() for n in [f[2]] + f[3].split() if n}
managed -= skip
# Los .local no existen fuera: se quedan siempre en hosts (al cargar otro proyecto no se comentan) y
# se añaden si les falta la linea. Sin ella, el equipo los pregunta a la red (mDNS) y cualquiera de
# la misma wifi podria contestar con su IP y servir su web con ese nombre
always = {n.lower() for n in managed if n.lower().endswith(".local")}
managed -= always
target = set()
for d in wanted:
    target |= {d, d[4:] if d.startswith("www.") else "www." + d}
# localhost y el vhost de los proyectos (web.local) no se tocan nunca
wanted = [d for d in wanted if d not in skip]
target -= skip
# (un .local no se apaga: no hay ninguna web «real» a la que devolverlo, y sin su linea se
# preguntaria a la red)
if mode == "no":
    managed |= target - always
lines = open(src).read().splitlines()
rx = re.compile(r"^(\s*)(#+\s*)?(127\.0\.0\.1)(\s+)(.*?)\s*$")
done, changes, out = set(), [], []
for line in lines:
    m = rx.match(line)
    names = m.group(5).split("#")[0].split() if m else []
    lnames = {n.lower() for n in names}
    # (una linea con un .local y un dominio de verdad, de un vhost con los dos, tambien es nuestra)
    ours = bool(names) and lnames <= (managed | always | target) and bool(lnames - always)
    if not ours:
        out.append(line)
        continue
    active = not m.group(2)
    if lnames & target:
        # Se falsea (sin quitar el # a una segunda linea repetida) o se deja de falsear
        on = mode != "no" and (active or not lnames <= done)
    else:
        # Al cargar un proyecto, el resto de dominios vuelve a la web real
        on = active and mode != "cargar"
    if on and not active:
        line = m.group(1) + m.group(3) + m.group(4) + m.group(5)
        changes.append("Falseado en %s: %s" % (src, " ".join(names)))
    elif not on and active:
        line = m.group(1) + "#" + m.group(3) + m.group(4) + m.group(5)
        # Los .local de esa linea no se comentan: se quedan activos en otra
        keep = [n for n in names if n.lower() in always]
        if keep:
            line = m.group(1) + "#" + m.group(3) + m.group(4) + " ".join(n for n in names if n.lower() not in always)
            out.append(m.group(1) + m.group(3) + m.group(4) + " ".join(keep))
        changes.append("Ya no esta falseado (lleva a la web real): " + " ".join(names))
    if on:
        done |= lnames
    out.append(line)
active_names, off_names = set(), set()
for l in out:
    mm = rx.match(l)
    if mm and not mm.group(2):
        active_names |= {n.lower() for n in mm.group(5).split("#")[0].split()}
    elif mm:
        off_names |= {n.lower() for n in mm.group(5).split("#")[0].split()}
# (tambien los que esten comentados: se vuelven a añadir)
for d in sorted(always - active_names):
    last = max([i for i, l in enumerate(out) if rx.match(l)] or [len(out) - 1])
    out.insert(last + 1, "127.0.0.1 %s" % d)
    changes.append("En %s, para que no se pregunte a la red: %s" % (src, d))
if mode in ("cargar", "si"):
    for d in wanted:
        if d not in done:
            alias = d[4:] if d.startswith("www.") else "www." + d
            new = "127.0.0.1 %s %s" % (d, alias)
            last = max([i for i, l in enumerate(out) if rx.match(l)] or [len(out) - 1])
            out.insert(last + 1, new)
            done |= {d, alias}
            changes.append("Falseado en %s: %s %s" % (src, d, alias))
open(dst, "w").write("\n".join(out) + "\n")
for c in changes:
    print(c)
EOF
    rc=$?
    if [ $rc -ne 0 ]; then
        rm -f "$copy"
        echo "No se ha podido preparar el nuevo $HOSTS_FILE"
        return 1
    fi
    if ! cmp -s "$copy" "$HOSTS_FILE"; then
        edit_hosts --aplicar "$copy" || { rm -f "$copy"; return 1; }
    fi
    rm -f "$copy"
}

# hosts-enlace: el vhost de los proyectos (web.local) pasa a 127.0.0.1 en hosts, que es donde escucha
# Apache. Se quita de las lineas que lo llevaban a otra direccion (la del nombre del equipo se queda
# con sus otros nombres) y se añade su linea. Con copia del anterior en ~/lvm-copias (edit_hosts)
function hosts_fix_link() {
    local link copy
    link=$(project_link)
    link=${link:-$PROJECT_VHOST}
    valid_domain "$link" || { echo "No hay vhost de los proyectos"; return 1; }
    copy=$(mktemp "${TMPDIR:-/tmp}/lvm-hosts.XXXXXX") || return 1
    if ! python3 -I - "$HOSTS_FILE" "$copy" "$link" <<'EOF'
import re, sys
src, dst, name = sys.argv[1], sys.argv[2], sys.argv[3].lower()
out, changes, ok = [], [], False
for line in open(src, errors="surrogateescape").read().splitlines():
    body, sep, comment = line.partition("#")
    w = body.split()
    if len(w) >= 2 and name in [x.lower() for x in w[1:]]:
        if w[0] == "127.0.0.1":
            ok = True
        else:
            rest = [x for x in w[1:] if x.lower() != name]
            changes.append("%s ya no lleva a %s" % (name, w[0]))
            if rest:
                line = " ".join([w[0]] + rest) + ((" " + sep + comment) if sep else "")
            else:
                line = "# (lvm-instalador: %s pasa a 127.0.0.1) %s" % (name, line)
    out.append(line)
if not ok:
    last = max([i for i, l in enumerate(out) if re.match(r"\s*127\.0\.0\.1\s", l)] or [len(out) - 1])
    out.insert(last + 1, "127.0.0.1 %s" % name)
    changes.append("%s lleva a este equipo (127.0.0.1)" % name)
open(dst, "w", errors="surrogateescape").write("\n".join(out) + "\n")
for c in changes:
    print(c)
EOF
    then
        rm -f "$copy"
        return 1
    fi
    if cmp -s "$copy" "$HOSTS_FILE"; then
        echo "$link ya lleva a este equipo (127.0.0.1)"
    else
        edit_hosts --aplicar "$copy" || { rm -f "$copy"; return 1; }
    fi
    rm -f "$copy"
}

# hosts-falsear <dominio> si|no: el interruptor de la pestaña Hosts
function hosts_fake_one() {
    local domain=$(tr 'A-Z' 'a-z' <<< "$1") state=$2
    if ! valid_domain "$domain" || [[ "$state" != si && "$state" != no ]]; then
        echo "Uso: lvm-instalador hosts-falsear <dominio> si|no"

        return 1
    fi
    local link
    for link in localhost "$PROJECT_VHOST" $(project_link); do
        if [ "$domain" == "$link" ] || [ "$domain" == "www.$link" ]; then
            echo "$domain no se falsea ni se deja de falsear desde aqui: es el de los proyectos o el del equipo"

            return 1
        fi
    done
    if [[ "$domain" == *.local ]] && [ "$state" == no ]; then
        echo "$domain no se deja de falsear: un .local no existe fuera de este equipo y, sin su linea en"
        echo "$HOSTS_FILE, el equipo lo preguntaria a la red (cualquiera de la misma wifi podria contestar)."

        return 1
    fi
    if ! vhosts_info | awk -F'|' -v d="$domain" '$3 == d || index(" " $4 " ", " " d " ") { f = 1 } END { exit !f }'; then
        echo "$domain no es el dominio de ningun vhost de $VHOSTS_FILE"

        return 1
    fi
    hosts_fake "$state" "$domain" || return 1
    if [ "$state" == si ]; then
        echo "$domain falseado: lleva a este equipo (127.0.0.1)"
    else
        echo "$domain ya no esta falseado: lleva a la web real"
    fi
}

# Para la pestaña Hosts: F|dominio|alias|carpeta|falseado (1/0)|https (1/0)|certificado (1/0)|PrestaShop (1/0)|personalizado (1/0)
function gui_hosts() {
    local info=$(vhosts_info) link=$(project_link)
    LVM_INFO=$info python3 -I - "$HOSTS_FILE" "$HTDOCS_DIR" "$PROJECT_VHOST $link" "$PORT_HTTPS" "$CUSTOM_DOMAINS_FILE" <<'EOF'
import os, re, sys
hosts, htdocs, links, https_port, custom_file = sys.argv[1:6]
custom = set()
try:
    custom = {l.split("=", 1)[0] for l in open(custom_file) if "=" in l}
except OSError:
    pass
skip = set()
for l in links.split():
    skip |= {l, "www." + l}
active = set()
try:
    for line in open(hosts, errors="replace"):
        m = re.match(r"^\s*127\.0\.0\.1\s+(.*)", line)
        if m:
            active |= set(m.group(1).split("#")[0].lower().split())
except OSError:
    pass
rows = {}
for row in os.environ.get("LVM_INFO", "").splitlines():
    f = row.split("|")
    if len(f) < 6 or f[2] in skip:
        continue
    r = rows.setdefault(f[2], {"alias": "", "folder": "", "https": 0, "crt": 0})
    aliases = f[3].split()
    # El alias www.<dominio> si lo hay (algun vhost http tiene un alias copiado de otro)
    r["alias"] = ("www." + f[2]) if "www." + f[2] in aliases else (r["alias"] or (aliases or [""])[0])
    r["folder"] = r["folder"] or f[1]
    if f[0] == https_port:
        r["https"] = 1
        r["crt"] = int(bool(f[4]) and os.path.isfile(f[4]))
for name in sorted(rows):
    r = rows[name]
    ps = any(os.path.isfile(os.path.join(htdocs, r["folder"], p))
             for p in ("app/config/parameters.php", "config/settings.inc.php")) if r["folder"] else False
    print("F|%s|%s|%s|%d|%d|%d|%d|%d" % (name, r["alias"], r["folder"], name in active,
                                         r["https"], r["crt"], ps, name in custom))
# El vhost de los proyectos (web.local) tiene que llevar a 127.0.0.1, donde escucha Apache: si en
# hosts apunta a otra direccion (127.0.1.1, la del nombre del equipo en Ubuntu) o no esta, el
# navegador da ERR_CONNECTION_REFUSED. L|nombre|direccion a la que apunta ahora (vacio si no esta)
vhost_names = {row.split("|")[2].lower() for row in os.environ.get("LVM_INFO", "").splitlines()
               if len(row.split("|")) >= 3}
for name in dict.fromkeys(links.lower().split()):
    if not name or name not in vhost_names or name in active:
        continue
    now = ""
    try:
        for line in open(hosts, errors="replace"):
            w = line.split("#")[0].split()
            if len(w) >= 2 and name in [x.lower() for x in w[1:]]:
                now = w[0]
                break
    except OSError:
        pass
    print("L|%s|%s" % (name, re.sub(r"[^0-9A-Fa-f.:]", "", now)))
EOF
}

# Ficheros y carpetas de htdocs que puede cambiar cualquier usuario del equipo (plugins y caches que
# los dejan en 777 o 666): otro usuario podria dejar un PHP y ejecutarlo con el tuyo pidiendolo a
# localhost. Se les quita la escritura para los demas (Apache, que corre con tu usuario, sigue
# pudiendo escribir). Solo lo tuyo y con tu usuario (sin sudo: root no cambia permisos dentro de
# htdocs, que es tuyo); de lo de otros solo se avisa. htdocs_close_world <carpeta>
function htdocs_close_world() {
    local dir=$1 me n others
    [ -d "$dir" ] && [ ! -L "$dir" ] || return 0
    me=$(id -un)
    # Una sola pasada (al cargar un proyecto con vendor o node_modules, cuenta): lo tuyo se cambia
    # y se cuenta a la vez. Lo de otros usuarios solo se mira con --otros (Protegerlas)
    if [ "$DRY" -eq 1 ]; then
        n=$(find "$dir" -xdev \( -type f -o -type d \) -perm -0002 -user "$me" -print 2> /dev/null | wc -l | tr -d ' ')
        [ "$n" -gt 0 ] && echo "  [simulacion] $n ficheros y carpetas de $dir dejarian de poder cambiarlos los demas usuarios"
    elif [ "$2" == "--otros" ]; then
        # Una sola pasada tambien aqui: lo tuyo se cambia y se cuenta, y lo de otros solo se cuenta
        local list
        list=$(find "$dir" -xdev \( -type f -o -type d \) -perm -0002 \
            \( -user "$me" -exec chmod o-w {} + -exec echo m \; -o -exec echo o \; \) 2> /dev/null)
        n=$(grep -c '^m$' <<< "$list") others=$(grep -c '^o$' <<< "$list")
        [ "$n" -gt 0 ] && echo "$n ficheros y carpetas de $dir ya no los puede cambiar cualquier usuario"
        [ "$others" -gt 0 ] && echo "Aviso: $others de $dir son de otro usuario y los puede cambiar cualquiera: revisalos (sudo chmod o-w)"
        return 0
    else
        n=$(find "$dir" -xdev \( -type f -o -type d \) -perm -0002 -user "$me" -exec chmod o-w {} + -print 2> /dev/null | wc -l | tr -d ' ')
        [ "$n" -gt 0 ] && echo "$n ficheros y carpetas de $dir ya no los puede cambiar cualquier usuario del equipo"
    fi
    return 0
}

# Tu usuario (el de SUDO_USER si esto corre con sudo), para Apache, PHP-FPM y los permisos: solo un
# nombre valido de un usuario que existe (va a la configuracion que lee root). Si no, el que corre
function web_user_name() {
    local u=${SUDO_USER:-$USER}
    if [[ "$u" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,31}$ ]] && id "$u" > /dev/null 2>&1; then
        echo "$u"
    else
        id -un
    fi
}

# Proyectos nuevos con dominio falseado (pestaña Hosts): dominio=carpeta, uno por linea
CUSTOM_DOMAINS_FILE="$HOME/.lvm-instalador/dominios"

# Dominio personalizado de una carpeta (vacio si no tiene)
function custom_domain() {
    local d
    [ -f "$CUSTOM_DOMAINS_FILE" ] || return 0
    d=$(awk -F= -v f="$1" '$2 == f { d = $1 } END { if (d != "") print d }' "$CUSTOM_DOMAINS_FILE")
    # El fichero es tuyo: solo un dominio valido (sin /, .., espacios ni saltos de linea)
    [ -n "$d" ] && valid_domain "$d" && echo "$d"
    return 0
}

# nuevo-dominio <dominio> <carpeta> [base]: proyecto nuevo con el dominio de produccion falseado.
# Crea la carpeta en htdocs, su vhost http y https con certificado (lo mismo que una tienda
# PrestaShop), la base vacia con el nombre de produccion en la version activa (si se indica y no
# existe) y falsea el dominio (los demas dejan de estarlo, como al cargar un proyecto). El dominio
# queda asociado a la carpeta: Cargar proyecto lo vuelve a falsear.
function new_custom_domain() {
    local domain=$(tr 'A-Z' 'a-z' <<< "$1") folder=${2%/} db=$3 link owner s=""

    if ! valid_domain "$domain"; then
        echo "Dominio no valido: $1 (por ejemplo: mitienda.com)"

        return 1
    fi
    for link in localhost "$PROJECT_VHOST" $(project_link); do
        if [ "$domain" == "$link" ] || [ "$domain" == "www.$link" ] || [ "$folder" == "$link" ]; then
            echo "$link es el de los proyectos o el del equipo: elige otro dominio y otra carpeta"

            return 1
        fi
    done
    if ! [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]; then
        echo "Carpeta no valida: $folder (solo letras sin acentos, numeros, punto, _ y -)"

        return 1
    fi
    if [ -L "$HTDOCS_DIR/$folder" ]; then
        echo "$HTDOCS_DIR/$folder es un enlace, no una carpeta de proyecto"

        return 1
    fi
    owner=$(vhosts_info | awk -F'|' -v d="$domain" '$3 == d || index(" " $4 " ", " " d " ") { print $2; exit }')
    if [ -n "$owner" ]; then
        echo "Ya hay un vhost para $domain (carpeta ${owner:-desconocida}). Para falsearlo usa su"
        echo "interruptor en la pestaña Hosts (o: lvm-instalador hosts-falsear $domain si)."

        return 1
    fi
    if [ -n "$db" ]; then
        db_valid_name "$db" || return 1
    fi

    if [ -d "$HTDOCS_DIR/$folder" ]; then
        echo "Se usa la carpeta que ya existe: $HTDOCS_DIR/$folder"
    else
        echo "Creando la carpeta $HTDOCS_DIR/$folder..."
        [ -w "$HTDOCS_DIR" ] || s=sudo
        run $s mkdir -p "$HTDOCS_DIR/$folder" || return 1
        [ -n "$s" ] && run sudo chown "${SUDO_USER:-$USER}:$(id -gn "${SUDO_USER:-$USER}")" "$HTDOCS_DIR/$folder"
    fi

    PS_RELOAD=0
    ps_vhost "$folder" "$domain" || return 1

    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $domain=$folder en $CUSTOM_DOMAINS_FILE"
    else
        mkdir -p "$(dirname "$CUSTOM_DOMAINS_FILE")"
        { [ -f "$CUSTOM_DOMAINS_FILE" ] && grep -v "^$domain=" "$CUSTOM_DOMAINS_FILE"; echo "$domain=$folder"; } > "$CUSTOM_DOMAINS_FILE.nuevo"
        mv "$CUSTOM_DOMAINS_FILE.nuevo" "$CUSTOM_DOMAINS_FILE"
    fi

    if [ -n "$db" ]; then
        if db_connect > /dev/null 2>&1 && db_exists "$db"; then
            echo "La base de datos $db ya existe en lampp-$DB_FOLDER: se deja como esta"
        else
            create_database "$db" || echo "Aviso: no se ha creado la base $db. Creala despues en la pestaña Bases de datos."
        fi
        # Cargar proyecto desde el buscador de bases encuentra la carpeta aunque aun no haya configuracion
        if [ "$DRY" -eq 0 ]; then
            mkdir -p "$(dirname "$PROJECTS_FILE")"
            { [ -f "$PROJECTS_FILE" ] && grep -v "^$db=" "$PROJECTS_FILE"; echo "$db=$folder"; } > "$PROJECTS_FILE.nuevo"
            mv "$PROJECTS_FILE.nuevo" "$PROJECTS_FILE"
        fi
    fi

    hosts_fake cargar "$domain" || return 1
    if [ "$PS_RELOAD" -eq 1 ] && [ -f /opt/lampp/logs/httpd.pid ]; then
        echo "Recargando Apache para aplicar el vhost y el certificado..."
        run sudo /opt/lampp/lampp reloadapache > /dev/null || { echo "No se ha podido recargar Apache. Reinicia la version activa."; return 1; }
    fi
    echo "Proyecto nuevo listo: https://$domain -> $HTDOCS_DIR/$folder$([ -n "$db" ] && echo " (base $db)")"
}

# Usuario con el que se ejecuta Apache en una version: fichero donde añadirlo|User|Group. En XAMPP
# el que manda es el ultimo, el de apache2/conf/httpd.conf (incluido al final de etc/httpd.conf)
function apache_user_conf() {
    python3 -I - "$1" <<'EOF'
import os, re, sys
base = sys.argv[1]
state = {"conf": os.path.join(base, "etc/httpd.conf"), "user": "", "group": ""}
def walk(path, depth=0):
    try:
        lines = open(path, errors="replace").read().splitlines()
    except OSError:
        return
    for line in lines:
        s = line.strip()
        m = re.match(r"(User|Group)\s+(\S+)", s)
        if m:
            state[m.group(1).lower()] = m.group(2)
            continue
        m = re.match(r"Include(?:Optional)?\s+\"?([^\"\s]+)\"?", s)
        if m and depth < 2 and m.group(1).endswith("apache2/conf/httpd.conf"):
            p = m.group(1)
            if p.startswith("/opt/lampp/"):
                p = os.path.join(base, p[len("/opt/lampp/"):])
            elif not p.startswith("/"):
                p = os.path.join(base, p)
            if os.path.isfile(p):
                state["conf"] = p
                walk(p, depth + 1)
walk(state["conf"])
print("%s|%s|%s" % (state["conf"], state["user"], state["group"]))
EOF
}

# Como en el manual: Apache se ejecuta con el usuario de la sesion (User/Group al final de su
# httpd.conf) para que la cache y los ficheros que crean las webs sean tuyos. Solo lo añade si
# hace falta; devuelve 0 si lo ha cambiado (hay que reiniciar Apache).
function ensure_web_user() {
    local dir=$1 conf user group
    local web_user=$(web_user_name) web_group
    [ -n "$web_user" ] && [ "$web_user" != root ] && [ -f "$dir/etc/httpd.conf" ] || return 1
    web_group=$(id -gn "$web_user")
    IFS='|' read -r conf user group <<< "$(apache_user_conf "$dir")"
    [ "$user" == "$web_user" ] && [ "$group" == "$web_group" ] && return 1

    echo "Apache de $(basename "$dir") se ejecuta como ${user:-daemon}:${group:-daemon}: se cambia a $web_user:$web_group en $conf"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] User $web_user / Group $web_group al final de $conf"
    else
        printf '\nUser %s\nGroup %s\n' "$web_user" "$web_group" | sudo tee -a "$conf" > /dev/null || return 1
    fi
    return 0
}

# ===========================================================================
# Seguridad: los servicios, solo para este equipo
# ===========================================================================
# XAMPP deja Apache, MariaDB y ProFTPD escuchando en todas las interfaces: cualquier equipo de la
# red veria los proyectos de los clientes, llegaria a MariaDB y entraria por FTP en htdocs (XAMPP
# trae el usuario daemon con la contraseña xampp). Se dejan solo para este equipo (127.0.0.1 y
# ::1), el FTP deja de arrancar con la version (se activa en la pestaña Servicios cuando haga
# falta, por ejemplo para que WordPress instale plugins) y los vhosts vuelven a ser de root. Como
# con User/Group, solo se cambia lo que falta; lo anterior queda en ~/lvm-copias.
SECURE_MARK=etc/lvm-seguridad

# ¿Tiene el equipo la direccion ::1? (sin ella, Apache no arrancaria con Listen [::1]:80)
function has_ipv6_loopback() {
    grep -q '^0\{31\}1 ' /proc/net/if_inet6 2> /dev/null
}

# Primer vhost del puerto 80: Apache le pasa las peticiones cuyo dominio no tiene ningun vhost. Una web
# cualquiera puede hacer que su dominio apunte a 127.0.0.1 (DNS rebinding) y entonces su JavaScript
# leeria phpMyAdmin (root sin contraseña) y los proyectos desde el navegador. Solo deja pasar
# localhost, 127.0.0.1 y [::1] (la carpeta htdocs y phpMyAdmin); el resto recibe un 403. Los vhosts
# por nombre (web.local, los dominios falseados) no pasan por aqui. HTTPS no lo necesita: el
# certificado no vale para el dominio de fuera y el navegador corta la conexion.
UNKNOWN_HOST_CONF=etc/extra/lvm-dominio-desconocido.conf
# Ademas, para todas las webs: phpMyAdmin (root sin contraseña) solo desde localhost (un fallo XSS
# en un proyecto antiguo no puede usarlo desde su dominio), su asistente setup cerrado, y los .env
# y repositorios .git de los proyectos no se sirven. El vhost del 443 se añade (SECURE_PY) si la
# version tiene el certificado de localhost.
UNKNOWN_HOST_VHOST='# lvm-instalador: dominios que no tienen ningun vhost (va antes de httpd-vhosts.conf)
# Solo deja pasar localhost, 127.0.0.1 y [::1]. Cualquier otro dominio que apunte a este equipo
# (una web que intenta leer phpMyAdmin o los proyectos desde el navegador) recibe un 403.
# Para usar otro dominio, crea su vhost (pestaña Hosts o httpd-vhosts.conf).
<VirtualHost *:80>
    ServerName localhost
    ServerAlias 127.0.0.1 [::1]
    <If "%{HTTP_HOST} !~ /^(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?$/">
        Require all denied
        ErrorDocument 403 "Este dominio no tiene vhost en este equipo (lvm-instalador): crea su vhost o entra con localhost."
    </If>
    # En 127.0.0.1 y [::1] solo phpMyAdmin: los proyectos van en localhost
    <If "%{HTTP_HOST} =~ /^(127\.0\.0\.1|\[::1\])(:[0-9]+)?$/ && %{REQUEST_URI} !~ m#^/phpmyadmin(/|$)#">
        Require all denied
        ErrorDocument 403 "En 127.0.0.1 solo esta phpMyAdmin: los proyectos van en http://localhost/ (lvm-instalador)"
    </If>
</VirtualHost>

# phpMyAdmin tiene su propio origen: solo en http://127.0.0.1/phpmyadmin/ (o [::1]), donde no hay
# nada mas. Los proyectos van en localhost/<carpeta>, web.local o sus dominios: un fallo XSS en uno
# de ellos no puede leer phpMyAdmin (es otro origen para el navegador)
<Location "/phpmyadmin">
    # Por localhost (un marcador antiguo, la costumbre de XAMPP), a su portada en 127.0.0.1: siempre
    # la misma direccion, sin lo que llevara detras. Por cualquier otro dominio, un 403 con el aviso
    <If "%{HTTP_HOST} =~ /^localhost(:[0-9]+)?$/i">
        # (el ? del final: Redirect añadiria la consulta de antes)
        Redirect 302 "http://127.0.0.1/phpmyadmin/?"
    </If>
    <ElseIf "%{HTTP_HOST} !~ /^(127\.0\.0\.1|\[::1\])(:[0-9]+)?$/">
        Require all denied
        ErrorDocument 403 "phpMyAdmin esta en http://127.0.0.1/phpmyadmin/ (lvm-instalador)"
    </ElseIf>
    # Lo que manda otra web (un formulario o un fetch a 127.0.0.1): el navegador pone ese dominio y
    # phpMyAdmin, que entra como root sin contraseña, lo ejecutaria aunque la web no pueda leer la
    # respuesta. Desde otra web solo se puede abrir la portada con un enlace; escribiendo la
    # direccion, desde lvm-instalador o dentro de phpMyAdmin, todo funciona igual
    <If "(%{HTTP:Sec-Fetch-Site} =~ /^(cross-site|same-site)$/i && !(%{REQUEST_METHOD} =~ /^(GET|HEAD)$/ && -z %{QUERY_STRING} && %{REQUEST_URI} =~ m#^/phpmyadmin/?(index\.php)?$#)) || (%{REQUEST_METHOD} !~ /^(GET|HEAD)$/ && -n %{HTTP:Origin} && %{HTTP:Origin} != '"'"'http://'"'"' . %{HTTP_HOST} && %{HTTP:Origin} != '"'"'https://'"'"' . %{HTTP_HOST})">
        Require all denied
        ErrorDocument 403 "Otra web ha intentado usar phpMyAdmin: no se ha hecho nada. Abrelo escribiendo http://127.0.0.1/phpmyadmin/ o desde lvm-instalador."
    </If>
</Location>
# Su asistente setup y su configuracion, cerrados (sin distinguir mayusculas: en el Mac el disco
# no las distingue y /phpmyadmin/Setup/ abriria setup/)
<LocationMatch "(?i)^/phpmyadmin/setup(/|$)">
    Require all denied
</LocationMatch>
<Files "config.inc.php">
    Require all denied
</Files>

# Configuracion, repositorios, copias de bases y registros de los proyectos (.env, .git, .sql,
# .dump, .old, copias~, debug.log, error_log, auth.json de composer...): no se sirven. Sin distinguir mayusculas (.ENV o .GIT en el Mac)
# Tampoco los registros (.log), los .yml (docker-compose lleva las claves de la BBDD), las copias
# de wp-config.php ni las copias de seguridad de las webs (Duplicator, UpdraftPlus, All-in-One...),
# ni claves y certificados con su clave (.pem, .key, .p12), .ini, .conf o las exportaciones de clientes
# del modulo de boletin de PrestaShop (customers_export_*.csv) y de WP All Import/Export (su carpeta
# wpallimport, con los .zip y .xml de clientes). Tampoco claves de otros programas (.my.cnf, .netrc,
# .pgpass, credentials*.json, .aws, .docker)
<DirectoryMatch "(?i)/\.(git|svn|hg|vscode|idea|ssh|aws|docker)(/|$)">
    Require all denied
</DirectoryMatch>
<DirectoryMatch "(?i)/wp-content/uploads/(sites/[0-9]+/)?wpall(import|export)(/|$)">
    Require all denied
</DirectoryMatch>
<FilesMatch "(?i)(^\.(env.*|git.*|ht.*|envrc|ds_store|npmrc|my\.cnf|netrc|pgpass|s3cfg|mysql_history|bash_history)$|^(credentials|service-account|gcloud-credentials)[^/]*\.json$|\.(sql|sql\.(gz|zip|bz2|xz)|dump|bak|old|orig|save|swp|log|ya?ml|wpress)$|~$|^(debug\.log|error_log|auth\.json)$|^wp-config(?!(\.php|-sample\.php)$)|^(backup|copia|respaldo|bkp)([-_.][^/]*)?\.(zip|tar|tgz|gz|bz2|xz|7z|rar)$|_archive\.(zip|daf)$|wpvivid[^/]*\.(zip|tar|gz)$|\.(pem|key|p12|pfx|jks|ini|conf|sqlite|sqlite3|db)$|^id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$|^customers_export_[^/]*\.(csv|zip|xml|xlsx?)$)">
    Require all denied
</FilesMatch>

# Una web de fuera no puede leer las respuestas de tus proyectos: WordPress responde a cualquier
# origen en su API (Access-Control-Allow-Origin), y se quita si el origen no es la propia web
<IfModule headers_module>
    <If "-n %{HTTP:Origin} && %{HTTP:Origin} != '"'"'http://'"'"' . %{HTTP_HOST} && %{HTTP:Origin} != '"'"'https://'"'"' . %{HTTP_HOST}">
        Header unset Access-Control-Allow-Origin
        Header always unset Access-Control-Allow-Origin
        Header unset Access-Control-Allow-Credentials
        Header always unset Access-Control-Allow-Credentials
    </If>
</IfModule>
TraceEnable Off
'
UNKNOWN_HOST_SSL='
# Lo mismo en HTTPS, con el certificado de localhost de la version
<IfModule ssl_module>
<VirtualHost *:443>
    ServerName localhost
    ServerAlias 127.0.0.1 [::1]
    SSLEngine on
    SSLCertificateFile "etc/ssl.crt/server.crt"
    SSLCertificateKeyFile "etc/ssl.key/server.key"
    <If "%{HTTP_HOST} !~ /^(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?$/">
        Require all denied
        ErrorDocument 403 "Este dominio no tiene vhost en este equipo (lvm-instalador): crea su vhost o entra con localhost."
    </If>
    # En 127.0.0.1 y [::1] solo phpMyAdmin: los proyectos van en localhost
    <If "%{HTTP_HOST} =~ /^(127\.0\.0\.1|\[::1\])(:[0-9]+)?$/ && %{REQUEST_URI} !~ m#^/phpmyadmin(/|$)#">
        Require all denied
        ErrorDocument 403 "En 127.0.0.1 solo esta phpMyAdmin: los proyectos van en http://localhost/ (lvm-instalador)"
    </If>
</VirtualHost>
</IfModule>
'

# Ficheros de configuracion de una version que hay que cambiar: <ruta>|<fichero nuevo>|<que cambia>
SECURE_PY='
import glob, os, re, sys
base, out, v6 = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
UNKNOWN_HOST_CONF, UNKNOWN_HOST_VHOST, UNKNOWN_HOST_SSL = sys.argv[4], sys.argv[5], sys.argv[6]
changes = []
# Un fichero con varios cambios (Listen y el Include de httpd.conf) se escribe una sola vez con
# todos: read() devuelve lo ya cambiado y save() lo pone al dia
pending = {}
def read(path):
    if path in pending:
        return pending[path]
    with open(path, encoding="utf-8", errors="surrogateescape", newline="") as f:
        return f.read()
def save(path, text, what):
    rel = os.path.relpath(path, base)
    for i, (r, dst, w) in enumerate(changes):
        if r == rel:
            changes[i] = (r, dst, w + "; " + what)
            break
    else:
        dst = os.path.join(out, str(len(changes)))
        changes.append((rel, dst, what))
    with open(dst, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
        f.write(text)
    pending[path] = text
def own(path):
    return os.path.isfile(path) and not os.path.islink(path)

# Apache: Listen 80 (o con la IP de la red, 0.0.0.0, * o [::]) -> Listen 127.0.0.1:80 y
# Listen [::1]:80 (los vhosts *:80 siguen igual). Los de 127.x, [::1] y localhost se quedan
listen = re.compile(r"^([ \t]*)Listen[ \t]+\"?(?:(\[[0-9A-Fa-f:.]*\]|[^\s:\[\]\"]+):)?(\d+)\"?([ \t]+[A-Za-z]+)?[ \t]*(\r?)$", re.M | re.I)
LOOP = re.compile(r"^(127\.\d+\.\d+\.\d+|\[::1\]|localhost)$", re.I)
confs = [os.path.join(base, "etc/httpd.conf"), os.path.join(base, "apache2/conf/httpd.conf")]
confs += sorted(glob.glob(os.path.join(base, "etc/extra/**/*.conf"), recursive=True))
http_ports = set()
# Direcciones y puertos ya escritos (en todos los ficheros): dos Listen iguales no dejan arrancar
# Apache («Cannot define multiple Listeners on the same IP:port»); el repetido se comenta
# Solo entre los ficheros que Apache carga de verdad (etc/httpd.conf y sus Include): otro httpd.conf
# suelto (el de fabrica de apache2/conf en las pilas propias) tiene sus propios Listen
def loaded():
    seen, todo = set(), [os.path.join(base, "etc/httpd.conf")]
    while todo:
        f = todo.pop()
        if f in seen or not own(f):
            continue
        seen.add(f)
        for inc in re.findall(r"(?mi)^[ \t]*Include(?:Optional)?[ \t]+\"?([^\"\s]+)", read(f)):
            if not inc.startswith("/"):
                inc = os.path.join(base, inc)
            else:
                for mark in ("/lampp/", "/xamppfiles/"):
                    if mark in inc and not inc.startswith(base + "/"):
                        inc = os.path.join(base, inc.split(mark, 1)[1])
                        break
            todo += glob.glob(inc)
    return seen
LOADED = loaded()
bound, bound_other = set(), {}
def addrs(addr, port):
    a = (addr or "").lower()
    if a == "localhost":
        return {("127.0.0.1", port), ("[::1]", port)}
    return {(a, port)}
for path in confs:
    if os.path.basename(path) == "httpd-vhosts.conf" or not own(path):
        continue
    text = read(path)
    ports = []
    bset = bound if path in LOADED else bound_other.setdefault(path, set())
    for m in listen.finditer(text):
        # Los de SSL no (httpd-ssl.conf, «https» o el 443): un vhost sin SSL delante romperia su https
        if (m.group(4) or "").strip().lower() != "https" and m.group(3) != "443" \
                and "ssl" not in os.path.basename(path).lower():
            http_ports.add(m.group(3))
    def fix(m):
        sp, port, proto, cr = m.group(1), m.group(3), m.group(4) or "", m.group(5)
        if m.group(2) and LOOP.match(m.group(2)):
            mine = addrs(m.group(2), port)
            if mine & bset:
                ports.append(port)
                return "%s# (lvm-instalador: repetido) %s" % (sp, m.group(0).lstrip())
            bset.update(mine)
            return m.group(0)
        ports.append(port)
        want = [a for a in (["127.0.0.1", "[::1]"] if v6 else ["127.0.0.1"]) if (a, port) not in bset]
        bset.update((a, port) for a in want)
        if not want:
            return "%s# (lvm-instalador: abierto a la red) %s" % (sp, m.group(0).lstrip())
        return "\n".join("%sListen %s:%s%s%s" % (sp, a, port, proto, cr) for a in want)
    new = listen.sub(fix, text)
    if new != text:
        save(path, new, "Apache, solo desde este equipo (puerto %s)" % ", ".join(ports))

# Apache: primer vhost del puerto 80 (etc/extra/lvm-dominio-desconocido.conf), incluido antes de los
# vhosts. Recibe los dominios que no tiene ningun vhost y solo deja pasar localhost
path = os.path.join(base, "etc/httpd.conf")
if own(path):
    text = read(path)
    vhosts = re.search(r"(?m)^([ \t]*)Include[ \t]+\"?etc/extra/httpd-vhosts\.conf\"?[ \t]*(\r?)$", text)
    if vhosts and UNKNOWN_HOST_CONF not in text:
        sp, cr = vhosts.group(1), vhosts.group(2)
        new = text[:vhosts.start()] + "%sInclude %s%s\n" % (sp, UNKNOWN_HOST_CONF, cr) + text[vhosts.start():]
        save(path, new, "Apache, rechaza los dominios sin vhost")
    elif UNKNOWN_HOST_CONF not in text:
        # Sin vhosts (Include comentado): al final, para que las reglas valgan igual
        nl = "\r\n" if "\r\n" in text else "\n"
        new = text + ("" if text.endswith("\n") else nl) + "# lvm-instalador" + nl + "Include " + UNKNOWN_HOST_CONF + nl
        save(path, new, "Apache, rechaza los dominios sin vhost")
    # El fichero es de lvm-instalador: si es de una version anterior (o le falta el 443), se rehace
    conf = os.path.join(base, UNKNOWN_HOST_CONF)
    want = UNKNOWN_HOST_VHOST
    # Otros puertos http (un Listen 8080 puesto a mano): tambien los recibe, si no evil.com:8080
    # resuelto a 127.0.0.1 llegaria a htdocs (DNS rebinding)
    # (y los que los vhosts usan con SSLEngine on)
    try:
        vtext = open(os.path.join(base, "etc/extra/httpd-vhosts.conf"), errors="replace").read()
    except OSError:
        vtext = ""
    for blk in re.findall(r"(?is)<VirtualHost\s+([^>]*)>(.*?)</VirtualHost>", vtext):
        if re.search(r"(?im)^\s*SSLEngine\s+on\b", blk[1]):
            http_ports -= set(re.findall(r":(\d+)", blk[0]))
    extra = sorted(http_ports - {"80"}, key=int)
    if extra and "<VirtualHost *:80>" in want:
        want = want.replace("<VirtualHost *:80>", "<VirtualHost %s>" % " ".join("*:" + x for x in ["80"] + extra), 1)
    if os.path.isfile(os.path.join(base, "etc/ssl.crt/server.crt")) \
            and os.path.isfile(os.path.join(base, "etc/ssl.key/server.key")):
        want += UNKNOWN_HOST_SSL
    if not os.path.lexists(conf):
        save(conf, want, "Apache, vhost para los dominios sin vhost")
    elif own(conf) and read(conf).startswith("# lvm-instalador:") and read(conf) != want:
        save(conf, want, "Apache, phpMyAdmin en 127.0.0.1 y sin .env, .git ni copias de bases")

# MariaDB: bind-address = 127.0.0.1 en [mysqld] si no tiene un bind-address de este equipo ni
# skip-networking. Un bind-address abierto (0.0.0.0, ::, *, la IP de la red) o skip-networking=0 se
# comentan: estaban ahi, pero dejaban entrar desde la red
path = os.path.join(base, "etc/my.cnf")
if own(path):
    text = read(path)
    nl = "\r\n" if "\r\n" in text else "\n"
    section, has, out_lines = None, False, []
    for line in text.splitlines(True):
        s = line.strip()
        m = re.match(r"\[([^\]]+)\]", s)
        if m:
            section = m.group(1).strip().lower()
        elif section in ("mysqld", "mariadb", "mariadbd", "server"):
            b = re.match(r"(?i)bind[-_]address\s*=\s*[\"\x27]?([^\s\"\x27#;]*)", s)
            k = re.match(r"(?i)skip[-_]networking\b\s*(?:=\s*[\"\x27]?([^\s\"\x27#;]*))?", s)
            if b:
                if b.group(1).lower() in ("127.0.0.1", "::1", "localhost"):
                    has = True
                else:
                    line = "# (lvm-instalador: abierto a la red) " + line
            elif k:
                if (k.group(1) or "1").lower() in ("1", "on", "true", "yes", ""):
                    has = True
                else:
                    line = "# (lvm-instalador: abierto a la red) " + line
        out_lines.append(line)
    if "".join(out_lines) != text:
        text = "".join(out_lines)
        save(path, text, "MariaDB, sin el bind-address abierto a la red")
    if not has:
        add = "# Solo desde este equipo (lvm-instalador)" + nl + "bind-address = 127.0.0.1" + nl
        m = re.search(r"(?m)^[ \t]*\[mysqld\][ \t]*\r?(\n|$)", text)
        if m:
            head = text[:m.end()]
            new = head + ("" if head.endswith("\n") else nl) + add + text[m.end():]
        else:
            new = text + ("" if text.endswith("\n") or not text else nl) + nl + "[mysqld]" + nl + add
        save(path, new, "MariaDB, solo desde este equipo (bind-address)")

# MariaDB: sin leer ni escribir ficheros del equipo desde SQL. Con secure_file_priv vacio (el de
# XAMPP), root (phpMyAdmin entra como root sin contraseña) lee cualquier fichero con LOAD_FILE y
# escribe un PHP en htdocs con INTO OUTFILE. Se limita a una carpeta vacia de root, que tiene que
# existir (si falta, MariaDB no arranca), y sin LOAD DATA LOCAL. Una carpeta puesta a mano se respeta
NOFILES = os.path.join(base, "etc/lvm-sin-ficheros")
if own(path):
    text = read(path)
    nl = "\r\n" if "\r\n" in text else "\n"
    section, priv, infile, out_lines = None, None, False, []
    for line in text.splitlines(True):
        s = line.strip()
        m = re.match(r"\[([^\]]+)\]", s)
        if m:
            section = m.group(1).strip().lower()
        elif section in ("mysqld", "mariadb", "mariadbd", "server"):
            p = re.match(r"(?i)(?:loose[-_])?secure[-_]file[-_]priv\s*=\s*[\"\x27]?([^\"\x27#;]*?)[\"\x27]?\s*(?:[#;].*)?$", s)
            k = re.match(r"(?i)(?:loose[-_])?local[-_]infile\b\s*(?:=\s*[\"\x27]?([^\s\"\x27#;]*))?", s)
            if p:
                if p.group(1).strip():
                    priv = p.group(1).strip()
                else:
                    line = "# (lvm-instalador: dejaba leer y escribir ficheros) " + line
            elif k:
                if (k.group(1) or "1").lower() in ("0", "off", "false", "no"):
                    infile = True
                else:
                    line = "# (lvm-instalador: dejaba leer y escribir ficheros) " + line
        out_lines.append(line)
    new = "".join(out_lines)
    add = ""
    if priv is None:
        add += "secure-file-priv = \"%s\"%s" % (NOFILES, nl)
        priv = NOFILES
    if not infile:
        add += "local-infile = 0" + nl
    if add:
        add = "# Sin leer ni escribir ficheros del equipo desde SQL (lvm-instalador)" + nl + add
        m = re.search(r"(?m)^[ \t]*\[mysqld\][ \t]*\r?(\n|$)", new)
        if m:
            head = new[:m.end()]
            new = head + ("" if head.endswith("\n") else nl) + add + new[m.end():]
        else:
            new = new + ("" if new.endswith("\n") or not new else nl) + nl + "[mysqld]" + nl + add
    if new != text:
        save(path, new, "MariaDB, sin leer ni escribir ficheros desde SQL (secure_file_priv)")
    if os.path.normpath(priv) == NOFILES and not os.path.isdir(NOFILES):
        # (una carpeta, no un fichero: secure_lampp la crea de root)
        changes.append(("etc/lvm-sin-ficheros/", "", "MariaDB, carpeta vacia de secure_file_priv"))

# ProFTPD: DefaultAddress 127.0.0.1 y SocketBindTight on, detras de Port
path = os.path.join(base, "etc/proftpd.conf")
if own(path):
    text = read(path)
    # Un DefaultAddress de la red o SocketBindTight off: abiertos, se cambian
    new = re.sub(r"(?mi)^([ \t]*DefaultAddress[ \t]+)(?!127\.0\.0\.1[ \t]*\r?$)(\S.*?)([ \t]*\r?)$",
                 r"\g<1>127.0.0.1\3", text)
    new = re.sub(r"(?mi)^([ \t]*SocketBindTight[ \t]+)off\b", r"\g<1>on", new)
    if new != text:
        save(path, new, "FTP, solo desde este equipo (DefaultAddress)")
        text = new
    if not re.search(r"(?mi)^[ \t]*DefaultAddress\b", text):
        nl = "\r\n" if "\r\n" in text else "\n"
        add = "# Solo desde este equipo (lvm-instalador)" + nl + "DefaultAddress 127.0.0.1" + nl
        if not re.search(r"(?mi)^[ \t]*SocketBindTight\b", text):
            add += "SocketBindTight on" + nl
        m = re.search(r"(?mi)^[ \t]*Port\b[^\n]*\n", text)
        new = text[:m.end()] + add + text[m.end():] if m else add + text
        save(path, new, "FTP, solo desde este equipo (DefaultAddress)")
        text = new
    # XAMPP trae el usuario daemon con la contraseña de fabrica (xampp), igual en todos los equipos
    new = re.sub(r"(?mi)^([ \t]*)(UserPassword[ \t]+daemon\b.*)$",
                 r"\1# (lvm-instalador: sin la contraseña de fabrica de XAMPP) \2", text)
    if new != text:
        save(path, new, "FTP, sin el usuario daemon con la contraseña de fabrica")
        text = new
    user = os.environ.get("LVM_FTP_USER") or os.environ.get("SUDO_USER") or os.environ.get("USER") or ""
    if re.fullmatch(r"[a-z_][a-z0-9_-]{0,31}", user) and not re.search(r"(?mi)^[ \t]*<Limit[ \t]+LOGIN", text):
        nl = "\r\n" if "\r\n" in text else "\n"
        add = nl + "# Solo tu usuario puede entrar por FTP (lvm-instalador)" + nl + "<Limit LOGIN>" + nl \
            + "    AllowUser " + user + nl + "    DenyAll" + nl + "</Limit>" + nl
        save(path, text + ("" if text.endswith("\n") else nl) + add, "FTP, solo entra tu usuario")

# Pilas propias de versiones anteriores: el FTP arrancaba siempre con la version. Ahora solo si se
# ha activado (etc/lvm-startftp, como etc/xampp/startftp en XAMPP)
path = os.path.join(base, "lampp")
if own(os.path.join(base, "etc/lvm-stack")) and own(path):
    text = read(path)
    if "lvm-startftp" not in text:
        new = re.sub(r"(?m)^(\s*start\) .*; start_apache); start_ftp ;;$",
                     r"""\1; if [ -f "$ROOT/etc/lvm-startftp" ]; then start_ftp; fi ;;""", text)
        new = re.sub(r"(?m)^(\s*)startftp\) start_ftp ;;$",
                     r"""\1startftp) touch "$ROOT/etc/lvm-startftp"; start_ftp ;;""", new)
        new = re.sub(r"(?m)^(\s*)stopftp\) stop_ftp ;;$",
                     r"""\1stopftp) rm -f "$ROOT/etc/lvm-startftp"; stop_ftp ;;""", new)
        if new != text:
            save(path, new, "El FTP solo arranca si se activa en Servicios")

# Certificado de fabrica de XAMPP (Apache Friends, de 2004, RSA de 1024 bits): su clave es la misma
# en todos los XAMPP y se puede descargar. Se cambia por uno propio de este equipo (localhost). La
# clave nueva solo se crea al aplicar (LVM_SECURE_APPLY): al comprobar basta con saber que falta
crt = os.path.join(base, "etc/ssl.crt/server.crt")
key = os.path.join(base, "etc/ssl.key/server.key")
def factory_cert(path):
    import base64, binascii
    pem = "".join(l.strip() for l in read(path).splitlines() if l.strip() and not l.startswith("-----"))
    try:
        return b"Apache Friends" in base64.b64decode(pem)
    except (binascii.Error, ValueError):
        return False
if own(crt) and own(key) and factory_cert(crt):
    import subprocess, tempfile
    if os.environ.get("LVM_SECURE_APPLY") == "1":
        d = tempfile.mkdtemp(dir=out)
        # Las extensiones van en un fichero de configuracion y no con -addext: la LibreSSL de macOS 12
        # (la que usa root, con el PATH del sistema) no tiene -addext
        with open(os.path.join(d, "cnf"), "w") as f:
            f.write("[req]\ndistinguished_name = dn\nx509_extensions = ext\nprompt = no\n[dn]\nCN = localhost\n"
                    "[ext]\nbasicConstraints = critical,CA:FALSE\n"
                    "subjectAltName = DNS:localhost,IP:127.0.0.1,IP:0:0:0:0:0:0:0:1\n")
        r = subprocess.run(["openssl", "req", "-x509", "-nodes", "-newkey", "rsa:2048", "-days", "3650",
                            "-config", os.path.join(d, "cnf"),
                            "-keyout", os.path.join(d, "key"), "-out", os.path.join(d, "crt")],
                           stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode == 0:
            # (el certificado primero: se escriben en este orden)
            save(crt, read(os.path.join(d, "crt")), "Apache, certificado SSL propio")
            save(key, read(os.path.join(d, "key")), "Apache, clave SSL propia (la de XAMPP es la misma en todos)")
    else:
        save(crt, "", "Apache, clave SSL propia (la de XAMPP es la misma en todos)")
# Pilas propias de la 1.44 y anteriores: el script lampp (que corre como root) cerraba el numero que
# hubiera en el .pid de MariaDB, que escribe mysql. Ahora, solo un numero de verdad y del MariaDB
path = os.path.join(base, "lampp")
if own(path):
    text = read(path)
    if "pila propia creada por lvm-instalador" in text and "function pid_in()" not in text:
        new = text
        for old, rep in (("function running() {\n    [ -f \"$1\" ] && kill -0 \"$(cat \"$1\" 2> /dev/null)\" 2> /dev/null\n}\n",
                          "# Numero de proceso de un .pid: solo un numero de verdad (ni 0, ni 1, ni negativo). Este script\n# corre como root y el .pid de MariaDB lo escribe mysql\nfunction pid_in() {\n    local p\n    p=$(head -c 20 \"$1\" 2> /dev/null | tr -d \" \\n\")\n    [[ \"$p\" =~ ^[0-9]+$ ]] && [ \"$p\" -gt 1 ] && echo \"$p\"\n}\n\nfunction running() {\n    local p\n    p=$(pid_in \"$1\") && kill -0 \"$p\" 2> /dev/null\n}\n"),
                         ("    kill \"$(cat \"$MYSQL_PID\")\"\n",
                          "    local p\n    # (y solo si es el MariaDB: su .pid lo podria cambiar mysql)\n    p=$(pid_in \"$MYSQL_PID\") && [[ \"$(cat \"/proc/$p/comm\" 2> /dev/null)\" =~ ^(mariadbd|mysqld)$ ]] && kill \"$p\"\n"),
                         ("    kill \"$(cat \"$FTP_PID\")\"\n",
                          "    local p\n    p=$(pid_in \"$FTP_PID\") && kill \"$p\"\n")):
            new = new.replace(old, rep, 1) if old in new else ""
        if new:
            save(path, new, "Script lampp: solo cierra los procesos de sus .pid de verdad")
# (las carpetas primero: si no se pudiera crear la de secure_file_priv, no se cambia el my.cnf)
for c in sorted(changes, key=lambda c: not c[0].endswith("/")):
    print("|".join(c))
'

# Antes de arrancar una version: si no se ha podido dejar solo para este equipo (secure_lampp
# devolvio 2), no se arranca, porque quedaria abierta a la red. secure_failed <codigo> <carpeta>
function secure_failed() {
    [ "$1" -eq 2 ] && [ "$DRY" -eq 0 ] || return 1
    echo "No se arranca $(basename "$2"): no se ha podido dejar solo para este equipo."
    echo "Prueba con: lvm-instalador asegurar --todas"
    return 0
}

# Lineas Listen de los vhosts compartidos que abren Apache a la red (sin 127.x, [::1] ni localhost).
# Apache las lee, pero SECURE_PY no cambia los vhosts (son de todas las versiones y de root): solo se
# pueden poner a mano (sudo -e), por ejemplo siguiendo una guia de vhosts por puerto
function vhosts_open_listen() {
    local real
    real=$(readlink -f "$VHOSTS_FILE" 2> /dev/null) && [ -f "$real" ] || return 0
    python3 -I - "$real" <<'EOF'
import re, sys
# Como Apache: lineas solo por \n, las acabadas en \ unidas a la siguiente y los campos separados
# por cualquier espacio ASCII (\v, \f, \r tambien). Un Include no se sigue: tambien se avisa
lines = open(sys.argv[1], encoding="utf-8", errors="replace", newline="\n").read().split("\n")
i = 0
while i < len(lines):
    n, line = i + 1, lines[i].rstrip("\r")
    while line.endswith("\\") and i + 1 < len(lines):
        i += 1
        line = line[:-1] + lines[i].rstrip("\r")
    i += 1
    w = re.split(r"[ \t\v\f\r]+", line.strip(" \t\v\f\r"), maxsplit=1)
    if w[0].lower() in ("include", "includeoptional"):
        print("Linea %d: %s (no se puede comprobar lo que trae)" % (n, re.sub(r"[\x00-\x1f\x7f]", " ", line.strip())[:120]))
        continue
    if w[0].lower() != "listen" or len(w) < 2:
        continue
    m = re.match(r"^[\"\x27]?(?:(\[[0-9A-Fa-f:.]*\]|[^\s:\[\]\"\x27]+):)?(\d+)", w[1])
    if m and not (m.group(1) and re.match(r"^(127\.\d+\.\d+\.\d+|\[::1\]|localhost)$", m.group(1), re.I)):
        print("Linea %d: %s" % (n, re.sub(r"[\x00-\x1f\x7f]", " ", line.strip())[:120]))
EOF
}

# Deja una version solo para este equipo (lo que falte). Devuelve 0 si ha cambiado algo (si esta en
# marcha, hay que reiniciarla para aplicarlo), 1 si no hacia falta y 2 si no se ha podido: entonces
# no se arranca (se queda como estaba, abierta a la red).
function secure_lampp() {
    local dir=$1 tmp list rel src what changed=1 v6=0 name
    [ -n "$dir" ] && [ -d "$dir" ] && [ ! -L "$dir" ] && [ -f "$dir/etc/httpd.conf" ] || return 1
    # Las pruebas sin sudo (LVM_PRUEBA) ya se instalan asi
    [ -n "$TEST_DIR" ] && return 1
    name=$(basename "$dir")
    has_ipv6_loopback && v6=1
    # Un Listen abierto en los vhosts compartidos dejaria Apache abierto a la red aunque la version
    # este cerrada: no se arranca hasta quitarlo (se avisa una vez aunque se miren varias versiones)
    local open
    open=$(vhosts_open_listen)
    if [ -n "$open" ]; then
        if [ -z "$LISTEN_WARNED" ]; then
            echo "Los vhosts ($VHOSTS_FILE) abren Apache a la red (o traen otros ficheros):"
            sed 's/^/  /' <<< "$open"
            echo "Quita esas lineas con Editar vhosts (pestaña Herramientas) y vuelve a arrancarla."
            LISTEN_WARNED=1
        fi
        return 2
    fi
    # Los ficheros nuevos se preparan como root en una carpeta de root: en una tuya, cualquier
    # programa tuyo podria cambiarlos (un ErrorLog "|orden" en httpd.conf) antes de que root los
    # copie a la version. En la simulacion, como antes, en una tuya y sin sudo
    # Primero se mira sin sudo si hay algo que cambiar (casi siempre no)
    local rooted=0
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-seguridad.XXXXXX") || return 2
    list=$(/usr/bin/python3 -I -c "$SECURE_PY" "$dir" "$tmp" "$v6" "$UNKNOWN_HOST_CONF" "$UNKNOWN_HOST_VHOST" \
        "$UNKNOWN_HOST_SSL") || { rm -rf "$tmp"; return 2; }
    rm -rf "$tmp"
    local sudo=sudo
    if [ -n "$list" ]; then
        if [ "$DRY" -eq 1 ]; then
            sudo=""
            tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-seguridad.XXXXXX") || return 2
        else
            tmp=$(sudo mktemp -d /tmp/lvm-seguridad.XXXXXX) && sudo chmod 700 "$tmp" || return 2
        fi
        list=$($sudo env LVM_SECURE_APPLY=1 LVM_FTP_USER="${SUDO_USER:-$USER}" /usr/bin/python3 -I -c "$SECURE_PY" "$dir" \
            "$tmp" "$v6" "$UNKNOWN_HOST_CONF" "$UNKNOWN_HOST_VHOST" "$UNKNOWN_HOST_SSL") || { $sudo rm -rf "$tmp"; return 2; }
        rooted=1
    fi
    while IFS='|' read -r rel src what; do
        [ -n "$rel" ] || continue
        [ $changed -eq 1 ] && echo "Seguridad de $name: solo se podra entrar desde este equipo"
        changed=0
        echo "  $what ($rel)"
        [ "$DRY" -eq 1 ] && continue
        # Una carpeta (la vacia de secure_file_priv): de root y sin nada dentro
        if [[ "$rel" == */ ]]; then
            if [ -L "$dir/${rel%/}" ] || ! sudo install -d -o 0 -g 0 -m 755 "$dir/${rel%/}"; then
                echo "  No se ha podido crear $dir/${rel%/}"
                sudo rm -rf "$tmp"
                return 2
            fi
            continue
        fi
        # (los ficheros nuevos, como lvm-dominio-desconocido.conf, no tienen copia)
        [ -f "$dir/$rel" ] && mkdir -p -m 700 "$HOME/lvm-copias" \
            && cp "$dir/$rel" "$HOME/lvm-copias/$name-$(basename "$rel")-$(date +%Y%m%d-%H%M%S)" 2> /dev/null
        sudo sh -c 'cat "$1" > "$2"' sh "$src" "$dir/$rel" || { sudo rm -rf "$tmp"; return 2; }
        [[ "$rel" == *.key ]] && sudo chmod 600 "$dir/$rel"
    done <<< "$list"
    [ $rooted -eq 1 ] && $sudo rm -rf "$tmp"

    # XAMPP trae ficheros que cualquier usuario del equipo puede cambiar (librerias PHP de lib/php
    # como fpdf.php, licencias) y la carpeta temp de las sesiones de PHP abierta a todos sin el bit
    # pegajoso (cualquiera podia borrar o cambiar las sesiones de otro)
    local loose=0 open_temp=0 said=0
    [ -n "$(find "$dir/lib/php" "$dir/licenses" -xdev -type f -perm -o+w -print -quit 2> /dev/null)" ] && loose=1
    [ -d "$dir/temp" ] && [ ! -L "$dir/temp" ] && [ "$(stat -c %a "$dir/temp")" == "777" ] && open_temp=1
    # (solo permisos: no hace falta reiniciar, asi que no cuenta como cambio)
    if [ $loose -eq 1 ] || [ $open_temp -eq 1 ]; then
        [ $changed -eq 1 ] && echo "Seguridad de $name:" && said=1
        [ $loose -eq 1 ] && echo "  Ficheros de lib/php y licenses que podia cambiar cualquier usuario: ya solo root"
        [ $open_temp -eq 1 ] && echo "  temp (sesiones de PHP): cada usuario solo puede borrar lo suyo (bit pegajoso)"
        if [ "$DRY" -eq 0 ]; then
            [ $loose -eq 1 ] && sudo find "$dir/lib/php" "$dir/licenses" -xdev -type f -perm -o+w -exec chmod o-w {} +
            [ $open_temp -eq 1 ] && sudo chmod 1777 "$dir/temp"
        fi
    fi

    # Una sola vez por version: el FTP deja de arrancar con ella (se activa en Servicios)
    if [ ! -f "$dir/$SECURE_MARK" ]; then
        if [ -f "$dir/etc/xampp/startftp" ] || [ -f "$dir/etc/lvm-startftp" ]; then
            [ $changed -eq 1 ] && [ $said -eq 0 ] && echo "Seguridad de $name:"
            echo "  El FTP ya no arranca con la version: activalo en la pestaña Servicios cuando lo necesites"
            changed=0
            if [ "$(active_dir)" == "$dir" ] && service_running ftp; then
                run sudo /opt/lampp/lampp stopftp
            fi
            run sudo rm -f "$dir/etc/xampp/startftp" "$dir/etc/lvm-startftp"
        fi
        if [ "$DRY" -eq 0 ]; then
            echo "1" | sudo tee "$dir/$SECURE_MARK" > /dev/null
        fi
    fi
    return $changed
}

# Todas las versiones instaladas, solo para este equipo: si una se arranca a mano (sudo
# /opt/lampp-8.1/lampp start), tampoco queda abierta a la red. Devuelve como secure_lampp: 0 si ha
# cambiado algo, 1 si no hacia falta y 2 si alguna no se ha podido.
function secure_all() {
    local d rc=1 r
    for d in $(lampp_dirs); do
        [ -L "$d" ] && continue
        secure_lampp "$d"
        r=$?
        [ $r -eq 2 ] && { echo "No se ha podido dejar $(basename "$d") solo para este equipo"; rc=2; }
        [ $r -eq 0 ] && [ $rc -eq 1 ] && rc=0
    done
    return $rc
}

# Versiones a las que les falta algo para ser solo de este equipo (lo que cambiaria secure_lampp),
# separadas por espacios. Para avisar en la ventana: protegerlas pide la contraseña.
function unsecured_versions() {
    local d tmp list out=""
    [ -n "$TEST_DIR" ] && return 0
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-seguridad.XXXXXX") || return 0
    for d in $(lampp_dirs); do
        [ -L "$d" ] || [ ! -f "$d/etc/httpd.conf" ] && continue
        list=$(python3 -I -c "$SECURE_PY" "$d" "$tmp" 1 "$UNKNOWN_HOST_CONF" "$UNKNOWN_HOST_VHOST" \
            "$UNKNOWN_HOST_SSL" 2> /dev/null)
        if [ -n "$list" ] || { [ ! -f "$d/$SECURE_MARK" ] \
                && { [ -f "$d/etc/xampp/startftp" ] || [ -f "$d/etc/lvm-startftp" ]; }; }; then
            out+="${out:+ }${d#/opt/lampp-}"
        fi
        rm -f "$tmp"/*
    done
    rm -rf "$tmp"
    echo "$out"
}

# ¿Esta en marcha un servicio (apache, mariadb o ftp) de la version montada?
function service_running() {
    local rx
    case $1 in
        apache) rx='^(httpd|apache2)$' ;;
        mariadb) rx='^(mysqld|mariadbd)$' ;;
        ftp) rx='^proftpd$' ;;
        *) return 1 ;;
    esac
    lampp_processes | awk -F'|' -v rx="$rx" '$6 == 0 && $7 ~ rx { f = 1 } END { exit !f }'
}

# Puertos de LAMPP que escuchan en toda la red y no solo en este equipo, uno por linea
function exposed_ports() {
    command -v ss > /dev/null || return 0
    ss -Htln 2> /dev/null | awk -v ports=" $PORT_HTTP $PORT_HTTPS $PORT_MYSQL $PORT_FTP " '{
        a = $4; p = a; sub(/.*:/, "", p); h = substr(a, 1, length(a) - length(p) - 1)
        if (index(ports, " " p " ") && h !~ /^(127\.|\[::1\]|::1$|\[::ffff:127\.)/ && h !~ /%lo$/) print p
    }' | sort -un
}

# Servicios abiertos a la red, para avisar: «Apache (80, 443), MariaDB (3306)»
function exposed_summary() {
    local ports p apache="" out=""
    lampp_running || return 0
    ports=$(exposed_ports)
    [ -z "$ports" ] && return 0
    for p in $ports; do
        case $p in
            "$PORT_HTTP"|"$PORT_HTTPS") apache+="${apache:+, }$p" ;;
        esac
    done
    [ -n "$apache" ] && out="Apache ($apache)"
    grep -qx "$PORT_MYSQL" <<< "$ports" && out+="${out:+, }MariaDB ($PORT_MYSQL)"
    grep -qx "$PORT_FTP" <<< "$ports" && out+="${out:+, }FTP ($PORT_FTP)"
    echo "$out"
}

# ¿Arranca el FTP con la version? (lo activa «servicio ftp arrancar» y lo quita «servicio ftp parar»)
function ftp_autostart() {
    [ -f "$1/etc/xampp/startftp" ] || [ -f "$1/etc/lvm-startftp" ]
}

# asegurar [version]: lo que falte para que solo se pueda entrar desde este equipo. Si es la version
# en marcha y algo sigue abierto a la red, se reinicia para aplicarlo.
function secure_command() {
    local version=$1 dir changed=1 rc
    if [ "$version" == "--todas" ]; then
        secure_all
        rc=$?
        htdocs_close_world "$HTDOCS_DIR" --otros
        hosts_fake locales
        vhosts_root
        [ $rc -eq 2 ] && return 1
        dir=$(active_dir)
        if [ -n "$dir" ] && lampp_running && { [ $rc -eq 0 ] || [ -n "$(exposed_ports)" ]; }; then
            echo "Reiniciando $(basename "$dir") para aplicarlo..."
            run sudo /opt/lampp/lampp restart > /dev/null || { echo "No se ha podido reiniciar"; return 1; }
        fi
        lampp_running && wait_mariadb && secure_mariadb
        echo "Todas las versiones son solo para este equipo"
        return 0
    fi
    if [ -n "$version" ]; then
        valid_version_name "$version" && [ -d "/opt/lampp-$version" ] \
            || { echo "No existe la version $version de lampp en el sistema"; return 1; }
        dir=/opt/lampp-$version
    else
        dir=$(active_dir)
        [ -n "$dir" ] || { echo "No hay ninguna version activa (indica cual: lvm-instalador asegurar <version>)"; return 1; }
    fi
    secure_lampp "$dir"
    rc=$?
    [ $rc -eq 2 ] && { echo "No se ha podido dejar $(basename "$dir") solo para este equipo"; return 1; }
    [ $rc -eq 0 ] && changed=0
    vhosts_root && changed=0
    if [ "$dir" == "$(active_dir)" ] && lampp_running && { [ $changed -eq 0 ] || [ -n "$(exposed_ports)" ]; }; then
        echo "Reiniciando $(basename "$dir") para aplicarlo..."
        run sudo /opt/lampp/lampp restart > /dev/null || { echo "No se ha podido reiniciar"; return 1; }
        [ "$DRY" -eq 1 ] && return 0
        sleep 1
        local left=$(exposed_summary)
        if [ -n "$left" ]; then
            echo "Sigue abierto a la red: $left"
            echo "Puede que no sea de LAMPP (otro programa en el mismo puerto): lvm-instalador procesos"
            return 1
        fi
    fi
    [ "$dir" == "$(active_dir)" ] && lampp_running && wait_mariadb && secure_mariadb
    [ $changed -eq 1 ] && echo "$(basename "$dir") ya era solo para este equipo: no hay nada que cambiar"
    echo "Solo se puede entrar desde este equipo"
}

# servicio apache|mariadb|ftp arrancar|parar|reiniciar: un servicio de la version montada (lo que
# hace el panel de XAMPP). El FTP arrancado asi sigue arrancando con la version hasta que se pare.
function service_control() {
    local name=$1 action=$2 dir cmds=() c
    dir=$(active_dir)
    if [ -z "$dir" ]; then
        echo "No hay ninguna version activa"

        return 1
    fi
    case "$name" in
        apache) c=apache ;;
        mariadb|mysql) c=mysql ;;
        ftp) c=ftp ;;
        *) echo "Uso: lvm-instalador servicio apache|mariadb|ftp arrancar|parar|reiniciar"; return 1 ;;
    esac
    case "$action" in
        arrancar|start) cmds=("start$c") ;;
        parar|stop) cmds=("stop$c") ;;
        reiniciar|restart) cmds=("stop$c" "start$c") ;;
        *) echo "Uso: lvm-instalador servicio apache|mariadb|ftp arrancar|parar|reiniciar"; return 1 ;;
    esac
    # Antes de arrancar: solo para este equipo y nada de otras versiones ocupando el puerto
    if [ "${cmds[-1]}" == "start$c" ]; then
        secure_lampp "$dir"
        secure_failed $? "$dir" && return 1
        vhosts_root
        close_processes
    fi
    for c in "${cmds[@]}"; do
        run sudo /opt/lampp/lampp "$c" || return 1
    done
}

# Para la pestaña Servicios: S|servicio|en marcha (1/0)|puertos|abierto a la red (1/0)|arranca con
# la version (1/0)|usuario (FTP), de la version montada
function gui_services() {
    local dir ports p name running port open auto user
    dir=$(active_dir)
    [ -n "$dir" ] || return 0
    ports=$(exposed_ports)
    for name in apache mariadb ftp; do
        running=0
        service_running "$name" && running=1
        case $name in
            apache) port="$PORT_HTTP, $PORT_HTTPS" ;;
            mariadb) port=$PORT_MYSQL ;;
            ftp) port=$PORT_FTP ;;
        esac
        open=0
        if [ $running -eq 1 ]; then
            for p in ${port//,/}; do grep -qx "$p" <<< "$ports" && open=1; done
        fi
        auto=1 user=""
        if [ $name == ftp ]; then
            ftp_autostart "$dir" || auto=0
            if is_stack_install "$dir"; then
                user=$(awk '/<Limit LOGIN>/ { f = 1 } f && $1 == "AllowUser" { print $2; exit }' "$dir/etc/proftpd.conf" 2> /dev/null)
            else
                user=$(awk '$1 == "UserPassword" { print $2; exit }' "$dir/etc/proftpd.conf" 2> /dev/null)
                user=${user:-daemon}
            fi
        fi
        echo "S|$name|$running|$port|$open|$auto|$user"
    done
}

# Lo que falta en la carga de un proyecto: si es PrestaShop, su dominio con vhost, certificado y
# falseado en /etc/hosts; si no, ningun dominio falseado. Recarga Apache si ha cambiado algo.
function load_project_domain() {
    local folder=$1 domain=""
    PS_RELOAD=0
    # Tienda recien clonada: parameters.php con la base cargada y, la primera vez, cache vacia
    if is_prestashop "$folder"; then
        PS_NEW_PARAMS=0
        ps_parameters "$folder" "$2" || return 1
        # Codigo de produccion volcado encima: la configuracion vuelve a la base de la carpeta
        ps_set_db "$folder" "${2:-$(saved_project_db "$folder")}" || return 1
        ps_first_load "$folder"
    fi
    # WordPress con el codigo de produccion pegado encima: wp-config.php con la base de la carpeta
    if ! is_prestashop "$folder" && is_wordpress "$folder"; then
        wp_config "$folder" "$2" || return 1
    fi
    if [ -n "$(ps_config "$folder")" ]; then
        domain=$(ps_domain "$folder")
        if [ -z "$domain" ]; then
            echo "Aviso: $folder es una tienda PrestaShop, pero no se ha podido saber su dominio: su"
            echo "base no se puede leer (¿MariaDB parado o root con contraseña?) y ningun vhost apunta"
            echo "a la carpeta. Crea su vhost (Editar vhosts) y vuelve a cargar el proyecto."
        elif ! vhost_points_to "$domain" "$folder" && grep -qxF -- "$folder" "$REPO_PROJECTS_FILE" 2> /dev/null; then
            # Montada con Montar nuevo proyecto: la base (su volcado) y el nombre de la carpeta (el del
            # repositorio) los elige quien publica el repositorio, asi que el parecido no basta
            echo "La tienda usa el dominio $domain (de su base). No se falsea solo, porque la base y el"
            echo "nombre de la carpeta vienen con el repositorio: si es el suyo, crealo en la pestaña"
            echo "Hosts (Nuevo proyecto con dominio falseado, con la carpeta $folder y ese dominio)."
            domain=""
        elif ! vhost_points_to "$domain" "$folder" && ! domain_fits_folder "$domain" "$folder"; then
            # El dominio viene de la base (shop_url): un volcado manipulado podria llevar uno real
            # (de un banco, de github...) para que este equipo lo mande aqui. Sin vhost suyo, solo
            # se falsea si se parece al nombre de la carpeta
            echo "Aviso: el dominio de la base ($domain) no se parece al nombre de la carpeta $folder:"
            echo "no se le crea vhost ni se falsea. Si es el correcto, crealo en la pestaña Hosts"
            echo "(Nuevo proyecto con dominio falseado) o en los vhosts."
            domain=""
        else
            echo "Tienda PrestaShop: dominio $domain"
            ps_vhost "$folder" "$domain" || return 1
        fi
    elif domain=$(custom_domain "$folder") && [ -n "$domain" ]; then
        # Proyecto nuevo creado con su dominio desde la pestaña Hosts (al crearlo ya se le hace su
        # vhost). El fichero de dominios es tuyo y otro programa podria añadir uno real (github.com):
        # sin vhost suyo, solo si se parece al nombre de la carpeta, como con PrestaShop
        if ! vhost_points_to "$domain" "$folder" && ! domain_fits_folder "$domain" "$folder"; then
            echo "Aviso: el dominio guardado para $folder ($domain) no tiene vhost ni se parece al nombre"
            echo "de la carpeta: no se crea ni se falsea. Si es el correcto, crealo en la pestaña Hosts."
            domain=""
        else
            echo "Proyecto con dominio propio: $domain"
            ps_vhost "$folder" "$domain" || return 1
        fi
    fi
    hosts_fake cargar $domain || return 1
    if [ "$PS_RELOAD" -eq 1 ] && [ -f /opt/lampp/logs/httpd.pid ]; then
        echo "Recargando Apache para aplicar el vhost y el certificado..."
        run sudo /opt/lampp/lampp reloadapache > /dev/null || { echo "No se ha podido recargar Apache. Reinicia la version activa."; return 1; }
    fi
    return 0
}

# ===========================================================================
# Tiendas PrestaShop: parameters.php y cache
# ===========================================================================
# El repositorio de una tienda 1.7 no lleva app/config/parameters.php (esta en su .gitignore): al
# clonarla queda vacio ('parameters' => NULL) y PrestaShop dice "install" directory is missing. Se
# crea con la base cargada en local y claves nuevas, y se guarda una copia en PS_PARAMS_DIR para
# volver a ponerla (con las mismas claves) si se pierde. La primera vez que se carga una tienda se
# vacia su var/cache (la de produccion da error 500 en local); se apunta en PS_LOADED_FILE.
PS_PARAMS_DIR="$HOME/.lvm-instalador/prestashop"
PS_LOADED_FILE="$HOME/.lvm-instalador/prestashop-cargados"
# Carpetas clonadas con montar-proyecto (el dominio de su base no se falsea solo)
REPO_PROJECTS_FILE="$HOME/.lvm-instalador/montados-de-repositorio"

# ¿Es una tienda PrestaShop? Por su configuracion, sus carpetas o "prestashop" en el nombre
function is_prestashop() {
    local dir=$HTDOCS_DIR/$1
    [[ "${1,,}" == *prestashop* ]] || [ -d "$dir/src/PrestaShopBundle" ] \
        || [ -f "$dir/classes/PrestaShopAutoload.php" ] || [ -n "$(ps_config "$1")" ]
}

# Base de una tienda cuya configuracion no la dice: la indicada, la recordada para la carpeta
# (~/.lvm-instalador/proyectos) o, en la version activa, la unica ps_<final de la carpeta>
# (dob-prestashop-mitienda -> ps_mitienda)
function ps_guess_db() {
    local folder=$1 db=$2 tail
    if [ -z "$db" ] && [ -f "$PROJECTS_FILE" ]; then
        db=$(awk -F= -v f="$folder" '$2 == f { d = $1 } END { if (d != "") print d }' "$PROJECTS_FILE")
    fi
    if [ -z "$db" ]; then
        tail=$(tr 'A-Z' 'a-z' <<< "${folder##*[-.]}")
        # Va dentro de la consulta: solo letras, numeros y _
        if [[ "$tail" =~ ^[a-z0-9_]+$ ]]; then
            db=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE LOWER(SCHEMA_NAME) IN ('ps_$tail', '$tail')" < /dev/null 2> /dev/null)
        fi
        [ "$(grep -c . <<< "$db")" == 1 ] || db=""
    fi
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] && echo "$db"
}

# Prefijo de las tablas de una tienda: el de su tabla <prefijo>shop_url (solo letras, numeros y _:
# los nombres de las tablas los trae la base, y el prefijo se usa despues en otras consultas). Si la
# base tiene varias tiendas, el indicado (el que ya usaba su configuracion) si lo tiene; si no, el
# mas corto. ps_table_prefix <base> [prefijo preferido]
function ps_table_prefix() {
    local pref=$2
    [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
    [[ "$pref" =~ ^[A-Za-z0-9_]+$ ]] || pref=""
    "${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT LEFT(TABLE_NAME, LENGTH(TABLE_NAME) - 8) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$1' AND TABLE_TYPE='BASE TABLE' AND TABLE_NAME LIKE '%shop\\_url' ORDER BY TABLE_NAME = '${pref}shop_url' DESC, LENGTH(TABLE_NAME) LIMIT 1" < /dev/null 2> /dev/null \
        | grep -E '^[A-Za-z0-9_]+$'
}

# Tienda 1.7 o posterior sin base en app/config/parameters.php: lo crea con la base cargada en local
# (la copia guardada si es de la misma base). Lo que ya tiene base no se toca.
function ps_parameters() {
    local folder=$1 db dir=$HTDOCS_DIR/$1 prefix saved try out
    local file=$dir/app/config/parameters.php
    [ -f "$dir/app/config/set_parameters.php" ] || [ -d "$dir/src/PrestaShopBundle" ] || return 0
    [ -f "$file" ] && grep -qE "['\"]database_name['\"][[:space:]]*=>[[:space:]]*['\"][^'\"]" "$file" && return 0

    # Si MariaDB se acaba de arrancar (cambio de version), se le dan unos segundos
    for try in 1 2 3 4 5 6; do
        out=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e 'SELECT 1' < /dev/null 2>&1) && break
        [[ "$out" == *"Can't connect"* ]] && [ "$DRY" -eq 0 ] || break
        sleep 1
    done
    db=$(ps_guess_db "$folder" "$2")
    if [ -z "$db" ] || ! db_exists "$db" 2> /dev/null; then
        echo "Aviso: $folder no tiene la base de datos en app/config/parameters.php y no se sabe"
        echo "cual es${db:+ ($db no esta en la version activa)}. Cargala desde el buscador de Bases de"
        echo "datos (Cargar proyecto) o pon database_name a mano en ese fichero."

        return 0
    fi
    prefix=$(ps_table_prefix "$db")
    if [ -z "$prefix" ]; then
        echo "Aviso: la base $db no tiene la tabla shop_url de PrestaShop: no se crea parameters.php"

        return 0
    fi

    if ! project_path_ok "$dir" "$file"; then
        echo "Aviso: app/config/parameters.php de $folder es un enlace o esta fuera de la carpeta: no se toca"

        return 0
    fi
    saved=$PS_PARAMS_DIR/$folder.parameters.php
    if [ -f "$saved" ] && grep -qF "'database_name' => '$db'" "$saved"; then
        echo "app/config/parameters.php no tiene la base: se pone la copia guardada ($db)"
        project_write "$saved" "$file" || return 1
    else
        echo "Creando app/config/parameters.php con la base $db (prefijo $prefix) y claves nuevas..."
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] $file con la base $db y copia en $saved"
            return 0
        fi
        [ -f "$file" ] && mkdir -p -m 700 "$HOME/lvm-copias" \
            && cp "$file" "$HOME/lvm-copias/parameters.php-$folder-$(date +%Y%m%d-%H%M%S)"
        mkdir -p -m 700 "$PS_PARAMS_DIR" || return 1
        python3 -I - "$PS_PARAMS_DIR/.nuevo" "$db" "$prefix" <<'EOF' || { echo "No se ha podido preparar $file"; return 1; }
import datetime, hashlib, os, secrets, string, sys
path, db, prefix = sys.argv[1:4]
alnum = string.ascii_letters + string.digits
def gen(n):
    return "".join(secrets.choice(alnum) for _ in range(n))
# Clave de defuse/php-encryption (new_cookie_key): cabecera, 32 bytes y su sha256, en hexadecimal
head = b"\xde\xf0\x00\x00"
key = os.urandom(32)
defuse = (head + key + hashlib.sha256(head + key).digest()).hex()
params = [
    ("database_host", "localhost"), ("database_port", ""), ("database_name", db),
    ("database_user", "root"), ("database_password", ""), ("database_prefix", prefix),
    ("database_engine", "InnoDB"), ("mailer_transport", "smtp"), ("mailer_host", "127.0.0.1"),
    ("mailer_user", None), ("mailer_password", None), ("secret", gen(64)),
    ("ps_caching", "CacheMemcache"), ("ps_cache_enable", False),
    ("ps_creation_date", datetime.date.today().isoformat()), ("locale", "es-ES"),
    ("use_debug_toolbar", True), ("cookie_key", gen(64)), ("cookie_iv", gen(32)),
    ("new_cookie_key", defuse),
]
def php(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "true" if v else "false"
    return "'%s'" % v.replace("\\", "\\\\").replace("'", "\\'")
text = "<?php return array (\n  'parameters' => \n  array (\n%s  ),\n);\n" % "".join(
    "    '%s' => %s,\n" % (k, php(v)) for k, v in params)
with open(path, "w") as f:
    f.write(text)
EOF
        project_write "$PS_PARAMS_DIR/.nuevo" "$file" || { rm -f "$PS_PARAMS_DIR/.nuevo"; echo "No se ha podido escribir $file"; return 1; }
        mv "$PS_PARAMS_DIR/.nuevo" "$saved"
    fi
    # La cache guarda la configuracion anterior (var/cache/*/appParameters.php): se vacia al cargar
    PS_NEW_PARAMS=1
    return 0
}

# Vacia una carpeta (var/cache de una tienda) como root sin seguir enlaces en ningun momento: la ruta
# se recorre desde / con O_NOFOLLOW y tiene que estar dentro de htdocs; dentro, los enlaces se
# borran (no se sigue a donde apuntan). CACHE_CLEAR_PY <carpeta> <htdocs>
CACHE_CLEAR_PY='
import os, stat, sys
target, top = sys.argv[1], os.path.realpath(sys.argv[2])
real = os.path.realpath(target)
if not real.startswith(top + "/") or not real.endswith("/var/cache"):
    sys.exit("%s no esta dentro de %s: no se vacia" % (target, top))
fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
for p in [p for p in real.split("/") if p]:
    nfd = os.open(p, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
    os.close(fd)
    fd = nfd
dev = os.fstat(fd).st_dev
def empty(dfd):
    for e in os.scandir(dfd):
        st = os.stat(e.name, dir_fd=dfd, follow_symlinks=False)
        if stat.S_ISDIR(st.st_mode) and st.st_dev == dev:
            sub = os.open(e.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=dfd)
            try:
                empty(sub)
            finally:
                os.close(sub)
            os.rmdir(e.name, dir_fd=dfd)
        elif not stat.S_ISDIR(st.st_mode):
            os.unlink(e.name, dir_fd=dfd)
empty(fd)
'

# vaciar-cache <carpeta>: borra el contenido de var/cache de una tienda (PrestaShop 1.7 la usa para
# Symfony y da error 500 con la de otro equipo). Si no tiene var/cache no hace nada.
function ps_clear_cache() {
    local folder=${1%/} cache s=""
    valid_project "$folder" || return 1
    cache=$HTDOCS_DIR/$folder/var/cache
    if [ ! -d "$cache" ]; then
        echo "$folder no tiene la carpeta var/cache: no hay cache que vaciar"

        return 0
    fi
    # var y var/cache tienen que estar dentro de la tienda: si fueran enlaces a otra carpeta (por
    # ejemplo a /var), con sudo se vaciaria la del sistema
    if [ -L "$HTDOCS_DIR/$folder/var" ] || [ -L "$cache" ] \
        || [ "$(readlink -f "$cache")" != "$(readlink -f "$HTDOCS_DIR/$folder")/var/cache" ]; then
        echo "var/cache de $folder es un enlace a otra carpeta: no se vacia"

        return 1
    fi
    # Los ficheros que creo Apache como daemon (antes de User/Group) solo se borran con sudo
    find "$cache" -mindepth 1 ! -user "$(id -un)" -print -quit 2> /dev/null | grep -q . && s=sudo
    echo "Vaciando la cache de $folder (var/cache)..."
    # Con sudo, root abre var/cache carpeta a carpeta sin seguir enlaces y borra desde ahi: si entre
    # la comprobacion y el borrado cambian var por un enlace (a /var), falla en lugar de vaciar otra
    if [ -n "$s" ]; then
        run $s python3 -I -c "$CACHE_CLEAR_PY" "$cache" "$HTDOCS_DIR"
    else
        run find "$cache" -mindepth 1 -delete
    fi || { echo "No se ha podido vaciar $cache"; return 1; }
    echo "Cache de $folder vaciada"
}

# Para el boton de la pestaña Bases de datos: la carpeta de la tienda de una base (la recordada, o
# la unica cuya configuracion la usa, o la unica cuyo nombre acaba como la base sin ps_)
function ps_clear_cache_db() {
    local db=$1 folder="" tail
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Base de datos no valida: $db"; return 1; }
    [ -f "$PROJECTS_FILE" ] && folder=$(awk -F= -v d="$db" '$1 == d { f = $2 } END { print f }' "$PROJECTS_FILE")
    if [ -z "$folder" ] || [ ! -d "$HTDOCS_DIR/$folder" ]; then
        folder=$(gui_projects | awk -F'|' -v d="$db" '$1 == "P" && $3 == d { print $2 }')
        if [ "$(grep -c . <<< "$folder")" != 1 ]; then
            tail=$(tr 'A-Z' 'a-z' <<< "${db#ps_}")
            folder=$(gui_projects | awk -F'|' -v t="$tail" '$1 == "P" { n = tolower($2); if (n == t || substr(n, length(n) - length(t)) ~ ("[-.]" t "$")) print $2 }')
        fi
    fi
    if [ -z "$folder" ] || [ "$(grep -c . <<< "$folder")" != 1 ]; then
        echo "No se sabe cual es la carpeta de la tienda de $db. Cargala una vez con Cargar proyecto"
        echo "(se recuerda) o usa: lvm-instalador vaciar-cache <carpeta>"

        return 1
    fi
    ps_clear_cache "$folder"
}

# Primera carga de una tienda en este equipo (o parameters.php nuevo): vacia su cache y la apunta
function ps_first_load() {
    local folder=$1
    if [ "$PS_NEW_PARAMS" != 1 ] && [ -f "$PS_LOADED_FILE" ] && grep -qxF "$folder" "$PS_LOADED_FILE"; then
        return 0
    fi
    grep -qxF "$folder" "$PS_LOADED_FILE" 2> /dev/null || echo "Primera carga de la tienda $folder en este equipo"
    ps_clear_cache "$folder" || return 0
    [ "$DRY" -eq 1 ] && return 0
    grep -qxF "$folder" "$PS_LOADED_FILE" 2> /dev/null && return 0
    mkdir -p "$(dirname "$PS_LOADED_FILE")" && echo "$folder" >> "$PS_LOADED_FILE"
}

# ===========================================================================
# WordPress: wp-config.php con la base cargada en local
# ===========================================================================
# Al pegar el codigo de produccion encima del proyecto local, su wp-config.php trae la base, el
# usuario, la contraseña y el servidor de produccion. Al cargar el proyecto (y al subir una base
# nueva para el) se comprueba que use la base asociada a la carpeta y que sus datos entren en el
# MariaDB local. Si no, se rehace con la plantilla: la copia del ultimo wp-config.php que funciono
# en este equipo (WP_CONFIG_DIR/<carpeta>.wp-config.php) o, si no la hay, el propio fichero (o
# wp-config-sample.php) con root y localhost. De la plantilla solo cambian la base y el prefijo.
WP_CONFIG_DIR="$HOME/.lvm-instalador/wordpress"

function is_wordpress() {
    [ -f "$HTDOCS_DIR/$1/wp-config.php" ] || [ -d "$HTDOCS_DIR/$1/wp-includes" ]
}

# Base recordada para una carpeta (la ultima de ~/.lvm-instalador/proyectos)
function saved_project_db() {
    [ -f "$PROJECTS_FILE" ] || return 0
    awk -F= -v f="$1" '$2 == f { d = $1 } END { if (d != "") print d }' "$PROJECTS_FILE"
}

# Recuerda la carpeta de una base. Con --unica, la carpeta deja de estar asociada a otras bases
# (la base nueva sustituye a la anterior)
function remember_project() {
    local db=$1 folder=$2
    [ "$DRY" -eq 1 ] && return 0
    mkdir -p "$(dirname "$PROJECTS_FILE")"
    { [ -f "$PROJECTS_FILE" ] && awk -F= -v d="$db" -v f="$folder" -v u="$3" \
        '$1 != d && !(u == "--unica" && $2 == f)' "$PROJECTS_FILE"; echo "$db=$folder"; } > "$PROJECTS_FILE.nuevo"
    mv "$PROJECTS_FILE.nuevo" "$PROJECTS_FILE"
}

# Datos de un wp-config.php, uno por linea: base, usuario, servidor, prefijo y contraseña
function wp_config_read() {
    python3 -I - "$1" <<'EOF'
import os, re, sys
try:
    if not os.path.isfile(sys.argv[1]) or os.path.getsize(sys.argv[1]) > 2000000:
        raise OSError("no es un fichero normal")
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        text = f.read()
except OSError:
    sys.exit(1)
def const(name):
    # Solo las que no estan comentadas (// define( 'DB_USER', 'development' );)
    m = re.search(r"""(?m)^[ \t]*define\(\s*['"]%s['"]\s*,\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")""" % name, text)
    if not m:
        return ""
    return re.sub(r"\\(.)", r"\1", m.group(1) if m.group(1) is not None else m.group(2))
m = re.search(r"""(?m)^[ \t]*\$table_prefix\s*=\s*['"]([^'"]*)['"]""", text)
# Sin caracteres de control (salen en la terminal: un ESC cambiaria lo que se ve), salvo en la
# contraseña, que no se muestra
for i, v in enumerate((const("DB_NAME"), const("DB_USER"), const("DB_HOST"), m.group(1) if m else "", const("DB_PASSWORD"))):
    print(v.replace("\n", " ") if i == 4 else re.sub(r"[\x00-\x1f\x7f-\x9f]", "?", v))
EOF
}

# ===========================================================================
# Administrador de pruebas de los paneles (WordPress y PrestaShop)
# ===========================================================================
# Al cargar una BBDD (y al pulsar el boton del panel en Cargar proyecto) se le añade un administrador
# de pruebas, el mismo en todos los equipos: el boton abre la pantalla de acceso con el usuario y la
# contraseña ya escritos. Solo en las BBDD de este equipo (que nunca van a produccion)
TEST_ADMIN_USER="local@local.test"
TEST_ADMIN_PASS="local"
# (huella bcrypt de «local», para PrestaShop 1.7 o posterior; la 1.6 usa md5 de su _COOKIE_KEY_ y
# la contraseña, y WordPress acepta md5 y la cambia por la suya al entrar)
TEST_ADMIN_BCRYPT='$2y$12$IqVkFsJq4UhjbzLfagfW9eU5V6iIauQCbfMJDY26MoM8ETz6ZKgxG'

# usuario-pruebas <base> [carpeta]: crea o deja al dia el administrador de pruebas en los WordPress y
# la tienda PrestaShop de la base. Dice A|wp|usuario|contraseña y/o A|ps|... por cada uno (para la
# ventana); sale con 1 si no hay ninguno. La carpeta (o la recordada para la base) solo hace falta en
# PrestaShop 1.6, por su _COOKIE_KEY_
function test_admin() {
    local db=$1 folder=$2 p sql cols col exprs hash src key done_any=1
    if ! [[ "$db" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$ ]]; then
        echo "Base no valida: $db"
        return 1
    fi
    [ -z "$folder" ] && folder=$(awk -F= -v d="$db" '$1 == d { split($2, a, " "); f = a[1] } END { print f }' "$PROJECTS_FILE" 2> /dev/null)
    [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9\ ._-]*$ ]] && [ -d "$HTDOCS_DIR/$folder" ] || folder=""
    local mysql=("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N --default-character-set=utf8mb4)
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] administrador de pruebas $TEST_ADMIN_USER / $TEST_ADMIN_PASS en $db"
        return 0
    fi
    # (solo tablas de verdad: una vista del volcado ejecutaria sus funciones como root)
    function has_table() {
        [ "$("${mysql[@]}" -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$db' AND TABLE_NAME='$1' AND TABLE_TYPE='BASE TABLE'" < /dev/null 2> /dev/null)" == 1 ]
    }

    # WordPress (todos los de la base): usuario con rol de administrador
    for p in $(wp_table_prefixes "$db"); do
        has_table "${p}usermeta" || continue
        sql=$(sed "s/@P@/$p/g" <<'SQL'
SET @id := (SELECT ID FROM `@P@users` WHERE user_login = 'local@local.test' ORDER BY ID LIMIT 1);
INSERT INTO `@P@users` (user_login, user_pass, user_nicename, user_email, user_url, user_registered, user_activation_key, user_status, display_name)
    SELECT 'local@local.test', MD5('local'), 'local-pruebas', 'local@local.test', '', NOW(), '', 0, 'Local (pruebas)' FROM DUAL WHERE @id IS NULL;
SET @id := IFNULL(@id, LAST_INSERT_ID());
UPDATE `@P@users` SET user_pass = MD5('local'), user_activation_key = '' WHERE ID = @id;
DELETE FROM `@P@usermeta` WHERE user_id = @id AND meta_key IN ('@P@capabilities', '@P@user_level');
INSERT INTO `@P@usermeta` (user_id, meta_key, meta_value) SELECT @id, '@P@capabilities', 'a:1:{s:13:"administrator";b:1;}' FROM DUAL WHERE @id > 0;
INSERT INTO `@P@usermeta` (user_id, meta_key, meta_value) SELECT @id, '@P@user_level', '10' FROM DUAL WHERE @id > 0;
SELECT CAST(IFNULL(@id, 0) AS UNSIGNED);
SQL
)
        if [ "$("${mysql[@]}" "$db" -e "$sql" < /dev/null 2> /dev/null | tail -1)" -gt 0 ] 2> /dev/null; then
            echo "A|wp|$TEST_ADMIN_USER|$TEST_ADMIN_PASS"
            done_any=0
        fi
    done

    # PrestaShop: una copia del primer SuperAdmin (mismas columnas, sea cual sea la version) con el
    # correo y la contraseña de pruebas, en todas las tiendas
    p=$(ps_table_prefix "$db")
    # (ps_table_prefix no da nada si la tienda no lleva prefijo)
    if has_table "${p}employee" && has_table "${p}employee_shop" && has_table "${p}shop" && has_table "${p}shop_url"; then
        src=$("${mysql[@]}" "$db" -e "SELECT passwd FROM \`${p}employee\` WHERE id_profile = 1 ORDER BY active DESC, id_employee LIMIT 1" < /dev/null 2> /dev/null)
        if [[ "$src" == '$'* ]]; then
            hash=$TEST_ADMIN_BCRYPT
        elif [ -n "$src" ]; then
            # PrestaShop 1.6: md5(_COOKIE_KEY_ + contraseña), con la clave de su settings.inc.php
            key=""
            [ -n "$folder" ] && key=$(python3 -I - "$HTDOCS_DIR/$folder/config/settings.inc.php" <<'EOF'
import re, sys
try:
    text = open(sys.argv[1], errors="replace").read(1000000)
except OSError:
    sys.exit(0)
m = re.search(r"""define\(\s*['"]_COOKIE_KEY_['"]\s*,\s*['"]([A-Za-z0-9]+)['"]""", text)
print(m.group(1) if m else "")
EOF
)
            [ -n "$key" ] && hash=$(python3 -I -c 'import hashlib, sys; print(hashlib.md5(sys.argv[1].encode()).hexdigest())' "$key$TEST_ADMIN_PASS")
        fi
        cols=$("${mysql[@]}" -e "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$db' AND TABLE_NAME='${p}employee' ORDER BY ORDINAL_POSITION" < /dev/null 2> /dev/null)
        if [ -z "$hash" ]; then
            [ -n "$src" ] && echo "Aviso: no se sabe la _COOKIE_KEY_ de la tienda (PrestaShop 1.6): sin administrador de pruebas. Cargala con su carpeta (Cargar proyecto)."
        elif [ -n "$cols" ] && ! grep -qvE '^[A-Za-z0-9_]+$' <<< "$cols"; then
            local list="" sel=""
            for col in $cols; do
                case $col in
                    id_employee) continue ;;
                    email) exprs="'local@local.test'" ;;
                    passwd) exprs="'$hash'" ;;
                    firstname) exprs="'Pruebas'" ;;
                    lastname) exprs="'Local'" ;;
                    active|id_profile) exprs=1 ;;
                    last_passwd_gen) exprs="NOW()" ;;
                    reset_password_token|reset_password_validity) exprs=NULL ;;
                    *) exprs="\`$col\`" ;;
                esac
                list+="${list:+, }\`$col\`" sel+="${sel:+, }$exprs"
            done
            sql="SET @src := (SELECT id_employee FROM \`${p}employee\` WHERE id_profile = 1 ORDER BY active DESC, id_employee LIMIT 1);
SET @id := (SELECT id_employee FROM \`${p}employee\` WHERE email = 'local@local.test' ORDER BY id_employee LIMIT 1);
INSERT INTO \`${p}employee\` ($list) SELECT $sel FROM \`${p}employee\` WHERE id_employee = @src AND @id IS NULL;
SET @id := IFNULL(@id, LAST_INSERT_ID());
UPDATE \`${p}employee\` SET passwd = '$hash', active = 1, id_profile = 1 WHERE id_employee = @id AND @src IS NOT NULL;
INSERT IGNORE INTO \`${p}employee_shop\` (id_employee, id_shop) SELECT @id, id_shop FROM \`${p}shop\` WHERE @id > 0 AND @src IS NOT NULL;
SELECT CAST(IF(@src IS NULL, 0, @id) AS UNSIGNED);"
            if [ "$("${mysql[@]}" "$db" -e "$sql" < /dev/null 2> /dev/null | tail -1)" -gt 0 ] 2> /dev/null; then
                echo "A|ps|$TEST_ADMIN_USER|$TEST_ADMIN_PASS"
                done_any=0
            fi
        fi
    fi
    unset -f has_table
    return $done_any
}

# Prefijos de los WordPress de una base: los de sus tablas <prefijo>options con <prefijo>users
function wp_table_prefixes() {
    [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
    # Solo prefijos de letras, numeros y _ (los nombres de las tablas los trae la base)
    "${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT LEFT(TABLE_NAME, LENGTH(TABLE_NAME) - 7) AS p FROM information_schema.TABLES
        WHERE TABLE_SCHEMA='$1' AND TABLE_TYPE='BASE TABLE' AND TABLE_NAME LIKE '%options' AND CONCAT(LEFT(TABLE_NAME, LENGTH(TABLE_NAME) - 7), 'users')
        IN (SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='$1' AND TABLE_TYPE='BASE TABLE') ORDER BY LENGTH(p)" < /dev/null 2> /dev/null \
        | grep -E '^[A-Za-z0-9_]*$'
}

# ¿Entra la web en la base con estos datos? usuario contraseña servidor base tabla. Solo se prueba
# si el servidor es este equipo (nunca se conecta a uno de produccion). La base y la tabla van en
# la consulta: solo nombres validos (el prefijo de la tabla puede venir del wp-config.php)
function db_login_ok() {
    local user=$1 pass=$2 host=$3 db=$4 table=$5
    [ -n "$user" ] && [[ "$host" =~ ^(localhost|127\.0\.0\.1)(:.*)?$ ]] || return 1
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] && [[ "$table" =~ ^[A-Za-z0-9_]+$ ]] || return 1
    # Sin leer la tabla: podria ser una vista del volcado que ejecuta funciones con los permisos de
    # este usuario (root muchas veces). Basta con que la vea como tabla de verdad
    db_base_table "$user" "$pass" "$db" "$table"
}

# URL con la que se ve un proyecto en este equipo: su dominio propio (pestaña Hosts) o el vhost de
# los proyectos (el ServerName que tenga: web.local, localhost...), con https si tiene certificado
function wp_local_url() {
    local domain link
    domain=$(custom_domain "$1")
    if [ -n "$domain" ]; then
        echo "https://$domain"

        return 0
    fi
    link=$(project_link)
    vhosts_info | awk -F'|' -v l="${link:-$PROJECT_VHOST}" '
        $2 == l && $5 != "" && https == "" { https = "https://" $3 ($1 == 443 ? "" : ":" $1) }
        $2 == l && $5 == "" && http == "" { http = "http://" $3 ($1 == 80 ? "" : ":" $1) }
        END { print (https != "" ? https : http != "" ? http : "https://" l) }'
}

# wp-config <carpeta> [base]: comprueba el wp-config.php de un WordPress y, si no usa la base
# asociada (la indicada, la recordada para la carpeta o la suya si esta en local) o no entra en el
# MariaDB local, lo rehace con la plantilla
function wp_config() {
    local folder=${1%/} db=$2 dir file sample saved src name user host prefix pass new_prefix prefixes
    local s_name s_user s_host s_prefix s_pass local_db=0 try out url
    valid_project "$folder" || return 1
    dir=$HTDOCS_DIR/$folder file=$HTDOCS_DIR/$folder/wp-config.php sample=$HTDOCS_DIR/$folder/wp-config-sample.php
    if ! project_path_ok "$dir" "$file" || { [ -e "$sample" ] && ! project_path_ok "$dir" "$sample"; }; then
        echo "Aviso: wp-config.php de $folder es un enlace o esta fuera de la carpeta: no se toca"

        return 0
    fi
    saved=$WP_CONFIG_DIR/$folder.wp-config.php
    { IFS= read -r name; IFS= read -r user; IFS= read -r host; IFS= read -r prefix; IFS= read -r pass; } \
        < <(wp_config_read "$file")

    # Si MariaDB se acaba de arrancar (cambio de version), se le dan unos segundos
    for try in 1 2 3 4 5 6; do
        out=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e 'SELECT 1' < /dev/null 2>&1) && break
        [[ "$out" == *"Can't connect"* ]] && [ "$DRY" -eq 0 ] || break
        sleep 1
    done
    [ -z "$db" ] && db=$(saved_project_db "$folder")
    if [ -z "$db" ]; then
        # El nombre lo trae el wp-config.php: solo si es un nombre de base valido
        [[ "$name" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]] && db_exists "$name" 2> /dev/null && db=$name
    fi
    if [ -z "$db" ]; then
        echo "Aviso: el wp-config.php de $folder usa la base ${name:-(ninguna)}, que no esta en la"
        echo "version activa, y la carpeta no tiene una base asociada. Cargala desde el buscador de"
        echo "Bases de datos (Cargar proyecto) o al subirla elige el proyecto, y se corrige sola."

        return 0
    fi
    if ! [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] || ! db_exists "$db" 2> /dev/null; then
        echo "Aviso: la base $db de $folder no esta en la version activa: no se toca su wp-config.php"

        return 0
    fi
    prefixes=$(wp_table_prefixes "$db")
    if [ -z "$prefixes" ]; then
        echo "Aviso: la base $db no tiene las tablas de WordPress: no se toca el wp-config.php de $folder"

        return 0
    fi

    # Funciona en este equipo con la base asociada: es la plantilla para la proxima vez
    if [ "$name" == "$db" ] && grep -qxF -- "$prefix" <<< "$prefixes" && db_login_ok "$user" "$pass" "$host" "$db" "${prefix}options"; then
        if [ "$DRY" -eq 0 ] && ! cmp -s "$file" "$saved"; then
            mkdir -p "$WP_CONFIG_DIR" && cp "$file" "$saved"
        fi
        echo "WordPress: wp-config.php usa la base $db"

        return 0
    fi

    # Plantilla: la copia de este equipo, el propio fichero o wp-config-sample.php
    if [ -f "$saved" ]; then
        src=$saved
    elif [ -f "$file" ]; then
        src=$file
    elif [ -f "$sample" ]; then
        src=$sample
    else
        echo "Aviso: $folder no tiene wp-config.php ni wp-config-sample.php: no se puede crear"

        return 0
    fi
    { IFS= read -r s_name; IFS= read -r s_user; IFS= read -r s_host; IFS= read -r s_prefix; IFS= read -r s_pass; } \
        < <(wp_config_read "$src")
    # Prefijo: siempre uno que traen las tablas de la base (nunca se cambian las tablas). Con varios
    # WordPress en la base, el del wp-config.php del proyecto o el de la plantilla si la base lo
    # tiene; si no se sabe cual es, no se toca (un prefijo sin tablas abriria la instalacion)
    if grep -qxF -- "$prefix" <<< "$prefixes" && [ -f "$file" ]; then
        new_prefix=$prefix
    elif grep -qxF -- "$s_prefix" <<< "$prefixes"; then
        new_prefix=$s_prefix
    elif [ "$(wc -l <<< "$prefixes")" == 1 ]; then
        new_prefix=$prefixes
    else
        echo "Aviso: $db tiene tablas de varios WordPress (prefijos $(tr '\n' ' ' <<< "$prefixes"| sed 's/ $//'))"
        echo "y el wp-config.php de $folder no usa ninguno: no se toca. Pon en \$table_prefix el"
        echo "de su web y vuelve a cargar el proyecto."

        return 0
    fi
    # Usuario, contraseña y servidor de la plantilla si entran en local; si no, root y localhost
    db_login_ok "$s_user" "$s_pass" "$s_host" "$db" "${new_prefix}options" || local_db=1

    if [ "$name" != "$db" ]; then
        echo "WordPress: el wp-config.php de $folder usa la base ${name:-(ninguna)}${host:+ en $host}; la de la carpeta es $db"
    else
        echo "WordPress: el wp-config.php de $folder no entra en el MariaDB local${host:+ (servidor $host, usuario $user)}"
    fi
    case "$src" in
        "$saved") echo "Se rehace con la plantilla de este equipo, con la base $db" ;;
        "$sample") echo "Se crea a partir de wp-config-sample.php, con la base $db y claves nuevas" ;;
        *) echo "Se cambia a la base $db" ;;
    esac
    [ $local_db -eq 1 ] && echo "  Usuario root y servidor localhost (los de MariaDB local)"
    [ "$new_prefix" != "$s_prefix" ] && echo "  Prefijo de las tablas: $new_prefix (era ${s_prefix:-ninguno})"
    url=$(wp_local_url "$folder")
    echo "  WP_SITEURL y WP_HOME: $url"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $file con la base $db y copia en $saved"

        return 0
    fi

    mkdir -p -m 700 "$WP_CONFIG_DIR" || return 1
    if [ -f "$file" ] && ! cmp -s "$file" "$saved"; then
        mkdir -p -m 700 "$HOME/lvm-copias" && cp "$file" "$HOME/lvm-copias/wp-config.php-$folder-$(date +%Y%m%d-%H%M%S)" \
            && echo "  El anterior queda en ~/lvm-copias"
    fi
    LVM_WP_CLAVE=${MYSQL_PWD:-} python3 -I - "$src" "$WP_CONFIG_DIR/.nuevo" "$db" "$new_prefix" "$local_db" "$url" <<'EOF' || { echo "No se ha podido preparar el wp-config.php"; return 1; }
import os, re, secrets, string, sys
src, dst, db, prefix, local_db, url = sys.argv[1:7]
# newline="": se conservan los finales de linea (CRLF en muchos wp-config.php)
with open(src, encoding="utf-8", errors="surrogateescape", newline="") as f:
    text = f.read()
def php(v):
    return "'%s'" % v.replace("\\", "\\\\").replace("'", "\\'")
def put(text, name, value):
    rx = re.compile(r"""(?m)^([ \t]*define\(\s*['"]%s['"]\s*,\s*)(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""" % name)
    return rx.sub(lambda m: m.group(1) + php(value), text, count=1)
text = put(text, "DB_NAME", db)
if local_db == "1":
    text = put(text, "DB_USER", "root")
    text = put(text, "DB_PASSWORD", os.environ.get("LVM_WP_CLAVE", ""))
    text = put(text, "DB_HOST", "localhost")
text = re.sub(r"""(?m)^([ \t]*\$table_prefix\s*=\s*)(['"])[^'"]*\2""", lambda m: m.group(1) + php(prefix), text, count=1)
# La web en este equipo (si no, WordPress redirige al dominio de produccion guardado en la base)
nl = "\r\n" if "\r\n" in text else "\n"
missing = []
for name in ("WP_SITEURL", "WP_HOME"):
    rx = re.compile(r"""(?m)^([ \t]*define\(\s*['"]%s['"]\s*,\s*)(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")""" % name)
    if rx.search(text):
        text = rx.sub(lambda m: m.group(1) + php(url), text, count=1)
    else:
        missing.append(name)
if missing:
    lines = "".join("define('%s', %s);%s" % (name, php(url), nl) for name in missing) + nl
    # Delante de los datos de la base, como en la plantilla del equipo; si no, detras de <?php
    m = re.search(r"""(?m)^[ \t]*(?://[^\r\n]*Database settings|define\(\s*['"]DB_NAME['"])""", text)
    if m:
        text = text[:m.start()] + lines + text[m.start():]
    else:
        m = re.search(r"<\?php[^\n]*\n", text)
        at = m.end() if m else 0
        text = text[:at] + nl + lines + text[at:]
# Sin editor de plugins y temas en el escritorio de WordPress: todos los proyectos van en el mismo
# origen (localhost), y un fallo XSS en uno podria usar ese editor en otro para ejecutar PHP
if not re.search(r"""(?m)^[ \t]*define\(\s*['"]DISALLOW_FILE_EDIT['"]""", text):
    line = "define('DISALLOW_FILE_EDIT', true); // lvm-instalador: sin editor de plugins en local" + nl
    m = re.search(r"""(?m)^[ \t]*(?:/\*[^\n]*stop editing|\$table_prefix\b)""", text)
    if m:
        text = text[:m.start()] + line + nl + text[m.start():]
    else:
        m = re.search(r"<\?php[^\n]*\n", text)
        at = m.end() if m else 0
        text = text[:at] + line + text[at:]
# wp-config-sample.php: claves nuevas
chars = string.ascii_letters + string.digits + "!#$%&()*+,-./:;<=>?@[]^_{|}~"
for key in ("AUTH_KEY", "SECURE_AUTH_KEY", "LOGGED_IN_KEY", "NONCE_KEY",
            "AUTH_SALT", "SECURE_AUTH_SALT", "LOGGED_IN_SALT", "NONCE_SALT"):
    rx = re.compile(r"""(?m)^([ \t]*define\(\s*['"]%s['"]\s*,\s*)['"]put your unique phrase here['"]""" % key)
    text = rx.sub(lambda m: m.group(1) + php("".join(secrets.choice(chars) for _ in range(64))), text, count=1)
with open(dst, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
    f.write(text)
EOF
    project_write "$WP_CONFIG_DIR/.nuevo" "$file" || { rm -f "$WP_CONFIG_DIR/.nuevo"; echo "No se ha podido escribir $file"; return 1; }
    mv "$WP_CONFIG_DIR/.nuevo" "$saved"
    echo "wp-config.php de $folder listo: base $db (plantilla guardada en $saved)"
}

# Datos de la base en la configuracion de una tienda (app/config/parameters.php o, en 1.6,
# config/settings.inc.php), uno por linea: fichero, base, usuario, servidor, prefijo y contraseña.
# Nada si no tiene configuracion con base (la crea ps_parameters).
function ps_db_read() {
    python3 -I - "$HTDOCS_DIR/$1" <<'EOF'
import os, re, sys
root = sys.argv[1]
quoted = r"""(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")"""
rules = [
    ("app/config/parameters.php", r"""['"]%s['"]\s*=>\s*""" + quoted,
     ("database_name", "database_user", "database_host", "database_prefix", "database_password")),
    ("config/settings.inc.php", r"""(?m)^[ \t]*define\(\s*['"]%s['"]\s*,\s*""" + quoted,
     ("_DB_NAME_", "_DB_USER_", "_DB_SERVER_", "_DB_PREFIX_", "_DB_PASSWD_")),
]
for rel, rx, keys in rules:
    try:
        if not os.path.isfile(os.path.join(root, rel)) or os.path.getsize(os.path.join(root, rel)) > 2000000:
            raise OSError("no es un fichero normal")
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        continue
    values = []
    for i, key in enumerate(keys):
        m = re.search(rx % key, text)
        v = (m.group(1) if m.group(1) is not None else m.group(2)) if m else ""
        v = re.sub(r"\\(.)", r"\1", v)
        # Sin caracteres de control (salen en la terminal), salvo en la contraseña
        values.append(v.replace("\n", " ") if i == 4 else re.sub(r"[\x00-\x1f\x7f-\x9f]", "?", v))
    if values[0]:
        print(rel)
        for v in values:
            print(v)
        break
EOF
}

# Tienda cuya configuracion no usa la base asociada a la carpeta (base nueva subida para ella o
# codigo de produccion pegado encima): cambia la base y el prefijo de las tablas y, si sus datos no
# entran en el MariaDB local, pone root y localhost. Deja PS_NEW_PARAMS=1 para vaciar la cache.
function ps_set_db() {
    local folder=$1 db=$2 rel name user host prefix pass new_prefix local_db=0 file
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
    { IFS= read -r rel; IFS= read -r name; IFS= read -r user; IFS= read -r host; IFS= read -r prefix; IFS= read -r pass; } \
        < <(ps_db_read "$folder")
    [ -n "$rel" ] || return 0
    file=$HTDOCS_DIR/$folder/$rel
    if ! project_path_ok "$HTDOCS_DIR/$folder" "$file"; then
        echo "Aviso: $rel de $folder es un enlace o esta fuera de la carpeta: no se toca"

        return 0
    fi
    if ! db_exists "$db" 2> /dev/null; then
        echo "Aviso: la base $db de $folder no esta en la version activa: no se toca $rel"

        return 0
    fi
    new_prefix=$(ps_table_prefix "$db" "$prefix")
    if [ -z "$new_prefix" ]; then
        echo "Aviso: la base $db no tiene la tabla shop_url de PrestaShop: no se toca $rel"

        return 0
    fi
    if [ "$name" == "$db" ] && [ "$prefix" == "$new_prefix" ] \
        && db_login_ok "$user" "$pass" "$host" "$db" "${new_prefix}shop_url"; then
        return 0
    fi
    db_login_ok "$user" "$pass" "$host" "$db" "${new_prefix}shop_url" || local_db=1

    if [ "$name" != "$db" ]; then
        echo "PrestaShop: $rel de $folder usa la base $name${host:+ en $host}; la de la carpeta es $db"
    else
        echo "PrestaShop: $rel de $folder no entra en el MariaDB local${host:+ (servidor $host, usuario $user)}"
    fi
    echo "Se cambia a la base $db"
    [ $local_db -eq 1 ] && echo "  Usuario root y servidor localhost (los de MariaDB local)"
    [ "$new_prefix" != "$prefix" ] && echo "  Prefijo de las tablas: $new_prefix (era ${prefix:-ninguno})"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] $file con la base $db"

        return 0
    fi

    mkdir -p -m 700 "$PS_PARAMS_DIR" "$HOME/lvm-copias" || return 1
    cp "$file" "$HOME/lvm-copias/$(basename "$rel")-$folder-$(date +%Y%m%d-%H%M%S)" && echo "  El anterior queda en ~/lvm-copias"
    LVM_PS_CLAVE=${MYSQL_PWD:-} python3 -I - "$file" "$PS_PARAMS_DIR/.nuevo" "$db" "$new_prefix" "$local_db" <<'EOF' || { echo "No se ha podido preparar $rel"; return 1; }
import os, re, sys
src, dst, db, prefix, local_db = sys.argv[1:6]
# newline="": se conservan los finales de linea
with open(src, encoding="utf-8", errors="surrogateescape", newline="") as f:
    text = f.read()
def php(v):
    return "'%s'" % v.replace("\\", "\\\\").replace("'", "\\'")
value = r"""(?:'(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|NULL|null)"""
if src.endswith("parameters.php"):
    rx = r"""(['"]%s['"]\s*=>\s*)""" + value
    keys = dict(name="database_name", prefix="database_prefix", user="database_user",
                password="database_password", host="database_host", port="database_port")
else:
    rx = r"""(?m)^([ \t]*define\(\s*['"]%s['"]\s*,\s*)""" + value
    keys = dict(name="_DB_NAME_", prefix="_DB_PREFIX_", user="_DB_USER_", password="_DB_PASSWD_",
                host="_DB_SERVER_")
def put(text, key, v):
    return re.sub(rx % keys[key], lambda m: m.group(1) + php(v), text, count=1)
text = put(text, "name", db)
text = put(text, "prefix", prefix)
if local_db == "1":
    text = put(text, "user", "root")
    text = put(text, "password", os.environ.get("LVM_PS_CLAVE", ""))
    text = put(text, "host", "localhost")
    if "port" in keys:
        text = put(text, "port", "")
with open(dst, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
    f.write(text)
EOF
    project_write "$PS_PARAMS_DIR/.nuevo" "$file" || { rm -f "$PS_PARAMS_DIR/.nuevo"; echo "No se ha podido escribir $file"; return 1; }
    # La copia que se repone si se pierde parameters.php pasa a ser esta
    if [[ "$rel" == */parameters.php ]]; then
        mv "$PS_PARAMS_DIR/.nuevo" "$PS_PARAMS_DIR/$folder.parameters.php"
    else
        rm -f "$PS_PARAMS_DIR/.nuevo"
    fi
    echo "$rel de $folder listo: base $db"
    PS_NEW_PARAMS=1
}

# Bases de datos de una version, en columnas. Si usa las de otra version, se indica de cual.
function databases_text() {
    local version=$1 width=${2:-72}
    local dir=/opt/lampp-$version
    local owner=$(data_owner "$dir")
    owner=${owner:-$version}

    local names=$(db_names "/opt/lampp-$owner")
    local count=$(grep -c . <<< "$names")
    local users=$(data_users "$owner")

    local text="lampp-$version: "
    if [ "$owner" != "$version" ]; then
        text+="usa las bases de datos de lampp-$owner"
    else
        text+="bases de datos propias"
    fi
    text+="\n"
    [ -n "$users" ] && text+="Las comparten: lampp-$owner $(printf 'lampp-%s ' $users)\n"
    text+="\nBases de datos: $count (sin contar las del sistema)\n\n"
    text+="$(columns "$width" <<< "$names")\n"

    echo "$text"
}

function list_databases() {
    local dir

    for dir in $(lampp_dirs); do
        echo -e "$(databases_text "${dir#/opt/lampp-}" "$(tput cols 2> /dev/null || echo 80)")"
        echo ""
    done
}

function disable_lampp() {
    if [ -d "/opt/lampp" ] && [ ! -L "/opt/lampp" ]; then
        echo "La carpeta /opt/lampp es una instalacion completa y no un enlace. No se puede ejecutar esta accion."

        return 1
    fi

    if [ -L "/opt/lampp" ]; then
        run sudo /opt/lampp/lampp stop
        run sudo unlink /opt/lampp
    fi
    # Sin version montada no queda ningun proceso de LAMPP en memoria
    close_processes --todos
}

# Motivo por el que no se puede desinstalar una version (vacio si se puede)
function remove_blocker() {
    local version=$1
    local dir=/opt/lampp-$version

    if [ -z "$version" ] || [[ "$version" == */* ]] || [ ! -d "$dir" ] || [ -L "$dir" ]; then
        echo "No existe la version $version de lampp en el sistema."
    elif [ "$(active_dir)" == "$dir" ]; then
        echo "lampp-$version es la version activa. Cambia antes a otra version (o desactivala) y vuelve a intentarlo."
    elif [ -n "$(data_users "$version")" ]; then
        echo "lampp-$version no se puede desinstalar porque estas versiones usan sus bases de datos: $(printf 'lampp-%s ' $(data_users "$version"))\nDesinstala antes esas versiones."
    elif [ -e "$dir/htdocs" ] && [ ! -L "$dir/htdocs" ]; then
        # htdocs deberia ser un enlace a /opt/htdocs; si es una carpeta real puede tener proyectos
        echo "lampp-$version tiene una carpeta htdocs propia (no es un enlace a /opt/htdocs) y podria contener proyectos.\nRevisala y muevela a mano antes de desinstalar."
    fi
}

# Copia comprimida de las bases de datos de una version (sin la version en marcha)
function backup_databases() {
    local version=$1 dir=${2:-/opt/lampp-$1}
    local user=${SUDO_USER:-$USER}
    local dest_dir=$(getent passwd "$user" | cut -d: -f6)/lvm-copias
    local dest="$dest_dir/lampp-$version-bases-$(date +%Y%m%d-%H%M%S).tar.gz"

    echo "Guardando copia de las bases de datos en $dest..."
    run mkdir -p -m 700 "$dest_dir" || return 1
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] tar -czf $dest -C $dir/var mysql"

        return 0
    fi

    # root solo lee las bases; el fichero lo crea tu usuario (solo para ti). Si root escribiera en
    # tu carpeta, un enlace con ese nombre le haria escribir encima de un fichero del sistema
    if [ "$(id -u)" -eq 0 ] && [ "$user" != root ]; then
        $SUDO tar -czf - -C "$dir/var" mysql | sudo -u "$user" sh -c 'umask 077; cat > "$1"' sh "$dest.parte" \
            || { rm -f "$dest.parte"; return 1; }
    else
        ( umask 077; $SUDO tar -czf - -C "$dir/var" mysql > "$dest.parte" ) || { rm -f "$dest.parte"; return 1; }
    fi
    mv -f "$dest.parte" "$dest" || return 1
    echo "Copia guardada: $dest ($(du -h "$dest" | cut -f1))"
}

# Copia de las bases de datos antes de desinstalar, si caben en la carpeta personal
function remove_backup() {
    local version=$1 dir=/opt/lampp-$1
    local home_dir=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
    local size_kb=0
    [ "$DRY" -eq 0 ] && size_kb=$(sudo du -sk "$dir/var/mysql" 2> /dev/null | cut -f1)
    local free_kb=$(df --output=avail -k "$home_dir" | tail -1 | tr -dc '0-9')

    if [ -n "$size_kb" ] && [ "$free_kb" -lt "$size_kb" ]; then
        echo "No hay espacio para la copia: ocupan $((size_kb / 1024)) MB y hay $((free_kb / 1024)) MB libres en $home_dir."
    elif backup_databases "$version"; then
        return 0
    fi

    echo "No se ha podido guardar la copia, asi que NO se desinstala nada."

    return 1
}

# desinstalar <version> [--copia]: sin preguntas (lo usa la ventana, que ya ha confirmado)
function cli_remove() {
    local version=$1 backup=0
    [ "$2" == "--copia" ] && backup=1

    local blocker=$(remove_blocker "$version")
    if [ -n "$blocker" ]; then
        echo -e "$blocker"

        return 1
    fi

    [ $backup -eq 1 ] && ! remove_backup "$version" && return 1

    remove_lampp "$version"
}

# Arranca, para o reinicia la version activa
function control_lampp() {
    if [ ! -L /opt/lampp ]; then
        echo "No hay ninguna version activa"

        return 1
    fi

    # Antes de arrancar, fuera los de otras versiones (ademas ocuparian los puertos 80, 443 y 3306)
    # y solo para este equipo
    if [ "$1" == start ] || [ "$1" == restart ]; then
        close_processes
        secure_lampp "$(active_dir)"
        secure_failed $? "$(active_dir)" && return 1
        vhosts_root
    fi
    local rc
    run sudo /opt/lampp/lampp "$1"
    rc=$?
    # Parada: no queda nada en memoria, tampoco de esta version
    if [ "$1" == stop ]; then
        close_processes --todos
    fi
    return $rc
}

function remove_lampp() {
    local version=$1
    local blocker=$(remove_blocker "$version")

    if [ -n "$blocker" ]; then
        echo -e "$blocker"

        return 1
    fi

    # htdocs y vhosts son enlaces (y las bases de datos, en las antiguas sobre XAMPP): rm no los sigue
    run sudo rm -R --one-file-system "/opt/lampp-$version" || return 1

    if [ "$DRY" -eq 1 ]; then
        echo "SIMULACION: no se ha borrado nada"
    else
        echo "lampp-$version desinstalada"
    fi
}

# Lo que trae de fabrica el htdocs de XAMPP
XAMPP_HTDOCS_DEFAULTS="applications.html|bitnami.css|dashboard|favicon.ico|img|index.php|webalizer|xampp"

# Convierte el XAMPP real de /opt/lampp en /opt/lampp-<nombre>, compartiendo htdocs y vhosts
function register_lampp() {
    local version=$1

    if [ ! -d "/opt/lampp" ] || [ -L "/opt/lampp" ]; then
        echo "Debes tener una instalacion valida en /opt/lampp antes de registrarla como una version alternativa"

        return 1
    fi

    if [ -z "$version" ] || ! valid_version_name "$version" || [ -e "/opt/lampp-$version" ]; then
        echo "Nombre no valido o ya existe /opt/lampp-$version"

        return 1
    fi

    run sudo /opt/lampp/lampp stop

    # Si ya hay /opt/htdocs (compartido), el htdocs de este XAMPP no se borra si tiene algo mas que
    # lo de fabrica (un XAMPP instalado a mano puede tener proyectos): se aparta en /opt, sin tocar
    # /opt/htdocs, y se avisa de donde esta
    local stamp=$(date +%Y%m%d-%H%M%S) extra
    if [ ! -d "/opt/htdocs" ]; then
        run sudo mv /opt/lampp/htdocs /opt/htdocs
    else
        extra=$(find /opt/lampp/htdocs -mindepth 1 -maxdepth 1 2> /dev/null | sed 's|.*/||' \
            | grep -vxE "$XAMPP_HTDOCS_DEFAULTS" | head -5)
        if [ -n "$extra" ]; then
            run sudo mv /opt/lampp/htdocs "/opt/htdocs-de-lampp-$version-$stamp"
            echo "El htdocs de este XAMPP tenia proyectos ($(paste -sd ',' - <<< "$extra" | sed 's/,/, /g')...): no se"
            echo "borra. Esta en /opt/htdocs-de-lampp-$version-$stamp; pasa a /opt/htdocs lo que quieras usar."
        else
            run sudo rm -R --one-file-system /opt/lampp/htdocs
        fi
    fi

    if [ ! -f "/opt/config/httpd-vhosts.conf" ]; then
        run sudo mkdir -p /opt/config
        run sudo mv /opt/lampp/etc/extra/httpd-vhosts.conf /opt/config/httpd-vhosts.conf
    else
        # (sus vhosts, por si tenia alguno propio: una copia en ~/lvm-copias)
        if [ "$DRY" -eq 0 ] && [ -f /opt/lampp/etc/extra/httpd-vhosts.conf ] \
                && grep -qvE '^[[:space:]]*(#|$)' /opt/lampp/etc/extra/httpd-vhosts.conf; then
            mkdir -p -m 700 "$HOME/lvm-copias" \
                && cp /opt/lampp/etc/extra/httpd-vhosts.conf "$HOME/lvm-copias/httpd-vhosts-de-lampp-$version-$stamp.conf" \
                && echo "Sus vhosts estan en ~/lvm-copias/httpd-vhosts-de-lampp-$version-$stamp.conf (copialos con Editar vhosts)"
        fi
        run sudo rm /opt/lampp/etc/extra/httpd-vhosts.conf
    fi

    run sudo mv /opt/lampp "/opt/lampp-$version"
    run sudo ln -s /opt/htdocs "/opt/lampp-$version/htdocs"
    run sudo ln -s /opt/config/httpd-vhosts.conf "/opt/lampp-$version/etc/extra/httpd-vhosts.conf"

    # Lo demas del manual de XAMPP, si falta: vhosts activados, Apache con tu usuario y htdocs tuyo
    [ -f "/opt/lampp-$version/etc/httpd.conf" ] \
        && run sudo sed -i 's|^#\(Include etc/extra/httpd-vhosts.conf\)|\1|' "/opt/lampp-$version/etc/httpd.conf"
    ensure_web_user "/opt/lampp-$version"
    # Y solo para este equipo (XAMPP escucha en toda la red y trae el FTP con daemon/xampp)
    secure_lampp "/opt/lampp-$version"
    vhosts_root
    local web_user=$(web_user_name)
    if [ -d /opt/htdocs ] && [ "$web_user" != root ] && [ "$(stat -c %U /opt/htdocs)" != "$web_user" ]; then
        echo "/opt/htdocs pasa a ser de $web_user para poder crear proyectos sin sudo"
        run sudo chown "$web_user:$(id -gn "$web_user")" /opt/htdocs
    fi

    echo "Nueva version de lampp registrada: $version"
}

# Vuelve a dejar activa la version que lo estaba antes de instalar un XAMPP
function restore_active() {
    local previous=$1 was_running=$2

    # Si un instalador fallido dejo una carpeta real en /opt/lampp, se aparta para no perderla
    if [ -e /opt/lampp ] && [ ! -L /opt/lampp ]; then
        local aside="/opt/lampp-fallido-$(date +%Y%m%d%H%M%S)"
        echo "Se aparta la instalacion incompleta de /opt/lampp a $aside"
        run sudo mv /opt/lampp "$aside"
    fi

    if [ -n "$previous" ] && [ ! -e /opt/lampp ]; then
        secure_lampp "$previous"
        local secure_rc=$?
        run sudo ln -s "$previous" /opt/lampp
        [ "$was_running" -eq 1 ] && ! secure_failed $secure_rc "$previous" && run sudo /opt/lampp/lampp start
    fi
}

# ===========================================================================
# Instalacion de un XAMPP completo
# ===========================================================================

function install_xampp() {
    local folder=$1 entry release php apache mariadb ftp perl pma md5 sha

    entry=$(catalog_entry "$folder") || { echo "XAMPP $folder no esta en el catalogo"; exit 1; }
    native_binaries || { echo "XAMPP solo esta disponible para equipos x86_64 (este es $(uname -m))"; exit 1; }
    IFS='|' read -r folder release php apache mariadb ftp perl pma md5 sha <<< "$entry"

    local target=/opt/lampp-$folder
    local url="https://sourceforge.net/projects/xampp/files/XAMPP%20Linux/$php/xampp-linux-x64-$release-installer.run/download"

    if [ -e "$target" ]; then
        echo "Ya existe $target"

        exit 1
    fi

    if [ -e /opt/lampp ] && [ ! -L /opt/lampp ]; then
        echo "/opt/lampp es una instalacion sin registrar. Registrala primero desde el panel."

        exit 1
    fi

    echo "Instalando dependencias ($XAMPP_DEPS)..."
    run sudo apt-get install -y -qq $XAMPP_DEPS || exit 1

    local tmp=$(mktemp -d /tmp/lvm-xampp-$release-XXXX)

    progress_parts "Descarga de XAMPP $release (150 MB)" "Instalador oficial de XAMPP" "Configuracion"

    echo "Descargando XAMPP $release (unos 150 MB)..."
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] descarga de $url y comprobacion sha256 $sha y md5 $md5"
    else
        progress 1 0 55 "descargando" bytes "$tmp/xampp.run" "$(remote_size "$url")"
        curl -q --proto =https --proto-redir =https -fsSL -o "$tmp/xampp.run" "$url" || exit 1

        if [ -z "$sha" ] || [ "$(sha256sum "$tmp/xampp.run" | cut -d' ' -f1)" != "$sha" ] \
                || [ "$(md5sum "$tmp/xampp.run" | cut -d' ' -f1)" != "$md5" ]; then
            echo "El instalador descargado no coincide con sus sumas sha256 y md5 esperadas. Se cancela."
            rm -rf "$tmp"

            exit 1
        fi

        chmod +x "$tmp/xampp.run"
    fi

    if [ "$DRY" -eq 1 ]; then
        local user=${SUDO_USER:-$USER}
        echo "  [simulacion] se pararia la version activa y se liberaria /opt/lampp"
        echo "  [simulacion] instalador de XAMPP en modo desatendido en /opt/lampp"
        echo "  [simulacion] registro como $target con /opt/htdocs y /opt/config/httpd-vhosts.conf compartidos"
        echo "  [simulacion] vhosts activados y Apache como $user:$(id -gn "$user" 2> /dev/null)"
        echo "  [simulacion] se reactivaria la version que estaba activa"
        rm -rf "$tmp"

        exit 0
    fi

    # El instalador de XAMPP siempre instala en /opt/lampp: se libera temporalmente
    local previous="" was_running=0
    if [ -L /opt/lampp ]; then
        previous=$(readlink -f /opt/lampp)
        lampp_running && was_running=1
        echo "Parando temporalmente lampp-${previous#/opt/lampp-}..."
        run sudo /opt/lampp/lampp stop
        run sudo unlink /opt/lampp
    fi

    echo "Ejecutando el instalador de XAMPP $release (unos minutos)..."
    progress 2 55 92 "instalando" time "" 120
    # Se ejecuta como root desde una carpeta de root, comprobado otra vez alli: en /tmp lo podria
    # cambiar cualquier programa de tu usuario entre la comprobacion y la ejecucion
    local rtmp
    rtmp=$(sudo mktemp -d /tmp/lvm-xampp-root-XXXX) || { restore_active "$previous" "$was_running"; rm -rf "$tmp"; exit 1; }
    sudo install -m 700 "$tmp/xampp.run" "$rtmp/xampp.run"
    if [ -z "$sha" ] || [ "$(sudo sha256sum "$rtmp/xampp.run" | cut -d' ' -f1)" != "$sha" ] \
            || [ "$(sudo md5sum "$rtmp/xampp.run" | cut -d' ' -f1)" != "$md5" ]; then
        echo "El instalador no coincide con sus sumas sha256 y md5 esperadas. Se cancela."
        sudo rm -rf "$rtmp"
        restore_active "$previous" "$was_running"
        rm -rf "$tmp"

        exit 1
    fi
    run sudo "$rtmp/xampp.run" --mode unattended --unattendedmodeui none
    sudo rm -rf "$rtmp"

    if [ "$DRY" -eq 0 ] && [ ! -x /opt/lampp/lampp ]; then
        echo "El instalador de XAMPP no ha terminado correctamente."
        restore_active "$previous" "$was_running"
        rm -rf "$tmp"

        exit 1
    fi

    progress 3 92 100 "registrando y configurando"
    run sudo /opt/lampp/lampp stop > /dev/null 2>&1
    register_lampp "$folder" || { restore_active "$previous" "$was_running"; exit 1; }

    # Ajustes habituales: vhosts compartidos activados y Apache con el usuario de la sesion
    run sudo sed -i 's|^#\(Include etc/extra/httpd-vhosts.conf\)|\1|' "$target/etc/httpd.conf"

    local web_user=$(web_user_name)
    if [ -n "$web_user" ] && [ "$web_user" != "root" ]; then
        local web_group=$(id -gn "$web_user")
        local conf="$target/apache2/conf/httpd.conf"
        [ -f "$conf" ] || [ "$DRY" -eq 1 ] || conf="$target/etc/httpd.conf"

        echo "Apache se ejecutara como $web_user:$web_group"
        run sudo sed -i '/^\(User\|Group\) /d' "$conf"
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] User $web_user / Group $web_group en $conf"
        else
            printf '\nUser %s\nGroup %s\n' "$web_user" "$web_group" | sudo tee -a "$conf" > /dev/null
        fi
    fi

    restore_active "$previous" "$was_running"
    rm -rf "$tmp"

    echo ""
    echo "XAMPP $release instalado en $target"
    echo "Para usarlo: lvm-instalador use $folder"
}

# ===========================================================================
# Pila propia de una version de PHP nueva (sin XAMPP)
# ===========================================================================

# Progreso de la instalacion, para la barra del panel. Las funciones de instalacion escriben en el
# archivo $PROGRESS (si esta definido) lineas como estas:
#   C|componente 1;componente 2;...               componentes de la version que se instala
#   S|n|desde|hasta|texto|modo|archivo|total|hora  empieza un paso del componente n
# <desde>-<hasta> es el tramo de la barra (en % de la version). Dentro del tramo se avanza segun
# <modo>: lines (lineas de un log), bytes (tamaño de un archivo que se descarga), time (segundos)
# o percent (ultimo "[ NN%]" del log, como el que escribe CMake).
function progress_parts() {
    [ -n "$PROGRESS" ] && echo "C|$(IFS=';'; echo "$*")" >> "$PROGRESS"
    return 0
}

# Cuando MariaDB se compila (MARIADB_SRC=1) es lo que mas tarda: los tramos de los componentes
# anteriores (0-93) se reparten en 0-53 y MariaDB usa 53-96.
function bar_pct() {
    if [ "${MARIADB_SRC:-0}" -eq 1 ] && [ "$2" -lt 6 ]; then
        echo $(( $1 * 53 / 93 ))
    else
        echo "$1"
    fi
}

function progress() {
    [ -n "$PROGRESS" ] && echo "S|$1|$(bar_pct "$2" "$1")|$(bar_pct "$3" "$1")|$4|$5|$6|$7|$(date +%s)" >> "$PROGRESS"
    return 0
}

# Tamaño de un archivo remoto en bytes (siguiendo redirecciones)
function remote_size() {
    curl -q --proto =https --proto-redir =https -fsSLI --max-time 15 "$1" 2> /dev/null | tr -d '\r' | awk 'tolower($1) == "content-length:" {n = $2} END {print n + 0}'
}

# Descarga una URL a la salida estandar. Se guarda una hora en cache, porque las pantallas
# del panel consultan las mismas paginas varias veces.
# (Todas las descargas van con curl -q: sin ~/.curlrc, que cualquier programa tuyo podria preparar
# con --insecure o un proxy suyo)
function fetch() {
    local cache=$LOG_DIR/cache
    local file=$cache/$(echo -n "$1" | md5sum | cut -c1-32)

    # Al instalar (FETCH_FRESH=1) no se pasa por la cache: es tuya (cualquier programa tuyo la puede
    # cambiar) y de ahi salen las direcciones y las huellas de lo que se instala como root
    if [ "${FETCH_FRESH:-0}" == 1 ]; then
        curl -q --proto =https --proto-redir =https -fsSL --max-time 30 "$1" 2> /dev/null
        return
    fi
    if [ ! -s "$file" ] || [ -n "$(find "$file" -mmin +60 2> /dev/null)" ]; then
        mkdir -p "$cache"
        if ! curl -q --proto =https --proto-redir =https -fsSL --max-time 30 "$1" > "$file.$$" 2> /dev/null; then
            rm -f "$file.$$"

            return 1
        fi
        mv "$file.$$" "$file"
    fi

    cat "$file"
}

# Ramas de los componentes que lleva una rama de PHP: "apache mariadb proftpd perl".
# Una rama de PHP posterior a las de STACK_MATRIX usa la ultima fila.
function stack_branches() {
    local row last=${STACK_MATRIX[${#STACK_MATRIX[@]}-1]}

    for row in "${STACK_MATRIX[@]}"; do
        if [ "${row%%|*}" == "$1" ]; then
            echo "$row" | cut -d'|' -f2- | tr '|' ' '

            return 0
        fi
    done

    # Una rama mas nueva que las de la tabla (con soporte en php.net) usa la ultima fila; una mas
    # vieja o desconocida, ninguna (antes recibia sin avisar la de la ultima fila)
    if [[ "$1" =~ ^[0-9]+\.[0-9]+$ ]] && [ "$(printf '%s\n' "$1" "${last%%|*}" | sort -V | tail -1)" == "$1" ]; then
        echo "$last" | cut -d'|' -f2- | tr '|' ' '

        return 0
    fi

    return 1
}

# Ultimo parche publicado de cada componente
function latest_apache() {
    fetch https://dlcdn.apache.org/httpd/ | grep -oE "href=\"httpd-$1\.[0-9]+\.tar\.bz2\"" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -uV | tail -1
}

# latest_apr apr|apr-util
function latest_apr() {
    fetch https://dlcdn.apache.org/apr/ | grep -oE "href=\"$1-1\.[0-9]+\.[0-9]+\.tar\.bz2\"" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -uV | tail -1
}

# Ultima version de una rama de MariaDB: "version|url|sha256". En x86_64, del binario oficial; en
# el resto, del codigo fuente (se compila).
function mariadb_release() {
    local kind=binario
    native_binaries || kind=fuente
    fetch "https://downloads.mariadb.org/rest-api/mariadb/$1/latest/" | python3 -I -c 'import json, re, sys
for version, release in json.load(sys.stdin)["releases"].items():
    # Va en URLs, carpetas y ficheros de configuracion: solo una version normal
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        continue
    if sys.argv[1] == "fuente":
        files = [f for f in release["files"] if f["file_name"] == "mariadb-%s.tar.gz" % version]
    else:
        files = [f for f in release["files"] if f["file_name"].endswith("-x86_64.tar.gz")
                 and "linux" in f["file_name"] and "debug" not in f["file_name"]]
    files.sort(key=lambda f: "systemd" not in f["file_name"])
    if files:
        url = files[0]["file_download_url"].replace("http://", "https://", 1)
        sha = (files[0].get("checksum") or {}).get("sha256sum", "")
        if not url.startswith("https://") or "|" in url or not re.fullmatch(r"[0-9a-f]{64}", sha):
            continue
        print(version + "|" + url + "|" + sha)
        break' "$kind" 2> /dev/null
}

function latest_perl() {
    fetch https://www.cpan.org/src/5.0/ | grep -oE "perl-$1\.[0-9]+\.tar\.xz\"" \
        | grep -oE '5\.[0-9]+\.[0-9]+' | sort -uV | tail -1
}

# ProFTPD publica parches con letra (1.3.9, 1.3.9a, 1.3.9b...). Se descartan las versiones rc.
function latest_proftpd() {
    local tags

    tags=$(fetch "https://api.github.com/repos/proftpd/proftpd/releases?per_page=50" | python3 -I -c 'import json, sys
for release in json.load(sys.stdin):
    # Solo las que publican el .sha256 del tar.gz: sin el no se puede comprobar la descarga (la
    # 1.3.9c, por ejemplo, no lo tiene; antes la instalacion fallaba si el ultimo parche era asi)
    assets = [a["name"] for a in release.get("assets", [])]
    if not release["prerelease"] and any(a.endswith(".tar.gz.sha256") for a in assets):
        print(release["tag_name"])' 2> /dev/null)

    # La API de GitHub limita las consultas: si falla, se leen las etiquetas con git
    if [ -z "$tags" ] && command -v git > /dev/null; then
        tags=$(/usr/bin/python3 -I -c "$NO_TTY_PY" git -c credential.helper= ls-remote --tags https://github.com/proftpd/proftpd 2> /dev/null < /dev/null | grep -oE 'v[0-9.]+[a-z]?$')
    fi

    grep -E "^v$(echo "$1" | sed 's/\./\\./g')[a-z]?$" <<< "$tags" | sed 's/^v//' | sort -V | tail -1
}

function latest_pma() {
    local version=$(fetch https://www.phpmyadmin.net/home_page/version.json \
        | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["version"])' 2> /dev/null)
    # Va en URLs y en la configuracion de Apache: solo numeros y puntos
    [[ "$version" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || version=""

    echo "${version:-$PMA_VERSION}"
}

# Versiones de una pila nueva: "php|apache|mariadb|proftpd|perl|phpmyadmin".
# Si no se puede consultar algun componente, se muestra su rama seguida de ".x".
function stack_versions() {
    local php=$1 branches
    read -r -a branches <<< "$(stack_branches "${php%.*}")"

    local apache=$(latest_apache "${branches[0]}")
    local mariadb=$(mariadb_release "${branches[1]}")
    mariadb=${mariadb%%|*}
    local ftp=$(latest_proftpd "${branches[2]}")
    local perl=$(latest_perl "${branches[3]}")

    echo "$php|${apache:-${branches[0]}.x}|${mariadb:-${branches[1]}.x}|${ftp:-${branches[2]}.x}|${perl:-${branches[3]}.x}|$(latest_pma)"
}

# download <url> <archivo> <sha256>: descarga un archivo y comprueba su suma
function download() {
    local url=$1 file=$2 sum=$3

    if [ -z "$sum" ]; then
        echo "  No se ha encontrado la suma sha256 de $(basename "$url")"

        return 1
    fi

    echo "  Descargando $(basename "$url")..."
    curl -q --proto =https --proto-redir =https -fsSL --retry 2 -o "$file" "$url" || { echo "  No se pudo descargar $url"; return 1; }

    if [ "$(sha256sum "$file" | cut -d' ' -f1)" != "$sum" ]; then
        echo "  $(basename "$url") no coincide con su suma sha256. Se cancela."

        return 1
    fi
}

# download_apache <ruta> <archivo>: dlcdn solo tiene la ultima version; si no esta, archive.apache.org
function download_apache() {
    local base sum

    for base in https://dlcdn.apache.org https://archive.apache.org/dist; do
        sum=$(curl -q --proto =https --proto-redir =https -fsSL "$base/$1.sha256" 2> /dev/null | grep -oE '^[0-9a-f]{64}')
        [ -n "$sum" ] && download "$base/$1" "$2" "$sum" && return 0
    done

    return 1
}

# step <componente> <desde> <hasta> <lineas> <descripcion> <log> <comando...>
# Un paso de la compilacion, con su salida en un log. <desde>-<hasta> es el tramo de la barra de
# progreso (en % de la version) y <lineas> las que suele tener el log al terminar.
# Informe para buscar la solucion de un fallo al instalar: el sistema, lo que se instalaba, el paso
# que fallo con sus primeros errores y el final de su log y, si fallo un configure, la ultima prueba
# de su config.log (ahi esta la causa real). Se guarda con los logs; la ventana lo muestra para
# copiarlo de una vez.
# error_report <informe> <lo que se instalaba> <log del paso o ""> <paso> <config.log o "">
function error_report() {
    local out=$1 what=$2 log=$3 desc=$4 config=$5
    {
        echo "$APP_NAME $APP_VERSION - error al instalar"
        echo "Fecha: $(date '+%Y-%m-%d %H:%M')"
        echo "Sistema: $( . /etc/os-release 2> /dev/null; echo "${PRETTY_NAME:-Linux}") ($(uname -sr), $(uname -m))"
        echo "Compilador: $(cc --version 2> /dev/null | head -1)"
        echo "Instalacion: $what"
        if [ -n "$log" ] && [ -f "$log" ]; then
            echo "Paso que fallo: $desc ($(basename "$log"))"
            local errors=$(grep -E -m 10 '(error:|Error:|ERROR|CMake Error|Undefined symbols|No such file)' "$log" | cut -c1-300)
            [ -n "$errors" ] && printf '\n== Primeros errores ==\n%s\n' "$errors"
            printf '\n== Ultimas 60 lineas de %s ==\n' "$(basename "$log")"
            tail -60 "$log"
        fi
        if [ -n "$config" ] && [ -f "$config" ]; then
            printf '\n== config.log: lo ultimo antes del error ==\n'
            awk '/^## Cache variables/ {exit} {print}' "$config" | grep -v '^## -* ##$' | tail -60
        fi
        printf '\nLogs completos: %s\n' "$(dirname "$out")"
    } > "$out" 2>&1
}

# Claves SSH publicadas de GitHub, GitLab y Bitbucket (para clonar sin aceptar claves nuevas sin mirar)
GIT_KNOWN_HOSTS='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
gitlab.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf
gitlab.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFSMqzJeV9rUzU4kWitGjeR4PWSa29SPqJ1fVkhtj3Hw9xjLVXVYrU9QlYWrOLXBpQ6KWjbjTDTdDkoohFzgbEY=
bitbucket.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIazEu89wgQZ4bqs3d63QSMzYVa0MuJ2e2gKTKqu+UUO
bitbucket.org ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBPIQmuzMBuKdWeF4+a2sjSSpBK0iqitSQ+5BM9KhpexuGt20JpTVM7u5BDZngncgrqDMbWdxMWWOGtZ9UgbqgZE='

# Ejecuta una orden en una sesion nueva, sin terminal de control: NO_TTY_PY <orden> [argumentos...]
NO_TTY_PY='
import os, signal, sys
# El hijo, en su sesion; este proceso se queda en el grupo de la tarea y le pasa las señales de
# Cancelar o Ctrl-C (si no, la compilacion seguiria despues de cancelar)
pid = os.fork()
if pid == 0:
    os.setsid()
    try:
        os.execvp(sys.argv[1], sys.argv[1:])
    except OSError as e:
        sys.stderr.write("%s: %s\n" % (sys.argv[1], e.strerror))
        os._exit(127)
def forward(sig, _):
    try:
        os.killpg(pid, sig)
    except OSError:
        pass
for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(s, forward)
while True:
    try:
        _, status = os.waitpid(pid, 0)
        break
    except InterruptedError:
        continue
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 128 + os.WTERMSIG(status))
'

# no_tty <orden> [argumentos...]: para programas que leen tu configuracion (git, ssh, certutil). Sin
# terminal de control (no pueden usar el permiso de sudo recordado ni abrir /dev/tty) y sin la terminal
# en sus descriptores: la salida pasa por una tuberia, asi que nada que dejen en marcha puede quedarse
# leyendola hasta que sudo pida la contraseña
function no_tty() {
    ( set -o pipefail; /usr/bin/python3 -I -c "$NO_TTY_PY" "$@" < /dev/null 2>&1 | cat )
}

function step() {
    local part=$1 from=$2 to=$3 lines=$4 desc=$5 log=$6
    shift 6

    if [ "$lines" -eq 0 ]; then
        progress "$part" "$from" "$to" "${desc,,}" percent "$log" 100
    else
        progress "$part" "$from" "$to" "${desc,,}" lines "$log" "$lines"
    fi
    printf '  [%3d%%] %s...\n' "$(bar_pct "$from" "$part")" "$desc"
    # Sin terminal (en su propia sesion): lo que se compila esta en una carpeta tuya y lo puede cambiar
    # cualquier programa tuyo; con la terminal de la tarea podria usar el permiso de sudo que ya se ha
    # dado (sudo -n). Sin ella, sudo le pediria la contraseña y falla
    if ! /usr/bin/python3 -I -c "$NO_TTY_PY" "$@" > "$log" 2>&1 < /dev/null; then
        echo "  ERROR: $desc. Ultimas lineas de $(basename "$log"):"
        tail -25 "$log" | sed 's/^/    /'
        # Compilando en paralelo, el error real queda lejos del final (tapado por avisos de otros
        # procesos): se repiten al final los primeros errores
        local errors=$(grep -E -m 5 '(error:|Error:|CMake Error)' "$log" | cut -c1-200)
        [ -n "$errors" ] && echo "  Primeros errores:" && sed 's/^/    /' <<< "$errors"
        STEP_LOG=$log STEP_DESC=$desc

        return 1
    fi
}

# Crea en <carpeta>/var/mysql unas bases de datos nuevas y vacias: solo las del sistema de
# MariaDB, root sin contraseña (como XAMPP) y la base 'phpmyadmin' con el usuario 'pma'.
function init_stack_databases() {
    local target=$1
    local data=$target/var/mysql my=$target/mysql cnf=$target/etc/my.cnf
    local user=mysql
    [ -n "$TEST_DIR" ] && user=$(id -un)

    if [ -e "$data" ]; then
        echo "Ya existe $data, no se crean bases de datos nuevas"

        return 1
    fi

    echo "  Creando bases de datos propias y vacias..."
    $SUDO "$my/scripts/mariadb-install-db" --defaults-file="$cnf" --basedir="$my" --datadir="$data" --user="$user" \
        --auth-root-authentication-method=normal --skip-test-db > "$LOG_DIR/install-db.log" 2>&1 \
        || { tail -20 "$LOG_DIR/install-db.log"; return 1; }

    # Apache y PHP-FPM tienen que poder llegar a mysql.sock, que esta en esta carpeta
    # (cada base de datos sigue protegida en su subcarpeta). Igual que en XAMPP.
    $SUDO chown "$user:" "$data"
    $SUDO chmod 775 "$data"

    # MariaDB temporal sin red y con su propio socket: no choca con la version en marcha. La
    # carpeta la crea root y solo es de mysql (el servidor no pide contraseña mientras se prepara)
    local tmp=$($SUDO mktemp -d /tmp/lvm-mysql-XXXX)
    local sock=$tmp/mysql.sock pid=$tmp/mysql.pid
    $SUDO chown "$user:" "$tmp"
    $SUDO chmod 700 "$tmp"
    $SUDO "$my/bin/mariadbd" --defaults-file="$cnf" --skip-networking --socket="$sock" --pid-file="$pid" \
        --log-error="$tmp/mysql.log" > /dev/null 2>&1 &

    local i
    for i in $(seq 150); do $SUDO test -S "$sock" && break; sleep 0.2; done

    local mysql=($SUDO "$my/bin/mariadb" --no-defaults -S "$sock" -uroot)
    local ok=0
    if $SUDO test -S "$sock" \
        && "${mysql[@]}" < "$target/phpmyadmin/sql/create_tables.sql" \
        && "${mysql[@]}" -e "CREATE USER IF NOT EXISTS 'pma'@'localhost';
            GRANT SELECT, INSERT, UPDATE, DELETE ON phpmyadmin.* TO 'pma'@'localhost';
            FLUSH PRIVILEGES;"; then
        ok=1
    fi

    # (el .pid lo escribe mysql: solo el numero de ese MariaDB, con su socket)
    local spid
    spid=$(db_temp_pid "$pid" "$sock") && $SUDO kill "$spid"
    for i in $(seq 150); do $SUDO test -f "$pid" || break; sleep 0.2; done
    $SUDO rm -rf "$tmp"

    if [ $ok -eq 0 ]; then
        echo "  Aviso: no se pudo crear la base 'phpmyadmin'; phpMyAdmin funcionara pero avisara de que falta su almacenamiento"
    fi

    return 0
}

# Escribe la configuracion de la pila en la carpeta temporal $S (que se copiara a $target).
# Usa las variables de install_stack.
function write_stack_files() {
    local test_mode=0 mysql_user=mysql
    [ -n "$TEST_DIR" ] && test_mode=1 && mysql_user=$(id -un)

    mkdir -p "$S"/{bin,etc/extra,etc/ssl.crt,etc/ssl.key,logs,tmp,cgi-bin,var/run,var/proftpd,php/etc/conf.d}
    # Apache tambien en ::1 si el equipo la tiene (localhost puede ser ::1)
    local listen6_http="" listen6_https=""
    if has_ipv6_loopback; then
        listen6_http="Listen [::1]:$PORT_HTTP"$'\n'
        listen6_https="Listen [::1]:$PORT_HTTPS"$'\n'
    fi

    # --- Apache ---
    local mods="mpm_event authn_file authn_core authz_host authz_groupfile authz_user authz_core access_compat
        auth_basic socache_shmcb reqtimeout include filter deflate brotli mime log_config env expires headers
        setenvif version proxy proxy_fcgi proxy_http ssl http2 unixd status autoindex cgid vhost_alias
        negotiation dir actions alias rewrite remoteip"
    local m load=""
    for m in $mods; do
        [ -f "$S/apache2/modules/mod_$m.so" ] && load+="LoadModule ${m}_module apache2/modules/mod_$m.so"$'\n'
    done

    cat > "$S/etc/httpd.conf" <<EOF
# Apache $apache de lampp-$lampp_name (lvm-instalador)
ServerRoot "$target"
# Solo desde este equipo
Listen 127.0.0.1:$PORT_HTTP
${listen6_http}
$load
<IfModule unixd_module>
User $web_user
Group $web_group
</IfModule>

ServerAdmin you@example.com
ServerName localhost:$PORT_HTTP
PidFile "logs/httpd.pid"
Timeout 300
KeepAlive On

<Directory />
    AllowOverride None
    Require all denied
</Directory>

DocumentRoot "$link/htdocs"
<Directory "$link/htdocs">
    Options Indexes FollowSymLinks ExecCGI Includes
    AllowOverride All
    Require all granted
</Directory>

DirectoryIndex index.php index.html index.htm

<Files ".ht*">
    Require all denied
</Files>

ErrorLog "logs/error_log"
LogLevel warn
LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
LogFormat "%h %l %u %t \"%r\" %>s %b" common
CustomLog "logs/access_log" common

ScriptAlias /cgi-bin/ "$target/cgi-bin/"
<Directory "$target/cgi-bin">
    AllowOverride None
    Options None
    Require all granted
</Directory>

TypesConfig apache2/conf/mime.types
AddType application/x-compress .Z
AddType application/x-gzip .gz .tgz
# Scripts CGI (Perl de esta version: #!$link/bin/perl)
AddHandler cgi-script .cgi .pl

<IfModule http2_module>
    Protocols h2 h2c http/1.1
</IfModule>

# Antes de los vhosts: los dominios que no tienen ninguno solo pasan si son localhost
Include $UNKNOWN_HOST_CONF
Include etc/extra/httpd-vhosts.conf
Include etc/extra/httpd-ssl.conf
Include etc/extra/httpd-lampp.conf
EOF
    printf '%s' "$UNKNOWN_HOST_VHOST" > "$S/$UNKNOWN_HOST_CONF"

    cat > "$S/etc/extra/httpd-ssl.conf" <<EOF
# HTTPS con un certificado autofirmado para localhost (los vhosts usan los suyos)
Listen 127.0.0.1:$PORT_HTTPS
${listen6_https}SSLCipherSuite HIGH:MEDIUM:!aNULL:!MD5
SSLProtocol all -SSLv3
SSLPassPhraseDialog builtin
SSLSessionCache "shmcb:$target/logs/ssl_scache(512000)"
SSLSessionCacheTimeout 300

<VirtualHost _default_:$PORT_HTTPS>
    DocumentRoot "$link/htdocs"
    ServerName localhost:$PORT_HTTPS
    ErrorLog "$target/logs/error_log"
    TransferLog "$target/logs/access_log"
    SSLEngine on
    SSLCertificateFile "$target/etc/ssl.crt/server.crt"
    SSLCertificateKeyFile "$target/etc/ssl.key/server.key"
</VirtualHost>
EOF

    cat > "$S/etc/extra/httpd-lampp.conf" <<EOF
# PHP $version via PHP-FPM
SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=\$1
ProxyTimeout 300
<FilesMatch "\.php$">
    SetHandler "proxy:unix:$target/var/run/php-fpm.sock|fcgi://localhost"
</FilesMatch>

# phpMyAdmin $pma, solo desde este equipo
Alias /phpmyadmin "$target/phpmyadmin"
<Directory "$target/phpmyadmin">
    AllowOverride AuthConfig Limit
    Require local
</Directory>
EOF

    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/CN=localhost" \
        -addext "basicConstraints=critical,CA:FALSE" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
        -keyout "$S/etc/ssl.key/server.key" -out "$S/etc/ssl.crt/server.crt" > /dev/null 2>&1

    # --- PHP ---
    cat > "$S/php/etc/conf.d/99-lampp.ini" <<EOF
; Mismos valores que el php.ini de XAMPP. Sin error_log: los errores van al log de Apache
memory_limit = 512M
upload_max_filesize = 40M
post_max_size = 40M
max_execution_time = 120
max_input_time = 60
max_input_vars = 3000
date.timezone = $PHP_TIMEZONE
error_reporting = E_ALL & ~E_DEPRECATED
display_errors = Off
log_errors = On
mysqli.default_socket = $target/var/mysql/mysql.sock
pdo_mysql.default_socket = $target/var/mysql/mysql.sock
opcache.enable = 1
opcache.revalidate_freq = 0
EOF

    # El OpenSSL 1.1 propio no conoce los certificados del sistema
    if needs_openssl11 "$short" && [ -f /etc/ssl/certs/ca-certificates.crt ]; then
        printf 'openssl.cafile = /etc/ssl/certs/ca-certificates.crt\nopenssl.capath = /etc/ssl/certs\n' >> "$S/php/etc/conf.d/99-lampp.ini"
    fi

    # A partir de PHP 8.5 opcache va integrado y no se carga como extension
    if ls "$S"/php/lib/php/extensions/*/opcache.so > /dev/null 2>&1; then
        echo "zend_extension = opcache" > "$S/php/etc/conf.d/10-opcache.ini"
    fi

    cat > "$S/php/etc/php-fpm.conf" <<EOF
[global]
pid = $target/var/run/php-fpm.pid
error_log = $target/logs/php-fpm.log
daemonize = yes

[lampp]
user = $web_user
group = $web_group
listen = $target/var/run/php-fpm.sock
listen.owner = $web_user
listen.group = $web_group
listen.mode = 0660
pm = ondemand
pm.max_children = 20
pm.process_idle_timeout = 60s
request_terminate_timeout = 300
catch_workers_output = yes
EOF

    # --- MariaDB ---
    mkdir -p "$S/etc/lvm-sin-ficheros"
    cat > "$S/etc/my.cnf" <<EOF
# MariaDB $mariadb de lampp-$lampp_name (lvm-instalador)
[client]
port = $PORT_MYSQL
socket = $target/var/mysql/mysql.sock
default-character-set = utf8mb4

[mysqld]
user = $mysql_user
port = $PORT_MYSQL
# Solo desde este equipo
bind-address = 127.0.0.1
# Sin leer ni escribir ficheros del equipo desde SQL (la carpeta esta vacia y es de root)
secure-file-priv = "$target/etc/lvm-sin-ficheros"
local-infile = 0
socket = $target/var/mysql/mysql.sock
basedir = $target/mysql
datadir = $target/var/mysql
plugin_dir = $target/mysql/lib/plugin
pid-file = $target/var/mysql/mysqld.pid
log-error = $target/var/mysql/mysqld.err
max_allowed_packet = 512M
table_open_cache = 640
sort_buffer_size = 5120K
read_buffer_size = 2560K
read_rnd_buffer_size = 5120K
myisam_sort_buffer_size = 80M
innodb_lock_wait_timeout = 50
# Mismo cotejamiento que XAMPP, para que los volcados se puedan importar en versiones
# anteriores y en los servidores (desde MariaDB 11.2 el de por defecto es uca1400)
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
loose-character-set-collations = utf8mb4=utf8mb4_general_ci

[mysqldump]
max_allowed_packet = 512M
EOF

    # --- ProFTPD: acceso a htdocs con el usuario del equipo y su contraseña ---
    cat > "$S/etc/proftpd.conf" <<EOF
# ProFTPD $ftp de lampp-$lampp_name (lvm-instalador)
ServerName "ProFTPD lampp-$lampp_name"
ServerType standalone
DefaultServer on
Port $PORT_FTP
# Solo desde este equipo
DefaultAddress 127.0.0.1
SocketBindTight on
Umask 022
MaxInstances 30
User $web_user
Group $web_group
PidFile $target/var/proftpd/proftpd.pid
ScoreboardFile $target/var/proftpd/proftpd.scoreboard
SystemLog $target/logs/proftpd.log
TransferLog $target/logs/xferlog
UseReverseDNS off
RequireValidShell off
<IfModule mod_ident.c>
    IdentLookups off
</IfModule>
<IfModule mod_delay.c>
    DelayTable $target/var/proftpd/proftpd.delay
</IfModule>

DefaultRoot $link/htdocs
<Limit LOGIN>
    AllowUser $web_user
    DenyAll
</Limit>
<Directory $link/htdocs/*>
    AllowOverwrite on
</Directory>
<Limit SITE_CHMOD>
    DenyAll
</Limit>
EOF

    # --- phpMyAdmin: como en XAMPP, entra como root sin contraseña ---
    local secret=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    cat > "$S/phpmyadmin/config.inc.php" <<EOF
<?php
declare(strict_types=1);

\$cfg['blowfish_secret'] = '$secret';

\$i = 1;
\$cfg['Servers'][\$i]['auth_type'] = 'config';
\$cfg['Servers'][\$i]['user'] = 'root';
\$cfg['Servers'][\$i]['password'] = '';
\$cfg['Servers'][\$i]['host'] = 'localhost';
\$cfg['Servers'][\$i]['socket'] = '$target/var/mysql/mysql.sock';
\$cfg['Servers'][\$i]['AllowNoPassword'] = true;
\$cfg['Servers'][\$i]['controluser'] = 'pma';
\$cfg['Servers'][\$i]['controlpass'] = '';
\$cfg['Servers'][\$i]['pmadb'] = 'phpmyadmin';
EOF
    for m in bookmark relation table_info table_coords pdf_pages column_info history table_uiprefs tracking \
        userconfig recent users usergroups navigationhiding savedsearches central_columns designer_settings \
        export_templates favorite; do
        local key=$m
        [ "$m" == "bookmark" ] && key=bookmarktable
        echo "\$cfg['Servers'][\$i]['$key'] = 'pma__$m';" >> "$S/phpmyadmin/config.inc.php"
    done
    cat >> "$S/phpmyadmin/config.inc.php" <<EOF

\$cfg['TempDir'] = '$target/phpmyadmin/tmp';
\$cfg['UploadDir'] = '';
\$cfg['SaveDir'] = '';
EOF
    mkdir -p "$S/phpmyadmin/tmp"

    # --- Script de arranque y parada (lo usa "lvm-instalador use") ---
    sed -e "s|@ROOT@|$target|g" -e "s|@NAME@|$lampp_name|g" -e "s|@NEED_ROOT@|$(( 1 - test_mode ))|g" > "$S/lampp" <<'EOF'
#!/bin/bash
# Arranque y parada de lampp-@NAME@ (pila propia creada por lvm-instalador):
# Apache con PHP-FPM, MariaDB y ProFTPD.
# Uso: lampp start|stop|restart|status|startapache|stopapache|reloadapache|startmysql|stopmysql|startftp|stopftp

ROOT=@ROOT@
APACHE_PID=$ROOT/logs/httpd.pid
MYSQL_PID=$ROOT/var/mysql/mysqld.pid
MYSQL_SOCK=$ROOT/var/mysql/mysql.sock
FTP_PID=$ROOT/var/proftpd/proftpd.pid

if [ @NEED_ROOT@ -eq 1 ] && [ "$(id -u)" -ne 0 ]; then
    echo "Hay que ejecutarlo como administrador: sudo $0 $*"
    exit 1
fi

# Numero de proceso de un .pid: solo un numero de verdad (ni 0, ni 1, ni negativo). Este script
# corre como root y el .pid de MariaDB lo escribe mysql
function pid_in() {
    local p
    p=$(head -c 20 "$1" 2> /dev/null | tr -d " \n")
    [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -gt 1 ] && echo "$p"
}

function running() {
    local p
    p=$(pid_in "$1") && kill -0 "$p" 2> /dev/null
}

# Espera hasta <segundos> a que se cumpla una condicion
function wait_until() {
    local seconds=$1 i
    shift

    for i in $(seq $(( seconds * 10 ))); do
        "$@" && return 0
        sleep 0.1
    done

    return 1
}

function stopped() {
    ! running "$1"
}

function mysql_ready() {
    running "$MYSQL_PID" && [ -S "$MYSQL_SOCK" ]
}

function start_apache() {
    running "$APACHE_PID" && { echo "Apache ya estaba arrancado."; return 0; }

    "$ROOT/bin/lvm-php-fpm" start
    # Como XAMPP: los avisos del arranque (vhosts sin carpeta, certificados...) van al log
    if "$ROOT/apache2/bin/httpd" -f "$ROOT/etc/httpd.conf" -E "$ROOT/logs/error_log" -k start >> "$ROOT/logs/error_log" 2>&1 \
        && wait_until 10 running "$APACHE_PID"; then
        echo "Apache arrancado."
    else
        echo "Apache no ha arrancado. Revisa $ROOT/logs/error_log"
        return 1
    fi
}

function stop_apache() {
    if running "$APACHE_PID"; then
        "$ROOT/apache2/bin/httpd" -f "$ROOT/etc/httpd.conf" -k stop
        wait_until 15 stopped "$APACHE_PID"
        echo "Apache parado."
    fi
    "$ROOT/bin/lvm-php-fpm" stop
}

function reload_apache() {
    "$ROOT/bin/lvm-php-fpm" reload
    running "$APACHE_PID" && "$ROOT/apache2/bin/httpd" -f "$ROOT/etc/httpd.conf" -E "$ROOT/logs/error_log" -k graceful >> "$ROOT/logs/error_log" 2>&1 \
        && echo "Apache recargado."
}

function start_mysql() {
    running "$MYSQL_PID" && { echo "MariaDB ya estaba arrancado."; return 0; }

    # mariadbd-safe busca sus herramientas desde la carpeta de MariaDB
    (cd "$ROOT/mysql" && nohup ./bin/mariadbd-safe --defaults-file="$ROOT/etc/my.cnf" > /dev/null 2>&1 &)
    if wait_until 60 mysql_ready; then
        echo "MariaDB arrancado."
    else
        echo "MariaDB no ha arrancado. Revisa $ROOT/var/mysql/mysqld.err"
        return 1
    fi
}

function stop_mysql() {
    running "$MYSQL_PID" || return 0

    local p
    # (y solo si es el MariaDB: su .pid lo podria cambiar mysql)
    p=$(pid_in "$MYSQL_PID") && [[ "$(cat "/proc/$p/comm" 2> /dev/null)" =~ ^(mariadbd|mysqld)$ ]] && kill "$p"
    wait_until 60 stopped "$MYSQL_PID" && echo "MariaDB parado." || echo "MariaDB sigue parandose."
}

function start_ftp() {
    running "$FTP_PID" && { echo "ProFTPD ya estaba arrancado."; return 0; }

    if "$ROOT/proftpd/sbin/proftpd" -c "$ROOT/etc/proftpd.conf" 2> /dev/null && wait_until 5 running "$FTP_PID"; then
        echo "ProFTPD arrancado."
    else
        echo "ProFTPD no ha arrancado. Revisa $ROOT/logs/proftpd.log"
        return 1
    fi
}

function stop_ftp() {
    running "$FTP_PID" || return 0

    local p
    p=$(pid_in "$FTP_PID") && kill "$p"
    wait_until 10 stopped "$FTP_PID"
    echo "ProFTPD parado."
}

function status() {
    local name pid

    echo "lampp-@NAME@ (pila propia)"
    for name in Apache MariaDB ProFTPD; do
        case $name in
            Apache) pid=$APACHE_PID ;;
            MariaDB) pid=$MYSQL_PID ;;
            ProFTPD) pid=$FTP_PID ;;
        esac
        running "$pid" && echo "$name esta arrancado." || echo "$name no esta arrancado."
    done
    "$ROOT/bin/lvm-php-fpm" status
}

case "$1" in
    # El FTP solo si se ha activado (lampp startftp; lo quita lampp stopftp)
    start) echo "Arrancando lampp-@NAME@..."; start_mysql; start_apache; if [ -f "$ROOT/etc/lvm-startftp" ]; then start_ftp; fi ;;
    stop) echo "Parando lampp-@NAME@..."; stop_apache; stop_mysql; stop_ftp ;;
    restart|reload) "$0" stop; "$0" start ;;
    status) status ;;
    startapache) start_apache ;;
    stopapache) stop_apache ;;
    reloadapache) reload_apache ;;
    restartapache) stop_apache; start_apache ;;
    startmysql) start_mysql ;;
    stopmysql) stop_mysql ;;
    restartmysql) stop_mysql; start_mysql ;;
    startftp) touch "$ROOT/etc/lvm-startftp"; start_ftp ;;
    stopftp) rm -f "$ROOT/etc/lvm-startftp"; stop_ftp ;;
    *) sed -n '4p' "$0" | sed 's/^# //'; exit 1 ;;
esac
EOF
    chmod 755 "$S/lampp"

    # PHP-FPM se arranca con el entorno limpio
    sed -e "s|@ROOT@|$target|g" -e "s|@VERSION@|$version|g" > "$S/bin/lvm-php-fpm" <<'EOF'
#!/bin/bash
# PHP-FPM @VERSION@ (lo arrancan y paran startapache/stopapache del script lampp)
FPM=@ROOT@/php/sbin/php-fpm
CONF=@ROOT@/php/etc/php-fpm.conf
PID=@ROOT@/var/run/php-fpm.pid

running() { [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2> /dev/null; }

case "$1" in
    start)
        running || env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin "$FPM" --fpm-config "$CONF"
        ;;
    stop)
        running && kill -QUIT "$(cat "$PID")"
        for i in $(seq 50); do running || break; sleep 0.1; done
        ;;
    reload)
        running && kill -USR2 "$(cat "$PID")"
        ;;
    status)
        running && echo "PHP-FPM @VERSION@ esta arrancado." || echo "PHP-FPM @VERSION@ no esta arrancado."
        ;;
esac
EOF
    chmod 755 "$S/bin/lvm-php-fpm"

    # --- Comandos en bin/, como en XAMPP: /opt/lampp/bin/php, /opt/lampp/bin/mysql... ---
    for m in php php-config phpize; do ln -s "../php/bin/$m" "$S/bin/$m"; done
    for m in perl perldoc cpan; do ln -s "../perl/bin/$m" "$S/bin/$m"; done
    for m in httpd ab htpasswd; do [ -e "$S/apache2/bin/$m" ] && ln -s "../apache2/bin/$m" "$S/bin/$m"; done

    # Los clientes de MariaDB leen el my.cnf de esta version (socket y puerto). Los nombres
    # antiguos (mysql, mysqldump...) llaman a los nuevos, que no avisan de que estan obsoletos.
    local name real
    for name in mysql:mariadb mysqldump:mariadb-dump mysqladmin:mariadb-admin mysqlcheck:mariadb-check \
        mysqlimport:mariadb-import mysqlshow:mariadb-show mysql_upgrade:mariadb-upgrade; do
        real=${name#*:}
        [ -e "$S/mysql/bin/$real" ] || real=${name%%:*}
        [ -e "$S/mysql/bin/$real" ] || continue
        for m in ${name%%:*} ${name#*:}; do
            printf '#!/bin/sh\nexec %s/mysql/bin/%s --defaults-file=%s/etc/my.cnf "$@"\n' "$target" "$real" "$target" > "$S/bin/$m"
            chmod 755 "$S/bin/$m"
        done
    done

    # htdocs y vhosts compartidos con las demas versiones
    if [ $test_mode -eq 1 ]; then
        mkdir -p "$S/htdocs"
        echo '<?php phpinfo();' > "$S/htdocs/index.php"
        : > "$S/etc/extra/httpd-vhosts.conf"
    else
        ln -s /opt/htdocs "$S/htdocs"
        ln -s /opt/config/httpd-vhosts.conf "$S/etc/extra/httpd-vhosts.conf"
    fi

    echo "$version" > "$S/etc/lvm-php"
    echo "$version|$apache|$mariadb|$ftp|$perl|$pma" > "$S/etc/lvm-stack"
    # Ya se instala solo para este equipo (secure_lampp no tiene nada que cambiar)
    echo "1" > "$S/$SECURE_MARK"
}

# PHP convierte cada -L de OPENSSL_LIBS/ICU_LIBS en una ruta de busqueda grabada en el binario
# (RUNPATH), y descarta cualquier -Wl,-rpath. Con OpenSSL e ICU propios esas rutas son de la carpeta
# temporal: se cambian por la definitiva de OpenSSL o se quitan (ICU es estatico).
# Usa las variables locales de install_stack.
function fix_php_runpath() {
    local elf

    [ ${#php_env[@]} -eq 0 ] && return 0

    for elf in "$S"/php/sbin/php-fpm "$S"/php/bin/php "$S"/php/bin/phpdbg; do
        [ -f "$elf" ] || continue
        if needs_openssl11 "$short"; then
            patchelf --set-rpath "$target/openssl/lib" "$elf" || return 1
        else
            patchelf --remove-rpath "$elf" || return 1
        fi
    done
}

# Ningun binario puede buscar librerias en la carpeta temporal de la compilacion: al borrarse,
# cualquier usuario podria crearla en /tmp con librerias falsas que se cargarian al arrancar.
# Enlaces de lo compilado que llevan fuera de la version (salvo htdocs y los vhosts compartidos):
# lo compilado es de tu usuario hasta que root lo copia, y un programa tuyo podria dejar un enlace
# a /etc para que root lo cambiara despues. Uso: <carpeta temporal> <carpeta definitiva>
BUILD_LINKS_PY='
import os, posixpath, sys
root, target = sys.argv[1], sys.argv[2]
ok = {"htdocs": "/opt/htdocs", "etc/extra/httpd-vhosts.conf": "/opt/config/httpd-vhosts.conf"}
# (los compartidos llevan a carpetas tuyas: nada puede apuntar a traves de ellos)
shared = [posixpath.join(target, k) for k in ok]
def under(path, top):
    return path == top or path.startswith(top + "/")
me = os.getuid()
for d, dirs, files in os.walk(root):
    for name in dirs + files:
        p = os.path.join(d, name)
        if not os.path.islink(p):
            # En la carpeta temporal todo lo ha creado tu usuario: un fichero de otro es un enlace duro
            # a un fichero suyo (macOS no los protege) que root copiaria
            if root != target and os.lstat(p).st_uid != me:
                print("%s (de otro usuario: enlace duro)" % os.path.relpath(p, root))
            continue
        rel, lt = os.path.relpath(p, root), os.readlink(p)
        if ok.get(rel) == lt:
            continue
        v = posixpath.join(target, rel)
        r = posixpath.normpath(lt if lt.startswith("/") else posixpath.join(posixpath.dirname(v), lt))
        bad = not under(r, target) or any(under(r, s) for s in shared)
        # La copia ya en su sitio (de root): tambien como lo resuelve el sistema, con los enlaces de en medio
        if root == target and not under(os.path.realpath(p), os.path.realpath(target)):
            bad = True
        if bad:
            print("%s -> %s" % (rel, lt))
'
function check_build_links() {
    local bad
    bad=$(/usr/bin/python3 -I -c "$BUILD_LINKS_PY" "$S" "$target") || bad="(no se han podido mirar)"
    bad=$(cut -c1-300 <<< "$bad")
    if [ -n "$bad" ]; then
        echo "  Lo compilado tiene enlaces que llevan fuera de $target (no se copia nada):"
        echo "$bad" | head -10 | sed 's/^/    /'

        return 1
    fi
}

function check_no_build_paths() {
    local bad=$(find "$S" -type f \( -perm -u+x -o -name '*.so*' \) -print0 2> /dev/null \
        | xargs -0 -r sh -c 'for f; do readelf -d "$f" 2> /dev/null | grep -qE "R(UN)?PATH.*'"$build"'" && echo "$f"; done' sh)

    if [ -n "$bad" ]; then
        echo "  Estos binarios buscan librerias en la carpeta temporal $build:"
        echo "$bad" | sed "s|^$S/|    |"

        return 1
    fi
}

# install_stack <version de PHP> [reemplazar] [carpeta: lampp-<carpeta>, por defecto la rama X.Y]
# Compila Apache, PHP, Perl y ProFTPD, y descarga MariaDB (binario oficial) y phpMyAdmin, todo
# dentro de /opt/lampp-X.Y. Se instala primero en una carpeta temporal (DESTDIR) y solo al final
# se copia a /opt, asi que si algo falla no queda nada a medias.
# Con reemplazar=1 sustituye la version que ya existe en /opt/lampp-X.Y. Si su MariaDB es de la
# misma rama, conserva sus bases de datos; si no, guarda una copia y empieza con unas vacias.
function install_stack() {
    local version=$1 replace=${2:-0}
    local FETCH_FRESH=1

    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Indica la version completa de PHP, por ejemplo: 8.4.26"

        exit 1
    fi

    # La carpeta es la rama (lampp-8.4) o, para un parche concreto, la version completa (lampp-8.4.10)
    local short=${version%.*}
    local lampp_name=${3:-$short}
    local target=/opt/lampp-$lampp_name link=/opt/lampp
    [ -n "$TEST_DIR" ] && target=$TEST_DIR/lampp-$lampp_name && link=$target

    if [ "$replace" -eq 0 ] && [ -e "$target" ]; then
        echo "Ya existe $target"

        exit 1
    fi

    if [ "$replace" -eq 1 ] && [ ! -d "$target" ]; then
        echo "No existe $target, no hay nada que actualizar"

        exit 1
    fi

    if [ "$replace" -eq 1 ] && [ -e "$target/htdocs" ] && [ ! -L "$target/htdocs" ] && [ -z "$TEST_DIR" ]; then
        echo "$target tiene una carpeta htdocs propia (no es un enlace a /opt/htdocs) y podria contener proyectos."
        echo "Revisala y muevela a mano antes de actualizar la version."

        exit 1
    fi

    echo "Consultando las ultimas versiones de cada componente..."
    local branches
    if ! stack_branches "$short" > /dev/null; then
        echo "PHP $short no esta entre las ramas que instala este gestor"

        exit 1
    fi
    if ! printf '%s\n' "${STACK_MATRIX[@]}" | grep -q "^$short|"; then
        echo "Aviso: PHP $short es mas nueva que las ramas probadas. Se instala con los componentes de la ${STACK_MATRIX[${#STACK_MATRIX[@]}-1]%%|*}."
    fi
    read -r -a branches <<< "$(stack_branches "$short")"

    local apache=$(latest_apache "${branches[0]}")
    local apr=$(latest_apr apr) aprutil=$(latest_apr apr-util)
    local mariadb_info=$(mariadb_release "${branches[1]}")
    local mariadb=${mariadb_info%%|*}
    local ftp=$(latest_proftpd "${branches[2]}")
    local perl=$(latest_perl "${branches[3]}")
    local pma=$(latest_pma)
    local php_sha=$(curl -q --proto =https --proto-redir =https -fsSL "https://www.php.net/releases/index.php?json&version=$version" \
        | python3 -I -c 'import json,sys; print([s["sha256"] for s in json.load(sys.stdin)["source"] if s["filename"].endswith(".tar.xz")][0])' 2> /dev/null)

    local missing=""
    [ -z "$php_sha" ] && missing+=" PHP-$version"
    [ -z "$apache" ] && missing+=" Apache-${branches[0]}"
    [ -z "$apr" ] || [ -z "$aprutil" ] && missing+=" APR"
    [ -z "$mariadb" ] && missing+=" MariaDB-${branches[1]}"
    [ -z "$ftp" ] && missing+=" ProFTPD-${branches[2]}"
    [ -z "$perl" ] && missing+=" Perl-${branches[3]}"

    if [ -n "$missing" ]; then
        echo "No se pudo consultar la ultima version de:$missing (¿hay conexion a internet?)"

        exit 1
    fi

    local web_user=$(web_user_name)
    local web_group=$(id -gn "$web_user")

    # Que hacer con las bases de datos de la version que se sustituye
    local keep_data=0 old_mariadb=""
    if [ "$replace" -eq 1 ]; then
        old_mariadb=$(stack_fields "$target" | cut -d'|' -f3)
        [ -f "$target/etc/lvm-stack" ] && [ -d "$target/var/mysql" ] && [ ! -L "$target/var/mysql" ] \
            && [ "${old_mariadb%.*}" == "${mariadb%.*}" ] && keep_data=1
    fi

    echo ""
    local stack_line="lampp-$lampp_name: PHP $version, Apache $apache, MariaDB $mariadb, ProFTPD $ftp, Perl $perl, phpMyAdmin $pma"
    echo "$stack_line"
    echo "Carpeta: $target   Usuario de Apache, PHP y FTP: $web_user:$web_group"

    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] dependencias de compilacion: $STACK_BUILD_DEPS"
        echo "  [simulacion] descarga con comprobacion sha256 y compilacion de Apache, APR $apr/$aprutil, PHP, Perl y ProFTPD"
        needs_openssl11 "$short" && echo "  [simulacion] OpenSSL $OPENSSL11_VERSION propio para PHP $short en $target/openssl"
        needs_icu72 "$short" && echo "  [simulacion] ICU 72.1 estatico dentro de PHP $short"
        if native_binaries; then
            echo "  [simulacion] MariaDB $mariadb: binario oficial de mariadb.org"
        else
            echo "  [simulacion] MariaDB $mariadb: se compila (no hay binario oficial para $(uname -m)); dependencias: $MARIADB_BUILD_DEPS"
        fi
        if [ "$replace" -eq 1 ] && [ $keep_data -eq 1 ]; then
            echo "  [simulacion] se sustituiria $target conservando sus bases de datos (MariaDB ${mariadb%.*})"
        elif [ "$replace" -eq 1 ]; then
            echo "  [simulacion] copia de las bases de datos de $target en ~/lvm-copias y bases nuevas y vacias"
        else
            echo "  [simulacion] bases de datos propias y vacias en $target/var/mysql (root sin contraseña)"
        fi
        echo "  [simulacion] puertos: web $PORT_HTTP/$PORT_HTTPS, MariaDB $PORT_MYSQL, FTP $PORT_FTP"

        exit 0
    fi

    if [ -z "$TEST_DIR" ]; then
        echo "Instalando dependencias de compilacion (solo librerias, no PHP)..."
        local deps=$STACK_BUILD_DEPS
        native_binaries || deps+=" $MARIADB_BUILD_DEPS"
        sudo apt-get update -qq && sudo apt-get install -y -qq $deps > /dev/null || exit 1

        # MariaDB se ejecuta con el usuario 'mysql', como en XAMPP
        if ! id mysql > /dev/null 2>&1; then
            sudo useradd --system --no-create-home --shell /usr/sbin/nologin mysql || exit 1
        fi
    fi

    STEP_LOG="" STEP_DESC=""
    local build=$(mktemp -d /tmp/lvm-pila-$lampp_name-XXXX)
    local stage=$build/stage
    local S=$stage$target
    local jobs=$(nproc)
    local MARIADB_SRC=0
    native_binaries || MARIADB_SRC=1
    # Compilar MariaDB necesita 1,5 GB de memoria por proceso: en maquinas virtuales pequeñas se
    # usan menos procesos para que no se quede sin memoria
    local mem_mb=$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo 2> /dev/null)
    local mariadb_jobs=$(( ${mem_mb:-2048} / 1536 ))
    (( mariadb_jobs < 1 )) && mariadb_jobs=1
    (( mariadb_jobs > jobs )) && mariadb_jobs=$jobs

    # Si algo falla se guardan los logs y se borra la carpeta temporal
    function stack_fail() {
        local logs=$LOG_DIR/pila-$lampp_name-$(date +%Y%m%d-%H%M%S)
        mkdir -p "$logs"
        cp "$build"/*.log "$logs/" 2> /dev/null
        # El config.log del componente que fallaba (stack_fail se llama desde su carpeta): ahi esta
        # el motivo real de los errores de configure
        local config=""
        if [ -f config.log ]; then
            config="$logs/$(basename "$PWD")-config.log"
            cp config.log "$config"
        fi
        rm -rf "$build"
        error_report "$logs/informe-error.txt" "$stack_line" "${STEP_LOG:+$logs/$(basename "$STEP_LOG")}" "$STEP_DESC" "$config"
        echo "No se ha instalado nada. Logs de la compilacion en $logs"
        echo "Informe del error: $logs/informe-error.txt"

        exit 1
    }

    cd "$build" || exit 1

    local php_part="PHP $version"
    needs_openssl11 "$short" && php_part+=" + OpenSSL $OPENSSL11_VERSION"
    needs_icu72 "$short" && php_part+=" + ICU 72.1"
    progress_parts "Descargas" "Apache $apache" "$php_part" "Perl $perl" "ProFTPD $ftp" "MariaDB $mariadb" \
        "phpMyAdmin $pma y configuracion"

    echo "Descargando el codigo fuente (con comprobacion sha256)..."
    progress 1 0 2 "codigo fuente"
    download_apache "httpd/httpd-$apache.tar.bz2" httpd.tar.bz2 || stack_fail
    download_apache "apr/apr-$apr.tar.bz2" apr.tar.bz2 || stack_fail
    download_apache "apr/apr-util-$aprutil.tar.bz2" apr-util.tar.bz2 || stack_fail
    download "https://www.php.net/distributions/php-$version.tar.xz" php.tar.xz "$php_sha" || stack_fail
    if needs_openssl11 "$short"; then
        download "https://www.openssl.org/source/openssl-$OPENSSL11_VERSION.tar.gz" openssl11.tar.gz "$OPENSSL11_SHA" || stack_fail
    fi
    if needs_icu72 "$short"; then
        download "https://github.com/unicode-org/icu/releases/download/release-72-1/icu4c-72_1-src.tgz" icu72.tgz "$ICU72_SHA" || stack_fail
    fi
    download "https://www.cpan.org/src/5.0/perl-$perl.tar.xz" perl.tar.xz \
        "$(curl -q --proto =https --proto-redir =https -fsSL "https://www.cpan.org/src/5.0/perl-$perl.tar.xz.sha256.txt" | grep -oE '^[0-9a-f]{64}')" || stack_fail
    download "https://github.com/proftpd/proftpd/archive/refs/tags/v$ftp.tar.gz" proftpd.tar.gz \
        "$(curl -q --proto =https --proto-redir =https -fsSL "https://github.com/proftpd/proftpd/releases/download/v$ftp/proftpd-$ftp.tar.gz.sha256" | grep -oE '^[0-9a-f]{64}')" || stack_fail
    download "https://files.phpmyadmin.net/phpMyAdmin/$pma/phpMyAdmin-$pma-all-languages.tar.xz" pma.tar.xz \
        "$(pma_sum "$pma")" || stack_fail
    IFS='|' read -r _ mariadb_url mariadb_sha <<< "$mariadb_info"
    if [ $MARIADB_SRC -eq 1 ]; then
        progress 1 2 10 "MariaDB (codigo fuente)" bytes "$build/mariadb.tar.gz" "$(remote_size "$mariadb_url")"
    else
        echo "  MariaDB $mariadb ocupa unos 450 MB, puede tardar."
        progress 1 2 10 "MariaDB (450 MB)" bytes "$build/mariadb.tar.gz" "$(remote_size "$mariadb_url")"
    fi
    download "$mariadb_url" mariadb.tar.gz "$mariadb_sha" || stack_fail

    echo "Apache $apache (con APR $apr y APR-util $aprutil)"
    tar -xjf httpd.tar.bz2 && tar -xjf apr.tar.bz2 && tar -xjf apr-util.tar.bz2 || stack_fail
    mv "apr-$apr" "httpd-$apache/srclib/apr" && mv "apr-util-$aprutil" "httpd-$apache/srclib/apr-util" || stack_fail
    cd "httpd-$apache" || stack_fail
    local pcre=$(command -v pcre2-config)
    step 2 10 15 1063 "Configurando" "$build/apache-configure.log" ./configure --prefix="$target/apache2" \
        --with-included-apr ${pcre:+--with-pcre="$pcre"} --enable-mods-shared=most \
        --enable-ssl --enable-proxy --enable-proxy-fcgi --enable-mpms-shared="event prefork" || stack_fail
    step 2 15 24 712 "Compilando" "$build/apache-make.log" make -j"$jobs" || stack_fail
    step 2 24 27 583 "Instalando" "$build/apache-install.log" make install DESTDIR="$stage" || stack_fail
    cd "$build" || stack_fail

    echo "PHP $version"
    # Las ramas antiguas llevan sus propios OpenSSL 1.1 e ICU 72 (cada uno ocupa 5 puntos de la barra)
    local php_env=() p=27
    if needs_openssl11 "$short"; then
        echo "  OpenSSL $OPENSSL11_VERSION (solo para esta version de PHP, en $target/openssl)"
        tar -xzf openssl11.tar.gz && cd "openssl-$OPENSSL11_VERSION" || stack_fail
        step 3 $p $((p + 1)) 30 "OpenSSL $OPENSSL11_VERSION: configurando" "$build/openssl11-configure.log" \
            ./config shared no-tests --prefix="$target/openssl" --openssldir="$target/openssl/ssl" \
            -Wl,-rpath,"$target/openssl/lib" || stack_fail
        step 3 $((p + 1)) $((p + 4)) 1700 "OpenSSL $OPENSSL11_VERSION: compilando" "$build/openssl11-make.log" make -j"$jobs" || stack_fail
        step 3 $((p + 4)) $((p + 5)) 300 "OpenSSL $OPENSSL11_VERSION: instalando" "$build/openssl11-install.log" \
            make install_sw DESTDIR="$stage" || stack_fail
        cd "$build" || stack_fail
        # PHP se enlaza con la copia de la carpeta temporal; al terminar, fix_php_runpath hace que
        # busque las librerias en $target/openssl/lib
        php_env+=(OPENSSL_CFLAGS="-I$S/openssl/include" OPENSSL_LIBS="-L$S/openssl/lib -lssl -lcrypto"
            LD_LIBRARY_PATH="$S/openssl/lib")
        p=$((p + 5))
    fi
    if needs_icu72 "$short"; then
        echo "  ICU 72.1 (estatico, queda dentro de PHP)"
        local deps=$build/deps
        tar -xzf icu72.tgz && cd icu/source || stack_fail
        step 3 $p $((p + 1)) 250 "ICU 72.1: configurando" "$build/icu72-configure.log" \
            env CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC" ./runConfigureICU Linux --prefix="$deps" \
            --enable-static --disable-shared --with-data-packaging=static \
            --disable-tests --disable-samples --disable-extras || stack_fail
        step 3 $((p + 1)) $((p + 4)) 900 "ICU 72.1: compilando" "$build/icu72-make.log" make -j"$jobs" || stack_fail
        step 3 $((p + 4)) $((p + 5)) 200 "ICU 72.1: instalando" "$build/icu72-install.log" make install || stack_fail
        cd "$build" || stack_fail
        # Los compiladores actuales tratan como errores avisos del codigo de las ramas antiguas
        php_env+=(ICU_CFLAGS="-I$deps/include"
            ICU_LIBS="-L$deps/lib -licui18n -licuio -licuuc -licudata -lstdc++ -lm -ldl -lpthread"
            CFLAGS="-O2 -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion"
            CXXFLAGS="-O2")
        # PHP 7.4 usa TRUE/FALSE, que ICU dejo de definir en la version 68
        [ "$short" == "7.4" ] && php_env+=(CPPFLAGS="-DU_DEFINE_FALSE_AND_TRUE=1")
        p=$((p + 5))
    fi

    tar -xJf php.tar.xz && cd "php-$version" || stack_fail
    step 3 $p $((p + 5)) 701 "Configurando" "$build/php-configure.log" env "${php_env[@]}" ./configure --prefix="$target/php" \
        --with-config-file-path="$target/php/etc" \
        --with-config-file-scan-dir="$target/php/etc/conf.d" \
        --enable-fpm --with-fpm-user="$web_user" --with-fpm-group="$web_group" --disable-cgi \
        --with-openssl --with-zlib --with-curl --with-readline --with-gettext \
        --enable-mbstring --enable-intl --enable-bcmath --enable-calendar --enable-exif --enable-ftp \
        --enable-gd --with-jpeg --with-freetype --with-webp \
        --with-zip --enable-soap --enable-sockets --with-sodium --with-password-argon2 \
        --enable-mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
        --with-mysql-sock="$target/var/mysql/mysql.sock" \
        --with-sqlite3 --with-pdo-sqlite || stack_fail
    step 3 $((p + 5)) 72 913 "Compilando (tarda unos minutos)" "$build/php-make.log" env "${php_env[@]}" make -j"$jobs" || stack_fail
    step 3 72 74 17 "Instalando" "$build/php-install.log" env "${php_env[@]}" make install INSTALL_ROOT="$stage" || stack_fail
    fix_php_runpath || stack_fail
    mkdir -p "$S/php/etc" && cp php.ini-production "$S/php/etc/php.ini" || stack_fail
    cd "$build" || stack_fail

    echo "Perl $perl"
    tar -xJf perl.tar.xz && cd "perl-$perl" || stack_fail
    step 4 74 80 948 "Configurando" "$build/perl-configure.log" sh Configure -des -Dprefix="$target/perl" \
        -Dman1dir=none -Dman3dir=none || stack_fail
    step 4 80 86 1798 "Compilando" "$build/perl-make.log" make -j"$jobs" || stack_fail
    step 4 86 89 3319 "Instalando" "$build/perl-install.log" make install DESTDIR="$stage" || stack_fail
    cd "$build" || stack_fail

    echo "ProFTPD $ftp"
    tar -xzf proftpd.tar.gz && cd "proftpd-$ftp" || stack_fail
    step 5 89 91 575 "Configurando" "$build/proftpd-configure.log" env install_user="$(id -un)" install_group="$(id -gn)" \
        ./configure --prefix="$target/proftpd" --sysconfdir="$target/etc" \
        --localstatedir="$target/var/proftpd" --enable-shadow || stack_fail
    step 5 91 92 162 "Compilando" "$build/proftpd-make.log" make -j"$jobs" || stack_fail
    step 5 92 93 50 "Instalando" "$build/proftpd-install.log" make install DESTDIR="$stage" || stack_fail
    cd "$build" || stack_fail

    if [ $MARIADB_SRC -eq 1 ]; then
        echo "MariaDB $mariadb (se compila: no hay binario oficial para $(uname -m); es lo que mas tarda)"
        tar -xzf mariadb.tar.gz && rm -f mariadb.tar.gz && cd "mariadb-$mariadb" || stack_fail
        step 6 53 55 0 "Configurando" "$build/mariadb-configure.log" cmake -S . -B build \
            -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$target/mysql" \
            -DCMAKE_INSTALL_RPATH="$target/mysql/lib" -DWITH_SSL=system -DWITH_PCRE=system \
            -DWITH_UNIT_TESTS=OFF -DWITH_WSREP=OFF -DWITH_SYSTEMD=no -DWITH_EMBEDDED_SERVER=OFF \
            -DINSTALL_MYSQLTESTDIR= -DINSTALL_SQLBENCHDIR= \
            -DPLUGIN_TOKUDB=NO -DPLUGIN_MROONGA=NO -DPLUGIN_SPIDER=NO -DPLUGIN_OQGRAPH=NO -DPLUGIN_ROCKSDB=NO \
            -DPLUGIN_CONNECT=NO -DPLUGIN_COLUMNSTORE=NO -DPLUGIN_S3=NO -DPLUGIN_AUTH_GSSAPI=NO \
            -DDEFAULT_CHARSET=utf8mb4 -DDEFAULT_COLLATION=utf8mb4_general_ci -DCOMPILATION_COMMENT="lvm-instalador" \
            || stack_fail
        step 6 55 94 0 "Compilando ($mariadb_jobs procesos, tarda bastante)" "$build/mariadb-make.log" \
            cmake --build build --parallel "$mariadb_jobs" || stack_fail
        step 6 94 96 0 "Instalando" "$build/mariadb-install.log" env DESTDIR="$stage" cmake --install build || stack_fail
        cd "$build" && rm -rf "mariadb-$mariadb" || stack_fail
    else
        echo "MariaDB $mariadb"
        mkdir -p "$S/mysql"
        step 6 93 96 0 "Descomprimiendo" "$build/mariadb-extract.log" tar -xzf mariadb.tar.gz -C "$S/mysql" --strip-components=1 \
            --exclude='*/mariadb-test' --exclude='*/mysql-test' --exclude='*/sql-bench' || stack_fail
        rm -f mariadb.tar.gz
    fi
    # Sin simbolos de depuracion ocupa unos 600 MB menos
    find "$S/mysql/bin" "$S/mysql/lib" -type f \( -perm -u+x -o -name '*.so*' \) \
        -exec strip --strip-unneeded {} + > /dev/null 2>&1
    local libs=$(ldd "$S/mysql/bin/mariadbd" "$S/mysql/bin/mariadb" 2> /dev/null | grep 'not found' | sort -u)
    if [ -n "$libs" ]; then
        echo "  Faltan librerias del sistema para MariaDB:"
        echo "$libs" | sed 's/^\s*/    /'
        stack_fail
    fi

    echo "phpMyAdmin $pma"
    progress 7 96 97 "configurando"
    tar -xJf pma.tar.xz && mv "phpMyAdmin-$pma-all-languages" "$S/phpmyadmin" || stack_fail

    echo "Configuracion"
    write_stack_files || stack_fail
    check_no_build_paths || stack_fail
    check_build_links || stack_fail

    # Copia a /opt. Si se rehace una version, la anterior se aparta hasta que todo este copiado.
    local aside="" was_running=0 links
    if [ "$replace" -eq 1 ]; then
        # Si es la version activa, se para mientras tanto y se arranca la nueva al terminar
        if [ -n "$TEST_DIR" ]; then
            "$target/lampp" status 2> /dev/null | grep -q " esta arrancado" && was_running=1
            "$target/lampp" stop > /dev/null 2>&1
        elif [ "$(active_dir)" == "$target" ]; then
            lampp_running && was_running=1
            sudo "$target/lampp" stop
        fi

        if [ $keep_data -eq 0 ] && [ -d "$target/var/mysql" ] && [ ! -L "$target/var/mysql" ]; then
            progress 7 97 98 "copia de las bases de datos"
            backup_databases "$lampp_name" "$target" || { echo "No se pudo guardar la copia de las bases de datos."; stack_fail; }
        fi

        aside=$target.anterior-$(date +%Y%m%d%H%M%S)
        echo "Apartando la version anterior en $aside..."
        $SUDO mv "$target" "$aside" || stack_fail
    fi

    echo "Copiando a $target..."
    progress 7 98 99 "copiando a $target"
    # Lo compilado es de tu usuario: se copia sin conservar el dueño (cada fichero nace de root, sin
    # un momento en que siga siendo tuyo ya en /opt) y sin setuid ni escritura para otros
    # (los enlaces se vuelven a mirar en la copia, que ya es de root: entre la primera comprobacion y
    # la copia se podria haber puesto otro)
    if ! { $SUDO mkdir -p "$target" && $SUDO cp -a --no-preserve=ownership "$S/." "$target/" \
            && $SUDO chmod -R go-w,ug-s "$target" \
            && links=$($SUDO /usr/bin/python3 -I -c "$BUILD_LINKS_PY" "$target" "$target") && [ -z "$links" ]; }; then
        $SUDO rm -rf "$target"
        [ -n "$aside" ] && $SUDO mv "$aside" "$target" && echo "Se ha dejado la version anterior como estaba."
        stack_fail
    fi

    if [ -z "$TEST_DIR" ]; then
        sudo chown -R root:root "$target"
        # Las dos carpetas que se abren a otros las crea root vacias: las copiadas venian de tu
        # carpeta, y si fueran un enlace root cambiaria el dueño y los permisos de lo que apuntan
        sudo rm -rf "$target/phpmyadmin/tmp" "$target/tmp"
        sudo install -d -o 0 -g "$web_group" -m 775 "$target/phpmyadmin/tmp"
        sudo install -d -o 0 -g 0 -m 1777 "$target/tmp"

        # htdocs y vhosts compartidos: se crean si es el primer LAMPP del equipo
        if [ ! -d /opt/htdocs ]; then
            sudo mkdir -p /opt/htdocs
            sudo chown "$web_user:$web_group" /opt/htdocs
        fi
        if [ ! -f /opt/config/httpd-vhosts.conf ]; then
            sudo mkdir -p /opt/config
            echo "# Virtual hosts compartidos por todas las versiones de lampp" | sudo tee /opt/config/httpd-vhosts.conf > /dev/null
        fi
    fi

    if [ $keep_data -eq 1 ]; then
        echo "Conservando las bases de datos (MariaDB ${old_mariadb} -> $mariadb)..."
        $SUDO mv "$aside/var/mysql" "$target/var/mysql" || stack_fail
    else
        progress 7 99 100 "creando las bases de datos"
        init_stack_databases "$target" || stack_fail
    fi

    echo "Comprobando la configuracion..."
    $SUDO "$target/apache2/bin/httpd" -t -f "$target/etc/httpd.conf" 2>&1 | sed 's/^/  Apache: /'
    $SUDO "$target/php/sbin/php-fpm" -t --fpm-config "$target/php/etc/php-fpm.conf" 2>&1 | sed 's/^.*NOTICE: /  PHP-FPM: /'
    $SUDO "$target/proftpd/sbin/proftpd" -t -c "$target/etc/proftpd.conf" 2>&1 | grep -iv '^checking' | sed 's/^/  ProFTPD: /'

    # Evita que "apt autoremove" desinstale librerias que usa esta pila
    if [ -z "$TEST_DIR" ]; then
        local pkgs=$(ldd "$target/php/sbin/php-fpm" "$target/apache2/bin/httpd" "$target/apache2/modules/"*.so \
            "$target/proftpd/sbin/proftpd" "$target/mysql/bin/mariadbd" 2> /dev/null | awk '/=> \//{print $3}' | sort -u \
            | while read -r lib; do
                dpkg -S "$lib" 2> /dev/null || dpkg -S "${lib#/usr}" 2> /dev/null || dpkg -S "/usr$lib" 2> /dev/null
            done | cut -d: -f1 | sort -u)
        [ -n "$pkgs" ] && sudo apt-mark manual $pkgs > /dev/null
    fi

    [ -n "$aside" ] && $SUDO rm -R --one-file-system "$aside"
    rm -rf "$build"

    if [ $was_running -eq 1 ]; then
        $SUDO "$target/lampp" start
    fi

    echo ""
    echo "lampp-$lampp_name instalada en $target"
    [ "$replace" -eq 1 ] && [ $keep_data -eq 0 ] && echo "Empieza con bases de datos vacias; la copia de las anteriores esta en ~/lvm-copias"
    [ "$replace" -eq 1 ] && [ $keep_data -eq 1 ] && echo "Conserva sus bases de datos"
    [ $was_running -eq 0 ] && echo "Para usarla: lvm-instalador use $lampp_name"

    return 0
}

# ===========================================================================
# Ejecucion de un plan de instalacion
# ===========================================================================

# Nombre de un elemento del plan de instalacion
function plan_label() {
    local name=${1#*:}

    case "${1%%:*}" in
        xampp) echo "XAMPP $name" ;;
        php) echo "PHP ${name%.*} (pila propia)" ;;
        parche) echo "PHP $name (pila propia)" ;;
        rehacer) echo "PHP ${name%.*} (actualizar)" ;;
    esac
}

# Instala un elemento del plan (en un subproceso: las funciones de instalacion usan exit)
function run_plan_item() {
    case "${1%%:*}" in
        xampp) ( install_xampp "${1#*:}" ) ;;
        php) ( install_stack "${1#*:}" ) ;;
        parche) ( install_stack "${1#*:}" 0 "${1#*:}" ) ;;
        rehacer) ( install_stack "${1#*:}" 1 ) ;;
    esac
}

function fmt_minutes() {
    if [ "$1" -lt 60 ]; then
        echo "menos de 1 min"
    else
        echo "$(( ($1 + 30) / 60 )) min"
    fi
}

# Pantalla de la barra de progreso (protocolo de whiptail --gauge) a partir de $PROGRESS
function progress_screen() {
    local info=$(grep '^I|' "$PROGRESS" | tail -1)
    [ -z "$info" ] && return 0

    local k n label started
    IFS='|' read -r _ k n label started <<< "$info"

    # Solo cuentan las lineas escritas desde que empezo esta version
    local section=$(awk '/^I\|/ {buf = ""} {buf = buf $0 "\n"} END {printf "%s", buf}' "$PROGRESS")
    local parts=$(grep '^C|' <<< "$section" | tail -1 | cut -d'|' -f2)
    local step=$(grep '^S|' <<< "$section" | tail -1)
    local pct=0 cur=0 what="" from to mode file total t0 done=0 frac=0

    if [ -n "$step" ]; then
        IFS='|' read -r _ cur from to what mode file total t0 <<< "$step"
        case "$mode" in
            lines) done=$(wc -l < "$file" 2> /dev/null) ;;
            bytes) done=$(stat -c %s "$file" 2> /dev/null) ;;
            time) done=$(( $(date +%s) - t0 )) ;;
            percent) done=$(tail -n 40 "$file" 2> /dev/null | grep -oE '^\[ *[0-9]+%\]' | tail -1 | tr -dc '0-9') ;;
        esac
        if [ -n "$mode" ] && [ "${total:-0}" -gt 0 ]; then
            frac=$(( ${done:-0} * 1000 / total ))
            (( frac > 990 )) && frac=990
        fi
        pct=$(( from + (to - from) * frac / 1000 ))
    fi
    grep -q '^R|' <<< "$section" && pct=100 && cur=999

    local text="Instalando $k de $n: $label\n\n" i=1 part list
    IFS=';' read -r -a list <<< "$parts"
    for part in "${list[@]}"; do
        if (( i < cur )); then
            text+="  [x] $part\n"
        elif (( i == cur )); then
            text+="  [>] $part: $what\n"
        else
            text+="  [ ] $part\n"
        fi
        i=$(( i + 1 ))
    done

    local elapsed=$(( $(date +%s) - started ))
    text+="\nTiempo: $(fmt_minutes $elapsed)"
    if (( pct >= 5 && pct < 100 )); then
        local left=$(( elapsed * (100 - pct) / pct ))
        if (( left < 60 )); then text+="   Queda menos de 1 min"; else text+="   Quedan unos $(fmt_minutes $left)"; fi
    fi
    (( n > 1 )) && text+="\nTotal de la instalacion: $(( ((k - 1) * 100 + pct) / n ))%"

    printf 'XXX\n%d\n%s\nXXX\n' "$pct" "$text"
}

# Barra de progreso mientras se instala en segundo plano (proceso <pid>)
function progress_gauge() {
    local job=$1
    local rows=$(tput lines 2> /dev/null || echo 24)
    local text_lines=12
    (( text_lines + 6 > rows - 1 )) && text_lines=$(( rows - 7 ))

    # whiptail fija el alto del texto con el texto inicial: se abre con lineas vacias
    local init=$(printf '%.0s \\n' $(seq $text_lines))

    while true; do
        local finished=0
        kill -0 "$job" 2> /dev/null || finished=1
        progress_screen
        [ $finished -eq 1 ] && break
        sleep 1
    done | wt --title "$TITLE" --gauge "$init" $(( text_lines + 6 )) 74 0
}

# install_plan "xampp:8.2.4 php:8.4.26 rehacer:8.3.35 ..."
function install_plan() {
    local items=($1) item ok=() failed=() errors=""

    mkdir -p -m 700 "$LOG_DIR"

    if [ "$DRY" -eq 0 ] && [ -z "$TEST_DIR" ]; then
        # Pide la contraseña una sola vez y la mantiene activa durante toda la instalacion
        echo "Se necesita la contraseña de administrador (sudo):"
        sudo -v || return 1
        while true; do sudo -n true; sleep 50; kill -0 "$$" 2> /dev/null || exit; done 2> /dev/null &
        local keepalive=$!
        trap "kill $keepalive 2> /dev/null" EXIT
    fi

    # Primero los XAMPP, despues las pilas propias
    items=($(printf '%s\n' "${items[@]}" | grep '^xampp:') $(printf '%s\n' "${items[@]}" | grep -v '^xampp:'))

    if [ "$UI" == "whiptail" ] && [ "$DRY" -eq 0 ]; then
        # Con ventanas: la instalacion va en segundo plano (salida al log) y se muestra la barra
        PROGRESS=$(mktemp /tmp/lvm-progreso-XXXX)
        (
            local k=0
            for item in "${items[@]}"; do
                k=$(( k + 1 ))
                echo "I|$k|${#items[@]}|$(plan_label "$item")|$(date +%s)" >> "$PROGRESS"
                echo -e "\n================ ${item/:/ } ================" >> "$LOG"
                run_plan_item "$item" < /dev/null > "$PROGRESS.$k" 2>&1
                echo "R|$item|$?" >> "$PROGRESS"
                cat "$PROGRESS.$k" >> "$LOG"
            done
        ) &
        local job=$!
        progress_gauge "$job"
        wait "$job"

        local k=0 rc
        for item in "${items[@]}"; do
            k=$(( k + 1 ))
            rc=$(grep "^R|$item|" "$PROGRESS" | cut -d'|' -f3)
            if [ "$rc" == "0" ]; then
                ok+=("$item")
            else
                failed+=("$item")
                errors+="\nUltimas lineas de ${item/:/ }:\n$(tail -6 "$PROGRESS.$k" 2> /dev/null | cut -c1-90)\n"
            fi
        done
        rm -f "$PROGRESS" "$PROGRESS".*
        PROGRESS=""
    else
        # Desde la ventana (LVM_PROGRESO=<archivo>) se escribe el mismo progreso que lee la barra
        # de whiptail, para que la ventana dibuje la suya
        [ -n "$LVM_PROGRESO" ] && PROGRESS=$LVM_PROGRESO
        local k=0 rc
        for item in "${items[@]}"; do
            k=$(( k + 1 ))
            [ -n "$PROGRESS" ] && echo "I|$k|${#items[@]}|$(plan_label "$item")|$(date +%s)" >> "$PROGRESS"
            echo ""
            echo "================ ${item/:/ } ================" | tee -a "$LOG"

            run_plan_item "$item" 2>&1 | tee -a "$LOG"
            rc=$?
            [ -n "$PROGRESS" ] && echo "R|$item|$rc" >> "$PROGRESS"

            if [ $rc -eq 0 ]; then ok+=("$item"); else failed+=("$item"); fi
        done
        PROGRESS=""
    fi

    local summary="Resultado de la instalacion:\n\n"
    for item in "${ok[@]}"; do
        local name=$(item_folder "$item")
        summary+="  OK     ${item/:/ }  ->  activar con: lvm-instalador use $name\n"
    done
    for item in "${failed[@]}"; do
        summary+="  ERROR  ${item/:/ }  (no se ha instalado nada; revisa el log)\n"
    done
    summary+="$errors\nLog completo: $LOG"
    [ "$DRY" -eq 1 ] && summary+="\n\nSIMULACION: no se ha hecho ningun cambio."

    echo -e "\n$summary" >> "$LOG"
    ui_msg "$summary"

    [ ${#failed[@]} -eq 0 ]
}

function check_space() {
    local needed=$1
    local free=$(df --output=avail -BG /opt | tail -1 | tr -dc '0-9')

    if [ "$free" -lt "$(( needed + 2 ))" ]; then
        ui_msg "Espacio insuficiente en /opt: hay ${free}G libres y se necesitan unos ${needed}G (+2G de margen)."

        return 1
    fi
}

function other_lvm_running() {
    pgrep -f "^(/usr)?/bin/bash (/opt/tools/lampp-vm.sh|/usr/bin/lvm)( |$)" > /dev/null
}

# ===========================================================================
# Panel
# ===========================================================================

# Elige un parche concreto de PHP: primero la rama y despues la version. Escribe el elemento
# del plan (php: o parche:) o devuelve 1 si se cancela.
function panel_pick_patch() {
    local releases=$1 supported=$2 items=() branch full version date latest
    local widths="10 16 16" states=$(php_branch_states)

    while read -r branch full; do
        [ -z "$branch" ] && continue
        local state=$(branch_state_text "$branch" "$states" "$supported")
        items+=("$branch" "$(fmt_row "$widths" "PHP $branch" "$full" "$state")")
    done <<< "$releases"

    while true; do
        branch=$(ui_table_menu "Elige la rama de PHP de la version que necesitas." "" \
            "$(fmt_row "$widths" "Rama" "Ultimo parche" "php.net")" "${items[@]}") || return 1
        latest=$(awk -v b="$branch" '$1 == b {print $2}' <<< "$releases")

        local patches=() item note dir installed=""
        for dir in $(lampp_dirs); do is_fpm_install "$dir" && installed+="$(php_version "$dir")"$'\n'; done
        while read -r version date sec; do
            [ -z "$version" ] && continue
            item=$(php_item "$version" "$latest")
            [ -e "/opt/lampp-$(item_folder "$item")" ] && continue
            grep -qxF "$version" <<< "$installed" && continue
            note="/opt/lampp-$(item_folder "$item")"
            [ "$version" == "$latest" ] && note+=" (ultimo)"
            [ "$sec" == "seguridad" ] && note+=" [seguridad]"
            patches+=("$version" "$(fmt_row "10 13 30" "$version" "$date" "$note")")
        done <<< "$(php_patches "$branch")"

        if [ ${#patches[@]} -eq 0 ]; then
            ui_msg "Ya tienes instaladas todas las versiones de PHP $branch."
            continue
        fi

        local text="Versiones publicadas de PHP $branch, de la mas nueva a la mas antigua.\n"
        text+="El ultimo parche va en /opt/lampp-$branch y los demas en su propia carpeta\n"
        text+="(/opt/lampp-$branch.Z), asi que pueden convivir varios. Todas llevan la misma\n"
        text+="pila (Apache, MariaDB, ProFTPD y Perl) y sus propias bases de datos.\n"
        text+="Los parches antiguos tienen fallos de seguridad ya corregidos: usalos solo\n"
        text+="si el proyecto necesita esa version exacta."
        version=$(ui_table_menu "$text" "" "$(fmt_row "10 13 30" "Version" "Publicada" "Carpeta")" "${patches[@]}") || continue

        php_item "$version" "$latest"

        return 0
    done
}

function panel_install() {
    local releases=$(php_releases) supported=$(php_supported)
    local items=() entry folder release php apache mariadb ftp perl pma md5 sha branch full f
    local widths="14 8 8 9 9 8 10"
    local header=$(fmt_row "$widths" "Instalar" "PHP" "Apache" "MariaDB" "ProFTPD" "Perl" "phpMyAdmin")

    for entry in "${XAMPP_CATALOG[@]}"; do
        IFS='|' read -r folder release php apache mariadb ftp perl pma md5 sha <<< "$entry"
        [ -e "/opt/lampp-$folder" ] && continue
        native_binaries || continue
        items+=("xampp:$folder" "$(fmt_row "$widths" "XAMPP $folder" "$php" "$apache" "$mariadb" "$ftp" "$perl" "$pma")")
    done

    if [ -z "$releases" ]; then
        ui_msg "No se pudo consultar php.net: solo se muestran las versiones de XAMPP."
    fi

    [ "$UI" == "whiptail" ] && [ -n "$releases" ] && clear && echo "Consultando las ultimas versiones de cada componente..."
    local old_branches=0 security_branches=0 states=$(php_branch_states)
    while read -r branch full; do
        [ -z "$branch" ] && continue
        # Si la carpeta de la rama ya es una pila propia, se pone al dia con "Actualizar". Si es un
        # XAMPP (por ejemplo lampp-7.4), el ultimo parche se instala a su lado, en lampp-X.Y.Z.
        is_fpm_install "/opt/lampp-$branch" && continue
        local item=$(php_item "$full" "$full")
        [ -e "/opt/lampp-$(item_folder "$item")" ] && continue
        php_installed_in "$full" > /dev/null && continue
        IFS='|' read -r -a f <<< "$(stack_versions "$full")"
        local label="PHP $(item_folder "$item")"
        case "$(branch_state_text "$branch" "$states" "$supported")" in
            "sin soporte") label+=" *"; old_branches=1 ;;
            "solo seguridad") label+=" +"; security_branches=1 ;;
        esac
        items+=("$item" "$(fmt_row "$widths" "$label" "${f[@]}")")
    done <<< "$releases"
    [ -n "$releases" ] && items+=("otro" "$(fmt_row "$widths" "Otro parche" "elegir una version concreta de PHP...")")

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "Ya tienes instaladas todas las versiones disponibles."

        return 0
    fi

    local text="Versiones que puedes instalar (las que ya tienes no aparecen).\n"
    native_binaries || text+="Este equipo es $(uname -m): no hay XAMPP y MariaDB se compila (tarda mas).\n"
    text+="XAMPP: paquete oficial completo, para proyectos antiguos.\n"
    text+="PHP:   pila propia sin XAMPP, con el ultimo parche de la rama. Se compila.\n"
    [ $security_branches -eq 1 ] && text+="       + Rama con solo parches de seguridad (sin correcciones de errores). Las demas son estables.\n"
    [ $old_branches -eq 1 ] && text+="       * Rama sin soporte de php.net: solo para proyectos antiguos.\n"
    text+="Otro parche: una version concreta (p. ej. 8.3.10) en su propia carpeta.\n"
    text+="Las versiones de PHP tienen sus propias bases de datos, vacias."

    local selected
    while true; do
        selected=$(ui_table_checklist "$text" "$header" "${items[@]}") || return 0
        selected=$(echo $selected)

        # "Otro parche": se elige la version y se suma a las marcadas
        if [[ " $selected " == *" otro "* ]]; then
            local patch
            selected=$(echo " $selected " | sed 's/ otro / /')
            patch=$(panel_pick_patch "$releases" "$supported") || continue
            [[ " $selected " == *" $patch "* ]] || selected+=" $patch"
            selected=$(echo $selected)
        fi

        [ -n "$selected" ] && break

        # Aceptar sin marcar nada: la fila resaltada no cuenta, hay que marcarla con Espacio
        ui_msg "No has marcado ninguna version.\n\nMuevete con las flechas hasta la version y pulsa Espacio para marcarla\n(aparece [*] a su izquierda). Despues pulsa Intro para aceptar."
    done

    local xampp_selected=$(printf '%s\n' $selected | grep '^xampp:' | sed 's/^xampp://')
    local php_selected=$(printf '%s\n' $selected | grep -E '^(php|parche):')

    # Resumen
    local n_xampp=$(printf '%s\n' $xampp_selected | grep -c .)
    local n_php=$(printf '%s\n' $php_selected | grep -c .)
    local needed=$(( n_xampp * SPACE_XAMPP_GB + n_php * SPACE_STACK_GB ))
    local summary="Se va a instalar:\n\n" item
    summary+="$header\n$(printf '%*s' ${#header} "" | tr ' ' '-')\n"

    for item in $xampp_selected; do
        IFS='|' read -r -a f <<< "$(xampp_fields "$item")"
        summary+="$(fmt_row "$widths" "XAMPP $item" "${f[@]}")\n"
    done
    for item in $php_selected; do
        full=${item#*:}
        IFS='|' read -r -a f <<< "$(stack_versions "$full")"
        summary+="$(fmt_row "$widths" "PHP $(item_folder "$item")" "${f[@]}")\n"
    done

    summary+="\nCarpetas:"
    for item in $xampp_selected; do summary+=" /opt/lampp-$item"; done
    for item in $php_selected; do summary+=" /opt/lampp-$(item_folder "$item")"; done
    summary+="\n"
    [ -n "$php_selected" ] && summary+="Las versiones de PHP se compilan y tienen bases de datos propias y vacias.\n"

    summary+="\nEspacio aproximado: ${needed}G\n"

    if [ -n "$xampp_selected" ] && [ -n "$(active_dir)" ]; then
        summary+="\nAVISO: el instalador de XAMPP necesita /opt/lampp, asi que la version\n"
        summary+="activa (lampp-$(active_dir | sed "s|^/opt/lampp-||")) se parara durante la instalacion de XAMPP\n"
        summary+="y se volvera a activar al terminar. Las versiones de PHP no la paran.\n"
    fi

    summary+="\nLa version activa no cambia. Las nuevas se activan con\n'Cambiar la version activa'."
    [ "$DRY" -eq 1 ] && summary+="\n\nSIMULACION: no se hara ningun cambio."
    summary+="\n\n¿Instalar?"

    check_space "$needed" || return 0

    if other_lvm_running; then
        ui_msg "Hay otra ejecucion de lvm en marcha. Espera a que termine."

        return 0
    fi

    ui_yesno "$summary" || return 0

    [ "$UI" == "whiptail" ] && clear
    install_plan "$selected"

    [ "$DRY" -eq 1 ] && return 0
    ui_yesno "¿Quieres activar ahora alguna de las versiones?" && panel_use
    return 0
}

function panel_use() {
    local items=() dir active=$(active_dir)

    for dir in $(lampp_dirs); do
        local mark=""
        [ "$dir" == "$active" ] && mark="activa"
        items+=("${dir#/opt/lampp-}" "$(stack_row "$dir" "$mark")")
    done

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "No hay versiones instaladas."

        return 0
    fi

    local version
    version=$(ui_table_menu "Elige la version que quieres activar.\nSe parara la version activa y se arrancara la elegida." \
        "${active#/opt/lampp-}" "$(stack_header "Estado")" "${items[@]}") || return 0

    if [ "/opt/lampp-$version" == "$active" ]; then
        ui_yesno "lampp-$version ya es la version activa. ¿Reiniciarla?" || return 0
        [ "$UI" == "whiptail" ] && clear
        control_lampp restart
    else
        [ "$UI" == "whiptail" ] && clear
        use_lampp "$version"
    fi

    [ -t 0 ] && read -p "Pulsa Intro para volver al panel... " _
}

function panel_register() {
    local name
    name=$(ui_input "Hay un XAMPP sin registrar en /opt/lampp.\nNombre de la version (p. ej. 8.2.12):" \
        "$(readlink /opt/lampp/bin/php 2> /dev/null | sed -n 's|^php-||p')") || return 0

    [ -z "$name" ] && return 0
    [ "$UI" == "whiptail" ] && clear
    register_lampp "$name"
    [ -t 0 ] && read -p "Pulsa Intro para volver al panel... " _
}

function panel_databases() {
    local items=() dir version owner count active=$(active_dir)
    local widths="10 12 30"

    for dir in $(lampp_dirs); do
        version=${dir#/opt/lampp-}
        owner=$(data_owner "$dir")
        count=$(db_names "/opt/lampp-${owner:-$version}" | grep -c .)

        local data="propias"
        [ -n "$owner" ] && [ "$owner" != "$version" ] && data="las de lampp-$owner"
        [ "$dir" == "$active" ] && data+=" (activa)"

        items+=("$version" "$(fmt_row "$widths" "$version" "$count" "$data")")
    done
    version=""

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "No hay versiones instaladas."

        return 0
    fi

    while true; do
        version=$(ui_table_menu "Elige una version para ver sus bases de datos." "${version:-${active#/opt/lampp-}}" \
            "$(fmt_row "$widths" "Version" "BBDD" "De quien son")" "${items[@]}") || return 0

        local cols=$(tput cols 2> /dev/null || echo 80)
        ui_msg "$(databases_text "$version" $(( (cols > 110 ? 110 : cols) - 8 )))"
    done
}

# Ultima version de PHP de la rama de una instalacion (vacio si la rama ya no tiene soporte)
function rebuild_version() {
    local dir=$1 releases=$2
    local php=$(stack_fields "$dir" | cut -d'|' -f1)

    awk -v b="${php%.*}" '$1 == b {print $2}' <<< "$releases"
}

# Rehace una version de PHP nueva con la ultima pila de su rama: actualiza los parches de una
# pila propia o pasa a pila propia una version antigua copiada de un XAMPP
function panel_rebuild() {
    local releases=$(php_releases) items=() dir version full f state

    if [ -z "$releases" ]; then
        ui_msg "No se pudo consultar php.net. Comprueba la conexion a internet."

        return 0
    fi

    [ "$UI" == "whiptail" ] && clear && echo "Consultando las ultimas versiones de cada componente..."
    for dir in $(lampp_dirs); do
        is_fpm_install "$dir" || continue
        full=$(rebuild_version "$dir" "$releases")
        [ -z "$full" ] || [ "$dir" != "/opt/lampp-${full%.*}" ] && continue

        local new=$(stack_versions "$full")
        if ! is_stack_install "$dir"; then
            state="sobre XAMPP"
        elif [ "$(stack_fields "$dir")" == "$new" ]; then
            state="al dia"
        else
            state="actualizable"
        fi

        IFS='|' read -r -a f <<< "$new"
        items+=("${dir#/opt/lampp-}" "$(fmt_row "$STACK_WIDTHS" "${dir#/opt/lampp-}" "${f[@]}" "$state")")
    done

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "No hay versiones de PHP nuevas que se puedan actualizar (los XAMPP y las versiones\ncon un parche concreto, como lampp-8.3.10, no se actualizan)."

        return 0
    fi

    local text="Elige la version que quieres actualizar. Se muestra la pila con la que quedara:\n"
    text+="la ultima de su rama de PHP. 'actualizable' = hay parches nuevos;\n"
    text+="'sobre XAMPP' = version antigua que pasara a tener su pila propia;\n"
    text+="'al dia' = ya tiene todos los paquetes en su ultima version."
    local new
    while true; do
        version=$(ui_table_menu "$text" "$version" "$(stack_header "Estado")" "${items[@]}") || return 0
        dir=/opt/lampp-$version
        full=$(rebuild_version "$dir" "$releases")
        new=$(stack_versions "$full")

        # Con todos los paquetes al dia no hay nada que actualizar: se avisa y se vuelve a la lista
        if is_stack_install "$dir" && [ "$(stack_fields "$dir")" == "$new" ]; then
            ui_up_to_date "lampp-$version"
            continue
        fi
        break
    done

    local old_mariadb=$(stack_fields "$dir" | cut -d'|' -f3) new_mariadb=$(cut -d'|' -f3 <<< "$new")
    IFS='|' read -r -a f <<< "$new"

    local header=$(stack_header "")
    local summary="lampp-$version se volvera a compilar con la ultima pila de PHP ${full%.*}:\n\n"
    summary+="$header\n$(printf '%*s' ${#header} "" | tr ' ' '-')\n"
    summary+="$(stack_row "$dir" "" "Ahora")\n"
    summary+="$(fmt_row "$STACK_WIDTHS" "Despues" "${f[@]}" "")\n\n"

    if is_stack_install "$dir" && [ "${old_mariadb%.*}" == "${new_mariadb%.*}" ]; then
        summary+="Conserva sus bases de datos (misma rama de MariaDB, ${new_mariadb%.*}).\n"
    elif [ -L "$dir/var/mysql" ]; then
        summary+="Ahora usa las bases de datos de lampp-$(data_owner "$dir"), que no se tocan.\n"
        summary+="La nueva version empezara con bases de datos propias y vacias.\n"
    else
        local count=$(db_names "$dir" | grep -c .)
        summary+="MariaDB $new_mariadb no usa directamente los datos de MariaDB $old_mariadb, asi que\n"
        summary+="la nueva version empezara con bases de datos vacias. Antes se guarda una\n"
        summary+="copia de las actuales ($count) en ~/lvm-copias/. Para llevarte alguna, exportala\n"
        summary+="antes desde phpMyAdmin e importala despues.\n"
    fi

    summary+="\nLa compilacion tarda 10-20 minutos y mientras tanto la version actual sigue\n"
    summary+="como esta. Solo al final se sustituye"
    if [ "$(active_dir)" == "$dir" ]; then
        summary+=": como es la version activa, se parara\nunos segundos y se arrancara la nueva.\n"
    else
        summary+=".\n"
    fi
    summary+="Los proyectos de /opt/htdocs y los vhosts de /opt/config no se tocan."
    [ "$DRY" -eq 1 ] && summary+="\n\nSIMULACION: no se hara ningun cambio."
    summary+="\n\n¿Actualizar lampp-$version?"

    check_space "$SPACE_STACK_GB" || return 0

    if other_lvm_running; then
        ui_msg "Hay otra ejecucion de lvm en marcha. Espera a que termine."

        return 0
    fi

    ui_yesno "$summary" || return 0

    [ "$UI" == "whiptail" ] && clear
    install_plan "rehacer:$full"
}

# ui_up_to_date lampp-X.Y: aviso en verde de que la version ya tiene todos los paquetes al dia
function ui_up_to_date() {
    local message="El paquete $1 se encuentra actualizado."

    if [ "$UI" == "whiptail" ]; then
        WT_GREEN=$message ui_msg "$message\n\nTodos sus paquetes (PHP, Apache, MariaDB, ProFTPD, Perl y phpMyAdmin)\nestan en la ultima version de su rama: no hay nada que actualizar."
    elif [ -t 2 ]; then
        ui_msg "\033[1;32m$message\033[0m\n\nNo hay nada que actualizar."
    else
        ui_msg "$message\n\nNo hay nada que actualizar."
    fi
}

function panel_remove() {
    local items=() dir version active=$(active_dir)

    for dir in $(lampp_dirs); do
        version=${dir#/opt/lampp-}
        local mark=""
        if [ "$dir" == "$active" ]; then
            mark="activa"
        elif [ -n "$(data_users "$version")" ]; then
            mark="en uso"
        fi
        items+=("$version" "$(stack_row "$dir" "$mark")")
    done

    if [ ${#items[@]} -eq 0 ]; then
        ui_msg "No hay versiones instaladas."

        return 0
    fi

    local text="Elige la version que quieres desinstalar.\n"
    text+="No se puede desinstalar la version activa ni una cuyas bases de datos usen otras ('en uso')."
    version=$(ui_table_menu "$text" "" "$(stack_header "Estado")" "${items[@]}") || return 0
    dir=/opt/lampp-$version

    local blocker=$(remove_blocker "$version")
    if [ -n "$blocker" ]; then
        ui_msg "$blocker"

        return 0
    fi

    local fields
    IFS='|' read -r -a fields <<< "$(stack_fields "$dir")"

    local summary="Se va a desinstalar lampp-$version (PHP ${fields[0]}) y se borrara la carpeta $dir.\n\n"
    local own_dbs=0 names=""

    if [ "$(data_owner "$dir")" != "$version" ]; then
        summary+="Sus bases de datos NO se tocan: son las de lampp-$(data_owner "$dir"), que sigue instalada.\n"
    else
        names=$(db_names "$dir")
        own_dbs=$(grep -c . <<< "$names")
        if [ "$own_dbs" -gt 0 ]; then
            summary+="ATENCION: sus bases de datos propias ($own_dbs) se BORRARAN con ella:\n\n"
            summary+="$(columns 66 <<< "$names")\n\n"
            summary+="Antes de borrar podras guardar una copia de todas ellas.\n"
        else
            summary+="No tiene bases de datos propias (aparte de las del sistema).\n"
        fi
    fi

    summary+="\nLos proyectos de /opt/htdocs y los vhosts de /opt/config no se tocan."
    [ "$DRY" -eq 1 ] && summary+="\n\nSIMULACION: no se hara ningun cambio."
    summary+="\n\n¿Desinstalar lampp-$version?"

    ui_yesno "$summary" || return 0

    local backup=0
    if [ "$own_dbs" -gt 0 ]; then
        ui_yesno "¿Guardar antes una copia comprimida de las bases de datos de lampp-$version?\n\nSe guardara en ~/lvm-copias/ (se necesita espacio libre en tu carpeta personal)." && backup=1

        # Sin copia, se pide escribir el nombre de la version para confirmar
        if [ $backup -eq 0 ]; then
            local typed
            typed=$(ui_input "Se borraran sus bases de datos ($own_dbs) SIN copia y no se podran recuperar.\n\nEscribe $version para confirmar:" "") || return 0
            if [ "$typed" != "$version" ]; then
                ui_msg "No coincide. No se ha desinstalado nada."

                return 0
            fi
        fi
    fi

    [ "$UI" == "whiptail" ] && clear

    if [ "$DRY" -eq 0 ]; then
        echo "Se necesita la contraseña de administrador (sudo):"
        sudo -v || return 0
    fi

    local ok=1
    [ $backup -eq 1 ] && ! remove_backup "$version" && ok=0

    [ $ok -eq 1 ] && remove_lampp "$version"

    [ -t 0 ] && read -p "Pulsa Intro para volver al panel... " _
}

# Icono del acceso del menu (PNG 256x256 incrustado, para que el instalador siga siendo un solo archivo).
# Lleva el nombre de la aplicacion para que GNOME no siga mostrando el icono antiguo de su cache
ICON_FILE="$HOME/.local/share/icons/lampp-version-manager.png"
OLD_ICON_FILES=("$HOME/.local/share/icons/lvm-instalador.png" "$HOME/.local/share/icons/php-version-loader.png"
    "$HOME/.local/share/icons/php-version-manager.png")
ICON_PNG_B64='
iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAYAAABccqhmAAA+40lEQVR42u19eZxcVZX/99z7ltq6k+6kE0KAIGKEBBUExUEkiYo6
ihCWLh30hxvLkAUHHWdQx6mu0dFxB7IoOOKGOnYhYXEfNR1RdkSQNMO+GEhIeknSXctb7j2/P15VL0kn6U56q6r75dOf0N1V/eq9
e8/3fM+5554LGBgYGBgYGBgYGBjUEcg8gtoZSy7/Txsy1AYgh07ajO20FEsBAI9jKy3EvMrLsAOdjNZWtFZ+0Apgcws9sPVxOnne
Qu5ABwBgaedizgHYvGgzt2XbGKDKxGHz2A0BGEyykbchQ4vRSS1YRB0A2tCmaND+Jw3MTB1tbRJYiqWdOxiLNjMGCcKQgyEAg0Mz
dkYOadGCRbQU0ISs3t8bNi74QGxHb3PCcvzZkqhFBdxEEo0ENDKQAlOciGIMHYfWINe25p31yqR0LY9YawY0kehjQomZfR3oIoe6
X2vuE+BuVmprmHK3ya5i6de53V52P5+HMyyADpHr3MGt7a0aZEjBEIDBvr0pQG3I0FJA7EAnp5FTe74mg4w4tbknFWg6moV6OQQd
TQoLtMB8Ah9OoMM1YxYRuwA5FgQkCUgICBAERSbIkfuGcCXmtZ4A6VoAMwgAUTQlWDMUayitobRCoBWYdcBAEcy7dMjbifAiET3J
Sm1hX73ALB5LJvFk5/pNxZE+P2dYdKBNLAU0slk2hGAIoK6ffaZs8B2A3tObtqNV2k2zDwfsV0HoEwhYxODjCfRyADNsSMshCwIE
BR19MYPB0ODyf2ACM0DMYK6ECVz+sXAkDj9nMYQjAS5fnsqhBIOYmMrRPgEQRBGJCBKQIiIXS1jQWsMLffgqUAz0INR/IyH+qrTa
rHz1GIfWA1vu37Yj3Zn1hxNCRnSU77/NEIIhgHrw8jm0CgDY00O2H3Fl3Cn6i5nxd5LEqxTrUwB6pUUiEScbDCCEQsgaGgwNzQBU
NIhEDCaK7JaGDCztJ4CHcCTmLV9UJoAD2h5XmCEyU2IQM/HAJQURCUkCUko4wgIBKPgeAh0WdKieF5B3KR0+KH39Jz/vP3pa7uPF
YSFMJmPt6FzMrbm0NmRgCKCmjL4Vi3hoDH8dLrXnNruvYOKlkvEmRXwagY5IkCsEAB8KISsoMANcIQsxKNIPcezGTgCjuVeO/g4x
ARoAmCAlCbKkRMyyobRG3i8prfUWoelPSqk7uaQ7Cs/teGzZpmw4LIfQmSPkWvVUJDgNARgc0nNtH8HT/6J5daPP/CYI/VaGOFOA
FsbItgUIHodQUGBARXIdgiNjn5gxmgAC2DcxMBMTA9BMTIKEtIREzHKgtUY+KPkcqscI+JVfCjaW+sUdy3Kr+gfUUWu7BIB0Lq1h
lIEhgOmKDDJiKSCWYdCT/WzG5U1KWGeS4Ldr8NtsWEe4ZMGHQsAKDFaI4nUxJN6eBGkyeQQw4tWZQSAFYiIS0pE2XGmhEHgIgvBF
MP9K++rnuhT+9g0//OjuoWFCB6Cz2f2viBgYAphkid8+IFWvwWr32Nl0ZqjV2Rp0VkxY8yxIeBwggGaAFZXl/JSNwdQSwAihA5gA
zQTpSItilgM/DFD0vG0A30ZBeDMe/OvvT3ng+qDMIJRL54RRBYYApmjSMuWQFkMl/k2zVh1nMd5DhLRFcpELCyUOEEJpjmJiSaDp
8cynEQGMJA8IpJi4TAYuSpEy+KsOud3LF3On//DKx4aqgqXZqSmGMgRQhzJ/MTqpYvjfwQdis5pT7yKSF4ZQ70pRzA2g4HFQydJP
H6OvEgLYFxnELJccaWFXsd+TTD/nQP3oqZ0v3Z7ORcuL3Nou2xZtZhMeGAKYAI+fEW0AKuv17S0rDrO1/IAEPmyTXCghUOQAGjos
y3sxvW+oOghgj4+sCdBCkBW3Y1BawfP9R8Ig/HawI/+jN274xHYgqi8AADJEYAhgPDw+hhj+rU0rFiuIiyXRhQnhzPERIuBQl8v0
RdU80yokgGE5A7AGE8VsWzjCQl+p8JJS6nt+n3dDJTwwRGAIYNwMf0PT6tMkYZUmPjdFbqzIARS0ApimvbevMQLYUxUAzLZlybjl
YncxX9SKc/C9q19/w0cfBKJlxM0mNDAEMDrvwgS0UaVoZ8PsK04mVp8A6D1JclFgHxo6nLaxfZ0RwJ65AiGFlbBd9JcKoQ70j5Uf
fPUN37nioQoRtJrCIkMA+3oW7WgdyOpvaFlxIinxMSJcGCdHFtgHwCFAsiaeW40RwBACZ2JSJMhKOjH0FQs+lPqBKpS+fur3P7YZ
iJKFZJYPDQFU0I5WWTH8m2auWGAJ8SkQfShBtl1kHwyEAGRNPa8aJYCheQJiKBJkpZw4+kqFPAfqm309fV9ZlvuXbRVFkM6llSGA
Oo7z2xDtQvvOgg/EZvc3rAToX1xy5hTZq03DrxMC2JMIhBBW0okhXyptUUHwhduvu/ybWUBzJiPQ1sZE9RkW1C0BDPX6t85afY4E
ZVyyTyoX7iiABNXy86kTAhgaGoChHcuWrrRRLHl3+77/H6//1opfDgkLlCGAOjD8VuQ0AXxz8+XHS7K+7JB8FwB4HCoGi6pO7hkC
OMBtM4Og47YrtdLwfO9HfT2lTy/7yZXPMjOhrY3qadlQ1Jvxp5FTBPDtzav/ySbrzhjZ7ypxoEscTK9SXYOJ8XhERCBZ9D3tqYAb
kqkLm+ak7nrg8m9eSkRM2ayu7D40CqBm5F9GELIMgH/aePnrbMv6SkzYZ5Q4hI7kvqw7S6hTBTCCIlC2ZUtXWMiXSr/M9xeuOuP7
//RwplxEVOu1AzVPABWv345WGZ91+GcA/UmbLKfIgUK9yH1DAKMKC1JOQpaC0m5VUtmTr//HrwHAxiUZa2ijEkMAVeP1Bwt62ptX
L3IJ30yQ86YC++U9+JCoZxgCGFENSCllwnLRX8z/rH933xVLbvzEM5zJCGTbuBYLiGoyB9COVkkgJmT1htmrL04Q/TFG1pv6uaR0
NNMlDAz2zg9IpRT3+QWVSiTPmjGz6U/3XrL+fMpmNYG4srfAKIAqkPw/mvORuUkVv9ol+70Bq3LdvjF8owDGlhuwQCiWvOv6Ht36
z8s2Zfu5vV1SunaWC2uG0Tgq5ZVp5NTNzate36CTG5PkvrfEgQqhjNc3GLMa8MOASyrQjanUZTNeNX/jHe/92mJKp1UtrRLUBAFk
kBGEqAHnhqaVFzuQGyXE8X1cmr4NOQymv3FEDZjF7lIhjLvuKY1zGjfe86E156ZzacUZFsxMhgCmgeTPIquvw6XWbbNWXx2Xzrc0
6YTHgaZ6XN4zmAA1ACvvlxSEaIk3Jm9+4NJvZilLmoi4vbW1qucYVbvxR17/8iMFyR8khLukwJ7S9by8Z3IAE/nINBHQ4MZFXz6/
oadr54fOzF21q5rLiEW1G3/7jBUnSmH9LiGcJf1cCtlIfoOJUwKCwaLPK4YNydS5TS1Nv73jwi8cQ7m02rgkYxkCmGTj/2nTinck
LPu3NslX9LMXEsgy09RgYiUzAYC1q9SvkvH4KQ2zZv/+Tx+8+nXLNmXDaiSBaiOAgUz/htkrL3aFfRuAWR6Hyhi/waQaDgmZ94rK
sqwFqcbUb+/98Jqzl23KhlxlKwRVQwA8pGPPLc0rPx2H8y0FbQcINcwSn8GUhAQki4GvWVCjm0psuOfitZdQLq24vXpIQFSL8bch
Q2nk1IbmlV9ICPdzHodKQzNVY0NOgxpSAiTCUGkFTclU8vq7Ll7zMUqnVXtEAtM+F0XVYPzlD8q3Nq2+Oi7tjxbZVxqo7YYdE/5g
zSrAOE9UTUSI2Y7o253/zKn/veJz5ZZj07r3oKgS48ets1Zen7CcjxbZV1Gm3xi/wbRypUKzJi/0VWNj6rP3Xbr+8+WCIeJpPFfF
dDb+NmSoDaANzSu/nxCxS/I6WuYzs81gmuYESLEWxbCkZjQ0fvK+y9Z9ibKkc63t0/bAGDFdjR/IUBZZfdKsldc3iNj787oUwmT6
Daa9ECDSzLLPL6jGVOMn7r507efSubRqn6YkMB0JgHJoFYSs3jBr5TVJin2knz1j/AbVRAJgsMgHRTUz1fjpuy5Z9+l0tDogDAEc
4NlVlvo2NK/8QopiV+TZUwCM8RtUoxIQhdBTMxpSn7v70jX/ROnpt0Q4rQgggyXl7bwrMknhXlVgL0SdNS41qDES0Fp4oa8akg1f
v/PS9RdTOq02ZqZPxeC0Ma6NyFhZbAo3NK28NClibaVoqa82D+UwqB8SIKJQa+GrUKfi7jfv/Mg1716WzYbThQSmBQFkkLGWIRve
1HTZO20h1/kcKgU26/wGNQFBREprMCCSidQP7vjANScvy06PsuEpJ4Dyfv4wN+MfT4oJ94dMkCEUmR19BrWlBCBCHWppiRnJVPzm
O/7f1UdRLq0yU9xncEoZKIOMWIX1+qfNq4+wpfiNRfKwkJVp5DFZk1IKNBzXApImzTJJT1wEKlSpWLwJkk7/8MK3/uT91/6rB0Bs
2rRpSqoFp2zkGUxtANqPuDIuidvj5CzwODCNOw1qPBwQMu8Vw8ZE8nVWg/ttIuKlgJiqasGpIgACcoKQ1XbBvyZJ7t/lo/38xvgN
6iEesHaX+sPGVOqCuz6y9jPLstmwI5ORdUMAG7FEEtLq5lkrLk8K95I8l5QxfoN6AgOy4JfCVCrRds/Fa85als2G7VNQIzDpBNCO
VrkMm8Kbm1ac7sD+WnQiL6ZtrbSBwcRI4Gh5kInJicW+2/EPV78inU6ryT58ZFIvlkFGpJHTP2tZcZgU4oeCEDMZf4P6jQQgvCDk
mOvOamiO33j/pZkEAExmu/FJIwAGaDE6CQCHSlyfIPeocisvk4I2qFsIQaIQJQVfrzDni5TN6lwuJ2qOANrKZb4bmleuTgj33f0m
7jcwqEgB2ecVVDKRWHX3xWvPSU/i6UOTQgCMjMhiU/jTmateY5H4gh8t9xnPb2BQpgCtQRrMdsz+5h/fu+bw1lxaT0aRkJh44x+y
3i/42zZZyRAaJu43MBieD/DDQKdiicOcGdZ1BHDb4sUT3k1owgkgh7TIIqtlwf9sUsROLrIfwhT7GBiMQAIk+0vFcGYqddZ9l6xd
Rem0KncTmrhrTrD3FwTSNzetON0R1iYNZg02S37TAaYp6DQdFmZbWqxUmC/t7H/taTd+/EnOZARls7qqFACDCWjDxgUfiAlBayUJ
oaDJGL+BwX5VAAUq5ISbaJDJxLUAkOucuFBgwgggh7QgZPXOvoZPpCj2mhIHZsnPwGCUoUDeL6jGZPLv77543UXpXFrlWltF1RAA
RwU/6taZV7zaAn2ywJ6GyfobGIwhFCDydciWY3150/u+Nq+1vV1PRJWgGH/jB+XQSe1ol1qqNY6w4wrMJutvYDAWFQARKF83JpJz
Ykn3i0Q0IUmacSeAXLmpp9u86f0Jcs8osm8KfgwMDoYEIGS/V1TxeOz9915yzRLKZnV7a6uctgSQQUa0ol3/onl1I4OyISuOkoEG
BgYHFwpo2NIiSOeL3NouWxctGlebGlcCWIzFRCD2GJ9ICneBD6VN4s/A4JBiAZn3S7oxkTz1npnbP0DZrM61jt9egXGTE4yMOAGr
+NaWK48VrL8bQtkMkGnsOY3nlmkJVi0jxSCAiV97+aK3fOctP/xICePURmy8R56V9j8XE3ZKQWtj/AYG4yECojLhxnjqyMB1/pWI
eHFn57jY1rgQACMjCFl9a/PqN9gQrUX2TWNPA4PxhSj4JRaOtepPF65d0Jobn2XBcSGAtvK/CvrfHLIFm7pSA4NxVgFEISvdGEum
7JT4ZwLxoOVNIQGU+/rrDbNXvckR8p1F9jWM9zcwmAgaEHm/xJYjP3Tvh9YfgyyYMyymlAA2Y1Hk7Zn/zYZFZleJgcEEmT9ASiud
iiWT7OBfCcS5zhwd4t88NO+fRk7dOmvVmyXJ34WsTMlvtcDsBqzakSMiEKNU2F187Wnfu+IxZJgoSwe1W/CQjLXi/TX0VTYkzCwy
MJh4IaC11kk3Hndi1pUEHJIKOGgCKMf+fHvzqtfbsN5cZJ9N7G9gMCmxgCgEJRaW+Id7P/iVI9O5g28nftAE0Bp5fw7Bq12yJYO1
GRkDg8mwf6JQKd0QTzUIN3kJEPUMmLQcwMC6f8uKY6HFwwDFGHzIOQUDkwMwGPXwaceyhBf4L9B2WnxK7rJdDI6yAxOtAHJRf3+w
si5LkBtnsDLGb2AwiSqAIAIVqMZYcj6a1IWRLB/7HoExG225vp9vS106Wzv2ZklyjoI22X+jAAymQAXEHUfkC8XN+Ue3nbhsUzac
8BxADlGXUuU65yeEOydEaIzfwGCKVEAp8HXcdRcnjm15KwPEYzxgdMyG24pWzWBi8EUazARhXIeBwdTJAO3aNpNjXUQAY/PmicsB
tKNVEog3NK9+nQXxhhIHgOnxb2AwdfZPJAuBR0LgrLvfd80RlM1qxuiXBA9KuhNwUZwcYZb+DAymOAwAKFRKNcaTDZS03wMAHUtG
b9c0tmuB2xs/0mxbsU6b5NwAms2e/6qVjiYJWDNDyTruuKJYLP7l6a5Zp6RzaTXuCmAjMhIAOVb8rIRw5obQyhi/gcE0UAFEohj4
bNnOiQsatr8RAHiUpwuPmgA6AA2AmXQrQFwu/DEwMJgOJMBQCceFtOX5YwwhDowMILKAvq3piqOUUJ0SIqkjzWgUgAkBDKbFeEaV
gUXPey7sKhx/Wu7jxUrNzjgogIwAQEros5LkJjW0qfwzMJhWEgDCUyHHXXcBzYwvBQCM4mThURFAG9oUACbwWcZPGBhM3zAgZjmw
pDgLAHKjeI81GvlPIH1785XzQ/bP8BAApte/gcE0jAIgiqEPEN75+DuucRfm0t6BwoADGvLSclGBRnBmXDhJbTb+GBhMTwVAEIEK
2bato3sOx2mjCQMOSAAdUfYfLHCmhIDp+GtgMK11gEo6MQjHfktEAIeQA2CAssjqW/CJBtb85qj013T9MTCYzkLA1woC9LYMMoLS
+y8K2i8B5NAa/b65eKol5GEKylT+GRhM6zwACT/0ASlefeZFzS+Lfrbvw0T3SwCbsZ3KwcUZcdhgQJlHbGAwjd0/QJq1Sjox13Hl
EgDoyHTIgyKALDYpAGDWZ4TQIJDx/gYG014GEEspQVK8CQB2LN4x9lWATPQ7/lHyirkMvNbnEGwafxgYTHtosPRUABCdft2ll9rp
dFrxPkL3/Rj0EgEAybh6nUNWg4p2/hkYGExzCCIEYQiS4ugTS69eGHn0zFgJYGnEJkxviJMNRPG/4QADgypIBTC0SjoxC05UD9CB
pWIsBEBZZFX5L51s4n8DgypLAzDYlhaEY524vzzAiARQfiW3Y0WKgRMDVib+NzCoLhEgSmEAMJ+ayWTEvvIAIxp1G6J4ITbLOh6E
uQrKaH8Dg6qyf1CoQpCghW97KjV7mGs/EAEsLf9ckXpNghxiE/8bGFSZ/QOKNVvSarDIOgkAcq1pMdocQMQXihZbKO8FMjAwqDoO
SNguKOEcBwCti1aMKgSgZZUEoMDiICr+M/G/gUG1gRkkBEiKRQCAzr0TgXsZdiUBuBGZGAHHhSYBaGBQnfYPEoEKAMWvyiAjKLd3
InAvw64kAHtbeuYzeK4Cm+DfwKAqgwCmQGmQlEe//cpGd6SX7EUAi8sn/1ohL7QgHdP918CgetMAmjVIYLa1K34UALTtURG4FwG0
YBEBgBZ0jEsWGBzCrAAYGFSh+YM0K7aEZZPWxwFAW+fi/RNAx6B8OFpCgEBGAhgYVC8NqJjtgB3rCADoWNRyoBxAtALAio9Wkfw3
CUADg+oFW1JCOpg/mhwAEcCZqBHoEaYCsLYFIjMApc0uj1q2fmYRagUd8jEAsLRtqdonAVS0/lLAIYH5ihkabBRArUIzlKeGD75B
bdE8EUKtAcaR0bc07ESvEY1795wtM8DUrGFO/6pZCECHCmGfB0hhGKCGFYDWCpB02C/ecY2zJ9eL4fF/ZYkgOZeJYwxtzL92XQM4
YPi9RRMC1DgUMyDQdNQx0t5T7g0jgEoNAJSeLSGk8Qm17BoAkoTS1j7oQMGwQK0SPcDMEKD4rp2YtWe4N4wAKl2AtUaLBQmAtYkB
alYbgiwBf0cBfncBZJE5IbhGGYBZgwGXZXA4AOTSg7sChxHA0nIbMCGo2SICTA1A7YcBoUL/Y93muMfaFQCkwWwLi2zLmgUArUOO
Cxo26o9ja6QAoBslpDkGrB5UgC2Rf6YX3rY+CFsaFVCbNMBSCEghG/f8zT5on2aQUf51pAI0eu97ATrQIGGUQC0GAZaQYOJGAOhY
tHnkZcAm9OpyjiClzbJQXakA76V+9Ny7BbDKc8MMf00pAEEECCQqwf5+FYBgHTczoM5IwJHo+78u9N77QhQKCJhwoGbGFxAkADta
BmzY+vjICqAVi8ojTjGjAOpwkjgCu/76Err++BygAbJl5AfMVKj6GIAEgQS5B8gBtDEAMCEWvc8sDtcdCdgSfY/uwEu/fgLetn4I
R4JsMaAUoi/zqKqSBzRcAOibt3BgBK2R5wFJ87jqNxwQrgVvex4v/eZJJI9pQuoVs+HMjkM4FsAA60EiMFxQDUPKkS8XKFcCdmAf
BEDlHACEOQiwznMCtgAY6Pu/LuSf6oXbkoB7WAOc5jisBgfCtUDSrBhUy3gqGSD01F4O39rHO8zImnAgcgauBTCjtK0fxRf7QJaA
sAQgKKoyMU+qCoaS0U8J7NbFaFSzByAANhWABkO8BwCQLUBRYTlYMaD0UJ4wmOYEoCmEVkqNTgEQlGF2g70VAQ+JFM0MqSYQEYTA
XgSwj+3Ae7/QwMCgSo0fxNFa4N4nfO2jEAheWToYhWdgUP0hQKTZmErA4J6fERTAgNorCiPxDAxqBhoamrgIAAsxj0ckgFylIQhx
ycR4BgY1EwKQBkOUFcA+Q4BeNJW/pz6jAAwMaiYIoKi0X/QBQ8uA9pEDYPAucySYgUGt5ACIQlbQpHcBwGJ0jhwCVGIDCepT0GYv
gIFBLbh/gDQ0BLB7vyFAR1kcsEZvCF1+r4GBQXXnAAANKA6pFwA2D+z63asr8JzKbsAdISuUG8WZWMDAoGrlPyoVnL6S2AEAbeVd
v3sRQKUfAEvdpcHKtAUzMKiBDAAIICr0Un7XoCYYgQCALAOAzocvMcMj4/4NDKpd/rMkAda8XXVbpeHmv49VgOaWeb0g9EZLgYYC
DAyqmAJYgACBFy7D9cGQyGBvAqgwQ8dz8AF6QZKAAGnzEA0MqjUAYEgQiGhrFOa3Dmv2I0bKGWSR1YB6QYCM/zcwqOoQgLSEABhb
AGAFFtH+CAAbkYkYQtOzljkcxMCg2iECaLDmZ0f85T6Zg+hZ0xnYwKC6IwAGpMcBpCWeBYAdQ6oAgREaglRewETPeAhApkForWrD
SCCK6F9WJtVTk+4fBAUdKJbPAMOLgEZUAJUXEILHA9ZBuRzYSIGaMHqKGnkSwIqhvRDBbg9Bb9GMcC26fwAyYvrtuktuAYC28lL/
MD+wx5uIAL4TV8Zfag6etEkcHkCz6f9Y/cavvRCqGEAmHVhxC05LEqmFs+A0x7H1tsegAwUy2z9qCSpGtixp//fLe9a9ZYjN7/tc
gPLw02n4enEDVj5mkTw8ZK0BmFCgyo2/cVELjvx/r0H8qEYkX96M2GEpOM0JlF7YjW2/eALwVflIMPPIakMBMJcT+Y9H37dKQk7t
NwcQJQ6iFxJhsw25rAifTVlwFdu/IOhSiMbXHIaFK8+AQglaa7CvwEoj6POM0dco8zMYRPIRAOjYYwlwXwQw8EIGPRJtCzbWX/1z
AdBeCN/PQ3shSJSbP9kY+H+D2hIABMgC+xAKjwB7rwAA+1gG7EDUPVRq+XCBfTYrAbUTCpAlQJIGDvYwqFX5HyUANfRuK0QnALQi
N7quwJVMYQnFToC7BIQ5Bs7AoLoogC2SINDmv++/tqssAkenACqJwHTv9bsIeMgmCQLMQrGBQfVA27CgGX8mELejfUQVv69KQK6U
BCvGn21TEmxgUG0QIRQE+AEAaMFmGgsBDNUD95QQAGYZ0MCgavS/AIki+6GGvhsAlqJNjYkAOpDVABDCvsfTqiAhTUWggUE1WD8Y
FiSI8WRTz5wnorB+5IzvPgkgW475W3u+9iIRHnKionGTB5hI0NAvGvKFycvY73X9Cb42TcE1ax/KJQvMuHMZsmE5/ucxhwAZLLEI
xGDeZLYGj//EJxHV5pMloomvoxp9DjU4UNB+CO2H4FADmqPXV1473h9HiqgeQDE40IPXDnR0HPjQ1xysoQsCyfJSZPnvDN7vCNck
DHutwWgfNVEIDRDdsb/4H9jX8eBlVLoEQ/AdJYRXmTzAOMq0kKGCENpTADNk3IKIWbBcG2QJCEdCxGyw0lB5H6oUIuzzoD0FmbQh
3WjoWI8DJzPg9xTBSsGeGYOVcGAl7MiVlAKoQgiV9xHsKkHGLMi4HbmC0foDAqAZ2lfQvgKHGsKVEDELMmaBbAlhC8iYBRBBFQOo
QvQV9JYgXAmZsEGCBsjIYL/xvyxq31NK/yGK/7PqoAigUjhQCPiuuBV22ZCzFbTGqJKHBvscIaVhpVwkX9GMhoWzkVzYjMSRMxCb
l0JsXgOslBN5ehGt3GovhLetH32Pd6Hnnhew47dPo/+x7sgw4vYhbeVlZghX4mWXvhZNpxyOhhPmInZYCmSLSDRqht9bRP7pHuy8
70Vsvf1x7HpoW0RYtjwwAREig3ckUi9rQsNxs5F6xSwkjpmJ2LwGxOY1wGmOQ9gCEGLg9X53EYWne7HzL1ux/XfPYOf9L0D7GnaD
A2ZTlbIfaJukVNAP/nXXN54tB1a8P27G/sOAjMgiq2+ZteKmBMXOz7MXEsgyz/mgLQ6v/MwSzG89AfZMF1bSgYAFho6+lI6MquJh
y7ExSQEhIgFW2tGHrbc8iqeuuQf9T/TAnunu1zOSFAh2FnHEha/Ga799DnQp2CuMsOIOCASlo/0Bg949ku1CShAI/u4itvz4r3js
83+A31OETNj7vDZJQrDLw/zWxTjuU0vgzkvAanAhpQ2AoaHBuiz3GUPC1OHXDIoeuv/4PJ665m5s/93TsBIOSNL4qJ/aSwCGDRSz
+rn02eXd6/49gyVWFpvCfb3+gJ58afk1rMX/cjl0NY/5IGNgRMY86/QjkZw/EyAgzPvw+/II+osI8z60F4IDBQ4jQ+SQwYGCKgYI
+osI+kuwG10cc8mpeONvLsL89yxGsMs75Dg5yHvw+4tQxaB8/fK1Qx31Dej34PcVQY7EMZedilNv+QfEj5oJVQz3fe0huxBnHj8f
ZMtoP0JfAX75flVxyP2OdM3+IgBg7pnH4g23/gNO+K8zAWboQEcKyWDP+F8W2IdU6n+HhfEHSwCV5UCh8ZsCeyUBsc+MosHoEOYD
aA6j5guiUp8vBpNiPFyiD0vCySgO9vsKcFoSOOW75+KYy1+HYLcX1fgfYi5g6MWja+sBb06WADTD251H80lH4LU3nAOZtKFDve/E
ZKUPgQ4AxUP2I4joLXqk+41UUCVJCgBBfwnaC7Hwo6fjpG+dHZHO/q5br/IfkhT00107i/cBQHqE+v8xEUA2GiI6Z9faZ8C404nU
v1kOPBSWFrT3xGWGlbThNCSisCBWTgomnYGfDST9ytlx7SsoL8SrvvJ2zH/vYgQ7vQGDGas6qVzHTsWja7uD1xbOkFifAGFLeLvz
mH3qArx89alQ/f7+FQhR+Z6Hk41wrCH3aw+7pp2KD5BdhfwAQqkvjyPPfzVe9dW3QfvKyNHh8l+7ZDGAX3wI3yu1Ry3A9+usRxXL
d6BNAghZ4OcS4s1cOW7IYHwGTjOkY6H7T3/D1tsfQ7izBFUIIsNscBGb14Dm047ErNOPgpA0ILtJRHGw1hqv+uLbsPvBl5B/phcy
Zo0pPuZQo/uO57Dr4ZeQf7oXfnceHDJk0kHy5U04onUxEi+biTAfDBi6kAJh4OOoi16D5254EH5XYTBxOIrEo7Qt5J/pxQs/eQSl
rf0I8z441LBSDpzZScw4cS5a3nwM3OYEwrw3sHtRSAGvP48FHzwZPXe/gOe+82fYM+Omp2HEzdJDSND42WjfMyoCWFr2+NoLb+93
Sp8XEG5ZuBkWGKfEoLQtvPjTR/Ho1zciFk8NeD7WGmBAJm3MXnI0XvXltyG5cBZUIRggAV0KEZ/biGOv/Ds8+I+3R8tpo7yucC3k
n96Ne997E0ov9Uc5x3LfQOhIjj/333/GyTeeh+ZT5iMslklAELSvED98BmafsQB/u/Fh2M3xqGbhgEKVIWwLvfe9gEc+81tI245a
kVWuqaOVidQrZuH4tqWYt/x4hHl/UEUQQYchjv3EaXjpV09EORCL6jwwZW3DEh6Hz+7oDe4YjfwfVQgQMUtWM5gu6LvuCYD+ECOb
TRgw/hAxC66ThN0Uhz3ThT3ThdOcgDM7AelYeOmXT+CeC9pReHYnpGtFy2Flgw08H/POeSUaFs+BKgVj6+1X/jtOUxxOSyK69gwX
dlMc7twUCs/txCMf/01khEPzDJohhMTM180fzCGMxWPZAs7MBJzm4dd0ZidgpRz0P9mD+953M17IbYaVdAfzEYKgSgEaXj4b8849
DmG/DxL1vTLNgHbJAgG3XYbrC6OR/6MmAABoi8IACM030chbiw3GQQlwWF4KVFz+0tHPmOG2JNH36A50/tvG4TkEAjhQcJqSOOyd
r4AqhMBBJAQHrjXk2tpXsGfG0Xv/C9j288dhxdxBLy8IGgoNr5wNq8Eduwxn7Pt+FcNKORAWYfMnf4vCs72Qrg3owaVCZo15Zx8H
K2mbEAAkiwhgKbppTE5n9ARQriayS7fm2euRkGY1YJKhfQW7KYaXfvk4eu7ZAivmDIn1CYDG7CVHw2pwwOE4Dg0BHGj03vfi4KVQ
rjBRGvEjGyFi1kD57rjxYaghEjYKz+3E3374EKQ9RPUIgvJDzDzxMMSPngn2Vd0GpAzWMVgUsP5Laudf7wJA6T2afx4yARDAjIw4
Z/u3X4LGLTGywWBlzHKyeV4g3O1hx++ejgqD9BCDCBQaT2iBOzsBDtX4LZFpBtkSxed3QgXBkJWGKEtvNbgQ9gRtFlUM6VrY/ttn
EBQ9kCUHJ6RiWI0OZixugfJU3YYBBGKLBCRw4zJsCgeO9xtPAgCAHDqjHBHr75cQMEyvwCkJ9sgS2L15O1Q4PCbnUMNudBFfMLPc
438c8xOS4G0vRHsXhhWXMoQTlSRHZDS+bpg5Ip/8Uz3wXspDWGKwVkFpSGkjvmBmmfDqc0YIkOzXfl/I9BNgsKfnuBNARVaUdnb9
MeTwwRgsYrBJBk5ynkDYAsW/7UJYDCNvXLE7ZpArEZubGlc5Xj4qKqoSVHo4sTBAAtHGpQkKCElEG4SKL+wCWbTHdQTc2ck9jruo
M/lPNoPw8/N71myplO5PCAEAQAYZmUZOEYsbLRImGzj59g8IQtgXrZsPNXLmaJ1cJsfZG3MU8OtAY9J3hHM0SznkKNuPPWsNop2U
UVhSl1NRhFAkNH0PALVh8ZgG/WCCpvJaDP+kj72dJhk4daHA/mRzTd6wrqf7HZ33d2HDY7XZ6932ewBMSKsJJYAssrodrXJ597oX
BeNH5WSgCQMmL+MDaMBqcKLilyFPngjQoYbqD8obZbhm7pekhJVywNB7CBuCKoTRfoQ6SwIQwBZJYsY308j55bV/TCgBAEBr5QRh
5vVF9n0BYfoDTNagE8ChQnx+I2TMHtgbUJHp7CuUtvVHycEacYzMDBmTiB3RCA55DzPX8LsKg2RRP/5fW7Bkv/ZeJCVvjOwypyeF
AAhZnUFGnNO7frOC/lmcHKrnJcFKSe6k7Ewrx+INx7fAsp2oVLjyK0sg2Omh+PzOqFlHLRBAmdQSxzTBnZuMPH3lWDMpoMIAhed3
QtqyrgJRBtglC0R8w7m7rtnZjtaDovyD9tyLy0uCANb40ZKgqEfDr2THw/5oL/9AY8uJGnilYTU4mHPmMdCsBtwea4a0JXZ3boff
U4zWy2uAAUgQlBei5S3HwE7EouW+Sg7EipKhfZ07yjsW6yYSZQkh8trrl1p+a6gqnzQCSCOnGIzl3Ws3BVr/KU42AVD1ZPyqFPX0
a1g8B3POfDlSC2dBlxtqHFSDDo723e+LQIQjEe7y0PKWY9D8d0dGG3MqdQAMEAR67vwbwj7/0HsDTI62H1RPIz1jKaBLIWKHN+Co
970KOgwH9jhEhGdh1yPbUXh+F8ipHwXAYF1W3T8+u/fa5yPvnz0o9jvE1l5pQcipm2nFVxh8enQgKdWH8RdDJF42Eyd86UzMOn1B
tD4daGz75RPYfNVvEXQXIBxrDBnqqA1WEHiQXtTyaiCs4CgD7ncXEJvfiOPblkaGwDxAFmQT/P4Stv/mKYiYVRXeX9gSYb8PVhw1
By3vMqw0JlHFAKoU4IQvvw2pY2cjyA/tfMQgEtj+66cQ9vlwmutmSzALCFFgv0QQVwOgg/X+h6QAoimbUxlkxLndLbcXtf+nGDkC
tZ4LIIIONZzmOE658Twc/o7jBxJuZAksSJ+Ek284J6qN16MsxhGE0Pfwsn88GYs+9WbE5ibBgUawy4PfVUCw04MOFWadvgCn5tJo
XDwXYWlwbz6HGlbMQVfHM9j50DZYCXta98sjIRAWfbS85Ric9M2zMOM1hwEAwn4fflcBfk8RqhgidngjTrr+bBx98WsRFoYYP0fb
iUvbd2PrLY9CJqwhm4Rq3/snyCYG37i8Z01nO1rFwXr/cVAAUS6AkFO3ytWf08y/RI1LABKEYKeHBR88EU2vng9vV38kP8sy3Ovr
R8vSl+Ows1+J57/3EJymA3smIgKHjNi8Riz+zzPx8o++ATsf3IrCszsR9vuQCRuNi1rQdOoRkK5EWBjSgaccNig/wFNr7onabk37
hxh9cBGz8LJLXo8jLnw1+h7Zjt2PdiHoLQIEJI9uQvPfHYHY3AaEBX9YWKQVw004ePKGu9D3ePeonnEtef+8DgpSiC8dqvcfFwJI
l1XA2Tvafr2heWVHQrhLS9HWrNrdJ0CE5LHN5dI72mNiA8QCjce3RJOSRm8U2g+hSiHsmTHMffuxEIi64jIYGlFj0LAQDDN+rTRi
DUn831f/gK5Nz8Ge4VZP73zNCPqLIEug6dT5mHXqUQOilKGg/Kgx6LD9DoGG0xhH9/3P46lr745qA+rI+yfJlf3sfe/dXWueKMf+
akoJYFAFkL6VVn1WQS+t6U6N5Zp7HaiRxU65vbXywjFLoUrYzqFC6KvhcXw5WTb0RB0iINaQxPM3PYTH/vMP0b74ajKGSlMpzQjz
AcD+kM7g5fuVg0k/aIbdGEf/09148JLbEfZ50bkI9UEAlcx/XlnqK1FwueiQb3xclu4qKuCc7rW/9zn8eaKWcwHlzPXO+18EEw9O
znL3XpIEjRA9d26BcMewFFduCmqlnDJ/8sBxWhgwej0gde2UAxG38MS6O/GXy34WGY4cRU8+3sfX6N3Qob1/6ORzJOyUO7ihiYfc
L0XPlcOoQ7CMRw1Eu/74DO4573/Q/3hXdCZB3Xh/6AQ5pAW+ccH2bzydO8TYf1wVAAC0AcgCEEp+qiTDtxKEXYt9Ayv737f97Als
uemvOOqCE6HgRxVqloCEhSe/cRe6Op4tt7E68ASNmoLa2HrbYxBxC3OWvgwyHgOXxX9lux9BgAAEJQ87Op7Bk9fcg5d+9QSshD3Q
svtAoQtJETXvLK8ikFX+frQCyC6/XlTakREoHJsfYc2wXBs9921B4bmdmPv3C+HMiIEgoKGG3G90z0qHyD/RjWdveBDP3fAgdCmM
pH/dHBPG2iZL9GnvRQT8XwymNrSNy82PGwFQeY/AOTuvffjmWSuva6DYFf3sKarF8wTLSayHVvwcux7chrnvegWc5ji8HQW8eFMn
nv/eXyAcMfolwHJT0B2/fwZPXXs35r79FWg6dT4ajpsNtyUZ9d4vKXjb+9H3WDe6Nj2Lnfe/COUp2A1u+ags3j/BxG303v033Pve
9uFEIQiqUK5d2Nf2gTJR+DvyeOCDtwwvMy435vB35CMS4lG1BQZZFvqf6sGfP3gLZpx4GGadfhRmvHou4vMbo/ZimuF3F5B/phe9
92xB9x3Pw9uej04Wilt1dUYgA3AgKeAwe17fuu52bJfZUXb8mTQCAIDNWMQMpl96V3wu75TeYws5J4wyYaLWRoQsAVYaT3zlT3jm
uvshXCtat84HsBqcg9ifzrCSDogEuu98fmA9X8ZkdGaejvIKuhQOHJZpu3J0hsAMsgVKL/Yh/3TvkL0DGDicRCbs/aZuKnvyt/38
8b3vixCpkDEVP0UdiWXSRv8TPdj1l22RgoqX1Qyiw0Sj7sfRFme7KR4dJabryfhZx8kWee3ft703+E4GGdE6DtJ/Qgggi6xejE6Z
7s/tuGXWys+6sNYGUJpqc2QAQQM96VW5XfbAOX0HMUcrE9tKOgMddirJr4qRIeUM/HxMXpAj+W677oi/G5VREcFudPcZGh1MPqWi
TmTcGsijVBSKcCRkzC6bAddl408BwQoMkP7kZbg+KNf86/H7++OMVuR0BhnxXLf4735d+nOMHFmz24UZA0t9A9nqcZCmQ5NfQ0dp
r58f1Oflvb/GcojISO8/1Hse6IY85H7F4PM9WEKtAe+vEmRLn8Mfn9u9/neMjEiPk/SfMAIggBejkz6KNZ5kWqVYhaISNNdykMYT
/Pfra+abFjNgbZEUBQ66NYt/YYDaJkRhTADSyKl2tMqze9fd5etgTYJcweYgEQODsbhSdmCR1vqq83vWbMmhdUy9/qaUAKJQoF1n
kBExstr6tfekQ1KYzkEGBqMLtOLkyDyX/vfc3nXfbkerPJhmH1NKAATixeikd/as2S2kXk0gEtHisRF3eh9xdK32tmM+5NxDHcX9
LCHI00HegrgCALdiEU9Uf6cJXZ6rhALn7Fj/qxIH307UckJwDLCSNmzpwm50Yaeif6V0IRyr9uiRES337XG/lnSjpUeDPaFi5AjN
+t/P7l77f4ey139Uc3Gi7yYKBdpEg9768aKk012yX+lxoKneOggNMezuP/4NQa8HXQoBEZ2uYycc5J/qQVRFXTPN/CAcif7Hu7Ht
d53Rfn4Z1f7LuIOd979Yrh0wSqDs/VWSXCvPpd+c0zv76omU/oNKfRLQjlaZRk7d1LTqjXEhfq/AUoEF1elZLvuU+/vpjlPtIc+I
ZcpE1dG5aJKekiRJinW30OLks3uvfX6sh3wcDCalTDeHTm5Hq2wtffe58+Ovo5Rw3+IjVFSHfQQBDOxy2+urRjdREtXX/R6cPiTt
kCUDHX5oee/aO9vRLldh1YSHyzSZd5hDq9iMRXRic/dvksJZlmdPkTlf0MBI/7CB4tYuXfzW+T3rLm1Hu0yP8YCPg8WkeWACeDMW
cRbZUCh8pKSD7TZJyWATABrUs/HrONlWP3sPSUp8PKr1b520RPmkSvDoVKF2ec6utc8oVh8iJi0hNJsskEGdxv0WSQpY7QTjwuXd
X+5rQ7SEXpMEAABppNVGZKxze9f/osTBZ+JkS5gqQYP6C/qZQFpCkGJ1yfKeNZ0ZLLFogpN+e2JK4u/vYhMDGWtF8SubzouffEKK
3BN8hGG9JgUN6pICVJJiVp6D/zyvZ91aRqtchl9MehetKTG4clVTtMk1lJcU2d8cJ8fiOjpYxKCu4/6wgWJWP3s/e7h71r9Hh3rm
9BTZ4tShss55c/Plx9uwO0jQnIBDbZSAQQ1LfxUnW/ocPBz6/OZz+9b2YJLj/ilXABVUkoLn9XzjUY+C94K5ZEHArAwY1Kjn1w5J
6elwWxj4553Xt647jbSYKuOfcgIABpOCF3R/Y6OnwostkkKAzMqAQa0ZP1uQYOa8YtV63u7rn2pHq8yNc4OPqiMAAFiGbLgRGev8
net/WND+pxPkSjL5AIPakf1sQWgBIXwdfvi83vV/zCBjpafY+Kc8B7DnZ2lHq0gjpzbMWnlNimJX5NkLMQkblgwMJtL4BUjHyJb9
uvTR83vWX7sRGWsZsuF0+HzTqgy3HZ1YjFZ5QfG7vzg//tojUxQ7xTPLgwZVbP8C0DFyZF57nzq/Z/1X29Eqz8L6aaNup91ujKj3
WYaALE5qXvWDpHQv7NelkEBGCRhUG8IkOVY/e587t3vdZyq7YqfTB5yW27G4XCpw/cmXWYc96/wkSe65fWxIwKCqoJLkyH7lff3c
3nUfKxt/5ZgnQwAHJgEmgJA74sqYWwhuSgr3nYYEDKog5ocAVEK4Mq9K65f3rFvJyAhCdlq2w5u2sTWBuA0ZSm/5etFL2Bfk2f9p
A8UsBodmmhlMU+NnAagEObIQetcs71m3MjONjX9aK4AKMoDIAvo6XGof1ux8JyHc9+W5FMIoAYPppVhZQOg42bLAweeXd6/5dAYZ
0YbshDX0rAsCGEICDIBvnbXiWwkRvzivPcUDB0kbGEyp+WsCIUa2KOrgM8t71n6OkRGY5sY/rUOAocgCOgMQA3RO9/pLCqF/bUI4
MmqfacqGDabU82sBKWxYogD/yuU9az9X7uQ77Y2/ahTAkBiLAAaB+LZZq66ySH4hZA0FbTYQGUyF8SsblgS4GEBdfG73uh9NZjuv
ulEAQ9iKAQIjI87uXvtfBQ4uEqCSA0sw2JQOG0yq8cfJkWDe6lPw9+d2r/vRRiyxqsn4q44AKiRAyOqNWGJd0L3+ByH4nZp5Wzw6
dMSQgMGkGH+KYjLk8JEQ3lvP6/rGpgyWWMuwqepWqKpWNi/DpjCDJdby7jUbS1x4q8/qoRTFJABldhIaTJDhM4FUimKyoL1f75aF
ty7vua6zHa0yW4XGX3U5gJFQKa/csOCjM628XufCvrDAPpcHy+QFDMbL+LUFKWySCHTwte/3vPQvufLRd9OtvHcsqPqe/JVDRy7Y
dUPxx4V7b74gfkrJgniLJCkUtNlIZDAexh/GohBzl4/g4nN61n1lMzYDgFiF9VXd0JZqaJAoh7RII6d+2rT6HS7Rtx1hHV5gT3F0
4JapFzA4GMmvk+TKEvzNPvRF53et+3PlzD6qgVCzZrwjgTiNnMpgiXV+75pflYS3tKD93yXIlQIEcyqxwRihLAiKky0L2vtB4Ogl
53et+3OlkQfVSJ6pJr3i0Ljs9pbVn4SmrEXCLnFgjiIzOIDXBwOsE+RKn4MeRfjE8q41N+w5r2oFNRkfR0ogIxigd+9Y8wVP62WK
+eGGaJVAGzVgsC+vL0CUopj0dNBR0uqM5V1rbmhHq2Qw1Zrx16wCGEkNtDddOsMl94sWicuICB4HCiY3YFCO9QHSCbKlx6EPps8/
0NP02SyymtEqqQYNv24IYE/pdlvz6reB6Ctxsl+VZw+Imo+asKB+jV9JCBkjGx6Hm3zmq87vWXN3pTNVdpKP6jIEMHGxHQEZImT1
f8/6cEMLJz8F4n92ybaKHCiABcEcWF9Hhq8BIEmu8DjYycT/cXbX2qsBcC3G+nVPACOpgQ1Nl59mC/tLDllv9KEQcGjCgjqQ+wTS
DllSgOAhuJ01XbW8Z00nA5Qrd6aul+dB9TkJhg003T77oxeD+ZMxsl9WYB8MrWBWC2pu2BmsLEjLJQseh3+F4P949441N+3pGOoJ
dVklRwCny2WcAPjdXdd8q+j1nVqE/yViLibIleVFXrO5qCb4HiEBlKKYpcFdRQ6uKsblqe/eseYmBiiDjKhH469bBbD3DGmXVN7G
eeucy1+tQ/kflhDnOJAocAAyicJqNXwNQCbIQYH9kJi/A0VfOGfX2mcAIIOMlZ0mB3QYApheYQFum716CRifEKB32SRRYJ8JpA0R
VJ3hM8A5AF9e3r3u/iFyf9q16DYEMA0QNXJs48qJrdGyIT4mSbzdgkCRAwAIGZAmWTitrJ4BVgJkxclBiQMw8FPJ6stn9ay/J3pN
RmDI2BqYCbyfCTV8stw++4p3EtM/aegz42SjwAE0dAhAmuXDqRwnZgBKQlhxcpBnTwnQzUS85t1da++okDoQHUdvnpghgDFhz51f
t8xecQY0XQKiC1LkxkocIIRWDCaz9XhyZT6DyYYlXLKQ59JuMP0PC3H9uV3XPjCo5gAyhm8IYDyIYGjceEvz6kWa+RJJuDAunDka
GiUOUT64xKiCibF7zYAWIMslGwRCif3nWfP3LFt/96zt33jaGL4hgEkIDQYn123zPjZb+94FAuL9AE5LkEMVVVB2Vaaw6BBjewI0
yt7eIQsF9kIJ0aEYN3pcuiXde/2uCklvxiI2Ut8QwIQjg4xYjM6hO8TotpYr3qi1eg8znZcUzuEAUOIAutys1JDB2IyewWRBihhZ
CFgjgHqamXMQ9JPlXWseHKrOjOEbApiiycrUgTa5bMh68s0NK2dZNs4GibM089sSwkkNJYNy4kpS9PjNGEQ2zwxoAoSEFC5Z0GCU
OOgVoF+B6ac7bftXF7301fwQErbakK2Z5hyGAGogPMgNVwXYMOOyo8my3iVZvj2EWpoQToOEQDlMAINDAlG9qYMhXp4JZNmQcMhC
AAWfwx4CbRTMtzl2+Ku3v/TN7cbbGwKopslNHcjIpWhTQ9ecNzR97Eii4ExBeJOCfqsFeUScbITQCFhBQTODVUQILGpIITCiPfeV
bs2WhIBLFgiEAnvMwHME/FZp/b9NQez3y/q/1rVnuFUrffgMAdRZrmApIJbuIVVvmfXhBkbs9dDiDCKcwYSTLIgZcXKgoBFwCAUN
BlTZaAhgYhBNY6XADICGGTsEQQgJAYckBASK7COE6rJY3qVJ/5FZb/ITOx5Ob8kVh4ZWbWiTbXuQqIEhgKrPFywF9J5LVLelLp0d
2s7rJPhUCHGKZj5JEOa6ZEsbEiEUyucgRrQwjBiAIeQwkWM7cBLrUCOPvicCIAUIkgRsSEgIeAjhcxgwaIsE7tfMDxP4Hi8sPZDe
/e2eoX+8vDkLxtMbAqiLMCGHVtGCRbRshA0pv5778WSgguNCza/R0IuIaDEBx4FxmCCKxciGhBggBAUNzRxlFaL/ynsXBgyVBged
Rhp/BniY1ZU9r4jeGykPAkGAIIggIRD5dEIABY9DaOYCQW8BqJOINmtwp9D8UGNj/qllz32vNHKoBI0qOU3XEIDBhIwDA6gQwtJ9
ZLY3LvhALL9r9lxfFF4pSBwD0FFgPhrAEQAdzuA5ROQCcGxISIoMVJIAc2TcgybOe12AytRQ+RcEKNZQYISsEEIzwD6AIhjbGHiR
iP7Gmp8lEs8z6ac12Y+prhndaWT9fSmgHehk4+UNARgcQCG0IUNLyz0blh1g2+ovsNotNeiU5VALhJ6tFbVoiCYSaJQajRqqgYE4
EcXAFC/TjsUgm8A+mKKQgqiogaJgLgLUR+BdAHZrEj2sdZe0eIf27a5g18zCSEa+p3fvQAeApbrNeHhDAAbjQwqL0UktWEQA0AHo
qVwSY2RER5mkIs/erstBhjF2QwAGkxlCAECFIACgQhKPYystxDzegU4GgM1YNGCcbWjjNrQNzIOh7628b9C4F3EbgDZkecjkMYZu
YGBgYGBgYFBV+P+KQOvejb/5WQAAAABJRU5ErkJggg==
'

function install_icon() {
    mkdir -p "$(dirname "$ICON_FILE")"
    base64 -d <<< "$ICON_PNG_B64" > "$ICON_FILE.tmp" 2> /dev/null && mv -f "$ICON_FILE.tmp" "$ICON_FILE"
    rm -f "${OLD_ICON_FILES[@]}"
}

# Lineas Exec/Terminal del acceso del menu: la ventana grafica si hay GTK 3 para Python. Si no, el
# panel en GNOME Terminal a 100x32, donde deja sitio al logo de abajo a la izquierda (a 80x24 la
# ventana lo taparia)
function launcher_exec() {
    # Ruta entre comillas por si lleva espacios (con \, ", ` y $ escapados, como pide el formato .desktop)
    local self=$SELF
    if [[ "$self" =~ [[:space:]\"\`\$\\] ]]; then
        self=$(sed -e 's/[\\"`$]/\\\\&/g' <<< "$self")
        self="\"$self\""
    fi
    if gui_available; then
        printf 'Exec=%s ventana\nTerminal=false\nStartupWMClass=%s\n' "$self" "$GUI_APP_ID"
    elif command -v gnome-terminal > /dev/null; then
        printf 'Exec=gnome-terminal --geometry=100x32 -- %s\nTerminal=false\n' "$self"
    else
        printf 'Exec=%s\nTerminal=true\n' "$self"
    fi
}

# Avisa al menu de aplicaciones de que han cambiado los accesos
function refresh_launchers() {
    command -v update-desktop-database > /dev/null && update-desktop-database -q "$1" 2> /dev/null
    touch "$1"
}

# Si el acceso antiguo esta anclado en el dock de GNOME, el dock lo sigue buscando por su nombre de
# archivo y lanza la version que tiene en cache (con la ruta vieja): se cambia por el nuevo, en su sitio
function replace_favorite() {
    command -v gsettings > /dev/null || return 0
    local favorites=$(gsettings get org.gnome.shell favorite-apps 2> /dev/null)
    [[ "$favorites" == *"'$1'"* ]] || return 0
    if [[ "$favorites" == *"'$2'"* ]]; then
        favorites=${favorites//"'$1', "/}
        favorites=${favorites//", '$1'"/}
        favorites=${favorites//"'$1'"/}
    else
        favorites=${favorites//"'$1'"/"'$2'"}
    fi
    gsettings set org.gnome.shell favorite-apps "$favorites" 2> /dev/null
}

LAUNCHER_DIR="$HOME/.local/share/applications"
LAUNCHER="$LAUNCHER_DIR/lampp-version-manager.desktop"

# Pone al dia los accesos creados por versiones anteriores (nombre, icono y lo que abren)
function update_launchers() {
    local apps=$LAUNCHER_DIR launcher=$LAUNCHER

    # El acceso antiguo se renombra: GNOME no siempre relee un .desktop que cambia de contenido,
    # pero con otro nombre de archivo lo trata como una aplicacion nueva (nombre e icono incluidos)
    local old changed=0
    for old in "$apps/lvm-instalador.desktop" "$apps/php-version-loader.desktop" "$apps/php-version-manager.desktop"; do
        [ -f "$old" ] || continue
        replace_favorite "$(basename "$old")" "$(basename "$launcher")"
        if [ -f "$launcher" ]; then
            rm -f "$old"
        else
            mv -f "$old" "$launcher"
        fi
        changed=1
    done

    # Un acceso creado por una version anterior se actualiza al nombre y al icono actuales
    if [ -f "$launcher" ]; then
        cmp -s "$ICON_FILE" <(base64 -d <<< "$ICON_PNG_B64" 2> /dev/null) || install_icon
        if ! grep -qxF "Name=$APP_NAME" "$launcher" || ! grep -qxF "Icon=$ICON_FILE" "$launcher"; then
            sed -i -e "s|^Name=.*|Name=$APP_NAME|" -e "s|^Icon=.*|Icon=$ICON_FILE|" \
                -e "s|^Comment=.*|Comment=Instalar, cambiar y desinstalar versiones de XAMPP y PHP|" "$launcher"
            changed=1
        fi
        local exec_lines=$(launcher_exec)
        # El acceso del paquete (.deb) abre el script de /opt/lvm-instalador, que es de root: una copia
        # que se ejecute desde otra carpeta (Descargas, que es tuya y la puede cambiar otro programa)
        # no se lo lleva a ella, porque en esa ventana se escribe la contraseña
        if grep -q '^Exec=.*/opt/lvm-instalador/' "$launcher" && [[ "$SELF" != /opt/lvm-instalador/* ]]; then
            exec_lines=$(grep -E '^(Exec|Terminal|StartupWMClass)=' "$launcher")
        fi
        if [ "$(grep -E '^(Exec|Terminal|StartupWMClass)=' "$launcher")" != "$exec_lines" ]; then
            # Se quitan las lineas viejas y se ponen las nuevas detras de Comment=
            awk -v lines="$exec_lines" '/^(Exec|Terminal|StartupWMClass)=/ { next } { print } /^Comment=/ { print lines }' \
                "$launcher" > "$launcher.tmp" && mv -f "$launcher.tmp" "$launcher"
            changed=1
        fi
    fi
    [ $changed -eq 1 ] && refresh_launchers "$apps"
    if [ -f "$launcher" ]; then
        for old in lvm-instalador.desktop php-version-loader.desktop php-version-manager.desktop; do
            replace_favorite "$old" "$(basename "$launcher")"
        done
    fi
}

# Crea el acceso del menu de aplicaciones
function write_launcher() {
    mkdir -p "$LAUNCHER_DIR"
    install_icon
    cat > "$LAUNCHER" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Instalar, cambiar y desinstalar versiones de XAMPP y PHP
$(launcher_exec)
Icon=$ICON_FILE
Categories=Development;
EOF
    chmod +x "$LAUNCHER"
    refresh_launchers "$LAUNCHER_DIR"
}

function offer_command_install() {
    [ "$DRY" -eq 1 ] && return 0

    local marker="$LOG_DIR/.accesos-ofrecidos-pvm"
    local launcher=$LAUNCHER
    local need_cmd=0 need_lvm=0 need_launcher=0

    update_launchers

    # Comandos creados por versiones anteriores que apuntan a otro archivo del instalador (por
    # ejemplo al pvm-instalador.sh de las versiones 1.5 a 1.7): lvm-instalador y lvm se reapuntan
    # y pvm-instalador, el nombre de esas versiones, se quita. Se ofrece aunque ya se ofreciera antes
    local link old_links=() drop_links=()
    # (los que llevan al de /opt/lvm-instalador, el del paquete, no se tocan: es de root)
    for link in /usr/local/bin/lvm-instalador /usr/local/bin/lvm; do
        [ -L "$link" ] && [ "$(readlink "$link")" != "$SELF" ] \
            && [[ "$(readlink "$link")" == */[lp]vm-instalador.sh ]] \
            && [[ "$(readlink "$link")" != /opt/lvm-instalador/* ]] && old_links+=("$link")
    done
    link=/usr/local/bin/pvm-instalador
    [ -L "$link" ] && [[ "$(readlink "$link")" == */[lp]vm-instalador.sh ]] && drop_links+=("$link")

    [ -f "$marker" ] && [ ${#old_links[@]} -eq 0 ] && [ ${#drop_links[@]} -eq 0 ] && return 0
    command -v lvm-instalador > /dev/null || need_cmd=1
    command -v lvm > /dev/null || need_lvm=1
    [ ${#old_links[@]} -gt 0 ] || [ ${#drop_links[@]} -gt 0 ] && need_cmd=1
    [ -f "$launcher" ] || need_launcher=1
    [ $need_cmd -eq 0 ] && [ $need_launcher -eq 0 ] && return 0

    mkdir -p -m 700 "$LOG_DIR"
    touch "$marker"

    local text="¿Quieres crear accesos directos para abrir este instalador facilmente?\n\n"
    [ $need_launcher -eq 1 ] && text+="  - Icono '$APP_NAME' en el menu de aplicaciones\n"
    command -v lvm-instalador > /dev/null || text+="  - Comando 'lvm-instalador' en la terminal\n"
    for link in "${old_links[@]}"; do
        text+="  - Comando '$(basename "$link")' (ya existe): que abra este archivo\n"
    done
    for link in "${drop_links[@]}"; do
        text+="  - Quitar el comando antiguo '$(basename "$link")' (ahora es 'lvm-instalador')\n"
    done
    [ $need_cmd -eq 1 ] && [ $need_lvm -eq 1 ] && text+="  - Comando 'lvm' en la terminal ('lvm use 8.4', 'lvm instalador'...)\n"
    text+="\nApuntaran a: $SELF\n(no muevas ni borres este archivo despues)"

    ui_yesno "$text" || return 0

    [ $need_launcher -eq 1 ] && write_launcher

    if [ $need_cmd -eq 1 ]; then
        [ "$UI" == "whiptail" ] && clear
        echo "Para crear el comando se necesita la contraseña de administrador (sudo):"
        command -v lvm-instalador > /dev/null || sudo ln -sf "$SELF" /usr/local/bin/lvm-instalador
        [ $need_lvm -eq 1 ] && sudo ln -s "$SELF" /usr/local/bin/lvm
        for link in "${old_links[@]}"; do sudo ln -sfn "$SELF" "$link"; done
        for link in "${drop_links[@]}"; do sudo rm -f "$link"; done
    fi

    ui_msg "Accesos creados. A partir de ahora puedes abrir el instalador desde el menu de aplicaciones o escribiendo 'lvm-instalador' en la terminal."
}

# Acerca de: que hace el instalador y la lista de versiones con sus cambios (la ultima, arriba)
ABOUT_TEXT="Gestor de paquetes Apache, MariaDB, PHP, Perl, phpMyAdmin y ProFTPD al
estilo XAMPP de forma independiente. Para Linux.

QUE HACE
- Instala varias versiones de PHP, de la 7.4 a la 8.5 y cualquier parche
  (8.3.10...), cada una con su propia pila: Apache, PHP-FPM, MariaDB,
  ProFTPD, Perl y phpMyAdmin, en /opt/lampp-X.Y y con sus propias bases
  de datos. Cada rama de PHP lleva componentes compatibles entre si.
- Instala XAMPP completos para proyectos antiguos (equipos x86_64).
- Solo hay una versión activa (/opt/lampp). Se cambia sin tocar los
  proyectos de /opt/htdocs ni los virtual hosts.
- Actualiza cada versión a los últimos parches de su rama, muestra sus
  bases de datos y desinstala versiones guardando copia en ~/lvm-copias.
- No instala PHP ni MariaDB en el sistema.

VERSIONES

1.49.0 (22 oct 2026)
- Nuevo nombre: Nexum Stack (antes LAMPP Version Manager). Cambian el
  título de la ventana, el nombre del icono del menú y los textos; los
  comandos (lvm-instalador, lvm), las carpetas y el funcionamiento siguen
  igual.
  * Esta versión se instala una vez en la terminal (sudo apt install):
    cambian los textos de su ayudante y de la ventana de la contraseña.
1.48.0 (22 oct 2026)
- Subir o actualizar una BBDD: si la base ya existe, ahora siempre se
  borran todas sus tablas antes de cargar la copia (antes era una opción,
  «Vaciar la BBDD antes de cargar», que venía apagada). Sin vaciarla, las
  tablas que la copia ya no trae se quedaban, y una copia de phpMyAdmin
  (no lleva DROP TABLE) cargada otra vez tras un error sumaba sus filas a
  las de antes: así se repitieron filas y faltaron claves primarias en una
  base de WordPress. Si la base tiene tablas, antes se guarda una copia
  suya en ~/lvm-copias (…-antes-de-cargar-fecha.sql.gz); si no se puede
  guardar, no se toca nada, y si la carga falla, se dice dónde está.
  Copiar una BBDD a otra versión que ya la tiene sigue igual (ya guardaba
  su copia). En la terminal: importar-bd <fichero> <base> [--crear]
  [--sin-copia]; --vaciar se sigue admitiendo, pero ya no hace falta.
1.47.0 (22 oct 2026)
- Tiendas con dominio real (las falseadas en /etc/hosts): el navegador ya
  no avisa con «La conexión no es privada» mientras están falseadas, así
  que Claude in Chrome también puede abrirlas. Al falsear una, Chrome,
  Chromium y Firefox aceptan su certificado propio; al dejar de
  falsearla (o al cargar otro proyecto), dejan de aceptarlo. Así, con su
  clave (Apache la tiene en memoria) no se puede suplantar la web de
  verdad: mientras está falseada, el navegador no va a ella. Si cambias
  /etc/hosts a mano, sale el aviso «El navegador acepta webs reales que
  ya no están falseadas» con el botón Quitar. En la terminal:
  lvm-instalador confiar-certificados --quitar.
- Prefijo de las tablas al rehacer wp-config.php: siempre uno que traen
  las tablas de la base (las tablas nunca se cambian ni se renombran).
  Si la base tiene tablas de varios WordPress, se usa el del wp-config.php
  del proyecto (antes ganaba el de la copia de este equipo) y, si ninguno
  está en la base, ya no se escribe un prefijo sin tablas: no se toca y
  se avisa. En las tiendas con varios prefijos, el que ya usaba su
  configuración si la base lo tiene.
1.46.0 (22 oct 2026)
- Certificados de los proyectos: el navegador ya no avisa con «La conexión
  no es privada». Desde que Arreglarlos quitó la CA común, cada proyecto
  https lleva su propio certificado y Chrome avisaba en todos; con el
  aviso, las herramientas que manejan el navegador (como Claude in
  Chrome) no podían abrirlos. Ahora Chrome, Chromium y Firefox aceptan el
  certificado de cada proyecto con un dominio de pruebas (web.local,
  .local, .test), solo ese y solo para su dominio (no una CA: no vale
  para ninguna otra web). Los de un dominio real (las tiendas falseadas
  en /etc/hosts) siguen avisando: Apache tiene su clave en memoria, donde
  la puede leer el PHP de cualquier web, y con ella se podría suplantar
  la web de verdad. Se hace solo al arreglar los certificados y al crear el
  vhost de un proyecto o una tienda; para los que ya estaban, sale el
  aviso «El navegador avisa al abrir estos proyectos» con el botón
  Confiar. Después cierra el navegador y vuelve a abrirlo. En la
  terminal: lvm-instalador confiar-certificados [dominio].
1.45.1 (22 oct 2026)
- BBDD, copiar a otra versión: ahora salen también las versiones que ya
  tienen esa BBDD, marcadas «ya la tiene: se sustituye». Al elegir una, se
  pide confirmación, se guarda antes una copia de la suya en ~/lvm-copias
  y se pone en su lugar la de origen (por ejemplo, para volver a copiar a
  la 8.4 una BBDD que ya se había copiado antes desde la 8.2.4). En la
  terminal: copiar-bd <base> <origen> <destino> --sustituir.
1.45.0 (22 oct 2026)
- Administrador de pruebas en los paneles: al cargar una BBDD de
  WordPress o PrestaShop se le añade un administrador local@local.test
  con contraseña local (el mismo en todos los equipos; las BBDD de este equipo
  nunca van a producción). En Cargar proyecto, el botón del panel abre
  una página con los dos ya escritos: solo hay que pulsar Entrar. Con
  las BBDD que ya estaban cargadas, se crea al pulsar el botón. En la
  terminal: lvm-instalador usuario-pruebas <base> [carpeta].
- Seguridad (noveno repaso):
  * El cliente de MariaDB y mysqldump de XAMPP ya no leen ~/.my.cnf:
    cualquier programa tuyo podía prepararlo para que cargaran una
    biblioteca suya con el permiso de administrador que la tarea ya tenía.
    Por lo mismo, git, ssh, certutil y curl van sin tu configuración o
    fuera de la terminal de la tarea.
  * La contraseña de administrador solo se manda a un sudo de verdad de
    la tarea: un programa que escribiera la marca de sudo ya no hace salir
    el cuadro de la contraseña.
  * Editar /etc/hosts: una línea con un retorno de carro (\r) en medio se
    saltaba la comprobación y podía llevar cualquier dominio a otra IP.
  * Montar nuevo proyecto: el dominio de una tienda (el de su base) ya no
    se falsea solo, porque la base y el nombre de la carpeta vienen con el
    repositorio. Si es el suyo, se crea en la pestaña Hosts (Nuevo
    proyecto con dominio falseado). Por SSH solo se clona de servidores
    cuya clave ya conoces (y de GitHub, GitLab y Bitbucket), y sin git-lfs.
  * Un Listen abierto a la red en los vhosts compartidos ya no pasa sin
    aviso: la versión no se arranca hasta quitarlo (Editar vhosts).
  * Tampoco se sirven por la web las exportaciones de clientes de WP All
    Import (carpeta wpallimport), las de PrestaShop en .zip o .xml, ni
    .my.cnf, .netrc, .pgpass, credentials*.json, .aws o .docker.
  * Otros: PHP_TIMEZONE, el correo de git en ServerAdmin y
    importar-bd --proyecto se comprueban antes de usarlos; los nombres solo
    admiten letras sin tilde (como en la ventana) aunque el equipo esté en
    español; las versiones de php.net se validan antes de enseñarlas.
  * El script lampp de las versiones propias solo cierra el MariaDB de su
    .pid (lo escribe mysql) y los vhosts de versiones antiguas pasan al
    administrador sin seguir enlaces.
- Actualizar desde la ventana: si la versión nueva hay que instalarla una
  vez en la terminal (cambia el programa que instala las actualizaciones),
  ya no sale el error de dpkg («Tubería rota»): se explica y hay un botón
  para copiar la orden (sudo apt install …).

1.44.2 (22 oct 2026)
- Seguridad:
  * ~/lvm-copias (copias de BBDD de clientes, vhosts y /etc/hosts
    anteriores) es siempre solo tuya, aunque ya existiera con otros
    permisos. Las copias que se descargan con exportar-bd, también.
  * Vaciar la base antes de cargar: si el volcado no se puede cargar
    (motores FEDERATED, CONNECT o SPIDER activos), ya no se borra antes.
  * Pestaña Hosts: los .local ya no se apagan (no existen fuera y, sin su
    línea, el equipo los preguntaba a la red, donde cualquiera de la misma
    wifi podía contestar). Los que estaban apagados vuelven a encenderse.
  * La contraseña temporal del usuario de la BBDD ya no se ve con ps
    mientras se carga un volcado.

1.44.1 (21 oct 2026)
- Versiones, Instalar: la fecha de publicación va junto a la versión de
  PHP, y «Parche de seguridad» es solo texto azul (sin fondo).
- Cargar proyecto: el título va fuera del recuadro, como en los demás
  apartados; el recuadro tiene más aire arriba y abajo, y el buscador y
  «Montar nuevo proyecto» van más separados de los botones del proyecto.
- Otro parche: la ventana es más ancha (la versión ya no sale cortada).

1.44.0 (21 oct 2026)
- Seguridad (octavo repaso):
  * Cerrar procesos: un programa que se pusiera un nombre trucado podía
    hacer que el gestor cerrara como administrador otros procesos, o todos
    los del equipo. Ahora los nombres se limpian y solo se cierran números
    de proceso de verdad.
  * Copiar una BBDD a otra versión: el programa auxiliar del cliente de
    MariaDB estaba en tu carpeta, y otro programa tuyo podía cambiarlo y
    conseguir permisos de administrador. Ahora va en una carpeta del
    administrador. Si se cancela la copia, no queda el volcado temporal.
  * Subir un volcado: sus vistas y funciones «SQL SECURITY INVOKER» se
    cargan ya como «DEFINER», así que, aunque la web o phpMyAdmin las lean
    a mitad de la carga, no se ejecutan como root. Al acabar, el usuario
    de la BBDD se vuelve a crear con permisos solo sobre su BBDD.
  * El MariaDB temporal (copiar o descargar una BBDD de otra versión)
    nunca se arranca como administrador.
  * Si no se puede dejar una versión solo para este equipo, ya no se
    arranca (al cargar un proyecto, Servicios, Arrancar o Reiniciar).
  * Actualizar desde la ventana: el ayudante ya no deja que apt instale
    otros paquetes «recomendados» o «sugeridos». Por eso esta versión se
    instala una vez en la terminal: sudo apt install
    ~/Descargas/lvm-instalador_1.44.0_all.deb (las siguientes, otra vez
    desde la ventana).
- Versiones, Instalar: cada versión de PHP lleva la fecha en que se
  publicó y si es un parche de seguridad (según php.net) o solo de errores.
- Cargar proyecto: solo dice a dónde apunta web.local (sin «Cargado
  ahora:», para que quepa el nombre entero) y, junto al nombre, un botón
  para desmontar el proyecto (web.local enseña una página vacía). Los botones van, de
  derecha a izquierda, en este orden: VS Code, phpMyAdmin, wp-admin y
  web.local, y son algo más grandes. Si la versión montada no tiene la
  BBDD del proyecto cargado, sale un aviso en rojo.
- Montar nuevo proyecto: botón junto al buscador de proyectos. Se
  despliega un asistente de tres pasos: la dirección del repositorio de
  GitHub (se clona en htdocs), la versión de PHP y la BBDD nueva, con su
  volcado si lo hay. Al terminar, el proyecto queda cargado. En la
  terminal: lvm-instalador montar-proyecto <url> <carpeta> <version> <base>
  [volcado] y lvm-instalador desmontar-proyecto.
- Los mensajes que salen al dejar el ratón encima tienen el aspecto de la
  ventana: gris oscuro y con las esquinas redondeadas.
- Herramientas, Registro de errores: ya no enseña el último error.
- Comandos: cada uno en su línea, con lo que hace debajo, separados por
  secciones resaltadas.
- Novedades: más espacio entre versiones, puntos y líneas.

1.43.1 (21 oct 2026)
- Herramientas, Registro de errores: primero el registro del vhost del
  proyecto cargado (web.local-error_log), que es donde van los errores de
  PHP de la web (el «error crítico» de WordPress) con PHP-FPM. Se ve el
  último error de PHP resumido: el mensaje, el fichero y la línea. Debajo,
  el general de Apache. «Ver el final» separa en líneas los mensajes de
  PHP-FPM, que llegan todos en una.

1.43.0 (21 oct 2026)
- BBDD: botón para copiar una BBDD a otra versión de PHP que no la tenga,
  para probar si el proyecto funciona con ese PHP. Se elige la versión en
  una ventana; la de origen no se toca. Si la de destino no es la activa,
  se arranca su MariaDB solo para la copia (pide la contraseña). La copia
  se carga igual de protegida que al subir un volcado. Después, al cargar
  el proyecto, se pregunta en qué versión. En la terminal:
  lvm-instalador copiar-bd <base> <origen> <destino>

1.42.3 (21 oct 2026)
- Cargar proyecto con la BBDD en varias versiones: la pregunta es más corta
  y cabe en una línea («¿Qué versión del proyecto y de PHP quieres?»).
- La versión elegida va solo con el borde verde de su tarjeta (ya no sale
  también el recuadro del botón de radio).

1.42.2 (21 oct 2026)
- Pestaña Hosts: aviso «web.local no lleva a este equipo» con el botón
  Arreglarlo, si en /etc/hosts web.local apunta a otra dirección (como
  127.0.1.1, la del nombre del equipo en Ubuntu) o no está. Apache solo
  escucha en 127.0.0.1 y el navegador daba «No se puede acceder a este
  sitio web» (ERR_CONNECTION_REFUSED). Se arregla una sola vez.
- phpMyAdmin abierto por localhost (un marcador antiguo o la costumbre
  de XAMPP) ya no da el aviso de error: lleva directamente a su dirección
  buena, 127.0.0.1/phpmyadmin. Por web.local u otro dominio sigue dando el
  aviso. Pulsa Protegerlas para aplicarlo a las versiones instaladas.

1.42.1 (21 oct 2026)
- Cargar proyecto: el proyecto cargado tiene ahora cuatro botones de icono,
  todos del mismo tamaño (al dejar el ratón encima se ve qué abre cada uno):
  * Bola del mundo: el proyecto en el navegador (web.local). Sustituye al
    botón verde «Abrir web.local».
  * phpMyAdmin: su BBDD directamente.
  * WordPress o PrestaShop: su panel de administración (wp-admin, o el
    back office de la tienda, se llame como se llame su carpeta).
  * Visual Studio Code, como antes.

1.42.0 (21 oct 2026)
- Nuevo aviso en Versiones: «Tablas del sistema de MariaDB antiguas». Las
  de algunas versiones vienen de una MariaDB anterior y el servidor llena
  su registro de errores (en una 8.2.4 llegó a 28 GB). Repararlas las pone
  al día sin tocar las BBDD de los proyectos (copia antes en ~/lvm-copias)
  y vacía el registro si es grande.
- Registrar un XAMPP de /opt/lampp ya no borra su htdocs si tiene proyectos
  (se aparta en /opt/htdocs-de-lampp-...) y guarda sus vhosts en ~/lvm-copias.
- Seguridad (séptimo repaso). Pulsa Protegerlas otra vez para aplicarlo:
  * Volcados: aunque se cierre la ventana a mitad de la carga, no queda
    nada INVOKER ni ningún evento; un evento que ya estuviera en marcha se
    corta, y al terminar el usuario de la BBDD ya no puede crear vistas,
    rutinas ni eventos. Root repasa la base al final. No se carga si
    MariaDB tiene activos FEDERATED, CONNECT o SPIDER.
  * Vhosts: un registro o un certificado entre comillas con espacios ya no
    puede llevar a otra carpeta (Apache lo abre como root). Los
    certificados nuevos, solo de las carpetas del gestor (los que ya
    tenías siguen valiendo), y los registros no pueden llamarse como sus
    ficheros de control.
  * Los dominios .local de los vhosts van siempre en hosts (si no, el equipo
    los pregunta a la red y otro de la misma wifi podría contestar).
  * Protegerlas y Cargar proyecto quitan la escritura para cualquier
    usuario en htdocs (plugins que dejan carpetas en 777).
  * Más ficheros que no se sirven: claves (.pem, .key, .p12, id_rsa, la
    carpeta .ssh), bases SQLite, .ini, .conf y las exportaciones de
    clientes de PrestaShop (customers_export).
  * Un dominio guardado para un proyecto solo se falsea si tiene su vhost
    o se parece a la carpeta.
  * Una carpeta de proyecto manipulada (un FIFO) ya no cuelga la ventana.
  * El acceso del menú y el comando lvm-instalador del paquete siguen
    apuntando al script de /opt aunque se ejecute una copia de Descargas.
  * Instalar versiones rechaza enlaces duros a ficheros de otros.

1.41.0 (21 oct 2026)
- Cargar proyecto: botón con el icono de Visual Studio Code a la derecha
  de «Abrir web.local». Abre la carpeta del proyecto cargado; si ya está
  abierta en VS Code, trae su ventana delante (no abre otra).
- Seguridad (sexto repaso, tras otra auditoría). Pulsa Protegerlas en el
  aviso de Versiones para aplicarlo a las versiones ya instaladas:
  * phpMyAdmin: una web abierta en el navegador ya no puede enviarle una
    consulta (un formulario o un fetch a 127.0.0.1). Desde otra web solo
    se abre su portada; escribiendo la dirección o desde el gestor, igual
    que siempre.
  * MariaDB ya no lee ni escribe ficheros del equipo desde SQL
    (LOAD_FILE, INTO OUTFILE, LOAD DATA LOCAL): secure_file_priv en una
    carpeta vacía de cada versión (etc/lvm-sin-ficheros).
  * Más ficheros que no se sirven: registros .log, .yml (docker-compose
    lleva las claves), copias de wp-config.php y copias de seguridad de
    las webs (.wpress, Duplicator, UpdraftPlus...).
  * Instalar versiones y actualizar phpMyAdmin: lo compilado no puede
    llevar enlaces fuera de la versión, y las carpetas tmp las crea root.
  * Protegerlas prepara los ficheros como root en una carpeta de root, y
    los certificados de los proyectos los crea root.
  * Volcados: se borran los eventos programados y las tablas que guardan
    sus ficheros fuera de MariaDB (DATA DIRECTORY), y se avisa.
  * El MariaDB temporal de las copias solo se para por su propio .pid, y
    los nombres raros de un proyecto o un .zip ya no cambian lo que se ve
    en la terminal.

1.40.1 (21 oct 2026)
- Ventana: los títulos de los apartados ya no llevan icono; lo lleva cada
  fila (Virtual hosts, Hosts del sistema, error_log, Comandos, Novedades...).

1.40.0 (21 oct 2026)
- Seguridad (quinto repaso, tras otra auditoría):
  * Actualizar desde la ventana: el ayudante exige que cada fichero del
    paquete sea de root y con sus permisos (sin setuid ni escritura para
    otros) y lee los scripts de instalación sin seguir enlaces.
  * Volcados: una vista rota en el volcado ya no deja a medias el paso
    de SQL SECURITY INVOKER a DEFINER; lo que no se pueda pasar se
    borra y se avisa.
  * Certificados: los de los proyectos se guardan en /opt/config/ssl,
    no en /etc/ssl/certs (allí el sistema los daba por buenos para
    cualquier web). Nuevo aviso «Certificados en los que confía todo el
    equipo» con el botón Arreglarlos (arreglar-certificados): pone un
    certificado propio a cada proyecto https y quita la confianza a las
    CAs locales sin límite de dominios que los firmaban.
  * Los certificados se crean con tu usuario y solo en la carpeta del
    gestor (nunca donde diga un vhost). Dominios guardados validados.
  * Protegerlas corrige también lo que ya estaba abierto (Listen con la
    IP de la red, bind-address 0.0.0.0, DefaultAddress, puertos de más)
    y cambia la clave SSL de fábrica de XAMPP, igual en todos.
  * Más ficheros que no se sirven: .dump, .old, .orig, copias~,
    error_log, auth.json, .npmrc, .sql.xz y .sql.bz2.
  * Lo compilado se copia a /opt sin conservar el dueño ni el setuid.
    Root ya no sigue enlaces al escribir la configuración de un
    proyecto ni al vaciar la caché de una tienda.
  * La ventana usa los programas del sistema (no los de ~/.local/bin).
  * Al instalar no se usa la caché de descargas, y phpMyAdmin lleva
    siempre sus huellas fijadas.
  * Lo que se compila corre sin la terminal de la tarea: aunque un
    programa tuyo lo cambie, no puede usar el permiso de sudo ya dado.
  * Cerrar procesos de otras versiones: un .pid manipulado ya no hace
    que se cierre otro programa del sistema ni la versión montada.
  * Las tareas de la ventana reciben solo las variables necesarias (ni
    funciones exportadas de bash ni las de prueba del gestor).
  * Protegerlas no deja dos Listen iguales (Apache no arrancaría).
  * Una CA local solo se avisa y se quita si su clave está en tu carpeta;
    también se apartan los certificados viejos sin usar de /etc/ssl/certs
    y se crean los que falten.
  * Esta versión se instala una vez en la terminal (sudo apt install):
    su ayudante cambia.

1.39.1 (20 oct 2026)
- Ventana: «BBDD» en lugar de «base de datos» en todos los textos.

1.39.0 (20 oct 2026)
- Seguridad (cuarto repaso, tras otra auditoría):
  * La contraseña de administrador va por una terminal exclusiva: ningún
    otro programa de tu usuario puede abrirla para leerla. La ventana
    no se puede inspeccionar desde fuera.
  * Actualizar: el ayudante revisa el paquete con tarfile (sin enlaces
    ni ficheros especiales), exige la huella, que el propio ayudante y
    la acción de polkit sean los instalados y las mismas dependencias.
    /opt pasa a ser del administrador al instalar el paquete.
  * Vhosts y /etc/hosts: se leen como los lee el sistema (por bytes);
    un carácter de control como \0 hacía que Apache viera una línea
    que la comprobación no veía.
  * Volcados: cada base tiene su usuario (lvm_bd_<base>), con el
    permiso solo para ella (el _ ya no vale por cualquier carácter),
    que se bloquea al terminar: sus disparadores y vistas siguen
    funcionando (en la 1.37 dejaban de hacerlo). Sus vistas y
    funciones SQL SECURITY INVOKER pasan a DEFINER, y el gestor solo
    lee como root tablas de verdad.
  * Reglas web sin distinguir mayúsculas (.ENV, .GIT) y más ficheros
    que no se sirven: copias .sql, debug.log, .vscode, config.inc.php.
    Una web de fuera ya no puede leer la API de tus WordPress (CORS).
  * Los wp-config.php que prepara el gestor desactivan el editor de
    plugins y temas (DISALLOW_FILE_EDIT).
  * phpMyAdmin se actualiza con huellas fijadas y solo si la versión
    es de root. El dominio de una tienda solo se falsea si su nombre
    va en la carpeta (prestashop.com ya no vale).
  * Los ficheros raros en un proyecto (FIFO, /dev/zero) ya no cuelgan
    la lista, y todos los python3 van con -I.

  * FTP de XAMPP: solo entra tu usuario. TRACE desactivado.
  * Esta versión se instala una vez en la terminal (sudo apt install):
    su ayudante y su postinst cambian.

1.38.1 (20 oct 2026)
- Barra lateral: filas más altas, como las de Configuración de Ubuntu.

1.38.0 (20 oct 2026)
- phpMyAdmin tiene su propia dirección: http://127.0.0.1/phpmyadmin/
  (los botones ya la abren). En 127.0.0.1 no hay nada más, y en
  localhost, web.local o los dominios falseados da 403. Así, un fallo
  XSS en un proyecto (que va en localhost/carpeta o en su dominio) no
  puede leer phpMyAdmin: para el navegador es otra web.
- Actualizar phpMyAdmin: botón Actualizar en su fila de cada versión y
  aviso en Versiones (Actualizarlos) cuando trae uno con fallos ya
  corregidos. Pone el más nuevo que admite su PHP (5.2.x desde PHP
  7.2.5, 5.1.4 para PHP 7.1), comprobado con su sha256, con la misma
  configuración y una clave de cookies nueva si era la de fábrica. El
  anterior queda en phpmyadmin.anterior.
  * En la terminal: lvm-instalador actualizar-phpmyadmin <versión> o
    --todas.

1.37.0 (20 oct 2026)
- Seguridad (tercer repaso, tras una auditoría completa):
  * /opt vuelve a ser del administrador: el PHP de una web ya no puede
    cambiar /opt/lampp ni /opt/lvm-instalador para que lo siguiente que
    se arranque con sudo sea suyo. Tus carpetas de dentro no cambian.
  * Aplicar vhosts y /etc/hosts: la copia se lee una sola vez a una
    carpeta de root y se comprueba y escribe esa misma. En los vhosts
    ya no se admiten Define ni variables, y los registros solo pueden ir
    a un fichero de logs.
  * Actualizar: el ayudante copia el paquete a una carpeta de root y
    comprueba allí su huella SHA-256 (la que se te ha mostrado), sus
    ficheros y sus scripts de instalación.
  * Todas las versiones quedan solo para este equipo (también las que
    no están montadas). Si una no se puede proteger, no se arranca.
    Versiones avisa de las que faltan, con el botón Protegerlas.
  * phpMyAdmin solo desde localhost, sin su asistente setup. Los .env y
    los .git de los proyectos ya no se ven por el navegador. Dominios
    desconocidos rechazados también por https.
  * Los volcados se cargan con un usuario temporal que solo puede tocar
    su base (sin DEFINER). Un volcado de una web comprometida no puede
    cambiar otras bases, crear usuarios ni leer o escribir ficheros.
  * MariaDB de XAMPP sin el usuario anónimo ni los permisos de las bases
    test. FTP de XAMPP sin el usuario daemon con la contraseña xampp.
  * El dominio de una tienda que viene de su base solo se falsea si se
    parece al nombre de la carpeta (o ya tiene su vhost).
  * Escrituras como root en los proyectos sin seguir enlaces, descargas
    solo por https, versiones de internet comprobadas, registros solo
    para tu usuario y la ventana sin fichero ventana.py en tu carpeta.
  * Corregido: con dos cambios en httpd.conf (Listen y el vhost de los
    dominios desconocidos) se perdía el primero.

1.36.0 (20 oct 2026)
- Diálogos con más aire: más separación entre textos, campos y
  opciones, y campos algo más altos. En todos los que abre la ventana.
  * Elegir la versión de un proyecto: cada versión es una opción
    separada, con la fecha de su base de datos debajo.

1.35.1 (20 oct 2026)
- Contraseña de administrador: ventana nueva con más aire, como la de
  autorización del sistema: el icono de la aplicación con un candado,
  el texto centrado, un campo más estrecho y más alto y botones grandes.

1.35.0 (20 oct 2026)
- Ventana con los apartados en una barra a la izquierda, como
  Configuración de Ubuntu.
- Cada apartado lleva su icono: los logotipos de PHP, Apache, MariaDB,
  phpMyAdmin, Perl, XAMPP, WordPress y PrestaShop (de Simple Icons, en
  el color de cada marca) o un símbolo del tema.
  * También los componentes de cada versión y los proyectos de Cargar
    proyecto y de Hosts (WordPress o PrestaShop).
- Servicios: una tarjeta por servicio con su logotipo, su estado, sus
  puertos y botones con texto (Reiniciar, Parar, Arrancar). Arriba,
  cuántos están en marcha y «Solo desde este equipo».

1.34.0 (20 oct 2026)
- Cargar proyecto: va en un contenedor hundido, con su título dentro,
  el buscador más grande y más separación con la versión activa.
  * En «Cargado ahora:» solo el proyecto va en verde (el vhost y la
    flecha, en el color normal).
  * El botón «Abrir web.local» es verde con letras blancas.
- Botones: al pasar el ratón sale la mano y cambian un poco de color,
  con una transición corta.

1.33.1 (20 oct 2026)
- Cargar proyecto: botón «Abrir Web.local» (borde y letras verdes) a
  la derecha del proyecto cargado. Abre el vhost en el navegador.

1.33.0 (20 oct 2026)
- Seguridad: una web que visites ya no puede leer phpMyAdmin ni tus
  proyectos desde el navegador haciendo que su dominio apunte a
  127.0.0.1 (DNS rebinding).
  * Nuevo primer vhost del puerto 80 (lvm-dominio-desconocido.conf):
    los dominios que no tienen vhost reciben un 403. Solo pasan localhost, 127.0.0.1 y [::1].
  * web.local y los dominios falseados funcionan igual que antes.
  * La dirección localhost muestra ahora la carpeta htdocs (antes salía
    el proyecto de web.local). phpMyAdmin sigue en localhost/phpmyadmin.
  * Se añade al montar cada versión (o con lvm-instalador asegurar) y
    ya viene en las versiones nuevas.

1.32.0 (20 oct 2026)
- Novedades: la lista de cambios se ve con formato (Markdown): cada
  versión con su título y su fecha, viñetas con sangría, el tema de
  cada cambio en negrita y las rutas y los ficheros en letra de código.
  lvm-instalador novedades la saca en Markdown.
- Se han puesto las tildes que faltaban en la lista de cambios.

1.31.0 (20 oct 2026)
- Seguridad (segundo repaso):
  * Instaladores de XAMPP: se comprueba su sha256, fijada en el
    script, además del md5 (con el md5 solo se puede fabricar otro
    fichero que de lo mismo).
  * ProFTPD: solo se instalan parches que publican su .sha256 (si el
    último no lo tiene, se usa el anterior en vez de fallar).
  * Una rama de PHP más vieja o desconocida ya no recibe sin avisar
    la pila de la última; una más nueva avisa de que no esta probada.
  * XAMPP: los ficheros de lib/php y licenses que podía cambiar
    cualquier usuario pasan a ser solo de root, y temp (sesiones de
    PHP) lleva el bit pegajoso. Al activar la versión o al cerrarla a
    la red; no hace falta reiniciar.
  * Paquete: depende también de sudo, openssl y binutils.

1.30.6 (20 oct 2026)
- Buscar actualizaciones: no encontraba los paquetes 1.30.3 y más
  nuevos (traen el fichero de polkit del mensaje en español, que no
  estaba entre los ficheros admitidos) y decía que no había ninguno.

1.30.5 (20 oct 2026)
- Cargar proyecto: en «Cargado ahora:» el nombre del proyecto va en
  negrita.

1.30.4 (20 oct 2026)
- Cargar proyecto: si la base del proyecto esta en varias versiones,
  la pregunta es «¿Qué versión del proyecto y de PHP quieres
  cargar?» y cada opción muestra la fecha de su copia de la base.
- «Cargado ahora:» va en gris y sin negrita; el proyecto, en verde.

1.30.3 (20 oct 2026)
- Actualizar: la contraseña se pide con un mensaje en español
  («Para instalar la versión nueva de LAMPP Version Manager hace
  falta tu contraseña») en vez del aviso en inglés de pkexec. Se ve a
  partir de la siguiente actualización.

1.30.2 (20 oct 2026)
- Versiones, Cargar proyecto: «Cargado ahora: …» sale en verde y en
  negrita, para ver de un vistazo que proyecto esta activo.

1.30.1 (20 oct 2026)
- Menú (☰): Buscar actualizaciones. Busca en Descargas un
  lvm-instalador_*.deb más nuevo y, si lo hay, muestra su fecha y su
  huella y lo instala (pide la contraseña). Al abrir la ventana ya no
  se busca solo.

1.30.0 (20 oct 2026)
- Versiones: bloque nuevo, Cargar proyecto, el primero de la pestaña.
  Se busca la carpeta del proyecto en /opt/htdocs (se ve también el
  que esta cargado ahora) y se pulsa Cargar: el vhost (web.local)
  apunta a su carpeta y se monta la versión de PHP donde esta su base
  de datos. Si la base esta en varias versiones, o en ninguna, se
  pregunta cual montar (se propone la activa o la de su .php-version).
- El aviso «Se puede entrar desde otros equipos de la red» ya solo
  sale en la pestaña Servicios.

1.29.0 (20 oct 2026)
- Seguridad: Apache, MariaDB y el FTP solo aceptan conexiones de este
  equipo (127.0.0.1 y ::1). XAMPP los deja abiertos a toda la red:
  cualquier equipo de la oficina podía ver los proyectos y entrar por
  FTP con el usuario daemon y la contraseña xampp. Se cambia solo lo
  que falta al montar, arrancar o registrar una versión (copia en
  ~/lvm-copias); las pilas nuevas ya se instalan así. Si algo sigue
  abierto, la pestaña Versiones avisa con un botón «Cerrar a la red».
  En la terminal: lvm-instalador asegurar.
- Pestaña nueva, Servicios (como el panel de XAMPP): Apache, MariaDB y
  el FTP de la versión montada, si están en marcha y si se puede
  entrar desde la red, con botones para arrancar, parar o reiniciar
  cada uno. El FTP ya no arranca con la versión: se arranca aquí
  cuando haga falta. En la terminal: lvm-instalador servicio
  apache|mariadb|ftp arrancar|parar|reiniciar.
- Subir una base: el volcado solo puede llevar SQL. Un .sql manipulado
  ya no puede ejecutar programas en el equipo (\! orden, system) ni
  leer sus ficheros. La línea del modo sandbox se sigue quitando.
- Los vhosts vuelven a ser del administrador (Apache los lee como root
  al arrancar). Editar vhosts abre una copia; al pulsar Aplicar se
  comprueba, se guarda la anterior en ~/lvm-copias, se escribe con la
  contraseña y se recarga Apache. Si Apache no la acepta, se deja
  como estaba. No se admiten ordenes que cambien todo Apache
  (LoadModule, Include, registros con |orden...).
- wp-config.php, parameters.php y var/cache: si en un proyecto son
  enlaces a otra carpeta, no se tocan (con la contraseña se podria
  escribir o borrar un fichero del sistema). Los nombres de bases,
  prefijos y carpetas que traen los proyectos se comprueban antes de
  usarlos en consultas o en los vhosts.
- La contraseña de administrador solo se envia si la pide sudo.
- Actualizar con un .deb de Descargas: ya no se ofrece solo al abrir;
  se busca desde Herramientas y se muestra su fecha y su huella.
- ~/lvm-copias y ~/.lvm-instalador (copias de bases y configuraciones
  de los proyectos) solo son accesibles para tu usuario.

1.28.1 (19 oct 2026)
- Subir una base de datos: el desplegable Proyecto es tan ancho como
  el nombre de carpeta más largo, para verlo entero al elegirlo.
- Al elegir la base se propone el proyecto que se llama como ella
  (wp_mitienda -> dob-wordpress-mitienda, ps_mitienda ->
  dob-prestashop-mitienda), si no hay uno recordado o que ya la use.
  Si se cambia a mano, se respeta.

1.28.0 (19 oct 2026)
- Bases de datos: cada base lleva debajo la fecha y la hora en que se
  importo y su antiguedad (hace 3 días, hace 4 meses...), en la lista
  de cada versión y en el buscador. Las que se suben con la aplicación
  guardan la fecha exacta en ~/.lvm-instalador/importaciones; para las
  demas se muestra cuando cambiaron por última vez sus tablas (al
  importarlas desde phpMyAdmin, por ejemplo), que se ve aunque su
  MariaDB este parado.

1.27.1 (19 oct 2026)
- Tiendas PrestaShop, lo mismo que WordPress en la 1.27.0: al subirle
  una base con Proyecto elegido, y al cargarla si se ha volcado encima
  el código de produccion, su app/config/parameters.php (o
  config/settings.inc.php en las 1.6) pasa a usar la base de la
  carpeta y su prefijo; si sus datos no entran en el MariaDB local,
  root y localhost. El anterior queda en ~/lvm-copias y se vacia la
  cache.
- El wp-config.php que se crea o se rehace lleva WP_SITEURL y WP_HOME
  con la dirección local del proyecto: la del vhost de los proyectos
  tal y como este configurado (https://web.local, http://localhost...)
  o, si el proyecto tiene dominio propio (pestaña Hosts), su dominio.
  Si ya las tiene, se cambia su valor; si no, se añaden delante de los
  datos de la base.

1.27.0 (19 oct 2026)
- Al subir una base de datos, la ventana de la carga termina con un
  check verde grande y el título en verde (antes solo ponia
  Terminado en gris). Igual en el resto de tareas que terminan bien.
- Subir una base de datos: nuevo campo Proyecto. Si es la base nueva de
  un proyecto, se elige su carpeta (se propone sola si se sabe) y la
  base pasa a ser la suya. Si es un WordPress, su wp-config.php se
  rehace con la plantilla de este equipo (la copia del último
  wp-config.php que funciono en local) cambiando solo la base y, si
  hace falta, el prefijo de las tablas. Comando: importar-bd ...
  --proyecto <carpeta>.
- Cargar proyecto en un WordPress con el código de produccion pegado
  encima: comprueba que wp-config.php usa la base asociada a la
  carpeta y que entra en el MariaDB local. Si no, lo rehace con la
  plantilla (sin plantilla: el mismo fichero con root y localhost; sin
  wp-config.php: wp-config-sample.php con claves nuevas). El anterior
  queda en ~/lvm-copias. Comando: wp-config <carpeta> [base].
- La base con la que se carga un proyecto queda asociada a su carpeta.
- La base de cada proyecto ya no se lee de las líneas comentadas de
  wp-config.php (// define( 'DB_NAME', ... )).

1.26.0 (19 oct 2026)
- Tiendas PrestaShop recien clonadas: su app/config/parameters.php no
  va en el repositorio y quedaba vacio (\"install\" directory is
  missing). Cargar proyecto lo crea con la base cargada en local (la
  del buscador, la recordada o ps_<final de la carpeta>), el prefijo de
  sus tablas y claves nuevas, y guarda una copia en
  ~/.lvm-instalador/prestashop para reponerla igual si se pierde. Si ya
  tiene base, no se toca. Ahora se reconoce como tienda aunque no tenga
  configuración, por sus carpetas o por \"prestashop\" en el nombre.
- La primera vez que se carga una tienda (y al crear su parameters.php)
  se vacia su var/cache, que en las 1.7 da error 500 con la cache de
  otro equipo. Si no tiene var/cache no pasa nada.
- Bases de datos: botón para vaciar la cache de la tienda en las bases
  ps_ (lista y buscador). Comando: vaciar-cache <carpeta> | --bd <base>.
- Los vhosts que se crean llevan ServerAdmin con tu correo (el de git,
  user.email; si no hay, usuario@localhost).

1.25.1 (13 oct 2026)
- Hosts, Nuevo proyecto: los campos de carpeta y base de datos tienen un
  ancho fijo, como los de Bases de datos (los nombres largos se cortan
  con ...). La lista de carpetas ya no lleva el dominio al lado: si la
  carpeta elegida ya tiene uno, se indica debajo de Carpeta. La pestaña
  ya no se ensancha.

1.25.0 (13 oct 2026)
- La pestaña Instalar pasa a Versiones, debajo de Instaladas, con el
  título Instalar nuevas versiones de PHP. La ventana queda con cuatro
  pestañas: Versiones, Bases de datos, Hosts y Herramientas.
- Los textos explicativos bajo los títulos de cada bloque se cambian
  por un símbolo de información junto al título: al pasar el raton por
  encima se muestra la explicacion.

1.24.0 (13 oct 2026)
- Hosts, Nuevo proyecto con dominio falseado: la carpeta se elige de una
  lista con las de /opt/htdocs (por ejemplo, la de un git clone; las que
  ya tienen dominio lo indican) o se crea una nueva con +. La base de
  datos, igual: las de la versión activa, una nueva con + o ninguna. Si
  la carpeta trae su configuración (wp-config.php, PrestaShop, .env), se
  propone su base de datos.
- Herramientas: Registro de errores muestra solo /opt/lampp/logs/error_log.
  Nuevo Comandos de lvm-instalador: todos los comandos y que hace cada
  uno (lo mismo que lvm-instalador --ayuda, ahora completo y por temas).

1.23.0 (13 oct 2026)
- Solo la versión montada queda en memoria. Al montar otra, al pulsar
  Parar o al parar desde la terminal, se comprueba que no quede ningún
  proceso de LAMPP (Apache, MariaDB, ProFTPD, PHP-FPM) y se cierran los
  que sigan vivos: primero de forma normal (MariaDB guarda todo antes
  de salir) y, si no hacen caso, a la fuerza. Antes de arrancar se
  cierran los de otras versiones, que ocuparian los puertos.
  Venia del lvm original: el lampp de XAMPP solo cierra lo que esta en
  sus .pid, y todos los procesos se llaman /opt/lampp/bin/... sea cual
  sea la versión, así que los que se quedaban no se distinguian.
- Versiones avisa si hay procesos de otras versiones en memoria, con un
  botón para cerrarlos. Comandos: lvm-instalador procesos (de que
  versión es cada uno) y lvm-instalador cerrar-procesos [--todos].

1.22.0 (13 oct 2026)
- Hosts: Nuevo proyecto con dominio falseado. Con el dominio y la base
  de datos de produccion: crea la carpeta en /opt/htdocs, su vhost http
  y https con certificado, la base vacia en la versión activa y falsea
  el dominio, para construirlo en local y subirlo después tal cual.
  Cargar proyecto vuelve a falsear su dominio. Comando:
  lvm-instalador nuevo-dominio <dominio> <carpeta> [base].
- Herramientas: Registros de errores de la versión montada (error_log
  y los de los vhosts), con Ver el final (las últimas líneas, sin
  abrir ficheros enormes) y Abrir. Registros pasa a llamarse Registros
  de instalaciones. Se quita el panel en la terminal (sigue en el menú).
- Los certificados nuevos son CA:FALSE (Apache ya no avisa con AH01906).

1.21.0 (13 oct 2026)
- Tiendas PrestaShop: al cargar el proyecto se lee su dominio de la base
  (tabla shop_url) y se crea lo que falte, como en el manual de XAMPP:
  su certificado autofirmado en /etc/ssl y su vhost http y https en
  /opt/config/httpd-vhosts.conf (con copia en ~/lvm-copias). Lo que ya
  existe no se toca. Su dominio se falsea en /etc/hosts (127.0.0.1).
- Al cargar cualquier otro proyecto, los dominios de los vhosts dejan
  de estar falseados y vuelven a llevar a la web real. localhost,
  web.local y el nombre del equipo no se tocan nunca.
- Pestaña nueva, Hosts: el dominio falseado arriba, con un interruptor
  encendido y el botón Abrir; debajo, los demas dominios de los vhosts
  con su interruptor para falsearlos o no a mano.
  Comando: lvm-instalador hosts-falsear <dominio> si|no.
- Apache con tu usuario (User/Group, como en el manual): al cargar un
  proyecto y al registrar un XAMPP se añade si la versión no lo tiene.
  Al registrar un XAMPP también se activan los vhosts y /opt/htdocs
  pasa a ser tuyo si no lo era.

1.20.0 (8 oct 2026)
- Pestaña nueva, Herramientas (la última), con lo que se usa de vez en
  cuando: editar vhosts y hosts, registrar un XAMPP de /opt/lampp, abrir
  las carpetas de proyectos, copias y registros, buscar un .deb más
  nuevo en Descargas, volver a crear el icono del menú, el panel en la
  terminal, Novedades y Acerca de. El menú sigue teniendo lo de siempre.

1.19.0 (8 oct 2026)
- Editar vhosts pasa al menú (debajo de Abrir phpMyAdmin), junto a uno
  nuevo, Editar hosts: abre una copia de /etc/hosts en el editor y, al
  pulsar Aplicar, la escribe con sudo (el anterior se guarda en
  ~/lvm-copias; no deja guardar uno sin la línea de localhost).
  Comando: lvm-instalador hosts.
- Versión activa: arrancar en verde, reiniciar en azul y parar en rojo.
- XAMPP y Pila propia, en gris como el resto del texto de la versión.
- Las bases de datos se descargan en .zip (un .sql dentro); se pueden
  volver a cargar tal cual. exportar-bd acepta .zip, .sql y .sql.gz.
- Buscador de bases: un punto verde marca las de la versión activa (ya
  no pone Activa) y no hay botón Activar. Cargar proyecto lo carga
  directamente en la versión de esa base; si hay que cambiar de PHP,
  avisa antes de parar la actual y activar la del proyecto.
- Instalar: Estable, Solo seguridad y Sin soporte son texto de color,
  sin fondo.

1.18.0 (8 oct 2026)
- Botón Editar vhosts en la versión activa (pestaña Versiones): abre
  /opt/lampp/etc/extra/httpd-vhosts.conf con el editor de textos. Si el
  fichero es de root, pide la contraseña una vez y lo hace tuyo para
  poder guardarlo. Después, Reiniciar aplica los cambios.
- Comando nuevo: lvm-instalador vhosts (lo abre en la terminal).

1.17.1 (8 oct 2026)
- Acerca de y Novedades vuelven a mostrar su texto: en la 1.17.0 unas
  comillas sin escapar cortaban el texto y salia un error de la línea
  3732 en cada comando.
- El empaquetador del .deb comprueba que el script no da errores al
  cargarse y que Novedades empieza por la versión del paquete.

1.17.0 (8 oct 2026)
- Actualizar con un .deb: al abrir la ventana, si en Descargas hay un
  lvm-instalador_<version>_all.deb más nuevo que la versión instalada,
  ofrece \"Actualizar a la <version>\". Pide la contraseña en una ventana
  (pkexec), lo instala y vuelve a abrir la ventana con la versión nueva.
  El Centro de aplicaciones no ofrece actualizar un .deb suelto.

1.16.0 (8 oct 2026)
- Cargar proyecto sin vhost para proyectos (equipos sin web.local): ya no
  se queda en un aviso. Crea el vhost web.local (http y https, sin cache
  en el navegador) en /opt/config/httpd-vhosts.conf, su certificado
  autofirmado en /opt/config/ssl y su línea en /etc/hosts, y lo apunta al
  proyecto. La ventana lo explica antes de cargar.
- Dialogos más anchos: el texto ya no se parte en una columna estrecha.
- Acerca de: solo el nombre, la versión, que es (gestor de paquetes
  Apache, MariaDB, PHP, Perl, phpMyAdmin y ProFTPD al estilo XAMPP de
  forma independiente), la firma y el año.
- Novedades: ventana más grande y solo con la lista de cambios (comando
  lvm-instalador novedades).

1.15.2 (8 oct 2026)
- La ventana se abre con el alto necesario para ver entera la pestaña
  Bases de datos (sin pasar del alto de la pantalla): lee los datos
  antes de mostrarse y mide esa pestaña.

1.15.1 (8 oct 2026)
- Cargar proyecto recarga Apache (recarga suave, menos de un segundo) si
  no cambia de versión: cada proceso de PHP recordaba durante 120 s a
  donde apuntaba web.local y seguia sirviendo el proyecto anterior.

1.15.0 (8 oct 2026)
- Buscador de bases de datos: botón \"Cargar proyecto\". Busca la carpeta
  de /opt/htdocs cuya configuración (wp-config.php, PrestaShop o .env)
  usa esa base, activa su versión de PHP y apunta el enlace del vhost
  (web.local) a esa carpeta. Si hay varias carpetas o ninguna, la eliges
  tu y se recuerda (~/.lvm-instalador/proyectos). Si la base esta en
  varias versiones o el .php-version del proyecto pide otra, pregunta
  cual montar. Comando: cargar-proyecto <carpeta> [version].
- \"Activa\" ya no parece un botón: es texto verde junto al nombre de la
  base de datos y de la versión activa.

1.14.0 (8 oct 2026)
- Bases de datos: buscador que filtra mientras escribes y dice en que
  versión (y con que PHP) esta cada base, con un botón para activarla o
  para elegirla como destino si ya es la activa.
- Al cargar una copia en una base que también existe en otra versión,
  avisa de donde esta y pregunta si cargarla también en la activa. Al
  crear una base con un nombre que ya existe en otra versión, lo indica.
- Descargar una copia (.sql.gz o .sql) de cualquier base de cualquier
  versión, desde su lista o desde el buscador. Si esa versión no esta en
  marcha, se arranca un MariaDB temporal sin red (pide sudo).
  Comando: exportar-bd <base> <fichero> [version].
- El botón de phpMyAdmin dice \"Abrir phpMyAdmin\".
- La copia previa al borrar una base ya funciona con el MariaDB 10.4 de
  XAMPP (no se piden eventos y, si mysql.proc es de un MariaDB antiguo,
  se copia sin rutinas).

1.13.2 (8 oct 2026)
- Bases de datos: el selector de la base de destino dice \"Elige una
  base de datos\" (como en el Mac) mientras no se ha elegido ninguna.

1.13.1 (8 oct 2026)
- Ventana, \"Otro parche concreto...\": los parches ya se pueden elegir
  (antes la lista no dejaba seleccionar ninguno y \"Añadir\" seguia
  desactivado). La fila elegida se marca en verde; con doble clic se
  añade directamente.

1.13.0 (7 oct 2026)
- Si falla una instalación, la ventana muestra el botón \"Ver el log
  del error\": un informe con el sistema, el compilador, lo que se
  instalaba, el paso que ha fallado, sus primeros errores, el final de
  su log y, si fallo la configuración, lo último de su config.log. Se
  copia entero con \"Copiar todo\" para buscar la solucion. También se
  guarda como informe-error.txt junto a los logs de la compilación.

1.12.0 (7 oct 2026)
- Instalar: cada rama de PHP indica su estado según php.net: Estable
  (correcciones de errores y de seguridad), Solo seguridad (con la
  fecha hasta la que tendrá parches) o Sin soporte. En \"Otro parche
  concreto\" se ve el estado de la rama y cual es el último parche.
- Panel: la misma información en la lista de ramas.

1.11.1 (7 oct 2026)
- Ventana: la pestaña Bases de datos pasa a ser la segunda e Instalar
  la tercera (lo que más se usa va primero).

1.11.0 (7 oct 2026)
- Cargar bases de datos: también desde un .zip (como los que se
  descargan del servidor), que se descomprime al vuelo, sin ocupar
  espacio en disco.
- Las copias que empiezan por /*M!999999\\- enable the sandbox mode */
  (mariadb-dump moderno) ya se cargan: esa línea se quita al vuelo,
  porque el MariaDB de XAMPP no la entiende (\"Unknown command\").

1.10.1 (7 oct 2026)
- Ventana: el botón Parar hace lo mismo que \"lvm disable\": para la
  versión y quita el enlace /opt/lampp, así que php deja de responder
  en la terminal hasta que actives una versión. Sale también con la
  versión activa ya parada.

1.10.0 (7 oct 2026)
- Ventana, pestaña Bases de datos: nuevo apartado \"Subir o actualizar
  una base de datos\". Eliges el fichero .sql o .sql.gz y la base de la
  versión activa, y una barra muestra lo cargado, el tiempo y lo que
  queda, como pv. Opción para vaciar la base antes.
- Crear y borrar bases de datos de la versión activa, con confirmacion.
  Al borrar una base con tablas avisa de que se elimina todo y es
  irreversible, y ofrece guardar antes una copia en ~/lvm-copias (sin
  copia hay que escribir el nombre de la base).
- Comandos importar-bd <fichero> <base> [--crear] [--vaciar],
  crear-bd <base> y borrar-bd <base> [--copia].
- Las bases con guion u otros simbolos en el nombre ya se ven bien
  (antes salian como wp_mi@002dweb).

1.9.1 (7 oct 2026)
- El icono creado por la 1.8 o anteriores abria el panel de la terminal
  en vez de la ventana: ahora abre la ventana.
- Los errores de la ventana abierta desde el menú se guardan en
  ~/.lvm-instalador/ventana.log.
- El acceso del menú funciona aunque la carpeta tenga espacios.

1.9.0 (7 oct 2026)
- Ventana gráfica (GTK 3, desde Ubuntu 20.04): pestañas Versiones,
  Instalar y Bases de datos, barra de progreso y la contraseña de sudo
  en una ventana. El acceso del menú abre la ventana; el panel de la
  terminal sigue con lvm-instalador.
- Comandos nuevos: ventana, arrancar, parar, reiniciar y
  desinstalar <version> --copia.

1.8.1 (7 oct 2026)
- Si el icono estaba anclado en el dock con su nombre antiguo, se cambia
  por el nuevo (el dock seguia abriendo la ruta vieja).

1.8.0 (7 oct 2026)
- El comando vuelve a ser lvm-instalador y el archivo lvm-instalador.sh
  (LAMPP Version Manager). El comando antiguo pvm-instalador se quita.

1.7.0 (7 oct 2026)
- Nuevo nombre: LAMPP Version Manager. El comando sigue siendo
  pvm-instalador.
- \"Acerca de\" explica por que existe: un XAMPP virtual por cada
  versión de PHP, ya que XAMPP no saca versiones nuevas.

1.6.0 (6 oct 2026)
- \"Cambiar la versión activa\" es la primera opción del menú.
- Actualizar: una versión al día no se puede actualizar; avisa en verde.
- Número de versión debajo de la firma y opción \"Acerca de\".

1.5.0 (6 oct 2026)
- Nuevo nombre: PHP Version Manager. Comando pvm-instalador.
- La versión activa aparece en verde en el panel.

1.4.0 (6 oct 2026)
- PHP 7.4 a 8.5 y cualquier parche publicado, en su propia carpeta.
- PHP 7.4 y 8.0 con OpenSSL 1.1.1w; 7.4 a 8.1 con ICU 72.1.

1.3.0 (6 oct 2026)
- Icono de PHP en el menú de aplicaciones y texto de bienvenida.

1.2.0 (5 oct 2026)
- Equipos ARM: MariaDB se compila desde el código fuente.
- Aviso si se acepta la lista sin marcar ninguna versión.

1.1.0 (5 oct 2026)
- Logo de hexer y firma; el acceso abre la terminal a 100x32.
- Barra de progreso en verde durante las instalaciones.

1.0.0 (5 oct 2026)
- Pila propia por versión de PHP, sin depender de un XAMPP.
- Actualizar versiones con los últimos parches de su rama.

0.5.0 (5 oct 2026)
- Cada versión de PHP nueva tiene sus propias bases de datos.

0.4.0 (5 oct 2026)
- Tablas con las versiones de todos los componentes.
- Pantalla de bases de datos y desinstalador con copia de seguridad.

0.3.0 (4 oct 2026)
- Instalador independiente con panel: catalogo de XAMPP, PHP nuevos,
  cambio de versión activa, modo simulación y accesos.

0.2.0 (4 oct 2026)
- Asistente por pasos para instalar versiones de PHP.

0.1.0 (4 oct 2026)
- Primera versión: PHP 8.4 con PHP-FPM sobre una copia de XAMPP 8.2.4."

function about_text() {
    echo "$APP_NAME $APP_VERSION\n$SIGNATURE\n\n$ABOUT_TEXT"
}

# Lista de versiones de ABOUT_TEXT en Markdown: «## version · fecha», viñetas (las de «  *», dentro
# de la anterior) en una sola linea, el tema antes de «:» en negrita y rutas y ficheros como codigo
CHANGES_MD_PY='
import re, sys

VERSION = re.compile(r"^(\d+\.\d+\.\d+) \((.+)\)$")
# Rutas (/opt/..., ~/...) y nombres de fichero: en letra de codigo
CODE = re.compile(r"(?<![\w`])((?:~/|/)[\w.*<>@+-]+(?:/[\w.*<>@+-]*)*|[\w*<>-]+(?:\.[\w*<>-]+)*"
                  r"\.(?:php|conf|cnf|deb|dmg|sql|zip|gz|desktop|policy|md|py|sh|log|pid|run|sha256)\b)")


def inline(text):
    text = CODE.sub(lambda m: "`%s`" % m.group(1), text)
    # Un punto o una coma del final de la frase queda fuera del codigo
    return re.sub(r"`([^`]*?)([.,;:]+)`", r"`\1`\2", text)


def bullet(text, depth):
    # «Tema: explicacion» o «Tema:» -> el tema en negrita
    m = re.match(r"^([^:«`/]{2,45}):(\s+(.*))?$", text)
    if m:
        text = "**%s:**%s" % (m.group(1), " " + m.group(3) if m.group(3) else "")
        return "  " * depth + "- " + text[:text.index(":**") + 3] + inline(text[text.index(":**") + 3:])
    return "  " * depth + "- " + inline(text)


def convert(plain):
    out, item, depth = [], None, 0

    def flush():
        nonlocal item
        if item is not None:
            out.append(bullet(item, depth))
            item = None

    for line in plain.split("\n"):
        m = VERSION.match(line)
        if m:
            flush()
            if out and out[-1] != "":
                out.append("")
            out.append("## %s · %s" % (m.group(1), m.group(2)))
            out.append("")
        elif line.startswith("- "):
            flush()
            item, depth = line[2:].strip(), 0
        elif line.startswith("  * "):
            flush()
            item, depth = line[4:].strip(), 1
        elif line.strip() and item is not None:
            item += " " + line.strip()
        elif not line.strip():
            flush()
        else:
            flush()
            out.append(inline(line.strip()))
    flush()
    return "\n".join(out).strip() + "\n"


sys.stdout.write(convert(sys.stdin.read()))
'

# Solo la lista de versiones con sus cambios, en Markdown (ventana "Novedades")
function changes_text() {
    echo -e "$ABOUT_TEXT" | sed -n '/^VERSIONES$/,$p' | tail -n +3 | python3 -I -c "$CHANGES_MD_PY"
}

function panel_about() {
    ui_msg "$(about_text)"
}

function panel() {
    offer_command_install

    while true; do
        local options=()

        options+=(
            "activar" "Cambiar la version activa"
            "instalar" "Instalar versiones (XAMPP completos y PHP nuevos)"
        )

        if [ -e /opt/lampp ] && [ ! -L /opt/lampp ]; then
            options+=("registrar" "Registrar el XAMPP sin gestionar de /opt/lampp (necesario para instalar XAMPP)")
        fi

        options+=(
            "estado" "Ver versiones instaladas"
            "bases" "Ver bases de datos de cada version"
            "desinstalar" "Desinstalar versiones"
        )

        local dir
        for dir in $(lampp_dirs); do
            if is_fpm_install "$dir"; then
                options+=("actualizar" "Actualizar versiones de PHP")
                break
            fi
        done

        options+=(
            "acerca" "Acerca de (version y cambios)"
            "salir" "Salir"
        )

        local header="Bienvenido al gestor de versiones LAMPP y PHP para Linux.\n"
        header+="Instala nuevas versiones de PHP o activa la que necesites.\n\n"
        # La version activa va en verde (con ventanas la pinta wt encima del texto)
        header+="Version activa: "
        local active=$(active_dir) active_text=""
        if [ -n "$active" ]; then
            active_text="lampp-${active#/opt/lampp-} (PHP $(php_version "$active"))"
            if [ "$UI" == "text" ] && [ -t 2 ]; then
                header+="\033[1;32m$active_text\033[0m"
            else
                header+=$active_text
            fi
        else
            header+="ninguna"
        fi
        [ "$DRY" -eq 1 ] && header+="\nMODO SIMULACION: no se hace ningun cambio"
        header+="\n\n¿Que quieres hacer?"

        # Firma abajo a la derecha de la cabecera, del ancho de la lista de opciones
        local cols=$(tput cols 2> /dev/null || echo 80)
        local sign_w=72
        (( sign_w > cols - 6 )) && sign_w=$(( cols - 6 ))
        if [ "$UI" == "text" ]; then
            header=$(with_signature "$header" $sign_w)
            header+="\n$(printf '%*s' $(( sign_w - ${#APP_VERSION} - 1 > 0 ? sign_w - ${#APP_VERSION} - 1 : 0 )) "")v$APP_VERSION"
        fi

        local choice
        choice=$(WT_GREEN=$active_text ui_menu "$header" "activar" "${options[@]}") || break

        case "$choice" in
            registrar) panel_register ;;
            instalar) panel_install ;;
            activar) panel_use ;;
            estado) ui_msg "$(status_text)" ;;
            bases) panel_databases ;;
            desinstalar) panel_remove ;;
            actualizar) panel_rebuild ;;
            acerca) panel_about ;;
            salir) break ;;
        esac
    done

    [ "$UI" == "whiptail" ] && clear

    return 0
}

# ===========================================================================
# Ventana (interfaz grafica con GTK 3)
# ===========================================================================

# La ventana es un programa en Python (GTK 3 y Python 3.8: funciona desde Ubuntu 20.04 sin instalar
# nada) que va dentro de este archivo, en gui_source. "lvm-instalador ventana" lo escribe en
# ~/.lvm-instalador/ventana.py y lo abre. La ventana no repite la logica del instalador: llama a
# este script con los comandos gui-* (datos en lineas "TIPO|campo|...") y con los de siempre (use,
# instalar, actualizar, desinstalar...) dentro de una pseudoterminal, para que sudo funcione igual
# que en la terminal. La contraseña la pide la ventana.
GUI_FILE="$LOG_DIR/ventana.py"
# Identificador de la ventana (el dock la relaciona con el acceso por StartupWMClass)
GUI_APP_ID="dev.hexer.LamppVersionManager"

function gui_available() {
    python3 -I -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk' 2> /dev/null
}

# Para la ventana: N|version|fecha|sha256|ruta del paquete .deb de lvm-instalador mas nuevo que esta
# version que haya en la carpeta de descargas (el Centro de aplicaciones no ofrece actualizar un
# .deb suelto). Solo lo busca cuando se pide (Herramientas): se instala como root, y cualquier web
# puede dejar un fichero en Descargas. Solo vale un paquete tuyo, sin enlaces y que solo lleve los
# ficheros de lvm-instalador, de root y con sus permisos (755 o 644).
PACKAGE_FILES_PY='
import posixpath, sys, tarfile
files = {"opt/lvm-instalador/lvm-instalador.sh", "opt/lvm-instalador/lvm-actualizar",
         "usr/share/applications/lampp-version-manager.desktop",
         "usr/share/icons/hicolor/256x256/apps/lampp-version-manager.png",
         "usr/share/polkit-1/actions/dev.hexer.lvm-instalador.policy"}
dirs = {""}
for f in files:
    parts = f.split("/")
    for i in range(1, len(parts)):
        dirs.add("/".join(parts[:i]))
try:
    with tarfile.open(fileobj=sys.stdin.buffer, mode="r|") as tar:
        for m in tar:
            name = (m.name[2:] if m.name.startswith("./") else m.name).rstrip("/")
            name = "" if name == "." else name
            if name.startswith("/") or ".." in name.split("/"):
                sys.exit(1)
            if not ((m.isdir() and name in dirs) or (m.isreg() and name in files)):
                sys.exit(1)
            exe = name in ("opt/lvm-instalador/lvm-instalador.sh", "opt/lvm-instalador/lvm-actualizar")
            if m.uid != 0 or m.gid != 0 or m.uname not in ("root", "") or m.gname not in ("root", "") or (m.mode & 0o7777) != (0o755 if m.isdir() or exe else 0o644):
                sys.exit(1)
except tarfile.TarError:
    sys.exit(1)
'
function gui_package() {
    local dir f v best="" best_v=$APP_VERSION real

    command -v dpkg-deb > /dev/null || return 0
    for dir in "$(xdg-user-dir DOWNLOAD 2> /dev/null)" "$HOME/Descargas" "$HOME/Downloads"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/lvm-instalador_*_all.deb; do
            [ -f "$f" ] && [ ! -L "$f" ] && [ -O "$f" ] || continue
            [ "$(dpkg-deb -f "$f" Package 2> /dev/null)" == "lvm-instalador" ] || continue
            # Solo los ficheros de lvm-instalador, normales (sin enlaces ni especiales): lo mismo
            # que comprueba como root lvm-actualizar antes de instalarlo
            dpkg-deb --fsys-tarfile "$f" 2> /dev/null | python3 -I -c "$PACKAGE_FILES_PY" || continue
            v=$(dpkg-deb -f "$f" Version 2> /dev/null)
            [ -n "$v" ] && dpkg --compare-versions "$v" gt "$best_v" && best=$f best_v=$v
        done
    done
    if [ -n "$best" ]; then
        real=$(readlink -f "$best")
        echo "N|$best_v|$(date -r "$real" '+%d/%m/%Y %H:%M')|$(sha256sum "$real" | cut -d' ' -f1)|$real"
    fi

    return 0
}

function gui_open() {
    if ! gui_available; then
        echo "La ventana necesita GTK 3 para Python. Instalalo con: sudo apt install python3-gi gir1.2-gtk-3.0"
        echo "Mientras tanto puedes usar el panel de la terminal: lvm-instalador"

        return 1
    fi

    if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        echo "No hay sesion grafica. Usa el panel de la terminal: lvm-instalador"

        return 1
    fi

    mkdir -p -m 700 "$LOG_DIR"
    # El codigo de la ventana va por la entrada de python, sin fichero en tu carpeta que otro
    # programa pudiera cambiar entre que se escribe y se abre (el ventana.py de antes se borra)
    rm -f "$GUI_FILE" "$GUI_FILE.tmp"
    cmp -s "$ICON_FILE" <(base64 -d <<< "$ICON_PNG_B64" 2> /dev/null) || install_icon
    [ "$DRY" -eq 0 ] && update_launchers

    # Abierta desde el menu no hay terminal donde ver los errores: van a ventana.log
    [ -t 2 ] || exec 2> "$LOG_DIR/ventana.log"
    # Con su ruta: el PATH de la sesion puede llevar delante carpetas tuyas (~/.local/bin)
    LVM_SIMULAR=$DRY exec /usr/bin/python3 -I - "$SELF" < <(gui_source)
}

# Datos de la ventana:
#   M|nombre|version|firma
#   A|activa|en marcha (1/0)|/opt/lampp sin registrar (1/0)|binarios x86_64 (1/0)|acceso del menu (1/0)
#   V|carpeta|php|apache|mariadb|proftpd|perl|phpmyadmin|tipo|bases de|motivo para no desinstalar
#   D|carpeta|base de datos|fecha|tipo (i: importada con lvm-instalador, c: ultimo cambio de tablas)
#   Z|procesos de LAMPP que sobran en memoria (de otras versiones)
#   Y|version montada|bytes del registro de errores: sus tablas del sistema de MariaDB son antiguas
function gui_data() {
    local active=$(active_dir) dir name owner blocker kind

    echo "M|$APP_NAME|$APP_VERSION|$SIGNATURE"
    echo "A|${active#/opt/lampp-}|$(lampp_running && echo 1 || echo 0)|$([ -e /opt/lampp ] && [ ! -L /opt/lampp ] && echo 1 || echo 0)|$(native_binaries && echo 1 || echo 0)|$([ -f "$LAUNCHER" ] && echo 1 || echo 0)"
    echo "H|$ACTIVE_VHOSTS|$HOSTS_FILE"
    # Procesos de LAMPP en memoria que no son de la version montada
    local stray=$(stray_summary)
    [ -n "$stray" ] && echo "Z|$stray"
    # Servicios de la version montada a los que se puede entrar desde otros equipos de la red
    local exposed=$(exposed_summary)
    [ -n "$exposed" ] && echo "N|$exposed"
    # Versiones que, si se arrancan a mano, quedarian abiertas a la red (o con el FTP de fabrica)
    local open_versions=$(unsecured_versions)
    [ -n "$open_versions" ] && echo "U|$open_versions"
    # Tablas del sistema de MariaDB antiguas en la version montada (llenan su registro de errores)
    if db_system_outdated; then
        local err_log=$(db_error_log "$active")
        echo "Y|${active#/opt/lampp-}|$([ -n "$err_log" ] && stat -c %s "$err_log" 2> /dev/null || echo 0)"
    fi
    # Certificados de proyectos en los que confia todo el equipo: C|dominio|motivo y A|CA
    # y G|dominio: proyectos https cuyo certificado propio aun no acepta el navegador, y Q|dominio:
    # los que acepta y ya no deberia (una tienda que ya no esta falseada)
    cert_audit | awk -F'|' '$1 == "C" { print "C|" $2 "|" $5 } $1 == "A" && !seen[$2]++ { print "W|" $2 }
        $1 == "T" && $5 == "0" { print "G|" $2 } $1 == "U" && !gone[$2]++ { print "Q|" $2 }
        $1 == "S" { n = split($2, a, "/"); print "C|" a[n] " (sin usar)|sistema" }'

    for dir in $(lampp_dirs); do
        name=${dir#/opt/lampp-}
        kind=XAMPP
        is_fpm_install "$dir" && kind=sobre
        is_stack_install "$dir" && kind=propia
        owner=$(data_owner "$dir")
        owner=${owner:-$name}
        blocker=$(remove_blocker "$name")
        blocker=${blocker//\\n/ }
        echo "V|$name|$(stack_fields "$dir")|$kind|$owner|${blocker//|/ }"
        db_dates "/opt/lampp-$owner/var/mysql" | sed "s/^/D|$name|/"
    done
}

# Ramas de PHP para instalar (consulta php.net):
#   B|rama|ultimo parche|con soporte (1/0)|MariaDB|Perl|estado|carpeta|estado en php.net|fin del soporte
#     activo|fin de los parches de seguridad (de php_branch_states; vacios si no se pudo consultar)
#     estado: nueva (se instala en lampp-<carpeta>), instalada (en lampp-<carpeta>),
#     actualizable (lampp-<rama> tiene un parche anterior) o existe (ya hay otra cosa en esa carpeta)
#     ... |fecha del ultimo parche (AAAA-MM-DD)|seguridad (1 si php.net lo marca como parche de seguridad)
#   X|carpeta|release|php|instalado (1/0)          (catalogo de XAMPP, solo en equipos x86_64)
function gui_branches() {
    local releases=$(php_releases) supported=$(php_supported) branch latest have folder state sup b
    local states=$(php_branch_states) st all=$(php_all_releases) date sec

    if [ -z "$releases" ]; then
        echo "ERROR|No se ha podido consultar php.net. Comprueba la conexion a internet."

        return 1
    fi

    while read -r branch latest; do
        read -r -a b <<< "$(stack_branches "$branch")"
        sup=0
        grep -qxF "$branch" <<< "$supported" && sup=1
        have=$(php_installed_in "$latest")
        if [ -n "$have" ]; then
            state=instalada folder=${have#/opt/lampp-}
        elif is_fpm_install "${TEST_DIR:-/opt}/lampp-$branch"; then
            state=actualizable folder=$branch
        else
            folder=$(item_folder "$(php_item "$latest" "$latest")")
            state=nueva
            [ -e "${TEST_DIR:-/opt}/lampp-$folder" ] && state=existe
        fi
        st=$(grep "^$branch|" <<< "$states" | cut -d'|' -f2-)
        # (siempre tres campos, aunque no se haya podido consultar: van despues la fecha y la marca)
        [ -z "$st" ] && st="||"
        read -r _ date sec <<< "$(awk -v v="$latest" '$1 == v {print; exit}' <<< "$all")"
        [ "$sec" == "seguridad" ] && sec=1 || sec=0
        echo "B|$branch|$latest|$sup|${b[1]}|${b[3]}|$state|$folder|$st|${date:--}|$sec"
    done <<< "$releases"

    if native_binaries; then
        local entry release php
        for entry in "${XAMPP_CATALOG[@]}"; do
            IFS='|' read -r folder release php _ <<< "$entry"
            echo "X|$folder|$release|$php|$([ -e "/opt/lampp-$folder" ] && echo 1 || echo 0)"
        done
    fi
}

# Parches de una rama: P|version|fecha|carpeta|estado (nueva, instalada o existe)|seguridad (1/0)
function gui_patches() {
    local branch=$1 latest version date item folder state sec

    latest=$(php_patches "$branch" | head -1 | cut -d' ' -f1)
    if [ -z "$latest" ]; then
        echo "ERROR|No se ha podido consultar php.net. Comprueba la conexion a internet."

        return 1
    fi

    while read -r version date sec; do
        folder=$(item_folder "$(php_item "$version" "$latest")")
        state=nueva
        if [ -n "$(php_installed_in "$version")" ]; then
            state=instalada
        elif [ -e "${TEST_DIR:-/opt}/lampp-$folder" ]; then
            state=existe
        fi
        echo "P|$version|$date|$folder|$state|$([ "$sec" == "seguridad" ] && echo 1 || echo 0)"
    done < <(php_patches "$branch")
}

# ¿Esta al dia una version de PHP? si|<php> / no|<php nuevo> / parche / no-php / error
function gui_up_to_date() {
    local version=$1
    local dir=${TEST_DIR:-/opt}/lampp-$version

    if ! is_fpm_install "$dir"; then
        echo "no-php"

        return 0
    fi

    local php=$(stack_fields "$dir" | cut -d'|' -f1)
    if [ "$version" != "${php%.*}" ]; then
        echo "parche"

        return 0
    fi

    local full=$(rebuild_version "$dir" "$(php_releases)")
    if [ -z "$full" ]; then
        echo "error"
    elif is_stack_install "$dir" && [ "$(stack_fields "$dir")" == "$(stack_versions "$full")" ]; then
        echo "si|$full"
    else
        echo "no|$full"
    fi
}

# ===========================================================================
# Cargar bases de datos en la version activa
# ===========================================================================

# El cliente /opt/lampp/bin/mysql lee el my.cnf de la version activa (socket y puerto). Si root tiene
# contraseña, se pasa en la variable MYSQL_PWD
DB_SYSTEM="information_schema|mysql|performance_schema|phpmyadmin|sys|test"
# Para pruebas se puede usar otro cliente (por ejemplo uno contra un MariaDB temporal)
DB_CLIENT=${LVM_BD_CLIENTE:-/opt/lampp/bin/mysql}
# El cliente y mysqldump de XAMPP leen tambien ~/.my.cnf y $MYSQL_HOME/my.cnf, que cualquier programa
# tuyo puede preparar (plugin-dir/default-auth les hacen cargar una biblioteca) y se ejecutan en la
# terminal de la tarea, con el permiso de sudo recordado: siempre sin esos ficheros
DB_SAFE=(/usr/bin/env -u MYSQL_HOME -u MARIADB_HOME HOME=/nonexistent)

# ¿Se puede cargar en la version activa? ok|carpeta|version de MariaDB / clave|carpeta / no|motivo
function gui_db_check() {
    local active=$(active_dir)
    if [ -z "$active" ]; then
        echo "no|No hay ninguna versión activa."

        return 0
    fi

    local folder=${active#/opt/lampp-} out
    if [ ! -x "$DB_CLIENT" ]; then
        echo "no|lampp-$folder no tiene el cliente de MariaDB (bin/mysql)."

        return 0
    fi

    if out=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e 'SELECT VERSION()' < /dev/null 2>&1); then
        echo "ok|$folder|${out%%-*}"
    elif [[ "$out" == *1045* ]] || [[ "$out" == *"Access denied"* ]]; then
        echo "clave|$folder"
    else
        echo "no|El MariaDB de lampp-$folder no está en marcha. Arráncalo en la pestaña Versiones."
    fi
}

# Conexion con el MariaDB activo: deja en DB_FOLDER la carpeta de la version activa y en DB_VERSION
# la de MariaDB. Si no se puede, explica por que (sale con 3 si hace falta la contraseña de root)
function db_connect() {
    local check=$(gui_db_check)
    case "$check" in
        ok\|*)
            DB_FOLDER=$(cut -d'|' -f2 <<< "$check")
            DB_VERSION=$(cut -d'|' -f3 <<< "$check")
            ;;
        clave\|*)
            echo "MariaDB pide la contraseña de root: ponla en la variable MYSQL_PWD"

            return 3
            ;;
        *)
            echo "${check#no|}"

            return 1
            ;;
    esac
}

# Nombre de base valido y que no sea del sistema
function db_valid_name() {
    # Sin - delante: mysql y mysqldump lo tomarian como una opcion (-h otroequipo...)
    if ! [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$ ]]; then
        echo "Nombre de base de datos no valido: $1 (solo letras sin acentos, numeros, _ y -, sin - delante)"

        return 1
    fi
    # (sin distinguir mayusculas: en el Mac el disco no las distingue y MySQL seria la base mysql)
    if [[ "${1,,}" =~ ^($DB_SYSTEM)$ ]]; then
        echo "$1 es una base de datos del sistema: no se toca"

        return 1
    fi
}

# Importaciones hechas con lvm-instalador: carpeta real de datos de MariaDB|base|fecha (segundos)
IMPORTS_FILE="$HOME/.lvm-instalador/importaciones"

# Bases de una carpeta de datos de MariaDB con su fecha: base|fecha|tipo. Tipo i: la de su ultima
# importacion con lvm-instalador. Tipo c: la de su carpeta, que cambia al crear o borrar tablas (al
# importar desde phpMyAdmin, por ejemplo); se lee sin MariaDB en marcha aunque la carpeta sea suya
function db_dates() {
    python3 -I - "$1" "$IMPORTS_FILE" <<'EOF'
import os, re, sys
data, imports = os.path.realpath(sys.argv[1]), sys.argv[2]
done = {}
try:
    with open(imports, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("|")
            if len(parts) == 3 and parts[0] == data and parts[2].isdigit():
                done[parts[1]] = int(parts[2])
except OSError:
    pass
try:
    names = os.listdir(data)
except OSError:
    names = []
rows = []
for raw in names:
    path = os.path.join(data, raw)
    if raw in ("mysql", "performance_schema", "phpmyadmin", "test", "sys") or raw.startswith("#") \
            or os.path.islink(path) or not os.path.isdir(path):
        continue
    # MariaDB guarda los caracteres especiales del nombre como @XXXX (wp_mi@002dweb es wp_mi-web)
    name = re.sub(r"@([0-9a-f]{4})", lambda m: chr(int(m.group(1), 16)), raw)
    # Solo nombres que se pueden usar: uno con | o un salto de linea (@007c, @000a) meteria lineas
    # falsas en lo que lee la ventana
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", name):
        continue
    if name in done:
        rows.append((name, done[name], "i"))
    else:
        try:
            rows.append((name, int(os.stat(path).st_mtime), "c"))
        except OSError:
            rows.append((name, 0, "c"))
for name, when, kind in sorted(rows, key=lambda r: r[0].lower()):
    print("%s|%d|%s" % (name, when, kind))
EOF
}

# Apunta la fecha de la importacion de una base (sin fecha: la olvida, al borrarla o crearla vacia)
function db_note_import() {
    local data=$1 db=$2 when=$3
    [ "$DRY" -eq 1 ] && return 0
    data=$(python3 -I -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$data") || return 0
    mkdir -p "$(dirname "$IMPORTS_FILE")" || return 0
    { [ -f "$IMPORTS_FILE" ] && awk -F'|' -v a="$data" -v d="$db" '!($1 == a && $2 == d)' "$IMPORTS_FILE"
      [ -n "$when" ] && echo "$data|$db|$when"; } > "$IMPORTS_FILE.nuevo"
    mv "$IMPORTS_FILE.nuevo" "$IMPORTS_FILE"
}

function db_exists() {
    # Va dentro de la consulta: solo nombres validos
    [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
    [ "$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$1'" < /dev/null)" != "0" ]
}

# crear-bd <base>: base vacia en utf8mb4_general_ci (como las de XAMPP)
function create_database() {
    local db=$1 rc
    db_valid_name "$db" || return 1
    db_connect
    rc=$?
    [ $rc -ne 0 ] && return $rc

    if db_exists "$db"; then
        echo "Ya hay una base de datos $db en lampp-$DB_FOLDER"

        return 1
    fi

    run "${DB_SAFE[@]}" "$DB_CLIENT" -uroot -e "CREATE DATABASE \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci" < /dev/null || return 1
    db_note_import "/opt/lampp/var/mysql" "$db"
    echo "Base de datos $db creada en lampp-$DB_FOLDER"
}

# Tablas y tamaño (bytes) de una base: I|tablas|bytes
function gui_db_info() {
    local db=$1 rc
    db_valid_name "$db" || return 1
    db_connect
    rc=$?
    [ $rc -ne 0 ] && return $rc

    if ! db_exists "$db"; then
        echo "No hay ninguna base de datos $db en lampp-$DB_FOLDER"

        return 1
    fi

    "${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT CONCAT('I|', COUNT(*), '|', COALESCE(SUM(DATA_LENGTH + INDEX_LENGTH), 0))
        FROM information_schema.TABLES WHERE TABLE_SCHEMA='$db'" < /dev/null
}

# borrar-bd <base> [--copia]: elimina la base y todo su contenido. Con --copia guarda antes un
# volcado en ~/lvm-copias (se puede volver a cargar con importar-bd); si la copia falla, no se borra
function drop_database() {
    local db=$1 backup=0 rc
    [ "$2" == "--copia" ] && backup=1
    db_valid_name "$db" || return 1
    db_connect
    rc=$?
    [ $rc -ne 0 ] && return $rc

    if ! db_exists "$db"; then
        echo "No hay ninguna base de datos $db en lampp-$DB_FOLDER"

        return 1
    fi

    if [ $backup -eq 1 ]; then
        local dest="$HOME/lvm-copias/lampp-$DB_FOLDER-$db-$(date +%Y%m%d-%H%M%S).sql.gz"
        echo "Guardando copia de $db..."
        run mkdir -p -m 700 "$HOME/lvm-copias"
        if ! export_database "$db" "$dest" "$DB_FOLDER"; then
            echo "No se ha podido guardar la copia, asi que NO se borra nada."

            return 1
        fi
    fi

    echo "Borrando la base de datos $db de lampp-$DB_FOLDER..."
    run "${DB_SAFE[@]}" "$DB_CLIENT" -uroot -e "DROP DATABASE \`$db\`" < /dev/null || return 1
    db_note_import "/opt/lampp/var/mysql" "$db"
    echo "Base de datos $db borrada"
}

# MariaDB temporal de una version que no esta en marcha: sin red, sin comprobar usuarios
# (--skip-grant-tables: solo se llega por un socket en una carpeta temporal) y con los ficheros de
# esa version (las de XAMPP tienen en su my.cnf y en el RPATH las rutas de /opt/lampp, la version
# activa: se cambian por las suyas). Deja el socket en DB_TMP_SOCK; db_temp_stop lo para.
DB_TMP=""
function db_temp_start() {
    local dir=$1 data=$1/var/mysql server args user grants=(--skip-grant-tables)
    # (con --con-permisos, con sus usuarios: para cargar una base con su usuario lvm_bd_<base>)
    [ "$2" == "--con-permisos" ] && grants=()
    # El dueño de los datos de verdad (-L: si var/mysql es un enlace, el de su destino). Nunca root:
    # un MariaDB de root escribiria como root donde le pidiera una base (DATA DIRECTORY, registros)
    user=$($SUDO stat -L -c %U "$data") || return 1
    [ -n "$TEST_DIR" ] && user=$(id -un)
    if [ "$user" == "root" ] || ! [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Las BBDD de lampp-${dir#/opt/lampp-} son de $user: no se arranca su MariaDB con ese usuario"
        return 1
    fi

    if [ -x "$dir/mysql/bin/mariadbd" ]; then
        server=("$dir/mysql/bin/mariadbd" --defaults-file="$dir/etc/my.cnf")
    elif [ -x "$dir/sbin/mysqld" ]; then
        server=(env LD_LIBRARY_PATH="$dir/lib" "$dir/sbin/mysqld" --defaults-file="$dir/etc/my.cnf"
            --basedir="$dir" --plugin-dir="$dir/lib/mysql/plugin/"
            --innodb-data-home-dir="$data/" --innodb-log-group-home-dir="$data/")
    else
        echo "lampp-${dir#/opt/lampp-} no tiene el servidor de MariaDB"

        return 1
    fi

    # La carpeta la crea root y solo entran mysql y tu grupo: el servidor no pide contraseña
    # mientras dura la copia (otros usuarios del equipo no pueden llegar a su socket)
    DB_TMP=$($SUDO mktemp -d /tmp/lvm-mysql-XXXX) || { DB_TMP=""; return 1; }
    DB_TMP_SOCK=$DB_TMP/mysql.sock
    $SUDO chown "$user:$(id -gn)" "$DB_TMP" && $SUDO chmod 750 "$DB_TMP" || { $SUDO rm -rf "$DB_TMP"; DB_TMP=""; return 1; }

    echo "Arrancando un MariaDB temporal de lampp-${dir#/opt/lampp-} (sin red, solo para esta copia)..."
    $SUDO "${server[@]}" --datadir="$data" --user="$user" --skip-networking "${grants[@]}" \
        --socket="$DB_TMP_SOCK" --pid-file="$DB_TMP/mysql.pid" --log-error="$DB_TMP/mysql.log" \
        < /dev/null > /dev/null 2>&1 &
    local server_pid=$!
    DB_TMP_PID=$server_pid DB_TMP_USER=$user

    local i
    for i in $(seq 300); do
        [ -S "$DB_TMP_SOCK" ] && return 0
        # Si se ha parado (por ejemplo, porque otro MariaDB usa ya esa carpeta), no se espera mas
        kill -0 $server_pid 2> /dev/null || break
        sleep 0.2
    done
    echo "No ha arrancado. Ultimas lineas de su registro:"
    # (lo lee el dueño de los datos, no root: si el registro fuera un enlace a un fichero de root,
    # root lo mostraria)
    $SUDO ${SUDO:+-u "$user"} tail -15 "$DB_TMP/mysql.log" 2> /dev/null | sed 's/^/  /'

    return 1
}

# Para lo que se lanzo en segundo plano con $SUDO (su $!): sus hijos y el. Con sudo es el sudo (que
# pasa la señal al servidor); si sudo es una funcion (Mac), una subshell cuyo hijo es el sudo
# Solo si lleva el socket de esa carpeta (al azar) en su orden: si ya habia terminado, su PID podria
# ser de otro proceso. db_temp_kill_launched <pid lanzado> <socket>
function db_temp_kill_launched() {
    local p
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 1 ] && [ -n "$2" ] || return 0
    for p in "$1" $($SUDO pgrep -P "$1" 2> /dev/null); do
        [[ "$($SUDO ps -ww -o args= -p "$p" 2> /dev/null)" == *"--socket=$2"* ]] && $SUDO kill "$p" 2> /dev/null
    done
    return 0
}

# PID de un MariaDB temporal: el de su .pid, solo si es de verdad ese servidor (su orden lleva el
# socket de esa carpeta, que es al azar). Si el MariaDB corre con tu usuario, otro programa tuyo
# podria poner en el .pid el de otro proceso para que root lo parase. db_temp_pid <.pid> <socket>
function db_temp_pid() {
    local pid
    $SUDO test -f "$1" && ! $SUDO test -L "$1" || return 1
    pid=$($SUDO head -c 20 "$1" 2> /dev/null | tr -d ' \n')
    [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 1 ] || return 1
    # (con sudo: macOS no enseña la orden de los procesos de otros usuarios)
    [[ "$($SUDO ps -ww -o args= -p "$pid" 2> /dev/null)" == *"--socket=$2"* ]] || return 1
    echo "$pid"
}

# Al salir (tambien si se cancela): sin copia a medias y sin MariaDB temporal en marcha
DB_PART="" DB_COPY_TMP=""
function db_cleanup() {
    [ -n "$DB_PART" ] && rm -f "$DB_PART"
    # (copiar-bd: su copia temporal y el envoltorio del cliente, tambien si se cancela)
    [ -n "$DB_COPY_TMP" ] && rm -f "$DB_COPY_TMP"
    db_client_wrapper_remove
    db_temp_stop
}

# Envoltorio del cliente de MariaDB para un MariaDB temporal: en una carpeta de root que nadie mas
# puede cambiar. Se ejecuta muchas veces en la terminal de la tarea, que ya tiene el permiso de sudo:
# si fuera un fichero tuyo, otro programa tuyo podria cambiarlo por «sudo -n ...» y ser root.
# db_client_wrapper <cliente> <carpeta de librerias o ""> <socket>: deja la ruta en DB_CLI
DB_CLI_DIR="" DB_CLI=""
function db_client_wrapper() {
    local client=$1 libs=$2 sock=$3 body
    if [ -n "$libs" ]; then
        body=$(printf '#!/bin/bash\nexec /usr/bin/env LD_LIBRARY_PATH=%q %q --no-defaults -S %q "$@"\n' "$libs" "$client" "$sock")
    else
        body=$(printf '#!/bin/bash\nexec %q --no-defaults -S %q "$@"\n' "$client" "$sock")
    fi
    DB_CLI_DIR=$($SUDO mktemp -d /tmp/lvm-cliente-XXXXXX) || { DB_CLI_DIR=""; return 1; }
    DB_CLI=$DB_CLI_DIR/mysql
    if ! printf '%s\n' "$body" | $SUDO sh -c 'umask 022; cat > "$1"' sh "$DB_CLI" \
        || ! $SUDO chmod 755 "$DB_CLI_DIR" "$DB_CLI"; then
        db_client_wrapper_remove
        return 1
    fi
}

function db_client_wrapper_remove() {
    [ -n "$DB_CLI_DIR" ] && [[ "$DB_CLI_DIR" == /tmp/lvm-cliente-* ]] && $SUDO rm -rf "$DB_CLI_DIR"
    DB_CLI_DIR="" DB_CLI=""
}

function db_temp_stop() {
    [ -z "$DB_TMP" ] && return 0
    if $SUDO test -f "$DB_TMP/mysql.pid"; then
        echo "Parando el MariaDB temporal..."
        # El de su .pid si es el servidor; si no, el sudo que lo arranco (que le pasa la señal)
        local pid
        pid=$(db_temp_pid "$DB_TMP/mysql.pid" "$DB_TMP_SOCK") && $SUDO kill "$pid" 2> /dev/null \
            || db_temp_kill_launched "$DB_TMP_PID" "$DB_TMP_SOCK"
        local i
        for i in $(seq 300); do $SUDO test -f "$DB_TMP/mysql.pid" || break; sleep 0.2; done
    fi
    $SUDO rm -rf "$DB_TMP"
    DB_TMP="" DB_TMP_PID=""
}

# copiar-bd <base> <version de origen> <version de destino>: copia una base a otra version que no
# la tiene, para probar el proyecto con otro PHP. Se descarga de la de origen (como exportar-bd) a un
# fichero solo tuyo y se carga en la de destino con la carga protegida de importar-bd (usuario de la
# base, sin DEFINER, lo INVOKER y los eventos neutralizados). Si la de destino no es la activa en
# marcha, se arranca su MariaDB solo para la copia (sin red y con su propio socket). La de origen no
# se toca
function copy_database() {
    local db=$1 src=$2 dst=$3 sdir ddir src_owner dst_owner tmp rc active active_owner
    local replace=0 load=(--crear)
    # --sustituir: si la de destino ya la tiene, antes se guarda una copia suya en ~/lvm-copias y se
    # carga la de origen encima (la de destino se vacia antes de cargar)
    [ "$4" == "--sustituir" ] && replace=1
    if [ -z "$db" ] || [ -z "$src" ] || [ -z "$dst" ]; then
        echo "Uso: lvm-instalador copiar-bd <base de datos> <version de origen> <version de destino> [--sustituir]"
        return 1
    fi
    db_valid_name "$db" || return 1
    valid_version_name "$src" && valid_version_name "$dst" || { echo "Version no valida"; return 1; }
    sdir="${TEST_DIR:-/opt}/lampp-$src" ddir="${TEST_DIR:-/opt}/lampp-$dst"
    [ -d "$sdir" ] && [ ! -L "$sdir" ] || { echo "No existe la version lampp-$src"; return 1; }
    [ -d "$ddir" ] && [ ! -L "$ddir" ] || { echo "No existe la version lampp-$dst"; return 1; }
    src_owner=$(data_owner "$sdir"); src_owner=${src_owner:-$src}
    dst_owner=$(data_owner "$ddir"); dst_owner=${dst_owner:-$dst}
    if [ "$src_owner" == "$dst_owner" ]; then
        echo "lampp-$src y lampp-$dst comparten las BBDD: $db ya esta en las dos"
        return 1
    fi
    if ! db_names "/opt/lampp-$src_owner" | grep -qxF "$db"; then
        echo "No hay ninguna BBDD $db en lampp-$src"
        return 1
    fi
    if db_names "/opt/lampp-$dst_owner" | grep -qxF "$db"; then
        if [ $replace -eq 0 ]; then
            echo "lampp-$dst ya tiene una BBDD $db: no se toca (con --sustituir se guarda una copia suya en"
            echo "~/lvm-copias y se pone la de lampp-$src en su lugar)"
            return 1
        fi
        load=(--crear --sin-copia)
    else
        replace=0
    fi
    active=$(active_dir)
    active_owner=""
    [ -n "$active" ] && { active_owner=$(data_owner "$active"); active_owner=${active_owner:-${active#/opt/lampp-}}; }
    echo "Copia de la BBDD $db: de lampp-$src a lampp-$dst (lampp-$src no se toca)"
    if [ "$DRY" -eq 1 ]; then
        [ $replace -eq 1 ] && echo "  [simulacion] copia de $db de lampp-$dst en ~/lvm-copias (la sustituida)"
        echo "  [simulacion] descarga de $db de lampp-$src a un fichero temporal en ~/.lvm-instalador"
        if [ "$dst_owner" == "$active_owner" ] && lampp_running; then
            echo "  [simulacion] carga en el MariaDB en marcha de lampp-$dst (importar-bd ${load[*]})"
        else
            echo "  [simulacion] MariaDB temporal de lampp-$dst (sin red) y carga de $db"
        fi
        return 0
    fi
    if [ $replace -eq 1 ]; then
        local backup="$HOME/lvm-copias/lampp-$dst-$db-antes-de-copiar-$(date +%Y%m%d-%H%M%S).sql.gz"
        echo "lampp-$dst ya tiene $db: antes se guarda una copia suya en $backup"
        mkdir -p -m 700 "$HOME/lvm-copias" || return 1
        if ! export_database "$db" "$backup" "$dst"; then
            echo "No se ha podido guardar la copia de $db de lampp-$dst, asi que no se ha cambiado nada."
            return 1
        fi
        db_temp_stop
    fi
    mkdir -p -m 700 "$LOG_DIR" || return 1
    tmp=$(mktemp "$LOG_DIR/copia-$db-XXXXXX") || return 1
    mv -f "$tmp" "$tmp.sql.gz" && tmp=$tmp.sql.gz || { rm -f "$tmp"; return 1; }
    # (si se cancela, db_cleanup la borra)
    DB_COPY_TMP=$tmp
    if ! export_database "$db" "$tmp" "$src"; then
        rm -f "$tmp"
        echo "No se ha podido descargar $db de lampp-$src: no se ha copiado nada."
        return 1
    fi
    db_temp_stop
    if [ "$dst_owner" == "$active_owner" ] && lampp_running; then
        import_database "$tmp" "$db" "${load[@]}"
        rc=$?
    else
        # MariaDB de la de destino solo para la copia, con sus usuarios (la carga va con el usuario de
        # la base). El cliente es el de esa version, sin sus ficheros de opciones (llevarian al socket
        # de la activa), por un envoltorio solo tuyo
        # El MariaDB y el cliente de la version duena de las BBDD de destino (si las comparte con
        # otra, la de la otra): su servidor es el que corresponde a esos datos
        local client libs="" odir="${TEST_DIR:-/opt}/lampp-$dst_owner"
        [ -d "$odir" ] && [ ! -L "$odir" ] || { rm -f "$tmp"; echo "No existe la version lampp-$dst_owner"; return 1; }
        if [ -x "$odir/mysql/bin/mariadb" ]; then
            client=$odir/mysql/bin/mariadb
        else
            # (el de XAMPP busca sus librerias en /opt/lampp/lib, que es la de la version activa)
            client=$odir/bin/mysql libs=$odir/lib
        fi
        if ! db_temp_start "$odir" --con-permisos; then
            rm -f "$tmp"
            db_temp_stop
            return 1
        fi
        if ! db_client_wrapper "$client" "$libs" "$DB_TMP_SOCK"; then
            rm -f "$tmp"
            db_temp_stop
            return 1
        fi
        DB_CLIENT=$DB_CLI DB_TARGET_FOLDER=$dst DB_TARGET_DATA="/opt/lampp-$dst_owner/var/mysql" import_database "$tmp" "$db" "${load[@]}"
        rc=$?
        db_client_wrapper_remove
        db_temp_stop
    fi
    rm -f "$tmp"
    DB_COPY_TMP=""
    if [ $rc -eq 0 ]; then
        echo "$db esta ahora tambien en lampp-$dst. Para probar el proyecto con PHP $(php_version "$ddir" 2> /dev/null), cargalo"
        echo "en Versiones y elige lampp-$dst."
    fi
    return $rc
}

# exportar-bd <base> <fichero .zip, .sql o .sql.gz> [version]: descarga una copia de la base (estructura,
# datos, rutinas y disparadores; sin eventos, que el MariaDB de XAMPP tiene desactivados), que se
# puede volver a cargar con importar-bd. Sin version, de la activa. Si la version (o la que tiene sus bases) es la activa y esta en marcha, se usa su
# MariaDB; si no, uno temporal (pide sudo).
function export_database() {
    local db=$1 dest=$2 folder=$3 rc

    if [ -z "$db" ] || [ -z "$dest" ]; then
        echo "Uso: lvm-instalador exportar-bd <base de datos> <fichero.zip|.sql|.sql.gz> [version]"

        return 1
    fi
    db_valid_name "$db" || return 1
    local active=$(active_dir)
    folder=${folder:-${active#/opt/lampp-}}
    local dir="${TEST_DIR:-/opt}/lampp-$folder"
    if [ -z "$folder" ] || [ ! -d "$dir" ]; then
        echo "No existe la version lampp-$folder"

        return 1
    fi
    local owner=$(data_owner "$dir")
    owner=${owner:-$folder}
    if ! db_names "/opt/lampp-$owner" | grep -qxF "$db"; then
        echo "No hay ninguna base de datos $db en lampp-$folder"

        return 1
    fi
    dest=$(readlink -m "$dest")
    if [ ! -d "$(dirname "$dest")" ] || [ ! -w "$(dirname "$dest")" ]; then
        echo "No se puede escribir en $(dirname "$dest")"

        return 1
    fi

    local active_owner=""
    if [ -n "$active" ]; then
        active_owner=$(data_owner "$active")
        active_owner=${active_owner:-${active#/opt/lampp-}}
    fi

    echo "Base de datos: $db (lampp-$folder$([ "$owner" != "$folder" ] && echo ", bases de lampp-$owner"))"
    echo "Destino: $dest"
    local dump=() check
    trap db_cleanup EXIT
    trap 'exit 130' INT TERM HUP
    if [ "$owner" == "$active_owner" ] && check=$(gui_db_check) && [[ "$check" != no\|* ]]; then
        db_connect
        rc=$?
        [ $rc -ne 0 ] && return $rc
        echo "Se usa el MariaDB en marcha de lampp-$DB_FOLDER (MariaDB $DB_VERSION)"
        dump=("${DB_SAFE[@]}" "${LVM_BD_VOLCADO:-$(dirname "$DB_CLIENT")/mysqldump}" -uroot)
    elif [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] MariaDB temporal de lampp-$owner y mysqldump $db > $dest"

        return 0
    else
        db_temp_start "/opt/lampp-$owner" || return 1
        # El cliente de la propia version (el de XAMPP, con sus bibliotecas)
        local client=/opt/lampp-$owner/mysql/bin/mariadb-dump
        [ -x "$client" ] || client=/opt/lampp-$owner/bin/mysqldump
        dump=(env LD_LIBRARY_PATH="/opt/lampp-$owner/lib" "$client" --no-defaults -S "$DB_TMP_SOCK" -uroot)
    fi

    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] mysqldump $db > $dest"

        return 0
    fi

    local out=(cat) inner
    [[ "${dest,,}" == *.gz ]] && out=(gzip -6)
    if [[ "${dest,,}" == *.zip ]]; then
        inner=$(basename "$dest")
        inner=${inner%.*}
        out=(python3 -I -c "$ZIP_WRITE_PY" "${inner%.sql}.sql")
    fi
    local part="$dest.parte" errors=$(mktemp) routines=--routines pid
    DB_PART=$part
    echo "Descargando..."
    while :; do
        # (solo para ti: lleva la base entera, aunque la carpeta de destino sea de todos)
        ( umask 077; set -o pipefail; "${dump[@]}" --default-character-set=utf8mb4 --single-transaction --quick \
            $routines --triggers --max-allowed-packet=1G "$db" < /dev/null 2> "$errors" | "${out[@]}" > "$part" ) &
        pid=$!
        while kill -0 $pid 2> /dev/null; do
            sleep 2
            kill -0 $pid 2> /dev/null && echo "  $(numfmt --to=iec --suffix=B "$(stat -c %s "$part" 2> /dev/null || echo 0)") escritos"
        done
        wait $pid && break
        rm -f "$part"
        # MariaDB actualizados sin mysql_upgrade (como el XAMPP 8.2.4 con datos de 10.1): mysql.proc
        # tiene columnas de menos y no se pueden leer las rutinas. Se descarga sin ellas
        if [ -n "$routines" ] && grep -q "mysql.proc" "$errors"; then
            echo "Aviso: no se pueden leer sus funciones y procedimientos (la tabla mysql.proc es de un"
            echo "MariaDB anterior); se descarga sin ellos. Las tablas y los datos van completos."
            routines=""
            continue
        fi
        cat "$errors"
        rm -f "$errors"
        echo "No se ha podido descargar la base de datos."

        return 1
    done
    rm -f "$errors"
    mv -f "$part" "$dest"
    DB_PART=""
    echo "Copia guardada: $dest ($(du -h "$dest" | cut -f1))"
}

# Mientras se carga un volcado, sus funciones y procedimientos ya existen: si fueran SQL SECURITY
# INVOKER y la web (que entra como root) o phpMyAdmin los usaran a mitad de carga, se ejecutarian como
# root y podrian cambiar otras bases o darle permisos a su usuario. Este filtro cambia al vuelo la
# palabra INVOKER suelta por DEFINER (se ejecutan con el usuario de la base, que solo puede tocarla),
# este donde este: asi da igual como se escriba (comentarios en medio, /*!...*/, trozos). No toca los
# nombres que la llevan dentro (invoker_id, php-di/invoker...) y conserva el largo y las mayusculas
# (no rompe los datos serializados de PHP); un texto con la palabra suelta cambia (documentado).
# Por SQL dinamico (PREPARE) no se pueden crear rutinas, y una vista solo puede tocar lo que su
# creador puede (su base); lo que quede lo neutraliza la limpieza
INVOKER_PY='
import re, sys
# La palabra INVOKER suelta (no dentro de un nombre: invoker_id, $invoker, php-di/invoker,
# Vendor\Invoker, x.invoker), en mayusculas o minusculas, pasa a DEFINER con las mismas mayusculas
RX = re.compile(rb"(?<![A-Za-z0-9_$@.\\])(?<![^*]/)INVOKER(?![A-Za-z0-9_$.\\])", re.I)
NEW = b"DEFINER"
def swap(w):
    return bytes(d if 65 <= c <= 90 else d + 32 for c, d in zip(w, NEW))
CHUNK = int(sys.argv[1]) if len(sys.argv) > 1 else 1 << 20
inp, out = sys.stdin.buffer, sys.stdout.buffer
# buf[:skip] ya se ha escrito: solo sirve para mirar los dos caracteres de antes de una palabra
buf, skip = b"", 0
while True:
    data = inp.read(CHUNK)
    eof = not data
    buf += data
    # Las palabras que empiezan en los ultimos 8 bytes esperan al trozo siguiente
    cut = len(buf) if eof else max(skip, len(buf) - 8)
    parts, pos = [], skip
    for m in RX.finditer(buf, skip):
        if m.start() >= cut:
            break
        parts.append(buf[pos:m.start()])
        parts.append(swap(m.group()))
        pos = m.end()
    cut = max(cut, pos)
    parts.append(buf[pos:cut])
    out.write(b"".join(parts))
    if eof:
        break
    keep = max(0, cut - 2)
    buf, skip = buf[keep:], cut - keep
'

# Copias en .zip (como las que se descargan del servidor): el .sql de dentro se lee sin
# descomprimirlo a disco. "info <zip>" -> nombre|tamaño|empieza por la linea del modo sandbox (1/0);
# "extraer <zip o ->" lo escribe en la salida ("-": el zip es la entrada estandar, para que el
# avance se vea en la posicion del descriptor)
ZIP_SQL_PY='
import re, shutil, sys, zipfile
# Los nombres de dentro del .zip salen en la terminal: sin caracteres de control
def clean(name):
    return re.sub(r"[\x00-\x1f\x7f-\x9f]", "?", name)
mode, src = sys.argv[1], sys.argv[2]
f = open(0, "rb", closefd=False) if src == "-" else open(src, "rb")
try:
    z = zipfile.ZipFile(f)
except Exception as exc:
    print("ERROR|El fichero .zip no es valido: %s" % clean(str(exc)))
    sys.exit(1)
sqls = [i for i in z.infolist() if not i.is_dir() and not i.filename.startswith("__MACOSX/")
        and i.filename.lower().endswith(".sql")]
if not sqls:
    print("ERROR|El .zip no tiene ningun fichero .sql dentro")
    sys.exit(1)
if len(sqls) > 1:
    print("ERROR|El .zip tiene varios .sql (%s): deja solo el que quieras cargar"
          % ", ".join(clean(i.filename) for i in sqls))
    sys.exit(1)
if mode == "info":
    with z.open(sqls[0]) as m:
        first = m.readline(200)
    print("%s|%d|%d" % (clean(sqls[0].filename).replace("|", " "), sqls[0].file_size,
                        1 if first.startswith(b"/*M!999999\\-") else 0))
    sys.exit(0)
try:
    with z.open(sqls[0]) as m:
        shutil.copyfileobj(m, sys.stdout.buffer, 1 << 20)
except BrokenPipeError:
    sys.exit(1)
'

# Escribe en un .zip (en la salida) lo que llega por la entrada, como un unico <nombre>.sql
ZIP_WRITE_PY='
import shutil, sys, time, zipfile
info = zipfile.ZipInfo(sys.argv[1], time.localtime()[:6])
info.compress_type = zipfile.ZIP_DEFLATED
info.external_attr = 0o644 << 16
with zipfile.ZipFile(sys.stdout.buffer, "w", zipfile.ZIP_DEFLATED) as z:
    with z.open(info, "w", force_zip64=True) as m:
        shutil.copyfileobj(sys.stdin.buffer, m, 1 << 20)
'

# importar-bd <fichero .sql, .sql.gz o .zip> <base> [--crear] [--sin-copia]: carga el fichero en el
# MariaDB de la version activa. --crear crea la base si no existe. Si ya existe, siempre se vacia
# antes (se borra y se crea de nuevo con su juego de caracteres): asi no quedan tablas que el volcado
# ya no trae ni filas de una carga anterior que fallo a medias (los volcados de phpMyAdmin no llevan
# DROP TABLE y sus INSERT se suman a lo que haya). Si tiene tablas, antes se guarda una copia suya en
# ~/lvm-copias; --sin-copia no la guarda (copiar-bd, que ya la ha guardado). --vaciar se admite, pero
# ya no hace falta.
# Las copias hechas con mariadb-dump moderno empiezan por "/*M!999999\- enable the sandbox mode */",
# que los clientes de MariaDB anteriores a 10.5.25 (el de XAMPP es 10.4) no entienden: esa primera
# linea se quita al vuelo, sin tocar el fichero.
# Avance: el fichero se abre como descriptor 3 del script y los programas que lo leen comparten su
# posicion, que se ve en /proc/<pid>/fdinfo/3 (asi lo hace pv -d). Con LVM_PROGRESO se escribe una
# linea S con modo fdpos para la ventana; en una terminal con pv se muestra la barra de pv.
function import_database() {
    local file=$1 db=$2 create=0 backup=1 saved="" project=""
    shift 2
    while [ $# -gt 0 ]; do
        case "$1" in
            --crear) create=1 ;;
            --vaciar) ;;
            --sin-copia) backup=0 ;;
            --proyecto) project=${2%/}; shift ;;
        esac
        shift
    done

    if [ -z "$file" ] || [ -z "$db" ]; then
        echo "Uso: lvm-instalador importar-bd <fichero.sql|.sql.gz|.zip> <base de datos> [--crear] [--sin-copia] [--proyecto <carpeta>]"

        return 1
    fi
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        echo "No se puede leer el fichero $file"

        return 1
    fi
    db_valid_name "$db" || return 1
    # (como en el resto: sin ., .. ni saltos de linea, que meterian lineas en ~/.lvm-instalador/proyectos)
    if [ -n "$project" ] && ! valid_project "$project"; then
        return 1
    fi

    # Tipo de fichero (por su contenido) y si empieza por la linea del modo sandbox. Se mira antes
    # de crear o vaciar la base, para no vaciarla si el fichero no sirve
    local kind=sql first="" sandbox=0 inner="" inner_size=0
    case "$(head -c 4 "$file" | od -An -tx1 | tr -d ' \n')" in
        1f8b*) kind=gz ;;
        504b0304) kind=zip ;;
    esac
    case "${file,,}" in
        *.zip) [ $kind == zip ] || { echo "$(basename "$file") no es un .zip valido"; return 1; } ;;
        *.gz) [ $kind == gz ] || { echo "$(basename "$file") no es un .gz valido"; return 1; } ;;
    esac
    case $kind in
        sql) first=$(head -c 200 "$file" | head -1) ;;
        gz) first=$(gzip -dc "$file" 2> /dev/null | head -c 200 | head -1) ;;
        zip)
            local info
            info=$(python3 -I -c "$ZIP_SQL_PY" info "$file")
            if [ $? -ne 0 ]; then
                echo "${info#ERROR|}"

                return 1
            fi
            IFS='|' read -r inner inner_size sandbox <<< "$info"
            ;;
    esac
    [[ "$first" == '/*M!999999\-'* ]] && sandbox=1

    local rc
    # (copiar-bd a una version que no es la activa: DB_CLIENT ya va a su MariaDB temporal)
    if [ -n "$DB_TARGET_FOLDER" ]; then
        DB_FOLDER=$DB_TARGET_FOLDER
        DB_VERSION=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT VERSION()" < /dev/null 2> /dev/null | cut -d- -f1)
        [ -n "$DB_VERSION" ] || { echo "No se puede entrar en el MariaDB de lampp-$DB_FOLDER"; return 1; }
    else
        db_connect
        rc=$?
        [ $rc -ne 0 ] && return $rc
    fi

    local folder=$DB_FOLDER
    # --binary-mode: el cliente no ejecuta sus propios comandos que traiga el volcado (\! orden,
    # system, source, tee: con ellos un .sql manipulado ejecutaria programas en este equipo), solo
    # SQL. --local-infile=0: el volcado no puede leer ficheros del equipo (LOAD DATA LOCAL INFILE)
    local mysql=("${DB_SAFE[@]}" "$DB_CLIENT" -uroot --default-character-set=utf8mb4 --binary-mode --local-infile=0)
    local size=$(stat -c %s "$file") name=$(basename "$file")
    # (el nombre va en el fichero de progreso, separado por |)
    name=${name//[|$'\n'$'\r']/_}

    echo "Fichero: $file ($(numfmt --to=iec --suffix=B "$size"))"
    [ $kind == zip ] && echo "Dentro del zip: $inner ($(numfmt --to=iec --suffix=B "$inner_size"), se descomprime al vuelo)"
    echo "Destino: base $db en lampp-$folder (MariaDB $DB_VERSION)"
    [ $sandbox -eq 1 ] && echo "Se quita la primera linea (/*M!999999\- enable the sandbox mode */), que los MariaDB antiguos no entienden"
    # (antes de crear o vaciar la base: si no se puede cargar, no se toca nada)
    # Con FEDERATED, CONNECT o SPIDER activos, una tabla del volcado podria conectarse a este mismo
    # MariaDB como root (sin contraseña) y leer o cambiar cualquier base: no se carga (vienen
    # desactivados; se activan a mano con INSTALL SONAME)
    local engines
    engines=$("${mysql[@]}" -N -e "SELECT GROUP_CONCAT(ENGINE) FROM information_schema.ENGINES
        WHERE ENGINE IN ('FEDERATED', 'CONNECT', 'SPIDER', 'OQGRAPH') AND SUPPORT IN ('YES', 'DEFAULT')" < /dev/null 2> /dev/null)
    if [ -n "$engines" ] && [ "$engines" != NULL ]; then
        echo "No se carga: MariaDB tiene activos los motores $engines, con los que una tabla del volcado"
        echo "podria entrar como root en este MariaDB. Desactivalos (UNINSTALL SONAME) y vuelve a cargarlo."
        return 1
    fi
    if ! db_exists "$db"; then
        if [ $create -eq 0 ]; then
            echo "La base $db no existe en lampp-$folder (con --crear se crea)"

            return 1
        fi
        echo "Creando la base de datos $db..."
        run "${mysql[@]}" -e "CREATE DATABASE \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci" < /dev/null || return 1
    else
        # (ya existe: se vacia siempre, con copia antes si tiene tablas)
        local tables
        tables=$("${mysql[@]}" -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$db'" < /dev/null)
        if ! [[ "$tables" =~ ^[0-9]+$ ]]; then
            echo "No se pueden ver las tablas de $db: no se ha cambiado nada."
            return 1
        fi
        if [ "$tables" -gt 0 ] && [ $backup -eq 1 ]; then
            saved="$HOME/lvm-copias/lampp-$DB_FOLDER-$db-antes-de-cargar-$(date +%Y%m%d-%H%M%S).sql.gz"
            echo "$db ya tiene $tables $([ "$tables" == 1 ] && echo tabla || echo tablas): se borran todas antes de cargar."
            echo "Antes se guarda una copia suya en $saved"
            run mkdir -p -m 700 "$HOME/lvm-copias"
            if ! export_database "$db" "$saved" "$DB_FOLDER"; then
                echo "No se ha podido guardar la copia de $db, asi que no se ha cambiado nada."
                return 1
            fi
        fi
        echo "Vaciando la base de datos $db..."
        local charset=$("${mysql[@]}" -N -e "SELECT CONCAT(DEFAULT_CHARACTER_SET_NAME, ' COLLATE ', DEFAULT_COLLATION_NAME)
            FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$db'" < /dev/null)
        run "${mysql[@]}" -e "DROP DATABASE \`$db\`; CREATE DATABASE \`$db\` CHARACTER SET $charset" < /dev/null || return 1
    fi

    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] mysql $db < $file"
        [ -n "$project" ] && import_project "$db" "$project"

        return 0
    fi

    # Las copias de WordPress o PrestaShop pueden traer filas grandes: el servidor admite paquetes
    # de hasta 1 GB (hasta que se reinicie) y el cliente tambien
    "${mysql[@]}" -e "SET GLOBAL max_allowed_packet = GREATEST(@@GLOBAL.max_allowed_packet, 1073741824)" < /dev/null 2> /dev/null

    # El volcado se carga con el usuario de esa base (lvm_bd_<base>), que solo puede tocarla (no
    # root): un .sql de una web comprometida no puede cambiar otras bases, crear usuarios ni leer o
    # escribir ficheros desde el servidor (sin el permiso FILE). En el permiso, el _ va escapado
    # (si no, wp_x valdria tambien para wpYx). Al terminar se bloquea: no puede entrar, pero las
    # vistas y disparadores del volcado (que son suyos) siguen funcionando.
    local imp_user="lvm_bd_$db" imp_pass grant_db=${db//_/\\_}
    imp_pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')
    db_drop_import_users "${mysql[@]}"
    # (con su huella, no con la contraseña: la orden se ve en ps; la contraseña va en MYSQL_PWD)
    local imp_hash
    imp_hash=$(printf '%s' "$imp_pass" | db_pass_hash) || return 1
    if ! "${mysql[@]}" -e "CREATE USER IF NOT EXISTS '$imp_user'@'localhost' IDENTIFIED BY PASSWORD '$imp_hash';
            ALTER USER '$imp_user'@'localhost' IDENTIFIED BY PASSWORD '$imp_hash' ACCOUNT UNLOCK;
            GRANT ALL PRIVILEGES ON \`$grant_db\`.* TO '$imp_user'@'localhost'" < /dev/null; then
        echo "No se ha podido preparar el usuario de la base para cargar el volcado"
        return 1
    fi
    # Si la carga se interrumpe, solo se marca: despues se limpia lo que haya cargado (con su
    # usuario, que aun puede entrar) y se bloquea igual
    local imp_stop=0
    trap 'imp_stop=1' INT TERM HUP PIPE
    local imp=(env MYSQL_PWD="$imp_pass" "${DB_SAFE[@]}" "$DB_CLIENT" -u"$imp_user" --default-character-set=utf8mb4
               --binary-mode --local-infile=0)

    # Lectura: descomprimir (gzip o zip), quitar la linea del modo sandbox y los DEFINER de vistas,
    # disparadores y rutinas (son de otro usuario: con el temporal no se podrian crear)
    local source=(cat) filter=(env LC_ALL=C sed -E -e 's/DEFINER=`[^`]*`@`[^`]*`//g')
    case $kind in
        gz) source=(gzip -dc) ;;
        zip) source=(python3 -I -c "$ZIP_SQL_PY" extraer -) ;;
    esac
    [ $sandbox -eq 1 ] && filter=(env LC_ALL=C sed -E -e '1{/^\/\*M!999999\\-/d}' -e 's/DEFINER=`[^`]*`@`[^`]*`//g')
    local definer=(python3 -I -c "$INVOKER_PY")
    local start=$(date +%s)

    exec 3< "$file"
    if [ -n "$LVM_PROGRESO" ]; then
        { echo "I|1|1|Cargando $name en $db|$start"
          echo "S|1|0|100|cargando|fdpos|/proc/$BASHPID/fdinfo/3|$size|$start"; } >> "$LVM_PROGRESO"
    fi
    echo "Cargando..."
    if [ -z "$LVM_PROGRESO" ] && [ -t 2 ] && command -v pv > /dev/null; then
        # En una terminal, la barra de pv (el zip necesita poder saltar dentro del fichero: pv va
        # sobre el .sql ya descomprimido)
        if [ $kind == zip ]; then
            ( set -o pipefail; python3 -I -c "$ZIP_SQL_PY" extraer "$file" | pv -s "$inner_size" \
                | "${filter[@]}" | "${definer[@]}" | "${imp[@]}" --max-allowed-packet=1G "$db" )
        else
            ( set -o pipefail; pv -s "$size" <&3 | "${source[@]}" | "${filter[@]}" \
                | "${definer[@]}" | "${imp[@]}" --max-allowed-packet=1G "$db" )
        fi
    else
        ( set -o pipefail; "${source[@]}" <&3 | "${filter[@]}" | "${definer[@]}" | "${imp[@]}" --max-allowed-packet=1G "$db" )
    fi
    rc=$?
    exec 3<&-
    # Primero se cortan sus conexiones (un evento del volcado que ya estuviera corriendo), despues
    # eventos y tablas con DIRECTORY, luego lo INVOKER; se bloquea y root repasa que no quede nada
    db_kill_user "$imp_user" "${mysql[@]}"
    db_neutralize_extras "$db" "${imp[@]}"
    db_neutralize_invoker "$db" "${imp[@]}"
    db_lock_import_user "$imp_user" "${mysql[@]}"
    db_root_cleanup "$db" "${mysql[@]}"
    trap - INT TERM HUP PIPE
    if [ $imp_stop -eq 1 ]; then
        echo "Carga interrumpida. Lo anterior ya esta en $db."
        [ -n "$saved" ] && echo "Lo que tenia antes esta en $saved (se vuelve a cargar con importar-bd)."
        return 130
    fi
    [ -n "$LVM_PROGRESO" ] && echo "R|bd:$db|$rc" >> "$LVM_PROGRESO"

    local secs=$(( $(date +%s) - start ))
    if [ $rc -ne 0 ]; then
        echo "Error al cargar $name. Lo anterior al error ya esta en $db."
        echo "Si el error es «Access denied», el volcado intenta tocar otra base o crear usuarios:"
        echo "solo se carga lo que va en $db (un volcado de una sola base, como los de phpMyAdmin)."
        [ -n "$saved" ] && echo "Lo que tenia antes esta en $saved (se vuelve a cargar con importar-bd)."

        return 1
    fi

    local tables=$("${mysql[@]}" -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$db'" < /dev/null)
    echo "Cargado en $((secs / 60)) min $((secs % 60)) s. La base $db tiene ahora $tables $([ "$tables" == 1 ] && echo tabla || echo tablas)."
    db_note_import "${DB_TARGET_DATA:-/opt/lampp/var/mysql}" "$db" "$(date +%s)"
    # Administrador de pruebas para el boton del panel de Cargar proyecto (WordPress o PrestaShop)
    local admin
    admin=$(test_admin "$db" "$project")
    grep -v '^A|' <<< "$admin" | grep .
    grep -q '^A|' <<< "$admin" && echo "Administrador de pruebas del panel: $TEST_ADMIN_USER, contraseña $TEST_ADMIN_PASS"
    [ -n "$project" ] && { import_project "$db" "$project" || return 1; }
    return 0
}

# Vistas y rutinas SQL SECURITY INVOKER de un volcado: se ejecutarian con los permisos de quien las
# use (root en phpMyAdmin, o en la web si su wp-config.php usa root). Pasan a DEFINER, de
# lvm_bd_<base> (lo hace ese mismo usuario). Con --force: una vista rota del volcado no para las
# demas. Las que no se dejen cambiar se borran, y se avisa. db_neutralize_invoker <base> <cliente...>
function db_neutralize_invoker() {
    local db=$1 left
    shift
    local list="FROM information_schema.VIEWS WHERE TABLE_SCHEMA = DATABASE() AND SECURITY_TYPE = 'INVOKER'"
    local rlist="FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND SECURITY_TYPE = 'INVOKER'"
    "$@" --raw -N "$db" -e "SELECT CONCAT('ALTER SQL SECURITY DEFINER VIEW \`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\` AS ', VIEW_DEFINITION, ';') $list;
        SELECT CONCAT('ALTER ', ROUTINE_TYPE, ' \`', REPLACE(ROUTINE_NAME, '\`', '\`\`'), '\` SQL SECURITY DEFINER;') $rlist" \
        < /dev/null 2> /dev/null | "$@" --force "$db" > /dev/null 2>&1
    left=$("$@" --raw -N "$db" -e "SELECT CONCAT('vista ', TABLE_NAME) $list; SELECT CONCAT(LOWER(ROUTINE_TYPE), ' ', ROUTINE_NAME) $rlist" < /dev/null 2> /dev/null)
    [ -z "$left" ] && return 0
    "$@" --raw -N "$db" -e "SELECT CONCAT('DROP VIEW IF EXISTS \`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\`;') $list;
        SELECT CONCAT('DROP ', ROUTINE_TYPE, ' IF EXISTS \`', REPLACE(ROUTINE_NAME, '\`', '\`\`'), '\`;') $rlist" \
        < /dev/null 2> /dev/null | "$@" --force "$db" > /dev/null 2>&1
    echo "Aviso: el volcado traia vistas o rutinas SQL SECURITY INVOKER que no se han podido pasar a"
    echo "DEFINER (rotas o mal hechas). Se han borrado, porque se ejecutarian con los permisos de quien"
    echo "las usara: $(printf '%s' "$left" | tr -c '[:alnum:]_ \n-' '?' | head -20 | paste -sd ',' - | sed 's/,/, /g')"
    # (lo que no haya podido borrar este usuario, como los paquetes de MariaDB 10.4, lo borra root
    # en db_root_cleanup)
    return 0
}

# Eventos y tablas con DATA DIRECTORY o INDEX DIRECTORY de un volcado. Los eventos se ejecutan solos
# (si el planificador de MariaDB esta encendido) aunque el usuario de la base este bloqueado, y
# podrian volver a crear vistas INVOKER. Las tablas con esas opciones guardan sus ficheros fuera de
# la carpeta de MariaDB (en las de otras versiones, en /tmp...). Se borran, y se avisa (lo hace el
# usuario de la base). db_neutralize_extras <base> <cliente...>
DB_DIRECTORY_PY='
import re, sys
# Salida de SHOW CREATE TABLE con -N --batch: nombre<TAB>sentencia, con \n \t \\ escapados
def unesc(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", "0": "\0"}.get(m.group(1), m.group(1)), s)
# La opcion de verdad es DATA DIRECTORY = <cadena>: las cadenas (un COMMENT o un DEFAULT que digan
# data directory), los nombres entre comillas y los comentarios no cuentan
def options(sql):
    sql = re.sub(r"\x27(?:[^\x27\\]|\\.|\x27\x27)*\x27", " Q ", sql)
    sql = re.sub(r"`(?:[^`]|``)*`", " I ", sql)
    return re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
for line in sys.stdin:
    name, _, create = line.rstrip("\n").partition("\t")
    if re.search(r"(?i)\b(DATA|INDEX)\s+DIRECTORY\s*=?\s*Q", options(unesc(create))):
        print("DROP TABLE IF EXISTS `%s`;" % unesc(name).replace("`", "``"))
'
function db_neutralize_extras() {
    local db=$1 events tables drop
    shift
    local elist="FROM information_schema.EVENTS WHERE EVENT_SCHEMA = DATABASE()"
    events=$("$@" --raw -N "$db" -e "SELECT EVENT_NAME $elist" < /dev/null 2> /dev/null)
    if [ -n "$events" ]; then
        "$@" --raw -N "$db" -e "SELECT CONCAT('DROP EVENT IF EXISTS \`', REPLACE(EVENT_NAME, '\`', '\`\`'), '\`;') $elist" \
            < /dev/null 2> /dev/null | "$@" --force "$db" > /dev/null 2>&1
        echo "Aviso: el volcado traia eventos programados (se ejecutan solos en el servidor). Se han"
        echo "borrado: $(printf '%s' "$events" | tr -c '[:alnum:]_ \n-' '?' | head -20 | paste -sd ',' - | sed 's/,/, /g')"
    fi
    # Las particionadas no lo dicen en CREATE_OPTIONS: se mira su SHOW CREATE TABLE
    local tlist="FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_TYPE = 'BASE TABLE'"
    drop=$( { "$@" --raw -N "$db" -e "SELECT CONCAT('DROP TABLE IF EXISTS \`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\`;')
                $tlist AND CREATE_OPTIONS LIKE '%DIRECTORY%'" < /dev/null 2> /dev/null
              "$@" --raw -N "$db" -e "SELECT CONCAT('SHOW CREATE TABLE \`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\`;')
                $tlist AND CREATE_OPTIONS LIKE '%partitioned%'" < /dev/null 2> /dev/null \
                  | "$@" -N --batch --force "$db" 2> /dev/null | /usr/bin/python3 -I -c "$DB_DIRECTORY_PY"; } | sort -u)
    [ -z "$drop" ] && return 0
    tables=$(printf '%s\n' "$drop" | sed -e 's/^DROP TABLE IF EXISTS `//' -e 's/`;$//')
    printf '%s\n' "$drop" | "$@" --force "$db" > /dev/null 2>&1
    echo "Aviso: el volcado traia tablas con DATA DIRECTORY o INDEX DIRECTORY, que guardan sus ficheros"
    echo "fuera de la carpeta de MariaDB. Se han borrado (con sus ficheros): $(printf '%s' "$tables" \
        | tr -c '[:alnum:]_ \n-' '?' | head -20 | paste -sd ',' - | sed 's/,/, /g')"
    if [ -n "$("$@" --raw -N "$db" -e "SELECT 1 $tlist AND CREATE_OPTIONS LIKE '%DIRECTORY%' LIMIT 1" < /dev/null 2> /dev/null)" ]; then
        echo "ATENCION: siguen quedando tablas con DATA DIRECTORY en $db."
    fi
    return 0
}

# Huella mysql_native_password de una contraseña leida de la entrada (asi no va en ninguna linea de
# ordenes, que cualquier usuario del equipo ve con ps)
function db_pass_hash() {
    python3 -I -c 'import hashlib, sys; p = sys.stdin.buffer.read(); print("*" + hashlib.sha1(hashlib.sha1(p).digest()).hexdigest().upper())'
}

# Bloquea el usuario de una base (con otra contraseña al azar): ya no puede entrar, pero lo suyo
# (vistas, disparadores) sigue funcionando. Se borra y se vuelve a crear con solo los permisos de su
# base: si durante la carga hubiera conseguido otros (globales, de otras bases, roles), no le quedan.
# db_lock_import_user <usuario> <cliente como root...>
function db_lock_import_user() {
    local user=$1 pass extra
    shift
    [[ "$user" =~ ^lvm_bd_[A-Za-z0-9_-]+$ ]] || return 0
    pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')
    # Sin permiso para crear vistas, rutinas ni eventos: una rutina suya (DEFINER) no podria crear
    # despues otra INVOKER. Lo que ya tiene sigue funcionando (la proxima carga le vuelve a dar todo)
    local gdb=${user#lvm_bd_}
    gdb=${gdb//_/\\_}
    db_kill_user "$user" "$@"
    if ! "$@" -e "DROP USER IF EXISTS '$user'@'localhost';
            CREATE USER '$user'@'localhost' IDENTIFIED BY '$pass' ACCOUNT LOCK;
            GRANT ALL PRIVILEGES ON \`$gdb\`.* TO '$user'@'localhost';
            REVOKE CREATE VIEW, CREATE ROUTINE, ALTER ROUTINE, EVENT ON \`$gdb\`.* FROM '$user'@'localhost'" < /dev/null 2> /dev/null; then
        # (MariaDB sin DROP USER IF EXISTS o sin ACCOUNT LOCK: como antes, y sin lo de fuera de su base)
        "$@" -e "ALTER USER '$user'@'localhost' IDENTIFIED BY '$pass' ACCOUNT LOCK" < /dev/null 2> /dev/null
        "$@" -e "REVOKE ALL PRIVILEGES, GRANT OPTION FROM '$user'@'localhost'" < /dev/null 2> /dev/null
        "$@" -e "GRANT ALL PRIVILEGES ON \`$gdb\`.* TO '$user'@'localhost'" < /dev/null 2> /dev/null
        "$@" -e "REVOKE CREATE VIEW, CREATE ROUTINE, ALTER ROUTINE, EVENT ON \`$gdb\`.* FROM '$user'@'localhost'" < /dev/null 2> /dev/null
    fi
    # Lo que le quede fuera de su base (no deberia haber nada) se avisa
    extra=$("$@" -N --raw -e "SHOW GRANTS FOR '$user'@'localhost'" < /dev/null 2> /dev/null \
        | LVM_ON="ON \`$gdb\`.* TO " awk 'index($0, "GRANT USAGE ON *.* TO ") != 1 && !index($0, ENVIRON["LVM_ON"])' | wc -l)
    [ "${extra:-0}" -gt 0 ] && echo "Aviso: el usuario $user conserva permisos fuera de su base. Revisalo en phpMyAdmin (Cuentas de usuario)."
    db_kill_user "$user" "$@"
    return 0
}

# Corta las conexiones de un usuario de base (tambien un evento suyo en marcha). Como root.
# db_kill_user <usuario> <cliente como root...>
function db_kill_user() {
    local user=$1
    shift
    [[ "$user" =~ ^lvm_bd_[A-Za-z0-9_-]+$ ]] || return 0
    "$@" -e "KILL USER '$user'@'localhost'" < /dev/null 2> /dev/null
    return 0
}

# Repaso como root, al final de una carga (o de una que se corto): si en la base quedan vistas,
# rutinas o paquetes INVOKER, eventos o tablas con DATA DIRECTORY, root los borra (solo DROP: nunca
# se ejecutan ni se pasan a DEFINER de root) y avisa. db_root_cleanup <base> <cliente como root...>
function db_root_cleanup() {
    local db=$1 drop left
    shift
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] || return 0
    local w="TABLE_SCHEMA = '$db'" rw="ROUTINE_SCHEMA = '$db'" ew="EVENT_SCHEMA = '$db'"
    # (--force: en una MariaDB con las tablas del sistema antiguas, EVENTS o ROUTINES dan error y lo
    # demas tiene que seguir)
    drop=$( { "$@" --raw -N --force -e "SELECT CONCAT('DROP VIEW IF EXISTS \`$db\`.\`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\`;')
                FROM information_schema.VIEWS WHERE $w AND SECURITY_TYPE = 'INVOKER';
            SELECT CONCAT(IF(ROUTINE_TYPE LIKE 'PACKAGE%', 'SET sql_mode = ORACLE; ', ''), 'DROP ', ROUTINE_TYPE,
                ' IF EXISTS \`$db\`.\`', REPLACE(ROUTINE_NAME, '\`', '\`\`'), '\`; SET sql_mode = DEFAULT;')
                FROM information_schema.ROUTINES WHERE $rw AND SECURITY_TYPE = 'INVOKER'
                ORDER BY ROUTINE_TYPE = 'PACKAGE';
            SELECT CONCAT('DROP EVENT IF EXISTS \`$db\`.\`', REPLACE(EVENT_NAME, '\`', '\`\`'), '\`;')
                FROM information_schema.EVENTS WHERE $ew;
            SELECT CONCAT('DROP TABLE IF EXISTS \`$db\`.\`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\`;')
                FROM information_schema.TABLES WHERE $w AND TABLE_TYPE = 'BASE TABLE' AND CREATE_OPTIONS LIKE '%DIRECTORY%'" \
                < /dev/null 2> /dev/null
          "$@" --raw -N -e "SELECT CONCAT('SHOW CREATE TABLE \`$db\`.\`', REPLACE(TABLE_NAME, '\`', '\`\`'), '\`;')
                FROM information_schema.TABLES WHERE $w AND TABLE_TYPE = 'BASE TABLE' AND CREATE_OPTIONS LIKE '%partitioned%'" \
                < /dev/null 2> /dev/null | "$@" -N --batch --force 2> /dev/null | /usr/bin/python3 -I -c "$DB_DIRECTORY_PY" \
                | sed "s/^DROP TABLE IF EXISTS /DROP TABLE IF EXISTS \`$db\`./"; } )
    [ -z "$drop" ] && return 0
    printf '%s\n' "$drop" | "$@" --force > /dev/null 2>&1
    left=$("$@" --raw -N --force -e "SELECT CONCAT('vista ', TABLE_NAME) FROM information_schema.VIEWS WHERE $w AND SECURITY_TYPE = 'INVOKER';
        SELECT CONCAT(LOWER(ROUTINE_TYPE), ' ', ROUTINE_NAME) FROM information_schema.ROUTINES WHERE $rw AND SECURITY_TYPE = 'INVOKER';
        SELECT CONCAT('evento ', EVENT_NAME) FROM information_schema.EVENTS WHERE $ew" < /dev/null 2> /dev/null)
    echo "Aviso: en $db quedaban $(printf '%s\n' "$drop" | grep -c 'DROP ') cosas del volcado que no deben estar (vistas o"
    echo "rutinas INVOKER, eventos o tablas con DATA DIRECTORY): las ha borrado root."
    if [ -n "$left" ]; then
        echo "ATENCION: siguen en $db: $(printf '%s' "$left" | tr -c '[:alnum:]_ \n-' '?' | head -10 | paste -sd ',' - | sed 's/,/, /g')."
        echo "No abras esa base como root en phpMyAdmin hasta quitarlas."
    fi
    return 0
}

# Borra los usuarios temporales de la 1.37 (lvm_imp_*) y bloquea los de las bases (lvm_bd_*) que
# hayan quedado abiertos (una carga que no termino). Recibe el cliente de MariaDB como root.
function db_drop_import_users() {
    local u
    for u in $("$@" -N -e "SELECT User FROM mysql.user WHERE User LIKE 'lvm\\_imp\\_%' AND Host='localhost'" < /dev/null 2> /dev/null); do
        [[ "$u" =~ ^lvm_imp_[0-9a-f]+$ ]] && "$@" -e "DROP USER IF EXISTS '$u'@'localhost'" < /dev/null 2> /dev/null
    done
    local open_users old_tables=0
    open_users=$("$@" -N -e "SELECT User FROM mysql.global_priv WHERE User LIKE 'lvm\\_bd\\_%' AND Host='localhost'
            AND IFNULL(JSON_VALUE(Priv, '$.account_locked'), 'false') <> 'true'" < /dev/null 2> /dev/null) \
        || { old_tables=1; open_users=$("$@" -N -e "SELECT User FROM mysql.user WHERE User LIKE 'lvm\\_bd\\_%' AND Host='localhost'" \
            < /dev/null 2> /dev/null); }
    # (con las tablas del sistema antiguas no hay global_priv ni se sabe si estan bloqueados: todos)
    for u in $open_users; do
        # (una carga que se corto: lo que dejara en su base lo repasa root)
        db_kill_user "$u" "$@"
        db_lock_import_user "$u" "$@"
        # (con las tablas antiguas no se sabe cuales se cortaron: se bloquean todos, pero su base no se
        # repasa, que borraria lo que hayas creado despues a proposito)
        [ $old_tables -eq 0 ] && db_root_cleanup "${u#lvm_bd_}" "$@"
    done
    return 0
}

# MariaDB de XAMPP trae un usuario anonimo (sin nombre ni contraseña) y permisos para cualquiera
# sobre las bases test y test_*: se quitan (las pilas propias ya se crean sin ellos). Con la version
# montada en marcha; si root tiene contraseña, con MYSQL_PWD.
# Tablas del sistema de MariaDB (mysql.*) de una version anterior a la del servidor: los datos de
# XAMPP vienen de una MariaDB antigua sin poner al dia, y el servidor escribe un error en su registro
# cada vez que usa las estadisticas de una tabla (en una 8.2.4 llego a 28 GB). 0 si la version
# montada, en marcha, las tiene asi (en las de 10.4 en adelante: varbinary(255) y varchar(199))
function db_system_outdated() {
    [ -x "$DB_CLIENT" ] && lampp_running || return 1
    local t
    t=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT CONCAT(TABLE_NAME, '.', COLUMN_NAME, '=', COLUMN_TYPE) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = 'mysql' AND ((TABLE_NAME = 'column_stats' AND COLUMN_NAME = 'min_value')
        OR (TABLE_NAME = 'innodb_table_stats' AND COLUMN_NAME = 'table_name'))" < /dev/null 2> /dev/null) || return 1
    [ -n "$t" ] || return 1
    grep -q "^column_stats.min_value=varbinary" <<< "$t" && grep -q "^innodb_table_stats.table_name=varchar(199)" <<< "$t" && return 1
    return 0
}

# Registro de errores de MariaDB de una version: el .err mas grande de var/mysql (solo su ruta)
function db_error_log() {
    find "$1/var/mysql" -maxdepth 1 -type f -name '*.err' -printf '%s %p\n' 2> /dev/null | sort -rn | head -1 | cut -d' ' -f2-
}

# reparar-bd-sistema: pone al dia las tablas del sistema de MariaDB de la version montada (con su
# propio mysql_upgrade, solo las del sistema: las bases de los proyectos no se tocan), despues de
# guardar una copia de la base mysql en ~/lvm-copias, y vacia su registro de errores si es grande
function repair_db_system() {
    local dir name upgrade dump log size backup out
    dir=$(active_dir)
    if [ -z "$dir" ] || ! lampp_running; then
        echo "La version activa tiene que estar en marcha: arrancala y vuelve a intentarlo."
        return 1
    fi
    if ! wait_mariadb; then
        echo "MariaDB no responde o root tiene contraseña (ponla en MYSQL_PWD y vuelve a intentarlo)."
        return 1
    fi
    name=$(basename "$dir")
    if [ -x "$dir/mysql/bin/mariadb-upgrade" ]; then
        upgrade=("$dir/mysql/bin/mariadb-upgrade") dump=("$dir/mysql/bin/mariadb-dump")
    elif [ -x "$dir/bin/mysql_upgrade" ] && [ -x "$dir/bin/mysqldump" ]; then
        upgrade=("$dir/bin/mysql_upgrade") dump=("$dir/bin/mysqldump")
    else
        echo "$name no tiene mysql_upgrade"
        return 1
    fi
    upgrade+=(--no-defaults -S "$dir/var/mysql/mysql.sock" -uroot)
    dump+=(--no-defaults -S "$dir/var/mysql/mysql.sock" -uroot)
    log=$(db_error_log "$dir")
    # mysql_upgrade escribe en la carpeta de datos (mysql_upgrade_info): se ejecuta con su dueño
    # (mysql, o tu usuario en el Mac), nunca como root. Con sudo -u, MYSQL_PWD no pasaria
    local owner as_owner=()
    owner=$(stat -c %U "$dir/var/mysql" 2> /dev/null)
    if [ -n "$owner" ] && [ "$owner" != "$(id -un)" ]; then
        [[ "$owner" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,31}$ ]] && [ "$owner" != root ] || {
            echo "La carpeta de datos de $name es de $owner: no se ejecuta mysql_upgrade con ese usuario."
            return 1
        }
        as_owner=(sudo -u "$owner")
        if [ -n "$MYSQL_PWD" ]; then
            echo "root de MariaDB tiene contraseña y con sudo -u no se le pasa: hazlo a mano en la terminal:"
            echo "  sudo -u $owner ${upgrade[0]} --no-defaults -S <socket> -uroot -p --upgrade-system-tables --force"
            return 1
        fi
    fi
    if db_system_outdated; then
        echo "Las tablas del sistema de MariaDB de $name son de una version anterior: se ponen al dia"
        echo "(las bases de los proyectos no se tocan)."
        backup="$HOME/lvm-copias/$name-mysql-sistema-$(date +%Y%m%d-%H%M%S).sql.gz"
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] copia de la base mysql en $backup"
            echo "  [simulacion] ${upgrade[0]##*/} --upgrade-system-tables --force"
        else
            mkdir -p -m 700 "$HOME/lvm-copias" || return 1
            if ! ( set -o pipefail; umask 077; "${dump[@]}" --databases mysql < /dev/null | gzip > "$backup" ); then
                rm -f "$backup"
                echo "No se ha podido guardar la copia de la base mysql: no se cambia nada."
                return 1
            fi
            echo "Copia de las tablas del sistema: $backup"
            if ! out=$("${as_owner[@]}" "${upgrade[@]}" --upgrade-system-tables --force < /dev/null 2>&1); then
                echo "$out" | tail -8 | sed 's/^/  /'
                echo "No se han podido poner al dia (la copia esta en $backup)."
                return 1
            fi
            echo "$out" | grep -E '^(Phase|OK)' | sed 's/^/  /'
            if db_system_outdated; then
                echo "Siguen sin estar al dia: revisa la salida de arriba."
                return 1
            fi
            echo "Tablas del sistema al dia."
            # Con las tablas antiguas, MariaDB no leia mysql.proc: rutinas INVOKER de volcados de
            # antes de la 1.42 (que nunca se neutralizaron) vuelven a funcionar. Se avisa de cuales
            local inv
            inv=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot --raw -N --force -e "SELECT CONCAT(ROUTINE_SCHEMA, '.', ROUTINE_NAME) FROM information_schema.ROUTINES
                    WHERE SECURITY_TYPE = 'INVOKER' AND ROUTINE_SCHEMA NOT IN ('mysql', 'sys');
                SELECT CONCAT(TABLE_SCHEMA, '.', TABLE_NAME) FROM information_schema.VIEWS
                    WHERE SECURITY_TYPE = 'INVOKER' AND TABLE_SCHEMA NOT IN ('mysql', 'sys');
                SELECT CONCAT(EVENT_SCHEMA, '.', EVENT_NAME, ' (evento)') FROM information_schema.EVENTS" < /dev/null 2> /dev/null)
            if [ -n "$inv" ]; then
                echo "Aviso: estas rutinas, vistas o eventos se ejecutan con los permisos de quien las use (root en"
                echo "phpMyAdmin). Si no las reconoces, vuelve a cargar esa BBDD con el gestor, que las neutraliza:"
                printf '%s\n' "$inv" | tr -c '[:alnum:]_ .()\n-' '?' | head -30 | sed 's/^/  /'
            fi
        fi
    else
        echo "Las tablas del sistema de MariaDB de $name ya estan al dia."
    fi
    # El registro: si pasa de 100 MB se vacia (solo son errores, ya corregidos; MariaDB sigue
    # escribiendo en el mismo fichero)
    if [ -n "$log" ] && [ -f "$log" ] && [ ! -L "$log" ] && [[ "$log" == "$dir"/var/mysql/*.err ]]; then
        size=$(stat -c %s "$log")
        if [ "$size" -gt 104857600 ]; then
            echo "El registro de errores de MariaDB ($log) ocupa $((size / 1048576)) MB: se vacia."
            # (con su dueño, mysql, no como root: no hace falta, y root seguiria un enlace)
            if [ ${#as_owner[@]} -gt 0 ]; then
                run sudo -u "$owner" truncate -s 0 "$log" || return 1
            else
                run truncate -s 0 "$log" || return 1
            fi
        fi
    fi
    return 0
}

# Espera (hasta 8 s) a que MariaDB de la version montada acepte a root. 1 si no arranca o pide
# contraseña (y no esta en MYSQL_PWD)
function wait_mariadb() {
    local i out
    [ -x "$DB_CLIENT" ] || return 1
    for i in 1 2 3 4 5 6 7 8; do
        out=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT 1" < /dev/null 2>&1) && return 0
        [[ "$out" == *"Access denied"* ]] && return 1
        sleep 1
    done
    return 1
}

function secure_mariadb() {
    [ -x "$DB_CLIENT" ] || return 0
    local mysql=("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N) hosts h
    hosts=$("${mysql[@]}" -e "SELECT Host FROM mysql.user WHERE User=''" < /dev/null 2> /dev/null) || return 0
    for h in $hosts; do
        [[ "$h" =~ ^[A-Za-z0-9._%-]+$ ]] || continue
        echo "MariaDB: se quita el usuario anonimo (''@$h)"
        [ "$DRY" -eq 1 ] || "${mysql[@]}" -e "DROP USER IF EXISTS ''@'$h'" < /dev/null 2> /dev/null
    done
    if [ -n "$("${mysql[@]}" -e "SELECT 1 FROM mysql.db WHERE Db IN ('test', 'test\\_%') LIMIT 1" < /dev/null 2> /dev/null)" ]; then
        echo "MariaDB: se quitan los permisos de cualquiera sobre las bases test"
        [ "$DRY" -eq 1 ] || "${mysql[@]}" -e "DELETE FROM mysql.db WHERE Db IN ('test', 'test\\_%'); FLUSH PRIVILEGES" < /dev/null 2> /dev/null
    fi
    # Usuarios de las bases que hayan quedado sin bloquear (una carga interrumpida)
    [ "$DRY" -eq 1 ] || db_drop_import_users "${DB_SAFE[@]}" "$DB_CLIENT" -uroot
    return 0
}

# Base subida para un proyecto: pasa a ser su base (sustituye a la anterior). Si es un WordPress, su
# wp-config.php se rehace con la plantilla para que la use; si es una tienda PrestaShop, su
# parameters.php (o settings.inc.php) pasa a usarla y se vacia su cache
function import_project() {
    local db=$1 folder=$2
    remember_project "$db" "$folder" --unica
    echo "La base $db queda asociada al proyecto $folder"
    if is_prestashop "$folder"; then
        PS_NEW_PARAMS=0
        ps_parameters "$folder" "$db" || return 1
        ps_set_db "$folder" "$db" || return 1
        ps_first_load "$folder"
    elif is_wordpress "$folder"; then
        wp_config "$folder" "$db" || return 1
    fi
    return 0
}

# Codigo de la ventana (Python). No puede contener una linea con solo LVM_GUI_PY.
function gui_source() {
    cat <<'LVM_GUI_PY'
#!/usr/bin/env python3
# Ventana de Nexum Stack (GTK 3 y Python 3.8: funciona desde Ubuntu 20.04).
# La escribe y la abre "lvm-instalador ventana". No repite la logica del instalador: lo ejecuta con
# los comandos gui-* (datos) y con los de siempre (use, instalar, actualizar, desinstalar...)
# dentro de una pseudoterminal, para que sudo funcione igual que en la terminal; la contraseña
# se pide en una ventana y se escribe en esa terminal.
import codecs
import fcntl
import html
import http.server
import os
import pty
import re
import shlex
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, GObject, Gtk

SCRIPT = os.path.abspath(sys.argv[1])
SIMULATE = os.environ.get("LVM_SIMULAR") == "1"
# Programas del sistema: el PATH de la sesion puede llevar delante carpetas tuyas (~/.local/bin),
# donde un sudo, un bash o un pkexec falso recibiria la contraseña que se escribe en la ventana
os.environ["PATH"] = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
for _k in [k for k in os.environ if k.startswith(("LD_", "PYTHON", "BASH_FUNC_"))
           or k in ("BASH_ENV", "ENV", "IFS", "CDPATH", "SHELLOPTS", "BASHOPTS", "PS4", "GLOBIGNORE")]:
    del os.environ[_k]
APP_ID = "dev.hexer.LamppVersionManager"
ICON = "lampp-version-manager"
LOG_DIR = os.path.expanduser("~/.lvm-instalador")
PROJECTS_FILE = os.path.join(LOG_DIR, "proyectos")


def is_ps_db(db):
    """Base de una tienda PrestaShop: suelen llamarse ps_<tienda>."""
    return db.lower().startswith("ps_")


# Proyectos de /opt/htdocs (LVM_HTDOCS solo para pruebas)
HTDOCS = os.environ.get("LVM_HTDOCS", "/opt/htdocs")
DB_RULES = [
    ("wp-config.php", r"""^[ \t]*define\(\s*['"]DB_NAME['"]\s*,\s*['"]([^'"]+)"""),
    ("app/config/parameters.php", r"""['"]database_name['"]\s*=>\s*['"]([^'"]+)"""),
    ("config/settings.inc.php", r"""define\(\s*['"]_DB_NAME_['"]\s*,\s*['"]([^'"]+)"""),
    (".env", r"""^\s*DB_DATABASE\s*=\s*["']?([^"'\s#]+)"""),
]


# Visual Studio Code, según cómo se haya instalado: .deb o .rpm (el nuevo y el antiguo), snap,
# flatpak o el paquete de Arch
VSCODE_IDS = ("com.microsoft.VSCode.desktop", "code.desktop", "code_code.desktop",
              "com.visualstudio.code.desktop", "visual-studio-code.desktop")


def vscode_app():
    """Acceso de Visual Studio Code (None si no está instalado)."""
    for app_id in VSCODE_IDS:
        try:
            app = Gio.DesktopAppInfo.new(app_id)
        except (TypeError, GLib.Error):
            app = None
        if app is not None:
            return app
    return None


# Ancho de los campos del formulario de la pestaña Hosts (como los de Bases de datos)
COMBO_CHARS = 24


def narrow(combo, chars=COMBO_CHARS):
    """Desplegable de ancho fijo: los nombres largos se cortan con «…» en lugar de ensanchar
    toda la pestaña."""
    for cell in combo.get_cells():
        cell.set_property("ellipsize", 3)  # Pango.EllipsizeMode.END
        cell.set_property("width-chars", chars)
        cell.set_property("max-width-chars", chars)
    return combo


def project_folders():
    """Carpetas de proyectos de /opt/htdocs (sin enlaces como web.local ni ocultas)."""
    try:
        return sorted((n for n in os.listdir(HTDOCS) if not n.startswith(".")
                       and not os.path.islink(os.path.join(HTDOCS, n))
                       and os.path.isdir(os.path.join(HTDOCS, n))), key=str.lower)
    except OSError:
        return []


def project_kind(folder):
    """ps (tienda PrestaShop, como is_prestashop del script), wp (WordPress) o vacío."""
    path = os.path.join(HTDOCS, folder)
    if "prestashop" in folder.lower() or os.path.isdir(os.path.join(path, "src/PrestaShopBundle")) \
            or os.path.isfile(os.path.join(path, "classes/PrestaShopAutoload.php")) \
            or os.path.isfile(os.path.join(path, "app/config/parameters.php")) \
            or os.path.isfile(os.path.join(path, "config/settings.inc.php")):
        return "ps"
    if os.path.isfile(os.path.join(path, "wp-config.php")) or \
            os.path.isdir(os.path.join(path, "wp-includes")):
        return "wp"
    return ""


# Lo que se hace con la configuración del proyecto al subirle una base nueva
PROJECT_CONFIG_TEXT = {
    "wp": "su wp-config.php se rehace con la plantilla de este equipo para usar esta BBDD",
    "ps": "su parameters.php (o settings.inc.php) pasa a usar esta BBDD y se vacía su caché",
}


def name_match_project(db, folders):
    """Carpeta que se llama como la base: wp_ajoselpajizo → dob-wordpress-ajoselpajizo (la base
    sin wp_ ni ps_, al final del nombre). Si hay varias, la del mismo tipo (WordPress o tienda)."""
    low = db.lower()
    tails = {low}
    if low[:3] in ("wp_", "ps_") and len(low) > 3:
        tails.add(low[3:])
    hits = [f for f in folders if any(f.lower() == v or f.lower()[-len(v) - 1:] in
                                     ("-" + v, "." + v, "_" + v) for v in tails)]
    if len(hits) > 1 and low[:3] in ("wp_", "ps_"):
        hits = [f for f in hits if project_kind(f) == low[:2]] or hits
    return hits[0] if len(hits) == 1 else None


def guess_project(db):
    """Carpeta del proyecto de una base: la recordada (~/.lvm-instalador/proyectos), la única
    cuya configuración la usa o la que se llama como la base. None si no se sabe."""
    folders = project_folders()
    saved = None
    try:
        with open(PROJECTS_FILE, encoding="utf-8") as f:
            for line in f.read().splitlines():
                if line.startswith(db + "="):
                    saved = line.split("=", 1)[1]
    except OSError:
        pass
    if saved in folders:
        return saved
    users = [f for f in folders if project_db(f) == db]
    if len(users) == 1:
        return users[0]
    return name_match_project(db, folders)


def project_db(folder):
    """Base de datos de la configuración de un proyecto (vacío si no tiene)."""
    for rel, rx in DB_RULES:
        path = os.path.join(HTDOCS, folder, rel)
        # Solo un fichero normal de hasta 2 MB, sin enlaces y sin esperar (un FIFO o un enlace a
        # /dev/zero de un proyecto colgarian la ventana)
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode) or st.st_size > 2000000:
                continue
            with os.fdopen(fd, errors="replace") as fh:
                fd = None
                m = re.search(rx, fh.read(2000000), re.M)
        except OSError:
            continue
        finally:
            if fd is not None:
                os.close(fd)
        if m:
            # Solo nombres de base validos (la configuracion la trae el proyecto)
            return m.group(1) if re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", m.group(1)) else ""
    return ""


# Registros mayores que esto no se abren en el editor de textos (solo «Ver el final»)
LOG_OPEN_MAX = 20 * 1024 * 1024
# Dominio de un proyecto nuevo (pestaña Hosts): mitienda.com, sub.mitienda.es…
DOMAIN_RX = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$")
# Marca con la que sudo pide la contraseña (SUDO_PROMPT). Distinta en cada ventana: un volcado o un
# fichero de un proyecto que se muestre en el registro no puede imitarla para que salga el cuadro
SUDO_MARK = "@@LVM-SUDO-%s@@" % os.urandom(8).hex()
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[78()][0-9A-Za-z]?")
GREEN = "#45A57C"

# Tramos de la barra de la pila propia (los mismos que usa el script en whiptail)
CSS = """
.grupo-titulo { font-weight: bold; }
.info { color: alpha(currentColor, 0.55); }
.info:hover { color: currentColor; }
.subtitulo { font-size: smaller; }
list.caja {
  background-color: alpha(@theme_fg_color, 0.045);
  border: 1px solid alpha(@theme_fg_color, 0.12);
  border-radius: 12px;
}
list.caja > row {
  border-bottom: 1px solid alpha(@theme_fg_color, 0.10);
  background-color: transparent;
  outline: none;
}
list.caja > row:hover { background-color: alpha(@theme_fg_color, 0.04); }
list.caja > row:selected, list.caja > row:selected:hover { background-color: alpha(GREEN, 0.25); }
list.caja > row:last-child { border-bottom: none; }
list.caja > row:first-child { border-top-left-radius: 12px; border-top-right-radius: 12px; }
list.caja > row:last-child { border-bottom-left-radius: 12px; border-bottom-right-radius: 12px; }
list.anidada { background-color: alpha(@theme_fg_color, 0.03); border-top: 1px solid alpha(@theme_fg_color, 0.10); }
list.anidada > row { border-bottom: 1px solid alpha(@theme_fg_color, 0.08); background-color: transparent; }
list.anidada > row:last-child { border-bottom: none; }
.tag { font-weight: bold; font-size: smaller; }
.pastilla { padding: 2px 10px; border-radius: 999px; font-weight: bold; font-size: smaller; }
.pastilla.activa { background-color: GREEN; color: white; }
.estado { font-weight: bold; font-size: smaller; }
.estado.estable { color: GREEN; }
.estado.seguridad { color: #c88800; }
.estado.soporte-no { color: #e01b24; }
.etiqueta-parche { font-weight: bold; font-size: smaller; }
.etiqueta-parche.seguridad-parche { color: #3584e4; }
.fecha-version { font-size: smaller; }
.boton-proyecto { min-width: 34px; min-height: 34px; padding: 2px 4px; }
.aviso-rojo { color: #e01b24; font-weight: bold; }
.asistente { padding: 14px 16px; border-radius: 12px; background-color: alpha(@theme_fg_color, 0.05);
             border: 1px solid alpha(@theme_fg_color, 0.10); }
.asistente-paso { font-weight: bold; }
/* Mensajes emergentes (al dejar el ratón encima): como el resto de la ventana, gris oscuro y con
   las esquinas redondeadas, en vez del negro del tema */
tooltip, tooltip.background { background-color: rgba(62, 62, 67, 0.98); color: #ececec;
             border-radius: 10px; border: 1px solid rgba(255, 255, 255, 0.10); padding: 6px 10px; }
tooltip decoration { background-color: transparent; border-radius: 10px; }
tooltip label { color: #ececec; padding: 2px 4px; }
button.icono-verde image { color: GREEN; }
button.icono-rojo image { color: #e01b24; }
button.icono-azul image { color: #3584e4; }
button.verde, button.verde:hover, button.verde:active {
  background-image: none; background-color: GREEN; color: white;
  border-color: shade(GREEN, 0.85); box-shadow: none; text-shadow: none;
}
button.verde:hover { background-color: shade(GREEN, 1.08); }
button.verde:disabled { background-color: alpha(GREEN, 0.4); color: alpha(white, 0.7); }
/* Todos los botones: transición suave y, al pasar el ratón, un poco más claros */
button { transition: background-color 120ms ease-out, box-shadow 120ms ease-out, color 120ms ease-out; }
button:hover:not(.verde):not(:disabled) { box-shadow: inset 0 0 0 999px alpha(@theme_fg_color, 0.07); }
button.verde:active { background-color: shade(GREEN, 0.92); }
/* Cargar proyecto: contenedor hundido con el título dentro */
.hundido {
  background-color: alpha(black, 0.16);
  border: 1px solid alpha(@theme_fg_color, 0.10);
  border-radius: 14px;
  box-shadow: inset 0 2px 5px alpha(black, 0.30), inset 0 1px 1px alpha(black, 0.25);
  padding: 32px 20px;
}
.hundido-titulo { font-weight: bold; font-size: 1.2em; }
.hundido entry.buscador {
  min-height: 38px; padding-left: 10px; padding-right: 10px; font-size: 1.05em;
  border-radius: 10px;
}
button.pildora { border-radius: 999px; padding: 8px 28px; }
.punto-verde { color: GREEN; }
.punto-gris { color: alpha(@theme_fg_color, 0.35); }
.error { color: #e01b24; }
.aviso { color: #c88800; }
.texto-activa { color: GREEN; font-weight: bold; }
switch:checked { background-image: none; background-color: GREEN; border-color: shade(GREEN, 0.85); }
progressbar progress { background-image: none; background-color: GREEN; border-color: GREEN; }
/* Barra lateral (como Configuración de Ubuntu) */
.lateral {
  background-color: alpha(@theme_fg_color, 0.035);
  border-right: 1px solid alpha(@theme_fg_color, 0.10);
}
list.barra-lateral { background-color: transparent; }
list.barra-lateral > row {
  margin: 2px 8px; padding: 12px 12px; min-height: 22px; border-radius: 10px;
  transition: background-color 120ms ease-out;
}
list.barra-lateral > row:hover { background-color: alpha(@theme_fg_color, 0.06); }
list.barra-lateral > row:selected, list.barra-lateral > row:selected:hover {
  background-color: alpha(@theme_fg_color, 0.11); color: @theme_fg_color;
}
list.barra-lateral > row:selected label { font-weight: bold; }
/* Icono de cada apartado: logotipo del paquete o símbolo, en un cuadrado redondeado */
.icono-seccion { background-color: alpha(@theme_fg_color, 0.07); border-radius: 8px; padding: 4px; }
.icono-servicio { background-color: alpha(@theme_fg_color, 0.07); border-radius: 12px; padding: 10px; }
.icono-seccion.verde-suave, .icono-servicio.verde-suave { background-color: alpha(GREEN, 0.16); color: GREEN; }
.icono-seccion.aviso-suave { background-color: alpha(#c88800, 0.16); color: #c88800; }
.titulo-grande { font-weight: bold; font-size: 1.25em; }
/* Contraseña de administrador */
.dialogo-clave headerbar { background: transparent; border: none; box-shadow: none; min-height: 28px; }
.clave-titulo { font-weight: bold; font-size: 1.15em; }
.candado { background-color: alpha(@theme_fg_color, 0.55); color: @theme_bg_color; border-radius: 999px; padding: 5px; }
entry.campo-clave { min-height: 38px; padding-left: 12px; padding-right: 12px; border-radius: 8px; }
button.boton-grande { min-height: 34px; border-radius: 8px; }
/* Diálogos: campos y desplegables algo más altos, y los botones con más sitio */
dialog entry { min-height: 34px; }
dialog combobox button, dialog spinbutton { min-height: 34px; }
dialog radiobutton, dialog checkbutton { padding-top: 2px; padding-bottom: 2px; }
dialog radiobutton > radio, dialog checkbutton > check { margin-right: 8px; }
messagedialog .dialog-action-box { margin-top: 6px; }
.opcion {
  border: 1px solid alpha(@theme_fg_color, 0.12); border-radius: 10px;
  background-color: alpha(@theme_fg_color, 0.03); padding: 10px 14px;
  transition: border-color 120ms ease-out, background-color 120ms ease-out;
}
.opcion.elegida { border-color: GREEN; background-color: alpha(GREEN, 0.08); }
/* Dentro de la tarjeta, el botón de radio sin su propio recuadro (el del foco del tema): la
   elegida ya se marca con el borde verde de la tarjeta */
.opcion radiobutton, .opcion radiobutton:focus, .opcion radiobutton:hover {
  outline-style: none; outline-width: 0; box-shadow: none; border: none; background: none;
}
/* Servicios: una tarjeta por servicio */
.servicio {
  background-color: alpha(@theme_fg_color, 0.045);
  border: 1px solid alpha(@theme_fg_color, 0.12);
  border-radius: 14px; padding: 16px 18px;
}
.servicio-nombre { font-weight: bold; font-size: 1.1em; }
.chip { padding: 1px 9px; border-radius: 999px; background-color: alpha(@theme_fg_color, 0.08); font-size: smaller; }
.pastilla.parada { background-color: alpha(@theme_fg_color, 0.12); }
.pastilla.segura { background-color: alpha(GREEN, 0.16); color: GREEN; }
.pastilla.peligro { background-color: alpha(#e01b24, 0.16); color: #e01b24; }
.firma { font-size: smaller; }
.log { font-family: monospace; font-size: 9pt; }
""".replace("GREEN", GREEN)


# ---------------------------------------------------------------- utilidades de interfaz

def label(text, *classes, xalign=0.0, **kw):
    lbl = Gtk.Label(label=text, xalign=xalign, **kw)
    for c in classes:
        lbl.get_style_context().add_class(c)
    return lbl


def css(widget, *classes):
    for c in classes:
        widget.get_style_context().add_class(c)
    return widget


def icon(name, size=16):
    img = Gtk.Image.new_from_icon_name(name, Gtk.IconSize.BUTTON)
    img.set_pixel_size(size)
    return img


# Logotipos de los paquetes (Simple Icons, CC0: un solo trazo en una caja de 24x24). Cada marca
# es de su dueño; se usan solo para identificar cada paquete
LOGO_PATHS = {
    "php": (
        "M7.01 10.207h-.944l-.515 2.648h.838c.556 0 .97-.105 1.242-.314.272-.21.455-.559.55-1.049"
        ".092-.47.05-.802-.124-.995-.175-.193-.523-.29-1.047-.29zM12 5.688C5.373 5.688 0 8.514 0 "
        "12s5.373 6.313 12 6.313S24 15.486 24 12c0-3.486-5.373-6.312-12-6.312zm-3.26 7.451c-.261."
        "25-.575.438-.917.551-.336.108-.765.164-1.285.164H5.357l-.327 1.681H3.652l1.23-6.326h2.65"
        "c.797 0 1.378.209 1.744.628.366.418.476 1.002.33 1.752a2.836 2.836 0 0 1-.305.847c-.143."
        "255-.33.49-.561.703zm4.024.715l.543-2.799c.063-.318.039-.536-.068-.651-.107-.116-.336-.1"
        "74-.687-.174H11.46l-.704 3.625H9.388l1.23-6.327h1.367l-.327 1.682h1.218c.767 0 1.295.134"
        " 1.586.401s.378.7.263 1.299l-.572 2.944h-1.389zm7.597-2.265a2.782 2.782 0 0 1-.305.847c-"
        ".143.255-.33.49-.561.703a2.44 2.44 0 0 1-.917.551c-.336.108-.765.164-1.286.164h-1.18l-.3"
        "27 1.682h-1.378l1.23-6.326h2.649c.797 0 1.378.209 1.744.628.366.417.477 1.001.331 1.751z"
        "M17.766 10.207h-.943l-.516 2.648h.838c.557 0 .971-.105 1.242-.314.272-.21.455-.559.551-1"
        ".049.092-.47.049-.802-.125-.995s-.524-.29-1.047-.29z"
    ),
    "apache": (
        "M17.805 2.197v.066h.156v.44h.072v-.44h.156v-.066zm.9 0l-.175.353-.172-.353h-.087v.506h.0"
        "67V2.3l.172.35h.045l.172-.35v.404h.066v-.506zm-4.257 1c-.204.31-.424.66-.66 1.06l-.04.06"
        "2a44.457 44.457 0 00-1.265 2.29c-.187.36-.38.742-.577 1.146l2.267-.25c.66-.302.955-.578 "
        "1.242-.976a15.5 15.5 0 00.23-.342c.23-.363.46-.763.663-1.16.197-.386.37-.767.505-1.11.08"
        "3-.22.15-.422.198-.6.042-.158.074-.307.1-.45-.884.15-1.965.295-2.668.33zM11.894 7.78l-.0"
        "77.16c-.078.16-.157.32-.236.488-.086.18-.172.364-.26.552l-.132.287a75.265 75.265 0 00-1."
        "427 3.3c-.163.397-.327.807-.493 1.23-.15.38-.297.765-.45 1.164l-.02.06c-.15.396-.3.802-."
        "453 1.22l-.01.027.72-.08a.213.213 0 01-.042-.006c.863-.106 2.01-.75 2.75-1.547.342-.367."
        "652-.8.94-1.306.213-.377.413-.795.604-1.258.168-.405.328-.843.48-1.318-.196.105-.423.18-"
        ".673.235a2.184 2.184 0 01-.273.046c.806-.31 1.314-.905 1.683-1.64a2.816 2.816 0 01-.968."
        "428c-.06.012-.116.022-.174.03l-.043.006h.002c.278-.118.514-.248.718-.403a2.571 2.571 0 0"
        "0.637-.698l.063-.104.077-.154a8.107 8.107 0 00.367-.85l.03-.088a3.04 3.04 0 00.123-.463."
        "733.733 0 01-.094.065c-.243.145-.66.277-.996.34l.663-.074-.664.073h-.017l-.1.017c.006-.0"
        "03.01-.006.017-.008l-2.265.25-.013.022zM8.27 16.45c-.117.323-.236.654-.355.992l-.005.015"
        "c-.016.046-.032.094-.05.142-.08.227-.15.432-.31.9.264.12.475.435.675.793a1.44 1.44 0 00-"
        ".466-.99c1.293.06 2.41-.27 2.99-1.217.05-.084.096-.173.14-.268-.26.333-.59.474-1.2.44 0 "
        "0-.004 0-.005.002l.004-.002c.9-.404 1.354-.79 1.754-1.433.094-.153.186-.32.28-.503-.788."
        "81-1.702 1.04-2.664.865l-.72.078a6.43 6.43 0 00-.067.183zM15.42.112c-.376.222-1 .85-1.74"
        "8 1.763l.686 1.294c.48-.687.97-1.307 1.462-1.836l.058-.062c-.02.02-.04.04-.057.062-.16.1"
        "76-.644.74-1.375 1.863.703-.035 1.784-.18 2.666-.33.262-1.47-.258-2.142-.258-2.142s-.66-"
        "1.07-1.436-.61zm-3.084 6.402a40.253 40.253 0 011.306-2.26l.04-.064c.224-.352.45-.693.677"
        "-1.02l-.685-1.293-.157.192c-.197.245-.403.51-.613.79a39.853 39.853 0 00-2.016 2.97l-.022"
        ".038.893 1.763c.19-.378.38-.752.575-1.118zm-3.73 8.32c.158-.406.319-.81.483-1.225.156-.3"
        "94.32-.79.484-1.19a91.133 91.133 0 011.6-3.604l.205-.424c.12-.243.237-.485.36-.724a.125."
        "125 0 01.02-.04l-.895-1.763-.044.07c-.207.34-.414.687-.617 1.042a38.056 38.056 0 00-1.09"
        "2 2.04l-.094.193a24.573 24.573 0 00-1.258 3.087 18.492 18.492 0 00-.52 1.997l.896 1.77c."
        "117-.317.24-.638.364-.963zm-1.376-.476a13.38 13.38 0 00-.234 1.692c0 .02-.004.04-.005.06"
        "-.28-.45-1.03-.888-1.026-.884.537.778.944 1.55 1.005 2.31-.29.058-.684-.027-1.14-.195.47"
        "5.436.83.556.97.588-.434.03-.89.328-1.346.67.668-.27 1.21-.38 1.596-.29-.61 1.74-1.23 3."
        "655-1.843 5.69a.538.538 0 00.364-.354c.11-.368.84-2.786 1.978-5.965l.097-.27.028-.078c.1"
        "2-.332.246-.672.374-1.02l.09-.237v-.004L7.24 14.3c-.003.02-.01.04-.012.06z"
    ),
    "mariadb": (
        "M23.157 4.412c-.676.284-.79.31-1.673.372-.65.045-.757.057-1.212.209-.75.246-1.395.75-2.0"
        "2 1.59-.296.398-1.249 1.913-1.249 1.988 0 .057-.65.998-.915 1.32-.574.713-1.08 1.079-2.1"
        "4 1.59-.77.36-1.224.524-4.102 1.477-1.073.353-2.133.738-2.367.864-.852.449-1.515 1.036-2"
        ".203 1.938-1.003 1.32-.972 1.313-3.042.947a12.264 12.264 0 00-.675-.063c-.644-.05-1.023."
        "044-1.332.334L0 17.193l.177.088c.094.05.353.234.561.398.215.17.461.347.55.391.088.044.17"
        ".088.183.101.012.013-.089.17-.228.353-.435.581-.593.871-.574 1.048.019.164.032.17.43.17."
        "517-.006.826-.056 1.261-.208.65-.233 2.058-.94 2.784-1.4.776-.5 1.717-.998 1.956-1.042.0"
        "82-.02.354-.07.594-.114.58-.107 1.464-.095 2.587.05.108.013.373.045.6.064.227.025.43.057"
        ".454.076.026.012.474.037.998.056.934.026 1.104.007 1.3-.189.126-.133.385-.631.498-.985.2"
        "09-.643.417-.921.366-.492-.113.966-.322 1.692-.713 2.411-.259.499-.663 1.092-.934 1.395-"
        ".322.347-.315.36.088.315.619-.063 1.471-.397 2.096-.82.827-.562 1.647-1.691 2.19-3.03.10"
        "7-.27.22-.22.183.083-.013.094-.038.315-.057.498l-.031.328.353-.202c.833-.48 1.414-1.262 "
        "2.127-2.884.227-.518.877-2.922 1.073-3.976a9.64 9.64 0 01.271-1.042c.127-.429.196-.555.4"
        "8-.858.183-.19.625-.555.978-.808.72-.505.953-.75 1.187-1.205.208-.417.284-1.13.132-1.357"
        "-.132-.202-.284-.196-.763.006Z"
    ),
    "phpmyadmin": (
        "M5.463 3.476C6.69 5.225 7.497 7.399 7.68 9.798a12.9 12.9 0 0 1-.672 5.254 4.29 4.29 0 0 "
        "1 2.969-1.523c.05-.004.099-.006.148-.008.08-.491.47-3.45-.977-6.68-1.068-2.386-3-3.16-3."
        "685-3.365Zm1.777.037s2.406 1.066 3.326 5.547c.607 2.955.049 4.836-.402 5.773a7.347 7.347"
        " 0 0 1 4.506-1.994c.86-.065 1.695.02 2.482.233-.1-.741-.593-3.414-2.732-5.92-3.263-3.823"
        "-7.18-3.64-7.18-3.64Zm14.817 9.701-17.92 3.049a2.284 2.284 0 0 1 1.535 2.254 2.31 2.31 0"
        " 0 1-.106.61c.055-.027 2.689-1.275 6.342-2.034 3.238-.673 5.723-.36 6.285-.273a6.46 6.46"
        " 0 0 1 3.864-3.606zm-6.213 4.078c-2.318 0-4.641.495-6.614 1.166-2.868.976-2.951 1.348-5."
        "55 1.043C1.844 19.286 0 18.386 0 18.386s2.406 1.97 4.914 2.127c1.986.125 3.505-.822 5.31"
        "5-1.414 2.661-.871 4.511-.97 6.253-.975C19.361 18.116 24 19.353 24 19.353s-2.11-1.044-5."
        "033-1.72a13.885 13.885 0 0 0-3.123-.34Z"
    ),
    "perl": (
        "M11.638 0c-.148 0-.207.689-.252 2.925-.058 2.86-.07 2.949-.51 3.914-.36.793-1.623 2.676-"
        "2.037 3.04-.373.328-1.183 1.56-1.58 2.401-.71 1.504-.659 3.52-.04 5.047.518 1.194 1.262 "
        "2.156 2.46 3.182.94.805 1.23.919 1.375.544.049-.128-.162-.572-.483-1.018-.313-.436-.843-"
        "1.362-1.178-2.059-1.382-2.926-.7-5.357.902-8.045.89-1.393 1.403-2.642 1.579-3.852.22-1.5"
        "15.043-6.079-.236-6.079zm-.757 1.215c-.186 0-.228.26-.228 1.422 0 .782-.08 1.654-.177 1."
        "938-.312.914-1.154 1.737-3.482 3.404-1.684 1.205-3.096 2.652-3.64 3.732-1.666 3.299-.195"
        " 7.311 3.42 9.333 1.613.902 2.966 1.253 2.966.768 0-.126-.054-.228-.121-.228s-.632-.332-"
        "1.254-.738c-2.69-1.755-3.947-3.927-3.747-6.482.15-1.91.873-3.08 3.796-6.135 2.522-2.636 "
        "2.69-2.97 2.693-5.304.001-1.42-.036-1.71-.226-1.71zm1.508.632c-.103.017-.14.905-.142 2.9"
        "03l-.004 2.926-.744 2.812c-.83 2.54-.954 5.133-.345 7.725.558 2.202.796 2.638 1.567 2.85"
        "7.343.098.89.355 1.216.572.736.49 1.395.435 2.715-.232 1.92-.97 3.209-2.222 4.067-3.953."
        "745-1.648.856-3.71.068-5.35-.7-1.414-1.882-2.554-4.358-4.197-2.162-1.436-2.617-1.82-3.15"
        "-2.652-.322-.503-.369-.724-.308-1.444.04-.468.126-.978.192-1.134.101-.239.069-.268-.202-"
        ".182-.26.082-.34.027-.42-.286-.061-.245-.112-.372-.152-.365zm.714 4.586c.034-.007.135.11"
        "3.252.306.144.237 1.022 1 1.952 1.697 2.888 2.189 5.27 4.378 4.087 8.2-.405 1.146-.99 2."
        "07-1.963 3.098-.544.575-1.266 1.09-1.53 1.09-.047 0 .252-.43.664-.954 1.337-1.7 1.972-3."
        "718 1.79-5.674-.168-1.796-1.557-3.975-3.753-5.89-.912-.796-1.518-1.536-1.512-1.846 0-.01"
        "6.005-.025.013-.027zm-1.089 15.492c-.208-.006-.297.349-.297 1.121 0 .94.018.988.342.942."
        "302-.042.347-.15.387-.899.032-.613-.019-.902-.183-1.039-.097-.08-.18-.123-.249-.125zm-1."
        "052.28c-.124-.002-.226.14-.327.43-.085.245-.253.481-.373.527-.322.124-.264.55.075.55.162"
        " 0 .402-.109.534-.24.441-.442.579-.824.382-1.062-.111-.134-.206-.203-.29-.205zm2.074.063"
        "c-.312 0-.28.61.053 1.034.309.392.908.567.908.264 0-.252-.775-1.298-.961-1.298z"
    ),
    "xampp": (
        "M16.792,11.923c0.113,0.043,0.226,0.079,0.334,0.128c0.45,0.203,0.715,0.553,0.748,1.044 c0"
        ".041,0.634,0.044,1.271,0.002,1.905c-0.049,0.732-0.725,1.292-1.483,1.271c-0.735-0.021-1.3"
        "69-0.62-1.397-1.341 c-0.017-0.441-0.003-0.884-0.006-1.326c-0.001-0.239-0.003-0.242-0.245"
        "-0.243c-1.363-0.001-2.726,0.008-4.089-0.003 c-0.888-0.007-1.421,0.482-1.471,1.46c-0.019,"
        "0.38-0.1,0.727-0.357,1.018c-0.397,0.451-0.898,0.601-1.472,0.466 c-0.554-0.131-0.867-0.52"
        "2-1.035-1.048c-0.117-0.367-0.056-0.737,0.012-1.094c0.341-1.797,1.366-3.006,3.125-3.555 c"
        "0.357-0.112,0.731-0.166,1.105-0.166c0.94,0.001,1.881,0.001,2.821-0.001c0.128,0,0.257-0.0"
        "12,0.385-0.021 c0.702-0.051,1.166-0.511,1.22-1.352c0.004-0.064,0-0.129,0.001-0.193c0.011"
        "-0.788,0.605-1.396,1.393-1.425 c0.787-0.029,1.438,0.527,1.493,1.318c0.076,1.083-0.265,2."
        "046-0.913,2.907C16.903,11.751,16.819,11.816,16.792,11.923z M8.249,10.436c-0.258-0.008-0."
        "571,0.018-0.882-0.035c-0.536-0.09-0.876-0.39-1.02-0.916C6.19,8.912,6.25,8.388,6.698,7.96"
        " C7.154,7.526,7.694,7.4,8.285,7.645c0.52,0.216,0.859,0.731,0.89,1.293C9.2,9.382,9.178,9."
        "828,9.182,10.272 c0.001,0.116-0.043,0.167-0.161,0.165C8.781,10.434,8.542,10.436,8.249,10"
        ".436z M21.682,0H2.318C1.102,0,0.116,0.986,0.116,2.202 v19.317c0,1.37,1.111,2.481,2.481,2"
        ".481h18.807c1.37,0,2.481-1.111,2.481-2.481V2.202C23.884,0.986,22.898,0,21.682,0z M20.125"
        ",12.473c0.519,0.804,0.733,1.69,0.677,2.657c-0.108,1.886-1.413,3.474-3.25,3.916c-2.585,0."
        "623-4.566-0.923-5.233-2.794 c-0.109-0.304-0.16-0.622-0.224-0.985c-0.068,0.414-0.115,0.78"
        "9-0.264,1.134c-0.697,1.617-1.884,2.603-3.665,2.799 c-2.104,0.232-4.048-1.067-4.632-3.084"
        "c-0.25-0.863-0.175-1.747-0.068-2.625c0.08-0.653,0.321-1.268,0.632-1.848 c0.057-0.106,0.0"
        "57-0.184-0.01-0.285c-0.561-0.845-0.779-1.777-0.7-2.784C3.43,8.035,3.56,7.52,3.805,7.038 "
        "C4.52,5.626,6.09,4.427,8.193,4.626c1.849,0.175,3.562,1.77,3.83,3.564c0.013,0.09,0.039,0."
        "178,0.068,0.311 c0.044-0.241,0.076-0.439,0.118-0.636c0.344-1.63,1.94-3.335,4.201-3.357c2"
        ".292-0.021,3.99,1.776,4.31,3.446 c0.17,0.888,0.089,1.776-0.103,2.663c-0.112,0.517-0.31,1"
        ".008-0.524,1.492C20.034,12.245,20.043,12.345,20.125,12.473z"
    ),
    "wordpress": (
        "M21.469 6.825c.84 1.537 1.318 3.3 1.318 5.175 0 3.979-2.156 7.456-5.363 9.325l3.295-9.52"
        "7c.615-1.54.82-2.771.82-3.864 0-.405-.026-.78-.07-1.11m-7.981.105c.647-.03 1.232-.105 1."
        "232-.105.582-.075.514-.93-.067-.899 0 0-1.755.135-2.88.135-1.064 0-2.85-.15-2.85-.15-.58"
        "5-.03-.661.855-.075.885 0 0 .54.061 1.125.09l1.68 4.605-2.37 7.08L5.354 6.9c.649-.03 1.2"
        "34-.1 1.234-.1.585-.075.516-.93-.065-.896 0 0-1.746.138-2.874.138-.2 0-.438-.008-.69-.01"
        "5C4.911 3.15 8.235 1.215 12 1.215c2.809 0 5.365 1.072 7.286 2.833-.046-.003-.091-.009-.1"
        "41-.009-1.06 0-1.812.923-1.812 1.914 0 .89.513 1.643 1.06 2.531.411.72.89 1.643.89 2.977"
        " 0 .915-.354 1.994-.821 3.479l-1.075 3.585-3.9-11.61.001.014zM12 22.784c-1.059 0-2.081-."
        "153-3.048-.437l3.237-9.406 3.315 9.087c.024.053.05.101.078.149-1.12.393-2.325.609-3.582."
        "609M1.211 12c0-1.564.336-3.05.935-4.39L7.29 21.709C3.694 19.96 1.212 16.271 1.211 12M12 "
        "0C5.385 0 0 5.385 0 12s5.385 12 12 12 12-5.385 12-12S18.615 0 12 0"
    ),
    "prestashop": (
        "M11.558 1.034C5.174 1.034 0 6.21 0 12.592c0 1.258.201 2.47.574 3.597l.002-.007a12.415 12"
        ".415 0 01.53-1.787l.011-.03c.085-.222.179-.442.277-.66l.084-.181c.08-.171.165-.34.253-.5"
        "07.036-.068.07-.136.108-.203.02-.038.044-.073.064-.11.094-.166.19-.332.29-.493l.075-.114"
        "c.125-.195.256-.386.393-.573l.035-.05c.144-.193.295-.38.451-.563l.1-.118c.155-.177.315-."
        "35.481-.517l.099-.097a10.321 10.321 0 01.546-.503c.74-2.48 3.005-4.285 5.686-4.285 1.079"
        " 0 2.152.31 3.071.873a6.017 6.017 0 012.211 2.407l.007.015.04.074v.003l.004.002a9.925 9."
        "925 0 011.567 1.198c.04.037.081.071.12.109.002 0 .006.005.007.006l-.002-.006-.001-.004v-"
        ".003l.042-.084c.377-2.384 1.43-4.102 2.67-4.102.934 0 1.762.975 2.276 2.476l.005.016.001"
        ".002c.145.158.287.331.424.521l.007.01.021.067-.02-.078c-1.542-4.569-5.863-7.857-10.952-7"
        ".857zM9.927 5.477C7.586 5.52 5.34 7.132 4.574 9.365l-.012.034a10.14 10.14 0 011.315-.895"
        "c2.806-1.656 6.479-1.646 9.278.016-.895-1.653-2.631-2.819-4.5-3.004a5.14 5.14 0 00-.728-"
        ".039zm9.834.5a1.36 1.36 0 00-.39.067c-1.265.562-1.719 2.073-2.031 3.303l-.016.072c.365-."
        "62.808-1.215 1.396-1.642.835-.687 2.105-.655 2.916.053.308.326.141.008.031-.22-.342-.75-"
        "1.025-1.653-1.906-1.634zM21.67 7.98zm-9.32.335l-1.07 3.27-.002.005-.006.002-4.498 1.112h"
        "-.009l4.456 1.087c.105.11.227.205.36.28h.002c.042.024.085.045.129.065l.01.005c.041.018.0"
        "83.033.126.047l.021.008c.04.013.08.023.12.032l.033.008a1.677 1.677 0 00.318.033 1.546 1."
        "546 0 001.43-.948c.08-.186.123-.39.123-.604v-.011l-.001-.012c-.001-.054-.004-.107-.01-.1"
        "6l-.001-.002a1.506 1.506 0 00-.026-.153l-.001-.004a1.511 1.511 0 00-.096-.288v-.003a1.52"
        "1 1.521 0 00-.348-.49v-.003zm3.148.626c.048 1.008.036 2.046-.1 3.057-.17 2.018-1.19 3.79"
        "8-1.972 5.616l-.03.08-.035.086c1.51-1.522 3.17-3.04 3.969-5.082.383-.636.118-1.342-.115-"
        "1.976-.17-.877-1.069-1.278-1.717-1.781zm6.172.572l-.588 2.688a1.764 1.764 0 00-.047.2c-."
        "002.02-.007.04-.01.06a1.76 1.76 0 00-.016.222l-.002.031h.003c0 .628.297 1.136.663 1.137a"
        ".41.41 0 00.182-.045l.027-.015a.537.537 0 00.07-.047c.013-.01.024-.022.036-.033a.752.752"
        " 0 00.137-.168l.03-.054a1.23 1.23 0 00.052-.108l.017-.04c.02-.053.038-.108.053-.166l.002"
        "-.002.001-.003.404-.451-.407-.456v.001l-.02-.063zm-4.381.856c.69 1.716.85 3.707.091 5.43"
        "-.49 1.368-1.587 2.463-1.874 3.905.73.115 1.468.176 2.21.186 2.166.029 4.332-.42 6.284-1"
        ".365-2.04-2.869-4.121-5.755-6.711-8.156zm-4.948.977a.583.583 0 110 1.166.583.583 0 010-1"
        ".166zm9.352.37c.138 0 .249.19.249.426s-.111.426-.249.426c-.137 0-.248-.19-.248-.426 0-.2"
        "35.11-.426.248-.426zm-4.044.184c-.016.112-.033.209-.05.29l-.006.023c-.01.05-.022.094-.03"
        "3.128-.48 1.417-1.275 2.52-2.36 3.697-.147.16-.301.32-.459.484a58.883 58.883 0 01-1.196 "
        "1.205c-.112.11-.259.261-.425.436-.103.287-.22.61-.318.95-.044-.016-.086-.031-.131-.049-2"
        ".108-.815-3.519-1.904-3.519-1.904s1.086 1.414 2.915 2.74c.177.129.351.24.522.339-.075 1."
        "194.452 2.34 2.83 2.682a4.81 4.81 0 001.228.008l-.01-.029a.062.062 0 00-.004-.01s-.167-."
        "133-.379-.377a3.842 3.842 0 01-.584-.897 3.382 3.382 0 01-.266-.862 3.176 3.176 0 01-.00"
        "6-.972c.017-.12.04-.241.072-.366.093-.374.255-.772.507-1.192l.002-.003.241-.404c1.103-1."
        "86 1.797-3.275 1.506-5.441a8.943 8.943 0 00-.078-.476zm4.668.576zm.013.203l.003.036v.01c"
        "0 .013-.003.025-.003.038 0-.014.003-.028.003-.043 0-.014-.002-.026-.003-.04zm-.012.275v."
        "001l-.002.01-.002.014.004-.025zm1.353 5.928c-2.553 1.138-5.44 1.44-8.192 1.007-.14 1.108"
        ".384 2.218 1.214 2.93l.012.01c2.703-.433 4.975-2.168 6.966-3.946z"
    ),
    # Bola del mundo (abrir el proyecto en el navegador), la de Material Icons
    "globo": (
        "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93"
        " 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1"
        "-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"
    ),
}

# Color de cada logotipo: el de la marca y, con el tema oscuro, uno algo más claro para que se vea
LOGO_COLORS = {"php": ("#777BB4", "#9A9ED6"), "apache": ("#D22128", "#EE5A4F"),
               "mariadb": ("#003545", "#C99A6E"), "phpmyadmin": ("#6C78AF", "#929CD2"),
               "perl": ("#39457E", "#7D95CF"), "xampp": ("#FB7A24", "#FB8A3C"),
               "wordpress": ("#21759B", "#55A6D2"), "prestashop": ("#DF0067", "#F0498F"),
               "globo": ("#1C71D8", "#62A0EA")}
_logo_cache = {}


def dark_theme():
    """¿El tema es oscuro? (por el color de fondo de las ventanas)"""
    if "dark" not in _logo_cache:
        ctx = Gtk.Window().get_style_context()
        found, bg = ctx.lookup_color("theme_bg_color")
        _logo_cache["dark"] = found and (0.299 * bg.red + 0.587 * bg.green + 0.114 * bg.blue) < 0.5
    return _logo_cache["dark"]


def logo(name, size=18):
    """Logotipo de un paquete en su color, nítido también en pantallas con escala 2."""
    scale = max(1, Gdk.Display.get_default().get_monitor(0).get_scale_factor())
    key = (name, size, scale)
    if key not in _logo_cache:
        color = LOGO_COLORS[name][1 if dark_theme() else 0]
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="%d" height="%d">'
               '<path fill="%s" d="%s"/></svg>' % (size * scale, size * scale, color,
                                                   LOGO_PATHS[name]))
        loader = GdkPixbuf.PixbufLoader.new_with_type("svg")
        loader.write(svg.encode())
        loader.close()
        _logo_cache[key] = loader.get_pixbuf()
    img = Gtk.Image()
    img.set_from_surface(Gdk.cairo_surface_create_from_pixbuf(_logo_cache[key], scale, None))
    return img


def symbol(name, size=18):
    """Icono simbólico del tema (con otro de reserva si el tema no lo tiene)."""
    if not Gtk.IconTheme.get_default().has_icon(name):
        name = "applications-system-symbolic"
    return icon(name, size)


# Icono de cada apartado, por el principio de su título: ("logo", paquete) o ("icono", nombre,
# clase de color)
SECTION_ICONS = [
    ("Versión activa", ("logo", "php")),
    ("Instalar nuevas versiones de PHP", ("logo", "php")),
    ("Instaladas", ("logo", "xampp")),
    ("Hay un XAMPP sin registrar", ("logo", "xampp")),
    ("XAMPP sin registrar", ("logo", "xampp")),
    ("Otras opciones", ("icono", "view-more-symbolic", "")),
    ("Hay procesos de otras versiones", ("icono", "dialog-warning-symbolic", "aviso-suave")),
    ("BBDD por versión", ("logo", "mariadb")),
    ("Buscar una BBDD", ("icono", "system-search-symbolic", "")),
    ("Subir o actualizar una BBDD", ("icono", "document-send-symbolic", "")),
    ("Se puede entrar desde otros equipos", ("icono", "network-wired-symbolic", "aviso-suave")),
    ("phpMyAdmin antiguo", ("logo", "phpmyadmin")),
    ("Certificados en los que confía", ("icono", "channel-insecure-symbolic", "aviso-suave")),
    ("Servicios", ("icono", "network-server-symbolic", "")),
    ("Host falseado", ("icono", "security-high-symbolic", "")),
    ("Dominios de los vhosts", ("logo", "apache")),
    ("Nuevo proyecto con dominio falseado", ("icono", "folder-new-symbolic", "verde-suave")),
    ("Configuración", ("icono", "document-properties-symbolic", "")),
    ("Carpetas", ("icono", "folder-symbolic", "")),
    ("Programa", ("icono", "system-software-install-symbolic", "")),
    ("Información", ("icono", "dialog-information-symbolic", "")),
    ("Registro de errores", ("icono", "text-x-generic-symbolic", "")),
    ("Cargar proyecto", ("icono", "folder-open-symbolic", "verde-suave")),
]


# Icono de cada fila, por su título: los títulos de los apartados no llevan icono, lo llevan las
# filas que contienen. Exactos (títulos cortos) y por el principio
ROW_ICONS_EXACT = {
    "Dominio": ("icono", "web-browser-symbolic", ""),
    "Carpeta": ("icono", "folder-symbolic", ""),
    "BBDD": ("logo", "mariadb"),
    "Proyecto": ("icono", "folder-open-symbolic", ""),
    "Proyectos": ("icono", "folder-symbolic", ""),
    "Novedades": ("icono", "starred-symbolic", ""),
    "Acerca de": ("icono", "help-about-symbolic", ""),
    "error_log": ("logo", "apache"),
}
ROW_ICONS = [
    ("Versiones sin proteger", ("icono", "network-wired-symbolic", "aviso-suave")),
    ("Abierto a la red", ("icono", "network-wired-symbolic", "aviso-suave")),
    ("phpMyAdmin con fallos", ("logo", "phpmyadmin")),
    ("MariaDB de lampp-", ("logo", "mariadb")),
    ("Proyectos con https", ("icono", "channel-insecure-symbolic", "aviso-suave")),
    ("Proyectos que avisan", ("icono", "channel-insecure-symbolic", "aviso-suave")),
    ("Webs reales que acepta", ("icono", "channel-insecure-symbolic", "aviso-suave")),
    ("Procesos que sobran", ("icono", "dialog-warning-symbolic", "aviso-suave")),
    ("XAMPP en /opt/lampp", ("logo", "xampp")),
    ("XAMPP oficiales", ("logo", "xampp")),
    ("XAMPP ", ("logo", "xampp")),
    ("PHP ", ("logo", "php")),
    ("Otro parche concreto", ("logo", "php")),
    ("Ninguna versión activa", ("logo", "php")),
    ("No hay ninguna versión", ("logo", "php")),
    ("lampp-", ("logo", "mariadb")),
    ("Ningún dominio falseado", ("icono", "security-high-symbolic", "")),
    ("web.local → ", ("icono", "dialog-warning-symbolic", "aviso-suave")),
    ("Fichero SQL", ("icono", "text-x-generic-symbolic", "")),
    ("BBDD de destino", ("logo", "mariadb")),
    ("Virtual hosts", ("logo", "apache")),
    ("Hosts del sistema", ("icono", "network-server-symbolic", "")),
    ("Copias de seguridad", ("icono", "drive-harddisk-symbolic", "")),
    ("Registros de instalaciones", ("icono", "document-open-recent-symbolic", "")),
    ("error_log de ", ("logo", "apache")),
    ("Buscar una versión nueva", ("icono", "software-update-available-symbolic", "")),
    ("Icono en el menú de aplicaciones", ("icono", "view-app-grid-symbolic", "")),
    ("Comandos de lvm-instalador", ("icono", "utilities-terminal-symbolic", "")),
]


def row_icon_spec(title):
    if title in ROW_ICONS_EXACT:
        return ROW_ICONS_EXACT[title]
    for prefix, spec in ROW_ICONS:
        if title.startswith(prefix):
            return spec
    return None


def section_icon(spec, size=20, cls="icono-seccion"):
    """Cuadrado redondeado con el logotipo o el símbolo de un apartado."""
    box = css(Gtk.Box(valign=Gtk.Align.CENTER), cls)
    if spec[0] == "logo":
        box.pack_start(logo(spec[1], size), False, False, 0)
    else:
        box.pack_start(symbol(spec[1], size), False, False, 0)
        if spec[2]:
            css(box, spec[2])
    return box


def section_icon_for(title):
    for prefix, spec in SECTION_ICONS:
        if title.startswith(prefix):
            return section_icon(spec)
    return None


def plural(n, one, many):
    return "%d %s" % (n, one if n == 1 else many)


def ver_tuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v or "")[:3])


def pma_outdated(php, pma):
    """¿Tiene la versión un phpMyAdmin con fallos de seguridad ya corregidos? Lo mínimo: 5.2.2 desde
    PHP 7.2.5, 5.1.4 desde la 7.1.3 y 4.9.11 antes (actualizar-phpmyadmin pone la más nueva)."""
    if not ver_tuple(php):
        return False
    if not ver_tuple(pma):
        return True
    need = (5, 2, 2) if ver_tuple(php) >= (7, 2, 5) else (5, 1, 4) if ver_tuple(php) >= (7, 1, 3) else (4, 9, 11)
    return ver_tuple(pma) < need


class ActionRow(Gtk.ListBoxRow):
    """Fila con titulo, subtitulo y widgets a la izquierda (prefijo) y a la derecha (sufijo)."""

    def __init__(self, title, subtitle=None, activatable=False):
        super().__init__(activatable=activatable, selectable=False)
        self.on_activate = None
        self.header = Gtk.Box(spacing=12, margin_start=14, margin_end=12,
                              margin_top=8, margin_bottom=8)
        self.prefix = Gtk.Box(spacing=8)
        self.header.pack_start(self.prefix, False, False, 0)
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2,
                        valign=Gtk.Align.CENTER)
        self.title = label(title, ellipsize=3)
        # Titulo y, a su derecha, etiquetas de texto (como «Activa»)
        self.title_box = Gtk.Box(spacing=12)
        self.title_box.pack_start(self.title, False, True, 0)
        texts.pack_start(self.title_box, False, False, 0)
        self.subtitle = label(subtitle or "", "dim-label", "subtitulo", ellipsize=3)
        self.subtitle.set_no_show_all(not subtitle)
        texts.pack_start(self.subtitle, False, False, 0)
        self.header.pack_start(texts, True, True, 0)
        self.suffix = Gtk.Box(spacing=8)
        self.header.pack_end(self.suffix, False, False, 0)
        self.set_size_request(-1, 50)
        self.add(self.header)
        spec = row_icon_spec(title or "")
        if spec:
            self.add_prefix(section_icon(spec, 16))

    def add_title_tag(self, w):
        w.set_valign(Gtk.Align.BASELINE)
        self.title_box.pack_start(w, False, False, 0)

    def add_prefix(self, w):
        w.set_valign(Gtk.Align.CENTER)
        self.prefix.pack_start(w, False, False, 0)

    def add_suffix(self, w):
        w.set_valign(Gtk.Align.CENTER)
        self.suffix.pack_start(w, False, False, 0)


class ExpanderRow(ActionRow):
    """Fila que despliega una lista anidada al pulsarla."""

    def __init__(self, title, subtitle=None, on_toggle=None):
        super().__init__(title, subtitle, activatable=True)
        self.on_toggle = on_toggle
        self.remove(self.header)
        self.arrow = icon("pan-down-symbolic")
        self.header.remove(self.suffix)
        self.header.pack_end(self.arrow, False, False, 0)
        self.header.pack_end(self.suffix, False, False, 0)
        self.inner = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "anidada")
        self.inner.connect("row-activated", on_row_activated)
        self.revealer = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.revealer.add(self.inner)
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        vbox.pack_start(self.header, False, False, 0)
        vbox.pack_start(self.revealer, False, False, 0)
        self.add(vbox)

    def add_row(self, w):
        if not isinstance(w, Gtk.ListBoxRow):
            row = Gtk.ListBoxRow(activatable=False, selectable=False)
            row.add(w)
            w = row
        self.inner.add(w)

    def set_expanded(self, on):
        self.revealer.set_reveal_child(on)
        self.arrow.set_from_icon_name("pan-up-symbolic" if on else "pan-down-symbolic",
                                      Gtk.IconSize.BUTTON)

    def toggle(self):
        on = not self.revealer.get_reveal_child()
        self.set_expanded(on)
        if self.on_toggle:
            self.on_toggle(on)


def on_row_activated(_lb, row):
    if isinstance(row, ExpanderRow):
        row.toggle()
    elif getattr(row, "on_activate", None):
        row.on_activate()


def password_dialog(parent, user, retry):
    """Contraseña de administrador, como el diálogo de autorización del sistema: centrado y con
    aire, el icono de la aplicación con un candado, un campo estrecho y alto y los botones abajo.
    Devuelve (respuesta, contraseña)."""
    dlg = Gtk.Dialog(title="", transient_for=parent, modal=True, use_header_bar=True)
    css(dlg, "dialogo-clave")
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0, margin_start=36,
                  margin_end=36, margin_top=6, margin_bottom=28)
    ov = Gtk.Overlay(halign=Gtk.Align.CENTER, margin_bottom=18)
    app = Gtk.Image.new_from_icon_name(Gtk.Window.get_default_icon_name() or "dialog-password",
                                       Gtk.IconSize.DIALOG)
    app.set_pixel_size(64)
    ov.add(app)
    lock = css(Gtk.Box(halign=Gtk.Align.END, valign=Gtk.Align.END), "candado")
    lock.pack_start(icon("changes-prevent-symbolic", 12), False, False, 0)
    ov.add_overlay(lock)
    box.pack_start(ov, False, False, 0)
    box.pack_start(label("Contraseña de administrador", "clave-titulo", xalign=0.5,
                         margin_bottom=8), False, False, 0)
    box.pack_start(label("Esta acción necesita permisos de administrador. Escribe la contraseña "
                         "de %s para continuar." % user, "dim-label", xalign=0.5, wrap=True,
                         max_width_chars=38, justify=Gtk.Justification.CENTER), False, False, 0)
    if retry:
        box.pack_start(label("Contraseña incorrecta. Vuelve a intentarlo.", "error", xalign=0.5,
                             margin_top=10), False, False, 0)
    entry = css(Gtk.Entry(visibility=False, input_purpose=Gtk.InputPurpose.PASSWORD,
                          placeholder_text="Contraseña", halign=Gtk.Align.CENTER, margin_top=22),
                "campo-clave")
    entry.set_size_request(260, -1)
    box.pack_start(entry, False, False, 0)
    buttons = Gtk.Box(spacing=10, homogeneous=True, halign=Gtk.Align.CENTER, margin_top=22)
    buttons.set_size_request(260, -1)
    cancel = css(Gtk.Button(label="Cancelar"), "boton-grande")
    ok = css(Gtk.Button(label="Continuar", sensitive=False), "verde", "boton-grande")
    cancel.connect("clicked", lambda *_: dlg.response(Gtk.ResponseType.CANCEL))
    ok.connect("clicked", lambda *_: dlg.response(Gtk.ResponseType.OK))
    entry.connect("changed", lambda e: ok.set_sensitive(bool(e.get_text())))
    entry.connect("activate", lambda e: e.get_text() and dlg.response(Gtk.ResponseType.OK))
    buttons.pack_start(cancel, True, True, 0)
    buttons.pack_start(ok, True, True, 0)
    box.pack_start(buttons, False, False, 0)
    dlg.get_content_area().add(box)
    dlg.show_all()
    resp = run_dialog(dlg)
    password = entry.get_text()
    dlg.destroy()
    return resp, password


def info_icon(text):
    """Simbolo de informacion: al pasar el raton muestra la explicacion (en lugar de un parrafo
    gris bajo el titulo)."""
    ev = Gtk.EventBox(valign=Gtk.Align.CENTER, tooltip_text=text)
    ev.add(css(icon("dialog-information-symbolic"), "info"))
    return ev


def group(title=None, description=None):
    """Bloque con titulo (con su simbolo de informacion si hay descripcion) y una lista con
    bordes redondeados."""
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    if title or description:
        head = Gtk.Box(spacing=6)
        if title:
            head.pack_start(label(title, "grupo-titulo"), False, False, 0)
        if description:
            head.pack_start(info_icon(description), False, False, 0)
        box.pack_start(head, False, False, 0)
    lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, margin_top=6), "caja")
    lb.connect("row-activated", on_row_activated)
    box.pack_start(lb, False, False, 0)
    return box, lb


def page():
    """Pagina con desplazamiento y contenido centrado de ancho limitado."""
    sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
    content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24, margin=24,
                      halign=Gtk.Align.CENTER)
    content.set_size_request(580, -1)
    sw.add(content)
    return sw, content


def clear(box):
    for child in box.get_children():
        box.remove(child)


def airy_dialog(dlg):
    """Más aire en cualquier diálogo: las cajas verticales con separación (no las de dos líneas
    como título y subtítulo, ni lo que va dentro de listas o botones) pasan a 16 px, y el texto de
    los mensajes, más separado de los botones."""
    if getattr(dlg, "aireado", False):
        return
    dlg.aireado = True
    area = dlg.get_message_area() if isinstance(dlg, Gtk.MessageDialog) else dlg.get_content_area()

    def walk(w):
        if isinstance(w, (Gtk.ListBox, Gtk.Button, Gtk.ScrolledWindow, Gtk.TextView, Gtk.ComboBox)):
            return
        if isinstance(w, Gtk.Box) and w.get_orientation() == Gtk.Orientation.VERTICAL \
                and w.get_spacing() >= 6:
            w.set_spacing(max(w.get_spacing(), 16))
        if isinstance(w, Gtk.Container):
            for c in w.get_children():
                walk(c)
    walk(area)
    if isinstance(dlg, Gtk.MessageDialog):
        area.set_spacing(max(area.get_spacing(), 16))
        area.set_margin_top(max(area.get_margin_top(), 8))
        area.set_margin_bottom(max(area.get_margin_bottom(), 12))


def run_dialog(dlg):
    """Abre un diálogo (modal) con más aire entre sus campos. Todos los diálogos se abren así."""
    if not isinstance(dlg, Gtk.FileChooserDialog):
        airy_dialog(dlg)
    return dlg.run()


def widen(dlg):
    """Los MessageDialog parten el texto en una columna estrecha: lineas de hasta 72 caracteres"""
    for child in dlg.get_message_area().get_children():
        if isinstance(child, Gtk.Label):
            child.set_max_width_chars(72)
            child.set_width_chars(min(72, max(len(child.get_text()), 30)))
    return dlg


def message(parent, title, text="", kind=Gtk.MessageType.INFO):
    dlg = Gtk.MessageDialog(transient_for=parent, modal=True, message_type=kind,
                            buttons=Gtk.ButtonsType.CLOSE, text=title)
    if text:
        dlg.format_secondary_text(text)
    widen(dlg)
    run_dialog(dlg)
    dlg.destroy()


def markdown_to_buffer(buf, text):
    """Pinta el Markdown de «lvm-instalador novedades»: «## versión · fecha», viñetas «- » (con dos
    espacios delante, dentro de la anterior), **negrita** y `código`."""
    # (con aire: espacio entre versiones, entre puntos y entre las líneas de un mismo punto)
    buf.create_tag("h2", weight=700, scale=1.3, pixels_above_lines=30, pixels_below_lines=12)
    buf.create_tag("fecha", weight=400, scale=0.8, foreground="#888888")
    buf.create_tag("li0", left_margin=44, indent=-16, pixels_above_lines=10, pixels_below_lines=2,
                   pixels_inside_wrap=5)
    buf.create_tag("li1", left_margin=68, indent=-16, pixels_above_lines=6, pixels_below_lines=2,
                   pixels_inside_wrap=5)
    buf.create_tag("punto", foreground=GREEN, weight=700)
    buf.create_tag("b", weight=700)
    buf.create_tag("code", family="monospace", scale=0.92, background_rgba=Gdk.RGBA(0.5, 0.5, 0.5, 0.16))
    buf.create_tag("p", pixels_above_lines=6, pixels_below_lines=8, pixels_inside_wrap=5)
    first = True
    for line in text.split("\n"):
        if not line.strip():
            continue
        if not first:
            buf.insert(buf.get_end_iter(), "\n")
        first = False
        if line.startswith("## "):
            version, _, date = line[3:].partition(" · ")
            buf.insert_with_tags_by_name(buf.get_end_iter(), version, "h2")
            if date:
                buf.insert_with_tags_by_name(buf.get_end_iter(), "   " + date, "h2", "fecha")
            continue
        m = re.match(r"^( *)- (.*)$", line)
        if m:
            depth = min(len(m.group(1)) // 2, 1)
            block = "li%d" % depth
            buf.insert_with_tags_by_name(buf.get_end_iter(), "•  " if depth == 0 else "◦  ",
                                         block, "punto")
            body = m.group(2)
        else:
            block, body = "p", line
        for part in re.split(r"(\*\*[^*]+\*\*|`[^`]+`)", body):
            if not part:
                continue
            if part.startswith("**") and part.endswith("**") and len(part) > 4:
                buf.insert_with_tags_by_name(buf.get_end_iter(), part[2:-2], block, "b")
            elif part.startswith("`") and part.endswith("`") and len(part) > 2:
                buf.insert_with_tags_by_name(buf.get_end_iter(), part[1:-1], block, "code")
            else:
                buf.insert_with_tags_by_name(buf.get_end_iter(), part, block)


def confirm(parent, title, text, ok_label, destructive=False, extra=None):
    """Pregunta con Cancelar / ok_label. extra: widget opcional debajo del texto."""
    dlg = Gtk.MessageDialog(transient_for=parent, modal=True,
                            message_type=Gtk.MessageType.QUESTION,
                            buttons=Gtk.ButtonsType.NONE, text=title)
    dlg.format_secondary_text(text)
    widen(dlg)
    if extra:
        dlg.get_message_area().pack_start(extra, False, False, 0)
    dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
    ok = dlg.add_button(ok_label, Gtk.ResponseType.ACCEPT)
    css(ok, "destructive-action" if destructive else "verde")
    dlg.set_default_response(Gtk.ResponseType.CANCEL if destructive else Gtk.ResponseType.ACCEPT)
    dlg.show_all()
    dlg.ok_button = ok
    resp = run_dialog(dlg)
    dlg.destroy()
    return resp == Gtk.ResponseType.ACCEPT


# ---------------------------------------------------------------- llamadas al script

def script_cmd(*args):
    return ["/bin/bash", SCRIPT] + (["--simular"] if SIMULATE else []) + list(args)


# Solo estas variables de la sesion pasan a las tareas: el resto podria cambiar lo que hace bash
# (funciones exportadas BASH_FUNC_*, SHELLOPTS con PS4, BASH_ENV) o lo que toca el gestor con sudo
ENV_KEEP = {"HOME", "USER", "LOGNAME", "LANG", "LANGUAGE", "DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "SSH_AUTH_SOCK",
            "DBUS_SESSION_BUS_ADDRESS", "TMPDIR", "PATH", "LVM_PRUEBA", "PHP_TIMEZONE",
            "http_proxy", "https_proxy", "no_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY",
            "NO_PROXY", "ALL_PROXY"}


def script_env(**extra):
    # (en las pruebas, con LVM_PRUEBA, tambien las LVM_* que cambian las carpetas)
    test = bool(os.environ.get("LVM_PRUEBA"))
    env = {k: v for k, v in os.environ.items()
           if k in ENV_KEEP or k.startswith(("LC_", "XDG_"))
           or (test and k.startswith("LVM_") and k != "LVM_SIMULAR")}
    env.update(LVM_UI="text", SUDO_PROMPT=SUDO_MARK, TERM="dumb")
    env.update(extra)
    return env


def run_quick(args, callback, env=None):
    """Comando sin sudo ni preguntas, en segundo plano. callback(rc, salida) en la interfaz."""
    def work():
        try:
            res = subprocess.run(script_cmd(*args), stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 env=script_env(**(env or {})), timeout=180)
            out = res.stdout.decode("utf-8", "replace")
            GLib.idle_add(callback, res.returncode, out)
        except Exception as exc:  # noqa: BLE001 - cualquier fallo se muestra como error
            GLib.idle_add(callback, 1, "ERROR|%s" % exc)
    threading.Thread(target=work, daemon=True).start()


def login_page(title, project, action, fields, panel):
    """Página de acceso al panel de un proyecto con el administrador de pruebas ya escrito: un
    formulario que va a la pantalla de acceso del proyecto; solo hay que pulsar Entrar."""
    e = html.escape
    rows, hidden = "", ""
    for name, value, text in fields:
        if text:
            kind = "password" if name in ("pwd", "passwd") else "text"
            rows += ('<label>%s<input type="%s" name="%s" value="%s" autocomplete="off"></label>'
                     % (e(text), kind, e(name), e(value)))
        else:
            hidden += '<input type="hidden" name="%s" value="%s">' % (e(name), e(value))
    return """<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="referrer" content="no-referrer"><title>%(title)s · %(project)s</title>
<style>
:root { color-scheme: light dark; --bg: #f4f4f6; --card: #fff; --line: #d8d8dc; --muted: #6b6b72; --accent: #2a7ae2; }
@media (prefers-color-scheme: dark) { :root { --bg: #1e1e20; --card: #2a2a2d; --line: #444; --muted: #a0a0a6; } }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: var(--bg);
       font: 15px/1.45 system-ui, "Ubuntu", sans-serif; }
form { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 28px 32px;
       width: min(380px, calc(100vw - 32px)); box-sizing: border-box; }
h1 { font-size: 19px; margin: 0 0 4px; } p { margin: 0 0 18px; color: var(--muted); font-size: 13px; }
label { display: block; font-size: 13px; color: var(--muted); margin-bottom: 14px; }
input[type=text], input[type=password] { display: block; width: 100%%; box-sizing: border-box; margin-top: 4px;
       padding: 8px 10px; font: inherit; border: 1px solid var(--line); border-radius: 8px; background: transparent; }
button { width: 100%%; margin-top: 6px; padding: 10px; font: inherit; font-weight: 600; color: #fff;
         background: var(--accent); border: 0; border-radius: 8px; cursor: pointer; }
small { display: block; margin-top: 14px; color: var(--muted); font-size: 12px; }
</style></head><body>
<form method="post" action="%(action)s">
<h1>%(title)s</h1><p>%(project)s · administrador de pruebas de este equipo</p>
%(rows)s%(hidden)s<button type="submit" autofocus>Entrar</button>
<small>Si no entra, el panel normal está en <a href="%(panel)s">%(panel)s</a>.</small>
</form></body></html>""" % {"title": e(title), "project": e(project or "proyecto"), "action": e(action),
                            "rows": rows, "hidden": hidden, "panel": e(panel)}


def serve_once(page, seconds=60):
    """Sirve una página en 127.0.0.1 (puerto libre y ruta al azar) durante un minuto y la devuelve.
    Por http y no como fichero: el Firefox de snap no puede abrir ficheros de /tmp ni de las
    carpetas ocultas. None si no se puede."""
    body = page.encode("utf-8")
    path = "/acceso-%s" % os.urandom(8).hex()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != path:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass
    try:
        srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    except OSError:
        return None
    srv.timeout = 1
    end = time.time() + seconds

    def work():
        while time.time() < end:
            srv.handle_request()
        srv.server_close()
    threading.Thread(target=work, daemon=True).start()
    return "http://127.0.0.1:%d%s" % (srv.server_address[1], path)


def parse_lines(out):
    return [line.split("|") for line in out.splitlines() if "|" in line]


def read_progress(path):
    """Como _read_progress, pero una línea rara (un nombre de fichero con |) no rompe la tarea."""
    try:
        return _read_progress(path)
    except (ValueError, IndexError):
        return None


def _read_progress(path):
    """Interpreta el archivo de progreso del script (mismo calculo que progress_screen).
    Devuelve dict o None si aun no ha empezado."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    starts = [i for i, l in enumerate(lines) if l.startswith("I|")]
    if not starts:
        return None
    _, k, n, name, started = (lines[starts[-1]].split("|") + [""] * 5)[:5]
    section = lines[starts[-1]:]
    parts = [l.split("|", 1)[1] for l in section if l.startswith("C|")]
    parts = parts[-1].split(";") if parts else []
    steps = [l for l in section if l.startswith("S|")]
    pct, cur, what, mode, done, total = 0, 0, "", "", 0, 0
    if steps:
        f = (steps[-1].split("|") + [""] * 9)[:9]
        _, cur, frm, to, what, mode, file, total, t0 = f
        cur, frm, to = int(cur or 0), int(frm or 0), int(to or 0)
        done = 0
        try:
            if mode == "lines":
                with open(file, "rb") as fh:
                    done = sum(1 for _ in fh)
            elif mode == "bytes":
                done = os.path.getsize(file)
            elif mode == "time":
                done = int(time.time()) - int(t0 or 0)
            elif mode == "fdpos":
                with open(file, encoding="ascii", errors="replace") as fh:
                    done = next((int(l.split()[1]) for l in fh if l.startswith("pos:")), 0)
            elif mode == "percent":
                with open(file, "rb") as fh:
                    tail = fh.read()[-8000:].decode("utf-8", "replace").splitlines()[-40:]
                found = [m.group(1) for m in (re.match(r"^\[ *(\d+)%\]", t) for t in tail) if m]
                done = int(found[-1]) if found else 0
        except (OSError, ValueError):
            done = 0
        frac = 0
        if mode and int(total or 0) > 0:
            frac = min(done * 1000 // int(total), 990)
        pct = frm + (to - frm) * frac // 1000
    results = [l.split("|") for l in lines if l.startswith("R|")]
    finished = any(l.startswith("R|") for l in section)
    if finished:
        pct, cur = 100, 999
    return {"k": int(k or 1), "n": int(n or 1), "name": name, "started": int(started or 0),
            "parts": parts, "cur": cur, "what": what, "pct": pct, "mode": mode,
            "done": done, "total": int(total or 0),
            "results": [(r[1], r[2]) for r in results if len(r) > 2]}


def item_folder(item):
    """Carpeta (lampp-<carpeta>) de un elemento del plan, como item_folder del script."""
    kind, _, name = item.partition(":")
    return name.rsplit(".", 1)[0] if kind in ("php", "rehacer") else name


def fmt_size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return ("%d %s" % (n, unit)) if unit == "B" else \
                ("%.1f %s" % (n, unit)).replace(".", ",")
        n /= 1024


MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
          "septiembre", "octubre", "noviembre", "diciembre"]


def fmt_month(date):
    """2026-12-31 -> diciembre de 2026"""
    try:
        y, m = date.split("-")[:2]
        return "%s de %s" % (MONTHS[int(m) - 1], y)
    except (ValueError, IndexError):
        return date


def fmt_day(date):
    """2026-10-21 -> 21 de octubre de 2026"""
    try:
        y, m, d = date.split("-")[:3]
        return "%d de %s de %s" % (int(d), MONTHS[int(m) - 1], y)
    except (ValueError, IndexError):
        return date


def release_tag(sec):
    """Etiqueta de un parche de PHP: de seguridad (php.net lo marca así: corrige vulnerabilidades)
    o solo de errores"""
    if sec == "1":
        tag = label("Parche de seguridad", "etiqueta-parche", "seguridad-parche")
        tag.set_tooltip_text("php.net la marca como parche de seguridad: corrige vulnerabilidades. "
                             "Conviene instalarla.")
    else:
        tag = label("Corrección de errores", "etiqueta-parche", "dim-label")
        tag.set_tooltip_text("Corrige errores. php.net no la marca como parche de seguridad.")
    return tag


def branch_release(f):
    """Fecha y marca de seguridad del último parche de una línea B"""
    fields = (f + [""] * 13)[:13]
    return fields[11], fields[12]


def branch_state(f):
    """Estado en php.net de una linea B: (estado, fin del soporte activo, fin de seguridad)"""
    fields = (f + [""] * 11)[:11]
    state, active_end, security_end = fields[8], fields[9], fields[10]
    if not state:
        state = "stable" if fields[3] == "1" else "eol"
    return state, active_end, security_end


def state_pill(state, active_end, security_end):
    """Estado de una rama en su color (sin fondo): Estable, Solo seguridad o Sin soporte"""
    if state == "stable":
        pill = label("Estable", "estado", "estable")
        pill.set_tooltip_text("Recibe correcciones de errores y de seguridad"
                              + (" (hasta %s)" % fmt_month(active_end) if active_end else "")
                              + ". Es la mejor opción para proyectos nuevos.")
    elif state == "security":
        pill = label("Solo seguridad", "estado", "seguridad")
        pill.set_tooltip_text("Ya no recibe correcciones de errores, solo parches de seguridad"
                              + (" hasta %s" % fmt_month(security_end) if security_end else "")
                              + ". Sirve para proyectos que aún no funcionan con las estables.")
    else:
        pill = label("Sin soporte", "estado", "soporte-no")
        pill.set_tooltip_text("php.net ya no publica parches, ni de seguridad"
                              + (" (desde %s)" % fmt_month(security_end) if security_end else "")
                              + ". Solo para proyectos antiguos.")
    return pill


def fmt_minutes(secs):
    return "menos de 1 min" if secs < 60 else "%d min" % ((secs + 30) // 60)


def fmt_age(secs):
    """Antigüedad aproximada: hace 5 min, hace 3 h, hace 12 días, hace 4 meses, hace 2 años."""
    if secs < 3600:
        return "hace %s" % plural(max(1, secs // 60), "min", "min")
    if secs < 86400:
        return "hace %s" % plural(secs // 3600, "hora", "horas")
    if secs < 60 * 86400:
        return "hace %s" % plural(secs // 86400, "día", "días")
    if secs < 365 * 86400:
        return "hace %s" % plural(secs // (30 * 86400), "mes", "meses")
    return "hace %s" % plural(secs // (365 * 86400), "año", "años")


# Tipo c de la fecha de una base: no se ha importado con lvm-instalador
DB_DATE_HELP = ("Fecha en la que cambiaron por última vez las tablas de la BBDD (al importarla "
                "desde phpMyAdmin, por ejemplo). Las que se suben desde esta versión guardan la "
                "fecha exacta de la importación.")


def db_date_text(when, kind):
    """Fecha de una base para su fila: la de su importación o la del último cambio de sus tablas."""
    if not when:
        return ""
    stamp = time.strftime("%d/%m/%Y a las %H:%M", time.localtime(when))
    age = fmt_age(max(0, int(time.time()) - when))
    return ("Importada el %s  ·  %s" if kind == "i" else
            "Tablas cambiadas el %s  ·  %s") % (stamp, age)


# ---------------------------------------------------------------- tareas con sudo

class Task:
    """Ejecuta un comando del script en una pseudoterminal y muestra su avance en una ventana.

    progress=True: instalaciones (barra y componentes a partir de LVM_PROGRESO).
    El resto: barra en movimiento y la salida en el registro."""

    def __init__(self, app, title, args, progress=False, done_text=None, on_done=None,
                 auto_close=False, env=None, cancel_text=None):
        self.app, self.args, self.progress = app, args, progress
        self.env, self.cancel_text = env or {}, cancel_text
        self.done_text, self.on_done, self.auto_close = done_text, on_done, auto_close
        self.finished = self.cancelled = False
        self.prompts = 0
        self.since_prompt = ""
        self.pending = ""
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self.pfile = None
        self.build(title)
        self.start()

    # ventana
    def build(self, title):
        dlg = Gtk.Dialog(title=title, transient_for=self.app.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(620, -1)
        dlg.get_header_bar().set_show_close_button(False)
        dlg.connect("delete-event", lambda *_: not self.finished)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=24)
        # Al terminar bien, un check verde grande: «Terminado» en gris no se ve de un vistazo
        ok_icon = "emblem-ok-symbolic" if Gtk.IconTheme.get_default().has_icon(
            "emblem-ok-symbolic") else "object-select-symbolic"
        self.done_icon = css(icon(ok_icon, 64), "punto-verde")
        self.done_icon.set_no_show_all(True)
        box.pack_start(self.done_icon, False, False, 0)
        self.head = label(title)
        css(self.head, "title-3")
        self.head.set_line_wrap(True)
        box.pack_start(self.head, False, False, 0)
        self.bar = Gtk.ProgressBar(show_text=True)
        box.pack_start(self.bar, False, False, 0)
        self.info = label("", "dim-label")
        box.pack_start(self.info, False, False, 0)

        self.parts_box = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        self.parts_box.set_no_show_all(True)
        box.pack_start(self.parts_box, False, False, 0)
        self.parts_shown = []

        self.expander = Gtk.Expander(label="Ver registro", expanded=not self.progress)
        self.log = css(Gtk.TextView(editable=False, monospace=True, cursor_visible=False,
                                    wrap_mode=Gtk.WrapMode.CHAR), "log")
        self.log_sw = Gtk.ScrolledWindow(min_content_height=200 if self.progress else 160)
        self.log_sw.add(self.log)
        self.expander.add(self.log_sw)
        box.pack_start(self.expander, True, True, 0)

        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        # Si falla: el informe del error (o el registro) en una ventana para copiarlo
        self.report_btn = css(Gtk.Button(label="Ver el log del error"), "pildora")
        self.report_btn.set_no_show_all(True)
        self.report_btn.connect("clicked", self.show_report)
        buttons.pack_start(self.report_btn, False, False, 0)
        self.extra_btn = css(Gtk.Button(), "verde", "pildora")
        self.extra_btn.set_no_show_all(True)
        buttons.pack_start(self.extra_btn, False, False, 0)
        self.close_btn = css(Gtk.Button(label="Cancelar"), "pildora")
        self.close_btn.connect("clicked", self.on_close)
        buttons.pack_start(self.close_btn, False, False, 0)
        box.pack_start(buttons, False, False, 0)

        dlg.get_content_area().add(box)
        self.dlg = dlg
        dlg.show_all()

    def append(self, text):
        text = ANSI.sub("", text).replace("\r\n", "\n").replace("\r", "")
        if not text:
            return
        buf = self.log.get_buffer()
        buf.insert(buf.get_end_iter(), text)
        adj = self.log_sw.get_vadjustment()
        GLib.idle_add(lambda: adj.set_value(adj.get_upper() - adj.get_page_size()) and False)

    # proceso
    def start(self):
        env = script_env(**self.env)
        if self.progress:
            fd, self.pfile = tempfile.mkstemp(prefix="lvm-progreso-", dir="/tmp")
            os.close(fd)
            env["LVM_PROGRESO"] = self.pfile
        self.master, slave = pty.openpty()
        # Terminal exclusiva: ningún otro programa de tu usuario (el PHP de una web, por ejemplo)
        # puede abrirla para leer la contraseña o escribir la marca de sudo. Root (sudo) sí
        fcntl.ioctl(slave, termios.TIOCEXCL)
        fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 160, 0, 0))
        self.tty = os.fstat(slave).st_rdev

        def as_terminal():
            # La pseudoterminal es la terminal de la sesion: sudo pide ahi la contraseña y
            # recuerda la autorizacion como en una terminal normal
            fcntl.ioctl(1, termios.TIOCSCTTY, 0)

        self.proc = subprocess.Popen(script_cmd(*self.args), stdin=subprocess.DEVNULL,
                                     stdout=slave, stderr=slave, env=env,
                                     start_new_session=True, preexec_fn=as_terminal)
        os.close(slave)
        flags = fcntl.fcntl(self.master, fcntl.F_GETFL)
        fcntl.fcntl(self.master, fcntl.F_SETFL, flags | os.O_NONBLOCK)
        self.watch = GLib.io_add_watch(GLib.IOChannel.unix_new(self.master), GLib.PRIORITY_DEFAULT,
                                       GLib.IOCondition.IN | GLib.IOCondition.HUP
                                       | GLib.IOCondition.ERR, self.on_output)
        GLib.child_watch_add(GLib.PRIORITY_DEFAULT, self.proc.pid, self.on_exit)
        self.started = time.time()
        self.timer = GLib.timeout_add(1000 if self.progress else 120, self.on_timer)
        self.on_timer()

    def read_all(self):
        chunks = []
        while True:
            try:
                data = os.read(self.master, 65536)
            except BlockingIOError:
                break
            except OSError:
                return chunks, True
            if not data:
                return chunks, True
            chunks.append(data)
        return chunks, False

    def on_output(self, *_):
        chunks, closed = self.read_all()
        for data in chunks:
            self.feed(self.decoder.decode(data))
        if closed:
            self.watch = None
            return False
        return True

    def feed(self, text):
        self.pending += text
        while SUDO_MARK in self.pending:
            before, self.pending = self.pending.split(SUDO_MARK, 1)
            self.append(before)
            self.since_prompt += before
            self.ask_password()
        # Se guarda un trozo que pueda ser el principio de la marca
        keep = 0
        for i in range(1, len(SUDO_MARK)):
            if self.pending.endswith(SUDO_MARK[:i]):
                keep = i
        out, self.pending = (self.pending[:-keep], self.pending[-keep:]) if keep else \
            (self.pending, "")
        self.since_prompt += out
        self.append(out)

    def sudo_asking(self):
        """¿Hay un sudo de root de esta tarea (descendiente de su proceso) en su terminal y sin hijos?
        Es lo que pasa cuando pide la contraseña. Cualquier programa de la tarea puede escribir la
        marca (la hereda en SUDO_PROMPT) y apagar el eco: así no se le manda a él"""
        procs = {}
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            try:
                with open("/proc/%s/stat" % name, "rb") as f:
                    stat = f.read().decode("ascii", "replace")
                with open("/proc/%s/status" % name, "rb") as f:
                    status = f.read().decode("utf-8", "replace")
            except OSError:
                continue
            comm = stat[stat.find("(") + 1:stat.rfind(")")]
            rest = stat[stat.rfind(")") + 2:].split()
            uid = next((l.split()[1:3] for l in status.splitlines() if l.startswith("Uid:")), [])
            if len(rest) < 5 or len(uid) < 2:
                continue
            tty = int(rest[4])
            procs[int(name)] = (int(rest[1]), comm, uid[1], os.makedev((tty >> 8) & 0xfff,
                                                                      (tty & 0xff) | ((tty >> 12) & 0xfff00)))
        children = {}
        for pid, (ppid, *_) in procs.items():
            children.setdefault(ppid, []).append(pid)
        stack, seen, found = [self.proc.pid], set(), []
        while stack:
            p = stack.pop()
            if p in seen:
                continue
            seen.add(p)
            for c in children.get(p, []):
                stack.append(c)
                # Solo cuenta un sudo de root (el de verdad es setuid): un programa tuyo que se
                # llame sudo no vale. Y en la terminal de la tarea, sin hijos (con hijos ya está
                # ejecutando la orden y la contraseña iría a ella)
                _, comm, euid, tty = procs[c]
                if comm == "sudo" and euid == "0" and tty == self.tty and not children.get(c):
                    found.append(c)
        return bool(found)

    def ask_password(self):
        retry = self.prompts > 0 and re.search(r"(?i)sorry|lo siento|incorrect|intent",
                                               self.since_prompt)
        self.prompts += 1
        self.since_prompt = ""
        if not self.sudo_asking():
            self.append("\nAviso: se ha pedido la contraseña, pero no la pide sudo. No se ha "
                        "enviado y se cancela la tarea.\n")
            self.cancel()
            return
        resp, password = password_dialog(self.dlg, os.environ.get("USER", ""), retry)
        if resp != Gtk.ResponseType.OK:
            self.cancel()
            return
        # Mientras el cuadro estaba abierto, sudo ha podido dejar de esperar: se vuelve a mirar
        if self.finished or not self.sudo_asking():
            self.append("\nAviso: sudo ya no esperaba la contraseña. No se ha enviado.\n")
            self.cancel()
            return
        # sudo apaga el eco de la terminal antes de pedirla. Si sigue encendido, quien la pide no
        # es sudo: no se escribe (se veria en el registro o la leeria otro programa)
        try:
            echo = termios.tcgetattr(self.master)[3] & termios.ECHO
        except termios.error:
            echo = True
        if echo:
            self.append("\nAviso: se ha pedido la contraseña, pero no la pide sudo. No se ha "
                        "enviado y se cancela la tarea.\n")
            self.cancel()
            return
        try:
            os.write(self.master, (password + "\n").encode())
        except OSError:
            pass

    def on_timer(self):
        if self.finished:
            return False
        if self.progress:
            self.show_progress(read_progress(self.pfile))
        else:
            self.bar.pulse()
            self.bar.set_text("Trabajando…")
        return True

    def show_progress(self, p):
        elapsed = int(time.time() - self.started)
        if not p:
            self.bar.pulse()
            self.bar.set_text("Preparando…")
            self.info.set_label("Tiempo: %s" % fmt_minutes(elapsed))
            return
        pct = p["pct"]
        total = ((p["k"] - 1) * 100 + pct) // p["n"]
        self.head.set_label(p["name"] + ("   (%d de %d)" % (p["k"], p["n"]) if p["n"] > 1 else ""))
        self.bar.set_fraction(total / 100)
        what = p["what"] or ("terminado" if pct >= 100 else "")
        self.bar.set_text(("%s  ·  %d %%" % (what[:1].upper() + what[1:], total)) if what
                          else "%d %%" % total)
        since = int(time.time() - (p["started"] or self.started))
        text = "Tiempo: %s" % fmt_minutes(since)
        if p["mode"] == "fdpos" and p["total"]:
            text = "%s de %s   ·   %s" % (fmt_size(min(p["done"], p["total"])),
                                         fmt_size(p["total"]), text)
        if 5 <= pct < 100:
            left = since * (100 - pct) // pct
            text += "   ·   Queda menos de 1 min" if left < 60 else \
                "   ·   Queda 1 min" if left < 90 else "   ·   Quedan unos %s" % fmt_minutes(left)
        self.info.set_label(text)
        self.show_parts(p["parts"], p["cur"])

    def show_parts(self, parts, cur):
        if not parts:
            return
        if parts != self.parts_shown:
            clear(self.parts_box)
            self.part_rows = []
            for name in parts:
                r = ActionRow(name)
                st = Gtk.Stack()
                st.add_named(label("…", "dim-label"), "pend")
                st.add_named(Gtk.Spinner(active=True), "run")
                st.add_named(css(icon("object-select-symbolic"), "punto-verde"), "ok")
                st.add_named(css(icon("dialog-error-symbolic"), "error"), "error")
                r.add_suffix(st)
                self.parts_box.add(r)
                self.part_rows.append(st)
            self.parts_box.show_all()
            self.parts_box.set_visible(True)
            self.parts_shown = parts
        for i, st in enumerate(self.part_rows, 1):
            st.set_visible_child_name("ok" if i < cur else "run" if i == cur else "pend")

    def on_exit(self, _pid, status):
        rc = os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1
        chunks, _ = self.read_all()
        for data in chunks:
            self.feed(self.decoder.decode(data))
        self.append(self.pending)
        if self.watch:
            GLib.source_remove(self.watch)
        try:
            os.close(self.master)
        except OSError:
            pass
        self.finish(rc)

    def finish(self, rc):
        self.finished = True
        p = read_progress(self.pfile) if self.pfile else None
        if self.pfile:
            try:
                os.unlink(self.pfile)
            except OSError:
                pass
        ok = rc == 0 and not self.cancelled
        if self.progress:
            self.info.set_label("Tiempo total: %s" % fmt_minutes(int(time.time() - self.started)))
        self.bar.set_fraction(1 if ok else self.bar.get_fraction())
        self.close_btn.set_label("Cerrar")
        if self.cancelled:
            self.head.set_label("Cancelado")
            self.bar.set_text("Cancelado")
        elif ok:
            self.head.set_label(self.done_text or "Terminado")
            self.bar.set_text("Terminado")
            self.done_icon.show()
            self.head.set_xalign(0.5)
            css(self.head, "texto-activa")
        else:
            self.head.set_label("No se ha podido completar")
            self.bar.set_text("Error")
            self.expander.set_expanded(True)
            self.report_btn.show()
            if p and self.part_rows_present():
                for i, st in enumerate(self.part_rows, 1):
                    if i == p["cur"]:
                        st.set_visible_child_name("error")
        if p:
            self.show_results(p, ok)
        if ok and self.progress and self.part_rows_present():
            for st in self.part_rows:
                st.set_visible_child_name("ok")
        if self.on_done:
            self.on_done(ok, self, p)
        if ok and self.auto_close:
            self.dlg.destroy()
            self.app.toast(self.done_text or "Terminado")

    def log_text(self):
        buf = self.log.get_buffer()
        return buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False)

    def show_report(self, *_):
        """El informe que deja el script al fallar una instalacion (uno por version con error) o,
        si no lo hay, el registro entero"""
        log = self.log_text()
        # Solo los informes de la carpeta de registros: la linea podria escribirla otro programa
        # para mostrar (y copiar) cualquier fichero
        logs = os.path.realpath(LOG_DIR) + os.sep
        paths = [p for p in dict.fromkeys(re.findall(r"^Informe del error: (.+?)\s*$", log, re.M))
                 if os.path.realpath(p).startswith(logs) and os.path.basename(p) == "informe-error.txt"]
        parts = []
        for path in paths:
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    parts.append(f.read().rstrip())
            except OSError:
                pass
        text = ("\n\n" + "=" * 70 + "\n\n").join(parts) if parts else log.strip()
        folder = os.path.dirname(paths[-1]) if parts else LOG_DIR

        dlg = Gtk.Dialog(title="Log del error", transient_for=self.dlg, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(820, 560)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=16)
        box.pack_start(label("Copia el texto para buscar la solución o para enviarlo. "
                             + ("Incluye el sistema, el paso que ha fallado y sus errores. "
                                if parts else "")
                             + "Los logs completos están en %s." % folder,
                             "dim-label", wrap=True), False, False, 0)
        view = css(Gtk.TextView(editable=False, monospace=True, wrap_mode=Gtk.WrapMode.CHAR),
                   "log")
        view.get_buffer().set_text(text)
        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.add(view)
        box.pack_start(sw, True, True, 0)
        row = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        copy = css(Gtk.Button(label="Copiar todo"), "verde", "pildora")

        def on_copy(*_):
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)
            copy.set_label("Copiado")
            GLib.timeout_add(2000, lambda: copy.set_label("Copiar todo") and False)

        copy.connect("clicked", on_copy)
        row.pack_start(copy, False, False, 0)
        folder_btn = css(Gtk.Button(label="Abrir la carpeta de logs"), "pildora")
        folder_btn.connect("clicked", lambda *_: self.app.open_uri("file://" + folder))
        row.pack_start(folder_btn, False, False, 0)
        close = css(Gtk.Button(label="Cerrar"), "pildora")
        close.connect("clicked", lambda *_: dlg.destroy())
        row.pack_start(close, False, False, 0)
        box.pack_start(row, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.show_all()

    def part_rows_present(self):
        return bool(getattr(self, "part_rows", None))

    def show_results(self, p, ok):
        res = [r for r in p["results"] if not r[0].startswith("bd:")]
        if len(res) > 1 or (res and not ok):
            good = [i for i, rc in res if rc == "0"]
            bad = [i for i, rc in res if rc != "0"]
            text = []
            if good:
                text.append("Instaladas: " + ", ".join("lampp-" + item_folder(i) for i in good))
            if bad:
                text.append("Con error: " + ", ".join("lampp-" + item_folder(i) for i in bad)
                            + ". No se ha instalado nada de ellas; mira el registro.")
            self.info.set_label("\n".join(text))
            if res and len(good) == len(res):
                self.head.set_label(self.done_text or "Terminado")

    def offer(self, text, callback):
        self.extra_btn.set_label(text)
        self.extra_btn.connect("clicked", lambda *_: (self.dlg.destroy(), callback()))
        self.extra_btn.show()

    def cancel(self):
        if self.finished:
            return
        self.cancelled = True
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
        except OSError:
            pass

    def on_close(self, *_):
        if self.finished:
            self.dlg.destroy()
            return
        if self.progress:
            title, text, ok = self.cancel_text or (
                "¿Cancelar la instalación?",
                "Lo que se haya descargado o compilado hasta ahora se pierde. "
                "Las versiones que ya estén instaladas no se tocan.",
                "Cancelar la instalación")
            if not confirm(self.dlg, title, text, ok, destructive=True):
                return
        self.cancel()


# ---------------------------------------------------------------- aplicacion

class App(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.data = None
        self.branches = None
        self.branches_error = None
        self.expanded = set()
        self.extra_patches = []
        self.busy = False
        # Formulario «Subir o actualizar una base de datos» (se conserva al redibujar la pestaña)
        self.imp = {"file": None, "db": None, "folder": None, "project": None}
        self.db_pwd = {}
        # Dominios de los vhosts (pestaña Hosts): None hasta leerlos
        self.hosts = None
        # Apache, MariaDB y FTP de la version montada (pestaña Servicios): None hasta leerlos
        self.services = None
        # Proyectos de /opt/htdocs (bloque «Cargar proyecto» de Versiones): None hasta leerlos
        self.projects = None
        # Formulario «Nuevo proyecto con dominio falseado» (se conserva al redibujar la pestaña)
        self.newdom = {"domain": "", "folder": "", "db": ""}

    # ventana
    def do_activate(self):
        if getattr(self, "win", None):
            self.win.present()
            return
        # Mano al pasar el ratón por cualquier botón (GTK 3 no tiene cursor en CSS): se pone en la
        # ventana de eventos del botón cada vez que el ratón entra, según esté activo o no
        hand = Gdk.Cursor.new_from_name(Gdk.Display.get_default(), "pointer")

        def pointer_hook(widget, event, *_):
            if isinstance(widget, (Gtk.Button, Gtk.Switch)) and event.window is not None:
                event.window.set_cursor(hand if widget.is_sensitive() else None)
            return True
        GObject.add_emission_hook(Gtk.Widget, "enter-notify-event", pointer_hook)
        prov = Gtk.CssProvider()
        prov.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        theme = Gtk.IconTheme.get_default()
        # El icono es un PNG suelto en ~/.local/share/icons (no de un tema): has_icon no lo ve
        self.icon = ICON if theme.lookup_icon(ICON, 24, 0) else "utilities-terminal"
        Gtk.Window.set_default_icon_name(self.icon)

        for name, cb in [("localhost", lambda *_: self.open_uri("http://localhost/")),
                         ("phpmyadmin", lambda *_: self.open_uri("http://127.0.0.1/phpmyadmin/")),
                         ("vhosts", self.on_vhosts), ("hosts", self.on_hosts),
                         ("logs", lambda *_: self.open_uri("file://" + LOG_DIR)),
                         ("update", lambda *_: self.check_package(manual=True)),
                         ("terminal", self.on_terminal), ("refresh", self.on_refresh),
                         ("changes", self.on_changes), ("about", self.on_about)]:
            act = Gio.SimpleAction.new(name, None)
            act.connect("activate", cb)
            self.add_action(act)

        self.win = Gtk.ApplicationWindow(application=self, title="Nexum Stack")
        self.win.set_default_size(920, 760)

        header = Gtk.HeaderBar(show_close_button=True)
        title = Gtk.Box(spacing=8)
        title.pack_start(icon(self.icon, 24), False, False, 0)
        self.title_lbl = label("Nexum Stack", "title")
        title.pack_start(self.title_lbl, False, False, 0)
        header.set_custom_title(title)
        menu = Gio.Menu()
        sec = Gio.Menu()
        sec.append("Abrir localhost", "app.localhost")
        sec.append("Abrir phpMyAdmin", "app.phpmyadmin")
        sec.append("Editar vhosts", "app.vhosts")
        sec.append("Editar hosts", "app.hosts")
        menu.append_section(None, sec)
        sec = Gio.Menu()
        sec.append("Volver a leer las versiones", "app.refresh")
        # De momento, el .deb de Descargas; mas adelante, un repositorio
        sec.append("Buscar actualizaciones", "app.update")
        sec.append("Abrir el panel en la terminal", "app.terminal")
        sec.append("Carpeta de registros", "app.logs")
        menu.append_section(None, sec)
        sec = Gio.Menu()
        sec.append("Novedades", "app.changes")
        sec.append("Acerca de Nexum Stack", "app.about")
        menu.append_section(None, sec)
        mb = Gtk.MenuButton(menu_model=menu)
        mb.add(icon("open-menu-symbolic"))
        header.pack_end(mb)
        self.win.set_titlebar(header)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.page_versions, self.ver_box = page()
        # Instalar va dentro de Versiones, debajo de las instaladas
        self.inst_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        self.page_dbs, self.db_box = page()
        self.page_tools, self.tools_box = page()
        self.page_hosts, self.hosts_box = page()
        self.page_services, self.services_box = page()
        self.stack.add_named(self.page_versions, "versiones")
        self.stack.add_named(self.page_services, "servicios")
        self.stack.add_named(self.page_hosts, "hosts")
        self.stack.add_named(self.page_dbs, "bbdd")
        self.stack.add_named(self.page_tools, "herramientas")

        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        # Apartados en una barra a la izquierda, como Configuración de Ubuntu
        body = Gtk.Box()
        self.tabs_box = self.build_tabs()
        body.pack_start(self.tabs_box, False, False, 0)
        body.pack_start(self.stack, True, True, 0)
        main.pack_start(body, True, True, 0)
        main.pack_start(Gtk.Separator(), False, False, 0)
        self.foot = label("", "dim-label", "firma", xalign=0.5, margin=6)
        main.pack_start(self.foot, False, False, 0)

        overlay = Gtk.Overlay()
        overlay.add(main)
        overlay.add_overlay(self.build_toast())
        self.win.add(overlay)
        for box in (self.ver_box, self.db_box, self.inst_box):
            self.loading(box)
        # Los datos se leen antes de mostrar la ventana (tarda poco) para abrirla ya con el tamaño
        # que necesita la pestaña Bases de datos, sin saltos
        try:
            res = subprocess.run(script_cmd("gui-datos"), stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 env=script_env(), timeout=10)
            self.on_data(res.returncode, res.stdout.decode("utf-8", "replace"))
            self.fit_height()
        except Exception:  # noqa: BLE001 - si falla, se abre con el tamaño por defecto
            pass
        self.win.show_all()
        self.toast_rev.set_reveal_child(False)
        self.reload(branches=True)
        GLib.timeout_add_seconds(20, self.on_tick)
        # El paquete nuevo de Descargas ya no se busca solo al abrir: se instala como root y
        # cualquier web puede dejar un fichero en Descargas. Se busca desde Herramientas
        if os.environ.get("LVM_CAPTURA"):
            GLib.timeout_add(2500, self.capture_all)

    # ------------------------------------------- paquete .deb nuevo en Descargas
    def check_package(self, manual=False):
        def got(_rc, out):
            found = False
            for f in parse_lines(out):
                if f[0] == "N" and len(f) >= 5:
                    found = True
                    self.offer_package(f[1], f[2], f[3], "|".join(f[4:]))
            if manual and not found:
                self.toast("No hay ningún paquete más nuevo que la %s en Descargas"
                           % self.data["version"])
            return False
        run_quick(["gui-paquete"], got)
        return False

    def offer_package(self, version, when, sha, path):
        current = (self.data or {}).get("version", "")
        if not confirm(self.win, "Hay una versión nueva de Nexum Stack",
                       "Tienes la %s y en %s está la %s (%s, del %s).\n\nSe instala como "
                       "administrador: instálala solo si ese fichero te lo ha pasado quien hace el "
                       "programa. Su huella SHA-256 es:\n%s\n\nAl actualizar se pide la contraseña de "
                       "administrador y la ventana se vuelve a abrir con la versión nueva. Tus "
                       "versiones de PHP, tus proyectos y tus BBDD no se tocan."
                       % (current, os.path.dirname(path), version, os.path.basename(path), when,
                          sha),
                       "Actualizar a la %s" % version):
            return
        if SIMULATE:
            self.toast("[simulación] pkexec apt-get install -y %s" % path)
            return

        dlg = Gtk.Dialog(title="Actualizando", transient_for=self.win, modal=True, deletable=False)
        box = Gtk.Box(spacing=12, margin=24)
        box.pack_start(Gtk.Spinner(active=True), False, False, 0)
        box.pack_start(label("Instalando la versión %s…" % version), False, False, 0)
        dlg.get_content_area().add(box)
        dlg.show_all()

        def done(rc, out):
            dlg.destroy()
            if rc == 0:
                # La version nueva esta en /opt/lvm-instalador: se abre su ventana cuando se
                # cierre esta (misma aplicacion: si siguiera abierta, solo se traeria al frente)
                subprocess.Popen(["sh", "-c", 'sleep 1; exec "$0" ventana',
                                  "/opt/lvm-instalador/lvm-instalador.sh"], start_new_session=True,
                                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
                self.quit()
            elif rc in (126, 127):
                self.toast("Actualización cancelada")
            elif "instalalo en la terminal" in out:
                self.terminal_install(version, path)
            else:
                message(self.win, "No se ha podido actualizar", out[-1200:], Gtk.MessageType.ERROR)
            return False

        def work():
            try:
                # Con el paquete 1.30.3 o mas nuevo instalado, la contraseña se pide con el
                # mensaje en español de su accion de polkit (dev.hexer.lvm-instalador.policy)
                # El ayudante (de root) copia el paquete a su carpeta y comprueba allí la huella que
                # se ha mostrado, su contenido y sus scripts. Sin él no se instala nada desde aquí
                helper = "/opt/lvm-instalador/lvm-actualizar"
                cmd = ["pkexec", helper, path, sha]
                res = subprocess.run(cmd,
                                     stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT)
                rc, out = res.returncode, res.stdout.decode("utf-8", "replace")
            except OSError as exc:
                rc, out = 1, str(exc)
            GLib.idle_add(done, rc, out)
        threading.Thread(target=work, daemon=True).start()

    def terminal_install(self, version, path):
        """La versión nueva cambia el ayudante de actualización (o su acción de polkit): el ayudante
        instalado no la acepta, a propósito, y hay que instalarla una vez en la terminal. Se explica
        y se da la orden lista para copiar (sin el «Tubería rota» de dpkg-deb, que solo confunde)."""
        cmd = "sudo apt install %s" % shlex.quote(path)
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True, message_type=Gtk.MessageType.INFO,
                                buttons=Gtk.ButtonsType.NONE,
                                text="La versión %s se instala una vez en la terminal" % version)
        dlg.format_secondary_text(
            "Esta versión cambia el programa que instala las actualizaciones, y el que tienes no "
            "puede dar por buena su propia sustitución. No es un error ni un paquete dañado.\n\n"
            "Abre una terminal (Ctrl+Alt+T), pega esta orden y escribe tu contraseña:\n\n%s\n\n"
            "Después, abre de nuevo Nexum Stack. Las siguientes versiones se vuelven a "
            "actualizar desde aquí." % cmd)
        dlg.add_button("Copiar la orden", 1)
        dlg.add_button("Cerrar", Gtk.ResponseType.CLOSE)
        widen(dlg)
        if run_dialog(dlg) == 1:
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(cmd, -1)
            self.toast("Orden copiada: pégala en la terminal")
        dlg.destroy()

    def fit_height(self):
        """Alto inicial para que la pestaña Bases de datos se vea entera sin agrandar la ventana
        (sin pasar del alto de la pantalla)."""
        self.db_box.show_all()
        width = max(self.db_box.get_preferred_width()[1], 580)
        need = self.db_box.get_preferred_height_for_width(width)[1]
        self.foot.show_all()
        need += self.foot.get_preferred_height()[1]
        need += 1 + 24  # separador y un margen por si crece (aviso…)
        try:
            mon = Gdk.Display.get_default().get_primary_monitor() or \
                Gdk.Display.get_default().get_monitor(0)
            limit = mon.get_workarea().height - 90  # barra de título y bordes
        except Exception:  # noqa: BLE001
            limit = 1000
        height = max(760, min(need, limit))
        self.win.set_default_size(1000, height)
        return height

    def build_tabs(self):
        """Barra lateral con los apartados (como Configuración de Ubuntu)."""
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL), "lateral")
        box.set_size_request(210, -1)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE, margin_top=10),
                 "barra-lateral")
        self.tabs = {}
        # Orden: lo que mas se usa primero (cambiar de version y cargar bases de datos)
        for name, text, ic in [("versiones", "Versiones", "view-list-symbolic"),
                               ("bbdd", "BBDD", "drive-multidisk-symbolic"),
                               ("servicios", "Servicios", "network-server-symbolic"),
                               ("hosts", "Hosts", "network-workgroup-symbolic"),
                               # Lo que se usa de vez en cuando
                               ("herramientas", "Herramientas", "applications-utilities-symbolic")]:
            row = Gtk.ListBoxRow()
            inner = Gtk.Box(spacing=12)
            inner.pack_start(symbol(ic, 16), False, False, 0)
            inner.pack_start(label(text), False, False, 0)
            row.add(inner)
            row.tab_name = name
            lb.add(row)
            self.tabs[name] = row
        lb.connect("row-selected", self.on_tab)
        lb.select_row(self.tabs["versiones"])
        self.tabs_list = lb
        box.pack_start(lb, False, False, 0)
        return box

    def on_tab(self, _lb, row):
        if row is not None:
            self.stack.set_visible_child_name(row.tab_name)

    def show_tab(self, name):
        self.tabs_list.select_row(self.tabs[name])

    def build_toast(self):
        self.toast_rev = Gtk.Revealer(halign=Gtk.Align.CENTER, valign=Gtk.Align.END,
                                      margin_bottom=48)
        box = css(Gtk.Box(spacing=12), "app-notification")
        self.toast_lbl = Gtk.Label()
        box.pack_start(self.toast_lbl, False, False, 0)
        self.toast_rev.add(box)
        self.toast_timer = None
        return self.toast_rev

    def toast(self, text):
        self.toast_lbl.set_label(text)
        self.toast_rev.set_reveal_child(True)
        if self.toast_timer:
            GLib.source_remove(self.toast_timer)
        self.toast_timer = GLib.timeout_add_seconds(4, self.hide_toast)

    def hide_toast(self):
        self.toast_rev.set_reveal_child(False)
        self.toast_timer = None
        return False

    def loading(self, box, text="Leyendo…"):
        clear(box)
        spin = Gtk.Box(spacing=10, halign=Gtk.Align.CENTER, margin_top=40)
        spin.pack_start(Gtk.Spinner(active=True), False, False, 0)
        spin.pack_start(label(text, "dim-label"), False, False, 0)
        box.pack_start(spin, False, False, 0)
        box.show_all()

    def open_text(self, path):
        """Abre un fichero de texto con el editor de textos, aunque no tenga extensión (error_log,
        hosts): el programa por defecto según su contenido podría ser otro."""
        app = Gio.AppInfo.get_default_for_type("text/plain", False)
        if app is None:
            self.open_uri(GLib.filename_to_uri(path))
            return
        try:
            app.launch([Gio.File.new_for_path(path)], None)
        except GLib.Error as exc:
            message(self.win, "No se ha podido abrir %s" % path, exc.message, Gtk.MessageType.ERROR)

    def loaded_project_folder(self):
        """Carpeta del proyecto cargado (a la que apunta el enlace del vhost), solo si es una
        carpeta de htdocs."""
        p = self.projects
        if not p or not p.get("current"):
            return None
        cur = p["current"]
        real = os.path.realpath(cur if os.path.isabs(cur) else os.path.join(HTDOCS, cur))
        if os.path.dirname(real) != os.path.realpath(HTDOCS) or not os.path.isdir(real):
            return None
        return real

    def loaded_project_entry(self):
        """Datos (de gui-proyectos) del proyecto cargado, o None."""
        folder = self.loaded_project_folder()
        if folder is None:
            return None
        name = os.path.basename(folder)
        return next((x for x in self.projects["list"] if x["name"] == name), None)

    def loaded_project_db(self):
        """BBDD del proyecto cargado (la recordada o la de su configuración), o vacío."""
        x = self.loaded_project_entry()
        db = self.project_base(x) if x else ""
        return db if re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", db or "") else ""

    def loaded_project_admin(self):
        """(tipo, carpeta del panel) del proyecto cargado: wp-admin en WordPress y, en PrestaShop, su
        carpeta de administración (cada tienda la llama de una forma; se reconoce por lo que tiene)."""
        folder = self.loaded_project_folder()
        if folder is None:
            return "", ""
        if os.path.isfile(os.path.join(folder, "wp-config.php")) and os.path.isdir(os.path.join(folder, "wp-admin")):
            return "wp", "wp-admin"
        try:
            names = sorted(os.listdir(folder), key=lambda n: (not n.lower().startswith("admin"), n))
        except OSError:
            return "", ""
        for n in names:
            d = os.path.join(folder, n)
            if re.fullmatch(r"[A-Za-z0-9_-]+", n) and not os.path.islink(d) and os.path.isdir(d) \
                    and os.path.isfile(os.path.join(d, "index.php")) \
                    and any(os.path.isfile(os.path.join(d, f)) for f in ("ajax-tab.php", "get-file-admin.php")):
                return "ps", n
        return "", ""

    def open_project_pma(self):
        """phpMyAdmin con la BBDD del proyecto cargado (en http://127.0.0.1/phpmyadmin/)."""
        db = self.loaded_project_db()
        if not db:
            return
        act = next((i for i in self.installs() if i["folder"] == self.data.get("active")), None)
        # (phpMyAdmin 4 usa db= sin route)
        if act and act.get("pma", "").startswith("4."):
            self.open_uri("http://127.0.0.1/phpmyadmin/index.php?db=%s" % db)
        else:
            self.open_uri("http://127.0.0.1/phpmyadmin/index.php?route=/database/structure&db=%s" % db)

    def open_project_admin(self):
        """Panel de administración del proyecto cargado, por el vhost (web.local). Antes deja al día
        su administrador de pruebas (usuario-pruebas) y abre una página con el usuario y la
        contraseña ya escritos: basta con pulsar Entrar. Si no se puede, el panel como siempre."""
        kind, admin = self.loaded_project_admin()
        if not (admin and self.projects and self.projects["link"]):
            return
        link = self.projects["link"]
        base = "http://%s/%s/" % (link, admin)
        db, folder = self.loaded_project_db(), self.loaded_project_folder()
        if not db or SIMULATE:
            self.open_uri(base)
            return

        def done(rc, out):
            mine = [l.split("|") for l in out.splitlines() if l.startswith("A|%s|" % kind)]
            if rc != 0 or not mine or len(mine[0]) < 4:
                self.open_uri(base)
                return False
            user, password = mine[0][2], mine[0][3]
            if kind == "wp":
                action = "http://%s/wp-login.php" % link
                fields = [("log", user, "Usuario o correo"), ("pwd", password, "Contraseña"),
                          ("rememberme", "forever", None), ("redirect_to", base, None)]
                title = "Panel de WordPress"
            else:
                action = base + "index.php?controller=AdminLogin"
                fields = [("email", user, "Correo"), ("passwd", password, "Contraseña"),
                          ("stay_logged_in", "1", None), ("submitLogin", "1", None),
                          ("redirect", "AdminDashboard", None)]
                title = "Back office de PrestaShop"
            url = serve_once(login_page(title, os.path.basename(folder or ""), action, fields, base))
            self.open_uri(url) if url else self.open_uri(base)
            return False
        run_quick(["usuario-pruebas", db, os.path.basename(folder or "")], done)

    def open_in_vscode(self):
        """Abre el proyecto cargado en Visual Studio Code. Si ya tiene una ventana con esa carpeta,
        VS Code la trae delante en lugar de abrir otra."""
        folder, app = self.loaded_project_folder(), vscode_app()
        if folder is None:
            message(self.win, "No se encuentra la carpeta del proyecto cargado",
                    "El enlace del vhost no apunta a una carpeta de %s." % HTDOCS, Gtk.MessageType.WARNING)
            return
        if app is None:
            message(self.win, "Visual Studio Code no está instalado",
                    "Instálalo desde code.visualstudio.com o desde el Centro de aplicaciones.",
                    Gtk.MessageType.WARNING)
            return
        try:
            # (con el contexto de la ventana, el escritorio deja que VS Code se ponga delante)
            ctx = self.win.get_display().get_app_launch_context()
            ctx.set_timestamp(Gtk.get_current_event_time())
            app.launch([Gio.File.new_for_path(folder)], ctx)
        except GLib.Error as exc:
            message(self.win, "No se ha podido abrir Visual Studio Code", exc.message, Gtk.MessageType.ERROR)

    def open_uri(self, uri):
        try:
            Gtk.show_uri_on_window(self.win, uri, Gdk.CURRENT_TIME)
        except GLib.Error as exc:
            message(self.win, "No se ha podido abrir %s" % uri, exc.message,
                    Gtk.MessageType.ERROR)

    def on_terminal(self, *_):
        for cmd in (["gnome-terminal", "--geometry=100x32", "--", SCRIPT],
                    ["x-terminal-emulator", "-e", SCRIPT]):
            try:
                subprocess.Popen(cmd, start_new_session=True)
                return
            except OSError:
                continue
        message(self.win, "No se ha encontrado ninguna terminal",
                "Abre una terminal y escribe: lvm-instalador")

    # datos
    def reload(self, branches=False):
        run_quick(["gui-datos"], self.on_data)
        run_quick(["gui-hosts"], self.on_hosts_data)
        run_quick(["gui-servicios"], self.on_services_data)
        run_quick(["gui-proyectos"], self.on_projects_data)
        if branches:
            self.branches = None
            self.branches_error = None
            self.loading(self.inst_box, "Consultando las versiones de PHP en php.net…")
            run_quick(["gui-ramas"], self.on_branches)

    def on_refresh(self, *_):
        self.reload(branches=True)

    def on_tick(self):
        if not self.busy and self.win.is_active():
            run_quick(["gui-datos"], self.on_data)
            run_quick(["gui-hosts"], self.on_hosts_data)
            run_quick(["gui-servicios"], self.on_services_data)
            run_quick(["gui-proyectos"], self.on_projects_data)
        return True

    def on_data(self, rc, out):
        d = {"installs": [], "dbs": {}, "dbdate": {}, "active": "", "running": False,
             "unregistered": False, "native": True, "launcher": True,
             "name": "Nexum Stack", "version": "", "signature": "",
             "vhosts": "/opt/lampp/etc/extra/httpd-vhosts.conf", "hosts": "/etc/hosts",
             "stray": "", "exposed": "", "unsecured": [], "certs": [], "cas": [], "untrusted": [], "stale": [],
             "dbsys": None}
        for f in parse_lines(out):
            if f[0] == "M" and len(f) >= 4:
                d["name"], d["version"], d["signature"] = f[1], f[2], f[3]
            elif f[0] == "A" and len(f) >= 6:
                d["active"], d["running"] = f[1], f[2] == "1"
                d["unregistered"], d["native"], d["launcher"] = \
                    f[3] == "1", f[4] == "1", f[5] == "1"
            elif f[0] == "V" and len(f) >= 11:
                d["installs"].append({
                    "folder": f[1], "php": f[2], "apache": f[3], "mariadb": f[4], "ftp": f[5],
                    "perl": f[6], "pma": f[7], "kind": f[8], "owner": f[9],
                    "blocker": "|".join(f[10:]).strip()})
            elif f[0] == "D" and len(f) >= 3:
                d["dbs"].setdefault(f[1], []).append(f[2])
                if len(f) >= 5 and f[3].isdigit():
                    d["dbdate"][(f[1], f[2])] = (int(f[3]), f[4])
            elif f[0] == "H" and len(f) >= 3:
                d["vhosts"], d["hosts"] = f[1], f[2]
            elif f[0] == "Z" and len(f) >= 2:
                d["stray"] = "|".join(f[1:])
            elif f[0] == "N" and len(f) >= 2:
                d["exposed"] = "|".join(f[1:])
            elif f[0] == "U" and len(f) >= 2:
                d["unsecured"] = f[1].split()
            elif f[0] == "Y" and len(f) >= 3:
                d["dbsys"] = (f[1], int(f[2]) if f[2].isdigit() else 0)
            elif f[0] == "C" and len(f) >= 3:
                d["certs"].append((f[1], f[2]))
            elif f[0] == "W" and len(f) >= 2:
                d["cas"].append("|".join(f[1:]))
            elif f[0] == "G" and len(f) >= 2:
                d["untrusted"].append(f[1])
            elif f[0] == "Q" and len(f) >= 2:
                d["stale"].append(f[1])
        if rc != 0 and not d["installs"]:
            message(self.win, "No se han podido leer las versiones instaladas", out[-600:],
                    Gtk.MessageType.ERROR)
        if d == self.data:
            return False
        self.data = d
        self.foot.set_label("%s  ·  v%s%s" % (d["signature"], d["version"],
                                             "  ·  SIMULACIÓN: no se cambia nada"
                                             if SIMULATE else ""))
        self.build_versions()
        self.build_databases()
        self.build_services()
        self.build_tools()
        if self.branches is not None:
            self.build_install()
        return False

    def on_branches(self, rc, out):
        rows = parse_lines(out)
        err = [f for f in rows if f[0] == "ERROR"]
        self.branches = [f for f in rows if f[0] in ("B", "X")]
        self.branches_error = err[0][1] if err or rc != 0 else None
        if self.branches_error and not err:
            self.branches_error = out.strip()[-400:] or "Error al consultar las versiones"
        self.build_install()
        return False

    def installs(self):
        return self.data["installs"] if self.data else []

    # -------------------------------------------------------------- servicios
    def on_services_data(self, _rc, out):
        rows = [{"name": f[1], "running": f[2] == "1", "ports": f[3], "open": f[4] == "1",
                 "auto": f[5] == "1", "user": f[6] if len(f) > 6 else ""}
                for f in parse_lines(out) if f[0] == "S" and len(f) >= 6]
        if rows != self.services:
            self.services = rows
            self.build_services()
        return False

    def build_services(self):
        """Apache, MariaDB y el FTP de la versión montada, como el panel de XAMPP: si están en
        marcha, si se puede entrar desde la red y botones para arrancarlos, pararlos o
        reiniciarlos. El FTP no arranca con la versión: se arranca aquí cuando haga falta."""
        clear(self.services_box)
        d = self.data
        if not d or self.services is None:
            self.loading(self.services_box)
            return
        if not d["active"]:
            box, lb = group("Servicios")
            row = ActionRow("Ninguna versión activa",
                            "Activa una versión en la pestaña Versiones para ver sus servicios.")
            row.add_prefix(label("●", "punto-gris"))
            lb.add(row)
            self.services_box.pack_start(box, False, False, 0)
            self.services_box.show_all()
            return
        # Cabecera: versión, cuántos están en marcha y si solo se entra desde este equipo
        running = sum(1 for sv in self.services if sv["running"])
        exposed = any(sv["open"] for sv in self.services)
        head = Gtk.Box(spacing=12, margin_bottom=4)
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
        texts.pack_start(label("Servicios de lampp-%s" % d["active"], "titulo-grande"),
                         False, False, 0)
        texts.pack_start(label("%d de %d en marcha" % (running, len(self.services)),
                               "dim-label"), False, False, 0)
        head.pack_start(texts, True, True, 0)
        if exposed:
            badge = label("Abierto a la red", "pastilla", "peligro", valign=Gtk.Align.CENTER)
        else:
            badge = label("Solo desde este equipo", "pastilla", "segura", valign=Gtk.Align.CENTER,
                          tooltip_text="Solo se puede entrar en ellos desde este equipo (127.0.0.1 "
                                       "y ::1): los demás equipos de la red no ven los proyectos "
                                       "ni las BBDD.")
        head.pack_end(badge, False, False, 0)
        self.services_box.pack_start(head, False, False, 0)

        info = {"apache": ("Apache", "Servidor web: las webs de /opt/htdocs y phpMyAdmin (con PHP)",
                           ("logo", "apache")),
                "mariadb": ("MariaDB", "Servidor de BBDD", ("logo", "mariadb")),
                "ftp": ("FTP (ProFTPD)", "Acceso por FTP a /opt/htdocs. No arranca con la versión: "
                        "arráncalo cuando lo necesites y páralo después.",
                        ("icono", "folder-remote-symbolic", ""))}
        cards = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        for sv in self.services:
            title, help_text, spec = info.get(sv["name"], (sv["name"], "",
                                                           ("icono", "system-run-symbolic", "")))
            card = css(Gtk.Box(spacing=16), "servicio")
            card.pack_start(section_icon(spec, 26, "icono-servicio"), False, False, 0)
            mid = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4,
                          valign=Gtk.Align.CENTER)
            top = Gtk.Box(spacing=10)
            top.pack_start(label(title, "servicio-nombre"), False, False, 0)
            if sv["running"]:
                top.pack_start(label("En marcha", "pastilla", "activa", valign=Gtk.Align.CENTER),
                               False, False, 0)
            else:
                top.pack_start(label("Parado", "pastilla", "parada", valign=Gtk.Align.CENTER),
                               False, False, 0)
            if sv["open"]:
                top.pack_start(label("Abierto a la red", "pastilla", "peligro",
                                     valign=Gtk.Align.CENTER), False, False, 0)
            mid.pack_start(top, False, False, 0)
            mid.pack_start(label(help_text, "dim-label", "subtitulo", wrap=True,
                                 max_width_chars=44), False, False, 0)
            chips = Gtk.Box(spacing=6, margin_top=2)
            for port in [p.strip() for p in sv["ports"].split(",") if p.strip()]:
                chips.pack_start(label("Puerto %s" % port, "chip"), False, False, 0)
            if sv["name"] == "ftp" and sv["user"]:
                chips.pack_start(label("usuario %s" % sv["user"], "chip"), False, False, 0)
            if sv["name"] == "ftp" and sv["auto"]:
                chips.pack_start(label("arranca con la versión", "chip"), False, False, 0)
            mid.pack_start(chips, False, False, 0)
            card.pack_start(mid, True, True, 0)
            actions = Gtk.Box(spacing=8, valign=Gtk.Align.CENTER)
            buttons = [("view-refresh-symbolic", "Reiniciar", "reiniciar", None),
                       ("media-playback-stop-symbolic", "Parar", "parar", None)] \
                if sv["running"] else \
                [("media-playback-start-symbolic", "Arrancar", "arrancar", "verde")]
            for ic, text, cmd, cls in buttons:
                b = Gtk.Button()
                inner = Gtk.Box(spacing=6)
                inner.pack_start(icon(ic), False, False, 0)
                inner.pack_start(Gtk.Label(label=text), False, False, 0)
                b.add(inner)
                if cls:
                    css(b, cls)
                b.connect("clicked", self.on_service, sv["name"], cmd, title)
                actions.pack_start(b, False, False, 0)
            card.pack_end(actions, False, False, 0)
            cards.pack_start(card, False, False, 0)
        self.services_box.pack_start(cards, False, False, 0)

        if any(sv["open"] for sv in self.services):
            box, lb = group("Se puede entrar desde otros equipos de la red")
            row = ActionRow("Abierto a la red", d["exposed"] or "Algún servicio escucha en toda la red")
            b = css(Gtk.Button(label="Cerrar a la red"), "verde")
            b.connect("clicked", self.on_secure)
            row.add_suffix(b)
            lb.add(row)
            self.services_box.pack_start(box, False, False, 0)
        self.services_box.show_all()

    def on_service(self, _btn, name, cmd, title):
        verbs = {"arrancar": ("Arrancando", "arrancado"), "parar": ("Parando", "parado"),
                 "reiniciar": ("Reiniciando", "reiniciado")}
        doing, done = verbs[cmd]
        self.run_task("%s %s" % (doing, title), ["servicio", name, cmd],
                      done_text="%s %s" % (title, done), auto_close=True)

    def on_update_pma(self, folder):
        self.run_task("Actualizando phpMyAdmin", ["actualizar-phpmyadmin", folder],
                      done_text="phpMyAdmin actualizado", auto_close=True)

    def on_secure_all(self, *_):
        self.run_task("Protegiendo las versiones", ["asegurar", "--todas"],
                      done_text="Todas las versiones son solo para este equipo", auto_close=True)

    def on_secure(self, *_):
        self.run_task("Cerrando a la red", ["asegurar"],
                      done_text="Solo se puede entrar desde este equipo", auto_close=True)

    # -------------------------------------------------------------- hosts
    def on_hosts_data(self, _rc, out):
        rows = [{"name": f[1], "alias": f[2], "folder": f[3], "fake": f[4] == "1",
                 "https": f[5] == "1", "crt": f[6] == "1", "ps": f[7] == "1",
                 "custom": len(f) >= 9 and f[8] == "1"}
                for f in parse_lines(out) if f[0] == "F" and len(f) >= 8]
        # El vhost de los proyectos (web.local) que no lleva a 127.0.0.1: (nombre, dirección de ahora)
        link_fix = [(f[1], f[2]) for f in parse_lines(out) if f[0] == "L" and len(f) >= 3]
        if rows != self.hosts or link_fix != getattr(self, "hosts_link_fix", None):
            self.hosts = rows
            self.hosts_link_fix = link_fix
            self.build_hosts()
        return False

    def build_hosts(self):
        """Dominios de los vhosts y si están falseados en /etc/hosts (llevan a este equipo). Al
        cargar una tienda PrestaShop se falsea su dominio y el resto vuelve a la web real."""
        clear(self.hosts_box)
        if self.hosts is None:
            self.loading(self.hosts_box)
            return
        fake = [h for h in self.hosts if h["fake"]]
        rest = [h for h in self.hosts if not h["fake"]]

        # Primero, si el vhost de los proyectos no lleva a este equipo: el navegador no conecta
        for name, now in getattr(self, "hosts_link_fix", []):
            box, lb = group("%s no lleva a este equipo" % name,
                            "Apache solo escucha en 127.0.0.1 y en /etc/hosts %s. El navegador da "
                            "«No se puede acceder a este sitio web» (ERR_CONNECTION_REFUSED). "
                            "Arreglarlo hace que %s lleve a 127.0.0.1 (una sola vez; la copia del "
                            "/etc/hosts anterior queda en ~/lvm-copias). Pide la contraseña de sudo."
                            % (("apunta a %s" % now) if now else "no está", name))
            row = ActionRow("%s → %s" % (name, now or "sin línea en /etc/hosts"),
                            "Tiene que ir a 127.0.0.1, donde escucha Apache")
            b = css(Gtk.Button(label="Arreglarlo"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Arreglando /etc/hosts", ["hosts-enlace"],
                done_text="web.local ya lleva a este equipo", auto_close=True))
            row.add_suffix(b)
            lb.add(row)
            self.hosts_box.pack_start(box, False, False, 0)

        box, lb = group("Host falseado",
                        "Al cargar una tienda PrestaShop se crea lo que le falte (su vhost y su "
                        "certificado) y su dominio se falsea en /etc/hosts: el navegador la abre "
                        "en este equipo. Al cargar otro proyecto deja de estar falseado y vuelve "
                        "a llevar a la web real.")
        if not fake:
            lb.add(ActionRow("Ningún dominio falseado",
                             "Los dominios de los vhosts llevan a sus webs reales"))
        for h in fake:
            lb.add(self.host_row(h))
        self.hosts_box.pack_start(box, False, False, 0)
        self.hosts_box.pack_start(self.build_new_domain(), False, False, 0)

        box, lb = group("Dominios de los vhosts",
                        "Encendido, el dominio lleva a este equipo (127.0.0.1); apagado, a la "
                        "web real. Se pide la contraseña de sudo para cambiar /etc/hosts.")
        if not rest:
            lb.add(ActionRow("No hay más dominios",
                             "Los vhosts están en /opt/config/httpd-vhosts.conf"))
        for h in rest:
            lb.add(self.host_row(h))
        self.hosts_box.pack_start(box, False, False, 0)
        self.hosts_box.show_all()

    def build_new_domain(self):
        """Proyecto nuevo con el dominio de producción falseado (para construirlo en local y
        subirlo después a producción con los nombres reales). La carpeta se elige entre las de
        /opt/htdocs (por ejemplo, la de un git clone) o se crea; la base, entre las de la
        versión activa o se crea, como en Bases de datos."""
        f = self.newdom
        active = self.data["active"] if self.data else ""
        box, lb = group("Nuevo proyecto con dominio falseado",
                        "Para construir en local un proyecto nuevo con su dominio y su BBDD "
                        "de producción, sin tocar nada en producción. Elige su carpeta de "
                        "/opt/htdocs (por ejemplo, la de un git clone) o crea una, y su BBDD. "
                        "Se crea su vhost http y https con certificado, lo que falte de la "
                        "carpeta y la BBDD, y se falsea el dominio. Al terminar se exporta a "
                        "producción tal cual.")

        row = ActionRow("Dominio", "El de producción")
        e = Gtk.Entry(text=f["domain"], placeholder_text="mitienda.com", width_chars=COMBO_CHARS,
                      valign=Gtk.Align.CENTER)
        e.connect("changed", lambda w: (f.__setitem__("domain", w.get_text().strip()),
                                        update())[0])
        row.add_suffix(e)
        lb.add(row)

        # Carpeta: las de /opt/htdocs (las que ya tienen dominio lo indican) o una nueva
        with_domain = {h["folder"]: h["name"] for h in (self.hosts or []) if h["folder"]}
        folders = project_folders()
        row = ActionRow("Carpeta", "Ya tiene el dominio %s" % with_domain[f["folder"]]
                        if f["folder"] in with_domain else
                        "En /opt/htdocs (git clone) o nueva")
        # Un dominio largo no ensancha la pestaña: se corta con «…» y se ve entero al pasar el raton
        row.subtitle.set_max_width_chars(26)
        row.subtitle.set_tooltip_text(row.subtitle.get_label())
        fcombo = narrow(Gtk.ComboBoxText(valign=Gtk.Align.CENTER))
        for name in folders:
            fcombo.append(name, name)
        if f["folder"] and f["folder"] not in folders:
            fcombo.append(f["folder"], "%s (nueva)" % f["folder"])
        if f["folder"]:
            fcombo.set_active_id(f["folder"])
        if fcombo.get_active_id() is None:
            f["folder"] = ""
            fcombo.append("@ninguna", "Elige una carpeta")
            fcombo.set_active_id("@ninguna")
        fcombo.connect("changed", lambda w: self.on_new_domain_folder(w.get_active_id()))
        row.add_suffix(fcombo)
        b = Gtk.Button(tooltip_text="Crear una carpeta nueva", valign=Gtk.Align.CENTER)
        b.add(icon("list-add-symbolic"))
        b.connect("clicked", lambda *_: self.ask_new_domain_name("folder", folders))
        row.add_suffix(b)
        lb.add(row)

        # Base de datos: las de la versión activa, una nueva o ninguna
        dbs = self.data["dbs"].get(active, []) if active else []
        row = ActionRow("BBDD", "En lampp-%s" % active if active
                        else "No hay ninguna versión activa")
        dcombo = narrow(Gtk.ComboBoxText(valign=Gtk.Align.CENTER, sensitive=bool(active)))
        dcombo.append("@sin", "Sin BBDD")
        for db in dbs:
            dcombo.append(db, db)
        if f["db"] and f["db"] not in dbs:
            dcombo.append(f["db"], "%s (nueva)" % f["db"])
        dcombo.set_active_id(f["db"] or "@sin")
        if dcombo.get_active_id() is None:
            f["db"] = ""
            dcombo.set_active_id("@sin")
        dcombo.connect("changed", lambda w: f.__setitem__(
            "db", "" if w.get_active_id() in (None, "@sin") else w.get_active_id()))
        row.add_suffix(dcombo)
        b = Gtk.Button(tooltip_text="Crear una BBDD nueva", valign=Gtk.Align.CENTER,
                       sensitive=bool(active))
        b.add(icon("list-add-symbolic"))
        b.connect("clicked", lambda *_: self.ask_new_domain_name("db", dbs))
        row.add_suffix(b)
        lb.add(row)

        row = ActionRow("", None)
        btn = css(Gtk.Button(label="Crear y falsear"), "suggested-action")
        btn.connect("clicked", lambda *_: self.on_new_domain())
        row.add_suffix(btn)
        lb.add(row)

        def update():
            btn.set_sensitive(bool(DOMAIN_RX.match(f["domain"])) and bool(f["folder"])
                              and not self.busy)
        self.newdom_update = update
        update()
        return box

    def on_new_domain_folder(self, folder):
        f = self.newdom
        f["folder"] = "" if folder in (None, "@ninguna") else folder
        # Si el proyecto ya trae su configuración (wp-config.php, PrestaShop, .env), se propone
        # su base de datos
        db = project_db(f["folder"]) if f["folder"] else ""
        if db and not f["db"]:
            f["db"] = db
            GLib.idle_add(lambda: (self.build_hosts(), False)[1])
            self.toast("BBDD de su configuración: %s" % db)
        else:
            GLib.idle_add(lambda: (self.build_hosts(), False)[1])

    def ask_new_domain_name(self, key, existing):
        """Nombre de una carpeta o una base nueva (se crea al pulsar «Crear y falsear»)."""
        is_db = key == "db"
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.QUESTION,
                                buttons=Gtk.ButtonsType.NONE,
                                text="BBDD nueva" if is_db else "Carpeta nueva")
        dlg.format_secondary_text(
            "Pon el nombre de la BBDD de producción. Se crea vacía en lampp-%s al "
            "pulsar «Crear y falsear»." % self.data["active"] if is_db else
            "Se crea en /opt/htdocs al pulsar «Crear y falsear». Si vas a clonar el proyecto "
            "con git, clónalo antes y elige su carpeta en la lista.")
        entry = Gtk.Entry(max_length=64, activates_default=True,
                          placeholder_text="nombre_de_la_base" if is_db else
                          (self.newdom["domain"] or "carpeta-del-proyecto"))
        hint = label("Letras sin acentos, números, _ y -" if is_db else
                     "Letras sin acentos, números, punto, _ y -", "dim-label")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.pack_start(entry, False, False, 0)
        box.pack_start(hint, False, False, 0)
        dlg.get_message_area().pack_start(box, False, False, 0)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Elegir", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        rx = r"^[A-Za-z0-9_-]{1,64}$" if is_db else r"^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$"

        def value():
            return entry.get_text().strip() or ("" if is_db else self.newdom["domain"])

        def update(*_):
            name = value()
            taken = name in existing
            ok.set_sensitive(bool(re.match(rx, name)) and not taken)
            hint.set_label("Ya existe: elígela en la lista." if taken else
                           "Letras sin acentos, números, _ y -" if is_db else
                           "Letras sin acentos, números, punto, _ y -")
        entry.connect("changed", update)
        update()
        dlg.show_all()
        resp = run_dialog(dlg)
        name = value()
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        self.newdom[key] = name
        GLib.idle_add(lambda: (self.build_hosts(), False)[1])

    def on_new_domain(self):
        f = self.newdom
        domain = f["domain"].lower()
        folder = f["folder"]
        db = f["db"]
        if not folder:
            return
        active = self.data["active"] if self.data else ""
        exists = os.path.isdir(os.path.join(HTDOCS, folder))
        steps = ["Carpeta /opt/htdocs/%s%s." % (folder, "" if exists else " (se crea)"),
                 "Vhost http y https de %s con su certificado autofirmado." % domain]
        if db:
            have = db in (self.data["dbs"].get(active, []) if active else [])
            steps.append("BBDD %s en lampp-%s%s." % (
                db, active, " (ya existe: se deja como está)" if have else " (se crea vacía)"))
        steps.append("%s se falsea en /etc/hosts; los demás dominios dejan de estarlo." % domain)
        if not confirm(self.win, "¿Crear %s?" % domain, "\n".join("• " + x for x in steps) +
                       "\n\nSe pide la contraseña de sudo.", "Crear y falsear"):
            return
        args = ["nuevo-dominio", domain, folder] + ([db] if db else [])

        def done(ok_, *_):
            if ok_:
                self.newdom = {"domain": "", "folder": "", "db": ""}
                self.hosts = None
                self.toast("%s falseado: https://%s → /opt/htdocs/%s" % (domain, domain, folder))
        self.run_task("Creando %s" % domain, args, done_text="%s listo" % domain,
                      env=self.db_env() if active else None, on_done=done)

    def host_row(self, h):
        info = [h["folder"] or "sin carpeta en /opt/htdocs"]
        if not h["https"]:
            info.append("sin https")
        elif not h["crt"]:
            info.append("falta el certificado")
        row = ActionRow(h["name"], "  ·  ".join(info))
        # Logotipo del proyecto: PrestaShop, WordPress (por el nombre de su carpeta) o un globo
        if h["ps"]:
            row.add_prefix(section_icon(("logo", "prestashop"), 16))
        elif "wordpress" in (h["folder"] or "").lower():
            row.add_prefix(section_icon(("logo", "wordpress"), 16))
        else:
            row.add_prefix(section_icon(("icono", "web-browser-symbolic", ""), 16))
        if h["ps"]:
            row.add_title_tag(label("PrestaShop", "dim-label"))
        elif h.get("custom"):
            row.add_title_tag(label("Proyecto nuevo", "dim-label"))
        if h["fake"]:
            b = Gtk.Button(label="Abrir", valign=Gtk.Align.CENTER,
                           tooltip_text="https://%s" % h["name"])
            b.connect("clicked", lambda *_: self.open_uri(
                "%s://%s" % ("https" if h["https"] else "http", h["name"])))
            row.add_suffix(b)
        sw = Gtk.Switch(active=h["fake"], valign=Gtk.Align.CENTER)
        # Un .local siempre lleva a este equipo (si no, se preguntaria a la red): no se apaga
        if h["name"].lower().endswith(".local") and h["fake"]:
            sw.set_sensitive(False)
            sw.set_tooltip_text("Un .local siempre lleva a este equipo: no existe fuera y, sin su "
                                "línea en /etc/hosts, se preguntaría a la red")
        sw.connect("state-set", self.on_host_switch, h)
        row.add_suffix(sw)
        return row

    def on_host_switch(self, sw, state, h):
        if state == h["fake"]:
            return False
        name = h["name"]
        if state:
            title, done = "Falseando %s" % name, "%s lleva a este equipo" % name
        else:
            title, done = "Dejando de falsear %s" % name, "%s lleva a la web real" % name

        def finished(ok_, *_):
            if not ok_:
                self.hosts = None
            self.toast(done if ok_ else "No se ha cambiado /etc/hosts")
        self.run_task(title, ["hosts-falsear", name, "si" if state else "no"],
                      done_text=done, auto_close=True, on_done=finished)
        # El interruptor cambia cuando se vuelva a leer /etc/hosts
        return True

    # ------------------------------------------------------- herramientas
    def build_tools(self):
        """Lo que se usa de vez en cuando: ficheros de configuración, carpetas, actualizar el
        programa e información."""
        clear(self.tools_box)
        d = self.data

        def add_row(lb, title, sub, btn_text, cb):
            row = ActionRow(title, sub)
            b = Gtk.Button(label=btn_text, valign=Gtk.Align.CENTER)
            b.connect("clicked", lambda *_: cb())
            row.add_suffix(b)
            lb.add(row)

        box, lb = group("Configuración",
                        "Los vhosts y los hosts del sistema son del administrador: se edita una "
                        "copia y se aplica con Aplicar (pide la contraseña).")
        add_row(lb, "Virtual hosts", d["vhosts"], "Editar…", self.on_vhosts)
        add_row(lb, "Hosts del sistema", d["hosts"], "Editar…", self.on_hosts)
        self.tools_box.pack_start(box, False, False, 0)

        if d["unregistered"]:
            box, lb = group("XAMPP sin registrar",
                            "/opt/lampp es una instalación de XAMPP completa y no un enlace.")
            add_row(lb, "XAMPP en /opt/lampp", "Regístralo con un nombre para gestionarlo junto a "
                    "las demás versiones", "Registrar…", self.on_register)
            self.tools_box.pack_start(box, False, False, 0)

        box, lb = group("Carpetas")
        add_row(lb, "Proyectos", "/opt/htdocs, compartida por todas las versiones", "Abrir",
                lambda: self.open_uri(GLib.filename_to_uri("/opt/htdocs")))
        copies = os.path.expanduser("~/lvm-copias")
        add_row(lb, "Copias de seguridad", "~/lvm-copias: BBDD borradas o desinstaladas y "
                "/etc/hosts anteriores", "Abrir",
                lambda: (os.makedirs(copies, exist_ok=True),
                         self.open_uri(GLib.filename_to_uri(copies))))
        add_row(lb, "Registros de instalaciones", "~/.lvm-instalador: logs de las instalaciones "
                "y de la ventana", "Abrir", lambda: self.open_uri(GLib.filename_to_uri(LOG_DIR)))
        self.tools_box.pack_start(box, False, False, 0)

        self.build_error_logs(add_row)

        box, lb = group("Programa")
        add_row(lb, "Buscar una versión nueva", "Busca un lvm-instalador_*.deb más nuevo en "
                "Descargas y lo instala", "Buscar", lambda: self.check_package(manual=True))
        add_row(lb, "Icono en el menú de aplicaciones", "Vuelve a crear el acceso «LAMPP Version "
                "Manager» si no aparece o no abre esta ventana", "Crear de nuevo",
                self.on_create_launcher)
        self.tools_box.pack_start(box, False, False, 0)

        box, lb = group("Información")
        add_row(lb, "Comandos de lvm-instalador", "Todos los comandos para la terminal y qué hace "
                "cada uno", "Ver", self.on_commands)
        add_row(lb, "Novedades", "Qué ha cambiado en cada versión", "Ver", self.on_changes)
        add_row(lb, "Acerca de", "%s %s" % (d["name"], d["version"]), "Ver", self.on_about)
        self.tools_box.pack_start(box, False, False, 0)
        self.tools_box.show_all()

    def project_error_log(self):
        """Registro de errores del vhost de los proyectos (web.local), sacado de su ErrorLog: con
        PHP-FPM, los errores de PHP de la web cargada (el «error crítico» de WordPress) van ahí y no
        al error_log general de Apache."""
        link = (self.projects or {}).get("link") or ""
        if not link:
            return None
        try:
            with open(self.data["vhosts"], errors="replace") as fh:
                text = fh.read(2000000)
        except OSError:
            text = ""
        for m in re.finditer(r"(?is)<VirtualHost\b[^>]*>(.*?)</VirtualHost>", text):
            body = m.group(1)
            names = " ".join(re.findall(r"(?im)^[ \t]*Server(?:Name|Alias)[ \t]+(.+)$", body)).lower().split()
            e = re.search(r"(?im)^[ \t]*ErrorLog[ \t]+\"?([^\"\s]+)\"?", body)
            if link.lower() in names and e and not e.group(1).startswith(("|", "syslog")):
                path = e.group(1)
                return path if path.startswith("/") else os.path.join("/opt/lampp", path)
        # (sin ErrorLog propio, sus errores van al general: no hay otro registro que enseñar)
        path = os.path.join("/opt/lampp/logs", link + "-error_log")
        return path if os.path.isfile(path) else None

    def log_row(self, title, path, note=""):
        """Fila de un registro: dónde está, cuánto ocupa y cuándo se cambió."""
        try:
            st = os.stat(path)
        except OSError:
            return ActionRow(title, "%s: no existe todavía (se crea con el primer error)" % path)
        when = GLib.DateTime.new_from_unix_local(int(st.st_mtime)).format("%d/%m/%Y %H:%M")
        size = GLib.format_size(st.st_size)
        sub = "%s  ·  %s  ·  modificado el %s" % (path, size, when)
        if note:
            sub = note + "\n" + sub
        row = ActionRow(title, sub)
        row.subtitle.set_line_wrap(True)
        row.subtitle.set_ellipsize(0)
        b = Gtk.Button(label="Ver el final", sensitive=st.st_size > 0, valign=Gtk.Align.CENTER)
        b.connect("clicked", lambda *_: self.show_log_tail(path))
        row.add_suffix(b)
        b = Gtk.Button(label="Abrir", valign=Gtk.Align.CENTER)
        # Un fichero de cientos de MB dejaria colgado el editor de textos
        if st.st_size > LOG_OPEN_MAX:
            b.set_sensitive(False)
            b.set_tooltip_text("Ocupa %s: demasiado para el editor. Usa «Ver el final»." % size)
        b.connect("clicked", lambda *_: self.open_text(path))
        row.add_suffix(b)
        return row

    def build_error_logs(self, add_row):
        """Los registros de errores de la versión montada: el del vhost del proyecto cargado
        (web.local), donde van los errores de PHP de la web, y el general de Apache."""
        box, lb = group("Registro de errores",
                        "Si la web cargada da un error (el «error crítico» de WordPress), el motivo "
                        "está en el registro de su vhost: ahí van los errores de PHP. Los de Apache "
                        "(que no arranca, un vhost mal escrito…), en el general. Lo más reciente "
                        "está al final.")
        path = self.project_error_log()
        if path:
            p = self.projects
            name = os.path.basename(p["current"].rstrip("/")) if p and p.get("current") else ""
            lb.add(self.log_row("error_log de %s%s" % (p["link"], "  (%s)" % name if name else ""), path))
        main = "/opt/lampp/logs/error_log"
        lb.add(self.log_row("error_log de Apache (lampp-%s)" % self.data["active"], main))
        self.tools_box.pack_start(box, False, False, 0)

    def show_log_tail(self, path, lines=400):
        """Últimas líneas de un registro (lo más reciente al final), sin leer el fichero entero."""
        try:
            # (sin quedarse esperando si no es un fichero normal: una tubería colgaría la ventana)
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                os.close(fd)
                raise OSError("no es un fichero normal")
            with os.fdopen(fd, "rb") as f:
                f.seek(0, os.SEEK_END)
                size = f.tell()
                f.seek(max(0, size - 256 * 1024))
                text = f.read().decode("utf-8", "replace")
        except OSError as exc:
            message(self.win, "No se ha podido leer %s" % path, str(exc), Gtk.MessageType.ERROR)
            return
        # (los de PHP-FPM llegan en una sola línea con \n escritos: se separan para leerlos)
        text = "\n".join(text.splitlines()[-lines:]).replace("\\n", "\n    ") or "(vacío)"
        dlg = Gtk.Dialog(title=os.path.basename(path), transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(980, 620)
        hb = dlg.get_header_bar()
        hb.set_subtitle("Últimas %d líneas de %s" % (lines, path))
        copy = Gtk.Button(label="Copiar todo")
        copy.connect("clicked", lambda *_: (
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1),
            self.toast("Copiado al portapapeles")))
        hb.pack_start(copy)
        reload_btn = Gtk.Button(label="Actualizar")
        reload_btn.connect("clicked", lambda *_: (dlg.destroy(), self.show_log_tail(path, lines)))
        hb.pack_end(reload_btn)
        tv = css(Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                              wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=12, right_margin=12,
                              top_margin=8, bottom_margin=8), "log")
        buf = tv.get_buffer()
        buf.set_text(text)
        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.add(tv)
        dlg.get_content_area().add(sw)
        dlg.show_all()
        # Lo más reciente está al final
        GLib.idle_add(lambda: (tv.scroll_to_iter(buf.get_end_iter(), 0, False, 0, 1), False)[1])
        run_dialog(dlg)
        dlg.destroy()

    # ---------------------------------------------------------- versiones
    def on_close_stray(self, *_):
        self.run_task("Cerrando los procesos que sobran", ["cerrar-procesos"],
                      done_text="Solo queda en memoria la versión montada", auto_close=True,
                      on_done=lambda ok_, *_: self.toast(
                          "Procesos cerrados" if ok_ else "No se han podido cerrar todos"))

    # ------------------------------------------------- cargar un proyecto (Versiones)
    def on_projects_data(self, rc, out):
        p = {"link": "", "current": "", "create": False, "list": [], "saved": {}}
        for f in parse_lines(out):
            if f[0] == "E" and len(f) >= 3:
                p["link"], p["current"] = f[1], f[2]
                p["create"] = len(f) >= 4 and f[3] == "N"
            elif f[0] == "P" and len(f) >= 4:
                p["list"].append({"name": f[1], "db": f[2], "php": f[3],
                                  "kind": f[4] if len(f) > 4 else ""})
            elif f[0] == "R" and len(f) >= 3:
                p["saved"][f[1]] = "|".join(f[2:])
        if rc != 0 and not p["list"]:
            p = None
        if p != self.projects:
            old_link = (self.projects or {}).get("link"), (self.projects or {}).get("current")
            self.projects = p
            self.update_project_search()
            # (el registro de errores de Herramientas es el del vhost del proyecto cargado)
            if self.data and old_link != ((p or {}).get("link"), (p or {}).get("current")):
                self.build_tools()
        return False

    def build_project_box(self):
        # Uno de los bloques más usados: su título fuera, como los demás apartados, y debajo el
        # contenedor hundido, con algo más de separación con lo de debajo (Versión activa)
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, margin_bottom=12)
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin_top=6), "hundido")
        head = Gtk.Box(spacing=6)
        head.pack_start(label("Cargar proyecto", "grupo-titulo"), False, False, 0)
        head.pack_start(info_icon(
            "Busca la carpeta de un proyecto de /opt/htdocs y cárgalo: el vhost "
            "(web.local) apunta a ella y se monta la versión de PHP donde está su BBDD. "
            "Si la BBDD está en varias versiones, se pregunta cuál montar. Con «Montar nuevo "
            "proyecto» se clona uno de GitHub y se le crea su BBDD."), False, False, 0)
        outer.pack_start(head, False, False, 0)
        outer.pack_start(box, False, False, 0)
        # «web.local → proyecto», junto al nombre el botón de desmontarlo y, a la derecha,
        # botones de icono (el texto sale al dejar el ratón encima). De derecha a izquierda: su
        # carpeta en Visual Studio Code, su BBDD en phpMyAdmin, su panel de administración
        # (WordPress o PrestaShop) y la web en el navegador
        # (todo el nombre si cabe; si no, cortado por el final)
        self.proj_now = label("", ellipsize=3, max_width_chars=70)

        def icon_button(image, callback):
            b = css(Gtk.Button(valign=Gtk.Align.CENTER, relief=Gtk.ReliefStyle.NORMAL),
                    "boton-proyecto")
            b.set_image(image)
            b.set_always_show_image(True)
            b.connect("clicked", lambda *_: callback())
            return b
        self.proj_open = icon_button(logo("globo", 20), lambda: self.projects and self.projects["link"]
                                     and self.open_uri("http://%s/" % self.projects["link"]))
        self.proj_pma = icon_button(logo("phpmyadmin", 20), self.open_project_pma)
        self.proj_admin = icon_button(logo("wordpress", 20), self.open_project_admin)
        # Desmontar: el vhost deja de apuntar al proyecto (enseña una página vacía)
        self.proj_unload = icon_button(icon("media-eject-symbolic", 18), self.on_unload_project)
        self.proj_now_row = Gtk.Box(spacing=8)
        self.proj_now_row.pack_start(section_icon(("icono", "folder-open-symbolic", "verde-suave"), 16),
                                     False, False, 4)
        name_box = Gtk.Box(spacing=8)
        name_box.pack_start(self.proj_now, False, True, 0)
        name_box.pack_start(self.proj_unload, False, False, 0)
        self.proj_now_row.pack_start(name_box, True, True, 0)
        # El de abrir su carpeta en Visual Studio Code, el último por la derecha (solo si está
        # instalado), con el icono de VS Code
        code = vscode_app()
        self.proj_code = css(Gtk.Button(valign=Gtk.Align.CENTER, relief=Gtk.ReliefStyle.NORMAL),
                             "boton-proyecto")
        if code is not None and code.get_icon() is not None:
            img = Gtk.Image.new_from_gicon(code.get_icon(), Gtk.IconSize.BUTTON)
            img.set_pixel_size(20)
            self.proj_code.set_image(img)
        else:
            self.proj_code.set_label("VS Code")
        self.proj_code.connect("clicked", lambda *_: self.open_in_vscode())
        self.proj_now_row.pack_end(self.proj_code, False, False, 0)
        self.proj_now_row.pack_end(self.proj_pma, False, False, 0)
        self.proj_now_row.pack_end(self.proj_admin, False, False, 0)
        self.proj_now_row.pack_end(self.proj_open, False, False, 0)
        if code is None:
            self.proj_code.set_no_show_all(True)
        self.proj_now_row.show_all()
        self.proj_now_row.set_no_show_all(True)
        box.pack_start(self.proj_now_row, False, False, 0)
        # Aviso en rojo: la versión montada no tiene el proyecto cargado (su BBDD está en otra)
        self.proj_warn = label("", "aviso-rojo", wrap=True)
        self.proj_warn.set_no_show_all(True)
        box.pack_start(self.proj_warn, False, False, 0)
        # Buscador y, a su derecha, «Montar nuevo proyecto» (despliega el asistente)
        # (algo separado de los botones del proyecto, que van justo encima)
        search_row = Gtk.Box(spacing=10, margin_top=16)
        self.proj_entry = css(Gtk.SearchEntry(placeholder_text="Buscar la carpeta del proyecto…"),
                              "buscador")
        self.proj_entry.connect("search-changed", lambda *_: self.update_project_search())
        self.proj_entry.connect("stop-search", lambda e: e.set_text(""))
        search_row.pack_start(self.proj_entry, True, True, 0)
        self.proj_new_btn = css(Gtk.Button(valign=Gtk.Align.CENTER), "verde")
        nb = Gtk.Box(spacing=6)
        nb.pack_start(icon("list-add-symbolic"), False, False, 0)
        nb.pack_start(Gtk.Label(label="Montar nuevo proyecto"), False, False, 0)
        self.proj_new_btn.add(nb)
        self.proj_new_btn.set_tooltip_text("Clona un proyecto de GitHub en /opt/htdocs, elige su "
                                           "versión de PHP y créale su BBDD")
        self.proj_new_btn.connect("clicked", lambda *_: self.toggle_new_project(True))
        search_row.pack_start(self.proj_new_btn, False, False, 0)
        box.pack_start(search_row, False, False, 0)
        self.new_proj_rev = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.new_proj_rev.add(self.build_new_project())
        # Plegado, oculto del todo: si no, el hueco entre filas del recuadro deja más espacio
        # debajo del buscador que encima de la primera fila
        self.new_proj_rev.set_no_show_all(True)
        self.new_proj_rev.connect("notify::child-revealed", lambda r, _p: r.get_reveal_child()
                                  or r.get_child_revealed() or r.hide())
        box.pack_start(self.new_proj_rev, False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        lb.connect("row-activated", on_row_activated)
        lb.set_no_show_all(True)
        box.pack_start(lb, False, False, 0)
        self.proj_results = lb
        outer.show_all()
        return outer

    # --- Montar nuevo proyecto: asistente de tres pasos (clon, versión de PHP y BBDD) ---

    def build_new_project(self):
        w = {}
        self.np = w
        outer = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14), "asistente")
        w["step"] = label("", "asistente-paso")
        outer.pack_start(w["step"], False, False, 0)
        w["stack"] = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
                               vhomogeneous=False, interpolate_size=True)
        outer.pack_start(w["stack"], False, False, 0)

        # 1. Repositorio y carpeta
        p1 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        p1.pack_start(label("Dirección del repositorio (GitHub u otro):"), False, False, 0)
        w["url"] = Gtk.Entry(placeholder_text="https://github.com/usuario/repositorio.git")
        p1.pack_start(w["url"], False, False, 0)
        p1.pack_start(label("Carpeta en /opt/htdocs:"), False, False, 0)
        w["folder"] = Gtk.Entry(placeholder_text="nombre-del-proyecto")
        p1.pack_start(w["folder"], False, False, 0)
        p1.pack_start(label("Se clona con tu usuario (sin sudo). Si el repositorio es privado, usa "
                            "su dirección SSH (git@github.com:usuario/repositorio.git) con tu clave "
                            "SSH ya configurada.", "dim-label", wrap=True), False, False, 0)
        w["err1"] = label("", "aviso-rojo", wrap=True)
        p1.pack_start(w["err1"], False, False, 0)
        w["stack"].add_named(p1, "1")
        w["folder_auto"] = True

        def url_changed(*_):
            name = re.sub(r"\.git$", "", w["url"].get_text().strip().rstrip("/").split("/")[-1].split(":")[-1])
            name = re.sub(r"[^A-Za-z0-9._-]", "-", name).lstrip(".-")[:100]
            if w["folder_auto"]:
                w["setting"] = True
                w["folder"].set_text(name)
                w["setting"] = False
            self.new_project_check()

        def folder_changed(*_):
            if not w.get("setting"):
                w["folder_auto"] = not w["folder"].get_text()
            self.new_project_check()
        w["url"].connect("changed", url_changed)
        w["folder"].connect("changed", folder_changed)

        # 2. Versión de PHP
        p2 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        p2.pack_start(label("¿En qué versión de PHP quieres crear el proyecto?"), False, False, 0)
        w["versions"] = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        p2.pack_start(w["versions"], False, False, 0)
        w["stack"].add_named(p2, "2")

        # 3. BBDD nueva y volcado
        p3 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        p3.pack_start(label("Nombre de la BBDD nueva:"), False, False, 0)
        w["db"] = Gtk.Entry(placeholder_text="wp_proyecto")
        w["db"].connect("changed", lambda *_: self.new_project_check())
        p3.pack_start(w["db"], False, False, 0)
        p3.pack_start(label("Volcado que se sube a la BBDD (.sql, .sql.gz o .zip):"), False, False, 0)
        w["file"] = Gtk.FileChooserButton(title="Elige el volcado de la BBDD",
                                          action=Gtk.FileChooserAction.OPEN)
        flt = Gtk.FileFilter()
        flt.set_name("Volcados (.sql, .sql.gz, .zip)")
        for pat in ("*.sql", "*.sql.gz", "*.zip", "*.SQL", "*.GZ", "*.ZIP"):
            flt.add_pattern(pat)
        w["file"].add_filter(flt)
        w["file"].connect("file-set", lambda *_: self.new_project_check())
        p3.pack_start(w["file"], False, False, 0)
        p3.pack_start(label("Si no eliges ninguno, la BBDD se crea vacía. El volcado se carga con "
                            "la carga protegida (con el usuario de la BBDD y sin DEFINER).",
                            "dim-label", wrap=True), False, False, 0)
        w["err3"] = label("", "aviso-rojo", wrap=True)
        p3.pack_start(w["err3"], False, False, 0)
        w["stack"].add_named(p3, "3")

        # Botones: Cancelar a la izquierda; Atrás y Siguiente (o Montar proyecto) a la derecha
        nav = Gtk.Box(spacing=8)
        cancel = Gtk.Button(label="Cancelar")
        cancel.connect("clicked", lambda *_: self.toggle_new_project(False))
        nav.pack_start(cancel, False, False, 0)
        w["next"] = css(Gtk.Button(label="Siguiente"), "verde")
        w["next"].connect("clicked", lambda *_: self.new_project_go(1))
        nav.pack_end(w["next"], False, False, 0)
        w["back"] = Gtk.Button(label="Atrás")
        w["back"].connect("clicked", lambda *_: self.new_project_go(-1))
        nav.pack_end(w["back"], False, False, 0)
        outer.pack_start(nav, False, False, 0)
        return outer

    def toggle_new_project(self, show):
        w = self.np
        if show:
            w["url"].set_text("")
            w["folder"].set_text("")
            w["folder_auto"] = True
            w["db"].set_text("")
            w["db_auto"] = True
            w["file"].unselect_all()
            w["version"] = None
            w["stack"].set_visible_child_name("1")
            # (show_all no le llega: tiene no_show_all)
            self.new_proj_rev.get_child().show_all()
            self.new_proj_rev.show()
            self.new_project_check()
            self.proj_entry.set_text("")
        self.new_proj_rev.set_reveal_child(show)
        self.proj_new_btn.set_sensitive(not show)
        if show:
            GLib.idle_add(w["url"].grab_focus)

    def new_project_page(self):
        return int(self.np["stack"].get_visible_child_name() or "1")

    def new_project_check(self):
        """Comprueba el paso en el que está el asistente: activa Siguiente y explica lo que falta."""
        w = self.np
        page = self.new_project_page()
        titles = {1: "Paso 1 de 3: clonar el repositorio", 2: "Paso 2 de 3: versión de PHP",
                  3: "Paso 3 de 3: BBDD nueva"}
        w["step"].set_label(titles[page])
        w["back"].set_visible(page > 1)
        w["next"].set_label("Montar proyecto" if page == 3 else "Siguiente")
        ok, err = True, ""
        if page == 1:
            url, folder = w["url"].get_text().strip(), w["folder"].get_text().strip()
            host, path = r"[A-Za-z0-9][A-Za-z0-9.-]*", r"[A-Za-z0-9_~][A-Za-z0-9._~/-]*"
            url_ok = bool(re.fullmatch(r"https://%s(:[0-9]{1,5})?/%s" % (host, path), url)
                          or re.fullmatch(r"git@%s:%s" % (host, path), url)
                          or re.fullmatch(r"ssh://git@%s(:[0-9]{1,5})?/%s" % (host, path), url))
            if not url:
                ok = False
            elif not url_ok:
                ok, err = False, "La dirección no es válida: usa https://… o git@servidor:usuario/repositorio.git"
            elif not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9._-]{0,99}", folder) or folder == ".lvm-sin-proyecto":
                ok, err = False, ("Pon un nombre de carpeta: letras sin acentos, números, punto, _ y -"
                                  if folder else "")
            elif os.path.lexists(os.path.join(HTDOCS, folder)):
                ok, err = False, "Ya existe /opt/htdocs/%s: elige otro nombre" % folder
            w["err1"].set_label(err)
            w["err1"].set_visible(bool(err))
        elif page == 2:
            ok = bool(w.get("version"))
        else:
            db = w["db"].get_text().strip()
            have = self.data["dbs"].get(w.get("version") or "", []) if self.data else []
            if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", db):
                ok, err = False, ("El nombre de la BBDD solo puede llevar letras sin acentos, números, _ y -"
                                  if db else "")
            elif db.lower() in (d.lower() for d in have):
                ok, err = False, "lampp-%s ya tiene una BBDD %s: elige otro nombre" % (w["version"], db)
            w["err3"].set_label(err)
            w["err3"].set_visible(bool(err))
        w["next"].set_sensitive(ok and not self.busy)

    def new_project_go(self, step):
        w = self.np
        page = self.new_project_page() + step
        if page == 4:
            self.new_project_run()
            return
        page = max(1, page)
        if page == 2:
            clear(w["versions"])
            insts = sorted(self.installs(), key=lambda i: [int(x) for x in re.findall(r"\d+", i["php"])],
                           reverse=True)
            if not insts:
                w["versions"].pack_start(label("No hay ninguna versión instalada: instala una en "
                                               "esta pestaña.", "aviso-rojo", wrap=True), False, False, 0)
            first = None
            for inst in insts:
                text = "PHP %s  ·  lampp-%s%s" % (inst["php"], inst["folder"],
                                                  "  (activa)" if inst["folder"] == self.data["active"] else "")
                rb = Gtk.RadioButton.new_with_label_from_widget(first, text)
                first = first or rb
                rb.connect("toggled", lambda b, f=inst["folder"]: b.get_active() and
                           (w.__setitem__("version", f), self.new_project_check()))
                w["versions"].pack_start(rb, False, False, 0)
                if inst["folder"] == (w.get("version") or self.data["active"]):
                    rb.set_active(True)
            if insts and not w.get("version"):
                w["version"] = insts[0]["folder"]
                first.set_active(True)
            w["versions"].show_all()
        if page == 3 and w.get("db_auto", True) and not w["db"].get_text():
            base = re.sub(r"[^a-z0-9_]", "_", w["folder"].get_text().strip().lower()).strip("_")[:40]
            w["db"].set_text(("wp_" + base) if base else "")
        w["stack"].set_visible_child_name(str(page))
        self.new_project_check()

    def new_project_run(self):
        w = self.np
        url, folder = w["url"].get_text().strip(), w["folder"].get_text().strip()
        version, db = w["version"], w["db"].get_text().strip()
        dump = w["file"].get_filename() or ""
        args = ["montar-proyecto", url, folder, version, db] + ([dump] if dump else [])

        def done(ok, *_):
            if ok:
                self.toggle_new_project(False)
                self.toast("Proyecto nuevo montado: %s en lampp-%s con la BBDD %s" % (folder, version, db))
        self.run_task("Montando el proyecto %s" % folder, args,
                      done_text="%s está clonado, cargado en lampp-%s y con su BBDD %s" % (folder, version, db),
                      on_done=done)

    def on_unload_project(self):
        p = self.projects
        if not p or not p.get("current"):
            return
        name = os.path.basename(p["current"].rstrip("/"))
        self.run_task("Desmontando el proyecto %s" % name, ["desmontar-proyecto"],
                      done_text="%s ya no apunta a %s" % (p["link"], name), auto_close=True)

    def project_base(self, x):
        """Base de un proyecto: la recordada para su carpeta (si está en alguna versión) o la de su
        configuración."""
        dbs = {db for i in self.installs() for db in self.data["dbs"].get(i["folder"], [])}
        saved = [db for db, f in (self.projects or {}).get("saved", {}).items() if f == x["name"]]
        for db in reversed(saved):
            if db in dbs:
                return db
        return x["db"] or (saved[-1] if saved else "")

    def update_project_search(self):
        if getattr(self, "proj_results", None) is None or not self.data:
            return
        p = self.projects
        now = ""
        esc = GLib.markup_escape_text
        if p and p["current"]:
            now = '%s → <span foreground="%s"><b>%s</b></span>' % (
                esc(p["link"]), GREEN, esc(os.path.basename(p["current"].rstrip("/"))))
        # Solo a dónde apunta el enlace: el vhost y la flecha, en el color normal, y el proyecto en
        # verde y negrita (sin título delante, para que quepa el nombre entero junto al botón de
        # desmontar). Desmontado: el vhost sin proyecto
        if now:
            self.proj_now.set_markup(now)
            # (si no cabe entero, al dejar el ratón encima)
            self.proj_now.set_tooltip_text("%s → %s" % (p["link"], p["current"].rstrip("/")))
        elif p and p.get("link") and not p.get("create"):
            self.proj_now.set_tooltip_text(None)
            self.proj_now.set_markup('%s → <i>ningún proyecto</i>  <span alpha="55%%">(enseña una página vacía)</span>'
                                     % esc(p["link"]))
        for b in (self.proj_unload, self.proj_open, self.proj_pma, self.proj_admin):
            b.set_visible(bool(now))
        self.proj_code.set_visible(bool(now) and vscode_app() is not None)
        # La versión montada no tiene la BBDD del proyecto cargado: aviso en rojo
        warn = ""
        if now and self.data and self.data.get("active"):
            db = self.loaded_project_db()
            if db and db not in self.data["dbs"].get(self.data["active"], []):
                where = [i["folder"] for i in self.installs() if db in self.data["dbs"].get(i["folder"], [])]
                warn = ("El proyecto vinculado a %s no está disponible para esa versión: lampp-%s no "
                        "tiene su BBDD %s%s." % (p["link"], self.data["active"], db,
                                                 (" (está en %s; vuelve a cargarlo para cambiar de versión)"
                                                  % ", ".join("lampp-%s" % x for x in where)) if where else ""))
        self.proj_warn.set_label(warn)
        self.proj_warn.set_visible(bool(warn))
        if now:
            name = os.path.basename(p["current"].rstrip("/"))
            self.proj_open.set_tooltip_text("Abrir http://%s/ en el navegador" % p["link"])
            db = self.loaded_project_db()
            self.proj_pma.set_sensitive(bool(db))
            self.proj_pma.set_tooltip_text("Abrir la BBDD %s en phpMyAdmin" % db if db
                                           else "No se sabe qué BBDD usa %s" % name)
            kind, admin = self.loaded_project_admin()
            self.proj_admin.set_image(logo("prestashop" if kind == "ps" else "wordpress", 16))
            self.proj_admin.set_sensitive(bool(admin))
            self.proj_admin.set_tooltip_text(
                ("Abrir el back office de PrestaShop (http://%s/%s/)" if kind == "ps"
                 else "Abrir el panel de WordPress (http://%s/%s/)") % (p["link"], admin)
                + " con el administrador de pruebas ya escrito (local@local.test, contraseña local): "
                  "solo hay que pulsar Entrar" if admin
                else "%s no es un WordPress ni una tienda PrestaShop con su carpeta de administración" % name)
            self.proj_code.set_tooltip_text(
                "Abrir %s en Visual Studio Code (si ya está abierto, se trae su ventana delante)" % name)
            self.proj_unload.set_tooltip_text(
                "Desmontar %s: %s deja de apuntar a él y enseña una página vacía" % (name, p["link"]))
        self.proj_now_row.set_visible(bool(p and p.get("link") and not p.get("create")))
        lb, q = self.proj_results, self.proj_entry.get_text().strip().lower()
        clear(lb)
        if not q or not p:
            lb.hide()
            return
        hits = [x for x in p["list"] if q in x["name"].lower()]
        hits.sort(key=lambda x: (not x["name"].lower().startswith(q), x["name"].lower()))
        if not hits:
            lb.add(ActionRow("Ningún proyecto con «%s» en el nombre" % q,
                             "Las carpetas de /opt/htdocs (sin las ocultas ni los enlaces)."))
        limit = 30
        for x in hits[:limit]:
            lb.add(self.project_hit_row(x, q))
        if len(hits) > limit:
            lb.add(ActionRow("Y %d más…" % (len(hits) - limit),
                             "Escribe más letras del nombre para encontrarlo."))
        for row in lb.get_children():
            row.show_all()
        lb.show()

    def project_hit_row(self, x, q):
        name = x["name"]
        row = ActionRow(name)
        kind = {"wp": "wordpress", "ps": "prestashop"}.get(x["kind"])
        row.add_prefix(section_icon(("logo", kind) if kind else ("icono", "folder-symbolic", ""), 16))
        start = name.lower().find(q)
        esc = GLib.markup_escape_text
        row.title.set_markup("%s<b>%s</b>%s" % (esc(name[:start]), esc(name[start:start + len(q)]),
                                                esc(name[start + len(q):])))
        db = self.project_base(x)
        where = [i["folder"] for i in self.installs() if db and db in self.data["dbs"].get(i["folder"], [])]
        parts = [{"wp": "WordPress", "ps": "PrestaShop"}.get(x["kind"], "")]
        if db:
            parts.append("BBDD %s" % db)
            parts.append(("en " + ", ".join("lampp-%s" % w for w in where)) if where
                         else "no está en ninguna versión")
        else:
            parts.append("sin BBDD detectada")
        if x["php"]:
            parts.append(".php-version %s" % x["php"])
        row.subtitle.set_label("  ·  ".join(t for t in parts if t))
        row.subtitle.set_no_show_all(False)
        current = self.projects and os.path.basename(self.projects["current"].rstrip("/")) == name
        if current:
            row.add_title_tag(label("Cargado", "texto-activa", "subtitulo"))
        b = Gtk.Button(label="Cargar", sensitive=not self.busy)
        b.connect("clicked", lambda *_: self.on_load_folder(x))
        row.add_suffix(b)
        return row

    def on_load_folder(self, x):
        p = self.projects
        if not p or not p["link"]:
            message(self.win, "No hay un vhost para cargar proyectos",
                    "Ningún vhost de /opt/config/httpd-vhosts.conf tiene como DocumentRoot un "
                    "enlace de /opt/htdocs (como web.local).", Gtk.MessageType.WARNING)
            return
        db = self.project_base(x)
        cands = [i for i in self.installs() if db and db in self.data["dbs"].get(i["folder"], [])]
        found = bool(cands)
        if not cands:
            cands = list(self.installs())
        if not cands:
            message(self.win, "No hay ninguna versión instalada",
                    "Instala una versión de PHP en esta pestaña para cargar proyectos.",
                    Gtk.MessageType.WARNING)
            return
        asked = len(cands) > 1
        if asked:
            inst = self.pick_version(x, db, cands, found)
            if not inst:
                return
        else:
            inst = cands[0]
        self.do_load_project(x["name"], db, inst, p["link"], p["create"], confirm_switch=not asked)

    def pick_version(self, x, db, cands, found):
        """Versión de PHP en la que se carga un proyecto, cuando puede ir en varias."""
        active = self.data["active"]
        pre = next((i for i in cands if i["folder"] == active), None) or \
            next((i for i in cands if x["php"] and i["php"].startswith(x["php"])), None) or cands[0]
        dlg = Gtk.Dialog(title="Cargar proyecto", transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(520, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Cargar proyecto", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        ask = ("¿Qué versión del proyecto y de PHP quieres?" if found else
               "¿Con qué versión de PHP quieres cargar el proyecto?")
        box.pack_start(css(label(ask, wrap=True, max_width_chars=60), "title-3"), False, False, 0)
        if found:
            why = ("%s tiene su BBDD (%s) en %d versiones de PHP y cada una guarda su "
                   "propia copia. Elige cuál cargar:" % (x["name"], db, len(cands)))
        elif db:
            why = ("La BBDD de %s (%s) no está en ninguna versión: súbela después en la "
                   "pestaña BBDD. Elige con qué versión de PHP cargarlo:" % (x["name"], db))
        else:
            why = ("No se sabe qué BBDD usa %s. Elige con qué versión de PHP cargarlo:"
                   % x["name"])
        box.pack_start(label(why, "dim-label", wrap=True, max_width_chars=60), False, False, 0)
        first, radios = None, []
        for i in cands:
            notes = []
            if i["folder"] == active:
                notes.append("la activa")
            if x["php"] and i["php"].startswith(x["php"]):
                notes.append("la de su .php-version")
            text = "PHP %s  (lampp-%s)%s" % (i["php"], i["folder"],
                                            "  ·  " + ", ".join(notes) if notes else "")
            rb = Gtk.RadioButton.new_from_widget(first)
            lines = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            lines.pack_start(label(text), False, False, 0)
            when = db_date_text(*self.data["dbdate"].get((i["folder"], db), (0, ""))) if found else ""
            if when:
                lines.pack_start(label("BBDD: " + when, "dim-label", "subtitulo"),
                                 False, False, 0)
            rb.add(lines)
            first = first or rb
            # Cada opción en su tarjeta; la elegida, con el borde verde
            opt = css(Gtk.Box(), "opcion")
            opt.pack_start(rb, True, True, 0)
            rb.connect("toggled", lambda b, o=opt: (o.get_style_context().add_class("elegida")
                                                     if b.get_active() else
                                                     o.get_style_context().remove_class("elegida")))
            rb.set_active(i is pre)
            if i is pre:
                css(opt, "elegida")
            radios.append((rb, i))
            box.pack_start(opt, False, False, 0)
        box.show_all()
        resp = run_dialog(dlg)
        chosen = next((i for rb, i in radios if rb.get_active()), None)
        dlg.destroy()
        return chosen if resp == Gtk.ResponseType.ACCEPT else None

    def build_versions(self):
        clear(self.ver_box)
        d = self.data
        if d["unregistered"]:
            box, lb = group("Hay un XAMPP sin registrar",
                            "/opt/lampp es una instalación de XAMPP completa y no un enlace. "
                            "Regístrala con un nombre (por ejemplo 8.2.12) para poder gestionarla "
                            "junto a las demás.")
            row = ActionRow("XAMPP en /opt/lampp")
            b = css(Gtk.Button(label="Registrar…"), "verde")
            b.connect("clicked", self.on_register)
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)

        if d["stray"]:
            # Procesos de otras versiones que se quedaron en memoria al cambiar (el lampp de XAMPP
            # solo cierra lo que encuentra en sus .pid)
            box, lb = group("Hay procesos de otras versiones en memoria",
                            "Solo debería estar en memoria la versión montada%s. Ocupan memoria y "
                            "pueden bloquear los puertos 80, 443 y 3306."
                            % (" (lampp-%s)" % d["active"] if d["active"] else ""))
            row = ActionRow("Procesos que sobran", d["stray"])
            row.subtitle.set_line_wrap(True)
            row.subtitle.set_ellipsize(0)
            b = css(Gtk.Button(label="Cerrarlos"), "destructive-action")
            b.connect("clicked", self.on_close_stray)
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        if d["dbsys"]:
            # Tablas del sistema de MariaDB antiguas: el servidor llena su registro de errores
            ver, size = d["dbsys"]
            box, lb = group("Tablas del sistema de MariaDB antiguas",
                            "Las tablas del sistema (mysql.*) son de una MariaDB anterior y el servidor "
                            "escribe un error cada vez que las usa: su registro de errores no para de "
                            "crecer. Repararlas las pone al día con el mysql_upgrade de la versión, sin "
                            "tocar las BBDD de los proyectos, después de guardar una copia en "
                            "~/lvm-copias, y vacía el registro si es grande.")
            row = ActionRow("MariaDB de lampp-%s" % ver, "Registro de errores: %s" % fmt_size(size))
            b = css(Gtk.Button(label="Repararlas"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Reparando las tablas del sistema de MariaDB", ["reparar-bd-sistema"],
                done_text="Tablas del sistema de MariaDB al día", auto_close=True))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        old_pma = [i for i in self.installs() if pma_outdated(i["php"], i["pma"])]
        if old_pma:
            box, lb = group("phpMyAdmin antiguo",
                            "Estas versiones traen un phpMyAdmin con fallos de seguridad que ya están "
                            "corregidos. Actualizarlo pone el más nuevo que admite su PHP, con la "
                            "misma configuración; el anterior queda en phpmyadmin.anterior.")
            row = ActionRow("phpMyAdmin con fallos corregidos después",
                            ", ".join("lampp-%s (%s)" % (i["folder"], i["pma"]) for i in old_pma))
            b = css(Gtk.Button(label="Actualizarlos"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Actualizando phpMyAdmin", ["actualizar-phpmyadmin", "--todas"],
                done_text="phpMyAdmin actualizado", auto_close=True))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        if d["unsecured"]:
            # Versiones a las que les falta algo de lo que pone el gestor (cerradas a la red y lo de
            # cada repaso de seguridad): se protegen todas a la vez
            box, lb = group("A algunas versiones les faltan protecciones",
                            "Les falta algo de lo que pone el gestor: solo para este equipo (si se "
                            "arrancan a mano, escucharían en toda la red), phpMyAdmin cerrado a otras "
                            "webs, MariaDB sin acceso a los ficheros del equipo... Protegerlas lo pone, "
                            "como en la activa; pide la contraseña de administrador.")
            row = ActionRow("Versiones sin proteger",
                            ", ".join("lampp-%s" % v for v in d["unsecured"]))
            b = css(Gtk.Button(label="Protegerlas"), "verde")
            b.connect("clicked", self.on_secure_all)
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)

        if d["certs"] or d["cas"]:
            # Certificados de proyectos en los que confía todo el equipo (no solo el navegador para
            # ese dominio): con su clave se podría falsificar cualquier web real en este equipo
            why = []
            if any(r == "falta" for _, r in d["certs"]):
                why.append("no tienen el certificado (Apache no arrancaría)")
            if any(r == "sistema" for _, r in d["certs"]):
                why.append("están en /etc/ssl/certs, donde el sistema los da por buenos para cualquier web")
            if any(r == "ca" for _, r in d["certs"]):
                why.append("son de CA (con su clave se puede firmar cualquier web)")
            if d["cas"]:
                why.append("los firma una CA de confianza sin límite de dominios (%s) cuya clave puede "
                           "leer cualquier programa tuyo, como el PHP de una web" % ", ".join(d["cas"]))
            box, lb = group("Certificados en los que confía todo el equipo",
                            "Los certificados https de estos proyectos " + "; ".join(why) + ". "
                            "Arreglarlos les pone uno propio, que solo vale para su dominio, y quita "
                            "esa confianza. Después el navegador avisará una vez en cada proyecto: "
                            "acepta el aviso. Pide la contraseña de administrador.")
            names = [dom for dom, _ in d["certs"]]
            row = ActionRow("Proyectos con https", ", ".join(names[:6]) + (" y %d más" % (len(names) - 6)
                                                                        if len(names) > 6 else "")
                            if names else "Ninguno: solo la CA")
            b = css(Gtk.Button(label="Arreglarlos"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Arreglando los certificados", ["arreglar-certificados"],
                done_text="Certificados arreglados"))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        if d["untrusted"]:
            # Proyectos https cuyo certificado propio no acepta el navegador: avisa al abrirlos y las
            # herramientas que lo manejan (Claude in Chrome) no pueden pasar del aviso
            box, lb = group("El navegador avisa al abrir estos proyectos",
                            "Chrome y Firefox no aceptan todavía su certificado: sale «La conexión no "
                            "es privada» y las herramientas que manejan el navegador (como Claude in "
                            "Chrome) no pueden abrirlos. Confiar hace que acepte el certificado propio "
                            "de cada proyecto, que solo vale para su dominio: no sirve para falsificar "
                            "ninguna otra web. El de una tienda con dominio real, solo mientras esté "
                            "falseada en /etc/hosts: al dejar de falsearla, deja de aceptarlo (con su "
                            "clave se podría suplantar la web de verdad). Después, si el navegador "
                            "estaba abierto, ciérralo y vuelve a abrirlo.")
            names = d["untrusted"]
            row = ActionRow("Proyectos que avisan en el navegador",
                            ", ".join(names[:6]) + (" y %d más" % (len(names) - 6) if len(names) > 6 else ""))
            b = css(Gtk.Button(label="Confiar"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Confiando en los certificados de los proyectos", ["confiar-certificados"],
                done_text="El navegador acepta los certificados de los proyectos"))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        if d["stale"]:
            # Tiendas con dominio real cuyo certificado aun acepta el navegador y ya no estan falseadas
            # (hosts cambiado a mano): con su clave se podria suplantar la web de verdad
            box, lb = group("El navegador acepta webs reales que ya no están falseadas",
                            "El navegador aceptaba su certificado mientras estaban falseadas en "
                            "/etc/hosts. Ya no lo están, así que el navegador va a la web de verdad, y "
                            "con la clave de ese certificado (Apache la tiene en memoria) se la podría "
                            "suplantar. Quitar hace que deje de aceptarlo. Después, si el navegador "
                            "estaba abierto, ciérralo y vuelve a abrirlo.")
            names = d["stale"]
            row = ActionRow("Webs reales que acepta el navegador",
                            ", ".join(names[:6]) + (" y %d más" % (len(names) - 6) if len(names) > 6 else ""))
            b = css(Gtk.Button(label="Quitar"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Quitando los certificados de las webs reales", ["confiar-certificados", "--quitar"],
                done_text="El navegador ya no acepta esos certificados"))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)

        # Lo primero: cargar un proyecto (el bloque se crea una vez y se conserva al redibujar,
        # para no perder lo escrito en el buscador)
        if getattr(self, "proj_box", None) is None:
            self.proj_box = self.build_project_box()
        parent = self.proj_box.get_parent()
        if parent:
            parent.remove(self.proj_box)
        self.ver_box.pack_start(self.proj_box, False, False, 0)
        self.update_project_search()

        if not d["launcher"] and not SIMULATE:
            box, lb = group()
            row = ActionRow("Icono en el menú de aplicaciones",
                            "Crea el acceso «Nexum Stack» para abrir esta ventana.")
            b = Gtk.Button(label="Crear")
            b.connect("clicked", self.on_create_launcher)
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)

        act = next((i for i in d["installs"] if i["folder"] == d["active"]), None)
        box, lb = group("Versión activa")
        if act:
            row = ActionRow("PHP %s" % act["php"], "/opt/lampp → lampp-%s" % act["folder"])
            row.add_prefix(label("●", "punto-verde" if d["running"] else "punto-gris"))
            row.add_suffix(label("En marcha" if d["running"] else "Parada", "dim-label"))
            # Parar = lvm disable: para y quita el enlace /opt/lampp, asi que php (enlazado a
            # /opt/lampp/bin/php) deja de responder. Tambien con la version ya parada
            actions = [("view-refresh-symbolic", "Reiniciar", "reiniciar", "icono-azul")] \
                if d["running"] else \
                [("media-playback-start-symbolic", "Arrancar", "arrancar", "icono-verde")]
            actions.append(("media-playback-stop-symbolic",
                            "Parar y desactivar (como lvm disable): php deja de responder hasta "
                            "que actives una versión", "parar", "icono-rojo"))
            for ic, tip, cmd, color in actions:
                b = css(Gtk.Button(tooltip_text=tip, relief=Gtk.ReliefStyle.NONE), color)
                b.add(icon(ic))
                b.connect("clicked", self.on_control, cmd, tip)
                row.add_suffix(b)
            web = Gtk.Button(label="Abrir localhost", sensitive=d["running"])
            web.connect("clicked", lambda *_: self.open_uri("http://localhost/"))
            row.add_suffix(web)
        else:
            row = ActionRow("Ninguna versión activa",
                            "Activa una de las versiones instaladas para usarla.")
            row.add_prefix(label("●", "punto-gris"))
        lb.add(row)
        self.ver_box.pack_start(box, False, False, 0)

        self.sg_tag = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)
        self.sg_btn = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)
        if d["installs"]:
            box, lb = group("Instaladas", "Pulsa una versión para ver sus componentes.")
            for inst in d["installs"]:
                lb.add(self.version_row(inst))
        else:
            box, lb = group("Instaladas")
            row = ActionRow("No hay ninguna versión instalada",
                            "Instala la primera más abajo.")
            lb.add(row)
        self.ver_box.pack_start(box, False, False, 0)
        # Debajo, instalar nuevas versiones (se rellena aparte, al consultar php.net)
        parent = self.inst_box.get_parent()
        if parent:
            parent.remove(self.inst_box)
        self.ver_box.pack_start(self.inst_box, False, False, 0)
        self.ver_box.show_all()

    def version_row(self, inst):
        folder = inst["folder"]
        is_active = folder == self.data["active"]
        exp = ExpanderRow("PHP %s" % inst["php"], "/opt/lampp-%s" % folder,
                          on_toggle=lambda on, f=folder: self.remember(f, on))
        kind = inst["kind"]
        # Icono: el de XAMPP si es (o va sobre) un XAMPP; el de PHP si es una pila propia
        if kind != "propia":
            for c in exp.prefix.get_children():
                exp.prefix.remove(c)
            exp.add_prefix(section_icon(("logo", "xampp"), 16))
        tag = label({"XAMPP": "XAMPP", "propia": "Pila propia"}.get(kind, "Sobre XAMPP"),
                    "tag", "dim-label", xalign=0.5)
        self.sg_tag.add_widget(tag)
        exp.add_suffix(tag)
        if is_active:
            b = css(Gtk.Button(label="Activa", can_focus=False), "verde")
        else:
            b = Gtk.Button(label="Activar")
            b.connect("clicked", self.on_activate_version, folder)
        self.sg_btn.add_widget(b)
        exp.add_suffix(b)

        dbs = len(self.data["dbs"].get(folder, []))
        db_text = plural(dbs, "propia", "propias") if inst["owner"] == folder else \
            "usa las de lampp-%s" % inst["owner"]
        for name, val, spec in [
                ("Apache", inst["apache"], ("logo", "apache")),
                ("MariaDB", inst["mariadb"], ("logo", "mariadb")),
                ("ProFTPD", inst["ftp"], ("icono", "folder-remote-symbolic", "")),
                ("Perl", inst["perl"], ("logo", "perl")),
                ("phpMyAdmin", inst["pma"], ("logo", "phpmyadmin")),
                ("BBDD", db_text, ("icono", "drive-multidisk-symbolic", ""))]:
            r = ActionRow(name)
            # (su propio icono, en lugar del que pondría la fila por su título)
            for c in r.prefix.get_children():
                r.prefix.remove(c)
            r.add_prefix(section_icon(spec, 16))
            if name == "phpMyAdmin" and pma_outdated(inst["php"], inst["pma"]):
                r.add_title_tag(label("antiguo", "estado", "seguridad"))
                up = Gtk.Button(label="Actualizar", tooltip_text="Pone el phpMyAdmin más nuevo que admite "
                                "su PHP (el anterior queda en phpmyadmin.anterior)")
                up.connect("clicked", lambda *_, f=folder: self.on_update_pma(f))
                r.add_suffix(up)
            r.add_suffix(label(val, "dim-label"))
            exp.add_row(r)

        actions = Gtk.Box(spacing=8, halign=Gtk.Align.END, margin=10)
        branch = inst["php"].rsplit(".", 1)[0]
        if kind != "XAMPP" and branch == folder:
            up = Gtk.Button(label="Actualizar")
            up.connect("clicked", self.on_update, folder)
            actions.pack_start(up, False, False, 0)
        rm = css(Gtk.Button(label="Desinstalar…", sensitive=not inst["blocker"]),
                 "destructive-action")
        if inst["blocker"]:
            rm.set_tooltip_text(inst["blocker"])
        rm.connect("clicked", self.on_remove, inst)
        actions.pack_start(rm, False, False, 0)
        exp.add_row(actions)
        if folder in self.expanded:
            exp.set_expanded(True)
        return exp

    def remember(self, folder, on):
        (self.expanded.add if on else self.expanded.discard)(folder)

    # acciones
    def run_task(self, title, args, **kw):
        self.busy = True
        user_done = kw.pop("on_done", None)

        def done(ok, task, p):
            self.busy = False
            if user_done:
                user_done(ok, task, p)
            self.reload(branches=kw_reload)
        kw_reload = kw.pop("reload_branches", False)
        return Task(self, title, args, on_done=done, **kw)

    def on_control(self, _btn, cmd, what):
        folder = self.data["active"]
        if cmd == "parar":
            self.run_task("Parando y desactivando lampp-%s" % folder, ["disable"],
                          done_text="lampp-%s parada y desactivada" % folder, auto_close=True)
            return
        texts = {"arrancar": "Versión activa arrancada", "reiniciar": "Versión activa reiniciada"}
        self.run_task("%s lampp-%s" % (what, folder), [cmd], done_text=texts[cmd], auto_close=True)

    def on_vhosts(self, *_):
        """Los vhosts son del administrador (Apache los lee como root al arrancar): se edita una
        copia en ~/.lvm-instalador y, al pulsar Aplicar, el script la comprueba, la escribe con sudo
        (guardando antes la anterior en ~/lvm-copias) y recarga Apache."""
        if not self.data:
            return
        path = self.data["vhosts"]
        real = os.path.realpath(path)
        if not os.path.isfile(real):
            message(self.win, "No se encuentra el fichero de vhosts",
                    "%s no existe en la versión activa." % path, Gtk.MessageType.WARNING)
            return
        copy = os.path.join(LOG_DIR, "httpd-vhosts.conf")
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            shutil.copyfile(real, copy)
        except OSError as exc:
            message(self.win, "No se ha podido leer %s" % real, str(exc), Gtk.MessageType.ERROR)
            return
        self.open_text(copy)
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.INFO,
                                buttons=Gtk.ButtonsType.NONE, text="Editar vhosts")
        dlg.format_secondary_text(
            "Los vhosts (%s) son del administrador: Apache los lee como root al arrancar. Se abre "
            "una copia (%s) en el editor de textos.\n\nHaz los cambios, guárdalos y pulsa Aplicar: "
            "se comprueban, se guarda una copia de los actuales en ~/lvm-copias, se escriben los "
            "nuevos (pide la contraseña de sudo) y se recarga Apache. Si Apache no los acepta, se "
            "dejan como estaban." % (real, copy))
        widen(dlg)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Aplicar", Gtk.ResponseType.ACCEPT), "verde")
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        try:
            with open(real, "rb") as a, open(copy, "rb") as b:
                same = a.read() == b.read()
        except OSError:
            same = False
        if same:
            self.toast("No has cambiado nada en los vhosts (¿guardaste los cambios?)")
            return
        self.run_task("Guardando los vhosts", ["vhosts", "--aplicar", copy],
                      done_text="Vhosts actualizados", auto_close=True)

    def on_hosts(self, *_):
        """/etc/hosts es de root: se edita una copia en ~/.lvm-instalador y, al pulsar Aplicar,
        el script la escribe encima con sudo (guardando antes el anterior en ~/lvm-copias)."""
        src = self.data["hosts"] if self.data else "/etc/hosts"
        copy = os.path.join(LOG_DIR, "hosts")
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            shutil.copyfile(src, copy)
        except OSError as exc:
            message(self.win, "No se ha podido leer %s" % src, str(exc), Gtk.MessageType.ERROR)
            return
        self.open_text(copy)
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.INFO,
                                buttons=Gtk.ButtonsType.NONE, text="Editar hosts")
        dlg.format_secondary_text(
            "%s es del administrador, así que se abre una copia (%s) en el editor de textos.\n\n"
            "Haz los cambios, guárdalos y pulsa Aplicar: se guarda una copia del %s actual en "
            "~/lvm-copias y se escribe el nuevo (pide la contraseña de sudo)." % (src, copy, src))
        widen(dlg)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Aplicar", Gtk.ResponseType.ACCEPT), "verde")
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        try:
            with open(src, "rb") as a, open(copy, "rb") as b:
                same = a.read() == b.read()
        except OSError:
            same = False
        if same:
            self.toast("No has cambiado nada en %s (¿guardaste los cambios?)" % src)
            return
        self.run_task("Guardando %s" % src, ["hosts", "--aplicar", copy],
                      done_text="%s actualizado" % src, auto_close=True)

    def on_activate_version(self, _btn, folder):
        self.run_task("Activando lampp-%s" % folder, ["use", folder],
                      done_text="lampp-%s activada" % folder, auto_close=True)

    def on_update(self, btn, folder):
        btn.set_sensitive(False)
        self.toast("Comprobando si hay una versión más nueva…")

        def checked(_rc, out):
            btn.set_sensitive(True)
            res = out.strip().splitlines()[-1].split("|") if out.strip() else ["error"]
            if res[0] == "si":
                self.toast("El paquete lampp-%s se encuentra actualizado" % folder)
            elif res[0] == "no" and len(res) > 1:
                if confirm(self.win, "¿Actualizar lampp-%s?" % folder,
                           "Se instalará PHP %s con los últimos parches de Apache, MariaDB, "
                           "ProFTPD, Perl y phpMyAdmin de su rama. La versión actual sigue "
                           "funcionando mientras se compila. Tarda varios minutos." % res[1],
                           "Actualizar"):
                    self.run_task("Actualizando lampp-%s" % folder, ["actualizar", folder],
                                  progress=True, reload_branches=True,
                                  done_text="lampp-%s actualizada a PHP %s" % (folder, res[1]))
            else:
                message(self.win, "No se ha podido comprobar la versión",
                        "No se ha podido consultar php.net. Comprueba la conexión a internet.",
                        Gtk.MessageType.WARNING)
            return False
        run_quick(["gui-al-dia", folder], checked)

    def on_remove(self, _btn, inst):
        folder = inst["folder"]
        own = inst["owner"] == folder
        dbs = self.data["dbs"].get(folder, []) if own else []
        text = "Se borrará la carpeta /opt/lampp-%s (PHP %s). " % (folder, inst["php"])
        if not own:
            text += "Sus BBDD no se tocan: son las de lampp-%s. " % inst["owner"]
        elif dbs:
            text += "Sus %s se borrarán con ella. " % plural(len(dbs), "BBDD propia",
                                                            "BBDD propias")
        text += "Los proyectos de /opt/htdocs y los vhosts no se tocan."

        extra = None
        state = {"copy": bool(dbs)}
        if dbs:
            extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            copy = Gtk.CheckButton(label="Guardar antes una copia de sus BBDD en "
                                         "~/lvm-copias", active=True)
            extra.pack_start(copy, False, False, 0)
            warn = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            warn.pack_start(label("Sin copia, las BBDD no se podrán recuperar. "
                                  "Escribe %s para confirmar:" % folder, "error", wrap=True,
                                  max_width_chars=50), False, False, 0)
            entry = Gtk.Entry()
            warn.pack_start(entry, False, False, 0)
            warn.set_no_show_all(True)
            extra.pack_start(warn, False, False, 0)

        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.WARNING,
                                buttons=Gtk.ButtonsType.NONE,
                                text="¿Desinstalar lampp-%s?" % folder)
        dlg.format_secondary_text(text)
        if extra:
            dlg.get_message_area().pack_start(extra, False, False, 0)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Desinstalar", Gtk.ResponseType.ACCEPT), "destructive-action")
        dlg.set_default_response(Gtk.ResponseType.CANCEL)
        if dbs:
            def update(*_):
                state["copy"] = copy.get_active()
                warn.set_visible(not state["copy"])
                for child in warn.get_children():
                    child.show()
                ok.set_sensitive(state["copy"] or entry.get_text().strip() == folder)
            copy.connect("toggled", update)
            entry.connect("changed", update)
        dlg.show_all()
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        args = ["desinstalar", folder] + (["--copia"] if state["copy"] else [])
        self.expanded.discard(folder)
        self.run_task("Desinstalando lampp-%s" % folder, args, reload_branches=True,
                      done_text="lampp-%s desinstalada" % folder
                      + (" (copia en ~/lvm-copias)" if state["copy"] else ""))

    def on_register(self, *_):
        entry = Gtk.Entry(placeholder_text="por ejemplo 8.2.12")
        dlg_ok = confirm(self.win, "Registrar el XAMPP de /opt/lampp",
                         "Se moverá a /opt/lampp-<nombre> y compartirá htdocs y los vhosts con "
                         "las demás versiones. Escribe el nombre de la versión:",
                         "Registrar", extra=entry)
        name = entry.get_text().strip()
        if not dlg_ok or not name:
            return
        if not re.match(r"^[0-9A-Za-z._-]+$", name):
            message(self.win, "Nombre no válido", "Usa solo números, letras, puntos y guiones.")
            return
        self.run_task("Registrando lampp-%s" % name, ["add", name],
                      done_text="XAMPP registrado como lampp-%s" % name)

    def on_create_launcher(self, *_):
        def done(rc, out):
            self.toast("Icono creado en el menú de aplicaciones" if rc == 0 else
                       "No se ha podido crear el icono")
            self.reload()
            return False
        run_quick(["gui-crear-acceso"], done)

    # ------------------------------------------------------------ instalar
    def build_install(self):
        clear(self.inst_box)
        self.checks = {}
        if self.branches_error:
            box, lb = group("Instalar nuevas versiones de PHP")
            row = ActionRow("No se han podido consultar las versiones", self.branches_error)
            row.add_prefix(css(icon("dialog-warning-symbolic"), "error"))
            b = Gtk.Button(label="Reintentar")
            b.connect("clicked", self.on_refresh)
            row.add_suffix(b)
            lb.add(row)
            self.inst_box.pack_start(box, False, False, 0)
            self.inst_box.show_all()
            return

        box, lb = group("Instalar nuevas versiones de PHP",
                        "Cada versión lleva su propio Apache, MariaDB, ProFTPD y Perl, "
                        "compilados para ella, y sus propias BBDD. Según php.net: "
                        "Estable recibe correcciones de errores y de seguridad (la mejor opción "
                        "para proyectos nuevos), Solo seguridad recibe únicamente parches de "
                        "seguridad hasta la fecha indicada y Sin soporte ya no recibe parches.")
        rows = sorted((f for f in self.branches if f[0] == "B"),
                      key=lambda f: [int(x) for x in f[1].split(".")], reverse=True)
        for f in rows:
            _, branch, latest, sup, maria, perl, state, folder = (f + [""] * 8)[:8]
            stack = "Apache 2.4  ·  MariaDB %s  ·  Perl %s" % (maria, perl)
            date, sec = branch_release(f)
            if state == "nueva":
                r = ActionRow("PHP %s" % latest, "%s  ·  → /opt/lampp-%s" % (stack, folder),
                              activatable=True)
                chk = Gtk.CheckButton()
                chk.connect("toggled", self.on_check)
                r.add_prefix(chk)
                r.on_activate = chk.activate
                self.checks["php:" + latest] = (chk, latest)
            else:
                sub = {"instalada": "Ya instalada en /opt/lampp-%s" % folder,
                       "actualizable": "lampp-%s tiene un parche anterior: usa Actualizar en "
                                       "Instaladas" % folder,
                       "existe": "Ya existe /opt/lampp-%s" % folder}.get(state, state)
                r = ActionRow("PHP %s" % latest, sub)
                r.add_prefix(icon("object-select-symbolic" if state == "instalada"
                                  else "dialog-information-symbolic"))
                r.set_sensitive(False)
            # Junto a la versión, la fecha en que se publicó y si es un parche de seguridad
            if date and date != "-":
                r.add_title_tag(label(fmt_day(date), "dim-label", "fecha-version"))
                r.add_title_tag(release_tag(sec))
            st, active_end, security_end = branch_state(f)
            r.add_suffix(state_pill(st, active_end, security_end))
            if st == "security" and security_end:
                r.subtitle.set_label(r.subtitle.get_label()
                                     + "  ·  seguridad hasta %s" % fmt_month(security_end))
            lb.add(r)
        self.inst_box.pack_start(box, False, False, 0)

        box, lb = group("Otras opciones")
        other = ActionRow("Otro parche concreto…",
                          "Una versión anterior de cualquier rama, en su propia carpeta",
                          activatable=True)
        other.add_suffix(icon("go-next-symbolic"))
        other.on_activate = self.on_pick_patch
        lb.add(other)
        for version in self.extra_patches:
            r = ActionRow("PHP %s" % version, "Parche concreto  ·  → /opt/lampp-%s" % version)
            chk = Gtk.CheckButton(active=True)
            chk.connect("toggled", self.on_check)
            r.add_prefix(chk)
            rm = Gtk.Button(tooltip_text="Quitar de la lista", relief=Gtk.ReliefStyle.NONE)
            rm.add(icon("window-close-symbolic"))
            rm.connect("clicked", self.on_drop_patch, version)
            r.add_suffix(rm)
            self.checks["parche:" + version] = (chk, version)
            lb.add(r)
        xampps = [f for f in self.branches if f[0] == "X"]
        if xampps:
            xexp = ExpanderRow("XAMPP oficiales", "Para proyectos antiguos (PHP 7.1 a 8.2)",
                               on_toggle=lambda on: self.remember("@xampp", on))
            for f in xampps:
                _, folder, release, php, installed = (f + [""] * 5)[:5]
                if installed == "1":
                    xr = ActionRow("XAMPP %s" % release, "Ya instalado en /opt/lampp-%s" % folder)
                    xr.set_sensitive(False)
                else:
                    xr = ActionRow("XAMPP %s" % release,
                                   "PHP %s  ·  → /opt/lampp-%s" % (php, folder), activatable=True)
                    chk = Gtk.CheckButton()
                    chk.connect("toggled", self.on_check)
                    xr.add_prefix(chk)
                    xr.on_activate = chk.activate
                    self.checks["xampp:" + folder] = (chk, folder)
                xexp.add_row(xr)
            if "@xampp" in self.expanded:
                xexp.set_expanded(True)
            lb.add(xexp)
        self.inst_box.pack_start(box, False, False, 0)

        self.install_btn = css(Gtk.Button(halign=Gtk.Align.CENTER), "verde", "pildora")
        self.install_btn.connect("clicked", self.on_install)
        self.inst_box.pack_start(self.install_btn, False, False, 0)
        self.inst_box.show_all()
        self.on_check()

    def selected(self):
        return [key for key, (chk, _v) in self.checks.items() if chk.get_active()]

    def on_check(self, *_):
        n = len(self.selected())
        self.install_btn.set_sensitive(n > 0)
        self.install_btn.set_label("Marca una o más versiones" if n == 0 else
                                   "Instalar %s" % plural(n, "versión", "versiones"))

    def on_drop_patch(self, _btn, version):
        self.extra_patches.remove(version)
        self.build_install()

    def on_pick_patch(self):
        branch_rows = {f[1]: f for f in self.branches if f[0] == "B"}
        branches = sorted(branch_rows, key=lambda b: [int(x) for x in b.split(".")], reverse=True)
        state_names = {"stable": "estable", "security": "solo seguridad", "eol": "sin soporte"}
        dlg = Gtk.Dialog(title="Otro parche de PHP", transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(620, 540)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        add = css(dlg.add_button("Añadir", Gtk.ResponseType.OK), "verde")
        add.set_sensitive(False)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=16)
        combo = Gtk.ComboBoxText()
        for b in branches:
            combo.append(b, "PHP %s  (%s)" % (b, state_names.get(branch_state(branch_rows[b])[0], "")))
        top = Gtk.Box(spacing=10)
        top.pack_start(label("Rama:"), False, False, 0)
        top.pack_start(combo, False, False, 0)
        box.pack_start(top, False, False, 0)
        sw = Gtk.ScrolledWindow(vexpand=True)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE,
                             activate_on_single_click=False), "caja")
        sw.add(lb)
        box.pack_start(sw, True, True, 0)
        status = label("", "dim-label")
        box.pack_start(status, False, False, 0)
        box.pack_start(label("Las versiones publicadas en php.net son todas definitivas, pero los "
                             "parches anteriores al último no tienen sus correcciones de "
                             "seguridad: úsalos solo si un proyecto necesita esa versión.",
                             "dim-label", wrap=True, max_width_chars=50), False, False, 0)
        dlg.get_content_area().add(box)
        chosen = {}

        def on_select(_lb, row):
            chosen["v"] = getattr(row, "version", None) if row else None
            add.set_sensitive(bool(chosen.get("v")))
        lb.connect("row-selected", on_select)
        lb.connect("row-activated", lambda _lb, row: getattr(row, "version", None)
                   and dlg.response(Gtk.ResponseType.OK))

        def loaded(rc, out, branch):
            if combo.get_active_id() != branch:
                return False
            clear(lb)
            rows = [f for f in parse_lines(out) if f[0] == "P"]
            if rc != 0 or not rows:
                status.set_label("No se ha podido consultar php.net.")
                return False
            st = branch_state(branch_rows[branch])
            status.set_label("PHP %s: %s" % (branch, {
                "stable": "estable, con correcciones de errores y de seguridad",
                "security": "solo parches de seguridad" + (" hasta %s" % fmt_month(st[2]) if st[2] else ""),
            }.get(st[0], "sin soporte de php.net")))
            for i, f in enumerate(rows):
                _, version, date, folder, state, sec = (f + [""] * 6)[:6]
                if state == "nueva" and version not in self.extra_patches:
                    r = ActionRow("PHP %s" % version, "→ /opt/lampp-%s" % folder)
                    r.version = version if folder == version else None
                    # ActionRow no se puede seleccionar por defecto: estas filas si (y con
                    # doble clic o Intro se añade directamente)
                    r.set_selectable(bool(r.version))
                    r.set_activatable(bool(r.version))
                    if folder != version:
                        # El ultimo parche de la rama va en lampp-X.Y: se marca en la lista principal
                        r.subtitle.set_label("Es la última: márcala en la lista principal")
                        r.set_sensitive(False)
                else:
                    r = ActionRow("PHP %s" % version, "%s" % (
                        "Ya instalada" if state == "instalada" else
                        "Ya en la lista" if version in self.extra_patches else
                        "Ya existe /opt/lampp-%s" % folder))
                    r.version = None
                    r.set_sensitive(False)
                if date and date != "-":
                    r.add_title_tag(label(fmt_day(date), "dim-label", "fecha-version"))
                r.add_title_tag(release_tag(sec))
                if i == 0:
                    r.add_suffix(label("Último", "pastilla", "estable" if st[0] != "eol" else "soporte-no"))
                lb.add(r)
            lb.show_all()
            return False

        def on_branch(*_):
            branch = combo.get_active_id()
            clear(lb)
            add.set_sensitive(False)
            status.set_label("Consultando los parches de PHP %s…" % branch)
            run_quick(["gui-parches", branch], lambda rc, out: loaded(rc, out, branch))
        combo.connect("changed", on_branch)
        dlg.show_all()
        if branches:
            combo.set_active(0)
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp == Gtk.ResponseType.OK and chosen.get("v"):
            self.extra_patches.append(chosen["v"])
            self.build_install()

    def on_install(self, *_):
        sel = self.selected()
        if not sel:
            return
        php = [self.checks[k][1] for k in sel if not k.startswith("xampp:")]
        xampp = [self.checks[k][1] for k in sel if k.startswith("xampp:")]
        names = ["XAMPP %s" % x for x in xampp] + ["PHP %s" % v for v in php]
        text = ("Se va a instalar: %s.\n\nCada versión de PHP se compila en tu equipo y tarda "
                "unos minutos (más en equipos lentos). Se pedirá la contraseña de "
                "administrador una sola vez. Las versiones instaladas no se tocan."
                % ", ".join(names))
        if not confirm(self.win, "¿Instalar %s?" % plural(len(names), "versión", "versiones"),
                       text, "Instalar"):
            return
        args = ["instalar"]
        if xampp:
            args += ["--xampp", ",".join(xampp)]
        if php:
            args += ["--php", ",".join(php)]
        args.append("--si")
        installed = [k for k in sel]

        def done(ok, task, p):
            if not p:
                return
            good = [item for item, rc in p["results"] if rc == "0"]
            for k in installed:
                if k.startswith("parche:") and any(g.endswith(k.split(":", 1)[1]) for g in good):
                    self.extra_patches = [v for v in self.extra_patches
                                          if v != k.split(":", 1)[1]]
            if len(good) == 1 and not SIMULATE:
                folder = item_folder(good[0])
                task.offer("Activar lampp-%s" % folder,
                           lambda: self.on_activate_version(None, folder))

        self.run_task("Instalando", args, progress=True, reload_branches=True, on_done=done,
                      done_text="Instalación terminada")

    # ------------------------------------------------------- bases de datos
    def build_databases(self):
        # El buscador no se redibuja (si no, se perderia lo escrito y el foco al refrescar)
        if getattr(self, "db_dyn", None) is None or self.db_dyn.get_parent() is None:
            clear(self.db_box)
            self.db_box.pack_start(self.build_db_search(), False, False, 0)
            self.db_dyn = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
            self.db_box.pack_start(self.db_dyn, False, False, 0)
        clear(self.db_dyn)
        d = self.data
        box, lb = group("BBDD por versión",
                        "Cada versión tiene su propio MariaDB. No se muestran las BBDD del "
                        "sistema (mysql, phpmyadmin…).")
        if not d["installs"]:
            lb.add(ActionRow("No hay ninguna versión instalada"))
        for inst in d["installs"]:
            folder = inst["folder"]
            dbs = d["dbs"].get(folder, [])
            sub = "MariaDB %s  ·  %s" % (inst["mariadb"], plural(len(dbs), "BBDD",
                                                                 "BBDD"))
            if inst["owner"] != folder:
                sub += "  ·  las de lampp-%s" % inst["owner"]
            exp = ExpanderRow("lampp-%s" % folder, sub,
                              on_toggle=lambda on, f=folder: self.remember("@db" + f, on))
            active = folder == d["active"]
            if active:
                exp.add_title_tag(label("Activa", "texto-activa"))
                pma = Gtk.Button(label="Abrir phpMyAdmin", sensitive=d["running"],
                                 tooltip_text=None if d["running"] else
                                 "La versión activa está parada: arráncala en Versiones")
                pma.connect("clicked", lambda *_: self.open_uri("http://127.0.0.1/phpmyadmin/"))
                exp.add_suffix(pma)
                row = ActionRow("Crear BBDD…")
                row.add_prefix(icon("list-add-symbolic"))
                row.set_activatable(True)
                row.on_activate = self.on_create_db
                exp.add_row(row)
            elif not dbs:
                exp.add_row(ActionRow("Sin BBDD propias"))
            for db in dbs:
                row = ActionRow(db, db_date_text(*d["dbdate"].get((folder, db), (0, ""))))
                if d["dbdate"].get((folder, db), (0, ""))[1] == "c":
                    row.subtitle.set_tooltip_text(DB_DATE_HELP)
                if is_ps_db(db):
                    row.add_suffix(self.cache_button(db))
                copy = self.copy_button(db, inst)
                if copy:
                    row.add_suffix(copy)
                row.add_suffix(self.download_button(db, folder))
                if active:
                    b = Gtk.Button(tooltip_text="Borrar la BBDD %s" % db,
                                   relief=Gtk.ReliefStyle.NONE)
                    b.add(icon("user-trash-symbolic"))
                    b.connect("clicked", lambda _b, n=db: self.on_drop_db(n))
                    row.add_suffix(b)
                exp.add_row(row)
            if "@db" + folder in self.expanded:
                exp.set_expanded(True)
            lb.add(exp)
        self.db_dyn.pack_start(box, False, False, 0)
        self.db_dyn.pack_start(self.build_import(), False, False, 0)
        self.db_box.show_all()
        self.update_db_search()

    def cache_button(self, db):
        """Vaciar var/cache de la tienda PrestaShop de la base (la carpeta la busca el script)."""
        b = Gtk.Button(tooltip_text="Vaciar la caché (var/cache) de la tienda de %s" % db,
                       relief=Gtk.ReliefStyle.NONE, sensitive=not self.busy)
        b.add(icon("edit-clear-all-symbolic"))
        b.connect("clicked", lambda *_: self.run_task(
            "Vaciando la caché de la tienda de %s" % db, ["vaciar-cache", "--bd", db],
            done_text="Caché vaciada", auto_close=True))
        return b

    def copy_targets(self, db, inst):
        """Versiones a las que se puede copiar la base: las que no comparten las bases con la de
        origen. Las que ya la tienen también (se sustituye, con copia antes)."""
        return [i for i in self.installs() if i["owner"] != inst["owner"]]

    def has_db(self, folder, db):
        return db in self.data["dbs"].get(folder, [])

    def copy_button(self, db, inst):
        """Copiar la base a otra versión de PHP que no la tenga (para probar el proyecto con ella)."""
        if not self.copy_targets(db, inst):
            return None
        b = Gtk.Button(tooltip_text="Copiar %s a otra versión de PHP (para probar el proyecto con ella)" % db,
                       relief=Gtk.ReliefStyle.NONE, sensitive=not self.busy)
        b.add(icon("edit-copy-symbolic"))
        b.connect("clicked", lambda *_: self.on_copy_db(db, inst))
        return b

    def on_copy_db(self, db, inst):
        targets = self.copy_targets(db, inst)
        if not targets:
            return
        dlg = Gtk.Dialog(title="Copiar BBDD", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(520, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Copiar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        box.pack_start(css(label("¿A qué versión de PHP quieres copiarla?", wrap=True,
                                 max_width_chars=60), "title-3"), False, False, 0)
        box.pack_start(label("Se copia %s desde lampp-%s, que no se toca. Después, carga el "
                             "proyecto en esa versión para probarlo con su PHP. Si no es la activa, se "
                             "arranca su MariaDB solo para la copia y se pide la contraseña de "
                             "administrador. Si la versión ya tiene %s, se sustituye: antes se guarda "
                             "una copia suya en ~/lvm-copias." % (db, inst["folder"], db),
                             "dim-label", wrap=True, max_width_chars=60), False, False, 0)
        first, radios = None, []
        # (primero las que no la tienen; dentro, de la más nueva a la más antigua)
        for i in sorted(targets, key=lambda i: (not self.has_db(i["folder"], db),
                                                [int(n) if n.isdigit() else 0 for n in i["php"].split(".")]),
                        reverse=True):
            rb = Gtk.RadioButton.new_from_widget(first)
            rb.add(label("PHP %s  (lampp-%s)%s%s" % (
                i["php"], i["folder"], "  ·  la activa" if i["folder"] == self.data["active"] else "",
                "  ·  ya la tiene: se sustituye" if self.has_db(i["folder"], db) else "")))
            first = first or rb
            opt = css(Gtk.Box(), "opcion")
            opt.pack_start(rb, True, True, 0)
            rb.connect("toggled", lambda b, o=opt: (o.get_style_context().add_class("elegida")
                                                     if b.get_active() else
                                                     o.get_style_context().remove_class("elegida")))
            if rb is first:
                css(opt, "elegida")
            radios.append((rb, i))
            box.pack_start(opt, False, False, 0)
        box.show_all()
        resp = run_dialog(dlg)
        chosen = next((i for rb, i in radios if rb.get_active()), None)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT or chosen is None:
            return
        args = ["copiar-bd", db, inst["folder"], chosen["folder"]]
        if self.has_db(chosen["folder"], db):
            if not confirm(self.win, "¿Sustituir %s en lampp-%s?" % (db, chosen["folder"]),
                           "lampp-%s ya tiene una BBDD %s. Se guarda antes una copia suya en "
                           "~/lvm-copias y después se pone en su lugar la de lampp-%s: lo que "
                           "tuviera la de lampp-%s se pierde (salvo en esa copia)."
                           % (chosen["folder"], db, inst["folder"], chosen["folder"]),
                           "Sustituir", destructive=True):
                return
            args.append("--sustituir")
        self.run_task("Copiando %s a lampp-%s" % (db, chosen["folder"]), args,
                      done_text="%s copiada a lampp-%s" % (db, chosen["folder"]), auto_close=True)

    def download_button(self, db, folder):
        b = Gtk.Button(tooltip_text="Descargar una copia de %s (.zip)" % db,
                       relief=Gtk.ReliefStyle.NONE)
        b.add(icon("document-save-symbolic"))
        b.connect("clicked", lambda *_: self.on_download_db(db, folder))
        return b

    # ------------------------------------------------------ buscador de bases
    def build_db_search(self):
        box, lb = group("Buscar una BBDD",
                        "Escribe parte del nombre para ver en qué versión está y qué PHP "
                        "tienes que activar para trabajar con ella.")
        self.db_entry = Gtk.SearchEntry(placeholder_text="Nombre de la BBDD…",
                                        margin_top=6)
        self.db_entry.connect("search-changed", lambda *_: self.update_db_search())
        self.db_entry.connect("stop-search", lambda e: e.set_text(""))
        box.pack_start(self.db_entry, False, False, 0)
        box.reorder_child(self.db_entry, len(box.get_children()) - 2)
        self.db_found = label("", "dim-label", "subtitulo")
        self.db_found.set_no_show_all(True)
        box.pack_start(self.db_found, False, False, 0)
        box.reorder_child(self.db_found, len(box.get_children()) - 2)
        lb.set_no_show_all(True)
        self.db_results = lb
        return box

    def db_installs(self, db, skip_owner=None):
        """Versiones en las que está la base (sin repetir las que comparten bases)."""
        return [i for i in self.installs() if db in self.data["dbs"].get(i["folder"], [])
                and i["owner"] != skip_owner]

    def update_db_search(self):
        if getattr(self, "db_results", None) is None or not self.data:
            return
        lb, q = self.db_results, self.db_entry.get_text().strip().lower()
        clear(lb)
        if not q:
            lb.hide()
            self.db_found.hide()
            return
        hits = [(db, inst) for inst in self.installs()
                for db in self.data["dbs"].get(inst["folder"], []) if q in db.lower()]
        # Primero la coincidencia exacta, luego las que empiezan igual; la activa delante
        hits.sort(key=lambda h: (h[0].lower() != q, not h[0].lower().startswith(q),
                                 h[0].lower(), h[1]["folder"] != self.data["active"]))
        names = len({h[0] for h in hits})
        if hits:
            self.db_found.set_label("%s en %s" % (
                plural(names, "BBDD", "BBDD"),
                plural(len({h[1]["folder"] for h in hits}), "versión", "versiones")))
        else:
            self.db_found.set_label("Ninguna versión tiene una BBDD con «%s» en el "
                                    "nombre." % q)
        self.db_found.show()
        if not hits:
            lb.hide()
            return
        limit = 40
        for db, inst in hits[:limit]:
            lb.add(self.db_hit_row(db, inst, q))
        if len(hits) > limit:
            lb.add(ActionRow("Y %d más…" % (len(hits) - limit),
                             "Escribe más letras del nombre para encontrarla."))
        # no_show_all (para que no aparezca vacía) hace que show_all no la toque: fila a fila
        for row in lb.get_children():
            row.show_all()
        lb.show()

    def db_hit_row(self, db, inst, q):
        folder = inst["folder"]
        row = ActionRow(db)
        start = db.lower().find(q)
        esc = GLib.markup_escape_text
        row.title.set_markup("%s<b>%s</b>%s" % (esc(db[:start]), esc(db[start:start + len(q)]),
                                                esc(db[start + len(q):])))
        sub = "lampp-%s  ·  PHP %s  ·  MariaDB %s" % (folder, inst["php"], inst["mariadb"])
        if inst["owner"] != folder:
            sub += "  ·  las de lampp-%s" % inst["owner"]
        when, kind = self.data["dbdate"].get((folder, db), (0, ""))
        if when:
            sub += "\n" + db_date_text(when, kind)
            if kind == "c":
                row.subtitle.set_tooltip_text(DB_DATE_HELP)
        row.subtitle.set_label(sub)
        row.subtitle.set_no_show_all(False)
        if is_ps_db(db):
            row.add_suffix(self.cache_button(db))
        row.add_suffix(self.download_button(db, folder))
        # Punto verde: su version de PHP es la activa
        active = folder == self.data["active"]
        dot = label("●", "punto-verde" if active else "punto-gris")
        dot.set_tooltip_text("Su versión de PHP está activa" if active else
                             "Su versión de PHP no está activa")
        row.add_prefix(dot)
        if active:
            b = Gtk.Button(label="Elegir como destino",
                           tooltip_text="Elegirla abajo, en «Subir o actualizar una BBDD»")
            b.connect("clicked", lambda *_: self.use_as_destination(db))
            row.add_suffix(b)
        load = Gtk.Button(label="Cargar proyecto", sensitive=not self.busy,
                          tooltip_text="Apunta el vhost (web.local) a su carpeta de htdocs y, si "
                                       "hace falta, cambia a lampp-%s (PHP %s)"
                                       % (folder, inst["php"]))
        load.connect("clicked", lambda *_: self.on_load_project(db, inst))
        row.add_suffix(load)
        return row

    def use_as_destination(self, db):
        self.imp.update(db=db)
        self.build_databases()
        self.toast("BBDD de destino: %s" % db)
        # Baja hasta el formulario de carga
        GLib.idle_add(lambda: (self.imp_btn.grab_focus(), False)[1])

    # ------------------------------------------------- cargar el proyecto de una base
    def on_load_project(self, db, inst):
        def got(rc, out):
            link, current, projects, saved, create = "", "", [], {}, False
            for f in parse_lines(out):
                if f[0] == "E" and len(f) >= 3:
                    link, current = f[1], f[2]
                    create = len(f) >= 4 and f[3] == "N"
                elif f[0] == "P" and len(f) >= 4:
                    projects.append({"name": f[1], "db": f[2], "php": f[3]})
                elif f[0] == "R" and len(f) >= 3:
                    saved[f[1]] = f[2]
            if rc != 0 or not projects:
                message(self.win, "No se han podido leer los proyectos",
                        "No se ha podido leer la carpeta /opt/htdocs.", Gtk.MessageType.WARNING)
            elif not link:
                message(self.win, "No hay un vhost para cargar proyectos",
                        "Ningún vhost de /opt/config/httpd-vhosts.conf tiene como DocumentRoot "
                        "un enlace de /opt/htdocs (como web.local).", Gtk.MessageType.WARNING)
            else:
                self.project_dialog(db, inst, link, current, projects, saved, create)
            return False
        run_quick(["gui-proyectos"], got)

    def project_dialog(self, db, inst, link, current, projects, saved, create=False):
        """Carga el proyecto de la base en la versión del resultado pulsado (inst). Si la carpeta
        se sabe (elegida antes o la única cuya configuración usa la base), sin preguntar; si no,
        se elige de una lista. Solo avisa cuando hay que cambiar de versión o crear el vhost."""
        by_name = {p["name"]: p for p in projects}
        matches = [p["name"] for p in projects if p["db"] == db]
        folder, manual = None, False
        if saved.get(db) in by_name:
            folder = saved[db]
        elif len(matches) == 1:
            folder = matches[0]
        else:
            folder = self.pick_project_folder(db, projects, matches)
            manual = True
        if not folder:
            return
        self.do_load_project(folder, db, inst, link, create, remember=manual)

    def do_load_project(self, folder, db, inst, link, create, confirm_switch=True, remember=False):
        """Carga una carpeta en una versión. Avisa cuando hay que cambiar de versión (si no se
        acaba de elegir) o crear el vhost."""
        target = inst["folder"]
        act = next((i for i in self.installs() if i["folder"] == self.data["active"]), None)
        where = (", donde está la BBDD %s" % db) if db and db in self.data["dbs"].get(target, []) \
            else ""
        notes = []
        if target != self.data["active"] and confirm_switch:
            if act:
                notes.append("Se va a cambiar de versión de PHP: se para lampp-%s (PHP %s) y se "
                             "activa lampp-%s (PHP %s)%s."
                             % (act["folder"], act["php"], target, inst["php"], where))
            else:
                notes.append("Se activa lampp-%s (PHP %s)%s." % (target, inst["php"], where))
        if create:
            notes.append("Todavía no hay un vhost para cargar proyectos: se crea %s (http y "
                         "https, con su certificado y su línea en /etc/hosts)." % link)
        if notes:
            title = "¿Cambiar a PHP %s?" % inst["php"] if target != self.data["active"] \
                and confirm_switch else "¿Crear %s?" % link
            if not confirm(self.win, title, "\n\n".join(notes) + "\n\n%s apuntará a %s. Se pide "
                           "la contraseña de sudo." % (link, folder), "Cargar proyecto"):
                return
        if remember:
            self.remember_project(db, folder)
        def loaded(ok_, *_):
            if not ok_:
                return

            def got(_rc, out):
                # Tienda PrestaShop: su dominio queda falseado (se ve en la pestaña Hosts)
                fake = [f[1] for f in parse_lines(out)
                        if f[0] == "F" and len(f) >= 9 and f[3] == folder and f[4] == "1"]
                self.on_hosts_data(_rc, out)
                self.toast("Proyecto cargado: %s → %s (PHP %s)%s"
                           % (link, folder, inst["php"],
                              "  ·  %s falseado (pestaña Hosts)" % fake[0] if fake else ""))
                return False
            run_quick(["gui-hosts"], got)
        self.run_task("Cargando el proyecto %s" % folder, ["cargar-proyecto", folder, target, db],
                      done_text="%s apunta a %s (PHP %s)" % (link, folder, inst["php"]),
                      auto_close=True, env=self.db_pwd.get(target) and
                      {"MYSQL_PWD": self.db_pwd[target]}, on_done=loaded)

    def pick_project_folder(self, db, projects, matches):
        """Lista con buscador de las carpetas de htdocs para elegir la del proyecto de una base."""
        dlg = Gtk.Dialog(title="Cargar proyecto", transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(560, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Cargar proyecto", Gtk.ResponseType.ACCEPT), "verde")
        ok.set_sensitive(False)
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        box.pack_start(css(label("Proyecto de %s" % db), "title-3"), False, False, 0)
        if len(matches) > 1:
            why = "Hay %d carpetas que usan «%s». Elige la que quieres cargar:" % (
                len(matches), db)
        else:
            why = ("No hay ninguna carpeta cuya configuración use «%s». Elige la del "
                   "proyecto:" % db)
        box.pack_start(label(why, "dim-label", wrap=True, max_width_chars=60), False, False, 0)
        box.pack_start(label("La elección se recuerda para esta BBDD.", "dim-label",
                             "subtitulo"), False, False, 0)
        find = Gtk.SearchEntry(placeholder_text="Buscar una carpeta de htdocs")
        box.pack_start(find, False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE,
                             activate_on_single_click=False), "caja")
        sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, min_content_height=260)
        sw.add(lb)
        box.pack_start(sw, False, False, 0)
        # Primero las que usan esta base, luego el resto por nombre
        for p in sorted(projects, key=lambda p: (p["db"] != db, p["name"].lower())):
            sub = ("Usa esta BBDD" if p["db"] == db else
                   "BBDD: %s" % p["db"] if p["db"] else "Sin BBDD detectada")
            if p["php"]:
                sub += "  ·  .php-version %s" % p["php"]
            row = ActionRow(p["name"], sub)
            row.set_selectable(True)
            row.set_activatable(True)
            row.name = p["name"]
            lb.add(row)
        lb.set_filter_func(lambda r: find.get_text().strip().lower() in r.name.lower())
        find.connect("search-changed", lambda *_: lb.invalidate_filter())
        lb.connect("row-selected", lambda _lb, row: ok.set_sensitive(row is not None))
        lb.connect("row-activated", lambda *_: dlg.response(Gtk.ResponseType.ACCEPT))
        box.show_all()
        find.grab_focus()
        resp = run_dialog(dlg)
        row = lb.get_selected_row()
        dlg.destroy()
        return row.name if resp == Gtk.ResponseType.ACCEPT and row is not None else None

    def remember_project(self, db, folder):
        """Guarda en ~/.lvm-instalador/proyectos la carpeta elegida a mano para una base."""
        lines = []
        try:
            with open(PROJECTS_FILE, encoding="utf-8") as f:
                lines = [l for l in f.read().splitlines() if l and not l.startswith(db + "=")]
        except OSError:
            pass
        lines.append("%s=%s" % (db, folder))
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            with open(PROJECTS_FILE, "w", encoding="utf-8") as f:
                f.write("\n".join(lines) + "\n")
        except OSError as exc:
            self.toast("No se ha podido recordar la carpeta: %s" % exc)

    # ------------------------------------------------- descargar una base de datos
    def on_download_db(self, db, folder):
        d = self.data
        inst = next((i for i in d["installs"] if i["folder"] == folder), None)
        if not inst:
            return
        act = next((i for i in d["installs"] if i["folder"] == d["active"]), None)
        running = bool(act) and d["running"] and act["owner"] == inst["owner"]
        dlg = Gtk.FileChooserDialog(title="Descargar la BBDD %s" % db,
                                    transient_for=self.win, action=Gtk.FileChooserAction.SAVE,
                                    do_overwrite_confirmation=True)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Descargar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        dlg.set_current_folder(
            GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD)
            or os.path.expanduser("~"))
        dlg.set_current_name("%s-lampp-%s-%s.zip" % (db, folder, time.strftime("%Y%m%d-%H%M")))
        if not running:
            dlg.set_extra_widget(label(
                "lampp-%s no está en marcha: se arranca un MariaDB temporal solo para la copia "
                "(pide la contraseña de sudo)." % folder, "dim-label", wrap=True,
                max_width_chars=60))
        path = dlg.get_filename() if run_dialog(dlg) == Gtk.ResponseType.ACCEPT else None
        dlg.destroy()
        if not path:
            return
        if not re.search(r"(?i)(\.sql(\.gz)?|\.zip)$", path):
            path += ".zip"

        def start(pwd):
            def done(ok, task, _p):
                if ok:
                    task.offer("Abrir la carpeta", lambda: self.open_uri(
                        GLib.filename_to_uri(os.path.dirname(path))))
            self.run_task("Descargando %s" % db, ["exportar-bd", db, path, folder],
                          env={"MYSQL_PWD": pwd} if pwd else None, on_done=done,
                          done_text="Copia de «%s» guardada: %s" % (db, os.path.basename(path)),
                          cancel_text=("¿Cancelar la descarga?",
                                       "No se guarda nada.", "Cancelar la descarga"))
        if running:
            self.check_db_access(start)
        else:
            start(None)

    # ------------------------------------------- subir o actualizar una base de datos
    def build_import(self):
        d = self.data
        act = next((i for i in d["installs"] if i["folder"] == d["active"]), None)
        if act and self.imp["folder"] != act["folder"]:
            # Otra version activa: sus bases son otras
            self.imp.update(db=None, folder=act["folder"])
        box, lb = group("Subir o actualizar una BBDD",
                        "Carga una copia .sql, .sql.gz o .zip en el MariaDB de la versión activa%s. "
                        "Antes se borran todas las tablas de la BBDD de destino (con una copia en "
                        "~/lvm-copias), para que no quede nada de lo anterior. Los .zip se "
                        "descomprimen solos."
                        % (", lampp-%s (MariaDB %s)" % (act["folder"], act["mariadb"])
                           if act else ""))
        if not act:
            lb.add(ActionRow("No hay ninguna versión activa",
                             "Activa una versión en la pestaña Versiones para cargar BBDD."))
            return box

        f = self.imp["file"]
        sub = "Ningún fichero elegido"
        if f:
            try:
                sub = "%s  ·  %s" % (os.path.basename(f), fmt_size(os.path.getsize(f)))
            except OSError:
                sub = "%s  ·  ya no existe" % os.path.basename(f)
        row = ActionRow("Fichero SQL", sub)
        if f:
            row.set_tooltip_text(f)
        b = Gtk.Button(label="Elegir…")
        b.connect("clicked", self.on_pick_sql)
        row.add_suffix(b)
        lb.add(row)

        row = ActionRow("BBDD de destino", "En lampp-%s" % act["folder"])
        combo = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
        for db in d["dbs"].get(act["folder"], []):
            combo.append(db, db)
        if self.imp["db"]:
            combo.set_active_id(self.imp["db"])
        if combo.get_active_id() is None:
            self.imp["db"] = None
            combo.append("@ninguna", "Elige una BBDD")
            combo.set_active_id("@ninguna")
        combo.connect("changed", self.on_pick_db)
        row.add_suffix(combo)
        b = Gtk.Button(tooltip_text="Crear una BBDD nueva", valign=Gtk.Align.CENTER)
        b.add(icon("list-add-symbolic"))
        b.connect("clicked", self.on_create_db)
        row.add_suffix(b)
        self.imp_drop_btn = Gtk.Button(tooltip_text="Borrar la BBDD elegida",
                                       valign=Gtk.Align.CENTER, sensitive=bool(self.imp["db"]))
        self.imp_drop_btn.add(icon("user-trash-symbolic"))
        self.imp_drop_btn.connect("clicked", lambda *_: self.on_drop_db(self.imp["db"]))
        row.add_suffix(self.imp_drop_btn)
        lb.add(row)

        # Proyecto de la base: queda como su base y, si es un WordPress, su wp-config.php la usa
        folders = project_folders()
        if self.imp.get("project") not in folders:
            self.imp["project"] = None
        # La primera vez con esta base se propone su proyecto; luego se respeta lo elegido
        if self.imp["db"] and self.imp.get("project_for") != self.imp["db"]:
            self.imp["project"] = guess_project(self.imp["db"]) or self.imp["project"]
            self.imp["project_for"] = self.imp["db"]
        self.imp_proj_row = ActionRow("Proyecto", self.import_project_hint())
        # Ancho del nombre más largo (hasta 56 letras), para verlo entero al elegirlo
        combo = narrow(Gtk.ComboBoxText(valign=Gtk.Align.CENTER),
                       min(56, max([COMBO_CHARS] + [len(n) for n in folders])))
        combo.append("@ninguno", "Ninguno")
        for name in folders:
            combo.append(name, name)
        combo.set_active_id(self.imp["project"] or "@ninguno")
        combo.connect("changed", self.on_pick_project)
        self.imp_proj_combo = combo
        self.imp_proj_row.add_suffix(combo)
        lb.add(self.imp_proj_row)

        self.imp_btn = css(Gtk.Button(label="Cargar", halign=Gtk.Align.CENTER, margin_top=6),
                           "verde", "pildora")
        self.imp_btn.connect("clicked", self.on_import)
        box.pack_start(self.imp_btn, False, False, 0)
        self.imp_hint = label("", "dim-label", xalign=0.5)
        box.pack_start(self.imp_hint, False, False, 0)
        self.update_import_button()
        return box

    def update_import_button(self):
        db = self.imp["db"]
        hint = ""
        if not self.data["running"]:
            hint = "La versión activa está parada: arráncala en la pestaña Versiones."
        elif not self.imp["file"]:
            hint = "Elige el fichero SQL."
        elif not db:
            hint = "Elige la BBDD de destino o crea una con +."
        self.imp_btn.set_sensitive(not hint and not self.busy)
        self.imp_hint.set_label(hint)
        self.imp_hint.set_visible(bool(hint))

    def on_pick_sql(self, *_):
        dlg = Gtk.FileChooserDialog(title="Elegir el fichero SQL", transient_for=self.win,
                                    action=Gtk.FileChooserAction.OPEN)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Elegir", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        flt = Gtk.FileFilter()
        flt.set_name("Copias SQL (.sql, .sql.gz, .zip)")
        for pat in ("*.sql", "*.SQL", "*.sql.gz", "*.SQL.GZ", "*.zip", "*.ZIP"):
            flt.add_pattern(pat)
        dlg.add_filter(flt)
        flt = Gtk.FileFilter()
        flt.set_name("Todos los ficheros")
        flt.add_pattern("*")
        dlg.add_filter(flt)
        start = os.path.dirname(self.imp["file"]) if self.imp["file"] else \
            GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD) or os.path.expanduser("~")
        dlg.set_current_folder(start)
        if run_dialog(dlg) == Gtk.ResponseType.ACCEPT:
            path = dlg.get_filename()
            self.imp["file"] = path
            # Si hay una base que se llama como el fichero (mi_web.sql → mi_web), se propone
            stem = re.sub(r"(?i)(\.sql)?(\.gz|\.zip)?$", "", os.path.basename(path))
            if not self.imp["db"] and stem in self.data["dbs"].get(self.data["active"], []):
                self.imp["db"] = stem
                self.imp["project"] = guess_project(stem) or self.imp.get("project")
                self.imp["project_for"] = stem
            elif stem not in self.data["dbs"].get(self.data["active"], []):
                others = self.db_installs(stem)
                if others:
                    self.toast("«%s» está en %s, no en la versión activa" % (
                        stem, ", ".join("lampp-%s" % i["folder"] for i in others)))
        dlg.destroy()
        self.build_databases()

    def import_project_hint(self):
        folder = self.imp.get("project")
        if not folder:
            return "Opcional: si es la BBDD nueva de un proyecto, elige su carpeta."
        what = PROJECT_CONFIG_TEXT.get(project_kind(folder))
        if what:
            return what[:1].upper() + what[1:] + "."
        return "La BBDD queda asociada a esta carpeta (Cargar proyecto la usa)."

    def on_pick_project(self, combo):
        folder = combo.get_active_id()
        self.imp["project"] = None if folder in (None, "@ninguno") else folder
        self.imp["project_for"] = self.imp["db"]
        self.imp_proj_row.subtitle.set_label(self.import_project_hint())

    def on_pick_db(self, combo):
        db = combo.get_active_id()
        if db == "@ninguna":
            return
        self.imp["db"] = db
        guess = guess_project(db)
        if guess:
            self.imp_proj_combo.set_active_id(guess)
        self.imp["project_for"] = db
        self.imp_drop_btn.set_sensitive(True)
        self.update_import_button()

    def on_import(self, *_):
        db = self.imp["db"]
        path, folder = self.imp["file"], self.data["active"]
        try:
            size = fmt_size(os.path.getsize(path))
        except OSError:
            message(self.win, "No se encuentra el fichero", path, Gtk.MessageType.ERROR)
            return
        text = "Se carga en el MariaDB de lampp-%s. " % folder
        act = next((i for i in self.installs() if i["folder"] == folder), None)
        others = self.db_installs(db, skip_owner=act["owner"] if act else None)
        title = "¿Cargar %s (%s) en %s?" % (os.path.basename(path), size, db)
        ok_label = "Vaciar y cargar"
        if others:
            where = ", ".join("lampp-%s (PHP %s)" % (i["folder"], i["php"]) for i in others)
            title = "«%s» ya existe en %s" % (db, where)
            text = ("¿Quieres introducirla también en lampp-%s%s, la versión activa? Cada versión "
                    "tiene su propio MariaDB: la de %s no se toca.\n\n"
                    % (folder, " (PHP %s)" % act["php"] if act else "", where)
                    + "Fichero: %s (%s).\n\n" % (os.path.basename(path), size))
            ok_label = "Cargar también en lampp-%s" % folder
        text += ("Antes se BORRAN todas las tablas de «%s», para que no quede nada de lo "
                 "anterior. Si tiene alguna, primero se guarda una copia en ~/lvm-copias." % db)
        project = self.imp.get("project")
        if project:
            what = PROJECT_CONFIG_TEXT.get(project_kind(project))
            text += "\n\nDespués, «%s» pasa a ser la BBDD de %s%s." % (
                db, project, ": " + what if what else "")
        if not confirm(self.win, title, text, ok_label, destructive=True):
            return
        self.check_db_access(lambda pwd: self.start_import(path, db, pwd, project))

    # crear y borrar bases de datos (siempre en la version activa)
    def db_env(self):
        pwd = self.db_pwd.get(self.data["active"])
        return {"MYSQL_PWD": pwd} if pwd else None

    def on_create_db(self, *_):
        self.check_db_access(lambda _pwd: self.ask_new_db())

    def ask_new_db(self):
        folder = self.data["active"]
        existing = self.data["dbs"].get(folder, [])
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.QUESTION,
                                buttons=Gtk.ButtonsType.NONE, text="Crear BBDD")
        dlg.format_secondary_text("Se crea vacía en el MariaDB de lampp-%s, con juego de "
                                  "caracteres utf8mb4 (utf8mb4_general_ci)." % folder)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        entry = Gtk.Entry(placeholder_text="nombre_de_la_base", max_length=64,
                          activates_default=True)
        box.pack_start(entry, False, False, 0)
        hint = label("Letras sin acentos, números, _ y -", "dim-label", wrap=True,
                     max_width_chars=50)
        box.pack_start(hint, False, False, 0)
        dlg.get_message_area().pack_start(box, False, False, 0)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Crear", Gtk.ResponseType.ACCEPT), "verde")
        ok.set_sensitive(False)
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)

        def update(*_):
            name = entry.get_text().strip()
            valid = bool(re.match(r"^[A-Za-z0-9_-]{1,64}$", name))
            taken = name in existing or name.lower() in (
                "information_schema", "mysql", "performance_schema", "phpmyadmin", "sys", "test")
            act = next((i for i in self.installs() if i["folder"] == folder), None)
            others = [] if taken or not valid else \
                self.db_installs(name, skip_owner=act["owner"] if act else None)
            if taken:
                hint.set_label("Ya hay una BBDD con ese nombre.")
            elif others:
                hint.set_label("Ya existe en %s. Si sigues, se crea también en lampp-%s."
                               % (", ".join("lampp-%s (PHP %s)" % (i["folder"], i["php"])
                                            for i in others), folder))
            else:
                hint.set_label("Letras sin acentos, números, _ y -")
            ctx = hint.get_style_context()
            (ctx.add_class if taken or (name and not valid) else ctx.remove_class)("error")
            (ctx.add_class if others else ctx.remove_class)("aviso")
            ok.set_sensitive(valid and not taken)
        entry.connect("changed", update)
        dlg.show_all()
        resp = run_dialog(dlg)
        name = entry.get_text().strip()
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return

        def created(rc, out):
            if rc == 0:
                self.imp.update(db=name)
                self.toast("BBDD «%s» creada" % name)
                self.reload()
            else:
                message(self.win, "No se ha podido crear la BBDD", out.strip()[-600:],
                        Gtk.MessageType.ERROR)
            return False
        run_quick(["crear-bd", name], created, env=self.db_env())

    def on_drop_db(self, db):
        if not db:
            return

        def info(rc, out):
            res = [f for f in parse_lines(out) if f[0] == "I"]
            if rc != 0 or not res:
                message(self.win, "No se puede borrar la BBDD", out.strip()[-600:],
                        Gtk.MessageType.ERROR)
            else:
                self.confirm_drop(db, int(res[0][1]), int(res[0][2]))
            return False
        self.check_db_access(lambda _pwd: run_quick(["gui-bd-info", db], info,
                                                    env=self.db_env()))

    def confirm_drop(self, db, tables, size):
        folder = self.data["active"]
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.WARNING,
                                buttons=Gtk.ButtonsType.NONE,
                                text="¿Borrar la BBDD «%s»?" % db)
        state = {"copy": tables > 0}
        if tables:
            dlg.format_secondary_markup(
                "Está en el MariaDB de lampp-%s y tiene <b>%s</b> (%s).\n\n"
                "<b>Se eliminará todo su contenido. Esta acción es irreversible: "
                "no se puede deshacer.</b>"
                % (folder, plural(tables, "tabla", "tablas"), fmt_size(size)))
        else:
            dlg.format_secondary_text("Está en el MariaDB de lampp-%s y está vacía (no tiene "
                                      "tablas). Esta acción no se puede deshacer." % folder)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Borrar", Gtk.ResponseType.ACCEPT), "destructive-action")
        dlg.set_default_response(Gtk.ResponseType.CANCEL)
        if tables:
            extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            copy = Gtk.CheckButton(label="Guardar antes una copia en ~/lvm-copias "
                                         "(se puede volver a cargar)", active=True)
            extra.pack_start(copy, False, False, 0)
            warn = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            warn.pack_start(label("Sin copia, el contenido no se podrá recuperar. "
                                  "Escribe %s para confirmar:" % db, "error", wrap=True,
                                  max_width_chars=50), False, False, 0)
            entry = Gtk.Entry()
            warn.pack_start(entry, False, False, 0)
            extra.pack_start(warn, False, False, 0)
            dlg.get_message_area().pack_start(extra, False, False, 0)

            def update(*_):
                state["copy"] = copy.get_active()
                warn.set_visible(not state["copy"])
                ok.set_sensitive(state["copy"] or entry.get_text().strip() == db)
            copy.connect("toggled", update)
            entry.connect("changed", update)
            dlg.show_all()
            update()
        else:
            dlg.show_all()
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return

        def done(ok_, _task, _p):
            if ok_ and self.imp["db"] == db:
                self.imp.update(db=None)
        self.run_task("Borrando la BBDD %s" % db,
                      ["borrar-bd", db] + (["--copia"] if state["copy"] else []),
                      env=self.db_env(), on_done=done, auto_close=True,
                      done_text="BBDD «%s» borrada" % db
                      + (" (copia en ~/lvm-copias)" if state["copy"] else ""))

    def check_db_access(self, then, retry=False):
        """Comprueba que se puede entrar en el MariaDB activo; si root tiene contraseña la pide."""
        folder = self.data["active"]
        pwd = self.db_pwd.get(folder)
        self.imp_btn.set_sensitive(False)

        def checked(_rc, out):
            self.update_import_button()
            res = (out.strip().splitlines() or ["no|Sin respuesta"])[-1].split("|")
            if res[0] == "ok":
                then(pwd)
            elif res[0] == "clave":
                new = self.ask_db_password(folder, retry=pwd is not None)
                if new is not None:
                    self.db_pwd[folder] = new
                    self.check_db_access(then, retry=True)
            else:
                message(self.win, "No se puede entrar en MariaDB", "|".join(res[1:]),
                        Gtk.MessageType.ERROR)
            return False
        run_quick(["gui-bd-comprobar"], checked, env={"MYSQL_PWD": pwd} if pwd else None)

    def ask_db_password(self, folder, retry=False):
        dlg = Gtk.Dialog(title="Contraseña de MariaDB", transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Continuar", Gtk.ResponseType.OK), "verde")
        dlg.set_default_response(Gtk.ResponseType.OK)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=20)
        box.pack_start(icon("dialog-password-symbolic", 48), False, False, 0)
        box.pack_start(label("El usuario root del MariaDB de lampp-%s tiene contraseña.\n"
                             "Escríbela para continuar." % folder,
                             xalign=0.5, justify=Gtk.Justification.CENTER), False, False, 0)
        if retry:
            box.pack_start(label("Contraseña incorrecta. Vuelve a intentarlo.", "error",
                                 xalign=0.5), False, False, 0)
        entry = Gtk.Entry(visibility=False, activates_default=True,
                          input_purpose=Gtk.InputPurpose.PASSWORD)
        box.pack_start(entry, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.show_all()
        resp = run_dialog(dlg)
        pwd = entry.get_text()
        dlg.destroy()
        return pwd if resp == Gtk.ResponseType.OK else None

    def start_import(self, path, db, pwd, project=None):
        args = ["importar-bd", path, db] + (["--proyecto", project] if project else [])

        def done(ok, _task, _p):
            if ok:
                self.imp.update(file=None, db=db)

        self.run_task("Cargando %s en %s" % (os.path.basename(path), db), args, progress=True,
                      on_done=done, done_text="BBDD «%s» cargada" % db
                      + (" en %s" % project if project else ""),
                      env={"MYSQL_PWD": pwd} if pwd else None,
                      cancel_text=("¿Cancelar la carga?",
                                   "La BBDD «%s» se queda a medias: tendrá lo que se haya "
                                   "cargado hasta ahora." % db, "Cancelar la carga"))

    # -------------------------------------------------------------- acerca
    def on_about(self, *_):
        d = self.data or {}
        about = Gtk.AboutDialog(
            transient_for=self.win, modal=True, program_name=d.get("name", ""),
            version=d.get("version", ""), logo_icon_name=self.icon,
            copyright="%s\n© %d" % (d.get("signature", ""), time.localtime().tm_year),
            comments="Gestor de paquetes Apache, MariaDB, PHP, Perl, phpMyAdmin y ProFTPD "
                     "al estilo XAMPP de forma independiente.")
        about.set_default_size(560, -1)
        about.run()
        about.destroy()

    def on_commands(self, *_):
        """Ayuda: los comandos de lvm-instalador (lo mismo que lvm-instalador --ayuda)."""
        def show(_rc, out):
            dlg = Gtk.Dialog(title="Comandos de lvm-instalador", transient_for=self.win,
                             modal=True, use_header_bar=True)
            dlg.set_default_size(860, 700)
            hb = dlg.get_header_bar()
            hb.set_subtitle("En la terminal: lvm-instalador --ayuda")
            copy = Gtk.Button(label="Copiar todo")
            copy.connect("clicked", lambda *_: (
                Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(out, -1),
                self.toast("Copiado al portapapeles")))
            hb.pack_start(copy)
            tv = css(Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                                  left_margin=16, right_margin=16, top_margin=12,
                                  bottom_margin=12), "log")
            # Cada sección («=== TÍTULO ===») en verde y grande, y cada orden en negrita: se
            # distinguen de su explicación (con sangría, debajo)
            buf = tv.get_buffer()
            buf.set_text(out)
            buf.create_tag("seccion", weight=700, scale=1.15, foreground=GREEN, pixels_above_lines=10,
                           pixels_below_lines=4)
            buf.create_tag("orden", weight=700, pixels_above_lines=4)
            for n, line in enumerate(out.split("\n")):
                tag = "seccion" if line.startswith("=== ") else \
                    "orden" if line.startswith("  lvm-instalador") else None
                if tag:
                    start = buf.get_iter_at_line(n)
                    end = start.copy()
                    end.forward_to_line_end()
                    buf.apply_tag_by_name(tag, start, end)
            sw = Gtk.ScrolledWindow(vexpand=True)
            sw.add(tv)
            dlg.get_content_area().add(sw)
            dlg.show_all()
            run_dialog(dlg)
            dlg.destroy()
            return False
        run_quick(["--ayuda"], show)

    def on_changes(self, *_):
        def show(_rc, out):
            dlg = Gtk.Dialog(title="Novedades", transient_for=self.win, modal=True,
                             use_header_bar=True)
            dlg.set_default_size(780, 680)
            tv = Gtk.TextView(editable=False, cursor_visible=False, wrap_mode=Gtk.WrapMode.WORD_CHAR,
                              left_margin=24, right_margin=24, top_margin=8, bottom_margin=24)
            markdown_to_buffer(tv.get_buffer(), out)
            sw = Gtk.ScrolledWindow(vexpand=True)
            sw.add(tv)
            dlg.get_content_area().add(sw)
            dlg.show_all()
            run_dialog(dlg)
            dlg.destroy()
            return False
        run_quick(["novedades"], show)

    # ----------------------------------------- capturas (solo para revisar la ventana)
    def capture(self, widget, name):
        import cairo
        widget.check_resize()
        w, h = widget.get_allocated_width(), widget.get_allocated_height()
        surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
        cr = cairo.Context(surf)
        Gtk.render_background(widget.get_style_context(), cr, 0, 0, w, h)
        widget.draw(cr)
        surf.write_to_png(os.path.join(os.environ["LVM_CAPTURA"], name + ".png"))

    def capture_all(self):
        steps = [(lambda: None, "1-versiones"), (lambda: self.show_tab("bbdd"), "3-bbdd"),
                 (lambda: self.show_tab("servicios"), None), (lambda: None, "6-servicios"),
                 (lambda: self.show_tab("hosts"), None), (lambda: None, "5-hosts"),
                 (lambda: self.show_tab("herramientas"), None), (lambda: None, "4-herramientas"),
                 (lambda: self.quit(), None)]

        def step(i=[0]):
            fn, shot = steps[i[0]]
            fn()
            if shot:
                GLib.timeout_add(1500, lambda: (self.capture(self.win, shot), False)[1])
            i[0] += 1
            return i[0] < len(steps)
        GLib.timeout_add(2500, step)
        return False


if __name__ == "__main__":
    # Nadie con tu usuario puede leer la memoria de la ventana (donde pasa la contraseña) ni
    # engancharse a ella (PR_SET_DUMPABLE = 0)
    try:
        import ctypes
        ctypes.CDLL(None).prctl(4, 0, 0, 0, 0)
    except (OSError, AttributeError):
        pass
    # Mismo identificador que StartupWMClass del acceso: asi el dock agrupa la ventana con su icono
    GLib.set_prgname(APP_ID)
    Gdk.set_program_class(APP_ID)
    sys.exit(App().run([sys.argv[0]]))
LVM_GUI_PY
}

# ===========================================================================
# Linea de comandos
# ===========================================================================

function cli_install() {
    local xampp="" php="" yes=0 selected="" b full branch

    while [ -n "$1" ]; do
        case "$1" in
            --xampp) xampp=${2//,/ }; shift 2 ;;
            --php) php=${2//,/ }; shift 2 ;;
            --base) echo "Aviso: --base ya no se usa (las versiones de PHP tienen su pila propia)"; shift 2 ;;
            --si|--yes|-y) yes=1; shift ;;
            *) echo "Opcion desconocida: $1"; return 1 ;;
        esac
    done

    for b in $xampp; do
        catalog_entry "$b" > /dev/null || { echo "XAMPP $b no esta en el catalogo"; return 1; }
        [ -e "/opt/lampp-$b" ] && echo "lampp-$b ya existe, se omite" && continue
        selected+=" xampp:$b"
    done

    if [ -n "$php" ]; then
        local releases=$(php_releases)

        # 8.4 = ultimo parche de la rama; 8.4.10 = ese parche concreto
        local item latest
        for branch in $php; do
            if [[ "$branch" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                full=$branch
                latest=$(awk -v b="${full%.*}" '$1 == b {print $2}' <<< "$releases")
                if [ -z "$latest" ] || ! php_patches "${full%.*}" | awk -v v="$full" '$1 == v {f = 1} END {exit !f}'; then
                    echo "PHP $full no esta publicada en php.net o su rama no se ofrece, se omite"
                    continue
                fi
                item=$(php_item "$full" "$latest")
            else
                full=$(awk -v b="$branch" '$1 == b {print $2}' <<< "$releases")
                [ -z "$full" ] && echo "PHP $branch no esta disponible en php.net, se omite" && continue
                if is_fpm_install "${TEST_DIR:-/opt}/lampp-$branch"; then
                    echo "lampp-$branch ya existe, se omite (para ponerla al dia: lvm-instalador actualizar $branch)"
                    continue
                fi
                item=$(php_item "$full" "$full")
            fi
            [ -e "${TEST_DIR:-/opt}/lampp-$(item_folder "$item")" ] && echo "lampp-$(item_folder "$item") ya existe, se omite" && continue
            local have=$(php_installed_in "$full")
            [ -n "$have" ] && echo "PHP $full ya esta instalada en $have, se omite" && continue
            selected+=" $item"
        done
    fi

    [ -z "$selected" ] && echo "No hay nada que instalar." && return 0

    echo "Se va a instalar:$selected"

    if [ $yes -ne 1 ]; then
        read -p "¿Continuar? [s/N]: " answer
        [[ "$answer" =~ ^[sSyY]$ ]] || return 0
    fi

    UI=text
    install_plan "$selected"
}

function cli_rebuild() {
    local version=$1
    local dir=${TEST_DIR:-/opt}/lampp-$version

    if [ -z "$version" ] || ! is_fpm_install "$dir"; then
        echo "lampp-$version no existe o no es una version de PHP nueva (los XAMPP no se rehacen)"

        return 1
    fi

    # Una version con un parche concreto (lampp-8.3.10) se queda en ese parche
    local php=$(stack_fields "$dir" | cut -d'|' -f1)
    if [ "$version" != "${php%.*}" ]; then
        echo "lampp-$version tiene un parche concreto de PHP y no se actualiza. Si necesitas otro, instalalo aparte."

        return 1
    fi

    local full=$(rebuild_version "$dir" "$(php_releases)")
    if [ -z "$full" ]; then
        echo "No se encuentra en php.net la ultima version de la rama de lampp-$version"

        return 1
    fi

    if is_stack_install "$dir" && [ "$(stack_fields "$dir")" == "$(stack_versions "$full")" ]; then
        if [ -t 1 ]; then
            echo -e "\033[1;32mEl paquete lampp-$version se encuentra actualizado.\033[0m No hay nada que actualizar."
        else
            echo "El paquete lampp-$version se encuentra actualizado. No hay nada que actualizar."
        fi

        return 0
    fi

    UI=text
    install_plan "rehacer:$full"
}

if [ "$1" == "--simular" ]; then
    DRY=1
    shift
fi

for cmd in curl python3; do
    command -v $cmd > /dev/null || { echo "Falta el comando $cmd. Instalalo con: sudo apt install $cmd"; exit 1; }
done

# Copias de bases, configuraciones de proyectos y registros: solo para tu usuario
for dir in "$HOME/lvm-copias" "$LOG_DIR"; do
    if [ -d "$dir" ] && [ -O "$dir" ] && [ ! -L "$dir" ]; then
        chmod 700 "$dir" 2> /dev/null
        find "$dir" -maxdepth 2 -type f -user "$(id -u)" -perm /077 -exec chmod go-rwx {} + 2> /dev/null
    fi
done


# ===========================================================================
# phpMyAdmin: actualizar el de una version
# ===========================================================================
# phpMyAdmin que admite cada PHP: la 5.2 (la ultima) desde PHP 7.2.5, la 5.1.4 desde la 7.1.3 y la
# 4.9.11 antes. Los XAMPP traen la 4.9.2, 5.2.0 o 5.2.1, con fallos de seguridad corregidos despues.
function pma_for_php() {
    local php=$1
    if [ "$(printf '%s\n%s\n' 7.2.5 "$php" | sort -V | head -1)" == 7.2.5 ]; then
        latest_pma
    elif [ "$(printf '%s\n%s\n' 7.1.3 "$php" | sort -V | head -1)" == 7.1.3 ]; then
        echo 5.1.4
    else
        echo 4.9.11
    fi
}

# Huella sha256 del phpMyAdmin <version>: las que pone el gestor van fijadas aqui; otra, la que
# publica phpMyAdmin (del mismo servidor que el fichero: solo protege de descargas a medias)
function pma_sum() {
    case $1 in
        5.2.3) echo 57881348297c4412f86c410547cf76b4d8a236574dd2c6b7d6a2beebe7fc44e3 ;;
        5.1.4) echo 3230cf0e004b6284c70e0cb26064a8666b271749ef54236d035104a972822999 ;;
        4.9.11) echo 2b14737a2220e5ac9d2eaf683df6b56ebaa490d038ee980367cb4db909a57923 ;;
        *) curl -q --proto =https --proto-redir =https -fsSL "https://files.phpmyadmin.net/phpMyAdmin/$1/phpMyAdmin-$1-all-languages.tar.xz.sha256" 2> /dev/null | grep -oE '^[0-9a-f]{64}' ;;
    esac
}

# Version de phpMyAdmin instalada en <carpeta de phpmyadmin> (vacio si no se sabe)
function pma_installed() {
    local v
    v=$(grep -hoE "(VERSION = |PMA_VERSION', )'[0-9.]+'" "$1/libraries/classes/Version.php" \
        "$1/libraries/classes/Config.php" "$1/libraries/Config.php" 2> /dev/null | head -1 | grep -oE "[0-9][0-9.]+")
    [ -z "$v" ] && v=$(grep -rhoE "(VERSION = |PMA_VERSION', )'[0-9.]+'" "$1/libraries" 2> /dev/null | head -1 | grep -oE "[0-9][0-9.]+")
    echo "$v"
}

# actualizar-phpmyadmin <version>: pone el phpMyAdmin mas nuevo que admite su PHP (comprobado con su
# sha256), con la configuracion de antes (config.inc.php) y una clave de cookies nueva si la de
# XAMPP es la de fabrica. El anterior queda en phpmyadmin.anterior.
function update_pma() {
    local FETCH_FRESH=1
    local version=$1 root dir php cur want tmp sum new grp d rc=0
    if [ "$version" == "--todas" ]; then
        for d in $(lampp_dirs); do
            [ -f "$d/phpmyadmin/config.inc.php" ] || continue
            update_pma "${d#/opt/lampp-}" || rc=1
        done
        return $rc
    fi
    valid_version_name "$version" && [ -d "/opt/lampp-$version" ] \
        || { echo "No existe la version $version de lampp en el sistema"; return 1; }
    root="/opt/lampp-$version"
    dir=$root/phpmyadmin
    if [ ! -f "$dir/config.inc.php" ]; then
        echo "$version no tiene phpMyAdmin con su configuracion ($dir/config.inc.php)"
        return 1
    fi
    php=$(php_version "$root")
    cur=$(pma_installed "$dir")
    want=$(pma_for_php "$php")
    [[ "$want" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || { echo "No se ha podido saber que phpMyAdmin poner"; return 1; }
    if [ -n "$cur" ] && [ "$(printf '%s\n%s\n' "$want" "$cur" | sort -V | tail -1)" == "$cur" ]; then
        echo "phpMyAdmin de $version ya esta al dia ($cur, PHP $php)"
        return 0
    fi
    echo "phpMyAdmin de $version: ${cur:-version antigua} -> $want (PHP $php)"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] descarga, comprobacion sha256 y cambio de $dir (el anterior en phpmyadmin.anterior)"
        return 0
    fi
    # Antes de cambiar nada como root: la carpeta de la version tiene que ser de root (y en
    # Linux, /opt tambien), no un enlace que lleve a otro sitio
    vhosts_root > /dev/null
    if [ -L "$root" ] || [ -L "$dir" ] || [ "$(stat -c %u /opt)" != 0 ] || [ "$(stat -c %u "$root")" != 0 ]; then
        echo "No se cambia phpMyAdmin: /opt o $root no son del administrador (lvm-instalador asegurar --todas)"
        return 1
    fi
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-pma.XXXXXX") || return 1
    sum=$(pma_sum "$want")
    if ! download "https://files.phpmyadmin.net/phpMyAdmin/$want/phpMyAdmin-$want-all-languages.tar.xz" "$tmp/pma.tar.xz" "$sum" \
            || ! tar -xJf "$tmp/pma.tar.xz" -C "$tmp"; then
        rm -rf "$tmp"
        return 1
    fi
    new=$tmp/phpMyAdmin-$want-all-languages
    [ -d "$new" ] || { rm -rf "$tmp"; echo "El paquete de phpMyAdmin no es el esperado"; return 1; }
    # La configuracion de antes; la clave de las cookies de XAMPP es la misma en todos (xampp)
    cp "$dir/config.inc.php" "$new/config.inc.php" || { rm -rf "$tmp"; return 1; }
    python3 -I - "$new/config.inc.php" <<'PY'
import re, secrets, string, sys
path = sys.argv[1]
text = open(path, encoding="utf-8", errors="surrogateescape").read()
m = re.search(r"""\$cfg\[\s*['"]blowfish_secret['"]\s*\]\s*=\s*(['"])(.*?)\1""", text)
if m is None or len(m.group(2)) < 32:
    key = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32))
    assign = "$cfg['blowfish_secret'] = '%s'" % key
    if m:
        text = text[:m.start()] + assign + text[m.end():]
    else:
        text = text.rstrip() + "\n" + assign + "; /* lvm-instalador */\n"
    open(path, "w", encoding="utf-8", errors="surrogateescape").write(text)
PY
    grp=$(stat -c %G "$dir/tmp" 2> /dev/null || echo root)
    # phpMyAdmin no trae enlaces: uno en la carpeta (que es tuya hasta que root la copia) seria de
    # otro programa. Se mira otra vez en la copia, ya de root, y tmp la crea root vacia (si fuera un
    # enlace, root cambiaria el dueño y los permisos de lo que apunta)
    if [ -n "$(find "$new" \( -type l -o -type f -links +1 \) -print -quit)" ]; then
        rm -rf "$tmp"
        echo "El phpMyAdmin descargado tiene enlaces (no deberia): no se cambia nada"
        return 1
    fi
    if ! { sudo rm -rf "$root/phpmyadmin.anterior" && sudo mv "$dir" "$root/phpmyadmin.anterior"; }; then
        echo "No se ha podido apartar $dir: no se cambia nada"
        rm -rf "$tmp"
        return 1
    fi
    if ! { sudo cp -R "$new" "$dir" \
            && [ -z "$(sudo find "$dir" -type l -print -quit)" ] \
            && sudo chown -R root:root "$dir" \
            && sudo chmod -R go-w "$dir" \
            && sudo rm -rf "$dir/tmp" \
            && sudo install -d -o 0 -g "$grp" -m 775 "$dir/tmp"; }; then
        sudo rm -rf "$dir" && sudo mv "$root/phpmyadmin.anterior" "$dir"
        echo "No se ha podido cambiar $dir: se ha dejado el phpMyAdmin anterior"
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    if [ "$(active_dir)" == "/opt/lampp-$version" ] && [ -f /opt/lampp/logs/httpd.pid ]; then
        run sudo /opt/lampp/lampp reloadapache > /dev/null
    fi
    echo "phpMyAdmin $want instalado en $version"
}

case "$1" in
    "")
        # Abierto desde un acceso del menu de una version anterior (1.8 o antes abrian el panel en
        # GNOME Terminal, y GNOME puede seguir lanzando esa orden de su cache aunque el acceso ya
        # este al dia): si hay ventana, se abre la ventana y se cierra la terminal
        if [ "$DRY" -eq 0 ] && [ "$(ps -o sid= -p $$ 2> /dev/null | tr -d ' ')" == "$$" ] \
            && { [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; } && gui_available; then
            update_launchers
            setsid "$SELF" ventana < /dev/null > /dev/null 2>&1 &
            exit 0
        fi
        panel
        ;;
    instalar|instalador|install|panel)
        shift
        if [ $# -eq 0 ]; then
            offer_command_install
            panel_install
            [ "$UI" == "whiptail" ] && clear
        else
            cli_install "$@"
        fi
        ;;
    use) use_lampp "$2" ;;
    list) list_lampp ;;
    list-db) list_databases ;;
    status|estado) echo -e "$(status_text)" ;;
    disable) disable_lampp ;;
    remove|desinstalar) cli_remove "$2" "$3" ;;
    ventana|gui) gui_open ;;
    arrancar|start) control_lampp start ;;
    parar|stop) control_lampp stop ;;
    reiniciar|restart) control_lampp restart ;;
    gui-datos) gui_data ;;
    gui-paquete) gui_package ;;
    gui-ramas) gui_branches ;;
    gui-parches) gui_patches "$2" ;;
    gui-al-dia) gui_up_to_date "$2" ;;
    gui-crear-acceso) write_launcher ;;
    gui-bd-comprobar) gui_db_check ;;
    importar-bd) import_database "$2" "$3" "${@:4}" ;;
    crear-bd) create_database "$2" ;;
    borrar-bd) drop_database "$2" "$3" ;;
    exportar-bd|descargar-bd) export_database "$2" "$3" "$4" ;;
    copiar-bd) copy_database "$2" "$3" "$4" "$5" ;;
    gui-bd-info) gui_db_info "$2" ;;
    gui-proyectos) gui_projects ;;
    cargar-proyecto) load_project "$2" "$3" "$4" ;;
    desmontar-proyecto) unload_project ;;
    usuario-pruebas) test_admin "$2" "$3" ;;
    montar-proyecto) mount_project "$2" "$3" "$4" "$5" "$6" ;;
    vaciar-cache)
        if [ "$2" == "--bd" ]; then ps_clear_cache_db "$3"; else ps_clear_cache "$2"; fi
        ;;
    wp-config) wp_config "$2" "$3" ;;
    gui-hosts) gui_hosts ;;
    gui-servicios) gui_services ;;
    servicio) service_control "$2" "$3" ;;
    asegurar) secure_command "$2" ;;
    reparar-bd-sistema) repair_db_system ;;
    arreglar-certificados) fix_certs ;;
    confiar-certificados) browser_trust "$2" ;;
    actualizar-phpmyadmin) update_pma "$2" ;;
    cerrar-procesos) close_processes "$2" ;;
    procesos) lampp_processes | awk -F'|' '{ printf "%-8s %-8s %-12s %-10s %s\n", $2, $3, $4, ($5 == "?" ? "anterior" : $5), $7 ($6 == 1 ? "  <- sobra" : "") }' ;;
    hosts-falsear) hosts_fake_one "$2" "$3" ;;
    hosts-enlace) hosts_fix_link ;;
    nuevo-dominio) new_custom_domain "$2" "$3" "$4" ;;
    vhosts|editar-vhosts) edit_vhosts "$2" ;;
    hosts|editar-hosts) edit_hosts "$2" "$3" ;;
    add) register_lampp "$2" ;;
    add-php) UI=text; install_plan "php:$2" ;;
    rehacer|actualizar) cli_rebuild "$2" ;;
    add-xampp) ( install_xampp "$2" ) ;;
    version|--version|-v) echo "$APP_NAME $APP_VERSION" ;;
    acerca|about) echo -e "$(about_text)" ;;
    novedades) changes_text ;;
    -h|--help|--ayuda) sed -n '3,/^$/p' "$SELF" | sed 's/^# \{0,1\}//' ;;
    *) echo "Accion desconocida: $1 (usa --ayuda)"; exit 1 ;;
esac
