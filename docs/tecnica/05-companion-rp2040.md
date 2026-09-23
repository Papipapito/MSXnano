# 05. El companion RP2040 (teclado, mando, ratón)

La FPGA no tiene host USB. Un **RP2040** (Waveshare RP2040-Zero o una Pico normal) hace
de host con TinyUSB, traduce teclado, mando y ratón a un protocolo de un solo cable y se
lo cuenta a la FPGA por una **UART a 115200 8N1** (GP15 → pin 31 de la Tang). La FPGA
mantiene una **matriz de teclado virtual** que el MSX lee por el PPI como si fuera un
teclado de verdad.

Fuentes: `fpga/rp2040/` (firmware, `FW_VERSION = 0x13`) y `fpga/src/kbd_uart_rx.v`
(receptor). **La cabecera de `kbd_uart_rx.v` es el contrato**; si alguien cambia el
protocolo tiene que cambiar los dos lados a la vez.

## Cableado

| Pico | Tang Nano 20K | Notas |
|---|---|---|
| GP15 | **pin 31** | UART TX (PIO) → RX de la FPGA. `PULL_MODE=UP`: sin Pico la línea reposa alta = nada pulsado |
| GND | GND | Masa común, obligatoria |
| VBUS (5 V) | 5 V | La Pico se alimenta de la Tang; el teclado y el hub, de la Pico |

Un solo sentido (la FPGA nunca habla con la Pico). Los pines 27/28/29 del mismo header
son de la WiFi y el turbo ([BOM](../BOM.md)).

## El protocolo (congelado)

Bytes por la UART, LSB primero. Los opcodes con el bit 7 a 1 llevan operandos; los que
lo tienen a 0 son órdenes de un byte.

| Secuencia | Significado |
|---|---|
| `0x90 <celda>` | **MAKE**: tecla pulsada. `celda = 0x80 \| (bit << 4) \| fila`, fila 0-10, bit 0-7 |
| `0xA0 <celda>` | **BREAK**: tecla soltada |
| `0xFE m0 … m10 0xFF` | **Resync** de la matriz completa (11 filas, activas a nivel bajo). Cada 250 ms |
| `0xC0 <versión>` | Anuncio de versión del firmware (con cada resync). La FPGA lo **consume y lo descarta** (el guardián de versión se quitó en la v2.0); hay que seguir leyéndolo o el byte de versión se tomaría por una orden |
| `0xB0 <puerto> <byte>` | **Joystick**: `puerto` 0 = puerto 1 del MSX, 1 = puerto 2. `byte` activo alto: bit0 derecha, bit1 izquierda, bit2 abajo, bit3 arriba, bit4 A, bit5 B |
| `0xD0 <dx> <dy> <btn>` | **Ratón**: deltas con signo (+ = derecha/abajo, tal cual del host), `btn` bit0 izquierdo, bit1 derecho, activo alto |
| `0x04` | Orden: **turbo toggle** (F11). La única orden cableada en `top.v` |
| `0x01`, `0x02`, `0x03` | Órdenes históricas (scanlines, reset, OSD). Decodificadas, sin conectar |

Dos propiedades de diseño que conviene no romper:

- **Todo es aditivo.** Una FPGA vieja ignora los opcodes que no conoce y los operandos
  caen como opcodes desconocidos, también ignorados. Así se pudo añadir el ratón y el
  joystick sin obligar a reflashear las dos cosas a la vez.
- **El resync cada 250 ms cura cualquier byte perdido.** Un MAKE que se pierde deja una
  tecla pulsada como mucho 250 ms. Y hay un **vigilante de ~1 s** en la FPGA: sin bytes
  durante ese tiempo suelta toda la matriz y pone los joysticks a cero. Desenchufar la
  Pico en caliente no deja nada colgado.

## Lo que hace el firmware

- **Teclado HID → matriz MSX**: la tabla en `inc/keymaps.h`. Distribución internacional
  (la de la BIOS); no hay ñ porque la fuente de la BIOS no la tiene.
- **F11** = orden `0x04` (turbo). El resto de F1-F10 son las teclas de función del MSX.
- **Mandos**: HID genérico (DirectInput) y **XInput** (`xinput_host.c`). Todos los mandos
  van al **puerto 1** (`joy_set_state(0, …)`): el firmware no reparte un segundo mando al
  puerto 2. Los botones 3 y 4 son **autofire** a 10 Hz (`AF_HALF_PERIOD_US = 50 ms`; no
  bajar de ~40 ms o el PAL a 50 Hz se pierde pulsaciones).
