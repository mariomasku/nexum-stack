#!/usr/bin/env python3
# Ventana de Nexum Dev Stack (GTK 3 y Python 3.8: funciona desde Ubuntu 20.04).
# La escribe y la abre "lvm-instalador ventana". No repite la logica del instalador: lo ejecuta con
# los comandos gui-* (datos) y con los de siempre (use, instalar, actualizar, desinstalar...)
# dentro de una pseudoterminal, para que sudo funcione igual que en la terminal; la contraseña
# se pide en una ventana y se escribe en esa terminal.
import base64
import codecs
import fcntl
import html
import http.server
import json
import os
import pty
import re
import zlib
import shlex
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, GObject, Gtk

SCRIPT = os.path.abspath(sys.argv[1])
SIMULATE = os.environ.get("LVM_SIMULAR") == "1"
# Modo demostración (las capturas del manual): con LVM_DEMO=<carpeta> y solo en simulación, los comandos
# gui-* no llegan al script: sus respuestas son las de esa carpeta, con datos inventados
# (ayuda/herramientas/demo-linux.py). Nada de este equipo sale en la ventana
DEMO = os.environ.get("LVM_DEMO", "") if SIMULATE else ""
# Programas del sistema: el PATH de la sesion puede llevar delante carpetas tuyas (~/.local/bin),
# donde un sudo, un bash o un pkexec falso recibiria la contraseña que se escribe en la ventana
os.environ["PATH"] = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
for _k in [k for k in os.environ if k.startswith(("LD_", "PYTHON", "BASH_FUNC_"))
           or k in ("BASH_ENV", "ENV", "IFS", "CDPATH", "SHELLOPTS", "BASHOPTS", "PS4", "GLOBIGNORE")]:
    del os.environ[_k]
APP_ID = "dev.hexer.LamppVersionManager"
# Parches de PHP sin soporte que se compilan con el arreglo de PHP2Shell (PHP2SHELL_BACKPORTS del script)
PHP2SHELL_BACKPORTS = ("7.4.33", "8.0.30", "8.1.34")
ICON = "lampp-version-manager"
LOG_DIR = os.path.expanduser("~/.lvm-instalador")
PROJECTS_FILE = os.path.join(LOG_DIR, "proyectos")
# Apartados de la ventana que se han plegado (uno por línea): siguen plegados al volver a abrirla
FOLDED_FILE = os.path.join(LOG_DIR, "ventana-plegados")


def is_ps_db(db):
    """Base de una tienda PrestaShop: suelen llamarse ps_<tienda>."""
    return db.lower().startswith("ps_")


# Proyectos de /opt/htdocs (LVM_HTDOCS solo para pruebas)
HTDOCS = os.environ.get("LVM_HTDOCS", "/opt/htdocs")
# (en la demostración, la de ejemplo: nunca la de verdad. El script quita LVM_HTDOCS fuera de las pruebas)
if DEMO:
    HTDOCS = os.path.join(DEMO, "htdocs")
DB_RULES = [
    ("wp-config.php", r"""^[ \t]*define\(\s*['"]DB_NAME['"]\s*,\s*['"]([^'"]+)"""),
    ("app/config/parameters.php", r"""['"]database_name['"]\s*=>\s*['"]([^'"]+)"""),
    ("config/settings.inc.php", r"""define\(\s*['"]_DB_NAME_['"]\s*,\s*['"]([^'"]+)"""),
    (".env", r"""^\s*DB_DATABASE\s*=\s*["']?([^"'\s#]+)"""),
]


# Visual Studio Code, según cómo se haya instalado: .deb o .rpm (el nuevo y el antiguo), snap,
# flatpak o el paquete de Arch
VSCODE_IDS = ("com.microsoft.VSCode.desktop", "code.desktop", "code_code.desktop",
              "com.visualstudio.code.desktop", "visual-studio-code.desktop")


def vscode_app():
    """Acceso de Visual Studio Code (None si no está instalado)."""
    for app_id in VSCODE_IDS:
        try:
            app = Gio.DesktopAppInfo.new(app_id)
        except (TypeError, GLib.Error):
            app = None
        if app is not None:
            return app
    return None


