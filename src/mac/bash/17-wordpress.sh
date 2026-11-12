# ===========================================================================
# WordPress: wp-config.php con la base cargada en local
# ===========================================================================
# Al pegar el codigo de produccion encima del proyecto local, su wp-config.php trae la base, el
# usuario, la contraseña y el servidor de produccion. Al cargar el proyecto (y al subir una base
# nueva para el) se comprueba que use la base asociada a la carpeta y que sus datos entren en el
# MariaDB local. Si no, se rehace con la plantilla: la copia del ultimo wp-config.php que funciono
# en este equipo (WP_CONFIG_DIR/<carpeta>.wp-config.php) o, si no la hay, el propio fichero (o
# wp-config-sample.php) con root y localhost. De la plantilla solo cambian la base y el prefijo.
WP_CONFIG_DIR="$LOG_DIR/wordpress"

function is_wordpress() {
    [ -f "$HTDOCS_DIR/$1/wp-config.php" ] || [ -d "$HTDOCS_DIR/$1/wp-includes" ]
}

# Vinculos entre las BBDD y las carpetas de los proyectos (~/.nexum/proyectos), uno por
# linea: base@version=carpeta (en esa version, la de XAMPP-<version>; sin carpeta, la base no es de
# ningun proyecto en esa version) o base=carpeta (en todas las versiones, como se guardaban hasta la
# 1.36). El de la version manda: asi la copia de una base en otra version puede ir con otra carpeta

# Nombre de la version activa (8.4.27, de XAMPP-8.4.27), o nada
function active_name() {
    local a=$(active_dir)
    [ -n "$a" ] && version_name "$a"
}

#@incluir comun/wordpress/linked_folder.sh
# vincular-bd <base> <version> <carpeta|->: la carpeta del proyecto de la base en esa version (- =
# ninguna). Cargar proyecto la carga con ella
function link_database() {
    local db=$1 ver=$2 folder=$3
    if [ -z "$db" ] || [ -z "$ver" ] || [ -z "$folder" ]; then
        echo "Uso: nexum vincular-bd <base de datos> <version> <carpeta de htdocs|->"
        return 1
    fi
    db_valid_name "$db" || return 1
    if ! valid_version_name "$ver" || [ ! -d "$BASE_DIR/XAMPP-$ver" ]; then
        echo "No existe la version XAMPP-$ver"
        return 1
    fi
    if [ "$folder" == "-" ]; then
        remember_project "$db" "" "$ver"
        echo "$db ya no esta vinculada a ningun proyecto en XAMPP-$ver"
    else
        folder=${folder%/}
        valid_project "$folder" || return 1
        remember_project "$db" "$folder" "$ver"
        echo "$db queda vinculada a $folder en XAMPP-$ver"
    fi
}

#@incluir comun/wordpress/wp_config_read.sh
