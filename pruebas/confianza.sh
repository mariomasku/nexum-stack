#!/bin/bash
# Pruebas de confiar-certificados (Linux 1.46.0 / Mac 1.34.0): el navegador acepta el certificado
# propio de cada proyecto https, y solo uno que no valga para otra web (TRUST_PY): autofirmado, no de
# CA, solo para su dominio y su alias, de root en la carpeta de certificados del gestor y con la clave
# solo para root. Linux: almacenes de Chrome y Firefox de una carpeta personal de prueba (certutil de
# verdad). Mac: security sustituido.
# (Linux 1.47.0 / Mac 1.35.0) El de una tienda con dominio real, solo mientras este falseada en hosts:
# al dejar de falsearla se quita (U|, Q| en la ventana).
# Uso: confianza.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-conf.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
MAC=0; grep -qE '^    BASE_DIR=(/Applications|/Library/Nexum)$' "$SRC" && MAC=1
extract "$SRC" run valid_domain vhosts_info browser_trust || exit 1
eval "$(sed -n "/^TRUST_PY='/,/^'\$/p" "$SRC")"
[ -n "$TRUST_PY" ] || { echo "no esta TRUST_PY"; exit 1; }
DRY=0 SUDO="" PORT_HTTPS=443 LOG_DIR=$W/log VHOSTS_FILE=$W/httpd-vhosts.conf OWN_SSL_DIR=$W/ssl HOSTS_FILE=$W/hosts
printf '127.0.0.1 localhost\n' > "$HOSTS_FILE"
# hosts_con <lineas...>: hosts con localhost y esas lineas
hosts_con() { { echo "127.0.0.1 localhost"; printf '%s\n' "$@"; } > "$HOSTS_FILE"; }
mkdir -p "$W/ssl" "$W/v" "$LOG_DIR" "$W/casa"
chmod 755 "$W/ssl"
export LVM_PRUEBA_DUENO=$(id -u)
q() { "$@" > /dev/null 2>&1; }
# cert <dominio> <subjectAltName> [CA:TRUE|CA:FALSE]: autofirmado en la carpeta del gestor
cert() {
    q openssl req -x509 -nodes -newkey rsa:2048 -days 30 -subj "/CN=$1" \
        -addext "basicConstraints=critical,${3:-CA:FALSE}" -addext "subjectAltName=$2" \
        -keyout "$W/ssl/$1-selfsigned.key" -out "$W/ssl/$1-selfsigned.crt"
    chmod 644 "$W/ssl/$1-selfsigned.crt"; chmod 600 "$W/ssl/$1-selfsigned.key"
}
cert buena.local "DNS:buena.local,DNS:www.buena.local"
cert www.alias.local "DNS:www.alias.local,DNS:alias.local"
cert ca.local "DNS:ca.local" CA:TRUE
cert otra.local "DNS:otra.local,DNS:google.com"
cert clave.local "DNS:clave.local"; chmod 644 "$W/ssl/clave.local-selfsigned.key"
cert enlace.local "DNS:enlace.local"; mv "$W/ssl/enlace.local-selfsigned.crt" "$W/v/e.crt"
ln -s "$W/v/e.crt" "$W/ssl/enlace.local-selfsigned.crt"
cert fuera.local "DNS:fuera.local"; mv "$W/ssl/fuera.local-selfsigned.crt" "$W/v/fuera.crt"
cert real.com "DNS:real.com,DNS:www.real.com"
cert dos.local "DNS:dos.local"; cat "$W/ssl/buena.local-selfsigned.crt" >> "$W/ssl/dos.local-selfsigned.crt"
vh() {
    local crt=${2:-$W/ssl/$1-selfsigned.crt}
    printf '<VirtualHost *:443>\n    ServerName %s\n    SSLEngine on\n    SSLCertificateFile "%s"\n    SSLCertificateKeyFile "%s"\n</VirtualHost>\n' \
        "$1" "$crt" "$W/ssl/$1-selfsigned.key"
}
{ for d in buena.local www.alias.local real.com ca.local otra.local clave.local enlace.local dos.local; do vh $d; done
  vh fuera.local "$W/v/fuera.crt"
  printf '<VirtualHost *:80>\n    ServerName solohttp.local\n</VirtualHost>\n'; } > "$VHOSTS_FILE"
