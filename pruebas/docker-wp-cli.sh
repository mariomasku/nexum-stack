#!/bin/bash
# Pruebas de WP-CLI en las imagenes de PHP de Docker (1.57.37): una opcion de Configuracion > Docker, apagada
# de serie (docker-wp-cli si|no [--rehacer]). Puesta, nexum-php:<version> trae wp, fijado por su huella, y las
# imagenes sin el (sin la etiqueta nexum.wp-cli) se rehacen al prepararlas y salen en Componentes.
# Sin Docker: la orden dk es falsa. Uso: docker-wp-cli.sh <lvm-instalador.sh de Linux o del Mac>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-wpcli.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
extract "$SRC" docker_wp_cli_on docker_wp_cli_dockerfile docker_php_has_wp_cli docker_php_needs_wp_cli docker_wp_cli_command docker_php_image \
    docker_php_ext docker_pg_dockerfile docker_php_needs_pgsql docker_pg_versions || exit 1
# (el Mac: las reglas de la web del contenedor van en la imagen)
grep -q "^function docker_web_rules() {" "$SRC" && { extract "$SRC" docker_web_rules || exit 1; }
eval "$(grep -E '^(WP_CLI_VERSION|WP_CLI_SHA256|DOCKER_EXT_INSTALLER|DOCKER_IMAGE_SCHEMA|DOCKER_PG_VERSIONS)=' "$SRC")"
php_85_or_later() { [ "$(printf '%s\n' 8.5 "$1" | sort -V | head -1)" == 8.5 ]; }
PHP_SECURE_INI="expose_php = Off" PHP_SECURE_INI_85="fatal_error_backtraces = 0" DOCKER_PHP_EXT="mysqli gd"
DOCKER_DIR=$W/docker DRY=0
# (dk falsa: IMG=1 si la imagen esta, con la etiqueta LABEL_WP; lo que se construye y se vuelve a crear, a su registro)
IMG=0 LABEL_WP=""
dk() {
    case "$1 $2" in
        "image inspect")
            [ "$IMG" == 1 ] || return 1
            case "$*" in *nexum.wp-cli*) echo "$LABEL_WP" ;; *nexum.esquema*) echo "$DOCKER_IMAGE_SCHEMA" ;; esac ;;
        "build "*) echo "build $*" >> "$W/dk.log" ;;
        "ps "*) echo php85 ;;
        "compose "*) echo "compose $*" >> "$W/dk.log" ;;
    esac
}
run() { "$@"; }
docker_ready() { return 0; }
docker_projects() { echo tienda; }
task_plan() { echo "plan $*" >> "$W/dk.log"; }
task_step() { :; }
DOCKER_PHP_VERSIONS="8.4 8.5"
D=$DOCKER_DIR/imagenes/php-8.5/Dockerfile
build() { : > "$W/dk.log"; IMG=$1 LABEL_WP=$2 docker_php_image "$3" "${@:4}" > /dev/null; }

