#!/bin/bash
# Pruebas de seguridad del Mac (1.39.2), sin root ni red: carpetas XAMPP-X.Y.Z en las comprobaciones,
# PHP2Shell (el .ini, PHP-FPM y htdocs sin CGI por SECURE_PY, el estado de cada version, el parche
# incrustado de 7.4/8.0/8.1 y su sha256, actualizar las que no lo tienen), la barrera entre webs (en
# un Apache temporal, si esta el de /opt/lampp-8.2.4), las firmas GPG de las descargas, el ayudante
# de PAM de MariaDB y pasar-version. Desde la 1.39.5, las firmas sin gnupg (SIG_VERIFY_PY, con claves
# y firmas de prueba hechas aqui con gpg) y las librerias de Homebrew (solo las que faltan, con un brew
# de mentira). Uso: mac-seguridad.sh <macos/lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-macseg.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
if ! grep -q '^function php2shell_state() {' "$SRC"; then
    echo "  ok    (este script del Mac aun no trae lo de PHP2Shell)"
    exit 0
fi
getvar() { ( eval "$(sed -n "/^$1='/,/^'\$/p" "$SRC")"; printf '%s.' "${!1}" ); }
SECURE_PY=$(getvar SECURE_PY); VH=$(getvar UNKNOWN_HOST_VHOST); SSL=$(getvar UNKNOWN_HOST_SSL)
INI=$(getvar PHP_SECURITY_INI); INI85=$(getvar PHP_SECURITY_INI_85); VCHECK=$(getvar VHOSTS_CHECK_PY)
SECURE_PY=${SECURE_PY%.} VH=${VH%.} SSL=${SSL%.} INI=${INI%.} INI85=${INI85%.} VCHECK=${VCHECK%.}
CONF=$(grep -m1 '^UNKNOWN_HOST_CONF=' "$SRC" | cut -d= -f2)

# --- XAMPP-8.4.27 (con el parche en el nombre) en las comprobaciones ---
# (desde la 1.39.3, en /Library/Nexum)
check "trusted_version_dir admite XAMPP-X.Y.Z" 'grep -A3 "^function trusted_version_dir" "$SRC" | grep -qF "^/Library/Nexum/XAMPP-[0-9]+\.[0-9]+(\.[0-9]+)?$"'
printf '<VirtualHost *:80>\n    ServerName a.local\n    ErrorLog "/Library/Nexum/XAMPP-8.4.27/xamppfiles/logs/a-error_log"\n    SSLEngine on\n    SSLCertificateFile "/Library/Nexum/XAMPP-8.4.27/xamppfiles/etc/ssl.crt/a.crt"\n</VirtualHost>\n' > "$W/vh-patch"
check "VHOSTS_CHECK_PY: registros y certificados de XAMPP-8.4.27" 'python3 -I -c "$VCHECK" "$W/vh-patch" > /dev/null'
printf '<VirtualHost *:80>\n    ErrorLog "/Library/Nexum/XAMPP-8.4.27.1/xamppfiles/logs/x"\n</VirtualHost>\n' > "$W/vh-mal"
check "VHOSTS_CHECK_PY: XAMPP-8.4.27.1 no" '! python3 -I -c "$VCHECK" "$W/vh-mal" > /dev/null'
check "ninguna comprobacion de carpetas se queda en XAMPP-X.Y" '! grep -nE "XAMPP-\[0-9\]\+\\\\\.\[0-9\]\+[/$]" "$SRC"'

