# ===========================================================================
# Certificados de los vhosts en los que confia todo el equipo
# ===========================================================================
# Un certificado de proyecto que el equipo da por bueno para todo (en /etc/ssl/certs, o de CA, o
# firmado por una CA local sin limite de dominios cuya clave esta en tu carpeta) deja que quien
# consiga su clave falsifique cualquier web real (el banco, Google) en este equipo. Ver CERTS_PY.
CERTS_PY='# Revisa los certificados de los vhosts https. Imprime:
#   C|dominio|crt|key|motivo   un vhost cuyo certificado hay que cambiar (motivo: falta = no existe;
#                              sistema = esta en
#                              /etc/ssl/certs, donde el sistema lo toma como de confianza; ca = es de
#                              CA y su clave podria firmar cualquier web; firmado = lo firmo una CA
#                              local sin limite de dominios)
#   A|nombre|sha256|sha1|donde una CA local de confianza, sin limite de dominios, que firma
#                              certificados de los vhosts (donde: file:<ruta>, nss:<carpeta>:<nombre>
#                              o llavero:<ruta>)
#   K|ruta                     la clave privada de esa CA en tu carpeta personal (sin ella no se
#                              avisa de la CA: lo que firme no puede salir de este equipo)
# CERTS_PY <linux|mac> <puerto https>; los vhosts en LVM_INFO (vhosts_info)
import base64, glob, hashlib, os, re, subprocess, sys, tempfile
osname, https = sys.argv[1], sys.argv[2]
HOME = os.path.expanduser("~")
def run(args, data=None):
    # En su sesion, sin terminal: certutil carga los modulos de pkcs11.txt de tu nssdb, y la terminal
    # de la tarea tiene el permiso de sudo recordado
    kw = {"input": data} if data is not None else {"stdin": subprocess.DEVNULL}
    try:
        r = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=20,
                           start_new_session=True, **kw)
        return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""
def pems(text):
    return re.findall(r"-----BEGIN CERTIFICATE-----[A-Za-z0-9+/=\s]+?-----END CERTIFICATE-----", text)
def info(pem):
    out = run(["openssl", "x509", "-noout", "-subject_hash", "-issuer_hash", "-text"], pem.encode())
    lines = out.splitlines()
    if len(lines) < 3:
        return None
    der = base64.b64decode("".join(l for l in pem.splitlines() if not l.startswith("-----")))
    cn = re.search(r"Subject:.*?CN\s*=\s*([^,/\n]+)", out)
    return {"subj": lines[0].strip(), "iss": lines[1].strip(), "ca": "CA:TRUE" in out,
            "nc": "Name Constraints" in out, "cn": (cn.group(1).strip() if cn else "?"),
            "sha256": hashlib.sha256(der).hexdigest(), "sha1": hashlib.sha1(der).hexdigest(), "pem": pem}
def read(path):
    try:
        if os.path.isfile(path) and os.path.getsize(path) <= 1 << 20:
            return open(path, errors="replace").read()
    except OSError:
        pass
    return ""
store = None
def trust_store():
    # CAs añadidas a mano en este equipo (las del sistema operativo no se miran). LVM_PRUEBA_CAS: una
    # carpeta con mas, solo para las pruebas
    found = []
    for f in sorted(glob.glob(os.path.join(os.environ.get("LVM_PRUEBA_CAS", "/nonexistent"), "*.crt"))):
        for p in pems(read(f)):
            found.append((p, "file:" + f))
    if osname == "linux":
        for f in sorted(glob.glob("/usr/local/share/ca-certificates/**/*.crt", recursive=True)):
            for p in pems(read(f)):
                found.append((p, "file:" + f))
        dbs = [os.path.join(HOME, ".pki/nssdb")]
        dbs += glob.glob(os.path.join(HOME, ".mozilla/firefox/*/"))
        dbs += glob.glob(os.path.join(HOME, "snap/firefox/common/.mozilla/firefox/*/"))
        for d in dbs:
            d = d.rstrip("/")
            if not os.path.isfile(os.path.join(d, "cert9.db")):
                continue
            for line in run(["certutil", "-L", "-d", "sql:" + d]).splitlines()[4:]:
                m = re.match(r"^(.*?)\s+([CcTtPpu]*,[CcTtPpu]*,[CcTtPpu]*)\s*$", line)
                if not m or "|" in m.group(1) or "\n" in m.group(1):
                    continue
                if not re.search(r"[CT]", m.group(2).split(",")[0]):
                    continue
                for p in pems(run(["certutil", "-L", "-d", "sql:" + d, "-n", m.group(1), "-a"])):
                    found.append((p, "nss:%s:%s" % (d, m.group(1))))
    else:
        for kc in ("/Library/Keychains/System.keychain", os.path.join(HOME, "Library/Keychains/login.keychain-db")):
            if os.path.exists(kc):
                for p in pems(run(["security", "find-certificate", "-a", "-p", kc])):
                    found.append((p, "llavero:" + kc))
    out = []
    for p, where in found:
        i = info(p)
        if i and i["ca"]:
            out.append((i, where))
    return out
