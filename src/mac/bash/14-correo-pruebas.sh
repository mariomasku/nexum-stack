# ===========================================================================
# Correo de pruebas: Mailpit
# ===========================================================================
# Lo que mandan las webs locales (formularios, pedidos, contraseñas) no puede llegar a nadie: con las
# BBDD copiadas de los clientes, un pedido de prueba avisaria al cliente real. Con el correo de pruebas
# encendido (por defecto), todo va a Mailpit (https://github.com/axllent/mailpit, MIT), que lo guarda
# y lo enseña en http://127.0.0.1:8025/:
#   - mail() de PHP en todas las versiones (sendmail_path al sendmail de Mailpit; SECURE_PY)
#   - WordPress con plugins de SMTP o Brevo, segun MAIL_WP_FILE: mailpit (los de SMTP siguen, pero
#     con su correo a Mailpit: etc/lvm-correo-wordpress.php en auto_prepend_file; los que mandan por
#     una API se desactivan en la copia local), desactivar (todos fuera de la copia local, con lo que
#     WordPress usa mail()) o nada (no se tocan: el correo puede salir de verdad)
#   - PrestaShop: su configuracion de correo, por SMTP a Mailpit (en la copia local)
# Los cambios en las BBDD se apuntan (con lo que habia) en la tabla MAIL_TABLE de la propia base: se
# deshacen al apagarlo y no salen en las copias (exportar-bd, copiar-bd, Docker). Mailpit va con la
# version activa: arranca y para con ella, con tu usuario y solo en 127.0.0.1. (Los proyectos de
# Docker Desktop aun no: podrian mandar a host.docker.internal:1025, pero Mailpit solo escucha en
# 127.0.0.1; sus BBDD, como las copias, llevan el correo de produccion)
# Version fijada y sha256 de cada .tar.gz de macOS (de los digest de la publicacion en GitHub,
# comprobados al descargarlos el 25/10/2026). La 1.32.0 arregla fallos de seguridad (GHSA-379p-g4f4-hq5h)
MAILPIT_VERSION="1.32.0"
MAILPIT_SHA_ARM64="23709bd727f20da2290de6a2a40c4685c48a3127586d77370efd1a3a595f9ef6"
MAILPIT_SHA_AMD64="d7f3d0964cd2ea4c2a7d10660a12e02876718e67d88ced390d9cd90350a453da"
# El programa, de root en /Library/Nexum/mailpit (junto al gestor y XAMPP-compartido, cada carpeta
# hasta / de root y sin escritura para el grupo admin): ni tu usuario ni una web pueden cambiar lo que
# ejecuta PHP al mandar un correo. Sus datos, solo tuyos
MAILPIT_DIR=$BASE_DIR/mailpit
MAILPIT_BIN=$MAILPIT_DIR/mailpit
MAILPIT_DATA=$LOG_DIR/mailpit
MAILPIT_MAX=500
MAIL_SMTP_PORT=1025
MAIL_UI_PORT=8025
MAIL_UI_URL="http://127.0.0.1:$MAIL_UI_PORT/"
# Encendido salvo que exista MAIL_OFF_FILE; el modo de WordPress, en MAIL_WP_FILE (mailpit si no hay)
MAIL_OFF_FILE=$LOG_DIR/correo-apagado
MAIL_WP_FILE=$LOG_DIR/correo-wordpress
MAIL_TABLE=lvm_correo_original

# etc/lvm-correo-wordpress.php de cada version (lo escribe SECURE_PY como root; @PUERTO@, el SMTP de
# Mailpit). El mismo que en Linux: vale desde PHP 7.1
MAIL_WP_PHP=$(cat <<'PHP'
<?php
// lvm-instalador (Nexum Dev Stack): correo de pruebas de WordPress. Lo pone root y PHP lo carga antes
// de cada script de esta version (auto_prepend_file) mientras el correo de pruebas esta encendido y
// los plugins de SMTP de WordPress van a Mailpit. Fuera de WordPress no hace nada: solo deja dos
// ganchos en la lista que WordPress lee al arrancar (desde la 4.7 la pasa a WP_Hook con
// WP_Hook::build_preinitialized_hooks; las anteriores la usan tal cual).
//  - phpmailer_init, el ultimo: lo que sale por PHPMailer (wp_mail y los plugins de SMTP que lo usan:
//    WP Mail SMTP, Easy WP SMTP, SMTP Mailer, WP SMTP...) va al SMTP de Mailpit, sin usuario ni cifrado
//  - pre_http_request: no se llama a las API de envio de correo (Brevo, SendGrid, Mailgun...)
if (!isset($GLOBALS['wp_filter']) || is_array($GLOBALS['wp_filter'])) {
    $GLOBALS['wp_filter']['phpmailer_init'][PHP_INT_MAX][] = array(
        'function' => function ($mailer) {
            if (!is_object($mailer) || !method_exists($mailer, 'isSMTP')) {
                return;
            }
            $mailer->isSMTP();
            $mailer->Host = '127.0.0.1';
            $mailer->Port = @PUERTO@;
            $mailer->SMTPAuth = false;
            $mailer->Username = '';
            $mailer->Password = '';
            $mailer->SMTPSecure = '';
            $mailer->SMTPAutoTLS = false;
        },
        'accepted_args' => 1,
    );
    $GLOBALS['wp_filter']['pre_http_request'][PHP_INT_MAX][] = array(
        'function' => function ($pre, $args = array(), $url = '') {
            $host = strtolower((string) parse_url((string) $url, PHP_URL_HOST));
            $path = strtolower((string) parse_url((string) $url, PHP_URL_PATH));
            // dominio => parte de la ruta ('' = cualquiera)
            $apis = array(
                'brevo.com' => '', 'sendinblue.com' => '', 'sendgrid.com' => '', 'sendgrid.net' => '',
                'mailgun.net' => '', 'postmarkapp.com' => '', 'sparkpost.com' => '', 'mailjet.com' => '',
                'smtp2go.com' => '', 'resend.com' => '', 'mailersend.com' => '', 'elasticemail.com' => '',
                'sendlayer.com' => '', 'smtp.com' => '', 'mandrillapp.com' => '', 'zeptomail.com' => '',
                'zeptomail.eu' => '', 'sendpulse.com' => '', 'pepipost.com' => '', 'netcorecloud.net' => '',
                'socketlabs.com' => '', 'gmail.googleapis.com' => '/send', 'graph.microsoft.com' => '/sendmail',
                'mail.zoho.com' => '/messages', 'mail.zoho.eu' => '/messages',
            );
            $hit = (bool) preg_match('/^email(-smtp)?\.[a-z0-9-]+\.amazonaws\.com$/', $host);
            foreach ($apis as $api => $part) {
                if (($host === $api || substr($host, -strlen($api) - 1) === '.' . $api)
                        && ($part === '' || strpos($path, $part) !== false)) {
                    $hit = true;
                }
            }
            if ($hit && class_exists('WP_Error')) {
                return new WP_Error('lvm_correo', 'Correo de pruebas (lvm-instalador): en este equipo no se llama a '
                    . 'las API de envio de correo; lo que se mande va a Mailpit.');
            }
            return $pre;
        },
        'accepted_args' => 3,
    );
}
PHP
)

