#!/bin/bash
# Icono junto al reloj (Linux 1.56.18, Mac 1.40.3): al cerrar la ventana, el programa sigue en el icono; su menu
# abre la ventana, arranca o para la version activa, abre web.local y sale. Se quita en Configuracion → Programa
# (fichero ventana-bandeja con «no»); sin el, cerrar la ventana cierra el programa como antes.
# Uso: bandeja.sh <lvm-instalador.sh> [empaquetar-deb.sh]
SRC=$1 DEB=${2:-} HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -qE "def nv_tray_setup|final class TrayIcon" "$SRC" || { echo "  ok    (sin el icono junto al reloj)"; exit 0; }
if grep -q "LVM_SWIFT" "$SRC"; then
    check "Mac: icono en la barra de menus, puesto si no se ha quitado (ventana-bandeja)" 'grep -q "let TRAY_FILE = LOG_DIR + \"/ventana-bandeja\"" "$SRC" && grep -q "TrayIcon.shared.show(trayWanted())" "$SRC" && grep -q "NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)" "$SRC"'
    check "Mac: su menu (abrir, estado, arrancar o parar, web.local y salir), rehecho al abrirlo" 'grep -q "func menuNeedsUpdate(_ menu: NSMenu) {" "$SRC" && grep -q "add(\"Abrir Nexum Dev Stack\", #selector(openWindow))" "$SRC" && grep -q "#selector(power), d != nil" "$SRC" && grep -q "#selector(openWeb), !link.isEmpty && running" "$SRC" && grep -q "add(\"Salir\", #selector(quit))" "$SRC"'
    check "Mac: con el icono, cerrar la ventana (o acabar una tarea sin ella) no cierra la aplicacion" 'grep -q "return !(AppModel.current?.busy ?? false) && !TrayIcon.shared.on" "$SRC" && grep -q "if task == nil && oldValue != nil && !TrayIcon.shared.on" "$SRC"'
    check "Mac: sin ventana, el menu se pone al dia cada minuto (solo gui-datos)" 'grep -q "if self.trayTicks == 0 { runQuick(\[\"gui-datos\"\])" "$SRC"'
    check "Mac: se quita o se pone en Configuracion → General → Programa" 'grep -q "generalBlock(\"Programa\"," "$SRC" && grep -q "Toggle(\"\", isOn: Binding(get: { model.trayOn }, set: { model.setTray(\$0) }))" "$SRC"'
    # Abrir al iniciar sesion (1.57.15): un LaunchAgent tuyo que abre la aplicacion con --al-iniciar
    check "Mac: «Abrir al iniciar sesion» en Programa, con su LaunchAgent (Label, 644, sin seguir enlaces)" 'grep -q "Tile(\"Abrir al iniciar sesión\"," "$SRC" && grep -q "Toggle(\"\", isOn: Binding(get: { model.loginOn }, set: { model.setLoginItem(\$0) }))" "$SRC" && grep -q "let LOGIN_LABEL = \"io.github.mariomasku.nexum.inicio\"" "$SRC" && grep -q "let LOGIN_PLIST = NSHomeDirectory() + \"/Library/LaunchAgents/\" + LOGIN_LABEL + \".plist\"" "$SRC" && grep -q "\"ProgramArguments\": \[\"/usr/bin/open\", \"-g\", \"-a\", APP_BUNDLE_PATH, \"--args\", LOGIN_ARG\]" "$SRC" && grep -q "\"RunAtLoad\": true," "$SRC" && grep -q "open(LOGIN_PLIST, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, mode_t(0o644))" "$SRC" && ! grep -q "launchctl.*LOGIN_" "$SRC"'
    check "Mac: apagarlo solo borra el nuestro (fichero normal con nuestro Label); en simulacion, nada" 'grep -q "guard loginItemOurs() else { return" "$SRC" && grep -q "return (p\[\"Label\"\] as? String) == LOGIN_LABEL" "$SRC" && grep -q "guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG" "$SRC" && grep -A2 "func setLoginItem(_ on: Bool) {" "$SRC" | grep -q "if SIMULATE {" && grep -q "\[simulación\] no se borra" "$SRC"'
    check "Mac: con --al-iniciar y el icono puesto, arranca sin ventana (solo el icono)" 'grep -q "let LOGIN_ARG = \"--al-iniciar\"" "$SRC" && grep -q "startHidden = CommandLine.arguments.contains(LOGIN_ARG) \&\& trayWanted()" "$SRC" && grep -q ".background(StartHiddenWindow())" "$SRC" && grep -q "w.orderOut(nil)" "$SRC"'
else
    check "Linux: AppIndicator (Ayatana o el de antes); sin el, como antes" 'grep -q "for name in (\"AyatanaAppIndicator3\", \"AppIndicator3\"):" "$SRC" && grep -q "if lib is None:" "$SRC"'
    check "Linux: la X esconde la ventana solo con el icono puesto" 'grep -q "self.win.connect(\"delete-event\", lambda \*_: self.nv_tray_hide())" "$SRC" && grep -A4 "    def nv_tray_hide(self):" "$SRC" | grep -q "return False"'
    check "Linux: su menu (abrir, estado, arrancar o parar, web.local y salir)" 'grep -q "add(\"open\", \"Abrir Nexum Dev Stack\", self.nv_tray_open)" "$SRC" && grep -q "add(\"power\", \"Arrancar\", self.nv_tray_power)" "$SRC" && grep -q "add(\"web\", \"Abrir web.local\", self.nv_tray_web)" "$SRC" && grep -q "add(\"quit\", \"Salir\", self.nv_tray_quit)" "$SRC"'
    check "Linux: escondida, el menu se pone al dia cada minuto (solo gui-datos)" 'grep -q "if self.tray is not None and not self.win.get_visible() and not self.busy:" "$SRC"'
    check "Linux: se quita o se pone en Configuracion → Programa (ventana-bandeja)" 'grep -q "TRAY_FILE = os.path.join(LOG_DIR, \"ventana-bandeja\")" "$SRC" && grep -q "self.nv_tray_row(lb)" "$SRC" && grep -q "sudo apt install gir1.2-ayatanaappindicator3-0.1" "$SRC"'
    [ -n "$DEB" ] && check "Linux: el paquete .deb recomienda el componente del icono" 'grep -q "^Recommends: .*gir1.2-ayatanaappindicator3-0.1" "$DEB"'
fi
exit $fail