def signed_by(cert, ca):
    # La firma de verdad (no solo el nombre del emisor, que cualquiera puede copiar en un certificado)
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, "ca"), "w").write(ca["pem"] + "\n")
        open(os.path.join(d, "crt"), "w").write(cert["pem"] + "\n")
        out = run(["openssl", "verify", "-CAfile", os.path.join(d, "ca"), os.path.join(d, "crt")])
    return out.strip().endswith("OK")
cas, rows, keys = {}, [], {}
for row in os.environ.get("LVM_INFO", "").splitlines():
    f = row.split("|")
    if len(f) < 6 or f[0] != https or not f[4] or not re.fullmatch(r"[a-z0-9.-]+", f[2]):
        continue
    dom, crt, key = f[2], f[4], f[5]
    if "|" in crt + key:
        continue
    try:
        os.lstat(crt)
    except FileNotFoundError:
        # Sin certificado Apache no arranca: Arreglarlos le pone uno propio
        rows.append((dom, crt, key, "falta", ""))
        continue
    except OSError:
        continue
    text = read(crt)
    p = pems(text)
    i = info(p[0]) if p else None
    if not i:
        continue
    why, by = "", ""
    if osname == "linux" and os.path.dirname(os.path.realpath(crt)) == "/etc/ssl/certs":
        why = "sistema"
    if i["ca"] or i["subj"] != i["iss"]:
        if store is None:
            store = trust_store()
    # De CA solo importa si el equipo confia en el (si no, nadie acepta lo que firme su clave) y si
    # su clave la puede leer un programa tuyo. Entonces tambien se quita su confianza (fila A)
    if i["ca"] and os.access(key, os.R_OK):
        for ca, where in store or []:
            if ca["sha256"] == i["sha256"]:
                why = why or "ca"
                cas.setdefault(ca["sha256"], (ca, set()))[1].add(where)
                keys.setdefault(ca["sha256"], [])
                if key not in keys[ca["sha256"]]:
                    keys[ca["sha256"]].append(key)
    if i["subj"] != i["iss"]:
        for ca, where in store:
            if ca["subj"] == i["iss"] and not ca["nc"] and signed_by(i, ca):
                by = ca["sha256"]
                cas.setdefault(by, (ca, set()))[1].add(where)
    rows.append((dom, crt, key, why, by))
# Las CAs que firman esos certificados solo son un peligro si su clave esta al alcance de un programa
# tuyo (en tu carpeta personal): entonces se avisa y Arreglarlos las quita. Una CA de empresa cuya
# clave no esta en este equipo no se toca
if cas:
    pubs = {}
    for sha, (ca, _) in cas.items():
        pub = run(["openssl", "x509", "-noout", "-pubkey"], ca["pem"].encode()).strip()
        if pub:
            pubs[pub] = sha
    seen = 0
    for top in [HOME] + [d for d in [os.environ.get("LVM_PRUEBA_CLAVES", "")] if d]:
        for root, dirs, files in os.walk(top):
            dirs[:] = [d for d in dirs if not d.startswith(".") or d in (".ssh", ".local", ".config")]
            if root.count(os.sep) - top.count(os.sep) >= 3:
                dirs[:] = []
            for n in files:
                if not re.search(r"(?i)(\.key|key\.pem)$", n):
                    continue
                path = os.path.join(root, n)
                seen += 1
                if seen > 2000 or os.path.islink(path) or "|" in path:
                    continue
                k = read(path)
                if "PRIVATE KEY" not in k:
                    continue
                pub = run(["openssl", "pkey", "-pubout", "-passin", "pass:"], k.encode()).strip()
                if pub in pubs:
                    keys.setdefault(pubs[pub], []).append(path)