# --- SECURE_PY: PHP2Shell en una pila propia ---
mk() {  # mk <carpeta> <php>
    mkdir -p "$1/etc/extra" "$1/php/etc/conf.d"
    printf 'Listen 127.0.0.1:80\n<Directory "/Applications/XAMPP/xamppfiles/htdocs">\n    Options Indexes FollowSymLinks ExecCGI Includes\n</Directory>\nAddHandler cgi-script .cgi .pl\nInclude %s\nInclude etc/extra/httpd-vhosts.conf\n' "$CONF" > "$1/etc/httpd.conf"
    : > "$1/etc/extra/httpd-vhosts.conf"
    echo "$2|2.4.69|11.8.9|1.3.9|5.42|5.2.3" > "$1/etc/pvm-stack"
    echo "$2" > "$1/etc/pvm-php"
    printf '[global]\npid = x\n[xampp]\nuser = yo\npm = ondemand\npm.max_children = 20\n' > "$1/php/etc/php-fpm.conf"
}
B=$W/pila85; mk "$B" 8.5.12; mkdir -p "$W/o1"
out=$(python3 -I -c "$SECURE_PY" "$B" "$W/o1" 1 "$CONF" "$VH" "$SSL" "$INI" "$INI85" 2>&1) || { echo "SECURE_PY falla: $out"; exit 1; }
f() { local dst; dst=$(awk -F'|' -v r="$1" '$1 == r {print $2}' <<< "$out"); [ -n "$dst" ] && cat "$dst"; }
Z=$(f php/etc/conf.d/zz-lvm-seguridad.ini); H=$(f etc/httpd.conf); FPM=$(f php/etc/php-fpm.conf)
check "PHP: zz-lvm-seguridad.ini con los limites contra PHP2Shell" 'grep -qx "session.upload_progress.enabled = Off" <<< "$Z" && grep -qx "max_input_nesting_level = 6" <<< "$Z" && grep -qx "post_max_size = 64M" <<< "$Z" && grep -qx "upload_max_filesize = 64M" <<< "$Z" && grep -qx "expose_php = Off" <<< "$Z"'
check "PHP 8.5: tambien fatal_error_backtraces = 0" 'grep -qx "fatal_error_backtraces = 0" <<< "$Z"'
check "PHP-FPM: pm.max_requests = 50" 'grep -qx "pm.max_requests = 50" <<< "$FPM" && grep -qx "pm = ondemand" <<< "$FPM"'
check "htdocs sin ExecCGI ni Includes, y sin el AddHandler de .cgi y .pl" 'grep -qx "    Options Indexes FollowSymLinks" <<< "$H" && grep -qx "# (lvm-instalador: sin CGI en htdocs) AddHandler cgi-script .cgi .pl" <<< "$H"'
U=$(f "$CONF")
check "Apache: LimitRequestBody de 64 MB y la barrera entre webs" 'grep -qx "LimitRequestBody 67108864" <<< "$U" && grep -q "^# lvm-barrera-web:" <<< "$U" && grep -q "Sec-Fetch-Site" <<< "$U"'
# Se aplica y, la segunda vez, ya no hay nada que cambiar
while IFS='|' read -r rel src _; do [ -n "$rel" ] && [[ "$rel" != */ ]] && mkdir -p "$(dirname "$B/$rel")" && cat "$src" > "$B/$rel"; done <<< "$out"
out2=$(python3 -I -c "$SECURE_PY" "$B" "$W/o1" 1 "$CONF" "$VH" "$SSL" "$INI" "$INI85" 2>&1)
check "asegurar dos veces: la segunda no cambia nada" '[ -z "$(grep -v "lvm-sin-ficheros" <<< "$out2")" ]'
B=$W/pila74; mk "$B" 7.4.33; mkdir -p "$W/o2"
out=$(python3 -I -c "$SECURE_PY" "$B" "$W/o2" 1 "$CONF" "$VH" "$SSL" "$INI" "$INI85" 2>&1)
check "PHP 7.4: sin fatal_error_backtraces" 'Z=$(f php/etc/conf.d/zz-lvm-seguridad.ini); grep -qx "expose_php = Off" <<< "$Z" && ! grep -q fatal_error_backtraces <<< "$Z"'
B=$W/oficial; mk "$B" 8.2.4; rm "$B/etc/pvm-stack"; mkdir -p "$W/o3"
out=$(python3 -I -c "$SECURE_PY" "$B" "$W/o3" 1 "$CONF" "$VH" "$SSL" "$INI" "$INI85" 2>&1)
check "XAMPP oficial (sin pvm-stack): su php.ini y su Apache no se tocan por PHP2Shell" '! grep -q "zz-lvm-seguridad\|php-fpm.conf" <<< "$out" && ! f etc/httpd.conf | grep -q "sin CGI"'
out=$(python3 -I -c "$SECURE_PY" "$W/pila85" "$W/o1" 1 "$CONF" "$VH" "$SSL" 2>&1)
check "SECURE_PY sin los .ini (como lo llamaban antes): sigue funcionando" '[ $? -eq 0 ]'
check "install_stack: la pila nueva ya sale asi" 'sed -n "/^function write_stack_files/,/^}/p" "$SRC" | grep -q "pm.max_requests = 50" && ! sed -n "/^function write_stack_files/,/^}/p" "$SRC" | grep -q "ExecCGI Includes\|^AddHandler cgi-script" && sed -n "/^function write_stack_files/,/^}/p" "$SRC" | grep -q "zz-lvm-seguridad.ini"'

# --- La barrera entre webs se puede apagar ---
extract "$SRC" web_barrier_on unknown_host_vhost || exit 1
UNKNOWN_HOST_VHOST=$VH TEST_DIR=$W WEB_BARRIER_OFF=$W/sin-barrera
check "barrera puesta: el bloque tal cual" '[ "$(unknown_host_vhost)" == "${VH%$'"'"'\n'"'"'}" ] && unknown_host_vhost | grep -q "^# lvm-barrera-web:"'
touch "$WEB_BARRIER_OFF"
check "barrera apagada: sin su bloque, con lo demas" '! unknown_host_vhost | grep -q "Sec-Fetch-Site: cross\|lvm-barrera-web" && unknown_host_vhost | grep -qx "LimitRequestBody 67108864" && unknown_host_vhost | grep -q "phpmyadmin"'
rm -f "$WEB_BARRIER_OFF"
check "barrera-web: en gui-datos (T|) y en la ayuda" 'grep -q "echo \"T|\$(web_barrier_on" "$SRC" && grep -q "lvm-instalador barrera-web \[si|no\]" "$SRC"'

