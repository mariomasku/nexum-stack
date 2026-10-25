#!/bin/bash
# Pruebas del correo de pruebas (Mailpit, Linux 1.55.0): SECURE_PY (sendmail_path y auto_prepend_file en
# las pilas propias y en el php.ini de XAMPP, y como estaba al apagarlo), el fichero de WordPress que
# lleva sus plugins de SMTP a Mailpit (con un WordPress de mentira y, si hay uno en /opt/htdocs, con su
# plugin.php de verdad), mail() de PHP hasta un Mailpit falso, los cambios en las BBDD de WordPress y
# PrestaShop contra un MariaDB temporal (el de la 8.2.4, como admin-fuera.sh) y que no salen en las
# copias, la instalacion de Mailpit (comprobada con su sha256) y la orden correo.
# Sin root, sin red y sin tocar /opt. Uso: correo.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function mail_db() {' "$SRC" || { echo "  ok    (sin correo de pruebas)"; exit 0; }
W=$(mktemp -d "$TMPBASE/w-correo.XXXX") || exit 1
SOCKD=""
cleanup() {
    [ -n "$MDB_ON" ] && "$DB_CLIENT" -uroot -e "SHUTDOWN" > /dev/null 2>&1
    pkill -u "$(id -u)" -f -- "$W/.*/mailpit --smtp" 2> /dev/null
    wait 2> /dev/null
    [ -n "$KEEP" ] || rm -rf "$W"
    [ -n "$SOCKD" ] && [ "$SOCKD" != "$W/db" ] && rm -rf "$SOCKD"
}
trap cleanup EXIT
getvar() { ( eval "$(sed -n "/^$1='/,/^'\$/p" "$SRC")"; printf '%s.' "${!1}" ); }
SECURE_PY=$(getvar SECURE_PY); SECURE_PY=${SECURE_PY%.}
MAIL_DB_PY=$(getvar MAIL_DB_PY); MAIL_DB_PY=${MAIL_DB_PY%.}
eval "$(sed -n '/^MAIL_WP_PHP=\$(cat <<.PHP.$/,/^)$/p' "$SRC")"
for v in MAILPIT_VERSION MAILPIT_SHA_AMD64 MAILPIT_SHA_ARM64 MAILPIT_MAX MAIL_SMTP_PORT MAIL_UI_PORT MAIL_TABLE; do
    eval "$(grep -m1 "^$v=" "$SRC")"
done
eval "$(grep -m1 '^DB_SAFE=(' "$SRC")"
PHP=""
for p in /usr/bin/php /opt/lampp-8.4/bin/php /opt/lampp-8.2.4/bin/php; do
    [ -x "$p" ] && PHP=$p && break
done
php() { LD_LIBRARY_PATH=$(dirname "$(dirname "$PHP")")/lib "$PHP" "$@"; }

# --- Lo fijo: version, sumas y logotipo
check "Mailpit fijado a una version, con la sha256 de linux amd64 y arm64" '[[ "$MAILPIT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$MAILPIT_SHA_AMD64" =~ ^[0-9a-f]{64}$ ]] && [[ "$MAILPIT_SHA_ARM64" =~ ^[0-9a-f]{64}$ ]] && [ "$MAILPIT_SHA_AMD64" != "$MAILPIT_SHA_ARM64" ]'
check "Mailpit solo en 127.0.0.1, con su Host comprobado y el entorno limpio (sin MP_*)" 'grep -q -- "--smtp \"127.0.0.1:\$MAIL_SMTP_PORT\" --listen \"127.0.0.1:\$MAIL_UI_PORT\"" "$SRC" && grep -q -- "--allowed-hosts \"127.0.0.1:\$MAIL_UI_PORT,localhost:\$MAIL_UI_PORT\"" "$SRC" && grep -q "exec env -i HOME=" "$SRC" && [ "$MAILPIT_MAX" -gt 0 ]'
check "logotipo de Mailpit en la ventana (LOGO_PATHS y su color)" 'grep -q "^    \"mailpit\": ($" "$SRC" && grep -q "\"mailpit\": (\"#" "$SRC"'

