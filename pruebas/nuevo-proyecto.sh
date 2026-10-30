#!/bin/bash
# Asistente de Nuevo proyecto (Linux 1.56.13, Mac 1.40.1): el repositorio, de los de GitHub (la lista de la
# pestaña Repositorios: su direccion SSH, su carpeta y su web) o la direccion de otro; y un paso 4 para
# falsear su dominio de produccion (nuevo-dominio, despues de montarlo). Uso: nuevo-proyecto.sh <script>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
grep -qE "def new_project_repo|func npPickRepo" "$SRC" || { echo "  ok    (sin el asistente nuevo)"; exit 0; }
if grep -q "LVM_SWIFT" "$SRC"; then
    check "Mac: cuatro pasos, el ultimo el dominio de produccion" 'grep -q "\"Paso 4 de 4: dominio de producción\"" "$SRC" && grep -q "if next >= 5 {" "$SRC" && grep -q "func stepDomain() -> some View" "$SRC"'
    check "Mac: el repositorio de la lista de GitHub (la de la ultima vez), por SSH" 'grep -q "runQuick(\[\"repos\", \"--cache\"\])" "$SRC" && grep -q "npUrl = \"git@github.com:\\\\(r.full).git\"" "$SRC"'
    check "Mac: falsear su dominio despues de montarlo" 'grep -q "\[\"nuevo-dominio\", domain, folder\]" "$SRC"'
    check "Mac: la caja de la terminal, con el mismo margen arriba que abajo" 'grep -q "padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))" "$SRC" && grep -q "padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))" "$SRC"'
else
    check "Linux: cuatro pasos, el ultimo el dominio de produccion" 'grep -q "4: \"Paso 4 de 4: dominio de producción\"" "$SRC" && grep -q "        if page == 5:" "$SRC" && grep -q "w\[\"stack\"\].add_named(p4, \"4\")" "$SRC"'
    check "Linux: el repositorio de la lista de GitHub (la de la ultima vez), por SSH, al escribir parte de su nombre" 'grep -q "run_quick(\[\"repos\", \"--cache\"\], got)" "$SRC" && grep -q "w\[\"url\"\].set_text(\"git@github.com:%s.git\" % full)" "$SRC" && grep -q "Gtk.EntryCompletion(model=w\[\"repo_store\"\]" "$SRC"'
    check "Linux: falsear su dominio despues de montarlo" 'grep -q "\[\"nuevo-dominio\", domain, folder\]" "$SRC"'
    check "Linux: la caja de la terminal, con el mismo margen arriba que abajo" 'grep -q "margin: 12px 14px 12px 14px;" "$SRC" && grep -q "padding: 10px 10px 10px 10px; }" "$SRC"'
fi
exit $fail
