#!/bin/bash
# Parches concretos de PHP en el Mac (1.57.5, como en Linux): gui-parches lista los de una rama y
# «instalar --php» acepta X.Y.Z (en su carpeta XAMPP-X.Y.Z). Con php.net de mentira, sin red.
# Uso: parches-mac.sh <script del Mac>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/parches-mac.XXXXXX") || exit 1
trap 'rm -rf "${W:?}"' EXIT
fn() { awk -v f="function $1() {" '$0 == f {p=1} p {print} p && /^}$/ {exit}' "$SRC"; }
for f in php_patches gui_patches cli_install; do fn "$f"; done > "$W/f.sh"
check "las tres funciones están en el script" '[ "$(grep -c "^function " "$W/f.sh")" -eq 3 ]'
BASE_DIR=$W/Nexum; mkdir -p "$BASE_DIR/XAMPP-8.3.9"
php_releases() { printf '8.4 8.4.15 x 2026-10-01 -\n8.3 8.3.27 x 2026-10-02 seguridad\n'; }
php_all_releases() { printf '8.4.15 2026-10-01 -\n8.3.27 2026-10-02 seguridad\n8.3.10 2024-08-01 -\n8.3.9 2024-07-04 -\n8.2.30 2026-09-01 seguridad\n'; }
php_installed_in() { [ "$1" == 8.3.10 ] && echo "$BASE_DIR/XAMPP-8.3"; }
install_plan() { echo "PLAN:$1"; }
. "$W/f.sh"
out=$(gui_patches 8.3)
check "gui-parches 8.3: sus tres parches, del más nuevo al más antiguo" '[ "$(cut -d"|" -f2 <<< "$out" | tr "\n" " ")" == "8.3.27 8.3.10 8.3.9 " ]'
check "el último, marcado; con su fecha y si es de seguridad" 'grep -qx "P|8.3.27|2026-10-02|nueva|1|1" <<< "$out"'
check "ya instalado en otra carpeta: instalada" 'grep -qx "P|8.3.10|2024-08-01|instalada|0|0" <<< "$out"'
check "ya hay una XAMPP-X.Y.Z: existe" 'grep -qx "P|8.3.9|2024-07-04|existe|0|0" <<< "$out"'
check "una rama que no se puede instalar: error" 'gui_patches 8.2 | grep -q "^ERROR|" && gui_patches "8.3;x" | grep -q "^ERROR|"'
php_all_releases() { printf '8.4.15 2026-10-01 -\n8.3.27 2026-10-02 seguridad\n8.3.10 2024-08-01 -\n8.3.8 2024-06-06 -\n'; }
php_installed_in() { return 1; }
rm -rf "$BASE_DIR/XAMPP-8.3.9"
out=$(cli_install --php 8.4,8.3.8 --si)
check "instalar --php 8.4,8.3.8: el último de 8.4 y ese parche de 8.3" 'grep -qx "PLAN: php:8.4.15 php:8.3.8" <<< "$out"'
out=$(cli_install --php 8.3.99 --si)
check "un parche que no está en php.net, se omite" 'grep -q "PHP 8.3.99 no esta en php.net, se omite" <<< "$out" && ! grep -q "^PLAN" <<< "$out"'
out=$(cli_install --php 8.2.30 --si)
check "un parche de una rama que no se puede instalar, se omite" 'grep -q "PHP 8.2 no esta disponible, se omite 8.2.30" <<< "$out" && ! grep -q "^PLAN" <<< "$out"'
check "ventana: Otro parche concreto, con su rama y sus parches" 'grep -qF "func patchCard(_ list: [Branch]) -> some View {" "$SRC" && grep -qF "runQuick([\"gui-parches\", branch])" "$SRC" && grep -qF "patchCard(list)" "$SRC"'
check "ventana: la carpeta instalada, con la versión entera (salvo rehacer:)" 'grep -qF "if !item.hasPrefix(\"rehacer:\") { return name }" "$SRC"'
check "la orden gui-parches, registrada" 'grep -qF "    gui-parches) gui_patches \"\$2\" ;;" "$SRC"'
exit $fail
