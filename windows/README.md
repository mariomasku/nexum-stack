# Nexum Dev Stack para Windows

Versión para Windows 11 (x64) del instalador de Linux y de macOS. Instala varias versiones de PHP, de la 7.1 a la 8.5, cada una con su propio Apache, MariaDB y phpMyAdmin, sin XAMPP. Solo una está activa a la vez.

Todo va en un solo archivo: `NexumDevStack.exe` (la ventana y los comandos de consola).

**Versión 0.1.0 (fase 1).** La lista de cambios está en «Novedades» (menú ☰ de la ventana) y en `NexumDevStack.exe novedades`.

## Qué instala

Con los binarios oficiales de Windows (no se compila nada):

| PHP | Apache | MariaDB | phpMyAdmin |
|-----|--------|---------|------------|
| 7.1 | 2.4 (Apache Lounge) | 10.11 | 5.1 |
| 7.2 a 8.2 | 2.4 (Apache Lounge) | 10.11 | 5.2 |
| 8.3 | 2.4 (Apache Lounge) | 11.4 | 5.2 |
| 8.4 | 2.4 (Apache Lounge) | 11.8 | 5.2 |
| 8.5 | 2.4 (Apache Lounge) | 12.3 | 5.2 |

- **Últimos parches:** de cada componente se instala el último parche publicado, consultado en las webs oficiales (windows.php.net, apachelounge.com, mariadb.org y phpmyadmin.net).
- **Descargas comprobadas:** todas con su sha256 y, cuando quien la publica la firma, también con su firma GPG (Apache Lounge, MariaDB y phpMyAdmin), contra las claves que lleva el programa. PHP para Windows no publica firmas: solo su sha256 por HTTPS, y la ventana lo dice.
- **PHP** va como módulo de Apache (Thread Safe), como en XAMPP, con las extensiones habituales (curl, gd, intl, mbstring, mysqli, pdo_mysql, openssl, zip, sodium, opcache…).
- **phpMyAdmin** entra como root sin contraseña, como en XAMPP, y solo desde este equipo.
- **Estado de cada rama**, según php.net: **Estable** (8.5 y 8.4), **Solo seguridad** (8.3 y 8.2, hasta la fecha que se indica) y **Sin soporte** (8.1 y anteriores, para proyectos antiguos).
- **PHP2Shell:** las 8.2.35, 8.3.36, 8.4.27 y 8.5.12 o posteriores tienen el arreglo. Las 7.x, 8.0 y 8.1 de Windows no se pueden arreglar (en Windows no se compila): salen como «Vulnerable (PHP2Shell)» en rojo y piden confirmación al activarlas.

Cada versión tarda unos minutos en instalarse (lo que tarde en descargar unos 150 MB) y ocupa unos 600 MB.

## Requisitos

- Windows 11 x64 (Windows 10 x64 también debería valer, pero no se ha probado).
- Una cuenta con permiso de administrador: Windows lo pide (aviso de UAC) para preparar `C:\NexumDevStack`, instalar o desinstalar versiones y cambiar `hosts`. Lo demás va con tu usuario.
- El **runtime de Visual C++ 2015-2026 x64** de Microsoft, que necesitan Apache y PHP. Si falta o es viejo, Nexum lo dice y lo instala (lo descarga de Microsoft y comprueba que está firmado por Microsoft).
- Los puertos 80, 443 y 3306 libres en 127.0.0.1. Si los usa otro programa (IIS, XAMPP, Skype antiguo…), Nexum dice cuál.

No hace falta instalar .NET: va dentro del `.exe`.

## Abrir el programa

El `.exe` no está firmado. La primera vez, Windows SmartScreen puede decir «Windows protegió su PC»: **Más información → Ejecutar de todas formas**.

Ábrelo normal, **sin** «Ejecutar como administrador»: Apache y MariaDB corren con tu usuario, y si el programa está abierto como administrador no los arranca.

La primera vez, la ventana ofrece **Preparar** `C:\NexumDevStack` (pide permiso de administrador una vez). Después, **Versiones de PHP → Instalar**.

## Dónde va cada cosa

| Carpeta | Qué es | De quién |
|---------|--------|----------|
| `C:\NexumDevStack\versiones\php-X.Y.Z` | Apache, PHP, MariaDB y phpMyAdmin de cada versión | administrador (tu usuario solo lee) |
| `C:\NexumDevStack\programa` | la copia del programa que se usa con permisos de administrador | administrador |
| `C:\NexumDevStack\datos\php-X.Y.Z` | las BBDD de cada versión | tu usuario |
| `C:\NexumDevStack\config` | vhosts, certificados y lo que comparten todas las versiones | tu usuario |
| `C:\NexumDevStack\htdocs` | tus proyectos | tu usuario |
| `C:\NexumDevStack\registros` | registros de Apache, PHP y MariaDB | tu usuario |
| `%LOCALAPPDATA%\NexumDevStack` | ajustes de la ventana (tema, versión activa) y registros de las tareas | tu usuario |
| `%USERPROFILE%\nexum-copias` | copias de las BBDD antes de borrarlas o sustituirlas | tu usuario |

Los programas de cada versión son de administrador para que nada que corra con tu usuario (un plugin, un script de un proyecto) pueda cambiarlos.

