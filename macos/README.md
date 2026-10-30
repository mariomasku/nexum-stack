# Nexum Dev Stack para macOS (lvm-instalador)

Versión para Mac del instalador de Linux. Instala varias versiones de PHP en un Mac con Apple Silicon (M1 o posterior), desde la 7.4 hasta la 8.5. Cada versión trae su propia pila, sin XAMPP, y solo una está activa a la vez.

Todo va en un solo archivo: `lvm-instalador.sh`.

**Versión 1.40.2.** La lista de cambios de cada versión está en «Novedades» (menú ☰ de la ventana, menú Gestor y Configuración) y en `lvm-instalador novedades`.

## Qué instala

Cada versión de PHP tiene su pila propia, compilada en tu Mac:

| PHP | Apache | MariaDB | ProFTPD | Perl | Extra |
|-----|--------|---------|---------|------|-------|
| 7.4 | 2.4 | 10.11 | 1.3.9 | 5.40 | OpenSSL 1.1.1w e ICU 72.1 |
| 8.0 | 2.4 | 10.11 | 1.3.9 | 5.40 | OpenSSL 1.1.1w e ICU 72.1 |
| 8.1 | 2.4 | 10.11 | 1.3.9 | 5.40 | ICU 72.1 |
| 8.2 | 2.4 | 10.11 | 1.3.9 | 5.40 | |
| 8.3 | 2.4 | 11.4 | 1.3.9 | 5.40 | |
| 8.4 | 2.4 | 11.8 | 1.3.9 | 5.42 | |
| 8.5 | 2.4 | 12.3 | 1.3.9 | 5.44 | |

- **Últimos parches:** de cada componente se instala el último parche, consultado en las webs oficiales. Todas las descargas se comprueban con sha256.
- **PHP:** funciona con PHP-FPM y lleva las mismas extensiones que la versión de Linux.
- **phpMyAdmin:** entra como root sin contraseña, como en XAMPP.
- **MariaDB:** se compila, porque MariaDB no publica binarios para Mac. Es lo que más tarda.
- **OpenSSL 1.1 e ICU 72:** PHP 7.4 y 8.0 no compilan con OpenSSL 3, y PHP 7.4, 8.0 y 8.1 no compilan con las ICU modernas. Por eso estas ramas llevan OpenSSL 1.1 o ICU 72 compilados dentro, sin instalar nada en el sistema.
- **Estado de cada rama:** se consulta en php.net. **Estable** (8.5 y 8.4) recibe correcciones de errores y de seguridad y es la mejor opción para proyectos nuevos. **Solo seguridad** (8.3 y 8.2) recibe solo parches de seguridad, hasta la fecha que se indica. **Sin soporte** (8.1, 8.0 y 7.4) ya no recibe parches y es para proyectos antiguos. La ventana lo muestra como texto de color y el panel en la última columna.

Cada versión tarda unos 20-40 minutos en instalarse y ocupa unos 8 GB mientras se compila.

## Requisitos

- Mac con Apple Silicon.
- Herramientas de línea de comandos de Xcode. Si faltan, el instalador abre la ventana para instalarlas.
- Homebrew. Si falta, el instalador ofrece instalarlo.

Homebrew solo instala las **librerías** con las que se compila, nunca PHP, Apache ni MariaDB. Al terminar, esas librerías se copian dentro de cada versión (`xamppfiles/lib`). Así un `brew upgrade` o un `brew uninstall` no rompe ninguna versión ya instalada. Desde la 1.39.5 solo se instalan las que faltan, sin actualizar las que ya tienes (salvo `openssl@3`, si hay una nueva), y si no falta ninguna no se llama a Homebrew. En las versiones de macOS para las que Homebrew ya no tiene paquetes hechos (como macOS 14) las compila, y la primera vez puede tardar.

macOS trae bash 3.2 y no trae whiptail. La primera vez, el instalador instala con Homebrew `newt` (whiptail) y compila su propio **bash 5.3** (del código de GNU, con la huella sha256 de cada fichero fijada en el script) en `/Library/Nexum/gestor/bash`, de root, y se vuelve a abrir con él. Desde la 1.39.3 ya no usa el `bash` de Homebrew: es de tu usuario, y el gestor lo ejecutaba con tu contraseña de administrador.

## Instalar o actualizar con el .dmg

La forma más fácil. Abre `lvm-instalador-mac-<versión>.dmg` y haz doble clic en **Instalar Nexum Dev Stack**. Se abre Terminal y el instalador:

- lo instala (o lo actualiza) en `/Library/Nexum/gestor`, una carpeta de root: pide tu contraseña de administrador (`lvm-instalador.sh instalar-gestor`). Si ya tienes una versión más nueva, no la cambia;
- la primera vez instala lo que falte: las herramientas de Xcode (después hay que volver a abrir el instalador), Homebrew, `whiptail` y el bash del gestor (se compila en un minuto);
- si vienes de la 1.39.2 o anterior, pasa tus versiones de `/Applications` a `/Library/Nexum` ([ver abajo](#paso-a-librarynexum-1393)) y deja la copia de `~/lvm-instalador/lvm-instalador.sh` en un aviso que abre el gestor de root;
- crea (o apunta al gestor) los comandos `lvm-instalador` y `lvm` y abre la ventana, que queda en Launchpad y en `~/Applications`.

El instalador no está firmado por Apple. La primera vez, macOS no deja abrirlo: en macOS 14 o anterior, botón derecho > **Abrir** > **Abrir**; en macOS 15 o posterior, **Ajustes del Sistema > Privacidad y seguridad > Abrir igualmente**. El `LEEME.txt` del disco lo explica, junto con otra forma de lanzarlo desde Terminal.

**Crear el `.dmg`** (en un Mac, con las herramientas que trae macOS): en la carpeta donde están `lvm-instalador.sh` y `empaquetar-dmg.sh`, ejecuta `bash empaquetar-dmg.sh`. Deja `lvm-instalador-mac-<versión>.dmg` en Descargas, después de montarlo para comprobar que el instalador está bien. Desde Linux no se puede: un `.dmg` que macOS monte necesita `hdiutil`.

## Actualizar desde la ventana

Desde la 1.38.0, **menú ☰ (o menú Gestor) → Buscar actualizaciones** busca la versión nueva en las publicaciones (Releases) del repositorio `nexum-stack` en GitHub: las que traen la de Mac llevan `lvm-instalador-mac-<versión>.zip` y su firma (`.zip.sig`).

- Si hay una más nueva, la descarga a `~/.lvm-instalador/actualizaciones`, comprueba su firma y enseña su fecha y su huella SHA-256. Al aceptar (pide la contraseña de administrador), root copia el `.zip` y su firma a una carpeta suya, vuelve a comprobar ahí la firma, saca el `lvm-instalador.sh`, comprueba que es la versión del nombre y que bash lo entiende, y lo instala en `/Library/Nexum/gestor` (el mismo al que apuntan la aplicación y los comandos). La ventana se vuelve a abrir con la versión nueva. Tus versiones de PHP, tus proyectos y tus BBDD no se tocan.
- Cada versión va firmada por quien publica el programa. Sin firma válida no se instala nada desde la ventana, y tampoco una versión más vieja que la que tienes.
- Desde la 1.39.3 la firma (EdDSA, Ed25519) la comprueba el propio gestor con el Python del sistema: ya no hace falta `gpgv` de gnupg, que es de Homebrew (de tu usuario) y podría dar por buena cualquier cosa que después instalaría root. Desde la 1.39.5 tampoco para las firmas del código fuente que se compila (`lvm-instalador preparar-firma` ya no hace nada).
- Sin conexión, se sigue buscando un `lvm-instalador-mac-*.dmg` más nuevo en Descargas, como hasta la 1.36.0 (ese no va firmado: se dice de dónde se descargó y su huella, y se abre para ejecutar su instalador).
- En la terminal: `lvm-instalador actualizar-gestor ~/.lvm-instalador/actualizaciones/lvm-instalador-mac-<versión>.zip`.

Hasta la 1.36.0 la aplicación se llamaba «Gestor de versiones PHP» y hasta la 1.38.0, «Nexum Stack». La primera vez que se abre la 1.39.0, la de `~/Applications` pasa a llamarse «Nexum Dev Stack» (sale así en Launchpad y Spotlight). Si la tenías en el Dock, vuelve a ponerla: el icono antiguo apunta al nombre de antes.

## Primera instalación (sin el .dmg)

1. Descarga el repositorio (con `git clone` o el ZIP).
2. Abre Terminal en la carpeta `macos` y ejecuta:

   ```bash
   bash lvm-instalador.sh instalar-gestor
   ```

   Se instala en `/Library/Nexum/gestor/lvm-instalador.sh` (de root: pide la contraseña de administrador) y desde ahí se abre siempre; la copia descargada ya no se usa (puedes borrarla). Con `bash lvm-instalador.sh` (sin `instalar-gestor`) hace lo mismo si aún no está instalado o si la copia es más nueva.

3. La primera vez ofrece crear dos accesos:
   - **Aplicación «Nexum Dev Stack»** en `~/Applications`, con su logotipo. Sale en Launchpad y Spotlight y abre la [ventana](#la-ventana). Si la ventana no se ha podido compilar, abre el panel en Terminal, a 100×32 para que quepa el logo.
   - **Comandos `lvm-instalador` y `lvm`** en `/opt/homebrew/bin`. No necesitan sudo.
4. En el panel, elige **Instalar versiones**, marca la versión de PHP que necesites y actívala al terminar.

Si vienes de la 1.0.0 o anterior: los comandos `pvm-instalador` y `pvm` se quitan solos y se ofrecen `lvm-instalador` y `lvm`. La aplicación se rehace para que apunte al archivo nuevo, y los logs pasan de `~/.pvm-instalador` a `~/.lvm-instalador`. Las copias de bases de datos antiguas siguen en `~/pvm-copias`; las nuevas van a `~/lvm-copias`.

## La ventana

La aplicación es una ventana nativa de macOS (SwiftUI, desde macOS 12). Hace lo mismo que la ventana de Linux y no repite la lógica del instalador: ejecuta los mismos comandos que la terminal.

Desde la 1.39.0 la ventana es como la de Linux (1.54): mismas órdenes, otra organización y otro aspecto.

**Arriba, siempre a la vista:**
- El **visor** de la versión montada, en un recuadro hundido: el logotipo de PHP con su versión (y la carpeta `XAMPP-X`), **Apache** y **MariaDB** con su punto (verde y latiendo si están en marcha), el botón **Encendidos / Parados** (arranca la versión activa, o la para y desactiva como `lvm disable`) y, en la flecha, sus **servicios** (Apache, MariaDB y el FTP, con sus puertos, si se puede entrar desde la red y arrancar, parar o reiniciar cada uno; el FTP no arranca con la versión).
- A su derecha (desde la 1.39.8), el **menú ☰** (sin recuadro, con un icono en cada opción): tema claro u oscuro (se recuerda), editar los vhosts y `/etc/hosts`, volver a leer las versiones, buscar actualizaciones, el panel en Terminal, la carpeta de registros, Novedades y Acerca de.
- **Correo** (desde la 1.39.9, a la izquierda de Terminal, con el logotipo de Mailpit): abre la bandeja del [correo de pruebas](#correo-de-pruebas-mailpit) con un número verde con los correos sin leer (se pregunta a Mailpit solo con la ventana a la vista). Con el correo de pruebas apagado no sale; sin Mailpit instalado, lleva a Configuración.
- A la derecha, **Terminal** (desde la 1.40.1, en lugar de Localhost): enseña y esconde una terminal abajo de la ventana, con el aspecto del visor, un poco hundida. Es tu shell, con tu usuario, en la carpeta del proyecto cargado («Proyecto cargado» vuelve a ella; el borde de arriba se arrastra para cambiar su alto). Sirve para las órdenes de siempre (git, composer, wp-cli…), con Ctrl+C como en Terminal; no para programas a pantalla completa como vim o htop. Al esconderla sigue abierta. (phpMyAdmin, desde la 1.39.5, en Bases de datos y en el menú Gestor) y, si hay alguno, los **avisos** en un solo botón con cuántos hay (los que antes salían arriba de Versiones: protecciones, certificados, phpMyAdmin antiguo, XAMPP oficial, procesos de otras versiones…).

**A la izquierda, los apartados:**

| Apartado | Qué hay |
|---|---|
| **Proyectos** | Arriba, el **proyecto cargado** en grande (o el que pulses en la lista): su tipo (WordPress o PrestaShop), su carpeta y, en un recuadro hundido, su **entorno** (la versión de PHP o Docker; elegir otro lo carga en esa versión) y su **BBDD**, con el botón de **vincular** (se pone azul al pasar el ratón). Debajo, sus botones con logotipos: **Abrir web**, **VS Code** (si está instalado), **phpMyAdmin**, **Panel** (wp-admin o el back office, con el administrador de pruebas ya escrito) y **desmontar**; a la derecha, **Añadir entorno…** (en otra versión de PHP copiando su BBDD, como Replicar, o en Docker), el menú **⋯** (vincular, abrir la carpeta, quitarlo de Docker, vaciar la caché de la tienda) e **Importar SQL**. Debajo, la **lista** de todos los proyectos de htdocs con sus cabeceras (proyecto, BBDD y versiones donde está), que busca por el nombre de la carpeta o de su BBDD y filtra por tipo; **Cargar** sale al pasar el ratón. **Nuevo** monta un proyecto desde git |
| **Versiones de PHP** | Una tabla con cada versión: si está en marcha, su PHP, su **soporte** en php.net (**Estable**, **Solo seguridad** o **Sin soporte**, con su fecha) y su **último parche** («al día» o el que hay más nuevo). **Activar** sale al pasar el ratón; **Activa** va en azul, del mismo tamaño. En el menú ⋯ de cada una: Componentes, **Actualizar** (solo si hay un parche más nuevo; si ya está al día, lo dice), actualizar phpMyAdmin y Desinstalar. **Componentes** (Apache, MariaDB, ProFTPD, Perl y phpMyAdmin de todas, con sus logotipos) e **Instalar versión…** se abren en un diálogo |
| **Bases de datos** | Tarjetas con cuántas BBDD hay, cuántas en la versión activa, la última que ha cambiado y lo que ocupan las **copias de seguridad** de `~/lvm-copias`. Una tabla plegable por versión (desde la 1.39.5, todas plegadas al entrar y una desplegada a la vez; con una búsqueda, las que la cumplen), con el **proyecto** de cada BBDD, la **fecha exacta** de su último cambio y sus acciones: vaciar la caché (tiendas), copiar a otra versión, descargar, **cargar su proyecto** y borrar (en la activa). La BBDD que usa el proyecto cargado lleva un **punto verde**. Busca por el nombre de la BBDD o de su proyecto, y se puede ver solo la versión activa. Debajo, **Subir o actualizar una BBDD** |
| **Docker** | [Proyectos en Docker Desktop](#docker) |
| **Dominios y hosts** | Los dominios de los vhosts de `XAMPP-compartido/httpd-vhosts.conf` y si están falseados en `/etc/hosts` (llevan a este Mac). Arriba, **Host falseado**: el de la tienda PrestaShop cargada, con el interruptor encendido y **Abrir**. Debajo, el resto, con su interruptor. En medio, **Nuevo proyecto con dominio falseado** (`lvm-instalador nuevo-dominio <dominio> <carpeta> [base]`) |
| **Configuración** | Lo que se usa de vez en cuando: **Editar** los vhosts y los hosts, la **barrera entre webs**, el **Correo de pruebas (Mailpit)** (encenderlo o apagarlo, los plugins de correo de WordPress, instalar Mailpit, abrir o vaciar su bandeja), el **XAMPP oficial** (apartarlo, cargar las copias de sus bases y volver a él), las carpetas de copias y de registros, el **Registro de errores**, **Comandos de lvm-instalador**, **Novedades** y **Acerca de** |

Los botones llevan un borde gris claro que se pone azul (`#0a84ff`) al pasar el ratón.

- **Contraseña:** la de administrador se pide en una ventana, una sola vez por acción. La acción se ejecuta en una pseudoterminal (`/usr/bin/script`), así que sudo funciona igual que en Terminal.
- **Progreso:** al instalar o actualizar se ve una barra con los componentes, el tiempo y lo que queda. «Ver registro» muestra la salida completa. Si la instalación falla, el botón **Ver el log del error** abre un informe con el sistema, el compilador, el paso que ha fallado, sus primeros errores, el final de su log y, si falló la configuración, lo último de su `config.log`. **Copiar todo** lo copia para buscar la solución. El informe también se guarda como `informe-error.txt` junto a los logs de la compilación.
- **Subir o actualizar una base de datos:** se elige un fichero `.sql`, `.sql.gz` o `.zip` (con un solo `.sql` dentro, como las copias que se descargan del servidor; se lee sin descomprimirlo a disco), una base de la versión activa y se pulsa **Cargar**. La barra muestra lo cargado («134 MB de 302 MB»), el tiempo y lo que queda, como `pv`. macOS no tiene `/proc`: la posición de lectura del fichero se consulta con `lsof`. Con el botón **+** se crea una base y con la papelera se borra. Si la base ya existe, antes se borran todas sus tablas, para que no quede nada de lo anterior (tablas que la copia ya no trae, filas de una carga que falló a medias); si tiene alguna, primero se guarda una copia suya en `~/lvm-copias` (`…-antes-de-cargar-fecha.sql.gz`). Si root de MariaDB tiene contraseña, la ventana la pide. Si la copia empieza por la línea `/*M!999999\- enable the sandbox mode */` (la escribe `mariadb-dump` moderno), esa línea se quita al vuelo.
- **Descargar una base:** el botón de descarga de cada base (en la lista de su versión o en el buscador) guarda una copia `.zip` con un `.sql` dentro (estructura, datos, rutinas, disparadores y eventos), que se puede volver a cargar con «Subir o actualizar». Funciona con cualquier versión: si no está en marcha, se arranca un MariaDB temporal sin red solo para la copia, y por eso pide la contraseña de administrador.
- **Borrar una base:** si tiene tablas, avisa de que se elimina todo su contenido y es irreversible, y propone guardar antes una copia `.sql.gz` en `~/lvm-copias`, que se puede volver a cargar. Sin copia, hay que escribir el nombre de la base para confirmar. Si la copia falla, no se borra nada.
- **Menú Gestor** (en la barra de menús de macOS, además del menú ☰): abrir localhost o phpMyAdmin, volver a leer las versiones, abrir el panel en Terminal, la carpeta de registros, «Novedades» y «Buscar actualizaciones» ([más abajo](#actualizar-desde-la-ventana)).
- **Cerrar la ventana** (desde la 1.39.5): como en las demás aplicaciones del Mac, el botón rojo cierra la ventana pero la aplicación sigue abierta, con su icono en el Dock (pulsándolo vuelve la ventana). Se sale con ⌘Q o con Salir del menú.
- **Cómo se compila:** el código de la ventana va dentro de `lvm-instalador.sh`. La primera vez, y cada vez que cambia, se compila en el Mac con las herramientas de Xcode (`swiftc`, menos de un minuto) y se mete en la aplicación. Si falla, el error queda en `~/.lvm-instalador/app/compilar.log` y la aplicación sigue abriendo el panel en Terminal.
- `lvm-instalador --simular ventana` abre la ventana en modo simulación: no cambia nada.
- Si vienes de la 1.1.0 o anterior, al abrir la aplicación antigua se compila la ventana y se abre ella en lugar del panel.

## Docker

Desde la 1.39.0, como en Linux (1.53 y 1.54): proyectos con **cualquier versión de PHP** (de la 5.6 a la 8.5, también 7.1 o 7.4) en contenedores, a la vez que las versiones XAMPP-X. Cada proyecto lleva su web (Apache con PHP, desde la 1.39.2), su MariaDB (con una copia de su BBDD de una versión XAMPP-X, si quieres) y su phpMyAdmin. Se abre por el **Apache de la versión activa**, por su dominio, `<carpeta>.docker.local`, con http y https (con su certificado) y sus `.htaccess` de siempre. Su `wp-config.php` (o `parameters.php` / `settings.inc.php` de PrestaShop) se sustituye **solo dentro del contenedor**: el del proyecto no cambia y la carpeta se puede seguir usando con XAMPP-X. El Apache de la versión activa le pasa la web entera (con sus `.htaccess`, que lee el Apache del contenedor).

- **Docker Desktop:** en el Mac no hay Docker sin root como en Linux; Docker es **Docker Desktop**, que mete los contenedores en su máquina virtual, apartados del Mac. No se instala desde aquí: **Instalar Docker…** explica cómo y abre su página de descarga (se instala como cualquier aplicación, arrastrándola a Aplicaciones, y la primera vez pide aceptar su licencia). Si está instalado y parado, **Abrir Docker Desktop** lo abre y espera a que responda (`lvm-instalador docker-instalar`). El gestor usa su `docker` (`/usr/local/bin/docker` o el de la aplicación) y su socket (`~/.docker/run/docker.sock` o `/var/run/docker.sock`).
- **Carpetas compartidas:** Docker Desktop solo deja a los contenedores usar las carpetas de su lista, y `/Library` no está. Añade `/Library/Nexum/XAMPP-compartido/htdocs` en **Settings › Resources › File sharing** y pulsa Apply. Si no, al crear un proyecto Docker dice «mounts denied». Si vienes de la 1.39.2 o anterior (tenías `/Applications/XAMPP-compartido/htdocs`), añade la nueva y vuelve a arrancar tus proyectos en Docker: su `compose.yaml` ya usa la ruta nueva.
- **La web del contenedor, con clave (desde la 1.39.2):** en Linux, Apache habla con el contenedor por un socket de una carpeta solo tuya. En el Mac no se puede: las carpetas compartidas de Docker Desktop (VirtioFS o gRPC FUSE) pasan ficheros, no sockets. Hasta la 1.39.1 cada proyecto publicaba su **PHP-FPM** en `127.0.0.1:<puerto>`, y FastCGI no pide nada: cualquier programa del Mac (y otro contenedor, por `host.docker.internal`) podía ejecutar PHP con `PHP_VALUE`. Ahora no hay PHP-FPM: en el puerto (desde el 29000, `PUERTO_WEB` en su `proyecto.conf`) está la **web del contenedor** (Apache con PHP, como `www-data`, con el `php.ini` de producción y los límites contra PHP2Shell), que solo responde a las peticiones con **la clave del proyecto** (`X-Nexum-Key`) y su dominio. La clave la pone el vhost con `Include "/Library/Nexum/XAMPP-compartido/docker-claves/<nombre>.conf"` (hasta la 1.39.2, en `/Applications/XAMPP-compartido`), un fichero de root que solo lee root (los vhosts los puede leer cualquiera). Las reglas que no sirven `.env`, `.git` o copias de BBDD van también en el Apache del contenedor.
- **Proyectos de antes:** se cambian solos al arrancarlos (o con **Cerrarlo**, en el aviso rojo del apartado Docker, o `lvm-instalador docker-migrar --todos`). Su BBDD (el volumen), su configuración, su dominio y su puerto se quedan; lo de antes queda en `~/.lvm-instalador/docker/<nombre>/antes-esquema-2` y, si algo falla, se deja como estaba.
- **phpMyAdmin del contenedor:** desde la 1.39.2 pide usuario y contraseña (antes entraba solo como root, y cualquier programa del Mac podía abrirlo). La llave de su fila enseña y copia la contraseña (`lvm-instalador docker-clave <nombre>`). Las contraseñas ya no van en las órdenes (`ps`): las lee el contenedor de su entorno.
- **Actualizar imagen** (las flechas de su fila, o `lvm-instalador docker-imagen <nombre>`): vuelve a descargar la imagen oficial de su PHP con sus últimos parches (`--pull --no-cache`) y rehace su contenedor de PHP. Las imágenes oficiales de PHP 8.1 y anteriores ya no reciben parches: siguen siendo vulnerables a PHP2Shell.
- **Botón Docker del proyecto cargado** (después de Panel): si no está en Docker, lo monta (PHP de la versión activa, su MariaDB y su BBDD, que puedes cambiar); si está, lo arranca y abre el apartado Docker; con varias versiones, pregunta cuál. La misma carpeta puede ir en Docker con varias versiones de PHP (`docker-crear ... --nombre <carpeta>-php84`).
- **El apartado Docker** (como Docker Desktop): tarjetas con el uso de **CPU** y **memoria** de los contenedores (sobre los núcleos y la memoria de la máquina virtual) y cuántos están **en marcha**; pestañas **Contenedores**, **Imágenes** y **Volúmenes**, con buscador y «solo en marcha». En Contenedores, una fila por proyecto (se pliega al pulsarla) con su versión de PHP (pulsándola se cambia), su estado (letras verdes y un punto que late), el puerto de su phpMyAdmin, su CPU y sus acciones: abrir la web, phpMyAdmin, **parar** (rojo) o **arrancar** (verde), registros y eliminar; debajo, cada contenedor con las suyas (parar o arrancar, reiniciar, registros y eliminar). **Proyecto en Docker…** crea uno: carpeta, PHP, MariaDB, la BBDD que se copia y su dominio. En Imágenes, cada una con su etiqueta y su ID, y botones para **volver a descargarla** de Docker Hub (las `nexum-*` se rehacen con «Actualizar imagen») o **borrarla** si no la usa ningún contenedor; en Volúmenes, **borrar** los que no use ninguno.
- **Cambiar de PHP** solo cambia su contenedor de PHP: su BBDD, su phpMyAdmin y su configuración se quedan. Si con la nueva no arranca, vuelve a la de antes.
- **La BBDD de XAMPP-X en vivo (WordPress, desde la 1.40.1):** un proyecto de Docker puede usar la BBDD de cualquier versión de XAMPP-X, la misma que web.local, sin copias: lo que cambias en un lado se ve en el otro. Se elige al montarlo (**Cómo: en vivo**) o después, con el botón de las flechas de su fila (`lvm-instalador docker-bd <nombre> lampp <versión> | docker`). El contenedor entra con el usuario y la contraseña del `wp-config.php` del proyecto. Si la MariaDB de esa versión no está en marcha, se arranca solo ella, con tu usuario y en otro puerto de `127.0.0.1` (del 3310 en adelante), sin chocar con la de la versión activa. Como Docker Desktop no llega a los sockets del Mac, un contenedor puente (`nexum-lampp-bd-<versión>`, «Puente a la BBDD de XAMPP-… (en vivo)» en la pestaña Docker) lleva las conexiones a `host.docker.internal:<puerto>`. Si activas esa versión en XAMPP-X, su MariaDB pasa a la de siempre (3306) y el puente se rehace solo. Se para cuando ningún proyecto de Docker la usa. Las tiendas PrestaShop siguen con su copia: guardan su dominio en la BBDD, y una misma BBDD no puede servir a web.local y a Docker a la vez.
- **Imágenes de web.local:** las imágenes y enlaces que un WordPress guardó trabajando con XAMPP-X (`https://web.local/wp-content/...`) salen del contenedor, cambiados al vuelo en lo que devuelve la web. La BBDD no se toca.
- **Menos memoria con varios proyectos a la vez:** el Apache con PHP de cada contenedor espera con un solo proceso (no con cinco), y el Apache de Docker con uno (no con tres).
- **Los proyectos sin visitas se paran solos** (Configuración, Docker): uno que lleva las horas elegidas (3 de partida, de 1 a 24 o nunca) sin ninguna visita, tampoco por el túnel, se para, y con él lo común que ya no use nadie. Lo comprueba un LaunchAgent tuyo cada 15 minutos, también con la ventana cerrada (`lvm-instalador docker-reposo`). Al entrar en uno parado, la web lo dice.
- Los contenedores **no arrancan solos** al encender el Mac (`restart: "no"`): se arrancan desde el apartado Docker.
- En la terminal: `lvm-instalador docker-crear <carpeta> <php> <mariadb> [--bd <base> --desde <versión>] [--dominio <d>]`, `docker-php <nombre> <versión>`, `docker-arrancar|docker-parar|docker-registros|docker-borrar <nombre>` `docker-contenedor arrancar|parar|reiniciar|registros|borrar <contenedor>`, `docker-imagenes borrar <ID|imagen:etiqueta> | descargar <imagen:etiqueta>` y `docker-volumen-borrar <volumen>`. Cada proyecto queda en `~/.lvm-instalador/docker/<nombre>` (`compose.yaml`, `proyecto.conf` y las contraseñas en `.env`, solo tuyos).

## Repositorios (GitHub)

- **La pestaña Repositorios** (como DevHub): la lista de los repositorios de la organización o cuenta de GitHub que se elija en Configuración, solo los que empiezan por los **prefijos** (de partida `dob-wordpress-` y `dob-prestashop-`; se añaden otros cuando haga falta) o todos con **Mostrar todos**, y un buscador. La lista de la última vez sale al momento y se lee de nuevo de GitHub por detrás.
- **Clonar** lo clona por SSH, con tu clave, en la carpeta de proyectos. Si ya está clonado en un proyecto, **Traer cambios** pregunta si aplastarlo y hace `git pull`; si choca con lo que tienes sin subir, no se toca nada y se dice. El logotipo de GitHub de cada fila abre el repositorio en GitHub.
- **La conexión** (Configuración, GitHub): un token de GitHub, que se guarda en el **Llavero** (no en un fichero), o la sesión de `gh`. La organización se puede escribir también como su dirección (`https://github.com/hexer-dev`). En Terminal: `lvm-instalador github`, `github-conectar`, `repos` y `repo-traer`.

## Túnel de Cloudflare

- **Compartir** (en el visor del proyecto) abre una dirección `https://….trycloudflare.com` para enseñar la web a un cliente, sin cuenta de Cloudflare ni abrir puertos. Al pulsarlo se elige cuánto dura (de 1 a 12 horas) y si se bloquea el panel de administración. Cada túnel lleva una **contraseña nueva al azar**, que se ve al abrirlo para copiarla. En Configuración quedan cloudflared, el túnel abierto y su registro.

## Parches nuevos

- En Configuración, **Parches nuevos** dice qué tiene un parche publicado: cada versión XAMPP-X (PHP, Apache, MariaDB, ProFTPD, Perl y phpMyAdmin), las imágenes de Docker (MariaDB comunes, phpMyAdmin y PHP, frente a Docker Hub), Mailpit y cloudflared. **Actualizar todo** lo pone al día. Se busca al abrir la ventana el primer arranque del día y cada pocos arranques. Las versiones `XAMPP-X.Y.Z` llevan su parche en el nombre: la nueva se instala a su lado. En Terminal: `lvm-instalador componentes` y `componentes-actualizar`.

## Correo de pruebas (Mailpit)

Desde la 1.39.9, como en Linux (1.55): lo que mandan las webs de este Mac (formularios de contacto, pedidos, contraseñas olvidadas) **no llega a nadie**. Con las BBDD copiadas de los clientes, un pedido de prueba avisaría al cliente real; ahora va a [Mailpit](https://github.com/axllent/mailpit) (MIT), que lo guarda y lo enseña en su bandeja, `http://127.0.0.1:8025/` (botón **Correo**, arriba). Está **encendido por defecto** y se apaga en **Configuración → Correo de pruebas (Mailpit)** o con `lvm-instalador correo no`.

- **Instalar Mailpit** (Configuración, o `lvm-instalador correo instalar`): se descarga la versión fijada (1.32.0) de GitHub para Mac (Apple Silicon o Intel), se comprueba con su **sha256** y su firma (`codesign`) y se copia **de root** en `/Library/Nexum/mailpit` (como el gestor: ni tu usuario ni una web pueden cambiar el programa que ejecuta PHP al mandar un correo). Pide la contraseña de administrador. curl no le pone la cuarentena; por si acaso se le quitan los atributos extendidos.
- **Mailpit arranca y para con la versión activa** (montar, arrancar, parar, desactivar, un servicio, cargar un proyecto y, si se ha cerrado, la ventana cada 20 s), **con tu usuario** (nunca como root), con el entorno limpio y **solo en 127.0.0.1**: SMTP en el puerto 1025 y su web en el 8025, que solo responde a `127.0.0.1:8025` y `localhost:8025` (otra web cuyo dominio lleve a 127.0.0.1 no puede leer los correos). Guarda como mucho 500 correos en `~/.lvm-instalador/mailpit` (solo tuya). Se arranca apartado de la terminal de la tarea (sin quedarse con ella), así que la ventana no se queda esperando.
- **PHP de todas las versiones:** `mail()` va al `sendmail` de Mailpit (`php/etc/conf.d/99-lvm-correo.ini` de cada versión, solo si el programa es de root hasta `/`). Apagado, ese fichero se queda sin directivas.
- **PrestaShop:** al cargar la tienda o su BBDD, su correo va por SMTP a Mailpit (127.0.0.1:1025, sin usuario ni cifrado), en todas sus tiendas.
- **WordPress con plugins de SMTP o Brevo** (WP Mail SMTP, Easy WP SMTP, Post SMTP, FluentSMTP, Brevo…), con tres opciones en Configuración (`lvm-instalador correo wordpress mailpit|desactivar|nada`):
  - **Llevarlos a Mailpit** (por defecto): los de SMTP siguen funcionando, pero su correo va a Mailpit (un fichero de root, `etc/lvm-correo-wordpress.php`, que PHP carga antes de cada script); los que mandan por una API (Brevo, FluentSMTP, Post SMTP…) se desactivan en la copia local.
  - **Desactivarlos en la copia local:** todos fuera; WordPress manda con `mail()`, a Mailpit.
  - **No tocarlos:** como en producción. Avisa: lo que manden puede llegar de verdad a los clientes.
- **Las copias no llevan los cambios:** lo que se cambia en una BBDD se apunta (con lo de antes) en su tabla `lvm_correo_original`. `exportar-bd`, `copiar-bd` y las BBDD que se copian a Docker van sin esa tabla y con el correo de producción. Al apagarlo o elegir «No tocarlos», se deshace al cargar el proyecto.
- **Docker:** sus proyectos aún no mandan a Mailpit (Docker Desktop podría llegar a `host.docker.internal:1025`, pero Mailpit solo escucha en 127.0.0.1); queda para más adelante.
- En el proyecto cargado, al lado de «PROYECTO CARGADO», sale **«su correo va a Mailpit»**.
- En la terminal: `lvm-instalador correo` (estado), `correo si [--instalar] | no`, `correo wordpress mailpit|desactivar|nada`, `correo instalar`, `correo vaciar` y `correo bd <base>` (aplica o deshace el correo de pruebas en una BBDD; se hace solo al cargarla). Los ajustes, en `~/.lvm-instalador/correo-apagado` (si existe, apagado) y `~/.lvm-instalador/correo-wordpress`.

## Puesta a punto de seguridad (Mac nuevo o tras actualizar)

Haz esto una vez al instalar el gestor en un Mac, y cada vez que la ventana muestre un aviso naranja. Cada paso pide la contraseña de administrador.

1. **Instala o actualiza** con el `.dmg` (ver arriba). Si no compila, pasa `~/.lvm-instalador/app/compilar.log` a quien te dio el programa.
2. **Abre la ventana y pulsa el botón de avisos** (el triángulo naranja con un número, arriba a la derecha). Salen los avisos pendientes, cada uno con su botón. Púlsalos de arriba abajo:

   | Aviso | Qué pasa si no lo arreglas | Botón |
   |---|---|---|
   | **A algunas versiones les faltan protecciones** | Les falta algo de lo que pone el gestor: arrancadas a mano escucharían en toda la red, con MariaDB sin contraseña; la clave SSL de fábrica de XAMPP (igual en todos); MariaDB arrancando como root; desde la 1.29.0, phpMyAdmin cerrado a otras webs y MariaDB sin acceso a los ficheros del Mac. Sale también tras actualizar el gestor, si la versión nueva añade protecciones. Si una versión no es de root, Protegerlas no la toca y dice cómo volver a instalarla. | **Protegerlas** |
   | **Tablas del sistema de MariaDB antiguas** | Las tablas del sistema de MariaDB (`mysql.*`) son de una versión anterior y el servidor llena su registro de errores sin parar (en una 8.2.4 llegó a 28 GB y casi llena el disco). | **Repararlas** (la versión tiene que estar en marcha; no toca las BBDD de los proyectos y guarda antes una copia en `~/lvm-copias`) |
   | **phpMyAdmin antiguo** | El phpMyAdmin de XAMPP tiene fallos de seguridad corregidos después. | **Actualizarlos** |
   | **Certificados en los que confía todo el Mac** | Los certificados https de los proyectos son de CA o los firma una CA tuya sin límite de dominios (como la de `mkcert`): con su clave, el PHP de una web podría falsificar cualquier web real (tu banco) en este Mac. | **Arreglarlos** |
   | **El navegador avisa al abrir estos proyectos** (desde la 1.34.0) | Safari y Chrome no aceptan todavía el certificado propio de los proyectos con dominio de pruebas (como `web.local`): sale «La conexión no es privada» y las herramientas que manejan el navegador, como **Claude in Chrome**, no pueden abrirlos. | **Confiar** (el Mac pide tu contraseña una vez por proyecto; después cierra Chrome del todo, Cmd+Q, y vuelve a abrirlo) |

   Cuando no queda ningún aviso, el Mac está al día.
3. **Después de Arreglarlos**, pulsa **Confiar** en el aviso «El navegador avisa al abrir estos proyectos»: el navegador aceptará sin aviso los proyectos con dominio de pruebas (`web.local`, `.local`, `.test`). Desde la 1.35.0, las tiendas con dominio real también, pero **solo mientras están falseadas** en `/etc/hosts`: al falsear una, sale en ese aviso (pulsa **Confiar**); al dejar de falsearla o cargar otro proyecto, el navegador deja de aceptarlo (el Mac pide tu contraseña). Es a propósito: Apache corre con tu usuario y tiene su clave en memoria, donde la puede leer el PHP de cualquier web, y con ella se podría suplantar la web de verdad; mientras está falseada, el navegador no va a ella. Si cambias `/etc/hosts` a mano o cancelas la contraseña, sale el aviso «El navegador acepta webs reales que ya no están falseadas»: pulsa **Quitar** (o `lvm-instalador confiar-certificados --quitar`).
4. **Si tenías una CA propia**, Arreglarlos la quita de los llaveros y te dice dónde está su clave privada. Bórrala, o guárdala cifrada fuera de tu carpeta personal. No vuelvas a instalar una CA así.
5. **Para ver antes qué haría**, en la terminal: `lvm-instalador --simular asegurar --todas` y `lvm-instalador --simular arreglar-certificados`.

Lo que no cambia, a propósito: MariaDB con root sin contraseña y Apache con tu usuario. No cargues proyectos ni volcados de origen dudoso.

## Uso diario

Abre «Nexum Dev Stack» desde Launchpad o Spotlight, o usa la terminal.

Comandos:

```bash
lvm-instalador                         # panel
lvm-instalador instalar --php 7.4,8.4  # instalar sin panel (--si para no preguntar)
lvm-instalador use 8.4                 # activar una versión
lvm-instalador estado                  # versiones instaladas
lvm-instalador list-db                 # bases de datos de cada versión
lvm-instalador actualizar 8.4          # recompilar con los últimos parches de su rama (si ya está al día, avisa en verde y no hace nada)
lvm-instalador desinstalar 7.4         # --copia guarda antes sus bases en ~/lvm-copias
lvm-instalador desactivar              # parar la activa y quitar el enlace
lvm-instalador ventana                 # abrir la ventana
lvm-instalador arrancar                # la versión activa (también parar y reiniciar)
lvm-instalador importar-bd copia.sql mi_web    # cargar una copia en la versión activa (también .sql.gz y .zip)
lvm-instalador importar-bd copia.sql nueva --crear   # creando la base; si ya existe, se vacía antes (con copia)
lvm-instalador crear-bd mi_web         # crear una base vacía en la versión activa
lvm-instalador cargar-proyecto mi-web 8.4   # web.local -> htdocs/mi-web (y activa la 8.4)
lvm-instalador montar-proyecto https://github.com/yo/mi-web.git mi-web 8.4 wp_mi_web [copia.sql]   # clonar, cargar y crear su BBDD
lvm-instalador desmontar-proyecto           # web.local enseña una página vacía
                                            # tienda PrestaShop: vhost, certificado y dominio falseado
lvm-instalador hosts-falsear mitienda.com si # falsea (o «no»: deja de falsear) un dominio de los vhosts
lvm-instalador borrar-bd mi_web --copia   # borrarla guardando antes una copia
lvm-instalador vhosts                  # editar httpd-vhosts.conf de la versión activa (después, reiniciar)
lvm-instalador hosts                   # editar /etc/hosts (sudo -e)
lvm-instalador exportar-bd mi_web ~/Downloads/mi_web.zip [8.4]   # descargar una copia (con el correo de producción)
lvm-instalador correo                  # correo de pruebas: estado (también si, no, instalar, vaciar)
lvm-instalador correo wordpress nada   # plugins de correo de WordPress: mailpit, desactivar o nada
lvm-instalador version                 # versión del instalador
lvm-instalador acerca                  # qué hace y lista de cambios
lvm-instalador --simular               # panel sin hacer ningún cambio
```

## Carpetas (al estilo XAMPP para Mac)

| Ruta | Qué es |
|------|--------|
| `/Library/Nexum/gestor` | El gestor (`lvm-instalador.sh`) y su `bash`, de root (desde la 1.39.3) |
| `/Library/Nexum/XAMPP-8.4.27/xamppfiles` | Versión 8.4.27: Apache, PHP, MariaDB, ProFTPD, Perl, phpMyAdmin (hasta la 1.36, `XAMPP-8.4`; desde la 1.38 cada versión va con su número completo; hasta la 1.39.2, en `/Applications`) |
| `/Applications/XAMPP` | Enlace a la versión activa |
| `/Applications/XAMPP/xamppfiles/xampp` | Arranque y parada (mejor con `lvm-instalador arrancar\|parar\|reiniciar`, que comprueba la versión antes de ejecutarla como root) |
| `/Applications/XAMPP/xamppfiles/bin` | `php`, `mysql`, `mysqldump`, `perl`… de la versión activa |
| `/Library/Nexum/XAMPP-compartido/htdocs` | Proyectos, compartidos por todas las versiones |
| `/Library/Nexum/XAMPP-compartido/httpd-vhosts.conf` | Virtual hosts, compartidos por todas las versiones |
| `/Applications/XAMPP-compartido`, `/Applications/XAMPP-X.Y.Z` | Solo si vienes de la 1.39.2 o anterior: enlaces a las de `/Library/Nexum`, para tus rutas de siempre (el gestor y root no pasan por ellos) |
| `/Library/Nexum/mailpit` | Mailpit (correo de pruebas), de root (desde la 1.39.9) |
| `~/lvm-copias` | Copias de las bases de datos (al desinstalar o actualizar) |
| `~/.lvm-instalador` | Logs de cada instalación (y, en `mailpit`, los correos de Mailpit) |

En los vhosts, usa como ruta de los proyectos `/Applications/XAMPP/xamppfiles/htdocs/...`, que siempre apunta a la carpeta compartida.

**Editar vhosts** (menú Gestor, debajo de Abrir phpMyAdmin): abre `/Library/Nexum/XAMPP-compartido/httpd-vhosts.conf`, el fichero real que comparten todas las versiones (en cada una, `xamppfiles/etc/extra/httpd-vhosts.conf` es un enlace a él), con el editor de textos de macOS. Funciona aunque no haya versión activa. El fichero es del administrador (Apache lo lee como root): se edita una copia y, al pulsar **Aplicar**, se comprueba y se escribe con la contraseña de administrador (ver más abajo). Después de guardar, **Reiniciar** aplica los cambios.

**Si el Mac ya tiene un XAMPP oficial** en `/Applications/XAMPP`: instalar la app y las versiones de PHP no lo toca (cada versión va en su carpeta, con sus bases vacías). Para **activar** una versión hay que **apartarlo** (botón de avisos, Configuración o `lvm-instalador apartar`), y eso no borra nada:

1. Lo para. Si algo sigue en marcha, no se mueve nada.
2. Copia **todas sus bases de datos** en `~/lvm-copias/XAMPP-oficial-<fecha>`, una `.zip` por base. Usa un MariaDB suyo temporal y sin red, así que da igual que root tenga contraseña. Si falla alguna, se detiene y el XAMPP se queda donde estaba.
3. Copia sus **proyectos** de `htdocs` a `/Library/Nexum/XAMPP-compartido/htdocs` (en APFS la copia es instantánea y no ocupa espacio). Si ya hay algo con el mismo nombre, no lo pisa y lo avisa.
4. Añade sus **vhosts** al fichero compartido. Como sus rutas son `/Applications/XAMPP/xamppfiles/htdocs/...`, siguen valiendo. Si Apache no los acepta, deja el fichero como estaba y lo avisa (la copia queda en la carpeta de las bases).
5. Lo mueve a `/Applications/XAMPP-oficial-<fecha>`, con todo lo suyo.

Después: activa una versión y, en **Configuración → XAMPP oficial**, pulsa **Cargar en XAMPP-X.Y** (`lvm-instalador importar-copias <carpeta>`). Las bases que ya existan en esa versión no se tocan. Si algo no va, **Volver al XAMPP oficial** (Configuración o `lvm-instalador volver-oficial`) para y desactiva la versión del gestor, devuelve el XAMPP a `/Applications/XAMPP`. Después arráncalo desde su panel (manager-osx): el gestor no ejecuta su script como administrador.

**Editar hosts** (menú Gestor): abre una copia de `/etc/hosts` en el editor de textos. Al pulsar **Aplicar**, guarda el `/etc/hosts` actual en `~/lvm-copias`, escribe el nuevo con la contraseña de administrador y vacía la caché de DNS. No deja guardar uno sin la línea de `localhost`, ni añadir dominios que lleven a otro equipo (solo a `127.x` o `::1`; para eso, en la terminal: `lvm-instalador hosts`).

**Editar vhosts** (menú Gestor): los vhosts (`XAMPP-compartido/httpd-vhosts.conf`) son del administrador, porque Apache los lee como root al arrancar. Se abre una copia en el editor de textos. Al pulsar **Aplicar**, se comprueba que solo lleva directivas de vhosts (nada de `LoadModule`, `Include`, `Listen` ni registros con `|orden`), se guarda la anterior en `~/lvm-copias`, se escribe con la contraseña y Apache la prueba: si no la acepta, se deja como estaba; si la acepta, se recarga Apache. En la terminal: `lvm-instalador vhosts`.

**Cargar proyecto:** en Proyectos, pulsa **Cargar** en el proyecto; o en Bases de datos, el botón de carpeta de una BBDD (cargar su proyecto). La ventana busca en `/Library/Nexum/XAMPP-compartido/htdocs` la carpeta cuya configuración usa esa base (`wp-config.php`, la de PrestaShop o `.env`), la carga directamente en la versión de ese resultado (un punto verde marca los de la versión activa) y apunta el enlace del vhost (el `DocumentRoot` de `httpd-vhosts.conf`, por ejemplo `web.local`) a esa carpeta. Si `httpd-vhosts.conf` no tiene ninguno (como al instalar la primera versión, que lo crea vacío), al cargar el primer proyecto se crea `web.local`: sus vhosts http y https (sin caché en el navegador), su certificado autofirmado en `/Library/Nexum/XAMPP-compartido/ssl` y sus líneas en `/etc/hosts` (IPv4 e IPv6, para que `.local` no tarde buscándolo por Bonjour). La ventana lo avisa antes de cargar y pide la contraseña de administrador. Si no la encuentra o hay varias, eliges tú y se recuerda para esa base. Si la versión del resultado no es la activa, avisa de que se cambia de versión de PHP, para la que está en marcha y activa la del proyecto. Si no cambia de versión, recarga Apache y PHP-FPM (recarga suave), porque PHP recuerda durante 120 s adónde apuntaba el enlace y seguiría sirviendo el proyecto anterior.

**Bases de datos:** cada versión tiene las suyas, que empiezan vacías. Para pasar una base de una versión a otra, expórtala desde phpMyAdmin con una versión activa y cárgala con la otra desde la ventana («Subir o actualizar una base de datos») o con `lvm-instalador importar-bd`. En el panel de Terminal, la opción **Bases de datos** también permite ver, cargar, crear y borrar; el fichero se elige en una ventana de Finder.

**Puertos:** web 80 y 443, MariaDB 3306 y FTP 21. Si el Apache que trae macOS está en marcha y ocupa el puerto 80, `xampp start` lo avisa; se para con `sudo apachectl stop`.

**Usuarios:** Apache, PHP-FPM y MariaDB funcionan con tu usuario del Mac. Al FTP entras con tu usuario y tu contraseña del Mac, y solo ves htdocs.

**Solo desde este Mac:** Apache escucha en `127.0.0.1` y `::1`, MariaDB en `127.0.0.1` y el FTP en `127.0.0.1`. Ningún otro equipo de la red (la de la oficina o una wifi pública) llega a los proyectos, a las bases ni al FTP. Las versiones instaladas antes de la 1.16.0 se cierran solas al montarlas o arrancarlas (o con **Cerrar a la red** en los servicios del visor de arriba, o `lvm-instalador asegurar`).

## Paso a /Library/Nexum (1.39.3)

Hasta la 1.39.2, lo que se ejecutaba con tu contraseña de administrador salía de ficheros que podía cambiar cualquier programa de tu usuario: el script (`~/lvm-instalador`), los comandos y el `bash` de Homebrew (`/opt/homebrew`), y las versiones en `/Applications`, donde puede escribir el grupo `admin`. Las comprobaciones (versión de root, sin enlaces…) se hacían antes y root volvía a resolver las rutas después, así que se podía cambiar una carpeta por otra entre medias. Desde la 1.39.3:

- **El gestor, en `/Library/Nexum/gestor`, de root:** `lvm-instalador.sh` y un `bash` 5.3 propio, compilado como root en el Mac del código de GNU (la huella sha256 de cada fichero va en el script). Los comandos `lvm-instalador` y `lvm` y la aplicación de `~/Applications` lo abren siempre a él (la ventana lleva la ruta fija; no la toma de su `Info.plist`). Una copia en otra carpeta (la del `.dmg`, una descargada, la de `~/lvm-instalador`) no ejecuta nada como root: abre la instalada o, si es más nueva, se instala (`instalar-gestor`).
- **Con el entorno limpio:** el gestor se vuelve a lanzar con su `bash` y solo las variables que necesita (sin `BASH_ENV`, `SHELLOPTS`, funciones exportadas ni `DYLD_*`), con los programas del sistema primero en el PATH. Las rutas de Homebrew van fijas (ya no se ejecuta la salida de `brew shellenv`).
- **Como root, solo programas del sistema o de `/Library/Nexum`:** `sudo` no ejecuta nada de Homebrew, de tu carpeta ni de `/Applications`. Los de `/Library/Nexum` los vuelve a comprobar root justo antes de ejecutarlos (el programa y cada carpeta hasta `/`, de root y sin escritura para otros ni enlaces). Como root, `HOME=/var/root` (no se leen `~/.my.cnf` ni `~/.curlrc` tuyos).
- **Las versiones y `XAMPP-compartido`, en `/Library/Nexum`:** `lvm-instalador migrar` (lo hace solo el instalador del `.dmg` y la primera vez que se instala el gestor) para lo que esté en marcha, las mueve con sus BBDD, cambia sus rutas (configuración, scripts, enlaces y las librerías de sus programas, con `install_name_tool` y la firma local otra vez), fija el `php.ini`, el `conf.d` y el `extension_dir` de PHP-FPM y las comprueba. Si algo falla, lo deja todo como estaba. En `/Applications` deja un enlace a cada una, para tus rutas de siempre (el IDE, `wp-config.php`, la caché de PrestaShop); root no pasa por ellos. Las versiones que siguen en `/Applications` ya no se arrancan como administrador: salen en Avisos («Protegerlas» las pasa).
- **Al instalar una versión,** root comprueba que sus programas solo cargan librerías suyas o del sistema (nunca de `/opt/homebrew`, que es de tu usuario).
- **Actualizaciones:** root las comprueba (firma, contenido y versión) en una carpeta suya antes de instalarlas en `/Library/Nexum/gestor`.

**Lo que sigue igual (límites):**

- **La compilación usa Homebrew**, que es de tu usuario: sus librerías, cabeceras, `cmake` y `pkgconf` (desde la 1.39.5, ya no `gpgv`: las firmas las comprueba el gestor). Un programa tuyo que cambiara Homebrew antes de instalar o actualizar una versión podría meter algo en lo que se compila, y root lo copiaría (comprueba enlaces, enlaces duros, setuid y de dónde carga librerías, pero no puede saber si un programa compilado es el bueno). Compilar con un usuario aparte (como en Linux, `nexum-build`) no lo arreglaría en el Mac, porque las herramientas de Homebrew seguirían siendo tuyas. Instala y actualiza versiones cuando no estés ejecutando programas de origen dudoso.
- **La aplicación de `~/Applications` y su ejecutable (`~/.lvm-instalador/app`) son de tu usuario:** la ventana no ejecuta nada como root por sí misma (ejecuta el gestor de root, que pide sudo), pero la contraseña la escribes en su panel. Un programa tuyo podría cambiarla por una que se la quedara, igual que podría enseñarte un panel falso o cambiar tu `~/.zshrc` para que `lvm-instalador` fuera otra cosa. Para lo más delicado, usa Terminal y comprueba que el comando es `/Library/Nexum/gestor/lvm-instalador.sh`.
- **Las versiones de antes de la 1.39.3, ya movidas, llevan compiladas las rutas de `/Applications`** (por ejemplo, la de los `@INC` de Perl o algunas por defecto de Apache y ProFTPD). Las que usa root (`php.ini`, `conf.d`, `extension_dir`, `ServerRoot`, librerías) se cambian al moverlas; las demás, solo las usa tu usuario a través de los enlaces de `/Applications`. Para quitarlas del todo: `lvm-instalador actualizar <versión>` (la vuelve a compilar ya en `/Library/Nexum`).
- **whiptail** (el panel de Terminal) es de Homebrew: lo ejecuta tu usuario, nunca root.

## Seguridad

- **Dominios sin vhost (desde la 1.20.0):** una web que visites puede hacer que su dominio apunte a `127.0.0.1` (*DNS rebinding*), y su JavaScript leería phpMyAdmin (root sin contraseña) y los proyectos desde tu navegador. El primer vhost del puerto 80 (`xamppfiles/etc/extra/lvm-dominio-desconocido.conf`, incluido antes de `httpd-vhosts.conf`) recibe los dominios que no tienen vhost y les devuelve un 403; solo pasan `localhost`, `127.0.0.1` y `[::1]`. `web.local` y los dominios falseados no cambian. `http://localhost/` muestra la carpeta `htdocs` y phpMyAdmin sigue en `http://127.0.0.1/phpmyadmin/`. HTTPS no lo necesita: el certificado no vale para el dominio de fuera y el navegador corta la conexión.
- **Desde la 1.25.0:**
  - El script `xampp` de una versión solo se ejecuta como administrador si su carpeta, el script y los vhosts compartidos son de root y sin escritura para el grupo `admin` (tu usuario puede escribir en `/Applications`). Si no, `lvm-instalador asegurar --todas` lo arregla.
  - La contraseña solo se envía si hay un `sudo` de root de la tarea esperándola (sin hijos, es decir, sin estar ya ejecutando la orden). macOS no deja ver desde la ventana si el eco está apagado: es una comprobación más débil que en Linux.
  - Aplicar vhosts y `/etc/hosts` comprueba y escribe una sola copia de root. En los vhosts no se admiten `Define` ni `${VAR}`.
  - Todas las versiones solo para este Mac («Protegerlas» en Versiones); si una no se puede, no se arranca.
  - phpMyAdmin solo en `http://127.0.0.1/phpmyadmin/`, sin `setup/`; no se sirven `.env` ni `.git`; dominios desconocidos rechazados también en el 443.
  - OpenSSL de cada versión con `etc/openssl.cnf` propio (`OPENSSL_CONF`), no el de Homebrew.
  - Volcados con un usuario temporal limitado a su base y sin `DEFINER`; MariaDB sin usuario anónimo ni permisos en `test`.
  - El dominio de `shop_url` solo se falsea si se parece a la carpeta o ya tiene vhost.
- **Desde la 1.27.0:** la contraseña de administrador va por una terminal exclusiva (`TIOCEXCL`): ningún otro programa de tu usuario puede abrirla. Las comprobaciones de vhosts y hosts leen por bytes (un `\0` no se cuela). Cada base tiene su usuario `lvm_bd_<base>` (permiso solo para ella, con el `_` escapado), bloqueado tras cargar; sus vistas y funciones `INVOKER` pasan a `DEFINER`, y el gestor solo lee como root tablas de verdad. Reglas web sin distinguir mayúsculas; no se sirven `.sql`, `debug.log`, `.vscode` ni `config.inc.php`; las webs de fuera no leen la API de WordPress (CORS). Los `wp-config.php` del gestor llevan `DISALLOW_FILE_EDIT`.
- **Límite del Mac (hasta la 1.39.2):** el script, el `bash` de Homebrew que lo ejecuta y la aplicación de `~/Applications` eran de tu usuario, y las versiones estaban en `/Applications` (donde escribe el grupo admin). Desde la 1.39.3 el gestor y las versiones van en `/Library/Nexum`, de root: ver [Paso a /Library/Nexum](#paso-a-librarynexum-1393).
- **Desde la 1.28.0:** `sudo` va con su ruta (`/usr/bin/sudo`) y lo que ejecuta como root, con el PATH del sistema: un `sudo` o un `python3` falso en `/opt/homebrew/bin`, que es de tu usuario, ya no recibe la contraseña ni corre como root. La contraseña solo se envía si un `sudo` de root de la tarea la está esperando, y se comprueba otra vez al cerrar el panel. MariaDB de las pilas propias arranca con tu usuario. La aplicación se firma con *hardened runtime* y no admite depuradores. Actualizar desde Descargas abre una copia del `.dmg` y dice de dónde se descargó. Certificados de los proyectos solo en `XAMPP-compartido/ssl` y creados con tu usuario; **Arreglarlos** (`arreglar-certificados`) cambia los de CA o firmados por una CA local y la quita de los llaveros. **Protegerlas** corrige también lo que ya estaba abierto y cambia la clave SSL de fábrica de XAMPP. Más ficheros que no se sirven (`.dump`, `.old`, copias `~`, `error_log`, `auth.json`). `~/.lvm-instalador` solo para tu usuario. Lo que se compila corre sin la terminal de la tarea, las tareas reciben solo las variables necesarias y un `.pid` manipulado ya no hace que se cierre otro programa. Una CA local solo se avisa y se quita si su clave está en tu carpeta personal.
- **Desde la 1.29.0** (se aplica con **Protegerlas**):
  - **phpMyAdmin y otras webs:** una web abierta en el navegador podía mandar un formulario o un `fetch` a `http://127.0.0.1/phpmyadmin/`, y phpMyAdmin (root sin contraseña) lo ejecutaba. Ahora Apache rechaza (403) lo que llega de otra web (`Sec-Fetch-Site` y `Origin`); desde otra web solo se abre la portada. Escribiendo la dirección, con el botón del gestor o dentro de phpMyAdmin funciona igual.
  - **MariaDB sin ficheros:** `secure-file-priv` apunta a una carpeta vacía de root de cada versión (`xamppfiles/etc/lvm-sin-ficheros`) y `local-infile = 0`: desde SQL ya no se lee un fichero del Mac (`LOAD_FILE`) ni se escribe un PHP en htdocs (`INTO OUTFILE`). Deja de funcionar, a propósito: en phpMyAdmin, importar un CSV con la opción «CSV usando LOAD DATA» (el CSV normal sí funciona), y `LOAD DATA LOCAL` o `SELECT ... INTO OUTFILE` desde la terminal. Para sacar datos a un fichero, exporta desde phpMyAdmin o con `mysqldump`.
  - **Más ficheros que no se sirven:** `.log`, `.yml`/`.yaml` (`docker-compose.yml` lleva las claves), copias de `wp-config.php` y copias de seguridad de las webs (`.wpress`, Duplicator, `backup*.zip`...).
  - **Versiones que no son de root:** Protegerlas ya no las hace de root (podría ser una versión falsa puesta en `/Applications` por otro programa, para que root la diera por buena). Avisa y hay que volver a instalarla: `lvm-instalador actualizar <versión>`.
  - **Root solo ejecuta lo de una versión de root** (`httpd -t`, el MariaDB temporal, el script `xampp` al actualizar) y solo escribe en `XAMPP-compartido/httpd-vhosts.conf` si es de root y sin enlaces. Unos vhosts tuyos (de versiones antiguas) solo pasan a root si no llevan directivas peligrosas.
  - **Apartar el XAMPP oficial:** sus proyectos se copian en una carpeta de root y los mueve tu usuario a htdocs; sus vhosts se comprueban y se escriben de una sola lectura. Las copias de las BBDD (`var/mysql`) las lee su dueño, no root (macOS no protege los enlaces duros).
  - **Instalar versiones y actualizar phpMyAdmin:** lo compilado no puede llevar enlaces fuera de la versión y las carpetas `tmp` las crea root.
  - **Volcados:** se borran los eventos programados y las tablas con `DATA DIRECTORY`/`INDEX DIRECTORY`, y se avisa. `MySQL` (con mayúsculas) también cuenta como base del sistema.
  - El MariaDB temporal solo se para por su propio `.pid`; la ventana no abre dos paneles de contraseña a la vez; los datos de un proyecto o de un `.zip` no meten secuencias de escape en la terminal.
- **Desde la 1.30.0** (se aplica con **Protegerlas**):
  - **Volcados:** aunque se cierre la ventana a mitad de la carga, se limpia igual: no queda nada `INVOKER` ni eventos; un evento del volcado que ya estuviera en marcha se corta (`KILL USER`); el usuario de la BBDD ya no puede crear vistas, rutinas ni eventos después, y root repasa la base al final. No se carga nada si MariaDB tiene activos FEDERATED, CONNECT o SPIDER (con ellos, una tabla podría entrar como root).
  - **Vhosts:** los certificados y las claves solo de las carpetas del gestor (si un vhost antiguo usa otra ruta, **Arreglarlos** en Versiones lo pasa), y los registros no pueden llamarse como los ficheros de control de Apache (`.pid`).
  - **Dominios `.local`:** los que tienen vhost van siempre en `/etc/hosts`. Sin esa línea, el Mac los pregunta a la red local (mDNS) y cualquiera en la misma wifi podría contestar con su web. Desde la 1.38.0 se pueden apagar en Dominios y hosts (se avisa antes): sus líneas quedan comentadas y se recuerda que están apagados (`~/.lvm-instalador/locales-apagados`), así que no se vuelven a añadir hasta que se encienden. Ya no salen como «Host falseado», sino en «Dominios de los vhosts».
  - **htdocs:** Protegerlas y Cargar proyecto quitan la escritura para cualquier usuario del Mac (plugins y cachés que dejan carpetas en 777). Apache sigue pudiendo escribir, porque corre con tu usuario.
  - **Más ficheros que no se sirven:** claves (`.pem`, `.key`, `.p12`), `.ini`, `.conf` y las exportaciones de clientes de PrestaShop (`customers_export_*.csv`).
  - Un dominio guardado para un proyecto solo se falsea si ya tiene su vhost o se parece al nombre de la carpeta.
  - Funciona en macOS 12.0 a 12.2 (no tienen `readlink -f`). Root solo escribe vhosts y certificados en `XAMPP-compartido` si son de root y sin enlaces. La contraseña solo se envía al `sudo` de la terminal de la propia tarea. Actualizar phpMyAdmin e instalar versiones rechazan enlaces duros.
- **phpMyAdmin por `localhost` (desde la 1.30.2):** `http://localhost/phpmyadmin` (un marcador antiguo o la costumbre de XAMPP) lleva directamente a `http://127.0.0.1/phpmyadmin/`, a su portada y sin lo que llevara detrás. Por `web.local`, el dominio de un proyecto o uno sin vhost sigue dando el aviso «phpMyAdmin está en http://127.0.0.1/phpmyadmin/». Se aplica con **Protegerlas**.
- **`web.local` que no lleva a este Mac (desde la 1.30.2):** si en `/etc/hosts` `web.local` apunta a otra dirección (por ejemplo `127.0.1.1`, la que Ubuntu usa para el nombre del equipo) o no está, el navegador da «No se puede acceder a este sitio web» (`ERR_CONNECTION_REFUSED`), porque Apache solo escucha en `127.0.0.1` y `::1`. **Dominios y hosts** lo avisa y **Arreglarlo** lo cambia una sola vez (con copia del `/etc/hosts` anterior en `~/lvm-copias`).
- **Probar un proyecto con otra versión de PHP:** en **Proyectos → Añadir entorno… → En otra versión de PHP** (antes, Replicar) copia la BBDD de un proyecto de una versión a otra con el **nombre** que elijas (se propone el de origen con el número de esa versión: `wp_tienda_8_4` → `wp_tienda_8_5`) y la vincula allí a la **carpeta** que elijas (la misma, otra o ninguna). En **Bases de datos**, el botón de copiar (dos hojas) junto a cada BBDD solo la copia, con el mismo nombre, a la versión que elijas, y siempre avisa antes. La de origen no se toca. Si la de destino ya tiene una BBDD con ese nombre, se pide confirmación, se guarda antes una copia de la suya en `~/lvm-copias` y se pone la nueva en su lugar (en la terminal, con `--sustituir`). Si la de destino no es la activa, se arranca su MariaDB solo para la copia (sin red; pide la contraseña), y la copia se carga igual de protegida que al subir un volcado (usuario de la BBDD, sin `DEFINER`, lo `INVOKER` y los eventos neutralizados). En la versión activa, la BBDD que usa el proyecto cargado lleva un punto verde. En la terminal: `lvm-instalador copiar-bd <base> <origen> <destino> [--como <nombre>] [--carpeta <carpeta|->]`.
- **Vincular cada versión con su carpeta:** las BBDD quedan vinculadas a la carpeta del proyecto en cada versión (`~/.lvm-instalador/proyectos`, líneas `base@versión=carpeta`). En **Cargar proyecto**, el botón del eslabón de cada proyecto elige su BBDD en cada versión o «Ninguna» para desvincularla. En la terminal: `lvm-instalador vincular-bd <base> <versión> <carpeta|->`.
- **Montar un proyecto nuevo de GitHub (desde la 1.44.0 / Mac 1.32.0):** en **Cargar proyecto**, el botón **Montar nuevo proyecto**, a la derecha del buscador, despliega un asistente de tres pasos: 1) la dirección del repositorio (`https://github.com/usuario/repositorio.git`, o `git@github.com:usuario/repositorio.git` si es privado, con tu clave SSH) y el nombre de la carpeta; 2) la versión de PHP; 3) el nombre de la BBDD nueva y, si lo hay, su volcado (`.sql`, `.sql.gz` o `.zip`). Se clona en htdocs con tu usuario (sin sudo, sin submódulos, sin ganchos y solo por https o ssh), se carga en esa versión, se crea la BBDD y se sube el volcado con la carga protegida. En la terminal: `lvm-instalador montar-proyecto <url> <carpeta> <versión> <base> [volcado]`.
- **Administrador de pruebas en los paneles (desde la 1.45.0 / Mac 1.33.0):** al cargar una BBDD de WordPress o PrestaShop (subir un volcado, copiarla a otra versión o montar un proyecto nuevo) se le añade un administrador **`local@local.test`** con contraseña **`local`**, el mismo en todos los equipos. En **Cargar proyecto**, el botón del panel (WordPress o PrestaShop) abre una página con los dos ya escritos: solo hay que pulsar **Entrar**. Si la BBDD ya estaba cargada de antes, se crea al pulsar el botón. En WordPress es un usuario con rol de administrador; en PrestaShop, una copia del primer SuperAdmin (su idioma y su tema) en todas las tiendas. Los usuarios de verdad no se tocan. En PrestaShop 1.6 hace falta la carpeta del proyecto (por su `_COOKIE_KEY_`): se carga desde Cargar proyecto. En la terminal: `lvm-instalador usuario-pruebas <base> [carpeta]`. Es un riesgo aceptado a propósito: esas BBDD solo viven en tu Mac y nunca se suben a producción (si alguna vez exportas una para otro sitio, borra antes ese usuario).
- **Desmontar el proyecto cargado:** el botón de expulsar, junto a «web.local → proyecto», hace que `web.local` deje de apuntar a él y enseñe una página vacía («No hay ningún proyecto cargado»). El enlace sigue existiendo y apunta a la carpeta oculta `htdocs/.lvm-sin-proyecto`. Si era una tienda PrestaShop, su dominio deja de estar falseado. En la terminal: `lvm-instalador desmontar-proyecto`.
- **Aviso en rojo en Cargar proyecto:** si la versión de PHP montada no tiene la BBDD del proyecto cargado (por ejemplo, al activar otra versión a mano), sale «El proyecto vinculado a web.local no está disponible para esa versión», con las versiones que sí la tienen.
- **Fecha y parches de seguridad:** en **Instalar nuevas versiones de PHP**, cada versión dice cuándo se publicó y si php.net la marca como **Parche de seguridad** (corrige vulnerabilidades) o **Corrección de errores**.
- **Octavo repaso de seguridad (1.44.0 / Mac 1.32.0):** Cerrar procesos ya no se puede engañar con un proceso de nombre trucado; copiar una BBDD a otra versión ya no deja un programa tuyo en la terminal que tiene el permiso de administrador; los volcados se cargan con sus vistas y funciones `INVOKER` cambiadas a `DEFINER` desde el principio, y al terminar el usuario de la BBDD se vuelve a crear solo con su BBDD; el MariaDB temporal nunca corre como administrador; y si una versión no se puede dejar solo para este Mac, no se arranca. No hay que hacer nada: se aplica al actualizar.
- **Noveno repaso de seguridad (Linux 1.45.0 / Mac 1.33.0):** se aplica al actualizar y, lo de Apache, con **Protegerlas**.
  - El cliente de MariaDB y `mysqldump` ya no leen `~/.my.cnf` (un programa tuyo podía prepararlo para que cargaran una biblioteca suya en la terminal que ya tenía el permiso de administrador). Por lo mismo, git y ssh van fuera de esa terminal y curl sin `~/.curlrc`.
  - **Apartar el XAMPP oficial:** su MariaDB, su cliente y su `mysqldump` ya no se ejecutan como administrador, sino con el dueño de sus bases. Si sus bases son de root, no se copian ni se aparta nada: expórtalas desde su phpMyAdmin o dale los datos a su usuario de MariaDB (`sudo chown -R _mysql /Applications/XAMPP/xamppfiles/var/mysql`) y vuelve a pulsar **Apartar**.
  - **Vhosts:** los registros y los certificados que iban por `/Applications/XAMPP/…` (un enlace que puede cambiar cualquier administrador, también un programa tuyo) pasan a `logs/…` y `etc/ssl.crt/…`, que es lo mismo sin pasar por el enlace. Pasa solo al aplicar los vhosts y al copiar los del XAMPP oficial.
  - **Antes de ejecutar una versión como administrador** se mira también por dentro lo que se ejecuta (Apache, PHP, ProFTPD, bibliotecas y configuración): si algo no es de root o lo puede cambiar el grupo admin, no se arranca como administrador hasta reinstalarla (`lvm-instalador actualizar X.Y`), porque ya no se sabe si lo han cambiado. Las versiones instaladas por el gestor ya están así.
  - **Editar /etc/hosts:** una línea con un retorno de carro (`\r`) en medio ya no se salta la comprobación.
  - **Montar nuevo proyecto con una tienda:** el dominio de su base ya no se falsea solo. Si es el suyo: **Dominios y hosts → Nuevo proyecto con dominio falseado**, con la carpeta del proyecto y ese dominio. Por SSH solo se clona de servidores cuya clave ya conoces y de GitHub, GitLab y Bitbucket; para otro, conéctate antes una vez en Terminal y acepta su clave: `ssh -T git@servidor`. Sin git-lfs.
  - **Un `Listen` abierto a la red en los vhosts compartidos** ya no pasa sin aviso: la versión no se arranca hasta quitarlo con **Herramientas → Editar vhosts**.
  - **Más ficheros que no se sirven:** la carpeta `wpallimport` de WP All Import/Export, las exportaciones de clientes de PrestaShop también en `.zip`, `.xml` o `.xlsx`, y `.my.cnf`, `.netrc`, `.pgpass`, `credentials*.json`, `.aws` y `.docker`.
  - Otros: `PHP_TIMEZONE`, el correo de git de `ServerAdmin` e `importar-bd --proyecto` se comprueban antes de usarlos; los nombres solo admiten letras sin tilde aunque el Mac esté en español, y las versiones de php.net se validan antes de enseñarlas.
- **«Ha habido un error crítico en esta web»:** es un error de PHP, muchas veces de un plugin que no funciona con la versión de PHP cargada (por ejemplo, uno que usa `create_function()`, que no existe desde PHP 8). En **Herramientas → Registro de errores**, el primero es el registro del vhost del proyecto cargado (`web.local-error_log`), donde van los errores de PHP con PHP-FPM: **Ver el final** enseña lo último, con el fichero y la línea del error. Debajo está el general de Apache.
- **Buenas costumbres** (no las impone el gestor):
  - Abre cada proyecto por su vhost (`web.local` o su dominio) y no por `http://localhost/<carpeta>`: en `localhost` todos los proyectos comparten origen y un fallo XSS en uno alcanzaría a los demás.
  - En Visual Studio Code, abre los proyectos de clientes en **modo restringido** y no confíes en toda la carpeta htdocs: un `tasks.json` o unos ajustes de un proyecto se ejecutarían al abrirlo.
  - No guardes en htdocs copias de seguridad, exportaciones de clientes ni claves: aunque el gestor no las sirva, cualquier programa con tu usuario las puede leer.
- **Volcados SQL:** se cargan con `--binary-mode --local-infile=0`, así que el volcado solo puede llevar SQL. Un `.sql` manipulado no puede ejecutar programas (`\! orden`, `system`) ni leer ficheros del Mac. La línea del modo sandbox se sigue quitando.
- **Vhosts del administrador:** si fueran tuyos, un plugin de una web podría añadirles una orden que Apache ejecutaría como root al arrancar.
- **Ficheros de los proyectos:** si `wp-config.php`, `parameters.php`, `settings.inc.php` o `var/cache` son enlaces a otra carpeta, no se tocan. Los nombres de bases, prefijos y carpetas que vienen de un proyecto se comprueban antes de usarlos en consultas o en los vhosts.
- **Contraseña de administrador:** la ventana la reconoce por una marca distinta en cada ejecución, que lo que sale en el registro no puede imitar.
- **Copias:** `~/lvm-copias` y `~/.lvm-instalador` solo son accesibles para tu usuario (en el Mac, la carpeta personal la pueden leer los demás usuarios).
- **Lo que sigue igual a propósito:** MariaDB con root sin contraseña, y Apache y MariaDB con tu usuario, para trabajar en local con comodidad. Por eso, un plugin malicioso de una web puede leer las demás bases y tus ficheros: conviene no cargar proyectos de origen dudoso.

- **Desde la 1.39.2:**
  - **PHP2Shell** (CVE-2026-109618 y CVE-2026-109619): en Versiones de PHP, las vulnerables salen en rojo, «Vulnerable (PHP2Shell)», y activarlas pide confirmación. Las 8.2 a 8.5 se arreglan con el último parche de su rama (8.2.35, 8.3.36, 8.4.27 y 8.5.12): una XAMPP-X.Y.Z se actualiza instalando el nuevo a su lado y, al terminar, **Pasar las BBDD** le copia sus BBDD con sus vínculos y la activa (`lvm-instalador pasar-version <origen> <destino>`). Las **7.4, 8.0 y 8.1** ya no tienen versiones nuevas, pero sí el parche mínimo oficial del equipo de seguridad de PHP (ramas `PHP-X.Y-CVE-2026-109618-109619` de php-src): va dentro del script, se comprueba su sha256 y se aplica al compilar 7.4.33, 8.0.30 y 8.1.34, que se ven como «PHP 7.4.33 + parche de seguridad (oct 2026)». Para ponérselo a una ya instalada: **Poner el parche de seguridad** en su menú ⋯ (o `lvm-instalador actualizar 7.4`), que la vuelve a compilar conservando sus BBDD si no cambia la rama de MariaDB. Las anteriores a la 7.4 (solo en Docker) no tienen arreglo.
  - Todas las versiones (con **Protegerlas** o al arrancarlas): `session.upload_progress.enabled = Off`, `max_input_nesting_level = 6`, `post_max_size` y `upload_max_filesize` de 64M y `expose_php = Off` (`php/etc/conf.d/zz-lvm-seguridad.ini`; en la 8.5, también `fatal_error_backtraces = 0`), `LimitRequestBody 67108864` en Apache, PHP-FPM con `pm.max_requests = 50` y htdocs sin `ExecCGI`, `Includes` ni el `AddHandler` de `.cgi` y `.pl`.
  - **Barrera entre webs:** una web que visites ya no puede mandar formularios, `fetch`, iframes ni imágenes a tus proyectos (`Sec-Fetch-Site: cross-site` que no sea abrir una página), ni un POST con el `Origin` de otra web. Se apaga en **Configuración → Seguridad** o con `lvm-instalador barrera-web no` (la vuelta por POST de una pasarela de pago se corta mientras está puesta).
  - Lo que se descarga para compilar se comprueba, además de con su sha256, con la **firma GPG** de quien lo publica (PHP, Apache y APR, MariaDB y phpMyAdmin), con sus claves públicas dentro del script. Desde la 1.39.5 la comprueba el propio gestor con el Python del sistema (RSA o Ed25519, con SHA-2; también las de una subclave de firmar, como gpg), sin gnupg: en macOS 14 Homebrew ya no lo trae hecho y lo compilaba entero. Solo vale una firma de las huellas de cada proyecto. Si la firma no es buena, no se instala nada. Perl y ProFTPD no publican firmas.
  - El ayudante de PAM de MariaDB (setuid de root) ya no llega a la versión: se quita antes de copiarla como root.

## Si ya tienes el XAMPP oficial

Si `/Applications/XAMPP` es un XAMPP oficial (una carpeta real, no un enlace), el panel ofrece apartarlo. Lo mueve a `/Applications/XAMPP-oficial-<fecha>` sin borrar nada, y así se puede crear el enlace a la versión activa. Antes copia sus bases a `~/lvm-copias` arrancando su MariaDB con el dueño de los datos (nunca como administrador): si son de root, avisa y no aparta nada.

## Estado

**Probado en un Mac real** (Apple Silicon, 7 de octubre de 2026): la instalación de PHP 8.5 con su pila completa funciona. Hicieron falta tres arreglos en la compilación de MariaDB (versiones 0.9.1 a 0.9.3).

Antes, desde Linux, se habían probado:
- la sintaxis de todos los scripts;
- el panel y las ventanas;
- el modo simulación, con las consultas reales de versiones a php.net, apache.org, mariadb.org, cpan.org y GitHub.

Las otras ramas de PHP (7.4 a 8.4) todavía no se han compilado en un Mac. Si algo falla, el instalador no deja nada a medias y guarda los logs de la compilación en `~/.lvm-instalador/pila-<versión>-<fecha>/`.

Para probar sin sudo y sin tocar `/Applications` ni `/Library/Nexum`, con puertos altos (8080, 8443, 3307 y 2121):

```bash
LVM_PRUEBA=$HOME/lvm-prueba bash lvm-instalador.sh instalar --php 8.4 --si
```

Guía paso a paso de la primera prueba y qué enviar si falla: [PRUEBA-MAC.md](PRUEBA-MAC.md).
