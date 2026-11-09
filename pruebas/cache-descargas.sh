#!/bin/bash
# Cache de descargas de las pilas propias (1.57.6): lo ya comprobado no se descarga otra vez, si su
# web no responde se usa el de la cache, lo cambiado en la cache no se usa, de cada familia solo el
# ultimo usado, el ultimo parche de la cache si no se puede consultar y vaciarla.
# Uso: cache-descargas.sh <script>
SRC=$(readlink -f "$1") HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q "^function stack_cache_store()" "$SRC" || { echo "  ok    (sin cache de descargas)"; exit 0; }
W=$(mktemp -d "$TMPBASE/cache-descargas.XXXXXX") || exit 1
trap 'rm -rf "${W:?}"' EXIT
extract "$SRC" dl_sha256 dl_cache_trusted dl_cache_sum dl_from_cache dl_note dl_cache_latest dl_re \
    stack_cache_fallback dl_fallback_note stack_cache_store downloads_command download download_apache || exit 1
MAC=0
if grep -q "^function download_checked()" "$SRC"; then
    extract "$SRC" download_checked download_signed || exit 1
else
    MAC=1
    extract "$SRC" sha256_of || exit 1
fi
eval "$(awk '/^DL_CACHE_PY=/ {p=1} p {print} p && /^'"'"'$/ {exit}' "$SRC")"
[ -n "$DL_CACHE_PY" ] || { echo "no esta DL_CACHE_PY"; exit 1; }

TEST_DIR=$W SUDO="" DRY=0 DL_CACHE_DIR=$W/descargas
# Firmas: se apuntan (las de la cache no se comprueban otra vez)
verify_sig() { echo "$1" >> "$W/firmas.log"; }
gpg_verify() { echo "$1" >> "$W/firmas.log"; }
# curl falso: https://x/<nombre> da "contenido de <nombre>"; con $W/caida, nada responde
curl() {
    local out="" u="${*: -1}"
    while [ $# -gt 0 ]; do [ "$1" == -o ] && out=$2; shift; done
    echo "$u" >> "$W/curl.log"
    [ -f "$W/caida" ] && return 22
    case $u in
        https://x/*) printf 'contenido de %s\n' "${u##*/}" > "$out" ;;
        *) return 22 ;;
    esac
}
sum_of() { printf 'contenido de %s\n' "$1" | dl_sha256 /dev/stdin; }
# download <url> <archivo> <suma> <nombre>, en los dos (en el Mac el nombre va despues de la firma)
dl() {
    if [ $MAC -eq 0 ]; then download "$1" "$2" "$3" "$4"; else download "$1" "$2" "$3" "" "" "$4"; fi
}
new_build() { build=$W/build$1; mkdir -p "$build"; cd "$build" || exit 1; : > "$W/curl.log"; : > "$W/firmas.log"; }

S1=$(sum_of php-8.4.27.tar.xz)
new_build 1
dl https://x/php-8.4.27.tar.xz php.tar.xz "$S1" > "$W/salida" 2>&1
check "la primera vez se descarga" 'grep -q php-8.4.27 "$W/curl.log" && [ -s php.tar.xz ]'
check "y se apunta para la cache" 'grep -qx "php.tar.xz|php-8.4.27.tar.xz|$S1" "$build/descargas.lista"'
stack_cache_store > "$W/salida" 2>&1
check "al terminar se guarda en la cache, con su suma" '[ -f "$DL_CACHE_DIR/php-8.4.27.tar.xz" ] && grep -q "^$S1 " "$DL_CACHE_DIR/php-8.4.27.tar.xz.sha256" && grep -q "1 fichero" "$W/salida"'

