#!/bin/bash
# Paquete nexum (1.57.11): lo que hacen su postinst y su postrm, sin root y sin tocar el sistema. Se
# sacan del .deb y se ejecutan con sus rutas cambiadas por las de una carpeta falsa (RAIZ): la orden
# nexum, las de antes (lvm-instalador, pvm-instalador), un lvm de otro programa (no se toca nunca) y el
# de Nexum (se quita), los iconos del menu de cada usuario y su temporizador de Docker sin visitas.
# Uso: paquete.sh <empaquetar-deb.sh> <lvm-instalador.sh>
EMP=$1 SRC=$2 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-paquete.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
mkdir "$W/src" && cp "$EMP" "$W/src/empaquetar-deb.sh" && cp "$SRC" "$W/src/lvm-instalador.sh" || exit 1
bash "$W/src/empaquetar-deb.sh" "$W/out" > /dev/null || { echo "  FALLA no se empaqueta"; exit 1; }
DEB=$(ls "$W"/out/*.deb)
check "el paquete se llama nexum y su fichero nexum_<version>_all.deb" '[ "$(dpkg-deb -f "$DEB" Package)" == nexum ] && [ "$(basename "$DEB")" == "nexum_$(dpkg-deb -f "$DEB" Version)_all.deb" ]'
check "quita el paquete de antes (Conflicts y Replaces: lvm-instalador)" '[ "$(dpkg-deb -f "$DEB" Conflicts)" == lvm-instalador ] && [ "$(dpkg-deb -f "$DEB" Replaces)" == lvm-instalador ]'
dpkg-deb -c "$DEB" | awk '{ print $NF }' | sed 's#^\./##; s#/$##' | grep . | sort > "$W/lista"
check "instala /opt/nexum (script, ayudante y clave), nexum.desktop, su icono, su ficha AppStream y su polkit, sin hexer ni lvm" \
    'diff -q "$W/lista" <(printf "%s\n" opt opt/nexum opt/nexum/nexum-actualizar opt/nexum/nexum-stack-firma.gpg opt/nexum/nexum.sh usr usr/share usr/share/applications usr/share/applications/nexum.desktop usr/share/icons usr/share/icons/hicolor usr/share/icons/hicolor/256x256 usr/share/icons/hicolor/256x256/apps usr/share/icons/hicolor/256x256/apps/nexum.png usr/share/metainfo usr/share/metainfo/io.github.mariomasku.nexum.metainfo.xml usr/share/polkit-1 usr/share/polkit-1/actions usr/share/polkit-1/actions/io.github.mariomasku.nexum.policy | sort) > /dev/null'
dpkg-deb -x "$DEB" "$W/x" && dpkg-deb -e "$DEB" "$W/ctl" || exit 1
MI=$W/x/usr/share/metainfo/io.github.mariomasku.nexum.metainfo.xml
check "ficha AppStream: Nexum Dev Stack, su icono nexum, nexum.desktop y la version del paquete con su fecha" \
    'python3 -I -c "
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
rel = r.find(\"releases/release\")
assert r.findtext(\"id\") == \"io.github.mariomasku.nexum\" and r.findtext(\"name\") == \"Nexum Dev Stack\"
assert r.findtext(\"icon\") == \"nexum\" and r.findtext(\"launchable\") == \"nexum.desktop\"
assert rel.get(\"version\") == sys.argv[2] and len(rel.get(\"date\")) == 10
assert \"hexer\" not in open(sys.argv[1]).read().lower()
" "$MI" "$(dpkg-deb -f "$DEB" Version)"'
if command -v appstreamcli > /dev/null; then
    check "ficha AppStream valida (appstreamcli validate)" 'appstreamcli validate --no-net --pedantic "$MI" > /dev/null 2>&1 || appstreamcli validate --no-net "$MI" > /dev/null 2>&1'
fi
check "el icono del menu abre /opt/nexum/nexum.sh, con el icono nexum" 'grep -qx "Exec=/opt/nexum/nexum.sh ventana" "$W/x/usr/share/applications/nexum.desktop" && grep -qx "Icon=nexum" "$W/x/usr/share/applications/nexum.desktop"'
check "polkit: nexum-actualizar, sin hexer" 'grep -q "<annotate key=\"org.freedesktop.policykit.exec.path\">/opt/nexum/nexum-actualizar</annotate>" "$W/x/usr/share/polkit-1/actions/io.github.mariomasku.nexum.policy" && ! grep -qi hexer "$W/x/usr/share/polkit-1/actions/io.github.mariomasku.nexum.policy"'
check "nexum-actualizar solo acepta nexum_*.deb, del paquete nexum" 'grep -q "^    /\*/nexum_\*_all.deb) ;;" "$W/x/opt/nexum/nexum-actualizar" && grep -q "Package 2>/dev/null)\" != nexum ]" "$W/x/opt/nexum/nexum-actualizar" && grep -q "/var/lib/dpkg/info/nexum.\" + name" "$W/x/opt/nexum/nexum-actualizar"'

