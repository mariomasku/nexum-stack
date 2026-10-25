# Prueba de la ventana nueva en un Mac (versión 1.39.12)

La 1.39.0 cambia la ventana entera (como la de Linux 1.54) y añade Docker con Docker Desktop. La 1.39.9 añade el correo de pruebas con Mailpit (paso 7). La 1.39.3 instala el gestor en `/Library/Nexum/gestor` (de root, con su propio bash) y pasa las versiones de `/Applications` a `/Library/Nexum`. Se escribió y se probó desde Linux: la parte de bash y Python, con herramientas falsas (`otool`, `install_name_tool`, `docker`) y las pruebas de siempre. **El código Swift no se ha compilado**, porque en Linux no hay SwiftUI, **y el paso a /Library/Nexum no se ha probado en un Mac**: el paso 0 es para eso.

## Paso 0: el gestor de root y el paso a /Library/Nexum (1.39.3)

Esto **sí cambia tus versiones** (las mueve, con sus BBDD). Si algo falla a mitad, lo deja todo como estaba, pero antes:

1. **Apunta cómo está ahora** (para comparar):

   ```bash
   ls -la /Applications | grep XAMPP; readlink /Applications/XAMPP
   lvm-instalador estado; lvm-instalador list-db
   readlink /opt/homebrew/bin/lvm-instalador
   ```

2. **Una instantánea del disco**, por si hubiera que volver atrás del todo: `sudo tmutil localsnapshot` (se recupera desde la recuperación de macOS con Time Machine). Y, si tienes BBDD que no quieras perder, una copia: **Bases de datos → descargar** o `lvm-instalador exportar-bd <base> ~/copia.zip`.
3. **Instala la 1.39.12** desde Terminal (no desde la ventana, para ver todo lo que dice). Saca el `.zip` en Descargas y ejecuta:

   ```bash
   bash ~/Downloads/lvm-instalador-mac-1.39.12/lvm-instalador.sh instalar-gestor
   ```

   Tiene que pedir la contraseña **una vez** y decir, por este orden:
   - «Preparando el bash del gestor (/Library/Nexum/gestor/bash, de root): bash 5.3.20 de ftp.gnu.org» y «Compilando bash 5.3.20 (un minuto)…». Si no compila, **no cambia nada** (sigues con la 1.39.2): pásame lo que sale.
   - «Instalado en /Library/Nexum/gestor/lvm-instalador.sh».
   - «Las versiones pasan de /Applications a /Library/Nexum…» con tus `XAMPP-7.4`, `XAMPP-8.5…` y `XAMPP-compartido`; «Parando lo que está en marcha…» (tarda unos 15 s); una línea `XAMPP-X -> /Library/Nexum/XAMPP-X` por cada una (puede tardar un par de minutos: cambia las rutas y vuelve a firmar los programas) y «Hecho».
   - `~/lvm-instalador/lvm-instalador.sh ahora solo abre /Library/Nexum/gestor/lvm-instalador.sh`.
   - Vuelve a arrancar la versión que estaba en marcha y abre la ventana (compila la ventana nueva: menos de un minuto).
4. **Comprueba el gestor:**

   ```bash
   ls -ld /Library/Nexum /Library/Nexum/gestor; ls -l /Library/Nexum/gestor   # root wheel, rwxr-xr-x
   /Library/Nexum/gestor/bash --version | head -1                                # 5.3.20
   otool -L /Library/Nexum/gestor/bash                                            # solo /usr/lib
   readlink /opt/homebrew/bin/lvm-instalador /opt/homebrew/bin/lvm                # /Library/Nexum/gestor/lvm-instalador.sh
   head -4 ~/lvm-instalador/lvm-instalador.sh                                     # el aviso, no el script
   /usr/libexec/PlistBuddy -c 'Print :LVMScript' ~/Applications/Nexum\ Dev\ Stack.app/Contents/Info.plist
   lvm-instalador version                                                         # Nexum Dev Stack 1.39.12
   ```

