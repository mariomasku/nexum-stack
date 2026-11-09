#!/bin/bash
# Construye los dos scripts que se instalan y se publican a partir de sus fuentes, en src/:
#
#   src/linux/bash/NN-*.sh  ->  lvm-instalador.sh          (con src/linux/ventana.py y tunel.py)
#   src/mac/bash/NN-*.sh    ->  macos/lvm-instalador.sh    (con src/mac/ventana.swift y tunel.py)
#
# El bash va por secciones, en el orden de su número. Una línea «#@incluir <fichero>» (dentro de un
# heredoc) se cambia por ese fichero entero, de la carpeta del sistema: la ventana de Linux (Python),
# la del Mac (Swift) y el proxy del túnel. El resultado sigue siendo un solo fichero, como siempre.
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
INCLUDE = re.compile(r"#@incluir ([A-Za-z0-9_.-]+)")


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
                inc = os.path.join(root, src, m.group(1))
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
for src, dst in TARGETS:
    text = build(src)
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