check "WP-CLI fijado: version y huella sha256" '[[ "$WP_CLI_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$WP_CLI_SHA256" =~ ^[0-9a-f]{64}$ ]]'
# Apagado (de serie): la imagen, como siempre
build 0 "" 8.5
check "apagado: la imagen se construye sin WP-CLI" 'grep -q "^build " "$W/dk.log" && ! grep -q "wp-cli" "$D" && grep -qx "RUN install-php-extensions mysqli gd" "$D" && grep -q "php.ini-production" "$D"'
build 1 "" 8.5
check "apagado: una imagen que ya esta no se toca" '[ ! -s "$W/dk.log" ]'
build 1 "$WP_CLI_VERSION" 8.5
check "apagado: tampoco la que lo trae (hasta que se rehaga)" '[ ! -s "$W/dk.log" ]'
# Puesto
docker_wp_cli_command si > "$W/out"
check "docker-wp-cli si: lo pone (sin --rehacer, las imagenes no se tocan)" '[ -f "$DOCKER_DIR/wp-cli" ] && grep -q "puesto" "$W/out" && grep -q "la proxima vez que se rehaga" "$W/out"'
build 0 "" 8.5
check "puesto: el Dockerfile lo descarga de su publicacion y comprueba la huella antes de instalarlo" 'grep -qF "https://github.com/wp-cli/wp-cli/releases/download/v$WP_CLI_VERSION/wp-cli-$WP_CLI_VERSION.phar" "$D" && grep -qF "echo \"$WP_CLI_SHA256  /usr/local/lib/wp-cli.phar\" | sha256sum -c - " "$D" && grep -qF "curl -q --proto =https -fsSL" "$D"'
check "puesto: con su etiqueta, la de su version" 'grep -qx "LABEL nexum.wp-cli=\"$WP_CLI_VERSION\"" "$D"'
check "wp: el .phar con --allow-root y sin los avisos de lo obsoleto" 'grep -qF "exec php -d error_reporting=8191 /usr/local/lib/wp-cli.phar --allow-root \"\$@\"\\n'"'"' > /usr/local/bin/wp" "$D" && grep -qF "chmod 755 /usr/local/bin/wp" "$D"'
check "WP-CLI despues de las extensiones y antes del arranque" '[ "$(grep -nE "^RUN install-php-extensions" "$D" | cut -d: -f1)" -lt "$(grep -n "nexum.wp-cli" "$D" | cut -d: -f1)" ] && [ "$(grep -n "nexum.wp-cli" "$D" | cut -d: -f1)" -lt "$(grep -n "^CMD" "$D" | cut -d: -f1)" ] && [ "$(grep -c "^FROM " "$D")" -eq 1 ]'
build 1 "" 8.4
check "puesto: una imagen sin WP-CLI se rehace al prepararla" 'grep -q "^build " "$W/dk.log"'
build 1 1.0.0 8.4
check "puesto: y una con otro WP-CLI" 'grep -q "^build " "$W/dk.log"'
build 1 "$WP_CLI_VERSION" 8.4
check "puesto: con este WP-CLI, no se toca" '[ ! -s "$W/dk.log" ]'
build 1 "$WP_CLI_VERSION" 8.4 --rehacer
check "--rehacer: se rehace con lo ya descargado (sin --pull ni --no-cache)" 'grep -q "^build " "$W/dk.log" && ! grep -qE -- "--pull|--no-cache" "$W/dk.log"'
IMG=1 LABEL_WP=""; check "docker_php_needs_wp_cli: puesto y sin el, si" 'docker_php_needs_wp_cli 8.4'
IMG=1 LABEL_WP=$WP_CLI_VERSION; check "docker_php_needs_wp_cli: con el, no" '! docker_php_needs_wp_cli 8.4'
# docker-wp-cli ... --rehacer: las imagenes que hay, y los contenedores en marcha de nuevo
: > "$W/dk.log"; IMG=1 LABEL_WP=""
docker_wp_cli_command si --rehacer > "$W/out"
check "si --rehacer: rehace las dos imagenes sin el y vuelve a crear los contenedores en marcha" '[ "$(grep -c "^build " "$W/dk.log")" -eq 2 ] && grep -q "^plan WP-CLI en las imágenes de PHP Imagen de PHP 8.4 Imagen de PHP 8.5 Volver a crear" "$W/dk.log" && grep -q "^compose .*/tienda/compose.yaml up -d php85$" "$W/dk.log" && grep -q "traen WP-CLI" "$W/out"'
: > "$W/dk.log"; IMG=1 LABEL_WP=$WP_CLI_VERSION
docker_wp_cli_command si --rehacer > "$W/out"
check "si --rehacer: si ya lo traen, nada que rehacer" '! grep -q "^build " "$W/dk.log" && grep -q "nada que rehacer" "$W/out"'
: > "$W/dk.log"
docker_wp_cli_command no --rehacer > "$W/out"
check "no --rehacer: lo quita y rehace las que lo traen, ya sin el" '[ ! -f "$DOCKER_DIR/wp-cli" ] && [ "$(grep -c "^build " "$W/dk.log")" -eq 2 ] && ! grep -q "wp-cli" "$D" && grep -q "ya no traen WP-CLI" "$W/out"'
check "docker-wp-cli: otra cosa, su uso" '! docker_wp_cli_command quizas > "$W/out" && grep -q "^Uso: nexum docker-wp-cli si|no \[--rehacer\]" "$W/out"'
DRY=1; check "en simulacion no cambia nada" 'docker_wp_cli_command si > "$W/out" && [ ! -f "$DOCKER_DIR/wp-cli" ] && grep -q "\[simulacion\]" "$W/out"'; DRY=0
check "Componentes ofrece rehacer las imagenes sin WP-CLI, solo con la opcion puesta" 'grep -qF "if docker_php_needs_wp_cli \"\$v\"; then" "$SRC" && grep -qF "(nexum-php:\$v), para que traiga WP-CLI\"" "$SRC"'
check "la orden, sin la contraseña de administrador" 'grep -qF "    docker-wp-cli) docker_wp_cli_command \"\$2\" \"\$3\" ;;" "$SRC" && grep -qxF "        docker-wp-cli) ;;" "$SRC"'
if grep -q "^import gi" <(sed -n '/^LVM_GUI_PY/,$p' "$SRC" | head -200) || grep -q "gi.require_version" "$SRC"; then
    check "Linux: el interruptor en Configuración > Docker, y pregunta si rehacer ya" 'grep -qF "row = ActionRow(\"WP-CLI en los contenedores de PHP\"" "$SRC" && grep -qF "now = Gtk.CheckButton(label=\"Rehacer ya las imágenes de PHP que tienes (unos minutos cada una)\", active=True)" "$SRC" && grep -qF "args = [\"docker-wp-cli\", \"si\" if on else \"no\"] + ([\"--rehacer\"] if now.get_active() else [])" "$SRC"'
else
    check "Mac: el interruptor en Configuración > Docker, y pregunta si rehacer ya" 'grep -qF "          WpCliCard()" "$SRC" && grep -qF "checkbox: \"Rehacer ya las imágenes de PHP que tienes (unos minutos cada una)\", checked: true)" "$SRC" && grep -qF "[\"docker-wp-cli\", v ? \"si\" : \"no\"] + (r.checked ? [\"--rehacer\"] : [])" "$SRC"'
fi
exit $fail
