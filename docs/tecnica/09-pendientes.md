# 09. Lo que queda abierto

El MSXnano se cierra en la v2.0 **con cosas sabidas y no hechas**. Están aquí para que
quien retome el proyecto (en esta placa o en otra) no las vuelva a descubrir. Ordenadas
de más a menos valor.

## 1. La interrupción de línea se dispara dos veces (VDP) — arreglo escrito, aparcado

**Bug confirmado, arreglo verificado en simulación, no cabe.** `vdp.vhd` abre la ventana
de disparo con dos comparaciones (`PREDOTCOUNTER_X = 255+25 OR = 511`) que caen en la
**misma** línea, porque el contador Y se registra un ciclo después del avance de línea
(`vdp_ssg.vhd:399/454`). Si la ISR lee `S#1` entre las dos ventanas, la segunda vuelve a
pedir interrupción y la rutina corre dos veces. Es el jitter de **R-Type** con el parche
de smooth-scroll, que en su día se achacó al parche. Ni openMSX, ni WebMSX, ni el OCM de
KdL ni TangCartMSX tienen el segundo término: es exclusivo del linaje goauld, y **el
MSXimus lo comparte**.

- Expediente: `fpga/tools/hsync_int_sim/` (README, testbench que barre el retardo del
  ack: el código actual da 2 interrupciones en una ventana de ~600 ciclos, con el parche
  1; y `vdp_hsync_int_fix.patch`, un cambio de una línea). Commit `633e58e`.
- Por qué se aparcó: **+47 CLS y `clk_54m` de 54,4 a 47,3-47,9 MHz**, determinista con
  cualquier `place/route_option`. Ver [06](06-sintesis-timing.md).
- Cómo retomarlo: aplicar el parche, correr el testbench, build con campaña de dados, y
  **R-Type con el parche es el juez**. En el MSXimus (chip mayor) es un cambio directo.

## 2. Los otros 25 hallazgos de la auditoría contra openMSX / WebMSX

Auditoría de julio de 2026 (34 hallazgos brutos, cada uno sometido a un verificador
adversarial: **26 confirmados**, 1 incierto, 7 refutados). Ninguno de los 25 restantes
rompe nada visible hoy; todos son de severidad baja o media. Por área:

