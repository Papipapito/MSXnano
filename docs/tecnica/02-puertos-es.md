# 02. Puertos de E/S

Todos los puertos que responde el core, agrupados. Los estándar del MSX se comportan como
en la máquina real; los **propios** del MSXnano están marcados y son los que interesan a
quien escriba software para él.

## Propios del MSXnano

| Puerto | R/W | Qué es |
|---|---|---|
| **0x2F** | R | **Versión del core** (`FPGA_VERSION` en `top.v`). Formato `0x1X` = 1.X, `0x20` = 2.0. El menú lo **muestra** en Ajustes; desde la v2.0 no lo compara con nada (el guardián de versión de la v1.9 se quitó). Sin guarda: se lee siempre |
| **0x2B** | R | Diagnóstico del **ratón**: estado del handshake (fase, pin 8, últimos nibbles). Solo para depurar `msx_mouse.v`; portado del 0x2E del MSXimus |
| **0x40** | W | **E/S conmutada** (OCM): selecciona el dispositivo. `OUT &H40,8` = turbo Panasonic; `OUT &H40,&H48` (72) = configuración goauld |
| **0x40** | R | Devuelve el complemento del dispositivo seleccionado si existe (`&HF7` tras seleccionar el 8) |
| **0x41** | R/W | Con el dispositivo 8: **turbo Panasonic**. Bit 0 = 0 turbo 5,37 MHz, 1 = 3,58. `OUT &H41,128` activa, `OUT &H41,129` desactiva; `INP(&H41)` lee el estado. Con el dispositivo 0x48: **config1** (mapper, Megaram, segundo SCC, scanlines; mapa de bits en [04](04-pack-bios.md)) |
| **0x42** | R/W | Con el dispositivo 0x48: **config2** en los bits 5:0 (SD, slot de Nextor, menú al arrancar, 8 sprites/línea, estéreo); **bit 6 = guardar en la flash**, **bit 7 = reiniciar**. Escribir en 0x41 o en 0x42 aplica los dos registros a la vez: el menú escribe siempre 0x41 y luego 0x42 |
| **0x43** | R/W | Con el dispositivo 0x48: `sram_cfg` de la Megaram (qué segmentos son SRAM). Volátil |
| **0x45** | R/W | Con el dispositivo 0x48: **Boot Turbo** (bit 0); se guarda en la flash con el resto |
| **0x10 / 0x11 / 0x12** | W/W/R | **Segundo PSG** (YM2149): registro, escritura y lectura, como los 0xA0-0xA2. En estéreo va al canal derecho |
| **0x06 / 0x07** | R/W | **UART del ESP** (WiFi): 0x07 = TX / estado (bit 0 = hay dato), 0x06 = RX / velocidad (`OUT (6),20` vacía el FIFO). Los usa la ROM UNAPI; velocidad fija 859372 |

### El protocolo del turbo, paso a paso

Es exactamente el del Panasonic FS-A1WSX, para que el software que lo conoce lo detecte:

```basic
OUT &H40,8            ' seleccionar el dispositivo "turbo"
IF INP(&H40)=&HF7 THEN PRINT "hay turbo"
OUT &H41,128          ' activar (bit0 = 0)
OUT &H41,129          ' desactivar (bit0 = 1)
PRINT INP(&H41) AND 1 ' 0 = en turbo
```

Si el puerto y la tecla F11 cambian el turbo en el mismo ciclo, gana el puerto (en el
chip T9769 real el puerto es el único control).

## Estándar del MSX (comportan como la máquina real)

| Puerto | Chip | Notas |
|---|---|---|
| **0x98 – 0x9B** | V9958 | VRAM, registros, paleta, indirecto. Con las esperas del VDP real |
| **0xA0 – 0xA2** | PSG | Registro, escritura, lectura. El puerto A (R#14) lleva el joystick/ratón; el bit 7 es la entrada de casete (siempre a 1, no hay casete) |
| **0xA8 – 0xAB** | PPI 8255 | Slots primarios (A8), teclado (A9 columna, AA fila), y **AB con el modo bit-set/reset** (motor, click, CAPS). Los cuatro se decodifican; el AA se puede releer (hubo un bug histórico aquí) |
| **0x7C / 0x7D** | OPLL | MSX-MUSIC |
| **0xB4 / 0xB5** | RTC | RP-5C01 |
| **0xD8 – 0xDB** | Kanji | JIS1 y JIS2 |
| **0xFC – 0xFF** | Mapper de RAM | 4 MB = 256 segmentos; los registros **no son legibles** (devuelven 0xFF) — es uno de los hallazgos aparcados |
| **0xF2** | — | Latch de 8 bits de lectura/escritura (heredado del OCM) |

## Memoria mapeada (no son puertos, pero se buscan aquí)

| Rango | Qué | Cómo |
|---|---|---|
| `0x5000/0x7000/0x9000/0xB000` en slot 2 | Bancos de la Megaram en modo Konami SCC | Escritura del número de banco |
| `0x9800 – 0x98FF` en slot 2 | **SCC** de la Megaram (con el banco 0x3F en 0x9000) | Registros de onda, frecuencia, volumen |
| `0x6000/0x8000/0xA000` | Konami4 | Idem |
| `0x6000/0x6800/0x7000/0x7800` | ASCII8 | Idem |
| `0x6000/0x7000` | ASCII16 | Idem |
| `0x7FFE / 0xBFFE` | SCC+: registro de modo | Solo el bit 5 (modo SCC+) está implementado; los de deformación no |
| `0xFFFF` | Registro de slot expandido | En los slots 0 y 3, que están expandidos |

## Lo que NO hay

Sin puerto de casete (el bit 7 del PSG está fijo a 1), sin impresora (0x90/0x91), sin
puerto de la MSX-AUDIO (0xC0-0xC3), sin OPL4 (0x7E/0x7F, 0xC4-0xC7), sin puertos del
turbo R (0xA7, 0xE4-0xE7). El software que los sondea recibe 0xFF y sigue.
