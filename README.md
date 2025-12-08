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

## Slot map

Slot map has been updated to improve compatibility without requiring changes.

![Slot map](/pics/mapa_slots4.png)

Mapper and megaram can be relocated to slots 1 or 2 using config menu.

## Megaram + Sofarun
Megaram is detected automatically by sofarun using default settings. When using other software you may need to indicate location, Slot 3-3 by default.

## Known issues
* Tape games fail: use poke -1,0

## Flashing
Progamming is done in three steps:
* Flash firmware MSXnano.fs
* Flash FPGA Companion firmware (https://github.com/MiSTle-Dev/.github/wiki/Firmware-Installation-BL616-%C2%B5C)
* Flash disk rom. MSXnano uses the same driver as Wondertang, Nextor-2.1.1.WonderTANG.ROM.bin. Flash Address = 0x100000 (subject to change)

## YouTube video
https://youtu.be/7KI_Em9QK0Y

## Standalone FPGA version of MSXgoauldSD_tn20k

This project is based on MSXgoauldSD_tn20k by https://github.com/jabadiagm, licensed under GPLv3.

This branch (`standalone`) contains a standalone FPGA implementation.  
All hardware-related files from the original project (PCB, MSX interface, schematics, etc.) have been intentionally removed, because this version does not rely on the original physical hardware.
