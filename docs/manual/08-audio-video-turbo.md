# 08. Audio, vídeo y turbo

## Audio

Cuatro fuentes, mezcladas en el FPGA y sacadas **por el HDMI** (no hay jack analógico en
la Tang Nano 20K):

| Chip | Qué es | Dónde |
|---|---|---|
| **PSG** (YM2149) | Los tres canales de tono + ruido de todo MSX | puertos 0xA0-0xA2 |
| **OPLL** (YM2413, MSX-MUSIC) | FM de 9 canales; la BIOS de MSX-MUSIC va en el pack | puertos 0x7C/0x7D |
| **SCC+** ×2 | El chip de ondas de Konami. Uno en la Megaram, el segundo se activa en Ajustes | en el espacio de la Megaram |
| — | El click de teclado y el motor de casete del PPI | puerto 0xAA |

**Estéreo**: con *Stereo Sound* activado en Ajustes, PSG y SCC van a un canal y el OPLL al
otro, como en el OCM. Desactivado, todo mezclado en mono a los dos.

El PSG pasa por un **filtro** (`psg_filter.v`) que le quita el escalón digital y lo
acerca al sonido de un MSX real por el altavoz de un televisor.

Lo que **no** hay: OPL4/MoonSound (no cabe ni de lejos; hay un estudio de viabilidad en
[pendientes](../tecnica/09-pendientes.md)), Y8950/MSX-AUDIO, ni salida analógica.

## Vídeo

El VDP es un **V9958** —el del MSX2+— con salida **HDMI**. Todos los modos, incluidos
SCREEN 10-12 (YJK) y el scroll horizontal por hardware (R#26/R#27) que usan los juegos
"smooth scroll".

| Ajuste | Qué hace |
|---|---|
| **Enable Scanlines** | Líneas de barrido alternas, para el efecto de monitor de tubo |
| **Sprites 8/línea** | Limita a 8 sprites por línea como el VDP real. Por defecto el core deja pintar más (sin parpadeo); algunos juegos y demos cuentan con el límite para efectos, y ahí conviene activarlo |

La imagen sale a la resolución nativa del VDP escalada por el HDMI; la sincronización es
la del MSX (50 o 60 Hz según lo que pida el software por R#9).

Dos rarezas conocidas del vídeo, ambas con expediente:

- **R-Type con el parche de smooth-scroll** tiembla en un ~15 % de los frames. Se sabe
  la causa (la interrupción de línea se dispara dos veces) y el arreglo está escrito y
  probado en simulación, pero **no cabe en el chip**: ver
  [pendientes](../tecnica/09-pendientes.md).
- La paleta se expande con ceros en vez de replicando bits, así que **los blancos salen
  un ~12 % oscuros**. Es el hallazgo número uno de la lista de mejoras aparcadas.

## Turbo

El MSXnano lleva el turbo **Panasonic WSX**: el Z80 pasa de 3,579545 a **5,369318 MHz
exactos** (3/2), con el VDP y el sonido a su velocidad normal. Es el mismo mecanismo que
usan el Panasonic FS-A1WSX y el FS-A1WX, así que el software que lo conoce lo detecta.

### Cómo activarlo

| Forma | Cómo | Cuándo |
|---|---|---|
| **F11** en el teclado USB | conmuta al momento | para probar |
| **Boot Turbo** en Ajustes | arranca siempre en turbo; requiere apagar y encender | para dejarlo fijo |
| **Desde software** | `OUT &H40,8 : OUT &H41,128` activa; `OUT &H41,129` desactiva | programas y `AUTOEXEC` |
| **`TURBO.COM`** | `TURBO ON` / `TURBO OFF` / `TURBO` (consulta) desde MSX-DOS | [msx-turbo](https://github.com/Papipapito/msx-turbo) |

El protocolo: el dispositivo 8 del **switched I/O** (`OUT &H40,8`), `INP(&H40)` devuelve
`&HF7` si está presente, y el bit 0 de `&H41` es el estado (0 = turbo). Es exactamente lo
que hace un Panasonic real, así que `INP(&H41)` te dice en qué velocidad estás.

Si F11 y el software cambian el turbo en el mismo ciclo, **gana el software**: en el
chip real (T9769) el puerto es el único control.

### Qué acelera y qué no

Acelera el Z80 en RAM y ROM. **No** acelera los accesos al VDP, que siguen con las esperas
del MSX, ni el sonido, ni la SD (que va limitada por el propio protocolo). En la práctica:
los juegos van más fluidos, las cargas de disco un poco más rápidas, y el software con
temporización por bucles (algunos juegos de MSX1, música) puede ir demasiado deprisa —
para eso está F11.
