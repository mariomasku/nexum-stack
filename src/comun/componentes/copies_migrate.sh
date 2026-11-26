# Hasta la 1.57.6 las copias de seguridad iban en ~/lvm-copias: la primera vez se renombra a
# ~/nexum-backups (COPIES_DIR). Solo si es una carpeta tuya (no un enlace) y aun no hay ninguna
# ~/nexum-backups: si estan las dos, no se toca ninguna
function copies_migrate() {
    local old=$HOME/lvm-copias
    [ -d "$old" ] && [ ! -L "$old" ] && [ -O "$old" ] || { copies_sort; return 0; }
    if [ -e "$COPIES_DIR" ] || [ -L "$COPIES_DIR" ]; then
        copies_sort
        return 0
    fi
    mv "$old" "$COPIES_DIR" 2> /dev/null && chmod 700 "$COPIES_DIR" 2> /dev/null
    copies_sort
    return 0
}

# ~/nexum-backups, por carpetas (1.57.51): solo copias, cada clase en la suya
#   bbdd/lampp-8.4/        (XAMPP-8.4 en el Mac) <base>-<fecha>.sql.gz, <base>-antes-de-cargar-…,
#                          <base>-antes-de-copiar-…, mysql-sistema-…, todas-las-bases-….tar.gz
#   bbdd/docker/           las de Docker (docker-<proyecto>-<base>-…, docker-mariadb-…, docker-postgres-…)
#   proyectos/<carpeta>/   antes-de-actualizar-<fecha>/, cache-prod-<fecha>/, wp-config.php-…, parameters.php-…
#   sistema/hosts/, sistema/vhosts/, sistema/lampp-8.4/ (httpd.conf, php.ini… que cambia el programa)
#   xampp-oficial/         (Mac) las BBDD del XAMPP oficial al apartarlo
# copies_in <subcarpeta> [<carpeta de copias>]: la crea (solo tuya; con sudo, como tu usuario, para que
# root no deje en ella carpetas suyas) y la escribe. En simulacion solo la escribe
function copies_in() {
    local d=${2:-$COPIES_DIR}/$1 user=${SUDO_USER:-$USER}
    if [ "$DRY" -eq 1 ]; then
        echo "$d"
        return 0
    fi
    if [ "$(id -u)" -eq 0 ] && [ -n "$user" ] && [ "$user" != root ]; then
        sudo -u "$user" /bin/sh -c 'umask 077; mkdir -p "$1"' sh "$d" || return 1
    else
        ( umask 077; mkdir -p "$d" ) || return 1
    fi
    echo "$d"
}

