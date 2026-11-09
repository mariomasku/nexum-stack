# Huella sha256 del phpMyAdmin <version>: las que pone el gestor van fijadas aqui; otra, la que
# publica phpMyAdmin (del mismo servidor que el fichero: solo protege de descargas a medias)
function pma_sum() {
    case $1 in
        5.2.3) echo 57881348297c4412f86c410547cf76b4d8a236574dd2c6b7d6a2beebe7fc44e3 ;;
        5.1.4) echo 3230cf0e004b6284c70e0cb26064a8666b271749ef54236d035104a972822999 ;;
        4.9.11) echo 2b14737a2220e5ac9d2eaf683df6b56ebaa490d038ee980367cb4db909a57923 ;;
        *) curl -q --proto =https --proto-redir =https -fsSL "https://files.phpmyadmin.net/phpMyAdmin/$1/phpMyAdmin-$1-all-languages.tar.xz.sha256" 2> /dev/null | grep -oE '^[0-9a-f]{64}' ;;
    esac
}

# Version de phpMyAdmin instalada en <carpeta de phpmyadmin> (vacio si no se sabe)
function pma_installed() {
    local v
    v=$(grep -hoE "(VERSION = |PMA_VERSION', )'[0-9.]+'" "$1/libraries/classes/Version.php" \
        "$1/libraries/classes/Config.php" "$1/libraries/Config.php" 2> /dev/null | head -1 | grep -oE "[0-9][0-9.]+")
    [ -z "$v" ] && v=$(grep -rhoE "(VERSION = |PMA_VERSION', )'[0-9.]+'" "$1/libraries" 2> /dev/null | head -1 | grep -oE "[0-9][0-9.]+")
    echo "$v"
}

