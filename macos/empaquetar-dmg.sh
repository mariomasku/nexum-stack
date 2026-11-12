#!/bin/bash
# Crea el .dmg de Nexum Dev Stack para Mac (nexum-mac-<version>.dmg) a partir de lvm-instalador.sh (la version sale de
# su APP_VERSION, el icono de su ICON_PNG_B64 y la tipografia del fondo de su FONT_GOLDMAN_B64) y de
# instalador.swift. Se ejecuta en un Mac: usa hdiutil, sips, iconutil, tiffutil y osascript, que vienen con
# macOS, y swiftc, de las herramientas de Xcode (desde Linux no se puede crear un .dmg que macOS monte sin
# herramientas de fuera).
#
# Uso, en la carpeta donde estan este archivo, instalador.swift y lvm-instalador.sh:
#   bash empaquetar-dmg.sh [carpeta de salida]     (por defecto ~/Downloads, «Descargas» en Finder)
#
# El disco lleva, en una ventana de Finder con su fondo (el logotipo, el nombre y la version) y los iconos
# grandes, sin barras:
#   Instalar Nexum Dev Stack.app   el instalador (instalador.swift, compilado aqui): una ventana con el logotipo
#     y el boton Instalar. Ejecuta, sin que se vea, "lvm-instalador.sh instalar-gestor" del disco y enseña sus
#     pasos en una barra con el porcentaje; la contraseña de administrador la pide en su panel. Al acabar,
#     «Se ha finalizado la instalacion» y el boton «Abrir Nexum Dev Stack». instalar-gestor:
#     - prepara lo que falte (herramientas de Xcode, Homebrew y whiptail)
#     - lo instala en /Library/Nexum/gestor, de root, con su bash compilado del codigo de GNU; si ya hay una
#       version mas nueva, no la cambia
#     - pasa las versiones de antes de la 1.39.3 de /Applications a /Library/Nexum, deja la copia de
#       ~/lvm-instalador en un aviso y crea o apunta el comando nexum y la aplicacion
#     (Contents/Resources/instalar.sh hace lo mismo en Terminal: la otra forma del LEEME)
#   LEEME.txt
#
# Imagen UDIF comprimida (UDZO) con HFS+. Se crea primero en lectura y escritura (UDRW) para que Finder guarde
# en ella la presentacion de la ventana; si Finder no deja (sin permiso de automatizacion para osascript), el
# .dmg se crea igual, sin la presentacion, y se avisa. Sin firma de Apple (solo la local, como la aplicacion
# que crea el gestor): la primera vez macOS pide permiso para abrir el instalador.

set -e -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/lvm-instalador.sh
SWIFT_SRC=$HERE/instalador.swift
OUT=${1:-$HOME/Downloads}
NAME="Nexum Dev Stack"
INSTALLER="Instalar $NAME"
# Ventana del disco en Finder: el fondo mide esto (en puntos; va tambien al doble, para pantallas Retina)
WIN_W=640 WIN_H=400 ICON_SIZE=112

VERSION=$(grep -m1 '^APP_VERSION=' "$SRC" | cut -d'"' -f2)
[ -n "$VERSION" ] || { echo "No se encuentra APP_VERSION en $SRC"; exit 1; }
bash -n "$SRC"
[ -f "$SWIFT_SRC" ] || { echo "No esta $SWIFT_SRC (el instalador): tiene que estar junto a este archivo."; exit 1; }
if [ "$(uname -s)" != "Darwin" ] || ! command -v hdiutil > /dev/null; then
    echo "Este script se ejecuta en un Mac: el .dmg se crea con hdiutil, que solo existe en macOS."
    exit 1
fi
if ! SWIFTC=$(xcrun --sdk macosx --find swiftc 2> /dev/null) || [ ! -x "$SWIFTC" ]; then
    echo "Hace falta swiftc para compilar el instalador: instala las herramientas de Xcode (xcode-select --install)"
    echo "y vuelve a ejecutar este script."
    exit 1
fi
VOLNAME="$NAME $VERSION"

