# Prueba de la ventana nueva en un Mac (versión 1.57.6)

La 1.39.0 cambia la ventana entera (como la de Linux 1.54) y añade Docker con Docker Desktop. La 1.39.9 añade el correo de pruebas con Mailpit (paso 7). La 1.39.3 instala el gestor en `/Library/Nexum/gestor` (de root, con su propio bash) y pasa las versiones de `/Applications` a `/Library/Nexum`. Se escribió y se probó desde Linux: la parte de bash y Python, con herramientas falsas (`otool`, `install_name_tool`, `docker`) y las pruebas de siempre. **El código Swift no se ha compilado**, porque en Linux no hay SwiftUI, **y el paso a /Library/Nexum no se ha probado en un Mac**: el paso 0 es para eso.

## Paso 0: el gestor de root y el paso a /Library/Nexum (1.39.3)

Esto **sí cambia tus versiones** (las mueve, con sus BBDD). Si algo falla a mitad, lo deja todo como estaba, pero antes:

1. **Apunta cómo está ahora** (para comparar):

   ```bash
   ls -la /Applications | grep XAMPP; readlink /Applications/XAMPP
   nexum estado; nexum list-db
   readlink /opt/homebrew/bin/nexum
   ```

2. **Una instantánea del disco**, por si hubiera que volver atrás del todo: `sudo tmutil localsnapshot` (se recupera desde la recuperación de macOS con Time Machine). Y, si tienes BBDD que no quieras perder, una copia: **Bases de datos → descargar** o `nexum exportar-bd <base> ~/copia.zip`.
3. **Instala la 1.57.6** desde Terminal (no desde la ventana, para ver todo lo que dice). Saca el `.zip` en Descargas y ejecuta:

   ```bash
   bash ~/Downloads/nexum-mac-1.57.6/lvm-instalador.sh instalar-gestor
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
   readlink /opt/homebrew/bin/nexum /opt/homebrew/bin/lvm                # /Library/Nexum/gestor/lvm-instalador.sh
   head -4 ~/lvm-instalador/lvm-instalador.sh                                     # el aviso, no el script
   /usr/libexec/PlistBuddy -c 'Print :LVMScript' ~/Applications/Nexum\ Dev\ Stack.app/Contents/Info.plist
   nexum version                                                         # Nexum Dev Stack 1.57.6
   ```

