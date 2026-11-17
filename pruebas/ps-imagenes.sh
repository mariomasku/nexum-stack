#!/bin/bash
# ps-imagenes (1.57.16): las direcciones de la web real salen una sola vez del DNS cifrado (nunca del
# sistema: con el dominio falseado daria este equipo) y curl va a ellas con --resolve, sin --doh-url
# (el curl 8.5 de Ubuntu 24.04 se colgaba o se caia con --doh-url y --parallel). Si curl no devuelve
# nada de un lote, se para en lugar de seguir lote tras lote. Sin red: curl de mentira.
# Uso: ps-imagenes.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
eval "$(sed -n '/^PS_IMAGES_DOH=/p' "$SRC")"
extract "$SRC" ps_images_resolve || exit 1

# --- Las direcciones, del DNS cifrado
curl() { echo "$*" >> "$W/doh"; case "$*" in
    *type=AAAA*) echo '{"Answer":[{"type":28,"data":"2606:4700::1"}]}' ;;
    *) echo '{"Answer":[{"type":5,"data":"cdn.tienda.es."},{"type":1,"data":"10.0.0.1"},{"type":1,"data":"1.2.3.4"}]}' ;;
esac; }
check "resolver: las publicas (IPv4 y la IPv6 entre corchetes), sin la privada ni el CNAME" '[ "$(ps_images_resolve tienda.es)" == "1.2.3.4,[2606:4700::1]" ]'
check "resolver: se pregunta al DNS cifrado por https (A y AAAA)" 'grep -qF -- "--proto =https" "$W/doh" && grep -qF "$PS_IMAGES_DOH?name=tienda.es&type=A" "$W/doh" && grep -qF "$PS_IMAGES_DOH?name=tienda.es&type=AAAA" "$W/doh"'
curl() { echo '{"Answer":[{"type":1,"data":"127.0.0.1"},{"type":1,"data":"192.168.1.5"},{"type":28,"data":"::1"}]}'; }
check "resolver: si solo da este equipo o redes privadas (lo de un dominio falseado), falla" '! ps_images_resolve tienda.es'
curl() { return 7; }
check "resolver: sin respuesta del DNS cifrado, falla (no se prueba con el del sistema)" '! ps_images_resolve tienda.es'
curl() { echo "<html>no es json"; }
check "resolver: una respuesta que no es JSON, falla" '! ps_images_resolve tienda.es'
unset -f curl
check "ps-imagenes: sin direcciones del DNS cifrado no descarga nada y lo dice" 'grep -q "No se pregunta al DNS de este equipo" "$SRC" && grep -qF "if ! ips=\$(ps_images_resolve \"\$domain\"); then" "$SRC"'

# --- La lista de las que faltan (1.57.21): de cada categoria, tambien su miniatura (<id>_thumb.jpg)
awk '/^    } 2> \/dev\/null \| python3 -I -c .$/ {f=1; next} f && /^. "\$HTDOCS_DIR\/\$folder"\)$/ {exit} f' "$SRC" > "$W/lista.py"
[ -s "$W/lista.py" ] || { echo "no esta el Python de la lista de ps_images"; exit 1; }
mkdir -p "$W/tienda/img/c" && : > "$W/tienda/img/c/7.jpg"
out=$(printf 'C\t7\nC\t8\nT\tcategory_default\t0\t1\t0\n' | python3 -I "$W/lista.py" "$W/tienda")
check "lista: de las categorias, la portada, sus tamaños y su miniatura (_thumb), sin las que ya estan" '[ "$out" == "$(printf "img/c/7-category_default.jpg\nimg/c/7_thumb.jpg\nimg/c/8.jpg\nimg/c/8-category_default.jpg\nimg/c/8_thumb.jpg")" ]'
out=$(printf 'I\t12\nM\t3\nT\thome_default\t1\t0\t0\n' | python3 -I "$W/lista.py" "$W/tienda")
check "lista: de los productos y las marcas, sin _thumb" '[ "$out" == "$(printf "img/p/1/2/12.jpg\nimg/p/1/2/12-home_default.jpg\nimg/m/3.jpg")" ]'

# --- La descarga (el Python de ps_images, con un curl de mentira)
awk '/python3 -I - "\$HTDOCS_DIR\/\$folder" "\$domain" "\$ips"/ {f=1; next} f && /^EOF$/ {exit} f' "$SRC" > "$W/dl.py"
[ -s "$W/dl.py" ] || { echo "no esta el Python de la descarga de ps_images"; exit 1; }
mkdir -p "$W/bin" "$W/logs" "$W/raiz/img"
chmod 700 "$W/logs"
for i in $(seq 1 350); do echo "img/p/$i.jpg"; done > "$W/lista"
# Bien: escribe cada fichero del -K y dice su resultado (y apunta con que opciones se llama)
cat > "$W/bin/curl" << 'EOF'
#!/bin/bash
echo "$*" >> "$CURL_LOG"
while [ $# -gt 0 ]; do [ "$1" == -K ] && cfg=$2; shift; done
grep -oP '^output = "\K[^"]+' "$cfg" | while read -r o; do echo imagen > "$o"; echo "0 200 $o"; done
EOF
chmod +x "$W/bin/curl"
out=$(CURL_LOG=$W/args PATH=$W/bin:$PATH python3 -I "$W/dl.py" "$W/raiz" tienda.es "1.2.3.4,[2606:4700::1]" "$W/logs" "$W/lista" "Nexum Dev Stack/1.57.16" 2>&1)
rc=$?
check "descarga: en dos lotes, las 350, y dice cuantas lleva revisadas" '[ $rc -eq 0 ] && grep -qx "Descargadas 300 de 350 (revisadas 300)" <<< "$out" && grep -qx "Descargadas 350 de 350 (revisadas 350)" <<< "$out" && [ "$(find "$W/raiz/img" -type f | wc -l)" -eq 350 ]'
check "descarga: curl va a las direcciones con --resolve, en paralelo y sin --doh-url" '[ "$(grep -c -- "--resolve tienda.es:443:1.2.3.4,\[2606:4700::1\]" "$W/args")" -eq 2 ] && grep -q -- "--parallel" "$W/args" && ! grep -q -- "--doh-url" "$W/args"'
# Mal: curl se cae sin decir nada (lo que hacia el de Ubuntu con --doh-url y --parallel)
printf '#!/bin/sh\nkill -SEGV $$\n' > "$W/bin/curl"
rm -rf "$W/raiz/img" && mkdir -p "$W/raiz/img"
out=$(PATH=$W/bin:$PATH python3 -I "$W/dl.py" "$W/raiz" tienda.es 1.2.3.4 "$W/logs" "$W/lista" x 2>&1)
rc=$?
check "curl caido: se para en el primer lote, lo dice y sale con error" '[ $rc -eq 1 ] && [ "$(grep -c "^Descargadas" <<< "$out")" -eq 1 ] && grep -q "Se para: curl no ha devuelto ningun resultado en este lote (se ha caido, señal 11)" <<< "$out"'
check "curl caido: no queda la carpeta temporal" '[ -z "$(ls "$W/logs")" ]'
exit $fail
