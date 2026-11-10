#!/bin/bash

# lvm-instalador - Nexum Dev Stack: gestor e instalador de versiones LAMPP y PHP para Linux en un solo archivo.
#
# Gestiona varias instalaciones de LAMPP en /opt/lampp-<version>, de las que solo una
# esta activa (/opt/lampp es un enlace a ella). Puede instalar:
#   - Versiones completas de XAMPP (Apache, PHP, MariaDB, ProFTPD, Perl, phpMyAdmin),
#     descargadas de SourceForge, para proyectos antiguos (PHP 7.x y 8.1).
#   - Versiones nuevas de PHP (php.net) con su pila propia, sin XAMPP: Apache, PHP (PHP-FPM),
#     Perl y ProFTPD compilados y MariaDB oficial, todo dentro de /opt/lampp-X.Y. Cada rama de
#     PHP lleva componentes mas modernos y compatibles entre si (STACK_MATRIX), y sus propias
#     bases de datos (vacias al instalar).
# No instala PHP ni MariaDB en el sistema: cada version solo funciona cuando esta activa.
#
# COMANDOS: lvm-instalador <comando> [opciones]
#
# Cada comando va en su linea, con lo que hace debajo. <...> es un dato obligatorio y [...]
# uno opcional; a | b son alternativas.
#
#
# === VENTANA Y PANEL =========================================================================
#
#   lvm-instalador
#       Sin comando: abre la ventana (desde el menu) o el panel en la terminal
#
#   lvm-instalador ventana
#       Ventana grafica (la abre el acceso del menu)
#
#   lvm-instalador instalador
#       Panel de la terminal, directo a la lista para instalar
#
#   lvm-instalador --simular <comando>
#       Delante de cualquier comando: muestra lo que haria sin cambiar nada (tambien sin
#       comando: el panel en simulacion)
#
#
# === VERSIONES DE LAMPP ======================================================================
#
#   lvm-instalador list
#       Versiones instaladas (/opt/lampp-<version>)
#
#   lvm-instalador estado
#       Version activa, si esta en marcha y lo que tiene cada una
#
#   lvm-instalador use <version>
#       Monta una version: para la actual, cierra lo que quede en memoria y arranca la nueva
#       (ej.: use 8.4)
#
#   lvm-instalador arrancar | parar | reiniciar
#       La version montada. Parar no deja ningun proceso en memoria
#
#   lvm-instalador disable
#       Para la version montada y la desmonta (quita /opt/lampp)
#
#   lvm-instalador procesos
#       Procesos de LAMPP en memoria y de que version es cada uno
#
#   lvm-instalador cerrar-procesos [--todos]
#       Cierra los que no son de la version montada (--todos: todos)
#
#
# === INSTALAR, ACTUALIZAR Y DESINSTALAR ======================================================
#
#   lvm-instalador instalar [--xampp 7.4,8.1] [--php 7.4,8.4,8.3.10] [--si]
#       Instala sin preguntas. 8.4 = ultimo parche de la rama en lampp-8.4; 8.3.10 = ese
#       parche en lampp-8.3.10; --si confirma
#
#   lvm-instalador add-php <version>
#       Instala una version de PHP con su pila propia
#
#   lvm-instalador add-xampp <version>
#       Instala un XAMPP oficial (7.1.33, 7.4 u 8.1). Ninguno tiene el arreglo de PHP2Shell
#       ni se puede arreglar: solo para lo que no funcione con una pila propia
#
#   lvm-instalador actualizar <version> [--copia]
#       Vuelve a compilar una version con la ultima pila de su rama (las basadas en XAMPP
#       pasan a pila propia)
#       Si su MariaDB cambia de rama, empieza con BBDD vacias: --copia guarda antes las de ahora
#       en ~/nexum-backups (sin ella, no se podran recuperar)
#
#   lvm-instalador github [estado] | cuenta <organizacion> | prefijos "<p1> <p2>"
#   lvm-instalador github-conectar [--gh] | github-desconectar
#   lvm-instalador repos [--todos] [--cache] | repo-traer <dueño/repo> [--actualizar]
#       Repositorios de GitHub (pestaña Repositorios): los de una organizacion o cuenta (los de sus
#       prefijos, o --todos), leidos con un token (por la entrada; se guarda en el llavero) o con la
#       sesion de gh. repo-traer lo clona por SSH en htdocs o, si ya esta, trae sus cambios (git pull)
#
#   lvm-instalador docker-reposo [estado] | horas <0-24> | comprobar
#       Los proyectos de Docker que llevan esas horas sin visitas se paran solos (y lo comun que
#       ya no use nadie). 0: nunca. Por defecto, 3 h. Lo comprueba un temporizador cada 15 minutos
#
#   lvm-instalador componentes | componentes-actualizar [--copia]
#       Los parches nuevos de todo: cada version de PHP (PHP, Apache, MariaDB, phpMyAdmin...),
#       las imagenes de Docker (MariaDB comunes, phpMyAdmin, PHP), Mailpit y cloudflared; y
#       ponerlo todo al dia (--copia, a cada version que se rehace, como en actualizar)
#
#   lvm-instalador descargas [vaciar]
#       La cache de descargas de las pilas propias (/var/cache/nexum-stack): el codigo de cada
#       componente ya comprobado, para no descargarlo otra vez y para instalar aunque su web no
#       responda. Sin nada, lo que hay y cuanto ocupa; vaciar, la borra
#
#   lvm-instalador copias [vaciar]
#       Las copias de seguridad de ~/nexum-backups (las que pides con --copia o en las casillas
#       de la ventana): sin nada, cuantos ficheros hay y cuanto ocupan; vaciar, las borra todas
#       (la carpeta se queda)
#
#   lvm-instalador copias-ficheros [si|no]
#       Copias de los ficheros que el programa cambia por su cuenta (el de hosts, los vhosts, la
#       configuracion de los proyectos al cargarlos, lo que cambia asegurar) en ~/nexum-backups,
#       antes de cambiarlos. Apagadas si no se encienden. Sin argumento, como estan
#
#   lvm-instalador manual [<capitulo>]
#       Abre el manual en el navegador (va dentro de este script; se saca a ~/.lvm-instalador/ayuda).
#       Con un capitulo (proyectos, bbdd, docker, configuracion, limpieza...), en ese. Con --ruta,
#       solo dice que fichero abrir
#
#   lvm-instalador limpieza
#       Lo que se puede limpiar, cada cosa con lo que ocupa y cuantos ficheros tiene
#
#   lvm-instalador limpiar <clave>...
#       Limpia esas cosas (pide la contraseña solo si alguna es de root). Claves: descargas (la cache
#       de descargas), copias (~/nexum-backups), correo (los correos de Mailpit), registros (los del
#       programa en ~/.lvm-instalador, no sus ajustes), registros-versiones (los de Apache, PHP-FPM,
#       PHP y MariaDB de cada version: se vacian), caches-proyectos (la cache de todos los proyectos),
#       temporales (los del programa con mas de un dia y que nada usa) y sesiones (las de PHP de cada
#       version: se cierran las sesiones abiertas en las webs locales). Sin copias: no se recupera
#
#   lvm-instalador actualizar-a <version> <php>
#       Pasa una version a otro parche de su rama (una lampp-8.3.10, que se queda en su
#       parche, o un XAMPP, que no se puede arreglar): instala PHP <php> al lado, en
#       lampp-<php>, le copia las BBDD con sus vinculos y, si era la activa, la activa. La
#       de antes no se toca: desinstalala cuando compruebes la nueva. 7.4.33, 8.0.30 y
#       8.1.34 se compilan con el parche de seguridad de PHP2Shell
#
#   lvm-instalador desinstalar <version> [--copia]
#       Borra una version (no la activa ni una cuyas bases usen otras); --copia guarda antes
#       sus bases en ~/nexum-backups
#
#   lvm-instalador add <nombre>
#       Registra como version un XAMPP instalado a mano en /opt/lampp (activa los vhosts,
#       Apache con tu usuario y htdocs tuyo)
#
#
# === BASES DE DATOS ==========================================================================
#
#   (en la version montada y en marcha; si root tiene contraseña: MYSQL_PWD=...)
#
#   lvm-instalador list-db
#       Bases de datos de cada version
#
#   lvm-instalador crear-bd <base>
#       Crea una base vacia (utf8mb4_general_ci)
#
#   lvm-instalador importar-bd <fichero> <base> [--crear] [--copia] [--proyecto <carpeta>]
#       Carga un .sql, .sql.gz o .zip; --crear crea la base si no existe. Si ya existe, antes se
#       borran todas sus tablas (con --copia, antes se guarda una copia en ~/nexum-backups si tenia
#       alguna; sin ella, no se podran recuperar); --proyecto la deja como base de esa carpeta: WordPress, rehace su wp-config.php
#       con la plantilla; PrestaShop, su parameters.php pasa a usarla
#
#   lvm-instalador exportar-bd <base> <fichero.zip|.sql|.sql.gz> [version]
#       Descarga una copia de una base (sin version, de la montada)
#
#   lvm-instalador copiar-bd <base> <origen> <destino> [--como <nombre>] [--carpeta <carpeta|->] [--sustituir [--copia]]
#       Copia una BBDD a otra version (para probar el proyecto con otro PHP); la de origen no se
#       toca. --como: nombre de la copia en la de destino (sin el, el mismo). --carpeta: carpeta
#       del proyecto a la que queda vinculada en la de destino (- = ninguna). Si la de destino ya
#       tiene una con ese nombre, solo con --sustituir (y con --copia, antes guarda una copia suya
#       en ~/nexum-backups)
#
#   lvm-instalador docker-nuevo <carpeta> <php> <mariadb> [--bd <base> --desde <version> [--en-vivo] | --volcado <fichero>]
#   lvm-instalador docker-bd <nombre> lampp <version> | docker
#       --en-vivo y docker-bd lampp: un WordPress de Docker con la BBDD de esa version LAMPP en vivo, la
#       misma que web.local (sin copias; su MariaDB se arranca sola, sin red, si no esta en marcha).
#       docker-bd docker: vuelve a su copia en la MariaDB comun de Docker
#   lvm-instalador docker-php-anadir | docker-php-quitar | docker-php-elegir <nombre> <version de PHP>
#   lvm-instalador docker-pasar <nombre> [--copia]
#   lvm-instalador docker-parar-todo
#   lvm-instalador docker-web [estado] | puertos <ip> <http> <https> | permitir | arrancar | parar | confiar | dns activar|quitar
#       Proyectos en Docker con el Apache de Docker (desde la 1.56): no necesitan LAMPP y un proyecto
#       puede ir en varias versiones de PHP a la vez con la misma BBDD (WordPress:
#       <proyecto>-php83.docker.local; una tienda, <proyecto>.docker.local con la version elegida).
#       Su BBDD va en una MariaDB comun por version y phpMyAdmin en https://pma.docker.local.
#       docker-pasar lleva al Apache de Docker un proyecto de antes (con LAMPP delante; --copia: y
#       guarda su BBDD en ~/nexum-backups). docker-web:
#       su direccion y sus puertos (127.0.0.2, 80 y 443) y permitir que Docker sin root use los de
#       menos de 1024. dns activar: un DNS para *.docker.test (los dominios de Docker pasan a .docker.test
#       y dejan de ir en /etc/hosts; web.local y lo demas, igual)
#   lvm-instalador node-arrancar <carpeta> [desarrollo|compilado]   proyecto de Node (Astro, Next, Vite...) en 127.0.0.1
#   lvm-instalador node-parar <carpeta>        lo para, y su tunel si se estaba compartiendo
#   lvm-instalador node-registro <carpeta>     lo ultimo que ha dicho su servidor
#   lvm-instalador tunel-abrir <direccion local> [carpeta] [--horas 1-12] [--admin bloquear|permitir]
#   lvm-instalador tunel-cerrar | tunel | tunel-instalar
#       Tunel de Cloudflare (sin cuenta): una web de este equipo, a la vista de otros con una
#       direccion https://<algo>.trycloudflare.com, con su contraseña (nueva al azar en cada
#       tunel), el admin bloqueado y que se cierra solo (2 h si no se dice). La web no se toca: el
#       dominio local se cambia por el del tunel al pasar
#   lvm-instalador docker-crear <carpeta> <php> <mariadb> [--bd <base> --desde <version>] [--dominio <d>] [--nombre <n>]
#   lvm-instalador docker-php <nombre> <version de PHP>
#   lvm-instalador docker-arrancar | docker-parar | docker-registros | docker-borrar <nombre>
#   lvm-instalador docker-imagen <nombre>
#   lvm-instalador docker-usuario-pruebas <nombre>
#       Proyectos en Docker sin root (pestaña Docker): docker-php cambia su version de PHP;
#       docker-imagen rehace su imagen de PHP con lo ultimo de Docker Hub (parches de seguridad);
#       docker-usuario-pruebas pone el administrador de pruebas en la BBDD de su contenedor
#   lvm-instalador docker-imagenes borrar <ID|imagen:etiqueta> | descargar <imagen:etiqueta>
#   lvm-instalador docker-volumen-borrar <volumen>
#       Las imagenes y los volumenes de tu Docker: borrar una que no use ningun contenedor, volver
#       a descargarla de Docker Hub, o borrar un volumen (sus datos se pierden)
#
#   lvm-instalador vincular-bd <base> <version> <carpeta|->
#       La carpeta de /opt/htdocs del proyecto de esa BBDD en esa version (Cargar proyecto la
#       carga con ella). Con -, la BBDD deja de estar vinculada a ninguna carpeta en esa version
#
#   lvm-instalador borrar-bd <base> [--copia]
#       Borra una base; --copia guarda antes una copia en ~/nexum-backups
#
#
# === PROYECTOS Y DOMINIOS ====================================================================
#
#   lvm-instalador cargar-proyecto <carpeta> [version] [base]
#       Apunta web.local a /opt/htdocs/<carpeta> (y monta antes esa version). Tienda
#       PrestaShop o proyecto nuevo: crea lo que falte de su vhost y su certificado y falsea
#       su dominio en /etc/hosts; los demas dominios dejan de estar falseados. Tienda sin base
#       en app/config/parameters.php (recien clonada): lo crea con la base (la indicada, la
#       recordada o ps_<final de la carpeta>); la primera vez vacia su var/cache. Si su
#       configuracion usa otra base (codigo de produccion volcado encima), vuelve a la de la
#       carpeta
#
#   lvm-instalador montar-proyecto <url de git> <carpeta> <version> <base> [volcado]
#       Proyecto nuevo desde GitHub (u otro repositorio): lo clona en /opt/htdocs/<carpeta>
#       con tu usuario (solo https o ssh, sin submodulos), lo carga en esa version, crea su
#       base y, si se indica, carga en ella el volcado (.sql, .sql.gz o .zip) con la carga
#       protegida
#
#   lvm-instalador desmontar-proyecto
#       web.local deja de apuntar al proyecto cargado y enseña una pagina vacia; los dominios
#       falseados de una tienda PrestaShop dejan de estarlo
#
#   lvm-instalador usuario-pruebas <base> [carpeta]
#       Crea o deja al dia el administrador de pruebas del panel (WordPress o PrestaShop):
#       local@local.test con contraseña local. Se hace solo al cargar una BBDD
#
#   lvm-instalador wp-config <carpeta> [base]
#       WordPress: comprueba que wp-config.php usa la base de la carpeta (la indicada o la
#       recordada) y entra en el MariaDB local; si no (codigo de produccion pegado encima), lo
#       rehace con la plantilla de este equipo, con WP_SITEURL y WP_HOME en la direccion
#       local. Cargar proyecto lo hace solo
#
#   lvm-instalador vaciar-cache <carpeta> | --bd <base>
#       Vacia var/cache de una tienda PrestaShop (por carpeta o base)
#
#   lvm-instalador limpiar-proyecto <carpeta> [cache] [registros] [actualizaciones]
#       Vacia las caches, los registros y los restos de las actualizaciones de un WordPress o de una
#       tienda PrestaShop (sin claves, todo). Nada de wp-content/uploads (salvo los registros de
#       WooCommerce) ni de img/. Las carpetas se quedan, vacias. No se puede recuperar
#
#   lvm-instalador nuevo-dominio <dominio> <carpeta> [base]
#       Proyecto nuevo con su dominio de produccion falseado: carpeta (la usa si existe),
#       vhost con certificado, base vacia con ese nombre en la version montada (si no existe)
#
#   lvm-instalador actualizar-proyecto <carpeta> [--codigo <zip, tar.gz o carpeta>] [--modo fusionar|sobrescribir] [--pull] [--bd <fichero>] [--base <base>] [--copia]
#       El proyecto con lo de produccion: git pull (si se pide), su codigo, su BBDD (con la carga
#       protegida de importar-bd) y lo vuelve a cargar. --copia: lo sustituido o quitado del codigo
#       y la BBDD de antes, en ~/nexum-backups
#   lvm-instalador hosts-falsear <dominio> si|no
#       Falsea (127.0.0.1) o deja de falsear el dominio de un vhost
#
#   lvm-instalador media-produccion <dominio .local> <dominio de produccion>|quitar
#       Lo que falte en local de wp-content/uploads o img (no van en git) se pide a la web de
#       produccion (redireccion 302). Solo en vhosts .local
#
#   lvm-instalador media-proyecto <carpeta> <dominio de produccion>|quitar
#       Lo mismo para un WordPress, en el vhost de los proyectos (web.local) mientras este cargado
#
#   lvm-instalador ps-imagenes <carpeta>
#       Descarga de la web real las imagenes de una tienda PrestaShop que faltan en img (productos,
#       categorias y marcas, segun su base), resolviendo el dominio con DNS cifrado (sin /etc/hosts)
#
#   lvm-instalador vhosts
#       Edita una copia de los vhosts y la aplica con sudo: se comprueba antes, se guarda el
#       anterior en ~/nexum-backups (con copias-ficheros si) y se recarga Apache
#
#   lvm-instalador hosts
#       Edita /etc/hosts (con sudoedit)
#
#
# === SERVICIOS Y SEGURIDAD ===================================================================
#
#   lvm-instalador servicio apache|mariadb|ftp arrancar|parar|reiniciar
#       Un servicio de la version montada. El FTP no arranca con la version: se activa asi (o
#       en la pestaña Servicios) y sigue activo hasta que se pare
#
#   lvm-instalador asegurar [version]
#       Deja Apache, MariaDB y el FTP solo para este equipo (no se puede entrar desde la red)
#       y los vhosts del administrador. Se hace solo al montar o arrancar una version
#
#   lvm-instalador barrera-web [si|no]
#       Barrera entre webs (encendida si no se apaga): otra web abierta en el navegador no
#       puede mandar formularios ni peticiones a tus proyectos. Una pasarela de pago que vuelve
#       a la tienda con un POST no pasa: apagala mientras la pruebas. Sin argumento, como esta
#
#   lvm-instalador correo [estado] | si [--instalar] | no
#       Correo de pruebas (encendido si no se apaga): lo que mandan las webs locales (formularios,
#       pedidos, contraseñas) no llega a nadie, va a Mailpit (http://127.0.0.1:8025/), que arranca
#       y para con la version activa. mail() de PHP en todas las versiones, PrestaShop por SMTP y
#       WordPress segun su modo. Apagado, el correo sale como sin el gestor. --instalar: y Mailpit
#
#   lvm-instalador correo wordpress mailpit|desactivar|nada
#       Plugins de correo de WordPress (WP Mail SMTP, Post SMTP, FluentSMTP, Brevo...) en la copia
#       local: mailpit (por defecto) los de SMTP siguen, con su correo a Mailpit, y los que mandan
#       por una API (Brevo) se desactivan; desactivar, todos fuera; nada, no se tocan (avisa: el
#       correo puede llegar de verdad). Los cambios no van en las copias (exportar-bd, Docker)
#
#   lvm-instalador correo instalar | vaciar | bd <base>
#       Instala Mailpit (comprobado con su sha256, de root en /opt/config/mailpit); vacia su
#       bandeja; o aplica (o deshace) el correo de pruebas en una BBDD (se hace solo al cargarla)
#
#   lvm-instalador arreglar-certificados
#       Los vhosts https con certificados en los que confia todo el equipo (en /etc/ssl/certs,
#       de CA o de una CA local sin limite de dominios) pasan a uno propio, y esa CA deja de
#       ser de confianza
#
#   lvm-instalador confiar-certificados [dominio|--quitar]
#       Chrome, Chromium y Firefox aceptan sin aviso el certificado propio de cada proyecto
#       https (o solo el de ese dominio): solo ese certificado, no una CA. Sin el aviso, las
#       herramientas que manejan el navegador (Claude in Chrome) pueden abrir los proyectos.
#       Los de una tienda con dominio real, solo mientras este falseada en /etc/hosts: al
#       dejar de falsearla, el navegador deja de aceptarlo (se hace solo al cambiar hosts).
#       --quitar: solo deja de aceptar los que ya no deberia
#
#
# === INFORMACION =============================================================================
#
#   lvm-instalador version | acerca | novedades
#       Version del programa / que hace / lista de cambios
#
#   lvm-instalador --ayuda
#       Esta ayuda
#
# Variables opcionales: PHP_TIMEZONE (por defecto Europe/Madrid), LVM_UI=text (panel sin ventanas)

