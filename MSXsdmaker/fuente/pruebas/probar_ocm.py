"""probar_ocm.py — pruebas de la maquina "ocm" (MSXBOOK, OneChipBook, 1chipMSX) con el OCM-SDBIOS Pack de KdL.

  python pruebas/probar_ocm.py RUTA_DEL_PACK [carpeta de trabajo]

1. Las BIOS: cada combinacion de opciones se monta y se compara con TODAS las que KdL trae hechas en sdbios-*/ (solo si
   el pack esta descomprimido): las de Nextor y MegaSDHC tienen que salir identicas (no se ofrecen la C-BIOS ni la MSX2
   para OCM-PLD 3.0-3.3, que no salen de make-sdb.cmd).
2. Varias tarjetas (imagenes) con MSXsdmaker.py: la IPL simulada (ipl_ocm.py) tiene que cargar OCM-BIOS.DAT del
   cluster 2, contiguo e igual a la receta principal; cada ALT-BIOS igual a su receta; NEXTOR.SYS el de la principal
   (y N2XTOR/N3XTOR si hace falta); UTILS y HELP los del pack (con las de N3XTOR.ZIP encima si arranca Nextor 3);
   sin PLDFLASH/SMXFLASH salvo con el grupo flash; FAT16 en todas las particiones.
Sale con 1 si algo falla."""
import glob
import hashlib
import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(AQUI, ".."))
from sdmaker import dispositivos, ocm, particiones, verificar  # noqa: E402

fallos = 0


def mal(texto):
    global fallos
    fallos += 1
    print("  MAL: " + texto)


def recetas_todas(pack):
    for tipo, _ in ocm.TIPOS:
        q = ocm.que_se_puede(tipo)
        for disco in (q["discos"] or ["nextor214"]):
            if disco not in pack.nucleos:
                continue
            for tec in (q["teclados"] or ["bsl"]):
                logos = [c for c, _, _ in ocm.LOGOS if c != "propio" or (tipo == "msx2p" and pack.tiene_propio())]
                for logo in (logos if q["logo"] else ["2"]):
                    for wifi in ((True, False) if q["wifi"] else (True,)):
                        for ltr in ((True, False) if q["logo_tr"] else (True,)):
                            for ex in ("1", "2", "3"):
                                yield ocm.receta(tipo=tipo, disco=disco, teclado=tec, logo=logo, wifi=wifi,
                                                 logo_tr=ltr, extra=ex)


def probar_bios(pack, ruta):
    print("== 1. BIOS contra las de KdL")
    hechas = sorted(f for f in glob.glob(os.path.join(ruta, "sdbios-*", "*", "*")) if os.path.getsize(f) == 512 * 1024)
    if not hechas:
        print("  (el pack no esta descomprimido: no hay sdbios-*/ con que comparar)")
        return
    nuestras = {hashlib.md5(ocm.construir_dat(pack, r)).hexdigest() for r in recetas_todas(pack)}
    sin = [os.path.relpath(f, ruta) for f in hechas if hashlib.md5(open(f, "rb").read()).hexdigest() not in nuestras]
    esperadas = [s for s in sin if "c-bios" in s or os.path.join("sdbios-k33", "msx2") in s]
    print("  %d hechas por KdL, %d iguales a una nuestra, %d sin pareja (C-BIOS y MSX2 de OCM-PLD 3.0-3.3: %d)"
          % (len(hechas), len(hechas) - len(sin), len(sin), len(esperadas)))
    for s in sin:
        if s not in esperadas:
            mal("sin pareja: " + s)


def leer_fichero(L, ruta):
    import struct
    c = 0
    datos = None
    for parte in ruta.strip("/").split("/"):
        d = L._dir(c)
        hallado = None
        for i in range(0, len(d), 32):
            e = d[i:i + 32]
            if e[0] == 0:
                break
            if e[0] == 0xE5 or e[11] == 0x0F or e[11] & 0x08:
                continue
            n = (e[:8].decode("latin-1").rstrip() + "." + e[8:11].decode("latin-1").rstrip()).rstrip(".")
            if n.upper() == parte.upper():
                hallado = e
                break
        if hallado is None:
            return None
        c = struct.unpack_from("<H", hallado, 26)[0]
        datos = (c, struct.unpack_from("<I", hallado, 28)[0], hallado[11] & 0x10)
    if datos[2]:
        return None
    return L._leer_clusters(datos[0], datos[1])


