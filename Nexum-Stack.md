# Nexum Dev Stack (lvm-instalador)

**Gestor de entornos locales de desarrollo para Linux y Mac**
Versión actual: **Linux 1.55.10** · **Mac 1.36.0** · Autor: M. Mascuñano – HEXER

---

## 1. Resumen

Nexum Dev Stack es una aplicación con ventana propia (y también comandos para la terminal) que permite tener **varias versiones de PHP en el mismo equipo**, cada una con su servidor web, su base de datos y sus herramientas, y **cambiar de una a otra con un clic**.

Además automatiza todo lo que antes había que hacer a mano siguiendo el manual interno de XAMPP: dar de alta proyectos, crear certificados, editar los virtual hosts, falsear dominios en `/etc/hosts`, cargar y descargar bases de datos, ajustar permisos y revisar errores del servidor.

El objetivo es que cualquier persona del equipo pueda **montar un proyecto de cliente en local en minutos**, sin tocar ficheros del sistema ni memorizar comandos, **sin riesgo de romper lo que ya funciona** y **sin dejar el equipo expuesto**: todo queda accesible solo desde el propio equipo.

---

## 2. ¿Por qué hacía falta? (punto de partida)

### 2.1 Cómo se trabajaba hasta ahora

El entorno local se montaba siguiendo un **manual interno**:

1. Instalar XAMPP en `/opt/lampp` (con PHP 7.4, la versión más habitual en los servidores).
2. Cambiar el dueño de `htdocs` y añadir `User` y `Group` al `httpd.conf` para evitar problemas de permisos con la caché.
3. Activar los virtual hosts descomentando una línea del `httpd.conf`.
4. Por cada proyecto:
   - añadir el dominio a `/etc/hosts`,
   - crear su bloque `<VirtualHost>` en `httpd-vhosts.conf`,
   - generar un certificado SSL con `openssl` respondiendo a varias preguntas,
   - añadir un segundo bloque para el puerto 443 con las rutas del certificado,
   - y reiniciar XAMPP.
5. Para tener varias versiones de PHP se usaba un script propio, **`lvm`**, que cambiaba el enlace `/opt/lampp` entre varias instalaciones de XAMPP (`/opt/lampp-7.4`, `/opt/lampp-8.1`, `/opt/lampp-8.2.4`…).

### 2.2 Los problemas

| Problema | Consecuencia |
|---|---|
| **XAMPP dejó de publicar versiones nuevas: la última es PHP 8.2.** | No había forma de trabajar con PHP 8.3, 8.4 o 8.5, que ya piden muchos proyectos y servidores. |
| **Todo era manual.** Cada proyecto exigía editar 3 ficheros del sistema, generar certificados y reiniciar. | Mucho tiempo por proyecto y errores frecuentes (vhosts mal copiados, certificados con otro nombre, alias equivocados…). |
| **Las tiendas PrestaShop redirigen siempre a su dominio real.** | Para verlas en local hay que falsear su dominio en `/etc/hosts`… y acordarse de quitarlo después, o el navegador sigue llevando a la copia local en lugar de a la web real. |
| **El script `lvm` original solo hacía `lampp stop` y confiaba en él.** | Al cambiar de versión se quedaban procesos de la anterior en memoria (todos se llaman `/opt/lampp/bin/…`, así que no se distinguían). Gastaban memoria y podían bloquear los puertos 80, 443 y 3306. |
| **Las bases de datos se cargaban a mano** (phpMyAdmin o terminal), con ficheros que a veces pesan varios GB y vienen en `.zip`. | Lento, sin barra de progreso y con errores por incompatibilidades entre versiones de MariaDB. |
| **XAMPP viene abierto a toda la red.** | Cualquier equipo de la oficina podía ver los proyectos, entrar en phpMyAdmin o en el FTP (usuario `daemon`, contraseña `xampp`). |
| **Instalar PHP en el sistema no era una opción.** | Hay proyectos críticos de clientes (WordPress y PrestaShop) en las versiones existentes que **no se pueden romper**. |
| **Los compañeros con Mac** no tenían una herramienta equivalente. | Cada uno montaba su entorno a su manera. |

### 2.3 La solución

Una aplicación que:

- **Construye un "XAMPP virtual" por cada versión de PHP**, de la 7.4 a la 8.5, con su propio Apache, PHP, MariaDB, ProFTPD, Perl y phpMyAdmin, compilados para ella y compatibles entre sí.
- **Respeta lo que ya existe:** sigue usando las instalaciones de XAMPP que ya había, la carpeta de proyectos y el fichero de vhosts compartidos. No instala PHP ni MariaDB en el sistema.
- **Convierte el manual en botones:** todo lo que el manual explicaba paso a paso lo hace la aplicación sola, y **solo lo que falte**: lo que ya está bien configurado no se toca.
- **Protege el equipo por defecto:** cierra a la red lo que XAMPP deja abierto y avisa, con un botón para arreglarlo, de lo que siga sin proteger.

