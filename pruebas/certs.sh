#!/bin/bash
# Pruebas de make_selfsigned y custom_domain (sin root). Uso: certs.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-cert.XXXX"); trap 'rm -rf "$W"' EXIT
extract "$SRC" run valid_domain make_selfsigned custom_domain || exit 1
DRY=0 SUDO="" SSL_CERTS_DIR=$W/ssl SSL_KEYS_DIR=$W/ssl OWN_SSL_DIR=$W/ssl
mkdir -p "$W/ssl" "$W/otra"
sudo() { echo "SUDO $*" >> "$W/sudo.log"; return 1; }
make_selfsigned tienda.com www.tienda.com "$W/ssl/tienda.com-selfsigned.crt" "$W/ssl/tienda.com-selfsigned.key" > /dev/null
check "crea certificado y clave en la carpeta del gestor" '[ -f "$W/ssl/tienda.com-selfsigned.crt" ] && [ -f "$W/ssl/tienda.com-selfsigned.key" ]'
check "la clave queda en 600" '[ "$(stat -c %a "$W/ssl/tienda.com-selfsigned.key")" = 600 ]'
check "no es de CA (CA:FALSE)" 'openssl x509 -in "$W/ssl/tienda.com-selfsigned.crt" -noout -ext basicConstraints | grep -q "CA:FALSE"'
check "lleva los dos nombres" 'openssl x509 -in "$W/ssl/tienda.com-selfsigned.crt" -noout -ext subjectAltName | grep -q "DNS:tienda.com, DNS:www.tienda.com"'
out=$(make_selfsigned tienda.com www.tienda.com "$W/otra/x.crt" "$W/otra/x.key"); rc=$?
check "rechaza rutas fuera de la carpeta del gestor" '[ $rc -ne 0 ] && [ ! -e "$W/otra/x.crt" ] && echo "$out" | grep -q "no se crea"'
out=$(make_selfsigned tienda.com x "$W/ssl/../otra/y.crt" "$W/ssl/y.key"); rc=$?
check "rechaza ../" '[ $rc -ne 0 ] && [ ! -e "$W/otra/y.crt" ]'
out=$(make_selfsigned "a/../b" x "$W/ssl/z.crt" "$W/ssl/z.key"); rc=$?
check "rechaza un dominio no valido" '[ $rc -ne 0 ] && [ ! -e "$W/ssl/z.crt" ]'
out=$(make_selfsigned tienda.com x "$W/ssl/z.txt" "$W/ssl/z.key"); rc=$?
check "rechaza un nombre que no es .crt/.pem" '[ $rc -ne 0 ] && [ ! -e "$W/ssl/z.txt" ]'
check "nunca usa sudo si la carpeta es tuya" '[ ! -s "$W/sudo.log" ]'
CUSTOM_DOMAINS_FILE=$W/dominios
printf 'buena.com=p1\n../../etc/x=p2\na b.com=p3\nmala.com\n=p4\n' > "$CUSTOM_DOMAINS_FILE"
check "dominio guardado bueno" '[ "$(custom_domain p1)" = buena.com ]'
check "dominio con ../ no se devuelve" '[ -z "$(custom_domain p2)" ]'
check "dominio con espacio no se devuelve" '[ -z "$(custom_domain p3)" ]'
# Carpeta de root (aqui, sin permiso de escritura): se escribe con sudo (sustituido). Desde la
# 1.41.0 el certificado y la clave los crea root (openssl con sudo) en una carpeta suya (sudo mktemp),
# y los copia con install (que no sigue un enlace en el destino). install -o 0 -g 0 se quita aqui
RO=$W/ro; mkdir -p "$RO"; chmod 555 "$RO"
SSL_CERTS_DIR=$RO SSL_KEYS_DIR=$RO OWN_SSL_DIR=$RO SUDO=sudo
sudo() {
    echo "SUDO $*" >> "$W/sudo2.log"
    [ "$1" == chown ] && return 0
    if [ "$1" == install ]; then
        shift; local a=(); while [ $# -gt 0 ]; do case $1 in -o|-g) shift 2 ;; *) a+=("$1"); shift ;; esac; done
        set -- install "${a[@]}"
    fi
    chmod u+w "$RO"; "$@"; local r=$?; chmod u-w "$RO"; return $r
}
make_selfsigned ro.com www.ro.com "$RO/ro.com-selfsigned.crt" "$RO/ro.com-selfsigned.key" > /dev/null
if grep -q "exec openssl req" "$SRC"; then
    # Linux (1.41.0): openssl como root en su carpeta y copia con install
    check "carpeta de root: crea con sudo" '[ -s "$RO/ro.com-selfsigned.crt" ] && [ "$(stat -c %a "$RO/ro.com-selfsigned.key")" = 600 ] && grep -q "SUDO sh -c umask 077; exec openssl" "$W/sudo2.log"'
    check "carpeta de root: openssl escribe en una carpeta de root (sudo mktemp) y copia con install" 'grep -q "^SUDO mktemp -d /tmp/lvm-cert" "$W/sudo2.log" && grep -q "^SUDO install -o 0 -g 0 -m 600" "$W/sudo2.log"'
    check "carpeta de root: el certificado lleva los dos nombres" 'openssl x509 -in "$RO/ro.com-selfsigned.crt" -noout -ext subjectAltName | grep -q "DNS:ro.com, DNS:www.ro.com"'
else
    # Mac: como root solo en una carpeta de root (aqui la de prueba es tuya): no se crea, y root no
    # escribe nada
    check "carpeta que no es de root: no se crea el certificado y sudo no escribe" '[ ! -e "$RO/ro.com-selfsigned.crt" ] && ! grep -qs "^SUDO sh -c umask" "$W/sudo2.log"'
fi
chmod 755 "$RO"
exit $fail
