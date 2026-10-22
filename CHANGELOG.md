# Novedades de Nexum Stack

Todo lo que ha incluido cada versión de Nexum Stack para Linux (antes LAMPP Version Manager y PHP Version Manager), de la más reciente a la primera. Es la misma lista que se ve en la ventana (menú ☰ → Novedades) y con `lvm-instalador novedades`.

[← Volver al README](README.md)

## 1.49.0 · 22 oct 2026

- **Nuevo nombre:** Nexum Stack (antes LAMPP Version Manager). Cambian el título de la ventana, el nombre del icono del menú y los textos; los comandos (lvm-instalador, lvm), las carpetas y el funcionamiento siguen igual.
  - Esta versión se instala una vez en la terminal (sudo apt install): cambian los textos de su ayudante y de la ventana de la contraseña.

## 1.48.0 · 22 oct 2026

- **Subir o actualizar una BBDD:** si la base ya existe, ahora siempre se borran todas sus tablas antes de cargar la copia (antes era una opción, «Vaciar la BBDD antes de cargar», que venía apagada). Sin vaciarla, las tablas que la copia ya no trae se quedaban, y una copia de phpMyAdmin (no lleva DROP TABLE) cargada otra vez tras un error sumaba sus filas a las de antes: así se repitieron filas y faltaron claves primarias en una base de WordPress. Si la base tiene tablas, antes se guarda una copia suya en `~/lvm-copias` (…`-antes-de-cargar-fecha.sql.gz`); si no se puede guardar, no se toca nada, y si la carga falla, se dice dónde está. Copiar una BBDD a otra versión que ya la tiene sigue igual (ya guardaba su copia). En la terminal: importar-bd <fichero> <base> [--crear] [--sin-copia]; --vaciar se sigue admitiendo, pero ya no hace falta.

## 1.47.0 · 22 oct 2026

- Tiendas con dominio real (las falseadas en `/etc/hosts`): el navegador ya no avisa con «La conexión no es privada» mientras están falseadas, así que Claude in Chrome también puede abrirlas. Al falsear una, Chrome, Chromium y Firefox aceptan su certificado propio; al dejar de falsearla (o al cargar otro proyecto), dejan de aceptarlo. Así, con su clave (Apache la tiene en memoria) no se puede suplantar la web de verdad: mientras está falseada, el navegador no va a ella. Si cambias `/etc/hosts` a mano, sale el aviso «El navegador acepta webs reales que ya no están falseadas» con el botón Quitar. En la terminal: lvm-instalador confiar-certificados --quitar.
- Prefijo de las tablas al rehacer `wp-config.php`: siempre uno que traen las tablas de la base (las tablas nunca se cambian ni se renombran). Si la base tiene tablas de varios WordPress, se usa el del `wp-config.php` del proyecto (antes ganaba el de la copia de este equipo) y, si ninguno está en la base, ya no se escribe un prefijo sin tablas: no se toca y se avisa. En las tiendas con varios prefijos, el que ya usaba su configuración si la base lo tiene.

## 1.46.0 · 22 oct 2026

- **Certificados de los proyectos:** el navegador ya no avisa con «La conexión no es privada». Desde que Arreglarlos quitó la CA común, cada proyecto https lleva su propio certificado y Chrome avisaba en todos; con el aviso, las herramientas que manejan el navegador (como Claude in Chrome) no podían abrirlos. Ahora Chrome, Chromium y Firefox aceptan el certificado de cada proyecto con un dominio de pruebas (web.local, .local, .test), solo ese y solo para su dominio (no una CA: no vale para ninguna otra web). Los de un dominio real (las tiendas falseadas en `/etc/hosts`) siguen avisando: Apache tiene su clave en memoria, donde la puede leer el PHP de cualquier web, y con ella se podría suplantar la web de verdad. Se hace solo al arreglar los certificados y al crear el vhost de un proyecto o una tienda; para los que ya estaban, sale el aviso «El navegador avisa al abrir estos proyectos» con el botón Confiar. Después cierra el navegador y vuelve a abrirlo. En la terminal: lvm-instalador confiar-certificados [dominio].

## 1.45.1 · 22 oct 2026

- **BBDD, copiar a otra versión:** ahora salen también las versiones que ya tienen esa BBDD, marcadas «ya la tiene: se sustituye». Al elegir una, se pide confirmación, se guarda antes una copia de la suya en `~/lvm-copias` y se pone en su lugar la de origen (por ejemplo, para volver a copiar a la 8.4 una BBDD que ya se había copiado antes desde la 8.2.4). En la terminal: copiar-bd <base> <origen> <destino> --sustituir.

## 1.45.0 · 22 oct 2026

- **Administrador de pruebas en los paneles:** al cargar una BBDD de WordPress o PrestaShop se le añade un administrador local@local.test con contraseña local (el mismo en todos los equipos; las BBDD de este equipo nunca van a producción). En Cargar proyecto, el botón del panel abre una página con los dos ya escritos: solo hay que pulsar Entrar. Con las BBDD que ya estaban cargadas, se crea al pulsar el botón. En la terminal: lvm-instalador usuario-pruebas <base> [carpeta].
- **Seguridad (noveno repaso):**
  - El cliente de MariaDB y mysqldump de XAMPP ya no leen `~/.my.cnf`: cualquier programa tuyo podía prepararlo para que cargaran una biblioteca suya con el permiso de administrador que la tarea ya tenía. Por lo mismo, git, ssh, certutil y curl van sin tu configuración o fuera de la terminal de la tarea.
  - La contraseña de administrador solo se manda a un sudo de verdad de la tarea: un programa que escribiera la marca de sudo ya no hace salir el cuadro de la contraseña.
  - Editar `/etc/hosts`: una línea con un retorno de carro (CR) en medio se saltaba la comprobación y podía llevar cualquier dominio a otra IP.
  - **Montar nuevo proyecto:** el dominio de una tienda (el de su base) ya no se falsea solo, porque la base y el nombre de la carpeta vienen con el repositorio. Si es el suyo, se crea en la pestaña Hosts (Nuevo proyecto con dominio falseado). Por SSH solo se clona de servidores cuya clave ya conoces (y de GitHub, GitLab y Bitbucket), y sin git-lfs.
  - Un Listen abierto a la red en los vhosts compartidos ya no pasa sin aviso: la versión no se arranca hasta quitarlo (Editar vhosts).
  - Tampoco se sirven por la web las exportaciones de clientes de WP All Import (carpeta wpallimport), las de PrestaShop en .zip o .xml, ni .`my.cnf`, .netrc, .pgpass, credentials*.json, .aws o .docker.
  - **Otros:** PHP_TIMEZONE, el correo de git en ServerAdmin y importar-bd --proyecto se comprueban antes de usarlos; los nombres solo admiten letras sin tilde (como en la ventana) aunque el equipo esté en español; las versiones de php.net se validan antes de enseñarlas.
  - El script lampp de las versiones propias solo cierra el MariaDB de su .pid (lo escribe mysql) y los vhosts de versiones antiguas pasan al administrador sin seguir enlaces.
