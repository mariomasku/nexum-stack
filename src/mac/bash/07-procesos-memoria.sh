# ===========================================================================
# Procesos en memoria: solo los de la version montada
# ===========================================================================
# Cada version arranca sus programas con su ruta real (/Applications/XAMPP-8.4/xamppfiles/...), y
# el XAMPP oficial con /Applications/XAMPP/xamppfiles. Si al parar una version algo se queda vivo,
# sigue en memoria aunque se monte otra. De que version es cada proceso se sabe por, en este orden:
#   - los .pid de cada version (Apache, MariaDB, ProFTPD, PHP-FPM),
#   - la ruta en su orden,
#   - la de su proceso hijo o padre (mariadbd-safe y mariadbd, trabajadores de Apache y PHP-FPM),
#   - y si solo pone /Applications/XAMPP/: de la montada si arranco despues de montarla.
# Sin sudo, macOS no enseña la orden completa de los procesos de otros usuarios (root): por eso la
# lista para cerrar se hace con sudo. (LVM_PS solo para pruebas: fichero con la salida de ps)

# P|pid|padre|usuario|version|sobra (1/0)|nombre|de Docker (1/0). Sobran los que no son de la version
# montada (todos si no hay ninguna), salvo la MariaDB de una version que usa en vivo un proyecto de
# Docker (en su puerto, apuntada en LAMPP_BD_MARK_DIR): esa no se cierra ni al parar XAMPP-X. Con
# --sudo, ps con sudo (orden completa de todos los procesos).
function lampp_processes() {
    local out ids=""
    # ids: solo los numeros (sin la orden, que la elige cada proceso y puede llevar saltos de linea
    # con una linea falsa dentro), antes que la lista completa
    if [ -n "$LVM_PS" ]; then
        out=$(cat "$LVM_PS")
    elif [ "$1" == "--sudo" ] && [ "$DRY" -eq 0 ]; then
        ids=$($SUDO ps -axo pid=) || return 0
        out=$($SUDO ps -axww -o pid=,ppid=,user=,lstart=,command=)
    else
        ids=$(ps -axo pid=) || return 0
        out=$(ps -axww -o pid=,ppid=,user=,lstart=,command=)
    fi
    # (con las carpetas donde puede haber versiones: BASE_DIR y, de antes de la 1.39.3, /Applications)
    LVM_PS_IDS=$ids LVM_PS_OUT=$out LVM_BD_MARCAS=$LAMPP_BD_MARK_DIR python3 -I - "$LINK" "$BASE_DIR" "$APPS_DIR" "$LEGACY_DIR" <<'EOF'
import glob, os, re, sys, time
link, base = sys.argv[1:3]
marks = os.environ.get("LVM_BD_MARCAS", "")
bases = []
for b in [base] + sys.argv[3:]:
    if b and b not in bases:
        bases.append(b)
active, link_time = "", 0
if os.path.islink(link):
    active = os.path.basename(os.path.realpath(link))[len("XAMPP-"):]
    link_time = os.lstat(link).st_mtime
official = os.path.isdir(link) and not os.path.islink(link)

by_pidfile = {}
for d in [d for b in bases for d in glob.glob(os.path.join(b, "XAMPP-*"))]:
    # (los enlaces de las versiones de antes de la 1.39.3 llevan a la misma carpeta: una vez)
    if os.path.islink(d):
        continue
    ver = os.path.basename(d)[len("XAMPP-"):]
    for rel in ("logs/httpd.pid", "var/mysql/mysqld.pid", "var/proftpd/proftpd.pid",
                "var/run/php-fpm.pid", "var/mysql/*.pid", "var/proftpd.pid"):
        for f in glob.glob(os.path.join(d, "xamppfiles", rel)):
            # Solo .pid de root: los de daemon o mysql los podria escribir ese usuario (o MariaDB
            # con INTO OUTFILE) para que se cerrara un proceso de la version montada
            try:
                fd = os.open(f, os.O_RDONLY | os.O_NOFOLLOW)
                with os.fdopen(fd) as fh:
                    if os.fstat(fh.fileno()).st_uid == 0:
                        by_pidfile[int(fh.read(64).split()[0])] = ver
            except (OSError, ValueError, IndexError):
                pass

NAMES = {"httpd", "mariadbd", "mysqld", "mariadbd-safe", "mysqld_safe", "proftpd", "php-fpm"}
rx = re.compile("(?:" + "|".join(re.escape(b) for b in bases) + r")/XAMPP(-[^/\s)|]+)?/xamppfiles/")
def clean(s):
    return re.sub(r"[\x00-\x1f\x7f-\x9f|]", "?", s)
procs = {}
seen = {}
for line in os.environ.get("LVM_PS_OUT", "").splitlines():
    f = line.split(None, 8)
    if len(f) < 9 or not f[0].isdigit() or not f[1].isdigit():
        continue
    try:
        start = time.mktime(time.strptime(" ".join(f[3:8]), "%a %b %d %H:%M:%S %Y"))
    except ValueError:
        start = 0
    seen[int(f[0])] = seen.get(int(f[0]), 0) + 1
    procs[int(f[0])] = {"ppid": int(f[1]), "user": f[2], "start": start, "cmd": f[8]}
# Una orden con un salto de linea puede fingir otra linea con el numero de otro proceso (que despues
# se cerraria con sudo kill): solo valen los numeros que existen y salen en una sola linea
if os.environ.get("LVM_PS_IDS"):
    ids = {int(x) for x in os.environ["LVM_PS_IDS"].split() if x.isdigit()}
    procs = {pid: p for pid, p in procs.items() if pid > 1 and pid in ids and seen[pid] == 1}

def name_of(cmd):
    if cmd.startswith("php-fpm:"):
        return "php-fpm"
    if cmd.startswith("proftpd:"):
        return "proftpd"
    first = cmd.strip("()").split()[0] if cmd.strip("()") else ""
    n = os.path.basename(first)
    if n in ("sh", "bash") and len(cmd.split()) > 1:
        n = os.path.basename(cmd.split()[1])
    return n

# Un .pid lo puede escribir el usuario de su servicio: solo se cree si el proceso es un programa de
# XAMPP (nunca el 1 ni otro del sistema, que se cerraria con sudo kill) y su orden no dice ya de que
# version es (si no, bastaria escribir el de la version montada en otra para que se cerrara)
by_pidfile = {pid: v for pid, v in by_pidfile.items()
              if pid > 1 and pid in procs and name_of(procs[pid]["cmd"]) in NAMES
              and not rx.search(procs[pid]["cmd"])}

def own(pid):
    """None si no es de ningun XAMPP; si lo es, su version ('' si solo /Applications/XAMPP/)."""
    p = procs[pid]
    if pid in by_pidfile:
        return by_pidfile[pid]
    if name_of(p["cmd"]) not in NAMES:
        return None
    m = rx.search(p["cmd"])
    if m:
        return (m.group(1) or "-")[1:]
    return None

lampp = {}
for pid in procs:
    v = own(pid)
    if v is not None:
        lampp[pid] = v
changed = True
while changed:
    changed = False
    for pid, p in procs.items():
        if pid in lampp:
            continue
        # Hijos (trabajadores) y padres vigilantes (mariadbd-safe de un mariadbd conocido). Solo
        # programas de XAMPP: nunca un sh o bash cualquiera (podria ser este mismo script)
        if name_of(p["cmd"]) not in NAMES:
            continue
        if (p["ppid"] > 1 and p["ppid"] in lampp) or any(c["ppid"] == pid for q, c in procs.items() if q in lampp):
            lampp[pid] = ""
            changed = True

def version(pid, seen=()):
    if by_pidfile.get(pid):
        return by_pidfile[pid]
    v = lampp[pid]
    if v:
        return v
    near = [procs[pid]["ppid"]] + [q for q, c in procs.items() if c["ppid"] == pid]
    for q in near:
        if q in lampp and q not in seen:
            r = version(q, seen + (pid,))
            if r != "?":
                return r
    if lampp[pid] == "" and rx.search(procs[pid]["cmd"]) and official:
        return "oficial"
    if active and procs[pid]["start"] >= link_time - 1:
        return active
    return "?"

for pid in sorted(lampp):
    p = procs[pid]
    v = version(pid)
    # El XAMPP oficial en su sitio (sin apartar) no sobra: es el que esta en uso
    extra = v != active and not (v == "oficial" and official)
    # La MariaDB que usa Docker: en el puerto apuntado para su version
    port = ""
    if marks and v not in ("", "?", "oficial"):
        try:
            port = open(os.path.join(marks, v)).read(10).strip()
        except OSError:
            port = ""
    for_docker = (name_of(p["cmd"]) in ("mariadbd", "mysqld") and port.isdigit()
                  and ("--port=%s" % port) in p["cmd"].split())
    print("P|%d|%d|%s|%s|%d|%s|%d" % (pid, p["ppid"], clean(p["user"]), clean(v), int(extra and not for_docker),
                                      clean(name_of(p["cmd"])), int(for_docker)))
EOF
}

