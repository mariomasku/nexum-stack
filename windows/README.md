# Nexum para Windows (preview WSL2)

Reutiliza el motor Linux y su paquete .deb. Proyectos, bases, cachés y dependencias
permanecen en el disco Linux para evitar el coste de trabajar desde /mnt/c.

Requisitos: Windows 11, WSL2 actualizado, Ubuntu con usuario y sudo, systemd y WSLg.
Si falta Ubuntu: `wsl --install -d Ubuntu`, reiniciar si se solicita y completar
usuario/contraseña. El instalador no cambia ni elimina otras distribuciones.

Desde PowerShell, en esta carpeta:

Tambien puedes hacer doble clic en `Instalar.cmd`; despues usar el acceso Nexum
Dev Stack de Inicio o `Nexum.cmd`.

Al abrir la interfaz, WSL se ejecuta sin crear consola, también cuando el lanzador
se invoca desde un `.exe` Windows sin consola. El acceso de Inicio oculta además
PowerShell; repetir Install para actualizar un acceso existente. Los comandos
Install, Run y Doctor conservan su consola interactiva.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\nexum.ps1 Install
.\nexum.ps1 Doctor
.\nexum.ps1 Open
.\nexum.ps1 Run version
.\nexum.ps1 Run instalar --php 8.4 --si
```

Install usa el acceso root que WSL concede al propietario Windows de la distribucion,
instala GTK y dependencias, construye un snapshot
LF en el disco Linux, instala el paquete de Nexum y crea acceso en Inicio. Cambia
el navegador HTTP/HTTPS y apertura de carpetas de este usuario Ubuntu para abrirlos
en Windows. No instala ninguna versión de PHP automáticamente.
En Ubuntu 26 cambia la alternativa sudo-rs por sudo clásico del propio Ubuntu:
la interfaz necesita su marcador SUDO_PROMPT para mostrar el diálogo de contraseña.
Mantiene autenticación normal y la configuración sudoers existente.

Todos los comandos del motor se pueden ejecutar mediante Run. Para trabajo diario,
usar `/opt/htdocs` con VS Code Remote WSL; no alojar datos MariaDB en C:.
Install detecta VS Code en Windows (registro e instalaciones habituales) y registra
el botón de proyectos para abrir la carpeta mediante Remote WSL en esta distribución.
Requiere la extensión WSL de VS Code. Si se instala VS Code después, repetir Install.
El botón de terminal abre una consola Windows con el motor de esta distribución.

El número `1.57.51` pertenece al motor Linux compartido (`APP_VERSION`). Esta rama
incorpora `origin/main` hasta `71377cc`. No representa una versión independiente
del port Windows. Install guarda
versión del motor y commit fuente en `/opt/nexum/windows/build-info.json`; Doctor los
muestra por separado. En paquetes sin `.git`, el commit figura como `unknown`.

Las actualizaciones del motor mantienen comprobación de firma y SHA-256. En WSL
usan el diálogo de contraseña de sudo de Ubuntu; no necesitan `pkexec` ni agente
polkit. El lanzador conserva el acompañante de hosts y certificados al reabrir
la ventana tras actualizar. Los adaptadores de ventana se instalan por separado
en `/opt/nexum/windows/window.py`, por lo que el paquete Linux no los sustituye.
Estos adaptadores dependen de la estructura de la ventana GTK del motor; cambios
incompatibles futuros requieren instalar una nueva integración Windows.

Cada tarea abre su propia pseudoterminal. La autorización previa de sudo en otra
tarea o terminal no garantiza que la actualización pueda reutilizarla; puede pedir
la contraseña otra vez. Nexum no guarda la contraseña. El adaptador mantiene sudo
como hijo de la tarea para que los motores anteriores también reconozcan su
petición y no cancelen la actualización con el aviso «no la pide sudo».

Install configura Descargas, Documentos y Escritorio de este usuario WSL con las
carpetas reales de Windows, incluidas ubicaciones movidas a OneDrive u otro disco.
Los selectores y exportaciones usan esas rutas; proyectos y BBDD siguen en Linux.
Archivos de texto sin extensión (hosts, registros) se abren con Bloc de notas.

Install establece `generateHosts=false` en la sección `[network]` de `/etc/wsl.conf`
para que WSL conserve los dominios añadidos por Nexum tras reiniciar. Si ya existe
el vhost `web.local` y WSL borró sus entradas, recupera los nombres que falten en
`/etc/hosts`; respeta entradas existentes y dominios de producción desactivados.
Guarda los ficheros anteriores en `/etc/wsl.conf.nexum.bak` y `/etc/hosts.nexum.bak`
cuando los modifica. El acompañante de Windows sincroniza después hosts y certificados.

Open solicita elevacion Windows para el acompañante de integracion. Mientras la
ventana siga abierta, revisa dominios cada tres segundos y sincroniza hosts y
certificados. El acompañante termina al cerrar el lanzador. Desde CLI, sincronizar
manualmente tras cambiar dominios, desde PowerShell administrador:

```powershell
.\nexum.ps1 Sync
```

Sync modifica exclusivamente su bloque identificado en hosts Windows y guarda copia.
Solo incluye nombres activos en hosts Linux y declarados en los virtual hosts de
Nexum. No copia claves privadas. Solo admite certificados autofirmados de servidor
con CA:FALSE, firma valida y todos sus nombres DNS mapeados. Los instala en Root
del usuario Windows y recuerda cuales añadió: al desmapear dominios retira esos
certificados, sin retirar confianza que ya existiera antes de Nexum. HTTPS Windows
requiere validacion con navegadores reales; esta preview no promete paridad completa.

Docker: habilitar explícitamente esta distribución en Settings > Resources > WSL
Integration de Docker Desktop, con contenedores Linux. Sin socket rootless existente,
Nexum usa `/var/run/docker.sock` y verifica que responde Docker Desktop para Linux.
Si falta el socket o el enlace `docker` está roto, el panel indica conexión pendiente
y permite volver a comprobarla; no ofrece instalar Docker de Ubuntu. Habilitar Ubuntu
en Docker Desktop y pulsar Apply crea la integración necesaria.
Si existe socket rootless, conserva ese motor y sus datos. No fusiona imágenes,
contenedores ni volúmenes entre motores. «Instalar Docker» reutiliza Desktop cuando
su socket está presente, sin instalar ni apagar otro motor. Sin integración Desktop,
sigue disponible la instalación rootless de Nexum.
Doctor consulta la conexión que usa el motor Nexum, además de detectar VS Code Windows;
no cambia Docker Desktop. Conexión aceptada no acredita todavía proyectos completos:
ver `COMPATIBILIDAD.md` para límites de dominios, HTTPS, permisos y sockets.

No usar wsl --shutdown para cerrar Nexum: afectaría otras distribuciones. Parar sus
servicios con `Run parar`; terminar Ubuntu solo cuando no tenga otros trabajos.

Crear ZIP portable de instalacion: `powershell -File .\empaquetar.ps1`.
Resultado en `dist/nexum-windows-<version>.zip`, junto al repositorio. Descomprimir
y ejecutar `windows/nexum.ps1 Install`. El ZIP incluye las fuentes compartidas.

Validacion local: `python windows/verify.py` desde raiz. Guarda verification.json;
abre ventana real durante 12 segundos y termina su grupo de procesos. No modifica
hosts ni confianza Windows. Pruebas del sincronizador: `sync.ps1 -WhatIf`.

Pendientes: desinstalador Windows, actualización del acompañante Windows (requiere repetir Install), pruebas de proyectos
reales y validación de todas las funciones sobre Windows.