---

## 3. Qué hace exactamente

La ventana tiene una barra lateral con cinco apartados: **Versiones**, **BBDD**, **Servicios**, **Hosts** y **Herramientas**.

### 3.1 Versiones de PHP y proyectos (apartado **Versiones**)

- **Cargar proyecto** (lo primero del apartado): se busca la carpeta del proyecto en `/opt/htdocs` y se pulsa Cargar. `web.local` pasa a apuntar a esa carpeta y se monta la versión de PHP donde está su base de datos; si está en varias, pregunta cuál, con la fecha de cada copia. Si es la primera vez:
  - **WordPress:** comprueba que `wp-config.php` usa la base del proyecto y entra en el MariaDB local. Si no (por ejemplo, con el código de producción pegado encima), lo rehace con la plantilla de este equipo, con la dirección local en `WP_SITEURL` y `WP_HOME`.
  - **PrestaShop:** crea o corrige su `parameters.php` (también en tiendas recién clonadas, que no lo traen) y vacía su `var/cache`.
  - El proyecto cargado tiene botones para abrirlo en el navegador, abrir su base en phpMyAdmin, entrar en su panel (wp-admin o el back office de la tienda) y abrir la carpeta en **Visual Studio Code**, además de uno para desmontarlo.
- **Montar nuevo proyecto:** asistente de tres pasos. Se indica la dirección del repositorio de GitHub (se clona en `htdocs`), la versión de PHP y la base nueva, con su volcado si lo hay. Al terminar, el proyecto queda cargado.
- **Varias versiones instaladas a la vez**, en `/opt/lampp-<versión>` (Linux) o `/Applications/XAMPP-<versión>` (Mac). Solo una está **montada** (activa) en cada momento.
- **Cambiar de versión con un clic** ("Activar"): para la actual, comprueba que no quede nada en memoria y arranca la nueva.
- **Arrancar, reiniciar y parar** la versión montada.
- **Instalar nuevas versiones de PHP** (al final del mismo apartado):
  - Lista las ramas de PHP con su último parche, consultando php.net en el momento, con la **fecha de publicación** y si es un **parche de seguridad** o solo de errores.
  - Indica el estado de cada una: **Estable** (recomendada para proyectos nuevos), **Solo seguridad** (con su fecha de fin) o **Sin soporte**.
  - Permite instalar un **parche concreto** (por ejemplo 8.3.10) si un servidor lo exige.
  - En Linux, también los **XAMPP oficiales** para proyectos antiguos (PHP 7.1 a 8.2).
  - Cada versión se compila en el equipo (10–40 minutos) con barra de progreso y, si algo falla, genera un **informe del error** listo para copiar.
- **Actualizar** una versión al último parche de su rama y **desinstalar** versiones (con copia de sus bases de datos si se quiere).
- **Avisos con botón:** arriba del apartado aparecen los problemas pendientes, cada uno con el botón que lo arregla. Por ejemplo, versiones sin proteger (**Protegerlas**), certificados en los que confía todo el equipo (**Arreglarlos**), phpMyAdmin con fallos ya corregidos (**Actualizarlos**), tablas del sistema de MariaDB antiguas que llenan el registro de errores (**Repararlas**) o certificados de proyectos que el navegador no acepta (**Confiar**).
- **Control de procesos:** solo puede quedar en memoria la versión montada. Si queda algún proceso de otra versión (herencia del `lvm` antiguo), la aplicación lo detecta, avisa y lo cierra: primero de forma normal (a MariaDB le da hasta 90 s para guardar) y, si no responde, a la fuerza.

### 3.2 Bases de datos (apartado **BBDD**)

- **Buscador** de bases en todas las versiones instaladas. Cada base muestra cuándo se cargó y su antigüedad ("hace 3 días", "hace 4 meses"…).
- **Subir o actualizar una base** (`.sql`, `.sql.gz` o `.zip` tal como llegan del servidor), con barra de progreso:
  - Si la base ya existe, **siempre se vacía antes** y se guarda una copia de lo que tenía en `~/lvm-copias`. Así no se mezclan filas de dos cargas ni quedan tablas que la copia ya no trae.
  - Campo **Proyecto**: si es la base nueva de un proyecto, se elige su carpeta y su configuración (`wp-config.php` o `parameters.php`) pasa a usarla.
  - Corrige automáticamente la primera línea que añaden las versiones modernas de MariaDB y que las antiguas no entienden.
  - En las bases de WordPress y PrestaShop añade un **administrador de pruebas** (`local@local.test` / `local`, igual en todos los equipos) para entrar en el panel sin buscar contraseñas.