# copies_dir_of <fichero de ~/nexum-backups>: crea su carpeta (como copies_in)
function copies_dir_of() {
    local rel=${1#"$COPIES_DIR"/}
    copies_in "$(dirname "$rel")" > /dev/null
}

# Lo que habia suelto en ~/nexum-backups (hasta la 1.57.50), a su carpeta. Solo lo que se reconoce, sin
# sobrescribir nada y sin borrar nada; lo que no se puede mover (de root) se queda donde esta. Solo cuando
# ha cambiado algo en ~/nexum-backups desde la ultima vez (la fecha de la carpeta)
COPIES_SORT_PY='
import os, re, sys
base, lists = sys.argv[1:3]
F = r"(\d{8}-\d{6})"
V = r"([0-9][0-9A-Za-z._]*)"
RULES = [
    (r"hosts-" + F, "sistema/hosts/{0}"),
    (r"httpd-vhosts\.conf-" + F, "sistema/vhosts/{0}"),
    (r"httpd-vhosts-de-lampp-.+-" + F + r"\.conf", "sistema/vhosts/{0}"),
    (r"((?:lampp|XAMPP)-" + V + r")-mysql-sistema-" + F + r"\.sql\.gz", "bbdd/{1}/mysql-sistema-{3}.sql.gz"),
    (r"((?:lampp|XAMPP)-" + V + r")-bases-" + F + r"\.tar\.gz", "bbdd/{1}/todas-las-bases-{3}.tar.gz"),
    (r"((?:lampp|XAMPP)-" + V + r")-(.+)-(antes-de-cargar|antes-de-copiar)-" + F + r"\.sql\.gz",
     "bbdd/{1}/{3}-{4}-{5}.sql.gz"),
    (r"((?:lampp|XAMPP)-" + V + r")-(.+)-" + F + r"\.sql\.gz", "bbdd/{1}/{3}-{4}.sql.gz"),
    (r"docker-.+-" + F + r"\.sql\.gz", "bbdd/docker/{0}"),
    (r"((?:lampp|XAMPP)-" + V + r")-(.+)-" + F, "sistema/{1}/{3}-{4}"),
    (r"(wp-config\.php|parameters\.php|parameters\.yml|settings\.inc\.php)-(.+)-" + F, "proyectos/{2}/{1}-{3}"),
    (r"(.+)-antes-de-actualizar-" + F, "proyectos/{1}/antes-de-actualizar-{2}"),
    (r"(.+)-cache-(dev|prod)-" + F, "proyectos/{1}/cache-{2}-{3}"),
    (r"((?:incompleta-)?XAMPP-oficial-" + F + r")", "xampp-oficial/{0}"),
]
NAME = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9 ._-]*$")
moved = 0
for name in sorted(os.listdir(base)):
    path = os.path.join(base, name)
    if os.path.islink(path) or name in ("bbdd", "proyectos", "sistema", "xampp-oficial"):
        continue
    dest = None
    m = re.fullmatch(r"(.+)-registro-" + F + r"-(.+)\.txt", name)
    if m:
        dest = os.path.join(lists, "%s-%s-%s.txt" % m.groups())
    else:
        for rx, to in RULES:
            m = re.fullmatch(rx, name)
            if m and all(NAME.match(g or "x") for g in m.groups()):
                dest = os.path.join(base, to.format(name, *m.groups()))
                break
    if dest is None or os.path.lexists(dest):
        continue
    try:
        os.makedirs(os.path.dirname(dest), mode=0o700, exist_ok=True)
        os.rename(path, dest)
        moved += 1
    except OSError:
        pass
if moved:
    print("Copias de seguridad ordenadas por carpetas en %s: %d" % (base, moved))
'
function copies_sort() {
    local stamp=$LOG_DIR/copias-ordenadas
    [ -d "$COPIES_DIR" ] && [ ! -L "$COPIES_DIR" ] && [ -O "$COPIES_DIR" ] && [ "$(id -u)" -ne 0 ] || return 0
    [ -f "$stamp" ] && [ ! "$COPIES_DIR" -nt "$stamp" ] && return 0
    mkdir -p -m 700 "$LOG_DIR" || return 0
    ( umask 077; python3 -I -c "$COPIES_SORT_PY" "$COPIES_DIR" "$LOG_DIR/listas" < /dev/null > /dev/null 2>&1 )
    touch "$stamp" 2> /dev/null
    return 0
}

# Lo que ocupa (en KB) dicho para personas: 3,4 MB
function copies_size_text() {
    awk -v n="${1:-0}" 'BEGIN {
        split("KB MB GB TB", u); i = 1
        while (n >= 1024 && i < 4) { n /= 1024; i++ }
        s = (i == 1) ? sprintf("%d %s", n, u[i]) : sprintf("%.1f %s", n, u[i])
        gsub(/\./, ",", s); print s
    }'
}

# ¿Hay en ~/nexum-backups carpetas que no son tuyas (copias que hizo root)? Lo de dentro solo se puede
# borrar con sudo
function copies_need_root() {
    [ -d "$COPIES_DIR" ] && [ ! -L "$COPIES_DIR" ] || return 1
    [ -n "$(find "$COPIES_DIR" -mindepth 1 -type d ! -user "$(id -u)" -print 2> /dev/null | head -1)" ]
}

