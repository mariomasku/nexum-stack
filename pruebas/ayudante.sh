#!/bin/bash
# Pruebas de lvm-actualizar (sin root): paquetes buenos y manipulados contra una copia del ayudante
# que mira los ficheros «instalados» en ref/ y no llama a apt-get. Uso: ayudante.sh <empaquetar-deb.sh> <lvm-instalador.sh>
set -u
EMP=$1 SRC=$2
W=$(mktemp -d "${LVM_TMP:-${TMPDIR:-/tmp}}/w-ayud.XXXX"); trap 'rm -rf "$W"' EXIT
fail=0
ok()   { echo "  ok   $1"; }
bad()  { echo "  FALLA $1"; fail=1; }
# Claves de prueba (la de verdad no se usa nunca): la del script que se empaqueta y otra cualquiera
for k in gpg gpg2; do
    mkdir -m 700 "$W/$k"
    gpg --homedir "$W/$k" --batch --passphrase '' --quick-generate-key "Prueba $k <$k@prueba.local>" ed25519 sign 0 2> /dev/null \
        || { echo "no se ha podido crear la clave de prueba"; exit 1; }
done
FPR=$(gpg --homedir "$W/gpg" --with-colons --list-keys | awk -F: '/^fpr/ { print $10; exit }')
FPR2=$(gpg --homedir "$W/gpg2" --with-colons --list-keys | awk -F: '/^fpr/ { print $10; exit }')
KEY=$(gpg --homedir "$W/gpg" --export "$FPR" | base64 -w 76)
sign() { gpg --homedir "$W/${2:-gpg}" --batch --yes --detach-sign -o "$1.sig" "$1" 2> /dev/null; }
# Paquete bueno, con el script que se prueba (con la clave de prueba)
mkdir "$W/src"; cp "$EMP" "$W/src/empaquetar-deb.sh"
python3 -I - "$SRC" "$W/src/lvm-instalador.sh" "$FPR" "$KEY" <<'PY' || { echo "no se ha podido poner la clave de prueba"; exit 1; }
import re, sys
src, dst, fpr, key = sys.argv[1:5]
t = open(src, encoding="utf-8").read()
t, n1 = re.subn(r'(?m)^UPDATE_KEY_FPR="[0-9A-F]{40}"$', 'UPDATE_KEY_FPR="%s"' % fpr, t)
t, n2 = re.subn(r"(?ms)^UPDATE_KEY_B64='\n.*?\n'$", lambda m: "UPDATE_KEY_B64='\n%s\n'" % key, t)
if n1 != 1 or n2 != 1:
    sys.exit(1)
