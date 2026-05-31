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
* WiFi via ESP-01S (MSX UNAPI) — WiFi BIOS ROM integrated into the BIOS pack
* Authentic MSX timing: per-M1 wait-state (~100% of real MSX speed), with a **Turbo mode** toggled by **F12** (full speed, ~116% / 4.13 MHz)

## What's new in v1.2
* Rebuilt on the **goauld standalone core** (cleaner base) while keeping the standalone / USB / WiFi design.
* **Authentic MSX speed**: added the per-M1 opcode-fetch wait-state that a real MSX board provides, so the CPU runs at ~100% (≈3.58 MHz effective, measured 101%) instead of ~116%. Toggleable via `` `define ENABLE_M1_WAIT `` in `fpga/top.v`.
* **WiFi BIOS integrated**: the ESP8266 UNAPI ROM now ships inside the single BIOS pack flashed at `0x200000` — there is no separate WiFi ROM to flash.
* WiFi UART pins aligned with the wiring diagram (`uart_rx` → pin 77, `uart_tx` → pin 73).
* **Claude (Anthropic)** collaborated on this release.

---

## 🔌 Connection diagram

```
                    ┌──────────────────────────────┐
   HDMI display ────┤ HDMI                         │
                    │                              │
   microSD card ────┤ SD                 USB-C ────┼──── PC (Gowin Programmer)
                    │                              │
                    │          BL616   USB-A ──────┼──── USB keyboard
                    │      (HID host)              ├──── USB gamepad
                    │                              │
                    │       [ S1: Reset ]          │
                    │       [ S2: UPDATE (BL616 ISP mode) ]
                    │                              │
                    │   GPIO header:               │
                    │      Pin 77 ─────────────────┼──── ESP-01S TX  ┐
                    │      Pin 73 ─────────────────┼──── ESP-01S RX  │ WiFi
                    │      3.3V  ─────────────────┼──── ESP-01S VCC │ (optional)
                    │      GND   ─────────────────┼──── ESP-01S GND ┘
                    └──────────────────────────────┘
