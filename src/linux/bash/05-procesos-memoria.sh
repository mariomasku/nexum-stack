# ===========================================================================
# Procesos en memoria: solo los de la version montada
# ===========================================================================
# Todos los LAMPP se arrancan por el enlace /opt/lampp, asi que sus procesos se llaman igual
# ("/opt/lampp/bin/httpd", "/opt/lampp/sbin/mysqld"...) sea cual sea la version. Si al parar una
# version algo se queda vivo (el lampp de XAMPP solo cierra lo que encuentra en sus .pid), sigue en
# memoria aunque se monte otra. De que version es cada proceso se sabe por, en este orden:
#   - la ruta real en su orden (/opt/lampp-8.4/...) o en el .pid de una version (httpd, proftpd,
#     php-fpm, mariadb),
#   - la de su proceso padre (los hijos de Apache, PHP-FPM, ProFTPD y mysqld_safe),
#   - y si solo pone /opt/lampp/: es de la version montada si arranco despues de montarla (el
#     enlace se crea al montar), y si no, de una version anterior.
# (LVM_ENLACE solo para pruebas: sin LVM_PRUEBA no se hace caso)
LAMPP_LINK=/opt/lampp
[ -n "$TEST_DIR" ] && [ -n "$LVM_ENLACE" ] && LAMPP_LINK=$LVM_ENLACE