trust() { LVM_INFO=$(vhosts_info) LVM_HOSTS_FILE=$HOSTS_FILE LVM_TRUST_DIR=$LOG_DIR/confianza HOME=$W/casa python3 -I -c "$TRUST_PY" "$([ $MAC -eq 1 ] && echo mac || echo linux)" 443 "$W/ssl" "$@"; }
a=$(trust)
check "el bueno se puede confiar (y aun no lo acepta el navegador)" 'grep -q "^T|buena.local|$W/ssl/buena.local-selfsigned.crt|[0-9A-F]\{40\}|0|0$" <<< "$a"'
check "con www: su alias es el dominio sin www" 'grep -q "^T|www.alias.local|" <<< "$a"'
check "dominio real sin falsear (su clave esta en la memoria de Apache): no" 'grep -q "^X|real.com|es un dominio real y no esta falseado" <<< "$a"'
hosts_con "127.0.0.1 real.com www.real.com"
check "dominio real falseado (el y su www): si, marcado como real" 'trust real.com | grep -q "^T|real.com|.*|0|1$"'
hosts_con "127.0.0.1 real.com"
check "falseado sin su www: no" 'trust real.com | grep -q "^X|real.com|"'
hosts_con "#127.0.0.1 real.com www.real.com"
check "con la linea comentada: no" 'trust real.com | grep -q "^X|real.com|"'
hosts_con "127.0.0.1 real.com www.real.com" "203.0.113.5 www.real.com"
check "con otra linea que lo lleva a otra direccion: no" 'trust real.com | grep -q "^X|real.com|"'
hosts_con "::1 real.com www.real.com  # falseado"
check "a ::1 (con comentario al final): si" 'trust real.com | grep -q "^T|real.com|"'
hosts_con
check "de CA: no" 'grep -q "^X|ca.local|" <<< "$a"'
check "con otro dominio en el certificado: no" 'grep -q "^X|otra.local|" <<< "$a"'
check "con la clave legible por otros: no" 'grep -q "^X|clave.local|" <<< "$a"'
check "certificado por un enlace: no" 'grep -q "^X|enlace.local|" <<< "$a"'
check "fuera de la carpeta del gestor: no" 'grep -q "^X|fuera.local|" <<< "$a"'
check "dos certificados en el fichero: no" 'grep -q "^X|dos.local|" <<< "$a"'
check "solo http: nada" '! grep -q "solohttp" <<< "$a"'
check "solo el dominio pedido" '[ "$(trust buena.local | cut -d"|" -f1,2)" == "T|buena.local" ]'
check "de otro dueño (no root): no" '[ "$(LVM_PRUEBA_DUENO=0 trust buena.local | cut -c1-2)" == "X|" ]'
chmod 775 "$W/ssl"
check "carpeta de certificados escribible por otros: no" '! trust | grep -q "^T|"'
chmod 755 "$W/ssl"
check "un dominio no valido no llega a mirarse" 'out=$(browser_trust "x;y" 2>&1); [ $? -ne 0 ] && grep -q "no valido" <<< "$out"'