# La raiz falsa: las rutas del principio de cada script, cambiadas (y nada de systemctl de verdad)
R=$W/raiz
mkdir -p "$R/opt" "$R/usr/local/bin" "$R/usr/share/applications" "$R/usr/share/icons/hicolor" "$R/home" "$R/run/user"
fake() {  # fake <postinst|postrm> -> $W/<nombre>.sh, con las rutas de la raiz falsa
    sed -e "s#^OPT=.*#OPT=$R/opt#" -e "s#^BIN=.*#BIN=$R/usr/local/bin#" -e "s#^APPS=.*#APPS=$R/usr/share/applications#" \
        -e "s#^ICONS=.*#ICONS=$R/usr/share/icons/hicolor#" -e "s#^HOMES=.*#HOMES=\"$R/home/*\"#" \
        -e "s#^RUNDIR=.*#RUNDIR=$R/run/user#" "$W/ctl/$1" > "$W/$1.sh"
    # (todas las rutas de fuera, cambiadas: si quedara alguna del sistema, la prueba no sigue)
    ! grep -qE '^(OPT|BIN|APPS|ICONS|HOMES|RUNDIR)=["]?/(opt|usr|home|run)' "$W/$1.sh"
}
fake postinst && fake postrm || { echo "  FALLA no se han podido cambiar las rutas del postinst o del postrm"; exit 1; }
check "postinst: las rutas, una por linea al principio (todas a la raiz falsa)" '[ "$(grep -cE "^(OPT|BIN|APPS|ICONS|RUNDIR)=$R/|^HOMES=\"$R/" "$W/postinst.sh")" == 6 ]'
H=$R/home/ana
mkdir -p "$H/.local/share/applications" "$H/.config/systemd/user"
B=$R/usr/local/bin
# Lo que dejo la 1.57.10: lvm-instalador y lvm de Nexum, pvm-instalador de la 1.7, un icono de usuario y
# el temporizador con la orden de antes
ln -s /opt/lvm-instalador/lvm-instalador.sh "$B/lvm-instalador"
ln -s /home/ana/viejo/pvm-instalador.sh "$B/pvm-instalador"
ln -s /opt/lvm-instalador/lvm-instalador.sh "$B/lvm"
printf '[Desktop Entry]\nType=Application\nName=Nexum Dev Stack\nExec=/opt/lvm-instalador/lvm-instalador.sh ventana\nIcon=/home/ana/.local/share/icons/lampp-version-manager.png\n' \
    > "$H/.local/share/applications/lampp-version-manager.desktop"
printf '[Unit]\nDescription=Nexum Dev Stack: parar los proyectos de Docker sin visitas\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/lvm-instalador docker-reposo comprobar\n' \
    > "$H/.config/systemd/user/nexum-reposo.service"
sh "$W/postinst.sh" configure > "$W/o1" 2>&1
check "postinst: termina bien" '[ $? -eq 0 ]'
check "nexum -> /opt/nexum/nexum.sh" '[ "$(readlink "$B/nexum")" == /opt/nexum/nexum.sh ]'
check "lvm-instalador y pvm-instalador (enlaces a un *-instalador.sh): quitados" '[ ! -e "$B/lvm-instalador" ] && [ ! -L "$B/lvm-instalador" ] && [ ! -L "$B/pvm-instalador" ]'
check "lvm de Nexum (enlace a lvm-instalador.sh): quitado" '[ ! -L "$B/lvm" ] && [ ! -e "$B/lvm" ]'
check "sin el icono del paquete: el de usuario pasa a nexum.desktop y abre el script de /opt/nexum" '[ ! -e "$H/.local/share/applications/lampp-version-manager.desktop" ] && grep -qx "Exec=/opt/nexum/nexum.sh ventana" "$H/.local/share/applications/nexum.desktop" && grep -qx "Name=Nexum Dev Stack" "$H/.local/share/applications/nexum.desktop"'
check "temporizador de Docker sin visitas: ExecStart con nexum (y lo demas igual)" 'grep -qx "ExecStart=/usr/local/bin/nexum docker-reposo comprobar" "$H/.config/systemd/user/nexum-reposo.service" && grep -qx "Type=oneshot" "$H/.config/systemd/user/nexum-reposo.service" && ! grep -q lvm-instalador "$H/.config/systemd/user/nexum-reposo.service"'
check "nada llamado lvm creado" '[ -z "$(find "$R" -name "lvm*" -print -quit)" ]'

