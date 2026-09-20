# 07. Simulación y bancos de prueba

Regla del proyecto: **nada se da por bueno sin pasar por Icarus** antes de gastar 20
minutos de síntesis y un viaje a la placa. Este capítulo lista lo que hay y cómo se
corre.

## Entorno

- **Icarus Verilog 12** (`iverilog -g2012` + `vvp`) en **WSL, distro Ubuntu-24.04**
  (`wsl -d Ubuntu-24.04`). No es la distro por defecto del PC: en la otra no está.
- `gtkwave` para ondas cuando hace falta.
- Icarus **no simula VHDL**. El VDP, el Z80, el PSG y el SCC son VHDL, así que los
  bancos que los tocan **transcriben** el trozo relevante a Verilog (es lo que hace
  `hsync_int_sim`) o prueban el módulo Verilog que los rodea. No hay GHDL instalado.
- El bitstream real sale **solo** de Gowin (`gw_sh.exe build.tcl`). Un `yosys` genérico
  serviría de *sanity check* de sintaxis, nunca para el timing.
- Cada banco imprime `RESULT: PASS` o `RESULT: FAIL …` y sale con código ≠ 0 al fallar:
  se pueden encadenar en un script.

## Bancos que hay

| Directorio | Prueba | Cómo se corre |
|---|---|---|
| `tools/megaram_equiv/` | **Lógica de `megaram.v`** (`megaram_scc`): decodificación de los cuatro mappers (Konami4 / SCC / ASCII8 / ASCII16), el banco 0 fijo del Konami4, el gating de SRAM por `sram_cfg`, las páginas de SRAM (segmentos 252-255) y el registro de modo SCC+ (`BFFE`). Lógica pura de un reloj, sin SDRAM ni PLL. `megaram_v16.v`/`megaram_v17.v` son las versiones históricas para comparar a mano (la regresión de MG2: registro de banco en `0x8000` pisado por el sondeo de RAM de la BIOS) | `bash run.sh` |
| `tools/turbo_cadence_equiv/` | **Conmutación glitch-free del turbo**: replica verbatim los divisores /30 y /20 + *period swallow* y el mux `clk_enable/clk_falling`; hace toggle de `turbo` en muchísimas fases y comprueba la invariante que el T80 necesita (nunca dos ENABLE ni dos FALLING seguidos, ni los dos en el mismo ciclo) | `iverilog -g2012 turbo_tb.v && vvp a.out` |
| `tools/mouse_sim/` | **Ratón MSX** (`msx_mouse.v`): imita la rutina del MSX (mover el pin 8, leer el PSG entre movimientos) contra el protocolo de openMSX. Vigila: delta negado, ciclo alterno a ceros, timeout que resincroniza, movimientos lentos con sensibilidad alta, botones activos a bajo | `iverilog -g2012 tb_msx_mouse.sv ../../fpga/src/msx_mouse.v && vvp a.out` |
| `fpga/tools/hsync_int_sim/` | **Interrupción de línea del VDP**: transcribe los tres trozos de VHDL implicados y barre el retardo del ack. Demuestra el disparo doble y que el parche lo cura. Ver su `README.md` | `iverilog -g2012 tb_hsync_int.v && vvp a.out` |
| `tools/scctest/` | **`SCCTEST.COM`** (asMSX, 557 B): se ejecuta **en el MSX**, no en el PC. Detecta SCC/SCC+ por slot verificando que la ventana conmuta con el banco (anti falso-RAM), activa la Megaram por E/S conmutada (`#D4/#0F`; en un arranque normal nadie la activa) y toca un tono por chip | Copiar a la SD y ejecutar desde DOS |
| `tools/scctest/opcheck/` | **`fat32_emu_test.py`**: mini-intérprete Z80 en Python que ejecuta los **bytes reales** del menú (vía `.sym`) contra una imagen FAT32/FAT16 sintética, interceptando `sd_read`. Probó `mount`/`clus2lba`/`fatnext`/`scan`/`load_rom` byte a byte antes de tocar la placa. `BUG22_MG2_bladeba.md` es el expediente de aquella caza | `python fat32_emu_test.py` |
| `tools/frontend_demo/` | `sample_sd/` con un `INDEX.DAT` + `COVERS.PAK` de ejemplo para el frontend gráfico de carátulas (diseño en `fpga/GRAPHICAL_FRONTEND_DESIGN.md`, no implementado en el core) | — |

## Qué NO está cubierto por simulación

- El **VDP completo** y el **Z80**: VHDL, sin GHDL. Se confía en el linaje OCM y en
  los juegos de prueba (abajo).
- El **controlador de SDRAM** y el árbitro CPU/VDP: no hay modelo de la SDRAM en el
  repo. Los cruces de dominio se vigilan por timing estático, no por simulación.
- El **HDMI**: se prueba con un monitor.
- La **UART del RP2040**: `kbd_uart_rx.v` no tiene banco propio; se probó en placa. Si
  se toca el protocolo, escribir uno antes (es un receptor 8N1 y una FSM de opcodes:
  media hora).

## Verificación en placa: el kit de regresión

Lo que hay que pasar antes de dar un `.fs` por bueno, en este orden:

| Prueba | Qué vigila |
|---|---|
| Arranque en frío, logo, menú, `Save & Restart` | Cargador de flash, config persistente |
| **Metal Gear 2 / SD Snatcher** (Konami SCC, dos fases) | Megaram, bancos, SCC. *Test de estrés obligatorio* desde la saga MG2 |
| **R-Type** (con y sin el parche de smooth-scroll) | VDP, interrupción de línea (el jitter es conocido, ver [09](09-pendientes.md)) |
| **Parodius**, **Aleste 2** | Sprites, scroll, ASCII8/16 |
| `SCCTEST.COM` | Los dos SCC y el estéreo |
| `DRVTEST` de Nextor apuntando al slot **3-2** | La SD |
| Un `.DSK` de 720 KB montado con `EMUFILE` | Nextor + `NEXTOR.EMU` |
| Teclado + mando + ratón por un hub, desenchufar la Pico en caliente | Companion y vigilante de 1 s |
| Turbo por F11 y por `OUT &H41` | Cadencia sin glitches (si se rompe, el Z80 se cuelga al instante) |
| WiFi: `W` en el menú (escanea redes) y una descarga de File-Hunter | UART del ESP y el CRC32 de las descargas |

**Alimentación**: probar con una fuente USB de solo corriente. El USB de un PC puede
falsear las pruebas (arranques que fallan por corriente, o JTAG que interfiere).

## Cómo se cazó cada cosa (para cuando toque cazar algo)

- **Discrepancia sim ↔ placa** → primero, registros sin valor inicial (known issue de
  Gowin; ver [06](06-sintesis-timing.md)); segundo, un `create_clock` sobre una red
  barrida que dejó informes rancios.
- **Un juego que se cuelga al cambiar de nivel** → `megaram_equiv` con los accesos que
  hace ese juego (se sacan con openMSX y un breakpoint en las escrituras al mapper).
- **Algo del menú** → `fat32_emu_test.py`: ejecuta el binario real, no una copia.
- **Un puerto que el Z80 lee mal** → antes de tocar el mux de `cpu_din`, leer la lección
  del commit `4cb65a4` en [06](06-sintesis-timing.md).
