# Fuentes de Nexum Dev Stack

Los dos scripts que se instalan y se publican, `lvm-instalador.sh` (Linux) y `macos/lvm-instalador.sh` (Mac), siguen siendo un solo fichero cada uno. Desde la 1.57.5 **se editan aquí, en `src/`**, y se construyen con `./construir.sh`.

## Qué hay

| Carpeta | Qué es | Va dentro de |
|---|---|---|
| `linux/bash/NN-*.sh` | El bash de Linux, una sección por fichero, en el orden de su número | `lvm-instalador.sh` |
| `linux/ventana.py` | La ventana de Linux (Python con GTK 3) | heredoc `LVM_GUI_PY` (sección `25-…`) |
| `linux/tunel.py` | El proxy del túnel de Cloudflare | heredoc `PYEOF` (sección `24-…`) |
| `mac/bash/NN-*.sh` | El bash del Mac, igual | `macos/lvm-instalador.sh` |
| `mac/ventana.swift` | La ventana del Mac (SwiftUI) | heredoc `LVM_SWIFT` (sección `23-accesos`) |
| `mac/tunel.py` | El proxy del túnel en el Mac | heredoc `PYEOF` (sección `28-…`) |

En el bash, la línea `#@incluir ventana.py` (dentro de su heredoc) es donde va ese fichero entero.

## Cómo se trabaja

1. Se edita en `src/`: la ventana en `ventana.py` o `ventana.swift`, y el bash en su sección.
2. `./construir.sh` rehace los dos scripts. Sin cambios, no los toca.
3. Las pruebas (`pruebas/todas.sh`), el paquete y `publicar.sh` usan los scripts construidos, como siempre.
4. Se hace commit de los dos: `src/` y los scripts construidos.

**Los scripts construidos no se editan a mano.** `./construir.sh --comprobar` falla si no son los de `src/`, y lo comprueban las pruebas (`pruebas/fuentes.sh`), `publicar.sh` y GitHub en cada envío.

## Por qué así

- **Herramientas:** el Python y el Swift son ficheros normales, así que el editor, el revisor de Python o `swiftc` los entienden. Metidos en un heredoc de 35.000 líneas de bash, ninguna herramienta podía.
- **Lo que se instala no cambia:** sigue siendo un solo fichero, con la misma firma y la misma forma de actualizarse.
- **Comprobado:** la primera vez se separó de forma que, al construir, los dos scripts salen idénticos byte a byte a los de la 1.57.5 publicada.

Lo común a Linux y Mac sigue repetido en `linux/bash` y `mac/bash`. Juntarlo es el paso siguiente del mantenimiento.
