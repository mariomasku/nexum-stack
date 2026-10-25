#!/bin/bash
# Pruebas de la 1.54.1 (PHP2Shell y repaso de seguridad), sin root ni red: mitigaciones del php.ini
# y sin CGI (SECURE_PY sobre arboles de prueba), estado de cada version, el arreglo de php-src de
# 7.4.33, 8.0.30 y 8.1.34, las firmas de las descargas (claves y huellas), la compilacion con el
# usuario nexum-build, actualizar-a y docker sin terminal. Uso: php2shell.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q '^function php2shell_state() {' "$SRC" || { echo "  ok    (sin PHP2Shell)"; exit 0; }
W=$(mktemp -d "$TMPBASE/w-p2s.XXXX"); trap 'rm -rf "$W"' EXIT
getvar() { ( eval "$(sed -n "/^$1='/,/^'\$/p" "$SRC")"; printf '%s.' "${!1}" ); }
SECURE_PY=$(getvar SECURE_PY); SECURE_PY=${SECURE_PY%.}
VH=$(getvar UNKNOWN_HOST_VHOST); VH=${VH%.}
SSL=$(getvar UNKNOWN_HOST_SSL); SSL=${SSL%.}
CONF=$(grep -m1 '^UNKNOWN_HOST_CONF=' "$SRC" | cut -d= -f2)
eval "$(sed -n '/^PHP_SECURE_INI=/,/^PHP_SECURE_INI_85=/p; /^PHP2SHELL_FIXED=/p; /^PHP2SHELL_MARK=/p; /^BUILD_USER=/p' "$SRC")"
eval "$(sed -n '/^PHP2SHELL_BACKPORTS=(/,/^)/p' "$SRC")"
for v in 7_4_33 8_0_30 8_1_34; do eval "$(sed -n "/^PHP2SHELL_DIFF_$v='/,/^'\$/p" "$SRC")"; done
eval "$(sed -n "/^GPG_KEYS_B64='/,/^'\$/p; /^GPG_FPR_APACHE=\"/,/\"\$/p; /^GPG_FPR_MARIADB=/p; /^GPG_FPR_PMA=\"/,/\"\$/p" "$SRC")"
eval "$(sed -n '/^XAMPP_CATALOG=(/,/^)/p' "$SRC")"
extract "$SRC" php_85_or_later php_secure_ini_file php2shell_backport php2shell_apply php2shell_state \
    is_fpm_install verify_sig php_gpg_fprs || exit 1