# Otra vez, con el icono del paquete puesto y un lvm de otro programa (como el Lampp Version Manager)
rm -f "$H/.local/share/applications/nexum.desktop"
printf '[Desktop Entry]\nExec="/home/ana/mi copia/lvm-instalador.sh" ventana\n' > "$H/.local/share/applications/lampp-version-manager.desktop"
cp "$W/x/usr/share/applications/nexum.desktop" "$R/usr/share/applications/nexum.desktop"
ln -s /opt/tools/lampp-vm.sh "$B/lvm"
printf '#!/bin/sh\necho otro\n' > "$R/lvm-real"; ln -s "$R/lvm-real" "$B/lvm-otro"
ln -s /opt/otro/lvm-instalador "$B/lvm-instalador"
sh "$W/postinst.sh" configure > "$W/o2" 2>&1
check "lvm de otro programa: intacto" '[ "$(readlink "$B/lvm")" == /opt/tools/lampp-vm.sh ] && [ "$(readlink "$B/lvm-otro")" == "$R/lvm-real" ]'
check "lvm-instalador que no lleva a un *-instalador.sh: no se toca" '[ "$(readlink "$B/lvm-instalador")" == /opt/otro/lvm-instalador ]'
check "con el icono del paquete: el de usuario de antes se quita (y no se crea otro)" '[ ! -e "$H/.local/share/applications/lampp-version-manager.desktop" ] && [ ! -e "$H/.local/share/applications/nexum.desktop" ]'
check "postinst otra vez (actualizar): nexum sigue igual" '[ "$(readlink "$B/nexum")" == /opt/nexum/nexum.sh ]'
rm -f "$B/lvm-instalador" "$B/lvm-otro"

# Un nexum que no es de este programa: no se toca y se avisa
rm -f "$B/nexum"; printf '#!/bin/sh\necho mio\n' > "$B/nexum"
sh "$W/postinst.sh" configure > "$W/o3" 2>&1
check "un nexum que no es de Nexum (un fichero): no se toca y se avisa" 'grep -qx "echo mio" "$B/nexum" && grep -q "Aviso: .*nexum ya existe y no es de Nexum Dev Stack" "$W/o3"'
rm -f "$B/nexum"; ln -s /usr/bin/otro-programa "$B/nexum"
sh "$W/postinst.sh" configure > "$W/o4" 2>&1
check "un nexum que lleva a otro programa: no se toca y se avisa" '[ "$(readlink "$B/nexum")" == /usr/bin/otro-programa ] && grep -q "Aviso:" "$W/o4"'
rm -f "$B/nexum"; ln -s /home/ana/copia/nexum.sh "$B/nexum"
sh "$W/postinst.sh" configure > /dev/null 2>&1
check "un nexum a otro nexum.sh (una copia): pasa al de /opt/nexum" '[ "$(readlink "$B/nexum")" == /opt/nexum/nexum.sh ]'

# Sin seguir enlaces en la carpeta del usuario
ln -s "$R/secreto" "$H/.local/share/applications/lampp-version-manager.desktop"
echo "Exec=/opt/lvm-instalador/lvm-instalador.sh" > "$R/secreto"
rm -f "$H/.config/systemd/user/nexum-reposo.service"; echo "ExecStart=/usr/local/bin/lvm-instalador docker-reposo comprobar" > "$R/unidad"
ln -s "$R/unidad" "$H/.config/systemd/user/nexum-reposo.service"
sh "$W/postinst.sh" configure > /dev/null 2>&1
check "iconos y temporizador que son enlaces: no se siguen ni se cambian" '[ -L "$H/.local/share/applications/lampp-version-manager.desktop" ] && grep -q lvm-instalador "$R/secreto" && grep -q "/usr/local/bin/lvm-instalador" "$R/unidad"'
rm -f "$H/.local/share/applications/lampp-version-manager.desktop" "$H/.config/systemd/user/nexum-reposo.service"

# postrm: lo suyo (nexum y su icono de usuario), nunca lvm
ln -s /opt/tools/lampp-vm.sh "$B/lvm" 2> /dev/null
printf '[Desktop Entry]\nExec=/opt/nexum/nexum.sh ventana\n' > "$H/.local/share/applications/nexum.desktop"
sh "$W/postrm.sh" upgrade > /dev/null 2>&1
check "postrm al actualizar: no quita nada" '[ "$(readlink "$B/nexum")" == /opt/nexum/nexum.sh ] && [ -f "$H/.local/share/applications/nexum.desktop" ]'
sh "$W/postrm.sh" remove > "$W/o5" 2>&1
check "postrm al desinstalar: quita nexum y el icono de usuario que lo abria" '[ ! -L "$B/nexum" ] && [ ! -e "$H/.local/share/applications/nexum.desktop" ]'
check "postrm: el lvm de otro programa, intacto" '[ "$(readlink "$B/lvm")" == /opt/tools/lampp-vm.sh ]'
ln -s /usr/bin/otro-programa "$B/nexum"
sh "$W/postrm.sh" remove > /dev/null 2>&1
check "postrm: un nexum de otro programa, intacto" '[ "$(readlink "$B/nexum")" == /usr/bin/otro-programa ]'

# El script: la orden es nexum y escribe el temporizador con ella
check "script: crea la orden nexum, nunca lvm" 'grep -q "sudo ln -sf \"\$SELF\" /usr/local/bin/nexum" "$SRC" && ! grep -q "ln -s[a-z]* \"\$SELF\" /usr/local/bin/lvm" "$SRC"'
check "script: el temporizador de antes (con lvm-instalador) se rehace con nexum" 'grep -q "bin=\$(command -v nexum 2> /dev/null)" "$SRC" && grep -qF "/opt/lvm-instalador/lvm-instalador\.sh\) docker-reposo " "$SRC"'
exit $fail