- **Actualizar desde la ventana:** si la versión nueva hay que instalarla una vez en la terminal (cambia el programa que instala las actualizaciones), ya no sale el error de dpkg («Tubería rota»): se explica y hay un botón para copiar la orden (sudo apt install …).

## 1.44.2 · 22 oct 2026

- **Seguridad:**
  - `~/lvm-copias` (copias de BBDD de clientes, vhosts y `/etc/hosts` anteriores) es siempre solo tuya, aunque ya existiera con otros permisos. Las copias que se descargan con exportar-bd, también.
  - **Vaciar la base antes de cargar:** si el volcado no se puede cargar (motores FEDERATED, CONNECT o SPIDER activos), ya no se borra antes.
  - **Pestaña Hosts:** los .local ya no se apagan (no existen fuera y, sin su línea, el equipo los preguntaba a la red, donde cualquiera de la misma wifi podía contestar). Los que estaban apagados vuelven a encenderse.
  - La contraseña temporal del usuario de la BBDD ya no se ve con ps mientras se carga un volcado.

## 1.44.1 · 21 oct 2026

- **Versiones, Instalar:** la fecha de publicación va junto a la versión de PHP, y «Parche de seguridad» es solo texto azul (sin fondo).
- **Cargar proyecto:** el título va fuera del recuadro, como en los demás apartados; el recuadro tiene más aire arriba y abajo, y el buscador y «Montar nuevo proyecto» van más separados de los botones del proyecto.
- **Otro parche:** la ventana es más ancha (la versión ya no sale cortada).

## 1.44.0 · 21 oct 2026

- **Seguridad (octavo repaso):**
  - **Cerrar procesos:** un programa que se pusiera un nombre trucado podía hacer que el gestor cerrara como administrador otros procesos, o todos los del equipo. Ahora los nombres se limpian y solo se cierran números de proceso de verdad.
  - **Copiar una BBDD a otra versión:** el programa auxiliar del cliente de MariaDB estaba en tu carpeta, y otro programa tuyo podía cambiarlo y conseguir permisos de administrador. Ahora va en una carpeta del administrador. Si se cancela la copia, no queda el volcado temporal.
  - **Subir un volcado:** sus vistas y funciones «SQL SECURITY INVOKER» se cargan ya como «DEFINER», así que, aunque la web o phpMyAdmin las lean a mitad de la carga, no se ejecutan como root. Al acabar, el usuario de la BBDD se vuelve a crear con permisos solo sobre su BBDD.
  - El MariaDB temporal (copiar o descargar una BBDD de otra versión) nunca se arranca como administrador.
  - Si no se puede dejar una versión solo para este equipo, ya no se arranca (al cargar un proyecto, Servicios, Arrancar o Reiniciar).
  - **Actualizar desde la ventana:** el ayudante ya no deja que apt instale otros paquetes «recomendados» o «sugeridos». Por eso esta versión se instala una vez en la terminal: sudo apt install `~/Descargas/lvm-instalador_1.44.0_all.deb` (las siguientes, otra vez desde la ventana).
- **Versiones, Instalar:** cada versión de PHP lleva la fecha en que se publicó y si es un parche de seguridad (según php.net) o solo de errores.
- **Cargar proyecto:** solo dice a dónde apunta web.local (sin «Cargado ahora:», para que quepa el nombre entero) y, junto al nombre, un botón para desmontar el proyecto (web.local enseña una página vacía). Los botones van, de derecha a izquierda, en este orden: VS Code, phpMyAdmin, wp-admin y web.local, y son algo más grandes. Si la versión montada no tiene la BBDD del proyecto cargado, sale un aviso en rojo.
- **Montar nuevo proyecto:** botón junto al buscador de proyectos. Se despliega un asistente de tres pasos: la dirección del repositorio de GitHub (se clona en htdocs), la versión de PHP y la BBDD nueva, con su volcado si lo hay. Al terminar, el proyecto queda cargado. En la terminal: lvm-instalador montar-proyecto <url> <carpeta> <version> <base> [volcado] y lvm-instalador desmontar-proyecto.
- Los mensajes que salen al dejar el ratón encima tienen el aspecto de la ventana: gris oscuro y con las esquinas redondeadas.
- **Herramientas, Registro de errores:** ya no enseña el último error.
- **Comandos:** cada uno en su línea, con lo que hace debajo, separados por secciones resaltadas.
- **Novedades:** más espacio entre versiones, puntos y líneas.

## 1.43.1 · 21 oct 2026

- **Herramientas, Registro de errores:** primero el registro del vhost del proyecto cargado (web.local-error_log), que es donde van los errores de PHP de la web (el «error crítico» de WordPress) con PHP-FPM. Se ve el último error de PHP resumido: el mensaje, el fichero y la línea. Debajo, el general de Apache. «Ver el final» separa en líneas los mensajes de PHP-FPM, que llegan todos en una.

## 1.43.0 · 21 oct 2026

- **BBDD:** botón para copiar una BBDD a otra versión de PHP que no la tenga, para probar si el proyecto funciona con ese PHP. Se elige la versión en una ventana; la de origen no se toca. Si la de destino no es la activa, se arranca su MariaDB solo para la copia (pide la contraseña). La copia se carga igual de protegida que al subir un volcado. Después, al cargar el proyecto, se pregunta en qué versión. En la terminal: lvm-instalador copiar-bd <base> <origen> <destino>

## 1.42.3 · 21 oct 2026

- Cargar proyecto con la BBDD en varias versiones: la pregunta es más corta y cabe en una línea («¿Qué versión del proyecto y de PHP quieres?»).
- La versión elegida va solo con el borde verde de su tarjeta (ya no sale también el recuadro del botón de radio).

## 1.42.2 · 21 oct 2026

- **Pestaña Hosts:** aviso «web.local no lleva a este equipo» con el botón Arreglarlo, si en `/etc/hosts` web.local apunta a otra dirección (como 127.0.1.1, la del nombre del equipo en Ubuntu) o no está. Apache solo escucha en 127.0.0.1 y el navegador daba «No se puede acceder a este sitio web» (ERR_CONNECTION_REFUSED). Se arregla una sola vez.
- phpMyAdmin abierto por localhost (un marcador antiguo o la costumbre de XAMPP) ya no da el aviso de error: lleva directamente a su dirección buena, 127.0.0.1/phpmyadmin. Por web.local u otro dominio sigue dando el aviso. Pulsa Protegerlas para aplicarlo a las versiones instaladas.

## 1.42.1 · 21 oct 2026

