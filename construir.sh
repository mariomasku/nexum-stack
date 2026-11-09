#!/bin/bash
# Construye los dos scripts que se instalan y se publican a partir de sus fuentes, en src/:
#
#   src/linux/bash/NN-*.sh  ->  lvm-instalador.sh          (con src/linux/ventana.py y tunel.py)
#   src/mac/bash/NN-*.sh    ->  macos/lvm-instalador.sh    (con src/mac/ventana.swift y tunel.py)
#
# El bash va por secciones, en el orden de su número. Una línea «#@incluir <fichero>» se cambia por ese
# fichero entero: de la carpeta del sistema (dentro de un heredoc: la ventana de Linux en Python, la del
# Mac en Swift y el proxy del túnel) o, con «comun/…», de src/comun: las funciones que son iguales en
# Linux y en Mac, una sola vez (cada una tiene que usarse en los dos). El resultado sigue siendo un solo
# fichero, como siempre.
#
# Uso: ./construir.sh               rehace los dos scripts
#      ./construir.sh --comprobar   no escribe nada: falla si los scripts no son los de src/
#
# Se edita en src/ y se construye. Los dos scripts siguen en el repositorio (los usan el paquete,
# publicar.sh y las pruebas), pero no se tocan a mano: la comprobación de GitHub lo detecta.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
mode=${1:-}
case "$mode" in
    ""|--comprobar) ;;
    *) echo "Uso: $0 [--comprobar]" >&2; exit 2 ;;
esac

python3 -I - "$HERE" "$mode" << 'PY'
import glob, os, re, sys

root, mode = sys.argv[1], sys.argv[2]
TARGETS = [("src/linux", "lvm-instalador.sh"), ("src/mac", "macos/lvm-instalador.sh")]
INCLUDE = re.compile(r"#@incluir ((?:comun/[A-Za-z0-9_-]+/)?[A-Za-z0-9_.-]+)")
common_used = {}  # comun/… -> sistemas que lo incluyen


def build(src):
    parts = sorted(glob.glob(os.path.join(root, src, "bash", "[0-9][0-9]-*.sh")))
    if not parts:
        sys.exit("construir: no hay secciones en %s/bash" % src)
    out = []
    used = set()
    for path in parts:
        text = open(path, encoding="utf-8", newline="").read()
        if not text.endswith("\n"):
            sys.exit("construir: %s no acaba en salto de línea" % path)
        for line in text[:-1].split("\n"):
            m = INCLUDE.fullmatch(line)
            if m:
                name = m.group(1)
                if name.startswith("comun/"):
                    inc = os.path.join(root, "src", name)
                    common_used.setdefault(name, set()).add(src)
                else:
                    inc = os.path.join(root, src, name)
                body = open(inc, encoding="utf-8", newline="").read()
                if not body.endswith("\n"):
                    sys.exit("construir: %s no acaba en salto de línea" % inc)
                out.append(body[:-1])
                used.add(m.group(1))
            else:
                out.append(line)
    # (un fichero que no se incluye en ningún sitio es un error: se habría perdido sin avisar)
    loose = {os.path.basename(p) for p in glob.glob(os.path.join(root, src, "*")) if os.path.isfile(p)} - used
    if loose:
        sys.exit("construir: en %s hay ficheros que no se incluyen: %s" % (src, ", ".join(sorted(loose))))
    return "\n".join(out) + "\n"


bad = []
built = {}
for src, dst in TARGETS:
    built[dst] = build(src)
# Lo de src/comun, en los dos sistemas: si solo lo usa uno, va en la carpeta de ese sistema
common = {os.path.relpath(p, os.path.join(root, "src")) for p in glob.glob(os.path.join(root, "src", "comun", "*", "*.sh"))}
for name in sorted(common | set(common_used)):
    users = common_used.get(name, set())
    if len(users) != len(TARGETS):
        sys.exit("construir: %s se usa en %s: lo común tiene que ir en Linux y en Mac"
                 % (name, " y ".join(sorted(users)) or "ningún sistema"))
for src, dst in TARGETS:
    text = built[dst]
    path = os.path.join(root, dst)
    try:
        old = open(path, encoding="utf-8", newline="").read()
    except FileNotFoundError:
        old = None
    if mode == "--comprobar":
        if old != text:
            bad.append(dst)
        continue
    if old != text:
        tmp = path + ".nuevo"
        with open(tmp, "w", encoding="utf-8", newline="") as f:
            f.write(text)
        os.chmod(tmp, 0o755)
        os.replace(tmp, path)
        print("construido: %s" % dst)
    else:
        print("sin cambios: %s" % dst)
if bad:
    print("construir: %s no %s lo de src/ (edita en src/ y ejecuta ./construir.sh)"
          % (" y ".join(bad), "es" if len(bad) == 1 else "son"), file=sys.stderr)
    sys.exit(1)
if mode == "--comprobar":
    print("Los dos scripts son los de src/")
PY
