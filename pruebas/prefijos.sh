#!/bin/bash
# Pruebas del prefijo de las tablas al rehacer wp-config.php (Linux 1.47.0 / Mac 1.35.0): siempre uno
# que traen las tablas de la base; con varios WordPress en la base, el del wp-config.php del proyecto
# o el de la plantilla; si no se sabe cual, no se toca. (ps_table_prefix, en volcados.sh)
# Uso: prefijos.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-pref.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
extract "$SRC" wp_config wp_config_read || exit 1
DRY=1 HTDOCS_DIR=$W/htdocs WP_CONFIG_DIR=$W/wpc DB_SAFE=() DB_CLIENT=true
mkdir -p "$HTDOCS_DIR/web" "$WP_CONFIG_DIR"
valid_project() { return 0; }
project_path_ok() { return 0; }
saved_project_db() { echo base; }
db_exists() { return 0; }
db_login_ok() { return 1; }
wp_local_url() { echo https://web.local; }
# cfg <prefijo>: wp-config.php del proyecto con otra base (asi se rehace)
cfg() { printf "<?php\ndefine('DB_NAME', 'otra');\ndefine('DB_USER', 'u');\ndefine('DB_PASSWORD', 'p');\ndefine('DB_HOST', 'localhost');\n\$table_prefix = '%s';\n" "$1" > "$HTDOCS_DIR/web/wp-config.php"; }
run_wp() { wp_config web 2>&1; }
PREFIXES="wp_"; wp_table_prefixes() { printf '%s\n' "$PREFIXES"; }
cfg abc_
check "un WordPress en la base: su prefijo, aunque el wp-config.php traiga otro" 'run_wp | grep -q "Prefijo de las tablas: wp_ (era abc_)"'
PREFIXES=$'wp_\nxyz_'
cfg xyz_
check "varios: el del wp-config.php del proyecto si la base lo tiene" 'out=$(run_wp); grep -q "Se cambia a la base base" <<< "$out" && ! grep -q "Prefijo de las tablas" <<< "$out"'
cp "$HTDOCS_DIR/web/wp-config.php" "$WP_CONFIG_DIR/web.wp-config.php"; sed -i "s/'xyz_'/'wp_'/" "$WP_CONFIG_DIR/web.wp-config.php"
check "varios: el del proyecto antes que el de la plantilla de este equipo" 'run_wp | grep -q "Prefijo de las tablas: xyz_ (era wp_)"'
cfg abc_
check "varios: si el del proyecto no esta, el de la plantilla" 'out=$(run_wp); grep -q "Se rehace con la plantilla" <<< "$out" && ! grep -q "Prefijo de las tablas" <<< "$out"'
rm "$WP_CONFIG_DIR/web.wp-config.php"
check "varios y ninguno sirve: no se toca (ni se escribe un prefijo sin tablas)" 'out=$(run_wp); grep -q "no usa ninguno: no se toca" <<< "$out" && ! grep -q "Se cambia" <<< "$out"'
check "nunca se renombran tablas" '! grep -qi "RENAME TABLE" "$SRC"'
exit $fail
