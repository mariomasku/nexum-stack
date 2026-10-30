#!/bin/bash
# Terminal abajo de la ventana (Linux 1.56.12, Mac 1.40.1): el boton Terminal (en lugar de Localhost) la
# enseña y la esconde; con el aspecto del visor, un poco hundida; tu shell, en la carpeta del proyecto
# cargado. Linux: VTE (la de la Terminal de GNOME). Mac: tu shell en una pseudoterminal con su sesion.
# Uso: terminal.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -qE "def nv_term_panel|final class TermSession" "$SRC" || { echo "  ok    (sin la terminal de la ventana)"; exit 0; }
if grep -q "LVM_SWIFT" "$SRC"; then
    check "Mac: Terminal en la cabecera en lugar de Localhost" 'grep -q "Button(action: { model.termOpen.toggle() }) {" "$SRC" && ! grep -q "Label(\"Localhost\", systemImage: \"globe\")" "$SRC"'
    check "Mac: abajo del contenido, solo a la vista si se ha pulsado" 'grep -q "                    if model.termOpen {" "$SRC" && grep -A1 "                    if model.termOpen {" "$SRC" | grep -q "TermPanel()"'
    check "Mac: tu shell en una pseudoterminal con su propia sesion (Ctrl+C y los trabajos, como en Terminal)" 'grep -q "posix_openpt(O_RDWR | O_NOCTTY)" "$SRC" && grep -q "posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))" "$SRC" && grep -q "posix_spawn_file_actions_addchdir_np(&fa, cwd)" "$SRC"'
    check "Mac: se ve como texto (sin codigos de color ni de cursor) y sigue abierta al esconderla" 'grep -q "env\[\"TERM\"\] = \"dumb\"" "$SRC" && grep -q "Esconder la terminal (sigue abierta)" "$SRC" && grep -q "if termOpen { termStart() }" "$SRC"'
    check "Mac: con el aspecto del visor, hundida (sombra por dentro)" 'grep -q "(como el visor de arriba, hundida: fondo algo más oscuro y sombra por dentro)" "$SRC"'
else
    check "Linux: Terminal en la cabecera en lugar de Localhost" 'grep -q "self.term_btn = Gtk.ToggleButton(" "$SRC" && ! grep -q "nv_button(\"web-browser-symbolic\", \"Localhost\"" "$SRC"'
    check "Linux: abajo del contenido (se cambia de alto arrastrando), escondida hasta que se pulsa" 'grep -q "self.term_paned.pack2(self.nv_term_panel(), False, False)" "$SRC" && grep -A3 "        box.show_all()" "$SRC" | grep -q "box.set_no_show_all(True)"'
    check "Linux: VTE con tu shell en la carpeta del proyecto cargado; sin VTE, dice como ponerla" 'grep -q "t.spawn_async(Vte.PtyFlags.DEFAULT, cwd, \[shell\]" "$SRC" && grep -q "sudo apt install gir1.2-vte-2.91" "$SRC"'
    check "Linux: con el aspecto del visor, hundida (sombra por dentro)" 'grep -q "^.nv-terminal { background-color: shade(@theme_bg_color, 0.78)" "$SRC" && grep -q "box-shadow: inset 0 2px 7px" "$SRC"'
    check "Linux: ir al proyecto cargado escribe el cd, con la ruta entre comillas" 'grep -qF "% shlex.quote(cwd)).encode())" "$SRC"'
    if python3 -c "import gi; gi.require_version('Vte','2.91')" 2> /dev/null; then
        S=$(mktemp -d "$TMPBASE/w-term.XXXX"); trap 'rm -rf "$S"' EXIT
        awk "/cat <<'LVM_GUI_PY'/{f=1;next} /^LVM_GUI_PY\$/{f=0} f" "$SRC" > "$S/gui.py"
        check "Linux: el codigo de la ventana compila" 'python3 -m py_compile "$S/gui.py"'
    fi
fi
exit $fail