- **Cargar proyecto:** el proyecto cargado tiene ahora cuatro botones de icono, todos del mismo tamaño (al dejar el ratón encima se ve qué abre cada uno):
  - **Bola del mundo:** el proyecto en el navegador (web.local). Sustituye al botón verde «Abrir web.local».
  - **phpMyAdmin:** su BBDD directamente.
  - **WordPress o PrestaShop:** su panel de administración (wp-admin, o el back office de la tienda, se llame como se llame su carpeta).
  - Visual Studio Code, como antes.

## 1.42.0 · 21 oct 2026

- **Nuevo aviso en Versiones:** «Tablas del sistema de MariaDB antiguas». Las de algunas versiones vienen de una MariaDB anterior y el servidor llena su registro de errores (en una 8.2.4 llegó a 28 GB). Repararlas las pone al día sin tocar las BBDD de los proyectos (copia antes en `~/lvm-copias`) y vacía el registro si es grande.
- Registrar un XAMPP de `/opt/lampp` ya no borra su htdocs si tiene proyectos (se aparta en `/opt/htdocs-de-lampp-`...) y guarda sus vhosts en `~/lvm-copias`.
- Seguridad (séptimo repaso). Pulsa Protegerlas otra vez para aplicarlo:
  - **Volcados:** aunque se cierre la ventana a mitad de la carga, no queda nada INVOKER ni ningún evento; un evento que ya estuviera en marcha se corta, y al terminar el usuario de la BBDD ya no puede crear vistas, rutinas ni eventos. Root repasa la base al final. No se carga si MariaDB tiene activos FEDERATED, CONNECT o SPIDER.
  - **Vhosts:** un registro o un certificado entre comillas con espacios ya no puede llevar a otra carpeta (Apache lo abre como root). Los certificados nuevos, solo de las carpetas del gestor (los que ya tenías siguen valiendo), y los registros no pueden llamarse como sus ficheros de control.
  - Los dominios .local de los vhosts van siempre en hosts (si no, el equipo los pregunta a la red y otro de la misma wifi podría contestar).
  - Protegerlas y Cargar proyecto quitan la escritura para cualquier usuario en htdocs (plugins que dejan carpetas en 777).
  - **Más ficheros que no se sirven:** claves (.pem, .key, .p12, id_rsa, la carpeta .ssh), bases SQLite, .ini, .conf y las exportaciones de clientes de PrestaShop (customers_export).
  - Un dominio guardado para un proyecto solo se falsea si tiene su vhost o se parece a la carpeta.
  - Una carpeta de proyecto manipulada (un FIFO) ya no cuelga la ventana.
  - El acceso del menú y el comando lvm-instalador del paquete siguen apuntando al script de `/opt` aunque se ejecute una copia de Descargas.
  - Instalar versiones rechaza enlaces duros a ficheros de otros.

## 1.41.0 · 21 oct 2026

- **Cargar proyecto:** botón con el icono de Visual Studio Code a la derecha de «Abrir web.local». Abre la carpeta del proyecto cargado; si ya está abierta en VS Code, trae su ventana delante (no abre otra).
- Seguridad (sexto repaso, tras otra auditoría). Pulsa Protegerlas en el aviso de Versiones para aplicarlo a las versiones ya instaladas:
  - **phpMyAdmin:** una web abierta en el navegador ya no puede enviarle una consulta (un formulario o un fetch a 127.0.0.1). Desde otra web solo se abre su portada; escribiendo la dirección o desde el gestor, igual que siempre.
  - MariaDB ya no lee ni escribe ficheros del equipo desde SQL (LOAD_FILE, INTO OUTFILE, LOAD DATA LOCAL): secure_file_priv en una carpeta vacía de cada versión (etc/lvm-sin-ficheros).
  - **Más ficheros que no se sirven:** registros .log, .yml (docker-compose lleva las claves), copias de `wp-config.php` y copias de seguridad de las webs (.wpress, Duplicator, UpdraftPlus...).
  - **Instalar versiones y actualizar phpMyAdmin:** lo compilado no puede llevar enlaces fuera de la versión, y las carpetas tmp las crea root.
  - Protegerlas prepara los ficheros como root en una carpeta de root, y los certificados de los proyectos los crea root.
  - **Volcados:** se borran los eventos programados y las tablas que guardan sus ficheros fuera de MariaDB (DATA DIRECTORY), y se avisa.
  - El MariaDB temporal de las copias solo se para por su propio .pid, y los nombres raros de un proyecto o un .zip ya no cambian lo que se ve en la terminal.

## 1.40.1 · 21 oct 2026

- **Ventana:** los títulos de los apartados ya no llevan icono; lo lleva cada fila (Virtual hosts, Hosts del sistema, error_log, Comandos, Novedades...).

## 1.40.0 · 21 oct 2026

- Seguridad (quinto repaso, tras otra auditoría):
  - **Actualizar desde la ventana:** el ayudante exige que cada fichero del paquete sea de root y con sus permisos (sin setuid ni escritura para otros) y lee los scripts de instalación sin seguir enlaces.
  - **Volcados:** una vista rota en el volcado ya no deja a medias el paso de SQL SECURITY INVOKER a DEFINER; lo que no se pueda pasar se borra y se avisa.
  - **Certificados:** los de los proyectos se guardan en `/opt/config/ssl`, no en `/etc/ssl/certs` (allí el sistema los daba por buenos para cualquier web). Nuevo aviso «Certificados en los que confía todo el equipo» con el botón Arreglarlos (arreglar-certificados): pone un certificado propio a cada proyecto https y quita la confianza a las CAs locales sin límite de dominios que los firmaban.
  - Los certificados se crean con tu usuario y solo en la carpeta del gestor (nunca donde diga un vhost). Dominios guardados validados.
  - Protegerlas corrige también lo que ya estaba abierto (Listen con la IP de la red, bind-address 0.0.0.0, DefaultAddress, puertos de más) y cambia la clave SSL de fábrica de XAMPP, igual en todos.
  - **Más ficheros que no se sirven:** .dump, .old, .orig, copias~, error_log, auth.json, .npmrc, .sql.xz y .sql.bz2.
  - Lo compilado se copia a `/opt` sin conservar el dueño ni el setuid. Root ya no sigue enlaces al escribir la configuración de un proyecto ni al vaciar la caché de una tienda.
  - La ventana usa los programas del sistema (no los de `~/.local/bin`).
  - Al instalar no se usa la caché de descargas, y phpMyAdmin lleva siempre sus huellas fijadas.
  - Lo que se compila corre sin la terminal de la tarea: aunque un programa tuyo lo cambie, no puede usar el permiso de sudo ya dado.
  - **Cerrar procesos de otras versiones:** un .pid manipulado ya no hace que se cierre otro programa del sistema ni la versión montada.
  - Las tareas de la ventana reciben solo las variables necesarias (ni funciones exportadas de bash ni las de prueba del gestor).
  - Protegerlas no deja dos Listen iguales (Apache no arrancaría).
  - Una CA local solo se avisa y se quita si su clave está en tu carpeta; también se apartan los certificados viejos sin usar de `/etc/ssl/certs` y se crean los que falten.
  - Esta versión se instala una vez en la terminal (sudo apt install): su ayudante cambia.

