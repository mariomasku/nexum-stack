# Al cargar una BBDD (y al pulsar el boton del panel en Cargar proyecto) se le añade un administrador
# de pruebas: el boton abre la pantalla de acceso con el usuario y la contraseña ya escritos. Solo en
# las BBDD de este equipo (que nunca van a produccion), y nunca en las copias que se descargan o se
# exportan (test_admin_filter). Es local@local.test con la contraseña local o, si se ha puesto otro en
# Configuracion (admin-pruebas), ese: su correo (que es tambien el usuario) y su contraseña van en
# TEST_ADMIN_FILE. TEST_ADMIN_USER y TEST_ADMIN_PASS son los de ahora (test_admin_load los lee)
TEST_ADMIN_USER="local@local.test"
TEST_ADMIN_PASS="local"
# (huella bcrypt de «local», para PrestaShop 1.7 o posterior; la 1.6 usa md5 de su _COOKIE_KEY_ y
# la contraseña, y WordPress acepta md5 y la cambia por la suya al entrar)
TEST_ADMIN_BCRYPT='$2y$12$IqVkFsJq4UhjbzLfagfW9eU5V6iIauQCbfMJDY26MoM8ETz6ZKgxG'
# La cuenta que crea Nexum lleva su marca: en WordPress, user_nicename local-pruebas y display_name
# «Local (pruebas)»; en PrestaShop, firstname Pruebas y lastname Local. Solo se cambia (y solo se
# quita de las copias) una cuenta con la marca y con un correo de los que ha usado el administrador de
# pruebas (el de ahora, los de antes del fichero y local@local.test, que no es de nadie: esa, con o sin
# marca, como siempre). Una cuenta de verdad con ese correo y sin la marca no se toca nunca
# Contraseña: de 4 a 64 de estos caracteres (sin comillas, barra invertida, espacios, $, `, | ni ;)
TEST_ADMIN_PASS_CHARS='A-Za-z0-9._@%+=:,!#*?-'