set -o pipefail
# Los rangos de las expresiones ([A-Za-z0-9]) siguen el orden del idioma: con es_ES aceptarian letras
# con tilde, ², ½... en carpetas, bases y dominios. En orden C, solo ASCII. (LC_ALL manda sobre
# LC_COLLATE: si esta puesto, pasa a LANG)
[ -n "${LC_ALL:-}" ] && export LANG=$LC_ALL && unset LC_ALL
export LC_COLLATE=C

SELF=$(readlink -f "$0")
LOG_DIR="$HOME/.lvm-instalador"
# Solo tuya: lleva registros, copias de los vhosts y configuraciones con contraseñas
[ -d "$LOG_DIR" ] && [ ! -L "$LOG_DIR" ] && [ -O "$LOG_DIR" ] && chmod 700 "$LOG_DIR" 2> /dev/null
# Las copias de seguridad (BBDD de clientes, vhosts, /etc/hosts anteriores): solo las que se piden
# (--copia) y, las de los ficheros que cambia el programa, si esta el ajuste COPIES_FILES_FLAG
COPIES_DIR="$HOME/nexum-backups"
COPIES_FILES_FLAG="$LOG_DIR/copias-ficheros"
# (actualizar, rehacer y componentes-actualizar con --copia: las BBDD de una version que empieza vacia)
STACK_DB_COPY=0
# (hasta la 1.57.6 era ~/lvm-copias: copies_migrate la renombra al arrancar, salvo con --simular)
# Igual que la de los registros: solo tuya, aunque la carpeta ya existiera con otros permisos
[ -d "$COPIES_DIR" ] && [ ! -L "$COPIES_DIR" ] && [ -O "$COPIES_DIR" ] && chmod 700 "$COPIES_DIR" 2> /dev/null
LOG="$LOG_DIR/instalacion-$(date +%Y%m%d-%H%M%S).log"
PHP_TIMEZONE=${PHP_TIMEZONE:-Europe/Madrid}
# Va al php.ini de cada pila (y lo lee el maestro de PHP-FPM, que es root): solo un nombre de zona
# horaria, sin saltos de linea que metan otras directivas (extension=...)
if ! [[ "$PHP_TIMEZONE" =~ ^[A-Za-z][A-Za-z0-9_+/-]{0,63}$ ]]; then
    echo "PHP_TIMEZONE no es una zona horaria valida: se usa Europe/Madrid" >&2
    PHP_TIMEZONE=Europe/Madrid