for dom, crt, key, why, by in rows:
    if not why and by in keys:
        why = "firmado"
    if why:
        print("C|%s|%s|%s|%s" % (dom, crt, key, why))
for sha, (ca, wheres) in cas.items():
    if sha not in keys:
        continue
    for where in sorted(wheres):
        print("A|%s|%s|%s|%s" % (ca["cn"].replace("|", "/"), sha, ca["sha1"], where))
    for path in keys[sha]:
        print("K|" + path)
'

# Lineas C|dominio|crt|key|motivo, A|CA|sha256|sha1|donde y (con --clave) K|ruta. Ver CERTS_PY.
# Para la ventana se guarda el resultado mientras no cambien los vhosts ni los almacenes de CAs
function cert_audit() {
    local stamp cache=$LOG_DIR/certificados f
    [ -f "$VHOSTS_FILE" ] || return 0
    stamp=$(for f in "$VHOSTS_FILE" "$OWN_SSL_DIR" "/Library/Keychains/System.keychain" "$HOME/Library/Keychains/login.keychain-db" "$HOSTS_FILE" "$LOG_DIR/confianza"; do
        [ -e "$f" ] && echo "$f $(stat -f %m "$f")"; done; echo "$1 $APP_VERSION")
    if [ "$1" != "--clave" ] && [ -f "$cache" ] && [ "$(head -1 "$cache")" == "#$(echo "$stamp" | md5 -q)" ]; then
        tail -n +2 "$cache"
        return 0
    fi
    local out info
    info=$(vhosts_info)
    # (y, para la ventana, los certificados propios con T|... y U|...: TRUST_PY)
    out=$(LVM_INFO=$info python3 -I -c "$CERTS_PY" mac "$PORT_HTTPS" "$@"
          [ "$1" == "--clave" ] || LVM_INFO=$info LVM_HOSTS_FILE=$HOSTS_FILE LVM_TRUST_DIR=$LOG_DIR/confianza python3 -I -c "$TRUST_PY" mac "$PORT_HTTPS" "$OWN_SSL_DIR" | grep '^[TU]|')
    if [ "$1" != "--clave" ] && [ -d "$LOG_DIR" ]; then
        { echo "#$(echo "$stamp" | md5 -q)"; [ -n "$out" ] && echo "$out"; } > "$cache"
    fi
    [ -n "$out" ] && echo "$out"
    return 0
}

# arreglar-certificados: cada vhost con un certificado de los de arriba pasa a uno autofirmado
# propio en la carpeta de certificados del gestor (no de CA, solo para su dominio), y las CAs locales
# sin limite de dominios que los firmaban dejan de ser de confianza en este Mac. La clave de la CA no
# se borra (puede que la quieras): se dice donde esta
function fix_certs() {
    local audit t dom crt key why copy n=0 cas=0 failed=0 old_files=() keyfile
    audit=$(cert_audit --clave)
    if ! grep -qE '^(C|A)\|' <<< "$audit"; then
        echo "Los certificados de los vhosts ya estan bien: ninguno es de confianza para todo este Mac."
        return 0
    fi
    copy=$(mktemp "${TMPDIR:-/tmp}/lvm-vhosts-cert.XXXXXX") || return 1
    cp "$VHOSTS_FILE" "$copy" || { rm -f "$copy"; return 1; }
    while IFS='|' read -r t dom crt key why; do
        [ "$t" == C ] || continue
        local new_crt="$OWN_SSL_DIR/$dom-selfsigned.crt" new_key="$OWN_SSL_DIR/$dom-selfsigned.key"
        case $why in
            sistema) echo "$dom: su certificado esta en /etc/ssl/certs (el sistema lo da por bueno para todo)" ;;
            ca) echo "$dom: su certificado es de CA (con su clave se firmaria cualquier web)" ;;
            firmado) echo "$dom: su certificado lo firma una CA de confianza sin limite de dominios" ;;
            falta) echo "$dom: su certificado ($crt) no existe" ;;
        esac
        echo "  -> certificado propio en $new_crt"
        make_selfsigned "$dom" "$(domain_alias "$dom")" "$new_crt" "$new_key" || { failed=$((failed + 1)); continue; }
        [ "$DRY" -eq 1 ] && { n=$((n + 1)); continue; }
        if ! LVM_DOM=$dom LVM_CRT=$new_crt LVM_KEY=$new_key python3 -I - "$copy" <<'PY'
