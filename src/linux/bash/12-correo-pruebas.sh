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
# version activa: arranca y para con ella, con tu usuario y solo en 127.0.0.1
# Version fijada y sha256 de cada .tar.gz (de los digest de la publicacion en GitHub, comprobados al
# descargarlos el 25/10/2026). La 1.32.0 arregla fallos de seguridad (GHSA-379p-g4f4-hq5h)
MAILPIT_VERSION="1.32.0"
MAILPIT_SHA_AMD64="4b5993c978e8604c70d43927e2ad103b311bba3b1822fa0cf1d4ee4ec890a93c"
MAILPIT_SHA_ARM64="e1e45d1dc72bd497fb262a1e4100178eee057c42c5fc36d143eb8621769e1137"
# El programa, de root junto a la configuracion compartida (/opt/config/mailpit): ni tu usuario ni
# una web pueden cambiar lo que ejecuta PHP al mandar un correo. Sus datos, solo tuyos
MAILPIT_DIR=$(dirname "$VHOSTS_FILE")/mailpit
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
# Mailpit). PHP 7.1 o posterior (el XAMPP mas antiguo)
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
# Numero del proceso de Mailpit: el de su .pid si es tuyo y es el del gestor o, si se ha perdido, el
# que este en marcha con su binario
function mailpit_pid() {
    local p
    p=$(head -c 20 "$MAILPIT_DATA/mailpit.pid" 2> /dev/null | tr -d ' \n')
    if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -gt 1 ] && [ -O "/proc/$p" ] \
            && tr '\0' '\n' < "/proc/$p/cmdline" 2> /dev/null | grep -qxF -- "$MAILPIT_BIN"; then
        echo "$p"
        return 0
    fi
    p=$(pgrep -u "$(id -u)" -f -- "$MAILPIT_BIN --smtp" 2> /dev/null | head -1)
    [ -n "$p" ] && echo "$p"
}

