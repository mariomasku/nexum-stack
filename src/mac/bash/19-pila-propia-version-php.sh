# ===========================================================================
# Pila propia de una version de PHP
# ===========================================================================

#@incluir comun/pila-propia-version-php/progress_parts.sh
#@incluir comun/pila-propia-version-php/descargas_cache.sh
function progress() {
    [ -n "$PROGRESS" ] && echo "S|$1|$2|$3|$4|$5|$6|$7|$(date +%s)" >> "$PROGRESS"
    return 0
}

# Tamaño de un archivo remoto en bytes (siguiendo redirecciones)
function remote_size() {
    curl -q --proto =https --proto-redir =https -fsSLI --max-time 15 "$1" 2> /dev/null | tr -d '\r' | awk 'tolower($1) == "content-length:" {n = $2} END {print n + 0}'
}

# Descarga una URL a la salida estandar. Se guarda una hora en cache, porque las pantallas
# del panel consultan las mismas paginas varias veces.
# (Todas las descargas van con curl -q: sin ~/.curlrc, que cualquier programa tuyo podria preparar
# con --insecure o un proxy suyo)
function fetch() {
    local cache=$LOG_DIR/cache
    local file=$cache/$(md5 -q -s "$1")

    # Al instalar (FETCH_FRESH=1) no se pasa por la cache: es tuya (cualquier programa tuyo la puede
    # cambiar) y de ahi salen las direcciones y las huellas de lo que se instala como root
    if [ "${FETCH_FRESH:-0}" == 1 ]; then
        curl -q --proto =https --proto-redir =https -fsSL --max-time 30 "$1" 2> /dev/null
        return
    fi
    if [ ! -s "$file" ] || [ -n "$(find "$file" -mmin +60 2> /dev/null)" ]; then
        mkdir -p "$cache"
        if ! curl -q --proto =https --proto-redir =https -fsSL --max-time 30 "$1" > "$file.$$" 2> /dev/null; then
            rm -f "$file.$$"

            return 1
        fi
        mv "$file.$$" "$file"
    fi

    cat "$file"
}

# Ultima version de cada rama de STACK_MATRIX publicada en php.net, aunque ya no tenga soporte
# (de la mas nueva a la mas antigua):
# "8.4 8.4.26 <sha256 del .tar.xz>"
function php_releases() {
    local i branch

    # De la rama mas nueva a la mas antigua, como se muestran en el panel y en la ventana
    for (( i = ${#STACK_MATRIX[@]} - 1; i >= 0; i-- )); do
        branch=${STACK_MATRIX[i]%%|*}
        fetch "https://www.php.net/releases/index.php?json&version=$branch" | python3 -I -c 'import json, re, sys
data = json.load(sys.stdin)
import datetime
sha = [s["sha256"] for s in data.get("source", []) if s["filename"].endswith(".tar.xz")]
try:
    date = datetime.datetime.strptime(data.get("date", ""), "%d %b %Y").strftime("%Y-%m-%d")
except ValueError:
    date = "-"
# (rama, ultimo parche, su sha256, su fecha y si php.net lo marca como parche de seguridad)
# (solo X.Y.Z y una suma de verdad: con un | o un salto de linea descolocaria las lineas de la ventana)
if re.match(r"^\d+\.\d+\.\d+$", str(data.get("version", ""))) and sha and re.match(r"^[0-9a-f]{64}$", sha[0]):
    print(sys.argv[1], data["version"], sha[0], date,
          "seguridad" if "security" in (data.get("tags") or []) else "-")' "$branch" 2> /dev/null
    done
}

# Todas las versiones publicadas de PHP 7, 8 y 9: "8.4.26 2026-09-24 seguridad|-", de la mas nueva
# a la mas antigua (fecha de cada una para las versiones instaladas)
function php_all_releases() {
    local major

    for major in 7 8 9; do
        # Una rama mayor que aun no existe (9) devuelve {"error": ...} y no cuenta como fallo
        fetch "https://www.php.net/releases/index.php?json&version=$major&max=1000" | python3 -I -c 'import json, re, sys, datetime
data = json.load(sys.stdin)
for version, info in (data.items() if "error" not in data else []):
    # (solo X.Y.Z: con un | o un salto de linea descolocaria las lineas de la ventana)
    if re.match(r"^\d+\.\d+\.\d+$", version):
        try:
            date = datetime.datetime.strptime(info.get("date", ""), "%d %b %Y").strftime("%Y-%m-%d")
        except ValueError:
            date = "-"
        print(version, date, "seguridad" if "security" in (info.get("tags") or []) else "-")' 2> /dev/null || true
    done | python3 -I -c 'import sys
rows = [l.split() for l in sys.stdin if l.strip()]
rows.sort(key=lambda r: [int(x) for x in r[0].split(".")], reverse=True)
for r in rows: print(" ".join(r))'
}

# Ramas de PHP con soporte oficial (las demas se marcan como "sin soporte" en el panel)
function php_supported() {
    fetch "https://www.php.net/releases/active.php" \
        | python3 -I -c 'import json, re, sys
for branches in json.load(sys.stdin).values():
    for branch in branches:
        if re.match(r"^\d+\.\d+$", str(branch)):
            print(branch)' 2> /dev/null
}

# Estado de cada rama en php.net: rama|estado|fin del soporte activo|fin de los parches de seguridad
#   estado: stable (correcciones de errores y de seguridad), security (solo de seguridad) o eol
function php_branch_states() {
    fetch "https://www.php.net/releases/branches.php" | python3 -I -c 'import json, re, sys
for b in json.load(sys.stdin):
    if not re.match(r"^\d+\.\d+$", str(b.get("branch", ""))) or b.get("state") not in ("stable", "security", "eol"):
        continue
    print("%s|%s|%s|%s" % (b.get("branch", ""), b.get("state", ""),
                           (b.get("active_support_end") or "")[:10], (b.get("security_support_end") or "")[:10]))' 2> /dev/null
}

# Texto del estado de una rama para el panel: estable, solo seguridad o sin soporte
function branch_state_text() {
    local st=$(grep "^$1|" <<< "$2" | cut -d'|' -f2)
    case "$st" in
        stable) echo "estable" ;;
        security) echo "solo seguridad" ;;
        eol) echo "sin soporte" ;;
        *) grep -qxF "$1" <<< "$3" && echo "con soporte" || echo "sin soporte" ;;
    esac
}

# Ramas de los componentes que lleva una rama de PHP: "apache mariadb proftpd perl".
function stack_branches() {
    local row

    # Solo las ramas de la tabla: antes una desconocida recibia sin avisar la de la ultima fila
    for row in "${STACK_MATRIX[@]}"; do
        if [ "${row%%|*}" == "$1" ]; then
            echo "$row" | cut -d'|' -f2- | tr '|' ' '

            return 0
        fi
    done

    return 1
}

# Ultimo parche publicado de cada componente
function latest_apache() {
    fetch https://dlcdn.apache.org/httpd/ | grep -oE "href=\"httpd-$1\.[0-9]+\.tar\.bz2\"" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | vsort | tail -1
}

# latest_apr apr|apr-util
function latest_apr() {
    fetch https://dlcdn.apache.org/apr/ | grep -oE "href=\"$1-1\.[0-9]+\.[0-9]+\.tar\.bz2\"" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | vsort | tail -1
}

# Ultima version de una rama de MariaDB: "version|url del codigo fuente|sha256"
# (MariaDB no publica binarios para macOS, asi que se compila)
function mariadb_release() {
    fetch "https://downloads.mariadb.org/rest-api/mariadb/$1/latest/" | python3 -I -c 'import json, re, sys
for version, release in json.load(sys.stdin)["releases"].items():
    # Va en URLs, carpetas y ficheros de configuracion: solo una version normal
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        continue
    files = [f for f in release["files"] if f["file_name"] == "mariadb-%s.tar.gz" % version]
    if files:
        url = files[0]["file_download_url"].replace("http://", "https://", 1)
        sha = (files[0].get("checksum") or {}).get("sha256sum", "")
        if not url.startswith("https://") or "|" in url or not re.fullmatch(r"[0-9a-f]{64}", sha):
            continue
        print(version + "|" + url + "|" + sha)
        break' 2> /dev/null
}

function latest_perl() {
    fetch https://www.cpan.org/src/5.0/ | grep -oE "perl-$1\.[0-9]+\.tar\.xz\"" \
        | grep -oE '5\.[0-9]+\.[0-9]+' | vsort | tail -1
}

