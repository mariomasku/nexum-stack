#!/bin/bash
# Pruebas del octavo repaso de seguridad (Linux 1.44.0 / Mac 1.32.0) y de lo nuevo de esas versiones:
# nombres de proceso con lineas falsas, sudo kill solo con numeros de proceso de verdad, el filtro de
# INVOKER al cargar volcados (con un MariaDB temporal), el bloqueo del usuario de la base sin permisos
# de fuera, el MariaDB temporal nunca como root, el envoltorio del cliente de copiar-bd, no arrancar si
# no se ha podido proteger, montar-proyecto / desmontar-proyecto y la ayuda de los comandos.
# Uso: repaso8.sh <lvm-instalador.sh>   (Linux o Mac: lo que es de una sola plataforma se salta)
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-r8.XXXX") || exit 1
MAC=0; grep -q '^    BASE_DIR=/Applications$' "$SRC" && MAC=1
SOCKD=$W; [ ${#SOCKD} -gt 80 ] && SOCKD=$(mktemp -d /tmp/lvm-r8.XXXX)
SLEEPER=""
cleanup() {
    [ -n "$SLEEPER" ] && kill "$SLEEPER" 2> /dev/null
    [ -x "$W/client" ] && "$W/client" -uroot -e "SHUTDOWN" > /dev/null 2>&1
    wait 2> /dev/null
    rm -rf "$W"; [ "$SOCKD" != "$W" ] && rm -rf "$SOCKD"
}
trap cleanup EXIT

# --- sudo kill solo con numeros de proceso de verdad
extract "$SRC" kill_pids || exit 1
check "kill_pids: fuera -1, 0, 1, letras, signos y numeros enormes" '[ "$(kill_pids -1 0 1 abc 5x -5 99999999999 2 123)" = "2 123" ]'
check "kill_pids: nada valido, nada" '[ -z "$(kill_pids -1 1 x)" ]'
# (cada sudo kill de una lista de pids, con kill_pids en las 4 lineas de antes)
unsafe=$(awk '/(pids|sure)=\$\(kill_pids/ { last = NR } /kill -(TERM|KILL) (-- )?\$(pids|sure)/ && NR - last > 4 { print NR }' "$SRC")
check "cerrar procesos usa kill_pids antes de cada sudo kill${unsafe:+ (lineas: $unsafe)}" '[ -z "$unsafe" ] && [ "$(grep -c "pids=\$(kill_pids\|sure=\$(kill_pids" "$SRC")" -ge 2 ]'

# --- Lineas falsas en la lista de procesos (el nombre lo elige cada proceso)
if [ $MAC -eq 0 ]; then
    extract "$SRC" lampp_processes || exit 1
    LAMPP_LINK=/opt/lampp
    (exec -a "/opt/lampp-8.2/bin/httpd
P|-1|1|root|?|1|httpd" sleep 30) &
    SLEEPER=$!
    sleep 0.3
    out=$(lampp_processes)
    check "Linux: ninguna linea con un pid que no sea un numero" '! awk -F"|" "\$2 !~ /^[0-9]+\$/" <<< "$out" | grep -q .'
    check "Linux: el proceso trucado sale con su pid y el nombre limpio" 'grep -q "^P|$SLEEPER|" <<< "$out" && ! grep -q "P|-1|" <<< "$out"'
    check "Linux: todas las lineas con 7 campos" '! awk -F"|" "NF != 7" <<< "$out" | grep -q .'
    kill "$SLEEPER" 2> /dev/null; wait "$SLEEPER" 2> /dev/null; SLEEPER=""
else
    extract "$SRC" lampp_processes || exit 1
    BASE_DIR=$W/App LINK=$W/App/XAMPP DRY=0 SUDO=""
    mkdir -p "$W/App/XAMPP-8.4/xamppfiles"
    L="Wed Oct 21 10:00:00 2026"
    # ps de mentira: con «pid=» solo los numeros; con la orden, una linea falsa con el pid de otro
    # proceso (400, que tambien sale con su orden de verdad) y otra con uno que no existe (900)
    ps() {
        if [ "$*" == "-axo pid=" ]; then printf '  100\n  200\n  400\n'; return; fi
        printf '  100     1 root     %s %s/App/XAMPP-8.4/xamppfiles/bin/httpd -k start\n' "$L" "$W"
        printf '  200   100 daemon   %s %s/App/XAMPP-8.4/xamppfiles/bin/httpd -k start\n' "$L" "$W"
        printf '  400     1 root     %s %s/App/XAMPP-8.4/xamppfiles/bin/httpd\n' "$L" "$W"
        printf '  400     1 root     %s /usr/sbin/sshd\n' "$L"
        printf '  900     1 root     %s %s/App/XAMPP-8.4/xamppfiles/bin/httpd\n' "$L" "$W"
    }
    out=$(lampp_processes)
    check "Mac: el pid repetido (linea falsa) no sale" '! grep -q "^P|400|" <<< "$out"'
    check "Mac: el pid que no existe no sale" '! grep -q "^P|900|" <<< "$out"'
    check "Mac: los de verdad si salen" 'grep -q "^P|100|" <<< "$out" && grep -q "^P|200|" <<< "$out"'
    unset -f ps
    # El XAMPP oficial (una carpeta en /Applications/XAMPP): su script nunca como root
    extract "$SRC" xampp_ctl || exit 1
    mkdir -p "$W/App/XAMPP/xamppfiles"
    printf '#!/bin/sh\necho EJECUTADO\n' > "$W/App/XAMPP/xamppfiles/xampp"; chmod +x "$W/App/XAMPP/xamppfiles/xampp"
    SUDO=sudo_falso; sudo_falso() { "$@"; }
    out=$(LINK=$W/App/XAMPP xampp_ctl start 2>&1); rc=$?
    check "Mac: el script del XAMPP oficial no se ejecuta como root" '[ $rc -ne 0 ] && ! grep -q EJECUTADO <<< "$out"'
    SUDO=""
    check "Mac: volver-oficial no exige un nombre de carpeta concreto (antes, siempre «no es de root»)" '! grep -q "official_trusted" "$SRC"'
    check "Mac: parar el oficial solo cierra sus servidores" 'grep -q "httpd|mysqld|mariadbd|proftpd|php-fpm) \$SUDO kill -TERM" "$SRC"'
fi

# --- Filtro de INVOKER al cargar: la palabra suelta pasa a DEFINER (mismo largo y mayusculas)
eval "$(sed -n "/^INVOKER_PY='/,/^'\$/p" "$SRC")"
[ -n "$INVOKER_PY" ] || { bad "no esta INVOKER_PY"; exit 1; }
printf 'CREATE FUNCTION a() RETURNS INT SQL SECURITY INVOKER RETURN 1;\nCREATE FUNCTION b() SQL SeCuRiTy /* x */ InVoKeR RETURN 1;\nCREATE FUNCTION c() SQL SECURITY --\001x\nINVOKER RETURN 1;\nCREATE FUNCTION d() SQL SECURITY /*M!999999 DEFINER */ INVOKER RETURN 1;\nCREATE FUNCTION e() SQL SECURITY/*!50013 */invoker RETURN 1;\nINSERT INTO t VALUES (%s);\n' \
    "'php-di/invoker'),('Vendor\\\\Invoker\\\\X'),('invoker_id'),('\$invoker'),('a.invoker'),('SECURITYINVOKER'" > "$W/casos.sql"
python3 -I -c "$INVOKER_PY" < "$W/casos.sql" > "$W/r.sql"
check "INVOKER: no queda la palabra suelta (comentarios, -- con control, /*M! */ y /*! */ en medio)" '! grep -qiP "(?<![A-Za-z0-9_\$@.\\\\])(?<![^*]/)invoker(?![A-Za-z0-9_\$.\\\\])" "$W/r.sql" && [ "$(grep -o "DEFINER\|DeFiNeR\|definer" "$W/r.sql" | wc -l)" -ge 5 ]'
check "INVOKER: los nombres que la llevan no cambian" 'grep -qF "php-di/invoker" "$W/r.sql" && grep -qF "Invoker" "$W/r.sql" && grep -qF "invoker_id" "$W/r.sql" && grep -qF "\$invoker" "$W/r.sql" && grep -qF "a.invoker" "$W/r.sql" && grep -qF "SECURITYINVOKER" "$W/r.sql"'
check "INVOKER: mismo largo (no rompe los datos serializados)" '[ "$(wc -c < "$W/r.sql")" = "$(wc -c < "$W/casos.sql")" ]'
same=1
for n in 1 2 3 7 8 9 13 64; do
    python3 -I -c "$INVOKER_PY" $n < "$W/casos.sql" | cmp -s - "$W/r.sql" || same=0
done
check "INVOKER: igual con cualquier tamaño de trozo" '[ $same = 1 ]'
python3 -c 'import sys; sys.stdout.buffer.write(b"SQL SECURITY /*" + b"x" * 3000000 + b"*/ INVOKER\n")' > "$W/largo.sql"
check "INVOKER: tambien tras un comentario de 3 MB (mas que un trozo)" '! python3 -I -c "$INVOKER_PY" < "$W/largo.sql" | grep -q INVOKER'
check "INVOKER: la carga lo usa" 'grep -q "\"\${definer\[@\]}\" | \"\${imp\[@\]}\"" "$SRC"'

# --- MariaDB temporal (sin red) para la carga y el bloqueo
LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/bin/mysql_install_db --no-defaults --basedir=/opt/lampp-8.2.4 \
    --datadir="$W/data" --auth-root-authentication-method=normal > "$W/install.log" 2>&1 \
    || { bad "no se ha podido crear el MariaDB temporal"; exit 1; }
printf '#!/bin/sh\nLD_LIBRARY_PATH=/opt/lampp-8.2.4/lib exec /opt/lampp-8.2.4/bin/mysql --no-defaults -S %s/sock "$@"\n' "$SOCKD" > "$W/client"
chmod +x "$W/client"
LD_LIBRARY_PATH=/opt/lampp-8.2.4/lib /opt/lampp-8.2.4/sbin/mysqld --no-defaults --basedir=/opt/lampp-8.2.4 --datadir="$W/data" \
    --socket="$SOCKD/sock" --skip-networking --pid-file="$W/pid" --log-error="$W/err.log" > /dev/null 2>&1 &
for i in $(seq 50); do "$W/client" -uroot -e 'SELECT 1' > /dev/null 2>&1 && break; sleep 0.2; done
mysql=("$W/client" -uroot)
db=wp_r8
"${mysql[@]}" -e "CREATE DATABASE $db; CREATE DATABASE otra; CREATE TABLE otra.v (x VARCHAR(10)); INSERT INTO otra.v VALUES ('limpio');
    CREATE USER 'lvm_bd_$db'@'localhost' IDENTIFIED BY 'p'; GRANT ALL PRIVILEGES ON \`wp\\_r8\`.* TO 'lvm_bd_$db'@'localhost'; CREATE ROLE r8"
imp=(env MYSQL_PWD=p "$W/client" -ulvm_bd_$db --binary-mode --local-infile=0)
cat > "$W/malo.sql" <<'SQL'
DELIMITER ;;
CREATE FUNCTION f() RETURNS INT SQL SECURITY INVOKER MODIFIES SQL DATA BEGIN UPDATE otra.v SET x='pwned'; RETURN 1; END;;
DELIMITER ;
CREATE TABLE real_options (option_name VARCHAR(10));
INSERT INTO real_options VALUES ('siteurl');
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 SQL SECURITY INVOKER */
/*!50001 VIEW wp_options AS SELECT option_name, f() AS z FROM real_options */;
DELIMITER ;;
CREATE FUNCTION f2() RETURNS INT SQL SECURITY /*M!999999 DEFINER */ INVOKER MODIFIES SQL DATA BEGIN UPDATE otra.v SET x='pwned'; RETURN 1; END;;
CREATE FUNCTION f3() RETURNS INT SQL SECURITY/*!50013 */InVoKeR MODIFIES SQL DATA BEGIN UPDATE otra.v SET x='pwned'; RETURN 1; END;;
CREATE PROCEDURE p4() SQL SECURITY
# comentario
INVOKER BEGIN UPDATE otra.v SET x='pwned'; END;;
DELIMITER ;
SQL
python3 -I -c "$INVOKER_PY" < "$W/malo.sql" | "${imp[@]}" $db 2>&1 | head -3
types=$("${mysql[@]}" -N -e "SELECT SECURITY_TYPE FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA='$db'
    UNION ALL SELECT SECURITY_TYPE FROM information_schema.VIEWS WHERE TABLE_SCHEMA='$db'" | sort -u | paste -sd,)
check "carga: la funcion y la vista quedan DEFINER desde el principio" '[ "$types" = DEFINER ]'
"${mysql[@]}" -N -e "SELECT * FROM $db.wp_options; SELECT $db.f2(); SELECT $db.f3(); CALL $db.p4()" > /dev/null 2>&1
check "carga: root usa la vista, las funciones y el procedimiento a mitad de carga y no toca otra base" '[ "$("${mysql[@]}" -N -e "SELECT x FROM otra.v")" = limpio ]'

# --- Bloqueo: sin permisos de fuera de su base (globales, de otras bases, roles)
extract "$SRC" db_lock_import_user db_kill_user || exit 1
"${mysql[@]}" -e "GRANT ALL PRIVILEGES ON *.* TO 'lvm_bd_$db'@'localhost' WITH GRANT OPTION; GRANT SELECT ON otra.* TO 'lvm_bd_$db'@'localhost'; GRANT r8 TO 'lvm_bd_$db'@'localhost'"
out=$(db_lock_import_user lvm_bd_$db "${mysql[@]}")
grants=$("${mysql[@]}" -N --raw -e "SHOW GRANTS FOR 'lvm_bd_$db'@'localhost'")
check "bloqueo: solo USAGE y su base" '[ "$(wc -l <<< "$grants")" = 2 ] && grep -qF "ON \`wp\\_r8\`.*" <<< "$grants" && ! grep -qF "GRANT OPTION" <<< "$grants" && ! grep -qF "\`otra\`" <<< "$grants" && ! grep -qF "GRANT \`r8\`" <<< "$grants"'
check "bloqueo: sin avisos si queda limpio" '[ -z "$out" ]'
check "bloqueo: no puede entrar" '! env MYSQL_PWD=p "$W/client" -ulvm_bd_$db -e "SELECT 1" > /dev/null 2>&1'
check "bloqueo: su vista y su funcion siguen funcionando (DEFINER)" '"${mysql[@]}" -N -e "SELECT option_name FROM $db.wp_options" 2>&1 | grep -q siteurl || "${mysql[@]}" -N -e "SELECT COUNT(*) FROM $db.real_options" | grep -q 1'
check "bloqueo: sin crear vistas, rutinas ni eventos" '! grep -q "CREATE VIEW\|CREATE ROUTINE\|EVENT" <<< "$grants"'

# --- MariaDB temporal: nunca como root (var/mysql enlazado o de root)
extract "$SRC" db_temp_start || exit 1
DRY=0 TEST_DIR="" SUDO=""
calls=$W/llamadas
mktemp() { echo "mktemp $*" >> "$calls"; command mktemp "$@"; }
stat() { echo root; }
trusted_version_dir() { return 0; }
mkdir -p "$W/v/var/mysql" "$W/v/xamppfiles/var/mysql"
out=$(db_temp_start "$W/v" --con-permisos 2>&1); rc=$?
check "MariaDB temporal: datos de root, no se arranca" '[ $rc -ne 0 ] && grep -q "son de root" <<< "$out" && [ ! -s "$calls" ]'
unset -f stat mktemp trusted_version_dir
check "MariaDB temporal: el dueño se mira siguiendo el enlace (-L)" 'grep -qE "stat -L (-c %U|-f %Su)" <<< "$(declare -f db_temp_start)"'

# --- Envoltorio del cliente de copiar-bd: en una carpeta de /tmp (de root con sudo), no en la tuya
extract "$SRC" db_client_wrapper db_client_wrapper_remove || exit 1
SUDO="" DB_CLI_DIR="" DB_CLI=""
db_client_wrapper "/opt/con espacio/mysql" "/opt/x/lib" "$W/s.sock"
check "envoltorio: en /tmp/lvm-cliente-*, no en ~/.lvm-instalador" '[[ "$DB_CLI_DIR" == /tmp/lvm-cliente-* ]] && [ -x "$DB_CLI" ]'
check "envoltorio: ruta con espacios bien escrita" 'grep -qF "/opt/con\\ espacio/mysql --no-defaults" "$DB_CLI"'
check "envoltorio: sin escritura para otros" '[ "$(command stat -c %a "$DB_CLI")" = 755 ]'
d=$DB_CLI_DIR
db_client_wrapper_remove
check "envoltorio: se borra" '[ ! -e "$d" ] && [ -z "$DB_CLI" ]'
check "copiar-bd ya no crea cliente-XXXXXX en tu carpeta" '! grep -q "LOG_DIR/cliente-" "$SRC"'
check "copiar-bd: la copia temporal se borra tambien al cancelar" 'grep -q "DB_COPY_TMP" <<< "$(declare -f db_cleanup 2> /dev/null || awk "/^function db_cleanup/,/^}/" "$SRC")"'

# --- No arrancar si no se ha podido proteger
extract "$SRC" secure_failed || exit 1
DRY=0
check "secure_failed: con 2 no se arranca" 'secure_failed 2 /x > /dev/null'
check "secure_failed: con 0 o 1 si" '! secure_failed 0 /x && ! secure_failed 1 /x'
DRY=1
check "secure_failed: en la simulacion no corta" '! secure_failed 2 /x'

# --- montar-proyecto: direcciones de git
extract "$SRC" git_url_ok || exit 1
okurl=1
for u in https://github.com/a/b.git git@github.com:a/b.git ssh://git@github.com:22/a/b.git https://gitlab.example.com/g/sub/p; do
    git_url_ok "$u" || { okurl=0; echo "    no admite $u"; }
done
check "git: admite https, git@ y ssh://" '[ $okurl = 1 ]'
badurl=1
for u in "file:///etc" "ext::sh -c id" "git@-oProxyCommand=x:a" "https://github.com/-u" "--upload-pack=x" "https://u:p@github.com/a/b" "git@github.com:a/b;id" "https://github.com/a b" "/opt/htdocs" "http://github.com/a/b"; do
    git_url_ok "$u" && { badurl=0; echo "    admite $u"; }
done
check "git: rechaza file://, ext::, opciones, credenciales, http y caracteres raros" '[ $badurl = 1 ]'
check "git: clon sin submodulos, sin ganchos, sin preguntas y solo https/ssh" 'grep -q "clone --no-recurse-submodules -- \"\$url\" \"\$dest\"" "$SRC" && grep -q "protocol.allow=never" "$SRC" && grep -q "core.hooksPath=/dev/null" "$SRC" && grep -q "GIT_TERMINAL_PROMPT=0" "$SRC"'

check "montar-proyecto: una tienda recupera su dominio tras subir el volcado" 'grep -A3 "aun no existia" "$SRC" | grep -q "load_project_domain \"\$folder\" \"\$db\""'

# --- Bajos arreglados en la 1.44.2 / Mac 1.32.3
check "lvm-copias: al arrancar se deja solo para ti (700)" 'grep -q "chmod 700 \"\$HOME/lvm-copias\"" "$SRC" && ! grep -qE "mkdir -p \"\\\$HOME/lvm-copias\"" "$SRC"'
imp=$(awk '/^function import_database\(\)/,/^}/' "$SRC")
e=$(grep -n "information_schema.ENGINES" <<< "$imp" | head -1 | cut -d: -f1)
d=$(grep -n "DROP DATABASE" <<< "$imp" | head -1 | cut -d: -f1)
check "vaciar: los motores se miran antes de borrar la base" '[ -n "$e" ] && [ -n "$d" ] && [ "$e" -lt "$d" ]'
# (desde la 1.50.1 de Linux un .local se puede apagar a mano: lo prueba extras.sh)
if ! grep -q '^function local_off() {' "$SRC"; then
extract "$SRC" hosts_fake_one || exit 1
valid_domain() { return 0; }
out=$(hosts_fake_one otra.local no 2>&1); rc=$?
check "hosts-falsear: un .local no se apaga" '[ $rc -ne 0 ] && grep -q "no se deja de falsear" <<< "$out"'
fi

# --- La ayuda: cada comando que enseña existe
cmds=$(sed -n '3,/^$/p' "$SRC" | grep -oE '^#   lvm-instalador [a-z][a-z-]*' | awk '{print $3}' | sort -u)
missing=""
for c in $cmds; do
    grep -qE "^    ([a-z|-]*\|)?$c(\|[a-z|-]*)?\)" "$SRC" || missing+=" $c"
done
check "ayuda: todos sus comandos existen${missing:+ (faltan:$missing)}" '[ -z "$missing" ]'
check "ayuda: incluye montar-proyecto y desmontar-proyecto" 'grep -q "^#   lvm-instalador montar-proyecto" "$SRC" && grep -q "^#   lvm-instalador desmontar-proyecto" "$SRC"'

# --- Simulaciones de los comandos nuevos (solo Linux: el del Mac no arranca fuera de macOS)
if [ $MAC -eq 0 ]; then
    out=$(bash "$SRC" --simular montar-proyecto "ext::sh -c id" x 8.2 wp_x 2>&1)
    check "montar-proyecto: direccion mala, no hace nada" 'grep -q "no es valida" <<< "$out" && ! grep -q "Clonando" <<< "$out"'
    out=$(bash "$SRC" --simular montar-proyecto https://github.com/a/b.git ../fuera 8.2 wp_x 2>&1)
    check "montar-proyecto: carpeta con ../, no" 'grep -q "solo puede llevar" <<< "$out"'
    out=$(bash "$SRC" --simular montar-proyecto https://github.com/a/b.git r8-nuevo 9.9 wp_x 2>&1)
    check "montar-proyecto: version que no existe, no" 'grep -q "No existe la version" <<< "$out"'
    out=$(bash "$SRC" --simular montar-proyecto https://github.com/a/b.git r8-nuevo 8.2 "wp;x" 2>&1)
    check "montar-proyecto: nombre de BBDD malo, no" '! grep -q "Clonando" <<< "$out"'
    out=$(bash "$SRC" --simular montar-proyecto https://github.com/a/b.git r8-nuevo 8.2 wp_r8nuevo 2>&1)
    check "montar-proyecto: los tres pasos en la simulacion" 'grep -q "1/3" <<< "$out" && grep -q "2/3" <<< "$out" && grep -q "3/3" <<< "$out"'
    out=$(bash "$SRC" --simular desmontar-proyecto 2>&1)
    check "desmontar-proyecto: el enlace pasa a la pagina vacia" 'grep -q "ln -s .lvm-sin-proyecto/" <<< "$out" || grep -q "No hay ningun" <<< "$out"'
    out=$(bash "$SRC" --simular gui-proyectos 2>&1 | head -1)
    check "gui-proyectos: nunca enseña la pagina vacia como proyecto" '! grep -q "lvm-sin-proyecto" <<< "$out"'
fi
exit $fail
