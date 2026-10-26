using System.Text.Json;
using System.Text.Json.Serialization;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Pila;

/// <summary>
/// Lo que lleva una versión instalada (versiones\php-X.Y.Z\nexum-version.json): lo escribe la instalación,
/// con permisos de administrador, y no lo puede cambiar tu usuario.
/// </summary>
public sealed class Manifiesto
{
    public string Folder { get; set; } = "";
    public string Php { get; set; } = "";
    public string PhpBuild { get; set; } = "";
    public string Apache { get; set; } = "";
    public string ApacheBuild { get; set; } = "";
    public string MariaDb { get; set; } = "";
    public string Pma { get; set; } = "";
    public string InstalledAt { get; set; } = "";
    public string InstalledBy { get; set; } = "";
    public List<string> Verified { get; set; } = new();
    public int Schema { get; set; } = 1;

    static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public string ToJson() => JsonSerializer.Serialize(this, Options);

    public static Manifiesto? Parse(string json)
    {
        try
        {
            var m = JsonSerializer.Deserialize<Manifiesto>(json, Options);
            // (va a rutas y a la ventana: solo valores con la forma esperada)
            if (m == null || !Validacion.IsVersionFolder(m.Folder) || !Validacion.IsPhpVersion(m.Php))
                return null;
            m.Apache = Clean(m.Apache);
            m.MariaDb = Clean(m.MariaDb);
            m.Pma = Clean(m.Pma);
            m.PhpBuild = Clean(m.PhpBuild);
            m.ApacheBuild = Clean(m.ApacheBuild);
            return m;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    static string Clean(string? v) => System.Text.RegularExpressions.Regex.IsMatch(v ?? "", @"^[A-Za-z0-9.\-+ ]{0,40}$") ? v ?? "" : "";

    public static Manifiesto? Load(Disposicion l, string folder)
    {
        var text = Ficheros.ReadSmallText(l.Manifest(folder), 200_000);
        var m = text == null ? null : Parse(text);
        return m != null && m.Folder == folder ? m : null;
    }

    /// <summary>Rama de PHP (8.4).</summary>
    [JsonIgnore]
    public string Branch => Versiones.Branch(Php);

    /// <summary>¿PHP 8 o posterior? (el módulo de Apache es php_module; en la 7, php7_module).</summary>
    [JsonIgnore]
    public int PhpMajor => Versiones.Parts(Php).FirstOrDefault();
}
