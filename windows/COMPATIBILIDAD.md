# Revisión WSL / Windows

Revisión estática sobre `feat/windows-wsl-preview`. No se han ejecutado pruebas,
Doctor, instalación ni servicios durante esta revisión. Los ajustes requieren
reconstruir e instalar la integración para llegar a la aplicación instalada.

## Ajustes incluidos

- VS Code: el instalador detecta `Code.exe` en Windows y registra un acceso que abre
  proyectos por Remote WSL, conservando distribución y ruta Linux. Rutas del proyecto
  viajan como URI y datos Base64; no se interpolan como código PowerShell.
- Docker: selección del socket rootless existente o integración Desktop de WSL.
  Se admite Desktop solo cuando el servidor se identifica como Docker Desktop/Linux.
  El instalador Docker no instala ni desactiva servicios si encuentra ese socket.
  Sin integración WSL, el panel muestra «Docker Desktop no conectado» e instrucciones
  para habilitar la distribución, en lugar de ofrecer instalar Docker en Ubuntu.
  El encabezado distingue Desktop de rootless también cuando el motor responde.
- Doctor: consulta el mismo motor Docker que usa Nexum. Antes usaba el contexto de
  `docker info`, que podía dar éxito aunque Nexum rechazara ese motor.
- Terminal: el botón abre una consola Windows con `wsl.exe`, distribución actual y
  comando Nexum. Ya no depende de GNOME Terminal dentro de WSL.
- Procedencia: Install registra versión del motor y commit fuente; Doctor muestra
  esos datos. `APP_VERSION=1.57.51` se hereda del motor Linux; no hay numeración
  independiente del port Windows.
- Actualizaciones: en WSL se usa sudo con la misma validación de firma y huella del
  ayudante Linux. Adaptadores GTK persistentes en `/opt/nexum/windows/window.py`;
  el lanzador reabre la ventana sin cerrar el acompañante Windows.
- Directorios: Install consulta Known Folders en Windows y configura Descargas,
  Documentos y Escritorio en WSL. Apertura directa de enlaces, Explorer y Bloc de
  notas mediante el puente, sin depender de las asociaciones GTK de texto.
- Entorno: las tareas conservan `WSL_DISTRO_NAME` y `WSL_INTEROP`, necesarios para
  seleccionar Docker Desktop y reconocer la distribución.

## Integración existente revisada

- Navegador y carpetas: `open.py` convierte rutas mediante `wslpath -w` y abre con
  Windows. HTTP/HTTPS y directorios tienen asociación de escritorio instalada.
- Hosts de LAMPP: acompañante sincroniza solo dominios declarados por Nexum y
  activos en `/etc/hosts`, mediante bloque propio en hosts Windows.
- Certificados LAMPP: solo exporta certificados públicos autofirmados de servidor;
  verifica restricciones y nombres. No copia claves privadas.
- Datos: proyectos y MariaDB permanecen en disco Linux. Instalar la integración no
  traslada datos a NTFS.
- Cierre: lanzador retira marcador de sesión; acompañante termina su bucle.
  Servicios Nexum siguen necesitando parada explícita, como indica el lanzador.

## Límites detectados que requieren trabajo adicional

- Docker web usa `127.0.0.2` y vhosts propios. El manifiesto Windows actual solo
  exporta hosts `127.0.0.1` y vhosts LAMPP. Los dominios Docker no se sincronizan.
- Certificado Docker contiene comodines. Política actual de confianza Windows los
  excluye; HTTPS Docker no queda resuelto con la conexión del motor.
- DNS comodín `*.docker.test` configura resolved de Linux. Windows no hereda esa
  configuración. Requiere integración DNS o publicación de dominios concretos.
- PHP-FPM antiguo y puente MariaDB LAMPP comparten sockets Unix mediante montajes.
  No se ha acreditado transporte de esos sockets entre distribución y VM Desktop.
- Contenedores PHP usan root suponiendo mapeo rootless al usuario Linux. Desktop
  necesita revisar UID/GID y permisos de escritura antes de dar paridad por válida.
- Puertos web: Linux calcula permisos con sysctl de su kernel; Desktop publica desde
  otro motor. Revisar colisiones y alcance en Windows antes de modificar ese límite.
- Actualizaciones: motor consulta releases Linux; acompañante y adaptadores Windows
  se actualizan repitiendo Install. Cambios futuros en la estructura GTK requieren
  adaptar `window.py`. Falta desinstalador Windows.
- Confianza HTTPS de navegador, reenvío localhost, Git Credential Manager y apertura
  de archivos fuera de las asociaciones instaladas siguen pendientes de validación.

Las pruebas funcionales se ejecutarán solo cuando se soliciten. Deberán cerrar todos
los procesos y servicios que creen, sin apagar otras distribuciones ni contenedores
ajenos.

## Sincronización de main · 26 noviembre 2026

Integrados 8 commits de `origin/main`, desde `f2fc14e` hasta `71377cc` (motor
1.57.51), mediante merge local en `feat/windows-wsl-preview`. Los cambios locales
Windows anteriores se conservaron; respaldo Git en el stash
`a97b53cc53d96f4ce426bb983466e0682a1d46e2`.

Conflictos de integración resueltos conservando el helper de credenciales GitHub,
el resumen nuevo de git pull y la lectura completa de sus listas para evitar
Broken pipe. El constructor de tareas conserva tanto `free` (concurrencia nueva)
como `command` (adaptador Windows). Los scripts generados se reconstruyeron desde
fuentes; el generador admite entradas CRLF y normaliza separadores de inclusiones
para Python en Windows. No se han ejecutado pruebas ni instalado estos cambios.

Próxima verificación solicitada por el usuario:

- Nginx independiente: activar pestaña, proyectos, PHP-FPM, puertos 8080/8443,
  apertura y HTTPS desde Windows.
- Docker: PostgreSQL común y Nginx común, tiendas en vivo, copias/recuperación y
  parches; mantener presentes los límites de sockets, permisos, DNS y HTTPS.
- Interfaz: cola, tareas concurrentes por proyecto, diálogos y desplegables WSLg.
- GitHub y VS Code: credenciales compartidas, resumen de pull y espacios de
  trabajo en subcarpetas con Remote WSL.
- BBDD: volcados comprimidos, creación al actualizar proyecto y borrado diferido,
  usando únicamente datos desechables.
- Copias: migración a `nexum-backups/{bbdd,proyectos,sistema}`, listas de cambios
  en `~/.nexum/listas` y actualización de phpMyAdmin.
- Actualizador: aviso al abrir/reabrir y programación periódica, sin perder los
  adaptadores Windows ni dejar acompañantes activos al cerrar.

La incorporación de código no acredita paridad funcional. Ejecutar estas pruebas
solo cuando se soliciten y terminar todos los recursos que creen.
