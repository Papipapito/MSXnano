# El fuente del menú ya NO vive aquí

El **repositorio oficial de las BIOS de las dos máquinas** (MSXnano y MSXimus)
es **`bios-msxnano-msximus`**. Allí está el fuente único (`src/menu_main.asm`),
que genera las cuatro variantes con las banderas `MSXIMUS` / `BIOS_MENU` /
`BIOS_ESP32` / `BIOS_FH`, y allí se montan los packs con `tools/hacer_packs.py`.

Lo que había en esta carpeta era una **copia bifurcada y obsoleta** (8.504 líneas
frente a 9.393): le faltaban `sd_cmd_go` (la carrera del strobe de la SD),
`INIT_VEC`/`MIR16` (el lanzamiento de ROMs planas) y la verificación CRC32 de las
descargas. Se eliminó el 02/09/2026 para que no hubiera dos menús con el mismo
nombre y distinto contenido.

Los documentos de diseño que estaban aquí se movieron a `bios-msxnano-msximus/docs/`:
`LAUNCH_SCREEN_DESIGN.md`, `M2_DESIGN.md` y `SRAM_PERSIST_CONSOLE60K_DESIGN.md`.

## Por qué queda un .bin

`fpga/src/rom/build.bat` concatena `..\msxnano_menu\fm_logo_menu.bin` para armar
el pack. **Ese binario lo genera el repo de BIOS**; aquí solo está la copia que
consume el build. Para regenerarlo:

```bash
cd ../../../../bios-msxnano-msximus && ./build.sh
# y copiar out/bios-Menu_msxnano.bin sobre fm_logo_menu.bin
```
