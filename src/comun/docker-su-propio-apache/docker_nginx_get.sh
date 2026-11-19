# Nginx de Docker (Configuración > Docker, 1.57.39): uno común, al lado del Apache de Docker, para los
# proyectos de Docker que le añadas. En la misma dirección y con los mismos dominios que el Apache de
# Docker (<proyecto>-php83.docker.local), en sus puertos (8081 y 8444 de serie: los de la pestaña Nginx
# son el 8080 y el 8443), y con el PHP del contenedor de cada versión del proyecto
# (DOCKER_NGINX_FASTCGI=1: por FastCGI, su puerto 9000; 0, el Mac: a su Apache). Imagen oficial, fijada
DOCKER_NGINX_IMAGE="nginx:1.30.7-alpine@sha256:bef154735288bc38d99fac41ae63730684bcc661503673a04a0f9bc526ba8598"
DOCKER_NGINX_DIR=$DOCKER_DIR/nginx
DOCKER_NGINX_FILE=$DOCKER_DIR/nginx.conf

# docker_nginx_get HTTP|HTTPS: sus puertos (de nginx.conf, o los de serie)
function docker_nginx_get() {
    local v="" def=8081
    [ "$1" == HTTPS ] && def=8444
    [ -f "$DOCKER_NGINX_FILE" ] && v=$(sed -n "s/^$1=//p" "$DOCKER_NGINX_FILE" | tail -1)
    if [[ "$v" =~ ^[1-9][0-9]{3,4}$ ]] && [ "$v" -le 65535 ]; then echo "$v"; else echo "$def"; fi
}

# Los proyectos de Docker (del Apache de Docker) que van también por el Nginx de Docker
function docker_nginx_projects() {
    local p
    for p in $(docker_web_projects); do
        [ "$(docker_conf "$p" NGINX)" == 1 ] && echo "$p"
    done
    return 0
}

function docker_nginx_state() {
    local s
    s=$(dk ps -a --filter name='^nexum-nginx$' --format '{{.State}}' 2> /dev/null | head -1)
    case $s in running) echo marcha ;; "") echo nuevo ;; *) echo parado ;; esac
}

# La dirección de un dominio de Docker por el Nginx de Docker
function docker_nginx_url() {
    echo "https://$1:$(docker_nginx_get HTTPS)"
}

# Un proyecto en el Nginx de Docker: cada versión de PHP (en una tienda, la elegida), por su dominio
function docker_nginx_site() {
    local slug=$1 folder versions v dom c
    folder=$(docker_conf "$slug" CARPETA)
    versions=$(docker_conf "$slug" PHP)
    [ "$(docker_conf "$slug" TIPO)" == ps ] && versions=$(docker_conf "$slug" ACTIVA)
    for v in $versions; do
        dom=$(docker_web_domain "$slug" "$v") c=$(docker_web_container "$slug" "$v")
        printf '    # %s (%s), PHP %s\n    server {\n        listen 80;\n        listen 443 ssl;\n        http2 on;\n' "$slug" "$folder" "$v"
        printf '        server_name %s;\n        ssl_certificate /certs/docker.local.crt;\n        ssl_certificate_key /certs/docker.local.key;\n' "$dom"
        printf '        root "/opt/lampp/htdocs/%s";\n        index index.php index.html;\n' "$folder"
        printf '        location ~ /\\.(?!well-known/) { deny all; }\n        location ~ ^/(vendor|node_modules)/ { deny all; }\n'
        # (con su PHP parado, lo dice en vez de un error sin mas; el nombre del contenedor, al llegar cada visita)
        printf '        error_page 502 504 = @parado;\n        location @parado { default_type text/plain; return 503 "%s"; }\n' "$DOCKER_STOPPED_MSG"
        if [ "${DOCKER_NGINX_FASTCGI:-1}" == 1 ]; then
            printf '        location / { try_files $uri $uri/ /index.php?$query_string; }\n'
            printf '        location ~ [^/]\\.php(/|$) {\n            fastcgi_split_path_info ^(.+?\\.php)(/.*)$;\n            try_files $fastcgi_script_name =404;\n'
            printf '            include /etc/nginx/fastcgi_params;\n            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\n'
            printf '            fastcgi_param PATH_INFO $fastcgi_path_info;\n            fastcgi_param HTTPS $https if_not_empty;\n'
            printf '            fastcgi_read_timeout 300;\n            set $php %s:9000;\n            fastcgi_pass $php;\n        }\n    }\n' "$c"
        else
            printf '        location / {\n            set $php http://%s;\n            proxy_pass $php;\n            proxy_set_header Host $host;\n' "$c"
            printf '            proxy_set_header X-Forwarded-Proto $scheme;\n            proxy_set_header X-Forwarded-For $remote_addr;\n'
            printf '            proxy_read_timeout 300;\n        }\n    }\n'
        fi
    done
}