if [ -x /opt/lampp-8.2.4/bin/httpd ] && [ -f /opt/lampp-8.2.4/etc/httpd.conf ]; then
    A=$W/apache; mkdir -p "$A"
    printf '%s' "$VH" | sed 's#<VirtualHost \*:80>#<VirtualHost *:28471 *:28472>#' > "$A/unk.conf"
    if python3 -I "$HERE/apache-temporal.py" /opt/lampp-8.2.4/etc/httpd.conf "$A" "$A/unk.conf" > /dev/null 2>&1; then
        if env LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/bin/httpd -f "$A/httpd.conf" -k start 2> "$A/arranque.txt"; then
            trap 'env LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/bin/httpd -f "$A/httpd.conf" -k stop 2> /dev/null; sleep 1; rm -rf "$W"' EXIT
            for i in $(seq 30); do curl -s -o /dev/null http://127.0.0.1:28471/ && break; sleep 0.2; done
            c() { curl -s -o /dev/null -w '%{http_code}' -H "Host: web.local" "$@" "http://127.0.0.1:28471/no-existe.php"; }
            check "barrera: POST con Origin de otra web a un proyecto (web.local): 403" '[ "$(c -X POST -H "Origin: https://evil.example" -d x=1)" = 403 ]'
            check "barrera: fetch o formulario cross-site sin Origin: 403" '[ "$(c -X POST -H "Sec-Fetch-Site: cross-site" -H "Sec-Fetch-Mode: no-cors" -d x=1)" = 403 ]'
            check "barrera: imagen o script desde otra web: 403" '[ "$(c -H "Sec-Fetch-Site: cross-site" -H "Sec-Fetch-Mode: no-cors" -H "Sec-Fetch-Dest: image")" = 403 ]'
            check "barrera: iframe desde otra web: 403" '[ "$(c -H "Sec-Fetch-Site: cross-site" -H "Sec-Fetch-Mode: navigate" -H "Sec-Fetch-Dest: iframe")" = 403 ]'
            check "barrera: enlace desde otra web (abrir la pagina): pasa" '[ "$(c -H "Sec-Fetch-Site: cross-site" -H "Sec-Fetch-Mode: navigate" -H "Sec-Fetch-Dest: document")" = 404 ]'
            check "barrera: POST del propio proyecto (mismo Origin): pasa" '[ "$(c -X POST -H "Origin: http://web.local" -H "Sec-Fetch-Site: same-origin" -d x=1)" = 404 ]'
            check "barrera: escribiendo la direccion o sin navegador: pasa" '[ "$(c -H "Sec-Fetch-Site: none")" = 404 ] && [ "$(c -X POST -d x=1)" = 404 ]'
            check "barrera: POST cross-site con Mode navigate (formulario de otra web): 403" '[ "$(c -X POST -H "Sec-Fetch-Site: cross-site" -H "Sec-Fetch-Mode: navigate" -H "Sec-Fetch-Dest: document" -d x=1)" = 403 ]'
        else
            echo "  ok    (no arranca el Apache de prueba: $(head -c 200 "$A/arranque.txt"))"
        fi
    fi
else
    echo "  ok    (sin /opt/lampp-8.2.4: la barrera no se prueba en un Apache)"
fi

# --- Estado de cada version frente a PHP2Shell ---
extract "$SRC" php2shell_backport php2shell_state php2shell_diff php2shell_missing vsort sha256_of || exit 1
eval "$(sed -n '/^PHP2SHELL_MARK=/p; /^PHP2SHELL_DATE=/p; /^PHP2SHELL_FIXED=/p; /^PHP2SHELL_BACKPORTS=(/,/^)/p' "$SRC")"
eval "$(sed -n "/^PHP2SHELL_XZ_74='/,/^'\$/p; /^PHP2SHELL_XZ_80='/,/^'\$/p; /^PHP2SHELL_XZ_81='/,/^'\$/p" "$SRC")"
sha256_of() { sha256sum "$1" | cut -d' ' -f1; }
check "8.4.26 vulnerable (actualizable); 8.4.27 y 8.5.12 corregidas" '[ "$(php2shell_state 8.4.26)" == actualizable ] && [ "$(php2shell_state 8.4.27)" == ok ] && [ "$(php2shell_state 8.5.12)" == ok ] && [ "$(php2shell_state 8.5.13)" == ok ]'
check "8.2.34 y 8.3.35 vulnerables; 8.2.35 y 8.3.36, no" '[ "$(php2shell_state 8.2.34)" == actualizable ] && [ "$(php2shell_state 8.3.35)" == actualizable ] && [ "$(php2shell_state 8.2.35)" == ok ] && [ "$(php2shell_state 8.3.36)" == ok ]'
mkdir -p "$W/XAMPP-7.4/xamppfiles/etc"
check "7.4.33 sin el parche: parcheable; con la marca: parche" '[ "$(php2shell_state 7.4.33 "$W/XAMPP-7.4")" == parcheable ] && touch "$W/XAMPP-7.4/$PHP2SHELL_MARK" && [ "$(php2shell_state 7.4.33 "$W/XAMPP-7.4")" == parche ]'
check "8.0.30 y 8.1.34 sin el parche: parcheable; 7.3 y 5.6: sin arreglo; 8.6: corregida" '[ "$(php2shell_state 8.0.30)" == parcheable ] && [ "$(php2shell_state 8.1.34)" == parcheable ] && [ "$(php2shell_state 7.3.33)" == sin-arreglo ] && [ "$(php2shell_state 5.6.40)" == sin-arreglo ] && [ "$(php2shell_state 8.6.0)" == ok ]'
check "falta el parche al rehacer: solo 7.4.33, 8.0.30 y 8.1.34 sin la marca" 'php2shell_missing "$W/otra" 8.1.34 && ! php2shell_missing "$W/XAMPP-7.4" 7.4.33 && ! php2shell_missing "$W/otra" 8.4.27'
for v in 7.4.33 8.0.30 8.1.34; do
    check "parche de $v: se descomprime y su sha256 es el del equipo de seguridad" 'php2shell_diff '"$v"' "$W/p-'"$v"'.diff" > /dev/null && grep -q "^+++ b/main/rfc1867.c" "$W/p-'"$v"'.diff" && grep -q "^+++ b/ext/session/session.c" "$W/p-'"$v"'.diff"'
