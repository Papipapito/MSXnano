#!/usr/bin/env python3
"""mkbanks.py - trocea una imagen de cinta .cvt (CVT1, la genera tsx2msx --tape)
en tape_bankN.hex de 2048 lineas exactas (un byte hex por linea), uno por
primitivo BSRAM de tape_rom.v. Relleno a cero hasta completar el ultimo banco.

Uso:  python mkbanks.py imagen.cvt [num_bancos=9]

Los tape_bankN.hex resultantes estan en .gitignore (contienen datos de juegos
con copyright); este script permite regenerarlos desde el .cvt local.
"""
import sys


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    banks = int(sys.argv[2]) if len(sys.argv) > 2 else 9
    data = open(sys.argv[1], "rb").read()
    cap = banks * 2048
    if len(data) > cap:
        sys.exit(f"imagen de {len(data)}B no cabe en {banks} bancos ({cap}B); "
                 f"sube num_bancos y anade los arrays/readmemh en tape_rom.v")
    data = data.ljust(cap, b"\x00")
    for b in range(banks):
        with open(f"tape_bank{b}.hex", "w") as f:
            f.writelines(f"{x:02X}\n" for x in data[b * 2048:(b + 1) * 2048])
    print(f"{banks} bancos de 2048 lineas escritos ({len(data)}B, "
          f"imagen util {len(open(sys.argv[1], 'rb').read())}B)")


main()
