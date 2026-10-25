#!/bin/bash
# Pruebas de Buscar actualizaciones del Mac (1.38.0): la version de Mac mas nueva de las publicaciones
# de GitHub (MAC_RELEASE_PY, con JSON inventado), la firma (update_signed) con claves de prueba, la
# descarga (github_update, con un curl de mentira: sin red) y actualizar-gestor (install_update).
# Uso: mac-actualizar.sh <lvm-instalador.sh del Mac>
SRC=$1 HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/comun.sh"
W=$(mktemp -d "$TMPBASE/w-macact.XXXX"); trap 'rm -rf "$W"' EXIT
if ! grep -q '^function install_update() {' "$SRC"; then
    echo "  ok    (este script del Mac aun no actualiza desde GitHub)"
    exit 0
fi
# Lo del Mac que no hay en Linux: stat -f %m, date -r <segundos> y shasum
stat() { if [ "$1" = -f ] && [ "$2" = %m ]; then command stat -c %Y "$3"; else command stat "$@"; fi; }
date() { if [ "$1" = -r ]; then command date -d "@$2" "${@:3}"; else command date "$@"; fi; }
shasum() { shift 2; sha256sum "$@"; }

# Claves de prueba (la de verdad no se usa nunca)
for k in gpg gpg2; do
    mkdir -m 700 "$W/$k"
    gpg --homedir "$W/$k" --batch --passphrase '' --quick-generate-key "Prueba $k <$k@prueba.local>" ed25519 sign 0 2> /dev/null \
        || { echo "no se ha podido crear la clave de prueba"; exit 1; }
done
FPR=$(gpg --homedir "$W/gpg" --with-colons --list-keys 2> /dev/null | awk -F: '/^fpr/ { print $10; exit }')
sign() { gpg --homedir "$W/${2:-gpg}" --batch --yes --detach-sign -o "$1.sig" "$1" 2> /dev/null; }
# mkzip <zip> <version del script> [extra]: extra = enlace (el script es un enlace), sin (sin script),
# roto (script con un error de sintaxis), dos (dos lvm-instalador.sh)
mkzip() {
    python3 -I -W ignore - "$@" <<'EOF'
import sys, zipfile
dst, v = sys.argv[1:3]
extra = sys.argv[3] if len(sys.argv) > 3 else ""
script = '#!/bin/bash\nAPP_VERSION="%s"\necho nueva\n' % v
if extra == "roto":
    script += "if then\n"
with zipfile.ZipFile(dst, "w") as z:
    z.writestr("README.md", "leeme\n")
    if extra == "sin":
        pass
    elif extra == "enlace":
        i = zipfile.ZipInfo("lvm-instalador.sh")
        i.external_attr = 0o120777 << 16
        z.writestr(i, "/etc/passwd")
    else:
        z.writestr("lvm-instalador.sh", script)
        if extra == "dos":
            z.writestr("lvm-instalador.sh", script)
EOF
}

extract "$SRC" mac_version_gt update_signed github_update install_update gui_package || exit 1
UPDATE_KEY_FPR=$FPR UPDATE_KEY_B64=$(gpg --homedir "$W/gpg" --export "$FPR" 2> /dev/null | base64 -w 76)
GPGV=$(command -v gpgv) APP_VERSION=1.37.0 DRY=0 UPDATE_REPO=o/r UPDATES_DIR=$W/act HOME=$W/home
mkdir -p "$HOME/Downloads"
eval "$(sed -n "/^MAC_RELEASE_PY='/,/^'\$/p" "$SRC")"
# (desde la 1.39.3 la firma la comprueba el gestor, sin gpgv: UPDATE_VERIFY_PY)
eval "$(sed -n "/^UPDATE_VERIFY_PY='/,/^'\$/p; /^UPDATE_EXTRACT_PY='/,/^'\$/p" "$SRC")"
NEW_VERIFY=0; [ -n "$UPDATE_VERIFY_PY" ] && NEW_VERIFY=1