done
check "parche cambiado: no se usa (sha256)" 'PHP2SHELL_BACKPORTS[0]="7.4|7.4.33|x|0000000000000000000000000000000000000000000000000000000000000000"; ! php2shell_diff 7.4.33 "$W/malo.diff" > /dev/null'
check "sin parche para 7.4.32 ni para 8.4: no hay diff" '! php2shell_diff 7.4.32 "$W/x.diff" 2> /dev/null && ! php2shell_diff 8.4.27 "$W/x.diff" 2> /dev/null'
check "los commits del equipo de seguridad de PHP" 'grep -q "7.4|7.4.33|712e60f9edfd03f0960fc4fc3c2c375f42b90aa2|d059c1b4" "$SRC" && grep -q "8.0|8.0.30|82f8f31b16a035c1b67cc253e79f7cc288f4cc20|4cda6e04" "$SRC" && grep -q "8.1|8.1.34|1d7dec178a094e6e75b229ce22754045f8c6070a|5bd88c38" "$SRC"'
check "install_stack: aplica el parche (en seco antes) y deja la marca; nunca una 7.4.34" 'sed -n "/^function install_stack/,/^}/p" "$SRC" | grep -q "php2shell_diff \"\$version\"" && sed -n "/^function install_stack/,/^}/p" "$SRC" | grep -q "patch -p1 -s -f --dry-run" && grep -q "lvm-parche-php2shell\"$" "$SRC" && ! grep -q "PHP 7\.4\.34\|7\.4\.34|" "$SRC"'
P=$(dirname "$SRC")/../pruebas/datos/php-7.4.33.tar.xz
if [ -f "$P" ]; then
    mkdir -p "$W/src" && tar -xJf "$P" -C "$W/src"
    check "el parche de 7.4.33 encaja en el codigo de php.net" '(cd "$W/src/php-7.4.33" && patch -p1 -s -f --dry-run < "$W/p-7.4.33.diff")'
fi

# --- gui-al-dia y actualizar en las versiones sin el parche ---
extract "$SRC" gui_up_to_date stack_fields rebuild_version || exit 1
BASE_DIR=$W; mkdir -p "$W/XAMPP-8.1.34/xamppfiles/etc"
check "XAMPP-8.1.34 sin el parche: hay que actualizarla (no|8.1.34)" '[ "$(gui_up_to_date 8.1.34)" == "no|8.1.34" ]'
touch "$W/XAMPP-8.1.34/$PHP2SHELL_MARK"
check "XAMPP-8.1.34 con el parche: al dia" '[ "$(gui_up_to_date 8.1.34)" == "si|8.1.34" ]'
echo "7.4.33|2.4.69|10.11.19|1.3.9|5.40.3|5.2.3" > "$W/XAMPP-7.4/xamppfiles/etc/pvm-stack"
rm -f "$W/XAMPP-7.4/$PHP2SHELL_MARK"
php_releases() { echo "7.4 7.4.33 x 2022-11-03 -"; }
stack_versions() { echo "7.4.33|2.4.69|10.11.19|1.3.9|5.40.3|5.2.3"; }
check "XAMPP-7.4 con todo al dia pero sin el parche: hay que actualizarla" '[ "$(gui_up_to_date 7.4)" == "no|7.4.33" ]'
touch "$W/XAMPP-7.4/$PHP2SHELL_MARK"
check "XAMPP-7.4 con el parche: al dia" '[ "$(gui_up_to_date 7.4)" == "si|7.4.33" ]'
check "actualizar XAMPP-7.4.33 la rehace en su carpeta (parchear, reemplazar=2)" 'grep -q "install_plan \"parchear:\$version\"" "$SRC" && grep -q "parchear) ( install_stack \"\${1#\*:}\" 2 ) ;;" "$SRC"'
check "gui-datos: X|carpeta|estado de cada version" 'grep -q "echo \"X|\$name|\$(php2shell_state" "$SRC"'

# --- Firmas GPG de lo que se descarga ---
extract "$SRC" gpg_verify || exit 1
eval "$(sed -n '/^GPG_FPRS_[A-Z]*=/p' "$SRC")"
eval "$(sed -n "/^GPG_KEYS_PHP='/,/^'\$/p; /^GPG_KEYS_APACHE='/,/^'\$/p; /^GPG_KEYS_MARIADB='/,/^'\$/p; /^GPG_KEYS_PMA='/,/^'\$/p" "$SRC")"
for k in PHP APACHE MARIADB PMA; do
    v=GPG_KEYS_$k fv=GPG_FPRS_$k
    tr -d ' \n' <<< "${!v}" | base64 -d > "$W/$k.gpg" 2> /dev/null
    have=$(gpg --show-keys --with-colons "$W/$k.gpg" 2> /dev/null | awk -F: '$1 == "pub" { p = 1; next } $1 == "fpr" && p { print $10; p = 0 }' | sort | tr '\n' ' ')
    want=$(tr ' ' '\n' <<< "${!fv}" | grep . | sort | tr '\n' ' ')
    check "claves de $k: las de sus huellas, ni una mas" '[ -n "$have" ] && [ "$have" == "$want" ]'
