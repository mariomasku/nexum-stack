# Fuentes de Nexum Dev Stack

Los dos scripts que se instalan y se publican, `lvm-instalador.sh` (Linux) y `macos/lvm-instalador.sh` (Mac), siguen siendo un solo fichero cada uno. Desde la 1.57.5 **se editan aquí, en `src/`**, y se construyen con `./construir.sh`.

## Qué hay

| Carpeta | Qué es | Va dentro de |
|---|---|---|
| `linux/bash/NN-*.sh` | El bash de Linux, una sección por fichero, en el orden de su número | `lvm-instalador.sh` |
| `linux/ventana/NN-*.py` | La ventana de Linux (Python con GTK 3), un fichero por apartado (desde la 1.57.6) | heredoc `LVM_GUI_PY` (sección `25-…`) |
| `linux/tunel.py` | El proxy del túnel de Cloudflare | heredoc `PYEOF` (sección `24-…`) |
| `mac/bash/NN-*.sh` | El bash del Mac, igual | `macos/lvm-instalador.sh` |
| `mac/ventana.swift` | La ventana del Mac (SwiftUI) | heredoc `LVM_SWIFT` (sección `23-accesos`) |
| `mac/tunel.py` | El proxy del túnel en el Mac | heredoc `PYEOF` (sección `28-…`) |
| `comun/<sección>/<función>.sh` | Funciones que son **iguales en Linux y en Mac**, una sola vez (desde la 1.57.6) | los dos scripts, cada una en su sitio |

En el bash, la línea `#@incluir ventana/` (dentro de su heredoc) es donde van los ficheros de esa carpeta, juntos y en el orden de su número, y `#@incluir comun/…` es donde van esas funciones comunes.

## La ventana de Linux (`linux/ventana/`)

Cada fichero es un apartado, por orden:

- **`01` a `04`:** lo de todo el programa: el arranque y los ajustes, las piezas de la interfaz (filas, tarjetas, logotipos), las llamadas al script (`gui-*`) y las tareas con su contraseña.
- **`05` a `15`:** la ventana base (`App`). Cada apartado es una clase pequeña (`AppServicios`, `AppVersiones`...), y `15-app.py` las junta en `App`.
- **`16` a `27`:** la ventana de ahora (`App2`, desde la 1.54), montada sobre la base. `16-nv-estilos.py` lleva sus colores y su CSS, cada apartado es una clase (`NvProyectos`, `NvDocker`...) y `27-nv-ventana.py` las junta en `App2`.
- **`28` y `29`:** la tipografía del logotipo y la línea que abre la ventana.

**Un método nuevo va en la clase de su apartado.** Si es de la ventana de ahora y cambia uno de la base con el mismo nombre, va en su clase `Nv…`, que manda sobre la base. Para ruff y las pruebas se junta entera con `./construir.sh --ventana <fichero>`. Se repartió (1.57.6) comprobando que los 530 métodos que usa la ventana son, compilados, exactamente los mismos que antes.

## Lo común a Linux y Mac (`comun/`)

Cada fichero es un tramo de funciones enteras (con sus comentarios) que está igual, y en el mismo orden, en los dos sistemas. Su nombre es el de su sección y el de su primera función: `comun/repositorios-github/github_command.sh` lleva `github_command` y las que la siguen.

- **Se cambia una vez y vale para los dos.** Es lo que se busca: que un arreglo no se quede en un solo sistema.
- **Si una función común tiene que ser distinta en un sistema:** se copia el tramo de vuelta a la sección de cada sistema (donde está su `#@incluir comun/…`), se borra de `comun/` y se cambia donde haga falta.
- `construir.sh` falla si un fichero de `comun/` no se incluye en los dos sistemas.

## Cómo se trabaja

1. Se edita en `src/`: la ventana en `linux/ventana/` o `ventana.swift`, y el bash en su sección.
2. `./construir.sh` rehace los dos scripts. Sin cambios, no los toca.
3. Las pruebas (`pruebas/todas.sh`), el paquete y `publicar.sh` usan los scripts construidos, como siempre.
4. Se hace commit de los dos: `src/` y los scripts construidos.

**Los scripts construidos no se editan a mano.** `./construir.sh --comprobar` falla si no son los de `src/`, y lo comprueban las pruebas (`pruebas/fuentes.sh`), `publicar.sh` y GitHub en cada envío.

## Por qué así

- **Herramientas:** el Python y el Swift son ficheros normales, así que el editor, el revisor de Python o `swiftc` los entienden. Metidos en un heredoc de 35.000 líneas de bash, ninguna herramienta podía.
- **Lo que se instala no cambia:** sigue siendo un solo fichero, con la misma firma y la misma forma de actualizarse.
- **Comprobado:** la primera vez se separó de forma que, al construir, los dos scripts salen idénticos byte a byte a los de la 1.57.5 publicada.

En `comun/` está, de momento, lo que ya era idéntico (147 funciones, unas 3.500 líneas). Lo casi igual (otras 75 funciones, que cambian en rutas como `/opt/lampp` y `/Library/Nexum` o en nombres como `lampp-` y `XAMPP-`) sigue en cada sistema: juntarlo pide cambiar código, con sus pruebas, y se irá haciendo por partes.