#@incluir comun/correo-pruebas/mail_on.sh
# ¿Es <pid> un Mailpit del gestor tuyo? Sin /proc: su usuario y su orden, de ps, que empieza por el
# binario y --smtp (el Python que lo arranca, antes de pasar a ser Mailpit, no vale)
function mailpit_is() {
    local uid cmd
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 1 ] || return 1
    read -r uid cmd < <(ps -o uid=,command= -p "$1" 2> /dev/null)
    [ "$uid" == "$(id -u)" ] && [[ "$cmd" == "$MAILPIT_BIN --smtp "* ]]
}

# Mailpit del gestor en marcha con tu usuario (pgrep, por el principio de su orden)
function mailpit_find() {
    pgrep -u "$(id -u)" -f -- "^$MAILPIT_BIN --smtp " 2> /dev/null | head -1
}

# Numero del proceso de Mailpit: el de su .pid si es tuyo y es el del gestor o, si se ha perdido, el
# que este en marcha con su binario
function mailpit_pid() {
    local p
    p=$(head -c 20 "$MAILPIT_DATA/mailpit.pid" 2> /dev/null | tr -d ' \n')
    if mailpit_is "$p"; then
        echo "$p"
        return 0
    fi
    p=$(mailpit_find)
    [ -n "$p" ] && echo "$p"
}

# Arranca Mailpit con tu usuario (nunca como root): SMTP y web solo en 127.0.0.1, la web solo con su
# direccion (Mailpit rechaza otro Host: una web cuyo dominio apunte a 127.0.0.1, DNS rebinding, no
# puede leer los correos; y las peticiones de otras webs que cambian algo, por su Origin), sin buscar
# versiones nuevas, sin CSS ni fuentes de fuera en los correos y como mucho MAILPIT_MAX. Con el entorno
# limpio: Mailpit lee su configuracion de las variables MP_* (una MP_SMTP_RELAY_ALL de tu sesion
# mandaria los correos de verdad).
# En el Mac no hay setsid: lo hace el Python del sistema (os.setsid y exec), para que no siga en la
# sesion de la terminal de la tarea. Y sin quedarse con ella: la entrada de /dev/null y la salida a un
# fichero (con la terminal abierta, la ventana se quedaria esperando el final de la tarea)
MAILPIT_SETSID_PY='
import os, sys
# (si ya fuera el primero de su grupo, setsid no se puede: antes, un proceso hijo)
try:
    os.setsid()
except OSError:
    if os.fork():
        os._exit(0)
    os.setsid()
os.execv(sys.argv[1], sys.argv[1:])
'
function mailpit_start() {
    local p="" i
    [ -n "$(mailpit_pid)" ] && return 0
    mailpit_installed || return 1
    [ "$(id -u)" -eq 0 ] && { echo "Mailpit no se arranca como root"; return 1; }
    # (--suave, desde la ventana cada 20 s: si no pudo arrancar hace menos de 5 minutos, no se espera otra vez)
    [ "$1" == --suave ] && [ -n "$(find "$MAILPIT_DATA/no-arranca" -mmin -5 2> /dev/null)" ] && return 1
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] Mailpit en 127.0.0.1:$MAIL_SMTP_PORT (SMTP) y $MAIL_UI_URL, con datos en $MAILPIT_DATA"
        return 0
    fi
    if [ -L "$MAILPIT_DATA" ] || { [ -e "$MAILPIT_DATA" ] && [ ! -O "$MAILPIT_DATA" ]; }; then
        echo "$MAILPIT_DATA no es una carpeta tuya: no se arranca Mailpit"
        return 1
    fi
    mkdir -p -m 700 "$MAILPIT_DATA" && chmod 700 "$MAILPIT_DATA" || return 1
    [ -L "$MAILPIT_DATA/salida.log" ] && rm -f "$MAILPIT_DATA/salida.log"
    ( cd / && exec env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin /usr/bin/python3 -I -c "$MAILPIT_SETSID_PY" \
        "$MAILPIT_BIN" \
        --smtp "127.0.0.1:$MAIL_SMTP_PORT" --listen "127.0.0.1:$MAIL_UI_PORT" \
        --allowed-hosts "127.0.0.1:$MAIL_UI_PORT,localhost:$MAIL_UI_PORT" \
        --database "$MAILPIT_DATA/mailpit.db" --max "$MAILPIT_MAX" --label "Nexum Dev Stack" \
        --disable-version-check --block-remote-css-and-fonts --smtp-disable-rdns --quiet \
        --log-file "$MAILPIT_DATA/mailpit.log" ) < /dev/null > "$MAILPIT_DATA/salida.log" 2>&1 &
    # (lista en un par de segundos; si no aparece o se cierra enseguida, el puerto lo usa otro programa.
    # Su numero se busca: el python3 de /usr/bin podria arrancarlo en un proceso aparte)
    for i in $(seq 30); do
        sleep 0.1
        p=$(mailpit_find)
        [ -n "$p" ] && curl -q -s --noproxy '*' --max-time 1 -o /dev/null "${MAIL_UI_URL}readyz" 2> /dev/null && break
    done
    p=$(mailpit_find)
    if [ -z "$p" ]; then
        rm -f "$MAILPIT_DATA/mailpit.pid"
        : > "$MAILPIT_DATA/no-arranca"
        echo "Mailpit no ha arrancado (¿otro programa en el puerto $MAIL_SMTP_PORT o $MAIL_UI_PORT?): mira $MAILPIT_DATA/mailpit.log"
        return 1
    fi
    echo "$p" > "$MAILPIT_DATA/mailpit.pid"
    rm -f "$MAILPIT_DATA/no-arranca"
    echo "Mailpit en marcha: el correo de las webs se ve en $MAIL_UI_URL"
}

