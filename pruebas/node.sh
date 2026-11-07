#!/bin/bash
# Proyectos de Node (Linux 1.57.0, Mac 1.41.0): que proyectos se ven, que Node se elige, la descarga
# comprobada, arrancar y parar con todos sus hijos, y su pestaña. Con un Node y un npm falsos, sin red.
# Uso: node.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -q "^function node_start()" "$SRC" || { echo "  ok    (sin proyectos de Node)"; exit 0; }
W=$(mktemp -d "$TMPBASE/node.XXXXXX") || exit 1
trap 'kill_all; rm -rf "${W:?}"' EXIT
kill_all() {
    local f p
    for f in "$W"/h/.lvm-instalador/node/proyectos/*.conf; do
        [ -f "$f" ] || continue
        p=$(sed -n 's/^PID=//p' "$f")
        [[ "$p" =~ ^[0-9]+$ ]] && kill -KILL -- "-$p" 2> /dev/null
    done
}
extract "$SRC" node_lines gui_node node_find node_install node_pid node_free_port node_deps node_build_astro node_command node_start node_stop node_log
eval "$(sed -n "/^NODE_LIST_PY='/,/^'$/p" "$SRC")"
HOME=$W/h HTDOCS_DIR=$W/htdocs LOG_DIR=$HOME/.lvm-instalador NODE_DIR=$LOG_DIR/node NODE_RUN_DIR=$NODE_DIR/proyectos
NODE_DEFAULT_MAJOR=26 NODE_PORT_FROM=47321 NODE_PORT_TO=47399 DRY=0 TEST_DIR=$W/prueba LVM_NODE_BASE=""
TUNNEL_STATE=$W/tunel-estado NODE_CMD=()
mkdir -p "$HOME" "$HTDOCS_DIR" "$TEST_DIR"
valid_project() { [ -d "$HTDOCS_DIR/$1" ] && [[ "$1" != */* ]]; }
task_plan() { :; }
task_step() { :; }
tunnel_close() { rm -f "$TUNNEL_STATE"; echo cerrado >> "$W/tunel-cerrado"; }

pkg() { mkdir -p "$HTDOCS_DIR/$1"; printf '%s\n' "$2" > "$HTDOCS_DIR/$1/package.json"; }
pkg astro '{"dependencies":{"astro":"^7"},"engines":{"node":">=24.0.0"},"scripts":{"dev":"astro dev","build":"astro build"}}'
pkg siguiente '{"dependencies":{"next":"16"},"scripts":{"dev":"next dev","build":"next build","start":"next start"}}'
pkg vite '{"devDependencies":{"vite":"7"},"scripts":{"dev":"vite"}}'
pkg propio '{"scripts":{"start":"node server.js"}}'
pkg libreria '{"dependencies":{"lodash":"4"}}'
pkg wp '{"devDependencies":{"vite":"7"},"scripts":{"dev":"vite"}}'; : > "$HTDOCS_DIR/wp/wp-config.php"
pkg laravel '{"devDependencies":{"vite":"7"},"scripts":{"dev":"vite"}}'; : > "$HTDOCS_DIR/laravel/artisan"
pkg roto '{"scripts":'
pkg "a|b" '{"dependencies":{"vite":"7"}}'
ln -s "$HTDOCS_DIR/vite" "$HTDOCS_DIR/enlace"
echo 26 > "$HTDOCS_DIR/siguiente/.nvmrc"
L=$(gui_node)
check "se ve con su tipo y lo que pide" 'grep -qx "P|astro|Astro|parado|||24+|0|db" <<< "$L" && grep -qx "P|siguiente|Next|parado|||26|0|dbs" <<< "$L" && grep -qx "P|vite|Vite|parado||||0|d" <<< "$L" && grep -qx "P|propio|Node|parado||||0|s" <<< "$L"'
check "no se ven: librerias, webs de PHP, json roto, nombres raros ni enlaces" '! grep -qE "^P\|(libreria|wp|laravel|roto|a\|b|enlace)\|" <<< "$L"'

