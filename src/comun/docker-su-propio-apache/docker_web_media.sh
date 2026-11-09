# Reglas de las imagenes de produccion de un WordPress en el Apache de Docker (su dominio, el de media-proyecto,
# el mismo que con LAMPP): lo que falte de wp-content/uploads (imagenes, videos y PDF; solo GET y HEAD) se pide
# a su web real con una redireccion 302. Nada si no tiene dominio de produccion
function docker_web_media() {
    local folder=$1 prod
    prod=$(media_saved "$folder")
    valid_domain "$prod" && [[ "$prod" != *.local && "$prod" != *.test && "$prod" != localhost && "$prod" != *.localhost ]] || return 0
    printf '    # nexum-media %s: lo que falte de wp-content/uploads se pide a produccion (media-proyecto)\n' "$prod"
    printf '    RewriteEngine On\n    RewriteCond %%{REQUEST_METHOD} ^(GET|HEAD)$\n'
    printf '    RewriteCond /opt/lampp/htdocs/%s%%{REQUEST_URI} !-f\n' "$folder"
    printf '    RewriteRule ^/(wp-content/uploads/.+\\.(%s))$ https://%s/$1 [NC,R=302,L]\n' "$MEDIA_EXT" "$prod"
}

# Configuracion del Apache de Docker (httpd.conf, las reglas, un vhost por proyecto y el de phpMyAdmin,
# en DOCKER_WEB_DIR/conf) y su compose.yaml. Se escribe entera cada vez (lo sabe todo de proyecto.conf).
# La carpeta conf va montada en el contenedor: se cambia lo de dentro, nunca la carpeta (el contenedor
# seguiria viendo la de antes)
DOCKER_WEB_CONF=/usr/local/apache2/conf/nexum/httpd.conf
