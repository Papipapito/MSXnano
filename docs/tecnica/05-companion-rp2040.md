# 05. El companion RP2040 (teclado, mando, ratón)

La FPGA no tiene host USB. Un **RP2040** (Waveshare RP2040-Zero o una Pico normal) hace
de host con TinyUSB, traduce teclado, mando y ratón a un protocolo de un solo cable y se
lo cuenta a la FPGA por una **UART a 115200 8N1** (GP15 → pin 31 de la Tang). La FPGA
mantiene una **matriz de teclado virtual** que el MSX lee por el PPI como si fuera un
teclado de verdad.

Hay dos montajes. Comparten el protocolo, la lógica de entrada (`inc/kbd_merge.h`,
`src/usbin.c`) y el pin 31; lo único que cambia es de dónde sale el USB:

| Montaje | Host USB | Imagen |
|---|---|---|
| **Portadora MSXnano v2** (`MSXnano-Boards/carrier`: Tang Nano 20K + RP2040-Zero en zócalos) | Pico-PIO-USB sobre tres puertos USB-A (J1, J2, J5); el USB-C de la Zero no es host | `rp2040_keyboard_carrier.uf2` (y `_carrier_debug.uf2`) |
| Zero o Pico cableada a mano | el USB-C del propio RP2040 (TinyUSB nativo; admite hub) | `rp2040_keyboard.uf2` (Zero), `rp2040_keyboard_pico.uf2` (Pico) |

Fuentes: `fpga/rp2040/` (firmware, `FW_VERSION = 0x13`) y `fpga/src/kbd_uart_rx.v`
(receptor). **La cabecera de `kbd_uart_rx.v` es el contrato**; si alguien cambia el
protocolo tiene que cambiar los dos lados a la vez.

## Cableado a mano (Zero o Pico)

| Pico | Tang Nano 20K | Notas |
|---|---|---|
| GP15 | **pin 31** | UART TX (PIO) → RX de la FPGA. `PULL_MODE=UP`: sin Pico la línea reposa alta = nada pulsado |
| GND | GND | Masa común, obligatoria |
| VBUS (5 V) | 5 V | La Pico se alimenta de la Tang; el teclado y el hub, de la Pico |

Un solo sentido (la FPGA nunca habla con la Pico). Los pines 27/28/29 del mismo header
son de la WiFi y el turbo ([BOM](../BOM.md)). En la portadora todo esto ya está cableado
(más abajo).

## El protocolo (congelado)

Bytes por la UART, LSB primero. Los opcodes con el bit 7 a 1 llevan operandos; los que
lo tienen a 0 son órdenes de un byte.

| Secuencia | Significado |
|---|---|
| `0x90 <celda>` | **MAKE**: tecla pulsada. `celda = 0x80 \| (bit << 4) \| fila`, fila 0-10, bit 0-7 |
| `0xA0 <celda>` | **BREAK**: tecla soltada |
| `0xFE m0 … m10 0xFF` | **Resync** de la matriz completa (11 filas, activas a nivel bajo). Cada 250 ms |
| `0xC0 <versión>` | Anuncio de versión del firmware (con cada resync). La FPGA lo **consume y lo descarta** (el guardián de versión se quitó en la v2.0); hay que seguir leyéndolo o el byte de versión se tomaría por una orden |
| `0xB0 <puerto> <byte>` | **Joystick**: `puerto` 0 = puerto 1 del MSX, 1 = puerto 2. `byte` activo alto: bit0 derecha, bit1 izquierda, bit2 abajo, bit3 arriba, bit4 A, bit5 B. Los dos puertos se repiten con cada resync |
| `0xD0 <dx> <dy> <btn>` | **Ratón**: deltas con signo (+ = derecha/abajo, tal cual del host), `btn` bit0 izquierdo, bit1 derecho, activo alto. Con ratón montado se repite como `0xD0 0 0 <btn>` con cada resync (los botones y la señal de vida), y al irse el último ratón sale un `0xD0 0 0 0` |
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
  (la de la BIOS); no hay ñ porque la fuente de la BIOS no la tiene. GRAPH sale del Alt
  izquierdo y de las dos teclas Windows, CODE del Alt derecho; F6-F10 se sintetizan como
  SHIFT+F1..F5.