# P|pid|padre|usuario|version|sobra (1/0)|nombre|de Docker (1/0). Sobran los que no son de la version
# montada (todos si no hay ninguna), salvo la MariaDB de una version que usa en vivo un proyecto de
# Docker (sin red, apuntada en LAMPP_BD_MARK_DIR): esa no se cierra ni al parar LAMPP
function lampp_processes() {
    python3 -I - "$LAMPP_LINK" "$LAMPP_BD_MARK_DIR" <<'EOF'
import glob, os, pwd, re, sys
link = sys.argv[1]
marks = sys.argv[2] if len(sys.argv) > 2 else ""
base = os.path.dirname(link)
active, link_time = "", 0
if os.path.islink(link):
    active = os.path.basename(os.path.realpath(link))[len("lampp-"):]
    link_time = os.lstat(link).st_mtime
btime = 0
for line in open("/proc/stat"):
    if line.startswith("btime"):
        btime = int(line.split()[1])
hz = os.sysconf("SC_CLK_TCK")

# .pid de cada version (los de MariaDB de XAMPP no se pueden leer sin ser root: los sustituye la
# regla del padre, mysqld_safe)
by_pidfile = {}
for d in glob.glob(os.path.join(base, "lampp-*")):
    ver = os.path.basename(d)[len("lampp-"):]
    for rel in ("logs/httpd.pid", "var/proftpd.pid", "var/proftpd/proftpd.pid",
                "var/run/php-fpm.pid", "logs/php-fpm.pid", "var/mysql/*.pid"):
        for f in glob.glob(os.path.join(d, rel)):
            # Solo .pid de root: los de daemon o mysql los podria escribir ese usuario (o MariaDB
            # con INTO OUTFILE) para que se cerrara un proceso de la version montada
            try:
                fd = os.open(f, os.O_RDONLY | os.O_NOFOLLOW)
                with os.fdopen(fd) as fh:
                    if os.fstat(fh.fileno()).st_uid == 0:
                        by_pidfile[int(fh.read(64).split()[0])] = ver
            except (OSError, ValueError, IndexError):
                pass

rx = re.compile(re.escape(link) + r"(-[^/\s)|]+)?/")
def clean(s):
    return re.sub(r"[\x00-\x1f\x7f-\x9f|]", "?", s)
procs = {}
for p in os.listdir("/proc"):
    if not p.isdigit():
        continue
    try:
        argv = open("/proc/%s/cmdline" % p, "rb").read().split(b"\0")
        argv = [a.decode("utf-8", "replace") for a in argv if a]
        stat = open("/proc/%s/stat" % p).read()
        uid = os.stat("/proc/%s" % p).st_uid
    except OSError:
        continue
    if not argv:
        continue
    fields = stat[stat.rindex(")") + 2:].split()
    procs[int(p)] = {"argv": argv, "ppid": int(fields[1]),
                     "start": btime + int(fields[19]) / hz, "uid": uid}

# Programas de LAMPP. Un .pid lo puede escribir el usuario con el que corre su servicio (daemon,
# mysql): solo se cree si el proceso es uno de estos (nunca el 1 ni otro programa del sistema, que
# se cerraria con sudo kill) y no dice ya en su ruta de que version es
NAMES = {"httpd", "mysqld", "mariadbd", "mysqld_safe", "mariadbd-safe", "proftpd", "php-fpm"}
def name_of(argv):
    a0 = argv[0]
    if a0.startswith("php-fpm:"):
        return "php-fpm"
    if a0.startswith("proftpd:"):
        return "proftpd"
    n = os.path.basename(a0.split()[0]) if a0.split() else ""
    if n in ("sh", "bash", "dash", "perl") and len(argv) > 1:
        n = os.path.basename(argv[1])
    return n
by_pidfile = {pid: v for pid, v in by_pidfile.items()
              if pid > 1 and pid in procs and name_of(procs[pid]["argv"]) in NAMES
              and not rx.match(procs[pid]["argv"][0])}

def own(pid):
    """None si no es de ningun LAMPP; si lo es, la version de su ruta ('' si solo /opt/lampp/)."""
    a = procs[pid]["argv"]
    # El propio programa (o el script que ejecuta sh/perl) esta en un LAMPP; PHP-FPM cambia su
    # nombre a «php-fpm: master process (/opt/lampp-8.4/php/etc/php-fpm.conf)»
    cands = [a[0]]
    if os.path.basename(a[0]) in ("sh", "bash", "dash", "perl") and len(a) > 1:
        cands.append(a[1])
    if a[0].startswith("php-fpm: master process"):
        cands.append(a[0][a[0].find("(") + 1:])
    for c in cands:
        m = rx.match(c)
        if m:
            return (m.group(1) or "-")[1:]
    if pid in by_pidfile:
        return by_pidfile[pid]
    return None

lampp = {}
for pid in procs:
    v = own(pid)
    if v is not None:
        lampp[pid] = v
# Hijos (trabajadores de Apache, PHP-FPM y ProFTPD, mysqld de mysqld_safe), aunque se llamen distinto
changed = True
while changed:
    changed = False
    for pid, p in procs.items():
        # Solo programas de LAMPP (trabajadores con otro nombre: «php-fpm: pool», «proftpd: ...»)
        if pid not in lampp and p["ppid"] > 1 and p["ppid"] in lampp and name_of(p["argv"]) in NAMES:
            lampp[pid] = ""
            changed = True

def version(pid, seen=()):
    if by_pidfile.get(pid):
        return by_pidfile[pid]
    v = lampp[pid]
    if v:
        return v
    parent = procs[pid]["ppid"]
    if parent in lampp and parent not in seen:
        return version(parent, seen + (pid,))
    # Solo /opt/lampp/: de la montada si arranco despues de montarla
    if active and procs[pid]["start"] >= link_time - 1:
        return active
    return "?"

for pid in sorted(lampp):
    p = procs[pid]
    v = version(pid)
    try:
        user = pwd.getpwuid(p["uid"]).pw_name
    except KeyError:
        user = str(p["uid"])
    a0 = p["argv"][0]
    name = a0.split(":")[0] if ":" in a0 and not a0.startswith("/") else os.path.basename(a0)
    if name in ("sh", "bash", "dash", "perl") and len(p["argv"]) > 1:
        name = os.path.basename(p["argv"][1])
    # La MariaDB que usa Docker: sin red, con el socket de su version y apuntada
    for_docker = (name in ("mysqld", "mariadbd") and "--skip-networking" in p["argv"] and v not in ("", "?")
                  and "--socket=%s/lampp-%s/var/mysql/mysql.sock" % (base, v) in p["argv"]
                  and bool(marks) and os.path.isfile(os.path.join(marks, v)))
    # Cualquier proceso elige su propio nombre: sin saltos de linea ni «|», que meterian lineas o
    # campos falsos (un pid que despues se cierra con sudo kill)
    print("P|%d|%d|%s|%s|%d|%s|%d" % (pid, p["ppid"], clean(user), clean(v), int(v != active and not for_docker),
                                      clean(name or a0), int(for_docker)))
EOF
}

