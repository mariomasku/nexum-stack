#!/bin/bash
# Parches nuevos de los componentes (Linux 1.56.8, Mac 1.40.1): lo que tiene un parche publicado (cada
# version de PHP frente a lo ultimo de su rama, las imagenes de Docker frente a Docker Hub, Mailpit y
# cloudflared) y ponerlo todo al dia. Sin Internet: lo de fuera, falso. Uso: componentes.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-componentes.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function components_check() {' "$SRC" || { echo "  ok    (sin parches de componentes)"; exit 0; }
extract "$SRC" components_check components_update docker_image_outdated || exit 1
MAC=0
grep -q "LVM_SWIFT" "$SRC" && MAC=1
DRY=0 DOCKER_DIR=$W/docker DOCKER_PHP_VERSIONS="8.4 8.3" DOCKER_PMA_IMAGE=phpmyadmin:5.2 MAILPIT_VERSION=1.33.0 TUNNEL_VERSION=2026.10.0
P=$([ $MAC -eq 1 ] && echo XAMPP || echo lampp)
# Las versiones instaladas (falsas): la 8.4 con MariaDB y Apache viejos, la 8.3 al dia, un parche concreto y un XAMPP
php_releases() { echo "8.4.27 8.3.30"; }
rebuild_version() { case $1 in *8.4) echo 8.4.27 ;; *8.3) echo 8.3.30 ;; esac; }
stack_versions() { case $1 in 8.4.27) echo "8.4.27|2.4.70|11.8.9|1.3.9e|5.42.3|5.2.3" ;; 8.3.30) echo "8.3.30|2.4.x|11.4.13|1.3.9e|5.40.5|5.2.3" ;; esac; }
stack_fields() { case $1 in *8.4) echo "8.4.27|2.4.69|11.8.8|1.3.9e|5.42.3|5.2.3" ;; *8.3) echo "8.3.30|2.4.69|11.4.13|1.3.9e|5.40.5|5.2.3" ;; *7.4.33) echo "7.4.33|2.4.69|10.6.20|1.3.9e|5.36.0|4.9.11" ;; esac; }
if [ $MAC -eq 1 ]; then
    BASE_DIR=$W/apps
    for v in 8.4 8.3 7.4.33; do mkdir -p "$BASE_DIR/XAMPP-$v/xamppfiles/etc"; touch "$BASE_DIR/XAMPP-$v/xamppfiles/etc/pvm-stack"; done
    version_dirs() { printf '%s\n' "$BASE_DIR/XAMPP-7.4.33" "$BASE_DIR/XAMPP-8.3" "$BASE_DIR/XAMPP-8.4"; }
    version_name() { echo "${1##*/XAMPP-}"; }
else
    lampp_dirs() { echo /opt/lampp-7.4.33 /opt/lampp-8.1 /opt/lampp-8.3 /opt/lampp-8.4; }
    is_fpm_install() { [ "$1" != /opt/lampp-8.1 ]; }
    # (ninguna es de una pila propia: su MariaDB no se mira; las de este equipo no cuentan)
    is_stack_install() { false; }
fi
# (sus piezas, bien: las dañadas se prueban aparte, al final)
stack_broken() { :; }
# Docker: la MariaDB 11.8 y la imagen de PHP 8.4 tienen una nueva en Docker Hub
docker_ready() { true; }
docker_maria_versions() { echo 11.8; }
dk() { echo "$*" >> "$W/dk.log"; [ "$1 $2" == "image inspect" ] && [[ "$3" == nexum-php:8.4 || "$3" == phpmyadmin:5.2 ]] && return 0; [ "$1 $2" == "image inspect" ] && return 1; return 0; }
docker_image_outdated() { [[ "$1" == mariadb:11.8 || "$1" == php:8.4-* ]]; }
mailpit_installed() { true; }
mailpit_installed_version() { echo 1.32.0; }
tunnel_installed() { true; }
tunnel_installed_version() { echo 2026.10.0; }

out=$(components_check)
check "una version con parches nuevos: cada componente, con la suya y la nueva" 'grep -qx "L|8.4|Apache|2.4.69|2.4.70" <<< "$out" && grep -qx "L|8.4|MariaDB|11.8.8|11.8.9" <<< "$out"'
check "lo que no se ha podido consultar (su rama .x) no cuenta" '! grep -q "^L|8.3|" <<< "$out"'
if [ $MAC -eq 1 ]; then
    check "una XAMPP-X.Y.Z (su parche en el nombre): se dice, no se rehace" '! grep -q "^L|7.4.33" <<< "$out"'
