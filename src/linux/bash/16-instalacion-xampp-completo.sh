# ===========================================================================
# Instalacion de un XAMPP completo
# ===========================================================================

function install_xampp() {
    local folder=$1 entry release php apache mariadb ftp perl pma md5 sha

    entry=$(catalog_entry "$folder") || { echo "XAMPP $folder no esta en el catalogo"; exit 1; }
    native_binaries || { echo "XAMPP solo esta disponible para equipos x86_64 (este es $(uname -m))"; exit 1; }
    IFS='|' read -r folder release php apache mariadb ftp perl pma md5 sha <<< "$entry"

    local target=/opt/lampp-$folder
    local url="https://sourceforge.net/projects/xampp/files/XAMPP%20Linux/$php/xampp-linux-x64-$release-installer.run/download"

    if [ -e "$target" ]; then
        echo "Ya existe $target"

        exit 1
    fi

    if [ -e /opt/lampp ] && [ ! -L /opt/lampp ]; then
        echo "/opt/lampp es una instalacion sin registrar. Registrala primero desde el panel."

        exit 1
    fi

    echo "Instalando dependencias ($XAMPP_DEPS)..."
    run sudo apt-get install -y -qq $XAMPP_DEPS || exit 1

    local tmp=$(mktemp -d /tmp/lvm-xampp-$release-XXXX)

    progress_parts "Descarga de XAMPP $release (150 MB)" "Instalador oficial de XAMPP" "Configuracion"

    echo "Descargando XAMPP $release (unos 150 MB)..."
    if [ "$DRY" -eq 1 ]; then
        echo "  [simulacion] descarga de $url y comprobacion sha256 $sha y md5 $md5"
    else
        progress 1 0 55 "descargando" bytes "$tmp/xampp.run" "$(remote_size "$url")"
        curl -q --proto =https --proto-redir =https -fsSL -o "$tmp/xampp.run" "$url" || exit 1

        if [ -z "$sha" ] || [ "$(sha256sum "$tmp/xampp.run" | cut -d' ' -f1)" != "$sha" ] \
                || [ "$(md5sum "$tmp/xampp.run" | cut -d' ' -f1)" != "$md5" ]; then
            echo "El instalador descargado no coincide con sus sumas sha256 y md5 esperadas. Se cancela."
            rm -rf "$tmp"

            exit 1
        fi

        chmod +x "$tmp/xampp.run"
    fi

    if [ "$DRY" -eq 1 ]; then
        local user=${SUDO_USER:-$USER}
        echo "  [simulacion] se pararia la version activa y se liberaria /opt/lampp"
        echo "  [simulacion] instalador de XAMPP en modo desatendido en /opt/lampp"
        echo "  [simulacion] registro como $target con /opt/htdocs y /opt/config/httpd-vhosts.conf compartidos"
        echo "  [simulacion] vhosts activados y Apache como $user:$(id -gn "$user" 2> /dev/null)"
        echo "  [simulacion] se reactivaria la version que estaba activa"
        rm -rf "$tmp"

        exit 0
    fi

    # El instalador de XAMPP siempre instala en /opt/lampp: se libera temporalmente
    local previous="" was_running=0
    if [ -L /opt/lampp ]; then
        previous=$(readlink -f /opt/lampp)
        lampp_running && was_running=1
        echo "Parando temporalmente lampp-${previous#/opt/lampp-}..."
        run sudo /opt/lampp/lampp stop
        run sudo unlink /opt/lampp
    fi

    echo "Ejecutando el instalador de XAMPP $release (unos minutos)..."
    progress 2 55 92 "instalando" time "" 120
    # Se ejecuta como root desde una carpeta de root, comprobado otra vez alli: en /tmp lo podria
    # cambiar cualquier programa de tu usuario entre la comprobacion y la ejecucion
    local rtmp
    rtmp=$(sudo mktemp -d /tmp/lvm-xampp-root-XXXX) || { restore_active "$previous" "$was_running"; rm -rf "$tmp"; exit 1; }
    sudo install -m 700 "$tmp/xampp.run" "$rtmp/xampp.run"
    if [ -z "$sha" ] || [ "$(sudo sha256sum "$rtmp/xampp.run" | cut -d' ' -f1)" != "$sha" ] \
            || [ "$(sudo md5sum "$rtmp/xampp.run" | cut -d' ' -f1)" != "$md5" ]; then
        echo "El instalador no coincide con sus sumas sha256 y md5 esperadas. Se cancela."
        sudo rm -rf "$rtmp"
        restore_active "$previous" "$was_running"
        rm -rf "$tmp"

        exit 1
    fi
    run sudo "$rtmp/xampp.run" --mode unattended --unattendedmodeui none
    sudo rm -rf "$rtmp"

    if [ "$DRY" -eq 0 ] && [ ! -x /opt/lampp/lampp ]; then
        echo "El instalador de XAMPP no ha terminado correctamente."
        restore_active "$previous" "$was_running"
        rm -rf "$tmp"

        exit 1
    fi

    progress 3 92 100 "registrando y configurando"
    run sudo /opt/lampp/lampp stop > /dev/null 2>&1
    register_lampp "$folder" || { restore_active "$previous" "$was_running"; exit 1; }

    # Ajustes habituales: vhosts compartidos activados y Apache con el usuario de la sesion
    run sudo sed -i 's|^#\(Include etc/extra/httpd-vhosts.conf\)|\1|' "$target/etc/httpd.conf"

    local web_user=$(web_user_name)
    if [ -n "$web_user" ] && [ "$web_user" != "root" ]; then
        local web_group=$(id -gn "$web_user")
        local conf="$target/apache2/conf/httpd.conf"
        [ -f "$conf" ] || [ "$DRY" -eq 1 ] || conf="$target/etc/httpd.conf"

        echo "Apache se ejecutara como $web_user:$web_group"
        run sudo sed -i '/^\(User\|Group\) /d' "$conf"
        if [ "$DRY" -eq 1 ]; then
            echo "  [simulacion] User $web_user / Group $web_group en $conf"
        else
            printf '\nUser %s\nGroup %s\n' "$web_user" "$web_group" | sudo tee -a "$conf" > /dev/null
        fi
    fi

    restore_active "$previous" "$was_running"
    rm -rf "$tmp"

    echo ""
    echo "XAMPP $release instalado en $target"
    echo "Para usarlo: lvm-instalador use $folder"
}