```

---

### 💾 What to flash and with what tool

| Step | File | Address | Tool | Notes |
|------|------|---------|------|-------|
| 1 | `msxnano.fs` | `0x000000` | [Gowin Programmer](https://www.gowinsemi.com/en/support/download_eda/) | External Flash mode |
| 2 |  `flash_nano20k.ini` | (BL616) | [BLFlashCube](https://dev.bouffalolab.com/download) | Hold UPDATE → plug USB-C → release |
| 2a | `bl616_fpga_partner_nano20k.bin` | `0x000000` (BL616) | [BLFlashCube](https://dev.bouffalolab.com/download) | Into INI File |
| 2b | `fpga_companion_nano20k.bin` | `0x040000` (BL616) | BLFlashCube + `flash_nano20k.ini` | Into Ini File |
| 3 | `goauld_rom_int.bin` (BIOS pack) | `0x200000` | Gowin Programmer | *exFlash C Bin Erase, Program thru GAO-Bridge*. Bundles MSX2+ BIOS + sub-ROM + Nextor 2.1 + **WiFi ROM** + config. Build locally (copyright) |
| 4 | ESP-01S UNAPI firmware (OCM) | — | esptool / Arduino IDE via CH340 adapter | *(WiFi only — see below)* |

> **File 1 (`msxnano.fs`):** download from [releases](https://github.com/Papipapito/MSXnano/releases)  
> **File 2a/2b:** download from [FPGA-Companion v1.4.21](https://github.com/MiSTle-Dev/FPGA-Companion/releases/tag/v1.4.21)  
> **File 3 (BIOS pack):** contains copyrighted MSX system ROMs, so it is **not** distributed here — build it from your own ROM dumps with `fpga/src/rom/build.bat`  
> **File 4 (ESP-01S):** download from [ducasp MSX-Development — ESPFW1.4](https://github.com/ducasp/MSX-Development/releases/tag/ESPFW1.4) — use the **OCM** release (contains two `.bin` files)

---

## Turbo mode (F12)

The CPU boots at **real-MSX speed** (the authentic per-M1 wait-state, ~100% / 3.58 MHz).
Press **F12** on the USB keyboard to toggle **Turbo** on/off:

| Mode | Speed | LED 5 |
|------|-------|-------|
| Real MSX (default) | ~100% (3.58 MHz) | blinking (~1.8 Hz) |
| Turbo | full speed, ~116% (≈4.13 MHz) | solid on |

The toggle is handled entirely in the FPGA (it never reaches the MSX), survives a soft
reset, and powers on in real-MSX mode.

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

Flash `msxnano.fs` using Gowin Programmer at address `0x000000`.

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

### 3. Flash the BIOS pack

This standalone core loads the MSX2+ BIOS from external SPI flash (it is **not** embedded in the bitstream), so a second flash step is required. Flash the BIOS pack `goauld_rom_int.bin` (international; or `goauld_rom_japan.bin`) at address `0x200000` with Gowin Programmer, Operation = *"exFlash C Bin Erase, Program thru GAO-Bridge"*.

The pack is a single 512 KB image that already bundles **everything**: MSX2+ BIOS + sub-ROM + logo/FM menu + **Nextor 2.1** disk ROM + **WiFi UNAPI ROM (esp8266e)** + config. There is no separate Nextor or WiFi ROM to flash.

> The pack contains copyrighted MSX system ROMs, so it is **not** included in this repository. Build it yourself from your own ROM dumps with `fpga/src/rom/build.bat`.

## WiFi (ESP-01S)

WiFi support uses an ESP-01S module (ESP8266) connected to the Tang Nano 20K header pins.

### Wiring

| ESP-01S pin | Tang Nano 20K pin | Direction |
|-------------|-------------------|-----------|
| TX (GPIO1)  | Pin 77            | ESP → FPGA |
| RX (GPIO3)  | Pin 73            | FPGA → ESP |
| VCC         | 3.3V              | Power |
| GND         | GND               | Ground |

### WiFi ROM (already integrated)

The WiFi UNAPI ROM (esp8266e) is **bundled inside the BIOS pack** flashed at `0x200000` (step 3) and is mapped to **Slot 1, page 1** (0x4000–0x7FFF), detected automatically by the MSX BIOS at boot. **No separate WiFi ROM flashing is needed** — you only have to wire the ESP-01S module and pre-flash it with its own UNAPI firmware (below).

I/O ports used by the WiFi interface:
| Port | Direction | Description |
|------|-----------|-------------|
| 0x06 | Read      | Receive byte from UART buffer |
| 0x06 | Write     | Set baud rate / clear buffer |
| 0x07 | Read      | UART status flags |
| 0x07 | Write     | Send byte to UART (to ESP-01S) |

Default baud rate: **859372 bps**. The ESP-01S must be pre-flashed with MSX UNAPI firmware at this baud rate.

#### ESP-01S firmware

Download the **OCM** build from [ducasp/MSX-Development — ESPFW1.4](https://github.com/ducasp/MSX-Development/releases/tag/ESPFW1.4).  
It contains two `.bin` files — flash both using esptool or the Arduino IDE via a **CH340 / CP2102 USB-serial 3.3V adapter**.

### MSX UNAPI

The WiFi module implements MSX UNAPI TCP/IP over the ESP8266 serial interface. Compatible with standard MSX networking software (Telnet clients, FTP, etc.).


## Hardware: case & bill of materials

- 🧩 **3D-printable case**: STL files in [`case/`](case). Recommended material: **white PETG**. Print everything at once with `case/msxnano_case_bambulab.3mf` (Bambu Lab).
- 📋 **Bill of materials**: component list in [`docs/BOM.md`](docs/BOM.md) and [`docs/MSXnano_BOM.xlsx`](docs/MSXnano_BOM.xlsx).

> The 3D case is based on [this Thingiverse design](https://www.thingiverse.com/thing:4066021), which served as the inspiration and starting point for our improved version.

## Credits

This project is based on the work of **jabadiagm** ([MSXgoauldSD_tn20k](https://github.com/jabadiagm/MSXgoauldSD_tn20k)), licensed under **GPLv3**.

It is a standalone FPGA implementation that does not rely on the original physical MSX hardware, so all hardware-related files (PCB, MSX interface, schematics) have been removed.

**Claude (Anthropic)** collaborated on this project.
