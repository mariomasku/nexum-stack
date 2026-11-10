#!/bin/bash
# Configuración (Linux 1.57.5, Mac 1.41.4): el título grande es el del apartado abierto (no se repite en su tarjeta),
# Apariencia en tres bloques con los botones del visor dentro (ya no hay apartado «Visor de los proyectos») y
# Seguridad entre webs explicada en cuatro puntos. Uso: apartados.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
if grep -q "^let ERROR_LOG = " "$SRC"; then
    check "Mac: sin apartado Visor de los proyectos (va en Apariencia)" '! grep -qF "(\"visor\", \"Visor de los proyectos\"" "$SRC" && ! grep -qF "func buttonsCard()" "$SRC" && grep -qF "block(\"Visor de los proyectos\"" "$SRC"'
    check "Mac: Apariencia en tres bloques (los apartados del menú lateral, en dos columnas)" 'grep -qF "block(\"Iconos del menú lateral\"" "$SRC" && grep -qF "Text(\"Apartados del menú lateral\")" "$SRC" && grep -qF "navSwitches(Array(items.prefix(half)))" "$SRC" && grep -qF "navSwitches(Array(items.dropFirst(half)))" "$SRC"'
    check "Mac: el título, el del apartado abierto" 'grep -qF "PageTitle(title: sec?.1 ?? \"Configuración\", sub: toolsDesc ?? \"Configuración\"," "$SRC" && grep -qF ".environment(\\.toolsSection, sec?.1)" "$SRC"'
    check "Mac: la tarjeta del apartado no repite el título" 'grep -qF "return t.hasPrefix(s)" "$SRC" && grep -qF ".preference(key: ToolsDescKey.self, value: isSectionCard ? description : nil)" "$SRC"'
    check "Mac: Seguridad entre webs, en cuatro puntos" '[ "$(sed -n "/^let CROSS_SITE_HELP/,/^]/p" "$SRC" | grep -cE "^    \(\"")" -eq 4 ] && grep -qF "TileCard(\"Qué es\", wide: true)" "$SRC"'
else
    check "Linux: sin apartado Visor de los proyectos (va en Apariencia)" '! grep -qF "(\"Visor de los proyectos\", \"Visor de los proyectos\"" "$SRC" && ! grep -qF "def nv_buttons_tools" "$SRC" && grep -qF "lb = block(\"Visor de los proyectos\"" "$SRC"'
    check "Linux: Apariencia en tres bloques" 'grep -qF "lb = block(\"Iconos del menú lateral\"" "$SRC" && grep -qF "lb = block(\"Apartados del menú lateral\"" "$SRC"'
    check "Linux: el título, el del apartado abierto" 'grep -qF "    def nv_tools_title(self):" "$SRC" && sed -n "/^        def picked(_lb, row):/,/^$/p" "$SRC" | grep -qF "self.nv_tools_title()"'
    check "Linux: la tarjeta del apartado no repite el título" 'grep -qF "self.tools_desc[title] = c.get_tooltip_text()" "$SRC"'
    check "Linux: Seguridad entre webs, en cuatro puntos" '[ "$(sed -n "/^CROSS_SITE_HELP = \[/,/^]/p" "$SRC" | grep -cE "^    \(\"")" -eq 4 ] && grep -qF "for ic, title, text in CROSS_SITE_HELP:" "$SRC"'
fi
exit $fail
