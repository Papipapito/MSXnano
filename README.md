# MSXnano — MSX2+ FPGA Core for Tang Nano 20K

**MSXnano** is an open-source MSX2+ FPGA implementation for the Tang Nano 20K (Gowin GW2AR-18). It runs a complete MSX2+ system — Z80 CPU, V9958 VDP with HDMI output, SCC/OPLL sound, SD card with Nextor, USB keyboard, joystick and mouse, and optional WiFi — entirely on the FPGA, with no original MSX hardware required.

> 📖 Project page, install guides and community: **[msx.barcelona](https://msx.barcelona)**

> **Project status: v2.0 is the final release** ([`v2.0-final`](https://github.com/Papipapito/MSXnano/releases/tag/v2.0-final)). The core fills ~89 % of the GW2AR-18 and
> the CPU clock closes with no margin to spare, so no new features fit. Everything that
> works is documented; everything that was left out is listed, with the reasons, in
> [docs/tecnica/09-pendientes.md](docs/tecnica/09-pendientes.md). Larger features live on
> in [MSXimus](https://github.com/Papipapito/MSXimus) (Tang Console 60K).

## Features

* Z80 with authentic MSX timing (per-M1 wait state, ~100% of real MSX speed)
* V9958 VDP with HDMI output
* MSX2+ BIOS · 4 MB mapper · 2 MB Megaram SCC · RTC
* PSG · OPLL · SCC+ (×2) · stereo
* SD card with **Nextor 2.1.4**, boot menu and file browser
* **USB keyboard, joystick and MSX mouse** through an RP2040 companion
* **Turbo** — Panasonic WSX protocol at an exact 5.369318 MHz
* Optional **WiFi** (MSX UNAPI) via ESP-01S, or an **ESP32-C6** that adds a status screen

---

## What's new in v2.0

### 🎛️ One BIOS, and the menu is now an option

There used to be two BIOS builds — one that booted straight to MSX, one with the SD
browser — so you had to pick which one to flash. There is now **a single BIOS** and the
menu is a **setting**: press **S** at boot, tick *Menu al arrancar*, `Save & Restart`.
Untick it and you are back to booting straight into MSX. The choice is stored in flash.

### 📥 Downloads from the boot menu (File-Hunter)

With WiFi connected, press **F** in the browser to search and download ROMs and disk
images straight to the SD card, without a PC.

### 🕹️ RP2040 companion — better keyboards, and an MSX mouse

The onboard **BL616 is no longer used**. USB keyboard, joystick and mouse are now served
by an **RP2040 (Pico Zero)** over a single wire.

This removes the biggest compatibility headache of the previous versions: Tang Nano 20K
boards made since 2024 (marked **`3921`**) ship a BL616 in a secure-boot state that often
could not run the companion firmware, leaving you **without a keyboard** and needing an
external M0S Dock. **With the RP2040 that problem is gone** — every board behaves the same.

And it adds what the BL616 never did: a **real MSX mouse**, from any USB mouse.

### 🖥️ Optional companion screen

Alongside WiFi you can fit an **ESP32-C6 with a 240×240 LCD** that shows connection
status, the clock and whether Turbo is on — plus the classic MSX boot logo. The
**ESP-01S** is still supported if you only want WiFi.

---

## 🔌 Wiring

All three companions are **optional and independent**. The core boots and runs with none
of them (you just get no keyboard, so fit the RP2040 at least).

### FPGA ↔ RP2040 (keyboard, joystick, mouse)

| Pico Zero | Tang Nano 20K | Notes |
|---|---|---|
| **GP15** (TX) | **pin 31** | PIO-UART, 115200 8N1 |
| GND | GND | common ground |
| VBUS | 5V | powers the Pico |

Plug the USB keyboard, gamepad or mouse into the Pico's own USB port (a hub works).

Firmware: **`rp2040_keyboard_zero.uf2`** for the Waveshare **RP2040-Zero** (the default), or
**`rp2040_keyboard_pico.uf2`** for a plain Raspberry Pi Pico — both in the release. Source
and the same binaries are in [`fpga/rp2040/`](fpga/rp2040/) (there the Zero one is named
`rp2040_keyboard.uf2`).

### FPGA ↔ ESP-01S (WiFi only)

| ESP-01S | Tang Nano 20K |
|---|---|
| RX | **pin 27** |
| TX | **pin 28** |
| VCC | 3.3V |
| GND | GND |

### FPGA ↔ ESP32-C6 (WiFi + status screen)

The C6 replaces the ESP-01S on the same UART and adds one wire for the Turbo indicator.

| ESP32-C6 | Tang Nano 20K | Signal |
|---|---|---|
| **GPIO17** (RX) | **pin 27** | FPGA → C6 |
| **GPIO16** (TX) | **pin 28** | C6 → FPGA |
| **GPIO3** | **pin 29** | Turbo status |
| GND | GND | common ground |

Board: Waveshare **ESP32-C6-LCD-1.3**. Firmware: **[ESP32-for-FPGA](https://github.com/Papipapito/ESP32-for-FPGA)**.

---

## 💾 What to flash

Everything is attached to the **[latest release](https://github.com/Papipapito/MSXnano/releases/latest)**.

| Step | File | Address | Tool |
|---|---|---|---|
| 1 | `msxnano_v2.0.fs` | `0x000000` | [Gowin Programmer](https://www.gowinsemi.com/en/support/download_eda/) — External Flash mode |
| 2 | `pack_bios_msxnano.bin` (Nextor 2.1.4, recommended) **or** `pack_bios_msxnano_nextor3.bin` (Nextor 3 beta) | `0x200000` | Gowin Programmer — *exFlash C Bin Erase, Program thru GAO-Bridge* |
| 3 | `rp2040_keyboard_zero.uf2` (RP2040-Zero) **or** `rp2040_keyboard_pico.uf2` (Pico) | — | Drag onto the Pico's `RPI-RP2` drive (hold BOOTSEL while plugging in) |
| 4 | `firmware_esp32c6_v2.0_merged.bin` | `0x0` | `esptool` — only if you fit the ESP32-C6 (the ESP-01S uses the ducasp UNAPI firmware) |

> The BIOS packs bundle the MSX2+ BIOS, sub-ROM, kanji, MSX-MUSIC, Nextor, the WiFi ROM,
> the boot menu and the config block. The system ROMs in them are copyrighted by their
> owners. Flashing a pack resets the saved Settings.

---

## Keyboard

| MSX key | USB key |
|---|---|
| **GRAPH** | Left Alt, or either **Windows** key |
| **CODE / KANA** | Right Alt |
| **STOP** | F12, or Scroll Lock |
| **SELECT** | End |
| **CAPS** | Caps Lock |
| **F6–F10** | F6–F10 — sent as SHIFT+F1..F5, exactly as on a real MSX |
| F1–F5, arrows, HOME/INS/DEL, ESC/TAB/BS/RETURN | 1:1 |

**F11** toggles Turbo on the fly. It can also be set at power-on from **Settings**
(*Boot Turbo*) or by software through the Panasonic ports `$40/$41` (software wins if
both change it in the same cycle).

---

## Slot map

![MSXnano MSX2+ slot map / memory layout for the Tang Nano 20K FPGA core](/pics/mapa_slots4.png)

The layout is fixed by design: **Megaram in slot 2**, SD in **3-2**. SofaRun detects the
Megaram automatically; other software may need it set by hand.

---

## Hardware: case & bill of materials

* Parts list: [`docs/BOM.md`](docs/BOM.md) (spreadsheet: [`docs/MSXnano_BOM.xlsx`](docs/MSXnano_BOM.xlsx)).
* 3D-printable case: [`case/`](case/README.md) — a Bambu Studio project with every part,
  plus the STLs. Two top-left lids: one with a window for the ESP32-C6 screen, one plain.

> The 3D case is based on [this Thingiverse design](https://www.thingiverse.com/thing:4066021), which served as the inspiration and starting point for our improved version.

---

## 📚 Documentation

Full documentation (in Spanish) is in [`docs/INDICE.md`](docs/INDICE.md):

| | |
|---|---|
| [`docs/manual/`](docs/manual/01-que-es.md) | **User manual** — install, SD card, boot menu, ROMs and mappers, keyboard/mouse/joystick, WiFi and File-Hunter, audio/video/turbo, case, troubleshooting |
| [`docs/tecnica/`](docs/tecnica/01-arquitectura.md) | **Technical reference** — architecture, I/O ports, memory maps, the BIOS pack, the RP2040 protocol, synthesis and timing (why nothing more fits), simulation, changelog, open items |
| [`docs/historico/`](docs/historico/README.md) | Index of bug-hunt reports, design documents and retired code kept in the tree |

## Credits

This project is based on the work of **jabadiagm** ([MSXgoauldSD_tn20k](https://github.com/jabadiagm/MSXgoauldSD_tn20k)), licensed under **GPLv3**.

It is a standalone FPGA implementation that does not rely on the original physical MSX hardware, so all hardware-related files (PCB, MSX interface, schematics) have been removed.

**Claude (Anthropic)** collaborated on this project.

---

## Community & links

- 🌐 Project page & guides: [msx.barcelona](https://msx.barcelona)
- 🐙 Other MSX FPGA projects: [github.com/Papipapito](https://github.com/Papipapito)
- 🗣️ Barcelona MSX community: [AAMSX](https://www.aamsx.com)
