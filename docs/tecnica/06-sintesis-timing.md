# 06. Síntesis y timing

Este es el capítulo que explica **por qué el proyecto se cierra en la v2.0**: el chip
está lleno y el reloj de la CPU cierra por el margen que le da el emplazador, no el
diseño. Todo lo de aquí está **medido**, no estimado; los commits citados llevan las
tablas.

## Herramienta

| | |
|---|---|
| Chip | GW2AR-18C (`GW2AR-LV18QN88C8/I7`), Tang Nano 20K |
| Gowin EDA | **1.9.12.03 Standard** desde la v2.0 (antes 1.9.11.03 Education) |
| Flujo | `cd fpga && gw_sh.exe build.tcl` → `impl/pnr/project.fs` |
| Esfuerzo | `set_option -place_option 2 -route_option 2` |
| Constraints | `fpga/tang9k.cst` (pines), `fpga/Z80_goauld.sdc` (relojes) |

`build.tcl` lleva `set_device -name GW2AR-18C …`: la 1.9.12 aborta sin el `-name`
(dispositivo ambiguo) y la 1.9.11 lo acepta, así que compila con las dos.

**Por qué se cambió a la 1.9.12** (04/09/2026, campaña de 13 builds, mismo RTL y mismo
`.sdc`, única variable el ejecutable): con la 1.9.11.03 el diseño sin BL616 daba
**46,2-51,0 MHz en 8 tiradas** para un `clock_54m` que exige 54 → fallaba siempre. Con la
1.9.12.03: **56,4 / 54,3 / 56,4** → pasa. Y el control (el mismo diseño con el BL616,
que sí cerraba con la 1.9.11 a 54,9) sube a 59,7 con la 1.9.12: es el emplazador/rutador,
no una casualidad de tirada. La 1.9.12 reporta además un hold `clock_audio → clock_27m`
de −1,3 ns que la 1.9.11 callaba; sale idéntico en el control, es un cruce asíncrono y
no bloquea.

## Ocupación de la v2.1 (dado 999917)

| Recurso | Uso | |
|---|---|---|
| **CLS** | **9.188 / 10.368** | **89 %** ← el cuello |
| Logic (LUT+ALU) | 15.136 / 20.736 | 73 % |
| Registros | 7.976 / 15.915 | 51 % |
| BSRAM | 14 / 46 | 31 % |
| DSP | 11 % | |
| PLL | 2 / 2 | 100 % |

El **CLS** (el bloque físico que agrupa LUTs y registros) es el recurso que se agota,
y al 89 % el rutador ya trabaja congestionado. (La tabla que traía la v2.0 —9.212 CLS,
15.741 de lógica, 8.214 registros, 16 BSRAM— no sale de su propio árbol: la v2.0
reconstruida el 29/09 con la misma herramienta y el mismo dado da 9.224 / 15.229 / 7.976 / 14.) Los dos PLL también están agotados: nada
que necesite otro reloj cabe sin reorganizar el árbol.

## Los relojes

| Reloj | Periodo | Fmax v2.0 | Notas |
|---|---|---|---|
| `clock_27m` | 37,0 ns | ~77 MHz | VDP, holgado |
| **`clock_54m`** | **18,5 ns** | **v2.0: 48,9 – 61,7 según tirada (3 de 6 cierran); v2.1: 55,1 – 62,5 (6 de 6)** | **CPU, bus, mux de `cpu_din`, cruce a la SDRAM** |
| `clock_108m` / `108i` | 9,26 ns | ~169 MHz | SDRAM |
| `clock_audio` | 3,6 MHz | — | Cruce asíncrono |

`clock_54m` es el que manda. Cierra con un margen que ha ido de **+0,37 ns** (referencia
de agosto, "por los pelos") a **+7,66 ns** en el dado entregado, pasando por negativo en
la mitad de las tiradas intermedias.

## Los dos caminos que mandan

### 1. El mux de `cpu_din`

La lectura del Z80 era una **cadena de prioridad** larguísima (~31 ternarios): cada
puerto, cada slot, cada periférico era un nivel más. Desde la v2.1 va **por grupos** (ver
abajo) al final de `top.v`. Ya iba con 20 ns de lógica contra
18,2 disponibles. La lección está en el commit `4cb65a4` (27/08/2026):

