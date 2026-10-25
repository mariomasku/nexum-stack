#!/bin/bash
# Pruebas de las reglas web en un Apache temporal (puertos 28471 y 28472, solo 127.0.0.1). Pide
# ficheros que no existen en la raiz de htdocs (que si existe: Apache aplica FilesMatch al nombre):
# 403 = regla aplicada, 404 = se habria servido. Uso: web.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-web.XXXX")
getvar() { ( eval "$(sed -n "/^$1='/,/^'\$/p" "$SRC")"; printf '%s.' "${!1}" ); }
VH=$(getvar UNKNOWN_HOST_VHOST); VH=${VH%.}
printf '%s' "$VH" | sed 's#<VirtualHost \*:80>#<VirtualHost *:28471 *:28472>#' > "$W/unk.conf"
# httpd.conf de la 8.2.4 (solo se lee) con los puertos, registros, htdocs, vhosts y phpMyAdmin de prueba
python3 -I "$HERE/apache-temporal.py" /opt/lampp-8.2.4/etc/httpd.conf "$W" "$W/unk.conf" \
    || { echo "no se ha podido preparar el Apache"; rm -rf "$W"; exit 1; }
grep -q "Include $W/unk.conf" "$W/httpd.conf" || { echo "no se ha podido preparar el Apache"; rm -rf "$W"; exit 1; }
env LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib PHPRC=/opt/lampp-8.2.4/etc /opt/lampp-8.2.4/bin/httpd -f "$W/httpd.conf" -k start 2> "$W/arranque.txt" || { cat "$W/arranque.txt"; rm -rf "$W"; exit 1; }
trap 'env LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib PHPRC=/opt/lampp-8.2.4/etc /opt/lampp-8.2.4/bin/httpd -f "$W/httpd.conf" -k stop 2> /dev/null; sleep 1; [ -n "$KEEP" ] && cp -r "$W/logs" "${KEEP_DIR:-$HOME}/ultimo-web-logs"; rm -rf "$W"' EXIT
for i in $(seq 30); do curl -s -o /dev/null http://127.0.0.1:28471/ && break; sleep 0.2; done
code() { curl -s -o /dev/null -w '%{http_code}' -H "Host: ${2:-localhost}" "http://127.0.0.1:${3:-28471}$1"; }
for f in /.env /.ENV /.env.local /.git /copia.sql /copia.SQL.gz /b.sql.xz /d.dump /w.php.old \
         /w.php.orig /w.php~ /w.php.save /error_log /auth.json /.npmrc /debug.log /.htpasswd; do
    check "403 en $f" '[ "$(code "$f")" = 403 ]'
