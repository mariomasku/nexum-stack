#!/bin/bash
# Prueba de cert_audit y fix_certs sobre vhosts de prueba (sudo y edit_vhosts sustituidos, CAs de
# prueba con LVM_PRUEBA_CAS). Uso: arreglar-certs.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-fix.XXXX"); trap 'rm -rf "$W"' EXIT
extract "$SRC" run valid_domain domain_alias make_selfsigned vhosts_info cert_audit fix_certs || exit 1
eval "$(sed -n "/^CERTS_PY='/,/^'\$/p" "$SRC")"
DRY=0 SUDO="" PORT_HTTPS=443 LOG_DIR=$W/log APP_VERSION=x
VHOSTS_FILE=$W/httpd-vhosts.conf OWN_SSL_DIR=$W/ssl SSL_CERTS_DIR=$W/ssl SSL_KEYS_DIR=$W/ssl
export LVM_PRUEBA_CAS=$W/cas LVM_PRUEBA_CLAVES=$W/otra LVM_PRUEBA_SSL=$W/sinssl
mkdir -p "$W/ssl" "$W/v" "$LOG_DIR" "$LVM_PRUEBA_CAS" "$W/otra"
sudo() { echo "SUDO $*" >> "$W/sudo.log"; "$@"; }
edit_vhosts() { [ "$1" == --aplicar ] && cp "$2" "$VHOSTS_FILE"; }
browser_trust() { echo "CONFIAR $*" >> "$W/confiar.log"; }
q() { "$@" > /dev/null 2>&1; }
# CA de confianza sin limite de dominios, y un certificado de tienda.com firmado por ella
q openssl req -x509 -nodes -newkey rsa:2048 -days 30 -subj "/CN=CA de prueba" -keyout "$W/otra/ca.key" -out "$LVM_PRUEBA_CAS/ca.crt"
q openssl req -nodes -newkey rsa:2048 -subj "/CN=tienda.com" -keyout "$W/v/t.key" -out "$W/v/t.csr"
q openssl x509 -req -in "$W/v/t.csr" -CA "$LVM_PRUEBA_CAS/ca.crt" -CAkey "$W/otra/ca.key" -CAcreateserial -days 30 -out "$W/v/t.crt"
# falsa.com: dice que lo emite la CA de prueba, pero lo firma otra con el mismo nombre
q openssl req -x509 -nodes -newkey rsa:2048 -days 30 -subj "/CN=CA de prueba" -keyout "$W/otra/falsa.key" -out "$W/otra/falsa.crt"
q openssl req -nodes -newkey rsa:2048 -subj "/CN=falsa.com" -keyout "$W/v/f.key" -out "$W/v/f.csr"
q openssl x509 -req -in "$W/v/f.csr" -CA "$W/otra/falsa.crt" -CAkey "$W/otra/falsa.key" -CAcreateserial -days 30 -out "$W/v/f.crt"
# viejo.com: autofirmado con CA:TRUE, pero nadie confia en el; deconfianza.com: CA:TRUE y en el almacen
q openssl req -x509 -nodes -newkey rsa:2048 -days 30 -subj "/CN=viejo.com" -addext "basicConstraints=critical,CA:TRUE" -keyout "$W/v/v.key" -out "$W/v/v.crt"
q openssl req -x509 -nodes -newkey rsa:2048 -days 30 -subj "/CN=deconfianza.com" -addext "basicConstraints=critical,CA:TRUE" -keyout "$W/v/d.key" -out "$W/v/d.crt"
cp "$W/v/d.crt" "$LVM_PRUEBA_CAS/d.crt"
vh() { printf '<VirtualHost *:443>\n    ServerName %s\n    SSLEngine on\n    SSLCertificateFile "%s"\n    SSLCertificateKeyFile %s\n</VirtualHost>\n' "$1" "$2" "$3"; }
{ printf '<VirtualHost *:80>\n    ServerName tienda.com\n</VirtualHost>\n'
  vh tienda.com "$W/v/t.crt" "$W/v/t.key"; vh falsa.com "$W/v/f.crt" "$W/v/f.key"
  vh viejo.com "$W/v/v.crt" "$W/v/v.key"; vh deconfianza.com "$W/v/d.crt" "$W/v/d.key"; } > "$VHOSTS_FILE"
