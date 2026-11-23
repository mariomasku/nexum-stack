# Docker vacio: los proyectos de DOCKER_DIR cuyos datos ya no estan en Docker (el volumen de su BBDD: el
# suyo, en los de antes, o el de su MariaDB comun, en los del Apache de Docker) y las PostgreSQL comunes
# sin el suyo. Pasa si Docker cambia de almacen de imagenes (a containerd, o al reves: lo de antes sigue
# en el disco, pero no se ve) o si Docker Desktop empieza con un disco nuevo de su maquina virtual. Los
# que usan la BBDD de una version en vivo no cuentan (su BBDD no esta en Docker). Una linea por cada uno:
# <nombre>|<su ultima copia en ~/nexum-backups, o nada>. Sin respuesta de Docker: nada
function docker_lost() {
    local vols p v db
    vols=$(dk volume ls --format '{{.Name}}' 2> /dev/null) || return 0
    for p in $(docker_projects); do
        db=$(docker_conf "$p" BBDD)
        if docker_web_project "$p"; then
            [ -n "$(docker_conf "$p" LAMPP_BD)" ] && continue
            v=$(docker_maria_name "$(docker_conf "$p" MARIADB)")
        else
            v=nexum-${p}_db
        fi
        grep -qxF "$v" <<< "$vols" && continue
        echo "$p|$(docker_last_copy "docker-$p-$db")"
    done
    for v in $(docker_pg_versions); do
        grep -qxF "$(docker_pg_name "$v")" <<< "$vols" || echo "postgres-$v|$(docker_last_copy "docker-postgres-$v")"
    done
    return 0
}

# La copia mas reciente de ~/nexum-backups que empieza por <prefijo> y sigue con su fecha (-AAAAMMDD-HHMMSS)
function docker_last_copy() {
    local f best="" key bkey=""
    for f in "$COPIES_DIR/$1"-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].sql.gz; do
        [ -f "$f" ] && [ ! -L "$f" ] || continue
        key=${f%.sql.gz}
        key=${key: -15}
        [[ "$key" > "$bkey" ]] && { best=$f; bkey=$key; }
    done
    [ -n "$best" ] && echo "$best"
    return 0
}