BUILD=$(mktemp -d)
RW_MNT=""
function cleanup() {
    [ -n "$RW_MNT" ] && hdiutil detach -quiet -force "$RW_MNT" 2> /dev/null
    rm -rf "$BUILD"
}
trap cleanup EXIT
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
    <key>CFBundleIdentifier</key><string>io.github.mariomasku.nexum.instalar</string>
    <key>CFBundleExecutable</key><string>instalar</string>
    <key>CFBundleIconFile</key><string>icono</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# El instalador (AppKit), para Apple Silicon y macOS 12 o posterior
echo "Compilando el instalador..."
cp "$SWIFT_SRC" "$BUILD/main.swift"
if ! "$SWIFTC" -O -target arm64-apple-macos12.0 -o "$APP/Contents/MacOS/instalar" "$BUILD/main.swift" \
        -framework AppKit > "$BUILD/compilar.log" 2>&1; then
    cat "$BUILD/compilar.log"
    echo "No se ha podido compilar el instalador ($SWIFT_SRC)."
    exit 1
fi
chmod 755 "$APP/Contents/MacOS/instalar"

# La otra forma, en Terminal (la del LEEME): lo mismo que el instalador, con sus preguntas en la terminal
cat > "$APP/Contents/Resources/instalar.sh" <<'EOF'
#!/bin/bash
# Instala o actualiza Nexum Dev Stack en Terminal (lo mismo que hace «Instalar Nexum Dev Stack» del .dmg en su
# ventana). El gestor va en /Library/Nexum/gestor, de root, y lo instala el propio lvm-instalador.sh de este
# disco (instalar-gestor): pide la contraseña de administrador, comprueba la copia y, si ya tienes una version
# mas nueva, no la cambia. Despues pasa las versiones de antes a /Library/Nexum, apunta los comandos y la
# aplicacion al gestor y abre la ventana.

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

finish "Listo: el gestor esta en /Library/Nexum/gestor (de root), «$NAME» en Launchpad y en ~/Applications, y en la terminal tienes la orden nexum."
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
# (el logotipo grande, para el fondo del disco)
sips -z 256 256 "$BUILD/icono.png" --out "$BUILD/logo.png" > /dev/null

# Fondo de la ventana del disco: lo dibuja un programa de AppKit compilado aqui mismo (sin nada de Homebrew),
# a su tamaño y al doble, y tiffutil los junta en un TIFF que Finder usa segun la pantalla. Si no se puede,
# el disco va sin fondo
sed -n "/^FONT_GOLDMAN_B64='/,/^'$/p" "$SRC" | sed '1s/^FONT_GOLDMAN_B64=.//; $d' | tr -d ' \n' \
    | base64 --decode > "$BUILD/Goldman-Regular.ttf" 2> /dev/null || rm -f "$BUILD/Goldman-Regular.ttf"
mkdir -p "$BUILD/fondo"
cat > "$BUILD/fondo/main.swift" <<'EOF'
// Fondo de la ventana del .dmg: argumentos <png 1x> <png 2x> <version> <logo.png> <ancho> <alto> [Goldman.ttf]
import AppKit
import CoreText