## 1.39.1 · 20 oct 2026

- **Ventana:** «BBDD» en lugar de «base de datos» en todos los textos.

## 1.39.0 · 20 oct 2026

- Seguridad (cuarto repaso, tras otra auditoría):
  - La contraseña de administrador va por una terminal exclusiva: ningún otro programa de tu usuario puede abrirla para leerla. La ventana no se puede inspeccionar desde fuera.
  - **Actualizar:** el ayudante revisa el paquete con tarfile (sin enlaces ni ficheros especiales), exige la huella, que el propio ayudante y la acción de polkit sean los instalados y las mismas dependencias. `/opt` pasa a ser del administrador al instalar el paquete.
  - Vhosts y `/etc/hosts`: se leen como los lee el sistema (por bytes); un carácter de control como el nulo hacía que Apache viera una línea que la comprobación no veía.
  - **Volcados:** cada base tiene su usuario (lvm_bd_<base>), con el permiso solo para ella (el _ ya no vale por cualquier carácter), que se bloquea al terminar: sus disparadores y vistas siguen funcionando (en la 1.37 dejaban de hacerlo). Sus vistas y funciones SQL SECURITY INVOKER pasan a DEFINER, y el gestor solo lee como root tablas de verdad.
  - Reglas web sin distinguir mayúsculas (.ENV, .GIT) y más ficheros que no se sirven: copias .sql, `debug.log`, .vscode, `config.inc.php`. Una web de fuera ya no puede leer la API de tus WordPress (CORS).
  - Los `wp-config.php` que prepara el gestor desactivan el editor de plugins y temas (DISALLOW_FILE_EDIT).
  - phpMyAdmin se actualiza con huellas fijadas y solo si la versión es de root. El dominio de una tienda solo se falsea si su nombre va en la carpeta (prestashop.com ya no vale).
  - Los ficheros raros en un proyecto (FIFO, `/dev/zero`) ya no cuelgan la lista, y todos los python3 van con -I.
  - **FTP de XAMPP:** solo entra tu usuario. TRACE desactivado.
  - Esta versión se instala una vez en la terminal (sudo apt install): su ayudante y su postinst cambian.

## 1.38.1 · 20 oct 2026

- **Barra lateral:** filas más altas, como las de Configuración de Ubuntu.

## 1.38.0 · 20 oct 2026

- **phpMyAdmin tiene su propia dirección:** http:/`/127.0.0.1/phpmyadmin/` (los botones ya la abren). En 127.0.0.1 no hay nada más, y en localhost, web.local o los dominios falseados da 403. Así, un fallo XSS en un proyecto (que va en localhost/carpeta o en su dominio) no puede leer phpMyAdmin: para el navegador es otra web.
- **Actualizar phpMyAdmin:** botón Actualizar en su fila de cada versión y aviso en Versiones (Actualizarlos) cuando trae uno con fallos ya corregidos. Pone el más nuevo que admite su PHP (5.2.x desde PHP 7.2.5, 5.1.4 para PHP 7.1), comprobado con su sha256, con la misma configuración y una clave de cookies nueva si era la de fábrica. El anterior queda en phpmyadmin.anterior.
  - **En la terminal:** lvm-instalador actualizar-phpmyadmin <versión> o --todas.

## 1.37.0 · 20 oct 2026

- Seguridad (tercer repaso, tras una auditoría completa):
  - `/opt` vuelve a ser del administrador: el PHP de una web ya no puede cambiar `/opt/lampp` ni `/opt/lvm-instalador` para que lo siguiente que se arranque con sudo sea suyo. Tus carpetas de dentro no cambian.
  - Aplicar vhosts y `/etc/hosts`: la copia se lee una sola vez a una carpeta de root y se comprueba y escribe esa misma. En los vhosts ya no se admiten Define ni variables, y los registros solo pueden ir a un fichero de logs.
  - **Actualizar:** el ayudante copia el paquete a una carpeta de root y comprueba allí su huella SHA-256 (la que se te ha mostrado), sus ficheros y sus scripts de instalación.
  - Todas las versiones quedan solo para este equipo (también las que no están montadas). Si una no se puede proteger, no se arranca. Versiones avisa de las que faltan, con el botón Protegerlas.
  - phpMyAdmin solo desde localhost, sin su asistente setup. Los .env y los .git de los proyectos ya no se ven por el navegador. Dominios desconocidos rechazados también por https.
  - Los volcados se cargan con un usuario temporal que solo puede tocar su base (sin DEFINER). Un volcado de una web comprometida no puede cambiar otras bases, crear usuarios ni leer o escribir ficheros.
  - MariaDB de XAMPP sin el usuario anónimo ni los permisos de las bases test. FTP de XAMPP sin el usuario daemon con la contraseña xampp.
  - El dominio de una tienda que viene de su base solo se falsea si se parece al nombre de la carpeta (o ya tiene su vhost).
  - Escrituras como root en los proyectos sin seguir enlaces, descargas solo por https, versiones de internet comprobadas, registros solo para tu usuario y la ventana sin fichero `ventana.py` en tu carpeta.
  - **Corregido:** con dos cambios en `httpd.conf` (Listen y el vhost de los dominios desconocidos) se perdía el primero.

## 1.36.0 · 20 oct 2026

- **Diálogos con más aire:** más separación entre textos, campos y opciones, y campos algo más altos. En todos los que abre la ventana.
  - **Elegir la versión de un proyecto:** cada versión es una opción separada, con la fecha de su base de datos debajo.

## 1.35.1 · 20 oct 2026

- **Contraseña de administrador:** ventana nueva con más aire, como la de autorización del sistema: el icono de la aplicación con un candado, el texto centrado, un campo más estrecho y más alto y botones grandes.

## 1.35.0 · 20 oct 2026

- Ventana con los apartados en una barra a la izquierda, como Configuración de Ubuntu.
- **Cada apartado lleva su icono:** los logotipos de PHP, Apache, MariaDB, phpMyAdmin, Perl, XAMPP, WordPress y PrestaShop (de Simple Icons, en el color de cada marca) o un símbolo del tema.
  - También los componentes de cada versión y los proyectos de Cargar proyecto y de Hosts (WordPress o PrestaShop).
- **Servicios:** una tarjeta por servicio con su logotipo, su estado, sus puertos y botones con texto (Reiniciar, Parar, Arrancar). Arriba, cuántos están en marcha y «Solo desde este equipo».

## 1.34.0 · 20 oct 2026

