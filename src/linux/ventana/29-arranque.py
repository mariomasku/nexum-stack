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