5. **Comprueba las versiones:**

   ```bash
   ls -la /Applications | grep XAMPP     # XAMPP -> /Library/Nexum/XAMPP-…; XAMPP-X y XAMPP-compartido, enlaces
   ls -la /Library/Nexum                 # las carpetas de verdad, de root; sin .migracion
   grep -rn '/Applications/XAMPP-' /Library/Nexum/XAMPP-*/xamppfiles/etc /Library/Nexum/XAMPP-compartido/httpd-vhosts.conf
                                         # nada (DocumentRoot "/Applications/XAMPP/xamppfiles/htdocs/…" sí puede salir con otra búsqueda: es el enlace de la activa y está bien)
   nexum estado; nexum list-db; nexum procesos
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

   - Cambia de versión (`nexum use 7.4` y vuelve a la tuya) y, en la ventana, **Encendidos** / **Parados** con la contraseña.
   - **Root ya no pasa por /Applications:** `mv /Applications/XAMPP-compartido /Applications/XAMPP-compartido.prueba` (es solo el enlace) y `nexum reiniciar`: tiene que arrancar y servir los proyectos igual. Después, `mv /Applications/XAMPP-compartido.prueba /Applications/XAMPP-compartido`.
   - **Una copia no ejecuta nada como root:** `cp /Library/Nexum/gestor/lvm-instalador.sh /tmp/x.sh && bash /tmp/x.sh version` dice la versión del gestor de root (abre el instalado, no la copia).
   - `nexum migrar` otra vez: no hace nada (ya no queda nada en `/Applications`).
6. **Docker:** en Docker Desktop, **Settings › Resources › File sharing**, añade `/Library/Nexum/XAMPP-compartido/htdocs` y pulsa Apply. Arranca tus proyectos en Docker (apartado Docker, Arrancar): `grep htdocs ~/.lvm-instalador/docker/*/compose.yaml` tiene que enseñar la ruta nueva, y cada proyecto abre por `https://<carpeta>.docker.local` con sus datos. `sudo ls -l /Library/Nexum/XAMPP-compartido/docker-claves` → ficheros de root con `-rw-------`.
7. **Si algo falla:** pásame toda la salida de Terminal y la de `ls -la /Applications /Library/Nexum` y `sudo ls -la /Library/Nexum/.migracion` (si existe: es el diario para deshacer). Si se quedara a medias, `nexum migrar` primero deshace lo que quedó en el diario y vuelve a empezar. Después de pasar las versiones, la 1.39.2 ya no las ve (busca carpetas en `/Applications`): no vuelvas a ella sin avisarme.

## Paso 1: compilar la ventana

Con el paso 0 ya está compilada. Si no se abrió, ejecuta:

```bash
nexum ventana
```

- Si compila, se abre la ventana nueva y la aplicación de `~/Applications` pasa a llamarse «Nexum Dev Stack» (la «Nexum Stack» de antes desaparece).
- Si no compila, dice que la ventana no está disponible. **Pásame el archivo `~/.lvm-instalador/app/compilar.log`.** Hasta que se arregle, el panel de Terminal funciona como siempre.

## Paso 2: mirar sin cambiar nada

Cierra la ventana y ábrela en modo simulación:

```bash
nexum --simular ventana
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
2. `nexum preparar-firma` → «Ya no hace falta gnupg…» (no instala nada). Si ya tenías gnupg de Homebrew, puedes quitarlo con `brew uninstall gnupg` (el gestor no lo usa).
3. **Cerrar la ventana:** desde la 1.40.2 cambia; se prueba en el paso 12. Minimízala (botón amarillo) y pulsa el icono del Dock: vuelve, con sus datos.
4. (Cerrar la ventana con una tarea en marcha: paso 12.)
5. **Barra de arriba:** sin el botón de phpMyAdmin (está en Bases de datos y en el menú Gestor → Abrir phpMyAdmin). El nombre: «Nexum» en negrita y «Dev Stack» normal y en azul; cambia el tema (menú ☰) y comprueba que se lee bien en los dos.
6. **Desplegables plegados:** entra en Bases de datos: todas las versiones plegadas (también la activa). Abre una y después otra: la primera se cierra; pulsa la abierta: se cierra. Ve a otro apartado y vuelve: otra vez todas plegadas. Escribe en el buscador: se despliegan las que tienen algo que coincide. Lo mismo en Docker con los proyectos (plegados al entrar, uno a la vez; con una búsqueda, desplegados).

## Paso 7: correo de pruebas con Mailpit (1.39.9)

Lo que mandan las webs (formularios, pedidos, contraseñas) tiene que llegar a Mailpit y a nadie más. **Prueba con BBDD de prueba o copias**, no con la tienda de producción.

1. **Instalar:** en **Configuración → Correo de pruebas (Mailpit)**, la fila «Mailpit no está instalado» con su logotipo; pulsa **Instalar Mailpit** (pide la contraseña). En el registro: «Descargando mailpit-darwin-arm64.tar.gz…» y «Mailpit 1.32.0 instalado». Comprueba:

   ```bash
   ls -ld /Library/Nexum/mailpit; ls -l /Library/Nexum/mailpit     # root wheel; mailpit rwxr-xr-x, LICENSE y version
   xattr /Library/Nexum/mailpit/mailpit                             # nada (sin cuarentena)
   codesign -v /Library/Nexum/mailpit/mailpit && echo firma-ok
   nexum correo                                            # encendido, WordPress a Mailpit, Mailpit 1.32.0 en marcha
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
8. **Las copias llevan el correo de producción:** en Bases de datos, descarga la BBDD de esa tienda o ese WordPress (o `nexum exportar-bd <base> ~/copia.sql`). El registro dice «Los cambios del correo de pruebas no van en la copia…». En el `.sql`: no hay ``CREATE TABLE `lvm_correo_original` ``, y al final, tras «-- lvm-instalador: el correo de pruebas cambio esto…», los `UPDATE` con lo de antes. Cárgala en otra BBDD vacía de prueba con phpMyAdmin: `PS_MAIL_SERVER` (o los plugins activos de WordPress) son los de producción. La BBDD de trabajo sigue con el correo a Mailpit.
9. **Vaciar** (fila «Bandeja de entrada», pide confirmación): la bandeja queda vacía y el número de **Correo** desaparece.
10. **Apagar** el interruptor «Correo de pruebas» (pide confirmación, en rojo, y la contraseña): el botón **Correo** de arriba desaparece, Mailpit se para y `99-lvm-correo.ini` se queda sin directivas; al cargar el proyecto, su BBDD vuelve a ser la de antes (sin `lvm_correo_original`). Vuelve a encenderlo.
11. **Docker:** sus proyectos aún no mandan a Mailpit (queda para más adelante); su BBDD copiada lleva el correo de producción.

Si algo falla, pasa la salida de la tarea, `nexum correo`, `cat ~/.lvm-instalador/mailpit/mailpit.log ~/.lvm-instalador/mailpit/salida.log` y `ps -axo user,pid,command | grep mailpit`.

## Paso 8: imágenes de producción, borrar un proyecto y Docker (1.39.25)

El código Swift de estas pantallas **no se ha compilado** (en Linux no hay SwiftUI ni AppKit): si `compilar.log` da un error, pásamelo tal cual. La parte de bash se ha probado desde Linux con las pruebas de siempre.

1. **Docker, nombres enteros:** en la pestaña Docker, **Nuevo proyecto**: los desplegables «Carpeta» y «BBDD que se copia» y el campo «Dominio» se ensanchan hasta el nombre más largo (hasta unos 520 puntos). En Proyectos, menú ⋮ de una fila, **Añadir entorno en Docker…**: lo mismo en el diálogo.
2. **Dominios y hosts:** cada `.local` tiene un botón con una foto. Pulsado, propone el dominio real de su carpeta (`tienda.es` para `tienda.local`). **Guardar** pide la contraseña; después, la fila dice «imágenes que faltan de …» y:

   ```bash
   grep -n -A6 'nexum-media' /Library/Nexum/XAMPP-compartido/httpd-vhosts.conf   # en los vhosts de ese .local (80 y 443), en ningún otro
   curl -sk -o /dev/null -w '%{http_code} %{redirect_url}\n' https://tienda.local/img/p/no/existe.jpg   # 302 a https://tienda.es/img/...
   curl -sk -o /dev/null -w '%{http_code}\n' https://tienda.local/img/logo.jpg                          # 200 si está en local
   ```

   Con el campo vacío, **Guardar** quita la regla (el `grep` ya no dice nada). Con un dominio que no es `.local` (`tienda.es`) el botón no sale.
3. **WordPress cargado,** menú ⋮: **Imágenes de producción…** propone el dominio de su BBDD (el `home` de `wp_options`). Al guardar, `web.local` pide a ese dominio lo que falte de `wp-content/uploads` (el `grep` del paso 2 lo enseña en el vhost de `web.local`). Carga otro proyecto: la regla cambia a la suya o desaparece. Las imágenes que faltaban se ven en la web.
4. **Tienda PrestaShop,** menú ⋮: **Descargar de producción las imágenes que faltan…** (su BBDD tiene que estar en la versión activa). La tarea dice cuántas faltan y va contando «Descargadas X de N». Si la web tiene protección contra robots, para enseguida y dice «La web de … no deja descargar»: entonces hay que dar permiso en su servidor al agente `Nexum-Dev-Stack/<versión>` o copiar `img` a mano.
5. **Borrar un proyecto** (con uno **de prueba**: la carpeta no se recupera). Crea uno con **Nuevo proyecto** (carpeta y BBDD vacía) y, si quieres, móntalo en Docker. Menú ⋮ → **Borrar el proyecto…**: hay que escribir su nombre. Después pregunta si se borra también su BBDD («Solo el proyecto» la deja). Comprueba:

   ```bash
   ls /Library/Nexum/XAMPP-compartido/htdocs | grep <carpeta>        # nada
   grep -n '<carpeta>' /Library/Nexum/XAMPP-compartido/httpd-vhosts.conf /etc/hosts   # nada (ni 127.0.0.1 ni ::1)
   ls ~/lvm-copias | tail -2                                         # la copia de la BBDD, si la pediste
   ```

   En Proyectos ya no sale; en Docker, tampoco.

## Paso 9: la ventana, Bases de datos y Mailpit (1.39.26)

1. **La ventana no se rompe:** hazla todo lo estrecha que deje. En Proyectos, el nombre del proyecto cargado sale en una o dos líneas (no letra a letra), «BBDD» en horizontal, las etiquetas de versión («8.5», «Docker 8.4») en una línea y «Cargar» y el menú ⋮ dentro de la tabla. Con un proyecto en Docker el mínimo es algo mayor (su botón «Montar en Docker»). Haz lo mismo en Versiones de PHP, Bases de datos y Docker: nada se monta encima de nada.
2. **Bases de datos:** cuatro tarjetas (sin «Copias de seguridad»); «La última que ha cambiado» y el disco de «Ocupan las BBDD» se leen enteros. Las copias siguen en Configuración, con **Abrir**.
3. **Mailpit:** en Configuración, **Instalar** el correo de pruebas. Tiene que acabar con «Mailpit 1.32.0 instalado», sin «no lleva una firma válida». Comprueba:

   ```bash
   codesign --verify --verbose /Library/Nexum/mailpit/mailpit       # «valid on disk»
   ls -l /Library/Nexum/mailpit/mailpit                              # root wheel, rwxr-xr-x
   ```

   Y sigue con el paso 7 (correo de pruebas) si no lo habías podido probar.

## Paso 10: Docker con su propio Apache, el túnel, los botones y el consumo (1.40.0)

Si la ventana no compila (no se abre tras instalar), manda `~/.lvm-instalador/app/compilar.log` entero: esta versión cambia mucho la ventana y no se ha podido compilar fuera de un Mac.

1. **Consumo, arriba:** en el recuadro de la versión sale «CPU x % · RAM y %». Al pasar el ratón, cada parte (la ventana, XAMPP-X, Docker Desktop, Mailpit y el túnel). Arranca y para XAMPP-X: los números cambian.
2. **Apache de Docker:** en Docker sale la franja «La dirección 127.0.0.2 del Apache de Docker aún no está en este Mac» con **Permitir** (pide la contraseña). Después:

   ```bash
   ifconfig lo0 | grep 127.0.0.2                                   # inet 127.0.0.2 netmask 0xff000000
   ls -l /Library/LaunchDaemons/dev.hexer.nexum-direccion.plist      # root wheel, rw-r--r--
   ```

   Reinicia el Mac y vuelve a mirar `ifconfig lo0`: tiene que seguir.
3. **Proyecto nuevo en Docker:** «Proyecto en Docker…» (ya sin dominio) con un WordPress y su BBDD. Se abre en `https://<carpeta>-php85.docker.local` **con XAMPP-X parado**. Prueba **Confiar** (Configuración, Docker) si el navegador avisa del certificado. phpMyAdmin: `https://pma.docker.local` (la llave copia la contraseña de root).
4. **Varias versiones:** «Versiones de PHP…» → Añadir otra (por ejemplo 8.3): las dos webs a la vez, cada una con su dominio y la misma BBDD. Con una tienda, «Elegir» cambia la versión con el mismo dominio.
5. **Parar:** en la tabla, la fila «MariaDB 11.8 (común)» y «Apache de Docker y phpMyAdmin» tienen su botón. Para la MariaDB con un proyecto en marcha: avisa de cuál se queda sin BBDD. «Parar todos» lo para todo. Parar un proyecto para también lo común que ya nadie usa.
6. **Pasar uno de antes:** en el visor de un proyecto de antes, «Pasar al Apache de Docker»: guarda su BBDD en `~/lvm-copias` y queda con el Apache de Docker.
7. **Túnel:** carga un proyecto y pulsa **Compartir** (logotipo de Cloudflare). La primera vez descarga cloudflared. Sale la dirección `https://….trycloudflare.com` y la contraseña. Ábrela **desde el móvil con datos**: pide la contraseña, se ve la web, `/wp-admin` da «No disponible», `/phpmyadmin` también. El botón pasa a «Compartiendo» (borde naranja). **Cerrar el túnel** y la dirección deja de funcionar.
8. **Botones:** menú ⋮ → «Personalizar los botones…»: quita uno, cambia el orden, prueba «Solo el icono» y «Icono y nombre» con el deslizador (la vista previa cambia). Guarda: el visor del proyecto cargado y el de Docker quedan igual, con Desmontar, ⋮, Versiones de PHP y Parar del mismo tamaño.
9. **Al cargar un proyecto** desde la lista de abajo, la página sube sola hasta el visor.
10. **web.local sin proyecto:** desmonta el proyecto y abre `http://web.local`: el logotipo de Nexum y «Abre Nexum Dev Stack y, en Proyectos, pulsa Cargar».

## Paso 11: el DNS de *.docker.test (1.40.1)

1. Configuración → Docker → **DNS de *.docker.test** → **Activar** (pide la contraseña). Tiene que acabar con «Listo: los proyectos de Docker se abren en https://<proyecto>.docker.test».
2. Comprueba en Terminal:

   ```bash
   cat /etc/resolver/docker.test                          # nameserver 127.0.0.1 / port 5354
   sudo launchctl print system/dev.hexer.nexum-dns | grep state   # state = running
   dscacheutil -q host -a name loquesea.docker.test       # ip_address: 127.0.0.2
   grep docker /etc/hosts                                 # ya sin las líneas .docker.local de Docker
   ```

3. Tus proyectos del Apache de Docker se abren ahora en `https://<proyecto>-php85.docker.test` (y las tiendas en `https://<proyecto>.docker.test`) sin aviso del certificado (si avisa: **Confiar**). phpMyAdmin, en `https://pma.docker.test`.
4. **Añade otra versión de PHP** a un proyecto: ya no pide la contraseña.
5. **`web.local` sigue igual:** carga un proyecto y ábrelo como siempre.
6. Reinicia el Mac y vuelve a abrir un `*.docker.test`: el DNS arranca solo.

## Paso 12: visor, Bases de datos, Configuración, cerrar la ventana y descargar una BBDD (1.40.2)

1. **Visor de arriba:** ya no está el botón «Encendidos» ni la flecha. Pasa el ratón por «● Apache ● MariaDB»: se marca. Púlsalo: se abre el desplegable de servicios, con **Parar y desactivar** (o **Arrancar XAMPP-…**, en azul, si está parada) arriba a la derecha. Púlsalo: el desplegable se cierra y la versión se para (o arranca).
2. **Bases de datos:** «Subir o actualizar una BBDD» está antes de la tabla, en un recuadro hundido, con cuatro columnas: **Fichero SQL** (Elegir… y el nombre), **BBDD de destino** (con + y la papelera), **Proyecto (opcional)** y **Cargar**. Sin fichero, debajo de Elegir… dice «Elige el fichero SQL.». La explicación larga, en el ⓘ del título. Carga una copia como siempre.
3. **Configuración:** a la izquierda, la columna de apartados (Parches nuevos, Vhosts y hosts, Seguridad entre webs, Correo de pruebas, Docker, Túnel de Cloudflare, Visor de los proyectos, GitHub, Registro de errores, Carpetas, XAMPP oficial, Información). Al pulsar uno, a la derecha sale solo lo suyo. Ve a otra pestaña y vuelve: sigue en el mismo apartado. En Repositorios (sin conexión con GitHub), **Ir a Configuración** abre el apartado GitHub.
4. **Cerrar la ventana** con el botón rojo: la aplicación se cierra del todo (sin punto debajo del icono del Dock). Compruébalo:

   ```bash
   pgrep -fl "Nexum Dev Stack" || echo "cerrada"
   ```

5. **Con una tarea en marcha** (por ejemplo, arrancar una versión), cierra la ventana: la aplicación sigue hasta que acaba la tarea y entonces se cierra sola.
6. **Descargar una BBDD de una versión que usa Docker en vivo:** con un proyecto de Docker con la BBDD de XAMPP-X en vivo en marcha (su MariaDB sin red), descarga una BBDD de esa versión desde Bases de datos. Antes fallaba con «Unable to lock ./ibdata1»; ahora dice «Se usa el MariaDB que ya esta en marcha para Docker (sin red)», la descarga termina y el proyecto de Docker sigue funcionando.
7. **Consumo:** deja la ventana abierta un par de minutos en reposo y mira en Monitor de Actividad «Nexum Dev Stack» y los procesos bash: cada 20 s se lanza una sola orden (`gui-vuelta`) en lugar de cuatro.

## Paso 13: terminal e icono en la barra de menús (1.40.3)

1. **Terminal, copiar y pegar:** abre la Terminal de abajo, escribe `echo hola`, selecciona `hola` y pulsa **⌘C**; en TextEdit, ⌘V pega «hola». Copia en TextEdit `ls` y pulsa **⌘V** en la terminal: se escribe `ls`. Botón derecho en la terminal: **Copiar** (solo con algo seleccionado), **Pegar** y **Seleccionar todo**. Copia dos líneas (`echo uno` y `echo dos`) y pégalas: salen «uno» y «dos».
2. **Terminal, proyecto cargado y DNS:** con un proyecto cargado, abre la terminal: empieza en la carpeta del proyecto (`pwd`), no en la de los proyectos. Haz `cd /` y pulsa **Proyecto cargado**: vuelve a ella. Pulsa **Vaciar DNS**: se escribe `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`, pide la contraseña y termina sin error.
3. Al abrir la aplicación, arriba a la derecha (junto al reloj) sale su icono. Púlsalo: **Abrir Nexum Dev Stack**, el estado de la versión activa («● XAMPP-… en marcha» o «○ … parada», en gris), **Parar y desactivar** o **Arrancar XAMPP-…**, **Abrir web.local** (activo solo con la versión en marcha) y **Salir**.
4. **Cierra la ventana** con el botón rojo: la aplicación sigue (el icono de arriba y el punto en el Dock). Desde el icono, **Abrir Nexum Dev Stack**: vuelve la ventana, con sus datos. Ciérrala otra vez y pulsa el icono del Dock: también vuelve.
5. Con la ventana cerrada, **Parar y desactivar** desde el icono: la versión se para. Al minuto, el menú dice «○ … parada». **Arrancar** la vuelve a poner en marcha.
6. **Salir** desde el icono: la aplicación se cierra del todo (`pgrep -fl "Nexum Dev Stack" || echo "cerrada"`).
7. **Configuración → Programa:** apaga «Dejar en la barra de menús al cerrar». El icono desaparece al momento; cerrar la ventana cierra la aplicación (como en el paso 12). Vuelve a abrirla: sigue sin icono. Enciéndelo otra vez: el icono vuelve.

## Paso 14: Nuevo proyecto con un WordPress (1.40.4)

1. **Nuevo proyecto** con un repositorio de WordPress y su volcado SQL. Al terminar, en la consola de la tarea, después de «3/3 BBDD …», sale «WordPress: … la de la carpeta es wp_…» y «wp-config.php de … listo: base wp_…».
2. Comprueba el `wp-config.php` de la carpeta: `DB_NAME` es la BBDD local, el usuario `root` y el servidor `localhost`, y `WP_HOME` es la dirección local. La web abre en local sin el error de conexión a la base de datos.
3. Pega encima el código de producción (con su `wp-config.php`) y vuelve a **cargar** el proyecto: el `wp-config.php` vuelve a la base local (el de producción queda en `~/lvm-copias`).
4. (1.40.5) Borra del `wp-config.php` las líneas `WP_SITEURL` y `WP_HOME` y vuelve a cargar el proyecto: sale «no lleva WP_SITEURL y WP_HOME en https://web.local» y vuelven a estar, con el resto del fichero igual. La web abre en local sin irse a producción.

## Paso 15: Crear y falsear (1.40.6)

1. En **Dominios y hosts**, «Nuevo proyecto con dominio falseado», sin escribir nada: el botón «Crear y falsear» está apagado y a su izquierda pone «Escribe el dominio de producción».
2. Pega `https://www.prueba-falsa.com/tienda/` en Dominio: pone «Elige su carpeta» (el dominio que cuenta es `www.prueba-falsa.com`). Escribe `mal_dominio`: dice que no es un dominio.
3. Escribe `prueba-falsa.com` y elige una carpeta, sin BBDD: el botón se enciende y pone «https://prueba-falsa.com → htdocs/<carpeta>». No hace falta crearlo.

## Paso 16: el host falseado, en el proyecto cargado y en Dominios y hosts (1.40.7)

1. **Proyectos**, con un proyecto cargado que tenga dominio en los vhosts (una tienda PrestaShop): junto al botón ⋮ salen su dominio y un interruptor. Con un proyecto sin dominio, no sale.
2. Apaga el interruptor y pon la contraseña: el dominio deja de estar falseado. Vuelve a encenderlo: al acabar, está encendido. Si cancelas la contraseña, se queda como estaba. En **Dominios y hosts** se ve lo mismo.
3. **Dominios y hosts**: «Host falseado» ocupa un tercio del ancho y «Nuevo proyecto con dominio falseado», a su lado, los otros dos. Debajo, «Dominios de los vhosts» a lo ancho. Agranda y encoge la ventana: se mantiene el reparto y no se corta el formulario.
4. Botón **Ver fichero de hosts**, arriba a la derecha: arriba salen los dominios que se pueden falsear (con su estado y su carpeta) y debajo `/etc/hosts` tal cual. No se puede editar.

5. El interruptor del proyecto cargado pone **Falsear Host** y su dominio debajo; falseado, **Host falseado**. Al dejar el ratón encima dice lo mismo.
6. Deja el ratón encima de los botones del proyecto y de los de Docker: el mensaje es corto y se lee de un vistazo. El botón **Log** lleva un folio verde con «LOG».

## Paso 17: el buscador de Nuevo proyecto (1.40.8)

1. Abre el programa, espera unos segundos y pulsa **Nuevo proyecto**: debajo del buscador pone «N repositorios de GitHub» al momento.
2. Escribe parte de un nombre: salen coincidencias sin esperar. También los repositorios que no llevan uno de los prefijos de Configuración.
3. Elige uno: debajo pone «Se clona por SSH…» y no vuelve a cambiar aunque llegue la lista de GitHub.
4. **Repositorios**: si tu GitHub está conectado con gh, «Leer de nuevo» tarda unos segundos, no minutos.

5. **Repositorios**: cada fila lleva un botón con el icono de copiar. Púlsalo, abre **Nuevo proyecto** y pega en el buscador: el repositorio queda elegido («Se clona por SSH…») y se rellena su carpeta.

## Paso 18: Actualizar proyecto (1.40.9)

**Prueba con un proyecto que no te importe** o con su trabajo ya subido a git.

1. **Proyecto cargado → Actualizar**: sale el diálogo con sus dos zonas. Sin nada elegido, «Actualizar…» está apagado.
2. Arrastra un `.sql` a la primera zona y un `.zip` a la segunda (un `.txt` dice que no vale). También se pueden elegir con sus botones. Prueba a arrastrar una carpeta a la segunda.
3. Elige **Fusionar** y pulsa **Actualizar…**: si es un repositorio, pregunta **¿Hacer git pull antes de copiar?** con la rama y lo que no tiene commit o no se ha subido, con tres opciones.
4. Al acabar, los ficheros del zip están en la carpeta, lo demás sigue, y lo sustituido en `~/lvm-copias/<carpeta>-antes-de-actualizar-<fecha>`. El `wp-config.php` apunta a la base local y la web abre en local.
   Sin desmontar ni volver a cargar nada a mano. Si la configuración no ha quedado en local, la tarea acaba con un aviso que lo dice.
   Prueba también solo con el código: pone «Se sigue usando la BBDD» y la BBDD no se toca. Y solo con la BBDD: la carpeta no se toca y no pregunta por el pull.
5. Repite con **Sobrescribir** y comprueba que `.git` sigue ahí, que lo que no traía el zip ya no está y que está en `~/lvm-copias`.

## Paso 19: botón Log del proyecto cargado (1.40.10)

1. **Proyecto cargado → Log**: se abre `error_log` y arriba pone `/Applications/XAMPP/xamppfiles/logs/error_log`, no `web.local-error_log`.
2. **Herramientas → Registro de errores**: siguen los dos, el de `web.local` y el de Apache.

## Paso 20: iconos y botones Actualizar e Importar (1.40.12)

1. **Proyecto cargado**: «Actualizar» lleva una flecha hacia arriba sobre una bandeja, en azul. Al pasar por encima dice «Actualizar proyecto», también con el estilo de solo icono.
2. Con un WordPress o un PrestaShop cargado sale **Importar**, una foto con una flecha hacia abajo y dibujada con línea fina. Al pasar por encima dice «Importar imágenes de producción». Con un proyecto de otro tipo no sale. Lo mismo en el visor de Docker.
3. Púlsalo: un WordPress abre «Imágenes de producción» y una tienda pregunta si descargar las que faltan.
4. **⋮ → Personalizar los botones**: «Importar» está en la lista con su icono. Ocúltalo y desaparece de los dos visores; vuelve a marcarlo y regresa.

## Paso 21: lista de pasos en las instalaciones (1.40.13)

1. **Proyecto cargado → Actualizar** con un `.sql` y un `.zip`: encima de «Ver registro» sale la lista (git pull si lo eliges, código, BBDD, volver a cargar y comprobar). El paso en curso gira y los acabados llevan su check.
2. Al cargar la BBDD, la barra avanza dentro de su tramo y el último paso acaba con check.
3. Repite con **Instalando cloudflared** o **Instalando Mailpit**, y **Actualizar componentes** si hay parches.
4. Si un paso falla, ese paso sale con una X roja, el registro se abre y los siguientes se quedan sin check.

## Paso 22: bandeja de correo dentro de la ventana (1.40.14)

1. **Configuración → Correo de pruebas**, con la versión activa arrancada: debajo de las tarjetas se ve la bandeja de Mailpit. El botón «Abrir» ya no está.
2. Pulsa el botón **Correo** de arriba: lleva a ese apartado, sin abrir el navegador.
3. Manda un correo de prueba desde una web local: aparece solo. Ábrelo, ve a otro apartado de Configuración y vuelve: sigue abierto.
4. Pulsa un enlace dentro del correo: se abre en el navegador y la bandeja sigue en su sitio.
5. Para la versión activa: sale «Mailpit está parado». Arráncala de nuevo: vuelve la bandeja.

## Paso 23: pestaña Node (1.41.0)

Hace falta un proyecto de Astro, Next o Vite en htdocs.

1. Abre **Node** en la barra lateral: sale el proyecto con su tipo y la versión de Node que pide. Una web de PHP con `package.json` no sale.
2. Parado, la fila lleva VS Code, carpeta y registro (solo con su icono), **Arrancar**, **Compilar** y **Túnel**. Los iconos abren lo suyo.
3. Pulsa **Compilar**: la lista de pasos llega hasta «Arrancar el servidor» y la fila pasa a verde con su dirección, **Abrir web**, reiniciar, **Túnel** y **Parar**.
4. **Túnel** abre el diálogo de compartir. Comprueba desde el móvil, sin Wi-Fi, que la web carga entera. El botón pasa a **Compartiendo** y enseña la dirección y la contraseña.
5. **Parar**: el túnel se cierra también y la dirección deja de responder. `pgrep -fl node` no enseña nada de ese proyecto.
6. **Arrancar** (desarrollo): cambia un fichero y se ve al momento. Pulsa **Túnel**: pregunta si compilarlo, lo compila y abre el diálogo de compartir.
7. Si el proyecto pide una versión de Node que no tienes, se descarga en `~/.lvm-instalador/node`.

## Paso 24: tareas en segundo plano (1.41.0)

1. Lanza algo largo (Actualizar componentes, o instalar una versión) y pulsa **Seguir en segundo plano**: la hoja se va y el programa se puede usar (pestañas, abrir webs, VS Code).
2. A la izquierda del visor sale una flecha verde que baja y late, con «Actualizando…» (o lo que haga) y el porcentaje. Al pasar el ratón dice qué se hace.
3. Púlsala: vuelve la hoja, con la lista de pasos al día. Escóndela otra vez.
4. Con la tarea escondida, intenta otra (por ejemplo, Arrancar en la pestaña Node): dice «Hay una tarea en marcha» y vuelve la hoja.
5. Al acabar bien una que se cierra sola: la flecha se va y sale el aviso de abajo. Si falla, la hoja vuelve sola con su registro.

## Paso 25: Apariencia (1.41.0)

1. **Configuración → Apariencia**: dos interruptores (iconos en color y logotipos), «Botones del proyecto» y uno por apartado del menú lateral (sin Proyectos ni Configuración).
2. **Iconos en color**: cada icono del menú con su color; Bases de datos son discos apilados. Elige otro apartado: el elegido se sigue leyendo.
3. **Logotipos**: Docker y Node con su logotipo y su letra; con los iconos en color, PHP con su óvalo. Prueba el tema claro y el oscuro: el «node» cambia de color de letra.
4. Quita **Node** del menú: desaparece. Ábrelo antes y quítalo: se pasa a Proyectos.
5. Cierra y abre la ventana: se acuerda de todo. En la simulación no se guarda.

## Paso 26: Configuración, avisos de parches y terminal (1.41.1)

1. **Configuración**: los apartados van en una columna pegada al menú lateral, sin hueco; lo de cada apartado, en filas (Docker y Correo de pruebas, en tarjetas).
2. **Correo de pruebas**: el interruptor va al lado del título, con el logotipo de Mailpit delante; ya no hay tarjeta de encender ni se pisan las tarjetas.
3. **Docker**: «Guardar» va debajo de los campos de la dirección y los puertos.
4. Con algún parche pendiente (**Parches nuevos**), arriba sale el aviso «Hay parches nuevos»: «Ahora no» lo quita hasta que salga otro; «Actualizar todo» los pone. Al abrir ya no salta la pregunta.
5. **Terminal**: va pegada a la ventana, de lado a lado. El prompt sale al principio de la línea (sin «%» delante). Escribe, borra con ⌫ y usa ↑: se ve bien. Una descarga con porcentaje se queda en una línea.

## Paso 27: diálogos con los cambios numerados (1.41.3)

1. En **Proyectos**, rellena un dominio nuevo y pulsa **Crear y falsear**: el diálogo dice «Qué se va a realizar» y debajo los cambios numerados (1., 2., 3.…), a la izquierda y separados; «Pide la contraseña de administrador» va al final, en gris. Cancela.
2. Lo mismo al **copiar una BBDD** a otra versión, al **cargar un proyecto** en otra versión de PHP y con **Actualizar todo** en Parches nuevos (cancela en todos).
3. Las líneas largas parten por debajo del texto, no por debajo del número.

## Paso 28: Configuración, Apariencia y Seguridad entre webs (1.57.5)

1. En **Configuración**, pulsa varios apartados: arriba, en grande, sale el nombre del que está abierto (con su icono y su explicación), no «Configuración», y su tarjeta no repite el título.
2. **Correo de pruebas**: el interruptor va al lado del título grande.
3. Ya no hay apartado **Visor de los proyectos**. En **Apariencia** hay tres bloques con su título: «Iconos del menú lateral», «Apartados del menú lateral» y «Visor de los proyectos» (con «Personalizar…»).
4. **Seguridad entre webs**: el interruptor arriba y, debajo, «Qué es» con cuatro puntos (El problema, Lo que hace la barrera, Cuándo apagarla, Dónde se aplica).

## Paso 29: Otro parche concreto (1.57.5)

1. En **Versiones de PHP → Instalar**, debajo de la lista de ramas está **Otro parche concreto**. Elige una rama: salen todos sus parches de php.net, con su fecha y si son de seguridad.
2. El último de la rama dice «márcalo en la lista de arriba»; los ya instalados salen atenuados. Marca uno antiguo (por ejemplo, el penúltimo): arriba sale en «Marcados» (la ✕ lo quita) y el botón dice «Instalar 1 versión».
3. Instálalo (20-40 min): va a /Library/Nexum/XAMPP-X.Y.Z. Al acabar, «Activar XAMPP-X.Y.Z» activa esa carpeta.
4. En la terminal: `nexum instalar --php 8.3.10` instala ese parche; uno que no exista en php.net dice que se omite.

## Qué apuntar

- El paso que falla y lo que sale en Terminal, en «Ver registro» o en `compilar.log`.
- Del paso 0: la salida entera de `instalar-gestor` y, si algo no cuadra, `ls -la /Applications /Library/Nexum`.
- Capturas de los apartados que se vean mal.
- La versión de macOS (menú Apple > Acerca de este Mac) y la de Docker Desktop.
