#!/bin/bash
# Pruebas del correo de pruebas en el Mac (Mailpit, 1.39.9), sin root, sin red y sin tocar /Library: el
# SECURE_PY del Mac (sendmail_path y auto_prepend_file en php/etc/conf.d/99-lvm-correo.ini de las pilas
# propias, y como queda al apagarlo), mail() de PHP y el fichero de WordPress (con un PHP de /opt/lampp o
# del sistema, si hay), Mailpit en marcha y parado con la version con un Mailpit falso (apartado con
# setsid desde Python, sin quedarse con la terminal de la tarea, su numero sin /proc), su instalacion
# (con su sha256, de un .tar.gz de prueba), la orden correo, los cambios en las BBDD de WordPress y
# PrestaShop contra un MariaDB temporal (el de la 8.2.4, como correo.sh) y que no salen en las copias, y
# lo de la ventana (Swift: botón Correo, Configuración, el logotipo). Uso: mac-correo.sh <macos/lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function mail_db() {' "$SRC" || { echo "  ok    (este script del Mac aun no trae el correo de pruebas)"; exit 0; }
W=$(mktemp -d "$TMPBASE/w-mac-correo.XXXX") || exit 1
SOCKD=""
cleanup() {
    [ -n "$MDB_ON" ] && "$DB_CLIENT" -uroot -e "SHUTDOWN" > /dev/null 2>&1
    pkill -u "$(id -u)" -f -- "^$W/.*/mailpit --smtp" 2> /dev/null
    wait 2> /dev/null
    [ -n "$KEEP" ] || rm -rf "$W"
    [ -n "$SOCKD" ] && [ "$SOCKD" != "$W/db" ] && rm -rf "$SOCKD"
}
trap cleanup EXIT
getvar() { ( eval "$(sed -n "/^$1='/,/^'\$/p" "$SRC")"; printf '%s.' "${!1}" ); }
SECURE_PY=$(getvar SECURE_PY); SECURE_PY=${SECURE_PY%.}
MAIL_DB_PY=$(getvar MAIL_DB_PY); MAIL_DB_PY=${MAIL_DB_PY%.}
MAILPIT_SETSID_PY=$(getvar MAILPIT_SETSID_PY); MAILPIT_SETSID_PY=${MAILPIT_SETSID_PY%.}
VH=$(getvar UNKNOWN_HOST_VHOST); VH=${VH%.} SSL=$(getvar UNKNOWN_HOST_SSL); SSL=${SSL%.}
PINI=$(getvar PHP_SECURITY_INI); PINI=${PINI%.} PINI85=$(getvar PHP_SECURITY_INI_85); PINI85=${PINI85%.}
CONF=$(grep -m1 '^UNKNOWN_HOST_CONF=' "$SRC" | cut -d= -f2)
eval "$(sed -n '/^MAIL_WP_PHP=\$(cat <<.PHP.$/,/^)$/p' "$SRC")"
for v in MAILPIT_VERSION MAILPIT_SHA_AMD64 MAILPIT_SHA_ARM64 MAILPIT_MAX MAIL_SMTP_PORT MAIL_UI_PORT MAIL_TABLE; do
    eval "$(grep -m1 "^$v=" "$SRC")"
done
eval "$(grep -m1 '^DB_SAFE=(' "$SRC")"
PHP=""
for p in /opt/lampp-8.4/bin/php /opt/lampp-8.2.4/bin/php /usr/bin/php; do
    [ -x "$p" ] && PHP=$p && break
done
php() { LD_LIBRARY_PATH=$(dirname "$(dirname "$PHP")")/lib "$PHP" "$@"; }

# --- Lo fijo: version, sumas de macOS, donde se instala y el logotipo
check "Mailpit fijado (la misma version que Linux), con la sha256 de darwin arm64 y amd64" '[[ "$MAILPIT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$MAILPIT_SHA_ARM64" =~ ^[0-9a-f]{64}$ ]] && [[ "$MAILPIT_SHA_AMD64" =~ ^[0-9a-f]{64}$ ]] && [ "$MAILPIT_SHA_AMD64" != "$MAILPIT_SHA_ARM64" ] && grep -q "mailpit-darwin-\$arch.tar.gz" "$SRC" && ! grep -q "mailpit-linux-" "$SRC"'
L=${LVM_SCRIPT:-$HERE/../lvm-instalador.sh}
if [ -f "$L" ]; then
    check "misma version de Mailpit que en Linux y otras sumas (las de macOS)" '[ "$(grep -m1 "^MAILPIT_VERSION=" "$L")" = "MAILPIT_VERSION=\"$MAILPIT_VERSION\"" ] && ! grep -qF "$MAILPIT_SHA_ARM64" "$L"'