| Área | Hallazgos confirmados |
|---|---|
| **Color** (`vdp_colordec.vhd`) | 👀 **La paleta de 3 bits se expande con ceros (`c*8`)** en vez de replicar bits: el blanco máximo es `0xE0`, todo sale ~12 % oscuro en HDMI. Trivial de arreglar y se nota en todo. El azul de 2 bits de SCREEN 8 se expande a 0,2,5,7 en vez de 0,2,4,7 (tiñe de azul los grises). YJK no se aplica en GRAPHIC6 |
| **Sprites** (`vdp_sprite.vhd`) | El bit 5S (S#0 bit 6) se activa aunque el flag F esté a 1 (openMSX cita Dragon Quest 2; el arreglo completo pide además que los bits 4-0 lleven el último sprite examinado). Colisiones falsas con sprites CC=1. Los flags siguen actualizándose con la pantalla apagada |
| **Comandos** (`vdp_command.vhd`) | LMCM no precarga el primer píxel (bloque desplazado un byte). LINE no corta al salirse por arriba (envuelve a Y=1023). Un cambio de modo con comando en vuelo deja CE colgado |
| **Registros / estado** (`vdp_register.vhd`, `vdp_hvcounter.vhd`) | Escribir R#19 borra el flag FH pendiente y leer S#1 lo borra aunque IE1=0. Escribir R#14 recarga el contador de VRAM entero. HR de S#2 desfasado media línea; VR de S#2 baja antes de tiempo |
| **PSG** (`YM2149.vhdl`, `top.v`) | El LFSR del ruido usa el tap bit0^bit2 en vez de bit0^bit3 (secuencia no maximal: periodo 114.681 en vez de 131.071). La lectura de registros por `0xA2` devuelve `0xFF` salvo R#14 |
| **SCC** (`scc_wave2.vhd`) | Frecuencia < 9 pone el puntero a 0 en vez de congelarlo. Del registro de deformación solo el bit 5 (los de frecuencia de 4/8 bits y rotación se ignoran) |
| **Mappers** (`megaram.v`, `top.v`) | **ASCII16 pierde el bit 6 del banco** (ROMs > 1 MB). Konami4 solo responde en los primeros 2 KB de cada página. La ventana del SCC solo en `0x9800-0x98FF` (el resto hasta `0x9FFF` lee `0xFF`). Los registros del mapper de RAM (`FC-FF`) no son legibles |

Cada arreglo es una build de 20 minutos con el reloj al límite: el criterio para el nano
era "solo lo que se vea", y ninguno se veía. En el MSXimus, donde hay sitio, son tareas
directas.

## 3. Higiene de código (medida: neutra para la síntesis)

De una revisión externa se validaron tres puntos, se aplicaron en una build de prueba y
se midió que **el netlist sale idéntico dígito a dígito** (misma Fmax, mismos CLS). Uno
ya está en `main` (`b8e35b1`: `swio_req` declarado dos veces en `top.v`); los otros dos
no se llegaron a commitear porque se cayeron con el experimento del punto 1:

- `memory.v` recibe 54 MHz en un puerto llamado `clk_27m` (herencia goauld; renombrar a
  `clk_cpu`, no cambiar el reloj).
- Seis asignaciones bloqueantes a `ff_flash_state` en el cargador de flash (más cinco en
  código comentado). Neutras: el `case` lee el estado antes de asignarlo.

Los dos "críticos" de esa misma revisión (múltiples drivers en `audio_sample`, contención
en el bus SDRAM) **son falsos**: `audio_sample` es una entrada de `v9958_top`, y el
`reg`-a-`z` + `assign` sobre el `inout` es el idioma estándar del tri-state.

## 4. Deuda de timing: el cruce de media fase `cpu1 → mem1`

El Z80 lanza en el flanco de bajada y la SDRAM captura en el de subida: 9,26 ns de
presupuesto y márgenes de décimas. **Cura conocida, no hecha**: registrar `RD`/`WR`/
dirección antes de `memory.v` (un ciclo), previa lectura de si su protocolo lo admite.
Alternativas: `set_multicycle_path` **solo si se demuestra** que el dato es estable más
de media fase (no asumirlo), o que la SDRAM capture también en bajada. Detalle en
[06](06-sintesis-timing.md). Es lo que convierte cada build en una campaña de dados.

## 5. La ñ (teclado español)

La BIOS internacional no tiene la ñ en la fuente ni en la tabla del teclado. La vía
apuntada: **reciclar la capa KANA** (tabla en `0FB6h` de la BIOS) y añadir el glifo en
`CGTABL` (`1BBFh`); el RP2040 mandaría la ñ como CODE + tecla. Es trabajo de pack (repo
`bios-msxnano-msximus`) más una línea en `keymaps.h`; no toca RTL.

## 6. SRAM de cartucho persistente

Los juegos con SRAM (`sram_cfg`, segmentos 252-255 de la Megaram) la pierden al apagar.
El MSXimus ya guarda la SRAM en la SD (bloque 5 del plan v3.5, 06/09/2026); en el nano
está **revisado y pendiente**. Hay 1 MB libre en la SDRAM (`0x600000`) para el lado FPGA
y el menú ya sabe escribir en la SD; falta el disparador (al salir del juego o por tecla).

## 7. Lo que se retiró y no vuelve

| Qué | Cuándo | Por qué |
|---|---|---|
| Cinta virtual TSX/CAS (`cas_stream`, `tape_uart`…) | v2.0 | El proyecto que la alimentaba se cayó. Vive en la Zynq del MSXimus (Z1.1) |
| Companion **ESP32-S3 con LCD (ESP32-1732S019)** | 09/2026 | Validado y luego **dañado** (el 3,3 V se hunde al arrancar la WiFi); descartado por el autor. El companion de pantalla es el **ESP32-C6** |
| BL616 (FPGA-Companion) | v2.0 | Las placas `3921` lo traían bloqueado; el RP2040 lo sustituye entero |
| ColecoVision / SG-1000 | v1.9 | Solo MSX |
| Compatible Mode | v1.9 | Vestigio del goauld que metía esperas |
| **OPL4 / MoonSound** | evaluado | No cabe en la 20K (ni con coprocesador). Está en el MSXimus |
| **V9968** | evaluado | ~2,5× el V9958 y 2 PLL: no cabe. Está en el MSXimus |
| Frontend gráfico de carátulas | diseño | `fpga/GRAPHICAL_FRONTEND_DESIGN.md`; pensado para el 60K |
| Salida HDMI a 720p con escalador | evaluado | Cosmético; CLS al límite |
| Audio por Bluetooth | evaluado | A2DP necesita BT clásico (ESP32 clásico o RP2350-W) y añade 100-200 ms de latencia |

## 8. Mappers que no hay

Solo Konami4, Konami SCC, ASCII8 y ASCII16 (los dos ASCII con SRAM en los segmentos
252-255). No hay mapper de R-Type (el cartucho Irem original), ni Cross Blaim, ni Harry
Fox, ni el de MSX-DOS2, ni Manbow 2 / Konami Ultimate. Los juegos con uno de esos
mappers solo van si existe una conversión de la escena a Konami SCC o ASCII. Cada mapper
nuevo son unas decenas de CLS en `megaram.v` más un nivel en el decodificador; hoy no
hay hueco.

## 9. Sin probar en placa

- El **pack con Nextor 3 beta** en el nano (validado en el MSXimus).
- Teclados con **hub interno** y algunos mandos XInput concretos.

## Cómo retomar el proyecto

1. Leer [06](06-sintesis-timing.md) entero antes de tocar nada.
2. Compilar el árbol intacto con la 1.9.12.03 y confirmar que reproduce ~89 % CLS y
   `clk_54m` > 54 MHz (con campaña de 3 dados).
3. Elegir **un** cambio. Simularlo ([07](07-simulacion.md)). Build. Kit de regresión.
4. Si el reloj cae: no es el cambio, es que no hay margen. Volver aquí.
