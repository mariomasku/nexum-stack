#!/bin/bash
# Fuentes (1.57.5): los dos scripts se construyen desde src/ con construir.sh. Que los del repositorio son
# los de src/, que cada pieza es válida por sí sola y que construir.sh detecta un cambio hecho a mano en
# un script construido o un fichero que no se incluye. Uso: fuentes.sh
HERE=$(cd "$(dirname "$0")" && pwd) ROOT=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/fuentes.XXXXXX") || exit 1
trap 'rm -rf "${W:?}"' EXIT
check "los dos scripts son los de src/" '"$ROOT/construir.sh" --comprobar > /dev/null'
bad=""
for f in "$ROOT"/src/linux/bash/*.sh "$ROOT"/src/mac/bash/*.sh "$ROOT"/src/comun/*/*.sh; do bash -n "$f" 2> /dev/null || bad+=" ${f##*/}"; done
check "cada sección de bash (y cada pieza común) es válida por sí sola${bad:+ (mal:$bad)}" '[ -z "$bad" ]'
"$ROOT/construir.sh" --ventana "$W/ventana.py"
check "el Python de la ventana (entera y cada fichero suyo) y del túnel, válido" 'for f in "$W/ventana.py" "$ROOT"/src/linux/ventana/*.py "$ROOT"/src/linux/tunel.py "$ROOT"/src/mac/tunel.py; do python3 -I -c "import ast, sys; ast.parse(open(sys.argv[1], encoding=\"utf-8\").read())" "$f" || exit 1; done'
check "la ventana y el túnel, incluidos una vez en cada sistema" '[ "$(cat "$ROOT"/src/linux/bash/*.sh | grep -c "^#@incluir [^c]")" -eq 2 ] && [ "$(cat "$ROOT"/src/mac/bash/*.sh | grep -c "^#@incluir [^c]")" -eq 2 ]'
n=$(find "$ROOT/src/comun" -name "*.sh" | wc -l)
check "cada pieza común ($n), incluida una vez en Linux y otra en Mac" 'for f in "$ROOT"/src/comun/*/*.sh; do r=${f#"$ROOT"/src/}; [ "$(cat "$ROOT"/src/linux/bash/*.sh | grep -cxF "#@incluir $r")" -eq 1 ] && [ "$(cat "$ROOT"/src/mac/bash/*.sh | grep -cxF "#@incluir $r")" -eq 1 ] || exit 1; done'
# Una copia del repositorio para estropearla
mkdir -p "$W/r/macos"
cp -r "$ROOT/src" "$ROOT/construir.sh" "$W/r/"
cp "$ROOT/lvm-instalador.sh" "$W/r/"
cp "$ROOT/macos/lvm-instalador.sh" "$W/r/macos/"
check "copia: se comprueba igual" '"$W/r/construir.sh" --comprobar > /dev/null'
printf '# a mano\n' >> "$W/r/lvm-instalador.sh"
check "un cambio a mano en el script construido: --comprobar falla" '! "$W/r/construir.sh" --comprobar > /dev/null 2>&1'
"$W/r/construir.sh" > /dev/null
check "construir.sh lo deja como el de src/" 'cmp -s "$W/r/lvm-instalador.sh" "$ROOT/lvm-instalador.sh"'
printf '# cambio en src\n' >> "$W/r/src/mac/ventana.swift"
"$W/r/construir.sh" > /dev/null
check "un cambio en src/mac/ventana.swift llega al script del Mac (dentro de su heredoc)" 'awk "/cat <<.LVM_SWIFT.\$/{f=1;next} /^LVM_SWIFT\$/{f=0} f" "$W/r/macos/lvm-instalador.sh" | tail -1 | grep -qx "# cambio en src"'
: > "$W/r/src/linux/suelto.py"
check "un fichero que no se incluye: error" '! "$W/r/construir.sh" > /dev/null 2>&1'
rm -f "$W/r/src/linux/suelto.py"
: > "$W/r/src/linux/ventana/suelto.py"
check "en la carpeta de la ventana, un fichero sin número: error" '! "$W/r/construir.sh" > /dev/null 2>&1'
rm -f "$W/r/src/linux/ventana/suelto.py"
printf '# cambio en src\n' >> "$W/r/src/linux/ventana/29-arranque.py"
"$W/r/construir.sh" > /dev/null
check "un cambio en un fichero de la ventana llega al script de Linux (al final de su heredoc)" 'awk "/cat <<.LVM_GUI_PY.\$/{f=1;next} /^LVM_GUI_PY\$/{f=0} f" "$W/r/lvm-instalador.sh" | tail -1 | grep -qx "# cambio en src"'
# Una pieza común que solo incluye un sistema: error (lo de un solo sistema va en su carpeta)
c=$(cd "$W/r/src" && ls comun/*/*.sh | head -1)
python3 -I - "$W/r/src/mac/bash" "#@incluir $c" << 'PY'
import glob, sys
for p in glob.glob(sys.argv[1] + "/*.sh"):
    t = open(p, encoding="utf-8").read()
    u = "".join(l for l in t.splitlines(True) if l.rstrip("\n") != sys.argv[2])
    if u != t:
        open(p, "w", encoding="utf-8").write(u)
PY
out=$("$W/r/construir.sh" 2>&1); rc=$?
check "una pieza común que solo usa Linux: error" '[ $rc -ne 0 ] && grep -q "lo común tiene que ir en Linux y en Mac" <<< "$out"'
exit $fail
