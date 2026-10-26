using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

namespace NexumDevStack.Core.Proyectos;

/// <summary>
/// El botón Panel: una página con el administrador de pruebas ya escrito (un formulario que va a la pantalla
/// de acceso del proyecto; solo hay que pulsar Entrar), servida una vez en 127.0.0.1 (puerto libre y ruta al
/// azar) durante un minuto. Por http y no como fichero: el navegador la abre igual en cualquier equipo.
/// </summary>
public static class AccesoPanel
{
    static string E(string s) => WebUtility.HtmlEncode(s);

    /// <summary>La página (como login_page de Linux). fields: (nombre, valor, texto visible o null si va oculto).</summary>
    public static string Page(string title, string project, string action, IEnumerable<(string Name, string Value, string? Text)> fields, string panel)
    {
        var rows = new StringBuilder();
        var hidden = new StringBuilder();
        foreach (var (name, value, text) in fields)
        {
            if (text != null)
            {
                var kind = name is "pwd" or "passwd" ? "password" : "text";
                rows.Append($"<label>{E(text)}<input type=\"{kind}\" name=\"{E(name)}\" value=\"{E(value)}\" autocomplete=\"off\"></label>");
            }
            else
                hidden.Append($"<input type=\"hidden\" name=\"{E(name)}\" value=\"{E(value)}\">");
        }
        return $$"""
<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="referrer" content="no-referrer"><title>{{E(title)}} · {{E(project)}}</title>
<style>
:root { color-scheme: light dark; --bg: #f4f4f6; --card: #fff; --line: #d8d8dc; --muted: #6b6b72; --accent: #0a84ff; }
@media (prefers-color-scheme: dark) { :root { --bg: #1e1e20; --card: #2a2a2d; --line: #444; --muted: #a0a0a6; } }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: var(--bg);
       font: 15px/1.45 system-ui, "Segoe UI", sans-serif; }
form { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 28px 32px;
       width: min(380px, calc(100vw - 32px)); box-sizing: border-box; }
h1 { font-size: 19px; margin: 0 0 4px; } p { margin: 0 0 18px; color: var(--muted); font-size: 13px; }
label { display: block; font-size: 13px; color: var(--muted); margin-bottom: 14px; }
input[type=text], input[type=password] { display: block; width: 100%; box-sizing: border-box; margin-top: 4px;
       padding: 8px 10px; font: inherit; border: 1px solid var(--line); border-radius: 8px; background: transparent; }
button { width: 100%; margin-top: 6px; padding: 10px; font: inherit; font-weight: 600; color: #fff;
         background: var(--accent); border: 0; border-radius: 8px; cursor: pointer; }
small { display: block; margin-top: 14px; color: var(--muted); font-size: 12px; }
</style></head><body>
<form method="post" action="{{E(action)}}">
<h1>{{E(title)}}</h1><p>{{E(project)}} · administrador de pruebas de este equipo</p>
{{rows}}{{hidden}}<button type="submit" autofocus>Entrar</button>
<small>Si no entra, el panel normal está en <a href="{{E(panel)}}">{{E(panel)}}</a>.</small>
</form></body></html>
""";
    }

    /// <summary>Sirve la página una vez (o durante <paramref name="seconds"/>) y devuelve su dirección; null si no se puede.</summary>
    public static string? ServeOnce(string page, int seconds = 60)
    {
        var body = Encoding.UTF8.GetBytes(page);
        var path = "/acceso-" + Convert.ToHexString(RandomNumberGenerator.GetBytes(8)).ToLowerInvariant();
        TcpListener listener;
        try
        {
            listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
        }
        catch (SocketException)
        {
            return null;
        }
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var until = DateTime.UtcNow.AddSeconds(seconds);
        var t = new Thread(() =>
        {
            try
            {
                while (DateTime.UtcNow < until)
                {
                    if (!listener.Pending())
                    {
                        Thread.Sleep(100);
                        continue;
                    }
                    using var client = listener.AcceptTcpClient();
                    client.ReceiveTimeout = 5000;
                    using var stream = client.GetStream();
                    var request = ReadRequestLine(stream);
                    var ok = request.StartsWith($"GET {path} ", StringComparison.Ordinal);
                    var head = ok
                        ? $"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {body.Length}\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n"
                        : "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                    stream.Write(Encoding.ASCII.GetBytes(head));
                    if (ok)
                        stream.Write(body);
                }
            }
            catch (Exception)
            {
                // (el navegador ha cortado la conexión: no pasa nada)
            }
            finally
            {
                listener.Stop();
            }
        }) { IsBackground = true, Name = "acceso-panel" };
        t.Start();
        return $"http://127.0.0.1:{port}{path}";
    }

    static string ReadRequestLine(Stream s)
    {
        var buf = new byte[1];
        // (la primera línea y las cabeceras, hasta la línea en blanco, de 8 KB como mucho)
        var all = new StringBuilder();
        while (all.Length < 8192 && s.Read(buf, 0, 1) == 1)
        {
            all.Append((char)buf[0]);
            if (all.Length >= 4 && all.ToString(all.Length - 4, 4) == "\r\n\r\n")
                break;
        }
        var text = all.ToString();
        var nl = text.IndexOf("\r\n", StringComparison.Ordinal);
        return nl >= 0 ? text[..nl] : text;
    }

    /// <summary>Campos y acción de la pantalla de acceso de WordPress o PrestaShop.</summary>
    public static (string Title, string Action, List<(string, string, string?)> Fields) LoginFor(string kind, string link, string admin,
        string user, string password)
    {
        var baseUrl = $"http://{link}/{admin}/";
        if (kind == "wp")
            return ("Panel de WordPress", $"http://{link}/wp-login.php", new()
            {
                ("log", user, "Usuario o correo"), ("pwd", password, "Contraseña"), ("rememberme", "forever", null), ("redirect_to", baseUrl, null),
            });
        return ("Back office de PrestaShop", baseUrl + "index.php?controller=AdminLogin", new()
        {
            ("email", user, "Correo"), ("passwd", password, "Contraseña"), ("stay_logged_in", "1", null), ("submitLogin", "1", null),
            ("redirect", "AdminDashboard", null),
        });
    }
}
