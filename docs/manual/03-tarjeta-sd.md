# 03. La tarjeta SD

La tarjeta es el disco del MSX. La maneja **Nextor** (el MSX-DOS 2 moderno de Konamiman)
a través de un driver propio para el lector SD de la Tang Nano 20K, y el menú de arranque
la lee directamente para enseñarte las ROMs y los discos.

## Qué tarjeta

Una **microSD** cualquiera, formateada en **FAT32**. Vale de 2 GB a 32 GB sin más;
tarjetas mayores hay que formatearlas en FAT32 a mano (Windows no lo ofrece por encima de
32 GB; en Linux `mkfs.vfat -F 32`).

Nextor soporta **varias particiones** y el menú permite cambiar entre ellas con **TAB**.
Con una sola partición FAT32 primaria no hay nada que configurar.

## Qué poner

Lo que quieras, en la estructura de carpetas que quieras: el navegador del menú recorre
las carpetas. Por costumbre:

| Carpeta | Contenido |
|---|---|
| `ROMS/` | Cartuchos `.rom` (se cargan en la Megaram) |
| `DSK/` | Imágenes de disco `.dsk` (se montan en Nextor) |
| `FHUNT/` | La crea el File-Hunter para sus descargas |
| raíz | `NEXTOR.SYS`, `COMMAND2.COM`, `AUTOEXEC.BAT` si quieres arrancar en DOS con utilidades |

Para arrancar en **MSX-DOS** hace falta `NEXTOR.SYS` y `COMMAND2.COM` en la raíz
(vienen con la distribución de Nextor). Sin ellos, ESC en el menú te deja en BASIC con
la SD accesible como unidad.

## Las dos versiones de Nextor

El pack lleva Nextor **dentro** (no va en la SD), y hay dos packs:

| Pack | Nextor | Cuándo |
|---|---|---|
| `pack_bios_msxnano.bin` | **2.1.4** | El recomendado. Estable, es el de siempre |
| `pack_bios_msxnano_nextor3.bin` | 3 beta | Para probar Nextor 3. Validado en el MSXimus; en el MSXnano no se ha probado en placa |

La SD sirve igual para los dos. Nextor 3 trae mejoras de compatibilidad con FAT y
ficheros largos; si no sabes cuál, el 2.1.4.

> Detalle que conviene saber: Nextor 2.1 **no se salta con SHIFT** al arrancar en esta
> máquina; si quieres arrancar sin disco, quita la tarjeta.

## Editar la SD desde el PC

Sin problema: es FAT32 normal. Solo una cosa: si editas ficheros de texto del MSX
(`AUTOEXEC.BAT`, `.BAT`, ficheros de configuración), hazlo con un editor que respete los
**finales de línea CR+LF** y no "arregle" las barras invertidas. Un editor de código en
modo Unix ha roto más de un `AUTOEXEC.BAT`.

## Rendimiento

La lectura de la SD va a unos **170 sectores por segundo** (unos 5,9 ms por sector de
512 bytes). El cuello de botella no es la tarjeta: es el Z80 copiando los datos con
`LDIR`, que se lleva la mitad del tiempo. Es lo normal en un MSX con interfaz de disco;
un juego de 128 KB carga en un par de segundos. El MSXimus lo acelera con DMA porque tiene
sitio para meterlo; aquí no.

## Guardado de partidas

El guardado en SRAM de los cartuchos (por ejemplo los juegos con pila) se emula en
**RAM volátil**: se pierde al apagar. Llevarlo a la tarjeta SD está resuelto en el MSXimus
y pendiente aquí por falta de espacio — ver [pendientes](../tecnica/09-pendientes.md).
