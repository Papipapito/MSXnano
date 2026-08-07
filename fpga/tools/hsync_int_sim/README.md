# Interrupción de línea del VDP: se dispara DOS veces por línea

**Estado: bug CONFIRMADO, arreglo ESCRITO Y VERIFICADO en simulación, pero
APARCADO porque hoy no cabe en el chip.** Ver "Por qué está aparcado".

## El bug

`vdp.vhd` genera la ventana de disparo de la interrupción de línea con **dos**
comparaciones:

```vhdl
IF( PREDOTCOUNTER_X = 255+25 OR PREDOTCOUNTER_X = "111111111" )THEN
    ACTIVE_LINE <= '1';
```

Y las dos pertenecen a la **misma línea**. El motivo está en `vdp_ssg.vhd`:

```vhdl
-- vdp_ssg.vhd:399 — el avance de linea cae en el MISMO valor 511
W_HSYNC <= '1' WHEN( W_H_CNT(1 DOWNTO 0) = "10" AND FF_PRE_X_CNT = "111111111" )
-- vdp_ssg.vhd:454 — y el contador Y va un ciclo por detras
FF_PRE_Y_CNT <= FF_MONITOR_LINE + ("0" & REG_R23_VSTART_LINE);
```

O sea: cuando el contador X vale 511 —que es justo el instante en que avanza la
línea— el contador Y **todavía tiene el número de la línea anterior**. Así que
`Y_CNT = R#19` se cumple dos veces para la misma línea, separadas por decenas de
microsegundos.

Como el borrado del flag (leer S#1) es un **pulso**, si la ISR hace el ack entre
las dos ventanas, la segunda **vuelve a pedir interrupción** y la rutina se
ejecuta **dos veces en la misma línea**.

Que el ack caiga dentro o fuera de esa ventana depende de qué instrucción
estuviera ejecutando el Z80 al aceptar la INT → **falla en un porcentaje de
frames, no siempre**. Es exactamente el síntoma del jitter de **R-Type con el
parche de smooth-scroll**, que en su día se achacó al parche y se dio el core
por exonerado. No lo estaba.

## No es así en ningún otro sitio

| Implementación | Condición |
|---|---|
| **OCM upstream** (KdL, ene-2025) | `= 231` (SC2/4) **o** `= 255` — una ventana, según modo |
| **TangCartMSX** (clon independiente) | `= 255` — una ventana |
| **openMSX** | un único *sync point* por coincidencia |
| **WebMSX** | una sola llamada, en "End of Active Display" |
| **linaje goauld** (esto) | `= 280` **OR** `= 511` — **dos ventanas** |

El segundo término es exclusivo del linaje goauld → MSXnano/MSXimus.
**El MSXimus (`MSX_up`) tiene el mismo bug.**

## El arreglo

`vdp_hsync_int_fix.patch` — quitar el término `OR PREDOTCOUNTER_X = "111111111"`.
`ACTIVE_LINE` **solo lo usa el latch de interrupción** (comprobado), así que no
tiene efectos colaterales.

## La verificación

```bash
iverilog -g2012 -o tb tb_hsync_int.v && vvp tb
```

El testbench transcribe literalmente los tres trozos de VHDL implicados (no es
el RTL de producción: Icarus no simula VHDL y no había GHDL). Barre el retardo
del ack y cuenta interrupciones por línea:

| Ack tras | Código actual | Con el arreglo |
|---|---|---|
| 4 ciclos | **2** ❌ | 1 ✅ |
| 194 | **2** ❌ | 1 ✅ |
| 384 | **2** ❌ | 1 ✅ |
| 574 | **2** ❌ | 1 ✅ |
| 764 en adelante | 1 | 1 ✅ |

Hay una ventana de ~600 ciclos en la que se duplica. Con el arreglo: **una sola
interrupción con cualquier retardo**.

## Por qué está APARCADO

El arreglo **quita** una comparación, pero mide:

| | clk_54m | CLS |
|---|---|---|
| Árbol intacto | **54,367 MHz** ✅ | 9212 (89%) |
| Con el arreglo | **47,3 – 47,9 MHz** ❌ | **9259 (90%)** |

**+47 celdas, y el mismo número con 3 combinaciones distintas de
place/route_option** → es determinista, NO es lotería de emplazamiento (esa
hipótesis se probó y se descartó). Con `clk_54m` cumpliendo por un 0,7% de
margen, esas 47 celdas bastan para tumbarlo a 47,9 MHz.

El porqué de que quitar lógica añada celdas no se llegó a determinar (haría
falta bajar al netlist). Da igual para la decisión: es medido y reproducible.

**Coste/beneficio**: arreglar el jitter de un puñado de programas con split
raster no compensa perder un 12% de margen en el reloj de la CPU, que afecta a
TODO.

## Cuándo retomarlo

Cuando haya holgura de celdas. Candidatos:
- Una línea de build "slim" (en el MSXimus quitar el audio bajó de 90% a 69% CLS).
- Después de cualquier limpieza que libere ~100 CLS.
- Si alguna vez se migra a un chip más grande.

Entonces: aplicar el parche, correr el testbench, build, y **probar R-Type con el
parche de smooth-scroll** — ese es el juez de si el diagnóstico era correcto.