- **Cargar proyecto:** va en un contenedor hundido, con su título dentro, el buscador más grande y más separación con la versión activa.
  - En «Cargado ahora:» solo el proyecto va en verde (el vhost y la flecha, en el color normal).
  - El botón «Abrir web.local» es verde con letras blancas.
- **Botones:** al pasar el ratón sale la mano y cambian un poco de color, con una transición corta.

## 1.33.1 · 20 oct 2026

- **Cargar proyecto:** botón «Abrir Web.local» (borde y letras verdes) a la derecha del proyecto cargado. Abre el vhost en el navegador.

## 1.33.0 · 20 oct 2026

- **Seguridad:** una web que visites ya no puede leer phpMyAdmin ni tus proyectos desde el navegador haciendo que su dominio apunte a 127.0.0.1 (DNS rebinding).
  - Nuevo primer vhost del puerto 80 (`lvm-dominio-desconocido.conf`): los dominios que no tienen vhost reciben un 403. Solo pasan localhost, 127.0.0.1 y [::1].
  - web.local y los dominios falseados funcionan igual que antes.
  - La dirección localhost muestra ahora la carpeta htdocs (antes salía el proyecto de web.local). phpMyAdmin sigue en localhost/phpmyadmin.
  - Se añade al montar cada versión (o con lvm-instalador asegurar) y ya viene en las versiones nuevas.

## 1.32.0 · 20 oct 2026

- **Novedades:** la lista de cambios se ve con formato (Markdown): cada versión con su título y su fecha, viñetas con sangría, el tema de cada cambio en negrita y las rutas y los ficheros en letra de código. lvm-instalador novedades la saca en Markdown.
- Se han puesto las tildes que faltaban en la lista de cambios.

## 1.31.0 · 20 oct 2026

- **Seguridad (segundo repaso):**
  - **Instaladores de XAMPP:** se comprueba su sha256, fijada en el script, además del md5 (con el md5 solo se puede fabricar otro fichero que de lo mismo).
  - **ProFTPD:** solo se instalan parches que publican su .sha256 (si el último no lo tiene, se usa el anterior en vez de fallar).
  - Una rama de PHP más vieja o desconocida ya no recibe sin avisar la pila de la última; una más nueva avisa de que no esta probada.
  - **XAMPP:** los ficheros de lib/php y licenses que podía cambiar cualquier usuario pasan a ser solo de root, y temp (sesiones de PHP) lleva el bit pegajoso. Al activar la versión o al cerrarla a la red; no hace falta reiniciar.
  - **Paquete:** depende también de sudo, openssl y binutils.

## 1.30.6 · 20 oct 2026

- **Buscar actualizaciones:** no encontraba los paquetes 1.30.3 y más nuevos (traen el fichero de polkit del mensaje en español, que no estaba entre los ficheros admitidos) y decía que no había ninguno.

## 1.30.5 · 20 oct 2026

- **Cargar proyecto:** en «Cargado ahora:» el nombre del proyecto va en negrita.

## 1.30.4 · 20 oct 2026

- **Cargar proyecto:** si la base del proyecto esta en varias versiones, la pregunta es «¿Qué versión del proyecto y de PHP quieres cargar?» y cada opción muestra la fecha de su copia de la base.
- «Cargado ahora:» va en gris y sin negrita; el proyecto, en verde.

## 1.30.3 · 20 oct 2026

- **Actualizar:** la contraseña se pide con un mensaje en español («Para instalar la versión nueva de LAMPP Version Manager hace falta tu contraseña») en vez del aviso en inglés de pkexec. Se ve a partir de la siguiente actualización.

## 1.30.2 · 20 oct 2026

- **Versiones, Cargar proyecto:** «Cargado ahora: …» sale en verde y en negrita, para ver de un vistazo que proyecto esta activo.

## 1.30.1 · 20 oct 2026

- **Menú (☰):** Buscar actualizaciones. Busca en Descargas un `lvm-instalador_*.deb` más nuevo y, si lo hay, muestra su fecha y su huella y lo instala (pide la contraseña). Al abrir la ventana ya no se busca solo.

## 1.30.0 · 20 oct 2026

- **Versiones:** bloque nuevo, Cargar proyecto, el primero de la pestaña. Se busca la carpeta del proyecto en `/opt/htdocs` (se ve también el que esta cargado ahora) y se pulsa Cargar: el vhost (web.local) apunta a su carpeta y se monta la versión de PHP donde esta su base de datos. Si la base esta en varias versiones, o en ninguna, se pregunta cual montar (se propone la activa o la de su .php-version).
- El aviso «Se puede entrar desde otros equipos de la red» ya solo sale en la pestaña Servicios.

## 1.29.0 · 20 oct 2026

- **Seguridad:** Apache, MariaDB y el FTP solo aceptan conexiones de este equipo (127.0.0.1 y ::1). XAMPP los deja abiertos a toda la red: cualquier equipo de la oficina podía ver los proyectos y entrar por FTP con el usuario daemon y la contraseña xampp. Se cambia solo lo que falta al montar, arrancar o registrar una versión (copia en `~/lvm-copias`); las pilas nuevas ya se instalan así. Si algo sigue abierto, la pestaña Versiones avisa con un botón «Cerrar a la red». En la terminal: lvm-instalador asegurar.
- Pestaña nueva, Servicios (como el panel de XAMPP): Apache, MariaDB y el FTP de la versión montada, si están en marcha y si se puede entrar desde la red, con botones para arrancar, parar o reiniciar cada uno. El FTP ya no arranca con la versión: se arranca aquí cuando haga falta. En la terminal: lvm-instalador servicio apache|mariadb|ftp arrancar|parar|reiniciar.
- **Subir una base:** el volcado solo puede llevar SQL. Un .sql manipulado ya no puede ejecutar programas en el equipo (\! orden, system) ni leer sus ficheros. La línea del modo sandbox se sigue quitando.
- Los vhosts vuelven a ser del administrador (Apache los lee como root al arrancar). Editar vhosts abre una copia; al pulsar Aplicar se comprueba, se guarda la anterior en `~/lvm-copias`, se escribe con la contraseña y se recarga Apache. Si Apache no la acepta, se deja como estaba. No se admiten ordenes que cambien todo Apache (LoadModule, Include, registros con |orden...).
- `wp-config.php`, `parameters.php` y var/cache: si en un proyecto son enlaces a otra carpeta, no se tocan (con la contraseña se podria escribir o borrar un fichero del sistema). Los nombres de bases, prefijos y carpetas que traen los proyectos se comprueban antes de usarlos en consultas o en los vhosts.
- La contraseña de administrador solo se envia si la pide sudo.
- **Actualizar con un .deb de Descargas:** ya no se ofrece solo al abrir; se busca desde Herramientas y se muestra su fecha y su huella.
- `~/lvm-copias` y `~/.lvm-instalador` (copias de bases y configuraciones de los proyectos) solo son accesibles para tu usuario.

## 1.28.1 · 19 oct 2026

