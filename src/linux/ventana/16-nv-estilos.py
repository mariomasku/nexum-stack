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
/* Barra de arriba mas alta, y el recuadro de la version montada, hundido (como una pantallita). Como en el Mac:
   un velo del color de la letra (en el tema claro, casi el fondo; en el oscuro, algo mas claro) y una sombra suave */
headerbar.nv-cabecera { min-height: 60px; padding-top: 8px; padding-bottom: 8px; }
/* El aviso de abajo (toast): grande, con el logotipo de Nexum. La píldora (el fondo y el borde con los colores
   de su icono) la pinta toast_paint: aquí, solo sus márgenes */
.nv-toast { padding: 15px 40px 15px 34px; }
.nv-toast-texto { font-size: 1.15em; font-weight: 600; }
.nv-pastilla { background-color: alpha(@theme_fg_color, 0.05); border: 1px solid alpha(@theme_fg_color, 0.12); border-radius: 12px;
               padding: 3px 4px; box-shadow: inset 0 1px 3px alpha(black, 0.16); }
.nv-pastilla button { border: none; background: transparent; box-shadow: none; }
.nv-pastilla button.nv-servicios { border-radius: 8px; padding: 2px 8px; }
.nv-pastilla button.nv-servicios:hover, .nv-pastilla button.nv-servicios:checked { background-color: alpha(@theme_fg_color, 0.10); }
/* Arrancar o parar la version desde el visor: solo el icono, verde (▶) o rojo (■), sin recuadro */
.nv-pastilla button.nv-encender { border-radius: 8px; padding: 2px 4px; }
.nv-pastilla button.nv-encender.nv-play { color: %(g)s; }
.nv-pastilla button.nv-encender.nv-stop { color: #e5534b; }
.nv-pastilla button.nv-encender:hover { background-color: alpha(@theme_fg_color, 0.10); }
.nv-pastilla button.nv-encender:disabled { opacity: 0.45; }
/* Subir o actualizar una BBDD: un visor un poco hundido, como el de arriba */
.nv-hundido { background-color: alpha(@theme_fg_color, 0.05); border: 1px solid alpha(@theme_fg_color, 0.12); border-radius: 12px;
              box-shadow: inset 0 1px 3px alpha(black, 0.16); padding: 14px 16px; }
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
.nv-selectores { background-color: alpha(@theme_fg_color, 0.05); border: 1px solid alpha(@theme_fg_color, 0.12); border-radius: 12px;
                 padding: 12px 14px; box-shadow: inset 0 1px 3px alpha(black, 0.16); }
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


def new_split_page(width=860):
    """Como new_page, en dos partes: arriba, fija (no se va al desplazar: el visor de Proyectos), y debajo lo
    que se desplaza (la lista). Devuelve (página, caja de arriba, caja de abajo, su ScrolledWindow)."""
    page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    top = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin_top=26, margin_bottom=14)
    top.set_size_request(width, -1)
    sw = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
    bottom = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin_bottom=26)
    bottom.set_size_request(width, -1)
    sw.add(bottom)
    page.pack_start(top, False, False, 0)
    page.pack_start(sw, True, True, 0)

    def fit(_w, alloc):
        side = max(26, (alloc.width - PAGE_MAX) // 2)
        for box in (top, bottom):
            if box.get_margin_start() != side:
                box.set_margin_start(side)
                box.set_margin_end(side)
    page.connect("size-allocate", fit)
    return page, top, bottom, sw


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