# Arranca Mailpit con tu usuario: SMTP y web solo en 127.0.0.1, la web solo con su direccion (Mailpit
# rechaza otro Host: una web cuyo dominio apunte a 127.0.0.1, DNS rebinding, no puede leer los
# correos; y las peticiones de otras webs que cambian algo, por su Origin), sin buscar versiones
# nuevas, sin CSS ni fuentes de fuera en los correos y como mucho MAILPIT_MAX. Con el entorno limpio:
# Mailpit lee su configuracion de las variables MP_* (una MP_SMTP_RELAY_ALL de tu sesion mandaria los
# correos de verdad)
function mailpit_start() {
    local p="" i
    [ -n "$(mailpit_pid)" ] && return 0
    mailpit_installed || return 1
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
    ( cd / && exec env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin setsid "$MAILPIT_BIN" \
        --smtp "127.0.0.1:$MAIL_SMTP_PORT" --listen "127.0.0.1:$MAIL_UI_PORT" \
        --allowed-hosts "127.0.0.1:$MAIL_UI_PORT,localhost:$MAIL_UI_PORT" \
        --database "$MAILPIT_DATA/mailpit.db" --max "$MAILPIT_MAX" --label "Nexum Dev Stack" \
        --disable-version-check --block-remote-css-and-fonts --smtp-disable-rdns --quiet \
        --log-file "$MAILPIT_DATA/mailpit.log" ) < /dev/null > /dev/null 2>&1 &
    # (lista en un par de segundos; si no aparece o se cierra enseguida, el puerto lo usa otro programa.
    # Su numero se busca: setsid puede arrancarlo en un proceso aparte)
    for i in $(seq 30); do
        sleep 0.1
        p=$(pgrep -u "$(id -u)" -f -- "$MAILPIT_BIN --smtp" 2> /dev/null | head -1)
        [ -n "$p" ] && curl -s --noproxy '*' --max-time 1 -o /dev/null "${MAIL_UI_URL}readyz" 2> /dev/null && break
    done
    p=$(pgrep -u "$(id -u)" -f -- "$MAILPIT_BIN --smtp" 2> /dev/null | head -1)
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
# Instala (o pone al dia) Mailpit en MAILPIT_DIR: el .tar.gz oficial de GitHub para este equipo,
# comprobado con su sha256 y abierto como root en una carpeta de root (asi ningun programa tuyo puede
# cambiarlo entre la comprobacion y la copia). Solo el programa y su licencia, de root
function mailpit_install() {
    local arch sha url tmp rtmp got own=(-o 0 -g 0) tls=(--proto '=https' --tlsv1.2)
    case $(uname -m) in
        x86_64|amd64) arch=amd64 sha=$MAILPIT_SHA_AMD64 ;;
        aarch64|arm64) arch=arm64 sha=$MAILPIT_SHA_ARM64 ;;
        *) echo "Mailpit no publica version para este equipo ($(uname -m))"; return 1 ;;
    esac
    url=https://github.com/axllent/mailpit/releases/download/v$MAILPIT_VERSION/mailpit-linux-$arch.tar.gz
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
    # La carpeta compartida tiene que ser de root (Mailpit va dentro)
    vhosts_root
    if [ -L "$MAILPIT_DIR" ] || { [ -z "$TEST_DIR" ] && [ -e "$MAILPIT_DIR" ] && [ "$(stat -c %u "$MAILPIT_DIR")" != 0 ]; }; then
        echo "$MAILPIT_DIR no es una carpeta de root: no se instala Mailpit"
        return 1
    fi
    mkdir -p -m 700 "$LOG_DIR" || return 1
    tmp=$(mktemp -d "$LOG_DIR/mailpit-descarga.XXXXXX") || return 1
    task_step
    echo "Descargando $(basename "$url")..."
    if ! curl -fsSL "${tls[@]}" --retry 2 --max-time 600 -o "$tmp/mailpit.tar.gz" "$url"; then
        rm -rf "$tmp"
        echo "No se ha podido descargar Mailpit ($url)"
        echo "Se puede descargar a mano de https://github.com/axllent/mailpit/releases/tag/v$MAILPIT_VERSION"
        return 1
    fi
    rtmp=$($SUDO mktemp -d "${TEST_DIR:-/tmp}/lvm-mailpit.XXXXXX") && $SUDO chmod 700 "$rtmp" || { rm -rf "$tmp"; return 1; }
    $SUDO cp "$tmp/mailpit.tar.gz" "$rtmp/mailpit.tar.gz"
    rm -rf "$tmp"
    task_step
    got=$($SUDO sha256sum "$rtmp/mailpit.tar.gz" 2> /dev/null | cut -d' ' -f1)
    if [ "$got" != "$sha" ]; then
        $SUDO rm -rf "$rtmp"
        echo "La descarga de Mailpit no coincide con su suma sha256 (${got:-ninguna}): no se instala."
        return 1
    fi
    # Se abre entero en su carpeta (ya comprobado con su sha256) y se busca el programa: segun la
    # version, el paquete lo guarda como mailpit o ./mailpit, con o sin LICENSE al lado
    local x=$rtmp/x bin lic err
    task_step
    if ! err=$({ $SUDO mkdir "$x" && $SUDO tar -xzf "$rtmp/mailpit.tar.gz" -C "$x" --no-same-owner --no-same-permissions; } 2>&1); then
        $SUDO rm -rf "$rtmp"
        echo "No se ha podido abrir el paquete de Mailpit: no se instala."
        [ -n "$err" ] && sed 's/^/  /' <<< "$err" | head -5
        echo "Se puede descargar a mano de https://github.com/axllent/mailpit/releases/tag/v$MAILPIT_VERSION ($(basename "$url"))"
        return 1
    fi
    bin=$($SUDO find "$x" -maxdepth 2 -type f -name mailpit 2> /dev/null | head -1)
    lic=$($SUDO find "$x" -maxdepth 2 -type f -name LICENSE 2> /dev/null | head -1)
    if [ -z "$bin" ]; then
        $SUDO rm -rf "$rtmp"
        echo "El paquete de Mailpit no trae su programa: no se instala."
        return 1
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
        echo "No se ha podido cambiar en todas las versiones: prueba con nexum asegurar --todas"
        return 1
    fi
    if [ $rc -eq 0 ] && lampp_running; then
        run sudo /opt/lampp/lampp reloadapache > /dev/null || { echo "No se ha podido recargar Apache"; return 1; }
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
                echo "  Mailpit no esta instalado (nexum correo instalar): sin el, mail() falla y no sale nada"
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
                mailpit_installed || echo "Aviso: Mailpit no esta instalado (nexum correo instalar): hasta entonces mail() falla"
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
                *) echo "Uso: nexum correo wordpress mailpit|desactivar|nada"; return 1 ;;
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
                echo "El correo de pruebas esta apagado: enciendelo con nexum correo si"
            fi
            return 0 ;;
        vaciar)
            [ -n "$(mailpit_pid)" ] || { echo "Mailpit no esta en marcha"; return 1; }
            run curl -fs --noproxy '*' --max-time 10 -X DELETE -o /dev/null "${MAIL_UI_URL}api/v1/messages" \
                || { echo "No se ha podido vaciar la bandeja de Mailpit"; return 1; }
            echo "Bandeja de Mailpit vacia"
            return 0 ;;
        bd)
            mail_db "$2" ;;
        *)
            echo "Uso: nexum correo [estado] | si [--instalar] | no | wordpress mailpit|desactivar|nada | instalar | vaciar | bd <base>"
            return 1 ;;
    esac
}

