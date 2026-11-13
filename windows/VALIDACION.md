# Validación local de la preview Windows

2026-11-13. Rama feat/windows-wsl, motor 1.57.15, Windows 11 y Ubuntu 26.04 WSL2.

Corrección posterior: el usuario detectó ventana vacía. Faltaba python3-gi-cairo;
GTK cargaba, pero el dibujo del logotipo fallaba por falta del convertidor cairo.Surface.
Dependencia instalada y añadida al instalador. Doctor ahora comprueba conversión
real de GdkPixbuf a cairo.Surface, y verify.py lee ventana.log durante el arranque,
además de comprobar proceso vivo. Interfaz completa verificada visualmente tras
reinicio. La prueba inicial de proceso vivo no detectaba este error y su resultado
no constituía validación de renderizado. Se conserva por separado el registro tras
cerrar el proceso para distinguir errores de arranque y de cierre.

Completado:

- Instalación real de GTK, dependencias y paquete Linux desde PowerShell Windows.
- Instalación repetida desde ZIP extraído en una ruta Windows con espacios: código 0.
- Acceso Nexum Dev Stack creado en Inicio; acompañante instalado en LocalAppData/Nexum.
- Comando `nexum.ps1 Run version`: Nexum Dev Stack 1.57.15.
- Ventana GTK real estable durante 12 segundos, sin traceback ni salida de errores.
  Su grupo de procesos se terminó al acabar la comprobación.
- Siete pruebas del manifiesto y apertura de enlaces: nombres activos, retirada al
  desactivar hosts, certificado de servidor, rechazo de CA y de SAN no mapeados,
  preservación de URL y rechazo de esquemas ejecutables/rutas relativas.
- PowerShell 5.1: sintaxis de lanzador, sincronizador y empaquetador; transporte
  exacto de argumentos con espacios, apóstrofos, comillas y barras invertidas.
- Política Windows X509: acepta hoja autofirmada, rechaza CA y dominio no activo,
  usando certificados efímeros sin modificar almacenes de confianza.
- Sincronización `-WhatIf`: ejecutada sin modificar hosts ni confianza Windows.
- 364 comprobaciones compartidas, todas correctas: 170 Linux y 194 macOS, usando
  seis grupos por plataforma y el grupo Docker específico de cada una.
- ZIP de instalación generado en dist, excluyendo auditorías e informes locales.

Alcance: estas pruebas validan instalador, lanzador y parte de la integración. No
certifican paridad total de todas las funciones ni rendimiento igual a Ubuntu físico.
No se instalaron pilas PHP ni se migraron proyectos o bases existentes. Docker
Desktop sigue sin integración Ubuntu; el diagnóstico lo distingue de motor operativo.
No se probó el acompañante elevado contra dominios y HTTPS de proyectos reales;
hosts y confianza Windows originales se conservaron durante la validación.

La instalación deja motor y dependencias disponibles en Ubuntu para uso posterior.
Los procesos de prueba se cierran; Docker Desktop anterior se conserva.

Repetir: `python windows/verify.py`. Resultados locales en verification.json.
Instalación desde ZIP registrada en installation.json. Los JSON se excluyen de Git
y del paquete; no son necesarios para ejecutar el producto.
