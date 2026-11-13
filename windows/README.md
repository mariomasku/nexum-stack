# Nexum para Windows (preview WSL2)

Reutiliza el motor Linux y su paquete .deb. Proyectos, bases, cachés y dependencias
permanecen en el disco Linux para evitar el coste de trabajar desde /mnt/c.

Requisitos: Windows 11, WSL2 actualizado, Ubuntu con usuario y sudo, systemd y WSLg.
Si falta Ubuntu: `wsl --install -d Ubuntu`, reiniciar si se solicita y completar
usuario/contraseña. El instalador no cambia ni elimina otras distribuciones.

Desde PowerShell, en esta carpeta:

Tambien puedes hacer doble clic en `Instalar.cmd`; despues usar el acceso Nexum
Dev Stack de Inicio o `Nexum.cmd`.

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

Docker: usar instalación rootless de Nexum o habilitar explícitamente integración
Ubuntu en Docker Desktop. Doctor informa de conectividad; no cambia Docker Desktop.

No usar wsl --shutdown para cerrar Nexum: afectaría otras distribuciones. Parar sus
servicios con `Run parar`; terminar Ubuntu solo cuando no tenga otros trabajos.

Crear ZIP portable de instalacion: `powershell -File .\empaquetar.ps1`.
Resultado en `dist/nexum-windows-<version>.zip`, junto al repositorio. Descomprimir
y ejecutar `windows/nexum.ps1 Install`. El ZIP incluye las fuentes compartidas.

Validacion local: `python windows/verify.py` desde raiz. Guarda verification.json;
abre ventana real durante 12 segundos y termina su grupo de procesos. No modifica
hosts ni confianza Windows. Pruebas del sincronizador: `sync.ps1 -WhatIf`.

Pendientes: desinstalador Windows, actualización coordinada del acompañante, pruebas de proyectos
reales y validación de todas las funciones sobre Windows.