if [ $MAC -eq 0 ]; then
    if ! command -v certutil > /dev/null; then
        bad "falta certutil (libnss3-tools) para probar los almacenes"
        exit $fail
    fi
    no_tty() { "$@" < /dev/null 2>&1; }
    # Un perfil de Firefox con su almacen
    mkdir -p "$W/casa/.mozilla/firefox/x.default"
    q certutil -N -d "sql:$W/casa/.mozilla/firefox/x.default" --empty-password
    out=$(HOME=$W/casa browser_trust 2>&1); rc=$?
    l=$(certutil -L -d "sql:$W/casa/.pki/nssdb" 2>&1)
    check "crea el almacen de Chrome y termina bien" '[ $rc -eq 0 ] && [ -f "$W/casa/.pki/nssdb/cert9.db" ]'
    check "Chrome: los buenos con confianza P (de servidor, no de CA)" 'grep -qE "^lvm-instalador buena.local +P,, *$" <<< "$l" && grep -qE "^lvm-instalador www.alias.local +P,, *$" <<< "$l"'
    check "Chrome: ninguno de los malos" '[ "$(grep -c "^lvm-instalador" <<< "$l")" -eq 2 ]'
    check "Firefox: tambien" 'certutil -L -d "sql:$W/casa/.mozilla/firefox/x.default" | grep -qE "^lvm-instalador buena.local +P,,"'
    check "ahora el navegador ya lo acepta" 'HOME=$W/casa trust buena.local | grep -q "|1|0$"'
    check "dice que hay que reabrir el navegador" 'grep -q "cierralos del todo" <<< "$out"'
    out=$(HOME=$W/casa browser_trust 2>&1)
    check "la segunda vez no cambia nada" 'grep -q "buena.local: el navegador ya lo aceptaba" <<< "$out" && ! grep -q "cierralos" <<< "$out"'
    # Se vuelve a crear el certificado: se cambia el que habia con ese nombre (no se quedan los dos)
    cert buena.local "DNS:buena.local,DNS:www.buena.local"
    check "certificado nuevo: el navegador aun no lo acepta" 'HOME=$W/casa trust buena.local | grep -q "|0|0$"'
    HOME=$W/casa browser_trust buena.local > /dev/null 2>&1
    new=$(openssl x509 -in "$W/ssl/buena.local-selfsigned.crt" -noout -fingerprint -sha1 | cut -d= -f2)
    have=$(certutil -L -d "sql:$W/casa/.pki/nssdb" -n "lvm-instalador buena.local" -a | openssl x509 -noout -fingerprint -sha1 | cut -d= -f2)
    check "y se cambia por el nuevo" '[ "$new" == "$have" ] && [ "$(certutil -L -d "sql:$W/casa/.pki/nssdb" | grep -c "lvm-instalador buena.local")" -eq 1 ]'
    check "simulacion: no toca el almacen" 'cert www.alias.local "DNS:www.alias.local,DNS:alias.local"; DRY=1 HOME=$W/casa browser_trust www.alias.local | grep -q "\[simulacion\] no_tty certutil -A" && HOME=$W/casa trust www.alias.local | grep -q "|0|0$"'
    # Tienda con dominio real: al falsearla se confia (--hosts, al cambiar hosts) y al dejar de
    # falsearla se quita, de todos los almacenes
    nicks() { certutil -L -d "sql:$1" | grep -c "^lvm-instalador $2 "; }
    hosts_con "127.0.0.1 real.com www.real.com"
    out=$(HOME=$W/casa browser_trust --hosts 2>&1)
    check "--hosts: confia en la tienda falseada" '[ "$(nicks "$W/casa/.pki/nssdb" real.com)" -eq 1 ] && [ "$(nicks "$W/casa/.mozilla/firefox/x.default" real.com)" -eq 1 ] && grep -q "real.com: el navegador ya acepta su certificado (mientras este falseado en hosts)" <<< "$out"'
    check "--hosts: solo las tiendas (no los de pruebas que aun no acepta)" '! grep -q "www.alias.local" <<< "$out" && HOME=$W/casa trust www.alias.local | grep -q "|0|0$"'
    check "--hosts: sin repetir lo que no cambia" '[ -z "$(HOME=$W/casa browser_trust --hosts 2>&1)" ]'
    hosts_con "#127.0.0.1 real.com www.real.com"
    out=$(HOME=$W/casa browser_trust --hosts 2>&1)
    check "--hosts: al dejar de falsearla se quita de Chrome y de Firefox" '[ "$(nicks "$W/casa/.pki/nssdb" real.com)" -eq 0 ] && [ "$(nicks "$W/casa/.mozilla/firefox/x.default" real.com)" -eq 0 ] && grep -q "real.com: el navegador ya no acepta su certificado" <<< "$out"'
    check "y los de pruebas se quedan" '[ "$(nicks "$W/casa/.pki/nssdb" buena.local)" -eq 1 ]'
    # hosts cambiado a mano (sin pasar por la aplicacion): la ventana lo dice (Q|) y Quitar lo quita
    hosts_con "127.0.0.1 real.com www.real.com"
    HOME=$W/casa browser_trust real.com > /dev/null 2>&1
    hosts_con
    check "a mano: TRUST_PY lo da por quitar (U|)" 'HOME=$W/casa trust | grep -qx "U|real.com"'
    check "simulacion: --quitar no lo quita" 'DRY=1 HOME=$W/casa browser_trust --quitar | grep -q "\[simulacion\] no_tty certutil -D" && [ "$(nicks "$W/casa/.pki/nssdb" real.com)" -eq 1 ]'
    out=$(HOME=$W/casa browser_trust --quitar 2>&1); rc=$?
    check "--quitar: lo quita y solo eso" '[ $rc -eq 0 ] && [ "$(nicks "$W/casa/.pki/nssdb" real.com)" -eq 0 ] && [ "$(nicks "$W/casa/.mozilla/firefox/x.default" real.com)" -eq 0 ] && [ "$(nicks "$W/casa/.pki/nssdb" buena.local)" -eq 1 ] && ! grep -q "acepta su certificado$" <<< "$out"'
    # (otro certificado de real.com, y uno de otro)
    q openssl req -x509 -nodes -newkey rsa:2048 -days 30 -subj "/CN=real.com" -keyout "$W/v/r2.key" -out "$W/v/r2.crt"
    q openssl req -x509 -nodes -newkey rsa:2048 -days 30 -subj "/CN=mio" -keyout "$W/v/o.key" -out "$W/v/o.crt"
    check "dos con el mismo nombre: se quitan los dos" 'hosts_con "127.0.0.1 real.com www.real.com"; HOME=$W/casa browser_trust real.com > /dev/null 2>&1; certutil -A -d "sql:$W/casa/.pki/nssdb" -n "lvm-instalador real.com" -t "P,," -i "$W/v/r2.crt"; [ "$(nicks "$W/casa/.pki/nssdb" real.com)" -eq 2 ] && hosts_con; HOME=$W/casa browser_trust real.com > /dev/null 2>&1; [ "$(nicks "$W/casa/.pki/nssdb" real.com)" -eq 0 ]'
    check "uno de otro (sin nuestro nombre): no se toca" 'certutil -A -d "sql:$W/casa/.pki/nssdb" -n "mio real.com" -t "P,," -i "$W/v/o.crt"; HOME=$W/casa browser_trust --quitar > /dev/null 2>&1; certutil -L -d "sql:$W/casa/.pki/nssdb" | grep -q "^mio real.com "'
    check "sin certutil, --hosts y --quitar no fallan" 'PATH=$W/bin browser_trust --hosts && PATH=$W/bin browser_trust --quitar'
    check "al cambiar hosts (editar o falsear) se llama a --hosts" '[ "$(grep -c "^        browser_trust --hosts || true$\|^    browser_trust --hosts || true$" "$SRC")" -eq 2 ]'
    # Sin certutil: dice como instalarlo
    mkdir -p "$W/bin"; for b in grep sed cut python3 openssl; do ln -sf "$(command -v $b)" "$W/bin/$b"; done
    check "sin certutil: dice como instalarlo" 'out=$(PATH=$W/bin browser_trust 2>&1); [ $? -ne 0 ] && grep -q "libnss3-tools" <<< "$out"'
    # cert_audit lleva las filas T a la ventana (G|dominio si aun avisa)
    extract "$SRC" cert_audit || exit 1
    eval "$(sed -n "/^CERTS_PY='/,/^'\$/p" "$SRC")"
    a=$(HOME=$W/casa APP_VERSION=x cert_audit)
    check "cert_audit: los propios con T" 'grep -q "^T|buena.local|.*|1|0$" <<< "$a" && grep -q "^T|www.alias.local|.*|0|0$" <<< "$a"'
    HOME=$W/casa certutil -A -d "sql:$W/casa/.pki/nssdb" -n "lvm-instalador real.com" -t "P,," -i "$W/ssl/real.com-selfsigned.crt"
    touch -d "+1 min" "$HOSTS_FILE"
    check "cert_audit: y los que hay que quitar con U (mira si cambia hosts)" 'HOME=$W/casa APP_VERSION=x cert_audit | grep -qx "U|real.com"'
    check "la ventana recibe Q|dominio de los que hay que quitar" "grep -qF '\$1 == \"U\" && !gone[\$2]++ { print \"Q|\" \$2 }' \"\$SRC\""
    check "ventana: aviso con el boton Quitar" 'grep -q "\"confiar-certificados\", \"--quitar\"\]" "$SRC" && grep -q "El navegador acepta webs reales que ya no están falseadas" "$SRC"'
    check "cert_audit --clave: sin ellas (arreglar no las usa)" '! HOME=$W/casa cert_audit --clave | grep -q "^T|"'
    check "la ventana recibe G|dominio de los que aun avisan" "grep -qF '\$1 == \"T\" && \$5 == \"0\" { print \"G|\" \$2 }' \"\$SRC\""
    check "ventana: aviso con el boton Confiar" 'grep -q "\"confiar-certificados\"\]" "$SRC" && grep -q "El navegador avisa al abrir estos proyectos" "$SRC"'
    # (desde la 1.53, tambien el vhost de un proyecto en Docker: docker_create)
    check "se confia solo al crear el vhost de web.local, el de una tienda y el de Docker" '[ "$(grep -c "^    browser_trust \"\$\(name\|domain\)\" || true$" "$SRC")" -eq $(grep -q "^function docker_create" "$SRC" && echo 3 || echo 2) ]'