# --- SECURE_PY: PHP de las pilas propias y de XAMPP
B=$W/xampp S=$W/pila
mkdir -p "$B/etc" "$S/etc" "$S/php/etc/conf.d" "$W/out" "$W/bin"
INI=$'[PHP]\r\nsendmail_path = "env -i /usr/sbin/sendmail -t -i"\r\n;sendmail_path = comentado\r\nauto_prepend_file =\r\nmemory_limit = 512M\r\n'
printf '%s' "$INI" > "$B/etc/php.ini"
echo "8.4.27|2.4|11.8|1.3.9|5.42|5.2.3" > "$S/etc/lvm-stack"
FAKE=$W/bin/mailpit
sp() {  # sp <LVM_CORREO> <version> [mas variables]: lo que cambiaria SECURE_PY
    local spec=$1 base=$2; shift 2
    rm -rf "$W/out"; mkdir -p "$W/out"
    env "$@" LVM_CORREO="$spec" LVM_CORREO_PHP="$MAIL_WP_PHP" python3 -I -c "$SECURE_PY" "$base" "$W/out" 1 etc/x.conf "" ""
}
new() { awk -F'|' -v r="$2" '$1 == r { print $2 }' <<< "$1"; }
take() { local f; f=$(new "$1" "$2"); [ -n "$f" ] && cp "$f" "$3/$2"; }
out=$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$B" LVM_CORREO_PRUEBA=1)
X=$(cat "$(new "$out" etc/php.ini)" 2> /dev/null)
check "XAMPP: sendmail_path al sendmail de Mailpit (127.0.0.1:1025) y auto_prepend_file al de WordPress" 'grep -q "^sendmail_path = \"$FAKE sendmail -S 127.0.0.1:$MAIL_SMTP_PORT\"" <<< "$X" && grep -q "^auto_prepend_file = \"$B/etc/lvm-correo-wordpress.php\"" <<< "$X"'
check "XAMPP: lo que tenia queda comentado (y lo comentado, igual)" 'grep -q "^; (lvm-instalador: correo de pruebas) sendmail_path = \"env -i" <<< "$X" && grep -q "^; (lvm-instalador: correo de pruebas) auto_prepend_file =" <<< "$X" && grep -q "^;sendmail_path = comentado" <<< "$X" && [ "$(grep -c "^sendmail_path" <<< "$X")" = 1 ]'
check "XAMPP: con los finales de linea del fichero (\\r\\n)" '[ "$(grep -c . "$(new "$out" etc/php.ini)")" = "$(grep -c $'"'"'\r$'"'"' "$(new "$out" etc/php.ini)")" ]'
check "el fichero de WordPress se escribe en la version, con el puerto" '[ -n "$(new "$out" etc/lvm-correo-wordpress.php)" ] && grep -q "Port = $MAIL_SMTP_PORT;" "$(new "$out" etc/lvm-correo-wordpress.php)"'
take "$out" etc/php.ini "$B"; take "$out" etc/lvm-correo-wordpress.php "$B"
out=$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$B" LVM_CORREO_PRUEBA=1)
check "XAMPP: una segunda pasada no cambia nada" '[ -z "$out" ]'
out=$(sp "$FAKE|$MAIL_SMTP_PORT|0" "$B" LVM_CORREO_PRUEBA=1)
X=$(cat "$(new "$out" etc/php.ini)" 2> /dev/null)
check "XAMPP: WordPress sin llevar a Mailpit: sin auto_prepend_file (vuelve el de antes)" 'grep -q "^sendmail_path = \"$FAKE" <<< "$X" && ! grep -q "lvm-correo-wordpress" <<< "$X" && grep -q "^auto_prepend_file =" <<< "$X"'
out=$(sp "" "$B")
check "XAMPP: apagado, el php.ini vuelve a ser exactamente el de antes" 'printf "%s" "$INI" | cmp -s - "$(new "$out" etc/php.ini)"'
printf '%s' "$INI" > "$B/etc/php.ini"
check "XAMPP: apagado y sin el bloque, nada que cambiar" '[ -z "$(sp "" "$B")" ]'
out=$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$S" LVM_CORREO_PRUEBA=1)
C=$(cat "$(new "$out" php/etc/conf.d/99-lvm-correo.ini)" 2> /dev/null)
check "pila propia: conf.d/99-lvm-correo.ini con sendmail_path y auto_prepend_file" 'grep -q "^sendmail_path = \"$FAKE sendmail -S 127.0.0.1:$MAIL_SMTP_PORT\"$" <<< "$C" && grep -q "^auto_prepend_file = \"$S/etc/lvm-correo-wordpress.php\"$" <<< "$C"'
take "$out" php/etc/conf.d/99-lvm-correo.ini "$S"; take "$out" etc/lvm-correo-wordpress.php "$S"
check "pila propia: una segunda pasada no cambia nada" '[ -z "$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$S" LVM_CORREO_PRUEBA=1)" ]'
out=$(sp "" "$S")
check "pila propia: apagado, el fichero queda sin directivas" '! grep -q "^[a-z]" "$(new "$out" php/etc/conf.d/99-lvm-correo.ini)"'
rm -f "$S/php/etc/conf.d/99-lvm-correo.ini"
check "pila propia: apagado y sin el fichero, nada que cambiar" '[ -z "$(sp "" "$S")" ]'
check "sin root: el binario y el fichero de WordPress no son de root, no se pone nada" '[ -z "$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$S")" ]'
check "al aplicar (como root) no vale la excepcion de las pruebas" '[ -z "$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$S" LVM_CORREO_PRUEBA=1 LVM_SECURE_APPLY=1)" ]'
check "un LVM_CORREO raro (otra directiva, ..) no se usa" '[ -z "$(sp "$FAKE\" -d x=1|1025|1" "$S" LVM_CORREO_PRUEBA=1)" ] && [ -z "$(sp "/opt/../tmp/m|1025|1" "$S" LVM_CORREO_PRUEBA=1)" ] && [ -z "$(sp "$FAKE|10;25|1" "$S" LVM_CORREO_PRUEBA=1)" ]'
ln -s /etc/passwd "$S/etc/lvm-correo-wordpress.php.x"
rm -f "$S/etc/lvm-correo-wordpress.php"; ln -s "$W/otro.php" "$S/etc/lvm-correo-wordpress.php"
out=$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$S" LVM_CORREO_PRUEBA=1)
check "un enlace en lugar del fichero de WordPress: ni se escribe ni se carga" '[ -z "$(new "$out" etc/lvm-correo-wordpress.php)" ] && ! grep -q auto_prepend "$(new "$out" php/etc/conf.d/99-lvm-correo.ini)"'
rm -f "$S/etc/lvm-correo-wordpress.php" "$S/etc/lvm-correo-wordpress.php.x"
check "secure_lampp y unsecured_versions le pasan el correo (y nunca la excepcion de las pruebas)" '[ "$(grep -c "LVM_CORREO=\$mail LVM_CORREO_PHP=\$MAIL_WP_PHP" "$SRC")" = 2 ] && grep -q "LVM_CORREO=\"\$mail\" LVM_CORREO_PHP=\"\$MAIL_WP_PHP\"" "$SRC" && [ "$(grep -c "LVM_CORREO_PRUEBA= " "$SRC")" = 2 ]'

