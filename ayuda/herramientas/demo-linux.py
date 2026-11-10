#!/usr/bin/env python3
"""Datos inventados para el modo demostración de la ventana de Linux (LVM_DEMO): las capturas del
manual, sin nada de un equipo real.

Escribe en <carpeta> (por defecto ../demo/linux) una respuesta por cada comando gui-* que pide la
ventana (<comando>.txt; <comando>_<argumento>.txt si depende de uno) y la carpeta de proyectos de
ejemplo (htdocs/). En las respuestas, @DEMO@ es la carpeta (lo cambia la ventana al leerlas).

Lo que no es de nadie (las ramas de PHP, sus fechas, los componentes) va tal cual lo da el programa;
los proyectos, las bases de datos, los dominios, los repositorios y la cuenta de GitHub son inventados,
con dominios .example (reservados: no existen).

Uso: demo-linux.py [carpeta]
"""
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "demo", "linux"))
NOW = 1794300000  # (10 nov 2026)
DAY = 86400

# --- Versiones instaladas: carpeta, PHP, Apache, MariaDB, ProFTPD, Perl, phpMyAdmin, tipo; y PHP2Shell
VERSIONS = [
    ("7.4.33", "7.4.33", "2.4.69", "10.11.19", "1.3.9d", "5.40.5", "5.2.3", "propia",
     "parche", "PHP 7.4.33 + parche de seguridad (oct 2026)"),
    ("8.1", "8.1.25", "2.4.58", "10.4.32", "1.3.6", "5.34.1", "5.2.3", "XAMPP",
     "vulnerable", "XAMPP (PHP 8.1.25): sus binarios no tienen el arreglo ni se pueden arreglar"),
    ("8.2", "8.2.35", "2.4.70", "10.11.19", "1.3.9e", "5.40.5", "5.2.3", "propia", "ok", ""),
    ("8.4", "8.4.27", "2.4.70", "11.8.9", "1.3.9e", "5.42.3", "5.2.3", "propia", "ok", ""),
    ("8.5", "8.5.12", "2.4.70", "12.3.3", "1.3.9e", "5.44.0", "5.2.3", "propia", "ok", ""),
]
ACTIVE = "8.4"

# --- Proyectos: carpeta, tipo, base de datos, versión donde está, dominio real falseado (tiendas)
PROJECTS = [
    ("panaderia-luna", "wp", "wp_panaderia_luna", "8.4", ""),
    ("clinica-del-sol", "wp", "wp_clinica_del_sol", "8.2", ""),
    ("academia-flor", "wp", "wp_academia_flor", "8.1", ""),
    ("ferreteria-norte", "ps", "ps_ferreteria_norte", "7.4.33", "ferreterianorte.example"),
    ("moda-verde", "ps", "ps_moda_verde", "8.4", "modaverde.example"),
    ("inventario-almacen", "php", "inventario_almacen", "8.5", ""),
    ("portfolio-estudio", "html", "", "", ""),
]
LOADED = "panaderia-luna"
# Proyectos de Node.js: carpeta, tipo, estado, modo, dirección, Node que pide, dependencias, scripts
NODE = [
    ("agenda-citas", "Next", "marcha", "dev", "http://127.0.0.1:3000/", "22", "1", "dev build start"),
    ("blog-viajes", "Astro", "parado", "", "", "22", "1", "dev build"),
]
# Proyectos de Docker: los de WordPress con su web (php, MariaDB, estado, versiones de PHP)
DOCKER = [
    ("clinica-del-sol", "8.2", "11.8", "marcha", "wp_clinica_del_sol", "8.2 8.4"),
    ("academia-flor", "8.4", "11.8", "parado", "wp_academia_flor", "8.4"),
]
GITHUB = ("tu-usuario", "tu-empresa")
REPOS = [  # nombre, privado, días desde el último cambio, web, descripción, estado
    ("panaderia-luna", 1, 1, "https://panaderialuna.example", "Web de la panadería", "clonado"),
    ("ferreteria-norte", 1, 3, "https://ferreterianorte.example", "Tienda online", "clonado"),
    ("moda-verde", 1, 6, "https://modaverde.example", "", "clonado"),
    ("clinica-del-sol", 1, 9, "", "Clínica dental", "clonado"),
    ("hotel-mirador", 1, 12, "https://hotelmirador.example", "Reservas del hotel", "nuevo"),
    ("taller-ruiz", 0, 20, "", "", "nuevo"),
    ("inventario-almacen", 1, 25, "", "Inventario del almacén", "clonado"),
    ("libros-mar", 1, 40, "https://librosmar.example", "", "nuevo"),
]