5. **Comprueba las versiones:**

   ```bash
   ls -la /Applications | grep XAMPP     # XAMPP -> /Library/Nexum/XAMPP-…; XAMPP-X y XAMPP-compartido, enlaces
   ls -la /Library/Nexum                 # las carpetas de verdad, de root; sin .migracion
   grep -rn '/Applications/XAMPP-' /Library/Nexum/XAMPP-*/xamppfiles/etc /Library/Nexum/XAMPP-compartido/httpd-vhosts.conf
                                         # nada (DocumentRoot "/Applications/XAMPP/xamppfiles/htdocs/…" sí puede salir con otra búsqueda: es el enlace de la activa y está bien)
   lvm-instalador estado; lvm-instalador list-db; lvm-instalador procesos
   ```

   - Los proyectos abren igual (`http://web.local`, los https sin aviso del navegador, las tiendas con dominio falseado) y phpMyAdmin (`http://127.0.0.1/phpmyadmin/`) enseña las mismas BBDD. `/etc/hosts` no cambia.
   - En un `phpinfo()`: «Loaded Configuration File» y «Scan this dir for additional .ini files» en `/Library/Nexum/XAMPP-…/xamppfiles/php/etc`, y `extension_dir` en `/Library/Nexum/…`.
   - **Apache y PHP-FPM, como root, solo cargan cosas de /Library/Nexum o del sistema** (no tiene que salir ninguna línea):

     ```bash
     V=$(readlink /Applications/XAMPP)
     for f in logs/httpd.pid var/run/php-fpm.pid; do
         sudo lsof -p "$(sudo cat "$V/xamppfiles/$f")" | awk '$NF ~ /\.(dylib|so)$/ {print $NF}' | grep -vE '^(/usr/lib/|/System/|/Library/Nexum/)'
     done
     ```

   - Cambia de versión (`lvm-instalador use 7.4` y vuelve a la tuya) y, en la ventana, **Encendidos** / **Parados** con la contraseña.
   - **Root ya no pasa por /Applications:** `mv /Applications/XAMPP-compartido /Applications/XAMPP-compartido.prueba` (es solo el enlace) y `lvm-instalador reiniciar`: tiene que arrancar y servir los proyectos igual. Después, `mv /Applications/XAMPP-compartido.prueba /Applications/XAMPP-compartido`.
   - **Una copia no ejecuta nada como root:** `cp /Library/Nexum/gestor/lvm-instalador.sh /tmp/x.sh && bash /tmp/x.sh version` dice la versión del gestor de root (abre el instalado, no la copia).
   - `lvm-instalador migrar` otra vez: no hace nada (ya no queda nada en `/Applications`).
6. **Docker:** en Docker Desktop, **Settings › Resources › File sharing**, añade `/Library/Nexum/XAMPP-compartido/htdocs` y pulsa Apply. Arranca tus proyectos en Docker (apartado Docker, Arrancar): `grep htdocs ~/.lvm-instalador/docker/*/compose.yaml` tiene que enseñar la ruta nueva, y cada proyecto abre por `https://<carpeta>.docker.local` con sus datos. `sudo ls -l /Library/Nexum/XAMPP-compartido/docker-claves` → ficheros de root con `-rw-------`.
7. **Si algo falla:** pásame toda la salida de Terminal y la de `ls -la /Applications /Library/Nexum` y `sudo ls -la /Library/Nexum/.migracion` (si existe: es el diario para deshacer). Si se quedara a medias, `lvm-instalador migrar` primero deshace lo que quedó en el diario y vuelve a empezar. Después de pasar las versiones, la 1.39.2 ya no las ve (busca carpetas en `/Applications`): no vuelvas a ella sin avisarme.

## Paso 1: compilar la ventana

Con el paso 0 ya está compilada. Si no se abrió, ejecuta:

```bash
lvm-instalador ventana
```

- Si compila, se abre la ventana nueva y la aplicación de `~/Applications` pasa a llamarse «Nexum Dev Stack» (la «Nexum Stack» de antes desaparece).
- Si no compila, dice que la ventana no está disponible. **Pásame el archivo `~/.lvm-instalador/app/compilar.log`.** Hasta que se arregle, el panel de Terminal funciona como siempre.

## Paso 2: mirar sin cambiar nada

Cierra la ventana y ábrela en modo simulación:

```bash
lvm-instalador --simular ventana
```

Comprueba (el pie de la barra lateral dice «SIMULACIÓN»):

