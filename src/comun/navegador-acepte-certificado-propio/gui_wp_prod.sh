# Para la ventana: G|dominio guardado de un WordPress o de una tienda (media-proyecto) y D|el de su base
# (en WordPress, home o siteurl de la tabla options, que el gestor no cambia: el local va en WP_HOME de
# wp-config.php; en una tienda, el de su shop_url, el mismo que ps-imagenes)
function gui_wp_prod() {
    local folder=$1 cfg db prefix url
    valid_project "$folder" > /dev/null || return 1
    echo "G|$(media_saved "$folder")"
    if is_prestashop "$folder"; then
        url=$(ps_domain "$folder" 2> /dev/null | tr 'A-Z' 'a-z')
        valid_domain "$url" && [[ "$url" != *.local && "$url" != *.test && "$url" != localhost && "$url" != *.localhost ]] && echo "D|$url"
        return 0
    fi
    cfg=$(wp_config_read "$HTDOCS_DIR/$folder/wp-config.php") || return 0
    db=$(sed -n 1p <<< "$cfg") prefix=$(sed -n 4p <<< "$cfg")
    [[ "$db" =~ ^[A-Za-z0-9_-]+$ ]] && [[ "$prefix" =~ ^[A-Za-z0-9_]*$ ]] || return 0
    if ! { [ -x "$DB_CLIENT" ] && db_base_table root "${MYSQL_PWD:-}" "$db" "${prefix}options"; }; then
        # (sin ella en la version activa: la de su proyecto del Apache de Docker, si lo hay)
        local p
        for p in $(docker_web_projects 2> /dev/null); do
            [ "$(docker_conf "$p" CARPETA)" == "$folder" ] || continue
            docker_ready || return 0
            url=$(docker_maria_sql "$(docker_conf "$p" MARIADB)" -N -e "SELECT option_value FROM \`$(docker_conf "$p" BBDD)\`.\`${prefix}options\`
                WHERE option_name IN ('home', 'siteurl') ORDER BY option_name = 'home' DESC LIMIT 1" < /dev/null 2> /dev/null | tr -d '\r')
            url=$(tr 'A-Z' 'a-z' <<< "$url" | sed -E 's|^https?://||; s|[/:?#].*$||')
            valid_domain "$url" && [[ "$url" != *.local && "$url" != *.test && "$url" != localhost && "$url" != *.localhost ]] && echo "D|$url"
        done
        return 0
    fi
    url=$("${DB_SAFE[@]}" "$DB_CLIENT" -uroot -N -e "SELECT option_value FROM \`$db\`.\`${prefix}options\`
        WHERE option_name IN ('home', 'siteurl') ORDER BY option_name = 'home' DESC LIMIT 1" < /dev/null 2> /dev/null)
    url=$(tr 'A-Z' 'a-z' <<< "$url" | sed -E 's|^https?://||; s|[/:?#].*$||')
    valid_domain "$url" && [[ "$url" != *.local && "$url" != localhost && "$url" != *.localhost ]] && echo "D|$url"
    return 0
}

# ps-imagenes <carpeta>: descarga de la web real las imagenes de una tienda PrestaShop que faltan en
# img (productos, categorias y marcas, con sus miniaturas; la lista sale de su base). La tienda se ve
# con su dominio real falseado, asi que una redireccion no sirve: se descargan por https resolviendo
# el dominio con DNS cifrado (PS_IMAGES_DOH, sin /etc/hosts) y comprobando su certificado de
# verdad. Cada fichero va a una carpeta temporal y solo pasa a img si ha llegado entero (200); sin
# seguir redirecciones y como mucho 30 MB por fichero. Lo que ya esta en local no se toca
PS_IMAGES_DOH="https://cloudflare-dns.com/dns-query"

# ps_images_resolve <dominio>: sus direcciones de verdad (separadas por comas, IPv6 entre corchetes),
# preguntadas una sola vez al DNS cifrado (PS_IMAGES_DOH) y nunca al del sistema: con el dominio
# falseado en /etc/hosts, el sistema diria 127.0.0.1. Hasta la 1.57.15 cada curl las preguntaba con
# --doh-url, y el curl 8.5 de Ubuntu 24.04 se cuelga o se cae con --doh-url y --parallel juntos (en
# un lote de 300 no devolvia nada y la tarea no avanzaba). Ninguna de este equipo ni de una red
# privada: si el DNS cifrado no contesta o solo da esas, falla (no se prueba con el del sistema)
function ps_images_resolve() {
    local domain=$1 type out ips=""
    for type in A AAAA; do
        out=$(curl -s --proto =https --max-redirs 0 --connect-timeout 15 --max-time 30 \
            -H "accept: application/dns-json" "$PS_IMAGES_DOH?name=$domain&type=$type" 2> /dev/null) || continue
        ips+=$(python3 -I -c '
import ipaddress, json, sys
try:
    data = json.loads(sys.stdin.read())
except ValueError:
    sys.exit(0)
want = 1 if sys.argv[1] == "A" else 28
for a in data.get("Answer") or []:
    if not isinstance(a, dict) or a.get("type") != want:
        continue
    try:
        ip = ipaddress.ip_address(str(a.get("data", "")).strip())
    except ValueError:
        continue
    if not ip.is_global:
        continue
    print(ip if ip.version == 4 else "[%s]" % ip)
' "$type" <<< "$out")$'\n'
    done
    ips=$(grep . <<< "$ips" | head -4 | paste -sd, -)
    [ -n "$ips" ] || return 1
    echo "$ips"
}

function ps_images() {
    local folder=${1%/} domain=$2 config db prefix t list total web="" maria="" p
    if [ -z "$folder" ]; then
        echo "Uso: nexum ps-imagenes <carpeta> [dominio de produccion]"

        return 1
    fi
    valid_project "$folder" || return 1
    is_prestashop "$folder" || { echo "$folder no es una tienda PrestaShop"; return 1; }
    command -v curl > /dev/null || { echo "Hace falta curl: sudo apt install curl"; return 1; }
    config=$(ps_config "$folder")
    db=${config%%|*} prefix=${config#*|}
    [ -n "$db" ] && [[ "$db$prefix" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "No se puede leer la BBDD de $folder (su parameters.php o settings.inc.php)"; return 1; }
    # La BBDD con la lista de imagenes: la de la version activa o, si no esta alli, la de su proyecto del
    # Apache de Docker (las imagenes van a su carpeta img, la misma con LAMPP y con Docker)
    for p in $(docker_web_projects 2> /dev/null); do
        [ "$(docker_conf "$p" CARPETA)" == "$folder" ] && web=$p
    done
    if { db_connect > /dev/null 2>&1 && db_exists "$db"; } || [ -z "$web" ]; then
        db_connect || return $?
        if ! db_exists "$db"; then
            echo "La BBDD de $folder ($db) no esta en lampp-$DB_FOLDER, la version activa: carga el proyecto"
            echo "en su version (o importa su BBDD en esta) y vuelve a intentarlo"

            return 1
        fi
        [ -n "$domain" ] || domain=$(ps_domain "$folder")
    else
        db=$(docker_conf "$web" BBDD) maria=$(docker_conf "$web" MARIADB)
        db_valid_name "$db" > /dev/null || { echo "$web no tiene una BBDD valida en su proyecto.conf"; return 1; }
        docker_ready || { echo "Docker no esta en marcha: arrancalo y vuelve a intentarlo"; return 1; }
        docker_maria_up "$maria" > /dev/null || { echo "La MariaDB $maria de Docker no responde"; return 1; }
        echo "Con la BBDD de la tienda en Docker ($db, MariaDB $maria)"
        [ -n "$domain" ] || domain=$(docker_conf "$web" PRODUCCION)
    fi
    domain=$(tr 'A-Z' 'a-z' <<< "$domain")
    domain=${domain#https://} domain=${domain#http://} domain=${domain%/}
    if ! valid_domain "$domain" || [[ "$domain" == *.local || "$domain" == *.test || "$domain" == localhost || "$domain" == *.localhost ]]; then
        echo "No se sabe el dominio de produccion de $folder: ${domain:-ninguno}. Dilo tu:"
        echo "nexum ps-imagenes $folder <dominio de produccion>"

        return 1
    fi
    # (en Docker, preguntas a su MariaDB comun; las dos, solo tablas de verdad)
    tbl() {
        if [ -n "$maria" ]; then
            [ "$(docker_maria_sql "$maria" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$db' AND table_name = '$1' AND table_type = 'BASE TABLE'" < /dev/null 2> /dev/null | tr -d '\r')" == 1 ]
        else
            db_base_table root "${MYSQL_PWD:-}" "$db" "$1"
        fi
    }
    # (solo tablas de verdad: una vista del volcado ejecutaria sus funciones como root)
    for t in image image_type; do
        tbl "$prefix$t" || { echo "La BBDD $db no tiene la tabla $prefix$t"; return 1; }
    done
    local sql=(db_root_sql -N -B)
    [ -n "$maria" ] && sql=(docker_maria_sql "$maria" -N -B)
    list=$( {
        "${sql[@]}" -e "SELECT 'I', id_image FROM \`$db\`.\`${prefix}image\`" < /dev/null
        "${sql[@]}" -e "SELECT 'T', name, products, categories, manufacturers FROM \`$db\`.\`${prefix}image_type\`" < /dev/null
        tbl "${prefix}category" \
            && "${sql[@]}" -e "SELECT 'C', id_category FROM \`$db\`.\`${prefix}category\` WHERE id_category > 2" < /dev/null
        tbl "${prefix}manufacturer" \
            && "${sql[@]}" -e "SELECT 'M', id_manufacturer FROM \`$db\`.\`${prefix}manufacturer\`" < /dev/null
    } 2> /dev/null | python3 -I -c '
import os, re, sys
root = sys.argv[1]
ids, types = {"I": [], "C": [], "M": []}, {"I": [], "C": [], "M": []}
for line in sys.stdin:
    f = line.rstrip("\n").split("\t")
    if f[0] in ids and len(f) == 2 and f[1].isdigit():
        ids[f[0]].append(int(f[1]))
    elif f[0] == "T" and len(f) == 5 and re.match(r"^[A-Za-z0-9_-]{1,64}$", f[1]):
        for k, col in (("I", 2), ("C", 3), ("M", 4)):
            if f[col] == "1":
                types[k].append(f[1])
for k, base in (("I", "img/p"), ("C", "img/c"), ("M", "img/m")):
    for i in sorted(set(ids[k])):
        d = base + "/" + "/".join(str(i)) if k == "I" else base
        for t in [""] + types[k]:
            rel = "%s/%d%s.jpg" % (d, i, "-" + t if t else "")
            if not os.path.isfile(os.path.join(root, rel)):
                print(rel)
' "$HTDOCS_DIR/$folder")
    total=$(grep -c . <<< "$list")
    if [ "$total" -eq 0 ]; then
        echo "A $folder no le falta ninguna imagen de productos, categorias ni marcas"

        return 0
    fi
    echo "A $folder le faltan $total imagenes: se descargan de https://$domain"
    echo "($domain se resuelve una vez con DNS cifrado, sin /etc/hosts aunque este falseado, y se comprueba su certificado)"
    if [ "$DRY" -eq 1 ]; then
        head -3 <<< "$list" | sed 's/^/  [simulacion] /'

        return 0
    fi
    # Las direcciones de la web real, una vez y del DNS cifrado: curl va a ellas con --resolve, que manda
    # sobre /etc/hosts (aunque el dominio siga falseado), y comprueba el certificado del dominio
    local ips
    if ! ips=$(ps_images_resolve "$domain"); then
        echo "El DNS cifrado ($PS_IMAGES_DOH) no da ninguna direccion publica de $domain: ¿sin conexion,"
        echo "o el dominio no existe? No se pregunta al DNS de este equipo (con el dominio falseado, daria"
        echo "este mismo equipo): vuelve a intentarlo cuando conteste"

        return 1
    fi
    echo "$domain esta en ${ips//,/, }"
    mkdir -p -m 700 "$LOG_DIR" || return 1
    # (las listas de una descarga cancelada se quedaban: fuera las de hace mas de un dia)
    find "$LOG_DIR" -maxdepth 1 -type f -name 'ps-imagenes-lista-*' -mmin +1440 -delete 2> /dev/null
    local file rc
    file=$(mktemp "$LOG_DIR/ps-imagenes-lista-XXXXXX") || return 1
    printf '%s\n' "$list" > "$file"
    python3 -I - "$HTDOCS_DIR/$folder" "$domain" "$ips" "$LOG_DIR" "$file" "$APP_NAME/$APP_VERSION" << 'EOF'
import os, shutil, signal, subprocess, sys, tempfile
root, domain, ips, logdir, listfile, agent = sys.argv[1:7]
rels = [l for l in open(listfile).read().split("\n") if l]
# (al cancelar la tarea se borra la carpeta temporal)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(130))
img = os.path.realpath(os.path.join(root, "img"))
got = gone = moved = blocked = seen = 0
stuck = ""
# El programa dice quien es (sin hacerse pasar por un navegador): si la web lo bloquea, se le da
# permiso en su servidor
agent = "%s (imagenes que faltan en una copia local)" % agent.replace(" ", "-")
with tempfile.TemporaryDirectory(dir=logdir, prefix="ps-imagenes-") as tmp:
    for start in range(0, len(rels), 300):
        batch = rels[start:start + 300]
        cfg = os.path.join(tmp, "curl.conf")
        with open(cfg, "w") as f:
            for n, rel in enumerate(batch):
                f.write('url = "https://%s/%s"\noutput = "%s/%d"\n' % (domain, rel, tmp, n))
        cmd = ["curl", "-s", "--parallel", "--parallel-max", "8", "-A", agent,
               "--proto", "=https", "--fail", "--max-redirs", "0", "--max-filesize", "30000000",
               "--connect-timeout", "15", "--max-time", "120", "--resolve", "%s:443:%s" % (domain, ips),
               "-K", cfg, "-w", "%{exitcode} %{http_code} %{filename_effective}\n"]
        # (un lote entero, como mucho 30 minutos: si curl se queda colgado, se para y se dice)
        try:
            r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=1800)
            out, rc = r.stdout, r.returncode
        except subprocess.TimeoutExpired as e:
            out = e.stdout or ""
            out, rc = out.decode(errors="replace") if isinstance(out, bytes) else out, "colgado"
        counted = 0
        for line in out.splitlines():
            code, http, name = (line.split(" ", 2) + ["", ""])[:3]
            n = os.path.basename(name)
            if not n.isdigit() or int(n) >= len(batch):
                continue
            counted += 1
            src = os.path.join(tmp, n)
            dest = os.path.join(root, batch[int(n)])
            # (sin salir de img: una carpeta de la ruta podria ser un enlace a otro sitio. Se mira
            # antes de crear nada)
            real = os.path.realpath(os.path.dirname(dest))
            if code == "0" and http == "200" and os.path.isfile(src) and os.path.getsize(src) > 0 \
                    and real.startswith(img + os.sep) and not os.path.lexists(dest):
                os.makedirs(os.path.dirname(dest), mode=0o755, exist_ok=True)
                shutil.move(src, dest)
                got += 1
            elif http in ("301", "302", "307", "308"):
                moved += 1
            elif http in ("000", "401", "403", "429", "503"):
                blocked += 1
            else:
                gone += 1
            if os.path.lexists(src):
                os.remove(src)
        seen += counted
        notes = [t % c for t, c in (("%d no estan en produccion", gone), ("%d bloqueadas por la web", blocked),
                                     ("%d con redireccion", moved)) if c]
        print("Descargadas %d de %d%s" % (got, len(rels), " (" + ", ".join(["revisadas %d" % seen] + notes) + ")"), flush=True)
        # curl no ha dicho nada de ninguna (se ha caido o colgado): no se sigue lote tras lote sin avanzar
        if not counted:
            stuck = rc
            break
        # Lo primero, todo bloqueado: no se sigue llamando a la web
        if not got and blocked == len(batch):
            break
if stuck != "":
    print("Se para: curl no ha devuelto ningun resultado en este lote (%s). Lo descargado se queda;" %
          ("colgado mas de 30 minutos" if stuck == "colgado" else "se ha caido, señal %d" % -stuck
           if isinstance(stuck, int) and stuck < 0 else "codigo %s" % stuck))
    print("vuelve a lanzarlo y sigue por las que faltan")
if blocked:
    print("La web de %s no deja descargar (cortafuegos o proteccion contra robots del servidor). Este" % domain)
    print("programa se presenta como «%s»: dale permiso en el servidor (Plesk: ModSecurity" % agent)
    print("o Imunify) o copia la carpeta img de produccion a mano")
if moved:
    print("Aviso: %d piden una redireccion (a www o a otro dominio): mira el dominio de la tienda" % moved)
print("Listo: %d imagenes nuevas en %s/img" % (got, root))
sys.exit(1 if stuck != "" else 0 if got or not rels else 1)
EOF
    rc=$?
    rm -f "$file"
    return $rc
}

# Dominios .local apagados a mano en la pestaña Hosts: ya no se mantienen en /etc/hosts.
# local_off si|no <dominio...>: no = apagado (se recuerda), si = encendido (se olvida)
LOCAL_OFF_FILE="$LOG_DIR/locales-apagados"
# (en simulacion no se guarda: los apagados van aqui, para que hosts_fake enseñe lo que haria)
LOCAL_OFF_DRY=""
function local_off() {
    local state=$1 d rest
    shift
    if [ "$DRY" -eq 1 ]; then
        [ "$state" == no ] && LOCAL_OFF_DRY+=" $*"
        echo "  [simulacion] $* $([ "$state" == no ] && echo "se recuerda apagado" || echo "se olvida como apagado") en $LOCAL_OFF_FILE"

        return 0
    fi
    mkdir -p -m 700 "$(dirname "$LOCAL_OFF_FILE")" || return 1
    rest=$(cat "$LOCAL_OFF_FILE" 2> /dev/null)
    for d in "$@"; do
        rest=$(grep -vxF -- "$d" <<< "$rest")
        [ "$state" == no ] && rest+=$'\n'"$d"
    done
    ( umask 077; sed '/^$/d' <<< "$rest" > "$LOCAL_OFF_FILE" )
}