# Ficheros de configuracion de una version que hay que cambiar: <ruta>|<fichero nuevo>|<que cambia>
SECURE_PY='
import glob, os, re, stat, sys
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
    # El fichero es de nexum: si es de una version anterior (o le falta el 443), se rehace
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

# Apache: sin CGI ni SSI en las carpetas de los proyectos (htdocs): un .cgi o .pl subido a una web
# (por un formulario de un proyecto antiguo) ya no se ejecuta. El cgi-bin de la version sigue igual
path = os.path.join(base, "etc/httpd.conf")
if own(path):
    text = read(path)
    def no_cgi(m):
        words = [w for w in m.group(3).split() if w.lower() not in ("execcgi", "includes", "+execcgi", "+includes")]
        return m.group(1) + m.group(2) + " ".join(words) + m.group(4)
    new = re.sub(r"(?is)(<Directory[ \t]+\"?[^\">\n]*/htdocs/?\"?[ \t]*>.*?^)([ \t]*Options[ \t]+)([^\r\n]*?)([ \t]*\r?$)",
                 lambda m: no_cgi(m) if re.search(r"(?i)\b(execcgi|includes)\b", m.group(3))
                 and "</directory" not in m.group(1).lower() else m.group(0), text, flags=re.M)
    new = re.sub(r"(?mi)^([ \t]*)(AddHandler[ \t]+cgi-script[ \t]+\.cgi[ \t]+\.pl[ \t]*)(\r?)$",
                 r"\1# (lvm-instalador: sin CGI en los proyectos) \2\3", new)
    if new != text:
        save(path, new, "Apache, sin CGI ni SSI en los proyectos (ExecCGI, Includes y .cgi .pl)")

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

# PHP: mitigaciones de PHP2Shell (PHP_SECURE_INI, en LVM_PHP_INI). Las pilas propias, en un fichero
# suyo de conf.d (99-lvm-seguridad.ini, que va despues de 99-lampp.ini); los XAMPP, en su etc/php.ini:
# cada directiva se cambia donde esta o, si no esta, se añade al final con las demas del gestor
# (las directivas, separadas por ; para que la orden de sudo sea una sola linea)
ini = [l.strip() for l in re.split(r"[;\n]", os.environ.get("LVM_PHP_INI", "")) if "=" in l]
stack_php = ""
if own(os.path.join(base, "etc/lvm-php")):
    stack_php = read(os.path.join(base, "etc/lvm-php")).strip()