#@incluir comun/correo-pruebas/mailpit_stop.sh
# Instala (o pone al dia) Mailpit en MAILPIT_DIR: el .tar.gz oficial de GitHub para este Mac,
# comprobado con su sha256 y abierto como root en una carpeta de root (asi ningun programa tuyo puede
# cambiarlo entre la comprobacion y la copia). Solo el programa y su licencia, de root. curl no le pone
# la cuarentena (Gatekeeper no lo mira); por si acaso, se le quitan los atributos extendidos, y su
# firma (la de Go, sin ella un Mac con Apple Silicon no lo ejecuta) se comprueba con codesign
function mailpit_install() {
    local arch sha url tmp rtmp got own=(-o 0 -g 0) tls=(--proto '=https' --proto-redir '=https' --tlsv1.2)
    case $(uname -m) in
        arm64|aarch64) arch=arm64 sha=$MAILPIT_SHA_ARM64 ;;
        x86_64|amd64) arch=amd64 sha=$MAILPIT_SHA_AMD64 ;;
        *) echo "Mailpit no publica version para este Mac ($(uname -m))"; return 1 ;;
    esac
    url=https://github.com/axllent/mailpit/releases/download/v$MAILPIT_VERSION/mailpit-darwin-$arch.tar.gz
    # (las pruebas, sin root ni red: otro fichero y su suma)
    if [ -n "$TEST_DIR" ]; then
        url=${LVM_MAILPIT_URL:-$url} sha=${LVM_MAILPIT_SHA:-$sha} own=() tls=()
    fi
    if mailpit_installed && [ "$(mailpit_installed_version)" == "$MAILPIT_VERSION" ]; then
        echo "Mailpit $MAILPIT_VERSION ya esta instalado en $MAILPIT_DIR"
        return 0
    fi
    task_plan "Instalando Mailpit $MAILPIT_VERSION" "Descargar Mailpit" "Comprobar la descarga" "Instalar Mailpit"
    echo "Instalando Mailpit $MAILPIT_VERSION (correo de pruebas) en $MAILPIT_DIR"
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] descarga de $url, comprobacion de su sha256 y copia de root en $MAILPIT_BIN"
        return 0
    fi
    # Su carpeta y la de encima (/Library/Nexum) tienen que ser de root
    if [ -L "$MAILPIT_DIR" ] || { [ -z "$TEST_DIR" ] && { [ "$(stat -f %u "$BASE_DIR" 2> /dev/null)" != 0 ] \
            || { [ -e "$MAILPIT_DIR" ] && [ "$(stat -f %u "$MAILPIT_DIR")" != 0 ]; }; }; }; then
        echo "$MAILPIT_DIR no es una carpeta de root: no se instala Mailpit"
        return 1
    fi
    mkdir -p -m 700 "$LOG_DIR" || return 1
    tmp=$(mktemp -d "$LOG_DIR/mailpit-descarga.XXXXXX") || return 1
    task_step
    echo "Descargando $(basename "$url")..."
    if ! curl -q -fsSL "${tls[@]}" --retry 2 --max-time 600 -o "$tmp/mailpit.tar.gz" "$url"; then
        rm -rf "$tmp"
        echo "No se ha podido descargar Mailpit ($url)"
        echo "Se puede descargar a mano de https://github.com/axllent/mailpit/releases/tag/v$MAILPIT_VERSION"
        return 1
    fi
    rtmp=$($SUDO mktemp -d "${TEST_DIR:-/tmp}/lvm-mailpit.XXXXXX") && $SUDO chmod 700 "$rtmp" || { rm -rf "$tmp"; return 1; }
    $SUDO cp "$tmp/mailpit.tar.gz" "$rtmp/mailpit.tar.gz"
    rm -rf "$tmp"
    task_step
    got=$($SUDO shasum -a 256 "$rtmp/mailpit.tar.gz" 2> /dev/null | cut -d' ' -f1)
    if [ "$got" != "$sha" ]; then
        $SUDO rm -rf "$rtmp"
        echo "La descarga de Mailpit no coincide con su suma sha256 (${got:-ninguna}): no se instala."
        return 1
    fi
    # Se abre entero en su carpeta (ya comprobado con su sha256) y se busca el programa; si falla, con
    # el error de tar y la pagina de descarga
    local x=$rtmp/x bin lic err
    task_step
    if ! err=$({ $SUDO /bin/mkdir "$x" && $SUDO /usr/bin/tar -xzf "$rtmp/mailpit.tar.gz" -C "$x" --no-same-owner; } 2>&1); then
        $SUDO rm -rf "$rtmp"
        echo "No se ha podido abrir el paquete de Mailpit: no se instala."
        [ -n "$err" ] && sed 's/^/  /' <<< "$err" | head -5
        echo "Se puede descargar a mano de https://github.com/axllent/mailpit/releases/tag/v$MAILPIT_VERSION ($(basename "$url"))"
        return 1
    fi
    bin=$($SUDO /usr/bin/find "$x" -maxdepth 2 -type f -name mailpit 2> /dev/null | head -1)
    lic=$($SUDO /usr/bin/find "$x" -maxdepth 2 -type f -name LICENSE 2> /dev/null | head -1)
    if [ -z "$bin" ]; then
        $SUDO rm -rf "$rtmp"
        echo "El paquete de Mailpit no trae su programa: no se instala."
        return 1
    fi
    # La firma se comprueba como root: la carpeta temporal es de root y solo suya (con tu usuario,
    # codesign no podia leerlo y decia siempre que no tenia firma). Si viniera sin ninguna (los de Apple
    # Silicon traen la local de Go), se le pone una local: su contenido ya esta comprobado con la
    # sha256 de la descarga. Una firma que no cuadra (programa cambiado), no se instala
    if [ -z "$TEST_DIR" ]; then
        $SUDO /usr/bin/xattr -c "$bin" 2> /dev/null
        if ! err=$($SUDO /usr/bin/codesign --verify "$bin" 2>&1); then
            if [[ "$err" == *"not signed at all"* ]] && $SUDO /usr/bin/codesign --force --sign - "$bin" > /dev/null 2>&1 \
                    && $SUDO /usr/bin/codesign --verify "$bin" 2> /dev/null; then
                echo "Mailpit viene sin firmar: se le pone una firma local (comprobado antes con su sha256)"
            else
                $SUDO rm -rf "$rtmp"
                echo "El programa de Mailpit no lleva una firma valida (macOS no lo ejecutaria): no se instala."
                [ -n "$err" ] && sed 's/^/  /' <<< "$err" | head -3
                return 1
            fi
        fi
    fi
    if ! { $SUDO install -d "${own[@]}" -m 755 "$MAILPIT_DIR" \
            && $SUDO install "${own[@]}" -m 755 "$bin" "$MAILPIT_DIR/mailpit.nuevo" \
            && $SUDO mv -f "$MAILPIT_DIR/mailpit.nuevo" "$MAILPIT_BIN" \
            && { [ -z "$lic" ] || $SUDO install "${own[@]}" -m 644 "$lic" "$MAILPIT_DIR/LICENSE"; } \
            && echo "$MAILPIT_VERSION" | $SUDO tee "$MAILPIT_DIR/version" > /dev/null; }; then
        $SUDO rm -rf "$rtmp"
        echo "No se ha podido copiar Mailpit a $MAILPIT_DIR"
        return 1
    fi
    $SUDO rm -rf "$rtmp"
    echo "Mailpit $MAILPIT_VERSION instalado: $MAILPIT_BIN (sus correos, en $MAILPIT_DATA)"
    # (el de antes, si estaba en marcha, se para: mailpit_sync arranca el nuevo)
    [ -n "$(mailpit_pid)" ] && mailpit_stop > /dev/null
    return 0
}

