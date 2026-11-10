#!/bin/bash
# Actualizar proyecto (Linux 1.56.27, Mac 1.40.9): el codigo de produccion (.zip, .tar.gz o carpeta) en
# un proyecto, fusionando o sobrescribiendo, sin salir de su carpeta, sin tocar .git y con lo sustituido
# en las copias; y el orden de los pasos. Uso: actualizar-proyecto.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q "^function project_update()" "$SRC" || { echo "  ok    (sin Actualizar proyecto)"; exit 0; }
W=$(mktemp -d "$TMPBASE/actualizar.XXXXXX") || exit 1
trap 'rm -rf "${W:?}"' EXIT
CODE=$( eval "$(sed -n "/^PROJECT_CODE_PY='/,/^'\$/p" "$SRC")"; printf '%s' "$PROJECT_CODE_PY" )
P=$W/htdocs/proyecto
fresh() {
    rm -rf "${W:?}/htdocs" "${W:?}/copias" "${W:?}/tmp"
    mkdir -p "$P/.git/refs" "$P/wp-content/uploads" "$P/antiguo"
    echo repo > "$P/.git/config"
    echo viejo > "$P/index.php"
    echo igual > "$P/igual.txt"
    echo foto > "$P/wp-content/uploads/foto.jpg"
    echo fuera > "$P/antiguo/solo-aqui.php"
}
go() { python3 -I -c "$CODE" "$P" "$1" "$2" "$W/copias" "$W/tmp" "${3:-0}" 2>&1; }

# Un paquete normal, dentro de public_html
mkdir -p "$W/src/public_html/wp-content"
echo nuevo > "$W/src/public_html/index.php"
echo igual > "$W/src/public_html/igual.txt"
echo tema > "$W/src/public_html/wp-content/tema.php"
printf '#!/bin/sh\n' > "$W/src/public_html/run.sh"; chmod 755 "$W/src/public_html/run.sh"
(cd "$W/src" && python3 -I -m zipfile -c "$W/normal.zip" public_html > /dev/null && tar czf "$W/normal.tgz" public_html)

fresh; out=$(go "$W/normal.zip" fusionar); rc=$?
check "fusionar (.zip): copia lo que trae, de dentro de public_html" '[ $rc -eq 0 ] && [ "$(cat "$P/index.php")" == nuevo ] && [ "$(cat "$P/wp-content/tema.php")" == tema ] && [ ! -e "$P/public_html" ]'
check "fusionar: deja lo que no trae y .git" '[ -f "$P/antiguo/solo-aqui.php" ] && [ -f "$P/wp-content/uploads/foto.jpg" ] && [ "$(cat "$P/.git/config")" == repo ]'
check "lo sustituido queda en las copias; lo igual ni se copia" '[ "$(cat "$W/copias/index.php")" == viejo ] && [ ! -e "$W/copias/igual.txt" ] && grep -q "1 iguales" <<< "$out" && grep -q "Lo que se ha sustituido o quitado esta en" <<< "$out"'
check "no quedan ficheros a medias ni el temporal" '[ -z "$(find "$P" -name ".lvm-parte-*")" ] && [ -z "$(ls -A "$W/tmp")" ]'

fresh; out=$(go "$W/normal.tgz" sobrescribir); rc=$?
check "sobrescribir (.tar.gz): quita lo que no trae, a las copias" '[ $rc -eq 0 ] && [ ! -e "$P/antiguo" ] && [ ! -e "$P/wp-content/uploads" ] && [ -f "$W/copias/antiguo/solo-aqui.php" ] && [ -f "$W/copias/wp-content/uploads/foto.jpg" ]'
check "sobrescribir: .git no se toca" '[ "$(cat "$P/.git/config")" == repo ] && [ ! -e "$W/copias/.git" ]'
check "sobrescribir: lo que trae se queda" '[ "$(cat "$P/index.php")" == nuevo ] && [ "$(cat "$P/igual.txt")" == igual ] && [ -x "$P/run.sh" ]'

