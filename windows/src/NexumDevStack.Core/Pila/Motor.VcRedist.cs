using NexumDevStack.Core.Descargas;
using NexumDevStack.Core.Tareas;
using Cat = NexumDevStack.Core.Catalogo.Catalogo;

namespace NexumDevStack.Core.Pila;

public sealed partial class Motor
{
    /// <summary>
    /// instalar-vcredist: descarga el runtime de Visual C++ 2015-2026 (x64) de Microsoft (aka.ms), comprueba que
    /// está firmado por Microsoft (Authenticode) y lo instala (pide permiso de administrador él mismo). El
    /// fichero se queda abierto sin que nadie lo pueda cambiar entre la comprobación y la instalación.
    /// </summary>
    public void InstallVcRedist(ISalida o)
    {
        var dir = Path.Combine(L.UserDir, "descargas");
        Directory.CreateDirectory(dir);
        var file = Path.Combine(dir, "vc_redist.x64.exe");
        o.Line("Descargando el runtime de Visual C++ de Microsoft...");
        using (var d = new Descargador(Signatures))
        {
            var bytes = d.GetBytes(Cat.VcRedistUrl, o.Cancel);
            File.WriteAllBytes(file, bytes);
        }
        using var hold = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (!Pf.IsSignedByMicrosoft(file, out var detail))
            throw new NexumException($"vc_redist.x64.exe no está firmado por Microsoft ({detail}): no se instala.");
        o.Line($"Firma de Microsoft: buena ({detail})");
        o.Line("Instalando (Windows pide permiso de administrador)...");
        // (con el shell: si el instalador pide ser administrador desde el principio, Windows lo eleva)
        int code;
        try
        {
            using var p = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(file, "/install /passive /norestart")
            {
                UseShellExecute = true,
                WorkingDirectory = dir,
            }) ?? throw new NexumException("No se ha podido lanzar el instalador del runtime de Visual C++.");
            if (!p.WaitForExit((int)TimeSpan.FromMinutes(15).TotalMilliseconds))
                throw new NexumException("El instalador del runtime de Visual C++ no ha terminado en 15 minutos.");
            code = p.ExitCode;
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 1223)
        {
            code = 1223;
        }
        switch (code)
        {
            case 0:
                o.Line("Runtime de Visual C++ instalado.");
                break;
            case 3010:
                o.Line("Runtime de Visual C++ instalado: Windows pide reiniciar el equipo para terminar.");
                break;
            case 1638:
                o.Line("Ya tienes un runtime de Visual C++ igual o más nuevo.");
                break;
            case 1602 or 1223:
                throw new NexumException("Cancelado: no se ha instalado el runtime de Visual C++.", 130);
            default:
                throw new NexumException($"El instalador del runtime de Visual C++ ha terminado con el código {code}.");
        }
    }
}