new_build 2
dl https://x/php-8.4.27.tar.xz php.tar.xz "$S1" > "$W/salida" 2>&1
check "la segunda vez sale de la cache (sin descargar)" '! grep -q php-8.4.27 "$W/curl.log" && [ "$(dl_sha256 php.tar.xz)" = "$S1" ] && grep -q "de la cache" "$W/salida"'
touch "$W/caida"
new_build 3
dl https://x/php-8.4.27.tar.xz php.tar.xz "" > "$W/salida" 2>&1
check "su web no da la suma: el de la cache, con la suma guardada" '[ "$(dl_sha256 php.tar.xz)" = "$S1" ] && grep -q "no da la suma" "$W/salida"'
dl https://x/php-8.4.30.tar.xz php2.tar.xz "" > /dev/null 2>&1
check "uno que no esta en la cache, sin suma: no se instala" '[ ! -e php2.tar.xz ]'
rm -f "$W/caida"

new_build 4
dl https://x/php-8.4.27.tar.xz php.tar.xz "$(sum_of otra-cosa)" > /dev/null 2>&1
check "con otra suma (otro fichero) no se usa el de la cache" 'grep -q php-8.4.27 "$W/curl.log"'
echo cambiado > "$DL_CACHE_DIR/php-8.4.27.tar.xz"
new_build 5
dl https://x/php-8.4.27.tar.xz php.tar.xz "$S1" > /dev/null 2>&1
check "cambiado en la cache: se descarga otra vez" 'grep -q php-8.4.27 "$W/curl.log" && [ "$(dl_sha256 php.tar.xz)" = "$S1" ]'
touch "$W/caida"
new_build 6
dl https://x/php-8.4.27.tar.xz php.tar.xz "" > /dev/null 2>&1
check "cambiado en la cache y sin web: no se usa" '[ ! -e php.tar.xz ]'
rm -f "$W/caida"
new_build 5
stack_cache_store > /dev/null 2>&1
check "y al guardar se rehace bien" '[ "$(dl_sha256 "$DL_CACHE_DIR/php-8.4.27.tar.xz")" = "$S1" ]'

# Firmas: la de la cache ya se comprobo
new_build 7
download_apache "httpd/httpd-2.4.62.tar.bz2" httpd.tar.bz2 > /dev/null 2>&1
check "Apache sin web y sin cache: no se instala" '[ ! -s httpd.tar.bz2 ]'
printf 'contenido de httpd-2.4.62.tar.bz2\n' > "$W/httpd"
mkdir -p "$W/build8" && cp "$W/httpd" "$W/build8/httpd.tar.bz2"
echo "httpd.tar.bz2|httpd-2.4.62.tar.bz2|$(sum_of httpd-2.4.62.tar.bz2)" > "$W/build8/descargas.lista"
build=$W/build8 stack_cache_store > /dev/null 2>&1
touch "$W/caida"
new_build 9
download_apache "httpd/httpd-2.4.62.tar.bz2" httpd.tar.bz2 > "$W/salida" 2>&1
check "Apache sin web: el de la cache, sin volver a pedir su firma" '[ "$(dl_sha256 httpd.tar.bz2)" = "$(sum_of httpd-2.4.62.tar.bz2)" ] && [ ! -s "$W/firmas.log" ]'
rm -f "$W/caida"

# Solo lo de la carpeta de la compilacion, sin seguir enlaces
new_build 10
echo secreto > "$W/fuera"
ln -s "$W/fuera" enlace.tar.gz
echo "enlace.tar.gz|fuera-1.0.0.tar.gz|$(dl_sha256 "$W/fuera")" > descargas.lista
echo "../fuera|fuera-2.0.0.tar.gz|$(dl_sha256 "$W/fuera")" >> descargas.lista
stack_cache_store > /dev/null 2>&1
check "un enlace o una ruta de fuera no se guardan" '[ ! -e "$DL_CACHE_DIR/fuera-1.0.0.tar.gz" ] && [ ! -e "$DL_CACHE_DIR/fuera-2.0.0.tar.gz" ]'