else
    check "un parche concreto y un XAMPP oficial: se dice por que no" 'grep -q "^F|7.4.33|parche concreto" <<< "$out" && grep -q "^F|8.1|XAMPP oficial" <<< "$out"'
fi
check "Docker: las imagenes con una nueva en Docker Hub (solo las que estan)" 'grep -qx "K|mariadb:11.8|la MariaDB 11.8 común de Docker" <<< "$out" && grep -q "^K|php:8.4-" <<< "$out" && ! grep -q "^K|phpmyadmin" <<< "$out" && ! grep -q "^K|php:8.3" <<< "$out"'
check "Mailpit con una version nueva; cloudflared al dia" 'grep -qx "X|Mailpit|1.32.0|1.33.0" <<< "$out" && ! grep -q "^X|cloudflared" <<< "$out"'
check "el total" 'grep -qx "S|5" <<< "$out"'
check "sin Docker: no se pregunta a Docker" ': > "$W/dk.log"; components_check --sin-docker | grep -qx "S|3" && [ ! -s "$W/dk.log" ]'
# (1.57.31) Una pieza dañada (su programa no esta o no responde), aunque este en lo ultimo de su rama: se rehace
stack_broken() { [[ "$1" == */8.3* || "$1" == */lampp-8.3 || "$1" == */XAMPP-8.3/xamppfiles ]] && echo "MariaDB Perl"; }
[ $MAC -eq 0 ] && is_stack_install() { [ "$1" == /opt/lampp-8.3 ]; }
out=$(components_check --sin-docker)
check "pieza dañada: sale como dañado con lo ultimo de su rama, aunque su version ya sea esa" 'grep -qx "L|8.3|MariaDB|dañado|11.4.13" <<< "$out" && grep -qx "L|8.3|Perl|dañado|5.40.5" <<< "$out"'
check "pieza dañada: las demas de esa version, como siempre" '! grep -q "^L|8.3|PHP\|^L|8.3|Apache" <<< "$out"'
stack_broken() { :; }
[ $MAC -eq 0 ] && is_stack_install() { false; }
# stack_broken de verdad, con una version falsa: cada programa responde o no
extract "$SRC" stack_broken || exit 1
V=$W/pila; mkdir -p "$V/php/bin" "$V/php/sbin" "$V/apache2/bin" "$V/mysql/bin" "$V/proftpd/sbin" "$V/perl/bin" "$V/phpmyadmin"
for f in php/bin/php php/sbin/php-fpm apache2/bin/httpd mysql/bin/mariadbd mysql/bin/mariadb mysql/bin/mariadbd-safe proftpd/sbin/proftpd perl/bin/perl; do
    printf '#!/bin/sh\nexit 0\n' > "$V/$f"; chmod +x "$V/$f"
done
: > "$V/phpmyadmin/index.php"
check "stack_broken: todo bien, nada" '[ -z "$(OSTYPE=linux-gnu stack_broken "$V")" ]'
rm "$V/mysql/bin/mariadbd"; printf '#!/bin/sh\nexit 1\n' > "$V/perl/bin/perl"
check "stack_broken: lo que falta y lo que no responde" '[ "$(OSTYPE=linux-gnu stack_broken "$V")" == "MariaDB Perl" ]'
check "stack_broken: en el Mac solo que esten (Perl esta, aunque no responda)" '[ "$(OSTYPE=darwin24 stack_broken "$V")" == "MariaDB" ]'
rm "$V/phpmyadmin/index.php" "$V/apache2/bin/httpd"
check "stack_broken: phpMyAdmin sin su index.php y Apache sin su programa" '[ "$(OSTYPE=linux-gnu stack_broken "$V")" == "Apache MariaDB Perl phpMyAdmin" ]'
check "stack_broken: lo usan Componentes, actualizar y la ventana" '[ "$(grep -c "stack_broken \"\$dir" "$SRC")" -ge 3 ]'
# piezas-danadas (1.57.32): para la ventana, D|version|piezas de las pilas propias con alguna dañada
extract "$SRC" gui_broken || exit 1
stack_broken() { [[ "$1" == */lampp-8.4 || "$1" == */XAMPP-8.4/xamppfiles ]] && echo "MariaDB"; }
[ $MAC -eq 0 ] && is_stack_install() { [ "$1" != /opt/lampp-8.1 ]; }
check "piezas-danadas: solo las versiones con alguna dañada" '[ "$(gui_broken)" == "D|8.4|MariaDB" ]'
check "piezas-danadas: es una orden de nexum" 'grep -q "^    piezas-danadas) gui_broken ;;" "$SRC"'
if [ $MAC -eq 1 ]; then
    check "ventana (Mac): Versiones en rojo, Reparar en su menú y Componentes, con piezas-danadas" 'grep -q "runQuick(\[\"piezas-danadas\"\])" "$SRC" && grep -q "Button(\"Reparar (" "$SRC" && grep -q "joined(separator: \", \") + \" dañado\")" "$SRC" && grep -q "\.onAppear { model.loadBroken() }" "$SRC"'
