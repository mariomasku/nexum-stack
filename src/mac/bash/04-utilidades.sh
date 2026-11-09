# ===========================================================================
# Utilidades (macOS no tiene sort -V, md5sum ni sha256sum)
# ===========================================================================

# Ordena versiones (1.3.9 < 1.3.9a < 1.3.10) y quita repetidas
function vsort() {
    python3 -I -c 'import re, sys
items = {line.strip() for line in sys.stdin if line.strip()}
key = lambda s: [(0, int(p)) if p.isdigit() else (1, p) for p in re.findall(r"\d+|[a-z]+", s)]
print("\n".join(sorted(items, key=key)))'
}

function sha256_of() {
    shasum -a 256 "$1" | cut -d' ' -f1
}

# Procesos de compilacion: uno por nucleo, pero como mucho uno por cada 1,5 GB de memoria, para
# que un Mac de 8 GB no se quede sin memoria compilando MariaDB
function cpu_count() {
    local cpus=$(sysctl -n hw.ncpu 2> /dev/null || echo 4)
    local mem=$(sysctl -n hw.memsize 2> /dev/null || echo 0)
    local by_mem=$(( mem / 1610612736 ))

    (( by_mem > 0 && by_mem < cpus )) && cpus=$by_mem
    (( cpus < 1 )) && cpus=1
    echo $cpus
}