# Despues de cambiar el correo de pruebas: el PHP de todas las versiones (como asegurar --todas, pide
# la contraseña), Apache y PHP-FPM de la activa recargados, Mailpit en marcha o parado y la BBDD del
# proyecto cargado al dia
function mail_apply() {
    local rc
    secure_all
    rc=$?
    if [ $rc -eq 2 ]; then
        echo "No se ha podido cambiar en todas las versiones: prueba con lvm-instalador asegurar --todas"
        return 1
    fi
    if [ $rc -eq 0 ] && lampp_running; then
        run xampp_ctl reloadapache > /dev/null || { echo "No se ha podido recargar Apache"; return 1; }
    fi
    mailpit_sync
    mail_loaded_project
    return 0
}

#@incluir comun/correo-pruebas/mail_wp_text.sh
function mail_command() {
    local mode old
    case $1 in
        ""|estado)
            if mail_on; then
                echo "Correo de pruebas encendido: lo que mandan las webs va a Mailpit"
            else
                echo "Correo de pruebas apagado: lo que mandan las webs sale como sin el gestor (puede llegar de verdad)"
            fi
            echo "  WordPress: $(mail_wp_text "$(mail_wp_mode)")"
            if mailpit_installed; then
                echo "  Mailpit $(mailpit_installed_version) en $MAILPIT_BIN$([ -n "$(mailpit_pid)" ] && echo ", en marcha: $MAIL_UI_URL" || echo ", parado (va con la version activa)")"
            else
                echo "  Mailpit no esta instalado (lvm-instalador correo instalar): sin el, mail() falla y no sale nada"
            fi
            return 0 ;;
        si|on|no|off)
            mkdir -p -m 700 "$LOG_DIR" || return 1
            if [ "$1" == si ] || [ "$1" == on ]; then
                mail_on && { echo "El correo de pruebas ya estaba encendido"; return 0; }
                sudo_first || return 1
                # (--instalar: y Mailpit, si no lo esta; lo ofrece la ventana la primera vez)
                if [ "$2" == --instalar ] && ! mailpit_installed; then
                    mailpit_install || return 1
                fi
                [ "$DRY" -eq 0 ] && rm -f "$MAIL_OFF_FILE"
                mailpit_installed || echo "Aviso: Mailpit no esta instalado (lvm-instalador correo instalar): hasta entonces mail() falla"
            else
                mail_on || { echo "El correo de pruebas ya estaba apagado"; return 0; }
                sudo_first || return 1
                [ "$DRY" -eq 0 ] && { : > "$MAIL_OFF_FILE" || return 1; }
            fi
            if [ "$DRY" -eq 1 ]; then
                echo "  [simulacion] correo de pruebas $([[ "$1" =~ ^(si|on)$ ]] && echo encendido || echo apagado) en todas las versiones"
                return 0
            fi
            if ! mail_apply; then
                # (no se ha podido aplicar: el interruptor vuelve a como estaba)
                if [ "$1" == si ] || [ "$1" == on ]; then : > "$MAIL_OFF_FILE"; else rm -f "$MAIL_OFF_FILE"; fi
                mail_apply > /dev/null 2>&1
                echo "No se ha cambiado el correo de pruebas"
                return 1
            fi
            mail_on && echo "Correo de pruebas encendido: lo que manden las webs va a Mailpit" \
                || echo "Correo de pruebas apagado: lo que manden las webs puede llegar de verdad"
            return 0 ;;
        wordpress)
            mode=$2
            case $mode in
                mailpit|desactivar|nada) ;;
                *) echo "Uso: lvm-instalador correo wordpress mailpit|desactivar|nada"; return 1 ;;
            esac
            if [ "$DRY" -eq 1 ]; then
                echo "  [simulacion] WordPress: $(mail_wp_text "$mode")"
                return 0
            fi
            sudo_first || return 1
            old=$(mail_wp_mode)
            mkdir -p -m 700 "$LOG_DIR" && echo "$mode" > "$MAIL_WP_FILE" || return 1
            if ! mail_apply; then
                echo "$old" > "$MAIL_WP_FILE"
                mail_apply > /dev/null 2>&1
                echo "No se ha cambiado el modo de WordPress"
                return 1
            fi
            echo "WordPress: $(mail_wp_text "$mode")"
            return 0 ;;
        instalar)
            mailpit_install || return 1
            [ "$DRY" -eq 1 ] && return 0
            if mail_on; then
                mail_apply
            else
                echo "El correo de pruebas esta apagado: enciendelo con lvm-instalador correo si"
            fi
            return 0 ;;
        vaciar)
            [ -n "$(mailpit_pid)" ] || { echo "Mailpit no esta en marcha"; return 1; }
            run curl -q -fs --noproxy '*' --max-time 10 -X DELETE -o /dev/null "${MAIL_UI_URL}api/v1/messages" \
                || { echo "No se ha podido vaciar la bandeja de Mailpit"; return 1; }
            echo "Bandeja de Mailpit vacia"
            return 0 ;;
        bd)
            mail_db "$2" ;;
        *)
            echo "Uso: lvm-instalador correo [estado] | si [--instalar] | no | wordpress mailpit|desactivar|nada | instalar | vaciar | bd <base>"
            return 1 ;;
    esac
}

# Ficheros de configuracion de una version que hay que cambiar: <ruta>|<fichero nuevo>|<que cambia>
SECURE_PY='
import glob, os, re, sys
base, out, v6 = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
UNKNOWN_HOST_CONF, UNKNOWN_HOST_VHOST, UNKNOWN_HOST_SSL = sys.argv[4], sys.argv[5], sys.argv[6]
# (lo de PHP de las pilas propias: el .ini y lo que se añade en la 8.5; sin ellos no se mira)
PHP_INI, PHP_INI_85 = (sys.argv[7], sys.argv[8]) if len(sys.argv) > 8 else ("", "")
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
        save(path, new, "Apache, solo desde este Mac (puerto %s)" % ", ".join(ports))

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
        save(conf, want, "Apache, reglas de seguridad al dia (phpMyAdmin, barrera entre webs, peticiones de 64 MB)")

# OpenSSL de Homebrew (copiado en la version) leeria su configuracion de /opt/homebrew, que es de tu
# usuario, al arrancar como root: la version usa la suya (etc/openssl.cnf, de root)
xampp = os.path.join(base, "xampp")
if own(xampp) and own(os.path.join(base, "etc/pvm-stack")):
    text = read(xampp)
    if "OPENSSL_CONF" not in text:
        new = re.sub(r"(?m)^(ROOT=.*)$", "\\1\n# OpenSSL: solo su configuracion (no la de Homebrew, que es de tu usuario)\n"
                     "export OPENSSL_CONF=$ROOT/etc/openssl.cnf\nexport OPENSSL_MODULES=$ROOT/lib/ossl-modules", text, count=1)
        if new != text:
            save(xampp, new, "OpenSSL con su propia configuracion")
    fpm = os.path.join(base, "bin/pvm-php-fpm")
    if own(fpm):
        text = read(fpm)
        if "OPENSSL_CONF" not in text:
            new = text.replace("env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \"$FPM\"",
                               "env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin OPENSSL_CONF=\"${FPM%/php/sbin/php-fpm}/etc/openssl.cnf\" \"$FPM\"")
            if new != text:
                save(fpm, new, "PHP-FPM con la configuracion de OpenSSL de la version")
    cnf = os.path.join(base, "etc/openssl.cnf")
    if not os.path.lexists(cnf):
        save(cnf, "# OpenSSL de esta version (lvm-instalador): sin configuracion ni modulos de fuera\n",
             "Configuracion de OpenSSL de la version")