# ¿Correo que vale para el administrador de pruebas? Solo ASCII, con forma de correo y como mucho 60
# caracteres (lo que cabe en user_login de WordPress). Sin comillas ni nada que cambie una consulta
function test_admin_mail_ok() {
    local LC_ALL=C
    [ ${#1} -le 60 ] && [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

function test_admin_pass_ok() {
    local LC_ALL=C
    [[ "$1" =~ ^[A-Za-z0-9._@%+=:,!#*?-]{4,64}$ ]]
}

# Lee el fichero del ajuste (solo si es un fichero normal tuyo, sin seguir enlaces): deja en
# TEST_ADMIN_USER, TEST_ADMIN_PASS y TEST_ADMIN_HASH (su bcrypt) el de ahora, en TEST_ADMIN_SET si es
# uno propio (1) o local@local.test (0) y en TEST_ADMIN_MAILS todos los correos que ha usado (para
# quitarlos de las copias). Lo que no vale del fichero no cuenta
TEST_ADMIN_MAILS=(local@local.test)
TEST_ADMIN_SET=0
TEST_ADMIN_HASH=$TEST_ADMIN_BCRYPT
function test_admin_load() {
    local f=$LOG_DIR/admin-pruebas line k v mail="" pass="" hash="" m seen
    local hist=()
    TEST_ADMIN_USER=local@local.test TEST_ADMIN_PASS=local TEST_ADMIN_HASH=$TEST_ADMIN_BCRYPT TEST_ADMIN_SET=0
    TEST_ADMIN_MAILS=(local@local.test)
    # (tuyo; con sudo, del usuario que lo ha lanzado: si no, la copia llevaria su administrador de pruebas)
    local owner_ok=0
    if [ -f "$f" ] && [ ! -L "$f" ]; then
        if [ -O "$f" ]; then
            owner_ok=1
        elif [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] \
                && [ "$(stat -c %U "$f" 2> /dev/null || stat -f %Su "$f" 2> /dev/null)" == "$SUDO_USER" ]; then
            owner_ok=1
        fi
    fi
    if [ $owner_ok -eq 1 ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            k=${line%%=*} v=${line#*=}
            [ "$k" == "$line" ] && continue
            case $k in
                correo) mail=$v ;;
                clave) pass=$v ;;
                bcrypt) hash=$v ;;
                antes) hist+=("$v") ;;
            esac
        done < <(head -c 65536 "$f" 2> /dev/null)
    fi
    if test_admin_mail_ok "$mail" && test_admin_pass_ok "$pass"; then
        TEST_ADMIN_USER=$mail TEST_ADMIN_PASS=$pass TEST_ADMIN_SET=1 TEST_ADMIN_HASH=""
        # (la huella se hace al guardar; si falta o no tiene forma de bcrypt, se rehace al usarla)
        [[ "$hash" =~ ^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$ ]] && TEST_ADMIN_HASH=$hash
        hist+=("$mail")
    fi
    for m in "${hist[@]}"; do
        test_admin_mail_ok "$m" || continue
        seen=0
        for v in "${TEST_ADMIN_MAILS[@]}"; do [ "${v,,}" == "${m,,}" ] && seen=1; done
        [ $seen -eq 0 ] && TEST_ADMIN_MAILS+=("$m")
    done
    return 0
}

# Huella bcrypt ($2y$, coste 8) de la contraseña de LVM_ADMIN_CLAVE (por el entorno: en la linea de
# ordenes se veria con ps), en Python sin nada mas: el bcrypt de siempre, con las tablas de Blowfish
# sacadas de las cifras de pi (lo que son). La comprueba PHP con password_verify, como PrestaShop
function test_admin_bcrypt() {
    python3 -I - <<'EOF'
import os, sys
pw = os.environ.get("LVM_ADMIN_CLAVE", "").encode()
if not pw:
    sys.exit(1)
COST, N = 8, 18 + 1024
# Las cifras hexadecimales de pi (sin el 3), por la formula de Machin con enteros
bits = 32 * N + 64
one = 1 << bits
def atan_inv(x):
    total, term, k, x2 = 0, one // x, 1, x * x
    while term:
        total += term // k if k % 4 == 1 else -(term // k)
        term //= x2
        k += 2
    return total
frac = (16 * atan_inv(5) - 4 * atan_inv(239) - 3 * one) >> 64
w = [(frac >> (32 * (N - 1 - i))) & 0xFFFFFFFF for i in range(N)]
P, S = w[:18], [w[18 + 256 * i:18 + 256 * (i + 1)] for i in range(4)]
S0, S1, S2, S3 = S
M = 0xFFFFFFFF
def enc(L, R):
    for i in range(0, 16, 2):
        L ^= P[i]
        R ^= ((((S0[L >> 24] + S1[(L >> 16) & 255]) & M) ^ S2[(L >> 8) & 255]) + S3[L & 255]) & M
        R ^= P[i + 1]
        L ^= ((((S0[R >> 24] + S1[(R >> 16) & 255]) & M) ^ S2[(R >> 8) & 255]) + S3[R & 255]) & M
    return R ^ P[17], L ^ P[16]
def stream(data):
    j = 0
    while True:
        v = 0
        for _ in range(4):
            v = (v << 8) | data[j]
            j = (j + 1) % len(data)
        yield v
def expand(key, salt):
    ks = stream(key)
    for i in range(18):
        P[i] ^= next(ks)
    L = R = 0
    ss = stream(salt) if salt else None
    for box in [P] + S:
        for i in range(0, len(box), 2):
            if ss:
                L ^= next(ss)
                R ^= next(ss)
            L, R = enc(L, R)
            box[i], box[i + 1] = L, R
salt = os.urandom(16)
key = (pw + b"\0")[:72]
expand(key, salt)
for _ in range(1 << COST):
    expand(key, None)
    expand(salt, None)
c = [int.from_bytes(b"OrpheanBeholderScryDoubt"[i:i + 4], "big") for i in range(0, 24, 4)]
for _ in range(64):
    for i in range(0, 6, 2):
        c[i], c[i + 1] = enc(c[i], c[i + 1])
B64 = "./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
def b64(data):
    n = int.from_bytes(data, "big") << (6 - len(data) * 8 % 6) % 6
    k = (len(data) * 8 + 5) // 6
    return "".join(B64[(n >> (6 * (k - 1 - i))) & 63] for i in range(k))
raw = b"".join(x.to_bytes(4, "big") for x in c)[:23]
print("$2y$%02d$%s%s" % (COST, b64(salt), b64(raw)))
EOF
}

# md5 en hexadecimal de lo que llega por la entrada (la contraseña no va en la linea de ordenes)
function test_admin_md5() {
    python3 -I -c 'import hashlib, sys; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest())'
}

# La linea de la salida de una carga con el administrador de pruebas que se ha puesto (la contraseña,
# solo la de local@local.test: la propia no va a ningun registro)
function test_admin_note() {
    test_admin_load
    if [ "$TEST_ADMIN_SET" == 1 ]; then
        echo "Administrador de pruebas del panel: $TEST_ADMIN_USER (con la contraseña de Configuracion > Administrador de pruebas)"
    else
        echo "Administrador de pruebas del panel: local@local.test, contraseña local"
    fi
}

# Escribe el ajuste: correo, contraseña, huella e historial (los correos de antes), en un fichero
# nuevo solo tuyo (600) que pasa a ser el del ajuste (mv no sigue un enlace que hubiera en su sitio)
function test_admin_write() {
    local mail=$1 pass=$2 hash=$3 f=$LOG_DIR/admin-pruebas tmp m
    shift 3
    if [ -L "$LOG_DIR" ] || [ -d "$f" ]; then
        echo "No se puede guardar en $f"
        return 1
    fi
    mkdir -p -m 700 "$LOG_DIR" && tmp=$(mktemp "$LOG_DIR/.admin-pruebas.XXXXXX") || { echo "No se puede guardar en $f"; return 1; }
    {
        echo "# Administrador de pruebas de los paneles de WordPress y PrestaShop (Nexum): se cambia en"
        echo "# Configuracion > Administrador de pruebas o con nexum admin-pruebas. Sin correo: local@local.test"
        echo "# con la contraseña local. «antes»: los correos de antes (se quitan tambien de las copias)"
        [ -n "$mail" ] && printf 'correo=%s\nclave=%s\nbcrypt=%s\n' "$mail" "$pass" "$hash"
        for m in "$@"; do printf 'antes=%s\n' "$m"; done
    } > "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$f" || { rm -f "$tmp"; echo "No se puede guardar en $f"; return 1; }
}

# admin-pruebas                         el administrador de pruebas de ahora (sin la contraseña)
# admin-pruebas --clave                 con la contraseña
# admin-pruebas <correo> [<contraseña>] lo cambia (sin contraseña, o con -, la pide o la lee de la
#                                       entrada: asi no se ve con ps ni queda en el historial)
# admin-pruebas --quitar                vuelve a local@local.test con la contraseña local
# (la ventana lee el fichero y guarda con esta orden, con la contraseña por la entrada). Las BBDD ya
# cargadas no cambian: el nuevo se crea al cargar una BBDD o con usuario-pruebas <base>
function test_admin_config() {
    local mail=${1:-} pass=${2:-} hist=() m hash
    test_admin_load
    case "$mail" in
        ""|--clave)
            if [ "$TEST_ADMIN_SET" == 1 ]; then
                echo "Administrador de pruebas: $TEST_ADMIN_USER (el de Configuracion, en $LOG_DIR/admin-pruebas)"
            else
                echo "Administrador de pruebas: local@local.test (el de siempre: no se ha puesto otro)"
            fi
            if [ "$mail" == --clave ]; then
                echo "Contraseña: $TEST_ADMIN_PASS"
            else
                echo "Contraseña: (nexum admin-pruebas --clave para verla)"
            fi
            [ ${#TEST_ADMIN_MAILS[@]} -gt 1 ] && echo "Se quitan de las copias: ${TEST_ADMIN_MAILS[*]}"
            return 0 ;;
        -h|--ayuda|--help)
            echo "Uso: nexum admin-pruebas [--clave | <correo> [<contraseña>|-] | --quitar]"
            return 0 ;;
    esac
    # (el historial: los correos de antes que no son local@local.test, que cuenta siempre)
    for m in "${TEST_ADMIN_MAILS[@]}"; do [ "$m" != local@local.test ] && hist+=("$m"); done
    if [ "$mail" == --quitar ]; then
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] no se guarda nada: el administrador de pruebas volveria a ser local@local.test"
            return 0
        fi
        test_admin_write "" "" "" "${hist[@]:$(( ${#hist[@]} > 50 ? ${#hist[@]} - 50 : 0 ))}" || return 1
        echo "Administrador de pruebas: local@local.test, contraseña local."
        echo "Las BBDD ya cargadas no cambian: se pone al cargar una BBDD o con nexum usuario-pruebas <base>."
        return 0
    fi
    if [[ "$mail" == -* ]]; then
        echo "Uso: nexum admin-pruebas [--clave | <correo> [<contraseña>|-] | --quitar]"
        return 1
    fi
    if [ -z "$pass" ] || [ "$pass" == - ]; then
        if [ -t 0 ]; then
            read -r -s -p "Contraseña del administrador de pruebas: " pass
            echo
        else
            IFS= read -r pass
        fi
    fi
    if ! test_admin_mail_ok "$mail"; then
        echo "Correo no válido: solo letras sin tildes, números y . _ % + - con forma de correo (ana@local.test), hasta 60 caracteres"
        return 1
    fi
    if [ "${mail,,}" == local@local.test ]; then
        echo "local@local.test es el de siempre: para volver a él, nexum admin-pruebas --quitar"
        return 1
    fi
    if ! test_admin_pass_ok "$pass"; then
        echo "Contraseña no válida: de 4 a 64 letras sin tildes, números o . _ - @ % + = : , ! # * ? (sin espacios, comillas, \\, \$ ni \`)"
        return 1
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] no se guarda nada: el administrador de pruebas seria $mail"
        return 0
    fi
    hash=$(LVM_ADMIN_CLAVE=$pass test_admin_bcrypt)
    if ! [[ "$hash" =~ ^\$2y\$08\$[./A-Za-z0-9]{53}$ ]]; then
        echo "No se ha podido hacer la huella de la contraseña (python3): no se ha cambiado nada"
        return 1
    fi
    # (el de ahora, si cambia, pasa al historial; el nuevo no hace falta: cuenta por ser el de ahora)
    local keep=()
    for m in "${hist[@]}"; do [ "${m,,}" != "${mail,,}" ] && keep+=("$m"); done
    test_admin_write "$mail" "$pass" "$hash" "${keep[@]:$(( ${#keep[@]} > 50 ? ${#keep[@]} - 50 : 0 ))}" || return 1
    echo "Administrador de pruebas: $mail (guardado)."
    echo "Las BBDD ya cargadas no cambian: se pone al cargar una BBDD o con nexum usuario-pruebas <base>."
    echo "Si una BBDD ya tiene un usuario de verdad con ese correo, no se toca: ahi no se crea."
}

# usuario-pruebas <base> [carpeta]: crea o deja al dia el administrador de pruebas en los WordPress y
# la tienda PrestaShop de la base. Dice A|wp|usuario|contraseña y/o A|ps|... por cada uno (para la
# ventana); sale con 1 si no hay ninguno. La carpeta (o la recordada para la base) solo hace falta en
# PrestaShop 1.6, por su _COOKIE_KEY_. Si en la base hay un usuario de verdad (sin la marca de Nexum)
# con ese correo, no se toca: se avisa y ahi no hay administrador de pruebas
function test_admin() {
    local db=$1 folder=$2 p sql cols col exprs hash src key done_any=1 res any=0 md5
    if ! [[ "$db" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$ ]]; then
        echo "Base no valida: $db"
        return 1
    fi
    [ -z "$folder" ] && folder=$(linked_folder "$db" "${DB_TARGET_FOLDER:-}")
    [[ "$folder" =~ ^[A-Za-z0-9_][A-Za-z0-9\ ._-]*$ ]] && [ -d "$HTDOCS_DIR/$folder" ] || folder=""
    # (el cliente de root de la version o, con DB_ROOT_CLIENT, otro: el de la MariaDB de un contenedor)
    local mysql=(db_root_sql -N --default-character-set=utf8mb4)
    test_admin_load
    # (el correo va en las consultas: solo uno que vale, sin comillas; la contraseña, solo su huella)
    local mail=$TEST_ADMIN_USER pass=$TEST_ADMIN_PASS
    test_admin_mail_ok "$mail" && test_admin_pass_ok "$pass" || { mail=local@local.test pass=local; }
    [ "$mail" == local@local.test ] && any=1
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] administrador de pruebas $mail en $db"
        return 0
    fi
    md5=$(printf '%s' "$pass" | test_admin_md5)
    [[ "$md5" =~ ^[0-9a-f]{32}$ ]] || { echo "No se puede hacer la huella de la contraseña (python3)"; return 1; }
    # (solo tablas de verdad: una vista del volcado ejecutaria sus funciones como root)
    function has_table() {
        [ "$("${mysql[@]}" -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$db' AND TABLE_NAME='$1' AND TABLE_TYPE='BASE TABLE'" < /dev/null 2> /dev/null)" == 1 ]
    }

    # WordPress (todos los de la base): usuario con rol de administrador. El suyo es el que tiene ese
    # usuario y la marca (local@local.test, con o sin ella); si hay otro con ese usuario o ese correo,
    # es de verdad: no se toca
    for p in $(wp_table_prefixes "$db"); do
        has_table "${p}usermeta" || continue
        sql=$(sed "s/@P@/$p/g" <<'SQL'
SET @mine := (SELECT ID FROM `@P@users` WHERE user_login = '@M@' AND (@ANY@ OR user_nicename = 'local-pruebas' OR display_name = 'Local (pruebas)') ORDER BY ID LIMIT 1);
SET @real := IF(@ANY@, NULL, (SELECT ID FROM `@P@users` WHERE (user_login = '@M@' OR user_email = '@M@') AND ID <> IFNULL(@mine, 0) ORDER BY ID LIMIT 1));
INSERT INTO `@P@users` (user_login, user_pass, user_nicename, user_email, user_url, user_registered, user_activation_key, user_status, display_name)
    SELECT '@M@', '@H@', 'local-pruebas', '@M@', '', NOW(), '', 0, 'Local (pruebas)' FROM DUAL WHERE @mine IS NULL AND @real IS NULL;
SET @id := IF(@real IS NULL, IFNULL(@mine, LAST_INSERT_ID()), NULL);
UPDATE `@P@users` SET user_pass = '@H@', user_activation_key = '' WHERE ID = @id;
DELETE FROM `@P@usermeta` WHERE user_id = @id AND meta_key IN ('@P@capabilities', '@P@user_level');
INSERT INTO `@P@usermeta` (user_id, meta_key, meta_value) SELECT @id, '@P@capabilities', 'a:1:{s:13:"administrator";b:1;}' FROM DUAL WHERE @id > 0;
INSERT INTO `@P@usermeta` (user_id, meta_key, meta_value) SELECT @id, '@P@user_level', '10' FROM DUAL WHERE @id > 0;
SELECT CONCAT(CAST(IFNULL(@id, 0) AS UNSIGNED), '|', @real IS NOT NULL);
SQL
)
        sql=${sql//@M@/$mail} sql=${sql//@H@/$md5} sql=${sql//@ANY@/$any}
        res=$("${mysql[@]}" "$db" -e "$sql" < /dev/null 2> /dev/null | tail -1)
        if [ "${res#*|}" == 1 ]; then
            echo "Aviso: el WordPress de $db (tablas ${p}) ya tiene un usuario de verdad con $mail: no se cambia ni se crea el de pruebas. Elige otro correo en Configuracion > Administrador de pruebas."
        elif [ "${res%%|*}" -gt 0 ] 2> /dev/null; then
            echo "A|wp|$mail|$pass"
            done_any=0
        fi
    done

    # PrestaShop: una copia del primer SuperAdmin (mismas columnas, sea cual sea la version) con el
    # correo y la contraseña de pruebas, en todas las tiendas. El suyo lleva firstname Pruebas y
    # lastname Local (local@local.test, con o sin ellos); otro con ese correo es de verdad: no se toca
    p=$(ps_table_prefix "$db")
    # (ps_table_prefix no da nada si la tienda no lleva prefijo)
    if has_table "${p}employee" && has_table "${p}employee_shop" && has_table "${p}shop" && has_table "${p}shop_url"; then
        src=$("${mysql[@]}" "$db" -e "SELECT passwd FROM \`${p}employee\` WHERE id_profile = 1 ORDER BY active DESC, id_employee LIMIT 1" < /dev/null 2> /dev/null)
        if [[ "$src" == '$'* ]]; then
            hash=$TEST_ADMIN_HASH
            [ -z "$hash" ] && hash=$(LVM_ADMIN_CLAVE=$pass test_admin_bcrypt)
            [[ "$hash" =~ ^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$ ]] || hash=""
        elif [ -n "$src" ]; then
            # PrestaShop 1.6: md5(_COOKIE_KEY_ + contraseña), con la clave de su settings.inc.php
            key=""
            [ -n "$folder" ] && key=$(python3 -I - "$HTDOCS_DIR/$folder/config/settings.inc.php" <<'EOF'
import re, sys
try:
    text = open(sys.argv[1], errors="replace").read(1000000)
except OSError:
    sys.exit(0)
m = re.search(r"""define\(\s*['"]_COOKIE_KEY_['"]\s*,\s*['"]([A-Za-z0-9]+)['"]""", text)
print(m.group(1) if m else "")
EOF
)
            [ -n "$key" ] && hash=$(printf '%s%s' "$key" "$pass" | test_admin_md5)
            [[ "$hash" =~ ^[0-9a-f]{32}$ ]] || hash=""
        fi
        cols=$("${mysql[@]}" -e "SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$db' AND TABLE_NAME='${p}employee' ORDER BY ORDINAL_POSITION" < /dev/null 2> /dev/null)
        if [ -z "$hash" ]; then
            [ -n "$src" ] && echo "Aviso: no se sabe la _COOKIE_KEY_ de la tienda (PrestaShop 1.6): sin administrador de pruebas. Cargala con su carpeta (Cargar proyecto)."
        elif [ -n "$cols" ] && ! grep -qvE '^[A-Za-z0-9_]+$' <<< "$cols"; then
            local list="" sel=""
            for col in $cols; do
                case $col in
                    id_employee) continue ;;
                    email) exprs="'$mail'" ;;
                    passwd) exprs="'$hash'" ;;
                    firstname) exprs="'Pruebas'" ;;
                    lastname) exprs="'Local'" ;;
                    active|id_profile) exprs=1 ;;
                    last_passwd_gen) exprs="NOW()" ;;
                    reset_password_token|reset_password_validity) exprs=NULL ;;
                    *) exprs="\`$col\`" ;;
                esac
                list+="${list:+, }\`$col\`" sel+="${sel:+, }$exprs"
            done
            sql="SET @src := (SELECT id_employee FROM \`${p}employee\` WHERE id_profile = 1 ORDER BY active DESC, id_employee LIMIT 1);