done
mkdir -m 700 "$W/g1" "$W/g2"
gpg --homedir "$W/g1" --batch --passphrase '' --quick-generate-key "Prueba <p@prueba.local>" ed25519 sign 0 2> /dev/null
gpg --homedir "$W/g2" --batch --passphrase '' --quick-generate-key "Otra <o@prueba.local>" ed25519 sign 0 2> /dev/null
GPG_FPRS_TEST=$(gpg --homedir "$W/g1" --with-colons --list-keys 2> /dev/null | awk -F: '/^fpr/ { print $10; exit }')
GPG_KEYS_TEST=$(gpg --homedir "$W/g1" --export 2> /dev/null | base64 -w 76)
# (desde la 1.39.5, sin gnupg: SIG_VERIFY_PY)
eval "$(sed -n "/^SIG_VERIFY_PY='/,/^'\$/p" "$SRC")"
echo "paquete" > "$W/paq.tar.xz"
gpg --homedir "$W/g1" --batch --yes --detach-sign --armor -o "$W/paq.asc" "$W/paq.tar.xz" 2> /dev/null
gpg --homedir "$W/g2" --batch --yes --detach-sign --armor -o "$W/otra.asc" "$W/paq.tar.xz" 2> /dev/null
check "firma buena de una de sus claves: vale" 'gpg_verify "$W/paq.tar.xz" "$W/paq.asc" TEST > /dev/null'
check "firma de otra clave: no vale" '! gpg_verify "$W/paq.tar.xz" "$W/otra.asc" TEST > /dev/null'
echo "cambiado" >> "$W/paq.tar.xz"
check "paquete cambiado: no vale" '! gpg_verify "$W/paq.tar.xz" "$W/paq.asc" TEST > /dev/null'
check "sin el comprobador: no se instala (falla cerrado)" '! SIG_VERIFY_PY="" gpg_verify "$W/paq.tar.xz" "$W/paq.asc" TEST > /dev/null'
check "PHP, Apache/APR, MariaDB y phpMyAdmin se descargan con su firma" 'grep -q "php-\$version.tar.xz.asc\" PHP" "$SRC" && grep -q "\"\$base/\$1.asc\" APACHE" "$SRC" && grep -q "/signature/\" MARIADB" "$SRC" && [ "$(grep -c "all-languages.tar.xz.asc\" PMA" "$SRC")" == 2 ]'
check "xz entre las librerias de Homebrew de la compilacion, y ya no gnupg" '! grep "^STACK_BUILD_DEPS=" "$SRC" | grep -qw gnupg && grep "^STACK_BUILD_DEPS=" "$SRC" | grep -qw xz'

