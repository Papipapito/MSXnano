


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
* Authentic MSX timing: per-M1 wait-state (~100% of real MSX speed), with a **Turbo mode** toggled by **F11** (full speed, ~116% / 4.13 MHz)

## What's new in v1.2
* Rebuilt on the **goauld standalone core** (cleaner base) while keeping the standalone / USB / WiFi design.
* **Authentic MSX speed**: added the per-M1 opcode-fetch wait-state that a real MSX board provides, so the CPU runs at ~100% (≈3.58 MHz effective, measured 101%) instead of ~116%. Toggleable via `` `define ENABLE_M1_WAIT `` in `fpga/top.v`.
* **WiFi BIOS integrated**: the ESP8266 UNAPI ROM now ships inside the single BIOS pack flashed at `0x200000` — there is no separate WiFi ROM to flash.
* WiFi UART pins on two consecutive pins for a single connector (`uart_rx` → pin 28, `uart_tx` → pin 27).
* **Claude (Anthropic)** collaborated on this release.

## What's new in v1.7.1

### 🐞 Bug fixes over v1.7
* **Two-stage Konami launch fixed for real (Metal Gear 2 / SD Snatcher boot).**
  v1.7 left a bank register pointing at 0x8000 in the power-on (Konami4) mode, which
  the BIOS RAM probe corrupts on every boot — so two-stage games came up to a blue
  screen. The launcher now initialises the four bank registers in the stub before
  jumping to the cartridge INIT, so these games boot.
* **Mapper detection by ROM content (openMSX-style), not by filename.** Previously a
  filename tag could mislead detection (e.g. the maker word "Konami" forced Konami4
  onto SCC games). Detection now scans the ROM; the filename tag is only a fallback.
* **.dsk mounting fixed** (the Nextor emulation record was being clobbered by the
  menu's depack pass).
* **Boot file list fixed**: files (not just folders) now show on the first listing.
* **Nextor 2.1.4** WonderTANG driver in the BIOS pack.
* **Cartridge SRAM (ASCII8/16)**, **MSX Barcelona boot splash**, and a VRAM-refresh
  fix that removes a stray line of garbage in the Space Manbow intro.

> ⚠️ **Known limitation:** **Metal Gear 2 — Solid Snake** boots and is playable, but
> shows a graphics glitch when gameplay starts (the loading screen does not fully
> clear, mixing with the game). This is a VDP-state issue specific to how the boot
> menu launches the ROM; launching the same game from SofaRun (MSX-DOS) is clean.
> Under investigation. Other Konami SCC games (Space Manbow, Maze of Galious, ...)
> are unaffected.

## What's new in v1.7

### 🎮 Konami mapper (without SCC) — new compatibility
Classic Konami games that use the plain Konami mapper (Nemesis 1, Penguin Adventure,
The Maze of Galious, ...) now load and run from the boot menu: the megaram gained a
true **Konami4 mode** (bank registers at 6000h/8000h/A000h, fixed bank 0, pure-ROM
behaviour immune to Konami's anti-copy pokes).

### 🕹️ Two-stage Konami boots fixed (Metal Gear 2, SD Snatcher)
Games whose cartridge INIT hooks **H.STKE** and returns to the BIOS (expecting the
boot to call them back) used to come up half-booted with garbled tiles. The launcher
now CALLs the cartridge INIT the way the BIOS does and, if the game hooked H.STKE,
invokes the hook itself. (See v1.7.1 above for the follow-up fixes this needed and
the remaining Metal Gear 2 gameplay glitch.)

### 🔎 Browser: search and manual mapper override
* **`/` search**: type part of a name (case-insensitive), ENTER jumps to the next
  match in the current folder; press `/` + ENTER again for the following one.
* **`M` on the confirm screen** cycles the mapper (plain → Konami → KonamiSCC →
  ASCII8 → ASCII16) for ROMs the auto-detection gets wrong — no file renaming needed.
* **Mapper auto-detection aligned with openMSX** `guessRomType`: full credit table
  (including the 77FFh ASCII16 register) and highest-score decision with openMSX
  tie-breaking.

### 🧹 Settings menu cleanup
The slot selectors (Mapper/MegaRam/SD) are gone from the UI — the system layout is
fixed by design (megaram in slot 2, SD in 3-2) and the saved values are preserved.

---

## What's new in v1.6

### 🗂️ Boot menu: SD file browser
The boot menu is now a full SD file browser (File-Hunter style) that starts before the OS:

![SD browser](/pics/menu_browser.png)

* **Launch `.ROM` games** straight into the megaram: mapper auto-detection (code scan)
  plus GoodMSX filename tags (`[KonamiSCC]`, `[ASCII8]`, `[ASCII16]`, ...), progress bar
  and confirm screen with size/mapper.
* **Launch `.DSK` images** via Nextor disk emulation — fully automatic, with a
  fragmentation check. The emulation helper sector is invisible (FAT32: a reserved
  sector of the partition; FAT16: an auto-created hidden file).
* **FAT16 + FAT32** support, auto-detected per partition from the BPB. Hybrid cards
  (e.g. FAT16 + FAT32) work; switch partitions with **TAB**. Long filenames (LFN) with
  marquee scrolling for long names, subdirectories (multi-cluster chains), filter tabs
  **[R]OM / [D]SK / [A]LL**, and entry counter.
* Keys: arrows + RETURN to navigate/launch, BS to go back, R/D/A filters, TAB partition,
  S settings, W WiFi, ESC boots the system (Nextor/MSX-DOS).

### ⚙️ Settings menu (S)
Cleaned up and extended — the always-required goauld toggles (mapper/megaram/SD) are
now forced on and removed from the UI:

![Settings](/pics/menu_settings.png)

| Option | What it does |
|--------|--------------|
| **Second SCC** | Enables a second SCC+ sound chip in the free slot (for dual-SCC players/trackers) |
| **Scanlines** | CRT-style scanlines on the HDMI output |
| **Compatible Mode** | Extra wait-states for picky software |
| **Stereo Sound** | HDMI stereo: PSG1+SCC1+OPLL left / PSG2+SCC2+OPLL right (off = mono on both) |
| **Pantalla 16:9** | HDMI AVI InfoFrame aspect signalling: 4:3 (off) or 16:9 (on). The TV decides pillarbox vs stretch |
| Slots | Mapper / MegaRam / SD slot selection (removed in v1.7 — fixed layout) |



### 🔊 Sound: SCC+ done right (and doubled)
* **Real SCC+ (SCC-I) mode**: B800h window, mode register at BFFEh, independent
  channel-5 waveform — Snatcher-class software works. Wave-RAM read-back fixed
  (software SCC detection used to read 0xFF).
* **Second SCC+**: a sound-only SCC-I "cartridge" in the other free slot, so software
  that drives two SCC cartridges finds both. Toggle in settings.
* **Second PSG** at ports 10h/11h/12h (OCM 2nd-gen standard) with register read-back.
* **HDMI stereo**: true L/R audio over HDMI (see settings table above).
* `tools/scctest/SCCTEST.COM`: detection + sound test for SCC/SCC+ per slot, dual PSG
  and FM, with stereo placement check.

Dual-SCC demo (turn the sound on 🔉):

https://github.com/user-attachments/assets/5fb49364-ebc3-4557-8cf1-1f48a0fafb3f

`SCCTEST.COM` in action:

https://github.com/user-attachments/assets/23cecea7-3888-40bd-9592-7cc60c37a41f

### 🧰 Other
* Critical timing closure improvements in the FPGA (54 MHz domain now closes with
  positive slack; SD-companion CDC constraints documented in the SDC).
* `build.bat` now bundles the new boot menu into the BIOS pack automatically.
* Z80-level emulation test harness for the menu's FAT code
  (`tools/scctest/opcheck/fat32_emu_test.py`).

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
                    │      Pin 28 ─────────────────┼──── ESP-01S TX  ┐
                    │      Pin 27 ─────────────────┼──── ESP-01S RX  │ WiFi
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

## Turbo mode (F11)

The CPU boots at **real-MSX speed** (the authentic per-M1 wait-state, ~100% / 3.58 MHz).
Press **F11** on the USB keyboard to toggle **Turbo** on/off:

| Mode | Speed | LED 5 |
|------|-------|-------|
| Real MSX (default) | ~100% (3.58 MHz) | blinking (~1.8 Hz) |
| Turbo | full speed, ~116% (≈4.13 MHz) | solid on |

The toggle is handled entirely in the FPGA (it never reaches the MSX), survives a soft
reset, and powers on in real-MSX mode. (F11 is used because F12 is captured by the
onboard BL616 FPGA-Companion firmware for its own OSD and never reaches the FPGA.)

## Keyboard (USB → MSX)

USB keyboard via the onboard BL616 (FPGA Companion). Letters and digits are 1:1; the
MSX special keys are mapped as follows:

| MSX key | USB key | Notes |
|---------|---------|-------|
| **GRAPH** | **Right Alt** | |
| **CODE / KANA** | **Left Alt** | Same MSX matrix key — acts as **CODE** with the international BIOS and **KANA** with the Japanese BIOS |
| **CAPS** | Caps Lock | |
| **STOP** | Scroll Lock | |
| **SELECT** | End | |
| ESC / TAB / BS / RETURN | Esc / Tab / Backspace / Enter | |
| Arrows / HOME / INS / DEL | Arrows / Home / Insert / Delete | |
| F1–F5 | F1–F5 | |
| **Turbo toggle** | **F11** | Not an MSX key — toggles CPU speed (see above) |

Notes: **F12 is not usable** (the BL616 FPGA-Companion firmware captures it for its own
OSD). The **Windows key is free** (unassigned). GRAPH and CODE/KANA were added by this
project (stock nano did not map them).

## Slot map

Slot map has been updated to improve compatibility without requiring changes.

![Slot map](/pics/mapa_slots4.png)

Mapper and megaram can be relocated to slots 1 or 2 using config menu.

## Megaram + Sofarun
Megaram is detected automatically by sofarun using default settings. When using other software you may need to indicate location, Slot 3-3 by default.

## Known issues
* Tape games fail: use poke -1,0
* **Metal Gear 2 — Solid Snake**: boots and is playable, but the in-game screen
  glitches when gameplay starts (loading screen doesn't fully clear). VDP-state issue
  tied to the menu launcher; launching from SofaRun (MSX-DOS) is clean. Under
  investigation.

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
| TX (GPIO1)  | Pin 28            | ESP → FPGA |
| RX (GPIO3)  | Pin 27            | FPGA → ESP |
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