# docker-copia: una copia de todas las BBDD de Docker en ~/nexum-backups, para poder volver a cargarlas
# (docker-recuperar): la de cada proyecto (docker_db_backup), las que hay en las MariaDB comunes sin
# ningun proyecto, y cada PostgreSQL comun entera (pg_dumpall). La hacen componentes-actualizar antes de
# poner Docker al dia y la ventana antes de que actualices Docker Desktop. Lo de un proyecto que ya no
# esta en Docker (docker_lost) no se puede copiar: se dice y se sigue. Si falla alguna, devuelve error
function docker_backup_all() {
    local why=${1:-no se sigue} p lost v db fail=0 n=0 name stamp out skip log
    [ "$DRY" -eq 1 ] && { echo "  [simulacion] copia de todas las BBDD de Docker en ~/nexum-backups"; return 0; }
    docker_ready || { echo "Docker no responde: no se puede hacer la copia de sus BBDD"; return 1; }
    mkdir -p -m 700 "$COPIES_DIR" || return 1
    lost=" $(docker_lost | cut -d'|' -f1 | tr '\n' ' ') "
    stamp=$(date +%Y%m%d-%H%M%S)
    log=$(mktemp "$LOG_DIR/docker-copia-XXXXXX") || return 1
    echo "Copia de las BBDD de Docker en $COPIES_DIR"
    for p in $(docker_projects); do
        if [[ "$lost" == *" $p "* ]]; then
            echo "$p: su BBDD ya no está en Docker, no hay nada que copiar (recupérala con docker-recuperar)"
            continue
        fi
        n=$((n + 1))
        ( docker_db_backup "$p" ) > "$log" 2>&1
        if [ $? -ne 0 ]; then
            sed "s/: no se borra nada$/: $why/" "$log"
            fail=1
        else
            sed -n 's/^Copia de [^(]*: /  /p; s/ no tiene BBDD propia en Docker.*/: con la BBDD de su versión, en vivo (no está en Docker)/p' "$log"
        fi
    done
    rm -f "$log"
    # (lo de las MariaDB comunes que no es de ningun proyecto: una BBDD creada a mano, la de uno ya borrado...)
    for v in $(docker_maria_versions); do
        dk volume inspect "$(docker_maria_name "$v")" > /dev/null 2>&1 || continue
        docker_maria_up "$v" > /dev/null || { echo "La MariaDB $v de Docker no responde: $why"; fail=1; continue; }
        skip=" information_schema mysql performance_schema sys "
        for p in $(docker_web_projects); do
            [ "$(docker_conf "$p" MARIADB)" == "$v" ] || continue
            skip+="$(docker_conf "$p" BBDD) $(docker_conf "$p" BBDD_DOCKER) "
        done
        for db in $(docker_maria_sql "$v" -N -e "SHOW DATABASES" < /dev/null 2> /dev/null); do
            [[ "$skip" == *" $db "* ]] && continue
            db_valid_name "$db" > /dev/null || continue
            n=$((n + 1))
            out="$COPIES_DIR/docker-mariadb-$v-$db-$stamp.sql.gz"
            ( umask 077
              set -o pipefail
              dk exec -i "$(docker_maria_name "$v")" sh -c 'MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb-dump || command -v mysqldump) -uroot --single-transaction --routines --triggers --events "$0"' "$db" \
                  < /dev/null | gzip > "$out" )
            if [ $? -ne 0 ] || [ "$(gzip -dc "$out" 2> /dev/null | head -c 4096 | wc -c)" -lt 100 ]; then
                rm -f "$out"
                echo "No se ha podido copiar $db de la MariaDB $v de Docker: $why"
                fail=1
            else
                echo "  $out"
            fi
        done
    done
    for v in $(docker_pg_versions); do
        name=$(docker_pg_name "$v")
        [[ "$lost" == *" postgres-$v "* ]] && { echo "PostgreSQL $v: sus BBDD ya no están en Docker, no hay nada que copiar"; continue; }
        docker_pg_up "$v" > /dev/null || { echo "La PostgreSQL $v de Docker no responde: $why"; fail=1; continue; }
        n=$((n + 1))
        out="$COPIES_DIR/docker-postgres-$v-$stamp.sql.gz"
        ( umask 077
          set -o pipefail
          dk exec "$name" pg_dumpall -U postgres < /dev/null | gzip > "$out" )
        if [ $? -ne 0 ] || [ "$(gzip -dc "$out" 2> /dev/null | head -c 4096 | wc -c)" -lt 100 ]; then
            rm -f "$out"
            echo "No se ha podido copiar la PostgreSQL $v de Docker: $why"
            fail=1
        else
            echo "  $out"
        fi
    done
    [ $n -eq 0 ] && echo "  No hay ninguna BBDD en Docker que copiar"
    [ $fail -eq 0 ] && echo "Copia de las BBDD de Docker hecha."
    return $fail
}