import os, re, sys
path = sys.argv[1]
dom, crt, key = os.environ["LVM_DOM"], os.environ["LVM_CRT"], os.environ["LVM_KEY"]
lines = open(path, encoding="utf-8", errors="surrogateescape").read().split("\n")
out, block, start = [], None, 0
for line in lines:
    s = line.strip()
    if re.match(r"(?i)<VirtualHost\b", s):
        block, start = [], len(out)
    out.append(line)
    if block is not None:
        block.append(len(out) - 1)
        if re.match(r"(?i)</VirtualHost>", s):
            names = [re.split(r"\s+", out[i].strip(), maxsplit=1)[1].split(":")[0].lower() for i in block
                     if re.match(r"(?i)\s*ServerName\s+\S", out[i])]
            if dom in names:
                for i in block:
                    m = re.match(r"(?i)(\s*)(SSLCertificateFile|SSLCertificateKeyFile)(\s+)\S.*$", out[i])
                    if m:
                        out[i] = m.group(1) + m.group(2) + m.group(3) + "\"%s\"" % (crt if m.group(2).lower() == "sslcertificatefile" else key)
            block = None
open(path, "w", encoding="utf-8", errors="surrogateescape").write("\n".join(out))
PY
        then
            failed=$((failed + 1))
            continue
        fi
        n=$((n + 1))
        :
    done <<< "$audit"
    if [ $n -gt 0 ]; then
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] los vhosts pasan a usar esos certificados (copia de root, comprobacion y recarga de Apache)"
        else
            edit_vhosts --aplicar "$copy" || { rm -f "$copy"; echo "No se han cambiado los vhosts: los certificados viejos siguen en uso."; return 1; }
            rm -f "$LOG_DIR/certificados"
        fi
    fi
    rm -f "$copy"

    if [ $failed -gt 0 ] && grep -q '^A|' <<< "$audit"; then
        echo "No se quita la confianza a la CA: $failed proyecto(s) no se han podido pasar a su certificado"
        echo "propio y dejarian de funcionar. Revisa sus vhosts y vuelve a pulsar Arreglarlos."
        audit=$(grep -v '^A|' <<< "$audit")
    fi
    while IFS='|' read -r t _ _ sha1 where; do
        [ "$t" == A ] || continue
        cas=1
        case $where in
            llavero:*)
                # Primero sus ajustes de confianza (los que pone mkcert con add-trusted-cert): borrar
                # el certificado no los quita
                local kc=${where#llavero:} pem
                pem=$(mktemp "${TMPDIR:-/tmp}/lvm-ca.XXXXXX") || continue
                security find-certificate -a -p "$kc" 2> /dev/null | python3 -I -c '
import base64, hashlib, re, sys
for p in re.findall(r"-----BEGIN CERTIFICATE-----[A-Za-z0-9+/=\s]+?-----END CERTIFICATE-----", sys.stdin.read()):
    der = base64.b64decode("".join(p.split("\n")[1:-1]))
    if hashlib.sha1(der).hexdigest() == sys.argv[1]:
        print(p)
        break' "$sha1" > "$pem"
                if [ "$kc" == /Library/Keychains/System.keychain ]; then
                    echo "Quitando la CA de confianza del llavero del sistema ($sha1)..."
                    [ -s "$pem" ] && run $SUDO security remove-trusted-cert -d "$pem"
                    run $SUDO security delete-certificate -Z "$sha1" "$kc"
                else
                    echo "Quitando la CA de tu llavero ($sha1)..."
                    [ -s "$pem" ] && run security remove-trusted-cert "$pem"
                    run security delete-certificate -Z "$sha1" "$kc"
                fi
                rm -f "$pem" ;;
        esac
    done <<< "$audit"
    keyfile=$(grep '^K|' <<< "$audit" | cut -d'|' -f2- | head -5)
    if [ -n "$keyfile" ]; then
        echo
        echo "La clave privada de esa CA sigue en tu carpeta:"
        sed 's/^/  /' <<< "$keyfile"
        echo "Ya no vale para falsificar webs en este Mac, pero si la usas en otros equipos, bórrala de aqui"
        echo "o guardala cifrada fuera de tu carpeta personal."
    fi
    rm -f "$LOG_DIR/certificados"
    echo
    echo "Certificados arreglados. Para que el navegador no avise en cada proyecto https, pulsa Confiar"
    echo "en el aviso «El navegador avisa al abrir estos proyectos» de la ventana"
    echo "(o: lvm-instalador confiar-certificados)."
    return 0
}

