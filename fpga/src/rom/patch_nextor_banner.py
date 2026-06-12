#!/usr/bin/env python3
"""Parchea el banner de arranque del driver WonderTANG dentro del pack BIOS.

El banner original (cartucho WonderTANG) lista subslots que no se corresponden
con el MSXnano (FM ROM en SS1, SMS VDP, etc.). Es UNA cadena ASCIIZ de hasta
243 bytes en el offset 0x5C50A del pack (Nextor@0x40000 + 0x1C50A, banco del
driver), impresa de una sola llamada: basta reescribirla (mas corta, terminada
en 0) sin tocar codigo. Uso:  python patch_nextor_banner.py <pack.bin>
"""
import sys

BANNER_OFF = 0x5C50A
BANNER_MAX = 243            # hasta el 0x00 original en 0x5C5FD

NEW = (b"MSXnano SD - WonderTANG! uSD driver\r\n"
       b"2023 Luis Antoniosi\r\n\r\n")

p = sys.argv[1]
d = bytearray(open(p, 'rb').read())
old = bytes(d[BANNER_OFF:BANNER_OFF+16])
assert old.startswith(b'Wonder') or old.startswith(b'MSXnano'), \
    'firma inesperada en 0x%X: %r' % (BANNER_OFF, old)
assert len(NEW) <= BANNER_MAX
d[BANNER_OFF:BANNER_OFF+BANNER_MAX] = NEW + b'\x00' * (BANNER_MAX - len(NEW))
open(p, 'wb').write(d)
print('banner parcheado en %s (%d bytes de texto)' % (p, len(NEW)))