1. **Arriba:** el visor con PHP (en una línea, sin partir «XAMPP-8.5»), Apache y MariaDB (punto verde que late si están en marcha) y «Encendidos» o «Parados»; la flecha abre los servicios. El menú ☰ a su derecha (desde la 1.39.8), con iconos; «Tema oscuro» o «Tema claro» cambia el tema y se recuerda al volver a abrir. **Correo** (logotipo de Mailpit, desde la 1.39.9) a la izquierda de Localhost, si el correo de pruebas está encendido. Localhost a la derecha (desde la 1.39.5, sin el botón de phpMyAdmin: está en Bases de datos y en el menú Gestor) y, si hay avisos, el botón con su número. La versión del programa va detrás de «Entornos PHP y Docker».
2. **Proyectos:** el cargado en grande, con su entorno y su BBDD en el recuadro hundido; el botón de vincular se pone azul con el ratón. En la lista, «Cargar» sale solo al pasar el ratón, y el buscador encuentra un proyecto por el nombre de su BBDD.
3. **Versiones de PHP:** la tabla con el soporte y el último parche (tarda un poco: viene de php.net). «Activar» sale al pasar el ratón y «Activa» es del mismo tamaño. Componentes e Instalar versión… se abren en un diálogo que se cierra con Esc.
4. **Bases de datos:** las cuatro tarjetas (la de copias dice cuánto ocupa `~/lvm-copias`), la tabla por versión (desde la 1.39.5, todas plegadas al entrar, también la activa) con la fecha exacta y el punto verde en la BBDD del proyecto cargado.
5. **Docker:** sin Docker Desktop, «Instalar Docker…» explica y abre la página de descarga. Con Docker Desktop abierto, la ballena en color, las tarjetas de CPU, memoria y en marcha, y las pestañas Contenedores, Imágenes y Volúmenes.
6. **Dominios y hosts** y **Configuración**: como Hosts y Herramientas de antes.
7. Pulsa **Activar** en una versión: se abre la ventana de la tarea con «[simulacion]» y se cierra sola.

Apunta lo que se vea mal: textos cortados, tablas que no caben (la ventana mide al menos 1140 de ancho), botones que no responden o colores que no se leen en uno de los dos temas.

## Paso 3: la contraseña de administrador

Sin simulación, pulsa **Encendidos** (para y desactiva la versión) y después **Parados** (la arranca). Tiene que salir la ventana «Contraseña de administrador»; con una incorrecta, «Contraseña incorrecta».

## Paso 4: un proyecto en Docker

1. Instala y abre Docker Desktop. En **Settings › Resources › File sharing**, añade `/Library/Nexum/XAMPP-compartido/htdocs` y pulsa Apply (desde la 1.39.3; la de antes, `/Applications/XAMPP-compartido/htdocs`, ya no hace falta).
2. **Los proyectos que ya tenías en Docker** (de la 1.39.1): en el apartado Docker sale un aviso rojo «PHP-FPM abierto en 127.0.0.1». Pulsa **Cerrarlo** (pide la contraseña): rehace la imagen de PHP (Apache con PHP), cambia su `compose.yaml` y su vhost y guarda lo de antes en `~/.lvm-instalador/docker/<nombre>/antes-esquema-2`. Después, cada proyecto tiene que abrirse igual por `https://<carpeta>.docker.local`, con sus datos.
3. En la ventana, **Docker → Proyecto en Docker…**: elige una carpeta de prueba, PHP 8.2, MariaDB 11.4, la BBDD que se copia (o ninguna) y pulsa **Crear en Docker**. La primera vez prepara la imagen de PHP (unos minutos).
4. Abre `https://<carpeta>.docker.local`: el Apache de la versión activa le pasa la web entera al del contenedor. Comprueba con un `phpinfo()` que la versión es la 8.2, que `$_SERVER['HTTP_X_NEXUM_KEY']` **no** sale y que `expose_php` está en Off.
5. **Sin la clave no responde** (lo que hay que comprobar en Docker Desktop, que no se ha podido probar desde Linux):
   - `curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: <carpeta>.docker.local' http://127.0.0.1:29000/` → **403**.
   - Desde otro contenedor: `docker run --rm curlimages/curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: <carpeta>.docker.local' http://host.docker.internal:29000/` → **403**.
   - `ls -l /Library/Nexum/XAMPP-compartido/docker-claves` (como tú) → «Permission denied»; `sudo ls -l` → ficheros de root con `-rw-------`.
   - `ps -axww | grep -i mariadb_root` no enseña ninguna contraseña mientras se copia una BBDD.