# Sin carpeta de copias (sin --copia): lo sustituido o quitado se borra, y se dice
fresh; out=$(python3 -I -c "$CODE" "$P" "$W/normal.tgz" sobrescribir "" "$W/tmp" 0 2>&1); rc=$?
check "sin --copia: sustituye y quita sin guardar nada, y lo dice" '[ $rc -eq 0 ] && [ "$(cat "$P/index.php")" == nuevo ] && [ ! -e "$P/antiguo" ] && [ ! -e "$W/copias" ] && [ -z "$(find "$W" -name solo-aqui.php)" ] && grep -q "Sin copia" <<< "$out" && ! grep -q "Lo que se ha sustituido" <<< "$out"'
check "sin --copia: .git no se toca" '[ "$(cat "$P/.git/config")" == repo ]'

# Simulacion: no cambia nada
fresh; out=$(go "$W/normal.zip" sobrescribir 1); rc=$?
check "simulacion: dice lo que haria y no cambia nada" '[ $rc -eq 0 ] && grep -q "^\[simulacion\] " <<< "$out" && [ "$(cat "$P/index.php")" == viejo ] && [ -f "$P/antiguo/solo-aqui.php" ] && [ ! -e "$W/copias" ]'

# Paquetes con mala intencion
ABS=$W/absoluto-lvm-prueba.txt
python3 -I - "$W/malo.zip" "$ABS" <<'EOF'
import stat, sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("bien.php", "bien")
    z.writestr("../../fuera-zip.txt", "x")
    z.writestr(sys.argv[2], "x")
    i = zipfile.ZipInfo("enlace"); i.external_attr = (stat.S_IFLNK | 0o777) << 16
    z.writestr(i, "/etc/passwd")
EOF
fresh; out=$(go "$W/malo.zip" fusionar)
check "zip: .. y rutas absolutas no salen de la carpeta; los enlaces no se crean" '[ -f "$P/bien.php" ] && [ ! -e "$W/fuera-zip.txt" ] && [ ! -e "$W/htdocs/fuera-zip.txt" ] && [ ! -e "$ABS" ] && [ ! -L "$P/enlace" ] && [ ! -e "$P/enlace" ] && grep -q "no se han copiado" <<< "$out"'
python3 -I - "$W/malo.tar" "$W" <<'EOF'
import io, sys, tarfile
with tarfile.open(sys.argv[1], "w") as t:
    def add(name, data=b"x", kind=tarfile.REGTYPE, link=""):
        i = tarfile.TarInfo(name); i.type = kind; i.linkname = link; i.size = len(data) if kind == tarfile.REGTYPE else 0
        t.addfile(i, io.BytesIO(data) if kind == tarfile.REGTYPE else None)
    add("bien.php")
    add("../../fuera-tar.txt")
    add("sale", kind=tarfile.SYMTYPE, link=sys.argv[2])
    add("sale/por-enlace.txt")
    add("duro", kind=tarfile.LNKTYPE, link="/etc/passwd")
    add("nodo", kind=tarfile.CHRTYPE)
EOF
fresh; out=$(go "$W/malo.tar" fusionar)
check "tar: ni .., ni enlaces, ni enlaces duros, ni dispositivos" '[ -f "$P/bien.php" ] && [ ! -e "$W/fuera-tar.txt" ] && [ ! -e "$W/por-enlace.txt" ] && [ ! -L "$P/sale" ] && [ ! -e "$P/duro" ] && [ ! -e "$P/nodo" ]'

