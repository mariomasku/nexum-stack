# Carpeta vinculada a <base> en <version> (sin version, la activa). Nada si no tiene
function linked_folder() {
    local db=$1 ver=${2:-$(active_name)}
    [ -f "$PROJECTS_FILE" ] || return 0
    awk -F= -v d="$db" -v k="$db@$ver" '$1 == k { v = $2; hv = 1 } $1 == d { g = $2 } END { print (hv ? v : g) }' "$PROJECTS_FILE"
}

# Base vinculada a una carpeta en <version> (sin version, la activa): la ultima que se vinculo
function saved_project_db() {
    local ver=${2:-$(active_name)}
    [ -f "$PROJECTS_FILE" ] || return 0
    awk -F= -v f="$1" -v ver="$ver" '{
        n = index($1, "@")
        if (n) { d = substr($1, 1, n - 1); if (substr($1, n + 1) != ver) next; per[d] = $2; has[d] = 1 }
        else { d = $1; all[d] = $2 }
        last[d] = NR
    } END {
        for (d in last) { v = (d in has) ? per[d] : all[d]; if (v == f && last[d] > best) { best = last[d]; db = d } }
        if (db != "") print db
    }' "$PROJECTS_FILE"
}

# remember_project <base> <carpeta> [version] [--unica]: vincula la base a la carpeta en esa version
# (sin version, la activa; sin carpeta, la desvincula). Con --unica, en esa version la carpeta deja
# de estar vinculada a otras bases (la base nueva sustituye a la anterior)
function remember_project() {
    local db=$1 folder=$2 ver=${3:-$(active_name)} key
    [ "$DRY" -eq 1 ] && return 0
    key=$db${ver:+@$ver}
    mkdir -p "$(dirname "$PROJECTS_FILE")"
    { [ -f "$PROJECTS_FILE" ] && awk -F= -v k="$key" -v d="$db" -v f="$folder" -v ver="$ver" -v u="$4" '
        $1 == k { next }
        u == "--unica" && f != "" && $2 == f && $1 != d {
            # (la de todas las versiones se queda para las demas y en esta se desvincula)
            if (index($1, "@") == 0) { print; if (ver != "") print $1 "@" ver "="; next }
            if (substr($1, index($1, "@") + 1) == ver) next
        }
        { print }' "$PROJECTS_FILE"; echo "$key=$folder"; } > "$PROJECTS_FILE.nuevo"
    mv "$PROJECTS_FILE.nuevo" "$PROJECTS_FILE"
}