done
check "un fichero normal inexistente da 404" '[ "$(code /index-no-existe.php)" = 404 ]'
check "un .zip no se bloquea (descargas de las webs)" '[ "$(code /plugin.zip)" = 404 ]'
check "dominio desconocido en 28472 (otro puerto): 403" '[ "$(code / evil.com 28472)" = 403 ]'
check "localhost en 28472: pasa" '[ "$(code /no-existe localhost 28472)" = 404 ]'
check "TRACE desactivado" '[ "$(curl -s -o /dev/null -w "%{http_code}" -X TRACE http://127.0.0.1:28471/)" = 405 ]'
# Otra web que manda un formulario o un fetch a phpMyAdmin (CSRF): el navegador pone Host 127.0.0.1
pm() { curl -s -o /dev/null -w '%{http_code}' -H "Host: 127.0.0.1:28471" "$@"; }
U=http://127.0.0.1:28471
check "CSRF: POST desde otra web (Origin) a phpMyAdmin: 403" '[ "$(pm -X POST -H "Origin: https://evil.example" -d sql_query=x "$U/phpmyadmin/no-existe.php?route=/sql")" = 403 ]'
check "CSRF: POST con Sec-Fetch-Site cross-site sin Origin: 403" '[ "$(pm -X POST -H "Sec-Fetch-Site: cross-site" -d x=1 "$U/phpmyadmin/no-existe.php")" = 403 ]'
check "CSRF: POST same-site (otro puerto de 127.0.0.1): 403" '[ "$(pm -X POST -H "Sec-Fetch-Site: same-site" -H "Origin: http://127.0.0.1:9999" -d x=1 "$U/phpmyadmin/no-existe.php")" = 403 ]'
check "CSRF: Origin null (iframe sandbox): 403" '[ "$(pm -X POST -H "Origin: null" -d x=1 "$U/phpmyadmin/no-existe.php")" = 403 ]'
check "CSRF: GET desde otra web con consulta: 403" '[ "$(pm -H "Sec-Fetch-Site: cross-site" "$U/phpmyadmin/no-existe.php?route=/sql&sql_query=x")" = 403 ]'
check "CSRF: imagen desde otra web a una ruta interna: 403" '[ "$(pm -H "Sec-Fetch-Site: cross-site" "$U/phpmyadmin/js/x.js")" = 403 ]'
# (la portada existe en el Apache de prueba, que sirve el phpMyAdmin de la version: solo un GET)
check "enlace desde otra web a la portada: pasa" '[ "$(pm -H "Sec-Fetch-Site: cross-site" "$U/phpmyadmin/")" != 403 ]'
check "POST del propio phpMyAdmin (Origin 127.0.0.1): pasa" '[ "$(pm -X POST -H "Origin: http://127.0.0.1:28471" -H "Sec-Fetch-Site: same-origin" -d x=1 "$U/phpmyadmin/no-existe.php")" = 404 ]'
check "POST del propio phpMyAdmin en [::1]: pasa" '[ "$(curl -s -o /dev/null -w "%{http_code}" -H "Host: [::1]:28471" -X POST -H "Origin: http://[::1]:28471" -d x=1 "$U/phpmyadmin/no-existe.php")" = 404 ]'
check "escribiendo la direccion (Sec-Fetch-Site none) con consulta: pasa" '[ "$(pm -H "Sec-Fetch-Site: none" "$U/phpmyadmin/no-existe.php?route=/sql")" = 404 ]'
check "navegador sin Sec-Fetch (antiguo), GET normal: pasa" '[ "$(pm "$U/phpmyadmin/no-existe.php?route=/")" = 404 ]'
check "Origin con 127.0.0.1 de prefijo (127.0.0.1.evil.com): 403" '[ "$(pm -X POST -H "Origin: http://127.0.0.1.evil.com" -d x=1 "$U/phpmyadmin/no-existe.php")" = 403 ]'
check "CSRF: POST desde otro servidor de 127.0.0.1 (otro puerto) sin Sec-Fetch: 403" '[ "$(pm -X POST -H "Origin: http://127.0.0.1:3000" -d x=1 "$U/phpmyadmin/no-existe.php")" = 403 ]'
check "CSRF: Sec-Fetch-Site en mayusculas: 403" '[ "$(pm -X POST -H "Sec-Fetch-Site: CROSS-SITE" -d x=1 "$U/phpmyadmin/no-existe.php")" = 403 ]'
check "CSRF: [::1] con Origin de 127.0.0.1 (otro origen): 403" '[ "$(curl -s -o /dev/null -w "%{http_code}" -H "Host: [::1]:28471" -X POST -H "Origin: http://127.0.0.1:28471" -d x=1 "$U/phpmyadmin/no-existe.php")" = 403 ]'
check "config.inc.php de phpMyAdmin en 127.0.0.1: 403" '[ "$(curl -s -o /dev/null -w "%{http_code}" -H "Host: 127.0.0.1:28471" "$U/phpmyadmin/config.inc.php")" = 403 ]'
check "config.inc.php por localhost: no se sirve (a la portada)" '[ "$(curl -s -o /dev/null -w "%{http_code}" -H "Host: localhost" "$U/phpmyadmin/config.inc.php")" = 302 ]'
# phpMyAdmin por localhost (un marcador antiguo): a su portada en 127.0.0.1, sin lo de detras
loc() { curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -H "Host: $2" "$@" 2> /dev/null; }
r=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -H "Host: localhost" "$U/phpmyadmin/")
check "localhost/phpmyadmin/: 302 a http://127.0.0.1/phpmyadmin/" '[ "${r%\?}" = "302 http://127.0.0.1/phpmyadmin/" ]'
r=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -H "Host: localhost" -X POST -d sql_query=x "$U/phpmyadmin/index.php?route=/sql&sql_query=x")
check "localhost/phpmyadmin con consulta y POST: a la portada, sin la consulta" '[ "${r%\?}" = "302 http://127.0.0.1/phpmyadmin/" ]'
r=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: evil.example" "$U/phpmyadmin/")
check "dominio sin vhost (DNS rebinding) en /phpmyadmin: 403, sin redireccion" '[ "$r" = 403 ]'
r2=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: web.local" "$U/phpmyadmin/")
check "phpMyAdmin por web.local u otro dominio: 403 con el aviso" '[ "$r2" = 403 ]'
r=$(curl -s -o /dev/null -w '%{http_code}' -H "Host: 127.0.0.1:28471" "$U/phpmyadmin/no-existe.php")
check "en 127.0.0.1 phpMyAdmin no redirige" '[ "$r" = 404 ]'
# Ficheros de los proyectos que no se sirven (y los que si)
for f in /debug2.log /docker-compose.yml /config.yaml /wp-config.txt /wp-config.php.txt /wp-config /web_a1b2_20261020_archive.zip \
         /backup-2026.tar.gz /copia_web.zip /backup_x-db.gz /sitio.wpress /web_wpvivid-ab12_2026_backup_all.zip /bkp.tar /backup.zip /copia.tar.gz /localhost+2-key.pem /server.key /php.ini /.user.ini /nginx.conf /customers_export_ab12.csv /cert.p12 /datos.sqlite /id_rsa /id_ed25519.pub /.ssh/authorized_keys; do
    check "403 en $f" '[ "$(code "$f")" = 403 ]'
