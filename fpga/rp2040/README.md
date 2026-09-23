# RP2040 companion — USB keyboard, gamepad and mouse

The FPGA has no USB host. This RP2040 firmware is the MSXnano's USB host (TinyUSB): it reads
a USB keyboard, gamepads and a mouse and sends everything to the FPGA over **one wire**.
Derived from the MSXgoauld "Guardian Angel" firmware.

## Wiring (1 wire + power, RP2040 → FPGA)

| RP2040 | Tang Nano 20K | Notes |
|---|---|---|
| **GP15** | **pin 31** (`kbd_uart_rx_pin`) | PIO UART TX, 115200 8N1, idle-high. Data flows RP2040 → FPGA only |
| GND | GND | common ground |
| VBUS | 5V | the Tang powers the RP2040; the RP2040 powers the keyboard / hub |

- 3.3 V LVCMOS on both ends: direct connection, no level shifter.
- GP15 is driven by PIO because the hardware UARTs can't reach it on this board layout.
- Plug the keyboard, gamepad or mouse into the RP2040's own USB port. A self-powered hub
  lets you use all three at once.

## What it does

- **Keyboard** → MSX matrix (`inc/keymaps.h`): GRAPH on Left Alt and both Windows keys,
  CODE/KANA on Right Alt, STOP on F12 / Scroll Lock, SELECT on End, F6–F10 as SHIFT+F1..F5.
- **F11** → turbo toggle (command `0x04`).
- **Gamepads**: generic HID (DirectInput) and **XInput**. All pads go to MSX joystick
  port 1. Buttons 3 and 4 are **autofire** at 10 Hz.
- **Mouse** → a real MSX mouse on joystick port 2 (the protocol is emulated in the FPGA,
  `fpga/src/msx_mouse.v`). The RP2040-Zero LED turns cyan while a mouse is mounted.
- Full-matrix **resync every 250 ms**, so a lost byte never leaves a key stuck.

The wire protocol is frozen; the contract is the header of
[`fpga/src/kbd_uart_rx.v`](../src/kbd_uart_rx.v), explained in Spanish in
[`docs/tecnica/05-companion-rp2040.md`](../../docs/tecnica/05-companion-rp2040.md).

## Firmware files

| Board | In this directory | In the release |
|---|---|---|
| Waveshare RP2040-Zero (default, LED on GPIO16) | `rp2040_keyboard.uf2` | `rp2040_keyboard_zero.uf2` |
| Raspberry Pi Pico (LED on GPIO25) | `rp2040_keyboard_pico.uf2` | `rp2040_keyboard_pico.uf2` |

Same binaries, two names. To flash: hold **BOOTSEL** while plugging the board into a PC and
drag the `.uf2` onto the `RPI-RP2` drive.

## Build Instructions

Before build, make sure to:

* have `pico-sdk` with `tinyusb` library
* check `PICO_SDK_PATH` environment variable linked to `pico-sdk` directory
* have the **Arm bare-metal compiler**: `arm-none-eabi-gcc`
  (on Windows: `winget install --id Arm.GnuArmEmbeddedToolchain`)
* have a **native host C/C++ compiler too** — and this one catches people out.
  SDK 2.x builds `picotool` from source to turn the `.elf` into a `.uf2`, and
  picotool runs on your PC, not on the RP2040, so the Arm compiler alone is not
  enough. On Windows, running the build from a Visual Studio *vcvars64* shell is
  enough; on Linux, `build-essential`.

Both `.uf2` in this directory are built from this source. Rebuild BOTH when you change the
firmware.

```
mkdir build && cd build
cmake -G Ninja .. && ninja      # default = Waveshare RP2040-Zero; add -DRP2040_ZERO=0 for a Pico
```