else
    # Mac: add-trusted-cert con tu usuario (sin sudo), solo ssl, al llavero de inicio de sesion
    security() { echo "SEC $*" >> "$W/sec.log"; }
    out=$(HOME=$W/casa browser_trust 2>&1); rc=$?
    check "termina bien" '[ $rc -eq 0 ]'
    check "add-trusted-cert solo ssl, sin sudo, a tu llavero" 'grep -qxF "SEC add-trusted-cert -r trustRoot -p ssl -k $W/casa/Library/Keychains/login.keychain-db $W/ssl/buena.local-selfsigned.crt" "$W/sec.log"'
    check "solo los buenos" '[ "$(grep -c add-trusted-cert "$W/sec.log")" -eq 2 ] && ! grep -qE "real.com|ca.local|otra.local|clave.local|enlace|fuera|dos.local" "$W/sec.log"'
    check "no usa sudo" '! grep -q "SUDO\|sudo" <<< "$(declare -f browser_trust)"'
    security() { return 1; }
    check "si cancelas la contraseña, lo dice y falla" 'out=$(HOME=$W/casa browser_trust buena.local 2>&1); [ $? -ne 0 ] && grep -q "cancelado" <<< "$out"'
    check "la ventana recibe G|dominio de los que aun avisan" "grep -qF '\$1 == \"T\" && \$5 == \"0\" { print \"G|\" \$2 }' \"\$SRC\""
    check "ventana: aviso con el boton Confiar" 'grep -q "\"confiar-certificados\"\]" "$SRC" && grep -q "model.trustCerts()" "$SRC"'
    # Tienda con dominio real: --hosts (al cambiar hosts) no confia sola (pide la contraseña: boton
    # Confiar), y al dejar de falsearla se quita con la copia que se guarda al confiar
    sha() { openssl x509 -in "$W/ssl/$1-selfsigned.crt" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :; }
    check "guarda una copia de cada uno en el que confia" '[ -f "$LOG_DIR/confianza/buena.local.$(sha buena.local).crt" ] && [ "$(ls "$LOG_DIR/confianza" | wc -l)" -eq 2 ]'
    security() { echo "SEC $*" >> "$W/sec.log"; }
    : > "$W/sec.log"
    hosts_con "127.0.0.1 real.com www.real.com"
    out=$(HOME=$W/casa browser_trust --hosts 2>&1)
    check "--hosts: la tienda falseada no se confia sola (dice que pulses Confiar)" '! grep -q add-trusted-cert "$W/sec.log" && grep -q "real.com: para que el navegador acepte su certificado mientras este falseado, pulsa Confiar" <<< "$out"'
    HOME=$W/casa browser_trust real.com > /dev/null 2>&1
    check "Confiar: confia en la tienda falseada y guarda su copia" 'grep -q "^SEC add-trusted-cert .* $W/ssl/real.com-selfsigned.crt$" "$W/sec.log" && [ -f "$LOG_DIR/confianza/real.com.$(sha real.com).crt" ]'
    # (el security que mira TRUST_PY: real.com esta en tus ajustes de confianza)
    mkdir -p "$W/sb"; sha real.com > "$W/trusted"
    cat > "$W/sb/security" << FIN
