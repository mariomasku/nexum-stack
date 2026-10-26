using System.ComponentModel;
using System.Diagnostics;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using Microsoft.Win32;
using NexumDevStack.Core.Configuracion;
using NexumDevStack.Core.Plataforma;

namespace NexumDevStack.Windows;

/// <summary>Windows 10 y 11.</summary>
public sealed class PlataformaWindows : IPlataforma
{
    public string HostsFilePath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "drivers", "etc", "hosts");

    public bool IsElevated
    {
        get
        {
            using var id = WindowsIdentity.GetCurrent();
            return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
        }
    }

    public string CurrentUserSid
    {
        get
        {
            using var id = WindowsIdentity.GetCurrent();
            return id.User?.Value ?? "";
        }
    }

    public string CurrentUserName => Environment.UserName;

    public IProcesos Processes { get; } = new ProcesosWindows();
    public ICertificados Certificates { get; } = new CertificadosWindows();
    public IElevacion Elevation { get; } = new ElevacionWindows();
    public IPermisos Permissions { get; } = new PermisosWindows();

    /// <summary>
    /// Runtime de Visual C++ 2015-2026 x64: HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64 (Installed,
    /// Major, Minor, Bld). Si el registro no lo dice, la versión de vcruntime140.dll de System32.
    /// </summary>
    public Version? VcRuntimeVersion()
    {
        foreach (var path in new[] { @"SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64", @"SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" })
        {
            try
            {
                using var k = Registry.LocalMachine.OpenSubKey(path);
                if (k?.GetValue("Installed") is int installed && installed == 1 && k.GetValue("Major") is int major &&
                    k.GetValue("Minor") is int minor)
                    return new Version(major, minor, k.GetValue("Bld") is int bld ? bld : 0);
            }
            catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException or IOException) { }
        }
        try
        {
            var dll = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "vcruntime140.dll");
            if (File.Exists(dll))
            {
                var v = FileVersionInfo.GetVersionInfo(dll);
                return new Version(v.FileMajorPart, v.FileMinorPart, v.FileBuildPart);
            }
        }
        catch (Exception) { }
        return null;
    }

    public void FlushDns()
    {
        try { Nativo.DnsFlushResolverCache(); }
        catch (Exception) { }
    }

    public IReadOnlyList<PuertoOcupado> PortOwners(IEnumerable<int> ports)
    {
        var wanted = ports.ToHashSet();
        var result = new List<PuertoOcupado>();
        foreach (var family in new[] { Nativo.AF_INET, Nativo.AF_INET6 })
            foreach (var (addr, port, pid) in Listeners(family))
                if (wanted.Contains(port))
                {
                    string name;
                    try
                    {
                        using var p = Process.GetProcessById(pid);
                        name = p.ProcessName;
                    }
                    catch (Exception)
                    {
                        name = pid == 4 ? "System" : "?";
                    }
                    result.Add(new PuertoOcupado(port, addr, pid, name, ProcesosWindows.ImagePath(pid)));
                }
        return result;
    }

    /// <summary>Puertos TCP en escucha con su proceso (GetExtendedTcpTable).</summary>
    static List<(string Address, int Port, int Pid)> Listeners(int family)
    {
        var list = new List<(string, int, int)>();
        int size = 0;
        Nativo.GetExtendedTcpTable(IntPtr.Zero, ref size, false, family, Nativo.TCP_TABLE_OWNER_PID_LISTENER, 0);
        var buf = Marshal.AllocHGlobal(size);
        try
        {
            if (Nativo.GetExtendedTcpTable(buf, ref size, false, family, Nativo.TCP_TABLE_OWNER_PID_LISTENER, 0) != 0)
                return list;
            var n = Marshal.ReadInt32(buf);
            var row = buf + 4;
            for (int i = 0; i < n; i++)
            {
                if (family == Nativo.AF_INET)
                {
                    // MIB_TCPROW_OWNER_PID: state, localAddr, localPort, remoteAddr, remotePort, pid (6 × 4 bytes)
                    var addr = new IPAddress(BitConverter.GetBytes(Marshal.ReadInt32(row + 4))).ToString();
                    var port = (Marshal.ReadByte(row + 8) << 8) | Marshal.ReadByte(row + 9);
                    var pid = Marshal.ReadInt32(row + 20);
                    list.Add((addr, port, pid));
                    row += 24;
                }
                else
                {
                    // MIB_TCP6ROW_OWNER_PID: localAddr[16], localScopeId, localPort, remoteAddr[16], remoteScopeId,
                    // remotePort, state, pid (56 bytes)
                    var bytes = new byte[16];
                    Marshal.Copy(row, bytes, 0, 16);
                    var port = (Marshal.ReadByte(row + 20) << 8) | Marshal.ReadByte(row + 21);
                    var pid = Marshal.ReadInt32(row + 52);
                    list.Add((new IPAddress(bytes).ToString(), port, pid));
                    row += 56;
                }
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buf);
        }
        return list;
    }

    /// <summary>¿Firma Authenticode buena (WinVerifyTrust) y de Microsoft Corporation?</summary>
    public bool IsSignedByMicrosoft(string path, out string detail)
    {
        var pathPtr = Marshal.StringToHGlobalUni(path);
        var fileInfo = new Nativo.WINTRUST_FILE_INFO { cbStruct = (uint)Marshal.SizeOf<Nativo.WINTRUST_FILE_INFO>(), pcwszFilePath = pathPtr };
        var filePtr = Marshal.AllocHGlobal(Marshal.SizeOf<Nativo.WINTRUST_FILE_INFO>());
        Marshal.StructureToPtr(fileInfo, filePtr, false);
        var data = new Nativo.WINTRUST_DATA
        {
            cbStruct = (uint)Marshal.SizeOf<Nativo.WINTRUST_DATA>(),
            dwUIChoice = Nativo.WTD_UI_NONE,
            fdwRevocationChecks = Nativo.WTD_REVOKE_WHOLECHAIN,
            dwUnionChoice = Nativo.WTD_CHOICE_FILE,
            pFile = filePtr,
            dwStateAction = Nativo.WTD_STATEACTION_VERIFY,
            dwProvFlags = Nativo.WTD_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT,
        };
        var dataPtr = Marshal.AllocHGlobal(Marshal.SizeOf<Nativo.WINTRUST_DATA>());
        Marshal.StructureToPtr(data, dataPtr, false);
        try
        {
            var r = Nativo.WinVerifyTrust(new IntPtr(-1), Nativo.WINTRUST_ACTION_GENERIC_VERIFY_V2, dataPtr);
            data = Marshal.PtrToStructure<Nativo.WINTRUST_DATA>(dataPtr);
            data.dwStateAction = Nativo.WTD_STATEACTION_CLOSE;
            Marshal.StructureToPtr(data, dataPtr, true);
            Nativo.WinVerifyTrust(new IntPtr(-1), Nativo.WINTRUST_ACTION_GENERIC_VERIFY_V2, dataPtr);
            if (r != 0)
            {
                detail = $"la firma no es válida (0x{r:X8})";
                return false;
            }
#pragma warning disable SYSLIB0057
            using var signer = new X509Certificate2(X509Certificate.CreateFromSignedFile(path));
#pragma warning restore SYSLIB0057
            var subject = signer.Subject;
            detail = signer.GetNameInfo(X509NameType.SimpleName, false);
            return subject.Contains("O=Microsoft Corporation", StringComparison.Ordinal);
        }
        catch (CryptographicException ex)
        {
            detail = ex.Message;
            return false;
        }
        finally
        {
            Marshal.FreeHGlobal(dataPtr);
            Marshal.FreeHGlobal(filePtr);
            Marshal.FreeHGlobal(pathPtr);
        }
    }
}