6. **Escritura de www-data:** en un WordPress en Docker, sube una imagen a la biblioteca de medios. Tiene que guardarse en `wp-content/uploads` de la carpeta del Mac (con VirtioFS los ficheros quedan a tu nombre). Si da «no se puede escribir», apúntalo con la versión de Docker Desktop y el tipo de carpetas compartidas (Settings › General › «VirtioFS» o «gRPC FUSE»).
7. Un `.htaccess` con `RewriteRule` (los enlaces permanentes de WordPress) tiene que funcionar, y `https://<carpeta>.docker.local/.env` dar 403.
8. **phpMyAdmin del contenedor** (su botón de la fila): pide usuario y contraseña. La llave de la fila enseña `root` y la contraseña, y **Copiar la contraseña** la deja en el portapapeles.
9. **Actualizar imagen** (las flechas de la fila): descarga otra vez `php:8.2-apache` y rehace el contenedor de PHP.
10. En **Proyectos**, con un proyecto cargado, el botón **Docker** (después de Panel): si no está en Docker, abre «Montar <proyecto> en Docker» con la rama de PHP de la versión activa; si ya está, lo arranca y abre el apartado Docker; con dos versiones (créalas con «Otra versión de PHP…», que propone `<carpeta>-php84.docker.local`), pregunta cuál.
11. Pulsa **PHP 8.2** en su fila y cámbiala a 7.4 (sale «Vulnerable (PHP2Shell)» en rojo en el formulario); parar (rojo), arrancar (verde), registros y, al final, la papelera (quita también su clave de `docker-claves`).
12. **Tabla de contenedores (1.39.4):** en la barra de la izquierda, la ballena de Docker sale de un color, como los demás iconos (azul solo si está elegida). En la tabla, la columna **ID** (12 cifras hexadecimales, como `docker ps`) va después de Nombre y ya no hay columna Estado: el punto verde junto al nombre dice si está en marcha, y junto al del proyecto si lo están todos. Los puertos salen enteros y las acciones, pegadas a la derecha; el primer botón del proyecto arranca (verde) o para (rojo) todos sus contenedores.

Si algo falla, pasa la salida de la tarea («Ver registro») y la de `docker ps -a` y `cat ~/.lvm-instalador/docker/<nombre>/compose.yaml`.

## Paso 5: PHP2Shell, la barrera entre webs y los diálogos (1.39.2)

1. **Versiones de PHP:** XAMPP-7.4 (y las 8.x sin el último parche) salen con «Vulnerable (PHP2Shell)» en rojo; al pasar el ratón, la explicación. Las que tienen el último parche dicen «Actualizado» en verde, sin el punto.
2. **Activar** una vulnerable pide confirmación («Activar XAMPP-7.4 igualmente», en rojo).
3. **XAMPP-7.4 → Poner el parche de seguridad (PHP2Shell)…** (menú ⋯): dice si se conservan sus BBDD (si su MariaDB es la 10.11) y la vuelve a compilar. En el registro tiene que salir «Parche de seguridad contra PHP2Shell (… php-src 712e60f9edfd)» y «Firma de php.tar.xz comprobada». Al terminar: sus BBDD siguen, los proyectos cargan, la columna dice «Actualizado» y «+ parche de seguridad (oct 2026)», y `/Library/Nexum/XAMPP-7.4/xamppfiles/bin/php -v` sigue diciendo 7.4.33 (al volver a compilarla, ya con las rutas de `/Library/Nexum` dentro). Si el parche no encaja o la firma falla, no se instala nada: pasa el «Log del error».
4. **XAMPP-8.5:** al arrancarla (o con Protegerlas) se le pone `php/etc/conf.d/zz-lvm-seguridad.ini` (con `fatal_error_backtraces = 0`), `pm.max_requests = 50` y la barrera. Comprueba con `phpinfo()` `post_max_size` = 64M y `session.upload_progress.enabled` = Off.
5. **Barrera entre webs:** en un proyecto cargado, desde la consola de otra web (por ejemplo `https://example.com`): `fetch('http://web.local/', {method: 'POST', mode: 'no-cors'})` → en el registro de acceso de Apache, un 403. Un enlace normal a `http://web.local/` desde otra web se abre. **Configuración → Seguridad → Barrera entre webs** la apaga (pide confirmación y contraseña) y la vuelve a poner.
6. **Diálogos:** el título y el texto centrados en todos (Borrar una BBDD, Desinstalar, Copiar a otra versión, Replicar, Editar vhosts, Novedades, Acerca de…), y el botón azul (o rojo) dice lo que hace. Si alguno sale con el título a la izquierda o cortado, haz una captura.

