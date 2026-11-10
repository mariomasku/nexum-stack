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
    check "Mac: el repositorio de la lista de GitHub (la de la ultima vez), por SSH" 'grep -q "runQuick(\[\"repos\", \"--todos\"\] + (cache ? \[\"--cache\"\] : \[\]))" "$SRC" && grep -q "npUrl = \"git@github.com:\\\\(r.full).git\"" "$SRC"'
    check "Mac: Crear y falsear dice que falta (dominio, carpeta) y limpia el dominio pegado como direccion" 'grep -q "let canCreate = matches(DOMAIN_RX, domain) && !model.newFolder.isEmpty && !model.busy" "$SRC" && grep -q "Text(why).font" "$SRC" && grep -q "let domain = cleanDomain(newDomain).lowercased()" "$SRC"'
    check "Mac: el proyecto cargado lleva el interruptor de su dominio (sin .local), con el mismo cambio que Dominios y hosts" 'grep -q "ForEach(model.projectHosts(x.name), id: \\\\.name) { h in" "$SRC" && grep -q "func projectHosts(_ name: String) -> \[HostEntry\]" "$SRC" && grep -q "\$0.folder == name && !\$0.name.lowercased().hasSuffix(\".local\")" "$SRC"'
    check "Mac: el interruptor dice Falsear Host y, falseado, Host falseado; el boton Log, con su icono" 'grep -q "Text(h.fake ? \"Host falseado\" : \"Falsear Host\")" "$SRC" && grep -q ".tip(h.fake ? \"Host falseado\" : \"Falsear Host\")" "$SRC" && grep -q "name: \"Log\", icon: .logo(\"log\")" "$SRC" && ! grep -q "name: \"Log\", icon: .symbol" "$SRC"'
    check "Mac: los repositorios del buscador se cargan al abrir el programa" 'grep -q "loadNpRepos(cache: true)$" "$SRC" && grep -q "asyncAfter(deadline: .now() + 5) { \[weak self\] in self?.loadNpRepos() }" "$SRC"'
    check "Mac: boton Copiar repositorio, solo con su icono, y al pegarlo queda elegido" 'grep -q ".tip(\"Copiar repositorio\")" "$SRC" && grep -q "Image(systemName: \"doc.on.doc\")" "$SRC" && grep -q "func npRepoTyped(_ text: String)" "$SRC" && grep -q "func repoQuery(_ text: String) -> String" "$SRC"' 
    check "Mac: Dominios de los vhosts en 1/3 y Nuevo proyecto en 2/3" 'grep -q "OneThirdTwoThirds(first: {" "$SRC" && grep -q "first.frame(width: unit, alignment: .topLeading)" "$SRC" && grep -q "second.frame(width: unit \* 2, alignment: .topLeading)" "$SRC"'
    check "Mac: los falseados (tambien los .local), arriba en dos columnas, cada uno con su interruptor (1.57.11)" 'grep -qF "return hosts.filter { \$0.fake }" "$SRC" && grep -qF "return hosts.filter { !\$0.fake }" "$SRC" && grep -qF "hostsVisor(fakes(hosts))" "$SRC" && grep -qF "hostColumn(left)" "$SRC" && grep -qF "hostColumn(right)" "$SRC" && grep -qF "Text(\"DOMINIOS Y HOSTS FALSEADOS\")" "$SRC"'
    check "Mac: boton Ver fichero de hosts, solo para leerlo" 'grep -q "Label(\"Ver fichero de hosts\", systemImage: \"doc.text\")" "$SRC" && grep -q "func viewHostsFile()" "$SRC"'
    check "Mac: falsear su dominio despues de montarlo" 'grep -q "\[\"nuevo-dominio\", domain, folder\]" "$SRC"'
    check "Mac: la terminal, sin márgenes alrededor (pegada a la ventana, 1.41.1)" '! sed -n "/^struct TermPanel: View {/,/^}/p" "$SRC" | grep -q "padding(EdgeInsets"'