fi
PMA_VERSION="5.2.3"
SPACE_XAMPP_GB=2
SPACE_STACK_GB=5

# Solo librerias para compilar (nunca PHP, Apache ni MariaDB del sistema)
STACK_BUILD_DEPS="build-essential pkg-config libxml2-dev libssl-dev libsqlite3-dev zlib1g-dev libcurl4-openssl-dev libonig-dev libzip-dev libpng-dev libjpeg-dev libfreetype-dev libwebp-dev libicu-dev libsodium-dev libargon2-dev libreadline-dev libpcre2-dev libexpat1-dev libnghttp2-dev libbrotli-dev patchelf patch"
XAMPP_DEPS="net-tools"
# Solo en equipos que no son x86_64 (ARM...): MariaDB no publica binarios y se compila
MARIADB_BUILD_DEPS="cmake bison libncurses-dev liblz4-dev libzstd-dev"

# MariaDB y XAMPP solo publican binarios para x86_64. En el resto (ARM, como una maquina virtual
# en un Mac con Apple Silicon) MariaDB se compila desde el codigo fuente y no se ofrece XAMPP.
function native_binaries() {
    [ "$(uname -m)" == "x86_64" ]
}

# Pila propia de cada rama de PHP: rama PHP|Apache|MariaDB|ProFTPD|Perl
# Cada rama nueva sube un escalon (MariaDB LTS y Perl mas modernos), para que los proyectos
# evolucionen con todo compatible entre si. Apache y ProFTPD solo tienen una rama estable.
# Las ramas sin soporte de php.net (7.4-8.1) son para proyectos antiguos y usan la pila de 8.2.
# Cada version de PHP va en su carpeta con la version completa (/opt/lampp-X.Y.Z; hasta la 1.50, el
# ultimo parche de la rama iba en /opt/lampp-X.Y).
# Los componentes son siempre los ultimos parches de su rama, consultados en las webs oficiales.
STACK_MATRIX=(
    "7.4|2.4|10.11|1.3.9|5.40"
    "8.0|2.4|10.11|1.3.9|5.40"
    "8.1|2.4|10.11|1.3.9|5.40"
    "8.2|2.4|10.11|1.3.9|5.40"
    "8.3|2.4|11.4|1.3.9|5.40"
    "8.4|2.4|11.8|1.3.9|5.42"
    "8.5|2.4|12.3|1.3.9|5.44"
)

# PHP 7.4 y 8.0 no funcionan con OpenSSL 3: llevan OpenSSL 1.1.1w compartido en /opt/lampp-X.Y/openssl
# (compartido y no estatico, para que sus simbolos no se mezclen con los del OpenSSL 3 que usa libcurl).
# PHP 7.4-8.1 no compilan con ICU 75 o posterior (exige C++17): llevan ICU 72.1 estatico.
OPENSSL11_VERSION="1.1.1w"
OPENSSL11_SHA="cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8"
ICU72_SHA="a2d2d38217092a7ed56635e34467f92f976b370e20182ad325edea6681a71d68"

function needs_openssl11() { [[ "$1" == "7.4" || "$1" == "8.0" ]]; }
function needs_icu72() { [[ "$1" == "7.4" || "$1" == "8.0" || "$1" == "8.1" ]]; }