# --- Lo que no es de nadie: tal cual lo da el programa
BRANCHES = """B|7.4|7.4.33|0|10.11|5.40|instalada|7.4.33|eol|2021-11-28|2022-11-28|2022-11-03|1
B|8.0|8.0.30|0|10.11|5.40|nueva|8.0.30|eol|2022-11-26|2023-11-26|2023-08-03|1
B|8.1|8.1.34|0|10.11|5.40|nueva|8.1.34|eol|2023-11-25|2025-12-31|2025-12-18|1
B|8.2|8.2.35|1|10.11|5.40|instalada|8.2|security|2024-12-31|2026-12-31|2026-10-21|1
B|8.3|8.3.36|1|11.4|5.40|nueva|8.3.36|security|2025-12-31|2027-12-31|2026-10-21|1
B|8.4|8.4.27|1|11.8|5.42|instalada|8.4|stable|2026-12-31|2028-12-31|2026-10-21|1
B|8.5|8.5.12|1|12.3|5.44|instalada|8.5|stable|2027-12-31|2029-12-31|2026-10-21|1
X|7.4|7.4.33-0|7.4.33|0
X|8.1|8.1.25-0|8.1.25|1
"""
DATES = """F|7.4.33|7.4.33|2022-11-03
F|8.1|8.1.25|2023-10-26
F|8.2|8.2.35|2026-10-21
F|8.4|8.4.27|2026-10-21
F|8.5|8.5.12|2026-10-21
"""
COMPONENTS = """F|7.4.33|parche concreto de PHP: se queda en el suyo
F|8.1|XAMPP oficial: no se rehace (instala una versión de PHP nueva al lado)
S|0
"""
SERVICES = """S|apache|1|80, 443|0|1|
S|mariadb|1|3306|0|1|
S|ftp|0|21|0|0|usuario
"""


def app_version():
    """La versión del programa, la del script construido (la de la cabecera de la ventana)."""
    import re
    try:
        with open(os.path.join(HERE, "..", "..", "lvm-instalador.sh"), encoding="utf-8") as f:
            m = re.search(r'^APP_VERSION="([0-9.]+)"', f.read(), re.M)
        return m.group(1) if m else "?"
    except OSError:
        return "?"


def lines(rows):
    return "".join("|".join(str(x) for x in r) + "\n" for r in rows)


def gui_datos():
    out = [("M", "Nexum Dev Stack", app_version(), "By M.Mascuñano"), ("A", ACTIVE, 1, 0, 1, 1),
           ("H", "@DEMO@/httpd-vhosts.conf", "@DEMO@/hosts"),
           ("E", 1, 1, "mailpit", 1, "1.32.0", "http://127.0.0.1:18025/", "1.32.0")]
    for v in VERSIONS:
        blocker = "lampp-%s es la version activa. Cambia antes a otra version (o desactivala) y vuelve a intentarlo." \
            % v[0] if v[0] == ACTIVE else ""
        out.append(("V",) + v[:8] + (v[0], blocker))
        out.append(("R", v[0], v[8], v[9]))
    n = 0
    for folder, _kind, db, ver, _dom in PROJECTS:
        if db:
            n += 1
            out.append(("D", ver, db, NOW - n * 3 * DAY, "c"))
    # (una copia antigua de una base, en otra versión: la de la tienda, en la 8.2)
    out.append(("D", "8.2", "ps_ferreteria_norte", NOW - 60 * DAY, "i"))
    return lines(out)


def gui_proyectos():
    out = [("E", "web.local", LOADED)]
    out += [("P", p[0], "", "", "") for p in PROJECTS]
    out += [("R", p[2], p[0]) for p in PROJECTS if p[2]]
    return lines(out)