- **F11** = orden `0x04` (turbo).
- **Varios teclados** (`kbm_*` en `inc/kbd_merge.h`): cada interfaz de teclado guarda *su*
  modificador y *sus* teclas (hasta 16), y al motor de diferencias de `usbin.c`
  (`kb_report_receive`, el único que emite MAKE/BREAK) solo le llega la **unión** de todos.
  Pasarle el informe de uno suelto haría que dos teclados que alternan informes se
  pisaran el estado y salieran BREAKs falsos. Al irse un teclado se recalcula la unión
  (BREAK de lo que solo él sostenía) y se manda un resync. Caben 8 interfaces de teclado.
- **Mandos** (`jpm_*`): HID genérico (DirectInput) y **XInput** (`xinput_host.c`) comparten
  un registro de hasta 8 mandos. Cada mando guarda su capa «mantenida» y su capa de
  autofire; el byte de un puerto es el OR de los de sus mandos.
  - **Reparto**: el primero que se monta va al puerto MSX 1 (`0xB0 0`), el segundo al
    puerto MSX 2 (`0xB0 1`); del tercero en adelante se suman (OR) al puerto 1. Cada
    mando conserva su puerto mientras siga montado. Si el puerto 1 se queda sin mandos,
    los del 2 pasan al 1 (los juegos de un jugador leen el 1).
  - Con un **ratón montado** el puerto 2 es del ratón (la FPGA se lo da con el primer
    `0xD0`): los mandos nuevos van al puerto 1 y se suman, y uno que ya estuviera en el
    2 queda tapado por el ratón.
  - Un adaptador doble que sale como una interfaz HID con dos Report ID cuenta como dos
    mandos. XInput admite un mando por dispositivo USB; un receptor inalámbrico de
    Xbox 360 se registra cuando se enciende el mando, no al enchufar el receptor.
  - Mapeo HID: ejes X/Y y cruceta; botones 1 y 2 = A y B; botones 3 y 4 = autofire de A
    y B. XInput: cruceta y stick izquierdo; A y B; X e Y = autofire de A y B. El autofire
    es a 10 Hz (`AF_HALF_PERIOD_US = 50 ms`; no bajar de ~40 ms o el PAL a 50 Hz se
    pierde pulsaciones).
- **Ratón**: se reenvían los informes HID tal cual (deltas sin negar; negarlos es cosa
  del RTL), acumulados y volcados a 100 Hz. Se pide el protocolo BOOT al montarlo (informe
  fijo de 3 bytes que todos los ratones soportan). LED de la Zero en cian cuando hay
  ratón montado.
- **LED de estado** (NeoPixel de la Zero): tres parpadeos azules al arrancar; después rojo =
  nada montado, verde = teclado, amarillo = mando, cian = ratón; destello blanco =
  actividad de tecla o mando, magenta = ratón moviéndose.
- **Hubs**: en el montaje a mano un hub alimentado funciona (teclado + mando + ratón es
  el montaje normal; teclados con hub interno a veces no enumeran). En la portadora no
  se soportan (siguiente apartado).

## La portadora MSXnano v2

Tang Nano 20K y RP2040-Zero van en zócalos; los tres USB-A se alimentan con los 5 V de la
placa (no pasan por la Zero), cada uno con 22 Ω en serie en D+ y D−, 15 kΩ a GND en cada
línea y un USBLC6. Sin chip de hub.

### Pines

| Zócalo | USB-A | D+ | D− | Puerto raíz de PIO-USB | `rhport` de TinyUSB |
|---|---|---|---|---|---|
| J1 | trasero | GP26 | GP27 | 0 | 1 |
| J2 | trasero | GP28 | GP29 | 1 | 2 |
| J5 | interno, frontal | GP0 | GP1 | 2 | 3 |

Los tres son DPDM (D− = D+ + 1) y **cualquier dispositivo va en cualquier zócalo**: los
rótulos de la serigrafía (`KEYBOARD`, `GAMEPAD`, `INT. KEYBOARD`) son solo una sugerencia,
el firmware no distingue. El enlace con la FPGA es el de siempre, GP15 → pin 31. GP16 es el
NeoPixel de la propia Zero; **no hay tira WS2812 externa** (GP26, que en el montaje a mano
es su salida de datos, aquí es el D+ de J1).

