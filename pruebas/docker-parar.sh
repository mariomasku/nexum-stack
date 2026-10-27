#!/bin/bash
# Parar los contenedores de Nexum (Linux 1.56.1): al parar un proyecto del Apache de Docker se para lo
# común que ya no usa nadie, docker-parar-todo para solo los de Nexum, y parar algo común que usa un
# proyecto en marcha avisa (terminal y ventana). Con un Docker falso. Uso: docker-parar.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-docker-parar.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^function docker_web_idle_stop() {' "$SRC" || { echo "  ok    (sin parar lo común)"; exit 0; }
extract "$SRC" docker_web_idle_stop docker_stop_all docker_shared_warn docker_container_action || exit 1

DRY=0
# Docker falso: los que estan en marcha, en $W/up; lo que se para, en $W/parados
dk() {
    case $1 in
        ps) cat "$W/up" ;;
        stop) shift; printf '%s\n' "$@" >> "$W/parados"; local n; for n in "$@"; do sed -i "/^$n\$/d" "$W/up"; done ;;
    esac
}
run() { "$@"; }
# Dos proyectos del Apache de Docker: tienda (MariaDB 11.8) y blog (MariaDB 10.11)
docker_web_projects() { echo tienda blog; }
docker_conf() {
    case "$1:$2" in
        tienda:MARIADB) echo 11.8 ;; blog:MARIADB) echo 10.11 ;;
        tienda:CARPETA) echo mi-tienda ;; blog:CARPETA) echo mi-blog ;;
    esac
}
start() { printf '%s\n' "$@" > "$W/up"; : > "$W/parados"; }

start nexum-web nexum-pma nexum-mariadb-11-8 nexum-mariadb-10-11 nexum-tienda-php83 nexum-blog-php84 otro-programa
sed -i '/nexum-blog-php84/d' "$W/up"
out=$(docker_web_idle_stop)
check "parado blog: su MariaDB (10.11) se para; la de tienda, que sigue, no" 'grep -qx nexum-mariadb-10-11 "$W/parados" && ! grep -q "nexum-mariadb-11-8\|nexum-web" "$W/parados" && grep -q "MariaDB 10.11 de Docker" <<< "$out"'
sed -i '/nexum-tienda-php83/d' "$W/up"
out=$(docker_web_idle_stop)
check "parados todos: MariaDB y el Apache de Docker con su phpMyAdmin, parados" 'grep -qx nexum-mariadb-11-8 "$W/parados" && grep -qx nexum-web "$W/parados" && grep -qx nexum-pma "$W/parados"'
check "lo de otros programas no se toca" 'grep -qx otro-programa "$W/up" && ! grep -q otro-programa "$W/parados"'

start nexum-web nexum-pma nexum-mariadb-11-8 nexum-tienda-php83 nexum-viejo-php-1 nexum-viejo-db-1 otro-programa nexum-raro
out=$(docker_stop_all)
check "parar todo: los de Nexum (proyectos, MariaDB comunes y Apache de Docker)" '[ "$(sort "$W/parados" | tr "\n" " ")" == "nexum-mariadb-11-8 nexum-pma nexum-tienda-php83 nexum-viejo-db-1 nexum-viejo-php-1 nexum-web " ]'
check "parar todo: lo de otros programas (y un nombre que no es de Nexum) sigue" 'grep -qx otro-programa "$W/up" && grep -qx nexum-raro "$W/up"'
: > "$W/up"
check "parar todo sin nada en marcha: lo dice" 'docker_stop_all | grep -q "No hay ningun contenedor de Nexum en marcha"'

