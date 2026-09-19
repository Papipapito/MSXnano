# 01. Arquitectura

Todo el MSX vive en un GW2AR-18 (Gowin, familia GW2A, 20.736 LUT4, 46 bloques de BSRAM,
8 MB de SDRAM en la propia placa). Este capítulo es el mapa: qué hay, dónde está y cómo
se relaciona.

## Linaje

```
ESE-MSX / OCM (1chipMSX)        ← el core original de KdL y compañía, en VHDL
   └─ MSXgoauldSD (jabadiagm)   ← portado al Tang Nano 20K, enchufado a un MSX real
        └─ MSXnano (este repo)  ← autónomo: sin MSX debajo, BIOS y periféricos dentro
             └─ MSXimus         ← ampliado en la Tang Console 60K
```

De ahí la mezcla de lenguajes: el **VDP, el PSG, el SCC, el Z80 y la E/S conmutada son
VHDL** (herencia OCM), y **todo lo que se añadió después es Verilog** (`top.v`, memoria,
megaram, SD, companions).

## Relojes

| Reloj | Frecuencia | De dónde | Qué mueve |
|---|---|---|---|
| `clk_27m` | 27 MHz | cristal de la placa | VDP (pixel), UART WiFi |
| `clk_54m` | 54 MHz | PLL ×2 | **dominio de la CPU**: Z80, bus, memoria del lado CPU, companions |
| `clk_108m` | 108 MHz | PLL ×4 | controlador de SDRAM |
| `clk_135m` | 135 MHz | PLL del VDP | serializador TMDS del HDMI (27 × 5) |

El Z80 no corre a 54 MHz: corre a **3,6 MHz** (108 MHz / 30) mediante un *clock enable*
(`clk_enable_3m6_54`). Es la tradición del OCM: un 0,57 % más rápido que los 3,579545 de
un MSX real, imperceptible. El **turbo** conmuta a un divisor /20 → 5,4 MHz, y un
*period swallow* se traga ciclos hasta dejarlo en **5,369318 MHz exactos** (3,579545 × 1,5,
lo que hace un Panasonic). La conmutación es *glitch-free*: nunca entrega dos enables
seguidos al Z80, y está probada en `tools/turbo_cadence_equiv` (testbench que replica la
lógica verbatim y hace toggles en todas las fases). Así el VDP y el sonido no se enteran
del turbo.

La única frontera de dominio delicada es **CPU (54) ↔ SDRAM (108)**, en `memory.v`, con
un árbitro que reparte los ciclos entre el Z80 y el VDP (la VRAM también vive en la
SDRAM). Ha dado guerra: ver [06. Síntesis y timing](06-sintesis-timing.md).

## Módulos

Lo que compila `build.tcl`, agrupado:

| Bloque | Ficheros | Lenguaje | Notas |
|---|---|---|---|
| **Top** | `top.v` (~2.900 líneas) | Verilog | Slots, E/S, config, mezclador de audio, companions. Es donde está el mapa de la máquina |
| **CPU** | `G80A/` (T80) | VHDL | El Z80 de OCM con los estados de espera de M1 (`ENABLE_M1_WAIT`) y de escritura (`ENABLE_WAIT`) que lo dejan a la velocidad de un MSX real |
| **VDP** | `tn_vdp_v3_v9958/src/vdp/*.vhd`, `v9958_top.v`, `hdmi/` | VHDL + SV | V9958 de OCM + salida HDMI (TMDS, audio empotrado) |
| **Memoria** | `memory.v`, `src/gowin/clk_108p.v` | Verilog | Controlador de SDRAM de 8 MB: RAM del mapper, VRAM y Megaram, con árbitro CPU/VDP |
| **Megaram** | `megaram.v` | Verilog | 2 MB, cuatro mappers (Konami4, KonamiSCC, ASCII8, ASCII16) |
| **Audio** | `PSG_YM2149/`, `jtopl/` (OPLL), `ocm/scc_wave2.vhd`, `psg_filter.v`, `ocm/lpf.vhd` | VHDL + Verilog | PSG, OPLL, 2×SCC+, filtro del PSG, mezcla estéreo en `top.v` |
| **SD** | `wondertang/sd_reader.sv`, `sdcmd_ctrl.sv`, `crc16.v`, `dpram.v` | SV | Lector SPI de la WonderTANG; Nextor lo maneja por puertos |
| **Flash** | `flash_rw.v` | Verilog | Lee el pack de BIOS por streaming al arrancar y escribe el bloque de configuración |
| **Companions** | `kbd_uart_rx.v`, `msx_mouse.v` | Verilog | Teclado/joystick por UART desde el RP2040; ratón MSX |
| **WiFi** | `ocm/wifi_lite.vhd`, `ocm/uart_lite.vhd` | VHDL | UART a 859372 baudios en los puertos 0x06/0x07 (protocolo ESP UNAPI) |
| **E/S conmutada** | `ocm/swioports.vhd` | VHDL | Los puertos 0x40-0x4F del OCM (dispositivo, turbo Panasonic, config goauld) |
| **Otros** | `ocm/rtc.v`, `ocm/kanji.v`, `ws2812.v`, `denoise/`, `monostable/` | | RTC, kanji, LED RGB de la placa, filtros de entrada |

