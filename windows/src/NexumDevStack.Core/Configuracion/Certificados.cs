using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text.RegularExpressions;
using NexumDevStack.Core.Tareas;
using NexumDevStack.Core.Util;

namespace NexumDevStack.Core.Configuracion;

/// <summary>
/// Certificados autofirmados de los proyectos (como make_selfsigned de Linux): de un solo dominio (y su
/// alias), CA:FALSE (no sirven para firmar otras webs) y en config\ssl.
/// </summary>
public static class Certificados
{
    public sealed record Par(string CertPem, string KeyPem, string Thumbprint);

    /// <summary>Organización con la que se reconocen los certificados de Nexum en el almacén de Windows.</summary>
    public const string Organization = "Nexum Dev Stack (local)";

    public static Par Create(string domain, string? alias, int days = 3650)
    {
        if (!Validacion.IsDomain(domain) && domain != "localhost")
            throw new NexumException($"Dominio no válido para el certificado: {domain}");
        if (alias != null && !Validacion.IsDomain(alias))
            alias = null;
        using var rsa = RSA.Create(2048);
        var req = new CertificateRequest($"CN={domain}, O={Organization}", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        req.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, true));
        req.CertificateExtensions.Add(new X509KeyUsageExtension(
            X509KeyUsageFlags.DigitalSignature | X509KeyUsageFlags.KeyEncipherment, true));
        req.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension(
            new OidCollection { new Oid("1.3.6.1.5.5.7.3.1") }, false));
        var san = new SubjectAlternativeNameBuilder();
        san.AddDnsName(domain);
        if (alias != null)
            san.AddDnsName(alias);
        if (domain == "localhost")
        {
            san.AddIpAddress(System.Net.IPAddress.Loopback);
            san.AddIpAddress(System.Net.IPAddress.IPv6Loopback);
        }
        req.CertificateExtensions.Add(san.Build());
        req.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(req.PublicKey, false));
        var now = DateTimeOffset.UtcNow.AddMinutes(-5);
        using var cert = req.CreateSelfSigned(now, now.AddDays(days));
        return new Par(cert.ExportCertificatePem() + "\n", rsa.ExportPkcs8PrivateKeyPem() + "\n", cert.Thumbprint);
    }

    /// <summary>Nombres de fichero válidos para config\ssl (sin rutas ni caracteres raros).</summary>
    public static bool IsSafeFileName(string name) => Regex.IsMatch(name, @"^[A-Za-z0-9][A-Za-z0-9._-]*\.(crt|pem|key)$");

    /// <summary>Huella SHA-1 de un certificado PEM (null si no se puede leer).</summary>
    public static string? Thumbprint(string pem)
    {
        try
        {
            using var c = X509Certificate2.CreateFromPem(pem);
            return c.Thumbprint;
        }
        catch (CryptographicException)
        {
            return null;
        }
    }

    /// <summary>¿Es de CA (sirve para firmar otras webs)? Esos no se aceptan en los vhosts.</summary>
    public static bool IsCa(string pem)
    {
        try
        {
            using var c = X509Certificate2.CreateFromPem(pem);
            var bc = c.Extensions.OfType<X509BasicConstraintsExtension>().FirstOrDefault();
            return bc?.CertificateAuthority == true;
        }
        catch (CryptographicException)
        {
            return true;
        }
    }

    /// <summary>Escribe el certificado y su clave en la carpeta de certificados (la clave, solo de tu usuario: lo da su carpeta).</summary>
    public static void Write(string sslDir, string crtName, string keyName, Par par)
    {
        if (!IsSafeFileName(crtName) || !IsSafeFileName(keyName))
            throw new NexumException($"Nombre de certificado no válido: {crtName}");
        Directory.CreateDirectory(sslDir);
        Ficheros.WriteAtomic(Path.Combine(sslDir, keyName), par.KeyPem);
        Ficheros.WriteAtomic(Path.Combine(sslDir, crtName), par.CertPem);
    }
}