# Resumen de los procesos que sobran: «lampp-8.4: httpd ×3, mysqld; version anterior: ...»
function stray_summary() {
    lampp_processes | awk -F'|' '$6 == 1 {
        v = ($5 == "?") ? "version anterior" : "lampp-" $5
        n[v "|" $7]++; if (!(v in seen)) { seen[v] = 1; order[++k] = v }
    } END {
        for (i = 1; i <= k; i++) {
            out = ""
            for (key in n) { split(key, f, "|"); if (f[1] == order[i]) out = out (out ? ", " : "") f[2] (n[key] > 1 ? " ×" n[key] : "") }
            printf "%s%s: %s", (i > 1 ? "; " : ""), order[i], out
        }
    }'
}

# cerrar-procesos [--todos]: cierra los procesos de LAMPP que no son de la version montada (con
# --todos, tambien los de la montada: se usa justo despues de pararla o desmontarla). Primero les da
# unos segundos por si estan terminando solos; despues TERM (MariaDB y Apache se cierran bien con
# el) empezando por los vigilantes (mysqld_safe volveria a arrancar mysqld), y KILL a los que sigan.
function close_processes() {
    local all=$1 list pids wait sure
    function _stray() {
        lampp_processes | awk -F'|' -v all="$all" '$8 != 1 && ($6 == 1 || all == "--todos")'
    }
    list=$(_stray)
    [ -z "$list" ] && return 0
    if [ "$all" == "--todos" ] && [ "$DRY" -eq 0 ]; then
        for wait in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
            sleep 1
            list=$(_stray)
            [ -z "$list" ] && return 0
        done
    fi
    echo "Procesos de LAMPP que siguen en memoria y no deberian:"
    awk -F'|' '{ printf "  %s (%s, pid %s, %s)\n", $7, ($5 == "?" ? "version anterior" : "lampp-" $5), $2, $4 }' <<< "$list"
    # Primero los vigilantes que vuelven a arrancar lo que se cierra
    pids=$(awk -F'|' '$7 ~ /^(mysqld_safe|mariadbd-safe)$/ { print $2 }' <<< "$list")
    pids="$pids $(awk -F'|' '$7 !~ /^(mysqld_safe|mariadbd-safe)$/ { print $2 }' <<< "$list")"
    pids=$(kill_pids $pids)
    [ -z "$pids" ] && return 1
    echo "Cerrandolos..."
    run sudo kill -TERM -- $pids 2> /dev/null
    [ "$DRY" -eq 1 ] && return 0
    # 15 s; MariaDB, hasta 90 s (con TERM guarda todo antes de salir: no se le corta a medias)
    for wait in $(seq 1 90); do
        sleep 1
        list=$(_stray)
        [ -z "$list" ] && { close_done "$all"; return 0; }
        [ "$wait" -ge 15 ] && ! awk -F'|' '$7 ~ /^(mysqld|mariadbd)$/ { f = 1 } END { exit !f }' <<< "$list" && break
        [ "$wait" -eq 15 ] && echo "Esperando a que MariaDB termine de guardar y se cierre..."
    done
    # Los que no han atendido a TERM (solo si siguen siendo los mismos procesos)
    sure=$(kill_pids $(awk -F'|' '{ print $2 }' <<< "$list"))
    [ -z "$sure" ] && return 1
    echo "Forzando el cierre de: $sure"
    sudo kill -KILL -- $sure 2> /dev/null
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
        echo "Cerrados: no queda ningun proceso de LAMPP en memoria."
    else
        echo "Cerrados: solo queda en memoria la version montada."
    fi
}

function list_lampp() {
    echo "Estas son las versiones disponibles"

    lampp_dirs
}