INI=${PHP_SECURE_INI//$'\n'/;}
secure() { LVM_PHP_INI=$INI LVM_PHP_INI_85=$PHP_SECURE_INI_85 python3 -I -c "$SECURE_PY" "$1" "$2" 0 "$CONF" "$VH" "$SSL"; }
# Aplica lo que dice SECURE_PY (como secure_lampp, sin root)
apply() { local rel dst; while IFS='|' read -r rel dst _; do [ -n "$dst" ] && cat "$dst" > "$1/$rel"; done <<< "$2"; }

# --- XAMPP: php.ini y httpd.conf ---
X=$W/xampp; mkdir -p "$X/etc/extra" "$W/o1"
cat > "$X/etc/httpd.conf" << 'C'
Listen 127.0.0.1:80
<Directory "/opt/lampp/htdocs">
    #   Indexes Includes FollowSymLinks SymLinksifOwnerMatch ExecCGI MultiViews
    Options Indexes FollowSymLinks ExecCGI Includes
    AllowOverride All
</Directory>
<Directory "/opt/lampp/cgi-bin">
    Options ExecCGI
</Directory>
<IfModule mime_module>
    AddHandler cgi-script .cgi .pl
</IfModule>
Include etc/extra/lvm-dominio-desconocido.conf
Include etc/extra/httpd-vhosts.conf
C
: > "$X/etc/extra/httpd-vhosts.conf"; printf '%s' "$VH" > "$X/$CONF"
printf '[PHP]\npost_max_size=40M\r\nupload_max_filesize = 40M\r\nexpose_php = On\r\n;session.upload_progress.enabled = On\r\n' > "$X/etc/php.ini"
out=$(secure "$X" "$W/o1")
check "XAMPP: cambia php.ini y httpd.conf" 'grep -q "^etc/php.ini|" <<< "$out" && grep -q "^etc/httpd.conf|.*sin CGI" <<< "$out"'
apply "$X" "$out"
CR=$'\r'
check "php.ini: valores cambiados donde estaban (con su \\r\\n)" 'grep -q "^post_max_size = 64M$CR\$" "$X/etc/php.ini" && grep -q "^expose_php = Off$CR\$" "$X/etc/php.ini"'
check "php.ini: los que faltaban, al final" 'grep -q "^session.upload_progress.enabled = Off" "$X/etc/php.ini" && grep -q "^max_input_nesting_level = 6" "$X/etc/php.ini" && grep -q "^;session.upload_progress.enabled = On" "$X/etc/php.ini"'
check "php.ini: XAMPP no es PHP 8.5: sin fatal_error_backtraces" '! grep -q fatal_error_backtraces "$X/etc/php.ini"'
check "htdocs sin ExecCGI ni Includes; cgi-bin igual; el comentario igual" 'grep -q "^    Options Indexes FollowSymLinks$" "$X/etc/httpd.conf" && grep -q "^    Options ExecCGI$" "$X/etc/httpd.conf" && grep -q "^    #   Indexes Includes" "$X/etc/httpd.conf"'
check "AddHandler cgi-script .cgi .pl comentado" 'grep -q "^    # (lvm-instalador: sin CGI en los proyectos) AddHandler cgi-script .cgi .pl$" "$X/etc/httpd.conf"'
out=$(secure "$X" "$W/o1")
check "XAMPP: otra pasada no cambia nada" '[ -z "$out" ]'
out=$(python3 -I -c "$SECURE_PY" "$X" "$W/o1" 0 "$CONF" "$VH" "$SSL")
check "sin LVM_PHP_INI (pruebas de antes): el php.ini no se mira" '! grep -q "php.ini" <<< "$out"'

# --- Pila propia (8.5): conf.d/99-lvm-seguridad.ini y PHP-FPM ---
P=$W/propia; mkdir -p "$P/etc/extra" "$P/php/etc/conf.d" "$W/o2"
printf 'Listen 127.0.0.1:80\n<Directory "/opt/lampp/htdocs">\n    Options Indexes FollowSymLinks\n</Directory>\nInclude %s\nInclude etc/extra/httpd-vhosts.conf\n' "$CONF" > "$P/etc/httpd.conf"
: > "$P/etc/extra/httpd-vhosts.conf"; printf '%s' "$VH" > "$P/$CONF"
echo 8.5.12 > "$P/etc/lvm-php"; echo "8.5.12|2.4.69|12.3.3|1.3.9|5.44.1|5.2.3" > "$P/etc/lvm-stack"
printf '[lampp]\npm = ondemand\npm.max_children = 20\npm.process_idle_timeout = 60s\n' > "$P/php/etc/php-fpm.conf"
out=$(secure "$P" "$W/o2")
apply "$P" "$out"
check "pila propia: 99-lvm-seguridad.ini igual que el de una pila nueva" '[ "$(cat "$P/php/etc/conf.d/99-lvm-seguridad.ini")" == "$(php_secure_ini_file 8.5.12)" ]'
check "PHP 8.5: con fatal_error_backtraces = 0" 'grep -qx "fatal_error_backtraces = 0" "$P/php/etc/conf.d/99-lvm-seguridad.ini"'
check "PHP 8.4: sin fatal_error_backtraces" '! php_secure_ini_file 8.4.27 | grep -q fatal_error_backtraces && php_secure_ini_file 8.4.27 | grep -qx "max_input_nesting_level = 6"'
check "PHP-FPM: pm.max_requests = 50 detras de pm.max_children" 'grep -A1 "^pm.max_children" "$P/php/etc/php-fpm.conf" | grep -qx "pm.max_requests = 50"'
check "pila propia: otra pasada no cambia nada" '[ -z "$(secure "$P" "$W/o2")" ]'
check "pila nueva: 99-lampp.ini con 64M, sin ExecCGI ni .cgi .pl, FPM con pm.max_requests" \
    'grep -q "^upload_max_filesize = 64M" "$SRC" && ! grep -q "^    Options Indexes FollowSymLinks ExecCGI Includes" "$SRC" && ! grep -q "^AddHandler cgi-script .cgi .pl" "$SRC" && grep -q "^pm.max_requests = 50$" "$SRC"'

# --- Estado de PHP2Shell de cada version ---
mk() { mkdir -p "$W/v/$1/php/sbin"; }
mk own-8.4.27; mk own-8.4.26; mk own-7.4.33; mk own-7.4.33b; mk own-8.6.0; mk own-7.3.33; mkdir -p "$W/v/xampp"
mkdir -p "$W/v/own-7.4.33b/etc"; echo x > "$W/v/own-7.4.33b/$PHP2SHELL_MARK"
check "8.4.27: ok" '[ "$(php2shell_state "$W/v/own-8.4.27" 8.4.27)" == "ok|" ]'
check "8.4.26: vulnerable (el arreglo en 8.4.27)" '[[ "$(php2shell_state "$W/v/own-8.4.26" 8.4.26)" == vulnerable\|*8.4.27* ]]'
check "7.4.33 sin el parche: vulnerable" '[[ "$(php2shell_state "$W/v/own-7.4.33" 7.4.33)" == vulnerable\|* ]]'
check "7.4.33 con el parche: «+ parche de seguridad»" '[ "$(php2shell_state "$W/v/own-7.4.33b" 7.4.33)" == "parche|PHP 7.4.33 + parche de seguridad (oct 2026)" ]'
check "7.3: vulnerable, sin arreglo" '[[ "$(php2shell_state "$W/v/own-7.3.33" 7.3.33)" == vulnerable\|* ]]'
check "rama posterior (8.6): ok" '[ "$(php2shell_state "$W/v/own-8.6.0" 8.6.0)" == "ok|" ]'
check "XAMPP (aunque sea 8.2.35): vulnerable" '[[ "$(php2shell_state "$W/v/xampp" 8.2.35)" == vulnerable\|XAMPP* ]]'
check "arreglo en 8.2.35, 8.3.36, 8.4.27 y 8.5.12" '[ "$PHP2SHELL_FIXED" == "8.2.35 8.3.36 8.4.27 8.5.12" ]'
check "catalogo de XAMPP sin el 8.2.4" '! printf "%s\n" "${XAMPP_CATALOG[@]}" | grep -q "^8.2.4|" && [ ${#XAMPP_CATALOG[@]} -eq 3 ]'

# --- El arreglo de php-src (7.4.33, 8.0.30 y 8.1.34) ---
for v in 7.4.33 8.0.30 8.1.34; do
    var=PHP2SHELL_DIFF_${v//./_}; info=$(php2shell_backport "$v")
    check "$v: el diff incrustado coincide con su sha256" '[ "$(base64 -d <<< "${!var}" | xz -dc | sha256sum | cut -d" " -f1)" == "${info#*|}" ]'
    check "$v: es el diff de php-src (rfc1867.c, php_variables.c y session.c)" 'base64 -d <<< "${!var}" | xz -dc | grep -q "^diff --git a/main/rfc1867.c" && base64 -d <<< "${!var}" | xz -dc | grep -q "^diff --git a/ext/session/session.c"'
done
check "8.1.33 o 8.2.30: sin arreglo de php-src" '! php2shell_backport 8.1.33 > /dev/null && ! php2shell_backport 8.2.30 > /dev/null'
mkdir -p "$W/src"
check "un codigo que no es el de PHP: el parche no entra y se dice" '! php2shell_apply 7.4.33 "$W/src" "$W/p.log" > "$W/p.out" 2>&1 && grep -q "no entra" "$W/p.out"'
PHP2SHELL_DIFF_8_0_30=${PHP2SHELL_DIFF_8_0_30/A/B}
check "diff cambiado: no coincide con su sha256 y no se aplica" '! php2shell_apply 8.0.30 "$W/src" "$W/p.log" > "$W/p.out" 2>&1 && grep -q "sha256" "$W/p.out"'
check "install_stack lo aplica antes de configure y deja la marca" 'grep -q "php2shell_apply \"\$version\" \"\$PWD\"" "$SRC" && grep -q "> \"\$S/\$PHP2SHELL_MARK\"" "$SRC"'

# --- Firmas de las descargas ---
command -v gpg > /dev/null && command -v gpgv > /dev/null || { echo "  FALLA faltan gpg y gpgv"; exit 1; }
G=$W/gpg; mkdir -m 700 "$G"
base64 -d <<< "$GPG_KEYS_B64" | xz -dc > "$W/claves.gpg"
have=$(gpg --homedir "$G" --batch --with-colons --show-keys "$W/claves.gpg" 2> /dev/null | awk -F: '$1 == "fpr" { print $10 }')
missing=""
for f in $GPG_FPR_APACHE $GPG_FPR_MARIADB $GPG_FPR_PMA $(for b in 8.0 8.1 8.2 8.3 8.4 8.5 8.6; do php_gpg_fprs $b; done) 5A52880781F755608BF815FC910DEB46F53EA312; do
    grep -qx "$f" <<< "$have" || missing+=" $f"
done
check "las claves incrustadas tienen todas las huellas (PHP, Apache, MariaDB, phpMyAdmin)" '[ -z "$missing" ]'
check "rama de PHP desconocida: sin huellas (no se instala sin comprobar)" '! php_gpg_fprs 7.3 > /dev/null && ! php_gpg_fprs 9.0 > /dev/null'
# Una firma buena de otra clave (que no es de quien publica) no vale
gpg --homedir "$G" --batch --passphrase "" --quick-gen-key "Otro <otro@example.invalid>" ed25519 sign 1d > /dev/null 2>&1
echo "codigo" > "$W/php.tar.xz"
gpg --homedir "$G" --batch --armor --detach-sign -o "$W/php.tar.xz.asc" "$W/php.tar.xz" 2> /dev/null
mine=$(gpg --homedir "$G" --batch --with-colons --list-keys otro@example.invalid 2> /dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
check "firma de una clave que no esta incrustada: no vale (ni con su huella)" '[ -n "$mine" ] && ! verify_sig "$W/php.tar.xz" "$W/php.tar.xz.asc" "$mine $(php_gpg_fprs 8.4)"'
check "sin firma: no vale" '! verify_sig "$W/php.tar.xz" "$W/no-esta.asc" "$(php_gpg_fprs 8.4)"'
check "install_stack comprueba las firmas de PHP, Apache, MariaDB y phpMyAdmin" \
    'grep -q "download_signed \"https://www.php.net/distributions/php-\$version.tar.xz\"" "$SRC" && grep -q "download_signed \"\$base/\$1\" \"\$2\" \"\$sum\" \"\$GPG_FPR_APACHE\"" "$SRC" && grep -q "verify_sig mariadb.tar.gz mariadb.tar.gz.asc \"\$GPG_FPR_MARIADB\"" "$SRC" && [ "$(grep -c "download_signed \"https://files.phpmyadmin.net" "$SRC")" -eq 2 ]'

# --- Compilacion con nexum-build ---
check "se compila con sudo -u nexum-build y env -i" 'grep -q "sudo -u \"\$BUILD_USER\" env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin" "$SRC" && [ "$BUILD_USER" == nexum-build ]'
check "la carpeta de la compilacion la crea root (la de nexum-build, dentro)" 'grep -q "build_top=\$(sudo mktemp -d /tmp/lvm-pila-" "$SRC" && grep -q "sudo install -d -o \"\$BUILD_USER\" -g \"\$BUILD_USER\" -m 755 \"\$build_top/w\"" "$SRC"'
check "las variables y el script, en ficheros de root" 'grep -q "sudo install -m 644 -o 0 -g 0 \"\$SELF\" \"\$build_top/lvm-instalador.sh\"" "$SRC"'
out=$(bash "$SRC" construir-pila "$W/vars" 2>&1); rc=$?
check "construir-pila con otro usuario: no hace nada" '[ $rc -ne 0 ] && grep -q "solo lo usa install_stack" <<< "$out"'
check "las descargas y las firmas, dentro de la compilacion (stack_build_phase)" 'awk "/^function stack_build_phase\\(\\) \\{/{p=1} p && /download_signed/{f=1} p && /^}/{exit} END{exit !f}" "$SRC"'

# --- actualizar-a (sin root: LVM_PRUEBA) ---
T=$W/t; mkdir -p "$T/lampp-8.3.10/etc" "$T/lampp-7.4/etc"
echo "8.3.10|2.4.69|11.4.13|1.3.9|5.40.3|5.2.3" > "$T/lampp-8.3.10/etc/lvm-stack"
out=$(LVM_PRUEBA=$T bash "$SRC" actualizar-a 8.3.10 8.4.27 2>&1)
check "actualizar-a: solo a un parche de su rama" 'grep -q "solo se pasa a otro parche de su rama" <<< "$out"'
out=$(LVM_PRUEBA=$T bash "$SRC" actualizar-a 8.3.10 8.3.9 2>&1)
check "actualizar-a: no hacia atras" 'grep -q "no se actualiza hacia atras" <<< "$out"'
out=$(LVM_PRUEBA=$T bash "$SRC" actualizar-a 8.3.10 8.3.36x 2>&1)
check "actualizar-a: version no valida, uso" 'grep -q "^Uso: lvm-instalador actualizar-a" <<< "$out"'
out=$(LVM_PRUEBA=$T bash "$SRC" actualizar-a ../x 8.3.36 2>&1)
check "actualizar-a: carpeta no valida" 'grep -q "no valida" <<< "$out"'

# --- Docker sin terminal y con su configuracion ---
extract "$SRC" docker_sock docker_config_dir dk || exit 1
eval "$(sed -n "/^NO_TTY_PY='/,/^'\$/p" "$SRC")"
DOCKER_CONFIG_DIR=$W/log/docker-config LVM_DOCKER_HOST=unix://$W/d.sock DOCKER_BIN=$W/docker
printf '#!/bin/sh\necho "cfg=$DOCKER_CONFIG host=$DOCKER_HOST tty=$(ps -o tty= -p $$)"\nread x && echo "in=$x"\nexit 4\n' > "$DOCKER_BIN"; chmod +x "$DOCKER_BIN"
mkdir -p "$W/log"; mkdir -p "$DOCKER_CONFIG_DIR/cli-plugins"; echo '{"credsStore":"x"}' > "$DOCKER_CONFIG_DIR/config.json"
export NT=$NO_TTY_PY
o=$(echo dato | dk ps); rc=$?
check "dk: DOCKER_CONFIG del gestor y el socket de Docker sin root" 'grep -q "cfg=$DOCKER_CONFIG_DIR host=unix://$W/d.sock" <<< "$o"'
check "dk: sin complementos propios ni ayudante de claves" '[ ! -e "$DOCKER_CONFIG_DIR/cli-plugins" ] && [ "$(cat "$DOCKER_CONFIG_DIR/config.json")" == "{}" ] && [ "$(stat -c %a "$DOCKER_CONFIG_DIR")" == 700 ]'
check "dk: la entrada por tuberia llega (una carga de BBDD) y su codigo se propaga" 'grep -q "^in=dato$" <<< "$o" && [ $rc -eq 4 ]'
o=$(script -qec "bash -c '$(declare -f docker_sock docker_config_dir dk | sed "s/'/'\\\\''/g"); NO_TTY_PY=\$NT; DOCKER_CONFIG_DIR=$DOCKER_CONFIG_DIR LVM_DOCKER_HOST=x DOCKER_BIN=$DOCKER_BIN; dk ps'" /dev/null 2>&1 | tr -d '\r')
check "dk: dentro de una terminal, docker no la tiene" 'grep -q "tty=?" <<< "$o"'
ln -s /tmp "$W/log/enlace"; DOCKER_CONFIG_DIR=$W/log/enlace
check "dk: si la carpeta es un enlace, no se usa" '! dk ps > /dev/null 2>&1'
check "phpMyAdmin de Docker sin entrar solo como root (sin PMA_USER ni PMA_PASSWORD)" '! grep -q "PMA_USER: root" "$SRC" && grep -q "^function docker_fix_pma() {" "$SRC"'
check "imagen de Docker: php.ini de produccion e install-php-extensions fijado por su huella" 'grep -q "php.ini-production" "$SRC" && ! grep -q "php.ini-development" "$SRC" && grep -q "^DOCKER_EXT_INSTALLER=\"mlocati/php-extension-installer:[0-9.]*@sha256:[0-9a-f]\{64\}\"$" "$SRC"'
check "Docker: ninguna contraseña en las ordenes (-e MYSQL_PWD=...)" '! grep -q "exec -T -e MYSQL_PWD=" "$SRC"'
exit $fail