- **Subir una base de datos:** el desplegable Proyecto es tan ancho como el nombre de carpeta más largo, para verlo entero al elegirlo.
- Al elegir la base se propone el proyecto que se llama como ella (wp_mitienda -> dob-wordpress-mitienda, ps_mitienda -> dob-prestashop-mitienda), si no hay uno recordado o que ya la use. Si se cambia a mano, se respeta.

## 1.28.0 · 19 oct 2026

- **Bases de datos:** cada base lleva debajo la fecha y la hora en que se importo y su antiguedad (hace 3 días, hace 4 meses...), en la lista de cada versión y en el buscador. Las que se suben con la aplicación guardan la fecha exacta en `~/.lvm-instalador/importaciones`; para las demas se muestra cuando cambiaron por última vez sus tablas (al importarlas desde phpMyAdmin, por ejemplo), que se ve aunque su MariaDB este parado.

## 1.27.1 · 19 oct 2026

- Tiendas PrestaShop, lo mismo que WordPress en la 1.27.0: al subirle una base con Proyecto elegido, y al cargarla si se ha volcado encima el código de produccion, su app/config/`parameters.php` (o config/`settings.inc.php` en las 1.6) pasa a usar la base de la carpeta y su prefijo; si sus datos no entran en el MariaDB local, root y localhost. El anterior queda en `~/lvm-copias` y se vacia la cache.
- El `wp-config.php` que se crea o se rehace lleva WP_SITEURL y WP_HOME con la dirección local del proyecto: la del vhost de los proyectos tal y como este configurado (https:/`/web.local`, http:/`/localhost`...) o, si el proyecto tiene dominio propio (pestaña Hosts), su dominio. Si ya las tiene, se cambia su valor; si no, se añaden delante de los datos de la base.

## 1.27.0 · 19 oct 2026

