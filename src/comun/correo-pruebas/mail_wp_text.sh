# Texto del modo de WordPress
function mail_wp_text() {
    case $1 in
        mailpit) echo "los plugins de SMTP de WordPress siguen, con su correo a Mailpit (los que mandan por una API, como Brevo, se desactivan en la copia local)" ;;
        desactivar) echo "los plugins de SMTP y de envio de correo de WordPress se desactivan en la copia local (WordPress usa mail(), que va a Mailpit)" ;;
        nada) echo "los plugins de correo de WordPress no se tocan: lo que manden por SMTP o por su API puede llegar de verdad" ;;
    esac
}

# correo [estado] | si | no | wordpress mailpit|desactivar|nada | instalar | vaciar | bd <base>
# Un ajuste que se aplica como root (interruptores de la ventana): la contraseña antes de cambiar
# nada. Cancelarla deja el ajuste como estaba
function sudo_first() {
    { [ "$DRY" -eq 1 ] || [ -z "$SUDO" ]; } && return 0
    sudo -v && return 0
    echo "Cancelado: no se ha cambiado nada"
    return 1
}

