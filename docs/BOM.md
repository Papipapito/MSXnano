# Bill of Materials (BOM) — v2.0

Everything you need to build a **MSXnano** (standalone MSX2+ on the Tang Nano 20K).
Items marked _(optional)_ are not required to boot; they add the feature noted.

Spreadsheet version: [`MSXnano_BOM.xlsx`](MSXnano_BOM.xlsx).

## Core

| # | Qty | Component | Notes |
|---|-----|-----------|-------|
| 1 | 1 | **Sipeed Tang Nano 20K** (GW2AR-18) | The main board. Any revision works: since v2.0 the onboard BL616 is **not used**, so boards marked `3921` (locked BL616) are fine. |
| 2 | 1 | **microSD card**, FAT32 | 2–32 GB is simplest. Larger cards must be formatted FAT32 by hand. |
| 3 | 1 | **USB-C cable** | Power + programming (Gowin Programmer). |
| 4 | 1 | **HDMI cable** | Video and audio out. There is no analog audio. |

## Keyboard, joystick and mouse (required for a keyboard)

| # | Qty | Component | Notes |
|---|-----|-----------|-------|
| 5 | 1 | **RP2040 board** | Waveshare **RP2040-Zero** (recommended, `rp2040_keyboard_zero.uf2` in the release) or a plain **Raspberry Pi Pico** (`rp2040_keyboard_pico.uf2`). |
| 6 | 3 | **Jumper wires** | Pico GP15 → Tang **pin 31**, GND → GND, VBUS → 5V. |
| 7 | 1 | **USB keyboard** | Plugged into the Pico's USB port. Plain keyboards work best (avoid ones with a built-in hub). |
| 8 | 1 | **USB hub** _(optional)_ | To use keyboard **and** gamepad/mouse at once. A **self-powered** hub is recommended. |
| 9 | 1 | **USB gamepad** _(optional)_ | DirectInput (HID) or XInput. Buttons 3/4 = autofire. |
| 10 | 1 | **USB mouse** _(optional)_ | Becomes a real MSX mouse on joystick port 2. |

## WiFi _(optional — MSX UNAPI, File-Hunter)_

Pick **one** of the two. Both use the same UART on pins 27/28.

| # | Qty | Component | Notes |
|---|-----|-----------|-------|
| 11a | 1 | **ESP-01S** (ESP8266) | RX → Tang **pin 27**, TX → **pin 28**, VCC → 3.3V, GND → GND. Firmware: ducasp ESP8266-UNAPI at 859372 baud. WiFi only. |
| 11b | 1 | **Waveshare ESP32-C6-LCD-1.3** | GPIO17 → pin 27, GPIO16 → pin 28, GPIO3 → **pin 29** (turbo LED), GND → GND. Powered by its own USB-C. Adds a 240×240 status screen. Firmware: [ESP32-for-FPGA](https://github.com/Papipapito/ESP32-for-FPGA). |
| 12 | — | Jumper wires / header | 4 wires for either module. |

## Enclosure _(optional)_

| # | Qty | Component | Notes |
|---|-----|-----------|-------|
| 13 | 1 set | **3D-printed case**, white PETG recommended | STL files in [`../case/`](../case). Print everything at once with `msxnano_case_bambulab.3mf`. Two top-left variants: with a window for the ESP32-C6 screen, or without. |
| 14 | — | **M2/M3 screws and standoffs** | See the spreadsheet and [`../case/README.md`](../case/README.md). |

## Notes

- **No soldering** is needed: the RP2040 and the ESP connect with jumper wires to the
  Tang Nano 20K header. All signals are 3.3 V, direct connection.
- Pins used on the Tang Nano 20K: **27, 28** (WiFi UART), **29** (turbo status, C6 only),
  **31** (keyboard link). All in the free 26–32 area.
- Flashing (bitstream + BIOS pack + RP2040 + ESP) is in the [main README](../README.md)
  and, in Spanish and in detail, in [`manual/02-instalacion.md`](manual/02-instalacion.md).