- **Copiar una base a otra versión de PHP**, para probar el proyecto con ese PHP sin tocar la original. Si la otra versión ya la tiene, pide confirmación y guarda antes una copia.
- **Crear, descargar (en `.zip`) y borrar bases** (al borrar, ofrece guardar una copia).
- **Vaciar la caché** de una tienda PrestaShop desde su base.
- **Abrir phpMyAdmin** de la versión activa, en su propia dirección (`http://127.0.0.1/phpmyadmin/`), y **actualizarlo** en cada versión al más nuevo que admite su PHP.

### 3.3 Servicios (apartado **Servicios**)

- Una tarjeta por servicio (Apache, MariaDB y FTP) de la versión montada, con su estado, sus puertos y botones para **arrancar, parar o reiniciar** cada uno, como el panel de XAMPP.
- Indica si se puede entrar desde la red y, si es así, ofrece cerrarlo.
- El FTP ya no arranca con la versión: se activa aquí solo cuando hace falta.

### 3.4 Dominios falseados (apartado **Hosts**)

- **Tiendas PrestaShop:** al cargar una tienda, la aplicación:
  1. Lee su dominio real de la base de datos (tabla `shop_url`).
  2. Crea su **certificado SSL** si no existe (sin preguntas, válido para el dominio y su `www.`).
  3. Crea su **virtual host http y https** si no existe, con el mismo formato que los ya existentes.
  4. **Falsea el dominio** en `/etc/hosts` para que el navegador abra la copia local, y hace que el navegador acepte su certificado mientras está falseado (sin el aviso "La conexión no es privada").
  5. Al cargar **cualquier otro proyecto**, el dominio deja de estar falseado, vuelve a llevar a la web real y el navegador deja de aceptar el certificado local.
- **Lista de todos los dominios** de los vhosts con un **interruptor** para falsearlos o no a mano. El dominio falseado en cada momento aparece arriba, con el interruptor encendido y un botón para abrirlo. Los dominios `.local` quedan en `/etc/hosts` (si no, el equipo los preguntaría a la red) salvo que se apaguen a mano, con un aviso, y no aparecen como falseados.
- **Nuevo proyecto con dominio falseado:** pensado para proyectos que se construyen desde cero (por ejemplo, con Figma + Claude) y se van a subir a producción tal cual:
  - Se indica el **dominio de producción**.
  - Se elige la **carpeta** del proyecto de la lista de `htdocs` (por ejemplo, la descargada con `git clone`) o se crea una nueva.
  - Se elige la **base de datos** con su **nombre de producción** (o se crea vacía).
  - La aplicación crea lo que falte, el vhost con certificado, y falsea el dominio.
  - Resultado: se desarrolla en local con el dominio y la base reales y, al exportar, **todo queda montado en producción sin haber tocado nada allí antes**.
- Si `web.local` no lleva a este equipo (por ejemplo, porque `/etc/hosts` lo manda a otra dirección), avisa con un botón para arreglarlo.
- Nunca toca `localhost`, `web.local` ni el nombre del equipo. Cada cambio en `/etc/hosts` o en los vhosts guarda antes una copia en `~/lvm-copias`.

### 3.5 Herramientas (apartado **Herramientas**)

- **Editar** los virtual hosts y el fichero `/etc/hosts`. Se edita una copia; al aplicarla se comprueba, se guarda la anterior en `~/lvm-copias` y se recarga Apache. Si Apache no la acepta, todo queda como estaba.
- **Registro de errores:** primero el del proyecto cargado (donde van los errores de PHP, como el "error crítico" de WordPress) y debajo el general de Apache. Cada uno con **"Ver el final"** (las últimas líneas, sin abrir ficheros enormes; hay logs de más de 100 MB) y **"Abrir"**. Es lo primero que hay que mirar cuando el servidor local da un error.
- **Carpetas:** proyectos, copias de seguridad y registros de instalaciones.
- **Comandos de lvm-instalador:** ayuda con todos los comandos de la terminal y qué hace cada uno.
- **Buscar una versión nueva** de la aplicación (también en el menú ☰ → Buscar actualizaciones), **Novedades** y **Acerca de**.
- **Solo Linux:** registrar un XAMPP instalado a mano y volver a crear el icono del menú.
- **Solo Mac:** apartar un **XAMPP oficial** que ya tuviera el compañero (copiando antes sus bases, proyectos y vhosts, sin borrar nada), cargar esas copias en el gestor y volver al XAMPP oficial si hiciera falta.

