rem msx2+ internacional kanji disk fm_logo
echo ---^| MSXnano BIOS pack ^|------------------------------------------
echo -----------------------------------------------------------------------------
echo I/O          128kB  JIS1    .ROM
echo I/O          128kB  JIS2    .ROM
echo 3-2 (4000h)  128kB  NEXTOR  .ROM
echo 0-0 (0000h)   32kB  MSX2P   .ROM
echo 3-1 (0000h)   16kB  MSX2PEXT.ROM
echo 3-1 (4000h)   16kB  FMLOGO  .ROM
echo 0-1 (4000h)   32kB  MSXKANJI.ROM
echo 0-2 (4000h)   16kB  ESP8266 .ROM
echo 0-3 (4000h)   16kB  FREE16KB.ROM
echo                6b   CONFIG  .ROM
echo -----------------------------------------------------------------------------
copy /b a1xxjis1.rom + a1xxjis2.rom + Nextor-2.1.4.WonderTANG.ROM.bin + 32k_msx2p_int_fix.bin + 16k_msx2p_subrom.bin + ..\msxnano_menu\fm_logo_menu.bin + knmsxppl.rom + esp8266e.rom + logo16k.bin + 6b_config.bin goauld_rom_int.bin
copy /b a1xxjis1.rom + a1xxjis2.rom + Nextor-2.1.4.WonderTANG.ROM.bin + a1wsxyen.rom + 2pextrtc.rom + ..\msxnano_menu\fm_logo_menu.bin + knmsxppl.rom + esp8266e.rom + logo16k.bin + 6b_config.bin goauld_rom_japan.bin
rem banner del driver: quitar la info de subslots del WonderTANG original
python patch_nextor_banner.py goauld_rom_int.bin
python patch_nextor_banner.py goauld_rom_japan.bin