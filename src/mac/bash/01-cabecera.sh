#!/bin/bash

# nexum - Nexum Dev Stack para macOS (Apple Silicon), en un solo archivo.
#
# Instala varias versiones de PHP, desde la 7.4, cada una con su pila propia y sin XAMPP:
# Apache, PHP (PHP-FPM), Perl, ProFTPD y MariaDB compilados, y phpMyAdmin, todo dentro de
# /Library/Nexum/XAMPP-X.Y.Z/xamppfiles (de root; hasta la 1.39.2, en /Applications). Solo una
# version esta activa: /Applications/XAMPP es un enlace a ella, como en el XAMPP de Mac. Cada rama de
# PHP lleva componentes compatibles entre si (STACK_MATRIX) y sus propias bases de datos (vacias al
# instalar). Los proyectos (htdocs) y los virtual hosts se comparten entre versiones en
# /Library/Nexum/XAMPP-compartido. El gestor esta en /Library/Nexum/gestor, tambien de root.
# No instala PHP ni MariaDB en el sistema ni con Homebrew: de Homebrew solo se usan librerias para
# compilar, y se copian dentro de cada version para que un "brew upgrade" no la rompa.
#
# COMANDOS: nexum <comando> [opciones]
#
# Cada comando va en su linea, con lo que hace debajo. <...> es un dato obligatorio y [...]
# uno opcional; a | b son alternativas.
#
#
# === VENTANA Y PANEL =========================================================================
#
#   nexum
#       Sin comando: panel interactivo en la terminal
#
#   nexum ventana
#       Abre la ventana (aplicacion nativa)
#
#   nexum instalador
#       Panel, directo a la lista para instalar
#
#   nexum --simular <comando>
#       Delante de cualquier comando: muestra lo que haria sin cambiar nada (tambien sin
#       comando: el panel en simulacion)
#
#
# === VERSIONES ===============================================================================
#
#   nexum list
#       Versiones instaladas (/Library/Nexum/XAMPP-<version>)
#
#   nexum estado
#       Version activa, si esta en marcha y lo que tiene cada una
#
#   nexum use <version>
#       Monta una version: para la actual, cierra lo que quede en memoria y arranca la nueva
#       (ej.: use 8.4)
#
#   nexum arrancar | parar | reiniciar
#       La version montada. Parar no deja ningun proceso en memoria
#
#   nexum disable
#       Para la version montada y la desmonta (quita /Applications/XAMPP)
#
#   nexum procesos
#       Procesos de XAMPP en memoria y de que version es cada uno
#
#   nexum cerrar-procesos [--todos]
#       Cierra los que no son de la version montada (--todos: todos)
#
#
# === INSTALAR, ACTUALIZAR Y DESINSTALAR ======================================================
#
#   nexum instalar --php 7.4,8.4[,8.3.10] [--si]   (una rama: su ultimo parche; X.Y.Z: ese parche)
#       Instala sin preguntas (--si confirma)
#
#   nexum actualizar <version> [--copia]
#       Vuelve a compilar una version con la ultima pila de su rama (y, en la 7.4, 8.0 y 8.1, con
#       el parche de seguridad contra PHP2Shell; tambien XAMPP-7.4.33, XAMPP-8.0.30 y XAMPP-8.1.34)
#       Si su MariaDB cambia de rama, empieza con BBDD vacias: --copia guarda antes las de ahora
#       en ~/nexum-backups (sin ella, no se podran recuperar)
#
#   nexum github [estado] | cuenta <organizacion> | prefijos "<p1> <p2>"
#   nexum github-conectar [--gh] | github-desconectar
#   nexum repos [--todos] [--cache] | repo-traer <dueño/repo> [--actualizar]
#       Repositorios de GitHub (pestaña Repositorios): los de una organizacion o cuenta (los de sus
#       prefijos, o --todos), leidos con un token (por la entrada; se guarda en el llavero) o con la
#       sesion de gh. repo-traer lo clona por SSH en htdocs o, si ya esta, trae sus cambios (git pull)
#
#   nexum docker-reposo [estado] | horas <0-24> | comprobar
#       Los proyectos de Docker que llevan esas horas sin visitas se paran solos (y lo comun que
#       ya no use nadie). 0: nunca. Por defecto, 3 h. Lo comprueba un temporizador cada 15 minutos
#
#   nexum docker-bd <nombre> lampp <version> | docker
#       Un WordPress de Docker con la BBDD de esa version XAMPP-X en vivo, la misma que web.local (sin
#       copias; su MariaDB se arranca sola en otro puerto si no esta en marcha). docker: vuelve a su
#       copia en la MariaDB comun de Docker. Al crearlo: docker-nuevo ... --bd <base> --desde <v> --en-vivo
#
#   nexum componentes | componentes-actualizar [--copia]
#       Los parches nuevos de todo: cada version de PHP (PHP, Apache, MariaDB, phpMyAdmin...),
#       las imagenes de Docker (MariaDB comunes, phpMyAdmin, PHP), Mailpit y cloudflared; y
#       ponerlo todo al dia (--copia, a cada version que se rehace, como en actualizar)
#
#   nexum descargas [vaciar]
#       La cache de descargas de las pilas propias (/Library/Nexum/descargas): el codigo de cada
#       componente ya comprobado, para no descargarlo otra vez y para instalar aunque su web no
#       responda. Sin nada, lo que hay y cuanto ocupa; vaciar, la borra
#
#   nexum copias [vaciar]
#       Las copias de seguridad de ~/nexum-backups (las que pides con --copia o en las casillas
#       de la ventana): sin nada, cuantos ficheros hay y cuanto ocupan; vaciar, las borra todas
#       (la carpeta se queda)
#
#   nexum copias-ficheros [si|no]
#       Copias de los ficheros que el programa cambia por su cuenta (el de hosts, los vhosts, la
#       configuracion de los proyectos al cargarlos, lo que cambia asegurar) en ~/nexum-backups,
#       antes de cambiarlos. Apagadas si no se encienden. Sin argumento, como estan
#
#   nexum manual [<capitulo>]
#       Abre el manual en el navegador (va dentro de este script; se saca a ~/.lvm-instalador/ayuda).
#       Con un capitulo (proyectos, bbdd, docker, configuracion, limpieza...), en ese. Con --ruta,
#       solo dice que fichero abrir
#
#   nexum limpieza
#       Lo que se puede limpiar, cada cosa con lo que ocupa y cuantos ficheros tiene
#
#   nexum limpiar <clave>...
#       Limpia esas cosas (pide la contraseña solo si alguna es de root). Claves: descargas (la cache
#       de descargas), copias (~/nexum-backups), correo (los correos de Mailpit), registros (los del
#       programa en ~/.lvm-instalador, no sus ajustes), registros-versiones (los de Apache, PHP-FPM,
#       PHP y MariaDB de cada version: se vacian), caches-proyectos (la cache de todos los proyectos),
#       temporales (los del programa con mas de un dia y que nada usa) y sesiones (las de PHP de cada
#       version: se cierran las sesiones abiertas en las webs locales). Sin copias: no se recupera
#
#   nexum pasar-version <origen> <destino>
#       Tras instalar el parche nuevo a su lado: copia a la nueva las BBDD de la anterior, con sus
#       vinculos, y la activa si la anterior era la activa (la anterior no se toca)
#
#   nexum desinstalar <version> [--copia]
#       Borra una version (no la activa); --copia guarda antes sus bases en ~/nexum-backups
#
#
# === XAMPP OFICIAL ===========================================================================
#
#   nexum apartar
#       Aparta un XAMPP oficial de /Applications/XAMPP: copia sus bases (.zip en ~/lvm-
#       copias), sus proyectos y sus vhosts, y lo mueve
#
#   nexum importar-copias <carpeta>
#       Carga en la version activa las bases .zip de una carpeta
#
#   nexum volver-oficial
#       Devuelve el XAMPP oficial apartado a /Applications/XAMPP
#
#
# === BASES DE DATOS ==========================================================================
#
#   (en la version montada y en marcha; si root tiene contraseña: MYSQL_PWD=...)
#
#   nexum list-db
#       Bases de datos de cada version
#
#   nexum crear-bd <base>
#       Crea una base vacia (utf8mb4_general_ci)
#
#   nexum importar-bd <fichero> <base> [--crear] [--copia] [--proyecto <carpeta>]
#       Carga un .sql, .sql.gz o .zip; --crear crea la base si no existe. Si ya existe, antes se
#       borran todas sus tablas (con --copia, antes se guarda una copia en ~/nexum-backups si tenia
#       alguna; sin ella, no se podran recuperar); --proyecto la deja como base de esa carpeta: WordPress, rehace su wp-config.php
#       con la plantilla; PrestaShop, su parameters.php pasa a usarla
#
#   nexum exportar-bd <base> <fichero.zip|.sql|.sql.gz> [version]
#       Descarga una copia de una base (sin version, de la activa)
#
#   nexum copiar-bd <base> <origen> <destino> [--como <nombre>] [--carpeta <carpeta|->] [--sustituir [--copia]]
#       Copia una BBDD a otra version (para probar el proyecto con otro PHP); la de origen no se
#       toca. --como: nombre de la copia en la de destino (sin el, el mismo). --carpeta: carpeta
#       del proyecto a la que queda vinculada en la de destino (- = ninguna). Si la de destino ya
#       tiene una con ese nombre, solo con --sustituir (y con --copia, antes guarda una copia suya
#       en ~/nexum-backups)
#
#   nexum vincular-bd <base> <version> <carpeta|->
#       La carpeta de htdocs del proyecto de esa BBDD en esa version (Cargar proyecto la carga
#       con ella). Con -, la BBDD deja de estar vinculada a ninguna carpeta en esa version
#
#   nexum borrar-bd <base> [--copia]
#       Borra una base; --copia guarda antes una copia en ~/nexum-backups
#
#
# === PROYECTOS Y DOMINIOS ====================================================================
#
#   nexum cargar-proyecto <carpeta> [version] [base]
#       Apunta web.local a htdocs/<carpeta> (y monta antes esa version). Tienda PrestaShop o
#       proyecto nuevo: crea lo que falte de su vhost y su certificado y falsea su dominio en
#       /etc/hosts; los demas dominios dejan de estar falseados. Tienda sin base en
#       app/config/parameters.php (recien clonada): lo crea con la base (la indicada, la
#       recordada o ps_<final de la carpeta>); la primera vez vacia su var/cache. Si su
#       configuracion usa otra base (codigo de produccion volcado encima), vuelve a la de la
#       carpeta
#
#   nexum montar-proyecto <url de git> <carpeta> <version> <base> [volcado]
#       Proyecto nuevo desde GitHub (u otro repositorio): lo clona en htdocs/<carpeta> con tu
#       usuario (solo https o ssh, sin submodulos), lo carga en esa version, crea su base y,
#       si se indica, carga en ella el volcado (.sql, .sql.gz o .zip) con la carga protegida
#
#   nexum desmontar-proyecto
#       web.local deja de apuntar al proyecto cargado y enseña una pagina vacia; los dominios
#       falseados de una tienda PrestaShop dejan de estarlo
#
#   nexum usuario-pruebas <base> [carpeta]
#       Crea o deja al dia el administrador de pruebas del panel (WordPress o PrestaShop):
#       local@local.test con contraseña local. Se hace solo al cargar una BBDD
#
#   nexum wp-config <carpeta> [base]
#       WordPress: comprueba que wp-config.php usa la base de la carpeta (la indicada o la
#       recordada) y entra en el MariaDB local; si no (codigo de produccion pegado encima), lo
#       rehace con la plantilla de este equipo, con WP_SITEURL y WP_HOME en la direccion
#       local. Cargar proyecto lo hace solo
#
#   nexum vaciar-cache <carpeta> | --bd <base>
#       Vacia var/cache de una tienda PrestaShop (por carpeta o base)
#
#   nexum limpiar-proyecto <carpeta> [cache] [registros] [actualizaciones]
#       Vacia las caches, los registros y los restos de las actualizaciones de un WordPress o de una
#       tienda PrestaShop (sin claves, todo). Nada de wp-content/uploads (salvo los registros de
#       WooCommerce) ni de img/. Las carpetas se quedan, vacias. No se puede recuperar
#
#   nexum nuevo-dominio <dominio> <carpeta> [base]
#       Proyecto nuevo con su dominio de produccion falseado: carpeta (la usa si existe),
#       vhost con certificado, base vacia con ese nombre en la version activa (si no existe)
#
#   nexum actualizar-proyecto <carpeta> [--codigo <zip, tar.gz o carpeta>] [--modo fusionar|sobrescribir] [--pull] [--bd <fichero>] [--base <base>] [--copia]
#       El proyecto con lo de produccion: git pull (si se pide), su codigo, su BBDD (con la carga
#       protegida de importar-bd) y lo vuelve a cargar. --copia: lo sustituido o quitado del codigo
#       y la BBDD de antes, en ~/nexum-backups
#   nexum hosts-falsear <dominio> si|no
#       Falsea (127.0.0.1 y ::1) o deja de falsear el dominio de un vhost. Un .local se mantiene
#       siempre en /etc/hosts salvo que se apague aqui (no): se recuerda en
#       ~/.lvm-instalador/locales-apagados y con si se vuelve a mantener
#
#   nexum media-produccion <dominio .local> <dominio de produccion>|quitar
#       Lo que falte en local de wp-content/uploads o img (no van en git) se pide a la web de
#       produccion (redireccion 302). Solo en vhosts .local
#
#   nexum media-proyecto <carpeta> <dominio de produccion>|quitar
#       Lo mismo para un WordPress, en el vhost de los proyectos (web.local) mientras este cargado
#
#   nexum ps-imagenes <carpeta>
#       Descarga de la web real las imagenes de una tienda PrestaShop que faltan en img (productos,
#       categorias y marcas, segun su base), resolviendo el dominio con DNS cifrado (sin /etc/hosts)
#
#   nexum vhosts
#       Edita una copia de XAMPP-compartido/httpd-vhosts.conf y la aplica con sudo: se
#       comprueba antes, se guarda el anterior en ~/nexum-backups (con copias-ficheros si) y
#       se recarga Apache
#
#   nexum hosts
#       Edita /etc/hosts (con sudo -e)
#
#
# === SERVICIOS Y SEGURIDAD ===================================================================
#
#   nexum servicio apache|mariadb|ftp arrancar|parar|reiniciar
#       Un servicio de la version montada. El FTP no arranca con la version: se activa asi (o
#       en la pestaña Servicios) y sigue activo hasta que se pare
#
#   nexum asegurar [version]
#       Deja Apache, MariaDB y el FTP solo para este Mac (no se puede entrar desde la red) y
#       los vhosts del administrador. Se hace solo al montar o arrancar una version
#
#   nexum barrera-web [si|no]
#       Barrera entre webs: otra web no puede mandar formularios ni peticiones a tus proyectos
#       en ninguna version (puesta de serie). Corta la vuelta por POST de una pasarela de pago:
#       apagala mientras la pruebes. Sin si/no, dice como esta
#
#   nexum arreglar-certificados
#       Los vhosts https con certificados en los que confia todo el equipo (en /etc/ssl/certs,
#       de CA o de una CA local sin limite de dominios) pasan a uno propio, y esa CA deja de
#       ser de confianza
#
#   nexum confiar-certificados [dominio|--quitar]
#       Safari y Chrome aceptan sin aviso el certificado propio de cada proyecto https (o solo
#       el de ese dominio): solo ese certificado, no una CA; el Mac pide tu contraseña en cada
#       uno. Sin el aviso, las herramientas que manejan el navegador (Claude in Chrome) pueden
#       abrir los proyectos. Los de una tienda con dominio real, solo mientras este falseada en
#       /etc/hosts: al dejar de falsearla, el navegador deja de aceptarlo (se hace solo al
#       cambiar hosts; pide la contraseña). --quitar: solo deja de aceptar los que ya no deberia
#
#
# === CORREO DE PRUEBAS =======================================================================
#
#   nexum correo [estado] | si [--instalar] | no
#       Correo de pruebas (encendido si no se apaga): lo que mandan las webs locales (formularios,
#       pedidos, contraseñas) no llega a nadie, va a Mailpit (http://127.0.0.1:8025/), que arranca
#       y para con la version activa. mail() de PHP en todas las versiones, PrestaShop por SMTP y
#       WordPress segun su modo. Apagado, el correo sale como sin el gestor. --instalar: y Mailpit
#       si no lo esta
#
#   nexum correo wordpress mailpit|desactivar|nada
#       Plugins de correo de WordPress (WP Mail SMTP, Post SMTP, FluentSMTP, Brevo...) en la copia
#       local: mailpit (por defecto) los de SMTP siguen, con su correo a Mailpit, y los que mandan
#       por una API se desactivan; desactivar, todos fuera; nada, no se tocan (su correo puede
#       llegar de verdad). Los cambios no van en las copias (exportar-bd, copiar-bd, Docker)
#
#   nexum correo instalar | vaciar | bd <base>
#       Instala Mailpit (comprobado con su sha256, de root en /Library/Nexum/mailpit); vacia su
#       bandeja; o aplica (o deshace) el correo de pruebas en una BBDD (se hace solo al cargarla)
#
#
# === DOCKER ==================================================================================
#
#   nexum docker-instalar
#       Docker Desktop: si no esta, abre su pagina de descarga (en el Mac se instala a mano); si
#       esta parado, lo abre y espera a que responda
#
#   nexum docker-nuevo <carpeta> <php> <mariadb> [--bd <base> --desde <version> | --volcado <fichero>]
#   nexum docker-php-anadir | docker-php-quitar | docker-php-elegir <nombre> <version de PHP>
#   nexum docker-pasar <nombre> [--copia]
#   nexum docker-parar-todo
#   nexum docker-web [estado] | puertos <ip> <http> <https> | permitir | arrancar | parar | confiar | dns activar|quitar
#       Proyectos en Docker con el Apache de Docker (desde la 1.40): no necesitan XAMPP-X y un proyecto
#       puede ir en varias versiones de PHP a la vez con la misma BBDD (WordPress:
#       <proyecto>-php83.docker.local; una tienda, <proyecto>.docker.local con la version elegida).
#       Su BBDD va en una MariaDB comun por version y phpMyAdmin en https://pma.docker.local.
#       docker-pasar lleva al Apache de Docker un proyecto de antes (con XAMPP-X delante; --copia: y
#       guarda su BBDD en ~/nexum-backups). docker-web:
#       su direccion y sus puertos (127.0.0.2, 80 y 443) y dar de alta esa direccion en este Mac. dns
#       activar: un DNS para *.docker.test (los dominios de Docker pasan a .docker.test y dejan de ir en
#       /etc/hosts; web.local y lo demas, igual)
#   nexum node-arrancar <carpeta> [desarrollo|compilado]   proyecto de Node (Astro, Next, Vite...) en 127.0.0.1
#   nexum node-parar <carpeta>        lo para, y su tunel si se estaba compartiendo
#   nexum node-registro <carpeta>     lo ultimo que ha dicho su servidor
#   nexum tunel-abrir <direccion local> [carpeta] [--horas 1-12] [--admin bloquear|permitir]
#   nexum tunel-cerrar | tunel | tunel-instalar
#       Tunel de Cloudflare (sin cuenta): una web de este equipo, a la vista de otros con una
#       direccion https://<algo>.trycloudflare.com, con su contraseña (nueva al azar en cada
#       tunel), el admin bloqueado y que se cierra solo (2 h si no se dice). La web no se toca: el
#       dominio local se cambia por el del tunel al pasar
#   nexum docker-crear <carpeta> <php> <mariadb> [--bd <base> --desde <version>] [--dominio <d>] [--nombre <n>]
#   nexum docker-php <nombre> <version de PHP>
#   nexum docker-arrancar | docker-parar | docker-registros | docker-borrar <nombre>
#       Proyectos en Docker Desktop (pestaña Docker), por su dominio <carpeta>.docker.local desde
#       el Apache de la version activa: docker-php cambia su version de PHP. --nombre: la misma
#       carpeta otra vez, con otro nombre (otra version de PHP)
#
#   nexum docker-imagen <nombre>
#       Rehace su imagen de PHP descargando otra vez la oficial (ultimos parches) y su contenedor
#
#   nexum docker-clave <nombre>
#       Usuario y contraseña de su phpMyAdmin (ya no entra solo como root)
#
#   nexum docker-usuario-pruebas <nombre>
#       El administrador de pruebas del Panel (local@local.test) en la BBDD de su contenedor
#
#   nexum docker-migrar <nombre> | --todos
#       Los proyectos de antes de la 1.39.2 (PHP-FPM abierto en 127.0.0.1) pasan a la web del
#       contenedor con clave. Se hace solo al arrancarlos
#
#   nexum docker-contenedor arrancar|parar|reiniciar|registros|borrar <contenedor>
#       Uno solo de los contenedores de un proyecto en Docker
#
#   nexum docker-imagenes borrar <ID|imagen:etiqueta> | descargar <imagen:etiqueta>
#   nexum docker-volumen-borrar <volumen>
#       Las imagenes y los volumenes de Docker Desktop: borrar una que no use ningun contenedor,
#       volver a descargarla de Docker Hub, o borrar un volumen (sus datos se pierden)
#
#
# === INFORMACION =============================================================================
#
#   nexum actualizar-gestor <nexum-mac-X.Y.Z.zip>
#       Instala esa version (la que descarga Buscar actualizaciones de GitHub) en el gestor de root
#       (/Library/Nexum/gestor), si su firma (.zip.sig al lado) es la de quien publica el programa y
#       es mas nueva. Root la vuelve a comprobar en una carpeta suya antes de instalarla
#
#   nexum instalar-gestor
#       Desde una copia del script (la del .dmg, una descargada): la instala en /Library/Nexum/gestor
#       (de root, con su bash) y sigue con migrar; despues abre la ventana
#
#   nexum migrar
#       Las versiones de antes de la 1.39.3 pasan de /Applications a /Library/Nexum (de root), con
#       sus BBDD, proyectos, vhosts y certificados; en /Applications queda un enlace a cada una. Si
#       algo falla, se deja todo como estaba. Los comandos y la aplicacion pasan a usar el gestor de
#       root. Se puede repetir
#
#   nexum version | acerca | novedades
#       Version del programa / que hace / lista de cambios
#
#   nexum --ayuda
#       Esta ayuda
#
# Variables opcionales: PHP_TIMEZONE (por defecto Europe/Madrid), LVM_UI=text (sin ventanas)