### 3.6 Lo del manual que ahora se hace solo

| Paso del manual | Ahora |
|---|---|
| `chown` de `htdocs` | Automático al registrar un XAMPP, si hace falta. |
| `User` / `Group` en `httpd.conf` | Se añade solo si la versión no lo tiene (al cargar un proyecto o registrar un XAMPP). Las versiones nuevas ya se instalan así. |
| Descomentar `Include etc/extra/httpd-vhosts.conf` | Automático. |
| Añadir el dominio a `/etc/hosts` | Automático (PrestaShop y proyectos nuevos) o con un interruptor. |
| Crear el `<VirtualHost>` del puerto 80 y del 443 | Automático, solo si falta. |
| Generar el certificado con `openssl` y sus preguntas | Automático, sin preguntas. Cada proyecto lleva su propio certificado (en `/opt/config/ssl`) y el navegador lo acepta sin avisos. |
| Ajustar `wp-config.php` o `parameters.php` a la base local | Automático al cargar el proyecto o al subir su base. |
| `sudo lampp start / stop / restart` | Botones de la ventana (y además comprueba que no quede nada en memoria). |
| Enlace simbólico `web.local` al proyecto | Botón "Cargar proyecto". |
| `net-tools` para el aviso de `netstat` | Se instala solo al instalar un XAMPP, si falta. |

---

## 4. Seguridad y garantías

- **No instala PHP ni MariaDB en el sistema:** cada versión vive en su carpeta y solo funciona cuando está montada.
- **No modifica las instalaciones existentes** más allá de lo imprescindible, y solo si falta.
- **Solo para este equipo:** Apache, MariaDB y el FTP solo aceptan conexiones del propio equipo. Si una versión no se puede proteger, no se arranca.
- **Navegador:** una web que se visite no puede leer phpMyAdmin ni los proyectos locales, ni enviar consultas a phpMyAdmin. phpMyAdmin tiene su propia dirección y los dominios desconocidos reciben un error 403.
- **Ficheros que no se sirven:** `.env`, `.git`, claves, copias de bases de datos, copias de seguridad de las webs, registros y otros ficheros sensibles de los proyectos no se pueden descargar desde el navegador.
- **Volcados de bases de datos:** se cargan con un usuario que solo puede tocar esa base. Un volcado de una web comprometida no puede cambiar otras bases, crear usuarios, leer ficheros del equipo ni ejecutar programas.
- **Actualizaciones de la aplicación:** cada versión va **firmada** por quien publica el programa. La firma se comprueba antes de ofrecerla y otra vez al instalarla, y no se acepta un paquete sin firma válida, más viejo que el instalado o que lleve ficheros que no son suyos.
- **Copias de seguridad automáticas** en `~/lvm-copias` (solo accesibles para tu usuario) antes de cambiar `/etc/hosts` o los vhosts, antes de cargar una copia encima de una base, al borrar bases de datos y al desinstalar versiones.
- **Modo simulación** (`--simular`): muestra lo que haría cualquier acción sin cambiar nada.
- La contraseña de administrador se pide en una **ventana propia**, solo cuando una acción la necesita, y no la puede leer ningún otro programa.
- Cada versión de PHP tiene **sus propias bases de datos**: instalar una nueva no toca las de las demás.
- **Batería de pruebas automáticas** (941 pruebas, Linux y Mac) que se pasa entera antes de publicar cada versión.

---

## 5. Instalación y actualización

### Linux (Ubuntu / Debian, 64 bits; desde Ubuntu 20.04)

