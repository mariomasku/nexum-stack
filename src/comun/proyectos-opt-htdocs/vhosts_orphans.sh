# Vhosts sin carpeta: los de un proyecto de htdocs (DocumentRoot en .../htdocs/<carpeta>) cuya carpeta ya no
# existe (se borró a mano, se movió o no se ha vuelto a clonar). Apache arranca igual, pero avisa de cada uno al
# arrancar («AH00112: Warning: DocumentRoot [...] does not exist»). Solo los de una carpeta de htdocs: el de
# localhost (htdocs entero) y los que llevan a otro sitio no se tocan nunca.
# Uso: VHOSTS_ORPHANS_PY <vhosts> <htdocs> lista | quitar <copia>
#   lista: W|<carpeta>|<dominios separados por espacios> por cada carpeta que falta
#   quitar: escribe en <copia> los vhosts sin esos bloques (ni la línea en blanco de antes)
VHOSTS_ORPHANS_PY='
import os, re, sys
src, htdocs, mode = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(src, encoding="utf-8", errors="surrogateescape", newline="").read().split("\n")
root = re.compile(r"^\s*DocumentRoot\s+\"?([^\"\s]*/htdocs/([^/\"\s]+))(/[^\"\s]*)?\"?\s*$", re.I)


def missing(block):
    """La carpeta de htdocs de un bloque, si no existe (o nada)."""
    for l in block:
        m = root.match(l)
        if m:
            name = m.group(2)
            if name in (".", "..") or os.path.lexists(os.path.join(htdocs, name)):
                return None
            return name
    return None


out, block, found = [], None, {}
for line in lines:
    if block is None:
        if re.match(r"^\s*<VirtualHost\b", line, re.I):
            block = [line]
        else:
            out.append(line)
        continue
    block.append(line)
    if re.match(r"^\s*</VirtualHost>", line, re.I):
        name = missing(block)
        if name:
            names = found.setdefault(name, [])
            for l in block:
                w = l.split("#", 1)[0].split()
                if len(w) >= 2 and w[0].lower() in ("servername", "serveralias"):
                    names += [n.lower().split(":")[0] for n in w[1:] if n.lower().split(":")[0] not in names]
            while out and not out[-1].strip():
                out.pop()
        else:
            out += block
        block = None
if block:
    out += block
if mode == "lista":
    for name in sorted(found):
        print("W|%s|%s" % (name, " ".join(found[name])))
elif mode == "quitar":
    with open(sys.argv[4], "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
        f.write("\n".join(out))
'

# vhosts-sin-carpeta [quitar]: los vhosts de proyectos cuya carpeta ya no está en htdocs; con quitar, se quitan
# (con edit_vhosts --aplicar: lo comprueba Apache antes, guarda la copia si está el ajuste de las copias de los
# ficheros y lo recarga). La carpeta, las BBDD y /etc/hosts no se tocan
function vhosts_orphans() {
    local vhosts list copy
    vhosts=$(readlink -f "$ACTIVE_VHOSTS" 2> /dev/null || echo "$ACTIVE_VHOSTS")
    if [ ! -f "$vhosts" ]; then
        echo "No hay fichero de vhosts ($ACTIVE_VHOSTS): no hay ninguna versión activa"

        return 1
    fi
    list=$(python3 -I -c "$VHOSTS_ORPHANS_PY" "$vhosts" "$HTDOCS_DIR" lista) || return 1
    if [ -z "$list" ]; then
        echo "Todos los vhosts de proyectos tienen su carpeta en $HTDOCS_DIR"

        return 0
    fi
    echo "Vhosts de carpetas que ya no están en $HTDOCS_DIR:"
    local name domains
    while IFS='|' read -r _ name domains; do
        echo "  $name (${domains:-sin dominio})"
    done <<< "$list"
    case "$1" in
        "") echo "Para quitarlos: nexum vhosts-sin-carpeta quitar"; return 0 ;;
        quitar) ;;
        *) echo "Uso: nexum vhosts-sin-carpeta [quitar]"; return 1 ;;
    esac
    mkdir -p -m 700 "$LOG_DIR" || return 1
    copy=$(mktemp "$LOG_DIR/vhosts-sin-carpeta-XXXXXX") || return 1
    python3 -I -c "$VHOSTS_ORPHANS_PY" "$vhosts" "$HTDOCS_DIR" quitar "$copy" || { rm -f "$copy"; return 1; }
    if cmp -s "$copy" "$vhosts"; then
        rm -f "$copy"
        echo "No había nada que quitar"

        return 0
    fi
    echo "Se quitan sus vhosts (las carpetas, las BBDD y /etc/hosts no se tocan)"
    edit_vhosts --aplicar "$copy" || { rm -f "$copy"; return 1; }
    rm -f "$copy"
}
