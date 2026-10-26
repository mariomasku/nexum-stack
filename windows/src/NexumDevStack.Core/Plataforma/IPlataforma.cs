namespace NexumDevStack.Core.Plataforma;

/// <summary>
/// Todo lo que depende de Windows, detrás de interfaces: la implementación de verdad está en
/// NexumDevStack.Windows; las pruebas usan las suyas.
/// </summary>
public interface IPlataforma
{
    /// <summary>C:\Windows\System32\drivers\etc\hosts</summary>
    string HostsFilePath { get; }

    /// <summary>¿Este proceso tiene permisos de administrador (elevado)?</summary>
    bool IsElevated { get; }

    /// <summary>SID de tu usuario (S-1-5-21-…).</summary>
    string CurrentUserSid { get; }

    string CurrentUserName { get; }

    IProcesos Processes { get; }

    ICertificados Certificates { get; }

    IElevacion Elevation { get; }

    IPermisos Permissions { get; }

    /// <summary>Runtime de Visual C++ 2015-2026 instalado (x64), o null si no está.</summary>
    Version? VcRuntimeVersion();

    /// <summary>Vacía la caché de DNS de Windows (al cambiar hosts).</summary>
    void FlushDns();

    /// <summary>Quién escucha en esos puertos TCP (de cualquier dirección).</summary>
    IReadOnlyList<PuertoOcupado> PortOwners(IEnumerable<int> ports);

    /// <summary>¿Firmado por Microsoft (Authenticode) y la firma es buena?</summary>
    bool IsSignedByMicrosoft(string path, out string detail);
}

public sealed record PuertoOcupado(int Port, string Address, int Pid, string ProcessName, string? ImagePath);

public sealed record ProcesoEncontrado(int Pid, string ImagePath, DateTime StartTime, int ParentPid);

public sealed record ResultadoProceso(int ExitCode, string Output, bool TimedOut);

/// <summary>Arranque, búsqueda y parada de procesos.</summary>
public interface IProcesos
{
    /// <summary>
    /// Arranca un proceso sin ventana, en su propio grupo (Ctrl+C de una consola no le llega) y sin heredar
    /// nada de este. Sigue en marcha al cerrar el programa. Devuelve su PID.
    /// </summary>
    int StartDetached(string exe, IReadOnlyList<string> args, string workDir, IReadOnlyDictionary<string, string?>? env = null);

    /// <summary>
    /// Ejecuta un programa y espera a que termine, con su salida (stdout y stderr juntos). Los argumentos van
    /// por separado (sin pasar por ningún intérprete de órdenes).
    /// </summary>
    ResultadoProceso Run(string exe, IReadOnlyList<string> args, TimeSpan timeout, string? workDir = null,
        IReadOnlyDictionary<string, string?>? env = null, string? stdin = null);

    /// <summary>Procesos cuyo programa está dentro de esa carpeta (con su ruta real).</summary>
    IReadOnlyList<ProcesoEncontrado> FindUnder(string folder);

    /// <summary>¿Sigue en marcha ese PID con ese programa?</summary>
    bool IsRunning(int pid, string expectedImage);

    /// <summary>Termina ese PID solo si su programa es <paramref name="expectedImage"/>.</summary>
    bool Kill(int pid, string expectedImage);
}

/// <summary>Almacén de certificados de confianza de tu usuario (Edge y Chrome lo usan).</summary>
public interface ICertificados
{
    /// <summary>¿Está ese certificado (por su huella SHA-1) en Raíz de tu usuario?</summary>
    bool IsTrusted(string thumbprint);

    /// <summary>Lo añade (Windows pregunta antes). false si no se ha añadido.</summary>
    bool Trust(string pemCertificate, out string detail);

    /// <summary>Lo quita (Windows pregunta antes).</summary>
    bool Untrust(string thumbprint, out string detail);

    /// <summary>Huellas SHA-1 de los certificados de Raíz de tu usuario que puso Nexum (por su nombre).</summary>
    IReadOnlyList<(string Thumbprint, string Subject)> NexumTrusted();
}

/// <summary>Relanzar el programa con permisos de administrador (UAC).</summary>
public interface IElevacion
{
    /// <summary>
    /// Lanza <paramref name="exe"/> con «runas» y «--elevado» + los argumentos. No espera.
    /// false si Windows no lo ha lanzado (cancelado en el aviso de UAC, por ejemplo).
    /// </summary>
    bool Launch(string exe, IReadOnlyList<string> args, out string detail, out System.Diagnostics.Process? process);
}

/// <summary>Permisos (ACL) de C:\NexumDevStack.</summary>
public interface IPermisos
{
    /// <summary>
    /// Solo administradores y SYSTEM pueden cambiarla; el resto, leer. Sin heredar del padre. Con
    /// <paramref name="recursive"/>, lo de dentro vuelve a heredar solo esos permisos (y su dueño pasa a ser
    /// Administradores).
    /// </summary>
    void SetAdminOnly(string dir, bool usersCanRead, bool recursive = false);

    /// <summary>Solo tu usuario (modificar), administradores y SYSTEM. Sin heredar del padre.</summary>
    void SetUserPrivate(string dir, string userSid);

    /// <summary>¿El dueño de la carpeta es Administradores o SYSTEM y nadie más puede escribir en ella?</summary>
    bool IsAdminOwned(string dir, out string detail);
}