# Un enlace en el proyecto no se sigue
mkdir -p "$W/externo" "$W/src2/wp-content"; echo a > "$W/src2/wp-content/nuevo.php"; echo secreto > "$W/externo/dato"
fresh; rm -rf "${P:?}/wp-content"; ln -s "$W/externo" "$P/wp-content"
out=$(go "$W/src2" fusionar)
check "un enlace del proyecto no se sigue: se aparta y no se escribe fuera" '[ ! -L "$P/wp-content" ] && [ -f "$P/wp-content/nuevo.php" ] && [ ! -e "$W/externo/nuevo.php" ] && [ -L "$W/copias/wp-content" ] && [ "$(cat "$W/externo/dato")" == secreto ]'
fresh; rm -f "${P:?}/index.php"; ln -s "$W/externo/dato" "$P/index.php"; mkdir -p "$W/src3"; echo pisa > "$W/src3/index.php"
go "$W/src3" fusionar > /dev/null
check "un fichero enlazado del proyecto tampoco: el de fuera no se cambia" '[ "$(cat "$W/externo/dato")" == secreto ] && [ ! -L "$P/index.php" ] && [ "$(cat "$P/index.php")" == pisa ]'
# Enlaces en una carpeta elegida: no se copian
mkdir -p "$W/src4"; echo a > "$W/src4/a.php"; ln -s /etc/passwd "$W/src4/enlace"
fresh; out=$(go "$W/src4" fusionar)
check "carpeta elegida: sus enlaces no se copian" '[ -f "$P/a.php" ] && [ ! -e "$P/enlace" ] && [ ! -L "$P/enlace" ]'
# La carpeta de wp-content sola va en su sitio (no se confunde con public_html)
mkdir -p "$W/src5/wp-content"; echo a > "$W/src5/wp-content/solo.php"
fresh; go "$W/src5" fusionar > /dev/null
check "un paquete solo con wp-content va en su sitio" '[ -f "$P/wp-content/solo.php" ] && [ ! -e "$P/solo.php" ]'
# Lo que no sirve
fresh; echo nada > "$W/no.txt"; out=$(go "$W/no.txt" sobrescribir); rc=$?
check "un fichero que no es un paquete: lo dice y no toca nada" '[ $rc -ne 0 ] && grep -q "no es un .zip" <<< "$out" && [ -f "$P/antiguo/solo-aqui.php" ]'
mkdir -p "$W/vacia"; fresh; out=$(go "$W/vacia" sobrescribir); rc=$?
check "una carpeta vacia con sobrescribir: no borra el proyecto" '[ $rc -ne 0 ] && grep -q "No trae ningun fichero" <<< "$out" && [ -f "$P/index.php" ]'
fresh; out=$(go "$P/antiguo" sobrescribir); rc=$?
check "una carpeta dentro del proyecto: no se admite" '[ $rc -ne 0 ] && grep -q "se solapan" <<< "$out" && [ -f "$P/index.php" ]'
fresh; out=$(go "$W/htdocs" fusionar); rc=$?
check "una carpeta que contiene el proyecto: tampoco" '[ $rc -ne 0 ] && grep -q "se solapan" <<< "$out"'
python3 -I - "$W/clave.zip" <<'EOF'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("a.php", "x")
data = bytearray(open(sys.argv[1], "rb").read())
# (el bit de cifrado, en la cabecera local y en la central)
for sig, off in ((b"PK\x03\x04", 6), (b"PK\x01\x02", 8)):
    i = data.find(sig)
    data[i + off] |= 1
open(sys.argv[1], "wb").write(data)
EOF
fresh; out=$(go "$W/clave.zip" fusionar); rc=$?
check "zip con contraseña: lo dice" '[ $rc -ne 0 ] && grep -q "lleva contraseña" <<< "$out"'
# Un fichero que no se puede sustituir: se dice y sale con error
if [ "$(id -u)" != 0 ]; then
    fresh; mkdir -p "$P/cerrada" "$W/src6/cerrada"; echo nuevo > "$W/src6/cerrada/x"; echo old > "$P/cerrada/x"; chmod 555 "$P/cerrada"
    out=$(go "$W/src6" fusionar); rc=$?
    chmod 755 "$P/cerrada"
    check "sin permiso: lo dice, sale con error y lo de antes sigue" '[ $rc -ne 0 ] && grep -q "No se han podido copiar o quitar 1" <<< "$out" && [ "$(cat "$P/cerrada/x")" == old ]'