Lado Tang (`fpga/tang9k.cst` / `top.v` frente al zócalo J12 de la portadora). «Cabecera» es
el pin del zócalo: fila A = la del 5 V, fila B = la de los LED, el 1 en el extremo del USB-C,
con los nombres del datasheet de Sipeed:

| Pin Tang | Señal del bitstream | Cabecera | Red de la portadora | Destino |
|---|---|---|---|---|
| 31 | `kbd_uart_rx_pin` (entrada, pull-up) | B14 | `KBD_TX` | GP15 de la Zero |
| 27 | `uart_tx` (salida) | B8 | `FPGA_TX` | J4.4 (TX) y J6.4 (RXD del ESP-01S) |
| 28 | `uart_rx` (entrada, pull-up) | B9 | `FPGA_RX` | J4.5 (RX) y J6.5 (TXD del ESP-01S, por 1 kΩ) |
| 29 | `turbo_status` (salida, pull-down) | B12 | `TURBO` | J4.6 |
| 25 | `ws2812_led` (salida) | B10 | sin conectar | — |
| 5V / GND | — | A1 / A2, A15, B20 | `+5V_TANG` / `GND` | LM66100 desde el USB-C de la portadora |

J4 (la pantalla ESP32-C6: `5V · GND · NC · TX · RX · TURBO`) y J6 (el zócalo del ESP-01S)
comparten los pines 27/28: se monta uno o el otro. TX y RX son los nombres de la FPGA. El
resto de pines del bitstream (HDMI, flash, LEDs, botones) son internos de la Tang, y los
que salen a la cabecera (microSD 80/85, LEDs 15-20) no se conectan en la portadora. El
pin 25 de la Tang va, dentro de la propia Tang, al CEC del HDMI (R51 100 Ω, R40 27 kΩ a
3,3 V) y a la señal LCD_HS del conector del LCD: `ws2812_led` sigue sacando su señal por
ahí aunque la portadora no tenga tira.

### Host USB: Pico-PIO-USB

TinyUSB no lleva a la vez el host nativo y el host PIO, así que el USB-C de la Zero deja de
ser host. Sí puede ser *dispositivo* a la vez que el host PIO, y la imagen de depuración lo
aprovecha. El host usa Pico-PIO-USB con tres puertos raíz: `tuh_configure(…,
TUH_CFGID_RPI_PIO_USB_CONFIGURATION, …)` + `tusb_init()` para J1 y
`pio_usb_host_add_port(dp, PIO_USB_PINOUT_DPDM)` para J2 y J5, **después** de `tusb_init`
(usa el estado que este crea). Todo en el mismo núcleo, con un único `tusb_init` de host.

Reparto de recursos de la Zero en la imagen de la portadora:

| Recurso | Quién | Por qué |
|---|---|---|
| Reloj de sistema | 120 MHz, `set_sys_clock_khz(120000, true)` lo primero de `main()` | Pico-PIO-USB exige un múltiplo de 12 MHz (TX a 48 MHz). Va antes de nada que calcule divisores sobre `clk_sys` (enlace UART, NeoPixel) |
| Núcleo 0 | todo: `tuh_init`, `tuh_task`, callbacks de `usbin.c`, bombas del enlace, LED, vigilante de puertos y la alarma de 1 ms de PIO-USB (SOF y transferencias, dentro de su IRQ) | Un solo dueño de todo el estado compartido, sin cerrojos. El núcleo 1 no se lanza. No partir `tuh_task()` y las bombas entre núcleos |
| `pio0` | entero de PIO-USB: SM0 TX, SM1 RX, SM2 EOP | El programa TX de PIO-USB va fijo en el offset 0 de `pio0`: el resto de programas PIO van en `pio1` |
| `pio1` SM0 | UART del enlace con la FPGA (GP15) | |
| `pio1` SM1 | NeoPixel de la Zero (GP16) | En el montaje a mano va en `pio0` SM0 |
| DMA | un canal para el TX de PIO-USB (`tx_ch`) | El firmware elige uno libre, lo suelta y se lo pasa; PIO-USB lo reclama con `dma_claim_mask` |
| Alarma | alarma de hardware 2, repetida cada 1 ms | La crea PIO-USB (`alarm_pool_create(2, 1)`); su IRQ cae en el núcleo que llama a `tusb_init` |
| Pila | 4 KB en el núcleo 0 (`PICO_STACK_SIZE=0x1000`) | La IRQ de 1 ms se apila sobre `tuh_task()` y los callbacks |
| USB nativo (`rhport` 0) | solo en la imagen de depuración: dispositivo CDC | Ver «Depuración» |

