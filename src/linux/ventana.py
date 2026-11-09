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


# ---------------------------------------------------------------- utilidades de interfaz

def label(text, *classes, xalign=0.0, **kw):
    lbl = Gtk.Label(label=text, xalign=xalign, **kw)
    for c in classes:
        lbl.get_style_context().add_class(c)
    return lbl


def css(widget, *classes):
    for c in classes:
        widget.get_style_context().add_class(c)
    return widget


def icon(name, size=16):
    img = Gtk.Image.new_from_icon_name(name, Gtk.IconSize.BUTTON)
    img.set_pixel_size(size)
    return img


# Logotipos de los paquetes (Simple Icons, CC0: un solo trazo en una caja de 24x24). Cada marca
# es de su dueño; se usan solo para identificar cada paquete
# Iconos actualizar e imagenes (upload3 y gallery-import, en outline): de Reicon, https://reicon.dev
# MIT License
#
# Copyright (c) 2025 REICON
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
LOGO_PATHS = {
    # (bases de datos: discos apilados; Node: su hexágono)
    "bbdd": "M 3.5 7 C 3.5 5.34 7.31 4 12 4 C 16.69 4 20.5 5.34 20.5 7 C 20.5 8.66 16.69 10 12 10 C 7.31 10 3.5 8.66 3.5 7 Z M 3.5 8.4 C 3.5 10.06 7.31 11.4 12 11.4 C 16.69 11.4 20.5 10.06 20.5 8.4 L 20.5 12 C 20.5 13.66 16.69 15 12 15 C 7.31 15 3.5 13.66 3.5 12 Z M 3.5 13.4 C 3.5 15.06 7.31 16.4 12 16.4 C 16.69 16.4 20.5 15.06 20.5 13.4 L 20.5 17 C 20.5 18.66 16.69 20 12 20 C 7.31 20 3.5 18.66 3.5 17 Z",
    "node": "M 10.61 2.8 C 12 2 12 2 13.39 2.8 L 19.27 6.2 C 20.66 7 20.66 7 20.66 8.6 L 20.66 15.4 C 20.66 17 20.66 17 19.27 17.8 L 13.39 21.2 C 12 22 12 22 10.61 21.2 L 4.73 17.8 C 3.34 17 3.34 17 3.34 15.4 L 3.34 8.6 C 3.34 7 3.34 7 4.73 6.2 Z",
    # (flecha de descarga: la tarea en segundo plano)
    "descarga": "M 10.6 3 L 13.4 3 L 13.4 11.6 L 17.2 7.8 L 19.2 9.8 L 12 17 L 4.8 9.8 L 6.8 7.8 L 10.6 11.6 Z M 4 19 L 20 19 L 20 21.6 L 4 21.6 Z",
    "actualizar": "M 17.53 7.53 C 17.823 7.237 17.823 6.763 17.53 6.47 L 12.53 1.47 C 12.39 1.329 12.199 1.25 12 1.25 C 11.801 1.25 11.61 1.329 11.47 1.47 L 6.47 6.47 C 6.177 6.763 6.177 7.237 6.47 7.53 C 6.763 7.823 7.237 7.823 7.53 7.53 L 11.25 3.811 L 11.25 15 C 11.25 15.414 11.586 15.75 12 15.75 C 12.414 15.75 12.75 15.414 12.75 15 L 12.75 3.811 L 16.47 7.53 C 16.763 7.823 17.237 7.823 17.53 7.53 Z M 21.212 19.109 C 21.249 18.647 21.25 18.052 21.25 17.2 L 21.25 14 C 21.25 13.586 21.586 13.25 22 13.25 C 22.414 13.25 22.75 13.586 22.75 14 L 22.75 17.232 C 22.75 18.045 22.75 18.701 22.707 19.232 C 22.662 19.778 22.568 20.258 22.341 20.703 C 21.982 21.408 21.408 21.982 20.703 22.341 C 20.258 22.568 19.778 22.662 19.232 22.707 C 18.701 22.75 18.045 22.75 17.232 22.75 L 6.768 22.75 C 5.955 22.75 5.299 22.75 4.769 22.707 C 4.222 22.662 3.742 22.568 3.298 22.341 C 2.592 21.982 2.018 21.408 1.659 20.703 C 1.432 20.258 1.338 19.778 1.293 19.232 C 1.25 18.701 1.25 18.045 1.25 17.232 L 1.25 14 C 1.25 13.586 1.586 13.25 2 13.25 C 2.414 13.25 2.75 13.586 2.75 14 L 2.75 17.2 C 2.75 18.052 2.751 18.647 2.788 19.109 C 2.825 19.563 2.895 19.824 2.995 20.021 C 3.211 20.445 3.555 20.789 3.979 21.005 C 4.176 21.105 4.437 21.174 4.891 21.212 C 5.353 21.249 5.948 21.25 6.8 21.25 L 17.2 21.25 C 18.052 21.25 18.647 21.249 19.109 21.212 C 19.563 21.174 19.824 21.105 20.021 21.005 C 20.445 20.789 20.789 20.445 21.005 20.021 C 21.105 19.824 21.174 19.563 21.212 19.109 Z",
    "imagenes": "M 9 10 C 10.105 10 11 9.105 11 8 C 11 6.895 10.105 6 9 6 C 7.895 6 7 6.895 7 8 C 7 9.105 7.895 10 9 10 Z M 13 2 L 9 2 C 4 2 2 4 2 9 L 2 15 C 2 20 4 22 9 22 L 15 22 C 20 22 22 20 22 15 L 22 10 M 18 2 L 18 8 L 20 6 M 18 8 L 16 6 M 2.67 18.95 L 7.6 15.64 C 8.39 15.11 9.53 15.17 10.24 15.78 L 10.57 16.07 C 11.35 16.74 12.61 16.74 13.39 16.07 L 17.55 12.5 C 18.33 11.83 19.59 11.83 20.37 12.5 L 22 13.9",
    # (el del botón Log: un folio con «LOG» en hueco, dibujado para Nexum)
    "log": "M 2 1 L 15 1 L 15 8 L 22 8 L 22 23 L 2 23 Z M 16.5 1 L 22 6.5 L 16.5 6.5 Z M 3.6 11 L 3.6 20 L 8.6 20 L 8.6 18.3 L 5.3 18.3 L 5.3 11 Z M 9.5 11 L 9.5 20 L 14.5 20 L 14.5 11 Z M 11.2 12.7 L 12.8 12.7 L 12.8 18.3 L 11.2 18.3 Z M 20.4 11 L 15.4 11 L 15.4 20 L 20.4 20 L 20.4 15.1 L 17.9 15.1 L 17.9 16.8 L 18.7 16.8 L 18.7 18.3 L 17.1 18.3 L 17.1 12.7 L 20.4 12.7 Z",
    # Cloudflare (Simple Icons 13.21.0, CC0)
    "cloudflare": (
        "M16.5088 16.8447c.1475-.5068.0908-.9707-.1553-1.3154-.2246-.3164-.6045-.499-1.0615-.5205l-8."
        "6592-.1123a.1559.1559 0 0 1-.1333-.0713c-.0283-.042-.0351-.0986-.021-.1553.0278-.084.1123-.1"
        "484.2036-.1562l8.7359-.1123c1.0351-.0489 2.1601-.8868 2.5537-1.9136l.499-1.3013c.0215-.0561."
        "0293-.1128.0147-.168-.5625-2.5463-2.835-4.4453-5.5499-4.4453-2.5039 0-4.6284 1.6177-5.3876 3"
        ".8614-.4927-.3658-1.1187-.5625-1.794-.499-1.2026.119-2.1665 1.083-2.2861 2.2856-.0283.31-.00"
        "69.6128.0635.894C1.5683 13.171 0 14.7754 0 16.752c0 .1748.0142.3515.0352.5273.0141.083.0844."
        "1475.1689.1475h15.9814c.0909 0 .1758-.0645.2032-.1553l.12-.4268zm2.7568-5.5634c-.0771 0-.161"
        "1 0-.2383.0112-.0566 0-.1054.0415-.127.0976l-.3378 1.1744c-.1475.5068-.0918.9707.1543 1.3164"
        ".2256.3164.6055.498 1.0625.5195l1.8437.1133c.0557 0 .1055.0263.1329.0703.0283.043.0351.1074."
        "0214.1562-.0283.084-.1132.1485-.204.1553l-1.921.1123c-1.041.0488-2.1582.8867-2.5527 1.914l-."
        "1406.3585c-.0283.0713.0215.1416.0986.1416h6.5977c.0771 0 .1474-.0489.169-.126.1122-.4082.175"
        "7-.837.1757-1.2803 0-2.6025-2.125-4.727-4.7344-4.727"
    ),
    # Docker (Simple Icons 13.21.0, CC0)
    "docker": (
        "M13.983 11.078h2.119a.186.186 0 00.186-.185V9.006a.186.186 0 00-.186-.186h-2.119a.185.18"
        "5 0 00-.185.185v1.888c0 .102.083.185.185.185m-2.954-5.43h2.118a.186.186 0 00.186-.186V3."
        "574a.186.186 0 00-.186-.185h-2.118a.185.185 0 00-.185.185v1.888c0 .102.082.185.185.185m0"
        " 2.716h2.118a.187.187 0 00.186-.186V6.29a.186.186 0 00-.186-.185h-2.118a.185.185 0 00-.1"
        "85.185v1.887c0 .102.082.185.185.186m-2.93 0h2.12a.186.186 0 00.184-.186V6.29a.185.185 0 "
        "00-.185-.185H8.1a.185.185 0 00-.185.185v1.887c0 .102.083.185.185.186m-2.964 0h2.119a.186"
        ".186 0 00.185-.186V6.29a.185.185 0 00-.185-.185H5.136a.186.186 0 00-.186.185v1.887c0 .10"
        "2.084.185.186.186m5.893 2.715h2.118a.186.186 0 00.186-.185V9.006a.186.186 0 00-.186-.186"
        "h-2.118a.185.185 0 00-.185.185v1.888c0 .102.082.185.185.185m-2.93 0h2.12a.185.185 0 00.1"
        "84-.185V9.006a.185.185 0 00-.184-.186h-2.12a.185.185 0 00-.184.185v1.888c0 .102.083.185."
        "185.185m-2.964 0h2.119a.185.185 0 00.185-.185V9.006a.185.185 0 00-.184-.186h-2.12a.186.1"
        "86 0 00-.186.186v1.887c0 .102.084.185.186.185m-2.92 0h2.12a.185.185 0 00.184-.185V9.006a"
        ".185.185 0 00-.184-.186h-2.12a.185.185 0 00-.184.185v1.888c0 .102.082.185.185.185M23.763"
        " 9.89c-.065-.051-.672-.51-1.954-.51-.338.001-.676.03-1.01.087-.248-1.7-1.653-2.53-1.716-"
        "2.566l-.344-.199-.226.327c-.284.438-.49.922-.612 1.43-.23.97-.09 1.882.403 2.661-.595.33"
        "2-1.55.413-1.744.42H.751a.751.751 0 00-.75.748 11.376 11.376 0 00.692 4.062c.545 1.428 1"
        ".355 2.48 2.41 3.124 1.18.723 3.1 1.137 5.275 1.137.983.003 1.963-.086 2.93-.266a12.248 "
        "12.248 0 003.823-1.389c.98-.567 1.86-1.288 2.61-2.136 1.252-1.418 1.998-2.997 2.553-4.4h"
        ".221c1.372 0 2.215-.549 2.68-1.009.309-.293.55-.65.707-1.046l.098-.288Z"),
    "php": (
        "M7.01 10.207h-.944l-.515 2.648h.838c.556 0 .97-.105 1.242-.314.272-.21.455-.559.55-1.049"
        ".092-.47.05-.802-.124-.995-.175-.193-.523-.29-1.047-.29zM12 5.688C5.373 5.688 0 8.514 0 "
        "12s5.373 6.313 12 6.313S24 15.486 24 12c0-3.486-5.373-6.312-12-6.312zm-3.26 7.451c-.261."
        "25-.575.438-.917.551-.336.108-.765.164-1.285.164H5.357l-.327 1.681H3.652l1.23-6.326h2.65"
        "c.797 0 1.378.209 1.744.628.366.418.476 1.002.33 1.752a2.836 2.836 0 0 1-.305.847c-.143."
        "255-.33.49-.561.703zm4.024.715l.543-2.799c.063-.318.039-.536-.068-.651-.107-.116-.336-.1"
        "74-.687-.174H11.46l-.704 3.625H9.388l1.23-6.327h1.367l-.327 1.682h1.218c.767 0 1.295.134"
        " 1.586.401s.378.7.263 1.299l-.572 2.944h-1.389zm7.597-2.265a2.782 2.782 0 0 1-.305.847c-"
        ".143.255-.33.49-.561.703a2.44 2.44 0 0 1-.917.551c-.336.108-.765.164-1.286.164h-1.18l-.3"
        "27 1.682h-1.378l1.23-6.326h2.649c.797 0 1.378.209 1.744.628.366.417.477 1.001.331 1.751z"
        "M17.766 10.207h-.943l-.516 2.648h.838c.557 0 .971-.105 1.242-.314.272-.21.455-.559.551-1"
        ".049.092-.47.049-.802-.125-.995s-.524-.29-1.047-.29z"
    ),
    "apache": (
        "M17.805 2.197v.066h.156v.44h.072v-.44h.156v-.066zm.9 0l-.175.353-.172-.353h-.087v.506h.0"
        "67V2.3l.172.35h.045l.172-.35v.404h.066v-.506zm-4.257 1c-.204.31-.424.66-.66 1.06l-.04.06"
        "2a44.457 44.457 0 00-1.265 2.29c-.187.36-.38.742-.577 1.146l2.267-.25c.66-.302.955-.578 "
        "1.242-.976a15.5 15.5 0 00.23-.342c.23-.363.46-.763.663-1.16.197-.386.37-.767.505-1.11.08"
        "3-.22.15-.422.198-.6.042-.158.074-.307.1-.45-.884.15-1.965.295-2.668.33zM11.894 7.78l-.0"
        "77.16c-.078.16-.157.32-.236.488-.086.18-.172.364-.26.552l-.132.287a75.265 75.265 0 00-1."
        "427 3.3c-.163.397-.327.807-.493 1.23-.15.38-.297.765-.45 1.164l-.02.06c-.15.396-.3.802-."
        "453 1.22l-.01.027.72-.08a.213.213 0 01-.042-.006c.863-.106 2.01-.75 2.75-1.547.342-.367."
        "652-.8.94-1.306.213-.377.413-.795.604-1.258.168-.405.328-.843.48-1.318-.196.105-.423.18-"
        ".673.235a2.184 2.184 0 01-.273.046c.806-.31 1.314-.905 1.683-1.64a2.816 2.816 0 01-.968."
        "428c-.06.012-.116.022-.174.03l-.043.006h.002c.278-.118.514-.248.718-.403a2.571 2.571 0 0"
        "0.637-.698l.063-.104.077-.154a8.107 8.107 0 00.367-.85l.03-.088a3.04 3.04 0 00.123-.463."
        "733.733 0 01-.094.065c-.243.145-.66.277-.996.34l.663-.074-.664.073h-.017l-.1.017c.006-.0"
        "03.01-.006.017-.008l-2.265.25-.013.022zM8.27 16.45c-.117.323-.236.654-.355.992l-.005.015"
        "c-.016.046-.032.094-.05.142-.08.227-.15.432-.31.9.264.12.475.435.675.793a1.44 1.44 0 00-"
        ".466-.99c1.293.06 2.41-.27 2.99-1.217.05-.084.096-.173.14-.268-.26.333-.59.474-1.2.44 0 "
        "0-.004 0-.005.002l.004-.002c.9-.404 1.354-.79 1.754-1.433.094-.153.186-.32.28-.503-.788."
        "81-1.702 1.04-2.664.865l-.72.078a6.43 6.43 0 00-.067.183zM15.42.112c-.376.222-1 .85-1.74"
        "8 1.763l.686 1.294c.48-.687.97-1.307 1.462-1.836l.058-.062c-.02.02-.04.04-.057.062-.16.1"
        "76-.644.74-1.375 1.863.703-.035 1.784-.18 2.666-.33.262-1.47-.258-2.142-.258-2.142s-.66-"
        "1.07-1.436-.61zm-3.084 6.402a40.253 40.253 0 011.306-2.26l.04-.064c.224-.352.45-.693.677"
        "-1.02l-.685-1.293-.157.192c-.197.245-.403.51-.613.79a39.853 39.853 0 00-2.016 2.97l-.022"
        ".038.893 1.763c.19-.378.38-.752.575-1.118zm-3.73 8.32c.158-.406.319-.81.483-1.225.156-.3"
        "94.32-.79.484-1.19a91.133 91.133 0 011.6-3.604l.205-.424c.12-.243.237-.485.36-.724a.125."
        "125 0 01.02-.04l-.895-1.763-.044.07c-.207.34-.414.687-.617 1.042a38.056 38.056 0 00-1.09"
        "2 2.04l-.094.193a24.573 24.573 0 00-1.258 3.087 18.492 18.492 0 00-.52 1.997l.896 1.77c."
        "117-.317.24-.638.364-.963zm-1.376-.476a13.38 13.38 0 00-.234 1.692c0 .02-.004.04-.005.06"
        "-.28-.45-1.03-.888-1.026-.884.537.778.944 1.55 1.005 2.31-.29.058-.684-.027-1.14-.195.47"
        "5.436.83.556.97.588-.434.03-.89.328-1.346.67.668-.27 1.21-.38 1.596-.29-.61 1.74-1.23 3."
        "655-1.843 5.69a.538.538 0 00.364-.354c.11-.368.84-2.786 1.978-5.965l.097-.27.028-.078c.1"
        "2-.332.246-.672.374-1.02l.09-.237v-.004L7.24 14.3c-.003.02-.01.04-.012.06z"
    ),
    "mariadb": (
        "M23.157 4.412c-.676.284-.79.31-1.673.372-.65.045-.757.057-1.212.209-.75.246-1.395.75-2.0"
        "2 1.59-.296.398-1.249 1.913-1.249 1.988 0 .057-.65.998-.915 1.32-.574.713-1.08 1.079-2.1"
        "4 1.59-.77.36-1.224.524-4.102 1.477-1.073.353-2.133.738-2.367.864-.852.449-1.515 1.036-2"
        ".203 1.938-1.003 1.32-.972 1.313-3.042.947a12.264 12.264 0 00-.675-.063c-.644-.05-1.023."
        "044-1.332.334L0 17.193l.177.088c.094.05.353.234.561.398.215.17.461.347.55.391.088.044.17"
        ".088.183.101.012.013-.089.17-.228.353-.435.581-.593.871-.574 1.048.019.164.032.17.43.17."
        "517-.006.826-.056 1.261-.208.65-.233 2.058-.94 2.784-1.4.776-.5 1.717-.998 1.956-1.042.0"
        "82-.02.354-.07.594-.114.58-.107 1.464-.095 2.587.05.108.013.373.045.6.064.227.025.43.057"
        ".454.076.026.012.474.037.998.056.934.026 1.104.007 1.3-.189.126-.133.385-.631.498-.985.2"
        "09-.643.417-.921.366-.492-.113.966-.322 1.692-.713 2.411-.259.499-.663 1.092-.934 1.395-"
        ".322.347-.315.36.088.315.619-.063 1.471-.397 2.096-.82.827-.562 1.647-1.691 2.19-3.03.10"
        "7-.27.22-.22.183.083-.013.094-.038.315-.057.498l-.031.328.353-.202c.833-.48 1.414-1.262 "
        "2.127-2.884.227-.518.877-2.922 1.073-3.976a9.64 9.64 0 01.271-1.042c.127-.429.196-.555.4"
        "8-.858.183-.19.625-.555.978-.808.72-.505.953-.75 1.187-1.205.208-.417.284-1.13.132-1.357"
        "-.132-.202-.284-.196-.763.006Z"
    ),
    "phpmyadmin": (
        "M5.463 3.476C6.69 5.225 7.497 7.399 7.68 9.798a12.9 12.9 0 0 1-.672 5.254 4.29 4.29 0 0 "
        "1 2.969-1.523c.05-.004.099-.006.148-.008.08-.491.47-3.45-.977-6.68-1.068-2.386-3-3.16-3."
        "685-3.365Zm1.777.037s2.406 1.066 3.326 5.547c.607 2.955.049 4.836-.402 5.773a7.347 7.347"
        " 0 0 1 4.506-1.994c.86-.065 1.695.02 2.482.233-.1-.741-.593-3.414-2.732-5.92-3.263-3.823"
        "-7.18-3.64-7.18-3.64Zm14.817 9.701-17.92 3.049a2.284 2.284 0 0 1 1.535 2.254 2.31 2.31 0"
        " 0 1-.106.61c.055-.027 2.689-1.275 6.342-2.034 3.238-.673 5.723-.36 6.285-.273a6.46 6.46"
        " 0 0 1 3.864-3.606zm-6.213 4.078c-2.318 0-4.641.495-6.614 1.166-2.868.976-2.951 1.348-5."
        "55 1.043C1.844 19.286 0 18.386 0 18.386s2.406 1.97 4.914 2.127c1.986.125 3.505-.822 5.31"
        "5-1.414 2.661-.871 4.511-.97 6.253-.975C19.361 18.116 24 19.353 24 19.353s-2.11-1.044-5."
        "033-1.72a13.885 13.885 0 0 0-3.123-.34Z"
    ),
    "perl": (
        "M11.638 0c-.148 0-.207.689-.252 2.925-.058 2.86-.07 2.949-.51 3.914-.36.793-1.623 2.676-"
        "2.037 3.04-.373.328-1.183 1.56-1.58 2.401-.71 1.504-.659 3.52-.04 5.047.518 1.194 1.262 "
        "2.156 2.46 3.182.94.805 1.23.919 1.375.544.049-.128-.162-.572-.483-1.018-.313-.436-.843-"
        "1.362-1.178-2.059-1.382-2.926-.7-5.357.902-8.045.89-1.393 1.403-2.642 1.579-3.852.22-1.5"
        "15.043-6.079-.236-6.079zm-.757 1.215c-.186 0-.228.26-.228 1.422 0 .782-.08 1.654-.177 1."
        "938-.312.914-1.154 1.737-3.482 3.404-1.684 1.205-3.096 2.652-3.64 3.732-1.666 3.299-.195"
        " 7.311 3.42 9.333 1.613.902 2.966 1.253 2.966.768 0-.126-.054-.228-.121-.228s-.632-.332-"
        "1.254-.738c-2.69-1.755-3.947-3.927-3.747-6.482.15-1.91.873-3.08 3.796-6.135 2.522-2.636 "
        "2.69-2.97 2.693-5.304.001-1.42-.036-1.71-.226-1.71zm1.508.632c-.103.017-.14.905-.142 2.9"
        "03l-.004 2.926-.744 2.812c-.83 2.54-.954 5.133-.345 7.725.558 2.202.796 2.638 1.567 2.85"
        "7.343.098.89.355 1.216.572.736.49 1.395.435 2.715-.232 1.92-.97 3.209-2.222 4.067-3.953."
        "745-1.648.856-3.71.068-5.35-.7-1.414-1.882-2.554-4.358-4.197-2.162-1.436-2.617-1.82-3.15"
        "-2.652-.322-.503-.369-.724-.308-1.444.04-.468.126-.978.192-1.134.101-.239.069-.268-.202-"
        ".182-.26.082-.34.027-.42-.286-.061-.245-.112-.372-.152-.365zm.714 4.586c.034-.007.135.11"
        "3.252.306.144.237 1.022 1 1.952 1.697 2.888 2.189 5.27 4.378 4.087 8.2-.405 1.146-.99 2."
        "07-1.963 3.098-.544.575-1.266 1.09-1.53 1.09-.047 0 .252-.43.664-.954 1.337-1.7 1.972-3."
        "718 1.79-5.674-.168-1.796-1.557-3.975-3.753-5.89-.912-.796-1.518-1.536-1.512-1.846 0-.01"
        "6.005-.025.013-.027zm-1.089 15.492c-.208-.006-.297.349-.297 1.121 0 .94.018.988.342.942."
        "302-.042.347-.15.387-.899.032-.613-.019-.902-.183-1.039-.097-.08-.18-.123-.249-.125zm-1."
        "052.28c-.124-.002-.226.14-.327.43-.085.245-.253.481-.373.527-.322.124-.264.55.075.55.162"
        " 0 .402-.109.534-.24.441-.442.579-.824.382-1.062-.111-.134-.206-.203-.29-.205zm2.074.063"
        "c-.312 0-.28.61.053 1.034.309.392.908.567.908.264 0-.252-.775-1.298-.961-1.298z"
    ),
    "xampp": (
        "M16.792,11.923c0.113,0.043,0.226,0.079,0.334,0.128c0.45,0.203,0.715,0.553,0.748,1.044 c0"
        ".041,0.634,0.044,1.271,0.002,1.905c-0.049,0.732-0.725,1.292-1.483,1.271c-0.735-0.021-1.3"
        "69-0.62-1.397-1.341 c-0.017-0.441-0.003-0.884-0.006-1.326c-0.001-0.239-0.003-0.242-0.245"
        "-0.243c-1.363-0.001-2.726,0.008-4.089-0.003 c-0.888-0.007-1.421,0.482-1.471,1.46c-0.019,"
        "0.38-0.1,0.727-0.357,1.018c-0.397,0.451-0.898,0.601-1.472,0.466 c-0.554-0.131-0.867-0.52"
        "2-1.035-1.048c-0.117-0.367-0.056-0.737,0.012-1.094c0.341-1.797,1.366-3.006,3.125-3.555 c"
        "0.357-0.112,0.731-0.166,1.105-0.166c0.94,0.001,1.881,0.001,2.821-0.001c0.128,0,0.257-0.0"
        "12,0.385-0.021 c0.702-0.051,1.166-0.511,1.22-1.352c0.004-0.064,0-0.129,0.001-0.193c0.011"
        "-0.788,0.605-1.396,1.393-1.425 c0.787-0.029,1.438,0.527,1.493,1.318c0.076,1.083-0.265,2."
        "046-0.913,2.907C16.903,11.751,16.819,11.816,16.792,11.923z M8.249,10.436c-0.258-0.008-0."
        "571,0.018-0.882-0.035c-0.536-0.09-0.876-0.39-1.02-0.916C6.19,8.912,6.25,8.388,6.698,7.96"
        " C7.154,7.526,7.694,7.4,8.285,7.645c0.52,0.216,0.859,0.731,0.89,1.293C9.2,9.382,9.178,9."
        "828,9.182,10.272 c0.001,0.116-0.043,0.167-0.161,0.165C8.781,10.434,8.542,10.436,8.249,10"
        ".436z M21.682,0H2.318C1.102,0,0.116,0.986,0.116,2.202 v19.317c0,1.37,1.111,2.481,2.481,2"
        ".481h18.807c1.37,0,2.481-1.111,2.481-2.481V2.202C23.884,0.986,22.898,0,21.682,0z M20.125"
        ",12.473c0.519,0.804,0.733,1.69,0.677,2.657c-0.108,1.886-1.413,3.474-3.25,3.916c-2.585,0."
        "623-4.566-0.923-5.233-2.794 c-0.109-0.304-0.16-0.622-0.224-0.985c-0.068,0.414-0.115,0.78"
        "9-0.264,1.134c-0.697,1.617-1.884,2.603-3.665,2.799 c-2.104,0.232-4.048-1.067-4.632-3.084"
        "c-0.25-0.863-0.175-1.747-0.068-2.625c0.08-0.653,0.321-1.268,0.632-1.848 c0.057-0.106,0.0"
        "57-0.184-0.01-0.285c-0.561-0.845-0.779-1.777-0.7-2.784C3.43,8.035,3.56,7.52,3.805,7.038 "
        "C4.52,5.626,6.09,4.427,8.193,4.626c1.849,0.175,3.562,1.77,3.83,3.564c0.013,0.09,0.039,0."
        "178,0.068,0.311 c0.044-0.241,0.076-0.439,0.118-0.636c0.344-1.63,1.94-3.335,4.201-3.357c2"
        ".292-0.021,3.99,1.776,4.31,3.446 c0.17,0.888,0.089,1.776-0.103,2.663c-0.112,0.517-0.31,1"
        ".008-0.524,1.492C20.034,12.245,20.043,12.345,20.125,12.473z"
    ),
    "github": "M 12 0.297 C 5.37 0.297 0 5.67 0 12.297 C 0 17.6 3.438 22.097 8.205 23.682 C 8.805 23.795 9.025 23.424 9.025 23.105 C 9.025 22.82 9.015 22.065 9.01 21.065 C 5.672 21.789 4.968 19.455 4.968 19.455 C 4.422 18.07 3.633 17.7 3.633 17.7 C 2.546 16.956 3.717 16.971 3.717 16.971 C 4.922 17.055 5.555 18.207 5.555 18.207 C 6.625 20.042 8.364 19.512 9.05 19.205 C 9.158 18.429 9.467 17.9 9.81 17.6 C 7.145 17.3 4.344 16.268 4.344 11.67 C 4.344 10.36 4.809 9.29 5.579 8.45 C 5.444 8.147 5.039 6.927 5.684 5.274 C 5.684 5.274 6.689 4.952 8.984 6.504 C 9.944 6.237 10.964 6.105 11.984 6.099 C 13.004 6.105 14.024 6.237 14.984 6.504 C 17.264 4.952 18.269 5.274 18.269 5.274 C 18.914 6.927 18.509 8.147 18.389 8.45 C 19.154 9.29 19.619 10.36 19.619 11.67 C 19.619 16.28 16.814 17.295 14.144 17.59 C 14.564 17.95 14.954 18.686 14.954 19.81 C 14.954 21.416 14.939 22.706 14.939 23.096 C 14.939 23.411 15.149 23.786 15.764 23.666 C 20.565 22.092 24 17.592 24 12.297 C 24 5.67 18.627 0.297 12 0.297",
    "wordpress": (
        "M21.469 6.825c.84 1.537 1.318 3.3 1.318 5.175 0 3.979-2.156 7.456-5.363 9.325l3.295-9.52"
        "7c.615-1.54.82-2.771.82-3.864 0-.405-.026-.78-.07-1.11m-7.981.105c.647-.03 1.232-.105 1."
        "232-.105.582-.075.514-.93-.067-.899 0 0-1.755.135-2.88.135-1.064 0-2.85-.15-2.85-.15-.58"
        "5-.03-.661.855-.075.885 0 0 .54.061 1.125.09l1.68 4.605-2.37 7.08L5.354 6.9c.649-.03 1.2"
        "34-.1 1.234-.1.585-.075.516-.93-.065-.896 0 0-1.746.138-2.874.138-.2 0-.438-.008-.69-.01"
        "5C4.911 3.15 8.235 1.215 12 1.215c2.809 0 5.365 1.072 7.286 2.833-.046-.003-.091-.009-.1"
        "41-.009-1.06 0-1.812.923-1.812 1.914 0 .89.513 1.643 1.06 2.531.411.72.89 1.643.89 2.977"
        " 0 .915-.354 1.994-.821 3.479l-1.075 3.585-3.9-11.61.001.014zM12 22.784c-1.059 0-2.081-."
        "153-3.048-.437l3.237-9.406 3.315 9.087c.024.053.05.101.078.149-1.12.393-2.325.609-3.582."
        "609M1.211 12c0-1.564.336-3.05.935-4.39L7.29 21.709C3.694 19.96 1.212 16.271 1.211 12M12 "
        "0C5.385 0 0 5.385 0 12s5.385 12 12 12 12-5.385 12-12S18.615 0 12 0"
    ),
    "prestashop": (
        "M11.558 1.034C5.174 1.034 0 6.21 0 12.592c0 1.258.201 2.47.574 3.597l.002-.007a12.415 12"
        ".415 0 01.53-1.787l.011-.03c.085-.222.179-.442.277-.66l.084-.181c.08-.171.165-.34.253-.5"
        "07.036-.068.07-.136.108-.203.02-.038.044-.073.064-.11.094-.166.19-.332.29-.493l.075-.114"
        "c.125-.195.256-.386.393-.573l.035-.05c.144-.193.295-.38.451-.563l.1-.118c.155-.177.315-."
        "35.481-.517l.099-.097a10.321 10.321 0 01.546-.503c.74-2.48 3.005-4.285 5.686-4.285 1.079"
        " 0 2.152.31 3.071.873a6.017 6.017 0 012.211 2.407l.007.015.04.074v.003l.004.002a9.925 9."
        "925 0 011.567 1.198c.04.037.081.071.12.109.002 0 .006.005.007.006l-.002-.006-.001-.004v-"
        ".003l.042-.084c.377-2.384 1.43-4.102 2.67-4.102.934 0 1.762.975 2.276 2.476l.005.016.001"
        ".002c.145.158.287.331.424.521l.007.01.021.067-.02-.078c-1.542-4.569-5.863-7.857-10.952-7"
        ".857zM9.927 5.477C7.586 5.52 5.34 7.132 4.574 9.365l-.012.034a10.14 10.14 0 011.315-.895"
        "c2.806-1.656 6.479-1.646 9.278.016-.895-1.653-2.631-2.819-4.5-3.004a5.14 5.14 0 00-.728-"
        ".039zm9.834.5a1.36 1.36 0 00-.39.067c-1.265.562-1.719 2.073-2.031 3.303l-.016.072c.365-."
        "62.808-1.215 1.396-1.642.835-.687 2.105-.655 2.916.053.308.326.141.008.031-.22-.342-.75-"
        "1.025-1.653-1.906-1.634zM21.67 7.98zm-9.32.335l-1.07 3.27-.002.005-.006.002-4.498 1.112h"
        "-.009l4.456 1.087c.105.11.227.205.36.28h.002c.042.024.085.045.129.065l.01.005c.041.018.0"
        "83.033.126.047l.021.008c.04.013.08.023.12.032l.033.008a1.677 1.677 0 00.318.033 1.546 1."
        "546 0 001.43-.948c.08-.186.123-.39.123-.604v-.011l-.001-.012c-.001-.054-.004-.107-.01-.1"
        "6l-.001-.002a1.506 1.506 0 00-.026-.153l-.001-.004a1.511 1.511 0 00-.096-.288v-.003a1.52"
        "1 1.521 0 00-.348-.49v-.003zm3.148.626c.048 1.008.036 2.046-.1 3.057-.17 2.018-1.19 3.79"
        "8-1.972 5.616l-.03.08-.035.086c1.51-1.522 3.17-3.04 3.969-5.082.383-.636.118-1.342-.115-"
        "1.976-.17-.877-1.069-1.278-1.717-1.781zm6.172.572l-.588 2.688a1.764 1.764 0 00-.047.2c-."
        "002.02-.007.04-.01.06a1.76 1.76 0 00-.016.222l-.002.031h.003c0 .628.297 1.136.663 1.137a"
        ".41.41 0 00.182-.045l.027-.015a.537.537 0 00.07-.047c.013-.01.024-.022.036-.033a.752.752"
        " 0 00.137-.168l.03-.054a1.23 1.23 0 00.052-.108l.017-.04c.02-.053.038-.108.053-.166l.002"
        "-.002.001-.003.404-.451-.407-.456v.001l-.02-.063zm-4.381.856c.69 1.716.85 3.707.091 5.43"
        "-.49 1.368-1.587 2.463-1.874 3.905.73.115 1.468.176 2.21.186 2.166.029 4.332-.42 6.284-1"
        ".365-2.04-2.869-4.121-5.755-6.711-8.156zm-4.948.977a.583.583 0 110 1.166.583.583 0 010-1"
        ".166zm9.352.37c.138 0 .249.19.249.426s-.111.426-.249.426c-.137 0-.248-.19-.248-.426 0-.2"
        "35.11-.426.248-.426zm-4.044.184c-.016.112-.033.209-.05.29l-.006.023c-.01.05-.022.094-.03"
        "3.128-.48 1.417-1.275 2.52-2.36 3.697-.147.16-.301.32-.459.484a58.883 58.883 0 01-1.196 "
        "1.205c-.112.11-.259.261-.425.436-.103.287-.22.61-.318.95-.044-.016-.086-.031-.131-.049-2"
        ".108-.815-3.519-1.904-3.519-1.904s1.086 1.414 2.915 2.74c.177.129.351.24.522.339-.075 1."
        "194.452 2.34 2.83 2.682a4.81 4.81 0 001.228.008l-.01-.029a.062.062 0 00-.004-.01s-.167-."
        "133-.379-.377a3.842 3.842 0 01-.584-.897 3.382 3.382 0 01-.266-.862 3.176 3.176 0 01-.00"
        "6-.972c.017-.12.04-.241.072-.366.093-.374.255-.772.507-1.192l.002-.003.241-.404c1.103-1."
        "86 1.797-3.275 1.506-5.441a8.943 8.943 0 00-.078-.476zm4.668.576zm.013.203l.003.036v.01c"
        "0 .013-.003.025-.003.038 0-.014.003-.028.003-.043 0-.014-.002-.026-.003-.04zm-.012.275v."
        "001l-.002.01-.002.014.004-.025zm1.353 5.928c-2.553 1.138-5.44 1.44-8.192 1.007-.14 1.108"
        ".384 2.218 1.214 2.93l.012.01c2.703-.433 4.975-2.168 6.966-3.946z"
    ),
    # Mailpit (correo de pruebas): su logotipo (server/ui/mailpit.svg de la 1.32.0, MIT), con sus dos
    # trazos llevados a la caja de 24x24 y en un solo color
    "mailpit": (
        "M2.235 0.96l9.771 9.782L21.836 0.96zM0.935 2.597l11.038 10.826 11.105-10.792-0.034 6.682L12."
        "141 13.757l2.751 2.289-1.476 1.086-7.549 0.033c-0.878-0.004-4.695-3.327-4.932-7.484zM14.22 1"
        "4.031l9.78-3.933-1.457 10.398-2.149-1.657c-3.942 4.204-8.21 4.769-12.336 3.78S2.228 18.81 0."
        "935 16.163-0.122 10.596 0.516 7.993c0.205 1.907-0.238 2.96 1.157 6.098 1.145 2.068 2.615 3.7"
        "04 4.697 4.527 2.522 1.124 5.85 0.609 7.565-0.551l2.583-2.205z"
    ),
    # Bola del mundo (abrir el proyecto en el navegador), la de Material Icons
    "globo": (
        "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93"
        " 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1"
        "-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"
    ),
}

# Color de cada logotipo: el de la marca y, con el tema oscuro, uno algo más claro para que se vea
LOGO_COLORS = {"log": ("#15803D", "#4ADE80"), "bbdd": ("#0284C7", "#38BDF8"), "node": ("#5FA04E", "#6CC24A"), "descarga": ("#15803D", "#4ADE80"), "actualizar": ("#1C71D8", "#62A0EA"), "imagenes": ("#1C71D8", "#62A0EA"), "php": ("#777BB4", "#9A9ED6"), "apache": ("#D22128", "#EE5A4F"),
               "mariadb": ("#003545", "#C99A6E"), "phpmyadmin": ("#6C78AF", "#929CD2"),
               "perl": ("#39457E", "#7D95CF"), "xampp": ("#FB7A24", "#FB8A3C"),
               "wordpress": ("#21759B", "#55A6D2"), "prestashop": ("#DF0067", "#F0498F"),
               "globo": ("#1C71D8", "#62A0EA"), "docker": ("#2496ED", "#4FAEF2"),
               "mailpit": ("#00A87B", "#2FD3A4"), "cloudflare": ("#F38020", "#F6A35A"),
               "github": ("#181717", "#E6EDF3")}
# Los que se dibujan con trazo, no rellenos
LOGO_STROKED = {"imagenes"}
_logo_cache = {}


def dark_theme():
    """¿El tema es oscuro? (por el color de fondo de las ventanas)"""
    if "dark" not in _logo_cache:
        ctx = Gtk.Window().get_style_context()
        found, bg = ctx.lookup_color("theme_bg_color")
        _logo_cache["dark"] = found and (0.299 * bg.red + 0.587 * bg.green + 0.114 * bg.blue) < 0.5
    return _logo_cache["dark"]


def logo_pixbuf(name, size, scale, color=None):
    """Imagen del logotipo de un paquete a esa escala, en su color o en el que se indique."""
    key = (name, size, scale, color)
    if key not in _logo_cache:
        color = color or LOGO_COLORS[name][1 if dark_theme() else 0]
        paint = ('fill="none" stroke="%s" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"'
                 if name in LOGO_STROKED else 'fill="%s"') % color
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="%d" height="%d">'
               '<path %s d="%s"/></svg>' % (size * scale, size * scale, paint, LOGO_PATHS[name]))
        loader = GdkPixbuf.PixbufLoader.new_with_type("svg")
        loader.write(svg.encode())
        loader.close()
        _logo_cache[key] = loader.get_pixbuf()
    return _logo_cache[key]


def logo(name, size=18):
    """Logotipo de un paquete en su color, nítido también en pantallas con escala 2."""
    scale = max(1, Gdk.Display.get_default().get_monitor(0).get_scale_factor())
    img = Gtk.Image()
    img.set_from_surface(Gdk.cairo_surface_create_from_pixbuf(logo_pixbuf(name, size, scale), scale, None))
    return img


# Logotipos con su tipografía (Apariencia): los oficiales de Docker (docker.com), Node.js (nodejs.org; con
# letra oscura en el tema claro y clara en el oscuro) y PHP (php.net), en SVG comprimido
BRAND_SVG = {
    "docker": "eNqFVk1v2zgQvfdXCOqlC5AUvyWmtg976qEB9tRDLkXgOJaxWiewvHKKRf/7vkfKSdEmbhBLQ3I4M2/mzdiLcdpWu7tl/fn22+bw1dTV0z/DflzW/fH4eNU0p9NJnZx6OGwbq7VuoD6rXD0Nu/3frymalFKTT+tq2hzG3cN+WRsF29Nuc/rz4WlZ60pXxgZd2djVq8Xd5n5cLcbjt2GzelflPzUedfXfvKiq+90wXFX7h/3m47z3/d2LpvlF870NUd/fv6Zsf1BeD7tH+Xh77K+qfw/Dh/dcc/nHy0U+F02JbcHzv3CeU3ZWBoDDZn2EsdsRmUPgdXXa3R17oLY+qVRX/Wa37Y/LmnCb1aI524FYsG9fblvY264WtPyyieTB47VzXhijlVnLTjkZVJROKys76aMy0qlWqiRNUJ1M0iacWC+9Vt0A3ZDP8RG4t5atsrAlYc0JG3ACdeGSUJ3oKEHPtMoLblsP61Zzy0qXoJLgHuhwF9InvZbQNEkZYWkfAQgbRQdH2Igw5uDUi6gCjAfcidDmv295bFUSSePAORGpqOHIKC9dwE0TGLyB/w4RK4uAiElYOnISjqDJywDBiOf3M+Ze31wjFCsSguuli6qd+OizlNc318Yx0IsabWKYFzSsbZmQCxquZe6g8AkN8etxjhKldJejvKiRo/y9hv75+Iu+ITdf5Z33ubQuM885BKllJPFAnFSkiLqOwJ8lVFGjJllCqVDsCNyeZWYVv2Av9J4pMB1OenI0ThIEcmtpUUpPeoGUwlowz7tZurn20ZAFtqMm+KOlMySyh+MsMbrR2FkSz3uQpPF8ciWpUaR5523wMTEiA8dxrTMc3BExyRYR4T1mQSIkX6SYBDLV4o3zeWeWhGVvzReJJwZk4Wxcmg6d+0NotJIB0SMwBr4zGij5M675TWXqiOdrb2NqY8pGShpbpDEHll1kqaRxTl5g2H6WHGBiaHgOBcwaLHtMBAwUwyxxLLGtwYrAOiI7kaDOzOhKdkpGyI9Z8ozaighyJ1LXZ6ohBch2hw/9YJjN0tvAOt8Wzp35paNKQ0AFJTIdejwwDCOZGDnPYmQ9NDkY4Aszg6MuwOXEBwKBlczXt30aY2PmuFVuapXpkR+9tiR9yCll+hKnXJFGS1ScVGifnEzTw0MCXkHSyzzp0C3oIIZHCSRzhWSpSDlteVnIpc+pbPNAB+oiYa9Dz+s8moxHY/WhpS/HmeoKZ9DIhkWiOUojG9sLMjqHzr1L+DtDJbqYE5bwDVAKACxxbVl38pyYMjp+iWSpJ90mdhUHElIAcOxqK1h2vAhlioixLwOq2c4f/BZZ/Q9szgOv",
    "node-claro": "eNrlWNtOI0kS/ZVUzcu0tFlU3jNHGKnZ6d596NautBrePYXBaMsGYbfp5uv3nMgqjDGM2HkdCVzhzMjIuJ6I8ulmd60ebi63y1ljY2rUcnFzvdzOmtw1anezeDi//T5rOtUp7CouXt0Mw6xZ364Xjfq+GtabWbPcbu9+OTl5eHhoH1x7e399YruuO4Ho5ux0Nd/8V91czpp5o0j/tr7Z4sy3zeL+P3fzfvGv9W8bisItjfohn2/ps9n+GBazhlL09sfd4pfh2+pmPV/3C9xzN98uFa75SkW7f3a7VFqX8hJfHyetf7q6umpOzk5PKOLs9FoUgi73w88/zT8cCHG+LdmplNsUwtwrr+gEo01bnNNtMIOOrbFGuzaG3Ou2gMaybn3UbSxBtyZ73aaclGmtt9gwJH2y5FO2TZHibGiNy7rtimudxV7nE2TgEQcPQR6c2Yae4sBkIaY+Q7CqG0xuXXTadGDNZHJadm1Kmh+VCF258JATU99h2fGa4kUlPXLAoGeyQj/qD7XINlH10spp1TPOum1ThBG+EsHsrGmdx50KLHHUPo2bQ2g7E2FdMamHN0yAd1xRHjxZlBxJ0+Zgdxqyuqo+gmJFF4gJlVhauYiiESaqSQHyxO5uPKskWIxhKiogNlmH1jsz0mAKWXW8MEOM9pDh8c2ENOBLhtugZypzB52VfDxPCsQv08vF2J5CXGmTSzgSIW3PchCy1FM8EsYXJT6opEOowlN0xc8lvrxWZFpFmeYiQtkIC3ktss7RsbhXP+OZAqzGm/XkJi0JKskg7KSeSiZ8/tj5T6yafXF4ClC4sksIf4bboKyGucbCxNSFkY6IHApnTESJVOClQjBkxTFkSULWJSRJkKePUDhmmOBxHjVjYw2dQnp1YaTpJEYbZyg755FCBGAkI2A75nhk2Dokc2x9qeHQkntSr7k1nm6KdqJDS9/TEN5kHBZK8gq+S3GkQ5sLCgFrqbCUO5dVQSDhlNZnP0dtt5KJzA6IgEkm9lJ0Y6E4w5LQkCnEEnp5V+Zt8G2YsAa+CFKjEioaFryEKEsiQZcUak7VVJWUTeKwbCqJI8UpSQtPOoOCYtWNWIAlEap6Q/OQGW3uYiWlJHCSQY68RE4Vo2lnqvTKspC1ZcY4Sb7iA31pmHIh8lzwsdJIX5Siqp/VQO7SAOyqo1213w09S5LaVHmmDbBtLzusENsADTtRIkYCrXMMX8fwFO8raSRxOi4hCgI3lZRdpgzOajlb00jXbaHn+Ez0Gj+pYqeraNldUbZEp5ilYb31SL3q+myensAYZpeCzyU1YRfLtUAobffEfcSpMGEABUg3K72AsCrpkzPLpMpZIusdIVFSCWk25fxIBnaTMAI+1yBFMsoJtWSjMjvm/pKdyj6uBDmYIksoATwNXZbiLIWpWp8SIXloVulITVsU6i2EGmMf30IRrur7b+zmi91ifXt52ah+uLl7uUa08ah2RNvDs8HT2OzEdVKzROdCjEUFfrE13BnZYXtduyl8RSula1SA54ZfStPqxQAaA7PhoCIchQwAy4LcRo9D3D4CqohGLte4syyojhsYGuU6ThrscgwatMjOjbXWCeRmaUbZFulqRHxiuyEPEjfGjNQSxHZxFL83K12EDgCYq+VuMlw4YuXAnFDQdHFDMpBkFf+nFkE5DHbPLs5YZjgIGCRqcENOM61zeqFGPR4rvu0wdlgjvbyqoZ7USKqqQYsAK2JR/8zsPJldBOklZwTqYX4bO8ElLb56/CpYGTkTFYlOGUMI51WKarNUR/lEyZIpRT+5vOwQETMHRuNvwlIPa5OUT87TGlTjNINVJIeMWS8DoWWuUN0Xg7aUgChofcEece39lC6gvK1e8pOXDhw5SGI5SSx/dKEaLxy59Btc++jnC46oVtIjT3UhIDZyZP+4wrdUAPYJjuKUMI2AdpoA4zjRRsHVjEYE78YnR9GzXd0nVuZyMB7i+IgsQmHu03BWrqOm4TW6VobsdmXYyzm4R4337NWYpl43TZajqo8rdi2bcU9Bd5A5a5yvkR0VBUe6Ji96ZTCvgcfIkaTeXQri8Ley4AAUfHw1DcZi2KEpAr7/sFx4oacsY7zYQC+RD0teRmPHrsS6Aj6xxaXY/0H5lI2WKSvLG8pUU18M0h6XBjQOE/oRs6fK0U+lU7kZui4HukpGdRHnp307TC89weQ5FBeL7AFadJWHjdmUCQbMVKXPipSjYDpCzXKEmnv4gPB9S3HO/al+YjKUAYR41I2J85aT72QB4kSHY/SzjJKhv/F2Vt+onNiBBxyz860DDmCgxN9UJXVr0Pvj6UC8HsVXBj0xHIoQv18EJJipnT3UAkJ9TbuvtdVrtb2frzdXt/erWSPkMN8ufg6OveNvbIrR5qdX3Hpc3nt//1DdYtkAxIBXsz8TAwV6DfGl/F3aiSG+yJAjp0lw/pfsDyy4YxgMexREuVGaDe5VFMwVBVEjunK9qPNnZT4iYb381TKvHI8HGTN6oP8wJgs3xrXL6pUVXhxjkbEA9W/Z3yJtLSV8wTcUFV8s8ZIQnHLyHvTqDYu3b/j6/AaRYzhF54GXcbbAuM3uLFdr46RLym8Y1/X/cnG1OTsdbtaL+f0/7ueXN4v1Vn5v+b1R382s4XDiGvUDJAajiEU7a9DLC9ZAebwmNOp6PPj6jzNnp5vt7Z3ih+5vh9t7Vt/nfO5+pSKyd3t1tVlsZw0wrzliTO7zMWNxLxl//VjspyNGc8z2yZ6LBw6NftUJfXUC8CRXH2CaztUHMVcPtP6d9j+pbt5r40u+YFGu/pgvvTQy+vPkyytOO2L8eP7Zv9sbi+oN1NLoDAB7dQa0EmfUlf/PHV15U6lDRlveaWZ8p99yfDMQR+5g/f2bdUlHXB781veXQb6TyQkgK27wR9qz/wG5awL3",
    "node-oscuro": "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",
    "php": "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",
}
BRAND_RATIO = {"docker": 4.6642, "node-claro": 3.3375, "node-oscuro": 3.3375, "php": 1.854}
_brand_cache = {}


def brand_pixbuf(key, height, scale):
    k = (key, height, scale)
    if k not in _brand_cache:
        loader = GdkPixbuf.PixbufLoader.new_with_type("svg")
        h = height * scale
        loader.set_size(int(round(h * BRAND_RATIO[key])), h)
        loader.write(zlib.decompress(base64.b64decode(BRAND_SVG[key])))
        loader.close()
        _brand_cache[k] = loader.get_pixbuf()
    return _brand_cache[k]


def row_selected(widget):
    """¿Va en la fila elegida de una lista? (GTK no les pasa ese estado a los dibujos de dentro)"""
    row = widget.get_ancestor(Gtk.ListBoxRow)
    return row is not None and row.is_selected()


class BrandLogo(Gtk.DrawingArea):
    """El logotipo de Docker, Node o PHP con su tipografía. De un color (mono, o en la fila elegida) se
    pinta con el del texto; PHP, siempre en el suyo (de un color su óvalo taparía las letras)."""

    def __init__(self, name, height, mono=False):
        super().__init__()
        self.name, self.height, self.mono = name, height, mono
        key = "node-claro" if name == "node" else name
        self.set_size_request(int(round(height * BRAND_RATIO[key])), height)
        self.set_valign(Gtk.Align.CENTER)

    def do_draw(self, cr):
        scale = max(1, self.get_scale_factor())
        key = ("node-oscuro" if dark_theme() else "node-claro") if self.name == "node" else self.name
        pix = brand_pixbuf(key, self.height, scale)
        y = (self.get_allocated_height() * scale - pix.get_height()) / 2
        cr.save()
        cr.scale(1.0 / scale, 1.0 / scale)
        if self.name != "php" and (self.mono or row_selected(self)):
            c = self.get_style_context().get_color(self.get_state_flags())
            cr.set_source_rgba(c.red, c.green, c.blue, c.alpha)
            cr.mask_surface(Gdk.cairo_surface_create_from_pixbuf(pix, 1, None), 0, y)
        else:
            Gdk.cairo_set_source_pixbuf(cr, pix, 0, y)
            cr.paint()
        cr.restore()
        return False


# Parches nuevos dejados para luego («Ahora no»): la lista de entonces; el aviso vuelve si cambia
IGNORED_UPDATES_FILE = os.path.join(LOG_DIR, "parches-para-luego")
_ignored_sim = []


def updates_ignored(items):
    if _ignored_sim:
        return _ignored_sim[0] == "\n".join(sorted(items))
    try:
        with open(IGNORED_UPDATES_FILE, encoding="utf-8") as fh:
            return fh.read(20000) == "\n".join(sorted(items))
    except OSError:
        return False


def updates_ignore(items):
    text = "\n".join(sorted(items))
    if SIMULATE:
        _ignored_sim[:] = [text]
        return
    os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
    with open(IGNORED_UPDATES_FILE + ".nuevo", "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(IGNORED_UPDATES_FILE + ".nuevo", IGNORED_UPDATES_FILE)


# Menú lateral: sus apartados (clave, texto e icono) y cómo se ven (Apariencia: ~/.lvm-instalador/apariencia)
SIDEBAR = [("ENTORNO", [("proyectos", "Proyectos", "folder-symbolic"), ("repos", "Repositorios", "logo:github"),
                        ("versiones", "Versiones de PHP", "logo:php"), ("bbdd", "Bases de datos", "logo:bbdd"),
                        ("docker", "Docker", "logo:docker"), ("node", "Node", "logo:node")]),
           ("SISTEMA", [("dominios", "Dominios y hosts", "network-workgroup-symbolic"),
                        ("config", "Configuración", "emblem-system-symbolic")])]
# (siempre se ven: sin Configuración no se podrían volver a enseñar)
SIDEBAR_FIXED = ("proyectos", "config")
LOOK_FILE = os.path.join(LOG_DIR, "apariencia")
_look_sim = {}


def look_conf():
    """color (iconos en color), marcas (Docker, Node y PHP con su logotipo) y ocultos (apartados que no se ven)."""
    conf = dict(_look_sim)
    if not conf:
        try:
            with open(LOOK_FILE, encoding="utf-8") as fh:
                conf = json.loads(fh.read(4000))
        except (OSError, ValueError):
            conf = {}
    if not isinstance(conf, dict):
        conf = {}
    keys = {k for _g, items in SIDEBAR for k, _t, _i in items} - set(SIDEBAR_FIXED)
    hidden = conf.get("ocultos")
    return {"color": conf.get("color") is True, "marcas": conf.get("marcas") is True,
            "ocultos": {k for k in hidden if k in keys} if isinstance(hidden, list) else set()}


def look_save(conf):
    data = {"color": conf["color"], "marcas": conf["marcas"], "ocultos": sorted(conf["ocultos"])}
    if SIMULATE:
        _look_sim.clear()
        _look_sim.update(data)
        return
    os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
    with open(LOOK_FILE + ".nuevo", "w", encoding="utf-8") as fh:
        json.dump(data, fh)
    os.replace(LOOK_FILE + ".nuevo", LOOK_FILE)


class MonoLogo(Gtk.DrawingArea):
    """Logotipo de un solo color, el del texto de donde va (como los iconos simbólicos del tema): en
    la barra lateral, igual que los demás iconos, también al elegir el apartado o cambiar de tema."""

    def __init__(self, name, size=16, colored=False):
        super().__init__()
        self.name, self.size, self.colored = name, size, colored
        self.set_size_request(size, size)
        self.set_valign(Gtk.Align.CENTER)

    def do_draw(self, cr):
        c = self.get_style_context().get_color(self.get_state_flags())
        color = "#%02x%02x%02x" % (int(c.red * 255), int(c.green * 255), int(c.blue * 255))
        # (en color, el suyo; en la fila elegida, el del texto, que se lea sobre el azul)
        if self.colored and not row_selected(self):
            color, c = None, Gdk.RGBA(0, 0, 0, 1)
        scale = max(1, self.get_scale_factor())
        pix = logo_pixbuf(self.name, self.size, scale, color)
        cr.save()
        cr.scale(1.0 / scale, 1.0 / scale)
        Gdk.cairo_set_source_pixbuf(cr, pix, 0, (self.get_allocated_height() * scale - pix.get_height()) / 2)
        cr.paint_with_alpha(c.alpha)
        cr.restore()
        return False


def symbol(name, size=18):
    """Icono simbólico del tema (con otro de reserva si el tema no lo tiene)."""
    if not Gtk.IconTheme.get_default().has_icon(name):
        name = "applications-system-symbolic"
    return icon(name, size)


# Icono de cada apartado, por el principio de su título: ("logo", paquete) o ("icono", nombre,
# clase de color)
SECTION_ICONS = [
    ("Versión activa", ("logo", "php")),
    ("Instalar nuevas versiones de PHP", ("logo", "php")),
    ("Instaladas", ("logo", "xampp")),
    ("Hay un XAMPP sin registrar", ("logo", "xampp")),
    ("XAMPP sin registrar", ("logo", "xampp")),
    ("Otras opciones", ("icono", "view-more-symbolic", "")),
    ("Hay procesos de otras versiones", ("icono", "dialog-warning-symbolic", "aviso-suave")),
    ("BBDD por versión", ("logo", "mariadb")),
    ("Buscar una BBDD", ("icono", "system-search-symbolic", "")),
    ("Subir o actualizar una BBDD", ("icono", "document-send-symbolic", "")),
    ("Se puede entrar desde otros equipos", ("icono", "network-wired-symbolic", "aviso-suave")),
    ("phpMyAdmin antiguo", ("logo", "phpmyadmin")),
    ("Certificados en los que confía", ("icono", "channel-insecure-symbolic", "aviso-suave")),
    ("Servicios", ("icono", "network-server-symbolic", "")),
    ("Host falseado", ("icono", "security-high-symbolic", "")),
    ("Dominios de los vhosts", ("logo", "apache")),
    ("Nuevo proyecto con dominio falseado", ("icono", "folder-new-symbolic", "verde-suave")),
    ("Configuración", ("icono", "document-properties-symbolic", "")),
    ("Carpetas", ("icono", "folder-symbolic", "")),
    ("Programa", ("icono", "system-software-install-symbolic", "")),
    ("Información", ("icono", "dialog-information-symbolic", "")),
    ("Registro de errores", ("icono", "text-x-generic-symbolic", "")),
    ("Cargar proyecto", ("icono", "folder-open-symbolic", "verde-suave")),
    ("Docker sin root", ("logo", "docker")),
    ("Proyectos en Docker", ("logo", "docker")),
    ("Nuevo proyecto en Docker", ("logo", "docker")),
]


# Icono de cada fila, por su título: los títulos de los apartados no llevan icono, lo llevan las
# filas que contienen. Exactos (títulos cortos) y por el principio
ROW_ICONS_EXACT = {
    "Dominio": ("icono", "web-browser-symbolic", ""),
    "Carpeta": ("icono", "folder-symbolic", ""),
    "BBDD": ("logo", "mariadb"),
    "Proyecto": ("icono", "folder-open-symbolic", ""),
    "Proyectos": ("icono", "folder-symbolic", ""),
    "Novedades": ("icono", "starred-symbolic", ""),
    "Acerca de": ("icono", "help-about-symbolic", ""),
    "error_log": ("logo", "apache"),
}
ROW_ICONS = [
    ("Versiones sin proteger", ("icono", "network-wired-symbolic", "aviso-suave")),
    ("Abierto a la red", ("icono", "network-wired-symbolic", "aviso-suave")),
    ("phpMyAdmin con fallos", ("logo", "phpmyadmin")),
    ("MariaDB de lampp-", ("logo", "mariadb")),
    ("Proyectos con https", ("icono", "channel-insecure-symbolic", "aviso-suave")),
    ("Proyectos que avisan", ("icono", "channel-insecure-symbolic", "aviso-suave")),
    ("Webs reales que acepta", ("icono", "channel-insecure-symbolic", "aviso-suave")),
    ("Procesos que sobran", ("icono", "dialog-warning-symbolic", "aviso-suave")),
    ("XAMPP en /opt/lampp", ("logo", "xampp")),
    ("XAMPP oficiales", ("logo", "xampp")),
    ("XAMPP ", ("logo", "xampp")),
    ("PHP ", ("logo", "php")),
    ("Otro parche concreto", ("logo", "php")),
    ("Ninguna versión activa", ("logo", "php")),
    ("No hay ninguna versión", ("logo", "php")),
    ("lampp-", ("logo", "mariadb")),
    ("Ningún dominio falseado", ("icono", "security-high-symbolic", "")),
    ("web.local → ", ("icono", "dialog-warning-symbolic", "aviso-suave")),
    ("Fichero SQL", ("icono", "text-x-generic-symbolic", "")),
    ("BBDD de destino", ("logo", "mariadb")),
    ("Virtual hosts", ("logo", "apache")),
    ("Hosts del sistema", ("icono", "network-server-symbolic", "")),
    ("Copias de seguridad", ("icono", "drive-harddisk-symbolic", "")),
    ("Registros de instalaciones", ("icono", "document-open-recent-symbolic", "")),
    ("error_log de ", ("logo", "apache")),
    ("Buscar una versión nueva", ("icono", "software-update-available-symbolic", "")),
    ("Icono en el menú de aplicaciones", ("icono", "view-app-grid-symbolic", "")),
    ("Comandos de lvm-instalador", ("icono", "utilities-terminal-symbolic", "")),
    # Los pasos de una instalación o actualización (la lista de la ventana de la tarea)
    ("Descargas", ("icono", "folder-download-symbolic", "")),
    ("Descarga de XAMPP", ("logo", "xampp")),
    ("Instalador oficial de XAMPP", ("logo", "xampp")),
    ("Apache ", ("logo", "apache")),
    ("Perl ", ("logo", "perl")),
    ("ProFTPD ", ("icono", "folder-remote-symbolic", "")),
    ("MariaDB ", ("logo", "mariadb")),
    ("phpMyAdmin ", ("logo", "phpmyadmin")),
    ("Configuracion", ("icono", "emblem-system-symbolic", "")),
    # Correo de pruebas: el logotipo de Mailpit en todas sus filas
    ("Mailpit", ("logo", "mailpit")),
    ("Bandeja de entrada", ("logo", "mailpit")),
    # Tunel de Cloudflare
    ("cloudflared", ("logo", "cloudflare")),
    ("Túnel", ("logo", "cloudflare")),
]


def row_icon_spec(title):
    if title in ROW_ICONS_EXACT:
        return ROW_ICONS_EXACT[title]
    for prefix, spec in ROW_ICONS:
        if title.startswith(prefix):
            return spec
    return None


def section_icon(spec, size=20, cls="icono-seccion"):
    """Cuadrado redondeado con el logotipo o el símbolo de un apartado."""
    box = css(Gtk.Box(valign=Gtk.Align.CENTER), cls)
    if spec[0] == "logo":
        box.pack_start(logo(spec[1], size), False, False, 0)
    else:
        box.pack_start(symbol(spec[1], size), False, False, 0)
        if spec[2]:
            css(box, spec[2])
    return box


def section_icon_for(title):
    for prefix, spec in SECTION_ICONS:
        if title.startswith(prefix):
            return section_icon(spec)
    return None


def plural(n, one, many):
    return "%d %s" % (n, one if n == 1 else many)


def ver_tuple(v):
    return tuple(int(x) for x in re.findall(r"\d+", v or "")[:3])


def pma_outdated(php, pma):
    """¿Tiene la versión un phpMyAdmin con fallos de seguridad ya corregidos? Lo mínimo: 5.2.2 desde
    PHP 7.2.5, 5.1.4 desde la 7.1.3 y 4.9.11 antes (actualizar-phpmyadmin pone la más nueva)."""
    if not ver_tuple(php):
        return False
    if not ver_tuple(pma):
        return True
    need = (5, 2, 2) if ver_tuple(php) >= (7, 2, 5) else (5, 1, 4) if ver_tuple(php) >= (7, 1, 3) else (4, 9, 11)
    return ver_tuple(pma) < need


class ActionRow(Gtk.ListBoxRow):
    """Fila con titulo, subtitulo y widgets a la izquierda (prefijo) y a la derecha (sufijo)."""

    def __init__(self, title, subtitle=None, activatable=False):
        super().__init__(activatable=activatable, selectable=False)
        self.on_activate = None
        self.header = Gtk.Box(spacing=12, margin_start=14, margin_end=12,
                              margin_top=8, margin_bottom=8)
        self.prefix = Gtk.Box(spacing=8)
        self.header.pack_start(self.prefix, False, False, 0)
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2,
                        valign=Gtk.Align.CENTER)
        self.title = label(title, ellipsize=3)
        # Titulo y, a su derecha, etiquetas de texto (como «Activa»)
        self.title_box = Gtk.Box(spacing=12)
        self.title_box.pack_start(self.title, False, True, 0)
        texts.pack_start(self.title_box, False, False, 0)
        self.subtitle = label(subtitle or "", "dim-label", "subtitulo", ellipsize=3)
        self.subtitle.set_no_show_all(not subtitle)
        texts.pack_start(self.subtitle, False, False, 0)
        self.header.pack_start(texts, True, True, 0)
        self.texts = texts
        self.suffix = Gtk.Box(spacing=8)
        self.header.pack_end(self.suffix, False, False, 0)
        self.set_size_request(-1, 50)
        self.add(self.header)
        spec = row_icon_spec(title or "")
        if spec:
            self.add_prefix(section_icon(spec, 16))

    def add_title_tag(self, w):
        w.set_valign(Gtk.Align.BASELINE)
        self.title_box.pack_start(w, False, False, 0)

    def add_prefix(self, w):
        w.set_valign(Gtk.Align.CENTER)
        self.prefix.pack_start(w, False, False, 0)

    def add_suffix(self, w):
        w.set_valign(Gtk.Align.CENTER)
        self.suffix.pack_start(w, False, False, 0)


class ExpanderRow(ActionRow):
    """Fila que despliega una lista anidada al pulsarla."""

    def __init__(self, title, subtitle=None, on_toggle=None):
        super().__init__(title, subtitle, activatable=True)
        self.on_toggle = on_toggle
        self.remove(self.header)
        self.arrow = icon("pan-down-symbolic")
        self.header.remove(self.suffix)
        self.header.pack_end(self.arrow, False, False, 0)
        self.header.pack_end(self.suffix, False, False, 0)
        self.inner = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "anidada")
        self.inner.connect("row-activated", on_row_activated)
        self.revealer = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.revealer.add(self.inner)
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        vbox.pack_start(self.header, False, False, 0)
        vbox.pack_start(self.revealer, False, False, 0)
        self.add(vbox)

    def add_row(self, w):
        if not isinstance(w, Gtk.ListBoxRow):
            row = Gtk.ListBoxRow(activatable=False, selectable=False)
            row.add(w)
            w = row
        self.inner.add(w)

    def set_expanded(self, on):
        self.revealer.set_reveal_child(on)
        self.arrow.set_from_icon_name("pan-up-symbolic" if on else "pan-down-symbolic",
                                      Gtk.IconSize.BUTTON)

    def toggle(self):
        on = not self.revealer.get_reveal_child()
        self.set_expanded(on)
        if self.on_toggle:
            self.on_toggle(on)


def on_row_activated(_lb, row):
    if isinstance(row, ExpanderRow):
        row.toggle()
    elif getattr(row, "on_activate", None):
        row.on_activate()


def password_dialog(parent, user, retry):
    """Contraseña de administrador, como el diálogo de autorización del sistema: centrado y con
    aire, el icono de la aplicación con un candado, un campo estrecho y alto y los botones abajo.
    Devuelve (respuesta, contraseña)."""
    dlg = Gtk.Dialog(title="", transient_for=parent, modal=True, use_header_bar=True)
    css(dlg, "dialogo-clave")
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0, margin_start=36,
                  margin_end=36, margin_top=6, margin_bottom=28)
    ov = Gtk.Overlay(halign=Gtk.Align.CENTER, margin_bottom=18)
    app = Gtk.Image.new_from_icon_name(Gtk.Window.get_default_icon_name() or "dialog-password",
                                       Gtk.IconSize.DIALOG)
    app.set_pixel_size(64)
    ov.add(app)
    lock = css(Gtk.Box(halign=Gtk.Align.END, valign=Gtk.Align.END), "candado")
    lock.pack_start(icon("changes-prevent-symbolic", 12), False, False, 0)
    ov.add_overlay(lock)
    box.pack_start(ov, False, False, 0)
    box.pack_start(label("Contraseña de administrador", "clave-titulo", xalign=0.5,
                         margin_bottom=8), False, False, 0)
    box.pack_start(label("Esta acción necesita permisos de administrador. Escribe la contraseña "
                         "de %s para continuar." % user, "dim-label", xalign=0.5, wrap=True,
                         max_width_chars=38, justify=Gtk.Justification.CENTER), False, False, 0)
    if retry:
        box.pack_start(label("Contraseña incorrecta. Vuelve a intentarlo.", "error", xalign=0.5,
                             margin_top=10), False, False, 0)
    entry = css(Gtk.Entry(visibility=False, input_purpose=Gtk.InputPurpose.PASSWORD,
                          placeholder_text="Contraseña", halign=Gtk.Align.CENTER, margin_top=22),
                "campo-clave")
    entry.set_size_request(260, -1)
    box.pack_start(entry, False, False, 0)
    buttons = Gtk.Box(spacing=10, homogeneous=True, halign=Gtk.Align.CENTER, margin_top=22)
    buttons.set_size_request(260, -1)
    cancel = css(Gtk.Button(label="Cancelar"), "boton-grande")
    ok = css(Gtk.Button(label="Continuar", sensitive=False), "verde", "boton-grande")
    cancel.connect("clicked", lambda *_: dlg.response(Gtk.ResponseType.CANCEL))
    ok.connect("clicked", lambda *_: dlg.response(Gtk.ResponseType.OK))
    entry.connect("changed", lambda e: ok.set_sensitive(bool(e.get_text())))
    entry.connect("activate", lambda e: e.get_text() and dlg.response(Gtk.ResponseType.OK))
    buttons.pack_start(cancel, True, True, 0)
    buttons.pack_start(ok, True, True, 0)
    box.pack_start(buttons, False, False, 0)
    dlg.get_content_area().add(box)
    dlg.show_all()
    resp = run_dialog(dlg)
    password = entry.get_text()
    dlg.destroy()
    return resp, password


def info_icon(text):
    """Simbolo de informacion: al pasar el raton muestra la explicacion (en lugar de un parrafo
    gris bajo el titulo)."""
    ev = Gtk.EventBox(valign=Gtk.Align.CENTER, tooltip_text=text)
    ev.add(css(icon("dialog-information-symbolic"), "info"))
    return ev


class TileGrid(Gtk.Grid):
    """Las filas de un apartado en tarjetas de dos en dos, como los visores de las otras pestañas: el
    icono y el título arriba, la explicación debajo (entera) y sus botones abajo a la derecha. add e
    insert reciben ActionRow, como un ListBox. Una fila con .wide (o la única del apartado) va a lo
    ancho, en una tarjeta con sus botones a la derecha. columns: las tarjetas por fila (2 de normal)."""

    def __init__(self, columns=2):
        super().__init__(column_spacing=12, row_spacing=12, column_homogeneous=True, margin_top=6)
        self.rows, self.columns = [], columns

    def add(self, row):
        self.insert(row, -1)

    def insert(self, row, pos):
        if 0 <= pos < len(self.rows):
            self.rows.insert(pos, row)
        else:
            self.rows.append(row)
        self.layout()

    def tile(self, row, wide):
        for w in (row.prefix, row.texts, row.suffix):
            if w.get_parent():
                w.get_parent().remove(w)
        for lbl in (row.title, row.subtitle):
            lbl.set_ellipsize(0)
            lbl.set_line_wrap(True)
            lbl.set_xalign(0)
        row.subtitle.set_max_width_chars(60)
        css(row.title, "nv-mosaico-titulo")
        card = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10), "nv-mosaico")
        if wide:
            line = Gtk.Box(spacing=12)
            line.pack_start(row.prefix, False, False, 0)
            line.pack_start(row.texts, True, True, 0)
            line.pack_end(row.suffix, False, False, 0)
            card.pack_start(line, True, True, 0)
        else:
            top = Gtk.Box(spacing=10)
            top.pack_start(row.prefix, False, False, 0)
            top.pack_start(row.texts, True, True, 0)
            card.pack_start(top, False, False, 0)
            bottom = Gtk.Box()
            bottom.pack_end(row.suffix, False, False, 0)
            card.pack_end(bottom, False, False, 0)
        return card

    def layout(self):
        # (antes de quitar las tarjetas de antes, lo de cada fila fuera de ellas: GTK destruye lo que lleve
        # dentro una tarjeta que se queda sin dueño)
        for row in self.rows:
            for w in (row.prefix, row.texts, row.suffix):
                if w.get_parent():
                    w.get_parent().remove(w)
        for ch in self.get_children():
            self.remove(ch)
        r = c = 0
        for row in self.rows:
            wide = getattr(row, "wide", False) or len(self.rows) == 1
            card = self.tile(row, wide)
            if wide:
                if c:
                    r, c = r + 1, 0
                self.attach(card, 0, r, self.columns, 1)
                r += 1
            else:
                self.attach(card, c, r, 1, 1)
                c += 1
                if c == self.columns:
                    r, c = r + 1, 0
        self.show_all()


def group(title=None, description=None, tiles=False, columns=2, lead=None, tail=None):
    """Bloque con titulo (con su simbolo de informacion si hay descripcion) y una lista con
    bordes redondeados (o, con tiles, sus filas en tarjetas de dos en dos: TileGrid)."""
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    if title or description:
        head = Gtk.Box(spacing=6)
        if lead is not None:
            head.pack_start(lead, False, False, 2)
        if title:
            head.pack_start(label(title, "grupo-titulo"), False, False, 0)
        if description:
            head.pack_start(info_icon(description), False, False, 0)
        if tail is not None:
            head.pack_start(tail, False, False, 6)
        box.pack_start(head, False, False, 0)
    if tiles:
        lb = TileGrid(columns)
    else:
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, margin_top=6), "caja")
        lb.connect("row-activated", on_row_activated)
    box.pack_start(lb, False, False, 0)
    return box, lb


def tile_group(title=None, description=None, columns=2, tiles=False, lead=None, tail=None):
    """Un apartado de Configuración: en filas (desde la 1.57.1) o, con tiles, en tarjetas de dos en dos o de
    columns en columns (Docker y el correo de pruebas)."""
    return group(title, description, tiles=tiles, columns=columns, lead=lead, tail=tail)


def fold_group(title, description, opened, on_toggle, summary=""):
    """Como group(), pero se pliega y se despliega al pulsar el título (on_toggle(abierto)).
    Plegado, al lado del título sale el resumen."""
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    head = Gtk.Box(spacing=6)
    btn = css(Gtk.Button(relief=Gtk.ReliefStyle.NONE, can_focus=True), "plegable")
    inner = Gtk.Box(spacing=6)
    arrow = icon("pan-down-symbolic" if opened else "pan-end-symbolic")
    inner.pack_start(label(title, "grupo-titulo"), False, False, 0)
    inner.pack_start(arrow, False, False, 0)
    btn.add(inner)
    btn.set_tooltip_text("Plegar" if opened else "Desplegar")
    head.pack_start(btn, False, False, 0)
    if description:
        head.pack_start(info_icon(description), False, False, 0)
    note = label(summary, "dim-label", "subtitulo")
    note.set_no_show_all(True)
    note.set_visible(bool(summary) and not opened)
    head.pack_start(note, False, False, 0)
    box.pack_start(head, False, False, 0)
    lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, margin_top=6), "caja")
    lb.connect("row-activated", on_row_activated)
    rev = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.SLIDE_DOWN, reveal_child=opened)
    rev.add(lb)
    box.pack_start(rev, False, False, 0)

    def toggle(*_):
        on = not rev.get_reveal_child()
        rev.set_reveal_child(on)
        arrow.set_from_icon_name("pan-down-symbolic" if on else "pan-end-symbolic", Gtk.IconSize.BUTTON)
        btn.set_tooltip_text("Plegar" if on else "Desplegar")
        note.set_visible(bool(summary) and not on)
        on_toggle(on)
    btn.connect("clicked", toggle)
    return box, lb


def page():
    """Pagina con desplazamiento y contenido centrado de ancho limitado."""
    sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
    content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24, margin=24,
                      halign=Gtk.Align.CENTER)
    content.set_size_request(580, -1)
    sw.add(content)
    return sw, content


def clear(box):
    for child in box.get_children():
        box.remove(child)


def center_texts(box):
    """Centra el título y la explicación de un diálogo: los textos (y los iconos) con que empieza
    cada caja vertical, hasta el primer campo, lista o botón."""
    for c in box.get_children():
        if isinstance(c, Gtk.Label):
            c.set_justify(Gtk.Justification.CENTER)
            c.set_xalign(0.5)
            c.set_halign(Gtk.Align.FILL)
        elif not isinstance(c, Gtk.Image):
            break


def airy_dialog(dlg):
    """Más aire en cualquier diálogo: las cajas verticales con separación (no las de dos líneas
    como título y subtítulo, ni lo que va dentro de listas o botones) pasan a 16 px, y el texto de
    los mensajes, más separado de los botones. Su título y su explicación, centrados."""
    if getattr(dlg, "aireado", False):
        return
    dlg.aireado = True
    area = dlg.get_message_area() if isinstance(dlg, Gtk.MessageDialog) else dlg.get_content_area()

    def walk(w):
        if isinstance(w, (Gtk.ListBox, Gtk.Button, Gtk.ScrolledWindow, Gtk.TextView, Gtk.ComboBox)) \
                or getattr(w, "nv_pasos", False):
            return
        if isinstance(w, Gtk.Box) and w.get_orientation() == Gtk.Orientation.VERTICAL:
            if w.get_spacing() >= 6:
                w.set_spacing(max(w.get_spacing(), 16))
            center_texts(w)
        if isinstance(w, Gtk.Container):
            for c in w.get_children():
                walk(c)
    walk(area)
    if isinstance(dlg, Gtk.MessageDialog):
        # (sin el icono de al lado: el texto, centrado de verdad)
        for c in area.get_parent().get_children():
            if isinstance(c, Gtk.Image):
                c.set_no_show_all(True)
                c.hide()
        area.set_spacing(max(area.get_spacing(), 16))
        area.set_margin_top(max(area.get_margin_top(), 8))
        area.set_margin_bottom(max(area.get_margin_bottom(), 12))


def run_dialog(dlg):
    """Abre un diálogo (modal) con más aire entre sus campos. Todos los diálogos se abren así."""
    if not isinstance(dlg, Gtk.FileChooserDialog):
        airy_dialog(dlg)
    return dlg.run()


def widen(dlg):
    """Los MessageDialog parten el texto en una columna estrecha: lineas de hasta 72 caracteres"""
    for child in dlg.get_message_area().get_children():
        if isinstance(child, Gtk.Label):
            child.set_max_width_chars(72)
            child.set_width_chars(min(72, max(len(child.get_text()), 30)))
    return dlg


def message(parent, title, text="", kind=Gtk.MessageType.INFO):
    dlg = Gtk.MessageDialog(transient_for=parent, modal=True, message_type=kind,
                            buttons=Gtk.ButtonsType.CLOSE, text=title)
    if text:
        dlg.format_secondary_text(text)
    widen(dlg)
    run_dialog(dlg)
    dlg.destroy()


def markdown_to_buffer(buf, text):
    """Pinta el Markdown de «lvm-instalador novedades»: «## versión · fecha», viñetas «- » (con dos
    espacios delante, dentro de la anterior), **negrita** y `código`."""
    # (con aire: espacio entre versiones, entre puntos y entre las líneas de un mismo punto)
    buf.create_tag("h2", weight=700, scale=1.3, pixels_above_lines=30, pixels_below_lines=12)
    buf.create_tag("fecha", weight=400, scale=0.8, foreground="#888888")
    buf.create_tag("li0", left_margin=44, indent=-16, pixels_above_lines=10, pixels_below_lines=2,
                   pixels_inside_wrap=5)
    buf.create_tag("li1", left_margin=68, indent=-16, pixels_above_lines=6, pixels_below_lines=2,
                   pixels_inside_wrap=5)
    buf.create_tag("punto", foreground=GREEN, weight=700)
    buf.create_tag("b", weight=700)
    buf.create_tag("code", family="monospace", scale=0.92, background_rgba=Gdk.RGBA(0.5, 0.5, 0.5, 0.16))
    buf.create_tag("p", pixels_above_lines=6, pixels_below_lines=8, pixels_inside_wrap=5)
    first = True
    for line in text.split("\n"):
        if not line.strip():
            continue
        if not first:
            buf.insert(buf.get_end_iter(), "\n")
        first = False
        if line.startswith("## "):
            version, _, date = line[3:].partition(" · ")
            buf.insert_with_tags_by_name(buf.get_end_iter(), version, "h2")
            if date:
                buf.insert_with_tags_by_name(buf.get_end_iter(), "   " + date, "h2", "fecha")
            continue
        m = re.match(r"^( *)- (.*)$", line)
        if m:
            depth = min(len(m.group(1)) // 2, 1)
            block = "li%d" % depth
            buf.insert_with_tags_by_name(buf.get_end_iter(), "•  " if depth == 0 else "◦  ",
                                         block, "punto")
            body = m.group(2)
        else:
            block, body = "p", line
        for part in re.split(r"(\*\*[^*]+\*\*|`[^`]+`)", body):
            if not part:
                continue
            if part.startswith("**") and part.endswith("**") and len(part) > 4:
                buf.insert_with_tags_by_name(buf.get_end_iter(), part[2:-2], block, "b")
            elif part.startswith("`") and part.endswith("`") and len(part) > 2:
                buf.insert_with_tags_by_name(buf.get_end_iter(), part[1:-1], block, "code")
            else:
                buf.insert_with_tags_by_name(buf.get_end_iter(), part, block)


def steps_box(steps, note=""):
    """Lo que va a hacer un diálogo que pide confirmar varios cambios: «Qué se va a realizar» y
    los cambios numerados, a la izquierda y separados entre sí; debajo, la nota (si la hay)."""
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin_top=4)
    box.nv_pasos = True
    head = Gtk.Label(xalign=0)
    head.set_markup("<b>Qué se va a realizar</b>")
    box.pack_start(head, False, False, 0)
    longest = max([len(x) for x in steps] + [len(note)])
    width = min(64, max(longest, 40))
    lst = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin_start=4)
    for i, step in enumerate(steps, 1):
        row = Gtk.Box(spacing=8)
        num = Gtk.Label(xalign=1, yalign=0, width_chars=3)
        num.set_markup('<span foreground="%s" weight="bold">%d.</span>' % (GREEN, i))
        row.pack_start(num, False, False, 0)
        t = Gtk.Label(label=step, xalign=0, yalign=0, wrap=True, selectable=True,
                      max_width_chars=64, width_chars=width)
        row.pack_start(t, True, True, 0)
        lst.pack_start(row, False, False, 0)
    box.pack_start(lst, False, False, 0)
    if note:
        n = css(Gtk.Label(label=note, xalign=0, wrap=True, selectable=True, max_width_chars=64,
                          width_chars=width, margin_top=6), "dim-label")
        box.pack_start(n, False, False, 0)
    return box


def confirm(parent, title, text, ok_label, destructive=False, extra=None, steps=None):
    """Pregunta con Cancelar / ok_label. extra: widget opcional debajo del texto. steps: los
    cambios que se van a hacer (numerados); text va entonces debajo, como nota."""
    dlg = Gtk.MessageDialog(transient_for=parent, modal=True,
                            message_type=Gtk.MessageType.QUESTION,
                            buttons=Gtk.ButtonsType.NONE, text=title)
    if steps:
        dlg.get_message_area().pack_start(steps_box(steps, text), False, False, 0)
    else:
        dlg.format_secondary_text(text)
    widen(dlg)
    if extra:
        dlg.get_message_area().pack_start(extra, False, False, 0)
    dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
    ok = dlg.add_button(ok_label, Gtk.ResponseType.ACCEPT)
    css(ok, "destructive-action" if destructive else "verde")
    dlg.set_default_response(Gtk.ResponseType.CANCEL if destructive else Gtk.ResponseType.ACCEPT)
    dlg.show_all()
    dlg.ok_button = ok
    resp = run_dialog(dlg)
    dlg.destroy()
    return resp == Gtk.ResponseType.ACCEPT


# ---------------------------------------------------------------- llamadas al script

def script_cmd(*args):
    return ["/bin/bash", SCRIPT] + (["--simular"] if SIMULATE else []) + list(args)


# Solo estas variables de la sesion pasan a las tareas: el resto podria cambiar lo que hace bash
# (funciones exportadas BASH_FUNC_*, SHELLOPTS con PS4, BASH_ENV) o lo que toca el gestor con sudo
ENV_KEEP = {"HOME", "USER", "LOGNAME", "LANG", "LANGUAGE", "DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "SSH_AUTH_SOCK",
            "DBUS_SESSION_BUS_ADDRESS", "TMPDIR", "PATH", "LVM_PRUEBA", "PHP_TIMEZONE",
            "http_proxy", "https_proxy", "no_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY",
            "NO_PROXY", "ALL_PROXY"}


def script_env(**extra):
    # (en las pruebas, con LVM_PRUEBA, tambien las LVM_* que cambian las carpetas)
    test = bool(os.environ.get("LVM_PRUEBA"))
    env = {k: v for k, v in os.environ.items()
           if k in ENV_KEEP or k.startswith(("LC_", "XDG_"))
           or (test and k.startswith("LVM_") and k != "LVM_SIMULAR")}
    env.update(LVM_UI="text", SUDO_PROMPT=SUDO_MARK, TERM="dumb")
    env.update(extra)
    return env


def once(callback, *args):
    """Llama a callback(*args) una sola vez en la interfaz. GLib.idle_add repite la llamada mientras
    devuelva algo verdadero: un callback que devolviera sus datos se quedaria dando vueltas a toda
    CPU, tambien despues de cerrar la ventana."""
    GLib.idle_add(lambda: (callback(*args), False)[1])


def close_stale_windows(script):
    """Cierra las ventanas de Nexum de este usuario que van con un código anterior al instalado: las de este
    mismo script (python3 -I - <script>) que arrancaron antes de que se instalara (su ctime). Las de la
    versión instalada no se tocan: si hay una abierta, el sistema le pasa la petición y se trae al frente."""
    if not script or not os.path.isfile(script):
        return
    try:
        installed = os.stat(script).st_ctime
        with open("/proc/stat") as fh:
            boot = int(next(l for l in fh if l.startswith("btime ")).split()[1])
    except (OSError, StopIteration, ValueError):
        return
    tick, me, uid = os.sysconf("SC_CLK_TCK"), os.getpid(), os.getuid()
    want = [b"/usr/bin/python3", b"-I", b"-", os.fsencode(script)]
    stale = []
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == me:
            continue
        pid = int(name)
        try:
            if os.stat("/proc/%d" % pid).st_uid != uid:
                continue
            with open("/proc/%d/cmdline" % pid, "rb") as fh:
                if fh.read().split(b"\0")[:-1] != want:
                    continue
            with open("/proc/%d/stat" % pid) as fh:
                st = fh.read()
            started = boot + int(st[st.rfind(")") + 2:].split()[19]) / tick
        except (OSError, ValueError, IndexError):
            continue
        if started < installed - 1:
            stale.append(pid)
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in stale:
            try:
                os.kill(pid, sig)
            except OSError:
                pass
        if not stale:
            break
        time.sleep(1.5)
        stale = [pid for pid in stale if os.path.exists("/proc/%d" % pid)]


# Buscador de Nuevo proyecto: al abrir el asistente, si hace más de estos segundos que no se pregunta a
# GitHub, se le pregunta por detrás
NP_REPOS_FRESH = 300
# Cuántos resultados enseña debajo
NP_REPOS_HITS = 6


def repo_query(text):
    """Lo que se busca en la lista de repositorios: dueño/repo si es una dirección de GitHub."""
    q = text.strip().lower()
    q = re.sub(r"^(git@github\.com:|ssh://git@github\.com/|https?://github\.com/)", "", q)
    return re.sub(r"(\.git)?/?$", "", q)


def run_quick(args, callback, env=None, timeout=180):
    """Comando sin sudo ni preguntas, en segundo plano. callback(rc, salida) en la interfaz."""
    def work():
        try:
            res = subprocess.run(script_cmd(*args), stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 env=script_env(**(env or {})), timeout=timeout)
            out = res.stdout.decode("utf-8", "replace")
            once(callback, res.returncode, out)
        except Exception as exc:  # noqa: BLE001 - cualquier fallo se muestra como error
            once(callback, 1, "ERROR|%s" % exc)
    threading.Thread(target=work, daemon=True).start()


def run_quick_input(args, text, callback, timeout=60):
    """Como run_quick, con text por la entrada del comando (un token: en la línea de órdenes se vería
    con ps)."""
    def work():
        try:
            res = subprocess.run(script_cmd(*args), input=text.encode(), stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, env=script_env(), timeout=timeout)
            once(callback, res.returncode, res.stdout.decode("utf-8", "replace"))
        except Exception as exc:  # noqa: BLE001 - cualquier fallo se muestra como error
            once(callback, 1, "ERROR|%s" % exc)
    threading.Thread(target=work, daemon=True).start()


# Botones del visor de un proyecto (el cargado y los de Docker) que se pueden ocultar y ordenar:
# clave, nombre e icono. «Desmontar», ⋮ y los propios de Docker (Versiones de PHP, Arrancar o Parar)
# se ven siempre
VISOR_BUTTONS = [("web", "Abrir web", ("logo", "globo")), ("vscode", "VS Code", ("vscode", "text-editor-symbolic")),
                 ("pma", "phpMyAdmin", ("logo", "phpmyadmin")), ("panel", "Panel", ("logo", "wordpress")),
                 ("docker", "Docker", ("logo", "docker")), ("compartir", "Compartir", ("logo", "cloudflare")),
                 ("log", "Log", ("logo", "log")), ("actualizar", "Actualizar", ("logo", "actualizar")),
                 ("imagenes", "Importar", ("logo", "imagenes"))]
# Configuración, Seguridad entre webs: qué es, en cuatro puntos (el mismo texto en el Mac)
CROSS_SITE_HELP = [
    ("dialog-warning-symbolic", "El problema",
     "Mientras trabajas, el navegador tiene abierta tu sesión en tus proyectos (el panel de WordPress, el de "
     "PrestaShop…). Cualquier otra web que abras a la vez podría mandarles a escondidas un formulario o una "
     "petición, y el navegador la enviaría con tu sesión: crear un administrador, cambiar una contraseña, borrar "
     "productos…"),
    ("security-high-symbolic", "Lo que hace la barrera",
     "Apache rechaza lo que llega a tus proyectos desde otra web, salvo abrir una página con un enlace normal. Lo "
     "que hagas dentro del propio proyecto, o escribiendo su dirección, funciona igual."),
    ("dialog-information-symbolic", "Cuándo apagarla",
     "Al probar una pasarela de pago (Redsys, PayPal, Stripe…): al acabar el pago, el banco te devuelve a la "
     "tienda mandando un formulario desde su web, y la barrera lo para (sale «Otra web ha intentado mandar algo a "
     "esta»). Apágala mientras pruebas los pagos y vuelve a encenderla al acabar."),
    ("network-workgroup-symbolic", "Dónde se aplica",
     "En todas tus versiones de PHP: localhost, web.local, los dominios falseados y los vhosts de los proyectos. "
     "Al cambiarla se reinicia Apache."),
]

BUTTON_STYLES = [("nombre", "Con su nombre"), ("icono", "Solo el icono (cuadrado)"),
                 ("grande", "Icono y nombre (cuadrado)")]
# Lado del cuadrado (px) de los estilos icono y grande: el de cada uno si no se ha elegido otro
BUTTON_SIZES = {"icono": 44, "grande": 88}
BUTTON_SIZE_MIN, BUTTON_SIZE_MAX = 32, 128
# (con el nombre debajo hace falta algo más de sitio)
BUTTON_SIZE_NAMED = 72
BUTTONS_FILE = os.path.join(LOG_DIR, "botones-visor")
# Al abrir la ventana se busca una versión nueva el primer arranque de cada día y, después, cada tantos
UPDATE_EVERY = 4
# (en la simulacion no se escribe nada: lo elegido vale mientras la ventana siga abierta)
_buttons_sim = {}


def buttons_conf():
    """order (todas las claves, en su orden), hidden (las que no se ven) y style (BUTTON_STYLES)."""
    keys = [k for k, _n, _i in VISOR_BUTTONS]
    conf = dict(_buttons_sim)
    if not conf:
        try:
            with open(BUTTONS_FILE, encoding="utf-8") as fh:
                conf = json.loads(fh.read(4000))
        except (OSError, ValueError):
            conf = {}
    if not isinstance(conf, dict):
        conf = {}
    order = [k for k in conf.get("order", []) if k in keys] if isinstance(conf.get("order"), list) else []
    order += [k for k in keys if k not in order]
    hidden = {k for k in conf.get("hidden", []) if k in keys} if isinstance(conf.get("hidden"), list) else set()
    style = conf.get("style") if conf.get("style") in [k for k, _t in BUTTON_STYLES] else "nombre"
    size = conf.get("size")
    if not isinstance(size, int) or not BUTTON_SIZE_MIN <= size <= BUTTON_SIZE_MAX:
        size = BUTTON_SIZES.get(style, BUTTON_SIZES["icono"])
    return {"order": order, "hidden": hidden, "style": style, "size": size}


def buttons_save(conf):
    data = {"order": conf["order"], "hidden": sorted(conf["hidden"]), "style": conf["style"], "size": conf["size"]}
    if SIMULATE:
        _buttons_sim.clear()
        _buttons_sim.update(data)
        return
    os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
    with open(BUTTONS_FILE + ".nuevo", "w", encoding="utf-8") as fh:
        json.dump(data, fh)
    os.replace(BUTTONS_FILE + ".nuevo", BUTTONS_FILE)


def button_icon(spec, size):
    if spec[0] == "logo":
        return logo(spec[1], size)
    if spec[0] == "vscode":
        code = vscode_app()
        if code is not None and code.get_icon() is not None:
            img = Gtk.Image.new_from_gicon(code.get_icon(), Gtk.IconSize.BUTTON)
            img.set_pixel_size(size)
            return img
    return icon(spec[1], size)


# Consumo de Nexum y sus servicios (el visor de arriba): los procesos de cada parte, leídos de /proc
USAGE_GROUPS = [("ventana", "Nexum Dev Stack (la ventana y sus tareas)"), ("lampp", "LAMPP (Apache, MariaDB y PHP-FPM)"),
                ("docker", "Docker sin root y sus contenedores"), ("mailpit", "Mailpit (correo de pruebas)"),
                ("tunel", "Túnel de Cloudflare")]


def usage_group(pid, argv, cgroup, own):
    """A qué parte de Nexum es un proceso (None: a ninguna). Sin los hijos: esos van con su padre."""
    first = argv[0] if argv else ""
    if pid == own:
        return "ventana"
    if first.startswith("/opt/lampp") or (first in ("/bin/sh", "sh") and len(argv) > 1 and argv[1].startswith("/opt/lampp")):
        return "lampp"
    if os.path.basename(first) == "mailpit" and "/mailpit/" in first:
        return "mailpit"
    if "nexum-tunel" in argv or first == os.path.join(LOG_DIR, "tunel", "cloudflared"):
        return "tunel"
    # Docker sin root: dockerd y los suyos en su servicio de usuario y cada contenedor en su scope
    if "user@%d.service" % os.getuid() in cgroup and ("/docker.service" in cgroup or "/docker-" in cgroup):
        return "docker"
    return None


class UsageMeter:
    """CPU y memoria de Nexum y sus servicios juntos: la CPU, en % de todo el equipo (todos los núcleos
    son el 100 %), entre una lectura y la anterior; la memoria, la PSS de cada proceso (lo que de verdad
    ocupa, sin contar dos veces lo compartido) o, si no se puede leer (los de root), lo suyo sin lo
    compartido."""

    def __init__(self):
        self.prev, self.when, self.known = {}, None, {}
        self.tick = os.sysconf("SC_CLK_TCK")
        self.page = os.sysconf("SC_PAGE_SIZE")
        self.cpus = os.cpu_count() or 1
        self.total = 0
        try:
            with open("/proc/meminfo") as fh:
                self.total = int(next(l for l in fh if l.startswith("MemTotal:")).split()[1]) * 1024
        except (OSError, StopIteration, ValueError):
            pass

    @staticmethod
    def read(path, mode="r"):
        try:
            with open(path, mode) as fh:
                return fh.read()
        except OSError:
            return None

    def sample(self):
        own = os.getpid()
        procs, known, seen = {}, self.known, {}
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            pid = int(name)
            stat = self.read("/proc/%d/stat" % pid)
            if stat is None:
                continue
            f = stat[stat.rfind(")") + 2:].split()
            # (su orden y su parte no cambian: se leen una vez por proceso, con su hora de inicio)
            key = (pid, f[19])
            if key not in known:
                raw = self.read("/proc/%d/cmdline" % pid, "rb")
                if raw is None:
                    continue
                argv = [a.decode("utf-8", "replace") for a in raw.split(b"\0") if a]
                known[key] = (argv, usage_group(pid, argv, self.read("/proc/%d/cgroup" % pid) or "", own))
            argv, group = known[key]
            seen[key] = known[key]
            procs[pid] = {"ppid": int(f[1]), "cpu": int(f[11]) + int(f[12]), "argv": argv, "group": group}
        self.known = seen
        # Los hijos van con su padre (los PHP-FPM de LAMPP, las tareas de la ventana: solo las suyas)
        for _pid, pr in procs.items():
            q, depth = pr["ppid"], 0
            while pr["group"] is None and q in procs and depth < 6:
                g = procs[q]["group"]
                if g and (g != "ventana" or any("lvm-instalador" in a for a in pr["argv"])):
                    pr["group"] = g
                q, depth = procs[q]["ppid"], depth + 1
        now = time.monotonic()
        out = {k: [0.0, 0] for k, _t in USAGE_GROUPS}
        for pid, pr in procs.items():
            if not pr["group"]:
                continue
            if self.when is not None and pid in self.prev:
                out[pr["group"]][0] += max(0, pr["cpu"] - self.prev[pid])
            mem = None
            roll = self.read("/proc/%d/smaps_rollup" % pid)
            if roll:
                m = re.search(r"^Pss:\s+(\d+) kB", roll, re.M)
                mem = int(m.group(1)) * 1024 if m else None
            if mem is None:
                # (residente sin lo compartido: los hijos de Apache comparten casi todo con su padre)
                statm = self.read("/proc/%d/statm" % pid)
                mem = max(0, int(statm.split()[1]) - int(statm.split()[2])) * self.page if statm else 0
            out[pr["group"]][1] += mem
        span = (now - self.when) if self.when else 0
        self.prev = {pid: pr["cpu"] for pid, pr in procs.items() if pr["group"]}
        self.when = now
        for k in out:
            out[k][0] = 100.0 * out[k][0] / self.tick / span / self.cpus if span > 0 else None
        return out


def docker_own(name):
    """¿Es un contenedor de Nexum (los que acepta docker-contenedor)? Los de los proyectos (de antes y
    del Apache de Docker), las MariaDB comunes, el Apache de Docker y su phpMyAdmin."""
    return bool(re.fullmatch(r"nexum-[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?-((php|db|pma)-\d{1,3}|php\d{2})", name)
                or re.fullmatch(r"nexum-(web|pma|mariadb-\d{1,2}-\d{1,2})", name))


def smooth_scroll(sw, target=0.0, ms=320):
    """Lleva una ventana con desplazamiento a esa altura poco a poco (como al deslizar)."""
    adj = sw.get_vadjustment()
    start, t0 = adj.get_value(), time.monotonic()
    if abs(start - target) < 1:
        return

    def step():
        k = min(1.0, (time.monotonic() - t0) * 1000 / ms)
        adj.set_value(start + (target - start) * (1 - (1 - k) ** 3))
        return k < 1.0
    GLib.timeout_add(15, step)


def tunnel_state():
    """El túnel de Cloudflare abierto (tunel-abrir): url, target (la dirección local), folder y expires.
    None si no hay ninguno o su proceso ya no está."""
    try:
        with open(os.path.join(LOG_DIR, "tunel", "estado"), encoding="utf-8") as fh:
            st = json.load(fh)
        pid = int(st["pid"])
        with open("/proc/%d/cmdline" % pid, "rb") as fh:
            if b"nexum-tunel" not in fh.read():
                return None
        return st if st.get("url") and int(st.get("expires", 0)) > time.time() else None
    except (OSError, ValueError, KeyError, TypeError):
        return None


def project_admin(folder):
    """(tipo, carpeta del panel) de un proyecto: wp-admin en WordPress y, en PrestaShop, su carpeta de
    administración (cada tienda la llama de una forma; se reconoce por lo que tiene)."""
    if os.path.isfile(os.path.join(folder, "wp-config.php")) and os.path.isdir(os.path.join(folder, "wp-admin")):
        return "wp", "wp-admin"
    try:
        names = sorted(os.listdir(folder), key=lambda n: (not n.lower().startswith("admin"), n))
    except OSError:
        return "", ""
    for n in names:
        d = os.path.join(folder, n)
        if re.fullmatch(r"[A-Za-z0-9_-]+", n) and not os.path.islink(d) and os.path.isdir(d) \
                and os.path.isfile(os.path.join(d, "index.php")) \
                and any(os.path.isfile(os.path.join(d, f)) for f in ("ajax-tab.php", "get-file-admin.php")):
            return "ps", n
    return "", ""


def login_page(title, project, action, fields, panel):
    """Página de acceso al panel de un proyecto con el administrador de pruebas ya escrito: un
    formulario que va a la pantalla de acceso del proyecto; solo hay que pulsar Entrar."""
    e = html.escape
    rows, hidden = "", ""
    for name, value, text in fields:
        if text:
            kind = "password" if name in ("pwd", "passwd") else "text"
            rows += ('<label>%s<input type="%s" name="%s" value="%s" autocomplete="off"></label>'
                     % (e(text), kind, e(name), e(value)))
        else:
            hidden += '<input type="hidden" name="%s" value="%s">' % (e(name), e(value))
    return """<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="referrer" content="no-referrer"><title>%(title)s · %(project)s</title>
<style>
:root { color-scheme: light dark; --bg: #f4f4f6; --card: #fff; --line: #d8d8dc; --muted: #6b6b72; --accent: #2a7ae2; }
@media (prefers-color-scheme: dark) { :root { --bg: #1e1e20; --card: #2a2a2d; --line: #444; --muted: #a0a0a6; } }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: var(--bg);
       font: 15px/1.45 system-ui, "Ubuntu", sans-serif; }
form { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 28px 32px;
       width: min(380px, calc(100vw - 32px)); box-sizing: border-box; }
h1 { font-size: 19px; margin: 0 0 4px; } p { margin: 0 0 18px; color: var(--muted); font-size: 13px; }
label { display: block; font-size: 13px; color: var(--muted); margin-bottom: 14px; }
input[type=text], input[type=password] { display: block; width: 100%%; box-sizing: border-box; margin-top: 4px;
       padding: 8px 10px; font: inherit; border: 1px solid var(--line); border-radius: 8px; background: transparent; }
button { width: 100%%; margin-top: 6px; padding: 10px; font: inherit; font-weight: 600; color: #fff;
         background: var(--accent); border: 0; border-radius: 8px; cursor: pointer; }
small { display: block; margin-top: 14px; color: var(--muted); font-size: 12px; }
</style></head><body>
<form method="post" action="%(action)s">
<h1>%(title)s</h1><p>%(project)s · administrador de pruebas de este equipo</p>
%(rows)s%(hidden)s<button type="submit" autofocus>Entrar</button>
<small>Si no entra, el panel normal está en <a href="%(panel)s">%(panel)s</a>.</small>
</form></body></html>""" % {"title": e(title), "project": e(project or "proyecto"), "action": e(action),
                            "rows": rows, "hidden": hidden, "panel": e(panel)}


def serve_once(page, seconds=60):
    """Sirve una página en 127.0.0.1 (puerto libre y ruta al azar) durante un minuto y la devuelve.
    Por http y no como fichero: el Firefox de snap no puede abrir ficheros de /tmp ni de las
    carpetas ocultas. None si no se puede."""
    body = page.encode("utf-8")
    path = "/acceso-%s" % os.urandom(8).hex()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != path:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass
    try:
        srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    except OSError:
        return None
    srv.timeout = 1
    end = time.time() + seconds

    def work():
        while time.time() < end:
            srv.handle_request()
        srv.server_close()
    threading.Thread(target=work, daemon=True).start()
    return "http://127.0.0.1:%d%s" % (srv.server_address[1], path)


def parse_lines(out):
    return [line.split("|") for line in out.splitlines() if "|" in line]


def read_progress(path):
    """Como _read_progress, pero una línea rara (un nombre de fichero con |) no rompe la tarea."""
    try:
        return _read_progress(path)
    except (ValueError, IndexError):
        return None


def _read_progress(path):
    """Interpreta el archivo de progreso del script (mismo calculo que progress_screen).
    Devuelve dict o None si aun no ha empezado."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    starts = [i for i, l in enumerate(lines) if l.startswith("I|")]
    if not starts:
        return None
    _, k, n, name, started = (lines[starts[-1]].split("|") + [""] * 5)[:5]
    section = lines[starts[-1]:]
    parts = [l.split("|", 1)[1] for l in section if l.startswith("C|")]
    parts = parts[-1].split(";") if parts else []
    steps = [l for l in section if l.startswith("S|")]
    pct, cur, what, mode, done, total = 0, 0, "", "", 0, 0
    if steps:
        f = (steps[-1].split("|") + [""] * 9)[:9]
        _, cur, frm, to, what, mode, file, total, t0 = f
        cur, frm, to = int(cur or 0), int(frm or 0), int(to or 0)
        done = 0
        try:
            if mode == "lines":
                with open(file, "rb") as fh:
                    done = sum(1 for _ in fh)
            elif mode == "bytes":
                done = os.path.getsize(file)
            elif mode == "time":
                done = int(time.time()) - int(t0 or 0)
            elif mode == "fdpos":
                with open(file, encoding="ascii", errors="replace") as fh:
                    done = next((int(l.split()[1]) for l in fh if l.startswith("pos:")), 0)
            elif mode == "percent":
                with open(file, "rb") as fh:
                    tail = fh.read()[-8000:].decode("utf-8", "replace").splitlines()[-40:]
                found = [m.group(1) for m in (re.match(r"^\[ *(\d+)%\]", t) for t in tail) if m]
                done = int(found[-1]) if found else 0
        except (OSError, ValueError):
            done = 0
        frac = 0
        if mode and int(total or 0) > 0:
            frac = min(done * 1000 // int(total), 990)
        pct = frm + (to - frm) * frac // 1000
    results = [l.split("|") for l in lines if l.startswith("R|")]
    finished = any(l.startswith("R|") for l in section)
    if finished:
        pct, cur = 100, 999
    return {"k": int(k or 1), "n": int(n or 1), "name": name, "started": int(started or 0),
            "parts": parts, "cur": cur, "what": what, "pct": pct, "mode": mode,
            "done": done, "total": int(total or 0),
            "results": [(r[1], r[2]) for r in results if len(r) > 2]}


def item_folder(item):
    """Carpeta (lampp-<carpeta>) de un elemento del plan, como item_folder del script."""
    kind, _, name = item.partition(":")
    return name.rsplit(".", 1)[0] if kind in ("php", "rehacer") else name


def fmt_size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return ("%d %s" % (n, unit)) if unit == "B" else \
                ("%.1f %s" % (n, unit)).replace(".", ",")
        n /= 1024


MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
          "septiembre", "octubre", "noviembre", "diciembre"]


def fmt_month(date):
    """2026-12-31 -> diciembre de 2026"""
    try:
        y, m = date.split("-")[:2]
        return "%s de %s" % (MONTHS[int(m) - 1], y)
    except (ValueError, IndexError):
        return date


def fmt_day(date):
    """2026-10-21 -> 21 de octubre de 2026"""
    try:
        y, m, d = date.split("-")[:3]
        return "%d de %s de %s" % (int(d), MONTHS[int(m) - 1], y)
    except (ValueError, IndexError):
        return date


def release_tag(sec):
    """Etiqueta de un parche de PHP: de seguridad (php.net lo marca así: corrige vulnerabilidades)
    o solo de errores"""
    if sec == "1":
        tag = label("Parche de seguridad", "etiqueta-parche", "seguridad-parche")
        tag.set_tooltip_text("Parche de seguridad")
    else:
        tag = label("Corrección de errores", "etiqueta-parche", "dim-label")
        tag.set_tooltip_text("Corrige errores")
    return tag


def branch_release(f):
    """Fecha y marca de seguridad del último parche de una línea B"""
    fields = (f + [""] * 13)[:13]
    return fields[11], fields[12]


def branch_state(f):
    """Estado en php.net de una linea B: (estado, fin del soporte activo, fin de seguridad)"""
    fields = (f + [""] * 11)[:11]
    state, active_end, security_end = fields[8], fields[9], fields[10]
    if not state:
        state = "stable" if fields[3] == "1" else "eol"
    return state, active_end, security_end


def state_pill(state, active_end, security_end):
    """Estado de una rama en su color (sin fondo): Estable, Solo seguridad o Sin soporte"""
    if state == "stable":
        pill = label("Estable", "estado", "estable")
        pill.set_tooltip_text("Con soporte completo"
                              + (" (hasta %s)" % fmt_month(active_end) if active_end else "")
                              + ". Es la mejor opción para proyectos nuevos.")
    elif state == "security":
        pill = label("Solo seguridad", "estado", "seguridad")
        pill.set_tooltip_text("Solo parches de seguridad"
                              + (" hasta %s" % fmt_month(security_end) if security_end else "")
                              + ". Sirve para proyectos que aún no funcionan con las estables.")
    else:
        pill = label("Sin soporte", "estado", "soporte-no")
        pill.set_tooltip_text("Sin parches"
                              + (" (desde %s)" % fmt_month(security_end) if security_end else "")
                              + ". Solo para proyectos antiguos.")
    return pill


def fmt_minutes(secs):
    return "menos de 1 min" if secs < 60 else "%d min" % ((secs + 30) // 60)


def fmt_clock(secs):
    """Tiempo transcurrido como un reloj: 0:42, 3:05, 1:02:10"""
    secs = int(secs)
    return ("%d:%02d:%02d" % (secs // 3600, secs // 60 % 60, secs % 60)) if secs >= 3600 else \
        "%d:%02d" % (secs // 60, secs % 60)


def time_left(elapsed, done, left):
    """Lo que queda, al ritmo de hasta ahora (done % en elapsed segundos; quedan left %)."""
    if done < 3 or elapsed < 3:
        return "calculando lo que queda…"
    secs = int(elapsed * left / done)
    if secs < 60:
        return "quedan unos %d s" % max(5, (secs + 4) // 5 * 5)
    if secs < 90:
        return "queda 1 min"
    if secs < 3600:
        return "quedan unos %d min" % ((secs + 30) // 60)
    return "quedan unas %d h %02d min" % (secs // 3600, secs // 60 % 60)


class Console:
    """El registro de una tarea como lo pinta una terminal: \r vuelve al principio de la línea (las
    barras de las descargas se quedan en una línea que avanza), ESC[nA sube n líneas y ESC[K / ESC[2K
    las borran (docker pull), y las líneas seguidas que solo cambian en sus números y llevan un % se
    quedan en una sola, que va subiendo. Solo las últimas líneas se pueden reescribir: las de antes
    pasan al texto fijo."""
    LIVE = 80
    TOKEN = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])|\x1b[78()][0-9A-Za-z]?|\r\n|\r|\n|\x08")

    def __init__(self, buf):
        self.buf = buf
        self.fixed = 0            # caracteres del texto fijo (al principio del buffer)
        self.lines, self.row, self.col = [""], 0, 0

    def put(self, s):
        line = self.lines[self.row]
        if len(line) < self.col:
            line += " " * (self.col - len(line))
        self.lines[self.row] = line[:self.col] + s + line[self.col + len(s):]
        self.col += len(s)

    def newline(self):
        # Un contador (12 %, 13 %, …) en líneas seguidas: se queda la última
        if self.row > 0 and "%" in self.lines[self.row]:
            shape = re.sub(r"\d+(?:[.,]\d+)?", "#", self.lines[self.row].strip())
            if shape == re.sub(r"\d+(?:[.,]\d+)?", "#", self.lines[self.row - 1].strip()):
                del self.lines[self.row - 1]
                self.row -= 1
        self.row += 1
        self.col = 0
        if self.row == len(self.lines):
            self.lines.append("")

    def write(self, text):
        pos = 0
        for m in self.TOKEN.finditer(text):
            if m.start() > pos:
                self.put(text[pos:m.start()])
            pos = m.end()
            tok = m.group(0)
            if tok in ("\n", "\r\n"):
                self.newline()
            elif tok == "\r":
                self.col = 0
            elif tok == "\x08":
                self.col = max(0, self.col - 1)
            elif m.group(2):
                arg, cmd = m.group(1), m.group(2)
                n = int(arg) if arg.isdigit() else 1
                if cmd == "A":
                    self.row = max(0, self.row - n)
                elif cmd == "B":
                    self.row = min(len(self.lines) - 1, self.row + n)
                elif cmd == "G":
                    self.col = max(0, n - 1)
                elif cmd == "K":
                    line = self.lines[self.row]
                    self.lines[self.row] = "" if arg == "2" else " " * min(self.col, len(line)) + \
                        line[self.col:] if arg == "1" else line[:self.col]
        if pos < len(text):
            self.put(text[pos:])
        self.show()

    def show(self):
        frozen = []
        while self.row > self.LIVE:
            frozen.append(self.lines.pop(0))
            self.row -= 1
        live = "\n".join(self.lines)
        self.buf.delete(self.buf.get_iter_at_offset(self.fixed), self.buf.get_end_iter())
        if frozen:
            fixed = "\n".join(frozen) + "\n"
            self.buf.insert(self.buf.get_end_iter(), fixed)
            self.fixed += len(fixed)
        self.buf.insert(self.buf.get_end_iter(), live)

    def text(self):
        return self.buf.get_text(self.buf.get_start_iter(), self.buf.get_end_iter(), False)


def fmt_age(secs):
    """Antigüedad aproximada: hace 5 min, hace 3 h, hace 12 días, hace 4 meses, hace 2 años."""
    if secs < 3600:
        return "hace %s" % plural(max(1, secs // 60), "min", "min")
    if secs < 86400:
        return "hace %s" % plural(secs // 3600, "hora", "horas")
    if secs < 60 * 86400:
        return "hace %s" % plural(secs // 86400, "día", "días")
    if secs < 365 * 86400:
        return "hace %s" % plural(secs // (30 * 86400), "mes", "meses")
    return "hace %s" % plural(secs // (365 * 86400), "año", "años")


# Tipo c de la fecha de una base: no se ha importado con lvm-instalador
DB_DATE_HELP = ("Fecha en la que cambiaron por última vez las tablas de la BBDD (al importarla "
                "desde phpMyAdmin, por ejemplo). Las que se suben desde esta versión guardan la "
                "fecha exacta de la importación.")


def db_date_text(when, kind):
    """Fecha de una base para su fila: la de su importación o la del último cambio de sus tablas."""
    if not when:
        return ""
    stamp = time.strftime("%d/%m/%Y a las %H:%M", time.localtime(when))
    age = fmt_age(max(0, int(time.time()) - when))
    return ("Importada el %s  ·  %s" if kind == "i" else
            "Tablas cambiadas el %s  ·  %s") % (stamp, age)


# ---------------------------------------------------------------- tareas con sudo

class Task:
    """Ejecuta un comando del script en una pseudoterminal y muestra su avance en una ventana.

    progress=True: instalaciones (barra y lista de pasos a partir de LVM_PROGRESO).
    El resto: barra en movimiento y la salida en el registro."""

    def __init__(self, app, title, args, progress=False, done_text=None, on_done=None,
                 auto_close=False, env=None, cancel_text=None):
        self.app, self.args, self.progress = app, args, progress
        self.env, self.cancel_text = env or {}, cancel_text
        self.done_text, self.on_done, self.auto_close = done_text, on_done, auto_close
        # (escondida con «Seguir en segundo plano»: el aviso de al lado del visor la trae de vuelta)
        self.background = False
        self.finished = self.cancelled = False
        self.prompts = 0
        self.since_prompt = ""
        self.pending = ""
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")
        self.pfile = None
        self.build(title)
        self.start()

    # ventana
    def build(self, title):
        dlg = Gtk.Dialog(title=title, transient_for=self.app.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(620, -1)
        dlg.get_header_bar().set_show_close_button(False)
        # (Esc o cerrarla con la tarea en marcha: sigue en segundo plano, si la ventana tiene su aviso)
        dlg.connect("delete-event", self.on_delete)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=24)
        # Al terminar bien, un check verde grande: «Terminado» en gris no se ve de un vistazo
        ok_icon = "emblem-ok-symbolic" if Gtk.IconTheme.get_default().has_icon(
            "emblem-ok-symbolic") else "object-select-symbolic"
        self.done_icon = css(icon(ok_icon, 64), "nv-hecho")
        self.done_icon.set_no_show_all(True)
        box.pack_start(self.done_icon, False, False, 0)
        self.head = label(title, xalign=0.5, justify=Gtk.Justification.CENTER)
        css(self.head, "nv-titulo")
        self.head.set_line_wrap(True)
        box.pack_start(self.head, False, False, 0)
        # Encima de la barra: lo que se hace (a la izquierda) y el porcentaje con lo que queda
        top = Gtk.Box(spacing=12, margin_top=4)
        self.what = label("", "nv-tenue", ellipsize=3)
        top.pack_start(self.what, True, True, 0)
        self.pct = label("", "nv-porcentaje")
        top.pack_end(self.pct, False, False, 0)
        box.pack_start(top, False, False, 0)
        self.bar = css(Gtk.ProgressBar(), "nv-progreso")
        box.pack_start(self.bar, False, False, 0)
        self.info = label("", "nv-chico", "nv-tenue")
        box.pack_start(self.info, False, False, 0)
        # Porcentaje que se lee en la salida (tareas sin progreso propio): (primero, último, cuándo empezó)
        self.seen_pct = None

        self.parts_box = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        self.parts_box.set_no_show_all(True)
        box.pack_start(self.parts_box, False, False, 0)
        self.parts_shown = []

        self.expander = Gtk.Expander(label="Ver registro", expanded=not self.progress)
        self.log = css(Gtk.TextView(editable=False, monospace=True, cursor_visible=False,
                                    wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=14, right_margin=14,
                                    top_margin=10, bottom_margin=10, pixels_below_lines=2), "log", "nv-consola")
        self.console = Console(self.log.get_buffer())
        self.log_sw = css(Gtk.ScrolledWindow(min_content_height=220 if self.progress else 180, margin_top=8),
                          "nv-consola-marco")
        self.log_sw.add(self.log)
        self.expander.add(self.log_sw)
        box.pack_start(self.expander, True, True, 0)

        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        # Si falla: el informe del error (o el registro) en una ventana para copiarlo
        self.report_btn = css(Gtk.Button(label="Ver el log del error"), "pildora")
        self.report_btn.set_no_show_all(True)
        self.report_btn.connect("clicked", self.show_report)
        buttons.pack_start(self.report_btn, False, False, 0)
        self.extra_btn = css(Gtk.Button(), "verde", "pildora")
        self.extra_btn.set_no_show_all(True)
        buttons.pack_start(self.extra_btn, False, False, 0)
        self.bg_btn = css(Gtk.Button(label="Seguir en segundo plano",
                                     tooltip_text="Esconder esta ventana y seguir usando el programa"), "pildora")
        self.bg_btn.connect("clicked", self.to_background)
        self.bg_btn.set_no_show_all(not hasattr(self.app, "nv_task_badge"))
        buttons.pack_start(self.bg_btn, False, False, 0)
        self.close_btn = css(Gtk.Button(label="Cancelar"), "pildora")
        self.close_btn.connect("clicked", self.on_close)
        buttons.pack_start(self.close_btn, False, False, 0)
        box.pack_start(buttons, False, False, 0)

        dlg.get_content_area().add(box)
        self.dlg = dlg
        dlg.show_all()

    def append(self, text):
        if not text:
            return
        self.console.write(text)
        if not self.progress:
            found = re.findall(r"(?<![\d.,])(\d{1,3})(?:[.,]\d+)?\s?%", ANSI.sub("", text))
            found = [int(n) for n in found if int(n) <= 100]
            if found:
                now = time.time()
                if self.seen_pct is None or found[-1] < self.seen_pct[1] - 30:
                    self.seen_pct = (found[-1], found[-1], now)
                else:
                    self.seen_pct = (self.seen_pct[0], found[-1], self.seen_pct[2])
        adj = self.log_sw.get_vadjustment()
        GLib.idle_add(lambda: adj.set_value(adj.get_upper() - adj.get_page_size()) and False)

    # proceso
    def start(self):
        env = script_env(**self.env)
        if self.progress:
            fd, self.pfile = tempfile.mkstemp(prefix="lvm-progreso-", dir="/tmp")
            os.close(fd)
            env["LVM_PROGRESO"] = self.pfile
        # (lo que cambia algo pide la contraseña al empezar: cancelarla no deja nada a medias)
        env["LVM_TAREA"] = "1"
        self.master, slave = pty.openpty()
        # Terminal exclusiva: ningún otro programa de tu usuario (el PHP de una web, por ejemplo)
        # puede abrirla para leer la contraseña o escribir la marca de sudo. Root (sudo) sí
        fcntl.ioctl(slave, termios.TIOCEXCL)
        fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 160, 0, 0))
        self.tty = os.fstat(slave).st_rdev

        def as_terminal():
            # La pseudoterminal es la terminal de la sesion: sudo pide ahi la contraseña y
            # recuerda la autorizacion como en una terminal normal
            fcntl.ioctl(1, termios.TIOCSCTTY, 0)

        self.proc = subprocess.Popen(script_cmd(*self.args), stdin=subprocess.DEVNULL,
                                     stdout=slave, stderr=slave, env=env,
                                     # (preexec_fn con hilos: solo hace un ioctl, sin reservar memoria ni bloqueos)
                                     start_new_session=True, preexec_fn=as_terminal)  # noqa: PLW1509
        os.close(slave)
        flags = fcntl.fcntl(self.master, fcntl.F_GETFL)
        fcntl.fcntl(self.master, fcntl.F_SETFL, flags | os.O_NONBLOCK)
        self.watch = GLib.io_add_watch(GLib.IOChannel.unix_new(self.master), GLib.PRIORITY_DEFAULT,
                                       GLib.IOCondition.IN | GLib.IOCondition.HUP
                                       | GLib.IOCondition.ERR, self.on_output)
        GLib.child_watch_add(GLib.PRIORITY_DEFAULT, self.proc.pid, self.on_exit)
        self.started = time.time()
        self.timer = GLib.timeout_add(1000 if self.progress else 120, self.on_timer)
        self.on_timer()

    def read_all(self):
        chunks = []
        while True:
            try:
                data = os.read(self.master, 65536)
            except BlockingIOError:
                break
            except OSError:
                return chunks, True
            if not data:
                return chunks, True
            chunks.append(data)
        return chunks, False

    def on_output(self, *_):
        chunks, closed = self.read_all()
        for data in chunks:
            self.feed(self.decoder.decode(data))
        if closed:
            self.watch = None
            return False
        return True

    def feed(self, text):
        self.pending += text
        while SUDO_MARK in self.pending:
            before, self.pending = self.pending.split(SUDO_MARK, 1)
            self.append(before)
            self.since_prompt += before
            self.ask_password()
        # Se guarda un trozo que pueda ser el principio de la marca
        keep = 0
        for i in range(1, len(SUDO_MARK)):
            if self.pending.endswith(SUDO_MARK[:i]):
                keep = i
        out, self.pending = (self.pending[:-keep], self.pending[-keep:]) if keep else \
            (self.pending, "")
        self.since_prompt += out
        self.append(out)

    def sudo_asking(self):
        """¿Hay un sudo de root de esta tarea (descendiente de su proceso) en su terminal y sin hijos?
        Es lo que pasa cuando pide la contraseña. Cualquier programa de la tarea puede escribir la
        marca (la hereda en SUDO_PROMPT) y apagar el eco: así no se le manda a él"""
        procs = {}
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            try:
                with open("/proc/%s/stat" % name, "rb") as f:
                    stat = f.read().decode("ascii", "replace")
                with open("/proc/%s/status" % name, "rb") as f:
                    status = f.read().decode("utf-8", "replace")
            except OSError:
                continue
            comm = stat[stat.find("(") + 1:stat.rfind(")")]
            rest = stat[stat.rfind(")") + 2:].split()
            uid = next((l.split()[1:3] for l in status.splitlines() if l.startswith("Uid:")), [])
            if len(rest) < 5 or len(uid) < 2:
                continue
            tty = int(rest[4])
            procs[int(name)] = (int(rest[1]), comm, uid[1], os.makedev((tty >> 8) & 0xfff,
                                                                      (tty & 0xff) | ((tty >> 12) & 0xfff00)))
        children = {}
        for pid, (ppid, *_) in procs.items():
            children.setdefault(ppid, []).append(pid)
        stack, seen, found = [self.proc.pid], set(), []
        while stack:
            p = stack.pop()
            if p in seen:
                continue
            seen.add(p)
            for c in children.get(p, []):
                stack.append(c)
                # Solo cuenta un sudo de root (el de verdad es setuid): un programa tuyo que se
                # llame sudo no vale. Y en la terminal de la tarea, sin hijos (con hijos ya está
                # ejecutando la orden y la contraseña iría a ella)
                _, comm, euid, tty = procs[c]
                if comm == "sudo" and euid == "0" and tty == self.tty and not children.get(c):
                    found.append(c)
        return bool(found)

    def ask_password(self):
        retry = self.prompts > 0 and re.search(r"(?i)sorry|lo siento|incorrect|intent",
                                               self.since_prompt)
        self.prompts += 1
        self.since_prompt = ""
        if not self.sudo_asking():
            self.append("\nAviso: se ha pedido la contraseña, pero no la pide sudo. No se ha "
                        "enviado y se cancela la tarea.\n")
            self.cancel()
            return
        resp, password = password_dialog(self.dlg, os.environ.get("USER", ""), retry)
        if resp != Gtk.ResponseType.OK:
            self.cancel()
            return
        # Mientras el cuadro estaba abierto, sudo ha podido dejar de esperar: se vuelve a mirar
        if self.finished or not self.sudo_asking():
            self.append("\nAviso: sudo ya no esperaba la contraseña. No se ha enviado.\n")
            self.cancel()
            return
        # sudo apaga el eco de la terminal antes de pedirla. Si sigue encendido, quien la pide no
        # es sudo: no se escribe (se veria en el registro o la leeria otro programa)
        try:
            echo = termios.tcgetattr(self.master)[3] & termios.ECHO
        except termios.error:
            echo = True
        if echo:
            self.append("\nAviso: se ha pedido la contraseña, pero no la pide sudo. No se ha "
                        "enviado y se cancela la tarea.\n")
            self.cancel()
            return
        try:
            os.write(self.master, (password + "\n").encode())
        except OSError:
            pass

    def on_timer(self):
        if self.finished:
            return False
        if self.progress:
            self.show_progress(read_progress(self.pfile))
        elif self.seen_pct:
            # Sin progreso propio, pero la salida da un porcentaje (una descarga, por ejemplo)
            first, pct, since = self.seen_pct
            self.bar.set_fraction(pct / 100)
            self.what.set_label("Trabajando…")
            self.set_pct(pct, time_left(time.time() - since, pct - first, 100 - pct))
            self.info.set_label("Tiempo: %s" % fmt_clock(time.time() - self.started))
        else:
            self.bar.pulse()
            self.what.set_label("Trabajando…")
            self.pct.set_label("")
            self.info.set_label("Tiempo: %s  ·  sin porcentaje: esta tarea no dice cuánto le queda"
                                % fmt_clock(time.time() - self.started))
        return True

    def set_pct(self, pct, left):
        self.pct.set_label("%d %%" % pct + ("   ·   %s" % left if left else ""))

    def show_progress(self, p):
        elapsed = int(time.time() - self.started)
        if not p:
            self.bar.pulse()
            self.what.set_label("Preparando…")
            self.pct.set_label("0 %")
            self.info.set_label("Tiempo: %s" % fmt_clock(elapsed))
            return
        pct = p["pct"]
        total = ((p["k"] - 1) * 100 + pct) // p["n"]
        self.head.set_label(p["name"] + ("   (%d de %d)" % (p["k"], p["n"]) if p["n"] > 1 else ""))
        self.bar.set_fraction(total / 100)
        what = p["what"] or ("terminado" if pct >= 100 else "")
        self.what.set_label(what[:1].upper() + what[1:])
        since = int(time.time() - (p["started"] or self.started))
        self.set_pct(total, time_left(since, pct, 100 - pct) if pct < 100 else "")
        text = "Tiempo: %s" % fmt_clock(since)
        if p["mode"] == "fdpos" and p["total"]:
            text = "%s de %s   ·   %s" % (fmt_size(min(p["done"], p["total"])),
                                         fmt_size(p["total"]), text)
        self.info.set_label(text)
        self.show_parts(p["parts"], p["cur"])

    def show_parts(self, parts, cur):
        if not parts:
            return
        if parts != self.parts_shown:
            clear(self.parts_box)
            self.part_rows = []
            for name in parts:
                r = ActionRow(name)
                st = Gtk.Stack()
                st.add_named(label("…", "dim-label"), "pend")
                st.add_named(Gtk.Spinner(active=True), "run")
                st.add_named(css(icon("object-select-symbolic"), "punto-verde"), "ok")
                st.add_named(css(icon("dialog-error-symbolic"), "error"), "error")
                r.add_suffix(st)
                self.parts_box.add(r)
                self.part_rows.append(st)
            # (sin no_show_all: con él, show_all no muestra las filas y la lista sale vacía)
            self.parts_box.set_no_show_all(False)
            self.parts_box.show_all()
            self.parts_shown = parts
        for i, st in enumerate(self.part_rows, 1):
            st.set_visible_child_name("ok" if i < cur else "run" if i == cur else "pend")

    def on_exit(self, _pid, status):
        rc = os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1
        chunks, _ = self.read_all()
        for data in chunks:
            self.feed(self.decoder.decode(data))
        self.append(self.pending)
        if self.watch:
            GLib.source_remove(self.watch)
        try:
            os.close(self.master)
        except OSError:
            pass
        self.finish(rc)

    def on_delete(self, *_):
        if self.finished:
            return False
        if hasattr(self.app, "nv_task_badge"):
            self.to_background()
        return True

    def to_background(self, *_):
        """La tarea sigue sin su ventana: el programa se puede usar (sin lanzar otra tarea a la vez) y, al
        lado del visor, una flecha verde que late la trae de vuelta."""
        if self.finished or not hasattr(self.app, "nv_task_badge"):
            return
        self.background = True
        self.dlg.set_modal(False)
        self.dlg.hide()
        self.app.nv_task_badge(self)

    def to_front(self, *_):
        self.background = False
        if hasattr(self.app, "nv_task_badge"):
            self.app.nv_task_badge(None)
        self.dlg.set_modal(True)
        self.dlg.present()

    def finish(self, rc):
        self.finished = True
        self.bg_btn.hide()
        hidden = self.background
        if hidden:
            self.background = False
            self.app.nv_task_badge(None)
        p = read_progress(self.pfile) if self.pfile else None
        if self.pfile:
            try:
                os.unlink(self.pfile)
            except OSError:
                pass
        ok = rc == 0 and not self.cancelled
        self.info.set_label("Tiempo total: %s" % fmt_clock(time.time() - self.started))
        self.bar.set_fraction(1 if ok else self.bar.get_fraction())
        self.close_btn.set_label("Cerrar")
        if self.cancelled:
            self.head.set_label("Cancelado")
            self.what.set_label("Cancelado")
            self.pct.set_label("")
        elif ok:
            self.head.set_label(self.done_text or "Terminado")
            self.what.set_label("Terminado")
            self.pct.set_label("100 %")
            self.done_icon.show()
            self.head.set_xalign(0.5)
        else:
            self.head.set_label("No se ha podido completar")
            self.what.set_label("Error")
            self.pct.set_label("")
            css(self.bar, "nv-progreso-error")
            self.expander.set_expanded(True)
            self.report_btn.show()
            if p and self.part_rows_present():
                for i, st in enumerate(self.part_rows, 1):
                    if i == p["cur"]:
                        st.set_visible_child_name("error")
        if p:
            self.show_results(p, ok)
        if ok and self.progress and self.part_rows_present():
            for st in self.part_rows:
                st.set_visible_child_name("ok")
        if self.on_done:
            self.on_done(ok, self, p)
        if ok and self.auto_close:
            self.dlg.destroy()
            self.app.toast(self.done_text or "Terminado")
        elif hidden:
            # (en segundo plano: vuelve para enseñar cómo ha ido; si ha fallado, con su registro)
            self.dlg.set_modal(True)
            self.dlg.present()

    def log_text(self):
        return self.console.text()

    def show_report(self, *_):
        """El informe que deja el script al fallar una instalacion (uno por version con error) o,
        si no lo hay, el registro entero"""
        log = self.log_text()
        # Solo los informes de la carpeta de registros: la linea podria escribirla otro programa
        # para mostrar (y copiar) cualquier fichero
        logs = os.path.realpath(LOG_DIR) + os.sep
        paths = [p for p in dict.fromkeys(re.findall(r"^Informe del error: (.+?)\s*$", log, re.M))
                 if os.path.realpath(p).startswith(logs) and os.path.basename(p) == "informe-error.txt"]
        parts = []
        for path in paths:
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    parts.append(f.read().rstrip())
            except OSError:
                pass
        text = ("\n\n" + "=" * 70 + "\n\n").join(parts) if parts else log.strip()
        folder = os.path.dirname(paths[-1]) if parts else LOG_DIR

        dlg = Gtk.Dialog(title="Log del error", transient_for=self.dlg, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(820, 560)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=16)
        box.pack_start(label("Copia el texto para buscar la solución o para enviarlo. "
                             + ("Incluye el sistema, el paso que ha fallado y sus errores. "
                                if parts else "")
                             + "Los logs completos están en %s." % folder,
                             "dim-label", wrap=True), False, False, 0)
        view = css(Gtk.TextView(editable=False, monospace=True, wrap_mode=Gtk.WrapMode.CHAR),
                   "log")
        view.get_buffer().set_text(text)
        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.add(view)
        box.pack_start(sw, True, True, 0)
        row = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        copy = css(Gtk.Button(label="Copiar todo"), "verde", "pildora")

        def on_copy(*_):
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1)
            copy.set_label("Copiado")
            GLib.timeout_add(2000, lambda: copy.set_label("Copiar todo") and False)

        copy.connect("clicked", on_copy)
        row.pack_start(copy, False, False, 0)
        folder_btn = css(Gtk.Button(label="Abrir la carpeta de logs"), "pildora")
        folder_btn.connect("clicked", lambda *_: self.app.open_uri("file://" + folder))
        row.pack_start(folder_btn, False, False, 0)
        close = css(Gtk.Button(label="Cerrar"), "pildora")
        close.connect("clicked", lambda *_: dlg.destroy())
        row.pack_start(close, False, False, 0)
        box.pack_start(row, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.show_all()

    def part_rows_present(self):
        return bool(getattr(self, "part_rows", None))

    def show_results(self, p, ok):
        res = [r for r in p["results"] if not r[0].startswith("bd:")]
        if len(res) > 1 or (res and not ok):
            good = [i for i, rc in res if rc == "0"]
            bad = [i for i, rc in res if rc != "0"]
            text = []
            if good:
                text.append("Instaladas: " + ", ".join("lampp-" + item_folder(i) for i in good))
            if bad:
                text.append("Con error: " + ", ".join("lampp-" + item_folder(i) for i in bad)
                            + ". No se ha instalado nada de ellas; mira el registro.")
            self.info.set_label("\n".join(text))
            if res and len(good) == len(res):
                self.head.set_label(self.done_text or "Terminado")

    def offer(self, text, callback):
        self.extra_btn.set_label(text)
        self.extra_btn.connect("clicked", lambda *_: (self.dlg.destroy(), callback()))
        self.extra_btn.show()

    def cancel(self):
        if self.finished:
            return
        self.cancelled = True
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
        except OSError:
            pass

    def on_close(self, *_):
        if self.finished:
            self.dlg.destroy()
            return
        if self.progress:
            title, text, ok = self.cancel_text or (
                "¿Cancelar la instalación?",
                "Se pierde lo descargado y compilado. Las versiones instaladas no se tocan.",
                "Cancelar la instalación")
            if not confirm(self.dlg, title, text, ok, destructive=True):
                return
        self.cancel()


# ---------------------------------------------------------------- aplicacion

class App(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.data = None
        self.branches = None
        self.php_dates = {}
        # Pestaña Docker: datos de gui-docker (None hasta leerlos) y el formulario de proyecto nuevo
        self.docker = None
        self.docker_form = {}
        self.branches_error = None
        self.expanded = set()
        try:
            with open(FOLDED_FILE, encoding="utf-8") as f:
                self.folded = {l.strip() for l in f if l.strip()}
        except OSError:
            self.folded = set()
        self.extra_patches = []
        self.busy = False
        # Formulario «Subir o actualizar una base de datos» (se conserva al redibujar la pestaña)
        self.imp = {"file": None, "db": None, "folder": None, "project": None}
        self.db_pwd = {}
        # Dominios de los vhosts (pestaña Hosts): None hasta leerlos
        self.hosts = None
        # Apache, MariaDB y FTP de la version montada (pestaña Servicios): None hasta leerlos
        self.services = None
        # Proyectos de /opt/htdocs (bloque «Cargar proyecto» de Versiones): None hasta leerlos
        self.projects = None
        # Los repositorios del buscador de Nuevo proyecto (np_repos_load)
        self.np_repos, self.np_repos_when, self.np_repos_busy = None, 0, False
        # Formulario «Nuevo proyecto con dominio falseado» (se conserva al redibujar la pestaña)
        self.newdom = {"domain": "", "folder": "", "db": ""}

    # ventana
    def do_activate(self):
        if getattr(self, "win", None):
            self.win.present()
            return
        # Mano al pasar el ratón por cualquier botón (GTK 3 no tiene cursor en CSS): se pone en la
        # ventana de eventos del botón cada vez que el ratón entra, según esté activo o no
        hand = Gdk.Cursor.new_from_name(Gdk.Display.get_default(), "pointer")

        def pointer_hook(widget, event, *_):
            if isinstance(widget, (Gtk.Button, Gtk.Switch)) and event.window is not None:
                event.window.set_cursor(hand if widget.is_sensitive() else None)
            return True
        GObject.add_emission_hook(Gtk.Widget, "enter-notify-event", pointer_hook)
        prov = Gtk.CssProvider()
        prov.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        theme = Gtk.IconTheme.get_default()
        # El icono es un PNG suelto en ~/.local/share/icons (no de un tema): has_icon no lo ve
        self.icon = ICON if theme.lookup_icon(ICON, 24, 0) else "utilities-terminal"
        Gtk.Window.set_default_icon_name(self.icon)

        for name, cb in [("localhost", lambda *_: self.open_uri("http://localhost/")),
                         ("phpmyadmin", lambda *_: self.open_uri("http://127.0.0.1/phpmyadmin/")),
                         ("vhosts", self.on_vhosts), ("hosts", self.on_hosts),
                         ("logs", lambda *_: self.open_uri("file://" + LOG_DIR)),
                         ("update", lambda *_: self.check_package(manual=True)),
                         ("terminal", self.on_terminal), ("refresh", self.on_refresh),
                         ("changes", self.on_changes), ("about", self.on_about)]:
            act = Gio.SimpleAction.new(name, None)
            act.connect("activate", cb)
            self.add_action(act)

        self.win = Gtk.ApplicationWindow(application=self, title="Nexum Dev Stack")
        self.win.set_default_size(920, 760)

        header = Gtk.HeaderBar(show_close_button=True)
        title = Gtk.Box(spacing=8)
        title.pack_start(icon(self.icon, 24), False, False, 0)
        self.title_lbl = label("Nexum Dev Stack", "title")
        title.pack_start(self.title_lbl, False, False, 0)
        header.set_custom_title(title)
        menu = Gio.Menu()
        sec = Gio.Menu()
        sec.append("Abrir localhost", "app.localhost")
        sec.append("Abrir phpMyAdmin", "app.phpmyadmin")
        sec.append("Editar vhosts", "app.vhosts")
        sec.append("Editar hosts", "app.hosts")
        menu.append_section(None, sec)
        sec = Gio.Menu()
        sec.append("Volver a leer las versiones", "app.refresh")
        # De momento, el .deb de Descargas; mas adelante, un repositorio
        sec.append("Buscar actualizaciones", "app.update")
        sec.append("Abrir el panel en la terminal", "app.terminal")
        sec.append("Carpeta de registros", "app.logs")
        menu.append_section(None, sec)
        sec = Gio.Menu()
        sec.append("Novedades", "app.changes")
        sec.append("Acerca de Nexum Dev Stack", "app.about")
        menu.append_section(None, sec)
        mb = Gtk.MenuButton(menu_model=menu)
        mb.add(icon("open-menu-symbolic"))
        header.pack_end(mb)
        self.win.set_titlebar(header)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.page_versions, self.ver_box = page()
        # Instalar va dentro de Versiones, debajo de las instaladas
        self.inst_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        self.page_dbs, self.db_box = page()
        self.page_tools, self.tools_box = page()
        self.page_hosts, self.hosts_box = page()
        self.page_services, self.services_box = page()
        self.page_docker, self.docker_box = page()
        self.stack.add_named(self.page_versions, "versiones")
        self.stack.add_named(self.page_services, "servicios")
        self.stack.add_named(self.page_hosts, "hosts")
        self.stack.add_named(self.page_dbs, "bbdd")
        self.stack.add_named(self.page_tools, "herramientas")
        self.stack.add_named(self.page_docker, "docker")

        main = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        # Apartados en una barra a la izquierda, como Configuración de Ubuntu
        body = Gtk.Box()
        self.tabs_box = self.build_tabs()
        body.pack_start(self.tabs_box, False, False, 0)
        body.pack_start(self.stack, True, True, 0)
        main.pack_start(body, True, True, 0)
        main.pack_start(Gtk.Separator(), False, False, 0)
        self.foot = label("", "dim-label", "firma", xalign=0.5, margin=6)
        main.pack_start(self.foot, False, False, 0)

        overlay = Gtk.Overlay()
        overlay.add(main)
        overlay.add_overlay(self.build_toast())
        self.win.add(overlay)
        for box in (self.ver_box, self.db_box, self.inst_box):
            self.loading(box)
        # Los datos se leen antes de mostrar la ventana (tarda poco) para abrirla ya con el tamaño
        # que necesita la pestaña Bases de datos, sin saltos
        try:
            res = subprocess.run(script_cmd("gui-datos"), stdin=subprocess.DEVNULL,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 env=script_env(), timeout=10)
            self.on_data(res.returncode, res.stdout.decode("utf-8", "replace"))
            self.fit_height()
        except Exception:  # noqa: BLE001 - si falla, se abre con el tamaño por defecto
            pass
        self.win.show_all()
        self.toast_rev.set_reveal_child(False)
        self.reload(branches=True)
        GLib.timeout_add_seconds(20, self.on_tick)
        # El paquete nuevo de Descargas ya no se busca solo al abrir: se instala como root y
        # cualquier web puede dejar un fichero en Descargas. Se busca desde Herramientas
        if os.environ.get("LVM_CAPTURA"):
            GLib.timeout_add(2500, self.capture_all)

    # ------------------------------------------- paquete .deb nuevo en Descargas
    def check_package(self, manual=False, auto=False):
        """Buscar una versión nueva (menú) o, con auto, al abrir la ventana (update_check_due): sin
        avisar si no hay."""
        def got(_rc, out):
            found, notes = False, []
            for f in parse_lines(out):
                if f[0] == "N" and len(f) >= 5:
                    found = True
                    # (si se dice que no, se vuelve a ofrecer la próxima vez que toque buscar)
                    self.offer_package(f[1], f[2], f[3], "|".join(f[4:]))
                elif f[0] == "I" and len(f) >= 2:
                    notes.append("|".join(f[1:]))
            if manual and not found:
                if notes:
                    message(self.win, "No hay ninguna versión nueva para instalar desde aquí",
                            "Tienes la %s.\n\n%s" % (self.data["version"], "\n\n".join(notes)))
                else:
                    self.toast("Tienes la última versión (%s)" % self.data["version"])
            return False
        if not auto:
            self.toast("Buscando actualizaciones…")
        run_quick(["gui-paquete"], got)
        return False

    def offer_package(self, version, when, sha, path):
        current = (self.data or {}).get("version", "")
        if os.path.dirname(path) == os.path.join(LOG_DIR, "actualizaciones"):
            where = "GitHub, publicada el %s" % when
        else:
            where = "%s (%s, del %s)" % (os.path.dirname(path), os.path.basename(path), when)
        if not confirm(self.win, "Hay una versión nueva de Nexum Dev Stack",
                       "De la %s a la %s (%s), firmada. Pide la contraseña de administrador y la ventana "
                       "se vuelve a abrir. Tus versiones, proyectos y BBDD no se tocan.\n\nHuella SHA-256:\n%s"
                       % (current, version, where, sha),
                       "Actualizar a la %s" % version):
            return False
        if SIMULATE:
            self.toast("[simulación] pkexec apt-get install -y %s" % path)
            return True

        dlg = Gtk.Dialog(title="Actualizando", transient_for=self.win, modal=True, deletable=False)
        box = Gtk.Box(spacing=12, margin=24)
        box.pack_start(Gtk.Spinner(active=True), False, False, 0)
        box.pack_start(label("Instalando la versión %s…" % version), False, False, 0)
        dlg.get_content_area().add(box)
        dlg.show_all()

        def done(rc, out):
            dlg.destroy()
            if rc == 0:
                # La version nueva esta en /opt/lvm-instalador: se abre su ventana cuando se
                # cierre esta (misma aplicacion: si siguiera abierta, solo se traeria al frente)
                subprocess.Popen(["sh", "-c", 'sleep 1; exec "$0" ventana',
                                  "/opt/lvm-instalador/lvm-instalador.sh"], start_new_session=True,
                                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL)
                self.quit()
            elif rc in (126, 127):
                self.toast("Actualización cancelada")
            elif "instalalo en la terminal" in out:
                self.terminal_install(version, path)
            else:
                message(self.win, "No se ha podido actualizar", out[-1200:], Gtk.MessageType.ERROR)
            return False

        def work():
            try:
                # Con el paquete 1.30.3 o mas nuevo instalado, la contraseña se pide con el
                # mensaje en español de su accion de polkit (dev.hexer.lvm-instalador.policy)
                # El ayudante (de root) copia el paquete a su carpeta y comprueba allí la huella que
                # se ha mostrado, su contenido y sus scripts. Sin él no se instala nada desde aquí
                helper = "/opt/lvm-instalador/lvm-actualizar"
                cmd = ["pkexec", helper, path, sha]
                res = subprocess.run(cmd,
                                     stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT)
                rc, out = res.returncode, res.stdout.decode("utf-8", "replace")
            except OSError as exc:
                rc, out = 1, str(exc)
            GLib.idle_add(done, rc, out)
        threading.Thread(target=work, daemon=True).start()
        return True

    def terminal_install(self, version, path):
        """La versión nueva cambia el ayudante de actualización (o su acción de polkit): el ayudante
        instalado no la acepta, a propósito, y hay que instalarla una vez en la terminal. Se explica
        y se da la orden lista para copiar (sin el «Tubería rota» de dpkg-deb, que solo confunde)."""
        cmd = "sudo apt install %s" % shlex.quote(path)
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True, message_type=Gtk.MessageType.INFO,
                                buttons=Gtk.ButtonsType.NONE,
                                text="La versión %s se instala una vez en la terminal" % version)
        dlg.format_secondary_text(
            "Esta versión cambia el programa que instala las actualizaciones, y el que tienes no "
            "puede dar por buena su propia sustitución. No es un error ni un paquete dañado.\n\n"
            "Abre una terminal (Ctrl+Alt+T), pega esta orden y escribe tu contraseña:\n\n%s\n\n"
            "Después, abre de nuevo Nexum Dev Stack. Las siguientes versiones se vuelven a "
            "actualizar desde aquí." % cmd)
        dlg.add_button("Copiar la orden", 1)
        dlg.add_button("Cerrar", Gtk.ResponseType.CLOSE)
        widen(dlg)
        if run_dialog(dlg) == 1:
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(cmd, -1)
            self.toast("Orden copiada: pégala en la terminal")
        dlg.destroy()

    def fit_height(self):
        """Alto inicial para que la pestaña Bases de datos se vea entera sin agrandar la ventana
        (sin pasar del alto de la pantalla)."""
        self.db_box.show_all()
        width = max(self.db_box.get_preferred_width()[1], 580)
        need = self.db_box.get_preferred_height_for_width(width)[1]
        self.foot.show_all()
        need += self.foot.get_preferred_height()[1]
        need += 1 + 24  # separador y un margen por si crece (aviso…)
        try:
            mon = Gdk.Display.get_default().get_primary_monitor() or \
                Gdk.Display.get_default().get_monitor(0)
            limit = mon.get_workarea().height - 90  # barra de título y bordes
        except Exception:  # noqa: BLE001
            limit = 1000
        height = max(760, min(need, limit))
        self.win.set_default_size(1000, height)
        return height

    def build_tabs(self):
        """Barra lateral con los apartados (como Configuración de Ubuntu)."""
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL), "lateral")
        box.set_size_request(210, -1)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE, margin_top=10),
                 "barra-lateral")
        self.tabs = {}
        # Orden: lo que mas se usa primero (cambiar de version y cargar bases de datos)
        for name, text, ic in [("versiones", "Versiones", "view-list-symbolic"),
                               ("bbdd", "BBDD", "drive-multidisk-symbolic"),
                               ("servicios", "Servicios", "network-server-symbolic"),
                               ("hosts", "Hosts", "network-workgroup-symbolic"),
                               ("docker", "Docker", "logo:docker"),
                               # Lo que se usa de vez en cuando
                               ("herramientas", "Herramientas", "applications-utilities-symbolic")]:
            row = Gtk.ListBoxRow()
            inner = Gtk.Box(spacing=12)
            # (Docker con su logotipo, de un color como los demás iconos del tema)
            inner.pack_start(MonoLogo(ic[5:], 16) if ic.startswith("logo:") else symbol(ic, 16),
                             False, False, 0)
            inner.pack_start(label(text), False, False, 0)
            row.add(inner)
            row.tab_name = name
            lb.add(row)
            self.tabs[name] = row
        lb.connect("row-selected", self.on_tab)
        lb.select_row(self.tabs["versiones"])
        self.tabs_list = lb
        box.pack_start(lb, False, False, 0)
        return box

    def on_tab(self, _lb, row):
        if row is not None:
            self.stack.set_visible_child_name(row.tab_name)
            if row.tab_name == "docker":
                run_quick(["gui-docker"], self.on_docker_data)

    def show_tab(self, name):
        self.tabs_list.select_row(self.tabs[name])

    def build_toast(self):
        self.toast_rev = Gtk.Revealer(halign=Gtk.Align.CENTER, valign=Gtk.Align.END,
                                      margin_bottom=48)
        box = css(Gtk.Box(spacing=12), "app-notification")
        self.toast_lbl = Gtk.Label()
        box.pack_start(self.toast_lbl, False, False, 0)
        self.toast_rev.add(box)
        self.toast_timer = None
        return self.toast_rev

    def toast(self, text):
        self.toast_lbl.set_label(text)
        self.toast_rev.set_reveal_child(True)
        if self.toast_timer:
            GLib.source_remove(self.toast_timer)
        self.toast_timer = GLib.timeout_add_seconds(4, self.hide_toast)

    def hide_toast(self):
        self.toast_rev.set_reveal_child(False)
        self.toast_timer = None
        return False

    def loading(self, box, text="Leyendo…"):
        clear(box)
        spin = Gtk.Box(spacing=10, halign=Gtk.Align.CENTER, margin_top=40)
        spin.pack_start(Gtk.Spinner(active=True), False, False, 0)
        spin.pack_start(label(text, "dim-label"), False, False, 0)
        box.pack_start(spin, False, False, 0)
        box.show_all()

    def open_text(self, path):
        """Abre un fichero de texto con el editor de textos, aunque no tenga extensión (error_log,
        hosts): el programa por defecto según su contenido podría ser otro."""
        app = Gio.AppInfo.get_default_for_type("text/plain", False)
        if app is None:
            self.open_uri(GLib.filename_to_uri(path))
            return
        try:
            app.launch([Gio.File.new_for_path(path)], None)
        except GLib.Error as exc:
            message(self.win, "No se ha podido abrir %s" % path, exc.message, Gtk.MessageType.ERROR)

    def loaded_project_folder(self):
        """Carpeta del proyecto cargado (a la que apunta el enlace del vhost), solo si es una
        carpeta de htdocs."""
        p = self.projects
        if not p or not p.get("current"):
            return None
        cur = p["current"]
        real = os.path.realpath(cur if os.path.isabs(cur) else os.path.join(HTDOCS, cur))
        if os.path.dirname(real) != os.path.realpath(HTDOCS) or not os.path.isdir(real):
            return None
        return real

    def loaded_project_entry(self):
        """Datos (de gui-proyectos) del proyecto cargado, o None."""
        folder = self.loaded_project_folder()
        if folder is None:
            return None
        name = os.path.basename(folder)
        return next((x for x in self.projects["list"] if x["name"] == name), None)

    def loaded_project_db(self):
        """BBDD del proyecto cargado en la versión activa (la vinculada o la de su configuración),
        o vacío."""
        x = self.loaded_project_entry()
        db = ""
        if x and self.data:
            pairs = self.project_pairs(x)
            db = next((d for i, d in pairs if i["folder"] == self.data.get("active")), None) or \
                (pairs[0][1] if pairs else self.project_base(x))
        return db if re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", db or "") else ""

    def loaded_project_admin(self):
        """(tipo, carpeta del panel) del proyecto cargado (project_admin)."""
        folder = self.loaded_project_folder()
        return project_admin(folder) if folder is not None else ("", "")

    def open_project_pma(self):
        """phpMyAdmin con la BBDD del proyecto cargado (en http://127.0.0.1/phpmyadmin/)."""
        db = self.loaded_project_db()
        if not db:
            return
        act = next((i for i in self.installs() if i["folder"] == self.data.get("active")), None)
        # (phpMyAdmin 4 usa db= sin route)
        if act and act.get("pma", "").startswith("4."):
            self.open_uri("http://127.0.0.1/phpmyadmin/index.php?db=%s" % db)
        else:
            self.open_uri("http://127.0.0.1/phpmyadmin/index.php?route=/database/structure&db=%s" % db)

    def open_project_admin(self):
        """Panel de administración del proyecto cargado, por el vhost (web.local). Antes deja al día
        su administrador de pruebas (usuario-pruebas) y abre una página con el usuario y la
        contraseña ya escritos: basta con pulsar Entrar. Si no se puede, el panel como siempre."""
        kind, admin = self.loaded_project_admin()
        if not (admin and self.projects and self.projects["link"]):
            return
        db, folder = self.loaded_project_db(), self.loaded_project_folder()
        self.open_admin_login(kind, admin, "http://%s" % self.projects["link"], os.path.basename(folder or ""),
                              ["usuario-pruebas", db, os.path.basename(folder or "")] if db else None)

    def open_admin_login(self, kind, admin, site, name, cmd):
        """Panel (wp-admin o el de la tienda) de la web <site> (http://web.local, https://x.docker.local)
        con el administrador de pruebas: cmd lo deja al día (usuario-pruebas o docker-usuario-pruebas,
        que dicen A|tipo|usuario|contraseña) y se abre una página con el usuario y la contraseña ya
        escritos. Sin cmd, o si no sale, el panel como siempre."""
        base = "%s/%s/" % (site, admin)
        if not cmd or SIMULATE:
            self.open_uri(base)
            return

        def done(rc, out):
            mine = [l.split("|") for l in out.splitlines() if l.startswith("A|%s|" % kind)]
            if rc != 0 or not mine or len(mine[0]) < 4:
                self.open_uri(base)
                return False
            user, password = mine[0][2], mine[0][3]
            if kind == "wp":
                action = "%s/wp-login.php" % site
                fields = [("log", user, "Usuario o correo"), ("pwd", password, "Contraseña"),
                          ("rememberme", "forever", None), ("redirect_to", base, None)]
                title = "Panel de WordPress"
            else:
                action = base + "index.php?controller=AdminLogin"
                fields = [("email", user, "Correo"), ("passwd", password, "Contraseña"),
                          ("stay_logged_in", "1", None), ("submitLogin", "1", None),
                          ("redirect", "AdminDashboard", None)]
                title = "Back office de PrestaShop"
            url = serve_once(login_page(title, name, action, fields, base))
            self.open_uri(url) if url else self.open_uri(base)
            return False
        run_quick(cmd, done)

    def open_in_vscode(self, folder=None):
        """Abre el proyecto cargado (u otra carpeta de htdocs) en Visual Studio Code. Si ya tiene una
        ventana con esa carpeta, VS Code la trae delante en lugar de abrir otra."""
        folder, app = folder or self.loaded_project_folder(), vscode_app()
        if folder is None:
            message(self.win, "No se encuentra la carpeta del proyecto cargado",
                    "El enlace del vhost no apunta a una carpeta de %s." % HTDOCS, Gtk.MessageType.WARNING)
            return
        if app is None:
            message(self.win, "Visual Studio Code no está instalado",
                    "Instálalo desde code.visualstudio.com o desde el Centro de aplicaciones.",
                    Gtk.MessageType.WARNING)
            return
        try:
            # (con el contexto de la ventana, el escritorio deja que VS Code se ponga delante)
            ctx = self.win.get_display().get_app_launch_context()
            ctx.set_timestamp(Gtk.get_current_event_time())
            app.launch([Gio.File.new_for_path(folder)], ctx)
        except GLib.Error as exc:
            message(self.win, "No se ha podido abrir Visual Studio Code", exc.message, Gtk.MessageType.ERROR)

    def open_uri(self, uri):
        try:
            Gtk.show_uri_on_window(self.win, uri, Gdk.CURRENT_TIME)
        except GLib.Error as exc:
            message(self.win, "No se ha podido abrir %s" % uri, exc.message,
                    Gtk.MessageType.ERROR)

    def on_terminal(self, *_):
        for cmd in (["gnome-terminal", "--geometry=100x32", "--", SCRIPT],
                    ["x-terminal-emulator", "-e", SCRIPT]):
            try:
                subprocess.Popen(cmd, start_new_session=True)
                return
            except OSError:
                continue
        message(self.win, "No se ha encontrado ninguna terminal",
                "Abre una terminal y escribe: lvm-instalador")

    # datos
    def reload(self, branches=False):
        run_quick(["gui-datos"], self.on_data)
        run_quick(["gui-hosts"], self.on_hosts_data)
        run_quick(["gui-servicios"], self.on_services_data)
        run_quick(["gui-proyectos"], self.on_projects_data)
        if branches:
            self.branches = None
            self.branches_error = None
            self.loading(self.inst_box, "Consultando las versiones de PHP en php.net…")
            run_quick(["gui-ramas"], self.on_branches)
        run_quick(["gui-fechas"], self.on_php_dates)
        run_quick(["gui-docker"], self.on_docker_data)

    def on_php_dates(self, rc, out):
        """Fecha de publicación del PHP de cada versión instalada (de php.net: llega después)."""
        dates = {f[1]: (f[2], f[3]) for f in parse_lines(out) if f[0] == "F" and len(f) >= 4}
        if dates and dates != self.php_dates:
            self.php_dates = dates
            if self.data:
                self.build_versions()
        return False

    def on_refresh(self, *_):
        self.reload(branches=True)

    def on_tick(self):
        if not self.busy and self.win.is_active():
            # (las cuatro en una sola orden: el script se lee una vez y no cuatro)
            run_quick(["gui-vuelta"], self.on_round)
            # (Docker solo mientras se ve su pestaña: pregunta a su servicio)
            if self.stack.get_visible_child_name() == "docker":
                run_quick(["gui-docker"], self.on_docker_data)
        return True

    def on_round(self, rc, out):
        """gui-vuelta: cada parte («@@<orden>|<código>» y sus líneas) a lo de siempre."""
        handlers = {"gui-datos": self.on_data, "gui-hosts": self.on_hosts_data,
                    "gui-servicios": self.on_services_data, "gui-proyectos": self.on_projects_data}
        parts, name, code = {}, None, 0
        for line in out.splitlines():
            m = re.fullmatch(r"@@(gui-[a-z]+)\|(\d+)", line)
            if m and m.group(1) in handlers:
                name, code = m.group(1), int(m.group(2))
                parts[name] = [code, []]
            elif name:
                parts[name][1].append(line)
        # (sin ninguna parte, algo ha ido mal antes de empezar: la siguiente vuelta)
        for name, fn in handlers.items():
            if name in parts:
                fn(parts[name][0], "\n".join(parts[name][1]) + "\n")
        return False

    def on_data(self, rc, out):
        d = {"installs": [], "dbs": {}, "dbdate": {}, "active": "", "running": False,
             "unregistered": False, "native": True, "launcher": True,
             "name": "Nexum Dev Stack", "version": "", "signature": "",
             "vhosts": "/opt/lampp/etc/extra/httpd-vhosts.conf", "hosts": "/etc/hosts",
             "stray": "", "exposed": "", "unsecured": [], "certs": [], "cas": [], "untrusted": [], "stale": [],
             "dbsys": None, "php2shell": {},
             "mail": {"installed": False, "on": True, "wp": "mailpit", "running": False, "version": "",
                      "url": "http://127.0.0.1:8025/", "offer": ""}}
        for f in parse_lines(out):
            if f[0] == "M" and len(f) >= 4:
                d["name"], d["version"], d["signature"] = f[1], f[2], f[3]
            elif f[0] == "A" and len(f) >= 6:
                d["active"], d["running"] = f[1], f[2] == "1"
                d["unregistered"], d["native"], d["launcher"] = \
                    f[3] == "1", f[4] == "1", f[5] == "1"
            elif f[0] == "V" and len(f) >= 11:
                d["installs"].append({
                    "folder": f[1], "php": f[2], "apache": f[3], "mariadb": f[4], "ftp": f[5],
                    "perl": f[6], "pma": f[7], "kind": f[8], "owner": f[9],
                    "blocker": "|".join(f[10:]).strip()})
            elif f[0] == "D" and len(f) >= 3:
                d["dbs"].setdefault(f[1], []).append(f[2])
                if len(f) >= 5 and f[3].isdigit():
                    d["dbdate"][(f[1], f[2])] = (int(f[3]), f[4])
            elif f[0] == "H" and len(f) >= 3:
                d["vhosts"], d["hosts"] = f[1], f[2]
            elif f[0] == "Z" and len(f) >= 2:
                d["stray"] = "|".join(f[1:])
            elif f[0] == "N" and len(f) >= 2:
                d["exposed"] = "|".join(f[1:])
            elif f[0] == "U" and len(f) >= 2:
                d["unsecured"] = f[1].split()
            elif f[0] == "Y" and len(f) >= 3:
                d["dbsys"] = (f[1], int(f[2]) if f[2].isdigit() else 0)
            elif f[0] == "C" and len(f) >= 3:
                d["certs"].append((f[1], f[2]))
            elif f[0] == "W" and len(f) >= 2:
                d["cas"].append("|".join(f[1:]))
            elif f[0] == "G" and len(f) >= 2:
                d["untrusted"].append(f[1])
            elif f[0] == "Q" and len(f) >= 2:
                d["stale"].append(f[1])
            elif f[0] == "E" and len(f) >= 8:
                # Correo de pruebas: Mailpit instalado, encendido, modo de WordPress, en marcha...
                d["mail"] = {"installed": f[1] == "1", "on": f[2] == "1", "wp": f[3], "running": f[4] == "1",
                             "version": f[5], "url": f[6] if f[6].startswith("http://127.0.0.1:") else
                             "http://127.0.0.1:8025/", "offer": f[7]}
            elif f[0] == "R" and len(f) >= 3:
                # PHP2Shell en cada version: ok, parche (7.4.33... con el arreglo) o vulnerable
                d["php2shell"][f[1]] = (f[2], "|".join(f[3:]))
        if rc != 0 and not d["installs"]:
            message(self.win, "No se han podido leer las versiones instaladas", out[-600:],
                    Gtk.MessageType.ERROR)
        if d == self.data:
            return False
        self.data = d
        # (solo la versión: la firma está en Acerca de, en el menú)
        # (la versión va arriba, detrás de «Entornos LAMPP y Docker»; abajo solo el aviso de la simulación)
        self.foot.set_label("SIMULACIÓN: no se cambia nada" if SIMULATE else "")
        if getattr(self, "brand_sub", None) is not None:
            self.brand_sub.set_label("Entornos LAMPP y Docker  ·  v%s" % d["version"] if d["version"]
                                     else "Entornos LAMPP y Docker")
        self.build_versions()
        self.build_databases()
        self.build_services()
        self.build_tools()
        if self.branches is not None:
            self.build_install()
        return False

    def on_branches(self, rc, out):
        rows = parse_lines(out)
        err = [f for f in rows if f[0] == "ERROR"]
        self.branches = [f for f in rows if f[0] in ("B", "X")]
        self.branches_error = err[0][1] if err or rc != 0 else None
        if self.branches_error and not err:
            self.branches_error = out.strip()[-400:] or "Error al consultar las versiones"
        self.build_install()
        return False

    def installs(self):
        return self.data["installs"] if self.data else []

    # -------------------------------------------------------------- servicios
    def on_services_data(self, _rc, out):
        rows = [{"name": f[1], "running": f[2] == "1", "ports": f[3], "open": f[4] == "1",
                 "auto": f[5] == "1", "user": f[6] if len(f) > 6 else ""}
                for f in parse_lines(out) if f[0] == "S" and len(f) >= 6]
        if rows != self.services:
            self.services = rows
            self.build_services()
        return False

    def build_services(self):
        """Apache, MariaDB y el FTP de la versión montada, como el panel de XAMPP: si están en
        marcha, si se puede entrar desde la red y botones para arrancarlos, pararlos o
        reiniciarlos. El FTP no arranca con la versión: se arranca aquí cuando haga falta."""
        clear(self.services_box)
        d = self.data
        if not d or self.services is None:
            self.loading(self.services_box)
            return
        if not d["active"]:
            box, lb = group("Servicios")
            row = ActionRow("Ninguna versión activa",
                            "Activa una versión en la pestaña Versiones para ver sus servicios.")
            row.add_prefix(label("●", "punto-gris"))
            lb.add(row)
            self.services_box.pack_start(box, False, False, 0)
            self.services_box.show_all()
            return
        # Cabecera: versión, cuántos están en marcha y si solo se entra desde este equipo
        running = sum(1 for sv in self.services if sv["running"])
        exposed = any(sv["open"] for sv in self.services)
        head = Gtk.Box(spacing=12, margin_bottom=4)
        texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, valign=Gtk.Align.CENTER)
        texts.pack_start(label("Servicios de lampp-%s" % d["active"], "titulo-grande"),
                         False, False, 0)
        texts.pack_start(label("%d de %d en marcha" % (running, len(self.services)),
                               "dim-label"), False, False, 0)
        head.pack_start(texts, True, True, 0)
        if exposed:
            badge = label("Abierto a la red", "pastilla", "peligro", valign=Gtk.Align.CENTER)
        else:
            badge = label("Solo desde este equipo", "pastilla", "segura", valign=Gtk.Align.CENTER,
                          tooltip_text="Solo accesibles desde este equipo")
        head.pack_end(badge, False, False, 0)
        # (en la ventana nueva, arrancar o parar la version entera: lo que hacia el boton Encendidos)
        if hasattr(self, "nv_power"):
            on = d["running"]
            b = Gtk.Button(label="Parar y desactivar" if on else "Arrancar lampp-%s" % d["active"],
                           valign=Gtk.Align.CENTER, sensitive=not self.busy)
            if not on:
                css(b, "verde")
            b.connect("clicked", lambda *_: (self.services_pop.popdown(), self.nv_power()))
            head.pack_end(b, False, False, 0)
        self.services_box.pack_start(head, False, False, 0)

        info = {"apache": ("Apache", "Servidor web: las webs de /opt/htdocs y phpMyAdmin (con PHP)",
                           ("logo", "apache")),
                "mariadb": ("MariaDB", "Servidor de BBDD", ("logo", "mariadb")),
                "ftp": ("FTP (ProFTPD)", "Acceso por FTP a /opt/htdocs. No arranca con la versión: "
                        "arráncalo cuando lo necesites y páralo después.",
                        ("icono", "folder-remote-symbolic", ""))}
        cards = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        for sv in self.services:
            title, help_text, spec = info.get(sv["name"], (sv["name"], "",
                                                           ("icono", "system-run-symbolic", "")))
            card = css(Gtk.Box(spacing=16), "servicio")
            card.pack_start(section_icon(spec, 26, "icono-servicio"), False, False, 0)
            mid = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4,
                          valign=Gtk.Align.CENTER)
            top = Gtk.Box(spacing=10)
            top.pack_start(label(title, "servicio-nombre"), False, False, 0)
            if sv["running"]:
                top.pack_start(label("En marcha", "pastilla", "activa", valign=Gtk.Align.CENTER),
                               False, False, 0)
            else:
                top.pack_start(label("Parado", "pastilla", "parada", valign=Gtk.Align.CENTER),
                               False, False, 0)
            if sv["open"]:
                top.pack_start(label("Abierto a la red", "pastilla", "peligro",
                                     valign=Gtk.Align.CENTER), False, False, 0)
            mid.pack_start(top, False, False, 0)
            mid.pack_start(label(help_text, "dim-label", "subtitulo", wrap=True,
                                 max_width_chars=44), False, False, 0)
            chips = Gtk.Box(spacing=6, margin_top=2)
            for port in [p.strip() for p in sv["ports"].split(",") if p.strip()]:
                chips.pack_start(label("Puerto %s" % port, "chip"), False, False, 0)
            if sv["name"] == "ftp" and sv["user"]:
                chips.pack_start(label("usuario %s" % sv["user"], "chip"), False, False, 0)
            if sv["name"] == "ftp" and sv["auto"]:
                chips.pack_start(label("arranca con la versión", "chip"), False, False, 0)
            mid.pack_start(chips, False, False, 0)
            card.pack_start(mid, True, True, 0)
            actions = Gtk.Box(spacing=8, valign=Gtk.Align.CENTER)
            buttons = [("view-refresh-symbolic", "Reiniciar", "reiniciar", None),
                       ("media-playback-stop-symbolic", "Parar", "parar", None)] \
                if sv["running"] else \
                [("media-playback-start-symbolic", "Arrancar", "arrancar", "verde")]
            for ic, text, cmd, cls in buttons:
                b = Gtk.Button()
                inner = Gtk.Box(spacing=6)
                inner.pack_start(icon(ic), False, False, 0)
                inner.pack_start(Gtk.Label(label=text), False, False, 0)
                b.add(inner)
                if cls:
                    css(b, cls)
                b.connect("clicked", self.on_service, sv["name"], cmd, title)
                actions.pack_start(b, False, False, 0)
            card.pack_end(actions, False, False, 0)
            cards.pack_start(card, False, False, 0)
        self.services_box.pack_start(cards, False, False, 0)

        if any(sv["open"] for sv in self.services):
            box, lb = group("Se puede entrar desde otros equipos de la red")
            row = ActionRow("Abierto a la red", d["exposed"] or "Algún servicio escucha en toda la red")
            b = css(Gtk.Button(label="Cerrar a la red"), "verde")
            b.connect("clicked", self.on_secure)
            row.add_suffix(b)
            lb.add(row)
            self.services_box.pack_start(box, False, False, 0)
        self.services_box.show_all()

    def on_service(self, _btn, name, cmd, title):
        verbs = {"arrancar": ("Arrancando", "arrancado"), "parar": ("Parando", "parado"),
                 "reiniciar": ("Reiniciando", "reiniciado")}
        doing, done = verbs[cmd]
        self.run_task("%s %s" % (doing, title), ["servicio", name, cmd],
                      done_text="%s %s" % (title, done), auto_close=True)

    def on_update_pma(self, folder):
        self.run_task("Actualizando phpMyAdmin", ["actualizar-phpmyadmin", folder], progress=True,
                      done_text="phpMyAdmin actualizado", auto_close=True)

    def on_secure_all(self, *_):
        self.run_task("Protegiendo las versiones", ["asegurar", "--todas"],
                      done_text="Todas las versiones son solo para este equipo", auto_close=True)

    def on_secure(self, *_):
        self.run_task("Cerrando a la red", ["asegurar"],
                      done_text="Solo se puede entrar desde este equipo", auto_close=True)

    # -------------------------------------------------------------- hosts
    def on_hosts_data(self, _rc, out):
        rows = [{"name": f[1], "alias": f[2], "folder": f[3], "fake": f[4] == "1",
                 "https": f[5] == "1", "crt": f[6] == "1", "ps": f[7] == "1",
                 "custom": len(f) >= 9 and f[8] == "1", "media": f[9] if len(f) >= 10 else ""}
                for f in parse_lines(out) if f[0] == "F" and len(f) >= 8]
        # El vhost de los proyectos (web.local) que no lleva a 127.0.0.1: (nombre, dirección de ahora)
        link_fix = [(f[1], f[2]) for f in parse_lines(out) if f[0] == "L" and len(f) >= 3]
        if rows != self.hosts or link_fix != getattr(self, "hosts_link_fix", None):
            self.hosts = rows
            self.hosts_link_fix = link_fix
            self.build_hosts()
        return False

    def build_hosts(self):
        """Dominios de los vhosts y si están falseados en /etc/hosts (llevan a este equipo). Al
        cargar una tienda PrestaShop se falsea su dominio y el resto vuelve a la web real."""
        clear(self.hosts_box)
        if self.hosts is None:
            self.loading(self.hosts_box)
            return
        # Un .local siempre esta en /etc/hosts (sin su linea se preguntaria a la red) y no hay ninguna
        # web real a la que devolverlo: no es un dominio falseado, va con los demas (sin apagarse)
        fake = [h for h in self.hosts if h["fake"] and not h["name"].lower().endswith(".local")]
        rest = [h for h in self.hosts if h not in fake]

        # Primero, si el vhost de los proyectos no lleva a este equipo: el navegador no conecta
        for name, now in getattr(self, "hosts_link_fix", []):
            box, lb = group("%s no lleva a este equipo" % name,
                            "Apache solo escucha en 127.0.0.1 y en /etc/hosts %s. El navegador da "
                            "«No se puede acceder a este sitio web» (ERR_CONNECTION_REFUSED). "
                            "Arreglarlo hace que %s lleve a 127.0.0.1 (una sola vez; la copia del "
                            "/etc/hosts anterior queda en ~/lvm-copias). Pide la contraseña de sudo."
                            % (("apunta a %s" % now) if now else "no está", name))
            row = ActionRow("%s → %s" % (name, now or "sin línea en /etc/hosts"),
                            "Tiene que ir a 127.0.0.1, donde escucha Apache")
            b = css(Gtk.Button(label="Arreglarlo"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Arreglando /etc/hosts", ["hosts-enlace"],
                done_text="web.local ya lleva a este equipo", auto_close=True))
            row.add_suffix(b)
            lb.add(row)
            self.hosts_box.pack_start(box, False, False, 0)

        box, lb = group("Host falseado",
                        "Al cargar una tienda PrestaShop se crea lo que le falte (su vhost y su "
                        "certificado) y su dominio se falsea en /etc/hosts: el navegador la abre "
                        "en este equipo. Al cargar otro proyecto deja de estar falseado y vuelve "
                        "a llevar a la web real.")
        if not fake:
            row = ActionRow("Ningún dominio falseado",
                            "Los dominios de los vhosts llevan a sus webs reales")
            # (en un tercio de la pestaña no cabe en una línea)
            row.subtitle.set_line_wrap(True)
            row.subtitle.set_ellipsize(0)
            lb.add(row)
        for h in fake:
            lb.add(self.host_row(h))
        # En la misma fila: el host falseado ocupa 1/3 y el proyecto nuevo, 2/3 (tres columnas iguales)
        grid = Gtk.Grid(column_spacing=18, column_homogeneous=True)
        box.set_valign(Gtk.Align.START)
        grid.attach(box, 0, 0, 1, 1)
        new_domain = self.build_new_domain()
        new_domain.set_valign(Gtk.Align.START)
        grid.attach(new_domain, 1, 0, 2, 1)
        self.hosts_box.pack_start(grid, False, False, 0)

        box, lb = group("Dominios de los vhosts",
                        "Encendido, el dominio lleva a este equipo (127.0.0.1); apagado, a la "
                        "web real. Se pide la contraseña de sudo para cambiar /etc/hosts.")
        if not rest:
            lb.add(ActionRow("No hay más dominios",
                             "Los vhosts están en /opt/config/httpd-vhosts.conf"))
        for h in rest:
            lb.add(self.host_row(h))
        self.hosts_box.pack_start(box, False, False, 0)
        self.hosts_box.show_all()

    def build_new_domain(self):
        """Proyecto nuevo con el dominio de producción falseado (para construirlo en local y
        subirlo después a producción con los nombres reales). La carpeta se elige entre las de
        /opt/htdocs (por ejemplo, la de un git clone) o se crea; la base, entre las de la
        versión activa o se crea, como en Bases de datos."""
        f = self.newdom
        active = self.data["active"] if self.data else ""
        box, lb = group("Nuevo proyecto con dominio falseado",
                        "Para construir en local un proyecto nuevo con su dominio y su BBDD "
                        "de producción, sin tocar nada en producción. Elige su carpeta de "
                        "/opt/htdocs (por ejemplo, la de un git clone) o crea una, y su BBDD. "
                        "Se crea su vhost http y https con certificado, lo que falte de la "
                        "carpeta y la BBDD, y se falsea el dominio. Al terminar se exporta a "
                        "producción tal cual.")

        row = ActionRow("Dominio", "El de producción")
        e = Gtk.Entry(text=f["domain"], placeholder_text="mitienda.com", width_chars=COMBO_CHARS,
                      valign=Gtk.Align.CENTER)
        e.connect("changed", lambda w: (f.__setitem__("domain", clean_domain(w.get_text())),
                                        update())[0])
        row.add_suffix(e)
        lb.add(row)

        # Carpeta: las de /opt/htdocs (las que ya tienen dominio lo indican) o una nueva
        with_domain = {h["folder"]: h["name"] for h in (self.hosts or []) if h["folder"]}
        folders = project_folders()
        row = ActionRow("Carpeta", "Ya tiene el dominio %s" % with_domain[f["folder"]]
                        if f["folder"] in with_domain else
                        "En /opt/htdocs (git clone) o nueva")
        # Un dominio largo no ensancha la pestaña: se corta con «…» y se ve entero al pasar el raton
        row.subtitle.set_max_width_chars(26)
        row.subtitle.set_tooltip_text(row.subtitle.get_label())
        fcombo = narrow(Gtk.ComboBoxText(valign=Gtk.Align.CENTER))
        for name in folders:
            fcombo.append(name, name)
        if f["folder"] and f["folder"] not in folders:
            fcombo.append(f["folder"], "%s (nueva)" % f["folder"])
        if f["folder"]:
            fcombo.set_active_id(f["folder"])
        if fcombo.get_active_id() is None:
            f["folder"] = ""
            fcombo.append("@ninguna", "Elige una carpeta")
            fcombo.set_active_id("@ninguna")
        fcombo.connect("changed", lambda w: self.on_new_domain_folder(w.get_active_id()))
        row.add_suffix(fcombo)
        b = Gtk.Button(tooltip_text="Crear una carpeta nueva", valign=Gtk.Align.CENTER)
        b.add(icon("list-add-symbolic"))
        b.connect("clicked", lambda *_: self.ask_new_domain_name("folder", folders))
        row.add_suffix(b)
        lb.add(row)

        # Base de datos: las de la versión activa, una nueva o ninguna
        dbs = self.data["dbs"].get(active, []) if active else []
        row = ActionRow("BBDD", "En lampp-%s" % active if active
                        else "No hay ninguna versión activa")
        dcombo = narrow(Gtk.ComboBoxText(valign=Gtk.Align.CENTER, sensitive=bool(active)))
        dcombo.append("@sin", "Sin BBDD")
        for db in dbs:
            dcombo.append(db, db)
        if f["db"] and f["db"] not in dbs:
            dcombo.append(f["db"], "%s (nueva)" % f["db"])
        dcombo.set_active_id(f["db"] or "@sin")
        if dcombo.get_active_id() is None:
            f["db"] = ""
            dcombo.set_active_id("@sin")
        dcombo.connect("changed", lambda w: f.__setitem__(
            "db", "" if w.get_active_id() in (None, "@sin") else w.get_active_id()))
        row.add_suffix(dcombo)
        b = Gtk.Button(tooltip_text="Crear una BBDD nueva", valign=Gtk.Align.CENTER,
                       sensitive=bool(active))
        b.add(icon("list-add-symbolic"))
        b.connect("clicked", lambda *_: self.ask_new_domain_name("db", dbs))
        row.add_suffix(b)
        lb.add(row)

        # (debajo, lo que falta para poder crearlo: sin eso el boton no se puede pulsar)
        row = ActionRow("", " ")
        btn = css(Gtk.Button(label="Crear y falsear"), "suggested-action")
        btn.connect("clicked", lambda *_: self.on_new_domain())
        row.add_suffix(btn)
        lb.add(row)

        def update():
            why = ("Escribe el dominio de producción" if not f["domain"] else
                   "«%s» no es un dominio (por ejemplo: mitienda.com)" % f["domain"]
                   if not DOMAIN_RX.match(f["domain"]) else
                   "Elige su carpeta" if not f["folder"] else
                   "Espera a que acabe la tarea en marcha" if self.busy else
                   "https://%s → /opt/htdocs/%s" % (f["domain"].lower(), f["folder"]))
            row.subtitle.set_label(why)
            btn.set_sensitive(bool(DOMAIN_RX.match(f["domain"])) and bool(f["folder"])
                              and not self.busy)
        self.newdom_update = update
        update()
        return box

    def on_new_domain_folder(self, folder):
        f = self.newdom
        f["folder"] = "" if folder in (None, "@ninguna") else folder
        # Si el proyecto ya trae su configuración (wp-config.php, PrestaShop, .env), se propone
        # su base de datos
        db = project_db(f["folder"]) if f["folder"] else ""
        if db and not f["db"]:
            f["db"] = db
            GLib.idle_add(lambda: (self.build_hosts(), False)[1])
            self.toast("BBDD de su configuración: %s" % db)
        else:
            GLib.idle_add(lambda: (self.build_hosts(), False)[1])

    def ask_new_domain_name(self, key, existing):
        """Nombre de una carpeta o una base nueva (se crea al pulsar «Crear y falsear»)."""
        is_db = key == "db"
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.QUESTION,
                                buttons=Gtk.ButtonsType.NONE,
                                text="BBDD nueva" if is_db else "Carpeta nueva")
        dlg.format_secondary_text(
            "Pon el nombre de la BBDD de producción. Se crea vacía en lampp-%s al "
            "pulsar «Crear y falsear»." % self.data["active"] if is_db else
            "Se crea en /opt/htdocs al pulsar «Crear y falsear». Si vas a clonar el proyecto "
            "con git, clónalo antes y elige su carpeta en la lista.")
        entry = Gtk.Entry(max_length=64, activates_default=True,
                          placeholder_text="nombre_de_la_base" if is_db else
                          (self.newdom["domain"] or "carpeta-del-proyecto"))
        hint = label("Letras sin acentos, números, _ y -" if is_db else
                     "Letras sin acentos, números, punto, _ y -", "dim-label")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.pack_start(entry, False, False, 0)
        box.pack_start(hint, False, False, 0)
        dlg.get_message_area().pack_start(box, False, False, 0)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Elegir", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        rx = r"^[A-Za-z0-9_-]{1,64}$" if is_db else r"^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$"

        def value():
            return entry.get_text().strip() or ("" if is_db else self.newdom["domain"])

        def update(*_):
            name = value()
            taken = name in existing
            ok.set_sensitive(bool(re.match(rx, name)) and not taken)
            hint.set_label("Ya existe: elígela en la lista." if taken else
                           "Letras sin acentos, números, _ y -" if is_db else
                           "Letras sin acentos, números, punto, _ y -")
        entry.connect("changed", update)
        update()
        dlg.show_all()
        resp = run_dialog(dlg)
        name = value()
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        self.newdom[key] = name
        GLib.idle_add(lambda: (self.build_hosts(), False)[1])

    def on_new_domain(self):
        f = self.newdom
        domain = f["domain"].lower()
        folder = f["folder"]
        db = f["db"]
        if not folder:
            return
        active = self.data["active"] if self.data else ""
        exists = os.path.isdir(os.path.join(HTDOCS, folder))
        steps = ["Carpeta /opt/htdocs/%s%s." % (folder, "" if exists else " (se crea)"),
                 "Vhost http y https de %s con su certificado autofirmado." % domain]
        if db:
            have = db in (self.data["dbs"].get(active, []) if active else [])
            steps.append("BBDD %s en lampp-%s%s." % (
                db, active, " (ya existe: se deja como está)" if have else " (se crea vacía)"))
        steps.append("%s se falsea en /etc/hosts; los demás dominios dejan de estarlo." % domain)
        if not confirm(self.win, "¿Crear %s?" % domain, "Se pide la contraseña de sudo.", "Crear y falsear",
                       steps=steps):
            return
        args = ["nuevo-dominio", domain, folder] + ([db] if db else [])

        def done(ok_, *_):
            if ok_:
                self.newdom = {"domain": "", "folder": "", "db": ""}
                self.hosts = None
                self.toast("%s falseado: https://%s → /opt/htdocs/%s" % (domain, domain, folder))
        self.run_task("Creando %s" % domain, args, done_text="%s listo" % domain,
                      env=self.db_env() if active else None, on_done=done)

    def host_row(self, h):
        info = [h["folder"] or "sin carpeta en /opt/htdocs"]
        if not h["https"]:
            info.append("sin https")
        elif not h["crt"]:
            info.append("falta el certificado")
        if h.get("media"):
            info.append("imágenes que faltan de %s" % h["media"])
        row = ActionRow(h["name"], "  ·  ".join(info))
        # (en la tarjeta estrecha se cortan con «…»: enteros al pasar el ratón)
        row.title.set_tooltip_text(h["name"])
        row.subtitle.set_tooltip_text("  ·  ".join(info))
        # Logotipo del proyecto: PrestaShop, WordPress (por el nombre de su carpeta) o un globo
        if h["ps"]:
            row.add_prefix(section_icon(("logo", "prestashop"), 16))
        elif "wordpress" in (h["folder"] or "").lower():
            row.add_prefix(section_icon(("logo", "wordpress"), 16))
        else:
            row.add_prefix(section_icon(("icono", "web-browser-symbolic", ""), 16))
        if h["ps"]:
            row.add_title_tag(label("PrestaShop", "dim-label"))
        elif h.get("custom"):
            row.add_title_tag(label("Proyecto nuevo", "dim-label"))
        if h["fake"]:
            b = Gtk.Button(label="Abrir", valign=Gtk.Align.CENTER,
                           tooltip_text="https://%s" % h["name"])
            b.connect("clicked", lambda *_: self.open_uri(
                "%s://%s" % ("https" if h["https"] else "http", h["name"])))
            row.add_suffix(b)
        if h["name"].lower().endswith(".local"):
            b = Gtk.Button(valign=Gtk.Align.CENTER, sensitive=not self.busy,
                           tooltip_text="Imágenes de producción" + (": %s" % h["media"] if h.get("media") else ""))
            b.add(icon("image-x-generic-symbolic"))
            b.connect("clicked", lambda *_: self.on_media_proxy(h))
            row.add_suffix(b)
        sw = Gtk.Switch(active=h["fake"], valign=Gtk.Align.CENTER)
        sw.set_tooltip_text(host_switch_tip(h))
        sw.connect("state-set", self.on_host_switch, h)
        row.add_suffix(sw)
        return row

    def project_hosts(self, name):
        """Dominios falseables de un proyecto: los de los vhosts de su carpeta. Un .local no es un
        dominio falseado (no hay ninguna web real a la que devolverlo)."""
        return [h for h in self.hosts or []
                if h["folder"] == name and not h["name"].lower().endswith(".local")]

    def on_view_hosts(self, *_):
        """El fichero de hosts, solo para verlo (para cambiarlo: Editar, en Configuración), con los
        dominios que se pueden falsear delante: un dominio con vhost no sale en él hasta falsearlo."""
        path = self.data["hosts"] if self.data else "/etc/hosts"
        vhosts = self.data["vhosts"] if self.data else ""
        try:
            with open(path, errors="replace") as f:
                text = f.read()
        except OSError as exc:
            message(self.win, "No se ha podido leer %s" % path, str(exc), Gtk.MessageType.ERROR)
            return
        self.show_text(path, "Dominios que se pueden falsear y contenido del fichero (solo lectura)",
                       hosts_view_text(self.hosts or [], path, vhosts, text), self.on_view_hosts,
                       lines=1000000, to_end=False)

    def on_media_proxy(self, h):
        """media-produccion: el dominio de producción al que se piden las imágenes que faltan en un
        .local (uploads e img no van en git). Se propone el dominio real del vhost de su carpeta."""
        name = h["name"]
        guess = h.get("media") or next((o["name"] for o in (self.hosts or []) if h["folder"]
                                        and o["folder"] == h["folder"] and not o["name"].endswith(".local")), "")
        dlg = Gtk.Dialog(title="Imágenes de producción", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(520, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        box.pack_start(label("Imágenes de producción en %s" % name, "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(label("Las imágenes, vídeos y PDF de wp-content/uploads o img que no estén en la carpeta "
                             "se piden a la web real (redirección 302): no hace falta descargarlas. Solo en "
                             "los .local; lo que ya está en local se sigue sirviendo desde aquí.",
                             "nv-tenue", wrap=True, max_width_chars=60), False, False, 0)
        entry = Gtk.Entry(text=guess, placeholder_text="ejemplo.com", max_length=80, activates_default=True)
        box.pack_start(entry, False, False, 0)
        dlg.get_content_area().add(box)
        if h.get("media"):
            css(dlg.add_button("Quitar", Gtk.ResponseType.REJECT), "destructive-action")
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Guardar", Gtk.ResponseType.OK), "nv-azul")
        dlg.set_default_response(Gtk.ResponseType.OK)

        def update(*_):
            d = re.sub(r"^https?://", "", entry.get_text().strip().lower()).rstrip("/")
            ok.set_sensitive(bool(DOMAIN_RX.match(d)) and not d.endswith(".local") and d != h.get("media"))
        entry.connect("changed", update)
        dlg.show_all()
        update()
        resp = run_dialog(dlg)
        prod = re.sub(r"^https?://", "", entry.get_text().strip().lower()).rstrip("/")
        dlg.destroy()
        if resp == Gtk.ResponseType.REJECT:
            self.run_task("Quitando las imágenes de producción de %s" % name, ["media-produccion", name, "quitar"],
                          done_text="%s ya no pide nada a producción" % name, auto_close=True)
        elif resp == Gtk.ResponseType.OK:
            self.run_task("Imágenes de producción en %s" % name, ["media-produccion", name, prod],
                          done_text="%s pide a %s las imágenes que faltan" % (name, prod), auto_close=True)

    def on_host_switch(self, sw, state, h):
        if state == h["fake"]:
            return False
        name = h["name"]
        local = name.lower().endswith(".local")
        if local and not state and not confirm(
                self.win, "¿Apagar %s?" % name,
                "Su línea de /etc/hosts queda comentada. Mientras esté apagado, al abrir %s "
                "cualquiera de tu misma wifi podría contestar con una web suya. Se puede volver a "
                "encender cuando quieras." % name,
                "Apagar %s" % name):
            sw.set_active(True)
            return True
        if local:
            title = "%s %s" % ("Encendiendo" if state else "Apagando", name)
            done = "%s %s" % (name, "lleva a este equipo" if state else "apagado")
        elif state:
            title, done = "Falseando %s" % name, "%s lleva a este equipo" % name
        else:
            title, done = "Dejando de falsear %s" % name, "%s lleva a la web real" % name

        def finished(ok_, *_):
            if not ok_:
                self.hosts = None
            self.toast(done if ok_ else "No se ha cambiado /etc/hosts")
        self.run_task(title, ["hosts-falsear", name, "si" if state else "no"],
                      done_text=done, auto_close=True, on_done=finished)
        # El interruptor cambia cuando se vuelva a leer /etc/hosts
        return True

    # ------------------------------------------------------- herramientas
    def build_tools(self):
        """Lo que se usa de vez en cuando: ficheros de configuración, carpetas, actualizar el
        programa e información."""
        clear(self.tools_box)
        d = self.data

        def add_row(lb, title, sub, btn_text, cb):
            row = ActionRow(title, sub)
            b = Gtk.Button(label=btn_text, valign=Gtk.Align.CENTER)
            b.connect("clicked", lambda *_: cb())
            row.add_suffix(b)
            lb.add(row)

        box, lb = tile_group("Configuración",
                        "Los vhosts y los hosts del sistema son del administrador: se edita una "
                        "copia y se aplica con Aplicar (pide la contraseña).")
        add_row(lb, "Virtual hosts", d["vhosts"], "Editar…", self.on_vhosts)
        add_row(lb, "Hosts del sistema", d["hosts"], "Editar…", self.on_hosts)
        self.tools_box.pack_start(box, False, False, 0)

        if d["unregistered"]:
            box, lb = tile_group("XAMPP sin registrar",
                            "/opt/lampp es una instalación de XAMPP completa y no un enlace.")
            add_row(lb, "XAMPP en /opt/lampp", "Regístralo con un nombre para gestionarlo junto a "
                    "las demás versiones", "Registrar…", self.on_register)
            self.tools_box.pack_start(box, False, False, 0)

        box, lb = tile_group("Carpetas")
        add_row(lb, "Proyectos", "/opt/htdocs, compartida por todas las versiones", "Abrir",
                lambda: self.open_uri(GLib.filename_to_uri("/opt/htdocs")))
        copies = os.path.expanduser("~/lvm-copias")
        add_row(lb, "Copias de seguridad", "~/lvm-copias: BBDD borradas o desinstaladas y "
                "/etc/hosts anteriores", "Abrir",
                lambda: (os.makedirs(copies, exist_ok=True),
                         self.open_uri(GLib.filename_to_uri(copies))))
        add_row(lb, "Registros de instalaciones", "~/.lvm-instalador: logs de las instalaciones "
                "y de la ventana", "Abrir", lambda: self.open_uri(GLib.filename_to_uri(LOG_DIR)))
        self.tools_box.pack_start(box, False, False, 0)

        self.build_error_logs(add_row)

        box, lb = tile_group("Programa")
        add_row(lb, "Buscar una versión nueva", "Busca en GitHub (y en Descargas) una versión más "
                "nueva, firmada, y la instala", "Buscar", lambda: self.check_package(manual=True))
        add_row(lb, "Icono en el menú de aplicaciones", "Vuelve a crear el acceso «Nexum Dev Stack» "
                "si no aparece o no abre esta ventana", "Crear de nuevo",
                self.on_create_launcher)
        self.nv_tray_row(lb)
        self.tools_box.pack_start(box, False, False, 0)

        box, lb = tile_group("Información")
        add_row(lb, "Comandos de lvm-instalador", "Todos los comandos para la terminal y qué hace "
                "cada uno", "Ver", self.on_commands)
        add_row(lb, "Novedades", "Qué ha cambiado en cada versión", "Ver", self.on_changes)
        add_row(lb, "Acerca de", "%s %s" % (d["name"], d["version"]), "Ver", self.on_about)
        self.tools_box.pack_start(box, False, False, 0)
        self.tools_box.show_all()

    def nv_tray_row(self, lb):
        """Configuración, Programa: el icono junto al reloj (solo en la ventana nueva)."""
        if not hasattr(self, "nv_tray_toggle"):
            return
        has = tray_lib() is not None
        row = ActionRow("Dejar en la bandeja al cerrar",
                        "La X la esconde en un icono junto al reloj (abrir, arrancar o parar, web.local y salir)"
                        if has else
                        "Falta su componente. En una terminal: sudo apt install gir1.2-ayatanaappindicator3-0.1")
        sw = Gtk.Switch(active=has and tray_wanted(), valign=Gtk.Align.CENTER, sensitive=has)
        sw.connect("notify::active", self.nv_tray_toggle)
        row.add_suffix(sw)
        lb.add(row)

    def project_error_log(self, link=None):
        """Registro de errores del vhost de los proyectos (web.local) o del dominio que se diga,
        sacado de su ErrorLog: con PHP-FPM, los errores de PHP de la web cargada (el «error
        crítico» de WordPress) van ahí y no al error_log general de Apache."""
        link = link or (self.projects or {}).get("link") or ""
        if not link:
            return None
        try:
            with open(self.data["vhosts"], errors="replace") as fh:
                text = fh.read(2000000)
        except OSError:
            text = ""
        for m in re.finditer(r"(?is)<VirtualHost\b[^>]*>(.*?)</VirtualHost>", text):
            body = m.group(1)
            names = " ".join(re.findall(r"(?im)^[ \t]*Server(?:Name|Alias)[ \t]+(.+)$", body)).lower().split()
            e = re.search(r"(?im)^[ \t]*ErrorLog[ \t]+\"?([^\"\s]+)\"?", body)
            if link.lower() in names and e and not e.group(1).startswith(("|", "syslog")):
                path = e.group(1)
                return path if path.startswith("/") else os.path.join("/opt/lampp", path)
        # (sin ErrorLog propio, sus errores van al general: no hay otro registro que enseñar)
        path = os.path.join("/opt/lampp/logs", link + "-error_log")
        return path if os.path.isfile(path) else None

    def log_row(self, title, path, note=""):
        """Fila de un registro: dónde está, cuánto ocupa y cuándo se cambió."""
        try:
            st = os.stat(path)
        except OSError:
            return ActionRow(title, "%s: no existe todavía (se crea con el primer error)" % path)
        when = GLib.DateTime.new_from_unix_local(int(st.st_mtime)).format("%d/%m/%Y %H:%M")
        size = GLib.format_size(st.st_size)
        sub = "%s  ·  %s  ·  modificado el %s" % (path, size, when)
        if note:
            sub = note + "\n" + sub
        row = ActionRow(title, sub)
        row.subtitle.set_line_wrap(True)
        row.subtitle.set_ellipsize(0)
        b = Gtk.Button(label="Ver el final", sensitive=st.st_size > 0, valign=Gtk.Align.CENTER)
        b.connect("clicked", lambda *_: self.show_log_tail(path))
        row.add_suffix(b)
        b = Gtk.Button(label="Abrir", valign=Gtk.Align.CENTER)
        # Un fichero de cientos de MB dejaria colgado el editor de textos
        if st.st_size > LOG_OPEN_MAX:
            b.set_sensitive(False)
            b.set_tooltip_text("Ocupa %s: usa «Ver el final»" % size)
        b.connect("clicked", lambda *_: self.open_text(path))
        row.add_suffix(b)
        return row

    def build_error_logs(self, add_row):
        """Los registros de errores de la versión montada: el del vhost del proyecto cargado
        (web.local), donde van los errores de PHP de la web, y el general de Apache."""
        box, lb = tile_group("Registro de errores",
                        "Si la web cargada da un error (el «error crítico» de WordPress), el motivo "
                        "está en el registro de su vhost: ahí van los errores de PHP. Los de Apache "
                        "(que no arranca, un vhost mal escrito…), en el general. Lo más reciente "
                        "está al final.")
        path = self.project_error_log()
        if path:
            p = self.projects
            name = os.path.basename(p["current"].rstrip("/")) if p and p.get("current") else ""
            lb.add(self.log_row("error_log de %s%s" % (p["link"], "  (%s)" % name if name else ""), path))
        lb.add(self.log_row("error_log de Apache (lampp-%s)" % self.data["active"], APACHE_ERROR_LOG))
        self.tools_box.pack_start(box, False, False, 0)

    def show_log_tail(self, path, lines=400):
        """Últimas líneas de un registro (lo más reciente al final), sin leer el fichero entero."""
        try:
            # (sin quedarse esperando si no es un fichero normal: una tubería colgaría la ventana)
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                os.close(fd)
                raise OSError("no es un fichero normal")
            with os.fdopen(fd, "rb") as f:
                f.seek(0, os.SEEK_END)
                size = f.tell()
                f.seek(max(0, size - 256 * 1024))
                text = f.read().decode("utf-8", "replace")
        except OSError as exc:
            message(self.win, "No se ha podido leer %s" % path, str(exc), Gtk.MessageType.ERROR)
            return
        self.show_text(os.path.basename(path), "Últimas %d líneas de %s" % (lines, path),
                       text, lambda: self.show_log_tail(path, lines), lines)

    def show_text(self, title, subtitle, text, reload=None, lines=400, to_end=True):
        """Las últimas líneas de un registro (lo más reciente al final) en un diálogo, con «Copiar
        todo» y, con reload, «Actualizar» (lo vuelve a leer)."""
        # (los de PHP-FPM llegan en una sola línea con \n escritos: se separan para leerlos)
        text = "\n".join(text.splitlines()[-lines:]).replace("\\n", "\n    ") or "(vacío)"
        dlg = Gtk.Dialog(title=title, transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(980, 620)
        hb = dlg.get_header_bar()
        hb.set_subtitle(subtitle)
        copy = Gtk.Button(label="Copiar todo")
        copy.connect("clicked", lambda *_: (
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(text, -1),
            self.toast("Copiado al portapapeles")))
        hb.pack_start(copy)
        if reload is not None:
            reload_btn = Gtk.Button(label="Actualizar")
            reload_btn.connect("clicked", lambda *_: (dlg.destroy(), reload()))
            hb.pack_end(reload_btn)
        tv = css(Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                              wrap_mode=Gtk.WrapMode.WORD_CHAR, left_margin=12, right_margin=12,
                              top_margin=8, bottom_margin=8), "log")
        buf = tv.get_buffer()
        buf.set_text(text)
        sw = Gtk.ScrolledWindow(vexpand=True)
        sw.add(tv)
        dlg.get_content_area().add(sw)
        dlg.show_all()
        # Lo más reciente está al final
        if to_end:
            GLib.idle_add(lambda: (tv.scroll_to_iter(buf.get_end_iter(), 0, False, 0, 1), False)[1])
        run_dialog(dlg)
        dlg.destroy()

    # ---------------------------------------------------------- versiones
    def on_close_stray(self, *_):
        self.run_task("Cerrando los procesos que sobran", ["cerrar-procesos"],
                      done_text="Solo queda en memoria la versión montada", auto_close=True,
                      on_done=lambda ok_, *_: self.toast(
                          "Procesos cerrados" if ok_ else "No se han podido cerrar todos"))

    # ------------------------------------------------- cargar un proyecto (Versiones)
    def on_projects_data(self, rc, out):
        p = {"link": "", "current": "", "create": False, "list": [], "saved": {}, "vlinks": {}}
        for f in parse_lines(out):
            if f[0] == "E" and len(f) >= 3:
                p["link"], p["current"] = f[1], f[2]
                p["create"] = len(f) >= 4 and f[3] == "N"
            elif f[0] == "P" and len(f) >= 4:
                p["list"].append({"name": f[1], "db": f[2], "php": f[3],
                                  "kind": f[4] if len(f) > 4 else ""})
            elif f[0] == "R" and len(f) >= 3:
                p["saved"][f[1]] = "|".join(f[2:])
            elif f[0] == "V" and len(f) >= 4:
                p["vlinks"][(f[1], f[2])] = f[3]
        if rc != 0 and not p["list"]:
            p = None
        if p != self.projects:
            old_link = (self.projects or {}).get("link"), (self.projects or {}).get("current")
            self.projects = p
            self.update_project_search()
            # (el registro de errores de Herramientas es el del vhost del proyecto cargado)
            if self.data and old_link != ((p or {}).get("link"), (p or {}).get("current")):
                self.build_tools()
            # (en BBDD, el punto verde va en la BBDD que usa el proyecto cargado)
            if self.data:
                self.build_databases()
            # (y el menú del icono junto al reloj, su web.local)
            if hasattr(self, "nv_tray_update"):
                self.nv_tray_update()
        return False

    def build_project_box(self):
        # Uno de los bloques más usados: su título fuera, como los demás apartados, y debajo el
        # contenedor hundido, con algo más de separación con lo de debajo (Versión activa)
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, margin_bottom=12)
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin_top=6), "hundido")
        head = Gtk.Box(spacing=6)
        head.pack_start(label("Cargar proyecto", "grupo-titulo"), False, False, 0)
        head.pack_start(info_icon(
            "Busca la carpeta de un proyecto de /opt/htdocs y cárgalo: el vhost "
            "(web.local) apunta a ella y se monta la versión de PHP donde está su BBDD. "
            "Si la BBDD está en varias versiones, se pregunta cuál montar. Con «Montar nuevo "
            "proyecto» se clona uno de GitHub y se le crea su BBDD."), False, False, 0)
        outer.pack_start(head, False, False, 0)
        outer.pack_start(box, False, False, 0)
        # «web.local → proyecto», junto al nombre el botón de desmontarlo y, a la derecha,
        # botones de icono (el texto sale al dejar el ratón encima). De derecha a izquierda: su
        # carpeta en Visual Studio Code, su BBDD en phpMyAdmin, su panel de administración
        # (WordPress o PrestaShop) y la web en el navegador
        # (todo el nombre si cabe; si no, cortado por el final)
        self.proj_now = label("", ellipsize=3, max_width_chars=70)

        def icon_button(image, callback):
            b = css(Gtk.Button(valign=Gtk.Align.CENTER, relief=Gtk.ReliefStyle.NORMAL),
                    "boton-proyecto")
            b.set_image(image)
            b.set_always_show_image(True)
            b.connect("clicked", lambda *_: callback())
            return b
        self.proj_open = icon_button(logo("globo", 20), lambda: self.projects and self.projects["link"]
                                     and self.open_uri("http://%s/" % self.projects["link"]))
        self.proj_pma = icon_button(logo("phpmyadmin", 20), self.open_project_pma)
        self.proj_admin = icon_button(logo("wordpress", 20), self.open_project_admin)
        # Desmontar: el vhost deja de apuntar al proyecto (enseña una página vacía)
        self.proj_unload = icon_button(icon("media-eject-symbolic", 18), self.on_unload_project)
        self.proj_now_row = Gtk.Box(spacing=8)
        self.proj_now_row.pack_start(section_icon(("icono", "folder-open-symbolic", "verde-suave"), 16),
                                     False, False, 4)
        name_box = Gtk.Box(spacing=8)
        name_box.pack_start(self.proj_now, False, True, 0)
        name_box.pack_start(self.proj_unload, False, False, 0)
        self.proj_now_row.pack_start(name_box, True, True, 0)
        # El de abrir su carpeta en Visual Studio Code, el último por la derecha (solo si está
        # instalado), con el icono de VS Code
        code = vscode_app()
        self.proj_code = css(Gtk.Button(valign=Gtk.Align.CENTER, relief=Gtk.ReliefStyle.NORMAL),
                             "boton-proyecto")
        if code is not None and code.get_icon() is not None:
            img = Gtk.Image.new_from_gicon(code.get_icon(), Gtk.IconSize.BUTTON)
            img.set_pixel_size(20)
            self.proj_code.set_image(img)
        else:
            self.proj_code.set_label("VS Code")
        self.proj_code.connect("clicked", lambda *_: self.open_in_vscode())
        self.proj_now_row.pack_end(self.proj_code, False, False, 0)
        self.proj_now_row.pack_end(self.proj_pma, False, False, 0)
        self.proj_now_row.pack_end(self.proj_admin, False, False, 0)
        self.proj_now_row.pack_end(self.proj_open, False, False, 0)
        if code is None:
            self.proj_code.set_no_show_all(True)
        self.proj_now_row.show_all()
        self.proj_now_row.set_no_show_all(True)
        box.pack_start(self.proj_now_row, False, False, 0)
        # Aviso en rojo: la versión montada no tiene el proyecto cargado (su BBDD está en otra)
        self.proj_warn = label("", "aviso-rojo", wrap=True)
        self.proj_warn.set_no_show_all(True)
        box.pack_start(self.proj_warn, False, False, 0)
        # Buscador y, a su derecha, «Montar nuevo proyecto» (despliega el asistente)
        # (algo separado de los botones del proyecto, que van justo encima)
        search_row = Gtk.Box(spacing=10, margin_top=16)
        self.proj_entry = css(Gtk.SearchEntry(placeholder_text="Buscar la carpeta del proyecto…"),
                              "buscador")
        self.proj_entry.connect("search-changed", lambda *_: self.update_project_search())
        self.proj_entry.connect("stop-search", lambda e: e.set_text(""))
        search_row.pack_start(self.proj_entry, True, True, 0)
        self.proj_new_btn = css(Gtk.Button(valign=Gtk.Align.CENTER), "verde")
        nb = Gtk.Box(spacing=6)
        nb.pack_start(icon("list-add-symbolic"), False, False, 0)
        nb.pack_start(Gtk.Label(label="Montar nuevo proyecto"), False, False, 0)
        self.proj_new_btn.add(nb)
        self.proj_new_btn.set_tooltip_text("Clonar un proyecto de GitHub")
        self.proj_new_btn.connect("clicked", lambda *_: self.toggle_new_project(True))
        # Replicar: el proyecto en otra versión de PHP (su BBDD copiada con otro nombre y vinculada
        # allí a la carpeta que se elija)
        self.proj_rep_btn = Gtk.Button(valign=Gtk.Align.CENTER)
        rb = Gtk.Box(spacing=6)
        rb.pack_start(icon("edit-copy-symbolic"), False, False, 0)
        rb.pack_start(Gtk.Label(label="Replicar"), False, False, 0)
        self.proj_rep_btn.add(rb)
        self.proj_rep_btn.set_tooltip_text("Replicar en otra versión de PHP")
        self.proj_rep_btn.connect("clicked", lambda *_: self.on_replicate())
        search_row.pack_start(self.proj_rep_btn, False, False, 0)
        search_row.pack_start(self.proj_new_btn, False, False, 0)
        box.pack_start(search_row, False, False, 0)
        self.new_proj_rev = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.SLIDE_DOWN)
        self.new_proj_rev.add(self.build_new_project())
        # Plegado, oculto del todo: si no, el hueco entre filas del recuadro deja más espacio
        # debajo del buscador que encima de la primera fila
        self.new_proj_rev.set_no_show_all(True)
        self.new_proj_rev.connect("notify::child-revealed", lambda r, _p: r.get_reveal_child()
                                  or r.get_child_revealed() or r.hide())
        box.pack_start(self.new_proj_rev, False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        lb.connect("row-activated", on_row_activated)
        lb.set_no_show_all(True)
        box.pack_start(lb, False, False, 0)
        self.proj_results = lb
        outer.show_all()
        return outer

    # --- Montar nuevo proyecto: asistente de tres pasos (clon, versión de PHP y BBDD) ---

    def build_new_project(self):
        w = {}
        self.np = w
        outer = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14), "asistente")
        w["step"] = label("", "asistente-paso")
        outer.pack_start(w["step"], False, False, 0)
        w["stack"] = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT,
                               vhomogeneous=False, interpolate_size=True)
        outer.pack_start(w["stack"], False, False, 0)

        # 1. Repositorio y carpeta: de los de GitHub (pestaña Repositorios) o la dirección de otro
        p1 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        p1.pack_start(label("¿De qué repositorio de GitHub? (escribe parte de su nombre)"), False, False, 0)
        w["repo"] = Gtk.Entry(placeholder_text="dob-wordpress-…", primary_icon_name="system-search-symbolic")
        w["repo"].connect("changed", lambda *_: self.new_project_search())
        w["repo"].connect("activate", lambda *_: self.new_project_first_hit())
        w["repo"].connect("key-press-event", self.new_project_search_key)
        p1.pack_start(w["repo"], False, False, 0)
        # Los resultados, en la propia ventana: el desplegable de Gtk.EntryCompletion es una ventana
        # emergente aparte, que en Wayland puede no llegar a verse
        w["repo_hits"] = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        w["repo_hits"].connect("row-activated", on_row_activated)
        w["repo_hits"].set_no_show_all(True)
        p1.pack_start(w["repo_hits"], False, False, 0)
        w["repo_note"] = label("", "dim-label", wrap=True)
        p1.pack_start(w["repo_note"], False, False, 0)
        p1.pack_start(label("o la dirección de otro repositorio (GitHub u otro servidor):"), False, False, 0)
        w["url"] = Gtk.Entry(placeholder_text="https://github.com/usuario/repositorio.git")
        p1.pack_start(w["url"], False, False, 0)
        p1.pack_start(label("Carpeta en /opt/htdocs:"), False, False, 0)
        w["folder"] = Gtk.Entry(placeholder_text="nombre-del-proyecto")
        p1.pack_start(w["folder"], False, False, 0)
        p1.pack_start(label("Se clona con tu usuario (sin sudo). Los de la lista, por SSH con tu clave; "
                            "una dirección https de un privado de GitHub, GitLab o Bitbucket se prueba sola "
                            "por SSH.", "dim-label", wrap=True), False, False, 0)
        w["err1"] = label("", "aviso-rojo", wrap=True)
        p1.pack_start(w["err1"], False, False, 0)
        w["stack"].add_named(p1, "1")
        w["folder_auto"] = True

        def url_changed(*_):
            name = re.sub(r"\.git$", "", w["url"].get_text().strip().rstrip("/").split("/")[-1].split(":")[-1])
            name = re.sub(r"[^A-Za-z0-9._-]", "-", name).lstrip(".-")[:100]
            if w["folder_auto"]:
                w["setting"] = True
                w["folder"].set_text(name)
                w["setting"] = False
            self.new_project_check()

        def folder_changed(*_):
            if not w.get("setting"):
                w["folder_auto"] = not w["folder"].get_text()
            self.new_project_check()
        w["url"].connect("changed", url_changed)
        w["folder"].connect("changed", folder_changed)

        # 2. Versión de PHP
        p2 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        p2.pack_start(label("¿En qué versión de PHP quieres crear el proyecto?"), False, False, 0)
        w["versions"] = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        p2.pack_start(w["versions"], False, False, 0)
        w["stack"].add_named(p2, "2")

        # 3. BBDD nueva y volcado
        p3 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        p3.pack_start(label("Nombre de la BBDD nueva:"), False, False, 0)
        w["db"] = Gtk.Entry(placeholder_text="wp_proyecto")
        w["db"].connect("changed", lambda *_: self.new_project_check())
        p3.pack_start(w["db"], False, False, 0)
        p3.pack_start(label("Volcado que se sube a la BBDD (.sql, .sql.gz o .zip):"), False, False, 0)
        w["file"] = Gtk.FileChooserButton(title="Elige el volcado de la BBDD",
                                          action=Gtk.FileChooserAction.OPEN)
        flt = Gtk.FileFilter()
        flt.set_name("Volcados (.sql, .sql.gz, .zip)")
        for pat in ("*.sql", "*.sql.gz", "*.zip", "*.SQL", "*.GZ", "*.ZIP"):
            flt.add_pattern(pat)
        w["file"].add_filter(flt)
        w["file"].connect("file-set", lambda *_: self.new_project_check())
        p3.pack_start(w["file"], False, False, 0)
        p3.pack_start(label("Si no eliges ninguno, la BBDD se crea vacía. El volcado se carga con "
                            "la carga protegida (con el usuario de la BBDD y sin DEFINER).",
                            "dim-label", wrap=True), False, False, 0)
        w["err3"] = label("", "aviso-rojo", wrap=True)
        p3.pack_start(w["err3"], False, False, 0)
        w["stack"].add_named(p3, "3")

        # 4. El dominio de producción: falsearlo en este equipo (como en Dominios y hosts) o no
        p4 = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        row4 = Gtk.Box(spacing=10)
        row4.pack_start(label("¿Falsear su dominio de producción en este equipo?", valign=Gtk.Align.CENTER), False, False, 0)
        w["fake"] = Gtk.Switch(active=False, valign=Gtk.Align.CENTER)
        w["fake"].connect("notify::active", lambda *_: self.new_project_check())
        row4.pack_end(w["fake"], False, False, 0)
        p4.pack_start(row4, False, False, 0)
        p4.pack_start(label("Dominio de producción:"), False, False, 0)
        w["domain"] = Gtk.Entry(placeholder_text="midominio.com")
        w["domain"].connect("changed", lambda *_: self.new_project_check())
        p4.pack_start(w["domain"], False, False, 0)
        p4.pack_start(label("Falseado, el navegador abre el proyecto en local con su dominio de verdad (con su "
                            "certificado), como en Dominios y hosts: lo que necesitan las tiendas PrestaShop y "
                            "los WordPress con el dominio en su BBDD. Si no, se abre en web.local.",
                            "dim-label", wrap=True), False, False, 0)
        w["err4"] = label("", "aviso-rojo", wrap=True)
        p4.pack_start(w["err4"], False, False, 0)
        w["stack"].add_named(p4, "4")

        # Botones: Cancelar a la izquierda; Atrás y Siguiente (o Montar proyecto) a la derecha
        nav = Gtk.Box(spacing=8)
        cancel = Gtk.Button(label="Cancelar")
        cancel.connect("clicked", lambda *_: self.toggle_new_project(False))
        nav.pack_start(cancel, False, False, 0)
        w["next"] = css(Gtk.Button(label="Siguiente"), "verde")
        w["next"].connect("clicked", lambda *_: self.new_project_go(1))
        nav.pack_end(w["next"], False, False, 0)
        w["back"] = Gtk.Button(label="Atrás")
        w["back"].connect("clicked", lambda *_: self.new_project_go(-1))
        nav.pack_end(w["back"], False, False, 0)
        outer.pack_start(nav, False, False, 0)
        return outer

    def toggle_new_project(self, show):
        w = self.np
        if show:
            w["repo"].set_text("")
            w["repo_note"].set_label("")
            w["fake"].set_active(False)
            w["domain"].set_text("")
            w["url"].set_text("")
            w["folder"].set_text("")
            w["folder_auto"] = True
            self.new_project_repos()
            w["db"].set_text("")
            w["db_auto"] = True
            w["file"].unselect_all()
            w["version"] = None
            w["stack"].set_visible_child_name("1")
            # (show_all no le llega: tiene no_show_all)
            self.new_proj_rev.get_child().show_all()
            self.new_proj_rev.show()
            self.new_project_check()
            self.proj_entry.set_text("")
        self.new_proj_rev.set_reveal_child(show)
        self.proj_new_btn.set_sensitive(not show)
        if show:
            GLib.idle_add(w["repo"].grab_focus)

    def new_project_page(self):
        return int(self.np["stack"].get_visible_child_name() or "1")

    def new_project_check(self):
        """Comprueba el paso en el que está el asistente: activa Siguiente y explica lo que falta."""
        w = self.np
        page = self.new_project_page()
        titles = {1: "Paso 1 de 4: el repositorio", 2: "Paso 2 de 4: versión de PHP",
                  3: "Paso 3 de 4: BBDD nueva", 4: "Paso 4 de 4: dominio de producción"}
        w["step"].set_label(titles[page])
        w["back"].set_visible(page > 1)
        w["next"].set_label("Montar proyecto" if page == 4 else "Siguiente")
        ok, err = True, ""
        if page == 1:
            url, folder = w["url"].get_text().strip(), w["folder"].get_text().strip()
            host, path = r"[A-Za-z0-9][A-Za-z0-9.-]*", r"[A-Za-z0-9_~][A-Za-z0-9._~/-]*"
            url_ok = bool(re.fullmatch(r"https://%s(:[0-9]{1,5})?/%s" % (host, path), url)
                          or re.fullmatch(r"git@%s:%s" % (host, path), url)
                          or re.fullmatch(r"ssh://git@%s(:[0-9]{1,5})?/%s" % (host, path), url))
            if not url:
                ok = False
            elif not url_ok:
                ok, err = False, "La dirección no es válida: usa https://… o git@servidor:usuario/repositorio.git"
            elif not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9._-]{0,99}", folder) or folder == ".lvm-sin-proyecto":
                ok, err = False, ("Pon un nombre de carpeta: letras sin acentos, números, punto, _ y -"
                                  if folder else "")
            elif os.path.lexists(os.path.join(HTDOCS, folder)):
                ok, err = False, "Ya existe /opt/htdocs/%s: elige otro nombre" % folder
            w["err1"].set_label(err)
            w["err1"].set_visible(bool(err))
        elif page == 2:
            ok = bool(w.get("version"))
        else:
            db = w["db"].get_text().strip()
            have = self.data["dbs"].get(w.get("version") or "", []) if self.data else []
            if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", db):
                ok, err = False, ("El nombre de la BBDD solo puede llevar letras sin acentos, números, _ y -"
                                  if db else "")
            elif db.lower() in (d.lower() for d in have):
                ok, err = False, "lampp-%s ya tiene una BBDD %s: elige otro nombre" % (w["version"], db)
            w["err3"].set_label(err)
            w["err3"].set_visible(bool(err))
        if page == 4:
            dom = w["domain"].get_text().strip().lower()
            w["domain"].set_sensitive(w["fake"].get_active())
            ok, err = True, ""
            if w["fake"].get_active() and not re.fullmatch(r"[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+", dom):
                ok, err = False, ("Dominio no válido (por ejemplo: midominio.com)" if dom else "")
            w["err4"].set_label(err)
            w["err4"].set_visible(bool(err))
        w["next"].set_sensitive(ok and not self.busy)

    def new_project_go(self, step):
        w = self.np
        page = self.new_project_page() + step
        if page == 5:
            self.new_project_run()
            return
        page = max(1, page)
        if page == 2:
            clear(w["versions"])
            insts = sorted(self.installs(), key=lambda i: [int(x) for x in re.findall(r"\d+", i["php"])],
                           reverse=True)
            if not insts:
                w["versions"].pack_start(label("No hay ninguna versión instalada: instala una en "
                                               "esta pestaña.", "aviso-rojo", wrap=True), False, False, 0)
            first = None
            for inst in insts:
                text = "PHP %s  ·  lampp-%s%s" % (inst["php"], inst["folder"],
                                                  "  (activa)" if inst["folder"] == self.data["active"] else "")
                rb = Gtk.RadioButton.new_with_label_from_widget(first, text)
                first = first or rb
                rb.connect("toggled", lambda b, f=inst["folder"]: b.get_active() and
                           (w.__setitem__("version", f), self.new_project_check()))
                w["versions"].pack_start(rb, False, False, 0)
                if inst["folder"] == (w.get("version") or self.data["active"]):
                    rb.set_active(True)
            if insts and not w.get("version"):
                w["version"] = insts[0]["folder"]
                first.set_active(True)
            w["versions"].show_all()
        if page == 3 and w.get("db_auto", True) and not w["db"].get_text():
            base = re.sub(r"[^a-z0-9_]", "_", w["folder"].get_text().strip().lower()).strip("_")[:40]
            w["db"].set_text(("wp_" + base) if base else "")
        w["stack"].set_visible_child_name(str(page))
        self.new_project_check()

    def new_project_run(self):
        w = self.np
        url, folder = w["url"].get_text().strip(), w["folder"].get_text().strip()
        version, db = w["version"], w["db"].get_text().strip()
        dump = w["file"].get_filename() or ""
        args = ["montar-proyecto", url, folder, version, db] + ([dump] if dump else [])
        domain = w["domain"].get_text().strip().lower() if w["fake"].get_active() else ""

        def faked(ok, *_):
            if ok:
                self.toast("%s, con %s falseado en este equipo" % (folder, domain))

        def done(ok, *_):
            if ok:
                self.toggle_new_project(False)
                self.toast("Proyecto nuevo montado: %s en lampp-%s con la BBDD %s" % (folder, version, db))
                # (después, si se ha pedido, su dominio de producción falseado)
                if domain:
                    GLib.idle_add(lambda: self.run_task("Falseando %s para %s" % (domain, folder),
                                                        ["nuevo-dominio", domain, folder], auto_close=True,
                                                        done_text="%s falseado: se abre en local" % domain,
                                                        on_done=faked) and False)
        self.run_task("Montando el proyecto %s" % folder, args, progress=True,
                      done_text="%s está clonado, cargado en lampp-%s y con su BBDD %s" % (folder, version, db),
                      on_done=done)

    def new_project_repo(self, full, web, kind):
        """Repositorio elegido de la lista de GitHub: su dirección SSH (con tu clave), su carpeta y, si su web
        es la de producción, su dominio para el paso 4 (y, en una tienda, falsearlo)."""
        w = self.np
        w["url"].set_text("git@github.com:%s.git" % full)
        dom = re.sub(r"^https?://", "", (web or "").strip().lower()).split("/")[0].split(":")[0]
        if re.fullmatch(r"[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+", dom):
            w["domain"].set_text(dom)
            w["fake"].set_active(kind == "ps")
        w["repo_note"].set_label("Se clona por SSH, con tu clave: git@github.com:%s.git%s" % (
            full, ("  ·  web: %s" % dom) if dom else ""))

    def new_project_search(self):
        """Al escribir en el buscador del paso 1: hasta NP_REPOS_HITS resultados debajo. Un repositorio
        pegado (botón de copiar de Repositorios) o escrito entero queda elegido."""
        w = self.np
        if w.get("repo_setting"):
            return
        text = w["repo"].get_text().strip()
        q = repo_query(text)
        rows = self.np_repos or []
        # (si se cambia lo escrito tras elegir uno, deja de estar elegido)
        if w.get("repo_picked") and q != w["repo_picked"]:
            w["repo_picked"] = None
            w["url"].set_text("")
            self.np_repos_show()
        hits = w["repo_hits"]
        clear(hits)
        exact = next((r for r in rows if r[0].lower() == q), None)
        if exact:
            self.new_project_pick(exact)
            return
        # (la dirección de un repositorio que no está en la lista, a su campo)
        if re.match(r"(git@|ssh://|https?://)", text):
            w["url"].set_text(text)
            q = ""
        if len(q) < 2:
            self.new_project_hits_shown(False)
            return
        found = [r for r in rows if q in r[0].lower()]
        for r in found[:NP_REPOS_HITS]:
            row = Gtk.ListBoxRow()
            row.on_activate = lambda r=r: self.new_project_pick(r)
            line = Gtk.Box(spacing=12, margin_start=12, margin_end=12, margin_top=6, margin_bottom=6)
            line.pack_start(label(r[0], ellipsize=3), False, True, 0)
            if r[1]:
                line.pack_end(label(r[1], "dim-label", "subtitulo", ellipsize=3, max_width_chars=30), False, True, 0)
            row.add(line)
            hits.add(row)
        if len(found) > NP_REPOS_HITS or not found:
            row = Gtk.ListBoxRow(activatable=False, selectable=False, can_focus=False)
            row.add(label("Y %d más: sigue escribiendo" % (len(found) - NP_REPOS_HITS) if found else
                          "Ningún repositorio con «%s»" % text if self.np_repos is not None else "Cargando la lista…",
                          "dim-label", margin_start=12, margin_end=12, margin_top=6, margin_bottom=6))
            hits.add(row)
        self.new_project_hits_shown(True)

    def new_project_hits_shown(self, show):
        hits = self.np["repo_hits"]
        if show:
            for row in hits.get_children():
                row.show_all()
            hits.show()
        else:
            hits.hide()
        # (la ventana del asistente, al alto de lo que enseña)
        top = hits.get_toplevel()
        if top is getattr(self, "np_dialog", None):
            top.resize(top.get_size()[0], 1)

    def new_project_pick(self, repo):
        w = self.np
        w["repo_setting"] = True
        w["repo"].set_text(repo[0])
        w["repo"].set_position(-1)
        w["repo_setting"] = False
        w["repo_picked"] = repo[0].lower()
        clear(w["repo_hits"])
        self.new_project_hits_shown(False)
        self.new_project_repo(*repo)

    def new_project_first_hit(self):
        """Intro en el buscador: el primer resultado."""
        for row in self.np["repo_hits"].get_children():
            if getattr(row, "on_activate", None):
                row.on_activate()
                return

    def new_project_search_key(self, _entry, event):
        """Flecha abajo en el buscador: a los resultados."""
        if event.keyval != Gdk.KEY_Down:
            return False
        rows = self.np["repo_hits"].get_children()
        if self.np["repo_hits"].get_visible() and rows and getattr(rows[0], "on_activate", None):
            rows[0].grab_focus()
            return True
        return False

    def new_project_repos(self):
        """La lista de repositorios de GitHub para el paso 1: ya está en memoria (np_repos_load, al abrir
        el programa). Si hace rato que no se pregunta a GitHub, se pone al día por detrás."""
        self.np_repos_show()
        if self.np_repos is None:
            self.np_repos_load(cache=True)
        if time.time() - self.np_repos_when > NP_REPOS_FRESH:
            self.np_repos_load()

    def np_repos_load(self, cache=False):
        """Los repositorios para el buscador de Nuevo proyecto, en segundo plano: los de la última vez
        (cache: al momento) o los de GitHub. Sin conexión, se queda la lista que había."""
        if cache and self.np_repos_when:
            return
        if not cache:
            if self.np_repos_busy:
                return
            self.np_repos_busy = True

        def got(_rc, out):
            rows = []
            for f in parse_lines(out):
                if f[0] == "R" and len(f) >= 11:
                    kind = "ps" if "prestashop" in f[6] + f[2] else "wp" if "wordpress" in f[6] + f[2] else ""
                    rows.append((f[1], f[7], kind))
            if not cache:
                self.np_repos_busy = False
                if rows:
                    self.np_repos_when = time.time()
            # (una respuesta de la última vez que llega tarde no pisa la de GitHub)
            if rows and not (cache and self.np_repos_when):
                self.np_repos = rows
            elif self.np_repos is None:
                self.np_repos = []
            self.np_repos_show()
            return False
        run_quick(["repos", "--todos"] + (["--cache"] if cache else []), got)

    def np_repos_show(self):
        """Debajo del buscador, cuántos hay, si el asistente ya existe."""
        w = getattr(self, "np", None)
        if not w or self.np_repos is None:
            return
        # (con uno ya elegido, debajo sigue lo que se va a clonar)
        if not w["url"].get_text():
            n = len(self.np_repos)
            w["repo_note"].set_label("%d repositorios de GitHub" % n if n else
                                     "Sin la lista de GitHub (conéctalo en Configuración, GitHub): escribe la dirección abajo")
            # (si ya se estaba escribiendo cuando ha llegado)
            if w["repo"].get_text().strip():
                self.new_project_search()

    def on_unload_project(self):
        p = self.projects
        if not p or not p.get("current"):
            return
        name = os.path.basename(p["current"].rstrip("/"))
        self.run_task("Desmontando el proyecto %s" % name, ["desmontar-proyecto"],
                      done_text="%s ya no apunta a %s" % (p["link"], name), auto_close=True)

    def link_of(self, db, ver):
        """Carpeta vinculada a una BBDD en una versión: la de esa versión ("" = ninguna), la de
        todas las versiones (como se guardaba hasta la 1.50) o None si no tiene."""
        p = self.projects or {}
        if (db, ver) in p.get("vlinks", {}):
            return p["vlinks"][(db, ver)]
        return p.get("saved", {}).get(db)

    def project_pairs(self, x):
        """(versión, BBDD) de un proyecto: las BBDD vinculadas a su carpeta en cada versión o, si no
        tiene ninguna, la de su configuración en las versiones donde no es de otro proyecto."""
        if not self.data:
            return []
        pairs = [(i, db) for i in self.installs() for db in self.data["dbs"].get(i["folder"], [])
                 if self.link_of(db, i["folder"]) == x["name"]]
        if pairs or not x["db"]:
            return pairs
        return [(i, x["db"]) for i in self.installs() if x["db"] in self.data["dbs"].get(i["folder"], [])
                and self.link_of(x["db"], i["folder"]) is None]

    def project_base(self, x):
        """Base de un proyecto que no está en ninguna versión (para los textos): la recordada para su
        carpeta o la de su configuración."""
        pairs = self.project_pairs(x)
        if pairs:
            return pairs[0][1]
        dbs = {db for i in self.installs() for db in self.data["dbs"].get(i["folder"], [])}
        saved = [db for db, f in (self.projects or {}).get("saved", {}).items() if f == x["name"]]
        for db in reversed(saved):
            if db in dbs:
                return db
        return x["db"] or (saved[-1] if saved else "")

    def update_project_search(self):
        if getattr(self, "proj_results", None) is None or not self.data:
            return
        p = self.projects
        now = ""
        esc = GLib.markup_escape_text
        if p and p["current"]:
            now = '%s → <span foreground="%s"><b>%s</b></span>' % (
                esc(p["link"]), GREEN, esc(os.path.basename(p["current"].rstrip("/"))))
        # Solo a dónde apunta el enlace: el vhost y la flecha, en el color normal, y el proyecto en
        # verde y negrita (sin título delante, para que quepa el nombre entero junto al botón de
        # desmontar). Desmontado: el vhost sin proyecto
        if now:
            self.proj_now.set_markup(now)
            # (si no cabe entero, al dejar el ratón encima)
            self.proj_now.set_tooltip_text("%s → %s" % (p["link"], p["current"].rstrip("/")))
        elif p and p.get("link") and not p.get("create"):
            self.proj_now.set_tooltip_text(None)
            self.proj_now.set_markup('%s → <i>ningún proyecto</i>  <span alpha="55%%">(enseña una página vacía)</span>'
                                     % esc(p["link"]))
        for b in (self.proj_unload, self.proj_open, self.proj_pma, self.proj_admin):
            b.set_visible(bool(now))
        self.proj_code.set_visible(bool(now) and vscode_app() is not None)
        # La versión montada no tiene la BBDD del proyecto cargado: aviso en rojo
        warn = ""
        if now and self.data and self.data.get("active"):
            db = self.loaded_project_db()
            x = self.loaded_project_entry()
            pairs = self.project_pairs(x) if x else []
            if db and not any(i["folder"] == self.data["active"] for i, _ in pairs) \
                    and db not in self.data["dbs"].get(self.data["active"], []):
                where = ["lampp-%s (%s)" % (i["folder"], d) for i, d in pairs]
                warn = ("El proyecto vinculado a %s no está disponible para esa versión: lampp-%s no "
                        "tiene su BBDD %s%s." % (p["link"], self.data["active"], db,
                                                 (" (está en %s; vuelve a cargarlo para cambiar de versión)"
                                                  % ", ".join(where)) if where else ""))
        self.proj_warn.set_label(warn)
        self.proj_warn.set_visible(bool(warn))
        if now:
            name = os.path.basename(p["current"].rstrip("/"))
            self.proj_open.set_tooltip_text("Abrir http://%s/ en el navegador" % p["link"])
            db = self.loaded_project_db()
            self.proj_pma.set_sensitive(bool(db))
            self.proj_pma.set_tooltip_text("Abrir la BBDD %s en phpMyAdmin" % db if db
                                           else "No se sabe qué BBDD usa %s" % name)
            kind, admin = self.loaded_project_admin()
            self.proj_admin.set_image(logo("prestashop" if kind == "ps" else "wordpress", 16))
            self.proj_admin.set_sensitive(bool(admin))
            self.proj_admin.set_tooltip_text(
                ("Abrir el back office de PrestaShop (http://%s/%s/)" if kind == "ps"
                 else "Abrir el panel de WordPress (http://%s/%s/)") % (p["link"], admin)
                + " con el administrador de pruebas ya escrito (local@local.test, contraseña local): "
                  "solo hay que pulsar Entrar" if admin
                else "%s no es un WordPress ni una tienda PrestaShop con su carpeta de administración" % name)
            self.proj_code.set_tooltip_text(
                "Abrir %s en Visual Studio Code (si ya está abierto, se trae su ventana delante)" % name)
            self.proj_unload.set_tooltip_text(
                "Desmontar %s: %s deja de apuntar a él y enseña una página vacía" % (name, p["link"]))
        self.proj_now_row.set_visible(bool(p and p.get("link") and not p.get("create")))
        lb, q = self.proj_results, self.proj_entry.get_text().strip().lower()
        clear(lb)
        if not q or not p:
            lb.hide()
            return
        hits = [x for x in p["list"] if q in x["name"].lower()]
        hits.sort(key=lambda x: (not x["name"].lower().startswith(q), x["name"].lower()))
        if not hits:
            lb.add(ActionRow("Ningún proyecto con «%s» en el nombre" % q,
                             "Las carpetas de /opt/htdocs (sin las ocultas ni los enlaces)."))
        limit = 30
        for x in hits[:limit]:
            lb.add(self.project_hit_row(x, q))
        if len(hits) > limit:
            lb.add(ActionRow("Y %d más…" % (len(hits) - limit),
                             "Escribe más letras del nombre para encontrarlo."))
        for row in lb.get_children():
            row.show_all()
        lb.show()

    def project_hit_row(self, x, q):
        name = x["name"]
        row = ActionRow(name)
        kind = {"wp": "wordpress", "ps": "prestashop"}.get(x["kind"])
        row.add_prefix(section_icon(("logo", kind) if kind else ("icono", "folder-symbolic", ""), 16))
        start = name.lower().find(q)
        esc = GLib.markup_escape_text
        row.title.set_markup("%s<b>%s</b>%s" % (esc(name[:start]), esc(name[start:start + len(q)]),
                                                esc(name[start + len(q):])))
        pairs = self.project_pairs(x)
        db = self.project_base(x)
        parts = [{"wp": "WordPress", "ps": "PrestaShop"}.get(x["kind"], "")]
        if pairs:
            # (BBDD wp_tienda en lampp-8.4, wp_tienda_8_5 en lampp-8.5.12)
            by = {}
            for i, d in pairs:
                by.setdefault(d, []).append("lampp-%s" % i["folder"])
            parts.append(", ".join("BBDD %s en %s" % (d, ", ".join(v)) for d, v in by.items()))
        elif db:
            parts.append("BBDD %s" % db)
            parts.append("no está en ninguna versión")
        else:
            parts.append("sin BBDD detectada")
        if x["php"]:
            parts.append(".php-version %s" % x["php"])
        row.subtitle.set_label("  ·  ".join(t for t in parts if t))
        row.subtitle.set_no_show_all(False)
        current = self.projects and os.path.basename(self.projects["current"].rstrip("/")) == name
        if current:
            row.add_title_tag(label("Cargado", "texto-activa", "subtitulo"))
        lk = Gtk.Button(tooltip_text="Vincular %s con su BBDD"
                        % name, relief=Gtk.ReliefStyle.NONE, sensitive=not self.busy and bool(self.data))
        lk.add(icon("insert-link-symbolic"))
        lk.connect("clicked", lambda *_: self.on_link_project(x))
        row.add_suffix(lk)
        b = Gtk.Button(label="Cargar", sensitive=not self.busy)
        b.connect("clicked", lambda *_: self.on_load_folder(x))
        row.add_suffix(b)
        return row

    def on_link_project(self, x):
        """Elige con qué BBDD va la carpeta en cada versión (o con ninguna): Cargar proyecto monta
        la versión con esa BBDD. Cada BBDD es de un solo proyecto en cada versión."""
        installs = sorted(self.installs(), key=lambda i: ver_tuple(i["php"]), reverse=True)
        if not installs:
            return
        pairs = self.project_pairs(x)
        name = x["name"]
        dlg = Gtk.Dialog(title="Vincular BBDD", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(600, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Guardar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        box.pack_start(css(label("BBDD de %s en cada versión" % name, wrap=True, max_width_chars=60),
                           "title-3"), False, False, 0)
        box.pack_start(label("Cargar proyecto monta la versión con la BBDD que elijas aquí. Con "
                             "«Ninguna», la carpeta deja de ir con esa versión (la BBDD no se toca). "
                             "Cada BBDD es de un solo proyecto en cada versión: si era de otro, "
                             "deja de serlo.", "dim-label", wrap=True, max_width_chars=60),
                         False, False, 0)
        grid = Gtk.Grid(column_spacing=12, row_spacing=8, margin_top=6)
        combos = []
        for n, i in enumerate(installs):
            dbs = sorted(self.data["dbs"].get(i["folder"], []), key=str.lower)
            mine = [d for j, d in pairs if j["folder"] == i["folder"]]
            grid.attach(label("PHP %s  (lampp-%s)" % (i["php"], i["folder"])), 0, n, 1, 1)
            c = Gtk.ComboBoxText(hexpand=True)
            c.append("@ninguna", "— Ninguna —")
            for d in dbs:
                other = self.link_of(d, i["folder"])
                c.append(d, d if other in (None, "", name) else "%s  (de %s)" % (d, other))
            c.set_active_id(mine[0] if mine else "@ninguna")
            narrow(c, 34)
            if not dbs:
                c.set_sensitive(False)
            grid.attach(c, 1, n, 1, 1)
            combos.append((i, c, mine))
        box.pack_start(grid, False, False, 0)
        box.show_all()
        resp = run_dialog(dlg)
        chosen = [(i, "" if c.get_active_id() in (None, "@ninguna") else c.get_active_id(), mine)
                  for i, c, mine in combos]
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        changes = []
        for i, new, mine in chosen:
            ver = i["folder"]
            for d in mine:
                if d != new:
                    changes.append((d, ver, ""))
            # (también la que solo venía de su configuración: así queda fija)
            if new and self.link_of(new, ver) != name:
                changes.append((new, ver, name))
        if not changes:
            return
        if SIMULATE:
            self.toast("[simulación] no se cambian los vínculos")
            return
        err = write_links(changes)
        if err:
            message(self.win, "No se han podido guardar los vínculos", err, Gtk.MessageType.ERROR)
            return
        self.toast("Vínculos de %s guardados" % name)
        run_quick(["gui-proyectos"], self.on_projects_data)

    def on_load_folder(self, x):
        p = self.projects
        if not p or not p["link"]:
            message(self.win, "No hay un vhost para cargar proyectos",
                    "Ningún vhost de /opt/config/httpd-vhosts.conf tiene como DocumentRoot un "
                    "enlace de /opt/htdocs (como web.local).", Gtk.MessageType.WARNING)
            return
        db = self.project_base(x)
        cands = self.project_pairs(x)
        found = bool(cands)
        if not cands:
            cands = [(i, db) for i in self.installs()]
        if not cands:
            message(self.win, "No hay ninguna versión instalada",
                    "Instala una versión de PHP en esta pestaña para cargar proyectos.",
                    Gtk.MessageType.WARNING)
            return
        asked = len(cands) > 1
        if asked:
            chosen = self.pick_version(x, db, cands, found)
            if not chosen:
                return
        else:
            chosen = cands[0]
        inst, db = chosen
        self.do_load_project(x["name"], db, inst, p["link"], p["create"], confirm_switch=not asked)

    def pick_version(self, x, db, cands, found):
        """Versión de PHP (y su BBDD) en la que se carga un proyecto, cuando puede ir en varias.
        cands: (versión, BBDD). Devuelve la elegida o None."""
        active = self.data["active"]
        pre = next((c for c in cands if c[0]["folder"] == active), None) or \
            next((c for c in cands if x["php"] and c[0]["php"].startswith(x["php"])), None) or cands[0]
        dlg = Gtk.Dialog(title="Cargar proyecto", transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(520, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Cargar proyecto", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        ask = ("¿Qué versión del proyecto y de PHP quieres?" if found else
               "¿Con qué versión de PHP quieres cargar el proyecto?")
        box.pack_start(css(label(ask, wrap=True, max_width_chars=60), "title-3"), False, False, 0)
        if found:
            why = ("%s está vinculado a una BBDD en %d versiones de PHP y cada una guarda su "
                   "propia copia. Elige cuál cargar (cámbialas con el botón de vincular):"
                   % (x["name"], len(cands)))
        elif db:
            why = ("La BBDD de %s (%s) no está en ninguna versión: súbela después en la "
                   "pestaña BBDD. Elige con qué versión de PHP cargarlo:" % (x["name"], db))
        else:
            why = ("No se sabe qué BBDD usa %s. Elige con qué versión de PHP cargarlo:"
                   % x["name"])
        box.pack_start(label(why, "dim-label", wrap=True, max_width_chars=60), False, False, 0)
        first, radios = None, []
        for c in cands:
            i, cdb = c
            notes = []
            if found:
                notes.append("BBDD %s" % cdb)
            if i["folder"] == active:
                notes.append("la activa")
            if x["php"] and i["php"].startswith(x["php"]):
                notes.append("la de su .php-version")
            text = "PHP %s  (lampp-%s)%s" % (i["php"], i["folder"],
                                            "  ·  " + ", ".join(notes) if notes else "")
            rb = Gtk.RadioButton.new_from_widget(first)
            lines = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            lines.pack_start(label(text), False, False, 0)
            when = db_date_text(*self.data["dbdate"].get((i["folder"], cdb), (0, ""))) if found else ""
            if when:
                lines.pack_start(label("BBDD: " + when, "dim-label", "subtitulo"),
                                 False, False, 0)
            rb.add(lines)
            first = first or rb
            # Cada opción en su tarjeta; la elegida, con el borde verde
            opt = css(Gtk.Box(), "opcion")
            opt.pack_start(rb, True, True, 0)
            rb.connect("toggled", lambda b, o=opt: (o.get_style_context().add_class("elegida")
                                                     if b.get_active() else
                                                     o.get_style_context().remove_class("elegida")))
            rb.set_active(c is pre)
            if c is pre:
                css(opt, "elegida")
            radios.append((rb, c))
            box.pack_start(opt, False, False, 0)
        box.show_all()
        resp = run_dialog(dlg)
        chosen = next((i for rb, i in radios if rb.get_active()), None)
        dlg.destroy()
        return chosen if resp == Gtk.ResponseType.ACCEPT else None

    def build_versions(self):
        clear(self.ver_box)
        d = self.data
        if d["unregistered"]:
            box, lb = group("Hay un XAMPP sin registrar",
                            "/opt/lampp es una instalación de XAMPP completa y no un enlace. "
                            "Regístrala con un nombre (por ejemplo 8.2.12) para poder gestionarla "
                            "junto a las demás.")
            row = ActionRow("XAMPP en /opt/lampp")
            b = css(Gtk.Button(label="Registrar…"), "verde")
            b.connect("clicked", self.on_register)
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)

        if d["stray"]:
            # Procesos de otras versiones que se quedaron en memoria al cambiar (el lampp de XAMPP
            # solo cierra lo que encuentra en sus .pid)
            box, lb = group("Hay procesos de otras versiones en memoria",
                            "Solo debería estar en memoria la versión montada%s. Ocupan memoria y "
                            "pueden bloquear los puertos 80, 443 y 3306."
                            % (" (lampp-%s)" % d["active"] if d["active"] else ""))
            row = ActionRow("Procesos que sobran", d["stray"])
            row.subtitle.set_line_wrap(True)
            row.subtitle.set_ellipsize(0)
            b = css(Gtk.Button(label="Cerrarlos"), "destructive-action")
            b.connect("clicked", self.on_close_stray)
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        if d["dbsys"]:
            # Tablas del sistema de MariaDB antiguas: el servidor llena su registro de errores
            ver, size = d["dbsys"]
            box, lb = group("Tablas del sistema de MariaDB antiguas",
                            "Las tablas del sistema (mysql.*) son de una MariaDB anterior y el servidor "
                            "escribe un error cada vez que las usa: su registro de errores no para de "
                            "crecer. Repararlas las pone al día con el mysql_upgrade de la versión, sin "
                            "tocar las BBDD de los proyectos, después de guardar una copia en "
                            "~/lvm-copias, y vacía el registro si es grande.")
            row = ActionRow("MariaDB de lampp-%s" % ver, "Registro de errores: %s" % fmt_size(size))
            b = css(Gtk.Button(label="Repararlas"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Reparando las tablas del sistema de MariaDB", ["reparar-bd-sistema"],
                done_text="Tablas del sistema de MariaDB al día", auto_close=True))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        old_pma = [i for i in self.installs() if pma_outdated(i["php"], i["pma"])]
        if old_pma:
            box, lb = group("phpMyAdmin antiguo",
                            "Estas versiones traen un phpMyAdmin con fallos de seguridad que ya están "
                            "corregidos. Actualizarlo pone el más nuevo que admite su PHP, con la "
                            "misma configuración; el anterior queda en phpmyadmin.anterior.")
            row = ActionRow("phpMyAdmin con fallos corregidos después",
                            ", ".join("lampp-%s (%s)" % (i["folder"], i["pma"]) for i in old_pma))
            b = css(Gtk.Button(label="Actualizarlos"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Actualizando phpMyAdmin", ["actualizar-phpmyadmin", "--todas"],
                done_text="phpMyAdmin actualizado", auto_close=True))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        if d["unsecured"]:
            # Versiones a las que les falta algo de lo que pone el gestor (cerradas a la red y lo de
            # cada repaso de seguridad): se protegen todas a la vez
            box, lb = group("A algunas versiones les faltan protecciones",
                            "Les falta algo de lo que pone el gestor: solo para este equipo (si se "
                            "arrancan a mano, escucharían en toda la red), phpMyAdmin cerrado a otras "
                            "webs, MariaDB sin acceso a los ficheros del equipo... Protegerlas lo pone, "
                            "como en la activa; pide la contraseña de administrador.")
            row = ActionRow("Versiones sin proteger",
                            ", ".join("lampp-%s" % v for v in d["unsecured"]))
            b = css(Gtk.Button(label="Protegerlas"), "verde")
            b.connect("clicked", self.on_secure_all)
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)

        if d["certs"] or d["cas"]:
            # Certificados de proyectos en los que confía todo el equipo (no solo el navegador para
            # ese dominio): con su clave se podría falsificar cualquier web real en este equipo
            why = []
            if any(r == "falta" for _, r in d["certs"]):
                why.append("no tienen el certificado (Apache no arrancaría)")
            if any(r == "sistema" for _, r in d["certs"]):
                why.append("están en /etc/ssl/certs, donde el sistema los da por buenos para cualquier web")
            if any(r == "ca" for _, r in d["certs"]):
                why.append("son de CA (con su clave se puede firmar cualquier web)")
            if d["cas"]:
                why.append("los firma una CA de confianza sin límite de dominios (%s) cuya clave puede "
                           "leer cualquier programa tuyo, como el PHP de una web" % ", ".join(d["cas"]))
            box, lb = group("Certificados en los que confía todo el equipo",
                            "Los certificados https de estos proyectos " + "; ".join(why) + ". "
                            "Arreglarlos les pone uno propio, que solo vale para su dominio, y quita "
                            "esa confianza. Después el navegador avisará una vez en cada proyecto: "
                            "acepta el aviso. Pide la contraseña de administrador.")
            names = [dom for dom, _ in d["certs"]]
            row = ActionRow("Proyectos con https", ", ".join(names[:6]) + (" y %d más" % (len(names) - 6)
                                                                        if len(names) > 6 else "")
                            if names else "Ninguno: solo la CA")
            b = css(Gtk.Button(label="Arreglarlos"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Arreglando los certificados", ["arreglar-certificados"],
                done_text="Certificados arreglados"))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        if d["untrusted"]:
            # Proyectos https cuyo certificado propio no acepta el navegador: avisa al abrirlos y las
            # herramientas que lo manejan (Claude in Chrome) no pueden pasar del aviso
            box, lb = group("El navegador avisa al abrir estos proyectos",
                            "Chrome y Firefox no aceptan todavía su certificado: sale «La conexión no "
                            "es privada» y las herramientas que manejan el navegador (como Claude in "
                            "Chrome) no pueden abrirlos. Confiar hace que acepte el certificado propio "
                            "de cada proyecto, que solo vale para su dominio: no sirve para falsificar "
                            "ninguna otra web. El de una tienda con dominio real, solo mientras esté "
                            "falseada en /etc/hosts: al dejar de falsearla, deja de aceptarlo (con su "
                            "clave se podría suplantar la web de verdad). Después, si el navegador "
                            "estaba abierto, ciérralo y vuelve a abrirlo.")
            names = d["untrusted"]
            row = ActionRow("Proyectos que avisan en el navegador",
                            ", ".join(names[:6]) + (" y %d más" % (len(names) - 6) if len(names) > 6 else ""))
            b = css(Gtk.Button(label="Confiar"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Confiando en los certificados de los proyectos", ["confiar-certificados"],
                done_text="El navegador acepta los certificados de los proyectos"))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)
        if d["stale"]:
            # Tiendas con dominio real cuyo certificado aun acepta el navegador y ya no estan falseadas
            # (hosts cambiado a mano): con su clave se podria suplantar la web de verdad
            box, lb = group("El navegador acepta webs reales que ya no están falseadas",
                            "El navegador aceptaba su certificado mientras estaban falseadas en "
                            "/etc/hosts. Ya no lo están, así que el navegador va a la web de verdad, y "
                            "con la clave de ese certificado (Apache la tiene en memoria) se la podría "
                            "suplantar. Quitar hace que deje de aceptarlo. Después, si el navegador "
                            "estaba abierto, ciérralo y vuelve a abrirlo.")
            names = d["stale"]
            row = ActionRow("Webs reales que acepta el navegador",
                            ", ".join(names[:6]) + (" y %d más" % (len(names) - 6) if len(names) > 6 else ""))
            b = css(Gtk.Button(label="Quitar"), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Quitando los certificados de las webs reales", ["confiar-certificados", "--quitar"],
                done_text="El navegador ya no acepta esos certificados"))
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)

        # Lo primero: cargar un proyecto (el bloque se crea una vez y se conserva al redibujar,
        # para no perder lo escrito en el buscador)
        if getattr(self, "proj_box", None) is None:
            self.proj_box = self.build_project_box()
        parent = self.proj_box.get_parent()
        if parent:
            parent.remove(self.proj_box)
        self.ver_box.pack_start(self.proj_box, False, False, 0)
        self.update_project_search()

        if not d["launcher"] and not SIMULATE:
            box, lb = group()
            row = ActionRow("Icono en el menú de aplicaciones",
                            "Crea el acceso «Nexum Dev Stack» para abrir esta ventana.")
            b = Gtk.Button(label="Crear")
            b.connect("clicked", self.on_create_launcher)
            row.add_suffix(b)
            lb.add(row)
            self.ver_box.pack_start(box, False, False, 0)

        act = next((i for i in d["installs"] if i["folder"] == d["active"]), None)
        box, lb = group("Versión activa")
        if act:
            row = ActionRow("PHP %s" % act["php"], "/opt/lampp → lampp-%s" % act["folder"])
            row.add_prefix(label("●", "punto-verde" if d["running"] else "punto-gris"))
            row.add_suffix(label("En marcha" if d["running"] else "Parada", "dim-label"))
            # Parar = lvm disable: para y quita el enlace /opt/lampp, asi que php (enlazado a
            # /opt/lampp/bin/php) deja de responder. Tambien con la version ya parada
            actions = [("view-refresh-symbolic", "Reiniciar", "reiniciar", "icono-azul")] \
                if d["running"] else \
                [("media-playback-start-symbolic", "Arrancar", "arrancar", "icono-verde")]
            actions.append(("media-playback-stop-symbolic",
                            "Parar y desactivar (como lvm disable): php deja de responder hasta "
                            "que actives una versión", "parar", "icono-rojo"))
            for ic, tip, cmd, color in actions:
                # (más grandes que los demás botones de icono: son los que más se usan)
                b = css(Gtk.Button(tooltip_text=tip, relief=Gtk.ReliefStyle.NONE), color, "control-grande")
                b.add(icon(ic, 24))
                b.connect("clicked", self.on_control, cmd, tip)
                row.add_suffix(b)
            web = Gtk.Button(label="Abrir localhost", sensitive=d["running"])
            web.connect("clicked", lambda *_: self.open_uri("http://localhost/"))
            row.add_suffix(web)
        else:
            row = ActionRow("Ninguna versión activa",
                            "Activa una de las versiones instaladas para usarla.")
            row.add_prefix(label("●", "punto-gris"))
        lb.add(row)
        self.ver_box.pack_start(box, False, False, 0)

        self.sg_tag = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)
        self.sg_btn = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)
        if d["installs"]:
            box, lb = fold_group("Instaladas", "Pulsa una versión para ver sus componentes. "
                                 "Pulsa el título para plegar o desplegar la lista.",
                                 "instaladas" not in self.folded,
                                 lambda on: self.remember_fold("instaladas", on),
                                 plural(len(d["installs"]), "versión", "versiones"))
            for inst in d["installs"]:
                lb.add(self.version_row(inst))
        else:
            box, lb = group("Instaladas")
            row = ActionRow("No hay ninguna versión instalada",
                            "Instala la primera más abajo.")
            lb.add(row)
        self.ver_box.pack_start(box, False, False, 0)
        # Debajo, instalar nuevas versiones (se rellena aparte, al consultar php.net)
        parent = self.inst_box.get_parent()
        if parent:
            parent.remove(self.inst_box)
        self.ver_box.pack_start(self.inst_box, False, False, 0)
        self.ver_box.show_all()

    def version_row(self, inst):
        folder = inst["folder"]
        is_active = folder == self.data["active"]
        exp = ExpanderRow("PHP %s" % inst["php"], "/opt/lampp-%s" % folder,
                          on_toggle=lambda on, f=folder: self.remember(f, on))
        # Fecha de publicación de su PHP, junto a la versión (como en Instalar)
        php_date = self.php_dates.get(folder)
        if php_date and php_date[0] == inst["php"]:
            tag = label(fmt_day(php_date[1]), "dim-label", "fecha-version")
            tag.set_tooltip_text("Publicada en php.net el %s" % fmt_day(php_date[1]))
            exp.add_title_tag(tag)
        kind = inst["kind"]
        # Icono: el de XAMPP si es (o va sobre) un XAMPP; el de PHP si es una pila propia
        if kind != "propia":
            for c in exp.prefix.get_children():
                exp.prefix.remove(c)
            exp.add_prefix(section_icon(("logo", "xampp"), 16))
        tag = label({"XAMPP": "XAMPP", "propia": "Pila propia"}.get(kind, "Sobre XAMPP"),
                    "tag", "dim-label", xalign=0.5)
        self.sg_tag.add_widget(tag)
        exp.add_suffix(tag)
        if is_active:
            b = css(Gtk.Button(label="Activa", can_focus=False), "verde")
        else:
            b = Gtk.Button(label="Activar")
            b.connect("clicked", self.on_activate_version, folder)
        self.sg_btn.add_widget(b)
        exp.add_suffix(b)

        dbs = len(self.data["dbs"].get(folder, []))
        db_text = plural(dbs, "propia", "propias") if inst["owner"] == folder else \
            "usa las de lampp-%s" % inst["owner"]
        for name, val, spec in [
                ("Apache", inst["apache"], ("logo", "apache")),
                ("MariaDB", inst["mariadb"], ("logo", "mariadb")),
                ("ProFTPD", inst["ftp"], ("icono", "folder-remote-symbolic", "")),
                ("Perl", inst["perl"], ("logo", "perl")),
                ("phpMyAdmin", inst["pma"], ("logo", "phpmyadmin")),
                ("BBDD", db_text, ("icono", "drive-multidisk-symbolic", ""))]:
            r = ActionRow(name)
            # (su propio icono, en lugar del que pondría la fila por su título)
            for c in r.prefix.get_children():
                r.prefix.remove(c)
            r.add_prefix(section_icon(spec, 16))
            if name == "phpMyAdmin" and pma_outdated(inst["php"], inst["pma"]):
                r.add_title_tag(label("antiguo", "estado", "seguridad"))
                up = Gtk.Button(label="Actualizar", tooltip_text="Actualizar phpMyAdmin")
                up.connect("clicked", lambda *_, f=folder: self.on_update_pma(f))
                r.add_suffix(up)
            r.add_suffix(label(val, "dim-label"))
            exp.add_row(r)

        actions = Gtk.Box(spacing=8, halign=Gtk.Align.END, margin=10)
        branch = inst["php"].rsplit(".", 1)[0]
        if kind != "XAMPP" and branch == folder:
            up = Gtk.Button(label="Actualizar")
            up.connect("clicked", self.on_update, folder)
            actions.pack_start(up, False, False, 0)
        rm = css(Gtk.Button(label="Desinstalar…", sensitive=not inst["blocker"]),
                 "destructive-action")
        if inst["blocker"]:
            rm.set_tooltip_text(inst["blocker"])
        rm.connect("clicked", self.on_remove, inst)
        actions.pack_start(rm, False, False, 0)
        exp.add_row(actions)
        if folder in self.expanded:
            exp.set_expanded(True)
        return exp

    def remember(self, folder, on):
        (self.expanded.add if on else self.expanded.discard)(folder)

    def remember_fold(self, key, opened):
        """Guarda qué apartados están plegados (siguen así al volver a abrir la ventana)."""
        (self.folded.discard if opened else self.folded.add)(key)
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            with open(FOLDED_FILE, "w", encoding="utf-8") as f:
                f.write("".join(k + "\n" for k in sorted(self.folded)))
        except OSError:
            pass

    # acciones
    def run_task(self, title, args, **kw):
        bg = getattr(self, "bg_task", None)
        if self.busy and bg is not None and not bg.finished:
            # (otra tarea en segundo plano: no van dos a la vez, que tocarían lo mismo)
            self.toast("Hay una tarea en marcha: espera a que acabe")
            bg.to_front()
            return None
        self.busy = True
        user_done = kw.pop("on_done", None)

        def done(ok, task, p):
            self.busy = False
            if user_done:
                user_done(ok, task, p)
            self.reload(branches=kw_reload)
        kw_reload = kw.pop("reload_branches", False)
        return Task(self, title, args, on_done=done, **kw)

    def on_control(self, _btn, cmd, what):
        folder = self.data["active"]
        if cmd == "parar":
            self.run_task("Parando y desactivando lampp-%s" % folder, ["disable"],
                          done_text="lampp-%s parada y desactivada" % folder, auto_close=True)
            return
        texts = {"arrancar": "Versión activa arrancada", "reiniciar": "Versión activa reiniciada"}
        self.run_task("%s lampp-%s" % (what, folder), [cmd], done_text=texts[cmd], auto_close=True)

    def on_vhosts(self, *_):
        """Los vhosts son del administrador (Apache los lee como root al arrancar): se edita una
        copia en ~/.lvm-instalador y, al pulsar Aplicar, el script la comprueba, la escribe con sudo
        (guardando antes la anterior en ~/lvm-copias) y recarga Apache."""
        if not self.data:
            return
        path = self.data["vhosts"]
        real = os.path.realpath(path)
        if not os.path.isfile(real):
            message(self.win, "No se encuentra el fichero de vhosts",
                    "%s no existe en la versión activa." % path, Gtk.MessageType.WARNING)
            return
        copy = os.path.join(LOG_DIR, "httpd-vhosts.conf")
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            shutil.copyfile(real, copy)
        except OSError as exc:
            message(self.win, "No se ha podido leer %s" % real, str(exc), Gtk.MessageType.ERROR)
            return
        self.open_text(copy)
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.INFO,
                                buttons=Gtk.ButtonsType.NONE, text="Editar vhosts")
        dlg.format_secondary_text(
            "Los vhosts (%s) son del administrador: Apache los lee como root al arrancar. Se abre "
            "una copia (%s) en el editor de textos.\n\nHaz los cambios, guárdalos y pulsa Aplicar: "
            "se comprueban, se guarda una copia de los actuales en ~/lvm-copias, se escriben los "
            "nuevos (pide la contraseña de sudo) y se recarga Apache. Si Apache no los acepta, se "
            "dejan como estaban." % (real, copy))
        widen(dlg)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Aplicar", Gtk.ResponseType.ACCEPT), "verde")
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        try:
            with open(real, "rb") as a, open(copy, "rb") as b:
                same = a.read() == b.read()
        except OSError:
            same = False
        if same:
            self.toast("No has cambiado nada en los vhosts (¿guardaste los cambios?)")
            return
        self.run_task("Guardando los vhosts", ["vhosts", "--aplicar", copy],
                      done_text="Vhosts actualizados", auto_close=True)

    def on_hosts(self, *_):
        """/etc/hosts es de root: se edita una copia en ~/.lvm-instalador y, al pulsar Aplicar,
        el script la escribe encima con sudo (guardando antes el anterior en ~/lvm-copias)."""
        src = self.data["hosts"] if self.data else "/etc/hosts"
        copy = os.path.join(LOG_DIR, "hosts")
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            shutil.copyfile(src, copy)
        except OSError as exc:
            message(self.win, "No se ha podido leer %s" % src, str(exc), Gtk.MessageType.ERROR)
            return
        self.open_text(copy)
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.INFO,
                                buttons=Gtk.ButtonsType.NONE, text="Editar hosts")
        dlg.format_secondary_text(
            "%s es del administrador, así que se abre una copia (%s) en el editor de textos.\n\n"
            "Haz los cambios, guárdalos y pulsa Aplicar: se guarda una copia del %s actual en "
            "~/lvm-copias y se escribe el nuevo (pide la contraseña de sudo)." % (src, copy, src))
        widen(dlg)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Aplicar", Gtk.ResponseType.ACCEPT), "verde")
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        try:
            with open(src, "rb") as a, open(copy, "rb") as b:
                same = a.read() == b.read()
        except OSError:
            same = False
        if same:
            self.toast("No has cambiado nada en %s (¿guardaste los cambios?)" % src)
            return
        self.run_task("Guardando %s" % src, ["hosts", "--aplicar", copy],
                      done_text="%s actualizado" % src, auto_close=True)

    def on_activate_version(self, _btn, folder):
        st, why = (self.data or {}).get("php2shell", {}).get(folder, ("", ""))
        if st == "vulnerable" and not confirm(
                self.win, "lampp-%s es vulnerable a PHP2Shell" % folder,
                "%s. Una petición preparada puede ejecutar código con tu usuario. Mejor actualízala "
                "(menú ⋮ de la versión)." % why,
                "Activar lampp-%s igualmente" % folder, destructive=True):
            return
        self.run_task("Activando lampp-%s" % folder, ["use", folder],
                      done_text="lampp-%s activada" % folder, auto_close=True)

    def on_update(self, btn, folder):
        btn.set_sensitive(False)
        self.toast("Comprobando si hay una versión más nueva…")

        def checked(_rc, out):
            btn.set_sensitive(True)
            res = out.strip().splitlines()[-1].split("|") if out.strip() else ["error"]
            if res[0] == "si":
                self.toast("El paquete lampp-%s se encuentra actualizado" % folder)
            elif res[0] == "no" and len(res) > 1:
                if confirm(self.win, "¿Actualizar lampp-%s?" % folder,
                           "PHP %s con los últimos parches de su rama. La actual sigue funcionando "
                           "mientras se compila (varios minutos)." % res[1],
                           "Actualizar a PHP %s" % res[1]):
                    self.run_task("Actualizando lampp-%s" % folder, ["actualizar", folder],
                                  progress=True, reload_branches=True,
                                  done_text="lampp-%s actualizada a PHP %s" % (folder, res[1]))
            else:
                message(self.win, "No se ha podido comprobar la versión",
                        "No se ha podido consultar php.net. Comprueba la conexión a internet.",
                        Gtk.MessageType.WARNING)
            return False
        run_quick(["gui-al-dia", folder], checked)

    def on_remove(self, _btn, inst):
        folder = inst["folder"]
        own = inst["owner"] == folder
        dbs = self.data["dbs"].get(folder, []) if own else []
        text = "Se borrará la carpeta /opt/lampp-%s (PHP %s). " % (folder, inst["php"])
        if not own:
            text += "Sus BBDD no se tocan: son las de lampp-%s. " % inst["owner"]
        elif dbs:
            text += "Sus %s se borrarán con ella. " % plural(len(dbs), "BBDD propia",
                                                            "BBDD propias")
        text += "Los proyectos de /opt/htdocs y los vhosts no se tocan."

        extra = None
        state = {"copy": bool(dbs)}
        if dbs:
            extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            copy = Gtk.CheckButton(label="Guardar antes una copia de sus BBDD en "
                                         "~/lvm-copias", active=True)
            extra.pack_start(copy, False, False, 0)
            warn = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            warn.pack_start(label("Sin copia, las BBDD no se podrán recuperar. "
                                  "Escribe %s para confirmar:" % folder, "error", wrap=True,
                                  max_width_chars=50), False, False, 0)
            entry = Gtk.Entry()
            warn.pack_start(entry, False, False, 0)
            warn.set_no_show_all(True)
            extra.pack_start(warn, False, False, 0)

        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.WARNING,
                                buttons=Gtk.ButtonsType.NONE,
                                text="¿Desinstalar lampp-%s?" % folder)
        dlg.format_secondary_text(text)
        if extra:
            dlg.get_message_area().pack_start(extra, False, False, 0)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Desinstalar", Gtk.ResponseType.ACCEPT), "destructive-action")
        dlg.set_default_response(Gtk.ResponseType.CANCEL)
        if dbs:
            def update(*_):
                state["copy"] = copy.get_active()
                warn.set_visible(not state["copy"])
                for child in warn.get_children():
                    child.show()
                ok.set_sensitive(state["copy"] or entry.get_text().strip() == folder)
            copy.connect("toggled", update)
            entry.connect("changed", update)
        dlg.show_all()
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        args = ["desinstalar", folder] + (["--copia"] if state["copy"] else [])
        self.expanded.discard(folder)
        self.run_task("Desinstalando lampp-%s" % folder, args, reload_branches=True,
                      done_text="lampp-%s desinstalada" % folder
                      + (" (copia en ~/lvm-copias)" if state["copy"] else ""))

    def on_register(self, *_):
        entry = Gtk.Entry(placeholder_text="por ejemplo 8.2.12")
        dlg_ok = confirm(self.win, "Registrar el XAMPP de /opt/lampp",
                         "Pasa a /opt/lampp-<nombre> y comparte htdocs y los vhosts con las demás. "
                         "Nombre de la versión:",
                         "Registrar el XAMPP", extra=entry)
        name = entry.get_text().strip()
        if not dlg_ok or not name:
            return
        if not re.match(r"^[0-9A-Za-z._-]+$", name):
            message(self.win, "Nombre no válido", "Usa solo números, letras, puntos y guiones.")
            return
        self.run_task("Registrando lampp-%s" % name, ["add", name],
                      done_text="XAMPP registrado como lampp-%s" % name)

    def on_create_launcher(self, *_):
        def done(rc, out):
            self.toast("Icono creado en el menú de aplicaciones" if rc == 0 else
                       "No se ha podido crear el icono")
            self.reload()
            return False
        run_quick(["gui-crear-acceso"], done)

    # ------------------------------------------------------------ instalar
    def build_install(self):
        clear(self.inst_box)
        self.checks = {}
        if self.branches_error:
            box, lb = group("Instalar nuevas versiones de PHP")
            row = ActionRow("No se han podido consultar las versiones", self.branches_error)
            row.add_prefix(css(icon("dialog-warning-symbolic"), "error"))
            b = Gtk.Button(label="Reintentar")
            b.connect("clicked", self.on_refresh)
            row.add_suffix(b)
            lb.add(row)
            self.inst_box.pack_start(box, False, False, 0)
            self.inst_box.show_all()
            return

        nuevas = sum(1 for f in self.branches if f[0] == "B" and (f + [""] * 8)[6] == "nueva")
        box, lb = fold_group("Instalar nuevas versiones de PHP",
                        "Pulsa el título para plegar o desplegar la lista. "
                        "Cada versión lleva su propio Apache, MariaDB, ProFTPD y Perl, "
                        "compilados para ella, y sus propias BBDD. Según php.net: "
                        "Estable recibe correcciones de errores y de seguridad (la mejor opción "
                        "para proyectos nuevos), Solo seguridad recibe únicamente parches de "
                        "seguridad hasta la fecha indicada y Sin soporte ya no recibe parches.",
                        "instalar" not in self.folded, lambda on: self.remember_fold("instalar", on),
                        plural(nuevas, "versión nueva", "versiones nuevas") if nuevas else "")
        rows = sorted((f for f in self.branches if f[0] == "B"),
                      key=lambda f: [int(x) for x in f[1].split(".")], reverse=True)
        for f in rows:
            _, branch, latest, sup, maria, perl, state, folder = (f + [""] * 8)[:8]
            stack = "Apache 2.4  ·  MariaDB %s  ·  Perl %s" % (maria, perl)
            date, sec = branch_release(f)
            if state == "nueva":
                r = ActionRow("PHP %s" % latest, "%s  ·  → /opt/lampp-%s" % (stack, folder),
                              activatable=True)
                chk = Gtk.CheckButton()
                chk.connect("toggled", self.on_check)
                r.add_prefix(chk)
                r.on_activate = chk.activate
                self.checks["php:" + latest] = (chk, latest)
            else:
                sub = {"instalada": "Ya instalada en /opt/lampp-%s" % folder,
                       "actualizable": "lampp-%s tiene un parche anterior: usa Actualizar en "
                                       "Instaladas" % folder,
                       "existe": "Ya existe /opt/lampp-%s" % folder}.get(state, state)
                r = ActionRow("PHP %s" % latest, sub)
                r.add_prefix(icon("object-select-symbolic" if state == "instalada"
                                  else "dialog-information-symbolic"))
                r.set_sensitive(False)
            # Junto a la versión, la fecha en que se publicó y si es un parche de seguridad
            if date and date != "-":
                r.add_title_tag(label(fmt_day(date), "dim-label", "fecha-version"))
                r.add_title_tag(release_tag(sec))
            st, active_end, security_end = branch_state(f)
            r.add_suffix(state_pill(st, active_end, security_end))
            if st == "security" and security_end:
                r.subtitle.set_label(r.subtitle.get_label()
                                     + "  ·  seguridad hasta %s" % fmt_month(security_end))
            lb.add(r)
        self.inst_box.pack_start(box, False, False, 0)

        box, lb = group("Otras opciones")
        other = ActionRow("Otro parche concreto…",
                          "Una versión anterior de cualquier rama, en su propia carpeta",
                          activatable=True)
        other.add_suffix(icon("go-next-symbolic"))
        other.on_activate = self.on_pick_patch
        lb.add(other)
        for version in self.extra_patches:
            r = ActionRow("PHP %s" % version, "Parche concreto  ·  → /opt/lampp-%s" % version)
            chk = Gtk.CheckButton(active=True)
            chk.connect("toggled", self.on_check)
            r.add_prefix(chk)
            rm = Gtk.Button(tooltip_text="Quitar de la lista", relief=Gtk.ReliefStyle.NONE)
            rm.add(icon("window-close-symbolic"))
            rm.connect("clicked", self.on_drop_patch, version)
            r.add_suffix(rm)
            self.checks["parche:" + version] = (chk, version)
            lb.add(r)
        xampps = [f for f in self.branches if f[0] == "X"]
        if xampps:
            xexp = ExpanderRow("XAMPP oficiales", "Para proyectos antiguos (PHP 7.1 a 8.1). Sin parche posible "
                               "de PHP2Shell: mejor una pila propia",
                               on_toggle=lambda on: self.remember("@xampp", on))
            for f in xampps:
                _, folder, release, php, installed = (f + [""] * 5)[:5]
                if installed == "1":
                    xr = ActionRow("XAMPP %s" % release, "Ya instalado en /opt/lampp-%s" % folder)
                    xr.set_sensitive(False)
                else:
                    xr = ActionRow("XAMPP %s" % release,
                                   "PHP %s  ·  → /opt/lampp-%s  ·  sin parche posible (PHP2Shell)" % (php, folder),
                                   activatable=True)
                    chk = Gtk.CheckButton()
                    chk.connect("toggled", self.on_check)
                    xr.add_prefix(chk)
                    xr.on_activate = chk.activate
                    self.checks["xampp:" + folder] = (chk, folder)
                xexp.add_row(xr)
            if "@xampp" in self.expanded:
                xexp.set_expanded(True)
            lb.add(xexp)
        self.inst_box.pack_start(box, False, False, 0)

        self.install_btn = css(Gtk.Button(halign=Gtk.Align.CENTER), "verde", "pildora")
        self.install_btn.connect("clicked", self.on_install)
        self.inst_box.pack_start(self.install_btn, False, False, 0)
        self.inst_box.show_all()
        self.on_check()

    def selected(self):
        return [key for key, (chk, _v) in self.checks.items() if chk.get_active()]

    def on_check(self, *_):
        n = len(self.selected())
        self.install_btn.set_sensitive(n > 0)
        self.install_btn.set_label("Marca una o más versiones" if n == 0 else
                                   "Instalar %s" % plural(n, "versión", "versiones"))

    def on_drop_patch(self, _btn, version):
        self.extra_patches.remove(version)
        self.build_install()

    def on_pick_patch(self):
        branch_rows = {f[1]: f for f in self.branches if f[0] == "B"}
        branches = sorted(branch_rows, key=lambda b: [int(x) for x in b.split(".")], reverse=True)
        state_names = {"stable": "estable", "security": "solo seguridad", "eol": "sin soporte"}
        dlg = Gtk.Dialog(title="Otro parche de PHP", transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(620, 540)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        add = css(dlg.add_button("Añadir", Gtk.ResponseType.OK), "verde")
        add.set_sensitive(False)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=16)
        combo = Gtk.ComboBoxText()
        for b in branches:
            combo.append(b, "PHP %s  (%s)" % (b, state_names.get(branch_state(branch_rows[b])[0], "")))
        top = Gtk.Box(spacing=10)
        top.pack_start(label("Rama:"), False, False, 0)
        top.pack_start(combo, False, False, 0)
        box.pack_start(top, False, False, 0)
        sw = Gtk.ScrolledWindow(vexpand=True)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE,
                             activate_on_single_click=False), "caja")
        sw.add(lb)
        box.pack_start(sw, True, True, 0)
        status = label("", "dim-label")
        box.pack_start(status, False, False, 0)
        box.pack_start(label("Las versiones publicadas en php.net son todas definitivas, pero los "
                             "parches anteriores al último no tienen sus correcciones de "
                             "seguridad: úsalos solo si un proyecto necesita esa versión.",
                             "dim-label", wrap=True, max_width_chars=50), False, False, 0)
        dlg.get_content_area().add(box)
        chosen = {}

        def on_select(_lb, row):
            chosen["v"] = getattr(row, "version", None) if row else None
            add.set_sensitive(bool(chosen.get("v")))
        lb.connect("row-selected", on_select)
        lb.connect("row-activated", lambda _lb, row: getattr(row, "version", None)
                   and dlg.response(Gtk.ResponseType.OK))

        def loaded(rc, out, branch):
            if combo.get_active_id() != branch:
                return False
            clear(lb)
            rows = [f for f in parse_lines(out) if f[0] == "P"]
            if rc != 0 or not rows:
                status.set_label("No se ha podido consultar php.net.")
                return False
            st = branch_state(branch_rows[branch])
            status.set_label("PHP %s: %s" % (branch, {
                "stable": "estable, con correcciones de errores y de seguridad",
                "security": "solo parches de seguridad" + (" hasta %s" % fmt_month(st[2]) if st[2] else ""),
            }.get(st[0], "sin soporte de php.net")))
            for i, f in enumerate(rows):
                _, version, date, folder, state, sec = (f + [""] * 6)[:6]
                if state == "nueva" and version not in self.extra_patches:
                    r = ActionRow("PHP %s" % version, "→ /opt/lampp-%s" % folder)
                    r.version = version if folder == version else None
                    # ActionRow no se puede seleccionar por defecto: estas filas si (y con
                    # doble clic o Intro se añade directamente)
                    r.set_selectable(bool(r.version))
                    r.set_activatable(bool(r.version))
                    if folder != version:
                        # El ultimo parche de la rama va en lampp-X.Y: se marca en la lista principal
                        r.subtitle.set_label("Es la última: márcala en la lista principal")
                        r.set_sensitive(False)
                else:
                    r = ActionRow("PHP %s" % version, "%s" % (
                        "Ya instalada" if state == "instalada" else
                        "Ya en la lista" if version in self.extra_patches else
                        "Ya existe /opt/lampp-%s" % folder))
                    r.version = None
                    r.set_sensitive(False)
                if date and date != "-":
                    r.add_title_tag(label(fmt_day(date), "dim-label", "fecha-version"))
                r.add_title_tag(release_tag(sec))
                if i == 0:
                    r.add_suffix(label("Último", "pastilla", "estable" if st[0] != "eol" else "soporte-no"))
                lb.add(r)
            lb.show_all()
            return False

        def on_branch(*_):
            branch = combo.get_active_id()
            clear(lb)
            add.set_sensitive(False)
            status.set_label("Consultando los parches de PHP %s…" % branch)
            run_quick(["gui-parches", branch], lambda rc, out: loaded(rc, out, branch))
        combo.connect("changed", on_branch)
        dlg.show_all()
        if branches:
            combo.set_active(0)
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp == Gtk.ResponseType.OK and chosen.get("v"):
            self.extra_patches.append(chosen["v"])
            self.build_install()

    def on_install(self, *_):
        sel = self.selected()
        if not sel:
            return
        php = [self.checks[k][1] for k in sel if not k.startswith("xampp:")]
        xampp = [self.checks[k][1] for k in sel if k.startswith("xampp:")]
        names = ["XAMPP %s" % x for x in xampp] + ["PHP %s" % v for v in php]
        text = "Cada PHP se compila aquí (unos minutos). Las versiones instaladas no se tocan."
        if not confirm(self.win, "¿Instalar %s?" % plural(len(names), "versión", "versiones"),
                       text, "Instalar %s" % (names[0] if len(names) == 1 else plural(len(names), "versión", "versiones")),
                       steps=["Se instala %s." % n for n in names]):
            return
        args = ["instalar"]
        if xampp:
            args += ["--xampp", ",".join(xampp)]
        if php:
            args += ["--php", ",".join(php)]
        args.append("--si")
        installed = [k for k in sel]

        def done(ok, task, p):
            if not p:
                return
            good = [item for item, rc in p["results"] if rc == "0"]
            for k in installed:
                if k.startswith("parche:") and any(g.endswith(k.split(":", 1)[1]) for g in good):
                    self.extra_patches = [v for v in self.extra_patches
                                          if v != k.split(":", 1)[1]]
            if len(good) == 1 and not SIMULATE:
                folder = item_folder(good[0])
                task.offer("Activar lampp-%s" % folder,
                           lambda: self.on_activate_version(None, folder))

        self.run_task("Instalando", args, progress=True, reload_branches=True, on_done=done,
                      done_text="Instalación terminada")

    # ------------------------------------------------------- bases de datos
    def build_databases(self):
        # El buscador no se redibuja (si no, se perderia lo escrito y el foco al refrescar)
        if getattr(self, "db_dyn", None) is None or self.db_dyn.get_parent() is None:
            clear(self.db_box)
            self.db_box.pack_start(self.build_db_search(), False, False, 0)
            self.db_dyn = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
            self.db_box.pack_start(self.db_dyn, False, False, 0)
        clear(self.db_dyn)
        d = self.data
        box, lb = group("BBDD por versión",
                        "Cada versión tiene su propio MariaDB. No se muestran las BBDD del "
                        "sistema (mysql, phpmyadmin…).")
        if not d["installs"]:
            lb.add(ActionRow("No hay ninguna versión instalada"))
        for inst in d["installs"]:
            folder = inst["folder"]
            dbs = d["dbs"].get(folder, [])
            sub = "MariaDB %s  ·  %s" % (inst["mariadb"], plural(len(dbs), "BBDD",
                                                                 "BBDD"))
            if inst["owner"] != folder:
                sub += "  ·  las de lampp-%s" % inst["owner"]
            exp = ExpanderRow("lampp-%s" % folder, sub,
                              on_toggle=lambda on, f=folder: self.remember("@db" + f, on))
            active = folder == d["active"]
            if active:
                exp.add_title_tag(label("Activa", "texto-activa"))
                pma = Gtk.Button(label="Abrir phpMyAdmin", sensitive=d["running"],
                                 tooltip_text=None if d["running"] else
                                 "La versión activa está parada")
                pma.connect("clicked", lambda *_: self.open_uri("http://127.0.0.1/phpmyadmin/"))
                exp.add_suffix(pma)
                row = ActionRow("Crear BBDD…")
                row.add_prefix(icon("list-add-symbolic"))
                row.set_activatable(True)
                row.on_activate = self.on_create_db
                exp.add_row(row)
            elif not dbs:
                exp.add_row(ActionRow("Sin BBDD propias"))
            # En la activa, punto verde en la BBDD que usa el proyecto cargado
            used = self.loaded_project_db() if active else ""
            for db in dbs:
                row = ActionRow(db, db_date_text(*d["dbdate"].get((folder, db), (0, ""))))
                if active:
                    dot = label("●", "punto-verde")
                    if db == used:
                        x = self.loaded_project_entry()
                        dot.set_tooltip_text("La usa el proyecto cargado%s"
                                             % (" (%s)" % x["name"] if x else ""))
                    else:
                        # (invisible: así los nombres quedan alineados)
                        dot.set_opacity(0)
                    row.add_prefix(dot)
                if d["dbdate"].get((folder, db), (0, ""))[1] == "c":
                    row.subtitle.set_tooltip_text(DB_DATE_HELP)
                if is_ps_db(db):
                    row.add_suffix(self.cache_button(db))
                copy = self.copy_button(db, inst)
                if copy:
                    row.add_suffix(copy)
                row.add_suffix(self.download_button(db, folder))
                if active:
                    b = Gtk.Button(tooltip_text="Borrar la BBDD %s" % db,
                                   relief=Gtk.ReliefStyle.NONE)
                    b.add(icon("user-trash-symbolic"))
                    b.connect("clicked", lambda _b, n=db: self.on_drop_db(n))
                    row.add_suffix(b)
                exp.add_row(row)
            if "@db" + folder in self.expanded:
                exp.set_expanded(True)
            lb.add(exp)
        self.db_dyn.pack_start(box, False, False, 0)
        self.db_dyn.pack_start(self.build_import(), False, False, 0)
        self.db_box.show_all()
        self.update_db_search()

    def cache_button(self, db):
        """Vaciar var/cache de la tienda PrestaShop de la base (la carpeta la busca el script)."""
        b = Gtk.Button(tooltip_text="Vaciar la caché de %s" % db,
                       relief=Gtk.ReliefStyle.NONE, sensitive=not self.busy)
        b.add(icon("edit-clear-all-symbolic"))
        b.connect("clicked", lambda *_: self.run_task(
            "Vaciando la caché de la tienda de %s" % db, ["vaciar-cache", "--bd", db],
            done_text="Caché vaciada", auto_close=True))
        return b

    def copy_targets(self, db, inst):
        """Versiones a las que se puede copiar la base: las que no comparten las bases con la de
        origen. Las que ya la tienen también (se sustituye, con copia antes)."""
        return [i for i in self.installs() if i["owner"] != inst["owner"]]

    def has_db(self, folder, db):
        return db in self.data["dbs"].get(folder, [])

    def copy_button(self, db, inst):
        """Copiar la base a otra versión de PHP que no la tenga (para probar el proyecto con ella)."""
        if not self.copy_targets(db, inst):
            return None
        b = Gtk.Button(tooltip_text="Copiar %s a otra versión de PHP" % db,
                       relief=Gtk.ReliefStyle.NONE, sensitive=not self.busy)
        b.add(icon("edit-copy-symbolic"))
        b.connect("clicked", lambda *_: self.on_copy_db(db, inst))
        return b

    def on_copy_db(self, db, inst):
        """Copia la BBDD, con el mismo nombre, de la versión pulsada a otra. Siempre se avisa
        antes. (Copiarla con otro nombre o con otra carpeta: Replicar, en Cargar proyecto.)"""
        targets = self.copy_targets(db, inst)
        if not targets:
            return
        dlg = Gtk.Dialog(title="Copiar BBDD", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(520, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Copiar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        box.pack_start(css(label("¿A qué versión de PHP copias %s?" % db, wrap=True,
                                 max_width_chars=60), "title-3"), False, False, 0)
        box.pack_start(label("Se copia con el mismo nombre desde lampp-%s, que no se toca. Para "
                             "copiarla con otro nombre o con otra carpeta de proyecto, usa Replicar "
                             "(Versiones, Cargar proyecto)." % inst["folder"],
                             "dim-label", wrap=True, max_width_chars=60), False, False, 0)
        first, radios = None, []
        # (primero las que no la tienen; dentro, de la más nueva a la más antigua)
        for i in sorted(targets, key=lambda i: (not self.has_db(i["folder"], db), ver_tuple(i["php"])),
                        reverse=True):
            rb = Gtk.RadioButton.new_from_widget(first)
            rb.add(label("PHP %s  (lampp-%s)%s%s" % (
                i["php"], i["folder"], "  ·  la activa" if i["folder"] == self.data["active"] else "",
                "  ·  ya la tiene: se sustituye" if self.has_db(i["folder"], db) else "")))
            first = first or rb
            opt = css(Gtk.Box(), "opcion")
            opt.pack_start(rb, True, True, 0)
            rb.connect("toggled", lambda b, o=opt: (o.get_style_context().add_class("elegida")
                                                     if b.get_active() else
                                                     o.get_style_context().remove_class("elegida")))
            if rb is first:
                css(opt, "elegida")
            radios.append((rb, i))
            box.pack_start(opt, False, False, 0)
        box.show_all()
        resp = run_dialog(dlg)
        chosen = next((i for rb, i in radios if rb.get_active()), None)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT or chosen is None:
            return
        args = ["copiar-bd", db, inst["folder"], chosen["folder"]]
        dst = chosen["folder"]
        notes = ["Se copia %s de lampp-%s (PHP %s) a lampp-%s (PHP %s), con el mismo nombre. "
                 "La de lampp-%s no se toca." % (db, inst["folder"], inst["php"], dst, chosen["php"],
                                                 inst["folder"])]
        if dst != self.data["active"]:
            notes.append("lampp-%s no es la activa: se arranca su MariaDB solo para la copia y se "
                         "pide la contraseña de administrador." % dst)
        replace = self.has_db(dst, db)
        if replace:
            notes.append("lampp-%s ya tiene una BBDD %s: se guarda antes una copia suya en "
                         "~/lvm-copias y después se pone en su lugar la de lampp-%s. Lo que tuviera "
                         "se pierde (salvo en esa copia)." % (dst, db, inst["folder"]))
            args.append("--sustituir")
        if not confirm(self.win, "¿Sustituir %s en lampp-%s?" % (db, dst) if replace else
                       "¿Copiar %s a lampp-%s?" % (db, dst), "",
                       ("Sustituir en lampp-%s" if replace else "Copiar a lampp-%s") % dst, destructive=replace,
                       steps=notes):
            return
        self.run_task("Copiando %s a lampp-%s" % (db, dst), args,
                      done_text="%s copiada a lampp-%s" % (db, dst), auto_close=True)

    def on_replicate(self, project=None):
        """Replicar un proyecto en otra versión de PHP: copia su BBDD de una versión a otra con el
        nombre que se elija (se propone el de la versión de destino: wp_x_8_4 → wp_x_8_5) y la
        vincula allí a la carpeta que se elija (la misma, otra o ninguna)."""
        if not self.data or not self.projects or self.busy:
            return
        projects = [x for x in self.projects["list"] if self.project_pairs(x)]
        if not projects:
            message(self.win, "No hay proyectos que replicar",
                    "Ningún proyecto de /opt/htdocs tiene su BBDD en una versión instalada.",
                    Gtk.MessageType.INFO)
            return
        if len({i["owner"] for i in self.installs()}) < 2:
            message(self.win, "No hay otra versión de PHP",
                    "Instala otra versión de PHP (con sus propias BBDD) para replicar un proyecto en ella.",
                    Gtk.MessageType.INFO)
            return
        # (el de la fila desde la que se pide o, si no, el cargado)
        loaded = project or self.loaded_project_entry()
        dlg = Gtk.Dialog(title="Replicar proyecto", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(600, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Replicar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        box.pack_start(css(label("Replicar un proyecto en otra versión de PHP", wrap=True,
                                 max_width_chars=60), "title-3"), False, False, 0)
        box.pack_start(label("Se copia su BBDD a la otra versión, con el nombre que elijas, y allí "
                             "queda vinculada a la carpeta que elijas: después, Cargar proyecto lo "
                             "monta con esa versión. La versión de origen no se toca.",
                             "dim-label", wrap=True, max_width_chars=60), False, False, 0)
        grid = Gtk.Grid(column_spacing=12, row_spacing=10, margin_top=8)
        box.pack_start(grid, False, False, 0)

        def field(n, text, widget):
            grid.attach(label(text, "dim-label"), 0, n, 1, 1)
            widget.set_hexpand(True)
            grid.attach(widget, 1, n, 1, 1)
            return widget
        pcombo = field(0, "Proyecto", Gtk.ComboBoxText())
        for x in projects:
            pcombo.append(x["name"], x["name"])
        scombo = field(1, "Desde", Gtk.ComboBoxText())
        tcombo = field(2, "A la versión", Gtk.ComboBoxText())
        entry = field(3, "Nombre de la BBDD", Gtk.Entry(max_length=64, activates_default=True))
        hint = label("", "dim-label", "subtitulo", wrap=True, max_width_chars=50)
        grid.attach(hint, 1, 4, 1, 1)
        fcombo = field(5, "Carpeta", Gtk.ComboBoxText())
        fcombo.append("@ninguna", "— Ninguna: vincúlala después —")
        for f in project_folders():
            fcombo.append(f, f)
        grid.attach(label("La carpeta del proyecto con la que se cargará en esa versión (si tiene "
                          "una propia para ella, elígela).", "dim-label", "subtitulo", wrap=True,
                          max_width_chars=50), 1, 6, 1, 1)
        for c in (pcombo, scombo, tcombo, fcombo):
            narrow(c, 40)
        state = {"auto": True, "set": False, "pairs": [], "targets": []}

        def source():
            n = scombo.get_active()
            return state["pairs"][n] if 0 <= n < len(state["pairs"]) else None

        def target():
            n = tcombo.get_active()
            return state["targets"][n] if 0 <= n < len(state["targets"]) else None

        def update(*_):
            t, name = target(), entry.get_text().strip()
            valid = bool(re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_-]{0,63}", name)) and \
                name.lower() not in ("information_schema", "mysql", "performance_schema",
                                     "phpmyadmin", "sys", "test")
            if not valid:
                hint.set_label("Letras sin acentos, números, _ y - (sin - delante).")
            elif t and self.has_db(t["folder"], name):
                hint.set_markup('<span foreground="#e01b24">lampp-%s ya tiene una BBDD %s: se '
                                'sustituye (antes se guarda una copia suya en ~/lvm-copias).</span>'
                                % (t["folder"], GLib.markup_escape_text(name)))
            else:
                hint.set_label("Se crea %s en lampp-%s." % (name, t["folder"]) if t else "")
            ok.set_sensitive(valid and t is not None and source() is not None)

        def on_target(*_):
            # (mientras no se escriba otro, el nombre sigue a la versión elegida)
            s, t = source(), target()
            if s and t and state["auto"]:
                state["set"] = True
                entry.set_text(copy_name(s[1], t["php"]))
                state["set"] = False
            update()

        def on_source(*_):
            s = source()
            tcombo.remove_all()
            state["targets"] = sorted((i for i in self.installs() if s and i["owner"] != s[0]["owner"]),
                                      key=lambda i: ver_tuple(i["php"]), reverse=True)
            for i in state["targets"]:
                tcombo.append(i["folder"], "PHP %s  (lampp-%s)" % (i["php"], i["folder"]))
            tcombo.set_active(0 if state["targets"] else -1)
            on_target()

        def on_project(*_):
            x = next((p for p in projects if p["name"] == pcombo.get_active_id()), None)
            scombo.remove_all()
            state["pairs"] = sorted(self.project_pairs(x), key=lambda c: ver_tuple(c[0]["php"]),
                                    reverse=True) if x else []
            for i, d in state["pairs"]:
                scombo.append(None, "PHP %s  (lampp-%s)  ·  BBDD %s" % (i["php"], i["folder"], d))
            # (la de la versión activa, si la tiene)
            act = next((n for n, (i, _) in enumerate(state["pairs"])
                        if i["folder"] == self.data["active"]), 0)
            scombo.set_active(act if state["pairs"] else -1)
            if x:
                fcombo.set_active_id(x["name"])
            on_source()

        def edited(*_):
            if not state["set"]:
                state["auto"] = False
            update()
        pcombo.connect("changed", on_project)
        scombo.connect("changed", on_source)
        tcombo.connect("changed", on_target)
        entry.connect("changed", edited)
        pcombo.set_active_id(loaded["name"] if loaded and loaded in projects else projects[0]["name"])
        box.show_all()
        resp = run_dialog(dlg)
        s, t, name, folder = source(), target(), entry.get_text().strip(), fcombo.get_active_id()
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT or not s or not t or not name:
            return
        (src, db), dst = s, t["folder"]
        folder = None if folder in (None, "@ninguna") else folder
        args = ["copiar-bd", db, src["folder"], dst, "--como", name, "--carpeta", folder or "-"]
        notes = ["Se copia %s de lampp-%s (PHP %s) a lampp-%s (PHP %s) como %s, y allí queda "
                 "vinculada a %s." % (db, src["folder"], src["php"], dst, t["php"], name,
                                       folder or "ninguna carpeta")]
        if dst != self.data["active"]:
            notes.append("lampp-%s no es la activa: se arranca su MariaDB solo para la copia y se "
                         "pide la contraseña de administrador." % dst)
        replace = self.has_db(dst, name)
        if replace:
            notes.append("lampp-%s ya tiene una BBDD %s: se guarda antes una copia suya en "
                         "~/lvm-copias y se pone en su lugar. Lo que tuviera se pierde (salvo en esa "
                         "copia)." % (dst, name))
            args.append("--sustituir")
        if not confirm(self.win, "¿Replicar en lampp-%s?" % dst, "",
                       ("Sustituir en lampp-%s" if replace else "Replicar en lampp-%s") % dst, destructive=replace,
                       steps=notes):
            return
        self.run_task("Replicando en lampp-%s" % dst, args,
                      done_text="%s replicada en lampp-%s como %s" % (db, dst, name), auto_close=True)

    def download_button(self, db, folder):
        b = Gtk.Button(tooltip_text="Descargar una copia de %s (.zip)" % db,
                       relief=Gtk.ReliefStyle.NONE)
        b.add(icon("document-save-symbolic"))
        b.connect("clicked", lambda *_: self.on_download_db(db, folder))
        return b

    # ------------------------------------------------------ buscador de bases
    def build_db_search(self):
        box, lb = group("Buscar una BBDD",
                        "Escribe parte del nombre para ver en qué versión está y qué PHP "
                        "tienes que activar para trabajar con ella.")
        self.db_entry = Gtk.SearchEntry(placeholder_text="Nombre de la BBDD…",
                                        margin_top=6)
        self.db_entry.connect("search-changed", lambda *_: self.update_db_search())
        self.db_entry.connect("stop-search", lambda e: e.set_text(""))
        box.pack_start(self.db_entry, False, False, 0)
        box.reorder_child(self.db_entry, len(box.get_children()) - 2)
        self.db_found = label("", "dim-label", "subtitulo")
        self.db_found.set_no_show_all(True)
        box.pack_start(self.db_found, False, False, 0)
        box.reorder_child(self.db_found, len(box.get_children()) - 2)
        lb.set_no_show_all(True)
        self.db_results = lb
        return box

    def db_installs(self, db, skip_owner=None):
        """Versiones en las que está la base (sin repetir las que comparten bases)."""
        return [i for i in self.installs() if db in self.data["dbs"].get(i["folder"], [])
                and i["owner"] != skip_owner]

    def update_db_search(self):
        if getattr(self, "db_results", None) is None or not self.data:
            return
        lb, q = self.db_results, self.db_entry.get_text().strip().lower()
        clear(lb)
        if not q:
            lb.hide()
            self.db_found.hide()
            return
        hits = [(db, inst) for inst in self.installs()
                for db in self.data["dbs"].get(inst["folder"], []) if q in db.lower()]
        # Primero la coincidencia exacta, luego las que empiezan igual; la activa delante
        hits.sort(key=lambda h: (h[0].lower() != q, not h[0].lower().startswith(q),
                                 h[0].lower(), h[1]["folder"] != self.data["active"]))
        names = len({h[0] for h in hits})
        if hits:
            self.db_found.set_label("%s en %s" % (
                plural(names, "BBDD", "BBDD"),
                plural(len({h[1]["folder"] for h in hits}), "versión", "versiones")))
        else:
            self.db_found.set_label("Ninguna versión tiene una BBDD con «%s» en el "
                                    "nombre." % q)
        self.db_found.show()
        if not hits:
            lb.hide()
            return
        limit = 40
        for db, inst in hits[:limit]:
            lb.add(self.db_hit_row(db, inst, q))
        if len(hits) > limit:
            lb.add(ActionRow("Y %d más…" % (len(hits) - limit),
                             "Escribe más letras del nombre para encontrarla."))
        # no_show_all (para que no aparezca vacía) hace que show_all no la toque: fila a fila
        for row in lb.get_children():
            row.show_all()
        lb.show()

    def db_hit_row(self, db, inst, q):
        folder = inst["folder"]
        row = ActionRow(db)
        start = db.lower().find(q)
        esc = GLib.markup_escape_text
        row.title.set_markup("%s<b>%s</b>%s" % (esc(db[:start]), esc(db[start:start + len(q)]),
                                                esc(db[start + len(q):])))
        sub = "lampp-%s  ·  PHP %s  ·  MariaDB %s" % (folder, inst["php"], inst["mariadb"])
        if inst["owner"] != folder:
            sub += "  ·  las de lampp-%s" % inst["owner"]
        when, kind = self.data["dbdate"].get((folder, db), (0, ""))
        if when:
            sub += "\n" + db_date_text(when, kind)
            if kind == "c":
                row.subtitle.set_tooltip_text(DB_DATE_HELP)
        row.subtitle.set_label(sub)
        row.subtitle.set_no_show_all(False)
        if is_ps_db(db):
            row.add_suffix(self.cache_button(db))
        row.add_suffix(self.download_button(db, folder))
        # Punto verde: su version de PHP es la activa
        active = folder == self.data["active"]
        dot = label("●", "punto-verde" if active else "punto-gris")
        dot.set_tooltip_text("Su versión de PHP está activa" if active else
                             "Su versión de PHP no está activa")
        row.add_prefix(dot)
        if active:
            b = Gtk.Button(label="Elegir como destino",
                           tooltip_text="Elegirla para subir una BBDD")
            b.connect("clicked", lambda *_: self.use_as_destination(db))
            row.add_suffix(b)
        load = Gtk.Button(label="Cargar proyecto", sensitive=not self.busy,
                          tooltip_text="Cargar en lampp-%s (PHP %s)"
                                       % (folder, inst["php"]))
        load.connect("clicked", lambda *_: self.on_load_project(db, inst))
        row.add_suffix(load)
        return row

    def use_as_destination(self, db):
        self.imp.update(db=db)
        self.build_databases()
        self.toast("BBDD de destino: %s" % db)
        # Baja hasta el formulario de carga
        GLib.idle_add(lambda: (self.imp_btn.grab_focus(), False)[1])

    # ------------------------------------------------- cargar el proyecto de una base
    def on_load_project(self, db, inst):
        def got(rc, out):
            link, current, projects, saved, create = "", "", [], {}, False
            vlinks = {}
            for f in parse_lines(out):
                if f[0] == "E" and len(f) >= 3:
                    link, current = f[1], f[2]
                    create = len(f) >= 4 and f[3] == "N"
                elif f[0] == "P" and len(f) >= 4:
                    projects.append({"name": f[1], "db": f[2], "php": f[3]})
                elif f[0] == "R" and len(f) >= 3:
                    saved[f[1]] = f[2]
                elif f[0] == "V" and len(f) >= 4:
                    vlinks[(f[1], f[2])] = f[3]
            # (el vínculo de la versión manda sobre el de todas; "" = desvinculada en ella)
            if (db, inst["folder"]) in vlinks:
                saved[db] = vlinks[(db, inst["folder"])]
            if rc != 0 or not projects:
                message(self.win, "No se han podido leer los proyectos",
                        "No se ha podido leer la carpeta /opt/htdocs.", Gtk.MessageType.WARNING)
            elif not link:
                message(self.win, "No hay un vhost para cargar proyectos",
                        "Ningún vhost de /opt/config/httpd-vhosts.conf tiene como DocumentRoot "
                        "un enlace de /opt/htdocs (como web.local).", Gtk.MessageType.WARNING)
            else:
                self.project_dialog(db, inst, link, current, projects, saved, create)
            return False
        run_quick(["gui-proyectos"], got)

    def project_dialog(self, db, inst, link, current, projects, saved, create=False):
        """Carga el proyecto de la base en la versión del resultado pulsado (inst). Si la carpeta
        se sabe (elegida antes o la única cuya configuración usa la base), sin preguntar; si no,
        se elige de una lista. Solo avisa cuando hay que cambiar de versión o crear el vhost."""
        by_name = {p["name"]: p for p in projects}
        matches = [p["name"] for p in projects if p["db"] == db]
        folder, manual = None, False
        if saved.get(db) in by_name:
            folder = saved[db]
        elif len(matches) == 1 and saved.get(db) != "":
            folder = matches[0]
        else:
            folder = self.pick_project_folder(db, projects, matches)
            manual = True
        if not folder:
            return
        self.do_load_project(folder, db, inst, link, create, remember=manual)

    def do_load_project(self, folder, db, inst, link, create, confirm_switch=True, remember=False):
        """Carga una carpeta en una versión. Avisa cuando hay que cambiar de versión (si no se
        acaba de elegir) o crear el vhost."""
        target = inst["folder"]
        act = next((i for i in self.installs() if i["folder"] == self.data["active"]), None)
        where = (", donde está la BBDD %s" % db) if db and db in self.data["dbs"].get(target, []) \
            else ""
        notes = []
        if target != self.data["active"] and confirm_switch:
            if act:
                notes.append("Se va a cambiar de versión de PHP: se para lampp-%s (PHP %s) y se "
                             "activa lampp-%s (PHP %s)%s."
                             % (act["folder"], act["php"], target, inst["php"], where))
            else:
                notes.append("Se activa lampp-%s (PHP %s)%s." % (target, inst["php"], where))
        if create:
            notes.append("Todavía no hay un vhost para cargar proyectos: se crea %s (http y "
                         "https, con su certificado y su línea en /etc/hosts)." % link)
        if notes:
            title = "¿Cambiar a PHP %s?" % inst["php"] if target != self.data["active"] \
                and confirm_switch else "¿Crear %s?" % link
            if not confirm(self.win, title, "", "Cargar %s" % folder,
                           steps=notes + ["%s apuntará a %s." % (link, folder)]):
                return
        if remember:
            self.remember_project(db, folder, target)
        def loaded(ok_, *_):
            if not ok_:
                return
            # El visor pasa al proyecto nuevo al momento, con sus botones: lo que se acaba de hacer se
            # sabe sin preguntarlo (gui-datos tarda unos segundos; la lectura completa sigue detrás)
            if self.projects is not None:
                self.projects = dict(self.projects, link=link, current=folder, create=False)
                self.selected_project = folder
            if self.data is not None and target != self.data["active"]:
                self.data = dict(self.data, active=target)
            self.update_project_search()
            # (la página sube sola hasta el visor, arriba: sin desplazarla a mano)
            GLib.timeout_add(120, lambda: smooth_scroll(self.page_projects) and False)

            def got(_rc, out):
                # Tienda PrestaShop: su dominio queda falseado (se ve en la pestaña Hosts)
                fake = [f[1] for f in parse_lines(out)
                        if f[0] == "F" and len(f) >= 9 and f[3] == folder and f[4] == "1"]
                self.on_hosts_data(_rc, out)
                self.toast("Proyecto cargado: %s → %s (PHP %s)%s"
                           % (link, folder, inst["php"],
                              "  ·  %s falseado (pestaña Hosts)" % fake[0] if fake else ""))
                return False
            run_quick(["gui-hosts"], got)
        self.run_task("Cargando el proyecto %s" % folder, ["cargar-proyecto", folder, target, db],
                      done_text="%s apunta a %s (PHP %s)" % (link, folder, inst["php"]),
                      auto_close=True, env=self.db_pwd.get(target) and
                      {"MYSQL_PWD": self.db_pwd[target]}, on_done=loaded)

    def pick_project_folder(self, db, projects, matches):
        """Lista con buscador de las carpetas de htdocs para elegir la del proyecto de una base."""
        dlg = Gtk.Dialog(title="Cargar proyecto", transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.set_default_size(560, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Cargar proyecto", Gtk.ResponseType.ACCEPT), "verde")
        ok.set_sensitive(False)
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        box.pack_start(css(label("Proyecto de %s" % db), "title-3"), False, False, 0)
        if len(matches) > 1:
            why = "Hay %d carpetas que usan «%s». Elige la que quieres cargar:" % (
                len(matches), db)
        else:
            why = ("No hay ninguna carpeta cuya configuración use «%s». Elige la del "
                   "proyecto:" % db)
        box.pack_start(label(why, "dim-label", wrap=True, max_width_chars=60), False, False, 0)
        box.pack_start(label("La elección se recuerda para esta BBDD.", "dim-label",
                             "subtitulo"), False, False, 0)
        find = Gtk.SearchEntry(placeholder_text="Buscar una carpeta de htdocs")
        box.pack_start(find, False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE,
                             activate_on_single_click=False), "caja")
        sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, min_content_height=260)
        sw.add(lb)
        box.pack_start(sw, False, False, 0)
        # Primero las que usan esta base, luego el resto por nombre
        for p in sorted(projects, key=lambda p: (p["db"] != db, p["name"].lower())):
            sub = ("Usa esta BBDD" if p["db"] == db else
                   "BBDD: %s" % p["db"] if p["db"] else "Sin BBDD detectada")
            if p["php"]:
                sub += "  ·  .php-version %s" % p["php"]
            row = ActionRow(p["name"], sub)
            row.set_selectable(True)
            row.set_activatable(True)
            row.name = p["name"]
            lb.add(row)
        lb.set_filter_func(lambda r: find.get_text().strip().lower() in r.name.lower())
        find.connect("search-changed", lambda *_: lb.invalidate_filter())
        lb.connect("row-selected", lambda _lb, row: ok.set_sensitive(row is not None))
        lb.connect("row-activated", lambda *_: dlg.response(Gtk.ResponseType.ACCEPT))
        box.show_all()
        find.grab_focus()
        resp = run_dialog(dlg)
        row = lb.get_selected_row()
        dlg.destroy()
        return row.name if resp == Gtk.ResponseType.ACCEPT and row is not None else None

    def remember_project(self, db, folder, ver):
        """Guarda en ~/.lvm-instalador/proyectos la carpeta elegida a mano para una base en una
        versión."""
        if SIMULATE:
            return
        err = write_links([(db, ver, folder)])
        if err:
            self.toast("No se ha podido recordar la carpeta: %s" % err)

    # ------------------------------------------------------------------ Docker
    def on_docker_data(self, rc, out):
        d = {"installed": False, "ready": False, "version": "", "lampp": False,
             "php": [], "maria": [], "projects": [], "containers": []}
        for f in parse_lines(out):
            if f[0] == "S" and len(f) >= 5:
                d.update(installed=f[1] == "1", ready=f[2] == "1", version=f[3], lampp=f[4] == "1",
                         rootful=len(f) > 5 and f[5] == "1")
            elif f[0] == "V" and len(f) >= 3:
                d["php"], d["maria"] = f[1].split(), f[2].split()
            elif f[0] == "P" and len(f) >= 9 and re.fullmatch(r"[a-z0-9-]{1,40}", f[1]):
                web = len(f) >= 13 and f[9] == "web"
                d["projects"].append({"slug": f[1], "folder": f[2], "php": f[3], "maria": f[4],
                                      "domain": f[5], "state": f[6], "db": f[7], "pma": f[8], "web": web,
                                      "kind": f[11] if web else "", "versions": f[12].split() if web else [f[3]],
                                      "lampp": f[13] if web and len(f) > 13 else ""})
            elif f[0] == "W" and len(f) >= 6:
                d["web"] = {"ip": f[1], "http": f[2], "https": f[3], "state": f[4], "ports_ok": f[5] == "1",
                            "tld": f[6] if len(f) > 6 and f[6] in ("docker.local", "docker.test") else "docker.local",
                            "dns": len(f) > 7 and f[7] == "1"}
                DOCKER_TLD[0] = d["web"]["tld"]
            elif f[0] == "C" and len(f) >= 7:
                d["containers"].append({"name": f[1], "image": f[2], "state": f[3], "status": f[4],
                                        "ports": f[5], "project": f[6], "id": f[7][:12] if len(f) > 7 else ""})
            elif f[0] == "I" and len(f) >= 6:
                d.setdefault("images", []).append({"repo": f[1], "tag": f[2], "id": f[3][:12], "size": f[4],
                                                   "created": f[5]})
            elif f[0] == "O" and len(f) >= 3:
                d.setdefault("volumes", []).append({"name": f[1], "driver": f[2]})
        if d != self.docker:
            self.docker = d
            self.build_docker()
        return False

    def build_docker(self):
        clear(self.docker_box)
        d = self.docker
        if d is None:
            self.loading(self.docker_box, "Comprobando Docker…")
            return
        if d["ready"]:
            self.docker_box.pack_start(self.build_docker_console(), False, False, 0)
        box, lb = group("Docker sin root",
                        "Cada proyecto en Docker va con el PHP que quieras (de la 5.6 a la 8.5), también "
                        "con varias versiones a la vez y la misma BBDD, en una MariaDB común. Docker tiene "
                        "su propio Apache, con las mismas reglas de seguridad y los .htaccess de cada "
                        "proyecto, así que no necesita LAMPP y funcionan a la vez. Docker corre sin root, "
                        "con tu usuario: ni un proyecto ni Docker pueden hacerse administradores del equipo.")
        if not d["installed"]:
            row = ActionRow("Docker no está instalado",
                            "Se instala Docker de Ubuntu en modo sin root (el Docker del sistema, con "
                            "root, se deja apagado). Pide la contraseña de administrador.")
            row.add_prefix(label("●", "punto-gris"))
            b = css(Gtk.Button(label="Instalar Docker", sensitive=not self.busy), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Instalando Docker sin root", ["docker-instalar"], done_text="Docker sin root instalado",
                on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)))
            row.add_suffix(b)
            lb.add(row)
        elif not d["ready"]:
            row = ActionRow("Docker sin root no responde",
                            "Está instalado, pero su servicio (el de tu usuario) no está en marcha o no "
                            "se ha preparado. Prepararlo lo deja listo; no cambia los contenedores.")
            row.add_prefix(label("●", "punto-gris"))
            b = css(Gtk.Button(label="Prepararlo", sensitive=not self.busy), "verde")
            b.connect("clicked", lambda *_: self.run_task(
                "Preparando Docker sin root", ["docker-instalar"], progress=True, done_text="Docker sin root listo",
                on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)))
            row.add_suffix(b)
            lb.add(row)
        else:
            row = ActionRow("Docker %s, sin root" % d["version"], "En marcha con tu usuario")
            row.add_prefix(label("●", "punto-verde"))
            lb.add(row)
            if d.get("rootful"):
                # (lo deja en marcha el paquete de Ubuntu: corre como root y no hace falta)
                row = ActionRow("Hay otro Docker en marcha: el de Ubuntu, como administrador",
                                "Este programa usa el suyo, con tu usuario. El de Ubuntu arranca solo con el equipo, "
                                "no hace falta y quien lo use puede hacerse con el equipo. Apágalo salvo que lo uses "
                                "fuera de este programa (pide la contraseña; tus proyectos no se tocan).")
                row.add_prefix(css(icon("dialog-warning-symbolic"), "error"))
                b = css(Gtk.Button(label="Apagarlo", sensitive=not self.busy), "verde")
                b.connect("clicked", lambda *_: self.run_task(
                    "Apagando el Docker del sistema", ["docker-instalar"], done_text="Docker del sistema apagado",
                    auto_close=True, on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)))
                row.add_suffix(b)
                lb.add(row)
            if not d["lampp"]:
                row = ActionRow("La versión LAMPP activa está parada",
                                "Los proyectos en Docker se abren por su Apache: arráncala en Versiones.")
                row.add_prefix(css(icon("dialog-warning-symbolic"), "error"))
                lb.add(row)
        self.docker_box.pack_start(box, False, False, 0)
        if d["ready"]:
            self.docker_box.pack_start(self.build_docker_projects(), False, False, 0)
            self.docker_box.pack_start(self.build_docker_new(), False, False, 0)
        self.docker_box.show_all()

    def build_docker_projects(self):
        d = self.docker
        box, lb = group("Proyectos en Docker",
                        "Arrancados, siguen en marcha aunque cierres esta ventana. Borrar quita sus "
                        "contenedores y la copia de su BBDD (la carpeta del proyecto y la BBDD de "
                        "LAMPP no se tocan).")
        if not d["projects"]:
            lb.add(ActionRow("Todavía no hay ningún proyecto en Docker", "Créalo abajo."))
        for p in d["projects"]:
            on = p["state"] == "marcha"
            row = ActionRow(p["folder"], "MariaDB %s  ·  https://%s%s" % (
                p["maria"], p["domain"],
                {"parcial": "  ·  a medias", "nuevo": "  ·  sin contenedores"}.get(p["state"], "")))
            dot = label("●", "punto-verde" if on else "punto-gris")
            dot.set_tooltip_text({"marcha": "En marcha", "parado": "Parado",
                                  "parcial": "Algún contenedor está parado"}.get(p["state"], p["state"]))
            row.add_prefix(dot)
            php = Gtk.Button(label="PHP %s" % p["php"], valign=Gtk.Align.CENTER, sensitive=not self.busy,
                             tooltip_text="Cambiar la versión de PHP de %s" % p["folder"])
            php.connect("clicked", lambda *_, p=p: self.on_docker_php(p))
            row.add_suffix(php)
            for ic, tip, fn, ok in [
                    ("web-browser-symbolic", "Abrir https://%s" % p["domain"],
                     lambda *_, p=p: self.open_uri("https://%s/" % p["domain"]), on),
                    ("drive-multidisk-symbolic", "Abrir su phpMyAdmin (http://127.0.0.1:%s/)" % p["pma"],
                     lambda *_, p=p: self.open_uri("http://127.0.0.1:%s/" % p["pma"]),
                     on and p["pma"].isdigit()),
                    ("text-x-generic-symbolic", "Ver los registros de sus contenedores",
                     lambda *_, p=p: self.run_task("Registros de %s" % p["folder"],
                                                   ["docker-registros", p["slug"]]), True),
                    ("media-playback-stop-symbolic" if on else "media-playback-start-symbolic",
                     "Parar sus contenedores" if on else "Arrancar sus contenedores",
                     lambda *_, p=p, on=on: self.run_task(
                         ("Parando %s" if on else "Arrancando %s") % p["folder"],
                         ["docker-parar" if on else "docker-arrancar", p["slug"]],
                         done_text="%s %s" % (p["folder"], "parado" if on else "en marcha"),
                         auto_close=True, on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)),
                     True),
                    ("user-trash-symbolic", "Borrar el proyecto en Docker",
                     lambda *_, p=p: self.on_docker_delete(p), True)]:
                b = Gtk.Button(tooltip_text=tip, relief=Gtk.ReliefStyle.NONE,
                               sensitive=ok and not self.busy)
                b.add(icon(ic))
                b.connect("clicked", fn)
                row.add_suffix(b)
            lb.add(row)
        return box

    def build_docker_console(self):
        """Consola de Docker (arriba de la pestaña, como Docker Desktop): todos los contenedores con su
        imagen, si están en marcha, desde cuándo y sus puertos."""
        d = self.docker
        cons = d.get("containers", [])
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10), "consola-docker")
        head = Gtk.Box(spacing=10)
        head.pack_start(logo("docker", 26), False, False, 0)
        head.pack_start(label("Docker", "consola-titulo"), False, False, 0)
        up = sum(1 for c in cons if c["state"] == "running")
        head.pack_end(label("%d en marcha  ·  %d parados" % (up, len(cons) - up), "consola-tenue"),
                      False, False, 0)
        box.pack_start(head, False, False, 0)
        if not cons:
            box.pack_start(label("$ docker ps\nNo hay contenedores.", "consola-tenue"), False, False, 0)
            return box
        grid = Gtk.Grid(column_spacing=18, row_spacing=4)
        for n, title in enumerate(["", "CONTENEDOR", "IMAGEN", "ESTADO", "PUERTOS"]):
            grid.attach(label(title, "consola-tenue"), n, 0, 1, 1)
        for row, c in enumerate(sorted(cons, key=lambda c: (c["project"], c["name"])), 1):
            on = c["state"] == "running"
            grid.attach(label("●", "consola-verde" if on else "consola-gris"), 0, row, 1, 1)
            # (sin el prefijo del gestor: nexum-<proyecto>-php-1 → <proyecto>-php)
            name = re.sub(r"-\d+$", "", re.sub(r"^nexum-", "", c["name"]))
            n_lbl = label(name, ellipsize=3, max_width_chars=34)
            n_lbl.set_tooltip_text(c["name"])
            grid.attach(n_lbl, 1, row, 1, 1)
            grid.attach(label(c["image"], "consola-tenue", ellipsize=3, max_width_chars=18), 2, row, 1, 1)
            grid.attach(label(docker_status_text(c["status"]), "consola-verde" if on else "consola-gris"),
                        3, row, 1, 1)
            ports = ", ".join(p for p in c["ports"].split(", ") if "->" in p) or "—"
            grid.attach(label(ports.replace("/tcp", ""), "consola-tenue"), 4, row, 1, 1)
        box.pack_start(grid, False, False, 0)
        return box

    def on_docker_php(self, p):
        """Cambiar la versión de PHP de un proyecto en Docker (solo su contenedor de PHP)."""
        versions = self.docker["php"]
        dlg = Gtk.Dialog(title="Cambiar PHP", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(460, -1)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Cambiar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8, margin=24)
        dlg.get_content_area().add(box)
        box.pack_start(css(label("¿Con qué versión de PHP quieres %s?" % p["folder"], wrap=True,
                                 max_width_chars=50), "title-3"), False, False, 0)
        box.pack_start(label("Solo se cambia su contenedor de PHP: su BBDD, su phpMyAdmin y su "
                             "configuración se quedan como están. La primera vez con cada versión se "
                             "prepara su imagen (unos minutos). Si no arranca, vuelve a PHP %s."
                             % p["php"], "dim-label", wrap=True, max_width_chars=50), False, False, 0)
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=4,
                           column_spacing=8, row_spacing=8, homogeneous=True)
        first, radios = None, []
        for v in versions:
            rb = Gtk.RadioButton.new_with_label_from_widget(first, "PHP %s%s" % (v, "  (ahora)" if v == p["php"] else ""))
            first = first or rb
            rb.set_active(v == p["php"])
            radios.append((rb, v))
            flow.add(rb)
        box.pack_start(flow, False, False, 0)
        box.show_all()
        resp = run_dialog(dlg)
        chosen = next((v for rb, v in radios if rb.get_active()), None)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT or not chosen or chosen == p["php"]:
            return
        self.run_task("%s: PHP %s → %s" % (p["folder"], p["php"], chosen), ["docker-php", p["slug"], chosen],
                      done_text="%s funciona ya con PHP %s" % (p["folder"], chosen), auto_close=True,
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def on_docker_delete(self, p):
        if not confirm(self.win, "¿Borrar %s de Docker?" % p["folder"],
                       "Se borran sus contenedores, su copia de la BBDD (%s) y su vhost (%s). La carpeta "
                       "y las BBDD de LAMPP no se tocan." % (p["db"], p["domain"]),
                       "Borrar de Docker", destructive=True):
            return
        self.run_task("Borrando %s de Docker" % p["folder"], ["docker-borrar", p["slug"]],
                      done_text="%s borrado de Docker" % p["folder"], auto_close=True,
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def build_docker_new(self):
        d = self.docker
        box, lb = group("Nuevo proyecto en Docker",
                        "Elige la carpeta del proyecto, su versión de PHP y de MariaDB y, si quieres, "
                        "la BBDD de LAMPP que se copia al contenedor. Su wp-config.php (o la "
                        "configuración de PrestaShop) se sustituye solo dentro del contenedor: el del "
                        "proyecto no cambia y la carpeta se puede seguir usando con LAMPP.")
        f = self.docker_form
        taken = {p["folder"] for p in d["projects"]}
        folders = [x for x in project_folders() if x not in taken]

        def combo_row(title, items, key, on_change=None):
            row = ActionRow(title)
            c = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
            for k, text in items:
                c.append(k, text)
            if not c.set_active_id(f.get(key) or "") and items:
                c.set_active(0)
            f[key] = c.get_active_id()
            # Ancho del nombre más largo (hasta 56 letras), para verlo entero al elegirlo
            narrow(c, min(56, max([COMBO_CHARS] + [len(t) for _k, t in items])))

            def changed(cb):
                f[key] = cb.get_active_id()
                if on_change:
                    on_change()
            c.connect("changed", changed)
            row.add_suffix(c)
            lb.add(row)
            return c
        combo_row("Carpeta", [(x, x) for x in folders], "folder",
                  lambda: GLib.idle_add(lambda: (self.docker_folder_changed(), False)[1]))
        combo_row("PHP", [(v, "PHP %s" % v) for v in d["php"]], "php")
        combo_row("MariaDB", [(v, "MariaDB %s" % v) for v in d["maria"]], "maria")
        # BBDD de LAMPP que se copia: las vinculadas a la carpeta en cada versión
        x = next((p for p in (self.projects or {}).get("list", []) if p["name"] == f.get("folder")), None)
        pairs = self.project_pairs(x) if x and self.data else []
        combo_row("BBDD que se copia", [("@vacia", "— Ninguna: vacía —")] +
                  [("%s|%s" % (i["folder"], db), "%s (lampp-%s)" % (db, i["folder"])) for i, db in pairs],
                  "source")
        # (el dominio sale solo: el de la tienda o el de la version de PHP)
        if f.get("folder"):
            dom = docker_web_domain({"slug": docker_slug(f["folder"]), "kind": project_kind(f["folder"])}, f.get("php") or "")
            row = ActionRow("Dominio", "Con el Apache de Docker (sin LAMPP), por https: " + dom)
            lb.add(row)
        row = ActionRow("")
        b = css(Gtk.Button(label="Crear en Docker", sensitive=bool(folders) and not self.busy), "verde")
        b.connect("clicked", lambda *_: self.on_docker_create())
        row.add_suffix(b)
        lb.add(row)
        return box

    def docker_folder_changed(self):
        f = self.docker_form
        f["source"] = None
        if not f.get("domain_set"):
            f["domain"] = docker_slug(f["folder"] or "") + ".docker.local" if f.get("folder") else ""
        self.build_docker()

    def on_docker_create(self):
        f = self.docker_form
        folder, php, maria = f.get("folder"), f.get("php"), f.get("maria")
        if not (folder and php and maria):
            return
        domain = docker_web_domain({"slug": docker_slug(folder), "kind": project_kind(folder)}, php)
        args = ["docker-nuevo", folder, php, maria]
        src = f.get("source")
        text = "PHP %s y MariaDB %s, en https://%s." % (php, maria, domain)
        if src and src != "@vacia" and "|" in src:
            ver, db = src.split("|", 1)
            args += ["--bd", db, "--desde", ver]
            text += " Con una copia de %s de lampp-%s (esa no se toca)." % (db, ver)
        else:
            text += " La BBDD empieza vacía."
        text += " La primera vez con cada PHP se prepara su imagen (unos minutos)."
        if not confirm(self.win, "¿Crear %s en Docker?" % folder, text, "Crear en Docker"):
            return
        self.run_task("Creando %s en Docker" % folder, args, progress=True,
                      done_text="%s en Docker: https://%s" % (folder, domain),
                      on_done=lambda *a: (f.clear(), run_quick(["gui-docker"], self.on_docker_data)))

    # ------------------------------------------------- descargar una base de datos
    def on_download_db(self, db, folder):
        d = self.data
        inst = next((i for i in d["installs"] if i["folder"] == folder), None)
        if not inst:
            return
        act = next((i for i in d["installs"] if i["folder"] == d["active"]), None)
        running = bool(act) and d["running"] and act["owner"] == inst["owner"]
        dlg = Gtk.FileChooserDialog(title="Descargar la BBDD %s" % db,
                                    transient_for=self.win, action=Gtk.FileChooserAction.SAVE,
                                    do_overwrite_confirmation=True)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Descargar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        dlg.set_current_folder(
            GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD)
            or os.path.expanduser("~"))
        dlg.set_current_name("%s-lampp-%s-%s.zip" % (db, folder, time.strftime("%Y%m%d-%H%M")))
        if not running:
            dlg.set_extra_widget(label(
                "lampp-%s no está en marcha: se arranca un MariaDB temporal solo para la copia "
                "(pide la contraseña de sudo)." % folder, "dim-label", wrap=True,
                max_width_chars=60))
        path = dlg.get_filename() if run_dialog(dlg) == Gtk.ResponseType.ACCEPT else None
        dlg.destroy()
        if not path:
            return
        if not re.search(r"(?i)(\.sql(\.gz)?|\.zip)$", path):
            path += ".zip"

        def start(pwd):
            def done(ok, task, _p):
                if ok:
                    task.offer("Abrir la carpeta", lambda: self.open_uri(
                        GLib.filename_to_uri(os.path.dirname(path))))
            self.run_task("Descargando %s" % db, ["exportar-bd", db, path, folder],
                          env={"MYSQL_PWD": pwd} if pwd else None, on_done=done,
                          done_text="Copia de «%s» guardada: %s" % (db, os.path.basename(path)),
                          cancel_text=("¿Cancelar la descarga?",
                                       "No se guarda nada.", "Cancelar la descarga"))
        if running:
            self.check_db_access(start)
        else:
            start(None)

    # ------------------------------------------- subir o actualizar una base de datos
    def build_import(self):
        d = self.data
        act = next((i for i in d["installs"] if i["folder"] == d["active"]), None)
        if act and self.imp["folder"] != act["folder"]:
            # Otra version activa: sus bases son otras
            self.imp.update(db=None, folder=act["folder"])
        box, lb = group("Subir o actualizar una BBDD",
                        "Carga una copia .sql, .sql.gz o .zip en el MariaDB de la versión activa%s. "
                        "Antes se borran todas las tablas de la BBDD de destino (con una copia en "
                        "~/lvm-copias), para que no quede nada de lo anterior. Los .zip se "
                        "descomprimen solos."
                        % (", lampp-%s (MariaDB %s)" % (act["folder"], act["mariadb"])
                           if act else ""))
        if not act:
            lb.add(ActionRow("No hay ninguna versión activa",
                             "Activa una versión en la pestaña Versiones para cargar BBDD."))
            return box

        f = self.imp["file"]
        sub = "Ningún fichero elegido"
        if f:
            try:
                sub = "%s  ·  %s" % (os.path.basename(f), fmt_size(os.path.getsize(f)))
            except OSError:
                sub = "%s  ·  ya no existe" % os.path.basename(f)
        row = ActionRow("Fichero SQL", sub)
        if f:
            row.set_tooltip_text(f)
        b = Gtk.Button(label="Elegir…")
        b.connect("clicked", self.on_pick_sql)
        row.add_suffix(b)
        lb.add(row)

        row = ActionRow("BBDD de destino", "En lampp-%s" % act["folder"])
        combo = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
        for db in d["dbs"].get(act["folder"], []):
            combo.append(db, db)
        if self.imp["db"]:
            combo.set_active_id(self.imp["db"])
        if combo.get_active_id() is None:
            self.imp["db"] = None
            combo.append("@ninguna", "Elige una BBDD")
            combo.set_active_id("@ninguna")
        combo.connect("changed", self.on_pick_db)
        row.add_suffix(combo)
        b = Gtk.Button(tooltip_text="Crear una BBDD nueva", valign=Gtk.Align.CENTER)
        b.add(icon("list-add-symbolic"))
        b.connect("clicked", self.on_create_db)
        row.add_suffix(b)
        self.imp_drop_btn = Gtk.Button(tooltip_text="Borrar la BBDD elegida",
                                       valign=Gtk.Align.CENTER, sensitive=bool(self.imp["db"]))
        self.imp_drop_btn.add(icon("user-trash-symbolic"))
        self.imp_drop_btn.connect("clicked", lambda *_: self.on_drop_db(self.imp["db"]))
        row.add_suffix(self.imp_drop_btn)
        lb.add(row)

        # Proyecto de la base: queda como su base y, si es un WordPress, su wp-config.php la usa
        folders = project_folders()
        if self.imp.get("project") not in folders:
            self.imp["project"] = None
        # La primera vez con esta base se propone su proyecto; luego se respeta lo elegido
        if self.imp["db"] and self.imp.get("project_for") != self.imp["db"]:
            self.imp["project"] = guess_project(self.imp["db"], self.data["active"] if self.data else None) or self.imp["project"]
            self.imp["project_for"] = self.imp["db"]
        self.imp_proj_row = ActionRow("Proyecto", self.import_project_hint())
        self.imp_proj_hint = self.imp_proj_row.subtitle
        # Ancho del nombre más largo (hasta 56 letras), para verlo entero al elegirlo
        combo = narrow(Gtk.ComboBoxText(valign=Gtk.Align.CENTER),
                       min(56, max([COMBO_CHARS] + [len(n) for n in folders])))
        combo.append("@ninguno", "Ninguno")
        for name in folders:
            combo.append(name, name)
        combo.set_active_id(self.imp["project"] or "@ninguno")
        combo.connect("changed", self.on_pick_project)
        self.imp_proj_combo = combo
        self.imp_proj_row.add_suffix(combo)
        lb.add(self.imp_proj_row)

        self.imp_btn = css(Gtk.Button(label="Cargar", halign=Gtk.Align.CENTER, margin_top=6),
                           "verde", "pildora")
        self.imp_btn.connect("clicked", self.on_import)
        box.pack_start(self.imp_btn, False, False, 0)
        self.imp_hint = label("", "dim-label", xalign=0.5)
        box.pack_start(self.imp_hint, False, False, 0)
        self.update_import_button()
        return box

    def update_import_button(self):
        db = self.imp["db"]
        hint = ""
        if not self.data["running"]:
            hint = "La versión activa está parada: arráncala en la pestaña Versiones."
        elif not self.imp["file"]:
            hint = "Elige el fichero SQL."
        elif not db:
            hint = "Elige la BBDD de destino o crea una con +."
        self.imp_btn.set_sensitive(not hint and not self.busy)
        self.imp_hint.set_label(hint)
        self.imp_hint.set_visible(bool(hint))

    def on_pick_sql(self, *_):
        dlg = Gtk.FileChooserDialog(title="Elegir el fichero SQL", transient_for=self.win,
                                    action=Gtk.FileChooserAction.OPEN)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Elegir", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        flt = Gtk.FileFilter()
        flt.set_name("Copias SQL (.sql, .sql.gz, .zip)")
        for pat in ("*.sql", "*.SQL", "*.sql.gz", "*.SQL.GZ", "*.zip", "*.ZIP"):
            flt.add_pattern(pat)
        dlg.add_filter(flt)
        flt = Gtk.FileFilter()
        flt.set_name("Todos los ficheros")
        flt.add_pattern("*")
        dlg.add_filter(flt)
        start = os.path.dirname(self.imp["file"]) if self.imp["file"] else \
            GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD) or os.path.expanduser("~")
        dlg.set_current_folder(start)
        if run_dialog(dlg) == Gtk.ResponseType.ACCEPT:
            path = dlg.get_filename()
            self.imp["file"] = path
            # Si hay una base que se llama como el fichero (mi_web.sql → mi_web), se propone
            stem = re.sub(r"(?i)(\.sql)?(\.gz|\.zip)?$", "", os.path.basename(path))
            if not self.imp["db"] and stem in self.data["dbs"].get(self.data["active"], []):
                self.imp["db"] = stem
                self.imp["project"] = guess_project(stem, self.data["active"] if self.data else None) or self.imp.get("project")
                self.imp["project_for"] = stem
            elif stem not in self.data["dbs"].get(self.data["active"], []):
                others = self.db_installs(stem)
                if others:
                    self.toast("«%s» está en %s, no en la versión activa" % (
                        stem, ", ".join("lampp-%s" % i["folder"] for i in others)))
        dlg.destroy()
        self.build_databases()

    def import_project_hint(self):
        folder = self.imp.get("project")
        if not folder:
            return "Opcional: si es la BBDD nueva de un proyecto, elige su carpeta."
        what = PROJECT_CONFIG_TEXT.get(project_kind(folder))
        if what:
            return what[:1].upper() + what[1:] + "."
        return "La BBDD queda asociada a esta carpeta (Cargar proyecto la usa)."

    def on_pick_project(self, combo):
        folder = combo.get_active_id()
        self.imp["project"] = None if folder in (None, "@ninguno") else folder
        self.imp["project_for"] = self.imp["db"]
        self.imp_proj_hint.set_label(self.import_project_hint())

    def on_pick_db(self, combo):
        db = combo.get_active_id()
        if db == "@ninguna":
            return
        self.imp["db"] = db
        guess = guess_project(db, self.data["active"] if self.data else None)
        if guess:
            self.imp_proj_combo.set_active_id(guess)
        self.imp["project_for"] = db
        self.imp_drop_btn.set_sensitive(True)
        self.update_import_button()

    def on_import(self, *_):
        db = self.imp["db"]
        path, folder = self.imp["file"], self.data["active"]
        try:
            size = fmt_size(os.path.getsize(path))
        except OSError:
            message(self.win, "No se encuentra el fichero", path, Gtk.MessageType.ERROR)
            return
        text = "Se carga en el MariaDB de lampp-%s. " % folder
        act = next((i for i in self.installs() if i["folder"] == folder), None)
        others = self.db_installs(db, skip_owner=act["owner"] if act else None)
        title = "¿Cargar %s (%s) en %s?" % (os.path.basename(path), size, db)
        ok_label = "Vaciar y cargar"
        if others:
            where = ", ".join("lampp-%s (PHP %s)" % (i["folder"], i["php"]) for i in others)
            title = "«%s» ya existe en %s" % (db, where)
            text = ("¿Quieres introducirla también en lampp-%s%s, la versión activa? Cada versión "
                    "tiene su propio MariaDB: la de %s no se toca.\n\n"
                    % (folder, " (PHP %s)" % act["php"] if act else "", where)
                    + "Fichero: %s (%s).\n\n" % (os.path.basename(path), size))
            ok_label = "Cargar también en lampp-%s" % folder
        text += ("Antes se BORRAN todas las tablas de «%s», para que no quede nada de lo "
                 "anterior. Si tiene alguna, primero se guarda una copia en ~/lvm-copias." % db)
        project = self.imp.get("project")
        if project:
            what = PROJECT_CONFIG_TEXT.get(project_kind(project))
            text += "\n\nDespués, «%s» pasa a ser la BBDD de %s%s." % (
                db, project, ": " + what if what else "")
        if not confirm(self.win, title, text, ok_label, destructive=True):
            return
        self.check_db_access(lambda pwd: self.start_import(path, db, pwd, project))

    # crear y borrar bases de datos (siempre en la version activa)
    def db_env(self):
        pwd = self.db_pwd.get(self.data["active"])
        return {"MYSQL_PWD": pwd} if pwd else None

    def on_create_db(self, *_):
        self.check_db_access(lambda _pwd: self.ask_new_db())

    def ask_new_db(self):
        folder = self.data["active"]
        existing = self.data["dbs"].get(folder, [])
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.QUESTION,
                                buttons=Gtk.ButtonsType.NONE, text="Crear BBDD")
        dlg.format_secondary_text("Se crea vacía en el MariaDB de lampp-%s, con juego de "
                                  "caracteres utf8mb4 (utf8mb4_general_ci)." % folder)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        entry = Gtk.Entry(placeholder_text="nombre_de_la_base", max_length=64,
                          activates_default=True)
        box.pack_start(entry, False, False, 0)
        hint = label("Letras sin acentos, números, _ y -", "dim-label", wrap=True,
                     max_width_chars=50)
        box.pack_start(hint, False, False, 0)
        dlg.get_message_area().pack_start(box, False, False, 0)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Crear", Gtk.ResponseType.ACCEPT), "verde")
        ok.set_sensitive(False)
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)

        def update(*_):
            name = entry.get_text().strip()
            valid = bool(re.match(r"^[A-Za-z0-9_-]{1,64}$", name))
            taken = name in existing or name.lower() in (
                "information_schema", "mysql", "performance_schema", "phpmyadmin", "sys", "test")
            act = next((i for i in self.installs() if i["folder"] == folder), None)
            others = [] if taken or not valid else \
                self.db_installs(name, skip_owner=act["owner"] if act else None)
            if taken:
                hint.set_label("Ya hay una BBDD con ese nombre.")
            elif others:
                hint.set_label("Ya existe en %s. Si sigues, se crea también en lampp-%s."
                               % (", ".join("lampp-%s (PHP %s)" % (i["folder"], i["php"])
                                            for i in others), folder))
            else:
                hint.set_label("Letras sin acentos, números, _ y -")
            ctx = hint.get_style_context()
            (ctx.add_class if taken or (name and not valid) else ctx.remove_class)("error")
            (ctx.add_class if others else ctx.remove_class)("aviso")
            ok.set_sensitive(valid and not taken)
        entry.connect("changed", update)
        dlg.show_all()
        resp = run_dialog(dlg)
        name = entry.get_text().strip()
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return

        def created(rc, out):
            if rc == 0:
                self.imp.update(db=name)
                self.toast("BBDD «%s» creada" % name)
                self.reload()
            else:
                message(self.win, "No se ha podido crear la BBDD", out.strip()[-600:],
                        Gtk.MessageType.ERROR)
            return False
        run_quick(["crear-bd", name], created, env=self.db_env())

    def on_drop_db(self, db):
        if not db:
            return

        def info(rc, out):
            res = [f for f in parse_lines(out) if f[0] == "I"]
            if rc != 0 or not res:
                message(self.win, "No se puede borrar la BBDD", out.strip()[-600:],
                        Gtk.MessageType.ERROR)
            else:
                self.confirm_drop(db, int(res[0][1]), int(res[0][2]))
            return False
        self.check_db_access(lambda _pwd: run_quick(["gui-bd-info", db], info,
                                                    env=self.db_env()))

    def confirm_drop(self, db, tables, size):
        folder = self.data["active"]
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True,
                                message_type=Gtk.MessageType.WARNING,
                                buttons=Gtk.ButtonsType.NONE,
                                text="¿Borrar la BBDD «%s»?" % db)
        state = {"copy": tables > 0}
        if tables:
            dlg.format_secondary_markup(
                "En lampp-%s, con <b>%s</b> (%s). <b>No se puede deshacer.</b>"
                % (folder, plural(tables, "tabla", "tablas"), fmt_size(size)))
        else:
            dlg.format_secondary_text("En lampp-%s, vacía (sin tablas). No se puede deshacer." % folder)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Borrar la BBDD", Gtk.ResponseType.ACCEPT), "destructive-action")
        dlg.set_default_response(Gtk.ResponseType.CANCEL)
        if tables:
            extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            copy = Gtk.CheckButton(label="Guardar antes una copia en ~/lvm-copias "
                                         "(se puede volver a cargar)", active=True)
            extra.pack_start(copy, False, False, 0)
            warn = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            warn.pack_start(label("Sin copia, el contenido no se podrá recuperar. "
                                  "Escribe %s para confirmar:" % db, "error", wrap=True,
                                  max_width_chars=50), False, False, 0)
            entry = Gtk.Entry()
            warn.pack_start(entry, False, False, 0)
            extra.pack_start(warn, False, False, 0)
            dlg.get_message_area().pack_start(extra, False, False, 0)

            def update(*_):
                state["copy"] = copy.get_active()
                warn.set_visible(not state["copy"])
                ok.set_sensitive(state["copy"] or entry.get_text().strip() == db)
            copy.connect("toggled", update)
            entry.connect("changed", update)
            dlg.show_all()
            update()
        else:
            dlg.show_all()
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return

        def done(ok_, _task, _p):
            if ok_ and self.imp["db"] == db:
                self.imp.update(db=None)
        self.run_task("Borrando la BBDD %s" % db,
                      ["borrar-bd", db] + (["--copia"] if state["copy"] else []),
                      env=self.db_env(), on_done=done, auto_close=True,
                      done_text="BBDD «%s» borrada" % db
                      + (" (copia en ~/lvm-copias)" if state["copy"] else ""))

    def check_db_access(self, then, retry=False):
        """Comprueba que se puede entrar en el MariaDB activo; si root tiene contraseña la pide."""
        folder = self.data["active"]
        pwd = self.db_pwd.get(folder)
        self.imp_btn.set_sensitive(False)

        def checked(_rc, out):
            self.update_import_button()
            res = (out.strip().splitlines() or ["no|Sin respuesta"])[-1].split("|")
            if res[0] == "ok":
                then(pwd)
            elif res[0] == "clave":
                new = self.ask_db_password(folder, retry=pwd is not None)
                if new is not None:
                    self.db_pwd[folder] = new
                    self.check_db_access(then, retry=True)
            else:
                message(self.win, "No se puede entrar en MariaDB", "|".join(res[1:]),
                        Gtk.MessageType.ERROR)
            return False
        run_quick(["gui-bd-comprobar"], checked, env={"MYSQL_PWD": pwd} if pwd else None)

    def ask_db_password(self, folder, retry=False):
        dlg = Gtk.Dialog(title="Contraseña de MariaDB", transient_for=self.win, modal=True,
                         use_header_bar=True)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Continuar", Gtk.ResponseType.OK), "verde")
        dlg.set_default_response(Gtk.ResponseType.OK)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=20)
        box.pack_start(icon("dialog-password-symbolic", 48), False, False, 0)
        box.pack_start(label("El usuario root del MariaDB de lampp-%s tiene contraseña.\n"
                             "Escríbela para continuar." % folder,
                             xalign=0.5, justify=Gtk.Justification.CENTER), False, False, 0)
        if retry:
            box.pack_start(label("Contraseña incorrecta. Vuelve a intentarlo.", "error",
                                 xalign=0.5), False, False, 0)
        entry = Gtk.Entry(visibility=False, activates_default=True,
                          input_purpose=Gtk.InputPurpose.PASSWORD)
        box.pack_start(entry, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.show_all()
        resp = run_dialog(dlg)
        pwd = entry.get_text()
        dlg.destroy()
        return pwd if resp == Gtk.ResponseType.OK else None

    def start_import(self, path, db, pwd, project=None):
        args = ["importar-bd", path, db] + (["--proyecto", project] if project else [])

        def done(ok, _task, _p):
            if ok:
                self.imp.update(file=None, db=db)

        self.run_task("Cargando %s en %s" % (os.path.basename(path), db), args, progress=True,
                      on_done=done, done_text="BBDD «%s» cargada" % db
                      + (" en %s" % project if project else ""),
                      env={"MYSQL_PWD": pwd} if pwd else None,
                      cancel_text=("¿Cancelar la carga?",
                                   "La BBDD «%s» se queda a medias: tendrá lo que se haya "
                                   "cargado hasta ahora." % db, "Cancelar la carga"))

    # -------------------------------------------------------------- acerca
    def on_about(self, *_):
        d = self.data or {}
        about = Gtk.AboutDialog(
            transient_for=self.win, modal=True, program_name=d.get("name", ""),
            version=d.get("version", ""), logo_icon_name=self.icon,
            copyright="%s\n© %d" % (d.get("signature", ""), time.localtime().tm_year),
            comments="Herramientas de desarrollo web en local.")
        about.set_default_size(560, -1)
        about.run()
        about.destroy()

    def on_commands(self, *_):
        """Ayuda: los comandos de lvm-instalador (lo mismo que lvm-instalador --ayuda)."""
        def show(_rc, out):
            dlg = Gtk.Dialog(title="Comandos de lvm-instalador", transient_for=self.win,
                             modal=True, use_header_bar=True)
            dlg.set_default_size(860, 700)
            hb = dlg.get_header_bar()
            hb.set_subtitle("En la terminal: lvm-instalador --ayuda")
            copy = Gtk.Button(label="Copiar todo")
            copy.connect("clicked", lambda *_: (
                Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(out, -1),
                self.toast("Copiado al portapapeles")))
            hb.pack_start(copy)
            tv = css(Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                                  left_margin=16, right_margin=16, top_margin=12,
                                  bottom_margin=12), "log")
            # Cada sección («=== TÍTULO ===») en verde y grande, y cada orden en negrita: se
            # distinguen de su explicación (con sangría, debajo)
            buf = tv.get_buffer()
            buf.set_text(out)
            buf.create_tag("seccion", weight=700, scale=1.15, foreground=GREEN, pixels_above_lines=10,
                           pixels_below_lines=4)
            buf.create_tag("orden", weight=700, pixels_above_lines=4)
            for n, line in enumerate(out.split("\n")):
                tag = "seccion" if line.startswith("=== ") else \
                    "orden" if line.startswith("  lvm-instalador") else None
                if tag:
                    start = buf.get_iter_at_line(n)
                    end = start.copy()
                    end.forward_to_line_end()
                    buf.apply_tag_by_name(tag, start, end)
            sw = Gtk.ScrolledWindow(vexpand=True)
            sw.add(tv)
            dlg.get_content_area().add(sw)
            dlg.show_all()
            run_dialog(dlg)
            dlg.destroy()
            return False
        run_quick(["--ayuda"], show)

    def on_changes(self, *_):
        def show(_rc, out):
            dlg = Gtk.Dialog(title="Novedades", transient_for=self.win, modal=True,
                             use_header_bar=True)
            dlg.set_default_size(780, 680)
            tv = Gtk.TextView(editable=False, cursor_visible=False, wrap_mode=Gtk.WrapMode.WORD_CHAR,
                              left_margin=24, right_margin=24, top_margin=8, bottom_margin=24)
            markdown_to_buffer(tv.get_buffer(), out)
            sw = Gtk.ScrolledWindow(vexpand=True)
            sw.add(tv)
            dlg.get_content_area().add(sw)
            dlg.show_all()
            run_dialog(dlg)
            dlg.destroy()
            return False
        run_quick(["novedades"], show)

    # ----------------------------------------- capturas (solo para revisar la ventana)
    def capture(self, widget, name):
        import cairo
        widget.check_resize()
        w, h = widget.get_allocated_width(), widget.get_allocated_height()
        surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
        cr = cairo.Context(surf)
        Gtk.render_background(widget.get_style_context(), cr, 0, 0, w, h)
        widget.draw(cr)
        surf.write_to_png(os.path.join(os.environ["LVM_CAPTURA"], name + ".png"))

    def capture_all(self):
        steps = [(lambda: None, "1-versiones"), (lambda: self.show_tab("bbdd"), "3-bbdd"),
                 (lambda: self.show_tab("servicios"), None), (lambda: None, "6-servicios"),
                 (lambda: self.show_tab("hosts"), None), (lambda: None, "5-hosts"),
                 (lambda: self.show_tab("herramientas"), None), (lambda: None, "4-herramientas"),
                 (lambda: self.quit(), None)]

        def step(i=[0]):  # noqa: B006 (el contador de los pasos, a propósito)
            fn, shot = steps[i[0]]
            fn()
            if shot:
                GLib.timeout_add(1500, lambda: (self.capture(self.win, shot), False)[1])
            i[0] += 1
            return i[0] < len(steps)
        GLib.timeout_add(2500, step)
        return False


# ===================================================================================================
# La ventana (desde la 1.54). Sobre App, que lleva los datos (gui-*), las tareas (con su contraseña) y
# los dialogos, y lanza las mismas ordenes de siempre; App2 cambia la organizacion y el aspecto.
#   - Arriba, siempre a la vista: la version activa (sus servicios al pulsarla), Localhost,
#     phpMyAdmin y los avisos en un solo boton
#   - Proyectos: el cargado en grande (su entorno y su BBDD) y la lista compacta de todos
#   - Versiones de PHP (tabla, e Instalar en un dialogo), Bases de datos, Docker, Dominios y hosts y
#     Configuracion
BLUE = "#0a84ff"
NEW_GREEN = "#30d158"
NEW_CSS = """
.nv-tenue { color: alpha(@theme_fg_color, 0.55); }
.nv-mono { font-family: monospace; }
.nv-chico { font-size: 0.86em; }
.nv-seccion { font-size: 0.78em; font-weight: bold; color: alpha(@theme_fg_color, 0.45); }
.nv-titulo { font-size: 1.2em; font-weight: bold; }
.nv-titulo-grande { font-size: 1.65em; font-weight: bold; }
/* «Dev Stack» del título: sin negrita y en azul, mezclado con el color del texto para que se lea
   bien en los dos temas (más claro sobre el gris oscuro, más oscuro sobre el claro) */
.nv-marca { font-weight: normal; color: mix(%(b)s, @theme_fg_color, 0.22); }
.nv-nexum { font-family: "Goldman"; font-weight: normal; letter-spacing: 1px; }
.nv-lateral { background-color: alpha(@theme_fg_color, 0.035); border-right: 1px solid alpha(@theme_fg_color, 0.08); }
.nv-nav { background: transparent; }
.nv-nav row { padding: 13px 14px; border-radius: 10px; margin: 2px 10px; }
.nv-nav row:hover { background-color: alpha(@theme_fg_color, 0.06); }
.nv-nav row:selected { background-color: %(b)s; color: white; }
.nv-nav row:selected label, .nv-nav row:selected image { color: white; }
/* Apariencia, iconos en color: los del tema, cada uno con el suyo (en la fila elegida, en blanco) */
.nv-nav image.nv-tinte-proyectos { color: #E8A23A; }
.nv-nav image.nv-tinte-dominios { color: #1C9C6B; }
.nv-nav image.nv-tinte-config { color: #7C6FD8; }
/* Configuración: la columna de sus apartados */
.nv-subnav-lateral { background-color: alpha(@theme_fg_color, 0.018); border-right: 1px solid alpha(@theme_fg_color, 0.08); }
.nv-subnav-caja { background-color: alpha(@theme_fg_color, 0.035); border: 1px solid alpha(@theme_fg_color, 0.08);
                  border-radius: 12px; padding: 6px 0; }
.nv-subnav row { padding: 9px 12px; margin: 1px 6px; border-radius: 8px; }
/* Barra de arriba mas alta, y el recuadro de la version montada, hundido (como una pantallita) */
headerbar.nv-cabecera { min-height: 60px; padding-top: 8px; padding-bottom: 8px; }
.nv-pastilla { background-color: shade(@theme_bg_color, 0.78); border: 1px solid alpha(black, 0.25); border-radius: 12px;
               padding: 3px 4px; box-shadow: inset 0 2px 4px alpha(black, 0.45), inset 0 0 0 1px alpha(black, 0.10),
               0 1px 0 alpha(white, 0.06); }
.nv-pastilla button { border: none; background: transparent; box-shadow: none; }
.nv-pastilla button.nv-servicios { border-radius: 8px; padding: 2px 8px; }
.nv-pastilla button.nv-servicios:hover, .nv-pastilla button.nv-servicios:checked { background-color: alpha(@theme_fg_color, 0.10); }
/* Subir o actualizar una BBDD: un visor un poco hundido, como el de arriba */
.nv-hundido { background-color: shade(@theme_bg_color, 0.86); border: 1px solid alpha(black, 0.20); border-radius: 12px;
              box-shadow: inset 0 2px 6px alpha(black, 0.35), inset 0 0 0 1px alpha(black, 0.10); padding: 14px 16px; }
.nv-hundido-titulo { font-weight: bold; }
.nv-terminal { background-color: shade(@theme_bg_color, 0.78); border: 1px solid alpha(black, 0.25); border-radius: 12px;
               box-shadow: inset 0 2px 7px alpha(black, 0.45), inset 0 0 0 1px alpha(black, 0.15); margin: 12px 14px 12px 14px;
               padding: 10px 10px 10px 10px; }
.nv-terminal-vte { border-radius: 8px; }
.nv-sep { background-color: alpha(@theme_fg_color, 0.15); min-width: 1px; margin: 6px 2px; }
.nv-verde { color: %(g)s; }
.nv-gris { color: alpha(@theme_fg_color, 0.3); }
.nv-aviso-num { background-color: #ff453a; color: white; border-radius: 9px; padding: 0 6px; font-size: 0.75em; font-weight: bold; }
.nv-correo-num { background-color: %(b)s; color: white; border-radius: 9px; padding: 0 6px; font-size: 0.75em; font-weight: bold; }
.nv-correo-aviso { color: #ff9f0a; }
/* Botones: redondeados, con borde gris y, al pasar el raton, borde azul (todos, tambien los planos
   y los desplegables; no los de cerrar, maximizar y minimizar). El principal, en azul */
button { border-radius: 8px; }
button:not(.titlebutton) { border-color: alpha(@theme_fg_color, 0.22); }
button:not(.titlebutton):hover, button:not(.titlebutton):checked:hover {
    border-color: %(b)s; background-image: none; background-color: alpha(%(b)s, 0.08); }
button.flat:not(.titlebutton):hover { border: 1px solid %(b)s; }
button.verde, button.suggested-action, .nv-azul { background-image: none; background-color: %(b)s; color: white; border-color: transparent; box-shadow: none; }
button.verde:hover, .nv-azul:hover { background-color: shade(%(b)s, 1.12); border-color: shade(%(b)s, 1.35); }
button.verde label, button.verde image, .nv-azul label, .nv-azul image { color: white; }
button.verde:disabled, .nv-azul:disabled { background-color: alpha(%(b)s, 0.35); }
button.suggested-action:hover { background-color: shade(%(b)s, 1.12); border-color: shade(%(b)s, 1.35); }
button.suggested-action label { color: white; }
button.suggested-action:disabled { background-color: alpha(%(b)s, 0.35); }
button.suggested-action:disabled label { color: alpha(white, 0.6); }
popover { border-radius: 12px; padding: 5px; }
popover modelbutton { border-radius: 7px; padding: 6px 12px; min-height: 26px; }
popover modelbutton:hover { background-color: %(b)s; color: white; }
/* Con el fondo azul al pasar el raton, la letra y los iconos en blanco (en el tema claro, la letra
   oscura del tema no se veia sobre el azul) */
popover modelbutton:hover label, popover modelbutton:hover image, popover modelbutton:hover arrow { color: white; }
/* El boton del menu: sin recuadro (tampoco al pasar el raton: solo un fondo suave) */
button.flat.nv-hamburguesa:not(.titlebutton), button.flat.nv-hamburguesa:not(.titlebutton):hover,
button.flat.nv-hamburguesa:not(.titlebutton):checked {
    border: 1px solid transparent; box-shadow: none; background-image: none; padding: 6px 8px; }
button.flat.nv-hamburguesa:not(.titlebutton):hover, button.flat.nv-hamburguesa:not(.titlebutton):checked {
    background-color: alpha(@theme_fg_color, 0.08); }
/* Opciones del menu: a todo el ancho, sin borde, y en azul al pasar el raton */
button.flat.nv-menuitem:not(.titlebutton), button.flat.nv-menuitem:not(.titlebutton):hover {
    border: 1px solid transparent; border-radius: 7px; padding: 7px 12px; min-height: 0; }
button.flat.nv-menuitem:not(.titlebutton):hover { background-color: %(b)s; }
button.flat.nv-menuitem:hover label, button.flat.nv-menuitem:hover image { color: white; }
combobox button, entry { border-radius: 8px; }
list.caja, .nv-grupo { background-color: alpha(@theme_fg_color, 0.045); border-radius: 12px; border: 1px solid alpha(@theme_fg_color, 0.07); }
.nv-grupo row { border-bottom: 1px solid alpha(@theme_fg_color, 0.06); }
.nv-grupo row:last-child { border-bottom: none; }
.nv-fila { padding: 8px 14px; }
.nv-cab label { font-size: 0.76em; font-weight: bold; color: alpha(@theme_fg_color, 0.45); }
.nv-zona { background-color: alpha(@theme_fg_color, 0.06); border: 2px dashed alpha(@theme_fg_color, 0.28); border-radius: 12px; }
.nv-zona-lista { background-color: alpha(%(b)s, 0.10); border: 2px solid %(b)s; }
.nv-zona:drop(active) { background-color: alpha(%(b)s, 0.30); border: 2px solid %(b)s; box-shadow: none; }
.nv-bbdd { color: mix(%(b)s, @theme_fg_color, 0.22); font-weight: bold; }
.nv-zona-icono { color: %(b)s; }
.nv-tarjeta { background-color: alpha(@theme_fg_color, 0.045); border: 1px solid alpha(@theme_fg_color, 0.08); border-radius: 14px; padding: 20px 22px; }
/* (Configuración: cada ajuste en su tarjeta, de dos en dos) */
.nv-mosaico { background-color: alpha(@theme_fg_color, 0.045); border: 1px solid alpha(@theme_fg_color, 0.08); border-radius: 12px; padding: 14px 16px; }
.nv-mosaico-titulo { font-weight: 600; }
.nv-etiqueta { font-size: 0.78em; padding: 1px 8px; border-radius: 10px; background-color: alpha(@theme_fg_color, 0.07); color: alpha(@theme_fg_color, 0.75); }
.nv-etiqueta-azul { background-color: alpha(%(b)s, 0.16); color: %(b)s; }
.nv-chip { font-size: 0.8em; padding: 3px 10px; border-radius: 7px; background-color: alpha(@theme_fg_color, 0.06); }
.nv-chip-docker { background-color: alpha(#1d63ed, 0.16); color: #4c8dff; }
.nv-selectores { background-color: alpha(black, 0.07); border: 1px solid alpha(black, 0.12); border-radius: 12px;
                 padding: 12px 14px; box-shadow: inset 0 1px 3px alpha(black, 0.22), 0 1px 0 alpha(white, 0.05); }
/* El boton de vincular (cambiar la BBDD de cada version): azul al pasar el raton */
.nv-selectores button:hover { background-image: none; background-color: %(b)s; border-color: %(b)s; }
.nv-selectores button:hover image, .nv-selectores button:hover label, .nv-selectores button:hover cellview,
.nv-selectores button:hover arrow { color: white; }
.nv-pie { border-top: 1px solid alpha(@theme_fg_color, 0.08); }
.nv-cargada { background-color: alpha(%(b)s, 0.10); }
.nv-elegida { background-color: alpha(@theme_fg_color, 0.06); }
.nv-discontinuo { border-style: dashed; }
.nv-proyecto-btn, .nv-proyecto-btn button { background-image: none; background-color: transparent; box-shadow: none;
                                           border: 1px solid alpha(@theme_fg_color, 0.22); }
.nv-proyecto-btn:hover, .nv-proyecto-btn button:hover { border-color: %(b)s; background-color: alpha(%(b)s, 0.08); }
.nv-proyecto-btn.nv-discontinuo { border-style: dashed; }
/* (un túnel abierto: la web se ve desde fuera) */
.nv-proyecto-btn.nv-boton-cuadrado { padding: 4px; border-radius: 12px; }
.nv-proyecto-btn.nv-compartiendo { border-color: #F38020; background-color: alpha(#F38020, 0.10); }
switch:checked { background-color: %(g)s; border-color: transparent; }
.nv-running { font-size: 0.86em; color: %(g)s; }
.nv-exited { font-size: 0.8em; padding: 1px 9px; border-radius: 10px; background-color: alpha(@theme_fg_color, 0.08); color: alpha(@theme_fg_color, 0.6); }
.nv-enlace { color: #4c8dff; }
.nv-dk-icono { border-radius: 8px; background-color: alpha(#1d63ed, 0.14); padding: 5px; }
/* Visor de un proyecto en Docker (al desplegar su fila): como el del proyecto cargado, más pequeño */
.nv-dk-visor { padding: 14px 18px; margin: 4px 12px 10px 38px; }
.nv-stat { background-color: alpha(@theme_fg_color, 0.045); border: 1px solid alpha(@theme_fg_color, 0.07); border-radius: 12px; padding: 14px 16px; }
.nv-cifra { font-size: 1.5em; font-weight: bold; }
/* Botones de siempre (los de la pestaña Docker): borde gris claro y azul al pasar el raton */
button.nv-clasico { background-image: none; background-color: transparent; box-shadow: none;
                    border: 1px solid alpha(@theme_fg_color, 0.16); }
button.nv-clasico:hover { border-color: %(b)s; background-color: alpha(%(b)s, 0.08); }
button.nv-stop image { color: #ff453a; }
button.nv-play image { color: %(g)s; }
/* El boton de la version activa: como «Activar», con borde y letra azules */
button.nv-activa, button.nv-activa:disabled { background-image: none; background-color: transparent; box-shadow: none;
                                             border: 1px solid %(b)s; }
button.nv-activa label, button.nv-activa:disabled label { color: %(b)s; }
/* Punto que parpadea: lo que esta en marcha */
@keyframes nv-latido { 0%% { opacity: 1; } 50%% { opacity: 0.25; } 100%% { opacity: 1; } }
.nv-latido { animation: nv-latido 1.6s ease-in-out infinite; }
/* Tarea en segundo plano, al lado del visor: verde, con la flecha que baja y late */
button.nv-tarea-fondo { background-image: none; box-shadow: none; border-radius: 999px; padding: 2px 10px;
                        border: 1px solid alpha(%(g)s, 0.55); background-color: alpha(%(g)s, 0.12); }
button.nv-tarea-fondo:hover { background-color: alpha(%(g)s, 0.22); }
button.nv-tarea-fondo label, button.nv-tarea-fondo image { color: %(g)s; }
@keyframes nv-baja { 0%% { opacity: 1; -gtk-icon-transform: translateY(-2px); }
                     50%% { opacity: 0.35; -gtk-icon-transform: translateY(2px); }
                     100%% { opacity: 1; -gtk-icon-transform: translateY(-2px); } }
.nv-tarea-flecha { animation: nv-baja 1.1s ease-in-out infinite; }
/* Opciones de los desplegables: fondo azul y letra blanca al pasar el raton */
menu menuitem:hover, .menu menuitem:hover { background-color: %(b)s; }
menu menuitem:hover label, menu menuitem:hover cellview, .menu menuitem:hover label { color: white; }
.nv-barra trough { min-height: 6px; border-radius: 3px; background-color: alpha(@theme_fg_color, 0.08); }
.nv-barra progress { min-height: 6px; border-radius: 3px; background-color: #1d63ed; }
.nv-segmentado { background-color: alpha(@theme_fg_color, 0.07); border-radius: 9px; padding: 2px; }
.nv-segmentado radiobutton, .nv-segmentado button { border-radius: 7px; border: none; background: transparent; box-shadow: none; padding: 3px 14px; }
.nv-segmentado radiobutton:checked, .nv-segmentado button:checked { background-color: alpha(@theme_fg_color, 0.16); }
.nv-dk-proyecto { font-weight: bold; }
.nv-on { color: %(g)s; background-image: none; background-color: alpha(%(g)s, 0.14); border-color: transparent; }
.nv-off { color: #ff453a; background-image: none; background-color: alpha(#ff453a, 0.14); border-color: transparent; }
.nv-on label, .nv-on image { color: %(g)s; }
/* Tema claro: «Encendidos» en azul (el verde no se ve sobre el gris claro) */
.nv-claro .nv-on { color: %(b)s; background-color: alpha(%(b)s, 0.12); }
.nv-claro .nv-on label, .nv-claro .nv-on image { color: %(b)s; }
.nv-off label, .nv-off image { color: #ff453a; }
/* Dialogos: como las pestañas (mismo fondo, botones redondeados con borde) y en azul, no en verde */
dialog, messagedialog { background-color: @theme_bg_color; }
dialog headerbar { min-height: 52px; border-bottom: 1px solid alpha(@theme_fg_color, 0.08); box-shadow: none; }
messagedialog .titlebar { min-height: 10px; }
messagedialog .dialog-action-box { margin: 0; padding: 4px 22px 20px 22px; border-top: none; }
messagedialog .dialog-action-area button, messagedialog .dialog-action-area button:first-child,
messagedialog .dialog-action-area button:last-child {
    border-radius: 8px; min-height: 34px; padding: 4px 18px; margin: 0 5px;
    border: 1px solid alpha(@theme_fg_color, 0.22); }
messagedialog .dialog-action-area button.verde { border-color: transparent; }
messagedialog .dialog-action-area button.destructive-action { border-color: transparent; }
messagedialog image { color: %(b)s; }
messagedialog label.title { font-size: 1.15em; }
dialog .dialog-action-area button { border-radius: 8px; min-height: 32px; padding: 4px 18px; }
progressbar progress { background-image: none; background-color: %(b)s; border-color: %(b)s; }
.opcion.elegida { border-color: %(b)s; background-color: alpha(%(b)s, 0.08); }
list.caja > row:selected, list.caja > row:selected:hover { background-color: alpha(%(b)s, 0.22); }
.pastilla.activa { background-color: %(b)s; }
.icono-seccion.verde-suave, .icono-servicio.verde-suave { background-color: alpha(%(b)s, 0.16); color: %(b)s; }
.texto-activa { color: %(b)s; }
radio:checked, check:checked { background-image: none; background-color: %(b)s; border-color: %(b)s; color: white; }
button.pildora { border-radius: 8px; padding: 6px 20px; }
/* Tareas: barra gruesa con su porcentaje y lo que queda, y el registro como una terminal */
.nv-progreso trough { min-height: 12px; border-radius: 6px; background-color: alpha(@theme_fg_color, 0.10); border: none; }
.nv-progreso progress { min-height: 12px; border-radius: 6px; background-color: %(b)s; border: none; }
.nv-progreso-error progress { background-color: #ff453a; }
.nv-porcentaje { font-weight: bold; }
.nv-hecho { color: %(b)s; }
.nv-consola-marco { border-radius: 10px; background-color: #1d2228; border: 1px solid alpha(black, 0.25); }
textview.nv-consola, textview.nv-consola text { background-color: #1d2228; color: #d7dee6; font-size: 9.5pt; }
expander title > arrow { min-width: 14px; }
""" % {"b": BLUE, "g": NEW_GREEN}

KIND_TEXT = {"wp": "WordPress", "ps": "PrestaShop"}

# Tema claro u oscuro de la ventana nueva (solo para ella: el escritorio no se toca)
THEME_FILE = os.path.join(LOG_DIR, "ventana-tema")
# Icono junto al reloj: «no» si se ha apagado en Configuración (sin el fichero, encendido)
TRAY_FILE = os.path.join(LOG_DIR, "ventana-bandeja")


def tray_lib():
    """El módulo del icono junto al reloj (AppIndicator de Ayatana, el de Ubuntu), o None si no está."""
    for name in ("AyatanaAppIndicator3", "AppIndicator3"):
        try:
            gi.require_version(name, "0.1")
            return getattr(__import__("gi.repository", fromlist=[name]), name)
        except (ValueError, ImportError, AttributeError):
            continue
    return None


def tray_wanted():
    try:
        with open(TRAY_FILE, encoding="utf-8") as f:
            return f.read().strip() != "no"
    except OSError:
        return True


def theme_exists(name):
    """¿Hay un tema GTK 3 con ese nombre (del sistema o tuyo)?"""
    if not re.fullmatch(r"[A-Za-z0-9._+-]{1,64}", name or ""):
        return False
    if name in ("Adwaita", "HighContrast"):
        return True
    return any(os.path.isdir(os.path.join(d, name, "gtk-3.0")) for d in
               ("/usr/share/themes", os.path.expanduser("~/.themes"), os.path.expanduser("~/.local/share/themes")))


PAGE_MAX = 1500


def new_page(width=860):
    """Pagina de la ventana nueva: con un ancho minimo y, con la ventana grande (maximizada), crece
    con ella hasta PAGE_MAX; a partir de ahi, centrada."""
    sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
    content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin=26,
                      halign=Gtk.Align.FILL)
    content.set_size_request(width, -1)
    sw.add(content)

    def fit(_w, alloc):
        side = max(26, (alloc.width - PAGE_MAX) // 2)
        if content.get_margin_start() != side:
            content.set_margin_start(side)
            content.set_margin_end(side)
    sw.connect("size-allocate", fit)
    return sw, content


def nv_dot(on):
    return label("●", "nv-verde" if on else "nv-gris")


def nv_button(icon_name, text=None, tip=None, cb=None, *classes, flat=False):
    b = Gtk.Button(tooltip_text=tip, valign=Gtk.Align.CENTER)
    if flat:
        b.set_relief(Gtk.ReliefStyle.NONE)
    box = Gtk.Box(spacing=6)
    if icon_name is not None:
        box.pack_start(icon_name if isinstance(icon_name, Gtk.Widget) else icon(icon_name), False, False, 0)
    if text:
        box.pack_start(Gtk.Label(label=text), False, False, 0)
    b.add(box)
    css(b, *classes)
    if cb:
        b.connect("clicked", cb)
    return b


def kind_icon(kind, size=18):
    return logo({"wp": "wordpress", "ps": "prestashop"}[kind], size) if kind in ("wp", "ps") \
        else icon("folder-symbolic", size)


class Hamburger(Gtk.DrawingArea):
    """Icono del menu: tres rayas, algo mas anchas que las del tema, del color del texto."""

    def __init__(self, width=20, height=16):
        super().__init__()
        self.set_size_request(width, height)

    def do_draw(self, cr):
        c = self.get_style_context().get_color(self.get_state_flags())
        cr.set_source_rgba(c.red, c.green, c.blue, c.alpha)
        w, h = self.get_allocated_width(), self.get_allocated_height()
        cr.set_line_width(2)
        cr.set_line_cap(1)  # (extremos redondeados)
        for y in (h / 2 - 5, h / 2, h / 2 + 5):
            cr.move_to(1, round(y) + 0.5)
            cr.line_to(w - 1, round(y) + 0.5)
        cr.stroke()
        return False


class App2(App):
    def __init__(self):
        super().__init__()

        self.selected_project = None
        self.np_dialog = None
        # Pestaña Docker: vista (cont, img, vol), filtros, proyectos plegados y uso de CPU y memoria
        # (dk_open: el proyecto desplegado, uno como mucho; al entrar en la pestaña, todos plegados)
        self.dk_view, self.dk_query, self.dk_only_up, self.dk_open, self.dk_stats = "cont", "", False, set(), None
        # Pestaña Bases de datos: buscador y «solo la activa» (la activa se ve desplegada al abrir)
        self.db_query, self.db_only_active = "", False
        # Tamaño de cada BBDD: (version duena, base) -> (bytes, cuando se midio)
        self.db_sizes = {}
        # Correo de pruebas: correos sin leer en Mailpit (None: no se sabe) y si se esta preguntando
        self.mail_unread, self.mail_polling = None, False

    # ------------------------------------------------------------------ ventana
    def do_activate(self):
        if getattr(self, "win", None):
            self.win.present()
            return
        hand = Gdk.Cursor.new_from_name(Gdk.Display.get_default(), "pointer")

        def pointer_hook(widget, event, *_):
            if isinstance(widget, (Gtk.Button, Gtk.Switch)) and event.window is not None:
                event.window.set_cursor(hand if widget.is_sensitive() else None)
            return True
        GObject.add_emission_hook(Gtk.Widget, "enter-notify-event", pointer_hook)

        # Los desplegables se abren debajo del boton, como una lista. Sin esto, GTK 3 pone la opcion
        # elegida encima del boton y, con muchas (los proyectos), deja huecos vacios por arriba o abajo
        def combo_hook(widget, *_):
            if isinstance(widget, Gtk.ComboBox) and widget.get_wrap_width() == 0:
                widget.set_wrap_width(1)
            return True
        GObject.add_emission_hook(Gtk.Widget, "realize", combo_hook)
        for text in (CSS, NEW_CSS):
            prov = Gtk.CssProvider()
            prov.load_from_data(text.encode())
            Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(), prov,
                                                     Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        theme = Gtk.IconTheme.get_default()
        self.icon = ICON if theme.lookup_icon(ICON, 24, 0) else "utilities-terminal"
        Gtk.Window.set_default_icon_name(self.icon)
        for name, cb in [("localhost", lambda *_: self.open_uri("http://localhost/")),
                         ("phpmyadmin", lambda *_: self.open_uri("http://127.0.0.1/phpmyadmin/")),
                         ("vhosts", self.on_vhosts), ("hosts", self.on_hosts),
                         ("logs", lambda *_: self.open_uri("file://" + LOG_DIR)),
                         ("update", lambda *_: self.check_package(manual=True)),
                         ("terminal", self.on_terminal), ("refresh", self.on_refresh),
                         ("changes", self.on_changes), ("about", self.on_about)]:
            act = Gio.SimpleAction.new(name, None)
            act.connect("activate", cb)
            self.add_action(act)
        self.win = Gtk.ApplicationWindow(application=self, title="Nexum Dev Stack")
        # Sin ninguna ventana del programa, se cierra del todo
        self.connect("window-removed", lambda app, _w: app.get_windows() or self.nv_exit())
        # (con el icono junto al reloj, la X la esconde: se vuelve a abrir o se sale desde él)
        self.win.connect("delete-event", lambda *_: self.nv_tray_hide())
        self.tray, self.tray_items, self.tray_ticks = None, {}, 0
        self.nv_tray_setup()
        self.win.set_default_size(1240, 840)
        self.win.set_titlebar(self.nv_header())
        try:
            with open(THEME_FILE, encoding="utf-8") as f:
                saved = f.read().strip()
        except OSError:
            saved = ""
        if saved in ("claro", "oscuro"):
            self.nv_apply_theme(saved == "oscuro")
        else:
            self.nv_apply_theme(self.nv_is_dark())

        # Cajas que rellenan los constructores de siempre (algunas no se ven: de ellas se sacan los
        # avisos, el asistente de proyecto nuevo e Instalar)
        self.legacy_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.ver_box = self.legacy_box
        self.inst_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=24)
        self.services_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=12)
        self.services_box.set_size_request(520, -1)
        self.services_pop.add(self.services_box)
        self.page_dbs, self.db_box = new_page()
        self.page_tools, self.tools_box = new_page(620)
        # (los apartados de Configuración, en una columna pegada al menú lateral)
        self.tools_side = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL), "nv-subnav-lateral")
        self.tools_side.set_size_request(220, -1)
        self.tools_wrap = Gtk.Box()
        self.tools_wrap.pack_start(self.tools_side, False, False, 0)
        self.tools_wrap.pack_start(self.page_tools, True, True, 0)
        self.page_hosts, self.hosts_box = new_page()
        self.page_docker, self.docker_box = new_page(940)
        self.page_projects, self.proj_page = new_page(940)
        self.page_repos, self.repos_page = new_page(940)
        self.repos, self.repos_all, self.github = None, False, None
        self.page_node, self.node_page = new_page(940)
        self.node_rows = None
        self.page_vers, self.vers_page = new_page(900)
        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        for name, w in [("proyectos", self.page_projects), ("repos", self.page_repos), ("versiones", self.page_vers),
                        ("bbdd", self.page_dbs), ("docker", self.page_docker), ("node", self.page_node),
                        ("dominios", self.page_hosts), ("config", self.tools_wrap)]:
            self.stack.add_named(w, name)
        body = Gtk.Box()
        body.pack_start(self.nv_sidebar(), False, False, 0)
        # (el contenido arriba y, abajo, la terminal: se cambia de alto arrastrando el borde)
        self.term_paned = Gtk.Paned(orientation=Gtk.Orientation.VERTICAL)
        self.term_paned.pack1(self.stack, True, False)
        self.term_paned.pack2(self.nv_term_panel(), False, False)
        body.pack_start(self.term_paned, True, True, 0)
        overlay = Gtk.Overlay()
        overlay.add(body)
        overlay.add_overlay(self.build_toast())
        self.win.add(overlay)
        self.nv_build_projects_shell()
        for box in (self.db_box, self.vers_page):
            self.loading(box)
        self.win.show_all()
        self.toast_rev.set_reveal_child(False)
        self.reload(branches=True)
        GLib.timeout_add_seconds(20, self.on_tick)
        # Los repositorios del buscador de Nuevo proyecto, ya cargados cuando se abra: los de la última
        # vez y, en cuanto la ventana ha cargado lo suyo, los de GitHub
        self.np_repos_load(cache=True)
        GLib.timeout_add_seconds(5, lambda: (self.np_repos_load(), False)[1])
        # Al abrir: si hay una versión nueva del programa (con los datos ya leídos: la versión actual)
        GLib.timeout_add_seconds(6, self.auto_check_package)
        # (los correos sin leer, tambien al volver a la ventana)
        self.win.connect("notify::is-active", lambda w, _p: w.is_active() and self.nv_mail_poll())

    # ------------------------------------------------------------------ icono junto al reloj
    def nv_tray_setup(self):
        """El icono junto al reloj (si está encendido en Configuración y hay AppIndicator): abrir la ventana,
        arrancar o parar la versión activa, abrir web.local y salir."""
        if self.tray is not None or not tray_wanted():
            return
        lib = tray_lib()
        if lib is None:
            return
        ind = lib.Indicator.new(APP_ID, self.icon, lib.IndicatorCategory.APPLICATION_STATUS)
        ind.set_title("Nexum Dev Stack")
        menu = Gtk.Menu()

        def add(key, text, cb=None):
            item = Gtk.MenuItem(label=text)
            if cb:
                item.connect("activate", lambda *_: cb())
            else:
                item.set_sensitive(False)
            menu.append(item)
            self.tray_items[key] = item
        add("open", "Abrir Nexum Dev Stack", self.nv_tray_open)
        menu.append(Gtk.SeparatorMenuItem())
        add("state", "Ninguna versión activa")
        add("power", "Arrancar", self.nv_tray_power)
        add("web", "Abrir web.local", self.nv_tray_web)
        menu.append(Gtk.SeparatorMenuItem())
        add("quit", "Salir", self.nv_tray_quit)
        menu.show_all()
        ind.set_menu(menu)
        ind.set_secondary_activate_target(self.tray_items["open"])
        ind.set_status(lib.IndicatorStatus.ACTIVE)
        self.tray = (lib, ind, menu)
        self.nv_tray_update()

    def nv_tray_remove(self):
        if self.tray is None:
            return
        lib, ind, _menu = self.tray
        ind.set_status(lib.IndicatorStatus.PASSIVE)
        self.tray, self.tray_items = None, {}

    def nv_tray_update(self):
        if self.tray is None:
            return
        d = self.data or {}
        act = d.get("active") or ""
        it = self.tray_items
        if not act:
            it["state"].set_label("Ninguna versión activa")
            it["power"].set_label("Elegir una versión…")
        else:
            it["state"].set_label("● lampp-%s en marcha" % act if d.get("running") else "○ lampp-%s parada" % act)
            it["power"].set_label("Parar y desactivar" if d.get("running") else "Arrancar lampp-%s" % act)
        it["power"].set_sensitive(bool(d) and not self.busy)
        link = (self.projects or {}).get("link") or ""
        it["web"].set_label("Abrir %s" % (link or "web.local"))
        it["web"].set_sensitive(bool(link) and bool(d.get("running")))

    def nv_tray_hide(self):
        """La X de la ventana: con el icono, la esconde (True: no se cierra); sin él, se cierra como siempre."""
        if self.tray is None:
            return False
        self.win.hide()
        return True

    def nv_tray_open(self):
        self.win.present()
        # (al volver, sus datos al momento: escondida solo se preguntaba lo del menú)
        if not self.busy:
            run_quick(["gui-vuelta"], self.on_round)

    def nv_tray_power(self):
        if not (self.data or {}).get("active"):
            self.nv_tray_open()
        self.nv_power()

    def nv_tray_web(self):
        link = (self.projects or {}).get("link")
        if link:
            self.open_uri("http://%s/" % link)

    def nv_tray_quit(self):
        self.nv_tray_remove()
        self.win.destroy()

    def nv_tray_toggle(self, sw, _p):
        on = sw.get_active()
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            with open(TRAY_FILE, "w", encoding="utf-8") as f:
                f.write("si\n" if on else "no\n")
        except OSError as exc:
            message(self.win, "No se ha podido guardar", str(exc), Gtk.MessageType.ERROR)
            return
        if on:
            self.nv_tray_setup()
        else:
            self.nv_tray_remove()

    def nv_exit(self):
        """Al cerrar la última ventana: se sale y, si algo lo retuviera (un bucle, un hilo, una orden que
        no acaba), a los 5 s se corta el proceso. Nunca queda un Nexum en marcha sin ventana."""
        self.quit()

        def watchdog():
            time.sleep(5)
            os._exit(0)
        threading.Thread(target=watchdog, daemon=True).start()

    def auto_check_package(self):
        if self.data is None or self.busy:
            return True
        if self.update_check_due():
            self.check_package(auto=True)
            # (y los parches de los componentes, un poco después: sin juntarse con el aviso del programa)
            GLib.timeout_add_seconds(25, self.nv_components_auto)
        return False

    def update_check_due(self):
        """¿Toca buscar una versión nueva al abrir? El primer arranque de cada día y, después, cada
        UPDATE_EVERY arranques. Se lleva en ~/.lvm-instalador/actualizaciones-arranques: fecha y los
        arranques desde la última vez que se buscó."""
        path = os.path.join(LOG_DIR, "actualizaciones-arranques")
        today = time.strftime("%Y-%m-%d")
        if SIMULATE:
            return True
        try:
            with open(path, encoding="utf-8") as fh:
                day, _, n = fh.read(40).strip().partition(" ")
            n = int(n)
        except (OSError, ValueError):
            day, n = "", 0
        due = day != today or n + 1 >= UPDATE_EVERY
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            with open(path + ".nuevo", "w", encoding="utf-8") as fh:
                fh.write("%s %d\n" % (today, 0 if due else n + 1))
            os.replace(path + ".nuevo", path)
        except OSError:
            pass
        return due

    def nv_header(self):
        hb = css(Gtk.HeaderBar(show_close_button=True), "nv-cabecera")
        brand = Gtk.Box(spacing=10)
        brand.pack_start(icon(self.icon, 30), False, False, 0)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
        # «NEXUM» en Goldman y «Dev Stack» sin negrita, en azul
        name = Gtk.Box(spacing=7)
        name.pack_start(label("NEXUM", "nv-titulo", "nv-nexum"), False, False, 0)
        name.pack_start(label("Dev Stack", "nv-titulo", "nv-marca"), False, False, 0)
        t.pack_start(name, False, False, 0)
        # (con la versión del programa detrás, al leer los datos)
        self.brand_sub = label("Entornos LAMPP y Docker", "nv-chico", "nv-tenue")
        t.pack_start(self.brand_sub, False, False, 0)
        brand.pack_start(t, False, False, 0)
        hb.pack_start(brand)
        # La version activa: al pulsarla, sus servicios (los de la pestaña Servicios de siempre)
        # Menu con un icono en cada opcion (el de GTK 3 a partir de un Gio.Menu no los pone) y el tema.
        # Sin recuadro, a la derecha del visor, con sus tres rayas mas anchas que las del tema
        mb = css(Gtk.MenuButton(tooltip_text="Menú", relief=Gtk.ReliefStyle.NONE, valign=Gtk.Align.CENTER), "nv-hamburguesa")
        mb.add(Hamburger())
        pop = Gtk.Popover(relative_to=mb)
        mbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1, margin=4)
        self.theme_item = None
        for n, section in enumerate([
                [("@tema", None, lambda: self.nv_theme())],
                [("Editar vhosts", "document-edit-symbolic", lambda: self.on_vhosts()),
                 ("Editar /etc/hosts", "network-workgroup-symbolic", lambda: self.on_hosts())],
                [("Volver a leer las versiones", "view-refresh-symbolic", lambda: self.on_refresh()),
                 ("Buscar actualizaciones", "software-update-available-symbolic", lambda: self.check_package(manual=True)),
                 ("Abrir el panel en la terminal", "utilities-terminal-symbolic", lambda: self.on_terminal()),
                 ("Carpeta de registros", "folder-documents-symbolic", lambda: self.open_uri("file://" + LOG_DIR))],
                [("Novedades", "starred-symbolic", lambda: self.on_changes()),
                 ("Acerca de Nexum Dev Stack", "help-about-symbolic", lambda: self.on_about())]]):
            if n:
                mbox.pack_start(Gtk.Separator(margin_top=4, margin_bottom=4), False, False, 0)
            for text, ic, fn in section:
                b = css(Gtk.Button(relief=Gtk.ReliefStyle.NONE), "nv-menuitem")
                row = Gtk.Box(spacing=10)
                img = symbol(ic or "weather-clear-night-symbolic", 16)
                lbl = Gtk.Label(label=text, xalign=0)
                row.pack_start(img, False, False, 0)
                row.pack_start(lbl, True, True, 0)
                b.add(row)
                b.connect("clicked", lambda _b, fn=fn: (pop.popdown(), fn()))
                if text == "@tema":
                    self.theme_item = (img, lbl)
                mbox.pack_start(b, False, False, 0)
        mbox.show_all()
        pop.add(mbox)
        mb.set_popover(pop)
        self.menu_btn = mb
        # Recuadro de la version montada: el logotipo de PHP y su version y Apache y MariaDB con su punto
        # (verde si estan en marcha); al pulsar en ellos, sus servicios (arrancarlos, pararlos...)
        pill = css(Gtk.Box(spacing=8, valign=Gtk.Align.CENTER), "nv-pastilla")
        pill.pack_start(Gtk.Box(), False, False, 4)
        pill.pack_start(logo("php", 18), False, False, 0)
        self.status_lbl = label("…")
        pill.pack_start(self.status_lbl, False, False, 0)
        self.status_sub = label("", "nv-tenue", "nv-mono", "nv-chico")
        pill.pack_start(self.status_sub, False, False, 0)
        pill.pack_start(css(Gtk.Box(), "nv-sep"), False, False, 0)
        self.status_btn = css(Gtk.MenuButton(tooltip_text="Servicios de la versión activa"), "nv-servicios")
        sbox = Gtk.Box(spacing=8)
        self.svc_dots = {}
        for name in ("Apache", "MariaDB"):
            dt = nv_dot(False)
            self.svc_dots[name] = dt
            sbox.pack_start(dt, False, False, 0)
            sbox.pack_start(label(name, "nv-chico"), False, False, 0)
        self.status_btn.add(sbox)
        self.services_pop = Gtk.Popover(relative_to=self.status_btn)
        self.status_btn.set_popover(self.services_pop)
        pill.pack_start(self.status_btn, False, False, 0)
        # Lo que gastan Nexum y sus servicios juntos (al pasar el ratón, cada parte)
        pill.pack_start(css(Gtk.Box(), "nv-sep"), False, False, 0)
        self.usage_lbl = label("CPU — · RAM —", "nv-mono", "nv-chico", "nv-tenue", width_chars=21, xalign=0.5,
                               tooltip_text="Consumo de Nexum y sus servicios")
        pill.pack_start(self.usage_lbl, False, False, 0)
        self.usage = UsageMeter()
        self.nv_usage_tick()
        GLib.timeout_add_seconds(3, self.nv_usage_tick)
        pill.pack_start(Gtk.Box(), False, False, 2)
        self.warn_btn = Gtk.MenuButton(tooltip_text="Avisos", relief=Gtk.ReliefStyle.NONE)
        wb = Gtk.Box(spacing=4)
        wb.pack_start(icon("dialog-warning-symbolic"), False, False, 0)
        self.warn_num = label("0", "nv-aviso-num", valign=Gtk.Align.CENTER)
        wb.pack_start(self.warn_num, False, False, 0)
        self.warn_btn.add(wb)
        # (el boton no se muestra con show_all: lo de dentro, si, o saldria vacio al aparecer)
        wb.show_all()
        pop = Gtk.Popover(relative_to=self.warn_btn)
        sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, propagate_natural_height=True,
                                max_content_height=560)
        self.warn_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16, margin=12)
        self.warn_box.set_size_request(560, -1)
        sw.add(self.warn_box)
        sw.show_all()
        pop.add(sw)
        self.warn_btn.set_popover(pop)
        self.warn_btn.set_no_show_all(True)
        # Tarea en segundo plano: una flecha verde que late, con su porcentaje; al pulsarla, su ventana
        self.bg_task = None
        self.task_badge = css(Gtk.Button(valign=Gtk.Align.CENTER), "nv-tarea-fondo")
        tb = Gtk.Box(spacing=5)
        tb.pack_start(css(logo("descarga", 16), "nv-tarea-flecha"), False, False, 0)
        self.task_badge_lbl = label("", "nv-chico", "nv-mono")
        tb.pack_start(self.task_badge_lbl, False, False, 0)
        self.task_badge.add(tb)
        tb.show_all()
        self.task_badge.set_no_show_all(True)
        self.task_badge.connect("clicked", lambda *_: self.bg_task and self.bg_task.to_front())
        # Los avisos, a la izquierda del visor, y el menu, justo a su derecha (antes de Localhost)
        center = Gtk.Box(spacing=10, valign=Gtk.Align.CENTER)
        center.pack_start(self.task_badge, False, False, 0)
        center.pack_start(self.warn_btn, False, False, 0)
        center.pack_start(pill, False, False, 0)
        center.pack_start(self.menu_btn, False, False, 0)
        hb.set_custom_title(center)
        # Terminal: la de abajo de la ventana, que se enseña y se esconde (en lugar de Localhost; phpMyAdmin
        # ya está en la pestaña Bases de datos)
        self.term_btn = Gtk.ToggleButton(relief=Gtk.ReliefStyle.NONE, valign=Gtk.Align.CENTER,
                                         tooltip_text="Mostrar u ocultar la terminal")
        tbox = Gtk.Box(spacing=6)
        tbox.pack_start(icon("utilities-terminal-symbolic", 16), False, False, 0)
        tbox.pack_start(Gtk.Label(label="Terminal"), False, False, 0)
        self.term_btn.add(tbox)
        self.term_btn.connect("toggled", lambda b: self.nv_term_show(b.get_active()))
        hb.pack_end(self.term_btn)
        # Correo de pruebas: la bandeja de Mailpit, plano como Terminal y con los correos sin leer (se
        # pregunta solo con la ventana activa). Con el correo de pruebas apagado no sale
        self.mail_btn = Gtk.Button(relief=Gtk.ReliefStyle.NONE, valign=Gtk.Align.CENTER)
        mbox = Gtk.Box(spacing=6)
        mbox.pack_start(logo("mailpit", 18), False, False, 0)
        mbox.pack_start(Gtk.Label(label="Correo"), False, False, 0)
        self.mail_num = label("0", "nv-correo-num", valign=Gtk.Align.CENTER)
        mbox.pack_start(self.mail_num, False, False, 0)
        mbox.show_all()
        self.mail_num.set_no_show_all(True)
        self.mail_num.hide()
        self.mail_btn.add(mbox)
        self.mail_btn.connect("clicked", lambda *_: self.nv_open_mail())
        self.mail_btn.set_no_show_all(True)
        hb.pack_end(self.mail_btn)
        return hb

    # ------------------------------------------------------------------ terminal (abajo de la ventana)
    def nv_term_panel(self):
        """La terminal de abajo: con el aspecto del visor de arriba, un poco hundida. La de verdad (VTE, la de
        la Terminal de GNOME) se crea la primera vez que se enseña; sigue viva al esconderla."""
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6), "nv-terminal")
        box.set_size_request(-1, 120)
        head = Gtk.Box(spacing=8)
        head.pack_start(icon("utilities-terminal-symbolic", 14), False, False, 0)
        head.pack_start(label("Terminal", "nv-chico"), False, False, 0)
        self.term_where = label("", "nv-chico", "nv-tenue")
        self.term_where.set_ellipsize(2)  # Pango.EllipsizeMode.MIDDLE
        head.pack_start(self.term_where, True, True, 0)
        b = nv_button("folder-symbolic", "Proyecto cargado", "Ir a la carpeta del proyecto cargado (cd)",
                      lambda *_: self.nv_term_cd(), flat=True)
        head.pack_end(nv_button("window-close-symbolic", None, "Esconder la terminal (sigue abierta)",
                                lambda *_: self.term_btn.set_active(False), flat=True), False, False, 0)
        head.pack_end(nv_button("view-refresh-symbolic", None, "Terminal nueva (cierra la de ahora)",
                                lambda *_: self.nv_term_spawn(restart=True), flat=True), False, False, 0)
        head.pack_end(b, False, False, 0)
        head.pack_end(nv_button("edit-clear-all-symbolic", "Vaciar DNS",
                                "Vaciar la caché DNS",
                                lambda *_: self.nv_term_type("sudo resolvectl flush-caches"), flat=True),
                      False, False, 0)
        box.pack_start(head, False, False, 0)
        self.term_slot = Gtk.Box()
        box.pack_start(self.term_slot, True, True, 0)
        box.show_all()
        box.set_no_show_all(True)
        box.hide()
        self.term_panel, self.term = box, None
        return box

    def nv_term_show(self, on):
        if on:
            if self.term is None and not self.nv_term_spawn():
                self.term_btn.set_active(False)
                return
            first = not self.term_panel.get_visible()
            self.term_panel.show()
            if first:
                # (un tercio de la ventana, como poco 220 px)
                h = self.term_paned.get_allocated_height()
                self.term_paned.set_position(max(200, h - max(220, h // 3)))
            self.term.grab_focus()
        else:
            self.term_panel.hide()

    def nv_term_project(self):
        p = self.projects or {}
        # (gui-proyectos da la carpeta como la tiene el enlace de web.local: su nombre, dentro de los proyectos)
        cur = (p.get("current") or "").rstrip("/")
        cur = os.path.join(HTDOCS, cur) if cur else ""
        return cur if cur and os.path.isdir(cur) else HTDOCS

    def nv_term_spawn(self, restart=False):
        """La terminal: tu shell, con tu usuario, en la carpeta del proyecto cargado (o de los proyectos)."""
        try:
            gi.require_version("Vte", "2.91")
            from gi.repository import Pango, Vte
        except (ValueError, ImportError):
            message(self.win, "Falta la terminal de GNOME (VTE)",
                    "Para la terminal de la ventana hace falta su componente. En una terminal:\n\n"
                    "sudo apt install gir1.2-vte-2.91", Gtk.MessageType.INFO)
            return False
        if self.term is not None:
            if not restart:
                return True
            self.term_slot.remove(self.term)
            self.term.destroy()
            self.term = None
        t = css(Vte.Terminal(), "nv-terminal-vte")
        t.set_scrollback_lines(10000)
        t.set_font(Pango.FontDescription("Monospace 10.5"))
        bg, fg = Gdk.RGBA(), Gdk.RGBA()
        bg.parse("#1D2228")
        fg.parse("#D7DEE6")
        # (colores que se leen bien sobre el fondo oscuro del visor: el azul de las carpetas, más claro)
        palette = []
        for c in ("#1D2228", "#E06C75", "#98C379", "#E5C07B", "#61AFEF", "#C678DD", "#56B6C2", "#D7DEE6",
                  "#5C6370", "#EF8A92", "#B5DC97", "#F0D49B", "#8CC8F7", "#DDA3EC", "#7FD3DD", "#FFFFFF"):
            rgba = Gdk.RGBA()
            rgba.parse(c)
            palette.append(rgba)
        t.set_colors(fg, bg, palette)
        t.set_hexpand(True)
        t.set_vexpand(True)
        # (al terminar el shell, se esconde; al volver a enseñarla, otra nueva)
        t.connect("child-exited", lambda *_: GLib.idle_add(self.nv_term_exited))
        # (copiar y pegar como en la Terminal de GNOME: Ctrl+Mayús+C/V, Ctrl/Mayús+Insert y el botón derecho)
        t.connect("key-press-event", self.nv_term_key)
        t.connect("button-press-event", self.nv_term_click)
        cwd = self.nv_term_project()
        import pwd
        shell = os.environ.get("SHELL") or pwd.getpwuid(os.getuid()).pw_shell or "/bin/bash"
        if not os.path.isabs(shell) or not os.access(shell, os.X_OK):
            shell = "/bin/bash"
        t.spawn_async(Vte.PtyFlags.DEFAULT, cwd, [shell], None, GLib.SpawnFlags.DEFAULT, None, None, -1, None, None)
        sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        sw.add(t)
        self.term_slot.pack_start(sw, True, True, 0)
        sw.show_all()
        self.term, self.term_sw = sw, t
        self.term_where.set_label(cwd)
        return True

    def nv_term_copy(self):
        t = self.term_sw
        if not t.get_has_selection():
            return
        try:
            from gi.repository import Vte
            t.copy_clipboard_format(Vte.Format.TEXT)
        except (AttributeError, ImportError):
            t.copy_clipboard()

    def nv_term_paste(self):
        self.term_sw.paste_clipboard()
        self.term_sw.grab_focus()

    def nv_term_key(self, t, ev):
        mods = ev.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK)
        both = Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK
        key = Gdk.keyval_to_lower(ev.keyval)
        if (mods == both and key == Gdk.KEY_c) or (mods == Gdk.ModifierType.CONTROL_MASK and key == Gdk.KEY_Insert):
            self.nv_term_copy()
            return True
        if (mods == both and key == Gdk.KEY_v) or (mods == Gdk.ModifierType.SHIFT_MASK and key == Gdk.KEY_Insert):
            self.nv_term_paste()
            return True
        return False

    def nv_term_click(self, t, ev):
        if ev.type != Gdk.EventType.BUTTON_PRESS or ev.button != 3:
            return False
        menu = Gtk.Menu()
        clip = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        for text, keys, sensitive, cb in (
                ("Copiar", "<Control><Shift>c", t.get_has_selection(), self.nv_term_copy),
                ("Pegar", "<Control><Shift>v", clip.wait_is_text_available(), self.nv_term_paste),
                ("Seleccionar todo", None, True, t.select_all)):
            item = Gtk.MenuItem(label=text)
            if keys:
                item.get_child().set_accel(*Gtk.accelerator_parse(keys))
            item.set_sensitive(sensitive)
            item.connect("activate", lambda _i, f=cb: f())
            menu.append(item)
        menu.show_all()
        menu.attach_to_widget(t, None)
        menu.popup_at_pointer(ev)
        return True

    def nv_term_exited(self):
        if self.term is not None:
            self.term_slot.remove(self.term)
            self.term.destroy()
            self.term = None
        self.term_btn.set_active(False)
        return False

    def nv_term_cd(self):
        """cd a la carpeta del proyecto cargado (escrito en la terminal, como si lo tecleara)."""
        if self.term is None:
            return
        cwd = self.nv_term_project()
        self.nv_term_type("cd %s" % shlex.quote(cwd))
        self.term_where.set_label(cwd)

    def nv_term_type(self, cmd):
        """Escribe una orden en la terminal y la manda, como si se tecleara."""
        if self.term is None:
            return
        self.term_sw.feed_child((cmd + "\n").encode())
        self.term_sw.grab_focus()

    def nv_theme(self):
        """Claro u oscuro, solo en esta ventana (se recuerda). Con un tema que ya es oscuro de por si
        (Yaru-...-dark), preferir el oscuro no cambia nada: se cambia a su variante clara."""
        self.nv_apply_theme(not self.nv_is_dark())
        # (se redibuja lo que lleva logotipos con el color del fondo)
        if self.data:
            self.build_versions()
            self.build_databases()
            self.build_tools()
            self.nv_build_projects()
        if self.docker is not None:
            self.build_docker()
        try:
            os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
            with open(THEME_FILE, "w", encoding="utf-8") as f:
                f.write("oscuro\n" if self.nv_is_dark() else "claro\n")
        except OSError:
            pass

    def nv_is_dark(self):
        s = Gtk.Settings.get_default()
        return s.get_property("gtk-theme-name").lower().endswith("-dark") \
            or s.get_property("gtk-application-prefer-dark-theme")

    def nv_apply_theme(self, dark):
        s = Gtk.Settings.get_default()
        name = s.get_property("gtk-theme-name")
        base = name[:-5] if name.lower().endswith("-dark") else name
        if dark:
            # (la variante -dark si el tema la tiene; si no, el oscuro del propio tema)
            if theme_exists(base + "-dark"):
                s.set_property("gtk-theme-name", base + "-dark")
                s.set_property("gtk-application-prefer-dark-theme", False)
            else:
                s.set_property("gtk-theme-name", base)
                s.set_property("gtk-application-prefer-dark-theme", True)
        else:
            s.set_property("gtk-theme-name", base if theme_exists(base) else "Adwaita")
            s.set_property("gtk-application-prefer-dark-theme", False)
        # (lo que cambia de color con el tema claro: .nv-claro en la ventana)
        if getattr(self, "win", None) is not None:
            ctx = self.win.get_style_context()
            (ctx.remove_class if dark else ctx.add_class)("nv-claro")
        # (los logotipos que dependen del fondo, con su color de nuevo)
        _logo_cache.clear()
        if getattr(self, "theme_item", None):
            img, lbl = self.theme_item
            img.set_from_icon_name("weather-clear-symbolic" if dark else "weather-clear-night-symbolic",
                                   Gtk.IconSize.BUTTON)
            lbl.set_label("Tema claro" if dark else "Tema oscuro")

    def nv_power(self):
        d = self.data
        if not d or not d["active"]:
            self.show_tab("versiones")
            return
        self.on_control(None, "parar" if d["running"] else "arrancar",
                        "Parar y desactivar" if d["running"] else "Arrancar")

    def nv_task_badge(self, task):
        """El aviso de la tarea en segundo plano (None: se quita)."""
        self.bg_task = task
        if task is None:
            self.task_badge.hide()
            return
        self.nv_task_badge_tick(task)
        self.task_badge.show()
        GLib.timeout_add(700, self.nv_task_badge_tick, task)

    def nv_task_badge_tick(self, task):
        if self.bg_task is not task or task.finished:
            return False
        m = re.search(r"\d+ ?%", task.pct.get_label() or "")
        # (lo que hace, con la primera palabra del título: «Actualizando…», «Instalando…»)
        verb = (task.dlg.get_title() or "En marcha").split()[0].rstrip(".,:")
        self.task_badge_lbl.set_label("%s…%s" % (verb, "  " + m.group(0) if m else ""))
        self.task_badge.set_tooltip_text("%s\n%s\nPulsa para ver la ventana" % (
            task.dlg.get_title(), task.what.get_label() or "En marcha"))
        return True

    def nv_sidebar(self):
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4), "nv-lateral")
        box.set_size_request(230, -1)
        self.side_box, self.tabs, self.tab_lists = box, {}, []
        self.foot = label("", "nv-chico", "nv-tenue", xalign=0.5, wrap=True, max_width_chars=26, margin=12)
        box.pack_end(self.foot, False, False, 0)
        self.nv_sidebar_fill()
        return box

    def nv_sidebar_fill(self):
        """Los apartados del menú lateral, como diga Apariencia (también al cambiarla: solo se rehace esto)."""
        box, look = self.side_box, look_conf()
        current = next((lb.get_selected_row().tab_name for lb in self.tab_lists if lb.get_selected_row()), "proyectos")
        for w in box.get_children():
            if w is not self.foot:
                w.destroy()
        self.tabs, self.tab_lists = {}, []
        for group_name, items in SIDEBAR:
            items = [it for it in items if it[0] in SIDEBAR_FIXED or it[0] not in look["ocultos"]]
            if not items:
                continue
            box.pack_start(label(group_name, "nv-seccion", margin_start=22, margin_top=16, margin_bottom=2), False, False, 0)
            lb = css(Gtk.ListBox(), "nv-nav")
            for name, text, ic in items:
                row = Gtk.ListBoxRow()
                inner = Gtk.Box(spacing=12)
                if look["marcas"] and name in ("docker", "node"):
                    # (el logotipo con su nombre, en su tipografía: ya dice qué es)
                    inner.pack_start(BrandLogo(name, 22 if name == "docker" else 20, mono=not look["color"]), False, False, 0)
                else:
                    if look["marcas"] and look["color"] and name == "versiones":
                        w = BrandLogo("php", 20)
                    elif ic.startswith("logo:"):
                        # (en color, cada uno el suyo; si no, de un color, como los iconos del tema)
                        w = MonoLogo(ic[5:], 20, colored=look["color"] and ic != "logo:github")
                    else:
                        w = symbol(ic, 20)
                        if look["color"]:
                            css(w, "nv-tinte-" + name)
                    inner.pack_start(w, False, False, 0)
                    inner.pack_start(label(text), False, False, 0)
                row.add(inner)
                row.tab_name = name
                lb.add(row)
                self.tabs[name] = (lb, row)
            lb.connect("row-selected", self.nv_on_tab)
            self.tab_lists.append(lb)
            box.pack_start(lb, False, False, 0)
        box.show_all()
        lb, row = self.tabs.get(current) or self.tabs["proyectos"]
        lb.select_row(row)

    def nv_look_set(self, key, value):
        conf = look_conf()
        if key.startswith("@"):
            (conf["ocultos"].discard if value else conf["ocultos"].add)(key[1:])
        else:
            conf[key] = value
        look_save(conf)
        self.nv_sidebar_fill()

    def nv_look_tools(self):
        """Configuración, Apariencia: en tres bloques, cada uno con su título, porque hacen cosas distintas:
        cómo se ve el menú lateral, qué apartados salen en él y los botones del visor de los proyectos."""
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=26)
        head = Gtk.Box(spacing=6)
        head.pack_start(label("Apariencia", "grupo-titulo"), False, False, 0)
        head.pack_start(info_icon("Cómo se ve la ventana. Se guarda al momento y vale también para la versión de Mac."),
                        False, False, 0)
        page.pack_start(head, False, False, 0)
        look = look_conf()

        def block(title, sub):
            b = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            b.pack_start(label(title, "nv-apartado-titulo", xalign=0), False, False, 0)
            b.pack_start(label(sub, "dim-label", "subtitulo", xalign=0, wrap=True), False, False, 0)
            lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, margin_top=8), "caja")
            lb.connect("row-activated", on_row_activated)
            b.pack_start(lb, False, False, 0)
            page.pack_start(b, False, False, 0)
            return lb

        def switch(lb, title, sub, key, on):
            row = ActionRow(title, sub)
            s = Gtk.Switch(active=on, valign=Gtk.Align.CENTER)
            s.connect("notify::active", lambda w, _p: self.nv_look_set(key, w.get_active()))
            row.add_suffix(s)
            lb.add(row)
        lb = block("Iconos del menú lateral", "Cómo se dibujan los iconos de la columna de la izquierda")
        switch(lb, "Iconos en color", "Cada apartado con su color; apagado, de un color, como el texto",
               "color", look["color"])
        switch(lb, "Logotipos de Docker, Node y PHP", "Con su logotipo y su tipografía en lugar del nombre",
               "marcas", look["marcas"])
        lb = block("Apartados del menú lateral",
                   "Cuáles se ven en la columna de la izquierda (Proyectos y Configuración salen siempre)")
        for _g, items in SIDEBAR:
            for name, text, _ic in items:
                if name not in SIDEBAR_FIXED:
                    switch(lb, text, None, "@" + name, name not in look["ocultos"])
        lb = block("Visor de los proyectos", "Los botones de cada proyecto: cuáles se ven, en qué orden y cómo")
        conf = buttons_conf()
        shown = [n for k, n, _i in sorted(VISOR_BUTTONS, key=lambda b: conf["order"].index(b[0])) if k not in conf["hidden"]]
        row = ActionRow("Botones", "%s · %s" % (", ".join(shown) or "ninguno",
                                                dict(BUTTON_STYLES)[conf["style"]].split(":")[0].lower()))
        b = Gtk.Button(label="Personalizar…", valign=Gtk.Align.CENTER)
        b.connect("clicked", lambda *_: self.nv_buttons_dialog())
        row.add_suffix(b)
        lb.add(row)
        self.tools_box.pack_start(page, False, False, 0)

    def nv_on_tab(self, lb, row):
        if row is None:
            return
        # (los logotipos dibujados cambian de color en la fila elegida: GTK no se lo dice, se repintan)
        self.side_box.queue_draw()
        for other in self.tab_lists:
            if other is not lb:
                other.unselect_all()
        self.stack.set_visible_child_name(row.tab_name)
        # Al entrar en una pestaña, sus apartados desplegables aparecen plegados
        if any(k.startswith("@db") for k in self.expanded) or self.dk_open:
            self.expanded.difference_update({k for k in self.expanded if k.startswith("@db")})
            self.dk_open = set()
            if self.data:
                self.nv_db_table()
            if self.docker is not None:
                self.nv_dk_table()
        if row.tab_name == "docker":
            run_quick(["gui-docker"], self.on_docker_data)
            run_quick(["gui-docker-estadisticas"], self.on_docker_stats)
        elif row.tab_name == "bbdd":
            run_quick(["gui-bbdd-tamanos"], self.on_db_sizes)
        elif row.tab_name == "repos":
            self.nv_repos_open()
        elif row.tab_name == "node":
            self.nv_node_load()

    def on_tick(self):
        res = super().on_tick()
        # (escondida en el icono: solo lo que enseña su menú, cada minuto)
        if self.tray is not None and not self.win.get_visible() and not self.busy:
            self.tray_ticks = (self.tray_ticks + 1) % 3
            if self.tray_ticks == 0:
                run_quick(["gui-datos"], self.on_data)
        if not self.busy and self.win.is_active() and self.stack.get_visible_child_name() == "docker":
            run_quick(["gui-docker-estadisticas"], self.on_docker_stats)
        if self.win.is_active():
            self.nv_mail_poll()
        return res

    # ------------------------------------------------------------------ correo de pruebas (Mailpit)
    def nv_mail(self):
        return (self.data or {}).get("mail") or {}

    def nv_mail_header(self):
        """Botón Correo de arriba: oculto con el correo de pruebas apagado; sin Mailpit instalado o
        parado, lleva a Configuración o lo explica."""
        m = self.nv_mail()
        self.mail_btn.set_visible(bool(m.get("on")))
        if not m.get("installed"):
            tip = "Mailpit no está instalado"
        elif not m.get("running"):
            tip = "Arranca la versión activa para ver el correo"
        else:
            n = self.mail_unread
            tip = "Correo de las webs (Mailpit)%s" % (": %d sin leer" % n if n else "")
        self.mail_btn.set_tooltip_text(tip)
        if not m.get("running"):
            self.nv_mail_count(None)
        else:
            self.nv_mail_poll()

    def nv_mail_poll(self):
        """Pregunta a Mailpit cuántos correos hay sin leer (en segundo plano, sin proxy)."""
        m = self.nv_mail()
        if not (m.get("on") and m.get("running")) or self.mail_polling:
            return
        self.mail_polling = True
        url = m["url"] + "api/v1/info"

        def work():
            n = None
            try:
                import json
                import urllib.request
                opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
                with opener.open(url, timeout=3) as r:
                    n = int(json.loads(r.read(100000).decode("utf-8", "replace")).get("Unread", 0))
            except Exception:  # noqa: BLE001 - parado o sin responder: sin número
                n = None
            GLib.idle_add(self.nv_mail_count, n, True)
        threading.Thread(target=work, daemon=True).start()

    def nv_mail_count(self, n, polled=False):
        if polled:
            self.mail_polling = False
        self.mail_unread = n
        if n:
            self.mail_num.set_label("99+" if n > 99 else str(n))
            self.mail_num.show()
        else:
            self.mail_num.hide()
        if self.nv_mail().get("running"):
            self.mail_btn.set_tooltip_text("Correo de las webs (Mailpit)%s" % (": %d sin leer" % n if n else ""))
        return False

    def nv_open_mail(self):
        m = self.nv_mail()
        if not m.get("installed"):
            self.nv_tools_show("Correo de pruebas (Mailpit)")
            self.toast("Instala Mailpit en Configuración, apartado Correo de pruebas")
        elif not m.get("running"):
            self.toast("Mailpit arranca con la versión activa: arráncala arriba")
        elif self.nv_mail_webkit() is None or getattr(self, "mail_web_dead", False):
            # (sin el componente del visor, o si se ha caído: como antes, en el navegador)
            self.open_uri(m["url"])
            GLib.timeout_add_seconds(3, lambda: (self.nv_mail_poll(), False)[1])
        else:
            self.nv_tools_show("Correo de pruebas (Mailpit)")

    def nv_mail_webkit(self):
        """El módulo del visor web (WebKitGTK para GTK 3) o None si no está instalado. Se carga la primera
        vez que hace falta: tarda y la ventana arranca igual sin él."""
        if not hasattr(self, "mail_webkit"):
            self.mail_webkit = None
            for version in ("4.1", "4.0"):
                try:
                    gi.require_version("WebKit2", version)
                    from gi.repository import WebKit2
                    self.mail_webkit = WebKit2
                    break
                except (ImportError, ValueError):
                    continue
        return self.mail_webkit

    def nv_mail_web(self):
        """El visor de la bandeja, siempre el mismo (al rehacer la pestaña no se pierde el correo abierto):
        sin nada en disco y sin proxy, porque Mailpit está en este equipo."""
        web = getattr(self, "mail_web", None)
        kit = self.nv_mail_webkit()
        if web is not None or kit is None:
            return web
        data = kit.WebsiteDataManager.new_ephemeral()
        data.set_network_proxy_settings(kit.NetworkProxyMode.NO_PROXY, None)
        ctx = kit.WebContext.new_with_website_data_manager(data)
        web = kit.WebView.new_with_context(ctx)
        web.get_settings().set_javascript_can_open_windows_automatically(False)
        web.connect("decide-policy", self.nv_mail_policy)
        web.connect("load-failed", self.nv_mail_load_failed)
        web.connect("web-process-terminated", self.nv_mail_crashed)
        web.connect("destroy", self.nv_mail_destroyed)
        ctx.connect("download-started", self.nv_mail_download)
        # (también su contexto: si Python lo suelta, el visor carga la página pero no la pinta)
        self.mail_web, self.mail_web_url, self.mail_web_ctx = web, None, (data, ctx)
        # (mientras se ve, el número de sin leer de arriba sigue a lo que se lee o se borra aquí)
        GLib.timeout_add_seconds(5, self.nv_mail_tick, web)
        return web

    def nv_mail_tick(self, web):
        if getattr(self, "mail_web", None) is not web:
            return False
        if web.get_mapped():
            self.nv_mail_poll()
        return True

    def nv_mail_policy(self, _web, decision, kind):
        """Solo se navega dentro de Mailpit. Un enlace de un correo va al navegador, y solo si se ha pulsado:
        un correo no puede abrir nada por su cuenta."""
        kit = self.mail_webkit
        if kind == kit.PolicyDecisionType.RESPONSE:
            if decision.is_mime_type_supported():
                return False
            uri = decision.get_request().get_uri()
            decision.ignore()
            self.nv_mail_external(uri)
            return True
        action = decision.get_navigation_action()
        uri = action.get_request().get_uri() or ""
        new_window = kind == kit.PolicyDecisionType.NEW_WINDOW_ACTION
        if not new_window and (uri.startswith(("about:", self.mail_web_url or "\0", "blob:" + (self.mail_web_url or "\0")))):
            return False
        decision.ignore()
        if new_window and action.is_user_gesture() \
                or action.get_navigation_type() == kit.NavigationType.LINK_CLICKED:
            self.nv_mail_external(uri)
        return True

    def nv_mail_external(self, uri):
        if (uri or "").startswith(("http://", "https://")):
            self.open_uri(uri)

    def nv_mail_download(self, _ctx, download):
        """Un adjunto: lo descarga el navegador, que pregunta dónde guardarlo."""
        uri = download.get_request().get_uri()
        download.cancel()
        self.nv_mail_external(uri)

    def nv_mail_load_failed(self, *_):
        # (parado o sin responder: se vuelve a pedir la próxima vez que se vea en marcha)
        self.mail_web_url = None
        return False

    def nv_mail_destroyed(self, web):
        # (destruido, su página ya no vale: la próxima vez se crea otro)
        if getattr(self, "mail_web", None) is web:
            self.mail_web = None

    def nv_mail_crashed(self, *_):
        """El proceso del visor se ha caído o no puede arrancar: se ofrece el navegador."""
        self.mail_web_dead = True
        self.mail_web = None
        GLib.idle_add(lambda: (self.build_tools(), False)[1])

    def nv_mail_view(self, m):
        """Debajo de las tarjetas: la bandeja de Mailpit o por qué no se ve."""
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin_top=12), "caja")
        box.set_size_request(-1, 620)
        old = getattr(self, "mail_web", None)

        def note(text, command=None):
            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, valign=Gtk.Align.CENTER, vexpand=True, margin=24)
            inner.pack_start(label(text, "nv-tenue", wrap=True, xalign=0.5, justify=Gtk.Justification.CENTER), False, False, 0)
            if command:
                inner.pack_start(label(command, "nv-chico", selectable=True, xalign=0.5), False, False, 0)
            if m["running"]:
                b = Gtk.Button(label="Abrir en el navegador", halign=Gtk.Align.CENTER)
                b.connect("clicked", lambda *_: self.open_uri(m["url"]))
                inner.pack_start(b, False, False, 0)
            box.pack_start(inner, True, True, 0)
            return box
        if SIMULATE:
            return note("En la simulación no se abre la bandeja: desde ella se pueden borrar correos.")
        if not m["running"]:
            if old is not None:
                self.mail_web_url = None
            return note("Mailpit está parado: arranca con la versión activa.")
        if getattr(self, "mail_web_dead", False):
            return note("La bandeja no se puede ver dentro de la ventana en este equipo.")
        web = self.nv_mail_web()
        if web is None:
            return note("Para ver la bandeja dentro de la ventana falta su componente:", "sudo apt install gir1.2-webkit2-4.1")
        box.pack_start(web, True, True, 0)
        if self.mail_web_url != m["url"]:
            self.mail_web_url = m["url"]
            web.load_uri(m["url"])
        return box

    def nv_mail_tools(self):
        """Configuración, Correo de pruebas: encenderlo, el modo de WordPress y Mailpit."""
        m = self.nv_mail()
        if not m:
            return
        on = m["on"]
        sw = Gtk.Switch(active=on, valign=Gtk.Align.CENTER, sensitive=not self.busy,
                        tooltip_text="Encendido: el correo de las webs va a Mailpit" if on else
                        "Apagado: lo que manden las webs puede llegar de verdad a los clientes")
        sw.connect("notify::active", self.on_mail_switch)
        tail = Gtk.Box(spacing=8)
        tail.pack_start(sw, False, False, 0)
        if not on:
            tail.pack_start(label("Apagado: lo que manden las webs puede llegar de verdad a los clientes",
                                  "nv-chico", "nv-correo-aviso", valign=Gtk.Align.CENTER), False, False, 0)
        box, lb = tile_group("Correo de pruebas (Mailpit)", tiles=True, lead=logo("mailpit", 20), tail=tail,
                        description=
                        "Lo que mandan las webs de este equipo (formularios, pedidos, contraseñas) no llega a "
                        "nadie: va a Mailpit, que lo enseña en su bandeja. PHP (mail()) en todas las versiones, "
                        "PrestaShop por SMTP y WordPress según su opción. Lo que se cambia en las BBDD no va en "
                        "las copias que descargas (exportar-bd, copiar-bd, Docker). Mailpit arranca y para con "
                        "la versión activa y solo se ve desde este equipo.")
        texts = {"mailpit": "Siguen funcionando, con su correo a Mailpit (los que usan una API, como Brevo, se desactivan en la copia local)",
                 "desactivar": "Se desactivan en la copia local: WordPress manda con mail(), a Mailpit",
                 "nada": "⚠ No se tocan: lo que manden puede llegar de verdad a los clientes"}
        row = ActionRow("WordPress con plugins de SMTP o Brevo", texts.get(m["wp"], ""))
        row.add_prefix(logo("wordpress", 18))
        if m["wp"] == "nada":
            css(row.subtitle, "nv-correo-aviso")
        combo = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
        for key, text in (("mailpit", "Llevarlos a Mailpit"), ("desactivar", "Desactivarlos en la copia local"),
                          ("nada", "No tocarlos")):
            combo.append(key, text)
        combo.set_active_id(m["wp"])
        combo.set_tooltip_text("Qué hacer con sus plugins de correo")
        combo.set_sensitive(on and not self.busy)
        combo.connect("changed", self.on_mail_wp)
        row.add_suffix(combo)
        lb.add(row)
        if m["installed"]:
            sub = "Mailpit %s · %s" % (m["version"] or "?", ("en marcha: %s" % m["url"]) if m["running"]
                                       else "parado: arranca con la versión activa")
            row = ActionRow("Bandeja de entrada", sub)
            row.add_prefix(icon("mail-unread-symbolic", 16))
            if m["offer"] and m["version"] and ver_tuple(m["offer"]) > ver_tuple(m["version"]):
                b = css(Gtk.Button(label="Actualizar a %s" % m["offer"], valign=Gtk.Align.CENTER), "verde")
                b.connect("clicked", lambda *_: self.on_mail_install())
                b.set_sensitive(not self.busy)
                row.add_suffix(b)
            b = Gtk.Button(label="Vaciar", tooltip_text="Vaciar la bandeja", valign=Gtk.Align.CENTER,
                           sensitive=m["running"] and not self.busy)
            b.connect("clicked", lambda *_: self.on_mail_clear())
            row.add_suffix(b)
        else:
            row = ActionRow("Mailpit no está instalado",
                            "Sin él, el correo de las webs no sale ni se ve. Se descarga de GitHub (Mailpit %s) y se "
                            "comprueba antes de instalarlo" % (m["offer"] or ""))
            row.subtitle.set_line_wrap(True)
            row.subtitle.set_ellipsize(0)
            b = css(Gtk.Button(label="Instalar Mailpit", valign=Gtk.Align.CENTER, sensitive=not self.busy), "verde")
            b.connect("clicked", lambda *_: self.on_mail_install())
            row.add_suffix(b)
        lb.add(row)
        if m["installed"]:
            box.pack_start(self.nv_mail_view(m), True, True, 0)
        self.tools_box.pack_start(box, False, False, 0)
        self.tools_box.reorder_child(box, 2)
        box.show_all()

    def on_mail_switch(self, sw, _p):
        on = sw.get_active()
        m = self.nv_mail()
        if on == m.get("on"):
            return
        args = ["correo", "si" if on else "no"]
        if on and not m.get("installed"):
            # (la primera vez: se ofrece instalar Mailpit, que se descarga de GitHub)
            if confirm(self.win, "¿Instalar Mailpit?",
                       "El correo de las webs irá a Mailpit, que se descarga de GitHub (Mailpit %s, comprobado "
                       "antes de instalarlo). Sin él, el correo no sale ni se ve." % (m.get("offer") or ""),
                       "Instalar Mailpit"):
                args.append("--instalar")
        if not on and not confirm(self.win, "¿Apagar el correo de pruebas?",
                                  "Lo que manden las webs (pedidos, formularios, contraseñas) podrá llegar de verdad "
                                  "a los clientes de las BBDD copiadas.", "Apagarlo", destructive=True):
            sw.set_active(True)
            return
        self.run_task("Encendiendo el correo de pruebas" if on else "Apagando el correo de pruebas", args,
                      auto_close=True, done_text="Correo de pruebas %s" % ("encendido" if on else "apagado"),
                      on_done=lambda *_: self.build_tools())

    def on_mail_wp(self, combo):
        mode = combo.get_active_id()
        if not mode or mode == self.nv_mail().get("wp"):
            return
        names = {"mailpit": "llevados a Mailpit", "desactivar": "desactivados en la copia local", "nada": "sin tocar"}
        self.run_task("Plugins de correo de WordPress: %s" % names[mode], ["correo", "wordpress", mode],
                      auto_close=True, done_text="Plugins de correo de WordPress %s" % names[mode],
                      on_done=lambda *_: self.build_tools())

    def on_mail_install(self):
        self.run_task("Instalando Mailpit", ["correo", "instalar"], progress=True, auto_close=True,
                      done_text="Mailpit instalado", on_done=lambda *_: self.build_tools())

    def on_mail_clear(self):
        if not confirm(self.win, "¿Vaciar la bandeja de Mailpit?", "Se borran todos los correos que han mandado "
                       "las webs de este equipo.", "Vaciar la bandeja", destructive=True):
            return

        def done(rc, out):
            self.toast("Bandeja de Mailpit vacía" if rc == 0 else (out.strip().splitlines() or ["No se ha podido vaciar"])[-1])
            self.nv_mail_poll()
            return False
        run_quick(["correo", "vaciar"], done)

    def show_tab(self, name):
        name = {"hosts": "dominios", "herramientas": "config", "servicios": "versiones"}.get(name, name)
        if name in self.tabs:
            lb, row = self.tabs[name]
            lb.select_row(row)

    # ------------------------------------------------------------------ datos
    def on_data(self, rc, out):
        res = super().on_data(rc, out)
        d = self.data
        if d:
            act = next((i for i in d["installs"] if i["folder"] == d["active"]), None)
            self.status_lbl.set_label("PHP %s" % act["php"] if act else "Ninguna versión activa")
            self.status_sub.set_label("lampp-%s" % d["active"] if act else "")
            self.nv_power_state()
            self.nv_projects_refresh()
            self.nv_mail_header()
        self.nv_tray_update()
        return res

    def on_services_data(self, rc, out):
        res = super().on_services_data(rc, out)
        self.nv_power_state()
        return res

    def nv_power_state(self):
        """Puntos de Apache y MariaDB (de gui-servicios)."""
        d = self.data
        if not d:
            return
        svc = {s["name"]: s["running"] for s in (self.services or [])}
        for name, dt in self.svc_dots.items():
            on = svc.get(name.lower(), False) if svc else d["running"]
            ctx = dt.get_style_context()
            ctx.remove_class("nv-gris" if on else "nv-verde")
            ctx.add_class("nv-verde" if on else "nv-gris")
            (ctx.add_class if on else ctx.remove_class)("nv-latido")

    def update_project_search(self):
        # (la busqueda de siempre sigue funcionando por detras: la usa el asistente de proyecto nuevo)
        if getattr(self, "proj_results", None) is not None:
            super().update_project_search()
        self.nv_build_projects()

    def on_docker_data(self, rc, out):
        res = super().on_docker_data(rc, out)
        self.nv_projects_refresh()
        return res

    def nv_projects_refresh(self):
        """Rehace Proyectos solo si ha cambiado algo de lo que enseña: los datos, los proyectos y Docker (on_data
        y los demás solo los cambian si llega algo distinto) y el túnel abierto. Cada 20 s llegan los datos de
        siempre: rehacerla entera cada vez costaba unos 400 ms de la interfaz, varias veces por vuelta."""
        key = (self.data, self.projects, self.docker, repr(tunnel_state()))
        old = getattr(self, "nv_proj_key", None)
        if old is not None and all(a is b for a, b in zip(old[:3], key[:3])) and old[3] == key[3]:
            return
        self.nv_proj_key = key
        self.nv_build_projects()

    # ------------------------------------------------------------------ versiones y avisos
    def build_versions(self):
        # Los de siempre se construyen en una caja que no se ve: de ahi salen los avisos (todo lo que
        # va antes de Cargar proyecto), que pasan al boton de avisos de arriba
        clear(self.legacy_box)
        self.ver_box = self.legacy_box
        super().build_versions()
        clear(self.warn_box)
        n = 0
        for child in list(self.legacy_box.get_children()):
            if child is getattr(self, "proj_box", None):
                break
            self.legacy_box.remove(child)
            self.warn_box.pack_start(child, False, False, 0)
            n += 1
        self.nv_warn_refresh()
        if self.inst_box.get_parent() is self.legacy_box:
            self.legacy_box.remove(self.inst_box)
        self.nv_build_versions()

    def nv_branch(self, php):
        """Linea B (de gui-ramas) de la rama de una version de PHP, o None si no se ha consultado."""
        branch = ".".join(php.split(".")[:2])
        return next((f for f in (self.branches or []) if f[0] == "B" and len(f) > 2 and f[1] == branch), None)

    def on_branches(self, rc, out):
        res = super().on_branches(rc, out)
        if self.data:
            self.nv_build_versions()
        return res

    def nv_build_versions(self):
        clear(self.vers_page)
        d = self.data
        head = Gtk.Box(spacing=12)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        tl = Gtk.Box(spacing=10)
        tl.pack_start(logo("php", 34), False, False, 0)
        tl.pack_start(label("Versiones de PHP", "nv-titulo-grande"), False, False, 0)
        t.pack_start(tl, False, False, 0)
        t.pack_start(label("Cada versión con su Apache, MariaDB y sus propias BBDD. Soporte y parches, según php.net",
                           "nv-chico", "nv-tenue"), False, False, 0)
        head.pack_start(t, True, True, 0)
        head.pack_end(nv_button("list-add-symbolic", "Instalar versión…", None, lambda *_: self.nv_install_dialog(),
                                "nv-azul"), False, False, 0)
        head.pack_end(nv_button(logo("apache", 16), "Componentes", "Componentes de cada versión",
                                lambda *_: self.nv_components_dialog()), False, False, 0)
        self.vers_page.pack_start(head, False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "nv-grupo")
        widths = [240, 90, 230, 200, 60, 0]
        groups = [Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL) for _ in widths]

        def row(cells, head_row=False):
            r = Gtk.ListBoxRow(activatable=False)
            b = css(Gtk.Box(spacing=14), "nv-fila", *(["nv-cab"] if head_row else []))
            for n, c in enumerate(cells):
                w = c if isinstance(c, Gtk.Widget) else label(c.upper() if head_row else c)
                if widths[n]:
                    w.set_size_request(widths[n], -1)
                    groups[n].add_widget(w)
                b.pack_start(w, n == len(cells) - 1, True, 0)
            hover = getattr(cells[-1], "hover_button", None)
            if hover is not None:
                ev = Gtk.EventBox(above_child=False)
                ev.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
                ev.connect("enter-notify-event", lambda *_, h=hover: (h.set_opacity(1), False)[1])
                ev.connect("leave-notify-event", lambda _w, e, h=hover: (e.detail == Gdk.NotifyType.INFERIOR
                                                                          or h.set_opacity(0), False)[1])
                ev.add(b)
                r.add(ev)
            else:
                r.add(b)
            lb.add(r)
        row(["Versión", "PHP", "Soporte", "Último parche", "BBDD", ""], True)
        for inst in self.installs():
            folder = inst["folder"]
            act = folder == d["active"]
            date = self.php_dates.get(folder)
            name = Gtk.Box(spacing=8)
            name.pack_start(nv_dot(act and d["running"]), False, False, 0)
            nt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            tl = Gtk.Box(spacing=6)
            tl.pack_start(label("lampp-%s" % folder, "nv-mono"), False, False, 0)
            tl.pack_start(label({"XAMPP": "XAMPP", "propia": "propia"}.get(inst["kind"], "sobre XAMPP"),
                                "nv-etiqueta", valign=Gtk.Align.CENTER), False, False, 0)
            nt.pack_start(tl, False, False, 0)
            nt.pack_start(label(fmt_day(date[1]) if date and date[0] == inst["php"] else "/opt/lampp-%s" % folder,
                                "nv-chico", "nv-tenue"), False, False, 0)
            name.pack_start(nt, False, False, 0)
            name.set_tooltip_text("/opt/lampp-%s" % folder)
            # Soporte de su rama y su ultimo parche (de php.net: llegan aparte)
            f = self.nv_branch(inst["php"])
            sup = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
            patch = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
            newer = None
            if f is not None:
                st, a_end, s_end = branch_state(f)
                pill = state_pill(st, a_end, s_end)
                pill.set_halign(Gtk.Align.START)
                sup.pack_start(pill, False, False, 0)
                when = s_end if st == "security" else a_end if st == "stable" else ""
                if when:
                    sup.pack_start(label(("seguridad hasta %s" if st == "security" else "hasta %s") % fmt_month(when),
                                         "nv-chico", "nv-tenue"), False, False, 0)
                latest = f[2] if len(f) > 2 else ""
                if latest == inst["php"]:
                    patch.pack_start(label("Actualizado", "nv-verde", "nv-chico"), False, False, 0)
                elif latest and ver_tuple(latest) > ver_tuple(inst["php"]):
                    newer = latest
                    patch.pack_start(label("PHP %s disponible" % latest, "nv-chico", "nv-enlace"), False, False, 0)
                    ldate, _sec = branch_release(f)
                    if ldate and ldate != "-":
                        patch.pack_start(label(fmt_day(ldate), "nv-chico", "nv-tenue"), False, False, 0)
                else:
                    patch.pack_start(label("—", "nv-tenue"), False, False, 0)
            else:
                sup.pack_start(label("consultando php.net…" if self.branches is None else "—", "nv-chico", "nv-tenue"), False, False, 0)
                patch.pack_start(label("—", "nv-tenue"), False, False, 0)
            # PHP2Shell (gui-datos, R|): en rojo si no tiene el arreglo
            p2s, p2s_why = d.get("php2shell", {}).get(folder, ("", ""))
            if p2s == "vulnerable":
                vul = label("Vulnerable (PHP2Shell)", "nv-chico", "error")
                vul.set_halign(Gtk.Align.START)
                vul.set_tooltip_text("Vulnerable: actualízala en el menú ⋮")
                patch.pack_start(vul, False, False, 0)
                patch.reorder_child(vul, 0)
                # (vulnerable no está «Actualizado», aunque tenga el último parche de su rama)
                for w in patch.get_children():
                    if isinstance(w, Gtk.Label) and w.get_text() == "Actualizado":
                        patch.remove(w)
            php_cell = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
            php_cell.pack_start(label(inst["php"], "nv-mono"), False, False, 0)
            if p2s == "parche":
                ps = label("+ parche de seguridad (oct 2026)", "nv-chico", "nv-verde")
                ps.set_tooltip_text("Parche oficial contra PHP2Shell")
                php_cell.pack_start(ps, False, False, 0)
            right = Gtk.Box(spacing=2, halign=Gtk.Align.END)
            if act:
                b = css(Gtk.Button(label="Activa", sensitive=False), "nv-activa")
            else:
                # (como «Cargar» en Proyectos: solo en la version con el raton encima)
                b = css(Gtk.Button(label="Activar", sensitive=not self.busy), "nv-azul")
                b.connect("clicked", self.on_activate_version, folder)
                b.set_opacity(0)
            b.set_size_request(96, -1)
            right.pack_start(b, False, False, 0)
            right.pack_start(self.nv_version_menu(inst, newer), False, False, 0)
            if not act:
                right.hover_button = b
            dbs = len(d["dbs"].get(folder, []))
            row([name, php_cell, sup, patch,
                 label(str(dbs) if inst["owner"] == folder else "→ %s" % inst["owner"], "nv-mono", "nv-tenue"), right])
        if not self.installs():
            row([label("Ninguna versión instalada: instala la primera")] + [label("") for _ in range(5)])
        self.vers_page.pack_start(lb, False, False, 0)
        self.vers_page.show_all()

    def nv_version_menu(self, inst, newer=None):
        folder = inst["folder"]
        m = Gtk.MenuButton(relief=Gtk.ReliefStyle.NONE)
        m.add(icon("view-more-symbolic"))
        pop = Gtk.Popover(relative_to=m)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=4)
        items = [("Componentes…", lambda: self.nv_components_dialog(inst))]
        # Actualizar solo si hay un parche mas nuevo y la version se pone al dia en su carpeta (las
        # lampp-X.Y de antes); sin datos de php.net, se comprueba al pulsar
        updatable = inst["kind"] != "XAMPP" and inst["php"].rsplit(".", 1)[0] == folder
        if updatable and (newer or self.nv_branch(inst["php"]) is None
                          or self.data.get("php2shell", {}).get(folder, ("",))[0] == "vulnerable"):
            items.append(("Actualizar a PHP %s" % newer if newer else "Buscar parches nuevos",
                          lambda: self.nv_update(folder)))
        elif not updatable:
            # Las que no se ponen al dia en su carpeta (lampp-X.Y.Z y los XAMPP): la nueva, al lado
            target = self.nv_fix_target(inst)
            if target:
                items.append(("Actualizar a PHP %s%s" % (target, " + parche de seguridad" if target in PHP2SHELL_BACKPORTS else ""),
                              lambda: self.nv_upgrade_to(inst, target)))
        if pma_outdated(inst["php"], inst["pma"]):
            items.append(("Actualizar phpMyAdmin", lambda: self.on_update_pma(folder)))
        items.append(("Desinstalar…", lambda: self.on_remove(None, inst) if not inst["blocker"]
                      else message(self.win, "No se puede desinstalar", inst["blocker"], Gtk.MessageType.INFO)))
        for text, fn in items:
            b = Gtk.ModelButton(text=text)
            b.connect("clicked", lambda *_, fn=fn: fn())
            box.pack_start(b, False, False, 0)
        box.show_all()
        pop.add(box)
        m.set_popover(pop)
        return m

    def nv_fix_target(self, inst):
        """PHP al que se puede pasar una version que no se actualiza en su carpeta: el ultimo parche
        de su rama si es mas nuevo o, si es un XAMPP o le falta el arreglo de PHP2Shell, aunque sea
        el mismo (7.4.33 de XAMPP -> pila propia 7.4.33 con el parche de seguridad). None si no hay."""
        f = self.nv_branch(inst["php"])
        latest = f[2] if f is not None and len(f) > 2 else ""
        if not re.fullmatch(r"\d+\.\d+\.\d+", latest):
            return None
        st = self.data.get("php2shell", {}).get(inst["folder"], ("",))[0]
        if ver_tuple(latest) > ver_tuple(inst["php"]):
            return latest
        if latest == inst["php"] and (inst["kind"] == "XAMPP" or st == "vulnerable"):
            return latest
        return None

    def nv_upgrade_to(self, inst, target):
        folder = inst["folder"]
        same = target == folder
        dbs = len(self.data["dbs"].get(folder, [])) if inst["owner"] == folder else 0
        fix = " con el parche de seguridad de PHP2Shell" if target in PHP2SHELL_BACKPORTS else ""
        have = next((i["folder"] for i in self.installs() if i["php"] == target and i["kind"] != "XAMPP"
                     and i["folder"] != folder), None)
        if have and not same:
            text = ("PHP %s ya está en lampp-%s: se le copian %s de lampp-%s con sus vínculos a las carpetas "
                    "de los proyectos%s. lampp-%s no se toca: desinstálala cuando compruebes que todo va bien."
                    % (target, have, plural(dbs, "BBDD", "BBDD") if dbs else "las BBDD (ahora no tiene ninguna)", folder,
                       " y, como es la activa, se activa lampp-%s" % have if folder == self.data["active"] else "",
                       folder))
        elif same:
            text = ("Se vuelve a compilar PHP %s%s en su carpeta, con la última pila de su rama. Conserva "
                    "sus BBDD si su MariaDB sigue en la misma rama (si no, guarda antes una copia en "
                    "~/lvm-copias). Tarda varios minutos." % (target, fix))
        else:
            text = ("Se instala PHP %s%s en lampp-%s, al lado de lampp-%s, que no se toca. Después se le copian "
                    "%s con sus vínculos a las carpetas de los proyectos%s. Cuando compruebes que todo va bien "
                    "con lampp-%s, desinstala lampp-%s (menú ⋮, Desinstalar). Tarda varios minutos."
                    % (target, fix, target, folder, plural(dbs, "BBDD", "BBDD") if dbs else "sus BBDD (ahora no tiene ninguna)",
                       " y, como es la activa, se activa la nueva" if folder == self.data["active"] else "",
                       target, folder))
        if not confirm(self.win, "¿Actualizar lampp-%s a PHP %s?" % (folder, target), text, "Actualizar"):
            return
        self.run_task("lampp-%s → PHP %s" % (folder, target), ["actualizar-a", folder, target],
                      progress=True, reload_branches=True,
                      done_text="PHP %s instalada%s" % (target, "" if same else " con las BBDD de lampp-%s" % folder))

    def nv_update(self, folder):
        """Actualizar una version (como on_update), diciendo en un mensaje si ya esta al dia."""
        self.toast("Comprobando si hay una versión más nueva…")

        def checked(_rc, out):
            res = out.strip().splitlines()[-1].split("|") if out.strip() else ["error"]
            if res[0] == "si":
                message(self.win, "lampp-%s ya está actualizada" % folder,
                        "Tiene el último parche de su rama (%s)." % (res[1] if len(res) > 1 else ""),
                        Gtk.MessageType.INFO)
            elif res[0] == "no" and len(res) > 1:
                if confirm(self.win, "¿Actualizar lampp-%s?" % folder,
                           "PHP %s con los últimos parches de su rama. La actual sigue funcionando "
                           "mientras se compila (varios minutos)." % res[1], "Actualizar a PHP %s" % res[1]):
                    self.run_task("Actualizando lampp-%s" % folder, ["actualizar", folder],
                                  progress=True, reload_branches=True,
                                  done_text="lampp-%s actualizada a PHP %s" % (folder, res[1]))
            elif res[0] == "parche":
                message(self.win, "lampp-%s no se actualiza en su carpeta" % folder,
                        "Es un parche concreto: instala el nuevo aparte con «Instalar versión…».",
                        Gtk.MessageType.INFO)
            else:
                message(self.win, "No se ha podido comprobar la versión",
                        "No se ha podido consultar php.net. Comprueba la conexión a internet.",
                        Gtk.MessageType.WARNING)
            return False
        run_quick(["gui-al-dia", folder], checked)

    def nv_components_dialog(self, only=None):
        """Componentes de cada version en una tabla, con el logotipo de cada uno en color."""
        dlg = Gtk.Dialog(title="Componentes", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(900, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        dlg.get_content_area().add(box)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "nv-grupo")
        widths = [150, 84, 84, 92, 78, 78, 92]
        groups = [Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL) for _ in widths]

        def row(cells, head_row=False):
            r = Gtk.ListBoxRow(activatable=False)
            b = css(Gtk.Box(spacing=14), "nv-fila", *(["nv-cab"] if head_row else []))
            for n, w in enumerate(cells):
                w.set_size_request(widths[n], -1)
                groups[n].add_widget(w)
                b.pack_start(w, n == len(cells) - 1, True, 0)
            r.add(b)
            lb.add(r)

        def head(text, spec):
            h = Gtk.Box(spacing=6)
            h.pack_start(logo(spec, 16) if spec in LOGO_PATHS else icon(spec, 16), False, False, 0)
            h.pack_start(label(text.upper()), False, False, 0)
            return h
        row([label("VERSIÓN"), head("PHP", "php"), head("Apache", "apache"), head("MariaDB", "mariadb"),
             head("FTP", "folder-remote-symbolic"), head("Perl", "perl"), head("PMA", "phpmyadmin")], True)
        for inst in self.installs():
            if only is not None and inst["folder"] != only["folder"]:
                continue
            pma = label(inst["pma"], "nv-mono", "nv-chico")
            if pma_outdated(inst["php"], inst["pma"]):
                pma.get_style_context().add_class("error")
                pma.set_tooltip_text("phpMyAdmin antiguo: actualízalo en ⋮")
            row([label("lampp-%s" % inst["folder"], "nv-mono"), label(inst["php"], "nv-mono"),
                 label(inst["apache"], "nv-mono", "nv-chico"), label(inst["mariadb"], "nv-mono", "nv-chico"),
                 label(inst["ftp"], "nv-mono", "nv-chico"), label(inst["perl"], "nv-mono", "nv-chico"), pma])
        box.pack_start(lb, False, False, 0)
        dlg.add_button("Cerrar", Gtk.ResponseType.CLOSE)
        box.show_all()
        run_dialog(dlg)
        dlg.destroy()

    def nv_install_dialog(self):
        dlg = Gtk.Dialog(title="Instalar versión", transient_for=self.win, modal=False, use_header_bar=True)
        dlg.set_default_size(760, 680)
        sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
        if self.inst_box.get_parent():
            self.inst_box.get_parent().remove(self.inst_box)
        self.inst_box.set_margin_start(20)
        self.inst_box.set_margin_end(20)
        self.inst_box.set_margin_top(12)
        sw.add(self.inst_box)
        dlg.get_content_area().pack_start(sw, True, True, 0)
        dlg.connect("destroy", lambda *_: self.inst_box.get_parent() and
                    self.inst_box.get_parent().remove(self.inst_box))
        dlg.show_all()

    # ------------------------------------------------------------------ Proyectos
    def nv_build_projects_shell(self):
        self.hero_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.proj_page.pack_start(self.hero_box, False, False, 0)
        head = Gtk.Box(spacing=10, margin_top=10)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        t.pack_start(label("Proyectos", "nv-titulo"), False, False, 0)
        head.pack_start(t, True, True, 0)
        self.nv_search = Gtk.SearchEntry(placeholder_text="Buscar proyecto", width_chars=22, valign=Gtk.Align.CENTER)
        self.nv_search.connect("search-changed", lambda *_: self.nv_list.invalidate_filter())
        self.nv_kind = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
        for k, v in [("all", "Todos"), ("wp", "WordPress"), ("ps", "PrestaShop"), ("", "Otros")]:
            self.nv_kind.append(k or "otros", v)
        self.nv_kind.set_active_id("all")
        self.nv_kind.connect("changed", lambda *_: self.nv_list.invalidate_filter())
        # (en azul, como «Nueva BBDD…»: el asistente de clonar de git, con su versión y su BBDD)
        new = nv_button("list-add-symbolic", "Nuevo proyecto…", "Clonar y montar un repositorio", lambda *_: self.nv_new_project(), "nv-azul")
        for w in (new, self.nv_kind, self.nv_search):
            head.pack_end(w, False, False, 0)
        self.proj_page.pack_start(head, False, False, 0)
        self.nv_list = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "nv-grupo")
        self.nv_list.set_filter_func(self.nv_filter)
        self.nv_list.connect("row-activated", lambda _l, r: r.project is not None and self.nv_select(r.project))
        self.proj_page.pack_start(self.nv_list, False, False, 0)
        self.nv_count = label("", "nv-chico", "nv-tenue")
        self.proj_page.pack_start(self.nv_count, False, False, 0)

    def nv_filter(self, row):
        x = row.project
        if x is None:
            return True
        q = self.nv_search.get_text().strip().lower()
        k = self.nv_kind.get_active_id()
        # (por el nombre de la carpeta o por el de cualquiera de sus BBDD: «tienda» encuentra
        # wordpress-ejemplo, cuya BBDD es wp_tienda)
        found = not q or q in x["name"].lower() or any(q in db.lower() for db in row.dbs)
        return found and (k == "all" or (k == "otros" and not x["kind"]) or x["kind"] == k)

    def nv_docker_loaded(self, x):
        """Botón Docker del proyecto cargado. Sin Docker, lo primero es instalarlo (o arrancarlo). Si el
        proyecto no está en Docker, se monta (con la versión de PHP que se elija); si está con una
        versión, se arranca; con varias, se pregunta cuál (o se monta con otra versión)."""
        def got(rc, out):
            self.on_docker_data(rc, out)
            d = self.docker or {}
            envs = self.nv_docker_of(x["name"])
            if not d.get("ready") or not d.get("php"):
                installed = d.get("installed")
                if confirm(self.win, "Docker está apagado" if installed else "Docker no está instalado",
                           "Se %s Docker sin root, con tu usuario. Pide la contraseña de administrador."
                           % ("arranca" if installed else "instala"),
                           "Arrancar Docker" if installed else "Instalar Docker"):
                    self.run_task("Arrancando Docker sin root" if installed else "Instalando Docker sin root",
                                  ["docker-instalar"], progress=True, done_text="Docker sin root listo",
                                  on_done=lambda ok, *_: ok and self.nv_docker_loaded(x))
            elif not envs:
                self.nv_docker_loaded_dialog(x)
            elif len(envs) == 1:
                self.nv_docker_mount(envs[0])
            else:
                self.nv_docker_choose(x, envs)
            return False
        run_quick(["gui-docker"], got)

    def nv_docker_add_env(self, x):
        """Añadir entorno en Docker: si ya va con el Apache de Docker, otra versión de PHP; si no, montarlo."""
        web = next((e for e in self.nv_docker_of(x["name"]) if e.get("web")), None)
        if web is not None:
            self.nv_docker_versions(web)
        else:
            self.nv_docker_loaded(x)

    def nv_docker_mount(self, dp):
        """Monta (arranca) un proyecto de Docker y lleva a la pestaña Docker."""
        if dp["state"] in ("marcha", "running"):
            self.show_tab("docker")
            self.toast("%s ya está en marcha en Docker: https://%s" % (dp["folder"], dp["domain"]))
            return

        def done(ok, *_):
            run_quick(["gui-docker"], self.on_docker_data)
            if ok:
                self.show_tab("docker")
        self.run_task("Arrancando %s en Docker (PHP %s)" % (dp["folder"], dp["php"]), ["docker-arrancar", dp["slug"]],
                      done_text="%s en Docker: https://%s" % (dp["folder"], dp["domain"]), auto_close=True, on_done=done)

    def nv_docker_choose(self, x, envs):
        """El proyecto está en Docker con varias versiones de PHP: cuál se monta, u otra nueva."""
        dlg = Gtk.Dialog(title="Docker", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(480, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        box.pack_start(label("¿Qué versión de %s montas?" % x["name"], "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(label("Está en Docker con varias versiones de PHP.", "nv-tenue", wrap=True), False, False, 0)
        group_rb, choice = None, {"v": envs[0]}
        for dp in sorted(envs, key=lambda e: ver_tuple(e["php"]), reverse=True) + [None]:
            opt = css(Gtk.Box(), "opcion")
            text = ("PHP %s  ·  %s%s" % (dp["php"], dp["domain"], "  ·  en marcha" if dp["state"] == "running" else "")
                    if dp else "Otra versión de PHP…")
            rb = Gtk.RadioButton.new_with_label_from_widget(group_rb, text)
            group_rb = group_rb or rb
            rb.connect("toggled", lambda b, o=opt, dp=dp: (o.get_style_context().add_class("elegida"), choice.update(v=dp))
                       if b.get_active() else o.get_style_context().remove_class("elegida"))
            if dp is envs[0]:
                css(opt, "elegida")
            opt.pack_start(rb, True, True, 0)
            box.pack_start(opt, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Montar", Gtk.ResponseType.OK), "nv-azul")
        dlg.show_all()
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp != Gtk.ResponseType.OK:
            return
        if choice["v"] is None:
            self.nv_docker_loaded_dialog(x)
        else:
            self.nv_docker_mount(choice["v"])

    def nv_docker_loaded_dialog(self, x):
        d = self.docker
        act = next((i for i in self.data["installs"] if i["folder"] == self.data["active"]), None) if self.data else None
        # Por defecto, lo mismo que tiene en la versión activa: su rama de PHP, su MariaDB y su BBDD
        php_now = ".".join((act or {}).get("php", "").split(".")[:2])
        maria_now = (act or {}).get("mariadb", "")
        php = php_now if php_now in d["php"] else d["php"][-1]
        maria = next((m for m in d["maria"] if maria_now.startswith(m + ".") or maria_now == m), d["maria"][-1])
        pairs = self.project_pairs(x) if self.data else []
        sources = [("@vacia", "Ninguna: empieza vacía")] + \
            [("%s|%s" % (i["folder"], db), "%s (lampp-%s)" % (db, i["folder"])) for i, db in pairs]
        source = next((k for k, _t in sources if act and k.startswith(act["folder"] + "|")), sources[-1][0])

        dlg = Gtk.Dialog(title="Docker", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(560, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        box.pack_start(label("Montar %s en Docker" % x["name"], "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(label("Se descargan las imágenes que falten y se abre por su dominio. La carpeta y su "
                             "BBDD de LAMPP no se tocan.", "nv-tenue", wrap=True, max_width_chars=60), False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        combos = {}
        wp = project_kind(x["name"]) == "wp"
        for key, title, items, current in [("php", "PHP", [(v, "PHP %s" % v) for v in d["php"]], php),
                                           ("maria", "MariaDB", [(v, "MariaDB %s" % v) for v in d["maria"]], maria),
                                           ("source", "BBDD" if wp else "BBDD que se copia", sources, source)] + (
                [("mode", "Cómo", [("vivo", "En vivo: la misma que web.local (sin copias)"),
                                   ("copia", "Una copia en Docker")], "vivo")] if wp else []):
            row = ActionRow(title)
            c = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
            for k, text in items:
                c.append(k, text)
            c.set_active_id(current)
            narrow(c, min(56, max([COMBO_CHARS] + [len(t) for _k, t in items])))
            row.add_suffix(c)
            lb.add(row)
            combos[key] = c
        # (el dominio sale solo: el de la tienda o el de la version de PHP elegida)
        base = docker_slug(x["name"])
        dom_row = ActionRow("Dominio", "…")
        lb.add(dom_row)

        def show_domain(*_):
            dom_row.subtitle.set_label("Con el Apache de Docker (sin LAMPP), por https: " + docker_web_domain(
                {"slug": base, "kind": project_kind(x["name"])}, combos["php"].get_active_id() or ""))
        combos["php"].connect("changed", show_domain)
        show_domain()
        box.pack_start(lb, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Montar en Docker", Gtk.ResponseType.OK), "nv-azul")
        dlg.show_all()
        resp = run_dialog(dlg)
        php, maria, src = (combos[k].get_active_id() for k in ("php", "maria", "source"))
        live = "mode" in combos and combos["mode"].get_active_id() == "vivo"
        dlg.destroy()
        if resp != Gtk.ResponseType.OK or not (php and maria):
            return
        domain = docker_web_domain({"slug": base, "kind": project_kind(x["name"])}, php)
        args = ["docker-nuevo", x["name"], php, maria]
        if src and src != "@vacia" and "|" in src:
            ver, db = src.split("|", 1)
            args += ["--bd", db, "--desde", ver] + (["--en-vivo"] if live else [])

        def done(ok, *_):
            run_quick(["gui-docker"], self.on_docker_data)
            if ok:
                self.show_tab("docker")
        self.run_task("Montando %s en Docker" % x["name"], args, progress=True,
                      done_text="%s en Docker: https://%s" % (x["name"], domain), on_done=done)

    def nv_docker_db_mode(self, p):
        """La BBDD de un WordPress de Docker: en vivo la de una versión LAMPP (la misma que web.local) o su
        copia en la MariaDB común de Docker."""
        x = {"name": p["folder"], "db": p["db"]}
        versions = []
        for i, _db in (self.project_pairs(x) if self.data else []):
            if i["folder"] not in versions:
                versions.append(i["folder"])
        dlg = Gtk.Dialog(title="BBDD", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(560, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        box.pack_start(label("BBDD de %s en Docker" % p["folder"], "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(label("En vivo, Docker usa la misma BBDD que web.local: lo que cambies en un lado se ve en el otro, "
                             "sin copias. Si la MariaDB de esa versión no está en marcha, se arranca solo ella (pide la "
                             "contraseña). La copia de Docker no se borra: se puede volver a ella.",
                             "nv-tenue", wrap=True, max_width_chars=62), False, False, 0)
        combo = Gtk.ComboBoxText()
        for v in versions:
            combo.append("lampp|" + v, "En vivo: la de lampp-%s (la de web.local)" % v)
        combo.append("docker", "Su copia en la MariaDB común de Docker")
        combo.set_active_id("lampp|" + p["lampp"] if p.get("lampp") else "docker")
        if combo.get_active_id() is None:
            combo.set_active(0)
        box.pack_start(combo, False, False, 0)
        if not versions:
            box.pack_start(label("Su BBDD no está en ninguna versión de LAMPP.", "nv-chico", "nv-tenue"), False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Usarla", Gtk.ResponseType.OK), "nv-azul")
        dlg.show_all()
        resp = run_dialog(dlg)
        choice = combo.get_active_id()
        dlg.destroy()
        if resp != Gtk.ResponseType.OK or not choice or choice == ("lampp|" + p["lampp"] if p.get("lampp") else "docker"):
            return
        args = ["docker-bd", p["slug"]] + (["lampp", choice.split("|", 1)[1]] if choice.startswith("lampp|") else ["docker"])
        self.run_task("BBDD de %s" % p["folder"], args, auto_close=True, done_text="Hecho",
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def dk_url(self, domain):
        """Dirección de una web del Apache de Docker: con el puerto si no es el 443."""
        port = ((self.docker or {}).get("web") or {}).get("https", "443")
        return "https://%s%s" % (domain, "" if port == "443" else ":" + port)

    def dk_pma_url(self, p):
        return self.dk_url(docker_pma_domain()) + "/" if p.get("web") else "http://127.0.0.1:%s/" % p["pma"]

    def nv_docker_copy_pass(self, p):
        """Contraseña de root de la BBDD del contenedor (DB_ROOT_PASS de su .env, solo tuyo), al
        portapapeles: su phpMyAdmin ya no entra solo. En los del Apache de Docker, la de su MariaDB comun."""
        path = os.path.join(LOG_DIR, "docker", ("mariadb-%s" % p["maria"]) if p.get("web") else p["slug"], ".env")
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                pw = next((l.split("=", 1)[1].strip() for l in fh.read(4000).splitlines()
                           if l.startswith("DB_ROOT_PASS=")), "")
        except OSError:
            pw = ""
        if not pw:
            self.toast("No se encuentra la contraseña de %s (%s)" % (p["folder"], path))
            return
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(pw, -1)
        if p.get("web"):
            self.toast("Contraseña de root de la MariaDB %s de Docker copiada: en phpMyAdmin, usuario root" % p["maria"])
        else:
            self.toast("Contraseña de root de %s copiada: en su phpMyAdmin, usuario root" % p["folder"])

    def nv_docker_versions(self, p):
        """Versiones de PHP de un proyecto del Apache de Docker: la misma carpeta y la misma BBDD. En
        WordPress van a la vez, cada una con su dominio; una tienda va con un dominio y la que se elija."""
        d = self.docker or {}
        ps = p.get("kind") == "ps"
        dlg = Gtk.Dialog(title="Versiones de PHP", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(560, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        box.pack_start(label("Versiones de PHP de %s" % p["folder"], "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(label(("La tienda guarda su dominio en la BBDD: va con %s y la versión que elijas." % self.dk_url(p["domain"]))
                             if ps else "Todas a la vez, cada una con su dominio, con la misma carpeta y la misma BBDD.",
                             "nv-tenue", wrap=True, max_width_chars=60), False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        choice = {}

        def act(args, title, done):
            choice.update(args=args, title=title, done=done)
            dlg.response(Gtk.ResponseType.OK)
        for v in p["versions"]:
            on = v == p["php"]
            row = ActionRow("PHP %s" % v, (self.dk_url(p["domain"]) + ("  ·  la elegida" if on else ""))
                            if ps else self.dk_url(docker_web_domain(p, v)))
            if ps and not on:
                b = Gtk.Button(label="Elegir", valign=Gtk.Align.CENTER, sensitive=not self.busy)
                b.connect("clicked", lambda *_, v=v: act(["docker-php-elegir", p["slug"], v], "%s con PHP %s" % (p["folder"], v),
                                                          "%s ya va con PHP %s" % (p["folder"], v)))
                row.add_suffix(b)
            if len(p["versions"]) > 1:
                b = Gtk.Button(valign=Gtk.Align.CENTER, sensitive=not self.busy,
                               tooltip_text="Quitar PHP %s" % v)
                b.add(icon("user-trash-symbolic"))
                b.connect("clicked", lambda *_, v=v: act(["docker-php-quitar", p["slug"], v], "Quitando PHP %s de %s" % (v, p["folder"]),
                                                          "PHP %s quitado de %s" % (v, p["folder"])))
                row.add_suffix(b)
            lb.add(row)
        rest = [v for v in d.get("php", []) if v not in p["versions"]]
        if rest:
            row = ActionRow("Añadir otra", "Se prepara su imagen la primera vez (unos minutos)")
            c = Gtk.ComboBoxText(valign=Gtk.Align.CENTER)
            for v in rest:
                c.append(v, "PHP %s" % v)
            c.set_active(0)
            row.add_suffix(c)
            b = css(Gtk.Button(label="Añadir", valign=Gtk.Align.CENTER, sensitive=not self.busy), "nv-azul")
            b.connect("clicked", lambda *_: c.get_active_id() and act(
                ["docker-php-añadir", p["slug"], c.get_active_id()], "Añadiendo PHP %s a %s" % (c.get_active_id(), p["folder"]),
                "%s con PHP %s" % (p["folder"], c.get_active_id())))
            row.add_suffix(b)
            lb.add(row)
        box.pack_start(lb, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cerrar", Gtk.ResponseType.CANCEL)
        dlg.show_all()
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp == Gtk.ResponseType.OK and choice:
            self.run_task(choice["title"], choice["args"], done_text=choice["done"],
                          on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def nv_docker_pass(self, p):
        """Un proyecto de antes (con LAMPP delante) pasa al Apache de Docker (docker-pasar)."""
        new = self.dk_url(docker_web_domain(dict(p, kind=project_kind(p["folder"])), p["php"]))
        if not confirm(self.win, "¿Pasar %s al Apache de Docker?" % p["folder"],
                       "Ya no necesitará LAMPP y podrás añadirle más versiones de PHP. Antes se guarda una copia de "
                       "su BBDD (%s) en ~/lvm-copias y se carga en la MariaDB común; después se quitan sus "
                       "contenedores de ahora, su vhost de LAMPP y su línea de /etc/hosts. Se abrirá en %s. "
                       "Pide la contraseña de administrador." % (p["db"], new), "Pasarlo"):
            return
        self.run_task("Pasando %s al Apache de Docker" % p["folder"], ["docker-pasar", p["slug"]], progress=True,
                      done_text="%s ya va con el Apache de Docker" % p["folder"],
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def nv_docker_web_strip(self, box):
        """El Apache de Docker: si está en marcha, su dirección y arrancarlo o pararlo; y si Docker sin root
        aún no puede usar sus puertos, el aviso con «Permitir»."""
        d = self.docker or {}
        w = d.get("web")
        if not w or not any(p.get("web") for p in d.get("projects", [])):
            return
        if not w["ports_ok"]:
            r = css(Gtk.Box(spacing=10), "nv-stat")
            r.pack_start(icon("dialog-warning-symbolic"), False, False, 0)
            tt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            tt.pack_start(label("Docker sin root aún no puede usar los puertos %s y %s" % (w["http"], w["https"])), False, False, 0)
            tt.pack_start(label("Los puertos de menos de 1024 son de root: se permite una vez (pide la contraseña). "
                                "O elige otros en Configuración.", "nv-chico", "nv-tenue"), False, False, 0)
            r.pack_start(tt, True, True, 0)
            r.pack_end(nv_button(None, "Permitir", None, lambda *_: self.run_task(
                "Permitiendo los puertos del Apache de Docker", ["docker-web", "permitir"], auto_close=True,
                done_text="Docker ya puede usar sus puertos", on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))),
                False, False, 0)
            box.pack_start(r, False, False, 0)
        r = css(Gtk.Box(spacing=10), "nv-stat")
        up = w["state"] == "marcha"
        r.pack_start(label("●", "nv-verde", "nv-latido") if up else nv_dot(False), False, False, 0)
        tt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        tt.pack_start(label("Apache de Docker %s" % ("en marcha" if up else "parado")), False, False, 0)
        tt.pack_start(label("En %s (http %s, https %s): sirve los proyectos de Docker sin LAMPP, con las mismas reglas "
                            "de seguridad. phpMyAdmin: %s" % (w["ip"], w["http"], w["https"], self.dk_url(docker_pma_domain())),
                            "nv-chico", "nv-tenue", ellipsize=3), False, False, 0)
        r.pack_start(tt, True, True, 0)
        r.pack_end(nv_button(None, "Parar" if up else "Arrancar", None, lambda *_: self.run_task(
            ("Parando" if up else "Arrancando") + " el Apache de Docker", ["docker-web", "parar" if up else "arrancar"],
            auto_close=True, on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))), False, False, 0)
        box.pack_start(r, False, False, 0)

    def nv_docker_update_image(self, p):
        if not confirm(self.win, "¿Actualizar la imagen de PHP %s?" % p["php"],
                       "Se rehace con los últimos parches de Docker Hub y se recrea el contenedor de PHP de "
                       "%s. Su BBDD y su configuración no cambian." % p["folder"],
                       "Actualizar la imagen"):
            return
        self.run_task("%s: imagen de PHP %s" % (p["folder"], p["php"]), ["docker-imagen", p["slug"]], progress=True,
                      done_text="%s ya usa la imagen nueva de PHP %s" % (p["folder"], p["php"]),
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def nv_docker_of(self, name):
        return [p for p in (self.docker or {}).get("projects", []) if p["folder"] == name]

    def nv_select(self, x):
        """Elegir un proyecto de la lista: solo el visor y la fila elegida (rehacer la lista entera
        tarda un cuarto de segundo con muchos proyectos; esto, al momento)."""
        self.selected_project = x["name"]
        if not getattr(self, "nv_list", None) or not self.projects or not self.data:
            return
        loaded = self.loaded_project_entry()
        if loaded is None:
            self.nv_hero(next((p for p in self.projects["list"] if p["name"] == x["name"]), None), None)
        for row in self.nv_list.get_children():
            proj = getattr(row, "project", None)
            if proj is None:
                continue
            ctx = row.get_style_context()
            if proj["name"] == x["name"] and not (loaded and proj["name"] == loaded["name"]):
                ctx.add_class("nv-elegida")
            else:
                ctx.remove_class("nv-elegida")

    def nv_build_projects(self):
        if not getattr(self, "nv_list", None) or not self.projects or not self.data:
            return
        p = self.projects
        loaded = self.loaded_project_entry()
        names = [x["name"] for x in p["list"]]
        if self.selected_project not in names:
            self.selected_project = loaded["name"] if loaded else None
        # (arriba, siempre el cargado, con sus botones: elegir otro en la lista no lo cambia. Sin
        # ninguno cargado, el elegido)
        shown = loaded or next((x for x in p["list"] if x["name"] == self.selected_project), None)
        self.nv_hero(shown, loaded)
        clear(self.nv_list)
        head = Gtk.ListBoxRow(activatable=False, selectable=False)
        head.project, head.dbs = None, []
        hb = css(Gtk.Box(spacing=12, margin_start=12, margin_end=8, margin_top=8, margin_bottom=8), "nv-cab")
        # (la columna Proyecto, tan ancha como el nombre más largo: se ve entero)
        self.nv_name_group = Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL)
        self.nv_size_lbls = {}
        for text, w in [("", 18), ("Proyecto", 260), ("Tamaño", 80), ("BBDD", 190), ("Versiones", 0)]:
            lbl = label(text.upper())
            if w:
                lbl.set_size_request(w, -1)
            if text == "Proyecto":
                self.nv_name_group.add_widget(lbl)
            hb.pack_start(lbl, not w, True, 0)
        head.add(hb)
        self.nv_list.add(head)
        for x in p["list"]:
            self.nv_list.add(self.nv_row(x, loaded))
        self.nv_list.show_all()
        self.nv_project_sizes()
        self.nv_count.set_label(plural(len(p["list"]), "proyecto", "proyectos") + " en /opt/htdocs")

    def nv_project_sizes(self):
        """Lo que ocupa cada proyecto en el disco: du en segundo plano, de 10 en 10 proyectos (sin límite de
        tiempo: alguno tarda) y como mucho una vez por minuto; cada uno se vuelve a medir cada 6 horas."""
        if getattr(self, "nv_sizes_busy", False) or time.time() - getattr(self, "nv_sizes_at", 0) < 60:
            return
        self.nv_sizes_busy = True
        run_quick(["gui-proyectos-tamanos"], self.on_project_sizes, timeout=None)

    def on_project_sizes(self, rc, out):
        self.nv_sizes_busy, self.nv_sizes_at = False, time.time()
        lines = parse_lines(out)
        self.project_sizes = {f[1]: (int(f[2]), int(f[3])) for f in lines
                              if f[0] == "T" and len(f) >= 4 and f[2].isdigit() and f[3].isdigit()}
        for name, lbl in getattr(self, "nv_size_lbls", {}).items():
            self.nv_size_text(lbl, name)
        # (quedan por medir: la siguiente tanda, ya)
        if any(f[0] == "F" for f in lines):
            self.nv_sizes_at = 0
            self.nv_project_sizes()
        return False

    def nv_size_text(self, lbl, name):
        got = getattr(self, "project_sizes", {}).get(name)
        lbl.set_label(fmt_size(got[0]) if got else "…")
        lbl.set_tooltip_text("Tamaño en disco, medido el %s"
                             % time.strftime("%d/%m/%Y a las %H:%M", time.localtime(got[1])) if got
                             else "Midiendo lo que ocupa en el disco…")

    def nv_row(self, x, loaded):
        row = Gtk.ListBoxRow()
        row.project = x
        is_loaded = loaded is not None and x["name"] == loaded["name"]
        # BBDD del proyecto para el buscador: las de cada version, la de su configuracion y la de Docker
        row.dbs = {db for _i, db in self.project_pairs(x)} | ({x["db"]} if x["db"] else set()) | \
            {dp["db"] for dp in self.nv_docker_of(x["name"])}
        if is_loaded:
            css(row, "nv-cargada")
        elif x["name"] == self.selected_project:
            css(row, "nv-elegida")
        box = Gtk.Box(spacing=12, margin_start=12, margin_end=8, margin_top=6, margin_bottom=6)
        box.pack_start(kind_icon(x["kind"]), False, False, 0)
        name = label(x["name"], tooltip_text=x["name"])
        name.set_size_request(260, -1)
        self.nv_name_group.add_widget(name)
        box.pack_start(name, False, False, 0)
        size = label("", "nv-mono", "nv-chico", "nv-tenue")
        size.set_size_request(80, -1)
        self.nv_size_lbls[x["name"]] = size
        self.nv_size_text(size, x["name"])
        box.pack_start(size, False, False, 0)
        pairs = self.project_pairs(x)
        db = pairs[0][1] if pairs else self.project_base(x)
        dbl = label(db or "sin BBDD", "nv-mono", "nv-chico", "nv-tenue", ellipsize=3, max_width_chars=24)
        dbl.set_size_request(190, -1)
        box.pack_start(dbl, False, False, 0)
        chips = Gtk.Box(spacing=4, valign=Gtk.Align.CENTER)
        for inst, _db in pairs:
            chips.pack_start(label(inst["php"].rsplit(".", 1)[0] if inst["php"].count(".") == 2 else inst["php"],
                                   "nv-chip", "nv-mono", tooltip_text="lampp-%s · %s" % (inst["folder"], _db)), False, False, 0)
        for dp in self.nv_docker_of(x["name"]):
            chip = css(Gtk.Box(spacing=5, tooltip_text="Docker · %s" % dp["db"]), "nv-chip", "nv-chip-docker")
            chip.pack_start(logo("docker", 13), False, False, 0)
            chip.pack_start(label("Docker %s" % dp["php"], "nv-mono"), False, False, 0)
            chips.pack_start(chip, False, False, 0)
        box.pack_start(chips, True, True, 0)
        # Al pasar el raton: Cargar (si no es el cargado), Montar en Docker (si tiene contenedores: con varios
        # pregunta cual) y su menu ⋮ (el hueco se guarda: la fila no salta)
        hover, dk = [], None
        if self.nv_docker_of(x["name"]):
            dk = nv_button(logo("docker", 16), "Montar en Docker", "Arrancar %s en Docker" % x["name"], lambda *_: self.nv_docker_loaded(x), "nv-proyecto-btn")
            dk.set_sensitive(not self.busy)
            hover.append(dk)
        if is_loaded:
            box.pack_end(label("Cargado", "nv-etiqueta", "nv-etiqueta-azul", valign=Gtk.Align.CENTER, margin_end=6), False, False, 0)
        else:
            b = css(Gtk.Button(label="Cargar", sensitive=not self.busy), "nv-azul")
            b.connect("clicked", lambda *_: self.on_load_folder(x))
            menu = self.nv_row_menu(x)
            menu.set_valign(Gtk.Align.CENTER)
            menu.set_sensitive(not self.busy)
            box.pack_end(menu, False, False, 0)
            box.pack_end(b, False, False, 0)
            hover += [b, menu]
        if dk is not None:
            box.pack_end(dk, False, False, 0)
        if not hover:
            row.add(box)
            return row
        for w in hover:
            w.set_opacity(0)
        menus = [w for w in hover if isinstance(w, Gtk.MenuButton)]
        ev = Gtk.EventBox(above_child=False)
        ev.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        ev.connect("enter-notify-event", lambda *_: ([w.set_opacity(1) for w in hover], False)[1])
        ev.connect("leave-notify-event", lambda _w, e: (e.detail == Gdk.NotifyType.INFERIOR or any(m.get_active() for m in menus)
                                                         or [w.set_opacity(0) for w in hover], False)[1])
        ev.add(box)
        row.add(ev)
        return row

    def nv_hero(self, x, loaded):
        clear(self.hero_box)
        p = self.projects
        is_loaded = x is not None and loaded is not None and x["name"] == loaded["name"]
        head = Gtk.Box(spacing=8)
        head.pack_start(nv_dot(is_loaded), False, False, 0)
        head.pack_start(label("PROYECTO CARGADO" if is_loaded else "PROYECTO ELEGIDO" if x else "NINGÚN PROYECTO CARGADO",
                              "nv-seccion"), False, False, 0)
        if p.get("link"):
            head.pack_end(label(("en %s" % p["link"]) if is_loaded else "%s → %s" % (
                p["link"], os.path.basename(p["current"].rstrip("/")) if p["current"] else "nada"), "nv-chico", "nv-tenue"), False, False, 0)
        # (el correo de la web cargada va a Mailpit: discreto, al lado)
        m = self.nv_mail()
        if is_loaded and m.get("on") and m.get("installed"):
            mail = Gtk.Box(spacing=5)
            mail.pack_start(MonoLogo("mailpit", 13), False, False, 0)
            mail.pack_start(label("su correo va a Mailpit", "nv-chico", "nv-tenue"), False, False, 0)
            mail.set_tooltip_text("Se ve en Correo, arriba")
            head.pack_end(mail, False, False, 12)
        self.hero_box.pack_start(head, False, False, 0)
        card = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16), "nv-tarjeta")
        if x is None:
            card.pack_start(label("Elige un proyecto de la lista para cargarlo.", "nv-tenue"), False, False, 0)
            self.hero_box.pack_start(card, False, False, 0)
            self.hero_box.show_all()
            return
        top = Gtk.Box(spacing=20)
        # (el logotipo solo, sin recuadro: con el visor de la derecha más alto, el recuadro se estiraba)
        img = kind_icon(x["kind"], 48)
        img.set_valign(Gtk.Align.CENTER)
        top.pack_start(img, False, False, 0)
        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, valign=Gtk.Align.CENTER)
        tl = Gtk.Box(spacing=10)
        # (los nombres largos, en dos lineas, no cortados)
        tl.pack_start(label(x["name"], "nv-titulo-grande", wrap=True, wrap_mode=2, max_width_chars=44), False, False, 0)
        if x["kind"]:
            tl.pack_start(label(KIND_TEXT[x["kind"]], "nv-etiqueta", valign=Gtk.Align.CENTER), False, False, 0)
        info.pack_start(tl, False, False, 0)
        info.pack_start(label("%s/%s" % (HTDOCS, x["name"]), "nv-mono", "nv-chico", "nv-tenue", selectable=True,
                              ellipsize=1, max_width_chars=40), False, False, 0)
        top.pack_start(info, True, True, 0)
        # Selectores: el entorno (version y su BBDD) y la BBDD de ese entorno
        pairs = self.project_pairs(x)
        dockers = self.nv_docker_of(x["name"])
        sel = css(Gtk.Grid(column_spacing=12, row_spacing=6, valign=Gtk.Align.CENTER), "nv-selectores")
        sel.attach(label("Entorno (versión de PHP)", "nv-chico", "nv-tenue"), 1, 0, 1, 1)
        sel.attach(label("BBDD", "nv-chico", "nv-tenue"), 2, 0, 1, 1)
        envs = [("lampp", inst, db) for inst, db in pairs] + [("docker", dp, dp["db"]) for dp in dockers]
        env = Gtk.ComboBoxText()
        env.set_size_request(230, -1)
        for kind, obj, _db in envs:
            env.append_text("PHP %s · lampp-%s" % (obj["php"], obj["folder"]) if kind == "lampp"
                            else "PHP %s · Docker" % obj["php"])
        if not envs:
            env.append_text("Sin entornos")
        current = next((n for n, (k, o, _d) in enumerate(envs) if k == "lampp" and o["folder"] == self.data["active"]), 0)
        env.set_active(current if is_loaded else 0)
        env.set_sensitive(bool(envs) and not self.busy)
        dbl = label("", "nv-mono", valign=Gtk.Align.CENTER)
        dbl.set_size_request(180, -1)

        def show_db(*_):
            n = env.get_active()
            dbl.set_label(envs[n][2] if envs and 0 <= n < len(envs) else "—")
        show_db()
        env.connect("changed", show_db)

        def changed(*_):
            n = env.get_active()
            if not envs or n < 0:
                return
            kind, obj, db = envs[n]
            if kind == "docker":
                self.show_tab("docker")
                self.toast("%s en Docker: https://%s" % (x["name"], obj["domain"]))
            elif not (is_loaded and obj["folder"] == self.data["active"]):
                self.do_load_project(x["name"], db, obj, p["link"], p["create"])
        env.connect("changed", changed)
        # Llevarlo a otro entorno: el +, a la izquierda del entorno (su SQL se importa en la pestaña
        # Bases de datos; la fila de abajo queda para los accesos directos del proyecto)
        sel.attach(self.nv_add_env_menu(x), 0, 1, 1, 1)
        sel.attach(env, 1, 1, 1, 1)
        sel.attach(dbl, 2, 1, 1, 1)
        lk = nv_button("insert-link-symbolic", None, "Cambiar la BBDD de cada versión (vincular)",
                       lambda *_: self.on_link_project(x), flat=True)
        sel.attach(lk, 3, 1, 1, 1)
        top.pack_end(sel, False, False, 0)
        card.pack_start(top, False, False, 0)
        card.pack_start(css(Gtk.Box(), "nv-pie"), False, False, 0)
        acts = Gtk.Box(spacing=8)
        if is_loaded:
            kind, admin = self.loaded_project_admin()
            # (con los logotipos de siempre: el globo, VS Code, phpMyAdmin y WordPress o PrestaShop)
            # (los que se ven, su orden y su estilo, como se haya elegido: nv_place_buttons)
            btns = {"web": nv_button(logo("globo", 18), "Abrir web", "Abrir http://%s/" % p["link"],
                                     lambda *_: self.open_uri("http://%s/" % p["link"]), "nv-proyecto-btn")}
            code = vscode_app()
            if code is not None:
                img = None
                if code.get_icon() is not None:
                    img = Gtk.Image.new_from_gicon(code.get_icon(), Gtk.IconSize.BUTTON)
                    img.set_pixel_size(18)
                btns["vscode"] = nv_button(img or "text-editor-symbolic", "VS Code",
                                           "Abrir en Visual Studio Code", lambda *_: self.open_in_vscode(),
                                           "nv-proyecto-btn")
            pma = nv_button(logo("phpmyadmin", 18), "phpMyAdmin", None, lambda *_: self.open_project_pma(), "nv-proyecto-btn")
            pma.set_sensitive(bool(self.loaded_project_db()))
            btns["pma"] = pma
            adm = nv_button(logo("prestashop" if kind == "ps" else "wordpress", 18), "Panel",
                            "Abrir el panel de administración",
                            lambda *_: self.open_project_admin(), "nv-proyecto-btn")
            adm.set_sensitive(bool(admin))
            adm.nv_logo = "prestashop" if kind == "ps" else "wordpress"
            btns["panel"] = adm
            btns["docker"] = nv_button(logo("docker", 18), "Docker", "Montar en Docker",
                                       lambda *_: self.nv_docker_loaded(x), "nv-proyecto-btn")
            btns["compartir"] = self.nv_share_button("http://%s" % p["link"], os.path.join(HTDOCS, x["name"]), x["name"])
            # El registro general de Apache: lo primero que se mira con un error (el del vhost, en Herramientas)
            has_log = os.path.isfile(APACHE_ERROR_LOG)
            logb = nv_button(logo("log", 18), "Log", "Ver el log de Apache" if has_log else "Aún no hay log de Apache",
                             lambda *_: self.show_log_tail(APACHE_ERROR_LOG), "nv-proyecto-btn")
            logb.set_sensitive(has_log)
            btns["log"] = logb
            btns["actualizar"] = nv_button(logo("actualizar", 18), "Actualizar", "Actualizar proyecto",
                                           lambda *_: self.nv_update_project(x), "nv-proyecto-btn")
            btns["actualizar"].set_sensitive(not self.busy)
            if x["kind"] in ("wp", "ps"):
                btns["imagenes"] = self.nv_images_button(x)
            eject = nv_button("media-eject-symbolic", None, "Desmontar el proyecto",
                              lambda *_: self.on_unload_project(), flat=True)
            self.nv_place_buttons(acts, btns, [(eject, ("icono", "media-eject-symbolic"), "Desmontar")])
            acts.pack_start(eject, False, False, 0)
        else:
            acts.pack_start(nv_button("media-playback-start-symbolic", "Cargar", None,
                                      lambda *_: self.on_load_folder(x), "nv-azul"), False, False, 0)
        # (⋮, pegado a la derecha; con un proyecto cargado, del tamaño de los demás botones)
        more = self.nv_more_menu(x)
        if is_loaded:
            self.nv_restyle(more, buttons_conf(), ("icono", "view-more-symbolic"), "Más")
        acts.pack_end(more, False, False, 0)
        # Si su carpeta tiene un dominio en los vhosts: falsearlo o dejar de falsearlo desde aquí, como
        # en Dominios y hosts
        if is_loaded:
            for h in reversed(self.project_hosts(x["name"])):
                fake = h["fake"]
                host = Gtk.Box(spacing=10, margin_end=10)
                texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
                texts.pack_start(label("Host falseado" if fake else "Falsear Host", halign=Gtk.Align.END), False, False, 0)
                texts.pack_start(label(h["name"], "nv-chico", "nv-tenue", halign=Gtk.Align.END, ellipsize=2,
                                       max_width_chars=28, tooltip_text=h["name"]), False, False, 0)
                host.pack_start(texts, False, False, 0)
                sw = Gtk.Switch(active=fake, valign=Gtk.Align.CENTER, tooltip_text=host_switch_tip(h))
                sw.connect("state-set", self.on_host_switch, h)
                host.pack_start(sw, False, False, 0)
                acts.pack_end(host, False, False, 0)
        card.pack_start(acts, False, False, 0)
        self.hero_box.pack_start(card, False, False, 0)
        self.hero_box.show_all()

    # --- Actualizar proyecto: la BBDD y el código de producción, arrastrados o elegidos ---

    def nv_drop_zone(self, title, formats, symbol_name, choosers, on_path):
        """Zona donde arrastrar un fichero o una carpeta, con sus botones de elegir. choosers: (texto,
        es carpeta). on_path(ruta) devuelve el motivo si no vale. Devuelve (widget, poner la ruta)."""
        ev = css(Gtk.EventBox(), "nv-zona")
        # (alta: es donde se suelta, tiene que verse bien)
        ev.set_size_request(-1, 112)
        box = Gtk.Box(spacing=16, margin_start=20, margin_end=18, margin_top=16, margin_bottom=16)
        ev.add(box)
        box.pack_start(css(icon(symbol_name, 36), "nv-zona-icono"), False, False, 0)
        # (en una rejilla: airy_dialog centra los textos de las cajas verticales; aquí, junto al icono, a la izquierda)
        texts = Gtk.Grid(orientation=Gtk.Orientation.VERTICAL, row_spacing=2, valign=Gtk.Align.CENTER)
        texts.add(label(title, "grupo-titulo", halign=Gtk.Align.START))
        name = label("Arrástralo aquí: %s" % formats, "dim-label", ellipsize=2, halign=Gtk.Align.START)
        texts.add(name)
        box.pack_start(texts, True, True, 0)

        def put(path):
            why = on_path(path)
            ctx = name.get_style_context()
            ctx.remove_class("error")
            if why:
                ctx.add_class("error")
                name.set_label(why)
            else:
                name.set_label(path or "Arrástralo aquí: %s" % formats)
            name.set_tooltip_text(path or None)
            clear_btn.set_visible(bool(path) and not why)
            # (el recuadro azul, solo con algo incorporado o al arrastrar encima)
            zone_ctx = ev.get_style_context()
            if path and not why:
                zone_ctx.add_class("nv-zona-lista")
            else:
                zone_ctx.remove_class("nv-zona-lista")

        def choose(folder):
            dlg = Gtk.FileChooserDialog(title=title, transient_for=ev.get_toplevel(), modal=True,
                                        action=Gtk.FileChooserAction.SELECT_FOLDER if folder else Gtk.FileChooserAction.OPEN)
            dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
            dlg.add_button("Elegir", Gtk.ResponseType.ACCEPT)
            dlg.set_current_folder(GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_DOWNLOAD) or os.path.expanduser("~"))
            resp = run_dialog(dlg)
            path = dlg.get_filename()
            dlg.destroy()
            if resp == Gtk.ResponseType.ACCEPT and path:
                put(path)

        def dropped(_w, _ctx, _x, _y, data, _info, _time):
            uris = data.get_uris()
            if uris:
                try:
                    put(GLib.filename_from_uri(uris[0])[0])
                except GLib.Error:
                    put("")
        ev.drag_dest_set(Gtk.DestDefaults.ALL, [], Gdk.DragAction.COPY)
        ev.drag_dest_add_uri_targets()
        ev.connect("drag-data-received", dropped)
        clear_btn = nv_button("window-close-symbolic", None, "Quitar", lambda *_: put(""), flat=True)
        # (oculto hasta que haya algo elegido, sin dejar oculto su icono)
        clear_btn.get_child().show_all()
        clear_btn.set_no_show_all(True)
        box.pack_start(clear_btn, False, False, 0)
        for text, folder in choosers:
            box.pack_start(nv_button(None, text, None, lambda *_, f=folder: choose(f)), False, False, 0)
        return ev, put

    def nv_update_project(self, x):
        """Actualizar el proyecto cargado con lo de producción: su BBDD y su código."""
        folder = x["name"]
        dlg = Gtk.Dialog(title="Actualizar proyecto", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(680, -1)
        dlg.get_header_bar().set_subtitle(folder)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14, margin=22)
        state = {"sql": "", "code": ""}

        def set_sql(path):
            why = ""
            if path and not (os.path.isfile(path) and path.lower().endswith((".sql", ".gz", ".zip"))):
                why, path = "Tiene que ser .sql, .sql.gz o .zip", ""
            state["sql"] = path
            update()
            return why

        def set_code(path):
            why = ""
            ok = os.path.isdir(path) or (os.path.isfile(path) and path.lower().endswith(
                (".zip", ".tar", ".tgz", ".tar.gz", ".tar.bz2", ".tar.xz")))
            if path and not ok:
                why, path = "Tiene que ser un .zip, un .tar.gz o una carpeta", ""
            state["code"] = path
            update()
            return why

        zone, _put = self.nv_drop_zone("Base de datos de producción", ".sql, .sql.gz o .zip", "drive-multidisk-symbolic",
                                       [("Elegir fichero…", False)], set_sql)
        box.pack_start(zone, False, False, 0)
        line = Gtk.Box(spacing=8)
        db_text = label("", "dim-label")
        line.pack_start(db_text, False, False, 0)
        # (su nombre, como texto; solo si el proyecto no tiene ninguna hay que escribirlo)
        known_db = self.loaded_project_db() or ""
        db_entry = Gtk.Entry(text=known_db, width_chars=28, max_length=64)
        line.pack_start(label(known_db, "nv-bbdd", selectable=True) if known_db else db_entry, False, False, 0)
        db_copy = label("(antes se guarda una copia de la actual)", "dim-label")
        line.pack_start(db_copy, False, False, 0)
        box.pack_start(line, False, False, 0)
        zone, _put = self.nv_drop_zone("Código de producción", ".zip, .tar.gz o carpeta", "folder-symbolic",
                                       [("Elegir fichero…", False), ("Elegir carpeta…", True)], set_code)
        box.pack_start(zone, False, False, 0)
        # Qué hacer con la carpeta: siempre a la vista, para saber lo que va a pasar
        merge = Gtk.RadioButton.new_with_label(None, "Fusionar: copia lo que trae y deja lo demás de la carpeta")
        over = Gtk.RadioButton.new_with_label_from_widget(merge, "Sobrescribir: además borra lo que no traiga")
        modes = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        modes.pack_start(merge, False, False, 0)
        modes.pack_start(over, False, False, 0)
        modes.pack_start(label("Se escribe sobre %s/%s. Su .git no se toca y lo sustituido o borrado queda en "
                               "~/lvm-copias." % (HTDOCS, folder), "aviso-rojo", wrap=True), False, False, 0)
        box.pack_start(modes, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        go = css(dlg.add_button("Actualizar…", Gtk.ResponseType.ACCEPT), "nv-azul")

        def update(*_):
            db_ok = bool(re.fullmatch(r"[A-Za-z0-9_-]{1,64}", db_entry.get_text().strip()))
            go.set_sensitive(bool(state["sql"] or state["code"]) and (not state["sql"] or db_ok))
            modes.set_sensitive(bool(state["code"]))
            # (sin fichero de BBDD no se toca: se sigue usando la misma)
            db_text.set_label("Se carga en la BBDD" if state["sql"] else "Se sigue usando la BBDD")
            db_copy.set_visible(bool(state["sql"]))
            line.set_visible(bool(known_db or state["sql"]))
            if not known_db:
                db_entry.set_sensitive(bool(state["sql"]))
        db_entry.connect("changed", update)
        dlg.show_all()
        update()
        resp = run_dialog(dlg)
        db = db_entry.get_text().strip()
        mode = "sobrescribir" if over.get_active() else "fusionar"
        dlg.destroy()
        if resp == Gtk.ResponseType.ACCEPT:
            self.nv_update_project_ask(folder, state["sql"], db, state["code"], mode)

    def nv_update_project_ask(self, folder, sql, db, code, mode):
        """Antes de copiar: si es un repositorio, ¿git pull antes?, avisando de lo que no se ha subido."""
        def start(pull):
            args = ["actualizar-proyecto", folder]
            if code:
                args += ["--codigo", code, "--modo", mode] + (["--pull"] if pull else [])
            if sql:
                args += ["--bd", sql]
            # (también solo con el código: al volver a cargarlo, su configuración vuelve a esta BBDD)
            if db:
                args += ["--base", db]

            def run(_pwd=None):
                self.run_task("Actualizando %s" % folder, args, progress=True, env=self.db_env(),
                              done_text="%s actualizado" % folder,
                              cancel_text=("¿Cancelar la actualización?",
                                           "El proyecto se queda a medias, con lo hecho hasta ahora. Lo sustituido "
                                           "sigue en ~/lvm-copias.", "Cancelar la actualización"))
            if sql:
                self.check_db_access(run)
            else:
                run()

        what = []
        if code:
            what.append(("Se fusiona «%s» con %s/%s." if mode == "fusionar" else
                         "Se sobrescribe la carpeta con «%s» en %s/%s: se borra lo que no traiga.")
                        % (os.path.basename(code), HTDOCS, folder))
        if sql:
            what.append("La BBDD %s se vacía y se carga «%s» (antes se guarda una copia)." % (db, os.path.basename(sql)))

        def got(_rc, out):
            f = next((x for x in parse_lines(out) if x[0] == "G" and len(x) >= 6), None)
            is_git = bool(code) and f is not None and f[1] == "1"
            if not is_git:
                if confirm(self.win, "¿Actualizar %s?" % folder, "", "Actualizar", steps=what):
                    start(False)
                return False
            dirty, ahead = int(f[3] or 0), int(f[4] or 0)
            state = ["Rama %s" % (f[2] or "sin rama (HEAD suelto)")]
            if dirty:
                state.append("%s sin commit" % plural(dirty, "cambio", "cambios"))
            if ahead:
                state.append("%s sin subir" % plural(ahead, "commit", "commits"))
            text = ["  ·  ".join(state)]
            if dirty or ahead:
                text.append("Revisa antes lo que estás trabajando: lo sustituido queda en ~/lvm-copias, pero no en git.")
            has_pull = f[5] == "1" and bool(f[2])
            text.append("Con el pull, la carpeta se equipara antes al repositorio. Si choca con tus cambios, se para "
                        "sin tocar nada." if has_pull else "No se puede hacer pull: no tiene origin o no está en una rama.")
            dlg = Gtk.MessageDialog(transient_for=self.win, modal=True, message_type=Gtk.MessageType.QUESTION,
                                    buttons=Gtk.ButtonsType.NONE, text="¿Hacer git pull antes de copiar?")
            dlg.get_message_area().pack_start(steps_box(what, "\n\n".join(text)), False, False, 0)
            dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
            dlg.add_button("Copiar sin pull", Gtk.ResponseType.NO)
            if has_pull:
                css(dlg.add_button("Hacer pull y copiar", Gtk.ResponseType.YES), "nv-azul")
            dlg.show_all()
            resp = run_dialog(dlg)
            dlg.destroy()
            if resp in (Gtk.ResponseType.YES, Gtk.ResponseType.NO):
                start(resp == Gtk.ResponseType.YES)
            return False
        run_quick(["gui-proyecto-git", folder], got)

    def nv_menu_button(self, text, icon_name, items, tip=None):
        m = css(Gtk.MenuButton(tooltip_text=tip), "nv-proyecto-btn")
        b = Gtk.Box(spacing=6)
        b.pack_start(icon_name if isinstance(icon_name, Gtk.Widget) else icon(icon_name), False, False, 0)
        if text:
            b.pack_start(Gtk.Label(label=text), False, False, 0)
        m.add(b)
        pop = Gtk.Popover(relative_to=m)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=4)
        for t, fn in items:
            mb = Gtk.ModelButton(text=t)
            mb.connect("clicked", lambda *_, fn=fn: fn())
            box.pack_start(mb, False, False, 0)
        box.show_all()
        pop.add(box)
        m.set_popover(pop)
        return m

    def nv_add_env_menu(self, x):
        return self.nv_menu_button(None, "list-add-symbolic", [
            ("En otra versión de PHP (copiar su BBDD)…", lambda: self.on_replicate()),
            ("En Docker…", lambda: (self.docker_form.update(folder=x["name"], source=None, domain_set=False,
                                                           domain=docker_slug(x["name"]) + ".docker.local"),
                                    self.show_tab("docker"), self.docker is not None and self.build_docker()))],
            "Añadir entorno: llevar el proyecto a otra versión de PHP o a Docker")

    def nv_row_menu(self, x):
        """Menú ⋮ de una fila de la lista (aparece al pasar el ratón, con Cargar): llevar el proyecto a
        otra versión o a Docker, importar su SQL y lo del menú Más, sin cambiar el proyecto de arriba."""
        items = [("Añadir entorno en otra versión de PHP…", lambda: self.on_replicate(x)),
                 ("Añadir entorno en Docker…", lambda: self.nv_docker_add_env(x)),
                 ("Importar SQL…", lambda: self.nv_import(x))] + self.nv_more_items(x)
        return self.nv_menu_button(None, "view-more-symbolic", items)

    def nv_more_menu(self, x):
        return self.nv_menu_button(None, "view-more-symbolic", self.nv_more_items(x))

    def nv_more_items(self, x):
        items = [("Vincular la BBDD de cada versión…", lambda: self.on_link_project(x)),
                 ("Abrir la carpeta", lambda: self.open_uri("file://%s/%s" % (HTDOCS, x["name"])))]
        for dp in self.nv_docker_of(x["name"]):
            items.append(("Eliminar de Docker…", lambda dp=dp: self.on_docker_delete(dp)))
        db = self.project_base(x)
        if x["kind"] == "ps" and db:
            items.append(("Vaciar la caché de la tienda", lambda: self.run_task(
                "Vaciando la caché de la tienda de %s" % db, ["vaciar-cache", "--bd", db],
                done_text="Caché vaciada", auto_close=True)))
        if x["kind"] == "ps":
            items.append(("Descargar de producción las imágenes que faltan…", lambda: self.nv_ps_images(x)))
        elif x["kind"] == "wp":
            items.append(("Imágenes de producción…", lambda: self.nv_wp_media(x)))
        items.append(("Personalizar los botones…", lambda: self.nv_buttons_dialog()))
        items.append(("Borrar el proyecto…", lambda: self.nv_delete_project(x)))
        return items

    def nv_images_button(self, x):
        """Importar imágenes de producción: un WordPress las pide a su web real; una tienda las descarga."""
        b = nv_button(logo("imagenes", 18), "Importar", "Importar imágenes de producción",
                      lambda *_: self.nv_wp_media(x) if x["kind"] == "wp" else self.nv_ps_images(x), "nv-proyecto-btn")
        b.set_sensitive(not self.busy)
        return b

    def nv_wp_media(self, x):
        """media-proyecto: lo que le falte a un WordPress de wp-content/uploads se pide a su web real
        mientras esté cargado (por web.local). Se propone el dominio de su base (home o siteurl)."""
        name = x["name"]

        def got(rc, out):
            f = {l[0]: l[1] for l in parse_lines(out) if len(l) >= 2}
            saved, guess = f.get("G", ""), f.get("D", "")
            dlg = Gtk.Dialog(title="Imágenes de producción", transient_for=self.win, modal=True, use_header_bar=True)
            dlg.set_default_size(520, -1)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
            box.pack_start(label("Imágenes de producción de %s" % name, "nv-titulo", wrap=True), False, False, 0)
            box.pack_start(label("Mientras esté cargado (y, si está en el Apache de Docker, también allí), lo que "
                                 "falte en su carpeta wp-content/uploads (imágenes, vídeos y PDF) se pide a su web "
                                 "real: no hace falta descargarlo. Lo que ya está en local se sigue sirviendo desde "
                                 "aquí.", "nv-tenue", wrap=True,
                                 max_width_chars=60), False, False, 0)
            entry = Gtk.Entry(text=saved or guess, placeholder_text="ejemplo.com", max_length=80,
                              activates_default=True)
            box.pack_start(entry, False, False, 0)
            if guess and not saved:
                box.pack_start(label("Es el dominio de su BBDD: compruébalo antes de guardar.", "nv-chico", "nv-tenue"),
                               False, False, 0)
            dlg.get_content_area().add(box)
            if saved:
                css(dlg.add_button("Quitar", Gtk.ResponseType.REJECT), "destructive-action")
            dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
            ok = css(dlg.add_button("Guardar", Gtk.ResponseType.OK), "nv-azul")
            dlg.set_default_response(Gtk.ResponseType.OK)

            def clean():
                return re.sub(r"^https?://", "", entry.get_text().strip().lower()).rstrip("/")

            # (el mismo de antes también: se vuelve a aplicar, en web.local y en el Apache de Docker)
            def update(*_):
                d = clean()
                ok.set_sensitive(bool(DOMAIN_RX.match(d)) and not d.endswith((".local", ".test")))
            entry.connect("changed", update)
            dlg.show_all()
            update()
            resp = run_dialog(dlg)
            prod = clean()
            dlg.destroy()
            if resp == Gtk.ResponseType.REJECT:
                self.run_task("Quitando las imágenes de producción de %s" % name, ["media-proyecto", name, "quitar"],
                              done_text="%s ya no pide nada a producción" % name, auto_close=True)
            elif resp == Gtk.ResponseType.OK:
                self.run_task("Imágenes de producción de %s" % name, ["media-proyecto", name, prod],
                              done_text="%s pide a %s las imágenes que le faltan" % (name, prod), auto_close=True)
            return False
        run_quick(["gui-wp-produccion", name], got, env=self.db_env())

    def nv_ps_images(self, x):
        """ps-imagenes: una tienda se ve con su dominio real falseado (una redirección volvería aquí), así
        que las imágenes que faltan se descargan de la web real, con la lista de su BBDD."""
        name = x["name"]
        if not confirm(self.win, "¿Descargar las imágenes que le faltan a %s?" % name,
                       "Se descargan de su web real las imágenes de productos, categorías y marcas que no "
                       "están en su carpeta img (la lista sale de su BBDD: la de la versión activa o, si no está "
                       "allí, la de su proyecto del Apache de Docker). Van a su carpeta img, la misma con LAMPP y con "
                       "Docker. Lo que ya "
                       "está en local no se toca. Con muchos productos puede tardar y ocupar bastante.\n\n"
                       "Su dominio está falseado en este equipo: se busca con DNS cifrado (Cloudflare) y se "
                       "comprueba su certificado real.", "Descargar"):
            return
        self.check_db_access(lambda _pwd: self.run_task(
            "Descargando las imágenes de %s" % name, ["ps-imagenes", name], env=self.db_env(),
            done_text="Imágenes de %s descargadas" % name))

    def nv_delete_project(self, x):
        """Borra el proyecto entero (borrar-proyecto): su carpeta, sus vhosts y dominios, lo de Docker y,
        si se marca, su BBDD de la versión activa (la de phpMyAdmin), con copia por defecto. Hay que
        escribir el nombre de la carpeta para confirmar: la carpeta no se puede recuperar."""
        name = x["name"]
        active = self.data["active"] if self.data else None
        db = next((d for i, d in self.project_pairs(x) if i["folder"] == active), None)
        docker = self.nv_docker_of(name)
        dlg = Gtk.MessageDialog(transient_for=self.win, modal=True, message_type=Gtk.MessageType.WARNING,
                                buttons=Gtk.ButtonsType.NONE, text="¿Borrar el proyecto «%s»?" % name)
        what = ["su carpeta %s/%s" % (HTDOCS, name), "sus vhosts y las líneas de sus dominios en /etc/hosts"]
        if docker:
            what.append("sus contenedores de Docker (%s)" % ", ".join(dp["domain"] for dp in docker))
        dlg.format_secondary_markup("Se borran %s. <b>La carpeta no se puede recuperar.</b>"
                                    % GLib.markup_escape_text(", ".join(what[:-1]) + " y " + what[-1]))
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Borrar el proyecto", Gtk.ResponseType.ACCEPT), "destructive-action")
        dlg.set_default_response(Gtk.ResponseType.CANCEL)
        extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        drop = copy = None
        if db:
            drop = Gtk.CheckButton(label="Borrar también su BBDD «%s» (lampp-%s, la de phpMyAdmin)" % (db, active))
            copy = Gtk.CheckButton(label="Guardar antes una copia en ~/lvm-copias (se puede volver a cargar)",
                                   active=True, margin_start=24)
            extra.pack_start(drop, False, False, 0)
            extra.pack_start(copy, False, False, 0)
        extra.pack_start(label("Escribe %s para confirmar:" % name, "error", wrap=True, max_width_chars=50),
                         False, False, 0)
        entry = Gtk.Entry(activates_default=False)
        extra.pack_start(entry, False, False, 0)
        dlg.get_message_area().pack_start(extra, False, False, 0)

        def update(*_):
            if copy is not None:
                copy.set_sensitive(drop.get_active())
            ok.set_sensitive(entry.get_text().strip() == name)
        entry.connect("changed", update)
        if drop is not None:
            drop.connect("toggled", update)
        dlg.show_all()
        update()
        resp = run_dialog(dlg)
        with_db = bool(drop and drop.get_active())
        with_copy = bool(copy and copy.get_active())
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        args = ["borrar-proyecto", name]
        if with_db:
            args += ["--bd", db] + (["--copia"] if with_copy else [])
        done = "Proyecto «%s» borrado" % name + (" con su BBDD" if with_db else "") \
            + (" (copia en ~/lvm-copias)" if with_db and with_copy else "")

        def go(*_):
            self.run_task("Borrando el proyecto %s" % name, args, env=self.db_env() if with_db else None,
                          done_text=done)
        if with_db:
            self.check_db_access(go)
        else:
            go()

    def nv_import(self, x):
        pairs = self.project_pairs(x)
        act = next((d for i, d in pairs if i["folder"] == self.data["active"]), None)
        self.imp.update(project=x["name"], db=act or self.imp.get("db"))
        self.build_databases()
        self.show_tab("bbdd")
        self.toast("Elige el fichero en «Subir o actualizar una BBDD»: proyecto %s" % x["name"])

    def nv_new_project(self):
        # El asistente de siempre (clonar de git, version y BBDD), en una ventana aparte
        if getattr(self, "proj_box", None) is None:
            return
        if self.np_dialog is None:
            self.np_dialog = Gtk.Window(title="Nuevo proyecto", transient_for=self.win, modal=False)
            self.np_dialog.set_default_size(700, -1)
            self.np_dialog.connect("delete-event", lambda w, *_: (self.toggle_new_project(False), w.hide(), True)[2])
            if self.new_proj_rev.get_parent():
                self.new_proj_rev.get_parent().remove(self.new_proj_rev)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin=20)
            box.pack_start(self.new_proj_rev, True, True, 0)
            self.np_dialog.add(box)
        self.toggle_new_project(True)
        self.np_dialog.show_all()

    def toggle_new_project(self, show):
        super().toggle_new_project(show)
        if not show and self.np_dialog is not None:
            self.np_dialog.hide()

    def nv_page_title(self, box, symbol_name, title, sub, trailing=None):
        """Título grande arriba de una página hecha con los constructores de siempre (como el de las
        demás pestañas). trailing: un botón, a su derecha."""
        head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        tl = Gtk.Box(spacing=10)
        tl.pack_start(symbol(symbol_name, 26), False, False, 0)
        title_lbl = label(title, "nv-titulo-grande")
        tl.pack_start(title_lbl, False, False, 0)
        head.pack_start(tl, False, False, 0)
        sub_lbl = label(sub, "nv-chico", "nv-tenue", xalign=0, wrap=True)
        head.pack_start(sub_lbl, False, False, 0)
        parts = (tl, title_lbl, sub_lbl)
        if trailing is not None:
            line = Gtk.Box(spacing=12)
            line.pack_start(head, True, True, 0)
            line.pack_end(trailing, False, False, 0)
            head = line
        box.pack_start(head, False, False, 0)
        box.reorder_child(head, 0)
        head.show_all()
        return parts

    def build_hosts(self):
        super().build_hosts()
        # (los desplegables y el dominio, del mismo ancho: caben en los 2/3 de la tarjeta)
        for w in self.nv_walk(self.hosts_box):
            if isinstance(w, Gtk.ComboBox):
                narrow(w, 30)
            elif isinstance(w, Gtk.Entry):
                w.set_width_chars(30)
        view = nv_button("text-x-generic-symbolic", "Ver fichero de hosts",
                         "Ver %s" % (self.data["hosts"] if self.data else "/etc/hosts"),
                         self.on_view_hosts)
        self.nv_page_title(self.hosts_box, "network-workgroup-symbolic", "Dominios y hosts",
                           "Los dominios de los vhosts y los que se llevan a este equipo en /etc/hosts", view)

    def on_hosts_data(self, rc, out):
        old = self.hosts
        res = super().on_hosts_data(rc, out)
        # (el interruptor del proyecto cargado sigue a /etc/hosts; solo su recuadro, no toda la lista)
        if self.hosts != old and getattr(self, "nv_list", None) and self.projects and self.data:
            loaded = self.loaded_project_entry()
            if loaded is not None:
                self.nv_hero(loaded, loaded)
        return res

    def build_tools(self):
        # (antes de vaciar la pestaña: al soltar su tarjeta, GTK destruiría también el visor del correo)
        web = getattr(self, "mail_web", None)
        if web is not None and web.get_parent() is not None:
            web.get_parent().remove(web)
        super().build_tools()
        # Barrera entre webs (lvm-instalador barrera-web): encendida si no existe el fichero
        box, lb = tile_group("Seguridad entre webs",
                             "Impide que otra web abierta en tu navegador use tus proyectos locales sin que lo sepas.")
        on = not os.path.exists(os.path.join(LOG_DIR, "sin-barrera-entre-webs"))
        row = ActionRow("Barrera entre webs", "Encendida: tus proyectos solo aceptan lo que llega desde ellos mismos"
                        if on else "Apagada: enciéndela cuando acabes de probar los pagos")
        sw = Gtk.Switch(active=on, valign=Gtk.Align.CENTER, sensitive=not self.busy)
        sw.connect("notify::active", self.on_cross_site)
        row.add_suffix(sw)
        lb.add(row)
        # Qué es, explicado: el problema, lo que hace, cuándo apagarla y dónde vale
        box.pack_start(label("Qué es", "nv-apartado-titulo", xalign=0, margin_top=20), False, False, 0)
        why = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, margin_top=6), "caja")
        for ic, title, text in CROSS_SITE_HELP:
            r = ActionRow(title, text)
            r.add_prefix(symbol(ic, 18))
            r.subtitle.set_ellipsize(0)
            r.subtitle.set_line_wrap(True)
            r.subtitle.set_xalign(0)
            why.add(r)
        box.pack_start(why, False, False, 0)
        self.tools_box.pack_start(box, False, False, 0)
        self.tools_box.reorder_child(box, 1)
        box.show_all()
        self.nv_components_tools()
        self.nv_docker_tools()
        self.nv_tunnel_tools()
        self.nv_mail_tools()
        self.nv_github_tools()
        self.nv_look_tools()
        self.nv_tools_sections()
        self.tools_title = self.nv_page_title(self.tools_box, "emblem-system-symbolic", "Configuración",
                                              "Elige un apartado en la columna de la izquierda")
        self.nv_tools_title()

    # Apartados de Configuración: su nombre en la columna de la izquierda, su icono y el orden (los que no
    # estén aquí, al final)
    TOOLS_SECTIONS = [("Parches nuevos", "Parches nuevos", "software-update-available-symbolic"),
                      ("Configuración", "Vhosts y hosts", "network-workgroup-symbolic"),
                      ("Seguridad entre webs", "Seguridad entre webs", "security-high-symbolic"),
                      ("Correo de pruebas (Mailpit)", "Correo de pruebas", "mail-unread-symbolic"),
                      ("Docker", "Docker", "logo:docker"),
                      ("Túnel de Cloudflare", "Túnel de Cloudflare", "network-transmit-receive-symbolic"),
                      ("GitHub (Repositorios)", "GitHub", "logo:github"),
                      ("Registro de errores", "Registro de errores", "dialog-warning-symbolic"),
                      ("Apariencia", "Apariencia", "preferences-desktop-appearance-symbolic"),
                      ("Carpetas", "Carpetas", "folder-symbolic"),
                      ("XAMPP sin registrar", "XAMPP sin registrar", "drive-harddisk-symbolic"),
                      ("Programa", "Programa", "system-software-install-symbolic"),
                      ("Información", "Información", "help-about-symbolic")]

    def nv_tools_sections(self):
        """Configuración en dos columnas: a la izquierda, los encabezados de sus apartados; a la derecha, lo que
        se puede cambiar del elegido. Los apartados son los de siempre (cada constructor añade el suyo a
        tools_box): aqui se pasan a una hoja cada uno. El elegido se recuerda al rehacer la pestaña."""
        groups = list(self.tools_box.get_children())
        for g in groups:
            self.tools_box.remove(g)
        order = {t: n for n, (t, _, _) in enumerate(self.TOOLS_SECTIONS)}
        info = {t: (name, ic) for t, name, ic in self.TOOLS_SECTIONS}

        def title_of(g):
            for w in self.nv_walk(g):
                if isinstance(w, Gtk.Label) and w.get_style_context().has_class("grupo-titulo"):
                    return w.get_label()
            return ""
        found = sorted(((title_of(g) or "Otros", n, g) for n, g in enumerate(groups)),
                       key=lambda x: (order.get(x[0], len(order)), x[1]))
        stack = Gtk.Stack(vhomogeneous=False, hhomogeneous=False, hexpand=True,
                          transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=120)
        nav = css(Gtk.ListBox(valign=Gtk.Align.START), "nv-nav", "nv-subnav")
        rows = {}
        self.tools_desc = {}
        self.tools_extra = {}
        for title, _n, g in found:
            if title in rows:
                continue
            # (su nombre va en el título grande de arriba: aquí, sin repetirlo; su explicación, debajo de él)
            tlbl = next((w for w in self.nv_walk(g) if isinstance(w, Gtk.Label)
                         and w.get_style_context().has_class("grupo-titulo")), None)
            if tlbl is not None:
                head = tlbl.get_parent()
                kids = head.get_children()
                extra = []
                for n, c in enumerate(kids):
                    if c is not tlbl and isinstance(c, Gtk.EventBox) and c.get_tooltip_text():
                        self.tools_desc[title] = c.get_tooltip_text()
                    elif n > kids.index(tlbl):
                        # (lo de detrás del título, como el interruptor del correo, va al lado del título grande)
                        extra.append(c)
                    if c not in extra:
                        c.set_no_show_all(True)
                        c.hide()
                for c in extra:
                    head.remove(c)
                    c.set_valign(Gtk.Align.CENTER)
                    c.set_margin_start(14)
                    c.set_no_show_all(False)
                if extra:
                    self.tools_extra[title] = extra
                head.set_no_show_all(True)
                head.hide()
            stack.add_named(g, title)
            name, ic = info.get(title, (title, "emblem-system-symbolic"))
            row = Gtk.ListBoxRow()
            inner = Gtk.Box(spacing=10)
            inner.pack_start(MonoLogo(ic[5:], 16) if ic.startswith("logo:") else symbol(ic, 16), False, False, 0)
            inner.pack_start(label(name, ellipsize=3), True, True, 0)
            row.add(inner)
            row.section = title
            nav.add(row)
            rows[title] = row

        def picked(_lb, row):
            if row is not None:
                self.tools_section = row.section
                stack.set_visible_child_name(row.section)
                self.nv_tools_title()
        nav.connect("row-selected", picked)
        want = getattr(self, "tools_section", None)
        if want not in rows and found:
            want = found[0][0]
        for w in self.tools_side.get_children():
            w.destroy()
        self.tools_side.pack_start(label("CONFIGURACIÓN", "nv-seccion", margin_start=22, margin_top=16, margin_bottom=2),
                                   False, False, 0)
        self.tools_side.pack_start(nav, False, False, 0)
        self.tools_side.show_all()
        self.tools_box.pack_start(stack, True, True, 0)
        self.tools_nav = rows
        stack.show_all()
        if want:
            nav.select_row(rows[want])

    def nv_tools_title(self):
        """El título grande de Configuración: el del apartado abierto (su icono, su nombre y su explicación)."""
        parts = getattr(self, "tools_title", None)
        sec = getattr(self, "tools_section", None)
        if not parts or not sec:
            return
        tl, title_lbl, sub_lbl = parts
        info = {t: (name, ic) for t, name, ic in self.TOOLS_SECTIONS}
        name, ic = info.get(sec, (sec, "emblem-system-symbolic"))
        old = tl.get_children()[0]
        tl.remove(old)
        old.destroy()
        new = MonoLogo(ic[5:], 26) if ic.startswith("logo:") else symbol(ic, 26)
        tl.pack_start(new, False, False, 0)
        tl.reorder_child(new, 0)
        new.show()
        title_lbl.set_label(name)
        sub_lbl.set_label(getattr(self, "tools_desc", {}).get(sec) or "Configuración")
        # (lo que iba al lado del título del apartado: el de antes sale y entra el del abierto)
        for c in tl.get_children()[2:]:
            tl.remove(c)
        for c in getattr(self, "tools_extra", {}).get(sec, []):
            tl.pack_start(c, False, False, 0)
            c.show_all()

    def nv_tools_show(self, section):
        """Abre Configuración en ese apartado (su título, como en TOOLS_SECTIONS)."""
        self.tools_section = section
        self.show_tab("config")
        row = getattr(self, "tools_nav", {}).get(section)
        if row is not None and row.get_parent() is not None:
            row.get_parent().select_row(row)

    def nv_components_tools(self):
        """Configuración, Parches nuevos: lo que tiene un parche publicado (cada versión de PHP con su
        Apache, MariaDB, phpMyAdmin…, las imágenes de Docker, Mailpit y cloudflared) y «Actualizar todo»."""
        box, lb = tile_group("Parches nuevos",
                             "Los parches de seguridad de todo lo que usa Nexum: cada versión de PHP (PHP, Apache, "
                             "MariaDB, ProFTPD, Perl y phpMyAdmin, frente a lo último de su rama), las imágenes de "
                             "Docker (las MariaDB comunes, phpMyAdmin y PHP, frente a Docker Hub), Mailpit y "
                             "cloudflared. Se busca al abrir la ventana el primer arranque del día y cada pocos "
                             "arranques. Las versiones de PHP se rehacen (la de ahora sigue funcionando mientras se "
                             "compila); los contenedores de Docker se rehacen en unos segundos, con sus BBDD.")
        row = ActionRow("Componentes", "Buscando parches nuevos…")
        row.add_prefix(icon("software-update-available-symbolic", 18))
        row.wide = True
        lb.add(row)
        self.tools_box.pack_start(box, False, False, 0)
        self.tools_box.reorder_child(box, 1)
        box.show_all()
        cached = getattr(self, "components", None)
        if cached is not None:
            self.nv_components_fill(row, cached)
        else:
            run_quick(["componentes"], lambda rc, out: (self.nv_components_got(out, row), False)[1])

    def nv_components_got(self, out, row=None):
        res = {"items": [], "notes": [], "errors": [], "n": 0}
        for f in parse_lines(out):
            if f[0] == "L" and len(f) >= 5:
                res["items"].append("lampp-%s: %s %s → %s" % (f[1], f[2], f[3], f[4]))
            elif f[0] == "K" and len(f) >= 3:
                res["items"].append("%s (%s): versión nueva en Docker Hub" % (f[1], f[2]))
            elif f[0] == "X" and len(f) >= 4:
                res["items"].append("%s: %s → %s" % (f[1], f[2], f[3]))
            elif f[0] == "E" and len(f) >= 2:
                res["errors"].append(f[1])
            elif f[0] == "S" and len(f) >= 2 and f[1].isdigit():
                res["n"] = int(f[1])
        self.components = res
        self.nv_warn_refresh()
        # (si Configuración se ha rehecho mientras tanto, esa fila ya no está en la ventana)
        if row is not None and row.subtitle.get_toplevel() is self.win:
            self.nv_components_fill(row, res)
        return res

    def nv_components_fill(self, row, res):
        if res["items"]:
            text = "\n".join("• " + i for i in res["items"])
        elif res["errors"]:
            text = "No se ha podido consultar: %s" % ", ".join(res["errors"])
        else:
            text = "Todo al día: no hay parches nuevos."
        if res["items"] and res["errors"]:
            text += "\n(No se ha podido consultar: %s)" % ", ".join(res["errors"])
        row.subtitle.set_label(text)
        for ch in row.suffix.get_children():
            row.suffix.remove(ch)
        b = Gtk.Button(label="Buscar de nuevo", valign=Gtk.Align.CENTER, sensitive=not self.busy)
        b.connect("clicked", lambda *_: (setattr(self, "components", None), self.build_tools()))
        row.add_suffix(b)
        if res["items"]:
            b = css(Gtk.Button(label="Actualizar todo (%d)" % len(res["items"]), valign=Gtk.Align.CENTER,
                               sensitive=not self.busy), "verde")
            b.connect("clicked", lambda *_: self.nv_components_update(res))
            row.add_suffix(b)
        row.suffix.show_all()

    def nv_components_update(self, res, ask=True):
        if ask and not confirm(self.win, "¿Actualizar todo?",
                               "Las versiones de PHP se rehacen con lo último de su rama (varios minutos; la de "
                               "ahora sigue funcionando mientras se compila). Los contenedores de Docker en marcha se "
                               "rehacen en unos segundos: sus BBDD y su configuración no cambian.", "Actualizar todo",
                               steps=res["items"]):
            return
        self.components = None
        self.run_task("Actualizando los componentes", ["componentes-actualizar"], progress=True,
                      reload_branches=True, done_text="Componentes al día",
                      on_done=lambda *_: self.build_tools())

    def nv_components_auto(self):
        """Al abrir (cuando toca buscar una versión nueva del programa): si algo tiene un parche nuevo,
        se dice y se ofrece actualizarlo todo."""
        def got(_rc, out):
            res = self.nv_components_got(out)
            # (sin preguntar: el aviso de arriba lo dice, y se puede dejar para luego)
            if res["items"] and not updates_ignored(res["items"]):
                self.toast("Hay parches nuevos: míralos en los avisos de arriba")
            return False
        run_quick(["componentes"], got)
        return False

    def nv_warn_refresh(self):
        """Los avisos de arriba: los de las versiones y, si hay parches nuevos que no se han dejado para
        luego, el suyo, el primero."""
        if not hasattr(self, "warn_box"):
            return
        for ch in self.warn_box.get_children():
            if getattr(ch, "nv_updates", False):
                ch.destroy()
        res = getattr(self, "components", None)
        if res and res["items"] and not updates_ignored(res["items"]):
            n = len(res["items"])
            box, lb = group("Hay parches nuevos (%d)" % n, None)
            box.nv_updates = True
            shown = res["items"][:6] + (["…y %d más" % (n - 6)] if n > 6 else [])
            row = ActionRow("Conviene ponerlos: son parches de seguridad",
                            "\n".join("• " + i for i in shown) + "\nLo de ahora sigue funcionando mientras se actualiza "
                            "(se puede seguir en segundo plano). Si no quieres cambiar nada, «Ahora no» lo deja hasta "
                            "que salga otro parche; siguen en Configuración, Parches nuevos.")
            row.add_prefix(icon("software-update-available-symbolic", 18))
            # (entero, sin cortar: en el aviso hay sitio)
            for lbl in (row.title, row.subtitle):
                lbl.set_ellipsize(0)
                lbl.set_line_wrap(True)
                lbl.set_max_width_chars(46)
            later = Gtk.Button(label="Ahora no", valign=Gtk.Align.CENTER)
            later.connect("clicked", lambda *_: (self.warn_btn.get_popover().popdown(), updates_ignore(res["items"]),
                                                 self.nv_warn_refresh()))
            row.add_suffix(later)
            go = css(Gtk.Button(label="Actualizar todo", valign=Gtk.Align.CENTER, sensitive=not self.busy), "verde")
            go.connect("clicked", lambda *_: (self.warn_btn.get_popover().popdown(), self.nv_components_update(res)))
            row.add_suffix(go)
            lb.add(row)
            self.warn_box.pack_start(box, False, False, 0)
            self.warn_box.reorder_child(box, 0)
        self.warn_box.show_all()
        n = len(self.warn_box.get_children())
        self.warn_num.set_label(str(n))
        self.warn_btn.set_visible(n > 0)

    # ------------------------------------------------------------------ repositorios de GitHub
    def nv_github_tools(self):
        """Configuración, GitHub: la conexión (un token en el llavero o la sesión de gh), la organización o
        cuenta y los prefijos de los repositorios que se ven en Repositorios."""
        box, lb = tile_group("GitHub (Repositorios)",
                             "Para la pestaña Repositorios: la lista de una organización o cuenta de GitHub, para "
                             "clonarlos por SSH (con tu clave) en /opt/htdocs. La lista se lee con un token de GitHub, "
                             "que se guarda en el llavero de la sesión (no en un fichero), o con tu sesión de gh. "
                             "Solo se ven los repositorios que empiezan por alguno de los prefijos (en la pestaña, "
                             "«Mostrar todos» enseña el resto).")
        self.tools_box.pack_start(box, False, False, 0)
        # (debajo del correo de pruebas)
        self.tools_box.reorder_child(box, 3)

        def fill(_rc, out):
            g = next((f for f in parse_lines(out) if f[0] == "G" and len(f) >= 6), None)
            # (si Configuración se ha rehecho mientras tanto, este apartado ya no está en la ventana)
            if g is None or box.get_toplevel() is not self.win:
                return False
            self.github_out = out
            self.github = {"on": g[1] == "1", "login": g[2], "source": g[3], "account": g[4], "prefixes": g[5]}
            gh = self.github
            how = {"llavero": "con el token del llavero", "gh": "con tu sesión de gh"}.get(gh["source"], "")
            row = ActionRow("Conexión", ("Conectado como %s, %s" % (gh["login"], how)) if gh["on"] else
                            "⚠ El token ya no vale (¿caducado?): conéctalo de nuevo" if gh["source"] else
                            "Sin conectar: hace falta para ver la lista de repositorios (también los privados)")
            row.add_prefix(logo("github", 18))
            row.wide = True
            b = css(Gtk.Button(label="Conectar con un token…", valign=Gtk.Align.CENTER, sensitive=not self.busy),
                    *(() if gh["on"] else ("verde",)))
            b.connect("clicked", lambda *_: self.nv_github_token())
            row.add_suffix(b)
            if shutil.which("gh") and gh["source"] != "gh":
                b = Gtk.Button(label="Usar la sesión de gh", valign=Gtk.Align.CENTER, sensitive=not self.busy,
                               tooltip_text="Usar la sesión de gh auth login")
                b.connect("clicked", lambda *_: run_quick(["github-conectar", "--gh"], self.nv_github_done))
                row.add_suffix(b)
            if gh["source"]:
                b = Gtk.Button(label="Desconectar", valign=Gtk.Align.CENTER, sensitive=not self.busy)
                b.connect("clicked", lambda *_: run_quick(["github-desconectar"], self.nv_github_done))
                row.add_suffix(b)
            lb.add(row)
            for key, title, sub, value, width in (
                    ("cuenta", "Organización o cuenta", "La de los repositorios que se ven (por ejemplo, hexer-dev)",
                     gh["account"], 22),
                    ("prefijos", "Prefijos de los repositorios",
                     "Separados por espacios (dob-wordpress- dob-prestashop- …); vacío: todos", gh["prefixes"], 34)):
                row = ActionRow(title, sub)
                entry = Gtk.Entry(text=value, width_chars=width, valign=Gtk.Align.CENTER)
                save = Gtk.Button(label="Guardar", valign=Gtk.Align.CENTER, sensitive=False)
                entry.connect("changed", lambda e, b=save, v=value: b.set_sensitive(e.get_text().strip() != v))
                save.connect("clicked", lambda _b, k=key, e=entry: run_quick(["github", k, e.get_text().strip()],
                                                                            self.nv_github_saved))
                entry.connect("activate", lambda e, b=save: b.get_sensitive() and b.clicked())
                row.add_suffix(entry)
                row.add_suffix(save)
                lb.add(row)
            box.show_all()
            return False
        # (lo de la última vez, al momento: se lee de nuevo al conectar o cambiar algo)
        if getattr(self, "github_out", None):
            fill(0, self.github_out)
        else:
            run_quick(["github"], fill)

    def nv_github_done(self, rc, out):
        lines = [l for l in out.strip().splitlines() if l.strip()]
        self.toast(lines[-1] if lines else ("Hecho" if rc == 0 else "No se ha podido"))
        # (la lista de antes puede ser de otra cuenta o con otros prefijos)
        self.repos, self.github_out = None, None
        self.build_tools()
        return False

    def nv_github_saved(self, rc, out):
        """Guardar la cuenta o los prefijos: si no vale, se dice en una ventana y lo escrito se queda."""
        lines = [l for l in out.strip().splitlines() if l.strip()]
        if rc != 0:
            message(self.win, "No se ha guardado", lines[-1] if lines else "No se ha podido guardar", Gtk.MessageType.WARNING)
            return False
        return self.nv_github_done(rc, out)

    def nv_github_token(self):
        dlg = Gtk.Dialog(title="Conectar con GitHub", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(520, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        head = Gtk.Box(spacing=10)
        head.pack_start(logo("github", 28), False, False, 0)
        head.pack_start(label("Token de GitHub", "nv-titulo"), False, False, 0)
        box.pack_start(head, False, False, 0)
        box.pack_start(label("Solo para leer la lista de repositorios (también los privados): se clonan por SSH, con tu "
                             "clave. Créalo en GitHub con el permiso «repo» (y «read:org» para los de una organización) "
                             "y pégalo aquí. Se guarda en el llavero de la sesión, no en un fichero.",
                             "nv-tenue", wrap=True, max_width_chars=60), False, False, 0)
        link = Gtk.LinkButton(uri="https://github.com/settings/tokens/new?scopes=repo,read:org&description=Nexum%20Dev%20Stack",
                              label="Crear un token en GitHub", halign=Gtk.Align.START)
        box.pack_start(link, False, False, 0)
        entry = Gtk.Entry(visibility=False, input_purpose=Gtk.InputPurpose.PASSWORD, activates_default=True,
                          placeholder_text="ghp_… o github_pat_…")
        box.pack_start(entry, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        ok = css(dlg.add_button("Conectar", Gtk.ResponseType.OK), "nv-azul")
        ok.set_sensitive(False)
        entry.connect("changed", lambda e: ok.set_sensitive(len(e.get_text().strip()) >= 20))
        dlg.set_default_response(Gtk.ResponseType.OK)
        dlg.show_all()
        resp = run_dialog(dlg)
        token = entry.get_text().strip()
        dlg.destroy()
        if resp == Gtk.ResponseType.OK and token:
            self.toast("Comprobando el token con GitHub…")
            run_quick_input(["github-conectar"], token + "\n", self.nv_github_done)

    def nv_node_load(self):
        """Pestaña Node: los proyectos de htdocs con su package.json y cómo están."""
        def got(_rc, out):
            self.nv_node_parse(out)
            self.nv_node_render()
            return False
        run_quick(["gui-node"], got)

    def nv_node_parse(self, out):
        self.node_rows = [{"folder": f[1], "kind": f[2], "running": f[3] == "marcha", "mode": f[4], "url": f[5],
                           "need": f[6], "deps": f[7] == "1", "scripts": f[8]}
                          for f in parse_lines(out) if f[0] == "P" and len(f) >= 9]

    def nv_node_render(self):
        if self.node_rows is None:
            return
        box = self.node_page
        clear(box)
        head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        head.pack_start(label("Node", "nv-titulo-grande"), False, False, 0)
        head.pack_start(label("Proyectos de %s hechos con Astro, Next, Nuxt, SvelteKit o Vite. Cada uno con su servidor en "
                              "este equipo, con tu usuario y con la versión de Node que pide." % HTDOCS,
                              "nv-chico", "nv-tenue", wrap=True, xalign=0), False, False, 0)
        box.pack_start(head, False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        for p in self.node_rows:
            lb.add(self.nv_node_row(p))
        if not self.node_rows:
            lb.add(ActionRow("Ningún proyecto de Node", "Se buscan las carpetas de %s con su package.json" % HTDOCS))
        box.pack_start(lb, False, False, 0)
        box.show_all()

    def nv_node_row(self, p):
        bits = [p["kind"], "Node %s" % p["need"] if p["need"] else ""]
        if p["running"]:
            bits.append("en marcha (%s): %s" % (p["mode"], p["url"]))
        elif not p["deps"]:
            bits.append("sin dependencias instaladas: se instalan al arrancar")
        row = ActionRow(p["folder"], " · ".join(b for b in bits if b))
        row.add_prefix(label("●", "punto-verde" if p["running"] else "punto-gris"))
        path = os.path.join(HTDOCS, p["folder"])

        def add(image, text, tip, cb, *classes, task=True):
            b = nv_button(image, text, tip, lambda *_: cb(), "nv-proyecto-btn", *classes)
            b.set_sensitive(not (task and self.busy))
            row.add_suffix(b)
        # (los de siempre, solo con su icono: el proyecto en el editor, en su carpeta y lo que dice su servidor)
        code = vscode_app()
        if code is not None:
            img = None
            if code.get_icon() is not None:
                img = Gtk.Image.new_from_gicon(code.get_icon(), Gtk.IconSize.BUTTON)
                img.set_pixel_size(18)
            add(img or "text-editor-symbolic", None, "Abrir en Visual Studio Code", lambda: self.open_in_vscode(path), task=False)
        add("folder-open-symbolic", None, "Abrir su carpeta", lambda: self.open_uri(GLib.filename_to_uri(path, None)), task=False)
        add(logo("log", 18), None, "Registro: lo último que ha dicho su servidor", lambda: self.run_task(
            "Registro de %s" % p["folder"], ["node-registro", p["folder"]]))
        if p["running"]:
            add("view-refresh-symbolic", None, "Volver a compilar y arrancar" if p["mode"] == "compilado" else "Reiniciar su servidor",
                lambda: self.nv_node_start(p, p["mode"]))
            add(logo("globo", 18), "Abrir web", "Abrir %s" % p["url"], lambda: self.open_uri(p["url"]), task=False)
        else:
            add("media-playback-start-symbolic", "Arrancar", "En desarrollo: los cambios se ven al momento",
                lambda: self.nv_node_start(p, "desarrollo"))
            add("system-run-symbolic", "Compilar", "Compilar y arrancar, como en producción",
                lambda: self.nv_node_start(p, "compilado"))
        st = tunnel_state()
        if p["running"] and st and st["target"] == p["url"]:
            add(logo("cloudflare", 18), "Compartiendo", "Ver dirección y contraseña del túnel",
                lambda: self.nv_share_dialog(), "nv-compartiendo", task=False)
        else:
            add(logo("cloudflare", 18), "Túnel", "Compartir con un túnel de Cloudflare" if p["running"] and p["mode"] == "compilado"
                else "Compilar, arrancar y compartir con un túnel de Cloudflare", lambda: self.nv_node_share(p))
        if p["running"]:
            add("media-playback-stop-symbolic", "Parar", "Parar su servidor (y su túnel, si se está compartiendo)",
                lambda: self.nv_node_stop(p))
        return row

    def nv_node_share(self, p):
        """Túnel: solo se comparte lo compilado (el túnel no deja pasar /node_modules/.vite y así el código
        fuente no sale del equipo). Si no lo está, se compila y arranca antes."""
        path = os.path.join(HTDOCS, p["folder"])
        if p["running"] and p["mode"] == "compilado":
            self.nv_share(p["url"], path, p["folder"], live=False)
            return
        if p["running"] and not confirm(self.win, "¿Compilar %s para compartirlo?" % p["folder"],
                                        "Está en desarrollo, y lo que se comparte es la versión compilada. Se para y "
                                        "arranca compilado: los cambios ya no se verán al momento.", "Compilar y compartir"):
            return

        def got(_rc, out):
            self.nv_node_parse(out)
            self.nv_node_render()
            now = next((r for r in self.node_rows if r["folder"] == p["folder"]), None)
            if now and now["running"]:
                GLib.idle_add(lambda: self.nv_share(now["url"], path, p["folder"], live=False) and False)
            return False
        self.run_task("Arrancando %s" % p["folder"], ["node-arrancar", p["folder"], "compilado"], progress=True, auto_close=True,
                      done_text="%s en marcha" % p["folder"],
                      on_done=lambda ok, *_: run_quick(["gui-node"], got) if ok else self.nv_node_load())

    def nv_node_start(self, p, mode):
        self.run_task("Arrancando %s" % p["folder"], ["node-arrancar", p["folder"], mode], progress=True, auto_close=True,
                      done_text="%s en marcha" % p["folder"], on_done=lambda *_: self.nv_node_load())

    def nv_node_stop(self, p):
        def done(*_):
            self.nv_node_load()
        self.run_task("Parando %s" % p["folder"], ["node-parar", p["folder"]], auto_close=True,
                      done_text="%s parado" % p["folder"], on_done=done)

    def nv_repos_open(self):
        """Al entrar en Repositorios: la lista de la última vez, al momento, y luego la de GitHub."""
        if self.repos is None:
            self.nv_repos_render(loading=True)
            self.nv_repos_load(cache=True)
        self.nv_repos_load()

    def nv_repos_load(self, cache=False):
        args = ["repos"] + (["--todos"] if self.repos_all else []) + (["--cache"] if cache else [])
        if not cache:
            self.repos_loading = True

        def got(_rc, out):
            if not cache:
                self.repos_loading = False
            res = {"rows": [], "error": None, "head": None}
            for f in parse_lines(out):
                if f[0] == "R" and len(f) >= 11:
                    res["rows"].append({"full": f[1], "name": f[2], "private": f[3] == "1", "date": f[4],
                                        "branch": f[5], "prefix": f[6], "web": f[7], "desc": f[8],
                                        "state": f[9], "folder": f[10]})
                elif f[0] == "C" and len(f) >= 6:
                    res["head"] = f
                elif f[0] == "E" and len(f) >= 2:
                    res["error"] = f[1]
            if cache and not res["head"]:
                return False
            if not cache and res["error"] and self.repos and self.repos.get("head"):
                # (sin conexión con GitHub: se queda la lista de la última vez, y se dice)
                self.repos["error"] = res["error"]
            else:
                self.repos = res
            self.nv_repos_render()
            return False
        run_quick(args, got)

    def nv_repos_render(self, loading=False):
        box = self.repos_page
        clear(box)
        head = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        tl = Gtk.Box(spacing=10)
        tl.pack_start(MonoLogo("github", 26), False, False, 0)
        tl.pack_start(label("Repositorios", "nv-titulo-grande"), False, False, 0)
        head.pack_start(tl, False, False, 0)
        r = self.repos or {}
        h = r.get("head")
        sub = ("%s en GitHub: %s de %s repositorios%s" % (h[2], h[5], h[4], "" if self.repos_all else " (los de sus prefijos)")
               if h else "Los repositorios de tu organización en GitHub, para clonarlos por SSH en /opt/htdocs")
        head.pack_start(label(sub, "nv-chico", "nv-tenue"), False, False, 0)
        box.pack_start(head, False, False, 0)
        if r.get("error") and not h:
            card = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10), "nv-mosaico")
            card.pack_start(label(r["error"], wrap=True, xalign=0), False, False, 0)
            b = Gtk.Button(label="Ir a Configuración", halign=Gtk.Align.START)
            b.connect("clicked", lambda *_: self.nv_tools_show("GitHub (Repositorios)"))
            card.pack_start(b, False, False, 0)
            box.pack_start(card, False, False, 0)
            box.show_all()
            return
        bar = Gtk.Box(spacing=10)
        search = Gtk.SearchEntry(placeholder_text="Buscar por nombre, descripción o web", width_chars=36)
        bar.pack_start(search, False, False, 0)
        bar.pack_start(label("Mostrar todos", "nv-tenue", valign=Gtk.Align.CENTER), False, False, 0)
        sw = Gtk.Switch(active=self.repos_all, valign=Gtk.Align.CENTER,
                        tooltip_text="Incluir los que no tienen prefijo")
        sw.connect("notify::active", lambda w, _p: (setattr(self, "repos_all", w.get_active()),
                                                    self.nv_repos_load(cache=True), self.nv_repos_load()))
        bar.pack_start(sw, False, False, 0)
        if loading or getattr(self, "repos_loading", False):
            bar.pack_end(Gtk.Spinner(active=True), False, False, 0)
        else:
            rb = nv_button("view-refresh-symbolic", None, "Leer de nuevo la lista de GitHub", lambda *_: self.nv_repos_load())
            bar.pack_end(rb, False, False, 0)
        if r.get("error"):
            bar.pack_end(label("⚠ " + r["error"], "nv-chico", wrap=True, max_width_chars=40), False, False, 0)
        box.pack_start(bar, False, False, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "caja")
        for repo in r.get("rows", []):
            lb.add(self.nv_repo_row(repo))
        if not r.get("rows"):
            lb.add(ActionRow("Cargando la lista de GitHub…" if loading or getattr(self, "repos_loading", False)
                             else "Ningún repositorio", ""))

        def match(row):
            q = search.get_text().strip().lower()
            return not q or q in getattr(row, "haystack", "")
        lb.set_filter_func(match)
        search.connect("search-changed", lambda *_: lb.invalidate_filter())
        box.pack_start(lb, False, False, 0)
        box.show_all()

    def nv_repo_row(self, repo):
        bits = [b for b in (("clonado en %s" % repo["folder"]) if repo["state"] == "clonado" else "", repo["desc"], repo["web"],
                            ("actualizado el %s" % repo["date"]) if repo["date"] else "") if b]
        row = ActionRow(repo["name"] + ("  🔒" if repo["private"] else ""), " · ".join(bits))
        kind = next((k for k in ("wordpress", "prestashop") if k in repo["prefix"] or k in repo["name"]), None)
        row.add_prefix(logo(kind, 20) if kind else MonoLogo("github", 20))
        row.haystack = " ".join((repo["full"], repo["desc"], repo["web"])).lower()
        if repo["state"] == "clonado":
            b = Gtk.Button(label="Traer cambios", valign=Gtk.Align.CENTER, sensitive=not self.busy,
                           tooltip_text="Actualizar con git pull")
            b.connect("clicked", lambda *_: self.nv_repo_fetch(repo))
        elif repo["state"] == "ocupado":
            b = Gtk.Button(label="Clonar", valign=Gtk.Align.CENTER, sensitive=False,
                           tooltip_text="Ya hay una carpeta con ese nombre")
        else:
            b = css(Gtk.Button(label="Clonar", valign=Gtk.Align.CENTER, sensitive=not self.busy,
                               tooltip_text="Clonar por SSH en /opt/htdocs"), "verde")
            b.connect("clicked", lambda *_: self.nv_repo_fetch(repo))
        row.add_suffix(b)
        # (detrás, el repositorio en GitHub: sus cambios, ramas y pull requests; solo el logotipo, así
        # todos los botones quedan a la misma altura)
        # (para pegarlo en Nuevo proyecto)
        cp = Gtk.Button(valign=Gtk.Align.CENTER, tooltip_text="Copiar repositorio")
        cp.add(icon("edit-copy-symbolic"))
        cp.connect("clicked", lambda *_: self.nv_repo_copy(repo))
        row.add_suffix(cp)
        gh = Gtk.Button(valign=Gtk.Align.CENTER, tooltip_text="Abrir en GitHub")
        gh.add(MonoLogo("github", 18))
        gh.connect("clicked", lambda *_: self.open_uri("https://github.com/%s" % repo["full"]))
        row.add_suffix(gh)
        return row

    def nv_repo_copy(self, repo):
        Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text("git@github.com:%s.git" % repo["full"], -1)
        self.toast("Repositorio copiado: %s" % repo["name"])

    def nv_repo_fetch(self, repo):
        if repo["state"] == "clonado":
            if not confirm(self.win, "¿Aplastar %s con lo de GitHub?" % repo["folder"],
                           "Este repositorio ya está clonado en /opt/htdocs/%s. Se traen sus cambios de GitHub (git pull) "
                           "y se juntan con los tuyos. Si chocan con lo que tienes sin subir o sin guardar, no se toca "
                           "nada y se dice." % repo["folder"], "Traer los cambios"):
                return
            args, title = ["repo-traer", repo["full"], "--actualizar"], "Trayendo los cambios de %s" % repo["name"]
        else:
            args, title = ["repo-traer", repo["full"]], "Clonando %s" % repo["name"]

        def done(ok, *_):
            # (su estado, de nuevo: ya clonado, en su carpeta)
            self.nv_repos_load(cache=True)
            if ok and repo["state"] != "clonado":
                self.toast("%s, en Proyectos" % repo["name"])
        self.run_task(title, args, auto_close=True, done_text="Hecho", on_done=done)

    def nv_docker_tools(self):
        """Configuración del Apache de Docker (docker-web): su dirección y sus puertos, permitir que Docker
        sin root use los de menos de 1024 y que el navegador acepte el certificado de *.docker.local."""
        w = {"IP": "127.0.0.2", "HTTP": "80", "HTTPS": "443"}
        try:
            for line in open(os.path.join(LOG_DIR, "docker", "web.conf"), encoding="utf-8", errors="replace"):
                k, _, v = line.strip().partition("=")
                if k in w and re.fullmatch(r"[0-9.]{1,15}", v):
                    w[k] = v
        except OSError:
            pass
        try:
            start = int(open("/proc/sys/net/ipv4/ip_unprivileged_port_start").read().strip())
        except (OSError, ValueError):
            start = 1024
        ports_ok = min(int(w["HTTP"]), int(w["HTTPS"])) >= start
        box, lb = tile_group("Docker",
                        "Los proyectos de Docker van con su propio Apache, en otra dirección de este equipo (nunca "
                        "abierta a la red): funcionan sin LAMPP y a la vez que él, con las mismas reglas de seguridad. "
                        "Con los puertos 80 y 443, las direcciones van sin puerto.", tiles=True)
        # La dirección y los dos puertos, juntos en una tarjeta a lo ancho (con Guardar y, si hace falta, Permitir)
        entries = {}
        row = ActionRow("Dirección y puertos",
                        "De este equipo (127.x.x.x; 127.0.0.1 con 80 y 443 es la de LAMPP). HTTP lleva siempre a https; si "
                        "HTTPS no es el 443, las direcciones lo llevan (https://…:8443). "
                        + ("Docker sin root ya puede usar sus puertos." if ports_ok else
                           "Docker sin root aún no puede usar los de menos de 1024: se permite una vez."))
        row.wide = True
        # (los campos en una línea y, debajo, a la derecha, Guardar y, si hace falta, Permitir)
        form = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, valign=Gtk.Align.CENTER)
        fields = Gtk.Box(spacing=8)
        form.pack_start(fields, False, False, 0)
        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.END)
        form.pack_start(buttons, False, False, 0)
        row.add_suffix(form)
        for key, text, width in (("IP", "Dirección", 13), ("HTTP", "HTTP", 5), ("HTTPS", "HTTPS", 5)):
            field = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
            field.pack_start(label(text, "nv-chico", "nv-tenue"), False, False, 0)
            e = Gtk.Entry(text=w[key], width_chars=width, max_length=15)
            field.pack_start(e, False, False, 0)
            fields.pack_start(field, False, False, 0)
            entries[key] = e

        def save(*_):
            ip, http, https = (entries[k].get_text().strip() for k in ("IP", "HTTP", "HTTPS"))
            if not re.fullmatch(r"127\.\d{1,3}\.\d{1,3}\.\d{1,3}", ip) or not http.isdigit() or not https.isdigit():
                message(self.win, "Dirección o puertos no válidos",
                        "La dirección tiene que ser de este equipo (127.x.x.x, como 127.0.0.2) y los puertos, números.",
                        Gtk.MessageType.WARNING)
                return
            self.run_task("Dirección y puertos del Apache de Docker", ["docker-web", "puertos", ip, http, https],
                          done_text="Apache de Docker en %s (%s y %s)" % (ip, http, https), auto_close=True,
                          on_done=lambda *a: (run_quick(["gui-docker"], self.on_docker_data), self.build_tools()))
        if not ports_ok:
            b = Gtk.Button(label="Permitir", sensitive=not self.busy,
                           tooltip_text="Permitir puertos desde el %s"
                           % min(int(w["HTTP"]), int(w["HTTPS"])))
            b.connect("clicked", lambda *_: self.run_task(
                "Permitiendo los puertos del Apache de Docker", ["docker-web", "permitir"], auto_close=True,
                done_text="Docker ya puede usar sus puertos",
                on_done=lambda *a: (run_quick(["gui-docker"], self.on_docker_data), self.build_tools())))
            buttons.pack_start(b, False, False, 0)
        b = css(Gtk.Button(label="Guardar", sensitive=not self.busy), "verde")
        b.connect("clicked", save)
        buttons.pack_start(b, False, False, 0)
        lb.add(row)
        # DNS comodín de *.docker.test: los dominios de Docker ya no van en /etc/hosts (sin contraseña al
        # añadir proyectos o versiones). web.local y lo demás, igual
        conf = {}
        try:
            for line in open(os.path.join(LOG_DIR, "docker", "web.conf"), encoding="utf-8", errors="replace"):
                k, _, v = line.strip().partition("=")
                conf[k] = v
        except OSError:
            pass
        dns = conf.get("DNS") == "1" and conf.get("TLD") == "docker.test"
        row = ActionRow("DNS de *.docker.test",
                        "Puesto: los dominios de Docker (<proyecto>-php83.docker.test) no van en /etc/hosts ni piden la contraseña"
                        if dns else "Los dominios de Docker pasan a .docker.test y dejan de ir en /etc/hosts: sin contraseña al "
                        "añadir proyectos o versiones. web.local, los proyectos de siempre y las tiendas falseadas, igual")
        b = Gtk.Button(label="Quitar" if dns else "Activar", valign=Gtk.Align.CENTER, sensitive=not self.busy)
        b.connect("clicked", lambda *_: self.nv_docker_dns(not dns))
        row.add_suffix(b)
        lb.add(row)
        row = ActionRow("Certificado de *.docker.local y *.docker.test",
                        "Chrome y Firefox lo aceptan sin aviso: solo vale para esos dominios (no es de una CA)")
        b = Gtk.Button(label="Confiar", valign=Gtk.Align.CENTER, sensitive=not self.busy)
        b.connect("clicked", lambda *_: self.run_task("Certificado de Docker en el navegador", ["docker-web", "confiar"],
                                                      done_text="El navegador acepta el certificado de Docker", auto_close=True))
        row.add_suffix(b)
        lb.add(row)
        # Los proyectos sin visitas se paran solos (docker-reposo): cuántas horas (0: nunca; 3 si no se ha dicho)
        try:
            idle = open(os.path.join(LOG_DIR, "docker", "reposo"), encoding="utf-8").read(10).strip()
        except OSError:
            idle = "3"
        idle = idle if re.fullmatch(r"[0-9]|1[0-9]|2[0-4]", idle) else "3"
        try:
            last = open(os.path.join(LOG_DIR, "docker-reposo.log"), encoding="utf-8", errors="replace").read().strip().splitlines()[-1]
        except (OSError, IndexError):
            last = ""
        row = ActionRow("Parar los proyectos sin visitas",
                        ("Un proyecto de Docker que lleva esas horas sin ninguna visita (tampoco por el túnel) se para "
                         "solo, y con él lo común que ya no use nadie (su MariaDB, el Apache de Docker): no gasta "
                         "memoria ni CPU. Se mira cada 15 minutos, también con la ventana cerrada. Al entrar en uno "
                         "parado, la web lo dice: se arranca en la pestaña Docker." if idle != "0" else
                         "Apagado: los proyectos de Docker siguen en marcha hasta que se paren a mano")
                        + ("\nLo último: %s" % last if last and idle != "0" else ""))
        row.wide = True
        combo = Gtk.ComboBoxText(valign=Gtk.Align.CENTER, sensitive=not self.busy)
        for h in ("0", "1", "2", "3", "4", "6", "8", "12", "24"):
            combo.append(h, "Nunca" if h == "0" else "A la hora sin visitas" if h == "1" else "A las %s h sin visitas" % h)
        if not combo.set_active_id(idle):
            combo.append(idle, "A las %s h sin visitas" % idle)
            combo.set_active_id(idle)
        combo.connect("changed", lambda c: c.get_active_id() != idle and run_quick(
            ["docker-reposo", "horas", c.get_active_id()],
            lambda rc, out: (self.toast((out.strip().splitlines() or ["Hecho"])[-1]), self.build_tools(), False)[2]))
        row.add_suffix(combo)
        lb.add(row)
        self.tools_box.pack_start(box, False, False, 0)
        self.tools_box.reorder_child(box, 2)
        box.show_all()

    def nv_tunnel_tools(self):
        """Configuración, Túnel de Cloudflare: cloudflared, el túnel abierto (con Cerrar) y su registro. La
        contraseña, las horas y el admin de cada túnel se eligen al abrirlo («Compartir»)."""
        box, lb = tile_group("Túnel de Cloudflare",
                        "Para enseñar una web de este equipo a un cliente o a un compañero: una dirección "
                        "https://….trycloudflare.com (sin cuenta de Cloudflare; cambia cada vez) con contraseña, "
                        "que se cierra sola. Sin abrir puertos del router. La web no se toca: su dominio local se "
                        "cambia por el del túnel al pasar. Se abre con «Compartir» en el visor del proyecto, y "
                        "ahí se elige su contraseña, cuánto dura y si se bloquea el admin.")
        self.tools_box.pack_start(box, False, False, 0)
        self.tools_box.reorder_child(box, 3)
        def fill(rc, out):
            info = next((f for f in parse_lines(out) if f[0] == "I" and len(f) >= 4), None)
            row = ActionRow("cloudflared", "Aún no está: se descarga de GitHub la primera vez que compartes (unos 40 MB)"
                            if not info or info[1] != "1" else "Versión %s, en ~/.lvm-instalador/tunel" % info[2])
            if info and (info[1] != "1" or info[2] != info[3]):
                b = Gtk.Button(label="Instalar" if info[1] != "1" else "Actualizar a la %s" % info[3],
                               valign=Gtk.Align.CENTER, sensitive=not self.busy)
                b.connect("clicked", lambda *_: self.run_task("Instalando cloudflared", ["tunel-instalar"], progress=True, auto_close=True,
                                                              done_text="cloudflared instalado",
                                                              on_done=lambda *a: self.build_tools()))
                row.add_suffix(b)
            lb.insert(row, 0)
            row.show_all()
            return False
        run_quick(["tunel"], fill)
        # (cloudflared y el registro, juntos en una fila; el túnel abierto, debajo a lo ancho)
        reg = os.path.join(LOG_DIR, "tunel", "registro")
        if os.path.isfile(reg):
            row = ActionRow("Registro del túnel", "Quién entra, las contraseñas equivocadas y lo que se bloquea (el último túnel)")
            b = Gtk.Button(label="Ver", valign=Gtk.Align.CENTER)
            b.connect("clicked", lambda *_: self.show_log_tail(reg))
            row.add_suffix(b)
            lb.add(row)
        st = tunnel_state()
        if st:
            row = ActionRow("Túnel abierto", "%s → %s, hasta las %s" % (st["url"], st["target"],
                                                                       time.strftime("%H:%M", time.localtime(st["expires"]))))
            row.add_suffix(Gtk.Button(label="Ver", valign=Gtk.Align.CENTER))
            row.suffix.get_children()[-1].connect("clicked", lambda *_: self.nv_share_dialog())
            b = css(Gtk.Button(label="Cerrar", valign=Gtk.Align.CENTER), "destructive-action")
            b.connect("clicked", lambda *_: self.nv_tunnel_close())
            row.add_suffix(b)
            row.wide = True
            lb.add(row)
        box.show_all()

    def nv_place_buttons(self, acts, btns, fixed=(), conf=None):
        """Los botones del visor (clave: botón) en acts: los que se ven, en su orden y con su estilo. fixed:
        los que van siempre (botón, icono, nombre), ya colocados: con el mismo estilo y el mismo tamaño."""
        conf = conf or buttons_conf()
        specs = dict((k, i) for k, _n, i in VISOR_BUTTONS)
        for key in conf["order"]:
            if key in btns and key not in conf["hidden"]:
                b = btns[key]
                self.nv_restyle(b, conf, ("logo", b.nv_logo) if getattr(b, "nv_logo", None) else specs[key],
                                dict((k, n) for k, n, _i in VISOR_BUTTONS)[key])
                acts.pack_start(b, False, False, 0)
        for b, spec, name in fixed:
            self.nv_restyle(b, conf, spec, name)

    def nv_restyle(self, b, conf, spec, name):
        """Un botón de nv_button (o un menú de nv_menu_button) como dice conf: con su nombre (como está),
        solo el icono o con el icono y el nombre debajo, en un cuadrado de conf["size"] de lado."""
        if conf["style"] == "nombre":
            return
        old = b.get_child()
        texts = [w.get_text() for w in old.get_children() if isinstance(w, Gtk.Label)] \
            if isinstance(old, Gtk.Container) else []
        name = texts[0] if texts else name
        tip = b.get_tooltip_text()
        b.remove(old)
        side = conf["size"]
        if isinstance(b, Gtk.Button):
            b.set_relief(Gtk.ReliefStyle.NORMAL)
        css(b, "nv-proyecto-btn", "nv-boton-cuadrado")
        if conf["style"] == "icono":
            b.add(button_icon(spec, max(16, side // 2)))
            b.set_tooltip_text("%s: %s" % (name, tip) if tip and not tip.startswith(name) else tip or name)
        else:
            side = max(side, BUTTON_SIZE_NAMED)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, valign=Gtk.Align.CENTER)
            box.pack_start(button_icon(spec, max(18, side * 2 // 5)), False, False, 0)
            box.pack_start(label(name, "nv-chico", xalign=0.5, ellipsize=3, max_width_chars=max(6, side // 8)),
                           False, False, 0)
            b.add(box)
        b.set_size_request(side, side)
        b.set_valign(Gtk.Align.CENTER)
        b.show_all()

    def nv_buttons_dialog(self):
        """Personalizar los botones del visor: cuáles se ven, en qué orden y cómo."""
        conf = buttons_conf()
        names = dict((k, (n, i)) for k, n, i in VISOR_BUTTONS)
        dlg = Gtk.Dialog(title="Botones del proyecto", transient_for=self.win, modal=True, use_header_bar=True)
        # (en horizontal: la lista a la izquierda y el estilo, el tamaño y la vista previa a la derecha, para
        # que quepa en la altura de un portátil)
        dlg.set_default_size(900, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        box.pack_start(label("Botones del visor del proyecto", "nv-titulo"), False, False, 0)
        box.pack_start(label("Los que se ven y en qué orden (el del proyecto cargado y el de Docker). Desmontar, ⋮ "
                             "y los propios de Docker (Versiones de PHP, Arrancar o Parar) se ven siempre.",
                             "nv-tenue", wrap=True, max_width_chars=110), False, False, 0)
        cols = Gtk.Box(spacing=26)
        box.pack_start(cols, True, True, 0)
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, valign=Gtk.Align.START), "caja")
        lb.set_size_request(320, -1)
        cols.pack_start(lb, False, False, 0)
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        cols.pack_start(side, True, True, 0)

        def fill():
            for row in lb.get_children():
                lb.remove(row)
            for n, key in enumerate(conf["order"]):
                name, spec = names[key]
                row = ActionRow(name)
                row.prefix.foreach(row.prefix.remove)
                chk = Gtk.CheckButton(active=key not in conf["hidden"], tooltip_text="Verlo en el visor")
                chk.connect("toggled", lambda w, k=key: (conf["hidden"].discard(k) if w.get_active() else conf["hidden"].add(k),
                                                         show_preview()))
                row.add_prefix(chk)
                row.add_prefix(button_icon(spec, 18))
                for icon_name, step, tip in (("go-up-symbolic", -1, "Antes"), ("go-down-symbolic", 1, "Después")):
                    b = nv_button(icon_name, None, tip, lambda *_, i=n, d=step: move(i, d), flat=True)
                    b.set_sensitive(0 <= n + step < len(conf["order"]))
                    row.add_suffix(b)
                lb.add(row)
            lb.show_all()

        def move(i, d):
            o = conf["order"]
            o[i], o[i + d] = o[i + d], o[i]
            fill()
        fill()
        grid = Gtk.Grid(column_spacing=12, row_spacing=10)
        grid.attach(label("Estilo", valign=Gtk.Align.CENTER), 0, 0, 1, 1)
        combo = Gtk.ComboBoxText(hexpand=True)
        for key, text in BUTTON_STYLES:
            combo.append(key, text)
        combo.set_active_id(conf["style"])
        grid.attach(combo, 1, 0, 2, 1)
        grid.attach(label("Tamaño", valign=Gtk.Align.CENTER), 0, 1, 1, 1)
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, BUTTON_SIZE_MIN, BUTTON_SIZE_MAX, 4)
        scale.set_draw_value(False)
        scale.set_hexpand(True)
        scale.set_value(conf["size"])
        grid.attach(scale, 1, 1, 1, 1)
        size_lbl = label("", "nv-mono", "nv-tenue", width_chars=9)
        grid.attach(size_lbl, 2, 1, 1, 1)
        side.pack_start(grid, False, False, 0)
        # Vista previa: los botones que se ven, como quedarán (con Desmontar y ⋮)
        side.pack_start(label("Así quedan", "nv-chico", "nv-tenue"), False, False, 0)
        # (en varias filas si no caben: se ven todos, del tamaño que tendrán)
        preview = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, column_spacing=8, row_spacing=8,
                              max_children_per_line=12, homogeneous=False, margin=4)
        side.pack_start(preview, False, False, 0)
        touched = {"size": False}

        def show_preview(*_):
            conf["style"] = combo.get_active_id() or "nombre"
            conf["size"] = int(scale.get_value())
            square = conf["style"] != "nombre"
            scale.set_sensitive(square)
            side = max(conf["size"], BUTTON_SIZE_NAMED) if conf["style"] == "grande" else conf["size"]
            size_lbl.set_label("%d×%d px" % (side, side) if square else "—")
            preview.foreach(preview.remove)
            btns = {}
            for key, name, spec in VISOR_BUTTONS:
                btns[key] = nv_button(button_icon(spec, 18), name, None, None, "nv-proyecto-btn")
            fixed = [(nv_button("media-eject-symbolic", None, "Desmontar", None, flat=True),
                      ("icono", "media-eject-symbolic"), "Desmontar"),
                     (self.nv_menu_button(None, "view-more-symbolic", []), ("icono", "view-more-symbolic"), "Más")]
            row = Gtk.Box()
            self.nv_place_buttons(row, btns, fixed, conf)
            for b in row.get_children() + [b for b, _spec, _name in fixed]:
                if b.get_parent():
                    b.get_parent().remove(b)
                b.set_can_focus(False)
                # (cada uno de su tamaño, sin estirarse al ancho de la columna)
                b.set_halign(Gtk.Align.START)
                preview.add(b)
            preview.show_all()

        def style_changed(*_):
            if not touched["size"]:
                scale.set_value(BUTTON_SIZES.get(combo.get_active_id(), conf["size"]))
            show_preview()

        def size_changed(*_):
            touched["size"] = True
            show_preview()
        combo.connect("changed", style_changed)
        scale.connect("value-changed", size_changed)
        refill = fill

        def fill():
            refill()
            show_preview()
        show_preview()

        def reset(*_):
            conf.update(order=[k for k, _n, _i in VISOR_BUTTONS], hidden=set())
            touched["size"] = False
            combo.set_active_id("nombre")
            fill()
        rb = css(Gtk.Button(label="Como al principio", halign=Gtk.Align.START,
                            tooltip_text="Volver a los botones de siempre"), "flat")
        rb.connect("clicked", reset)
        side.pack_end(rb, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Guardar", Gtk.ResponseType.ACCEPT), "verde")
        dlg.set_default_response(Gtk.ResponseType.ACCEPT)
        dlg.show_all()
        resp = run_dialog(dlg)
        conf["style"] = combo.get_active_id() or "nombre"
        conf["size"] = int(scale.get_value())
        dlg.destroy()
        if resp != Gtk.ResponseType.ACCEPT:
            return
        try:
            buttons_save(conf)
        except OSError as exc:
            message(self.win, "No se han podido guardar los botones", str(exc), Gtk.MessageType.ERROR)
            return
        self.nv_tunnel_refresh()
        self.toast("Botones del proyecto guardados")

    def nv_share_button(self, url, folder, name, tip_extra=""):
        """«Compartir» del visor de un proyecto: abre un túnel de Cloudflare a esa dirección; si ya lo
        está, «Compartiendo» (en verde) enseña la dirección y la contraseña."""
        st = tunnel_state()
        mine = bool(st) and st["target"] == url.rstrip("/")
        b = nv_button(logo("cloudflare", 18), "Compartiendo" if mine else "Compartir",
                      "Ver dirección y contraseña" if mine else
                      "Compartir con un túnel de Cloudflare%s" % tip_extra,
                      lambda *_: self.nv_share_dialog() if mine else self.nv_share(url, folder, name), "nv-proyecto-btn")
        if mine:
            css(b, "nv-compartiendo")
        return b

    def nv_share(self, url, folder, name, live=True):
        """Abre un túnel a esa web, con lo suyo, que se elige ahora: cuánto dura y si se bloquea el panel de
        administración. Su contraseña, siempre una nueva al azar (se ve al abrirlo, para copiarla)."""
        st = tunnel_state()
        dlg = Gtk.Dialog(title="Compartir", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(560, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        head = Gtk.Box(spacing=10)
        head.pack_start(logo("cloudflare", 30), False, False, 0)
        head.pack_start(label("Compartir %s" % name, "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(head, False, False, 0)
        text = ("Cualquiera que tenga la dirección y la contraseña verá %s tal y como está en este equipo%s mientras "
                "el túnel esté abierto." % (url, " (lo que cambies, al momento)" if live else ""))
        if st:
            text += " Se cierra el que hay abierto (%s)." % st["target"]
        if not os.path.isfile(os.path.join(LOG_DIR, "tunel", "cloudflared")):
            text += " La primera vez se descarga cloudflared, el programa de Cloudflare (unos 40 MB)."
        text += " Lleva una contraseña nueva al azar: se ve al abrirlo, para copiarla y mandarla."
        box.pack_start(label(text, "nv-tenue", wrap=True, max_width_chars=64), False, False, 0)
        grid = Gtk.Grid(column_spacing=14, row_spacing=10, margin_top=4)
        grid.attach(label("Se cierra solo en", valign=Gtk.Align.CENTER), 0, 1, 1, 1)
        hours = Gtk.Box(spacing=6)
        spin = Gtk.SpinButton.new_with_range(1, 12, 1)
        spin.set_value(2)
        hours.pack_start(spin, False, False, 0)
        hours.pack_start(label("horas", "nv-tenue", valign=Gtk.Align.CENTER), False, False, 0)
        grid.attach(hours, 1, 1, 2, 1)
        grid.attach(label("Bloquear el panel de\nadministración", valign=Gtk.Align.CENTER), 0, 2, 1, 1)
        sw = Gtk.Switch(active=True, halign=Gtk.Align.START, valign=Gtk.Align.CENTER)
        grid.attach(sw, 1, 2, 1, 1)
        note = label("", "nv-chico", wrap=True, max_width_chars=64)
        box.pack_start(grid, False, False, 0)
        box.pack_start(note, False, False, 0)
        dlg.get_content_area().add(box)
        dlg.add_button("Cancelar", Gtk.ResponseType.CANCEL)
        css(dlg.add_button("Compartir", Gtk.ResponseType.OK), "nv-azul")
        dlg.set_default_response(Gtk.ResponseType.OK)

        def update(*_):
            note.set_label("wp-admin y el admin de PrestaShop no se abren por el túnel (tus BBDD llevan el administrador "
                           "de pruebas, con una contraseña conocida)" if sw.get_active() else
                           "⚠ El panel de administración se podrá abrir por el túnel: cualquiera con la contraseña puede "
                           "probar a entrar")
        sw.connect("notify::active", update)
        dlg.show_all()
        update()
        resp = run_dialog(dlg)
        h, admin = str(spin.get_value_as_int()), "bloquear" if sw.get_active() else "permitir"
        dlg.destroy()
        if resp != Gtk.ResponseType.OK:
            return
        args = ["tunel-abrir", url, folder, "--horas", h, "--admin", admin]

        def opened(ok_, *_):
            self.nv_tunnel_refresh()
            if ok_ and tunnel_state():
                self.nv_share_dialog()
        if not os.path.isfile(os.path.join(LOG_DIR, "tunel", "cloudflared")):
            self.run_task("Instalando cloudflared", ["tunel-instalar"], progress=True, auto_close=True, done_text="cloudflared instalado",
                          on_done=lambda ok_, *a: ok_ and GLib.idle_add(
                              lambda: self.run_task("Abriendo el túnel de %s" % name, args, auto_close=True,
                                                    done_text="Túnel abierto", on_done=opened) and False))
            return
        self.run_task("Abriendo el túnel de %s" % name, args, auto_close=True, done_text="Túnel abierto",
                      on_done=opened)

    def nv_share_dialog(self):
        """La dirección del túnel abierto y su contraseña, para copiarlas y mandarlas."""
        st = tunnel_state()
        if not st:
            self.toast("El túnel ya está cerrado")
            self.nv_tunnel_refresh()
            return
        password, blocked = st.get("password", ""), st.get("admin") != "permitir"
        until = time.strftime("%H:%M", time.localtime(st["expires"]))
        clip = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        dlg = Gtk.Dialog(title="Túnel de Cloudflare", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(560, -1)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin=22)
        head = Gtk.Box(spacing=10)
        head.pack_start(logo("cloudflare", 30), False, False, 0)
        head.pack_start(label("Compartiendo %s" % st["target"], "nv-titulo", wrap=True), False, False, 0)
        box.pack_start(head, False, False, 0)
        grid = Gtk.Grid(column_spacing=14, row_spacing=8, margin_top=4)
        for n, (title, value) in enumerate((("Dirección", st["url"]), ("Contraseña", password))):
            grid.attach(label(title, "nv-tenue", xalign=0), 0, n, 1, 1)
            grid.attach(label(value, "nv-mono", selectable=True, xalign=0, hexpand=True), 1, n, 1, 1)
            grid.attach(nv_button("edit-copy-symbolic", None, "Copiar", lambda *_, v=value, w=title: (
                clip.set_text(v, -1), self.toast("%s copiada" % w)), flat=True), 2, n, 1, 1)
        box.pack_start(grid, False, False, 0)
        box.pack_start(label("Se cierra solo a las %s. %s Quién entra y lo que se bloquea queda en el registro del "
                             "túnel (Configuración, Túnel de Cloudflare)." % (
                                 until, "El panel de administración va bloqueado." if blocked
                                 else "⚠ El panel de administración no va bloqueado."),
                             "nv-tenue", wrap=True, max_width_chars=64), False, False, 0)
        acts = Gtk.Box(spacing=8)
        msg = ("Te paso la web en pruebas:\n%s\nContraseña: %s\n(Funciona hasta las %s.)" % (st["url"], password, until))
        acts.pack_start(nv_button("mail-send-symbolic", "Copiar para enviar", "Copiar dirección y contraseña",
                                  lambda *_: (clip.set_text(msg, -1), self.toast("Texto para enviar copiado")), "nv-azul"),
                        False, False, 0)
        acts.pack_start(nv_button("web-browser-symbolic", "Abrir", "Abrirla tú en el navegador",
                                  lambda *_: self.open_uri(st["url"])), False, False, 0)
        box.pack_start(acts, False, False, 0)
        dlg.get_content_area().add(box)
        close = dlg.add_button("Cerrar el túnel", Gtk.ResponseType.REJECT)
        css(close, "destructive-action")
        dlg.add_button("Listo", Gtk.ResponseType.CLOSE)
        dlg.set_default_response(Gtk.ResponseType.CLOSE)
        dlg.show_all()
        resp = run_dialog(dlg)
        dlg.destroy()
        if resp == Gtk.ResponseType.REJECT:
            self.nv_tunnel_close()

    def nv_tunnel_close(self):
        def done(rc, out):
            self.toast("Túnel cerrado: la dirección ya no lleva a ningún sitio" if rc == 0 else "No se ha podido cerrar el túnel")
            self.nv_tunnel_refresh()
            return False
        run_quick(["tunel-cerrar"], done)

    def nv_tunnel_refresh(self):
        """Los botones de Compartir y Configuración, con el túnel como esté ahora."""
        for fn in (self.nv_build_projects, self.nv_dk_table, self.nv_node_render, self.build_tools):
            try:
                fn()
            except Exception:  # noqa: BLE001 - una pestaña aún sin datos
                pass

    def nv_docker_dns(self, on):
        """docker-web dns activar|quitar"""
        if on:
            if not confirm(self.win, "¿Activar el DNS de *.docker.test?",
                           "Un DNS mínimo, solo en este equipo (127.0.0.1), que contesta a cualquier <algo>.docker.test. Los "
                           "proyectos del Apache de Docker pasan a .docker.test (su configuración, el dominio de las tiendas en "
                           "su BBDD y el certificado) y sus líneas salen de /etc/hosts. Desde entonces, añadir proyectos o "
                           "versiones de Docker no pide la contraseña por los dominios. web.local, los proyectos de siempre y "
                           "los dominios falseados de las tiendas no cambian. Si no contesta, se quita y todo sigue como "
                           "estaba. Pide la contraseña de administrador.", "Activar"):
                return
        elif not confirm(self.win, "¿Quitar el DNS de *.docker.test?",
                         "Los dominios de Docker siguen siendo .docker.test y vuelven a /etc/hosts. Pide la contraseña de "
                         "administrador.", "Quitar", destructive=True):
            return
        self.run_task("Activando el DNS de *.docker.test" if on else "Quitando el DNS de *.docker.test",
                      ["docker-web", "dns", "activar" if on else "quitar"],
                      done_text="DNS de *.docker.test " + ("puesto" if on else "quitado"),
                      on_done=lambda *a: (run_quick(["gui-docker"], self.on_docker_data), self.build_tools()))

    def on_cross_site(self, sw, _p):
        on = sw.get_active()
        if on == (not os.path.exists(os.path.join(LOG_DIR, "sin-barrera-entre-webs"))):
            return
        self.run_task("Encendiendo la barrera entre webs" if on else "Apagando la barrera entre webs",
                      ["barrera-web", "si" if on else "no"], auto_close=True,
                      done_text="Barrera entre webs %s" % ("encendida" if on else "apagada"),
                      on_done=lambda *_: self.build_tools())

    # ------------------------------------------------------------------ Bases de datos (como Docker)
    def update_db_search(self):
        # (el buscador de siempre no esta en la ventana nueva: la tabla tiene el suyo)
        pass

    def on_db_sizes(self, rc, out):
        sizes = {(f[1], f[2]): (int(f[3]), int(f[4])) for f in parse_lines(out)
                 if f[0] == "Z" and len(f) >= 5 and f[3].isdigit() and f[4].isdigit()}
        if sizes != self.db_sizes:
            self.db_sizes = sizes
            self.nv_db_table()
        self.nv_db_disk()
        return False

    def reload(self, branches=False):
        super().reload(branches)
        run_quick(["gui-bbdd-tamanos"], self.on_db_sizes)

    def build_databases(self):
        d = self.data
        clear(self.db_box)
        if not d:
            self.loading(self.db_box)
            return
        box = self.db_box
        act = next((i for i in self.installs() if i["folder"] == d["active"]), None)
        head = Gtk.Box(spacing=12)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        t.pack_start(label("Bases de datos", "nv-titulo-grande"), False, False, 0)
        t.pack_start(label("Cada versión con su MariaDB y sus BBDD (sin las del sistema)", "nv-chico", "nv-tenue"), False, False, 0)
        head.pack_start(t, True, True, 0)
        new = nv_button("list-add-symbolic", "Nueva BBDD…", "Crear una BBDD vacía", self.on_create_db, "nv-azul")
        new.set_sensitive(bool(act) and not self.busy)
        head.pack_end(new, False, False, 0)
        pma = nv_button(logo("phpmyadmin", 16), "phpMyAdmin", "phpMyAdmin de la versión activa",
                        lambda *_: self.open_uri("http://127.0.0.1/phpmyadmin/"))
        pma.set_sensitive(bool(act) and d["running"])
        head.pack_end(pma, False, False, 0)
        box.pack_start(head, False, False, 0)
        # Tarjetas: cuantas hay, en la activa y la ultima que ha cambiado
        all_dbs = [(f, db) for f, dbs in d["dbs"].items() for db in dbs
                   if next((i for i in self.installs() if i["folder"] == f and i["owner"] == f), None)]
        latest = max(((d["dbdate"].get(k, (0, ""))[0], k) for k in all_dbs), default=(0, None))
        stats = Gtk.Box(spacing=12, homogeneous=True)
        cards = [("BBDD", str(len(all_dbs)), plural(len({f for f, _ in all_dbs}), "versión", "versiones"), None),
                 ("En la versión activa", str(len(d["dbs"].get(d["active"], []))) if act else "—",
                  ("lampp-%s · MariaDB %s" % (act["folder"], act["mariadb"])) if act else "ninguna activa", None),
                 ("La última que ha cambiado", latest[1][1] if latest[1] else "—",
                  ("lampp-%s · %s" % (latest[1][0], fmt_age(max(0, int(time.time()) - latest[0])))) if latest[1] else "", None)]
        for title, value, sub, _extra in cards:
            c = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4), "nv-stat")
            top = Gtk.Box(spacing=6)
            top.pack_start(label(title, "nv-chico", "nv-tenue", ellipsize=3), True, True, 0)
            c.pack_start(top, False, False, 0)
            c.pack_start(label(value, "nv-cifra", ellipsize=3), False, False, 0)
            c.pack_start(label(sub, "nv-chico", "nv-tenue", ellipsize=3), False, False, 0)
            stats.pack_start(c, True, True, 0)
        # Lo que ocupan las BBDD de todas las versiones y lo que queda libre en el disco de /opt
        c = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4), "nv-stat")
        c.pack_start(label("Ocupan las BBDD", "nv-chico", "nv-tenue", ellipsize=3), False, False, 0)
        self.db_disk_card = (label("—", "nv-cifra", ellipsize=3), css(Gtk.ProgressBar(margin_top=2), "nv-barra"),
                             label("", "nv-chico", "nv-tenue", ellipsize=3), c)
        for w in self.db_disk_card[:3]:
            c.pack_start(w, False, False, 0)
        stats.pack_start(c, True, True, 0)
        self.nv_db_disk()
        box.pack_start(stats, False, False, 0)
        # Subir o actualizar una BBDD: antes de la tabla, en un visor hundido
        box.pack_start(self.nv_db_import(), False, False, 0)
        tools = Gtk.Box(spacing=10)
        only = Gtk.Switch(active=self.db_only_active, valign=Gtk.Align.CENTER)
        only.connect("notify::active", lambda w, _p: (setattr(self, "db_only_active", w.get_active()), self.nv_db_table()))
        tools.pack_end(only, False, False, 0)
        tools.pack_end(label("Solo la versión activa", "nv-chico", "nv-tenue", valign=Gtk.Align.CENTER), False, False, 0)
        search = Gtk.SearchEntry(placeholder_text="Buscar una BBDD o su proyecto", width_chars=30,
                                 valign=Gtk.Align.CENTER, text=self.db_query)
        search.connect("search-changed", lambda e: (setattr(self, "db_query", e.get_text().strip().lower()), self.nv_db_table()))
        tools.pack_start(search, False, False, 0)
        box.pack_start(tools, False, False, 0)
        self.db_table = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.pack_start(self.db_table, False, False, 0)
        self.nv_db_table()
        box.show_all()
        self.update_import_button()

    def nv_db_import(self):
        """Subir o actualizar una BBDD, compacto: el fichero, la BBDD de destino, el proyecto y Cargar en
        columnas, dentro de un visor hundido. Lo que hace es lo de siempre (on_pick_sql, on_import...)."""
        d = self.data
        act = next((i for i in d["installs"] if i["folder"] == d["active"]), None)
        if act and self.imp["folder"] != act["folder"]:
            # Otra version activa: sus bases son otras
            self.imp.update(db=None, folder=act["folder"])
        box = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10), "nv-hundido")
        head = Gtk.Box(spacing=8)
        head.pack_start(symbol("document-send-symbolic", 16), False, False, 0)
        head.pack_start(label("Subir o actualizar una BBDD", "nv-hundido-titulo"), False, False, 0)
        head.pack_start(info_icon("Carga una copia .sql, .sql.gz o .zip en el MariaDB de la versión activa. Antes se "
                                  "borran todas las tablas de la BBDD de destino (con una copia en ~/lvm-copias), para "
                                  "que no quede nada de lo anterior. Los .zip se descomprimen solos."), False, False, 0)
        if act:
            head.pack_start(label("en lampp-%s · MariaDB %s" % (act["folder"], act["mariadb"]), "nv-chico", "nv-tenue",
                                  valign=Gtk.Align.CENTER), False, False, 0)
        box.pack_start(head, False, False, 0)
        # (sin version activa: lo dice y no hay nada que elegir; update_import_button no se llama)
        self.imp_btn = None
        if not act:
            box.pack_start(label("Activa una versión en Versiones de PHP para cargar BBDD.", "nv-chico", "nv-tenue"),
                           False, False, 0)
            return box

        def column(title, widget, hint=None):
            c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            c.pack_start(label(title.upper(), "nv-chico", "nv-tenue"), False, False, 0)
            c.pack_start(widget, False, False, 0)
            if hint is not None:
                c.pack_start(hint, False, False, 0)
            return c
        cols = Gtk.Box(spacing=16)
        # Fichero
        f = self.imp["file"]
        name = "Ningún fichero elegido"
        if f:
            try:
                name = "%s · %s" % (os.path.basename(f), fmt_size(os.path.getsize(f)))
            except OSError:
                name = "%s · ya no existe" % os.path.basename(f)
        pick = Gtk.Box(spacing=6)
        b = Gtk.Button(label="Elegir…", valign=Gtk.Align.CENTER)
        b.connect("clicked", self.on_pick_sql)
        pick.pack_start(b, False, False, 0)
        fl = label(name, "nv-chico", "nv-mono" if f else "nv-tenue", ellipsize=2, max_width_chars=28,
                   valign=Gtk.Align.CENTER)
        if f:
            fl.set_tooltip_text(f)
        pick.pack_start(fl, True, True, 0)
        # (lo que falta para poder cargar: debajo del fichero, que tiene sitio)
        self.imp_hint = label("", "nv-chico", "nv-tenue", wrap=True, max_width_chars=36)
        self.imp_hint.set_no_show_all(True)
        cols.pack_start(column("Fichero SQL", pick, self.imp_hint), True, True, 0)
        # BBDD de destino (con crear y borrar al lado)
        dest = Gtk.Box(spacing=4)
        combo = narrow(Gtk.ComboBoxText(valign=Gtk.Align.CENTER), 24)
        for db in d["dbs"].get(act["folder"], []):
            combo.append(db, db)
        if self.imp["db"]:
            combo.set_active_id(self.imp["db"])
        if combo.get_active_id() is None:
            self.imp["db"] = None
            combo.append("@ninguna", "Elige una BBDD")
            combo.set_active_id("@ninguna")
        combo.connect("changed", self.on_pick_db)
        dest.pack_start(combo, True, True, 0)
        b = nv_button("list-add-symbolic", None, "Crear una BBDD nueva", self.on_create_db, flat=True)
        dest.pack_start(b, False, False, 0)
        self.imp_drop_btn = nv_button("user-trash-symbolic", None, "Borrar la BBDD elegida",
                                      lambda *_: self.on_drop_db(self.imp["db"]), flat=True)
        self.imp_drop_btn.set_sensitive(bool(self.imp["db"]))
        dest.pack_start(self.imp_drop_btn, False, False, 0)
        cols.pack_start(column("BBDD de destino", dest), True, True, 0)
        # Proyecto de la base: queda como su base y, si es un WordPress, su wp-config.php la usa
        folders = project_folders()
        if self.imp.get("project") not in folders:
            self.imp["project"] = None
        # La primera vez con esta base se propone su proyecto; luego se respeta lo elegido
        if self.imp["db"] and self.imp.get("project_for") != self.imp["db"]:
            self.imp["project"] = guess_project(self.imp["db"], d["active"]) or self.imp["project"]
            self.imp["project_for"] = self.imp["db"]
        combo = narrow(Gtk.ComboBoxText(valign=Gtk.Align.CENTER), 24)
        combo.append("@ninguno", "Ninguno")
        for name in folders:
            combo.append(name, name)
        combo.set_active_id(self.imp["project"] or "@ninguno")
        combo.connect("changed", self.on_pick_project)
        self.imp_proj_combo = combo
        # (la explicacion de debajo: la cambia on_pick_project)
        self.imp_proj_hint = label(self.import_project_hint(), "nv-chico", "nv-tenue", wrap=True, max_width_chars=30)
        cols.pack_start(column("Proyecto (opcional)", combo, self.imp_proj_hint), True, True, 0)
        # Cargar
        go = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4, valign=Gtk.Align.END)
        self.imp_btn = css(Gtk.Button(label="Cargar"), "verde", "pildora")
        self.imp_btn.connect("clicked", self.on_import)
        go.pack_start(self.imp_btn, False, False, 0)
        cols.pack_end(go, False, False, 0)
        box.pack_start(cols, False, False, 0)
        return box

    def update_import_button(self):
        # (sin version activa no hay boton Cargar)
        if getattr(self, "imp_btn", None) is not None:
            super().update_import_button()

    def nv_db_disk(self):
        """Tarjeta «Ocupan las BBDD»: la suma de las medidas de todas las versiones (cada una se mide
        cuando está activa y en marcha) y la barra del disco donde están (/opt), con lo que queda libre."""
        card, d = getattr(self, "db_disk_card", None), self.data
        if card is None or not d:
            return
        val, bar, sub, box = card
        all_dbs = [(f, db) for f, dbs in d["dbs"].items() for db in dbs
                   if next((i for i in self.installs() if i["folder"] == f and i["owner"] == f), None)]
        got = [self.db_sizes[k][0] for k in all_dbs if k in self.db_sizes]
        val.set_label(fmt_size(sum(got)) if got else "—")
        missing = len(all_dbs) - len(got)
        box.set_tooltip_text(("%s sin medir"
                              % plural(missing, "BBDD", "BBDD")) if missing else
                             "Tamaño de las BBDD de todas las versiones")
        try:
            st = os.statvfs("/opt")
            total, free = st.f_blocks * st.f_frsize, st.f_bavail * st.f_frsize
        except OSError:
            total = free = 0
        bar.set_fraction(1 - free / total if total else 0)
        sub.set_label("Disco: %s libres de %s" % (fmt_size(free), fmt_size(total)) if total else "")
        tip = "Quedan %s libres en el disco de /opt (ocupado el %d %%)" % (fmt_size(free), round(100 - 100 * free / total)) \
            if total else None
        bar.set_tooltip_text(tip)
        sub.set_tooltip_text(tip)

    def nv_db_project(self, db, folder):
        """Proyecto de una BBDD en una version: el vinculado o el que la usa en su configuracion."""
        f = self.link_of(db, folder)
        if f:
            return f
        if f == "":
            return ""
        users = [x["name"] for x in (self.projects or {}).get("list", []) if x["db"] == db]
        return users[0] if len(users) == 1 else ""

    def nv_db_toggle(self, key):
        """Pliega o despliega una versión en Bases de datos: solo una desplegada a la vez (al abrir
        otra, se cierra la anterior)."""
        if key in self.expanded:
            self.expanded.discard(key)
        else:
            self.expanded.difference_update({k for k in self.expanded if k.startswith("@db")})
            self.expanded.add(key)
        self.nv_db_table()

    def nv_db_table(self):
        if getattr(self, "db_table", None) is None:
            return
        clear(self.db_table)
        d = self.data
        q = self.db_query
        used = self.loaded_project_db()
        loaded = self.loaded_project_entry()
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "nv-grupo")
        widths = [270, 210, 110, 230, 190]
        groups = [Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL) for _ in widths]

        def row(cells, head_row=False, indent=0, on_click=None):
            r = Gtk.ListBoxRow(activatable=on_click is not None)
            b = css(Gtk.Box(spacing=12), "nv-fila", *(["nv-cab"] if head_row else []))
            for n, c in enumerate(cells):
                w = c if isinstance(c, Gtk.Widget) else label(c.upper() if head_row else c)
                if n == 0 and indent:
                    cell = Gtk.Box()
                    sp = Gtk.Box()
                    sp.set_size_request(indent, -1)
                    cell.pack_start(sp, False, False, 0)
                    cell.pack_start(w, True, True, 0)
                    w = cell
                w.set_size_request(widths[n], -1)
                groups[n].add_widget(w)
                b.pack_start(w, n == len(cells) - 1, True, 0)
            r.add(b)
            r.on_click = on_click
            lb.add(r)

        def actions(items):
            a = Gtk.Box(spacing=6, halign=Gtk.Align.START)
            for w in items:
                if w is not None:
                    a.pack_start(w, False, False, 0)
            return a
        lb.connect("row-activated", lambda _l, r: r.on_click and r.on_click())
        row(["Nombre", "Proyecto", "Tamaño", "Cambiada", "Acciones"], True)

        def size_label(owner, db):
            got = self.db_sizes.get((owner, db))
            if not got:
                lbl = label("—", "nv-chico", "nv-tenue")
                lbl.set_tooltip_text("Se mide con su versión en marcha")
                return lbl
            lbl = label(fmt_size(got[0]), "nv-chico", "nv-mono")
            lbl.set_tooltip_text("Datos e índices, medido el %s"
                                 % time.strftime("%d/%m/%Y a las %H:%M", time.localtime(got[1])))
            return lbl
        shown = 0
        for inst in sorted(self.installs(), key=lambda i: ver_tuple(i["php"]), reverse=True):
            folder = inst["folder"]
            active = folder == d["active"]
            if self.db_only_active and not active:
                continue
            dbs = d["dbs"].get(folder, []) if inst["owner"] == folder else []
            rows = []
            for db in dbs:
                proj = self.nv_db_project(db, folder)
                if q and q not in db.lower() and q not in proj.lower():
                    continue
                rows.append((db, proj))
            if q and not rows:
                continue
            shown += 1
            key = "@db" + folder
            opened = key in self.expanded if not q else True
            name = Gtk.Box(spacing=8)
            name.pack_start(icon("pan-down-symbolic" if opened else "pan-end-symbolic"), False, False, 0)
            ic = css(Gtk.Box(), "nv-dk-icono")
            ic.pack_start(logo("mariadb", 14), False, False, 0)
            name.pack_start(ic, False, False, 0)
            name.pack_start(label("lampp-%s" % folder, "nv-dk-proyecto", "nv-mono"), False, False, 0)
            if active:
                name.pack_start(label("Activa", "nv-etiqueta", "nv-etiqueta-azul", valign=Gtk.Align.CENTER), False, False, 0)
            sub = "PHP %s · MariaDB %s" % (inst["php"], inst["mariadb"])
            count = plural(len(dbs), "BBDD", "BBDD") if inst["owner"] == folder else "usa las de lampp-%s" % inst["owner"]
            grp_acts = []
            if active:
                b = nv_button("drive-multidisk-symbolic", None, "Abrir phpMyAdmin", lambda *_: self.open_uri("http://127.0.0.1/phpmyadmin/"), flat=True)
                b.set_sensitive(d["running"])
                grp_acts.append(b)
                b = nv_button("list-add-symbolic", None, "Crear una BBDD vacía aquí", self.on_create_db, flat=True)
                b.set_sensitive(not self.busy)
                grp_acts.append(b)
            total = sum(self.db_sizes.get((inst["owner"], db), (0, 0))[0] for db in d["dbs"].get(inst["owner"], []))
            row([name, label(sub, "nv-chico", "nv-tenue"),
                 label(fmt_size(total) if total else "—", "nv-chico", "nv-mono" if total else "nv-tenue"),
                 label(count, "nv-chico", "nv-tenue"), actions(grp_acts)],
                on_click=lambda key=key: self.nv_db_toggle(key))
            if not opened:
                continue
            for db, proj in rows:
                when, kind = d["dbdate"].get((folder, db), (0, ""))
                n = Gtk.Box(spacing=8)
                is_used = active and loaded is not None and db == used
                dt = label("●", "nv-verde" if is_used else "nv-gris")
                dt.set_tooltip_text("La usa el proyecto cargado (%s)" % loaded["name"] if is_used else None)
                if not is_used:
                    dt.set_opacity(0.25)
                n.pack_start(dt, False, False, 0)
                if is_ps_db(db):
                    n.pack_start(logo("prestashop", 14), False, False, 0)
                elif db.lower().startswith("wp_"):
                    n.pack_start(logo("wordpress", 14), False, False, 0)
                n.pack_start(label(db, "nv-mono", "nv-chico", ellipsize=3, tooltip_text=db), False, False, 0)
                pl = label(proj or "—", "nv-chico", "nv-tenue" if not proj else "", ellipsize=3)
                # (la fecha del cambio: la de su carga con el gestor o la del ultimo cambio de sus tablas)
                ch = label(("%s %s" % (time.strftime("%d/%m/%Y %H:%M", time.localtime(when)),
                                       "· importada" if kind == "i" else ""))
                           if when else "—", "nv-chico", "nv-mono" if when else "nv-tenue")
                if when:
                    ch.set_tooltip_text(db_date_text(when, kind))
                acts = []
                if is_ps_db(db):
                    acts.append(self.cache_button(db))
                cp = self.copy_button(db, inst)
                if cp:
                    acts.append(cp)
                acts.append(self.download_button(db, folder))
                ld = nv_button("folder-open-symbolic", None, "Cargar su proyecto (en lampp-%s)" % folder,
                               lambda *_, db=db, inst=inst: self.on_load_project(db, inst), flat=True)
                ld.set_sensitive(not self.busy)
                acts.append(ld)
                if active:
                    rm = nv_button("user-trash-symbolic", None, "Borrar la BBDD %s" % db, lambda *_, db=db: self.on_drop_db(db), flat=True)
                    rm.set_sensitive(not self.busy)
                    acts.append(rm)
                row([n, pl, size_label(inst["owner"], db), ch, actions(acts)], indent=26)
        if not shown:
            r = Gtk.ListBoxRow(activatable=False)
            r.add(label("Ninguna BBDD con «%s»" % q if q else "No hay versiones con BBDD", "nv-tenue", margin=14))
            lb.add(r)
        self.db_table.pack_start(lb, False, False, 0)
        self.db_table.show_all()

    # ------------------------------------------------------------------ Docker (como Docker Desktop)
    def build_docker(self):
        d = self.docker
        if d is None or not d["ready"]:
            # (sin Docker en marcha: lo de siempre, con el boton de instalarlo o prepararlo)
            return super().build_docker()
        clear(self.docker_box)
        box = self.docker_box
        head = Gtk.Box(spacing=12)
        t = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        tl = Gtk.Box(spacing=10)
        tl.pack_start(logo("docker", 28), False, False, 0)
        tl.pack_start(label("Contenedores Docker", "nv-titulo-grande"), False, False, 0)
        t.pack_start(tl, False, False, 0)
        t.pack_start(label("Docker %s · sin root, con tu usuario" % d["version"], "nv-chico", "nv-tenue"), False, False, 0)
        head.pack_start(t, True, True, 0)
        new = nv_button("list-add-symbolic", "Proyecto en Docker…", None, lambda *_: self.nv_docker_new(), "nv-azul")
        head.pack_end(new, False, False, 0)
        # Parar todo lo de Nexum de una vez (proyectos, MariaDB comunes y el Apache de Docker)
        running = [c for c in d.get("containers", []) if c["state"] == "running" and docker_own(c["name"])]
        stop = nv_button("media-playback-stop-symbolic", "Parar todos",
                         "Parar %d contenedores de Nexum" % len(running) if running else
                         "No hay ningún contenedor de Nexum en marcha",
                         lambda *_: self.run_task("Parando todos los contenedores de Nexum", ["docker-parar-todo"],
                                                  auto_close=True, done_text="Contenedores de Nexum parados",
                                                  on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)),
                         "nv-proyecto-btn", "nv-stop")
        stop.set_sensitive(bool(running) and not self.busy)
        head.pack_end(stop, False, False, 0)
        box.pack_start(head, False, False, 0)
        for text, sub, btn in ([("Hay otro Docker en marcha: el de Ubuntu, como administrador",
                                 "Este programa usa el suyo, con tu usuario: el de Ubuntu no hace falta y quien lo use "
                                 "puede hacerse con el equipo. Apágalo salvo que lo uses fuera de este programa.",
                                 ("Apagarlo", lambda *_: self.run_task("Apagando el Docker del sistema", ["docker-instalar"],
                                                                         done_text="Docker del sistema apagado", auto_close=True,
                                                                         on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))))]
                               if d.get("rootful") else []) + \
                              ([("La versión LAMPP activa está parada", "Los proyectos en Docker de antes se abren por su "
                                 "Apache (los del Apache de Docker, no).", ("Arrancarla", lambda *_: self.nv_power()))]
                               if not d["lampp"] and any(not p.get("web") for p in d["projects"]) else []):
            r = css(Gtk.Box(spacing=10), "nv-stat")
            r.pack_start(icon("dialog-warning-symbolic"), False, False, 0)
            tt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            tt.pack_start(label(text), False, False, 0)
            tt.pack_start(label(sub, "nv-chico", "nv-tenue"), False, False, 0)
            r.pack_start(tt, True, True, 0)
            r.pack_end(nv_button(None, btn[0], None, btn[1]), False, False, 0)
            box.pack_start(r, False, False, 0)
        self.nv_docker_web_strip(box)
        # Tarjetas: CPU, memoria (docker stats, llegan aparte) y en marcha
        cons = d.get("containers", [])
        up = sum(1 for c in cons if c["state"] == "running")
        stats = Gtk.Box(spacing=12, homogeneous=True)
        self.dk_cards = {}
        for key, title in [("cpu", "Uso de CPU de los contenedores"), ("mem", "Memoria de los contenedores"),
                           ("up", "En marcha")]:
            c = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6), "nv-stat")
            c.pack_start(label(title, "nv-chico", "nv-tenue"), False, False, 0)
            val = label("…", "nv-cifra")
            bar = css(Gtk.ProgressBar(), "nv-barra")
            sub = label("", "nv-chico", "nv-tenue")
            for w in (val, bar, sub):
                c.pack_start(w, False, False, 0)
            stats.pack_start(c, True, True, 0)
            self.dk_cards[key] = (val, bar, sub)
        val, bar, sub = self.dk_cards["up"]
        val.set_label("%d de %d" % (up, len(cons)))
        bar.set_fraction(up / len(cons) if cons else 0)
        sub.set_label(plural(len(d["projects"]), "proyecto", "proyectos"))
        box.pack_start(stats, False, False, 0)
        self.nv_show_stats()
        # Pestañas, buscador y «solo en marcha»
        tools = Gtk.Box(spacing=10)
        seg = css(Gtk.Box(), "nv-segmentado")
        first = None
        for key, text in [("cont", "Contenedores"), ("img", "Imágenes"), ("vol", "Volúmenes")]:
            rb = Gtk.RadioButton.new_with_label_from_widget(first, text)
            rb.set_mode(False)
            first = first or rb
            rb.set_active(self.dk_view == key)
            rb.connect("toggled", lambda r, k=key: r.get_active() and (setattr(self, "dk_view", k), self.nv_dk_table()))
            seg.pack_start(rb, False, False, 0)
        tools.pack_start(seg, False, False, 0)
        only = Gtk.Switch(active=self.dk_only_up, valign=Gtk.Align.CENTER)
        only.connect("notify::active", lambda w, _p: (setattr(self, "dk_only_up", w.get_active()), self.nv_dk_table()))
        tools.pack_end(only, False, False, 0)
        tools.pack_end(label("Solo en marcha", "nv-chico", "nv-tenue", valign=Gtk.Align.CENTER), False, False, 0)
        search = Gtk.SearchEntry(placeholder_text="Buscar", width_chars=18, valign=Gtk.Align.CENTER, text=self.dk_query)
        search.connect("search-changed", lambda e: (setattr(self, "dk_query", e.get_text().strip().lower()), self.nv_dk_table()))
        tools.pack_end(search, False, False, 0)
        box.pack_start(tools, False, False, 0)
        self.dk_table = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.pack_start(self.dk_table, False, False, 0)
        self.nv_dk_table()
        box.pack_start(label("Para llevar un proyecto a Docker: «Proyecto en Docker…» o, en Proyectos, «Añadir entorno».",
                             "nv-chico", "nv-tenue"), False, False, 0)
        for w in self.nv_walk(box):
            if isinstance(w, Gtk.Button) and not w.get_style_context().has_class("nv-azul"):
                css(w, "nv-clasico")
        box.show_all()

    def nv_container_delete(self, c):
        """Eliminar un contenedor suelto de un proyecto en Docker."""
        if not confirm(self.win, "¿Eliminar el contenedor %s?" % c["name"],
                       "Se vuelve a crear al arrancar el proyecto; los datos de la BBDD siguen en su volumen. "
                       "Para quitar el proyecto entero, usa la papelera de su fila.",
                       "Eliminar el contenedor", destructive=True):
            return
        self.run_task("Eliminando %s" % c["name"], ["docker-contenedor", "borrar", c["name"]],
                      done_text="%s eliminado" % c["name"], auto_close=True,
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def nv_docker_new(self):
        """El formulario de siempre para crear un proyecto en Docker, en un dialogo."""
        dlg = Gtk.Dialog(title="Proyecto en Docker", transient_for=self.win, modal=True, use_header_bar=True)
        dlg.set_default_size(620, -1)
        form = self.build_docker_new()
        form.set_margin_start(18)
        form.set_margin_end(18)
        form.set_margin_bottom(18)
        dlg.get_content_area().add(form)
        # (al pulsar «Crear en Docker» se cierra: la tarea va en su ventana)
        for w in self.nv_walk(form):
            if isinstance(w, Gtk.Button) and w.get_label() == "Crear en Docker":
                w.connect("clicked", lambda *_: dlg.destroy())
        dlg.show_all()

    def nv_walk(self, w):
        yield w
        if isinstance(w, Gtk.Container):
            for c in w.get_children():
                yield from self.nv_walk(c)

    def docker_folder_changed(self):
        f = self.docker_form
        f["source"] = None
        if not f.get("domain_set"):
            f["domain"] = docker_slug(f["folder"] or "") + ".docker.local" if f.get("folder") else ""

    def on_docker_stats(self, rc, out):
        cores, total, cpu, mem = 1, 0, {}, {}
        units = {"B": 1, "KiB": 1024, "MiB": 1024 ** 2, "GiB": 1024 ** 3, "TiB": 1024 ** 4,
                 "kB": 1000, "KB": 1000, "MB": 1000 ** 2, "GB": 1000 ** 3}
        for f in parse_lines(out):
            if f[0] == "T" and len(f) >= 3 and f[1].isdigit() and f[2].isdigit():
                cores, total = int(f[1]), int(f[2])
            elif f[0] == "K" and len(f) >= 4:
                try:
                    cpu[f[1]] = float(f[2].rstrip("%"))
                    m = re.match(r"([\d.]+)\s*([A-Za-z]+)", f[3].split("/")[0].strip())
                    mem[f[1]] = float(m.group(1)) * units.get(m.group(2), 1) if m else 0
                except ValueError:
                    pass
        self.dk_stats = {"cores": cores, "total": total, "cpu": cpu, "mem": mem}
        self.nv_show_stats()
        if getattr(self, "dk_table", None) is not None and self.dk_view == "cont":
            self.nv_dk_table()
        return False

    def nv_show_stats(self):
        s = self.dk_stats
        if not getattr(self, "dk_cards", None) or s is None:
            return
        val, bar, sub = self.dk_cards["cpu"]
        total_cpu = sum(s["cpu"].values())
        val.set_label(("%.1f %%" % total_cpu).replace(".", ","))
        bar.set_fraction(min(1, total_cpu / (100 * s["cores"])))
        sub.set_label("de %d %% (%s)" % (100 * s["cores"], plural(s["cores"], "núcleo", "núcleos")))
        val, bar, sub = self.dk_cards["mem"]
        used = sum(s["mem"].values())
        val.set_label(fmt_size(int(used)))
        bar.set_fraction(min(1, used / s["total"]) if s["total"] else 0)
        sub.set_label("de %s" % fmt_size(s["total"]) if s["total"] else "")

    def nv_dk_toggle(self, proj):
        """Despliega un proyecto de Docker (y pliega el que estuviera abierto) o lo pliega."""
        self.dk_open = set() if proj in self.dk_open else {proj}
        self.nv_dk_table()

    def nv_dk_table(self):
        if getattr(self, "dk_table", None) is None:
            return
        clear(self.dk_table)
        d = self.docker
        q = self.dk_query
        if self.dk_view == "img":
            rows = [i for i in d.get("images", []) if q in ("%s:%s %s" % (i["repo"], i["tag"], i["id"])).lower()]
            used = {c["image"] for c in d.get("containers", [])}
            self.dk_table.pack_start(self.nv_simple_table(
                ["Imagen", "Etiqueta", "ID", "Tamaño", "Creada", "Acciones"], [300, 110, 120, 90, 120, 90],
                [[label(i["repo"], "nv-mono", "nv-chico", ellipsize=3, tooltip_text=i["repo"]),
                  label(i["tag"], "nv-mono", "nv-chico", "nv-enlace"),
                  label(i["id"], "nv-mono", "nv-chico", "nv-tenue", selectable=True),
                  label(i["size"], "nv-mono", "nv-tenue"),
                  label(docker_status_text("Up " + i["created"].replace(" ago", "")).replace("en marcha · ", "hace "), "nv-tenue"),
                  self.nv_image_actions(i, "%s:%s" % (i["repo"], i["tag"]) in used or i["id"] in used)] for i in rows],
                "No hay imágenes"), False, False, 0)
        elif self.dk_view == "vol":
            rows = [v for v in d.get("volumes", []) if q in v["name"].lower()]
            # (el de la BBDD de un proyecto lo usa su contenedor db, aunque esté parado)
            used = {"%s_db" % c["project"] for c in d.get("containers", []) if c["project"]}
            self.dk_table.pack_start(self.nv_simple_table(["Volumen", "Driver", "De", "Acciones"], [420, 120, 200, 90],
                                     [[label(v["name"], "nv-mono", "nv-chico"), label(v["driver"], "nv-tenue"),
                                       label(re.sub(r"^nexum-(.+)_db$", r"\1 (BBDD)", v["name"]) if v["name"].startswith("nexum-") else "—",
                                             "nv-tenue"),
                                       self.nv_volume_actions(v, v["name"] in used)] for v in rows], "No hay volúmenes"), False, False, 0)
        else:
            self.dk_table.pack_start(self.nv_containers_table(), False, False, 0)
        for w in self.nv_walk(self.dk_table):
            if isinstance(w, Gtk.Button) and not w.get_style_context().has_class("nv-proyecto-btn"):
                css(w, "nv-clasico")
        self.dk_table.show_all()

    def nv_image_actions(self, i, in_use):
        """Volver a descargar una imagen de Docker Hub y borrarla (si no la usa ningún contenedor)."""
        a = Gtk.Box(spacing=6, halign=Gtk.Align.START)
        ref = "%s:%s" % (i["repo"], i["tag"])
        pullable = i["tag"] != "<none>" and not i["repo"].startswith("nexum-")
        pull = nv_button("folder-download-symbolic", None, "Volver a descargar de Docker Hub"
                         if pullable else "Se rehace con «Actualizar imagen»"
                         if i["repo"].startswith("nexum-") else "Sin etiqueta: no se puede volver a descargar",
                         lambda *_: self.run_task("Descargando %s" % ref, ["docker-imagenes", "descargar", ref],
                                                  done_text="%s descargada" % ref,
                                                  on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)))
        pull.set_sensitive(pullable and not self.busy)
        a.pack_start(pull, False, False, 0)
        rm = nv_button("user-trash-symbolic", None, "La usa un contenedor: bórralo antes" if in_use else "Borrar la imagen",
                       lambda *_: self.nv_image_delete(i, ref))
        rm.set_sensitive(not in_use and not self.busy)
        a.pack_start(rm, False, False, 0)
        return a

    def nv_image_delete(self, i, ref):
        tagged = i["tag"] != "<none>"
        if not confirm(self.win, "¿Borrar la imagen %s?" % (ref if tagged else i["id"]),
                       "Ocupa %s. Si hace falta, se vuelve a descargar o a preparar." % i["size"],
                       "Borrar la imagen", destructive=True):
            return
        self.run_task("Borrando %s" % (ref if tagged else i["id"]), ["docker-imagenes", "borrar", ref if tagged else i["id"]],
                      done_text="Imagen borrada", auto_close=True,
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def nv_volume_actions(self, v, in_use):
        a = Gtk.Box(spacing=6, halign=Gtk.Align.START)
        rm = nv_button("user-trash-symbolic", None, "Lo usa un contenedor: bórralo antes"
                       if in_use else "Borrar el volumen", lambda *_: self.nv_volume_delete(v))
        rm.set_sensitive(not in_use and not self.busy)
        a.pack_start(rm, False, False, 0)
        return a

    def nv_volume_delete(self, v):
        if not confirm(self.win, "¿Borrar el volumen %s?" % v["name"],
                       "Se pierden sus datos. No se puede deshacer.", "Borrar el volumen", destructive=True):
            return
        self.run_task("Borrando %s" % v["name"], ["docker-volumen-borrar", v["name"]],
                      done_text="Volumen borrado", auto_close=True,
                      on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data))

    def nv_simple_table(self, headers, widths, rows, empty):
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "nv-grupo")
        groups = [Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL) for _ in widths]
        for n_row, cells in enumerate([[label(h.upper()) for h in headers]] + rows):
            r = Gtk.ListBoxRow(activatable=False)
            b = css(Gtk.Box(spacing=14), "nv-fila", *(["nv-cab"] if n_row == 0 else []))
            for n, w in enumerate(cells):
                w.set_size_request(widths[n], -1)
                groups[n].add_widget(w)
                b.pack_start(w, n == len(cells) - 1, True, 0)
            r.add(b)
            lb.add(r)
        if not rows:
            r = Gtk.ListBoxRow(activatable=False)
            r.add(label(empty, "nv-tenue", margin=14))
            lb.add(r)
        return lb

    def nv_docker_visor(self, p, items):
        """Visor de un proyecto en Docker, como el del proyecto cargado: su nombre y su logotipo, sus
        versiones, su dominio, si está en marcha y sus accesos directos (la web, su panel con el
        administrador de pruebas, su phpMyAdmin, VS Code, el registro de PHP y arrancar o parar)."""
        folder = os.path.join(HTDOCS, p["folder"])
        kind = project_kind(p["folder"])
        akind, admin = project_admin(folder)
        up = bool(items) and all(c["state"] == "running" for c in items)
        some = any(c["state"] == "running" for c in items)
        web = p.get("web")
        if web:
            php_c = next((c["name"] for c in items if c["name"] == "nexum-%s-php%s" % (p["slug"], p["php"].replace(".", ""))), None)
        else:
            php_c = next((c["name"] for c in items if re.fullmatch(r"nexum-[a-z0-9-]+-php-\d+", c["name"])), None)
        card = css(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12), "nv-tarjeta", "nv-dk-visor")
        top = Gtk.Box(spacing=14)
        # (el logotipo solo, sin recuadro, como arriba en Proyectos)
        img = kind_icon(kind, 36)
        img.set_valign(Gtk.Align.CENTER)
        top.pack_start(img, False, False, 0)
        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3, valign=Gtk.Align.CENTER)
        tl = Gtk.Box(spacing=10)
        tl.pack_start(label(p["folder"], "nv-titulo", ellipsize=3, max_width_chars=48, tooltip_text=p["folder"]),
                      False, False, 0)
        if kind:
            tl.pack_start(label(KIND_TEXT[kind], "nv-etiqueta", valign=Gtk.Align.CENTER), False, False, 0)
        info.pack_start(tl, False, False, 0)
        info.pack_start(label(("PHP %s · %s · %s" % (" · ".join(p["versions"]),
                                                    ("BBDD de lampp-%s en vivo (la de web.local)" % p["lampp"]) if p.get("lampp")
                                                    else "MariaDB %s común" % p["maria"], self.dk_url(p["domain"])))
                              if web else "PHP %s · MariaDB %s · https://%s" % (p["php"], p["maria"], p["domain"]),
                              "nv-mono", "nv-chico", "nv-tenue", selectable=True, ellipsize=3), False, False, 0)
        top.pack_start(info, True, True, 0)
        st = Gtk.Box(spacing=6, valign=Gtk.Align.CENTER)
        st.pack_start(label("●", "nv-verde", "nv-latido") if up else nv_dot(False), False, False, 0)
        st.pack_start(label("En marcha" if up else "A medias" if some else "Parado", "nv-chico",
                            *([] if up else ["nv-tenue"])), False, False, 0)
        top.pack_end(st, False, False, 0)
        card.pack_start(top, False, False, 0)
        card.pack_start(css(Gtk.Box(), "nv-pie"), False, False, 0)
        acts = Gtk.Box(spacing=8)
        stopped = "Está parado: arráncalo antes"
        if web and p.get("kind") != "ps" and len(p["versions"]) > 1:
            # (varias versiones a la vez: cada una con su dominio)
            wb = self.nv_menu_button("Abrir web", "web-browser-symbolic",
                                     [("PHP %s  ·  %s" % (v, docker_web_domain(p, v)),
                                       lambda v=v: self.open_uri(self.dk_url(docker_web_domain(p, v)) + "/")) for v in p["versions"]],
                                     "Abrir una de sus versiones de PHP" if up else stopped)
        else:
            wb = nv_button(logo("globo", 18), "Abrir web", "Abrir %s/" % self.dk_url(p["domain"]) if up else stopped,
                           lambda *_: self.open_uri(self.dk_url(p["domain"]) + "/"), "nv-proyecto-btn")
        wb.set_sensitive(up)
        btns = {"web": wb}
        st = tunnel_state()
        targets = [(v, self.dk_url(docker_web_domain(p, v))) for v in p["versions"]] \
            if web and p.get("kind") != "ps" and len(p["versions"]) > 1 else [(p["php"], self.dk_url(p["domain"]))]
        if len(targets) > 1 and not (st and st["target"] in [t for _v, t in targets]):
            sb = self.nv_menu_button("Compartir", logo("cloudflare", 18), [("PHP %s  ·  %s" % (v, t), lambda t=t: self.nv_share(t, folder, p["folder"]))
                                                         for v, t in targets],
                                     "Compartir con un túnel de Cloudflare" if up else stopped)
        else:
            mine = next((t for _v, t in targets if st and st["target"] == t), targets[0][1])
            sb = self.nv_share_button(mine, folder, p["folder"])
        sb.set_sensitive(up)
        btns["compartir"] = sb
        adm = nv_button(logo("prestashop" if akind == "ps" else "wordpress", 18), "Panel",
                        stopped if not up else "Abrir el panel de administración"
                        if admin else "No tiene panel de administración",
                        lambda *_: self.open_admin_login(akind, admin, self.dk_url(p["domain"]), p["folder"],
                                                         ["docker-usuario-pruebas", p["slug"]]), "nv-proyecto-btn")
        adm.set_sensitive(up and bool(admin))
        adm.nv_logo = "prestashop" if akind == "ps" else "wordpress"
        btns["panel"] = adm
        pma_ok = web or p["pma"].isdigit()
        pma = nv_button(logo("phpmyadmin", 18), "phpMyAdmin",
                        stopped if not up else "Abrir phpMyAdmin (copia la contraseña)" if pma_ok else "Sin puerto de phpMyAdmin",
                        lambda *_: (self.nv_docker_copy_pass(p), self.open_uri(self.dk_pma_url(p))),
                        "nv-proyecto-btn")
        pma.set_sensitive(up and pma_ok)
        btns["pma"] = pma
        code = vscode_app()
        if code is not None:
            cimg = None
            if code.get_icon() is not None:
                cimg = Gtk.Image.new_from_gicon(code.get_icon(), Gtk.IconSize.BUTTON)
                cimg.set_pixel_size(18)
            vs = nv_button(cimg or "text-editor-symbolic", "VS Code", "Abrir en Visual Studio Code",
                           lambda *_: self.open_in_vscode(folder), "nv-proyecto-btn")
            vs.set_sensitive(os.path.isdir(folder))
            btns["vscode"] = vs
        lg = nv_button(logo("log", 18), "Log", "Ver el log de errores" if php_c else "Arráncalo para ver su log",
                       lambda *_: self.nv_docker_log(p, php_c), "nv-proyecto-btn")
        lg.set_sensitive(bool(php_c))
        btns["log"] = lg
        if kind in ("wp", "ps"):
            btns["imagenes"] = self.nv_images_button({"name": p["folder"], "kind": kind})
        self.nv_place_buttons(acts, btns)
        if web:
            vb = nv_button("list-add-symbolic", "Versiones de PHP…", "Gestionar sus versiones de PHP",
                           lambda *_: self.nv_docker_versions(p), "nv-proyecto-btn")
        else:
            vb = nv_button("go-up-symbolic", "Pasar al Apache de Docker", "Varias versiones de PHP a la vez",
                           lambda *_: self.nv_docker_pass(p), "nv-proyecto-btn")
        vb.set_sensitive(not self.busy)
        conf = buttons_conf()
        self.nv_restyle(vb, conf, ("icono", "list-add-symbolic" if web else "go-up-symbolic"),
                        "Versiones de PHP" if web else "Pasar")
        acts.pack_start(vb, False, False, 0)
        power = nv_button("media-playback-stop-symbolic" if up else "media-playback-start-symbolic",
                          "Parar" if up else "Arrancar",
                          "Parar sus contenedores" if up else "Arrancar sus contenedores",
                          lambda *_: self.run_task(("Parando %s" if up else "Arrancando %s") % p["folder"],
                                                   ["docker-parar" if up else "docker-arrancar", p["slug"]], auto_close=True,
                                                   on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)),
                          "nv-proyecto-btn", "nv-stop" if up else "nv-play")
        power.set_sensitive(not self.busy)
        self.nv_restyle(power, conf, ("icono", "media-playback-stop-symbolic" if up else "media-playback-start-symbolic"),
                        "Parar" if up else "Arrancar")
        acts.pack_end(power, False, False, 0)
        card.pack_start(acts, False, False, 0)
        return card

    def nv_usage_tick(self):
        """Cada 3 s, en segundo plano (leer /proc lleva unos milisegundos): CPU y RAM de Nexum y sus servicios.
        Con la ventana minimizada u oculta, nada."""
        gw = self.win.get_window()
        if getattr(self, "usage_busy", False) or not self.win.get_visible() or not gw or \
                gw.get_state() & Gdk.WindowState.ICONIFIED:
            return True
        self.usage_busy = True

        def work():
            try:
                out = self.usage.sample()
            except Exception:  # noqa: BLE001 - un proceso que desaparece a mitad: la siguiente vez
                out = None
            GLib.idle_add(self.nv_usage_show, out)
        threading.Thread(target=work, daemon=True).start()
        return True

    def nv_usage_show(self, out):
        self.usage_busy = False
        if not out:
            return False
        total = self.usage.total or 1
        cpu = [v[0] for v in out.values() if v[0] is not None]
        mem = sum(v[1] for v in out.values())
        fmt = lambda x: ("%.1f" % x).replace(".", ",")
        self.usage_lbl.set_label("CPU %s %% · RAM %s %%" % (fmt(sum(cpu)) if cpu else "—", fmt(100.0 * mem / total)))
        lines = ["Nexum Dev Stack y sus servicios: CPU %s %% de todo el equipo (%d núcleos) · RAM %s (%s %% de %s)"
                 % (fmt(sum(cpu)) if cpu else "—", self.usage.cpus, fmt_size(mem), fmt(100.0 * mem / total),
                    fmt_size(total)), ""]
        for key, text in USAGE_GROUPS:
            c, m = out[key]
            if m or c:
                lines.append("%s: CPU %s %% · %s" % (text, fmt(c) if c is not None else "—", fmt_size(m)))
        self.usage_lbl.set_tooltip_text("\n".join(lines))
        return False

    def nv_shared_users(self, name):
        """Proyectos del Apache de Docker en marcha que usan un contenedor común: el Apache de Docker o
        su phpMyAdmin (todos) o una MariaDB común (los que van con esa versión). Vacío si no es común."""
        d = self.docker or {}
        up = {c["name"] for c in d.get("containers", []) if c["state"] == "running"}
        m = re.fullmatch(r"nexum-mariadb-(\d+)-(\d+)", name)
        bridge = re.fullmatch(r"nexum-lampp-bd-(\d+(?:-\d+){1,2})", name)
        if not m and not bridge and name not in ("nexum-web", "nexum-pma"):
            return []
        users = []
        for p in d.get("projects", []):
            if not p.get("web"):
                continue
            if bridge and p.get("lampp") != bridge.group(1).replace("-", "."):
                continue
            if m and (p["maria"] != "%s.%s" % m.groups() or p.get("lampp")):
                continue
            if any(re.fullmatch(r"nexum-%s-php\d{2}" % re.escape(p["slug"]), n) for n in up):
                users.append(p["folder"])
        return users

    def nv_stop_shared_ok(self, names, what):
        """Antes de parar algo común: si lo usa algún proyecto en marcha, se dice cuáles y se pregunta."""
        users = sorted({u for n in names for u in self.nv_shared_users(n)})
        if not users:
            return True
        many = len(users) > 1
        if "mariadb" in " ".join(names) or "lampp-bd" in " ".join(names):
            text = ("Es común: ahora %s %s. %s sin BBDD (errores de conexión) hasta que la vuelvas a arrancar; "
                    "al arrancar un proyecto que va con ella, se arranca sola."
                    % ("la usan" if many else "la usa", ", ".join(users), "Se quedarán" if many else "Se quedará"))
        else:
            text = ("Es común: ahora %s %s. %s de verse hasta que lo vuelvas a arrancar; al arrancar un proyecto "
                    "del Apache de Docker, se arranca solo."
                    % ("lo usan" if many else "lo usa", ", ".join(users), "Dejarán" if many else "Dejará"))
        return confirm(self.win, "¿Parar %s?" % what, text,
                       "Pararla igualmente" if "mariadb" in " ".join(names) else "Pararlo igualmente", destructive=True)

    def nv_docker_log(self, p, name):
        """Lo último del contenedor de PHP de un proyecto en Docker: ahí van los errores de PHP de su web
        (PHP-FPM los manda a su salida de errores) y los avisos del propio PHP-FPM."""
        def done(rc, out):
            if rc != 0 and not out.strip():
                message(self.win, "No se han podido leer los registros de %s" % name, "", Gtk.MessageType.ERROR)
                return False
            self.show_text("PHP de %s" % p["folder"], "Últimas líneas del contenedor %s (los errores de PHP de "
                           "https://%s)" % (name, p["domain"]), out, lambda: self.nv_docker_log(p, name))
            return False
        run_quick(["docker-contenedor", "registros", name], done)

    def nv_containers_table(self):
        d = self.docker
        cons = d.get("containers", [])
        stats = (self.dk_stats or {}).get("cpu", {})
        lb = css(Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE), "nv-grupo")
        widths = [270, 110, 150, 130, 60, 130]
        groups = [Gtk.SizeGroup(mode=Gtk.SizeGroupMode.HORIZONTAL) for _ in widths]

        def row(cells, head_row=False, indent=0, on_click=None):
            r = Gtk.ListBoxRow(activatable=on_click is not None)
            b = css(Gtk.Box(spacing=12), "nv-fila", *(["nv-cab"] if head_row else []))
            for n, c in enumerate(cells):
                w = c if isinstance(c, Gtk.Widget) else label(c.upper() if head_row else c)
                if n == 0 and indent:
                    cell = Gtk.Box()
                    sp = Gtk.Box()
                    sp.set_size_request(indent, -1)
                    cell.pack_start(sp, False, False, 0)
                    cell.pack_start(w, True, True, 0)
                    w = cell
                w.set_size_request(widths[n], -1)
                groups[n].add_widget(w)
                b.pack_start(w, n == len(cells) - 1, True, 0)
            r.add(b)
            r.on_click = on_click
            lb.add(r)

        def actions(items):
            a = Gtk.Box(halign=Gtk.Align.START)
            for ic, tip, fn, ok in items:
                b = nv_button(ic, None, tip, lambda *_, fn=fn: fn(), "nv-clasico",
                              *(["nv-stop"] if "stop" in ic else ["nv-play"] if "start" in ic else []))
                b.set_sensitive(ok and not self.busy)
                a.pack_start(b, False, False, 2)
            return a

        def cpu_text(names):
            vals = [stats[n] for n in names if n in stats]
            return ("%.1f %%" % sum(vals)).replace(".", ",") if vals else "—"
        lb.connect("row-activated", lambda _l, r: r.on_click and r.on_click())
        row(["Nombre", "ID", "Imagen", "Puertos", "CPU", "Acciones"], True)
        projects = {p["slug"]: p for p in d["projects"]}
        shown = 0
        for proj in sorted({c["project"] for c in cons}):
            items = sorted((c for c in cons if c["project"] == proj), key=lambda c: c["name"])
            slug = proj[6:] if proj.startswith("nexum-") else ""
            p = projects.get(slug)
            title = p["folder"] if p else proj or "(sin proyecto)"
            # (lo comun del Apache de Docker)
            if not p and proj == "nexum-web":
                title = "Apache de Docker y phpMyAdmin"
            elif not p and re.fullmatch(r"nexum-mariadb-\d+-\d+", proj or ""):
                title = "MariaDB %s (común)" % proj[len("nexum-mariadb-"):].replace("-", ".")
            elif not p and re.fullmatch(r"nexum-lampp-bd-\d+-\d+(-\d+)?", proj or ""):
                title = "Puente a la BBDD de lampp-%s (en vivo)" % proj[len("nexum-lampp-bd-"):].replace("-", ".")
            visible = [c for c in items if (not self.dk_only_up or c["state"] == "running")
                       and (self.dk_query in c["name"].lower() or self.dk_query in title.lower())]
            if not visible:
                continue
            shown += 1
            up = all(c["state"] == "running" for c in items)
            opened = proj in self.dk_open
            name = Gtk.Box(spacing=8)
            name.pack_start(icon("pan-down-symbolic" if opened else "pan-end-symbolic"), False, False, 0)
            ic = css(Gtk.Box(), "nv-dk-icono")
            ic.pack_start(logo("docker", 14), False, False, 0)
            name.pack_start(ic, False, False, 0)
            name.pack_start(label(title, "nv-dk-proyecto", ellipsize=3), False, False, 0)
            # (en marcha: su punto verde que late; ya no hay columna Estado)
            if up:
                name.pack_start(label("●", "nv-verde", "nv-latido", valign=Gtk.Align.CENTER,
                                      tooltip_text="En marcha"), False, False, 0)
            if p:
                web = p.get("web")
                php = Gtk.Button(label="PHP %s" % " · ".join(p["versions"]) if web else "PHP %s" % p["php"],
                                 valign=Gtk.Align.CENTER, sensitive=not self.busy,
                                 tooltip_text="Gestionar sus versiones de PHP"
                                 if web else "Cambiar la versión de PHP")
                php.connect("clicked", lambda *_, p=p: self.nv_docker_versions(p) if p.get("web") else self.on_docker_php(p))
                img_cell = Gtk.Box()
                img_cell.pack_start(php, False, False, 0)
                pma = label(docker_pma_domain() if web else "%s:80" % p["pma"] if p["pma"].isdigit() else "—",
                            "nv-mono", "nv-chico", "nv-enlace")
                acts = actions(([] if web else [
                    ("go-up-symbolic", "Pasarlo al Apache de Docker: sin LAMPP y con varias versiones de PHP a la vez",
                     lambda p=p: self.nv_docker_pass(p), True)]) + [
                    # (lo primero: arrancar o parar todos sus servicios a la vez)
                    ("media-playback-stop-symbolic" if up else "media-playback-start-symbolic", "Parar todos sus servicios" if up else "Arrancar todos sus servicios",
                     lambda p=p, up=up: self.run_task(("Parando %s" if up else "Arrancando %s") % p["folder"],
                                                      ["docker-parar" if up else "docker-arrancar", p["slug"]],
                                                      auto_close=True, on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)), True),
                    ("web-browser-symbolic", "Abrir %s" % self.dk_url(p["domain"]), lambda p=p: self.open_uri(self.dk_url(p["domain"]) + "/"), up),
                    ("drive-multidisk-symbolic", "phpMyAdmin (entra con el usuario root y la contraseña de la llave)",
                     lambda p=p: self.open_uri(self.dk_pma_url(p)), up),
                    ("dialog-password-symbolic", "Copiar la contraseña de root de su BBDD (para su phpMyAdmin)",
                     lambda p=p: self.nv_docker_copy_pass(p), True),
                    ("software-update-available-symbolic", "Actualizar la imagen de PHP %s con lo último de Docker Hub "
                     "(parches de seguridad); la BBDD y la configuración no cambian" % p["php"],
                     lambda p=p: self.nv_docker_update_image(p), True),
                    ("text-x-generic-symbolic", "Registros", lambda p=p: self.run_task("Registros de %s" % p["folder"], ["docker-registros", p["slug"]]), True)] + (
                    [("network-transmit-receive-symbolic", "BBDD: la de LAMPP en vivo (la misma que web.local) o su copia de Docker",
                      lambda p=p: self.nv_docker_db_mode(p), True)] if web and p.get("kind") == "wp" else []) + [
                    ("user-trash-symbolic", "Eliminar el proyecto de Docker: sus contenedores y la copia de su BBDD "
                     "(la carpeta y la BBDD de LAMPP no se tocan)", lambda p=p: self.on_docker_delete(p), True)])
            else:
                img_cell, pma, acts = label(plural(len(items), "contenedor", "contenedores"), "nv-chico", "nv-tenue"), label(""), label("")
                done = lambda *a: run_quick(["gui-docker"], self.on_docker_data)
                if proj == "nexum-web":
                    acts = actions([("media-playback-stop-symbolic" if up else "media-playback-start-symbolic",
                                     "Parar el Apache de Docker y su phpMyAdmin (los proyectos del Apache de Docker dejan "
                                     "de verse)" if up else "Arrancar el Apache de Docker y su phpMyAdmin",
                                     lambda up=up: (not up or self.nv_stop_shared_ok(["nexum-web"], "el Apache de Docker")) and self.run_task(
                                         "Parando el Apache de Docker" if up else "Arrancando el Apache de Docker",
                                         ["docker-web", "parar" if up else "arrancar"], auto_close=True, on_done=done), True)])  # noqa: B023 (done es el mismo en cada vuelta)
                elif re.fullmatch(r"nexum-lampp-bd-\d+-\d+(-\d+)?", proj or "") and len(items) == 1:
                    # (el puente de los proyectos de Docker que usan en vivo la BBDD de esa version LAMPP)
                    ver = proj[len("nexum-lampp-bd-"):].replace("-", ".")
                    users = [q["folder"] for q in d["projects"] if q.get("lampp") == ver]
                    name.set_tooltip_text("Conecta Docker a la MariaDB de lampp-%s" % ver)
                    acts = actions([("media-playback-stop-symbolic" if up else "media-playback-start-symbolic",
                                     "Parar el puente (%s se queda%s sin BBDD)" % (", ".join(users) or "ningún proyecto",
                                                                                   "n" if len(users) > 1 else "")
                                     if up else "Arrancar el puente",
                                     lambda up=up, n=items[0]["name"], t=title: (not up or self.nv_stop_shared_ok([n], t)) and self.run_task(
                                         ("Parando %s" if up else "Arrancando %s") % t,
                                         ["docker-contenedor", "parar" if up else "arrancar", n], auto_close=True,
                                         on_done=done), True)])  # noqa: B023 (done es el mismo en cada vuelta)
                elif re.fullmatch(r"nexum-mariadb-\d+-\d+", proj or "") and len(items) == 1:
                    acts = actions([("media-playback-stop-symbolic" if up else "media-playback-start-symbolic",
                                     "Parar %s (los proyectos que van con ella se quedan sin BBDD)" % title if up else
                                     "Arrancar %s" % title,
                                     lambda up=up, n=items[0]["name"], t=title: (not up or self.nv_stop_shared_ok([n], t)) and self.run_task(
                                         ("Parando %s" if up else "Arrancando %s") % t,
                                         ["docker-contenedor", "parar" if up else "arrancar", n], auto_close=True,
                                         on_done=done), True)])  # noqa: B023 (done es el mismo en cada vuelta)
            row([name, label(""), img_cell, pma, label(cpu_text([c["name"] for c in items]), "nv-mono", "nv-chico", "nv-tenue"), acts],
                on_click=lambda proj=proj: self.nv_dk_toggle(proj))
            if not opened:
                continue
            # (desplegado: su visor, con sus accesos directos, encima de sus contenedores)
            if p:
                vr = Gtk.ListBoxRow(activatable=False, selectable=False)
                vr.on_click = None
                vr.add(self.nv_docker_visor(p, items))
                lb.add(vr)
            for c in visible:
                on = c["state"] == "running"
                kn = Gtk.Box(spacing=8)
                kn.pack_start(nv_dot(on), False, False, 0)
                # (dentro de su proyecto, solo su parte: db-1, php-1, pma-1)
                short = c["name"][len(proj) + 1:] if proj and c["name"].startswith(proj + "-") else c["name"]
                kn.pack_start(label(short, "nv-mono", "nv-chico", ellipsize=3,
                                    tooltip_text="%s · %s" % (c["name"], docker_status_text(c["status"]))), False, False, 0)
                ports = ", ".join(pp.replace("/tcp", "").replace("127.0.0.1:", "").replace("->", ":")
                                  for pp in c["ports"].split(", ") if "->" in pp) or "—"
                own = docker_own(c["name"])
                row([kn, label(c["id"] or "—", "nv-mono", "nv-chico", "nv-tenue", selectable=True,
                               tooltip_text="ID del contenedor"),
                     label(c["image"], "nv-mono", "nv-chico", "nv-enlace", ellipsize=3),
                     label(ports, "nv-mono", "nv-chico", "nv-enlace" if ports != "—" else "nv-tenue"),
                     label(cpu_text([c["name"]]), "nv-mono", "nv-chico", "nv-tenue"),
                     actions([("media-playback-stop-symbolic" if on else "media-playback-start-symbolic", "Parar" if on else "Arrancar",
                               lambda c=c, on=on: (not on or self.nv_stop_shared_ok([c["name"]], c["name"])) and self.run_task(
                                   ("Parando %s" if on else "Arrancando %s") % c["name"],
                                                                ["docker-contenedor", "parar" if on else "arrancar", c["name"]],
                                                                auto_close=True, on_done=lambda *a: run_quick(["gui-docker"], self.on_docker_data)), own),
                              ("view-refresh-symbolic", "Reiniciar", lambda c=c: self.run_task("Reiniciando %s" % c["name"],
                                                                                              ["docker-contenedor", "reiniciar", c["name"]], auto_close=True), own and on),
                              ("text-x-generic-symbolic", "Registros", lambda c=c: self.run_task("Registros de %s" % c["name"],
                                                                                                ["docker-contenedor", "registros", c["name"]]), own),
                              ("user-trash-symbolic", "Eliminar este contenedor", lambda c=c: self.nv_container_delete(c), own)])],
                    indent=26)
        if not shown:
            r = Gtk.ListBoxRow(activatable=False)
            r.add(label("Ningún contenedor" + (" en marcha" if self.dk_only_up else "") + (" con «%s»" % self.dk_query if self.dk_query else ""),
                        "nv-tenue", margin=14))
            lb.add(r)
        return lb

def load_fonts():
    """Fuente del nombre de la cabecera: se escribe en ~/.lvm-instalador/cache/fuentes y se añade
    solo a esta ventana (fontconfig), sin instalarla en el sistema. Sin ella, la del tema."""
    import base64
    import ctypes
    import ctypes.util
    try:
        fc = ctypes.CDLL(ctypes.util.find_library("fontconfig") or "libfontconfig.so.1")
        fc.FcConfigAppFontAddFile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        folder = os.path.join(LOG_DIR, "cache", "fuentes")
        os.makedirs(folder, mode=0o700, exist_ok=True)
        for name, text in FONTS_B64.items():
            data, path = base64.b64decode(text), os.path.join(folder, name)
            if not os.path.isfile(path) or os.path.getsize(path) != len(data) or open(path, "rb").read() != data:
                with open(path + ".nuevo", "wb") as f:
                    f.write(data)
                os.replace(path + ".nuevo", path)
            fc.FcConfigAppFontAddFile(None, path.encode())
    except (OSError, AttributeError, ValueError):
        pass


# «NEXUM» en Goldman (Google Fonts), con la SIL Open Font License 1.1, que va dentro del .ttf (y su
# texto, en fuentes/ del repositorio): Copyright 2018 The Goldman Project Authors
# (https://github.com/magictype/goldman)
FONTS_B64 = {
    "Goldman-Regular.ttf": """
AAEAAAASAQAABAAgRFNJRwAAAAEAATB8AAAACEdERUaDLYAIAAD4ZAAAAi5HUE9TUhwFwgAA+pQAAC+IR1NVQueU8NUAASocAAAG
YE9TLzJiFXbMAAABqAAAAGBjbWFw1Tm9SAAADBAAAAcGY3Z0IBLFCO4AACHkAAAAbGZwZ21iLv99AAATGAAADgxnYXNwAAAAEAAA
+FwAAAAIZ2x5ZoaDS6wAACdYAAC7aGhlYWQkUwfhAAABLAAAADZoaGVhEjwRhgAAAWQAAAAkaG10eAgeN78AAAIIAAAKCGxvY2Er
IvucAAAiUAAABQZtYXhwBhURgQAAAYgAAAAgbmFtZVbPeZMAAOLAAAADtnBvc3TNTVKZAADmeAAAEeJwcmVwWrHfOwAAISQAAAC9
AAEAAAABAAAs3sIFXw889QAPA+gAAAAA2zyh3AAAAADbPiOs/dr9WBDbBB4AAAAGAAIAAAAAAAAAAQAAA4T+1AAAEQ392v8iENsA
AQAAAAAAAAAAAAAAAAAAAoIAAQAAAoIB9gARAH4ABQACAJgA/ACNAAACVA4MAAMAAwAEAowBkAAFAAACigJYAAAASwKKAlgAAAFe
ADIBDQAAAAAAAAAAAAAAAAAAAEUAAABDAAAAAAAAAABOT05FAMAADfsCA4T+1AAABEwCvCAAAZMAAAAAAcACTAAAACAABAJAAAAC
WAAAAlgAAADcAAADDgAAA7EAFASsAAoErAAKAw4AAAMOAAADDgAAAw4AAAMOAAADDgAAAw4AAAMOAAADDgAAAw4AAAMOAAADDgAA
Aw4AAAMOAAADDgAAAw4AAAMOAAADDgAAAw4AAAMOAAADDgAAAw4AAAMOAAADDgAAAxwAUALzAEYC8wBGAvMARgLzAEYC8wBGAvMA
RgMmAFAF8ABQBfAAUAMmAFADJv/+AuMACgWHAFAFhwBQAv4AUAL+AFAC/gBQAv4AUAL+AFAC/gBQAv4AUAL+AFAC/gBQAv4AUAL+
AFAC/gBQAv4AUAL+AFAC/gBQAv4AUAL+AFAC/gBQAzoAUAL+AFADJv/+Av4AUALUAFADGwBGAxsARgMbAEYDGwBGAxsARgMbAEYD
GwBQAzAAUAMwAFADMABQASQAUAO6AFABJABQAST//AEkAAIBJP/FASQACAEkAFABJABQASQAMwEkACkBJP/8ASQACgEkADwBJP/n
ApYACgKWAAoDHgBQAx4AUAKuAFAFRABQAq4AUAKuAFACrgBQAlgAUAPBAFACrv/zA4sAUAM6AFAF0ABQAlgAAAM6AFADOgBQAzoA
UAOMAAoETQBQAzoAUAMdAEYFAQBGAx0ARgMdAEYDHQBGAx0ARgMdAEYDHQBGAx0ARgMdAEYDHQBGAx0ARgMdAEYDHQBGAx0ARgMd
AEYDHQBGAx0ARgMdAEYDHQBGAx0ARgMdAEYDHQBGAx0ARgMdAEYDHQBGA28AKAMdAEYDHQBGAx0ARgMdAEYDHQBGAv0AUAMmAEYD
PABQAzwAUAM8AFADPABQAzwAUAM8AFAC9AA8AvQAPAL0ADwC9AA8As8AMgL0ADwC9AA8ArYAFAK2ABQCtgAUArYAFAK2ABQC/QBQ
Av4AQQL+AEEC/gBBAv4AQQL+AEEC/gBBAv4AQQL+AEEC/gBBAv4AQQL+AEEC/gBBAv4AQQL+AEEC/gBBAv4AQQL+AEEC/gBBAv4A
QQL+AEEC/gBBAuAACgRXAAoEVwAKBFcACgRXAAoEVwAKAuIACgLiAAoC4gAKAuIACgLiAAoC4gAKAuIACgLiAAoC4gAKAuIACgLc
ADIC3AAyAtwAMgLcADICiwAtAoAALQKLAC0CiwAtAosALQKLAC0CiwAtAosALQKLAC0CiwAtAosALQKLAC0CiwAtAosALQKLAC0A
5v/EAAD+egKLAC0CiwAtAosALQQUAC0EFAAtAosALQKLAC0CiwAtAosALQMkAFACiwAtAMEAJhENABQCgABQAosALQKLAC0BkgAo
AZIAHgIcAFADqwBQAosALQKKADwBfv/YAQAAUAFnACgBZwAoAXUAKAGdAFABVAAUAAD+cAAA/nAAAP5wAAD+cAAA/nAAAP5bAAD+
cAEAAFABdwBQAXcAUAJOADICTgAyAUEAOQDBAFkAAP6VAk4AMgJOADICTgAyAk4AMgLzAEYA3gAAAAAAAAJbADIBQQAUAAD+cAAA
/nAAAP5wAAD+cAAA/lUBLwBQAvMARgEqADoAAP7CAAD+2AJbAFADLgBQAqcAUAKUADICRABQAkQAUAAA/fgC3AAyApQAMgHMAFAB
nQA6AAD+NQAA/igCfwBQAQ7/kgK4ADwC1QAyAMAAJwAA/t0AAP7UAWoAKAT1ADIE9QAyAmwAMgJsADICbAAyAmwAMgJsADICbAAy
AmwAMgJsADICbAAyAmwAMgJsADICbAAyAmwAMgJsADICbAAyAmwAMgK4ADIBXAAZAVwAGQJsADICqwBQAmwAMgPAAFACsAAoArwA
UAKPADwCbAAyAjAAUAMnAB4CgAAyAmwAMgLjADwBTQBQAU0AUAHfABQDKwAUA9YAFAUNABQDswAUAmIAFAOCABQB3wAUAl0AFAJi
ABQCWACCArUAKAFbABQBWwAUA8UAFAJdABQCdQAoAvYAKAGKAAUBewAUAa0AKAEO/5IDJABQAosAKAKLACgCiwAoAosAKAKLACgC
iwAoArMAKADmABQAAP7KAoAAUAKAAFADGwBGAuIAUALiAFAB1ABQAdQAUAKPADwCj//7Ao8APAAA/tQAAP/zAYYAUAAA/mYB4ABQ
AeAAUAEHADwA8gA8APIAPADy/+MA8v/pAPL/rADy/+8A8gA8AQcAPADyADwA8gAaAPIAEADy/+MCBgA8APL/8QN0AAACGAAoAPIA
DgDy/84BE/+wAQj/sAEI/7ACagA8AmoAPAJqADwDXgA8APwAPAD8ADwBRAA8APwAOQGxADwBSgAoAoAAUAKJAFACpwA8ApoAKAI9
ACgCDwA8AlgAHgJYACgA/P/VA5EAPAFMAB4AAP6sAAD+rANJAFACbAA8An8AUADKACgCgAA8AnMAUAKPADwCjwA8A2cAPADcAAAC
jwA8Ao8APAKl/7AC1AAyAWoAGQFqABkDogA8AlgAAAJEAGQCjwA8A2kAUAT/AFACgAAyAoAAMgKAADICgAAyAoAAMgKAADICgAAy
AoAAMgKAADICgAAyAoAAMgKAADICgAAyAoAAMgQMADIBBQAeAAD+1AKAADICgAAyAoAAMgKAADICgAAyAoAAMgKAADICgAAyAoAA
MgKAADICgAAyAWcAFAC0AAoA5QAUA08AFAMxABQDfQAUAOUAFAKAADIBdwAtAXIAMgKAADICgAAyAoAAMgKAADICigA8AAD+swKu
AFABJgAEATYAKAJeACgDgAA8AS8AUAEvAFABLwBQBNsAPANJAFADKwA8A3UAUAKBAFACgQBQAlgAKAK5ACgCigAyAnIAUAJzAFAB
XgAoAfwAOgHUAFAB1P/+ARYAeAEWACYBPgA6AMoAKAH1ADwB9QA8AyIAKAH1ADwB9QA8AfUAPAHnAFABPgAoASQAFAAA/o4B9QA8
Au0APAJpAFACpQBQAn4AMgJ+ADICfgAyAn4AMgKQADICfgAyAn4AMgFqACgCOQBQAT4AOgJpABQBNQAKAUwAFAO2ABQC1ABQAWoA
KAFqACgBugAUAAD9+AAA/gwB4ABQAqcAPAAA/doAAP4WAuoAKAHEABQBxAAUAcQAFAHEABQBxAAUAqgAUAKzACgBWgAUAVoAFAPE
ABQD8gAUAYYAKAGSACgAAP5mAlUAUAJ8ACgBPgAUAT4AFAFcACgCgAA8AoAAPAKAADwCgAA8AoAAPAKAADwCgAA8AoAAPAKAADwC
gAA8AoAAPAKAADwCgAA8AoAAPAKAADwCgAA8AoAAPAKAADwCgABQAoAAPAKAADwCgAA8Ak4ACgNdAAoDXQAKA10ACgNdAAoDXQAK
At4AKAQ3ADwCRAAKAk//2AJP/9gCT//YAk//2AJP/9gC9gAUAk//2AJP/9gCT//YAk//2AJhACgCYQAoAmEAKAJhACgC9ABQAXoA
KAF6ADcCoQBQAvQAUAAAAAIAAAADAAAAFAADAAEAAAAUAAQG8gAAAKYAgAAGACYADQB+AUgBfgGPAZIBnQGhAbABzAHnAesB8wIb
Ai0CMwI3AlkCcgK6ArwCxwLJAt0DBAMMAw8DEgMbAyEDJAMoAy4DMQM4A5QDqQO8A8AehR6eHvkgECAUIBogHiAiICYgMCAzIDog
RCBSIHQgoSCkIKkgrSCyILUguiC9IRMhFiEiIS4hXiICIgUiDyISIhUiGiIeIisiSCJgImUlyyfp+P/7Av//AAAADQAgAKABSgGP
AZIBnQGgAa8BxAHmAeoB8QH6AioCMAI3AlkCcgK5ArwCxgLJAtgDAAMGAw8DEQMbAyEDIwMmAy4DMQM1A5QDqQO8A8AegB6eHqAg
ECATIBggHCAgICYgMCAyIDkgRCBSIHQgoSCjIKYgqyCxILUguSC8IRMhFiEiIS4hWyICIgUiDyIRIhUiGSIeIisiSCJgImQlyifo
+P/7Af////UAAAAAAAD/Ev/a/tUAAAAAAAAAAAAAAAAAAAAAAAD/av/P/1MAAP4zAAD+nQAAAAAAAP4aAAD+bP7ZAAAAAP3T/oYA
APyY/Ob+Af5GAADhrgAA4XsAAOH6AAAAAOEo4dMAAOFI4S3g0eD84H4AAAAAAAAAAOBfAAAAAOCd4LjhKeAoAADf/N9M3/sAAN8c
AADffd9x3qnfawAAAAAAAAfxAAAAAQAAAKQBYAKwAAAAAAAAAxIDFAMWAyYDKAMqAy4DcAN2AAAAAAAAA3YAAAN2AAADdgOAA4gA
AAOSAAAAAAOQA5IAAAAAA5IAAAAAAAAAAAOQAAADmAAABEgAAARIBEwAAAAABEwAAAAAAAAAAAAABEQERgRMBFAAAARQBFIAAAAA
AAAAAARMAAAAAAAABEwAAARMAAAAAAAAAAAERgRIBEoAAARKAAAAAwFaAg4BzQEyAf8A7QIVAfwB/QD2AgcBIAGKAgACNQJ9AesC
TAJDAW0BZwIyAi4BSgHGAR4CLQGsAVUBfAIMAPcABAAgACEAJwAvAEUARgBNAFAAXwBhAGMAawBsAHUAlQCWAJcAnQCkAKoAvwDA
AMUAxgDPAP4A+gD/APQCYgF6ANMA+QELASYBOgFcAXMBgwGMAZ8BogGmAbUBvwHPAfkCCwIWAiQCPQJQAmYCZwJuAm8CeQD8APsA
/QD1AcIBWwEXAjkBJQJ0AQgCLAEtASQB8wF/AbICOAIcAbYBLAIIAk8CSADiAboB+wIBARUB8QH0AYAB8AHvAkcCDQAYAAgADwAf
ABYAHQAGACQAPQAwADMAOgBZAFIAVABWAEMAdACEAHcAeQCTAIABvgCRALEAqwCtAK8AxwCpAXkA6QDVANwA+ADlAPIA5wERAUgB
OwE+AUUBlgGOAZABkgFXAcwB4AHQAdIB9wHZATAB9QJXAlECUwJVAnACQgJyABsA7AAJANYAHADuACIBDAAlARIAJgETACMBEAAq
ASoAKwErAEABTwAxATwAOwFGAEIBVAAyAT0ASQF2AEcBdABLAXgASgF3AE8BhQBOAYQAXgGeAFwBmgBTAY8AXQGdAFcBlQBRAZkA
YAGgAGIBowGkAGUBpwBnAakAZgGoAGgBqgBqAbQAbwHAAHEBxABwAcMAQQFTAI4B6gB4AdEAjAHoAHYB3QCYAhcAmgIaAJkCGQCe
AiUAogIpAKACJwCfAiYApwJAAKYCPwClAj4AvgJlALsCYQCsAlIAvQJkALkCXwC8AmMAwgJpAMgCcQDJANACegDSAnwA0QJ7AIYB
4gCzAlkAKQAuATkAZABpAbEAbQBzAckASAF1AJAB8gAoAC0BOAAeAPMABwDoAJIB9gAVAOQAGgDrADkBRAA/AU0AVQGRAFsBmAB/
AdgAjQHpAJsCGwCcAiAArgJUALoCYACjAioAqAJBAIEB2gCUAfgAggHbAM0CdwIJATcBGAENAQABNAIeAd4CSQGIAXsA4wEZAkoB
uAECATUBLwGGAh8BiQEPAQcBIgE2AS4BIQEWAd8COwI6AjcCNgDEAmsAwQJoAMMCagAXAOYAGQDqABAA3QASAN8AEwDgABQA4QAR
AN4ACgDXAAwA2QANANoADgDbAAsA2AA8AUcAPgFJAEQBWAA0AT8ANgFBADcBQgA4AUMANQFAAFoBlwBYAZQAgwHcAIUB4QB6AdMA
fAHVAH0B1gB+AdcAewHUAIcB4wCJAeUAigHmAIsB5wCIAeQAsAJWALICWAC0AloAtgJcALcCXQC4Al4AtQJbAMsCdQDKAnMAzAJ2
AM4CeAFSAVACEAIRAg8BJwEoAQkBvAIrAXIBrgHBAgQCIgJtATMBWQGlAgUBfgIjAa8BuQIhAe4CRgFqAjECPAG7AQoCGAGtAX0B
swJsAasCHQFlAWsAALAALCCwAFVYRVkgIEu4AA5RS7AGU1pYsDQbsChZYGYgilVYsAIlYbkIAAgAY2MjYhshIbAAWbAAQyNEsgAB
AENgQi2wASywIGBmLbACLCMhIyEtsAMsIGSzAxQVAEJDsBNDIGBgQrECFENCsSUDQ7ACQ1R4ILAMI7ACQ0NhZLAEUHiyAgICQ2BC
sCFlHCGwAkNDsg4VAUIcILACQyNCshMBE0NgQiOwAFBYZVmyFgECQ2BCLbAELLADK7AVQ1gjISMhsBZDQyOwAFBYZVkbIGQgsMBQ
sAQmWrIoAQ1DRWNFsAZFWCGwAyVZUltYISMhG4pYILBQUFghsEBZGyCwOFBYIbA4WVkgsQENQ0VjRWFksChQWCGxAQ1DRWNFILAw
UFghsDBZGyCwwFBYIGYgiophILAKUFhgGyCwIFBYIbAKYBsgsDZQWCGwNmAbYFlZWRuwAiWwDENjsABSWLAAS7AKUFghsAxDG0uw
HlBYIbAeS2G4EABjsAxDY7gFAGJZWWRhWbABK1lZI7AAUFhlWVkgZLAWQyNCWS2wBSwgRSCwBCVhZCCwB0NQWLAHI0KwCCNCGyEh
WbABYC2wBiwjISMhsAMrIGSxB2JCILAII0KwBkVYG7EBDUNFY7EBDUOwA2BFY7AFKiEgsAhDIIogirABK7EwBSWwBCZRWGBQG2FS
WVgjWSFZILBAU1iwASsbIbBAWSOwAFBYZVktsAcssAlDK7IAAgBDYEItsAgssAkjQiMgsAAjQmGwAmJmsAFjsAFgsAcqLbAJLCAg
RSCwDkNjuAQAYiCwAFBYsEBgWWawAWNgRLABYC2wCiyyCQ4AQ0VCKiGyAAEAQ2BCLbALLLAAQyNEsgABAENgQi2wDCwgIEUgsAEr
I7AAQ7AEJWAgRYojYSBkILAgUFghsAAbsDBQWLAgG7BAWVkjsABQWGVZsAMlI2FERLABYC2wDSwgIEUgsAErI7AAQ7AEJWAgRYoj
YSBksCRQWLAAG7BAWSOwAFBYZVmwAyUjYUREsAFgLbAOLCCwACNCsw0MAANFUFghGyMhWSohLbAPLLECAkWwZGFELbAQLLABYCAg
sA9DSrAAUFggsA8jQlmwEENKsABSWCCwECNCWS2wESwgsBBiZrABYyC4BABjiiNhsBFDYCCKYCCwESNCIy2wEixLVFixBGREWSSw
DWUjeC2wEyxLUVhLU1ixBGREWRshWSSwE2UjeC2wFCyxABJDVVixEhJDsAFhQrARK1mwAEOwAiVCsQ8CJUKxEAIlQrABFiMgsAMl
UFixAQBDYLAEJUKKiiCKI2GwECohI7ABYSCKI2GwECohG7EBAENgsAIlQrACJWGwECohWbAPQ0ewEENHYLACYiCwAFBYsEBgWWaw
AWMgsA5DY7gEAGIgsABQWLBAYFlmsAFjYLEAABMjRLABQ7AAPrIBAQFDYEItsBUsALEAAkVUWLASI0IgRbAOI0KwDSOwA2BCIGC3
GBgBABEAEwBCQkKKYCCwFCNCsAFhsRQIK7CLKxsiWS2wFiyxABUrLbAXLLEBFSstsBgssQIVKy2wGSyxAxUrLbAaLLEEFSstsBss
sQUVKy2wHCyxBhUrLbAdLLEHFSstsB4ssQgVKy2wHyyxCRUrLbArLCMgsBBiZrABY7AGYEtUWCMgLrABXRshIVktsCwsIyCwEGJm
sAFjsBZgS1RYIyAusAFxGyEhWS2wLSwjILAQYmawAWOwJmBLVFgjIC6wAXIbISFZLbAgLACwDyuxAAJFVFiwEiNCIEWwDiNCsA0j
sANgQiBgsAFhtRgYAQARAEJCimCxFAgrsIsrGyJZLbAhLLEAICstsCIssQEgKy2wIyyxAiArLbAkLLEDICstsCUssQQgKy2wJiyx
BSArLbAnLLEGICstsCgssQcgKy2wKSyxCCArLbAqLLEJICstsC4sIDywAWAtsC8sIGCwGGAgQyOwAWBDsAIlYbABYLAuKiEtsDAs
sC8rsC8qLbAxLCAgRyAgsA5DY7gEAGIgsABQWLBAYFlmsAFjYCNhOCMgilVYIEcgILAOQ2O4BABiILAAUFiwQGBZZrABY2AjYTgb
IVktsDIsALEAAkVUWLEOBkVCsAEWsDEqsQUBFUVYMFkbIlktsDMsALAPK7EAAkVUWLEOBkVCsAEWsDEqsQUBFUVYMFkbIlktsDQs
IDWwAWAtsDUsALEOBkVCsAFFY7gEAGIgsABQWLBAYFlmsAFjsAErsA5DY7gEAGIgsABQWLBAYFlmsAFjsAErsAAWtAAAAAAARD4j
OLE0ARUqIS2wNiwgPCBHILAOQ2O4BABiILAAUFiwQGBZZrABY2CwAENhOC2wNywuFzwtsDgsIDwgRyCwDkNjuAQAYiCwAFBYsEBg
WWawAWNgsABDYbABQ2M4LbA5LLECABYlIC4gR7AAI0KwAiVJiopHI0cjYSBYYhshWbABI0KyOAEBFRQqLbA6LLAAFrAXI0KwBCWw
BCVHI0cjYbEMAEKwC0MrZYouIyAgPIo4LbA7LLAAFrAXI0KwBCWwBCUgLkcjRyNhILAGI0KxDABCsAtDKyCwYFBYILBAUVizBCAF
IBuzBCYFGllCQiMgsApDIIojRyNHI2EjRmCwBkOwAmIgsABQWLBAYFlmsAFjYCCwASsgiophILAEQ2BkI7AFQ2FkUFiwBENhG7AF
Q2BZsAMlsAJiILAAUFiwQGBZZrABY2EjICCwBCYjRmE4GyOwCkNGsAIlsApDRyNHI2FgILAGQ7ACYiCwAFBYsEBgWWawAWNgIyCw
ASsjsAZDYLABK7AFJWGwBSWwAmIgsABQWLBAYFlmsAFjsAQmYSCwBCVgZCOwAyVgZFBYIRsjIVkjICCwBCYjRmE4WS2wPCywABaw
FyNCICAgsAUmIC5HI0cjYSM8OC2wPSywABawFyNCILAKI0IgICBGI0ewASsjYTgtsD4ssAAWsBcjQrADJbACJUcjRyNhsABUWC4g
PCMhG7ACJbACJUcjRyNhILAFJbAEJUcjRyNhsAYlsAUlSbACJWG5CAAIAGNjIyBYYhshWWO4BABiILAAUFiwQGBZZrABY2AjLiMg
IDyKOCMhWS2wPyywABawFyNCILAKQyAuRyNHI2EgYLAgYGawAmIgsABQWLBAYFlmsAFjIyAgPIo4LbBALCMgLkawAiVGsBdDWFAb
UllYIDxZLrEwARQrLbBBLCMgLkawAiVGsBdDWFIbUFlYIDxZLrEwARQrLbBCLCMgLkawAiVGsBdDWFAbUllYIDxZIyAuRrACJUaw
F0NYUhtQWVggPFkusTABFCstsEMssDorIyAuRrACJUawF0NYUBtSWVggPFkusTABFCstsEQssDsriiAgPLAGI0KKOCMgLkawAiVG
sBdDWFAbUllYIDxZLrEwARQrsAZDLrAwKy2wRSywABawBCWwBCYgICBGI0dhsAwjQi5HI0cjYbALQysjIDwgLiM4sTABFCstsEYs
sQoEJUKwABawBCWwBCUgLkcjRyNhILAGI0KxDABCsAtDKyCwYFBYILBAUVizBCAFIBuzBCYFGllCQiMgR7AGQ7ACYiCwAFBYsEBg
WWawAWNgILABKyCKimEgsARDYGQjsAVDYWRQWLAEQ2EbsAVDYFmwAyWwAmIgsABQWLBAYFlmsAFjYbACJUZhOCMgPCM4GyEgIEYj
R7ABKyNhOCFZsTABFCstsEcssQA6Ky6xMAEUKy2wSCyxADsrISMgIDywBiNCIzixMAEUK7AGQy6wMCstsEkssAAVIEewACNCsgAB
ARUUEy6wNiotsEossAAVIEewACNCsgABARUUEy6wNiotsEsssQABFBOwNyotsEwssDkqLbBNLLAAFkUjIC4gRoojYTixMAEUKy2w
TiywCiNCsE0rLbBPLLIAAEYrLbBQLLIAAUYrLbBRLLIBAEYrLbBSLLIBAUYrLbBTLLIAAEcrLbBULLIAAUcrLbBVLLIBAEcrLbBW
LLIBAUcrLbBXLLMAAABDKy2wWCyzAAEAQystsFksswEAAEMrLbBaLLMBAQBDKy2wWyyzAAABQystsFwsswABAUMrLbBdLLMBAAFD
Ky2wXiyzAQEBQystsF8ssgAARSstsGAssgABRSstsGEssgEARSstsGIssgEBRSstsGMssgAASCstsGQssgABSCstsGUssgEASCst
sGYssgEBSCstsGcsswAAAEQrLbBoLLMAAQBEKy2waSyzAQAARCstsGosswEBAEQrLbBrLLMAAAFEKy2wbCyzAAEBRCstsG0sswEA
AUQrLbBuLLMBAQFEKy2wbyyxADwrLrEwARQrLbBwLLEAPCuwQCstsHEssQA8K7BBKy2wciywABaxADwrsEIrLbBzLLEBPCuwQCst
sHQssQE8K7BBKy2wdSywABaxATwrsEIrLbB2LLEAPSsusTABFCstsHcssQA9K7BAKy2weCyxAD0rsEErLbB5LLEAPSuwQistsHos
sQE9K7BAKy2weyyxAT0rsEErLbB8LLEBPSuwQistsH0ssQA+Ky6xMAEUKy2wfiyxAD4rsEArLbB/LLEAPiuwQSstsIAssQA+K7BC
Ky2wgSyxAT4rsEArLbCCLLEBPiuwQSstsIMssQE+K7BCKy2whCyxAD8rLrEwARQrLbCFLLEAPyuwQCstsIYssQA/K7BBKy2whyyx
AD8rsEIrLbCILLEBPyuwQCstsIkssQE/K7BBKy2wiiyxAT8rsEIrLbCLLLILAANFUFiwBhuyBAIDRVgjIRshWVlCK7AIZbADJFB4
sQUBFUVYMFktAEu4AMhSWLEBAY5ZsAG5CAAIAGNwsQAHQrQAKxsDACqxAAdCtzAEIAgSBwMKKrEAB0K3NAIoBhkFAwoqsQAKQrwM
QAhABMAAAwALKrEADUK8AEAAQABAAAMACyq5AAMAAESxJAGIUViwQIhYuQADAGREsSgBiFFYuAgAiFi5AAMAAERZG7EnAYhRWLoI
gAABBECIY1RYuQADAABEWVlZWVm3MgIiBhQFAw4quAH/hbAEjbECAESzBWQGAEREAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAGAAYABgAGAJMAAACTP/r/1YCTAAAAkz/6/9WAHkAeQBWAFYCTAAAAnoBwAAA/0sCTAAAAoEBwAAA/0sAGAAYABgA
GAITAOgCEwDoAAAAKgAqACoAKgBcAJYA/gEQASIBNAFGAWABcgGEAZYBqAG6AdQB5gH4AgoCHAIuAkACUgJkAnYCiAKaAqwCxgLY
AzADeAOKA5wDqAO6A8wECAQUBCYEOARABGoEdgSCBLgEygTcBO4FAAUSBSwFPgVQBWIFdAWGBZgFqgW8Bc4F4AXyBkwGXgZwBoIG
sAcGBxgHKgc8B0gHWge+B+gH+ggMCCYIMghECFYIaAh6CIwIngiwCMII1AjmCPgJCgkcCVQJZgnqCfwKJAowCkIKTgpaCmwKeAqK
CsYK/gsKCwoLHAsuCzoLjguaC6wL9gxgDHIMhAyWDKgMwgzUDOYM+A0KDRwNNg1QDWINdA2GDZgNqg28Dc4N4A3yDgQOFg4oDpwO
rg7ADtIO5A7+D0YPshBWEGgQehCGEJgQqhEiETQRRhFSEbIRxBHQEfQSBhIYEiQSMBJ8ErwSzhLgEvITBBMWEygTOhNME14TcBOC
E5QTphO4E8oT3BPuFAAUEhQkFE4UjhSgFLIUxBTWFQwVOhVMFV4VcBWCFZQVphW4FcoV/hYQFiIWNBaeFyIXLhc6F0YXXBdoF3QX
gBeMF5gXrhe6F8YX0hfcGAQYFhgoGDoZKBk0GUAZUhlkGXYalBqmGq4iRiK8Isgi3iMmIzYjeCRGJFgksCS8JNYk4iUqJTYlXCVm
JXYlsCXCJdQl5iX4JgomNCZEJlQmnCaoJrIm4CbyJv4nCicWJygnxCfMKB4oyijUKQopHCkuKUApUilkKi4qWCpoKngqkiqkKyIr
eCuqK/IsAiwOLCAsaCxyLIIsnCy2LL4tZi3eLegt+C4ILhQuIC4sLoYuki6eLqouti7CLtgu5C7wLvwvDi8gLzIvRC9QL2Iv2i/q
L/owDDAcMC4wSjC6MNYxLDE+MVQxxjI0MkYysDMEM1ozsDO8M8gz1DPgNFA0XDS2NRI1GjUoNYI1jDWcNaw1tDYUNkw2VjZmNnY2
kjbON0I3TjdaN2Y3cjeEN/o4BDgQOCY4PDjgOOw4+DkEOSQ5cDmCOZQ51jocOiY6PDpYOmA6lDqmOrI6vjrKOtw67jsAOxI7LDs4
O0o7XDtoO3o8ADxoPII8lDziPO49Ij2oPbo+OD7GPuQ+9j8CPw4/ID8sPzg/Tj+wQAJAYEBsQJpAtkDIQRhBIkEyQWBBpkIGQiBC
TkKOQqpC4kLuQzhDOENEQ1BDpkQQRCBEMEQ8RDxErkTARTJFTkWURaBFrEW4RcRF2kXmRfJF/kYQRiJGPEZWRmhG9kcAR1pHZkd4
R4pHlkeoR7RHxkfYR+RH9kgISCZIMEhASFBIYEhwSIBIkkiiSLJIxEjQSOJI/ElYSaBJ1EngShZKfEseS0BLTktWTDZMpE0gTWpN
lE2qTbJN3k44TtBPak92T4JPkk+eT65P2k/iUBBQaFB6UK5QwFDMUN5Q+FEaUSRRelGMUd5R5lJuUsxS2FLkUvBTUlNeU2pTdlPq
U/xUJFQuVD5UTlS4VMJU0lTwVRBVIlUqVXxVnFW8VfpWPlZQVmJWblZ6VthXXFdmV3ZXhleWV6ZXsFf6WBRYaFhyWIJYkljOWNpY
5ljyWQRZFlkoWTRZRllYWWRZdlmCWZRZplmyWcRZ1ln2WghaFFomWk5ajlqaWqZauFrEWxRbclumXAxcGFwkXDZcSFyQXJxcrlzA
XNJdBF0QXRxdLl12XYBdkF2iXbQAAAACAAAAAAJAAkwAAwAHACpAJwAAAAMCAANnAAIBAQJXAAICAV8EAQECAU8AAAcGBQQAAwAD
EQUGFysxESERJSERIQJA/kQBOP7IAkz9tGABjAAAAAACAAAAAAMOAkwABwALAC1AKgAEAAIBBAJnAAUFAF8AAAAiTQYDAgEBIwFO
AAALCgkIAAcABxEREQcIGSsxATMBIychBzchAyMBJcUBJJo7/ppBZQEdiQoCTP20f3/hAREAAAAAAgAUAAADnQJMAAcADQAyQC8D
AgICAwEBAQICTAADAwBfAAAAIk0AAgIBXwQBAQEjAU4AAAwLCQgABwAHFAUIFyszJzcnEzMBByUhNwEjASgUjQHwjAGBFP1JAgQF
/wAK/vwoV24BX/3cKGMKAWT+nAAAAAACAAoAAASYAkwAEgAWAH+1CwEFBAFMS7AOUFhAKAACAAMIAgNnAAgABgQIBmcJAQEBAF8A
AAAiTQAEBAVfCgcCBQUjBU4bQC4ACQABAQlyAAIAAwgCA2cACAAGBAgGZwABAQBgAAAAIk0ABAQFXwoHAgUFIwVOWUAUAAAWFRQT
ABIAEhEjERERERELCB0rMwEhFSEVIRUhFSEXFAYjITUhBzchESMKARADUv4WAXb+igHuKDZC/d7+3D5gAQKIAkxgimOfVQQHiYnh
ARsAAAD//wAKAAAEmAMmAiYABgAAAQcA4wOvAIwACLECAbCMsDUrAAD//wAAAAADDgMmAiYABAAAAQcA4wLrAIwACLECAbCMsDUr
AAD//wAAAAADDgMdAiYABAAAAQcBAgKCAIwACLECAbCMsDUrAAD//wAAAAADDgPiAiYABAAAAQcBAwKAAIwACLECArCMsDUrAAD/
/wAA/6cDDgMdAiYABAAAACcBNgJyAEYBBwECAoIAjAAQsQIBsEawNSuxAwGwjLA1KwAA//8AAAAAAw4D4gImAAQAAAEHAQQCgACM
AAixAgKwjLA1KwAA//8AAAAAAw4EBgImAAQAAAEHAQUCggCMAAixAgKwjLA1KwAA//8AAAAAAw4DygImAAQAAAEHAQYCggCMAAix
AgKwjLA1KwAA//8AAAAAAw4DEgImAAQAAAEHARkCiACMAAixAgGwjLA1KwAA//8AAAAAAw4D2AImAAQAAAEHARoChQCMAAixAgKw
jLA1KwAA//8AAP+nAw4DEgImAAQAAAAnATYCcgBGAQcBGQKIAIwAELECAbBGsDUrsQMBsIywNSsAAP//AAAAAAMOA9gCJgAEAAAB
BwEbAoUAjAAIsQICsIywNSsAAP//AAAAAAMOA/wCJgAEAAABBwEcAowAjAAIsQICsIywNSsAAP//AAAAAAMOA8ACJgAEAAABBwEd
AowAjAAIsQICsIywNSsAAP//AAAAAAMOAyYCJgAEAAABBwEpAsMAbgAIsQICsG6wNSsAAP//AAAAAAMOAvYCJgAEAAABBwEvAtYA
bgAIsQICsG6wNSsAAP//AAD/pwMOAkwCJgAEAAABBwE2AnIARgAIsQIBsEawNSsAAP//AAAAAAMOAyYCJgAEAAABBwF7Al8AjAAI
sQIBsIywNSsAAP//AAAAAAMOA0oCJgAEAAABBwGGAksAggAIsQIBsIKwNSsAAP//AAAAAAMOAwgCJgAEAAABBwEHAoIAUAAIsQIB
sFCwNSsAAP//AAAAAAMOAtoCJgAEAAABBwG4AlQAeAAIsQIBsHiwNSsAAP//AAD/WQMOAkwCJgAEAAABBwHfA2kAEAAIsQIBsBCw
NSsAAP//AAAAAAMOA0UCJgAEAAABBwIfAnwAjAAIsQICsIywNSsAAP//AAAAAAMOBB4CJgAEAAAAJwIfAnwAjAEHAOMC6wGEABGx
AgKwjLA1K7EEAbgBhLA1KwD//wAAAAADDgMOAiYABAAAAQcCSgJ3AIIACLECAbCCsDUrAAAAAwBQAAAC4AJNABIAHAAmADlANgkB
BQIBTAACAAUEAgVnAAMDAF8AAAAiTQAEBAFfBgEBASMBTgAAJiQfHRwaFRMAEgARIQcIFyszESEyFhUVFAYHFhYVFRQOAiMBIRY2
NTU0JiMhESEyNjU1NCYjIVABs15WIxQsNA4nRzn+qQEaIyIgLP7tATsmJy41/tsCTUs1Hik1Cw5FOBIePDEeAWEBJRwKFyv+cyYh
Eh8nAAABAEYAAALfAk0AIAAyQC8bAQMCHAEAAwJMAAICAV8AAQEiTQADAwBfBAEAACMATgEAGhYSDgoHACABHwUIFiszIiYmNTU0
NjMhMhYVByYmIyMiFRUUFjMzMjY3FxQGBiP9R1AgVmEBLUVJFBGnnzNQIy0pprcWKSFYUyhQO99gWw8IUwMHR/8iJQcEQgUUEP//
AEYAAALfAyYCJgAhAAABBwDjAwoAjAAIsQEBsIywNSsAAP//AEYAAALfAyECJgAhAAABBwEPAoMAjAAIsQEBsIywNSsAAP//AEb/
JALfAk0CJgAhAAAABwEWAS4AAP//AEYAAALfAxICJgAhAAABBwEZAqcAjAAIsQEBsIywNSsAAP//AEYAAALfAvYCJgAhAAABBwE1
Ao8AggAIsQEBsIKwNSsAAAACAFAAAALqAkwADAAVAC1AKgEBAwABTAADAwBfAAAAIk0AAgIBXwQBAQEjAU4AABUTDw0ADAALIgUI
FyszESchMhYWFRUUBgYjJSEyNzU0JiMhWgoB0FFXIiFXUv6+ATpNASIs/sYB/FAoTzvnPE8oYEf/HSkAAP//AFAAAAXWAkwAJgAn
AAAABwDPAxQAAP//AFAAAAXWAyECJgAoAAABBwEPA+QAjAAIsQMBsIywNSsAAP//AFAAAALqAyECJgAnAAABBwEPAnkAjAAIsQIB
sIywNSsAAP////4AAALqAkwCBgBDAAAAAgAKAAAC2QJxAAMABwAmQCMGAQIAAUwAAAIAhQACAgFfAwEBARUBTgAABQQAAwADEQQH
FyszATMBJSEDIwoBRUkBQf3mAWaxAgJx/Y9fAWIAAAD//wBQAAAFcwJMACYAJwAAAAcCeQMmAAD//wBQAAAFcwKVACYAJwAAAAcC
ewMmAAAAAQBQAAAC6gJMAA4ANUAyCwEFBAFMAAIAAwQCA2cAAQEAXwAAACJNAAQEBV8GAQUFIwVOAAAADgANEREREREHCBsrMxEh
FSEVIRUhFSEXFAYjUAJu/hYBdv6KAe4oNkICTGCKY59VBAcAAAD//wBQAAAC6gMmAiYALwAAAQcA4wL2AIwACLEBAbCMsDUrAAD/
/wBQAAAC6gMdAiYALwAAAQcBAgKNAIwACLEBAbCMsDUrAAD//wBQAAAC6gMhAiYALwAAAQcBDwJvAIwACLEBAbCMsDUrAAD//wBQ
AAAC6gMSAiYALwAAAQcBGQKTAIwACLEBAbCMsDUrAAD//wBQAAAC6gPYAiYALwAAAQcBGgKQAIwACLEBArCMsDUrAAD//wBQ/1cC
6gMSAiYALwAAACcBNgKK//YBBwEZApMAjAARsQEBuP/2sDUrsQIBsIywNSsA//8AUAAAAuoD2AImAC8AAAEHARsCkACMAAixAQKw
jLA1KwAA//8AUAAAAuoD/AImAC8AAAEHARwClwCMAAixAQKwjLA1KwAA//8AUAAAAuoDwAImAC8AAAEHAR0ClwCMAAixAQKwjLA1
KwAA//8AUAAAAuoDJgImAC8AAAEHASkCzgBuAAixAQKwbrA1KwAA//8AUAAAAuoC9gImAC8AAAEHAS8C4QBuAAixAQKwbrA1KwAA
//8AUAAAAuoC9gImAC8AAAEHATUCewCCAAixAQGwgrA1KwAA//8AUP9XAuoCTAImAC8AAAEHATYCiv/2AAmxAQG4//awNSsA//8A
UAAAAuoDJgImAC8AAAEHAXsCagCMAAixAQGwjLA1KwAA//8AUAAAAuoDSgImAC8AAAEHAYYCVgCCAAixAQGwgrA1KwAA//8AUAAA
AuoDCAImAC8AAAEHAQcCjQBQAAixAQGwULA1KwAA//8AUAAAAuoC2gImAC8AAAEHAbgCXwB4AAixAQGweLA1KwAAAAEAUP9QAuoC
TAAfAExASRMBAgQEAQEDAwEAAQNMAAIEBQQCBYAABQMEBQN+BgEEBCJNAAMDI00AAQEAYgcBAAAnAE4BABoZGBcVFBIREA8IBgAf
AR4ICBYrBSImJzcWFjMyNjU0JicBJyMRIxEnMwEXMxEzERQGBiMCOyVBEhUOLhkbIRkU/tMnCoQKkAFUJwuELkkrsBEKQgQJHB4Z
KhQBOS/+ZwH8UP6cNgGa/ZY3QBsA//8AUP9dAuoCTAImAC8AAAEHAd8DNAAUAAixAQGwFLA1KwAA/////gAAAuoCTAImACcAAAEH
AjsB6AA9AAixAgGwPbA1KwAA//8AUAAAAuoDDgImAC8AAAEHAkoCggCCAAixAQGwgrA1KwAAAAEAUAAAAsACTAAKAC9ALAEBAQAB
TAACAAMEAgNnAAEBAF8AAAAiTQUBBAQjBE4AAAAKAAoRERESBggaKzMRJyEVIRUhFSEVWgoCcP4eAXb+igH8UGCSY/cAAAAAAQBG
AAAC3wJNACUAP0A8HgEDBCIhAgADAkwABQAEAwUEZwACAgFfAAEBIk0AAwMAXwYBAAAjAE4BACAfHRwbFhIOCgcAJQEkBwgWKzMi
JiY1NTQ2MyEyFhUHJiYjIyIVFRQWMzMyNjc1Bwc1IREXFAYj/UdQIFZhAS1FSRQRp58zUCMtKWCEKzyDAUIKVGQoUDvfYFsPCFMD
B0f/IiUDAYgBCmL+5xUIDQAA//8ARgAAAt8DHQImAEYAAAEHAQICvwCMAAixAQGwjLA1KwAA//8ARgAAAt8DIQImAEYAAAEHAQ8C
oQCMAAixAQGwjLA1KwAA//8ARgAAAt8DEgImAEYAAAEHARkCxQCMAAixAQGwjLA1KwAA//8ARv7pAt8CTQImAEYAAAAHASECuQAA
//8ARgAAAt8C9gImAEYAAAEHATUCrQCCAAixAQGwgrA1KwAAAAEAUAAAAt8CsQAxAD5AOwkBBQAqAQQBAkwKAQUBSwAAAAUBAAVn
AAEABAMBBGcAAwMCXwcGAgICIwJOAAAAMQAxNDVENyQlCAgcKzMRND4CMzIWFxUHMzIWFRUUDgIjIyImNTcWFjMzMjYnNTYmIyci
JjU1NzUjIgYVEVAuUWo9X2sKaG9OQAUYNjHKREAoE2VMMh0UAQEWG6wPEFxOVUYBqE1nPBkVB1KtRzGeEiwoGgwIVwQHFROEFhQB
EQ0rwgNOVv5fAAAAAQBQAAAC4AJMAAsAJ0AkAAEABAMBBGcCAQAAIk0GBQIDAyMDTgAAAAsACxERERERBwgbKzMRMxUhNTMRIzUh
FVCEAYiEhP54Akz09P20+PgAAAD//wBQAAAC4AJMAiYATQAAAQcCOgLEANgACLEBAbDYsDUrAAD//wBQAAAC4AMSAiYATQAAAQcB
GQKYAIwACLEBAbCMsDUrAAAAAQBQAAAA1AJMAAMAGUAWAAAAIk0CAQEBIwFOAAAAAwADEQMIFyszETMRUIQCTP20AAAA//8AUAAA
A2oCTAAmAFAAAAAHAF8BJAAA//8AUAAAAQ8DJgImAFAAAAEHAOMB9QCMAAixAQGwjLA1KwAA/////AAAASgDHQImAFAAAAEHAQIB
jACMAAixAQGwjLA1KwAA//8AAgAAARsDEgImAFAAAAEHARkBkgCMAAixAQGwjLA1KwAA////xQAAAQUDJgImAFAAAAEHASkBzQBu
AAixAQKwbrA1KwAA//8ACAAAARwC9gImAFAAAAEHAS8B4ABuAAixAQKwbrA1KwAA//8AUAAAANQC9gImAFAAAAEHATUBegCCAAix
AQGwgrA1KwAA//8AUP9XANUCTAImAFAAAAEHATYBf//2AAmxAQG4//awNSsA//8AMwAAANQDJgImAFAAAAEHAXsBaQCMAAixAQGw
jLA1KwAA//8AKQAAAPsDSgImAFAAAAEHAYYBVQCCAAixAQGwgrA1KwAA/////AAAASgDCAImAFAAAAEHAQcBjABQAAixAQGwULA1
KwAA//8ACgAAARoC2gImAFAAAAEHAbgBXgB4AAixAQGweLA1KwAA//8APP9XAQcCTAImAFAAAAEHAd8BaAAOAAixAQGwDrA1KwAA
////5wAAAT0DDgImAFAAAAEHAkoBgQCCAAixAQGwgrA1KwAAAAEACgAAAkYCTAAUACxAKQ0FAgECBAEAAQJMAAICIk0AAQEAYAMB
AAAjAE4CAA8OCgcAFAITBAgWKyEiJiY1NxYWMzMyNjURJzMRFAYGIwEQSHdHMh1nVWAvHgiMGU1PBxIQTQ0JLRoBVVD+ZzJSL///
AAoAAAKDAxICJgBfAAABBwEZAvoAjAAIsQEBsIywNSsAAAABAFD/9gMUAkwALACAQAoNAQQDHwEBBAJMS7AYUFhAFgAEAAEABAFp
BQEDAyJNAgYCAAAjAE4bS7AyUFhAGgAEAAECBAFpBQEDAyJNAAICI00GAQAAIwBOG0AaAAQAAQIEAWkAAgIjTQYBAAADXwUBAwMi
AE5ZWUATAQAZGBIQDw4MCwoIACwBLAcIFisFIiYnJicuAiMjFSMRJzMRMzI2Nz4CNzMHDgMHFhYXFhYXHgIzBwYGAsMxSCMmNhk0
QTAvhAqOOBQaCxxIRRmiKRxAPjIMGy0hGS8fIz4rBhQDHgooIig0GiIS6gH8UP8ACgscVFkiPB1EQTELCRwbFCodIB4IUQMHAP//
AFD/LwMUAkwCJgBhAAABBwEhAnMARgAIsQEBsEawNSsAAAABAFAAAAKkAkwACQAmQCMGAQICAQFMAAAAIk0AAQECYAMBAgIjAk4A
AAAJAAgREgQIGCszNxEzESEXFAYjUAqEAZ4oNkJQAfz+FFUEBwAA//8AUAAABPQCTAAmAGMAAAAHAF8CrgAA//8AUAAAAqQDJgIm
AGMAAAEHAOMC2ACMAAixAQGwjLA1KwAA//8AUAAAAqQCjQImAGMAAAAHAQ4BcgAA//8AUP7pAqQCTAImAGMAAAAHASEChwAA//8A
UAAAAqQCTAAmAGMAAAEHAgEBGAAeAAixAQGwHrA1KwAA//8AUP9QA4UCgQAmAGMAAAAHAZ8CrgAA////8wAAAqQCTAImAGMAAAEH
AjcB5wCPAAixAQGwj7A1KwAAAAEAUAAAAzsCTAARADhANQEBAwAEAQQDAkwABAMCAwQCgAUBAwMAXwEBAAAiTQcGAgICIwJOAAAA
EQAREhIRERISCAgcKzMRJzMTEzMRIxEjBwcjJycjEVoKmOLqh4QLJ355figKAfxQ/nABkP20AXVX4uJX/osAAAEAUAAAAuoCTAAO
ADRAMQEBBAABTAAEAAEABAGAAAEDAAEDfgIBAAAiTQYFAgMDIwNOAAAADgAOEhEREhIHCBsrMxEnMwEXMxEzESMBJyMRWgqQAVQn
C4R//qQnCgH8UP6cNgGa/bQBai/+ZwAAAP//AFAAAAWAAkwAJgBsAAAABwBfAzoAAP//AFAAAALqAyYCJgBsAAABBwDjAwAAjAAI
sQEBsIywNSsAAP//AFAAAALqAyECJgBsAAABBwEPAnkAjAAIsQEBsIywNSsAAP//AFD+6QLqAkwCJgBsAAAABwEhApsAAAABAAr/
UAM8AkwAHQBIQEUMAQYCBQEBBQJMAAYCAwIGA4AAAwUCAwV+BAECAiJNAAUFI00AAQEAYgcBAAAnAE4BABgXFRQTEhEQDg0JBwAd
ARwICBYrFyImJjU3FhYzMjY1ESczARczETMRIwEnIxEUBgYjgR03IxQMLRkbIQqQAVQnC4R//qQnCi5JK7AJDgc8AwcaKAIaUP6c
NgGa/bQBai/+STdAG///AFD/UAQRAoEAJgBsAAAABwGfAzoAAP//AFAAAALqAw4CJgBsAAABBwJKAowAggAIsQEBsIKwNSsAAAAC
AEYAAALXAkwAEgAiAC1AKgADAwFfAAEBIk0FAQICAF8EAQAAIwBOFRMBAB0aEyIVIgsIABIBEQYIFiszIiYmNTU0NjYzITIWFhUV
FAYjJTMyNjU1NCYjIyIGFRUUFv1GUCEgUEcBJEZPIU5o/vnrJSkqJOskLCsoUDvnOk8pKU8651hbYCYh/x0pJiD/IiUAAAAAAgBG
AAAE7QJMAB4ALwBQQE0MAQMBHBcCAAYCTAAEAAUGBAVnCQEDAwFfAgEBASJNCwgCBgYAXwcKAgAAIwBOIR8BAConHy8hLxsZFhUU
ExIREA8ODQsIAB4BHQwIFiszIiYmNTU0NjYzMzIXNSEVIRUhFSEVIRcUBiMhNQYjJzMyNjY1NTQmIyMiBhUVFBb9RlAhIFBH1E8z
Am7+FgF2/ooB7ig2Qv3eNE63rzM9Gj1NryQsKyhQO+c6TykkJGCKY59VBAclJWAUNTCbRDQmIP8iJf//AEYAAALXAyYCJgB1AAAB
BwDjAvIAjAAIsQIBsIywNSsAAP//AEYAAALXAx0CJgB1AAABBwECAokAjAAIsQIBsIywNSsAAP//AEYAAALXAxICJgB1AAABBwEZ
Ao8AjAAIsQIBsIywNSsAAP//AEYAAALXA9gCJgB1AAABBwEaAowAjAAIsQICsIywNSsAAP//AEb/VwLXAxICJgB1AAAAJwE2Aob/
9gEHARkCjwCMABGxAgG4//awNSuxAwGwjLA1KwD//wBGAAAC1wPYAiYAdQAAAQcBGwKMAIwACLECArCMsDUrAAD//wBGAAAC1wP8
AiYAdQAAAQcBHAKTAIwACLECArCMsDUrAAD//wBGAAAC1wPAAiYAdQAAAQcBHQKTAIwACLECArCMsDUrAAD//wBGAAAC1wMmAiYA
dQAAAQcBKQLKAG4ACLECArBusDUrAAD//wBGAAAC1wL2AiYAdQAAAQcBLwLdAG4ACLECArBusDUrAAD//wBGAAAC1wNyAiYAdQAA
ACcBLwLdAG4BBwG4AlsBEAARsQICsG6wNSuxBAG4ARCwNSsA//8ARgAAAtcDcgImAHUAAAAnATUCdwCCAQcBuAJZARAAEbECAbCC
sDUrsQMBuAEQsDUrAP//AEb/VwLXAkwCJgB1AAABBwE2Aob/9gAJsQIBuP/2sDUrAP//AEYAAALXAyYCJgB1AAABBwF7AmYAjAAI
sQIBsIywNSsAAP//AEYAAALXA0oCJgB1AAABBwGGAlIAggAIsQIBsIKwNSsAAP//AEYAAANrAlgCJgB1AAABBwGHAp8AbgAIsQIB
sG6wNSsAAP//AEYAAANrAyYCJgCGAAABBwDjAvIAjAAIsQMBsIywNSsAAP//AEb/VwNrAlgCJgCGAAABBwE2Anz/9gAJsQMBuP/2
sDUrAP//AEYAAANrAyYCJgCGAAABBwF7AmYAjAAIsQMBsIywNSsAAP//AEYAAANrA0oCJgCGAAABBwGGAlIAggAIsQMBsIKwNSsA
AP//AEYAAANrAw4CJgCGAAABBwJKAn4AggAIsQMBsIKwNSsAAP//AEYAAALXAxwCJgB1AAABBwGJArYAjAAIsQICsIywNSsAAP//
AEYAAALXAwgCJgB1AAABBwEHAokAUAAIsQIBsFCwNSsAAP//AEYAAALXAtoCJgB1AAABBwG4AlsAeAAIsQIBsHiwNSsAAAABACgA
AANHAkwAQQA7QDgdCgUDAQUgBAIAAQJMAAUFAl8AAgIUTQMBAQEAXwQGAgAAFQBOAQAzMCUiHx4VEgkHAEEBQAcHFiszIiYmNTcW
FjMzNS4DNTU0NjMzMhYVFRQOAgcVMxcUBiMjIiY1NDY3NjY1NTQmIyMiBhUVFBYXHgIVFAYGI6wiPSUyDDgTbSlBLhhga/tpYRQq
QCzLKDZCfTpIKTMpJSok6iQsJCwlKhEVNC8HEhBNDAoUDiAyUkAqVmZmVipATjAhEhVVBAc2LiguHRc7MUwdKSYgTDI9FBAdJx8V
LiH//wBG/14C1wJMAiYAdQAAAQcB3wJgABUACLECAbAVsDUrAAD//wBG/9MC1wJvAiYAdQAAAQcCNgKaACMACLECAbAjsDUrAAD/
/wBG/9MC1wMmAiYAkQAAAQcA4wLoAIwACLEDAbCMsDUrAAD//wBGAAAC1wMOAiYAdQAAAQcCSgJ+AIIACLECAbCCsDUrAAD//wBG
AAAC1wOaAiYAdQAAACcCSgJ+AIIBBwG4AlsBOAARsQIBsIKwNSuxAwG4ATiwNSsAAAIAUAAAAsECTQATAB0ANUAyAQEEABIBAQMC
TAADAAECAwFnAAQEAF8AAAAiTQUBAgIjAk4AAB0bFhQAEwATSSIGCBgrMxEnITIeAhUVFA4CIyMiJicVESEyNjU1NCYjIVoKAbtA
SSMKDiZIOmY/bRsBEC0iIiz+7wH8USI3Phw7Fzk1IwYCvwEXLB8/ICwAAAIARv+YA04CTAAmADcAOkA3FAEAAwFMAAIAAoYABAQB
XwABASJNBgEDAwBhBQEAACMATiknAQAyLyc3KTcgHgsIACYBJgcIFiszIiYmNTU0NjYzITIWFhUVFAYHBgcWFhceAhcHBgYjIiYn
LgMnMzI2NjU1NCYjIyIGFRUUFv1GUCEgUEcBJEZPISUvHUYqSRshRTQGFgQiHStLLShDSF4nfENTJyok6yQsKyhQO+c6TykpTzqD
S1kfExsHDwUGCQUBVgEHEQ4NGhUNYB9PR5EdKSYg/yIlAAIAUP/2AzICTQAkADMArbULAQcDAUxLsBhQWEAkAAUBAAEFAIAJAQYE
AQEFBgFpAAcHA18AAwMiTQIIAgAAIwBOG0uwMlBYQCgABQECAQUCgAkBBgQBAQUGAWkABwcDXwADAyJNAAICI00IAQAAIwBOG0Ao
AAUBAgEFAoAIAQACAIYJAQYEAQEFBgFpAAcHA18AAwMiTQACAiMCTllZQBsnJQEAMC4lMycxIB8YFw4MCgkIBgAkASQKCBYrBSIm
JycmJiMjFSMRJyEyHgIVFRQOAgceAxceAjMHBgYBMjY3NjY1NTQmIyEVFhYCzyhNMUgsaU8fhAoBu0BJIwoMIj8zDSgrJAokOCQD
FAkq/okmPBgsIyIs/u8sSgoZMUgtKt8B/FEiNz4cExY2NCQDBx0iHAYVEAJRAwcBRAMCBScfFyAsrgMCAP//AFD/9gMyAyYCJgCX
AAABBwDjAuMAjAAIsQIBsIywNSsAAP//AFD/9gMyAyECJgCXAAABBwEPAlwAjAAIsQIBsIywNSsAAP//AFD+6QMyAk0CJgCXAAAA
BwEhApwAAP//AFD/9gMyAyYCJgCXAAABBwEpArsAbgAIsQICsG6wNSsAAP//AFD/9gMyAwgCJgCXAAABBwEHAnoAUAAIsQIBsFCw
NSsAAAABADwAAAK4AkwAMQBnS7AuUFhAHwAGAAIBBgJnBQEEBANfAAMDIk0AAQEAXwcBAAAjAE4bQCUABQMEBAVyAAYAAgEGAmcA
BAQDYAADAyJNAAEBAF8HAQAAIwBOWUAVAQAqJyIhIB4aFxEOCQUAMQEwCAgWKzMiJjU3FhYzMzI2NTU0JiMjIiY1NTQ2NjMhMhYV
ByYmIyciBgcVFBYzMzIWFhUVFAYjwERAKBe3oBMrJB0y6GVcIVBGARBEVBQauJsLLiABJSveQFowTV8MCFcEBx8lFCMeS1UQLEot
DghUAwcBJRwRISEaRUMQS1wAAP//ADwAAAK4AyYCJgCdAAABBwDjAucAjAAIsQEBsIywNSsAAP//ADwAAAK4AyECJgCdAAABBwEP
AmAAjAAIsQEBsIywNSsAAP//ADz/JAK4AkwCJgCdAAAABwEWAQsAAAACADIAAAKYAkwAIQArAENAQBEBAgMIAQUBAkwAAQAFBAEF
ZwACAgNhAAMDIk0HAQQEAF8GAQAAIwBOJCIBACgnIiskKxYSDwsHBAAhAR8ICBYrMyImNTUzMhYXNTQmIyMiBgcnNDYzMzIeAhUR
FAYHBgYjJzMyNjU1IRUUFsJMRPdTbygWGidtkhoLmLIyMjYXBSYmLXg4idIqMf6jGUc+ugMFjQ0bBwNWDgYfLi4P/uAxPRQYCGAj
Ny9VHBgAAP//ADwAAAK4AxICJgCdAAABBwEZAoQAjAAIsQEBsIywNSsAAP//ADz+6QK4AkwCJgCdAAAABwEhAngAAAABABQAAAKi
Ak0ABwAhQB4CAQAAAV8AAQEiTQQBAwMjA04AAAAHAAcREREFCBkrIQMhNSEVIREBGQH+/AKO/vsB7WBg/hMAAP//ABQAAAKiAk0C
JgCkAAABBwI7AnMAPQAIsQEBsD2wNSsAAP//ABQAAAKiAyECJgCkAAABBwEPAjcAjAAIsQEBsIywNSsAAP//ABT/JAKiAk0CJgCk
AAAABwEWAOMAAP//ABT+6QKiAk0CJgCkAAAABwEhAlAAAAACAFAAAALBAnUAFQAfADlANgEBAQAUAQIEAkwAAQAFBAEFZwAEAAID
BAJnAAAAJE0GAQMDIwNOAAAfHRgWABUAFUkhEgcIGSszESczFSEyHgIVFRQOAiMjIiYnFTUhMjY1NTQmIyFaCo4BXzI2FwUFGDYx
mD9tGwEvEh4fEf7RAiVQeBwqKw9uEiwoGgYCl+8UFF4UFAAAAAEAQf/2Ar0CTAAUAD5LsDJQWEASAwEBASJNAAICAGAEAQAAIwBO
G0APAAIEAQACAGQDAQEBIgFOWUAPAQAPDgsIBQQAFAETBQgWKxciJjURMxEUFjMzMjY1ETMRFAYGI+RbSIQuItQgMIQeRj4KYlEB
o/5ZLyAhLgGn/l02UC3//wBB//YCvQMcAiYAqgAAAQcA4wLkAIIACLEBAbCCsDUrAAD//wBB//YCvQMTAiYAqgAAAQcBAgJ7AIIA
CLEBAbCCsDUrAAD//wBB//YCvQMIAiYAqgAAAQcBGQKBAIIACLEBAbCCsDUrAAD//wBB//YCvQMcAiYAqgAAAQcBKQK8AGQACLEB
ArBksDUrAAD//wBB//YCvQLsAiYAqgAAAQcBLwLPAGQACLEBArBksDUrAAD//wBB/1cCvQJMAiYAqgAAAQcBNgJs//YACbEBAbj/
9rA1KwD//wBB//YCvQMcAiYAqgAAAQcBewJYAIIACLEBAbCCsDUrAAD//wBB//YCvQNAAiYAqgAAAQcBhgJEAHgACLEBAbB4sDUr
AAD//wBB//YDWwLQAiYAqgAAAQcBhwKPAOYACLEBAbDmsDUrAAD//wBB//YDWwMmAiYAswAAAQcA4wL7AIwACLECAbCMsDUrAAD/
/wBB/1cDWwLQAiYAswAAAQcBNgJx//YACbECAbj/9rA1KwD//wBB//YDWwMmAiYAswAAAQcBewJvAIwACLECAbCMsDUrAAD//wBB
//YDWwNKAiYAswAAAQcBhgJbAIIACLECAbCCsDUrAAD//wBB//YDWwMOAiYAswAAAQcCSgKHAIIACLECAbCCsDUrAAD//wBB//YC
vQMSAiYAqgAAAQcBiQKoAIIACLEBArCCsDUrAAD//wBB//YCvQL+AiYAqgAAAQcBBwJ7AEYACLEBAbBGsDUrAAD//wBB//YCvQLQ
AiYAqgAAAQcBuAJNAG4ACLEBAbBusDUrAAD//wBB/1ECvQJMAiYAqgAAAQcB3wJZAAgACLEBAbAIsDUrAAD//wBB//YCvQM7AiYA
qgAAAQcCHwJ1AIIACLEBArCCsDUrAAD//wBB//YCvQMEAiYAqgAAAQcCSgJwAHgACLEBAbB4sDUrAAAAAQAKAAAC1gJLAAoAIUAe
AgEAACJNAAEBA18EAQMDIwNOAAAACgAKEhIRBQgZKyEBMxMXMzcTMwcBASH+6Yy8GwkavogQ/vsCS/5rSEgBlTz98QAAAQAKAAAE
TQJLABYALUAqAAYGAF8EAgIAACJNAwEBAQVfCAcCBQUjBU4AAAAWABYSEhISEhIRCQgdKzMDMxMXMzcTMxMXMzcTMwcDIwMnIwcD
4deMjRcKDYWqixIKF4OMCs6qiBQKE4cCS/6AYUQBnf5jRGEBgDz98QGJQED+d///AAoAAARNAyYCJgDAAAABBwDjA48AjAAIsQEB
sIywNSsAAP//AAoAAARNAxICJgDAAAABBwEZAywAjAAIsQEBsIywNSsAAP//AAoAAARNAvYCJgDAAAABBwEvA3oAbgAIsQECsG6w
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
EBsUAgIDCwEFATcxAgAGA0wbS7AeUFhAEBsUAgIDCwELATcxAgAGA0wbQBAbFAICAwsBCwg3MQIABgNMWVlLsA5QWEAlCAEBCwEF
BgEFZwkBAgIDYQQBAwMlTQ0KAgYGAGEHDAIAACMAThtLsB5QWEAqAAsFAQtXCAEBAAUGAQVnCQECAgNhBAEDAyVNDQoCBgYAYQcM
AgAAIwBOG0ArAAEACwUBC2cACAAFBggFZwkBAgIDYQQBAwMlTQ0KAgYGAGEHDAIAACMATllZQCNHRQEAT0xFU0dTQ0A8OzUyLyoo
JCAdGRYSDgkFADoBOQ4IFiszIiY1NDYzMzIWFhc1NCYjIyIGByc2NjMzMhYXNjYzMzIWFhUVIyImJxUGMzMyNjY3FxQjIyImJwYG
IwEhNTQmJiMjIhUFMzI2NTU0JiMjIgYVFBa9TERHSTMyYUkORFAUSHEaDBFnWyAzViENNC3XQksfr1pxEwExMzZnVhooxcklMQ4x
ilABZQETCSw1eTD+gscdHzhLgBsVGEc+QUYEDg8lKy8HA08HChQVERgZOC+UCAE3KAMFAkEfDw0PDQECQBQQBCjsCBURGiIaHBwY
AAD//wAtAAAD7AKaAiYA5wAAAAcA4wN0AAD//wAtAAACVAKaAiYA0wAAAAcBewIxAAD//wAtAAACVAK+AiYA0wAAAQcBhgId//YA
CbECAbj/9rA1KwD//wAtAAACVAJ8AiYA0wAAAQcBBwJU/8QACbECAbj/xLA1KwD//wAtAAACVAJOAiYA0wAAAQcBuAIm/+wACbEC
Abj/7LA1KwAAAgBQ//YDEAJNAEUAVQFMS7AVUFhADxABBQM/NgIHCAMBAAYDTBtADxABBQM/NgIHCAMBAQYDTFlLsA5QWEA7AAME
BQQDcgAIBQcFCAeAAAYHAAcGAIAABAQCXwACAiJNAAUFAGEBCQIAACNNCgEHBwBhAQkCAAAjAE4bS7AVUFhAPAADBAUEAwWAAAgF
BwUIB4AABgcABwYAgAAEBAJfAAICIk0ABQUAYQEJAgAAI00KAQcHAGEBCQIAACMAThtLsDJQWEA5AAMEBQQDBYAACAUHBQgHgAAG
BwEHBgGAAAQEAl8AAgIiTQoBBwcBXwABASNNAAUFAGEJAQAAIwBOG0A2AAMEBQQDBYAACAUHBQgHgAAGBwEHBgGAAAUJAQAFAGUA
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
OIAAODY5ODZ+SgE2PDk2PH5LATw8hAAFAAMHBQNpAAAAAQkAAWkADAAJEAwJaRQBEBkeEFkqKCADGCsBHgoYHmkAGS0BFgQZFmlF
ASwAERcsEWlHL0YuKSUGFzFDJBwaQAYTJxcTaQA7Dzk7WUkBND8BDzA0D2lIQBMBMEQBJjkwJmkAOzs5YQA5OzlRG0uwDVBYQP8A
AgwDDAIDgAAHAwYDB3IABgEDBnAqKAIYGSIZGCKAACIeGSIefgAKHhYeChaAAAQWCxYEC4AfAQsdHgtwAB0sFh0sfgAVLBEsFRGA
ABIXCBcSCIA1QiMhPg4NPQgIExcIE34AJxM0Eyc0gAAzNDI0MzKAADIbNDIbfkEBGzs0Gzt+ADcwJjA3JoAAOjk4OTo4gAA4Njk4
Nn5KATY8OTY8fksBPDyEAAUAAwcFA2kAAAABCQABaQAMAAkQDAlpFAEQGR4QWSsBHgoZHlkgARktARYEGRZpRQEsABEXLBFpRy9G
LiklBhcxQyQcGkAGEycXE2kAOw85O1lJATQ/AQ9AGDA0D2lIATBEASY5MCZpADs7OWEAOTs5URtA/wACDAMMAgOAAAcDBgMHcgAG
AQMGcCooAhgZIhkYIoAAIh4ZIh5+AAoeFh4KFoAABBYLFgQLgB8BCx0WCx1+AB0sFh0sfgAVLBEsFRGAABIXCBcSCIA1QiMhPg4N
PQgIExcIE34AJxM0Eyc0gAAzNDI0MzKAADIbNDIbfkEBGzs0Gzt+ADcwJjA3JoAAOjk4OTo4gAA4Njk4Nn5KATY8OTY8fksBPDyE
AAUAAwcFA2kAAAABCQABaQAMAAkQDAlpFAEQGR4QWSsBHgoZHlkgARktARYEGRZpRQEsABEXLBFpRy9GLiklBhcxQyQcGkAGEycX
E2kAOw85O1lJATQ/AUAZDzA0D2lIATBEASY5MCZpADs7OWEAOTs5UVlZWVlBsQHmAeUBvQG8AbEBsAGXAZYBjQGMAXwBfAFvAW8B
SAFHAS8BLgEiASIA5QDlAMQAwwCRAJAAWABYAB8AHwHlAfUB5gH1Ad4B3AHYAdYB1QHTAdABzwHKAcgBvAHkAb0B5AG2AbUBsAG7
AbEBuwGrAakBqAGmAZ8BnQGWAa8BlwGvAYwBlQGNAZUBfAGLAXwBiwGEAYMBbwF7AW8BewF2AXQBZgFlAWIBYAFcAVsBTwFNAUcB
bgFIAW4BQQFAAS4BRgEvAUYBIgEtASIBLQEpAScBHwEdARkBFwERAQ8BDAELAQcBBgD+AP0A5QD8AOUA+wD1APMA7gDsAOkA6ADg
AN8A2QDYANIA0ADLAMkAwwDkAMQA5AC8ALoAtQCzAKoAqACQAMIAkQDCAFgAjwBYAI8AhgCFAH8AegBwAG4AawBqAGEAXgAfAFcA
HwBXABIANwBaAC4AOwA1ACcAKABMAAYAHisBIiYnJjY3NjYzMhYXFhYVFAYjIiYmNzYmIyMGBhUUATcRNDY3NSImIyIGBwYGBxQW
FxYWFw4CIyImNTQ2NzY2NzY2MzIWFjM3FhYGBwYGIyIuAiMRFyE3ETQ2NzUjIgYHBgYHFBYXFhYzFAYGIyImNTQ2NzY2NzY2MzIW
FhcVFxM3ERcjNxEjAwcDIxEXBSImNTQ2Njc2JicmJjU0NjcuAjU0NjY3FzIeAhUUBgcGBiMiBhUUFhYzMhYWFRQGBiUiJjU0NjYz
MhYXFhYVIyImNzcuAiMGBhUUFhYzNxUGBgU3ESc3FzY2MzIWFhUUBiMiJicVFAYGIyUiJjU0Njc+AjM1NCYmIxUGBiMiJicmJjc3
MzIWFRUXIyImJwU3EScyFjMyNjcRFwUiJjU0Njc2NjcWBgcGBhUUFhYzNxUOAgEiJiY1NDYzMhYXNiYnJiY1NTQ2NTMHFRQWMzI2
NxEzBxUUBgYHBgYBNjY1NCYjIgcVFBYWBTM2NjU0JiYjBgYHFR4CITI2NzUnBhUUFgEyNjY1NQYGIyIGFxYWFRQGIyImIyIGFRQW
JTI1NCYmIwYGFRQWASImJicmJicmNjc2NjMyFhYXFhYzNjYmIyIGIyM2Njc2MzIWFhUUBgYHIiY1NDc2NjMGFhcWFhcUBgcHBxcD
CCAkFDwhDhoNKCM4KSAkBwsGBRECGzUDHggcCRQyGxgyFxogBRsTDiYNAxYmGyk6ExMXDQkSPiw9nKVIlggDBggLKSwfUE89DRP2
PQgLBCkZOhQZIQUHEA0pDhEiHCsxERkXGQoRPi0dUlMfdoejFrIICFtKqQgVBLdabSErDgsDCxIbIAwQHRIeKxR7GzgwHh8WHFAs
IBsNKy02WzZAbAmrfoc9Yzk1YBcYCLYNBQY1BiImDg8gJ0AmeQlA/LsXCGQlETArNlczbl8cLw4bJhD200lEEhMXR1MoHy0VBxcO
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
MC8uJi0mLSknACUAJSQjIiEkIRURERERJRESCB8rFzciJjU1NDYzMzczBzM3MwcWFhcHJiYnAzY2NxcUBiMjByM3IwcnEyMiFRUU
FjMzEyYiI/UPaFZWYZURSRFDEUkRGicQFAUqJmBWZA0pVGRPD0gPRA8iYGFQJHVEYA8hEzw8UWLfYFtERERGAQsGVgEEAf54AgYC
VggNPDw8nAGNR/8iJQGLAQAAAAEAOv9wANoAhAAUAA9ADAcBAEkAAAB2LAEIFysXBiY3PgI3JiY1NDYzMhYVFA4CVhUHBwYVFAMa
GCEmKSkZKC6KBhcMCCQtFwQeHyMdIygdQDkn///+wv7p/0b/zQEPASD+kv9gNOUACbEAAbj/YLA1KwD///7YAfr/eAMOAQ8BIP+y
An7AAAAJsQABuAJ+sDUrAP//AFD/pgILAnkAJwIAAAAB9AAnAgABLP+mAQYCNVAAABKxAAG4AfSwNSuxAQG4/6awNSv//wBQAAAC
3gJMAC8BCwDbAJ0mygEGAmwoAAAIsQABsJ2wNSsAAgBQAEYCVwH7ACMAMwBnQB0UExEMCgkGAwAjHhwbAgEGAQICTBILAgBKHQEB
SUuwGFBYQBMEAQIAAQIBYwADAwBfAAAAJQNOG0AaAAAAAwIAA2kEAQIBAQJZBAECAgFfAAECAU9ZQA0mJC4rJDMmMz89BQgYKzcn
NyYmNTU0NjcnNxc2MzMyFzcXBxYWFRUUBgcXBycGIyMiJzczMjY1NTQmIyMiBhUVFBaFNTUODQwPNTUvKkNmQiovNTUODQ0ONTUv
KkJmQyqKLSUpKiQtJCwrRjUsFjwlBiU7Fiw1ORQUOTUsFjslBiU8Fiw1ORQUTCYhHh0pJiAeIiUAAgAyAAACTgJ6ABcAJQBBQD4P
AQUBFAEABAJMAAICJE0ABQUBYQABASVNBwEEBABhAwYCAAAjAE4aGAEAIh0YJRolExIREA4KABcBFggIFiszIi4CNTU0PgIzMzIW
FzUzESMnBgYjJzMyNjU1JiYjIyIVFRS2MjYXBQUXNzEzXHEeelInKnZNDNkVCiJoOzMwGigsEsAPKyocBwTF/YYUBw1WChTvAgUo
xCgAAAEAUP+wAfQCTAAPAC5AKwYBAgABAUwDAQEEAQAFAQBnBgEFBQJfAAICIgVOAAAADwAPISESERIHCBsrFxEHIzUzFzUzFTcz
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
//8AMgAAAkQCagImAToAAAEHATUCI//2AAmxAgG4//awNSsA//8AMv9XAkQBwAImAToAAAEHATYCKP/2AAmxAgG4//awNSsA//8A
MgAAAkQCmgImAToAAAAHAXsCEgAA//8AMgAAAkQCvgImAToAAAEHAYYB/v/2AAmxAgG4//awNSsAAAMAMgAAAoYCTAAfAC8APwBF
QEIYBwIFAgFMBwECAAUEAgVnAAMDAV8AAQEiTQgBBAQAXwYBAAAjAE4yMCIgAQA6NzA/Mj8qJyAvIi8RDgAfAR4JCBYrMyImNTU0
NjcmJjU1NDY2MzMyFhYVFRQGBxYWFRUUBiMDMzI2NTU0JiMjIgYVFRQWFzMyNjU1NCYjIyIGFRUUFulgVyUwHBsgUEerRk8hGh4w
JldfrHInJx4wci4iJQ2uJSkqJK4kLCtRWAsvShIOOiYLJ0QpKUQnCyU5EBJKLwtYUQFcICUFJSEeKAUlIPwiJRcgJiMjFyUi//8A
Gf/7AUMBIQEOAUoA+yAAAAmxAAO4//uwNSsAAAD//wAZAR0BQwJDAQ8BSgAAAR0gAAAJsQADuAEdsDUrAP//ADIAAAJEAnwCJgE6
AAABBwEHAjX/xAAJsQIBuP/EsDUrAP//AFAAAAJbAIIAJgIAAAAAJwIAAL4AAAAHAgABfAAA//8AMgAAAkQCTgImAToAAAEHAbgC
B//sAAmxAgG4/+ywNSsAAAEAUADcA3ABUAADAB5AGwAAAQEAVwAAAAFfAgEBAAFPAAAAAwADEQMIFys3NSEVUAMg3HR0AAAAAwAo
/9gCiAJ0ABkAIwAtAE9ATA4LAgQALCseHQQFBBgBAgIFA0wAAQABhQYBAwIDhgAAAAQFAARpBwEFAgIFWQcBBQUCYQACBQJRJSQA
ACQtJS0hHwAZABkoEigIBhkrFzcmJjU0PgIzMhc3MwcWFhUUDgIjIicHAxQWFxMmIyIGBhMyNjY1NCYnAxZaQjU/L1RuP0Y+H1o5
MTsvVG4/QTspQSwl8SwwP2k+5kBoPigi8CgoaSp8ST9uVC8eMlsqeUY/blQvGkIBWDVbHwGCEz5p/ts+aT8yVyD+gRAAAAABAFAA
3AJsAVAAAwAeQBsAAAEBAFcAAAABXwIBAQABTwAAAAMAAxEDCBcrNzUhFVACHNx0dAAAAAEAPP9QAlgBwAAlADxAORcBAgQFAQED
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
AQcBhgIH//YACbEDAbj/9rA1KwD//wAyAAAC2AKCAiYB4gAAAQcCSgIz//YACbEDAbj/9rA1KwD//wAyAAACTgKQAiYBzwAAAAcB
iQJnAAD//wAyAAACTgJ8AiYBzwAAAQcBBwI6/8QACbECAbj/xLA1KwD//wAyAAACTgJOAiYBzwAAAQcBuAIM/+wACbECAbj/7LA1
KwAAAQAUAAABFwJWAAUAGUAWBAIBAwBKAQEAACMATgAAAAUABQIIFiszEQcnJRGTeAcBAwHsCVUe/aoAAAD//wAKAAAAjAErAA4B
6wAAIAAAAP//ABQBHQCWAkgBDwHrAAoBHSAAAAmxAAG4AR2wNSsA//8AFP+wAzYCTAAmAe0AAAAnAXEA5QAAAAcBSwHzAAD//wAU
/7ADJwJMACYB7QAAACcBcQDlAAAABwJNAfMAAP//ABT/sANBAkwAJgHtAAAAJwFxAOUAAAAHAW4B8wAA//8AFADoAJYCEwEPAesA
CgDoIAAACLEAAbDosDUrAAD//wAy/2MCXAHAAiYBzwAAAQcB3wK9ABoACLECAbAasDUrAAD//wAtAUoBQAIqAQ8A0wAWAUogAAAJ
sQACuAFKsDUrAP//ADIBSgFAAioBDwHPABkBSiAAAAmxAAK4AUqwNSsA//8AMv+HAk4CIwImAc8AAAEHAjYCRv/XAAmxAgG4/9ew
NSsA//8AMv+HAk4CmgImAfUAAAAHAOMCmQAA//8AMgAAAk4CggImAc8AAAEHAkoCL//2AAmxAgG4//awNSsA//8AMgAAAk4DDgIm
Ac8AAAAnAkoCL//2AQcBuAIMAKwAEbECAbj/9rA1K7EDAbCssDUrAAACADz/RgJYAcAAFwAnAEJAPwMBBQAkAQQFFgECBANMAAUF
AGEBAQAAJU0HAQQEAmEAAgIjTQYBAwMnA04aGAAAIx8YJxonABcAF0lCEQgIGSsXETMXNjYzMzIeAhUVFA4CIyMiJicVEzMyNjU1
NiYjIyIGBxUUFjxSGS19UDMyNhcFBRc2MjNMdikf2RMdARcaMkBjIwm6AnoNBQgaKCwSwA8rKhwIBMYBEBQUxBYSBQPtFgkAAAAA
Af6z/0z/mQADABIAULEGZERLsApQWEAXAAIBAQJwAAEAAAFZAAEBAGIDAQABAFIbQBYAAgEChQABAAABWQABAQBiAwEAAQBSWUAN
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
ACcBcQFaAAAABwFuAmgAAP//ACgA6AFVAhMBDwJDABQA6CAAAAixAAGw6LA1KwAA//8AKAH9AX4CjAAHAkoBwgAAAAAAAf5mAf3/
vAKMAB4AM7EGZERAKAACAAEDAgFpAAMAAANZAAMDAGEEAQADAFEBABUTEA4GBAAeAR4FCBYrsQYARAMiLgIjIgYHBgYmNTQ2MzIe
AjMyNjc2NhYVFAYGqRwpIB8TGRMFBBQRMzEcJx8hFRcWBAQTEhUtAf4VHBUjDwwJDBIsQxUcFSMPDQkMExszIQAA//8AUAGbAgUC
TQAvAKQASgGbE1wBDwBrAQsBmxNcABKxAAG4AZuwNSuxAQG4AZuwNSsAAAABACgAAAJoAlcAKAAzQDAUAQABEwECAAEBAwIDTAAA
AAFhAAEBIk0AAgIDXwQBAwMjA04AAAAoACgrRU0FCBkrMzU+BDc2NjU1NCYjIyIGBgcnPgIzMzIeAhUVFAYHBgYHFSEVKBFFVVhL
FiAZKC4eOnRbFgocYoBGHD9MKQ5FTVRzGQGQYQssNjkzERkvFxQZIAgJA1sFDAgdLjcaFTVjKy4/DghgAP//ABQAAAE0ASwADgJM
AAAgAAAA//8AFAEdATQCSQEPAkwAAAEdIAAACbEAAbgBHbA1KwD//wAoAOgBSAIUAQ8CTAAUAOggAAAIsQABsOiwNSsAAAABADwA
AAJEAcAAFwAtQCoUAQACAUwDAQEBJU0AAgIAYgQFAgAAIwBOAQATEhEQDQoHBgAXARYGCBYrMyIuAjURMxEGFjMzMjY1ETMRIycG
BiPAMTcXBXoBHxLGFgh6UiYobUQaKCwSAUD+vhYSCBYBTP5AFAgMAP//ADwAAAJEApoCJgJQAAAABwDjAqMAAP//ADwAAAJEApEC
JgJQAAAABwECAjoAAP//ADwAAAJEAoYCJgJQAAAABwEZAkAAAP//ADwAAAJEApoCJgJQAAABBwEpAnv/4gAJsQECuP/isDUrAP//
ADwAAAJEAmoCJgJQAAABBwEvAo7/4gAJsQECuP/isDUrAP//ADz/VwJEAcACJgJQAAABBwE2Ai3/9gAJsQEBuP/2sDUrAP//ADwA
AAJEApoCJgJQAAAABwF7AhcAAP//ADwAAAJEAr4CJgJQAAABBwGGAgP/9gAJsQEBuP/2sDUrAP//ADwAAALYAkQCJgJQAAABBwGH
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
AAACTQHAAAwAMEAtBgEAAQkBAgMCAkwAAAABXwABASVNAAICA18EAQMDIwNOAAAADAALEhESBQgZKzM1ASE1IRUBIRcUBiMoAUP+
0QHq/rQBVR48RzwBLVc8/tJLBAcA//8AKAAAAk0CmgImAnkAAAAHAOMCngAA//8AKAAAAk0ClQImAnkAAAAHAQ8CFwAA//8AKAAA
Ak0CagImAnkAAAEHATUCI//2AAmxAQG4//awNSsAAAIAUAAAAqQCTAASACIALUAqAAMDAV8AAQEiTQUBAgIAXwQBAAAjAE4VEwEA
HRoTIhUiCwgAEgERBggWKyEiJiY1NTQ2NjMzMhYWFRUUBiMnMzI2NTU0JiMjIgYVFRQWAQdGUCEgUEfnRk8hTmjKriUpKiSuJCwr
KFA75zpPKSlPOudYW2AmIf8dKSYg/yIl//8AKAAAAVIBJgAOAn0AACAAAAD//wA3AR0BYQJDAQ8CfQAPAR0gAAAJsQACuAEdsDUr
AP//AFAAAAKkAkwAJgJ9AAABDwI3AwQAVk1xAAixAgGwVrA1K///AFAAAAKkAkwCJgJ9AAABDwI3Aw0AYU1xAAixAgGwYbA1KwAA
AAwAlgADAAEECQAAAKIAAAADAAEECQABAA4AogADAAEECQACAA4AsAADAAEECQADADQAvgADAAEECQAEAB4A8gADAAEECQAFAEYB
EAADAAEECQAGAB4BVgADAAEECQAJAB4BdAADAAEECQALABgBkgADAAEECQAMAB4BqgADAAEECQANASIByAADAAEECQAOADYC6gBD
AG8AcAB5AHIAaQBnAGgAdAAgADIAMAAxADgAIABUAGgAZQAgAEcAbwBsAGQAbQBhAG4AIABQAHIAbwBqAGUAYwB0ACAAQQB1AHQA
aABvAHIAcwAgACgAaAB0AHQAcABzADoALwAvAGcAaQB0AGgAdQBiAC4AYwBvAG0ALwBtAGEAZwBpAGMAdAB5AHAAZQAvAGcAbwBs
AGQAbQBhAG4AKQBHAG8AbABkAG0AYQBuAFIAZQBnAHUAbABhAHIAMQAuADAAMAAwADsATgBPAE4ARQA7AEcAbwBsAGQAbQBhAG4A
LQBSAGUAZwB1AGwAYQByAEcAbwBsAGQAbQBhAG4AIABSAGUAZwB1AGwAYQByAFYAZQByAHMAaQBvAG4AIAAxAC4AMAAwADAAOwAg
AHQAdABmAGEAdQB0AG8AaABpAG4AdAAgACgAdgAxAC4AOAAuADMAKQBHAG8AbABkAG0AYQBuAC0AUgBlAGcAdQBsAGEAcgBKAGEA
aQBrAGkAcwBoAGEAbgAgAFAAYQB0AGUAbABtAGEAZwBpAGMAdAB5AHAAZQAuAGkAbgBoAHQAdABwADoALwAvAGoAYQBpAGsAaQAu
AGkAbgBUAGgAaQBzACAARgBvAG4AdAAgAFMAbwBmAHQAdwBhAHIAZQAgAGkAcwAgAGwAaQBjAGUAbgBzAGUAZAAgAHUAbgBkAGUA
cgAgAHQAaABlACAAUwBJAEwAIABPAHAAZQBuACAARgBvAG4AdAAgAEwAaQBjAGUAbgBzAGUALAAgAFYAZQByAHMAaQBvAG4AIAAx
AC4AMQAuACAAVABoAGkAcwAgAGwAaQBjAGUAbgBzAGUAIABpAHMAIABhAHYAYQBpAGwAYQBiAGwAZQAgAHcAaQB0AGgAIABhACAA
RgBBAFEAIABhAHQAOgAgAGgAdAB0AHAAcwA6AC8ALwBzAGMAcgBpAHAAdABzAC4AcwBpAGwALgBvAHIAZwAvAE8ARgBMAGgAdAB0
AHAAcwA6AC8ALwBzAGMAcgBpAHAAdABzAC4AcwBpAGwALgBvAHIAZwAvAE8ARgBMAAAAAgAAAAAAAP+cADIAAAAAAAAAAAAAAAAA
AAAAAAAAAAKCAAAAAQECAAMAJAEDAJABBADJAQUBBgEHAQgBCQEKAMcBCwEMAQ0BDgEPARAAYgERAK0BEgETARQBFQBjARYArgAl
ACYA/QD/AGQBFwEYACcBGQEaARsBHAEdAR4BHwAoAGUBIAEhAMgBIgEjASQBJQEmAScAygEoASkAywEqASsBLAEtAS4A6QEvACkA
KgD4ATABMQEyATMBNAArATUBNgAsATcAzAE4AM0BOQDOAPoBOgDPATsBPAE9AT4BPwAtAUAALgFBAC8BQgFDAUQBRQFGAUcA4gAw
ADEBSAFJAUoBSwFMAU0BTgBmADIAsADQAU8A0QFQAVEBUgFTAVQBVQBnAVYBVwFYANMBWQFaAVsBXAFdAV4BXwFgAWEBYgFjAWQA
kQFlAK8BZgAzADQANQFnAWgBaQFqAWsANgFsAOQA+wFtAW4BbwA3AXABcQFyAXMA7QA4ANQBdADVAXUAaAF2ANYBdwF4AXkBegF7
AXwBfQF+AX8BgAGBAYIBgwA5ADoBhAGFAYYBhwA7ADwA6wGIALsBiQGKAYsBjAGNAD0BjgDmAY8ARAGQAGkBkQGSAZMBlAGVAZYA
awGXAZgBmQGaAZsAjQGcAZ0AbAGeAKABnwBqAaABoQGiAAkBowGkAaUApwBuAaYAQQBhAA0AIwBtAEUAPwBfAF4AYAA+AEAA2wGn
AagBqQGqAasBrAGtAOgAhwGuAEYA/gDhAa8BsAEAAG8BsQGyAbMA3gG0AIQA2AG1AbYBtwG4AbkAHQG6AA8BuwG8Ab0AiwC9AEcA
ggDCAb4BvwEBAIMAjgHAAcEAuAHCAAcBwwDcAcQBxQHGAccByABIAHAByQHKAHIBywHMAc0BzgHPAdAAcwHRAdIAcQHTABsB1AHV
AdYAqwHXALMB2ACyAdkB2gAgAdsA6gHcAd0ABACjAEkB3gHfAeAB4QHiAeMB5AHlAMAB5gAYAecB6AHpAMEApgAXAeoB6wHsALwA
9wBKAPkB7QHuAe8B8ACJAEMB8QAhAJUB8gCpAKoAvgC/AEsB8wH0AfUB9gDfAfcAEAH4AEwB+QB0AfoAdgH7AHcB/AH9ANcAdQH+
Af8CAAIBAJIAnAICAgMATQIEAgUATgIGAgcCCABPAgkCCgILAgwCDQAfAJQCDgIPAhACEQCkALkA4wBQANoCEgITAhQCFQDvAhYC
FwDwAFECGAIZAhoCGwIcAh0AHAIeAh8CIAACAI8AeAAGAiEAUgB5AiIAewIjAiQCJQImAicCKAB8AikCKgIrALEA4AIsAHoCLQIu
Ai8CMAIxAjICMwI0AjUCNgAUAjcCOAI5APQA9QI6AjsAnQCeAKECPAB9Aj0AUwI+AIgACwAMAJgACAARAMMCPwDGAkACQQCbAA4A
kwJCAJoAVAAiAKIABQDFALQAtQC2ALcAxAAKAFUCQwClAkQCRQJGAIoCRwDdAkgCSQJKAksCTABWAk0A5QD8Ak4CTwJQAlEAhgAe
ABoCUgJTAlQAGQJVAlYAEgJXAlgCWQCFAloCWwCZAFcCXAJdAl4CXwDuABYCYAJhAmIA9gJjANkCZACMABUCZQJmAmcAWAB+AmgA
gAJpAIECagB/AmsCbAJtAm4CbwJwAnECcgJzAnQAQgJ1AnYCdwBZAFoCeAJ5AnoCewJ8An0AWwBcAOwCfgC6An8AlgKAAoECggKD
AF0ChADnAoUAEwKGAocCiAKJAkNSBUEuYWx0B0FFYWN1dGUGQWJyZXZlB3VuaTFFQUUHdW5pMUVCNgd1bmkxRUIwB3VuaTFFQjIH
dW5pMUVCNAd1bmkxRUE0B3VuaTFFQUMHdW5pMUVBNgd1bmkxRUE4B3VuaTFFQUEHdW5pMDIwMAd1bmkxRUEwB3VuaTFFQTIHdW5p
MDIwMgdBbWFjcm9uB0FvZ29uZWsKQXJpbmdhY3V0ZQtDY2lyY3VtZmxleApDZG90YWNjZW50B3VuaTAxRjEHdW5pMDFDNAZEY2Fy
b24GRGNyb2F0B3VuaTAzOTQHdW5pMDFGMgd1bmkwMUM1BkVicmV2ZQZFY2Fyb24HdW5pMUVCRQd1bmkxRUM2B3VuaTFFQzAHdW5p
MUVDMgd1bmkxRUM0B3VuaTAyMDQKRWRvdGFjY2VudAd1bmkxRUI4B3VuaTFFQkEHdW5pMDIwNgdFbWFjcm9uA0VuZwdFb2dvbmVr
B3VuaTFFQkMGR2Nhcm9uC0djaXJjdW1mbGV4B3VuaTAxMjIKR2RvdGFjY2VudAd1bmkxRTlFBEhiYXILSGNpcmN1bWZsZXgCSUoG
SWJyZXZlB3VuaTAyMDgHdW5pMUVDQQd1bmkxRUM4B3VuaTAyMEEHSW1hY3JvbgdJb2dvbmVrBkl0aWxkZQtKY2lyY3VtZmxleAd1
bmkwMTM2B3VuaTAxQzcGTGFjdXRlBkxjYXJvbgd1bmkwMTNCBExkb3QHdW5pMDFDOAd1bmkwMUNBBE5VTEwGTmFjdXRlBk5jYXJv
bgd1bmkwMTQ1B3VuaTAxOUQHdW5pMDFDQgZPYnJldmUHdW5pMUVEMAd1bmkxRUQ4B3VuaTFFRDIHdW5pMUVENAd1bmkxRUQ2B3Vu
aTAyMEMHdW5pMDIyQQd1bmkwMjMwB3VuaTFFQ0MHdW5pMUVDRQVPaG9ybgd1bmkxRURBB3VuaTFFRTIHdW5pMUVEQwd1bmkxRURF
B3VuaTFFRTANT2h1bmdhcnVtbGF1dAd1bmkwMjBFB09tYWNyb24HdW5pMDNBOQd1bmkwMUVBC09zbGFzaGFjdXRlB3VuaTAyMkMG
UmFjdXRlBlJjYXJvbgd1bmkwMTU2B3VuaTAyMTAHdW5pMDIxMgZTYWN1dGUHdW5pMDE4RgtTY2lyY3VtZmxleAd1bmkwMjE4BFRi
YXIGVGNhcm9uB3VuaTAxNjIHdW5pMDIxQQZVYnJldmUHdW5pMDIxNAd1bmkxRUU0B3VuaTFFRTYFVWhvcm4HdW5pMUVFOAd1bmkx
RUYwB3VuaTFFRUEHdW5pMUVFQwd1bmkxRUVFDVVodW5nYXJ1bWxhdXQHdW5pMDIxNgdVbWFjcm9uB1VvZ29uZWsFVXJpbmcGVXRp
bGRlBldhY3V0ZQtXY2lyY3VtZmxleAlXZGllcmVzaXMGV2dyYXZlC1ljaXJjdW1mbGV4B3VuaTFFRjQGWWdyYXZlB3VuaTFFRjYH
dW5pMDIzMgd1bmkxRUY4BlphY3V0ZQpaZG90YWNjZW50BWEuYWx0BmFicmV2ZQd1bmkxRUFGB3VuaTFFQjcHdW5pMUVCMQd1bmkx
RUIzB3VuaTFFQjUHdW5pMUVBNQd1bmkxRUFEB3VuaTFFQTcHdW5pMUVBOQd1bmkxRUFCCWFjdXRlY29tYgd1bmkwMjAxB3VuaTFF
QTEHYWVhY3V0ZQd1bmkxRUEzB3VuaTAyMDMHYW1hY3Jvbgdhb2dvbmVrB3VuaTAyQkMHdW5pRjhGRgphcmluZ2FjdXRlB3VuaTAz
MkUHdW5pMDMwNgt1bmkwMzA2MDMwMQt1bmkwMzA2MDMwMAt1bmkwMzA2MDMwOQt1bmkwMzA2MDMwMwd1bmkwMzExB3VuaTIyMTkJ
Y2Fyb24uYWx0B3VuaTAzMEMLY2NpcmN1bWZsZXgKY2RvdGFjY2VudAd1bmkyMEI1B3VuaTAzMjcHdW5pMDMwMgt1bmkwMzAyMDMw
MQt1bmkwMzAyMDMwMAt1bmkwMzAyMDMwOQt1bmkwMzAyMDMwMw1jb2xvbm1vbmV0YXJ5B3VuaTAzMjYHdW5pMDMxMgd1bmkyMDUy
B3VuaTAzMEYGZGNhcm9uB3VuaTAzMjQHdW5pMDMwOAd1bmkyMjE1BGRvbmcHdW5pMDMwNwxkb3RiZWxvd2NvbWIHdW5pMDJCQQd1
bmkwMUYzB3VuaTAxQzYGZWJyZXZlBmVjYXJvbgd1bmkxRUJGB3VuaTFFQzcHdW5pMUVDMQd1bmkxRUMzB3VuaTFFQzUHdW5pMDIw
NQplZG90YWNjZW50B3VuaTFFQjkHdW5pMUVCQgplaWdodC5kbm9tCmVpZ2h0Lm51bXIHdW5pMDIwNwdlbWFjcm9uCGVtcHR5c2V0
A2VuZwdlb2dvbmVrCWVzdGltYXRlZAd1bmkxRUJEBEV1cm8DZl9mBWZfZl9pBmZfZl9pagVmX2ZfbANmX2kEZl9pagdmX2pvaW50
A2ZfbAd1bmkwMkM5CWZpdmUuZG5vbQlmaXZlLm51bXILZml2ZWVpZ2h0aHMJZm91ci5kbm9tCWZvdXIubnVtcgd1bmkyMDc0Bmdj
YXJvbgtnY2lyY3VtZmxleAd1bmkwMTIzCmdkb3RhY2NlbnQJZ3JhdmVjb21iB3VuaTIwQjIEaGJhcgtoY2lyY3VtZmxleA1ob29r
YWJvdmVjb21iB3VuaTAzMUIHdW5pMDMwQgd1bmkyMDEwBWkuVFJLBmlicmV2ZQd1bmkwMjA5CWkubG9jbFRSSwd1bmkxRUNCB3Vu
aTFFQzkHdW5pMDIwQgJpagdpbWFjcm9uB2lvZ29uZWsGaXRpbGRlC2pjaXJjdW1mbGV4B3VuaTAyMzcHdW5pMDEzNwxrZ3JlZW5s
YW5kaWMHdW5pMjBBRAZsYWN1dGUGbGNhcm9uB3VuaTAxM0MEbGRvdAd1bmkyN0U4BGxpcmEHdW5pMjBCQQd1bmkyMTEzB3VuaTAx
QzkHdW5pMDMzMQd1bmkwMzA0B3VuaTIwQkMHdW5pMDBCNQZtaW51dGUHdW5pMDNCQwZuYWN1dGUHdW5pMjBBNgd1bmkwMEEwBm5j
YXJvbgd1bmkwMTQ2B3VuaTAyNzIJbmluZS5kbm9tCW5pbmUubnVtcgd1bmkwMUNDB3VuaTIxMTYGb2JyZXZlB3VuaTFFRDEHdW5p
MUVEOQd1bmkxRUQzB3VuaTFFRDUHdW5pMUVENwd1bmkwMjBEB3VuaTAyMkIHdW5pMDIzMQd1bmkxRUNEB3VuaTAzMjgHdW5pMUVD
RgVvaG9ybgd1bmkxRURCB3VuaTFFRTMHdW5pMUVERAd1bmkxRURGB3VuaTFFRTENb2h1bmdhcnVtbGF1dAd1bmkwMjBGB29tYWNy
b24Ib25lLmRub20Ib25lLm51bXIJb25lZWlnaHRoB3VuaTAwQjkHdW5pMDFFQgtvc2xhc2hhY3V0ZQd1bmkwMjJEB3VuaTAzMjEW
cGVyaW9kY2VudGVyZWQubG9jbENBVAZwZXNldGEHdW5pMjBCMQd1bmkwMkI5BnJhY3V0ZQZyY2Fyb24HdW5pMDE1Nwd1bmkwMjEx
B3VuaTI3RTkHdW5pMDMwQQd1bmkwMjEzB3VuaTIwQkQHdW5pMjBBOAd1bmkyMEI5BnNhY3V0ZQd1bmkwMjU5C3NjaXJjdW1mbGV4
B3VuaTAyMTkGc2Vjb25kCnNldmVuLmRub20Kc2V2ZW4ubnVtcgxzZXZlbmVpZ2h0aHMIc2l4LmRub20Ic2l4Lm51bXIHdW5pMDMz
OAd1bmkwMzM3B3VuaTAwQUQHdW5pMDMzNgd1bmkwMzM1BHRiYXIGdGNhcm9uB3VuaTAxNjMHdW5pMDIxQgp0aHJlZS5kbm9tCnRo
cmVlLm51bXIMdGhyZWVlaWdodGhzB3VuaTAwQjMJdGlsZGVjb21iCHR3by5kbm9tCHR3by5udW1yB3VuaTAwQjIGdWJyZXZlB3Vu
aTAyMTUHdW5pMUVFNQd1bmkxRUU3BXVob3JuB3VuaTFFRTkHdW5pMUVGMQd1bmkxRUVCB3VuaTFFRUQHdW5pMUVFRg11aHVuZ2Fy
dW1sYXV0B3VuaTAyMTcHdW1hY3Jvbgd1b2dvbmVrBXVyaW5nBnV0aWxkZQZ3YWN1dGULd2NpcmN1bWZsZXgJd2RpZXJlc2lzBndn
cmF2ZQZjaXJjbGUHdW5pMjBBOQt5Y2lyY3VtZmxleAd1bmkxRUY1BnlncmF2ZQd1bmkxRUY3B3VuaTAyMzMHdW5pMUVGOQZ6YWN1
dGUKemRvdGFjY2VudAl6ZXJvLmRub20JemVyby5udW1yCXplcm8uemVybwl6ZXJvc2xhc2gAAAABAAH//wAPAAEAAgAOAAAAAAAA
AdQAAgBLAAQABAABAAYAKwABAC0AQAABAEIASwABAE0AbQABAG8AcQABAHMAjgABAJAAoAABAKIAqAABAKoA0wABANUA4QABAOMA
4wADAOQA7AABAO4A7gABAPIA8wABAPgA+QABAQEBBwADAQsBDAABAQ8BDwADARABEwABARYBFgADARkBHQADASEBIgADASQBJAAB
ASYBJgABASkBKQADASoBKwABAS4BLwADATUBNgADATgBSQABAU0BTQABAU8BTwABAVQBVAABAVgBWAABAVwBXAABAV0BXQACAXMB
eAABAXsBewADAYMBhQABAYYBhwADAYkBiQADAYwBmgABAZ0BngABAaABowABAaYBqgABAbEBsQABAbQBtQABAbcBuAADAboBugAB
Ab0BvQABAb8BwAABAcMBxAABAckByQABAcwBzAABAc4B3QABAd8B3wADAeAB6gABAfIB+QABAfoB+gADAgsCCwABAhYCFwABAhkC
HAABAh8CHwADAiACIAABAiQCJwABAikCKgABAjYCNwADAjoCOwADAj0CQQABAkoCSgADAksCSwABAlACYQABAmMCawABAm4CcwAB
AnUCfAABAAEAAwAAABAAAAAiAAAAVAABAAcBAQEWASEBLgE2AbcB+gABABcA4wECAQMBBAEFAQYBBwEPARkBGgEbARwBHQEiASkB
LwE1AXsBhgGJAbgCHwJKAAEAAQGHAAAAAQAAAAoAIgBOAAFERkxUAAgABAAAAAD//wADAAAAAQACAANrZXJuABRtYXJrABxta21r
ACIAAAACAAAAAQAAAAEAAgAAAAMAAwAEAAUABgAOD+IRwiyeLUgvCAACAAgAAgAKADYAAQAMAAQAAAABABIAAQABAGYABgCk/84A
pf/OAKb/zgCn/84AqP/OAL//zgACCi4ABAAAC1gNMAAjACUAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAD/3QAAAAAAAAAAAAAAAP/u
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/s/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/
xAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/E
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAAAAAAD/nAAAAAAAAP+m/4gAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/5UAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/2AAAAAD/xAAA
/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9gAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/6b/4v+I/5z/2AAAAAAAAAAAAAAAAP/E/7D/7AAAAAAAAAAAAAAAAAAA
/9gAAAAAAAAAAP/s/8T/7P/EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/+wA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/2AAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7P/EAAAAAAAA/9j/2AAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAD/ugAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/3QAAAAAAAD/dP9gAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAD/nP+IAAAAAAAAAAD/5P/OAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/2AAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/YAAD/sP/Y/+wAAP/sAAAAAP/sAAD/2AAAAAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAA
AAD/7P/s/+z/xAAAAAAAAAAAAAAAAAAA/9gAAP+I/7D/7AAA/+wAAAAA/+wAAP/YAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/
xP/s/8T/7P/E/8QAAAAA/+wAAAAAAAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAP+wAAAAAAAAAAD/dAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/xAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAP/YAAAAAP+w/+z/7P/s/8T/xAAAAAAAAP/OAAAAAAAA/8QAAAAo/+wAAAAAAAD/sAAA/8QAAAAA
AAAAAAAAACgAAAAAAAAAAAAA/+wAAAAAAAAAAAAeAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADwAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAP/vAAAAAAAAAAAAAAAAAAAAAP/EAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/xAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAAAA/8QAAAAAAAD/xP/EAAAAAAAAAAAAAAAA/8QAAAAAAAAAAAAAAAAAAAAA
AAAAAP/EAAAAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAD/7AAAAAAAAP/s/+wAAAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAAAAAAAA
AAAA/+wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP/sAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP+wAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAD/7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAD/2P/s/5X/2P/s/+z/7AAAAAD/7AAA/9j/2AAAAAAAAP/YAAAAAP/sAAAAAAAAAAAAAAAA/8T/xP/E/8QAAAAAAAAA
AAAAAAAAAAAAAAD/xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAA/9MAAP+w/8T/7AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD/7AAAAAAAAAAA/7AAAAAAAAAA
AAAA/84AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAIAMQAEAB8AAAAnACwAHAAvAEAAIgBCAEUANABRAFEAOABfAGgAOQBqAGoAQwBtAG0ARAB1AI4ARQCQAKgAXwC/ANMAeADVAOEA
jQDkAOwAmgDuAO8AowDyAPMApQD4APkApwEqASoAqQE6AUkAqgFNAU0AugFPAU8AuwFUAVQAvAFYAVgAvQFcAV0AvgFhAWEAwAFl
AWUAwQFtAW0AwgF5AXkAwwF/AYUAxAGMAYwAywGUAZQAzAGiAaQAzQGoAagA0AG1AbUA0QG/AcAA0gHDAcQA1AHMAcwA1gHPAd0A
1wHgAeoA5gHyAfIA8QH1AfkA8gIQAhAA9wISAhMA+AIWAhcA+gIZAhsA/AIgAiAA/wIkAicBAAIpAioBBAJCAkIBBgJmAmsBBwAC
AE4ABAAEAAMABQAFACIABgAHAAUACAAfAAMAKAApAAwALAAsAAMALwBAAAUAQgBCAAUARABEAAUARQBFACEAUQBRABAAXwBgABAA
YQBiABYAYwBjAAsAZABkABAAZQBoAAsAagBqAAsAbQBtABAAdgB2AAUAlQCVACAAlwCcAAoAnQCgAAkAogCjAAkApACoAA8AvwC/
AB8AwADEAA4AxQDFAB4AxgDOAAYAzwDSAAwA0wDTAAEA1QDhAAEA5ADmAAEA5wDoAAQA6QDsAAEA7gDuAAEA7wDvABEA8gDzAAEA
+AD4AAEA+QD5AAIBKgEqABUBOgFJAAQBTQFNAAQBTwFPAAQBVAFUAAQBWAFYAAQBXAFdABQBYQFhABIBZQFlABIBbQFtAB0BeQF5
ABwBfwF/ABsBgAGAABoBgQGBABkBggGCABgBgwGFAAEBjAGMABIBlAGUABIBogGkABMBqAGoABUBtQG1AAEBvwHAAAEBwwHEAAEB
zAHMAAEBzwHcAAIB3QHdAAQB4AHqAAIB8gHyAAIB9QH5AAICEAIQABECEgITABECFgIXAAgCGQIbAAgCIAIgAAgCJAInAAcCKQIq
AAcCQgJCAAICZgJmABcCZwJrAA0AAgBnAAQABAAEAAUABQAkAAYAHwAEACAAIAABACEAJgADACcAKwABACwALAAEAC0AQAABAEIA
RQABAEYASwADAE0AXgABAF8AYAAYAGEAagABAGwAbQABAG8AcQABAHMAdAABAHUAjgADAJAAlAADAJUAlQABAJYAlgADAJcAnAAB
AKEAoQADAKQAqAARAKkAqQABAL8AvwAjAMAAxAAQAMUAxQAiAMYAzgAMAM8A0gATANMA0wAFANUA4QAFAOQA7AAFAO4A7gAFAO8A
7wAWAPIA8wAFAPYA9gAhAPgA+AAFAPkA+QAHAQsBDAACARABEwACARcBFwACASYBJgACASsBKwACATgBSQACAU0BTQACAU8BTwAC
AVMBUwAIAVQBVAACAVgBWAACAVwBYQAKAWMBZQAKAWsBawAKAW0BbQAgAXMBeAAOAXkBeQAHAX8BfwAfAYABgAAeAYEBgQAdAYIB
ggAcAYMBhQAHAYwBjAAVAY0BkwAJAZQBlAAVAZUBmAAJAZkBmQAVAZoBmgAJAZ0BngAJAZ8BnwAbAaIBpAAHAaYBpwAHAakBqgAH
AbEBsQAHAbQBtAAHAbUBtQAIAb0BvQAXAb8BwAAIAcMBxAAIAckByQAIAcwBzAAIAc4BzgABAc8B3QACAeAB6gACAfIB8gACAfUB
+AACAfkB+QAXAgsCCwACAhACEAAUAhECEQAWAhICEwAUAhYCFwAIAhkCGwAIAiACIAAIAiQCJwANAikCKgANAi4CLgAaAjUCNQAZ
Aj0CQQAPAkICQgAHAlACYQAGAmMCZQAGAm8CcwALAnUCeAALAnkCfAASAAIAAAABAAgAAgCsAAQAAAEuAYwADQAGAAAAAP90/7D/
dP+wAAD/xAAAAAAAAAAAAAD/dAAAAAAAAAAAAAD/xAAAAAAAAAAAAAD/xAAAAAAAAAAAAAD/sAAAAAAAAAAAAAD/sAAAAAAAAAAA
AAD/sAAAAAAAAAAAAAD/xAAAAAAAAAAAAAD/iAAAAAAAAAAAAAD/sAAAAAAAAAAAAAD/xAAAAAAAAAAAAAD/xAAAAAAAAAAAAAEA
PwBFAJUApAClAKYApwCoAL8AwADBAMIAwwDEAMYAxwDIAMkAygDLAMwAzQDOAR4BIAEhASMBLQEuAS8BNAE1ATYBTgFcAV0CAAIB
AgICDwIUAhYCFwIZAhoCGwIgAi0CLgJmAmcCaAJpAmoCawJvAnACcQJyAnMCdQJ2AncCeAACAA8ARQBFAAwAlQCVAAsApACoAAYA
vwC/AAoAwADEAAUAxgDOAAIBXAFdAAcCFgIXAAMCGQIbAAMCIAIgAAMCLgIuAAkCZgJmAAgCZwJrAAQCbwJzAAECdQJ4AAEAAgAM
AKQAqAAEAL8AvwAFAMAAxAADAMYAzgACAR4BHgABASABIAABASMBIwABAS8BLwABATUBNgABAU4BTgABAgACAQABAi0CLQABAAQA
AAABAAgAAQAMAFgABQGmAlYAAQAkAOMBAQECAQMBBAEFAQYBBwEPARYBGQEaARsBHAEdASEBIgEpAS4BLwE1ATYBewGGAYcBiQG3
AbgB3wH6Ah8CNgI3AjoCOwJKAAIANwAEAAQAAAAGACsAAQAtAEAAJwBCAEsAOwBNAGwARQBvAHEAZQBzAI4AaACQAKAAhACiAKgA
lQCqANMAnADVAOEAxgDkAOwA0wDuAO4A3ADyAPMA3QD4APkA3wELAQwA4QEQARMA4wEkASQA5wEmASYA6AEqASsA6QE4AUkA6wFN
AU0A/QFPAU8A/gFUAVQA/wFYAVgBAAFcAVwBAQFzAXgBAgGDAYUBCAGMAZoBCwGdAZ4BGgGgAaMBHAGmAaoBIAGxAbEBJQG0AbUB
JgG6AboBKAG9Ab0BKQG/AcABKgHDAcQBLAHJAckBLgHMAcwBLwHOAd0BMAHgAeoBQAHyAfkBSwILAgsBUwIWAhcBVAIZAhwBVgIg
AiABWgIkAicBWwIpAioBXwI9AkEBYQJLAksBZgJQAmEBZwJjAmsBeQJuAnMBggJ1AnwBiAAkAAAafgABGXQAABqKAAAahAAAGoQA
ABqKAAAaigAAGpAAABqWAAEZegAAGpwAABqiAAAaogAAGqgAABqoAAEZgAAAGq4AABq0AAEZhgAAGroAABrAAAEZjAAAGsYAABrM
AAIbugAAGtIAARmSAAAa2AADAJIAARmYAAAa3gAEAJgABACeAAQApAAEAKoAABrkAAH/awAAAAH++gEJAAH+ugCrAAH+1ADuAAH+
6ADpAZAQCBAgAAAQJgAAD6IPrgAAD7QAAA+oD64AAA+0AAAPuhAgAAAQJgAAD8AQIAAAECYAAA/GECAAABAmAAAPwA/wAAAQJgAA
D8YQIAAAECYAAA/GECAAABAmAAAPzBAgAAAQJgAAD9IQIAAAECYAAA/YECAAABAmAAAP0g/wAAAQJgAAD9gQIAAAECYAAA/YECAA
ABAmAAAP3hAgAAAQJgAAD+QQIAAAECYAAA/qECAAABAmAAAQCA/wAAAQJgAAEA4QIAAAECYAAA/2ECAAABAmAAAP/BAgAAAQJgAA
EAIQIAAAECYAABAIECAAABAmAAAQDhAgAAAQJgAAEBQQIAAAECYAABAaECAAABAmAAAQLBAyAAAAAAAAEooSkAAAAAAAABA4EpAA
AAAAAAAQPhKQAAAAAAAAEooQRAAAAAAAABBKEpAAAAAAAAAQUBKQAAAAAAAAEcQQwgAAAAAQthBWAAAAAAAAELYQXAAAAAAAABC2
EbgQwgAAAAAQthHEEMIAAAAAELYAAAAAAAAAABC2AAAAAAAAAAAQthCwEMIAABDIAAAQYhDCAAAQyAAAEGgQwgAAEMgAABBoEMIA
ABDIAAAQbhDCAAAQyAAAEHQQwgAAEMgAABBuEJIAABDIAAAQdBDCAAAQyAAAEHQQwgAAEMgAABB6EMIAABDIAAAQgBDCAAAQyAAA
EIYQwgAAEMgAABCMEMIAABDIAAAQsBCSAAAQyAAAEJgQwgAAEMgAABCeEMIAABDIAAAQpBDCAAAQyAAAEKoQwgAAEMgAABCwEMIA
ABDIAAARxBDCAAAAABC2ELwQwgAAEMgAABDOENQAAAAAAAAQ5hD4AAAAAAAAENoQ+AAAAAAAABDaEPgAAAAAAAAQ4BD4AAAAAAAA
EOYQ7AAAAAAAABDyEPgAAAAAAAATMhEEAAAAABEKEzIRBAAAAAARChD+EQQAAAAAEQoRUhFeAAARZAAAAAAAAAAAEWQAABEQEV4A
ABFkAAARFhFeAAARZAAAERwRXgAAEWQAABEiEV4AABFkAAARKBFeAAARZAAAES4RXgAAEWQAABFSETQAABFkAAAROhFeAAARZAAA
EUARXgAAEWQAABFGEV4AABFkAAARTBFeAAARZAAAEVIRXgAAEWQAABFYEV4AABFkAAARahF2AAAAAAAAEXARdgAAAAAAABKKEXwA
AAAAAAASihGCAAAAAAAAEZQRmhGgAAARpgAAAAARoAAAEaYRiBGaEaAAABGmEZQRmhGgAAARphGUEY4RoAAAEaYRlBGaEaAAABGm
EZQRmhGgAAARphGUEZoRoAAAEaYRrBX8AAAAAAAAEcQSkAAAAAAAABGyEpAAAAAAAAARuBKQAAAAAAAAEcQRvgAAAAAAABHEEpAA
AAAAAAARyhKQAAAAAAAAEk4SchJ4En4ShBHQEdYAABHcAAASGBJyEngSfhKEEeISchJ4En4ShBHoEnISeBJ+EoQR7hJyEngSfhKE
EegSEhJ4En4ShBHuEnISeBJ+EoQR7hJyEngSfhKEEfQSchJ4En4ShBH6EnISeBJ+EoQSABJyEngSfhKEEgYSchJ4En4ShBIMEnIS
eBJ+EoQSThISEngSfhKEEiQSchJ4En4ShBIqEnISeBJ+EoQSThIwEjYSfhKEEhgSMBI2En4ShBJOEh4SNhJ+EoQSJBIwEjYSfhKE
EioSMBI2En4ShBJmEjASNhJ+EoQSPBJyEngSfhKEEkISchJ4En4ShBJIEnISeBJ+EoQSThJyEngSfhKEElQSYBJ4En4ShBJaEmAS
eBJ+EoQSZhJyEngSfhKEEmwSchJ4En4ShBLYE1AAAAAAAAASihKQAAAAAAAAEqISugAAAAAAABKWEroAAAAAAAASnBK6AAAAAAAA
EqISqAAAAAAAABKuEroAAAAAAAAStBK6AAAAAAAAEtgTUAAAAAAAABLAE1AAAAAAAAASxhNQAAAAAAAAEtgSzAAAAAAAABLSE1AA
AAAAAAAS2BLeAAAAAAAAE4wS6gAAAAAS/BOMEuoAAAAAEvwS5BLqAAAAABL8E4wS8AAAAAAS/BOMEvYAAAAAEvwTbhQQE4AThgAA
EwIUEBOAE4YAABMIFBATgBOGAAATDhQQE4AThgAAExQUEBOAE4YAABMaFBATgBOGAAATbhMgE4AThgAAE3QUEBOAE4YAABMmFBAT
gBOGAAATMhNQE1YThgAAEywTUBNWE4YAABMyEzgTVhOGAAATPhNQE1YThgAAE0QTUBNWE4YAABNKE1ATVhOGAAATXBQQE4AThgAA
E2IUEBOAE4YAABNoFBATgBOGAAATbhQQE4AThgAAE3QUEBOAE4YAABN6FBATgBOGAAATjBOSAAAAAAAAE5gTtgAAAAAAABOeE7YA
AAAAAAATpBO2AAAAAAAAE6oTtgAAAAAAABOwE7YAAAAAAAATzhPyAAAAAAAAE84T8gAAAAAAABO8E/IAAAAAAAATwhPyAAAAAAAA
E8gT8gAAAAAAABPOE9QAAAAAAAAT2hPyAAAAAAAAE+AT8gAAAAAAABPmE/IAAAAAAAAT7BPyAAAAAAAAE/gUEAAAAAAAABP+FBAA
AAAAAAAUBBQQAAAAAAAAFAoUEAAAAAAAABR2FI4AABSUAAAUFhSOAAAUlAAAFBwUjgAAFJQAABQiFI4AABSUAAAUHBRMAAAUlAAA
FCIUjgAAFJQAABQiFI4AABSUAAAUKBSOAAAUlAAAFC4UjgAAFJQAABQ0FI4AABSUAAAULhRMAAAUlAAAFDQUjgAAFJQAABQ0FI4A
ABSUAAAUOhSOAAAUlAAAFEAUjgAAFJQAABRGFI4AABSUAAAUdhRMAAAUlAAAFFIUXgAAAAAAABRYFF4AAAAAAAAUfBSOAAAUlAAA
FGQUjgAAFJQAABRqFI4AABSUAAAUcBSOAAAUlAAAFHYUjgAAFJQAABR8FI4AABSUAAAUghSOAAAUlAAAFIgUjgAAFJQAABfEF9YA
AAAAAAAXxBSmAAAAAAAAF1gUpgAAAAAAABdeFKYAAAAAAAAXxBSaAAAAAAAAF2QUpgAAAAAAABSgFKYAAAAAAAAUrBSyAAAAAAAA
FLgWyBS+AAAUxBS4FsgUvgAAFMQUuBbIFL4AABTEAAAAABS+AAAUxAAAAAAUvgAAFMQYYBUMAAAVEgAAGGYVDAAAFRIAABhsFQwA
ABUSAAAYbBUMAAAVEgAAFMoVDAAAFRIAABTQFQwAABUSAAAUyhToAAAVEgAAFNAVDAAAFRIAABTQFQwAABUSAAAU1hUMAAAVEgAA
FNwVDAAAFRIAABTiFQwAABUSAAAYchUMAAAVEgAAGGAU6AAAFRIAABTuFQwAABUSAAAU9BUMAAAVEgAAFPoVDAAAFRIAABUAFQwA
ABUSAAAYYBUMAAAVEgAAFQYVDAAAFRIAABUYFR4AAAAAAAAVJBVCAAAAAAAAFSoVQgAAAAAAABUqFUIAAAAAAAAVMBVCAAAAAAAA
FTYVQgAAAAAAABU8FUIAAAAAAAAVSBVUAAAAABVaFUgVVAAAAAAVWhVOFVQAAAAAFVoAABXkAAAAAAAAFaIYygAAFa4AABVgGMoA
ABWuAAAVZhjKAAAVrgAAFWwYygAAFa4AABVyGMoAABWuAAAVeBjKAAAVrgAAFaIYygAAFa4AAAAAFX4AAAAAAAAVhBjKAAAVrgAA
FYoYygAAFa4AABWQGMoAABWuAAAVlhjKAAAVrgAAAAAV5AAAAAAAABWcGMoAABWuAAAVohjKAAAVrgAAFagYygAAFa4AABW0FcAA
AAAAAAAVuhXAAAAAAAAAF4gVxgAAAAAAABeIFcwAAAAAAAAV3hXkFeoAABXwFdIV5BXqAAAV8BXeFeQV6gAAFfAV3hXYFeoAABXw
Fd4V5BXqAAAV8BXeFeQV6gAAFfAV3hXkFeoAABXwFfYV/AAAAAAAABfEF9YX3BfiAAAXxBfWF9wX4gAAFsIXpgAAAAAAABYCF6YA
AAAAAAAWCBemAAAAAAAAFsIWDgAAAAAAABbCF6YAAAAAAAAWFBemAAAAAAAAAAAAABYaFiAWJhfEF9YWsBa2FrwXWBfWFrAWtha8
F14X1hawFrYWvBdkF9YWsBa2FrwWLBfWFrAWtha8F2QXdhawFrYWvBYsF9YWsBa2FrwWLBfWFrAWtha8FjIX1hawFrYWvBdqF9YW
sBa2FrwXcBfWFrAWtha8FjgX1hawFrYWvBY+F9YWsBa2FrwXxBd2FrAWtha8FkQWSgAAFlAAABfKF9YWsBa2FrwXfBfWFrAWtha8
FlwX1hZ0FrYWvBZWF9YWdBa2FrwWXBd2FnQWtha8FmIX1hZ0FrYWvBZoF9YWdBa2FrwWbhfWFnQWtha8F7IX1hawFrYWvBe4F9YW
sBa2FrwXvhfWFrAWtha8F8QX1hawFrYWvBZ6FoAAABaGAAAWjBaSFpgWnhakF4gX1hawFrYWvBeCF9YWsBa2FrwX0BfWFrAWtha8
FqoX1hawFrYWvBfEF9YAAAAAAAAWwhbIAAAAAAAAFtoW/gAAAAAAABbOFv4AAAAAAAAW1Bb+AAAAAAAAFtoW4AAAAAAAABbmFv4A
AAAAAAAW7BbyAAAAAAAAFvgW/gAAAAAAABciFxwAAAAAAAAXBBccAAAAAAAAFwoXHAAAAAAAABciFxAAAAAAAAAXFhccAAAAAAAA
FyIXKAAAAAAAABc6Fy4XRgAAF0wXOhcuF0YAABdMFzoXLhdGAAAXTBc6FzQXRgAAF0wXOhdAF0YAABdMAAAAAAAAAAAXUhfEF9YX
3BfiAAAXWBfWF9wX4gAAF14X1hfcF+IAABdkF9YX3BfiAAAXahfWF9wX4gAAF3AX1hfcF+IAABfEF3YX3BfiAAAXyhfWF9wX4gAA
F3wX1hfcF+IAABeIF6YXrBfiAAAXghemF6wX4gAAF4gXjhesF+IAABeUF6YXrBfiAAAXmhemF6wX4gAAF6AXphesF+IAABeyF9YX
3BfiAAAXuBfWF9wX4gAAF74X1hfcF+IAABfEF9YX3BfiAAAXyhfWF9wX4gAAF9AX1hfcF+IAABfoF+4AAAAAAAAX9BgSAAAAAAAA
F/oYEgAAAAAAABgAGBIAAAAAAAAYBhgSAAAAAAAAGAwYEgAAAAAAABgYGB4AAAAAAAAYNhhaAAAAAAAAGCQYWgAAAAAAABgqGFoA
AAAAAAAYMBhaAAAAAAAAGDYYPAAAAAAAABhCGFoAAAAAAAAYSBhaAAAAAAAAGE4YWgAAAAAAABhUGFoAAAAAAAAYYBh4AAAAAAAA
GGYYeAAAAAAAABhsGHgAAAAAAAAYchh4AAAAAAAAAAECTAJMAAECYAMwAAECTAAAAAEETQAUAAEBnAMwAAEBiAMIAAEBiARuAAEB
iAReAAEBiAL+AAEBiASWAAEBiAQiAAEBnAMQAAEBiALkAAEBhf9bAAEBiANOAAEBiAL3AAEBiALuAAEBiAJMAAEBiANEAAEBnAQo
AAEBiAMMAAEBhQBQAAEC1AAQAAEB3gJMAAEB3gAAAAEBuwMwAAEBpwMIAAEBnf8kAAEBpwL+AAEBpQLkAAEDCAJMAAEDCAMIAAEB
pwMwAAEBkwMIAAEBkwL+AAEBkwSWAAEBkwQiAAEBpwMQAAEBkwLkAAEBkQLkAAEBnf8LAAEBkwNEAAEBkwNOAAEBkwL3AAEBkwLu
AAEBkwJMAAEA0AEmAAEBkwMMAAEBnQAAAAECnwAUAAEBfgJMAAEBfgAAAAEBxQMIAAEBxQL+AAEBxQJMAAEBz/7KAAEBwwLkAAEB
xQAAAAEBmAL+AAEBmAAAAAEBmAHGAAEApgMwAAEAkgMIAAEAkgL+AAEApgMQAAEAkgLkAAEAkALkAAEAkv8LAAEAkgNEAAEAkgNO
AAEAkgL3AAEAkgLuAAEAkgJMAAEAkgMMAAEAkgAAAAEA0wAOAAEB+gJMAAEB+gL+AAEBPAAAAAEBfwBGAAEBif8QAAEBiQMwAAEB
nf7KAAEBdQJMAAEBkwAAAAEBuAJMAAEAoQE6AAEBxgJMAAEBsQMwAAEBnQMIAAEBsf7KAAEBnQJMAAEBnQMMAAEDlgJMAAEDoAAA
AAEEogAUAAEBjwMIAAEBjwL+AAEBjwSWAAEBjwQiAAEBowMQAAEBjwLkAAEBjwOGAAEBjQOGAAEBmf8LAAEBowMwAAEBj/8LAAEB
jwNEAAEBjwNOAAEBjwAAAAEDCQIuAAEBjwMwAAEBjwL3AAEBjwLuAAEBjwJMAAEBhQJMAAEBmQMwAAEBhQAAAAEBjwMMAAEBjwOu
AAEBmQAAAAEC9QHUAAEBywAVAAEBlAEsAAEBpwJMAAEBpwAAAAEBlAMwAAEBgAMIAAEBgAJMAAEBsv7KAAEBlAMQAAEBgAL3AAEB
qAAAAAEBmAMwAAEBhAMIAAEBev8kAAEBhAL+AAEBhAJMAAEBjv7KAAEBWwMIAAEBXAAAAAEBUv8kAAEBZv7KAAEBWwEmAAEBlQMm
AAEBgQL+AAEBgQL0AAEBlQMGAAEBgQLaAAEBf/8LAAEBgQNEAAEBrAMwAAEBmAJMAAEBhP8LAAEBmANEAAEBmANOAAEBmAMMAAEB
hAAAAAEC+QKmAAEBgQMmAAEBgQLtAAEBgQLkAAEBgQJCAAEBgQM6AAEBgQMCAAEC5QJMAAEBxAAIAAEBWwJMAAEBWwAAAAECLAJM
AAECQAMwAAECLAL+AAECLALkAAECLANEAAECLAAAAAEBhQMwAAEBcQL+AAEBcQLkAAEBcQJMAAEBcf8LAAEBcQNEAAEBcQNOAAEB
cQLuAAEBcQMMAAEBcQAAAAEBfwJMAAEBkwMwAAEBfwMIAAEBfQLkAAEBfwAAAAEBbgKkAAEBWgJ8AAEBWgPiAAEBWgPSAAEBWgJy
AAEBWgQKAAEBWgOWAAEBbgKEAAEBWgJYAAEBWv8LAAECEQHAAAECJQKkAAECEQAAAAEBWgLCAAEBWgJrAAEBWgJiAAEBWgHAAAEB
WgK4AAEBbgOcAAEBWgKAAAEBWgAAAAECRgAKAAEBIv8kAAEBPgJYAAEBLAAAAAEBnQGtAAEBkQCdAAEBDgHKAAECcwJMAAEB6gIW
AAEBOwJyAAEBOwQKAAEBOwOWAAEBTwKEAAEBOwJYAAEBO/8LAAEBOwK4AAEBOwLCAAEBOwJrAAEBOwJiAAEBOwKAAAEBOwAAAAEC
DgAXAAEA8AHAAAEA8AAAAAEBQQHAAAEBQQJ8AAEBQQJyAAEBNwL3AAEBPwJYAAEBQQAAAAEBlQH8AAEBlQKuAAEBRQAAAAEAzQIi
AAEAjQKkAAEAeQJ8AAEAeQJyAAEAjQKEAAEAeQJYAAEAg/8LAAEAeQHAAAEAeQK4AAEAeQLCAAEAeQJrAAEAeQJiAAEAdwJYAAEA
eQKAAAEApQAPAAEAjgJyAAEAjgHAAAEAhAAAAAEBLAAKAAEBNv7UAAEAlwNYAAEAjf7KAAEAgwJ0AAEAgwAAAAEA5QJMAAEAgwE6
AAEBxgHAAAEBxgAAAAEBXgKkAAEBSgJ8AAEBQP7KAAEBSgKAAAEEvQF+AAEElgCnAAED+wErAAEBQAQKAAEBQAOWAAEBQAL6AAEB
PgL6AAEC2wHAAAEC2wAAAAEDrgAXAAEBWAKkAAEBRAHAAAEBRAK4AAEBRALCAAEBRAKAAAECdgG2AAEAwwIqAAEAwwFKAAEBOQFP
AAEAuQIqAAEAuQFKAAEBSgH4AAEBLQFXAAEAuQG6AAEBQAMiAAECYgFcAAECKAAaAAEBQADgAAEBSgHAAAEBSgAAAAEBMgKuAAEB
HgKGAAEBHgHKAAEBCv7KAAEBMgKOAAEA7wIXAAEA+AGUAAEBHgJ1AAEBAAAAAAEBZwKkAAEBUwJ8AAEBNf8kAAEBUwJyAAEBPwAA
AAEBUwHAAAEBSf7KAAEA2QAAAAEAz/8kAAEAsQJCAAEA4/7KAAEBEALGAAEA5wEIAAEAswH0AAEBVAKkAAEBQAJ8AAEBQAJyAAEB
VAKEAAEBQAJYAAEBQP8LAAEBQALCAAEBSgKkAAEBNgHAAAEBNv8LAAEBNgK4AAEBNgLCAAEBNgKAAAEBNgAAAAECdgIaAAEBQAKk
AAEBQAJrAAEBQAJiAAEBQAHAAAEBQAK4AAEBQAKAAAEBQAAAAAECYgHAAAECOAAKAAEBJwHAAAEBJwAAAAEBrwHAAAEBwwKkAAEB
rwJyAAEBrwJYAAEBrwK4AAEBrwAAAAEBIgHAAAEBIgAAAAEBNwKkAAEBIwJyAAEBIwJYAAEBIwHAAAEB4f8LAAEBIwK4AAEBIwLC
AAEBIwJiAAEBIwKAAAEB4QAAAAEBOwHAAAEBTwKkAAEBOwJ8AAEBOQJYAAEBMQAAAAYAEAABAAoAAAABAAwADAABAB4AZgABAAcB
AQEWASEBLgE2AbcB+gAHAAAAHgAAACQAAAAqAAAAMAAAADYAAAA8AAAAQgAB/wYAAAABAHkAAAAB/wwAAAAB/rIAAAAB/xMACgAB
/zQAAAAB/ygAAAAHABAAFgAcACIAKAAuADQAAf8G/0IAAQBv/yQAAf8W/soAAf6y/0wAAf8T/xUAAf80/2AAAf8o/0wABgAQAAEA
CgABAAEADAAMAAEAPgEIAAEAFwDjAQIBAwEEAQUBBgEHAQ8BGQEaARsBHAEdASIBKQEvATUBewGGAYkBuAIfAkoAFwAAAF4AAABq
AAAAZAAAAGQAAABqAAAAagAAAHAAAAB2AAAAfAAAAIIAAACCAAAAiAAAAIgAAACOAAAAlAAAAJoAAACgAAAApgAAAKwAAACyAAAA
uAAAAL4AAADEAAH+nQHAAAH/CAHAAAH/BgHAAAH/BgH8AAH/JAHAAAH/AAHAAAH/AwHAAAH+/AHAAAH/FgHAAAH+xQHeAAH+sgHe
AAH/GAHKAAH/KQHAAAH/PQHKAAH+2QHAAAH/NAHUAAH/DAHAAAH/EQHKABcAMAA2ADwAPABCAEgATgBUAFoAYABgAGYAbAByAHgA
fgCEAIoAkACWAJwAogCoAAH+sQKkAAH/BgJ8AAH/CAPiAAH/BgPiAAH/BgPSAAH/BgKnAAH/JAJ8AAH/AAJyAAH/AwQKAAH+/AQK
AAH+/AOWAAH/DAL3AAH+2QKiAAH+sgJ2AAH/FgJiAAH/KQK4AAH/PQLMAAH+2QKkAAH/NAJ2AAH/DAK4AAH/EQKKAAYAEAABAAoA
AgABAAwADAABABIAHgABAAEBhwABAAAABgABAFYBZgABAAQAAQBqAcAAAQAAAAoArAGcAAJERkxUAA5sYXRuAC4ABAAAAAD//wAL
AAAAAQACAAMABAAFAAYADwAQABEAEgAAAAhBWkUgADRDQVQgADxDUlQgAERLQVogAExNT0wgAFRST00gAFxUQVQgAGRUUksgAGwA
AP//AAEABwAA//8AAQAIAAD//wABAAkAAP//AAEACgAA//8AAQALAAD//wABAAwAAP//AAEADQAA//8AAQAOABNhYWx0AHRjYWx0
AHxjY21wAIJkbGlnAIpkbm9tAJBmcmFjAJZsaWdhAKBsb2NsAKZsb2NsAKxsb2NsALJsb2NsALhsb2NsAL5sb2NsAMRsb2NsAMps
b2NsANBudW1yANZvcmRuANxzdXBzAOR6ZXJvAOoAAAACAAAAAQAAAAEAHgAAAAIAAgAFAAAAAQAbAAAAAQASAAAAAwATABQAFQAA
AAEAHAAAAAEADwAAAAEABgAAAAEADgAAAAEACwAAAAEACgAAAAEACQAAAAEADAAAAAEADQAAAAEAEQAAAAIAGAAaAAAAAQAQAAAA
AQAdACAAQgCkATgBpAGkAb4CHAJaAloCbgJuApACkAKQApACkAKkAugCxgLUAugC9gNCA0IDaAO+A+AEAgQmBGoEfgSwAAEAAAAB
AAgAAgAuABQB9ACjAKgB8wFLAWgBbgGhAccB9AHsAgICKgIvAjMBcQJBAkQCTQJ+AAEAFAB1AKAApwDTAUwBaQFvAZ8ByAHPAe0C
AQInAjACNAI1AkACRQJOAn8AAwAAAAEACAABAHAADAAeACQAKgAwADgAPgBEAEwAUgBYAGAAaAACAAUB8wACAUsBTAACAWgBaQAD
AW4BbwFwAAIBkwGVAAIBxwHIAAMB7AHtAfEAAgIvAjAAAgIzAjQAAwJEAkUCSAADAk0CTgJPAAMCfgJ/AoAAAQAMAAQBSgFnAW0B
jAHGAesCLgIyAkMCTAJ9AAYAAAACAAoAHAADAAAAAQB0AAEAQAABAAAAAwADAAAAAQBiAAIAFAAuAAEAAAAEAAEACwEBARYBLgE2
AYcBtwHfAjYCNwI6AjsAAQAPAOMBAgEHAQ8BGQEiASkBLwE1AXsBhgGJAbgCHwJKAAEAAAABAAgAAgAKAAIBlQGhAAEAAgGMAZ8A
BAAAAAEACAABAE4AAgAKACwABAAKABAAFgAcAQMAAgDjAQQAAgF7AQUAAgGGAQYAAgJKAAQACgAQABYAHAEaAAIA4wEbAAIBewEc
AAIBhgEdAAICSgABAAIBAgEZAAYAAAACAAoAJAADAAEAFAABAEIAAQAUAAEAAAAHAAEAAQGmAAMAAQAUAAEAKAABABQAAQAAAAgA
AQABAGMAAQAAAAEACAABAAYAAQABAAECAQABAAAAAQAIAAIADgAEAKMAqAIqAkEAAQAEAKAApwInAkAAAQAAAAEACAABAAYABwAB
AAEBjAABAAAAAQAIAAIADgAEAXAB8QJIAk8AAQAEAW0B6wJDAkwAAQAAAAEACAABANAAAQABAAAAAQAIAAEABv88AAEAAQI1AAEA
AAABAAgAAQCuAAIABgAAAAIACgAiAAMAAQASAAEAUAAAAAEAAAAWAAEAAQFxAAMAAQASAAEAOAAAAAEAAAAXAAEACgFLAWgBbgHH
AewCLwIzAkQCTQJ+AAEAAAABAAgAAQAG//8AAQAKAUwBaQFvAcgB7QIwAjQCRQJOAn8ABgAAAAIACgAkAAMAAQAsAAEAEgAAAAEA
AAAZAAEAAgAEANMAAwABABIAAQAqAAAAAQAAABkAAQAKAUoBZwFtAcYB6wIuAjICQwJMAn0AAQACAHUBzwABAAAAAQAIAAIADgAE
AfMB9AHzAfQAAQAEAAQAdQDTAc8ABAAAAAEACAABABQAAQAIAAEABAHOAAMBzwIAAAEAAQBsAAQAAAABAAgAAQBaAAEACAACAAYA
DgFfAAMBXAGZAWIAAgGZAAQAAAABAAgAAQA2AAEACAAFAAwAFAAcACIAKAFeAAMBXAGMAWAAAwFcAaYBXQACAVwBYQACAYwBZAAC
AaYAAQABAVwAAQAAAAEACAABAAYAAwABAAECfQAGAAAAAQAIAAMAAQAYAAEAOAADACQAHgAkAAEAAAAfAAEAAQBfAAEAAQBhAAEA
AQBQAAEAAAABAAgAAQAGAAEAAQABAAQAAAABAAAAAA==
""",
}

if __name__ == "__main__":
    load_fonts()
    # Nadie con tu usuario puede leer la memoria de la ventana (donde pasa la contraseña) ni
    # engancharse a ella (PR_SET_DUMPABLE = 0)
    try:
        import ctypes
        ctypes.CDLL(None).prctl(4, 0, 0, 0, 0)
    except (OSError, AttributeError):
        pass
    # Mismo identificador que StartupWMClass del acceso: asi el dock agrupa la ventana con su icono
    GLib.set_prgname(APP_ID)
    Gdk.set_program_class(APP_ID)
    # Las ventanas de versiones anteriores que sigan en marcha se cierran: hasta la 1.56.14 podian quedarse
    # dando vueltas sin ventana, y la siguiente vez que se abria, el sistema le pasaba la peticion a una de
    # ellas (con el codigo de antes) en lugar de abrir esta
    close_stale_windows(sys.argv[1] if len(sys.argv) > 1 else "")
    # La ventana es App2 (desde la 1.54): App lleva toda la logica (datos, tareas y dialogos) y App2 la
    # organizacion y el aspecto. Al acabar, se sale del todo (sin esperar a ningun hilo)
    rc = App2().run([sys.argv[0]])
    sys.stdout.flush()
    os._exit(rc or 0)
