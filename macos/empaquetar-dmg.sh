#!/bin/bash
# Crea el .dmg de Nexum Dev Stack para Mac a partir de lvm-instalador.sh (la version sale de
# su APP_VERSION y el icono de su ICON_PNG_B64). Se ejecuta en un Mac: usa hdiutil, sips e iconutil,
# que vienen con macOS (desde Linux no se puede crear un .dmg que macOS monte sin herramientas de fuera).
#
# Uso, en la carpeta donde estan este archivo y lvm-instalador.sh:
#   bash empaquetar-dmg.sh [carpeta de salida]     (por defecto ~/Downloads, «Descargas» en Finder)
#
# El disco lleva:
#   Instalar Nexum Dev Stack.app   abre Terminal con el instalador (instalar.sh), que ejecuta
#     "lvm-instalador.sh instalar-gestor" del disco (desde la 1.39.3):
#     - prepara lo que falte (herramientas de Xcode, Homebrew y whiptail)
#     - lo instala en /Library/Nexum/gestor, de root (pide la contraseña de administrador), con su
#       bash compilado del codigo de GNU; si ya hay una version mas nueva, no la cambia
#     - pasa las versiones de antes de la 1.39.3 de /Applications a /Library/Nexum, deja la copia de
#       ~/lvm-instalador en un aviso, crea o apunta los comandos y la aplicacion y abre la ventana
#   LEEME.txt
#
# Imagen UDIF comprimida (UDZO) con HFS+. Sin firma de Apple (solo la local, como la aplicacion que
# crea el gestor): la primera vez macOS pide permiso para abrir el instalador.

set -e -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/lvm-instalador.sh
OUT=${1:-$HOME/Downloads}
NAME="Nexum Dev Stack"
INSTALLER="Instalar $NAME"

VERSION=$(grep -m1 '^APP_VERSION=' "$SRC" | cut -d'"' -f2)
[ -n "$VERSION" ] || { echo "No se encuentra APP_VERSION en $SRC"; exit 1; }
bash -n "$SRC"
if [ "$(uname -s)" != "Darwin" ] || ! command -v hdiutil > /dev/null; then
    echo "Este script se ejecuta en un Mac: el .dmg se crea con hdiutil, que solo existe en macOS."
    exit 1
fi

BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
ROOT=$BUILD/disco
APP=$ROOT/$INSTALLER.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

install -m 755 "$SRC" "$APP/Contents/Resources/lvm-instalador.sh"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$INSTALLER</string>
    <key>CFBundleDisplayName</key><string>$INSTALLER</string>
    <key>CFBundleIdentifier</key><string>dev.hexer.lvm-instalador.instalar</string>
    <key>CFBundleExecutable</key><string>instalar</string>
    <key>CFBundleIconFile</key><string>icono</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict>
</plist>
EOF

# Ejecutable de la aplicacion: abre Terminal con instalar.sh (puede tener que preguntar: Homebrew,
# contraseña...). El .command se escribe en una carpeta temporal y sin atributos: el del disco
# llevaria la cuarentena de la descarga y macOS volveria a pedir permiso para abrirlo.
cat > "$APP/Contents/MacOS/instalar" <<'EOF'
#!/bin/bash
RES=$(cd "$(dirname "$0")/../Resources" && pwd)
CMD=$(mktemp -d /tmp/lvm-instalar-XXXX)/instalar.command
printf '#!/bin/bash\nexec /bin/bash %q\n' "$RES/instalar.sh" > "$CMD"
chmod 755 "$CMD"
xattr -c "$CMD" 2> /dev/null
exec open -a Terminal "$CMD"
EOF
chmod 755 "$APP/Contents/MacOS/instalar"

cat > "$APP/Contents/Resources/instalar.sh" <<'EOF'
#!/bin/bash
# Instala o actualiza Nexum Dev Stack (lo abre en Terminal la aplicacion del .dmg). Desde la 1.39.3 el
# gestor va en /Library/Nexum/gestor, de root, y lo instala el propio lvm-instalador.sh de este disco
# (instalar-gestor): pide la contraseña de administrador, comprueba la copia y, si ya tienes una
# version mas nueva, no la cambia. Despues pasa las versiones de antes a /Library/Nexum, apunta los
# comandos y la aplicacion al gestor y abre la ventana.

HERE=$(cd "$(dirname "$0")" && pwd)
NEW=$HERE/lvm-instalador.sh
NAME="Nexum Dev Stack"