# Espera a que la MariaDB de un proyecto de los de antes acepte conexiones de verdad (no la temporal con
# la que la imagen prepara una BBDD nueva, sin red: healthcheck.sh --connect va por la red)
function docker_db_wait() {
    local dir=$DOCKER_DIR/$1 i
    for i in $(seq 120); do
        dk compose --project-directory "$dir" -f "$dir/compose.yaml" exec -T db sh -c \
            'if command -v healthcheck.sh > /dev/null; then healthcheck.sh --connect --innodb_initialized; else MYSQL_PWD=$MARIADB_ROOT_PASSWORD $(command -v mariadb || command -v mysql) -uroot -h 127.0.0.1 -e "SELECT 1"; fi' \
            < /dev/null > /dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

# docker-recuperar [nombre...]: lo que docker_lost dice que ya no esta en Docker (o solo esos), de nuevo:
# sus imagenes de PHP, sus contenedores y su BBDD (vacia, con su usuario y su contraseña de siempre) y,
# si hay, su ultima copia de ~/nexum-backups cargada en ella. Las PostgreSQL comunes, igual (con su
# ultima copia entera). Lo que no tiene copia se queda con la BBDD vacia, y se dice
function docker_recover() {
    local lost line p copy want=" $* " v db user pass dir fail=0 n=0 f maria
    docker_ready || { echo "Docker no responde: arráncalo y vuelve a probar"; return 1; }
    lost=$(docker_lost)
    if [ -z "$lost" ]; then
        echo "No falta nada: los proyectos de Docker tienen sus BBDD."
        return 0
    fi
    while IFS='|' read -r p copy; do
        [ -n "$p" ] || continue
        [ $# -gt 0 ] && [[ "$want" != *" $p "* ]] && continue
        n=$((n + 1))
        echo ""
        echo "== $p =="
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] contenedores de nuevo${copy:+ y carga de $copy}"
            continue
        fi
        if [[ "$p" =~ ^postgres-([0-9]+)$ ]]; then
            v=${BASH_REMATCH[1]}
            docker_pg_up "$v" || { fail=1; continue; }
            if [ -n "$copy" ]; then
                echo "Cargando $copy"
                gzip -dc "$copy" | dk exec -i "$(docker_pg_name "$v")" psql -U postgres -q -d postgres > /dev/null \
                    || echo "Aviso: la carga ha dado errores (los de los usuarios que ya estaban no importan)"
            else
                echo "No hay ninguna copia suya en $COPIES_DIR: la PostgreSQL $v empieza vacía"
            fi
            continue
        fi
        db=$(docker_conf "$p" BBDD) dir=$DOCKER_DIR/$p
        for v in $(docker_conf "$p" PHP); do
            docker_php_image "$v" || { echo "No se ha podido preparar la imagen de PHP $v"; fail=1; continue 2; }
        done
        if docker_web_project "$p"; then
            maria=$(docker_conf "$p" MARIADB) user=$(docker_conf "$p" USUARIO)
            pass=$(sed -n 's/^DB_PASS=//p' "$dir/.env" 2> /dev/null | head -1)
            if ! db_valid_name "$db" > /dev/null || ! [[ "$user" =~ ^[A-Za-z0-9_]{1,32}$ ]] || [ -z "$pass" ]; then
                echo "$p: no se encuentran su BBDD, su usuario o su contraseña en $dir"
                fail=1
                continue
            fi
            docker_maria_up "$maria" || { fail=1; continue; }
            printf 'CREATE DATABASE IF NOT EXISTS `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;\nCREATE USER IF NOT EXISTS '"'"'%s'"'"'@'"'"'%%'"'"' IDENTIFIED BY '"'"'%s'"'"';\nGRANT ALL PRIVILEGES ON `%s`.* TO '"'"'%s'"'"'@'"'"'%%'"'"';\n' \
                "$db" "$user" "$pass" "$db" "$user" | docker_maria_sql "$maria" || { fail=1; continue; }
            if [ -n "$copy" ]; then
                echo "Cargando $copy en $db"
                gzip -dc "$copy" | docker_maria_sql "$maria" --binary-mode "$db" \
                    || { echo "Aviso: la carga de la BBDD ha dado errores (mira lo de arriba)"; fail=1; }
            fi
            # (lo que habia en esa MariaDB comun sin ningun proyecto, con su ultima copia)
            for f in "$COPIES_DIR/docker-mariadb-$maria-"*.sql.gz; do
                [ -f "$f" ] || continue
                v=${f#"$COPIES_DIR/docker-mariadb-$maria-"}
                v=${v%-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].sql.gz}
                db_valid_name "$v" > /dev/null || continue
                [ -n "$(docker_maria_sql "$maria" -N -e "SHOW DATABASES LIKE '$v'" < /dev/null 2> /dev/null)" ] && continue
                f=$(docker_last_copy "docker-mariadb-$maria-$v")
                echo "Cargando $f en $v (de la MariaDB $maria, sin proyecto)"
                printf 'CREATE DATABASE `%s`;\n' "$v" | docker_maria_sql "$maria" \
                    && gzip -dc "$f" | docker_maria_sql "$maria" --binary-mode "$v" || echo "Aviso: la carga de $v ha dado errores"
            done
            docker_action arrancar "$p" || fail=1
        else
            docker_action arrancar "$p" || { fail=1; continue; }
            if [ -n "$copy" ]; then
                docker_db_wait "$p" || { echo "$p: su MariaDB de Docker no responde"; fail=1; continue; }
                echo "Cargando $copy en $db"
                gzip -dc "$copy" | dk compose --project-directory "$dir" -f "$dir/compose.yaml" exec -T db sh -c \
                    'MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb || command -v mysql) -uroot --binary-mode "$0"' "$db" \
                    || { echo "Aviso: la carga de la BBDD ha dado errores (mira lo de arriba)"; fail=1; }
            fi
        fi
        [ -z "$copy" ] && echo "No hay ninguna copia suya en $COPIES_DIR: su BBDD empieza vacía (cárgale una con «Subir BBDD»)"
    done <<< "$lost"
    echo ""
    [ $n -eq 0 ] && { echo "Ninguno de esos ha perdido su BBDD."; return 0; }
    [ $fail -eq 0 ] && echo "Recuperado: $n." || echo "Algo no se ha podido recuperar: mira lo de arriba."
    return $fail
}
