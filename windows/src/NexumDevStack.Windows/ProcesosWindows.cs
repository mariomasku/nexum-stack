using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using NexumDevStack.Core.Plataforma;

namespace NexumDevStack.Windows;

/// <summary>
/// Procesos en Windows: Apache y MariaDB se arrancan con CreateProcess sin heredar nada (ni la salida de la
/// tarea que los lanza: si la heredaran, la ventana no vería terminar la tarea), sin ventana y en su propio
/// grupo; si se puede, fuera del «job» de quien los lanza, para que sigan en marcha al cerrar el programa.
/// </summary>
public sealed class ProcesosWindows : ProcesosBase
{
    public override int StartDetached(string exe, IReadOnlyList<string> args, string workDir, IReadOnlyDictionary<string, string?>? env = null)
    {
        var cmd = new StringBuilder(Quote(exe));
        foreach (var a in args)
            cmd.Append(' ').Append(Quote(a));
        var block = EnvironmentBlock(env);
        var si = new Nativo.STARTUPINFO
        {
            cb = Marshal.SizeOf<Nativo.STARTUPINFO>(),
            dwFlags = Nativo.STARTF_USESHOWWINDOW,
            wShowWindow = Nativo.SW_HIDE,
        };
        var envPtr = Marshal.StringToHGlobalUni(block);
        try
        {
            var flags = Nativo.CREATE_NO_WINDOW | Nativo.CREATE_NEW_PROCESS_GROUP | Nativo.CREATE_UNICODE_ENVIRONMENT;
            if (!Nativo.CreateProcessW(exe, new StringBuilder(cmd.ToString()), IntPtr.Zero, IntPtr.Zero, false,
                    flags | Nativo.CREATE_BREAKAWAY_FROM_JOB, envPtr, workDir, ref si, out var pi))
            {
                // (el «job» de quien lanza no deja salir de él: sin esa opción)
                var err = Marshal.GetLastWin32Error();
                if (err != 5 || !Nativo.CreateProcessW(exe, new StringBuilder(cmd.ToString()), IntPtr.Zero, IntPtr.Zero, false,
                        flags, envPtr, workDir, ref si, out pi))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), $"No se ha podido arrancar {Path.GetFileName(exe)}");
            }
            Nativo.CloseHandle(pi.hThread);
            Nativo.CloseHandle(pi.hProcess);
            return pi.dwProcessId;
        }
        finally
        {
            Marshal.FreeHGlobal(envPtr);
        }
    }

    /// <summary>Entorno de este proceso, sin las variables peligrosas y con los cambios, ordenado y con su doble \0.</summary>
    static string EnvironmentBlock(IReadOnlyDictionary<string, string?>? changes)
    {
        var env = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (System.Collections.DictionaryEntry e in Environment.GetEnvironmentVariables())
            env[(string)e.Key] = (string?)e.Value ?? "";
        foreach (var k in UnsafeEnv)
            env.Remove(k);
        if (changes != null)
            foreach (var (k, v) in changes)
            {
                if (v == null) env.Remove(k);
                else env[k] = v;
            }
        var sb = new StringBuilder();
        foreach (var (k, v) in env)
        {
            if (k.Length == 0 || k.Contains('=') && !k.StartsWith('=')) continue;
            sb.Append(k).Append('=').Append(v).Append('\0');
        }
        sb.Append('\0');
        return sb.ToString();
    }

    /// <summary>Un argumento con las reglas de comillas de Windows (las de CommandLineToArgvW).</summary>
    public static string Quote(string arg)
    {
        if (arg.Length > 0 && arg.IndexOfAny(new[] { ' ', '\t', '"', '\n', '\v' }) < 0)
            return arg;
        var sb = new StringBuilder("\"");
        for (int i = 0; i < arg.Length; i++)
        {
            int slashes = 0;
            while (i < arg.Length && arg[i] == '\\')
            {
                slashes++;
                i++;
            }
            if (i == arg.Length)
            {
                sb.Append('\\', slashes * 2);
                break;
            }
            if (arg[i] == '"')
                sb.Append('\\', slashes * 2 + 1).Append('"');
            else
                sb.Append('\\', slashes).Append(arg[i]);
        }
        return sb.Append('"').ToString();
    }

    /// <summary>Ruta real del programa de un proceso (null si no se puede saber: de otro usuario o protegido).</summary>
    public static string? ImagePath(int pid)
    {
        var h = Nativo.OpenProcess(Nativo.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (h == IntPtr.Zero)
            return null;
        try
        {
            var sb = new StringBuilder(1024);
            var size = sb.Capacity;
            return Nativo.QueryFullProcessImageNameW(h, 0, sb, ref size) ? sb.ToString(0, size) : null;
        }
        finally
        {
            Nativo.CloseHandle(h);
        }
    }

    public override IReadOnlyList<ProcesoEncontrado> FindUnder(string folder)
    {
        var root = Path.GetFullPath(folder).TrimEnd('\\') + "\\";
        var list = new List<ProcesoEncontrado>();
        foreach (var p in Process.GetProcesses())
        {
            using (p)
            {
                // (solo los programas que pueden ser de Nexum, para no abrir todos los procesos del equipo)
                var name = p.ProcessName;
                if (!name.Equals("httpd", StringComparison.OrdinalIgnoreCase) &&
                    !name.Equals("mariadbd", StringComparison.OrdinalIgnoreCase) &&
                    !name.Equals("mysqld", StringComparison.OrdinalIgnoreCase) &&
                    !name.Equals("php", StringComparison.OrdinalIgnoreCase) &&
                    !name.Equals("php-cgi", StringComparison.OrdinalIgnoreCase) &&
                    !name.Equals("rotatelogs", StringComparison.OrdinalIgnoreCase))
                    continue;
                var path = ImagePath(p.Id);
                if (path == null || !path.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                    continue;
                DateTime start;
                try { start = p.StartTime; }
                catch (Exception) { start = DateTime.MinValue; }
                list.Add(new ProcesoEncontrado(p.Id, path, start, 0));
            }
        }
        return list;
    }

    public override bool IsRunning(int pid, string expectedImage)
    {
        var path = ImagePath(pid);
        return path != null && string.Equals(Path.GetFullPath(path), Path.GetFullPath(expectedImage), StringComparison.OrdinalIgnoreCase);
    }

    public override bool Kill(int pid, string expectedImage)
    {
        // Solo si es de verdad ese programa (un PID se puede reutilizar)
        var h = Nativo.OpenProcess(Nativo.PROCESS_QUERY_LIMITED_INFORMATION | Nativo.PROCESS_TERMINATE | Nativo.SYNCHRONIZE, false, pid);
        if (h == IntPtr.Zero)
            return false;
        try
        {
            var sb = new StringBuilder(1024);
            var size = sb.Capacity;
            if (!Nativo.QueryFullProcessImageNameW(h, 0, sb, ref size) ||
                !string.Equals(Path.GetFullPath(sb.ToString(0, size)), Path.GetFullPath(expectedImage), StringComparison.OrdinalIgnoreCase))
                return false;
            return Nativo.TerminateProcess(h, 1);
        }
        finally
        {
            Nativo.CloseHandle(h);
        }
    }
}
