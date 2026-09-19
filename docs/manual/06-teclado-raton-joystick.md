# 06. Teclado, ratón y joystick

Todo lo USB pasa por el **RP2040**. Hace de host USB (teclado, mando y ratón, por un hub
si quieres los tres) y le manda al FPGA el estado por un solo hilo a 115200 baudios. El
FPGA mantiene una **matriz de teclado virtual** que el MSX lee exactamente igual que
leería un teclado de membrana: para el software no hay diferencia.

Desde la v2.0 es el **único** companion de entrada: el BL616 que la Tang Nano 20K trae de
fábrica ya no se usa. Motivo: las placas fabricadas desde 2024 (las marcadas `3921`)
llevan el BL616 en un estado de arranque seguro que no admite el firmware companion, y te
quedabas sin teclado. Con el RP2040 todas las placas se comportan igual.

## El mapa de teclas

Distribución **internacional / US**. Las teclas del MSX que no existen en un teclado de PC
van así:

| Tecla MSX | En el teclado USB |
|---|---|
| **GRAPH** | Alt izquierdo, o cualquiera de las teclas **Windows** |
| **CODE / KANA** | Alt derecho |
| **STOP** | **F12**, o Bloq Despl (Scroll Lock) |
| **SELECT** | Fin (End) |
| **CAPS** | Bloq Mayús |
| **F6 – F10** | F6 – F10, enviadas como SHIFT+F1..F5, exactamente como hace un MSX real |
| F1–F5, cursores, HOME/INS/DEL, ESC/TAB/BS/RETURN | 1:1 |
| **Turbo** | **F11** conmuta el turbo (ver abajo) |
| Teclado numérico | al teclado numérico del MSX |

### La ñ y el teclado español

La BIOS internacional no lleva la ñ. Con un teclado español la tecla ñ no produce nada.
Está apuntado cómo resolverlo (reciclar la capa KANA) pero no se ha hecho: ver
[pendientes](../tecnica/09-pendientes.md).

### F11 y el turbo

**F11 conmuta el turbo** entre 3,58 y 5,37 MHz al momento, y el cambio sobrevive hasta
que el software lo cambie por los puertos Panasonic o reinicies. Si además quieres que
la máquina **arranque** ya en turbo, es el ajuste *Boot Turbo* del menú. Más en
[08. Audio, vídeo y turbo](08-audio-video-turbo.md).

## El ratón

Cualquier ratón USB se convierte en un **ratón MSX** de los de verdad —el "inteligente",
el que habla por handshake con el pin 8 del puerto de joystick, no el de cuadratura—. El
protocolo está tomado de openMSX ciclo a ciclo, incluidas las ocho fases (las cuatro
normales y las cuatro alternas que devuelven cero y que el software usa para distinguir
un ratón de un trackball).

Lo ve el software que usa ratón MSX (SymbOS, los programas de dibujo, los juegos que lo
admiten). Aparece en el **puerto de joystick 2**. Los dos botones van a los disparos.

En la placa Pico Zero, el LED de a bordo lo cuenta: **cian** = ratón montado, **magenta**
= ratón moviéndose. Útil para saber si el hub se lo ha tragado.

## El joystick

Un gamepad USB HID normal (DirectInput) es un joystick MSX en el **puerto 1**. Se usan
la cruceta o el stick izquierdo, y los botones 1 y 2 como disparos A y B.

**Autofire**: los botones **3 y 4** disparan en ráfaga (A y B respectivamente) a 10 Hz
(semiperiodo de 50 ms, elegido para que cada disparo se lea también a 50 Hz).

Todos los mandos van al **puerto 1**; el firmware no reparte un segundo mando al puerto 2.
Mando y ratón sí conviven, porque el ratón usa el puerto 2.

Los mandos **XInput** (tipo Xbox) también funcionan, con soporte específico. Los mandos
que llevan interruptor XInput/DInput funcionan en cualquiera de las dos posiciones.

## Hubs

Teclado + mando por un hub está **probado en placa**. Recomendaciones:
- Hub **con alimentación propia** si vas a colgar más de un dispositivo: la Pico se
  alimenta del 5 V de la Tang y no le sobra corriente.
- Teclados **sencillos**. Los que llevan hub interno (puerto USB en el lateral, teclas
  multimedia como dispositivo aparte) cuentan como varios dispositivos y pueden agotar
  los endpoints del RP2040.

## Latencia

Del teclado al programa: **~14 ms típicos**. Casi todo es del propio MSX (la BIOS lee el
teclado una vez por frame, ~8 ms de media) y del sondeo USB del teclado (~4 ms). Lo que
añade el RP2040 y el hilo son **0,17 ms**: menos de un 1 % de un frame, imperceptible.
Un teclado con sondeo a 1 ms (los "gaming") lo baja a ~10 ms. Cifras y desglose en
[tecnica/05-companion-rp2040.md](../tecnica/05-companion-rp2040.md).

## Si el teclado deja de responder

El FPGA lleva un **vigilante de un segundo**: si deja de recibir datos del RP2040, suelta
todas las teclas y el joystick, para que un cable suelto no deje una tecla clavada. Si el
teclado "muere", mira el cable del pin 31 y que la Pico tenga alimentación (su LED).
