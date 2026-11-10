# ===========================================================================
# Tiendas PrestaShop: dominio propio, certificado y /etc/hosts falseado
# ===========================================================================
# PrestaShop redirige siempre al dominio guardado en su base (tabla shop_url), asi que no se puede
# ver por web.local. Se monta como en el manual de XAMPP del equipo: un vhost por dominio (http y
# https) con DocumentRoot en la carpeta del proyecto, un certificado autofirmado en /opt/config/ssl
# (junto al de web.local) y el dominio falseado en /etc/hosts (127.0.0.1). Al cargar otro proyecto,
# el dominio deja de estar falseado y vuelve a llevar a la web real. Hasta la 1.39 iban en
# /etc/ssl/certs, donde el sistema los toma como certificados de confianza (los pasa
# arreglar-certificados). (LVM_SSL_CERTS/LVM_SSL_KEYS solo para pruebas)
SSL_CERTS_DIR=${LVM_SSL_CERTS:-$(dirname "$VHOSTS_FILE")/ssl}
SSL_KEYS_DIR=${LVM_SSL_KEYS:-$(dirname "$VHOSTS_FILE")/ssl}
OWN_SSL_DIR=$(dirname "$VHOSTS_FILE")/ssl

#@incluir comun/tiendas-prestashop-dominio/ps_config.sh
# Certificado autofirmado (no de CA) de <dominio> y <alias> en <crt> y su clave en <key>:
# make_selfsigned <dominio> <alias> <crt> <key>. Si la carpeta es de root, openssl corre como root en
# una carpeta temporal de root (si no, con tu usuario en una tuya), y solo si <crt> y <key> estan en las
# carpetas de certificados del gestor: las rutas de un vhost las puede haber escrito cualquier programa
# tuyo (la copia de los vhosts es tuya) y root no debe crear ni machacar ficheros donde digan.
function make_selfsigned() {
    local cn=$1 alt=$2 crt=$3 key=$4 tmp s="" d ok_crt=0 ok_key=0
    for d in "$SSL_CERTS_DIR" "$OWN_SSL_DIR"; do [ "$(dirname "$crt")" == "$d" ] && ok_crt=1; done
    for d in "$SSL_KEYS_DIR" "$OWN_SSL_DIR"; do [ "$(dirname "$key")" == "$d" ] && ok_key=1; done
    if [ $ok_crt -eq 0 ] || [ $ok_key -eq 0 ] || ! [[ "$(basename "$crt")" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.(crt|pem)$ ]] \
            || ! [[ "$(basename "$key")" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.(key|pem)$ ]] || ! valid_domain "$cn"; then
        echo "El certificado de $cn ($crt) no esta en la carpeta de certificados del gestor ($OWN_SSL_DIR): no se crea."
        echo "Pulsa Arreglarlos en el aviso de certificados (Versiones) o: nexum arreglar-certificados"
        return 1
    fi
    { [ -d "$(dirname "$crt")" ] && [ -w "$(dirname "$crt")" ] && [ -w "$(dirname "$key")" ]; } || s=sudo
    [ -d "$(dirname "$crt")" ] && [ -d "$(dirname "$key")" ] || run $s mkdir -p "$(dirname "$crt")" "$(dirname "$key")" || return 1
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] certificado autofirmado de $cn en $crt (clave en $key)"
        return 0
    fi
    # Con sudo, el certificado y la clave los crea root en una carpeta de root: en una tuya, otro
    # programa tuyo podria cambiarlos por los suyos antes de que root los copie
    if [ -n "$s" ]; then
        tmp=$(sudo mktemp -d /tmp/lvm-cert.XXXXXX) && sudo chmod 700 "$tmp" || return 1
    else
        tmp=$(mktemp -d "${TMPDIR:-/tmp}/lvm-cert.XXXXXX") || return 1
    fi
    if ! $s sh -c 'umask 077; exec openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/CN=$2" \
            -addext "basicConstraints=critical,CA:FALSE" -addext "subjectAltName=$3" \
            -keyout "$1/key" -out "$1/crt"' sh "$tmp" "$cn" "DNS:$cn${alt:+,DNS:$alt}" > /dev/null 2>&1; then
        $s rm -rf "$tmp"
        echo "No se ha podido crear el certificado de $cn"
        return 1
    fi
    if [ -n "$s" ]; then
        # (install cambia el fichero por otro: si el de destino fuera un enlace, no lo sigue)
        $s install -o 0 -g 0 -m 644 "$tmp/crt" "$crt" && $s install -o 0 -g 0 -m 600 "$tmp/key" "$key"
    else
        install -m 644 "$tmp/crt" "$crt" && install -m 600 "$tmp/key" "$key"
    fi || { $s rm -rf "$tmp"; echo "No se ha podido guardar el certificado de $cn"; return 1; }
    $s rm -rf "$tmp"
    return 0
}