# --- SIG_VERIFY_PY (1.39.5): las firmas sin gnupg, con claves y firmas de prueba hechas aqui con gpg ---
check "SIG_VERIFY_PY: sin gpgv ni gnupg en el script" '[ -n "$SIG_VERIFY_PY" ] && ! grep -q "GPGV\|install_gpgv\|brew install --quiet gnupg\|Falta gnupg" "$SRC"'
check "SIG_VERIFY_PY: con el Python del sistema y aislado" 'grep -A8 "^function gpg_verify" "$SRC" | grep -qF "/usr/bin/python3 -I -c \"\$SIG_VERIFY_PY\""'
sv() {  # sv <home de gpg> <fichero> <firma> [huellas]: lo que dice SIG_VERIFY_PY con las claves de ese home
    gpg --homedir "$1" --export 2> /dev/null | base64 -w 76 \
        | python3 -I -c "$SIG_VERIFY_PY" "$2" "$3" "${4:-$(gpg --homedir "$1" --with-colons --list-keys 2> /dev/null | awk -F: '/^fpr/ { print $10; exit }')}" 2> /dev/null
}
fpr_of() { gpg --homedir "$1" --with-colons --list-keys 2> /dev/null | awk -F: '/^fpr/ { print $10; exit }'; }
mkdir -m 700 "$W/rsa" "$W/sub" "$W/rev"
gpg --homedir "$W/rsa" --batch --passphrase '' --quick-generate-key "RSA <r@prueba.local>" rsa2048 sign 0 2> /dev/null
# (como la de PHP 8.3 o la de phpMyAdmin: firma una subclave; la principal solo certifica)
gpg --homedir "$W/sub" --batch --passphrase '' --quick-generate-key "Sub <s@prueba.local>" ed25519 cert 0 2> /dev/null
gpg --homedir "$W/sub" --batch --passphrase '' --quick-add-key "$(fpr_of "$W/sub")" rsa2048 sign 0 2> /dev/null
gpg --homedir "$W/rev" --batch --passphrase '' --quick-generate-key "Rev <v@prueba.local>" rsa2048 sign 0 2> /dev/null
printf 'contenido de prueba\n%.0s' $(seq 1 500) > "$W/f.tar"
gpg --homedir "$W/g1" --batch --yes --detach-sign -o "$W/ed.sig" "$W/f.tar" 2> /dev/null
gpg --homedir "$W/rsa" --batch --yes --armor --digest-algo SHA512 --detach-sign -o "$W/rsa.asc" "$W/f.tar" 2> /dev/null
gpg --homedir "$W/rsa" --batch --yes --digest-algo SHA256 --detach-sign -o "$W/rsa256.sig" "$W/f.tar" 2> /dev/null
gpg --homedir "$W/rsa" --batch --yes --digest-algo SHA384 --detach-sign -o "$W/rsa384.sig" "$W/f.tar" 2> /dev/null
gpg --homedir "$W/rsa" --batch --yes --digest-algo SHA224 --detach-sign -o "$W/rsa224.sig" "$W/f.tar" 2> /dev/null
gpg --homedir "$W/rsa" --batch --yes --allow-weak-digest-algos --digest-algo SHA1 --detach-sign -o "$W/rsa1.sig" "$W/f.tar" 2> /dev/null
gpg --homedir "$W/sub" --batch --yes --armor --detach-sign -o "$W/sub.asc" "$W/f.tar" 2> /dev/null
gpg --homedir "$W/rev" --batch --yes --detach-sign -o "$W/rev.sig" "$W/f.tar" 2> /dev/null
gpg --homedir "$W/g1" --batch --yes --clearsign -o "$W/clear.asc" "$W/f.tar" 2> /dev/null
check "SIG_VERIFY_PY: Ed25519 binaria" '[ "$(sv "$W/g1" "$W/f.tar" "$W/ed.sig")" == "FIRMA-BUENA $(fpr_of "$W/g1")" ]'
check "SIG_VERIFY_PY: Ed25519 en texto (.asc)" '[ "$(sv "$W/g1" "$W/paq.tar.xz" "$W/otra.asc" "$(fpr_of "$W/g2")" | grep -c FIRMA-BUENA)" == 0 ] && echo paquete > "$W/p2" && gpg --homedir "$W/g1" --batch --yes --armor --detach-sign -o "$W/p2.asc" "$W/p2" 2> /dev/null && sv "$W/g1" "$W/p2" "$W/p2.asc" | grep -q "^FIRMA-BUENA "'
check "SIG_VERIFY_PY: RSA en texto con SHA-512" '[ "$(sv "$W/rsa" "$W/f.tar" "$W/rsa.asc")" == "FIRMA-BUENA $(fpr_of "$W/rsa")" ]'
check "SIG_VERIFY_PY: RSA con SHA-256, SHA-384 y SHA-224" 'sv "$W/rsa" "$W/f.tar" "$W/rsa256.sig" | grep -q ^FIRMA-BUENA && sv "$W/rsa" "$W/f.tar" "$W/rsa384.sig" | grep -q ^FIRMA-BUENA && sv "$W/rsa" "$W/f.tar" "$W/rsa224.sig" | grep -q ^FIRMA-BUENA'
check "SIG_VERIFY_PY: con SHA-1, no" '[ -s "$W/rsa1.sig" ] && ! sv "$W/rsa" "$W/f.tar" "$W/rsa1.sig" | grep -q FIRMA-BUENA'
check "SIG_VERIFY_PY: de una subclave, con la huella de la principal" '[ "$(sv "$W/sub" "$W/f.tar" "$W/sub.asc")" == "FIRMA-BUENA $(fpr_of "$W/sub")" ]'
check "SIG_VERIFY_PY: la huella de la subclave no vale como la de la principal" '! sv "$W/sub" "$W/f.tar" "$W/sub.asc" "$(gpg --homedir "$W/sub" --with-colons --list-keys 2> /dev/null | awk -F: "/^fpr/ { n++ } /^fpr/ && n == 2 { print \$10 }")" | grep -q FIRMA-BUENA'
check "SIG_VERIFY_PY: de una clave que no es de las del proyecto, no" '! sv "$W/rsa" "$W/f.tar" "$W/ed.sig" | grep -q FIRMA-BUENA && ! sv "$W/g1" "$W/f.tar" "$W/ed.sig" "$(fpr_of "$W/rsa")" | grep -q FIRMA-BUENA'
check "SIG_VERIFY_PY: con la clave en el llavero pero sin su huella en la lista, no" '! { gpg --homedir "$W/g1" --export; gpg --homedir "$W/rsa" --export; } 2> /dev/null | base64 -w 76 | python3 -I -c "$SIG_VERIFY_PY" "$W/f.tar" "$W/ed.sig" "$(fpr_of "$W/rsa")" 2> /dev/null | grep -q FIRMA-BUENA'
check "SIG_VERIFY_PY: y con las dos claves y su huella, si" '{ gpg --homedir "$W/rsa" --export; gpg --homedir "$W/g1" --export; } 2> /dev/null | base64 -w 76 | python3 -I -c "$SIG_VERIFY_PY" "$W/f.tar" "$W/ed.sig" "$(fpr_of "$W/rsa") $(fpr_of "$W/g1")" 2> /dev/null | grep -qx "FIRMA-BUENA $(fpr_of "$W/g1")"'
cp "$W/f.tar" "$W/f2.tar"; printf x >> "$W/f2.tar"
check "SIG_VERIFY_PY: el fichero cambiado, no (RSA, Ed25519 y subclave)" '! sv "$W/rsa" "$W/f2.tar" "$W/rsa.asc" | grep -q FIRMA && ! sv "$W/g1" "$W/f2.tar" "$W/ed.sig" | grep -q FIRMA && ! sv "$W/sub" "$W/f2.tar" "$W/sub.asc" | grep -q FIRMA'
python3 -I -c 'import sys; d = bytearray(open(sys.argv[1], "rb").read()); d[-3] ^= 1; open(sys.argv[2], "wb").write(bytes(d))' "$W/rsa256.sig" "$W/mal.sig"
python3 -I -c 'import sys; d = bytearray(open(sys.argv[1], "rb").read()); d[-3] ^= 1; open(sys.argv[2], "wb").write(bytes(d))' "$W/ed.sig" "$W/maled.sig"
check "SIG_VERIFY_PY: la firma cambiada, no (RSA y Ed25519)" '! sv "$W/rsa" "$W/f.tar" "$W/mal.sig" | grep -q FIRMA && ! sv "$W/g1" "$W/f.tar" "$W/maled.sig" | grep -q FIRMA'
sed '3s/./X/5' "$W/rsa.asc" > "$W/crc.asc"
check "SIG_VERIFY_PY: la .asc estropeada (su CRC), no" '! cmp -s "$W/rsa.asc" "$W/crc.asc" && ! sv "$W/rsa" "$W/f.tar" "$W/crc.asc" | grep -q FIRMA'
check "SIG_VERIFY_PY: un mensaje firmado en claro, no (solo firmas sueltas)" '! sv "$W/g1" "$W/f.tar" "$W/clear.asc" | grep -q FIRMA'
check "SIG_VERIFY_PY: sin firma o sin claves, no" ': > "$W/vacia.sig" && ! sv "$W/g1" "$W/f.tar" "$W/vacia.sig" | grep -q FIRMA && ! python3 -I -c "$SIG_VERIFY_PY" "$W/f.tar" "$W/ed.sig" "$(fpr_of "$W/g1")" < /dev/null 2> /dev/null | grep -q FIRMA'
check "SIG_VERIFY_PY: de una clave aun sin revocar, si" 'sv "$W/rev" "$W/f.tar" "$W/rev.sig" | grep -q ^FIRMA-BUENA'
# (gpg deja hecho su certificado de revocacion, con «:» delante para que no se importe sin querer)
sed 's/^:-----BEGIN/-----BEGIN/' "$W/rev/openpgp-revocs.d/$(fpr_of "$W/rev").rev" > "$W/rev.rev" 2> /dev/null
gpg --homedir "$W/rev" --batch --import "$W/rev.rev" 2> /dev/null
check "SIG_VERIFY_PY: de una clave revocada, no" 'gpg --homedir "$W/rev" --list-keys 2> /dev/null | grep -q "revoc\|revok" && ! sv "$W/rev" "$W/f.tar" "$W/rev.sig" | grep -q FIRMA'
# gpg_verify: solo con FIRMA-BUENA y una huella de la lista (no basta con que Python termine bien)
GPG_FPRS_FALSA=$GPG_FPRS_TEST GPG_KEYS_FALSA=$GPG_KEYS_TEST
check "gpg_verify: si Python termina bien sin decir nada, no" '! SIG_VERIFY_PY="pass" gpg_verify "$W/f.tar" "$W/ed.sig" FALSA > /dev/null'
check "gpg_verify: FIRMA-BUENA de otra huella, no" '! SIG_VERIFY_PY="print(\"FIRMA-BUENA 0000000000000000000000000000000000000000\")" gpg_verify "$W/f.tar" "$W/ed.sig" FALSA > /dev/null'
check "gpg_verify: FIRMA-BUENA y despues algo mas, no" '! SIG_VERIFY_PY="print(\"FIRMA-BUENA $GPG_FPRS_TEST\"); print(1)" gpg_verify "$W/f.tar" "$W/ed.sig" FALSA > /dev/null'
check "gpg_verify: FIRMA-BUENA pero Python falla, no" '! SIG_VERIFY_PY="print(\"FIRMA-BUENA $GPG_FPRS_TEST\"); raise SystemExit(1)" gpg_verify "$W/f.tar" "$W/ed.sig" FALSA > /dev/null'
check "gpg_verify: la buena, si, y dice la clave" 'SIG_VERIFY_PY="print(\"FIRMA-BUENA $GPG_FPRS_TEST\")" gpg_verify "$W/f.tar" "$W/ed.sig" FALSA | grep -q "comprobada (clave ${GPG_FPRS_TEST: -16})"'
check "gpg_verify: al fallar, dice por que" 'gpg_verify "$W/f2.tar" "$W/ed.sig" TEST | grep -q "no es buena o no es de quien lo publica (la firma no es buena o el fichero no es el firmado)"'
check "preparar-firma: ya no instala nada" 'grep -q "preparar-firma) echo \"Ya no hace falta gnupg" "$SRC"'