def at_least(v, want):
    try:
        return tuple(int(x) for x in v.split(".")[:2]) >= want
    except ValueError:
        return False
if ini and at_least(stack_php, (8, 5)):
    ini += [l.strip() for l in re.split(r"[;\n]", os.environ.get("LVM_PHP_INI_85", "")) if "=" in l]
confd = os.path.join(base, "php/etc/conf.d")
if ini and own(os.path.join(base, "etc/lvm-stack")) and os.path.isdir(confd) and not os.path.islink(confd):
    path = os.path.join(confd, "99-lvm-seguridad.ini")
    want = "; lvm-instalador: mitigaciones de PHP2Shell (CVE-2026-109618 y CVE-2026-109619)\n" + "\n".join(ini) + "\n"
    if not os.path.lexists(path) or (own(path) and read(path) != want):
        save(path, want, "PHP, mitigaciones de PHP2Shell (sin el progreso de las subidas, 64 MB como mucho)")
elif ini and own(os.path.join(base, "etc/php.ini")):
    path = os.path.join(base, "etc/php.ini")
    text = read(path)
    nl = "\r\n" if "\r\n" in text else "\n"
    new, add = text, []
    for line in ini:
        key, val = (x.strip() for x in line.split("=", 1))
        rx = re.compile(r"(?mi)^[ \t]*%s[ \t]*=[ \t]*([^\r\n]*?)[ \t]*(\r?)$" % re.escape(key))
        if rx.search(new):
            # (las que ya tienen el valor, igual: asi no se vuelve a escribir cada vez)
            new = rx.sub(lambda m: m.group(0) if m.group(1).strip("\"\x27").lower() == val.lower()
                         else "%s = %s%s" % (key, val, m.group(2)), new)
        else:
            add.append("%s = %s" % (key, val))
    if add:
        new = new + ("" if new.endswith("\n") else nl) + nl + "; lvm-instalador: mitigaciones de PHP2Shell" + nl \
            + nl.join(add) + nl
    if new != text:
        save(path, new, "PHP, mitigaciones de PHP2Shell en php.ini (sin el progreso de las subidas, 64 MB como mucho)")
# PHP-FPM de las pilas propias: cada proceso se renueva cada 50 peticiones (lo que se haya podido
# quedar en su memoria no dura)
path = os.path.join(base, "php/etc/php-fpm.conf")
if ini and own(os.path.join(base, "etc/lvm-stack")) and own(path):
    text = read(path)
    if not re.search(r"(?mi)^[ \t]*pm\.max_requests\b", text):
        new = re.sub(r"(?m)^([ \t]*pm\.max_children[ \t]*=[^\n]*\n)", r"\1pm.max_requests = 50\n", text, count=1)
        if new != text:
            save(path, new, "PHP-FPM, cada proceso se renueva cada 50 peticiones")

# PHP: correo de pruebas (LVM_CORREO = binario de Mailpit|puerto|WordPress a Mailpit 1/0; vacio, apagado).
# mail() va a Mailpit (sendmail_path) y, si los plugins de SMTP de WordPress van a Mailpit, PHP carga
# antes de cada script etc/lvm-correo-wordpress.php (auto_prepend_file; su texto llega en
# LVM_CORREO_PHP). Las dos rutas solo si son de root, sin enlaces ni escritura para otros, hasta /: nadie
# mas puede cambiar lo que ejecuta o carga PHP. Las pilas propias, en su conf.d/99-lvm-correo.ini (va
# despues de los demas); los XAMPP, en un bloque al final de su php.ini, con lo que tenian comentado
# (vuelve al apagarlo)
def root_path_ok(path):
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
m = re.fullmatch(r"(/[A-Za-z0-9._/-]+)\|([0-9]{1,5})\|([01])", os.environ.get("LVM_CORREO", ""))
if m and "/../" not in m.group(1) + "/":
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
MAIL_BEGIN, MAIL_END = "; >>> lvm-instalador: correo de pruebas (Mailpit)", "; <<< lvm-instalador: correo de pruebas"
MAIL_OFF = "; (lvm-instalador: correo de pruebas) "
confd = os.path.join(base, "php/etc/conf.d")
if own(os.path.join(base, "etc/lvm-stack")) and os.path.isdir(confd) and not os.path.islink(confd):
    path = os.path.join(confd, "99-lvm-correo.ini")
    want = "; lvm-instalador: correo de pruebas (Mailpit). Se cambia en Configuracion o con lvm-instalador correo\n" \
        + ("".join(l + "\n" for l in mail_lines) if mail_lines else "; (apagado: el correo de PHP sale como sin el gestor)\n")
    if (mail_lines and not os.path.lexists(path)) or (own(path) and read(path) != want):
        save(path, want, "PHP, el correo de las webs va a Mailpit" if mail_lines else "PHP, correo de pruebas apagado")
