# MSX Goa'uld Guardian Angel

> **⚠️🚨 Warning 🚨⚠️**  
> For firmware 090 check 090 branch

The MSX Goa'uld Guardian Angel for hard tasks.

## Wiring (1-wire, RP2040 -> FPGA)

Data is one-directional (RP2040 transmits, FPGA receives) plus a common ground.
The RP2040 is the USB host for the keyboard and is powered from the MSX 5V rail.

| Device            | Function       | Pin    | Connection Note                          |
|-------------------|----------------|--------|------------------------------------------|
| RP2040 UART0 TX   | UART TX (data) | GPIO 0 | -> Tang Nano 20K pin 75 (kbd_uart_rx_pin)|
| RP2040 GND        | Ground         | GND    | -> Tang Nano 20K GND (common ground)     |
| RP2040 VBUS/VSYS  | 5V power in    | VBUS   | -> MSX +5V                               |
| Tang Nano 20K RX  | UART RX (data) | 75     | <- RP2040 GPIO0 (only the FPGA receives) |

- UART **115200 8N1**, idle-high, LSB-first; data flows RP2040 -> FPGA only.
- 3.3 V LVCMOS both ends - direct connection, no level shifter.
- built for the [Waveshare RP2040 Zero](https://www.waveshare.com/wiki/RP2040-Zero) (builtin LED GPIO16); for a Pico add `-DRP2040_ZERO=0`.
- both FPGA and RP2040 firmwares must be the matching pair on this branch.
- power the RP2040 from the MSX 5V supply to its VBUS/VSYS pin.

## Build Instructions

Before build, make sure to:

* have `pico-sdk` with `tinyusb` library
* check `PICO_SDK_PATH` environment variable linked to `pico-sdk` directory

```
mkdir build && cd build
cmake -G Ninja .. && ninja      # default = Waveshare RP2040-Zero; add -DRP2040_ZERO=0 for a Pico
```

## Some ideas

- [x] Scanlines toggle button
- [x] OSD toggle button
- [x] USB Keyboard basic functionalities
- [x] USB Keyboard
- [ ] Local Firmware Switching
- [ ] Persistent Configuration Files
- [ ] USB Gamepad
- [ ] Reset button (needs MSX external mod in reset wire, WIP)
- [ ] USB Floppy Drives
- [ ] USB Mass Storage
- [ ] Ethernet USB adapters
- [ ] WiFi USB adapters
- [ ] BIOS Switching
