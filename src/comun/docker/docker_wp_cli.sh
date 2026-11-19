# WP-CLI dentro de las imagenes de PHP del gestor (nexum-php:<version>), para ejecutar wp contra la BBDD
# del contenedor con su wp-config (docker exec <contenedor> wp ... --path=<carpeta del proyecto>). Es una
# opcion de Configuracion > Docker, apagada de serie: la imagen de una version de PHP es la misma para
# todos sus proyectos. Puesta, existe $DOCKER_DIR/wp-cli. Fijado por su huella (la del .phar de la
# publicacion de GitHub): si alguien cambiara ese fichero, la imagen no se construye. Para otra
# version: su .phar.sha256 de github.com/wp-cli/wp-cli/releases
WP_CLI_VERSION=2.12.0
WP_CLI_SHA256=ce34ddd838f7351d6759068d09793f26755463b4a4610a5a5c0a97b68220d85c

# ¿Esta puesta la opcion?
function docker_wp_cli_on() {
    [ -f "$DOCKER_DIR/wp-cli" ]
}

# Las lineas del Dockerfile que lo instalan, con su etiqueta (nada con la opcion quitada). wp corre como
# el root del contenedor (en Docker sin root de Linux, tu usuario), asi que va con --allow-root; y sin
# los avisos de lo obsoleto (con PHP 8.5, la 2.12 avisa de lo suyo en cada orden)
function docker_wp_cli_dockerfile() {
    docker_wp_cli_on || return 0
    printf 'LABEL nexum.wp-cli="%s"\n' "$WP_CLI_VERSION"
    printf 'RUN curl -q --proto =https -fsSL -o /usr/local/lib/wp-cli.phar https://github.com/wp-cli/wp-cli/releases/download/v%s/wp-cli-%s.phar \\\n' "$WP_CLI_VERSION" "$WP_CLI_VERSION"
    printf ' && echo "%s  /usr/local/lib/wp-cli.phar" | sha256sum -c - \\\n' "$WP_CLI_SHA256"
    # shellcheck disable=SC2016
    printf ' && printf '\''#!/bin/sh\\nexec php -d error_reporting=8191 /usr/local/lib/wp-cli.phar --allow-root "$@"\\n'\'' > /usr/local/bin/wp \\\n'
    printf ' && chmod 755 /usr/local/bin/wp\n'
}

# ¿La imagen de PHP <version> del gestor ya trae este WP-CLI? (sin la imagen: no)
function docker_php_has_wp_cli() {
    [ "$(dk image inspect --format '{{index .Config.Labels "nexum.wp-cli"}}' "nexum-php:$1" 2> /dev/null)" == "$WP_CLI_VERSION" ]
}

# ¿Le falta WP-CLI a la imagen <version>, con la opcion puesta? (quitada, la que lo trae sigue valiendo
# hasta que se rehaga)
function docker_php_needs_wp_cli() {
    docker_wp_cli_on && ! docker_php_has_wp_cli "$1"
}

# docker-wp-cli si|no [--rehacer]: pone o quita la opcion. Con --rehacer, rehace ya las imagenes de PHP
# que hay (con lo que ya tienen descargado: solo cambia WP-CLI) y vuelve a crear los contenedores en
# marcha de sus proyectos; sin el, cada imagen cambia la proxima vez que se rehaga
function docker_wp_cli_command() {
    local want=$1 v slug dir running vs=() steps=() fail=0
    case $want in
        si|no) ;;
        *) echo "Uso: nexum docker-wp-cli si|no [--rehacer]"; return 1 ;;
    esac
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] WP-CLI en las imagenes de PHP de Docker: $want${2:+, y se rehacen ya}"
        return 0
    fi
    mkdir -p -m 700 "$DOCKER_DIR" || return 1
    if [ "$want" == si ]; then
        : > "$DOCKER_DIR/wp-cli" || return 1
        echo "WP-CLI en las imagenes de PHP de Docker: puesto (wp $WP_CLI_VERSION)"
    else
        rm -f "$DOCKER_DIR/wp-cli" || return 1
        echo "WP-CLI en las imagenes de PHP de Docker: quitado"
    fi
    if [ "$2" != --rehacer ]; then
        echo "Cada imagen de PHP cambia la proxima vez que se rehaga (Componentes o Actualizar la imagen)"
        return 0
    fi
    docker_ready > /dev/null 2>&1 || { echo "Docker no esta en marcha: las imagenes cambian la proxima vez que se rehagan"; return 1; }
    for v in $DOCKER_PHP_VERSIONS; do
        dk image inspect "nexum-php:$v" > /dev/null 2>&1 || continue
        # (solo las que no estan ya como se quiere)
        if [ "$want" == si ]; then docker_php_has_wp_cli "$v" && continue
        else [ -z "$(dk image inspect --format '{{index .Config.Labels "nexum.wp-cli"}}' "nexum-php:$v" 2> /dev/null)" ] && continue
        fi
        vs+=("$v")
        steps+=("Imagen de PHP $v")
    done
    if [ ${#vs[@]} -eq 0 ]; then
        echo "Las imagenes de PHP de Docker ya estan asi: nada que rehacer"
        return 0
    fi
    steps+=("Volver a crear los contenedores en marcha")
    task_plan "WP-CLI en las imágenes de PHP" "${steps[@]}"
    for v in "${vs[@]}"; do
        task_step
        docker_php_image "$v" --rehacer || { echo "No se ha podido rehacer la imagen de PHP $v: sigue con la anterior"; fail=1; }
    done
    task_step
    for slug in $(docker_projects); do
        dir=$DOCKER_DIR/$slug
        running=$(dk ps --filter "label=com.docker.compose.project=nexum-$slug" --format '{{.Label "com.docker.compose.service"}}' 2> /dev/null)
        [ -n "$running" ] || continue
        # shellcheck disable=SC2086
        dk compose --project-directory "$dir" -f "$dir/compose.yaml" up -d $running > /dev/null || fail=1
    done
    dk image prune -f > /dev/null 2>&1
    [ $fail -eq 0 ] && echo "Listo: las imagenes de PHP de Docker $([ "$want" == si ] && echo "traen WP-CLI" || echo "ya no traen WP-CLI")"
    return $fail
}