- **Instalar:** doble clic en `lvm-instalador_<versión>_all.deb` → "Instalar".
- **Instalar:** el `.deb` de cada versión está en las [publicaciones del repositorio](https://github.com/mariomasku/nexum-stack/releases).
- **Actualizar:** en la aplicación, pulsar **Buscar actualizaciones** (menú ☰ o Herramientas). Busca la última versión publicada en GitHub, comprueba su firma, muestra su fecha y su huella y la instala tras pedir la contraseña. Sin conexión, busca un `.deb` firmado en **Descargas**.
- Algunas versiones cambian el programa que instala las actualizaciones y hay que instalarlas una vez en la terminal (`sudo apt install ./lvm-instalador_<versión>_all.deb`); la aplicación lo detecta y da la orden lista para copiar. La 1.50.0 es una de ellas.
- Se abre desde el menú de aplicaciones: **Nexum Dev Stack**.

### Mac (Apple Silicon: M1 o posterior)

- Descomprimir `lvm-instalador-mac-<versión>.zip` y ejecutar en la terminal `bash empaquetar-dmg.sh`, que compila la aplicación en el propio Mac y genera el `.dmg`.
- Instalar desde el `.dmg`. Usa Homebrew solo para librerías de compilación.
- **Actualizar:** dejar el `.dmg` nuevo en **Descargas** y pulsar **Buscar actualizaciones**.

### Requisitos

- Usuario con permisos de administrador (`sudo`).
- Conexión a internet.
- Unos 5 GB libres por versión de PHP mientras se instala (luego ocupa ~1,5 GB).

---

## 6. Comandos principales (terminal)

La aplicación se usa normalmente desde la ventana, pero todo está disponible también como comando:

| Comando | Qué hace |
|---|---|
| `lvm-instalador` | Abre la ventana (o el panel en la terminal). |
| `lvm-instalador use 8.4` | Monta la versión 8.4. |
| `lvm-instalador arrancar` / `parar` / `reiniciar` | Controla la versión montada. |
| `lvm-instalador servicio apache\|mariadb\|ftp arrancar\|parar\|reiniciar` | Controla un servicio suelto de la versión montada. |
| `lvm-instalador instalar --php 8.4,8.5 --si` | Instala versiones sin preguntas. |
| `lvm-instalador procesos` | Procesos en memoria y de qué versión es cada uno. |
| `lvm-instalador importar-bd copia.zip mi_base --crear` | Carga una copia de base de datos (si la base ya existe, la vacía antes y guarda copia). |
| `lvm-instalador exportar-bd mi_base copia.zip` | Descarga una base en `.zip`. |
| `lvm-instalador copiar-bd mi_base 8.2.4 8.4` | Copia una base a otra versión de PHP. |
| `lvm-instalador cargar-proyecto <carpeta> [versión]` | Carga un proyecto (y su dominio si es PrestaShop o proyecto nuevo). |
| `lvm-instalador montar-proyecto <url de git> <carpeta> <versión> <base> [volcado]` | Clona un proyecto de GitHub, crea su base y lo deja cargado. |
| `lvm-instalador nuevo-dominio <dominio> <carpeta> [base]` | Proyecto nuevo con su dominio de producción falseado. |
| `lvm-instalador hosts-falsear <dominio> si/no` | Falsea o deja de falsear un dominio. |
| `lvm-instalador asegurar` | Deja las versiones accesibles solo desde este equipo. |
| `lvm-instalador --simular <comando>` | Muestra lo que haría sin cambiar nada. |
| `lvm-instalador --ayuda` | Lista completa de comandos. |

---

## 7. Beneficios para el equipo

- **Proyectos con PHP moderno** (8.3, 8.4, 8.5) sin depender de XAMPP.
- **De varios pasos manuales a un clic** para montar un proyecto, incluido su dominio, su certificado y su configuración. Un proyecto nuevo de GitHub queda listo con un asistente de tres pasos.
- **Menos errores de configuración:** vhosts, certificados y hosts siempre con el mismo formato.
- **Bases de datos sin sorpresas:** cada carga deja la base limpia y con copia de lo anterior, y siempre hay un administrador de pruebas para entrar en el panel.
- **Entorno igual para todos**, en Linux y en Mac.
- **Equipos protegidos:** nada queda abierto a la red de la oficina.
- **Sin procesos fantasma** al cambiar de versión.
- **Diagnóstico rápido** de errores del servidor desde la propia aplicación.
- **Flujo directo a producción** para proyectos nuevos: dominio y base de datos reales desde el primer día.

---

## 8. Estado y pendientes

- **Linux:** versión 1.55.10, probada en Ubuntu 24.04. Pendiente de comprobar en un equipo con Ubuntu 20.04.
- **Mac:** versión 1.36.0, con las mismas funciones que Linux. Se probó a fondo en un Mac real hasta la 1.12.0; las versiones posteriores pasan la batería de pruebas automáticas, pero quedan por comprobar en un Mac real "Apartar" con un XAMPP oficial de un compañero y que el navegador acepte los certificados de los proyectos. La versión de Mac todavía no lleva el nombre Nexum Dev Stack.
- **Actualizaciones desde GitHub:** desde la 1.50.0. Pendiente de la primera prueba completa: publicar la 1.50.1 e instalarla con **Buscar actualizaciones**.
- **Manual interactivo:** pendiente de rehacer con datos de ejemplo (las capturas actuales son de un equipo real).
