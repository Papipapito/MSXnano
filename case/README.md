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
| `lower_left_interruptor.stl` | Same as `lower_left.stl` plus a hole in the left side for a KCD11-101 rocker power switch (carrier rev B) | 1 (instead of `lower_left.stl`) |
| `lower_left_microsd.stl` | Same as `lower_left.stl` plus a rear microSD slot for a microSD extension cable | 1 (instead of `lower_left.stl`) |
| `lower_left_microsd_interruptor.stl` | microSD slot + rocker switch hole | 1 (instead of `lower_left.stl`) |
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

### Rear microSD slot (2026-10)

The Tang's microSD faces the front, inside the case. `lower_left_microsd*.stl` add a 14 × 2.7 mm
slot in the back wall, left of the USB-C, and two posts for a **microSD extension cable with a metal
socket and two screw ears (holes 25 mm apart)**, 15 cm long (flexible cable ≥ 135 mm). The socket
lies flat on the posts, card mouth against the wall, fixed with 2 × M2.5 self-tapping screws (≤ 8 mm).
The cable runs on the floor under the carrier: fit the socket and the cable before the board, then
plug the extension into the Tang's microSD slot.

### Power switch (carrier rev B, 2026-10)

The carrier rev B powers up through header J13: a jumper keeps it always on (print `lower_left.stl`),
or a rocker switch turns it on and off (print `lower_left_interruptor.stl`). Switch: mini rocker
**KCD11-101** (2 pins, ON-OFF, solder lugs, snap-in; window 9.0 × 13.9 mm in the recessed panel of the
left side, wall thinned to 1.5 mm around it). Solder half of a female-female Dupont lead to each lug
(heat-shrink), snap the switch in from outside and plug the two female ends onto J13 instead of the jumper.

## Credits
Based on [Spectravideo SVI-728 Retropie case](https://www.thingiverse.com/thing:4066021)
by Palver (CC BY-NC), which served as the inspiration and starting point for this improved
version. The parts here are modified versions of that design.

## Assembly
See the bill of materials in [`../docs/MSXnano_BOM.xlsx`](../docs/MSXnano_BOM.xlsx) (or
[`../docs/BOM.md`](../docs/BOM.md)) and the wiring/flashing steps in the [main README](../README.md).
Step-by-step assembly, in Spanish: [`../docs/manual/09-carcasa.md`](../docs/manual/09-carcasa.md).