# ProFTPD publica parches con letra (1.3.9, 1.3.9a, 1.3.9b...). Se descartan las versiones rc.
function latest_proftpd() {
    local tags

    tags=$(fetch "https://api.github.com/repos/proftpd/proftpd/releases?per_page=50" | python3 -I -c 'import json, sys
for release in json.load(sys.stdin):
    # Solo las que publican el .sha256 del tar.gz: sin el no se puede comprobar la descarga
    assets = [a["name"] for a in release.get("assets", [])]
    if not release["prerelease"] and any(a.endswith(".tar.gz.sha256") for a in assets):
        print(release["tag_name"])' 2> /dev/null)

    # La API de GitHub limita las consultas: si falla, se leen las etiquetas con git
    if [ -z "$tags" ] && command -v git > /dev/null; then
        tags=$(/usr/bin/python3 -I -c "$NO_TTY_PY" git -c credential.helper= ls-remote --tags https://github.com/proftpd/proftpd 2> /dev/null < /dev/null | grep -oE 'v[0-9.]+[a-z]?$')
    fi

    grep -E "^v$(echo "$1" | sed 's/\./\\./g')[a-z]?$" <<< "$tags" | sed 's/^v//' | vsort | tail -1
}

# phpMyAdmin 6 necesita PHP 8.1 o posterior: las ramas anteriores se quedan con la 5.2
function latest_pma() {
    local branch=$1
    local version=$(fetch https://www.phpmyadmin.net/home_page/version.json \
        | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["version"])' 2> /dev/null)
    # Va en URLs y en la configuracion de Apache: solo numeros y puntos
    [[ "$version" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || version=""

    if [ -n "$version" ] && [ "${version%%.*}" -ge 6 ] && { [ "$branch" == "7.4" ] || [ "$branch" == "8.0" ]; }; then
        version=$PMA_VERSION
    fi

    echo "${version:-$PMA_VERSION}"
}

# Versiones de una pila: "php|apache|mariadb|proftpd|perl|phpmyadmin".
# Si no se puede consultar algun componente, se muestra su rama seguida de ".x".
function stack_versions() {
    local php=$1 branches
    read -r -a branches <<< "$(stack_branches "${php%.*}")"

    local apache=$(latest_apache "${branches[0]}")
    local mariadb=$(mariadb_release "${branches[1]}")
    mariadb=${mariadb%%|*}
    local ftp=$(latest_proftpd "${branches[2]}")
    local perl=$(latest_perl "${branches[3]}")

    echo "$php|${apache:-${branches[0]}.x}|${mariadb:-${branches[1]}.x}|${ftp:-${branches[2]}.x}|${perl:-${branches[3]}.x}|$(latest_pma "${php%.*}")"
}

# Comprueba una firma OpenPGP suelta del codigo fuente (en texto, .asc, o binaria) contra las claves
# de un proyecto, solo con Python del sistema: sin gnupg de Homebrew, que en las versiones de macOS
# sin paquetes ya hechos se compila entero (con python, meson, gnutls...). Firmas v4 de un fichero
# (tipo 0), RSA (PKCS#1 v1.5, de 2048 bits o mas) o EdDSA (Ed25519), con SHA-2 (sin SHA-1). Vale la
# firma de la clave principal o de una subclave de firmar con su firma de enlace de la principal y la
# de vuelta de la subclave (como gpg); nada revocado. Una clave caducada vale para lo que firmo (como
# gpgv). Uso: <fichero> <firma> <huellas que se aceptan>, con las claves (en base64) en la entrada.
# Solo es buena si escribe FIRMA-BUENA <huella de la clave principal> (no basta con que termine bien)
SIG_VERIFY_PY='
import base64, hashlib, sys, time
path, sig_path, want = sys.argv[1], sys.argv[2], sys.argv[3].upper().split()
def no(why):
    sys.stderr.write("Firma: %s\n" % why)
    sys.exit(1)
class Mal(Exception):
    pass
def packets(data):
    i, out = 0, []
    while i < len(data):
        b = data[i]
        if not b & 0x80:
            raise Mal("paquete OpenPGP no valido")
        if b & 0x40:
            tag, o = b & 0x3F, data[i + 1] if i + 1 < len(data) else 0
            if o < 192:
                n, h = o, 2
            elif o < 224:
                if i + 2 >= len(data):
                    raise Mal("paquete cortado")
                n, h = ((o - 192) << 8) + data[i + 2] + 192, 3
            elif o == 255:
                n, h = int.from_bytes(data[i + 2:i + 6], "big"), 6
            else:
                raise Mal("longitud parcial no admitida")
        else:
            tag, lt = (b >> 2) & 0x0F, b & 3
            if lt == 3:
                raise Mal("longitud indeterminada no admitida")
            size = (1, 2, 4)[lt]
            n, h = int.from_bytes(data[i + 1:i + 1 + size], "big"), 1 + size
        body = data[i + h:i + h + n]
        if len(body) != n or i + h > len(data):
            raise Mal("paquete cortado")
        out.append((tag, body))
        i += h + n
    return out
def mpi(b, i):
    if i + 2 > len(b):
        raise Mal("numero cortado")
    bits = int.from_bytes(b[i:i + 2], "big")
    n = (bits + 7) // 8
    if i + 2 + n > len(b):
        raise Mal("numero cortado")
    return b[i + 2:i + 2 + n], i + 2 + n
# Firma en texto (ASCII armor) o en binario
def dearmor(raw):
    if raw[:1] and raw[0] & 0x80:
        return raw
    try:
        lines = raw.decode("ascii").replace("\r", "").split("\n")
    except UnicodeDecodeError:
        raise Mal("la firma no es OpenPGP")
    try:
        a = lines.index("-----BEGIN PGP SIGNATURE-----")
        z = lines.index("-----END PGP SIGNATURE-----", a)
    except ValueError:
        raise Mal("la firma no es OpenPGP")
    body, i = lines[a + 1:z], 0
    while i < len(body) and body[i].strip():
        if ":" not in body[i]:
            break
        i += 1
    body = [l.strip() for l in body[i:] if l.strip()]
    crc = None
    if body and body[-1].startswith("=") and len(body[-1]) == 5:
        crc = body.pop()[1:]
    try:
        data = base64.b64decode("".join(body), validate=True)
    except ValueError:
        raise Mal("firma en texto no valida")
    if crc is not None:
        c = 0xB704CE
        for x in data:
            c ^= x << 16
            for _ in range(8):
                c <<= 1
                if c & 0x1000000:
                    c ^= 0x1864CFB
        if base64.b64decode(crc) != (c & 0xFFFFFF).to_bytes(3, "big"):
            raise Mal("la firma en texto esta estropeada (CRC)")
    return data
# Ed25519 (RFC 8032), solo para comprobar
P = 2 ** 255 - 19
Q = 2 ** 252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P
SQRT_M1 = pow(2, (P - 1) // 4, P)
def recover_x(y, sign):
    xx = (y * y - 1) * pow(D * y * y + 1, P - 2, P) % P
    x = pow(xx, (P + 3) // 8, P)
    if (x * x - xx) % P:
        x = x * SQRT_M1 % P
    if (x * x - xx) % P:
        return None
    if x == 0 and sign:
        return None
    if x & 1 != sign:
        x = P - x
    return x
def add(a, b):
    x1, y1, z1, t1 = a
    x2, y2, z2, t2 = b
    A = (y1 - x1) * (y2 - x2) % P
    B = (y1 + x1) * (y2 + x2) % P
    C = 2 * t1 * t2 * D % P
    E = 2 * z1 * z2 % P
    e, f, g, h = B - A, E - C, E + C, B + A
    return (e * f % P, g * h % P, f * g % P, e * h % P)
def mul(s, a):
    r = (0, 1, 1, 0)
    while s:
        if s & 1:
            r = add(r, a)
        a = add(a, a)
        s >>= 1
    return r
def encode(a):
    zi = pow(a[2], P - 2, P)
    x, y = a[0] * zi % P, a[1] * zi % P
    return (y | ((x & 1) << 255)).to_bytes(32, "little")
def decode(s):
    if len(s) != 32:
        return None
    y = int.from_bytes(s, "little")
    sign, y = y >> 255, y & ((1 << 255) - 1)
    if y >= P:
        return None
    x = recover_x(y, sign)
    return None if x is None else (x, y, 1, x * y % P)
BY = 4 * pow(5, P - 2, P) % P
BASE = (recover_x(BY, 0), BY, 1, recover_x(BY, 0) * BY % P)
def ed25519_ok(pub, msg, sig):
    a, r = decode(pub), decode(sig[:32])
    s = int.from_bytes(sig[32:], "little")
    if a is None or r is None or s >= Q:
        return False
    h = int.from_bytes(hashlib.sha512(sig[:32] + pub + msg).digest(), "little") % Q
    return encode(mul(s, BASE)) == encode(add(r, mul(h, a)))
# Resumenes admitidos (sin SHA-1 ni MD5) y su DigestInfo para RSA (PKCS#1 v1.5)
HASHES = {8: hashlib.sha256, 9: hashlib.sha384, 10: hashlib.sha512, 11: hashlib.sha224}
DIGEST_INFO = {8: "3031300d060960864801650304020105000420", 9: "3041300d060960864801650304020205000430",
               10: "3051300d060960864801650304020305000440", 11: "302d300d06096086480165030402040500041c"}
ED_OID = bytes.fromhex("2B06010401DA470F01")
# Clave publica v4: (huella, creada, algoritmo, material) o None si no se puede usar
def pubkey(kb):
    if len(kb) < 6 or kb[0] != 4:
        return None
    fpr = hashlib.sha1(b"\x99" + len(kb).to_bytes(2, "big") + kb).hexdigest().upper()
    made, algo = int.from_bytes(kb[1:5], "big"), kb[5]
    try:
        if algo in (1, 3):
            n, i = mpi(kb, 6)
            e, i = mpi(kb, i)
            n, e = int.from_bytes(n, "big"), int.from_bytes(e, "big")
            if n.bit_length() < 2048 or e < 3 or not e & 1:
                return None
            return (fpr, made, "rsa", (n, e), kb)
        if algo == 22 and len(kb) > 7 and kb[6] == len(ED_OID) and kb[7:7 + len(ED_OID)] == ED_OID:
            q, _ = mpi(kb, 7 + len(ED_OID))
            if len(q) != 33 or q[0] != 0x40:
                return None
            return (fpr, made, "ed", q[1:], kb)
    except Mal:
        return None
    return None
def subpackets(b):
    i, out = 0, []
    while i < len(b):
        o = b[i]
        if o < 192:
            n, h = o, 1
        elif o < 255:
            if i + 1 >= len(b):
                raise Mal("subpaquete no valido")
            n, h = ((o - 192) << 8) + b[i + 1] + 192, 2
        else:
            n, h = int.from_bytes(b[i + 1:i + 5], "big"), 5
        if n < 1 or i + h + n > len(b):
            raise Mal("subpaquete no valido")
        out.append((b[i + h] & 0x7F, b[i + h] & 0x80, b[i + h + 1:i + h + n]))
        i += h + n
    return out
# Firma v4: dict con lo que hace falta, o Mal si no se entiende
KNOWN = (2, 3, 4, 5, 7, 9, 11, 12, 16, 21, 22, 23, 25, 27, 30, 31, 32, 33)
def parse_sig(sb):
    if len(sb) < 10 or sb[0] != 4:
        raise Mal("firma que no es v4")
    hl = int.from_bytes(sb[4:6], "big")
    if 6 + hl + 2 > len(sb):
        raise Mal("firma cortada")
    hashed = sb[6:6 + hl]
    ul = int.from_bytes(sb[6 + hl:8 + hl], "big")
    unhashed = sb[8 + hl:8 + hl + ul]
    rest = sb[8 + hl + ul:]
    hs, us = subpackets(hashed), subpackets(unhashed)
    for t, crit, v in hs:
        # Uno critico que no se conoce: no se puede dar por buena (como gpgv)
        if crit and t not in KNOWN:
            raise Mal("subpaquete critico desconocido (%d)" % t)
    s = {"type": sb[1], "algo": sb[2], "hash": sb[3], "trailer": sb[:6 + hl], "hs": hs, "us": us}
    s["made"] = next((int.from_bytes(v, "big") for t, c, v in hs if t == 2 and len(v) == 4), None)
    s["life"] = next((int.from_bytes(v, "big") for t, c, v in hs if t == 3 and len(v) == 4), 0)
    s["flags"] = next((v[0] for t, c, v in hs if t == 27 and v), None)
    s["fprs"] = [v[1:].hex().upper() for t, c, v in hs + us if t == 33 and len(v) == 21 and v[0] == 4]
    s["ids"] = [v.hex().upper() for t, c, v in hs + us if t == 16 and len(v) == 8]
    s["embedded"] = [v for t, c, v in hs + us if t == 32]
    if len(rest) < 2:
        raise Mal("firma cortada")
    s["prefix"] = rest[:2]
    if s["algo"] in (1, 3):
        m, i = mpi(rest, 2)
        s["mpis"] = (m,)
    elif s["algo"] == 22:
        r, i = mpi(rest, 2)
        q, i = mpi(rest, i)
        s["mpis"] = (r, q)
    else:
        raise Mal("algoritmo de firma no admitido (%d)" % s["algo"])
    if i != len(rest):
        raise Mal("firma con datos de mas")
    return s
def by(s, key):
    # (la firma dice de que clave es: con la huella, o con el ID largo si no la trae)
    return key[0] in s["fprs"] or (not s["fprs"] and key[0][-16:] in s["ids"])
def check(s, key, h):
    # h: el resumen ya con los datos firmados; se le añade la cola de la firma
    if s["hash"] not in HASHES or s["made"] is None or s["made"] < key[1]:
        return False
    h.update(s["trailer"])
    h.update(b"\x04\xff" + len(s["trailer"]).to_bytes(4, "big"))
    digest = h.digest()
    if s["prefix"] != digest[:2]:
        return False
    if key[2] == "rsa" and s["algo"] in (1, 3):
        n, e = key[3]
        k = (n.bit_length() + 7) // 8
        sig = int.from_bytes(s["mpis"][0], "big")
        if sig >= n:
            return False
        t = bytes.fromhex(DIGEST_INFO[s["hash"]]) + digest
        if k < len(t) + 11:
            return False
        return pow(sig, e, n).to_bytes(k, "big") == b"\x00\x01" + b"\xff" * (k - len(t) - 3) + b"\x00" + t
    if key[2] == "ed" and s["algo"] == 22:
        r, q = s["mpis"]
        if len(r) > 32 or len(q) > 32:
            return False
        return ed25519_ok(key[3], digest, r.rjust(32, b"\0") + q.rjust(32, b"\0"))
    return False
def key_hash(s, *keys):
    h = HASHES[s["hash"]]() if s["hash"] in HASHES else hashlib.sha256()
    for k in keys:
        h.update(b"\x99" + len(k[4]).to_bytes(2, "big") + k[4])
    return h
def good_sig(body, signer, want_type, *keys):
    try:
        s = parse_sig(body)
    except Mal:
        return None
    if s["type"] != want_type or not by(s, signer) or not check(s, signer, key_hash(s, *keys)):
        return None
    return s
# Las claves (de stdin, en base64): las principales, y las subclaves de firmar con su firma de enlace
# (de la principal) y la de vuelta (de la subclave), como gpg. Nada revocado
try:
    ring = packets(base64.b64decode("".join(sys.stdin.read().split()), validate=True))
except (ValueError, Mal):
    no("las claves no son validas")
signers, primary, sub, where, cur_sigs = {}, None, None, None, []
def close():
    if where == "key" and any(good_sig(b, primary, 0x20, primary) for b in cur_sigs):
        primary[5]["revoked"] = True
    if where != "sub" or any(good_sig(b, primary, 0x28, primary, sub) for b in cur_sigs):
        return
    for b in cur_sigs:
        s = good_sig(b, primary, 0x18, primary, sub)
        if not s or (s["flags"] is not None and not s["flags"] & 0x02):
            continue
        if any(good_sig(e, sub, 0x19, primary, sub) for e in s["embedded"]):
            signers[sub[0]] = (sub, primary)
            return
for tag, body in ring:
    if tag in (6, 13, 14, 17):
        close()
        where, cur_sigs = None, []
    if tag == 6:
        primary = pubkey(body)
        if primary is not None:
            primary += ({},)
            signers[primary[0]] = (primary, primary)
            where = "key"
    elif tag == 14 and primary is not None:
        sub = pubkey(body)
        if sub is not None:
            sub += ({},)
            where = "sub"
    elif tag == 2:
        cur_sigs.append(body)
close()
# Las de firmar: de las huellas que se aceptan para este proyecto y sin revocar
usable = [(k, p) for k, p in signers.values() if p[0] in want and not p[5].get("revoked")]
if not usable:
    no("no hay ninguna clave de las esperadas")
# La firma (en texto o binaria): de un fichero (tipo 0), de una de esas claves
with open(sig_path, "rb") as f:
    raw = f.read(65537)
if len(raw) > 65536:
    no("la firma es demasiado grande")
try:
    sp = packets(dearmor(raw))
except Mal as e:
    no(str(e))
if not sp or any(t != 2 for t, b in sp):
    no("no es una firma suelta")
cands = []
for t, b in sp:
    try:
        s = parse_sig(b)
    except Mal as e:
        no(str(e))
    if s["type"] != 0:
        no("tipo de firma no admitido")
    if s["hash"] not in HASHES:
        no("resumen no admitido (%d)" % s["hash"])
    if s["life"] and (s["made"] is None or time.time() > s["made"] + s["life"]):
        no("la firma ha caducado")
    for k, p in usable:
        if by(s, k):
            cands.append((s, k, p))
if not cands:
    no("la firma no es de ninguna de las claves esperadas")
hs = {}
with open(path, "rb") as f:
    for s, k, p in cands:
        hs.setdefault(s["hash"], HASHES[s["hash"]]())
    for chunk in iter(lambda: f.read(1 << 20), b""):
        for h in hs.values():
            h.update(chunk)
for s, k, p in cands:
    if check(s, k, hs[s["hash"]].copy()):
        print("FIRMA-BUENA %s" % p[0])
        sys.exit(0)
no("la firma no es buena o el fichero no es el firmado")
'

# gpg_verify <archivo> <firma> <PHP|APACHE|MARIADB|PMA>: ¿es buena la firma y de una de las claves de
# GPG_FPRS_<...>? Con SIG_VERIFY_PY, solo con esas claves (ni las tuyas ni un servidor de claves)
function gpg_verify() {
    local file=$1 sig=$2 keys=GPG_KEYS_$3 fprs=GPG_FPRS_$3 out="" fpr why
    [ -n "${!keys}" ] && [ -n "${!fprs}" ] && [ -n "$SIG_VERIFY_PY" ] \
        || { echo "  No hay claves para comprobar $(basename "$file")"; return 1; }
    out=$(/usr/bin/python3 -I -c "$SIG_VERIFY_PY" "$file" "$sig" "${!fprs}" <<< "${!keys}" 2>&1) || out="NO $out"
    # FIRMA-BUENA <huella de la clave principal> (y que sea una de las del proyecto)
    fpr=$(awk '$1 == "FIRMA-BUENA" && NF == 2 && NR == 1 { print $2 }' <<< "$out")
    if [[ "$fpr" =~ ^[0-9A-F]{40}$ ]] && [ "$(wc -l <<< "$out")" -eq 1 ] && [[ " ${!fprs} " == *" $fpr "* ]]; then
        echo "  Firma de $(basename "$file") comprobada (clave ${fpr: -16})"
        return 0
    fi
    why=$(sed -n 's/^\(NO \)\{0,1\}Firma: //p' <<< "$out" | head -1)
    echo "  La firma de $(basename "$file") no es buena o no es de quien lo publica${why:+ ($why)}. Se cancela."
    return 1
}

# download <url> <archivo> <sha256> [<url de la firma> <PHP|APACHE|MARIADB|PMA>] [nombre en la cache de
# descargas]: descarga un archivo y comprueba su suma y, si se indica, su firma GPG (gpg_verify)
# La suma sha256 del codigo de ProFTPD <version>: la publica con cada version en GitHub. A veces su
# descarga directa responde 504 durante horas: entonces se pide el mismo fichero por la API de GitHub
# (del mismo repositorio), que lo sirve por otro camino
function proftpd_sum() {
    local ftp=$1 sum id
    sum=$(curl -q --proto =https --proto-redir =https -fsSL --retry 2 --max-time 60 \
        "https://github.com/proftpd/proftpd/releases/download/v$ftp/proftpd-$ftp.tar.gz.sha256" 2> /dev/null | grep -oE '^[0-9a-f]{64}')
    if [ -z "$sum" ]; then
        id=$(curl -q --proto =https --proto-redir =https -fsSL --retry 2 --max-time 60 \
            "https://api.github.com/repos/proftpd/proftpd/releases/tags/v$ftp" 2> /dev/null \
            | python3 -I -c 'import json, sys
print(next((a["id"] for a in json.load(sys.stdin).get("assets", []) if a.get("name") == sys.argv[1]), ""))' "proftpd-$ftp.tar.gz.sha256" 2> /dev/null)
        [[ "$id" =~ ^[0-9]+$ ]] && sum=$(curl -q --proto =https --proto-redir =https -fsSL --retry 2 --max-time 60 \
            -H 'Accept: application/octet-stream' "https://api.github.com/repos/proftpd/proftpd/releases/assets/$id" 2> /dev/null \
            | grep -oE '^[0-9a-f]{64}')
    fi
    echo "$sum"
}

function download() {
    local url=$1 file=$2 sum=$3 sig_url=$4 keys=$5 name=${6:-$(basename "$1")}
    DL_SUM=$sum

    # (de la cache de descargas, si esta con esa suma o, si su web no la da, con la que se guardo: su
    # firma ya se comprobo al guardarlo)
    if dl_from_cache "$name" "$file" "$sum"; then
        if [ -z "$sum" ]; then
            echo "  Su web no da la suma sha256 de $name: se usa el de la cache de descargas (ya comprobado)"
        else
            echo "  $name: de la cache de descargas (sha256 comprobada)"
        fi
        dl_note "$file" "$name" "$DL_SUM"
        return 0
    fi

    # (STEP_DESC: el motivo, para el informe del error si falla aqui, antes de compilar nada)
    if [ -z "$sum" ]; then
        echo "  No se ha encontrado la suma sha256 de $name"
        STEP_DESC="no se ha podido leer la suma sha256 de $name (su web no responde: prueba en un rato)"

        return 1
    fi

    echo "  Descargando $name..."
    curl -q --proto =https --proto-redir =https -fsSL --retry 2 -o "$file" "$url" || {
        echo "  No se pudo descargar $url"
        STEP_DESC="no se ha podido descargar $url (su web no responde: prueba en un rato)"
        return 1
    }

    if [ "$(sha256_of "$file")" != "$sum" ]; then
        echo "  $name no coincide con su suma sha256. Se cancela."
        STEP_DESC="$name no coincide con su suma sha256: no se instala"

        return 1
    fi

    if [ -n "$sig_url" ]; then
        curl -q --proto =https --proto-redir =https -fsSL --retry 2 -o "$file.firma" "$sig_url" \
            || { echo "  No se pudo descargar la firma de $name ($sig_url). Se cancela."; return 1; }
        gpg_verify "$file" "$file.firma" "$keys" || return 1
    fi
    dl_note "$file" "$name" "$sum"
}

# download_apache <ruta> <archivo>: dlcdn solo tiene la ultima version; si no esta, archive.apache.org
function download_apache() {
    local base sum

    for base in https://dlcdn.apache.org https://archive.apache.org/dist; do
        sum=$(curl -q --proto =https --proto-redir =https -fsSL "$base/$1.sha256" 2> /dev/null | grep -oE '^[0-9a-f]{64}')
        [ -n "$sum" ] && download "$base/$1" "$2" "$sum" "$base/$1.asc" APACHE && return 0
    done

    # (ninguna de las dos responde: el de la cache de descargas, si esta)
    [ -z "$sum" ] && download "" "$2" "" "" APACHE "$(basename "$1")"
}

# step <componente> <desde> <hasta> <lineas> <descripcion> <log> <comando...>
# Un paso de la compilacion, con su salida en un log. <desde>-<hasta> es el tramo de la barra de
# progreso (en % de la version) y <lineas> las que suele tener el log al terminar (0 = el log
# escribe "[ NN%]", como CMake).
# Informe para buscar la solucion de un fallo al instalar: el sistema, lo que se instalaba, el paso
# que fallo con sus primeros errores y el final de su log y, si fallo un configure, la ultima prueba
# de su config.log (ahi esta la causa real). Se guarda con los logs; la ventana lo muestra para
# copiarlo de una vez.
# error_report <informe> <lo que se instalaba> <log del paso o ""> <paso> <config.log o "">
function error_report() {
    local out=$1 what=$2 log=$3 desc=$4 config=$5
    {
        echo "$APP_NAME $APP_VERSION - error al instalar"
        echo "Fecha: $(date '+%Y-%m-%d %H:%M')"
        echo "Sistema: macOS $(sw_vers -productVersion 2> /dev/null) ($(uname -m))"
        echo "Compilador: $(cc --version 2> /dev/null | head -1)"
        echo "Instalacion: $what"
        if [ -n "$log" ] && [ -f "$log" ]; then
            echo "Paso que fallo: $desc ($(basename "$log"))"
            local errors=$(grep -E -m 10 '(error:|Error:|ERROR|CMake Error|Undefined symbols|No such file)' "$log" | cut -c1-300)
            [ -n "$errors" ] && printf '\n== Primeros errores ==\n%s\n' "$errors"
            printf '\n== Ultimas 60 lineas de %s ==\n' "$(basename "$log")"
            tail -60 "$log"
        elif [ -n "$desc" ]; then
            # (falló antes de compilar: al descargar o comprobar el código)
            echo "Motivo: $desc"
        fi
        if [ -n "$config" ] && [ -f "$config" ]; then
            printf '\n== config.log: lo ultimo antes del error ==\n'
            awk '/^## Cache variables/ {exit} {print}' "$config" | grep -v '^## -* ##$' | tail -60
        fi
        printf '\nLogs completos: %s\n' "$(dirname "$out")"
    } > "$out" 2>&1
}

# Claves SSH publicadas de GitHub, GitLab y Bitbucket (para clonar sin aceptar claves nuevas sin mirar)
GIT_KNOWN_HOSTS='github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
gitlab.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf
gitlab.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFSMqzJeV9rUzU4kWitGjeR4PWSa29SPqJ1fVkhtj3Hw9xjLVXVYrU9QlYWrOLXBpQ6KWjbjTDTdDkoohFzgbEY=
bitbucket.org ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIazEu89wgQZ4bqs3d63QSMzYVa0MuJ2e2gKTKqu+UUO
bitbucket.org ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBPIQmuzMBuKdWeF4+a2sjSSpBK0iqitSQ+5BM9KhpexuGt20JpTVM7u5BDZngncgrqDMbWdxMWWOGtZ9UgbqgZE='

# Ejecuta una orden en una sesion nueva, sin terminal de control: NO_TTY_PY <orden> [argumentos...]
NO_TTY_PY='
import os, signal, sys
# El hijo, en su sesion; este proceso se queda en el grupo de la tarea y le pasa las señales de
# Cancelar o Ctrl-C (si no, la compilacion seguiria despues de cancelar)
pid = os.fork()
if pid == 0:
    os.setsid()
    try:
        os.execvp(sys.argv[1], sys.argv[1:])
    except OSError as e:
        sys.stderr.write("%s: %s\n" % (sys.argv[1], e.strerror))
        os._exit(127)
def forward(sig, _):
    try:
        os.killpg(pid, sig)
    except OSError:
        pass
for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(s, forward)
while True:
    try:
        _, status = os.waitpid(pid, 0)
        break
    except InterruptedError:
        continue
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 128 + os.WTERMSIG(status))
'

# no_tty <orden> [argumentos...]: para programas que leen tu configuracion (git, ssh, certutil). Sin
# terminal de control (no pueden usar el permiso de sudo recordado ni abrir /dev/tty) y sin la terminal
# en sus descriptores: la salida pasa por una tuberia, asi que nada que dejen en marcha puede quedarse
# leyendola hasta que sudo pida la contraseña
function no_tty() {
    ( set -o pipefail; /usr/bin/python3 -I -c "$NO_TTY_PY" "$@" < /dev/null 2>&1 | cat )
}

function step() {
    local part=$1 from=$2 to=$3 lines=$4 desc=$5 log=$6
    shift 6

    if [ "$lines" -eq 0 ]; then
        progress "$part" "$from" "$to" "${desc,,}" percent "$log" 100
    else
        progress "$part" "$from" "$to" "${desc,,}" lines "$log" "$lines"
    fi
    printf '  [%3d%%] %s...\n' "$from" "$desc"
    # Sin terminal (en su propia sesion): lo que se compila esta en una carpeta tuya y lo puede cambiar
    # cualquier programa tuyo; con la terminal de la tarea podria usar el permiso de sudo que ya se ha
    # dado (sudo -n). Sin ella, sudo le pediria la contraseña y falla
    if ! /usr/bin/python3 -I -c "$NO_TTY_PY" "$@" > "$log" 2>&1 < /dev/null; then
        echo "  ERROR: $desc. Ultimas lineas de $(basename "$log"):"
        tail -25 "$log" | sed 's/^/    /'
        STEP_LOG=$log STEP_DESC=$desc
        # Compilando en paralelo, el error real queda lejos del final (tapado por avisos de otros
        # procesos): se repiten al final los primeros errores, que salen tambien en el resumen
        local errors=$(grep -E -m 5 '(error:|Error:|CMake Error|Undefined symbols)' "$log" | cut -c1-200)
        [ -n "$errors" ] && echo "  Primeros errores:" && sed 's/^/    /' <<< "$errors"

        return 1
    fi
}

# Quita de los flags de un build de CMake la carpeta usr/include del SDK de macOS. La meten los
# .pc de Homebrew para librerias del sistema (zlib, libxml2...), que apuntan a un SDK concreto
# (MacOSX14.sdk) distinto del que usa el compilador (MacOSX.sdk), y CMake no la reconoce como del
# sistema: con -I queda por delante de las cabeceras de C++ (c++/v1) y no compila nada en C++
# ("<cstddef> tried including <stddef.h> but didn't find libc++'s <stddef.h>"). El compilador ya
# busca en el SDK por su cuenta, asi que quitarla no cambia nada mas.
# strip_sdk_includes <carpeta del build>
function strip_sdk_includes() {
    local files
    files=$(grep -rlE --include=flags.make -e '-(I|isystem ?)"?[^ "]*/SDKs/MacOSX[0-9.]*\.sdk/usr/include"?( |$)' "$1")
    [ -z "$files" ] && return 0
    echo "lvm-instalador: quitando la carpeta usr/include del SDK de los flags de:"
    while IFS= read -r file; do
        echo "  $file"
        sed -i '' -E 's#-(I|isystem ?)"?[^ "]*/SDKs/MacOSX[0-9.]*\.sdk/usr/include"?( |$)##g' "$file"
    done <<< "$files"
}

# Copia dentro de <carpeta>/lib las librerias de Homebrew que usan los binarios de la pila y cambia
# sus referencias a esa copia (con la ruta final <destino>/lib), para que la version siga
# funcionando aunque se actualice o desinstale Homebrew. Los archivos tocados se vuelven a firmar
# (en Apple Silicon un binario modificado sin firmar no arranca).
# bundle_libs <carpeta en el area temporal> <ruta final de esa carpeta>
function bundle_libs() {
    python3 -I - "$1" "$2" <<'EOF'
import os, shutil, subprocess, sys

stage, final = sys.argv[1], sys.argv[2]
stage_lib, final_lib = os.path.join(stage, "lib"), os.path.join(final, "lib")
MAGIC = {b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe"}

def is_macho(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) in MAGIC
    except OSError:
        return False

def deps(path):
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True).stdout.splitlines()[1:]
    return [line.strip().split(" (")[0] for line in out if line.strip()]

def rpaths(path):
    out = subprocess.run(["otool", "-l", path], capture_output=True, text=True).stdout.splitlines()
    found = []
    for i, line in enumerate(out):
        if "cmd LC_RPATH" in line:
            for extra in out[i + 1:i + 4]:
                extra = extra.strip()
                if extra.startswith("path "):
                    found.append(extra.split()[1])
    return found

def resolve(dep, origin):
    base = os.path.dirname(origin)
    if dep.startswith(("@loader_path/", "@executable_path/")):
        return os.path.realpath(os.path.join(base, dep.split("/", 1)[1]))
    if dep.startswith("@rpath/"):
        for rp in rpaths(origin):
            rp = rp.replace("@loader_path", base).replace("@executable_path", base)
            candidate = os.path.join(rp, dep[len("@rpath/"):])
            if os.path.exists(candidate):
                return os.path.realpath(candidate)
        return None
    return dep

def tool(*args):
    subprocess.run(list(args), check=True, capture_output=True)

os.makedirs(stage_lib, exist_ok=True)
queue = []
for dirpath, _, files in os.walk(stage):
    for name in files:
        path = os.path.join(dirpath, name)
        if not os.path.islink(path) and is_macho(path):
            queue.append((path, path))

copied, changed = {}, set()
while queue:
    path, origin = queue.pop()
    for dep in deps(path):
        real = resolve(dep, origin)
        if not real or not real.startswith("/opt/homebrew/"):
            continue
        name = os.path.basename(dep)
        new = os.path.join(final_lib, name)
        if name not in copied:
            dest = os.path.join(stage_lib, name)
            shutil.copy2(real, dest)
            os.chmod(dest, 0o755)
            tool("install_name_tool", "-id", new, dest)
            copied[name] = real
            changed.add(dest)
            queue.append((dest, real))
        tool("install_name_tool", "-change", dep, new, path)
        changed.add(path)

for path in changed:
    tool("codesign", "--force", "--sign", "-", path)

print("  %d librerias de Homebrew copiadas en %s" % (len(copied), final_lib))
EOF
}

# OpenSSL 1.1.1w estatico para PHP 7.4 y 8.0 (en <deps>, solo para compilar). Ocupa 5 puntos de
# la barra desde <inicio>.
function build_openssl11() {
    local deps=$1 p=$2

    tar -xzf openssl11.tar.gz && cd "openssl-$OPENSSL11_VERSION" || return 1
    step 3 $p $((p + 1)) 30 "OpenSSL $OPENSSL11_VERSION: configurando" "$build/openssl11-configure.log" \
        ./Configure darwin64-arm64-cc no-shared no-tests --prefix="$deps" --openssldir=/private/etc/ssl || return 1
    step 3 $((p + 1)) $((p + 4)) 1700 "OpenSSL $OPENSSL11_VERSION: compilando" "$build/openssl11-make.log" make -j"$jobs" || return 1
    step 3 $((p + 4)) $((p + 5)) 300 "OpenSSL $OPENSSL11_VERSION: instalando" "$build/openssl11-install.log" make install_sw || return 1
    cd "$build" || return 1
}

# ICU 72.1 estatico para PHP 7.4, 8.0 y 8.1 (en <deps>, solo para compilar). Ocupa 5 puntos de
# la barra desde <inicio>.
function build_icu72() {
    local deps=$1 p=$2

    tar -xzf icu72.tgz && cd icu/source || return 1
    step 3 $p $((p + 1)) 250 "ICU 72.1: configurando" "$build/icu72-configure.log" \
        ./runConfigureICU MacOSX --prefix="$deps" --enable-static --disable-shared --with-data-packaging=static \
        --disable-tests --disable-samples --disable-extras || return 1
    step 3 $((p + 1)) $((p + 4)) 900 "ICU 72.1: compilando" "$build/icu72-make.log" make -j"$jobs" || return 1
    step 3 $((p + 4)) $((p + 5)) 200 "ICU 72.1: instalando" "$build/icu72-install.log" make install || return 1
    cd "$build" || return 1
}

# Crea en xamppfiles/var/mysql unas bases de datos nuevas y vacias: solo las del sistema de
# MariaDB, root sin contraseña (como XAMPP) y la base 'phpmyadmin' con el usuario 'pma'.
function init_stack_databases() {
    local target=$1 user=$2
    local data=$target/var/mysql my=$target/mysql cnf=$target/etc/my.cnf

    if [ -e "$data" ]; then
        echo "Ya existe $data, no se crean bases de datos nuevas"

        return 1
    fi

    echo "  Creando bases de datos propias y vacias..."
    # (el ayudante de PAM no se copia a la version; si estuviera, fuera antes: mariadb-install-db le
    # daria la carpeta a tu usuario con un programa setuid de root dentro)
    $SUDO rm -rf "$my/lib/plugin/auth_pam_tool_dir" || return 1
    $SUDO "$my/scripts/mariadb-install-db" --defaults-file="$cnf" --basedir="$my" --datadir="$data" --user="$user" \
        --auth-root-authentication-method=normal --skip-test-db > "$LOG_DIR/install-db.log" 2>&1 \
        || { tail -20 "$LOG_DIR/install-db.log"; return 1; }
    # (y despues, por si acaso)
    $SUDO rm -rf "$my/lib/plugin/auth_pam_tool_dir"

    # Apache y PHP-FPM tienen que poder llegar a mysql.sock, que esta en esta carpeta
    $SUDO chown "$user" "$data"
    $SUDO chmod 775 "$data"

    # MariaDB temporal sin red y con su propio socket: no choca con la version en marcha. La
    # carpeta la crea root y solo es del usuario del servidor (no pide contraseña mientras se prepara)
    local tmp=$($SUDO mktemp -d /tmp/lvm-mysql-XXXX)
    local sock=$tmp/mysql.sock pid=$tmp/mysql.pid
    $SUDO chown "$user" "$tmp"
    $SUDO "$my/bin/mariadbd" --defaults-file="$cnf" --skip-networking --socket="$sock" --pid-file="$pid" \
        --log-error="$tmp/mysql.log" > /dev/null 2>&1 &
    local server_pid=$!

    local i
    for i in $(seq 150); do $SUDO test -S "$sock" && break; sleep 0.2; done

    local mysql=($SUDO "$my/bin/mariadb" --no-defaults -S "$sock" -uroot)
    $SUDO chmod 700 "$tmp"
    local ok=0
    if $SUDO test -S "$sock" \
        && "${mysql[@]}" < "$target/phpmyadmin/sql/create_tables.sql" \
        && "${mysql[@]}" -e "CREATE USER IF NOT EXISTS 'pma'@'localhost';
            GRANT SELECT, INSERT, UPDATE, DELETE ON phpmyadmin.* TO 'pma'@'localhost';
            FLUSH PRIVILEGES;"; then
        ok=1
    fi

    # (la carpeta es de tu usuario, con el que corre el servidor: el .pid solo vale si es de verdad
    # ese servidor; si no, se para el sudo que lo arranco)
    local spid
    if $SUDO test -f "$pid"; then
        spid=$(db_temp_pid "$pid" "$sock") && $SUDO kill "$spid" || db_temp_kill_launched "$server_pid" "$sock"
    fi
    for i in $(seq 150); do $SUDO test -f "$pid" || break; sleep 0.2; done
    $SUDO rm -rf "$tmp"

    if [ $ok -eq 0 ]; then
        echo "  Aviso: no se pudo crear la base 'phpmyadmin'; phpMyAdmin funcionara pero avisara de que falta su almacenamiento"
    fi

    return 0
}

# Escribe la configuracion de la pila en la carpeta temporal $S (que se copiara a $target).
# Usa las variables de install_stack.
function write_stack_files() {
    local test_mode=0
    [ -n "$TEST_DIR" ] && test_mode=1

    mkdir -p "$S"/{bin,etc/extra,etc/ssl.crt,etc/ssl.key,logs,tmp,cgi-bin,var/run,var/proftpd,php/etc/conf.d}

    # --- Apache ---
    local mods="mpm_event authn_file authn_core authz_host authz_groupfile authz_user authz_core access_compat
        auth_basic socache_shmcb reqtimeout include filter deflate brotli mime log_config env expires headers
        setenvif version proxy proxy_fcgi proxy_http ssl http2 unixd status autoindex cgid vhost_alias
        negotiation dir actions alias rewrite remoteip"
    local m load=""
    for m in $mods; do
        [ -f "$S/apache2/modules/mod_$m.so" ] && load+="LoadModule ${m}_module apache2/modules/mod_$m.so"$'\n'
    done

    cat > "$S/etc/httpd.conf" <<EOF
# Apache $apache de XAMPP-$vname (lvm-instalador)
ServerRoot "$target"
# Solo desde este Mac
Listen 127.0.0.1:$PORT_HTTP
Listen [::1]:$PORT_HTTP

$load
<IfModule unixd_module>
User $web_user
Group $web_group
</IfModule>

ServerAdmin you@example.com
ServerName localhost:$PORT_HTTP
PidFile "logs/httpd.pid"
Timeout 300
KeepAlive On

<Directory />
    AllowOverride None
    Require all denied
</Directory>

DocumentRoot "$docroot"
<Directory "$docroot">
    # (sin ExecCGI ni Includes: en htdocs solo hay proyectos PHP)
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

DirectoryIndex index.php index.html index.htm

<Files ".ht*">
    Require all denied
</Files>

ErrorLog "logs/error_log"
LogLevel warn
LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" combined
LogFormat "%h %l %u %t \"%r\" %>s %b" common
CustomLog "logs/access_log" common

ScriptAlias /cgi-bin/ "$target/cgi-bin/"
<Directory "$target/cgi-bin">
    AllowOverride None
    Options None
    Require all granted
</Directory>

TypesConfig apache2/conf/mime.types
AddType application/x-compress .Z
AddType application/x-gzip .gz .tgz
# Scripts CGI, solo en cgi-bin (Perl de esta version: #!$link_files/bin/perl). En htdocs no: un .pl
# o un .cgi subido a un proyecto no se ejecuta

<IfModule http2_module>
    Protocols h2 h2c http/1.1
</IfModule>

# Antes de los vhosts: los dominios que no tienen ninguno solo pasan si son localhost
Include $UNKNOWN_HOST_CONF
Include etc/extra/httpd-vhosts.conf
Include etc/extra/httpd-ssl.conf
Include etc/extra/httpd-xampp.conf
EOF
    unknown_host_vhost > "$S/$UNKNOWN_HOST_CONF"
    # OpenSSL (copiado de Homebrew) con la configuracion de la version, no la de /opt/homebrew
    echo "# OpenSSL de esta version (lvm-instalador): sin configuracion ni modulos de fuera" > "$S/etc/openssl.cnf"

    cat > "$S/etc/extra/httpd-ssl.conf" <<EOF
# HTTPS con un certificado autofirmado para localhost (los vhosts usan los suyos)
Listen 127.0.0.1:$PORT_HTTPS
Listen [::1]:$PORT_HTTPS
SSLCipherSuite HIGH:MEDIUM:!aNULL:!MD5
SSLProtocol all -SSLv3
SSLPassPhraseDialog builtin
SSLSessionCache "shmcb:$target/logs/ssl_scache(512000)"
SSLSessionCacheTimeout 300

<VirtualHost _default_:$PORT_HTTPS>
    DocumentRoot "$docroot"
    ServerName localhost:$PORT_HTTPS
    ErrorLog "$target/logs/error_log"
    TransferLog "$target/logs/access_log"
    SSLEngine on
    SSLCertificateFile "$target/etc/ssl.crt/server.crt"
    SSLCertificateKeyFile "$target/etc/ssl.key/server.key"
</VirtualHost>
EOF

    cat > "$S/etc/extra/httpd-xampp.conf" <<EOF
# PHP $version via PHP-FPM
SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=\$1
ProxyTimeout 300
<FilesMatch "\.php$">
    SetHandler "proxy:unix:$target/var/run/php-fpm.sock|fcgi://localhost"
</FilesMatch>

# phpMyAdmin $pma, solo desde este equipo
Alias /phpmyadmin "$target/phpmyadmin"
<Directory "$target/phpmyadmin">
    AllowOverride AuthConfig Limit
    Require local
</Directory>
EOF

    # El openssl de macOS es LibreSSL: se usa el de Homebrew
    "$(brew --prefix openssl@3)/bin/openssl" req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/CN=localhost" \
        -addext "basicConstraints=critical,CA:FALSE" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
        -keyout "$S/etc/ssl.key/server.key" -out "$S/etc/ssl.crt/server.crt" > /dev/null 2>&1

    # --- PHP ---
    cat > "$S/php/etc/conf.d/99-xampp.ini" <<EOF
; Mismos valores que el php.ini de XAMPP. Sin error_log: los errores van al log de Apache
memory_limit = 512M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 120
max_input_time = 60
max_input_vars = 3000
date.timezone = $PHP_TIMEZONE
error_reporting = E_ALL & ~E_DEPRECATED
display_errors = Off
log_errors = On
mysqli.default_socket = $target/var/mysql/mysql.sock
pdo_mysql.default_socket = $target/var/mysql/mysql.sock
; Certificados del sistema (macOS), para HTTPS desde PHP
openssl.cafile = /etc/ssl/cert.pem
curl.cainfo = /etc/ssl/cert.pem
opcache.enable = 1
opcache.revalidate_freq = 0
EOF

    # Contra PHP2Shell (va despues de 99-xampp.ini; SECURE_PY lo deja igual en las ya instaladas)
    { printf '%s' "$PHP_SECURITY_INI"
      if [ "${short%%.*}" -gt 8 ] || { [ "${short%%.*}" -eq 8 ] && [ "${short#*.}" -ge 5 ]; }; then
          printf '%s' "$PHP_SECURITY_INI_85"
      fi
    } > "$S/php/etc/conf.d/zz-lvm-seguridad.ini" || return 1

    # A partir de PHP 8.5 opcache va integrado y no se carga como extension
    if ls "$S"/php/lib/php/extensions/*/opcache.so > /dev/null 2>&1; then
        echo "zend_extension = opcache" > "$S/php/etc/conf.d/10-opcache.ini"
    fi

    cat > "$S/php/etc/php-fpm.conf" <<EOF
[global]
pid = $target/var/run/php-fpm.pid
error_log = $target/logs/php-fpm.log
daemonize = yes

[xampp]
user = $web_user
group = $web_group
listen = $target/var/run/php-fpm.sock
listen.owner = $web_user
listen.group = $web_group
listen.mode = 0660
pm = ondemand
pm.max_requests = 50
pm.max_children = 20
pm.process_idle_timeout = 60s
request_terminate_timeout = 300
catch_workers_output = yes
EOF

    # --- MariaDB: se ejecuta con el usuario del Mac ---
    mkdir -p "$S/etc/lvm-sin-ficheros"
    cat > "$S/etc/my.cnf" <<EOF
# MariaDB $mariadb de XAMPP-$vname (lvm-instalador)
[client]
port = $PORT_MYSQL
socket = $target/var/mysql/mysql.sock
default-character-set = utf8mb4

[mysqld]
user = $web_user
port = $PORT_MYSQL
# Solo desde este Mac
bind-address = 127.0.0.1
# Sin leer ni escribir ficheros del Mac desde SQL (la carpeta esta vacia y es de root)
secure-file-priv = "$target/etc/lvm-sin-ficheros"
local-infile = 0
socket = $target/var/mysql/mysql.sock
basedir = $target/mysql
datadir = $target/var/mysql
plugin_dir = $target/mysql/lib/plugin
pid-file = $target/var/mysql/mysqld.pid
log-error = $target/var/mysql/mysqld.err
max_allowed_packet = 512M
table_open_cache = 640
sort_buffer_size = 5120K
read_buffer_size = 2560K
read_rnd_buffer_size = 5120K
myisam_sort_buffer_size = 80M
innodb_lock_wait_timeout = 50
# Mismo cotejamiento que XAMPP, para que los volcados se puedan importar en versiones
# anteriores y en los servidores (desde MariaDB 11.2 el de por defecto es uca1400)
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
loose-character-set-collations = utf8mb4=utf8mb4_general_ci

[mysqldump]
max_allowed_packet = 512M
EOF

    # --- ProFTPD: acceso a htdocs con el usuario del Mac y su contraseña (PAM de macOS) ---
    local pam=ftpd
    [ -f /etc/pam.d/ftpd ] || pam=login
    cat > "$S/etc/proftpd.conf" <<EOF
# ProFTPD $ftp de XAMPP-$vname (lvm-instalador)
ServerName "ProFTPD XAMPP-$vname"
ServerType standalone
DefaultServer on
Port $PORT_FTP
# Solo desde este Mac
DefaultAddress 127.0.0.1
SocketBindTight on
Umask 022
MaxInstances 30
User $web_user
Group $web_group
PidFile $target/var/proftpd/proftpd.pid
ScoreboardFile $target/var/proftpd/proftpd.scoreboard
SystemLog $target/logs/proftpd.log
TransferLog $target/logs/xferlog
UseReverseDNS off
RequireValidShell off
<IfModule mod_ident.c>
    IdentLookups off
</IfModule>
<IfModule mod_delay.c>
    DelayTable $target/var/proftpd/proftpd.delay
</IfModule>
<IfModule mod_auth_pam.c>
    AuthPAM on
    AuthPAMConfig $pam
    AuthOrder mod_auth_pam.c* mod_auth_unix.c
</IfModule>

DefaultRoot $ftp_root
<Limit LOGIN>
    AllowUser $web_user
    DenyAll
</Limit>
<Directory $ftp_root/*>
    AllowOverwrite on
</Directory>
<Limit SITE_CHMOD>
    DenyAll
</Limit>
EOF

    # --- phpMyAdmin: como en XAMPP, entra como root sin contraseña ---
    local secret=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
    cat > "$S/phpmyadmin/config.inc.php" <<EOF
<?php
declare(strict_types=1);

\$cfg['blowfish_secret'] = '$secret';

\$i = 1;
\$cfg['Servers'][\$i]['auth_type'] = 'config';
\$cfg['Servers'][\$i]['user'] = 'root';
\$cfg['Servers'][\$i]['password'] = '';
\$cfg['Servers'][\$i]['host'] = 'localhost';
\$cfg['Servers'][\$i]['socket'] = '$target/var/mysql/mysql.sock';
\$cfg['Servers'][\$i]['AllowNoPassword'] = true;
\$cfg['Servers'][\$i]['controluser'] = 'pma';
\$cfg['Servers'][\$i]['controlpass'] = '';
\$cfg['Servers'][\$i]['pmadb'] = 'phpmyadmin';
EOF
    for m in bookmark relation table_info table_coords pdf_pages column_info history table_uiprefs tracking \
        userconfig recent users usergroups navigationhiding savedsearches central_columns designer_settings \
        export_templates favorite; do
        local key=$m
        [ "$m" == "bookmark" ] && key=bookmarktable
        echo "\$cfg['Servers'][\$i]['$key'] = 'pma__$m';" >> "$S/phpmyadmin/config.inc.php"
    done
    cat >> "$S/phpmyadmin/config.inc.php" <<EOF

\$cfg['TempDir'] = '$target/phpmyadmin/tmp';
\$cfg['UploadDir'] = '';
\$cfg['SaveDir'] = '';
EOF
    mkdir -p "$S/phpmyadmin/tmp"

    # --- Script de arranque y parada, como el de XAMPP para Mac (lo usa "lvm-instalador use") ---
    sed -e "s|@ROOT@|$target|g" -e "s|@NAME@|$vname|g" -e "s|@NEED_ROOT@|$(( 1 - test_mode ))|g" \
        -e "s|@WEB_USER@|$web_user|g" > "$S/xampp" <<'EOF'
#!/bin/bash
# Arranque y parada de XAMPP-@NAME@ (pila propia creada por lvm-instalador):
# Apache con PHP-FPM, MariaDB y ProFTPD.
# Uso: xampp start|stop|restart|status|startapache|stopapache|reloadapache|startmysql|stopmysql|startftp|stopftp

ROOT=@ROOT@
# Como root, solo los programas del sistema (Homebrew es de tu usuario)
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
# OpenSSL: solo su configuracion (no la de Homebrew, que es de tu usuario)
export OPENSSL_CONF=$ROOT/etc/openssl.cnf
export OPENSSL_MODULES=$ROOT/lib/ossl-modules
APACHE_PID=$ROOT/logs/httpd.pid
MYSQL_PID=$ROOT/var/mysql/mysqld.pid
MYSQL_SOCK=$ROOT/var/mysql/mysql.sock
FTP_PID=$ROOT/var/proftpd/proftpd.pid
# MariaDB con tu usuario, no como root: var/mysql (sus datos, su pid y su registro) es tuya, y
# como root mariadbd-safe escribiria donde apuntara un enlace puesto ahi, y kill mataria el
# proceso cuyo numero se hubiera escrito en el pid
WEB_USER=@WEB_USER@
as_web() {
    if [ "$(id -u)" -eq 0 ] && [ -n "$WEB_USER" ] && [ "$WEB_USER" != root ]; then
        /usr/bin/sudo -u "$WEB_USER" "$@"
    else
        "$@"
    fi
}

if [ @NEED_ROOT@ -eq 1 ] && [ "$(id -u)" -ne 0 ]; then
    echo "Hay que ejecutarlo como administrador: sudo $0 $*"
    exit 1
fi

function running() {
    [ -f "$1" ] && kill -0 "$(cat "$1" 2> /dev/null)" 2> /dev/null
}

#@incluir comun/pila-propia-version-php/wait_until.sh
# Programa que ya escucha en un puerto (el Apache de macOS, otro XAMPP...)
function port_owner() {
    lsof -nP -iTCP:"$1" -sTCP:LISTEN 2> /dev/null | awk 'NR == 2 {print $1 " (PID " $2 ")"}'
}

function start_apache() {
    running "$APACHE_PID" && { echo "Apache ya estaba arrancado."; return 0; }

    # (< /dev/null en todo lo que se queda en marcha: si no, se queda con la terminal de la tarea
    # que lo arranca y la ventana no ve el final)
    "$ROOT/bin/pvm-php-fpm" start < /dev/null
    # Como XAMPP: los avisos del arranque (vhosts sin carpeta, certificados...) van al log
    if "$ROOT/apache2/bin/httpd" -f "$ROOT/etc/httpd.conf" -E "$ROOT/logs/error_log" -k start < /dev/null >> "$ROOT/logs/error_log" 2>&1 \
        && wait_until 10 running "$APACHE_PID"; then
        echo "Apache arrancado."
    else
        local port=$(sed -n 's/^Listen //p' "$ROOT/etc/httpd.conf" | head -1)
        local owner=$(port_owner "$port")
        echo "Apache no ha arrancado. Revisa $ROOT/logs/error_log"
        [ -n "$owner" ] && echo "El puerto $port ya lo usa $owner. Si es el Apache de macOS: sudo apachectl stop"
        return 1
    fi
}

function stop_apache() {
    if running "$APACHE_PID"; then
        "$ROOT/apache2/bin/httpd" -f "$ROOT/etc/httpd.conf" -k stop
        wait_until 15 stopped "$APACHE_PID"
        echo "Apache parado."
    fi
    "$ROOT/bin/pvm-php-fpm" stop
}

function reload_apache() {
    "$ROOT/bin/pvm-php-fpm" reload
    running "$APACHE_PID" && "$ROOT/apache2/bin/httpd" -f "$ROOT/etc/httpd.conf" -E "$ROOT/logs/error_log" -k graceful >> "$ROOT/logs/error_log" 2>&1 \
        && echo "Apache recargado."
}

function start_mysql() {
    running "$MYSQL_PID" && { echo "MariaDB ya estaba arrancado."; return 0; }

    # mariadbd-safe busca sus herramientas desde la carpeta de MariaDB
    (cd "$ROOT/mysql" && as_web /usr/bin/nohup ./bin/mariadbd-safe --defaults-file="$ROOT/etc/my.cnf" < /dev/null > /dev/null 2>&1 &)
    if wait_until 60 mysql_ready; then
        echo "MariaDB arrancado."
    else
        echo "MariaDB no ha arrancado. Revisa $ROOT/var/mysql/mysqld.err"
        return 1
    fi
}

function stop_mysql() {
    running "$MYSQL_PID" || return 0

    as_web kill "$(cat "$MYSQL_PID")"
    wait_until 60 stopped "$MYSQL_PID" && echo "MariaDB parado." || echo "MariaDB sigue parandose."
}

function start_ftp() {
    running "$FTP_PID" && { echo "ProFTPD ya estaba arrancado."; return 0; }

    if "$ROOT/proftpd/sbin/proftpd" -c "$ROOT/etc/proftpd.conf" < /dev/null 2> /dev/null && wait_until 5 running "$FTP_PID"; then
        echo "ProFTPD arrancado."
    else
        echo "ProFTPD no ha arrancado. Revisa $ROOT/logs/proftpd.log"
        return 1
    fi
}

function stop_ftp() {
    running "$FTP_PID" || return 0

    kill "$(cat "$FTP_PID")"
    wait_until 10 stopped "$FTP_PID"
    echo "ProFTPD parado."
}

function status() {
    local name pid

    echo "XAMPP-@NAME@ (pila propia)"
    for name in Apache MariaDB ProFTPD; do
        case $name in
            Apache) pid=$APACHE_PID ;;
            MariaDB) pid=$MYSQL_PID ;;
            ProFTPD) pid=$FTP_PID ;;
        esac
        running "$pid" && echo "$name esta arrancado." || echo "$name no esta arrancado."
    done
    "$ROOT/bin/pvm-php-fpm" status
}

case "$1" in
    # El FTP solo si se ha activado (xampp startftp; lo quita xampp stopftp)
    start) echo "Arrancando XAMPP-@NAME@..."; start_mysql; start_apache; if [ -f "$ROOT/etc/lvm-startftp" ]; then start_ftp; fi ;;
    stop) echo "Parando XAMPP-@NAME@..."; stop_apache; stop_mysql; stop_ftp ;;
    restart|reload) "$0" stop; "$0" start ;;
    status) status ;;
    startapache) start_apache ;;
    stopapache) stop_apache ;;
    reloadapache) reload_apache ;;
    restartapache) stop_apache; start_apache ;;
    startmysql) start_mysql ;;
    stopmysql) stop_mysql ;;
    restartmysql) stop_mysql; start_mysql ;;
    startftp) touch "$ROOT/etc/lvm-startftp"; start_ftp ;;
    stopftp) rm -f "$ROOT/etc/lvm-startftp"; stop_ftp ;;
    *) sed -n '4p' "$0" | sed 's/^# //'; exit 1 ;;
esac
EOF
    chmod 755 "$S/xampp"

    # PHP-FPM se arranca con el entorno limpio
    fpm_script_template | sed -e "s|@ROOT@|$target|g" -e "s|@VERSION@|$version|g" > "$S/bin/pvm-php-fpm"
    chmod 755 "$S/bin/pvm-php-fpm"

    # --- Comandos en bin/, como en XAMPP: /Applications/XAMPP/xamppfiles/bin/php, .../bin/mysql... ---
    for m in php php-config phpize; do ln -s "../php/bin/$m" "$S/bin/$m"; done
    for m in perl perldoc cpan; do ln -s "../perl/bin/$m" "$S/bin/$m"; done
    for m in httpd ab htpasswd; do [ -e "$S/apache2/bin/$m" ] && ln -s "../apache2/bin/$m" "$S/bin/$m"; done

    # Los clientes de MariaDB leen el my.cnf de esta version (socket y puerto). Los nombres
    # antiguos (mysql, mysqldump...) llaman a los nuevos, que no avisan de que estan obsoletos.
    local name real
    for name in mysql:mariadb mysqldump:mariadb-dump mysqladmin:mariadb-admin mysqlcheck:mariadb-check \
        mysqlimport:mariadb-import mysqlshow:mariadb-show mysql_upgrade:mariadb-upgrade; do
        real=${name#*:}
        [ -e "$S/mysql/bin/$real" ] || real=${name%%:*}
        [ -e "$S/mysql/bin/$real" ] || continue
        for m in ${name%%:*} ${name#*:}; do
            printf '#!/bin/sh\nexec %s/mysql/bin/%s --defaults-file=%s/etc/my.cnf "$@"\n' "$target" "$real" "$target" > "$S/bin/$m"
            chmod 755 "$S/bin/$m"
        done
    done

    # htdocs y vhosts compartidos con las demas versiones; /Applications/XAMPP-X.Y/htdocs como en XAMPP
    if [ $test_mode -eq 1 ]; then
        mkdir -p "$S/htdocs"
        echo '<?php phpinfo();' > "$S/htdocs/index.php"
        : > "$S/etc/extra/httpd-vhosts.conf"
    else
        ln -s "$COMMON/htdocs" "$S/htdocs"
        ln -s "$COMMON/httpd-vhosts.conf" "$S/etc/extra/httpd-vhosts.conf"
    fi
    ln -s xamppfiles/htdocs "$stage$root/htdocs"

    echo "$version" > "$S/etc/pvm-php"
    # (con el parche de seguridad contra PHP2Shell: PHP sigue llamandose igual, la marca lo dice)
    [ -n "$php_patch" ] && echo "CVE-2026-109618-109619|$php_patch|$PHP2SHELL_DATE" > "$S/etc/lvm-parche-php2shell"
    echo "$version|$apache|$mariadb|$ftp|$perl|$pma" > "$S/etc/pvm-stack"
    # Ya se instala solo para este Mac (secure_version no tiene nada que cambiar)
    echo "1" > "$S/etc/lvm-seguridad"
}

# Script pvm-php-fpm de una version, con @ROOT@ (su xamppfiles) y @VERSION@ (la de PHP): PHP-FPM con
# el entorno limpio y el php.ini y conf.d de su carpeta, no los que trae compilados (en las versiones
# de antes de la 1.39.3, que se compilaron en /Applications, serian los de alli). Tambien lo usa migrar
function fpm_script_template() {
    cat <<'EOF'
#!/bin/bash
# PHP-FPM @VERSION@ (lo arrancan y paran startapache/stopapache del script xampp)
FPM=@ROOT@/php/sbin/php-fpm
CONF=@ROOT@/php/etc/php-fpm.conf
INI=@ROOT@/php/etc/php.ini
PID=@ROOT@/var/run/php-fpm.pid

running() { [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2> /dev/null; }

case "$1" in
    start)
        running || env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin OPENSSL_CONF="${FPM%/php/sbin/php-fpm}/etc/openssl.cnf" \
            OPENSSL_MODULES="${FPM%/php/sbin/php-fpm}/lib/ossl-modules" PHP_INI_SCAN_DIR="${INI%/php.ini}/conf.d" \
            "$FPM" -c "$INI" --fpm-config "$CONF"
        ;;
    stop)
        running && kill -QUIT "$(cat "$PID")"
        for i in $(seq 50); do running || break; sleep 0.1; done
        ;;
    reload)
        running && kill -USR2 "$(cat "$PID")"
        ;;
    status)
        running && echo "PHP-FPM @VERSION@ esta arrancado." || echo "PHP-FPM @VERSION@ no esta arrancado."
        ;;
esac
EOF
}

# Enlaces de lo compilado que llevan fuera de la version (salvo htdocs y los vhosts compartidos):
# lo compilado es de tu usuario hasta que root lo copia, y un programa tuyo podria dejar un enlace
# a /etc para que root lo cambiara despues. Uso: <carpeta temporal> <carpeta definitiva> <compartida>
BUILD_LINKS_PY='
import os, posixpath, sys
root, target = sys.argv[1], sys.argv[2]
ok = {"htdocs": "xamppfiles/htdocs", "xamppfiles/htdocs": sys.argv[3] + "/htdocs",
      "xamppfiles/etc/extra/httpd-vhosts.conf": sys.argv[3] + "/httpd-vhosts.conf"}
# (los compartidos llevan a carpetas tuyas: nada puede apuntar a traves de ellos)
shared = [posixpath.join(target, k) for k in ok]
def under(path, top):
    return path == top or path.startswith(top + "/")
me = os.getuid()
for d, dirs, files in os.walk(root):
    for name in dirs + files:
        p = os.path.join(d, name)
        if not os.path.islink(p):
            # En la carpeta temporal todo lo ha creado tu usuario: un fichero de otro es un enlace duro
            # a un fichero suyo (macOS no los protege) que root copiaria
            if root != target and os.lstat(p).st_uid != me:
                print("%s (de otro usuario: enlace duro)" % os.path.relpath(p, root))
            continue
        rel, lt = os.path.relpath(p, root), os.readlink(p)
        if ok.get(rel) == lt:
            continue
        v = posixpath.join(target, rel)
        r = posixpath.normpath(lt if lt.startswith("/") else posixpath.join(posixpath.dirname(v), lt))
        bad = not under(r, target) or any(under(r, s) for s in shared)
        # La copia ya en su sitio (de root): tambien como lo resuelve el sistema, con los enlaces de en medio
        if root == target and not under(os.path.realpath(p), os.path.realpath(target)):
            bad = True
        if bad:
            print("%s -> %s" % (rel, lt))
'
function check_build_links() {
    local bad
    bad=$(/usr/bin/python3 -I -c "$BUILD_LINKS_PY" "$stage$root" "$root" "$COMMON") || bad="(no se han podido mirar)"
    bad=$(cut -c1-300 <<< "$bad")
    if [ -n "$bad" ]; then
        echo "  Lo compilado tiene enlaces que llevan fuera de $root (no se copia nada):"
        echo "$bad" | head -10 | sed 's/^/    /'

        return 1
    fi
}

# brew_quiet <argumentos>: brew sin pistas, sin limpiar y sin actualizar lo que ya esta instalado
# (ni lo que se pide ni lo que depende de ello). brew no se puede ejecutar como root: si el
# instalador va con sudo, se usa el usuario de la sesion
function brew_quiet() {
    local env=(HOMEBREW_NO_INSTALL_UPGRADE=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1
        HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1)
    if [ "$(id -u)" -eq 0 ] && [ -n "$SUDO_USER" ]; then
        sudo -u "$SUDO_USER" env "${env[@]}" brew "$@"
    else
        env "${env[@]}" brew "$@"
    fi
}

# brew_filter: de lo que brew escribe en stderr, quita sus avisos (el de las herramientas de Xcode,
# que repite en cada formula; el de las versiones de macOS viejas; pistas; formulas nuevas o sin
# actualizar; lo que dice al actualizarse) y deja lo demas, siempre los errores
function brew_filter() {
    awk '
        /Error/ { skip = 0; print; fflush(); next }
        # (el de Xcode acaba en "You should download..."; los demas, en una linea en blanco)
        skip == 1 && /^You should download the Command Line Tools/ { skip = 0; next }
        skip == 2 && /^[[:space:]]*$/ { skip = 0; next }
        skip && /^(Warning|==>)/ { skip = 0 }
        skip { next }
        /^Warning: A newer Command Line Tools release is available/ { skip = 1; next }
        /^Warning: You are using macOS/ || /^==> (New|Outdated|Updated) (Formulae|Casks)/ { skip = 2; next }
        /HOMEBREW_NO_ENV_HINTS/ || /^You have [0-9]+ outdated (formula|formulae|cask|casks)/ { next }
        /^You can upgrade them with brew upgrade/ || /^or list them with brew outdated/ { next }
        /Cannot verify integrity/ || /^Running `brew update --auto-update`/ { next }
        /^==> Auto-updat/ || /^Auto-updated Homebrew/ || /^Updated [0-9]+ taps?/ || /^Updated Homebrew from/ { next }
        /^==> Homebrew was updated/ || /^==> Updated Homebrew/ || /^Already up-to-date/ { next }
        { print; fflush() }'
}

# Las librerias de Homebrew para compilar (STACK_BUILD_DEPS): solo instala las que faltan (con una
# sola consulta a brew; las que tienen otro nombre, como icu4c, una a una) y openssl@3 se pone al dia
# si brew dice que tiene una nueva. Si no falta nada, ni se llama a brew install (ni se actualiza
# Homebrew). En las versiones de macOS para las que Homebrew ya no tiene paquetes hechos, todo lo
# que se instala se compila
function brew_build_deps() {
    local have f missing=() upgrade=0
    have=$(brew_quiet list --formula -1 2> /dev/null)
    for f in $STACK_BUILD_DEPS; do
        grep -qxF -- "$f" <<< "$have" && continue
        brew_quiet list --versions "$f" > /dev/null 2>&1 || missing+=("$f")
    done
    [[ " ${missing[*]} " != *" openssl@3 "* ]] && [ -n "$(brew_quiet outdated --quiet openssl@3 2> /dev/null)" ] && upgrade=1
    if [ ${#missing[@]} -eq 0 ] && [ $upgrade -eq 0 ]; then
        echo "  Ya estan todas instaladas"
        return 0
    fi
    [ ${#missing[@]} -gt 0 ] && echo "  Se instalan con Homebrew: ${missing[*]}"
    [ $upgrade -eq 1 ] && echo "  Se actualiza openssl@3 (hay una version nueva)"
    echo "  En las versiones de macOS para las que Homebrew ya no tiene paquetes hechos, se compilan desde el codigo fuente: puede tardar un buen rato."
    if [ ${#missing[@]} -gt 0 ]; then
        { brew_quiet install --quiet "${missing[@]}" 2>&1 > /dev/null; } | brew_filter >&2
        [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "  No se han podido instalar con Homebrew: ${missing[*]}"; return 1; }
    fi
    if [ $upgrade -eq 1 ]; then
        { brew_quiet upgrade --quiet openssl@3 2>&1 > /dev/null; } | brew_filter >&2
        [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "  No se ha podido actualizar openssl@3 con Homebrew"; return 1; }
    fi
    return 0
}

# install_stack <version de PHP> [reemplazar]
# Compila Apache, PHP, Perl, ProFTPD y MariaDB y descarga phpMyAdmin, todo dentro de
# /Applications/XAMPP-X.Y/xamppfiles. Se instala primero en una carpeta temporal (DESTDIR) y solo
# al final se copia a /Applications, asi que si algo falla no queda nada a medias.
# Con reemplazar=1 sustituye la version que ya existe. Si su MariaDB es de la misma rama, conserva
# sus bases de datos; si no, empieza con unas vacias (con STACK_DB_COPY=1, el --copia de actualizar,
# antes guarda una copia en ~/nexum-backups).
function install_stack() {
    local version=$1 replace=${2:-0}
    local FETCH_FRESH=1

    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Indica la version completa de PHP, por ejemplo: 8.4.26"

        exit 1
    fi

    # Carpeta con la version completa (XAMPP-8.4.27). Actualizar (reemplazar=1) rehace en la suya una
    # XAMPP-X.Y de antes de la 1.38, que se llamaba como la rama; reemplazar=2 rehace XAMPP-<version>
    # con la misma version (7.4.33, 8.0.30 y 8.1.34, para ponerles el parche de seguridad)
    local short=${version%.*}
    local vname=$version
    [ "$replace" -eq 1 ] && vname=$short
    local root=$BASE_DIR/XAMPP-$vname
    local target=$root/xamppfiles
    local link_files=$LINK/xamppfiles docroot=$LINK/xamppfiles/htdocs
    # (el FTP entra como root en su htdocs, por su ruta real y no por el enlace /Applications/XAMPP)
    local ftp_root=$target/htdocs
    [ -n "$TEST_DIR" ] && link_files=$target && docroot=$target/htdocs

    if ! grep -q "^$short|" <<< "$(printf '%s\n' "${STACK_MATRIX[@]}")"; then
        echo "PHP $short no esta entre las ramas que instala este gestor"

        exit 1
    fi

    if [ "$replace" -eq 0 ] && [ -e "$root" ]; then
        echo "Ya existe $root"

        exit 1
    fi

    if [ "$replace" -ge 1 ] && [ ! -f "$target/etc/pvm-stack" ]; then
        echo "No existe $root, no hay nada que actualizar"

        exit 1
    fi

    if [ "$replace" -ge 1 ] && [ -e "$target/htdocs" ] && [ ! -L "$target/htdocs" ] && [ -z "$TEST_DIR" ]; then
        echo "$target tiene una carpeta htdocs propia (no es un enlace a $COMMON/htdocs) y podria contener proyectos."
        echo "Revisala y muevela a mano antes de actualizar la version."

        exit 1
    fi

    if ! xcode-select -p > /dev/null 2>&1; then
        echo "Faltan las herramientas de linea de comandos de Xcode. Instalalas con: xcode-select --install"

        exit 1
    fi

    echo "Consultando las ultimas versiones de cada componente..."
    local branches
    read -r -a branches <<< "$(stack_branches "$short")"

    local apache=$(latest_apache "${branches[0]}")
    local apr=$(latest_apr apr) aprutil=$(latest_apr apr-util)
    local mariadb_info=$(mariadb_release "${branches[1]}")
    local mariadb=${mariadb_info%%|*}
    local ftp=$(latest_proftpd "${branches[2]}")
    local perl=$(latest_perl "${branches[3]}")
    local pma=$(latest_pma "$short")
    local php_sha=$(curl -q --proto =https --proto-redir =https -fsSL "https://www.php.net/releases/index.php?json&version=$version" \
        | python3 -I -c 'import json,sys; print([s["sha256"] for s in json.load(sys.stdin)["source"] if s["filename"].endswith(".tar.xz")][0])' 2> /dev/null)

    # (lo que no responda, de la cache de descargas si esta)
    stack_cache_fallback fuente

    local missing=""
    [ -z "$php_sha" ] && missing+=" PHP-$version"
    [ -z "$apache" ] && missing+=" Apache-${branches[0]}"
    [ -z "$apr" ] || [ -z "$aprutil" ] && missing+=" APR"
    [ -z "$mariadb" ] && missing+=" MariaDB-${branches[1]}"
    [ -z "$ftp" ] && missing+=" ProFTPD-${branches[2]}"
    [ -z "$perl" ] && missing+=" Perl-${branches[3]}"

    if [ -n "$missing" ]; then
        echo "No se pudo consultar la ultima version de:$missing (¿hay conexion a internet?)"

        exit 1
    fi

    local web_user=$(web_user_name)
    local web_group=$(id -gn "$web_user")

    # Que hacer con las bases de datos de la version que se sustituye
    local keep_data=0 old_mariadb=""
    if [ "$replace" -ge 1 ]; then
        old_mariadb=$(stack_fields "$root" | cut -d'|' -f3)
        [ -d "$target/var/mysql" ] && [ ! -L "$target/var/mysql" ] \
            && [ "${old_mariadb%.*}" == "${mariadb%.*}" ] && keep_data=1
    fi

    local extras="" php_patch=""
    # 7.4.33, 8.0.30 y 8.1.34: con el parche de seguridad oficial contra PHP2Shell
    php2shell_backport "$version" > /dev/null && php_patch=$(php2shell_backport "$version" | cut -d'|' -f3)
    needs_openssl11 "$short" && extras+=", OpenSSL $OPENSSL11_VERSION"
    needs_icu72 "$short" && extras+=", ICU 72.1"

    echo ""
    local php_shown="PHP $version"
    [ -n "$php_patch" ] && php_shown+=" + parche de seguridad ($PHP2SHELL_DATE)"
    local stack_line="XAMPP-$vname: $php_shown, Apache $apache, MariaDB $mariadb, ProFTPD $ftp, Perl $perl, phpMyAdmin $pma$extras"
    echo "$stack_line"
    echo "Carpeta: $root   Usuario de Apache, PHP, MariaDB y FTP: $web_user:$web_group"

    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] librerias de Homebrew: $STACK_BUILD_DEPS"
        echo "  [simulacion] descarga con comprobacion sha256 y compilacion de Apache, APR $apr/$aprutil, PHP, Perl, ProFTPD y MariaDB$extras"
        echo "  [simulacion] copia de las librerias de Homebrew dentro de $target/lib"
        if [ "$replace" -ge 1 ] && [ $keep_data -eq 1 ]; then
            echo "  [simulacion] se sustituiria $root conservando sus bases de datos (MariaDB ${mariadb%.*})"
        elif [ "$replace" -ge 1 ]; then
            [ "${STACK_DB_COPY:-0}" -eq 1 ] && echo "  [simulacion] copia de las bases de datos de $root en ~/nexum-backups y bases nuevas y vacias"
            [ "${STACK_DB_COPY:-0}" -eq 1 ] || echo "  [simulacion] sin copia: bases nuevas y vacias en $root (las anteriores no se podran recuperar)"
        else
            echo "  [simulacion] bases de datos propias y vacias en $target/var/mysql (root sin contraseña)"
        fi
        echo "  [simulacion] puertos: web $PORT_HTTP/$PORT_HTTPS, MariaDB $PORT_MYSQL, FTP $PORT_FTP"

        exit 0
    fi

    echo "Instalando las librerias de Homebrew para compilar (solo librerias, no PHP)..."
    brew_build_deps || exit 1

    STEP_LOG="" STEP_DESC=""
    local build=$(mktemp -d /tmp/lvm-pila-$short-XXXX)
    local stage=$build/stage
    local S=$stage$target
    local deps=$build/deps
    local jobs=$(cpu_count)
    local sdk=$(xcrun --show-sdk-path)

    # Si algo falla se guardan los logs y se borra la carpeta temporal
    function stack_fail() {
        local logs=$LOG_DIR/pila-$short-$(date +%Y%m%d-%H%M%S)
        mkdir -p "$logs"
        cp "$build"/*.log "$logs/" 2> /dev/null
        # El config.log del componente que fallaba (stack_fail se llama desde su carpeta): ahi esta
        # el motivo real de los errores de configure ("GD build test failed...")
        local config=""
        if [ -f config.log ]; then
            config="$logs/$(basename "$PWD")-config.log"
            cp config.log "$config"
        fi
        # (lo ya descargado y comprobado, a la cache: al reintentar no se descarga otra vez)
        stack_cache_store -n
        cd / && rm -rf "$build"
        error_report "$logs/informe-error.txt" "$stack_line" "${STEP_LOG:+$logs/$(basename "$STEP_LOG")}" "$STEP_DESC" "$config"
        echo "No se ha instalado nada. Logs de la compilacion en $logs"
        echo "Informe del error: $logs/informe-error.txt"

        exit 1
    }

    cd "$build" || exit 1

    # Rutas de Homebrew. Las librerias "keg-only" no estan en /opt/homebrew/lib y hay que indicarlas.
    local b_ssl=$(brew --prefix openssl@3) b_icu=$(brew --prefix icu4c) b_pcre=$(brew --prefix pcre2)
    local pc="" f
    for f in zlib sqlite readline; do pc+="$(brew --prefix $f)/lib/pkgconfig:"; done
    pc+="$HOMEBREW_PREFIX/lib/pkgconfig"
    local headerpad="-Wl,-headerpad_max_install_names"

    local php_part=$php_shown
    [ -n "$extras" ] && php_part+=" (con ${extras#, })"
    local parts=("Descargas" "Apache $apache" "$php_part" "Perl $perl" "ProFTPD $ftp" "MariaDB $mariadb" \
        "phpMyAdmin $pma y configuracion")
    progress_parts "${parts[@]}"

    echo "Descargando el codigo fuente (con comprobacion sha256 y de las firmas GPG)..."
    progress 1 0 1 "codigo fuente"
    download_apache "httpd/httpd-$apache.tar.bz2" httpd.tar.bz2 || stack_fail
    download_apache "apr/apr-$apr.tar.bz2" apr.tar.bz2 || stack_fail
    download_apache "apr/apr-util-$aprutil.tar.bz2" apr-util.tar.bz2 || stack_fail
    download "https://www.php.net/distributions/php-$version.tar.xz" php.tar.xz "$php_sha" \
        "https://www.php.net/distributions/php-$version.tar.xz.asc" PHP || stack_fail
    download "https://www.cpan.org/src/5.0/perl-$perl.tar.xz" perl.tar.xz \
        "$(curl -q --proto =https --proto-redir =https -fsSL --retry 2 --max-time 60 "https://www.cpan.org/src/5.0/perl-$perl.tar.xz.sha256.txt" | grep -oE '^[0-9a-f]{64}')" || stack_fail
    download "https://github.com/proftpd/proftpd/archive/refs/tags/v$ftp.tar.gz" proftpd.tar.gz \
        "$(proftpd_sum "$ftp")" "" "" "proftpd-$ftp.tar.gz" || stack_fail
    download "https://files.phpmyadmin.net/phpMyAdmin/$pma/phpMyAdmin-$pma-all-languages.tar.xz" pma.tar.xz \
        "$(pma_sum "$pma")" "https://files.phpmyadmin.net/phpMyAdmin/$pma/phpMyAdmin-$pma-all-languages.tar.xz.asc" PMA || stack_fail
    if needs_openssl11 "$short"; then
        download "https://www.openssl.org/source/openssl-$OPENSSL11_VERSION.tar.gz" openssl11.tar.gz "$OPENSSL11_SHA" || stack_fail
    fi
    if needs_icu72 "$short"; then
        download "https://github.com/unicode-org/icu/releases/download/release-72-1/icu4c-72_1-src.tgz" icu72.tgz "$ICU72_SHA" || stack_fail
    fi
    IFS='|' read -r _ mariadb_url mariadb_sha <<< "$mariadb_info"
    progress 1 1 4 "MariaDB (codigo fuente)" bytes "$build/mariadb.tar.gz" "$(remote_size "$mariadb_url")"
    # (la firma, en la misma direccion de su API: .../mariadb-X.Y.Z.tar.gz/signature/)
    download "$mariadb_url" mariadb.tar.gz "$mariadb_sha" "${mariadb_url%/}/signature/" MARIADB \
        "mariadb-$mariadb-fuente.tar.gz" || stack_fail

    echo "Apache $apache (con APR $apr y APR-util $aprutil)"
    tar -xjf httpd.tar.bz2 && tar -xjf apr.tar.bz2 && tar -xjf apr-util.tar.bz2 || stack_fail
    mv "apr-$apr" "httpd-$apache/srclib/apr" && mv "apr-util-$aprutil" "httpd-$apache/srclib/apr-util" || stack_fail
    cd "httpd-$apache" || stack_fail
    step 2 4 6 1063 "Configurando" "$build/apache-configure.log" env LDFLAGS="$headerpad" ./configure \
        --prefix="$target/apache2" --with-included-apr --with-pcre="$b_pcre/bin/pcre2-config" \
        --with-ssl="$b_ssl" --with-nghttp2="$(brew --prefix nghttp2)" --with-brotli="$(brew --prefix brotli)" \
        --enable-mods-shared=most --enable-ssl --enable-http2 --enable-brotli --enable-proxy --enable-proxy-fcgi \
        --enable-mpms-shared="event prefork" || stack_fail
    step 2 6 9 712 "Compilando" "$build/apache-make.log" make -j"$jobs" || stack_fail
    step 2 9 10 583 "Instalando" "$build/apache-install.log" make install DESTDIR="$stage" || stack_fail
    cd "$build" || stack_fail

    echo "PHP $version"
    # Las ramas antiguas compilan con avisos que los compiladores actuales tratan como errores
    local php_cflags="-O2" php_cxxflags="-O2" php_cppflags="" php_pc=$pc
    local php_ssl_pc="$b_ssl/lib/pkgconfig" php_icu_pc="$b_icu/lib/pkgconfig" p=10
    # PHP 7.4 usa TRUE/FALSE, que ICU dejo de definir en la version 68
    [ "$short" == "7.4" ] && php_cppflags="-DU_DEFINE_FALSE_AND_TRUE=1"
    # El configure de PHP compila con -fvisibility=hidden, y con el enlazador actual de Apple un
    # programa con main oculto no tiene punto de entrada ("dyld: main executable has no entry
    # point"). PHP 7.4 es la unica rama que ejecuta un programa de prueba (el de GD: "GD build test
    # failed"); -fvisibility=default, que va despues en la linea del compilador, lo anula
    [ "$short" == "7.4" ] && php_cppflags+=" -fvisibility=default"
    if needs_icu72 "$short"; then
        php_cflags+=" -Wno-error=implicit-function-declaration -Wno-error=incompatible-function-pointer-types"
        php_cflags+=" -Wno-error=int-conversion -Wno-error=incompatible-pointer-types -Wno-error=implicit-int"
    else
        php_cxxflags+=" -std=c++17"
    fi
    if needs_openssl11 "$short"; then
        build_openssl11 "$deps" $p || stack_fail
        php_ssl_pc="$deps/lib/pkgconfig"
        p=$((p + 5))
    fi
    if needs_icu72 "$short"; then
        build_icu72 "$deps" $p || stack_fail
        php_icu_pc="$deps/lib/pkgconfig"
        p=$((p + 5))
    fi
    php_pc="$php_ssl_pc:$php_icu_pc:$pc"
    # 7.4 y 8.0 traen PCRE2 10.35, cuyo JIT no reserva memoria con MAP_JIT y falla en Apple Silicon
    # ("Allocation of JIT memory failed"): usan el pcre2 de Homebrew, que bundle_libs copia dentro
    local php_extra=()
    needs_openssl11 "$short" && php_extra+=(--with-external-pcre)

    # PHP 7.4 y 8.0 buscan argon2.h solo en la ruta indicada, /usr y /usr/local (no en /opt/homebrew);
    # desde la 8.1 se busca con pkg-config y la ruta se ignora
    tar -xJf php.tar.xz && cd "php-$version" || stack_fail
    if [ -n "$php_patch" ]; then
        echo "  Parche de seguridad contra PHP2Shell (CVE-2026-109618 y CVE-2026-109619, php-src ${php_patch:0:12})"
        php2shell_diff "$version" "$build/php2shell.diff" || stack_fail
        # (primero en seco: si no encaja entero, no se toca nada)
        /usr/bin/patch -p1 -s -f --dry-run < "$build/php2shell.diff" > "$build/php-parche.log" 2>&1 \
            && /usr/bin/patch -p1 -s -f < "$build/php2shell.diff" >> "$build/php-parche.log" 2>&1 \
            || { echo "  El parche de seguridad no se aplica a PHP $version (mira php-parche.log)"; stack_fail; }
    fi
    step 3 $p $((p + 3)) 701 "Configurando" "$build/php-configure.log" env PKG_CONFIG_PATH="$php_pc" \
        CFLAGS="$php_cflags" CXXFLAGS="$php_cxxflags" CPPFLAGS="$php_cppflags" LDFLAGS="$headerpad" \
        LIBXML_CFLAGS="-I$sdk/usr/include/libxml2" LIBXML_LIBS="-lxml2" \
        CURL_CFLAGS="-I$sdk/usr/include" CURL_LIBS="-lcurl" \
        ./configure --prefix="$target/php" \
        --with-config-file-path="$target/php/etc" \
        --with-config-file-scan-dir="$target/php/etc/conf.d" \
        --enable-fpm --with-fpm-user="$web_user" --with-fpm-group="$web_group" --disable-cgi \
        --with-openssl --with-zlib --with-curl --with-readline="$(brew --prefix readline)" \
        --with-gettext="$(brew --prefix gettext)" --with-iconv="$(brew --prefix libiconv)" \
        --enable-mbstring --enable-intl --enable-bcmath --enable-calendar --enable-exif --enable-ftp \
        --enable-gd --with-jpeg --with-freetype --with-webp \
        --with-zip --enable-soap --enable-sockets --with-sodium --with-password-argon2="$(brew --prefix argon2)" \
        --enable-mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
        --with-mysql-sock="$target/var/mysql/mysql.sock" \
        --with-sqlite3 --with-pdo-sqlite "${php_extra[@]}" || stack_fail
    step 3 $((p + 3)) 37 913 "Compilando (tarda unos minutos)" "$build/php-make.log" make -j"$jobs" || stack_fail
    step 3 37 38 17 "Instalando" "$build/php-install.log" make install INSTALL_ROOT="$stage" || stack_fail
    mkdir -p "$S/php/etc" && cp php.ini-production "$S/php/etc/php.ini" || stack_fail
    cd "$build" || stack_fail

    echo "Perl $perl"
    tar -xJf perl.tar.xz && cd "perl-$perl" || stack_fail
    step 4 38 41 948 "Configurando" "$build/perl-configure.log" sh Configure -des -Dprefix="$target/perl" \
        -Dman1dir=none -Dman3dir=none || stack_fail
    step 4 41 46 1798 "Compilando" "$build/perl-make.log" make -j"$jobs" || stack_fail
    step 4 46 48 3319 "Instalando" "$build/perl-install.log" make install DESTDIR="$stage" || stack_fail
    cd "$build" || stack_fail

    echo "ProFTPD $ftp"
    tar -xzf proftpd.tar.gz && cd "proftpd-$ftp" || stack_fail
    step 5 48 49 575 "Configurando" "$build/proftpd-configure.log" env install_user="$(id -un)" install_group="$(id -gn)" \
        LDFLAGS="$headerpad" ./configure --prefix="$target/proftpd" --sysconfdir="$target/etc" \
        --localstatedir="$target/var/proftpd" --enable-auth-pam || stack_fail
    # ProFTPD falla a veces al compilar en paralelo (Homebrew tambien lo compila sin -j)
    step 5 49 50 162 "Compilando" "$build/proftpd-make.log" make || stack_fail
    step 5 50 51 50 "Instalando" "$build/proftpd-install.log" make install DESTDIR="$stage" || stack_fail
    cd "$build" || stack_fail

    echo "MariaDB $mariadb (compilar MariaDB es lo que mas tarda)"
    # (mariadb.tar.gz se queda hasta el final: se guarda en la cache de descargas)
    tar -xzf mariadb.tar.gz && cd "mariadb-$mariadb" || stack_fail
    step 6 51 53 0 "Configurando" "$build/mariadb-configure.log" cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$target/mysql" -DCMAKE_PREFIX_PATH="$HOMEBREW_PREFIX" \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_FIND_FRAMEWORK=LAST -DCMAKE_EXE_LINKER_FLAGS="$headerpad" -DCMAKE_SHARED_LINKER_FLAGS="$headerpad" \
        -DCMAKE_MODULE_LINKER_FLAGS="$headerpad" -DCMAKE_INSTALL_RPATH="$target/mysql/lib" \
        -DCMAKE_INSTALL_NAME_DIR="$target/mysql/lib" -DWITH_SSL="$b_ssl" -DWITH_PCRE=system -DWITH_LIBFMT=system \
        -DLIBFMT_INCLUDE_DIR="$(brew --prefix fmt)/include" \
        -DBISON_EXECUTABLE="$(brew --prefix bison)/bin/bison" -DWITH_UNIT_TESTS=OFF -DWITH_WSREP=OFF \
        -DWITH_EMBEDDED_SERVER=OFF -DINSTALL_MYSQLTESTDIR= -DINSTALL_SQLBENCHDIR= \
        -DPLUGIN_TOKUDB=NO -DPLUGIN_MROONGA=NO -DPLUGIN_SPIDER=NO -DPLUGIN_OQGRAPH=NO -DPLUGIN_ROCKSDB=NO \
        -DPLUGIN_CONNECT=NO -DPLUGIN_COLUMNSTORE=NO -DPLUGIN_S3=NO -DPLUGIN_AUTH_GSSAPI=NO \
        -DPLUGIN_AUTH_PAM=NO -DPLUGIN_AUTH_PAM_V1=NO \
        -DDEFAULT_CHARSET=utf8mb4 -DDEFAULT_COLLATION=utf8mb4_general_ci -DCOMPILATION_COMMENT="lvm-instalador" \
        || stack_fail
    strip_sdk_includes build >> "$build/mariadb-configure.log"
    step 6 53 94 0 "Compilando (tarda bastante)" "$build/mariadb-make.log" cmake --build build --parallel "$jobs" || stack_fail
    step 6 94 96 0 "Instalando" "$build/mariadb-install.log" env DESTDIR="$stage" cmake --install build || stack_fail
    # Sin el ayudante de PAM (aqui no se usa PAM): si llegara a la version, mariadb-install-db le daria
    # su carpeta al usuario del servidor (tu usuario) con un programa setuid de root dentro, hasta que
    # se borrara. Se quita antes de copiar nada como root (mariadb-install-db no tiene una opcion para
    # no hacerlo: solo lo hace si la carpeta existe)
    rm -rf "$S/mysql/lib/plugin/auth_pam_tool_dir" || stack_fail
    cd "$build" && rm -rf "mariadb-$mariadb" || stack_fail

    echo "phpMyAdmin $pma"
    progress 7 96 97 "configurando"
    tar -xJf pma.tar.xz && mv "phpMyAdmin-$pma-all-languages" "$S/phpmyadmin" || stack_fail

    echo "Configuracion"
    write_stack_files || stack_fail

    echo "Copiando dentro de la version las librerias de Homebrew que usa..."
    bundle_libs "$S" "$target" || stack_fail
    check_build_links || stack_fail

    # Copia a /Applications. Si se rehace una version, la anterior se aparta hasta que todo este copiado.
    local aside="" was_running=0 links
    if [ "$replace" -ge 1 ]; then
        # Si es la version activa, se para mientras tanto y se arranca la nueva al terminar
        if [ -n "$TEST_DIR" ]; then
            "$target/xampp" status 2> /dev/null | grep -q " esta arrancado" && was_running=1
            "$target/xampp" stop > /dev/null 2>&1
        elif [ "$(active_dir)" == "$root" ]; then
            lampp_running && was_running=1
            # Su script xampp lo ejecuta root solo si la version es de root (si no, podria ser de otro
            # programa): entonces se cierran sus procesos sin ejecutar nada de ella
            if trusted_version_dir "$root"; then
                sudo "$target/xampp" stop
            else
                close_processes --todos
            fi
        fi

        if [ $keep_data -eq 0 ] && [ -d "$target/var/mysql" ] && [ ! -L "$target/var/mysql" ]; then
            if [ "${STACK_DB_COPY:-0}" -eq 1 ]; then
                progress 7 97 98 "copia de las bases de datos"
                backup_databases "$vname" "$root" || { echo "No se pudo guardar la copia de las bases de datos."; stack_fail; }
            else
                echo "Sin copia: las bases de datos de ahora no se podran recuperar (con --copia se guardan antes)"
            fi
        fi

        aside=$root.anterior-$(date +%Y%m%d%H%M%S)
        echo "Apartando la version anterior en $aside..."
        $SUDO mv "$root" "$aside" || stack_fail
    fi

    echo "Copiando a $root..."
    progress 7 98 99 "copiando a $root"
    # Lo compilado es de tu usuario: como root se copia sin -p (cada fichero nace de root, sin setuid
    # ni el dueño de antes) y sin escritura para otros
    # (los enlaces se vuelven a mirar en la copia, que ya es de root: entre la primera comprobacion y
    # la copia se podria haber puesto otro)
    # (mkdir sin -p: si ya hubiera una carpeta con ese nombre, puesta por otro programa mientras se
    # compilaba, falla y no se copia dentro)
    # (y, ya de root, root mira que sus programas solo carguen librerias suyas o del sistema: una de
    # /opt/homebrew, que es de tu usuario, la cargaria Apache como root. MACHO_AUDIT_PY)
    local audit=""
    if ! { $SUDO mkdir "$root" && $SUDO cp -R "$stage$root/." "$root/" && $SUDO chmod -R go-w,ug-s "$root" \
            && links=$($SUDO /usr/bin/python3 -I -c "$BUILD_LINKS_PY" "$root" "$root" "$COMMON") && [ -z "$links" ] \
            && { [ -n "$TEST_DIR" ] || audit=$($SUDO /usr/bin/python3 -I -c "$MACHO_AUDIT_PY" "$root"); }; }; then
        [ -n "$audit" ] && { echo "  Lo compilado carga librerias de fuera de la version (no se instala):"; head -5 <<< "$audit" | sed 's/^/    /'; }
        $SUDO rm -rf "$root"
        [ -n "$aside" ] && $SUDO mv "$aside" "$root" && echo "Se ha dejado la version anterior como estaba."
        stack_fail
    fi

    if [ -z "$TEST_DIR" ]; then
        sudo chown -R root:admin "$root"
        # Tu usuario esta en el grupo admin: sin escritura de grupo (ni de otros) en lo que lee
        # Apache al arrancar como root, por si la umask la dejo (menos las bases de datos y tmp)
        sudo find "$root" \( -path "$target/var" -o -path "$target/tmp" -o -path "$target/phpmyadmin/tmp" \) -prune -o \
            ! -type l \( -perm -020 -o -perm -002 \) -exec chmod go-w {} +
        # Las dos carpetas que se abren a otros las crea root vacias: las copiadas venian de tu
        # carpeta, y si fueran un enlace root cambiaria el dueño y los permisos de lo que apuntan
        sudo rm -rf "$target/phpmyadmin/tmp" "$target/tmp"
        sudo install -d -o 0 -g "$web_group" -m 775 "$target/phpmyadmin/tmp"
        sudo install -d -o 0 -g 0 -m 1777 "$target/tmp"

        # htdocs y vhosts compartidos: se crean si es la primera version del Mac (XAMPP-compartido, de
        # root: Apache lee como root sus vhosts, certificados y claves de Docker)
        if [ ! -d "$COMMON/htdocs" ]; then
            [ -d "$COMMON" ] || sudo install -d -o root -g wheel -m 755 "$COMMON"
            sudo mkdir -p "$COMMON/htdocs"
            sudo chown "$web_user:$web_group" "$COMMON/htdocs"
        fi
        if [ ! -f "$COMMON/httpd-vhosts.conf" ]; then
            echo "# Virtual hosts compartidos por todas las versiones de PHP" | sudo tee "$COMMON/httpd-vhosts.conf" > /dev/null
        fi
    fi

    if [ $keep_data -eq 1 ]; then
        echo "Conservando las bases de datos (MariaDB ${old_mariadb} -> $mariadb)..."
        $SUDO mv "$aside/xamppfiles/var/mysql" "$target/var/mysql" || stack_fail
    else
        progress 7 99 100 "creando las bases de datos"
        init_stack_databases "$target" "$web_user" || stack_fail
    fi

    # Apache lee al comprobar (y al arrancar) los vhosts compartidos y carga sus modulos: como root,
    # solo si la version y los vhosts son de root (vhosts_root los deja asi si pasan la comprobacion)
    local trusted=1
    if [ -z "$TEST_DIR" ]; then
        vhosts_root
        trusted_version_dir "$root" || trusted=0
    fi
    if [ $trusted -eq 1 ]; then
        echo "Comprobando la configuracion..."
        $SUDO "$target/apache2/bin/httpd" -t -f "$target/etc/httpd.conf" 2>&1 | sed 's/^/  Apache: /'
        $SUDO "$target/php/sbin/php-fpm" -t --fpm-config "$target/php/etc/php-fpm.conf" 2>&1 | sed 's/^.*NOTICE: /  PHP-FPM: /'
        $SUDO "$target/proftpd/sbin/proftpd" -t -c "$target/etc/proftpd.conf" 2>&1 | grep -iv '^checking' | sed 's/^/  ProFTPD: /'
    else
        echo "No se comprueba la configuracion como administrador: la version o los vhosts compartidos no"
        echo "son de root o el grupo puede cambiarlos. Dejalo bien con: lvm-instalador asegurar --todas"
    fi

    [ -n "$aside" ] && $SUDO rm -R "$aside"
    stack_cache_store
    # (fuera de la carpeta antes de borrarla: si no, lo que se ejecuta despues avisa de que no
    # encuentra la carpeta actual, getcwd)
    cd / && rm -rf "$build"

    if [ $was_running -eq 1 ]; then
        if [ $trusted -eq 1 ]; then
            $SUDO "$target/xampp" start
        else
            echo "No se arranca: primero lvm-instalador asegurar --todas"
        fi
    fi

    echo ""
    echo "XAMPP-$vname instalada en $root"
    [ "$replace" -ge 1 ] && [ $keep_data -eq 0 ] && echo "Empieza con bases de datos vacias$([ "${STACK_DB_COPY:-0}" -eq 1 ] && echo "; la copia de las anteriores esta en ~/nexum-backups")"
    [ "$replace" -ge 1 ] && [ $keep_data -eq 1 ] && echo "Conserva sus bases de datos"
    [ $was_running -eq 0 ] && echo "Para usarla: lvm-instalador use $vname"

    return 0
}