# PHP2Shell (CVE-2026-109618 y CVE-2026-109619), en las pilas propias: PHP con los limites que lo
# frenan (php/etc/conf.d/zz-lvm-seguridad.ini, que va despues de 99-xampp.ini), PHP-FPM que rehace
# sus procesos cada 50 peticiones y htdocs sin CGI ni SSI (ExecCGI, Includes y el AddHandler de
# .cgi y .pl: ahi solo hay proyectos PHP)
if PHP_INI and own(os.path.join(base, "etc/pvm-stack")):
    conf_d = os.path.join(base, "php/etc/conf.d")
    php = read(os.path.join(base, "etc/pvm-php")).strip() if own(os.path.join(base, "etc/pvm-php")) else ""
    nums = [int(x) for x in re.findall(r"\d+", php)[:2]]
    want = PHP_INI + (PHP_INI_85 if len(nums) == 2 and nums >= [8, 5] else "")
    ini = os.path.join(conf_d, "zz-lvm-seguridad.ini")
    if os.path.isdir(conf_d) and not os.path.islink(conf_d):
        if not os.path.lexists(ini):
            save(ini, want, "PHP, limites contra PHP2Shell (CVE-2026-109618/109619)")
        elif own(ini) and read(ini).startswith("; lvm-instalador:") and read(ini) != want:
            save(ini, want, "PHP, limites contra PHP2Shell al dia")
    path = os.path.join(base, "php/etc/php-fpm.conf")
    if own(path):
        text = read(path)
        if not re.search(r"(?m)^[ \t]*pm\.max_requests[ \t]*=", text):
            new = re.sub(r"(?m)^([ \t]*pm[ \t]*=.*?)(\r?)$", lambda m: m.group(0) + "\npm.max_requests = 50" + m.group(2), text, count=1)
            if new != text:
                save(path, new, "PHP-FPM, procesos nuevos cada 50 peticiones (PHP2Shell)")
    path = os.path.join(base, "etc/httpd.conf")
    if own(path):
        text = read(path)
        new = re.sub(r"(?m)^([ \t]*Options[ \t]+Indexes[ \t]+FollowSymLinks)[ \t]+ExecCGI[ \t]+Includes[ \t]*(\r?)$", r"\1\2", text)
        new = re.sub(r"(?m)^([ \t]*)(AddHandler[ \t]+cgi-script[ \t]+\.cgi[ \t]+\.pl[ \t]*\r?)$",
                     r"\1# (lvm-instalador: sin CGI en htdocs) \2", new)
        if new != text:
            save(path, new, "Apache, htdocs sin CGI ni SSI (ExecCGI, Includes, .cgi y .pl)")

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
        add = "# Solo desde este Mac (lvm-instalador)" + nl + "bind-address = 127.0.0.1" + nl
        m = re.search(r"(?m)^[ \t]*\[mysqld\][ \t]*\r?(\n|$)", text)
        if m:
            head = text[:m.end()]
            new = head + ("" if head.endswith("\n") else nl) + add + text[m.end():]
        else:
            new = text + ("" if text.endswith("\n") or not text else nl) + nl + "[mysqld]" + nl + add
        save(path, new, "MariaDB, solo desde este Mac (bind-address)")

# MariaDB: sin leer ni escribir ficheros del Mac desde SQL. Con secure_file_priv vacio (el de
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
        add = "# Sin leer ni escribir ficheros del Mac desde SQL (lvm-instalador)" + nl + add
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
        add = "# Solo desde este Mac (lvm-instalador)" + nl + "DefaultAddress 127.0.0.1" + nl
        if not re.search(r"(?mi)^[ \t]*SocketBindTight\b", text):
            add += "SocketBindTight on" + nl
        m = re.search(r"(?mi)^[ \t]*Port\b[^\n]*\n", text)
        new = text[:m.end()] + add + text[m.end():] if m else add + text
        save(path, new, "FTP, solo desde este Mac (DefaultAddress)")

# El FTP arrancaba siempre con la version. Ahora solo si se ha activado (etc/lvm-startftp)
path = os.path.join(base, "xampp")
if own(path):
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

# Pilas propias de la 1.27 y anteriores: MariaDB arrancaba como root (mariadbd-safe) y se paraba con
# kill como root, con var/mysql de tu usuario. Ahora con tu usuario (el de user= en my.cnf)
path = os.path.join(base, "xampp")
if own(path):
    text = read(path)
    if "pila propia creada por lvm-instalador" in text and "as_web" not in text:
        user = ""
        mycnf = os.path.join(base, "etc/my.cnf")
        if own(mycnf):
            m = re.search(r"(?m)^[ \t]*user[ \t]*=[ \t]*([A-Za-z_][A-Za-z0-9_.-]*)[ \t]*\r?$", read(mycnf))
            user = m.group(1) if m else ""
        start_old = "(cd \"$ROOT/mysql\" && nohup ./bin/mariadbd-safe"
        stop_old = "    kill \"$(cat \"$MYSQL_PID\")\""
        anchor = "FTP_PID=$ROOT/var/proftpd/proftpd.pid\n"
        if user and user != "root" and start_old in text and stop_old in text and anchor in text:
            helper = ("WEB_USER=" + user + "\nas_web() {\n"
                      "    if [ \"$(id -u)\" -eq 0 ] && [ -n \"$WEB_USER\" ] && [ \"$WEB_USER\" != root ]; then\n"
                      "        /usr/bin/sudo -u \"$WEB_USER\" \"$@\"\n    else\n        \"$@\"\n    fi\n}\n")
            new = text.replace(anchor, anchor + "# MariaDB con tu usuario, no como root (lvm-instalador)\n" + helper, 1)
            new = new.replace(start_old, "(cd \"$ROOT/mysql\" && as_web /usr/bin/nohup ./bin/mariadbd-safe", 1)
            new = new.replace(stop_old, "    as_web kill \"$(cat \"$MYSQL_PID\")\"", 1)
            save(path, new, "MariaDB arranca con tu usuario, no como root")
    # Hasta la 1.39.7, MariaDB, PHP-FPM, Apache y ProFTPD arrancaban con la terminal de la tarea como
    # entrada: seguian con ella abierta y la ventana se quedaba esperando el final (en el 98 %)
    # (las de la 1.27 y anteriores, despues del cambio de arriba: no dos cambios del mismo fichero a la vez)
    text = read(path)
    if "pila propia creada por lvm-instalador" in text and "as_web" in text:
        new = text
        for old, fixed in (
                ("--defaults-file=\"$ROOT/etc/my.cnf\" > /dev/null 2>&1 &)",
                 "--defaults-file=\"$ROOT/etc/my.cnf\" < /dev/null > /dev/null 2>&1 &)"),
                ("    \"$ROOT/bin/pvm-php-fpm\" start\n", "    \"$ROOT/bin/pvm-php-fpm\" start < /dev/null\n"),
                ("-k start >> \"$ROOT/logs/error_log\" 2>&1", "-k start < /dev/null >> \"$ROOT/logs/error_log\" 2>&1"),
                ("-c \"$ROOT/etc/proftpd.conf\" 2> /dev/null &&", "-c \"$ROOT/etc/proftpd.conf\" < /dev/null 2> /dev/null &&")):
            new = new.replace(old, fixed, 1)
        if new != text:
            save(path, new, "Los servicios arrancan sin quedarse con la terminal de la tarea")