| Build | `clock_54m` | |
|---|---|---|
| referencia | 54,367 MHz | pasa por los pelos |
| + arreglo del PPI (`0xAB` y relectura de `0xAA`) | 44,642 | falla, 26 endpoints |
| + PPI + ratón | 44,242 | falla, 33 endpoints |
| + mux fusionado | 53,953 | falla, 2 endpoints |
| **+ puerto 2 registrado** | **58,921** | **pasa, más margen que la referencia** |

Los dos arreglos, sin coste funcional: (a) **un solo decodificador** para `0xA9`/`0xAA`
(comparten término y se eligen por `bus_addr[1]`; el XOR de los dos bits bajos excluye
`0xA8` y `0xAB`, que se sirven más abajo en la cadena — capturarlos aquí habría dejado
mudo el puerto A y con él la selección de slots), y (b) **el valor del puerto 2 del PSG
se calcula en un registro** (`psg_port2_q`) en vez de dentro del mux, lo que saca de la
cadena toda la lógica combinacional del ratón. Retrasarlo un ciclo es invisible: entre el
OUT del strobe y el IN siguiente pasan ~280 ns.

**Regla:** cualquier cosa nueva que el Z80 tenga que leer entra **registrada**, nunca como
un nivel más del mux.

**v2.1 (29/09/2026): el mux por grupos.** Idea de MSXHeroTN (terracide303, `e48a96f`).
Las fuentes van en 5 grupos que son tramos seguidos de la lista original; cada grupo saca
su *acierto* (el OR exacto de sus condiciones) y su valor (su minicadena, en el mismo
orden) en paralelo, y luego los grupos se resuelven entre sí en orden. Profundidad = grupo
más largo + número de grupos (~11) en vez de ~31. La **prioridad es idéntica** —gana la
primera condición cierta, sin suponer que las decodificaciones se excluyan—, solo se
juntan condiciones vecinas con el mismo valor y se quitan `slot0/slotx` (daban `FF`, que
es el defecto). Demostrado con `fpga/tools/cpudin_equiv/verify.py`: yosys (miter + SAT)
con los `define de la build y cinco combinaciones más, y 200.000 vectores en Icarus; tres
mutaciones a propósito (orden, acierto incompleto, grupos permutados) las caza. El bloque
va al final del módulo porque la cadena leía señales declaradas 2.000 líneas más abajo.

Medido con la 1.9.12.03, seis dados, la misma fuente salvo el mux (la v2.0 se reproduce
exacta: 61,655 / 60,567 / 51,366 con los dados de su campaña):

| Dado | v2.0 (cadena) | v2.1 (grupos) |
|---|---|---|
| 999961 | 61,655 | 57,952 |
| 999979 | 60,567 | 60,423 |
| 999983 | **51,366 falla** | 59,722 |
| 999953 | **48,890 falla** | 55,137 |
| 999931 | 54,220 (+0,22) | 55,901 |
| 999917 | **51,033 falla** | **62,494 ← entregado** |
| | **3 de 6**, media 54,6 | **6 de 6**, media 58,6 |

Los CLS no cambian (media 9.197 frente a 9.198): aquí no libera área, como sí midió
MSXHeroTN en su árbol (−127). Lo que da es **estabilidad**: las tiradas malas de la v2.0
caían en caminos que salen de `cpu1/WR_n` (hacia `mem1/sdram_addr`, el camino 2, y
`state_wait`), que no se han tocado: con el mux más corto el emplazador tiene holgura
para no romperlos.

### 2. El cruce de media fase `cpu1 → mem1`

El Z80 lanza `WR_n`/dirección en el flanco de **bajada** de `clock_54m` y la SDRAM lo
captura en el de **subida**: solo hay **9,26 ns** de presupuesto, medio periodo. En el par
46 (validado en placa) ese camino tenía **+0,148 ns** de margen; cualquier recolocación
lo tumba. Es la **deuda real** del diseño, y la cura está identificada pero no hecha:
registrar `RD`/`WR`/dirección antes de entrar en `memory.v`, pagando un ciclo (hay que
comprobar que su protocolo lo admite). Los `set_multicycle_path` del `.sdc` cubren
`-to cpu1/...`, no este arco `-from cpu1 -to mem1`.

## Tres cosas contraintuitivas, medidas

1. **Quitar lógica NO mejora el timing.** Al extirpar el BL616 (−479 LUT, −353 FF,
   78 % → 75 % de lógica) `clock_54m` **bajó** de 54,9 a 46-51 MHz en 8 tiradas: sin
   presión de área el emplazador dispersa `cpu1` de `mem1` y el cruce de media fase se va
   a −1,0 ns. El mismo diseño con el BL616 vuelto a emplazar da 54,1 y 54,9. Corolario
   del mismo hallazgo en el MSXimus ("dieta" de periféricos que rutó peor).
2. **El F11 no costaba nada.** Una campaña entera atribuyó al toggle del turbo una caída
   de Fmax; sin F11 salían 47,7 y 49,7, con F11 48,7 y 51,0. No hay margen para nada,
   que es distinto.
3. **Un cambio determinista de +47 CLS tumba el reloj.** El arreglo de la interrupción de
   línea del VDP ([09](09-pendientes.md)) quita una comparación y aun así cuesta 47 CLS
   **con cualquier combinación** de `place/route_option` → `clock_54m` 54,4 → 47,3-47,9.
   No es lotería de emplazamiento: se probó y se descartó.

## Campañas de dados

Cuando el diseño cierra "según tirada", se hacen **campañas**: la misma fuente varias
veces cambiando una constante inerte para que el emplazador parta de otro sitio. En el
MSXnano el dado es el tope del contador `led_cnt` (el parpadeo del LED, `top.v` ~2778).
Desde la v2.1 **el repo lleva el dado entregado** (`999917`) y reconstruye el bitstream:
el `.bin` sale idéntico byte a byte y el `.fs` solo cambia en la línea de fecha de su
cabecera (comprobado el 29/09). Campaña del par 48, el entregado como v2.0:

| Dado | `clock_54m` | |
|---|---|---|
| 999983 | 51,366 (−2,634) | falla en `cpu1/WR_n → mem1/sdram_addr` |
| 999979 | 60,567 (+6,567) | pasa |
| **999961** | **61,655 (+7,655)** | **entregado** |

**1 de 3 falla.** El `.fs` publicado lleva el dado 999961; `main` tiene 999999, así que
**el repo no reconstruye byte a byte la release** (la reconstruye funcionalmente). Los
dados se apuntan en `files/<fecha>/` con cada pareja `.fs` + `.bin`.

Método para juzgar una tirada: mirar las **familias de reloj** de los endpoints
violados, no el total. Las familias `VideoDLClk/VideoDHClk → 108m` (VRAM → sprites) son
el suelo: salen igual en builds buenas y malas, y se ha comprobado que son un artefacto
de modelar registros de 27 MHz como relojes con latencia cero. Lo que importa es si
aparece una familia **nueva** y, sobre todo, si cae algo en **`clock_54m`**.

## Trampas de la herramienta

- **`create_clock` sobre una red que ya no existe** (barrida por la síntesis) → `run pnr`
  aborta con `TA2004` pero **sale con código 0** y deja los informes rancios de la build
  anterior. Mirar siempre la cola de `impl/pnr/project.log`.
- **`clock_108i` se define por `get_pins {clk_main/rpll_inst/CLKOUT}`**, no por la red
  `clk_108m`, que no existe tras sintetizar. Sin eso ~100 caminos SDRAM → CPU/VDP quedan
  fuera del análisis.
- Gowin **ignora `set_min_delay`**: mide, no arregla.
- Registros sin valor inicial pueden dar netlist ≠ HDL (known issue de los release notes
  de la 1.9.11 y 1.9.12). Pista al cazar discrepancias entre simulación y placa.
- `-verilog_std sysv2017` es obligatorio: hay `.sv` en el árbol (SD, HDMI).

## Por qué no hay más espacio (y qué se hizo para ganarlo)

Lo que ya se quitó para llegar aquí: el BL616 y su SPI (v2.0), la cinta virtual y sus
puertos de diagnóstico (v2.0), la depuración `timing_debug` de producción, la variante
"Compatible Mode" (v1.9), el menú clásico de cuatro opciones. Lo que se intentó y no
sirvió: quitar periféricos para "hacer sitio" (rutó peor, punto 1 de arriba).

Lo que queda: un 11 % de CLS que el rutador necesita para respirar, cero PLL, y un reloj
de CPU que depende del dado. Añadir una función implica hoy **quitar otra del mismo
tamaño y volver a tirar los dados**. Esa es la razón de cerrar la v2.0 como versión final
del MSXnano en la Tang Nano 20K; lo que no cabe aquí sigue en el
[MSXimus](https://github.com/Papipapito/MSXimus) (Tang Console 60K).
