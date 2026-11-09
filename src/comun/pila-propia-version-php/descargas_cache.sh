# Cache de descargas de las pilas propias (DL_CACHE_DIR, de root): el codigo de cada componente ya
# comprobado (su sha256 y, si la tiene, su firma), con su suma al lado (<nombre>.sha256). Al instalar:
# - si un fichero esta y su suma es la que publica su web, no se vuelve a descargar;
# - si su web no da la suma (no responde), se usa el de la cache, que se comprobo al guardarlo;
# - si no se puede consultar el ultimo parche de un componente, se usa el mas nuevo de su rama que
#   haya en la cache (stack_cache_fallback), con un aviso.
# Lo guarda root al terminar (bien o mal: un reintento ya no lo descarga otra vez). De cada componente
# y rama se queda solo el ultimo que se ha usado. Nada de lo tuyo (tu usuario) puede cambiarla.

# dl_sha256 <archivo>: su suma sha256
function dl_sha256() {
    if command -v sha256sum > /dev/null; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# dl_cache_trusted: ¿la cache y la carpeta que la contiene son de root y solo root escribe en ellas?
# (si no, no se usa: en las pruebas, la de TEST_DIR)
function dl_cache_trusted() {
    [ -n "$TEST_DIR" ] && return 0
    [ -d "$DL_CACHE_DIR" ] && [ ! -L "$DL_CACHE_DIR" ] || return 1
    [ $(( $(find "$DL_CACHE_DIR" "${DL_CACHE_DIR%/*}" -maxdepth 0 -user 0 ! -perm -020 ! -perm -002 2> /dev/null | wc -l) )) -eq 2 ]
}

# dl_cache_sum <nombre>: la suma con la que se guardo <nombre> en la cache (nada si no esta)
function dl_cache_sum() {
    local f=$DL_CACHE_DIR/$1
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] && dl_cache_trusted || return 0
    [ -f "$f" ] && [ ! -L "$f" ] && [ -f "$f.sha256" ] && [ ! -L "$f.sha256" ] || return 0
    grep -m 1 -oE '^[0-9a-f]{64}' "$f.sha256"
}

# dl_from_cache <nombre> <archivo> <sha256 o "">: copia <nombre> de la cache a <archivo> si su suma es
# esa (o, sin suma, la guardada) y lo comprueba otra vez. Deja la suma en DL_SUM. 1 si no esta
function dl_from_cache() {
    local name=$1 file=$2 sum=$3 saved
    saved=$(dl_cache_sum "$name")
    [ -n "$saved" ] || return 1
    [ -z "$sum" ] && sum=$saved
    [ "$saved" == "$sum" ] || return 1
    cp "$DL_CACHE_DIR/$name" "$file" 2> /dev/null || return 1
    if [ "$(dl_sha256 "$file")" != "$sum" ]; then
        rm -f "$file"
        return 1
    fi
    DL_SUM=$sum
}

# dl_note <archivo> <nombre> <sha256>: apunta una descarga ya comprobada, para guardarla en la cache
function dl_note() {
    printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$build/descargas.lista"
}

