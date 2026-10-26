using System.Windows;
using System.Windows.Controls;
using NexumDevStack.Core;
using NexumDevStack.Core.Configuracion;
using NexumDevStack.Core.Pila;
using NexumDevStack.Core.Util;

namespace NexumDevStack.App.Paginas;

/// <summary>
/// Configuración: los ficheros (vhosts, hosts), la barrera entre webs, las carpetas, los registros de errores y
/// el programa.
/// </summary>
public sealed class PaginaConfiguracion : Pagina
{
    public PaginaConfiguracion(VentanaPrincipal w) : base(w) { }

    void AddRow(StackPanel list, string title, string sub, string button, Action action)
    {
        var (row, suffix, _, s) = Ui.Row(title, sub);
        s.TextWrapping = TextWrapping.Wrap;
        suffix.Children.Add(Ui.TextButton(button, action));
        Ui.AddRow(list, row);
    }

    public override void Build()
    {
        Content.Children.Clear();
        Content.Children.Add(Ui.PageTitle(Ui.Icon(Ico.Ajustes, 24), "Configuración", "Ficheros de configuración, carpetas, registros y el programa"));
        var l = W.Motor.L;
        var st = W.State;

        var (cfg, cfgList) = Ui.Group("Configuración",
            "Los vhosts son compartidos por todas las versiones; hosts es del administrador. Se edita una copia y se aplica con Aplicar (hosts pide permiso de administrador).");
        AddRow(cfgList, "Virtual hosts", l.VhostsFile, "Editar…", () => W.EditVhosts());
        AddRow(cfgList, "Hosts del sistema", W.Motor.Pf.HostsFilePath, "Editar…", () => W.EditHosts());
        Content.Children.Add(cfg);

        var (sec, secList) = Ui.Group("Seguridad entre webs",
            "Otra web abierta en el navegador no puede mandar formularios ni peticiones a tus proyectos con tus sesiones. " +
            "Una pasarela de pago que vuelve a la tienda con un POST (Redsys, PayPal…) no pasa: apágala mientras la pruebas.");
        var on = st?.CrossSite ?? W.Motor.CrossSiteOn;
        var (row, suffix, _, _) = Ui.Row("Barrera entre webs",
            on ? "Encendida: solo se puede llegar a tus proyectos desde otra web con un enlace" : "Apagada: enciéndela cuando acabes de probar los pagos");
        var sw = Ui.Switch(on, v => W.RunTask(v ? "Encendiendo la barrera entre webs" : "Apagando la barrera entre webs",
            new[] { "barrera-web", v ? "si" : "no" }, new OpcionesTarea { DoneText = v ? "Barrera entre webs encendida" : "Barrera entre webs apagada", AutoClose = true }));
        sw.IsEnabled = Prepared && !W.Busy;
        suffix.Children.Add(sw);
        Ui.AddRow(secList, row);
        Content.Children.Add(sec);

        var (dirs, dirList) = Ui.Group("Carpetas");
        AddRow(dirList, "Proyectos", $"{l.Htdocs}, compartida por todas las versiones", "Abrir", () => W.OpenFolder(l.Htdocs));
        AddRow(dirList, "Copias de seguridad", $"{l.CopiesDir}: BBDD borradas o sustituidas, vhosts y configuraciones anteriores", "Abrir", () => W.OpenFolder(l.CopiesDir));
        AddRow(dirList, "Registros de las tareas", $"{l.UserLogs}: lo que ha hecho cada tarea de la ventana", "Abrir", () => W.OpenFolder(l.UserLogs));
        AddRow(dirList, "Instalación", $"{l.Root}: las versiones, sus BBDD y lo compartido", "Abrir", () => W.OpenFolder(l.Root));
        Content.Children.Add(dirs);

        if (Prepared && st?.Active is { } active)
        {
            var (logs, logList) = Ui.Group("Registro de errores",
                "Si la web cargada da un error (el «error crítico» de WordPress), el motivo está en el registro de su vhost o en el general de Apache: " +
                "ahí van los errores de PHP. Lo más reciente está al final.");
            var loaded = W.Projects?.Current;
            LogRow(logList, $"error de web.local{(string.IsNullOrEmpty(loaded) ? "" : $"  ({loaded})")}", Path.Combine(l.LogDir(active), "web.local-error.log"));
            LogRow(logList, $"error de Apache ({active})", l.ApacheErrorLog(active));
            LogRow(logList, $"error de MariaDB ({active})", l.MariaDbErrorLog(active));
            Content.Children.Add(logs);
        }

        var (prog, progList) = Ui.Group("Programa");
        var installed = st?.ProgramVersion;
        var (prow, psuf, _, _) = Ui.Row("Programa de administrador",
            installed == null ? $"Todavía no está en {l.ProgramExe}" : $"{l.ProgramExe}: versión {installed}" +
                (Versiones.Compare(installed, AppInfo.Version) < 0 ? $" (esta es la {AppInfo.Version}: actualízala)" : ""));
        if (Prepared && (installed == null || Versiones.Compare(installed, AppInfo.Version) < 0))
            psuf.Children.Add(Ui.TextButton("Actualizar", () => W.RunTask("Actualizando el programa de administrador", new[] { "actualizar-programa" },
                new OpcionesTarea { DoneText = "Programa actualizado", AutoClose = true })));
        Ui.AddRow(progList, prow);
        AddRow(progList, "Buscar una versión nueva", "La actualización firmada desde aquí llega en la fase 3", "Buscar",
            () => Dialogo.Message(W, "Buscar una versión nueva", "La actualización firmada del programa llega en la fase 3."));
        Content.Children.Add(prog);

        var (info, infoList) = Ui.Group("Información");
        AddRow(infoList, "Comandos de NexumDevStack.exe", "Todos los comandos para la consola y qué hace cada uno", "Ver", () => W.ShowCommands());
        AddRow(infoList, "Novedades", "Qué ha cambiado en cada versión", "Ver", () => W.ShowChanges());
        AddRow(infoList, "Acerca de", $"{AppInfo.Name} {AppInfo.Version}", "Ver", () => W.ShowAbout());
        Content.Children.Add(info);
    }

    void LogRow(StackPanel list, string title, string path)
    {
        string sub;
        long size = 0;
        try
        {
            var fi = new FileInfo(path);
            if (fi.Exists)
            {
                size = fi.Length;
                sub = $"{path}  ·  {Texto.Size(size)}  ·  modificado el {Texto.Stamp(fi.LastWriteTime)}";
            }
            else
                sub = $"{path}: no existe todavía (se crea con el primer error)";
        }
        catch (IOException)
        {
            sub = path;
        }
        var (row, suffix, _, s) = Ui.Row(title, sub);
        s.TextWrapping = TextWrapping.Wrap;
        var tail = Ui.TextButton("Ver el final", () => W.ShowLogTail(path));
        tail.IsEnabled = size > 0;
        suffix.Children.Add(tail);
        var open = Ui.TextButton("Abrir", () => W.OpenText(path));
        open.Margin = new Thickness(8, 0, 0, 0);
        // (uno de cientos de MB dejaría colgado el Bloc de notas)
        open.IsEnabled = size > 0 && size < 20 * 1024 * 1024;
        suffix.Children.Add(open);
        Ui.AddRow(list, row);
    }
}
