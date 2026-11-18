#!/bin/bash
# Pruebas de WP_SITEURL y WP_HOME con el dominio falseado o no (1.57.23): el wp-config.php de un
# WordPress con dominio propio lleva las dos parejas, la de web.local y la del dominio, y solo una sin
# comentar: la del dominio mientras esta falseado en hosts y la de web.local cuando no (sin falsear,
# el dominio es produccion). Uso: wp-falseo.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-wpf.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
extract "$SRC" wp_local_url wp_link_url wp_folder_domain domain_faked wp_urls_sync wp_urls_sync_all valid_domain || exit 1
DRY=0 HTDOCS_DIR=$W/htdocs HOSTS_FILE=$W/hosts CUSTOM_DOMAINS_FILE=$W/dominios PROJECT_VHOST=web.local
mkdir -p "$HTDOCS_DIR/tienda" "$HTDOCS_DIR/blog" "$HTDOCS_DIR/sin"
valid_project() { return 0; }
project_path_ok() { return 0; }
project_link() { echo web.local; }
project_write() { cp "$1" "$2"; }
custom_domain() { awk -F= -v f="$1" '$2 == f { print $1 }' "$CUSTOM_DOMAINS_FILE"; }
vhosts_info() { printf '443|web.local|web.local||/c/w.crt|/c/w.key\n443|blog|miblog.es|www.miblog.es|/c/b.crt|/c/b.key\n'; }
echo "panaderia-luna.com=tienda" > "$CUSTOM_DOMAINS_FILE"
cfg() { printf "<?php\r\ndefine('DB_NAME', 'b');\r\n\$table_prefix = 'wp_';\r\n" > "$HTDOCS_DIR/$1/wp-config.php"; }
f=$HTDOCS_DIR/tienda/wp-config.php
act() { grep -E "^define\('$1'" "$f" | sed -E "s/.*, '([^']*)'.*/\1/"; }
com() { grep -cE "^// define\('$1', '$2'\);" "$f"; }

# Sin falsear: web.local sin comentar y el dominio comentado
printf '127.0.0.1 localhost web.local\n#127.0.0.1 panaderia-luna.com www.panaderia-luna.com\n' > "$HOSTS_FILE"
cfg tienda; cfg blog; cfg sin
check "sin falsear, la direccion local es la de web.local" '[ "$(wp_local_url tienda)" = https://web.local ]'
out=$(wp_urls_sync tienda)
check "sin falsear: WP_SITEURL y WP_HOME en web.local" '[ "$(act WP_SITEURL)" = https://web.local ] && [ "$(act WP_HOME)" = https://web.local ]'
check "sin falsear: la pareja del dominio, comentada" '[ "$(com WP_SITEURL https://panaderia-luna.com)" = 1 ] && [ "$(com WP_HOME https://panaderia-luna.com)" = 1 ]'
check "dice que el dominio sin falsear es produccion" 'grep -q "sin falsear es produccion" <<< "$out"'
check "conserva los finales de linea CRLF" '[ "$(grep -c $'"'"'\r$'"'"' "$f")" = "$(wc -l < "$f")" ]'
# Falseado: al reves
printf '127.0.0.1 localhost web.local\n127.0.0.1 panaderia-luna.com www.panaderia-luna.com\n' > "$HOSTS_FILE"
check "falseado, la direccion local es la del dominio" '[ "$(wp_local_url tienda)" = https://panaderia-luna.com ]'
wp_urls_sync tienda > /dev/null
check "falseado: WP_SITEURL y WP_HOME en el dominio" '[ "$(act WP_SITEURL)" = https://panaderia-luna.com ] && [ "$(act WP_HOME)" = https://panaderia-luna.com ]'
check "falseado: la pareja de web.local, comentada" '[ "$(com WP_SITEURL https://web.local)" = 1 ] && [ "$(com WP_HOME https://web.local)" = 1 ]'
check "solo una pareja sin comentar y una sola de cada" '[ "$(grep -cE "^define\(.WP_(SITEURL|HOME)" "$f")" = 2 ] && [ "$(grep -c "define(.WP_SITEURL" "$f")" = 2 ] && [ "$(grep -c "^// nexum: WP_SITEURL y WP_HOME" "$f")" = 1 ]'
cp "$f" "$W/antes"
out=$(wp_urls_sync tienda --callado)
check "otra vez, no cambia nada ni dice nada (--callado)" 'cmp -s "$f" "$W/antes" && [ -z "$out" ]'
# Uno de produccion pegado encima: la pareja de produccion sin comentar se cambia
sed -i "s#^define('WP_HOME', 'https://panaderia-luna.com');#define('WP_HOME', 'https://otra-web.com');#" "$f"
printf "define('WP_SITEURL', 'https://otra-web.com');\r\n" >> "$f"
wp_urls_sync tienda > /dev/null
check "las que no son de ninguna pareja y sin comentar se quitan (solo puede ir una)" '! grep -q "otra-web.com" "$f" && [ "$(act WP_HOME)" = https://panaderia-luna.com ]'
# Una comentada del proyecto, con otra direccion, se queda
printf "// define('WP_HOME', 'https://staging.panaderia-luna.com');\r\n" >> "$f"
wp_urls_sync tienda > /dev/null
check "una comentada del proyecto con otra direccion no se toca" 'grep -q "staging.panaderia-luna.com" "$f"'
# Dominio por su vhost (sin el fichero de dominios), y wp_urls_sync_all despues de cambiar hosts
printf '127.0.0.1 localhost web.local\n127.0.0.1 miblog.es www.miblog.es\n#127.0.0.1 panaderia-luna.com www.panaderia-luna.com\n' > "$HOSTS_FILE"
out=$(wp_urls_sync_all)
check "sync_all: el del vhost falseado pasa a su dominio" 'grep -q "^define(.WP_HOME., .https://miblog.es.)" "$HTDOCS_DIR/blog/wp-config.php"'
check "sync_all: el que deja de estar falseado vuelve a web.local" '[ "$(act WP_HOME)" = https://web.local ]'
check "sync_all: dice cuales cambian" 'grep -q "WordPress de blog" <<< "$out" && grep -q "WordPress de tienda" <<< "$out"'
check "sin dominio propio: no se toca" '! grep -q WP_HOME "$HTDOCS_DIR/sin/wp-config.php"'
# Simulacion: no escribe
DRY=1; printf '127.0.0.1 localhost web.local\n127.0.0.1 panaderia-luna.com\n' > "$HOSTS_FILE"; cp "$f" "$W/antes"
out=$(wp_urls_sync tienda)
check "en simulacion no escribe y dice lo que haria" 'cmp -s "$f" "$W/antes" && grep -q "simulacion.*https://panaderia-luna.com" <<< "$out"'
exit $fail