- Al subir una base de datos, la ventana de la carga termina con un check verde grande y el título en verde (antes solo ponia Terminado en gris). Igual en el resto de tareas que terminan bien.
- **Subir una base de datos:** nuevo campo Proyecto. Si es la base nueva de un proyecto, se elige su carpeta (se propone sola si se sabe) y la base pasa a ser la suya. Si es un WordPress, su `wp-config.php` se rehace con la plantilla de este equipo (la copia del último `wp-config.php` que funciono en local) cambiando solo la base y, si hace falta, el prefijo de las tablas. Comando: importar-bd ... --proyecto <carpeta>.
- Cargar proyecto en un WordPress con el código de produccion pegado encima: comprueba que `wp-config.php` usa la base asociada a la carpeta y que entra en el MariaDB local. Si no, lo rehace con la plantilla (sin plantilla: el mismo fichero con root y localhost; sin `wp-config.php`: `wp-config-sample.php` con claves nuevas). El anterior queda en `~/lvm-copias`. Comando: wp-config <carpeta> [base].
- La base con la que se carga un proyecto queda asociada a su carpeta.
- La base de cada proyecto ya no se lee de las líneas comentadas de `wp-config.php` (// define( 'DB_NAME', ... )).

## 1.26.0 · 19 oct 2026

- **Tiendas PrestaShop recien clonadas:** su app/config/`parameters.php` no va en el repositorio y quedaba vacio ("install" directory is missing). Cargar proyecto lo crea con la base cargada en local (la del buscador, la recordada o ps_<final de la carpeta>), el prefijo de sus tablas y claves nuevas, y guarda una copia en `~/.lvm-instalador/prestashop` para reponerla igual si se pierde. Si ya tiene base, no se toca. Ahora se reconoce como tienda aunque no tenga configuración, por sus carpetas o por "prestashop" en el nombre.
- La primera vez que se carga una tienda (y al crear su `parameters.php`) se vacia su var/cache, que en las 1.7 da error 500 con la cache de otro equipo. Si no tiene var/cache no pasa nada.
- **Bases de datos:** botón para vaciar la cache de la tienda en las bases ps_ (lista y buscador). Comando: vaciar-cache <carpeta> | --bd <base>.
- Los vhosts que se crean llevan ServerAdmin con tu correo (el de git, user.email; si no hay, usuario@localhost).

## 1.25.1 · 13 oct 2026

- **Hosts, Nuevo proyecto:** los campos de carpeta y base de datos tienen un ancho fijo, como los de Bases de datos (los nombres largos se cortan con ...). La lista de carpetas ya no lleva el dominio al lado: si la carpeta elegida ya tiene uno, se indica debajo de Carpeta. La pestaña ya no se ensancha.

## 1.25.0 · 13 oct 2026

- La pestaña Instalar pasa a Versiones, debajo de Instaladas, con el título Instalar nuevas versiones de PHP. La ventana queda con cuatro pestañas: Versiones, Bases de datos, Hosts y Herramientas.
- Los textos explicativos bajo los títulos de cada bloque se cambian por un símbolo de información junto al título: al pasar el raton por encima se muestra la explicacion.

## 1.24.0 · 13 oct 2026

- **Hosts, Nuevo proyecto con dominio falseado:** la carpeta se elige de una lista con las de `/opt/htdocs` (por ejemplo, la de un git clone; las que ya tienen dominio lo indican) o se crea una nueva con +. La base de datos, igual: las de la versión activa, una nueva con + o ninguna. Si la carpeta trae su configuración (`wp-config.php`, PrestaShop, .env), se propone su base de datos.
- **Herramientas:** Registro de errores muestra solo `/opt/lampp/logs/error_log`. Nuevo Comandos de lvm-instalador: todos los comandos y que hace cada uno (lo mismo que lvm-instalador --ayuda, ahora completo y por temas).

## 1.23.0 · 13 oct 2026

- Solo la versión montada queda en memoria. Al montar otra, al pulsar Parar o al parar desde la terminal, se comprueba que no quede ningún proceso de LAMPP (Apache, MariaDB, ProFTPD, PHP-FPM) y se cierran los que sigan vivos: primero de forma normal (MariaDB guarda todo antes de salir) y, si no hacen caso, a la fuerza. Antes de arrancar se cierran los de otras versiones, que ocuparian los puertos. Venia del lvm original: el lampp de XAMPP solo cierra lo que esta en sus .pid, y todos los procesos se llaman `/opt/lampp/bin/`... sea cual sea la versión, así que los que se quedaban no se distinguian.
- Versiones avisa si hay procesos de otras versiones en memoria, con un botón para cerrarlos. Comandos: lvm-instalador procesos (de que versión es cada uno) y lvm-instalador cerrar-procesos [--todos].

## 1.22.0 · 13 oct 2026

- **Hosts:** Nuevo proyecto con dominio falseado. Con el dominio y la base de datos de produccion: crea la carpeta en `/opt/htdocs`, su vhost http y https con certificado, la base vacia en la versión activa y falsea el dominio, para construirlo en local y subirlo después tal cual. Cargar proyecto vuelve a falsear su dominio. Comando: lvm-instalador nuevo-dominio <dominio> <carpeta> [base].
- **Herramientas:** Registros de errores de la versión montada (error_log y los de los vhosts), con Ver el final (las últimas líneas, sin abrir ficheros enormes) y Abrir. Registros pasa a llamarse Registros de instalaciones. Se quita el panel en la terminal (sigue en el menú).
- Los certificados nuevos son CA:FALSE (Apache ya no avisa con AH01906).

## 1.21.0 · 13 oct 2026

- **Tiendas PrestaShop:** al cargar el proyecto se lee su dominio de la base (tabla shop_url) y se crea lo que falte, como en el manual de XAMPP: su certificado autofirmado en `/etc/ssl` y su vhost http y https en `/opt/config/httpd-vhosts.conf` (con copia en `~/lvm-copias`). Lo que ya existe no se toca. Su dominio se falsea en `/etc/hosts` (127.0.0.1).
- Al cargar cualquier otro proyecto, los dominios de los vhosts dejan de estar falseados y vuelven a llevar a la web real. localhost, web.local y el nombre del equipo no se tocan nunca.
- **Pestaña nueva, Hosts:** el dominio falseado arriba, con un interruptor encendido y el botón Abrir; debajo, los demas dominios de los vhosts con su interruptor para falsearlos o no a mano. Comando: lvm-instalador hosts-falsear <dominio> si|no.
- Apache con tu usuario (User/Group, como en el manual): al cargar un proyecto y al registrar un XAMPP se añade si la versión no lo tiene. Al registrar un XAMPP también se activan los vhosts y `/opt/htdocs` pasa a ser tuyo si no lo era.

## 1.20.0 · 8 oct 2026

- Pestaña nueva, Herramientas (la última), con lo que se usa de vez en cuando: editar vhosts y hosts, registrar un XAMPP de `/opt/lampp`, abrir las carpetas de proyectos, copias y registros, buscar un .deb más nuevo en Descargas, volver a crear el icono del menú, el panel en la terminal, Novedades y Acerca de. El menú sigue teniendo lo de siempre.

## 1.19.0 · 8 oct 2026

- Editar vhosts pasa al menú (debajo de Abrir phpMyAdmin), junto a uno nuevo, Editar hosts: abre una copia de `/etc/hosts` en el editor y, al pulsar Aplicar, la escribe con sudo (el anterior se guarda en `~/lvm-copias`; no deja guardar uno sin la línea de localhost). Comando: lvm-instalador hosts.
- **Versión activa:** arrancar en verde, reiniciar en azul y parar en rojo.
- XAMPP y Pila propia, en gris como el resto del texto de la versión.
- Las bases de datos se descargan en .zip (un .sql dentro); se pueden volver a cargar tal cual. exportar-bd acepta .zip, .sql y .`sql.gz`.
- **Buscador de bases:** un punto verde marca las de la versión activa (ya no pone Activa) y no hay botón Activar. Cargar proyecto lo carga directamente en la versión de esa base; si hay que cambiar de PHP, avisa antes de parar la actual y activar la del proyecto.
- **Instalar:** Estable, Solo seguridad y Sin soporte son texto de color, sin fondo.

## 1.18.0 · 8 oct 2026

- Botón Editar vhosts en la versión activa (pestaña Versiones): abre `/opt/lampp/etc/extra/httpd-vhosts.conf` con el editor de textos. Si el fichero es de root, pide la contraseña una vez y lo hace tuyo para poder guardarlo. Después, Reiniciar aplica los cambios.
- **Comando nuevo:** lvm-instalador vhosts (lo abre en la terminal).

## 1.17.1 · 8 oct 2026

- Acerca de y Novedades vuelven a mostrar su texto: en la 1.17.0 unas comillas sin escapar cortaban el texto y salia un error de la línea 3732 en cada comando.
- El empaquetador del .deb comprueba que el script no da errores al cargarse y que Novedades empieza por la versión del paquete.

## 1.17.0 · 8 oct 2026

- **Actualizar con un .deb:** al abrir la ventana, si en Descargas hay un `lvm-instalador_<version>_all.deb` más nuevo que la versión instalada, ofrece "Actualizar a la <version>". Pide la contraseña en una ventana (pkexec), lo instala y vuelve a abrir la ventana con la versión nueva. El Centro de aplicaciones no ofrece actualizar un .deb suelto.

## 1.16.0 · 8 oct 2026

- Cargar proyecto sin vhost para proyectos (equipos sin web.local): ya no se queda en un aviso. Crea el vhost web.local (http y https, sin cache en el navegador) en `/opt/config/httpd-vhosts.conf`, su certificado autofirmado en `/opt/config/ssl` y su línea en `/etc/hosts`, y lo apunta al proyecto. La ventana lo explica antes de cargar.
- **Dialogos más anchos:** el texto ya no se parte en una columna estrecha.
- **Acerca de:** solo el nombre, la versión, que es (gestor de paquetes Apache, MariaDB, PHP, Perl, phpMyAdmin y ProFTPD al estilo XAMPP de forma independiente), la firma y el año.
- **Novedades:** ventana más grande y solo con la lista de cambios (comando lvm-instalador novedades).

## 1.15.2 · 8 oct 2026

- La ventana se abre con el alto necesario para ver entera la pestaña Bases de datos (sin pasar del alto de la pantalla): lee los datos antes de mostrarse y mide esa pestaña.

## 1.15.1 · 8 oct 2026

- Cargar proyecto recarga Apache (recarga suave, menos de un segundo) si no cambia de versión: cada proceso de PHP recordaba durante 120 s a donde apuntaba web.local y seguia sirviendo el proyecto anterior.

## 1.15.0 · 8 oct 2026

- **Buscador de bases de datos:** botón "Cargar proyecto". Busca la carpeta de `/opt/htdocs` cuya configuración (`wp-config.php`, PrestaShop o .env) usa esa base, activa su versión de PHP y apunta el enlace del vhost (web.local) a esa carpeta. Si hay varias carpetas o ninguna, la eliges tu y se recuerda (`~/.lvm-instalador/proyectos`). Si la base esta en varias versiones o el .php-version del proyecto pide otra, pregunta cual montar. Comando: cargar-proyecto <carpeta> [version].
- **"Activa" ya no parece un botón:** es texto verde junto al nombre de la base de datos y de la versión activa.

## 1.14.0 · 8 oct 2026

- **Bases de datos:** buscador que filtra mientras escribes y dice en que versión (y con que PHP) esta cada base, con un botón para activarla o para elegirla como destino si ya es la activa.
- Al cargar una copia en una base que también existe en otra versión, avisa de donde esta y pregunta si cargarla también en la activa. Al crear una base con un nombre que ya existe en otra versión, lo indica.
- Descargar una copia (.`sql.gz` o .sql) de cualquier base de cualquier versión, desde su lista o desde el buscador. Si esa versión no esta en marcha, se arranca un MariaDB temporal sin red (pide sudo). Comando: exportar-bd <base> <fichero> [version].
- El botón de phpMyAdmin dice "Abrir phpMyAdmin".
- La copia previa al borrar una base ya funciona con el MariaDB 10.4 de XAMPP (no se piden eventos y, si mysql.proc es de un MariaDB antiguo, se copia sin rutinas).

## 1.13.2 · 8 oct 2026

- **Bases de datos:** el selector de la base de destino dice "Elige una base de datos" (como en el Mac) mientras no se ha elegido ninguna.

## 1.13.1 · 8 oct 2026

- **Ventana, "Otro parche concreto...":** los parches ya se pueden elegir (antes la lista no dejaba seleccionar ninguno y "Añadir" seguia desactivado). La fila elegida se marca en verde; con doble clic se añade directamente.

## 1.13.0 · 7 oct 2026

- Si falla una instalación, la ventana muestra el botón "Ver el log del error": un informe con el sistema, el compilador, lo que se instalaba, el paso que ha fallado, sus primeros errores, el final de su log y, si fallo la configuración, lo último de su `config.log`. Se copia entero con "Copiar todo" para buscar la solucion. También se guarda como informe-error.txt junto a los logs de la compilación.

## 1.12.0 · 7 oct 2026

- **Instalar:** cada rama de PHP indica su estado según php.net: Estable (correcciones de errores y de seguridad), Solo seguridad (con la fecha hasta la que tendrá parches) o Sin soporte. En "Otro parche concreto" se ve el estado de la rama y cual es el último parche.
- **Panel:** la misma información en la lista de ramas.

## 1.11.1 · 7 oct 2026

- **Ventana:** la pestaña Bases de datos pasa a ser la segunda e Instalar la tercera (lo que más se usa va primero).

## 1.11.0 · 7 oct 2026

- **Cargar bases de datos:** también desde un .zip (como los que se descargan del servidor), que se descomprime al vuelo, sin ocupar espacio en disco.
- Las copias que empiezan por `/*M`!999999\- enable the sandbox mode */ (mariadb-dump moderno) ya se cargan: esa línea se quita al vuelo, porque el MariaDB de XAMPP no la entiende ("Unknown command").

## 1.10.1 · 7 oct 2026

- **Ventana:** el botón Parar hace lo mismo que "lvm disable": para la versión y quita el enlace `/opt/lampp`, así que php deja de responder en la terminal hasta que actives una versión. Sale también con la versión activa ya parada.

## 1.10.0 · 7 oct 2026

- **Ventana, pestaña Bases de datos:** nuevo apartado "Subir o actualizar una base de datos". Eliges el fichero .sql o .`sql.gz` y la base de la versión activa, y una barra muestra lo cargado, el tiempo y lo que queda, como pv. Opción para vaciar la base antes.
- Crear y borrar bases de datos de la versión activa, con confirmacion. Al borrar una base con tablas avisa de que se elimina todo y es irreversible, y ofrece guardar antes una copia en `~/lvm-copias` (sin copia hay que escribir el nombre de la base).
- Comandos importar-bd <fichero> <base> [--crear] [--vaciar], crear-bd <base> y borrar-bd <base> [--copia].
- Las bases con guion u otros simbolos en el nombre ya se ven bien (antes salian como wp_mi@002dweb).

## 1.9.1 · 7 oct 2026

- El icono creado por la 1.8 o anteriores abria el panel de la terminal en vez de la ventana: ahora abre la ventana.
- Los errores de la ventana abierta desde el menú se guardan en `~/.lvm-instalador/ventana.log`.
- El acceso del menú funciona aunque la carpeta tenga espacios.

## 1.9.0 · 7 oct 2026

- **Ventana gráfica (GTK 3, desde Ubuntu 20.04):** pestañas Versiones, Instalar y Bases de datos, barra de progreso y la contraseña de sudo en una ventana. El acceso del menú abre la ventana; el panel de la terminal sigue con lvm-instalador.
- **Comandos nuevos:** ventana, arrancar, parar, reiniciar y desinstalar <version> --copia.

## 1.8.1 · 7 oct 2026

- Si el icono estaba anclado en el dock con su nombre antiguo, se cambia por el nuevo (el dock seguia abriendo la ruta vieja).

## 1.8.0 · 7 oct 2026

- El comando vuelve a ser lvm-instalador y el archivo `lvm-instalador.sh` (LAMPP Version Manager). El comando antiguo pvm-instalador se quita.

## 1.7.0 · 7 oct 2026

- **Nuevo nombre:** LAMPP Version Manager. El comando sigue siendo pvm-instalador.
- **"Acerca de" explica por que existe:** un XAMPP virtual por cada versión de PHP, ya que XAMPP no saca versiones nuevas.

## 1.6.0 · 6 oct 2026

- "Cambiar la versión activa" es la primera opción del menú.
- **Actualizar:** una versión al día no se puede actualizar; avisa en verde.
- Número de versión debajo de la firma y opción "Acerca de".

## 1.5.0 · 6 oct 2026

- **Nuevo nombre:** PHP Version Manager. Comando pvm-instalador.
- La versión activa aparece en verde en el panel.

## 1.4.0 · 6 oct 2026

- PHP 7.4 a 8.5 y cualquier parche publicado, en su propia carpeta.
- PHP 7.4 y 8.0 con OpenSSL 1.1.1w; 7.4 a 8.1 con ICU 72.1.

## 1.3.0 · 6 oct 2026

- Icono de PHP en el menú de aplicaciones y texto de bienvenida.

## 1.2.0 · 5 oct 2026

- **Equipos ARM:** MariaDB se compila desde el código fuente.
- Aviso si se acepta la lista sin marcar ninguna versión.

## 1.1.0 · 5 oct 2026

- Logo de hexer y firma; el acceso abre la terminal a 100x32.
- Barra de progreso en verde durante las instalaciones.

## 1.0.0 · 5 oct 2026

- Pila propia por versión de PHP, sin depender de un XAMPP.
- Actualizar versiones con los últimos parches de su rama.

## 0.5.0 · 5 oct 2026

- Cada versión de PHP nueva tiene sus propias bases de datos.

## 0.4.0 · 5 oct 2026

- Tablas con las versiones de todos los componentes.
- Pantalla de bases de datos y desinstalador con copia de seguridad.

## 0.3.0 · 4 oct 2026

- **Instalador independiente con panel:** catalogo de XAMPP, PHP nuevos, cambio de versión activa, modo simulación y accesos.

## 0.2.0 · 4 oct 2026

- Asistente por pasos para instalar versiones de PHP.

## 0.1.0 · 4 oct 2026

- **Primera versión:** PHP 8.4 con PHP-FPM sobre una copia de XAMPP 8.2.4.
