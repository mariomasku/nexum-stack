#!/bin/bash
# Publica la version de lvm-instalador.sh (su APP_VERSION) en GitHub, para que «Buscar
# actualizaciones» la encuentre en todos los equipos:
#   1. comprueba que el repositorio esta limpio, en main y al dia con GitHub, y que la version es
#      mas nueva que la ultima publicada
#   2. pasa la bateria de pruebas (pruebas/todas.sh): con algun fallo no se publica
#   3. crea el paquete en dist/ (empaquetar-deb.sh) y lo firma con la clave de UPDATE_KEY_FPR (pide
#      su frase de contraseña)
#   4. tras confirmarlo: pone al dia CHANGELOG.md y la version de README.md (commit), crea la
#      etiqueta vX.Y.Z, lo sube todo y crea la publicacion (Release) con el .deb, su firma y las
#      novedades de esa version
# Necesita gh con la sesion iniciada (gh auth login) y la clave privada de las firmas en gpg.
#
# Uso: ./publicar.sh

set -e -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
SRC=$HERE/lvm-instalador.sh
VERSION=$(grep -m1 '^APP_VERSION=' "$SRC" | cut -d'"' -f2)
FPR=$(grep -m1 '^UPDATE_KEY_FPR=' "$SRC" | cut -d'"' -f2)
REPO=$(grep -m1 '^UPDATE_REPO=' "$SRC" | cut -d'"' -f2)
TAG=v$VERSION
DIST=$HERE/dist
DEB=$DIST/lvm-instalador_${VERSION}_all.deb

function fail() {
    echo "No se publica: $*" >&2
    exit 1
}

[ -n "$VERSION" ] && [ -n "$FPR" ] && [ -n "$REPO" ] || fail "faltan APP_VERSION, UPDATE_KEY_FPR o UPDATE_REPO en $SRC"
echo "== Nexum Stack $VERSION → github.com/$REPO"

# --- 1. Comprobaciones ------------------------------------------------------------------------
command -v gh > /dev/null || fail "falta gh (sudo apt install gh)"
gh auth status > /dev/null 2>&1 || fail "gh no tiene la sesion iniciada (gh auth login)"
gpg --list-secret-keys "$FPR" > /dev/null 2>&1 || fail "no esta en este equipo la clave privada $FPR"
[ "$(git branch --show-current)" == main ] || fail "no estas en la rama main"
[ -z "$(git status --porcelain)" ] || fail "hay cambios sin commit (mira git status)"
git fetch -q origin main
[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ] \
    || fail "main no esta igual que en GitHub (haz git pull o git push antes)"
git rev-parse -q --verify "refs/tags/$TAG" > /dev/null && fail "la etiqueta $TAG ya existe"
gh release view "$TAG" -R "$REPO" > /dev/null 2>&1 && fail "la $VERSION ya esta publicada"
LATEST=$(gh release view -R "$REPO" --json tagName -q .tagName 2> /dev/null || true)
if [ -n "$LATEST" ] && ! dpkg --compare-versions "$VERSION" gt "${LATEST#v}"; then
    fail "la $VERSION no es mas nueva que la ultima publicada ($LATEST): sube APP_VERSION"
fi
echo "   Ultima publicada: ${LATEST:-ninguna}"

# --- 2. Pruebas -------------------------------------------------------------------------------
echo "== Pruebas (pruebas/todas.sh)"
if ! RESULT=$(LVM_SCRIPT=$SRC LVM_EMPAQUETAR=$HERE/empaquetar-deb.sh "$HERE/pruebas/todas.sh" 2>&1); then
    echo "$RESULT" | tail -40
    fail "fallan pruebas"
fi
echo "   $(echo "$RESULT" | tail -1)"

# --- 3. Paquete y firma -----------------------------------------------------------------------
echo "== Paquete y firma"
mkdir -p "$DIST"
rm -f "$DEB" "$DEB.sig"
"$HERE/empaquetar-deb.sh" "$DIST" > /dev/null
[ -f "$DEB" ] || fail "empaquetar-deb.sh no ha creado $DEB"
gpg --local-user "$FPR" --detach-sign --output "$DEB.sig" "$DEB"
# Comprobada como la comprobara el programa: con la clave que lleva el script y su huella
CHECK=$(mktemp -d)
trap 'rm -rf "$CHECK"' EXIT
sed -n "/^UPDATE_KEY_B64='/,/^'$/p" "$SRC" | sed '1d;$d' | base64 -d > "$CHECK/firma.gpg"
GNUPGHOME=$CHECK gpgv --status-fd 1 --keyring "$CHECK/firma.gpg" "$DEB.sig" "$DEB" 2> /dev/null \
    > "$CHECK/estado" || true
grep -q "^\[GNUPG:\] VALIDSIG $FPR " "$CHECK/estado" || fail "la firma no se comprueba con la clave del script"
echo "   $DEB"
echo "   SHA-256: $(sha256sum "$DEB" | cut -d' ' -f1)"

# Novedades de esta version (las de la publicacion)
NOTES=$DIST/novedades-$VERSION.md
bash "$SRC" novedades | awk -v head="## $VERSION " 'index($0, head) == 1 { on = 1; next } /^## / { if (on) exit } on' \
    | sed '/./,$!d' > "$NOTES"
[ -s "$NOTES" ] || fail "no hay novedades de la $VERSION"
cat >> "$NOTES" << EOF

---

**Actualizar:** en Nexum Stack, menú ☰ → *Buscar actualizaciones* (comprueba la firma antes de instalarla).
**Instalar en la terminal:** descarga \`lvm-instalador_${VERSION}_all.deb\` y ejecuta \`sudo apt install ./lvm-instalador_${VERSION}_all.deb\`.
EOF

# --- 4. Publicar ------------------------------------------------------------------------------
echo
echo "Novedades de la $VERSION:"
sed 's/^/   /' "$NOTES"
echo
read -r -p "¿Publicar la $VERSION en GitHub? Se sube y la veran todos los equipos [s/N] " answer
[[ $answer =~ ^[sS]$ ]] || fail "cancelado (el paquete firmado queda en $DIST)"

{ head -6 CHANGELOG.md; bash "$SRC" novedades; } > CHANGELOG.md.nuevo
mv CHANGELOG.md.nuevo CHANGELOG.md
sed -i -E "s/^\*\*Versión actual: [0-9.]+\*\*/**Versión actual: $VERSION**/" README.md
grep -q "^\*\*Versión actual: $VERSION\*\*" README.md || fail "no se encuentra «Versión actual» en README.md"
git add CHANGELOG.md README.md
git diff --cached --quiet || git commit -q -m "Versión $VERSION"
git tag -a "$TAG" -m "Nexum Stack $VERSION"
git push -q origin main "$TAG"
if ! gh release create "$TAG" -R "$REPO" --verify-tag --title "Nexum Stack $VERSION" \
        --notes-file "$NOTES" "$DEB" "$DEB.sig"; then
    echo "La etiqueta $TAG ya esta en GitHub, pero no se ha creado la publicacion. Para reintentarlo:" >&2
    echo "  gh release create $TAG -R $REPO --verify-tag --title \"Nexum Stack $VERSION\" --notes-file $NOTES $DEB $DEB.sig" >&2
    exit 1
fi
echo "Publicada: https://github.com/$REPO/releases/tag/$TAG"
