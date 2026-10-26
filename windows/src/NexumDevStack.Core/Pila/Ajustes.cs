using System.Text.Json;
using System.Text.Json.Serialization;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Pila;

/// <summary>Preferencias de tu usuario (%LOCALAPPDATA%\NexumDevStack\ajustes.json): la versión activa.</summary>
public sealed class Ajustes
{
    [JsonPropertyName("activa")]
    public string? Active { get; set; }

    static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public static Ajustes Load(Disposicion l)
    {
        var text = Ficheros.ReadSmallText(l.SettingsFile, 100_000);
        if (text == null)
            return new Ajustes();
        try
        {
            var a = JsonSerializer.Deserialize<Ajustes>(text, Options) ?? new Ajustes();
            if (a.Active != null && !Validacion.IsVersionFolder(a.Active))
                a.Active = null;
            return a;
        }
        catch (JsonException)
        {
            return new Ajustes();
        }
    }

    public void Save(Disposicion l) => Ficheros.WriteAtomic(l.SettingsFile, JsonSerializer.Serialize(this, Options));
}