# --- PHP: mail() hasta el Mailpit falso, y el fichero de WordPress
cat > "$FAKE" << 'EOF'
#!/bin/bash
# Mailpit falso: sendmail guarda el correo; si no, se queda en marcha (como el servidor)
d=$(dirname "$0")
if [ "$1" == sendmail ]; then
    shift
    printf '%s\n' "$*" > "$d/sendmail-args"
    cat > "$d/correo"
    exit 0
fi
printf '%s\n' "$*" > "$d/arranque"
env > "$d/entorno"
sleep 60 &
trap 'kill $!; exit 0' TERM
wait
EOF
chmod 755 "$FAKE"
out=$(sp "$FAKE|$MAIL_SMTP_PORT|1" "$S" LVM_CORREO_PRUEBA=1)
take "$out" php/etc/conf.d/99-lvm-correo.ini "$S"; take "$out" etc/lvm-correo-wordpress.php "$S"
if [ -n "$PHP" ]; then
    php -n -c "$S/php/etc/conf.d/99-lvm-correo.ini" -r 'var_export(mail("cliente@tienda.es", "Pedido 1", "Gracias", "From: tienda@tienda.es"));' > "$W/mail.out" 2>&1
    check "mail() de PHP va al sendmail de Mailpit (-S 127.0.0.1:1025) con el correo entero" '[ "$(cat "$W/mail.out")" = true ] && grep -q "^-S 127.0.0.1:$MAIL_SMTP_PORT" "$W/bin/sendmail-args" && grep -q "^To: cliente@tienda.es" "$W/bin/correo" && grep -q "^Subject: Pedido 1" "$W/bin/correo"'
    cat > "$W/wp-falso.php" << 'EOF'
<?php
// WordPress de mentira: como su plugin.php desde la 4.7, la lista de ganchos de antes (la del fichero
// de lvm-instalador) pasa a objetos por WP_Hook::build_preinitialized_hooks
class WP_Hook {
    public $callbacks = array();
    public static function build_preinitialized_hooks($filters) {
        $out = array();
        foreach ($filters as $tag => $groups) {
            $h = new WP_Hook();
            foreach ($groups as $prio => $cbs) { foreach ($cbs as $cb) { $h->add($cb['function'], $prio, $cb['accepted_args']); } }
            $out[$tag] = $h;
        }
        return $out;
    }
    public function add($f, $prio, $n) { $this->callbacks[$prio][] = array('function' => $f, 'accepted_args' => $n); ksort($this->callbacks); }
}
class WP_Error { public $code; public function __construct($c, $m) { $this->code = $c; } }
global $wp_filter;
$wp_filter = $wp_filter ? WP_Hook::build_preinitialized_hooks($wp_filter) : array();
function add_action($tag, $f, $prio = 10, $n = 1) {
    global $wp_filter;
    if (!isset($wp_filter[$tag])) { $wp_filter[$tag] = new WP_Hook(); }
    $wp_filter[$tag]->add($f, $prio, $n);
}
function apply_filters($tag, $value) {
    global $wp_filter;
    $args = func_get_args(); array_shift($args);
    if (!isset($wp_filter[$tag])) { return $value; }
    foreach ($wp_filter[$tag]->callbacks as $cbs) {
        foreach ($cbs as $cb) { $args[0] = $value; $value = call_user_func_array($cb['function'], array_slice($args, 0, $cb['accepted_args'])); }
    }
    return $value;
}
function do_action_ref_array($tag, $args) {
    global $wp_filter;
    foreach ($wp_filter[$tag]->callbacks as $cbs) { foreach ($cbs as $cb) { call_user_func_array($cb['function'], $args); } }
}
EOF
    cat > "$W/prueba-wp.php" << 'EOF'