## Paso 6: sin gnupg, Homebrew y cerrar la ventana (1.39.5)

1. **Rehacer una versión** (por ejemplo XAMPP-8.5.12, menú ⋯ → actualizar o rehacer): en la consola de la tarea, tras «Instalando las librerias de Homebrew para compilar», o «Ya estan todas instaladas» (y no se llama a Homebrew), o «Se instalan con Homebrew: …» solo con las que falten, y el aviso de que en las versiones de macOS sin paquetes hechos se compilan y puede tardar. Ya no sale `gnupg` ni se compilan python, meson o gnutls por él, ni los avisos repetidos de «A newer Command Line Tools release is available». Después: «Firma de httpd.tar.bz2 comprobada (clave …)», lo mismo para apr, apr-util, php.tar.xz, pma.tar.xz y mariadb.tar.gz.
2. `lvm-instalador preparar-firma` → «Ya no hace falta gnupg…» (no instala nada). Si ya tenías gnupg de Homebrew, puedes quitarlo con `brew uninstall gnupg` (el gestor no lo usa).
3. **Cerrar la ventana** con el botón rojo: la aplicación sigue abierta (su icono en el Dock, con el punto debajo). Pulsa el icono del Dock: vuelve la ventana, con sus datos. Minimízala (botón amarillo) y pulsa el icono: vuelve también. **⌘Q** (o Nexum Dev Stack → Salir) sí la cierra.
4. Con una tarea en marcha (por ejemplo, arrancar una versión), cierra la ventana y vuelve a abrirla desde el Dock: la tarea sigue y termina.
5. **Barra de arriba:** sin el botón de phpMyAdmin (está en Bases de datos y en el menú Gestor → Abrir phpMyAdmin). El nombre: «Nexum» en negrita y «Dev Stack» normal y en azul; cambia el tema (menú ☰) y comprueba que se lee bien en los dos.
6. **Desplegables plegados:** entra en Bases de datos: todas las versiones plegadas (también la activa). Abre una y después otra: la primera se cierra; pulsa la abierta: se cierra. Ve a otro apartado y vuelve: otra vez todas plegadas. Escribe en el buscador: se despliegan las que tienen algo que coincide. Lo mismo en Docker con los proyectos (plegados al entrar, uno a la vez; con una búsqueda, desplegados).

## Paso 7: correo de pruebas con Mailpit (1.39.9)

Lo que mandan las webs (formularios, pedidos, contraseñas) tiene que llegar a Mailpit y a nadie más. **Prueba con BBDD de prueba o copias**, no con la tienda de producción.

1. **Instalar:** en **Configuración → Correo de pruebas (Mailpit)**, la fila «Mailpit no está instalado» con su logotipo; pulsa **Instalar Mailpit** (pide la contraseña). En el registro: «Descargando mailpit-darwin-arm64.tar.gz…» y «Mailpit 1.32.0 instalado». Comprueba:

   ```bash
   ls -ld /Library/Nexum/mailpit; ls -l /Library/Nexum/mailpit     # root wheel; mailpit rwxr-xr-x, LICENSE y version
   xattr /Library/Nexum/mailpit/mailpit                             # nada (sin cuarentena)
   codesign -v /Library/Nexum/mailpit/mailpit && echo firma-ok
   lvm-instalador correo                                            # encendido, WordPress a Mailpit, Mailpit 1.32.0 en marcha
   ```

2. **Con la versión activa en marcha**, Mailpit también (la tarea de instalar termina sola, sin quedarse en el 98 %):

   ```bash
   pgrep -lf '^/Library/Nexum/mailpit/mailpit --smtp'               # uno, con tu usuario (ps -o user= -p <pid>)
   lsof -nP -iTCP -sTCP:LISTEN | grep mailpit                       # solo 127.0.0.1:1025 y 127.0.0.1:8025
   ls -ld ~/.lvm-instalador/mailpit                                 # drwx------
   curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: evil.com' http://127.0.0.1:8025/   # no 200 (Host no permitido)
   ```

   Arriba sale **Correo** con el logotipo en color; pulsándolo se abre `http://127.0.0.1:8025/`. **Parados** (desactiva la versión): Mailpit se para (`pgrep` no enseña nada) y al arrancarla vuelve. Cierra la sesión de Mailpit a mano (`pkill -f '^/Library/Nexum/mailpit/mailpit'`): en menos de 20 s, con la ventana delante, vuelve a estar en marcha.