# dl_cache_latest <antes> <despues> <expresion de la version>: la version mas nueva de la cache entre
# los <antes><version><despues> (httpd- .tar.bz2 '2\.4\.[0-9]+' -> 2.4.62)
function dl_cache_latest() {
    local f n v found=()
    dl_cache_trusted || return 0
    for f in "$DL_CACHE_DIR/$1"*"$2"; do
        n=${f##*/} v=${n#"$1"} v=${v%"$2"}
        [[ "$v" =~ ^($3)$ ]] && [ -n "$(dl_cache_sum "$n")" ] && found+=("$v")
    done
    [ ${#found[@]} -eq 0 ] || printf '%s\n' "${found[@]}" | sort -V | tail -1
}

# Una rama (2.4) como expresion (2\.4)
function dl_re() {
    sed 's/\./\\./g' <<< "$1"
}

# stack_cache_fallback <binario|fuente>: lo que install_stack no ha podido consultar (su web no
# responde) sale de la cache, si esta: el ultimo parche de cada componente que haya ahi de su rama y
# la suma de PHP. Cambia las variables de install_stack (php_sha, apache, apr, aprutil, mariadb,
# mariadb_info, ftp, perl; branches son sus ramas)
function stack_cache_fallback() {
    local kind=$1 v
    if [ -z "$php_sha" ]; then
        php_sha=$(dl_cache_sum "php-$version.tar.xz")
        [ -n "$php_sha" ] && echo "Aviso: php.net no responde: PHP $version sale de la cache de descargas (ya comprobado)"
    fi
    if [ -z "$apache" ]; then
        apache=$(dl_cache_latest httpd- .tar.bz2 "$(dl_re "${branches[0]}")\.[0-9]+")
        [ -n "$apache" ] && dl_fallback_note "Apache ${branches[0]}" "$apache"
    fi
    if [ -z "$apr" ]; then
        apr=$(dl_cache_latest apr- .tar.bz2 '1\.[0-9]+\.[0-9]+')
        [ -n "$apr" ] && dl_fallback_note "APR" "$apr"
    fi
    if [ -z "$aprutil" ]; then
        aprutil=$(dl_cache_latest apr-util- .tar.bz2 '1\.[0-9]+\.[0-9]+')
        [ -n "$aprutil" ] && dl_fallback_note "APR-util" "$aprutil"
    fi
    if [ -z "$mariadb" ]; then
        v=$(dl_cache_latest mariadb- "-$kind.tar.gz" "$(dl_re "${branches[1]}")\.[0-9]+")
        if [ -n "$v" ]; then
            mariadb=$v mariadb_info="$v||$(dl_cache_sum "mariadb-$v-$kind.tar.gz")|"
            dl_fallback_note "MariaDB ${branches[1]}" "$v"
        fi
    fi
    if [ -z "$ftp" ]; then
        ftp=$(dl_cache_latest proftpd- .tar.gz "$(dl_re "${branches[2]}")[a-z]?")
        [ -n "$ftp" ] && dl_fallback_note "ProFTPD ${branches[2]}" "$ftp"
    fi
    if [ -z "$perl" ]; then
        perl=$(dl_cache_latest perl- .tar.xz "$(dl_re "${branches[3]}")\.[0-9]+")
        [ -n "$perl" ] && dl_fallback_note "Perl ${branches[3]}" "$perl"
    fi
    return 0
}

function dl_fallback_note() {
    echo "Aviso: no se ha podido consultar el ultimo parche de $1 (su web no responde): se usa $2, el mas"
    echo "  nuevo de la cache de descargas (ya comprobado; si hay uno mas nuevo, actualiza despues)"
}

# Guarda en la cache, como root, lo apuntado en <compilacion>/descargas.lista: cada fichero se copia
# sin seguir enlaces y se comprueba otra vez su suma al copiarlo. Despues, de cada componente y rama
# (php-8.4, httpd-2.4, mariadb-11.4-binario...) solo se deja el ultimo que se ha usado.
# Uso: <compilacion> <cache>. Escribe G|<nombre> por cada uno guardado y B|<nombre> por cada uno borrado
DL_CACHE_PY='
import hashlib, os, re, stat, sys
build, cache = sys.argv[1:3]
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
SUM = re.compile(r"^[0-9a-f]{64}$")
# (php-8.4.27.tar.xz -> php-8.4.tar.xz; proftpd-1.3.9a.tar.gz -> proftpd-1.3.tar.gz)
FAMILY = re.compile(r"^(.*?[0-9]+\.[0-9]+)\.[0-9]+[a-z]?(\D.*)$")
me = os.getuid()

def private_dir(p):
    st = os.lstat(p)
    return stat.S_ISDIR(st.st_mode) and st.st_uid == me and not st.st_mode & 0o022

def unlink(p):
    try:
        os.unlink(p)
    except OSError:
        pass

def sha256_of(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def write_sum(dst, s, name):
    tmp = dst + ".sha256.tmp"
    unlink(tmp)
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
    with os.fdopen(fd, "w") as f:
        f.write("%s  %s\n" % (s, name))
    os.rename(tmp, dst + ".sha256")

try:
    if not os.path.lexists(cache):
        os.makedirs(cache, 0o755)
    if not private_dir(cache) or not private_dir(os.path.dirname(cache)):
        sys.exit("La cache de descargas %s no es solo de root: no se usa" % cache)
    os.chmod(cache, 0o755)
except OSError as e:
    sys.exit("No se puede usar la cache de descargas: %s" % e)

try:
    with open(os.path.join(build, "descargas.lista")) as f:
        lines = f.read().splitlines()
except OSError:
    lines = []

for line in lines:
    parts = line.split("|")
    if len(parts) != 3:
        continue
    rel, name, s = parts
    if not NAME.match(rel) or not NAME.match(name) or name.endswith((".sha256", ".tmp")) or not SUM.match(s):
        continue
    dst = os.path.join(cache, name)
    # (si ya esta, y bien, solo se marca como usado)
    try:
        with open(dst + ".sha256") as f:
            if f.read().split()[:1] == [s] and stat.S_ISREG(os.lstat(dst).st_mode) and sha256_of(dst) == s:
                os.utime(dst)
                os.utime(dst + ".sha256")
                continue
    except OSError:
        pass
    tmp = dst + ".tmp"
    unlink(tmp)
    try:
        src = os.open(os.path.join(build, rel), os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        continue
    h = hashlib.sha256()
    try:
        with os.fdopen(src, "rb") as fin:
            if not stat.S_ISREG(os.fstat(fin.fileno()).st_mode):
                continue
            out = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o644)
            with os.fdopen(out, "wb") as fout:
                for chunk in iter(lambda: fin.read(1 << 20), b""):
                    h.update(chunk)
                    fout.write(chunk)
        if h.hexdigest() != s:
            unlink(tmp)
            continue
        os.rename(tmp, dst)
        write_sum(dst, s, name)
        print("G|" + name)
    except OSError:
        unlink(tmp)

# De cada familia, el ultimo usado; y nada a medias
files = {}
for n in os.listdir(cache):
    p = os.path.join(cache, n)
    if n.endswith(".tmp"):
        unlink(p)
        continue
    if n.endswith(".sha256") or not stat.S_ISREG(os.lstat(p).st_mode):
        continue
    m = FAMILY.match(n)
    files.setdefault(m.group(1) + m.group(2) if m else n, []).append((os.lstat(p).st_mtime, n))
for group in files.values():
    group.sort(reverse=True)
    for _, n in group[1:]:
        unlink(os.path.join(cache, n))
        unlink(os.path.join(cache, n + ".sha256"))
        print("B|" + n)
for n in os.listdir(cache):
    if n.endswith(".sha256") and not os.path.exists(os.path.join(cache, n[:-7])):
        unlink(os.path.join(cache, n))
'

# stack_cache_store [-n]: guarda en la cache lo que ha descargado esta instalacion (en $build). Con -n,
# sin pedir la contraseña (al fallar: si ya no vale la de antes, no se guarda y ya esta)
function stack_cache_store() {
    local sudo=$SUDO out n
    [ -n "$sudo" ] && [ "$1" == "-n" ] && sudo="sudo -n"
    [ -s "$build/descargas.lista" ] || return 0
    out=$($sudo /usr/bin/python3 -I -c "$DL_CACHE_PY" "$build" "$DL_CACHE_DIR" 2>&1 < /dev/null) || {
        [ -n "$out" ] && echo "  $out"
        return 0
    }
    n=$(grep -c '^G|' <<< "$out")
    [ "$n" -gt 0 ] && echo "Guardado en la cache de descargas ($DL_CACHE_DIR): $n fichero(s)"
    return 0
}

# lvm-instalador descargas [vaciar]: lo que hay en la cache de descargas y cuanto ocupa, o vaciarla
function downloads_command() {
    local f total=0 n=0 size
    case "${1:-}" in
        ""|lista)
            if [ ! -d "$DL_CACHE_DIR" ] || ! dl_cache_trusted; then
                echo "La cache de descargas ($DL_CACHE_DIR) esta vacia"
                return 0
            fi
            for f in "$DL_CACHE_DIR"/*; do
                [ -f "$f" ] && [ ! -L "$f" ] && [[ "$f" != *.sha256 ]] || continue
                size=$(wc -c < "$f" | tr -d ' ')
                total=$((total + size)) n=$((n + 1))
                printf '  %-50s %6s MB\n' "${f##*/}" "$(( (size + 524288) / 1048576 ))"
            done
            echo "Cache de descargas ($DL_CACHE_DIR): $n fichero(s), $(( (total + 524288) / 1048576 )) MB"
            ;;
        vaciar)
            if [ ! -d "$DL_CACHE_DIR" ]; then
                echo "La cache de descargas ya esta vacia"
                return 0
            fi
            [ -L "$DL_CACHE_DIR" ] && { echo "$DL_CACHE_DIR es un enlace: no se toca"; return 1; }
            if [ "$DRY" -eq 1 ]; then
                echo "  [simulacion] se borraria todo lo de $DL_CACHE_DIR"
                return 0
            fi
            $SUDO find "$DL_CACHE_DIR" -mindepth 1 -maxdepth 1 -type f -delete || return 1
            echo "Cache de descargas vacia: la proxima instalacion lo descarga todo otra vez"
            ;;
        *)
            echo "Uso: lvm-instalador descargas [vaciar]"
            return 1
            ;;
    esac
}
