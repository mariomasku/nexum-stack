# docker-borrar <nombre> --copia: antes de borrar el proyecto, una copia de su BBDD de Docker en
# ~/nexum-backups (docker-<nombre>-<bbdd>-<fecha>.sql.gz, se puede volver a cargar con importar-bd), con un
# volcado de su MariaDB de Docker: la comun de su version, en los del Apache de Docker, o la suya, en los
# de antes. Con la BBDD en vivo de una version (sin copia en Docker), no hay nada que copiar. Si la copia
# falla, devuelve error: entonces no se borra nada
function docker_db_backup() {
    local slug=$1 dir=$DOCKER_DIR/$1 db maria backup i cl
    local c=(dk compose --project-directory "$dir" -f "$dir/compose.yaml")
    local dump='MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb-dump || command -v mysqldump) -uroot --single-transaction --routines --triggers --events "$0"'
    db=$(docker_conf "$slug" BBDD)
    docker_web_project "$slug" && [ -n "$(docker_conf "$slug" LAMPP_BD)" ] && db=$(docker_conf "$slug" BBDD_DOCKER)
    if ! db_valid_name "$db" > /dev/null; then
        echo "$slug no tiene BBDD propia en Docker: no hay nada que copiar"
        return 0
    fi
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] copia de $db (la de Docker) en ~/nexum-backups"
        return 0
    fi
    echo "Copia de su BBDD de Docker ($db)"
    if docker_web_project "$slug"; then
        maria=$(docker_conf "$slug" MARIADB)
        docker_maria_up "$maria" > /dev/null || { echo "La MariaDB $maria de Docker no responde: no se borra nada"; return 1; }
        cl=(dk exec -i "$(docker_maria_name "$maria")")
    else
        "${c[@]}" up -d db > /dev/null || { echo "No se ha podido arrancar su MariaDB de Docker: no se borra nada"; return 1; }
        for i in $(seq 60); do
            "${c[@]}" exec -T db sh -c 'MYSQL_PWD=$MARIADB_ROOT_PASSWORD exec $(command -v mariadb || command -v mysql) -uroot -e "SELECT 1"' \
                < /dev/null > /dev/null 2>&1 && break
            sleep 1
        done
        cl=("${c[@]}" exec -T db)
    fi
    mkdir -p -m 700 "$COPIES_DIR" || return 1
    backup="$COPIES_DIR/docker-$slug-$db-$(date +%Y%m%d-%H%M%S).sql.gz"
    ( umask 077
      set -o pipefail
      "${cl[@]}" sh -c "$dump" "$db" < /dev/null | gzip > "$backup" )
    if [ $? -ne 0 ] || [ "$(gzip -dc "$backup" 2> /dev/null | head -c 4096 | wc -c)" -lt 100 ]; then
        echo "No se ha podido copiar su BBDD de Docker ($db): no se borra nada"
        rm -f "$backup"
        return 1
    fi
    echo "Copia de $db: $backup"
}