else
    check "Linux: los resultados, en la propia ventana (el desplegable de Gtk.EntryCompletion puede no verse en Wayland)" '! grep -q "Gtk.EntryCompletion(" "$SRC" && grep -q "w\[\"repo_hits\"\] = css(Gtk.ListBox" "$SRC" && grep -q "found = \[r for r in rows if q in r\[0\].lower()\]" "$SRC"' 
    RQ=$(python3 -c "import re
$(awk '/^def repo_query\(text\):/,/return re.sub/' "$SRC")
print(repo_query(' git@github.com:Hexer-Dev/Uno.git '), repo_query('https://github.com/a/b/'), repo_query('ssh://git@github.com/a/c.git'), repo_query('depra'))")
    check "Linux: repo_query deja dueño/repo de una direccion de GitHub y no toca lo demas" '[ "$RQ" == "hexer-dev/uno a/b a/c depra" ]' 
    check "Linux: boton Copiar repositorio, solo con su icono, con la direccion SSH" 'grep -q "tooltip_text=\"Copiar repositorio\")" "$SRC" && grep -q "cp.add(icon(\"edit-copy-symbolic\"))" "$SRC" && grep -q "set_text(\"git@github.com:%s.git\" % repo\[\"full\"\], -1)" "$SRC"' 
    check "Linux: cuatro pasos, el ultimo el dominio de produccion" 'grep -q "4: \"Paso 4 de 4: dominio de producción\"" "$SRC" && grep -q "        if page == 5:" "$SRC" && grep -q "w\[\"stack\"\].add_named(p4, \"4\")" "$SRC"'
    check "Linux: el repositorio de la lista de GitHub (la de la ultima vez), por SSH, al escribir parte de su nombre" 'grep -q "run_quick(\[\"repos\", \"--todos\"\] + (\[\"--cache\"\] if cache else \[\]), got)" "$SRC" && grep -q "w\[\"url\"\].set_text(\"git@github.com:%s.git\" % full)" "$SRC"'
    check "Linux: el boton azul (suggested-action) se ve apagado cuando no se puede pulsar" 'grep -q "button.suggested-action:disabled { background-color: alpha(%(b)s, 0.35); }" "$SRC"'
    check "Linux: Crear y falsear dice que falta (dominio, carpeta) y limpia el dominio pegado como direccion" 'grep -q "row.subtitle.set_label(why)" "$SRC" && grep -q "f.__setitem__(\"domain\", clean_domain(w.get_text()))" "$SRC"'
    CD=$(python3 -c "$(printf 'import re\n'; awk '/^def clean_domain\(text\):/,/rstrip/' "$SRC")
print(clean_domain(' https://www.mitienda.com/tienda?x=1 '), clean_domain('mitienda.com.'), clean_domain('http://a.es:8080/'))")
    check "Linux: clean_domain deja solo el nombre (sin https://, ruta, puerto ni punto final)" '[ "$CD" == "www.mitienda.com mitienda.com a.es" ]'
    check "Linux: el proyecto cargado lleva el interruptor de su dominio y sigue a /etc/hosts" 'grep -q "for h in reversed(self.project_hosts(x\[\"name\"\])):" "$SRC" && grep -q "sw.connect(\"state-set\", self.on_host_switch, h)" "$SRC" && grep -q "if self.hosts != old and getattr(self, \"nv_list\", None)" "$SRC"'
    check "Linux: el interruptor dice Falsear Host y, falseado, Host falseado; el boton Log, con su icono" 'grep -q "label(\"Host falseado\" if fake else \"Falsear Host\"" "$SRC" && grep -q "return \"Host falseado\" if h\[\"fake\"\] else \"Falsear Host\"" "$SRC" && grep -q "(\"log\", \"Log\", (\"logo\", \"log\"))" "$SRC" && ! grep -q "\"text-x-generic-symbolic\", \"Log\"" "$SRC"'
    check "Linux: los repositorios del buscador se cargan al abrir el programa" 'grep -q "self.np_repos_load(cache=True)$" "$SRC" && grep -q "GLib.timeout_add_seconds(5, lambda: (self.np_repos_load(), False)\[1\])" "$SRC"'
    check "Linux: los falseados (tambien los .local), arriba en dos columnas, cada uno con su interruptor (1.57.11)" 'grep -qF "fake = [h for h in self.hosts if h[\"fake\"]]" "$SRC" && grep -qF "rest = [h for h in self.hosts if not h[\"fake\"]]" "$SRC" && grep -qF "self.hosts_box.pack_start(self.hosts_visor(fake), False, False, 0)" "$SRC" && grep -qF "cols[n % 2].add(self.host_row(h))" "$SRC" && grep -qF "label(\"DOMINIOS Y HOSTS FALSEADOS\", \"nv-seccion\")" "$SRC"'
    check "Linux: Dominios de los vhosts en 1/3 y Nuevo proyecto en 2/3" 'grep -q "Gtk.Grid(column_spacing=18, column_homogeneous=True)" "$SRC" && grep -q "grid.attach(box, 0, 0, 1, 1)" "$SRC" && grep -q "grid.attach(new_domain, 1, 0, 2, 1)" "$SRC"'
    HV=$(python3 -c "$(awk '/^def hosts_view_text\(/,/return "\\n".join\(head\)/' "$SRC")
hs = [dict(name='a.es', folder='x', fake=True), dict(name='bb.local', folder='', fake=False)]
print(hosts_view_text(hs, '/etc/hosts', '/v.conf', '127.0.0.1 a.es'))")
    check "Linux: el visor enseña los dominios falseables, con su estado, y el fichero tal cual" 'grep -q "^#   falseado  a.es      ->  x$" <<< "$HV" && grep -q "^#   apagado   bb.local  ->  sin carpeta$" <<< "$HV" && grep -q "tienen vhost en /v.conf" <<< "$HV" && [ "$(tail -1 <<< "$HV")" == "127.0.0.1 a.es" ]'
    check "Linux: falsear su dominio despues de montarlo" 'grep -q "\[\"nuevo-dominio\", domain, folder\]" "$SRC"'
    check "Linux: la caja de la terminal, con el mismo margen arriba que abajo" 'grep -q "margin: 12px 14px 12px 14px;" "$SRC" && grep -q "padding: 10px 10px 10px 10px; }" "$SRC"'
fi
# (1.57.12) nuevo-dominio con un vhost del dominio: si lleva a esa carpeta, se usa y sigue; si lleva a otra,
# se para antes de cambiar nada. El asistente lo dice en el paso 4, antes de empezar
if grep -q 'vhost_points_to "$domain" "$folder" && echo "Ya hay un vhost para $domain que lleva a $folder: se usa"' "$SRC"; then
    (
        extract "$SRC" new_custom_domain vhost_points_to valid_domain || exit 1
        NT=$(mktemp -d); trap 'rm -rf "$NT"' EXIT
        HTDOCS_DIR=$NT/htdocs DRY=1 PROJECT_VHOST=web.local CUSTOM_DOMAINS_FILE=$NT/dominios
        mkdir -p "$HTDOCS_DIR/panaderia-luna"
        project_link() { echo web.local; }
        vhosts_info() { echo "443|panaderia-luna|panaderia-luna.com|www.panaderia-luna.com||"; echo "443||fuera.com|||"; }
        ps_vhost() { echo "PS_VHOST $*"; }
        hosts_fake() { echo "FALSEA $*"; }
        run() { echo "RUN $*"; }
        out=$(new_custom_domain panaderia-luna.com panaderia-luna 2>&1); rc=$?
        check "nuevo-dominio: el vhost del dominio ya lleva a esa carpeta: se usa y sigue (vhost, falsear)" '[ $rc -eq 0 ] && grep -q "que lleva a panaderia-luna: se usa" <<< "$out" && grep -q "^PS_VHOST panaderia-luna panaderia-luna.com" <<< "$out" && grep -q "^FALSEA cargar panaderia-luna.com" <<< "$out"'
        out=$(new_custom_domain www.panaderia-luna.com otra-luna 2>&1); rc=$?
        check "nuevo-dominio: el vhost lleva a otra carpeta: lo dice y no cambia nada" '[ $rc -ne 0 ] && grep -q "lleva a $HTDOCS_DIR/panaderia-luna, no a otra-luna" <<< "$out" && ! grep -q "PS_VHOST\|FALSEA\|RUN" <<< "$out"'
        out=$(new_custom_domain fuera.com otra-luna 2>&1); rc=$?
        check "nuevo-dominio: el vhost lleva fuera de htdocs: lo dice y no cambia nada" '[ $rc -ne 0 ] && grep -q "una carpeta de fuera de" <<< "$out" && ! grep -q "PS_VHOST" <<< "$out"'
        exit $fail
    ) || fail=1
    check "asistente: el paso 4 avisa antes de empezar si el dominio lleva a otra carpeta" 'grep -qF "Ya hay un vhost para" "$SRC" && { grep -qF "and dom in [h[\"name\"].lower()] + h[\"alias\"].lower().split()), None)" "$SRC" || grep -qF "h.folder != folder && ([h.name.lowercased()]" "$SRC"; }'
fi
exit $fail