SET @mine := (SELECT id_employee FROM \`${p}employee\` WHERE email = '$mail' AND ($any OR (firstname = 'Pruebas' AND lastname = 'Local')) ORDER BY id_employee LIMIT 1);
SET @real := IF($any, NULL, (SELECT id_employee FROM \`${p}employee\` WHERE email = '$mail' AND id_employee <> IFNULL(@mine, 0) ORDER BY id_employee LIMIT 1));
INSERT INTO \`${p}employee\` ($list) SELECT $sel FROM \`${p}employee\` WHERE id_employee = @src AND @mine IS NULL AND @real IS NULL;
SET @id := IF(@real IS NULL, IFNULL(@mine, LAST_INSERT_ID()), NULL);
UPDATE \`${p}employee\` SET passwd = '$hash', active = 1, id_profile = 1 WHERE id_employee = @id AND @src IS NOT NULL;
INSERT IGNORE INTO \`${p}employee_shop\` (id_employee, id_shop) SELECT @id, id_shop FROM \`${p}shop\` WHERE @id > 0 AND @src IS NOT NULL;
SELECT CONCAT(CAST(IF(@src IS NULL, 0, IFNULL(@id, 0)) AS UNSIGNED), '|', @real IS NOT NULL);"
            res=$("${mysql[@]}" "$db" -e "$sql" < /dev/null 2> /dev/null | tail -1)
            if [ "${res#*|}" == 1 ]; then
                echo "Aviso: la tienda de $db ya tiene un empleado de verdad con $mail: no se cambia ni se crea el de pruebas. Elige otro correo en Configuracion > Administrador de pruebas."
            elif [ "${res%%|*}" -gt 0 ] 2> /dev/null; then
                echo "A|ps|$mail|$pass"
                done_any=0
            fi
        fi
    fi
    unset -f has_table
    return $done_any
}

# Tablas del administrador de pruebas en una base (para exportar-bd): deja en skip los --ignore-table
# del volcado de siempre y en only/wheres cada tabla con su condicion (sin las filas del administrador
# de pruebas: las de local@local.test, como siempre, y las que llevan la marca de Nexum con un correo
# de los que ha usado, el de ahora o uno de antes; una cuenta de verdad con ese correo, sin la marca, si
# va). Solo las tablas de verdad que lo tienen. Usa query (el cliente de la base)
function test_admin_filter() {
    local db=$1 t c p n m in="" wp ps
    local -A cols=()
    test_admin_load
    for m in "${TEST_ADMIN_MAILS[@]}"; do
        test_admin_mail_ok "$m" && in+="${in:+, }'$m'"
    done
    wp="IFNULL(user_login IN ($in) AND (user_login = 'local@local.test' OR user_nicename = 'local-pruebas' OR display_name = 'Local (pruebas)'), 0)"
    ps="IFNULL(email IN ($in) AND (email = 'local@local.test' OR (firstname = 'Pruebas' AND lastname = 'Local')), 0)"
    while IFS=$'\t' read -r t c; do
        [[ "$t" =~ ^[A-Za-z0-9_]+$ ]] && cols[$t]=$c
    done < <("${query[@]}" -e "SELECT c.TABLE_NAME, c.COLUMN_NAME FROM information_schema.COLUMNS c
        JOIN information_schema.TABLES t ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME
        WHERE c.TABLE_SCHEMA = '$db' AND t.TABLE_TYPE = 'BASE TABLE' AND (
            (c.TABLE_NAME LIKE '%users' AND c.COLUMN_NAME = 'user_login')
            OR (c.TABLE_NAME LIKE '%employee' AND c.COLUMN_NAME = 'email'))" < /dev/null 2> /dev/null)
    for t in "${!cols[@]}"; do
        if [ "${cols[$t]}" == user_login ]; then
            p=${t%users}
            n=$("${query[@]}" "$db" -e "SELECT COUNT(*) FROM \`$t\` WHERE $wp" < /dev/null 2> /dev/null)
            [ "${n:-0}" -gt 0 ] 2> /dev/null || continue
            skip+=(--ignore-table="$db.$t") only+=("$t") wheres+=("NOT $wp")
            if [ "$("${query[@]}" -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$db' AND TABLE_NAME = '${p}usermeta' AND TABLE_TYPE = 'BASE TABLE'" < /dev/null 2> /dev/null)" == 1 ]; then
                skip+=(--ignore-table="$db.${p}usermeta") only+=("${p}usermeta")
                wheres+=("user_id IS NULL OR user_id NOT IN (SELECT ID FROM \`$t\` WHERE $wp)")
            fi
        else
            p=${t%employee}
            n=$("${query[@]}" "$db" -e "SELECT COUNT(*) FROM \`$t\` WHERE $ps" < /dev/null 2> /dev/null)
            [ "${n:-0}" -gt 0 ] 2> /dev/null || continue
            skip+=(--ignore-table="$db.$t") only+=("$t") wheres+=("NOT $ps")
            if [ "$("${query[@]}" -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$db' AND TABLE_NAME = '${p}employee_shop' AND TABLE_TYPE = 'BASE TABLE'" < /dev/null 2> /dev/null)" == 1 ]; then
                skip+=(--ignore-table="$db.${p}employee_shop") only+=("${p}employee_shop")
                wheres+=("id_employee IS NULL OR id_employee NOT IN (SELECT id_employee FROM \`$t\` WHERE $ps)")
            fi
        fi
    done
    return 0
}
