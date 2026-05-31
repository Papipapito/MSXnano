# Bill of Materials (BOM)

Components to build an **MSXnano** (standalone MSX2+ on Tang Nano 20K).

> Draft — review quantities, models and links. Items marked _(optional)_ are not
> required to boot, only for the feature noted.

## Core

| # | Qty | Component | Notes |
|---|-----|-----------|-------|
| 1 | 1 | **Sipeed Tang Nano 20K** (GW2AR-18 FPGA) | The main board. Includes onboard BL616 (USB HID host) and 6 user LEDs. |
| 2 | 1 | **microSD card** | For disk images / Nextor (FAT). Any size; small is fine. |
| 3 | 1 | **USB-C cable** | Power + programming (Gowin Programmer). |
| 4 | 1 | **HDMI cable** | Video output to a monitor/TV. |
| 5 | 1 | **USB keyboard** (USB-A) | Connected to the BL616 USB-A host port. |
| 6 | 1 | **USB hub** _(optional)_ | Needed only to use keyboard **and** gamepad at the same time. |
| 7 | 1 | **USB gamepad** _(optional)_ | XInput (Xbox-style) recommended; see README for compatibility. |

## WiFi _(optional — MSX UNAPI / internet)_

| # | Qty | Component | Notes |
|---|-----|-----------|-------|
| 8 | 1 | **ESP-01S** (ESP8266) module | Wired to the GPIO header: TX→pin 77, RX→pin 73, VCC→3.3V, GND→GND. Flash with ducasp ESPFW1.4 (OCM). |
| 9 | — | Jumper wires / header | To connect the ESP-01S to the Tang Nano 20K header. |

## Enclosure

| # | Qty | Component | Notes |
|---|-----|-----------|-------|
| 10 | 1 | **3D-printed case** | STL files in [`../case/`](../case). |
| 11 | — | **Screws / standoffs** _(if the case needs them)_ | _(fill in size/qty)_ |

## Notes
- No soldering is required for the base build (keyboard/gamepad are USB; SD and HDMI are onboard). Only the optional ESP-01S needs header wiring.
- Flashing instructions (bitstream + BL616 firmware + BIOS pack) are in the [main README](../README.md).
