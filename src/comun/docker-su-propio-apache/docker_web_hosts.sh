# Lineas de /etc/hosts de los dominios de Docker: docker_web_hosts poner|quitar <dominio...>. poner: a la
# direccion del Apache de Docker (y fuera de cualquier otra linea); quitar: fuera. Solo esos dominios
function docker_web_hosts() {
    local mode=$1 copy rc n names=()
    shift
    # (con el DNS comodin, los *.docker.test los contesta el; solo se tocan los de antes)
    for n in "$@"; do
        docker_dns_on && [[ "$n" == *.docker.test ]] && continue
        names+=("$n")
    done
    set -- "${names[@]}"
    [ $# -gt 0 ] || return 0
    mkdir -p -m 700 "$LOG_DIR" || return 1
    copy=$(mktemp "$LOG_DIR/hosts-docker-XXXXXX") || return 1
    python3 -I - "$HOSTS_FILE" "$copy" "$mode" "$(docker_web_get IP)" "$@" << 'EOF'
import re, sys
src, dst, mode, ip = sys.argv[1:5]
names = [n.lower() for n in sys.argv[5:]]
lines = open(src).read().splitlines()
now = {}
for line in lines:
    w = line.split("#", 1)[0].split()
    for n in w[1:]:
        now.setdefault(n.lower(), w[0])
if mode == "poner" and all(now.get(n) == ip for n in names):
    out = lines
else:
    out = []
    for line in lines:
        body, sep, comment = line.partition("#")
        w = body.split()
        if len(w) >= 2 and re.match(r"^(127\.\d+\.\d+\.\d+|::1)$", w[0]):
            keep = [n for n in w[1:] if n.lower() not in names]
            if len(keep) != len(w) - 1:
                if not keep:
                    continue
                line = w[0] + " " + " ".join(keep) + (" " + sep + comment if sep else "")
        out.append(line)
    if mode == "poner":
        out.append(ip + " " + " ".join(names))
open(dst, "w").write("\n".join(out) + "\n")
EOF
    if cmp -s "$copy" "$HOSTS_FILE"; then
        rm -f "$copy"
        return 0
    fi
    edit_hosts --aplicar "$copy"
    rc=$?
    rm -f "$copy"
    return $rc
}