def caso(nombre, pack, ruta_pack, trabajo, tamano, args, bios=None, flash=False):
    print("== %s: %s %s" % (nombre, tamano, " ".join(args)))
    img = os.path.join(trabajo, nombre + ".img")
    orden = [sys.executable, os.path.join(AQUI, "..", "MSXsdmaker.py"), "imagen", img, "--tamano", tamano,
             "--maquina", "ocm", "--pack", ruta_pack] + args
    for n, texto in (bios or []):
        orden += ["--bios", "%s=%s" % (n, texto)]
    r = subprocess.run(orden, capture_output=True, text=True)
    if r.returncode != 0 or "ERROR" in r.stdout:
        mal("MSXsdmaker: %s %s" % (r.stdout[-400:], r.stderr[-400:]))
        return
    lista = [(n, ocm.leer_receta(t)) for n, t in bios] if bios else ocm.por_defecto(
        "nextor3" if "nextor3" in args else "nextor214")
    lista = [("ALT-BIOS." + n if n.startswith("DA") else n, rr) for n, rr in lista]
    ipl = subprocess.run([sys.executable, os.path.join(AQUI, "ipl_ocm.py"), img], capture_output=True, text=True)
    print("  " + ipl.stdout.strip().replace("\n", "\n  "))
    if ipl.returncode != 0 or "cluster 2 " not in ipl.stdout or "entrada 1 " not in ipl.stdout:
        mal("la IPL no carga OCM-BIOS.DAT desde el cluster 2 como primera entrada")
    dev = dispositivos.Imagen(img)
    try:
        tabla = particiones.leer_tabla(lambda lba: dev.leer(lba))
        if any(t != 0x0E for _, t, _, _ in tabla):
            mal("hay particiones que no son FAT16: %s" % tabla)
        L = verificar.LectorFat(dev, tabla[0][2])
        for n, rr in lista:
            if leer_fichero(L, n) != ocm.construir_dat(pack, rr):
                mal("%s no es su receta" % n)
        print("  %d BIOS iguales a sus recetas" % len(lista))
        os_ = {n.upper(): d for n, d, _ in pack.carpeta("make/sdcreate/os")}
        n3 = {k: v[0] for k, v in pack.n3xtor().items()} if "nextor3" in pack.nucleos else {}
        versiones = [v for v in (ocm.nextor_de(rr) for _, rr in lista) if v]
        sys_ = {2: os_["NEXTOR.SYS"], 3: n3.get("NEXTOR.SYS")}
        if versiones:
            if leer_fichero(L, "NEXTOR.SYS") != sys_[versiones[0]]:
                mal("NEXTOR.SYS no es el de Nextor %d" % versiones[0])
            otro = 5 - versiones[0]
            esta = leer_fichero(L, "N%dXTOR.SYS" % otro)
            if (otro in versiones) != (esta is not None) or (esta is not None and esta != sys_[otro]):
                mal("N%dXTOR.SYS" % otro)
        for f in ("MSXDOS2.SYS", "COMMAND2.COM"):
            if leer_fichero(L, f) != os_[f]:
                mal(f)
        if (3 in versiones) != (leer_fichero(L, "COMMAND3.COM") is not None):
            mal("COMMAND3.COM")
        for sub in ("utils", "help"):
            esperado = {n.upper(): d for n, d, _ in pack.carpeta("make/sdcreate/" + sub) if not n.startswith("__")}
            if sub == "utils" and not flash:
                for f in ocm.FLASHEO:
                    esperado.pop(f, None)
            if versiones and versiones[0] == 3:
                for k, d in n3.items():
                    p = k.split("/")
                    if len(p) == 2 and p[0].lower() == sub:
                        esperado[p[1].upper()] = d
            malos = [n for n, d in esperado.items() if leer_fichero(L, sub.upper() + "/" + n) != d]
            sobran = [k for k in L.listar() if k.upper().startswith("/%s/" % sub.upper())
                      and k.split("/")[-1].upper() not in esperado]
            if malos or sobran:
                mal("%s: distintos %s, sobran %s" % (sub.upper(), malos[:5], sobran[:5]))
            else:
                print("  %s: %d ficheros, los del pack" % (sub.upper(), len(esperado)))
        for f in ("AUTOEXEC.BAT", "AUTOEXEC.BTM"):
            a = leer_fichero(L, f)
            if a:
                lineas = [x for x in a.decode("ascii").replace("\x1a", "").split("\r\n") if x]
                print("  %s: %s" % (f, " | ".join(x for x in lineas if x.upper().startswith(("PATH", "MAPDRV")))))
    finally:
        dev.cerrar()


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    ruta = sys.argv[1]
    trabajo = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.expanduser("~"), "sdimg_ocm")
    os.makedirs(trabajo, exist_ok=True)
    pack = ocm.abrir(ruta)
    print(pack.texto(), "problemas:", pack.problemas() or "ninguno")
    probar_bios(pack, ruta)
    caso("o1_defecto_3x200M", pack, ruta, trabajo, "1G", ["--n", "3", "--tam-particion", "200M"])
    caso("o2_nextor3_resto", pack, ruta, trabajo, "6G", ["--sistema", "nextor3", "--n", "1", "--resto"])
    caso("o3_mezcla", pack, ruta, trabajo, "1G", ["--n", "2", "--tam-particion", "300M", "--programas", "todos"],
         bios=[("OCM-BIOS.DAT", "msx2p,nextor3,yen,logo=B,sin-wifi,extra=2"), ("DA0", "msx1,nextor214,wst"),
               ("DA5", "turbor,megasd1,sin-logo-tr"), ("DA9", "vacia")], flash=True)
    caso("o4_megasd_4g", pack, ruta, trabajo, "5G", ["--esquema", "fat16-4g", "--n", "1"],
         bios=[("OCM-BIOS.DAT", "msx2p,megasd1,logo=9"), ("DA1", "msx2,megasd2,yen,extra=1")])
    if pack.tiene_propio():
        caso("o5_logo_propio", pack, ruta, trabajo, "1G", ["--tam-particion", "300M"],
             bios=[("OCM-BIOS.DAT", "msx2p,nextor214,logo=propio")])
    print("PRUEBAS OCM: %d fallos" % fallos)
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