- **Ratón**: se reenvían los informes HID tal cual (deltas sin negar; negarlos es cosa
  del RTL). LED de la Pico Zero en cian cuando hay ratón montado.
- **Hubs**: funcionan; un teclado + un mando + un ratón por un hub alimentado es el
  montaje normal. Teclados con hub interno a veces no enumeran.

## El lado FPGA

`kbd_uart_rx.v` corre entero en `clk_54m` (el pin RX pasa por un sincronizador de dos
flops; no hay CDC multi-bit). Expone:

- `vkey_row_out`: la fila de la matriz virtual para la columna que el PPI tiene
  seleccionada (`vkey_col`, nibble bajo del puerto C). En `top.v` se hace AND con la
  lectura del `0xA9`, así que si algún día hubiera un teclado físico convivirían.
- `joy_state0/1`: guardados activos a alto tal cual llegan; `top.v` los reordena al
  formato activo-bajo del PSG y los mezcla en la lectura del `0xA2`.
- `cmd_turbo_toggle`: pulso de un ciclo que en `top.v` hace `turbo <= ~turbo`
  (la misma variable que mueve el puerto Panasonic `0x41`).
- `mouse_*`: hacia `msx_mouse.v`.

## El ratón: `msx_mouse.v`

El ratón MSX no es de cuadratura: es "inteligente" y habla por **handshake con el pin 8**
del puerto de joystick. El MSX mueve ese pin y el ratón presenta **cuatro nibbles** por
los bits 0-3 del puerto A del PSG (X alto, X bajo, Y alto, Y bajo); los botones van en
los bits 4-5, activos a bajo. El módulo sigue el protocolo de **openMSX**
(`src/input/Mouse.cc`), no de memoria, y hay cuatro detalles que documenta su cabecera y
que se pierde quien lo escribe de oído:

1. Son **ocho fases**, no cuatro: una ronda completa es el ciclo principal y un ciclo
   alterno que devuelve deltas a cero a propósito (es como el software distingue un
   ratón de un trackball).
2. Se avanza por **flanco** del strobe, no por nivel (por nivel la máquina avanzaría
   sola y perdería movimiento). Cazado por `tb_msx_mouse`, prueba 1.
3. **El delta va negado**: mover a la derecha da delta negativo.
4. **Timeout de 1,5 ms** sin actividad → la fase vuelve al final del ciclo alterno, de
   forma que el siguiente strobe alto empieza una ronda limpia. Tiene que ser menor que
   un frame para que el joytest funcione (bug #474 de openMSX).

El delta se entrega saturado a ±127 y se **consume** del acumulador en vez de borrarlo:
así los movimientos lentos no desaparecen al dividir por la sensibilidad, que es la
trampa clásica de un ratón USB moderno con mucho más DPI que uno de MSX. El ratón vive
en el **puerto 2** (strobe `psgPB[5]`); el puerto `0x2B` expone la fase para depurar.

## Latencia

De la tecla al MSX, con teclado USB:

| Tramo | Típico |
|---|---|
| Sondeo USB del teclado (intervalo HID típico) | 1-8 ms, media ~4 |
| Firmware + UART (2 bytes a 115200) | ~0,2 ms |
| Hasta que el MSX lee esa fila del PPI (barrido de la BIOS por interrupción) | 0-20 ms, media ~8-10 |
| **Total** | **~14 ms** típico, 30 peor caso |

El tramo grande es el barrido del propio MSX, que sería el mismo con un teclado físico.
El BL616 de la placa por SPI (lo que usaba la v1.x) daba lo mismo: el USB y el barrido
mandan, el cable no.

## Compilar el firmware

`fpga/rp2040/README.md` tiene el detalle. Resumen: Pico SDK + TinyUSB, `cmake -G Ninja
.. && ninja`. Salen dos `.uf2`: `rp2040_keyboard.uf2` para la RP2040-Zero (LED NeoPixel
en GPIO16, por defecto) y `rp2040_keyboard_pico.uf2` para la Pico (`-DRP2040_ZERO=0`,
LED en GPIO25). El pin de la UART es GP15 en las dos. Si tocas el firmware, recompila
las dos. Se graban arrastrando el `.uf2` con la placa en modo BOOTSEL.
