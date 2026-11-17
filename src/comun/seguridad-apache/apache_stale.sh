# Apache con la configuracion de antes: apache_stale <raiz> (la de la version: /opt/lampp-8.2, o
# XAMPP-8.2/xamppfiles en el Mac). Sale con 0 si etc/httpd.conf o algun etc/extra/*.conf es mas nuevo
# que la ultima vez que Apache la cargo: la ultima «resuming normal operations» (AH00489, que escribe al
# arrancar y en cada recarga) de logs/error_log. Pasa si la seguridad se escribe y Apache no se recarga
# (la barrera entre webs nueva escrita, y Apache con la de antes en memoria). Sin esa linea (registro
# vaciado o sin permiso para leerlo), no se dice nada: mejor callar que avisar de mas.
# Solo con Apache en marcha (si esta parado, la tomara al arrancar)
APACHE_STALE_PY='
import glob, os, re, sys, time
root = sys.argv[1]
confs = [os.path.join(root, "etc/httpd.conf")] + glob.glob(os.path.join(root, "etc/extra/*.conf"))
newest = 0
for f in confs:
    try:
        newest = max(newest, os.stat(f).st_mtime)
    except OSError:
        pass
try:
    with open(os.path.join(root, "logs/error_log"), "rb") as fh:
        fh.seek(0, 2)
        fh.seek(max(0, fh.tell() - 4 * 1024 * 1024))
        tail = fh.read().decode("utf-8", "replace")
except OSError:
    sys.exit(1)
last = None
for last in re.finditer(r"^\[\w{3} (\w{3} +\d+ \d\d:\d\d:\d\d)(?:\.\d+)? (\d{4})\][^\n]*AH00489", tail, re.M):
    pass
if not last or not newest:
    sys.exit(1)
try:
    loaded = time.mktime(time.strptime("%s %s" % (" ".join(last.group(1).split()), last.group(2)), "%b %d %H:%M:%S %Y"))
except ValueError:
    sys.exit(1)
# (unos segundos de margen: la recarga escribe la linea justo despues de leer los ficheros)
sys.exit(0 if newest > loaded + 5 else 1)
'
function apache_stale() {
    [ -n "$1" ] && [ -d "$1" ] && python3 -I -c "$APACHE_STALE_PY" "$1" 2> /dev/null
}
