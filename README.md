# lvm-instalador · Nexum Stack

Gestor e instalador de versiones de **LAMPP** (Linux, Apache, MySQL/MariaDB, PHP y Perl) para Linux. Todo va en un solo archivo: `lvm-instalador.sh`.

Incluye una versión para **macOS** con Apple Silicon en [`macos/`](macos/README.md).

## Por qué existe

XAMPP ya no saca versiones con los PHP nuevos: la última es la 8.2. Muchos proyectos ya necesitan PHP 8.3, 8.4 o 8.5, y otros siguen necesitando PHP 7.x.

Nexum Stack monta por su cuenta un LAMPP para **cada versión de PHP que existe**. Cada uno funciona como un **XAMPP virtual**: tiene su propio Apache, PHP, MariaDB, Perl, ProFTPD y phpMyAdmin en su carpeta `/opt/lampp-X.Y`, con sus propias bases de datos y la misma forma de uso que un XAMPP (`/opt/lampp/lampp start`, `http://127.0.0.1/phpmyadmin`…).

## Qué hace

- **Instala cualquier versión de PHP**, de la 7.4 a la 8.5. Puede ser el último parche de una rama o uno concreto, como la 8.3.10. Cada versión lleva su **pila propia**, compilada desde el código oficial, con componentes modernos y compatibles entre sí.
- **Instala también XAMPP completos** (7.1, 7.4, 8.1 y 8.2) para proyectos antiguos.
- **Solo hay una versión activa** a la vez (`/opt/lampp` apunta a ella). Cambiar de versión es un comando y no toca los proyectos de `/opt/htdocs` ni los virtual hosts, que comparten todas las versiones.
- **Actualiza** cada versión a los últimos parches de su rama, **muestra las bases de datos** de cada una y **desinstala** versiones, guardando antes una copia de sus bases de datos.
- **No instala PHP ni MariaDB en el sistema**: cada versión vive dentro de su carpeta y no afecta al resto del equipo.
- **Ventana gráfica** (GTK 3, desde Ubuntu 20.04) con las pestañas Versiones (que incluye instalar nuevas versiones), Bases de datos, Hosts y Herramientas. La contraseña de `sudo` se pide en una ventana. Ver [La ventana](#la-ventana).
- Panel en la terminal (whiptail), barra de progreso durante las instalaciones y modo simulación para ver lo que haría sin cambiar nada.

---

## Requisitos

| Requisito | Detalle |
|---|---|
| Sistema | Ubuntu o Debian de 64 bits (probado en Ubuntu 24.04) |
| Permisos | Usuario con `sudo` |
| Conexión | Internet (XAMPP de SourceForge; PHP, Apache, MariaDB, ProFTPD, Perl y phpMyAdmin de sus webs oficiales) |
| Comandos | `curl` y `python3`. Si falta `curl`: `sudo apt install curl` |
| Ventana | GTK 3 para Python (`python3-gi`, `gir1.2-gtk-3.0`), que ya viene en Ubuntu de escritorio desde la 20.04. Sin ella, el icono del menú abre el panel de la terminal |
| Procesador | x86_64 o ARM (en ARM, MariaDB se compila y tarda más, y no hay catálogo de XAMPP) |
| Espacio | Unos 2 GB libres en `/opt` por cada XAMPP y 5 GB por cada versión de PHP mientras se compila (después ocupa unos 1,5 GB) |

El resto de dependencias (`net-tools`, librerías de compilación) las instala el propio script cuando hacen falta.

---

## Instalar o actualizar con el paquete .deb

Lo más sencillo: doble clic en `lvm-instalador_<versión>_all.deb`. Se abre el Centro de aplicaciones (Ubuntu Software en 20.04 y 22.04): **Instalar** y la contraseña. Para actualizar, igual con el `.deb` nuevo. En una terminal: `sudo apt install ./lvm-instalador_<versión>_all.deb`.

- Instala el script en `/opt/lvm-instalador/lvm-instalador.sh`, el icono del menú en `/usr/share/applications/lampp-version-manager.desktop` y el del icono en `/usr/share/icons/hicolor/256x256/apps/`.
- Al instalarse, `/usr/local/bin/lvm-instalador` (y `lvm`, si ya era un enlace a `lvm-instalador.sh`) apunta al script de `/opt`, y los iconos del menú de cada usuario (`~/.local/share/applications/lampp-version-manager.desktop`) se reapuntan también. Así deja de abrirse la versión vieja de la carpeta donde se descomprimió.
- Al desinstalar el paquete (`sudo apt remove lvm-instalador`) se quitan esos enlaces y accesos. Las versiones de PHP de `/opt/lampp-*`, los proyectos y las bases de datos no se tocan.
- El paquete se genera con `./empaquetar-deb.sh [carpeta]`, que toma la versión de `APP_VERSION` y el icono que lleva el script.

## Primera instalación

### 1. Descargar

Con git:

```bash
cd ~
git clone <URL-del-repositorio> lvm-instalador
cd lvm-instalador
```

O descarga el ZIP del repositorio, descomprímelo en tu carpeta personal (por ejemplo en `~/lvm-instalador/`) y abre una terminal en esa carpeta (clic derecho → **Abrir en una terminal**).

> **No muevas ni borres la carpeta después**: el comando y el icono del menú apuntan a ese archivo.

### 2. Ejecutar por primera vez

```bash
chmod +x lvm-instalador.sh
./lvm-instalador.sh
```

### 3. Crear los accesos directos

La primera vez pregunta si quieres crear los **accesos directos**. Responde **Sí** y escribe tu contraseña de `sudo` (no se ve al escribirla; es normal). Se crean:

- El icono **«Nexum Stack»** en el menú de aplicaciones, que abre la [ventana gráfica](#la-ventana).
- El comando **`lvm-instalador`**, para abrirlo desde cualquier terminal.
- El comando corto **`lvm`** (`lvm use 8.4`…), solo si el equipo no tiene ya otro comando con ese nombre.

Si prefieres crear el comando a mano, desde la carpeta del repositorio:

```bash
sudo ln -sf "$PWD/lvm-instalador.sh" /usr/local/bin/lvm-instalador
```

Si vienes de una versión anterior con el comando `pvm-instalador`, el instalador ofrece quitarlo y dejar `lvm-instalador` apuntando a este archivo.

### 4. Instalar la primera versión de PHP

1. Abre **«Nexum Stack»** desde el menú de aplicaciones y ve a la pestaña **Instalar** (en la terminal: `lvm-instalador instalador`).
2. Marca la versión de PHP que necesites, por ejemplo **PHP 8.4.x**. Si también tienes proyectos antiguos, marca además **XAMPP 8.2.4-0** (dentro de «XAMPP oficiales»). Las versiones de PHP no necesitan ningún XAMPP.
3. Pulsa **Instalar** y escribe la contraseña de `sudo` cuando la pida. A partir de ahí todo es automático: cada versión de PHP tarda entre 7 y 20 minutos en compilarse, según el equipo.
4. Al terminar, pulsa **Activar lampp-8.4** (en la terminal, el panel pregunta si quieres activarla).
5. Comprueba que funciona: abre `http://127.0.0.1/phpmyadmin` en el navegador y ejecuta `/opt/lampp/bin/php -v` en la terminal.

---

## Manual de usuario

En la carpeta `manual/` hay un manual interactivo (ábrelo con doble clic en `manual/index.html`; funciona sin conexión): la ventana pestaña a pestaña con capturas, las tareas habituales, casos paso a paso (Protegerlas, Arreglarlos, Actualizar phpMyAdmin, Cerrar a la red, editar vhosts, actualizar el gestor, volcados) y el catálogo completo de medidas de seguridad, con qué hace cada una, contra qué protege y cómo comprobarla.

## Puesta a punto de seguridad (equipo nuevo o tras actualizar)

Haz esto una vez al instalar el gestor en un equipo, y cada vez que la ventana muestre un aviso naranja. Así queda como el equipo de referencia. Cada paso pide la contraseña de administrador.

1. **Instala el paquete.** Equipo nuevo: doble clic en el `.deb` (o `sudo apt install ~/Descargas/lvm-instalador_<versión>_all.deb`). Si ya lo tenías, las versiones que cambian el ayudante de actualización (la 1.39.0, la 1.40.0, la 1.44.0 y la 1.49.0) se instalan una vez en la terminal con ese mismo `sudo apt install`; las demás, desde la ventana.
2. **Abre la ventana y mira la pestaña Versiones.** Arriba aparecen los avisos pendientes, cada uno con su botón. Púlsalos de arriba abajo:

   | Aviso | Qué pasa si no lo arreglas | Botón |
   |---|---|---|
   | **A algunas versiones les faltan protecciones** | Les falta algo de lo que pone el gestor. Por ejemplo: arrancadas a mano escucharían en toda la red, con MariaDB sin contraseña; tienen la clave SSL de fábrica de XAMPP (la misma en todos); otra web podría mandar consultas a phpMyAdmin, o MariaDB podría leer y escribir ficheros del equipo (desde la 1.41.0). Sale también tras actualizar el gestor, si la versión nueva añade protecciones. | **Protegerlas** |
   | **Tablas del sistema de MariaDB antiguas** | Las tablas del sistema de MariaDB (`mysql.*`) son de una versión anterior y el servidor llena su registro de errores sin parar (en una 8.2.4 llegó a 28 GB y casi llena el disco). | **Repararlas** (la versión tiene que estar en marcha; no toca las BBDD de los proyectos y guarda antes una copia en `~/lvm-copias`) |
   | **phpMyAdmin antiguo** | El phpMyAdmin de XAMPP tiene fallos de seguridad corregidos después. | **Actualizarlos** |
   | **Certificados en los que confía todo el equipo** | Los certificados https de los proyectos están en `/etc/ssl/certs`, son de CA o los firma una CA tuya sin límite de dominios: con su clave, el PHP de una web podría falsificar cualquier web real (tu banco) en este equipo. | **Arreglarlos** |
   | **El navegador avisa al abrir estos proyectos** (desde la 1.46.0) | Chrome y Firefox no aceptan todavía el certificado propio de los proyectos con dominio de pruebas (como `web.local`): sale «La conexión no es privada» y las herramientas que manejan el navegador, como **Claude in Chrome**, no pueden abrirlos. | **Confiar** (después cierra el navegador del todo y vuelve a abrirlo) |

   Cuando no queda ningún aviso, el equipo está al día.
3. **Después de Arreglarlos**, el navegador acepta sin aviso los proyectos con dominio de pruebas (`web.local`, `.local`, `.test`): desde la 1.46.0, Arreglarlos hace también lo de **Confiar**. Desde la 1.47.0, las tiendas con dominio real también, pero **solo mientras están falseadas** en `/etc/hosts`: al falsear una (pestaña Hosts o al cargarla), el navegador acepta su certificado; al dejar de falsearla, deja de aceptarlo. Es a propósito: Apache corre con tu usuario y tiene su clave en memoria, donde la puede leer el PHP de cualquier web, y con ella se podría suplantar la web de verdad; mientras está falseada, el navegador no va a la web de verdad. Si cambias `/etc/hosts` a mano, sale el aviso «El navegador acepta webs reales que ya no están falseadas»: pulsa **Quitar** (o `lvm-instalador confiar-certificados --quitar`).
4. **Si tenías una CA propia** (la de `mkcert` o una creada con scripts como `generar-certificados.sh`), Arreglarlos la quita de la confianza del sistema y de Chrome y Firefox, y te dice dónde está su clave privada. Bórrala, o guárdala cifrada fuera de tu carpeta personal si la usas en otro sitio. No vuelvas a instalar una CA así en el equipo.
5. **Para ver antes qué haría**, en la terminal: `lvm-instalador --simular asegurar --todas` y `lvm-instalador --simular arreglar-certificados`. Sin `--simular`, lo hacen (igual que los botones).

Lo que no cambia, a propósito: MariaDB con root sin contraseña y Apache con tu usuario. Por eso, no cargues proyectos ni volcados de origen dudoso: un plugin malicioso puede leer las demás bases y tus ficheros.

## Uso diario

Abre la ventana desde el menú de aplicaciones (**«Nexum Stack»**) o usa la terminal:

```bash
lvm-instalador ventana         # ventana gráfica (la que abre el icono del menú)
lvm-instalador                 # panel en la terminal: activar, instalar, actualizar, desinstalar...
lvm-instalador use 8.4         # cambiar la versión activa
lvm-instalador list            # ver las versiones instaladas y cuál está activa
```

Arranque y parada de la versión activa:

```bash
lvm-instalador arrancar | parar | reiniciar
sudo /opt/lampp/lampp start | stop | restart | status     # lo mismo, como en XAMPP
```

La lista completa de comandos está en [Comandos sin panel](#comandos-sin-panel).

**Versión actual: 1.17.0.** Para actualizar, deja el `.deb` nuevo en Descargas y abre la ventana: si es más nuevo que la versión instalada, ofrece «Actualizar a la X» (pide la contraseña con pkexec, lo instala y se vuelve a abrir). El Centro de aplicaciones de Ubuntu no ofrece actualizar un `.deb` suelto; desde la terminal: `pkexec apt install -y ~/Descargas/lvm-instalador_<versión>_all.deb`. El número aparece en el pie de la ventana y en el panel, debajo de la firma. La lista de cambios está en «Novedades» (menú de la ventana), en la opción «Acerca de» del panel y en `lvm-instalador novedades`.

---

## La ventana

![Ventana de Nexum Stack](capturas/ventana.png)

`lvm-instalador ventana` (o el icono del menú) abre una ventana con cuatro pestañas. Las explicaciones de cada bloque están en el símbolo de información (ⓘ) junto a su título: se ven al pasar el ratón por encima.

| Pestaña | Qué hay |
|---|---|
| **Versiones** | La versión activa, con su estado (en marcha o parada) y los botones Arrancar (verde), Reiniciar (azul), Parar (rojo) y Abrir localhost. **Parar** hace lo mismo que `lvm disable`: para la versión y quita el enlace `/opt/lampp`, así que `php` deja de responder en la terminal hasta que actives una versión. Debajo, todas las versiones instaladas: la etiqueta **XAMPP** o **Pila propia** (en gris) y el botón **Activar**, o **Activa** en verde. Al pulsar una versión se despliegan sus componentes y los botones **Actualizar** (solo pilas propias) y **Desinstalar…**. Si quedan en memoria procesos de otras versiones, arriba sale **Hay procesos de otras versiones en memoria** con el botón **Cerrarlos** |
| **Bases de datos** | Un **buscador**, las bases de cada versión (sin las del sistema) con el botón **Abrir phpMyAdmin** en la versión activa y la descarga de cada base. Debajo, **Subir o actualizar una base de datos** |
| **Hosts** | Los dominios de los vhosts de `/opt/config/httpd-vhosts.conf` y si están falseados en `/etc/hosts` (llevan a este equipo). Arriba, **Host falseado**: el dominio de la tienda PrestaShop cargada, con el interruptor encendido y el botón **Abrir**. Debajo, el resto de dominios con su interruptor para falsearlos o dejar de falsearlos a mano (pide la contraseña de sudo). En medio, **Nuevo proyecto con dominio falseado**: dominio de producción, carpeta elegida de la lista de `/opt/htdocs` (por ejemplo, la de un `git clone`) o nueva con **+**, y base de datos de la versión activa, nueva con **+** o ninguna (si la carpeta trae `wp-config.php`, PrestaShop o `.env`, se propone su base); crea la carpeta en `/opt/htdocs`, su vhost http y https con certificado, la base vacía en la versión activa y falsea el dominio, para construir el proyecto en local y subirlo a producción tal cual (`lvm-instalador nuevo-dominio <dominio> <carpeta> [base]`). «Cargar proyecto» vuelve a falsear su dominio |
| **Versiones → Instalar nuevas versiones de PHP** (debajo de Instaladas) | Las ramas de PHP con su último parche, los componentes que llevaría y la carpeta donde se instala. Cada rama lleva su estado según php.net, como texto de color: **Estable** (verde, recibe correcciones de errores y de seguridad: la mejor opción para proyectos nuevos), **Solo seguridad** (ámbar, solo parches de seguridad hasta la fecha que se indica) o **Sin soporte** (rojo, solo para proyectos antiguos). También «Otro parche concreto…», que muestra el estado de la rama y marca su último parche, y los XAMPP oficiales |
| **Herramientas** | Lo que se usa de vez en cuando: **Editar** los vhosts y los hosts, registrar un XAMPP de `/opt/lampp`, abrir las carpetas de proyectos, copias y **Registros de instalaciones**, el **Registro de errores** (`/opt/lampp/logs/error_log` de la versión montada, con **Ver el final** para leer las últimas líneas sin abrir ficheros enormes, y **Abrir**), **Buscar una versión nueva** (un `.deb` más nuevo en Descargas), volver a crear el icono del menú, **Comandos de lvm-instalador** (la ayuda con todos los comandos), **Novedades** y **Acerca de** |

- **Contraseña:** las acciones que necesitan `sudo` piden la contraseña en una ventana, una sola vez por acción.
- **Progreso:** al instalar o actualizar se ve una barra con el porcentaje, los componentes (hechos, en curso y pendientes), el tiempo y una estimación del que queda. «Ver registro» muestra la salida completa. Al terminar, el botón **Activar** activa la versión recién instalada. Si la instalación falla, el botón **Ver el log del error** abre un informe con el sistema, el compilador, el paso que ha fallado, sus primeros errores, el final de su log y, si falló la configuración, lo último de su `config.log`. **Copiar todo** lo copia para buscar la solución. El informe también se guarda como `informe-error.txt` junto a los logs de la compilación.
- **Subir o actualizar una base de datos:** se elige un fichero `.sql`, `.sql.gz` o `.zip`, la base de destino de la versión activa y se pulsa **Cargar**. La barra muestra lo cargado (por ejemplo «319 MB de 657 MB»), el tiempo y lo que queda, como `pv`. Si la base ya existe, antes se borran todas sus tablas, para que no quede nada de lo anterior (tablas que la copia ya no trae, filas de una carga que falló a medias); si tiene alguna, primero se guarda una copia suya en `~/lvm-copias` (`…-antes-de-cargar-fecha.sql.gz`). Si root de MariaDB tiene contraseña, la ventana la pide. La versión activa tiene que estar en marcha.
  - **`.zip`:** las copias que se descargan del servidor suelen venir en `.zip`. Se cargan directamente: el `.sql` de dentro se descomprime al vuelo, sin ocupar espacio en disco, y la barra avanza según lo leído del zip. El zip tiene que tener un solo `.sql`.
  - **Línea del modo sandbox:** los `mariadb-dump` modernos ponen como primera línea `/*M!999999\- enable the sandbox mode */`. El cliente de MariaDB de XAMPP (10.4) no la entiende y daba «Unknown command '\-'». Ahora esa línea se quita al vuelo, sin tocar el fichero.
- **Buscar una base de datos:** filtra mientras escribes, sin recargar nada. Cada resultado dice en qué versión está, con qué PHP y qué MariaDB, y resalta lo escrito. Un punto verde marca las que están en la versión activa; en ellas, el botón **Elegir como destino** la deja elegida para cargar una copia.
- **Cargar proyecto:** cada resultado del buscador tiene este botón. Busca en `/opt/htdocs` la carpeta cuya configuración usa esa base (`wp-config.php`, `app/config/parameters.php` o `config/settings.inc.php` de PrestaShop, o `.env`) y la carga directamente en la versión de PHP de ese resultado. Si esa versión no es la activa, avisa de que se cambia de versión de PHP, para la que está en marcha y activa la del proyecto. Cambia el enlace del vhost para que apunte a esa carpeta. Es lo mismo que `unlink web.local; ln -s <carpeta>/ web.local`. El nombre del enlace (`web.local`) se lee del `DocumentRoot` de `/opt/config/httpd-vhosts.conf`. Si ningún vhost apunta a un enlace de `/opt/htdocs` (un equipo sin vhosts propios), al cargar el primer proyecto se crea `web.local`: sus vhosts http y https (sin caché en el navegador) en ese fichero, su certificado autofirmado en `/opt/config/ssl` y su línea en `/etc/hosts`. La ventana lo avisa antes de cargar y pide la contraseña de sudo.
  - Si ninguna carpeta usa la base, o la usan varias, se elige de una lista con buscador. La elección se recuerda para esa base en `~/.lvm-instalador/proyectos`, y «Cambiar…» permite cambiarla.
  - Si la base está en más de una versión, sale un resultado por versión: se carga en la del resultado que pulses.
  - Si no cambia de versión, recarga Apache (recarga suave, y PHP-FPM en las pilas propias). Sin ella, cada proceso de PHP recuerda durante 120 s (`realpath_cache_ttl`) adónde apuntaba el enlace y sigue sirviendo el proyecto anterior. Si cambia de versión no hace falta, porque la activación ya reinicia todo.
  - Para que el navegador tampoco muestre el proyecto anterior desde su caché, conviene poner `Header always set Cache-Control "no-store"` (dentro de `<IfModule headers_module>`) en los vhosts de `web.local`.
  - En la terminal: `lvm-instalador cargar-proyecto <carpeta> [versión]`.
  - Encima del buscador se ve a dónde apunta `web.local` («web.local → proyecto»; si el nombre no cabe, se ve entero al dejar el ratón encima). Junto a él está el botón para **desmontarlo**, y a la derecha los de abrirlo (de derecha a izquierda: Visual Studio Code, su BBDD en phpMyAdmin, wp-admin y `web.local`). **Montar nuevo proyecto**, a la derecha del buscador, clona uno de GitHub (ver más abajo).
  - **Tiendas PrestaShop** (las que tienen `app/config/parameters.php` o `config/settings.inc.php`): PrestaShop redirige siempre al dominio guardado en su base, así que no basta con `web.local`. Al cargarla se hace lo del manual de XAMPP del equipo, solo lo que falte:
    - **Dominio:** el de la tienda principal en la tabla `<prefijo>shop_url` de su base. Si la base no se puede leer, el `ServerName` del vhost que ya apunte a la carpeta.
    - **Certificado:** si no existe, `openssl req -x509 -nodes` sin preguntas (Common Name y nombre alternativo con el dominio y su `www.`), en `/etc/ssl/certs/<dominio>-selfsigned.crt` y `/etc/ssl/private/<dominio>-selfsigned.key`.
    - **Vhost:** si no hay vhost http o https para el dominio, se añade al final de `/opt/config/httpd-vhosts.conf` con el mismo formato que los demás (copia del fichero en `~/lvm-copias`) y se recarga Apache. Si ya existe, no se toca; si apunta a otra carpeta, solo se avisa.
    - **Hosts:** se falsea el dominio en `/etc/hosts` (`127.0.0.1 <dominio> www.<dominio>`): se le quita el `#` a su línea o se añade si no la hay.
  - **Cualquier otro proyecto:** los dominios de los vhosts que estuvieran falseados se comentan con `#` y vuelven a llevar a la web real. `localhost`, `web.local` y el nombre del equipo no se tocan nunca. Cada cambio de `/etc/hosts` guarda el anterior en `~/lvm-copias`.
  - **Apache con tu usuario:** si la versión no tiene `User`/`Group` con tu usuario (como pide el manual, para que la caché y los ficheros que crean las webs sean tuyos), se añaden al final de su `httpd.conf`. Lo mismo al registrar un XAMPP, que además activa los vhosts y hace tuya `/opt/htdocs` si no lo era.
  - En la terminal, a mano: `lvm-instalador hosts-falsear <dominio> si|no`.
- **Solo la versión montada en memoria:** todos los LAMPP se arrancan por el enlace `/opt/lampp`, así que sus procesos se llaman igual (`/opt/lampp/bin/httpd`…) sea cual sea la versión, y el `lampp stop` de XAMPP solo cierra lo que encuentra en sus `.pid`. Al montar otra versión, al pulsar **Parar** y al parar desde la terminal, el gestor comprueba que no quede ningún proceso de LAMPP (Apache, MariaDB, ProFTPD, PHP-FPM) y cierra los que sigan vivos: primero de forma normal (a MariaDB le da hasta 90 s para guardar) y después a la fuerza. Antes de arrancar cierra los de otras versiones. La versión de cada proceso se sabe por su ruta real, por los `.pid` de cada versión, por su proceso padre y, si solo pone `/opt/lampp/`, por si arrancó antes o después de montar la versión actual. En la terminal: `lvm-instalador procesos` y `lvm-instalador cerrar-procesos [--todos]`.
  - Que Apache tenga varios procesos es normal: uno principal (root) y varios de trabajo que atienden las peticiones (con XAMPP, de 5 a 10 esperando). Todos son de la misma versión.
- **Editar vhosts** (menú, debajo de Abrir phpMyAdmin): los vhosts (`/opt/config/httpd-vhosts.conf`, compartidos por todas las versiones) son del administrador, porque Apache los lee como root al arrancar. Se abre una copia en `~/.lvm-instalador/httpd-vhosts.conf` con el editor de textos. Al pulsar **Aplicar**:
  - se comprueba que solo lleva directivas de vhosts (nada de `LoadModule`, `Include`, `Listen`, `PidFile` ni registros con `|orden` o fuera de `logs/`);
  - se guarda la anterior en `~/lvm-copias` y se escribe la nueva con sudo;
  - Apache la prueba (`httpd -t`): si no la acepta, se deja como estaba; si la acepta, se recarga Apache.

  Lo que no se admite se puede poner a mano con `sudoedit /opt/config/httpd-vhosts.conf`. En la terminal: `lvm-instalador vhosts`.
- **Editar hosts** (menú): abre una copia de `/etc/hosts` en el editor de textos. Al pulsar **Aplicar**, guarda el `/etc/hosts` actual en `~/lvm-copias` y escribe el nuevo con sudo. No deja guardar uno sin la línea de `localhost`, ni añadir dominios que lleven a otro equipo (solo a `127.x` o `::1`). Para eso, en la terminal: `lvm-instalador hosts` (con `sudoedit`).
- **Cargar proyecto** (el primer bloque de la pestaña Versiones): buscador de las carpetas de `/opt/htdocs`, con el proyecto cargado ahora y, a su derecha, cuatro botones de icono (al dejar el ratón encima se ve qué abre cada uno): la **bola del mundo** abre el proyecto en el navegador (`web.local`); **phpMyAdmin**, su BBDD; **WordPress** o **PrestaShop**, su panel de administración (`wp-admin` o el back office de la tienda, se llame como se llame su carpeta); y **Visual Studio Code**, su carpeta (si ya está abierta, trae su ventana delante; solo sale si VS Code está instalado). **Cargar** apunta el vhost (`web.local`) a la carpeta y monta la versión de PHP donde está su base de datos. Si la base está en varias versiones, o en ninguna, pregunta cuál montar (propone la activa o la de su `.php-version`).
- **Pestaña Servicios** (como el panel de XAMPP): Apache, MariaDB y el FTP de la versión montada. Cada uno con su estado, sus puertos y si se puede entrar desde la red, y botones para arrancar, parar o reiniciar. **El FTP no arranca con la versión:** se arranca aquí cuando haga falta y sigue arrancando con ella hasta que se pare. En la terminal: `lvm-instalador servicio apache|mariadb|ftp arrancar|parar|reiniciar`.
- **Base que ya existe en otra versión:** al cargar una copia en una base que también está en otra versión, la ventana avisa («ya existe en lampp-7.4 (PHP 7.4.33)») y pregunta si cargarla también en la activa. Cada versión tiene su propio MariaDB, así que la otra no se toca. Al crear una base, también avisa si ese nombre ya existe en otra versión.
- **Descargar una base de datos:** el botón de descarga de cada base (en la lista de su versión o en el buscador) guarda una copia `.zip` con un `.sql` dentro (o `.sql.gz` o `.sql` si el nombre acaba así), con estructura, datos, disparadores y rutinas. Se puede volver a cargar con «Subir o actualizar». Funciona con cualquier versión: si no está en marcha, se arranca un MariaDB temporal sin red y sin tocar la versión activa, solo para la copia, y por eso pide la contraseña de sudo.
- **Crear y borrar bases de datos** (solo en la versión activa, que tiene que estar en marcha): «Crear base de datos…» en su lista o el botón **+** junto al destino de la carga. La base se crea vacía en utf8mb4_general_ci. La papelera de cada base, o la que está junto al destino, la borra tras una confirmación. Si la base tiene tablas, avisa de que se elimina todo su contenido y es irreversible, y propone guardar antes una copia `.sql.gz` en `~/lvm-copias`, que se puede volver a cargar. Sin copia, hay que escribir el nombre de la base para confirmar. Si la copia falla, no se borra nada.
- **Desinstalar:** propone guardar antes una copia de las bases de datos en `~/lvm-copias`. Si se quita la copia, hay que escribir el nombre de la versión para confirmar.
- **Menú (☰):** abrir localhost o phpMyAdmin, volver a leer las versiones, abrir el panel en la terminal, la carpeta de registros, «Novedades» y «Acerca de».
- La ventana no repite la lógica del instalador: ejecuta los mismos comandos que la terminal. El código de la ventana (Python, GTK 3) va dentro de `lvm-instalador.sh` y se escribe en `~/.lvm-instalador/ventana.py` al abrirla.
- `lvm-instalador --simular ventana` abre la ventana en modo simulación.

## Uso del panel

```bash
lvm-instalador              # panel
lvm-instalador --simular    # panel en modo prueba: muestra lo que haría sin cambiar nada
```

En las ventanas: **flechas** para moverte, **Espacio** para marcar, **Intro** para aceptar y **Tab** para llegar a los botones.

Durante la instalación se muestra una **barra de progreso** para cada versión: el porcentaje de esa versión, sus componentes (hechos `[x]`, en curso `[>]`, pendientes `[ ]`) con lo que se está haciendo en cada uno, el tiempo que lleva, una estimación del que queda y, si se instalan varias, el porcentaje total. Todo el detalle va al log. En modo texto, cada paso indica su porcentaje.

```
Instalando 1 de 2: PHP 8.4 (pila propia)

  [x] Descargas
  [x] Apache 2.4.69
  [>] PHP 8.4.26: compilando (tarda unos minutos)
  [ ] Perl 5.42.3
  [ ] ProFTPD 1.3.9d
  [ ] MariaDB 11.8.9
  [ ] phpMyAdmin 5.2.3 y configuracion

Tiempo: 3 min   Quedan unos 4 min
Total de la instalacion: 24%
                        48%
```

Las ventanas usan fondo negro con el elemento seleccionado en blanco. En la ventana principal, la versión activa aparece en verde (#45A57C). Abajo a la izquierda, fuera de la ventana, aparece el logo de hexer en ASCII (en blanco y verde #45A57C); si la ventana es tan grande que lo taparía, no se muestra. Por eso el acceso del menú abre GNOME Terminal a 100×32; si lo lanzas desde una terminal más pequeña, puede que no se vea. La parte rellena de la barra de progreso es verde (#45A57C; color exacto en terminales con `COLORTERM=truecolor`, verde básico en el resto), con el porcentaje siempre en blanco, para que el porcentaje (que whiptail siempre pinta en blanco) se lea encima. Si prefieres otros colores, define tu propia variable `NEWT_COLORS` y el script la respetará. Con `LVM_UI=text` funciona sin ventanas.

| Opción | Qué hace |
|---|---|
| Cambiar la versión activa | Para la versión activa y arranca la elegida |
| Instalar versiones | Lista para marcar lo que quieres instalar. Solo aparece lo que no tienes |
| Ver versiones instaladas | Tabla con las versiones de PHP, Apache, MariaDB, ProFTPD, Perl y phpMyAdmin de cada una |
| Ver bases de datos | Tabla con el número de bases de cada versión; al elegir una, sus nombres en columnas |
| Desinstalar versiones | Borra una versión. Ver [Desinstalar](#desinstalar) |
| Actualizar versiones de PHP | Vuelve a compilar una versión de PHP con la última pila de su rama. Ver [Actualizar versiones de PHP](#actualizar-versiones-de-php) |
| Acerca de | Qué hace el instalador, su versión y la lista de cambios de cada versión |
| Registrar XAMPP sin gestionar | Solo aparece si hay un XAMPP instalado a mano en `/opt/lampp` |

### Qué se puede instalar

**XAMPP completos** (descargados de SourceForge, con suma de verificación):

| XAMPP | Apache | PHP | MariaDB | ProFTPD | Perl | phpMyAdmin |
|---|---|---|---|---|---|---|
| 7.1.33-1 | 2.4.41 | 7.1.33 | 10.4.10 | 1.3.6 | 5.16.3 | 4.9.2 |
| 7.4.33-0 | 2.4.54 | 7.4.33 | 10.4.27 | 1.3.6 | 5.34.1 | 5.2.0 |
| 8.1.25-0 | 2.4.58 | 8.1.25 | 10.4.32 | 1.3.6 | 5.34.1 | 5.2.1 |
| 8.2.4-0 | 2.4.56 | 8.2.4 | 10.4.28 | 1.3.6 | 5.34.1 | 5.2.1 |

**PHP con pila propia** (sin XAMPP). Cada rama de PHP lleva sus componentes:

| PHP | Apache | MariaDB | ProFTPD | Perl | phpMyAdmin |
|---|---|---|---|---|---|
| 7.4 \* | 2.4 | 10.11 LTS | 1.3.9 | 5.40 | última |
| 8.0 \* | 2.4 | 10.11 LTS | 1.3.9 | 5.40 | última |
| 8.1 \* | 2.4 | 10.11 LTS | 1.3.9 | 5.40 | última |
| 8.2 | 2.4 | 10.11 LTS (soporte hasta 2028) | 1.3.9 | 5.40 | última |
| 8.3 | 2.4 | 11.4 LTS (hasta 2029) | 1.3.9 | 5.40 | última |
| 8.4 | 2.4 | 11.8 LTS (hasta 2030) | 1.3.9 | 5.42 | última |
| 8.5 | 2.4 | 12.3 LTS (hasta 2029) | 1.3.9 | 5.44 | última |

\* Ramas sin soporte de php.net (ya no reciben parches de seguridad): solo para proyectos antiguos que no se puedan actualizar. Usan la misma pila que la 8.2. Como no funcionan con las librerías actuales de Linux, llevan las suyas dentro de su carpeta: **OpenSSL 1.1.1w** (7.4 y 8.0, en `/opt/lampp-X.Y/openssl`) e **ICU 72.1** (7.4, 8.0 y 8.1, dentro de PHP). Tardan unos minutos más en compilarse.

- **Último parche o parche concreto.** En la lista de instalar, cada rama instala su **último parche** en `/opt/lampp-X.Y`. La fila **Otro parche** permite elegir rama y versión exacta (todas las publicadas en php.net, con su fecha). Un parche que no es el último va en su propia carpeta, `/opt/lampp-X.Y.Z` (por ejemplo `/opt/lampp-8.3.10`), así que pueden convivir varios de la misma rama, cada uno con sus bases de datos. Si la carpeta de la rama la ocupa un XAMPP (por ejemplo `/opt/lampp-7.4`), el último parche también va a `/opt/lampp-7.4.33`. No se ofrecen las versiones de PHP que ya tienes instaladas con pila propia.
- De cada rama se instala **el último parche publicado** en ese momento, consultado en las webs oficiales. Por ejemplo, en octubre de 2026 la 8.4 quedaba con PHP 8.4.26, Apache 2.4.69, MariaDB 11.8.9, ProFTPD 1.3.9d, Perl 5.42.3 y phpMyAdmin 5.2.3.
- Apache y ProFTPD solo tienen una rama estable mantenida, así que todas usan la misma. MariaDB y Perl suben un escalón con cada rama de PHP.
- Una rama de PHP posterior a la tabla (8.6…) aparece sola y usa la última fila hasta que se amplíe la tabla (`STACK_MATRIX` en el script).
- Apache, PHP, Perl y ProFTPD **se compilan** desde el código fuente oficial (unos 10-20 minutos por versión). MariaDB usa el **binario oficial** de mariadb.org, porque compilarla tardaría casi una hora. Todo se descarga con comprobación sha256.
- Cada versión tiene **bases de datos propias y vacías**: las del sistema de MariaDB, la de phpMyAdmin y root sin contraseña, como un XAMPP recién instalado.
- MariaDB usa el cotejamiento `utf8mb4_general_ci`, igual que XAMPP, para que las bases exportadas desde una versión nueva se puedan importar en las antiguas y en los servidores.

En la lista de instalación cada fila muestra la versión exacta de cada componente que quedará instalada.

---

## Desinstalar

Opción **Desinstalar versiones** del panel (o `lvm-instalador desinstalar <version>`):

- No deja desinstalar **la versión activa**: cambia antes a otra.
- No deja desinstalar un XAMPP cuyas **bases de datos usan otras versiones** (aparece como `en uso`; solo pasa con versiones instaladas por el script antiguo).
- Si la versión tiene **bases de datos propias**, las enumera y ofrece guardar antes una copia en `~/lvm-copias/lampp-<versión>-bases-<fecha>.tar.gz`. Si no quieres copia, hay que escribir el nombre de la versión para confirmar.
- `/opt/htdocs` y `/opt/config` nunca se borran. Si la versión tuviera una carpeta `htdocs` propia (no un enlace), se niega a borrarla.

Desde la línea de comandos no se hace copia: úsalo solo para versiones sin bases propias o ya copiadas.

---

## Actualizar versiones de PHP

Opción **Actualizar versiones de PHP** del panel (o `lvm-instalador actualizar <version>`). Vuelve a compilar una versión de PHP con la última pila de su rama. Las versiones con un parche concreto (`/opt/lampp-8.3.10`) no se actualizan: se quedan en su parche.

- **`actualizable`**: hay parches nuevos de algún componente (por ejemplo, PHP 8.4.26 → 8.4.27). **Conserva sus bases de datos**, porque la rama de MariaDB es la misma.
- **`sobre XAMPP`**: versión instalada por el script antiguo, que copiaba Apache, MariaDB, ProFTPD y Perl de un XAMPP. Pasa a tener su pila propia. Como su MariaDB cambia de rama (por ejemplo, de 10.4 a 11.8), empieza con bases de datos vacías y antes guarda una copia de las anteriores en `~/lvm-copias/`.
- **`al dia`**: ya tiene todos los paquetes en su última versión, así que no se puede actualizar. Al elegirla aparece en verde «El paquete lampp-X.Y se encuentra actualizado.» y se vuelve a la lista. `lvm-instalador actualizar <version>` muestra el mismo aviso y no compila nada.

Mientras se compila, la versión actual sigue funcionando. Solo al final se sustituye: si es la activa, se para unos segundos y arranca la nueva. Si algo falla, la versión anterior queda como estaba.

---

## Comandos sin panel

```bash
lvm-instalador ventana            # ventana gráfica
lvm-instalador instalador         # abrir directamente la lista de versiones para instalar
lvm-instalador use 8.4             # activar una versión
lvm-instalador list                # listar versiones instaladas
lvm-instalador estado              # estado detallado
lvm-instalador list-db             # bases de datos de cada versión
lvm-instalador disable             # parar y desactivar la versión activa
lvm-instalador desinstalar 8.3     # eliminar una versión (no la activa ni una base en uso)
lvm-instalador desinstalar 8.3 --copia   # lo mismo, guardando antes sus bases en ~/lvm-copias
lvm-instalador arrancar            # arrancar la versión activa (también parar y reiniciar)
lvm-instalador importar-bd copia.sql mi_web   # cargar una copia en la versión activa (también .sql.gz y .zip)
lvm-instalador importar-bd copia.sql nueva --crear   # creando la base; si ya existe, se vacía antes (con copia)
lvm-instalador crear-bd mi_web     # crear una base vacía en la versión activa
lvm-instalador borrar-bd mi_web --copia   # borrarla guardando antes una copia en ~/lvm-copias
lvm-instalador exportar-bd mi_web ~/Descargas/mi_web.zip [7.4]       # descargar una copia (sin versión, de la activa)
lvm-instalador cargar-proyecto dob-wordpress-mi_web [7.4]           # web.local -> esa carpeta (y activa la 7.4)
lvm-instalador montar-proyecto https://github.com/yo/mi_web.git mi_web 8.4 wp_mi_web [copia.sql]   # clonar, cargar y crear su BBDD
lvm-instalador desmontar-proyecto                                  # web.local enseña una página vacía
lvm-instalador vhosts             # editar httpd-vhosts.conf de la versión activa (después, reiniciar)
lvm-instalador hosts              # editar /etc/hosts (sudoedit)
lvm-instalador add 8.2.12          # registrar un XAMPP instalado a mano en /opt/lampp
lvm-instalador actualizar 8.4      # actualizar una versión de PHP
lvm-instalador version            # versión del instalador
lvm-instalador acerca             # qué hace y lista de cambios

# Instalación desatendida
lvm-instalador instalar --xampp 8.2.4 --php 8.4,8.5 --si
lvm-instalador instalar --php 7.4,8.3.10 --si   # 7.4 = último parche; 8.3.10 = ese parche en /opt/lampp-8.3.10
lvm-instalador use 8.3.10                       # activar una versión con parche concreto
```

Arranque y parada de la versión activa (como siempre en XAMPP):

```bash
sudo /opt/lampp/lampp start | stop | restart | status
```

En las versiones con pila propia también: `startapache`, `stopapache`, `reloadapache`, `startmysql`, `stopmysql`, `startftp` y `stopftp`.

---

## Cómo queda organizado

```
/opt/lampp            -> enlace a la versión activa
/opt/lampp-8.2.4/     XAMPP completo (Apache, PHP 8.2.4, MariaDB, ProFTPD, Perl)
/opt/lampp-8.3.10/    Pila propia de PHP 8.3.10 (parche concreto)
/opt/lampp-8.4/       Pila propia de PHP 8.4
    lampp             Arranque y parada (start, stop, restart, status...)
    apache2/          Apache        etc/httpd.conf, etc/extra/
    php/              PHP (PHP-FPM) php/etc/php.ini, php/etc/conf.d/99-lampp.ini
    mysql/            MariaDB       etc/my.cnf
    proftpd/          ProFTPD       etc/proftpd.conf
    perl/             Perl
    phpmyadmin/       phpMyAdmin
    bin/              php, mysql, mysqldump, perl... (/opt/lampp/bin/php como en XAMPP)
    var/mysql/        Bases de datos propias (vacías al instalar)
    logs/             error_log, access_log, php-fpm.log, proftpd.log
/opt/htdocs/          Proyectos, compartidos por todas las versiones
/opt/config/httpd-vhosts.conf   Virtual hosts, compartidos por todas las versiones
```

- PHP se ejecuta como **PHP-FPM** (proceso aparte) y arranca y para junto con Apache.
- Apache, PHP-FPM y el FTP se ejecutan con el usuario que instala, así que los permisos de los archivos de los proyectos no cambian. MariaDB se ejecuta con el usuario `mysql`, como en XAMPP.
- HTTPS en el puerto 443 con un certificado autofirmado para `localhost`; los virtual hosts usan sus propios certificados, como hasta ahora.
- **Solo desde este equipo:** Apache escucha en `127.0.0.1` y `::1`, MariaDB en `127.0.0.1` (`bind-address`) y el FTP en `127.0.0.1` (`DefaultAddress`). Los demás equipos de la red no llegan a nada.
- **FTP**: entra con tu usuario y contraseña del equipo y llega directamente a `/opt/htdocs`. No arranca con la versión: se arranca en la pestaña Servicios (o con `lvm-instalador servicio ftp arrancar`).
- **Perl**: scripts `.pl` y `.cgi` en `/opt/htdocs` o en `cgi-bin/` con `#!/opt/lampp/bin/perl`. No incluye mod_perl.
- Al instalar un XAMPP, Apache queda configurado para ejecutarse con el usuario que lo instala y con los virtual hosts activados.

---

## Seguridad

Desde la 1.29.0, el gestor deja cada versión cerrada a la red y protege el equipo de lo que traigan los proyectos y las bases de los clientes:

- **Solo desde este equipo.** XAMPP deja Apache, MariaDB y ProFTPD escuchando en todas las interfaces, y el FTP entra con `daemon` / `xampp`, la contraseña de fábrica de todos los XAMPP. Al montar, arrancar o registrar una versión se cambia solo lo que falta: `Listen 127.0.0.1:80` y `[::1]:80` (lo mismo con el 443), `bind-address = 127.0.0.1` y `DefaultAddress 127.0.0.1`. Los ficheros anteriores quedan en `~/lvm-copias`. Si algo sigue abierto, la pestaña Versiones avisa y ofrece **Cerrar a la red**. En la terminal: `lvm-instalador asegurar`.
- **Dominios sin vhost (desde la 1.33.0).** Una web que visites puede hacer que su dominio apunte a `127.0.0.1` (*DNS rebinding*): su JavaScript leería phpMyAdmin (root sin contraseña) y los proyectos desde tu navegador. El primer vhost del puerto 80 (`etc/extra/lvm-dominio-desconocido.conf`, incluido antes de `httpd-vhosts.conf`) recibe los dominios que no tienen vhost y les devuelve un 403; solo pasan `localhost`, `127.0.0.1` y `[::1]`. `web.local` y los dominios falseados no cambian. `http://localhost/` muestra la carpeta `htdocs` y phpMyAdmin sigue en `http://127.0.0.1/phpmyadmin/`. HTTPS no lo necesita: el certificado no vale para el dominio de fuera y el navegador corta la conexión.
- **Desde la 1.37.0:**
  - `/opt` es del administrador (sus carpetas siguen siendo de quien eran): el PHP de una web, que se ejecuta con tu usuario, no puede cambiar `/opt/lampp` ni `/opt/lvm-instalador`.
  - Aplicar vhosts y `/etc/hosts` lee la copia una sola vez a una carpeta de root y escribe exactamente lo que se ha comprobado. En los vhosts no se admiten `Define` ni `${VAR}`, y los registros solo van a un fichero de `logs`.
  - `lvm-actualizar` copia el `.deb` a una carpeta de root y comprueba allí la huella SHA-256 que se te ha mostrado, que solo lleva ficheros de lvm-instalador y que su `postinst`/`postrm` son los del paquete instalado (si cambian, se instala a mano con `sudo apt install`). Aún sin firma.
  - Todas las versiones se dejan solo para este equipo (`lvm-instalador asegurar --todas`, o «Protegerlas» en Versiones). Si una no se puede, no se arranca.
  - phpMyAdmin solo en `http://127.0.0.1/phpmyadmin/` (desde la 1.38.0/1.26.0 tiene su propio origen: en `127.0.0.1` no hay nada más, y en `localhost`, `web.local` o un dominio falseado da 403; un XSS en un proyecto no lo alcanza), sin `setup/`. No se sirven `.env`, `.git`, `.svn` ni `.hg`. El vhost de dominios desconocidos también está en el 443.
  - Los volcados se cargan con un usuario temporal (`lvm_imp_*`) con permisos solo sobre su base y sin `DEFINER`: no pueden tocar otras bases, crear usuarios ni usar ficheros del servidor. Un volcado de varias bases (`--all-databases`) ya no se carga.
  - MariaDB de XAMPP sin el usuario anónimo ni los permisos de las bases `test`; ProFTPD de XAMPP sin `daemon`/`xampp`.
  - El dominio de `shop_url` solo se falsea si se parece a la carpeta o ya tiene su vhost.
- **Desde la 1.39.0:** la contraseña de administrador va por una terminal exclusiva (`TIOCEXCL`): ningún otro programa de tu usuario puede abrirla. Las comprobaciones de vhosts y hosts leen por bytes (un `\0` no se cuela). Cada base tiene su usuario `lvm_bd_<base>` (permiso solo para ella, con el `_` escapado), bloqueado tras cargar; sus vistas y funciones `INVOKER` pasan a `DEFINER`, y el gestor solo lee como root tablas de verdad. Reglas web sin distinguir mayúsculas; no se sirven `.sql`, `debug.log`, `.vscode` ni `config.inc.php`; las webs de fuera no leen la API de WordPress (CORS). Los `wp-config.php` del gestor llevan `DISALLOW_FILE_EDIT`. `lvm-actualizar` revisa el paquete con `tarfile` (sin enlaces), exige la huella y que el ayudante, la acción de polkit, los scripts y las dependencias sean los instalados; si cambian, `sudo apt install`.
- **Desde la 1.40.0:** el ayudante de actualización exige que cada fichero del paquete sea de root y con sus permisos (sin setuid) y lee los scripts de instalación sin seguir enlaces. Una vista rota en un volcado ya no deja vistas `INVOKER` sin pasar a `DEFINER`. Los certificados de los proyectos van en `/opt/config/ssl` (no en `/etc/ssl/certs`, donde el sistema los toma como de confianza), se crean con tu usuario y solo en esa carpeta, y **Arreglarlos** (`arreglar-certificados`) pasa los antiguos y quita las CAs locales sin límite de dominios. **Protegerlas** corrige también lo que ya estaba abierto (`Listen` con la IP de la red, `bind-address = 0.0.0.0`, `DefaultAddress`, puertos de más) y cambia la clave SSL de fábrica de XAMPP. No se sirven `.dump`, `.old`, `.orig`, copias `~`, `error_log`, `auth.json` ni `.npmrc`. Lo compilado se copia a `/opt` sin conservar el dueño ni el setuid; root no sigue enlaces al escribir en los proyectos ni al vaciar la caché; la ventana usa los programas del sistema (no los de `~/.local/bin`) y pasa a las tareas solo las variables necesarias. Lo que se compila corre sin la terminal de la tarea (no puede usar el permiso de `sudo` ya dado). Un `.pid` manipulado ya no hace que se cierre otro programa. Una CA local solo se avisa y se quita si su clave está en tu carpeta personal.
- **Desde la 1.41.0** (se aplica con **Protegerlas**):
  - **phpMyAdmin y otras webs.** Una web abierta en el navegador podía mandar un formulario o un `fetch` a `http://127.0.0.1/phpmyadmin/`, y phpMyAdmin (root sin contraseña) lo ejecutaba aunque la web no pudiera leer la respuesta. Ahora Apache rechaza (403) lo que llega de otra web (cabeceras `Sec-Fetch-Site` y `Origin`); desde otra web solo se abre la portada. Escribiendo la dirección, con el botón del gestor o dentro de phpMyAdmin funciona igual.
  - **MariaDB sin ficheros.** `secure-file-priv` apunta a una carpeta vacía de root de cada versión (`etc/lvm-sin-ficheros`) y `local-infile = 0`: desde SQL ya no se puede leer un fichero del equipo (`LOAD_FILE`) ni escribir un PHP en htdocs (`INTO OUTFILE`). Si esa carpeta se borrara, MariaDB no arrancaría: Protegerlas (y montar la versión) la vuelve a crear. Deja de funcionar, a propósito: en phpMyAdmin, importar un CSV con la opción «CSV usando LOAD DATA» (el CSV normal sí funciona), y `LOAD DATA LOCAL` o `SELECT ... INTO OUTFILE` desde la terminal. Para sacar datos a un fichero, exporta desde phpMyAdmin o con `mysqldump`.
  - **Más ficheros que no se sirven:** `.log`, `.yml`/`.yaml` (un `docker-compose.yml` lleva las claves de la BBDD), copias de `wp-config.php` (`wp-config.txt`, `wp-config.php.txt`...) y copias de seguridad de las webs (`.wpress`, `*_archive.zip` de Duplicator, `backup*.zip`/`.tar.gz`, UpdraftPlus...). Un `.zip` o un `.csv` normales se siguen sirviendo.
  - **Root ya no trabaja sobre carpetas tuyas:** Protegerlas prepara los ficheros como root en una carpeta de root; al instalar una versión o actualizar phpMyAdmin, lo compilado no puede llevar enlaces fuera de la versión y las carpetas `tmp` las crea root; los certificados de los proyectos los crea root.
  - **Volcados:** se borran los eventos programados y las tablas con `DATA DIRECTORY`/`INDEX DIRECTORY` (guardan sus ficheros fuera de MariaDB), y se avisa.
  - El MariaDB temporal de las copias solo se para por su propio `.pid`; los nombres de bases se comparan sin mayúsculas; los datos de un `wp-config.php` o de un `.zip` ya no pueden meter secuencias de escape en la terminal.
  - Lo que queda: lo que se compila al instalar una versión sigue en una carpeta tuya hasta que root lo copia, así que un programa que ya corriera con tu usuario podría cambiar los binarios. Compilar con otro usuario sería un cambio grande; tampoco cambiaría mucho, porque ese programa también podría cambiar tu `.bashrc` y capturar la contraseña (ver el límite de abajo).
- **Desde la 1.42.0** (se aplica con **Protegerlas**):
  - **Volcados:** aunque se cierre la ventana a mitad de la carga, se limpia igual: no queda nada `INVOKER` ni eventos; un evento del volcado que ya estuviera en marcha se corta (`KILL USER`); el usuario de la BBDD ya no puede crear vistas, rutinas ni eventos después, y root repasa la base al final. No se carga nada si MariaDB tiene activos FEDERATED, CONNECT o SPIDER (con ellos, una tabla podría entrar como root).
  - **Vhosts:** los certificados y las claves solo de las carpetas del gestor (si un vhost antiguo usa otra ruta, **Arreglarlos** en Versiones lo pasa), y los registros no pueden llamarse como los ficheros de control de Apache (`.pid`).
  - **Dominios `.local`:** los que tienen vhost van siempre en `/etc/hosts`. Sin esa línea, el equipo los pregunta a la red local (mDNS) y cualquiera en la misma wifi podría contestar con su web.
  - **htdocs:** Protegerlas y Cargar proyecto quitan la escritura para cualquier usuario del equipo (plugins y cachés que dejan carpetas en 777). Apache sigue pudiendo escribir, porque corre con tu usuario.
  - **Más ficheros que no se sirven:** claves (`.pem`, `.key`, `.p12`), `.ini`, `.conf` y las exportaciones de clientes de PrestaShop (`customers_export_*.csv`).
  - Un dominio guardado para un proyecto solo se falsea si ya tiene su vhost o se parece al nombre de la carpeta.
  - **Registrar un XAMPP** de `/opt/lampp` ya no borra su htdocs si tiene proyectos: se aparta en `/opt/htdocs-de-lampp-<versión>-<fecha>` y sus vhosts se copian a `~/lvm-copias`.
  - El acceso del menú y el comando `lvm-instalador` del paquete siguen apuntando al script de `/opt` aunque se ejecute una copia desde Descargas.
- **phpMyAdmin por `localhost` (desde la 1.42.2):** `http://localhost/phpmyadmin` (un marcador antiguo o la costumbre de XAMPP) lleva directamente a `http://127.0.0.1/phpmyadmin/`, a su portada y sin lo que llevara detrás. Por `web.local`, el dominio de un proyecto o uno sin vhost sigue dando el aviso «phpMyAdmin está en http://127.0.0.1/phpmyadmin/». Se aplica con **Protegerlas**.
- **`web.local` que no lleva a este equipo (desde la 1.42.2):** si en `/etc/hosts` `web.local` apunta a otra dirección (por ejemplo `127.0.1.1`, la que Ubuntu usa para el nombre del equipo) o no está, el navegador da «No se puede acceder a este sitio web» (`ERR_CONNECTION_REFUSED`), porque Apache solo escucha en `127.0.0.1`. La pestaña **Hosts** lo avisa y **Arreglarlo** lo cambia una sola vez (con copia del `/etc/hosts` anterior en `~/lvm-copias`).
- **Probar un proyecto con otra versión de PHP:** en la pestaña **BBDD**, el botón de copiar (dos hojas) junto a cada BBDD la copia a otra versión, eligiendo en una ventana. La de origen no se toca. Si esa versión ya tiene una BBDD con ese nombre, sale marcada «ya la tiene: se sustituye»: se pide confirmación, se guarda antes una copia de la suya en `~/lvm-copias` y se pone la nueva en su lugar (desde la 1.45.1 / Mac 1.33.1; en la terminal, con `--sustituir`). Si la de destino no es la activa, se arranca su MariaDB solo para la copia (sin red; pide la contraseña), y la copia se carga igual de protegida que al subir un volcado (usuario de la BBDD, sin `DEFINER`, lo `INVOKER` y los eventos neutralizados). Después, **Cargar proyecto** pregunta en qué versión cargarlo. En la terminal: `lvm-instalador copiar-bd <base> <origen> <destino>`.
- **Montar un proyecto nuevo de GitHub (desde la 1.44.0 / Mac 1.32.0):** en **Cargar proyecto**, el botón **Montar nuevo proyecto**, a la derecha del buscador, despliega un asistente de tres pasos: 1) la dirección del repositorio (`https://github.com/usuario/repositorio.git`, o `git@github.com:usuario/repositorio.git` si es privado, con tu clave SSH) y el nombre de la carpeta; 2) la versión de PHP; 3) el nombre de la BBDD nueva y, si lo hay, su volcado (`.sql`, `.sql.gz` o `.zip`). Se clona en htdocs con tu usuario (sin sudo, sin submódulos, sin ganchos y solo por https o ssh), se carga en esa versión, se crea la BBDD y se sube el volcado con la carga protegida. En la terminal: `lvm-instalador montar-proyecto <url> <carpeta> <versión> <base> [volcado]`.
- **Administrador de pruebas en los paneles (desde la 1.45.0 / Mac 1.33.0):** al cargar una BBDD de WordPress o PrestaShop (subir un volcado, copiarla a otra versión o montar un proyecto nuevo) se le añade un administrador **`local@local.test`** con contraseña **`local`**, el mismo en todos los equipos. En **Cargar proyecto**, el botón del panel (WordPress o PrestaShop) abre una página con los dos ya escritos: solo hay que pulsar **Entrar**. Si la BBDD ya estaba cargada de antes, se crea al pulsar el botón. En WordPress es un usuario con rol de administrador; en PrestaShop, una copia del primer SuperAdmin (su idioma y su tema) en todas las tiendas. Los usuarios de verdad no se tocan. En PrestaShop 1.6 hace falta la carpeta del proyecto (por su `_COOKIE_KEY_`): se carga desde Cargar proyecto. En la terminal: `lvm-instalador usuario-pruebas <base> [carpeta]`. Es un riesgo aceptado a propósito: esas BBDD solo viven en tu equipo y nunca se suben a producción (si alguna vez exportas una para otro sitio, borra antes ese usuario).
- **Desmontar el proyecto cargado:** el botón de expulsar, junto a «web.local → proyecto», hace que `web.local` deje de apuntar a él y enseñe una página vacía («No hay ningún proyecto cargado»). El enlace sigue existiendo y apunta a la carpeta oculta `htdocs/.lvm-sin-proyecto`. Si era una tienda PrestaShop, su dominio deja de estar falseado. En la terminal: `lvm-instalador desmontar-proyecto`.
- **Aviso en rojo en Cargar proyecto:** si la versión de PHP montada no tiene la BBDD del proyecto cargado (por ejemplo, al activar otra versión a mano), sale «El proyecto vinculado a web.local no está disponible para esa versión», con las versiones que sí la tienen.
- **Fecha y parches de seguridad:** en **Instalar nuevas versiones de PHP**, cada versión dice cuándo se publicó y si php.net la marca como **Parche de seguridad** (corrige vulnerabilidades) o **Corrección de errores**.
- **Octavo repaso de seguridad (1.44.0 / Mac 1.32.0):** Cerrar procesos ya no se puede engañar con un proceso de nombre trucado; copiar una BBDD a otra versión ya no deja un programa tuyo en la terminal que tiene el permiso de administrador; los volcados se cargan con sus vistas y funciones `INVOKER` cambiadas a `DEFINER` desde el principio, y al terminar el usuario de la BBDD se vuelve a crear solo con su BBDD; el MariaDB temporal nunca corre como administrador; y si una versión no se puede dejar solo para este equipo, no se arranca. No hay que hacer nada: se aplica al actualizar.
- **Noveno repaso de seguridad (1.45.0 / Mac 1.33.0):** se aplica al actualizar y, lo de Apache, con **Protegerlas**.
  - El cliente de MariaDB y `mysqldump` de los XAMPP ya no leen `~/.my.cnf` (un programa tuyo podía prepararlo para que cargaran una biblioteca suya en la terminal que ya tenía el permiso de administrador). Por lo mismo, git, ssh y certutil van fuera de esa terminal y curl sin `~/.curlrc`.
  - La contraseña de administrador solo se manda a un `sudo` de verdad de la tarea (de root, en su terminal y esperando): un programa que escribiera la marca de sudo ya no hace salir el cuadro.
  - **Editar /etc/hosts:** una línea con un retorno de carro (`\r`) en medio ya no se salta la comprobación.
  - **Montar nuevo proyecto con una tienda:** el dominio de su base ya no se falsea solo, porque la base y el nombre de la carpeta vienen con el repositorio. Si es el suyo: pestaña **Hosts → Nuevo proyecto con dominio falseado**, con la carpeta del proyecto y ese dominio. Por SSH solo se clona de servidores cuya clave ya conoces y de GitHub, GitLab y Bitbucket (sus claves publicadas van en el gestor); para otro servidor (el de un compañero, un GitLab propio), conéctate antes una vez en la terminal para comprobar y aceptar su clave: `ssh -T git@servidor`. Tampoco se descarga nada con git-lfs.
  - **Un `Listen` abierto a la red en los vhosts compartidos** (puesto a mano siguiendo alguna guía) ya no pasa sin aviso: la versión no se arranca hasta quitarlo con **Herramientas → Editar vhosts**.
  - **Más ficheros que no se sirven:** la carpeta `wpallimport` de WP All Import/Export (con los `.zip` y `.xml` de clientes), las exportaciones de clientes de PrestaShop también en `.zip`, `.xml` o `.xlsx`, y `.my.cnf`, `.netrc`, `.pgpass`, `credentials*.json`, `.aws` y `.docker`.
  - Otros: `PHP_TIMEZONE`, el correo de git que va en `ServerAdmin` e `importar-bd --proyecto` se comprueban antes de usarlos; los nombres de carpetas, bases y dominios solo admiten letras sin tilde aunque el equipo esté en español (como ya hacía la ventana); el script de las versiones propias solo cierra el MariaDB de su `.pid`; los vhosts de versiones antiguas pasan al administrador sin seguir enlaces, y las versiones de php.net se validan antes de enseñarlas.
- **«Ha habido un error crítico en esta web»:** es un error de PHP, muchas veces de un plugin que no funciona con la versión de PHP cargada (por ejemplo, uno que usa `create_function()`, que no existe desde PHP 8). En **Herramientas → Registro de errores**, el primero es el registro del vhost del proyecto cargado (`web.local-error_log`), donde van los errores de PHP con PHP-FPM: **Ver el final** enseña lo último, con el fichero y la línea del error. Debajo está el general de Apache.
- **Buenas costumbres** (no las impone el gestor):
  - Abre cada proyecto por su vhost (`web.local` o su dominio) y no por `http://localhost/<carpeta>`: en `localhost` todos los proyectos comparten origen y un fallo XSS en uno alcanzaría a los demás.
  - En Visual Studio Code, abre los proyectos de clientes en **modo restringido** y no confíes en toda la carpeta htdocs: un `tasks.json` o unos ajustes de un proyecto se ejecutarían al abrirlo.
  - No guardes en htdocs copias de seguridad, exportaciones de clientes ni claves: aunque el gestor no las sirva, cualquier programa con tu usuario las puede leer.
- **El FTP no arranca solo.** Se arranca en la pestaña Servicios cuando haga falta.
- **Volcados SQL.** Se cargan con `--binary-mode --local-infile=0`: el volcado solo puede llevar SQL. Un `.sql` manipulado no puede ejecutar programas (`\! orden`, `system`) ni leer ficheros del equipo. La línea `/*M!999999\- enable the sandbox mode */` se sigue quitando, para que cargue en el MariaDB 10.4 de XAMPP.
- **Vhosts del administrador.** Apache los lee como root: si fueran tuyos, un plugin de una web podría añadirles una orden que se ejecutaría como root. Se editan con una copia que se comprueba antes de aplicarla.
- **Ficheros de los proyectos.** Si `wp-config.php`, `parameters.php`, `settings.inc.php` o `var/cache` son enlaces a otra carpeta, no se tocan. Los nombres de bases, prefijos de tablas y carpetas que vienen de un proyecto se comprueban antes de usarlos en consultas o en los vhosts.
- **Contraseña de administrador.** La ventana solo la envía si la pide un `sudo` de verdad de la tarea (de root, en su terminal y con el eco apagado).
- **Actualizaciones.** El `.deb` de Descargas se busca solo desde Herramientas. Antes de instalarlo se muestran su fecha y su huella SHA-256, y no se acepta un paquete que lleve ficheros fuera de los suyos.
- **Copias.** `~/lvm-copias` y `~/.lvm-instalador` (copias de bases y de configuraciones con contraseñas) solo son accesibles para tu usuario.

Límite que no se puede cerrar desde el gestor: un programa que ya corre con tu usuario puede cambiar tus accesos directos (`~/.local/share/applications`) o tu `.bashrc` y mostrarte una ventana falsa que pida la contraseña. El gestor solo la pide en su ventana o en la de polkit; si algo la pide de forma rara, no la escribas.

Lo que sigue igual a propósito: MariaDB con root sin contraseña y Apache con tu usuario, para trabajar en local con comodidad. Por eso, un plugin malicioso de una web puede leer las demás bases y los ficheros de tu usuario: conviene no cargar proyectos de origen dudoso.

## Avisos importantes

- **Cada versión tiene sus propias bases de datos.** Para probar un proyecto en una versión nueva, exporta su base de datos desde phpMyAdmin con la versión antigua activa e impórtala con la nueva.
- **Instalar un XAMPP para temporalmente la versión activa** (el instalador oficial siempre usa `/opt/lampp`). Al terminar se vuelve a activar sola. Instalar un PHP nuevo no la para.
- **MariaDB de cada versión es distinta.** Una base de datos exportada desde una MariaDB antigua se importa sin problemas en una más nueva. Al revés también funciona normalmente, gracias al cotejamiento `utf8mb4_general_ci`.
- Las versiones de PHP instaladas con el script antiguo (que copiaban un XAMPP) siguen funcionando y aparecen como `sobre X`. Se pasan a pila propia con **Actualizar versiones de PHP**.
- **`.htaccess` con `php_value` o `php_flag`** da error 500 en las versiones de PHP nuevas (PHP-FPM). Esos valores van en un archivo `.user.ini` en la carpeta del proyecto.
- La zona horaria de PHP es `Europe/Madrid`. Para otra: `PHP_TIMEZONE=Europe/London lvm-instalador`.
- Extensiones de PHP incluidas en las versiones nuevas: mysqli, pdo_mysql, gd (jpeg, webp, freetype), intl, mbstring, zip, curl, soap, bcmath, exif, sodium, opcache, sqlite. **No incluye imagick.**

---

## Solución de problemas

| Síntoma | Qué revisar |
|---|---|
| Error 503 en una versión PHP nuevo | `sudo /opt/lampp/lampp status` y `sudo tail /opt/lampp/logs/php-fpm.log` |
| MariaDB no arranca | `sudo tail /opt/lampp/var/mysql/mysqld.err` |
| Errores de PHP | `/opt/lampp/logs/error_log` |
| Una instalación de PHP falla | No queda nada instalado. Los logs de la compilación se guardan en `~/.lvm-instalador/pila-<versión>-<fecha>/` |
| Una instalación de XAMPP falla a medias | Revisa el log indicado al final y borra la versión con `lvm-instalador desinstalar <version>` |
| Logs de cada instalación | `~/.lvm-instalador/` |
| Volver a la versión anterior | `lvm-instalador use <version>` |
| Al actualizar: «El paquete trae otro /opt/lvm-instalador/lvm-actualizar» y «Tubería rota» | No es un error: esa versión cambia el ayudante de actualización (la 1.44.0, viniendo de la 1.43 o anterior). Se instala una vez en la terminal: `sudo apt install ~/Descargas/lvm-instalador_<versión>_all.deb`. Desde la 1.45.0 la ventana lo explica y copia la orden |

---

## Versión para macOS

En [`macos/`](macos/README.md) está la versión para Mac con Apple Silicon (M1 o posterior): `macos/lvm-instalador.sh`, con los comandos `lvm-instalador` y `lvm`. Instala las versiones de PHP en `/Applications/XAMPP-X.Y`, al estilo de XAMPP para Mac, y usa Homebrew solo para las librerías. Desde la 1.2.0 tiene ventana nativa (SwiftUI) con las mismas pestañas que la de Linux, y la misma gestión de bases de datos: cargar copias, crear y borrar. Las instrucciones están en su propio README.

---

By M.Mascuñano - HEXER