let a = CommandLine.arguments
guard a.count >= 7, let w = Double(a[5]), let h = Double(a[6]) else { exit(2) }
let W = CGFloat(w), H = CGFloat(h)
if a.count > 7 { _ = CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: a[7]) as CFURL, .process, nil) }
let version = a[3]
let logo = NSImage(contentsOfFile: a[4])
func rgb(_ v: Int) -> NSColor {
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let colors = [0x006CB7, 0x88BB1D, 0xFFB608, 0xFF0000, 0xF20093].map { rgb($0) }

/// y desde arriba (como en Finder) a y de AppKit (desde abajo)
func top(_ y: CGFloat, _ h: CGFloat = 0) -> CGFloat { return H - y - h }

func draw() {
    let all = NSRect(x: 0, y: 0, width: W, height: H)
    NSGradient(starting: rgb(0xF4F7FB), ending: rgb(0xE2E9F1))?.draw(in: all, angle: -90)
    // Las franjas con los colores del logotipo, arriba y abajo
    let g = NSGradient(colors: colors)
    g?.draw(in: NSRect(x: 0, y: top(0, 6), width: W, height: 6), angle: 0)
    g?.draw(in: NSRect(x: 0, y: 0, width: W, height: 4), angle: 0)
    // Un halo claro detras del instalador
    NSGradient(colors: [NSColor(white: 1, alpha: 0.95), NSColor(white: 1, alpha: 0)])?
        .draw(in: NSBezierPath(ovalIn: NSRect(x: W / 2 - 120, y: top(180) - 120, width: 240, height: 240)),
              relativeCenterPosition: .zero)
    // El logotipo y el nombre
    logo?.draw(in: NSRect(x: 34, y: top(26, 60), width: 60, height: 60), from: .zero, operation: .sourceOver, fraction: 1)
    let goldman = NSFont(name: "Goldman", size: 28) ?? NSFont.systemFont(ofSize: 26, weight: .heavy)
    let name = NSMutableAttributedString(string: "NEXUM", attributes: [.font: goldman, .foregroundColor: rgb(0x006CB7), .kern: 1])
    name.append(NSAttributedString(string: "  Dev Stack", attributes: [
        .font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: rgb(0x1D2228)]))
    name.draw(at: NSPoint(x: 106, y: top(30, 34)))
    NSAttributedString(string: "Versión " + version + "   ·   Mac con Apple Silicon", attributes: [
        .font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: rgb(0x5A6573)]).draw(at: NSPoint(x: 108, y: top(66, 16)))
    // «Doble clic para instalar», en una píldora con el borde de colores (como los avisos de la ventana)
    let hint = NSAttributedString(string: "Doble clic para instalar", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: rgb(0x2A3340)])
    let size = hint.size()
    let pw: CGFloat = size.width + 44, ph: CGFloat = 34
    let pill = NSRect(x: (W - pw) / 2, y: top(300, ph), width: pw, height: ph)
    let path = NSBezierPath(roundedRect: pill, xRadius: ph / 2, yRadius: ph / 2)
    NSColor(white: 1, alpha: 0.92).setFill()
    path.fill()
    NSGraphicsContext.saveGraphicsState()
    path.setClip()
    let ring = NSBezierPath(roundedRect: pill.insetBy(dx: -1, dy: -1), xRadius: ph / 2 + 1, yRadius: ph / 2 + 1)
    ring.append(NSBezierPath(roundedRect: pill.insetBy(dx: 2.5, dy: 2.5), xRadius: ph / 2 - 2.5, yRadius: ph / 2 - 2.5).reversed)
    ring.setClip()
    g?.draw(in: pill, angle: 0)
    NSGraphicsContext.restoreGraphicsState()
    hint.draw(at: NSPoint(x: pill.minX + 22, y: pill.minY + (ph - size.height) / 2))
}

func render(_ scale: CGFloat, _ out: String) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]),
          (try? data.write(to: URL(fileURLWithPath: out))) != nil else { exit(1) }
}

render(1, a[1])
render(2, a[2])
EOF
BACKGROUND=""
FONT_ARG=()
[ -s "$BUILD/Goldman-Regular.ttf" ] && FONT_ARG=("$BUILD/Goldman-Regular.ttf")
if "$SWIFTC" -O -target arm64-apple-macos12.0 -o "$BUILD/fondo/fondo" "$BUILD/fondo/main.swift" -framework AppKit \
        > "$BUILD/fondo/compilar.log" 2>&1 \
        && "$BUILD/fondo/fondo" "$BUILD/fondo.png" "$BUILD/fondo@2x.png" "$VERSION" "$BUILD/logo.png" "$WIN_W" "$WIN_H" \
            "${FONT_ARG[@]}"; then
    mkdir -p "$ROOT/.background"
    if tiffutil -cathidpicheck "$BUILD/fondo.png" "$BUILD/fondo@2x.png" -out "$ROOT/.background/fondo.tiff" > /dev/null 2>&1; then
        BACKGROUND=fondo.tiff
    else
        cp "$BUILD/fondo.png" "$ROOT/.background/fondo.png"
        BACKGROUND=fondo.png
    fi