fi
check "Mailpit de root en /Library/Nexum/mailpit (BASE_DIR), sus datos en ~/.lvm-instalador/mailpit" 'grep -qx "MAILPIT_DIR=\$BASE_DIR/mailpit" "$SRC" && grep -qx "MAILPIT_DATA=\$LOG_DIR/mailpit" "$SRC" && grep -qx "MAIL_OFF_FILE=\$LOG_DIR/correo-apagado" "$SRC" && grep -qx "MAIL_WP_FILE=\$LOG_DIR/correo-wordpress" "$SRC"'
check "Mailpit solo en 127.0.0.1, con su Host comprobado y el entorno limpio (sin MP_*)" 'grep -q -- "--smtp \"127.0.0.1:\$MAIL_SMTP_PORT\" --listen \"127.0.0.1:\$MAIL_UI_PORT\"" "$SRC" && grep -q -- "--allowed-hosts \"127.0.0.1:\$MAIL_UI_PORT,localhost:\$MAIL_UI_PORT\"" "$SRC" && grep -q "exec env -i HOME=" "$SRC" && [ "$MAILPIT_MAX" -gt 0 ]'
check "sin setsid ni /proc (no estan en el Mac)" '! sed -n "/^function mailpit_is() {/,/^function mailpit_sync() {/p" "$SRC" | grep -q "setsid \"\|/proc/"'
check "sin LVM_PRUEBA no se hace caso de LVM_MAILPIT_URL ni LVM_MAILPIT_SHA" 'sed -n "/^if \[ -z \"\$TEST_DIR\" \]; then/,/^fi/p" "$SRC" | grep -q "LVM_MAILPIT_URL LVM_MAILPIT_SHA"'
M=$(grep -m1 '^    "mailpit": "' "$SRC" | sed 's/^    "mailpit": "//; s/",$//')
check "logotipo de Mailpit para la ventana: M, L, C y Z absolutos en la caja de 24x24" '[ -n "$M" ] && python3 -I -c "
import re, sys
t = sys.argv[1].split()
n = [float(x) for x in t if x not in (\"M\", \"L\", \"C\", \"Z\")]
assert all(re.fullmatch(r\"[MLCZ]|-?[0-9]+(\.[0-9]+)?\", x) for x in t) and t[0] == \"M\"
assert len(n) > 40 and min(n) > -1 and max(n) <= 24.5
" "$M"'
check "y su color de marca" 'grep -q "\"mailpit\": hexColor(0x00A87B)" "$SRC"'

# --- SECURE_PY del Mac: PHP de las pilas propias (php/etc/conf.d)
S=$W/pila B=$W/sin-pila
mk() {  # mk <carpeta>: una pila propia como las de install_stack
    mkdir -p "$1/etc/extra" "$1/php/etc/conf.d"
    printf 'Listen 127.0.0.1:80\nInclude %s\nInclude etc/extra/httpd-vhosts.conf\n' "$CONF" > "$1/etc/httpd.conf"
    : > "$1/etc/extra/httpd-vhosts.conf"
    echo "8.4.27|2.4.69|11.8.9|1.3.9|5.42|5.2.3" > "$1/etc/pvm-stack"
    echo "8.4.27" > "$1/etc/pvm-php"
}
mk "$S"; mk "$B"; rm "$B/etc/pvm-stack"
mkdir -p "$W/out" "$W/bin"
FAKE=$W/bin/mailpit
sp() {  # sp <LVM_CORREO> <version> [mas variables]: lo que cambiaria SECURE_PY (solo lo del correo)
    local spec=$1 base=$2; shift 2
    rm -rf "$W/out"; mkdir -p "$W/out"
    env "$@" LVM_CORREO="$spec" LVM_CORREO_PHP="$MAIL_WP_PHP" python3 -I -c "$SECURE_PY" "$base" "$W/out" 1 "$CONF" "$VH" "$SSL" \
        | grep -E "^(php/etc/conf.d/99-lvm-correo.ini|etc/lvm-correo-wordpress.php)\|"
}
new() { awk -F'|' -v r="$2" '$1 == r { print $2 }' <<< "$1"; }
take() { local f; f=$(new "$1" "$2"); [ -n "$f" ] && cp "$f" "$3/$2"; }
out=$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$S" LVM_CORREO_PRUEBA=1)
C=$(cat "$(new "$out" php/etc/conf.d/99-lvm-correo.ini)" 2> /dev/null)
check "pila propia: 99-lvm-correo.ini con sendmail_path al sendmail de Mailpit (127.0.0.1:1025) y auto_prepend_file" 'grep -q "^sendmail_path = \"$FAKE sendmail -S 127.0.0.1:$MAIL_SMTP_PORT\"$" <<< "$C" && grep -q "^auto_prepend_file = \"$S/etc/lvm-correo-wordpress.php\"$" <<< "$C"'
check "el fichero de WordPress se escribe en la version, con el puerto" '[ -n "$(new "$out" etc/lvm-correo-wordpress.php)" ] && grep -q "Port = $MAIL_SMTP_PORT;" "$(new "$out" etc/lvm-correo-wordpress.php)" && cmp -s <(printf "%s\n" "${MAIL_WP_PHP//@PUERTO@/$MAIL_SMTP_PORT}") "$(new "$out" etc/lvm-correo-wordpress.php)"'
if [ -f "$L" ]; then
    LWP=$(eval "$(sed -n '/^MAIL_WP_PHP=\$(cat <<.PHP.$/,/^)$/p' "$L")"; printf '%s' "$MAIL_WP_PHP")
    check "el fichero de WordPress es el mismo que en Linux" '[ "$LWP" = "$MAIL_WP_PHP" ]'
fi
take "$out" php/etc/conf.d/99-lvm-correo.ini "$S"; take "$out" etc/lvm-correo-wordpress.php "$S"
check "una segunda pasada no cambia nada" '[ -z "$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$S" LVM_CORREO_PRUEBA=1)" ]'
out=$(sp "$FAKE|$MAIL_SMTP_PORT|0" "$S" LVM_CORREO_PRUEBA=1)
check "WordPress sin llevar a Mailpit (desactivar o nada): sendmail_path sin auto_prepend_file" 'C=$(cat "$(new "$out" php/etc/conf.d/99-lvm-correo.ini)"); grep -q "^sendmail_path = \"$FAKE" <<< "$C" && ! grep -q auto_prepend <<< "$C"'
out=$(sp "" "$S")
check "apagado: el fichero queda sin directivas" '[ -n "$(new "$out" php/etc/conf.d/99-lvm-correo.ini)" ] && ! grep -q "^[a-z]" "$(new "$out" php/etc/conf.d/99-lvm-correo.ini)"'
take "$out" php/etc/conf.d/99-lvm-correo.ini "$S"
check "apagado otra vez: nada que cambiar" '[ -z "$(sp "" "$S")" ]'
rm -f "$S/php/etc/conf.d/99-lvm-correo.ini"
check "apagado y sin el fichero, nada que cambiar" '[ -z "$(sp "" "$S")" ]'
check "sin pvm-stack (no es una pila del gestor): nada" '[ -z "$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$B" LVM_CORREO_PRUEBA=1)" ]'
check "sin root: el binario y el fichero de WordPress no son de root, no se pone nada" '[ -z "$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$S")" ]'
check "al aplicar (como root) no vale la excepcion de las pruebas" '[ -z "$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$S" LVM_CORREO_PRUEBA=1 LVM_SECURE_APPLY=1)" ]'
check "un LVM_CORREO raro (otra directiva, .., otro puerto) no se usa" '[ -z "$(sp "$FAKE\" -d x=1|1025|1" "$S" LVM_CORREO_PRUEBA=1)" ] && [ -z "$(sp "/Library/../tmp/m|1025|1" "$S" LVM_CORREO_PRUEBA=1)" ] && [ -z "$(sp "$FAKE|10;25|1" "$S" LVM_CORREO_PRUEBA=1)" ]'
rm -f "$S/etc/lvm-correo-wordpress.php"; ln -s "$W/otro.php" "$S/etc/lvm-correo-wordpress.php"
out=$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$S" LVM_CORREO_PRUEBA=1)
check "un enlace en lugar del fichero de WordPress: ni se escribe ni se carga" '[ -z "$(new "$out" etc/lvm-correo-wordpress.php)" ] && ! grep -q auto_prepend "$(new "$out" php/etc/conf.d/99-lvm-correo.ini)"'
rm -f "$S/etc/lvm-correo-wordpress.php"
# root_path_ok, con un programa de root de verdad (sin enlaces: /usr/bin/env) y con uno detras de un enlace
out=$(sp "/usr/bin/env|$MAIL_SMTP_PORT|0" "$S")
check "root_path_ok: un programa de root hasta / si vale (sin la excepcion de las pruebas)" 'grep -q "^sendmail_path = \"/usr/bin/env sendmail" "$(new "$out" php/etc/conf.d/99-lvm-correo.ini)"'
ln -s /usr/bin/env "$W/bin/env-enlace"
check "root_path_ok: detras de un enlace, no" '[ -z "$(sp "$W/bin/env-enlace|$MAIL_SMTP_PORT|0" "$S")" ]'
out=$(LVM_CORREO="$FAKE|$MAIL_SMTP_PORT|1" LVM_CORREO_PHP="$MAIL_WP_PHP" LVM_CORREO_PRUEBA=1 python3 -I -c "$SECURE_PY" "$S" "$W/out" 1 "$CONF" "$VH" "$SSL" "$PINI" "$PINI85")
check "con los .ini de PHP2Shell tambien (como lo llama secure_version)" 'grep -q "^php/etc/conf.d/99-lvm-correo.ini|" <<< "$out" && grep -q "^php/etc/conf.d/zz-lvm-seguridad.ini|" <<< "$out"'
check "secure_version y unsecured_versions le pasan el correo (y nunca la excepcion de las pruebas)" '[ "$(grep -c "LVM_CORREO=\$mail LVM_CORREO_PHP=\$MAIL_WP_PHP LVM_CORREO_PRUEBA= " "$SRC")" = 2 ] && grep -q "env LVM_SECURE_APPLY=1 LVM_CORREO=\"\$mail\" LVM_CORREO_PHP=\"\$MAIL_WP_PHP\"" "$SRC" && sed -n "/^function secure_version() {/,/^}/p" "$SRC" | grep -q "mail=\$(mail_secure_spec)" && sed -n "/^function unsecured_versions() {/,/^}/p" "$SRC" | grep -q "mail=\$(mail_secure_spec)"'

# --- PHP: mail() hasta el Mailpit falso, y el fichero de WordPress
# Mailpit falso: sendmail guarda el correo; si no, apunta sus argumentos y su entorno y se queda en
# marcha con la orden de Mailpit (como el de verdad: <binario> --smtp ...)
cat > "$FAKE" << 'EOF'
#!/bin/bash
d=$(dirname "$0")
if [ "$1" == sendmail ]; then
    shift
    printf '%s\n' "$*" > "$d/sendmail-args"
    cat > "$d/correo"
    exit 0
fi
printf '%s\n' "$*" > "$d/arranque"
env > "$d/entorno"
exec -a "$0 $*" sleep 60
EOF
chmod 755 "$FAKE"
out=$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$S" LVM_CORREO_PRUEBA=1)
take "$out" php/etc/conf.d/99-lvm-correo.ini "$S"; take "$out" etc/lvm-correo-wordpress.php "$S"
if [ -n "$PHP" ]; then
    php -n -c "$S/php/etc/conf.d/99-lvm-correo.ini" -r 'var_export(mail("cliente@tienda.es", "Pedido 1", "Gracias", "From: tienda@tienda.es"));' > "$W/mail.out" 2>&1
    check "mail() de PHP va al sendmail de Mailpit (-S 127.0.0.1:1025) con el correo entero" '[ "$(cat "$W/mail.out")" = true ] && grep -q "^-S 127.0.0.1:$MAIL_SMTP_PORT" "$W/bin/sendmail-args" && grep -q "^To: cliente@tienda.es" "$W/bin/correo" && grep -q "^Subject: Pedido 1" "$W/bin/correo"'
    echo '<?php echo isset($GLOBALS["wp_filter"]["phpmailer_init"]) ? "ganchos" : "nada", "|", function_exists("add_action") ? "wp" : "sin wp", "\n";' > "$W/otro.php"
    r=$(php -n -c "$S/php/etc/conf.d/99-lvm-correo.ini" "$W/otro.php" 2>&1)
    check "auto_prepend_file: fuera de WordPress (PrestaShop, phpMyAdmin) solo deja sus ganchos" '[ "$r" = "ganchos|sin wp" ]'
    for v in 7.4 8.5; do
        [ -x "/opt/lampp-$v/bin/php" ] || continue
        r=$(LD_LIBRARY_PATH=/opt/lampp-$v/lib "/opt/lampp-$v/bin/php" -n -l "$S/etc/lvm-correo-wordpress.php" 2>&1)
        check "el fichero de WordPress vale para PHP $v (php -l)" 'grep -q "No syntax errors" <<< "$r"'
    done
else
    echo "  ok    (sin PHP: no se prueba mail() ni el fichero de WordPress)"
fi

# --- Mailpit en marcha y parado con la version (con el falso)
extract "$SRC" mail_on mail_wp_mode mailpit_installed mailpit_installed_version mail_secure_spec mailpit_is mailpit_find \
    mailpit_pid mailpit_start mailpit_stop mailpit_sync || exit 1
LOG_DIR=$W/home/.lvm-instalador DRY=0
mkdir -p -m 700 "$LOG_DIR"
MAILPIT_DIR=$W/bin MAILPIT_BIN=$FAKE MAILPIT_DATA=$LOG_DIR/mailpit MAIL_UI_URL="http://127.0.0.1:1/"
MAIL_OFF_FILE=$LOG_DIR/correo-apagado MAIL_WP_FILE=$LOG_DIR/correo-wordpress
check "por defecto: encendido, WordPress a Mailpit" 'mail_on && [ "$(mail_wp_mode)" = mailpit ] && [ "$(mail_secure_spec)" = "$FAKE|$MAIL_SMTP_PORT|1" ]'
echo raro > "$MAIL_WP_FILE"
check "un modo raro en el fichero cuenta como mailpit" '[ "$(mail_wp_mode)" = mailpit ]'
echo nada > "$MAIL_WP_FILE"
check "modo nada: sendmail_path sin el fichero de WordPress" '[ "$(mail_secure_spec)" = "$FAKE|$MAIL_SMTP_PORT|0" ]'
: > "$MAIL_OFF_FILE"
check "apagado: nada para el PHP" '! mail_on && [ -z "$(mail_secure_spec)" ]'
rm -f "$MAIL_OFF_FILE" "$MAIL_WP_FILE"
lampp_running() { false; }
mailpit_sync > /dev/null
check "con la version parada no arranca" '[ -z "$(mailpit_pid)" ] && [ ! -e "$W/bin/arranque" ]'
lampp_running() { true; }
# (en una sustitucion de orden: si Mailpit se quedara con su salida, esto no acabaria nunca)
s0=$(date +%s)
o=$(MP_SMTP_RELAY_ALL=true mailpit_sync)
s1=$(date +%s)
p=$(mailpit_pid)
check "con la version en marcha arranca, con tu usuario y su .pid" '[ -n "$p" ] && [ "$(cat "$MAILPIT_DATA/mailpit.pid")" = "$p" ] && [ "$(ps -o user= -p "$p")" = "$(id -un)" ] && grep -q "en marcha" <<< "$o"'
check "no se queda con la salida de la tarea (la orden acaba enseguida)" '[ $((s1 - s0)) -lt 8 ]'
check "apartado de la sesion de la tarea (os.setsid del Python del sistema): es el lider de la suya" '[ "$(ps -o sid= -p "$p" | tr -d " ")" = "$p" ] && [ "$(ps -o sid= -p "$p" | tr -d " ")" != "$(ps -o sid= -p $$ | tr -d " ")" ]'
check "entrada de /dev/null y salida a su fichero (no a la terminal de la tarea)" '[ "$(readlink "/proc/$p/fd/0")" = /dev/null ] && [ "$(readlink "/proc/$p/fd/1")" = "$MAILPIT_DATA/salida.log" ] && [ "$(readlink "/proc/$p/fd/2")" = "$MAILPIT_DATA/salida.log" ]'
check "sus datos en ~/.lvm-instalador/mailpit (700) y como mucho $MAILPIT_MAX correos" '[ "$(stat -c %a "$MAILPIT_DATA")" = 700 ] && grep -q -- "--database $MAILPIT_DATA/mailpit.db --max $MAILPIT_MAX" "$W/bin/arranque"'
check "solo 127.0.0.1 (SMTP y web) y sin las variables MP_* de la sesion" 'grep -q -- "--smtp 127.0.0.1:$MAIL_SMTP_PORT --listen 127.0.0.1:$MAIL_UI_PORT" "$W/bin/arranque" && ! grep -q "^MP_" "$W/bin/entorno" && grep -qx "PATH=/usr/bin:/bin" "$W/bin/entorno"'
mailpit_sync > /dev/null
check "otra vez: no arranca otro" '[ "$(pgrep -u "$(id -u)" -fc -- "^$FAKE --smtp ")" = 1 ]'
rm -f "$MAILPIT_DATA/mailpit.pid"
check "sin su .pid tambien lo encuentra (pgrep por el principio de su orden)" '[ "$(mailpit_pid)" = "$p" ]'
echo $$ > "$MAILPIT_DATA/mailpit.pid"
check "un .pid de otro proceso no vale (ps: su usuario y su orden)" '! mailpit_is $$ && [ "$(mailpit_pid)" = "$p" ]'
sleep 300 & other=$!
echo "$other" > "$MAILPIT_DATA/mailpit.pid"
check "ni el de un proceso tuyo cualquiera" '! mailpit_is "$other" && [ "$(mailpit_pid)" = "$p" ]'
kill "$other" 2> /dev/null; wait "$other" 2> /dev/null
check "ni el 1 ni algo que no es un numero" '! mailpit_is 1 && ! mailpit_is "1 2" && ! mailpit_is ""'
: > "$MAIL_OFF_FILE"
o=$(mailpit_sync)
check "al apagar el correo de pruebas se para" '[ -z "$(mailpit_pid)" ] && ! kill -0 "$p" 2> /dev/null && grep -q parado <<< "$o"'
rm -f "$MAIL_OFF_FILE"
mailpit_sync > /dev/null; p=$(mailpit_pid)
lampp_running() { false; }
mailpit_sync > /dev/null
check "al parar la version se para" '[ -n "$p" ] && ! kill -0 "$p" 2> /dev/null && [ -z "$(mailpit_pid)" ]'
check "arranca y para con la version: use, arrancar/parar, disable, servicio, cargar-proyecto, los cambios del correo y la ventana" '[ "$(grep -c "^    mailpit_sync$" "$SRC")" -ge 6 ] && grep -q "mailpit_sync --suave > /dev/null 2>&1" "$SRC" && for f in use_version load_project_steps service_control disable_version control_lampp mail_apply; do sed -n "/^function $f() {/,/^}/p" "$SRC" | grep -q "^    mailpit_sync$" || exit 1; done'
check "nunca como root" 'sed -n "/^function mailpit_start() {/,/^}/p" "$SRC" | grep -q "\"\$(id -u)\" -eq 0 ] && { echo \"Mailpit no se arranca como root\""'
# Otro programa en su puerto: no arranca y, desde la ventana (--suave), no se reintenta en 5 minutos
printf '#!/bin/bash\nexit 1\n' > "$W/bin/mailpit-malo"; chmod 755 "$W/bin/mailpit-malo"
lampp_running() { true; }
o=$(MAILPIT_BIN=$W/bin/mailpit-malo mailpit_sync)
check "si no arranca (puerto ocupado) lo dice" 'grep -q "no ha arrancado" <<< "$o" && [ -e "$MAILPIT_DATA/no-arranca" ]'
s0=$(date +%s%N); MAILPIT_BIN=$W/bin/mailpit-malo mailpit_sync --suave > /dev/null; s1=$(date +%s%N)
check "desde la ventana (--suave) no se reintenta enseguida" '[ $(( (s1 - s0) / 1000000 )) -lt 1000 ]'
rm -f "$MAILPIT_DATA/no-arranca"
lampp_running() { false; }
mv "$MAILPIT_DATA" "$W/mailpit-mio"; ln -s "$W/mailpit-mio" "$MAILPIT_DATA"
lampp_running() { true; }
o=$(mailpit_start)
check "si su carpeta es un enlace, no arranca" 'grep -q "no es una carpeta tuya" <<< "$o" && [ -z "$(mailpit_find)" ]'
rm -f "$MAILPIT_DATA"; mv "$W/mailpit-mio" "$MAILPIT_DATA"
lampp_running() { false; }

# --- Instalar Mailpit (sin red: un .tar.gz de prueba) y la orden correo
extract "$SRC" mailpit_install mail_wp_text mail_command || exit 1
mkdir -p "$W/tar" "$W/prueba"
cp "$FAKE" "$W/tar/mailpit"; echo "MIT" > "$W/tar/LICENSE"; echo "readme" > "$W/tar/README.md"
tar -czf "$W/mailpit.tar.gz" -C "$W/tar" mailpit LICENSE README.md
SHA=$(sha256sum "$W/mailpit.tar.gz" | cut -d' ' -f1)
APPLIED=$W/aplicado
mail_apply() { echo "aplicado" >> "$APPLIED"; return 0; }
mail_db() { echo "bd $1"; }
run() { if [ "$DRY" -eq 1 ]; then echo "  [simulacion] $*"; else "$@"; fi; }
cli() {  # cli [--simular] <argumentos de correo>: como lvm-instalador correo, en las pruebas (LVM_PRUEBA)
    local dry=0
    [ "$1" == --simular ] && dry=1 && shift
    ( TEST_DIR=$W/prueba BASE_DIR=$W/prueba SUDO="" DRY=$dry LOG_DIR=$W/home2/.lvm-instalador
      MAILPIT_DIR=$W/prueba/mailpit MAILPIT_BIN=$W/prueba/mailpit/mailpit MAILPIT_DATA=$W/home2/.lvm-instalador/mailpit
      MAIL_OFF_FILE=$W/home2/.lvm-instalador/correo-apagado MAIL_WP_FILE=$W/home2/.lvm-instalador/correo-wordpress
      LVM_MAILPIT_URL=file://$W/mailpit.tar.gz
      mail_command "$@" ) < /dev/null 2>&1
}
mkdir -p "$W/home2"
o=$(cli)
check "correo estado: encendido por defecto, WordPress a Mailpit y Mailpit sin instalar" 'grep -q "^Correo de pruebas encendido" <<< "$o" && grep -q "siguen, con su correo a Mailpit" <<< "$o" && grep -q "no esta instalado" <<< "$o"'
o=$(cli no)
check "correo no: apagado (con su fichero) y aplicado" '[ -e "$W/home2/.lvm-instalador/correo-apagado" ] && grep -q "apagado" <<< "$o" && [ "$(cat "$APPLIED")" = aplicado ]'
o=$(cli --simular si)
check "--simular correo si no cambia nada" '[ -e "$W/home2/.lvm-instalador/correo-apagado" ] && grep -q simulacion <<< "$o" && [ "$(grep -c . "$APPLIED")" = 1 ]'
o=$(LVM_MAILPIT_SHA=$(printf '0%.0s' {1..64}) cli instalar)
check "una descarga con otra sha256 no se instala" '[ ! -e "$W/prueba/mailpit/mailpit" ] && grep -q "no coincide con su suma sha256" <<< "$o"'
o=$(LVM_MAILPIT_SHA=$SHA cli instalar)
check "con su sha256, instalado en BASE_DIR/mailpit con su version y su licencia (sin el README)" '[ -x "$W/prueba/mailpit/mailpit" ] && cmp -s "$W/prueba/mailpit/mailpit" "$FAKE" && [ "$(cat "$W/prueba/mailpit/version")" = "$MAILPIT_VERSION" ] && [ -f "$W/prueba/mailpit/LICENSE" ] && [ ! -e "$W/prueba/mailpit/README.md" ] && grep -q "esta apagado" <<< "$o"'
check "no queda nada de la descarga" '[ -z "$(ls -d "$W"/home2/.lvm-instalador/mailpit-descarga.* "$W"/prueba/lvm-mailpit.* 2> /dev/null)" ]'
o=$(LVM_MAILPIT_SHA=$SHA cli instalar)
check "otra vez: ya esta instalado" 'grep -q "ya esta instalado" <<< "$o"'
check "en el Mac: fuera los atributos extendidos y la firma comprobada (codesign), solo sin LVM_PRUEBA" 'sed -n "/^function mailpit_install() {/,/^}/p" "$SRC" | grep -q "\$SUDO /usr/bin/xattr -c \"\$bin\"" && sed -n "/^function mailpit_install() {/,/^}/p" "$SRC" | grep -q "/usr/bin/codesign --verify \"\$bin\""'
check "como root, solo programas del sistema (root_command): tar, shasum, install, xattr..." '! sed -n "/^function mailpit_install() {/,/^}/p" "$SRC" | grep -E "\\\$SUDO +(/opt/homebrew|brew|gtar|sha256sum)"'
check "la carpeta de encima (/Library/Nexum) y la suya, de root (stat -f del Mac)" 'sed -n "/^function mailpit_install() {/,/^}/p" "$SRC" | grep -q "stat -f %u \"\$BASE_DIR\""'
o=$(cli si)
check "correo si: encendido otra vez" '[ ! -e "$W/home2/.lvm-instalador/correo-apagado" ] && grep -q "encendido" <<< "$o"'
o=$(cli wordpress desactivar)
check "correo wordpress desactivar: se guarda" '[ "$(cat "$W/home2/.lvm-instalador/correo-wordpress")" = desactivar ] && grep -q "se desactivan en la copia local" <<< "$o"'
o=$(cli wordpress todo)
check "correo wordpress con un modo raro: uso, sin cambiar nada" '[ "$(cat "$W/home2/.lvm-instalador/correo-wordpress")" = desactivar ] && grep -q "^Uso" <<< "$o"'
o=$(cli raro)
check "correo con una orden rara: uso" 'grep -q "^Uso: lvm-instalador correo" <<< "$o"'
o=$(cli vaciar)
check "correo vaciar sin Mailpit en marcha: lo dice" 'grep -q "no esta en marcha" <<< "$o"'
check "la ayuda y el comando correo" 'grep -q "^#   lvm-instalador correo \[estado\]" "$SRC" && grep -q "^    correo) mail_command \"\$2\" \"\$3\" ;;" "$SRC" && grep -q "de root en /Library/Nexum/mailpit" "$SRC"'
check "mail_apply: asegura todas, recarga Apache y PHP-FPM con xampp_ctl y pone al dia el proyecto cargado" 'sed -n "/^function mail_apply() {/,/^}/p" "$SRC" | grep -q "run xampp_ctl reloadapache" && sed -n "/^function mail_apply() {/,/^}/p" "$SRC" | grep -q "^    mail_loaded_project$"'
check "gui-datos: E| con lo de Mailpit (y lo arranca si se ha cerrado)" 'grep -q "echo \"E|\$(mailpit_installed && echo 1 || echo 0)|\$(mail_on && echo 1 || echo 0)|\$(mail_wp_mode)|" "$SRC" && sed -n "/^function gui_data() {/,/^}/p" "$SRC" | grep -q "mailpit_sync --suave"'

# --- La ventana (Swift)
SW=$(sed -n "/^    cat <<'LVM_SWIFT'$/,/^LVM_SWIFT$/p" "$SRC")
check "ventana: lee la linea E| de gui-datos" 'grep -q "case \"E\" where f.count >= 8:" <<< "$SW" && grep -q "^struct MailState: Equatable {" <<< "$SW"'
check "ventana: botón Correo arriba, junto a Localhost, con el logotipo y los sin leer; oculto si esta apagado" 'grep -q "^            mailButton()$" <<< "$SW" && grep -q "if let m = model.data?.mail, m.on {" <<< "$SW" && grep -q "LOGO_PATHS\[\"mailpit\"\]" <<< "$SW" && grep -q "\"99+\"" <<< "$SW"'
check "ventana: los sin leer de api/v1/info, con el curl del sistema y sin proxy, solo con la ventana a la vista" 'grep -q "\"api/v1/info\"" <<< "$SW" && grep -q "\"/usr/bin/curl\"" <<< "$SW" && grep -q "\"--noproxy\", \"\*\"" <<< "$SW" && sed -n "/func pollMail() {/,/^    }/p" <<< "$SW" | grep -q "isVisible"'
check "ventana: Configuración, interruptor (confirma al apagar), los tres modos de WordPress e instalar o la bandeja" 'grep -q "Card(\"Correo de pruebas (Mailpit)\"" <<< "$SW" && grep -q "¿Apagar el correo de pruebas?" <<< "$SW" && grep -q "Text(\"Llevarlos a Mailpit\").tag(\"mailpit\")" <<< "$SW" && grep -q "Text(\"Desactivarlos en la copia local\").tag(\"desactivar\")" <<< "$SW" && grep -q "Text(\"No tocarlos\").tag(\"nada\")" <<< "$SW" && grep -q "\[\"correo\", \"wordpress\", mode\]" <<< "$SW" && grep -q "Button(\"Instalar Mailpit\")" <<< "$SW" && grep -q "Row(\"Bandeja de entrada\"" <<< "$SW" && grep -q "args.append(\"--instalar\")" <<< "$SW"'
check "ventana: las filas del correo con el logotipo de Mailpit (ROW_ICONS)" 'grep -q "(\"Mailpit\", \"logo:mailpit\", brand(\"mailpit\"))" <<< "$SW" && grep -q "(\"Bandeja de entrada\", \"logo:mailpit\", brand(\"mailpit\"))" <<< "$SW" && grep -q "(\"Correo de pruebas\", \"logo:mailpit\", brand(\"mailpit\"))" <<< "$SW"'
check "ventana: «su correo va a Mailpit» junto al proyecto cargado" 'grep -q "Text(\"su correo va a Mailpit\")" <<< "$SW"'
check "ventana: sin let en los ViewBuilder ni if let con varias asignaciones raras (Swift de macOS 12)" '! grep -nE "^\s+if let [a-z]+ = [^,{]+, let " <<< "$(sed -n "/func mailButton() -> some View {/,/^    }/p; /func mailCard(_ d: AppData) -> some View {/,/^    }/p" <<< "$SW")"'
check "version 1.39.9 o posterior, con la entrada de Mailpit en las novedades" 'v=$(sed -n "s/^APP_VERSION=\"\(.*\)\"$/\1/p" "$SRC"); [ "$(printf "1.39.9\n%s\n" "$v" | sort -V | head -1)" == "1.39.9" ] && grep -qx "1.39.9 (25 oct 2026)" "$SRC" && grep -A3 "^1.39.9 (25 oct 2026)$" "$SRC" | grep -q "Mailpit"'
check "1.39.10: el paquete se abre entero y se busca el programa, con el error de tar si falla" 'sed -n "/^function mailpit_install() {/,/^}/p" "$SRC" | grep -q "find \"\$x\" -maxdepth 2 -type f -name mailpit" && sed -n "/^function mailpit_install() {/,/^}/p" "$SRC" | grep -q "releases/tag/v\$MAILPIT_VERSION"'

# --- BBDD: WordPress y PrestaShop contra un MariaDB temporal
if [ ! -x /opt/lampp-8.2.4/sbin/mysqld ]; then
    echo "  ok    (sin /opt/lampp-8.2.4: no se prueban las BBDD)"
    exit $fail
fi
MDB=$W/db; mkdir -p "$MDB"
SOCKD=$MDB; [ ${#SOCKD} -gt 80 ] && SOCKD=$(mktemp -d /tmp/lvm-mac-correo.XXXX)
LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/bin/mysql_install_db --no-defaults --basedir=/opt/lampp-8.2.4 \
    --datadir="$MDB/data" --auth-root-authentication-method=normal > "$MDB/install.log" 2>&1 \
    || { echo "  FALLA no se ha podido crear el MariaDB temporal"; exit 1; }
printf '#!/bin/sh\nLD_LIBRARY_PATH=/opt/lampp-8.2.4/lib exec /opt/lampp-8.2.4/bin/mysql --no-defaults -S %s/sock "$@"\n' "$SOCKD" > "$MDB/client"
printf '#!/bin/sh\nLD_LIBRARY_PATH=/opt/lampp-8.2.4/lib exec /opt/lampp-8.2.4/bin/mysqldump --no-defaults -S %s/sock "$@"\n' "$SOCKD" > "$MDB/dump"
chmod +x "$MDB/client" "$MDB/dump"
LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/sbin/mysqld --no-defaults --basedir=/opt/lampp-8.2.4 --datadir="$MDB/data" \
    --socket="$SOCKD/sock" --skip-networking --pid-file="$MDB/pid" --log-error="$MDB/err.log" > /dev/null 2>&1 &
DB_CLIENT=$MDB/client MDB_ON=1
for i in $(seq 50); do "$DB_CLIENT" -uroot -e 'SELECT 1' > /dev/null 2>&1 && break; sleep 0.2; done
"$DB_CLIENT" -uroot -e 'SELECT 1' > /dev/null 2>&1 || { echo "  FALLA el MariaDB temporal no arranca"; exit 1; }
unset -f mail_db
extract "$SRC" mail_db_rows mail_db mail_export_filter || exit 1
m() { "$DB_CLIENT" -uroot -N "$@"; }
plugins() { m "$1" -e "SELECT option_value FROM $2 WHERE option_name = 'active_plugins'" | grep -o 's:[0-9]*:"[^"]*"' | sed 's/^s:[0-9]*:"//; s/"$//' | grep -E '/|\.php$' | sort | tr '\n' ' '; }
opt() { m "$1" -e "SELECT option_value FROM $2 WHERE option_name = '$3'"; }
psv() { m "$1" -e "SELECT IFNULL(GROUP_CONCAT(IFNULL(value, 'NULL') ORDER BY id_configuration), '') FROM ps_configuration WHERE name = '$2'"; }
ser() { python3 -I -c 'import sys
items = sys.argv[1:]
print("a:%d:{" % len(items) + "".join("i:%d;s:%d:\"%s\";" % (n, len(p), p) for n, p in enumerate(items)) + "}")' "$@"; }
m -e "CREATE DATABASE cliente"
WMS='a:2:{s:4:"mail";a:2:{s:6:"mailer";s:10:"sendinblue";s:10:"from_email";s:14:"web@cliente.es";}s:10:"sendinblue";a:1:{s:7:"api_key";s:12:"xkeysib-1234";}}'
m cliente << SQL
CREATE TABLE wp_options (option_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, option_name VARCHAR(191) NOT NULL UNIQUE, option_value LONGTEXT NOT NULL, autoload VARCHAR(20) NOT NULL DEFAULT 'yes') DEFAULT CHARSET=utf8mb4;
INSERT INTO wp_options (option_name, option_value) VALUES ('siteurl', 'https://cliente.es'),
    ('active_plugins', '$(ser akismet/akismet.php mailin/sendinblue.php wp-mail-smtp/wp_mail_smtp.php fluent-smtp/fluent-smtp.php contact-form-7/wp-contact-form-7.php)'),
    ('wp_mail_smtp', '$WMS');
CREATE TABLE ps_configuration (id_configuration INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, id_shop_group INT UNSIGNED NULL, id_shop INT UNSIGNED NULL,
    name VARCHAR(254) NOT NULL, value TEXT NULL, date_add DATETIME NOT NULL, date_upd DATETIME NOT NULL) DEFAULT CHARSET=utf8mb4;
INSERT INTO ps_configuration (id_shop_group, id_shop, name, value, date_add, date_upd) VALUES
    (NULL, NULL, 'PS_MAIL_METHOD', '1', NOW(), NOW()), (1, 2, 'PS_MAIL_METHOD', '3', NOW(), NOW()),
    (NULL, NULL, 'PS_MAIL_SERVER', 'smtp-relay.brevo.com', NOW(), NOW()), (NULL, NULL, 'PS_MAIL_USER', 'tienda@cliente.es', NOW(), NOW()),
    (NULL, NULL, 'PS_MAIL_PASSWD', NULL, NOW(), NOW()), (NULL, NULL, 'PS_MAIL_SMTP_PORT', '587', NOW(), NOW());
SQL
ORIG_AP=$(plugins cliente wp_options)
sum() { m cliente -e "CHECKSUM TABLE wp_options, ps_configuration" | awk '{print $2}' | tr '\n' ' '; }
ORIG_SUM=$(sum)
o=$(mail_db cliente)
check "mail_db (con el cliente del Mac, DB_SAFE): dice lo que cambia" 'grep -q "desactivados en la copia local: Brevo, FluentSMTP" <<< "$o" && grep -q "WP Mail SMTP mandaba por sendinblue" <<< "$o" && grep -q "PrestaShop (ps_configuration): correo por SMTP a Mailpit" <<< "$o"'
check "WordPress: fuera Brevo y FluentSMTP (API), siguen WP Mail SMTP, Contact Form 7 y los demas" '[ "$(plugins cliente wp_options)" = "akismet/akismet.php contact-form-7/wp-contact-form-7.php wp-mail-smtp/wp_mail_smtp.php " ]'
check "PrestaShop: SMTP a 127.0.0.1:1025 sin usuario ni cifrado, en todas las tiendas" '[ "$(psv cliente PS_MAIL_METHOD)" = "2,2" ] && [ "$(psv cliente PS_MAIL_SERVER)" = 127.0.0.1 ] && [ "$(psv cliente PS_MAIL_SMTP_PORT)" = "$MAIL_SMTP_PORT" ] && [ "$(psv cliente PS_MAIL_USER)" = "" ] && [ "$(psv cliente PS_MAIL_SMTP_ENCRYPTION)" = off ]'
SUM1=$(sum)
mail_db cliente > /dev/null
check "otra vez (otra carga): nada cambia" '[ "$(sum)" = "$SUM1" ]'
# --- La copia (lo que hace export_database): sin la tabla y con lo de antes
query=("$DB_CLIENT" -uroot -N) skip=() mail_sql=""
mail_export_filter cliente
check "copia: la tabla apuntada se queda fuera y hay SQL con lo de antes" '[ "${skip[*]}" = "--ignore-table=cliente.$MAIL_TABLE" ] && grep -q "^UPDATE \`wp_options\`" <<< "$mail_sql" && grep -q "^DELETE FROM \`ps_configuration\`" <<< "$mail_sql"'
{ "$MDB/dump" -uroot --single-transaction --quick --triggers "${skip[@]}" cliente; printf '%s\n' "$mail_sql"; } > "$MDB/copia.sql" 2> "$MDB/dump.err"
m -e "CREATE DATABASE copia"; m copia < "$MDB/copia.sql"
check "copia: sin $MAIL_TABLE, con los plugins y el correo de PrestaShop de produccion" '! m copia -e "SHOW TABLES" | grep -qx "$MAIL_TABLE" && [ "$(plugins copia wp_options)" = "$ORIG_AP" ] && [ "$(opt copia wp_options wp_mail_smtp)" = "$WMS" ] && [ "$(psv copia PS_MAIL_SERVER)" = smtp-relay.brevo.com ] && [ "$(psv copia PS_MAIL_PASSWD)" = NULL ] && [ -z "$(psv copia PS_MAIL_SMTP_ENCRYPTION)" ]'
check "la BBDD de trabajo sigue con el correo a Mailpit" '[ "$(psv cliente PS_MAIL_SERVER)" = 127.0.0.1 ]'
check "export_database: con el cliente de la activa o el del MariaDB temporal, sin la tabla y con lo de antes al final" 'E=$(sed -n "/^function export_database() {/,/^}/p" "$SRC"); grep -q "^    mail_export_filter \"\$db\"$" <<< "$E" && grep -q "query=(\"\${DB_SAFE\[@\]}\" \"\$DB_CLIENT\" -uroot -N)" <<< "$E" && grep -q "query=(\"\$dir/xamppfiles/mysql/bin/mariadb\" --no-defaults -S \"\$DB_TMP_SOCK\" -uroot -N)" <<< "$E" && grep -q "\"\${skip\[@\]}\" \"\$db\" || exit 1" <<< "$E" && grep -q "printf .%s\\\\n. \"\$mail_sql\"" <<< "$E"'
check "al cargar una BBDD (importar-bd, copiar-bd, pasar-version) y un proyecto se aplica" 'sed -n "/^function import_database() {/,/^}/p" "$SRC" | grep -q "^    mail_db \"\$db\"$" && sed -n "/^function load_project_steps() {/,/^}/p" "$SRC" | grep -q "mail_db \"\$mdb\""'
check "Docker (docker-crear --bd) copia con exportar-bd: lleva el correo de produccion" 'sed -n "/^function docker_create() {/,/^}/p" "$SRC" | grep -q "export_database \"\$db\""'
echo nada > "$MAIL_WP_FILE"
o=$(mail_db cliente)
check "modo nada: vuelve todo lo de antes y la tabla desaparece" '[ "$(plugins cliente wp_options)" = "$ORIG_AP" ] && [ "$(psv cliente PS_MAIL_METHOD)" = "1,3" ] && ! m cliente -e "SHOW TABLES" | grep -qx "$MAIL_TABLE" && grep -q "deshecho" <<< "$o"'
rm -f "$MAIL_WP_FILE"
mail_db cliente > /dev/null
: > "$MAIL_OFF_FILE"
mail_db cliente > /dev/null
check "apagado: la BBDD vuelve a ser la de antes del correo de pruebas" '[ "$(sum)" = "$ORIG_SUM" ] || [ "$(plugins cliente wp_options)" = "$ORIG_AP" -a "$(psv cliente PS_MAIL_SERVER)" = smtp-relay.brevo.com ]'
rm -f "$MAIL_OFF_FILE"
check "una base con un nombre raro no se toca" '! mail_db "x;DROP" > /dev/null'
exit $fail
