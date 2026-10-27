"""MSXsdmaker — prepara tarjetas SD para MSXimus, MSXnano, MSX Pico y MSXBOOK / 1chipMSX: particiones FAT16 de 2 o 4 GB (como el FDISK
de Nextor) o una FAT32, sistema (Nextor 2.1.4, Nextor 3 o MSX-DOS) y programas (SofaRun, Multi Mente...).

  MSXsdmaker                     abre la ventana
  MSXsdmaker listar              tarjetas que se pueden preparar (Windows)
  MSXsdmaker version             esta version y la ultima publicada en GitHub
  MSXsdmaker imagen F.img --tamano 8G [opciones]     crea una imagen (para probar, o para grabarla con Rufus/dd)
  MSXsdmaker tarjeta N [opciones] --si               prepara el disco N de "listar" (BORRA TODO)
opciones: --esquema fat16-2g|fat16-4g|fat32  --n 3  --resto  --sistema nextor214|nextor3|msxdos|ninguno
          --programas todos|ninguno|sofarun,mm,util,...  --etiqueta MSX  --tam-particion 64M (solo pruebas)
con Nextor 3: --sin-yenslash (no pone YENSLASH ON)  --bufinsert (modo insercion)  --dirk bytes (DIR en bytes, como
          MSX-DOS 2)  --btm (AUTOEXEC.BTM en vez de AUTOEXEC.BAT)
MSXBOOK / OneChipBook / 1chipMSX: --maquina ocm [--pack RUTA] (el OCM-SDBIOS Pack de KdL; sin --pack se busca en la
          carpeta OCM-SDBIOS junto al programa). Las BIOS: sin --bios, las de por defecto (--sistema nextor214|nextor3);
          o una --bios por cada una, la principal primero, con las opciones de make-sdb.cmd separadas por comas:
            --bios "OCM-BIOS.DAT=msx2p,nextor3,bsl,logo=2,wifi,extra=3" --bios "DA1=turbor,nextor3,logo-tr"
          tipo msx2p|turbor|msx2|msx1|msx2p33|vacia, disco nextor214|nextor3|megasd1|megasd2, teclado bsl|yen|wst,
          logo=0-9|A-E|propio, wifi|sin-wifi, logo-tr|sin-logo-tr, extra=1|2|3. --programas defecto|todos|...
          (flash = PLDFLASH y SMXFLASH)"""
import argparse
import sys

from sdmaker import VERSION, contenido, dispositivos, novedades, ocm, particiones, proceso


def _tam(texto):
    t = texto.upper().rstrip("B")
    mult = {"K": 1 << 10, "M": 1 << 20, "G": 1 << 30, "T": 1 << 40}.get(t[-1:], 1)
    return int(float(t.rstrip("KMGT")) * mult)


def _grupos(texto, maquina="fpga"):
    todos = [g[0] for g in contenido.grupos_de(maquina)]
    if texto is None:
        texto = "defecto" if maquina == "ocm" else "todos"
    if texto == "todos":
        return set(todos)
    if texto == "defecto":
        return contenido.grupos_por_defecto(maquina)
    if texto == "ninguno":
        return set()
    g = set(texto.split(","))
    malos = g - set(todos)
    if malos:
        sys.exit("programas desconocidos: %s (hay: %s)" % (", ".join(sorted(malos)), ", ".join(todos)))
    return g


def _opciones(ap):
    ap.add_argument("--esquema", default="fat16-2g", choices=["fat16-2g", "fat16-4g", "fat32"])
    ap.add_argument("--n", type=int, default=1, help="cuantas particiones FAT16")
    ap.add_argument("--resto", action="store_true", help="una ultima particion con lo que sobre")
    ap.add_argument("--sistema", default="nextor214", choices=list(contenido.SISTEMAS))
    ap.add_argument("--programas", default=None, help="todos, defecto, ninguno o una lista (sofarun,mm,...)")
    ap.add_argument("--etiqueta", default="MSX")
    ap.add_argument("--tam-particion", default=None, help="tamano de las particiones FAT16 (pruebas)")
    ap.add_argument("--sin-yenslash", action="store_true", help="Nextor 3: sin YENSLASH ON en el AUTOEXEC")
    ap.add_argument("--bufinsert", action="store_true", help="Nextor 3: SET BUFINSERT=ON (modo insercion)")
    ap.add_argument("--dirk", default="defecto", choices=["defecto", "bytes"], help="Nextor 3: DIR en K o en bytes")
    ap.add_argument("--btm", action="store_true", help="Nextor 3: AUTOEXEC.BTM en vez de AUTOEXEC.BAT")
    ap.add_argument("--maquina", default="fpga", choices=list(contenido.MAQUINAS))
    ap.add_argument("--pack", help="ocm: el OCM-SDBIOS Pack de KdL (.7z, .zip o carpeta)")
    ap.add_argument("--bios", action="append", default=[], help="ocm: NOMBRE=receta (ver arriba); repetible")