else
    check "ventana: Versiones en rojo, Reparar en su menú y Componentes, con piezas-danadas" 'grep -q "run_quick(\[\"piezas-danadas\"\], got)" "$SRC" && grep -q "(\"Reparar (%s dañado)\" %" "$SRC" && grep -q "dmg = label(\"%s dañado\" %" "$SRC" && grep -q "cells\[n\].set_text(cells\[n\].get_text() + \" · dañado\")" "$SRC" && grep -q "elif row.tab_name == \"versiones\":" "$SRC"'
fi
stack_broken() { :; }
[ $MAC -eq 0 ] && is_stack_install() { false; }
stack_broken() { :; }
if [ $MAC -eq 0 ]; then
    # mariadb_release: de lo que publica MariaDB, solo su binario (con el mismo final van sus plugins)
    extract "$SRC" mariadb_release || exit 1
    native_binaries() { true; }
    fetch() { printf '%s' '{"releases":{"11.8.10":{"files":[
      {"file_name":"mariadb-plugin-tidesdb-11.8.10-5.2.1-linux-systemd-x86_64.tar.gz","file_download_url":"https://downloads.mariadb.org/p.tar.gz","checksum":{"sha256sum":"'"$(printf 'a%.0s' $(seq 64))"'"}},
      {"file_name":"mariadb-11.8.10-linux-x86_64.tar.gz","file_download_url":"https://downloads.mariadb.org/b.tar.gz","checksum":{"sha256sum":"'"$(printf 'c%.0s' $(seq 64))"'"}},
      {"file_name":"mariadb-11.8.10-linux-systemd-x86_64.tar.gz","file_download_url":"http://downloads.mariadb.org/m.tar.gz","checksum":{"sha256sum":"'"$(printf 'b%.0s' $(seq 64))"'"}},
      {"file_name":"mariadb-11.8.10.tar.gz","file_download_url":"https://downloads.mariadb.org/s.tar.gz","checksum":{"sha256sum":"'"$(printf 'd%.0s' $(seq 64))"'"}}]}}}'; }
    check "mariadb_release: el binario de MariaDB (con systemd), no uno de sus plugins" '[ "$(mariadb_release 11.8 | cut -d"|" -f1,2)" == "11.8.10|https://downloads.mariadb.org/m.tar.gz" ]'
    native_binaries() { false; }
    check "mariadb_release: sin binarios, su codigo fuente" '[ "$(mariadb_release 11.8 | cut -d"|" -f2)" == "https://downloads.mariadb.org/s.tar.gz" ]'
    fetch() { printf '%s' '{"releases":{"11.8.10":{"files":[{"file_name":"mariadb-plugin-tidesdb-11.8.10-5.2.1-linux-systemd-x86_64.tar.gz","file_download_url":"https://downloads.mariadb.org/p.tar.gz","checksum":{"sha256sum":"'"$(printf 'a%.0s' $(seq 64))"'"}}]}}}'; }
    native_binaries() { true; }
    check "mariadb_release: si solo hay plugins, nada (no se instala uno de ellos como MariaDB)" '[ -z "$(mariadb_release 11.8)" ]'
fi