def gui_hosts():
    out = []
    for folder, kind, _db, _v, dom in PROJECTS:
        if dom:
            out.append(("F", dom, "www." + dom, folder, 0, 1, 1, 1 if kind == "ps" else 0, 0, ""))
    out.append(("F", "panaderialuna.test", "", "panaderia-luna", 0, 1, 1, 0, 1, ""))
    return lines(out)


def sizes():
    z, t = [], []
    for folder, _k, db, ver, _d in PROJECTS:
        if db:
            z.append(("Z", ver, db, 40 * 1024 * 1024 + len(db) * 7340032, NOW - DAY))
        t.append(("T", folder, 120 * 1024 * 1024 + len(folder) * 9437184, NOW - DAY))
    for v in VERSIONS:
        z.append(("Z", v[0], "mysql", 6332416, NOW - DAY))
    return lines(z), lines(t)


def gui_limpieza():
    """Configuración, Limpieza: lo que ocupa cada cosa (inventado)."""
    MB = 1024 * 1024
    return lines([("L", "descargas", 1288 * MB, 23), ("L", "copias", 412 * MB, 9), ("L", "correo", 3 * MB, 57),
                  ("L", "registros", 18 * MB, 31), ("L", "registros-versiones", 264 * MB, 48),
                  ("L", "caches-proyectos", 731 * MB, 18342), ("L", "temporales", 96 * MB, 412),
                  ("L", "sesiones", 2 * MB, 140)])


def gui_limpiar_proyecto():
    """⋮, Limpiar proyecto…: lo de cada WordPress y cada tienda (inventado)."""
    out = {}
    MB = 1024 * 1024
    for n, (folder, kind, *_rest) in enumerate(PROJECTS):
        if kind == "wp":
            rows = [("P", "cache", (40 + n * 13) * MB, 1200 + n * 97, "wp-content/cache"),
                    ("P", "registros", (2 + n) * MB, 3, "wp-content/debug.log,wp-content/uploads/wc-logs/*.log")]
            if n == 0:
                rows.append(("P", "actualizaciones", 6 * MB, 214, "wp-content/upgrade,wp-content/upgrade-temp-backup"))
        elif kind == "ps":
            rows = [("P", "cache", (180 + n * 21) * MB, 5400 + n * 311, "var/cache,cache/smarty/compile,cache/smarty/cache"),
                    ("P", "registros", (9 + n) * MB, 12, "var/logs,modules/*/logs/*.log")]
        else:
            continue
        out["gui-limpiar-proyecto_" + folder] = lines(rows)
    return out


def gui_docker():
    out = [("S", 1, 1, "29.1.3", 1, 0),
           ("V", "8.5 8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2 7.1 7.0 5.6", "11.8 11.4 10.11 10.6 10.5 10.4")]
    for folder, php, maria, state, db, vers in DOCKER:
        slug = folder
        out.append(("P", slug, folder, php, maria, "%s-php%s.docker.test" % (slug, php.replace(".", "")),
                    "marcha" if state == "marcha" else "parado", db, "web", "web", php, "wp", vers, ""))
    out.append(("W", "127.0.0.2", 80, 443, "marcha", 1, "docker.test", 1))
    for folder, php, _m, state, _db, _v in DOCKER:
        up = state == "marcha"
        out.append(("C", "nexum-%s-php%s" % (folder, php.replace(".", "")), "nexum-php:" + php,
                    "running" if up else "exited", "Up 2 hours" if up else "Exited (0) 3 days ago", "", "nexum-" + folder,
                    "a1b2c3d4e5f6"))
    out.append(("C", "nexum-mariadb-11-8", "mariadb:11.8", "running", "Up 2 hours", "", "nexum-web", "0f1e2d3c4b5a"))
    out.append(("C", "nexum-web", "httpd:2.4", "running", "Up 2 hours", "127.0.0.2:80->80/tcp", "nexum-web", "9a8b7c6d5e4f"))
    out += [("I", "nexum-php", "8.4", "ab3024dccaee", "805MB", "13 days ago"),
            ("I", "nexum-php", "8.2", "d29d148f9005", "791MB", "2 weeks ago"),
            ("I", "mariadb", "11.8", "c4124d1afa87", "458MB", "2 weeks ago"),
            ("I", "httpd", "2.4", "a30cd4cd57f3", "177MB", "2 weeks ago"),
            ("I", "phpmyadmin", "5.2", "f54a37b908b2", "821MB", "4 days ago"),
            ("O", "nexum-mariadb-11-8-datos", "local")]
    return lines(out)


