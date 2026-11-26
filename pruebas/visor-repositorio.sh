#!/bin/bash
# Visor del proyecto (1.57.15): el botón del repositorio (GitHub u otro), solo si la carpeta tiene un remote
# origin. La dirección se lee de .git/config (sin ejecutar git) y se pasa a su web https, sin usuario ni
# contraseña (un token en la dirección nunca se enseña). Uso: visor-repositorio.sh <lvm-instalador.sh>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-repo.XXXX") || exit 1
trap 'rm -rf "$W"' EXIT

if grep -q "LVM_SWIFT" "$SRC"; then
    check "Mac: el botón «repo» en la lista, detrás de VS Code, con el logotipo de GitHub" 'grep -qF "(\"vscode\", \"VS Code\"), (\"repo\", \"Repositorio\")," "$SRC" && grep -qF "case \"repo\": return .logo(\"github\")" "$SRC"'
    check "Mac: en el visor del cargado y en el de Docker, solo si tiene repositorio" '[ "$(grep -c "if let .*repo = projectRepoURL(" "$SRC")" -eq 2 ] && [ "$(grep -c "items\[\"repo\"\] = AnyView(VisorButton(conf: c, name: github ? \"GitHub\" : \"Repositorio\"," "$SRC")" -eq 2 ]'
    check "Mac: un botón nuevo sale detrás del que le precede, no al final" 'grep -qF "if let before = keys[..<i].last(where: { order.contains(\$0) }), let at = order.firstIndex(of: before) {" "$SRC"'
    check "Mac: el logotipo de GitHub con el color del texto (se ve en el tema oscuro)" 'grep -qF "return name == \"github\" ? Color.primary" "$SRC"'
    exit $fail
fi
check "Linux: el botón «repo» en la lista, detrás de VS Code, con el logotipo de GitHub" 'grep -qF "(\"repo\", \"Repositorio\", (\"logo\", \"github\"))," "$SRC"'
check "Linux: en el visor del cargado y en el de Docker, solo si tiene repositorio" '[ "$(grep -c "repo = repo_button(" "$SRC")" -eq 2 ] && [ "$(grep -c "btns\[\"repo\"\] = repo" "$SRC")" -eq 2 ]'

python3 -I - "$SRC" "$W" > "$W/o" 2>&1 <<'PY'
import json, os, re, sys
src, w = sys.argv[1], sys.argv[2]
text = open(src, encoding="utf-8").read()
g = {"os": os, "re": re, "json": json}
exec(re.search(r"(?ms)^def project_repo_url\(.*?\n(?=\S)", text).group(0), g)
f = g["project_repo_url"]
def repo(name, url, gitfile=False):
    d = os.path.join(w, name)
    git = os.path.join(d, ".git")
    if gitfile:
        os.makedirs(os.path.join(w, "gitdirs", name))
        os.makedirs(d)
        open(git, "w").write("gitdir: ../gitdirs/%s\n" % name)
        git = os.path.join(w, "gitdirs", name)
    else:
        os.makedirs(git)
    open(os.path.join(git, "config"), "w").write(
        '[core]\n\tbare = false\n[remote "upstream"]\n\turl = https://github.com/otra/cosa.git\n'
        '[remote "origin"]\n\turl = %s\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n' % url)
    return d
for name, url in [("https", "https://github.com/ana/panaderia-luna.git"), ("ssh", "git@github.com:ana/panaderia-luna.git"),
                  ("token", "https://x-token:ghp_SECRETO@github.com/ana/panaderia-luna"),
                  ("gitlab", "ssh://git@gitlab.com:2222/grupo/sub/tienda.git"), ("local", "/ruta/local/repo.git"),
                  ("file", "file:///tmp/repo"), ("puntos", "https://github.com/ana/../otra"), ("raro", "https://github.com/ana/x?a=<b>")]:
    print("%s=%s" % (name.upper(), f(repo(name, url))))
print("WORKTREE=%s" % (f(repo("worktree", "https://github.com/ana/arbol.git", gitfile=True)),))
os.makedirs(os.path.join(w, "singit"))
print("SINGIT=%s" % (f(os.path.join(w, "singit")),))
d = os.path.join(w, "sinorigen", ".git")
os.makedirs(d)
open(os.path.join(d, "config"), "w").write('[remote "upstream"]\n\turl = https://github.com/otra/cosa.git\n')
print("SINORIGEN=%s" % (f(os.path.dirname(d)),))
# El orden guardado de antes (sin «repo»): sale detrás de VS Code, no al final
exec(re.search(r"(?ms)^VISOR_BUTTONS = .*?\n(?=\S)", text).group(0), g)
code = re.search(r"(?ms)^def buttons_conf\(.*?\n(?=\S)", text).group(0)
g.update({"_buttons_sim": {}, "BUTTONS_FILE": os.path.join(w, "botones-visor"), "BUTTON_STYLES": [("nombre", "")],
          "BUTTON_SIZES": {"icono": 44}, "BUTTON_SIZE_MIN": 32, "BUTTON_SIZE_MAX": 128})
exec(code, g)
open(g["BUTTONS_FILE"], "w").write(json.dumps({"order": ["log", "web", "vscode", "pma"], "hidden": []}))
order = g["buttons_conf"]()["order"]
print("ORDEN=%s" % ",".join(order))
PY
check "https y ssh de GitHub: su web, sin .git" 'grep -qxF "HTTPS=('"'"'https://github.com/ana/panaderia-luna'"'"', '"'"'github.com'"'"')" "$W/o" && grep -qxF "SSH=('"'"'https://github.com/ana/panaderia-luna'"'"', '"'"'github.com'"'"')" "$W/o"' || cat "$W/o"
check "un token en la dirección no sale" 'grep -q "^TOKEN=(.https://github.com/ana/panaderia-luna.," "$W/o" && ! grep -q SECRETO "$W/o"'
check "otro servidor (GitLab, con puerto): su web" 'grep -q "^GITLAB=(.https://gitlab.com/grupo/sub/tienda., .gitlab.com.)" "$W/o"'
check "una ruta local, file://, con .. o con caracteres raros: sin botón" 'grep -qx "LOCAL=None" "$W/o" && grep -qx "FILE=None" "$W/o" && grep -qx "PUNTOS=None" "$W/o" && grep -qx "RARO=None" "$W/o"'
check "un worktree (.git es un fichero gitdir:)" 'grep -q "^WORKTREE=(.https://github.com/ana/arbol.," "$W/o"'
check "sin git o sin remote origin (aunque tenga otro): sin botón" 'grep -qx "SINGIT=None" "$W/o" && grep -qx "SINORIGEN=None" "$W/o"'
check "con el orden guardado de antes, el botón nuevo sale detrás de VS Code (y lo tuyo sigue en su orden)" 'grep -qx "ORDEN=log,actualizar,imagenes,web,vscode,repo,pma,panel,docker,compartir,unlink,correo,terminal" "$W/o"'
exit $fail