/// <summary>Raíz de confianza de tu usuario (Edge y Chrome la usan; Firefox, con security.enterprise_roots.enabled).</summary>
public sealed class CertificadosWindows : ICertificados
{
    static X509Store Open(OpenFlags flags)
    {
        var s = new X509Store(StoreName.Root, StoreLocation.CurrentUser);
        s.Open(flags);
        return s;
    }

    public bool IsTrusted(string thumbprint)
    {
        using var s = Open(OpenFlags.ReadOnly);
        return s.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, false).Count > 0;
    }

    public bool Trust(string pemCertificate, out string detail)
    {
        try
        {
            using var c = X509Certificate2.CreateFromPem(pemCertificate);
            if (c.Extensions.OfType<X509BasicConstraintsExtension>().Any(b => b.CertificateAuthority))
            {
                detail = "es de CA: no se acepta";
                return false;
            }
            using var s = Open(OpenFlags.ReadWrite);
            // (Windows enseña su aviso; si se dice que no, salta una excepción)
            s.Add(c);
            detail = "";
            return s.Certificates.Find(X509FindType.FindByThumbprint, c.Thumbprint, false).Count > 0;
        }
        catch (CryptographicException ex)
        {
            detail = ex.Message;
            return false;
        }
    }

    public bool Untrust(string thumbprint, out string detail)
    {
        try
        {
            using var s = Open(OpenFlags.ReadWrite);
            var found = s.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, false);
            foreach (var c in found)
                if (c.Subject.Contains("O=" + Certificados.Organization, StringComparison.Ordinal))
                    s.Remove(c);
            detail = "";
            return s.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, false).Count == 0;
        }
        catch (CryptographicException ex)
        {
            detail = ex.Message;
            return false;
        }
    }

    public IReadOnlyList<(string Thumbprint, string Subject)> NexumTrusted()
    {
        using var s = Open(OpenFlags.ReadOnly);
        return s.Certificates.Cast<X509Certificate2>()
            .Where(c => c.Subject.Contains("O=" + Certificados.Organization, StringComparison.Ordinal))
            .Select(c => (c.Thumbprint, c.Subject)).ToList();
    }
}

/// <summary>Relanzar con permisos de administrador (aviso de UAC), con la ventana del programa como dueña.</summary>
public sealed class ElevacionWindows : IElevacion
{
    /// <summary>La ventana principal (para que el aviso de UAC salga delante de ella).</summary>
    public static IntPtr OwnerWindow { get; set; }

    public bool Launch(string exe, IReadOnlyList<string> args, out string detail, out Process? process)
    {
        var psi = new ProcessStartInfo(exe)
        {
            UseShellExecute = true,
            Verb = "runas",
            Arguments = string.Join(" ", args.Select(ProcesosWindows.Quote)),
            WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.System),
            WindowStyle = ProcessWindowStyle.Hidden,
            // (con la ventana como dueña, el aviso de UAC sale delante de ella; .NET solo la pasa con ErrorDialog)
            ErrorDialog = OwnerWindow != IntPtr.Zero,
            ErrorDialogParentHandle = OwnerWindow,
        };
        try
        {
            process = Process.Start(psi);
            detail = "";
            return process != null;
        }
        catch (Win32Exception ex)
        {
            process = null;
            detail = ex.NativeErrorCode == 1223 ? "cancelado en el aviso de Windows" : ex.Message;
            return false;
        }
    }
}