# Su configuración (nginx/conf/nginx.conf) y su compose.yaml, en ficheros solo tuyos
function docker_nginx_write() {
    local d=$DOCKER_NGINX_DIR p
    [ "$DRY" -eq 1 ] && return 0
    mkdir -p -m 700 "$DOCKER_DIR" "$d" "$d/conf" || return 1
    {
        cat << 'EOF'
# Nginx de Docker de Nexum Dev Stack (se rehace solo: no se edita a mano)
worker_processes 1;
error_log /dev/stderr warn;
pid /tmp/nginx.pid;
events { worker_connections 256; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log off;
    sendfile on;
    server_tokens off;
    client_max_body_size 256m;
    # (el DNS de Docker: el contenedor de PHP de cada proyecto, al llegar la visita, aunque esté parado al arrancar)
    resolver 127.0.0.11 valid=10s ipv6=off;
    resolver_timeout 3s;
    # (un PHP recién parado no contesta: el aviso de parado a los 5 segundos, no al minuto)
    fastcgi_connect_timeout 5s;
    proxy_connect_timeout 5s;
    # Los dominios sin ningún proyecto en el Nginx de Docker, sin respuesta
    server {
        listen 80 default_server;
        listen 443 ssl default_server;
        ssl_reject_handshake on;
        return 444;
    }
EOF
        for p in $(docker_nginx_projects); do
            docker_nginx_site "$p"
        done
        echo "}"
    } > "$d/conf/nginx.conf.nuevo" || return 1
    chmod 600 "$d/conf/nginx.conf.nuevo" && mv -f "$d/conf/nginx.conf.nuevo" "$d/conf/nginx.conf" || return 1
    { printf 'name: nexum-nginx\nservices:\n  nginx:\n    image: %s\n    container_name: nexum-nginx\n    restart: "no"\n' "$DOCKER_NGINX_IMAGE"
      printf '    ports:\n      - "%s:%s:80"\n      - "%s:%s:443"\n' "$(docker_web_get IP)" "$(docker_nginx_get HTTP)" "$(docker_web_get IP)" "$(docker_nginx_get HTTPS)"
      printf '    volumes:\n      - "%s:/opt/lampp/htdocs:ro"\n      - "./conf:/etc/nginx/nexum:ro"\n      - "%s/certs:/certs:ro"\n' "$HTDOCS_DIR" "$DOCKER_WEB_DIR"
      printf '    command: ["nginx", "-g", "daemon off;", "-c", "/etc/nginx/nexum/nginx.conf"]\n    networks: [nexum]\n'
      printf 'networks:\n  nexum:\n    external: true\n    name: nexum\n'; } > "$d/compose.yaml.nuevo" || return 1
    chmod 600 "$d/compose.yaml.nuevo" && mv -f "$d/compose.yaml.nuevo" "$d/compose.yaml"
}

# Lo arranca con su configuración al día (y el certificado de *.docker.local). Si ya estaba en marcha,
# prueba la configuración nueva y la recarga sin cortar nada; si cambian sus puertos, se vuelve a crear
function docker_nginx_up() {
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] Nginx de Docker (nexum-nginx) en $(docker_web_get IP), puertos $(docker_nginx_get HTTP) y $(docker_nginx_get HTTPS)"
        return 0
    fi
    docker_ready > /dev/null 2>&1 || { echo "Docker sin root no esta en marcha"; return 1; }
    docker_web_cert && docker_nginx_write && docker_net || return 1
    if [ "$(docker_nginx_state)" == marcha ] && [ "$1" != --crear ]; then
        if ! dk exec nexum-nginx nginx -t -q -c /etc/nginx/nexum/nginx.conf; then
            echo "Nginx de Docker no acepta la configuración nueva: sigue con la de antes"
            return 1
        fi
        dk exec nexum-nginx nginx -s reload -c /etc/nginx/nexum/nginx.conf || return 1
        return 0
    fi
    dk compose --project-directory "$DOCKER_NGINX_DIR" -f "$DOCKER_NGINX_DIR/compose.yaml" up -d --force-recreate || return 1
}