done
# (1.45.0 / Mac 1.33.0) Exportaciones de clientes de WP All Import y de PrestaShop en otros formatos,
# y claves de otros programas. La carpeta wpallimport tiene que existir: DirectoryMatch va por carpetas
mkdir -p "$W/htdocs/wp-content/uploads/wpallimport/files"
mkdir -p "$W/htdocs/wp-content/uploads/wpallexport/exports" "$W/htdocs/wp-content/uploads/sites/3/wpallimport"
for f in /customers_export_ab12.zip /Customers_Export_2025.xml /customers_export_x.xlsx /.my.cnf /.netrc /.pgpass \
         /credentials.json /credentials-prod.json /.aws/credentials /.docker/config.json \
         /wp-content/uploads/wpallimport/files/Customers_Export_2025_July.zip /wp-content/uploads/wpallimport/files/x.xml \
         /wp-content/uploads/wpallexport/exports/clientes.csv /wp-content/uploads/sites/3/wpallimport/x.zip \
         /service-account.json /gcloud-credentials.json /.s3cfg /.mysql_history /.bash_history; do
    check "403 en $f" '[ "$(code "$f")" = 403 ]'
done
for f in /wp-content/uploads/2025/10/foto.zip /customers.xml /mi-credentials.php; do
    check "pasa $f (404)" '[ "$(code "$f")" = 404 ]'
done
for f in /wp-config.php /wp-config-sample.php /plugin2.zip /datos.csv /phpinfo.php /tema.zip /woocommerce-product-archive.zip /db-tools.zip /mysqldump-helper.zip /mi-backupbuddy.zip; do
    check "pasa $f (404)" '[ "$(code "$f")" = 404 ]'
done
exit $fail