fi

# El orden de los pasos, y que un fallo pare los siguientes
extract "$SRC" project_update gui_project_git project_config_db project_config_local || exit 1
PROJECT_CODE_PY=$CODE
HTDOCS_DIR=$W/htdocs HOME=$W/casa COPIES_DIR=$W/casa/nexum-backups DRY=0 SUDO="" GIT_KNOWN_HOSTS=x
mkdir -p "$HOME"
valid_project() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }
db_valid_name() { [[ "$1" =~ ^[a-z_]+$ ]]; }
db_connect() { echo connect >> "$W/orden"; }
repo_clones() { echo "empresa/proyecto proyecto"; }
repo_pull() { echo "pull $2" >> "$W/orden"; return ${PULL_RC:-0}; }
htdocs_close_world() { echo cierra >> "$W/orden"; }
import_database() { echo "bd $*" >> "$W/orden"; return ${BD_RC:-0}; }
saved_project_db() { echo guardada; }
load_project() { echo "carga $*" >> "$W/orden"; }
is_prestashop() { [ -n "$ES_PS" ]; }
is_wordpress() { [ -n "$ES_WP" ]; }
ps_config() { echo "${PS_BD}|ps_"; }
wp_config_read() { sed -n "s/.*DB_NAME', '\([^']*\)'.*/\1/p" "$1"; }
wp_config_has_url() { grep -q "WP_HOME', '$2'" "$1"; }
wp_local_url() { echo https://web.local; }
echo "SELECT 1;" > "$W/d.sql"
fresh; : > "$W/orden"; out=$(project_update proyecto --codigo "$W/normal.zip" --modo fusionar --pull --bd "$W/d.sql" --base wp_x); rc=$?
check "pasos: pull, codigo, BBDD (protegida, de este proyecto) y volver a cargar" '[ $rc -eq 0 ] && [ "$(grep -v connect "$W/orden" | cut -d" " -f1 | tr "\n" " ")" == "pull cierra bd carga " ] && grep -q "bd $W/d.sql wp_x --crear --proyecto proyecto" "$W/orden" && grep -q "carga proyecto  wp_x" "$W/orden" && [ "$(cat "$P/index.php")" == nuevo ] && [ ! -e "$COPIES_DIR" ] && grep -q "Sin copia" <<< "$out"'
check "pull por SSH de su repositorio" 'grep -q "pull git@github.com:empresa/proyecto.git" "$W/orden"'
fresh; : > "$W/orden"; out=$(project_update proyecto --codigo "$W/normal.zip" --modo fusionar --bd "$W/d.sql" --base wp_x --copia); rc=$?
check "con --copia: lo sustituido en ~/nexum-backups y la BBDD se carga con --copia" '[ $rc -eq 0 ] && [ "$(cat "$COPIES_DIR"/proyecto-antes-de-actualizar-*/index.php)" == viejo ] && grep -q "bd $W/d.sql wp_x --crear --proyecto proyecto --copia" "$W/orden"'
fresh; : > "$W/orden"; out=$(PULL_RC=1 project_update proyecto --codigo "$W/normal.zip" --pull --bd "$W/d.sql" --base wp_x); rc=$?
check "si el pull falla, no se copia ni se carga nada" '[ $rc -ne 0 ] && [ "$(cat "$P/index.php")" == viejo ] && ! grep -qE "^(bd|carga)" "$W/orden" && grep -q "No se ha copiado" <<< "$out"'
fresh; : > "$W/orden"; out=$(BD_RC=1 project_update proyecto --bd "$W/d.sql" --base wp_x); rc=$?
check "si la BBDD falla, no se vuelve a cargar" '[ $rc -ne 0 ] && ! grep -q "^carga" "$W/orden"'
fresh; : > "$W/orden"; out=$(project_update proyecto --codigo "$W/no.txt" --bd "$W/d.sql" --base wp_x); rc=$?
check "si el codigo falla, no se carga la BBDD" '[ $rc -ne 0 ] && ! grep -qE "^(bd|carga)" "$W/orden"'
fresh; : > "$W/orden"; out=$(project_update proyecto --codigo "$W/normal.zip"); rc=$?
check "solo el codigo: sin pull si no se pide, y vuelve a cargarlo con su base de siempre" '[ $rc -eq 0 ] && ! grep -q "^pull" "$W/orden" && grep -q "carga proyecto  guardada" "$W/orden"'
fresh; : > "$W/orden"; out=$(DRY=1 project_update proyecto --codigo "$W/normal.zip" --pull); rc=$?
check "simulacion: ni pull ni cambios" '! grep -q "^pull" "$W/orden" && [ "$(cat "$P/index.php")" == viejo ] && grep -q "simulacion" <<< "$out"'
# Las tres formas: la BBDD, el codigo o las dos
fresh; : > "$W/orden"; out=$(project_update proyecto --bd "$W/d.sql" --base wp_x); rc=$?
check "solo la BBDD: se importa y la carpeta no se toca" '[ $rc -eq 0 ] && grep -q "^bd " "$W/orden" && ! grep -qE "^(pull|cierra)" "$W/orden" && [ "$(cat "$P/index.php")" == viejo ] && [ -f "$P/antiguo/solo-aqui.php" ] && grep -q "carga proyecto  wp_x" "$W/orden"'
fresh; : > "$W/orden"; out=$(project_update proyecto --codigo "$W/normal.zip" --base wp_x); rc=$?
check "solo el codigo: la BBDD no se toca (ni se importa ni se conecta) y sigue siendo la misma" '[ $rc -eq 0 ] && ! grep -qE "^(bd|connect)" "$W/orden" && [ "$(cat "$P/index.php")" == nuevo ] && grep -q "carga proyecto  wp_x" "$W/orden"'
fresh; : > "$W/orden"; out=$(project_update proyecto --codigo "$W/normal.zip" --bd "$W/d.sql" --base wp_x); rc=$?
check "la BBDD y el codigo: los dos" '[ $rc -eq 0 ] && grep -q "^bd " "$W/orden" && [ "$(cat "$P/index.php")" == nuevo ]'
# Solo el codigo: la BBDD se sabe aunque el de produccion pise la configuracion
saved_project_db() { :; }
mkdir -p "$W/prod"; printf "<?php define('DB_NAME', 'bd_produccion');\n" > "$W/prod/wp-config.php"
fresh; : > "$W/orden"; printf "<?php define('DB_NAME', 'bd_local'); define('WP_HOME', 'https://web.local');\n" > "$P/wp-config.php"
out=$(ES_WP=1 project_update proyecto --codigo "$W/prod"); rc=$?
check "solo el codigo y sin base asociada: se vuelve a cargar con la que usaba antes de copiar, no con la de produccion" 'grep -q "carga proyecto  bd_local" "$W/orden" && grep -q bd_produccion "$P/wp-config.php"'
check "si tras cargarlo el wp-config.php sigue con lo de produccion: lo dice y sale con error" '[ $rc -ne 0 ] && grep -q "usa la BBDD bd_produccion y tendría que usar bd_local" <<< "$out" && ! grep -q "Proyecto actualizado" <<< "$out"'
# La ventana le dice cual es
fresh; : > "$W/orden"; out=$(project_update proyecto --codigo "$W/prod" --base wp_x)
check "--base sin --bd: se vuelve a cargar con ella, sin importar nada" 'grep -q "carga proyecto  wp_x" "$W/orden" && ! grep -q "^bd" "$W/orden"'
# Cuando lo corrige al cargar, acaba bien
load_project() { printf "<?php define('DB_NAME', '%s'); define('WP_HOME', 'https://web.local');\n" "$3" > "$HTDOCS_DIR/$1/wp-config.php"; }
fresh; printf "<?php define('DB_NAME', 'bd_local');\n" > "$P/wp-config.php"
out=$(ES_WP=1 project_update proyecto --codigo "$W/prod"); rc=$?
check "WordPress: con el wp-config.php corregido al cargarlo, acaba bien, sin recargar a mano" '[ $rc -eq 0 ] && grep -q "Proyecto actualizado" <<< "$out" && grep -q bd_local "$P/wp-config.php"'
load_project() { :; }
mkdir -p "$W/prod2"; printf "<?php define('DB_NAME', 'bd_local');\n" > "$W/prod2/wp-config.php"
fresh; out=$(ES_WP=1 project_update proyecto --codigo "$W/prod2" --base bd_local); rc=$?
check "WordPress: sin la direccion local (WP_HOME), tambien lo dice" '[ $rc -ne 0 ] && grep -q "no lleva WP_SITEURL y WP_HOME" <<< "$out"'
fresh; out=$(ES_PS=1 PS_BD=otra project_update proyecto --codigo "$W/prod" --base bd_local); rc=$?
check "PrestaShop: con parameters.php en otra BBDD, lo dice" '[ $rc -ne 0 ] && grep -q "usa la BBDD otra y tendría que usar bd_local" <<< "$out"'
fresh; out=$(ES_PS=1 PS_BD=bd_local project_update proyecto --codigo "$W/prod" --base bd_local); rc=$?
check "PrestaShop: con parameters.php en su BBDD, acaba bien" '[ $rc -eq 0 ] && grep -q "Proyecto actualizado" <<< "$out"'
load_project() { echo "carga $*" >> "$W/orden"; }
saved_project_db() { echo guardada; }
unset -f wp_config_read wp_config_has_url

# El wp_config de verdad sobre un wp-config.php de produccion: queda con la base y la direccion locales
(
    extract "$SRC" wp_config wp_config_read wp_config_has_url project_write || exit 1
    WP_CONFIG_DIR=$W/wpc DB_SAFE=() DB_CLIENT=true DRY=0
    mkdir -p "$WP_CONFIG_DIR"
    project_path_ok() { return 0; }
    run() { "$@"; }
    saved_project_db() { echo bd_local; }
    db_exists() { return 0; }
    db_login_ok() { [ "$1" == root ]; }
    wp_table_prefixes() { echo wp_; }
    wp_local_url() { echo https://web.local; }
    is_prestashop() { return 1; }
    is_wordpress() { return 0; }
    fresh
    cat > "$P/wp-config.php" << 'EOF'
<?php
define('DB_NAME', 'bd_produccion');
define('DB_USER', 'usuario_prod');
define('DB_PASSWORD', 'clave_prod');
define('DB_HOST', 'servidor.prod');
$table_prefix = 'wp_';
EOF
    wp_config proyecto bd_local > "$W/wp-config.log" 2>&1
    project_config_local proyecto bd_local > /dev/null \
        && [ "$(wp_config_read "$P/wp-config.php" | head -1)" == bd_local ] && ! grep -q clave_prod "$P/wp-config.php"
)
rc=$?
check "wp_config real: el de produccion queda en local, y project_config_local lo da por bueno" '[ $rc -eq 0 ]'
[ $rc -eq 0 ] || sed 's/^/        /' "$W/wp-config.log"
extract "$SRC" wp_config_read wp_config_has_url > /dev/null

for bad in "--modo otro --codigo $W/normal.zip" "" "--bd $W/d.sql --base mal;nombre" "--codigo $W/no-existe.zip"; do
    fresh; : > "$W/orden"; out=$(project_update proyecto $bad); rc=$?
    check "no se admite: [${bad//$W\//}]" '[ $rc -ne 0 ] && [ "$(cat "$P/index.php")" == viejo ] && ! grep -qE "^(cierra|bd|carga)" "$W/orden"'
done
out=$(project_update "../fuera" --codigo "$W/normal.zip"); rc=$?
check "una carpeta que no es un proyecto: no" '[ $rc -ne 0 ]'
fresh; ln -s "$W/externo" "$W/htdocs/enlazado"; out=$(project_update enlazado --codigo "$W/normal.zip"); rc=$?
check "un proyecto que es un enlace: no" '[ $rc -ne 0 ] && [ ! -e "$W/externo/index.php" ]'

# Lo que se sabe del repositorio antes de copiar
fresh; rm -rf "${P:?}/.git"
check "gui-proyecto-git: sin repositorio" '[ "$(gui_project_git proyecto)" == "G|0||0|0|0" ]'
if command -v git > /dev/null; then
    git -C "$P" init -q
    git -C "$P" symbolic-ref HEAD refs/heads/principal
    git -C "$P" add index.php > /dev/null
    git -C "$P" -c user.name=a -c user.email=a@a commit -q -m uno
    echo cambio >> "$P/index.php"
    IFS='|' read -r g is branch dirty ahead origin <<< "$(gui_project_git proyecto)"
    check "gui-proyecto-git: rama y cambios sin commit, sin origin" '[ "$is" == 1 ] && [ "$branch" == principal ] && [ "$dirty" -ge 1 ] && [ "$origin" == 0 ]'
fi

# La ventana
if grep -q "LVM_SWIFT" "$SRC"; then
    check "Mac: el boton, en los del proyecto cargado" 'grep -q "(\"actualizar\", \"Actualizar\")" "$SRC" && grep -q "name: \"Actualizar\", icon: .logo(\"actualizar\")" "$SRC" && grep -q "tip: \"Actualizar proyecto\") {" "$SRC"'
    check "Mac: dialogo con sus dos zonas para arrastrar o elegir" 'grep -q "struct UpdateProjectSheet: View" "$SRC" && [ "$(grep -c "\.onDrop(of: \[UTType.fileURL\]" "$SRC")" -ge 1 ] && grep -q "func upPick(code: Bool, folder: Bool)" "$SRC" && grep -q "^import UniformTypeIdentifiers" "$SRC"'
    check "Mac: las zonas, altas y de otro color; al arrastrar, otro color y el borde azul" 'grep -q ".frame(minHeight: 112)" "$SRC" && grep -q ".stroke(over.wrappedValue || !path.isEmpty ? Color.blue : Color.primary.opacity(0.28)" "$SRC"'
    check "Mac: el nombre de la BBDD, como texto y en azul (campo solo si no tiene ninguna)" 'grep -q "Text(model.upDb).fontWeight(.bold).foregroundColor(.blue)" "$SRC" && grep -q "if model.upDbKnown {" "$SRC"'
    check "Mac: pregunta por el pull antes de copiar" 'grep -q "\"¿Hacer git pull antes de copiar?\"" "$SRC" && grep -q "\[\"gui-proyecto-git\", folder\]" "$SRC"'
    check "Mac: sin fichero de BBDD dice que se sigue usando la misma" 'grep -q "model.upSql.isEmpty ? \"Se sigue usando la BBDD\" : \"Se carga en la BBDD\"" "$SRC" && grep -q "let can = (!model.upSql.isEmpty || !model.upCode.isEmpty)" "$SRC"'
    check "Mac: tambien solo con el codigo le dice su BBDD" 'grep -q "if !db.isEmpty { args += \[\"--base\", db\] }" "$SRC"'
else
    check "Linux: el boton, en los del proyecto cargado" 'grep -q "(\"actualizar\", \"Actualizar\", (\"logo\", \"actualizar\"))" "$SRC" && grep -q "btns\[\"actualizar\"\] = nv_button(logo(\"actualizar\", 18), \"Actualizar\", \"Actualizar proyecto\"" "$SRC"'
    check "Linux: dialogo con sus dos zonas para arrastrar o elegir" 'grep -q "drag_dest_add_uri_targets()" "$SRC" && grep -q "connect(\"drag-data-received\"" "$SRC" && grep -q "def nv_update_project(self, x):" "$SRC"'
    check "Linux: las zonas, altas y de otro color; al arrastrar, otro color y el borde azul" 'grep -q "ev.set_size_request(-1, 112)" "$SRC" && grep -q "^.nv-zona { background-color: alpha(@theme_fg_color" "$SRC" && grep -q "^.nv-zona-lista { background-color: alpha(%(b)s, 0.10); border: 2px solid %(b)s; }" "$SRC" && grep -q "zone_ctx.add_class(\"nv-zona-lista\")" "$SRC" && grep -q "^.nv-zona:drop(active) { background-color: alpha(%(b)s, 0.30); border: 2px solid %(b)s" "$SRC"'
    check "Linux: el nombre de la BBDD, como texto y en azul (campo solo si no tiene ninguna)" 'grep -q "label(known_db, \"nv-bbdd\", selectable=True) if known_db else db_entry" "$SRC" && grep -q "^.nv-bbdd { color: mix(%(b)s" "$SRC"'
    check "Linux: pregunta por el pull antes de copiar" 'grep -q "\"¿Hacer git pull antes de copiar?\"" "$SRC" && grep -q "run_quick(\[\"gui-proyecto-git\", folder\], got)" "$SRC"'
    check "Linux: sin fichero de BBDD dice que se sigue usando la misma" 'grep -q "\"Se carga en la BBDD\" if state\[\"sql\"\] else \"Se sigue usando la BBDD\"" "$SRC" && grep -q "go.set_sensitive(bool(state\[\"sql\"\] or state\[\"code\"\])" "$SRC"'
    check "Linux: tambien solo con el codigo le dice su BBDD" 'grep -q "args += \[\"--base\", db\]" "$SRC"'
    check "Linux: el boton Log abre el error_log general de Apache" 'grep -q "^APACHE_ERROR_LOG = \"/opt/lampp/logs/error_log\"$" "$SRC" && grep -q "lambda \*_: self.show_log_tail(APACHE_ERROR_LOG), \"nv-proyecto-btn\"" "$SRC" && ! grep -q "loaded_project_log" "$SRC"'
fi
check "Importar imagenes: solo en WordPress y PrestaShop, en los dos visores" 'if grep -q "^let ERROR_LOG = " "$SRC"; then [ "$(grep -c "items\[\"imagenes\"\] = AnyView" "$SRC")" = 2 ] && grep -q "x.kind == \"wp\" || x.kind == \"ps\"" "$SRC" && grep -q "(\"imagenes\", \"Importar\")" "$SRC" && grep -q "tip: \"Importar imágenes de producción\") {" "$SRC" && grep -q "tip.hasPrefix(name) ? tip" "$SRC"; else [ "$(grep -c "btns\[\"imagenes\"\] = self.nv_images_button" "$SRC")" = 2 ] && grep -q "if x\[\"kind\"\] in (\"wp\", \"ps\"):" "$SRC" && grep -q "(\"imagenes\", \"Importar\", (\"logo\", \"imagenes\"))" "$SRC" && grep -q "\"Importar\", \"Importar imágenes de producción\"," "$SRC"; fi'
check "Los iconos de Reicon llevan su licencia MIT" 'grep -q "Copyright (c) 2025 REICON" "$SRC"'
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: el boton Log abre el error_log general de Apache" 'grep -q "^            model.showLogTail(ERROR_LOG)$" "$SRC" && grep -q "tip: hasLog ? \"Ver el log de Apache\"" "$SRC"'
fi
exit $fail