3. **PHP:** en un `phpinfo()` de la versión activa, `sendmail_path` = `/Library/Nexum/mailpit/mailpit sendmail -S 127.0.0.1:1025` y `auto_prepend_file` = `…/xamppfiles/etc/lvm-correo-wordpress.php` (los dos ficheros de root: `ls -l /Library/Nexum/XAMPP-*/xamppfiles/php/etc/conf.d/99-lvm-correo.ini`). Con `php -r 'mail("cliente@ejemplo.es", "Prueba", "Hola");'` (el de `/Applications/XAMPP/xamppfiles/bin`), el correo sale en la bandeja y el número verde de **Correo** sube en unos segundos (se pregunta solo con la ventana delante).
4. **WordPress:** carga un WordPress con un formulario de contacto (Contact Form 7 o el de su tema) y, si puedes, con **WP Mail SMTP** (configurado con Brevo o SMTP) y el plugin de **Brevo**. Al cargarlo, en el registro: «WordPress (wp_options): desactivados en la copia local: Brevo» y, si WP Mail SMTP mandaba por Brevo, «ahora por PHP, a Mailpit». Manda el formulario: el correo está en Mailpit (y no le llega a nadie). Con **Recuperar la contraseña** en wp-login, lo mismo.
5. **Las tres opciones de WordPress** (Configuración): «Desactivarlos en la copia local» (en wp-admin, WP Mail SMTP sale desactivado; el formulario sigue llegando a Mailpit), «No tocarlos» (sale el aviso en naranja «⚠ No se tocan…»; al volver a cargar el proyecto, los plugins vuelven a estar como en producción: el registro dice «Correo de pruebas deshecho…») y «Llevarlos a Mailpit» otra vez. Cada cambio pide la contraseña (rehace el PHP de todas las versiones).
6. **PrestaShop:** carga una tienda; en el registro, «PrestaShop (ps_configuration): correo por SMTP a Mailpit (127.0.0.1:1025)». En su back office (Parámetros avanzados → Correo electrónico) sale SMTP con 127.0.0.1 y el puerto 1025. Haz un **pedido de prueba** en la tienda: el correo de confirmación al cliente y el aviso a la tienda están en Mailpit.
7. **Al lado de «PROYECTO CARGADO»** sale «su correo va a Mailpit» con el logotipo, en gris; al pasar el ratón, la explicación.
8. **Las copias llevan el correo de producción:** en Bases de datos, descarga la BBDD de esa tienda o ese WordPress (o `lvm-instalador exportar-bd <base> ~/copia.sql`). El registro dice «Los cambios del correo de pruebas no van en la copia…». En el `.sql`: no hay ``CREATE TABLE `lvm_correo_original` ``, y al final, tras «-- lvm-instalador: el correo de pruebas cambio esto…», los `UPDATE` con lo de antes. Cárgala en otra BBDD vacía de prueba con phpMyAdmin: `PS_MAIL_SERVER` (o los plugins activos de WordPress) son los de producción. La BBDD de trabajo sigue con el correo a Mailpit.
9. **Vaciar** (fila «Bandeja de entrada», pide confirmación): la bandeja queda vacía y el número de **Correo** desaparece.
10. **Apagar** el interruptor «Correo de pruebas» (pide confirmación, en rojo, y la contraseña): el botón **Correo** de arriba desaparece, Mailpit se para y `99-lvm-correo.ini` se queda sin directivas; al cargar el proyecto, su BBDD vuelve a ser la de antes (sin `lvm_correo_original`). Vuelve a encenderlo.
11. **Docker:** sus proyectos aún no mandan a Mailpit (queda para más adelante); su BBDD copiada lleva el correo de producción.

Si algo falla, pasa la salida de la tarea, `lvm-instalador correo`, `cat ~/.lvm-instalador/mailpit/mailpit.log ~/.lvm-instalador/mailpit/salida.log` y `ps -axo user,pid,command | grep mailpit`.

## Qué apuntar

- El paso que falla y lo que sale en Terminal, en «Ver registro» o en `compilar.log`.
- Del paso 0: la salida entera de `instalar-gestor` y, si algo no cuadra, `ls -la /Applications /Library/Nexum`.
- Capturas de los apartados que se vean mal.
- La versión de macOS (menú Apple > Acerca de este Mac) y la de Docker Desktop.