# PHP2Shell (CVE-2026-109618 y CVE-2026-109619, oct 2026): las peticiones con muchas variables
# anidadas o con el progreso de las subidas en la sesion pueden ejecutar codigo en PHP. Primer parche
# de cada rama con soporte que lo arregla (los anteriores son vulnerables)
PHP2SHELL_FIXED="8.2.35 8.3.36 8.4.27 8.5.12"
# Las ramas 7.4, 8.0 y 8.1 ya no tienen versiones nuevas: el equipo de seguridad de PHP publico un
# arreglo minimo (no una version: siguen siendo 7.4.33, 8.0.30 y 8.1.34) en las ramas
# PHP-X.Y-CVE-2026-109618-109619 de php-src, de Arnaud Le Blanc. Las pilas propias de esos parches
# se compilan con el: aqui va solo el diff (xz y base64), que se comprueba con su sha256 antes de
# aplicarlo. version|commit de php-src|sha256 del diff
PHP2SHELL_BACKPORTS=(
    "7.4.33|712e60f9edfd03f0960fc4fc3c2c375f42b90aa2|d059c1b4ea0f9023a1e1c17f6eddee82e3c2e029c60dd0a08fc5466764b5eaa4"
    "8.0.30|82f8f31b16a035c1b67cc253e79f7cc288f4cc20|4cda6e04266d0799c546cd0d79e1161eec82810da62252c164fc19ee00571b54"
    "8.1.34|1d7dec178a094e6e75b229ce22754045f8c6070a|5bd88c386523dde98fefaa7bac97ec80f754b84cc58d6511c01dfde39ce1fbe2"
)
# Las pilas que lo llevan lo dicen en este fichero (lo que sale en la ventana: «+ parche de seguridad»)
PHP2SHELL_MARK=etc/lvm-parche-php2shell
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
PHP2SHELL_DIFF_7_4_33='
/Td6WFoAAATm1rRGAgAhARwAAAAQz1jM4J/dGTZdADIaSQnC/BF9UN4KT0fUaKJ0WK281ySqtdq4gWAU2CmoZ/JhK+0kB3bFIb0G
pf0e1wfdsSqDSg0qaXMVy47K2E9fN+TJBFpmPtkeCTNTLPlrLEBL7eSQi6GsC6kScFdp7GAMIsBKuP3oVLwpo0L0O0o72QHqydzo
/8Q3473RamVoLhZwX1SDIcE8G19RhTmGT9tz8PI+k3NfjSrAQ6XaLD5T60+7beScPLvsrb/WGVvQAvpAGCdmhyLEeRGA+RKInYHT
wTqH1Z8qMFWK8hg+suZAkdvWWrQvHOyGNo/qrFGcdOLSeGr6SzmadpERQ7kHxX9CEXVf3cVP6NBlM5Cbf5PEuWZnYYrXlFG6MRmC
WjTgutJgMAivLgp+tLtIuXp86EkXgH+HHxdjG56VNm0OKAk4uM4OOhy/JWPGBL3iiGpGFela3ONM0JmcirH1e+KPedLaJeNbRHHu
Mf6YBn2I5Gjze9wKuksIOECyz9WYckOGlIXEHmN89SjYWcPzgYyvCllxzMNHFWP48J2waN9u0NEQkbBDbzDxC6kyRYCNQLvwuOAC
PrfLhif1/mb2Rvz1AhcNim9VVgGl0d66GdUOi/8AxDu019wrPzfSE8lUm2LaaJ+apwQ69iY0p4Qi55N2qEnurP61nuRu+Qp6b6dH
oJSLphvq+gl6eAKgElwcugOMrBwFGb7Pmh9SoLeVDExR7p1eyirZfBslwYQH7q5hPrBJBI+m3gtqDvG9tDgWnQgEc41R+e7c1buO
YUY7m/D3124kdHY83PsgMmJ7p3/Bmb1Q7xtC5OKakSbipcVBgOGmRC0Ttj8HRwfnqho2KXsymG+2k6XtMKfUPPfTr63726i/xZ5K
2711VrqGR4xKpiRNKfhbVOyFMN8zg3ZGoYjO54JulIJZFvA9AVgkYUquVQQZsdI1vfBscFFcGTfrn6lx+IGdbvcFWCh7wk+9okFL
eaypa078wJKbS71+OR1edS81IER4H+/zfexv8qzIO8A9HGb76qPH+nsWO674A/nlMlGXJaZZDT49jiWD0bEJtNlEeMiOfm1ZXgwM
aG4d1U5jxaqgOM15Bfy5t/VxLzONvF6qLs7ak8Z9qVb0as2dF+ly40LptM6ZneKIX/Ge+rwRWV4Ktjbo9GyXBAYtMQlDhqxyDbnz
CcxCsUuActhADjlOXJWtU4QOtSu9OU7t9MBhObd4qzShrmyHFghqanZozMwt8+Xhkas63FB1AQkEvuQPuPbFyF6nNRaEOXpmNcfC
2ygP18fgxTLE18zLCNMna642MtNkhSeOunKU5FF5zwoJ82m5rS8UAcSvfaXsEjTPD9KruSYplqqNbKHDKAxYj5oRNBLTX+yvQkcM
2q2Wj6uQM4HE3zJcwXLFRjF+G39s/eaT6TFRTTZuCZWZjIV6lEKdeG02krcf8CbcMC4QGQblSvV66EcMFxFTmgaqXuaIFjv8oyYW
z29krnSzaJbKRRnDUhrcecWokhfewfUYfpFAf7HYmPzkrRlMaVXf1JGjArIXLuArnB+xL28qTuCFoardrGdGbihG9o0m+bmUu+bL
goC67BHxrCBK7O9fWoakiRiJjmhPZHOzOoSc7B46QQe1Q6fMi3L/p6ZOqDFCCzhXoNqI7x12X+3IRcB5SdGIbFH0hqCre91x7LgS
LTTCWZXEXJwNARQOdt/1vSIErqCaMuokM8p0NK4Y6aUyGgM85SEo06TqBwZjL8bw/Hck5M500bc5txz9Wi2A6QFjPpkY0tU/paFN
le8Zy7H1JG7BrzuGhdBcVQodRIJMLHKoRUrrmaV1ZsoK0C6dhu/mHpnnId8mqRuac29dhZTcde6mrjRF5G8d85R7wPi5jplwb92f
oxQ8w00IwbhVSU9LIYyOu+4J1vp3FHpiVNyYYcKmz5stSj4C6zWckZplvCKNTQIAy52OHLpa0LxOvDgNoJOSrGS3UOVkdGe3DWU7
IYKLFEsJlpepbodXdLjPGTWlI4uSVgscIXu817jNUBSoU/b7hEyCMhOTLEp77MQhABz7/nBATF9hcyAQZ8iA47k3YE8M2GN5CP/l
M4beQZ8hwCKTW+55es/nZ+BmRz2W65YSXTWRNagEY/sdG8PITYmHcgblyMfDvP+m+nwEEKVPTzcGgTRR4CLLEppxwn+pGeRlNjKX
/afmGyRLL449BEd6dzROsGeCd0nzugBtIstZT7YS5Zd7F75gmobcGaXqXUj5BguG5/lngppZcN9mQ3g6wgexk8CfdpC/zQurb2Lt
xInRBbPyNcMdwYqkkbpjDmMU9deNKMPROkdXvwClP2HT9XFSHfEP+kZVwAsmHkN6JiveJZQzEDfEhki090nRNOoit26nDONJlieY
913KPb14rwJpeNgiuVY2HIhWLpgQNOoNc9DxR1JUG7IUS/3BlvQ3gd/+iAfXhjvSjUcTp2jW1BoWmBVFXv7SHsi6eX2hTkwDYODu
5hq5XmQOvdprCX+IctFpD6OBl9XD0ZT78oPLH1uTQBzVqf/UGQSMYcxVzYvD8Ry/nTQmIO+3EZ3vApj+plOtmo4YRYkxue56BVAl
bXUgiVL/hKzVtO4oemrml93MhLSksJT9cp8VbU55zhv6yg5qanQoZpZZbgOhPkZrjKD8QigvEMz7GvNWBGnjWgVTQjx9EE3xGgns
9UsOrXBHbYLlvL4HxFY7ppDUFN7peyF+3hq1x4J/jt6Hk3uQGKvn56+CHg1KPcW5nDlN+5gL4bqcQe+EbE6eqxllGWJ4P9LpyOfI
FqjI26/wAOgtHGnfIhpgim8JSmW5aeofc5+yOgPlaTZX4ITqqsEnt4HVZRRjWBsdYxh266QqhtjMOK2uWKxe0wWISb28eAqChf+X
6NIIeWILGDuufP3XE0LK+LeAoiUjAfJ4PTtweI4Y8dOvQptUMOYAQ/p6+vcbzaFFigqMpeSzd29J7Ik7BOgSa7u97lg6/N16ZsUw
8hkBTPcbE0Jr5uIyj+55OGU/KotSWQSiq/dsqGz3nqCMWX86d5a1mtUgW8QEpUMjV29Riv6RO5D4fk2QJtabtb74wtxl9A8JArVG
9eyef91/+MuCfOWlDhJv5y1DSQdNSZ2/fO8rWTbhPPelzyKyUXKPXWFKQCJUa49W4qjWLOWLw5iqc/6gJnLeePGTBJ/Kw1zs2cHV
hEvDAUdbbELAiKyj976XVTicU5WdIDFMS5JJs9M7+DfLAbLbj+95QXJTLBDuRskwt6OM5x6bTb2WE3ZX4a0KCj6ds1auOOKFWBLF
WpA3jV6Pk9zncHBpcE6HQKC4SLXrZDnsY250q3gv6/lypp3qGzMn0v7xq2GzeAaffkW7hYM98dERynEcHNSfCIdRCsnSD41MYg2L
ULSpWrW3wzaTi6f46j0MiZH/KbEYdGPcWZEpi5GtEWIrNzN1pmHKN5OlBwh6bwXg1Xfcx64ICD4WJ39fGpl4WSdVKeEQpwvVIOxz
3fgHYd7HJThginM+d13mctECUyTZZ41RfF7YLhwRfXNPm6w6Hk/svmhuH980g39+v+a2Ow4j/CWzx8rpFvqPqwWBsDvfOG4KwSTa
ty7Zr30SXafJxtSaGf32/KGfHxd1BpJje9zzN8HjqpoKwcCPSv4J2WyJSArn5Bt/NTtDTqpVByYxcFrK7vMSoxURoUInNGifW+G1
OlNQahtXCQb0JSeSHHAu49QEOhJG+Fps8pvaX6k0cuVU5JYZ2KKp7PbeKT0OA53jOcU5h/17EkMJ1HraNucIA2kyRbcTzLblmSNC
a8FFegxOWaaP6hqdpyURy1xsN66DjzsZiKRQIMrobIXwb9e9f8KlXusiSz5x2c02/u5YSoD389ROCIc0bsDZVvNWs5Llc29LdKe/
qK8ih1pNdzLDxX85LrlDWMeTTEMFdxheJ1trLeLDRuoKuobtLKg0W4dNCLqrESLqmzACW2o1uaRKnjCPaG7v61na2Fm9CEFE/DB7
QVD6O0urt2IqWreWXhKMMTrJY8AyzipPkc3otmrLzP9GaoZ1itQn0N6ZAcNx7pcCqU916Z360haXAC++LBRZ+zGA723a/BKP4tfV
l5ehJQjAUcoXLnwQ4tYHt9A841DMVj5tFmaGVaNs6xQL8o9D1+Jm4iiqBMv4U4GiHeBxJc8xNrOtI+zHxD5iGb8MptJlZviU3qoJ
IgGVMf2XFhUENutixPk80jSCNgwv8sLGuqnSJc2JCC7DqIyM/NYupNCGLMowu6eZG6Qimuh6lPXoHwAkn9K2YYFfO12g1PIeh7Sv
Oct3XzXSmdEPvRw4RKoVy0k+VVl3j9Rti21ILgaAc6RvYD8y5KudKUSQPgmIF9lAVLCwDXNGcW42G31PKJS2/W+0qFlBqmSO/1Wp
+Oz4gMvaOq1tgLlDpkwqKoFa1QJQK0/l7xRYvU9wCnu0lt6yxeBE8uoSBb3r+8tCWmhneUOFdrPV5dOaP6KG5GnuWBs4V2WGzDs0
BfRWVE/bb3hMBuoBt0RoETsM8h1P14el17a3YIyozq2swa+aSSONoAWdi65iIJqnm6Q9fgCpGrL6wWUMkXK9a3DtUw411nI5bfey
cUhu6KstZ/RnNeqNPUCrS/J7LLgfZnyhNEeXtg5ZZy8B91wyn0nL9i7Xo+Oy5z1/PwyJkWZfRsehZm7aT1IIBC8lf3jen/FpKqXk
e3D6sKD7fh7AQ0O0UGS66Smxd3wBmJRvPdoEHNm5i4d1EvLhY068aqjv8x4CEC95LSnHqldMitZjvTFutsxCgxi66Ymt26GhskE8
DArHPwPP0RAzXR7bG8/+oMEo1lNW+vWwEzROneMA1vFd8oC971G+Noyvf33DLo8Iun279pViyjsSlLAFFNWWvM7LLEh+rMiuBjPQ
OcDc3zRjQaMIC/oh8XBWYBVPfRNjgFqby9TO6paB3g+fJmxMqg+NuSIU9b3dJBGd112yiGf7+Ejd9qrEfUKsp1DAJ/EwSvOJPhnj
dEDG8DReM2IAmS8v+e9Jaql0cY42edIHiiMtrfFchDLC+YVk8kxzOMMDuXaO/arDj+RtRa9ngwIY07HHuvHihQazfmn3hrjgoq6z
7srXQGNw0FKalhvmZNtZf5816OPcn1AgG99KXOsWsCPP5omAZnkBCaWf89ZRqzM9EA1he1c5Xh7/DBhM/IxSQfoqP/5gUT2ljoma
AQjQ3ZvpXrRPpocQhggb+8OcTYmesaupibGxRxuXIe7LFcN9fbcWKtoPAcVOne3kH8MoyQpiDU0gNjNPkrvMQLMPayHFz5+OwW/Y
lM5KiKYln3TsON4iT2FesgZ7k0AFV1+FO9JAGcwxrarjbnp4mphZ1sEAP3y+kwmfJQ75mlwrh6OhH01kvs20WIUja3ZhR3Tr1K+V
KUve4XpPF633doyG9NxDYkI9c0QDsm8rW+zf5oHF6CowxFQNA7bvNqCsPvW/NEIv2rYaIjBaZtl6SJQvxWaLAwIn47HhQ+N5QNj4
lgpxAqryI2eJVT4YMqjpisNmQfaUoVsq9+PmYV4beFZ+bQ/ea/3bEQNX1bLrHxsyZAmdRq3/mKnUGOFKknAYXWc3vRI8Dr2MUX6I
rFdA3cVEbGx6TEbX5YFpjhfAQggs9f8ChO0Y/PcX4yvE7+f1bkoUv2YQlksLnmCSjv/eVLGUh9LcovFVSoZaSpDzqjV49PjeHD1Z
4K4kXSRPz8X+7yB0XN2A2DRIJSH0u2u4O2Q40YO+GAMzQIFXBW04+LGjiFOz0DwdqkxRGmBF4MYYsmYuFDrNtn6HPXPIFLleNxYk
F6dniz0F+JA1xU04m4LFyhGxYVVyMTT62ALk/MBcZ+a+1IT5QkY+nogAkRFEfS8uOxMwH6SD0Ac9E2dKf249YieXi3ANImpOKUnC
0A78+2kcV6o8pYKH+xePo+ATEK7J6BtVvTmZcL1xxJ4apTF8c0PRqvF+PKQ8PFQPWI6wIGqSpR4LyiRwAdmhzCNhwCahQEx6nu3A
SKP+Fa2vg/H6VQHFU2o8zvvCZPVUEAfuOElvNNXZYZ2A/ni98UGpzEcuYF7MD7Nx1XKdcDbb89HOrWyhAx58XlrXP6Lrg5IYRQN3
bbQu5rmPsBbtf+1w6yGzjYpUbUmqZsX/u1CB60pMixx/jAm5Ov0AmSJTEI/XY8z2y+E7Q4VHNTI5nSBGuX56uedIT9YAJxWyUjvd
JvgGoKT+pc0EJwfH25m3KcpQ+lnGutFc3dBp3AH+IDTlwx4N1Rha1y/1TTOsnCOZgB4Qmhr2AJvAaakWpEe4C5w4eZ1mzEd4bQTh
VfTRvCjH2XU4Ye3yg3JKfSxIeseYg59+miC8vh3BXvcAqiqvYrbJ4fdlCgcinTlzV+wvzgbeyEO1O2mdUQVzQrBQ5wX8npMimEe7
6q1WOjsPZIJTQwqSl/ZCVM09SDIa6r/6FTnAy5+V6o3C3qLDjXMfxSHxzPv7OoAaX2ekPfu8r20WziG3aZsnzXZfEku6QBMuVjJ6
elBOOPkEwSM9ZUiCS52X6p8wIcyJpcykDzd8iWiJlCPms7dHcjfZrNlsW0r9fiyEdK3axMSWTJcwWC5fMaf7Gl5SnnH0xENdKFU6
FHfAXBU5JdoPZS6FGM4TOXhWVKgXUCO+KYP3J3tz4JWcUiYis6t2egG2gD9Lbu73Gm/fIgiU7sENrdXXngvPY8uvFjjbcE1yuF4Q
0NPFw0r37lhGxGZwoR3d90wEPY+w/4MRDEdlnLHQH7lXqOpd6W8GLjb3B6bRRpzqNloOqfyU0uEGn4OIYgBdRRNVzxLC3zxjngJF
NDLBN2lsl/soW3/nwtHp3pxYUgFGbdVNQwRfZKhrMGorCfchN37oSe5ghfW33xMJLxuOqx8vXRsGwkWV9tjhwG8T9vNX5LVDxCc8
hwuOl2bL/nVFGbZJ6r5v7uzdZRX5Mbp82x4k6n1o2nhhf1cgC8rEWCcNmQpIFYrSK61Uc/c6kyUgfuGubAty8Ka4+/Bx1rj5zwdM
eYIscIm/6C4vLOgVpu3TXHYf2GzVQ14hk9rsSYMRYBsR3CWsOJ8mx5TDIVEcZMPnRL8IAqZV80kWtqf3/iHCoZfkJX1SS+Ukkbhg
HY1y1h8zhjeluirIMdXJ60gEf1h5eomUUpKMqVvzt1K40ws1X8ujYuPN26Ai5vVgtcJNF5ma2Ytk85SZHVkqZVGS5UF3Ex57SV8l
CVuGE2M+u6OQwDCk3JuTcADcwpep79jnRrp9Zx89j+Odj2bypbjpO3Vf6MKzzHs7bkqvV3l+of6ngPiMtdFnqJQtWVfrLMNxS5wy
lyLpJUXYK+hbMisk5YVN2jakDGjkrQ5y7LUKTu1utUrRtGfP3BN7B5s5mTJVlKBhVa5vL0YgsZupXrZYQbwsw9JG9oLSh0NOnQls
S944pOCauexw6V81KpamJi1+SXlIzqKillfrXJj7tuHKQBxQmeLhYxOyKRUOP8qSzrLz9afDEkvIcSLoovI5CXvWUGOLdfRRH7Gp
FfwjwYUgWei5EKDgrsrmn22gzaJbXlDUsSvQL+FfSdq+CyHj4FJMO7wq98GY5ndnRDq1rubKXSbBUFL/CpCxwje5sS9VKyEI1aF6
7ZCC05dNhz21UYYhG7RZ8lkIJFGHE/MwYr01mZ7iYEMadV5xQkZi08KtogahamBcMhZg+Yd50tNaxJBpCP8zbX9o/ET1nGP4EdKy
8FoD5CoFzQ1yF+HfsQdOD419Bqnw/Z8ZELjMrfTAMN/iDm2P7+ReVK8m1SHb1GIEaweXDpL8ebP/lPQyoLGz6FCcq+JuQexmi3PG
i7xAAOHHGIDYbv2KbQpfc4fWQ2AnEno1edSDU4buEEVJw4uAJUopq9Gy39YPutzVthl5/iyJgjajAxHzih+JotQMA6atxZPJ7yjR
yx+ozFhfdGQY6hT1JvSZjH7r2Vl8cSMul6VDRjqRdU9ezKY0CkejFZjRM13hmkPQ0+xAWW1Y3gGPyJdZliW95RYYIohz9oQKV/7+
Kn85h3/jcGX0c9EF5H5kFNTPDo4rgXegoxkOEr2LNup525YuSMCty2WueDRCwunamk6K51FkXUhbSWRlk6/eRJQS2nWtGfJEwRwS
8U9lo7p7bL2U/lC094UhnX61lFxRIV+7OYhX8lgo8e+09IbXaU/G6QUB1PNBFT1HjFy8NitMxwoXvHcwRaol4/gqNJru5XEqyRHj
yZ3GWapnVQt0sBnh4F5Cq4ZQmItmAXbBrpIqhjYE28bKqO0o4+gcgr8ogmSZwNDpIr23YBDyqKz6eXD8LZQmaVVhWaKnoZ0I2QXh
Kl5hcwv1wdlOO1OLkPlYG6o8/C5EzL2QNSG2D69+cOo9+a9kI3Pxuj1+Z2kqTH/mRP5vLNH4MgwgrBnE7qGbb2WgM4aD0VuPPoLo
0us0eiOb2TtwkG8vF0dNwwdhFRgy2e8W4Uaxn1JFAP+5aDCcjwj+VIPBhozvLcHMUehMKVzTr95XZ3s3pJxt8tofL26ivwECmBoo
+TA5AEWOB+AT/Vq627PTpzgT+wWhL672awLOeloq07SScKdpmTfm3RxDMEsfH6/0HElwRljdde7t4RBJ6eSZPAtYmCTPEoZq6BSW
un/RRVA4JbHOhL0Kp2R2KzxTCMeLQaTKqUpaxGzZsMt3uwAAAADxUSn3mBBPdwAB0jLevwIAGpf9fbHEZ/sCAAAAAARZWg==
'
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
PHP2SHELL_DIFF_8_0_30='
/Td6WFoAAATm1rRGAgAhARwAAAAQz1jM4Jo0F5RdADIaSQnC/BF9UN4KT0fUaKJ0WK281ySqtdq4gWAU2CmoZ/JhK+0kB3cn8SR2
VAJ6MHS1N180xCXCcaC3Qmk8D1zSzJxt8Rd80/sqHZoOGhbMXdX4W16k9EHnHasdwW6t4jY5rN2mQV1SGh9ZZHOUu9+kBiIArKD5
/vCu+Cd4Tso3YCay/O3fqAhPAC1JSWIbkmYvaxFZPtcHal3oBLlcP66LAoZtwcfcWxqJkfYZ5a2PGVgA3dZBPyagVvK1raAiCVZW
x1IRRw86s17C0mjOg39W6WuHu37shVhKcp7xUenxgBGfVQIXPkHtpUelEXyDf4ToN9xGo2QkaAs2zohtHhEskyb7vTIPw8RX4Jrd
bgbdwXUIe+IwnvuYvqpAyL8fvWmN26edUcJpg+4bv346MjHiOGKyswxnuyoZZGXbnaARGrI5NbCQoIncScA6PW1WWVJ4AMS6ACem
t8sM1z69N4xLN9Bvmv/Pc0R7UgDBNmsfAtCsl8GuNSZ+peSIpbboc+Od9ORTfySO9tfx//R4DqqiyqBClmZ/2BfhUX4KFQhWsI1q
GHqJz1v8fFWQVk+LHLIeVnoyub8Xhx0GU58HshQiTb21q3El3WRG3nsCpOjchcU5XyPK9BvyNRYIIkouFr+qZhXbHHM0t5nndO4z
6+TQO+6on2hYzupU96y4b0Ae2z2fVLyb/psPuae0adDiFlDBBroDokLAh/WoNPphsNGymt4wB8ISI3G9E4LK2LzBZQTLw6fdqtuG
N/jY8ygCgqcOkUMv3X6m2FkwdwQ+6stUXJxpeyozK2+PxR4guu2kcMzwlpX4cg3wJmg5a0fA0CQwPzB1OjC1EQ6WotgYySE2u5m2
T1lY0AkaCJYTNoao40v322rSe7BtTexXLp/WDkqbWgHpAM2u1p1XK9G43hu6m7FFbsE6xi1NMQnP/P75kK/7Nx65UBDpUhSvnEG5
Kf19+/gymFHSHs65iaVCRfwwrdFFMBcArZaLpAmh0p02H5Rp+pNgY5OSFuRtCwfoeyUcCIFwT06LEl2J18tLqrnXqfs7F42P7wBb
ol204ldlkWE+In7JC1o7tib4KFFSYGg/wzbm7qoppwyyNr+yK62zhH57Kzc9p4LX/CFauNw0vrBFjdQDLtjPOFuF2/vNJ/FbG/xA
dnTUq+Msr/buBzTpeg/kry+jIoS9LrAD1tw+actZ82isYleTkEPRfE4rjSYxU0oewXiSZaRQKA7SZWLEt/tguyI+QPTLOgpJgdgj
ErnRIy8n3MIEtswDKvFXBtHhETXxEhOktfGK2Kn6IZWidVRE8puXLZb327ukWnl/uiw/RkE/DrqcXwIxvyT0EPtgTG4EYXeyBLwQ
N24jPO94/FObl4rq1/460VTLncS9pXwZ3hHvsKSgo/YXvnd7UwNRd8fdgfViyiT+Bey/soapdQ45kQjdH5GIgt8/6gYYjVuPSGt4
rcpDVTyZq/6w/dvqP5LfBm6+tf+aLwSYP1nPp08bGAM1PT0iSmd0ZkCzZaIHoF+V4vdghhKG7kWU+r8hVvvVi7LIgUE8Pkn+DXht
r3Lf4yFDA1LJb8TAXS8KUPDFG7jJm003gXgf08LSxHS69/fEBPdL7ZhkQnYHDLOYGNcZmZr5mNzQGluN8zyuK3B/tnsc7QNEiq60
KKW3QtmOHLYhsNXHNcz9HqSIxZFgrSLAe9ET2z80FEcuppYu1V6kss1rCh8gPSWDYAljOASUo2PdkVedYTeVRJxeWHHcPraDogzC
o+4Fot1YuUGBdbaWNdcOpd59Vft+gX8wNaEEUdPl04+zCuMHEp6hTRAAxgC50JUhIqJUfBiH5zPmvy/LrJULtzKazIfEdu92aSFQ
ERjmrktMIFcHrxTRYMGdK49YcLIV7ytE++WZKkLIdnd7Y42XTHDddlXSpuWI2Z8SM7u8Nn4QYYvrMG7sgHCu544w/4rO28yyaCIO
hzKglD78E4AXhIsVkcSHs8wBEwCzPF/fHjq4eaEXPCcElt1wgyKURWQIGhabh5blm/7QHhxp5gWgq0kMyHJjFV/ak7BUbRiRlqZN
M39k9W+bpMFGGKKvAtv3JTar+l5sZdmclrje5HjJxDNl7TKA3soPfkejLyYJ+DF9dto3hF5yy/eVOSXxB8pKUAQfj+QcjOFX836m
inOUp+6E6IxWzcruOBTYHL5jbwja/cloUDJQyDR97EBGpO9zqhRy02zBs03EER8OummKZKXNK/53Bo2E+1pKzEqT+5N4EZST9BRw
m6pdEWISC1n3LO98m5bu/3Wf9kUytLad3lTQ6AYz7IhJ9iDT8m2hdXHBQ6y7aBxHQElgA/XjOmTbtnpgpmSyDzjKxb0H9gwxS0OY
nI8iKGLdAMj5JY9bNrr4rEmzi5VtjMCDkG28MVXE1nS5t2q1PRS6fUtCh1X4f+sw+9Cd9DjFHtoX9EbY8XfSrZAe30LtkLA9IRSW
ZmA/2D0QO1KkEfVNPmougnAI/b/frdFvQbvUi9lvVbuEjfg89Sph21q9Hauiwi48Z0tx1o4LDRho1VG4z67w4rzqDBUX+i9ZMlYZ
PgAGQeZfJP8xuG3O2DNNSYdGkaz14vkNIO7ROYaT3cVc67DshcoO/Cm9FslSabSO0zxizCcv+kf+VUOEZgj/ayG0xpiNv73uKq0+
5brPEujOUAFhBOw1jTpOUIaXmahLSeyyQYDeYAZlarQoHheGla5tvQlj3g/M0DhAKTpGk8uRQ2cA5A/tH0ufIqm+WNf2HSi98GNJ
zSbuoVpVTY9GMdbkec/mYyik/9KHA415okEBGbiYmuVBojvZW2vVo8sORZwJBv9CAbDrfgVbNo8tuFa/8GhhxlGElLIFny2lELGA
pxzhwtKRQtdhZZMwMfn2qndu0TUY5jjQki1u6zP35MkLjdYwvnNRMfYfPesD6VqN9evqrzw/boChorYYpcQzHVaKUdQowrY/ltmb
iq0tPqC1dRnVsmr7/Zg55RGRiwHnmYspGc+Pb/2M3Kjtot/wW7vTzIQtfoiVTI3y3KpN21ZHsm57f0FKsQUZLfnRFAMuYtDzk+MV
z8IXXX2SXFW7NMOQ9gOVFSnhK+wJzqhkk5KV7wnczoDWEk2h8dIqdgl0BFfgMM0rMPqm9lWOi9Igf6xLv5DnzR8MPjBPG3sd75EX
PcHjink/p1QNYPcL0YVdjQMoySBsC1pGwlVNLPmAt3LN4Hcj0C5NpYzD0scQ1dy7Zaq+j+/MAowrUobyTq3AUtLEujTC/DICOi/k
1pxPiz6DUhMK7lVfJ5Rw0r1NUOUkVapXGqtdkgztH4jaYdAByr6xhgHsLGaOtkdoR/xLRfhcu/pPsD7q02uDueudroTd087l1DRE
ffvqLnc19QySL/rHdxUjLc/8BmSQCnieIs/KefNhjmI8oYrlATqWR9ugiX2uD92lRco3QnVB0TyUd7TpgGi3QD91emInXumbNgK2
gLjfyETlwl58321oanq6YO/kKdUcpuHp3HmfHLrUZVIYi0Veb5UlaURFxLvtlmmTYM/OfVqoHXWywTZ0KQY1l0FsEGdGQF8dCHVc
GWsr18kiaQlAaZmkQKMaKE3nkiPkseo5WMmGiDT0Khlvih//5QFEYE/f6+IwgyKxMDA18SP/ZCzTKQxySkthoECqj1UpnvsribRt
knRRSEeh5APui67rMbD/Wlog48HXkca8xlv+RyDFd9mhQIq92sH2JIqfM4/jVg0STGG7PwAyEkAT0o1YVSs2Y6JbjoyUFtKlMBR3
A8gCjqXsTsYbaThk93QsnQ5aIC1eT8RXv2A/kdJQ25UuNjQIIaK/Py+JaFxFzrxHJX5vStNbGFqgSWIjjeYqrP0N3tFk3eSJhuyz
mCAdQhCPFjUtAeGr0A5tCTDHcKbF38v0aZgWjavd15M/dCwhvK772Iq+WI8KmNjn1gdEQAp7tZksXEr/aIba1FMxAiseWhzaMr41
LoP7EVBdYvxMyF5/Rr6Cdh9aSa+1MFP1ymEZrIKEaJSbEXFfIUo9j5jmPWVNnge14HCWH6r6W00DmT3w60mUYvTxFFtgjIS0UwgR
nFxOlTJP5NSBJGOCouU5UizRA+4UaSS7uvlaOcmxr4BS4oSB2EysrKPJdSoTFkr3mF1+nZ3Vh7jR0b53jrHUnTY834smmtwOFrDc
zMq0Zvifd8KPqCOBcWE8d8atbmKqelmAEcyf5an2LTVgC6sPKfUYIZHt7dvs/FIILflZEzjDV+jVlrQjkmimoJuwF7csg91fQWRS
Ee0/xgH6tzKTFPI48IIXURjOeZJNx3ml78cyHhuqtQQE5P4nEASL+nR344HpDBzt10IkAK0FU8eW2d0cpn3cB86LyEn4YgUaPNJb
LyUXXTrC7EPdkcyo1711Mb5uh9f3gciZKcBwi4xCXSFEd7E7KXXpQpBXOAITWfhQjAPempLFIlF1u51HiZuGZtjDTs4LiP3GmUlN
vo7wZW+QxeCZGG3vLIRxYUt2uLT7LbSw26KO3GPGS5/Bzlt1pDd8Upvw6fvc8DZAWdBZ8fNlprDXd5ZlEraTOY1Xil1K1xf/Pwlo
zWqeEPNxVUybzXUAxVrCU418sTH1rOtIUE7qFKwNGLy30ehQfnIdU6waPqe1gGimUrK6zLPqdzdN1XUJ1COcxDkEEBTiojp+FGzn
mcAgjAWr5NL4FLA/hnpY+/FTQeSIOLRA8I+YMtltk7SNOJD5gcBxrd0du+gFynkye/oQgiAchRHT2vMW3LMQrtJeR15RLJd0H/r1
MkX8LdxN1rNA4+D7GXSM4Sb429td9IZ06RURW+Hn5BxzC5AwYA3PF6iEWEgfcM4n+2MJlvPv3XQFm813+GpaC8u9X4h60ZqLZnG0
SjXuRJX8CutOM0x+Ww+ftmGHbSL2hVqfFj9smkbcJdtGSYLuTr/jf98WL+T6stol/IRvWWTKPuCpnOoSLipntODPxUGaBp2NgliR
ewcQ3dYlGHqqNV3c53naPbE57LxWBUXyCiurnX+NWFLOhSb7PN+W9wV2iqfJkLk5l+V4H0lscP3k7ywb9731H+DjO+VFwqlSA6nX
J5v5vW36LnN/TD9xHe8e2Yw23c3vdjBC8XENuXVynmBC9CMUpOyfrVOqfTJK08iKXPaZtZPugXGXA+TRpJCZe3ILV3AzdcYtDmZv
rwQUC7GnIFD6rKRfXYhuAJIt9tDPJamoXhvHi78q8uVkbkHvtjmJiVEL8xpu8SMVdTSYNFwOFSme+gElErL7kjK6dKAPP11g4agq
0oTQdkVCBfc215q1lT7N0o1P3bs+iHfWcYKpLJS/8j4G1Ci94Sb1YrnDRtyEm/JOWRzBSp9iyEu2aNEg5SLiKhzamRXpOFh7XuqR
++GTPOkOExsvL3OvLxXhY02HwCbiJK8IjWxE9bQrNpzH9E7Cr5x3XRcpxcB+sXiSgDrkG2V+VtGbVgbtBfw+CZvVQzU6JuzXX7TF
NDmAEeQoOgmI5Bx2tX6krwl7h45YdhgAJCtA3oCq30C3Bh/5camQK4p8KHRb4pz8eCZxP+JmDcKob2lEQzz5SZLPga/dmrd15aC1
Y4PVAnVhsewRcDUJeGMWgfQ8Fmw118BZG2+dd2gC0UnInxPziP+RLptQMdwx0D2uB1iniLO9+F7AIGtZ+O4HQfI0aCxznfi+zKDt
pu8/RpZr8kwgFCXd+T26GF+tVFPge91u7g7dCjHMLwN4UX3t5n1arqD2LCfouu0FWwKgwLDkRTbr7i/HKvx5wRVmqTEXlzgSVbpk
OWsie7Ky0LGmAiLf8bCSUxvngow6dnXypZwTe7tM3LZ8JiZdtFwIuNHwpuQDqt+PdPU2L95QEYdD2xbgLsdCKHbJcF5lgcLK6brH
LdnkfArPMHWrPBWdOknFRnbQF9rSW/QB3VB4gibQI+f2XxYddzD0PRVE5Ycb+4TQNf+57YQ3ws9tg3gJ8ejcQ5mK4JdR23Y0Phfc
vxnwy23Juj71iR90phMXCg84pe/2McrPB0WAhrfxyta1JxdgIEbBq6QDuxQyILnp4fSXlTotUg1DJtdT/3ljSftziBZVU2mLktDD
tE5W6Slng0JmitfF5LjikZrhd5vQSCU2PI2NwconcCbmRtaOuBUQjiwgIwBcy5CQ4uxI2ANgdpEp/CVjLMbqFOD/e3OBcP3ERYhq
UeeH8AIvIkGPP8Jpa15pcR2NKnOtir8v1HSx+yCMgDjqK4TsegQk6xVlSRJOsIP4lCIwA3FV2SDiFH4wowU6fGwtuHfy01qpy5Iw
loQKSPi4oI/jUXHGqUBlpN2K1NZPIpZ8HPpy4KWa30ePTfJN6I76NiI7QnNmctG0An+ERFXwka7mAoUhdNMSsC1oRMv0F4bbNkzO
ftuPiQaRwEIaaSTiu7iUOAOGRouKGl+CQCLi/XrAUe08TvwCC8Fv/D0OcZMZx25eASKmW5WfmT2y032ha+snlHPCtknQmkqSb1sB
/EwtRjjsf6FF9Z9lIHU94n39PwsKaXVQ5GJOZOO8v3u/lANR84DGlDYVAU/N+hQQEDmVcJVhoPPM0N3Iy+vijr6mM8CxFOyQSZFZ
0JI/h6AQrM3uyVfznKDJ2+Nb4KRq61860f7buF07kjotcEIUQyoHbAsHSCg0QBNnqZ3hNXjNkHEhRMfjZfGgO5eeCASf3n/TGWBO
fuzLvgtuVE0lRqFkbkGSbL7DPFYzDIeDzNl0qHTLGWZqjeOmTYZVwNWWbt3OfxPyLPCfjXnHmKb3ga3+Lc83q7bTQPhn/6PjnuJ+
rAAs7SwcBc8Ritmy/Hmrk9ZKeRdgdE+aMrdZFd2BSKjnoHzlThLtvlc1+P/YuRrBkbef+aHw6tL9wMnbHEg2ourKBHEOWzbvMa2f
59V32exr1PQMehHxsjyX2lhcolP2RlmwPKphbmXgoS4z61VipvxhzjkCK6J/ZkxQisExLwvR5gAB2XwIaktX0QTzVvVcLeCbhuRu
Lyw0AB+woKf8E5GWQdaJ+NcUuPmz24MO8hBQ8HW/D9Bh2YNsuJesfIxTav5t15ifGJ61G8/b7dEdnzgmIkleWyk3MaK2NRZtpIdW
kVwngQJQQHUpRP7YcwpIKuiO116udwV9NBHWXbrLacg/ejrR40h6KdKrYimQfOvcYJFk/d8X8imrDVRY7pw9Cuv2ZIqqaTW1QO4k
/Chz+sZs7LWIvQCyL3TTlZScNuoGEFFDWRscZMPDagLbBtwXPlimHnQHaOgByoy+S2AugkPojqoUyYxlaUiQdRsubkbpT7z18Xwz
UBXBbqqM4fjbk3qPMIm8j0MmZcgJf0rFVQpfGQeZ7She99LD4ZmHC6ryuH5/L5OvLFMl3gPI+KcZLzfiucp1wAtMKLsznMrdi8XW
oDr6/Riuft6QRGVidVSH2/aNj7I4DOmtW4cLG44IWTFvmmUifx3SZdztFzcP8HaORaKWCTxPwQozeHCN605KcOVZ8bVA9oQWVy+l
/RUD+ISOm9L1BfmcWtkboQkMpCZwhpG9tk16fnxYfAMIqthQood0YmEd7bihYMbuJshBQl5fl1u0FUXHhCz9G0BaM66L15qwUl9L
KtomUc1HQ7kg/IjVp2TN0UD0zyvr7JcXu4a68qIfhE247S1NaY1NCSfdE9MhNQ9/eDolsHnTP/g0NW/GbBU41GTRE0Epew/ExThZ
HJm5lk4CMsXRL3DyDk23z4yyNy7nEHdumzIXUwNZmEkqNcNwkV3qObp8+Tu3TNYhGc70Hs3zqamTEtSbUVZghmX+gdi9eDbuJ4o4
rAyoGTRoDY4ya8pg4sAsHjZtbWyeB+yv8HeZAQJR8QNSZS0e/876vG8EOx5FbfSK40is9IbtbcnSuYhFbJrW0/+UrZN1YVmHcVlf
Jug5DE1I/Fg4KbLBsC27q/5G0eUBaJrrbkwlhFPxiGma2KOEBRGvlo6B3ONPZ4wEOzEajBTBI3Zp7SInvQ3lL9IshxNrDsyDaht5
iyGk1ydP33KsI+ZJRA1G1XIOVRGYVwYseKvvqcPZu4Q7qhtrp99ded9bqAFauDPc3P6DXpFojvYjp3aRhDWGlHi8wgCWGpEcToKR
VwABsC+1tAIAm/XDQLHEZ/sCAAAAAARZWg==
'
# shellcheck disable=SC2034  # (se lee por su nombre (${!nombre}) o es a propósito)
PHP2SHELL_DIFF_8_1_34='
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
'