def repos():
    login, org = GITHUB
    out = [("C", login, org, "Organization", 12, len(REPOS))]
    for name, private, days, web, desc, state in REPOS:
        date = __import__("time").strftime("%Y-%m-%d", __import__("time").gmtime(NOW - days * DAY))
        prefix = ""
        out.append(("R", "%s/%s" % (org, name), name, private, date, "main", prefix, web, desc, state,
                    name if state == "clonado" else ""))
    return lines(out)


def vhosts():
    text = "# Virtual hosts compartidos por todas las versiones de lampp\n"
    text += "<VirtualHost *:80>\n    ServerName web.local\n    DocumentRoot /opt/htdocs/web.local\n" \
            "    ErrorLog logs/web.local-error_log\n</VirtualHost>\n"
    for folder, _k, _db, _v, dom in PROJECTS:
        if dom:
            text += "<VirtualHost *:443>\n    ServerName %s\n    ServerAlias www.%s\n    DocumentRoot /opt/htdocs/%s\n" \
                    "</VirtualHost>\n" % (dom, dom, folder)
    return text


def htdocs(root):
    for folder, kind, db, _v, _d in PROJECTS:
        p = os.path.join(root, folder)
        os.makedirs(p)
        if kind == "wp":
            os.makedirs(os.path.join(p, "wp-includes"))
            os.makedirs(os.path.join(p, "wp-admin"))
            with open(os.path.join(p, "wp-config.php"), "w") as f:
                f.write("<?php\ndefine('DB_NAME', '%s');\n" % db)
        elif kind == "ps":
            os.makedirs(os.path.join(p, "config"))
            with open(os.path.join(p, "config", "settings.inc.php"), "w") as f:
                f.write("<?php\n")
        with open(os.path.join(p, "index.html" if kind == "html" else "index.php"), "w") as f:
            f.write("<!-- ejemplo -->\n")
    for folder, kind, *_ in NODE:
        p = os.path.join(root, folder)
        os.makedirs(p)
        with open(os.path.join(p, "package.json"), "w") as f:
            f.write('{"name": "%s", "dependencies": {"%s": "*"}}\n' % (folder, kind.lower()))
    os.symlink(LOADED, os.path.join(root, "web.local"))


def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    z, t = sizes()
    data = gui_datos()
    files = {
        "gui-datos": data, "gui-proyectos": gui_proyectos(), "gui-hosts": gui_hosts(), "gui-servicios": SERVICES,
        "gui-ramas": BRANCHES, "gui-fechas": DATES, "componentes": COMPONENTS, "gui-al-dia": "no-php\n",
        "gui-bbdd-tamanos": z, "gui-proyectos-tamanos": t, "gui-docker": gui_docker(),
        "gui-docker-estadisticas": "T|12|16110338048\n",
        "gui-node": lines(("P",) + n for n in NODE),
        "github": lines([("G", 1, GITHUB[0], "gh", GITHUB[1], "")]),
        "repos": repos(), "tunel": "I|1|2026.10.0|2026.10.0\n",
        "correo": "Correo de pruebas encendido: lo que mandan las webs va a Mailpit\n",
        "httpd-vhosts.conf": vhosts(), "hosts": "127.0.0.1\tlocalhost\n127.0.0.1\tweb.local\n",
        "gui-limpieza": gui_limpieza(),
    }
    files.update(gui_limpiar_proyecto())
    # (gui-vuelta: varias de una vez, como las da el programa)
    files["gui-vuelta"] = "".join("@@%s|0\n%s" % (k, files[k]) for k in ("gui-datos", "gui-hosts", "gui-servicios", "gui-proyectos"))
    for name, text in files.items():
        with open(os.path.join(OUT, name if "." in name or name == "hosts" else name + ".txt"), "w", encoding="utf-8") as f:
            f.write(text)
    htdocs(os.path.join(OUT, "htdocs"))
    print("Datos de la demostración en %s (%d respuestas)" % (OUT, len(files)))


main()