# Resumen de los procesos que sobran: «XAMPP-8.4: httpd ×3, mariadbd; version anterior: ...»
function stray_summary() {
    lampp_processes | awk -F'|' '$6 == 1 {
        v = ($5 == "?") ? "version anterior" : ($5 == "oficial" ? "XAMPP oficial" : "XAMPP-" $5)
        n[v "|" $7]++; if (!(v in seen)) { seen[v] = 1; order[++k] = v }
    } END {
        for (i = 1; i <= k; i++) {
            out = ""
            for (key in n) { split(key, f, "|"); if (f[1] == order[i]) out = out (out ? ", " : "") f[2] (n[key] > 1 ? " ×" n[key] : "") }
            printf "%s%s: %s", (i > 1 ? "; " : ""), order[i], out
        }
    }'
}

# cerrar-procesos [--todos]: cierra los procesos que no son de la version montada (con --todos,
# tambien los de la montada: justo despues de pararla o desmontarla). Les da unos segundos por si
# estan terminando solos; despues TERM empezando por los vigilantes (mariadbd-safe volveria a
# arrancar MariaDB) y, a los que sigan, KILL (a MariaDB se le dan hasta 90 s para guardar).
function close_processes() {
    local all=$1 list pids wait
    function _stray() {
        lampp_processes --sudo | awk -F'|' -v all="$all" '$8 != 1 && ($6 == 1 || all == "--todos")'
    }
    list=$(_stray)
    [ -z "$list" ] && return 0
    if [ "$all" == "--todos" ] && [ "$DRY" -eq 0 ]; then
        for wait in $(seq 1 15); do
            sleep 1
            list=$(_stray)
            [ -z "$list" ] && return 0
        done
    fi
    echo "Procesos de XAMPP que siguen en memoria y no deberian:"
    awk -F'|' '{ printf "  %s (%s, pid %s, %s)\n", $7, ($5 == "?" ? "version anterior" : ($5 == "oficial" ? "XAMPP oficial" : "XAMPP-" $5)), $2, $4 }' <<< "$list"
    pids=$(awk -F'|' '$7 ~ /^(mariadbd-safe|mysqld_safe)$/ { print $2 }' <<< "$list")
    pids="$pids $(awk -F'|' '$7 !~ /^(mariadbd-safe|mysqld_safe)$/ { print $2 }' <<< "$list")"
    pids=$(kill_pids $pids)
    [ -z "$pids" ] && return 1
    echo "Cerrandolos..."
    run $SUDO kill -TERM $pids 2> /dev/null
    [ "$DRY" -eq 1 ] && return 0
    for wait in $(seq 1 90); do
        sleep 1
        list=$(_stray)
        [ -z "$list" ] && { close_done "$all"; return 0; }
        [ "$wait" -ge 15 ] && ! awk -F'|' '$7 ~ /^(mysqld|mariadbd)$/ { f = 1 } END { exit !f }' <<< "$list" && break
        [ "$wait" -eq 15 ] && echo "Esperando a que MariaDB termine de guardar y se cierre..."
    done
    pids=$(kill_pids $(awk -F'|' '{ print $2 }' <<< "$list"))
    [ -z "$pids" ] && return 1
    echo "Forzando el cierre de: $pids"
    $SUDO kill -KILL $pids 2> /dev/null
    sleep 1
    list=$(_stray)
    if [ -n "$list" ]; then
        echo "No se han podido cerrar:"
        awk -F'|' '{ printf "  %s (pid %s)\n", $7, $2 }' <<< "$list"
        return 1
    fi
    close_done "$all"
}

# Solo numeros de proceso de verdad (sin signo, ni 0 ni 1) antes de pasarlos a sudo kill: un -1
# cerraria todos los procesos del equipo. kill_pids <pid>...
function kill_pids() {
    local p out=""
    for p in "$@"; do
        [[ "$p" =~ ^[1-9][0-9]{0,9}$ ]] && [ "$p" -gt 1 ] && out="$out $p"
    done
    echo "${out# }"
}

function close_done() {
    if [ "$1" == "--todos" ]; then
        echo "Cerrados: no queda ningun proceso de XAMPP en memoria."
    else
        echo "Cerrados: solo queda en memoria la version montada."
    fi
}

function list_versions() {
    echo "Estas son las versiones disponibles"

    version_dirs
}