a=$(cert_audit)
check "detecta el firmado por una CA local" 'grep -q "^C|tienda.com|.*|firmado$" <<< "$a" && grep -q "^A|CA de prueba|" <<< "$a"'
check "no se fia del nombre del emisor (firma falsa)" '! grep -q "falsa.com" <<< "$a"'
check "de CA sin confianza: no avisa" '! grep -q "viejo.com" <<< "$a"'
check "de CA y de confianza: avisa" 'grep -q "^C|deconfianza.com|.*|ca$" <<< "$a"'
fix_certs > "$W/out.txt" 2>&1
check "despues, el navegador acepta los certificados propios (confiar-certificados)" '[ -f "$W/confiar.log" ]'
check "tienda.com pasa a su certificado propio" 'grep -q "SSLCertificateFile \"$W/ssl/tienda.com-selfsigned.crt\"" "$VHOSTS_FILE" && grep -q "SSLCertificateKeyFile \"$W/ssl/tienda.com-selfsigned.key\"" "$VHOSTS_FILE"'
check "los demas no se tocan" 'grep -q "\"$W/v/f.crt\"" "$VHOSTS_FILE" && grep -q "\"$W/v/v.crt\"" "$VHOSTS_FILE"'
check "el nuevo no es de CA" 'openssl x509 -in "$W/ssl/tienda.com-selfsigned.crt" -noout -ext basicConstraints | grep -q CA:FALSE'
check "la CA de prueba no se toca (no esta en /usr/local/share)" '[ -f "$LVM_PRUEBA_CAS/ca.crt" ] && ! grep -q "rm -f $LVM_PRUEBA_CAS" "$W/sudo.log" 2> /dev/null'
rm -f "$LVM_PRUEBA_CAS/d.crt"
# Con la CA aun de confianza pero sin su clave en tu carpeta: ya no se avisa de ella
mv "$W/otra/ca.key" "$W/ca.key.fuera"
printf '<VirtualHost *:443>\n    ServerName otra2.com\n    SSLCertificateFile "%s"\n    SSLCertificateKeyFile "%s"\n</VirtualHost>\n' "$W/v/t.crt" "$W/v/t.key" >> "$VHOSTS_FILE"
rm -f "$LOG_DIR/certificados"; a=$(cert_audit)
check "CA sin su clave al alcance: no se avisa" '! grep -q "^A|" <<< "$a" && ! grep -q "otra2.com" <<< "$a"'
sed -i "/otra2.com/,+3d" "$VHOSTS_FILE"; sed -i '/^<VirtualHost \*:443>$/{N;/\n$/d}' "$VHOSTS_FILE"
rm -f "$LVM_PRUEBA_CAS/ca.crt"
check "despues ya no hay nada que arreglar" '[ -z "$(cert_audit)" ]'
check "segunda vez: dice que ya esta bien" 'fix_certs | grep -q "ya estan bien"'
# Certificado viejo sin usar en la carpeta de confianza (aqui, la de prueba): se avisa
mkdir -p "$W/sinssl"; cp "$W/v/v.crt" "$W/sinssl/viejo.com-selfsigned.crt"; cp "$W/v/v.crt" "$W/sinssl/x-selfsigned.crt.bak-1"
rm -f "$LOG_DIR/certificados"; a=$(cert_audit)
check "avisa de los certificados viejos sin usar (y sus .bak)" 'grep -q "^S|$W/sinssl/viejo.com-selfsigned.crt$" <<< "$a" && grep -q "x-selfsigned.crt.bak-1" <<< "$a"'
exit $fail
