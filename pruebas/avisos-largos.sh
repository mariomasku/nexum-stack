#!/bin/bash
# Avisos de más de dos líneas (1.57.38): sus botones van debajo del texto, a la derecha, y el texto usa
# todo el ancho (al lado se quedaba en una columna estrecha). Uso: avisos-largos.sh <lvm-instalador.sh de Linux o del Mac>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
if grep -q "gi.require_version" "$SRC"; then
    check "Linux: la fila sabe poner sus botones debajo" 'grep -qF "    def suffix_below(self, chars=72):" "$SRC" && grep -qF "        self.texts.pack_start(self.suffix, False, False, 0)" "$SRC" && grep -qF "        self.suffix.set_halign(Gtk.Align.END)" "$SRC"'
    check "Linux: en los avisos, los de más de dos líneas, debajo" 'grep -qF "if isinstance(w, ActionRow) and w.suffix.get_children() and w.text_lines() > 2:" "$SRC" && grep -qF "                w.suffix_below()" "$SRC"'
    check "Linux: el de parches ya no va en una columna de 46" '! grep -qF "lbl.set_max_width_chars(46)" "$SRC"'
    # (cuantas lineas: el titulo y cada linea del subtitulo, a unos 60 caracteres por linea)
    eval "$(python3 - "$SRC" << 'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"    def text_lines\(self, chars=60\):\n(?:        .*\n)+", s)
print("TL_OK=%d" % bool(m))
PY
)"
    check "Linux: cuenta las líneas del título y del subtítulo" '[ "$TL_OK" == 1 ]'
else
    check "Mac: la fila ancha, con sus botones debajo a la derecha y el texto entero" 'grep -qF "struct WideRow<Trailing: View>: View {" "$SRC" && grep -qF "                    .fixedSize(horizontal: false, vertical: true)" "$SRC"'
    check "Mac: el aviso de parches la usa (con la lista entera, no en dos líneas)" 'grep -qF "                    WideRow(\"Conviene ponerlos: son parches de seguridad\"," "$SRC"'
fi
exit $fail