Lo que hay en el árbol pero **no** compila: `fpga/bl616/` (el companion antiguo, retirado
en la v2.0) y `fpga/src/usb/` (su lado FPGA). Se conservan como referencia.

## Defines de compilación

En la cabecera de `top.v`. Todos activos en la v2.0:

| Define | Qué activa |
|---|---|
| `ENABLE_V9958` | El VDP (sin él no hay vídeo) |
| `ENABLE_BIOS` | La BIOS desde el pack de flash |
| `ENABLE_SOUND` | PSG, OPLL, SCC y mezclador |
| `ENABLE_MAPPER` | El mapper de RAM de 4 MB |
| `ENABLE_SCAN_LINES` | El ajuste de scanlines |
| `ENABLE_SDCARD` | El lector SD y el cargador de flash |
| `ENABLE_CONFIG` | El bloque de configuración persistente (Ajustes) |
| `ENABLE_WAIT` | Un estado de espera extra en `MREQ`+`WR` |
| `ENABLE_M1_WAIT` | Un estado de espera por cada `M1`: **el freno que lo deja a velocidad de MSX real** |
| `ENABLE_WIFI` | La UART del ESP |

Quitar defines para ganar sitio es tentador y **no funciona**: se probó (la "dieta") y
rutó peor. Ver [06](06-sintesis-timing.md).

## El flujo de arranque

1. La FPGA carga el bitstream desde la flash (`0x000000`).
2. `flash_rw.v` lee el **pack** desde `0x200000` y lo copia por streaming a la SDRAM:
   BIOS, sub-ROM, Nextor, kanji, WiFi, logo, menú y los 6 bytes de configuración.
3. Los 6 bytes de config siembran los ajustes (turbo de arranque, menú, scanlines...).
4. Se suelta el reset del Z80. Arranca la BIOS → logo → menú o DOS.

Por eso **el core y el pack van emparejados**: el RTL sabe en qué offset del pack está
cada cosa (está cableado, no hay índice). Ver [04. El pack](04-pack-bios.md).

## Dónde mirar para cada cosa

| Quiero entender... | Empieza por |
|---|---|
| Qué hay en cada slot y página | `top.v`, los `*_req` (líneas ~1290-1350 y ~1480-2490) |
| Cómo se lee un puerto de E/S | `top.v`, el mux de `cpu_din` (~línea 700). **Es el camino crítico**: ver [06](06-sintesis-timing.md) |
| El turbo | `top.v` (~línea 975: `turbo`), `swioports.vhd`, `tools/turbo_cadence_equiv` |
| El teclado USB | `kbd_uart_rx.v` (la cabecera es el contrato), `rp2040/src/usbin.c` |
| El ratón | `msx_mouse.v` (la cabecera explica el protocolo) |
| La SDRAM y el árbitro | `memory.v` |
| Un mapper | `megaram.v` |