start nexum-web nexum-pma nexum-mariadb-11-8 nexum-mariadb-10-11 nexum-tienda-php83
out=$(docker_container_action parar nexum-mariadb-11-8)
check "parar una MariaDB común en uso: avisa de quién la usa (y la para)" 'grep -q "Aviso: nexum-mariadb-11-8 es comun y lo usan ahora: mi-tienda. Se quedan sin BBDD" <<< "$out" && grep -qx nexum-mariadb-11-8 "$W/parados"'
out=$(docker_container_action parar nexum-mariadb-10-11)
check "parar una MariaDB común que nadie usa: sin aviso" '! grep -q Aviso <<< "$out"'
out=$(docker_container_action parar nexum-web)
check "parar el Apache de Docker en uso: avisa" 'grep -q "Aviso: nexum-web es comun y lo usan ahora: mi-tienda. Dejan de verse" <<< "$out"'

if grep -q "LVM_SWIFT" "$SRC"; then
    check "ventana (Mac): puede parar todos los de Nexum (MariaDB común y Apache de Docker incluidos)" 'grep -q "|php\[0-9\]{2})\$\"" "$SRC" && grep -q "\"^nexum-(web|pma|mariadb-\[0-9\]{1,2}-\[0-9\]{1,2})\$\"" "$SRC"'
    check "ventana (Mac): pregunta antes de parar algo común en uso (contenedor, grupo y Apache)" '[ "$(grep -c "stopSharedOK(" "$SRC")" -ge 4 ] && grep -q "if action == \"parar\" \&\& !stopSharedOK(\[c.name\], c.name) { return }" "$SRC"'
    check "ventana (Mac): «Parar todos» en la pestaña Docker" 'grep -q "\"docker-parar-todo\"\]" "$SRC"'
else
# La ventana: puede parar todos los de Nexum y pregunta antes de parar algo común en uso
sed -n "/^    cat <<'LVM_GUI_PY'$/,/^LVM_GUI_PY$/p" "$SRC" | sed '1d;$d' > "$W/gui.py"
out=$(python3 -I - "$W/gui.py" << 'EOF'
import ast, re, sys
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
code = [ast.unparse(n) for n in ast.walk(tree) if isinstance(n, ast.FunctionDef) and n.name in ("docker_own", "nv_shared_users")]
g = {"re": re}
exec("\n".join(code), g)
own = g["docker_own"]
print("own|%d" % all(own(n) for n in ("nexum-mariadb-11-8", "nexum-web", "nexum-pma", "nexum-tienda-php83", "nexum-viejo-db-1")))
print("ajeno|%d" % (not any(own(n) for n in ("otro-programa", "nexum-raro", "nexum-tienda-php8", "mariadb"))))
class App:
    docker = {"projects": [{"web": True, "maria": "11.8", "slug": "tienda", "folder": "mi-tienda"},
                           {"web": True, "maria": "10.11", "slug": "blog", "folder": "mi-blog"},
                           {"web": False, "maria": "11.8", "slug": "viejo", "folder": "viejo"}],
              "containers": [{"name": "nexum-tienda-php83", "state": "running"}, {"name": "nexum-blog-php84", "state": "exited"},
                             {"name": "nexum-viejo-php-1", "state": "running"}]}
u = lambda n: g["nv_shared_users"](App(), n)
print("maria|%d" % (u("nexum-mariadb-11-8") == ["mi-tienda"] and u("nexum-mariadb-10-11") == []))
print("web|%d" % (u("nexum-web") == ["mi-tienda"] and u("nexum-tienda-php83") == []))
EOF
)
check "ventana: puede parar todos los de Nexum (MariaDB común y Apache de Docker incluidos)" 'grep -qx "own|1" <<< "$out"'
check "ventana: los de otros programas, no" 'grep -qx "ajeno|1" <<< "$out"'
check "ventana: sabe qué proyectos en marcha usan cada MariaDB común" 'grep -qx "maria|1" <<< "$out"'
check "ventana: y cuáles usan el Apache de Docker" 'grep -qx "web|1" <<< "$out"'
check "ventana: pregunta antes de parar algo común en uso (fila, grupo y Apache)" '[ "$(grep -c "self.nv_stop_shared_ok(" "$SRC")" -ge 3 ]'
check "ventana: «Parar todos» en la pestaña Docker" 'grep -q "\"docker-parar-todo\"\]" "$SRC"'
fi
exit $fail
