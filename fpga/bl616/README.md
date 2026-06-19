# Teclado USB (BL616 / FPGA-Companion) — IMPORTANTE

El teclado y los mandos USB del MSXnano los gestiona el **MCU BL616** mediante el
firmware **FPGA-Companion** (de [MiSTle-Dev](https://github.com/MiSTle-Dev/FPGA-Companion)),
que habla con la FPGA por SPI. Hay **dos formas** de tener ese BL616:

1. **El BL616 de a bordo** del propio Tang Nano 20K, o
2. **Un M0S Dock externo** (módulo BL616 aparte) conectado al header `m0s`.

El core conmuta **automáticamente** al M0S Dock externo cuando lo detecta
(pin `m0s[2]`), así que basta con enchufarlo.

---

## ⚠️ El problema de los Tang Nano 20K nuevos (2024+)

Desde **~febrero de 2024**, Sipeed fabrica los Tang Nano 20K (marca **`3921`** en la
placa) con el **eFuse de "secure-boot" del BL616 en un estado distinto**. En estas
placas, el BL616 de a bordo **a menudo NO puede ejecutar el firmware del companion**,
y el resultado es que **el teclado no funciona** (aunque la imagen por HDMI y el menú
sí funcionen — eso es la FPGA, no el BL616).

El propio autor del firmware lo advierte: en un BL616 en estado "unfused" *flashear el
firmware del µC lo puede dejar sin responder* (recuperable, ver abajo), y **es imposible
saber a priori si un `3921` es fused o unfused**. Su recomendación oficial para estas
placas es **usar un M0S Dock externo** (o PiPico) en lugar del BL616 de a bordo.

**Resumen:**

| Tu placa | BL616 de a bordo | Solución |
|---|---|---|
| Antigua (pre-2024) | Suele funcionar | Flashear el firmware onboard (abajo) |
| Nueva (`3921`, 2024+) | A menudo NO | **M0S Dock externo** |

---

## Test rápido: ¿mi Tang necesita el M0S Dock?

1. Flashea el **firmware onboard** (carpeta de abajo, `flash_nano20k.ini`).
2. Apaga y enciende la placa (power-cycle).
3. Conecta un teclado USB y prueba en el menú.
   - **Funciona** → tu BL616 de a bordo es compatible. Listo, no necesitas el dock.
   - **No funciona** → necesitas un **M0S Dock** (sección M0S Dock).

> Si tras flashear el onboard la placa deja de aparecer como puerto serie o no se deja
> reprogramar, **recupérala** con el firmware de fábrica `friend_20k`:
> https://github.com/harbaum/MiSTeryNano/blob/main/firmware/friend_20k

---

## Cómo flashear (Bouffalo Lab Dev Cube / Flash Cube)

Para cualquiera de las tres opciones:

1. Abre **BouffaloLabDevCube** (o BLFlashCube) → pestaña **MCU** / carga del `.ini`.
2. **Mantén pulsado BOOT/UPDATE** mientras conectas el USB-C, luego suelta.
3. Refresca el puerto COM, selecciónalo, baud **2000000**, y pulsa **Create & Download**.

### Opción A — BL616 de a bordo (estándar)
`flash_nano20k.ini`
- `bl616_fpga_partner_nano20k.bin` → `0x0`
- `fpga_companion_nano20k.bin` → `0x40000`

### Opción B — BL616 de a bordo (unconditional / bootloader firmado)
`flash_nano20k_unconditional.ini` (alternativa si la A no arranca el companion estando
el USB-C conectado a un PC para alimentar)
- `bl616_bootloader_0x20000_nano20k_signed.bin` → `0x0`
- `fpga_companion_bl616_tn20k.bin` → `0x20000`

### Opción C — M0S Dock externo (recomendado para placas nuevas)
`flash_m0sdock_cfg.ini`
- `fpga_companion_m0sdock.bin` → `0x0`

Flashea el M0S Dock (con su propio BOOT), cablea las 5 líneas SPI + alimentación
al Tang, y enchufa el teclado al USB-C del M0S Dock con un adaptador
**USB-C → USB-A (OTG)**. El core detecta el dock cuando CS (`m0s[2]`) baja y
conmuta del BL616 de a bordo al externo automáticamente (no hay que tocar RTL).

#### Cableado M0S Dock → Tang Nano 20K

Las señales SPI están definidas en el firmware (`mcu_hw.c`, build `M0S_DOCK`:
MISO=IO10, MOSI=IO11, CSN=IO12, SCK=IO13, IRQ=IO14) y en el RTL del MSXnano
(`fpga_companion.v` + `tang9k.cst`). Mapeo final:

| Señal | M0S Dock | Tang Nano 20K (pin GW2A) | `m0s[]` |
|---|---|---|---|
| MISO (FPGA→M0S) | IO10 | 42 | `m0s[0]` |
| MOSI (M0S→FPGA) | IO11 | 41 | `m0s[1]` |
| CS/SS (M0S→FPGA) | IO12 | 56 | `m0s[2]` |
| SCK (M0S→FPGA) | IO13 | 54 | `m0s[3]` |
| IRQ (FPGA→M0S) | IO14 | 51 | `m0s[4]` |
| 5V | 5V | 5V | alimentación |
| GND | GND | GND | común |

Notas:
- **IO10–IO14 están agrupadas** en el header CK-Link/debug del M0S Dock.
- El M0S Dock se **alimenta desde el Tang** (5V + GND), porque su USB-C lo ocupa
  el teclado.
- Las direcciones de señal cuadran 1:1: MISO/IRQ las conduce la FPGA, y
  MOSI/CS/SCK las conduce el M0S; `m0s[2]` lleva PULL-UP para que sin dock se use
  el BL616 de a bordo.

---

## Créditos / licencia

Los binarios `.bin` y `.ini` de esta carpeta son del proyecto
**FPGA-Companion** de MiSTle-Dev (versión **v1.4.21**), redistribuidos aquí por
comodidad bajo su licencia. Fuente y versiones más recientes:
https://github.com/MiSTle-Dev/FPGA-Companion/releases

Más contexto del cambio de hardware de Sipeed:
https://github.com/MiSTle-Dev/.github/wiki/Versions_TangNano20k
