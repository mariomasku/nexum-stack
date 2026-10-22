#!/bin/bash
# Pruebas de lvm-actualizar (sin root): paquetes buenos y manipulados contra una copia del ayudante
# que mira los ficheros «instalados» en ref/ y no llama a apt-get. Uso: ayudante.sh <empaquetar-deb.sh> <lvm-instalador.sh>
set -u
EMP=$1 SRC=$2
W=$(mktemp -d "${LVM_TMP:-${TMPDIR:-/tmp}}/w-ayud.XXXX"); trap 'rm -rf "$W"' EXIT
fail=0
ok()   { echo "  ok   $1"; }
bad()  { echo "  FALLA $1"; fail=1; }
# Paquete bueno, con el script que se prueba
mkdir "$W/src"; cp "$EMP" "$W/src/empaquetar-deb.sh"; cp "$SRC" "$W/src/lvm-instalador.sh"
bash "$W/src/empaquetar-deb.sh" "$W/out" > /dev/null || { echo "no se empaqueta"; exit 1; }
GOOD=$(ls "$W"/out/*.deb)
mkdir -p "$W/ref" "$W/tree"
dpkg-deb -R "$GOOD" "$W/tree/base"
cp "$W/tree/base/opt/lvm-instalador/lvm-actualizar" "$W/ref/lvm-actualizar"
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
    "$W/ref/lvm-actualizar" > "$W/act.sh"
grep -q INSTALARIA "$W/act.sh" && grep -q "$W/ref/policy" "$W/act.sh" && grep -q "$W/ref/lvm-instalador." "$W/act.sh" \
    || { echo "no se ha podido preparar la copia del ayudante"; exit 1; }
# build <nombre> <orden que cambia el arbol (en fakeroot, $T es el arbol)>
build() {
    local n=$1; shift
    rm -rf "$W/tree/$n"; cp -a "$W/tree/base" "$W/tree/$n"
    T=$W/tree/$n fakeroot sh -c "$*; dpkg-deb --build -Zxz \"\$T\" \"$W/out/lvm-instalador_9.9.9_all.deb.$n\"" > /dev/null 2>&1
    mkdir -p "$W/dl/$n"; mv "$W/out/lvm-instalador_9.9.9_all.deb.$n" "$W/dl/$n/lvm-instalador_9.9.9_all.deb"
    echo "$W/dl/$n/lvm-instalador_9.9.9_all.deb"
}
try() {  # try <esperado: si|no> <descripcion> <deb> [huella]
    local want=$1 what=$2 deb=$3 sum=${4-}
    [ -n "$sum" ] || sum=$(sha256sum "$deb" 2>/dev/null | cut -d' ' -f1)
    out=$(sh "$W/act.sh" "$deb" "$sum" 2>&1); rc=$?
    if [ "$want" = si ]; then [ $rc -eq 0 ] && echo "$out" | grep -q INSTALARIA && ok "$what" || bad "$what: $out"
    else [ $rc -ne 0 ] && ! echo "$out" | grep -q INSTALARIA && ok "$what (rechazado: $(echo "$out" | tail -1 | cut -c1-70))" || bad "$what se acepta"; fi
}
mkdir -p "$W/dl/good"; cp "$GOOD" "$W/dl/good/lvm-instalador_9.9.9_all.deb"
try si "paquete bueno" "$W/dl/good/lvm-instalador_9.9.9_all.deb"
try no "sin huella" "$W/dl/good/lvm-instalador_9.9.9_all.deb" "x"
try no "huella de otro" "$W/dl/good/lvm-instalador_9.9.9_all.deb" "$(printf %064d 0)"
mkdir -p "$W/dl/lnk"; ln -s "$W/dl/good/lvm-instalador_9.9.9_all.deb" "$W/dl/lnk/lvm-instalador_9.9.9_all.deb"
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
try no "dueño root por numero pero de un usuario por nombre" "$W/dl/uname/lvm-instalador_9.9.9_all.deb"
pf no "$W/dl/uname/lvm-instalador_9.9.9_all.deb" "dueño por nombre"
exit $fail
