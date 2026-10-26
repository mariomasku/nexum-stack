using System.Security.AccessControl;
using System.Security.Principal;
using NexumDevStack.Core.Plataforma;

namespace NexumDevStack.Windows;

/// <summary>
/// Permisos de C:\NexumDevStack:
///   - raíz, programa, versiones, descargas y tareas: Administradores y SYSTEM (control total); Usuarios, leer
///     y ejecutar. Tu usuario no puede cambiar los programas (como las pilas de root en Linux).
///   - datos, config, htdocs, registros y tmp: solo tu usuario (modificar), Administradores y SYSTEM. Ni los
///     demás usuarios del equipo pueden leer las BBDD, las claves de los certificados ni los proyectos.
/// Sin heredar nada de C:\ (que deja crear carpetas a cualquiera).
/// </summary>
public sealed class PermisosWindows : IPermisos
{
    static readonly SecurityIdentifier Admins = new(WellKnownSidType.BuiltinAdministratorsSid, null);
    static readonly SecurityIdentifier System = new(WellKnownSidType.LocalSystemSid, null);
    static readonly SecurityIdentifier Users = new(WellKnownSidType.BuiltinUsersSid, null);
    static readonly SecurityIdentifier CreatorOwner = new(WellKnownSidType.CreatorOwnerSid, null);
    static readonly SecurityIdentifier TrustedInstaller = new("S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464");

    const InheritanceFlags Both = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;

    public void SetAdminOnly(string dir, bool usersCanRead, bool recursive = false)
    {
        var sec = new DirectorySecurity();
        sec.SetOwner(Admins);
        sec.SetAccessRuleProtection(true, false);
        sec.AddAccessRule(new FileSystemAccessRule(Admins, FileSystemRights.FullControl, Both, PropagationFlags.None, AccessControlType.Allow));
        sec.AddAccessRule(new FileSystemAccessRule(System, FileSystemRights.FullControl, Both, PropagationFlags.None, AccessControlType.Allow));
        if (usersCanRead)
            sec.AddAccessRule(new FileSystemAccessRule(Users, FileSystemRights.ReadAndExecute, Both, PropagationFlags.None, AccessControlType.Allow));
        new DirectoryInfo(dir).SetAccessControl(sec);
        if (recursive)
            ResetChildren(dir);
    }

    /// <summary>Lo de dentro solo hereda (sin permisos propios) y su dueño pasa a ser Administradores.</summary>
    static void ResetChildren(string dir)
    {
        foreach (var e in Directory.EnumerateFileSystemEntries(dir))
        {
            var attrs = File.GetAttributes(e);
            if ((attrs & FileAttributes.ReparsePoint) != 0)
                continue;
            if ((attrs & FileAttributes.Directory) != 0)
            {
                var s = new DirectorySecurity();
                s.SetOwner(Admins);
                s.SetAccessRuleProtection(false, false);
                new DirectoryInfo(e).SetAccessControl(s);
                ResetChildren(e);
            }
            else
            {
                var s = new FileSecurity();
                s.SetOwner(Admins);
                s.SetAccessRuleProtection(false, false);
                new FileInfo(e).SetAccessControl(s);
            }
        }
    }

    public void SetUserPrivate(string dir, string userSid)
    {
        var user = new SecurityIdentifier(userSid);
        var di = new DirectoryInfo(dir);
        var sec = new DirectorySecurity();
        sec.SetAccessRuleProtection(true, false);
        sec.AddAccessRule(new FileSystemAccessRule(Admins, FileSystemRights.FullControl, Both, PropagationFlags.None, AccessControlType.Allow));
        sec.AddAccessRule(new FileSystemAccessRule(System, FileSystemRights.FullControl, Both, PropagationFlags.None, AccessControlType.Allow));
        sec.AddAccessRule(new FileSystemAccessRule(user, FileSystemRights.Modify | FileSystemRights.Synchronize, Both, PropagationFlags.None,
            AccessControlType.Allow));
        di.SetAccessControl(sec);
    }

    public bool IsAdminOwned(string dir, out string detail)
    {
        try
        {
            var sec = new DirectoryInfo(dir).GetAccessControl(AccessControlSections.Owner | AccessControlSections.Access);
            var owner = sec.GetOwner(typeof(SecurityIdentifier)) as SecurityIdentifier;
            if (owner == null || !(owner.Equals(Admins) || owner.Equals(System) || owner.Equals(TrustedInstaller)))
            {
                detail = "su dueño no es Administradores: " + owner?.Value;
                return false;
            }
            const FileSystemRights write = FileSystemRights.WriteData | FileSystemRights.AppendData | FileSystemRights.WriteExtendedAttributes |
                                           FileSystemRights.WriteAttributes | FileSystemRights.Delete | FileSystemRights.DeleteSubdirectoriesAndFiles |
                                           FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;
            foreach (FileSystemAccessRule r in sec.GetAccessRules(true, true, typeof(SecurityIdentifier)))
            {
                if (r.AccessControlType != AccessControlType.Allow)
                    continue;
                var sid = (SecurityIdentifier)r.IdentityReference;
                if (sid.Equals(Admins) || sid.Equals(System) || sid.Equals(TrustedInstaller) || sid.Equals(CreatorOwner))
                    continue;
                if ((r.FileSystemRights & write) != 0)
                {
                    detail = $"{sid.Value} puede escribir en ella";
                    return false;
                }
            }
            detail = "";
            return true;
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or IOException or InvalidOperationException)
        {
            detail = ex.Message;
            return false;
        }
    }
}
