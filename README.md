# MSXnano
MSX2+ core for the Tang Nano 20k (60k and 138k soon)

* Z80
* V9958 with hdmi output
* MSX2+ BIOS
* SD Card support + Nextor 2.1
* 4MB mapper
* 2MB megaram SCC
* RTC
* PSG
* OPLL
* FPGA Companion used as HID (keyboard, gamepads) interface
* WiFi via ESP-01S (MSX UNAPI)

## Slot map

Slot map has been updated to improve compatibility without requiring changes.

![Slot map](/pics/mapa_slots4.png)

Mapper and megaram can be relocated to slots 1 or 2 using config menu.

## Megaram + Sofarun
Megaram is detected automatically by sofarun using default settings. When using other software you may need to indicate location, Slot 3-3 by default.

## Known issues
* Tape games fail: use poke -1,0

## Flashing

Programming is done in three steps:

### 1. Flash the FPGA bitstream

Flash `MSXnano.fs` using Gowin Programmer at address `0x000000`.

### 2. Flash the BL616 FPGA Companion firmware

The onboard BL616 MCU handles USB keyboard, mouse and gamepads via SPI.
It requires **two binaries** flashed at specific addresses — using only one is not enough.

Download the following files from the [MiSTle-Dev FPGA-Companion v1.4.21 release](https://github.com/MiSTle-Dev/FPGA-Companion/releases/tag/v1.4.21):

| File | Address | Description |
|------|---------|-------------|
| [`bl616_fpga_partner_nano20k.bin`](https://github.com/MiSTle-Dev/FPGA-Companion/releases/download/v1.4.21/bl616_fpga_partner_nano20k.bin) | `0x000000` | BL616 bootloader / base firmware |
| [`fpga_companion_nano20k.bin`](https://github.com/MiSTle-Dev/FPGA-Companion/releases/download/v1.4.21/fpga_companion_nano20k.bin) | `0x040000` | FPGA Companion application (HID, gamepad support) |

Also download [`flash_nano20k.ini`](https://github.com/MiSTle-Dev/FPGA-Companion/releases/download/v1.4.21/flash_nano20k.ini) — it configures the flash tool to write both files at the correct addresses in one step.

Flash using [BouffaloLabDevCube](https://dev.bouffalolab.com/download) (BLFlashCube) with the `.ini` file:
* Press and hold **UPDATE** on the Tang Nano 20K, connect USB, release UPDATE (enters BL616 ISP mode)
* For full flashing instructions see: [MiSTle-Dev BL616 Firmware Installation](https://github.com/MiSTle-Dev/.github/wiki/Firmware-Installation-BL616-%C2%B5C)

#### Supported USB gamepads

| Controller | Status |
|-----------|--------|
| Xbox 360 (wired) | ✅ Works |
| Xbox 360-compatible clones (XInput) | ✅ Works |
| Xbox One (XInput mode) | ✅ Works |
| Lenovo X01 (USB dongle) | ✅ Works |
| Xbox Series X/S | ❌ Not supported (different protocol) |
| PlayStation 4 / 5 | ❌ Not supported |

Player 1 = first XInput device enumerated; Player 2 = second device (requires USB hub).

### 3. Flash the disk ROM

MSXnano uses the same Nextor driver as Wondertang: `Nextor-2.1.1.WonderTANG.ROM.bin`.
Flash Address = `0x100000` (subject to change).

## WiFi (ESP-01S)

WiFi support uses an ESP-01S module (ESP8266) connected to the Tang Nano 20K header pins.

### Wiring

| ESP-01S pin | Tang Nano 20K pin | Direction |
|-------------|-------------------|-----------|
| TX (GPIO1)  | Pin 77            | ESP → FPGA |
| RX (GPIO3)  | Pin 73            | FPGA → ESP |
| VCC         | 3.3V              | Power |
| GND         | GND               | Ground |

### Slot mapping

The WiFi BIOS ROM (esp8266e) is mapped to **Slot 1, page 1** (0x4000–0x7FFF).  
It is detected automatically by the MSX BIOS at boot.

I/O ports used by the WiFi interface:
| Port | Direction | Description |
|------|-----------|-------------|
| 0x06 | Read      | Receive byte from UART buffer |
| 0x06 | Write     | Set baud rate / clear buffer |
| 0x07 | Read      | UART status flags |
| 0x07 | Write     | Send byte to UART (to ESP-01S) |

Default baud rate: **859372 bps**. The ESP-01S must be pre-flashed with MSX UNAPI firmware at this baud rate.

### MSX UNAPI

The WiFi module implements MSX UNAPI TCP/IP over the ESP8266 serial interface. Compatible with standard MSX networking software (Telnet clients, FTP, etc.).

## YouTube video
https://youtu.be/7KI_Em9QK0Y

## Standalone FPGA version of MSXgoauldSD_tn20k

This project is based on MSXgoauldSD_tn20k by https://github.com/jabadiagm, licensed under GPLv3.

This branch (`standalone`) contains a standalone FPGA implementation.  
All hardware-related files from the original project (PCB, MSX interface, schematics, etc.) have been intentionally removed, because this version does not rely on the original physical hardware.
