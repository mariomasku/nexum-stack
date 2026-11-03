#!/bin/bash
# Asistente de Nuevo proyecto (Linux 1.56.13, Mac 1.40.1): el repositorio, de los de GitHub (la lista de la
# pestaña Repositorios: su direccion SSH, su carpeta y su web) o la direccion de otro; y un paso 4 para
# falsear su dominio de produccion (nuevo-dominio, despues de montarlo). Uso: nuevo-proyecto.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -qE "def new_project_repo|func npPickRepo" "$SRC" || { echo "  ok    (sin el asistente nuevo)"; exit 0; }
check "WordPress: wp-config.php se prepara despues de importar su BBDD (al cargarlo aun no existia)" 'grep -q "if \[ -n \"\$file\" \] && { is_prestashop \"\$folder\" || is_wordpress \"\$folder\"; }; then" "$SRC"'
check "WordPress: si le faltan WP_SITEURL y WP_HOME no se da por bueno (se le ponen al cargar)" 'grep -q "&& wp_config_has_url \"\$file\" \"\$url\"; then" "$SRC" && grep -q "no lleva WP_SITEURL y WP_HOME en \$url" "$SRC"'
eval "$(awk '/^function wp_config_has_url\(\)/,/^}$/' "$SRC")"
WPT=$(mktemp -d)
printf "<?php\ndefine('WP_SITEURL', 'https://web.local');\ndefine( \"WP_HOME\", \"https://web.local/\" );\n" > "$WPT/bien.php"
printf "<?php\ndefine('WP_SITEURL', 'https://web.local');\n// define('WP_HOME', 'https://web.local');\n" > "$WPT/comentada.php"
printf "<?php\ndefine('WP_SITEURL', 'https://kitoli.es');\ndefine('WP_HOME', 'https://kitoli.es');\n" > "$WPT/produccion.php"
check "WordPress: wp_config_has_url acepta las dos con la direccion local (comillas dobles, barra final)" 'wp_config_has_url "$WPT/bien.php" https://web.local'
check "WordPress: wp_config_has_url no acepta una comentada ni las de produccion" '! wp_config_has_url "$WPT/comentada.php" https://web.local && ! wp_config_has_url "$WPT/produccion.php" https://web.local && ! wp_config_has_url "$WPT/no-esta.php" https://web.local'
rm -rf "$WPT"
if grep -q "LVM_SWIFT" "$SRC"; then
    check "Mac: cuatro pasos, el ultimo el dominio de produccion" 'grep -q "\"Paso 4 de 4: dominio de producción\"" "$SRC" && grep -q "if next >= 5 {" "$SRC" && grep -q "func stepDomain() -> some View" "$SRC"'
    check "Mac: el repositorio de la lista de GitHub (la de la ultima vez), por SSH" 'grep -q "runQuick(\[\"repos\", \"--cache\"\])" "$SRC" && grep -q "npUrl = \"git@github.com:\\\\(r.full).git\"" "$SRC"'
    check "Mac: Crear y falsear dice que falta (dominio, carpeta) y limpia el dominio pegado como direccion" 'grep -q "let canCreate = matches(DOMAIN_RX, domain) && !model.newFolder.isEmpty && !model.busy" "$SRC" && grep -q "Text(why).font" "$SRC" && grep -q "let domain = cleanDomain(newDomain).lowercased()" "$SRC"'
    check "Mac: falsear su dominio despues de montarlo" 'grep -q "\[\"nuevo-dominio\", domain, folder\]" "$SRC"'
    check "Mac: la caja de la terminal, con el mismo margen arriba que abajo" 'grep -q "padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))" "$SRC" && grep -q "padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))" "$SRC"'
else
    check "Linux: la lista de repositorios enseña su nombre (set_text_column: con text_column al crearla sale vacia)" 'grep -q "comp.set_text_column(0)" "$SRC" && ! grep -q "Gtk.EntryCompletion(model=w\[\"repo_store\"\], text_column=0" "$SRC"'
    check "Linux: cuatro pasos, el ultimo el dominio de produccion" 'grep -q "4: \"Paso 4 de 4: dominio de producción\"" "$SRC" && grep -q "        if page == 5:" "$SRC" && grep -q "w\[\"stack\"\].add_named(p4, \"4\")" "$SRC"'
    check "Linux: el repositorio de la lista de GitHub (la de la ultima vez), por SSH, al escribir parte de su nombre" 'grep -q "run_quick(\[\"repos\", \"--cache\"\], got)" "$SRC" && grep -q "w\[\"url\"\].set_text(\"git@github.com:%s.git\" % full)" "$SRC" && grep -q "Gtk.EntryCompletion(model=w\[\"repo_store\"\]" "$SRC"'
    check "Linux: el boton azul (suggested-action) se ve apagado cuando no se puede pulsar" 'grep -q "button.suggested-action:disabled { background-color: alpha(%(b)s, 0.35); }" "$SRC"'
    check "Linux: Crear y falsear dice que falta (dominio, carpeta) y limpia el dominio pegado como direccion" 'grep -q "row.subtitle.set_label(why)" "$SRC" && grep -q "f.__setitem__(\"domain\", clean_domain(w.get_text()))" "$SRC"'
    CD=$(python3 -c "$(printf 'import re\n'; awk '/^def clean_domain\(text\):/,/rstrip/' "$SRC")
print(clean_domain(' https://www.mitienda.com/tienda?x=1 '), clean_domain('mitienda.com.'), clean_domain('http://a.es:8080/'))")
    check "Linux: clean_domain deja solo el nombre (sin https://, ruta, puerto ni punto final)" '[ "$CD" == "www.mitienda.com mitienda.com a.es" ]'
    check "Linux: falsear su dominio despues de montarlo" 'grep -q "\[\"nuevo-dominio\", domain, folder\]" "$SRC"'
    check "Linux: la caja de la terminal, con el mismo margen arriba que abajo" 'grep -q "margin: 12px 14px 12px 14px;" "$SRC" && grep -q "padding: 10px 10px 10px 10px; }" "$SRC"'
fi
exit $fail
