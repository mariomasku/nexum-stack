#!/bin/bash
# Construye los dos scripts que se instalan y se publican a partir de sus fuentes, en src/:
#
#   src/linux/bash/NN-*.sh  ->  lvm-instalador.sh          (con src/linux/ventana/ y tunel.py)
#   src/mac/bash/NN-*.sh    ->  macos/lvm-instalador.sh    (con src/mac/ventana/ y tunel.py)
#
# El bash va por secciones, en el orden de su número. Una línea «#@incluir <fichero>» se cambia por ese
# fichero entero: de la carpeta del sistema (dentro de un heredoc: la ventana de Linux en Python, la del
# Mac en Swift y el proxy del túnel) o, con «comun/…», de src/comun: las funciones que son iguales en
# Linux y en Mac, una sola vez (cada una tiene que usarse en los dos). «#@incluir <carpeta>/» junta sus
# ficheros NN-*, en el orden de su número y con dos líneas en blanco entre uno y otro: las ventanas,
# en src/linux/ventana/ (cada apartado, una clase en su fichero) y src/mac/ventana/ (cada apartado en
# su fichero; AppModel, en una clase con sus propiedades y extensiones). El resultado sigue siendo un
# solo fichero, como siempre. «#@manual linux|mac», la última línea, pone detrás un exit y el manual
# (ayuda/: la página, su estilo, su código, la tipografía y las capturas de ese sistema; en el Mac, las de
# Linux que aún no tengan la suya) en un tar en base64, siempre igual para lo mismo (sin fechas ni dueños):
# lo saca «lvm-instalador manual».
#
# Uso: ./construir.sh                      rehace los dos scripts
#      ./construir.sh --comprobar          no escribe nada: falla si los scripts no son los de src/
#      ./construir.sh --ventana <fichero>  escribe en <fichero> la ventana de Linux entera (para
#                                          revisarla con ruff o comprobar que es Python válido)
#      ./construir.sh --ventana-mac <fich>  la del Mac entera (para compilarla con swiftc)
#
# Se edita en src/ y se construye. Los dos scripts siguen en el repositorio (los usan el paquete,
# publicar.sh y las pruebas), pero no se tocan a mano: la comprobación de GitHub lo detecta.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
mode=${1:-} out=${2:-}
case "$mode" in
    ""|--comprobar) ;;
    --ventana|--ventana-mac) [ -n "$out" ] || { echo "Uso: $0 $mode <fichero>" >&2; exit 2; } ;;
    *) echo "Uso: $0 [--comprobar | --ventana <fichero> | --ventana-mac <fichero>]" >&2; exit 2 ;;
esac

python3 -I - "$HERE" "$mode" "$out" << 'PY'
import glob, os, re, sys

root, mode, out_file = sys.argv[1:4]
TARGETS = [("src/linux", "lvm-instalador.sh"), ("src/mac", "macos/lvm-instalador.sh")]
INCLUDE = re.compile(r"#@incluir ((?:comun/[A-Za-z0-9_-]+/)?[A-Za-z0-9_.-]+/?)")
MANUAL = re.compile(r"#@manual (linux|mac)")
common_used = {}  # comun/… -> sistemas que lo incluyen


def read(path):
    body = open(path, encoding="utf-8", newline="").read()
    if not body.endswith("\n"):
        sys.exit("construir: %s no acaba en salto de línea" % path)
    return body


def read_folder(path):
    """Los NN-* de una carpeta, en orden, con dos líneas en blanco entre uno y otro (sin el último salto)."""
    names = sorted(os.listdir(path))
    pieces = [n for n in names if re.fullmatch(r"[0-9][0-9]-[A-Za-z0-9_.-]+", n)]
    if not pieces or len(pieces) != len(names):
        sys.exit("construir: en %s solo van ficheros NN-*: %s" % (path, ", ".join(sorted(set(names) - set(pieces))) or "no hay"))
    return "\n\n\n".join(read(os.path.join(path, n))[:-1] for n in pieces)


def manual(so):
    """El manual de ese sistema, después de un exit: un tar sin fechas ni dueños, en base64 dentro de un heredoc."""
    import base64, io, tarfile
    base = os.path.join(root, "ayuda")
    names = ["index.html", "estilo.css", "manual.js", "img/nexum.png"]
    names += sorted("fuentes/" + n for n in os.listdir(os.path.join(base, "fuentes")))
    linux = sorted(os.listdir(os.path.join(base, "img", "linux")))
    if so == "linux":
        names += ["img/linux/" + n for n in linux]
    else:
        mac = sorted(os.listdir(os.path.join(base, "img", "mac"))) if os.path.isdir(os.path.join(base, "img", "mac")) else []
        names += ["img/mac/" + n for n in mac] + ["img/linux/" + n for n in linux if n not in mac]
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        dirs = set()
        for name in names:
            parts = name.split("/")[:-1]
            for i in range(1, len(parts) + 1):
                d = "/".join(parts[:i])
                if d not in dirs:
                    dirs.add(d)
                    info = tarfile.TarInfo(d)
                    info.type, info.mode, info.mtime = tarfile.DIRTYPE, 0o755, 0
                    tar.addfile(info)
            data = open(os.path.join(base, name), "rb").read()
            info = tarfile.TarInfo(name)
            info.size, info.mode, info.mtime = len(data), 0o644, 0
            tar.addfile(info, io.BytesIO(data))
    b64 = base64.b64encode(buf.getvalue()).decode()
    body = "\n".join(b64[i:i + 76] for i in range(0, len(b64), 76))
    return ("# (el script acaba aquí: lo de abajo es el manual, que saca «lvm-instalador manual»)\nexit\n"
            ": <<'NEXUM_MANUAL'\n" + body + "\nNEXUM_MANUAL")


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
            mm = MANUAL.fullmatch(line)
            if mm:
                out.append(manual(mm.group(1)))
                continue
            m = INCLUDE.fullmatch(line)
            if m:
                name = m.group(1)
                if name.startswith("comun/"):
                    inc = os.path.join(root, "src", name)
                    common_used.setdefault(name, set()).add(src)
                else:
                    inc = os.path.join(root, src, name)
                out.append(read_folder(inc) if name.endswith("/") else read(inc)[:-1])
                used.add(name.rstrip("/"))
            else:
                out.append(line)
    # (un fichero que no se incluye en ningún sitio es un error: se habría perdido sin avisar)
    loose = {os.path.basename(p) for p in glob.glob(os.path.join(root, src, "*")) if os.path.basename(p) != "bash"} - used
    if loose:
        sys.exit("construir: en %s hay ficheros que no se incluyen: %s" % (src, ", ".join(sorted(loose))))
    return "\n".join(out) + "\n"


if mode in ("--ventana", "--ventana-mac"):
    text = read_folder(os.path.join(root, "src", "linux" if mode == "--ventana" else "mac", "ventana")) + "\n"
    with open(out_file, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    sys.exit(0)

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
