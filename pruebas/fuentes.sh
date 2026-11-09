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
for f in "$ROOT"/src/linux/bash/*.sh "$ROOT"/src/mac/bash/*.sh; do bash -n "$f" 2> /dev/null || bad+=" ${f##*/}"; done
check "cada sección de bash es válida por sí sola${bad:+ (mal:$bad)}" '[ -z "$bad" ]'
check "el Python de la ventana y del túnel, válido" 'for f in "$ROOT"/src/linux/ventana.py "$ROOT"/src/linux/tunel.py "$ROOT"/src/mac/tunel.py; do python3 -I -c "import ast, sys; ast.parse(open(sys.argv[1], encoding=\"utf-8\").read())" "$f" || exit 1; done'
check "cada pieza, incluida una vez" '[ "$(cat "$ROOT"/src/linux/bash/*.sh | grep -c "^#@incluir ")" -eq 2 ] && [ "$(cat "$ROOT"/src/mac/bash/*.sh | grep -c "^#@incluir ")" -eq 2 ]'
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
exit $fail