elif own(os.path.join(base, "etc/php.ini")):
    path = os.path.join(base, "etc/php.ini")
    text = read(path)
    nl = "\r\n" if "\r\n" in text else "\n"
    # Lo que habia: sin el bloque del gestor y con lo que dejo comentado
    new = re.sub(r"(?s)(?:\r?\n)?%s[^\n]*\n.*?%s[^\n]*(?:\n|$)" % (re.escape(MAIL_BEGIN), re.escape(MAIL_END)), "", text)
    new = re.sub(r"(?m)^%s" % re.escape(MAIL_OFF), "", new)
    if mail_lines:
        for line in mail_lines:
            key = line.split("=", 1)[0].strip()
            new = re.sub(r"(?mi)^(?=[ \t]*%s[ \t]*=)" % re.escape(key), MAIL_OFF, new)
        new = new + ("" if new.endswith("\n") or not new else nl) + nl + MAIL_BEGIN + nl + nl.join(mail_lines) + nl + MAIL_END + nl
    if new != text:
        save(path, new, "PHP, el correo de las webs va a Mailpit (php.ini)" if mail_lines
             else "PHP, correo de pruebas apagado (php.ini como estaba)")

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
    echo "Prueba con: nexum asegurar --todas"
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
    local rooted=0 HOST_VHOST mail
    host_vhost
    # (el correo de pruebas: binario|puerto|WordPress, o nada si esta apagado)
    mail=$(mail_secure_spec)
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-seguridad.XXXXXX") || return 2
    list=$(LVM_PHP_INI=${PHP_SECURE_INI//$'\n'/;} LVM_PHP_INI_85=$PHP_SECURE_INI_85 LVM_CORREO=$mail LVM_CORREO_PHP=$MAIL_WP_PHP \
        LVM_CORREO_PRUEBA= /usr/bin/python3 -I -c "$SECURE_PY" \
        "$dir" "$tmp" "$v6" "$UNKNOWN_HOST_CONF" "$HOST_VHOST" "$UNKNOWN_HOST_SSL") || { rm -rf "$tmp"; return 2; }
    rm -rf "$tmp"
    local sudo=sudo
    if [ -n "$list" ]; then
        if [ "$DRY" -eq 1 ]; then
            sudo=""
            tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-seguridad.XXXXXX") || return 2
        else
            tmp=$(sudo mktemp -d /tmp/lvm-seguridad.XXXXXX) && sudo chmod 700 "$tmp" || return 2
        fi
        list=$($sudo env LVM_SECURE_APPLY=1 LVM_FTP_USER="${SUDO_USER:-$USER}" LVM_PHP_INI="${PHP_SECURE_INI//$'\n'/;}" \
            LVM_PHP_INI_85="$PHP_SECURE_INI_85" LVM_CORREO="$mail" LVM_CORREO_PHP="$MAIL_WP_PHP" \
            /usr/bin/python3 -I -c "$SECURE_PY" "$dir" \
            "$tmp" "$v6" "$UNKNOWN_HOST_CONF" "$HOST_VHOST" "$UNKNOWN_HOST_SSL") || { $sudo rm -rf "$tmp"; return 2; }
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
        # (los ficheros nuevos, como lvm-dominio-desconocido.conf, no tienen copia; los demas, solo con
        # el ajuste copias-ficheros)
        [ -f "$dir/$rel" ] && [ -f "$COPIES_FILES_FLAG" ] && mkdir -p -m 700 "$COPIES_DIR" \
            && cp "$dir/$rel" "$COPIES_DIR/$name-$(basename "$rel")-$(date +%Y%m%d-%H%M%S)" 2> /dev/null
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
# La ventana lo pregunta cada 20 s y son unos 400 ms (un python3 por version), pero solo cambia si cambian
# sus ficheros: con la misma huella (fecha, cambio, dueño y permisos de lo de etc, php/etc, apache2/conf y
# lampp de cada version, y lo que se le pasa a SECURE_PY) y de hace menos de 10 min, la respuesta de antes.
# Sin cache con root (escribiria en tu carpeta) ni con LVM_SIN_CACHE
function unsecured_versions() {
    local d tmp list out="" HOST_VHOST mail key="" cache=$LOG_DIR/cache/versiones-abiertas dirs=()
    [ -n "$TEST_DIR" ] && return 0
    host_vhost
    mail=$(mail_secure_spec)
    for d in $(lampp_dirs); do
        [ -L "$d" ] || [ ! -f "$d/etc/httpd.conf" ] || dirs+=("$d")
    done
    if [ "$EUID" -ne 0 ] && [ -z "${LVM_SIN_CACHE:-}" ]; then
        key=$({ printf '%s\n' "$APP_VERSION" "$HOST_VHOST" "$mail" "$PHP_SECURE_INI" "$PHP_SECURE_INI_85" \
                    "$MAIL_WP_PHP" "$UNKNOWN_HOST_SSL" "${dirs[@]}"
                for d in "${dirs[@]}"; do
                    find -H "$d/etc" "$d/php/etc" "$d/apache2/conf" "$d/lampp" -maxdepth 6 \
                        -printf '%C@ %T@ %U %G %m %p\n' 2> /dev/null
                done; } | md5sum | cut -d' ' -f1)
        if [ -f "$cache" ] && [ ! -L "$cache" ] && [ -z "$(find "$cache" -mmin +10 2> /dev/null)" ] \
            && [ "$(head -1 "$cache" 2> /dev/null)" == "$key" ]; then
            sed -n 2p "$cache"
            return 0
        fi
    fi
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-seguridad.XXXXXX") || return 0
    for d in "${dirs[@]}"; do
        list=$(LVM_PHP_INI=${PHP_SECURE_INI//$'\n'/;} LVM_PHP_INI_85=$PHP_SECURE_INI_85 LVM_CORREO=$mail LVM_CORREO_PHP=$MAIL_WP_PHP \
            LVM_CORREO_PRUEBA= python3 -I -c "$SECURE_PY" "$d" "$tmp" 1 "$UNKNOWN_HOST_CONF" "$HOST_VHOST" \
            "$UNKNOWN_HOST_SSL" 2> /dev/null)
        if [ -n "$list" ] || { [ ! -f "$d/$SECURE_MARK" ] \
                && { [ -f "$d/etc/xampp/startftp" ] || [ -f "$d/etc/lvm-startftp" ]; }; }; then
            out+="${out:+ }${d#/opt/lampp-}"
        fi
        rm -f "$tmp"/*
    done
    rm -rf "$tmp"
    if [ -n "$key" ] && mkdir -p -m 700 "$LOG_DIR/cache" 2> /dev/null; then
        printf '%s\n%s\n' "$key" "$out" > "$cache.$$" && mv -f "$cache.$$" "$cache"
    fi
    echo "$out"
}

# ¿Esta en marcha un servicio (apache, mariadb o ftp) de la version montada? Con un segundo argumento, lo
# que ya ha dado lampp_processes (que recorre /proc con un python3): para no leerlo una vez por servicio
function service_running() {
    local rx
    case $1 in
        apache) rx='^(httpd|apache2)$' ;;
        mariadb) rx='^(mysqld|mariadbd)$' ;;
        ftp) rx='^proftpd$' ;;
        *) return 1 ;;
    esac
    { if [ $# -ge 2 ]; then printf '%s\n' "$2"; else lampp_processes; fi; } \
        | awk -F'|' -v rx="$rx" '$6 == 0 && $7 ~ rx { f = 1 } END { exit !f }'
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

# barrera-web [si|no]: enciende o apaga la barrera entre webs. Al cambiarla se rehace el
# lvm-dominio-desconocido.conf de todas las versiones (como asegurar --todas, pide la contraseña) y
# se recarga el Apache de la montada si esta en marcha. Sin argumento, dice como esta
function cross_site_command() {
    local rc
    case $1 in
        "")
            if cross_site_on; then
                echo "La barrera entre webs esta encendida (nexum barrera-web no para apagarla)"
            else
                echo "La barrera entre webs esta apagada (nexum barrera-web si para encenderla)"
            fi
            return 0 ;;
        si|on) cross_site_on && { echo "La barrera entre webs ya estaba encendida"; return 0; } ;;
        no|off) cross_site_on || { echo "La barrera entre webs ya estaba apagada"; return 0; } ;;
        *) echo "Uso: nexum barrera-web [si|no]"; return 1 ;;
    esac
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] barrera entre webs $([ "$1" == si ] || [ "$1" == on ] && echo encendida || echo apagada) en todas las versiones"
        return 0
    fi
    sudo_first || return 1
    mkdir -p -m 700 "$LOG_DIR" || return 1
    if [ "$1" == si ] || [ "$1" == on ]; then
        rm -f "$CROSS_SITE_OFF"
    else
        : > "$CROSS_SITE_OFF" || return 1
    fi
    secure_all
    rc=$?
    if [ $rc -eq 2 ]; then
        # (no se ha podido aplicar: el interruptor vuelve a como estaba)
        if [ "$1" == si ] || [ "$1" == on ]; then : > "$CROSS_SITE_OFF"; else rm -f "$CROSS_SITE_OFF"; fi
        secure_all > /dev/null 2>&1
        echo "No se ha podido cambiar en todas las versiones: se deja como estaba"
        return 1
    fi
    if [ $rc -eq 0 ] && lampp_running; then
        run sudo /opt/lampp/lampp reloadapache > /dev/null || { echo "No se ha podido recargar Apache"; return 1; }
    fi
    if cross_site_on; then
        echo "Barrera entre webs encendida: otra web no puede mandar nada a tus proyectos"
    else
        echo "Barrera entre webs apagada: enciendela cuando acabes de probar la pasarela de pago"
    fi
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
        [ -n "$dir" ] || { echo "No hay ninguna version activa (indica cual: nexum asegurar <version>)"; return 1; }
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
            echo "Puede que no sea de LAMPP (otro programa en el mismo puerto): nexum procesos"
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
        *) echo "Uso: nexum servicio apache|mariadb|ftp arrancar|parar|reiniciar"; return 1 ;;
    esac
    case "$action" in
        arrancar|start) cmds=("start$c") ;;
        parar|stop) cmds=("stop$c") ;;
        reiniciar|restart) cmds=("stop$c" "start$c") ;;
        *) echo "Uso: nexum servicio apache|mariadb|ftp arrancar|parar|reiniciar"; return 1 ;;
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
    mailpit_sync
}

# Para la pestaña Servicios: S|servicio|en marcha (1/0)|puertos|abierto a la red (1/0)|arranca con
# la version (1/0)|usuario (FTP), de la version montada
function gui_services() {
    local dir ports p name running port open auto user procs
    dir=$(active_dir)
    [ -n "$dir" ] || return 0
    ports=$(exposed_ports)
    procs=$(lampp_processes)
    for name in apache mariadb ftp; do
        running=0
        service_running "$name" "$procs" && running=1
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