# --- brew_build_deps (1.39.5): solo lo que falta, sin actualizar lo instalado, sin los avisos de brew ---
extract "$SRC" brew_quiet brew_filter brew_build_deps || exit 1
mkdir -p "$W/bin"
cat > "$W/bin/brew" << 'EOF'
#!/bin/bash
# brew de mentira: apunta lo que se le pide (con las variables de Homebrew) en $BREW_LOG
echo "$* | $(env | grep '^HOMEBREW_' | sort | tr '\n' ' ')" >> "$BREW_LOG"
case "$1" in
    list)
        if [ "$2" == --formula ]; then printf '%s\n' $BREW_HAVE; exit 0; fi
        # list --versions <f>: con otro nombre (icu4c es icu4c@77)
        [ "$3" == icu4c ] && [[ " $BREW_HAVE " == *" icu4c@77 "* ]] && { echo "icu4c@77 77.1"; exit 0; }
        exit 1 ;;
    outdated) [ -n "$BREW_OLD" ] && echo "$BREW_OLD"; exit 0 ;;
    install|upgrade)
        echo "==> Pouring algo (a stdout)"
        cat "$BREW_NOISE" >&2
        exit "${BREW_RC:-0}" ;;
esac
EOF
chmod +x "$W/bin/brew"
cat > "$W/ruido" << 'EOF'
Running `brew update --auto-update`...
==> Auto-updated Homebrew!
Updated 2 taps (homebrew/core and homebrew/cask).
==> New Formulae
foo
bar

You have 7 outdated formulae installed.
Warning: A newer Command Line Tools release is available.
Update them from Software Update in System Settings.

If that doesn't show you any updates, run:
  sudo rm -rf /Library/Developer/CommandLineTools
  sudo xcode-select --install

Alternatively, manually download them from:
  https://developer.apple.com/download/all/.
You should download the Command Line Tools for Xcode 16.2.

Warning: You are using macOS 14.
We (and Apple) do not provide support for this old version.

