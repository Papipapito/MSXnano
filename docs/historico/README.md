# Histórico: expedientes, diseños y código retirado

Documentos y directorios que **no describen la v2.0** pero explican cómo se llegó a ella.
Se dejan donde están (muchos los referencian commits y scripts); esto es el índice.

## Expedientes de cazas de bugs

| Documento | Qué cuenta |
|---|---|
| [`fpga/tools/hsync_int_sim/README.md`](../../fpga/tools/hsync_int_sim/README.md) | La interrupción de línea del VDP que se dispara dos veces: diagnóstico, testbench, parche y por qué está aparcado. Commit `633e58e` |
| [`tools/scctest/opcheck/BUG22_MG2_bladeba.md`](../../tools/scctest/opcheck/BUG22_MG2_bladeba.md) | Nota de traspaso de la caza del bug #22 (Metal Gear 2 glitcheando en partida), con lo aprendido del repo de bladeba. Resuelto en la v1.8 (R#13 del menú) |
| [`fpga/AUDIT_PRE_PORT_60K.md`](../../fpga/AUDIT_PRE_PORT_60K.md) | Auditoría del core antes de portarlo a la Tang Console 60K (base v1.8/v1.9): código muerto heredado, 6 bugs latentes en rutas de error, y los cuatro frentes del port (SDRAM → DDR3, relojes, constraints, companion). Es el punto de partida del MSXimus |

## Diseños no implementados en el nano

| Documento | Qué es |
|---|---|
| [`fpga/GRAPHICAL_FRONTEND_DESIGN.md`](../../fpga/GRAPHICAL_FRONTEND_DESIGN.md) | Frontend gráfico de carátulas estilo EmuELEC, dibujado por el MCU y compuesto en la FPGA. Investigado en julio de 2026; pensado para el 60K. `tools/frontend_demo/sample_sd/` tiene el `INDEX.DAT` + `COVERS.PAK` de muestra |
| [`fpga/src/msxnano_menu/LEEME.md`](../../fpga/src/msxnano_menu/LEEME.md) | Por qué el fuente del menú ya no vive en este repo (está en `bios-msxnano-msximus`) y por qué queda un `.bin` |

## Código en el árbol que no compila en la v2.0

| Directorio | Qué era | Estado |
|---|---|---|
| [`fpga/bl616/`](../../fpga/bl616/README.md) | Firmware FPGA-Companion del BL616 (teclado/mando por SPI) y sus `.ini` de flasheo, con la guía del M0S Dock externo | Retirado en la v2.0 (RP2040). Se conserva para quien tenga una placa anterior a la `3921` y quiera la v1.9 |
| `fpga/src/usb/` | El lado FPGA del BL616: `fpga_companion.v`, `hid.v`, `mcu_spi_new.v`, `sys_ctrl.v`, `usb_keyboard_msx.vhd` | Fuera de `build.tcl` desde `8ce5b74` |
| `fpga/msx_debug/timing_debug.v` | Diagnóstico de tiempos del goauld original | Fuera de producción (costaba 3 % de CLS) |
| `fpga/pulse_min_max/` | Utilidades de medida de pulsos del goauld | Sin usar |
| `fpga/src/rom/` | `build.bat` y los rellenos `*_ff.bin` para montar el pack a la antigua | Sustituido por `hacer_packs.py` del repo de BIOS; sigue valiendo si tienes las 10 ROMs |
| `tools/megaram_equiv/megaram_v16.v`, `megaram_v17.v` | Versiones históricas de la Megaram | Referencia para comparar |

## Releases y ficheros entregados

- `files/<fecha>/` guarda cada pareja `.fs` + `.bin` entregada, con el dado en el nombre
  o en el commit. La v2.0 es `files/20260904/msxnano_20260904_48_v20_sinCinta.*`.
- `bin/` lleva el `.fs` y el pack de la release vigente.
- Las notas de cada versión: [`tecnica/08-changelog.md`](../tecnica/08-changelog.md) y
  [GitHub → Releases](https://github.com/Papipapito/MSXnano/releases).

## Ramas y repos que ya no están

`MSXNano_SCC`, `MSXNano_Menu`, `Menu`, `dev`, `MSXnano-cinta` y `_MSXnano_dev_ref` se
fusionaron o se eliminaron; **`main` es la única rama**. Los repos `ESP32-UNAPI-MSX` y el
fork `ESP32-UNAPI-Firmware` se retiraron: el firmware del ESP vive en
[`ESP32-for-FPGA`](https://github.com/Papipapito/ESP32-for-FPGA). Todo lo borrado sigue en
el respaldo privado `MSXnano-backup`.
