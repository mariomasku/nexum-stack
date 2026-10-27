#!/bin/bash
# Botones del visor a tu gusto y cuándo se buscan actualizaciones al abrir (Linux 1.56.1): la
# configuración de los botones aguanta un fichero roto o de otra versión, y se busca el primer
# arranque del día y después cada UPDATE_EVERY. Uso: botones-actualizar.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-botones.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^def buttons_conf():' "$SRC" || { echo "  ok    (sin botones a tu gusto)"; exit 0; }
sed -n "/^    cat <<'LVM_GUI_PY'$/,/^LVM_GUI_PY$/p" "$SRC" | sed '1d;$d' > "$W/gui.py"

out=$(python3 -I - "$W/gui.py" "$W" << 'EOF'
import ast, json, os, sys, time
src, w = sys.argv[1:3]
tree = ast.parse(open(src, encoding="utf-8").read())
want = {"buttons_conf", "buttons_save", "update_check_due"}
consts = {"VISOR_BUTTONS", "BUTTON_STYLES", "UPDATE_EVERY", "BUTTON_SIZES", "BUTTON_SIZE_MIN", "BUTTON_SIZE_MAX"}
code = []
for node in ast.walk(tree):
    if isinstance(node, ast.FunctionDef) and node.name in want:
        node.decorator_list = []
        code.append(ast.unparse(node))
    elif isinstance(node, ast.Assign) and any(isinstance(n, ast.Name) and n.id in consts
                                              for t in node.targets for n in ast.walk(t)):
        code.append(ast.unparse(node))
g = {"os": os, "json": json, "time": time, "LOG_DIR": w, "SIMULATE": False, "_buttons_sim": {},
     "BUTTONS_FILE": os.path.join(w, "botones-visor")}
exec("\n".join(code), g)


def say(name, ok):
    print("%s|%s" % ("ok" if ok else "FALLA", name))


keys = [k for k, _n, _i in g["VISOR_BUTTONS"]]
c = g["buttons_conf"]()
say("botones: sin fichero, todos, en su orden y con su nombre", c["order"] == keys and not c["hidden"] and c["style"] == "nombre")
i = keys.index("compartir")
say("botones: Compartir, detrás de Docker y antes de Log", keys[i - 1] == "docker" and keys[i + 1] == "log")
open(g["BUTTONS_FILE"], "w").write("{roto")
say("botones: un fichero roto no rompe nada", g["buttons_conf"]()["order"] == keys)
json.dump({"order": ["log", "inventado", "web"], "hidden": ["pma", "otro"], "style": "raro"}, open(g["BUTTONS_FILE"], "w"))
c = g["buttons_conf"]()
say("botones: lo que no se conoce se ignora y los que faltan van al final",
    c["order"][:2] == ["log", "web"] and sorted(c["order"]) == sorted(keys) and c["hidden"] == {"pma"} and c["style"] == "nombre")
g["buttons_save"]({"order": list(reversed(keys)), "hidden": {"vscode"}, "style": "grande", "size": 96})
c = g["buttons_conf"]()
say("botones: se guarda el orden, los ocultos y el estilo", c["order"] == list(reversed(keys)) and c["hidden"] == {"vscode"} and c["style"] == "grande")
json.dump({"style": "icono"}, open(g["BUTTONS_FILE"], "w"))
c = g["buttons_conf"]()
say("botones: cada estilo cuadrado con su tamaño si no se ha elegido otro", c["size"] == g["BUTTON_SIZES"]["icono"])
json.dump({"style": "grande", "size": 9999}, open(g["BUTTONS_FILE"], "w"))
say("botones: un tamaño fuera de lo que deja el deslizador no vale", g["buttons_conf"]()["size"] == g["BUTTON_SIZES"]["grande"])
g["buttons_save"]({"order": keys, "hidden": set(), "style": "icono", "size": 64})
say("botones: se guarda el tamaño", g["buttons_conf"]()["size"] == 64)
g["buttons_save"]({"order": list(reversed(keys)), "hidden": {"vscode"}, "style": "grande", "size": 96})
g["SIMULATE"] = True
g["buttons_save"]({"order": keys, "hidden": set(), "style": "icono", "size": 40})
say("botones: en la simulación no se escribe el fichero", json.load(open(g["BUTTONS_FILE"]))["style"] == "grande"
    and g["buttons_conf"]()["style"] == "icono")
g["SIMULATE"] = False

due = g["update_check_due"]
path = os.path.join(w, "actualizaciones-arranques")
seq = [due(None) for _ in range(9)]
every = g["UPDATE_EVERY"]
say("actualizaciones: el primer arranque del día se busca", seq[0])
say("actualizaciones: después, cada %d arranques" % every,
    [n for n, d in enumerate(seq) if d] == list(range(0, 9, every)))
open(path, "w").write("2000-01-01 2\n")
say("actualizaciones: otro día, se vuelve a buscar al primer arranque", due(None) and open(path).read().startswith(time.strftime("%Y-%m-%d") + " 0"))
open(path, "w").write("basura")
say("actualizaciones: un fichero roto cuenta como el primero del día", due(None))
g["SIMULATE"] = True
open(path, "w").write(time.strftime("%Y-%m-%d") + " 1\n")
say("actualizaciones: en la simulación se busca sin apuntar nada", due(None) and open(path).read().endswith(" 1\n"))
EOF
)
while IFS='|' read -r st name; do
    [ "$st" == ok ] && ok "$name" || bad "$name"
done <<< "$out"
check "actualizaciones: si se dice que no, ya no se apunta la versión rechazada" '! grep -q "declined_update" "$SRC"'
check "ventana: «Personalizar los botones…» en el menú ⋮ y en Configuración" 'grep -q "(\"Personalizar los botones…\", lambda: self.nv_buttons_dialog())" "$SRC" && grep -q "self.nv_buttons_tools()" "$SRC"'
check "ventana: Desmontar, ⋮ y los fijos de Docker, del mismo estilo y tamaño" 'grep -q "\[(eject, (\"icono\", \"media-eject-symbolic\"), \"Desmontar\")\]" "$SRC" && grep -q "self.nv_restyle(more, buttons_conf()" "$SRC" && grep -q "self.nv_restyle(power, conf" "$SRC" && grep -q "self.nv_restyle(vb, conf" "$SRC"'
check "ventana: sin nombre, el cuadrado mide lo mismo de alto que de ancho" 'grep -q "b.set_size_request(side, side)" "$SRC"'
check "ventana: al cargar un proyecto, la página sube sola hasta el visor" 'grep -q "smooth_scroll(self.page_projects)" "$SRC"'
check "ventana: los dos visores colocan sus botones con lo elegido" '[ "$(grep -c "self.nv_place_buttons(acts, btns" "$SRC")" -eq 2 ]'
exit $fail
