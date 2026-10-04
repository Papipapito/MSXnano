# Case (3D-printable enclosure)

3D-printable enclosure for the MSXnano (Tang Nano 20K based MSX2+).

## Quick print
Open **`msxnano_case_bambulab.3mf`** in **Bambu Studio** — it contains every part laid
out and ready to print all at once.

**Recommended material: white PETG.**

## Parts (STL)

| File | Part | Qty |
|------|------|-----|
| `Upper_Left_esp32.stl` | Top — left, **with a window for the ESP32-C6 LCD** | 1 (pick one) |
| `upper_left_sin_pantalla.stl` | Top — left, **plain** (ESP-01S or no WiFi module) | 1 (pick one) |
| `upper_right.stl` | Top — right | 1 |
| `lower_left.stl` | Bottom — left, **cut for the [MSXnano carrier v2](https://github.com/Papipapito/MSXnano-Boards/tree/main/carrier)**: USB-C, HDMI and 2 × USB-A out of the back wall, 4 standoffs for the board | 1 |
| `prototipo/lower_left_prototipo.stl` | Bottom — left, previous prototype (Tang + RP2040 wired by hand) | — |
| `lower_right.stl` | Bottom — right | 1 |
| `lower_side.stl` | Bottom side (TN20K case v4) | 1 |
| `keyboard_support_a.stl` | Keyboard support A | 1 |
| `keyboard_support_b.stl` | Keyboard support B | 1 |
| `raspberry_support.stl` | Board support (hand-wired RP2040 build; not needed with the carrier) | 1 |
| `pillar1.stl` | Pillar 1 | 2 |
| `pillar2.stl` | Pillar 2 | 2 |
| `msxnano_case_bambulab.3mf` | Bambu Lab project (all parts) | — |

### The two top-left lids

Only one of the two is printed. The left lid is where the WiFi module sits: choose
`Upper_Left_esp32.stl` if you fit the **Waveshare ESP32-C6-LCD-1.3** (its 240×240 screen
shows through the window), or `upper_left_sin_pantalla.stl` for an ESP-01S or no module.
Every other part is common to both builds.

### Bottom-left for the carrier board (2026-09)

`lower_left.stl` is the original Thingiverse part with the rear window closed and four new
openings for the carrier's rear edge (USB-C power, HDMI, keyboard USB-A, gamepad USB-A), plus
four standoffs printed into the floor on the Raspberry Pi 3 hole pattern (Ø 6 mm, 6.5 mm tall,
Ø 2.2 mm blind holes). The carrier sits on them 10.5 mm above the floor with its rear edge
against the back wall; fix it with 4 × M2.5 × 6–8 screws from the top (they cut their own
thread in the plastic; if you prefer heat-set inserts, open the holes to Ø 3.2 mm).
`raspberry_support.stl` is not needed with the carrier. The lid and the other parts are unchanged.

## Credits
Based on [Spectravideo SVI-728 Retropie case](https://www.thingiverse.com/thing:4066021)
by Palver (CC BY-NC), which served as the inspiration and starting point for this improved
version. The parts here are modified versions of that design.

## Assembly
See the bill of materials in [`../docs/MSXnano_BOM.xlsx`](../docs/MSXnano_BOM.xlsx) (or
[`../docs/BOM.md`](../docs/BOM.md)) and the wiring/flashing steps in the [main README](../README.md).
Step-by-step assembly, in Spanish: [`../docs/manual/09-carcasa.md`](../docs/manual/09-carcasa.md).
