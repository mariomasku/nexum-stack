#!/bin/bash
# Pruebas del instalador del .dmg del Mac (1.57.15), sin root, sin red y sin un Mac: el script en modo
# instalador (LVM_INSTALADOR=1) escribe sus pasos (NEXUM-PASO|<porcentaje>|<texto>) y la pregunta de Homebrew
# (NEXUM-PREGUNTA|homebrew|<texto>, con la respuesta por la entrada); sin la variable, nada de eso.
#   - instalar-gestor con --simular, de verdad, en una copia del script con las herramientas de Apple, Homebrew
#     y sudo de mentira (en la carpeta temporal) y uname diciendo Darwin/arm64: llega a 100, sin bajar
#   - Homebrew: «no» para sin instalar nada; «sí» pide antes la contraseña (sudo -v) y lo instala con
#     NONINTERACTIVE=1 (sin pedir Intro)
#   - gestor_migrate (migrar --ventana) acaba en 100 y, desde el instalador, no abre la ventana
#   - el instalador (macos/instalador.swift) y empaquetar-dmg.sh: lo que tienen que llevar
# Uso: mac-instalador.sh <macos/lvm-instalador.sh> [macos/empaquetar-dmg.sh] [macos/instalador.swift]
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
DMG=${2:-$(dirname "$SRC")/empaquetar-dmg.sh}
SWIFT=${3:-$(dirname "$SRC")/instalador.swift}
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-macinst.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT
if ! grep -q '^function boot_step() {' "$SRC"; then
    echo "  ok    (este script del Mac aun no tiene el instalador con barra del .dmg)"
    exit 0
fi

# --- Las marcas ---
extract "$SRC" boot_step boot_installer || exit 1
check "boot_step: con LVM_INSTALADOR=1, la marca" '[ "$(LVM_INSTALADOR=1 boot_step 45 "Copiando algo")" = "NEXUM-PASO|45|Copiando algo" ]'
check "boot_step: sin la variable (o con otro valor), nada" '[ -z "$(boot_step 45 x)" ] && [ -z "$(LVM_INSTALADOR=0 boot_step 45 x)" ] && [ -z "$(LVM_INSTALADOR=si boot_step 45 x)" ]'
check "boot_step: con BOOT_NO_STEPS (el gestor al volver a arrancar), nada" '[ -z "$(LVM_INSTALADOR=1 BOOT_NO_STEPS=1 boot_step 45 x)" ]'
check "boot_step: siempre devuelve 0 (no corta un && ni set -e)" 'boot_step 1 x && LVM_INSTALADOR=1 boot_step 1 x > /dev/null'
BOOT=$(awk '/^# Arranque: macOS trae bash 3.2/ {p = 1} p {print} /^# Desde aqui, bash moderno/ {exit}' "$SRC")
check "arranque: boot_step y boot_installer, en el arranque (bash 3.2)" 'grep -q "^function boot_step() {" <<< "$BOOT" && grep -q "^function boot_installer() {" <<< "$BOOT"'
check "arranque: el gestor al volver a arrancar no repite los pasos (BOOT_NO_STEPS=1 boot_prereqs)" 'grep -q "^        BOOT_NO_STEPS=1 boot_prereqs$" <<< "$BOOT"'
check "boot_clean_exec deja pasar LVM_INSTALADOR (las LVM_*) y SUDO_PROMPT" 'sed -n "/^function boot_clean_exec() {/,/^}/p" "$SRC" | grep -q "LVM_\*) ;;" && sed -n "/^function boot_clean_exec() {/,/^}/p" "$SRC" | grep -q "SUDO_PROMPT"'
check "LVM_INSTALADOR no esta entre las variables de prueba que se borran" '! sed -n "/^    unset LVM_HTDOCS/,/LVM_DNS_RESOLVER$/p" "$SRC" | grep -q LVM_INSTALADOR'

