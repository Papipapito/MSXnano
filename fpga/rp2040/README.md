# RP2040 companion — USB keyboard, gamepad and mouse

The FPGA has no USB host. This RP2040 firmware is the MSXnano's USB host (TinyUSB): it reads
a USB keyboard, gamepads and a mouse and sends everything to the FPGA over **one wire**.
Derived from the MSXgoauld "Guardian Angel" firmware. XInput host driver:
[Ryzee119/tusb_xinput](https://github.com/Ryzee119/tusb_xinput) (MIT).

## Which file to flash

| Build | Your setup | Flash | In the release |
|---|---|---|---|
| Carrier board | **MSXnano v2 carrier** (RP2040-Zero in its socket, 3 USB-A) | `rp2040_keyboard_carrier.uf2` | — |
| Carrier board | Debug log on the Zero's USB-C. **Tests only, not for normal use** | `rp2040_keyboard_carrier_debug.uf2` | — |
| Hand-wired | Waveshare RP2040-Zero wired to pin 31 (LED on GPIO16) | `rp2040_keyboard.uf2` | `rp2040_keyboard_zero.uf2` |
| Hand-wired | Raspberry Pi Pico wired to pin 31 (LED on GPIO25) | `rp2040_keyboard_pico.uf2` | `rp2040_keyboard_pico.uf2` |
| Tang alone | No RP2040: the Tang's own BL616 | see [`../bl616/README.md`](../bl616/README.md) | — |

The two families are not interchangeable: the hand-wired images use the board's own USB-C as
the host, the carrier images use the carrier's three USB-A sockets and leave the USB-C free.

To flash: hold **BOOTSEL** (BOOT on the Zero) while plugging the board into a PC and drag the
`.uf2` onto the `RPI-RP2` drive. On the carrier the Zero's USB-C is at the board's right edge;
with the carrier powered, hold BOOT and press RESET instead of replugging.

## What it does

- **Keyboard** → MSX matrix (`inc/keymaps.h`): GRAPH on Left Alt and both Windows keys,
  CODE/KANA on Right Alt, STOP on F12 / Scroll Lock, SELECT on End, F6–F10 as SHIFT+F1..F5.
  Several keyboards at once are merged: a key held on any of them is held.
- **F11** → turbo toggle (command `0x04`).
- **Gamepads**: generic HID (DirectInput) and **XInput**. The first pad plugged in goes to MSX
  joystick port 1, the second to port 2; any further pad is OR'd into port 1. When port 1 is
  left without pads, those on port 2 move to port 1 (one-player games read port 1). Buttons 3
  and 4 (XInput: X and Y) are **autofire** at 10 Hz.
  - A dual adapter that shows up as one HID interface with two Report IDs counts as two pads.
  - XInput: one controller per USB device. A wireless Xbox 360 receiver takes a port when its
    controller is switched on, not when the receiver is plugged in.
- **Mouse** → a real MSX mouse on joystick port 2 (the protocol is emulated in the FPGA,
  `fpga/src/msx_mouse.v`). The mouse owns MSX port 2 while it is plugged in: a pad plugged in
  meanwhile is OR'd into port 1, and a pad already on port 2 is hidden by the mouse. The
  firmware repeats the mouse buttons with every resync and releases them when the last mouse
  is unplugged; the FPGA gives port 2 back to a pad only after the next MSX reset.
- **Status LED** (RP2040-Zero NeoPixel): three blue blinks at power-up, then red = nothing
  mounted, green = keyboard, yellow = gamepad, cyan = mouse. White flash = key or pad
  activity, magenta flash = mouse moving.
- Full-matrix **resync every 250 ms**, so a lost byte never leaves a key stuck.

The wire protocol is frozen; the contract is the header of
[`fpga/src/kbd_uart_rx.v`](../src/kbd_uart_rx.v), explained in Spanish in
[`docs/tecnica/05-companion-rp2040.md`](../../docs/tecnica/05-companion-rp2040.md).

## MSXnano v2 carrier board

The RP2040-Zero sits in a socket of the carrier and its USB-C is **not** the host. The host is
[Pico-PIO-USB](https://github.com/sekigon-gonnoc/Pico-PIO-USB) (MIT) bit-banging three GPIO
pairs, each with its own USB-A socket (5 V from the board's rail, not through the Zero):

| Socket | D+ / D− | Where |
|---|---|---|
| J1 | GP26 / GP27 | rear |
| J2 | GP28 / GP29 | rear |
| J5 | GP0 / GP1 | internal, for a keyboard inside the case |

- **Any device works in any socket.** Three sockets, so up to three devices at once, for
  example keyboard + two gamepads, two keyboards + a gamepad, or keyboard + mouse + gamepad
  (with the mouse, the gamepad goes to MSX port 1).
- Pads take the MSX ports in the order they are mounted: plug first the one that must be
  player 1. With several devices plugged in at power-up, the order is that in which they
  finish enumerating.
- **No hubs on the carrier**: Pico-PIO-USB does not handle them reliably. Plug the devices
  straight into J1, J2 and J5. (The hand-wired build, on the board's native USB, does work
  with a self-powered hub.)
- The link to the FPGA (GP15 → pin 31) and its protocol are the same as in the hand-wired
  build. The status LED is the Zero's own NeoPixel (GP16); there is no external WS2812 strip
  (GP26 is J1).

### Debug build

`rp2040_keyboard_carrier_debug.uf2` also makes the Zero's USB-C a USB serial port (CDC,
`CAFE:4A01`, any baud rate). Plug it into a PC and open the port with any terminal (PuTTY,
Tera Term, `screen /dev/ttyACM0`). It prints, in Spanish:

- At boot: firmware and TinyUSB versions, the system clock (must read 120000 kHz) and the
  PIO-USB set-up (`configure=1 host_init=1`, `add=0` for J2 and J5).
- Every USB mount / unmount with VID:PID and socket (`puerto=J1`, `J2` or `J5`), then what the
  firmware made of it: `KBD`, `MOUSE`, `XINPUT`, or `PAD ... -> puerto MSX n` for a gamepad.
- `PIO-USB Jx: línea en SE0 sin enumerar, puerto liberado` when the port watchdog frees a
  socket that got stuck.

The last 2 KB of log are kept until a terminal opens, so the boot lines are still there when
you connect; after that, plug and unplug devices and watch the lines.

Licences of the bundled third-party code are in [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md):
ship it next to the `.uf2` files.

## Wiring of the hand-wired build (1 wire + power, RP2040 → FPGA)

| RP2040 | Tang Nano 20K | Notes |
|---|---|---|
| **GP15** | **pin 31** (`kbd_uart_rx_pin`) | PIO UART TX, 115200 8N1, idle-high. Data flows RP2040 → FPGA only |
| GND | GND | common ground |
| VBUS | 5V | the Tang powers the RP2040; the RP2040 powers the keyboard / hub |

- 3.3 V LVCMOS on both ends: direct connection, no level shifter.
- GP15 is driven by PIO because the hardware UARTs can't reach it on this board layout.
- Plug the keyboard, gamepad or mouse into the RP2040's own USB port. A self-powered hub lets
  you use all of them at once.
- On the carrier all of this is already routed.

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

Three of the four `.uf2` in this directory are built from this source; `rp2040_keyboard_carrier.uf2`
is the build validated on the board, from commit `4c334aa` (before the debug-only link-status line
of `381ebd0`). Rebuild ALL of them when you change the firmware. One build directory per variant (changing the options in an existing
one is not reliable).

| Variant | cmake options |
|---|---|
| RP2040-Zero (default) | — |
| Raspberry Pi Pico | `-DRP2040_ZERO=0` |
| MSXnano v2 carrier | `-DMSXNANO_CARRIER=ON` |
| Carrier, debug log | `-DMSXNANO_CARRIER=ON -DMSXNANO_DEBUG_CDC=ON` |

```
mkdir build && cd build
cmake -G Ninja .. && ninja      # plus the options of the variant
```

The carrier variants use [TinyUSB](https://github.com/hathach/tinyusb) 0.21.0 (Ha Thach) and
Pico-PIO-USB (sekigon-gonnoc) from submodules, both MIT, instead of the SDK's TinyUSB, so
fetch them first, from the repository root:

```
git submodule update --init --depth 1 fpga/rp2040/lib/tinyusb fpga/rp2040/lib/Pico-PIO-USB
```

Pico-PIO-USB is compiled from a copy in the build directory with `PIO_USB_ROOT_PORT_CNT = 3`
(`cmake/stage_pio_usb.cmake`); the submodule is never modified.

The input logic (several keyboards and pads, the port watchdog) is tested on the PC, without
hardware, with `pwsh test/run.ps1` (gcc inside WSL).
