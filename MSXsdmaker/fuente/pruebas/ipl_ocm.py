"""ipl_ocm.py — lee una imagen como la IPL-ROM del OCM (ocm_iplrom_fat_driver.asm de OCM-PLD 3.9) y dice que BIOS
cargaria: la primera entrada del MBR con sector de inicio != 0 (24 bits, sin mirar el tipo), el BPB FAT12/16 de esa
particion, la raiz buscando OCM-BIOS.DAT u OCM-BIOS.DA0-.DA9 (el caracter 11 decide si se comparan 10 u 11), y 512 KB
SEGUIDOS desde su primer cluster. Ademas comprueba que ese fichero este contiguo en la FAT (si no, la IPL cargaria
basura) y, con --esperado, que lo cargado sea ese fichero.

  python ipl_ocm.py imagen.img [--esperado OCM-BIOS.DAT]      sale con 1 si la IPL no encontraria una BIOS buena"""
import argparse
import hashlib
import struct
import sys

SECTOR = 512


def leer(f, lba, n=1):
    f.seek(lba * SECTOR)
    return f.read(n * SECTOR)


def ipl(f):
    mbr = leer(f, 0)
    inicio = None
    for i in range(4):
        e = mbr[446 + 16 * i:462 + 16 * i]
        lba24 = e[8] | e[9] << 8 | e[10] << 16              # la IPL solo usa 3 bytes (CDE)
        if lba24:
            inicio = lba24
            break
    if inicio is None:
        return None, "sin particiones: la IPL arrancaria la BIOS de la flash"
    pbr = leer(f, inicio)
    spc = pbr[13]
    reservados, nfat, raiz_ent = struct.unpack_from("<HBH", pbr, 14)
    spf = struct.unpack_from("<H", pbr, 22)[0]
    if spf == 0 or raiz_ent == 0:
        return None, "la particion 1 no es FAT12/16 (¿FAT32?): BIOS de la flash"
    lba_raiz = inicio + reservados + nfat * spf
    datos = lba_raiz + (raiz_ent + 15) // 16
    for s in range(spf):                                     # la IPL recorre tantos sectores como sectores por FAT
        sec = leer(f, lba_raiz + s)
        for k in range(0, SECTOR, 32):
            e = sec[k:k + 32]
            n = 10 if 0x30 <= e[10] <= 0x39 else 11
            if e[:n] == b"OCM-BIOSDAT"[:n]:
                if e[11] & 0x18:
                    return None, "OCM-BIOS es un directorio o una etiqueta: BIOS de la flash"
                clus = struct.unpack_from("<H", e, 26)[0]
                return {"nombre": e[:11].decode("latin-1"), "cluster": clus, "tamano": struct.unpack_from("<I", e, 28)[0],
                        "inicio": inicio, "spc": spc, "lba": datos + (clus - 2) * spc, "spf": spf,
                        "lba_fat": inicio + reservados, "orden": s * 16 + k // 32}, None
    return None, "no hay OCM-BIOS.DAT ni .DA0-.DA9 en la raiz: BIOS de la flash"


def contiguo(f, r):
    fat = leer(f, r["lba_fat"], r["spf"])
    c, n, salto = r["cluster"], 0, None
    while 2 <= c < 0xFFF8:
        sig = struct.unpack_from("<H", fat, c * 2)[0]
        n += 1
        if 2 <= sig < 0xFFF8 and sig != c + 1 and salto is None:
            salto = (c, sig)
        c = sig
    return n, salto


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("imagen")
    ap.add_argument("--esperado", help="el OCM-BIOS.DAT que deberia cargar")
    a = ap.parse_args()
    with open(a.imagen, "rb") as f:
        r, error = ipl(f)
        if error:
            print("IPL: " + error)
            return 1
        cargado = leer(f, r["lba"], 1024)
        n, salto = contiguo(f, r)
    print("IPL: %s, entrada %d de la raiz, cluster %d (sector %d), %d bytes, md5 de los 512 KB leidos %s"
          % (r["nombre"], r["orden"], r["cluster"], r["lba"], r["tamano"], hashlib.md5(cargado).hexdigest()[:12]))
    mal = 0
    if r["tamano"] != 512 * 1024:
        print("  MAL: no mide 512 KB"); mal += 1
    if salto:
        print("  MAL: el fichero NO esta contiguo (cluster %d -> %d): la IPL leeria otra cosa" % salto); mal += 1
    else:
        print("  contiguo: %d clusters seguidos" % n)
    if r["cluster"] != 2:
        print("  aviso: no esta en el cluster 2 (RTCSAVE y las IPL anteriores a OCM-PLD 3.9.1 lo quieren ahi)")
    if a.esperado:
        esperado = open(a.esperado, "rb").read()
        if cargado == esperado:
            print("  lo cargado es IDENTICO a %s" % a.esperado)
        else:
            print("  MAL: lo cargado NO es %s" % a.esperado); mal += 1
    return 1 if mal else 0


if __name__ == "__main__":
    sys.exit(main())