#!/bin/bash
[ "\$1" == trust-settings-export ] && python3 -c 'import plistlib, sys; plistlib.dump({"trustList": {l.strip(): {} for l in open(sys.argv[2]) if l.strip()}}, open(sys.argv[1], "wb"))' "\$2" "$W/trusted"
exit 0
FIN
    chmod +x "$W/sb/security"
    hosts_con
    security() { return 1; }
    out=$(PATH=$W/sb:$PATH HOME=$W/casa browser_trust --hosts 2>&1); rc=$?
    check "al dejar de falsearla, si cancelas la contraseña: lo dice, falla y guarda la copia" '[ $rc -ne 0 ] && grep -q "Pulsa Quitar" <<< "$out" && [ -f "$LOG_DIR/confianza/real.com.$(sha real.com).crt" ]'
    check "y TRUST_PY lo da por quitar (U|)" 'PATH=$W/sb:$PATH trust | grep -qx "U|real.com|$LOG_DIR/confianza/real.com.$(sha real.com).crt|$(sha real.com)|1"'
    security() { echo "SEC $*" >> "$W/sec.log"; }
    : > "$W/sec.log"
    out=$(PATH=$W/sb:$PATH HOME=$W/casa browser_trust --quitar 2>&1); rc=$?
    check "--quitar: remove-trusted-cert con su copia, y la borra" '[ $rc -eq 0 ] && grep -qxF "SEC remove-trusted-cert $LOG_DIR/confianza/real.com.$(sha real.com).crt" "$W/sec.log" && [ ! -f "$LOG_DIR/confianza/real.com.$(sha real.com).crt" ]'
    check "--quitar: solo esa (los de pruebas se quedan)" '[ "$(grep -c remove-trusted-cert "$W/sec.log")" -eq 1 ] && ! grep -q add-trusted-cert "$W/sec.log" && [ -f "$LOG_DIR/confianza/buena.local.$(sha buena.local).crt" ]'
    cp "$W/ssl/real.com-selfsigned.crt" "$LOG_DIR/confianza/real.com.$(sha real.com).crt"; : > "$W/trusted"; : > "$W/sec.log"
    check "copia de uno que ya no acepta: se borra sin pedir la contraseña" 'PATH=$W/sb:$PATH HOME=$W/casa browser_trust --quitar > /dev/null 2>&1 && [ ! -s "$W/sec.log" ] && [ ! -f "$LOG_DIR/confianza/real.com.$(sha real.com).crt" ]'
    check "al cambiar hosts (editar o falsear) se llama a --hosts" '[ "$(grep -c "^        browser_trust --hosts || true$\|^    browser_trust --hosts || true$" "$SRC")" -eq 2 ]'
    check "la ventana recibe Q|dominio de los que hay que quitar" "grep -qF '\$1 == \"U\" && !gone[\$2]++ { print \"Q|\" \$2 }' \"\$SRC\""
    check "ventana: aviso con el boton Quitar" 'grep -q "\"confiar-certificados\", \"--quitar\"\]" "$SRC" && grep -q "model.untrustCerts()" "$SRC"'
fi
check "orden confiar-certificados" 'grep -q "^    confiar-certificados) browser_trust \"\$2\" ;;$" "$SRC"'
exit $fail
