#!/usr/bin/env python3
"""Correos inventados para el Mailpit de la demostración (capturas-linux.sh): los manda por su SMTP
(127.0.0.1:11025) y escribe el identificador del pedido, para abrirlo en la captura."""
import json
import smtplib
import time
import urllib.request
from email.message import EmailMessage

WEB = "http://127.0.0.1:18025/"
CORREOS = [
    ("Clínica del Sol <noreply@clinicadelsol.example>", "ana.ruiz@correo.example", "Restablecer tu contraseña",
     "<p>Hola, Ana:</p><p>Alguien ha pedido cambiar la contraseña de tu cuenta. Si has sido tú, pulsa el botón:</p>"
     "<p><a href='https://clinicadelsol.example/restablecer' style='background:#0a84ff;color:#fff;padding:10px 18px;"
     "border-radius:8px;text-decoration:none'>Crear una contraseña nueva</a></p><p>Si no, no hagas nada.</p>"),
    ("Academia Flor <hola@academiaflor.example>", "jorge.martin@correo.example", "Bienvenido a la Academia Flor",
     "<h2>¡Ya estás dentro!</h2><p>Tu curso <b>Arreglos florales para principiantes</b> empieza el lunes.</p>"),
    ("Panadería Luna <web@panaderialuna.example>", "info@panaderialuna.example", "Nuevo mensaje del formulario de contacto",
     "<p><b>Nombre:</b> Lucía Gómez<br><b>Correo:</b> lucia.gomez@correo.example<br><b>Teléfono:</b> 600 000 000</p>"
     "<p><b>Mensaje:</b> Hola, ¿hacéis tartas por encargo para el sábado? Serían para 12 personas.</p>"),
    ("Moda Verde <pedidos@modaverde.example>", "maria.lopez@correo.example", "Tu pedido #1042 está confirmado",
     "<div style='font-family:sans-serif;max-width:560px'><h2 style='color:#1f9d55'>¡Gracias por tu compra, María!</h2>"
     "<p>Hemos recibido tu pedido <b>#1042</b>. Te avisaremos cuando salga.</p>"
     "<table style='width:100%;border-collapse:collapse'>"
     "<tr><td style='padding:6px;border-bottom:1px solid #ddd'>Camiseta de algodón orgánico (M)</td><td align='right'>24,90 €</td></tr>"
     "<tr><td style='padding:6px;border-bottom:1px solid #ddd'>Pantalón de lino (40)</td><td align='right'>49,00 €</td></tr>"
     "<tr><td style='padding:6px'>Envío</td><td align='right'>Gratis</td></tr>"
     "<tr><td style='padding:6px'><b>Total</b></td><td align='right'><b>73,90 €</b></td></tr></table>"
     "<p style='color:#888'>Moda Verde · Calle Ejemplo, 1 · 00000 Ciudad</p></div>"),
]


def main():
    for _ in range(50):
        try:
            urllib.request.urlopen(WEB + "readyz", timeout=1)
            break
        except OSError:
            time.sleep(0.2)
    with smtplib.SMTP("127.0.0.1", 11025, timeout=10) as smtp:
        for frm, to, subject, html in CORREOS:
            msg = EmailMessage()
            msg["From"], msg["To"], msg["Subject"] = frm, to, subject
            msg.set_content("Este correo necesita un programa que vea HTML.")
            msg.add_alternative(html, subtype="html")
            smtp.send_message(msg)
            time.sleep(0.3)
    with urllib.request.urlopen(WEB + "api/v1/messages", timeout=5) as r:
        msgs = json.load(r)["messages"]
    print(next(m["ID"] for m in msgs if m["Subject"].startswith("Tu pedido")))


main()
