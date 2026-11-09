function github_conf() {
    local v="" p ok=""
    [ -f "$GITHUB_CONF_FILE" ] && v=$(sed -n "s/^$1=//p" "$GITHUB_CONF_FILE" | head -1)
    case $1 in
        CUENTA) [[ "$v" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$ ]] || v="" ;;
        ORIGEN) [[ "$v" =~ ^(llavero|gh)$ ]] || v="" ;;
        PREFIJOS)
            grep -q '^PREFIJOS=' "$GITHUB_CONF_FILE" 2> /dev/null || v=$GITHUB_DEFAULT_PREFIXES
            for p in $v; do [[ "$p" =~ ^[A-Za-z0-9._-]{1,50}$ ]] && ok+=" $p"; done
            v=${ok# } ;;
    esac
    echo "$v"
}

# github_conf_set <clave> <valor>
function github_conf_set() {
    local tmp
    mkdir -p -m 700 "$(dirname "$GITHUB_CONF_FILE")" || return 1
    tmp=$(mktemp "$GITHUB_CONF_FILE.XXXXXX") || return 1
    { grep -v "^$1=" "$GITHUB_CONF_FILE" 2> /dev/null; printf '%s=%s\n' "$1" "$2"; } > "$tmp" && chmod 600 "$tmp" \
        && mv -f "$tmp" "$GITHUB_CONF_FILE"
}