def _opciones_n3(a):
    return {"yenslash": not a.sin_yenslash, "bufinsert": a.bufinsert, "dirk": "0" if a.dirk == "bytes" else "",
            "btm": a.btm}


def _ocm(a):
    """{"pack", "bios"} para --maquina ocm (o None)."""
    if a.maquina != "ocm":
        return None
    ruta = a.pack or ocm.buscar()
    if not ruta:
        sys.exit("no encuentro el OCM-SDBIOS Pack de KdL: ponlo en la carpeta %s junto al programa o usa --pack"
                 % ocm.CARPETA)
    pack = ocm.abrir(ruta)
    problemas = pack.problemas()
    if problemas:
        sys.exit("el pack %s no vale: %s" % (ruta, "; ".join(problemas)))
    print("   %s" % pack.texto())
    if a.bios:
        lista = []
        for b in a.bios:
            nombre, _, texto = b.partition("=")
            nombre = nombre.strip().upper()
            if nombre.startswith("DA"):
                nombre = "ALT-BIOS." + nombre
            try:
                lista.append((nombre, ocm.leer_receta(texto)))
            except ValueError as e:
                sys.exit(str(e))
    else:
        lista = ocm.por_defecto("nextor3" if a.sistema == "nextor3" else "nextor214")
    try:
        ocm.comprobar_lista(lista)
    except ValueError as e:
        sys.exit(str(e))
    for nombre, r in lista:
        print("   %-13s %s" % (nombre, ocm._ascii(ocm.describir(r, pack))))
    return {"pack": pack, "bios": lista}


def _crear(dev, a):
    datos_ocm = _ocm(a)
    if datos_ocm and a.esquema == "fat32":
        sys.exit("el OCM solo arranca de FAT16")
    tam = _tam(a.tam_particion) // 512 if a.tam_particion else None
    plan = particiones.planificar(dev.sectores, a.esquema, a.n, a.resto, tam)
    for p in plan:
        print("  ", p)
    print("   sin usar: %s" % dispositivos.formato_tamano(particiones.sin_usar(dev.sectores, plan) * 512))

    def aviso(texto, fraccion=None):
        if not texto.startswith("Copiando"):
            print("[%3d%%] %s" % (int((fraccion or 0) * 100), texto))
    inf = proceso.crear(dev, plan, a.sistema, _grupos(a.programas, a.maquina), a.etiqueta, aviso,
                        opciones=_opciones_n3(a), ocm=datos_ocm)
    print("ficheros: %d (%s) en %.1f s" % (inf["ficheros"], dispositivos.formato_tamano(inf["bytes"]), inf["segundos"]))
    for e in inf["errores"]:
        print("ERROR:", e)
    return 1 if inf["errores"] else 0


def main():
    if len(sys.argv) == 1:
        from sdmaker import ventana
        ventana.main()
        return 0
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="orden", required=True)
    sub.add_parser("listar")
    sub.add_parser("version")
    ai = sub.add_parser("imagen")
    ai.add_argument("fichero")
    ai.add_argument("--tamano", required=True, help="p.ej. 8G, 256M")
    _opciones(ai)
    at = sub.add_parser("tarjeta")
    at.add_argument("disco", type=int)
    at.add_argument("--si", action="store_true", help="no preguntar")
    _opciones(at)
    a = ap.parse_args()
    if a.orden == "listar":
        for t in dispositivos.listar_tarjetas():
            print("disco %d: %s, %s (%s), unidades %s" % (t["numero"], t["modelo"],
                  dispositivos.formato_tamano(t["bytes"]), t["bus"], " ".join(t["letras"]) or "-"))
        return 0
    if a.orden == "version":
        u = novedades.ultima()
        print("MSX SD Maker %s; la ultima publicada: %s" % (VERSION, "%s (%s)" % u if u else "no se sabe (sin red?)"))
        return 0
    if a.orden == "imagen":
        dev = dispositivos.Imagen(a.fichero, _tam(a.tamano) // 512)
    else:
        tarjetas = {t["numero"]: t for t in dispositivos.listar_tarjetas()}
        if a.disco not in tarjetas:
            sys.exit("el disco %d no es una tarjeta que se pueda preparar (mira 'listar')" % a.disco)
        t = tarjetas[a.disco]
        if not a.si and input("Se BORRARA TODO el disco %d (%s, %s). Escribe SI: " % (
                a.disco, t["modelo"], dispositivos.formato_tamano(t["bytes"]))).strip() != "SI":
            return 1
        dev = dispositivos.DiscoWindows(a.disco)
    try:
        return _crear(dev, a)
    finally:
        dev.cerrar()


if __name__ == "__main__":
    sys.exit(main())
