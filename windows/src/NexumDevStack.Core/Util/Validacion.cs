using System.Text.RegularExpressions;

namespace NexumDevStack.Core.Util;

/// <summary>
/// Lo que se acepta en cada dato que acaba en un fichero de configuración, en una consulta SQL o en una
/// ruta: los mismos límites que el script de Linux (solo ASCII, sin comillas ni saltos de línea).
/// </summary>
public static class Validacion
{
    static readonly Regex DbRx = new(@"^[A-Za-z0-9_][A-Za-z0-9_-]{0,63}$", RegexOptions.CultureInvariant);
    static readonly Regex FolderRx = new(@"^[A-Za-z0-9_][A-Za-z0-9 ._-]*$", RegexOptions.CultureInvariant);
    static readonly Regex NewFolderRx = new(@"^[A-Za-z0-9_][A-Za-z0-9._-]{0,63}$", RegexOptions.CultureInvariant);
    static readonly Regex DomainRx = new(
        @"^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$", RegexOptions.CultureInvariant);
    static readonly Regex PhpRx = new(@"^\d{1,2}\.\d{1,2}\.\d{1,3}$", RegexOptions.CultureInvariant);
    static readonly Regex VersionFolderRx = new(@"^php-\d{1,2}\.\d{1,2}\.\d{1,3}$", RegexOptions.CultureInvariant);
    static readonly Regex SidRx = new(@"^S-1-5-21(-\d{1,10}){4}$", RegexOptions.CultureInvariant);
    static readonly Regex TaskIdRx = new(@"^[0-9a-f]{16}$", RegexOptions.CultureInvariant);

    /// <summary>Bases del sistema: no se tocan nunca (sin distinguir mayúsculas).</summary>
    public static readonly string[] SystemDatabases = { "information_schema", "mysql", "performance_schema", "phpmyadmin", "sys", "test" };

    /// <summary>Nombre de BBDD válido (sin - delante: el cliente lo tomaría como una opción).</summary>
    public static bool IsDbName(string? name) => name != null && DbRx.IsMatch(name);

    public static bool IsSystemDb(string name) => SystemDatabases.Contains(name.ToLowerInvariant());

    /// <summary>Nombre de BBDD válido y que no es del sistema; si no, el motivo.</summary>
    public static string? DbNameProblem(string? name)
    {
        if (!IsDbName(name))
            return $"Nombre de base de datos no valido: {name} (solo letras sin acentos, numeros, _ y -, sin - delante)";
        if (IsSystemDb(name!))
            return $"{name} es una base de datos del sistema: no se toca";
        return null;
    }

    /// <summary>Carpeta de proyecto (va entre comillas en los vhosts): letras sin acentos, números, espacio, punto, _ y -.</summary>
    public static bool IsProjectFolder(string? name) =>
        name != null && FolderRx.IsMatch(name) && name.Length <= 128 && name != "." && name != ".." && !name.EndsWith('.') && !name.EndsWith(' ');

    /// <summary>Carpeta nueva (Nuevo proyecto con dominio falseado): sin espacios.</summary>
    public static bool IsNewFolder(string? name) => name != null && NewFolderRx.IsMatch(name) && !name.EndsWith('.');

    public static bool IsDomain(string? d) => d != null && d.Length <= 253 && DomainRx.IsMatch(d);

    /// <summary>Versión completa de PHP: 8.4.27</summary>
    public static bool IsPhpVersion(string? v) => v != null && PhpRx.IsMatch(v);

    /// <summary>Carpeta de una versión instalada: php-8.4.27</summary>
    public static bool IsVersionFolder(string? v) => v != null && VersionFolderRx.IsMatch(v);

    /// <summary>SID de una cuenta de usuario local o de dominio (S-1-5-21-…).</summary>
    public static bool IsUserSid(string? sid) => sid != null && SidRx.IsMatch(sid);

    /// <summary>Identificador de una tarea elevada: 16 caracteres hexadecimales en minúscula.</summary>
    public static bool IsTaskId(string? id) => id != null && TaskIdRx.IsMatch(id);

    /// <summary>Nombres reservados de Windows (no se pueden usar como carpeta).</summary>
    public static bool IsReservedWindowsName(string name)
    {
        var stem = name.Split('.')[0].ToUpperInvariant();
        return stem is "CON" or "PRN" or "AUX" or "NUL" ||
               (stem.Length == 4 && (stem.StartsWith("COM") || stem.StartsWith("LPT")) && char.IsDigit(stem[3]));
    }
}