Warning: Cannot verify integrity of 'abc.json'
Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`).
Warning: A newer Command Line Tools release is available.
Update them from Software Update in System Settings.
You should download the Command Line Tools for Xcode 16.2.
Warning: libzip 1.11 no se ha podido enlazar
Error: libzip: failed to build
EOF
all=$(grep -m1 "^STACK_BUILD_DEPS=" "$SRC" | cut -d'"' -f2) STACK_BUILD_DEPS=$all
export BREW_LOG=$W/brew.log BREW_NOISE=$W/ruido
bb() { PATH=$W/bin:$PATH BREW_HAVE=$1 BREW_OLD=$2 BREW_RC=${3:-0} brew_build_deps 2>&1; }
: > "$BREW_LOG"; out=$(bb "${all/icu4c/icu4c@77}" "")
check "brew: con todo instalado, ni brew install ni brew upgrade" 'grep -q "Ya estan todas" <<< "$out" && ! grep -q "^install\|^upgrade" "$BREW_LOG" && [ "$(grep -c "^list --formula" "$BREW_LOG")" == 1 ]'
check "brew: con otro nombre (icu4c@77), se pregunta solo por ese" '[ "$(grep -c "^list --versions" "$BREW_LOG")" == 1 ] && grep -q "^list --versions icu4c " "$BREW_LOG"'
: > "$BREW_LOG"; out=$(bb "$(sed "s/\blibzip\b//; s/\bwebp\b//" <<< "$all")" ""); rc=$?
check "brew: solo instala las que faltan" 'grep -q "^install --quiet libzip webp |" "$BREW_LOG" && [ "$(grep -c "^install" "$BREW_LOG")" == 1 ] && ! grep -q "^upgrade" "$BREW_LOG"'
check "brew: sin actualizar lo instalado, sin pistas ni limpiar" 'l=$(grep "^install" "$BREW_LOG") && ( for v in NO_INSTALL_UPGRADE NO_ENV_HINTS NO_INSTALL_CLEANUP NO_INSTALLED_DEPENDENTS_CHECK; do grep -q "HOMEBREW_$v=1" <<< "$l" || exit 1; done )'
check "brew: antes dice que instala y que puede tardar" 'grep -q "Se instalan con Homebrew: libzip webp" <<< "$out" && grep -q "se compilan desde el codigo fuente: puede tardar" <<< "$out"'
check "brew: sin los avisos de brew" '! grep -q "Command Line Tools\|Update them\|xcode-select\|developer.apple.com\|outdated formulae\|New Formulae\|^foo\|Auto-updated\|Updated 2 taps\|auto-update\|HOMEBREW_NO_ENV_HINTS\|Cannot verify integrity\|You are using macOS\|old version\|Pouring" <<< "$out"'
check "brew: los errores y otros avisos si" 'grep -q "^Error: libzip: failed to build" <<< "$out" && grep -q "^Warning: libzip 1.11 no se ha podido enlazar" <<< "$out"'
: > "$BREW_LOG"; out=$(bb "$all" "openssl@3")
check "brew: openssl@3 con una nueva, solo brew upgrade openssl@3" 'grep -q "^upgrade --quiet openssl@3 |" "$BREW_LOG" && ! grep -q "^install" "$BREW_LOG" && grep -q "Se actualiza openssl@3" <<< "$out"'
out=$(bb "$(sed "s/\blibzip\b//" <<< "$all")" "" 1); rc=$?
check "brew: si falla, lo dice y devuelve error" '[ $rc -ne 0 ] && grep -q "No se han podido instalar con Homebrew: libzip" <<< "$out"'
check "install_stack: las librerias con brew_build_deps (ya no brew install de todas)" 'sed -n "/^function install_stack/,/^}/p" "$SRC" | grep -q "brew_build_deps || exit 1" && ! grep -q "brew install --quiet \$STACK_BUILD_DEPS" "$SRC"'

# --- MariaDB: el ayudante de PAM no llega a la version ---
check "PAM: se quita del arbol de la compilacion antes de copiarlo como root" 'sed -n "/^function install_stack/,/^}/p" "$SRC" | awk "/auth_pam_tool_dir/ { a = NR } /mkdir \"\\\$root\" && \\\$SUDO cp -R/ { b = NR } END { exit !(a && b && a < b) }"'
check "PAM: y antes de mariadb-install-db" 'sed -n "/^function init_stack_databases/,/^}/p" "$SRC" | awk "/rm -rf .*auth_pam_tool_dir/ && !a { a = NR } /scripts\/mariadb-install-db/ && !b { b = NR } END { exit !(a && b && a < b) }"'

# --- pasar-version: las BBDD con sus vinculos ---
extract "$SRC" move_to_version valid_version_name linked_folder || exit 1
BASE_DIR=$W DRY=0 PROJECTS_FILE=$W/proyectos
mkdir -p "$W/XAMPP-8.4.26/xamppfiles/etc" "$W/XAMPP-8.4.27/xamppfiles/etc"
touch "$W/XAMPP-8.4.26/xamppfiles/etc/pvm-stack" "$W/XAMPP-8.4.27/xamppfiles/etc/pvm-stack"
printf 'wp_a@8.4.26=tienda-a\nwp_b=web-b\n' > "$PROJECTS_FILE"
db_names() { case "$1" in *8.4.26) printf 'wp_a\nwp_b\nya\n' ;; *) printf 'ya\n' ;; esac; }
copy_database() { echo "COPIA $*" >> "$W/copias"; }
active_dir() { echo "$W/XAMPP-8.4.26"; }
realpath_f() { readlink -f "$1"; }
use_version() { echo "USE $1" >> "$W/copias"; }
move_to_version 8.4.26 8.4.27 > /dev/null
check "pasar-version: cada BBDD con su carpeta, las que ya tiene no, y activa la nueva" 'grep -qx "COPIA wp_a 8.4.26 8.4.27 --carpeta tienda-a" "$W/copias" && grep -qx "COPIA wp_b 8.4.26 8.4.27 --carpeta web-b" "$W/copias" && ! grep -q "COPIA ya" "$W/copias" && grep -qx "USE 8.4.27" "$W/copias"'
check "pasar-version: versiones raras, no" '! move_to_version 8.4.26 "../x" > /dev/null 2>&1 && ! move_to_version 8.4.26 8.4.26 > /dev/null 2>&1'
exit $fail
