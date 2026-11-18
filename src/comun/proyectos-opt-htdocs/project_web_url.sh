# Direccion con la que se abre el proyecto cargado (Abrir web, la bandeja, su panel y Compartir): la
# misma que Nexum pone en WP_HOME (wp_local_url: su dominio mientras esta falseado y, si no, la del vhost
# de los proyectos, con https si tiene certificado). Asi no se entra por http, donde un .htaccess de
# produccion («lo que llegue por el puerto 80, a https://midominio.es») se lleva la visita a la web real.
# Sin la barra del final; nada si no sale una direccion valida
function project_web_url() {
    local folder=$1 url
    if [ -n "$folder" ] && [ -f "$HTDOCS_DIR/$folder/wp-config.php" ]; then
        url=$(wp_local_url "$folder")
    else
        url=$(wp_link_url)
    fi
    [[ "$url" =~ ^https?://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$ ]] && echo "$url"
    return 0
}