<?php
// (con WPINC, el plugin.php de un WordPress de verdad; sin el, el de mentira)
if (getenv('WPINC')) { require getenv('WPINC') . '/plugin.php'; class WP_Error { public $code; public function __construct($c, $m) { $this->code = $c; } } }
else { require getenv('WP_FALSO'); }
class PHPMailer { public $Mailer = 'mail'; public $Host = 'localhost'; public $Port = 25; public $SMTPAuth = false; public $Username = ''; public $Password = ''; public $SMTPSecure = ''; public $SMTPAutoTLS = true; public function isSMTP() { $this->Mailer = 'smtp'; } }
// Un plugin de SMTP (WP Mail SMTP) con su servidor y otro que llega tarde
add_action('phpmailer_init', function ($m) { $m->isSMTP(); $m->Host = 'smtp-relay.brevo.com'; $m->Port = 587; $m->SMTPAuth = true; $m->Username = 'u'; $m->Password = 'p'; $m->SMTPSecure = 'tls'; }, 10);
add_action('phpmailer_init', function ($m) { $m->Host = 'smtp.otro.com'; }, 99999);
$m = new PHPMailer();
do_action_ref_array('phpmailer_init', array(&$m));
echo "$m->Mailer|$m->Host|$m->Port|" . var_export($m->SMTPAuth, true) . "|$m->Username|$m->SMTPSecure|" . var_export($m->SMTPAutoTLS, true) . "\n";
foreach (array('https://api.brevo.com/v3/smtp/email', 'https://api.sendinblue.com/v3/contacts', 'https://api.eu.mailgun.net/v3/x/messages', 'https://email.eu-west-1.amazonaws.com/', 'https://gmail.googleapis.com/gmail/v1/users/me/messages/send', 'https://api.wordpress.org/plugins/info/', 'https://brevo.com.ejemplo.es/', 'https://gmail.googleapis.com/oauth2/v4/token') as $u) {
    $r = apply_filters('pre_http_request', false, array(), $u);
    echo (is_object($r) ? 'corta' : 'pasa') . "\n";
}
EOF
    r=$(WP_FALSO=$W/wp-falso.php php -n -c "$S/php/etc/conf.d/99-lvm-correo.ini" "$W/prueba-wp.php" 2>&1)
    check "WordPress (de mentira): phpmailer_init, el ultimo, a Mailpit sin usuario ni cifrado" '[ "$(head -1 <<< "$r")" = "smtp|127.0.0.1|$MAIL_SMTP_PORT|false||false|false" ] || [ "$(head -1 <<< "$r")" = "smtp|127.0.0.1|$MAIL_SMTP_PORT|false|||false" ]'
    check "WordPress (de mentira): corta las API de correo (Brevo, Sendinblue, Mailgun, SES, Gmail) y deja las demas" '[ "$(tail -n +2 <<< "$r" | tr "\n" " ")" = "corta corta corta corta corta pasa pasa pasa " ]'
    WPI=$(ls -d "${LVM_HTDOCS:-/opt/htdocs}"/*/wp-includes 2> /dev/null | while read -r d; do [ -f "$d/class-wp-hook.php" ] && echo "$d" && break; done)
    if [ -n "$WPI" ]; then
        r=$(WPINC=$WPI php -n -c "$S/php/etc/conf.d/99-lvm-correo.ini" "$W/prueba-wp.php" 2>&1)
        check "WordPress de verdad ($(basename "$(dirname "$WPI")")): su plugin.php recoge los ganchos y van a Mailpit" '[[ "$(head -1 <<< "$r")" == "smtp|127.0.0.1|$MAIL_SMTP_PORT|false|"*"|false" ]] && [ "$(tail -n +2 <<< "$r" | tr "\n" " ")" = "corta corta corta corta corta pasa pasa pasa " ]'
    fi
    # (auto_prepend_file no vale con -r: un script)
    echo '<?php echo isset($GLOBALS["wp_filter"]["phpmailer_init"]) ? "ganchos" : "nada", "|", function_exists("add_action") ? "wp" : "sin wp", "\n";' > "$W/otro.php"
    r=$(php -n -c "$S/php/etc/conf.d/99-lvm-correo.ini" "$W/otro.php" 2>&1)
    check "fuera de WordPress (PrestaShop, phpMyAdmin) no hace nada mas: sin errores ni funciones" '[ "$r" = "ganchos|sin wp" ]'
    for v in 7.1.33 7.4; do
        [ -x "/opt/lampp-$v/bin/php" ] || continue
        r=$(LD_LIBRARY_PATH=/opt/lampp-$v/lib "/opt/lampp-$v/bin/php" -n -l "$S/etc/lvm-correo-wordpress.php" 2>&1)
        check "el fichero de WordPress vale para PHP $v (php -l)" 'grep -q "No syntax errors" <<< "$r"'
    done
else
    echo "  ok    (sin PHP: no se prueba mail() ni el fichero de WordPress)"
fi

# --- Mailpit en marcha y parado con la version (con el falso)
extract "$SRC" mail_on mail_wp_mode mailpit_installed mailpit_installed_version mail_secure_spec mailpit_pid mailpit_start mailpit_stop mailpit_sync || exit 1
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
o=$(MP_SMTP_RELAY_ALL=true mailpit_sync)
p=$(mailpit_pid)
check "con la version en marcha arranca, con tu usuario y su .pid" '[ -n "$p" ] && [ "$(cat "$MAILPIT_DATA/mailpit.pid")" = "$p" ] && [ "$(stat -c %U "/proc/$p")" = "$(id -un)" ] && grep -q "en marcha" <<< "$o"'
check "sus datos en ~/.lvm-instalador/mailpit (700) y como mucho $MAILPIT_MAX correos" '[ "$(stat -c %a "$MAILPIT_DATA")" = 700 ] && grep -q -- "--database $MAILPIT_DATA/mailpit.db --max $MAILPIT_MAX" "$W/bin/arranque"'
check "solo 127.0.0.1 (SMTP y web) y sin las variables MP_* de la sesion" 'grep -q -- "--smtp 127.0.0.1:$MAIL_SMTP_PORT --listen 127.0.0.1:$MAIL_UI_PORT" "$W/bin/arranque" && ! grep -q "^MP_" "$W/bin/entorno"'
mailpit_sync > /dev/null
check "otra vez: no arranca otro" '[ "$(pgrep -u "$(id -u)" -fc -- "$FAKE --smtp")" = 1 ]'
rm -f "$MAILPIT_DATA/mailpit.pid"
check "sin su .pid tambien lo encuentra" '[ "$(mailpit_pid)" = "$p" ]'
echo $$ > "$MAILPIT_DATA/mailpit.pid"
check "un .pid de otro proceso no vale" '[ "$(mailpit_pid)" = "$p" ]'
: > "$MAIL_OFF_FILE"
o=$(mailpit_sync)
check "al apagar el correo de pruebas se para" '[ -z "$(mailpit_pid)" ] && ! kill -0 "$p" 2> /dev/null && grep -q parado <<< "$o"'
rm -f "$MAIL_OFF_FILE"
mailpit_sync > /dev/null; p=$(mailpit_pid)
lampp_running() { false; }
mailpit_sync > /dev/null
check "al parar la version se para" '[ -n "$p" ] && ! kill -0 "$p" 2> /dev/null && [ -z "$(mailpit_pid)" ]'
check "arranca y para con la version: use, arrancar/parar, disable, servicio, cargar-proyecto y la ventana" '[ "$(grep -c "^    mailpit_sync$" "$SRC")" -ge 6 ] && grep -q "mailpit_sync --suave > /dev/null 2>&1" "$SRC"'
# Otro programa en su puerto: no arranca y, desde la ventana (--suave), no se reintenta en 5 minutos
printf '#!/bin/bash\nexit 1\n' > "$W/bin/mailpit-malo"; chmod 755 "$W/bin/mailpit-malo"
lampp_running() { true; }
o=$(MAILPIT_BIN=$W/bin/mailpit-malo mailpit_sync)
check "si no arranca (puerto ocupado) lo dice" 'grep -q "no ha arrancado" <<< "$o" && [ -e "$MAILPIT_DATA/no-arranca" ]'
s0=$(date +%s%N); MAILPIT_BIN=$W/bin/mailpit-malo mailpit_sync --suave > /dev/null; s1=$(date +%s%N)
check "desde la ventana (--suave) no se reintenta enseguida" '[ $(( (s1 - s0) / 1000000 )) -lt 1000 ]'
lampp_running() { false; }

# --- Instalar Mailpit (sin red: un .tar.gz de prueba) y la orden correo
mkdir -p "$W/tar" "$W/prueba" "$W/config" "$W/htdocs" "$W/home2"
cp "$FAKE" "$W/tar/mailpit"; echo "MIT" > "$W/tar/LICENSE"
tar -czf "$W/mailpit.tar.gz" -C "$W/tar" mailpit LICENSE
SHA=$(sha256sum "$W/mailpit.tar.gz" | cut -d' ' -f1)
: > "$W/config/httpd-vhosts.conf"
lvm() { env -u LVM_SIMULAR HOME="$W/home2" LVM_PRUEBA="$W/prueba" LVM_VHOSTS="$W/config/httpd-vhosts.conf" LVM_HTDOCS="$W/htdocs" \
    LVM_BD_CLIENTE=/bin/false LVM_MAILPIT_URL="${MP_URL:-file://$W/mailpit.tar.gz}" LVM_UI=text bash "$SRC" "$@" < /dev/null 2>&1; }
o=$(lvm correo)
check "correo estado: encendido por defecto, WordPress a Mailpit y Mailpit sin instalar" 'grep -q "^Correo de pruebas encendido" <<< "$o" && grep -q "siguen, con su correo a Mailpit" <<< "$o" && grep -q "no esta instalado" <<< "$o"'
o=$(lvm correo no)
check "correo no: apagado (con su fichero)" '[ -e "$W/home2/.lvm-instalador/correo-apagado" ] && grep -q "apagado" <<< "$o"'
o=$(lvm --simular correo si)
check "--simular correo si no cambia nada" '[ -e "$W/home2/.lvm-instalador/correo-apagado" ] && grep -q simulacion <<< "$o"'
o=$(LVM_MAILPIT_SHA=$(printf '0%.0s' {1..64}) lvm correo instalar)
check "una descarga con otra sha256 no se instala" '[ ! -e "$W/config/mailpit/mailpit" ] && grep -q "no coincide con su suma sha256" <<< "$o"'
o=$(LVM_MAILPIT_SHA=$SHA lvm correo instalar)
check "con su sha256, instalado en la carpeta de la configuracion compartida (con su version y licencia)" '[ -x "$W/config/mailpit/mailpit" ] && cmp -s "$W/config/mailpit/mailpit" "$FAKE" && [ "$(cat "$W/config/mailpit/version")" = "$MAILPIT_VERSION" ] && [ -f "$W/config/mailpit/LICENSE" ] && grep -q "esta apagado" <<< "$o"'
check "no queda nada de la descarga" '[ -z "$(ls -d "$W"/home2/.lvm-instalador/mailpit-descarga.* "$W"/prueba/lvm-mailpit.* 2> /dev/null)" ]'
o=$(LVM_MAILPIT_SHA=$SHA lvm correo instalar)
check "otra vez: ya esta instalado" 'grep -q "ya esta instalado" <<< "$o"'
# Un paquete con el programa como ./mailpit y sin licencia (1.55.1: se abre entero y se busca)
rm -rf "$W/config/mailpit"; mkdir -p "$W/tar2"; cp "$FAKE" "$W/tar2/mailpit"
tar -czf "$W/mailpit2.tar.gz" -C "$W/tar2" ./mailpit
o=$(MP_URL="file://$W/mailpit2.tar.gz" LVM_MAILPIT_SHA=$(sha256sum "$W/mailpit2.tar.gz" | cut -d' ' -f1) lvm correo instalar)
check "paquete con ./mailpit y sin licencia: instalado igual" '[ -x "$W/config/mailpit/mailpit" ] && cmp -s "$W/config/mailpit/mailpit" "$FAKE" && [ ! -e "$W/config/mailpit/LICENSE" ]'
# Un paquete roto: no se instala y dice el error de tar y desde donde descargarlo
rm -rf "$W/config/mailpit"; echo "no es un tar" > "$W/roto.tar.gz"
o=$(MP_URL="file://$W/roto.tar.gz" LVM_MAILPIT_SHA=$(sha256sum "$W/roto.tar.gz" | cut -d' ' -f1) lvm correo instalar)
check "paquete roto: no se instala, con el error de tar y la pagina de descarga" '[ ! -e "$W/config/mailpit/mailpit" ] && grep -q "No se ha podido abrir el paquete de Mailpit" <<< "$o" && grep -q "releases/tag/v" <<< "$o"'
o=$(LVM_MAILPIT_SHA=$SHA lvm correo instalar)
check "sin LVM_PRUEBA no se hace caso de LVM_MAILPIT_URL ni LVM_MAILPIT_SHA" 'grep -q "LVM_MAILPIT_URL" <<< "$(sed -n "/^if \[ -z \"\$TEST_DIR\" \]; then/,/^fi/p" "$SRC")" && grep -q "LVM_MAILPIT_SHA" <<< "$(sed -n "/^if \[ -z \"\$TEST_DIR\" \]; then/,/^fi/p" "$SRC")"'
o=$(lvm correo wordpress desactivar)
check "correo wordpress desactivar: se guarda" '[ "$(cat "$W/home2/.lvm-instalador/correo-wordpress")" = desactivar ] && grep -q "se desactivan en la copia local" <<< "$o"'
o=$(lvm correo wordpress todo)
check "correo wordpress con un modo raro: uso, sin cambiar nada" '[ "$(cat "$W/home2/.lvm-instalador/correo-wordpress")" = desactivar ] && grep -q "^Uso" <<< "$o"'
o=$(lvm correo raro)
check "correo con una orden rara: uso" 'grep -q "^Uso: lvm-instalador correo" <<< "$o"'
check "la ayuda y la ventana conocen la orden correo" 'grep -q "^#   lvm-instalador correo \[estado\]" "$SRC" && grep -q "^    correo) mail_command" "$SRC" && grep -q "\[\"correo\", \"wordpress\", mode\]" "$SRC"'

# --- BBDD: WordPress y PrestaShop contra un MariaDB temporal
if [ ! -x /opt/lampp-8.2.4/sbin/mysqld ]; then
    echo "  ok    (sin /opt/lampp-8.2.4: no se prueban las BBDD)"
    exit $fail
fi
MDB=$W/db; mkdir -p "$MDB"
SOCKD=$MDB; [ ${#SOCKD} -gt 80 ] && SOCKD=$(mktemp -d /tmp/lvm-correo.XXXX)
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
extract "$SRC" mail_db_rows mail_db mail_export_filter || exit 1
m() { "$DB_CLIENT" -uroot -N "$@"; }
# Plugins de una opcion serializada, ordenados
plugins() { m "$1" -e "SELECT option_value FROM $2 WHERE option_name = 'active_plugins'" | grep -o 's:[0-9]*:"[^"]*"' | sed 's/^s:[0-9]*:"//; s/"$//' | grep -E '/|\.php$' | sort | tr '\n' ' '; }
opt() { m "$1" -e "SELECT option_value FROM $2 WHERE option_name = '$3'"; }
psv() { m "$1" -e "SELECT IFNULL(GROUP_CONCAT(IFNULL(value, 'NULL') ORDER BY id_configuration), '') FROM ps_configuration WHERE name = '$2'"; }
ser() { python3 -I -c 'import sys, re
items = sys.argv[1:]
print("a:%d:{" % len(items) + "".join("i:%d;s:%d:\"%s\";" % (n, len(p), p) for n, p in enumerate(items)) + "}")' "$@"; }
m -e "CREATE DATABASE cliente"
WMS='a:2:{s:4:"mail";a:2:{s:6:"mailer";s:10:"sendinblue";s:10:"from_email";s:14:"web@cliente.es";}s:10:"sendinblue";a:1:{s:7:"api_key";s:12:"xkeysib-1234";}}'
EWS='a:1:{s:4:"mail";a:1:{s:6:"mailer";s:4:"smtp";}}'
m cliente << SQL
CREATE TABLE wp_options (option_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, option_name VARCHAR(191) NOT NULL UNIQUE, option_value LONGTEXT NOT NULL, autoload VARCHAR(20) NOT NULL DEFAULT 'yes') DEFAULT CHARSET=utf8mb4;
CREATE TABLE wp_users (ID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, user_login VARCHAR(60));
CREATE TABLE wp_sitemeta (meta_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, site_id BIGINT UNSIGNED NOT NULL DEFAULT 0, meta_key VARCHAR(255), meta_value LONGTEXT);
CREATE TABLE wp_2_options LIKE wp_options;
INSERT INTO wp_options (option_name, option_value) VALUES ('siteurl', 'https://cliente.es'),
    ('active_plugins', '$(ser akismet/akismet.php mailin/sendinblue.php wp-mail-smtp/wp_mail_smtp.php fluent-smtp/fluent-smtp.php woocommerce/woocommerce.php)'),
    ('wp_mail_smtp', '$WMS');
INSERT INTO wp_2_options (option_name, option_value) VALUES ('active_plugins', '$(ser easy-wp-smtp/easy-wp-smtp.php post-smtp/postman-smtp.php)'), ('easy_wp_smtp', '$EWS');
INSERT INTO wp_sitemeta (site_id, meta_key, meta_value) VALUES (1, 'active_sitewide_plugins', 'a:2:{s:21:"mailin/sendinblue.php";i:1700000000;s:19:"akismet/akismet.php";i:1;}');
CREATE TABLE ps_configuration (id_configuration INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, id_shop_group INT UNSIGNED NULL, id_shop INT UNSIGNED NULL,
    name VARCHAR(254) NOT NULL, value TEXT NULL, date_add DATETIME NOT NULL, date_upd DATETIME NOT NULL) DEFAULT CHARSET=utf8mb4;
INSERT INTO ps_configuration (id_shop_group, id_shop, name, value, date_add, date_upd) VALUES
    (NULL, NULL, 'PS_MAIL_METHOD', '1', NOW(), NOW()), (1, 2, 'PS_MAIL_METHOD', '3', NOW(), NOW()),
    (NULL, NULL, 'PS_MAIL_SERVER', 'smtp-relay.brevo.com', NOW(), NOW()), (NULL, NULL, 'PS_MAIL_USER', 'tienda@cliente.es', NOW(), NOW()),
    (NULL, NULL, 'PS_MAIL_PASSWD', NULL, NOW(), NOW()), (NULL, NULL, 'PS_MAIL_SMTP_PORT', '587', NOW(), NOW()), (NULL, NULL, 'PS_SHOP_EMAIL', 'tienda@cliente.es', NOW(), NOW());
SQL
ORIG_AP=$(plugins cliente wp_options)
sum() { m cliente -e "CHECKSUM TABLE wp_options, wp_2_options, wp_sitemeta, ps_configuration" | awk '{print $2}' | tr '\n' ' '; }
ORIG_SUM=$(sum)
o=$(mail_db cliente)
check "mail_db (WordPress a Mailpit): dice lo que cambia" 'grep -q "desactivados en la copia local: Brevo, FluentSMTP" <<< "$o" && grep -q "WP Mail SMTP mandaba por sendinblue" <<< "$o" && grep -q "PrestaShop (ps_configuration): correo por SMTP a Mailpit" <<< "$o"'
check "WordPress: fuera Brevo y FluentSMTP (API), siguen WP Mail SMTP y los demas" '[ "$(plugins cliente wp_options)" = "akismet/akismet.php woocommerce/woocommerce.php wp-mail-smtp/wp_mail_smtp.php " ]'
check "WP Mail SMTP: de Brevo (API) a mail(), sin perder su configuracion" 'grep -q "s:6:\"mailer\";s:4:\"mail\";" <<< "$(opt cliente wp_options wp_mail_smtp)" && grep -q "xkeysib-1234" <<< "$(opt cliente wp_options wp_mail_smtp)" && grep -q "web@cliente.es" <<< "$(opt cliente wp_options wp_mail_smtp)"'
check "multisitio: Brevo fuera de los activados en toda la red, el resto igual" '[ "$(m cliente -e "SELECT meta_value FROM wp_sitemeta")" = "a:1:{s:19:\"akismet/akismet.php\";i:1;}" ]'
check "otro sitio (wp_2_): fuera Post SMTP; Easy WP SMTP por SMTP sigue igual" '[ "$(plugins cliente wp_2_options)" = "easy-wp-smtp/easy-wp-smtp.php " ] && [ "$(opt cliente wp_2_options easy_wp_smtp)" = "$EWS" ]'
check "PrestaShop: SMTP a 127.0.0.1:1025 sin usuario ni cifrado, en todas las tiendas" '[ "$(psv cliente PS_MAIL_METHOD)" = "2,2" ] && [ "$(psv cliente PS_MAIL_SERVER)" = 127.0.0.1 ] && [ "$(psv cliente PS_MAIL_SMTP_PORT)" = "$MAIL_SMTP_PORT" ] && [ "$(psv cliente PS_MAIL_USER)" = "" ] && [ "$(psv cliente PS_MAIL_PASSWD)" = "" ] && [ "$(psv cliente PS_MAIL_SMTP_ENCRYPTION)" = off ]'
check "PrestaShop: lo demas, igual" '[ "$(psv cliente PS_SHOP_EMAIL)" = tienda@cliente.es ] && [ "$(opt cliente wp_options siteurl)" = https://cliente.es ]'
check "lo cambiado queda apuntado en $MAIL_TABLE" '[ "$(m cliente -e "SELECT COUNT(*) FROM $MAIL_TABLE")" -ge 10 ]'
SUM1=$(sum); N1=$(m cliente -e "SELECT COUNT(*) FROM $MAIL_TABLE")
mail_db cliente > /dev/null
check "otra vez (otra carga): nada cambia" '[ "$(sum)" = "$SUM1" ] && [ "$(m cliente -e "SELECT COUNT(*) FROM $MAIL_TABLE")" = "$N1" ]'
# En local se activa otro plugin y se cambia el remitente
m cliente -e "UPDATE wp_options SET option_value = '$(ser akismet/akismet.php woocommerce/woocommerce.php wp-mail-smtp/wp_mail_smtp.php hello.php)' WHERE option_name = 'active_plugins'"
# Una fila apuntada a mano (de un volcado manipulado) sobre otra opcion: no se hace caso
m cliente -e "INSERT INTO $MAIL_TABLE (tabla, fila, clave, tipo, ruta, original, puesto) SELECT 'wp_options', option_id, 'siteurl', 'valor', '', 'https://malo.es', option_value FROM wp_options WHERE option_name = 'siteurl'"
# --- La copia (lo que hace export_database): sin la tabla y con lo de antes
query=("$DB_CLIENT" -uroot -N) skip=() mail_sql=""
mail_export_filter cliente
check "copia: la tabla apuntada se queda fuera y hay SQL con lo de antes" '[ "${skip[*]}" = "--ignore-table=cliente.$MAIL_TABLE" ] && grep -q "^UPDATE \`wp_options\`" <<< "$mail_sql" && grep -q "^DELETE FROM \`ps_configuration\`" <<< "$mail_sql"'
{ "$MDB/dump" -uroot --single-transaction --quick --triggers "${skip[@]}" cliente; printf '%s\n' "$mail_sql"; } > "$MDB/copia.sql" 2> "$MDB/dump.err"
check "el volcado no lleva la tabla ni los valores locales del correo" '[ ! -s "$MDB/dump.err" ] && ! grep -q "CREATE TABLE \`$MAIL_TABLE\`" "$MDB/copia.sql"'
m -e "CREATE DATABASE copia"; m copia < "$MDB/copia.sql"
check "copia: los plugins de antes vuelven (y el activado en local se queda)" '[ "$(plugins copia wp_options)" = "akismet/akismet.php fluent-smtp/fluent-smtp.php hello.php mailin/sendinblue.php woocommerce/woocommerce.php wp-mail-smtp/wp_mail_smtp.php " ]'
check "copia: WP Mail SMTP otra vez con Brevo, multisitio y wp_2_ como estaban" '[ "$(opt copia wp_options wp_mail_smtp)" = "$WMS" ] && grep -q "mailin/sendinblue.php\";i:1700000000;" <<< "$(m copia -e "SELECT meta_value FROM wp_sitemeta")" && [ "$(plugins copia wp_2_options)" = "easy-wp-smtp/easy-wp-smtp.php post-smtp/postman-smtp.php " ]'
check "copia: el correo de PrestaShop de produccion (NULL incluido) y sin la fila nueva" '[ "$(psv copia PS_MAIL_METHOD)" = "1,3" ] && [ "$(psv copia PS_MAIL_SERVER)" = smtp-relay.brevo.com ] && [ "$(psv copia PS_MAIL_USER)" = tienda@cliente.es ] && [ "$(psv copia PS_MAIL_PASSWD)" = NULL ] && [ "$(psv copia PS_MAIL_SMTP_PORT)" = 587 ] && [ -z "$(psv copia PS_MAIL_SMTP_ENCRYPTION)" ]'
check "copia: sin $MAIL_TABLE y la fila apuntada a mano no cambia nada" '! m copia -e "SHOW TABLES" | grep -qx "$MAIL_TABLE" && [ "$(opt copia wp_options siteurl)" = https://cliente.es ]'
check "la BBDD de trabajo sigue con el correo a Mailpit" '[ "$(psv cliente PS_MAIL_SERVER)" = 127.0.0.1 ] && grep -q "s:4:\"mail\";" <<< "$(opt cliente wp_options wp_mail_smtp)"'
query=("$DB_CLIENT" -uroot -N) skip=() mail_sql=""
mail_export_filter copia
check "una BBDD sin el correo de pruebas: se descarga como siempre" '[ ${#skip[@]} -eq 0 ] && [ -z "$mail_sql" ]'
check "export_database lo usa (en el volcado, al final)" 'grep -q "^    mail_export_filter \"\$db\"$" "$SRC" && grep -q "printf .%s\\\\n. \"\$mail_sql\"" "$SRC"'
check "al cargar una BBDD (importar-bd, copiar-bd) y un proyecto se aplica" 'grep -q "^    mail_db \"\$db\"$" "$SRC" && grep -q "mail_db \"\$mdb\"" "$SRC"'
# --- Desactivarlos todos
echo desactivar > "$MAIL_WP_FILE"
o=$(mail_db cliente)
check "modo desactivar: tambien WP Mail SMTP fuera (y su servicio, como estaba)" '[ "$(plugins cliente wp_options)" = "akismet/akismet.php hello.php woocommerce/woocommerce.php " ] && [ "$(opt cliente wp_options wp_mail_smtp)" = "$WMS" ] && [ "$(plugins cliente wp_2_options)" = "" ]'
check "modo desactivar: PrestaShop tambien a Mailpit" '[ "$(psv cliente PS_MAIL_SERVER)" = 127.0.0.1 ]'
# --- No tocarlos: vuelve lo de antes (lo de produccion) y la tabla desaparece
echo nada > "$MAIL_WP_FILE"
o=$(mail_db cliente)
check "modo nada: vuelve todo lo de antes y se dice" '[ "$(plugins cliente wp_options)" = "akismet/akismet.php fluent-smtp/fluent-smtp.php hello.php mailin/sendinblue.php woocommerce/woocommerce.php wp-mail-smtp/wp_mail_smtp.php " ] && [ "$(psv cliente PS_MAIL_METHOD)" = "1,3" ] && [ "$(psv cliente PS_MAIL_PASSWD)" = NULL ] && grep -q "deshecho" <<< "$o"'
check "modo nada: sin $MAIL_TABLE y sin las filas nuevas de PrestaShop" '! m cliente -e "SHOW TABLES" | grep -qx "$MAIL_TABLE" && [ -z "$(psv cliente PS_MAIL_SMTP_ENCRYPTION)" ]'
o=$(mail_db cliente)
check "modo nada otra vez: nada que hacer" '[ -z "$o" ] && ! m cliente -e "SHOW TABLES" | grep -qx "$MAIL_TABLE"'
# --- Encendido otra vez y apagado
rm -f "$MAIL_WP_FILE"
mail_db cliente > /dev/null
m cliente -e "UPDATE wp_options SET option_value = '$(ser akismet/akismet.php mailin/sendinblue.php wp-mail-smtp/wp_mail_smtp.php fluent-smtp/fluent-smtp.php woocommerce/woocommerce.php)' WHERE option_name = 'active_plugins'"
mail_db cliente > /dev/null
: > "$MAIL_OFF_FILE"
o=$(mail_db cliente)
check "apagado: la BBDD vuelve a ser la de antes del correo de pruebas" '[ "$(sum)" = "$ORIG_SUM" ] || [ "$(plugins cliente wp_options)" = "$ORIG_AP" -a "$(psv cliente PS_MAIL_SERVER)" = smtp-relay.brevo.com -a "$(opt cliente wp_options wp_mail_smtp)" = "$WMS" ]'
check "apagado: sin $MAIL_TABLE" '! m cliente -e "SHOW TABLES" | grep -qx "$MAIL_TABLE"'
rm -f "$MAIL_OFF_FILE"
m -e "CREATE DATABASE vacia"
check "una BBDD sin WordPress ni PrestaShop: nada" '[ -z "$(mail_db vacia)" ] && ! m vacia -e "SHOW TABLES" | grep -q .'
check "una base con un nombre raro no se toca" '! mail_db "x;DROP" > /dev/null'
exit $fail