# --- Que Node se elige ---
fake_node() {
    local d=$1 v=$2
    mkdir -p "$d/bin"
    printf '#!/bin/bash\necho %s\n' "$v" > "$d/bin/node"
    # (npm falso: «run dev», «start» o «run build» sirven o compilan; los hijos, para comprobar que se paran)
    cat > "$d/bin/npm" << 'EOF'
#!/bin/bash
case "$1 $2" in
    "run dev"|"start "*)
        sleep 300 &
        exec python3 -I -m http.server --bind "$HOST" "$PORT" ;;
    "run build") echo compilado > "$PWD/compilado"; [ ! -f "$PWD/falla-build" ] ;;
    "ci "*|"install "*) mkdir -p "$PWD/node_modules"; echo "$*" >> "$PWD/npm.log" ;;
esac
EOF
    cp "$d/bin/npm" "$d/bin/npx"
    chmod +x "$d/bin/node" "$d/bin/npm" "$d/bin/npx"
}
PATH_OLD=$PATH
PATH=/usr/bin:/bin
hash -r
NVM=$HOME/.nvm/versions/node
fake_node "$NVM/v20.19.0" v20.19.0
fake_node "$NVM/v24.9.0" v24.9.0
fake_node "$NVM/v24.10.0" v24.10.0
fake_node "$NVM/v26.1.0" v26.1.0
check "exacta: la mas nueva de ese mayor" '[ "$(node_find 24)" == "$NVM/v24.10.0/bin" ]'
check "24+: la mas nueva de ahi en adelante" '[ "$(node_find 24+)" == "$NVM/v26.1.0/bin" ]'
check "sin nada pedido: la mas nueva" '[ "$(node_find "")" == "$NVM/v26.1.0/bin" ]'
check "si no hay ninguna que valga, nada" '[ -z "$(node_find 30)" ] && [ -z "$(node_find 27+)" ]'
fake_node "$NODE_DIR/v26.2.0" v26.2.0
check "la de Nexum cuenta igual" '[ "$(node_find 26)" == "$NODE_DIR/v26.2.0/bin" ]'
rm -rf "${NODE_DIR:?}/v26.2.0"