# Ancho de los campos del formulario de la pestaña Hosts (como los de Bases de datos)
COMBO_CHARS = 24


def narrow(combo, chars=COMBO_CHARS):
    """Desplegable de ancho fijo: los nombres largos se cortan con «…» en lugar de ensanchar
    toda la pestaña."""
    for cell in combo.get_cells():
        cell.set_property("ellipsize", 3)  # Pango.EllipsizeMode.END
        cell.set_property("width-chars", chars)
        cell.set_property("max-width-chars", chars)
    return combo


def host_switch_tip(h):
    """Lo que dice el interruptor de un dominio al dejar el ratón encima."""
    if h["name"].lower().endswith(".local"):
        return "Apagar este .local" if h["fake"] else "Encender este .local"
    return "Host falseado" if h["fake"] else "Falsear Host"


def hosts_view_text(hosts, path, vhosts, text):
    """Lo que enseña el visor del fichero de hosts: los dominios que se pueden falsear (los que tienen
    vhost, estén o no en el fichero) y, debajo, el fichero tal cual."""
    head = ["# DOMINIOS QUE SE PUEDEN FALSEAR (tienen vhost%s)" % (" en %s" % vhosts if vhosts else "")]
    states = []
    for h in hosts:
        local = h["name"].lower().endswith(".local")
        states.append(("encendido" if h["fake"] else "apagado") if local
                      else ("falseado" if h["fake"] else "sin falsear"))
    state_w = max([len(x) for x in states] or [0])
    name_w = max([len(h["name"]) for h in hosts] or [0])
    for h, state in zip(hosts, states):
        head.append("#   %s  %s  ->  %s" % (state.ljust(state_w), h["name"].ljust(name_w),
                                            h["folder"] or "sin carpeta"))
    if not hosts:
        head.append("#   (ninguno)")
    head += ["#", "# CONTENIDO DE %s" % path, ""]
    return "\n".join(head) + "\n" + text


def project_folders():
    """Carpetas de proyectos de /opt/htdocs (sin enlaces como web.local ni ocultas)."""
    try:
        return sorted((n for n in os.listdir(HTDOCS) if not n.startswith(".")
                       and not os.path.islink(os.path.join(HTDOCS, n))
                       and os.path.isdir(os.path.join(HTDOCS, n))), key=str.lower)
    except OSError:
        return []


def project_kind(folder):
    """ps (tienda PrestaShop, como is_prestashop del script), wp (WordPress) o vacío."""
    path = os.path.join(HTDOCS, folder)
    if "prestashop" in folder.lower() or os.path.isdir(os.path.join(path, "src/PrestaShopBundle")) \
            or os.path.isfile(os.path.join(path, "classes/PrestaShopAutoload.php")) \
            or os.path.isfile(os.path.join(path, "app/config/parameters.php")) \
            or os.path.isfile(os.path.join(path, "config/settings.inc.php")):
        return "ps"
    if os.path.isfile(os.path.join(path, "wp-config.php")) or \
            os.path.isdir(os.path.join(path, "wp-includes")):
        return "wp"
    return ""


# Lo que se hace con la configuración del proyecto al subirle una base nueva
PROJECT_CONFIG_TEXT = {
    "wp": "su wp-config.php se rehace con la plantilla de este equipo para usar esta BBDD",
    "ps": "su parameters.php (o settings.inc.php) pasa a usar esta BBDD y se vacía su caché",
}


def name_match_project(db, folders):
    """Carpeta que se llama como la base: wp_ajoselpajizo → dob-wordpress-ajoselpajizo (la base
    sin wp_ ni ps_, al final del nombre). Si hay varias, la del mismo tipo (WordPress o tienda)."""
    low = db.lower()
    tails = {low}
    if low[:3] in ("wp_", "ps_") and len(low) > 3:
        tails.add(low[3:])
    hits = [f for f in folders if any(f.lower() == v or f.lower()[-len(v) - 1:] in
                                     ("-" + v, "." + v, "_" + v) for v in tails)]
    if len(hits) > 1 and low[:3] in ("wp_", "ps_"):
        hits = [f for f in hits if project_kind(f) == low[:2]] or hits
    return hits[0] if len(hits) == 1 else None