# --- Versiones
check "version: 1.37.1 es mas nueva que 1.37.0" 'mac_version_gt 1.37.1 1.37.0'
check "version: 1.40.0 es mas nueva que 1.37.10" 'mac_version_gt 1.40.0 1.37.10'
check "version: 1.37.10 es mas nueva que 1.37.9 (no por orden de letras)" 'mac_version_gt 1.37.10 1.37.9'
check "version: la misma no es mas nueva" '! mac_version_gt 1.37.0 1.37.0'
check "version: una rara no vale" '! mac_version_gt "1.38;x" 1.37.0'

# --- MAC_RELEASE_PY: la version de Mac mas nueva de todas las publicaciones
rel() {  # rel <esperado|no> <descripcion> <cambio en python sobre rels>
    local out json rc
    json=$(python3 -I -c '
import json, sys
def r(tag, mac=None, when="2026-10-23T10:00:00Z"):
    u = "https://github.com/o/r/releases/download/%s/" % tag
    names = ["lvm-instalador_%s_all.deb" % tag[1:], "lvm-instalador_%s_all.deb.sig" % tag[1:]]
    if mac:
        names += ["lvm-instalador-mac-%s.zip" % mac, "lvm-instalador-mac-%s.zip.sig" % mac]
    return {"tag_name": tag, "published_at": when, "draft": False, "prerelease": False,
            "assets": [{"name": n, "browser_download_url": u + n} for n in names]}
rels = [r("v1.52.0"), r("v1.51.0", "1.38.0"), r("v1.50.2", "1.37.9")]
exec(sys.argv[1])
print(json.dumps(rels))' "$3")
    out=$(python3 -I -c "$MAC_RELEASE_PY" o/r <<< "$json"); rc=$?
    if [ "$1" = no ]; then
        [ $rc -ne 0 ] && ok "GitHub rechaza: $2" || bad "GitHub acepta: $2 ($out)"
    else
        [ $rc -eq 0 ] && [ "${out%%|*}" = "$1" ] && ok "GitHub: $2" || bad "GitHub: $2 ($out)"
    fi
}
rel 1.38.0 "la de Mac mas nueva, aunque la ultima publicacion no traiga la de Mac" "pass"
rel 1.38.0 "la mas nueva aunque venga despues en la lista" "rels.reverse()"
rel 1.37.9 "sin la firma del .zip, se salta esa" "rels[1]['assets'].pop()"
rel 1.37.9 "de otro repositorio, se salta" "rels[1]['assets'][2]['browser_download_url'] = rels[1]['assets'][2]['browser_download_url'].replace('/o/r/', '/o/x/')"
rel 1.37.9 "version de prueba, se salta" "rels[1]['prerelease'] = True"
rel 1.37.9 "borrador, se salta" "rels[1]['draft'] = True"
rel 1.37.9 "nombre con ordenes, se salta" "rels[1]['assets'][2]['name'] = 'lvm-instalador-mac-1.38.0;x.zip'"
rel 1.37.9 "fecha rara, se salta" "rels[1]['published_at'] = '2026-10-23 10:00|x'"
rel no "ninguna con la de Mac" "rels = [r('v1.52.0')]"
rel no "no es una lista" "rels = rels[0]"
check "GitHub: devuelve fecha y descargas de su publicacion" '[ "$(python3 -I -c "$MAC_RELEASE_PY" o/r <<< "[{\"tag_name\": \"v1.51.0\", \"published_at\": \"2026-10-23T10:00:00Z\", \"assets\": [{\"name\": \"lvm-instalador-mac-1.38.0.zip\", \"browser_download_url\": \"https://github.com/o/r/releases/download/v1.51.0/lvm-instalador-mac-1.38.0.zip\"}, {\"name\": \"lvm-instalador-mac-1.38.0.zip.sig\", \"browser_download_url\": \"https://github.com/o/r/releases/download/v1.51.0/lvm-instalador-mac-1.38.0.zip.sig\"}]}]")" = "1.38.0|2026-10-23T10:00:00Z|https://github.com/o/r/releases/download/v1.51.0/lvm-instalador-mac-1.38.0.zip|https://github.com/o/r/releases/download/v1.51.0/lvm-instalador-mac-1.38.0.zip.sig" ]'

# --- La firma
mkdir "$W/z"
mkzip "$W/z/lvm-instalador-mac-1.38.0.zip" 1.38.0 && sign "$W/z/lvm-instalador-mac-1.38.0.zip"
cp "$W/z/lvm-instalador-mac-1.38.0.zip" "$W/z/otra.zip"; sign "$W/z/otra.zip" gpg2
cp "$W/z/lvm-instalador-mac-1.38.0.zip" "$W/z/sinfirma.zip"
cp "$W/z/lvm-instalador-mac-1.38.0.zip" "$W/z/enlace.zip"; ln -s "$W/z/lvm-instalador-mac-1.38.0.zip.sig" "$W/z/enlace.zip.sig"
check "firma: buena" 'update_signed "$W/z/lvm-instalador-mac-1.38.0.zip"'
check "firma: de otra clave, no" '! update_signed "$W/z/otra.zip"'
check "firma: sin firma, no" '! update_signed "$W/z/sinfirma.zip"'
check "firma: la firma es un enlace, no" '! update_signed "$W/z/enlace.zip"'
if [ $NEW_VERIFY -eq 1 ]; then
    check "firma: sin gpgv tambien se comprueba (la comprueba el gestor)" 'GPGV=$W/no-esta update_signed "$W/z/lvm-instalador-mac-1.38.0.zip"'
    check "firma: sin el comprobador, no (no basta con que python termine bien)" '! UPDATE_VERIFY_PY="" update_signed "$W/z/lvm-instalador-mac-1.38.0.zip" && ! UPDATE_VERIFY_PY="pass" update_signed "$W/z/lvm-instalador-mac-1.38.0.zip"'
    check "firma: con otra huella, no" '! UPDATE_KEY_FPR=0000000000000000000000000000000000000000 update_signed "$W/z/lvm-instalador-mac-1.38.0.zip"'
    printf 'x' >> "$W/z/sinfirma.zip"; cp "$W/z/lvm-instalador-mac-1.38.0.zip.sig" "$W/z/sinfirma.zip.sig"
    check "firma: el .zip cambiado, no" '! update_signed "$W/z/sinfirma.zip"'
    rm -f "$W/z/sinfirma.zip.sig"
    gpg --homedir "$W/gpg" --batch --yes --armor --detach-sign -o "$W/z/armada.sig" "$W/z/lvm-instalador-mac-1.38.0.zip" 2> /dev/null
    cp "$W/z/lvm-instalador-mac-1.38.0.zip" "$W/z/armada"
    check "firma: en ASCII (armada), no (las publicaciones llevan la binaria)" '! update_signed "$W/z/armada"'
    check "firma: con SHA-256 tambien" 'gpg --homedir "$W/gpg" --batch --yes --digest-algo SHA256 --detach-sign -o "$W/z/s256.sig" "$W/z/lvm-instalador-mac-1.38.0.zip" 2> /dev/null && cp "$W/z/lvm-instalador-mac-1.38.0.zip" "$W/z/s256" && update_signed "$W/z/s256"'
    check "firma: la de verdad (huella de UPDATE_KEY_FPR del script) no vale para las de prueba" '! UPDATE_KEY_B64=$(sed -n "/^UPDATE_KEY_B64=.\$/,/^.\$/p" "$SRC" | sed "1d;\$d") UPDATE_KEY_FPR=$(grep -m1 "^UPDATE_KEY_FPR=" "$SRC" | cut -d\" -f2) update_signed "$W/z/lvm-instalador-mac-1.38.0.zip"'
    check "firma: la clave del script tiene la huella de UPDATE_KEY_FPR" '[ "$(python3 -I -c "import base64,hashlib,sys; d=base64.b64decode(\"\".join(sys.argv[1].split())); b=d[2:2+d[1]]; print(hashlib.sha1(b\"\\x99\"+len(b).to_bytes(2,\"big\")+b).hexdigest().upper())" "$(sed -n "/^UPDATE_KEY_B64=.\$/,/^.\$/p" "$SRC" | sed "1d;\$d")")" = "$(grep -m1 "^UPDATE_KEY_FPR=" "$SRC" | cut -d\" -f2)" ]'
else
    check "firma: sin gpgv, no" '! GPGV=$W/no-esta update_signed "$W/z/lvm-instalador-mac-1.38.0.zip"'
fi

# --- github_update / gui_package con un curl de mentira (sirve $W/srv; cuenta las descargas)
mkdir "$W/srv"
cp "$W/z/lvm-instalador-mac-1.38.0.zip" "$W/z/lvm-instalador-mac-1.38.0.zip.sig" "$W/srv/"
CODE=200 DOWNLOADS=0
curl() {
    local out="" url=${!#} a
    for a in "$@"; do [ "$prev" = -o ] && out=$a; local prev=$a; done
    if [[ "$url" == https://api.github.com/* ]]; then
        printf '[{"tag_name": "v1.51.0", "published_at": "2026-10-23T10:00:00Z", "assets": [%s]}]\n%s' \
            '{"name": "lvm-instalador-mac-1.38.0.zip", "browser_download_url": "https://github.com/o/r/releases/download/v1.51.0/lvm-instalador-mac-1.38.0.zip"}, {"name": "lvm-instalador-mac-1.38.0.zip.sig", "browser_download_url": "https://github.com/o/r/releases/download/v1.51.0/lvm-instalador-mac-1.38.0.zip.sig"}' \
            "$CODE"
        return 0
    fi
    DOWNLOADS=$((DOWNLOADS + 1))
    cp "$W/srv/${url##*/}" "$out" 2> /dev/null
}
out=$(github_update; echo "rc=$?")
check "GitHub: ofrece la nueva (U|version|fecha|huella|ruta)" 'grep -q "^U|1.38.0|23/10/2026 ..:..|$(sha256sum "$W/srv/lvm-instalador-mac-1.38.0.zip" | cut -d" " -f1)|$W/act/lvm-instalador-mac-1.38.0.zip$" <<< "$out"'
check "GitHub: descargada en actualizaciones, con su firma" '[ -f "$W/act/lvm-instalador-mac-1.38.0.zip" ] && [ -f "$W/act/lvm-instalador-mac-1.38.0.zip.sig" ]'
check "GitHub: la carpeta de actualizaciones es solo tuya" '[ "$(command stat -c %a "$W/act")" = 700 ]'
check "GitHub: con la fecha de la publicacion" '[ "$(command date -r "$W/act/lvm-instalador-mac-1.38.0.zip" -u +%F)" = 2026-10-23 ]'
n=$DOWNLOADS; github_update > /dev/null; github_update > /dev/null
check "GitHub: ya descargada y firmada, no se vuelve a bajar" '[ "$DOWNLOADS" = "$n" ]'
out=$(gui_package)
check "gui-paquete: con la de GitHub, no busca en Descargas" 'grep -q "^U|1.38.0" <<< "$out" && ! grep -q "^N|" <<< "$out"'
out=$(APP_VERSION=1.38.0 github_update; echo "rc=$?")
check "GitHub: si no es mas nueva, nada que ofrecer" '! grep -q "^U|" <<< "$out" && grep -q "rc=1" <<< "$out"'
rm -rf "$W/act"; cp "$W/z/otra.zip.sig" "$W/srv/lvm-instalador-mac-1.38.0.zip.sig"
out=$(github_update; echo "rc=$?")
check "GitHub: con otra firma no se ofrece y se borra" '! grep -q "^U|" <<< "$out" && grep -q "no está firmada" <<< "$out" && [ ! -e "$W/act/lvm-instalador-mac-1.38.0.zip" ]'
if [ $NEW_VERIFY -eq 1 ]; then
    cp "$W/z/lvm-instalador-mac-1.38.0.zip.sig" "$W/srv/lvm-instalador-mac-1.38.0.zip.sig"
    out=$(GPGV=$W/no-esta github_update)
    check "GitHub: sin gpgv tambien la ofrece (la firma la comprueba el gestor)" 'grep -q "^U|1.38.0|" <<< "$out" && ! grep -q "^G|" <<< "$out"'
    rm -rf "$W/act"
else
    out=$(GPGV=$W/no-esta github_update)
    check "GitHub: sin gpgv lo dice (G|) y no descarga" 'grep -q "^G|" <<< "$out" && grep -q "brew install gnupg" <<< "$out" && [ ! -e "$W/act/lvm-instalador-mac-1.38.0.zip" ]'
fi
out=$(CODE=404 github_update; echo "rc=$?")
check "GitHub: sin publicaciones lo dice" 'grep -q "^I|Todavía no hay" <<< "$out" && grep -q "rc=1" <<< "$out"'
out=$(CODE=000 github_update)
check "GitHub: sin conexion lo dice" 'grep -q "^I|No se ha podido consultar GitHub" <<< "$out"'
ln -s "$W/otra" "$W/act2"
out=$(UPDATES_DIR=$W/act2 github_update)
check "GitHub: si la carpeta de actualizaciones es un enlace, no descarga" 'grep -q "es un enlace" <<< "$out" && [ ! -e "$W/otra" ]'
rm -f "$W/act2"
# Sin conexion: el .dmg de Descargas, como hasta la 1.36.0
mdls() { echo '("https://ejemplo.com/x.dmg")'; }
echo dmg > "$HOME/Downloads/lvm-instalador-mac-1.39.0.dmg"
out=$(CODE=000 TMPDIR=$W gui_package)
check "gui-paquete: sin conexion, el .dmg de Descargas (N|)" 'grep -q "^N|1.39.0|" <<< "$out" && grep -q "^O|https://ejemplo.com/x.dmg" <<< "$out"'

# --- actualizar-gestor
mkdir -p "$W/inst"
SELF=$W/inst/lvm-instalador.sh
# (desde la 1.39.3 instala en el gestor de root: en las pruebas, LVM_PRUEBA, sin sudo y en SELF)
if [ $NEW_VERIFY -eq 1 ]; then
    eval "$(sed -n "/^NEXUM_DIR=/p; /^TRUSTED_DIR=/p; /^TRUSTED_SCRIPT=/p" "$SRC")"
    printf '#!/bin/bash\nAPP_VERSION="1.37.0"\necho vieja\n' > "$SELF"
    out=$(SUDO=sudo TEST_DIR="" install_update "$W/z/lvm-instalador-mac-1.38.0.zip" 2>&1); rc=$?
    check "actualizar-gestor: desde una copia que no es el gestor de root, no instala nada" '[ $rc -ne 0 ] && grep -q "gestor de root" <<< "$out" && grep -q "echo vieja" "$SELF"'
    check "actualizar-gestor: root comprueba la firma de su copia, no la de tu carpeta" 'sed -n "/^function install_update() {/,/^}/p" "$SRC" | grep -q "UPDATE_VERIFY_PY\" \"\$work/nuevo.zip\""'
    TEST_DIR=$W SUDO=""
fi
reset_self() { printf '#!/bin/bash\nAPP_VERSION="1.37.0"\necho vieja\n' > "$SELF"; chmod 755 "$SELF"; }
try() {  # try <si|no> <descripcion> <zip> [variables]
    reset_self
    local out rc
    out=$(eval "${4:-}" install_update "$3" 2>&1); rc=$?
    if [ "$1" = si ]; then
        [ $rc -eq 0 ] && grep -q "echo nueva" "$SELF" && ok "actualizar-gestor: $2" || bad "actualizar-gestor: $2 ($out)"
    else
        [ $rc -ne 0 ] && grep -q "echo vieja" "$SELF" && ok "actualizar-gestor rechaza: $2" || bad "actualizar-gestor acepta: $2 ($out)"
    fi
}
cp "$W/z/lvm-instalador-mac-1.38.0.zip" "$W/z/lvm-instalador-mac-1.38.0.zip.sig" "$W/inst/" 2> /dev/null
try si "firmado y mas nuevo" "$W/z/lvm-instalador-mac-1.38.0.zip"
check "actualizar-gestor: el nuevo con permiso de ejecucion" '[ "$(command stat -c %a "$SELF")" = 755 ] && [ ! -e "$SELF.nuevo" ]'
reset_self; out=$(DRY=1 install_update "$W/z/lvm-instalador-mac-1.38.0.zip" 2>&1); rc=$?
check "actualizar-gestor: en simulacion no se cambia" '[ $rc -eq 0 ] && grep -q "\[simulacion\]" <<< "$out" && grep -q "echo vieja" "$SELF"'
try no "la misma version" "$W/z/lvm-instalador-mac-1.38.0.zip" "APP_VERSION=1.38.0"
try no "una mas vieja" "$W/z/lvm-instalador-mac-1.38.0.zip" "APP_VERSION=1.40.0"
if [ $NEW_VERIFY -eq 1 ]; then
    try si "sin gpgv (la firma la comprueba el gestor)" "$W/z/lvm-instalador-mac-1.38.0.zip" "GPGV=$W/no-esta"
else
    try no "sin gpgv" "$W/z/lvm-instalador-mac-1.38.0.zip" "GPGV=$W/no-esta"
fi
mkdir "$W/m"
cp "$W/z/otra.zip" "$W/m/lvm-instalador-mac-1.38.0.zip"; cp "$W/z/otra.zip.sig" "$W/m/lvm-instalador-mac-1.38.0.zip.sig"
try no "firmado con otra clave" "$W/m/lvm-instalador-mac-1.38.0.zip"
rm -f "$W/m/lvm-instalador-mac-1.38.0.zip.sig"
try no "sin firma" "$W/m/lvm-instalador-mac-1.38.0.zip"
for extra in enlace sin roto dos; do
    mkzip "$W/m/lvm-instalador-mac-1.38.0.zip" 1.38.0 "$extra"; sign "$W/m/lvm-instalador-mac-1.38.0.zip"
    try no "firmado, pero con el script $extra" "$W/m/lvm-instalador-mac-1.38.0.zip"
done
mkzip "$W/m/lvm-instalador-mac-1.38.0.zip" 1.39.0; sign "$W/m/lvm-instalador-mac-1.38.0.zip"
try no "firmado, pero el script es de otra version que la del nombre" "$W/m/lvm-instalador-mac-1.38.0.zip"
mkzip "$W/m/nombre.zip" 1.38.0; sign "$W/m/nombre.zip"
try no "un .zip con otro nombre" "$W/m/nombre.zip"
ln -sf "$W/z/lvm-instalador-mac-1.38.0.zip" "$W/m/x" && mkdir "$W/l" && ln -s "$W/z/lvm-instalador-mac-1.38.0.zip" "$W/l/lvm-instalador-mac-1.38.0.zip" \
    && cp "$W/z/lvm-instalador-mac-1.38.0.zip.sig" "$W/l/"
try no "el .zip es un enlace" "$W/l/lvm-instalador-mac-1.38.0.zip"
exit $fail