Una mala colocación (otro programa en `pio0`, un canal DMA ocupado, un reloj que no sea
múltiplo de 12 MHz) **no hace panic**: el USB se queda muerto en silencio. Por eso
`main.c` fija la colocación a mano y el registro de depuración imprime reloj, PIO y canal.

PIO-USB dimensiona sus tablas con `PIO_USB_ROOT_PORT_CNT`, que vale 2 por defecto y no está
protegido por `#ifndef`. `cmake/stage_pio_usb.cmake` copia el `src/` del submódulo al
directorio de build y cambia solo esa línea a 3 en la copia (si la línea cambia en una
versión nueva del submódulo, el cmake falla en vez de parchear a medias). El submódulo
queda exactamente en el commit fijado, y `main.c` tiene un `_Static_assert` de que son 3.

### Por qué `CFG_TUH_HUB` es 2 aunque no haya hubs

Con TinyUSB 0.21 la enumeración es de uno en uno (comparten el búfer de control). Si un
segundo dispositivo se conecta mientras otro enumera, su evento de *attach* se guarda en
una cola de attach diferido (`_usbh_daq`). Esa cola **solo existe con `CFG_TUH_HUB ≥ 1` y
tiene exactamente `CFG_TUH_HUB` entradas**; sin ella el segundo attach se pierde sin
más y ese dispositivo no llega a enumerar. Pasa de verdad en el arranque en frío con varios
dispositivos enchufados: PIO-USB recorre los tres puertos en cada pasada de 1 ms, así que
los attach llegan a la vez.

Con tres puertos raíz pueden esperar dos a la vez (el tercero enumera), así que hace falta
`CFG_TUH_HUB ≥ 2`; `tusb_config.h` lo fija en 2 y lleva un `#error` si baja. Esto activa
también el driver de hub, pero los hubs **no son un montaje soportado en la portadora**:
sobre PIO-USB no son fiables (límites conocidos de Pico-PIO-USB y TinyUSB).
`CFG_TUH_DEVICE_MAX` es 8 (tres puertos raíz y holgura).

### Vigilante de puertos (`inc/port_watch.h`)

Pico-PIO-USB marca un puerto *connected + suspended* al detectar la conexión y a partir de
ahí solo vigila la desconexión en los puertos *no suspendidos*. TinyUSB, si al acabar el
antirrebote (150 ms) la línea está en SE0, aborta la enumeración sin reiniciar el puerto.
Un dispositivo que se saca justo en esa ventana deja el puerto *connected + suspended* con
la línea en SE0 para siempre: no vuelve a generar attach hasta apagar y encender. Con tres
puertos la ventana se alarga, porque un attach diferido espera a las enumeraciones que
lleva delante.

El firmware mira cada puerto raíz cada 100 ms (`carrier_port_watch()` en `main.c`, con las
interrupciones cortadas porque la alarma de 1 ms toca los mismos campos). Si lleva tres
pasadas seguidas *connected + suspended + SE0* y no hay un reset de bus en curso (que
fuerza SE0 a propósito y se reconoce porque el habilitador de salida de D+ está forzado),
lo marca desconectado y la IRQ de SOF verá la siguiente conexión. La decisión es pura
(`pw_step`) y se prueba en el PC.

### Combinaciones con tres zócalos

Tres zócalos y sin hubs son hasta tres dispositivos a la vez: teclado + dos mandos
(mando 1 → puerto MSX 1, mando 2 → puerto MSX 2), dos teclados + mando (los teclados se
fusionan), o teclado + ratón + mando (el ratón manda en el puerto 2, el mando va al 1). El
orden de reparto de los mandos es el de montaje; con varios dispositivos enchufados al
arrancar es el orden en que acaban de enumerar.

### Depuración (`rp2040_keyboard_carrier_debug.uf2`)