# Ponerlo al dia: cada cosa con lo suyo
mkdir -p "$DOCKER_DIR/mariadb-11.8"
printf 'services:\n  db:\n    environment:\n      MARIADB_ROOT_PASSWORD: ${DB_ROOT_PASS}\n    command: []\n' > "$DOCKER_DIR/mariadb-11.8/compose.yaml"
docker_maria_name() { echo nexum-mariadb-11-8; }
docker_maria_up() { echo "maria_up $1" >> "$W/hecho.log"; }
docker_php_image() { echo "php_image $*" >> "$W/hecho.log"; }
docker_projects() { echo blog; }
docker_conf() { [ "$2" == PHP ] && echo "8.4 8.3"; }
docker_web_state() { echo marcha; }
docker_web_up() { echo web_up >> "$W/hecho.log"; }
mailpit_install() { echo mailpit_install >> "$W/hecho.log"; }
tunnel_install() { echo tunnel_install >> "$W/hecho.log"; }
cli_rebuild() { echo "rebuild $1" >> "$W/hecho.log"; }
dk() { echo "$*" >> "$W/dk.log"
       case "$1 $2" in "image inspect") [[ "$3" == nexum-php:8.4 || "$3" == phpmyadmin:5.2 ]] ;; "ps -q") echo abc ;; "ps --filter") echo php84 ;; *) return 0 ;; esac; }
: > "$W/dk.log"; : > "$W/hecho.log"
DRY=1 components_update > "$W/o" 2>&1
check "simulacion: dice lo que haria y no hace nada" 'grep -q "MariaDB 11.8.8 → 11.8.9" "$W/o" && [ ! -s "$W/hecho.log" ] && ! grep -q "^pull" "$W/dk.log"'
components_update > "$W/o" 2>&1; rc=$?
check "termina bien" '[ $rc -eq 0 ] && grep -q "Todo al día" "$W/o"'
check "la version de PHP se rehace una vez (aunque tenga varios parches)" '[ "$(grep -c "^rebuild 8.4$" "$W/hecho.log")" == 1 ] && ! grep -q "rebuild 8.3\|rebuild 7.4" "$W/hecho.log"'
check "MariaDB comun: imagen nueva, su contenedor de nuevo y que se ponga al dia sola" 'grep -qx "pull mariadb:11.8" "$W/dk.log" && grep -qx "maria_up 11.8" "$W/hecho.log" && grep -qx "      MARIADB_AUTO_UPGRADE: \"1\"" "$DOCKER_DIR/mariadb-11.8/compose.yaml" && [ "$(grep -c AUTO_UPGRADE "$DOCKER_DIR/mariadb-11.8/compose.yaml")" == 1 ]'
check "imagen de PHP: de nuevo, y los contenedores en marcha que la usan, rehechos" 'grep -q "^php_image 8.4 --nueva$" "$W/hecho.log" && grep -q "compose .*up -d php84" "$W/dk.log"'
check "Mailpit, con la suya; cloudflared, nada" 'grep -qx mailpit_install "$W/hecho.log" && ! grep -q tunnel_install "$W/hecho.log"'
components_update > /dev/null 2>&1
check "dos veces: MARIADB_AUTO_UPGRADE una sola vez" '[ "$(grep -c AUTO_UPGRADE "$DOCKER_DIR/mariadb-11.8/compose.yaml")" == 1 ]'
cli_rebuild() { echo "rebuild $1" >> "$W/hecho.log"; return 1; }
components_update > "$W/o" 2>&1; rc=$?
check "si algo falla, se dice (y lo demas se hace)" '[ $rc -ne 0 ] && grep -q "Algo no se ha podido actualizar" "$W/o"'
php_releases() { :; }; docker_ready() { false; }; mailpit_installed_version() { echo 1.33.0; }
components_update > "$W/o" 2>&1; rc=$?
check "nada que actualizar: lo dice (y lo que no se ha podido consultar)" '[ $rc -eq 0 ] && grep -q "Todo está al día" "$W/o" && grep -q "no se ha podido consultar: php.net" "$W/o"'

# La ventana
if [ $MAC -eq 1 ]; then
    check "ventana (Mac): Parches nuevos en Configuración (en General) y, al abrir, en los avisos (1.41.1); Mailpit en tarjetas" 'grep -q "^                componentsCard()$" "$SRC" && grep -q "self.autoCheckComponents()" "$SRC" && grep -qF "solo se ve desde este Mac.\", tiles: true," "$SRC"'
else
    check "ventana: Parches nuevos en Configuración y, al abrir, en los avisos (1.57.2); Mailpit en tarjetas" 'grep -q "^        self.nv_components_tools()$" "$SRC" && grep -q "GLib.timeout_add_seconds(25, self.nv_components_auto)" "$SRC" && grep -q "tile_group(\"Correo de pruebas (Mailpit)\", tiles=True," "$SRC"'
fi
exit $fail