def guess_project(db, ver=None):
    """Carpeta del proyecto de una base: la vinculada (~/.lvm-instalador/proyectos; la de la
    versión, si se indica, manda sobre la de todas), la única cuya configuración la usa o la que se
    llama como la base. None si no se sabe o si en esa versión está desvinculada."""
    folders = project_folders()
    saved = per = None
    try:
        with open(PROJECTS_FILE, encoding="utf-8") as f:
            for line in f.read().splitlines():
                if line.startswith(db + "="):
                    saved = line.split("=", 1)[1]
                elif ver and line.startswith("%s@%s=" % (db, ver)):
                    per = line.split("=", 1)[1]
    except OSError:
        pass
    if per is not None:
        return per if per in folders else None
    if saved in folders:
        return saved
    users = [f for f in folders if project_db(f) == db]
    if len(users) == 1:
        return users[0]
    return name_match_project(db, folders)


def docker_status_text(status):
    """Estado de un contenedor en español: «Up 2 minutes» → «en marcha · 2 min»."""
    units = [(r"(\d+) seconds?", r"\1 s"), (r"Less than a second", "1 s"), (r"(\d+) minutes?", r"\1 min"),
             (r"About a minute", "1 min"), (r"About an hour", "1 h"), (r"(\d+) hours?", r"\1 h"),
             (r"(\d+) days?", r"\1 días"), (r"(\d+) weeks?", r"\1 semanas"), (r"(\d+) months?", r"\1 meses")]
    text = status
    for rx, rep_ in units:
        text = re.sub(rx, rep_, text)
    text = re.sub(r"\s*\((healthy|unhealthy|health: starting)\)", "", text)
    m = re.match(r"Up (.+)$", text)
    if m:
        return "en marcha · %s" % m.group(1)
    m = re.match(r"Exited \((\d+)\) (.+) ago$", text)
    if m:
        return "parado hace %s%s" % (m.group(2), "" if m.group(1) == "0" else " (error %s)" % m.group(1))
    return {"Created": "creado", "Restarting": "reiniciándose", "Paused": "en pausa"}.get(text.split(" ")[0], text)


def docker_slug(folder):
    """Nombre corto de un proyecto en Docker (como docker_slug del script)."""
    s = re.sub(r"[^a-z0-9]+", "-", folder.lower()).strip("-")[:40].rstrip("-")
    return s or "proyecto"


# Final de los dominios del Apache de Docker (gui-docker, W): docker.local o, con el DNS comodín, docker.test
DOCKER_TLD = ["docker.local"]


def docker_web_domain(p, v):
    """Dominio de una versión de PHP de un proyecto del Apache de Docker (docker_web_domain del script):
    el de la tienda (uno solo) o <proyecto>-php83.docker.local (o .docker.test)."""
    if p.get("kind") == "ps":
        return "%s.%s" % (p["slug"], DOCKER_TLD[0])
    return "%s-php%s.%s" % (p["slug"], v.replace(".", ""), DOCKER_TLD[0])


def docker_pma_domain():
    return "pma." + DOCKER_TLD[0]


def copy_name(db, php):
    """Nombre propuesto para la copia de una BBDD en otra versión: sin el sufijo de versión que
    traiga y con el de la de destino (wp_tienda_8_4 → wp_tienda_8_5)."""
    base = re.sub(r"[_-]\d+_\d+(_\d+)?$", "", db) or db
    name = "%s_%s" % (base, "_".join(php.split(".")[:2]))
    return name if len(name) <= 64 else db