else
    echo "Aviso: no se ha podido dibujar el fondo del disco (va sin el):"
    tail -5 "$BUILD/fondo/compilar.log" 2> /dev/null | sed 's/^/  /'
fi

cat > "$ROOT/LEEME.txt" <<EOF
$NAME $VERSION para Mac con Apple Silicon
$(printf '%*s' $(( ${#NAME} + ${#VERSION} + 27 )) '' | tr ' ' '=')

INSTALAR O ACTUALIZAR
Haz doble clic en «$INSTALLER» y pulsa Instalar. Se abre una
ventana con el logotipo y una barra con el porcentaje y lo que se esta
haciendo en cada momento:
- lo instala (o lo actualiza) en /Library/Nexum/gestor, una carpeta de
  root: pide tu contraseña de administrador en su propio panel. Si ya
  tienes una version mas nueva, no cambia nada;
- la primera vez instala lo que haga falta: las herramientas de Xcode
  (sale la ventana de Apple; cuando terminan, la instalacion sigue
  sola), Homebrew (te pregunta antes) y el bash del gestor (se compila
  en un minuto o dos);
- si tus versiones de PHP son de antes de la 1.39.3, las pasa de
  /Applications a /Library/Nexum, con sus bases de datos, proyectos,
  vhosts y certificados (en /Applications queda un enlace a cada una);
- crea la orden nexum (en la terminal) y la aplicacion «$NAME»,
  en Launchpad y en ~/Applications.
Al terminar dice «Se ha finalizado la instalacion»: el boton «Abrir
$NAME» abre la ventana, y ya puedes expulsar el disco. Si algo
falla, «Ver detalles» enseña todo lo que ha pasado (para copiarlo). Lo
que escribe el instalador queda en ~/Library/Logs/Nexum.

Tus proyectos y tus bases de datos no se tocan.

SI MACOS NO DEJA ABRIRLO
El instalador no esta firmado por Apple. La primera vez macOS dice que
no puede comprobar que no tiene software malicioso:
- macOS 14 o anterior: boton derecho sobre el instalador > Abrir > Abrir.
- macOS 15 o posterior: pulsa "Hecho", ve a Ajustes del Sistema >
  Privacidad y seguridad, baja hasta "Se ha bloqueado..." y pulsa "Abrir
  igualmente". Vuelve a abrir el instalador.

Otra forma, en Terminal (lo mismo, con las preguntas en la terminal):
  bash /Volumes/Nexum*/Instalar*.app/Contents/Resources/instalar.sh
EOF

# Firma local (sin certificado) y sin atributos de cuarentena del script descargado. Con hardened runtime
# (-o runtime): macOS no deja cargarle librerias de fuera ni que otro programa lea su memoria (la contraseña)
xattr -cr "$ROOT"
codesign --force --deep -o runtime -s - "$APP" > /dev/null 2>&1 || codesign --force --deep -s - "$APP" > /dev/null 2>&1 || true

mkdir -p "$OUT"
DMG=$OUT/nexum-mac-$VERSION.dmg
RW=$BUILD/disco-rw.dmg
# Primero en lectura y escritura, con sitio para lo que guarda Finder (.DS_Store)
SIZE_MB=$(( $(du -sm "$ROOT" | cut -f1) + 20 ))
hdiutil create -quiet -ov -volname "$VOLNAME" -srcfolder "$ROOT" -fs HFS+ -format UDRW -size "${SIZE_MB}m" "$RW"
# (montado donde Finder lo vea: sin -nobrowse. Si ya hay un disco con ese nombre, macOS le pone otro: se usa
# el que diga hdiutil)
ATTACH=$(hdiutil attach -readwrite -noverify -noautoopen "$RW")
RW_MNT=$(grep -o '/Volumes/.*$' <<< "$ATTACH" | tail -1 || true)
[ -n "$RW_MNT" ] && [ -d "$RW_MNT" ] || { echo "No se ha podido montar el disco para prepararlo: $ATTACH"; exit 1; }
DISK=$(basename "$RW_MNT")

# Icono del disco
cp "$APP/Contents/Resources/icono.icns" "$RW_MNT/.VolumeIcon.icns"
if SETFILE=$(xcrun --find SetFile 2> /dev/null) && [ -x "$SETFILE" ]; then
    "$SETFILE" -a C "$RW_MNT" || true
else
    # (lo mismo que SetFile -a C: la marca «icono propio» en la informacion de Finder de la carpeta)
    xattr -wx com.apple.FinderInfo 0000000000000000040000000000000000000000000000000000000000000000 "$RW_MNT" 2> /dev/null || true
fi

# La ventana del disco en Finder: vista de iconos, sin barras, su tamaño, el fondo y cada icono en su sitio
LAYOUT=0
if osascript - "$DISK" "$INSTALLER.app" "$BACKGROUND" "$WIN_W" "$WIN_H" "$ICON_SIZE" > "$BUILD/finder.log" 2>&1 <<'EOF'
on run argv
    set diskName to item 1 of argv
    set appName to item 2 of argv
    set bgName to item 3 of argv
    set winW to (item 4 of argv) as integer
    set winH to (item 5 of argv) as integer
    set iconSize to (item 6 of argv) as integer
    tell application "Finder"
        tell disk diskName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            -- (la barra del título no cuenta en el fondo: unos 28 puntos más de alto)
            set the bounds of container window to {200, 120, 200 + winW, 120 + winH + 28}
            set opts to the icon view options of container window
            set arrangement of opts to not arranged
            set icon size of opts to iconSize
            set text size of opts to 13
            set label position of opts to bottom
            if bgName is not "" then set background picture of opts to file (".background:" & bgName)
            set position of item appName of container window to {winW div 2, 180}
            set position of item "LEEME.txt" of container window to {winW - 84, 318}
            close
            open
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
EOF
then
    LAYOUT=1
else
    echo "Aviso: Finder no ha dejado preparar la ventana del disco (¿sin permiso de automatizacion para"
    echo "Terminal en Ajustes del Sistema > Privacidad y seguridad > Automatizacion?). El .dmg se crea"
    echo "igual, sin el fondo ni los iconos colocados:"
    sed 's/^/  /' "$BUILD/finder.log"
fi
# (lo que deja macOS al montarlo no va en el disco)
rm -rf "$RW_MNT/.fseventsd" "$RW_MNT/.Trashes" 2> /dev/null || true
sync
DETACHED=0
for _ in 1 2 3 4 5; do
    if hdiutil detach -quiet "$RW_MNT" 2> /dev/null; then
        DETACHED=1
        break
    fi
    sleep 2
done
[ $DETACHED -eq 1 ] || hdiutil detach -quiet -force "$RW_MNT"
RW_MNT=""
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG"

# Comprobacion: se monta y lleva el instalador con su ejecutable, el script del gestor y el LEEME
MNT=$(mktemp -d)
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" "$DMG"
ok=0
[ -x "$MNT/$INSTALLER.app/Contents/MacOS/instalar" ] && cmp -s "$MNT/$INSTALLER.app/Contents/Resources/lvm-instalador.sh" "$SRC" \
    && [ -x "$MNT/$INSTALLER.app/Contents/Resources/instalar.sh" ] && [ -f "$MNT/LEEME.txt" ] && ok=1
[ $ok -eq 1 ] && [ $LAYOUT -eq 1 ] && [ ! -f "$MNT/.DS_Store" ] && echo "Aviso: el disco no lleva la presentacion de la ventana (.DS_Store)."
hdiutil detach -quiet "$MNT"
rmdir "$MNT"
[ $ok -eq 1 ] || { echo "El .dmg se ha creado, pero al montarlo no esta bien el instalador: $DMG"; exit 1; }
echo "Creado y comprobado: $DMG"
[ $LAYOUT -eq 1 ] || echo "(sin la presentacion de la ventana en Finder: mira el aviso de arriba)"
