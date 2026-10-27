#!/bin/bash
# Ventana del Mac 1.40.0 (Swift): lo mismo que la de Linux 1.56. Actualizaciones (el primer arranque del
# día y después cada UPDATE_EVERY), botones del visor a tu gusto (el mismo fichero, los mismos botones y
# estilos que Linux), lo que gasta Nexum arriba, la página que sube al cargar un proyecto y los proyectos
# nuevos de Docker con el Apache de Docker. Uso: mac-ventana-140.sh <lvm-instalador.sh del Mac>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
LINUX=$HERE/../lvm-instalador.sh
grep -q "LVM_SWIFT" "$SRC" && grep -q "^func updateCheckDue() -> Bool {" "$SRC" || { echo "  ok    (sin la ventana 1.40 del Mac)"; exit 0; }

# Actualizaciones
check "actualizaciones: al abrir, solo si toca (y ya no se apunta la versión rechazada)" 'grep -q "if updateCheckDue() { self.checkUpdates(auto: true) }" "$SRC" && ! grep -q "declinedUpdate" "$SRC"'
check "actualizaciones: cada tantos arranques como en Linux, en el mismo fichero" '[ "$(grep -oP "^let UPDATE_EVERY = \K[0-9]+" "$SRC")" == "$(grep -oP "^UPDATE_EVERY = \K[0-9]+" "$LINUX")" ] && grep -q "\"/actualizaciones-arranques\"" "$SRC"'
# Botones del visor
mac_keys=$(grep -A2 "^let VISOR_BUTTONS:" "$SRC" | grep -oP '\("\K[a-z]+(?=", "[^"]+"\))' | tr '\n' ' ')
lin_keys=$(grep -A3 "^VISOR_BUTTONS = " "$LINUX" | grep -oP '\("\K[a-z]+(?=", "[^"]+", \()' | tr '\n' ' ')
check "botones: los mismos que en Linux y en el mismo orden ($mac_keys)" '[ -n "$mac_keys" ] && [ "$mac_keys" == "$lin_keys" ]'
check "botones: los mismos estilos y tamaños que en Linux" 'grep -q "(\"nombre\", \"Con su nombre\"), (\"icono\", \"Solo el icono (cuadrado)\")" "$SRC" && grep -q "let VISOR_SIZES: \[String: Int\] = \[\"icono\": 44, \"grande\": 88\]" "$SRC" && grep -q "^BUTTON_SIZES = {\"icono\": 44, \"grande\": 88}" "$LINUX"'
check "botones: el mismo fichero que en Linux" 'grep -q "let VISOR_FILE = LOG_DIR + \"/botones-visor\"" "$SRC"'
check "botones: los dos visores colocan sus botones con lo elegido" 'grep -q "let items = loadedItems(x, p, c)" "$SRC" && grep -q "let items = visorItems(p, g, up)" "$SRC" && [ "$(grep -c "ForEach(c.order.filter { !c.hidden.contains(\$0) && items\[\$0\] != nil }" "$SRC")" -eq 2 ]'
check "botones: Desmontar, ⋮, Versiones de PHP y Arrancar o Parar, con el mismo estilo" 'grep -q "VisorButton(conf: c, name: \"Desmontar\"" "$SRC" && grep -q "VisorButton(conf: model.visorConf, name: \"Más\"" "$SRC" && grep -q "VisorButton(conf: c, name: \"Versiones de PHP…\"" "$SRC" && grep -q "VisorButton(conf: c, name: up ? \"Parar\" : \"Arrancar\"" "$SRC"'
check "botones: sin nombre, igual de alto que de ancho" 'grep -q "\.frame(width: side, height: side)" "$SRC"'
check "botones: «Personalizar los botones…» en el menú ⋮ y en Configuración, con vista previa" 'grep -q "(\"Personalizar los botones…\", { model.panel = .buttons })" "$SRC" && grep -q "Button(\"Personalizar…\") { model.panel = .buttons }" "$SRC" && grep -q "case .buttons:" "$SRC" && grep -q "Text(\"Así quedan\")" "$SRC"'
# Lo que gasta Nexum, arriba
check "consumo: CPU y RAM en el recuadro de arriba, cada 3 s y fuera de la interfaz" 'grep -q "usageText()" "$SRC" && grep -q "Timer.scheduledTimer(withTimeInterval: 3, repeats: true)" "$SRC" && grep -q "DispatchQueue.global(qos: .utility).async" "$SRC"'
# Al cargar un proyecto
check "al cargar un proyecto, la página sube sola hasta el visor" 'grep -q "self.scrollTop += 1" "$SRC" && grep -q "WidePage(width: Swift.max(980, model.projectsTableWidth), top: model.scrollTop)" "$SRC" && grep -q "proxy.scrollTo(\"arriba\", anchor: .top)" "$SRC"'
# Docker
check "Docker: los proyectos nuevos, con el Apache de Docker (formulario y desde Proyectos)" '[ "$(grep -c "\[\"docker-nuevo\", " "$SRC")" -eq 2 ] && ! grep -q "\[\"docker-crear\", " "$SRC"'
check "Docker: la franja del Apache de Docker (Permitir, Arrancar o Parar) y su apartado en Configuración" 'grep -q "webStrip(k)" "$SRC" && grep -q "dockerCard()" "$SRC" && grep -q "model.dockerWebCommand(\"permitir\")" "$SRC"'
check "Docker: versiones de PHP y pasar los de antes" 'grep -q "\[\"docker-php-anadir\", p.slug, v\]" "$SRC" && grep -q "\[\"docker-pasar\", p.slug\]" "$SRC"'
check "Docker: XAMPP-X parado solo avisa con proyectos de antes" 'grep -q "if !k.xampp && k.projects.contains(where: { !\$0.isWeb })" "$SRC"'
exit $fail