def write_links(changes):
    """Guarda vínculos (base, versión, carpeta; carpeta vacía = ninguna) en
    ~/.lvm-instalador/proyectos, como base@versión=carpeta. Devuelve el error o None."""
    keys = {"%s@%s" % (db, ver) for db, ver, _ in changes}
    lines = []
    try:
        with open(PROJECTS_FILE, encoding="utf-8") as f:
            lines = [l for l in f.read().splitlines() if l and l.split("=", 1)[0] not in keys]
    except OSError:
        pass
    lines += ["%s@%s=%s" % c for c in changes]
    try:
        os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
        with open(PROJECTS_FILE + ".nuevo", "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        os.replace(PROJECTS_FILE + ".nuevo", PROJECTS_FILE)
    except OSError as exc:
        return str(exc)
    return None


def project_db(folder):
    """Base de datos de la configuración de un proyecto (vacío si no tiene)."""
    for rel, rx in DB_RULES:
        path = os.path.join(HTDOCS, folder, rel)
        # Solo un fichero normal de hasta 2 MB, sin enlaces y sin esperar (un FIFO o un enlace a
        # /dev/zero de un proyecto colgarian la ventana)
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode) or st.st_size > 2000000:
                continue
            with os.fdopen(fd, errors="replace") as fh:
                fd = None
                m = re.search(rx, fh.read(2000000), re.M)
        except OSError:
            continue
        finally:
            if fd is not None:
                os.close(fd)
        if m:
            # Solo nombres de base validos (la configuracion la trae el proyecto)
            return m.group(1) if re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", m.group(1)) else ""
    return ""


# Registros mayores que esto no se abren en el editor de textos (solo «Ver el final»)
LOG_OPEN_MAX = 20 * 1024 * 1024
APACHE_ERROR_LOG = "/opt/lampp/logs/error_log"
# Dominio de un proyecto nuevo (pestaña Hosts): mitienda.com, sub.mitienda.es…
DOMAIN_RX = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$")


def clean_domain(text):
    """Dominio escrito o pegado como direccion (https://www.mitienda.com/tienda): solo el nombre."""
    d = re.sub(r"^[A-Za-z][A-Za-z0-9+.-]*://", "", text.strip())
    return re.split(r"[/?#:\s]", d, maxsplit=1)[0].rstrip(".")


# Marca con la que sudo pide la contraseña (SUDO_PROMPT). Distinta en cada ventana: un volcado o un
# fichero de un proyecto que se muestre en el registro no puede imitarla para que salga el cuadro
SUDO_MARK = "@@LVM-SUDO-%s@@" % os.urandom(8).hex()
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b[78()][0-9A-Za-z]?")
GREEN = "#45A57C"

