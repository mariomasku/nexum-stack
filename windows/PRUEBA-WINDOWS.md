# Prueba de Nexum Dev Stack en Windows 11 (versión 0.1.0, fase 1)

Es la primera versión para Windows. Se escribió y se compiló desde Linux: la parte que no depende de Windows (catálogo, descargas y firmas, configuración de Apache, PHP y MariaDB, proyectos, BBDD, hosts, comandos) tiene 205 pruebas automáticas que pasan, con procesos falsos. **Nada de lo que toca Windows de verdad se ha ejecutado nunca**: la ventana WPF, los procesos, los permisos (ACL), el aviso de UAC, los certificados, los puertos y el registro de Windows. Esta prueba es para eso.

Ve paso a paso y, en cuanto algo falle, para y mándame lo que dice el apartado [Qué mandarme](#qué-mandarme).

## Antes de empezar

- Windows 11 x64, con internet y una cuenta que pueda aceptar el aviso de UAC (administrador).
- Mejor en una máquina virtual o un equipo de pruebas, con una instantánea antes de empezar: el programa cambia `C:\Windows\System32\drivers\etc\hosts` y añade certificados a la raíz de confianza de tu usuario.
- Los puertos 80, 443 y 3306 libres. Si tienes XAMPP, IIS o WAMP, páralos (o compruébalo con el paso 3, que debe decir quién los usa).
- No hace falta instalar .NET ni el runtime de Visual C++: el programa lleva .NET dentro y ofrece el runtime si falta (es parte de la prueba).

## Paso 1: abrir el programa

1. Saca el `.zip` en una carpeta cualquiera (por ejemplo, `Descargas\nexum`).
2. Doble clic en `NexumDevStack.exe`. La primera vez SmartScreen puede decir «Windows protegió su PC»: **Más información → Ejecutar de todas formas**. Tarda unos segundos la primera vez (se descomprime en `%TEMP%`).
3. Comprueba:
   - [ ] Se abre **una sola ventana**, sin ninguna consola negra detrás.
   - [ ] Cabecera: el logotipo, «**Nexum** Dev Stack» (Dev Stack en azul) y debajo «Entornos LAMPP y Docker · v0.1.0».
   - [ ] A la izquierda, ENTORNO (Proyectos, Versiones de PHP, Bases de datos, Docker) y SISTEMA (Dominios y hosts, Configuración).
   - [ ] La barra de título propia: se arrastra, doble clic maximiza, los botones de minimizar, maximizar y cerrar funcionan, se puede cambiar de tamaño por los bordes, y **Windows + flechas** la coloca (snap). Maximizada no se sale de la pantalla ni tapa la barra de tareas.
   - [ ] Menú ☰ → tema claro y oscuro: cambia todo (también los diálogos y los menús desplegables). Al cerrar y abrir, se acuerda.
   - [ ] Menú ☰ → Novedades, Comandos y Acerca de se abren y se leen bien.
   - [ ] Con la pantalla a 125 % o 150 % de escala se ve nítido y nada se corta.
4. Ábrelo una segunda vez con botón derecho → **Ejecutar como administrador**: debe abrir, pero al arrancar algo tiene que decir que no arranca Apache ni MariaDB como administrador. Ciérralo y sigue con el normal.

## Paso 2: preparar C:\NexumDevStack

1. La ventana debe ofrecer **Preparar** (o en los avisos). Acéptalo: sale el aviso de UAC **delante** de la ventana (si sale detrás, parpadeando en la barra de tareas, apúntalo).
2. Comprueba:
   - [ ] Se crea `C:\NexumDevStack` con `versiones`, `programa`, `descargas`, `tareas`, `datos`, `config`, `htdocs`, `registros` y `tmp`.
   - [ ] En PowerShell (normal, no como administrador):

     ```powershell
     icacls C:\NexumDevStack\versiones      # Administradores y SYSTEM control total; Usuarios solo lectura
     icacls C:\NexumDevStack\htdocs         # tu usuario control total, sin "Usuarios"
     New-Item C:\NexumDevStack\versiones\prueba.txt   # debe dar "Acceso denegado"
     New-Item C:\NexumDevStack\htdocs\prueba.txt      # debe funcionar (bórralo después)
     dir C:\NexumDevStack\programa                    # NexumDevStack.exe
     ```

   - [ ] Si cancelas el aviso de UAC, dice «cancelado en el aviso de Windows» y no se queda colgado.

## Paso 3: avisos y runtime de Visual C++

- [ ] El botón de avisos (a la izquierda del visor) dice lo que haya: runtime de Visual C++ que falta o es viejo, puertos ocupados (con el nombre del programa), etc.
- [ ] Si falta el runtime: **Instalar** lo descarga de Microsoft, comprueba la firma y abre su instalador (con UAC). Después el aviso desaparece.
- [ ] Si tienes algo en el puerto 80 o 3306, dice qué programa es.

## Paso 4: instalar versiones de PHP

1. **Versiones de PHP → Instalar**. Instala primero **8.4** (la recomendada). Comprueba:
   - [ ] La lista de ramas sale con su estado de php.net (Estable, Solo seguridad, Sin soporte) y su último parche.
   - [ ] Se abre la ventana de tareas: barra azul gruesa, «NN % · quedan unos X», el reloj del tiempo que lleva, la lista de partes y la consola oscura. Las descargas avanzan **en la misma línea** (no una línea por cada trozo).
   - [ ] En la consola: «sha256 correcta» y «firma GPG correcta» de Apache Lounge (Steffen Land), MariaDB y phpMyAdmin; de PHP, solo la sha256 (y lo dice).
   - [ ] Pide UAC una vez para copiar los programas a `versiones\php-8.4.X`.
   - [ ] Al terminar, la fila de la 8.4 en la tabla, con su Apache, MariaDB y phpMyAdmin.
   - [ ] **Cancelar** a mitad de una descarga: se para, no queda `versiones\php-8.4.X.parcial` ni nada a medias, y se puede volver a instalar.
2. Instala también una antigua, por ejemplo **7.4**, y una **8.1**:
   - [ ] La 7.4 y la 8.1 salen como «Vulnerable (PHP2Shell)» en rojo, y al activarlas piden confirmación.
3. Comprueba la carpeta: `dir C:\NexumDevStack\versiones\php-8.4.*` debe tener `apache`, `php`, `mariadb` y `phpmyadmin`, y `C:\NexumDevStack\datos\php-8.4.*` las BBDD iniciales (`mysql`, `phpmyadmin`…).

## Paso 5: activar, arrancar y parar

1. **Activar** la 8.4 (o el menú de su fila). Comprueba:
   - [ ] El visor de arriba dice la 8.4 **en verde** (en marcha).
   - [ ] **Localhost** abre `http://localhost` en el navegador; `http://localhost/phpmyadmin` entra como root sin contraseña.
   - [ ] Crea `C:\NexumDevStack\htdocs\info.php` con `<?php phpinfo();`: `http://localhost/info.php` dice PHP 8.4.X, Server API «Apache 2.0 Handler», y extensiones curl, gd, intl, mbstring, mysqli, pdo_mysql, openssl, sodium, zip y opcache.
   - [ ] En el Administrador de tareas, `httpd.exe` y `mariadbd.exe` corren con **tu usuario** (columna «Nombre de usuario» en Detalles), no como administrador ni como SYSTEM.
   - [ ] **No se abre ninguna ventana de consola** de Apache o MariaDB.
   - [ ] Desde otro equipo de tu red, `http://<ip-de-este-equipo>` **no** responde.
   - [ ] En PowerShell: `netstat -ano | findstr ":80 :443 :3306"` solo muestra `127.0.0.1` y `[::1]`, nunca `0.0.0.0`.
2. **Parar**: el visor deja de estar en verde y en el Administrador de tareas no queda ningún `httpd.exe` ni `mariadbd.exe`.
3. **Arrancar** otra vez, y **Reiniciar**.
4. **Activar la 7.4** (con la 8.4 en marcha): para la 8.4, confirma lo de PHP2Shell y arranca la 7.4. `info.php` dice 7.4. Vuelve a la 8.4.
5. Cierra la ventana con la versión en marcha: Apache y MariaDB **siguen en marcha** (como en Linux). Vuelve a abrir el programa: el visor la ve en marcha.
6. Desde PowerShell:

   ```powershell
   cd <carpeta del exe>
   .\NexumDevStack.exe estado | Out-Default
   .\NexumDevStack.exe procesos | Out-Default
   .\NexumDevStack.exe parar | Out-Default
   .\NexumDevStack.exe arrancar | Out-Default
   .\NexumDevStack.exe --ayuda | Out-Default
   ```

   - [ ] Se ve la salida en la consola, con acentos y «ñ» bien, y PowerShell espera a que termine.

## Paso 6: bases de datos

1. **Bases de datos**: salen las de la versión activa con su tamaño.
2. Comprueba:
   - [ ] **Crear** `prueba`: sale en la lista y en phpMyAdmin.
   - [ ] **Subir** un `.sql`, un `.sql.gz` y un `.zip` (por ejemplo, el volcado de un WordPress): la barra dice «134 MB de 302 MB»; al terminar, las tablas están.
   - [ ] Subir un volcado con `DEFINER=` o con `USE otra_base;`: carga sin tocar otras BBDD (y lo dice en la consola).
   - [ ] **Descargar** una base como `.zip` y como `.sql.gz`: se abre bien y no tiene el usuario `local@local.test`.
   - [ ] **Copiar a otra versión** (a la 7.4): sale allí.
   - [ ] **Borrar** con copia: la copia queda en `%USERPROFILE%\nexum-copias`.
   - [ ] Con la versión parada, la página lo dice (arráncala arriba).

## Paso 7: proyectos y web.local

1. Copia a `C:\NexumDevStack\htdocs` un WordPress y, si tienes, una tienda PrestaShop (1.7 u 8), con sus volcados.
2. **Proyectos**:
   - [ ] Salen con su logotipo (WordPress, PrestaShop) y su BBDD.
   - [ ] **Cargar** el WordPress (elige la versión y la BBDD): pide UAC para `hosts` la primera vez. Después `https://web.local` abre el WordPress. Windows pregunta si confías en el certificado de `web.local`: **Sí**. Edge y Chrome lo abren sin aviso de certificado (Firefox necesita `security.enterprise_roots.enabled` en `about:config`).
   - [ ] **Panel** abre `wp-admin` con `local@local.test` / `local` ya escrito y entra.
   - [ ] **Abrir web**, **VS Code** (si está instalado), **phpMyAdmin** y **abrir carpeta** funcionan.
   - [ ] **Cargar** la tienda PrestaShop: falsea su dominio real en `hosts`, crea su vhost y su certificado, y `https://<dominio de la tienda>` la abre en local. **Vaciar caché** borra `var\cache`.
   - [ ] **Desmontar**: `web.local` deja de apuntar al proyecto y el dominio de la tienda deja de estar falseado.
   - [ ] Cancela una carga a mitad (o haz que falle, por ejemplo con la BBDD equivocada): todo queda como estaba (hosts, vhosts, la versión activa).
   - [ ] **Replicar** un proyecto en otra versión y **Vincular BBDD**.
   - [ ] **Nuevo**: crea la carpeta, con su dominio falseado si lo pides.
3. Comprueba `C:\Windows\System32\drivers\etc\hosts`: solo cambian las líneas de los dominios de Nexum (`web.local` y los falseados) y lo demás no se toca. Si Windows Defender avisa de que se cambió `hosts`, apúntalo (y si lo bloquea).

## Paso 8: dominios, configuración y seguridad

- [ ] **Dominios y hosts**: salen los dominios falseados, con su certificado (de confianza o no) y su vhost. Falsear y dejar de falsear funciona.
- [ ] **Configuración → editar vhosts**: cambia algo mal a propósito (una línea sin sentido) y aplica: debe decir que Apache no lo acepta y dejarlo como estaba. Un cambio bueno se aplica y Apache se reinicia.
- [ ] **Configuración → editar hosts**: aplicar un cambio pide UAC y se guarda.
- [ ] **Barrera entre webs**: con ella encendida, un `.php` de un proyecto no puede leer ficheros de otro proyecto (`file_get_contents('C:/NexumDevStack/htdocs/otro/wp-config.php')` falla); apagada, sí.
- [ ] `http://127.0.0.1` con un nombre que no es de ningún vhost (por ejemplo, añade `127.0.0.1 nadie.local` a hosts y abre `http://nadie.local`) no abre ningún proyecto.
- [ ] `http://web.local/.env`, `/.git/config` y `/copia.sql` dan 403.
- [ ] **Certificados → quitar**: desaparecen de la raíz de confianza de tu usuario (`certmgr.msc` → Entidades de certificación raíz de confianza → Certificados, los de «Nexum Dev Stack»).

## Paso 9: actualizar y desinstalar

- [ ] Si una versión no tiene el último parche, la tabla lo dice y **Actualizar a PHP X.Y.Z** instala la nueva al lado, le copia las BBDD con sus vínculos y la activa. La de antes queda intacta.
- [ ] **Desinstalar** la 8.1 con copia: pide UAC, borra `versiones\php-8.1.X` y `datos\php-8.1.X`, y deja la copia en `%USERPROFILE%\nexum-copias`. No deja desinstalar la activa.

## Lo que más puede fallar

Lo escribí con cuidado, pero nunca se ha ejecutado en Windows. Si falla, casi seguro es aquí:

1. **La ventana (WPF con barra de título propia):** maximizar, snap, bordes, escala de pantalla, colores de los desplegables y de las barras de desplazamiento en tema claro.
2. **Parar y reiniciar Apache** (`httpd -k shutdown` y `-k restart` sin servicio de Windows): que no pare o que deje procesos. Y que arranque sin abrir ventanas de consola.
3. **DLL de PHP** que choquen con las de Apache (OpenSSL, nghttp2, libcurl): Apache no arranca y `registros\php-X.Y.Z\apache-error.log` dice «Cannot load php8apache2_4.dll» o algo de un módulo.
4. **MariaDB:** que `mariadb-install-db` cree bien los datos iniciales y que se pare bien con `mariadb-admin shutdown`.
5. **Permisos (ACL)** de `C:\NexumDevStack` y la copia del programa en `programa`.
6. **El aviso de UAC:** que salga delante, que el programa reciba lo que hace la parte de administrador (la consola de la ventana de tareas) y que cancelar funcione.
7. **Certificados:** el aviso de Windows al añadirlos y quitarlos.
8. **hosts:** que Defender lo bloquee o avise.
9. **Puertos:** que diga bien quién usa el 80, 443 o 3306.
10. **El .exe de un solo archivo:** que tarde la primera vez o que un antivirus lo bloquee.
11. **Los comandos desde PowerShell o cmd:** que la salida se vea y que los acentos salgan bien.

## Qué mandarme

Cuando algo falle (o al terminar, aunque todo vaya bien), mándame:

1. Qué paso y qué casilla, lo que esperabas y lo que pasó, y **capturas** de la ventana (con el mensaje de error si lo hay).
2. Los registros, en un `.zip`:
   - `%LOCALAPPDATA%\NexumDevStack\registros\*.log`: las tareas de la ventana (`tarea-…-error.log`) y `ventana-errores.log` si existe.
   - `C:\NexumDevStack\tareas\*.log`: lo que hizo la parte de administrador.
   - `C:\NexumDevStack\registros\php-X.Y.Z\apache-error.log` y `mariadb.err` de la versión que falle.
3. La salida de:

   ```powershell
   .\NexumDevStack.exe estado | Out-Default
   .\NexumDevStack.exe procesos | Out-Default
   icacls C:\NexumDevStack; icacls C:\NexumDevStack\versiones
   netstat -ano | findstr ":80 :443 :3306"
   winver
   ```

En la ventana de tareas, **Guardar el registro** (o el botón de copiar) da todo lo que salió en la consola.
