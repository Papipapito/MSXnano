# 03. La tarjeta SD

La tarjeta es el disco del MSX. La maneja **Nextor** (el MSX-DOS 2 moderno de Konamiman)
a través de un driver propio para el lector SD de la Tang Nano 20K, y el menú de arranque
la lee directamente para enseñarte las ROMs y los discos.

## Qué tarjeta

Una **microSD** de marca, en **FAT16**. La forma más fácil de dejarla lista es
**[MSX SD Maker](../../MSXsdmaker/LEEME.md)**, un programa para Windows que está en este
repositorio: parte la tarjeta en particiones FAT16 de 2 o 4 GB como lo hace el FDISK de
Nextor, copia Nextor (la versión de tu pack), SofaRun, Multi Mente y un surtido de
utilidades, y escribe el `AUTOEXEC.BAT` que monta las demás particiones como C:, D:…

**FAT16, no FAT32.** Nextor (la 2.1.4 y la 3.0 beta 2) solo monta FAT12 y FAT16, hasta
4 GB por partición: con una tarjeta FAT32 el menú navega y lanza ROMs y discos, pero ESC no
llega a MSX-DOS y el File-Hunter no descarga («FH: la SD es FAT32»). Sin MSX SD Maker, una
tarjeta de 2 GB o menos se formatea en FAT16 desde cualquier sistema; con tarjetas mayores,
una partición de hasta 4 GB en FAT16 con una herramienta de particiones o con `CALL FDISK`
desde el propio MSX.

Nextor soporta **varias particiones** y el menú permite cambiar entre ellas con **TAB**.

## Qué poner

Lo que quieras, en la estructura de carpetas que quieras: el navegador del menú recorre
las carpetas. Por costumbre:

| Carpeta | Contenido |
|---|---|
| `ROMS/` | Cartuchos `.rom` (se cargan en la Megaram) |
| `DSK/` | Imágenes de disco `.dsk` (se montan en Nextor) |
| `FHUNT/` | La crea el File-Hunter para sus descargas |
| raíz | `NEXTOR.SYS`, `COMMAND2.COM`, `AUTOEXEC.BAT` si quieres arrancar en DOS con utilidades |

Para arrancar en **MSX-DOS** hace falta `NEXTOR.SYS` y `COMMAND2.COM` en la raíz de la
primera partición FAT16 (vienen con la distribución de Nextor, y MSX SD Maker los copia). Sin ellos, ESC en el menú te deja en BASIC con
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
