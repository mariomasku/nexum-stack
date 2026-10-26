using Org.BouncyCastle.Bcpg;
using Org.BouncyCastle.Bcpg.OpenPgp;

namespace NexumDevStack.Core.Descargas;

/// <summary>
/// Comprobación de firmas OpenPGP (como gpgv en Linux), con BouncyCastle y solo con las claves que lleva el
/// programa: ni las del equipo ni un servidor de claves. Una firma solo vale si es de una de las huellas
/// de quien publica ese fichero (la de su clave principal), no de cualquiera de las claves. Una clave
/// caducada vale para lo que firmó antes.
/// </summary>
public sealed class Firmas
{
    readonly PgpPublicKeyRingBundle _keys;

    public Firmas(Stream keyring)
    {
        _keys = new PgpPublicKeyRingBundle(PgpUtilities.GetDecoderStream(keyring));
    }

    /// <summary>Las claves que lleva el programa (las de lvm-instalador de Linux y la de Apache Lounge).</summary>
    public static Firmas Embedded()
    {
        using var s = typeof(Firmas).Assembly.GetManifestResourceStream("NexumDevStack.Core.claves-firmas.gpg")
                      ?? throw new InvalidOperationException("Faltan las claves de las firmas en el programa");
        return new Firmas(s);
    }

    /// <summary>Huellas de las claves principales del llavero.</summary>
    public IEnumerable<string> Fingerprints() =>
        _keys.GetKeyRings().Cast<PgpPublicKeyRing>().Select(r => Hex(r.GetPublicKey().GetFingerprint()));

    static string Hex(byte[] b) => Convert.ToHexString(b);

    /// <summary>
    /// ¿Es buena la firma (separada, en ASCII o binaria) de <paramref name="data"/> y de una de esas huellas?
    /// Devuelve la huella de quien la firmó (null si no vale) y el motivo.
    /// </summary>
    public string? Verify(Stream data, Stream signature, IEnumerable<string> allowedFingerprints, out string detail)
    {
        var allowed = new HashSet<string>(allowedFingerprints.Select(f => f.Replace(" ", "").ToUpperInvariant()));
        PgpSignatureList? list;
        try
        {
            var factory = new PgpObjectFactory(PgpUtilities.GetDecoderStream(signature));
            var obj = factory.NextPgpObject();
            if (obj is PgpCompressedData compressed)
                obj = new PgpObjectFactory(compressed.GetDataStream()).NextPgpObject();
            list = obj as PgpSignatureList;
        }
        catch (Exception ex) when (ex is IOException or PgpException)
        {
            detail = "la firma no se puede leer: " + ex.Message;
            return null;
        }
        if (list == null || list.Count == 0)
        {
            detail = "el fichero de la firma no tiene ninguna firma";
            return null;
        }

        var buffer = new byte[1 << 16];
        detail = "la firma no es de ninguna clave conocida";
        for (int i = 0; i < list.Count; i++)
        {
            var sig = list[i];
            if (sig.SignatureType != PgpSignature.BinaryDocument)
            {
                detail = "la firma no es de un fichero binario";
                continue;
            }
            PgpPublicKey? key;
            PgpPublicKeyRing? ring;
            try
            {
                key = _keys.GetPublicKey(sig.KeyId);
                ring = _keys.GetPublicKeyRing(sig.KeyId);
            }
            catch (PgpException)
            {
                key = null;
                ring = null;
            }
            if (key == null || ring == null)
                continue;
            var primary = Hex(ring.GetPublicKey().GetFingerprint());
            if (!allowed.Contains(primary))
            {
                detail = $"la firma es de {primary}, que no publica este fichero";
                continue;
            }
            try
            {
                sig.InitVerify(key);
                if (data.CanSeek)
                    data.Position = 0;
                int n;
                while ((n = data.Read(buffer, 0, buffer.Length)) > 0)
                    sig.Update(buffer, 0, n);
                if (sig.Verify())
                {
                    detail = "firma buena de " + primary;
                    return primary;
                }
                detail = "la firma no coincide con el fichero";
            }
            catch (Exception ex) when (ex is PgpException or IOException)
            {
                detail = "no se ha podido comprobar la firma: " + ex.Message;
            }
        }
        return null;
    }

    /// <summary>Huella de la clave principal que dice haber hecho esta firma (si la conocemos), sin comprobar los datos.</summary>
    public string? Issuer(Stream signature)
    {
        try
        {
            var factory = new PgpObjectFactory(PgpUtilities.GetDecoderStream(signature));
            var obj = factory.NextPgpObject();
            if (obj is PgpCompressedData compressed)
                obj = new PgpObjectFactory(compressed.GetDataStream()).NextPgpObject();
            if (obj is not PgpSignatureList list || list.Count == 0)
                return null;
            var ring = _keys.GetPublicKeyRing(list[0].KeyId);
            return ring == null ? null : Hex(ring.GetPublicKey().GetFingerprint());
        }
        catch (Exception ex) when (ex is IOException or PgpException)
        {
            return null;
        }
    }
}