# De cada familia, solo el ultimo usado
for v in 8.4.28 8.3.10; do
    new_build "p$v"
    dl "https://x/php-$v.tar.xz" php.tar.xz "$(sum_of "php-$v.tar.xz")" > /dev/null 2>&1
    sleep 1
    stack_cache_store > /dev/null 2>&1
done
check "PHP 8.4.28 sustituye a la 8.4.27 en la cache" '[ -f "$DL_CACHE_DIR/php-8.4.28.tar.xz" ] && [ ! -e "$DL_CACHE_DIR/php-8.4.27.tar.xz" ] && [ ! -e "$DL_CACHE_DIR/php-8.4.27.tar.xz.sha256" ]'
check "y la 8.3.10 (otra rama) se queda" '[ -f "$DL_CACHE_DIR/php-8.3.10.tar.xz" ]'

# El ultimo parche de la cache si no se puede consultar
for n in mariadb-11.4.5-fuente.tar.gz mariadb-11.8.2-fuente.tar.gz proftpd-1.3.9a.tar.gz perl-5.40.1.tar.xz \
        apr-1.7.5.tar.bz2 apr-util-1.6.3.tar.bz2; do
    printf 'contenido de %s\n' "$n" > "$DL_CACHE_DIR/$n"
    echo "$(sum_of "$n")  $n" > "$DL_CACHE_DIR/$n.sha256"
done
version=8.4.28 branches=(2.4 11.4 1.3.9 5.40) php_sha="" apache="" apr="" aprutil="" mariadb="" mariadb_info="" ftp="" perl=5.40.3
stack_cache_fallback fuente > "$W/salida"
check "sin web: el parche de la cache de cada rama" '[ "$apache" = 2.4.62 ] && [ "$mariadb" = 11.4.5 ] && [ "$ftp" = 1.3.9a ] && [ "$apr" = 1.7.5 ] && [ "$aprutil" = 1.6.3 ]'
check "MariaDB con la suma guardada (y sin url: sale de la cache)" '[ "$mariadb_info" = "11.4.5||$(sum_of mariadb-11.4.5-fuente.tar.gz)|" ]'
check "la suma de PHP, de la cache" '[ "$php_sha" = "$(sum_of php-8.4.28.tar.xz)" ]'
check "lo que si se ha consultado no se cambia" '[ "$perl" = 5.40.3 ] && grep -q "Aviso: no se ha podido consultar el ultimo parche de Apache 2.4" "$W/salida"'
branches=(2.4 10.11 1.3.8 5.38) apache="" mariadb="" ftp="" perl=""
stack_cache_fallback binario > /dev/null
check "de otra rama no se coge nada" '[ "$apache" = 2.4.62 ] && [ -z "$mariadb" ] && [ -z "$ftp" ] && [ -z "$perl" ]'

# Fuera de las pruebas solo vale una cache de root
TEST_DIR="" DL_CACHE_DIR=$W/descargas
check "una cache que no es de root no se usa" '! dl_cache_trusted && [ -z "$(dl_cache_sum php-8.4.28.tar.xz)" ]'
TEST_DIR=$W

downloads_command > "$W/salida"
check "lvm-instalador descargas: lo que hay y cuanto ocupa" 'grep -q "php-8.4.28.tar.xz" "$W/salida" && grep -q "fichero(s)" "$W/salida" && ! grep -q "\.sha256" "$W/salida"'
DRY=1 downloads_command vaciar > "$W/salida"
check "vaciar en simulacion no borra nada" '[ -f "$DL_CACHE_DIR/php-8.4.28.tar.xz" ] && grep -q simulacion "$W/salida"'
downloads_command vaciar > /dev/null
check "vaciar la deja vacia" '[ -z "$(ls -A "$DL_CACHE_DIR")" ]'
check "se guarda tambien al fallar, y MariaDB no se borra antes" 'grep -q "stack_cache_store -n" "$SRC" && ! grep -q "rm -f mariadb.tar.gz" "$SRC"'
exit $fail
