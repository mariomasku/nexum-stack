# ===========================================================================
# Pila propia de una version de PHP nueva (sin XAMPP)
# ===========================================================================

#@incluir comun/pila-propia-version-php/progress_parts.sh
# Cuando MariaDB se compila (MARIADB_SRC=1) es lo que mas tarda: los tramos de los componentes
# anteriores (0-93) se reparten en 0-53 y MariaDB usa 53-96.
function bar_pct() {
    if [ "${MARIADB_SRC:-0}" -eq 1 ] && [ "$2" -lt 6 ]; then
        echo $(( $1 * 53 / 93 ))
    else
        echo "$1"
    fi
}

function progress() {
    [ -n "$PROGRESS" ] && echo "S|$1|$(bar_pct "$2" "$1")|$(bar_pct "$3" "$1")|$4|$5|$6|$7|$(date +%s)" >> "$PROGRESS"
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
    local file=$cache/$(echo -n "$1" | md5sum | cut -c1-32)

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

# Ramas de los componentes que lleva una rama de PHP: "apache mariadb proftpd perl".
# Una rama de PHP posterior a las de STACK_MATRIX usa la ultima fila.
function stack_branches() {
    local row last=${STACK_MATRIX[${#STACK_MATRIX[@]}-1]}

    for row in "${STACK_MATRIX[@]}"; do
        if [ "${row%%|*}" == "$1" ]; then
            echo "$row" | cut -d'|' -f2- | tr '|' ' '

            return 0
        fi
    done

    # Una rama mas nueva que las de la tabla (con soporte en php.net) usa la ultima fila; una mas
    # vieja o desconocida, ninguna (antes recibia sin avisar la de la ultima fila)
    if [[ "$1" =~ ^[0-9]+\.[0-9]+$ ]] && [ "$(printf '%s\n' "$1" "${last%%|*}" | sort -V | tail -1)" == "$1" ]; then
        echo "$last" | cut -d'|' -f2- | tr '|' ' '

        return 0
    fi

    return 1
}

# Ultimo parche publicado de cada componente
function latest_apache() {
    fetch https://dlcdn.apache.org/httpd/ | grep -oE "href=\"httpd-$1\.[0-9]+\.tar\.bz2\"" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -uV | tail -1
}

# latest_apr apr|apr-util
function latest_apr() {
    fetch https://dlcdn.apache.org/apr/ | grep -oE "href=\"$1-1\.[0-9]+\.[0-9]+\.tar\.bz2\"" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -uV | tail -1
}

# Ultima version de una rama de MariaDB: "version|url|sha256|firma en base64". En x86_64, del binario oficial; en
# el resto, del codigo fuente (se compila).
function mariadb_release() {
    local kind=binario
    native_binaries || kind=fuente
    fetch "https://downloads.mariadb.org/rest-api/mariadb/$1/latest/" | python3 -I -c 'import json, re, sys
for version, release in json.load(sys.stdin)["releases"].items():
    # Va en URLs, carpetas y ficheros de configuracion: solo una version normal
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        continue
    if sys.argv[1] == "fuente":
        files = [f for f in release["files"] if f["file_name"] == "mariadb-%s.tar.gz" % version]
    else:
        files = [f for f in release["files"] if f["file_name"].endswith("-x86_64.tar.gz")
                 and "linux" in f["file_name"] and "debug" not in f["file_name"]]
    files.sort(key=lambda f: "systemd" not in f["file_name"])
    if files:
        url = files[0]["file_download_url"].replace("http://", "https://", 1)
        sha = (files[0].get("checksum") or {}).get("sha256sum", "")
        if not url.startswith("https://") or "|" in url or not re.fullmatch(r"[0-9a-f]{64}", sha):
            continue
        # (y su firma, en base64 en una sola linea: la comprueba install_stack)
        import base64
        sig = base64.b64encode((files[0].get("signature") or "").encode()).decode()
        print(version + "|" + url + "|" + sha + "|" + sig)
        break' "$kind" 2> /dev/null
}

function latest_perl() {
    fetch https://www.cpan.org/src/5.0/ | grep -oE "perl-$1\.[0-9]+\.tar\.xz\"" \
        | grep -oE '5\.[0-9]+\.[0-9]+' | sort -uV | tail -1
}

# ProFTPD publica parches con letra (1.3.9, 1.3.9a, 1.3.9b...). Se descartan las versiones rc.
function latest_proftpd() {
    local tags

    tags=$(fetch "https://api.github.com/repos/proftpd/proftpd/releases?per_page=50" | python3 -I -c 'import json, sys
for release in json.load(sys.stdin):
    # Solo las que publican el .sha256 del tar.gz: sin el no se puede comprobar la descarga (la
    # 1.3.9c, por ejemplo, no lo tiene; antes la instalacion fallaba si el ultimo parche era asi)
    assets = [a["name"] for a in release.get("assets", [])]
    if not release["prerelease"] and any(a.endswith(".tar.gz.sha256") for a in assets):
        print(release["tag_name"])' 2> /dev/null)

    # La API de GitHub limita las consultas: si falla, se leen las etiquetas con git
    if [ -z "$tags" ] && command -v git > /dev/null; then
        tags=$(/usr/bin/python3 -I -c "$NO_TTY_PY" git -c credential.helper= ls-remote --tags https://github.com/proftpd/proftpd 2> /dev/null < /dev/null | grep -oE 'v[0-9.]+[a-z]?$')
    fi

    grep -E "^v$(echo "$1" | sed 's/\./\\./g')[a-z]?$" <<< "$tags" | sed 's/^v//' | sort -V | tail -1
}

function latest_pma() {
    local version=$(fetch https://www.phpmyadmin.net/home_page/version.json \
        | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["version"])' 2> /dev/null)
    # Va en URLs y en la configuracion de Apache: solo numeros y puntos
    [[ "$version" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || version=""

    echo "${version:-$PMA_VERSION}"
}

# Versiones de una pila nueva: "php|apache|mariadb|proftpd|perl|phpmyadmin".
# Si no se puede consultar algun componente, se muestra su rama seguida de ".x".
function stack_versions() {
    local php=$1 branches
    read -r -a branches <<< "$(stack_branches "${php%.*}")"

    local apache=$(latest_apache "${branches[0]}")
    local mariadb=$(mariadb_release "${branches[1]}")
    mariadb=${mariadb%%|*}
    local ftp=$(latest_proftpd "${branches[2]}")
    local perl=$(latest_perl "${branches[3]}")

    echo "$php|${apache:-${branches[0]}.x}|${mariadb:-${branches[1]}.x}|${ftp:-${branches[2]}.x}|${perl:-${branches[3]}.x}|$(latest_pma)"
}

# Firmas de lo que se descarga para compilar: claves publicas de quienes publican PHP, Apache (httpd
# y APR), MariaDB y phpMyAdmin, sacadas el 24/10/2026 de php.net/distributions/php-keyring.gpg (las
# de php.net/gpg-keys.php), downloads.apache.org/httpd/KEYS y apr/KEYS, supplychain.mariadb.com y
# files.phpmyadmin.net/phpmyadmin.keyring. En binario (gpg --export --export-options export-minimal),
# con xz y base64. Una firma solo vale si es de una de las huellas de su proyecto (GPG_FPR_*), no de
# cualquiera de estas claves. Perl, ProFTPD, OpenSSL e ICU no publican firmas: solo su sha256
GPG_KEYS_B64='
/Td6WFoAAATm1rRGAgAhARwAAAAQz1jM4Sk47/5dAEyAfZNFSdKqWSSUFHmfRPjgtY2dDKa0whmRx6L4fvuXsmsiLYLPh09CNboO
RBEdh1mAgKfP04PowTlJAPcrnMFj3N3WvsM1NWDZx3i9KO2jxrVf939eQ7YeU366zby3Kt5bmNTDqil+jYTxgtR3FC148rP2CmJV
SH8y2ovK1qdcwOJSFbp5o++vxle91QDIXZhMuEQabWbSrJFzvJDxdeu3FWR4zua8sElg/p0aLe2X8av7bWcamf5SBrEVzMrQLJOp
H68lH8BtUSLaxBYSKFjlB9q9bttYyLnx7ozfSJ6laQmcssX2/XuaqpsDsGxR/uUKSObMrvrTAj5vGYLBeR2Y9gR1DOz+ubfG0ZE7
2tFmH7hU+LZL3XuLgdXLkW5YEyHLyXFKKTrpdctoE7z8TtYaefbdUbdM+F57ScREOoJvfdPXDyyeEB0vxXZfg/KDxbC1F1L1MRsb
5vko/0QPoWhnpuEmP0XUw4Nhy2Nlc+aWA4QZQ8E4lb7VhfDkROyjdpHBJJsrDa9dmISbH7Qy7EAqudb2lyjl9BWLs/WJiX2N8dv0
4IqZiyWE5SI9gYSaR18/zHUw+7ulFwR/X88QYd37H6iexPr5PkdfuSFHv4ZlnOc4EkEIN00eR9M0QYlZ11/Z5qagBiB85zihlErc
eL/65WPz6+Br07T+zfRa7qD/jtTa2nHTlCt38B6N7OKgt1rdlp00rQxnGbldEOMBwPzvygUfdlHXe4YxTVJev86fFU4WeTMIp0mB
oJhWnciLtXS+8CsFlOJZTDf7Kj5NX9Hvhv4F3LnaOAxP03T7pqzIeUEchK3iu4fUFAqrbr+UWIb4ZYw+vn0sSqzNy1wPENwx7TCW
+KxdrtyM2my2bUhk/K7Qr+OPAeYWUBr1CD7ekV94s7eQkym+f/cmhwdq+VkZxopvYdlbBjq30Fz7PBq8KP9VU9AAcRrb6M6Y7Pc1
L08q0tnzyMZPP3NAysZkKnXJp3++4zAVSiudH6s15soD5BMnWm6KsJIM1Lvel80vWPTIwlv4eeGF5XbOWDDx54xmpE8vwSxGTARQ
t9Vr6ExN7H+71M3kC4kQMx4zPM/zGy1EjoYhVAg//QXrR/i7b/glRin30J9nphEmHvoJR6syto7eRK8EZXQyqV/XDU0xGc6J7HWN
KNK1LFr13wlc8oi5NjdRIVdmh9CQWgXmshcTwmAQcfX+huTVLR6c2srLkGHV9UUDfc1nWlkxlllrn9kw6T3WNuXuhZSqeQpW32Xy
fSyra4Z+fIVGGJlTpC4K6SKYE4A9lys/Bv/3Pw6nH0Kfj4NOJ46M2CQU6guaYjbacQPEtTrL1U3WA9/ZXNQWB/roRIeSemEY64XA
PtHJ5C+FPgplKPWFhpO26Y1TtQe/mT7dEMu8CcA5aAQH82az1ZNFjEnfkbWXHLvyXN4GhzwYSdgyDN0orlw7/TyY5oj80bvFcRBf
fpbwr3XSMIVF8A4XV6o8YwWcGKyA6e/vFkc1zh4PHDlHvU/qQ/TkNwjIuTclDW4KZOWbIfuVW/HEq0YFrwzc1eUAWDkEUbuGFsYO
niiPk7MUiuxPT6h6DZ9jFeNOIIZoXBlFNWSBCrkSWEOya5/z41qKY+brY94AJ2+RYNr2fve+bsuRWXp46wQ7oYKVWYlpvf/KLoKY
PpSZmSfaybcqve6FHt89N5wRjW7rom8WnWJF3+7srViLZzMph00HV9uxbPzIPQUp+35aZYIGBGlAogaP0vWk2/yOmxyMW7WqKMTK
RymVi+0QSi0vXYZZoQ/D5O4wHkt62xkpE4oU8TdvTt8U+qu0OpF7OWiYQ5i5j7Hrvly3Zi7wrr3OD8O0zLEQWXJm1TH8r4ifc7b2
d50uDmvGr8t/qb7SlUHDkEzMTdtRos4k89/HCg8EZgATIa+oPGFUv32OCfU3saP//zJK00Zxwy3eiUYXsZD7/sDksqtDE4j+M0I4
dnZ/MxNaOt7wv5VfpMxwQlxq/IZf5G/omzg/bYu5e1uUxiKvAFYUpofpfNEnFcSrmgGVtGkP/jO0tX6iu2FIEPJJ5Mtmt0pwMk9F
3yIsYCcZQzYy9uZJfBAYjAM8yqnnZT2WUvXMi3BWZB+L+rzcbP1iOjiP0pK48DlVmM8/sWd7l447VSjbFMUqsB0MBHtoX3sNcFyF
gE/Dq3Dsqy2uwiB+e3qxhSzSCkgG3+yR9OyuuRB3bFIWDDy4yJHXmEInR8d4VUR12Oynw9VGR5A2tA+OB3wZqn8KGDav99PRikcs
XCDW/M5c+AQTyvksZOxaMkyzTOsGtU8ZKbQWZOanhYjLUf8e6fGwA7ZDBtMipszv1UzYk+zGTbw6/zlVWHvWC2WHEW7jW7ePNopd
438R2fRdXOFBdXzkuIz9lqmhFfaj+x3yofE46pLCgfDXFIGVOoL7+3rE8WqIua0kekHkGUiaeW6/x4Iv6ay0rMVnekarDSDn/3Dz
Hm8XO2WmOpAuHyV3cRs5PU9VMNG904DwvLIipcj1UN6gVN+WmkEM6wLUQp00nsaZ9jdXiwb1jQGbCNPPBrf94qHLpTd0tsWlc4Jd
lLtbrGTePrEJNsGSE1WAG92KRzz+FCXkDB7NxzE1U1pWVqA2abUj0Giw2ewrYIoV3nUslK/l9TVfWPZdmfkI3Lx0goWQ/CaWFSd0
eygn8JOXZ5OpZUjAF1Vz1DpIQ5xwE7oxG5KgQwknFRnrX3g3umkAtbL+9wFNyOJtF0lmW65sPq0bHtgFhtqKNqIZn5YnlXJXE77Z
sFhbgAaUoWcxF5zpOx5XXP1dkro/oK7epE7Z3hvJUDB0n5wNiY4HqfXyOvGtvEv5iABZx3FY7orqbizajovr5I8VQwnCkMvlGlVB
YKTW3Rq/fJtQm7LfyAkF8YXL3TTUu5EDdOtQZpyodN533/y5fq4OuGLppkE3LqTUMjXfOMpgl2PhtVPspkNcsLfPbYduxe0wnZer
SbVKjm7wIaLD6CpbJaqix/OcGEC8gTk9Cciw5pvLpVLXy8OIjSHUdI/C0LO85owsEzBTRDJAGJxz1b7S23pVututKTSzer0Bv+sR
rF/FxkEU2RXMz2p6eHUu2CasGEKHQGFJiPp3pWHTqmnnWHtY7oGVwjXZOn8VTXibJm/84I5daQlDHN1Y6fCOTyXsHzeFNBIY8Jps
wYiseYmqwe/fsinLB9vpJuvOsk7+gNCTA2LbPDWVibIN0R9z6y6ry0vMh2c9urTcw+1I4k0psSbNR5kPvcsiA316oP45Lf8B2LpB
zer4p9BaPVBZ9sM64sHymXJWQEAVvtjcON4XOZvveF5unD6IW4nUayOZrLRIOu+qdKOtK3dyaLe/90C+Gzi66LfDk7LNvn22wyl6
5a6AG35scue5YCocdd12ryA8+7qrk4TxcWwLC30AmD+bPdhZSj8TP8ZAzknjFtSwxgGvWuGYsi4uFGOH96Lg1gHNs14fBxxaMLRG
4dGWKHlzfrFBwY1eGYi4+GYUwVTBYznH6GrXK6KuQHnAiHwmJw98573VvMRw4GHzOGypR3J2Uskvk1RJCxiT5y2RQqZF2GbPEAWH
64/13kqus73c/5dsxnHQApEGLVZX8YijUMEHV1zDQVqns9hDAKDiOb3d/OxuobJ+SA7IL25Fd0f9vs5J6FdRZMy0bLV1mR0FPMUG
bjIK+gaYJiHxtb1Y6LkSrE63xXMbk2UwFPWw6QsjiE8u31A1LLdnYVRbm3Yf+1c/3co/ropaVYtKVcZJ+0/pOrRMCU7GpVfJYrGH
Q8Pf/LXM+nPqeUjTYVT6XDVJ5KId07wN67DGiNOXV0T4bXJ7CiQFC7zgbhMhRmwQOvQnt7E+4KQaTrGGhA7ddIb4iwo7GOAyMGV4
vj21787BW9YNucRD9IVD0RtwXt2X15npKHI7qKiqEfYhBmdnh8OKznO0Yy3qoEHSukpSVU2EdXjb6qq6Nk0AFGKpyeGvqjoVdBb2
1HJR+k2Danm0r8Mb804hcx/gaUo+5A+qGdarhSjFHt0ygxoo0KRWmbLN0zTTvAt9ipuohGSDZQRNjwuadoyxaSkciqxH1Rqb5BD5
OII2I+Oi7YnTFQWkXcXHdR8g5zNzcoQjRBPwfr6mNw0AphcUwP95CaurC7bBgjZNVIuwYpsywETZHWTiZ7x7Bz9EW3zj9fZ3zOhs
Ciu2alVw9Z/wlVKRVH4yTgOVER62seliu0piaT62WP7LKXxm+nvqdgRjYSjS0T+2a9wM+olX/+BEer44PYDnemXbgaHyD4VYrlaO
sy9qKjEj4cNiYqTGFNAccM8C5yfpVe0bRah7p1c/QZNrfGnDSK6KcQdR4fF6vPCGxiXSWkC89i7j41b3sJ4HLg1XtuLRo73W649L
qaWJEn+d0uyx2/HF0hf9Bj5MP0C6vraK8FN4WbrC58E3PqAnqSnpRYLwmkLdb3UromsR7SAhphtE7lDfV+S64ZfIcFkBX/oQR9Wx
nw9r+GOLmNZM11gXBoBM0kUquKAjqKcsmmrrco/CpZJT6o52bPFcnKSzHlvlKEmPFH41QjlD3GW1xfNLutXyc26MZgUeC+J6tE7v
3jNOZ6++OvG2vpWx3q0RccHA5NYC3vYZksGRBoEovv1lmF408rK35715sNj1jQ/U5tStJfO9DrOLGvzzrlxES6J/8Kwlp0eEOhch
y1QJxenyP51I55I3mQAl68Uw76CaTFnTHZ4p9v0BQo6CimGxzYQYLyr7ZKQh557bvLKf4e6QeyzQDvTALiQHsLfAxOrQvPGB47nh
E0IGn1jL1FBB5DE/Wen+xa6kt2DrpEFm6AaerbHoZgjCzK0yORPpTeVHo8Na/E1gvieeWWTeKjIHrRR5akIo4EDtR9XBTct79oEG
J5lYW8Divp1ECx/ToXo3bHRSTyE8PN7ZA529wVMlBKnBc70nSRfvGXX/2r27KPoDDHHjivAejeq2i5ciT25lEQeJxCvbveeR8Oxh
M93n67geupMUxaQE5jYIdMu8Xzj6rYTYTrJAZXs8DJi3QNhVPEQGtZ7H1T0fEiXw0zc1vkR6VGlHAifk17JF4g71ZCUz/SXHvVW5
EaGlqMP/EX4nikx22PqUVUQBPuAsYm7+CbDJ3zaW8qZYgJnJ8afPxuESDb/PqP66J03mOqA4Bx27r+yGFrgKzzymF6HiZKG/lcod
Q3czymAqXRTExM7AjGLNigltcYgGZ43AOwfo4SCqNMQ5Wp53SAyOyuvnZ61Exyit8gVf92cQNINLd3CECPe1u9Gs4eCltffiJzLc
vIviy3Zv8HE0l5rKjRsmVTd/OxCihK5RzoztZ6qcpUwmcWaz2lMaucv+Lj+6GEkdwS1ZY5zHGAYtXzE3XnXBkv1aFk4sXpPkPyPt
qyFSJzpwmCZSBRsEYHFvDLH462kzrLC5qTI1wkjo1T4c/nYUKzAzpbCUybIEIq1RlNTSunCJTTCfUqKXNVWAwPXnu4AglsP1MFAl
VnalBCnOaO8A/Gmb/44I2SCYpMHMICo/n+fGmRDv2HHCEN25ZlazhK/K1bggF2p1DR+OA/GbaXAgvQmcgwMeu9F57QdFh9SofNEx
6VdM79bn4V2VGrkuW3lKLNgWrf7avLrrDl0TgDmb1ujVDM9RyCHL6lo7QNkEYMpOLihwuuZpZ5szEzfN12jUhLBCY/ZA1fMynfwn
q1f4QfYDtGG/R1l8qAAT8+XLMeCrV1wOYeBGF39u+MrrbrzJQT/HC02rnhgNrAqn65p3UYFgOXqTtS+IMCttJQXxCJjWbZF9356Y
lEVSZluhuZFIa70WW4t96jE9k2udZkkHkH8mmC0Ilx4kHeLs5+7lixIqg1WleCovLWchoKd7mH0k8O2cQIFN9aOF25u1nHLpNmFv
CjieCzGClPLWJhN62gXQxaDalB2fCTZcbp8icna/PbZfopak8l6sm19qdlnKpYmYr2euXF3BthbRVGnYIgvtsNeQWRpSDaqFI7i5
WtXbbfjl7obaWcAc+sW5nTox6VnLYqlt2GM6MghuHf3ZGxwnlMFgEqI25/6eDGkGNkiWXTk0xuMSGIxs1C1AbFRgEmRZMA0Y6AWU
OkRGRCUn99OG3LiSDnyqKUrD1nRz0nhfv6yrewQro9EUCzNkbLi79Q8komjyANuTlhWyX9+LbelkyD+9J9WIyItPqEMxUdfDsl/u
IEWU3b8Ta+KE0hhnHfeMyU33nibt6cO+MBtfqwcDX6xckqTKeqXNK6oTg0ekxBIoCZ6yGLAPGirrO9RzEN2EI/Q+Hf+n4txJyiBk
QC/vdSO9pUi18Wzt8/Z+9kH3JW3HH5nBcR+tDAUS938YPfEKdrPWLO2TGexwcjNTRdvTB4TAH/RPfcMFUe1AKIEB2VEoTPn81t83
Y5lEzUNgqukpmoce2EkAeXiZQJa9pNXLQMDwWXddfNKuxQ14h2YS497qh4tsdelMXro8e2gsjnIm5JFEF3OtbQ+Tt+1uSOlEXsXS
MurG7qWfG6wMXgXPu9I5oa+BkWfTWo6xm8zGXf9U1kB6n94v+MUjMqCtOZPxgkSzXmz0PdSNtI8u/tpOssqbuonVv1Y3XY3SIFcx
+r6zRWbHO9B9cPhgz2uJlMjiXJNsDOS88lbi5bSckJ9TyaXEpLE/nS9RO0Vs0WNMHoL2lMNDshQOTGNnHR3kNXCHwPeau/BseNXv
JiGe4MLI/qVYjw0oL1yKk4vraOvH3XBFaa2Prx0zAZ+Cz6iJ2r0jspLQGnuUZkaYn3oy10l02JkBh2aBaGvLyn4LJWmiUVYgbJ4k
FXtf9qnFJg0Cve7TsSBWx2VW70BsWJx6lYUy9e3N56Ewq6QMjKnRwuVZAaJWfuU8l77AuF+wx7Xmgtn04m4gRHIi/KqlZ5mYwfq2
TvhZ54SsMEN6ZLnaXI7d/ci+Z37cYabTmnHXi4shgYMADnBGjwLUja7MxVdnDzDzNP5pSwWyLe8ElmRXpOe2Zcs+yqqBKF/Tt+hy
K8L7AWXdR8Rw4+WBu+YW+u1tQQzYwIWWe5s4R9HGCdy/hNhZyCX0kNv4Hp4RMHbpgOz7Rnpe1a3C3BMeKOY+wmO9pUKCptn5H+AH
s2/Gv+RmRxWCIKd8xeSfCSTXsPVifFMknMuSCRBVwYlSRFS5sypG12GCQGcipXR2RCakDyo5AKoH7dArhPu+C0RDaYgLFXmtjaJE
7TLwTLIuQk3lcI5KSc2AqODH3E2xuePk3OHYWh4+jicvjVXpSEXlzCOreQ2O1HvO7zvMlqnwy6zeS6sb4fvy4Iq0VumlW1fwMw6x
ViZ5gA76AqFSsZs7S2PkcV1fLmjrLvXMzijrHkyUUJtAWsBQZWLKx226uuCF3UclnhfO2bu7IktRI9AU1L7lFXqMqd1LfgjoGBHI
ZSur0QEcFFnt3ZxFMxw4aoIMyK7NmaSxdGNOiAHEmPN+slyOUCqDjeGDBcZIY6djV+TlWWSOIdlN9NLrTkjGwN0rkXxAvJb2b1m4
0nzfAew+KTKwawMKpKrcGMAAFcdzD4r2xd2klEZIgrdsFM92vY/f0FRoPr3CtNK3+AlzpQ3KCIrz1miEi2Ys3/Os8rRRHPN9IFs9
gmbtVl4dpbxQSjEs+nGG0F4VBwktjf5cjg6k027EE4HHyqEGEx5p9hp52Wve4GA8RUHccQHoeoCk4fqXwM6YclcvWf8lTexwZtRt
aNeZ2GUwuIH3AvAZMPn6msjZUGQK1bnNUmusxfuThmu9qT+c4EmYi+0Pww6+clTvK29y+hI/s1hlf34gEVE3gEKGT+8wUe18kSCx
ksEML1gb67lrCuK0wLUIMY3JjkoGiTuroGLSG+r1qdCnk4BSeZc2HtyI7X/6kePnylxDHTBMFiI3nasu3KHJn8TFZSLoVjqqMP3b
0d0lagj2bd7/XHBkccAudifeioDMaRRvExRcjaHUj86lsc3uTZlv7dVlQ8qCejMdrgRmxODUZCthSIzhzNd2+KwaoYB7LOE0lhXD
Q+N6OwJuPwK/75YVkf7GgnrY2kcX5g9pdC4tjIG7eZhfoHyMQ3M3yLIoGaknWIuAXYVvpjD+nfbrI1ehz20TDT5kE3oIIk+Hp9yb
i3oO5BTp87sVq8BCU0TIALMNiD9BRXfN1LEh8jrebqj2ylV9gWY9Dw7PLtqFX2PWJg6CUiE/e09HGZmkpp5UAwEUToV7/jCTjruB
8LrD76TRL6ywrdwyQSH42eP5rMCXySQqh8d5KvJ14czeHL0nr3jrLx/caOZT5i/9FKmCDCHbIkPUtjNp6ECkYxHOZCTfR0wy8wrx
5jjCz7ctYpyGiiLUGfET5mGt9MNwXq0ZqUbgrODABJbdCQ5oFNqb3siN7gJQIqE5BxqYlLSmhpoDLcPUYQcLVLYJcSpn9IDOM7g4
vrdmYZX8vmZDmAwK6ke1hG6ZGQAcvfjoDEmH+khm4fi+pLSTl79htYlq8a4seVRiU6+nX8H+2sPDG0WmIeeHIRfE47dqWJbf7aBV
X7PAlhx+IZFXr673o76z8MXDI1LgBySi7eD2BmZRW+++GcYkVjg5x0YH5mEVkxHQNCu5JVeeT5wfu4xTqio9pQoKxg4Xg5AOoeTr
wLPE9463ni9mFYPnzTLcr7Z73k1nVr75JF+LJ+6HWYeDNACyMf92Maol5jpF3JS8DpDqPKnKPYvpc5atkoulL4ljda5YkGlDXSX4
Jx/iw05jOO9QvUN7ye3TK8E1hkBKsR8J0Ou+9kyPc66frrmCU7hGAR8LinSBLmMQSY+OSREE7MKD6brJ7fLGRTp78f69jhpRlK9X
X/2Rdyy9I52v/O/qqXoGZ0871V5nMrMAMGvTT33b+oKvGi0sPMqmQVldPfQiKpZIiHSAgrGPQYYlbeXJfDuNGTTrzH2vutEnnaWk
lBUxyLOe0FcVCkfpfdtsWSjaxT5aDQFFs8M32bhE5wSeNanz/XrPI9Sc4JEr30hjTdqT7vnWCsabgFGWkQOCbJodQHBa26PPINVq
SbUfiGb/x0UA91JT2tvWUrFjwHyO3h1GxncA6LB/c2ojOvObgwpP9pW2+Pzi30qtb5rIU5Qu7ugfG84UTZgr9BNK3iDTN3XsYbX7
vNnnT9sPE1MAPLZ5MYJwZ9WjGk6aGYmcqR8T8luMXEuyBxkA5qYcTde3kohKkRyz5e/k5ZL+kMUPjdfjxcyQN2wKw87W1lrlNz9/
xbwRROJyGW/DMC4XHCyIKDLUtFv7Ly8o8QYFnHBMObXaaLmxlvNSu6Zll/g3KPJXpCTzqe+BSe68TV6B4sj/hn5lhXXJjJ79PjOP
aGt1xBOrtso9SiyjepDR0N/cW5HUOMJP8YVCNOyQP5Weo0rV2QIRFGMEBi0wBioM2iPVVI1fYpP/1QbKPkZsYEwT6+iICoay+9T8
NS24fyBX+BQHfygESN43NF+J4bVAx8vFcrcH9YrqmIlNhMhmjJ9gAa1j7SDYIVdW5Ygx9fsosLiOBD7dPfIMPcGxYX44t3fAqX0w
mB//9FzdBs3X1rFKjRkPGwkl0qCFjCqRSaHMEU9qgD9BpUVMGP6XM/BMnMRtYueXfxfIP7YTXm/bSTYaSz+//qLdwYO5JeHFGcdv
3IiY7qr+kJ10CVZPLBFyzA5jcHRGp/KPiTXmQ7JZJ2ahLsFRg2BEtpxq1qG7vayvDoEg5YiBqXSg8QV8ZcI64+3Ef0RGAzS7d4PU
r7iam6Max8KqsMhVwVPxLGqnNhON2WS27Q2zq7616cVcshwl2B3+YUea0VsQn9DBXZIstlH0867WOKRRxXh0sskkAi58Sd6UY4TF
PKh73RVtbmBDw1f9STDw/dnF71t+LLiIoiy7KSJ80pN6rFXUeeaaXfOHrhjBV4LlMMmvxwvpO3JqgfbK3ZPCMN4CLSoxxO3ruIQf
pDm+WhPGqwl3vM7UAUpxerYsY3jYk3v39ZDH84Wq85YvpkUe+ZIKGsNKi5Jx1OQJ+CJCGQcjie69RdEMpGeyM6wGT0T36aGcJ+un
A1Pt0kUsmEl6lbFJjGpA0Mj0WmnL7l8ADA+U2Q+mimLBsXmYgrlmiUMoVrHVmxeTJ1pQv1/nuMO+aIZHDTcT4rJ+8WnDbOm9MuIA
fYZg2z5UM7Jl/2g+GHFLoaat0I8KQsuStlSSINEKE7Loux3JynuiRi+QlCPDIAUeUuoyivSSGB2YkrctDS/ECTJLmdcsgTQN7+OW
flE18BNBQGu9Olrc/M70jC7Q6ZXpYV2ivrIRqb6EtYOfuTBAYREgVJkw6amtM2EGT7zhQQkHVTsuXcRU2vnR+8JBDxs6bcte9VL/
FsXuFwdFc7qSdYiZDh6ZnuoMzowEDHZejZB+o6JbpnhnmPGNJSCxIlZb0k/rFSE9vMbpBo9ooI5ElaBjAZvfz9IF+slDXuI9mBPR
4vUDvKo9tslvzPgSgb31KjvA5aD9dSKW+nyXDpxZjTrWiyjQybgzfq07x4bwmSjLiXvHogmV0MX6oVV50Lr82FMatDCaSUPwJSmu
9f2J0d05Ee77OtV1C2qGdpnAeIJMWy1DY5od/ru3/ieGzLJnMmsL2zn/o9+QNZyv33RxU9RKnS6f9YqQ5qhTUsRzClsicTjbinUm
DycnUUx6MlIH/AWimq2xWIh3TDGwqux8rf/6edRsoCIu/wPVdna/aridsBJv2pKwa6OdE+VmrtvL8pRbhu4l2SOtngM9wR7CF6AC
hHnAhdHqQ2nm52aWD/2Hpgl9lJvXMrgNdTybNO19RGtHDyr+oVdLFc2YQ/+7kPqW6IaoQ9KdM5U1mHXApEx8QfQQIYiqkRv6K7RS
KeLh13cSxh7pNOQZJtFs8i9O9nnxg12lklBSTvkzoc4FHZsMSh9Ciq2ExuKl+9j3sHQcKLO0/Tus+RXiPiXw4XNDSDzeQXwHRhhH
I1CvrUwlivwjGRFTTXSODlq7IoA4BY5wFYTulA2MLVamBOAUaOq6PHpzaTp3QNvwvXcLFOOKqD5PWfM4c8R4iTUXLp/WQ3xUPh5J
zZheWs95EmYhxkwJTB5vVwJ8Y7faJa/3NXIr0LRAFFGA78N+NxWCsVqzPEzFWnaVngBiiqaIXo2lk3Ab7j2cYxuoCj00F7GHhEhy
3ebORLvC0madE4spA5EvrMv08L8ML4LqngKJSmxuIxMSrZKP7mt7pYR7r6LQebN5HZUKxRD5aOtkyv4sIvKElTnZo37SaEN/7QPG
QhMzkoc4GNUePqxHiuesjR0RGiGjzvwPVLhb669OE4YdEYS3LL9F6GIymRmE4raIDwowA5DhN/49LK1kDXUru9SecyyI1URuxpX2
6J1asRAWVDoyi8YJw+SMAyhXATrKwuQbnQLtT6cQF10OPT5QB/9F+VSc/KK3Uoda9zlX4aGSYsasE1AWIPPbdtxucR88wDoMaJqT
q6/+NBGE6l9cQXrFdrlotyBl21ylbW4GIx0S8/UpUYIJRc3/eq3DUuY+YIWx+BTWNZQUvJ7TEAjh3iATra5kqBSbCrR5wCt+VQfy
RHK9BzuYnQMFoEBsi8vFWaKGgS5OeQZNLYe9wBfgH4IJ6bTCO+5bOjDmbT4wnacnOHjKS4G6d9Hf9CH1FJ0HDqHMueMiAshS/IAO
W9+5hiTuvupYIPoTH4wXeLxzUui3y8YyYVN56hcIph+f4q4vymZBOtgs93ehd10kBJAAPk8x9EIWXJj/QQVcWIAWkI1S41ocfH8u
sz88d8F1VSVmhRp5KzI0pJzh1jiehq6lPOzOHszSshcgj/HWYuZRs4siFST/24nlrcFPQ0uZuaOnNUdIWrQvtJzoIVVAMgr76Jhv
a5auczO/bxUfeKHuBoEka6U4mSJhEzd955XSqSmkNjcf84sTftrjwj8rRPoXVurfeGvk7P36piwpAPNvTvvHx589Awhe0veMK4s/
PHNZFVk68sUTNkyRsfTWfEXPjCeJTVsll0ndGcX5kBiisInOrsuiidCbWBjLXeyJWHC6Trm2/MXjrEo78/aw+IAV/Sg/SngFW/Vf
rqM5hcb+uODOl3VgPMlXFig5ukN6Z01ZoQqT11ZYcS4nyZphiKIa9To05B3Ib3IPxjcFpEc+uzhnIFuRKmxvrS2rdhdXSOcLXMZC
eVL6Z4OcPHCsdseF3LvF+1mB5COzQHcFxrSJICisUuEVGpGlHoRdJYIwAcrWre0f+kVScxssz36TW5e8Kqj1EdzEHEpZaOb+JXKx
f3gldInAlcTQ4hhTlIwNoJvyiM+t4U7prT3K7DYWPkxedfRx1h1zpMC+jlpMUtHZgpQEDeH5PtAYxcT4kNv6mS6/kIJpPKQ+NFR4
IeV9LSOvHKopyOTVezVhJeu9iunlj8Hl66+iWBCay1Vf4vr1ZsWPqXzgpGgwxPznl6VRLJBHo/JDOYbQiTt4wVMp1F5FbwinclCy
c103kGwjI9S4iY4cV2bidf0SiarC5TFo+A6bRg4+JAJ2Kkdmcgy7nbKWNWD4UNyfbbwl/wztOl4Wi+hBdYYNcEFnrKtHIfkwpdJy
8NpzuzUBq3/jrXGSIdaicx9EtHdSrph+ab7ZGK9ETLeoTIk5Kl45W6X/GOvaPSTXY6ZekFSUVQdDr8HWI4GYfqDDOZtMj7vxUse7
B4d74FOZjY+UjJfgQbXOnaRsWzobe9vCfOBRODPfcAJSGBzJC8g0njnR97siRrCMSzVazs9NBbwCOUG9UV8bCe+Wgslh489TOA6p
NXHtBB6vhny9L6ofMXykgIrvznGfMDBmw53+Q0XmdChh4PgEqF3azCAFYwSQoZo1Zs3hO9xLsx3Q12PNdlRsNZojJAXJnlwpqafS
h5o7iIi8EsI7MV6kXxNTH8s7BxG5JodNLmYFSK9lVgIiJxBl/pjdJn5rTgQ29S/+gaxboVtdLbG6MhaIEaF0OGaqIRFQ40OnqFwe
i49CiSlZ0BuzQ2JHgCFlZzxQONXc/6He5p1Gutds52xEx8MzQXooAmizOMLuO1DdxVEiaf4ScWeDgFZwreDaVVH2OhK1J4XFtdDp
HzEh3U9vM0H1gNA6ujUBooJoTB8IsMq4w/qgIds/vMZImuVNDYvkeowRiaIy2IqKJIIX8K4l/NLIhee/xJu5rZm0o3gRBz3ihShB
p3VKzf5Fm0Ko7hZyCq35HxS+ZMoe5dT4cUow9R2GClZiJG726N1vbmzxT2itNMSXYCpz3tVl7FJHb0xBzvoLPQyHrr7RIRwpTrgz
3ReSJhQYBo0SD3ZDLluIVfAHaURNRQTCE9fh55ifzOkOUPS7VsooF4PBNG22Uj8RIJvZP1ly4i/yotw3nwgXph0wOVRz28WHcAIV
brFUb52+1Adx2uZjNhkG2quIlngMq893iTVwpxFmB0gTpgxozVFocJSkBbeP+ONy9KKRdec6MpQFYgsFxMCh3Zy6dwKrl14P6/PF
HbrMeLeZzpGXDoWGMZRh/laL50chc+PltgP/x4/m5d5MyM2nVkvjpJegqQR+TVG1YtHDTGkH1oBYfMDKNvIFoGtEHRC6R/Tk7S+L
zfJmnleaBJ0HujOiC4SXoigKPw8DQVnMeGOGwmP5wKSysWncHZS8BhjuvWmR2QI9ZXZ6r4j+frzGLSREwU1w67o0kXE2KbAOPAey
pAcEnLHCwlhuyD1b6p2qalcAL/G5MywxA5cTQJKcqFWEB9NBriZ8TJWoEQfnfPmbifnyMINEzne0HgYGGMmvJhY+bXb1bwpb//p3
wk0WF59uSy4GRZJzqU0QSdfmB13qaBVIqo00V31B4zWZWXM6ZGdnaU5UYq/mWtk9wiJ1pdARsKXlJ9tfo+eQM/cU3HkOzJGPBccp
tdpwUj9lOAy9EPMDs9irfy7fqZh3N3g5PMC2iv+fvrso0ELHCb3J36xmyaUWBskyjbAD7y9gGSsiAVi3GhdaqaTkWE6Ye0B0DkP6
MrxObWF4dVCK+z9GthG+c9osDyimQjHBy3ToSWYTeehrjz6H4ZtCM+iWtJ5N+6uk/2fx9Fcc02YakQD/1XTsJujPDnAdlurmtcWx
SM2bod+qLEMCsSvxqLzMwQmjH81UkrGr1vJDtgpwV/KoBIdcZLIoC6NtgrUAqvho04iVgXY7KSeZUjL90K68Xt2ZAO/txyGHwMSp
NxjDrQ3LEIQPFvmvo2HJuke8PiWnW0xvxPeMjrtKfCQCgOVAQWmMrJ/+5uhjEgIiV6t+B1xs81DNedP1NRh/9ILd+iEgOEMGe2wn
QYnXjdpZRFd4YXQ71HMcmoDw50LClYVZCEd37ZUsyIPaqC5qbu+c1Zp5gqgNkXZTxf3IGZN4DKw7H0pFADooHz5XlN25swCNlgp/
z4adW9IQYNZdAeKh+1PCSCY9d+T3QcmiGkPBmLYL+8WBlf3Q0Rc03rO3J3Tr2V7okDqNzlFe/5FkqG2P4IvJ8fBlspmG1S+e6NKG
hHzLn/yc1sg9IfMzpQNobbVsKRTHH6MFV6reKEmrzZUsxHhun8cmPTfkh1U1sS7nMRruqzGMnkd0o9WE71Km/JRTT2AUJ8v1dwiK
oDJOMNKVyzNJ5Xh6UhTqAf3OwDYnFmVxKegGIdZPbNYgg2Rs+NtZDRGafpztpQ1I/t2eyFG8+vHfUnf6UhLlBj880vKg3ISAYpn2
BJzpqMyYkgu/YAgZEM1lin3ubrlMQsoN0unrpg0CnxzcveE8GThp9dOWA1wVdNFv0buVvjnKm21tuze6HAo6mG69+eu4NgCA/ZFI
5Sxu3AjjsopXIr3nSxkkK4WHQZ0fC2TeokBzjpCCtAjdljyCLnMWbySvBWKFMjbfEUxpuxPEIPronbIWvrmbzpYCREB2jboaBMVJ
EDy/tAiaFGQPgrf1LOUd/9i/9Cbn6+sY4r7wakLPwYuwzPF2Sob2LZVGceTH4hfsgCjdNQu6musAqdtvilo91ddHj3wlfcqKQQez
1JHMD8lwgh+JYMQZO1PllufAxfyoO7oyEYLD5zrxczukTjnTPIsw0JNjZHvCA5+B7DVM/6sgHvrXO0my6TxlRI7XI+tUCaHo8S5K
Q9jzhSEgOwIsgrcyJs8rE8wsCfluJI0TKuDv3HsLoS86FEQISfFg/3YxLPj8mgPGBFg+qkYq3PYSwyeaDR3HWTpTMoy2FbdP1e3v
Nx22G9CxsDJUts4TbELdmTwXbjHtvMvc8wm11/4rOkmXFJgJvCp1tU/s65/eMAqefOS1vzlBlBBBobMsMY7DY5qyy/nQH4wmRlAz
HmLeQe+mG7it0MxwSra5D46UdpuHm5r7xdE6FCgzMCsEyCP45YQO8UlN5Ey5tYb1lcE+7Si1pVPpWey6Rb55AEHeiNYRBolrdCPj
fAp0/X43JeuUwwtct7wRdIIkgvY+VhBlHzTZQqp/hoxDMT3L4QMRS/CsgSvOO4kMvvq68Q1H4xCK63K1bUSnIlsnCs27sYWp0c15
zY1/96o9cq6VgWmeLtXkxwzdUenDczBFlc5PUKgJ8KAcDmIDUe1q8C3ZL5NV09/pF2dkOUHFaPiW+0VYLm8uxf12TH7MIHFfBTwN
0qjylqJ8ghjxduU1IVAGnUOIruse6H5ONXwrx7dHgWUnYhYYoyKoER4pzUPdanOO+bYmiKvWw1HKCgcEhrOWaA8MwUJGJX5akWOk
6g5zUBUogv4/fvAl9xI+KjTiqcpgGpLme8nPw4PmWGVXR3vO7LAm2vGj6iiKEWZ2IKX2anP9ATu4/ouNjCQJOGQDqIew4Jw3P6RI
1TG847a28AvzTStEhfR9UXN9kliMRa5xg09PBRvTKS3urWbtRPAIM50LPDXL6VwjA6WYKqbda9Q0HgpJFrdo9540pdCT34FR/tti
Fgm5SmK6VfBtk7nKGc7PKk9znxetJVC0q4/VtS9KU0lIDultijDevWNmdwMbuDzqelrEGNDjKjjWRRJ3tWK1/0eiNETifEz+0zKq
B/AxaDUjHv3D29iy3v2RCwu8wFNuA2b98rP7DQGxUQ/xKZxjEL1ItdWsrlYq74S+V0tjpoDP+mXCn9LN15p6wbpNAak1l+4yXwlE
w4tEjWjSVvYGd6ssNghnrYsfm8Azhwp4u0XVOtCixcQU1c9fJ+G0PAm15tsWz0mv5yTFw3/7yd7xEnxBNy8QcasEfC3oP9grWTvA
x1e6u0kOp/mf4ADpcrNqXDP/hkI0opGuy1Jk0/dnYRKh03D0EMWoELTwIDJQe+R8kwKc3TSAANnbdhNq+mvOMZ+72QnRc/D8Z5bS
Q+vwQUZx9+RUADlsxTd6OdBnNShl4o3JZimb2gSx06DXAaK67yjsGUctcmBX3lhB/Yc4VpIWamzG7jMayGjfq3LZ1xjVs4cds0QD
EsEk02udPpaJaUY46QC0tu7Ufp/fZan0wt3DCFTrSQc5EHRWCZf1gTR3gFV3cU0kE1/r5/sdQb1eFtrI+kjD9BzgT4Pq3CLlEGeN
19AOPWMVFep7Db7ndipkXhlLuA0foXy7x4N6ouFXUN72c8rHP1klVTwtzM5nY5frUGzWFY7CjQdPEhBDAfA3Z1uj/7mqrRJB6GPg
ZyQ0wdMEBT+z5/gr72hbyv5bbLipqt5s3v0Hvg1zFgS1ZcgtW4E0hv2LZCqPrZie9obRPoSqSvJLjbgHek6JfmCN60jhbQWmTy8t
mumlvHk2sYLMlEOPZ1JcXxbxjC8EN5hw+48YXQMAUUWN0AIvhHdhlfQdKZsGhYnSJqmUSNLkUW6pqlY6e8jGciABdBWgcBdYR9zU
JmDtO4YPzN6ZN2vx+S4585RF511Aiz3eHzpmBQ5LJrRGbFrdiL/LuAorQegRV8FWj8eaCJSSWlIUgJV84Gk3zkM+0pWffBKF/Kdd
1H8YIswJd/abR2InX96UX154cYVgtCBewy7QsPwpvhey3HiiRV7QLwcdNNuk93y5sNBgDMViuwiUcwdLK2Gx0zBFn8lJfNQq3Wsv
rPKkkmBqpZlam/BYm4cvW/rxv9kMRr8EDikxcht6TtNqTr/STL7FOIDooUlAkhcDAV40XZ934dYsShHjpmWy+NSXnIr/v+/Ls1KJ
P7kUNHnSVadKKn/BsP2xx/lXYL0N9WbpIyAym19Nxp2Aabl7ycTlT9RJ9tsLs1eYMX3Zq2eEwzC3lr5gdX6qKV9bzISCCIP1VIxP
v+a5ykxiR9SSOrUjfMGlfpL9g0iPX1iVuzBPtUTf2jg5x1iPsmGZVJeWzv6YGefQkb3nDcTv3Ofxrjx45/k8sSq1OWfcD0+syl9c
tYwJYvdQz0g7Ix2hHVvSz7p4iX5556JhSISu3CnInUAhm1nCEA6yQhwaCxx0TZK5i/S+qqICTtCQO5lheRFVBIDQayMBAHA8wIlf
nQTA2WG2cRoHlwKtg3crlImc2uOYLBD4c26npEmJa+HR4R3FB5cpCAL3yRDeUw5UXeR7AR4Cr9QTS/jSB3r0UWCbPUSL0T+PttCO
/CLTval4/wCNFi/77JlkecYcyRVrJ/kQNVIxEysPnoa1OXFYrXyw64E+D86hZpMIDJ8if/0tnWKsnFqEXjZT2/GOTBSfaxQnGpTH
sk92gqlNKEJp11Es3ubTUYaOs5B8QnTmmxEcAUJTGpLiuKlMnmMW1mJcQAuTcbB2wSYajzTvRBuhGES0HVwrt6q3VtAvv7xqKlb3
u0Rk26YqTks7WVpauxqe7pys3DnB7063yV0Foea8MUgHMzegN03GXN5v0a3TLdVo6P7xb+HHXzf5CEzVHyK7OQm2sTGdtWGtF1kT
VQLWwm3NrtVmYXo79//XRmmXtYRctLJrtk0JpY5dT6ZWMmT+2xRK/RLjHM/jrsark3ABXMzMrKDScC+y9lkYgFtKUC1Ki0YjIErE
i69ewsQVW2gmLBdiemwyILavSVByolrSMrGY6cGMgEwEblZBDsapVGWXCkXKiEKs8ZpRkA2VRktyEMobZNYMCo7XIQXcKBc3Lb87
dKZoQ+8oeoJpuJ3TwFCUp8sRU0gbXG1Lru9TudL1bqAdx5I++Pe6/pBLSX55m763JFyIK89bHU0xkonSyop62tRk7YY6lQVTTDtX
BvBcWL1Mj1GAGWJxkRYHCxGgMaHa+zkLPTLLrhBUTxVFebxB9J1UhMBenS8kdkqbtM/atUqvPdSlspAWGTsZ2zHaOOIm8D6cz4Cz
8/OAmFr4cJyUq2tTSDzUs/24Uw7tqZoOa5COO1eZ0bzyrxH17BkxAmBeEs34wpZKEEVIcQ5qhRZf6rkOExOF63mW4oh8sjkASDxS
bnwUWy7bkXzZiBzICdjj/o7V5HD9vGnMjggbOSnC8l+nngasHWAMJdPAivFKGK8R8adeKp9vS1xbalrK9UeDVNjdFSfVt32AwF1b
NOdJmaNEMzxy4b2aDp0An5xaW2fkSF1+bZnJmprQzxMKICc/sYxYcjtP9rtMEf8QUT1dSHDu5J3PNVAqGlyxYApf/V/uycLBgYs8
h1M8nQ4L70eOVVYaHA22vybSoPl0oSIBUeD8Pf8Lc4u7urBsgz14JpGvqUyM+VKbnvans/MxG6Z4hzro0YC9pinFcrbCH7oaKZiB
Xhr/3T2r1KKMfx/GQIOTbU1iWND4ZfOxnubN5n5SWD47uqt+670Xl37uQkI82ksqR8pXNYzcOFr4WHE0YBzz4HQgJKn5ypSpnBOv
WUo+ArHQIULPHZ3cHsOsyWpx0XmNWHIjDTvWYXtsIomj64OIVJpQ1Y22H28o5uX08TXOteU4Vw5Wk+6OZijJyp/B+VeINXfdh5ua
E7oZKhTUYKOLQsP2JkklwBaNy5bTgndiW8qKzWWgXfLbUqWRLMULmpCD3du45TEJrzBbxn1uf62qeFz1MbhG2896Ilk2zC9fyKd7
OAaML/hAB9D5M377H/9fL3KELVikTgiQjYX2LuPPBYk4Tglkb8BwnqqiAoaX+Lx3QYeZeN/xklhvvfI4SD2UKRsfzrraMzi6hW0R
RLQ4qv1IhaMv5s0MV2iQ7vTbg97fG3IyZo5kNt+zKvPtGBXQBy8xSkr0gr6DAtj1PKdwJl1BjVCAxtaBvHAgZNd5DqvjnDOxmoBI
iDqjNJCbiuaoYkx0t7sr+mUBnxNsft30uUMysOOEAwlqSvDMmS9adxkREAFV/yXKayJCHlM/QMlu3n8WaGU8Eq0xLfFc6JN1o8/K
cwSi7ndmYOxbFgj6ptHINuI8j3YDzrBAlytirxd37S5QP2NzTD4ekwKU9F6pB6zPK9eZMdDbJt595Jj5KOVFBbTAFBiP+xasb/B7
8ZVF9JyZEAvg2pEsDFIFq1g2Yu9NZHAx2OISQAK82A53BKqvmbRwmfkqWCkra//vXNrkGFThAgMDdx3sJjBWW6iHB41JqbsorTuZ
MYUiLuGHaPF5U886rtLgNGIAGRza+ckCx2a3QiR1qafRIyDt3DXBGLmcP54QS8Qsiv0LlfonvGTN0AuSsA6PohG7hGF+GneIFbzl
iurfWUNigz4rGM9OuMXPpNlDfI9bXzafeuRcixisY5LSBUIRfGXxF85QELpkf3YBeaDos9RwIHA2ywteSArfoGHQWeICGqeTXIg1
os/cpvaRdrZtT7hMdeVUp8tmgVC3zhbiLLTFETSlC08XFGTvcbTT0jxMk0kHtQmqv5KjDNYjnLQXEGR40KM+wb6NR7qQ+i+vTCfL
MXvy1eSYbs4rOytoXo/2Xo4C9lN6/llg7rZThve3NY549MY2biiiKST+jWKa8yc3JZmvqQWQ0upc4HLUD7OSgzw07pgXlahMU0UK
aQqmMtSJKYPj1MKzZI09TPQexxlp3CtN2qjB0aX7lMnvpydw7b9n2dC71zGI5gPJe8DyW1g+CeLbpf6x5t4kgt3M6SQYscOSbKQn
TnIXpf44ulFKi+m6rfuiqpA+oCjpWf00IiINpl2DQXFbF/WXSWgHH1QsS1n1LME5SX8f4FTCELJWAUkMO8RyTDZY/ssPPtdAfvRL
s3ZiUFMwN7fq//WdHJc7ZFDgE7UZYckKkvasd20tQcFSm4N2EBtbxfdINLFaW+pOGzd8HHOSEpnd9jNtaXyMdvdokXKUxEnpnqxe
av9M0UBHSoRzUigE64s1huZyXIWJPTYmtE2aS8lPxAl0oAGXzkU7vG3PsIcX4dGEgfSJ88EIn3fJ9Iit6ulWOOdw6n6izBdymy4G
MD+0TOKfCBOX0kdR4UMxiki3IOnTRUbGHSILiztXi0IabL3VElgF7yalWW1wQTv9YmpGyySMy9MOjOjAaHxfKr8DwJlCXyEvOV4/
gZ2GOh+LpcWf3uqkMppJfnx6E/GnRSV2g6kjFxcG8jIqla27Fdxx+o8uCLaH5g0QqjeUJGPl3MuRxf8/l3IGuUNAUfU6qdzKHpme
jsOrbC5yl9VPhG80/5EJ+w5YqfbCDILB9BHllc5WQ2y4w9X1e6oC9xXxUdQ1Tibp1UOuS0C1kkkNiipLKLO57OZCz217c9FcgyfE
p+7gd9RCDo3vXK3mknFfTGsAEb5laT8C2GqCvJpMY5+wJ5yBZm7KMRIGHuuodaVPdVPAVwXsdKErkskEbwlgv9F7gCTXV1f8g3dT
Tfj6NHHizH0Hm+oMGAgAOjxbAXEOFztVPjIl2sQ8JCbMFJhPSn3G/COqc8EY8LQXG2ecE3FAEZntODm3TfpwAn4o1LLWiY9I//Iq
FqEzGle7QEnIQCAdC18/JmLVa8kh2TSek8oMqfcf8+24vYy5NtHn6i53L9vsHZJv7hORzaQ/c1f9JuSdo+jVTGfDUMYKT1lYnTgp
FUancwUe+3nHljPVfSxhzQX6b/5ySM6HmZEZvGpYh3qjCR4B9gBBjxdraq77v9eDUNlzHpwoJP/9H7H9fSB/X22XFfyYN+dHYiIx
MXnz0N/+Re1vE7UrZ4gxoPUEcpBXBryXwwpAdi8FFsD+Bvh2NNXQVjxyqRIMuu08UcugDEGZABS9PoWHggAEdG55PIF58aXmXx3p
TbuWkkQedBZMhueiO8pMsN7L1/HxmeDAy64u/PB8T5Xm044THgE1ulteONunCBZrpHy2jByPb6b+HjkXDH+Q6YUWP7LmUPiREP83
sihjcsuhS2gusXWx3i1rNmOLskLZJYNLmtj6nulQy7SzHq2ZjRLTAbLb9waZK35RJne4sG9CLxLYNxECUqSQwlD3SyVIajnKDzua
+tGN8SaYUkOsgpfsjkT7CXE7+i2SG2fII16iS/bSYot7dOm0EetxQwTbS1BsSUMcxd4H9CKrrhkHE+l7QTzINitKypdC+zmFb2b+
vHxp6Ztk6/xx7PS6iJ5AXfOKBi86gRPizMLpR50Eje91x/Hf9lyiSROoiIkWLiWmscubqtR7sBZH3UMmshzflgUKNZ+GoGELKapT
uKYNGiPUK5mhCPWN5XIbC1iL/xTK1O56WKU6nnPQT0Oherfjc+foNMeXFmZZ6PkJK1IoP3HQK0QflhxA/FhQ/PELm2ZBUiBLyDJ5
HTJ7kdwZoe/VxAoa8ylnyyDIADxA3JeEXqRITg+5yuvgxNwdaTw0b8QQuunZKRMAt5wnVxbjaLQBc+sPPXrYS26zJCQ2FBGK42G8
OkGtWml5podCKogWDlVb2xMcRVTwrjF0RkEliIvC7YSANXnFRx+Ffx21DNB46tXBD0e9fwPcYaqwv0mip0CnTd6D6AjxKT654Yq3
e7loNQ79y60824Dc27RcxtMToItxY/SovR80v8EZdaIJqwt2mXopHzMSG+RZiPa+y7H7uc+gQfqzj1j7eiQ+eOpq2HF/pDXd+p3I
+RHJZxSVCkd7K+txgBxCaS1l2/s86DFYvXnfmqeV6KTU9a57MRNUlAG3jmNcqzWG2eBjQK5mriAusAvOy2Txb/1nG7xVV3fC0a0Y
4YzNu+D4ryYFL4ZYbTNQTiZZSJ7tkQ0rpD+98F/O2Tm25ElXwaoC3ldm0a09G8UGthlE/wP/P133stvJjmXcU4Cekbqoq+65PFOO
RwFnLrbeV4PLAfIpt0+U4MUeaMnCWdd9jg3EagTEAFoMOgDc4kYozyD8FTPRPslEmuBXKcd2ruc2JstmOHE8dNX16jLlFfi9EOpy
AjrmmoauInbeIciXSkyqgg3aoOMRVMRgUc8ELHgITzo+yxY3aBLV+zwJ8Z1VMjwfVXtBdaJTKOZfKARKMuTSkkuMmC0SvQH6LCCD
aO8xAh9tyDuqrXYI/Ges35a2rH5cTbFVZo1voGBVKPT6E/YJ9P0BrI6Y6ZM++erRaGf0/OinE2ypg9hgtlKIRtWK59vBFujvTftP
PqY4BKexN/i5ofnZGYa2dFRIQbeQ3+9QsM6SNFOb4XrNc+hNcfyx0pSRM0tpvdmL81JbSDkJohXgPVccMAHFZeZHA/Ope8SRlqgM
soTH82VECrgNWrJ6FTTOdMSM8JWxC+ppGB5IFRKd66jbG7aWyEB5ZkdGGe0nYom5n8b1YUWRrUQzySapgqGNQztSoKQZUsrmZHGh
Zzf/oMXOEqDilU8yPyq0HLl6ieFAAut8KuL03VtSfj/FvwgBxritnbI5RTHos/G+GCN9LOHGROpukpQZ5c9Sh6OANrzrGf1tyaG9
eF+5m3uz1eXu+bcdIvod12BeaqtMBp1F15QuSbAI7J9j+iqQ6+2TS6nlkIOQaGU/w2hp8ZOOmiNv+ruJpSfVcqTEq7QNTEsUU5vI
3s/nP/FEKkcDhYHHq2+fFURZzO3NgRDVfKC5KVFvQW157ONXS1WDpbxLYkKDxjmpwVB7/aLlZ7AHpezFyWkXs0oRQGtHFgbaDr39
wLITFFp95HNp7SYREILF2YfLpcUKcTgIstd5mDAPmGCtObtLMczrcDGWWoFKTHhEq4tl47hnWSAIA1/zmx+wppmPBq4FbHH6XhB+
X/8osAzZGW6KAQunv6uzBt0N5sUpQVlsYWsGdHquPpQLgGv3PhHc9ADz7TlweJqCipxJMTEjS1yan3qQmMoNR0QLKIGqJRfpAJta
C9chlkxKXAFiScxsnOGMx1cUHLPDITUbNdO9gYIlYy1+KIZJdLOxfjSGZR6BX1FkPtRy7qqiSivi7T4vwxls1wI1ZEuHgrWYzmQZ
AoSPwlpKktVZfmZLmCwst86xPvs4kFS5jodWjk2c2fOKCi1uUHD1veMzUHtA+ZZAKPUVT2aKMYNup/Bo+wXO2qZFNc33tJWNZntX
FfCPz8yQRw37FrOA5u+pZFBksHYPKOHN8qBKkTK+jQJpw5j/UlU05kxSL9bshifUuEIJCpJ4hH/RdVYI6SlcsvPJkcCeBsT3k9fQ
Q3VzAkHZLqAv/MdCGNzurPLqSJ/iGIXGJTlTAhxAZ5hUiT9V0PjFx+P9L6RQv29cmZQxXyx817WHbgK6ckzWsrb0QKHcH9JVzxKT
6MJeOBFvqsDVlaJgsEnWC/6RjYRMfPPhNMZpPafnXqPEwntmdD/ZSFANVGrB9239yPLc1ZHoM0auxSvejLJergwGpSLC1M6opFZ9
5Pk5T8OOuZhfy2KbSQ3mL7GxfwnA887poOVWhIAKt1QkYxeN4W7yLgiNhngwhN9s8EvPMUUNnxdIYOUDEzRBwHfgPGOhfAA0yzaM
8EsLLoKfauikTlfWXV1pBkh7JTzQ7WnPFNqvisyO0m1RnKnVHQJu4I1JC/b/wzT2KFObkNauUj1R9KKyDyk3Z5ZLgpmvYqX4oC0k
XYqeKK5Y86mguwYRW3feww1uYbtASDJrOjnUlC2Ey6jzr/4hilU0hzcjU1ctaXDqkB2UeRD9fMgGG8hAkpBPbf2kokbb8V+VW5sU
IyZ8sekcRULNJe5DVA/QfMvQeB9TJRQ2H0I4SsqN6K005iENhjaEjgCOClFDXVcTyovy+dALQebcvNanBxGAL2LmBTEmCIQK9igO
VwlSK5UmxP6IXcPIEla50yK0bfRZPNHfLdUKvdZE0c+q7weX8IZ9Qq1O1g6CGwGnbVZh2CGL5BuN5T+xnkv4O8URFn94JJZXBEsA
yPoEYho7nurh7krsqXAtP7AJvQwrqHd860/Hl3Z1PiNS1mjwnfsr1KOlAjOe4Ms9J0/aTwfvEYfNi3fkvMY/9kSgGYtNGF2d3XYf
gloq3LU9jYwn3/4WQta0b8f01kLmRUFGnkl6K4Qe8Te7I1WD2HCpfBSjyUMtbE7qOSYrh0ewv3l+cQD7lYPTIQTiMfoZXZ/gaY5H
iT11/JZF3M01wKUcn8S95ZxDfiYWbm/EKZIleWRaJwk3cjCArM2eIGLX8AiKqTM93rhOu0x3FI7fY0xc5tWanp3NoZMMUeu2QMuy
q3TdnfpKMv5TyJg7IZi4bKbmgbdNMhrn/+6Fe82M0gItx6Qy38kmJebaFfOLxMlU3nyEwMx7+BnBPGin0FyrSYBMyGivHZOvrZPz
NoVWZdKKpbKjhND3xUaQvN+cZKCAtb1LOWIp1SrLQaW1G1505Jng+E3/nR6LGdnWKDQPK2sFRMh3lwdm5ZUmYHTvnUzQWnnb1qFB
Na/t7XIf22vEucJtTD2xphBJdxrQtrt7N/aP+OdUv8+5QLxHR0VBvT+6T6O4iQv5dwQeEL51GoTfsBpX4+C5KgP3d6DLoYVfSKxl
8lztCB8zz+CRT4LMkKAB9L80ULNry0t7/0s6TS6i/uafRgB9h/kZ6AQZPjtMR7uYOIdxfzcRc6pMDLrlvJRZQ/Rj7sL5l7uNqH+S
0Raa+m706tNW2OJD5LFmlNpGgkxGWLQGHWKJs5Ou0bkjUUb8G8SK67MLBPEJCpsDCeX+QtV5qa8zHlrAwx74vr9Gwn9TFTpoP5Lg
+rK0Dcwjay74N2yAhk6NR4iV7q5Psnv5oBPctDMehXff6acoCXBAibxEkASQEGCqs9qd22Z2Y6e1DivE02xni501lcW+ovJIKM68
YcpmTMNK+agEQgb1bLaAYseM9JIgbmHAymxIdH93o/1JbR6Wu0/Mi9boAI553FhveZ867XLO3vG7/V1qjQz5HKcoug1q3S8R1a8b
OPEQuNxK7gGKodt5LIV9hLi1ksPavlI/ILzMUqF12eG2FNHRllzTDROOS8SoTAT9vKBKSmeCeoMRWqEdP2gfTAVdSbiFLXkuJmOX
l58LC7T3/a59XQ2Y5cem1mQPuD9MzNKCqXRSt5obgZA8YR4BBcE7WKi7lZRbi5cfJ0xZzdQeBCFaB6oIFPOV7XAnH0fkY5L7fcRY
N4YstSBuUcbmi44Fm7JvlP5i/OQkjmu1qaRQmt1tpRZfz5Euu/N11xuXJg+PIAyQBoITLQQPvghNGwgsGRzIiyfHBrqpkA3KNfRE
16NajU5rANQmjcMX/VBK9leCsouNqP8iv8osA12hBbf5tdYOarJp5RopKAYRkvAIcP+1LpfBMlXe3t2mFeoPKVI4GGuxCecgvZ/B
Pr/DOw+Ln/ezUFNa3rTK4Cl8/5lopr+4/1aRBwNzpyPPs6MguDbRPaR3CRqiS2nzIetuC7mwW2eHAgb0lIlaUkjApLmWK6GrFBkJ
dePZ2FOWRreSihZD2FAsNMoNi0SPRX3+ILgmA9LX5XtlEXA7UKDoPyPZ/cVBikdCVInNXpJLkNWbE85Amgaav67X9cSTGdYO5Mkv
lp1RVeklNfKDxNHCMoOUfI/Ut9LIsc2X+gER5c4i4+iAxfwyVrxWg/BLqVacfFuxVOjufcqwBJ8V8jFCebF6yZDR4b24OJp1mRI4
bY6X29Iq0XJGov7LHX7851IcOOtc5NlWD2K2J6ZBfrwVyIVsmlyK5BVZx/wpH78DNVfhyXWTEsEfgTjFCZM2ek1aZECVlZe7KMCo
atmUjCPmmrvTynbjkqF9kBmrnqkTxHQEhGO7gGzDvWlVQLUh1ugtg5wGv0kR1wYl9dKesd7xz2NWBNv3qerier2BULIXvcqBQ09N
g8KXXWH92W8OOqv8zJ+WbRWIdFvJjaRmNiB43dtNlCLWG6fXCqaGBiP2AXPEpU2cGegM9i/sZ1FRcDTTeY3dnr1VJT4eoUvQvr/A
hZbLPihvZeltsoD7wzaIu6yf/WKU2JeU4S4sEchOExXvQaUZboAoN+tOvc2iLhihCJN6XjNM0wpCEaeiSjCWXKcMHqqVGBRzTeDR
BHIaLDjuykubbW9WFTwlfCL2PS+LED2f2u6a95IzDDeNwQXPtggGX5uLhWERyTQ+G4vPvZKGYQtJ/1l2HkmSz3Ff5UsqsXcwwPZS
NO21J2ds/22I6iuXbjOr3Ujw8S5/3CHfQNmU0+CMcn8KpSCgs60/Km+VvY8rQBx6WEFgDi3081mQB48IaAHg2+rq3x5x/f6z2NYQ
JgUFECSWzm8LUoPPYGgBc7W9Cp1LhTbPYqthGjY8+4LIgcRXIyqLONESVEzen87Vt6IZpRAKhE2PXotXU/HZ0f19Wz5IQKF23P50
QUN0mnh6IgiCactH2PLvVLYNYs6LMoUTazjcKsU0gKyjhEmzunm+z1Y8/w6SJPEsI0cRifOCfg2Pi2KX8aadygLvs7fdL+fwP6qu
zcQAuHv7XWyveN24iimIfy7gWmFdlEOk2A3agBLb2NKo4N7xn7r0Zmk6EFSuR6C2/Sy1IM/+0Pphoq8T4LCZCXwDhS1P7/bOsPC7
gxSl+VeSss4NJgxMAq/hwuwsbNwJ3V0TuAxWS32rGH1CHuWXVZp2WR8omfunmzsQzptNXPbnX/d6e3ScIDsYL7fjjxfgWrMTGy4n
y63ECFTGmyUVkPfcfuw5MJMcesJwz7MBzMogT0qwYJgJfAcXV+LcYC47MqMYGzyC4Lvpoyx7BU1yK+7mPGFDhR1QtB+eGxcYygWd
ENc6jMpk1oQk4iEEP0BHrheOVHlnvDqxlLgCr9KIvaYnio8Njh0Z7VPO5UzMXeBP4tHOa1hlZG6K8k7TrOhaGolxaKBRTnR+r4y3
4YVPzn5My9BQ44+EineAk8KqIQ6p0ckXmk4w8yX/4Xo/Wt9sjejZzCE0Kuip6aM+FBsMDnR36U8V/ZXovBca0DDlh9S9Uo82miEs
nFO0RQsIkgpAlAGyhgE1RErh8URnhaPrnR6DjIzB68DhCekHfvdHyVM19W3D31Eh//MokMswd4wzbaFRaArPKSgo8nUrCVKvsi0l
6dBfF2hzsWWRErk5n770BrDQ1W+xifwZtZJ0HFOiqp+5sg37tXb4HZnz9+dN6ICH0mwsWGXGJgQypOwli94Dz4S3uP82+f4qArmE
GsBzkgIp5uI37s5r5sW6O254mwM1o8U58wof96t+rEQM8ew2mLGSIoinCtuf+WbELBqUX/3xwM81EEVp15LJ4DEadGIL1V5lC53V
h+XojcRthoCYqjeT9W8IKwjr+hYwc0zTYdkRJn0UJq7wcjEsj836TFpOMiKZGHRqilOsAX6cxsuY777opXiVOOKvNSzEiv05ll7S
3a+Lu6R5pR7WQavfrrbUkrIZuFdCcwHXHoklaKOAnQw2E8C9/DsdJx/ioshk6/xsmx26ZJuyTXQUmZR/qEhiODcQLxxKbP37cdwK
oz4ClT3Khtu0MgCGKAvto+B4uqMthSCM91NllFK0I4v2/JThtrBQ7/OSN1SzFI+/VWegsT/8RdOxqrWaulx4RkjUzC7TRWkggTyA
UTkXPuGtaR0Vd7SOosfRE2Qoz34P0ClCXARSKYHT3ZPTto6UEqB1/O62Im7NUWAKp6exuWXgXkr2WJstSY+Dtnwvs6Uos23DvE+V
Sxmgt6m+y+7waE99/EyS1ral1+lkbafuu+wIzm3iZhPHSTYY2XP0TXn7G99Pg+haDqKlmu4pGuTvdypgOvcC8xQuy5HgmaV1bZjV
obPeQSe46AicjHI4UdyR3DBNTXX0j/YJyEEb4dZOrB8x6l9nLuHT5BHJs/dQNPTsy+PZctfjooPyFw8jfsxr2EhilGTMYtCRnLYy
JehfYxubySvsZz4oolpVbdhDf6cZz/I4FfK5HYxxwukIVcSpjGBbRHADYQz7xq1SRuvOx2wDBdkwuHB5bA56/5lWlWb+e17W9zOx
SS4l0VEIeRtSKlT9LSO7VI3+37v/IsvQIjDzwp9zssKBBmDNgS43Vdet81X7Gi/9vLmndYM9cHQmxiAJxJYnRh/RX4DkPRRw9lKE
J997LkDxu8MkoXTkXfxXPrTbWhh3EzkmIM7MVl8E5PcUr8hLsFXLDcELdUMUMu1ARcKfUW+DmswQLEpERV+tX0apX39GrfYobEWp
CPj6/xEsivhGvATlI4Jp7xC4jYLI9vH+jAvmyb+IBrq1pmN9cs6YsaJPbxJJGhbvs6rD6wnQFPnnkTyH6841+qwr7I7/CHD2auHe
mS3lFfx+BoIBwyZtsLWNp1QRtDaJvF/7d0/hCLW7wzP7Nettb2s74Mbd8jSRfV5XQaR9RQy9Mg+pe12ptMVb9S3tpUW7QFT9AEWA
u7qvZeZ1450RyCkVBGv3EqPIAaI/GzB4qvZt0mywUr9azgd1+Mm7GfJUOhRxvUdKcBa9Gq4efOpapEksLr+tKyqX1mqhQWIGkHpt
wpHY/XKbNP8CAczP3vdfMa9E+BbaW9PtCzATcvHvPsdKylcyxw/Z6Rwc/Bhccib4oawDVZIJltvrZZXVbnjv2AxOS5u7avDKvEQY
7pbVKd9tVtiGD7+fiBS5gPvo51mkOy9kyQfOjIKGQy3t4iw5N6AuleFzJkxmDov32SG/Ev5cbQayjwvLTGE/MMAw92fYSjp56wmP
3S3ZVY2kqolA98dIn2Z5tUJooIeejhrCxXGnabNTk3u4bkMX2PCen+TtTpdR2c69JYuzEP3cwcLzytjm4DfzOuTw8hZY+UutbeeU
hy7omkJz1vQTt0jfp34NosmvlrfYx0K4avsiV1fhSW9IYThiETOltYAn7wHxBoGcqwYsuO49Cl+FjGfoky1a/MLreyUYmLmdSGKu
kP0toKs08piG6lzdFJBQMexUglsckBWrfDPTSW1VxyhYqwjSeOAcoVH/e4vSCPgYUe2+YGWXs2bif0saZs1MAnSzVkzMFpjwjp2a
mJDUZ85UtKga/ZFS877hcTSKjf1Io4loI5z1jfatFPbLVioMpQeaNY+kPvKfxqM2VATVRKtRS8aecT1cevqh2So6e5JK+PzxT3r5
iGjlQ/H63+n+GT6qSqDSHeaRhXEi5AeyyXc+Sn6vMg61hIV5W1HRR3odGg2eILqb0/UqVny8rD0p5tz2+niadhXomdSirGoqwoD9
oyNdFqwS147IoEIhQVl8D9uVFK79BPbBZmg+efUxwphzoz3WEL+CTv+Lg0ytPu7Vc7bV+jnndznQ8/hPOhqGTwgOMu2vvcavuhAk
iPZYKMwf+grkWsU+QOpgwUQo/Y+862iy2yIbpEbWb5/2uMXv/V9HDzvVr2DePh2rAWK3P8BjwSE6DLQIUQzW0/av1eYmWXzajxBD
91wowZiKTeLmWxiQVzEMhz2cLvcQV+TBT25qhlp1mryiE4uqK0ErrdRu+rvaArIR9hqqG/xkag+3dKTFs3vJhj91LR3yvdrRunHx
nonrTSR2draG+1pTkPpAMIG8s8abnC3xFcvMAaORmCnJfQeDXqfrmKUoSkk6DTRBVQ+yuYKTuAu2UHGKdOMch01KcDYEbozm/lGJ
75UFVXvMgNyzGtLhT1TxU2qtYg7x/jw/bKsX2hBGH6olkdJVIrBYfVdg4g1kUUIA7jR5KAoFDNDwohg7BCSakiN4E671yerqZfe1
LXWUnQ1pfYWdc0sJdM9cAlNYrvWducrOlSnzj8yE8Mzz8cg+qDtRzERxI/NHI4QpZhilR/1s1hgi6gGYduspOduhpgYHV6WVtLON
VZetlHbmvX8jnztBhzbVionLS5nSHvVu99Je8AhfkdUbNDxh6MpyxeN97Egx6j7L8f1h4RoY0mqBXIaxZFUmUyjCEseQR93HParJ
ZNEQY0eCrdiiQEa9dEdcZpUgUfx8XGyQORCUAjagNW4NPPcfHxQ0XAT27av7QxmuDVmvICDh4Bv8jW09jXg7cS3U1gvsh3BBH5/f
BMZK1v2qTafzTrWWCu7CdD9Ksq3D+aOiDoJfkEmOByu2MvEI+cKFNemVuJdfV4utOhJs+b+QPKQthMmk6BRl4TPDWUaUgn79H6GP
y5hZwiHczcxqzH+8ImAoiAaEUBIWutEz29741CP/zxgnMIXf6XlrpB+I9NWxBKfLJTCM4n3Ad1fRcVk0zkLF9BYnBbD4ejhCO+k0
t6Si8Uor//aHJBzVeSf+9Bi2/Tl3ztwAt4QkLDoxHXE4XWBjHiCT1pz3dy1BhT41CUeLGnWWIRmYMMa4UERLuP+6qKyG+s8Hmj5L
IpZA91o+QJ5wZEhiVz4xKmDvmhf/XVAGtQ628Kw1P2BPpYRdRcvFrxjglZKpII2ecXwf9t4nzRd99NKOxFxJNc7na5xjcHSYO4Px
IpjPdsGtfPpCOlAuNT05k+m/cXzs4wYTmZK18RWWr6I18bc9eMhbss1icqlCtUdD0bJtghyb2IHYSayxN9/qbstLz8+FqB+ClJoZ
0OB8QA7Gn4T9XP+9CHuqAmSWGUNN/EHTY9B4a5DXqrPO3UsmzWYbcjXGOqr/1QTRiZ3y6ISuwS3kHJ+Csg+LZkxkWizbA8k7i+k2
qk1riUY41AGw5wFNegu7W+Qy6N/Cl1BdlGDVDPR9Vs9+/skYM7FPg9rryR43BaDCK9xdVJQAu34Y5MLAzdOUZIRBxc/SKYq5fGg2
nvDuJ79ti0kHdwy/VQgjOet3w4lEQZPQ2ABOlkYlEmfbZKxOrbyVGYmy9RWzu8Z26R2mcKX5bd8VgWRBG8HMntAaaGeiU23bWsHm
VM1AK+HkVkKi6XAxOF41KLKVL5Upy1bjjtkqPH89FZu6xXur8Ab3E7xfVTVqGOr1jJYYRvb7iAQcsqBxrkfVKDg7W/Q3ApbVlAtw
N/9mkVTIGa6dxoRVJ7P/eUQcSfHwZWoRp4ULF3NEdv2r/I+/jg5kb8/bkWPpf2p9srygdPhad2lrvWFz7Apkc9N6F8XNmITE1bsR
W0qJXKTGKX6tAD8sZ2OoxOcbX5xOM0rzpfDUzxmFl47TFTDTlTko2fdQGEoYb0ZW3AOFpx+j0Qs160WBf85h4jlXzVqTeDSHvUT+
i582ULD9nv5j33uk61IE4rFihjU9bQC5DL4Gvl11vjEp61O4AV5Qiv4QckuMz2A3PQZRubSKinsPjQKNEkU9q22HQQqkgW1UO4gK
LsroWgeq1nf3Kdde1d8zC7jLpeLgqCQF/0FKGDBqylrbvwUlZb4Qj5ZoWHiLwAsGjA6dPdswQZKtZdPadyGy57/0S1TOX6KNJmFU
LJLYk2IOWSVoekkZ6WVijUfacCQfU5e2/QubtGLdhvBr3Jrd4rn8kO9PL8LN/JSJ22FK3F1y5oQOYgM1lS5cV2NNxBcDiuqKv2gG
/QPt86ZnL0G8wYHzI/vfQIOwzrbrQcCeKbf1k5h2xVsRsOXnzVxogxO7GNEEcUST+pdfZX4Ddh9Kl8O2LqmhmzWFR/NweNLuOePS
X9/Aj7E4/dpX+eFsPiXuv34UJxPXXH9U+XHhhJ4FJVLQhUIb+DveVGBaumscKhkEPOLflbPccLFtr8KyzZ9nIcUCQ1/s5e8TOswp
5hW8lYuPbJ5k/juKOIPk6qKiLWcTwkZx7SHIHpZfgVpefU8OEmqKQOo+BdnIYx+dS2WYvw1PiSnswz7ml1Zvr4n1GTmEDbHnEE9k
aWJd+ijwkp0KsC12cFAph8kByuFTaUn1FZ//kVGNBXHb5A96ThKE3Fe5D8hBxcffN64JcMFiJUBBOoTM8e3zccl8UFCVrKxFry1F
+3lhO8vIGMWer0avkUptju9JFcnTG4iNzTWvKyHU2qdgFKKR4eb2W8tcYtg/5czJ862Oxd1rlnZMyOVGnPr9OmrhTRTso0ZXO5yl
LqOTHCPzgUFvL99O299MZKgsmgzAJQWcGv8QDTo2omLYbJtYCFktwOjd4Nt0T0tLHUgKIrPBQWos0q+kwKTnL4fhUGgh9k8lrki/
BCg5XUEb7QtveEU8ks6Im/Rt3gGctlsGT/D5XxxBDKdr5IYorm0fDFfg8HTeZ9OrF3/WBqMecf6QHRCLGG1gmv3cxjpfkRaQSkZH
XPMyHMVtvRVhoahRzDFYCywAA1fpXkU8JlczyNON7gd8CaEdobAOV0F6Al233djn1brxso8J9eO0LSizNBJtiZBC8QU6St1Aqi86
jmLUk8itSADXTRCPvM8Jo7eItgsXKtIaUJ+9EqptFMJSgUO5GNOWC+8YeaGWgNdBD6a1/PeJJE7TlJ6lXIDQWc/zcspM3kUDAi/F
3ZEf1/DQyKB2S+FAJa3wIrK17GCYv69A+aTjpFhgrKk2Mn/k5f6vA6dYsiR8ca5dafA/dDma3IBp3UHGE26FMlptRo29nbzY4PnV
UHvZnifg4vVMML2LWHyR6vChj+a9NUcMdEu5OBKUoVx4ecbnqyJkRjb8Tv/iAtKZn6BpPyWgLaDaLowfq5YPSvakPpkjocNri7WX
Xg4+LxlCGkEVpcpZWbBJJWDIbgSD54sJ+9XJfnHVMbIwFGEmnSV3Zt9DeS2lCWStGUQb0YDxbBhENOc9XPzR8LHYUmr01Bd2WSfK
kyxgiSxsf3Jr9qrOkkfYmPssaVuDTKa5epouUyhskeQ5b9VoDqJP94hLa+4cKctbhf2Xzi15v+griGHotPB19fQbeFBBT9rK1bS3
vHZuQl+x6ayAQeV/X+GLlTmC2ej7nyDMmYhcSKKK7uPzcEoRanN2AyS1vd+WOCT2/p6ypCT3aWBTuYsPz3Jf0XGtsBl4AVMfuSkV
/C9V6+In6SSDAvggOQ5OJwbHz/SrnQ+8NcILeOw5dubsDXvdIdCyVp/SY1hYV4wRNZBiFof4ps9OYYkT75wvN0JWjSX+3hZpNbXx
Lfy6nlpgttU8oIQfeW/rXd+wmpEUtQgffj80dLTwCgy4VQ8a6lLRVbRpdtYgTo7Pt2RELGKVpF3XdmDCR5p2hUG3V3a4hp01v7Rv
KMYzdFyE+zQcsXtZ4nUHUk990JmiurKDADmUwayr0rvPrqYb4Rovgt/4+Zal1Jz6bR1xiWNUWw843/RjIOASMb7hU7H5P0rrmk5p
VZ9Nazk0EJlChia2QI+uzOgDUwLrTvMO4IBuTqQJU1cqE71/2XrT0W/hB0PBMV6e+n7wbplTYey97JWWSX2+WIiDT6Js6ZxfHt8P
bXks2Yjiwl9N5QUo6RoarazH11EpBTwZ43EpikioyiwL+AqB9pRrY2a4pN8CByoRDsdv46dVTCeVRUelAyyRO+HF1hz9VWw8q/m9
z1JNqQQI5TbibkHppuXQq1SnWHPLK5aboTQOnkV1sG/YGqpCK6OcOcLynEtHTUlwAgbuibzQKDXdpnhM6rz+iwvpGCzxLvOuPI9O
1l8cqwAWJ+ksKnAZlU9AON1a6XRVoW1FIvM0DKuB0SdZBgjTdPN1DiM43VnXBwd7uESaAVaxTWXgLN5I4bC/wUyp2cTxoq6wVXyg
7VzeCm01ffBScTnXVauxp5DZOhEKkiBLHAvAaVqfc+ub3zcvfaSzCddMAASHe6QzxG70DgR42DPmdfxqVTtArrSD7ouM80kJrI+H
Fr9S5bTDW9He3DfAVDR6aWVe/s6Q0RckQkH8L/lXaR7tlFzKdbBKFb5Mwxj18Mm/32i6Cvazzbhtpa6pxvsbsseI+8ZUiDOGV8xr
KKuPbXR71i20fQXGTRsmaRhKSLlS8m+PR4Q20vCuC1lq4nU2Tgtfz8szUWytAxegposW10f+cbwi2A1u7X9Gu2KDCy9dMINzP2VK
5fIgVL6BeEe4tLDcdJVb6PnT0acTdwlO6oOU/LJCDrg7NJ6SMRjdUyRhCYKOwX9fN1Tv36SPbf7MazO4VIrxRVhvPljF3O1hp0LA
OXLuHLlV/GtAVfUKJclYTbH43CJ+8nkEHR71caGEHYMqe7hplJ738PqP7V70VMd1MCeezD1ova3oZ9sDgDJAFo+V8HWf2u+Zm5RF
Qd+6Adg80Unx26GrBxwXkak34pcS//Q1P5ldfN1MLt8Y5Wkxr/xz0HgHSYs6jSa/e4yUC1aL/7isAhtDBSalNNLfstyRBOal5mPO
7+kmSbiPxGnvPpl7qQuJxjhjAQWYAmPYF0W0gIbpLgVzGS56w6Nf2kVZhCQCBNvkRzuVQPEtcNz3DLBdMMCuhx7OIKmzNTySBBzs
Nb7LR92BoNqWIDBejdQYdfMIF8MMBRfBZqI0G/ZZuLs5wk/A4VWJJYrWWsfB9/D0GQBF1bG8cScQ0Evf9SqpKW7Ss0XzbnURvtIi
18Yjs6wjhSHgqOzj31TFfLxQDFkT8zq5Xb5IJv4d8dVz4vMveXOY1uexk7IT5Vz/cbqlFJsO2w6V8/ZUPaJBqpRs04g3D6wjXjGG
arca38muJT6LivVH/nefnHI0B6IvHwnBEmAggrLOtTIASLjs5l836nGv2oIoyMo2v8gdx6GxPeehJ+28mdBCprtngt2PUW7y2O1K
K13MS0vP+3VZ20wILCkM2VrYRCdKRCFnjqQCBL8bKHt3Gi9al1IsMrUhkCyWaA9bEs15evyBHaMXnafwqO0zGv7/8uzQNFwo1/zq
0qiD1EHcSZEwFZYnpl2sxrQR5L2CMyoavqySFErPqlqrkis4RMJw4SgfFlzqNoBXlsvIwGtyAgHffguvVa3AiWYtC7TzLP+GQNOd
gB3uKFYN0txJaMmjOYuXeJg0Zz4KUMe5Mri9NRUU4VYUdj1AD09uHK3Po9Ggad2wCD1CQdoiIvD6Q4IO6fFvMfhN6sUc5wiCemft
4plSZkmV9rYfxWvTyr9qtSkbfuCWwC/Wr1xpnUG+rVcH8TnZUvB3CwYtfQ5wYy4SdyMvy6i3cjaBxhZ9u42HgXRnrC6zckveSCQN
mjyWwk+e3tO8UDD8XQwVreePyWECPV+etGh32Y7O4nIvuKA0PFtNCE47DYefl4avHtza4/Ntt/xRumwCo84pPvYNlrBlI2yPF5UD
15Lhj/bFyZMBtaeeum+26INBrX+awvWIW7o4JIYf4cKzURVHfOaJ8TwIcpIjliuoSXUNiwbpULTlP3LG8lbxPFCN414Su+NJjcCa
hUkygMHjnARPhSHoBKazJKNORINLL7HGWkJZJYarhLPq/fLaVFd1ed9v1Rf4jLp2Vaw+1JBkAMxpbzfWhgEGFDURVowRZRvv6OUV
lkj8kfLFiq/XLII20PYpqtZL3WRHoaozwAROSTxNSe+jQFMuUhlmhcsuUTgJsqwSBwpG2wdWLtBxARuDVCvYTjSgePGdf30z9DYu
DE7FpGEMIKechXBMeztV2KkNOsTlTFQ25VxObNpQGcGDuK1vOltjUjqL1Sb4bhzGg+NjZ48FVHfeaQCszJx1VQmeTzq5lrQTIHDh
OMycxN9isSwKzMWGalNYOKpDQMcCaMrRej4PbTe7Kxfy2soMLVOcfjw6QxTtlZT9PC/pwqWKrj1hf8vm0aG7JNaq4BRg65tSLLXL
PNCj6TM7WPpoEKzsfCAr0RmMJ4hVfLbRiZ/UfdF6PkPTqV1nDn8JnPLaAvk498s68BN4M+80MvnE6JrBvHKHJ82Z4tDbqrH1PbmQ
gicLMlANOCq7vjuqpv0HHuf4GKsl/5qUpEz9SYIbnWk7L3F2oG7Vg2fXgimaf8JSd1QRQUd+RayHaPGWDiyDOrwM2cPNRm1AdyPb
6SM/VvI3UxspYUeJ2brmcdHgAJHIZC33DWuBjDCVuF89D3EA8d29sQSvUKfBOYVYJIZwZGpoVmlrz5DfKiALodJYcTlRJtFN4Pgm
hTh0phiS1a5jlbHjOgf0fG97FUnP3HAJHD/Ier9y30sBEoDSftX5Dtn8nvmCGEcJHRPP6u2KzK0UfvEBIGNuxRQTG0yzio9gVN6l
9JseOBcxclhVxtG9XUhP0uF9NaHJdqeehe2IDLcgAcURRRl0oeX4uhChgHBveorwJMroX2ApIEJxAktsNITpUyZVgzgjT3826/QT
Q8IUFpwYWB1aiM7yV7vTFwLmoF0P2zmra5zhBXHtgpyYWASv/why4u+8U4k9CRhmlROJGVd+LrHDYCfgOeNd9kW6CX+aYGSH+6Xd
OFqFIhmKdknLBDuIXNFcHqmkr1CPQYeUTA2dXxVewdhXFXJNfeHQ1wSV3l4K4uDGbNnFu4arLBU4FwAl0mcKmVSIaMe41uF4JkhA
s1hpwCB2SstxfAX/6oru8yFW1zQxe+I91g+wzmqyO2YzxWGn3ALca5M1vmtgdeF9e+8EtMHEIwpGqEvNKB0iuO9EK0ZhNU5j9K2B
lShjk8dbNH4XO0Lsq6r2RuI1XmbyP10pZ0Noj8pSySGLFoVUt6JMrrohscEW6T2VzNO69/2w9rBDhKJji7tDxzSVPzJrPMtyHOSp
sKdnCePuWfhgqd5sshaZ5ZxyqRyvBf4Jj8nCPXPyTldVSHRcU5TeNeesSG6WWJUrM8hsz+hdUYHG0GXcdeSjY86Vqt4Ice5FYypf
iwAfvwA1j41NfwLh/p5p49ng19YfIprGoIZwDVZ88YwCHSNTaF0xCqd9XyPuMaTX34rpkfRBo19HRmSYMa7sZjYBg+EV6boBqhoq
dheZMe+Gv4sNdRmydfOROIPTSdyvLQE5VCHZfzI/WpPsFIWQ3ZPXvp7l6cpOJX5a847mPzzc8/KCPEVmjkiu+1dfReHuBe2J3wgd
LQSMUlufN4KethxPPjuQhD1WOC3I9Gu6TNxgz1QHuM1TcVwvWg8SzU01jUeaGTroinAeoJZDQqp0VpE9FXXtd2zDV8TbVp77Ut9u
drLKYxpTqlRWd/xxV0Z+0Be1ddFdUASJ1XUkmYLRwPimZtzmFDlk6Zb7b/g/hGJw8JrWJHf0Qa/M8em/RZ7frIYfhWdfUxEadNOM
4byqKpi+yl9cBQnl3IykjIyKkBZoHQqZN3WNpRIrZUmxtZzd9rs0xk8wft7LsIezgmkU31JusNJI9LgyfuCZXAjhtXKJebv3ICfo
Q7n3Z1T3RFozjNroLgDP/bSL7L+USQkJsDpinBLPODAYvYSmsTsyF+iYqo6NrKDJxM8EQDim5RibSAYLojQSbQJBqDhzXVu+3nq6
YMzhGas/GvozXvJJDnOY1RdFyRM6yR/NMG2gRurLB+qwzhqYEwxCZ1jAKhz9zprVWjJPHEIymdzw8XBbYIwl6QQ6cMZi/bLxIcn2
3Jz5mK6LZmQyO3MwpuqUHR3LdfShAj186eUmV3gsT8EO42PV6UD/chTrCOXxWohWcKxZu5VpqctK68wEBc66imfAs6aNQ6frlfg6
b41ao5KpsPV5a/YJXFqU2X1A1Y3r8jTWN8DNSQRigeLMbEP7VysnH+kpQqxvmWnD8wKjlJwjfsoi57AeD19SIykWkKkYo9qSmPpN
dRqqrlsZz00rs0f0zVdUVYMotxGzKT8+75XlhsRBvaOHfSkfiMlJVSsp5qyGX3R4gUyF6m+NgKmMtcrXStu7DFUtPzzF599FVK2J
tczf3kbKGloyEg73CnJ2WX+j5mBuOwHZcvFcBMXNu3P6eIssaXJhKEqGzr0/gcLQjpeEkhPSQqrpbtRdQc5m1mUfyYhWJaL8H3f8
W0nn7YyLnUv2JTK+fNp/Z5WeNzBn7bXpmatXvd8wYty9m6K1/US8VVK2iALvF9ebpA8OZ0TTXMQjRljFlg4QDUSunXqEZLeEglp2
NuKEHR1Qmp2n+0XEBd7hqg+yJ5oiuHOh8PxxSB/wc6U9eq0R9ZPBDD6RzJCM832f9LIAwP7snAWNZa1Jncs3O753thhRh5OTNLrD
zvNPROBWNgxV9z5UoRJtrnyGGAdpqF/VjCRG2gwEksLEJCKJJBMOmdEOR2o/jO1FgSe7CpwSIAKQU0Knf+5nYAngc9KUQk5ik+ib
oTj0amDDb7N+5z85SRTHkNbnKI2d7ixOLYirpanRbPpNZdpZYs/YvW9p3zrzJP2UFyLVAaVTvIpes4mbtuCKWGeX2Cw2gUcDpUt3
di0G5FsGdkStadmesjkr3aEkTuhYvd8sdaJ7XhfOy1ST21HHVAv9IbaaEvMyKGrXIbTJawQmRc5UMG3xKzN6N2bLOPxdRmOZusYD
skS+OOOd1dyqmqggzPN85g4d0rBre2Wjj6IAX5tQ28g/FHSNR1kDinvZebv1bE7pgfE2N+1uHyORl1b/p25TvxRoh7hdec31irGH
uP+/5Hgp2lrY0dVTWt1dRWd4UpQ4yoiTtByiibcpUevlF8BYY85cM2lmdlwlAu3hRCoIttTXOAqdUf+AXBkkUM4BUKrkkSAlyAmD
re5NcIqvhLt56C8dh2dbOHGy2b8uUAzTCxOjSHerZ3UHNnS8O6Mor/7EItV5JZIVkJryYHnAUpPFPXa34dz/Dd2l56+cbDWyj/Hf
9ftthKAzY9bjnJxrg8RPJxy1pSdVTt5h0spVs42fwdMHDFjqgfYch0g5p+IAI2Y79zzrMrwqy7ZJ2EfdxdccHl9kBZ8GOr8TYxuK
25OqgcR8jo7eFGXjMqvOWSFKsTHAgJf/1a3dFbnRxiAlWUM/yTRc6Mwqm8c59XUZnaidwlhQEfgpFhD+qrE3KBfZxyyp5XBhNZRi
Ift47+kqzDHKVpfxPMpVIRNl5s1rESF/tW5QkPWxlI01tPkdbezwOAtDw+f5INhhwHlV1Um3eGBAzeDVMVo1KhZVtjubGR1Y2Qn2
xjvzJx1jMA6pQ2IcQc2q+3WiCtsiC0FGWsajSBZDvBX2c92x5UG4RFsGKlZqR+yzUOzdWDRzooetHFiPTeIxEsnCxP5o90ww/d7c
LR3kXw2rqbMDmFxIi9xWnRqoTl48K2jRnexSc5NjUmE4hmxfnjmo1LrDbpxbxTpcXJNDLm0qo1+tuF4SyQ4igIx423j02vYKCC31
49X6jOBwT6GkEO0uoxDNH3Cz2dH7/Qwo4hnErW7L8RbrY9qafpGMhp8fk4TwPtgOGdCAsgM6gFCw7qYTqXk83ZYDVq9/f+98iQBx
HunLklN+A8BKx/17X2u4sroo98oTjVfO6N7fjcz5Q5i7xQ0rTVTy9cWNpg6h6TySRWzNBXpeS88HjQZNz2tfqH3edkAnoyLBiKGx
OSCT7Ase+X5+A8cc5w9zzBPH11hqC1t1qGlOq+Rwy6Cxp/96sA07AsP5Y255+NZpw2mfQMSGPaAotOG4rHl7JhUXXGoDjk263DvR
Trb2+0IlVvChr8tnNktdBwcISksBusQZ30cEg5tcN0vhyBlhMlNJ1XvltXkZ7KIvHBWV96sKWKpFA0eEaVk98mzVvtIdMRowUfvV
vAJL6iJjwHC2cyqZ121Mh9iiwj3X09pi/1cybl0Il7Zn5VPQsPeYP9NusbwLiJw0Oau0z21m0xwUxuK6YbNxHurmDShbK6iHOO5a
L2QsOx7YtTeL2exWx+W3ITbmQ6vxzyBVCXJKFDQHNpGRzPwK7mLHAT9Bk7Z0DYG4DMFX6xNg42tF2npc8MzQze8Q3S9O+GqTjB/n
S32zLON9mc9Lk1zT2YO49ogjKN9VeNKSYWgoLJqgMnjac+1FC5ghxyMqoTbnZXytnvLFHaysZp37uQni5UWcDZAwIPjb16k0J9wa
h7z02+2gP6Uxcn0IiGZrHrVVwlIW7cptU38LJX4YjwrftRlho+dK7Ffbzk5Fb1O639uNEBjPTV4lNp8koqfp7f4Al37+JCn7NzoV
/wwU8frp1gQMSyWLTm+nwADseeObAZpX0sEi7p0DJLDmgimmQh/WBEY9eEc2y/dGLL5/tmcesQC4zIU72bTMFDfJFlKS7AsqzQUm
N0BgclLE/8JkQo2DHxl2M+JHvJ28+2FUbRFlxPtRUPhojn32/y8yYFEXopHxluob2yewEQ6AynXWpgHQOf3dW1wJS2HW5IOPTGV0
Hvpedl+j3DrNIA+5gmo7qnqZVh3CRRhUZyQlCfbR8TvLkevqkg+zGmhKZKbS6EAGtz2QDVu4jBLHzAH1lYhu8dAH8NfLqepIoOwz
PP5AizafGJ7X+917fTKqN/K9nSkHThADIhVNf+efZV3VADy8kYwu8R3cpP6v7dZNZAIe/0oC4wUiMo8rhaeP4156Yu1AWfwvcMnI
2zUSAo+cJXCFuAaLoY6z5xvdZxvVlMNshf/urPBN9gFwrHtvG+2jM06DO36lO1LKWQOS017JA56PXShfhsIOjlYX8vHjZuu7iIMA
zC73gGKjDlC5r2QVC0aqNOJK6wX9Y+D+T0YQyeNJZXIGr47q5ugXxtTvJcV3vBf8Tke85YmKZYTIvN0pmZ6F9maI1PEY8EvOD8Vo
c4DUwKnOUkuH2Vj2pv1KzMAyuU+MKXI1rnzWTBLkBVJ3vfTn3rsrQJJkxeXF3ebX6cA1YW0LgSgyb/n9WFhyqIwwYRZdLWZXc8pZ
aN5nsHb4jtWlnwTNhJgnes/6lozEJ8U2OyJUVEuT5rJeIP3EE52zX2XjR1/nyN+6W7MWh3WKAP2JsBxnreUxJqYpWtV1s1WdGMJy
qaglolVOycl8L43Aa+HYTxRksc8/dshBZKnXgc/vq82uyb7CXJCce1DXA4ACOPZqK6WrqRK6AAzVg94N+SXwygvK3zBZVvvq6ITI
OdXMvrywVTPSWcZr0dCGC8GD9M/UW+61IvSMmvVkCkp02i4Xb0dq4CIxGjOtO5SNPwIx67PkpULyY8Gte38C2UqqNTVxz1P6aNyZ
mGfk9Flejao4UpawNv/mClBVtbd8m59JSGvMxayLIi/qy0ZCDmmZA9xZfXANe4bAttVPJm+HVm5sfgOKQa1ozA05Rdyc27KIR+sB
32ZbtmUq/oximkVNZQ4sAqNUBE9I6q6Ia5JJJxPkQQhjKpRjrihSQFxRL8TyNiEC/3NyrX+Dk/LT3AKjIz0EVxdqb7M+xkwJbAVa
jW0WhzcUdSQ4U9+iSde/GZuKuPCrjdCkvAjq+HDyrLgpiX+OUh+OxCFiHlXMLLsKef77C9kYmiUxzgr/QOXrWM9HS62dHJ1NHpkk
J+5G6AI/FNsi3Kv6IbLlpbZXiqN5m5U4G/bzN9VyPU6GQlhPZRXlQ7RhoHKcjQguFsRRfCX8BhH+cbDI3TAbAD51vSXgNOPUzvxU
I9gJlPLp0f7aw8XUQLWk/oUS4/BOMclED+sHOGXB2HLk6qj7PNpNAaropx9R9JadQwesPb5nwbtnt/FNHkIOoHVhZUIevrG0Rxy8
dfY6OY2p16Ge1upYqRe94pt/bhOT/UHmlqbOJD8EXnpW7xl1kJ1ChgAu0CGFCVvG3iY3Z/VpKKcjmskEx61XWRzI60N4y1lZ/olR
BCcPauaKM1BysO+OVT2Q0DLCiG/nmBtKG1Hz9CnQayG3okVK/z8Wzme6e86VGcT5p9n20WVriiZ1oworqr/A08OOuoZ8Lyoi1dlx
hxMPhAhyQ5ZvtLAnr4L/F5oXJYz0SMlkSFI2nBNJ8dJ98gj1Ql98a2YzvZBfj69tr+Vfg4TtWZSBWdEiDrTMu+QmvKNGBoYxFLL2
I5jRjvX8GzJXDc3t8PxKjXMa78D0N+hdPmFYhJX8ntklP5c2HQo4PlCtERO2F9+U0VwG165dLdy34Iz82fmMfT69vaJUWDvs878v
pXO88SurDXTj3kPCCD4JmZNmf56RrTH2S3y7EI7kWgQ984p4MPghqBNJGKgaS1eJdDgMEKQdBgZnup9wmPNEmNcyMUD26uCQX0B8
XbKTwsjxD3dh/VYR2QWGWtmhwclyH58uPP9A8vzWrviOwF94u7p9PUTl1zxMiP6VhNUSpj6ZoPnvyOBI1Li22cKau6BhNtpCxhFR
BVD1xfFWb2+CnzvsAKOr6s66zj1P/S8U0V6DZUMXvTcHLEn/8u2TR9IZSS3IuBZaIuu7ZzTfkl6Lr0Hh2NjnJ/0FY25D55XKGn/5
GZkdgdRE7OXyrLd+CWGRewWFhZu2yyKPNbZLqQNde1KeAdMCnbLtExjx9Prf94n6gNWeRHhbRfdLGKMLnHE8xHZDzBTBwJIlG+n3
q2zVkrlWcWkr/06o58CZXX123sI7lI7bOCylaeZVTnNoufbu19BfhpDhnzUmG/s277YuQSwvOnnrNgzqel8Myj3U8uNcHV9dmQed
suJLqD2l4Hj7VDqlBvO5zqaToCRc5mmbvNYSuwRy5rArafiUOPC9EY9J6yqNgC8BLKOFgWTTBtHdtac+V/JOIJIEDtmKIiYTTsnJ
1J5qI8qqBxrM+uhuw9fsBiH2gRVbtnj/lJN+5EimUcyKGpQP3YEfmmo3RokLPim+2tN52Vn6E4KGjgSSzkXk+5S0Ml7lYoGSfxyG
FTxUuMmorA4NLsd1UdOH7c5uD4hHhr+KXy5b5ScpBnCnScYrwvLw5mJ5roZu2FjAIX4tpHZ7dsrn2Pqf6FYtJrTduOcVz8PSoAP5
lPG+KCgxvLD/GReREjI4mdzzyWSdZKXn+JIyACn2WQD3idztO4CgvBn9wJxzahXM3D7D17/ZyWGaVBduR4tozKx4y0ForQRflgWM
m0TDqxhtO0u2SzDlcCU/19cPsK7QDgc6AT/Enov9WBGXsqJtUYBQ1ijuArtg9TZilZ31OJEao37QrTVeD6i3FcTz3xQqwL7E4URu
9TnAm+Ap2gIhUPvOjpk1CHpMhOI9maiYg7ng7p9f4PKWnmQ9qslVtE+OHw4UYV3EoQJ82yc8Bjajy0HW7W6+LUXztpgPvLz2sGCL
MUfjeYiEOrQowqtY9WBVv4XHZV0O6TDPW053w0W2WdTw/dfi1QZD4IhEOGrVvJnFDQPxPizHysWfjhlhnkBOyua9mMrl3AvE/7ph
rlkNgE1l/Xikg/Hc5uz+3kP04DOYCJgnb34a2cQziTR8VHGo21zm91ZwHSDeHo/lsbB21Py5Qvc3vwFfpJxv4JySNbyza00afSt0
C2iUX2oXFKkHrknpb88C4jXlX4m0J2rRDCn+Tp7QzB3JmRemf9RxcOvkZfEyaKLW2uu+fYtc0UMEl+sANeSFQQb9ArnnfzsCLisK
CZpNHcgAI58mn3NMbhecKaMjQemvN3feHndy59W3FUvDjGOgnvTSVrpqpJfnFuwHs+R89oZlwIxrW2hZhUrZ7pQSplyO/dqEKB6R
FcZVAjniap3Sfam4FtpFsw52Mr86z51E0endJBgUYMzGbNUMxAvOxGmJsJ3FqC+51Wt3/Grk7I15W+5pUAlOsmKXYLEbk8K8ZMQ1
s/v5ByToxuueCJ6ERWCySFhVrxgYZP6kdVaCdYjGhZRZxye1negat/xS5dxj0a47NhDZHnN4Ou4lPwyGIBUm7LUH4ByiHigAk7kt
+uClNH7PZLkv5lRUIQ54m3zG+1/o0e2R5f6OleECU9RKPtVjDsJYAA7T/y9gz7YjoOMzI1/TWa+NYCwPQzTcjFIU0iMldIr68wjM
izs9iwF5oytie7C1VA05JaQDWYSucUsaUNIv112Hl7OqfZU0jU6A92pazEjHwMDLFgfROtE4kZJo5Rh90yYzoxRvpJn6J3eS7j2o
ctpX9VdR7BSBpugilufVc9puie/B/CHhBKSPrTPJG7un27cmP1MErL9UuOajabetDZqTB/1e3EiyBNXO0fPP/laRtAPmlxDt0p6s
J8LXvk4nQ0uZ/np4XaP5KsEOja2/lo1vSGaXELhNs+xfCu/o7pxZZQLxTyhi1e0rWrO+S+yLNdR33UZPovr7gRz/2fMvccLV2/Xy
sn/cWLBqwIovhrDhnC8oXY5SnAvrcnzCTsxZpaQzx/9O8xX75wO+E+ImuOrEZB01X+DAvX9czVgUKBZgzeZET+A3iiGKeJRzxMxJ
gSlgGRN+/HGCn9Mh3qSzKyvInz/6bvc7eHNnPwHVK9qQxsLsA39i+CdizmjCu2hbv/dP1jtK8Ure86J/or5mwqJmDDx5xpyzEZi3
pG9Z5UVPVgf9nNgxUsiWdsnMupRQpNWNSBi4WnaCz5qOoHx30U2/6/Z1f4F72zhknMXRb/bONio9rtuYLStQ4+Pxzno2CBkZx68a
6x2qaLl3eZRTtoxW0IsmYIqngJJNzupa2Kz5BQRGvjfQCPAJ5dKJndoZrDKH48WR/WSzu2erAYofrqpoFpEnbFqYPzvDKJFhUzdz
fvxWybmFu37iRHssnDFW0UHKZsne8vWelARP8b/YdB53HUfUIwInywWYI4SazrCZXpK+0lb+YFOo/Y/zN1fNK/HocIlAoIrwjx1G
19qkBA1Ajw5c7WwotJP20HhYe538buY2BhfdmzslNTlMusT8GT2SJykJojYru30YzxupigjIWZI23MkQ0tKNFq68NSwfYJWHcVkM
mcpMXjUQqO+GOb+g7aUvyM8/PTaXcr9X/FDlUDTX0pnJffsFKa5p3aR7LTXTJLaymWOsguNXT+DG7swdCayL2fHcP1g6SmFr5McP
MzCneOzilFZUjy1gZvmFXLLT6Z30o4evrt2q5tWICiXk+NpoJ/nCTwLygHC7sOFe3uNV7LiKZtGYTBC/xoy6lQIB1zWXPKyNGjlu
SRYkM8sXADaXygY8iIn7NUstwhnQr65pB9i0VM+A/LBiXQuqLNxRJLmSxsQS4Owj3gb7337GQK1LZhwlFito2TQoFtIRtibkLUw4
1PCC0aZ4Wp8g52atMmMPW3cirIDZbQzRgHi1K/ASitwvB3lqST5/heJ+jAbuvTtBRqsapMtxwV5AAcQjs0AHg07C3Zoyj42TPNkj
+E0d32teASnaZBvNjqpIZUaFFlE7oW4wvE6bwNMV9m1YMiFd9NNk5u7Mz+z2OhixwsaITkdtLsFws0UsXJklJ6lf4SOpda0r4qJf
EybX/tMFa6FpJoI0Uxel2aPoeM9GLPZABXuR/3xEX0rvlomiP5ghDaVoYoX885akt6lXRrxuDnaZge7ldN76bs2l7sRqfFk9jof5
xlSx5tJ0ihZIzaEbi1S9MHV2E/xIkgjdYbtiFPfyU5Z1EuDUry8+qaM5ktNZDv1WIYLgBuMzVVLVw+Itlf+txo1MvSQvieLFXr08
r8sFIurCHqYbmiSZe0oBkTMWZpSDbyso/fB4Ytw0xhV6shvYkl+Qpz7uwrLHsqzQVLO+DPJjL+p90jiCMjo56ydnzrBTSlARMJBr
c+ZUvRCdXtwKfg0SGWRvoY/XqC+KZ8taQTtwHP3qEV1DWfFphFVx2xrybwtmwMS8bKqrpHqO3BMoKernuJM492uW3ukNeOHz373o
IlJfhEyF/twt1DpnRGqPaPBLClaOluVJs6tyhodgpk7XMFMw0icHUCG9Buc3bxNvZ+lBue2aFZ081ozx0gzmKg3r6Ngyc+5gtyFN
7lJTdH8h3Zw5K8rVYsMHObrdojH97QOnJYKgEfIQFR2wcL1UsSOqxiIg+0rUVMMmfZZ2XxkdspElWXINzh4l/ttfZvBSe1eDhEsf
hD8oW/56n4fe30aDOwHR6DG8M42H4zIWtUWsB/RrCq3h4Xjs2zb/Ay4qbcqeI+ju4k4/P6O2Y8JjdDrHUBsYQ5u6PUQH4Udi+ng+
O50WljJOHImZlYgHIwJDRYEx1RqkqGWXyUNiFggurXny9YcW6KCY90W7jCMWmX1e3izaSYygeXpDTg8B/pwZbb25VLwNTrsP9Skm
CBj7jg0lxx2lxGncJAxwJ8/22NgW0Tcdf8nYEG/yqKztNh9ZN9UoEwnMK3n6EZ3pkp/gxzti6n1hLR9ZPQOPAINUOH5TqJFpl0vk
7yp5fWFgDbH7nm6TC783NgBewHRIDkEr9crADW7YufbSIKC92wflHk5iDmHlhXU0oX0lkORDbWzbXIL+nE+37NQJFjKaOy3leblU
uxgRRmkw/ey9eq/+lNtnr4RL7zPCuV8uwhpNSg8Is38fPLR4N2Hj9/LMAGkeDzsLMkDf7jkY7BRMda/fjij0HXpe3JO/TDpwk3Vh
QIp/+N1FEj7C0y0X9IpQ9BV8Oee7J7XDKWt0iUZBRHlfErbQmdXdUBffZYpN7kpKFBwwo+FzD7tg3peL4IMZPaEyAb2buShyWtdL
PSpaRvAiewuJ8EBqXdYlMzBtP8gUNOOJD9UwcCuZO/bF6aU4eV9tf9rQeLJLFZOm9HwGQqiGQufhMr8DOcpZShlKGta7MTv7pRnn
CrCXAezXLz6DZycKQEzpqPZgEu9Amnub9uaMWTp2srFcdthSvL8SfF/otW4GQDHy3URFzLAzCqO3jZhBAZWiic1cNCpA4WwFhwGO
Ar5hiGBUIAy8S18v6fd5+TJiMeBA/pHOfGhifE4PGLnofrUVMPDtNeSc/eY+3CXE5YYJUGIf5P4bmdpCoZCWWJ3J2y91agbjXhUd
+mK1UfKlMD+2WtrdDGuttEnDVaEmoVogO4kxyH0n4WwwUOaUnaJqCUAPJiDtCU3fbLsa3T916OM00ko+ZMmNgSVLwpWPeDcLkg9Q
ZkB2wWFdVKQDbc0z41iysmsjVJMBvlPt2HcBWQdEYA3VFL8h4IDqswPiFw0m46a5BCSP5daBa1YR4FddGsj3LfDOdffih26lQT+s
kw5oxZhiC07aRmwnz+BYlMvq3y1lE3jRAoWCqX+e0y9HIALc1p5GlS39Gr/W0C1ADufHZtnjRaLAersut8dkYPa71ceK8z6i4L3L
luPqyIK7m6dyolhruTKYmi7GuCdvLbFpALfddOv2H3wXbhzLb8TH0OxHUo+qQxh+RCQhgRNB7swFBtbPt0EOtUe0If5wpRQBuSjC
iKKPOH6Vg3YOyrEgAsirfjhnlM/lIXoNzLaVLbFfw52uf8+gz3VTBItPEr/TTSN+lGb3kt+k2v7YwSpiq1gp6aV4sqpTUIXLTRUG
9uVpNMy0XE6zS+T3LGWS6/5PIRj7HGLB0RFStOCQcSV6de5HY922p2LaC98uHtle2+M5spx8aj7safF2epPKDaH8qQwyNKiBoipO
JMm2DuukgTrSRP3P3dFVy8BI5ZxLD0C0nJU+GSQvW5M81qa5xByDYAbVCjJD/dWf6WfMYlfz/Pa/pmUYakpqM8oyhfbsBz+QNBLh
Pm2gKv0ieFNgE76e3F9EuKTwlE6M7/NlkYbXNInpz2Y5/cDNipk+g485fJB69wVi+DhCuWCG170Gso76/DJtG4VaUmzW6XIG2Jyv
CeJnPWo2DsajwyzHhNdOvn/pEHOueN/Z95C6QATUK5Mnw0ZTJZU3jKepS8epZLBoGitx9j96CG18hWNkC/4qD2VulODAOyW/tvYH
9CV5zH0Dn2UqAW8HCnslHXj6wv8zD1Sq4LsmQkoLuMb37j6V6fhJRUViv4xlhOoDsq8qK3Gnv+773/db9Wk7ZlTnKZL8jdaohiaO
z+QDvh4CVPLEmvRxSdrZcQZFnk/2DlNWZDMMkGyKWgoBkGYu3Jn6zWmOmLGHSltlaG7kMKYJvNzzy6LA688SqKb2qKqoZvF2rbtU
KGY47COkdGNBKTWGq3NwdjYtQsOfwIS8iM4DpQ3QHJiNnE3wZdK0PbFOinjhgmFPBMzFmXZ3fL0IH+uWFg9jLZhQd86Y0H8B0jl/
YKRxVAxwXbNlhI+ZDxz70yOg+2kOuJYZ1ztyjhSG7S/0UvowbXVlSlLmk+rvUQzAzJNIFQbV1Cj8wber2hdwAyTjvi5hio0HP8V+
dPvZLrvbEmQlM7IF2aDTOB3oZx0wXfIPWIq8n4a/y5gzr126kf6Zw5lRms9SuG2cDN5i19gMxM/pXTJyyTBIzOuxKmsH4RinIJlt
kb0Mi7oDDFtrxT9qp4yxurnR5TUd2H62uXY6bMffTC0v6dVM/zocOphE3cU3UBadcvOfOJC/q2lp6ow+xDKiJZug32nCK8EMIw55
GDrmFFe/y9erHwnIp1Na9HLRHdJt8l3jybm7j32jaFrPTm+cIZf6wv6YBc4oYqFH/cFqQAzXnKs/4Sk6syk+bRuJklNHzI472zpD
iqWRzsNfvb67SFfg4KVHYOV+rOOhMfaYVjSEvx1Bs6t8RniyntG6cLO/Rm6b7TC8uwdU9xLHIYDVQix9+MIm8d9fgGwHgVkzrnXU
PxInBKraI8REblYHDL8ehtuYtPT1/HNar6eeYIuoNob8XyVgTqq1C8QiHOI3vyjGaGW+dQnbe2JcbqZX224pc/CF/q87VYP9icFI
9re/1BK0VsRWVVIXn7EzRS3LnZAdqRorFQ5qnTRSya+VcxnHRHZ4H0cMTadXGdt0aA9DrQrdHAgBeW+OJ+eNqPsf8ZmKHG9bG3bI
7kNFeCbTtqQstrBaF+fQn8hhxzG78ylz0Kj95bWKAPFMvjIPNVCChncT0Lq3ryYNavhZeEcNRdTQPbW4lzXXE449A/pWZQs/nDQZ
4MwLfMT4yT4zbPoZQws1aQJ4HfHukkYid9TLxfJl4xb3t8S0qV5UyugpZ8qzBOZg68N9M2at1i/OG1Pgh/m4lX67t+5cSqsC5qQj
ZCSzIwo7bX2NuxADSgxU9twCqInqe2CiK5g4p04t3SUf6ZonahYOP4W2zGzyVUGrUaEPm8xXtOErytV1S2vvKHkOh4405QpzKnXv
RUOvBG3aHeK0Llny+DQOzYi3Dpy9NepM85ZlsbwdAI6qvqlQXB0RPzjTe3qzOuEI2w3PciNEtp/ogcF6Ho2Q//TeBa29RkTlc+Z0
vMyqCekxtmCZ1a39aBE/hecFym/tHr75EIsGL9n3i9twOxoZ/X5NB072hc0iK6nT8C5/FO9b2g5EQPXuFfrVAkcCj3biqhU0L9yV
GjnhDRwDHFXfq1k0gBRLmlGjuCPvGEwBB+8biGO19918+GUHQnkZA+12NjtGb0Ql4WnzRK1ZMhUeRki+YdWGZzyMnHAPUbyiRBhh
UCzNUwEbephYDbcLFmDDwLMOwkqoQrf6Zmf6J0nwhwM5AQR3D67gtWUd6XGwSqxsyjBe9sxZ+4Wsp4Rho6n9ousJPaIMv1WlGSmJ
66BZ65rdpNWtJ92XCkGElDSzILU3VN4kYfETcujuTibC7Wh6Kmw0U2hYTlfTHfziFZ1FdyWQN6IW6MRTDxg42cWUxdkq55Gy5rHK
70RxDZdbDh6xkVd80ahAzrNddsngU7s3cfOu2qUnG6f4vo3lIvemqCzPxhB3me8iXD4ToJBzFxqCCWHe9oa2brR8KE1NBbA01R3O
ebeJ/l2sRgK+E662mNiRuY+VsMHRynjvx1B0tCW26BCOvf/V7XT3w6+DKwH1tHBJVopumkcUWF2zl/TPYFb6Wqp0+2SaNArLlRhS
qvFvH48vT9r9+CA+WDenCJQfP7w67VqBiAZ3og10IyEsGzvLGjYPEi668/Qd+CWhFfTI9QmL6kPiydkm3j5DMXaGtZt1QnOaZL6c
FB9fuwzH+1wDIFVueJ7nmeTGu9nW96z/s7Smqk5aH5BlV3f/806UV7zL7COHrF+RT0KBR6OpDsCiDaNfPinuvYjNuVJ6XltHqlJJ
ynA16vHJvkAWyzgvQkSFBxfCoSIgLnl1Z1b/UPfN+go64qfdJh3nZbLQXbx9QR21ZV5jV00cIh18EZG7uqies3QODvt61zK6bapz
zyicBbVZfeqOFnVN0prh7TU9Q9FpISRZh7wVE4DjrTJjyOeT3Ertn1iawkUNxrXbSz9eTG+optwnkqn0xau1N2ir6AxpIPP2HigR
RMh90INghLHi9nF8eG8JMN+sPmh9e8DWZl5+NfiZZeTdfx0QyqT7AYJJ7F387SLQHIGyRW3OIFeYXC213MyEEJYZkTXmuxTjTwId
Q3rnoTp2t/gvhag3p3G7IMrsJSs8ieOdgtDXfkOBgPX4KVLpRQtRL799P5HDcoqdyRZRhzBgULZPPfIqNhxZizdNSgNGCxJOyC9F
1ub13vW2yP0QY0IkIqlqw5q607kPCUoXWRV0T7HJLEt8LySZfRnsbscQWA2ATZzRikU6zjUmeFliXAiggYAegc2pAIZhiWZd9joB
8l6+jT/wj31zZVSLvyCyId/HI+PvM6NT+TPlCsAbxanXq6nHlhrYwQUIbH9qnOjB4t9yXrptwezd5RXkFIpFPnPNnV4IT7kEOl0J
nyDNQT81zDsfInKkXBiagvgzDdw8WIQF+kPzG3r0AyehfV0NRftOBCZGLL79p4erP5ktNbEeOLxnh2GTrboloPY79DiZOgmB3aSI
G/WKlDvC1stKp3KdK4jJf83Jpuoy87Y9uOhR3vql7fw0oU8e0F/Zh562g41cnx1GkbcfywnYKAzl1LUqaqZ0Fxt55BMft8GMcP2F
q8Ttdlra70rfLnvxtyZd48onTieZbMJP45+wn/UiPBpUvV9rN3XaEcSr4MsQs/64pzM1p1XP20a6xIjhnsDceP4IZcFh+XfTzHgZ
TcCl0N10iSzOM869vq4X+Lm8wLmqHM+IDLqb2owoppEHjbbL3xVHo5RJcNo29YEr7fDOLqxfSkeJ+oej2ooCE+ljtH1NoyXMgLBO
RMcuce6N/RDFIOTfFtrYsKYxVkmBoJ5FORnl98YZY9r/W8KepSPIEy6aQsXXaBPymzaS7Uznss8ic+FJFz4p4Q1EYwQb45nPVB0Z
ShvEMOH92S9XmOXkgsoaazFL0yQxBylcwMep+4mtSEBilqavkbAucm2d0Ht0i9pmEoYWQheIcbtwWtLg3mj44OeG5xgDoszVTQyG
NEKvo7MC8pGTaPO2AUOqjm46xxFgsQp2EPziynX4wsQd44eZ98gfwIHFwTOj/spt5DhMmmxw3g6eCg+XZ0GHCVoRe+10H8UqUl+y
a1tuKITEXjCga2LUfZVy7CLUIJz5p5Znkqr51olq8Dxx+Qk869EXVKzIp91eU5L6EYdHiHobFePqPeiYRqUTQaETTk7sRG4m82jm
5B59neuvHgIiAhNH43/QWd8fBSOKUvrwGLs3DZxw4etAGXC27HsAFxg48n3mQIuWG4rwlcrkNWBCrp8Fa8o7Hn+RkguM50owpC85
HJoYRYeZajQ8FNkMX0pVs6c2t0XYiDj2QbiwpQUJJfRzBJ8FhK9U3aaRbcXdp3UlvWDPcvl8zaW7WU0G60JryKEgCznA06pphxyj
ovVT1USYfkUQuMQHi+ESlU5ExX7+LZMhjmj/JVSyU9CvN/1IrIWyb8iL51jzH7MsjVhP3XnZX7+h0FpIMvcMLKd1Td637660DnWw
C0yY7QHt8scq5eAshwIcKcmnOcF+2HgfKS5lViYyJ9jMyjglBsdVqkMdPhk5bhEfVxprusXIgJS8DxsTegli6LA+QHmjPm9FL1ut
eFm5TL7TVGpIFZYKnOD3wdMxsPgOx5UDoruNEP1bMk8qd5mrwZ9VEDmrRN436cHk6vAbJfJwC0WOMBupwQf5TlW4XPceg2/7q2Vv
FT9kFIpEKgXhtVrOezgeK1meYiWZoc/l5ll1vZj7L4CFRHkrxvmSHeOTyf7rSpp87IYNN7ROq2vyXJuaZN0FdcNZgQA9hcLSXx7C
YiX1Oq745lPr3H1sjG28lwEgaAv+NBjCw4KQDssSolBWcX5G6wRB1L46gZXCJthXs77NveutsD9YPiBB6so6AOJrMrLfk42VK9Xg
VIRHlc2L9dl/9kRTOvuHZct0du1za/EKYlL8+HqVfaTmSLrvxUroh0b4xiSRcC2+bssa6Q2sWCuil6T0GFIjXyd/R6FoIAMj3+ws
3K1gjO31iTlpXJgO7n1s/fwccHtgh2hLvOWe5bcUQxEGcjI/5Hk2DUuqh2oJ20R5n+oyzt2TRjX+SKAYTIDrB7iRSeRqSxjcTLCm
Y8kIDUPl6tR+quqA/vHLZ5ARQTGBbolWb5w3GZ5Mm1KGMbAEuNEkCnK7oMGId+cHXc2hmEl7Bp2I00QwvEvLd4utDmKo09K13pIy
YzrIUlgBbMZH5RnW04ClE3ROgbr84DefhmwzBakK7GQszGtamdCQrdBU2C/d7xYeD4N2TWikWBDuTFyz9OmZ2tgReT1A+95pYJ4M
VpmdZBHREipKi09WIw4fPpJ0kpR7JhtViplPIqQ2YNFe0nrSVY9Zsm2qSWqI/OM29sAfi94+37IVAVsmbeacL/8yDkp20clCOlwE
9tBm2olxQfGizXlJCnJETofFNK9WwW+tnPJljNGWdzrJDGPJXbFtgdQ2MHZFNO466NSzv3dvuIkpiq1hO6nKrWvcdJVNW18geNUw
NPr9UKCcYt7HFFsB+9NYsrsQBQyPDiCJK6yWZlwoJMG/HY7MDrrUeXw5Mg+WBlZSAerake+8WXLsruNZwv4LdoFSQEfx3Cat+4Hw
8/UKMl+4aputoQjaY5j7y+eRG1hPk06yVTpq8szcVmdVX+BlbYrCUcCz8SuVLezUy3ChituMu1GYunBymRESo3ObYmLrvG6ghJjB
QDTnh8vwUDSYQD2kJ+842utMt+ryRUbm3xe8XSyRFRtPM2wgFhQN5i3x/MnaUmDUTPxFEtLWZRwqhcm3AeopRhEfplcqnilpaSce
HtyEUhidU2ufGDxE9j7GXOpfmxghCQFG1guFEIWa6pJdSgz2mXTXbi1CfjBI5lvVgUrB0xssVkc8nqY46oltMz45X+QRQ56PMSvW
ItD9yWqnoi2NdJQbA/HWJevOFVCHS9l6uKYnRIwVur8R5SFWnj/UEyPwxbjGeSZ3cM6L5Xdffo1A5pHRHTlGJW/nkmjDdfiVQbfV
+0P9QNCipZzNgfEFZwVWpkO0K/uSdv0hI9EXIYnZhZgzpU4vmzFojIsFUfPQPxaYH6Ph34vHT0PMTGfsvULSyz+RZ1qK5/ep25V2
gCMbrZ65Ezf/tOATYCzaH/ZJNKHQ3J5Idu/wbRJ8GQe5SrpI6GhXXbA5pmgT/silufWaMAyLq4ZFNlDWdRJk80R+Q/Cp1py8uDeo
bk2t8aAjrmdoXYTA7gUoKsSggCEZuKSkdOp9nu2XmtmcCWXiOJFWXBpNAfwcoXzeW8tE13KE+FzjJ/bdd4rXJ+gDdV4OYpv8S5Kt
VsVHJMbXrzwiTXhYmW88rQCGHVjkwowimZqlSSSmnkVpZqDtcVM3dKtymjWUEBedrdohq+JuDsLdegV/IsEVye+FdZCr5+r5FIMf
nsFY79o88/AxyosEpOGfWviE8gFiGp+lrspAmrY/n70ti+yrep00Jg3/ckXBohc7T6kRb9JlTuywkHthDR5+S4j6jd/F9YT6Rk/s
F4e6nXmeUcXY20V0XPQ7hKKV5UBex/yIBm4rjXG3wvThDYzur/PKSLS4OfHdquU0bACD+VPGkxozQFwIuPnsI935rxKYaiSFhcWg
g3r80B6b2N5nZLz76/ALYiCtVIk07bIi0mAK4ymRxCsLViZR2LYp4Xchmo+R74/jGvEWrr4Rv1GbaSAoU+tN61I14Sc7U92TqHnj
wLMZ0yre4UO2aSRXPNnakZy8tef63uUnEtXl0v0SwrPl+Su6E9OESuzSsBZcknnxwxui928rCvSen9xhKIFEbT3GXsbkw8jY0+NB
Okwc8eZv2v0rELCssBzUZ5KSK0sSVmohzfTVK+o9Ko03kisAU7sPNmJoztD9MEBA/ovmW8tQJjXeGTEAK0xaqhe2xvLuYOn8Ht6u
Go2J1jog4xBPt0FNaCQJsJy+q8FWYW50zMCVOl8QTxcCnafw8HDb91Ti8UvwvCTYQyi0PvXdVzSNRcKgEeJRqN0yoD/y3UOJ/PDh
ZRtCYb0sS/P0PQVV1YvBazBqSbeYfUJWDESHygDfqv1pLQM/iZrH7bOAYKVmSaSJaOK/SkV8/K4xFuZJxP8NlrvJNAJ7DxztWN6l
pwFJJdNq58hk+7z/cPCY4Xja4gZzTmlLEOY2LGRai1sXtRut3UV8OC1FAL3pNpSCVoEiZZAEOBoqcoCj2g1fsr3aeGUK9qvqCJDH
0b8L8XS5cYe4dVc+wMQau0/yKDsM6kfyeJU+d+D1KhadBg1BCkAtcyXgIg26A7qdO7yilvzosn3GeUWDaeNEDvbJTEbq7EgHNvjp
Ke1QpE7h4whIFtfVfw7cENL0nswZtRPq4c/s3uDXtGVrdEO+AayKtzai8gLn4ivwCgofqGTPk0pca++3ou+eEf3T+RF62larsALI
FVXSBgBP02DV8x42LG4WnTwWsNr1fMDS8IiJcwddTH5im8HEqGxkFX2LZKiml1kWyhflpCn3jNM2HavQeISCUAypQZH2ydG+pbAb
gNn6p/B97KjihPC1juNhJOqEYRDCw874zxNtrfl1wcncQ9B6drGZZ+1M9OCEHKGgrgW3JH/2n043zV+/dBHuuo1hN18viYonCUpV
nitTC/Kj9HeZW6YAPllGwU6VKLJUM56zFcF19i3zV+rYoZamH28oJvPoDgk5Xjzk4R1yzKKrP4p2czBPVd46Tsbfb5cy9ZljuYXW
Y7knRu0w1q/efdtgX8yEv+WuS56ZxIwuWlfxJ0lnU1lm8KOuewroTufPOVRMSR/yJXg197aZq4y58uLlXBGBH4tEU8Dfees/7wDp
VGc+ZduJ5rxoueALaLs3StNFmH4FZDuL4fZ7g3UIOly36Jm0hN7D0mbVg9u5/WP1bjRqJ7/j2iySMuuvJ4c4CVU8ArdaMFKl9xhi
5Yg8pZLBAkP44xjEc8u4fUR5u9XtEN5MVKxwZ3AM8YBpeqSDQ9XsEn2veXbVd5oky+TlNcT0YnYiNvCezJ4jUx7Qo3JKjQDqCS0/
QNxQD6UA8a6hspkyrPzDOHTZnYR5M4SJm5l8j/hKVCU1xd9eA+nrxM8H/o6N4WO28U81ua6U2lg0sDN2jkbxYWM3gzjQ5LnD1Wa0
RAK8XBS7BdlAVnco/i10XCPwXkjuMEhfwiJymRLxJhY5SLfwGJZFtCDy30w9DR5ZYnNNf7xx5qDcjFkBLwSvDBWGOIrH/y0isFEb
2qEdGdxJ7Yca7c7SreCK1evQesWjuZJTLw5L00u0vd8z6nG66OgFU1IEu3D2VMGU+xw9cywWqTDtzpF+7DooxQnyR3TZ+H8/9XfX
N6MaTV0560JwlIdbOjH4REC3FRdts350bpQk96Yl51GFQWDwyAM9N0FyyPrAntUhw0VyXhvLvZVkIvxWEY/sAGLuagolm2N4u4Ia
QIOLFnseKAarMEcFxJ8sMGcHP42LCtPlOlkOgjhNJwkk8Acs2oIiEJuDiMJIBd5cMEQrJk1a+j/nwvvKu/thZurN7D2gdyuEKIEc
0bHTJQiaBXbKYSuS2t45VaYUKlrPe58rRy24Hc3GjLQgEmV3gVFCe6BKpn2xtQ8TtRejNHzVX/vFEWk5Uz3cpa1dtDxpB4/OgJ6F
J0K/ZMRd8binczbpYHFKv/jCyr9eFHaPuba1wTmoqEJIFWODRsiOq6FB33PnrYSUDKwO67bPuSh5Ayh9IZLOlEUeZPTVBBo7qRFC
e1D4iZUsXGhYHYUrShAwgBDg08VtA/UPAJRh4q+4grIeamQJjyrBTx7TlCHmnho0othxIufCNplzCbvKXjdZ1HWf/rL8mORlgo3P
nYM99de5moUdRhbL8S44994MdXlE+ekGv0tXlt8J0RQBk4PKGIjHOyVzgNgtSnCCncMSGpj44neCM02XMLZwr1LoCXXyMFeIFuqm
xXPSMFMxWRUi0czicrXJZUEHjM63ZjAh+V+vPV3yGyA2sV7c06lgqFBLVTkN/pEBsHZtHnw/9TdjxNQ6MR2mU66F/wZAM5JFpJFv
IaEB9keQvdtVHfDFLFdNFNSGckG8R7lqKJBIx7U4eid1Awd/yVvQJ41XtMt3aD3cCk/in7aHXMtA9fWLHlcAGU5BRZnTSgeDN4r3
qPJh4ZbhFolBBH/Vt1Uoux286r6dipuf1NOOfc3oaiSqgMvBT750xZhE1A/hNTGk7ksXSvl325bH0ajiqTXDd8dv1hL4UCqEuyv9
ZJCbY16fpdNMiJjE/kMp+S+u4ujK6/1qWlw7OKnjNVEdQYDkC3OX8VlFFYTsu3TxYL/3UQVc54IpSwvOs+p+/YPqUeTx6sRgudXS
R3DqFOFabgyYGwxwAztJlVu6jNNBaZygsErM/tctcz9pBWz2Xz/5NWmbV3et/NUyRBiUi40RSkKx3kDggKuEjW1EDmZ+4ggjOrDe
g22iZhemT7mxpJrNQS6Ou5Rc7sokV7h3FoFPYQuwCI1K/xJk7Eqq2MjqZXiFMAkPw+oNP4y/Eugrbh8iTkHfgRexZPXup0yH3+aJ
+ZAAk1nRV3o/JkPTI9xTGlppDsYDQvj+8c6LihE7lgnGRwksmknmA6yKAy1IJdGBY+AxzZVEdvM2+QPG+ZrIfNkKPCY6/vv6o3Iu
FlarlNIKsKT3xzXRhVxPRoIBMWh1dweeKbupZTjGcARVC4fsXkgW9CpambV2vyab4cJcjJYPnlCVll+kWo7nluMUKwTbBPSlNEg5
NxTlWLRb+0BKEghf58GOo0F5U2wylukNbhjVr9GNIZFgjaECZ9kdrFJ/BibJBNVtIVV5BKOEAUduGTTAaaiPPPi3rPL5jUYfKFyj
U0b3TCOrmgmxzpO9Db9NQ8q2VmHtCQFIHUClIYGz3/lh0r7gX2Jos0jxmx6eVXODkE6xw/qqb3ne3VpkFimfd+mz/zkv/2/EkCua
udhZr0aPI6RjYfrQyrd3vWOGGQJy2Q+LvVQs9SunGYIBU089ltjzU6r7MEZsX70pogZFuBXPRCoN6abe3dVuLP+HXAdVPw6ilgZ6
hQzR/+dc1NUEEO2Pxrc6qsJslwpYrmXk0/6zav5xcWgmB9I0YI9B9KXBY5ixo2miZo4Kp9VHTLcbCLRn9Gzd04yviRWbfnWazanI
R7S7YNdad3M/orUuDzv6+Oib+bSoJwAX0NgVn8r0Om3uwCzeL5wyQWejkgXIOlvXlHVBYSPpG49HY4cRdAiZIqS619LALqiHynnW
MYYAyD/c/v6DgFfkxuT6SKEH+eBrWsuNQDA1k69/9qZxdts2Wf9UI5ObB8+XpbytQpIeYLb+MiM5LtlzyjZ7TPsBLA4SyrLBDdjd
r10eEIPKlRb6MpWIPzChPwiYfv861KatnGrKPYdn+9Ep6Quw4kGxftfr2cUIoHTMixckwx5HHbX3E/WHcCYB+V+zkI7shpTZEZDe
92RoZJcOlwCLdEhcwV97f2Cw98a96/FcQenwICKExp0z/WLDwDJqU9MIvAjbiO2WTVLvyFezXP9kj/vVC0UMhl9WCZoCvF44II02
Sts1TtYSki1UXx7UJ+YGUCpFRNZNc1qOl3jEmbCMagifMd8n+MyZxpkKiNUdZz/XaIbs4YbkwcoMxcVQoSJJIaEoXcq+SDHn5eYZ
MRZpKbZvDy91HRj/ksrgcBfo6p4R/fN1mnFyC9eUP1oYj7pZ2pKXkHX09C9nRu2AxmPC2o8VWknNu2htoOo9ZacktTrZZ5VKoDK2
NjEKMkUjy9WV+WghA1kLsVAfbliXOMs/Fra9nu171sPxKKKMOSDjRYPVf/IrG9CeIhc+gUSwO027lArL4rXFF7QlYBq8ztWqHs+F
oEHnSqchTU2fvxZ6i/5LP1+50tqYRGxithmLTIei1lVzZQbEo4Kbwrj7KrP46Z7Kh6fWcaNbzmlkkNbXuK9Qv2zXG7NMX78A6NuN
UaaYAfpnXo9y5ohbqVzY87THasvi6Q9H67PG7oXgQ3zfVsuDYsR3UT3HREokOWnpqeh7I+irjlUxlSan4yfpk7QmWDnvPJTGXCxi
goDpMrVi7KoX9n6hYrP1oIdvfIr33BYEh/gOog3SJ3VFbwe9IIdTh7DSg0ynI1HhUroPxLPLe6XTodYl0fsb2QPbRjcbQ1UIWD7y
5hCTwC13NBwnJ/Py/DcssSqdJ/1FI305QBaFtXkb2eNx9bczyakOIOc3YVt41o58LtY5rBfmXQclEiwKphD4GzIQB2R7U5Zf1Dqr
CjbCRClA47/2sPOp0rAz/7+WEypyNN3KRynS/bCzVhLhry20ds0uWy79LaryK3tsILYZa9UX2+h5+tziUPNtZLvSV52Vu5jQ4snZ
SJp2H/yY+aTyyfoSHWfUDiYetLk+u111Wv+ZumKDrBPYXxvYXoEbBYApDQE9W88XVvO0DvS/MmSd8cQWNei9V3By3CQgeVj/YXvM
EQ6TFGOgVTiTyqFa/8ProZAN8BC7yKZOBXOqmFQPK+4Bud/g9BSjFEGC6vBbJJlYPmJ6+TD92vAr6xXBSfE+zeyTJIy+QGUkACUW
rkRGrjw4V9dld/bttITKeP5HxQjbGeUUiIawGrUsJaajt0UFwJrl76+H1IPhvl7sgSUnC3c9UC3ZiNcU5ezekt1OtbeL4uhbPFn4
Qp0wIYvOZya52+6RFl6qWpHK4cd7PIJZR8ktoGr72qbaXNrID6Nop45BpkcQ2Y85Z+Cg6yNGos+qBKwcA7Mo5JdhBFhNFWOZIgg8
T+7+ZnZSIiG3UWIsT9rUxbR5oI+utucDGesIjmearqqVPZYLOKeKZV/lHZMqVNiX8ftA/d4DeGVCAu2l6t8qqhQaqCwIPttsFHGI
5eJ4u7IgobCqLU/PyHPY65Gynd0FOYOrHJX0ZQHe93MfxvYQHevIGbN7UfzBA7fW2fjD7lI+ypjTHV2gNNXzvtn26xXSAl/OxR4f
UfofKpEaZogx/Mh+1mi/pgPKtUJ5zId1EBNq1Bh4FmMt4rNnWZ2NmfxzMP51GWAI1nOL35kGNPhq4UQnYP6EVdPz9nPaH167pv07
mwYGBdHzlewJ/Zy/Ij7VeT18JP3V4EtvnJ9eUsNkdfJ71Z6qN1ltF75l1Avc+mAQa4mo5uLqz4gz7/TmhAMUC6W7B4bb2mCeZ/oo
zk7uwAU+udqA5LmacrgI5yg7WgLOqqYgnBisDCXsojyWyKM8fFEK0XIephlCCvsZyPiyo6l20qppUG3vfl59ey+/e9bEHyelrZlO
qYV8aC4tZfy1hEbJ0Cr+OMgKr3mlbKTMKFONyngvJFt6Z7eqB1znaj5Q94YPh6FGFVhFX/0ZSlmavwrSRPg+1GwK+I54As/iJlR7
edfCYTywsaG55s5T91MYPtP3zCqGDnsrc7w8u7UyZ0mi2r6SryS9VNhqhff1ka79YSY8HClLMadXpa2+Erzp2sIHiA6yLLBo1aeY
aMOs4D77bb/o57pybKU9Chyvp6t5SEW1CO7+3j8EJ67KXyyytRHYRWZILOO/XHR98Oq/PznBiLhA9C8y4uhheQs7LTsQim2GUZCE
+AruZdXOT0ilmuYYZDj6xa2V1/Wjo6jWEnqefHgj3v2smQ8g2UNJeLZJzUWqdyXZnynd+VHSFfWfKI/weLap5nKTjSEWhW2kaRRx
uBfAuMWiEC1j7jdHjfnq1snH5tMnBvSGTY8zGkxmW5riwBWFyY3OQWPi6jAncT7C6RaPTHGXtmtLRr+ko/ZT2uEzwUWUM0iaGZPD
V5P55oZtX0ADwgFIjj88K37BFBH7vPxbTBL6eKOUQ11DvQaiA7jeCYdjUxUcx04+qMCcD1OPVDQhJ2+b0cFrMu2VGDrbukZ+AHDo
ykTuPv0OuraB/ykcEsZ4hVT5/kAaPqZWINZafivPAH4i5Nox0nPC2VhVftQ8pMirfHfScZzR5fvRL0B90PZa/QhX29q9sd4HjCmJ
PtL6z5EhBZoJL+wpKH7U+VVBWTcDgqe6J0j7357XeuzdHG8AfldQUtM2TWhLZ5Kl0JMbaO3bEOy34lJXK0EwohXofYLfgZ4Zuch1
d6edh7+QTxX5+C3xBQeyVtEZJ9zqD57DFEjVo0PU0k8SKFtyBg2KxEWM0Petkyw6NQL7+TV4uPpe/JVoGi3E8ZzwIBWZXLeqIu6y
339WmyCAKSD7frR2YGQXPSgTS4+ssZa6Tf1HqtYzIAWN0e8Kky8Uq2Pc0LN2eoVKEfvh44gIt4ErqcfNd6lSpXijJD7oDD35Ivli
Tu0D6C0UEKtG83rzk5er0AV5xJmSFO/7Ngo+mNlNQv6AVU+VjXhzGWyERQSvYAkCO2Lz8XSWbYIEkATvPccOlR27TgggQ92CQWU/
12OQlFHrrrdwP4u8FhB9LIeoHRvseMfJ5Yx2TlSCUgSrwg3XT8vZsi0eizBkvu4j5BXV1WrGz4xq5h6ycgwUSw1rPf0sN6lV1Oah
5g8RnX/E0lIR4CLMrOdn2I6xRiqrO41JbS+jpyasHYxVh2t4zceZ7lZ5/IKpXZ9STy+H+hh4wpndA9LLN6OdYZtHTvNwCGIpNkDG
MBcRMQAezmDH8jirE9gMI9cZ91GyFseMGBaFpOOcVfKoIkflERO/XTd1KUzq55fcYJwiUIMlmE4tgkfXJP+O3l6r/Hc8nKVVjsJa
G2/SYGIhALJqr+knkd5mS8GZIduZhsfF6gvsfOYfTrOfELY0bDe9dLciXXcHId+KajLo3KocUGwfMsaGCVG14atmrC3oVmcLBNT9
9ANdmTAEeNOJznppLv2HallNjJrFWhvhUStvWndmQBzq7M9VZOvaQeTOMTD7VlUGJA+3rUptoX+B8xp2qK9o8m6YVE+xCCqzxewl
NRUAsPeWL6x4PjnpAamFVSPun3tdOtXaEZrYRNPFWDp76qNbneeb5on95ue6/w9/8wAMyvDeF5P9oJsz4vhp9mWi4sKwXIKJTmhL
w58l/S6YCG2+SencRn4blNJj9FTiJ4nbFif10rrHz92jnRrKyD1fgzMjiM8XHV4wsdWq6pf5L0IT7GAKijiCYZVNbpS7v3JuUj2B
2tZhOFUl5X5f9U11Lbeq/tesW3aleve+NwSyUKGDgJoOPfcsJfBXpqvAUsqUof7wUZff80l6psLQum/BSX8u//EL0SlR5AVZ8Sk+
bw7Mn7Kr90pvtvAv8vZq/Hki/9Rjb2QV8iiSICCSaqb3AEQDX5RcXNHAffIfNJoyluGOQdUONnpk2dl2PIK5dT7wh/MQ6bpQKgFZ
L5VzXeSGS4KsuyNneRNV32Bg7l6qEJk83qXHrPdxHrWuflAtNsCuC0M+z5IUJzweH1V7dOKUoPvb/DPjlw1MycT5dnA8Dx8CKLl0
rCiPbwl2eFBgQSGQQuubKW+EOTdv9HfbGK0vY/h59ei/WiOlo/5ATbxwoxG3rSiDYQtI3UVUk6jIhWfl1coPb+wtkSK3acAPsT19
+iLjfixtQYaoeShyRxW/2d7kilq6ePRQyWwGekjQkFv/qGSgZetKLB73Fp7UrNHlpxKvJK6ZICVst8hUi96so7XgpG+ZuYnL6rFV
2lWfMn15QgwS80eiYGUaXgzx7CFafvpuiqR9EDuU8DhVg0dC0CxmK7VNj2zrzbeVAlvvumSvyIoARRgacopE2V8hrKGUP8nsM3XQ
5ejERWpt8svx6/eaPvkAnF7lDjiJ/iHS94QlJxpkme5pzDQwvOYnNlBJQb2w9oIW9d1zATY1g1RgLAYwyh+Fvk74UzSs5LK3+bOn
VaMh3flNsUz5VLo6Y0/ZPS+BaokgCht7jjDLh2jhhQVQ5KY4hhVPuN5cm/yvzPkYP12SjHlwjwQLfYNcGz7LGGKDPRkTqFFeLXqU
WTucNjyjkaKx3x/l/UcEnlaXCpBAKnjtz2uA22dzZmws4mesaEdkqEg0x5Hv28K1B5DXNoCuFO+YNVvcZ8KxMmzh7biHQ0ek0slm
BsUxlDDYCNtQ1HHv5k5Hlbz+RvoiNv05oQHMMdo9oJ5gyMvH5KN34DPOSUccFoCe4VqnWnTzxkIqZQOM2Z5ureIY1xh6ekIWV9rP
iQ8a+Sq2OTC9krk8Ycp5y2jcAsVgJ27ugBUjD6LuMsXQImNnvvYkdtWWy/ekX6kScmsTCTLk0IhKYvEeJD7hXn9YcYGwUODGORCn
zuHi6jgJKmE+HHqMJxF1AoOZIsdP/kw0eHeFFlFFSbzlvMVn29XOza0pFPuKen3CxhcfkUKRC2zBiOTZrSMs3OcwQ6kK17COvIOS
ujDbH4fwjQ0XUrgax8mov+fESPhe17WwqspGA8KZZ/IFjet8cLIqcZ7gLfvpNfK4gJKIOugg58TegUKpltVPl1ZATPeZB3FxrZlR
xAVYaFnq+F1uPsVpSmlK9yeQdLwpzP6eX+mkytXzXQquTfTtzcCuIXox9OUrXUwJKy3kTNGhYIY827qE3ABR4cm1/YxsfC18HROO
R/7c9Qtu7vopUSIm1/OV12Gy0zsuCJGAIGPT3YItyw/ZuU7KHHU5bS0dZjPEh0G6Pt58oWvXAvnQEY0tqHTf0Hn4DrZ6CwTJ5U9b
2pJds5jvta/vYb5HgRDwG8jL5BvmCoKAgTs2a9YEQ3tONPrElNGel24XPCMoBjXd4h0jmNCtjX2vtHx/00hbcOvvZI9SkgIi02pQ
UGLWXbt9CzTNZ/kdvILhtJ1fL1FLJaCp4dBfh4iy+2Sr3eBzs57HeZKGJUZ5mHl1duvD288sUsB0baXLXEvYjtiIhlTbQTIxBVio
E1IEz/h9eXVPJYtkDU5girTCFGClCCgJteyyWBFB6TASPdzjw6ZATkpjyl7xhbnHhSeuv552ou18uHdE3FIKSBgt9ZgPyYQohmiB
uKDFzukr/itxevSdp4X+BrWuhz85ZKvM1NYg3gLBfN0EfUn/PP4xxx4RwYkmZPk+Wr7HkIol2kVN8xnlJlIl/QaCiT7JINCM7J2S
loGzykwkS8mb1dox6/fjFeMI07EMjG121G6z+ifRys8sfJGt6vmmxpRgfOwQ9bEBmm+NxPuhynuB7cCk/EdYYaekg1f6j1fpUsSv
fQ0Dx0ej5Tyj7+VBEVXMkViec32svuxTv3pqRxH7zIk6I6oV+8dXPQVaAk4DqbUj6uHEo06DJe5XAnpfa58m4W6iYP2Gta5491oz
E2wO2TuDeGkXPBZ+ZgEWE4cin/0udXVljwl4FeX6owK21BaeWxxYQ+j4841Q0/nq2HvnqGJkeI1sAQM1CjTQljwojNmUgbdh2nFa
BsSyYlQYWjHybnTLBnTrZMKejkdPoYT3TlYfMGOAquxX7+Q/34k1bwP2I2TPjllAldxGekbbt+tTVvVrcT5M4wmV65Yd57I2dIXJ
JxdghvFjWbY7A35iDWSZ2Dq7bRz6JSy7NsK1nnbq2PeW6p4hNhQd0Tn/CK2Nd+JMAVFOn2hpEGFyywEZb+oVX1IDQcdOUnkkBOfm
hDFzq246KAnDuAUOE/+Jp1F6sYW5KU3hvqGIwuYRqY/yjjhahQtOe0YQzWsAQMIQiL7ohlBzHqY3mmZeoeC4JVSVHwDovf7tC7wY
JCoOfwrFjZWlIXScf62kinDZrOgcOlBZlCct2Ln5BDVGebIOsNoZQwljVAIIpKV1pF4VxZOf7tTvTbfM1H+yuIFVcDag61o/GwDB
OrPo7b78PfgM/lUNLxYpOBBlJmzCcZB+DHwdUaq2XKhJYJj2qfBF9JlfaqH+GtAzWDx+Cj8wvdHF2KIqHVOkNSdr1OSw4E40F993
Hy0DYjHrshLnJBgyNwQW0aI4SNCDv+y8bILhdZPbSH/0OPb+zMASHo+IUnqFezvQ0g9X8MogdsyMUKV+mlHE7PVXaTiDWYSvD+U4
++gZK7p5NMPNdUeutNx4+DatLG3R4PvGbNQvrBx+vMvqtgBYzUYLUGpfDz4NW6h1QqSDTpkfBWqlcARA4HhLWiQCpFSZnC5kkh+V
gobNuQ+pRT2n8HzLfMeDfHXhE4VqQltti2JyTuSHZrxJAmXX4846I9V5MOoeGiaLRIxwhx3IhetJENGnMzuu3nGLniDqB2GKvUXj
9h1afvnRMYJf0EyEpe1ZlPcJ+2aABeHwEU/of2sjObokWc+xCOmmMEZVTcl+I+nqHvfh5TaK7DRlGRAAI2v1pcyZLm/6bY7v8yIf
osejFJyB/YjHdYo4RSB6mpjiFcnADWlig1DbaYvIfKbL317FgOTntwJkhKet6ZQ3zqSyOmS9zyjdiiy5J+ayzchMYfdd/IXfv7uo
SU1DPBa8NnzU4Dyiv3Semb+z5SNFr5MvlJ6dIcj5bRZaZy++5azoE0SrPYQjXr5PE7+1jQzi1KRnLjJ+sAl0Pn4OmfcqI9k5z5K2
2BNTicqCIpDpSefdw6ck6+d0LwwFFk55jQD31HFwSwzjxo58rCt/O/iQQ2yfU4CnaACZKn/+8CqTpFm1b2XWYC6ZdJJ7b5NdeOrk
dxzBUx3jK2nVjZz6vKoJ1AGeOyb2rU56E6sNPxP3tHExA7FolMhYnATkFuuSk+eUpjZyUffYgGhUKIsJSyAdcQZWq+ofwsAxliLX
ZBDAETop7S7k2FSWuXm1CfJ2Nb3BI2oeHV0uUta9PCl0QhM4CBDHHS37oi4WZLB02dvBQqpFCHimbZmWktzrrIjX87boeI/AyVsc
oJsTx8clYXmgfMhTZ2bJK6UzXfdxtKHm+NHvpRK5g5Y4zGGvW2PWn6WWaZWAWj0V59b828gLBRFateQFQCYHklfqwBtog5g/fRAB
fVc1L6Ji6ni0nhDfvJMGcRUPbGwb4QedvsNOhqcvVGuR/VNUf3n+HR5LCVjU2a72re2e9j/JZu0IXjUp1mPbyp26f3T98hVpS76c
mQYULU0hfVQ547Oo/fzIq5giOTGVwO5EvdkCKUOrNyWlBKB/BaSgW2ygWjzGlFQwhe1RK9j4sulWhiZ17uyeD749p6RWKFshFRab
GgIq2ISjGWkxB+Wxh2+lIBakpnZ8YtoFIsQh+b+vCg+9m7j9fGtes9u4HpYMZrCQzXwtYb0tm1RFemM90SJlpW38opwkn0IfBCBN
VhMpaYP7bpOMeV1fJyIJ+D9uDQN9ifCtr+zGpm98i4CkPClKCmSeDxMW9hP4LpcHuz9jL7r9c5CAMaqoMVxNbpHDMrTc3myzDrj/
C5HeRTFh8IsKFyBOJpgMiAsWcgTcA5M5ubCND23AIHCaHi8CNaAbymrk/fX6RngrfgeAJheCg6ZMrA+rBrQNQ1WrEP0cCPodPWz+
VkdhaJBOdHFEsLAs+ePjwWLMWF9LketGjBtNEA7dgZlAo4y6zgZBRXPR8l+lm2vTdoYMVInV02Lq472Jf+7hYWw/UMnexTKx4637
N23pjef/Xd3IbMPNVNxtX1X+YjMiz501+FaKdJ/EXBZynrkz+vqmuGJDPFmFiP9NMHsUbzAnTND33gUWcRHxlBhfRIW1lBlBNZvK
A0YBAIuCh9uf1i4ttNbadeJB+HXB4iEXO8KXFfpDwd/4dB/G0PIyLaTs4P+rAVY04lo6ohQ1pAoWralDFR3yebZJZ+517ZOfniqU
akcKbJN0fh+6VY27o9KhMdeH6X1sTn+mHBhJKwxOu8401ISL2zXDCwdHqfQswAYhSAMkFJK9fxExuc9RdsPJM1YHyShPJb0+u/K9
TKU2flZRW4qLVRQ4ArJ2xjkivoNN16Nj5rWfdO5WzyB3HmO4gcf39Fjq9QMHmBCEdsrCEm2fOv7C3Qw1sBeC/4wPQkaUxNSZho/L
3YtdmUSzSXHGeB153V9ECRVk5oqJ9MXhKYgqOMEQga1ckskT+FCIWMVSBgcz34lGeWm+wt9NWR2qMjVG9ULlzcCTNfs1Jjord04p
b483ehGrg8A0gOdmEwG+geu+8CiNOKVgWnef8AV7xYcZq/WMOjTprCMBV3jRjpd9dYkyRmP3NHFzO6jCFaZwnxMQN+zj4eWHK2Nq
m3P15cT830yiaLW/uL3NnuEkmym+1482g0RCaaOOkOi9/5k0cf8rNeuWgmftDMnz/tVUAbusJwHFNG9O+/cmY0U+U1voJtacVgNc
SyIYY1MLg87COG0SRZC9q2lIK8kLVtU0cxxNJFm0fPTYoat9j7CSBgf6KLXxvmosiSE6A2MVrTHTvtL9a2tcK8E7fA30oeRlhT3X
mZ+FB+Hv/oi10AlFLjAmmqE9PzV7XeGSb2BBXaeCZsRuiGDMDHA8nDETNLNruQLaGfgLdhtuKRGZu7Jyshz2JokwzBcggE+JtGq6
tJOJwjE76BWbah7X5XJWABBAsqwL9xqbPfjXd/YnZSDLzJPyHetJsXD5wAF0LRkFtyT+5k9CWDIDUq7YFDEV6177uNZwA3GyBOGk
NbhH/pQAxGktljk7KZBVc9YQEubcpxj3LzCeaPo+m8o5lqcUvSD0aP4qOx5NusohFeXCNqrGRQh5GjuMWzcmjBVvOcjHGRIS7ifM
9mGG5iHbNrlfs1lb2oZXi6Rhtrowe3JFkWsofeoTO87HH8gi2KTKIHvmiKeGmORImhDyQdqcwMuHr6u5t2VoTGv95ttaCaazxjHA
VamRqhAwjnLRXfdgyyslMYKBIMWWCK4xbTpesgrxOgbvGOuM0nlImnFNdkWTLMf9pimYz9swh35gXen88IRSSTAZjwubKsj2Aimf
o6P0Mcna0K3/RQ+8/OLR/Z7evCJ5i53n4kjx4b0gPmxnhNZRcbbwX4n2QhS6IHJefu9likznIthioBC2l7moziChirdWtz9Gdivo
Du2UIPmCHJnwNQtW5BYrnKC+dEOl632PNVIrYch5nnicuJpAAmuZbtUiHu/ygLDseswg0s14afgCGe6zhGC9+CU4e5G59k4s/tMT
ZJVaGI1sJW4pp/+i27quxgaNe3XTLtksc6HAmW9vEbU1KHHj8kYjTwQj/7eAzSxZR7Dz/rUl2NK6Bw80pZ3bcmEkuI6ejO7pqBGB
9+UQbcI5Ht0BVnTxe97BIOx7GfDwZkCzrMcFAPM8JhtIllp8f0gDqrPVAl+fnc2elULIHDoPihPyp6bW/i/N3FgwS6njKWNAzmDW
hxbxYZQfjUiZ64mXM3EStZRuKwt33WnLRj9/6BfV5uMm6LcycF1EjKxcwDoEW4wkisHubK1IzOgwLDOM1EI3rl2zy9Z8CejobbMV
TTyf5N3ffAy3v8PEqb3Z3Xb2ye8wcFhAMEP9zOOAqPB4G0SRxpIUD9Z+d9SOW7bFTwUN3+w2jmew1yr9UpmDG2I67iC/vdPa6OBw
MUM7aNLzvfmDBW9LikVdeNfaLEpMwLrlRhvxMWrEw/PBg3s2Fv0VqdWJQbvFX88/N1JoFuvIjaLCP01VyP/pb5ExqRxVZhROiJm+
pp9IRDHYTwcy4gr96xGfcLSY1y44hmyDzLJDGEn1Gg3hBFGvpOnLmygWm8GUmWS2WW/NMl2umgtFK5QZMUrmbTO8O9XtODXLcr0l
gM8N/pZSMdYXiKEW8n9SlD7nc9AP0sUQeryVKCxMW/iIurfaGOhmrUxM83urQGSP1F8icrHhtwZRc7Wfb0xlzbDK+rSFCoOSxYBS
3ujX72QF+Pbi9kDiC74OrNsXwGPNt0UH17SX6H9izSxHQiozTQ4YkAJ6B3htt1BZQ4a2LuPnigFaxxlfzdn0/EHYs5nxrYoLj/3K
GkJGVlGXRAud2Puu+iHA3Y2pprDhj2Cgp1K9pg+pBmAyQdU7hJe0s8O4LCPKJqG8C5FMCbdQoqBpQftdRAJg86mF9qlCRQYh/vvb
4RBR23hUU4LczelDF5DxvCGUtvEF5S0P4qkGw1/aKWrHOBvFUjcs1oS0yzhOqc+OmWmtWh6FPpdWgjyKzod7j5cGHCrFe0TJVVpS
3g0lAq56JTkhuGCXBQVjWHVMTuw250WqaUBAcien2JuUTpxHiEhUmrX9msjY30HejcrnaYY/5n9j6Jt6Sm0zD4b3Yo9B+IHP91Vi
1GdrZCyHDNGEvYpRElAn+uEnxhSOwjO9jRRmIQmulQoU0ykvIw3wOOuTH0WlaPA6kT6VXdDjIhJAoJDb2aA/6aLxzTJishe63go4
kAvlLQYgJxd221Hzwncy3vu8o+nLT+SJ8XAl63GVdium0PQKTqKSnOfZbuZjiWLA3LhmRPE+71ZdFTkHxm1EACMKjoXyMfebihKx
/LCPwx+sfx6dHFIPkY+PCAVjG8a7tGxn3BhSd+ymMwFKff9hn0cI4zrfFr2XifvtHqtNfUne6tC5aRgEgWgfPS7nknaouYqOImeO
DB55HS4Zl0j0XzuZB9ncMT1H7X244sDpO8LaWfEY3cR+ZOYMdC5yMSHM/mn0DolRybfNh9R7ef4GsGZ3FxRxx9Spquu5iZy89+rX
1XRHvxQ7y7kJTIJvaN/MkQN3GOLAjCk4LGvIu/9i1kBCumpawVhFiAdcEY3tfsGAZ7j0jTUN4hdBTQSJ+Xo1ARWINgHuaudjfMo+
JlxZ9iE8em7ummhFuVOVT9bp0ZHMzvKXR52Jb4DhFq8nqRXvmbkov64svSm5JHobWeNy0PX6bGbgCd/VfKDNBAjodz3ucSP4VCfI
kz4L3HTBh5Tz/zQbkMf7W9SNteNAZ/7fbELOFIPOTCUdD2ip+XMHLg6tJHUwBgqZYkWaDAvDF4LHBuYbu6wOUsNfj3tjYwuqa7TQ
RWHt8WJKPsw+71ZZcbRd3ZS9Krtjedt07eAa7J54y3ulnKV38YhoHk/bLiZfgjFkkv1EXazBm+7bhG6ktdwUyERoRG/sSiHcB1hH
xXyNLfu8v+ntuaZ4eaTDtmUhR/P0+SpxQrl6Q2ByHt8xP9u8OAp0xZt5ed31XIyt2xYQUMOpwvU8YlH7a1DyQ+RdxrouS51ZhDQD
H1+uYb1wKmLVKsAFSrkdcwRmwk5hfFrvdS5Zna6mhzTLam4CvKyL3pVo7o3k1zQAffsQVNQUXrCgFfUjDd2xlgDrzKrSiaeqz0v/
IAZ3JMlUvJQ69wfoSP/u9R3GeoBB546TjRarqywQ/2fvAQcjszg4VtU7EL4alaTuQRR8k1kyXbG2XLlHieo8FaGsidmSkb0zQcrO
g7gEFChfX/zbZe1N2HlCLESquFbdic1K2vBGXa5KQlzeK3OzihJZY54l+JFUh3qUGk2N1uFu3yEh6y5uqMHhJqq6xlDzOGdsxLq5
oYH81Jo8Ls/q22XLb7cHZ9wTQYsgXiLEA5ojK5EVzBpCD1n37Co2r6BnsSw3zhJFFvkLJEY0VGoYNG9T22uT7A1hiX9Mp7pEn/LA
w4kEVLj3oZayfkTXB9/vR+1MQAaZk70XkQ/TfK3YCcCTNnhHhomhiMdfqZL+w3mZhJBaIp3GRoE7MFGAgQ4mX4Nw5407bwTFeucO
Z3jewWuRxNIsKW8Dl/WEeKOvzhMXCS2gPqqD4mbM7ASsc6Z44RTtg9p4fl/o0p5SLYstG6d/JZqQklRfByzMSEQJDAGnhYOXmcME
NmTDhAahRpnx4uuzKoCtImR00w64M/pZaQmCLo2wngpUb6szojKOXCqGd9WAUcW9cYbgGI1M/DBid4TsV67xLO87x8gkkgKedl/3
QVt1eAqbTbeCvIfu72Dua54fATLj2Co5kV+f5Sdv7ngvS6jxBxiGxuRW3Pa691+BtoNBisswpnV+Ua93KRlwkkZNMcz4bwvtCidR
gG68g2e1O+H/GodiYiY9zYMdVKnvYf82rjzihvJQydQzBv1gkRxV68GzpCLg02kx0JLvfmsDEy4XKSVwUM60A3t9X16m0XffWFnl
Uwib5aPN/+e/O9vdwIxHFdmsvdN1qzJ7mm2uIl3qXfcykI4qVd1pXF30Q4FZqApqo/awJaWgwwfcjqFupMYneClvUHvsuKfiXLRj
CFWfDXMUNIdKo/lQVD4xZtlxTEWkZ8+mG2iqucVU3mn4eC5sreGEjJA70LztjHAonxMdtGQCPHmUN3I5oDVeNg7JKFQKxLEepcJt
nBOFtuL1jA12qq/FxVQ7jYXo1qUZ6LNE11DxPbNdwliaQPq5uW1nCWWKjG3r5r4c9i0uB+AUPsNmHHaK2pZ7DidjabjasRjexK0T
gEWa/dPlxOy+mUXndS+7SyNFcSN8AmoSM2sUqW2W3lT353mXDECvAEiUpzk50/rG79QEHCdOIQovzpIvbVTf5rxapz6juYXvOvZV
WMCcxUCDePkt3WW5n7fX1s0uiP6S2ziLqtTqALY9xC+73rfiZzwWwD30ZVO9Miic/hqXqgApu5QladpqhvHbKM4qgDhtni7lwPGe
fWRj7sDetZ5HJvri6edbJm8oVkIdfwGbCh9Ux4wtRKMZIYnB9ayVm9ULBbDO4Ih0FjRGLb/aoi2CpZkiPm6s4mvT1SR2cFvmdybA
U1J1DJMMogW8xT4Ccl8Fz5mfrWuGorwGmRYq4SoCkXWDVXWzCNEKP7L1KapHA7eoSsfqXBCyR1nL92AGiG0b2CIuXN/xXyIjmuYC
ehr04mGWc9GgBFZeD8Tu6Vd+Fa2tK3vGPBP8wF6+ha5UUMYM8qDSX3scHz5jQUDGgbQ+seEw1dOLW5jnqnQztxmlurN4jkU2B+iH
oimA9sQBezI4e4xv4nFABV0T+0R1f6mhYbgGlDBOOR0gxkWAryMOlTvCybXzMRc0prVU/7a6pU5FBaBH7aclSOW0tv4oIke4K0nh
mGO3ylumI/pPbj+781iCjDA/FaTWH6tvjBHc0uSitMfqkWJXQKopWQbtN+X2jCuqnxn2PkUXOwDFTPmdyTv1+R6kPXprRZmuTsj2
1NVfFycA3IhSbkv2E20ZqX9YqEj/LpmyKVY2VvMn01Eh4rTylnwcRUkF0t2c340a0M2LeJ6dgj0K4sgS/GS1a9zkb6k0rnHgiuDw
3p0nOug7KZzGZ3OYCZ9JA5jHccVXlSlGw3mElBoc2vH4cSVeyI9xK7TBDVEkY0mSdaioYbCmqbmCeqOKRWFk8nw1I2byx2ANaijw
A6e6SQ0vHQFulJQ+Bu/jxUt9COsr+2bcuklBVH4ELYKpQbrUEt46Y/1jfxIHUEfmJM/u0cJwU3JFZe4lHaGsGCA/pcA0zLaXjK7q
sgVbCsVM7qe3QqsdXFp2vRAxzmkQ1z0Xsa40eQt8/1NY7HQMQWdlaZdFMMUStoWgmQZgHmItzIXTz6rd8MzbMn5AeZan8LoPnmcT
fsx+D10hiBgfaAvebVj6sWbZ+4rkHib0t39taBvd9TQnUCT5QTrpt70QcMqiMfSFk5/PKm8hbOLRHIrF22jkUJc9sQptmxfOVpGh
/Vlv64nTFwRadhzfJX7gO3SxHHjKKL+E47axYO5DT5iuP4i5ui3hdzr29RiPnld0gm3ubsXKXzUWZA4mC4/jc+g0FKCl1xgAQ0K3
/SyZO7VBEDvskNv+0PpACiheTxJ1UIm7dFqn4CeEBrvNInodQ8s38xoMH4cu99dRPmzciNk/L+hvxaAo/xpJ9LlJSBDOj4V/5eY3
AQ/F5ks/aatGbqVNy4W4wqBPkPuL0ZCAScHwGpUs+ud+h68mmAgpOGK6yUPiC66zqgYYcvUa9louUC0I8+ifbIPcxlI50hLs5z10
rP+JjTPwESygKCG92sVyZWhOqLly7B8A2cuIxi1kNPHATrtQVF8UJY7iKvzdm4vbQQau7RG6wiU0rI/wmLWq5fUm9HXRtLRb+zEs
qyA095CPSC9Qc9ccs3apkjyj4vMrJ7xLuEq/UTScSjSaKiwukc67rWC4suKhUfbDJiUXPrTkh6wUNPum4TeKnoKWDgxxKpiBMK2F
e9pw19HFWKPcCgJ4BNZ+CQCOLFZbce0WQePn8g2BVHQKwPEZvpf4QzjRnJPsx2eM8R4J0AKzl/pTXxZfJ4a8qnQ/FGBRRns9Jfin
+tqf/OleQtmi+rRITPtGfemyIdb5kp/RneNvp27LhH1WZgT+qFcL9k9fJRxqxuw6fva3DXVZNb3orDBJMs4CfcyFv0WJzVs77pY7
Ou3qa9Lfx6Uvdr+XyzDBhwS/dRtIxjR0Mvpm3shI6PGm11BJQzzh8BfojS7fAKJHjxw1taqqzBR6a78q01ysS5QvmrwdqkmVTHf+
IUQ2JAVuFVkgqCRNM2Ae5TNopexF8WDcDebZPhw5/7xQQsE2jEus8Lr3XsUGX/ZLcMGtjd+bTWuytxSYhyjXJRKfrHSmF9uGoNJa
aZy/bB40RC/D2WoIQLx9zmFiCKzNXEi5FUJZluBdoptylQUqZ4KSBQqpLGSKqMSn1qO9GbtTcFu6ZOpJVHb5hSa+vaOYNoV3DtZt
OX/4BrRsCNJw6OlEpKVsdTZK2l5FGres2nmpq+ak7UjUvvAQaxEmrg0j2ofkUgZMMM++UVNPKyr84wF/yERdKaSZ8dE/cj4VTMPG
gjOTFdKjTtYPQ4dLis+6QP2ggIlJPsnlDIfnIItb21UaFM5aW/8KFccCTN67HPTQdrw+xKYaHEqCmSAvO0TDpGlDWN9yfHq9EEYj
Rtgb3KzCS0lpTC9qGuvavz7icSi26gVQzFIE060KBM02vYdxLISsRWJQuHIfnlHTcr09Ac6BaJ4xvp4g66c2apq8/pqnT1ZWuJfR
MjWaT+69lzJo/0pYwvOq9THKMASfbO9GNZ1vU6Q1L1XQ6KaG4/w+2LL5dZObFLixofiUGonfOCHncVRE33zixMoBkdvRMDp6D/XW
TlxCpJWKxEAGYG4Xl91pECmVyW837LPgKiL3eXzTlRpqeQ2Oq2+TJ6JBBtEC/TVunPrSQ9onxUOZFBryWN8jA7Ie6n57xBwtkrVU
U3PkjETlqGujS7j4eQ3b106jETzpL62YYNYGzlDknNSst5obu3y8686HRVCsPt2dDRdnYx5JDle7CRCQOq+JhZoOdoOsvIoLPuB2
05GC2P489iGvtGTm40OpBL5cFm0acyUEt2VXEe1435SIQpV2wuXA82OEGosvb+mQl8w8DoTOajTv+ZP/uKzmPVqbDe8wGGhXwuuy
AfRobEeU+KYcm58inKf71j6D42YhbtVof+MXirsREGYm38PTxjCPYWBZZyH8TV/JUcubAaJCsYCMy2t+3jdZIupKxGzI4KiHeTQF
RupPcnDjmPJVAw7R/1bJIZOFb8e+FnUocQR33Gaf5aL1Fkaa/NjEcvsFYtoO6/BZcEq8zNXfWZB1HvpzzjQv09y2bezHTp6sh7Lk
PGMGwkYAHJ7DIAuJytPe5X3VbgTPsaU1qK9EshtObpscudlVF7eTRhiJF95VajPr/A/olrYijAHUtLC+YU1IzTeQzJX8dtpgcK6L
O/dbML1ItDdwD+xyqfG2P5I1mKAIr1Tjo7/GC+BC6ziYGxI2n06+JXXzYLQd5g6KWRwxjGSkcvw3km8tLgS+cggAhJcYcfS+WbS5
Lh7uEG3I/PmXPImlilaItyVNC59R5WwFl1T3yt+Z8MNy0Wh6oi/Zfx/fRUogsWvdxJ6rBTDYOKquWhQtGAUjqYoLvwOJrEy8uVhm
OaQqnv5aqJGW/OfnlAIbGZZXmQFTrPGOZXr9W8vqMFYHUPx10Sux59Ht1Z4nacefoXRMLD6LiIUQScVskZzGw0LERhsU2ez+7WeV
HmM2wdyp5TeQMCOJMnkFFzG6b0HO+eEl2jAIdwUmab/0AMIjNUK9hC7mbvPcnD+hnZnUMgJdYAfvwmM9Fwi+CYQcxuOpS9fVeBqb
PPKQ+GMt1Xllr9J0gKi8DedupEemqS5N5xbbu7DeqdD1rMTaFFgrj9PnIYd9A9E+81HAOsvRTlU9LFTEzDAvD6zHleFCTTP5bWA3
/kT1324bZksk33+wnWYjOWszW0QbYvvZYdUbkoWf+y2sXy6IreXyYs6X28yFJHZaRsSjKBumklas7fI5/Gbu08+uW3d+a3XeRqfS
xk5s/HUXAZXyeMEbsOo0Wnx2op0uaAXJrYuzR+nGogK3AcO52S7F7KByj3OUjXaJWSuKKxZ5uLPIQ+aVTgMbtiBHFYdgkxncfZ6u
lvZgUfXHMG4iiacgD/NQC+daYNgl6GQatgQdjT1nNXRm0EPWoKkvMq6L5cXFOmK5/5AY0YWQGkFfaNdat/X8jSgrZTcQMMa8Y3xk
N4xwZJWl8MBB8rQVvx5G+y9gmhDgbbCef4QQYZOc7ELID6dSma/tznUhIyAPsBvVgIXd5Qmz+/6m+pkae5klqH1g/Bx9H1VF3Kcc
4KSgMvdKablbIxGNqFjYtssJSGy6FygD8zl3UZ4i7CoM0PnTdqxqEVmH1gCW2SxC/gGNdG+3/z0DvdKXKNB4AIdTJEAo9cSTNpdn
jFa9j0WuXuDAQFXwSerm4Ms+1F1t5VNyPR6Mm3qpztxi0jP2YZPq8wowAS6nvFwkLjyzUBGv9nFUfXe7NuTR9+117D6BH3IaaIwL
CydqOK5M4z88twjueafLJoFJvdpTRB5yEE1us3TDZv3FZeceu2zwKyDsjkQCTJ+H5dHmpUsAqR+oZMetyySB8fnoL7IPQQy1gjsQ
+xETTVfymNC9dA3DbEV6ASK8sq1k3pCKF951s63Jyte2XGIhz4lpHssU4sFXVBSiWU83clfsfhVT1W4eaNjwb/KTMXZpNnnsXEq5
iIrS1VH3mfWknA1HrnmyB+9QN7ACzHdqkOWuZy9PLAc5aRql2GdGC/yppNb5vDv/6CQ8b2G5hXRXji5eLth9Ft9msICP/mqUWGWh
7FNSFcII1ot8bDhG27H22INg6L4U2ALkD188wQWoDPAVHjTgcHBGiTqiEBzw44n5rZ6by+NqjK1SP7aiJUHVufvVUXmLDlI9Zgvo
6dJ6Z5ze39XK8kW2l3uVRvmi+Ypg5Al8zkinK8UwrbeoInKilKMv9o+GUq3a0UFdG1f1I/kxatLWdFec93Keu70C9TWaVphZvsIt
jpAv6E61VVrq5jAP/ryzeNBMk516cZM9fITcbda/4xsjGBqlnSXLeDTIARRmQM6tXptYLvX1UAb6ZzUG5QvM2KETbXeSbXkU6Efm
KMyNmPxAIjY8MQ3NQmjKsQUvaTHADDhi/1C22ed5RKVOqBskq/9CCBZn0t+QnZMarlz1O3PAXWgPYH2LjUhFtzQ/XMVEoTo916xs
2utmmiiLQ4hoCyydhsjUDlgRWRwamwkc7rKxajXQH8Oh4E3H3IQTJzqW/3nCG8e0tyJNO0r3nJv6cr/KtQQ4ugoI5iWgyIWmZwI/
PGVKkvlMREGhd0i/8uQNPV9OJ7Rl4dWvRzSS7Wfxpws26mGUTWlM6EEGjT4dyupfWVhdJLV+SmnxobZEOwZVKN/HqWCNO/Ytz56V
rXoVg6klfURSblYq1Sog9lTVu7O71bCgsuE78iOoQa5Kujy6Yxyl/6CHll96UxLNR/M5q6gCKzz30xhq4/9bubm8m1CuHx+n2pVf
Tt/gZXIm/OUNq0+cj1g7GzLN2PQEgOUJ1S8J2couVupoXceW4dtDdVzOxjIvC697TtVxzDSs9Uvn1R3oK0v2nEJKguOjIZBxlIvK
sKYVb4p7Cqpyihx+MCLYuELCvpSm0SR8lP2ZTUvSNQkmd+KpVC7w0FYK9ALid3hZAW8KzvMmE4oWSbQZ7TA8At/SQdHM4zGFqjgM
xOxliEDAbsKVVOGaXYklGgo80RyQV6B6mFKmYsWvbg+ett0uuHgi/83mAD4iscSg2YDh6jsVZUExFMuKe7NIa4N8Cu5hVXUdITDE
e9nBn8T/+7hO06BraudOUcMQBXWRGHWHrxsz9vxGtLCEtJJtuH9/H5djJv70TKbTXoyFtO26Q2iBAGqitEdxy40UjNzeCauj8Lx/
JNRGu7A/sDJwjSOTUhRihqZCbYwg0n4TASnOpQSWZMtqwyWQkBjgsgisVBqco/Z6ca/dTDwAbnftfBWoKAK19NeJHBfLsvXfvv4h
wpTcM0m7mWLmUfPejLRAQZ9aEZKNYVQkBdkeEi3ShmaX2O5/pFVg35yr5iApy9djqZ0pYgjtC7LYYriSuOV30fjt/gHFOOc5Bucx
WXGI+/tr2WW0Q1oPn5uOxftExhblrmts0+bzafQqV+RPp8SPPGOeRlJgnFecXgjSfFxl17XInmAzboBG64erH76eRiQMF6rl13FW
ZkSWcNsX1dc36ptnCcMKx0ge3joq5V4cZImYrmxaNbzw6hj3qEgWaVRFjklyYZjM21CD2ebuQKG6NKnou5JkFmfiMkENCkrbUadE
M4DQ/nrLbYdXxgCB+zJRBF6dc7rffvKtZYmQgEHNXrHE/H+mw6PqdShxKWk27Fbhwv4MxxHlDTMiQgHR2A9AnUbQTU9FJnrOmSDt
zeUhdS2H7k4fet5Jk+G5ZTHPnyBxj01hMc7Kexm78ZLAimMvlsB9y777Jzd7fusmmBzrvF1ZPWJwvTaxJhZGF0GojhlOCGdpGrlc
hEc3cXaAhQwZygf/EX1heYWWTNQPLUuZRJKnmF2u1xSeFY6jSAUQKYRRPd4pzX2nsv+iuRFStliPCBsjpA/TNwQRiRmZ2670BwZH
u5lgcV2kCPLcQlZbNpfq3EpLIoLp/0wbyNUnJ00i0oKEcrhPUXAcRCIE3slpGe4vFJsR8JtWe+UruD1qh4jtjjlfJ74Fie+DkAhl
95e/gkxkwZcDTHf2W7dhBZgct5sn1oBzLwn6y5Ea21ei8p99dHWIAmoOLnP4CI7/ati6nRW4GEY3txOpCg9EUPe4Z3Q+kMVwrGFc
9yQdeZyAl9E1/RiWnub0uV8qijcRfBk3ArfiEg0PTZMybgTXPwbFq4frWBZrYdpHXJGlXM3RR3bCWmUAy9rOyh4RUMZ1BJgbzTp4
+HxpSUZrB1VQh5314PPQQQskJVfOeVWjhBkNu3dPea5RcPL/BaE+b5oCZ/cOQb+W6Dy2bRAQR2qeED0t+S03E23HDZ97iPeHbywZ
TSMRuyRcXMKDIun3PLT6wWO8jjrxVm8PZp+ANqKylwcuEltKh3JX+rB9tDTzMaExCVyN7inaPXDHqsmItSMtb37312Sq+ReZOaEa
DfGnv/3jCoAF6ToyRLdsd+ilphMqMcXMjNwlIbh1cw8oV+LQfhI/73GAqQUEgnecLoQf9Yv6Dn+PJtUi/lsDFewmGrQrRYStOt2l
Ws50WGpmhIcS1SdI7Dnz10t25Vi4qLecuoZcO1/9KTvRFjBxv6oQS7VMFlJyheC0eHdJcwDnfd672u0YmVvIjmuN23AMNNJ7hXj/
FVB+twBo+s1knL8KGeCdOowIIbq3PZ1amhbYvWNXoQYeWLrvHYr/1zn8yWoh0HNXmGrNrbeFe+6f0xYlI9CynqgLxdcB/RkZCfPv
PCbjvkmZML0HHutEbIucFQyrZfREcS+hMHf/wacjBzGNwuVp8noaJO68VpLtyvLTz+ygo9F1IxjAfpWYo+ix6mlnJbtNYT7xiPSf
KeGHkqlFDBdc3CaIsKd7W2JkKt/xJXLur8Z6djeP6x+PRbarj/7agMg+nCbATMGcSah6wZ5y14ttbNQXLKWYPe6IAe8TyFVZBbT/
uo0ar2+Hp4Qdw2bWHVz/4+6rdMXQRdzAF0CDnRnzPWsZ+pSTpND7r5Xxi7y2Vc1Ka/77iPx/wlBV0ETd5JhnUEnOjhe+/W4SUGbF
m7tkOwuk1NT4vv9MLqdJSm/L//7TnmxXJkky1psWNZTrVJd6omhQfo/a5AbOVjXNb4g+tF0Z9mn6u/j/zcR1KWIeyJx3TUS4WnJk
TZ13QJDM93X+lO88mdejob+i93SPB3sBWzRmIKbc14SImS7wR20IoSZY6vikqjNtcuQQxeUhB+7PXPEPpZkUsd6+9y0VdM/lzdy2
1MAirze0tGgI2AyNiS6iZmSFJXDf9Y2VFmKPCUZBYfNhA2jm5SkR+bXvq8PPEUWd+8GX+/ZZMry6K0/qx39rJDHUn8+n9g9YFutc
Zb9NvcikDRV4eisJDtCATuXah2YWCC6ipTnPYH7oKr2oOpllZaoN/j88FsLiaLXTO3/drFXrTafCmVx4r68QWuCwPXCiYMKH6V4P
OTVJwG1jn+sD2T2NARzO+LKJFtwjx8xXKzvgJyv3iKBTZYtE0KQYpsSSoNzf9xAJW0GEubqjQoCPXOYazQCuOVQdjqLKiwCCtBQQ
s+MWM706Es4y9pfM6Rg2GpVR117k0rKi9/cQEbBhm35Dc2M2nzbsClvbahDCx6/esuC9qlPAWsI6nA3GRAd2+Ky0v4e6vOaTbPpC
whZXHFQH019reqOfkUsIqcO9SLrC//J9AkiU9p9OhYizuRl+l0pE1z4AxKKwcbXkHLoFZK/EMHLcczUVQwlAtckHEotlatehfUMt
48AXx5A2rpr6Z9A3noDrJIE/kZhCteUNgferR0Pg8xdQRirJweKpexGvvQ9WYKex0q1r8QULR+xe8JXiPxLyk9oEAPAwxqbqSFik
rPovj4+c9v6/YDaPWa7Q+nGEKYLNTRtTz1DREZoi9LWf7FcRoQRfQf64ePfL7MpdNvGpgAbP/IGGdl5ass/IR8+PCJ7iRUQmmCKX
QglEhsWc8eXBtIAIzuKGUARL6mGXq8iIMCVh8nLrM+eyyFSlo0GHqeJJZTpghiCiW1sVKpMq/x9nnks6UqNzWl+ckFJdBDj2grU9
u+f7re1fgMzWe6O9G/CsJX+yytLoutYgKi1T4Rrl5UuWstzSqe6IxeetGqFh/O8pjeYOzjcO2yJglPcdOthsVkPXs8MdOxtl5UsK
zbCCZB0GCjEqHbobFwcyUnhnPDDeB3qq6FpOCTMwT32v3q+/v3JVbx/k17V7jkKrb5zy7BZVbyD7ka6wI4ronmCDsX6O9RHKLYsg
xpUwqP2e63EuJ2FNoMDZoz8BpFvZ6UyykgcG9E1v/GTb5LFv9Vj3dDeGiKejHdzIsvRtQeNyzkD/mg+Hrvc//w+EJrzBHhrcmD7X
PaC3rHmC+/gcnSOd+/EGGICD8uVq4yMvgJ/ZNbmSuGPTjYoqSIzB8jaqGiW5vpAOt2qfmDaL+onVZp1N93jGeYDx3ctcZ3tNIIcL
hMvuXwGb+C0bAWi2u9YW2q8bIzHglb4tjANBmsVphQTonQ6iISWXOKvnfQVhqPwK1lYYC59a78z0djvAy5PitRmaC8HXuzbSgRhn
Rvs5FkK3uIMcgZGejlRYHotvgxW1KQCfNo1rrqLEYyVsZZ+zwBfrr9SLhzBZ1a4CFlob+442PFK3AmhCZVoPNd/xk9/A41AnQHhz
7iowVsuuP0jxONkbbGLTT5P5e64c9OmyJppCd2OXHjzZIe61cO6H8DxJoKAObAdL9oOk4OrA8lEULJywQxU3hMzGTMCRJdBBaffo
LXik843rq+ETtnGCo/1ZQIafp0YvDlvTQfB8uoftcJtLxeh20t/lKLqo5D3jY5YxKq3utwQeeceJ3jb72I5CtqBeTFtL3HzSIvYx
qnHyDLDOCXNXaNmmZG/zVO0mzcOyqmVA7nZBvh8VeSQjn5MIuMd572orMxfF0i6PPhVULxyR/FNO9gnhToH1ylB9V/n86mrtXJIZ
fR5V+qqDrL5Phnp5mKBerF+egCqHdMiCUj3n7GbaNIzHKBkbmArpcLkgqHF9NmWnizHUoBTKogNqAvB8aSeB8tvW2a7qA04KD6Fn
9AGID1vJIYzyeR0sxU0GXCBJFxUR09PyjoFd5ueJ8d/OfgO7cf5dOny3Zp+sk481qyo64uBocv0VL9MNbLS3p+pbRf4Wu1dNhU/2
fxlcbcaPglHHFZu0vwvIaRHmpHLuHawiUaUzErPHLOmqIBe7HB5WznaAEHTcte2KGXkncWYWJbVxGC5qNiPNdKVfwOFaKCyafGz3
oNGrquOxTKQf6zx6yvjzYwjDLLdcifLB21XbHZ9CiWSB1XfAEGaitN9vLE7SeWJAYJamtFJgRpN0qomibECfMh+JqUq5Q6bYwxx/
Rzb4wBLxrV/zsrd6312KyeoXpKlZOifZejTzL/zfM6N/Jec9+iXTqxZgdT1a9pEwNpvyqGAfaz5mrTPXfaLS4q/qeYGYjz/5dKiz
2hUSHqtRb/h8ODTu4IOvPJTmQ/DgNI61iFHnv7m8E+hYnT7ctSDKhepShn5wZvLyqc6/QcpuZU2Z3meXEAooCJBhI2WEJAxc1aIs
x94T7I/DNWotWkR6r7DvraY5/KzdJNtRc5SatPjLgF4tg9YoeS1kykUGRl71TfLtPw1Pp6WdCR7peSbRZnGhzcj8ppD8UFpOkHeQ
vZAok53zF4Q5QrEHPJLRR4HwVZx1XzO2O4gK52dD9vykV/GU1oa3TLzwbDfE02M4ZVBJU0Vr1DPROjhpzkMwKEv5FFF3JkMAJqsX
/47Art3eF2KwgOZmX0viE3/w5d81+xcvGOBVooJB+qko7YX97GlzdOJjhPuYWuXhSEZgTfGnz/bGV4IJfH8cj24V5Daa4P2HrSaJ
gnJAzXCphIies4SZS70rZDxx55DbHwQVonDoAQZizUiejUiu7lvS5GN+duQTLzNZ9aszSGVjuMPOpuMPCpwHrJIQRwfWkF/6O1nX
yacYSIY6MczUv9i1e2CyWkeAcDMNu1AAa1yBVxBcB6xUkgtJuki6zVqKiCHBDl5Nkdf2hnESnpegH8L2XU2DIFZIYI2foohRlYaT
LBU3Wtb8dK5Y/cqC4fmr8SbZry4iAIBmrEssDqkBFiUV9dzQuyU11yTzt6xjXgcrVe8brqZcZWm6egiULP0bC5j0cJGobJrjeksk
ecCt+5YNwp1kJMCP8ay5q+xrEwnF4W7ahjhH10W4IOe5OtzCwg/WKMqItqbL8Ekn2+I/oIJOotrK8RYCO52UwhNK7DW1SgIyaaeK
NO3w8ccn7KSOqZ8O6Uh2ezVu0JEijhwxZIbOgXCbvusjX7ShBfR6wIjI4/9q/kCJ+Pq7bwBGyboOMN5e7aqqvRvXtTX0Vhk+Nf6/
4+CayBXPwcXz3t7XsTt5Xqm8CtA/KRWrE+vsRi3zzqWbLyQCREUk9VOaaTRRhyEhYpCvPThgymDp/kzJBa9ZnuywJ0QX+h8NQCGl
DZ7iLIvq5CvrhPuJ086DQsTq3gNSP+gZfiFFNhqFNf1Ug+IQbqgpVGJNNbO+K4N8gdoLF1TVKpr6PCv+5S/sBZA8LjHJKeyjw4Vf
nItZ9IOnnBC4p3IQP6cT/ZeT5aH3/5BJ0AFB0gGrQqIstMGhkGxArrdsU1N34/AW6bMQwGHJGpOyYpSvGeyLxtMErWWXBFDE5cdI
rWnEwKDJXndxx7fQ3I5Hz0EeSIA0F0ombwK5/dAkl7Z05YWE7AOI1P4umKUyaIGFbO3xhD4YhZERWa/JcjiQtjFykswJsHGaZNhc
JIqfSA9YpkHYp8ZC+5dLnUK8Sd6ghx8XEglvWkEu24BmXv3o/s7kPIZXj5rn8rOyqN4EBai8caOSrEm6zG/dZ9rktr2qo1fOMf5L
U6Y2TcEwwm3DPyttE6QG8w8nnXhO9vRBdib/1oCdR6j9Ysgi4HzN2QhXEKz2voOyewHOX6vKdeq4KfFoDooyUPmUKOyWWtTsahjK
MDg4mKn43fJFB/4gtxElLVtDwNp40uc74PvS3F/cjjta8TUdZ9NJbifAA8EvpSIYOT6RfGTsg8cHu4ntqEJJzeqryU4WA86N2FMz
L8QZyaSfYc5NF1h73MwOU4KkvQoWbYs6O/EJcY5SN9wh9tId0FVtpppzPV4MfuisT1KFTd+Wd36wgHOZt/KSRuG7nbothE7kru5a
eG1gk35tyzuJm4g8O2FLM4ncTQR5wyNpmpPvu3uQ1LFpHMORrlaWsJPZ1Ys7HQy5rqibnjUc+nOOZR8oOyl/uIBIrIETieQGVm0Z
yWbCFaW+JSfY+N73xdUcchz+0GXP8ouO2PKglUO19ftiwXY8IXRj3fOFazw5WrULt1h4lr9Lfh5/ivYiC7BI4g/DLL+b2wIPLF4g
X1BAL9R4EwA9jM3cLFyuzKW495d4sc69+kThyBi15yFiUfdOSzaRhgTma559Tfb56FDE3gvwADrAjBq0AI42rmLEzIZ1JSbejBg/
bF9JMHm/UjdmYyXS1jTi1vskUiuooK4rs2KJzR8fuZbD8NEzPVL4KLqfqkilmcE86X0sm3jLX+NkkEihGd84S1VlI8DfqIIA2kGh
/Gvaurv95UGO50Zpt1nijV7vhRqnrqC0hZsFheZPYMb4e9atabiGJuPe+oq220v/V9rfExqhGsVLaCtl2VqF/ZVmdsuE4OEMpWBw
wFv6I9//qsV523pjMhddvQyqBB8VQgOgYEdBwsqsgUaziNWwylGb3AxstnXQGYTl32me2iVyQ++1M3Yc+f98mU5VZLepSrEVuV7s
o6UVKxd13bgGZCLy4Otpu3IOwauc8ED+VTUvYJKb3Zu+tZy0BNXoYMvWzK8GZRJIs9TrSdxT8okyA0BQmPH4Pizjqp9ehrf9vRlN
Vk9g6s+7VNE3HeFkz2Bf2PY4gnq3iFNI5ZZpDS1P/fF9nQfYFHCbVDeYeXkKhFXRdt1u1SuQ0B123EgYJTMpTR6EVGhQyAYcaHHC
2lyZd14lwkFAYZdn7eMojYLxP8MSYDUCJXK6Fwm4EM9mFkmdUIhopwpWAxyAsRurrgCJ2tjoBvmGOMPX69kbpSUqTYsUS7+fMUdP
glleOM905i0V2lTUkfIBgnn34pwvKpUXOp8so1BfiKSthp0fbp0xyGGDbxf4j7fsIBvFjXNorTPgZD27v/qO0iXB0oX7dJknCb0V
ijyM5WbWltgC0AQ255BmxtS1If9ePVvbvG07oPLaMTHKoiP3x5cRMMgmcpvD3TdGgeOMpFEqIesTodoq6CgI2qrNVcQYzcxn411q
XOtd7WieeipiHrOQK+PR9nIxSdwvOizHB7ndYI7hoxWlaP9GhxQOYu+lcl7RejtFfgRq6w1AdTw/EL3W7wmX8GD+KK1H1ecgM7Y0
clD/RBHGHfPe9VX0gMh3xcZgW4LbrkP/reKWJ5bpq2IFk1NvyARzZ0JDhTGBIKd2isjIdUMUf3P/TU/Yrhrtz5iboamADBXrW44M
0mDr1iUd1EIM/rfUY8Feb9cy5XlyF/dZGvFs+JviHNghF+SqRvPyUKxWH9bWKss2LqFfHlS7dZSnvkVREauog9ZLVFfypoFlga8K
latTGjgbK346Dd6+Y0X9VvQEkOOzbxcKZSn58W1tq3fKgml+yHD1KUP6dd66UMpXSDJYeVUC7HmNLW3bz77aVu41BDZ938rrGkW4
Wrx0seaYhykNLCqBCOWLfQaDlxWosbBEUKHlBSQqY5Wnv/moxqYG3QJSvyTC13n51QF7SPBGeohH0dSWlPWhESZt3Lzw8+PDXpUP
McxqzIybIEb3ZsNBYWz3aH8D3wxy5eMwVSptTPuG8yaieRyehEM5MoLU656aVuiL+CKhc9kafKRTQTrOiPggCnJxtEA3dl5FZfZT
wOEM3NBNtfwghcUyJwNy+XJgLYZSXdByCfKbKTL5QGDoSs59FeXu8SrP9E0rMOXF0VEArO5HEodL8tKLx89HdBHUfGStoS5Gn8BF
neEByhuBC5bsX7UlBUBnCdaYZTGokFLjEvxe3KVC08dsuX2U4msWD3fvSzx7RI+oslqE9XRcac1BPDbpEDeTPar2rc79eE2YyMeM
n52M5QRsGmXLw4ImN2IUFvigiY3MIa/XE7PLRz7gooP9b42AZ/x1gMPxav2FWoyXFIUvzO8PH4xV+Kftw3OWfQ4kApdABcn1fTYv
qvS6VaZylbL58N/6ABrHvu3ibtMTi/mbLtKc4076dBXu4EWv/9HXD6+yPSNsdY/okWpS1VyJrUEAbQHZn1KYHo8k8JMXYSh1iZNP
e9newSBrM8Dkyu9x0BNZf2l5bm8ay0MaILxo1Kp39aQ1qA+NkBndcSeryf8hS5J/KHSXz5QzNJVngUOsT9zi+aW2udvWurtkDkzN
GiwgULnZbmLoRs9J0ZXStYRXLGeS1TyEYvdlseJPqDVlu9drIdh3evY++2f+l4bGBLPtS2g1+lArypsNFX9OxAh/4CzttBdFhzrk
aOftm72pe/OQg01Sb6EScKrYqOC74Z6lw8SPsFXBzwhYkXvYuGxUT40INwd40BRc5OVcpHLR6QuANgFnKWLF4PmDXISIN/HYGFOT
HQlW2ZB9uG/1x4P0vcVCQ3iEu7Pjoe/9eaM4WBHAQID44qjC2gBVwKCKtrUjcJKWU5A1q+tM403BSCVcccMnPKyV8epdjFtPUbfW
1ol5D/k2D9s/0q17RZKKw3+vSUvOgV8ZeN+nLSEX62ToCN5+uPZeElujW9vAC99GuIBMZsCJMFGG5rzT8DHfhyQgatqhLiiYpbAg
kZFjcu3Ml5gm2WxBHNsvj14aM7xyNTLt6sqRvD6L7MCDdfDzX5Pvd4oCAcG/xK2Ax09LJz0r4oGtNX/dN2V/CS/wh7Cq8jKU07nO
12NDx85gkR+uOH1XHKc7IYWCT+PJmpL/xIHCwFaA7QQJq2CTcUtLLkLOsDAXwce3YlKJN+rR9iR6Pv5Y1NXde3HnGukQPnnv7fMd
KXjZpnLErz4SQgSneBe6b29uMfnIttGzEvcW70KyTgfAFJTZhvv/32Su2HmyBQhFz0JZ63qX6F+LiqAUN1iYel+PqCvy1iwTsu1P
tej9nct0aiuD15K/dMc/KK0y0hNX375EhjZXnMnlc8AziZMOGv0XN5SYwH3Yy2hEFm92lyaIkWE97KcXqauj/p1roJxSkpmMebZb
OUm4marvwBXDM9nUNzxT4kJB/XDAfqlwGcrp1DAgThITyu6cENVt10C8zlSFK81TNmCgfGCp4gX7wgG2dAV7N7KQK+KHQv6dyTJm
Zea9IepPIVVXn3tdcH9AY4byplUJjYttu3LgPyi6fF8ojqxhMgN1YBpi+S5TaT9MkX+XaOZTK0X8yVx1Evr0f1kINlKiDPPGCn1n
Ca39DS+HZEOmHJPDTLC76oSt0uo9/eSuYHvRixp+GA88vEKI1+8axDGB25VJZYu7z8cUgYCzmBgB7Wc639x709egJHazCfsjNGPZ
M9nnmWupKKjUuoq2QCpjqpZivPos9CrKx8yntjhhnEQ+f5F9PjjTaygoazKOmTKQy51gJ7yA8C9QorJGFTE5OYZHIfMyzSl+EAQx
2epp7xAiCLqvzLj0hW31LZO/146oCk91Mzb5+k46z3KPPV3Fz0dP+D5hxVdqmXoorza+7Ypgi/lZFMACIwv7q9w8t365v9LU893i
WgpSvHb0nZwn2rAvTG3hmNW27VPAfwuaxltw4gwu8UQlLYwytuwBWXrPG89xirTEAdwjOsRCd/Rxe0DhujLE0PpjP1c4zW+kOyJn
Hzhj3SdAsmKFzjAmogTHWNy2J1DFh8w2cXSTyguyL+I791R/59j+7hFrbvEP7ga0Y7HW5QqGLA5FoHFUjxfDnKMlyyn7sUeViM0+
JsUX0uuPBlyjxNj739EVPwOkqaTkVa1PmoYT7H9tPBN6s0JXU2/rWAZtEBS2nO7eIPzgXpCbHxKQgr3xSz6hYT3zxyhqXk5EcJLB
c9kJ3drSHaiTjgtjFOGL4bqqBtjixymT2RR06oTrplb1GcXoPin7A8QAB8IHRx51g+Y76Or9RsHseWRpe73Kq5uUzTOoDTnFHMqP
Uj9JhqX2+DwsgeZHIyNQHhoHdfu5a6USqg1s1D8IauIdr43hUURnGUvF0tmmLBs2w9xfVDEcwHR0ysv7PJNBhGwz2Z0v7JYj2hXI
uCcvH6vnoe5Vg/Ehr3AzYt53z54OET5EKgxMitfuX9m8INd+9CJmvb4zrsSQw0/ifaO0BqubBJx+sHLcIh0G97L+QnA0mKa+LOBH
dlzdOJDbCIBZ457O2+0nmg9H/OiuywVy9kJIZaWlvPWFBYJ9UFfMSoZHlHV/oLCT92nYMPTIqkfpehvPV2NBNjvYmyScOMGQocZn
71Yqqd4YU8C9tHK47Z1rATlutq3VLK/+mxHxLEFz434RJWGfm8Yfl1X2A5VoIMO5p1VKJin62posayIMDfscIJKSye7mbo9Cr1tL
3lj+uPSb78hEIbxzRivx7ibWL/u6ID+Y++QKweD77KW3UgAI0u6dRJr53/lUkQNOLwQRVTIXwebuVGuJLW26Pub8UVX/j1/XxTOf
mKdcE6Ym+53U6zp3IQgJAsXzbZir9+OQnyqqP+8KXisXtqYTRd9OhPTGADxXAeF+3mqpwHV1WxB4GMxb+g3lAse+fhfybRIRvWmU
3fch2TNkeE3Tij0G3ixWTsTW75r0Qa+O61dPm/RhHFLCpPu1UNIKsURiX7iSfPl4wz9Rl5dS1vf8qnWVO70z+AV/3XX/Hn24yvGQ
Q1XzZHNiTa1JxD6/tkPxsoeyD7doIODQPAoNVvWtBJLQlddYKNyJs2s1Br1ci1T/9TvP3HNXpD34gfn4lj6dVyUrL9gJz4/BvWt4
Jvvbx09kj3G/v4/0yPdQZ++CAS1G+yF8xRo5CHfVk0AlEc0DZt4rRiYmVK+9YopFC2Bh6bsA0sxB5E6sd8RTX+xmgwSjZHuHqRpJ
fyzJQTX7bxDiQu1IFq8l556Kddg8Ab7xwtvFeDTuJ91XRVkXW+I0PuWCgctb1CWD8eV4R2e3f7Kn6s/R3KqWSoW16jdvorQv6tOH
8x/X8/djzQDCfEaS1mNDiJpFZ4GndHV6kSfSQc2sKzHQ9c1uhiMpMPj3seNhMAAsBWny2Ho8LtWEPXhpWn6i1ZbvlltFbw5Q2bHx
SRKVxFnCQP0GWBi1qkAJI8lZVKDkniOXdLrLvtEXHMyH9Nsu75YZcTy2NbkZXJBpcyh8QAV3ra3I0ygeS0EX4yUmcD8LFw1Z9/cg
gOw65QV9rQbqdYi84CrPuYRSZRvLJjLuDfleUcRHBhjVycmGGG86wjYCzz+cBsFIspYI63RQs9WyTDHZvnxamATdr6iBO158iG+q
xO0I47DSTjotEpkQ4d/cZj0vzUZnfFbEGYvAijOu+xzu9NSs2tSOoP3OQwAZd9mAMmgW2y92Z6YrP/B+cxGrzgNVKwhRcOOFIoHK
liw6N5JM52IrsSClEKums0G+4klPRhrk2FdLMpjdsFGuIYdHZsoNMkRGdMMQcz1hwhfI7R+QVF4fvSw0H8Nns9g8mpCpq1D0n/U1
S6i7pevUHvheMm5DzlLCNqouEq9r3QiCWZlD6vn0Vl3SoVuiHUZilK1K1Fs3VNXyQKNfQF3iAyDbfnQtsfMFtj6aa9+dpigy3H5x
8jUncMN3DA0ylekLH+dbb1lhnfJD7VBmFm8GcmSUT1JJ7hbo7aAjS8nG1z+XTWd6wNNkntiJfJFA/Vzz/bjBwxJa6p5otjT+Odtz
5MrHYSIMYFovjiMlsSUusD0WG6ioUUcTXN0d6TXylqt8gK6PTzPC1UyZGKyonlRfT7JYjaQJMjqIsdPCWYrxwHpL2/T7Vz7aYrzV
Y7fONR5YN3opqoFl5Fen8BKc1HV5YTWEg5aN7/vZoQjzyQK5ctZiIT6vAer+KuN6QjVPTv30FrOfeVo/cSR6UGZP/iqEBlnCPrII
2MkSX/Kqcaj18Qfz4Gd28ImHBq+dhLXUp1f3Ft2UgD8hzX61F8R3SZFHsq0qs6L8a7N7qkvgb0LrCRUeDNSWG/+w+YoAUgaWuPNB
QsW6N67x0oScpIaHgvbm5Z6fiLuxAZmJxfQVrab6cSVLQoimDRsY8xJSmhJwwXfWnl+SeHUYtBDRtZa452Za2zaYdRb5tv3MeMIg
7jAz1+R56xkWSKYDmG1+Iq+Y9+GhzJPECWnzHM8cCkDrSuXr3vko8adbuHP/jXbAdd9p66LYAYboBBXZZvOPa2R+jq1NfXqcMduy
WdpJB38kZ1jPDT4Uc1OOwam7nv0rowABHg/xyuPQdZ/ocU1gG2ZaBpxrHNzWLpR8TGCJdRhKWJmy/XCOKux4tOlJapk3VMEvnrBN
iboVMIGyZQd9uLW+wdaJwn/eDvQckmfa4zjGmKsZIs8vNqb23yLZY/uvgBrGl24qRVJ1sD2PgDcjrrnw4YMPAEy9qCki0hPd3Lvt
0S5j5M7eGBc1rlZxYFJJl063MXsSqRd9omTFVPr5dbtAiEMtCmIxShXntatbbSfnIMEZt0k7jp8sTqID1nS6C58sujTCiGMH/zeS
2kGV9rWw//2MwD+iYpKtwN3OJOKST9oIRQzmHH+mcCfcGqhmbWSrekMCrWYnfe0G23GghlZd7EsdcJT4Z6EA11xansirfKCFg5Zb
OI2uaKPJBYwIDZdVmOWjQFDj0Kd5/sxEDzeJFJ+qrc3JbxxQr3+lTZZR6E3t1p+cEF4QbkAh+4DMyHcEp47jm/SLoWCbetNoW/SL
sUHQXhXyY3ZXIIOJjKb2JfwunJoIhxfyyH73jBpOxLNd5zIF4siwiz2jnGy5R+doR5GMjyerJQyebrGuxuvP3U/kgFoVcdAGUOn9
kUbOr5U08n7vBndJjuFiIIwLlYrGShtI2EKqUUF5Ger0mOgzhmKIUsa0j9WlsyD/SlxmnIwoqdB6uw5VX83xpSU1AtIejvPlUFLp
svuAEMml86X3h2uMbUMtSDDLj7/ARZCkyWQBAvSwRRptyb6Yni30/6YhTh1+vOmIyxO8KeGXBQUc/BncZtdKVnkw30tXg7rvCRDw
3c1xCieu6bAZfscTKq3Gi2pGCI1KH+aDqqOEN6f+bQCaXzrO93EAroVakECnOOwd1b9NhGHqfdzWOR9BzKfIbfraeDn34Qqn+ldg
yiwp43w0+cZYWI4/so4O8HCL33Pg6bZHR6DRZ4Hc3ujoe9lTS3FpL13vkMNsKS+N51M6UHyoEejeufhr5qbwC6CSEj1W1cJ0HX/p
S8j29xSGU1/rCg2cjrk17v59Oqvv/4gDvxKDq2zRgH2d+UWx2713kGuuSVNFWjxkPKBy3Tf2KTPMxX8GEk6zMUAHd7Z+kcQFX8pb
Ub9wr0O6nOmfPMaWye6fii7fiPc4qjSSQYTkA1yA6DKEY1UFxdE7pOY5RPxkDbr/hBXlMn8t/M8LcmGmju76IvqbhliqbwN4WSW3
Vgs6GpY0H5CQOH2WxDje/zjLpbtevOpEgRRXMEUaBtBzuc2WyDo2Q4cg/f0JLvu/wvGmZ3n3aVsoxfnNsV2XCQ+qAcA9qrtNxf10
x1WhWEFrX/a+2U0aZ3v+6imDmVUer9YNmTbX9TBi8KQl2gdegztuOmDYgxdGwEZzmaa314hw0bim+FnfnVV82O26QZ2SQKYonIDn
J6XxIJ+Uw7YV11YE1KoP6XCfXgXVVggYi1iAT6Q7fRG81aj82yG8PyufepAbCFZY+fkeueA5Vf22Nin9B852V0ubkYOMH3++/Snl
4VenqAUQy4cj+FsDJVIdSo8PyCJVtA1OJQqrpxLXXwtXJkb74IHnsoJOkD0RpRwzdbLlJOnQzkA71xy/90lyQ+gXLbm7kM5BG7qt
g79TkTgI3TiZjFmyYqCAeqiNllVaF06B/mgdaZ/hVBMX8dus44d2/4yo5rnltftTlUWS1XVJR/hrozz3tON666RuNuR1VkK4oi0B
7jnn0nFwPYCfubt190FCURH/Ui7qiBm8hpPK8VkqDwEWxyo59MPPzE1rcjTQ8UiRk3mqlvPIEiOFIXrdd9UcYoQrYA3z7y7otkC5
49IzB6GzSz0mxMRqc2bAGq2aGb4nzo59vmOEb0RVz3BaYCFVtlMyixAMubYFaGGTSgvZMC0YJBdvbkFZ6u5C2FiH0C38Guu1XIVe
6eMvCzFPSc+j4xSG7OsFZQqngo3TBiBUheozJNQ64W2qU7D14j0m3tBlys8tax19cCWQLZHNuF9qTgo2RywDePQyqbxc60tHXqQU
NhvNKoDizHqlGtsbZ8By2Gahi41RHprO+Epp6sqlHI4T27MukBckT+vS7UKcbd0NWtsV0Yu3v5+NP9AY3dQsGik/gj7JlwfEt/l6
KpHY3WzoX/WIy5pFpOKgx9KA8f7xHEnztSkGasTa0kN21R0zSihB3C77DNGZN/a9YPy54TuOgOz4W3crIbm8L9JVpHO1gAQ3qRX3
gppDndBO4DAAZGK3uNO9fO49bk1DCGjFIF7vu88ULijrpJVHWR/v5rs+QP7fK9m2lXj6f/2Hvqln7VCKICchID9MtXnXI93zcQLX
FQqXr1/IOpM+7DHxoZKw98YIhPVSRaO++NRGjjwFlMXO/WLz+cgbmSBhWJqsXGYnODaRkMpnmWsHJC4XIfpy3jw9IzTNCYTHeHmJ
K5JDi6B+vHaHyE9focsYWKRD6HKnZiTcKe8C/wtWK4jfUBkV3ovoZYgHTIavGHIaBfrTwgXBPxBoWO0E5nhyjDX3bni1S7VBiIKQ
4qveVH1hGbfUn4tw1hZRCl6lvcGqn+O29lo80zH52wZzqphZwM+iZUWTxTcNcHWoMDG66Ff4WX7EluCJSEtp2TrW3MrPX7CquSrN
k+teGi22gR6V7P/iyUGP6jBs31W0bxkv6fbzLaJS1BkMxuUr96QVAn4FfdcLh3Acy36tlKwoCpVBQ34mvvi1L2KuB+BIUb+q+ezZ
FpPV33KqvTN5XRSJDFxhp9xyJLRXUfTjlSIgfF4r7ytecps//gKG1Pg7+D/bXgPVcwtLqOFqzEzI3hfBgQtTjPnUUeG0sI+VIuKG
IfRLcNqOqTCUbzT4xZbAbDedKCWUxUQ353qWymYMY58gJYmFt7iE4NKxwb/qCYNEthpBzUPWl3fBf9g967Y02t0mpPWFNXwN38mY
Yz2R+FljnU+vPqcoA2Z2ZWPXfbMP+K18d4mIv7ObfJ5tjxaITfMgtmM/4htaT1QrKu0mvAo3VsXZs2zLpytApaoqW/KZck0JS8Js
qd+G5KUfpm8TMUCAwYvtO1NwlQ6+jVtgoyj5CVShWKmT0pZV4Lu3QQfd/Rmq5xk7r9qmtQNGIXgmHJ2s2TuQ68yBGuuPzE+lu/tN
BW9RC4M9182yNysDXYXPY4ioMT5hO15zi+L09Ie3Jy5UqmzYRbjsKMp6GzP4dbRSGKHfxGK9OerDsez2ap8HerSSN9FhrrvRry8k
DJU4kYNOSbajUAEgAKxWqRjHiVAm00vqDiL0hyZC6CCFipdeUvgT7qTcKvFET/GiKx+vLdAkSl3npmktIeMtrj1Qo0gYeSbx/+2L
dmHyc/+Y5BeQ8YrE/G7yJl6Q5Wesxz+h6Rsdy9afaekzS97UhRypIo7LXUWLhvLTnHia+j4b7w2aV3Z80v/IxAyFTYQ7HLpICthG
H4uVxY8rWliGtZPjz/0rbH+oOhtRiS9/vsDSxTUJsqpo3ECc8DpmIcffz2MJ43lSL1KvqnnVlTTabHa7r2SQqRivQrM7VUXtbvkQ
ciNUhJtHq4cP0JoBmrzQ5fSQVhvcs4/krzpLQEGHKcbINKFsDbZ5uoqQIFM9lfj+NKZhGsbUn+1qjWykQzQWae/VSoYJpXIKE7H2
nMaFsKc7Rxkg+UXVyKO4JoNN9nswcpzFjBtumGns/kmMPBkdaz3oeT6c153tuBN4BCmYwjF7CRmVVQfPEMCp18Nnn2EA7oBR9wMl
92V782zjcY5V9l2TO8gomUpbM2/pBgT8gfifjptO7gVH/ujKl1OuBdygdWDLXjzrp00G7rqaj7Sqj0hyPPVNHc+xmierTrfOhq1o
3LwYjWJ4E5johJ/3kpR+v9lSIL5Qg9jeXsvseYmmV45WMFdGYj1nAOTdbFsnKuXGc5mrbmC5O+b6FqLdKROCFqWWE7RMU2Dw/6U5
l32t2iwAsac5fyJjjF3vBGIQdp45508hzo6wAGe2L554JYW83wDjKmV/t7sjqX2ojmFYH9kxM7x+vCSaVvxv0MG+55c9eYc/kGZR
NnRhZGqbmwjUqdATCtla2yNtRJuU58OxHIY1Sl35fGROPgN+PQDUkTy7Ieg8InNs6tkSz0j8+iofULqb/mvS83TUO84KWtDXsFGG
A16y+XprQkUW88t9RGj4DS6gWk1MbIKZcVjddSMSI+Pq3LOHnVtD7d2WlQozWa1TBnLyMKeTdgmILlToFkrtxX5Fyy5uJXCZ5QxX
QYcIMoPYz7HczuEgzQElhe0phfxK6AXT5OTLRv0pHjoNRFeuONoDsZimwfHOpOCnV3f5na+VNJGhFSPRpvr33ZuhNyCYOFDK9en0
RcPQCb+6dZ8bAVwUkvGiN06QWA7+2DxIhAL548h8WFKM9R7SAeJIwUgFqsBeW7QpK5RW5g18GKFPpbkfUyT4iZn1qiJKFzn9JJTl
MiLxQwWNeKD89KpXn8Obp/EuHY2jB9JbiGGl8bwlXhNdS0W1niKQTrEnrCTiYIJftY7ha1/tzlhdFsrqCa6ESqOB177ZMebfEI7Z
jAb4JNFniHeLDsEMBfc5YcsMmxBN9TbKlPWMEoRS7kJ/ZyocRZeDQnmIj/HtentUIUB4gAy/oylj/rp0zQ8W6VxOXIiRHTIK/TC7
98TUp5+9HARMb6pDGqt1yQR54Q2LjtXDaG63gAC0g/A0vZNI/5rF5HqV+gRIHQ2YD0Gg3wirPrCvjv7MOOfSN85fX4U6sWcPb7C0
2pnAc55frCVBrLeo/zcTDbsHN0vrxiVxI9hatS+j1eTQmZk9FW8EEbZOWJJQB3SsIa7yiczDd6eVCh/tTDA71OzUilJ/fuM6cWiG
EC0eDUzWg8PngrtR26ankehPWckkpuGrkunGC3C1npmzp/XstIIwQ7QrkQbcc5HLBrxac6mW5EiNoJgRqvcCZYpTaC9gbZvrahpg
WP5coza4zHTGgxzA5sL2qJbRSgctke5OBxb34hrytyxu9ZfOyfC0fGiuokaqKkCu97VMqAETZQeyFscNMke+GAIFn2yW2J7vMAgi
0Y+oOdQsm1mmGaXPK5na93hTecMb0twphdeOvp7Fb0yXjjjssy5a9U+2poGiRB0s/NhiWYda7PG4c275SmaV4QXckpFAnCsHal9i
8hH3UTjusPdIQ5I4vetaTBZ6xiH251e3KjaqJLNNcpNt6UoRc0Q6V0o80Om0u+8yIn3S9dUJUN1SIuKRAbhba3Ev+qPsQIzz8Edw
56L+Coalx3a6sgS9zEzMqVjzuCaa+rbjX/382Tw7vWWa8qXmkB/KXXZgWzv/aQhcmUHPKLKLdtRFoVvbdDUwvm+LQhfBkX9ZCMRl
Ev0PD/+k4pvIdua23D6fCrm/eA7+RnsKWK/ItM77w2HrDRHOJyIGob+JBtA6j4vN2D2wAmcCjBO7Fays+QIp4XrYkG+ZMo9FQSJv
WtdXViiDCJssYFsderjgAfB8FYxTMLzPPTCC7x3I05e69o4Ks893LwCo+2r6OaJrR8482yxMEoYH05zSHq04C5MQwBmtI7Pu0j0f
r6hoQdkjpZJwiwp6YZwhSIVdmHH+UPRSoV43UOe7S23zdgh8S/XfJ+ZyVZ6DenkoNamOotiSz/STp8fmddHUxUMLHLv3QDRDiZl5
+bxKBMAWJQFbo8CIb2/7zvXIxspkac3LugxIzCkdqAVuRFUs7I0jxMCi1oKIrozU7K5a8tbAWAW1Qt5p7eXitguSu2IutD4lIURS
eNzixArfF6fQ62UL0QD+Go2uvM2u7a+/hErLkZc1qJfn4+cgi5f0Q23ajF2FeySj2ItXju0rjYPch2rcN7W3gqYghOBLyqG1dVNr
++3T9jwpgQ+Ae7xpieIysrz6OCr9sQPSZyjY4Hck+sxBMa9TUfnvSRtNKpGcSJ8KELBXJ2nEWhPWOCOOkSEFx85VBIEo0GZBSUfx
fxZCXynlw3MiLWxfHxjA6QnzPrE5U0WY6skLlbzRNvBoNdYei0jBstJKpIXWDNUFsFcXoeLgoPxZ/sy8MOSvlsMohsrd+2Wcv/cb
NSqwPSMmS1WUjg1HdnQIRhVtY7xxPcvSKwq7UK/v6kJV+d0kLWbgK4V7obM2wTq9tRZmHzFdWad8a4F1y2eHRgnhNAwwFp/CPgGg
eByO9aLNCj2B0WJdTC0QpKceOP1YQ8jH7zRRFyXLiE2dzpxKQH3L+coIgrx0ygmDQco+xhv3SeTnU9aLJOEQpFZ+9gNkwLN3/des
DFtS5OSGOFOjKDj/r8aWOE0OYReEfB/UNk2Q7AIGo/7gN2TeUv+R4vHjHoAjSmft+yAxZkwE0M9hm/chzajNdSqTDM1qR6m1IrXM
fDg6u3Pt0EC6w+gNqN24AjOXY6/S7GpMAaw/MO1aIt3A6eOBi9NulVEPf7gIVi7q1B7tirHD0hs+LN+o5r5Jzk+5xs95oQ1/6tw0
hRcvyLUPWAbpOlF9D4oryszLJ20AdBg7/Lvuj6X526CZEwZQBCkhUzZIl1F4Dlip0TKPORFm5nsLOlzZYlw1LxjHt/aPogdyWqsu
bFZcK0eBbZAXCq9eCDmFNqp63v6Pkes4G/Gt6WkwCYv41dRRcWJE3gmYQ2ntZt9XA4cIZ0cnc7s5rgtGZVUbGghc8eUEEIbSNr64
BIW9rwLbM6ZpJC5IsB3JgGCOYOqgKbNT4JlUVNrQubQYbLMYcwaofaPF8XJFg67wRgHIMttEWyCKXvmqhB0Jz/kKRvcTya3r3GzI
1o+a6yygO8wgucME2IgmtXP7uDCi+Ijs6vAz1kjTpM1hPngT5U8FvAs/WNdcahG250Wj49uoQYTiv+mBIAtCPB3NwSgescdhQkn6
MJd+K6bMlslJ66fd1m1/cZW7tVHmnR5MiWbc8pOVLnBkV+U0fITg+FVoeGz625F+j3NWK7JDPFjMWH42+2oAKrYxyGeDa2Hrqsai
QSBVzvhHqxai6OczePQW8wSKZW+gMX2pKrxlBZDewVPTMjVx6MO74DhGL8fDxnGqIU5/WpaCq1lEoUaWOow+7a6aO5PAsLgwL8PV
5RLUayvlNp38uqWAe5jhLzQQWGi2napysH9xpqg3aCbG75qievqIO9C0oyeHFVTVlx58mRLaIvdsJ9cbQiubqU7eKPk0Rw9Sl8OT
kUbmoPbIh6aW0zbePpK6fEUAs84l7/naplVLAtts/8K8+xVZXOgl2YJgmj0MXynCAfhwZQeABQYpwKfMSPGMQyncUmUrdD5DccL4
qPcIF4V+mgI2ekWekeJ3Kc+cDZnAYbh5hK5l++176ER9bmoApIDwptmEW0+SgrmAEvsU8hHn8S3H7F57jrzMPxSlA3gG/IppnE3z
bUgegc7arYffHhUMXS47jpEi9MHD2QWsDKth5k4kSBq36B63n2uPBUZ6Q2aVWjuykk+8SFic8JoVgh7zqzyHbKwCKo765z3uu+0u
xGbLIlht7QSWoGfhsybJNamEfJswJEYgLXWuEVjJXlM08aHLfNF2ndgiXWSq6usjUrwygZt+7DGXTobkeeX8u3WRW9z02Bq54OvF
PowCsnpGP4E8xOM75UmWVnuExKizk7qpboLlt30SrBd8NCnYFlqxiu2BQKOvLYWnKsPXmcE+4xCBHo9r1sFyG017X6+F3N1Y5te3
NnVdSta7sVJ5xDoNZc7SWG7qSa8hqZ4lvLEWs3HwytJnfLwQQR+GfiFP4feIi+wIDuu+LhzcqNeYkGAAjge9gcDjvVPwXvjS4KUi
F5o61KzsQerhPecvukcNpaTgxN2nN7gKksEzi9fbW68f87To88ULRSnCDWn37Fka/vl6V4VflwvkFKdqIfx8s1fXmHbENXYBrI5A
rESy1Lb4+Xpe+zidvM3Qt9/fNiaMwTGVeviFBiDebQ70lrGI+vAq4j7IQWHrNwEAfMbXb+fsEaCHIn+FkFR+ck69ln3OqajUCudp
uCKamNpF/HTzNpz4Mynrkd+7JSnrlDCKjh+85Z80qe4WzRRjb9U6QLMBXQPZ/9+lnoYAmAXcvDqsYlX4wn7jLtvg8H9lDz1tL8qH
UWFAyVWZM52eb9mU5QTo5r2KEk24KNBd9nvSRbKTcX3GzDQIk9BSDENz6emqlre5JoCN4slnuOnZXWo1sWvNWd/fR1R/KwEH8k3Q
Ipc8jvglMH8FNkKW7sR/iAxioqZJBfQ+/AlAxUyIAZRDD9qENhsw3valK2p2+3j3WcCrecyExYszibeDEmEPUHCRHDu6XLux4zS3
SnYAwlOI0XhUGKyXUARVTvgj2g9EjmH3l1z9tiqhM+g87dM/KA6JUyznCb12Nk8bKU0wcYd5J7J4qdK929GpuDPzArz9kkMs34m4
NGb48Zy5meUvN49OTC1N5NLIp+iiFjqIuCs6xXB+eUQx93sbgmrUs7V2KpKhq4xcW0/V7QRBDqCVt8aF483NJdP1BzhVp2RpLNrt
sKoluhvlswo54VJIiVLk++exMbnfmHJeyfv1+XC3IX6LPNp5GahZHzXsv3ARqIDqcwy06t0oGgaYXRR6fkhZW4qchReoW14qtawn
Gx+vnQU0qy3f/iz+U/9sPW5czM0oZ6rApwW0MzRXrO2yJNNbMp7M+nvXku2CRDuTHtk5hGNPpMGX2JVCKC+BEeNODSD5p1efO9LV
0mK9vBm+Gr8n0l0P5CAwEyCoCTvngy3JS8Hu1YJRoUqZOJlu985mq+70+6Ltc4LeaVxu+lwau+et2uACUtOORdfspg0yRTL3HH1P
0QSlaJV3md60Oo7V3nmjEQjeFb8GCRiGgQ3udavki1c8YjKWaFyZCFpspDwjpdXG3eKFiq+3MggbHmv4a0uJl9IpE7b0g2Bot3U5
cnnRw7flXQ0cYJulcdYiGdUiQcx+EdWbH1jSp9ZqCuHBY0z6YyaixzlFTCc3el6lcDGxUd5gk6CukDizkOifJwANqY2Bh75uWh6j
0bjNZyaJuIQzSaaWQ0ZHhdBkU3RRcecmlfGTWzjulHm2z2T1+6ALIWq7RvF5PD9EjplrCAd6l8fHsvBVjRP022jWHqvP0jI6eAY/
AHDO6MdhG1oYmWN6oKHQJC29K4ceitIVIokul9J1n658to6kXRyD9pWjJnsPaDjrjmvqdSNIRn38diLZaUhMxCeUNi7xoOSwtxm7
jpQWLKxXmyXSF6dRcFIRy1V0XLI0CtfsI+OBMQqxNhCdkMzdIh4nuZVqy5/+tMHbunDFdKIEBnvC1RE7g/OMYF8LOjcyg90ttW/q
2ouIhyrRPBzE7P/1n+FY9l1GbQiTmgwV5ge+8KrHjLTPqY9iYj/BcnAO6aDOIISFtlAMMIHC7rXercmH9DNTwE6zc14uNZMKe9PV
/CDA6U0lQerqRTbZfXha6qTpMnRwQQOhCzcxCPX5CM5wZMZo+778pn1JTr+b0ukfJjv8GsVyv6ywldhSHAaW4trgDfCKc4ivP421
az5SDmi8dXrYfoH9kTkO1kxK7emid12UkwPwioCrBWLthoJV7YdvnPxsHvShb+j0ssxsLGj4T10Qvi2VrLVxeP8IsXiOrM+WWEHm
Wi+VUt9X5PdHHD2/MrIci74aGzWmeeFDNjtit9Behk9WBGHLASy/z05GWNxAGYod433+C+tytvADnpYQe/KfYCpJ/1aLrbFaq1jM
+w+adfUQG7Gb0nfvxIOkR6T43jWv6hOUXISUGUSWcW25tzWalsJ/IwNMQmPXHjDlkPjZd+gfj2E2g9Fl7gMQaZuWpldtqepS6nXp
O7FhqMrXP25YYbrZhLx1F3lNltEx7Sfx4aNVyeWVR9+6RdNIT9uS/NOSBhKiTvODB6k5gyH9bpfrAY3auiuk6MEwomWxUaBUmarS
BgtrQEGPcg0CfIYNLvSs2Eb9g1rukEJbnktzT28F4SaQ7EEYFcSgVTguc+ma1D8FI1hBZ/GmNLpvIB719X4xm7znzBDw577mDI/+
KGjDSFVh3ZKXbfnkAZ9HXyMa4hx6Q2Ev9lXcn28kWpZ3g+0sqO2eSTSyj/2q5X1+DIJQjJETvjwSASq8Czximd0QtDwxNrNwJYbk
GKa9DIqm7nWrz0h964C2V2k8Z4P8cw/7KP90kSS5rYFGtcKBrcSgFwXpmQZnxTSHf9j0HaI0r/PmPvfCQoK3L6PQ0PDtaQQ99cv8
Y16acdJ9qFlwcvdOvq2wMU6XkErWe4suow7lE5ciLbM7Z3EmAndgB0zZ3vRWilE2QrIut2jnwdOzVPtn8ymrvdba1mOirwpcQ7H1
cGTpAHaAn3uCwrmcZdSmmWu5eG5un5nbFUsJMWdCKt/BNO5KRM17AmrUAERDi/pKBi9ON+GC9Pu6K/rVFvYtt74s/OfPEDzTw+Ji
epkdOaA0Bh+BfxlMEe2ejqiPaicMpE8U9P4ivFE83L97hmwPSMXcwcGfQOSOYR04ALayq/F/bHvrNkDuQBkF9j4acYBgGT7bf8ls
y9NH74bxCElKry9Lk9obNDB2kKAHk1kZwx0zThdLbGQmVwvhxbF1ICXJyNueAoGlmsXCnM0r//fRfw/sx1UOVbu7/Iv+9v3loJRR
ABppkaFBK6ybwudyxgxpCjZsMg7MFFKU8iIu05SUcnlnmIJF90QBFUFTIDKwTf2ATS58eRddtMOJbaWfuvEFJ+RorwrqC3Kq1F/x
R57PA4xftIaMIKsmNkX3t+kbf41cFEL/U36TUPi7rzYa4gxdfR47410Z13Hj+Z8f6E7QfvczrRNsELJI7lwuNgQ3DMv5HplwZmoo
Z4G7SBku8TN+Uxyhv88LZ3VxdG0qapoAoaH+5cfXiD/13l7+WNBYkU50K4OtfxB82mGMVkX3T30K3dcxuIZEN/KarXYxfdMFPjkQ
VFZ2aVek8QvpkPOaOBJ2hZynAJuH99dsEHsYHhP1+2ebGDH1NYE5ZLkg3O6CyhCYNPsHcHDWHjGvGJSliSYg8kZ+7nURfFycA4w0
2V6DuKLyg3DFaGw+f8wwOBZKEQTCHNaIKoqBGfYFaAFOEtM3NCGhl8oHqcMPF3jDCQWvZeMAxl8cNGzVEpQjtHYoP77umXTPya2k
dFHs740pYGK653Hwr4QpLdR4XsFx2eD29YAbO6+UNTe121zIsRczs4WQwAub04eM52WdJJB73v4MjHFPY2k2rBMbdZX/Rveq6ACG
43UE4FT0PQUMxnG25VpKZcXRT694NB2cWUbHMxBxMSLeFOOSeeqeP2II4RzHX/uZCshvhX/h6VEcR1nxmfv8v6ZNNHt/K3lgXwb4
slPwz/9N1oAhf58BwOf4H+wOSSikx8GPOT7gEaL7g6EQDIhcfgtYJekyvw4dL7Nto3Mt0fQfTWoWjZ7TSkLyR11Do7g/L/i8Pflm
NFx6ut92qEIyzRYbqmBe3dn6EqmzqImkXmvsBM3QPc+KQ7d7dO+xYCJBIwRzyG6sHdS9sb+n/tL0VseDfLYIEt6jhdimHaYMwuvm
hHt0xgSU5Z9FeiOR+ZhnKB975wWXQS0YmcqOqCD5jgneqCsiHIWRKV4gOvvEaram1kIXggiTgb6kVMs2b6SH2AXaP6UJpSitJvQN
Lm2Y6c/TjBqCxDwJuv/+RG1iyzuNtdxDr9k7G42enuaHS1dzzUPDKLjbHknm/2yTj1fLWCX8QAt/EX40TyGMH5KKDOkMEWrRFWRz
3Zj94U3BkUTl+9zRrMxlUP+zhFxaFVxbxDFVlQrAQ2YweX9zuLsoIKC6WweQYPyf6eYSfUyTW6J3quhAVB5eGkwNUwq9ZHoXly29
+h+xE5jGMSBrq+LEcIomK0faF2JaxIGxetZCGX/iLqnLMzHKIj8FOqJjTEYAzSI11ypnHdLb3kKUd8ZLxH5B7nbNBPGV6QxvOsKM
jYyquIm75z14ktUiLKvRM3w7e7RZy705yExMA3+pP3qRC10WoSlyfKaAdyW/da/GWo60/6a9QJHZW3wK5WxygEkO8CUsUnBCAN02
70lQlWCtyGeqhzuQ6GfZKoJNQw6KzFH4XAxwI0kgwYL/8xro0RhjGGBG/Fy4BUdfKKTbkwGjhvyAeMy+JkWk/oKY5BaWTd+AHuOM
Ni/Lt2esIYBHuL2uA7Krm8bQ4uVVe4E35bq7YDJQMgMEvqn3JHQDn3rmBrXMPm5emejRaHWBNM20KQKlj1Tx5npJGQE/qI8SgOGN
aLp3r10bzuJEP406X9tNT4cw7frj1kH1trD7NDeIfKGSbuUGNF7anvj8+IU+mljPiwhPVOfhYn/PAbQb4ErtdbfGwuM6vY6Wt0t1
wyQWQd88Rc4NMvmth1nP+bvdivRUUjKetKN+oZvAkdk1zAiT00T3A8hJx0USxEGUS0ZRqZ0MQsPDuQAdoFqt81oL06IfXmqcOem5
Fk0MkwAQdAQ7I5+n8ekknhMPrMFovbv0/93mhL0QonLbb8jPg4bul8Q32eAu+PHOZJkMZXQ3APLttLLuwMVHgiPBFPPibeIgmyj4
xBrfz4tZ9+F5NPpQOH+6yKQ4AjZEC1MAzZzeGe2uTR0IrwBNYmaiNQS2CksE2puKYyWjDWwbud0hU5UIMboozH5AUDjQUEbcIlKf
HKS4oNr6jh7mcfUdLNkJKhC9m5/KMcYRPWvS5g6FKuQqBS4rLRgI94+4mGdkyzEabTjsm/wvGYzQYhQLVBSUWutdSQTtBJ4PzERd
TssYNpeCCgSeDuZUdvQsycruKGpngrfsyjG+Fs0Ihf9Lnn4Zp+WATid5HbUIVDWgHNlYlA5PXpW7IP11EcK/ZZgpbIWM+Td2ftvy
zoKEOcyBgcZLKURGRYAaOzEn6PAbDjRF8clzEVew7IeOC2w7tEFxPAiWTioYMoZZ7eY3czVahQr18BKMjTFGmSjinzIf3jUL32pH
RYmp0UDgPqSzSSqBKAgHfdSN3FXBzL5l/xXKPLVKBIal5P+yFes3Bb7ZxQtp3QIugvBbbNHu2sEJZYZ4y3eMSca2kb6swYcOnI5w
dNy8PEPssURGDWGmhldim7t5k+jvPg2GkdhDRxWJ60YHSmri+nTE9pgqdzXU9MjLVSWZJJ4kuA9DKq6sdI+EjU1HYC8jSqTXyK2O
WFUyej0a2JktsOrRdX7fJLHZJmj4XIJhO8KTBgpI+vs2FdMmKSByIXQohMWknx3ipyTXuajvBmTZIP+9LxWcRLq5C6H7x9DK9W8H
R1CXIH4B8rT4CUHZmoocR3rKyTk4JVpT/Z2hGs7cpWaJQjJQW7yEeNUqemgKlNyg6LNg/QKFBvDPkrlSpOdsmdR071+nRkfc4gdm
wy0dQvKGJZSvlXXvHUeFq+JfUqJlrZhahqd63uYcQnhk+GSUiF6UpeebFtvUMNhr71nc23PTjB80AdKRJr12MefTRz4IltvPI//A
HZDVXWzoAHnLxAy9xfgZ7kg1T9OjQ7dx4FTERzvNaF5Sg7bD/7/WOsTOlSI+8ButCFYMuswS9jBqsP6gBv60Y4Pv67/CutUvWFa2
EJiU35U+RMG/y7BMOQNiDDM1Or+YzNjoKk/oeEQqmk9fcX1ejLWptmjlLa+ZnFMRYwsfm9YopcjgU1Xzk2GGcvsmMPprr0Q14N1G
2ztuwJZMIM2EjamdR9Jj3smP/IwgrcIA69rhT3CxaplLwyLJyKApMdtxgJa1FZJM+W1Q/T3MGnqHG32xBLae7rugnvqqVZAbw0iQ
N4+PxBhqO821nQGN+CSS9y9NqS35comKIRvAh79B5H29ky9CS+p7nUtP3BgakCjidqFdTpekFG3nGoN9Lb9mGh+p2y4GpUw8OExk
vj1X9OpvSPl9FpXg1dkLpuSFm8jpIsQhXYG55xTs3Jb7dXJDfmQBO8GuvQKLhuk2jqfkNLR9s2d7SugIxdD0fCursbNbTPJmMYZb
r6Qq0Idiyutls9vdLMCPgXMLSH7ZRTFKyxKnmyOU/NRBSQWcCCOvZiVi5DFaZS7xsHoFXHE2e227Ivd2It5EF38BKILlHTaxxEKK
U//nrj6EH2d01mqrxUVgsWUSWsfg0p0O5fYlKyn0iTbOW7qax4PXqnvG5cqSX+Es88oyDgUNM8yfbG4vk2ze7k3BzK5I7urgCXq8
pQBxKl3TrcT0xTWlLASxj8tp3RzUIL150ZmmMEk2HU+4Os0WOvG90VXYHNm7kwDQRDU3gnwYeSxzEcaw7tLDp0ro/5GjAYEW/P77
6AggspelS1WHk1BUjTyhBILahDErcvpeeLzSY1joQsmdhdmqn387GWMZq0Ju9plZOueoJfCOU6yg91AvRUF6CxZAZfeuBtzaMVzk
CKTg6R2RvHBI8FkqiBbgBuahAkVmoLRyXmdKwhs4E1up4rl2LPa9yam3hg/a2FUM/zDj2e6Pb9R7EhdBHEgLAnU8BKjWJvouA8kT
k0ziHNwkjQ/JKzlgs3rNs12FUr5e2hTS1C79i4RxVs/gj/q2Y7EztQ4SQK+cQ3uTNK+mQQu26Rly3kuoXEWS+SvYpJXbscbLFFg6
FnX8mQWsjCCpPsNGrxRTr23IasHZa7UybigwkqGcXrzugbEuaFMpUze9P52kvy5iDwh8Y9glAOc9IhsZz/qPLwU/0oLjunD7lowX
ouaf1Hlldf5slJF+iEm8t9ltJ1BGht4sxTr/TfvJRGw+Zv8Dqglxk+wGk1f8krQynh07Qo/Wa52xAgncKJDhpkLfegZw6mGGE7Hc
ArR+5TmgRuo7xWbbaDTm0DeHlXO2cOoA+IMiX7ntUrCMG/yhOhEYexUx0Cre2M2qsHzmxYIm7h+8S5xe/N67V7RvqumAujnpgPES
3Gu6JJU4j33PUkZMwrK6L2HRI2dfHszXPSiJSj2H+ww1vP9Wwa0bFf+w1UNMZ79CN9r3tTj7aQL7EVXXIo+20n7L8OZMMeuLiayg
z7Gm60Sw43wWarrQJjvbRPloIxsXWc43d1IjkvY87ld5JjIigelFCW4XIwBZWIGZtjEf36rAvgU+ff5pJwWfHCcTiu4qFtIAFVLs
7ddUcoYn3KdHkHW/LxozCcZoDOh9rDOB+BST5y06L2yqsSEhvfJGbr80Jzg1MFf9plGCY+iyEbk1Jmf11lcfW93csSKe+TdLTxXw
EQNborewyaMQoUgAlJLjccEUZHk79YNOrM+bmZaQU58FK0cb14wIvefjlFAdhtzx6f3BH50M2kUyqr4iDjsmp0FX88nRSEb6wiCt
bgYiIAlsNyv7lnyK13zZ0JaNSSTOP0HmoDOOax6zohXPlz58NVzRRogP6jI7O52QxOLKN13lpctNmwBtCXoLIO1d2RqeQ4O5+qp8
raSnvSATEpcac8dKolb9cBWirmb4Ef765ayomS/Za3Uoyszi8ViLVcUlHi5fbH2pVlmxUucPy9mJDcFT4zb7+NIA+SY1psADBHSf
9Ygv9hC/L2fLtC0es8pn/dfkYZLETdgvdfAAov+BCDCT6QtNSKpuWhKyobiyr4cgsSO9q4aavIJYA6EIcrEjIwlNRIM/l1AYHABr
RMYFAfWDXRRoJq3gRKwPrJtafO7S1d7YSc4cMriF6ujUhgOoFPbvaR7VIrcLuLowK9Je78jaKAFZkISZSKyMYMf1ftgFh6FEOcrS
TNuIRAjslC8rXXNv2vTftUyOSXYf3gt6uJwtebq6wwqbfHiaBdmwiwxczQpHonS4I9m8/44Jx2bOmDgiv+EFnkTPdtCNtB/UYPRb
8N+udgRhrTBvHuKylu44PYqSSrwmNvJrBXa+mhlgNy6BbBvD8dRqfBDFnyMO3iHgY2O5i9JCCk6br1hfULhk4X4wXgXQaXsnimeO
mab9QdkpvYPp/VZTgKAl8YBxFvYqMUDjZm0EzrzL9F7EQffII83QItt1/ssaJ0RFcNCiklXT3pXq7JiocGPCX8zo+QQ8LeHgXc+g
/2hR3uUXGixhX9Do+s1yKDYBhsuZPZ/qjcGPihbI2R0vpdr9WBx0TujodMOQHjBpg4NoQPHf3irnT7XQFsPkHDiu96nMcZUyHUaS
tucaERt+yrIDaIRB62nqcAjFeIu+Ojw0WqC8hr8zcwlyFZPzA8vmK5Zp60Dl4IidPxOEKe5FgUfCVxB5zoCaXTkfxe+eqUMeJiQQ
Ub5MGQOVga1JPL3vatfE1fe7Z3zhqhRwyKPLh5tpOj8S6Ii4tQafAMq0NTpSEHgUJp1LrJN3rGa4VqMS5CVtawr14z1QwruXGK6K
3k0xrJ0pv4TRXePqM+Rzv1UUuo9H0FUvCX+PayRGvbp8GNUbb91PIQS3tcNsm/nElNTrwJHmnE6kK1W8EqhYVCjey5pgqvCSs0/W
qfvlUQ5pLEGVyRbrCkm+1oRfsuJn3hooKqqC54eE+n20EsLVTho+v88Ps5sbiaFynjsRKkOvGTh3KX/CCGSWc66JcgPKtw22X2Wj
pv+OC2cZi0sNDwuW+RoaSsfIIhsM2YqtmLnQmBeuUtRuHy/KdJpfTXtYIcJcsa9OOA5VfAwyKj7XoSZr7uQZVwY8UoJR62444KUV
6Ob1CgAH/kcmFx+foEDk5LC28k5s3GLhNguwOaRxnIQkoTXYzqrwuyp26TSkfqYWQIAqYrs7wvUcqXmzNc7W+atsIYHnI3BmeA9Q
HfP0UzJlPUFAAMWwtrP5EgVOZzyNkwAab4Kj38lDj2HK5C0epoSRO87HoGN0ZZqyRNZ9V0Ua/lO3mMXAMsmGaFBqVDzFvux1lJ1t
78BsNEi3cLug/es7sh8UnnIYr8dnthTDIdI7OcMHQoEKYpYYCvRUvT+qsQYsaj/4x5h/x6NK5j3MzjT5E0ozr0XpCuplhXh2HkJe
MM8eXXEhSATEW2IC2mVQbc61DXTMikrRq6dGMDtQADUaIOhel36YYUIIZ+fKcfE2F2/WiAoen6nxgLXrE8HvizDuclwZ2BsrQlXg
RcXvU1SzbkR+jQuvOVMutxCK9xUG7L+pXFttKCoFFQ35W3uAqNGB9dbT5WW85HjPIdd8vAjb1ZkUI1Z3MKCcTjnhVnKYQg3Shygo
no37ap7iH0AMIvZciZdHpilGghXcUzdvPy12fmNZKDYNG6R0iJOFRqSrWoaldB4WsiWyzKWEy9IQptH8pQr0aN//TBdreHLmeciX
+zxB2GGxIxwdOeKSkU+qaw/yFbuVzg5Ga6gMUMZYmqOHUW890WKpACISnRuSTmzvnwOrhnVlTQuH1O8yxYJVxyiNL2RtebTv4fsh
WfurGIQywerEqQq1EtTNgQ6RyGa7VfH/dRN0mfsHwc3yD4KCcKxXJ+ZWn3e1lufc/9vSagpo/VH08BmoUIAq0eh1V4FxAv+Jutyd
V1rmQFWAU2ACXj92OoKar6apnWJAiaFz+Iv3IYt4ilaeNAb9ZuKDVq6tyf02Frv1gF/oNG5l4BYX9iqsoYCeXO9evs79SKeDLj42
PycfW/Qauu6MrZP6zJSS1h7KJh628UnAYEZ3OcfIeFE4VMEszx/WDFh+H4M2ZM8RTQQHBNICaxr0NYpdV2pCAJfbZIbMTaZPQJJM
Kb6d+GSny5ErtDyp90Vst+M/ZkpOdIDxyQkpeqMhm5QgwnXO7dqmFF3oBstewdGPElL82wZRpD4zVL/2UGc4pxm7NaUa7GhfT1Du
cGSxCnFCK5PoXXAogJWqUp7zcOfWCYzP+rIs6m0quVRXzsF8mRxUY9VLtAutDDr2/KDk09DyaoNVvi4wjZJaKml6HnBMP6K9pVg/
iXFMcdHPuO4Gzl5PMX8oNDeQk1sFtu2v3XtOPrghsuN27EkJK9p1U51Z75fGLHEu+jGucx4/9lT0QGijZYZpsEcJNQoEnhBU02tI
f28t3knk1GNZzd6sk2voxe6H1pywZmi9T3yPQ9nM7vFHKonNe7ysWnc/PK47vCBYQ2MItlW3O3ajfVfJ+fwjC6G/IYyiVR+L8SBe
EhaPxnkefSzIVzOcRw3rOJzNJNfgKQsLF7wcejIyRHYkBsqX2dgDI/XSEUvqujt1svt/7bJ+5pF+0DUHnMuV7FjoR5nxag8vzpFF
p0b4mQUDeHkb9fPQP/V57w2mdlrYrip/BojR73bQoV9KNW5MzoHHKKkEYpYZht1hWcbl0uKQljCPHvSS1P5VYebsYyv3sTPb6caf
WyYzxCXqQ1TuLrJFDUT7CR6iby/O38wi7ahRwFdjjclSCovtL2kXdKOnsDe8jYD0/9lBRO9jZyNzwcgu2tJwkC8m/PdnoA98/L/8
cZuVv2yGuJfDRYisel2aYXLmSip9UZUq5lIvj6RPo8TPyWFs8EtdHn2+OTPMjKKQiboVMIfIiNv0N2L0upLC0gtLSsnh23WgOaNG
VLpdS0eWVgTu9i6t+tpBW7maY2/jooFHKKpen5GYSDdfJ1JDZz54QWFScNQOocBZOS1OEN88ikjY4D0uYCO/92infQdQLsRCq/X0
CS9KHTiCCgBykTiiUGbxbZNLMA58h5yPW2F2a3xAwnEBuSzK95dw4X7lp9cg8vCgzFBVr32nWxX7dt8th1AFjAFHmcHV802SGgVb
aWGjBjG1xcRpEpYnah5bK4igqaxdwhY0+WZWVPaevpTWxMUGMjbwi+fM8V33/2v88Er0zRs8qhTXJa2CdmmfIsTk4YLTEM0kqhFq
7rVYxlvG+Z5GQ3e44M4vtTs0zgPhcOVxaJmNdoBeIiQ5ruVqoI3Z8FKNwryKOJ84GqqyDSwzCk/PBleKfl+sPw1b9exJrG9RcusI
calqrLsGL87IkovluYgweGbEimYWIRiuq+Q8vN5SFZZ8AKtHfGzV0Xt3moLi80XZjvDwxGxWO7tosXHfJl56WyX2qA0EopUjYs1U
SQUq35diqNWsV5WJy7Jw1+mgTuStYHwC8VqF7GBmCOmb48xKAFyiEa56wsjF6eN84UGJUMFS53vkTS5CIZ/bMuSTkNhQMG+4JjX1
/0mgtKXfhHBlPpjeB9xEVqZWpQtUAqaRs8nYz/8TkKWW+PpRrUDKRRCPMzDxlcpJvAFtRlJze0Zi4vB9CiyeogpHWzSu64GEHngh
HFUlwimUcFFlVcRCbMi9gGtX5Yxps0m80vRkdIhr6lKw9VDHV9m/dJbn05WMan6RyaYP1eUD6nyHvGgaDGJyaZ20QQplwiyI5h7Z
N6Ecp5koaPeIOdvPQpK9mlCiuSTALA0Lq7aladVlg3ouE2l47nd44vr9ptpmJGi9EZtWzApCnlBfxc64m0Gu3b6eXv2NXesYyKxD
JTMCyBXzS2/jJtw8mgzG+RKHTXVGFQBimk8oL4ulrgrNsgE5YETEpxAbC7x2HQdLI4/HJo37YxGSyNENSEKRa8UG2Vvq7osxTWBB
cXDzFdi04A8hCxu92xcjLIxGkdNLXb47a9KKa6nawNDrQkWRJJLrYMmqZcgCqZx0h5vkXC3FnClCdlMgJspw8A43ZKoebmw/QuNw
xOb/8+2DTIpikypUfCvflHC1s84xPI7WsTSydy28DnAwdXvPjgqI4fxzJCRjRjMtj6Tn6/tgWl1idyuK87y7hKVX7dgFjl+c0OvQ
RWv7sTaKreo9WS9A6Jqzb+MdH1b4v5uyTKcPETDYgj4hbA6Xy9D4gpry1se3KNrD8vhGsRFpVYlR0uloGcg9kOrI6Ap7lLtZcuU0
Hq8MAuW8RViL/nCMfdexrqiYt0A1VLcS0wGGByTsfUzNV9M/puywga82yAVbwTfJt8p5rze4B/dPR83kLOLyef9Pxm/diqhoz1I4
5Vs4KVzQwFPO3BdzqAq7EE1Fiv0tgiDoINJtMIPnyNa84srQnCJNiJyZ2iPeiayhAF14HuEZ3sMi+sK42qw8GeH/F6UWR3P7wRTL
uxFRLlx8fSa90FohkxBxW5eStOnOJwaebUTJO9KFT0s+fHjh5AVBb+7ALOo44EScz2dmWOzGJjxjssZDjUbXJXbAkocHA5tDZ7Wm
LNH5LTTZqj2K/MwYQp05iX+TNUSTyUjsoFvaKl9gJYWaptM4FWmoJl0DiFND1nPjgWBRS2ma2bfvDzX1Pb1ckKkhVwKzPwexnVSW
0RdNZ4qpEFFE2VntgbokNfu7WlpnOzOCMN3qOCCGdP7irdvbDmCgJEAMtB5INywdxw5ryC7mhbn+xBEaP61XckqUQfGQiu4Tn6Qn
8ISH/XskbOpdvragVsQG2QRkfYXF9Hyn1z4C0TvPejdM3JUQy4VaAxcN/PinDJCwaCsyfsKzp+pqYlb83id36wyqu1ViOYZXvsmy
+mx9tuNcJET8XYjgPRs/v8EoMseT2GolGMNpXo5Y2Op2V8BGmwEenhwMDaRYW5NpkGPvFaCQutoB/YmXl1AhpRpvY3V/ilmse3ak
HfptfX/mPNze5H5ZBzrvY6VcAHLTdOFYhN34/I1q4OHHLC6DuNmRtSMNGO1iSFFoDNH/sHMPPoOdl0xm043vb8+2LY+JCO3bWmLA
AO11EOXA9FMK74+D71aEYM2SIbUFLaZtidEEt/yAwMtogTmK2ip41pAS52D/J8U7BqFUOiKp7BEW9wHJDxmuyWYAu24SQ4aQ1MnQ
5eWcXz0W7pSCFLUt2eDZhHmCCcDDHsxtKHrGhWgBhjNY5f3fnE+zzAaYKbpSeNyBAy1iC8vkX0tL6mqjIddD2ew7mcQ9aavlAczm
RyUG5iMXtBvcRCsZsi3pch3ZWruf1zed+Ccj4sChQb8dTBA+Q7OBqaZ8Q41qMn2M6zgDglaC3M3MpSNnaKT+nXqgcsKrl0h/W4T0
44YarLIRaIWzNPI0D4gppCaU+J+HDvEq50F19ZcMAKbpUdO0i9on+3yRRDvRtBsvY8x3XX8xWZMOpSza4zWTet5hmzyncKmEJvYx
fandFSa2Z6+BUb3qzcMmOlgE+k6eMe/FBzJyhhKSBMiREWWCAFYJzmsEbiqrLUR0Z5cgF60/1etUIwFEXvBwHocTa3qlk1QBJfQn
XMEowxhaiaNQhdJhbiiqWKwXIVMPQdiiSHaH0AgcxyMRNy0Yhlm5AyXNueIN6y2LrJHCy+8Lug2W45sQIkL58i36HyjzLOn+CIXN
Z/JAzRXDPw9avV/CnVDN8NEuua8MJVuo/u2h4tHe/H7Vur5jbE204z/O0a73yvk7NP51jpzc2SYDjB7MK7S0DT14F3GBXPJdsixb
1IlznsZqGABMib2XQRDtS+87VsLYngAM7tNlp/L/cBokiiGrs5EsirfkfMxe2TTNmyNLhOZ/TLvJbb6wFgznKQ+dqDkBUZrjVr1D
NFCxh7IPXd+9El9pZbxUuV3z7CnEB51+xYhZ/CIcGw0MaeOreyAhKJppPskz6ZS4oFyWlaNnrudOlnHuKYQf8q7qDcbGeNMrd3Nb
mHgSYOmpFPj3wrKgyB4/GxeVohezyefn+MtxUTNf0jD7c4aYB4T0ZopTcJWHovF/nW0Or6MbVG6d+ToYCXXOto4TWxIByc4udPPZ
udK/jyyWnFnOoap2L7M1X0i37ykCdglMs3X5zqixyVed5ou5OckT0jKmSykdxN79mVs5nzlc1vVSzKruAu7DZ2UavmgjKqsJ7VcV
vqVrj1Sf2eDoXDhRGvNgfnx3LUgpIMkK6FR6jvz9uKEt1T/XBLIRx9N9b8a3Xz4OviWCc/AmvwHFQP1aSX764CdDite5FLHHsP96
UdZT/crnW11tgo5lsKfj8pxdTHxUShCFg8Mg4yvae6tlDgdXgQv96Jx1ZyXjt6JIccD75wL6vDYIUiqMg7WlBbIR/8x+naC7rb+6
ShOmOqEiqLDok8dkH/Agqc4m/kFi1cD3PvChFzsbbxacBGHkTLBIoponhzQLjnOe7hToemcSq9Vz6mByYVLLTfVEszMQlej8916U
hEuhHQqqEr8nbeoq9fI306GbDpoP+iCh3ziRFZvvJgdiKaHLfQ2C2xo8mGCtdivHFzRySbVvdcGEPgTGZJr1jfL7Se00YYHjEd4f
C31gEWnEDKx+EhqyL8FsYyrk7VoLX9d1EUUTrJGrT/IiIh1BkZUIu7rI1HNhMWiD6dO3kdmd8m6OePJjP8HPFpoTZZNINBZ1O2LG
HjW71AJFA7Azg/RRpq17YWCdHWQDJ5sXfnhd6PcWBTUUcsO3QNzmcAq9li2s0BaghVBDly7ijLkIYXBYalevtFVvOUrToWceVMwt
tL1PLM7951e3aKAzUjcTaxgoBwFCm2pse7E4uGcLfDRE4EoVEAaBi2paWYD9ozWre/909bYRsRyDH8Q3tJmyeVz2lNp0GPxLuCAA
z3fRfEqFW4slvrot1KWDjgtDSfe9UXTVyYM8D6HRGMW1FaDJ5vApwscEcRz8WGvcdxwlSPFP+RQ7CGt4Po0+U828NFGEV7QljwwC
KIC1VGTkmoPxJHAaDwGXYRY1/DnOcyeEqvGwN2LMRpJAop2UokgfxaTJAUYPErL9WrfOheCO1VxjMbAByzgidUGZoY3G/erWG2MC
CEjkJbq6adTqIu8XWFocXiBqP5703mCT9l3XKFH9jqRQHR9Ad9002W97bTdeYX5MI06lxKTzUQXGFvzZ3ezNeQcfuf2EDg1QVBNI
BEaneqyHkUugr/yok/PKV8PJeyXt8/rC7AE0zw6lR5TBC8GL1E1Kh+lM5DJ0ZhQ9nmxIXgJu906k+S4nRIZj4qcx99OYV90RZIiM
e1xylUOjEZbyZINgELmnPeZIcqNXZP0oaBIKASQHGqsyq2dVDxyvYOh1M5QRB184dB8oPPt63PXQLVgIROxEEdiwbFiDg5PXrkKq
tw8czUyutTROujiLX5C8OOsY3d1gS0K2xu5kk8CLMp5qCMjy4CNte4+coQBCL7pjDs1pXMY1eOhtWBPaF8na5SvjtcvAwYXGgBan
jvpdUKBv1EI2BG9wQMK5e9LGPn9y7P2CqFN0orTMfxNPa7N+R8BgkfH67RhA8wOXMuE68idbiwEXm5XAhKSFjkqeUnBTS/mUzvZV
BtIlhmwfhT7Dtqu+T6CiTkLvrTURr0yzy69Iwikpoy9sDkHgkjf2h9JZkKt8xj3XcvSQTbDS7CrtFiFnOW2/whbQ6N9PWIy0PMvn
dNcDw0SzMMsuHcwtlFYzC4thFzGETtEeTJ9jqDMUHSlYiVEf2ZZXeNMcmpz1IfLGeR+qbU0Fs9XH0y7SlEmQswxN4pkJObMySjwL
86x1NFr98/zUgCuVprPc2MTij6JK+j0F4yp9bYxEuZ89Ea3QQxxg5rQ6v5NycOucPgFk6jXGuTO6hYzMRiVTzdtexkNJRVCPsgkl
9tIrNQPLMjVN1gv0cUKZLytc8A9wRYYChS4k/I5nCicMs5SinkGvVdK1tnbD03JGOaVP2WIEbEViTjPYHhuBdZ7IZYMjL3zyj8ca
YTAoIm841PzMqNFApfc52sXdA7gGq7r12guxlnu9MJkrhhC9sATJEcNxLP0HsHIQtMLBOhLRq9C4Ue7uO752NcMpY3vTjwesRdL3
Tnq/Qbh6aur1WJdJEJJypcg5WKC8XxfgbvGCwjmySDH6pfVOnEcx+JEfGFikd451JofKqSrWwdwrHagNrQFWT4cGhyi+6E7LR9zU
HqKst4YgYHxcBPJa0Kt0YMCMd0cubqGksaU5fToPhBnAbJvbflw0pXWl4/2Do3GhZVkDYZ+RtM1uxm3fNByNqzSVj6C9N82nREFu
GBt8SJ/UlxmcV2ioptPsC8xUKlrRnXk9M8EMK3rgVOYyb4Mo3gx11zQx59ITOmyWyD3gmG5aR2y8LcB8tDxckyJXHI8Pl0OOixWx
tFZIKxxQCpwjLhz77Hxf/+kyGv88lhqTRyHL1V76v7lGnFK4ITWfyNdHgjbwBsGzNiVHG6URN5scjKCqBwYqpLJ6eRx2aRSZPPED
F+ve1X6D1I9DEGcR7odG+df79BZYYQEKRXKwlgnNRXAb1poPLMRd4WLkMCS04dcy213DxauVs3DeihT3Y+o78IAKULrfOuRe1aLC
tSmPt3oP1grJ/WoDutp6S8Kabyf/thBbpw8KidckDs6MFKTIEMr4aAIuhZoP1kekM+99VTqG2WRSS+falzmtw47i7BIrOV/AH9B7
FD68zmFGD8NUy3nkO7lB8x6jIop3XPRFP3UJLnI8zN8FRHK4C1Q0J6aekMJZMw157YMC0bwDDF5mtyLYCCsllqN+fT7lXFkG/+AE
6GnG6SFuxAzxBUWOtIBrjVlkel7QsLrW0Zan6rYOcJrgX7VaSmqTtwtrl7xzXe+pV8WH4gnn1fMWtom/2BWrcbwOrGdZv7xTfOLW
+nFEjpjbAE48SuyQ2UALurzBuXa8DJ22WAiXEXOFpaYl9zf/arS6mVScKRbxipJriHnEh1yKz+t0ET/DaCqyXCE6zXfViOyuuI1F
G+jQabn4ZFraGr5pMU4bA5w51nWE+WrBEjvbpA4LzhtpcgH4BeaKjBztUdIsXsyPD0LsmIOlRZRlF4eqUyw5Jq3OfMTcSru/VPfL
QcQqApcLK55PxUR13HrMVRehx41SBc3dG/9Tu4+83dMhIIC4l9uijXAubINE+V2JvB/wj1BTydcO8oL8RxTB3jPoflLq1PRWIUd0
JwuaK2i98ncfG+v1kgZHFSeVm7pzPf68fZMdftUMQZEcYxWy2+HB0M0B3dTaAleE974hw7M903zrz8OAyCzDx1xcLZ9XswR7HOWu
6PH3X+6SDLBUminiMxrt66NzHI+fqGqCIGROP5mAVGlgNjHivHmyVLmja//yCPz2LRlqYRb9VHD693qEl6gVTP6TVmotR/pTDIk6
HooH5qHTljYIEnZz+yqVWSxLHsM28n64uvo6Th8oAknFLSNaidrp39Pi4Xr6iu13CkN5V/P7LYE4NoYRz2stZNuUqxq4V8x+qNSA
SIWOg+PU9lEbUPlt6edFH8yvZrfgSxVWLcECcsVpiMqGztxyADtfgwbq2m+ArDkL/m/eBhiZ75e8U/1TZmJL9tv7UbqkFut91C7o
oTTDglpcAfs8ClslRbpMCfGKPtI3vYfk5coFEKwhyHARNrqzW4uFbT8pB93GAlmeNeOVCkYgVi3gBQ6rKY3c+yAZfsAvb0VYoBL/
gBmQKjD6RdGyBuxfWubqr9evVmjpTgfIdr9HxTGjLt3hn27470vpp/dfy418A4GVgIIMGYjHi0c1DnRLeY9asKI7ZTxTgtJRnEf/
ZoLXJuGJoX/NIuyd4kNScRPx614EcPy2iOzCfwTmL1epN5Itg/ZGH/pkmLoMga8/YHFwt8qxBkI8mh2nWz/C1DUD/C9/wkjZqX7t
m2S8i2rKEi2+df0jvWDsRn4ZSAk9VzgLNHvelo7p5K7GIwv45axoxvJCVGDxdFJinrQKpjXS2y4ieMiAnCPUqM4qUWM+H+MMKRA4
N6fO1KJYPbdPY/pOgb3BfDXsxjEcmN5PNxUf33SIpcqv5kCsaBgq7TPH8VCS43+VLfr24wPxd6tYEuLsav5pitmB84dRE05276lJ
Ws3BHSfw5s+VkVZTyYsWmzKOpkcOMDk6Z1RThk3qfbMX7htBG/D3x/T0D3+K0nDn2Y9UGKgdvX0dtg9DQREv+c5kJXK90pCd5hBX
vKwju4uqQ3Yo0aDePen0KovT/65dTiBBftgkCMF7+m/nqzkNvC8N/qFkXkie7JVhKj23eJgHXBSezotqYdtcSDYAIuGQ5Hs7CJmf
WRQShdPy4iWGj2PsY/iBI9Vit8lJH4jmcbL3DNyUqC5tKLkUdpO9+lGwwol709Ev6EMpPR6u34hu/WB6yZYuhfDg2ilM5LpsEhNv
iEChyJBTy60cqWQ/OiL/LiX6CUAZYS6TujYH0x8AXjDFOV1RudEEw3gagkHKamElS4Qhj8vhrmGRBcSXc27vHtStM8D06NHg9Uq5
74WzkwNBYnpU8y44Q5/qw+lFl3wm1EeuK7rH/DvlBSMx7FKZJvUl4jm5gDZOCeud0sQE1AzTtjvJaIulOsFoqIIHuIqvQHbYh1W0
qQDGumwVi1DePgAfEvJhotxLSmm9NZF3vH87Af6T7KS8WQFJJzr1vPX/9Odr4hco8mrDf0dlyBViuA6ICGK7bZdMWRd/h3kzk04p
qCqJhHA9j+T39qbb7qsFBX2seiRRiQ3pN94sPZNBbUEWbEr3msjXVgS+wQtMpefXy6zhZyAuHUXuWk5myZtOoq66y3H/zsIT3w/y
u79U8VzJOyAJMXPXRNEMSLinnRXaQ9ccjWYb1HvkfjUKXD4Lu5GlqTQnTgbQLv240ldXP9ya4QU7FPDHIujXYE+n1P7T1WcXK52m
wmmDLoRw7l7SfIdPVhkRG9tJPxwuIBSWuGzTcMnaBaGH5aZkWidj1ervCF0rH9f8tlP8/4ID7RyfP3Tfig1LCPIvwBDLeOuPkv9y
d6O/xccadPS3Gfx5BfQUOfqNPjsI93+w+fsdqcCr3YoPHCCYG/UpeWsVNTNNDrxOuTfGPMFQKt9IS0GdkIVVPVryFRDheXePwfPj
h6zumotqKY05DYWaE8OnWOKYxdmgQVV7nOQR0puIsFFSlj3AtWyhpQXN85R4TJHV/ij9Qmpn19sXwkp9mU8rWKUeJW522utpmt+K
KtBYB/Wm/noY1Z40k/PuubmwQmWYIHYyVzm7XC86zym0buFmzaLa3lAm3npi7XI6toVf19v2jxMcHPaxqsNYb2+Gbp01hSCgC4VT
fAxQ5lMSIYJv8Ci9gtTs1u6vwp6+slUp96vAo1uUxDZ2d432xoE0IqOhr2P/PnOyDz7zTk5wzOGCgWm2pqgqaF4deC3czWnvjkD+
d8beZw7+UtOSMAWfB+hTzaKaoU73ZXEIvMFv5u+0ctYlt3vyohqEr+Rsq+smgBA7bCMjp4h1Oo3lEklD/Je6KH9dyU9kwdr83v6B
r4wFU6md0f1t6IX2qURVNZhMkVvayV//v7VUcZnrg4iG9mWO0O+/MZTVpLB3jqBiYjVqIVpXLn4KjhYcDRdWN0s/WakEO4askA9T
LnZeOmxxnpk04lfJYGH6MT6QhvwmAqFFElSAUQjGErsawbYPTchmtLbjbhszhvC6YkgO9EEfRNR29TsCeYvl4wt19PLJfNKcvVDe
55G6tuKD3LBYz5UGNr9cneByfgjjrMG7cz5TNpCIrt/mLmnZMXijXlNvc6VFomEgU1/ZihbwRJkCGH9bZJYpD0+j+0Rw48BSnJrp
h2n4RFwO6zG9T/o09Aqy1EznlPYMZ78WPO5a+oef0qzQHT0RTl40V+YTJ/+QgVPgVrhlgXpJTnJRQwNywdbQmv1q7PvvpEJBW5iK
iF+Orz9gNQs+yQ5aQaR6uhLaurVnEZO8u/UlAYjd2z74sWCCkktwlqvEAsFQXYheRENpTp1qAccZ7Nd//N/OJKadTqh3ZE3rB6jo
Pjgx/wGyNN96atLdSF6AJrIxhLQofh9bh/bqk5TUdcaGZt+BWj65WC3X++oQYzCuninzYkmWEdcNljASJg25eDGrsuWrTAALoePg
1zB5+SrovvxVRvq1hCt2Vib4w4BhlVm/AORQq+hbHgRd9xrp0/YHyp58W5oezoowNsAf58oKe+vqF8P36ueZgeWlvcJ8CTIQ20zO
WuPs72cjba16T12PFCA/W0QItaNTlPhEyCHhrqXYWYOKKgmYU6sar7wIjHxThbW5wkQkDEcAN4faFl19M/wHn24hGoAyuVdgvwnA
WkkDBSqOUtd7/T+4iGh8Sx97WQymgsbT8HCUVP545iplYbV7p88rzokV7l+Fz7XLox/zSdwZqnbds3iEJy4UA4qes76g2byNvqLr
ABIF5mrxBThr7VV1JYya3n67wrwhbubO7oVS9Z6d6HGo6lvDlkyKRlhNWzOUmKCWXnU7V8aBzVWhx0qwbprsAbZcpNX6bgVO0ykL
6ByJ3ckVXDA/HYzKzopFoK5rt5lNOwtOoVcCjevvszVSCgj2jheaUmaCVDA11qjZq/EBMMrpGw4KfmK3Mg7y+R6NLc8EbJKhoBDa
Ag5xHgMQofJWfLfPK5mhbLivuToJ7gCV2dda4G7uTEyt9+8k4ovQ/Prvz6/ANgqlxBXrF64ENJefHujzmyn6T+znMBqqrauPRM2g
k6x1zLi4ibPnkdycoq5zX/LMgtXqPbhpVsaXtgyLS3TiAiTuNu+5wK1wTw+qJEVxuBE4DlL6vzr017xDqBRIe4Lh3MTnr8ZFjN9e
nf4gplurp/0ar8FHsy6bWf8grKMW9jnNoXpkWA3DziKdOBBHiNOU/h7yhpPWPvcNX2ahw2vtCzzTnwBF3gG9motvQUmh/zQZyBxe
lVNs4WpQnHkeYo+4G6ctoOSWcfO+7mEEJtMp6CgiDTPjzmpG5mg4RYWmlIpANSeBp5sZoJyE09uyhlQVzdRpHQB5UOM+KgwU6gRp
SFVrkyXihIN8I7PMshBjZsqo/40eCRFmOM9icTEcXa1MORwUIAMEy2gSdK3le277oNGZa55lLhjcZey9xcgeN8QS57DmIES6Fj5K
K6xOWNKOzpfNCRzGJLmy6CSMobkTTSZR0Y2QrANMz/VQWzoYRSsqROm01nR1qT2MwqMeFreGNI2y1nRwlj2bCei2dohHObbRRWpp
mxP59rPnCOFQZvRf0pxs+NwLF0s7V6uBiYO6kSO1LEXrDtbLr65NVAPbgQRfRoX3pU8BHYBOMhKyyBmXhfg0tMGxakgohi/QH3s2
NTnYjw0OHuhgWvborWtkdkpj2efmkZpa190gg3xykyrNJ9rnb8blFq7KwwNEGDlQGOfUjQ3jEiUhkPv5JCwovIZwT7AGVmDRXHXd
m58qf1sYKSvXc5lOJe5dnegDnUvkjw4CkAqcOrzuhSM57QJnOdCEQzywMiZBh78P0b2HV6GP9evPpo1tykbC8taU4Qre1hggkmsA
1OyYOPh3xevRx4rQOkPZqs2wkdJNplRJ80yv42+qKGTTWAsWZ0T80JkPWWyOSQhpbs20hOgiVrgrX01nInSoHgd7Qirfi0NqbjsW
eF64UflgbXSYKdtMYRXrcP2cFev4zXt6UQ61Pz1Xuwr//UV19qt9pSGyZ+heHR2eeFjLempWG1WGF67ZWfp/6s5Ic9dmQnapUfsQ
vfjElN2Yvw+zmtAVNCEVOlapz+i2T4UUQ8VZRc7GVI1pfyyGt0r8IS/5+tB0/nAx10twLoC8N8hzdQTMWgTtug1F5hVB5876QZg3
N168LjPZcwKIepsE8sMec4uxpSBEodUTHfDDMj2QSdt251XotMgUAGtMBthhUDrz9FYMlcj6iZs2y82HL2PYD+LVzQoPgbuuo6wa
826oLy11hPDb7DHwVGUr2I00S3IXpRJGfaoOtUSknkLvoggpN6eKR4NdBwAgydokYaZJrRyRKnOo1mmDHnOvp+7jYGKw/J2PZUJ8
vDBWpQb15CoAeWkZwhJPM20bYVykxWKnKjp+iD2NAHfPVP7NcyM6EVAGa/R6MSsraFh/U3+VEIaIU8zLseDQpd2mVdW7qqOIYRd0
FypaHMx0szFa10opDP8IWlkQejDmaVwubg//PIuT+cr14paBZ7oW9OscB+8TUHYvKoUb2AC9qIo0rnUmnqmqMrxvAYIK0jfcHArQ
NLGNw5UnLseLT/LwAZdyaOd7APEZhYtwx22koplFmEfUwqQZVbwcutIgsxrSYtnS5G78oKb2La2g31m7dhyrlMHpRLFKxkL/Z/No
dD3lwfZWvzJaSfPWkwLU130CweoPZ8RBuCnvVooNslffjyWe0CB9WiQv9aawzAVVdJBOp3xsrwvGLKsmMm4EuKf9zVgj4LDzP+5p
m0HbBbNeQWwsN2JBL9JBN3bi4Iynbw8/oiIA58SykMSUqQgy/2y7m8TtQpdGJK+Ekbg6epwg1aXTUq7OT+lJ9b62bKcUBkRSz69Y
5kdgYx12vgQ355ne1t6FhfdQBw5MCunuCUEaa3cTzIJ6ArHP2TOyuwnedYyOrWf7ZyZcXZKqDbnncV/p1yd+RsCxVemzoP06vFHX
IMYVtuSjrf6u8oEQgiZ18A4YB7gCOfmAiRdLlt1Ecp3gfGHnJ+/+k3bMO6S+1Hf54sYFKJlZNaTjy+GvwFyzvWfl7UYKc/RpKyXp
X3p7kTXmC9FnAIeE3FmVAnP31/E0TZm+LfimsGbPvrHaW3nxcDBWwNIVSAJePhIMWGLH65KoFVDX8dGQAXuFB73Q9T3XKlysC8C0
Bo1/7AOoDAPiaA5yZ1z4LiPBpRJTX0fEMTUSqfn+EmaEIfxPVaPhaZNtKUWBpCq0ZqnEKbQqRin4Vbxss/RIOy/G5lbscfd0mQND
kSRK6/Rhe5+WdzWl0ob92T88fJaIbO0uwGPFCaWfPQ/HDsT/7M+DAe1lT1ekn+RY5c7RSHtYr2wGzGcVdm1iXuloWdASL5uSis0o
yrIHzp/OrwJzKzQQgBvaCuqXDqab0FPOZxvUZEg2sFW7+yKuD16kQNMjD42hk2fXVP+O4idzLnWapaxmNC3WQtOXLO1ZvhQTuFFn
T/kvIaDPtttXW0ieHYypddfoV4SLq/SPgDns/9ouk1ZJ3f6zD7+9umAoD7Onf5GxywqsOVwfscoaGBihRUopOzh4t5Zudc5HacCg
e0RJbOdmiCct0b+Tm4CqFiNl99fBc87mP630Bb5Xg9TnmRewE3s06pIQ5IynmPz+AqElmulqy//MFRYzTpCzFpr8ZkftCDsOMCu6
L9EHsVyBVo7p9M4X+yPBE6uoljFQg8aXGxCxdGH6ah+Wh/ChMEDASprEoURqR8d0jR4vnTIWeyczIMiThI09E6whNQ+oKL3skGIT
Ctiaa1xt5DbO1NwkBbtOTMqWZk0vmOeadRad4TL/xhu/Dko0HZ+j5lM+GjSOC9TqYNGt4swV0ZNHSJOybEHkb/Uen++kRzQ7IXcu
YS4NNpjYGhDM/Boj85cFPWBwWDAqJV9aT9eQ9wkIBspYGQ/3c1qNEzxp1EG/gzL1JB52Y3XbPoOm/5Nb072pwGe0EeaWwJP2WzVz
L0mKqZh715AU15WK7pBkr77dCSEBp4vJfF0W+F3FEaVFnU99Vd8uxc38Un13yJdDI+yYU5FJSdJP0GsS0TZ9or2CmB+mbjqet1d+
qzILYI2HjnH72yguPSF1wh3tSTezQMf+6PFAVBg1jCHS0i4ZtnhVb+KUZdwZMkBFXf+Jk67w3EVSCJS42BmrObEWyguzpIS/A6vl
z54uV3IE0bd/MAjCkmYwY0GqD2boD2F4dhJVV8AFr+KHfXgc0M3rtNNVa3otPwJOERqe3Tq5yC3+BkKhg48Lq+FEZPzr/+PSmaPt
PPPYb75DCA9ugW+qhiFMzkf02kDOYq9MREY5kW4XlbEpkMHRuySkwzZrL56zLj/nvpi3t/4k/1QgvObPVsT/2TjzliZNInewHGKT
yEP/ZIu915Nfu5ZZfsm6C4XzyDx7YbVYIJ0HGyMsWwmyd+Gmui3E+WGpOHaEodvpXgRXBMygGRnGEng4Vmr8BdVykN2xAtEu/Q3q
rV8ElEMZ19G8eGh9AQGv9QQzCrZ2Y2TSrHaZP2UXn9rwv5OF8r6AM2j53/B/rRb5WlfPEZqu8WQ3O8P2raKDB9Z2uNBavosHrQJX
xz10Fw3aCPW9XlSMWuXJCN6fWC3M3rvqiK+vz74wQ0j4/ikc3af63AL6CT59aHv/78s2WR6jpk9a+yM+a3rlP3C2MD6N7YJvozen
Mp7pUM4lj0k2/Sr2C93xNgS+fHJV8Ka+W1mTMqZtN2w+csPQHdoueUArPdFkQV26fNRqV8WYkwkofqUss6ofFW3jF3NQbA9rZXk+
zAlqg97McsZ3RmjTIwnS6OgSfyVPimeBD4Zp/RVI/euFwKSrJXGyceoEPgfgOophnZLiiwxSagaI9wuLsW8jat2E/qqaQL1gl3vj
NTA3/CdN9tp68amuotGZ8I3DEtp/PQq9yKycGGLFaz0cBuuKnRkLTNbTyiu6agcxmOGQcAi8kfzAxMMbaazOyt9MGRYrn1x9N5Z5
jI9NS7D+OHNxVYooAY/BAbFo90X9HIbEMcheOkgyBM9UfNrrYwBVctxkKOjkz/FWiV20met52uno7LEe4Iws3Jg/w/OMoQAWjIfQ
9Nol46DPq5tLevPhYApybpJJAIlneH4iPj1/XMkBnySycsH0lc+POw3sDn75DMaQNBRWcF7p+U2MXxoMvOBD/o3obJda6pUcBTA8
DN61AB6flHpmwcPSUF49e3asV0bttx+Ph/lhcY+veW0UDWVcp5BfXgzRuBY7UanqTOtOLhUHhUxvVhUM/CS91nV+JnOWcRMoXFkI
f1nVR7VNBhLRTVriFe0hFf3dVFXtuiTxw9Q3qsPs7plskaBRqYrIbK/0R4ZcDm4aRHQxufdoMLIf9wm+MdLUtGArvhPXWZy2Oa1x
t0BBrJQ9e30X2lMEN/5kTvd+vxFl74LE/49WNqHbvbyRXEl88LuImE8Ty7rOT0/5+kUjsmsb95yAxZFqSAKApQK8KjXMUiHvFnQT
YCE0ld7p3vLFmaCcouHcPhxHrtUxgFLuoY5zu3j24QzxiTb6cIWjyyPzspxQXlmX3QZn2gMuiy/vNmFHA7HxCUREkyyx/qZUUJ1B
1wZAJ3RFj/iw9thwaOrw/eMidykHjcL3tASEgOW/CEbd1WYtEjpCImw4CMbrl1bV4nGjYutl4fUcW1zqWa5cqe7XPOlcFy58K8CI
koutWscoCDRFX6M+MfBsuHv3jwr1z1XSiRSYwXi+KAFK9hTZeGdu3SHVkrhoVGe16hOTyZRiYmbMTTdl9m1rmdc7febAX30adFHX
9nouhCfPvyyx9FboRdNgHbVcosHzVHhVp2sFNEPTyu32887IbYGV/LNoTnFn57QJQ0W/s6Eft7nHON652mpP5RHA78Xhz78R4DLe
mijUGahb5Ysje4ZNgu6Lvv2gQLcAld1zxT3upQOrGhHIpJzIUwV8mC1qkFA6MaPQj7hCcGhCN8UKth2GqW4fONz9hti5FGC/ZMlQ
bCCuG3reKIg1RuKuKqQzysHiKnREDfjscX0FHB4M9ZyJu1bI8nFZWlLJhJtyqjQXR59AuqczcHGpucG0u7MAMltLRlmAUsBJxjJg
UouJ0BHjTcSTV7l/nQ8oJlm/9MKhrzB6Co6xtV1SpHdEWp5Dk9RZibQpJXQpbtySVa+i36ZheKTRQyqiBhj1LfA0zB0kCpYmliDP
YqYWu6Zswe3qLfUz+9eXmqHXZ0kueXB8f4VoP8Josgsmqlkr3yhAjeoIrk4/HIGrkZvAvk7cpZ9tvguXF0rP/AOkMzxhQfdmcmI2
w4CrXemE0XEeFL71d5hwY1gAMyfh3ZD/SgemBZIAJVr+akfQKwojgZ/FpIZpxV83iH5Y1RtTQU18YDCJkD22owvmfbA6OetNGQzG
3eq5fVpsyENazgiQ7iWoPsYWcO2nnSIJIeRCuYO1ajjhtE1jmzJSjRAEsWBIN06DnfI4V17jTDaUn3OZq48LZcYwfZvFsNi4qZG9
LeyghIzVuFZNYkyY9jWzg23asl645cnEYx2DmqWCei3DmXfsK2gZNpO9y20Y3gIGJ7XBS8c64+czECaRt47mrFU3Rr8sa/oXp1nk
EcRzBhe4Se78Aag/E1D+Jd6hbN8nYdZLfFWbk30nny0VEV8lzg++G2zhXwtTUMiIdCH9RbrFmMyCWy16XFaAwma2xp2qnCS0fdvU
ZGd37jx5Tx06H3zl8ObcsOmULRbEnuFyXKYsGAJFYI5CYH8/imMjiece0zmT5fIMf+wFR4umlelDnPoWFE6mqdCHK6L7VG6K4Ks2
r13vVG7cG8T/8wGVCMw5fvyisu3dBIwKIHJxKhTkV/gQ5E0d1AggjXNWAFey3jtnyfntChDcMmtgp1WGcsbNnpH+5hwiawwmU0Vf
Dv8p/KOg0AsHrNEhm8xU5eJekJb3W++K45VruE102gHnxlPAVfH+cgBT6Bd8GoHfHl5ak6LLuCUDnkEbmIh03YSUnjdqZIOxkc6C
WuD+4Z77xXq1tXG2CEcXIUF4GSJAPVkdSUh6Yb6zwWP0f2/ZBLFS4+YGtD50piqhVvPDMzQZKP9DMJ+sA3VZ5nc9i9YZyTBK24Vo
JwTwP1ek1yssufGZBzkSf9ETusn1UjkMgIclNZyZ1cIolt1fAOYSRsuJq82LHH+vHK31hcxwd3pF6Hs9njtyV8CN9HDJf0uZ9pZB
QLhY6+sFvSR2h4wS1qrOSAbh4LYjVro3FN1lhGa/A1utRDD+ZHNRzptX9kTw+m+7w34GNtvtt2iNYUP7jg1I4OS8do5K93dS7Qbq
0A8CcFhOgqBUCA//Aqwlz1MHIBAQZFN84dUTpfzYpxakRi4f4Q0MhDRH8GBbHRUx5ncRMsfxe9nrlDdEQYKmKsZMRAUKYeDE9NZg
ErwoDIXu7NQXoQZm1BbGUzUT1uhy/hksMNcZXmwpNoPikpzq1J3ff2sQUWgAfHY9jE+oa7ccqo2NZd8JpLJWfXvoiFDa72vd+TNE
uHLsmA8/+wa1ZpvEFP2/FL94SKngpJBRTHcnlGEAPT/7p/D+CdrAu61WctCXqD1mT25f4PQb96x3jZ2xWsPxxN1HvGLI+df9FrGn
aOkF17eoT3op27PIlrpaU3LtoRO8aflvnsBhVMCM6b4kdIhNJPBjCGlFD4kiYTYR/DHIRCzTCrg1nrV5tjKM7yQBUF6MkaxAHCy3
C6hMLFd3+98TO3BA22Aop4uiq/ziVntF7HbJF6oVBdSY5WXSgqYS+D6Vn03j1Rwt2jveIX/5O07HKmpN212yyzwf1zFz5ja/uy+w
dL9oRWCneS046x02RqCPu6k+7GFwOUQpfS32WiUwmx0OtQlrMBJrHfKOWmCKtotN/TtXg16f2BE1tOLB1AuK6LwE8ApCIegX8aSZ
m+DqN3WRxtyzODlpIDM8TcAARBFNhnbfasZWEyJVyrIpIKXhaOR6GDNJDZn6ffN358v9daCjPuOqtnAYo36TqGmtKCIPX+RLD5M3
NnFfW+DqLIQNveS9Ow5gYVD3SdOjRhuYUhcVYe5jZRMWya3U8Ta+mMxVPRNxJRNekf711ij3SkauK7HvraUs5XWR4Zd1ztjP3BPg
YYa5XwIgNOl6+0jmhClPabtOGfcyrNipKwFVea+Ei0otSAkS+mGScfqGq0aJDmwBgLjdkUOQRccUDHCef6ZI8pXP0Fu/Ted29FdG
hIUfxSR2toM/3oWzQdjf5FxDclWDEiVgCsbWBx8bOeUfhqdBwojI5CJBmbOyUYuHcW37ZkABHjE8C+0Agy7dkmV0SCHgWxIoYXp3
DByB7Sz0Oufa7TOckyirDm2KG8a8sNz7PCtcY69a5g//YQudx6Bz8tlpkL01Gf6+fFK4lC8kzycCAz0H3/mKYQD8TMqskwFqGGzL
soFmvn6B8F7gEjr9GjO/p+G5kZsNeDPjwyjGVJQbwH1Rq0YHFnSZIwYhU3Zvsc9YZRPNepG+jrb0tMLB5QgaJ+u1OUfiNXYxi91b
z+Os/5OHL3r7KHVQYekS+VXmgObSO8Xl80LsOYlNXwBGYPNscrGrxpJ7LjUu1w77n1wOg6cmh6lCGIShZoKZFyA+dlkAwiElSvjH
8YyNi8lT9HKPNze1H7yK2Y6sAkx5Z29AsyHEmw2f/dpiyWiGbXMv7Hfv9Qs3LuLj9/9PH73ZxKahgCW24am+uQ+JlZYf4XuKvv4B
Ym+SrERzFC4ZznQgFLjbrx5nngKXeXU/ec37CfUkG1znklIRilvPyVnYRC/YFoJ1KT2JzisMsl9RJePhy7ANLlnkUAHCn4wNwlh7
rTLp28esuxbVP35Tbqd4W+UEBlsL/vWvebEWKJvS+JUt/eTn/1Y2FgvRMwS+JMy0MkPtidvEFMh3g26Jr4EzOeaU9BZPJlVJC2EE
oMVt31rfO3e+qbssh+LyP5re+erwsUENZ0Wzv9nVbO0KTTZ87s/bqpHBm9Dhrdylvsl7ItYaxMBKq0/OplQaNMTbTMZ1vfpT0Glv
vy0iCnkAGroK4vLwwMBai2E6ZMRmcRUNDhx/TyOv8/p+1CBGOOl24XEsLPiE1RabERMqsQCLXuvpsXh1a5LDp2LwQ98jkHfV1dkm
pxak3PCUr3PMF+SKy3ehF+IiD2ddE5R4nVejJF/QM3iXS3qxbny9KAWhPpE/0vxv7XLBxlALl2ad2jx+XQ0YgaPz1ZR0ZoDa0/cS
bK1m3b3h3uo4Tu1tsPznQo7Sbq1XgnAv7gc6T3bVGvqW7lvxJxJmfw/JLHUNcy96mtfQ61s4gyxeNMLUSl34vxseMNFx8lLrsZKJ
dYyFfHwGLMmf+tYM1u495od3VJuXGFreLqweuvjbByYdPqS2Fzmx2NdwdJXmd661InSgcWmifFYOP8oo4jHjcEx+Zc6gSqdaC7+d
HLj5U/dcni0WKRvQsSSRAheIqcl3v75k+KRFFQKGbUNbU/DBAZllQPb7L6MbPsVFX0s9UNdOljZecWSLB/gPs1nVigMmwkTsxskw
GRz/6XzBT51B9gdSRIjnaROvXhFd0D9im2p5HZqAZyg0CgKAJxurGR7r6h0FiN9v6L7AB1+3j13dMzIQKWu5GQrXJ7S2PA9b0ZaZ
+WwKS2sPqEEryRY7pPd0sMYVwwwU0GhWUQneL2ZlO49IL0d4kp2DMe5ZV6J5dptHTc9Z0M2Zk58+mx5aRCZSDpo+kFISoOnzOQL9
bktAtUZsQacqePW9eNVgGlvXyeFHfa/33oHm+Skzx5GhnoelFhxsQMnQLck/kh0Nd/YmvqPT9WxEZrK8wKCU+vjuT8M0je0jOe1V
UOr5pt/Hpd4VfgXZJnDWI9NGifunyRedcVLC4cjixYI9wwv2x5zk+pO7acxgVxsCqJvBbPvOXm5roXKboc5VMzutriSWwg1MtKGM
rLueydHiNE1BuwsTIrUdr6o7pIsIFdYa1wwGkGDTiHrY85RzDUyMXry0EmiaXWkNSn3bNCVTJWzuV/WjIPANk6z+hKpS7LoftRi/
z29xswtKv/jLYP4FEB9Q3LizVLTnOiCnYMBMAp+HacjBkechPaVozHZUA2gLrLC92JFd9mqqzFDB0EB/ecEFHpp1ZEsuDrgd+7vd
pedwre+CmE20hMqSv/e/Sx+SOtW13imWW0RLcDVKXA/wjdT5SmwQFneaaZBc+IqUVKpJzNXLuGzBbt3LU9Jkgy412deOmvSO8Ylx
a68pCf+Pcdw6Q02JK6gftr72tBlb285l2PSTuZs7+6ThNDjuMWPdqalmgZK4PR6aZCIKmMM8hvYXwgzayIS+6kaHGRIwhrCf3vZU
khszPyX1PGAVG7DZDVmA+KoiLAeb/GJS+TAruoOfrFyqmFAjz3QVd+QmZMAR0QJBHBWtiGn8cd6RRgJZ/nbdsg3Ws74s1Nb31FJd
S5g//5kzUrUMyeoV4GluOu3J2VPqdt4z6dwokzEnPWq4KDYetJ+tPrOPmkHKi1smxh7RvkyiQ7laiNLDqGBB8zIrJnTvVTryo37n
ftPeyrqU71R3eb8VekSGxVg/1p9NvCBqmT0RGRQMIfGHK802By0msTt5etDMs5Tzbjb1h4lMEHTBRpftbKz5B/ZKg8G+6RWjs7Go
eqAXZicNWLnYDuBzrnI5zyejrWw/golXV5HnTXsfLEkdYo7Rx+BwPKSNCcSMjFM9TXyr1PFOlZ9P3tXn3SIMfMntXlFrh0VPX9dd
f4auCrMEG+6+BPr6Ank6+j++R12itzcNfKeFUJfqu1l6wBW1GPNTL8Tqptggo244LjN+9BwH+hDtp/XD672T0e3uMedGO9uo4Psc
uS+8fUes6MK3O+36NsAqqpeVoej0gh1SYXEpeTwQyxCwsjZaHYBwF4i9nWQPlDjBO0qjHoU6UiA1elEr9Z1nn1enOG2MOtGw+ul4
wXjONkPYmfMsdwpmrnHvnxLypoejGS3F3zpcOnaJvPARtc2447CRO1R6zj8QU+usWNyVZFkkY6cRHfx2BdvfB3cswyDWb+XogaS6
sKQSGfVEljYqpv6YKgQ5JaFsDwKRTMJO0JBS/5ilKV3y5kC+0b1/1MR4shk4b/rGe3PnHABAnHnsvY9X2KhXJAqK3evTgaEB/ijJ
6jOtCBa4bFrgWhXhMfeztK05VdcwumSEZbRXn1yiZYu+XDKMYMjcPhvyxT4+gUwDN5w07fKs3gqf5qjoqC+8e2Z8zOvE8lbwLu7F
UsQi7VO8J9sOJ1fsFBewgUdtMXc2DFSkfIrMuFEV3TYFqyMUlf8MJg+7JmJ6+lX7V9eE5iID4go9bAjdkIZCyI+dIfiUA6GSj594
mhc8dFhGCC3zYPYdQBpa9YMHDJwphFZ0yB0tl7E0Ks1f4R/8SBDHlleq+oGjF8lgP6PdSGOKO/A4uhtLmx9n8IJdfJxmoPG4lC86
3qgPUmHxf6L5gFqkpNWGvrj3FffGJjK0NSMxBFBlaPxwtPMt9XGvPu7QZVdZJho38oyb7N2PlpIBGPQN6qkBxwGih1KmbxWN+ajj
tYas6hvefDL4O1qCk53novs7IKbvKRhCOnGQEPOa6OSXoNh62FKw3vSGm45At/RNQEMuKnpUYXPW1HFtV4JyltKWt+ZGenv2tC+H
nnu0EPg+IAG5OSgrBrtCQaOkUo0JFP/OF2DT1JLJTDmiI75Gd161XAQpqIPEgerfR8aMnntOS7d3b1H7sdUTewZ1roSJsSQWo39m
8J4gZ33x041vJfltNWDi5P6kFY2usLlN3ScL2bfrekvy8fIezVANVjwepTU31C7gb4+xNoYgUiQJp/M3WFrO1fUz5CY3XsmFLN3U
nJ2pEnHNGH5paHJKkNTHJS7mU2g3hhFtBylxNrAe5voYw3bjv3uyUE3X5C7+DBwzdX3A3XYXXUyFEfXQet8Pm8I4a3Ixx7JwaMBE
N5MB4HFT8t/MedRvw+7m06ch2WewI7FwrdNx3cJAO+YOm6XnrOEHcelFEp2i++A7K9xf/cYCKDfEDWLynHJgsMS34kFy79LBzfJ3
jBTh2CSc/UXjS1CJwGpl9Wnhp60L6h6rJDopzRUQUEwp1wNupygsgcCp4gwm53kqGSttPNF80U0aQVSIfAIdvCYcetLSSK1Iley5
3d9HxKaCXKte351Ntbo7LWWQApz8tur6Oeoq3POGMWwgeNh2WW1xEgC7f+p8tQ3EzXki6FMDirYwhWDvddCqKCKld04HAkO+qFst
iBRYL2YqPOJ6YwJS/mahkOEF96qgHqOCjbg06nkL1tF4iipSLJLSho6nnKux/3THA/T9ExoZtYdtv4DsOzfjqNwmTuCwwv73/BSM
WDwZcdcRikQ44CYSqz0AOBM6S0+20vFraC6q3EOWi8HorWnshzssQA7aV9bXA1wkvbFXHm2fxlRiJRMoM1lrjP0ru4hW/2V3DlTQ
aQt16508BnC9P1m2evi/vMaDF5PLGMvmPzjIF7ncEKFL3pO+2PpVe1jlL2PqtcVfTuRAf/PzbRIvuynk8SJgzyH0xAGSphy2gKAA
QII+N+WRrOPl4tNsn3MDt7jQG4V30amsFfJEXIJBEUQn0xZ6BQCKty0OpnDFtIfue2pzUXd0Sn/q7RuxaXhDTIBvCU1OcWXvvxWb
Fge0ENyBBGUyqSo/Y3CoWTdBGw1XoxqaWYBK92vOrkPf3EcNM9xOWUzVU2ayHXSflsPMDgCvhklvQu8E8rXdvqTgY0YtXM9fsKwN
bEfrWdFIzhGobDwcemB4ygs26PM7LtW/T7unPaLTJt0Gu4OBLbqvcBX5akZTTHppUL3B2dFBwser+sZXKgWON8gEHkGUOc+5/1o1
vZbx6JWwMtfg5J69dr0tokGcGODwscsdmrB39UJuOIPOikQOFE8Rtr9StCzdM3A4MaLlWNUqmKD9TeL4Z6NfeAkVCm2w8cXkajGb
VfbHKzBwAqH1M7UGeKj09HOEuTq7dhY6NjwSa2FgUX6S9lEkFV3J1mwOpA7jNyHqWbjchLadBJPqf8x+TlLMDJJSZDjE6pX/Tr77
sHNTt40ZkTY7ua7KL58bcIMe/HJoAeZeK4cX1eWim/LWSjO3CuXWOAfiIM2y10AVWB6NtGoBS/xBzp/aEwbANRD90r0ZnEiRqvVY
xL3NMLvvpoTpiPgKJDIxa8YavT5jEDuV0v4RkWpwpmWTDYHLzBp4meGvrCtWriaZdnM3AxQD2Sm89btca743iuKVk4MfffsLJf9J
EwIV8Ksb+kShJMHRk2ePCzI+H5fs3TATB0URbCs2y+pG/VE0C1dxiQaNGkbMzD/cezqK3ebydJsPEjb5Bbt0Qg6UJCysAFjjnJrD
aUZo1PDHQHWlaAYzNP4n6uUZxg4hD2b4mgpj4wqEF8I7n3MVWgqOjp3lSXPak45KRrABb/lg3VTZ1/QrOpcNKtZC/yPwUg6GW1dk
uGmUez+byuHGk6+6SeqRZ95DYnn477m3TV4OqhWlyR3Qm6VU/AKwIVAgI/nsFO5dUps1HINCzer1oHzaiIw2WI+fUvcBJ1s1Ms4D
2g3FpcjVy6+JjyTkZa/LbeXSgGH1JT4h57DAQPFZfCKTUHQBpgb4m67DBSON51kLLlumTAFjAmtCrpoPxJexNojG5Lu7CLzdx8iB
zy3CYOjf0d3WaIIsF/NjFDw1sWylscixBmrjLkDpQqincZ8UHyk/YqSEkszouJJyheVbCGLHFBY6H2Emfjo0FO9mAajf2UsoAQVB
eveekkwhail4C3I+Cw9jSOt3/G3wlD+wE7yADV1uZNlK7V+wNqLWjuCgLjy85ICVEAstp4W+NDbDFhuNa+YyY+t4/RaIelhTzw28
IqpvXTDdXa3h2jU1GqNC7i5UHhjFejgzUbv0Rmgq4OuetszxBBvHUbV6KXO7GkDGKTf8Y+4lWsXtAmZbphE9AdStgCZusBRzivcB
6w8xjIAxoATEtqikCS2yuDDj/NlHer3owxco2LODZ380wrqkERdSFT7hwwoeYGMPYFwHGzxYPWr7NmV2dUZAo21UXO+f6T3CjqIW
kzmAwA0BzsMecSCWVzdtOC/fKyg1MGNyKWNBZJpmKw9W97qg43oVlG6na2qj2q9VfIhwj369ZDcyTu2mNf6xZ5f1NGkFS8Jr7Sf4
7l3mEPws2MjesBsreTAM7ysqhgoRc6Jcx1wZqFygk5TidJ8KEjw2LZM8ezVvVfxnMpc5d719M/bBkCy8MsJ4Gm87Jv/08CMkBeRd
Szkg2+fbXt8qIyzExgfT58o5GvI0nSdRylgk0Ng6wdY2IXOT1AbQw2YVMtFKi/THRJyt4jjMSF+m/J0KboezaiWEYcHnAydIjKpI
fRZrJXElHIV2cxpZ7oeqd522tZDlWmqxf3sHIIcvF2lT4mjbk9vKdRkl1cPqsLKWDuqTpcNMwcKQ1TZfULzHWA7IjN3suvq163Ji
3HxbksTJM726OKt7FCj+l9AKyHvJn/qDymOfPWauCw7kxrBSHu0u4GM/htmJgdbIT0KLv/Gqqi7E2lIzcrZcJtbesxBEBY2K9W1T
c3Hwi1KuQgmrsG9PrhKrbtoyDxKfkeWplNVVx/Nxv6lwzWK3hzEcFOqDFb+3rXcJTmb+4+wDvwTdL8iupVOrCWOgHbMz1LLov8fJ
P5+R7YXrCo1F+Z/+xgm0n3Tqra+t3QZZCD87n4PrXKb0kCT5TcqTeXBKN9b5P6uaqNhDejV/oR1UbtTUb/KXOiKgYrIaUEKa3/HF
5HBsWsoaYTXwVqEE9mfF9kZ0SqBK43pdJs7LWEaKaxgPVCkA/kOSVVG/zXmuL0+SC7kI8F/FTr2u+PfKigHGpvLVCa8cj2qTY/TZ
MnNL/DFP7S+kCAKlCaRQQJ8QQ2zi4IXReaiQdRajtg/8Swkx2px2Ms20PmjLy4NGCm/ruGa7r4nLYBgLW/pFapp7WcwFM4BDn8Ql
itD8hZtNSnxrBn3HhCDFBafKrEv6uZeenpgsBwyDvWtcrfuwKu10aXzkwyp3sjfg7mofpgv9zgcCp5RQ0YxyLRE2bvUPmf1DziJI
uaoiCRAHyEC5BCQW0ue27VGvkSl8t6WzHUZ3/RztVZ15rdrcVR//xRsL+bfKcoVe87ORhvqCmFiKTzD0WlVb3XdOKVpF+z/xKcH1
oF6C1f6Svbdbxbvf3ifweOHDBveIO34yyG4occkJ8CmtTJ0E7u2aHBvu1CsKtyru8gfD4/xAE0ZtNhgaGd7ghXz99WSZTff3ynaZ
F/xMu5FDP5B3Val1Mu2zV+JZllpE4JXF9GOk2iVepvkB7uiHCX8MD2JQDCv7qbPc7C2cxF5XT84nqBoC1rMckiVCRwjC0SaXeSGo
gX2/PBoWQUsqQnTtBGmX7nK5BabUGOxHHaoYcCjrswEc4rHR75KiBjhyZZZZ/mo3vvPPxwTrBET1Ov3LUExgY29lc0UGBqOO28mB
SNG/AxVgs5JANiYT3rruP4+h8jypeEZQtCELb2iKqQXike6W9VrpiY4ujjeHn0PkptEnorQGKHIslEiPBYgA2Bz9ygruaNj5sQIt
W7sjqks0CN+eu8R8VNln0DsftOzVCPtciq0cqFuxf86UmN0kaqPhopks/1e8nFDhGFgg0kGCz11QAzyFrQS/37phDO/3WgL2LkO/
wcgrYcwiAtULY2e1s5T3zHkYBBlr2ivbsZbhPhG1znOsEdPtdgUCv0zpba4XIspqKh98n5v95kyi/DI4eYLXxwHM/mAPoOnaZVBo
AXaEnwpQRbC89MyhEFdO13sdjWMftZhnKWH+hKGBacVaxdzE608lW+zuJL25bGhZrfjrTtKcRxiQzOEbSymITDvpn1OepyahUITH
RCIvz6XZBjob2tIDdxBBMI3LouAdH8tO5R4BfmfER64Z/Rk6bpvtDHiXtKTk0wh5g+i1B2JyDosIg8OTUs9kQuzNTmzU8KJN1kwS
lH3odHSmrnVpi6pPzZuRJMJdJzEz0y7lfKLdNaHBN49m8sweT9ps3doJlcmDboE+vP3IPclCNFy/Qj0SI6IoWirWOvP+s/VrAgZ2
mrF0RWv8l0XRudfevtUNRGPytWrtnfM9bq/7Ztl4KPMaz3cmQN62qE4yjGcTIQDQ1Ap53dcMjhUNW2o4pov2wxHgNlxdDKWZZDru
RqHwRLJR+hJk0RRn7c7tkUybT3GVcBrCAHZwQwfofoMrEv3fu5iHLZppr8dlvP3S3w9B+a0ukTklQ4LPgmiwSIbi+o9OP8VA+BoE
wMlaGetHYafhlpgrnM1+fDsKYAzAYjbu7f2EkbjqUBrXwzI2S2oWtzdSQoTwbMgVBQ0rF4aHXpexxR+HEhcmG3WnXQJwR11MVFPc
26nh9ck3uDl1p8IGj+/PEzH+35RvbxiJYDWsCT1zAr7kvmmwptw8+BaN6a8Qz6qSO+tTSIngkC/foPGMEXf3CpgqtDATycLD1Rwc
aqGRZyB3xPm+aGG3Zri+M95iURIax6gXWA/xZQYVqLFUEmbFZva3LcC908MW606Y82DdqTdlzmdo1hmB6Ek1xKWjhaSUNZFK8mwc
3LmQtgyOyaKAs/97HTNB6tEIaOSxzseoUr30hpbogcl2SxKk0UphohD75FFXQRYoyPzPksL1cm0RMf6uBG4BV3dBRxugMOt8hwXQ
nQrS7RU874ZRP3+bOCe6OraxUhg6B3y+jszrFLFtiWnpZlJ23D8GVc0uKpgRg/2MejVAaEDUSnWcgrCCfnxlDWrrvZCOe67MNgH6
2nZYOQ33ZBMS3dWzyuP8Ro24i6cU2Mhdjgl5galJc0vuxUh98rxgfFx9NTmofHqF6lzvuBiyc7CxOqdlTqpmcV3eG2+UK3ElK8OB
9ihZBj1sSO4tRlvVVI/9Bs82FRw97N7HzX3D+1BavjtoB+R5JPg/GCT02/bCN69Roc8tl+14eVfW/ysx+nCfWG1Y2J8TMNDa4DHg
jAfclRYNR27Rv9Qkkt/qRdcp0Mz2OyNHdXBEg/+rU+ohThrGeFd/3SaF0wk9I4dJJ+XnGbUrY7aCSg9jnDMGa7uuAHH5ICnt6ynO
os/n4Sm59EN9uo36fxRCzMT90F/2k7+NZ7I1e4rnrtu5uJMiEKReYkPmH8CiVJipUFdLzrv+ndF24IlHwFA8cjZzj+suiuiaYX3M
InoPI8Uv44hgf0bpjxxkx7FdSb72z1Ucwghk2xve1hf+hX9BgY08M126/URR/lwy5sRNd6aV1uGS6ZYF6I9iT3JEckNeXopAbyjY
hXbne5jDq1BlRhTikF7bq6sDXlMM88dHiwlQMuopTLV6QziS8T2KK+mlyiInNvlMbo963b2boI5ONeHJZV4gFd5ERGy6DK9DxGpJ
7d1VmghS2mGvr+xrQpNV9OF+gPNcpgsEHlond5VtKxP5SXq2mwjDEzbKX4Hwo+aO+WJPwhKbWh4ZPPy97OxLTl0NUk+EQs3r66eU
5396UOVdTLJKHgCps3wizX+Hj+fwXvunjNajicQg4wicf+5tjoJ/+a74dwXdrYj2d5iAMbe8Xga/fBbsnzULMUpqWzeVBGxmVQcJ
IdC7Mi4Ud488aNql6NfgirhDXUQlWVZE1ZmZEcfTWVVyWgg2ClETPB42M9DhAiUOCaTO6Ui4+qXVqH4Xj3iRMnRzydNe4eH6bQh9
vT94EaHfRRXEFEYtM6TItvtGzjujlysR22wguec02e2Lo/9yJ7Z7jOlbhgeAN6sR1L8KdmhBeqvtgp9n4EVd5X+p7rxYVFMN/nSS
avTE1Am9alcNCMQA3bWS6v7z/9mvsvJHKDwRYkgouvk2dBGkrsxj3J/mnQORHJmryD5KOTyPbk+3R5NyHHef8m5nlYLv9tTlj11D
PDLmLPaxVCo34+qnI/RjE8KBTq700fzTsrYNVZSKVKWpGuX2Kgyii3OU/o3tsiizFabW5rVUJFy/8Oz6IWYoh064FWz8DU4QsDxh
yGFjoXdT9YE4S+Vpj1RhcfcgwDBeSXAk6n6IaEvXdqnapMtxKos7dI4e21KYEvySK8PNwhN6HjFO2aWShXjtybbEdUA6LKBM6uMN
jhiIcIjWkBxiG8WpgzI1EjaafPuvAPYGqdAFMyrADYCPaXNt7WlwkCo3KV48KhW/PGKeoWL+Y1R6l+lJee5ERz9yADBLDCsLE4H9
6HD1801eSWsRXGlJfaXLQj4LndlytsfoX3eKTg4iHG0T3iMNsyA1+NoKQkENa2zLThLDV3h6i2aX9H5lYHYwR6namddLqb1/Cpvc
qhWOAauanqqYzeBj7Q9TyGgPND0RRMCn41Ns++GLE12E2TFLVxxFUjCsOH5NqIDerG19RIDvZ1k0YTrtP6oynuNijIRDkX+r3Lzf
gmsfrLRh4fwpAtwqqAdk7w6sC2RvqAj8ClicJLgfELMvvV6XDSdQBJgaPds/IDyaPbaP2Zh5zh62+sLUQtlONllICjtRIWfjR5gy
020Nun6NkX0UEm/Nu2qp3nZc8ZX2K7en0pPp7GYmZQ9YWE7/1CLwaAqOCkywog7nq2n8/NhVz5ilaktZwBpHy1iyMjPNl//w401R
DqWL4Ve8S5EUlLpvDnKz8mfMZaNNV/YqU9lSNyCfPrt1xhwC2ZfKBbhiwDh7+vGR3F71hHn6SP85uNiNNugKPQobn6PwYhGhIx6x
gXt9izYio9YaN2LQxPkbxKaOoRFFbUNK3nf5HeVwIItRE1EBjCYJttblqcZ3al33QN1z5uELS82MSIiCyyHH6VzgJ1a8Ko5u6rEW
ghZhKiETDv/S9UVky0Me6MWci6SFjLh1imQmyAyxNeqbd8ramVjbfW6/6PYJybTDLMjYAFRHLdQ31uVKWklqGGeDoMqrxas2SZc8
F0HEZWDiOcB0qMXcnwxuEBEd7kaYYt9H5AGfc0C6t2H8oTOo7EyjnSRnENDm6PbCwWHSDnu36mP2fH8q8waADRvBXFkPDQXdq8pl
CYAaSiXmyIvV8XG/SxspiHVC44Fsxnm74kVNjj7CGhX2RZwVPKXnNChPxa2U7GtEl+UkqzaOfmc1AoW4xBKx9te8A5xtTPno2URF
haqUYNiOw+9LqCAXArkDxJiLJBDCbGSzk2N2aTRZB8IFv6tlfGcUe1iF31QUBnlcHv0/TUK2KkqLlcoRuwodXhxtsgDMAj+mFVSn
LuzRqVlOb4GtOko5tEtt0ZE/5PgJcWVgeFpGY22zNFqmA7GYVe0gOGPlhohA+HfANCqVqRl7OPjvxoD77lbcDYuw4N/9UppBQJpI
KkZ9Gf6B2rsm8m4tojP981FqXn7TRoGxyelcLIjTOGgLjc0FIuVFnIdf26FHT9C6VW8j6yq6Etj9zU0G5yn5zR/4qMEc6496XhtO
a4HHGgcjWPY58SKimx+m2Qh2b18rlxcqWuxk5qk+Uhp+8xDBK6AnQlH6DXZuxUuSSdhlQcbysZLdzwAm2hJd9ne1FiCDer6aa8WZ
cUyOoGTTd8R04cN6uXSYyqi5AYfwOvz9bHp52UilIz2tmbBf5xrTYuPTeGHoO8e/jJJN5qqZoUnex1ky6d2cdypZG5jqb+FitM5a
gdA4qQD5CP3K8gXc97S2YOeCbgrB52cv6Yu9kNYJM1ax8z8uYR94te21UZIOENuRsvfhzucBeWSDCTQSLWFdA55RHg2Y6EmTbFAJ
ySUi9bK5N39oNw5s2aN9Sdahkd09YoOlI6xJlaoQDLdGn4PoEpTNWuOU87EBABgB5RR18ulLC2KXf3dGvbEwU17TVZ4T9JVEcqf3
wxcKbDbZIg23F/waykgCxdbqmePjmmWcq/c4eCZ7rShSinSWEipvfYLhIhawPzhk+bJ+QlMLbdA9wlKDcEWRSbcoggq0RshnsCMH
+Bm4xqInCL8o21NQt1I5xz3mKBsa2rq4Bvcw9mNtktl5+zx3cF5a6ix7X50ASYxpaDoom3QnGUHQ5BvJUihI9/+7JvwRc8xaSi08
G2x2xny2/HH/qgAoukdKT2chSvWLruQ1ERcMtpM06aWebOsKMu/XBHTd0XaF9ZgTm0qgRzdQHYpnv7uhr37uqP/OAzPzSPEKTnwy
TRX31nFSQVVr/meCMliESJBKApZ8Q0jbMjtyfaGVe314o8wskysBBrOohjsoBa9x3uNarONkCFyOCpEgsgSEJjr+7Jj1z0mPk1TM
gumEyinPbnPRhDbAC6v0QsZamz8IVSzYB0C6IEc+s5qhZG9LE5vZMEWNwDXcAndIKzFCFn4NNHL1K3ly3knIbn4dyS29RHBtDMke
de07k2TL4A2o9hymC06OvnPvcE/jLLtBS2UQaFP1GI2wHE3nLCsF1POsqXJVVOCbDFs1Djr8aLYYFYj/3bjpkVKjOtqCkbnX1goJ
JfsYjvYk4fZy71ztypwEnqgJ2m/gHWAsCv3fx7grwEUG88EjRvFVGCzz8ghq3OucVkwMSpGK/fGhgniGiGjzitSjAljTLB1GdYWS
vEqCiAvW4o64NVELEjbdI/B5i/bxWqtJ5959dAWJ8CKhP96KfNgz+ThN2fd3jl6LXUj37GIn6a9fQXiIke4/rig2qNiOMQ52IJF6
AoYJvrCUj7Dd8QWUyFRS6ur4YUnIwa67EGClg88qMbmqKo3VBzxA9Asj8HOsQLA9SMqlOEqH5cQkXjfGKsrKEm7BdxKDTs3yzaJL
o3DigVkXHIlPo37UpQYJeLTq4VWBriwwlt7VC06qSof44o+572de9I3ObEwnI2POw1WNAKba2kWXJdX/dYueRUptNBD1+QEJZY34
qZgBYIJPbb9O65TUsSAy7aexYYiMdnZfdL+7Pvt72dbNCXq9VP53kSxkFXD6Of/kzu8UY8W+VB8tH4CCCGFZ6MPzwkVLUoFcMce7
2FvgdRrlYYSYRpikVn/iEXEZ+IPbd8tN1ZYf6T9tBsHE+NanAvEhXZwQTZyIxQdj+oXqMn+30s6o6QwGUz/bI+a5X/Ju4/hoguMM
cl4RHnlkYbrXeNxNq+aXyGSfEYRgzqkK9BdtKjkUsHZpJCQoZxW1bv3vcl7LpvAIyIRrYJfXtl0qUBuYGQt8Om5/hq9VKgpqAosK
feKCA0UQmfsglh0CA9D5MHEeWmKtco29uTCDenSmTvazwUoTt8zlQJUfsewD6f25s/k3faUdFmnU5s3jzqx5XGf/nawkoWuJDy6X
2vAwPXMPywjYtwiMLhTqK2HVyJ3M83gxIznZu10aROo6jyLyvjUcf2hN2914J4OYUlbT8t4giqapWN9Afca21jdX5p35EnsOlNDj
t/i7oKHREg4OEiy0Mml8abe/6uHnN9gOjANMzqVwuMrd+GJ3gGm2Vza7LspWv++jaLMr8cDvTAzcZqLtcZ4wQ3i++H+HakZzvey8
g6VVPZ8Kf9AFsFf3iN+ulq2dIXtMJsEDDArG0nBWXrz+XAGDj6H041VpaHtwFL7/NCrinP579LrHb80zWg8OVazCn7avqfzY5KwZ
jW810Lp1kggfeyv8hGfLKkH7biGZ2d0OZV9X1ZZvFbNy1vVI2oZbt1HLMt2EQpzMeJTXOcSOvJjUMp8Cn7DboY2HJZl0w3Gq7t7e
zG5lMb75XVAQR9gEENGQxk9/d0OzRzG959fMr2I8EWDphOANAe/WKtwaelLSZmgL12jyEX1TaAY1RYWYqVh5VnXPpNLP2pUVuHXq
3nQPCo4FM5qAARvRIsU+Ee4ktctYNF12+qBz8wk/sEV3gKjz/rHzTepO0iOtLd4BHywNG00IkCKvXN25hWdrsfO/rFIvlz4g4751
Wnbk4v+y5mxNlpUTcoLvHJq5Vi0qHcKr0viNmqszXd5CMud/bFo+Xn8sj97/JNuL6ltlJRzxqB4t/nP4JdrkexLEzDL6GbUTt9cx
HXlqN2HbhOrNQrYwtulqKNLX6a5H+otiU79LC/2+luTnO5JMbL53OQNDxshqZ6osvHlZ3wFD11+9+QDQ83svG191jQ8K7LkZXn0X
SSr3FXDhWRDXAxsHo3lrIseklNKK0Lx3ZJmYxfLoO9JSv+EvkEe6j8T7wG57r7Q1v92O0RbH3vKZCQtdUz31NtDMYqdyH4tpILPd
vRElY2P2RfdKaQOSFva1FQRAgRibpABLPGA358V3pHJERoVDkMlKXrxhEgmJeow+mh3nPMPHgypIuO5LDfS+gfkYBip3pMWBhhyg
wie2pryAYcdvMgH4T6UsjZ8iWqthRvwAY05LcIc0KlT4FFufGXvQIdqsb5H3RGwwkMyMkcudhl5pcdKAi8zj9BVoN9CoA5p5tu5q
LQZL95iuDe4sYegwijoOlVfz2zjzrot4HQ/ne7t07nLXGmX62ngSc+zp1RRPmwfuM8OVnKi9fYf/HzY340oMsVx97sHlk5LXHb5N
uSg9uOWzy+d29RQZWbOjslgIjh3PsjjHPD/zOVcKF41stF9+tgKGY1+5GEyPzbFBuCuTE3i2ey2PPIfg1Yi8eocamtwdLpBDcI+6
NNj4mIVA5jWaSwLDFV2b5+FOvdFc3oDl97sPF48zYpR0SyWfFJ07935xsSltfV6Yu4E+ozBraGeEIle29KXi2SQGP1kt059Z44rQ
ZY4+mj5Zcnm7WhrATguXemle2gKWAiiYWEXysS3M3TQPJqYFi9cAQYmQOG78G3afdcAqBhLO1S+EPYZqwkzn9/H9V+r+SAdZocKH
dGrUgrKIuGIaZgoFXq23OA708Kcs+ZFqHXL0Ndewoy+pIVz5FFEAnaPFcPc+1ucVb4WP7zA6I9X5n/Dg7zrMVA4LaX4zwhzw1iRL
sR5nWMtr6K4K0O3Fn4gJ92J1xfTfOh017cPbXi7PMPZAocVSZI6LewMEYKu7FtWyH4NRKu8Abk3dqm8fPi6izRsC6lz38bEupKaV
P2AaNOOcXe+Jh1VVHUpGIbmanoW9OUu+C2CFHDXG6XtuP7snf3WjFO6Ugg9iHgMES1wpJxGsQNjOHzuJx367FjahGQVCV1w4/tIO
n4JoRgPKdIcShT+RAOEV30Nn/IWDX85nLw0VybUL3IonUmcJpi6VnE36Jiv/Bc/n76uoD4uMl572SfdhQt/blSbnBkRTu+6xyrN7
UmRebOf7P4PkrHyH1WRb7UNHBZec+fEvpdzE0l5zKnK5nPzrBi96WmTe/6tvv73B0TvRecQx/AazeFa6iOOjZnXMrV5R/K8F36pr
skhM3onW0E9sjCKmtHQRpp892RTWzsKULFWC9JRYm1pzGXkwRZahubSK7JFmxnePdfgazWhsoLNgcZVjmmBrMV16YsjHHxHyo8U5
dNs/7UU6nw2l9+UC0nx/ncCASHf2Diam3EnLBrlg75Xyw7xiAHdUFtW8AIuDotiLKP5Mc/9l7lxwmIsWbljgBLGilJepeLVsSw71
ch3329TkvXMQrZEeAsvmERzf3YPaFb+J2OvGOHkzgITNZxinsWQpICFHiFD3pvVPnwqGmCUqHhaiJe9vPXFDClvleyKL2ynUG3yf
5IzhnWNIpnnKFUTZe83x2I2QPOkYyrBbvs3n+wnbbv/P4tqq//3Irw0PTgBYYSV+kt93wBvbNZFThOmD4HQVtJCGdf2cf2MAVLnH
I5uKoHC/2OxMPfuT4r5CBAJRSPEOd2zIJhvPGTV4jgDaFM3ciIjOW7ctF7rmeHCGqI+LiCc7FtyddvT2wf8Y8FBj+ld2OlrOLqI7
WzJGeixoOwJBMOdTPthA//NHYymAFPmEzTHcGdlp1JCU1oD3MFuf6SVddTVdmqXRzjKd+AnNHnLJ4aaIeaSpZNmIEu+NdU0sEiUF
p+y8hWVaB9/3jnGzUz9bixgw7UROcq/qD8hT178NmpugMwjTsOphrWllwc1xN6UznKcafiXV/jEZ0M9ycuMFEqZyHIo+XvAijW6R
Ia6albGyRTnmLjvMzFyjYsXEMapzlSGRo3gEoIr3TEngO6Q249qoGTbMzvYDaS+j4fiCFRHvhbIQ4L1L1D4qy1byb3vVtF9j+L/9
wu7/Gw/huNSciZaJ3URk3v3Sxfd2X+Vod5L0heEu7h0Sr5ygDlp/Te0RjcBptGwTJ2oW9ojfTL9oQWCLV5knY5SDMVGZ8/oxCxI9
15pbCqdy5xFv3vlW/gIgwIrgIlDTmeU2AHcrDJuLdCkq1HE7NyffxJfRplC3+bQV4AYqbrBd1JXQoLG3Q8jwYSWUIMZXsVP4VVKf
eXiC/GMAijyus1/+cE7mDNV1zBQisqqaoq1uhuRXNBq2sbwlzLLYndDZeYWCUi8fpDTskZFljV93xDR9/9/r7kRVeUMAIzJQ0a+R
rjD7wl57qdreEaudBOBkH/ZxvNmm9GZ5W539+F4d0OaTduIDPORzlSkrmXbnQik2FQ2PaMnGSnFwPdD8oYv9NPIT4JzKgwiWJSRy
NboSrpjUH8XN+j9GIh4RZ4KdSp12oRcDEX8tv2hPFSrFkFn0mRaliXTs9rAX0juiscxmHBeHjKtvQlvwEJPIx9nUKCNVHlaXLJHw
ruqCU/fgRjyVAfkizo07IJCLnUi6usCIg4UzVxiNVNv2Xf2InxK0C02KlViOvMQHuQfJdJfJQbMjxKY5oGz9tPl0rZWu+UXOQwLF
qtJ8gepH4JDDkLjUQX1HRBxBMhC7gJ7OrG45QdvzmcHC1JSEyWV1mqmSEYVETcsLI/5hh3UvNcYTQBI6Rv7Ex1DUJ1YkfK83VDiv
gExVkNV9fRGeIB+xAu5uy4Yzkt2kPOFlsy5SZb/4hgZZHIpj1Cs25MJWtleymuklt/dI81Zg95P0smOAf9+EZSYFu+FD6Ya0XE46
Ye2kYkF4BDjy6OfLmp6j3iVdjKgXMVSJHabiFv6vkHo5/ty/R9zzx9SCMtj4CqqJCQQxsEw62GoT45dd+MhxD04s1VMEpzDR5z0F
ndumSrt/LCfnPjAtSSXhfHRzemBkXvCaCygH3M4xJLVV1eihInE0tQ9CyRH3zbfC2YH4G/gmC/KirByWN3ldLZHZyGq/QalV1Biq
1gicXanMvDlHYF0DANBmi7BeFSfZ9u4PMVrwhj24Zd4bHs1ZJ4A2m0rkHvrtKqu2VGLsML0BLtCLBjhtf1r7BUyfcOqsDu+1HHqJ
j5EC+wgGPlfj/TNXUiZFJYyl9dO6i5JY/805wb24KdWIMGXb/xBaLVGB+N+Cht+oyLIDFjx894zE6kfAnlYhjhy3A+LIP5kPkRCu
GP2XZabGEuVwQTzbwG6Oc5mYgbjWtmraQ3J6Bv7iEPK3BgZUyhJ6qTZ8jAk+vjLuudaO2rToz6zyFiq6EaITkslBUpJDtVorjyQg
CLhKlxUOFX2gdsY73rOm/2PvrMwmFvMsPoJ5QM8KzzbMPyUksqzNBsvf7sbZBLYG3su+Ti40l0iM0O+SJqYkwEfrD9hZw060qxsx
zTBa6NjS3YTJhYYZ2bIndS95wTAflQgLqRf7ArlSHscDIuuxDhgWRVB1nXYBUl8C1gQceVMXfAo8RyDgwLfuhd383rcJXvMi15mD
zVWffDh4QjCMEdjfw345eqTAWSCJrOHjOPAhqVGjAVGIuP7kW4/g1KlBIbWoRpZuJqOYwgqyC3FrjU6YqerAA7LNjePCW2DVBQvz
Z0ThXPP4zpWE97VyMcD0CMBOTQmylMP6mL+Xh2wq/ia3y5vRXH7aDDlVpEtZvH2PZKoplpwn7Zb3N7rgQNf3uPdB6ahDavK+oCgx
JlMS7TcaoU7CSp9S+Bxh6//boAweqkzwfJl9A6Ft2PqKNdY03ssxTqI1YF9oKyt8sVy59GC611uT977fvw04xoQN84bjCs+DMjBm
/+Lu5YHzcDAx9kPftGj1jv0JtwaicRdRl014S13oChBJZWDpPkOUJPNdPoKg9GUi27xahuGfC9KHEa+BoNcpHOJ7Z3qCIZ55de4u
RnpxuBz3d0pp+a9OWEUXdPiJ0bHs0YoKTU9jav2cnT9oDcl+4fBpK6cQ/lM9gLre624cGlsdgI7Sa6YmfaU9RooSYh/QxJqasuo4
RqNQ3Tc6oh4Ykr3BMI/ya/mB2AAEaZOrQBuAb7rqWcJYqniuGf7j/XajIVua9DO2Hy7XcXYBPpCC4ZJgoPQqb9FEvFGDxnaIlg/7
3t+sjpZNguaExDy79R0GecnLNMPmrd1iIpj5UgELgSAMouH9I7e8/VVwt5PSr2eht1NldvTXpAkq6lm7cJxwh3j+9FiCIbC6zn/G
ReYJH/k+ghqEZfUvgEocJCobAPxD5jPGPCn6EPVReK0mQeEH9h6aYF7H50ynKZehs0GUzj3PZ6sfYgNAqe8u4v2ZTHlYUW4wulU/
MPzortyjoSfcxmJE5Rq+q2IlNqFeDC/OMeyWo8RNfdf2EFgF7/57ZGuAuqICFASPXfNIGUuR3N+n/QG8c+6E4vMMKYoVT/0bTL4e
Fj1mV1MGsW0icGCZRpvYwUmK7Ghb9w8D2BPKByA//f18pqezlF1FnEw+1cTXXEDCX5Ctz6FdxmSFx0bDFSAfJTEF4znBj1pAvLsa
vE8XPJLotuQFBJN1FkvuL9OiyKEzFNAZJP5ZKXWmwTbzM7YhoOZlo+ZfLRWBQinsQv7pGhdeQXbojui+uZxcUXlg3SAxO9KkU4/2
VUQ+vaFfCUqc4NSNWHSlzDSMTCnCyRbe1ItzNgLKXsvRe6bCYb/82KGoNOvHEQZXpSIAAACOffDo1CgCygABzrcG1bQHBSm0+rHE
Z/sCAAAAAARZWg==
'
# Release managers de httpd y APR (Eric Covener, Stefan Eissing, Jim Jagielski, Daniel Ruggeri,
# Christophe Jaillet, Yann Ylavic, Joe Orton, Graham Leggett y Jeff Trawick)
GPG_FPR_APACHE="65B2D44FE74BD5E3DE3AC3F082781DE46D5954FA 26F51EF9A82F4ACB43F1903ED377C9E7D1944C66
A93D62ECC3C8EA12DB220EC934EA76E6791485A8 8B39757B1D8A994DF2433ED58B3A601F08C975E5
B9E8213AEFB861AF35A41F2C995E35221AD84DFF E3480043595621FE56105F112AB12A7ADC55C003
C55AB7B9139EB2263CD1AABC19B033D1760C227B 8935926745E1CE7E3ED748F6EC99EE267EB5F61A
93525CFCF6FDFFB3FD9700DD5A4B10AE43B56A27 CBA1525BAA7A47BE28FF23DDD3B13FCA2CE60BED
EB138C6AF0FC691001B16D93344A844D751D7F27 5B5181C2C0AB13E59DA3F7A3EC582EB639FF092C"
# MariaDB Signing Key
GPG_FPR_MARIADB="177F4010FE56CA3336300305F1656F24C74CD1D8"
# Isaac Bennetch, Marc Delisle, Michal Cihar y el equipo de seguridad de phpMyAdmin
GPG_FPR_PMA="3D06A59ECE730EB71B511C17CE752F178259BD92 436FF1884B1A0C3FDCBF0D79FEFC65D181AF644A
63CB1DF1EF12CF2AC0EE5A329C27B31342B7511D 5BAD38CFB98050B94BD7FB5BDA68AB39218AB947"

# Release managers de cada rama de PHP (php.net/gpg-keys.php). Una rama que no esta aqui no se
# puede comprobar: hay que actualizar lvm-instalador
function php_gpg_fprs() {
    case $1 in
        7.4) echo "5A52880781F755608BF815FC910DEB46F53EA312 42670A7FE4D0441C8E4632349E4FDC074A4EF02D" ;;
        8.0) echo "1729F83938DA44E27BA0F4D3DBDB397470D12172 BFDDD28642824F8118EF77909B67A5C12229118F 2C16C765DBE54A088130F1BC4B9B5F600B55F3B4 39B641343D8C104B2B146DC3F9C39DC0B9698544" ;;
        8.1) echo "528995BFEDFBA7191D46839EF9BA0ADA31CBD89E 39B641343D8C104B2B146DC3F9C39DC0B9698544 F1F692238FBC1666E5A5CCD4199F9DFEF6FFBAFD" ;;
        8.2) echo "1198C0117593497A5EC5C199286AF1F9897469DC 39B641343D8C104B2B146DC3F9C39DC0B9698544 E60913E4DF209907D8E30D96659A97C9CF2A795A" ;;
        8.3) echo "1198C0117593497A5EC5C199286AF1F9897469DC AFD8691FDAEDF03BDF6E460563F15A9B715376CA C28D937575603EB4ABB725861C0779DC5C0A9DE4" ;;
        8.4) echo "AFD8691FDAEDF03BDF6E460563F15A9B715376CA 9D7F99A0CB8F05C8A6958D6256A97AF7600A39A6 0616E93D95AF471243E26761770426E17EBBB3DD" ;;
        8.5) echo "1198C0117593497A5EC5C199286AF1F9897469DC 49D9AF6BC72A80D6691719C8AA23F5BE9C7097D4 D95C03BC702BE9515344AE3374E44BC9067701A5" ;;
        8.6) echo "D95C03BC702BE9515344AE3374E44BC9067701A5 016895DE9A475111D537A6E69134FF30BC5A99B5 5CFF17B64DC1C244F5D0EAC3E43535E2EB19010E" ;;
        *) return 1 ;;
    esac
}

# verify_sig <archivo> <firma .asc> <huellas>: 0 si la firma es buena y de una de esas huellas
# (la de su clave principal). Con gpgv y solo las claves de GPG_KEYS_B64, en una carpeta temporal: ni
# tus claves (~/.gnupg) ni un servidor de claves. Una clave caducada vale para lo que firmo antes
function verify_sig() {
    local file=$1 sig=$2 fprs=" ${3//$'\n'/ } " home out f
    [ -s "$sig" ] || return 1
    home=$(mktemp -d "${TMPDIR:-/tmp}/lvm-gpg.XXXXXX") || return 1
    base64 -d <<< "$GPG_KEYS_B64" 2> /dev/null | xz -dc > "$home/claves.gpg" 2> /dev/null
    out=$(gpgv --homedir "$home" --keyring "$home/claves.gpg" --status-fd 1 "$sig" "$file" 2> /dev/null)
    rm -rf "$home"
    grep -q '^\[GNUPG:\] BADSIG' <<< "$out" && return 1
    for f in $(awk '$2 == "VALIDSIG" { print $NF }' <<< "$out"); do
        [[ "$fprs" == *" $f "* ]] && return 0
    done
    return 1
}

# download_signed <url> <archivo> <sha256> <huellas> [url de la firma, por defecto <url>.asc]: como
# download y, ademas, su firma. Si no esta o no es de quien lo publica, no se usa
function download_signed() {
    local url=$1 file=$2 sum=$3 fprs=$4 sig_url=${5:-$1.asc}
    download "$url" "$file" "$sum" || return 1
    if ! curl -q --proto =https --proto-redir =https -fsSL --retry 2 -o "$file.asc" "$sig_url" 2> /dev/null \
            || ! verify_sig "$file" "$file.asc" "$fprs"; then
        echo "  La firma de $(basename "$url") no es buena o no es de quien lo publica. Se cancela."
        return 1
    fi
    echo "  Firma de $(basename "$url"): buena"
}

# download <url> <archivo> <sha256>: descarga un archivo y comprueba su suma
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
    local url=$1 file=$2 sum=$3

    # (STEP_DESC: el motivo, para el informe del error si falla aqui, antes de compilar nada)
    if [ -z "$sum" ]; then
        echo "  No se ha encontrado la suma sha256 de $(basename "$url")"
        STEP_DESC="no se ha podido leer la suma sha256 de $(basename "$url") (su web no responde: prueba en un rato)"

        return 1
    fi

    echo "  Descargando $(basename "$url")..."
    curl -q --proto =https --proto-redir =https -fsSL --retry 2 -o "$file" "$url" || {
        echo "  No se pudo descargar $url"
        STEP_DESC="no se ha podido descargar $url (su web no responde: prueba en un rato)"
        return 1
    }

    if [ "$(sha256sum "$file" | cut -d' ' -f1)" != "$sum" ]; then
        echo "  $(basename "$url") no coincide con su suma sha256. Se cancela."
        STEP_DESC="$(basename "$url") no coincide con su suma sha256: no se instala"

        return 1
    fi
}

# download_apache <ruta> <archivo>: dlcdn solo tiene la ultima version; si no esta, archive.apache.org
function download_apache() {
    local base sum

    for base in https://dlcdn.apache.org https://archive.apache.org/dist; do
        sum=$(curl -q --proto =https --proto-redir =https -fsSL "$base/$1.sha256" 2> /dev/null | grep -oE '^[0-9a-f]{64}')
        # (y su firma: la sha256 viene del mismo sitio que el fichero)
        [ -n "$sum" ] && download_signed "$base/$1" "$2" "$sum" "$GPG_FPR_APACHE" && return 0
    done

    return 1
}

# step <componente> <desde> <hasta> <lineas> <descripcion> <log> <comando...>
# Un paso de la compilacion, con su salida en un log. <desde>-<hasta> es el tramo de la barra de
# progreso (en % de la version) y <lineas> las que suele tener el log al terminar.
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
        echo "Sistema: $( . /etc/os-release 2> /dev/null; echo "${PRETTY_NAME:-Linux}") ($(uname -sr), $(uname -m))"
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
    printf '  [%3d%%] %s...\n' "$(bar_pct "$from" "$part")" "$desc"
    # Sin terminal (en su propia sesion): lo que se compila esta en una carpeta tuya y lo puede cambiar
    # cualquier programa tuyo; con la terminal de la tarea podria usar el permiso de sudo que ya se ha
    # dado (sudo -n). Sin ella, sudo le pediria la contraseña y falla
    if ! /usr/bin/python3 -I -c "$NO_TTY_PY" "$@" > "$log" 2>&1 < /dev/null; then
        echo "  ERROR: $desc. Ultimas lineas de $(basename "$log"):"
        tail -25 "$log" | sed 's/^/    /'
        # Compilando en paralelo, el error real queda lejos del final (tapado por avisos de otros
        # procesos): se repiten al final los primeros errores
        local errors=$(grep -E -m 5 '(error:|Error:|CMake Error)' "$log" | cut -c1-200)
        [ -n "$errors" ] && echo "  Primeros errores:" && sed 's/^/    /' <<< "$errors"
        STEP_LOG=$log STEP_DESC=$desc

        return 1
    fi
}

# Crea en <carpeta>/var/mysql unas bases de datos nuevas y vacias: solo las del sistema de
# MariaDB, root sin contraseña (como XAMPP) y la base 'phpmyadmin' con el usuario 'pma'.
function init_stack_databases() {
    local target=$1
    local data=$target/var/mysql my=$target/mysql cnf=$target/etc/my.cnf
    local user=mysql
    [ -n "$TEST_DIR" ] && user=$(id -un)

    if [ -e "$data" ]; then
        echo "Ya existe $data, no se crean bases de datos nuevas"

        return 1
    fi

    echo "  Creando bases de datos propias y vacias..."
    $SUDO "$my/scripts/mariadb-install-db" --defaults-file="$cnf" --basedir="$my" --datadir="$data" --user="$user" \
        --auth-root-authentication-method=normal --skip-test-db > "$LOG_DIR/install-db.log" 2>&1 \
        || { tail -20 "$LOG_DIR/install-db.log"; return 1; }

    # Apache y PHP-FPM tienen que poder llegar a mysql.sock, que esta en esta carpeta
    # (cada base de datos sigue protegida en su subcarpeta). Igual que en XAMPP.
    $SUDO chown "$user:" "$data"
    $SUDO chmod 775 "$data"

    # MariaDB temporal sin red y con su propio socket: no choca con la version en marcha. La
    # carpeta la crea root y solo es de mysql (el servidor no pide contraseña mientras se prepara)
    local tmp=$($SUDO mktemp -d /tmp/lvm-mysql-XXXX)
    local sock=$tmp/mysql.sock pid=$tmp/mysql.pid
    $SUDO chown "$user:" "$tmp"
    $SUDO chmod 700 "$tmp"
    $SUDO "$my/bin/mariadbd" --defaults-file="$cnf" --skip-networking --socket="$sock" --pid-file="$pid" \
        --log-error="$tmp/mysql.log" > /dev/null 2>&1 &

    local i
    for i in $(seq 150); do $SUDO test -S "$sock" && break; sleep 0.2; done

    local mysql=($SUDO "$my/bin/mariadb" --no-defaults -S "$sock" -uroot)
    local ok=0
    if $SUDO test -S "$sock" \
        && "${mysql[@]}" < "$target/phpmyadmin/sql/create_tables.sql" \
        && "${mysql[@]}" -e "CREATE USER IF NOT EXISTS 'pma'@'localhost';
            GRANT SELECT, INSERT, UPDATE, DELETE ON phpmyadmin.* TO 'pma'@'localhost';
            FLUSH PRIVILEGES;"; then
        ok=1
    fi

    # (el .pid lo escribe mysql: solo el numero de ese MariaDB, con su socket)
    local spid
    spid=$(db_temp_pid "$pid" "$sock") && $SUDO kill "$spid"
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
    local test_mode=0 mysql_user=mysql
    [ -n "$TEST_DIR" ] && test_mode=1 && mysql_user=$(id -un)

    mkdir -p "$S"/{bin,etc/extra,etc/ssl.crt,etc/ssl.key,logs,tmp,cgi-bin,var/run,var/proftpd,php/etc/conf.d}
    # Apache tambien en ::1 si el equipo la tiene (localhost puede ser ::1)
    local listen6_http="" listen6_https=""
    if has_ipv6_loopback; then
        listen6_http="Listen [::1]:$PORT_HTTP"$'\n'
        listen6_https="Listen [::1]:$PORT_HTTPS"$'\n'
    fi

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
# Apache $apache de lampp-$lampp_name (lvm-instalador)
ServerRoot "$target"
# Solo desde este equipo
Listen 127.0.0.1:$PORT_HTTP
${listen6_http}
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

DocumentRoot "$link/htdocs"
<Directory "$link/htdocs">
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
# Scripts CGI solo en cgi-bin (Perl de esta version: #!$link/bin/perl): en los proyectos, un .cgi
# o .pl no se ejecuta

<IfModule http2_module>
    Protocols h2 h2c http/1.1
</IfModule>

# Antes de los vhosts: los dominios que no tienen ninguno solo pasan si son localhost
Include $UNKNOWN_HOST_CONF
Include etc/extra/httpd-vhosts.conf
Include etc/extra/httpd-ssl.conf
Include etc/extra/httpd-lampp.conf
EOF
    local HOST_VHOST
    host_vhost
    printf '%s' "$HOST_VHOST" > "$S/$UNKNOWN_HOST_CONF"

    cat > "$S/etc/extra/httpd-ssl.conf" <<EOF
# HTTPS con un certificado autofirmado para localhost (los vhosts usan los suyos)
Listen 127.0.0.1:$PORT_HTTPS
${listen6_https}SSLCipherSuite HIGH:MEDIUM:!aNULL:!MD5
SSLProtocol all -SSLv3
SSLPassPhraseDialog builtin
SSLSessionCache "shmcb:$target/logs/ssl_scache(512000)"
SSLSessionCacheTimeout 300

<VirtualHost _default_:$PORT_HTTPS>
    DocumentRoot "$link/htdocs"
    ServerName localhost:$PORT_HTTPS
    ErrorLog "$target/logs/error_log"
    TransferLog "$target/logs/access_log"
    SSLEngine on
    SSLCertificateFile "$target/etc/ssl.crt/server.crt"
    SSLCertificateKeyFile "$target/etc/ssl.key/server.key"
</VirtualHost>
EOF

    cat > "$S/etc/extra/httpd-lampp.conf" <<EOF
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

    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/CN=localhost" \
        -addext "basicConstraints=critical,CA:FALSE" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
        -keyout "$S/etc/ssl.key/server.key" -out "$S/etc/ssl.crt/server.crt" > /dev/null 2>&1

    # --- PHP ---
    cat > "$S/php/etc/conf.d/99-lampp.ini" <<EOF
; Mismos valores que el php.ini de XAMPP (las subidas, 64 MB como 99-lvm-seguridad.ini). Sin
; error_log: los errores van al log de Apache
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
opcache.enable = 1
opcache.revalidate_freq = 0
EOF

    # El OpenSSL 1.1 propio no conoce los certificados del sistema
    if needs_openssl11 "$short" && [ -f /etc/ssl/certs/ca-certificates.crt ]; then
        printf 'openssl.cafile = /etc/ssl/certs/ca-certificates.crt\nopenssl.capath = /etc/ssl/certs\n' >> "$S/php/etc/conf.d/99-lampp.ini"
    fi

    # Mitigaciones de PHP2Shell (el mismo fichero que pone SECURE_PY en las versiones de antes)
    php_secure_ini_file "$version" > "$S/php/etc/conf.d/99-lvm-seguridad.ini"

    # A partir de PHP 8.5 opcache va integrado y no se carga como extension
    if ls "$S"/php/lib/php/extensions/*/opcache.so > /dev/null 2>&1; then
        echo "zend_extension = opcache" > "$S/php/etc/conf.d/10-opcache.ini"
    fi

    cat > "$S/php/etc/php-fpm.conf" <<EOF
[global]
pid = $target/var/run/php-fpm.pid
error_log = $target/logs/php-fpm.log
daemonize = yes

[lampp]
user = $web_user
group = $web_group
listen = $target/var/run/php-fpm.sock
listen.owner = $web_user
listen.group = $web_group
listen.mode = 0660
pm = ondemand
pm.max_children = 20
pm.max_requests = 50
pm.process_idle_timeout = 60s
request_terminate_timeout = 300
catch_workers_output = yes
EOF

    # --- MariaDB ---
    mkdir -p "$S/etc/lvm-sin-ficheros"
    cat > "$S/etc/my.cnf" <<EOF
# MariaDB $mariadb de lampp-$lampp_name (lvm-instalador)
[client]
port = $PORT_MYSQL
socket = $target/var/mysql/mysql.sock
default-character-set = utf8mb4

[mysqld]
user = $mysql_user
port = $PORT_MYSQL
# Solo desde este equipo
bind-address = 127.0.0.1
# Sin leer ni escribir ficheros del equipo desde SQL (la carpeta esta vacia y es de root)
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

    # --- ProFTPD: acceso a htdocs con el usuario del equipo y su contraseña ---
    cat > "$S/etc/proftpd.conf" <<EOF
# ProFTPD $ftp de lampp-$lampp_name (lvm-instalador)
ServerName "ProFTPD lampp-$lampp_name"
ServerType standalone
DefaultServer on
Port $PORT_FTP
# Solo desde este equipo
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

DefaultRoot $link/htdocs
<Limit LOGIN>
    AllowUser $web_user
    DenyAll
</Limit>
<Directory $link/htdocs/*>
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

    # --- Script de arranque y parada (lo usa "lvm-instalador use") ---
    sed -e "s|@ROOT@|$target|g" -e "s|@NAME@|$lampp_name|g" -e "s|@NEED_ROOT@|$(( 1 - test_mode ))|g" > "$S/lampp" <<'EOF'
#!/bin/bash
# Arranque y parada de lampp-@NAME@ (pila propia creada por lvm-instalador):
# Apache con PHP-FPM, MariaDB y ProFTPD.
# Uso: lampp start|stop|restart|status|startapache|stopapache|reloadapache|startmysql|stopmysql|startftp|stopftp

ROOT=@ROOT@
APACHE_PID=$ROOT/logs/httpd.pid
MYSQL_PID=$ROOT/var/mysql/mysqld.pid
MYSQL_SOCK=$ROOT/var/mysql/mysql.sock
FTP_PID=$ROOT/var/proftpd/proftpd.pid

if [ @NEED_ROOT@ -eq 1 ] && [ "$(id -u)" -ne 0 ]; then
    echo "Hay que ejecutarlo como administrador: sudo $0 $*"
    exit 1
fi

# Numero de proceso de un .pid: solo un numero de verdad (ni 0, ni 1, ni negativo). Este script
# corre como root y el .pid de MariaDB lo escribe mysql
function pid_in() {
    local p
    p=$(head -c 20 "$1" 2> /dev/null | tr -d " \n")
    [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -gt 1 ] && echo "$p"
}

function running() {
    local p
    p=$(pid_in "$1") && kill -0 "$p" 2> /dev/null
}

#@incluir comun/pila-propia-version-php/wait_until.sh
function start_apache() {
    running "$APACHE_PID" && { echo "Apache ya estaba arrancado."; return 0; }

    "$ROOT/bin/lvm-php-fpm" start
    # Como XAMPP: los avisos del arranque (vhosts sin carpeta, certificados...) van al log
    if "$ROOT/apache2/bin/httpd" -f "$ROOT/etc/httpd.conf" -E "$ROOT/logs/error_log" -k start >> "$ROOT/logs/error_log" 2>&1 \
        && wait_until 10 running "$APACHE_PID"; then
        echo "Apache arrancado."
    else
        echo "Apache no ha arrancado. Revisa $ROOT/logs/error_log"
        return 1
    fi
}

function stop_apache() {
    if running "$APACHE_PID"; then
        "$ROOT/apache2/bin/httpd" -f "$ROOT/etc/httpd.conf" -k stop
        wait_until 15 stopped "$APACHE_PID"
        echo "Apache parado."
    fi
    "$ROOT/bin/lvm-php-fpm" stop
}

function reload_apache() {
    "$ROOT/bin/lvm-php-fpm" reload
    running "$APACHE_PID" && "$ROOT/apache2/bin/httpd" -f "$ROOT/etc/httpd.conf" -E "$ROOT/logs/error_log" -k graceful >> "$ROOT/logs/error_log" 2>&1 \
        && echo "Apache recargado."
}

function start_mysql() {
    running "$MYSQL_PID" && { echo "MariaDB ya estaba arrancado."; return 0; }

    # mariadbd-safe busca sus herramientas desde la carpeta de MariaDB
    (cd "$ROOT/mysql" && nohup ./bin/mariadbd-safe --defaults-file="$ROOT/etc/my.cnf" > /dev/null 2>&1 &)
    if wait_until 60 mysql_ready; then
        echo "MariaDB arrancado."
    else
        echo "MariaDB no ha arrancado. Revisa $ROOT/var/mysql/mysqld.err"
        return 1
    fi
}

function stop_mysql() {
    running "$MYSQL_PID" || return 0

    local p
    # (y solo si es el MariaDB: su .pid lo podria cambiar mysql)
    p=$(pid_in "$MYSQL_PID") && [[ "$(cat "/proc/$p/comm" 2> /dev/null)" =~ ^(mariadbd|mysqld)$ ]] && kill "$p"
    wait_until 60 stopped "$MYSQL_PID" && echo "MariaDB parado." || echo "MariaDB sigue parandose."
}

function start_ftp() {
    running "$FTP_PID" && { echo "ProFTPD ya estaba arrancado."; return 0; }

    if "$ROOT/proftpd/sbin/proftpd" -c "$ROOT/etc/proftpd.conf" 2> /dev/null && wait_until 5 running "$FTP_PID"; then
        echo "ProFTPD arrancado."
    else
        echo "ProFTPD no ha arrancado. Revisa $ROOT/logs/proftpd.log"
        return 1
    fi
}

function stop_ftp() {
    running "$FTP_PID" || return 0

    local p
    p=$(pid_in "$FTP_PID") && kill "$p"
    wait_until 10 stopped "$FTP_PID"
    echo "ProFTPD parado."
}

function status() {
    local name pid

    echo "lampp-@NAME@ (pila propia)"
    for name in Apache MariaDB ProFTPD; do
        case $name in
            Apache) pid=$APACHE_PID ;;
            MariaDB) pid=$MYSQL_PID ;;
            ProFTPD) pid=$FTP_PID ;;
        esac
        running "$pid" && echo "$name esta arrancado." || echo "$name no esta arrancado."
    done
    "$ROOT/bin/lvm-php-fpm" status
}

case "$1" in
    # El FTP solo si se ha activado (lampp startftp; lo quita lampp stopftp)
    start) echo "Arrancando lampp-@NAME@..."; start_mysql; start_apache; if [ -f "$ROOT/etc/lvm-startftp" ]; then start_ftp; fi ;;
    stop) echo "Parando lampp-@NAME@..."; stop_apache; stop_mysql; stop_ftp ;;
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
    chmod 755 "$S/lampp"

    # PHP-FPM se arranca con el entorno limpio
    sed -e "s|@ROOT@|$target|g" -e "s|@VERSION@|$version|g" > "$S/bin/lvm-php-fpm" <<'EOF'
#!/bin/bash
# PHP-FPM @VERSION@ (lo arrancan y paran startapache/stopapache del script lampp)
FPM=@ROOT@/php/sbin/php-fpm
CONF=@ROOT@/php/etc/php-fpm.conf
PID=@ROOT@/var/run/php-fpm.pid

running() { [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2> /dev/null; }

case "$1" in
    start)
        running || env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin "$FPM" --fpm-config "$CONF"
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
    chmod 755 "$S/bin/lvm-php-fpm"

    # --- Comandos en bin/, como en XAMPP: /opt/lampp/bin/php, /opt/lampp/bin/mysql... ---
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

    # htdocs y vhosts compartidos con las demas versiones
    if [ $test_mode -eq 1 ]; then
        mkdir -p "$S/htdocs"
        echo '<?php phpinfo();' > "$S/htdocs/index.php"
        : > "$S/etc/extra/httpd-vhosts.conf"
    else
        ln -s /opt/htdocs "$S/htdocs"
        ln -s /opt/config/httpd-vhosts.conf "$S/etc/extra/httpd-vhosts.conf"
    fi

    echo "$version" > "$S/etc/lvm-php"
    # (compilada con el arreglo de PHP2Shell: install_stack deja su commit en php2shell)
    [ -n "$php2shell" ] && echo "CVE-2026-109618 CVE-2026-109619: php-src ${php2shell%%|*}" > "$S/$PHP2SHELL_MARK"
    echo "$version|$apache|$mariadb|$ftp|$perl|$pma" > "$S/etc/lvm-stack"
    # Ya se instala solo para este equipo (secure_lampp no tiene nada que cambiar)
    echo "1" > "$S/$SECURE_MARK"
}

# PHP convierte cada -L de OPENSSL_LIBS/ICU_LIBS en una ruta de busqueda grabada en el binario
# (RUNPATH), y descarta cualquier -Wl,-rpath. Con OpenSSL e ICU propios esas rutas son de la carpeta
# temporal: se cambian por la definitiva de OpenSSL o se quitan (ICU es estatico).
# Usa las variables locales de install_stack.
function fix_php_runpath() {
    local elf

    [ ${#php_env[@]} -eq 0 ] && return 0

    for elf in "$S"/php/sbin/php-fpm "$S"/php/bin/php "$S"/php/bin/phpdbg; do
        [ -f "$elf" ] || continue
        if needs_openssl11 "$short"; then
            patchelf --set-rpath "$target/openssl/lib" "$elf" || return 1
        else
            patchelf --remove-rpath "$elf" || return 1
        fi
    done
}

# Ningun binario puede buscar librerias en la carpeta temporal de la compilacion: al borrarse,
# cualquier usuario podria crearla en /tmp con librerias falsas que se cargarian al arrancar.
# Enlaces de lo compilado que llevan fuera de la version (salvo htdocs y los vhosts compartidos):
# lo compilado es de tu usuario hasta que root lo copia, y un programa tuyo podria dejar un enlace
# a /etc para que root lo cambiara despues. Uso: <carpeta temporal> <carpeta definitiva>
BUILD_LINKS_PY='
import os, posixpath, sys
root, target = sys.argv[1], sys.argv[2]
ok = {"htdocs": "/opt/htdocs", "etc/extra/httpd-vhosts.conf": "/opt/config/httpd-vhosts.conf"}
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
    bad=$(/usr/bin/python3 -I -c "$BUILD_LINKS_PY" "$S" "$target") || bad="(no se han podido mirar)"
    bad=$(cut -c1-300 <<< "$bad")
    if [ -n "$bad" ]; then
        echo "  Lo compilado tiene enlaces que llevan fuera de $target (no se copia nada):"
        echo "$bad" | head -10 | sed 's/^/    /'

        return 1
    fi
}

function check_no_build_paths() {
    local bad=$(find "$S" -type f \( -perm -u+x -o -name '*.so*' \) -print0 2> /dev/null \
        | xargs -0 -r sh -c 'for f; do readelf -d "$f" 2> /dev/null | grep -qE "R(UN)?PATH.*'"$build"'" && echo "$f"; done' sh)

    if [ -n "$bad" ]; then
        echo "  Estos binarios buscan librerias en la carpeta temporal $build:"
        echo "$bad" | sed "s|^$S/|    |"

        return 1
    fi
}

# Usuario del sistema que compila las pilas propias (sin contraseña, sin sesion y sin carpeta propia)
BUILD_USER=nexum-build
function build_user_ready() {
    id "$BUILD_USER" > /dev/null 2>&1 && return 0
    echo "Creando el usuario $BUILD_USER (sin contraseña ni sesion: solo compila las pilas propias)..."
    sudo useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$BUILD_USER"
}

# Borra la carpeta de la compilacion (la de root con la de BUILD_USER dentro, o la tuya en las pruebas)
function stack_rm_build() {
    if [ -n "$build_top" ]; then
        [[ "$build_top" == /tmp/lvm-pila-* ]] && sudo rm -rf "$build_top"
    else
        rm -rf "$build"
    fi
}

# Compilacion de install_stack con BUILD_USER: este mismo script (copiado por root a su carpeta) con
# construir-pila y las variables de install_stack en un fichero de root. Su progreso se pasa al de
# la ventana. Usa las variables de install_stack
function stack_build_child() {
    local vars=$build_top/variables prog="" tailpid="" rc
    [ -n "$PROGRESS" ] && prog=$build/progreso
    { declare -p version short lampp_name target link apache apr aprutil mariadb_info mariadb ftp perl pma \
          php_sha web_user web_group build stage S jobs MARIADB_SRC mariadb_jobs stack_line PHP_TIMEZONE
      printf 'PROGRESS=%q\n' "$prog"; } | sudo sh -c 'umask 022; cat > "$1"' sh "$vars" || return 1
    sudo install -m 644 -o 0 -g 0 "$SELF" "$build_top/lvm-instalador.sh" || return 1
    if [ -n "$prog" ]; then
        tail -n +1 -F "$prog" 2> /dev/null >> "$PROGRESS" &
        tailpid=$!
    fi
    echo "Compilando con el usuario $BUILD_USER en $build"
    sudo -u "$BUILD_USER" env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME="$build" TMPDIR="$build" LANG=C.UTF-8 \
        /bin/bash "$build_top/lvm-instalador.sh" construir-pila "$vars" < /dev/null
    rc=$?
    if [ -n "$tailpid" ]; then
        sleep 1
        kill "$tailpid" 2> /dev/null
        wait "$tailpid" 2> /dev/null
    fi
    return $rc
}

# stack_fail de la compilacion con BUILD_USER: deja el paso que fallo (y su config.log) para
# install_stack, que guarda los logs con el informe y borra la carpeta
function stack_child_fail() {
    printf '%s\n%s\n' "$STEP_LOG" "$STEP_DESC" > "$build/fallo"
    [ -f config.log ] && cp config.log "$build/fallo-$(basename "$PWD")-config.log"
    exit 1
}

# Descargas, compilacion y configuracion de una pila propia en $build (install_stack). Usa sus variables
function stack_build_phase() {
    local php_part="PHP $version"
    php2shell_backport "$version" > /dev/null && php_part+=" + parche de seguridad"
    needs_openssl11 "$short" && php_part+=" + OpenSSL $OPENSSL11_VERSION"
    needs_icu72 "$short" && php_part+=" + ICU 72.1"
    progress_parts "Descargas" "Apache $apache" "$php_part" "Perl $perl" "ProFTPD $ftp" "MariaDB $mariadb" \
        "phpMyAdmin $pma y configuracion"

    echo "Descargando el codigo fuente (con comprobacion sha256)..."
    progress 1 0 2 "codigo fuente"
    download_apache "httpd/httpd-$apache.tar.bz2" httpd.tar.bz2 || stack_fail
    download_apache "apr/apr-$apr.tar.bz2" apr.tar.bz2 || stack_fail
    download_apache "apr/apr-util-$aprutil.tar.bz2" apr-util.tar.bz2 || stack_fail
    local php_fprs
    php_fprs=$(php_gpg_fprs "$short") || { echo "  No se conocen las claves de quienes publican PHP $short: actualiza lvm-instalador"; stack_fail; }
    download_signed "https://www.php.net/distributions/php-$version.tar.xz" php.tar.xz "$php_sha" "$php_fprs" || stack_fail
    if needs_openssl11 "$short"; then
        download "https://www.openssl.org/source/openssl-$OPENSSL11_VERSION.tar.gz" openssl11.tar.gz "$OPENSSL11_SHA" || stack_fail
    fi
    if needs_icu72 "$short"; then
        download "https://github.com/unicode-org/icu/releases/download/release-72-1/icu4c-72_1-src.tgz" icu72.tgz "$ICU72_SHA" || stack_fail
    fi
    download "https://www.cpan.org/src/5.0/perl-$perl.tar.xz" perl.tar.xz \
        "$(curl -q --proto =https --proto-redir =https -fsSL --retry 2 --max-time 60 "https://www.cpan.org/src/5.0/perl-$perl.tar.xz.sha256.txt" | grep -oE '^[0-9a-f]{64}')" || stack_fail
    download "https://github.com/proftpd/proftpd/archive/refs/tags/v$ftp.tar.gz" proftpd.tar.gz \
        "$(proftpd_sum "$ftp")" || stack_fail
    download_signed "https://files.phpmyadmin.net/phpMyAdmin/$pma/phpMyAdmin-$pma-all-languages.tar.xz" pma.tar.xz \
        "$(pma_sum "$pma")" "$GPG_FPR_PMA" || stack_fail
    local mariadb_sig
    IFS='|' read -r _ mariadb_url mariadb_sha mariadb_sig <<< "$mariadb_info"
    if [ $MARIADB_SRC -eq 1 ]; then
        progress 1 2 10 "MariaDB (codigo fuente)" bytes "$build/mariadb.tar.gz" "$(remote_size "$mariadb_url")"
    else
        echo "  MariaDB $mariadb ocupa unos 450 MB, puede tardar."
        progress 1 2 10 "MariaDB (450 MB)" bytes "$build/mariadb.tar.gz" "$(remote_size "$mariadb_url")"
    fi
    download "$mariadb_url" mariadb.tar.gz "$mariadb_sha" || stack_fail
    # (la firma de MariaDB viene con la sha256 en su API: se comprueba con su clave)
    if ! base64 -d <<< "$mariadb_sig" > mariadb.tar.gz.asc 2> /dev/null \
            || ! verify_sig mariadb.tar.gz mariadb.tar.gz.asc "$GPG_FPR_MARIADB"; then
        echo "  La firma de MariaDB $mariadb no es buena o no es de MariaDB. Se cancela."
        stack_fail
    fi
    echo "  Firma de MariaDB $mariadb: buena"

    echo "Apache $apache (con APR $apr y APR-util $aprutil)"
    tar -xjf httpd.tar.bz2 && tar -xjf apr.tar.bz2 && tar -xjf apr-util.tar.bz2 || stack_fail
    mv "apr-$apr" "httpd-$apache/srclib/apr" && mv "apr-util-$aprutil" "httpd-$apache/srclib/apr-util" || stack_fail
    cd "httpd-$apache" || stack_fail
    local pcre=$(command -v pcre2-config)
    step 2 10 15 1063 "Configurando" "$build/apache-configure.log" ./configure --prefix="$target/apache2" \
        --with-included-apr ${pcre:+--with-pcre="$pcre"} --enable-mods-shared=most \
        --enable-ssl --enable-proxy --enable-proxy-fcgi --enable-mpms-shared="event prefork" || stack_fail
    step 2 15 24 712 "Compilando" "$build/apache-make.log" make -j"$jobs" || stack_fail
    step 2 24 27 583 "Instalando" "$build/apache-install.log" make install DESTDIR="$stage" || stack_fail
    cd "$build" || stack_fail

    echo "PHP $version"
    # Las ramas antiguas llevan sus propios OpenSSL 1.1 e ICU 72 (cada uno ocupa 5 puntos de la barra)
    local php_env=() p=27
    if needs_openssl11 "$short"; then
        echo "  OpenSSL $OPENSSL11_VERSION (solo para esta version de PHP, en $target/openssl)"
        tar -xzf openssl11.tar.gz && cd "openssl-$OPENSSL11_VERSION" || stack_fail
        step 3 $p $((p + 1)) 30 "OpenSSL $OPENSSL11_VERSION: configurando" "$build/openssl11-configure.log" \
            ./config shared no-tests --prefix="$target/openssl" --openssldir="$target/openssl/ssl" \
            -Wl,-rpath,"$target/openssl/lib" || stack_fail
        step 3 $((p + 1)) $((p + 4)) 1700 "OpenSSL $OPENSSL11_VERSION: compilando" "$build/openssl11-make.log" make -j"$jobs" || stack_fail
        step 3 $((p + 4)) $((p + 5)) 300 "OpenSSL $OPENSSL11_VERSION: instalando" "$build/openssl11-install.log" \
            make install_sw DESTDIR="$stage" || stack_fail
        cd "$build" || stack_fail
        # PHP se enlaza con la copia de la carpeta temporal; al terminar, fix_php_runpath hace que
        # busque las librerias en $target/openssl/lib
        php_env+=(OPENSSL_CFLAGS="-I$S/openssl/include" OPENSSL_LIBS="-L$S/openssl/lib -lssl -lcrypto"
            LD_LIBRARY_PATH="$S/openssl/lib")
        p=$((p + 5))
    fi
    if needs_icu72 "$short"; then
        echo "  ICU 72.1 (estatico, queda dentro de PHP)"
        local deps=$build/deps
        tar -xzf icu72.tgz && cd icu/source || stack_fail
        step 3 $p $((p + 1)) 250 "ICU 72.1: configurando" "$build/icu72-configure.log" \
            env CFLAGS="-O2 -fPIC" CXXFLAGS="-O2 -fPIC" ./runConfigureICU Linux --prefix="$deps" \
            --enable-static --disable-shared --with-data-packaging=static \
            --disable-tests --disable-samples --disable-extras || stack_fail
        step 3 $((p + 1)) $((p + 4)) 900 "ICU 72.1: compilando" "$build/icu72-make.log" make -j"$jobs" || stack_fail
        step 3 $((p + 4)) $((p + 5)) 200 "ICU 72.1: instalando" "$build/icu72-install.log" make install || stack_fail
        cd "$build" || stack_fail
        # Los compiladores actuales tratan como errores avisos del codigo de las ramas antiguas
        php_env+=(ICU_CFLAGS="-I$deps/include"
            ICU_LIBS="-L$deps/lib -licui18n -licuio -licuuc -licudata -lstdc++ -lm -ldl -lpthread"
            CFLAGS="-O2 -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types -Wno-error=int-conversion"
            CXXFLAGS="-O2")
        # PHP 7.4 usa TRUE/FALSE, que ICU dejo de definir en la version 68
        [ "$short" == "7.4" ] && php_env+=(CPPFLAGS="-DU_DEFINE_FALSE_AND_TRUE=1")
        p=$((p + 5))
    fi

    tar -xJf php.tar.xz && cd "php-$version" || stack_fail
    # 7.4.33, 8.0.30 y 8.1.34: con el arreglo de PHP2Shell de php-src (PHP2SHELL_BACKPORTS)
    local php2shell=""
    if php2shell=$(php2shell_backport "$version"); then
        echo "  Parche de seguridad de PHP2Shell (CVE-2026-109618 y CVE-2026-109619, php-src ${php2shell:0:12})"
        php2shell_apply "$version" "$PWD" "$build/php2shell.log" || stack_fail
    fi
    step 3 $p $((p + 5)) 701 "Configurando" "$build/php-configure.log" env "${php_env[@]}" ./configure --prefix="$target/php" \
        --with-config-file-path="$target/php/etc" \
        --with-config-file-scan-dir="$target/php/etc/conf.d" \
        --enable-fpm --with-fpm-user="$web_user" --with-fpm-group="$web_group" --disable-cgi \
        --with-openssl --with-zlib --with-curl --with-readline --with-gettext \
        --enable-mbstring --enable-intl --enable-bcmath --enable-calendar --enable-exif --enable-ftp \
        --enable-gd --with-jpeg --with-freetype --with-webp \
        --with-zip --enable-soap --enable-sockets --with-sodium --with-password-argon2 \
        --enable-mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
        --with-mysql-sock="$target/var/mysql/mysql.sock" \
        --with-sqlite3 --with-pdo-sqlite || stack_fail
    step 3 $((p + 5)) 72 913 "Compilando (tarda unos minutos)" "$build/php-make.log" env "${php_env[@]}" make -j"$jobs" || stack_fail
    step 3 72 74 17 "Instalando" "$build/php-install.log" env "${php_env[@]}" make install INSTALL_ROOT="$stage" || stack_fail
    fix_php_runpath || stack_fail
    mkdir -p "$S/php/etc" && cp php.ini-production "$S/php/etc/php.ini" || stack_fail
    cd "$build" || stack_fail

    echo "Perl $perl"
    tar -xJf perl.tar.xz && cd "perl-$perl" || stack_fail
    step 4 74 80 948 "Configurando" "$build/perl-configure.log" sh Configure -des -Dprefix="$target/perl" \
        -Dman1dir=none -Dman3dir=none || stack_fail
    step 4 80 86 1798 "Compilando" "$build/perl-make.log" make -j"$jobs" || stack_fail
    step 4 86 89 3319 "Instalando" "$build/perl-install.log" make install DESTDIR="$stage" || stack_fail
    cd "$build" || stack_fail

    echo "ProFTPD $ftp"
    tar -xzf proftpd.tar.gz && cd "proftpd-$ftp" || stack_fail
    step 5 89 91 575 "Configurando" "$build/proftpd-configure.log" env install_user="$(id -un)" install_group="$(id -gn)" \
        ./configure --prefix="$target/proftpd" --sysconfdir="$target/etc" \
        --localstatedir="$target/var/proftpd" --enable-shadow || stack_fail
    step 5 91 92 162 "Compilando" "$build/proftpd-make.log" make -j"$jobs" || stack_fail
    step 5 92 93 50 "Instalando" "$build/proftpd-install.log" make install DESTDIR="$stage" || stack_fail
    cd "$build" || stack_fail

    if [ $MARIADB_SRC -eq 1 ]; then
        echo "MariaDB $mariadb (se compila: no hay binario oficial para $(uname -m); es lo que mas tarda)"
        tar -xzf mariadb.tar.gz && rm -f mariadb.tar.gz && cd "mariadb-$mariadb" || stack_fail
        step 6 53 55 0 "Configurando" "$build/mariadb-configure.log" cmake -S . -B build \
            -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$target/mysql" \
            -DCMAKE_INSTALL_RPATH="$target/mysql/lib" -DWITH_SSL=system -DWITH_PCRE=system \
            -DWITH_UNIT_TESTS=OFF -DWITH_WSREP=OFF -DWITH_SYSTEMD=no -DWITH_EMBEDDED_SERVER=OFF \
            -DINSTALL_MYSQLTESTDIR= -DINSTALL_SQLBENCHDIR= \
            -DPLUGIN_TOKUDB=NO -DPLUGIN_MROONGA=NO -DPLUGIN_SPIDER=NO -DPLUGIN_OQGRAPH=NO -DPLUGIN_ROCKSDB=NO \
            -DPLUGIN_CONNECT=NO -DPLUGIN_COLUMNSTORE=NO -DPLUGIN_S3=NO -DPLUGIN_AUTH_GSSAPI=NO \
            -DDEFAULT_CHARSET=utf8mb4 -DDEFAULT_COLLATION=utf8mb4_general_ci -DCOMPILATION_COMMENT="lvm-instalador" \
            || stack_fail
        step 6 55 94 0 "Compilando ($mariadb_jobs procesos, tarda bastante)" "$build/mariadb-make.log" \
            cmake --build build --parallel "$mariadb_jobs" || stack_fail
        step 6 94 96 0 "Instalando" "$build/mariadb-install.log" env DESTDIR="$stage" cmake --install build || stack_fail
        cd "$build" && rm -rf "mariadb-$mariadb" || stack_fail
    else
        echo "MariaDB $mariadb"
        mkdir -p "$S/mysql"
        step 6 93 96 0 "Descomprimiendo" "$build/mariadb-extract.log" tar -xzf mariadb.tar.gz -C "$S/mysql" --strip-components=1 \
            --exclude='*/mariadb-test' --exclude='*/mysql-test' --exclude='*/sql-bench' || stack_fail
        rm -f mariadb.tar.gz
    fi
    # Sin simbolos de depuracion ocupa unos 600 MB menos
    find "$S/mysql/bin" "$S/mysql/lib" -type f \( -perm -u+x -o -name '*.so*' \) \
        -exec strip --strip-unneeded {} + > /dev/null 2>&1
    local libs=$(ldd "$S/mysql/bin/mariadbd" "$S/mysql/bin/mariadb" 2> /dev/null | grep 'not found' | sort -u)
    if [ -n "$libs" ]; then
        echo "  Faltan librerias del sistema para MariaDB:"
        echo "$libs" | sed 's/^\s*/    /'
        stack_fail
    fi

    echo "phpMyAdmin $pma"
    progress 7 96 97 "configurando"
    tar -xJf pma.tar.xz && mv "phpMyAdmin-$pma-all-languages" "$S/phpmyadmin" || stack_fail

    echo "Configuracion"
    write_stack_files || stack_fail
    check_no_build_paths || stack_fail
    check_build_links || stack_fail
}

# install_stack <version de PHP> [reemplazar] [carpeta: lampp-<carpeta>, por defecto la rama X.Y]
# Compila Apache, PHP, Perl y ProFTPD, y descarga MariaDB (binario oficial) y phpMyAdmin, todo
# dentro de /opt/lampp-X.Y. Se instala primero en una carpeta temporal (DESTDIR) y solo al final
# se copia a /opt, asi que si algo falla no queda nada a medias.
# Con reemplazar=1 sustituye la version que ya existe en /opt/lampp-X.Y. Si su MariaDB es de la
# misma rama, conserva sus bases de datos; si no, guarda una copia y empieza con unas vacias.
function install_stack() {
    local version=$1 replace=${2:-0}
    local FETCH_FRESH=1

    if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Indica la version completa de PHP, por ejemplo: 8.4.26"

        exit 1
    fi

    # La carpeta es la version completa (lampp-8.4.27); sin tercer argumento (actualizar una lampp-X.Y
    # de antes de la 1.51), la rama
    local short=${version%.*}
    local lampp_name=${3:-$short}
    local target=/opt/lampp-$lampp_name link=/opt/lampp
    [ -n "$TEST_DIR" ] && target=$TEST_DIR/lampp-$lampp_name && link=$target

    if [ "$replace" -eq 0 ] && [ -e "$target" ]; then
        echo "Ya existe $target"

        exit 1
    fi

    if [ "$replace" -eq 1 ] && [ ! -d "$target" ]; then
        echo "No existe $target, no hay nada que actualizar"

        exit 1
    fi

    if [ "$replace" -eq 1 ] && [ -e "$target/htdocs" ] && [ ! -L "$target/htdocs" ] && [ -z "$TEST_DIR" ]; then
        echo "$target tiene una carpeta htdocs propia (no es un enlace a /opt/htdocs) y podria contener proyectos."
        echo "Revisala y muevela a mano antes de actualizar la version."

        exit 1
    fi

    echo "Consultando las ultimas versiones de cada componente..."
    local branches
    if ! stack_branches "$short" > /dev/null; then
        echo "PHP $short no esta entre las ramas que instala este gestor"

        exit 1
    fi
    if ! printf '%s\n' "${STACK_MATRIX[@]}" | grep -q "^$short|"; then
        echo "Aviso: PHP $short es mas nueva que las ramas probadas. Se instala con los componentes de la ${STACK_MATRIX[${#STACK_MATRIX[@]}-1]%%|*}."
    fi
    read -r -a branches <<< "$(stack_branches "$short")"

    local apache=$(latest_apache "${branches[0]}")
    local apr=$(latest_apr apr) aprutil=$(latest_apr apr-util)
    local mariadb_info=$(mariadb_release "${branches[1]}")
    local mariadb=${mariadb_info%%|*}
    local ftp=$(latest_proftpd "${branches[2]}")
    local perl=$(latest_perl "${branches[3]}")
    local pma=$(latest_pma)
    local php_sha=$(curl -q --proto =https --proto-redir =https -fsSL "https://www.php.net/releases/index.php?json&version=$version" \
        | python3 -I -c 'import json,sys; print([s["sha256"] for s in json.load(sys.stdin)["source"] if s["filename"].endswith(".tar.xz")][0])' 2> /dev/null)

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
    if [ "$replace" -eq 1 ]; then
        old_mariadb=$(stack_fields "$target" | cut -d'|' -f3)
        [ -f "$target/etc/lvm-stack" ] && [ -d "$target/var/mysql" ] && [ ! -L "$target/var/mysql" ] \
            && [ "${old_mariadb%.*}" == "${mariadb%.*}" ] && keep_data=1
    fi

    echo ""
    local stack_line="lampp-$lampp_name: PHP $version, Apache $apache, MariaDB $mariadb, ProFTPD $ftp, Perl $perl, phpMyAdmin $pma"
    echo "$stack_line"
    echo "Carpeta: $target   Usuario de Apache, PHP y FTP: $web_user:$web_group"

    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] dependencias de compilacion: $STACK_BUILD_DEPS"
        echo "  [simulacion] descarga con comprobacion sha256 y compilacion de Apache, APR $apr/$aprutil, PHP, Perl y ProFTPD"
        needs_openssl11 "$short" && echo "  [simulacion] OpenSSL $OPENSSL11_VERSION propio para PHP $short en $target/openssl"
        needs_icu72 "$short" && echo "  [simulacion] ICU 72.1 estatico dentro de PHP $short"
        if native_binaries; then
            echo "  [simulacion] MariaDB $mariadb: binario oficial de mariadb.org"
        else
            echo "  [simulacion] MariaDB $mariadb: se compila (no hay binario oficial para $(uname -m)); dependencias: $MARIADB_BUILD_DEPS"
        fi
        if [ "$replace" -eq 1 ] && [ $keep_data -eq 1 ]; then
            echo "  [simulacion] se sustituiria $target conservando sus bases de datos (MariaDB ${mariadb%.*})"
        elif [ "$replace" -eq 1 ]; then
            echo "  [simulacion] copia de las bases de datos de $target en ~/lvm-copias y bases nuevas y vacias"
        else
            echo "  [simulacion] bases de datos propias y vacias en $target/var/mysql (root sin contraseña)"
        fi
        echo "  [simulacion] puertos: web $PORT_HTTP/$PORT_HTTPS, MariaDB $PORT_MYSQL, FTP $PORT_FTP"

        exit 0
    fi

    if [ -z "$TEST_DIR" ]; then
        echo "Instalando dependencias de compilacion (solo librerias, no PHP)..."
        local deps=$STACK_BUILD_DEPS
        native_binaries || deps+=" $MARIADB_BUILD_DEPS"
        apt_install $deps || exit 1

        # MariaDB se ejecuta con el usuario 'mysql', como en XAMPP
        if ! id mysql > /dev/null 2>&1; then
            sudo useradd --system --no-create-home --shell /usr/sbin/nologin mysql || exit 1
        fi
    fi

    STEP_LOG="" STEP_DESC=""
    # Se compila con el usuario BUILD_USER, en una carpeta que crea root: lo que root copia a /opt (y
    # despues arranca como root) no lo puede cambiar ningun programa tuyo entre que se compila y se
    # copia. Las descargas y sus comprobaciones (sha256 y firmas) tambien van con el. En las pruebas
    # (LVM_PRUEBA, sin sudo), con tu usuario como antes
    local build_top="" build
    if [ -z "$TEST_DIR" ]; then
        build_user_ready || exit 1
        build_top=$(sudo mktemp -d /tmp/lvm-pila-$lampp_name-XXXX) && sudo chmod 755 "$build_top" \
            && sudo install -d -o "$BUILD_USER" -g "$BUILD_USER" -m 755 "$build_top/w" || exit 1
        build=$build_top/w
    else
        build=$(mktemp -d /tmp/lvm-pila-$lampp_name-XXXX)
    fi
    local stage=$build/stage
    local S=$stage$target
    local jobs=$(nproc)
    local MARIADB_SRC=0
    native_binaries || MARIADB_SRC=1
    # Compilar MariaDB necesita 1,5 GB de memoria por proceso: en maquinas virtuales pequeñas se
    # usan menos procesos para que no se quede sin memoria
    local mem_mb=$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo 2> /dev/null)
    local mariadb_jobs=$(( ${mem_mb:-2048} / 1536 ))
    (( mariadb_jobs < 1 )) && mariadb_jobs=1
    (( mariadb_jobs > jobs )) && mariadb_jobs=$jobs

    # Si algo falla se guardan los logs y se borra la carpeta temporal
    function stack_fail() {
        local logs=$LOG_DIR/pila-$lampp_name-$(date +%Y%m%d-%H%M%S)
        mkdir -p "$logs"
        cp "$build"/*.log "$logs/" 2> /dev/null
        # El config.log del componente que fallaba (stack_fail se llama desde su carpeta): ahi esta
        # el motivo real de los errores de configure
        local config="" f
        if [ -f config.log ]; then
            config="$logs/$(basename "$PWD")-config.log"
            cp config.log "$config"
        fi
        # (si fallo compilando con BUILD_USER, el paso y el config.log los dejo en la carpeta)
        if [ -f "$build/fallo" ]; then
            { IFS= read -r STEP_LOG; IFS= read -r STEP_DESC; } < "$build/fallo"
            for f in "$build"/fallo-*-config.log; do
                [ -f "$f" ] && config="$logs/${f#"$build/fallo-"}" && cp "$f" "$config"
            done
        fi
        stack_rm_build
        error_report "$logs/informe-error.txt" "$stack_line" "${STEP_LOG:+$logs/$(basename "$STEP_LOG")}" "$STEP_DESC" "$config"
        echo "No se ha instalado nada. Logs de la compilacion en $logs"
        echo "Informe del error: $logs/informe-error.txt"

        exit 1
    }

    if [ -n "$build_top" ]; then
        cd "$build" && stack_build_child || stack_fail
    else
        cd "$build" || exit 1
        stack_build_phase
    fi

    # Copia a /opt. Si se rehace una version, la anterior se aparta hasta que todo este copiado.
    local aside="" was_running=0 links
    if [ "$replace" -eq 1 ]; then
        # Si es la version activa, se para mientras tanto y se arranca la nueva al terminar
        if [ -n "$TEST_DIR" ]; then
            "$target/lampp" status 2> /dev/null | grep -q " esta arrancado" && was_running=1
            "$target/lampp" stop > /dev/null 2>&1
        elif [ "$(active_dir)" == "$target" ]; then
            lampp_running && was_running=1
            sudo "$target/lampp" stop
        fi

        if [ $keep_data -eq 0 ] && [ -d "$target/var/mysql" ] && [ ! -L "$target/var/mysql" ]; then
            progress 7 97 98 "copia de las bases de datos"
            backup_databases "$lampp_name" "$target" || { echo "No se pudo guardar la copia de las bases de datos."; stack_fail; }
        fi

        aside=$target.anterior-$(date +%Y%m%d%H%M%S)
        echo "Apartando la version anterior en $aside..."
        $SUDO mv "$target" "$aside" || stack_fail
    fi

    echo "Copiando a $target..."
    progress 7 98 99 "copiando a $target"
    # Lo compilado es de tu usuario: se copia sin conservar el dueño (cada fichero nace de root, sin
    # un momento en que siga siendo tuyo ya en /opt) y sin setuid ni escritura para otros
    # (los enlaces se vuelven a mirar en la copia, que ya es de root: entre la primera comprobacion y
    # la copia se podria haber puesto otro)
    if ! { $SUDO mkdir -p "$target" && $SUDO cp -a --no-preserve=ownership "$S/." "$target/" \
            && $SUDO chmod -R go-w,ug-s "$target" \
            && links=$($SUDO /usr/bin/python3 -I -c "$BUILD_LINKS_PY" "$target" "$target") && [ -z "$links" ]; }; then
        $SUDO rm -rf "$target"
        [ -n "$aside" ] && $SUDO mv "$aside" "$target" && echo "Se ha dejado la version anterior como estaba."
        stack_fail
    fi

    if [ -z "$TEST_DIR" ]; then
        sudo chown -R root:root "$target"
        # Las dos carpetas que se abren a otros las crea root vacias: las copiadas venian de tu
        # carpeta, y si fueran un enlace root cambiaria el dueño y los permisos de lo que apuntan
        sudo rm -rf "$target/phpmyadmin/tmp" "$target/tmp"
        sudo install -d -o 0 -g "$web_group" -m 775 "$target/phpmyadmin/tmp"
        sudo install -d -o 0 -g 0 -m 1777 "$target/tmp"

        # htdocs y vhosts compartidos: se crean si es el primer LAMPP del equipo
        if [ ! -d /opt/htdocs ]; then
            sudo mkdir -p /opt/htdocs
            sudo chown "$web_user:$web_group" /opt/htdocs
        fi
        if [ ! -f /opt/config/httpd-vhosts.conf ]; then
            sudo mkdir -p /opt/config
            echo "# Virtual hosts compartidos por todas las versiones de lampp" | sudo tee /opt/config/httpd-vhosts.conf > /dev/null
        fi
    fi

    if [ $keep_data -eq 1 ]; then
        echo "Conservando las bases de datos (MariaDB ${old_mariadb} -> $mariadb)..."
        $SUDO mv "$aside/var/mysql" "$target/var/mysql" || stack_fail
    else
        progress 7 99 100 "creando las bases de datos"
        init_stack_databases "$target" || stack_fail
    fi

    echo "Comprobando la configuracion..."
    $SUDO "$target/apache2/bin/httpd" -t -f "$target/etc/httpd.conf" 2>&1 | sed 's/^/  Apache: /'
    $SUDO "$target/php/sbin/php-fpm" -t --fpm-config "$target/php/etc/php-fpm.conf" 2>&1 | sed 's/^.*NOTICE: /  PHP-FPM: /'
    $SUDO "$target/proftpd/sbin/proftpd" -t -c "$target/etc/proftpd.conf" 2>&1 | grep -iv '^checking' | sed 's/^/  ProFTPD: /'

    # Evita que "apt autoremove" desinstale librerias que usa esta pila
    if [ -z "$TEST_DIR" ]; then
        local pkgs=$(ldd "$target/php/sbin/php-fpm" "$target/apache2/bin/httpd" "$target/apache2/modules/"*.so \
            "$target/proftpd/sbin/proftpd" "$target/mysql/bin/mariadbd" 2> /dev/null | awk '/=> \//{print $3}' | sort -u \
            | while read -r lib; do
                dpkg -S "$lib" 2> /dev/null || dpkg -S "${lib#/usr}" 2> /dev/null || dpkg -S "/usr$lib" 2> /dev/null
            done | cut -d: -f1 | sort -u)
        [ -n "$pkgs" ] && sudo apt-mark manual $pkgs > /dev/null
    fi

    [ -n "$aside" ] && $SUDO rm -R --one-file-system "$aside"
    stack_rm_build

    if [ $was_running -eq 1 ]; then
        $SUDO "$target/lampp" start
    fi

    echo ""
    echo "lampp-$lampp_name instalada en $target"
    [ "$replace" -eq 1 ] && [ $keep_data -eq 0 ] && echo "Empieza con bases de datos vacias; la copia de las anteriores esta en ~/lvm-copias"
    [ "$replace" -eq 1 ] && [ $keep_data -eq 1 ] && echo "Conserva sus bases de datos"
    [ $was_running -eq 0 ] && echo "Para usarla: lvm-instalador use $lampp_name"

    return 0
}

