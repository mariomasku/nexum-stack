#!/bin/bash
# Crea el .zip de prueba de Nexum Dev Stack para Windows (se ejecuta en Linux o en cualquier sitio con
# el SDK de .NET 8): pasa las pruebas, publica NexumDevStack.exe (un solo archivo, con .NET dentro, x64)
# y lo mete con README.md y PRUEBA-WINDOWS.md en windows/nexum-dev-stack-windows-<versión>.zip.
#
# Uso:  bash windows/empaquetar-windows.sh
# La versión sale de windows/Directory.Build.props. El .zip y el .exe no van al repositorio (.gitignore).

set -e -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
DOTNET=${DOTNET:-$(command -v dotnet || echo "$HOME/.dotnet/dotnet")}
[ -x "$DOTNET" ] || { echo "No se encuentra dotnet (SDK de .NET 8): instálalo o pon su ruta en DOTNET."; exit 1; }
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
command -v zip > /dev/null || { echo "Falta zip."; exit 1; }

VERSION=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$HERE/Directory.Build.props" | head -1)
[ -n "$VERSION" ] || { echo "No se encuentra <Version> en $HERE/Directory.Build.props"; exit 1; }
ZIP=$HERE/nexum-dev-stack-windows-$VERSION.zip

echo "=== Pruebas ==="
"$DOTNET" test "$HERE/tests/NexumDevStack.Core.Tests" -c Release

echo "=== NexumDevStack.exe $VERSION ==="
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
"$DOTNET" publish "$HERE/src/NexumDevStack.App" -c Release -r win-x64 --self-contained true \
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true \
    -o "$BUILD/publicado"
EXE=$BUILD/publicado/NexumDevStack.exe
[ -f "$EXE" ] || { echo "No se ha creado NexumDevStack.exe"; exit 1; }
# (un ejecutable de Windows: empieza por MZ)
[ "$(head -c 2 "$EXE")" = "MZ" ] || { echo "NexumDevStack.exe no es un ejecutable de Windows"; exit 1; }

DIR=$BUILD/nexum-dev-stack-windows-$VERSION
mkdir -p "$DIR"
cp "$EXE" "$HERE/README.md" "$HERE/PRUEBA-WINDOWS.md" "$DIR/"
rm -f "$ZIP"
(cd "$BUILD" && zip -q -9 -r "$ZIP" "nexum-dev-stack-windows-$VERSION")
unzip -tq "$ZIP" > /dev/null

echo
echo "Hecho: $ZIP ($(du -h "$ZIP" | cut -f1); el .exe, $(du -h "$EXE" | cut -f1))"
echo "sha256: $(sha256sum "$ZIP" | cut -d' ' -f1)"