function finish() {
    echo
    echo "$1"
    echo
    echo "Ya puedes cerrar esta ventana de Terminal y expulsar el disco «$NAME»."
    exit "${2:-0}"
}

NEW_V=$(/usr/bin/grep -m1 '^APP_VERSION=' "$NEW" 2> /dev/null | /usr/bin/cut -d'"' -f2)
clear
echo "$NAME $NEW_V"
echo "================================"
echo

if ! /bin/bash "$NEW" instalar-gestor; then
    finish "No se ha terminado de instalar. Si se estaba instalando algo (las herramientas de Xcode), cuando acabe vuelve a abrir «Instalar $NAME»." 1
fi

finish "Listo: el gestor esta en /Library/Nexum/gestor (de root), «$NAME» en Launchpad y en ~/Applications, y en la terminal tienes los comandos lvm-instalador y lvm."
EOF
chmod 755 "$APP/Contents/Resources/instalar.sh"

# Icono: el PNG del script, ampliado a los tamaños que pide macOS y convertido a .icns (como create_app)
sed -n "/^ICON_PNG_B64='/,/^'$/p" "$SRC" | sed '1s/^ICON_PNG_B64=.//; $d' | tr -d ' \n' \
    | base64 --decode > "$BUILD/icono.png"
mkdir -p "$BUILD/icono.iconset"
for size in 16 32 128 256 512; do
    sips -z $size $size "$BUILD/icono.png" --out "$BUILD/icono.iconset/icon_${size}x${size}.png" > /dev/null
    sips -z $(( size * 2 )) $(( size * 2 )) "$BUILD/icono.png" --out "$BUILD/icono.iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$BUILD/icono.iconset" -o "$APP/Contents/Resources/icono.icns"

cat > "$ROOT/LEEME.txt" <<EOF
$NAME $VERSION para Mac con Apple Silicon
$(printf '%*s' $(( ${#NAME} + ${#VERSION} + 27 )) '' | tr ' ' '=')

INSTALAR O ACTUALIZAR
Haz doble clic en «$INSTALLER». Se abre Terminal y:
- lo instala (o lo actualiza) en /Library/Nexum/gestor, una carpeta de
  root: pide tu contraseña de administrador. Si ya tienes una version
  mas nueva, no cambia nada;
- la primera vez instala lo que haga falta: las herramientas de Xcode
  (despues hay que volver a abrir el instalador), Homebrew y el bash
  del gestor (se compila en un minuto);
- si tus versiones de PHP son de antes de la 1.39.3, las pasa de
  /Applications a /Library/Nexum, con sus bases de datos, proyectos,
  vhosts y certificados (en /Applications queda un enlace a cada una);
- crea los comandos lvm-instalador y lvm y abre la ventana. La
  aplicacion «$NAME» queda en Launchpad y en ~/Applications.

Tus proyectos y tus bases de datos no se tocan.

SI MACOS NO DEJA ABRIRLO
El instalador no esta firmado por Apple. La primera vez macOS dice que
no puede comprobar que no tiene software malicioso:
- macOS 14 o anterior: boton derecho sobre el instalador > Abrir > Abrir.
- macOS 15 o posterior: pulsa "Hecho", ve a Ajustes del Sistema >
  Privacidad y seguridad, baja hasta "Se ha bloqueado..." y pulsa "Abrir
  igualmente". Vuelve a abrir el instalador.

Otra forma, sin abrir la aplicacion: en Terminal,
  bash /Volumes/Nexum*/Instalar*.app/Contents/Resources/instalar.sh
EOF

# Firma local (sin certificado) y sin atributos de cuarentena del script descargado
xattr -cr "$ROOT"
codesign --force --deep -s - "$APP" > /dev/null 2>&1 || true

mkdir -p "$OUT"
DMG=$OUT/lvm-instalador-mac-$VERSION.dmg
hdiutil create -quiet -ov -volname "$NAME $VERSION" -srcfolder "$ROOT" -fs HFS+ -format UDZO "$DMG"
# Comprobacion: se monta y lleva el instalador con su ejecutable
MNT=$(mktemp -d)
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" "$DMG"
ok=0
[ -x "$MNT/$INSTALLER.app/Contents/MacOS/instalar" ] && cmp -s "$MNT/$INSTALLER.app/Contents/Resources/lvm-instalador.sh" "$SRC" && ok=1
hdiutil detach -quiet "$MNT"
rmdir "$MNT"
[ $ok -eq 1 ] || { echo "El .dmg se ha creado, pero al montarlo no esta bien el instalador: $DMG"; exit 1; }
echo "Creado y comprobado: $DMG"
