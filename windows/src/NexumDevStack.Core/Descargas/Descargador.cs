using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using NexumDevStack.Core.Catalogo;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Descargas;

/// <summary>
/// Descargas solo por HTTPS (también las redirecciones), con su sha256 calculado mientras se descargan, su
/// firma comprobada si la hay y una caché de lo ya comprobado.
/// </summary>
public sealed class Descargador : IDisposable
{
    readonly HttpClient _http;
    readonly Firmas _firmas;

    public Descargador(Firmas firmas, HttpMessageHandler? handler = null)
    {
        _firmas = firmas;
        handler ??= new SocketsHttpHandler
        {
            AllowAutoRedirect = true,
            MaxAutomaticRedirections = 8,
            AutomaticDecompression = DecompressionMethods.None,
            ConnectTimeout = TimeSpan.FromSeconds(20),
        };
        _http = new HttpClient(handler) { Timeout = Timeout.InfiniteTimeSpan };
        _http.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("NexumDevStack", AppInfo.Version));
        _http.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("(Windows)"));
    }

    public void Dispose() => _http.Dispose();

    static void CheckHttps(Uri? uri, string what)
    {
        if (uri == null || uri.Scheme != Uri.UriSchemeHttps)
            throw new NexumException($"{what}: solo se descarga por HTTPS ({uri})");
    }

    /// <summary>Texto de una URL (páginas y JSON de los proveedores), de hasta 8 MB.</summary>
    public async Task<string> GetTextAsync(string url, CancellationToken ct, int timeoutSeconds = 30)
    {
        var uri = new Uri(url);
        CheckHttps(uri, url);
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));
        using var resp = await _http.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, cts.Token).ConfigureAwait(false);
        CheckHttps(resp.RequestMessage?.RequestUri, url);
        resp.EnsureSuccessStatusCode();
        await using var s = await resp.Content.ReadAsStreamAsync(cts.Token).ConfigureAwait(false);
        using var ms = new MemoryStream();
        var buf = new byte[1 << 16];
        int n;
        while ((n = await s.ReadAsync(buf, cts.Token).ConfigureAwait(false)) > 0)
        {
            ms.Write(buf, 0, n);
            if (ms.Length > 8 << 20)
                throw new NexumException($"{url}: la respuesta es demasiado grande");
        }
        return Encoding.UTF8.GetString(ms.ToArray());
    }

    /// <summary>Un fichero pequeño (hasta 64 MB) en memoria.</summary>
    public byte[] GetBytes(string url, CancellationToken ct, int timeoutSeconds = 300)
    {
        var uri = new Uri(url);
        CheckHttps(uri, url);
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));
        using var resp = _http.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, cts.Token).GetAwaiter().GetResult();
        CheckHttps(resp.RequestMessage?.RequestUri, url);
        resp.EnsureSuccessStatusCode();
        using var s = resp.Content.ReadAsStream(cts.Token);
        using var ms = new MemoryStream();
        var buf = new byte[1 << 16];
        int n;
        while ((n = s.Read(buf, 0, buf.Length)) > 0)
        {
            ms.Write(buf, 0, n);
            if (ms.Length > 64 << 20)
                throw new NexumException($"{url}: es demasiado grande");
        }
        return ms.ToArray();
    }

    public string GetText(string url, CancellationToken ct, int timeoutSeconds = 30) =>
        GetTextAsync(url, ct, timeoutSeconds).GetAwaiter().GetResult();

    /// <summary>sha256 de un fichero.</summary>
    public static string Sha256Of(string path)
    {
        using var fs = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(fs)).ToLowerInvariant();
    }

    /// <summary>
    /// Descarga <paramref name="d"/> en <paramref name="cacheDir"/> (o usa la que ya esté y coincida) y
    /// comprueba su sha256 y su firma. Devuelve la ruta del fichero comprobado.
    /// </summary>
    public string Fetch(Descarga d, string cacheDir, ISalida o, (int From, int To)? span = null)
    {
        Directory.CreateDirectory(cacheDir);
        if (!System.Text.RegularExpressions.Regex.IsMatch(d.Name, @"^[A-Za-z0-9][A-Za-z0-9._-]*$"))
            throw new NexumException($"Nombre de descarga no válido: {d.Name}");
        var dest = Path.Combine(cacheDir, d.Name);
        if (File.Exists(dest) && !Ficheros.IsLink(dest) && Sha256Of(dest) == d.Sha256)
        {
            o.Line($"  {d.Name}: ya descargado antes (sha256 correcta)");
        }
        else
        {
            o.Line($"  Descargando {d.Name}...");
            var part = dest + ".parte";
            for (int attempt = 1; ; attempt++)
            {
                try
                {
                    DownloadTo(d.Url, part, o, span);
                    break;
                }
                catch (Exception ex) when (attempt < 3 && ex is HttpRequestException or IOException && !o.Cancel.IsCancellationRequested)
                {
                    o.Line($"  Fallo al descargar ({ex.Message}); se reintenta...");
                    Thread.Sleep(2000 * attempt);
                }
            }
            var sum = Sha256Of(part);
            if (sum != d.Sha256)
            {
                File.Delete(part);
                throw new NexumException($"  {d.Name} no coincide con su suma sha256 (es {sum}). Se cancela.");
            }
            File.Move(part, dest, true);
        }
        o.Line($"  sha256 de {d.Name}: correcta ({d.Sha256[..16]}…)");
        if (d.Signed)
        {
            string sigText = d.SignatureText ?? GetText(d.SignatureUrl!, o.Cancel);
            using var sig = new MemoryStream(Encoding.ASCII.GetBytes(sigText));
            using var data = File.OpenRead(dest);
            var who = _firmas.Verify(data, sig, d.Fingerprints, out var detail);
            if (who == null)
                throw new NexumException($"  La firma de {d.Name} no es buena o no es de quien lo publica ({detail}). Se cancela.");
            o.Line($"  Firma de {d.Name}: buena ({detail})");
        }
        else
        {
            o.Line($"  {d.Name}: {d.HowVerified}");
        }
        return dest;
    }

    void DownloadTo(string url, string path, ISalida o, (int From, int To)? span)
    {
        var uri = new Uri(url);
        CheckHttps(uri, url);
        using var resp = _http.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, o.Cancel).GetAwaiter().GetResult();
        CheckHttps(resp.RequestMessage?.RequestUri, url);
        if (!resp.IsSuccessStatusCode)
            throw new NexumException($"  No se pudo descargar {url} ({(int)resp.StatusCode} {resp.ReasonPhrase})");
        var total = resp.Content.Headers.ContentLength ?? 0;
        using var src = resp.Content.ReadAsStream(o.Cancel);
        using var dst = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None);
        var buf = new byte[1 << 17];
        long done = 0, lastShown = -1;
        var shown = DateTime.MinValue;
        int n;
        while ((n = src.Read(buf, 0, buf.Length)) > 0)
        {
            o.Cancel.ThrowIfCancellationRequested();
            dst.Write(buf, 0, n);
            done += n;
            if ((DateTime.UtcNow - shown).TotalMilliseconds > 400)
            {
                shown = DateTime.UtcNow;
                var pct = total > 0 ? (int)(done * 100 / total) : -1;
                if (pct != lastShown)
                {
                    lastShown = pct;
                    // (la barra de la tarea avanza dentro del tramo de esta descarga)
                    if (span is { } sp && pct >= 0)
                        o.Progress(sp.From + (sp.To - sp.From) * pct / 100, "descargando " + Path.GetFileName(path).Replace(".parte", ""));
                    o.Raw(total > 0
                        ? $"\r    {pct,3} %  {Texto.Size(done)} de {Texto.Size(total)}"
                        : $"\r    {Texto.Size(done)}");
                }
            }
        }
        o.Raw(total > 0 ? $"\r    100 %  {Texto.Size(done)} de {Texto.Size(total)}\n" : $"\r    {Texto.Size(done)}\n");
        if (total > 0 && done != total)
            throw new IOException($"descarga incompleta ({done} de {total} bytes)");
    }
}