open(dst, "w", encoding="utf-8").write(t)
PY
bash "$W/src/empaquetar-deb.sh" "$W/out" > /dev/null || { echo "no se empaqueta"; exit 1; }
GOOD=$(ls "$W"/out/*.deb)
mkdir -p "$W/ref" "$W/tree"
dpkg-deb -R "$GOOD" "$W/tree/base"
cp "$W/tree/base/opt/lvm-instalador/lvm-actualizar" "$W/ref/lvm-actualizar"
cp "$W/tree/base/opt/lvm-instalador/nexum-stack-firma.gpg" "$W/ref/firma.gpg"
cp "$W/tree/base/usr/share/polkit-1/actions/dev.hexer.lvm-instalador.policy" "$W/ref/policy"
cp "$W/tree/base/DEBIAN/postinst" "$W/ref/lvm-instalador.postinst"
cp "$W/tree/base/DEBIAN/postrm" "$W/ref/lvm-instalador.postrm"
DEPS=$(dpkg-deb -f "$GOOD" Depends)
sed -e "s#/opt/lvm-instalador/lvm-actualizar\"#$W/ref/lvm-actualizar\"#" \
    -e "s#\"/usr/share/polkit-1/actions/dev.hexer.lvm-instalador.policy\"#\"$W/ref/policy\"#" \
    -e "s#/var/lib/dpkg/info/lvm-instalador.#$W/ref/lvm-instalador.#" \
    -e "s#\$(dpkg-query -W -f='\${Depends}' lvm-instalador 2>/dev/null)#$DEPS#" \
    -e "s#\$(dpkg-query -W -f=\"\\\\\${\$field}\" lvm-instalador 2>/dev/null)#\$(dpkg-deb -f \"$GOOD\" \"\$field\")#" \
    -e 's#^DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"#echo INSTALARIA#' \
    -e 's#^DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$pkg"#echo INSTALARIA#' \
    -e "s#/opt/lvm-instalador/nexum-stack-firma.gpg#$W/ref/firma.gpg#g" \
    -e "s#^installed=\$(dpkg-query -W -f='\${Version}' lvm-instalador 2>/dev/null)\$#installed=0.1#" \
    "$W/ref/lvm-actualizar" > "$W/act.sh"
grep -q INSTALARIA "$W/act.sh" && grep -q "$W/ref/policy" "$W/act.sh" && grep -q "$W/ref/lvm-instalador." "$W/act.sh" \
    && grep -q -- "--keyring $W/ref/firma.gpg" "$W/act.sh" && grep -qx "installed=0.1" "$W/act.sh" \
    || { echo "no se ha podido preparar la copia del ayudante"; exit 1; }
if grep -q "VALIDSIG $FPR " "$W/act.sh"; then ok "el ayudante exige la huella de la clave del script"; else bad "el ayudante no lleva la huella de la clave"; fi
# build <nombre> <orden que cambia el arbol (en fakeroot, $T es el arbol)>
build() {
    local n=$1; shift
    rm -rf "$W/tree/$n"; cp -a "$W/tree/base" "$W/tree/$n"
    T=$W/tree/$n fakeroot sh -c "$*; dpkg-deb --build -Zxz \"\$T\" \"$W/out/lvm-instalador_9.9.9_all.deb.$n\"" > /dev/null 2>&1
    mkdir -p "$W/dl/$n"; mv "$W/out/lvm-instalador_9.9.9_all.deb.$n" "$W/dl/$n/lvm-instalador_9.9.9_all.deb"
    sign "$W/dl/$n/lvm-instalador_9.9.9_all.deb"
    echo "$W/dl/$n/lvm-instalador_9.9.9_all.deb"
}
try() {  # try <esperado: si|no> <descripcion> <deb> [huella]
    local want=$1 what=$2 deb=$3 sum=${4-}
    [ -n "$sum" ] || sum=$(sha256sum "$deb" 2>/dev/null | cut -d' ' -f1)
    out=$(sh "$W/act.sh" "$deb" "$sum" 2>&1); rc=$?
    if [ "$want" = si ]; then [ $rc -eq 0 ] && echo "$out" | grep -q INSTALARIA && ok "$what" || bad "$what: $out"
    else [ $rc -ne 0 ] && ! echo "$out" | grep -q INSTALARIA && ok "$what (rechazado: $(echo "$out" | tail -1 | cut -c1-70))" || bad "$what se acepta"; fi
}
mkdir -p "$W/dl/good"; cp "$GOOD" "$W/dl/good/lvm-instalador_9.9.9_all.deb"; sign "$W/dl/good/lvm-instalador_9.9.9_all.deb"
try si "paquete bueno" "$W/dl/good/lvm-instalador_9.9.9_all.deb"
try no "sin huella" "$W/dl/good/lvm-instalador_9.9.9_all.deb" "x"
try no "huella de otro" "$W/dl/good/lvm-instalador_9.9.9_all.deb" "$(printf %064d 0)"
mkdir -p "$W/dl/lnk"; ln -s "$W/dl/good/lvm-instalador_9.9.9_all.deb" "$W/dl/lnk/lvm-instalador_9.9.9_all.deb"
cp "$W/dl/good/lvm-instalador_9.9.9_all.deb.sig" "$W/dl/lnk/"
try no "paquete enlazado" "$W/dl/lnk/lvm-instalador_9.9.9_all.deb" "$(sha256sum "$GOOD" | cut -d' ' -f1)"
try no "icono setuid" "$(build suid 'chmod 4755 "$T/usr/share/icons/hicolor/256x256/apps/lampp-version-manager.png"')"
try no "polkit de un usuario" "$(build polown 'chown 1000:1000 "$T/usr/share/polkit-1/actions/dev.hexer.lvm-instalador.policy"')"
try no "ayudante 0777" "$(build actmod 'chmod 777 "$T/opt/lvm-instalador/lvm-actualizar"')"
try no "script escribible por todos" "$(build scrmod 'chmod 777 "$T/opt/lvm-instalador/lvm-instalador.sh"')"
try no "carpeta 0777" "$(build dirmod 'chmod 777 "$T/opt/lvm-instalador"')"
try no "postinst enlace a uno igual" "$(build pilnk 'cp "$T/DEBIAN/postinst" '"$W"'/pi; ln -sf '"$W"'/pi "$T/DEBIAN/postinst"')"
try no "postinst distinto" "$(build pidif 'echo "# otro" >> "$T/DEBIAN/postinst"')"
try no "preinst nuevo" "$(build pre 'printf "#!/bin/sh\nexit 0\n" > "$T/DEBIAN/preinst"; chmod 755 "$T/DEBIAN/preinst"')"
try no "polkit cambiado" "$(build pol 'sed -i s/auth_admin/yes/ "$T/usr/share/polkit-1/actions/dev.hexer.lvm-instalador.policy"')"
try no "ayudante cambiado" "$(build act 'echo "# x" >> "$T/opt/lvm-instalador/lvm-actualizar"')"
try no "enlace simbolico" "$(build sl 'rm "$T/usr/share/applications/lampp-version-manager.desktop"; ln -s /etc/shadow "$T/usr/share/applications/lampp-version-manager.desktop"')"
try no "enlace duro a /etc" "$(build hl 'mkdir -p "$T/etc"; chmod 755 "$T/etc"; echo x > "$T/etc/sudoers.d-x"; chmod 644 "$T/etc/sudoers.d-x"; ln -f "$T/etc/sudoers.d-x" "$T/usr/share/applications/lampp-version-manager.desktop"')"
try no "fichero de mas" "$(build extra 'mkdir -p "$T/etc/sudoers.d"; chmod 755 "$T/etc" "$T/etc/sudoers.d"; echo x > "$T/etc/sudoers.d/x"; chmod 644 "$T/etc/sudoers.d/x"')"
try no "Conflicts" "$(build conf 'sed -i "/^Depends/a Conflicts: sudo" "$T/DEBIAN/control"')"
try no "Recommends con otro paquete" "$(build rec 'sed -i "s/^Recommends: .*/&, cowsay/" "$T/DEBIAN/control"')"
try no "Suggests nuevo" "$(build sug 'sed -i "/^Depends/a Suggests: openssh-server" "$T/DEBIAN/control"')"
if grep -q 'apt-get install -y --no-install-recommends "$pkg"' "$W/ref/lvm-actualizar"; then ok "apt sin los recomendados"; else bad "apt instala los recomendados"; fi
# Comprobacion previa de la ventana (PACKAGE_FILES_PY): lo mismo que el ayudante en el contenido
PFP=$(sed -n "/^PACKAGE_FILES_PY='/,/^'$/p" "$SRC" | sed '1d;$d')
pf() { dpkg-deb --fsys-tarfile "$2" | python3 -I -c "$PFP"; rc=$?; if [ "$1" = si ]; then [ $rc -eq 0 ] && ok "ventana: $3" || bad "ventana: $3"; else [ $rc -ne 0 ] && ok "ventana rechaza: $3" || bad "ventana acepta: $3"; fi; }
pf si "$GOOD" "paquete bueno"
pf no "$W/dl/suid/lvm-instalador_9.9.9_all.deb" "icono setuid"
pf no "$W/dl/polown/lvm-instalador_9.9.9_all.deb" "polkit de un usuario"
# uid 0 pero con el nombre de un usuario: dpkg hace caso al nombre
mkdir -p "$W/dl/uname" "$W/un"
( cd "$W/un" && ar x "$GOOD" && python3 -I - <<'PY'
import tarfile, lzma
src = tarfile.open("data.tar.xz")
with lzma.open("data2.tar.xz", "wb") as raw, tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as dst:
    for m in src.getmembers():
        if m.name.endswith("lvm-actualizar"):
            m.uname, m.gname = "usuario", "usuario"
        dst.addfile(m, src.extractfile(m) if m.isreg() else None)
PY
  mv data2.tar.xz data.tar.xz && ar rc "$W/dl/uname/lvm-instalador_9.9.9_all.deb" debian-binary control.tar.* data.tar.xz )
sign "$W/dl/uname/lvm-instalador_9.9.9_all.deb"
try no "dueño root por numero pero de un usuario por nombre" "$W/dl/uname/lvm-instalador_9.9.9_all.deb"
# Firma: con la clave de las actualizaciones, de ese paquete y sin enlaces
G=$W/dl/good/lvm-instalador_9.9.9_all.deb
mkdir -p "$W/dl/nosig"; cp "$G" "$W/dl/nosig/"
try no "sin firma" "$W/dl/nosig/lvm-instalador_9.9.9_all.deb"
mkdir -p "$W/dl/sig2"; cp "$G" "$W/dl/sig2/"; sign "$W/dl/sig2/lvm-instalador_9.9.9_all.deb" gpg2
try no "firmado con otra clave" "$W/dl/sig2/lvm-instalador_9.9.9_all.deb"
mkdir -p "$W/dl/sigother"; cp "$G" "$W/dl/sigother/"; cp "$W/dl/suid/lvm-instalador_9.9.9_all.deb.sig" "$W/dl/sigother/"
try no "firma de otro paquete" "$W/dl/sigother/lvm-instalador_9.9.9_all.deb"
mkdir -p "$W/dl/siglnk"; cp "$G" "$W/dl/siglnk/"; ln -s "$G.sig" "$W/dl/siglnk/lvm-instalador_9.9.9_all.deb.sig"
try no "firma enlazada" "$W/dl/siglnk/lvm-instalador_9.9.9_all.deb"
# Las dos claves en el fichero de claves: aun asi, solo vale la de la huella
gpg --homedir "$W/gpg2" --export "$FPR2" >> "$W/ref/firma.gpg"
try no "firmado con otra clave que tambien esta en el fichero" "$W/dl/sig2/lvm-instalador_9.9.9_all.deb"
cp "$W/tree/base/opt/lvm-instalador/nexum-stack-firma.gpg" "$W/ref/firma.gpg"
try no "clave de las firmas cambiada en el paquete" "$(build key 'gpg --homedir '"$W/gpg2"' --export '"$FPR2"' >> "$T/opt/lvm-instalador/nexum-stack-firma.gpg"')"
# Solo versiones mas nuevas que la instalada (una vieja firmada podria traer fallos ya corregidos)
for inst in "$(dpkg-deb -f "$GOOD" Version)" 99; do
    sed "s#^installed=0.1\$#installed=$inst#" "$W/act.sh" > "$W/act-$inst.sh"
    out=$(sh "$W/act-$inst.sh" "$G" "$(sha256sum "$G" | cut -d' ' -f1)" 2>&1); rc=$?
    [ $rc -ne 0 ] && ! echo "$out" | grep -q INSTALARIA && ok "instalada la $inst: rechazado ($(echo "$out" | tail -1 | cut -c1-60))" || bad "instalada la $inst: se acepta"
done
# Ventana: la firma (update_signed) y la ultima publicacion de GitHub (RELEASE_PY)
eval "$(awk '/^function update_signed\(\) \{/ { p = 1 } p { print } p && /^}/ { exit }' "$W/src/lvm-instalador.sh")"
UPDATE_KEY_FPR=$FPR UPDATE_KEY_B64=$KEY
update_signed "$G" && ok "ventana: firma buena" || bad "ventana: firma buena rechazada"
! update_signed "$W/dl/nosig/lvm-instalador_9.9.9_all.deb" && ok "ventana rechaza: sin firma" || bad "ventana acepta: sin firma"
! update_signed "$W/dl/sig2/lvm-instalador_9.9.9_all.deb" && ok "ventana rechaza: otra clave" || bad "ventana acepta: otra clave"
! update_signed "$W/dl/sigother/lvm-instalador_9.9.9_all.deb" && ok "ventana rechaza: firma de otro paquete" || bad "ventana acepta: firma de otro paquete"
! update_signed "$W/dl/siglnk/lvm-instalador_9.9.9_all.deb" && ok "ventana rechaza: firma enlazada" || bad "ventana acepta: firma enlazada"
RPY=$(sed -n "/^RELEASE_PY='/,/^'$/p" "$SRC" | sed '1d;$d')
rel() {  # rel <si|no> <descripcion> <cambio en python sobre r>
    local out json
    json=$(python3 -I -c '
import json, sys
u = "https://github.com/o/r/releases/download/v1.2.3/"
r = {"tag_name": "v1.2.3", "published_at": "2026-10-22T10:00:00Z", "draft": False, "prerelease": False,
     "assets": [{"name": n, "browser_download_url": u + n} for n in ("lvm-instalador_1.2.3_all.deb", "lvm-instalador_1.2.3_all.deb.sig")]}
exec(sys.argv[1])
print(json.dumps(r))' "$3")
    out=$(python3 -I -c "$RPY" o/r <<< "$json"); rc=$?
    if [ "$1" = si ]; then [ $rc -eq 0 ] && [ "$out" = "1.2.3|2026-10-22T10:00:00Z|https://github.com/o/r/releases/download/v1.2.3/lvm-instalador_1.2.3_all.deb|https://github.com/o/r/releases/download/v1.2.3/lvm-instalador_1.2.3_all.deb.sig" ] && ok "GitHub: $2" || bad "GitHub: $2 ($out)"
    else [ $rc -ne 0 ] && ok "GitHub rechaza: $2" || bad "GitHub acepta: $2 ($out)"; fi
}
rel si "publicacion buena" "pass"
rel no "sin firma" "r['assets'].pop()"
rel no "descarga de otro sitio" "r['assets'][0]['browser_download_url'] = 'https://evil.example.com/lvm-instalador_1.2.3_all.deb'"
rel no "descarga de otro repositorio" "r['assets'][0]['browser_download_url'] = r['assets'][0]['browser_download_url'].replace('/o/r/', '/o/x/')"
rel no "version de prueba" "r['prerelease'] = True"
rel no "borrador" "r['draft'] = True"
rel no "etiqueta con ordenes" "r['tag_name'] = 'v1.2.3;rm'"
rel no "etiqueta sin v" "r['tag_name'] = '1.2.3'"
rel no "fecha rara" "r['published_at'] = '2026-10-22 10:00|x'"
rel no "no es JSON" "r = 'x'"
pf no "$W/dl/uname/lvm-instalador_9.9.9_all.deb" "dueño por nombre"
exit $fail