# copias [vaciar]: sin nada, cuantos ficheros hay en ~/nexum-backups y cuanto ocupan. vaciar borra todo
# lo que hay dentro (la carpeta se queda), despues de comprobar que es una carpeta tuya y no un enlace.
# Lo que no se pueda borrar con tu usuario (copias que hizo root en una carpeta suya) se borra con
# sudo, solo dentro de esa carpeta y sin pasar a otros discos. Con --simular no se borra nada
function copies_command() {
    local dir=$COPIES_DIR files kb left
    case "$1" in
        ""|vaciar) ;;
        *) echo "Uso: nexum copias [vaciar]"; return 1 ;;
    esac
    if [ -L "$dir" ] || { [ -e "$dir" ] && [ ! -d "$dir" ]; }; then
        echo "$dir no es una carpeta (es un enlace o un fichero): no se toca"
        return 1
    fi
    if [ ! -d "$dir" ]; then
        echo "No hay copias de seguridad: $dir no existe"
        return 0
    fi
    if [ ! -O "$dir" ]; then
        echo "$dir no es tuya: no se toca"
        return 1
    fi
    files=$(find "$dir" -mindepth 1 -type f 2> /dev/null | wc -l | tr -d ' ')
    kb=$(du -sk "$dir" 2> /dev/null | cut -f1)
    if [ "$1" != vaciar ]; then
        echo "Copias de seguridad en $dir: $files $([ "$files" == 1 ] && echo fichero || echo ficheros), $(copies_size_text "${kb:-0}")"
        return 0
    fi
    if [ -z "$(find "$dir" -mindepth 1 -maxdepth 1 2> /dev/null | head -1)" ]; then
        echo "No hay copias de seguridad que borrar: $dir esta vacia"
        return 0
    fi
    echo "Borrando las copias de seguridad de $dir ($files $([ "$files" == 1 ] && echo fichero || echo ficheros), $(copies_size_text "${kb:-0}"))..."
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] find $dir -xdev -mindepth 1 -delete (la carpeta se queda)"
        return 0
    fi
    # (find -delete no sigue los enlaces: un enlace de dentro se borra, no lo que hay al otro lado)
    find "$dir" -xdev -mindepth 1 -delete 2> /dev/null
    left=$(find "$dir" -mindepth 1 -maxdepth 1 2> /dev/null | head -1)
    if [ -n "$left" ] && [ -n "$SUDO" ]; then
        echo "Algunas copias son de root: se borran con sudo (solo dentro de $dir)"
        # (se vuelve a comprobar justo antes: que sigue siendo tu carpeta y no un enlace)
        if [ -L "$dir" ] || [ ! -d "$dir" ] || [ ! -O "$dir" ]; then
            echo "$dir ha cambiado: no se borra nada mas"
            return 1
        fi
        sudo find "$dir" -xdev -mindepth 1 -delete
        left=$(find "$dir" -mindepth 1 -maxdepth 1 2> /dev/null | head -1)
    fi
    if [ -n "$left" ]; then
        echo "No se ha podido borrar todo: queda, por ejemplo, $left"
        return 1
    fi
    echo "Copias de seguridad borradas ($dir esta vacia)"
}

# copias-ficheros [si|no]: las copias de los ficheros que el programa cambia por su cuenta (el de hosts,
# los vhosts, la configuracion de los proyectos al cargarlos, lo que cambia asegurar), en ~/nexum-backups
# antes de cambiarlos. Es el fichero COPIES_FILES_FLAG: si esta, se guardan; si no (lo de partida), no.
# Sin nada, dice como esta. No pide contraseña
function copies_files_command() {
    case "$1" in
        "")
            if [ -f "$COPIES_FILES_FLAG" ]; then
                echo "Copias de los ficheros que cambia el programa: si (en ~/nexum-backups, antes de cambiarlos)"
            else
                echo "Copias de los ficheros que cambia el programa: no (con nexum copias-ficheros si, se guardan)"
            fi
            ;;
        si)
            if [ "$DRY" -eq 1 ]; then
                echo "  [simulacion] se crearia $COPIES_FILES_FLAG"
                return 0
            fi
            mkdir -p -m 700 "$LOG_DIR" || return 1
            # (un enlace en su lugar no se sigue: se quita y se crea el fichero)
            [ -L "$COPIES_FILES_FLAG" ] && rm -f "$COPIES_FILES_FLAG"
            [ -f "$COPIES_FILES_FLAG" ] || ( umask 077; : > "$COPIES_FILES_FLAG" ) || return 1
            echo "Copias de los ficheros que cambia el programa: si (en ~/nexum-backups, antes de cambiarlos)"
            ;;
        no)
            if [ "$DRY" -eq 1 ]; then
                echo "  [simulacion] se quitaria $COPIES_FILES_FLAG"
                return 0
            fi
            rm -f "$COPIES_FILES_FLAG" || return 1
            echo "Copias de los ficheros que cambia el programa: no"
            ;;
        *) echo "Uso: nexum copias-ficheros [si|no]"; return 1 ;;
    esac
}