# PHP: correo de pruebas (LVM_CORREO = binario de Mailpit|puerto|WordPress a Mailpit 1/0; vacio, apagado).
# mail() va a Mailpit (sendmail_path) y, si los plugins de SMTP de WordPress van a Mailpit, PHP carga
# antes de cada script etc/lvm-correo-wordpress.php (auto_prepend_file; su texto llega en
# LVM_CORREO_PHP). Las dos rutas solo si son de root, sin enlaces ni escritura para otros, hasta /
# (/Library/Nexum/mailpit y la version): nadie mas puede cambiar lo que ejecuta o carga PHP. En
# php/etc/conf.d/99-lvm-correo.ini de cada pila; apagado, ese fichero se queda sin directivas
def root_path_ok(path):
    import stat
    p = os.path.abspath(path)
    while not os.path.lexists(p):
        p = os.path.dirname(p)
    while True:
        st = os.lstat(p)
        if stat.S_ISLNK(st.st_mode) or st.st_uid != 0 or st.st_mode & 0o022:
            return False
        if p == "/":
            return True
        p = os.path.dirname(p)
mail_lines = []
confd = os.path.join(base, "php/etc/conf.d")
mail_stack = own(os.path.join(base, "etc/pvm-stack")) and os.path.isdir(confd) and not os.path.islink(confd)
m = re.fullmatch(r"(/[A-Za-z0-9._/-]+)\|([0-9]{1,5})\|([01])", os.environ.get("LVM_CORREO", ""))
if mail_stack and m and "/../" not in m.group(1) + "/":
    binp, port, wp = m.group(1), m.group(2), m.group(3) == "1"
    prep = os.path.join(base, "etc/lvm-correo-wordpress.php")
    php = os.environ.get("LVM_CORREO_PHP", "")
    # (solo las pruebas, sin root, se saltan la comprobacion; nunca al aplicar)
    test = os.environ.get("LVM_CORREO_PRUEBA") == "1" and os.environ.get("LVM_SECURE_APPLY") != "1"
    if test or root_path_ok(binp):
        mail_lines.append("sendmail_path = \"%s sendmail -S 127.0.0.1:%s\"" % (binp, port))
        if wp and php.startswith("<?php") and (not os.path.lexists(prep) or own(prep)) and (test or root_path_ok(prep)):
            want = php.replace("@PUERTO@", port).rstrip("\n") + "\n"
            if not os.path.lexists(prep) or read(prep) != want:
                save(prep, want, "PHP, plugins de SMTP de WordPress a Mailpit (lvm-correo-wordpress.php)")
            mail_lines.append("auto_prepend_file = \"%s\"" % prep)
if mail_stack:
    path = os.path.join(confd, "99-lvm-correo.ini")
    want = "; lvm-instalador: correo de pruebas (Mailpit). Se cambia en Configuracion o con lvm-instalador correo\n" \
        + ("".join(l + "\n" for l in mail_lines) if mail_lines else "; (apagado: el correo de PHP sale como sin el gestor)\n")
    if (mail_lines and not os.path.lexists(path)) or (own(path) and read(path) != want):
        save(path, want, "PHP, el correo de las webs va a Mailpit" if mail_lines else "PHP, correo de pruebas apagado")
# (las carpetas primero: si no se pudiera crear la de secure_file_priv, no se cambia el my.cnf)
for c in sorted(changes, key=lambda c: not c[0].endswith("/")):
    print("|".join(c))
'

# Antes de arrancar una version: si no se ha podido dejar solo para este Mac (secure_version
# devolvio 2), no se arranca, porque quedaria abierta a la red. secure_failed <codigo> <carpeta>
function secure_failed() {
    [ "$1" -eq 2 ] && [ "$DRY" -eq 0 ] || return 1
    echo "No se arranca $(basename "$2"): no se ha podido dejar solo para este Mac."
    echo "Prueba con: lvm-instalador asegurar --todas"
    return 0
}

