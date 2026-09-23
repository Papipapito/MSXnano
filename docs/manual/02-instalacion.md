# 02. Instalación

Cuatro cosas que grabar, en este orden: el **core** en la flash de la Tang, el **pack de
BIOS** detrás de él, el **firmware del RP2040**, y —solo si lo montas— el del **ESP**. Y
unos pocos cables.

## 1. El core (`.fs`)

Herramienta: **Gowin Programmer** (viene con el
[Gowin EDA](https://www.gowinsemi.com/en/support/download_eda/); basta la edición
Education). **No** uses openFPGALoader: no maneja bien la flash externa de esta placa.

| Qué | Fichero | Dirección | Modo del Programmer |
|---|---|---|---|
| Core | `msxnano_v2.0.fs` (de la [release](https://github.com/Papipapito/MSXnano/releases)) | `0x000000` | *External Flash Mode* |

Al terminar, la placa reinicia sola con el core cargado. Sin pack todavía no arranca nada
útil: falta la BIOS.

## 2. El pack de BIOS

El pack es un fichero de **512 KB** que concatena la BIOS MSX2+, la sub-ROM, Nextor, la
ROM de kanji, la ROM WiFi, el logo, el menú y el bloque de configuración. La FPGA lo lee
de la flash por streaming al arrancar.

| Qué | Fichero | Dirección | Modo del Programmer |
|---|---|---|---|
| Pack | `pack_bios_msxnano.bin` | `0x200000` | *exFlash C Bin Erase, Program thru GAO-Bridge* |

Hay dos packs en la release: **`pack_bios_msxnano.bin`** (Nextor 2.1.4, el recomendado) y
`pack_bios_msxnano_nextor3.bin` (Nextor 3 beta). Ver [03. La tarjeta SD](03-tarjeta-sd.md)
para las diferencias.

> Los packs llevan ROMs de sistema con derechos de autor de sus dueños; van en la release
> por decisión del autor. Las herramientas que los montan (`tools/hacer_packs.py`) viven en
> su repositorio de BIOS, `bios-msxnano-msximus`, que es **privado**. La anatomía completa
> está en [tecnica/04-pack-bios.md](../tecnica/04-pack-bios.md).

## 3. El RP2040 (teclado, joystick y ratón)

Sin él no hay teclado. Es un **RP2040** con firmware propio que hace de host USB y le
cuenta al FPGA qué teclas hay pulsadas por **un solo hilo**.

**Firmware** (en [`fpga/rp2040/`](../../fpga/rp2040/), fuente incluido):

| Placa | Fichero en el repo | Fichero en la release |
|---|---|---|
| Waveshare **RP2040-Zero** (la recomendada) | `rp2040_keyboard.uf2` | `rp2040_keyboard_zero.uf2` |
| Raspberry Pi **Pico** normal | `rp2040_keyboard_pico.uf2` | `rp2040_keyboard_pico.uf2` |

Para grabarlo: mantén pulsado **BOOTSEL** mientras enchufas la Pico al PC, aparece una
unidad `RPI-RP2`, arrastra el `.uf2` encima. Se reinicia sola.

**Cableado** (tres hilos):

| Pico Zero | Tang Nano 20K | Qué es |
|---|---|---|
| **GP15** | **pin 31** | datos, UART 115200 8N1 (salida del Pico) |
| GND | GND | masa común |
| VBUS | 5V | alimentación del Pico |

El teclado, el mando o el ratón se enchufan al **USB de la propia Pico**. Un hub funciona
(teclado + mando a la vez está probado), y un hub **con alimentación propia** evita
sorpresas.

## 4. WiFi: ESP-01S o ESP32-C6 (opcional)

Los dos hablan el mismo protocolo (MSX UNAPI, firmware de ducasp) por la misma UART a
859372 baudios; el core no sabe cuál tiene enchufado. El C6 añade una **pantalla de
estado** y un hilo más para el indicador de turbo.

### ESP-01S (solo WiFi)

| ESP-01S | Tang Nano 20K |
|---|---|
| RX | **pin 27** |
| TX | **pin 28** |
| VCC | 3,3 V |
| GND | GND |

Firmware: el [ESP8266-UNAPI de ducasp](https://github.com/ducasp/ESP8266-UNAPI-Firmware),
compilado para 859372 baudios (soportado de serie).

### ESP32-C6-LCD-1.3 (WiFi + pantalla)

| ESP32-C6 | Tang Nano 20K | Señal |
|---|---|---|
| **GPIO17** (RX) | **pin 27** | FPGA → C6 |
| **GPIO16** (TX) | **pin 28** | C6 → FPGA |
| **GPIO3** | **pin 29** | indicador de turbo, FPGA → C6 |
| GND | GND | masa común |

Firmware: [ESP32-for-FPGA](https://github.com/Papipapito/ESP32-for-FPGA)
(`firmware_esp32c6_v2.0_merged.bin` en la release). La pantalla enseña el logo al arrancar,
el estado de la WiFi, la hora y si el turbo está activo.

Placa: Waveshare **ESP32-C6-LCD-1.3** (240×240). Se alimenta por su propio USB-C.

## 5. Primer arranque

1. HDMI al televisor, Pico con teclado, SD en la ranura, alimentación por el USB-C de la Tang.
2. Sale el **logo de MSX Barcelona** y, según el ajuste, el menú o directamente MSX-DOS.
3. Si sale el menú y quieres arrancar directo a MSX: **S** (Ajustes) → desmarcar *Menu al
   arrancar* → *Save & Restart*. Ver [04. El menú](04-menu.md).

## Actualizar

Cada versión nueva son los mismos pasos 1 y 2. **El core y el pack van emparejados**: el
menú **no** lo comprueba (solo enseña la versión del `.fs` en Ajustes, leída del puerto
0x2F), así que graba siempre el core y el pack de la misma release.

## Resumen de pines de la Tang Nano 20K

| Pin | Señal | Companion |
|---|---|---|
| 27 | UART TX (FPGA → ESP) | ESP-01S / C6 |
| 28 | UART RX (ESP → FPGA) | ESP-01S / C6 |
| 29 | turbo_status | C6 |
| 31 | teclado/joystick/ratón (Pico → FPGA) | RP2040 |

Todos en la zona libre 26-32 de la placa; la 26, 30 y 32 quedan sin usar. Nivel lógico
3,3 V en todos: conexión directa, sin adaptación.