El USB-C de la Zero es un dispositivo CDC (rhport 0, VID:PID `CAFE:4A01`, cualquier
velocidad) por el que sale `dbg_printf()`. Escribe en un anillo de 2 KB que no bloquea nunca
y que `dbg_task()` vuelca cuando hay un terminal con DTR; si se llena pierde lo más
antiguo, así que el arranque sigue ahí cuando se abre el puerto. El registro no cambia lo
que sale por el cable (lo comprueba `test_usbin_dbg`). Líneas:

| Línea | Qué dice |
|---|---|
| `MSXnano carrier fw 0x13, TinyUSB …, sys 120000 kHz, PIO-USB pio0 dmaN` | Versión, reloj (debe ser 120000) y canal DMA |
| `PIO-USB configure=1 host_init=1 \| J1 … \| J2 … add=0 \| J5 … add=0` | PIO-USB bien montado. `add=-1` = PIO-USB no ha encontrado un puerto raíz libre para ese zócalo |
| `USB mount addr=A VID:PID puerto=Jn hub=0/0` / `USB umount …` | Cada dispositivo con su zócalo; `hub≠0/0` = cuelga de un hub |
| `KBD mount … (n teclados)` / `KBD umount …` / `HID umount …` | Teclados registrados |
| `PAD HID …` / `PAD mount HID\|XInput … -> puerto MSX n (m mandos)` / `PAD umount …` | Mandos y su puerto MSX |
| `PAD los mandos del puerto MSX 2 pasan al puerto MSX 1` | Reparto compactado |
| `MOUSE mount … -> puerto MSX 2` | Ratón (el puerto 2 es suyo) |
| `XINPUT open/mount …`, `XINPUT wireless … mando conectado\|desconectado` | Driver XInput |
| `HID mount …: sin hueco…`, `no se pudo pedir informe` | Dispositivo ignorado (tablas llenas o fallo al armar el informe) |
| `PIO-USB Jn: línea en SE0 sin enumerar, puerto liberado` | El vigilante ha soltado un puerto colgado |

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
- `mouse_*`: hacia `msx_mouse.v`. `mouse_present` lo sube el cuarto byte de un `0xD0` y lo
  bajan el reset del MSX o el vigilante del enlace (~1 s sin bytes); **no caduca por falta
  de `0xD0`**, así que tras desenchufar el último ratón el puerto 2 sigue siendo suyo hasta
  el siguiente reset del MSX.

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

`fpga/rp2040/README.md` tiene el detalle. Resumen: cuatro imágenes, una por variante y
cada una en su directorio de build (cambiar las opciones en uno existente no es fiable):

| Imagen | Opciones de cmake |
|---|---|
| `rp2040_keyboard.uf2` (RP2040-Zero, LED NeoPixel en GPIO16) | ninguna |
| `rp2040_keyboard_pico.uf2` (Pico, LED en GPIO25) | `-DRP2040_ZERO=0` |
| `rp2040_keyboard_carrier.uf2` | `-DMSXNANO_CARRIER=ON` |
| `rp2040_keyboard_carrier_debug.uf2` | `-DMSXNANO_CARRIER=ON -DMSXNANO_DEBUG_CDC=ON` |

El pin de la UART es GP15 en las cuatro. Las dos primeras usan el TinyUSB del Pico SDK; las
de la portadora usan TinyUSB 0.21.0 y Pico-PIO-USB de los submódulos `fpga/rp2040/lib/…`
(`git submodule update --init --depth 1 fpga/rp2040/lib/tinyusb fpga/rp2040/lib/Pico-PIO-USB`,
desde la raíz del repositorio). Si tocas el firmware, recompila las cuatro. Se graban
arrastrando el `.uf2` con la placa en modo BOOTSEL.

La lógica de entrada (varios teclados, reparto de mandos, ratones, vigilante de puertos) se
prueba en el PC, sin hardware, con `pwsh fpga/rp2040/test/run.ps1` (gcc dentro de WSL): la
lógica pura de `kbd_merge.h` y `port_watch.h`, y el `usbin.c` real con el SDK y TinyUSB
sustituidos por stubs, comprobando que un solo dispositivo produce los mismos bytes por el
cable que el firmware de un solo teclado.
