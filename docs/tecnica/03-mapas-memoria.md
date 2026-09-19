# 03. Mapas de memoria

Tres mapas distintos que conviene no mezclar: lo que ve el **Z80** (slots), dónde vive
cada cosa en la **SDRAM** de 8 MB, y qué hay en la **flash SPI** de la placa.

## Lo que ve el Z80: slots

Los slots 0 y 3 están expandidos; el 1 no existe (a menos que la config lo habilite:
*Slot 1* en Ajustes) y el 2 es la Megaram.

| Slot | Página 0 (0000) | Página 1 (4000) | Página 2 (8000) | Página 3 (C000) |
|---|---|---|---|---|
| **0-0** | BIOS MSX2+ | BIOS | — | — |
| **0-1** | — | Driver kanji | Driver kanji | — |
| **0-2** | — | ROM WiFi (UNAPI ESP) | — | — |
| **0-3** | — | Logo (16 KB) | — | — |
| **1** | — | — | — | — |
| **2** | Megaram | Megaram | Megaram | Megaram |
| **3-0** | Mapper 4 MB | Mapper | Mapper | Mapper |
| **3-1** | Sub-ROM | MSX-MUSIC + **menú** | — | — |
| **3-2** | — | Nextor | Nextor | — |
| **3-3** | — | — | — | — |

Notas:

- La **BIOS** es la del MSXgoauld con el parche `int_fix` (ver [04](04-pack-bios.md)).
- **Nextor 2.1.4** en el 3-2 es lo que ven `NEXTOR.SYS` y las utilidades; es el slot que
  hay que dar a `DRVTEST` y compañía.
- El **mapper** es de 4 MB = 256 segmentos de 16 KB. Nextor lo detecta como "4096 KB".
- La **Megaram** de 2 MB responde en las cuatro páginas; el mapper que tenga activo decide
  qué ventanas se ven (ver [02](02-puertos-es.md), memoria mapeada).
- El **menú** va pegado a la ROM de MSX-MUSIC en el 3-1 (16 KB entre los dos) y el
  **logo** de arranque en el 0-3. Ninguno se ve una vez en el DOS: el menú hace su
  trabajo y se retira.
- Con *Slot 1* activado en Ajustes, el mapper aparece además en el slot 1 (`mapper_req12`
  en `top.v`): sirve para software antiguo que solo busca RAM en los slots 1-2.

## La SDRAM de 8 MB

Es un chip de 64 Mbit sobre la placa, con bus de datos de 16 bits. El core lo trata como
8 MB de bytes (`ram_addr[22:0]`) y lo reparte así (el comentario de `top.v` línea ~1540
es la fuente):

| Rango | Tamaño | Qué | Banco |
|---|---|---|---|
| `0x000000 – 0x3FFFFF` | 4 MB | **Mapper de RAM** | A + B |
| `0x400000 – 0x5FFFFF` | 2 MB | **Megaram** | C |
| `0x600000 – 0x6FFFFF` | 1 MB | libre | — |
| `0x700000 – 0x73FFFF` | 256 KB | Kanji JIS1 + JIS2 | D |
| `0x740000 – 0x75FFFF` | 128 KB | Nextor (disco WonderTANG) | D |
| `0x760000 – 0x767FFF` | 32 KB | BIOS MSX2+ | D |
| `0x768000 – 0x76BFFF` | 16 KB | Sub-ROM | D |
| `0x76C000 – 0x76FFFF` | 16 KB | MSX-MUSIC + menú | D |
| `0x770000 – 0x777FFF` | 32 KB | Driver kanji | D |
| `0x778000 – 0x77BFFF` | 16 KB | ROM WiFi (esp8266e) | D |
| `0x77C000 – 0x77FFFF` | 16 KB | Logo | D |
| `0x7C0000 – 0x7FFFFF` | 256 KB | **VRAM** del V9958 (128 KB útiles, ampliable) | D |

Tres cosas que se deducen del mapa:

1. **El pack se copia entero a `0x700000`**: el cargador de flash escribe desde
   `RAM_START_ADDRESS + 1` en adelante, y por eso el offset de cada ROM en el pack es
   exactamente su dirección menos `0x700000`. Si se mueve algo en el pack hay que mover
   también el `ram_addr` correspondiente en `top.v`.
2. **La VRAM comparte chip con todo**: de ahí el árbitro CPU/VDP en `memory.v` y por qué
   el VDP tiene prioridad (un píxel perdido se ve; un ciclo del Z80 retrasado no).
3. **Queda 1 MB libre** (`0x600000-0x6FFFFF`). No es sitio para lógica, es sitio para
   datos: por ejemplo, una SRAM de cartucho persistente ([09](09-pendientes.md)).

Los "bancos" A-D son los cuatro bancos internos de la SDRAM. El reparto no es casual:
el controlador puede tener una fila abierta por banco, así que la RAM del mapper (A+B),
la Megaram (C) y las ROMs + VRAM (D) no se pisan las filas entre sí.

## La flash SPI de la placa

Es la flash de configuración de la Tang Nano 20K (la misma que carga el bitstream), de
8 MB, y el core la lee por SPI en el arranque:

| Dirección | Tamaño | Qué | Cómo se graba |
|---|---|---|---|
| `0x000000` | ~1 MB | **Bitstream** (`msxnano.fs`) | Gowin Programmer, *External Flash Mode* |
| `0x200000` | 512 KB + 6 | **Pack de BIOS** + firma + config | Gowin Programmer, *exFlash C Bin Erase, Program thru GAO-Bridge*, dirección `0x200000` |
| `0x280000` | 6 bytes | Firma `AB` + `config1` + `config2` + turbo de arranque + `FF` | Lo escribe el core al hacer *Save & Restart* |

El cargador (`flash_rw.v` + la máquina de estados de `top.v`, `FLASH_START_ADDRESS`)
lee `GOAULD_ROM_SIZE = 512·1024 + 6` bytes seguidos. Los 6 últimos son la configuración
persistente: la firma `41 42` ("AB") dice que el bloque es válido; si no está, se cargan
los valores por defecto (`CONFIG1_DEFAULT`, `CONFIG2_DEFAULT`).

Esto tiene una consecuencia práctica: **regrabar el pack borra los ajustes** (el
Programmer borra el sector entero). No es un fallo, es que la config vive pegada al pack.

## Ejemplo: seguir una lectura de la BIOS

`LD A,(0000h)` con el slot 0-0 en la página 0:

1. El Z80 saca `bus_addr = 0x0000`, `MREQ`, `RD`.
2. `top.v` resuelve slot primario 0 (PPI A8) y secundario 0 (`0xFFFF` del slot 0) →
   `bios_req = 1`.
3. `ram_addr = {8'b11101100, bus_addr[14:0]}` = `0x760000`.
4. `memory.v` pide el byte a la SDRAM en el hueco que le deja el VDP; el Z80 espera con
   `wait_n` si hace falta.
5. El byte vuelve por el mux de `cpu_din`.