# Tramos de la barra de la pila propia (los mismos que usa el script en whiptail)
CSS = """
.grupo-titulo { font-weight: bold; }
.nv-apartado-titulo { font-weight: bold; font-size: 1.05em; }
/* Título de un apartado plegable: sin el relleno del botón, alineado con los demás títulos */
button.plegable { padding: 0 4px 0 0; min-height: 0; }
/* Arrancar, reiniciar y parar la versión activa */
button.control-grande { min-width: 40px; min-height: 40px; padding: 4px; }
/* Consola de Docker (pestaña Docker): oscura, con letra de terminal, como Docker Desktop */
.consola-docker { background-color: #1d2228; border-radius: 10px; padding: 14px 16px; }
.consola-docker label { color: #d7dee6; font-family: monospace; font-size: 0.92em; }
.consola-docker label.consola-titulo { font-family: inherit; font-size: 1.15em; font-weight: bold; color: #ffffff; }
.consola-docker label.consola-tenue { color: #8c99a6; }
.consola-docker label.consola-verde { color: #4cc38a; }
.consola-docker label.consola-gris { color: #6d7884; }
.info { color: alpha(currentColor, 0.55); }
.info:hover { color: currentColor; }
.subtitulo { font-size: smaller; }
list.caja {
  background-color: alpha(@theme_fg_color, 0.045);
  border: 1px solid alpha(@theme_fg_color, 0.12);
  border-radius: 12px;
}
list.caja > row {
  border-bottom: 1px solid alpha(@theme_fg_color, 0.10);
  background-color: transparent;
  outline: none;
}
list.caja > row:hover { background-color: alpha(@theme_fg_color, 0.04); }
list.caja > row:selected, list.caja > row:selected:hover { background-color: alpha(GREEN, 0.25); }
list.caja > row:last-child { border-bottom: none; }
list.caja > row:first-child { border-top-left-radius: 12px; border-top-right-radius: 12px; }
list.caja > row:last-child { border-bottom-left-radius: 12px; border-bottom-right-radius: 12px; }
list.anidada { background-color: alpha(@theme_fg_color, 0.03); border-top: 1px solid alpha(@theme_fg_color, 0.10); }
list.anidada > row { border-bottom: 1px solid alpha(@theme_fg_color, 0.08); background-color: transparent; }
list.anidada > row:last-child { border-bottom: none; }
.tag { font-weight: bold; font-size: smaller; }
.pastilla { padding: 2px 10px; border-radius: 999px; font-weight: bold; font-size: smaller; }
.pastilla.activa { background-color: GREEN; color: white; }
.estado { font-weight: bold; font-size: smaller; }
.estado.estable { color: GREEN; }
.estado.seguridad { color: #c88800; }
.estado.soporte-no { color: #e01b24; }
.etiqueta-parche { font-weight: bold; font-size: smaller; }
.etiqueta-parche.seguridad-parche { color: #3584e4; }
.fecha-version { font-size: smaller; }
.boton-proyecto { min-width: 34px; min-height: 34px; padding: 2px 4px; }
.aviso-rojo { color: #e01b24; font-weight: bold; }
.asistente { padding: 14px 16px; border-radius: 12px; background-color: alpha(@theme_fg_color, 0.05);
             border: 1px solid alpha(@theme_fg_color, 0.10); }
.asistente-paso { font-weight: bold; }
/* Mensajes emergentes (al dejar el ratón encima): como el resto de la ventana, gris oscuro y con
   las esquinas redondeadas, en vez del negro del tema */
tooltip, tooltip.background { background-color: rgba(62, 62, 67, 0.98); color: #ececec;
             border-radius: 10px; border: 1px solid rgba(255, 255, 255, 0.10); padding: 6px 10px; }
tooltip decoration { background-color: transparent; border-radius: 10px; }
tooltip label { color: #ececec; padding: 2px 4px; }
button.icono-verde image { color: GREEN; }
button.icono-rojo image { color: #e01b24; }
button.icono-azul image { color: #3584e4; }
button.verde, button.verde:hover, button.verde:active {
  background-image: none; background-color: GREEN; color: white;
  border-color: shade(GREEN, 0.85); box-shadow: none; text-shadow: none;
}
button.verde:hover { background-color: shade(GREEN, 1.08); }
button.verde:disabled { background-color: alpha(GREEN, 0.4); color: alpha(white, 0.7); }
/* Todos los botones: transición suave y, al pasar el ratón, un poco más claros */
button { transition: background-color 120ms ease-out, box-shadow 120ms ease-out, color 120ms ease-out; }
button:hover:not(.verde):not(:disabled) { box-shadow: inset 0 0 0 999px alpha(@theme_fg_color, 0.07); }
button.verde:active { background-color: shade(GREEN, 0.92); }
/* Cargar proyecto: contenedor hundido con el título dentro */
.hundido {
  background-color: alpha(black, 0.16);
  border: 1px solid alpha(@theme_fg_color, 0.10);
  border-radius: 14px;
  box-shadow: inset 0 2px 5px alpha(black, 0.30), inset 0 1px 1px alpha(black, 0.25);
  padding: 32px 20px;
}
.hundido-titulo { font-weight: bold; font-size: 1.2em; }
.hundido entry.buscador {
  min-height: 38px; padding-left: 10px; padding-right: 10px; font-size: 1.05em;
  border-radius: 10px;
}
button.pildora { border-radius: 999px; padding: 8px 28px; }
.punto-verde { color: GREEN; }
.punto-gris { color: alpha(@theme_fg_color, 0.35); }
.error { color: #e01b24; }
.aviso { color: #c88800; }
.texto-activa { color: GREEN; font-weight: bold; }
switch:checked { background-image: none; background-color: GREEN; border-color: shade(GREEN, 0.85); }
progressbar progress { background-image: none; background-color: GREEN; border-color: GREEN; }
/* Barra lateral (como Configuración de Ubuntu) */
.lateral {
  background-color: alpha(@theme_fg_color, 0.035);
  border-right: 1px solid alpha(@theme_fg_color, 0.10);
}
list.barra-lateral { background-color: transparent; }
list.barra-lateral > row {
  margin: 2px 8px; padding: 12px 12px; min-height: 22px; border-radius: 10px;
  transition: background-color 120ms ease-out;
}
list.barra-lateral > row:hover { background-color: alpha(@theme_fg_color, 0.06); }
list.barra-lateral > row:selected, list.barra-lateral > row:selected:hover {
  background-color: alpha(@theme_fg_color, 0.11); color: @theme_fg_color;
}
list.barra-lateral > row:selected label { font-weight: bold; }
/* Icono de cada apartado: logotipo del paquete o símbolo, en un cuadrado redondeado */
.icono-seccion { background-color: alpha(@theme_fg_color, 0.07); border-radius: 8px; padding: 4px; }
.icono-servicio { background-color: alpha(@theme_fg_color, 0.07); border-radius: 12px; padding: 10px; }
.icono-seccion.verde-suave, .icono-servicio.verde-suave { background-color: alpha(GREEN, 0.16); color: GREEN; }
.icono-seccion.aviso-suave { background-color: alpha(#c88800, 0.16); color: #c88800; }
.titulo-grande { font-weight: bold; font-size: 1.25em; }
/* Contraseña de administrador */
.dialogo-clave headerbar { background: transparent; border: none; box-shadow: none; min-height: 28px; }
.clave-titulo { font-weight: bold; font-size: 1.15em; }
.candado { background-color: alpha(@theme_fg_color, 0.55); color: @theme_bg_color; border-radius: 999px; padding: 5px; }
entry.campo-clave { min-height: 38px; padding-left: 12px; padding-right: 12px; border-radius: 8px; }
button.boton-grande { min-height: 34px; border-radius: 8px; }
/* Diálogos: campos y desplegables algo más altos, y los botones con más sitio */
dialog entry { min-height: 34px; }
dialog combobox button, dialog spinbutton { min-height: 34px; }
dialog radiobutton, dialog checkbutton { padding-top: 2px; padding-bottom: 2px; }
dialog radiobutton > radio, dialog checkbutton > check { margin-right: 8px; }
messagedialog .dialog-action-box { margin-top: 6px; }
.opcion {
  border: 1px solid alpha(@theme_fg_color, 0.12); border-radius: 10px;
  background-color: alpha(@theme_fg_color, 0.03); padding: 10px 14px;
  transition: border-color 120ms ease-out, background-color 120ms ease-out;
}
.opcion.elegida { border-color: GREEN; background-color: alpha(GREEN, 0.08); }
/* Dentro de la tarjeta, el botón de radio sin su propio recuadro (el del foco del tema): la
   elegida ya se marca con el borde verde de la tarjeta */
.opcion radiobutton, .opcion radiobutton:focus, .opcion radiobutton:hover {
  outline-style: none; outline-width: 0; box-shadow: none; border: none; background: none;
}
/* Servicios: una tarjeta por servicio */
.servicio {
  background-color: alpha(@theme_fg_color, 0.045);
  border: 1px solid alpha(@theme_fg_color, 0.12);
  border-radius: 14px; padding: 16px 18px;
}
.servicio-nombre { font-weight: bold; font-size: 1.1em; }
.chip { padding: 1px 9px; border-radius: 999px; background-color: alpha(@theme_fg_color, 0.08); font-size: smaller; }
.pastilla.parada { background-color: alpha(@theme_fg_color, 0.12); }
.pastilla.segura { background-color: alpha(GREEN, 0.16); color: GREEN; }
.pastilla.peligro { background-color: alpha(#e01b24, 0.16); color: #e01b24; }
.firma { font-size: smaller; }
.log { font-family: monospace; font-size: 9pt; }
""".replace("GREEN", GREEN)