## La ventana

Arriba, el visor de la versión activa (si está en marcha, en verde), el botón de avisos (versiones sin soporte o vulnerables, puertos ocupados, runtime de Visual C++, certificados…), el menú ☰ (tema claro u oscuro, novedades, comandos, acerca de) y **Localhost**.

A la izquierda:

- **Proyectos:** las carpetas de `htdocs`; WordPress y PrestaShop se reconocen solos. **Cargar** apunta `https://web.local` a la carpeta con su versión de PHP y su BBDD; si algo falla o se cancela, todo queda como estaba. Las tiendas PrestaShop se abren con su dominio real falseado en `hosts`, con su vhost y su certificado. **Abrir web**, **VS Code**, **phpMyAdmin**, **Panel** (con el administrador de pruebas `local@local.test` / `local` ya escrito), **Replicar**, **Vincular BBDD** y **Desmontar**.
- **Versiones de PHP:** instalar, activar, arrancar y parar, actualizar a otro parche (**Actualizar a PHP X.Y.Z**: se instala al lado y se le copian las BBDD; la de antes no se toca hasta que la desinstales), componentes y desinstalar.
- **Bases de datos:** las de cada versión, con su tamaño. Crear, borrar (con copia), subir (`.sql`, `.sql.gz` o `.zip`, con la carga protegida: sin `DEFINER`, sin comandos del cliente y sin tocar otras BBDD), descargar y copiar a otra versión.
- **Docker:** próximamente.
- **Dominios y hosts:** los dominios falseados, su certificado y su vhost.
- **Configuración:** editar los vhosts (se comprueban con Apache antes de aplicarlos) y `hosts`, la barrera entre webs, los certificados y los registros.

Las tareas largas abren la ventana de tareas: barra de avance, «NN % · quedan unos X», el tiempo que lleva y la consola con todo lo que se hace. Se puede cancelar y guardar el registro.

## Seguridad

- Apache y MariaDB solo escuchan en `127.0.0.1` y `::1`: nadie de tu red puede entrar.
- Un nombre que no es de ningún vhost no abre nada (vhost para los desconocidos). Con la **barrera entre webs** (encendida si no la apagas), un proyecto no puede leer los ficheros de otro.
- phpMyAdmin solo desde este equipo. Apache no sirve `.env`, `.git`, volcados (`.sql`, `.gz`…) ni copias de configuración.
- `php.ini` endurecido como en Linux (sin `expose_php`, sin `allow_url_include`, errores al registro…).
- Certificados por proyecto, sin autoridad de certificación (CA:FALSE), en la raíz de confianza **de tu usuario** (Windows pregunta cada vez). Edge y Chrome los aceptan; Firefox, con `security.enterprise_roots.enabled` en `about:config`.
- **MariaDB:** root sin contraseña, como en XAMPP. Escucha solo en `127.0.0.1`, pero cualquier usuario de este equipo puede conectarse: si el equipo es compartido, ponle contraseña a root.
- El aviso de UAC protege los programas de las versiones de cambios hechos por accidente, pero no frente a un programa malicioso que ya corre con tu usuario (en Windows, UAC no es una barrera de seguridad).

## Comandos

Los mismos que en Linux, en castellano. Desde PowerShell, para ver la salida y esperar a que termine:

```powershell
.\NexumDevStack.exe estado | Out-Default
.\NexumDevStack.exe instalar 8.4 | Out-Default
.\NexumDevStack.exe usar 8.4.27 | Out-Default
.\NexumDevStack.exe --ayuda | Out-Default
```

La lista completa, en `NexumDevStack.exe --ayuda` y en el menú ☰ → Comandos.

## Lo que falta (próximas fases)

- **Docker** (pestaña «Próximamente»).
- **Correo de pruebas (Mailpit):** `mail()` va a `127.0.0.1:1025`, y hasta entonces falla.
- **Actualización firmada del programa** desde la ventana.
- Clonar proyectos con git desde **Nuevo**: de momento crea la carpeta (y, si quieres, su dominio falseado).

## Para quien lo desarrolla

C# y WPF con .NET 8, en `windows/`:

- `src/NexumDevStack.Core`: todo lo que hace el programa (catálogo, descargas y firmas, configuración de Apache, PHP y MariaDB, proyectos, BBDD, hosts, comandos), sin nada de Windows, para poder probarlo en Linux.
- `src/NexumDevStack.Windows`: procesos, permisos (ACL), UAC, certificados, puertos y registro de Windows.
- `src/NexumDevStack.App`: la ventana (WPF) y la entrada de los comandos; produce `NexumDevStack.exe`.
- `tests/NexumDevStack.Core.Tests`: pruebas (xunit) de Core.

```bash
dotnet build windows/NexumDevStack.sln
dotnet test windows/tests/NexumDevStack.Core.Tests
bash windows/empaquetar-windows.sh     # pruebas + nexum-dev-stack-windows-<versión>.zip
```

La versión está solo en `windows/Directory.Build.props`, y sus novedades en `src/NexumDevStack.Core/AppInfo.cs`. Se compila desde Linux (`EnableWindowsTargeting`); la ventana solo se puede probar en Windows: ver `PRUEBA-WINDOWS.md`.

M.Mascuñano - HEXER
