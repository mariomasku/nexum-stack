# manual [--ruta] [<capitulo>]: el manual (ayuda/), que va dentro de este mismo script (al final, después
# del exit, en base64: un solo fichero, también al actualizar). Se saca a ~/.nexum/ayuda la
# primera vez y cada vez que cambia (su huella), y se abre en el navegador en <capitulo> (proyectos,
# limpieza…), con Linux o Mac ya elegido. --ruta: solo dice qué abrir (lo abre la ventana).
# El navegador no siempre respeta lo de detrás de # al abrir un fichero: se abre abrir.html, que lleva a
# index.html?so=…#<capitulo>
MANUAL_PY='
import base64, hashlib, io, os, shutil, sys, tarfile, tempfile
script, dest = sys.argv[1], sys.argv[2]
lines, inside = [], False
with open(script, encoding="utf-8") as f:
    for line in f:
        line = line.rstrip("\n")
        if line == ": <<'"'"'NEXUM_MANUAL'"'"'":
            inside = True
        elif inside and line == "NEXUM_MANUAL":
            break
        elif inside:
            lines.append(line)
if not lines:
    sys.exit("Este script no lleva el manual dentro")
data = "".join(lines).encode()
mark = hashlib.sha256(data).hexdigest()
try:
    with open(os.path.join(dest, ".huella")) as f:
        if f.read().strip() == mark:
            sys.exit(0)
except OSError:
    pass
os.umask(0o077)
parent = os.path.dirname(dest)
os.makedirs(parent, mode=0o700, exist_ok=True)
if os.path.islink(dest):
    sys.exit("%s es un enlace: no se toca" % dest)
new = tempfile.mkdtemp(prefix=".ayuda-", dir=parent)
try:
    with tarfile.open(fileobj=io.BytesIO(base64.b64decode(data)), mode="r:") as tar:
        for m in tar:
            parts = m.name.split("/")
            # (solo ficheros y carpetas, dentro de la suya: nada de rutas absolutas, .. ni enlaces)
            if m.name.startswith("/") or ".." in parts or not (m.isfile() or m.isdir()):
                sys.exit("El manual trae algo que no se saca: %s" % m.name)
            path = os.path.join(new, *parts)
            if m.isdir():
                os.makedirs(path, mode=0o700, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
            with tar.extractfile(m) as src, open(path, "wb") as out:
                shutil.copyfileobj(src, out)
    with open(os.path.join(new, ".huella"), "w") as f:
        f.write(mark + "\n")
    old = None
    if os.path.isdir(dest):
        old = tempfile.mkdtemp(prefix=".ayuda-vieja-", dir=parent)
        os.rename(dest, os.path.join(old, "ayuda"))
    os.rename(new, dest)
    new = None
    if old:
        shutil.rmtree(old, ignore_errors=True)
finally:
    if new:
        shutil.rmtree(new, ignore_errors=True)
'

function manual_command() {
    local only="" chapter="" dir=$LOG_DIR/ayuda
    [ "$1" == "--ruta" ] && only=1 && shift
    chapter=${1:-}
    if ! [[ "$chapter" =~ ^[a-z][a-z0-9-]{0,40}$ ]]; then
        [ -n "$chapter" ] && echo "Capitulo no valido: $chapter (se abre el principio)"
        chapter=inicio
    fi
    python3 -I -c "$MANUAL_PY" "$SELF" "$dir" || { echo "No se ha podido sacar el manual a $dir"; return 1; }
    ( umask 077
      printf '<!doctype html>\n<meta charset="utf-8">\n<title>Manual de Nexum Dev Stack</title>\n<meta http-equiv="refresh" content="0; url=index.html?so=%s#%s">\n<script>location.replace("index.html?so=%s#%s")</script>\n' \
          "$MANUAL_SO" "$chapter" "$MANUAL_SO" "$chapter" > "$dir/abrir.html" ) || return 1
    if [ -n "$only" ]; then
        echo "$dir/abrir.html"
        return 0
    fi
    echo "Abriendo el manual: $dir/index.html"
    manual_open "$dir/abrir.html"
}
