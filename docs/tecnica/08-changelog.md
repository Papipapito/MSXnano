# 08. Historial de versiones

Resumen técnico de cada release (tags del repo). Las notas completas están en
[GitHub → Releases](https://github.com/Papipapito/MSXnano/releases). Versión del core =
puerto `0x2F`.

## v2.0-final — 23 de septiembre de 2026 · **la última release**

- **Los mismos binarios que la v2.0**: `.fs` del par 48 (dado 999961, md5 `b0e374d8…`) y
  los packs del 04/09 (Nextor 2.1.4 `4dc4e4f5…`, Nextor 3 beta `d6f3b2d4…`).
- Validado en placa por Albert el 23/09: **F11 → 5,37 MHz**, mando, ratón, Space Manbow y
  Metal Gear 2, y el guardado de cambios.
- La documentación completa (`docs/`), la carcasa con las dos tapas y los dos packs de
  BIOS en la release.

## v2.0 — 4 de septiembre de 2026 · `FPGA_VERSION = 0x20`

- **Fuera el BL616**: teclado, mando y **ratón MSX** por un **RP2040** (GP15 → pin 31, un
  cable). Las placas `3921` de 2024+ traían el BL616 con *secure boot* y muchas se
  quedaban sin teclado; con la RP2040 todas se comportan igual. −479 LUT, −353 FF y un
  reloj inferido menos (`WARN TA1132`).
- **Ratón MSX** (`msx_mouse.v`, protocolo de openMSX, 8 fases, puerto 2) servido por el
  mensaje `0xD0` del RP2040; diagnóstico en `0x2B`.
- **Una sola BIOS**: el menú se activa/desactiva en Ajustes (*Menu al arrancar*, bit 3 de
  `config2`, guardado en flash). Antes había dos packs.
- **Descargas** desde el menú con WiFi (File-Hunter, tecla F). Cupo en el pack del nano
  al retirar la cinta web; probado en placa el 04/09.
- **ESP32-C6 con pantalla** como companion opcional (estado, reloj, turbo, logo animado);
  el ESP-01S sigue valiendo. Pin 29 = estado del turbo.
- **PPI**: decodificado `0xAB` (bit set/reset: CAPS, click, motor) y relectura de `0xAA`,
  portado del MSXimus.
- **Timing**: fusión del decodificador `A9/AA` y puerto 2 del PSG registrado (commit
  `4cb65a4`); paso a **Gowin 1.9.12.03**; `set_device -name`.
- **Fuera la cinta virtual** (`cas_stream`, `tape_uart`, `cas_player`, `tape_flash`,
  `tape_rom`, puertos `0x2C-0x2E`): el proyecto que la alimentaba se cayó. Pines 26 y 32
  libres. `CASIN` en reposo alto.
- `F11` cableado al turbo (`kbd_cmd_turbo` → `turbo <= ~turbo`).
- Teclado RP2040: F6-F10 como en un MSX real, GRAPH en Alt izq./Windows, CODE en Alt
  der., STOP en F12.
- README reducido de 405 a 152 líneas: solo lo que hay.
- Assets de la release: `.fs` + `.bin`, los dos `.uf2`, `firmware_esp32c6_v2.0_merged.bin`.
  Dado del `.fs`: 999961.

## v1.9 — 10 de julio de 2026 · `0x19`

- **Solo MSX**: fuera la emulación de SG-1000/ColecoVision (`sn76489.v` borrado).
- **Turbo Panasonic WSX 5,369 MHz** con conmutación de cadencia *glitch-free* (F11 ya no
  cuelga); testbench `turbo_cadence_equiv`.
- Arreglo de la pantalla negra en *Save & Reset* con turbo (el boot-turbo solo en frío).
- Fuera el *Compatible Mode* vestigial del goauld (`config2` bit 3 queda libre).
- Guardián de versión menú ↔ bitstream por el puerto `0x2F`.
- Límite de 8 sprites por línea como ajuste (`config2` bit 4).
- Refresco de SDRAM ligado a `RFSH` (bucle de arranque resuelto).

## v1.8 — 29 de junio de 2026

- **ColecoVision y SG-1000** desde el menú (`.col`/`.sg`, SN76489). Retirado en la v1.9.
- **Metal Gear 2 arreglado** de verdad: el menú usaba el registro de parpadeo `R#13` para
  resaltar, que en V9938/V9958 fuerza la página 0 y anulaba el cambio de página del juego.
  El lanzador ahora restaura `R#12/R#13` y hace un `STOP` de comando antes del `INIT`.
- Logo de arranque (`logo16k` con magic `LG`, menú con `CALLF 8C:4002`).

## v1.7.1 — 13 de junio de 2026

- Corrección sobre v1.7: Konami4 en dos fases, `.dsk`, navegador, **Nextor 2.1.4** (desde
  aquí es la versión de referencia), SRAM, splash, arreglo del refresco del VDP.
- Limitación conocida entonces: MG2 glitcheaba al empezar (resuelto en v1.8).

## v1.7 — 11 de junio de 2026

- **Mapper Konami4** (registros en `6000/8000/A000`, banco 0 fijo, sin registros de modo:
  inmune a los *pokes* anticopia). Arregla Nemesis, Penguin Adventure y los Konami sin SCC,
  que nunca habían funcionado.
- Las ventanas del SCC (`9800/B800`) y su audio, exclusivas del modo SCC: un banco `0x3F`
  en Konami4/ASCII ya no abre el sonido por accidente.
- Búsqueda en el navegador y **forzado de mapper** (tecla M, etiquetas GoodMSX).
- **La saga MG2**: el sondeo de RAM de la BIOS escribía en `0x8000` de todos los slots y
  pisaba un registro de banco del Konami4 en modo por defecto → los juegos de dos fases
  entraban con el mapeo roto. Cerrojo anticopia en `7FFE` bit 7, `restore_palette`,
  `clock_108i` por `get_pins`.

## v1.6 — 10 de junio de 2026

- **Menú de arranque** completo: navegador de la SD estilo File-Hunter (pestañas
  ROM/DSK/ALL, nombres largos, subdirectorios), lanzar `.ROM` a la Megaram con detección
  de mapper, lanzar `.DSK` por emulación de Nextor (sin ficheros auxiliares), **FAT16 +
  FAT32** por partición (TAB cambia de partición).
- **SCC+ real** (SCC-I: ventana `B800`, registro `BFFE`, canal 5 con onda propia; lectura
  de la wave RAM arreglada) y **segundo SCC+** en el slot libre; **segundo PSG** en
  `0x10-0x12`.
- **Estéreo por HDMI**: PSG1+SCC1+OPLL a la izquierda, PSG2+SCC2+OPLL a la derecha.
- Timing: el dominio de 54 MHz cierra con margen positivo (constraints CDC del SPI del
  companion + *retime* del decodificador kanji).
- `fat32_emu_test.py`: intérprete Z80 para probar el menú en el PC.

## v1.5 — 4 de junio de 2026

- Primer menú de arranque (M2): navegador de SD, lanzador de ROMs, autofire.

## v1.3 — 31 de mayo de 2026

- Turbo por **F11** (F12 la capturaba el firmware del BL616).
- Teclas GRAPH y CODE/KANA.

## v1.2 — 31 de mayo de 2026

- **Reconstrucción sobre el core goauld standalone** (sin bus MSX debajo): BL616 para
  HID, LEDs discretos, HDMI, WiFi.
- **Estado de espera por M1** (`ENABLE_M1_WAIT`) → velocidad de MSX real (~100 %; antes
  116 %).
- **BIOS en un pack de flash** (`0x200000`) que se copia a la SDRAM al arrancar, en vez
  de empotrada en BSRAM (que estaba al 100 %); la ROM UNAPI del ESP va dentro. Pack fuera
  del repo (copyright).
- Configuración persistente en flash (`0x280000`, firma `AB`), heredada del OCM.
- Fuera los directorios de hardware del goauld (KiCad, PCBA).

## v1.1 — 27 de mayo de 2026

- WiFi con ESP-01S (MSX UNAPI).

## v1.0 — 27 de mayo de 2026

- Primera versión: MSX2+ en la Tang Nano 20K a partir del MSXgoauldSD de jabadiagm.