# Lineas Listen de los vhosts compartidos que abren Apache a la red (sin 127.x, [::1] ni localhost).
# Apache las lee, pero SECURE_PY no cambia los vhosts (son de todas las versiones y de root): solo se
# pueden poner a mano (sudo -e), por ejemplo siguiendo una guia de vhosts por puerto
function vhosts_open_listen() {
    local real
    real=$(realpath_f "$VHOSTS_FILE" 2> /dev/null) && [ -f "$real" ] || return 0
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
    if w[0].lower() == "include" and len(w) > 1 and re.match(r"^\"?/Library/Nexum/XAMPP-compartido/docker-claves/[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?\.conf\"?$", w[1].strip(" \t\v\f\r")):
        # (la clave de un proyecto en Docker: un RequestHeader, de root)
        continue
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

# Deja una version solo para este Mac (lo que falte). Devuelve 0 si ha cambiado algo (si esta en
# marcha, hay que reiniciarla para aplicarlo), 1 si no hacia falta y 2 si no se ha podido: entonces
# no se arranca.
function secure_version() {
    local dir=$1 tmp list rel src what changed=1 name base
    base=$dir/xamppfiles
    [ -n "$dir" ] && [ -d "$base" ] && [ ! -L "$dir" ] && [ -f "$base/etc/httpd.conf" ] || return 1
    # Las pruebas sin sudo (LVM_PRUEBA) ya se instalan asi
    [ -n "$TEST_DIR" ] && return 1
    name=$(basename "$dir")
    # Una version que no es de root no se hace de root: en /Applications puede escribir cualquier
    # administrador, y un programa con tu usuario podria haber puesto ahi una version falsa (con su
    # script xampp) para que, al protegerla, root la diera por buena y la arrancara. Se reinstala
    if [ "$(stat -f %u "$dir")" != 0 ] || [ "$(stat -f %u "$base")" != 0 ]; then
        echo "$name no es del administrador: no se protege ni se arranca como root. Si la instalaste"
        echo "tu, vuelve a instalarla desde la terminal: lvm-instalador actualizar $(version_name "$dir")"
        return 2
    fi
    # Un Listen abierto en los vhosts compartidos dejaria Apache abierto a la red aunque la version
    # este cerrada: no se arranca hasta quitarlo (se avisa una vez aunque se miren varias versiones)
    local open
    open=$(vhosts_open_listen)
    if [ -n "$open" ]; then
        if [ -z "$LISTEN_WARNED" ]; then
            echo "Los vhosts ($VHOSTS_FILE) abren Apache a la red (o traen otros ficheros):"
            sed 's/^/  /' <<< "$open"
            echo "Quita esas lineas con Editar vhosts (menú de la ventana) y vuelve a arrancarla."
            LISTEN_WARNED=1
        fi
        return 2
    fi
    # Los ficheros nuevos se preparan como root en una carpeta de root: en una tuya, cualquier
    # programa tuyo podria cambiarlos (un ErrorLog "|orden" en httpd.conf) antes de que root los
    # copie a la version. Primero se mira sin sudo si hay algo que cambiar (casi siempre no)
    local rooted=0 mail
    # (el correo de pruebas: binario|puerto|WordPress, o nada si esta apagado)
    mail=$(mail_secure_spec)
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-seguridad.XXXXXX") || return 2
    # macOS siempre tiene ::1 (lo0)
    list=$(LVM_CORREO=$mail LVM_CORREO_PHP=$MAIL_WP_PHP LVM_CORREO_PRUEBA= /usr/bin/python3 -I -c "$SECURE_PY" \
        "$base" "$tmp" 1 "$UNKNOWN_HOST_CONF" "$(unknown_host_vhost)" \
        "$UNKNOWN_HOST_SSL" "$PHP_SECURITY_INI" "$PHP_SECURITY_INI_85") || { rm -rf "$tmp"; return 2; }
    rm -rf "$tmp"
    local sudo=$SUDO
    if [ -n "$list" ]; then
        if [ "$DRY" -eq 1 ]; then
            sudo=""
            tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-seguridad.XXXXXX") || return 2
        else
            tmp=$($SUDO mktemp -d /tmp/lvm-seguridad.XXXXXX) && $SUDO chmod 700 "$tmp" || return 2
        fi
        list=$($sudo env LVM_SECURE_APPLY=1 LVM_CORREO="$mail" LVM_CORREO_PHP="$MAIL_WP_PHP" \
            /usr/bin/python3 -I -c "$SECURE_PY" "$base" \
            "$tmp" 1 "$UNKNOWN_HOST_CONF" "$(unknown_host_vhost)" "$UNKNOWN_HOST_SSL" \
            "$PHP_SECURITY_INI" "$PHP_SECURITY_INI_85") || { $sudo rm -rf "$tmp"; return 2; }
        rooted=1
    fi
    while IFS='|' read -r rel src what; do
        [ -n "$rel" ] || continue
        [ $changed -eq 1 ] && echo "Seguridad de $name: solo se podra entrar desde este Mac"
        changed=0
        echo "  $what ($rel)"
        [ "$DRY" -eq 1 ] && continue
        # Una carpeta (la vacia de secure_file_priv): de root y sin nada dentro
        if [[ "$rel" == */ ]]; then
            if [ -L "$base/${rel%/}" ] || ! $SUDO install -d -o 0 -g 0 -m 755 "$base/${rel%/}"; then
                echo "  No se ha podido crear $base/${rel%/}"
                $SUDO rm -rf "$tmp"
                return 2
            fi
            continue
        fi
        # (los ficheros nuevos, como lvm-dominio-desconocido.conf, no tienen copia; los demas, solo con
        # el ajuste copias-ficheros)
        [ -f "$base/$rel" ] && [ -f "$COPIES_FILES_FLAG" ] && mkdir -p -m 700 "$COPIES_DIR" \
            && cp "$base/$rel" "$COPIES_DIR/$name-$(basename "$rel")-$(date +%Y%m%d-%H%M%S)" 2> /dev/null
        $SUDO sh -c 'cat "$1" > "$2"' sh "$src" "$base/$rel" || { $SUDO rm -rf "$tmp"; return 2; }
        [[ "$rel" == *.key ]] && $SUDO chmod 600 "$base/$rel"
    done <<< "$list"
    [ $rooted -eq 1 ] && $sudo rm -rf "$tmp"

    # La carpeta de la version y su script xampp, sin escritura para el grupo (admin, que es tu
    # usuario): xampp_ctl no arranca una version que no lo cumpla. Solo se quita la escritura: lo
    # que no es de root no se hace de root (ver arriba)
    local f
    for f in "$dir" "$base" "$base/xampp" "$base/bin/pvm-php-fpm"; do
        [ -e "$f" ] && [ ! -L "$f" ] || continue
        if [ "$(stat -f %u "$f")" != 0 ]; then
            echo "  $f no es del administrador: vuelve a instalarla (lvm-instalador actualizar $(version_name "$dir"))"
            return 2
        fi
        if [ $(( 8#$(stat -f %Lp "$f") & 8#022 )) -ne 0 ]; then
            [ $changed -eq 1 ] && echo "Seguridad de $name:"
            changed=0
            echo "  $f: sin escritura para el grupo ni los demas"
            run $SUDO chmod go-w "$f" || return 2
        fi
    done

    # Lo de dentro que root ejecuta o carga: si no es de root o el grupo admin (tu usuario) lo puede
    # cambiar, ya no se sabe si lo han cambiado (un httpd.conf o una biblioteca): no se da por buena
    # quitandole la escritura, se reinstala (install_stack lo deja todo de root y sin escritura)
    # mariadb-install-db le da al usuario del servidor (tu usuario) la carpeta del ayudante de PAM y
    # deja dentro un programa setuid de root. Aqui no se usa PAM: se quita (como root; la carpeta de
    # encima es de root) en vez de dar la version por insegura y no arrancarla
    local pam=$base/mysql/lib/plugin/auth_pam_tool_dir
    if [ -e "$pam" ] || [ -L "$pam" ]; then
        [ $changed -eq 1 ] && echo "Seguridad de $name:"
        changed=0
        echo "  Se quita $pam (el ayudante de PAM de MariaDB, que aqui no se usa)"
        run $SUDO rm -rf "$pam" || return 2
    fi

    local unsafe
    unsafe=$(version_unsafe_files "$dir" | head -1)
    if [ -n "$unsafe" ]; then
        echo "  $unsafe no es del administrador o lo puede cambiar el grupo admin: vuelve a instalar la"
        echo "  version (lvm-instalador actualizar $(version_name "$dir")). Hasta entonces no se arranca como root."
        return 2
    fi

    # Una sola vez por version: el FTP deja de arrancar con ella (se activa en Servicios)
    if [ ! -f "$dir/$SECURE_MARK" ]; then
        if [ "$(active_dir)" == "$(realpath_f "$dir")" ] && service_running ftp; then
            [ $changed -eq 1 ] && echo "Seguridad de $name:"
            echo "  El FTP ya no arranca con la version: activalo en los servicios de la ventana (la flecha del visor de arriba) cuando lo necesites"
            changed=0
            run xampp_ctl stopftp
        fi
        run $SUDO rm -f "$base/etc/lvm-startftp"
        if [ "$DRY" -eq 0 ]; then
            echo "1" | $SUDO tee "$dir/$SECURE_MARK" > /dev/null
        fi
    fi
    return $changed
}

# Todas las versiones, solo para este Mac. Devuelve como secure_version: 0 si ha cambiado algo, 1
# si no hacia falta y 2 si alguna no se ha podido.
function secure_all() {
    local d rc=1 r
    for d in $(version_dirs); do
        [ -f "$d/xamppfiles/etc/pvm-stack" ] || continue
        secure_version "$d"
        r=$?
        [ $r -eq 2 ] && { echo "No se ha podido dejar $(basename "$d") solo para este Mac"; rc=2; }
        [ $r -eq 0 ] && [ $rc -eq 1 ] && rc=0
    done
    return $rc
}

# Versiones a las que les falta algo de lo que pondria secure_version, separadas por espacios
# La ventana lo pregunta cada 20 s y es un python3 por version, pero solo cambia si cambian sus ficheros:
# con la misma huella (cambio, fecha, dueño y permisos de la version, de xamppfiles y de lo de etc y
# apache2/conf, y lo que se le pasa a SECURE_PY) y de hace menos de 10 min, la respuesta de antes. Sin
# cache con root (escribiria en tu carpeta) ni con LVM_SIN_CACHE
function unsecured_versions() {
    local d tmp list out="" mail checked="" key="" cache=$LOG_DIR/cache/versiones-abiertas dirs=() deep=() top=()
    [ -n "$TEST_DIR" ] && return 0
    mail=$(mail_secure_spec)
    # (las de /Applications de antes de la 1.39.3: protegerlas es pasarlas a /Library/Nexum)
    for d in $(legacy_dirs); do
        out+="${out:+ }${d##*/XAMPP-}"
    done
    for d in $(version_dirs); do
        [ -f "$d/xamppfiles/etc/pvm-stack" ] || continue
        dirs+=("$d") top+=("$d" "$d/xamppfiles") deep+=("$d/xamppfiles/etc" "$d/xamppfiles/apache2/conf")
    done
    if [ "$EUID" -ne 0 ] && [ -z "${LVM_SIN_CACHE:-}" ]; then
        key=$({ printf '%s\n' "$APP_VERSION" "$mail" "$MAIL_WP_PHP" "$(unknown_host_vhost)" "$UNKNOWN_HOST_SSL" \
                    "$PHP_SECURITY_INI" "$PHP_SECURITY_INI_85" "${dirs[@]}"
                if [ ${#dirs[@]} -gt 0 ]; then
                    { find -H "${top[@]}" -maxdepth 0 -print0; find -H "${deep[@]}" -maxdepth 6 -print0; } 2> /dev/null \
                        | xargs -0 stat -f '%c %m %u %g %p %N' 2> /dev/null
                fi; } | md5 -q)
        if [ -f "$cache" ] && [ ! -L "$cache" ] && [ -z "$(find "$cache" -mmin +10 2> /dev/null)" ] \
            && [ "$(head -1 "$cache" 2> /dev/null)" == "$key" ]; then
            checked=$(sed -n 2p "$cache")
            out+="${out:+${checked:+ }}$checked"
            echo "$out"
            return 0
        fi
    fi
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-seguridad.XXXXXX") || return 0
    for d in "${dirs[@]}"; do
        list=$(LVM_CORREO=$mail LVM_CORREO_PHP=$MAIL_WP_PHP LVM_CORREO_PRUEBA= python3 -I -c "$SECURE_PY" \
            "$d/xamppfiles" "$tmp" 1 "$UNKNOWN_HOST_CONF" \
            "$(unknown_host_vhost)" "$UNKNOWN_HOST_SSL" "$PHP_SECURITY_INI" "$PHP_SECURITY_INI_85" 2> /dev/null)
        [ -n "$list" ] || ! trusted_version_dir "$d" && checked+="${checked:+ }$(version_name "$d")"
        rm -f "$tmp"/*
    done
    rm -rf "$tmp"
    if [ -n "$key" ] && mkdir -p -m 700 "$LOG_DIR/cache" 2> /dev/null; then
        printf '%s\n%s\n' "$key" "$checked" > "$cache.$$" && mv -f "$cache.$$" "$cache"
    fi
    out+="${out:+${checked:+ }}$checked"
    echo "$out"
}

# ¿Se puede arrancar como root esta carpeta? Solo una carpeta XAMPP-<version> de /Library/Nexum (de
# root: en /Applications puede escribir cualquier administrador, tu usuario, y un programa tuyo
# podria cambiar una version o XAMPP-compartido por algo suyo entre la comprobacion y el arranque),
# de root con su script xampp de root y los vhosts compartidos de root, todo sin enlaces ni escritura
# para el grupo o los demas, y cada carpeta de encima igual (boot_root_owned). Las de /Applications
# de antes de la 1.39.3, no: primero lvm-instalador migrar
function trusted_version_dir() {
    local d=$1 f vhosts
    [[ "$d" =~ ^/Library/Nexum/XAMPP-[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || return 1
    boot_root_owned "$d/xamppfiles/xampp" || return 1
    vhosts=$(realpath_f "$VHOSTS_FILE" 2> /dev/null)
    # (si existen y no se sabe adonde llevan, no vale: no se comprobarian)
    [ -e "$VHOSTS_FILE" ] && [ -z "$vhosts" ] && return 1
    # (los vhosts, en XAMPP-compartido de /Library/Nexum)
    [ -n "$vhosts" ] && { [ "$vhosts" == "$COMMON/httpd-vhosts.conf" ] && boot_root_owned "$vhosts" || return 1; }
    for f in "$d" "$d/xamppfiles" "$d/xamppfiles/xampp" "$COMMON" ${vhosts:+"$vhosts"}; do
        [ -e "$f" ] || { [ "$f" == "$COMMON" ] && continue; return 1; }
        [ ! -L "$f" ] || return 1
        [ "$(stat -f %u "$f")" == 0 ] || return 1
        [ $(( 8#$(stat -f %Lp "$f") & 8#022 )) -eq 0 ] || return 1
    done
    # Y, por dentro, lo que root ejecuta o carga al arrancar (programas, bibliotecas, configuracion):
    # de root y sin escritura para el grupo ni los demas, como lo deja install_stack
    [ -z "$(version_unsafe_files "$d" | head -1)" ]
}

# Lo de dentro de una version que root ejecuta o carga y no es de root o pueden cambiar el grupo o
# los demas (las bases, tmp y los registros quedan fuera)
function version_unsafe_files() {
    local deep=() sub
    for sub in apache2 php proftpd bin sbin lib libexec mysql etc; do
        [ -e "$1/xamppfiles/$sub" ] && deep+=("$1/xamppfiles/$sub")
    done
    [ ${#deep[@]} -gt 0 ] || return 0
    find "${deep[@]}" ! -type l \( ! -user root -o -perm -020 -o -perm -002 \) -print 2> /dev/null
}

