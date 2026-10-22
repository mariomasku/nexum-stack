"""Prepara la configuracion del Apache temporal de web.sh (antes, la carpeta sec2 del scratchpad).

Uso: python3 -I apache-temporal.py <httpd.conf de la version> <carpeta de trabajo> <unk.conf>

Parte del httpd.conf de una version instalada (por defecto /opt/lampp-8.2.4; solo se lee) y escribe
<carpeta>/httpd.conf para un Apache que solo escucha en 127.0.0.1:18080 y 127.0.0.1:18081, con:
  - los registros y el .pid en <carpeta>/logs;
  - htdocs en <carpeta>/htdocs (vacia: las pruebas piden ficheros que no existen);
  - el vhost de dominios desconocidos que se le pase (<unk.conf>, sacado del script que se prueba);
  - un vhost de web.local y un phpMyAdmin falso (una pagina estatica en <carpeta>/phpmyadmin): nunca
    se sirve el phpMyAdmin de verdad ni se habla con un MariaDB;
  - sin SSL ni PHP, ni las paginas de error de XAMPP.
"""
import os, re, sys

src, W, unk = sys.argv[1], os.path.abspath(sys.argv[2]), os.path.abspath(sys.argv[3])
base = os.path.dirname(os.path.dirname(os.path.abspath(src)))  # /opt/lampp-8.2.4
t = open(src, encoding="utf-8", errors="replace").read()

# Nada de /opt/lampp (ya no es la version activa, y puede no existir): la version de la que se parte
t = t.replace('"/opt/lampp"', '"%s"' % base).replace("/opt/lampp/", base + "/")
t = re.sub(r'(?m)^ServerRoot .*$', 'ServerRoot "%s"' % base, t)
# htdocs propia y vacia
t = t.replace(base + "/htdocs", W + "/htdocs")
# Solo los puertos de prueba
t = re.sub(r"(?m)^\s*Listen .*$", "", t)
# Registros y .pid en la carpeta de trabajo
t = re.sub(r'(?m)^(\s*(ErrorLog|CustomLog|PidFile))\s+"?logs/([^"\s]+)"?', r'\1 "%s/logs/\3"' % W, t)
# Los Include de la version que tocan la red, los vhosts, SSL y phpMyAdmin se cambian por los de prueba
inc_unk = "Include %s/unk.conf" % W
inc_vh = "Include %s/vhosts.conf" % W
if re.search(r"(?m)^Include etc/extra/lvm-dominio-desconocido\.conf", t):
    t = re.sub(r"(?m)^Include etc/extra/lvm-dominio-desconocido\.conf.*$", inc_unk, t)
    t = re.sub(r"(?m)^Include etc/extra/httpd-vhosts\.conf.*$", inc_vh, t)
else:
    t = re.sub(r"(?m)^Include etc/extra/httpd-vhosts\.conf.*$", inc_unk + "\n" + inc_vh, t)
t = re.sub(r"(?m)^Include etc/extra/httpd-ssl\.conf.*$", "", t)
# Paginas de error de XAMPP: estan en /opt/lampp/error (fuera de la version)
t = re.sub(r"(?m)^Include etc/extra/httpd-multilang-errordoc\.conf.*$", "", t)
t = re.sub(r"(?m)^Include etc/extra/httpd-xampp\.conf.*$", "Include %s/xampp.conf" % W, t)
t = re.sub(r'(?m)^Include "?%s/apache2/conf/httpd\.conf"?.*$' % re.escape(base), "", t)
if inc_unk not in t or inc_vh not in t:
    sys.exit("no se ha podido preparar el httpd.conf de prueba")
t += ("\nListen 127.0.0.1:18080\nListen 127.0.0.1:18081\nPidFile %s/logs/httpd.pid\n"
      "ErrorLog %s/logs/error_log\nDefaultRuntimeDir %s/logs\n" % (W, W, W))

for d in ("logs", "htdocs", "phpmyadmin", "web.local"):
    os.makedirs(os.path.join(W, d), exist_ok=True)
# (index.php como en el de verdad: las reglas solo dejan pasar /phpmyadmin/ e index.php. Sin PHP, se
# sirve tal cual)
open(os.path.join(W, "phpmyadmin", "index.php"), "w").write("<title>phpMyAdmin de prueba</title>\n")
open(os.path.join(W, "phpmyadmin", "config.inc.php"), "w").write("<?php // de prueba\n")
open(os.path.join(W, "httpd.conf"), "w").write(t)
open(os.path.join(W, "xampp.conf"), "w").write(
    'Alias /phpmyadmin "%s/phpmyadmin"\n<Directory "%s/phpmyadmin">\n    AllowOverride None\n'
    '    Require local\n</Directory>\n' % (W, W))
open(os.path.join(W, "vhosts.conf"), "w").write(
    '<VirtualHost *:18080>\n    ServerName web.local\n    DocumentRoot "%s/web.local"\n'
    '    <Directory "%s/web.local">\n        Require all granted\n    </Directory>\n</VirtualHost>\n' % (W, W))
if not os.path.isfile(unk):
    sys.exit("falta " + unk)
