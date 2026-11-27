#!/usr/bin/python3
"""Run the installed engine GUI with persistent, root-installed WSL adapters."""
import ast
import os
import pathlib
import subprocess
import sys

ENGINE = '/opt/nexum/nexum.sh'
BRIDGE = '/opt/nexum/windows/open.py'
RESTART = 75


def adapt(gui):
    """Called after engine classes are defined, before its normal GTK startup."""
    gui['ENV_KEEP'].update({'WSL_DISTRO_NAME', 'WSL_INTEROP'})
    original_command = gui['script_cmd']

    def script_command(*args):
        if args and args[0] == 'windows-update':
            # Older engines only authenticate sudo descendants of the task process.
            # Keep bash alive until sudo exits; pass package paths as arguments.
            return ['/bin/bash', '-c', '/usr/bin/sudo "$@"; exit $?',
                    'nexum-windows-update', '/opt/nexum/nexum-actualizar', *args[1:]]
        return original_command(*args)

    gui['script_cmd'] = script_command
    glib, gtk = gui['GLib'], gui['Gtk']

    def open_uri(app, uri):
        try:
            # Older engine releases concatenate raw paths into file:// links.
            if uri.startswith('file://') and pathlib.Path(uri[7:]).exists():
                uri = uri[7:]
            subprocess.run(['/usr/bin/python3', BRIDGE, uri], check=True,
                           stdin=subprocess.DEVNULL, capture_output=True, timeout=20)
        except (OSError, subprocess.SubprocessError) as error:
            detail = (error.stderr or b'').decode('utf-8', 'replace') if isinstance(error, subprocess.CalledProcessError) else str(error)
            gui['message'](app.win, 'No se ha podido abrir %s' % uri, detail, gtk.MessageType.ERROR)

    def open_text(app, path):
        try:
            subprocess.run(['/usr/bin/python3', BRIDGE, '--text', path], check=True,
                           stdin=subprocess.DEVNULL, capture_output=True, timeout=20)
        except (OSError, subprocess.SubprocessError) as error:
            gui['message'](app.win, 'No se ha podido abrir %s' % path, str(error), gtk.MessageType.ERROR)

    def terminal(app, *_args):
        try:
            subprocess.run(['/usr/bin/python3', BRIDGE, '--terminal'], check=True,
                           stdin=subprocess.DEVNULL, capture_output=True, timeout=20)
        except (OSError, subprocess.SubprocessError) as error:
            gui['message'](app.win, 'No se ha podido abrir la terminal', str(error), gtk.MessageType.ERROR)

    def restart(app):
        # The Windows launcher repeats this process, keeping its sync companion alive.
        app.windows_restart = True
        app.quit()
        return False

    def offer_package(app, version, when, sha, path):
        if app.task_running():
            app.refuse_task()
            return False
        if not gui['confirm'](app.win, 'Hay una versión nueva de Nexum Dev Stack',
                              'Versión %s, del %s. Se comprueba su firma y se pide la contraseña '
                              'de sudo de Ubuntu. La ventana se vuelve a abrir.\n\nSHA-256:\n%s'
                              % (version, when, sha), 'Actualizar a la %s' % version):
            return False
        if gui['SIMULATE']:
            app.toast('[simulación] Actualizar a la %s' % version)
            return True

        def installed(ok, task, _progress):
            if ok:
                glib.idle_add(restart, app)
            elif 'instalalo en la terminal' in task.log_text():
                app.terminal_install(version, path)

        app.run_task('Actualizando a la versión %s' % version,
                     ['windows-update', path, sha], on_done=installed,
                     done_text='Nexum actualizado')
        return True

    base = gui['AppPrograma']
    base.open_uri, base.open_text, base.on_terminal = open_uri, open_text, terminal
    base.offer_package, base.restart_updated = offer_package, restart
    original_run = gui['App2'].run

    def run(app, *args, **kwargs):
        result = original_run(app, *args, **kwargs)
        return RESTART if getattr(app, 'windows_restart', False) else result

    gui['App2'].run = run
    original_vscode = gui.get('vscode_app')
    if original_vscode:
        def vscode():
            app = gui['Gio'].DesktopAppInfo.new('nexum-windows-vscode.desktop')
            return app or original_vscode()
        gui['vscode_app'] = vscode


def main():
    text = pathlib.Path(ENGINE).read_text(encoding='utf-8')
    start = "    cat <<'LVM_GUI_PY'\n"
    source = text.split(start, 1)[1].split('\nLVM_GUI_PY\n', 1)[0]
    tree = ast.parse(source, filename=ENGINE + ':gui')
    # Inject adapters immediately before the engine's own __main__ block.
    entry = next(i for i, node in enumerate(tree.body)
                 if isinstance(node, ast.If) and isinstance(node.test, ast.Compare)
                 and isinstance(node.test.left, ast.Name) and node.test.left.id == '__name__')
    tree.body.insert(entry, ast.parse('_windows_adapt(globals())').body[0])
    ast.fix_missing_locations(tree)
    sys.argv = ['-', ENGINE]
    log = pathlib.Path.home() / '.nexum'
    log.mkdir(mode=0o700, exist_ok=True)
    with (log / 'ventana.log').open('w', encoding='utf-8') as output:
        os.dup2(output.fileno(), 2)
        exec(compile(tree, ENGINE + ':gui', 'exec'),
             {'__name__': '__main__', '_windows_adapt': adapt})


if __name__ == '__main__':
    main()