# docker-nginx [estado] | arrancar | parar | anadir <proyecto> | quitar <proyecto> | puertos <http> <https>
#   estado: X|estado (marcha, parado o nuevo)|dirección|http|https y, por cada proyecto de Docker,
#   Y|proyecto|1 si va por Nginx|sus direcciones por el Nginx de Docker (separadas por espacios)
function docker_nginx_command() {
    local slug=$2 p dom urls
    case ${1:-estado} in
        estado)
            echo "X|$(docker_ready > /dev/null 2>&1 && docker_nginx_state || echo "?")|$(docker_web_get IP)|$(docker_nginx_get HTTP)|$(docker_nginx_get HTTPS)"
            for p in $(docker_web_projects); do
                urls=""
                for dom in $(docker_web_domains "$p"); do urls+=" $(docker_nginx_url "$dom")"; done
                echo "Y|$p|$([ "$(docker_conf "$p" NGINX)" == 1 ] && echo 1 || echo 0)|${urls# }"
            done ;;
        arrancar)
            docker_nginx_up --crear || return 1
            echo "Nginx de Docker en marcha en $(docker_web_get IP), puertos $(docker_nginx_get HTTP) y $(docker_nginx_get HTTPS)" ;;
        parar)
            [ -f "$DOCKER_NGINX_DIR/compose.yaml" ] || { echo "Nginx de Docker no estaba creado"; return 0; }
            [ "$DRY" -eq 1 ] && { echo "  [simulacion] Nginx de Docker parado"; return 0; }
            run dk compose --project-directory "$DOCKER_NGINX_DIR" -f "$DOCKER_NGINX_DIR/compose.yaml" stop && echo "Nginx de Docker parado" ;;
        anadir|quitar)
            docker_web_project "$slug" || { echo "No es un proyecto de Docker con el Apache de Docker: $slug"; return 1; }
            [ "$DRY" -eq 1 ] && { echo "  [simulacion] $slug $([ "$1" == anadir ] && echo "va" || echo "deja de ir") por el Nginx de Docker"; return 0; }
            docker_conf_set "$slug" NGINX "$([ "$1" == anadir ] && echo 1 || echo 0)" || return 1
            if [ "$(docker_ready > /dev/null 2>&1 && docker_nginx_state)" == marcha ]; then
                docker_nginx_up || return 1
            fi
            if [ "$1" == anadir ]; then
                for dom in $(docker_web_domains "$slug"); do echo "$slug por el Nginx de Docker: $(docker_nginx_url "$dom")"; done
                [ "$(docker_nginx_state)" == marcha ] || echo "(arranca el Nginx de Docker en Configuración, Docker)"
            else
                echo "$slug ya no va por el Nginx de Docker (con el Apache de Docker, igual)"
            fi ;;
        puertos)
            local http=$2 https=$3
            for p in "$http" "$https"; do
                if ! [[ "$p" =~ ^[1-9][0-9]{3,4}$ ]] || [ "$p" -gt 65535 ]; then echo "Puerto no válido: $p (de 1024 a 65535)"; return 1; fi
                if [ "$p" == "$(docker_web_get HTTP)" ] || [ "$p" == "$(docker_web_get HTTPS)" ]; then
                    echo "El puerto $p es del Apache de Docker"; return 1
                fi
            done
            [ "$http" == "$https" ] && { echo "http y https no pueden ir en el mismo puerto"; return 1; }
            [ "$DRY" -eq 1 ] && { echo "  [simulacion] Nginx de Docker en los puertos $http y $https"; return 0; }
            mkdir -p -m 700 "$DOCKER_DIR" || return 1
            ( umask 077; printf 'HTTP=%s\nHTTPS=%s\n' "$http" "$https" > "$DOCKER_NGINX_FILE.nuevo" ) && mv -f "$DOCKER_NGINX_FILE.nuevo" "$DOCKER_NGINX_FILE" || return 1
            if [ "$(docker_ready > /dev/null 2>&1 && docker_nginx_state)" == marcha ]; then
                docker_nginx_up --crear || return 1
            fi
            echo "Nginx de Docker en los puertos $http (http) y $https (https)" ;;
        *) echo "Uso: nexum docker-nginx [estado] | arrancar | parar | anadir <proyecto> | quitar <proyecto> | puertos <http> <https>"; return 1 ;;
    esac
}