# --- Descarga comprobada ---
os=$(uname -s | tr 'A-Z' 'a-z')
case "$(uname -m)" in arm64|aarch64) arch=arm64 ;; *) arch=x64 ;; esac
web=$W/web/latest-v28.x
mkdir -p "$web" "$W/paquete/node-v28.1.2-$os-$arch/bin"
printf '#!/bin/bash\necho v28.1.2\n' > "$W/paquete/node-v28.1.2-$os-$arch/bin/node"
cp "$W/paquete/node-v28.1.2-$os-$arch/bin/node" "$W/paquete/node-v28.1.2-$os-$arch/bin/npm"
chmod +x "$W/paquete/node-v28.1.2-$os-$arch/bin/"*
tar -czf "$web/node-v28.1.2-$os-$arch.tar.gz" -C "$W/paquete" "node-v28.1.2-$os-$arch"
suma() { if command -v sha256sum > /dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
LVM_NODE_BASE=file://$W/web
printf '%s  otro-paquete.tar.gz\n%s  node-v28.1.2-%s-%s.tar.gz\n' "$(printf '0%.0s' {1..64})" "$(printf '0%.0s' {1..64})" "$os" "$arch" > "$web/SHASUMS256.txt"
out=$(node_install 28 2>&1); rc=$?
check "suma que no coincide: no se instala" '[ $rc -ne 0 ] && grep -q "no coincide" <<< "$out" && [ ! -e "$NODE_DIR/v28.1.2" ] && [ -z "$(ls -d "$NODE_DIR"/descarga.* 2> /dev/null)" ]'
printf '%s  node-v28.1.2-%s-%s.tar.gz\n' "$(suma "$web/node-v28.1.2-$os-$arch.tar.gz")" "$os" "$arch" > "$web/SHASUMS256.txt"
out=$(node_install 28 2>&1); rc=$?
check "suma buena: instalada, sin restos, y se encuentra" '[ $rc -eq 0 ] && [ -x "$NODE_DIR/v28.1.2/bin/node" ] && [ -z "$(ls -d "$NODE_DIR"/descarga.* 2> /dev/null)" ] && [ "$(node_find 28)" == "$NODE_DIR/v28.1.2/bin" ]'
out=$(node_install 'x; rm' 2>&1); check "una version rara no se usa" '[ $? -ne 0 ] || grep -q "no válida" <<< "$out"'
TD=$TEST_DIR; TEST_DIR=""; check "la direccion falsa solo vale en las pruebas" 'grep -q "\[ -n \"\$TEST_DIR\" \] && \[ -n \"\$LVM_NODE_BASE\" \]" "$SRC"'; TEST_DIR=$TD
rm -rf "${NODE_DIR:?}/v28.1.2"

# --- Arrancar y parar, de verdad ---
out=$(DRY=1 node_start propio 2>&1)
check "simulacion: no arranca nada" 'grep -q "\[simulacion\]" <<< "$out" && [ ! -e "$NODE_RUN_DIR/propio.conf" ]'
out=$(node_start noexiste 2>&1); check "carpeta que no existe" '[ $? -ne 0 ] || [ -z "$out" ]; [ ! -e "$NODE_RUN_DIR/noexiste.conf" ]'
out=$(node_start libreria 2>&1); rc=$?; check "lo que no es de Node no se arranca" '[ $rc -ne 0 ] && grep -q "no es un proyecto de Node" <<< "$out"'
out=$(node_start propio raro 2>&1); rc=$?; check "modo desconocido" '[ $rc -ne 0 ]'
out=$(node_start vite compilado 2>&1 < /dev/null); rc=$?
out=$(node_start propio 2>&1 < /dev/null); rc=$?
check "arranca y dice su direccion" '[ $rc -eq 0 ] && grep -qE "^URL\|http://127\.0\.0\.1:47[0-9]+$" <<< "$out"'
check "instala sus dependencias sin lock con npm install" 'grep -q "^install " "$HTDOCS_DIR/propio/npm.log"'
url=$(sed -n 's/^URL|//p' <<< "$out")
pid=$(node_pid propio)
check "responde y solo en 127.0.0.1" 'curl -s -o /dev/null --noproxy "*" --max-time 3 "$url/" && ! grep -qE "HOST=0" "$NODE_RUN_DIR/propio.conf"'
check "su estado y su registro solo tuyos" '[ "$(stat -c %a "$NODE_RUN_DIR/propio.log" 2> /dev/null || stat -f %Lp "$NODE_RUN_DIR/propio.log")" == 600 ] && [ "$(stat -c %a "$NODE_RUN_DIR/propio.conf" 2> /dev/null || stat -f %Lp "$NODE_RUN_DIR/propio.conf")" == 600 ]'
check "se ve en marcha, con su modo y direccion" 'gui_node | grep -qx "P|propio|Node|marcha|desarrollo|$url||1|s"'
check "en su propia sesion" '[ "$(ps -o sess= -p "$pid" 2> /dev/null | tr -d " ")" == "$pid" ]'
check "con la entrada a cero: no se queda con la terminal de la tarea" '[ "$(ls -l "/proc/$pid/fd/0" 2> /dev/null | grep -c /dev/null)" == 1 ] || [ ! -d /proc ]'
hijo=$(pgrep -s "$pid" sleep | head -1)
check "tiene un hijo (para comprobar que se para)" '[ -n "$hijo" ]'
out=$(node_start propio 2>&1 < /dev/null); rc=$?
url2=$(sed -n 's/^URL|//p' <<< "$out"); old=$pid; pid=$(node_pid propio)
check "arrancarlo otra vez cambia el servidor, no deja dos" '[ $rc -eq 0 ] && [ "$pid" != "$old" ] && ! kill -0 "$old" 2> /dev/null'
printf '{"target": "%s", "pid": 1}' "$url2" > "$TUNNEL_STATE"
out=$(node_stop propio 2>&1)
check "parar lo cierra con sus hijos" '! kill -0 "$pid" 2> /dev/null && [ -z "$(pgrep -s "$pid" 2> /dev/null)" ] && [ ! -e "$NODE_RUN_DIR/propio.conf" ]'
check "y cierra su tunel: el puerto podria ser de otro" '[ -s "$W/tunel-cerrado" ] && [ ! -e "$TUNNEL_STATE" ]'
out=$(node_stop propio 2>&1); check "parar lo parado no falla" '[ $? -eq 0 ] && grep -q "no está en marcha" <<< "$out"'

# Un pid que ya no es el suyo no se mata
sleep 300 & otro=$!
printf 'PID=%s\nLSTART=otra hora\nPORT=47399\nMODE=desarrollo\n' "$otro" > "$NODE_RUN_DIR/propio.conf"
out=$(node_stop propio 2>&1)
check "un pid que ya es de otro programa no se mata" 'kill -0 "$otro" 2> /dev/null'
kill -KILL "$otro" 2> /dev/null; wait "$otro" 2> /dev/null
check "ni se da por arrancado" 'printf "PID=%s\nLSTART=otra hora\nPORT=47399\n" "$$" > "$NODE_RUN_DIR/propio.conf"; gui_node | grep -q "^P|propio|Node|parado|"'
rm -f "$NODE_RUN_DIR/propio.conf"
out=$(node_stop "../x" 2>&1); rc=$?; check "parar: carpeta rara" '[ $rc -ne 0 ]'
out=$(node_log "../x" 2>&1); rc=$?; check "registro: carpeta rara" '[ $rc -ne 0 ]'

pkg falla '{"scripts":{"start":"x","build":"x"}}'; mkdir -p "$HTDOCS_DIR/falla/node_modules"; : > "$HTDOCS_DIR/falla/falla-build"
out=$(node_start falla compilado 2>&1 < /dev/null); rc=$?
check "si no compila, no arranca y lo dice" '[ $rc -ne 0 ] && grep -q "No se ha podido compilar" <<< "$out" && [ ! -e "$NODE_RUN_DIR/falla.conf" ]'
pkg muere '{"scripts":{"dev":"x"}}'; mkdir -p "$HTDOCS_DIR/muere/node_modules"
printf '#!/bin/bash\necho se-cae; exit 3\n' > "$NVM/v26.1.0/bin/npm"
out=$(node_start muere 2>&1 < /dev/null); rc=$?
check "si se cae al arrancar, se dice con su registro" '[ $rc -ne 0 ] && grep -q "se ha parado al arrancar" <<< "$out" && grep -q se-cae <<< "$out" && [ ! -e "$NODE_RUN_DIR/muere.conf" ]'
fake_node "$NVM/v26.1.0" v26.1.0

# --- Astro compilado sin tocar el proyecto ---
A=$HTDOCS_DIR/astro
mkdir -p "$A/node_modules/@astrojs/node"; : > "$A/node_modules/@astrojs/node/package.json"
printf "import vercel from '@astrojs/vercel';\nexport default { adapter: vercel() };\n" > "$A/astro.config.mjs"
cp "$A/package.json" "$W/antes.json"; cp "$A/astro.config.mjs" "$W/antes.mjs"
cat > "$NVM/v26.1.0/bin/npx" << 'EOF'
#!/bin/bash
echo "$*" > "$PWD/npx.log"
EOF
node_build_astro "$A" "$NVM/v26.1.0/bin" "PATH=/usr/bin:/bin" > /dev/null 2>&1
check "Astro con Vercel: compila con el adaptador de Node" 'grep -q "astro build --config node_modules/.nexum-astro.config.mjs" "$A/npx.log" && grep -q "adapter: node({ mode: .standalone. })" "$A/node_modules/.nexum-astro.config.mjs" && grep -q "import base from .\.\./astro.config.mjs." "$A/node_modules/.nexum-astro.config.mjs"'
check "su configuracion y su package.json no cambian" 'cmp -s "$A/package.json" "$W/antes.json" && cmp -s "$A/astro.config.mjs" "$W/antes.mjs"'
printf "export default {};\n" > "$A/astro.config.mjs"
node_build_astro "$A" "$NVM/v26.1.0/bin" "PATH=/usr/bin:/bin" > /dev/null 2>&1
check "sin adaptador de alojamiento: su compilacion normal" 'grep -qx -- "--no-install astro build" "$A/npx.log"'
node_command "$A" Astro compilado db "$NVM/v26.1.0/bin" 47000
check "Astro estatico: solo su carpeta dist, en 127.0.0.1" '[ "${NODE_CMD[*]}" == "python3 -I -m http.server --bind 127.0.0.1 --directory dist 47000" ]'
mkdir -p "$A/dist/server"; : > "$A/dist/server/entry.mjs"
node_command "$A" Astro compilado db "$NVM/v26.1.0/bin" 47000
check "Astro con servidor: su entrada" '[ "${NODE_CMD[*]: -1}" == dist/server/entry.mjs ]'
for k in Astro Next Nuxt SvelteKit Vite; do
    node_command "$A" "$k" desarrollo d /b 47000
    check "$k en desarrollo: solo en 127.0.0.1 y en su puerto" 'grep -q "127.0.0.1" <<< "${NODE_CMD[*]}" && grep -q 47000 <<< "${NODE_CMD[*]}"'
done
for k in Next SvelteKit Vite; do
    node_command "$A" "$k" compilado b /b 47000
    check "$k compilado: solo en 127.0.0.1 y en su puerto" 'grep -q "127.0.0.1" <<< "${NODE_CMD[*]}" && grep -q 47000 <<< "${NODE_CMD[*]}"'
done
PATH=$PATH_OLD
hash -r

# --- Sin contraseña y sin root ---
check "no pide la contraseña en las tareas" 'grep -qE "^ +gui-\*\|node-\*\|exportar-bd" "$SRC"'
check "como root no arranca" 'sed -n "/^function node_start()/,/^}/p" "$SRC" | grep -q "no se arrancan como root"'
check "no usa sudo" '! sed -n "/^function node_find()/,/^function node_log()/p" "$SRC" | grep -qE "\b(sudo|\$SUDO)\b"'
check "comandos en el programa" 'grep -qF "node-arrancar) shift; node_start \"\$@\" ;;" "$SRC" && grep -qF "node-parar) node_stop \"\$2\" ;;" "$SRC" && grep -qF "gui-node) gui_node ;;" "$SRC"'

# --- Su pestaña ---
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: en la lista de apartados y con su vista" 'grep -qF "(\"node\", \"Node\", \"logo:node\")" "$SRC" && grep -qF "case \"node\": NodeView()" "$SRC"'
    check "Mac: los datos al entrar" 'grep -qF "if key == \"node\" { reloadNode() }" "$SRC"'
    check "Mac: el boton Tunel siempre, y lo que se comparte es lo compilado" 'sed -n "/^struct NodeView: View {/,/^struct ReposView/p" "$SRC" | grep -qF "model.shareNode(p)" && sed -n "/^    func shareNode/,/^    }/p" "$SRC" | grep -qF "[\"node-arrancar\", p.folder, \"compilado\"]" && sed -n "/^    func shareNode/,/^    }/p" "$SRC" | grep -qF "if p.running && p.mode == \"compilado\" {"'
    check "Mac: sus botones" 'for b in Arrancar Compilar "Abrir web" Parar Compartiendo; do sed -n "/^struct NodeView: View {/,/^struct ReposView/p" "$SRC" | grep -qF "name: \"$b\"" || exit 1; done; sed -n "/^struct NodeView: View {/,/^struct ReposView/p" "$SRC" | grep -qF "openInVSCode(path)" && sed -n "/^struct NodeView: View {/,/^struct ReposView/p" "$SRC" | grep -qF "showFolder(path)"'
    check "Mac: con su lista de pasos" 'grep -q "runTask(\"Arrancando .*\[\"node-arrancar\", p.folder, mode\], progress: true" "$SRC"'
else
    check "Linux: en la lista de apartados y en la pila" 'grep -qF "(\"node\", \"Node\", \"logo:node\")" "$SRC" && grep -qF "(\"node\", self.page_node)" "$SRC"'
    check "Linux: los datos al entrar" 'grep -q "elif row.tab_name == \"node\":" "$SRC"'
    check "Linux: el boton Tunel siempre, y lo que se comparte es lo compilado" 'sed -n "/^    def nv_node_row/,/^    def nv_node_share/p" "$SRC" | grep -q "lambda: self.nv_node_share(p))" && sed -n "/^    def nv_node_share/,/^    def nv_node_start/p" "$SRC" | grep -qF "[\"node-arrancar\", p[\"folder\"], \"compilado\"]" && sed -n "/^    def nv_node_share/,/^    def nv_node_start/p" "$SRC" | grep -qF "if p[\"running\"] and p[\"mode\"] == \"compilado\":"'
    check "Linux: sus botones" 'for b in Arrancar Compilar "Abrir web" Parar Compartiendo; do sed -n "/^    def nv_node_row/,/^    def nv_node_share/p" "$SRC" | grep -qF "\"$b\"," || exit 1; done; sed -n "/^    def nv_node_row/,/^    def nv_node_share/p" "$SRC" | grep -qF "self.open_in_vscode(path)" && sed -n "/^    def nv_node_row/,/^    def nv_node_share/p" "$SRC" | grep -qF "GLib.filename_to_uri(path, None)"'
    check "Linux: el boton de Compartir cambia con el tunel" 'grep -qF "self.nv_node_render, self.build_tools" "$SRC"'
    check "Linux: con su lista de pasos" 'grep -q "\[\"node-arrancar\", p\[\"folder\"\], mode\], progress=True" "$SRC"'
fi
exit $fail
