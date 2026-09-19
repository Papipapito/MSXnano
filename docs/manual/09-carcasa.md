# 09. La carcasa

Una caja impresa en 3D, en dos mitades (superior e inferior) partidas a su vez en
izquierda y derecha para caber en cualquier impresora de sobremesa. Está en
[`case/`](../../case/). Parte de
[este diseño de Thingiverse](https://www.thingiverse.com/thing:4066021), rediseñado para
el MSXnano.

## Imprimir

Lo más cómodo: abrir **`msxnano_case_bambulab.3mf`** en **Bambu Studio**. Trae todas las
piezas colocadas y orientadas para imprimirlas de una vez.

Si tu impresora no es Bambu, los **STL** están sueltos. Material recomendado: **PETG
blanco**. Sin soportes en la mayoría de piezas; las tapas van boca abajo.

## Las piezas

| Fichero | Pieza | Cantidad |
|---|---|---|
| `Upper_Left_esp32.stl` | Tapa superior izquierda, **con ventana para la pantalla del ESP32-C6** | 1 (elige una) |
| `upper_left_sin_pantalla.stl` | Tapa superior izquierda, **sin ventana** | 1 (elige una) |
| `upper_right.stl` | Tapa superior derecha | 1 |
| `lower_left.stl` | Base izquierda | 1 |
| `lower_right.stl` | Base derecha | 1 |
| `lower_side.stl` | Lateral de la base (encaje de la Tang Nano 20K, versión 4) | 1 |
| `keyboard_support_a.stl` | Soporte de teclado A | 1 |
| `keyboard_support_b.stl` | Soporte de teclado B | 1 |
| `raspberry_support.stl` | Soporte de la placa RP2040 | 1 |
| `pillar1.stl` | Pilar 1 | 2 |
| `pillar2.stl` | Pilar 2 | 2 |
| `msxnano_case_bambulab.3mf` | Proyecto Bambu Lab con todo | — |

### Las dos tapas superiores izquierdas

Son la **única decisión** al imprimir. La tapa izquierda es donde va el módulo WiFi:

- **`Upper_Left_esp32.stl`**: lleva la ventana para la pantalla del **ESP32-C6-LCD-1.3**.
  Imprime esta si vas a montar el C6.
- **`upper_left_sin_pantalla.stl`**: tapa lisa. Para un montaje con ESP-01S, o sin WiFi.

El resto de piezas es igual en los dos casos. Solo se imprime una de las dos.

## Montaje

1. La **Tang Nano 20K** encaja en `lower_side.stl`, que se une a las dos bases. El
   USB-C, la microSD y el HDMI de la placa quedan accesibles por los laterales.
2. La **RP2040** va en `raspberry_support.stl`, con su USB hacia fuera para enchufar el
   teclado (o el hub).
3. Los **pilares** unen la base con la tapa y fijan la altura.
4. Si montas el **ESP32-C6**, va detrás de la ventana de `Upper_Left_esp32.stl`, con su
   USB-C accesible para alimentarlo.
5. Los tres cables de la Pico y los cuatro del ESP van por dentro al header de la Tang:
   ver [02. Instalación](02-instalacion.md).

Tornillería y detalles de medidas en la [lista de materiales](../BOM.md) y en la hoja
[`MSXnano_BOM.xlsx`](../MSXnano_BOM.xlsx).

## Créditos

Diseño base: [Thingiverse 4066021](https://www.thingiverse.com/thing:4066021), que sirvió
de punto de partida. Las modificaciones para el MSXnano (soportes, la ventana de la
pantalla, el lateral v4 de la Tang) son del proyecto.
