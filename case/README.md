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
| `lower_left.stl` | Bottom — left | 1 |
| `lower_right.stl` | Bottom — right | 1 |
| `lower_side.stl` | Bottom side (TN20K case v4) | 1 |
| `keyboard_support_a.stl` | Keyboard support A | 1 |
| `keyboard_support_b.stl` | Keyboard support B | 1 |
| `raspberry_support.stl` | Board support | 1 |
| `pillar1.stl` | Pillar 1 | 2 |
| `pillar2.stl` | Pillar 2 | 2 |
| `msxnano_case_bambulab.3mf` | Bambu Lab project (all parts) | — |

### The two top-left lids

Only one of the two is printed. The left lid is where the WiFi module sits: choose
`Upper_Left_esp32.stl` if you fit the **Waveshare ESP32-C6-LCD-1.3** (its 240×240 screen
shows through the window), or `upper_left_sin_pantalla.stl` for an ESP-01S or no module.
Every other part is common to both builds.

## Credits
Based on [this Thingiverse design](https://www.thingiverse.com/thing:4066021), which served
as the inspiration and starting point for this improved version.

## Assembly
See the bill of materials in [`../docs/MSXnano_BOM.xlsx`](../docs/MSXnano_BOM.xlsx) (or
[`../docs/BOM.md`](../docs/BOM.md)) and the wiring/flashing steps in the [main README](../README.md).
Step-by-step assembly, in Spanish: [`../docs/manual/09-carcasa.md`](../docs/manual/09-carcasa.md).