# --- instalar-gestor con --simular, de verdad, en una copia con lo de Apple y Homebrew de mentira ---
mkdir -p "$W/bin" "$W/brew/bin" "$W/home" "$W/sinbrew/bin"
printf '#!/bin/sh\n[ "$1" = -p ] && echo /Library/Developer/CommandLineTools && exit 0\necho "xcode-select $*" >> "%s/log"\nexit 1\n' "$W" > "$W/bin/xcode-select"
printf '#!/bin/sh\necho "brew $*" >> "%s/log"\nexit 0\n' "$W" > "$W/brew/bin/brew"
cp "$W/brew/bin/brew" "$W/brew/bin/whiptail"
printf '#!/bin/sh\necho "sudo $*" >> "%s/log"\nexit 0\n' "$W" > "$W/bin/sudo"
# (curl de mentira: el install.sh de Homebrew, que apunta su entorno y deja un brew)
cat > "$W/bin/curl" << EOF
#!/bin/sh
echo "curl \$*" >> "$W/log"
cat << 'X'
echo "install.sh NONINTERACTIVE=\$NONINTERACTIVE" >> "$W/log"
mkdir -p "$W/sinbrew/bin" && cp "$W/brew/bin/brew" "$W/sinbrew/bin/brew"
X
EOF
chmod +x "$W"/bin/* "$W"/brew/bin/*
copy() {
    sed -e "s#/usr/bin/xcode-select#$W/bin/xcode-select#g" -e "s#^BREW=/opt/homebrew/bin/brew\$#BREW=$1/bin/brew#" \
        -e "s#/opt/homebrew/bin/whiptail#$1/bin/whiptail#g" -e "s#/usr/bin/sudo #$W/bin/sudo #g" \
        -e "s#/usr/bin/curl -q --proto =https --proto-redir =https -fsSL https://raw.githubusercontent.com/Homebrew#$W/bin/curl https://raw.githubusercontent.com/Homebrew#" \
        "$SRC" > "$2"
}
copy "$W/brew" "$W/con-brew.sh"
copy "$W/sinbrew" "$W/sin-brew.sh"
check "la copia de prueba lleva lo de mentira (y no el de verdad)" 'grep -q "^BREW=$W/brew/bin/brew$" "$W/con-brew.sh" && ! grep -q "/usr/bin/xcode-select" "$W/con-brew.sh" && ! grep -q "/usr/bin/sudo -v" "$W/sin-brew.sh"'
# (Darwin y arm64: uname, una funcion exportada; el arranque no lo llama por su ruta)
uname() { case "$1" in -s) echo Darwin ;; -m) echo arm64 ;; *) command uname "$@" ;; esac; }
export -f uname
run() { local f=$1; shift; ( cd "$W" && env -u LVM_PRUEBA HOME="$W/home" "$@" bash "$f" --simular instalar-gestor ); }

out=$(run "$W/con-brew.sh" LVM_INSTALADOR=1 < /dev/null 2>&1); rc=$?
steps=$(grep '^NEXUM-PASO|' <<< "$out")
check "simulacion: termina bien" '[ $rc -eq 0 ]'
check "simulacion: escribe los pasos (herramientas de Xcode, Homebrew, version, bash, copiar)" 'grep -q "^NEXUM-PASO|[0-9]*|Comprobando las herramientas de Xcode$" <<< "$steps" && grep -q "^NEXUM-PASO|[0-9]*|Comprobando Homebrew$" <<< "$steps" && grep -q "bash del gestor" <<< "$steps" && grep -q "/Library/Nexum/gestor" <<< "$steps" && [ "$(wc -l <<< "$steps")" -ge 5 ]'
check "simulacion: llega a 100, y es lo ultimo" '[ "$(tail -1 <<< "$steps" | cut -d"|" -f2)" = 100 ] && grep -q "no se ha cambiado nada" <<< "$(tail -1 <<< "$steps")"'
check "simulacion: el porcentaje no baja nunca y siempre es un numero de 0 a 100" 'prev=-1; okp=1; while IFS="|" read -r _ p _; do case $p in ""|*[!0-9]*) okp=0 ;; *) [ "$p" -ge "$prev" ] && [ "$p" -le 100 ] || okp=0; prev=$p ;; esac; done <<< "$steps"; [ $okp -eq 1 ]'
check "simulacion: cada marca, una linea entera (NEXUM-PASO|n|texto)" '! grep "NEXUM-" <<< "$out" | grep -qvE "^NEXUM-PASO\|[0-9]{1,3}\|[^|]+$"'
check "simulacion: no pide la contraseña ni instala nada" '! grep -q "^sudo\|^brew\|^curl" "$W/log" 2> /dev/null'
out2=$(run "$W/con-brew.sh" < /dev/null 2>&1); rc2=$?
check "sin LVM_INSTALADOR: ninguna marca, y lo mismo de siempre" '[ $rc2 -eq 0 ] && ! grep -q "NEXUM-" <<< "$out2" && grep -q "\[simulacion\] se instalaria la" <<< "$out2" && [ "$(grep -v "^NEXUM-" <<< "$out")" = "$out2" ]'

# --- Homebrew: la pregunta, en el instalador ---
rm -f "$W/log"
out=$(printf 'n\n' | run "$W/sin-brew.sh" LVM_INSTALADOR=1 2>&1); rc=$?
check "Homebrew: sin el, la pregunta del instalador (una linea NEXUM-PREGUNTA|homebrew|...)" 'grep -q "^NEXUM-PREGUNTA|homebrew|.*Homebrew.*¿Instalarlo ahora?" <<< "$out" && [ "$(grep -c "^NEXUM-PREGUNTA|" <<< "$out")" = 1 ]'
check "Homebrew: con «n», se para sin pedir la contraseña ni instalar nada" '[ $rc -ne 0 ] && ! grep -q "NEXUM-PASO|100|" <<< "$out" && ! grep -q "^sudo\|^curl\|^install.sh" "$W/log" 2> /dev/null && grep -q "Sin Homebrew no se puede instalar" <<< "$out"'
check "Homebrew: en el instalador, sin la pregunta de Terminal ([s/N])" '! grep -q "\[s/N\]" <<< "$out"'
rm -f "$W/log"
out=$(printf 's\n' | run "$W/sin-brew.sh" LVM_INSTALADOR=1 2>&1); rc=$?
check "Homebrew: con «s», sigue hasta 100" '[ $rc -eq 0 ] && [ "$(grep "^NEXUM-PASO|" <<< "$out" | tail -1 | cut -d"|" -f2)" = 100 ] && [ -x "$W/sinbrew/bin/brew" ]'
check "Homebrew: antes, la contraseña (sudo -v: su instalador usa sudo -n sin preguntas)" '[ "$(head -1 "$W/log")" = "sudo -v" ] && grep -n "^curl\|^install.sh" "$W/log" | head -1 | grep -q "^2:"'
check "Homebrew: su install.sh, de GitHub por https y con NONINTERACTIVE=1 (sin pedir Intro)" 'grep -qx "curl https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "$W/log" && grep -qx "install.sh NONINTERACTIVE=1" "$W/log"'
check "Homebrew: pasos de la contraseña y de la instalacion, en orden" 'grep "^NEXUM-PASO|" <<< "$out" | grep -n "Homebrew" | tail -2 | grep -q "Instalando Homebrew" && grep -q "^NEXUM-PASO|[0-9]*|Esperando la contraseña de administrador (para Homebrew)$" <<< "$out"'
rm -rf "$W/sinbrew/bin/brew" "$W/log"
out=$(printf 'n\n' | run "$W/sin-brew.sh" 2>&1); rc=$?
check "Homebrew: sin el instalador ni terminal, como siempre (sin marcas, sin leer la respuesta)" '[ $rc -ne 0 ] && grep -q "^ERROR|Hace falta Homebrew" <<< "$out" && ! grep -q "NEXUM-" <<< "$out" && [ ! -e "$W/log" ]'

# --- La misma version ya instalada (boot_install_self) y migrar --ventana (gestor_migrate) ---
extract "$SRC" boot_install_self gestor_migrate || exit 1
boot_version_of() { echo 1.57.15; }
boot_version_gt() { return 1; }
boot_bash_ok() { return 0; }
echo x > "$W/a.sh"; cp "$W/a.sh" "$W/b.sh"
out=$(BOOT_ME=$W/a.sh TRUSTED_SCRIPT=$W/b.sh LVM_INSTALADOR=1 boot_install_self); rc=$?
check "misma version instalada: lo dice («ya estaba instalada») y sigue" '[ $rc -eq 0 ] && grep -q "^NEXUM-PASO|75|La 1.57.15 ya estaba instalada" <<< "$out"'
boot_version_gt() { return 0; }
out=$(BOOT_ME=$W/a.sh TRUSTED_SCRIPT=$W/b.sh LVM_INSTALADOR=1 boot_install_self); rc=$?
check "una mas nueva instalada: «ya estaba instalada», no se cambia y sigue" '[ $rc -eq 0 ] && grep -q "^NEXUM-PASO|75|Ya estaba instalada la 1.57.15, más nueva" <<< "$out"'
stacks_migrate() { return 0; }
retire_old_copies() { :; }
point_commands() { :; }
migrate_old_app() { :; }
open_window() { echo "abre la ventana"; }
update_app() { :; }
legacy_dirs() { :; }
TEST_DIR=$W DRY=0 APP_NAME="Nexum Dev Stack"
out=$(LVM_INSTALADOR=1 gestor_migrate --ventana); rc=$?
check "migrar --ventana: pasos (versiones, orden nexum, aplicacion) y 100 al final" '[ $rc -eq 0 ] && [ "$(grep "^NEXUM-PASO|" <<< "$out" | tail -1)" = "NEXUM-PASO|100|Se ha finalizado la instalación" ] && grep -q "^NEXUM-PASO|[0-9]*|Creando la orden nexum$" <<< "$out" && grep -q "aplicación «Nexum Dev Stack»" <<< "$out"'
stacks_migrate() { return 1; }
out=$(LVM_INSTALADOR=1 gestor_migrate --ventana); rc=$?
check "migrar --ventana: si algo falla, sin 100 (el instalador da el error)" '[ $rc -ne 0 ] && ! grep -q "^NEXUM-PASO|100|" <<< "$out"'
stacks_migrate() { return 0; }
out=$(gestor_migrate --ventana); rc=$?
check "migrar --ventana: sin el instalador, sin marcas" '[ $rc -eq 0 ] && ! grep -q "NEXUM-" <<< "$out"'
check "open_window: desde el instalador, la ventana no se abre sola (la abre su boton)" 'sed -n "/^function open_window() {/,/^}/p" "$SRC" | grep -B30 "open \"\$APP_BUNDLE\"" | grep -q "^    boot_installer && return 0$"'

# --- El instalador (Swift) y el .dmg ---
if [ -f "$SWIFT" ]; then
    check "instalador: ejecuta instalar-gestor del disco con LVM_INSTALADOR=1 (y --simular)" 'grep -q "env\[\"LVM_INSTALADOR\"\] = \"1\"" "$SWIFT" && grep -q "SCRIPT\] + (SIMULATE ? \[\"--simular\"\] : \[\]) + \[\"instalar-gestor\"\]" "$SWIFT" && grep -q "let SCRIPT = RES_DIR + \"/lvm-instalador.sh\"" "$SWIFT"'
    check "instalador: en una pseudoterminal exclusiva (script y TIOCEXCL), con la marca de fin" 'grep -q "URL(fileURLWithPath: \"/usr/bin/script\")" "$SWIFT" && grep -q "termios.TIOCEXCL" "$SWIFT" && grep -q "@@LVM-FIN-\$LVM_FIN" "$SWIFT"'
    check "instalador: la contraseña, con la marca de sudo al azar y solo si la pide un sudo de root suyo" 'grep -q "env\[\"SUDO_PROMPT\"\] = SUDO_MARK" "$SWIFT" && grep -q "^let SUDO_MARK = \"@@LVM-SUDO-\\\\(RUN_TOKEN)@@\"$" "$SWIFT" && grep -q "guard sudoAsking() else" "$SWIFT" && grep -q "guard !finished, sudoAsking() else" "$SWIFT" && grep -q "f\[2\] == \"0\" && (path == \"sudo\" || path == \"/usr/bin/sudo\")" "$SWIFT" && grep -q "NSSecureTextField" "$SWIFT"'
    check "instalador: el entorno, solo el de la lista (sin BASH_ENV, DYLD_* ni las LVM_* de fuera)" 'sed -n "/private func scriptEnv()/,/^    }/p" "$SWIFT" | grep -q "keep.contains(k) || k.hasPrefix(\"LC_\")" && ! sed -n "/private func scriptEnv()/,/^    }/p" "$SWIFT" | grep -v "^ *//" | grep -q "BASH_ENV\|DYLD\|hasPrefix(\"LVM_\")"'
    check "instalador: lee NEXUM-PASO y NEXUM-PREGUNTA (Homebrew, responde s o n)" 'grep -q "hasPrefix(\"NEXUM-PASO|\")" "$SWIFT" && grep -q "hasPrefix(\"NEXUM-PREGUNTA|\")" "$SWIFT" && grep -q "guard id == \"homebrew\" else" "$SWIFT" && grep -q "(yes ? \"s\\\\n\" : \"n\\\\n\")" "$SWIFT"'
    check "instalador: espera a las herramientas de Xcode (xcode-select --install, cada 5 s, una hora como mucho)" 'grep -q "p.arguments = \[\"--install\"\]" "$SWIFT" && grep -q "withTimeInterval: 5, repeats: true" "$SWIFT" && grep -q "^let TOOLS_WAIT_MAX: TimeInterval = 60 \* 60$" "$SWIFT"'
    check "instalador: al acabar, «Se ha finalizado la instalación», Abrir y expulsar el disco" 'grep -q "\"Se ha finalizado la instalación\"" "$SWIFT" && grep -q "mainButton.title = \"Abrir \" + APP_NAME" "$SWIFT" && grep -q "Ya puedes expulsar el disco" "$SWIFT"'
    check "instalador: si falla, Ver detalles y Copiar; el registro en ~/Library/Logs/Nexum (600, sin enlaces)" 'grep -q "\"Ver detalles\"" "$SWIFT" && grep -q "addButton(withTitle: \"Copiar\")" "$SWIFT" && grep -q "/Library/Logs/Nexum\"" "$SWIFT" && grep -q "O_NOFOLLOW, mode_t(0o600)" "$SWIFT"'
    check "instalador: cerrar a medias pregunta antes de cortar" 'grep -q "func windowShouldClose" "$SWIFT" && grep -q "¿Cancelar la instalación?" "$SWIFT" && grep -q "func applicationShouldTerminate(" "$SWIFT"'
    check "instalador: sin nombres de empresa" '! grep -qiE "hexer|dob-|mskdev|\bmsk\b" "$SWIFT"'
fi
if [ -f "$DMG" ]; then
    check ".dmg: compila el instalador con swiftc (arm64, macOS 12) y falla claro sin swiftc" 'grep -q "\"\$SWIFTC\" -O -target arm64-apple-macos12.0 -o \"\$APP/Contents/MacOS/instalar\" \"\$BUILD/main.swift\"" "$DMG" && grep -q "Hace falta swiftc para compilar el instalador" "$DMG" && grep -q "LSMinimumSystemVersion</key><string>12.0" "$DMG"'
    check ".dmg: sigue con lvm-instalador.sh, icono.icns e instalar.sh (Terminal)" 'grep -q "install -m 755 \"\$SRC\" \"\$APP/Contents/Resources/lvm-instalador.sh\"" "$DMG" && grep -q "Resources/icono.icns" "$DMG" && grep -q "^cat > \"\$APP/Contents/Resources/instalar.sh\" <<.EOF.$" "$DMG"'
    check ".dmg: en lectura y escritura, la ventana con Finder (con aviso si no deja) y luego UDZO" 'grep -q -- "-format UDRW" "$DMG" && grep -q "^if osascript - " "$DMG" && grep -q "Finder no ha dejado preparar la ventana" "$DMG" && grep -q -- "hdiutil convert -quiet \"\$RW\" -format UDZO" "$DMG" && grep -q "toolbar visible of container window to false" "$DMG" && grep -q "statusbar visible of container window to false" "$DMG"'
    check ".dmg: fondo (1x y 2x), icono del disco y comprobacion final montandolo" 'grep -q "fondo@2x.png" "$DMG" && grep -q "tiffutil -cathidpicheck" "$DMG" && grep -q "Doble clic para instalar" "$DMG" && grep -q ".VolumeIcon.icns" "$DMG" && grep -q "Creado y comprobado" "$DMG" && grep -q "cmp -s \"\$MNT/\$INSTALLER.app/Contents/Resources/lvm-instalador.sh\" \"\$SRC\"" "$DMG"'
    check ".dmg: bash lo entiende" 'bash -n "$DMG"'
    PUB=$(dirname "$DMG")/../publicar.sh
    [ -f "$PUB" ] && check "publicar.sh: el instalador.swift va en el .zip del Mac (empaquetar-dmg.sh lo necesita)" 'grep -q "empaquetar-dmg.sh instalador.swift" "$PUB"'
fi
exit $fail
