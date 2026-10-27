#!/bin/bash
# Consumo de Nexum y sus servicios en el visor de arriba (Linux 1.56.2): qué procesos cuentan (LAMPP,
# Docker sin root, Mailpit, el túnel y la ventana, con sus hijos) y que la lectura de /proc da cifras.
# Uso: consumo.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-consumo.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
grep -q '^class UsageMeter:' "$SRC" || { echo "  ok    (sin consumo en el visor)"; exit 0; }
sed -n "/^    cat <<'LVM_GUI_PY'$/,/^LVM_GUI_PY$/p" "$SRC" | sed '1d;$d' > "$W/gui.py"
out=$(python3 -I - "$W/gui.py" << 'PY'
import ast, os, re, sys, time
tree = ast.parse(open(sys.argv[1], encoding="utf-8").read())
code = [ast.unparse(n) for n in tree.body if (isinstance(n, (ast.FunctionDef, ast.ClassDef)) and n.name in ("usage_group", "UsageMeter"))
        or (isinstance(n, ast.Assign) and any(getattr(t, "id", "") == "USAGE_GROUPS" for t in n.targets))]
g = {"os": os, "re": re, "time": time, "LOG_DIR": "/home/x/.lvm-instalador"}
exec("\n".join(code), g)
grp = g["usage_group"]
uid = os.getuid()
user = "0::/user.slice/user-%d.slice/user@%d.service" % (uid, uid)
def say(name, ok):
    print("%s|%s" % ("ok" if ok else "FALLA", name))
say("LAMPP: Apache, MariaDB y su mysqld_safe", grp(5, ["/opt/lampp/bin/httpd", "-k", "start"], "", 1) == "lampp"
    and grp(5, ["/opt/lampp-8.2.4/sbin/mysqld"], "", 1) == "lampp" and grp(5, ["/bin/sh", "/opt/lampp/bin/mysqld_safe"], "", 1) == "lampp")
say("Docker sin root: dockerd y cada contenedor (los de otro usuario, no)",
    grp(5, ["/usr/bin/dockerd"], user + "/app.slice/docker.service", 1) == "docker"
    and grp(5, ["mariadbd"], user + "/user.slice/docker-4d31.scope", 1) == "docker"
    and grp(5, ["mariadbd"], "0::/user.slice/user-9999.slice/user@9999.service/app.slice/docker.service", 1) is None)
say("Mailpit, el túnel y la propia ventana", grp(5, ["/opt/config/mailpit/mailpit", "--smtp"], "", 1) == "mailpit"
    and grp(5, ["python3", "-I", "-c", "x", "nexum-tunel", "/p"], "", 1) == "tunel"
    and grp(5, ["/home/x/.lvm-instalador/tunel/cloudflared", "tunnel"], "", 1) == "tunel" and grp(7, ["python3"], "", 7) == "ventana")
say("lo de otros programas no cuenta", grp(5, ["/usr/bin/firefox"], user + "/app.slice/app-firefox.scope", 1) is None
    and grp(5, ["/usr/sbin/mysqld"], "0::/system.slice/mysql.service", 1) is None)
m = g["UsageMeter"]()
first = m.sample()
time.sleep(0.3)
second = m.sample()
say("primera lectura sin CPU (no hay con qué comparar); después, con cifras",
    all(v[0] is None for v in first.values()) and all(v[0] is not None and v[0] >= 0 for v in second.values()))
say("la propia ventana cuenta con su memoria", second["ventana"][1] > 0 and m.total > 0)
PY
)
while IFS='|' read -r st name; do
    [ "$st" == ok ] && ok "$name" || bad "$name"
done <<< "$out"
check "ventana: CPU y RAM en la pastilla de arriba, cada 3 s y en segundo plano" 'grep -q "self.usage_lbl = label(\"CPU — · RAM —\"" "$SRC" && grep -q "GLib.timeout_add_seconds(3, self.nv_usage_tick)" "$SRC" && grep -q "threading.Thread(target=work, daemon=True).start()" "$SRC"'
exit $fail