# Arreglo de PHP2Shell para un parche de PHP: "commit|sha256" (nada si no hay)
function php2shell_backport() {
    local row
    for row in "${PHP2SHELL_BACKPORTS[@]}"; do
        [ "${row%%|*}" == "$1" ] && echo "${row#*|}" && return 0
    done
    return 1
}

# php2shell_apply <version> <carpeta del codigo de PHP> <log>: aplica el arreglo (comprobado antes con
# su sha256: si no coincide o no entra limpio, no se compila nada)
function php2shell_apply() {
    local version=$1 src=$2 log=$3 info var diff
    info=$(php2shell_backport "$version") || return 1
    var=PHP2SHELL_DIFF_${version//./_}
    diff=$(dirname "$log")/php2shell-$version.diff
    base64 -d <<< "${!var}" 2> /dev/null | xz -dc > "$diff" 2> /dev/null
    if [ "$(sha256sum "$diff" | cut -d' ' -f1)" != "${info#*|}" ]; then
        echo "  El parche de seguridad de PHP $version no coincide con su suma sha256. Se cancela."
        return 1
    fi
    if ! patch -d "$src" -p1 --forward --batch --no-backup-if-mismatch < "$diff" > "$log" 2>&1; then
        echo "  El parche de seguridad no entra en PHP $version. Ultimas lineas de $(basename "$log"):"
        tail -10 "$log" | sed 's/^/    /'
        return 1
    fi
}

# Estado de PHP2Shell de una version instalada: php2shell_state <carpeta> <php>
#   ok|                      tiene el arreglo (su parche o uno posterior)
#   parche|<texto>           un parche sin soporte compilado con el arreglo de php-src
#   vulnerable|<texto>       sin el arreglo (y que hacer)
function php2shell_state() {
    local dir=$1 php=$2 branch=${2%.*} min v
    if ! is_fpm_install "$dir"; then
        echo "vulnerable|XAMPP (PHP $php): sus binarios no tienen el arreglo ni se pueden arreglar"
        return 0
    fi
    for v in $PHP2SHELL_FIXED; do
        [ "${v%.*}" == "$branch" ] && min=$v
    done
    if [ -n "$min" ]; then
        if [ "$(printf '%s\n' "$min" "$php" | sort -V | head -1)" == "$min" ]; then
            echo "ok|"
        else
            echo "vulnerable|PHP $php: el arreglo esta en PHP $min"
        fi
    elif php2shell_backport "$php" > /dev/null; then
        if [ -f "$dir/$PHP2SHELL_MARK" ]; then
            echo "parche|PHP $php + parche de seguridad (oct 2026)"
        else
            echo "vulnerable|PHP $php sin el parche de seguridad: Actualizar la compila con el"
        fi
    elif [ "$(printf '%s\n' 8.5 "$branch" | sort -V | tail -1)" == "$branch" ]; then
        # (una rama posterior a la 8.5 ya sale con el arreglo)
        echo "ok|"
    else
        echo "vulnerable|PHP $php: no tiene arreglo (solo lo tienen 7.4.33, 8.0.30, 8.1.34 y desde 8.2.35)"
    fi
}

# Solo para probar el instalador sin sudo: LVM_PRUEBA=/ruta instala las pilas en /ruta/lampp-X.Y
# con puertos altos y sin tocar /opt/lampp, /opt/htdocs, /opt/config ni apt
TEST_DIR=${LVM_PRUEBA:-}
# Las variables de prueba solo valen con LVM_PRUEBA: si no, una variable de tu sesion (que puede
# poner cualquier programa tuyo) cambiaria que ficheros toca el gestor con sudo
if [ -z "$TEST_DIR" ]; then
    unset LVM_HTDOCS LVM_VHOSTS LVM_VHOSTS_ACTIVO LVM_SSL_CERTS LVM_SSL_KEYS LVM_HOSTS LVM_BD_CLIENTE \
        LVM_BD_VOLCADO LVM_ENLACE LVM_PS LVM_PRUEBA_CAS LVM_PRUEBA_CLAVES LVM_PRUEBA_SSL LVM_MAILPIT_URL \
        LVM_MAILPIT_SHA LVM_DOCKER_SYSCTL LVM_PORT_START_FILE LVM_CLOUDFLARED_URL LVM_CLOUDFLARED_SHA \
        LVM_DNS_SCRIPT LVM_DNS_UNIT LVM_DNS_RESOLVED
fi
# Proyectos y vhosts compartidos por todas las versiones (LVM_HTDOCS/LVM_VHOSTS solo para pruebas)
HTDOCS_DIR=${LVM_HTDOCS:-/opt/htdocs}
VHOSTS_FILE=${LVM_VHOSTS:-/opt/config/httpd-vhosts.conf}
PROJECTS_FILE="$HOME/.lvm-instalador/proyectos"
# Vhost que se crea para cargar proyectos si no hay ninguno (LVM_HOSTS solo para pruebas)
PROJECT_VHOST=web.local
HOSTS_FILE=${LVM_HOSTS:-/etc/hosts}
# Fichero de vhosts de la version activa, el que se edita desde la ventana (LVM_VHOSTS_ACTIVO solo para pruebas)
ACTIVE_VHOSTS=${LVM_VHOSTS_ACTIVO:-/opt/lampp/etc/extra/httpd-vhosts.conf}
if [ -n "$TEST_DIR" ]; then
    SUDO="" PORT_HTTP=8080 PORT_HTTPS=8443 PORT_MYSQL=3307 PORT_FTP=2121
else
    SUDO=sudo PORT_HTTP=80 PORT_HTTPS=443 PORT_MYSQL=3306 PORT_FTP=21
fi
# Cache de descargas de las pilas propias (de root; descargas_cache.sh)
DL_CACHE_DIR=/var/cache/nexum-stack
[ -n "$TEST_DIR" ] && DL_CACHE_DIR=$TEST_DIR/descargas

# Versiones de XAMPP disponibles
# carpeta|release|PHP|Apache|MariaDB|ProFTPD|Perl|phpMyAdmin|md5 del instalador|sha256 del instalador
# (la sha256 se saco el 20/10/2026 de los instaladores de SourceForge, con su md5 igual al de aqui:
# el md5 solo no basta, se pueden fabricar dos ficheros con el mismo)
XAMPP_CATALOG=(
    "7.1.33|7.1.33-1|7.1.33|2.4.41|10.4.10|1.3.6|5.16.3|4.9.2|896394f65873a2b14eca63b3c6d7f1ac|15b46deccb8a81946e9c1e26eade6c19481108906effb4bdbdfc55895c7c5da8"
    "7.4|7.4.33-0|7.4.33|2.4.54|10.4.27|1.3.6|5.34.1|5.2.0|8467421af9ee1f04464b3e439199480c|8785db581be53d6126e2f400112cb86ae3ab9119d73e18f619231c33231302d0"
    "8.1|8.1.25-0|8.1.25|2.4.58|10.4.32|1.3.6|5.34.1|5.2.1|e380a45f13e1dbe6b0544c9a304e153c|0e3940cb7315ea3432e6925a60e6d6cd6705d5b116f0c7398aa585e4a5081b5c"
)
# (1.54.1: sin el XAMPP 8.2.4. Ningun XAMPP tiene el arreglo de PHP2Shell ni se puede arreglar: se
# ofrecen solo para proyectos que no funcionan con una pila propia, avisando)

DRY=0
PROGRESS=""

# Firma del panel principal
SIGNATURE="By M.Mascuñano"

# Version del instalador: sale debajo de la firma y en "Acerca de", con la lista de cambios
APP_VERSION="1.57.10"

# Actualizaciones: la ultima publicacion (Release) del repositorio de GitHub. Cada una lleva el
# lvm-instalador_<version>_all.deb y su firma (.sig), hecha con la clave de UPDATE_KEY_FPR; su parte
# publica va aqui y en /opt/lvm-instalador/nexum-stack-firma.gpg (la que usa el ayudante, como root)
UPDATE_REPO="mariomasku/nexum-stack"
UPDATE_KEY_FPR="3506F1EB091AD4A23F40081FF24FD5CC07557404"
UPDATE_KEY_B64='
mDMEatoqkhYJKwYBBAHaRw8BAQdAxAut0to4730sesIdm2rZyf1OW711qSJX0I1R05RzfS+0M05l
eHVtIFN0YWNrIC0gZmlybWEgZGUgcGFxdWV0ZXMgPHNvcG9ydGVAaGV4ZXIuZGV2PoiTBBMWCgA7
FiEENQbx6wka1KI/QAgf8k/VzAdVdAQFAmraKpICGwMFCwkIBwICIgIGFQoJCAsCBBYCAwECHgcC
F4AACgkQ8k/VzAdVdARhwgD+PjUtI6Bn7GLlySuGZHPldPSF2YKPk32jWFsUZXRtHLIBAPO+uAx+
lARQvnHUnZRmG9VdnoUuRq5Phb/RhBOXrqIA
'

# Logo de hexer abajo a la izquierda, fuera de las ventanas: '#' en blanco y '/' en verde #45A57C
LOGO=(
    "##  //"
    " ##//"
    "  ##"
    " ####"
    "##  ##"
)

