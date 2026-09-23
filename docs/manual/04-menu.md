# 04. El menú de arranque

El menú vive **dentro del pack de BIOS** (en la ROM de MSX-MUSIC, a partir del offset
0x760) y su fuente está en el repositorio de BIOS del autor, `bios-msxnano-msximus`
(privado), común a las dos máquinas. Este capítulo cuenta cómo se usa.

## Arranque

1. Logo de **MSX Barcelona**.
2. Si *Menu al arrancar* está activado: el **navegador** de la SD.
   Si no: directamente **MSX-DOS** (o BASIC, si no hay `NEXTOR.SYS`).

Desde la v2.0 hay **una sola BIOS** y el menú es un ajuste. Antes había que elegir qué pack
grabar; ahora se elige en Ajustes y se guarda en la flash.

## El navegador

| Tecla | Hace |
|---|---|
| **↑ / ↓** | mover; **← / →** = una página |
| **RETURN** o **botón A** del mando | abrir carpeta, o lanzar la ROM / montar el disco |
| **BACKSPACE** o **botón B** | carpeta anterior |
| **TAB** | cambiar de partición |
| **/** | buscar por nombre (subcadena; RETURN busca la siguiente, ESC cancela) |
| **M** | forzar el mapper de la ROM seleccionada (cicla entre los tipos) |
| **ESC** | arrancar el sistema (MSX-DOS) |
| **S** | Ajustes |
| **W** | configuración WiFi del ESP |
| **F** | File-Hunter: buscar y descargar de internet |
| **H** | ayuda |

Los nombres largos se desplazan (marquesina) cuando la entrada está seleccionada.

## Lanzar una ROM

Al pulsar RETURN sobre un `.rom` sale la **pantalla de lanzamiento**: nombre, tamaño, el
mapper detectado (o el forzado con M) y una barra de carga mientras se copia a la Megaram.
Con la ROM cargada, cualquier tecla arranca el MSX con ella "enchufada". Ver
[05. ROMs y mappers](05-roms-mappers.md) para cómo se decide el mapper.

## Montar un disco

Sobre un `.dsk` la pantalla es la misma. El disco se monta como unidad A: y el sistema
arranca desde él (o desde la SD si el disco no es de arranque).

## Ajustes (tecla S)

| Ajuste | Qué hace |
|---|---|
| **Slot 1** | Qué hay en el slot 1 |
| **Second SCC** | Activa el segundo SCC+ |
| **Enable Scanlines** | Líneas de barrido en la salida HDMI |
| **Stereo Sound** | Mezcla estéreo (PSG/SCC a un lado, OPLL al otro) o mono |
| **Sprites 8/línea** | Limita a 8 sprites por línea como un VDP real (algunos juegos cuentan con ello) |
| **Boot Turbo** | Arrancar siempre a 5,37 MHz. **Requiere reiniciar físicamente** (apagar y encender), porque se aplica al leer la flash |
| **Version FPGA (.fs)** | Muestra la versión del core que hay grabado (lee el puerto 0x2F). Si no cuadra con la del pack, avisa |
| **Menu al arrancar** | Si está marcado sale el navegador; si no, arranca directo |
| **Save & Restart** | Guarda en la flash y reinicia |

Los ajustes se guardan en el **bloque de configuración** del pack (los 6 bytes del final)
y sobreviven a apagar la máquina. Actualizar el pack los pone a su valor por defecto.

## File-Hunter (tecla F)

Con WiFi conectada, busca en [file-hunter.com](https://www.file-hunter.com) por nombre y
descarga ROMs e imágenes de disco a la carpeta `FHUNT/` de la SD, verificando el CRC32 de
cada descarga. Después aparecen en el navegador como cualquier otro fichero.

> **Estado en el MSXnano**: cabe en el pack desde el 04/09/2026 y ese mismo día se probó
> en placa: funciona. Ver [07. WiFi y File-Hunter](07-wifi-file-hunter.md).

## WiFi (tecla W)

Configura la red del ESP (escaneo de redes, contraseña, hora por NTP). Necesita un ESP-01S
o un ESP32-C6 enchufado. Ver [07](07-wifi-file-hunter.md).
