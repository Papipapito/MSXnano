# 01. Qué es el MSXnano

Un **MSX2+ completo dentro de una FPGA**, en la placa Sipeed Tang Nano 20K. No necesita
un MSX: **es** un MSX. Se conecta a un televisor por HDMI, se le enchufa un teclado USB y
arranca en MSX-DOS o en un menú desde el que se lanzan juegos y discos guardados en una
tarjeta microSD.

Es la línea de core que empezó jabadiagm con el
[MSXgoauldSD_tn20k](https://github.com/jabadiagm/MSXgoauldSD_tn20k) —un Tang Nano 20K
enchufado al zócalo del Z80 de un MSX real— convertida en una máquina **autónoma**: sin
placa MSX debajo, con todo el hardware del sistema dentro del chip. Su hermano mayor es el
[MSXimus](https://github.com/Papipapito/MSXimus), en la Tang Console 60K, que hereda este
core y lo amplía con lo que aquí no cabe.

## Lo que trae

| | |
|---|---|
| **CPU** | Z80 a 3,58 MHz con la temporización de un MSX real (un estado de espera por cada ciclo M1), y **turbo a 5,369318 MHz exactos** con el protocolo Panasonic WSX |
| **Vídeo** | **V9958** (el VDP del MSX2+, con SCREEN 10-12 y scroll horizontal) con salida **HDMI**; scanlines opcionales |
| **Audio** | PSG, **OPLL** (MSX-MUSIC) y **dos SCC+**, mezclados en **estéreo** por el HDMI |
| **Memoria** | 4 MB de mapper de RAM · **Megaram de 2 MB** con SCC en el slot 2 · reloj de tiempo real |
| **Almacenamiento** | Tarjeta microSD con **Nextor 2.1.4** en el slot 3-2, menú de arranque y navegador de ficheros |
| **Teclado, joystick y ratón** | USB, a través de un **RP2040** (Pico Zero); incluye un **ratón MSX** de verdad a partir de cualquier ratón USB |
| **WiFi** | Opcional: MSX UNAPI con un **ESP-01S**, o un **ESP32-C6** que además pone una pantalla de estado |
| **BIOS** | MSX2+ internacional, con el menú integrado y activable desde Ajustes |

## Lo que hace falta

- Una **Tang Nano 20K**. Cualquier revisión: desde la v2.0 el companion USB es externo,
  así que da igual que la placa traiga el BL616 bloqueado (las marcadas `3921` en adelante).
- Un **RP2040** para el teclado. Por defecto una Waveshare **RP2040-Zero**; vale también
  una Raspberry Pi Pico normal. Tres cables.
- Un **teclado USB**. Y si quieres, un mando y un ratón, por un hub.
- Una **tarjeta microSD** en FAT32.
- Un cable **HDMI** y un televisor o monitor.
- El **pack de BIOS**. Va aparte del core: ver [02. Instalación](02-instalacion.md).
- Opcional: un **ESP-01S** o un **ESP32-C6-LCD-1.3** para WiFi, y la [carcasa](09-carcasa.md).

## Lo que no es

- **No es un emulador.** El Z80, el VDP y los chips de sonido son lógica en la FPGA; el
  software corre sobre ellos ciclo a ciclo. Por eso funciona lo que en un emulador se
  rompe, y también por eso cada función nueva cuesta silicio.
- **No es un turbo R.** Es un MSX2+ con turbo Panasonic: el turbo acelera el Z80, no hay R800.
- **No lleva cartucho físico.** Las ROMs se cargan desde la SD en la Megaram. No hay slot.
- **No es un MSXimus.** Le faltan el V9968, el OPL4, el DMA de la SD y demás cosas que
  necesitan un chip cuatro veces más grande.

## Por qué está cerrado

El core ocupa el **~89 % de las celdas lógicas** del GW2AR-18. En ese régimen, cualquier
cambio —incluso quitar lógica— reordena el emplazamiento y puede tumbar el reloj de la
CPU; se ha comprobado varias veces. El `.fs` de la v2.0 cierra a 61,7 MHz sobre los 54
necesarios, pero es el mejor de tres emplazamientos: uno de los tres no cerraba. Ahí se
queda. Lo que se sabe y no se pudo meter está
en [pendientes y aparcado](../tecnica/09-pendientes.md).
