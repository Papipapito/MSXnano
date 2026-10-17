"""contenido.py — que se copia a la particion de arranque y el AUTOEXEC.BAT que lo arranca.

Las fuentes son las carpetas de sd/ (la de este repositorio; con el .exe, la que va a su lado en el ZIP de la release,
o si falta, la copia que lleva dentro; ver carpeta_sd):
  base/               lo comun de las SD del MSXimus (MM, UTIL, WIFI, FONTS, musica...)
  nextor-2.1.4/       NEXTOR.SYS + COMMAND2.COM + bin/ (herramientas de Nextor 2)
  nextor-3.0.0-beta2/ NEXTOR.SYS + COMMAND3.COM + bin/ (herramientas de Nextor 3)
  extras/             lo de la SD de la MSX Pico que no estaba en base (SOFARUN, hub, mapper, IA, indev.com) y FPGA
                      (MXUPDATE.COM, que actualiza el core del MSXimus 60K/138K y del MSXnano desde MSX-DOS y, por
                      WiFi, se actualiza el mismo)
El AUTOEXEC.BAT de base/ no se copia: se genera (PATH, alias y MAPDRV segun lo elegido y las particiones creadas).

Con la maquina "ocm" (MSXBOOK, OneChipBook, 1chipMSX...) la BIOS, el sistema, HELP y UTILS salen del OCM-SDBIOS Pack de
KdL (ocm.py) y de sd/ los grupos que sirven en un OCM (sin MXUPDATE ni indev; la musica de OPL4, desmarcada)."""
import os
import re
import sys

from .fatfs import Nodo

SISTEMAS = {
    "nextor214": ("Nextor 2.1.4", "nextor-2.1.4", None),
    "nextor3": ("Nextor 3.0 beta 2", "nextor-3.0.0-beta2", None),
    "msxdos": ("MSX-DOS básico (MSXDOS2.SYS + COMMAND2.COM, y MSXDOS.SYS + COMMAND.COM)", "nextor-2.1.4",
               ["MSXDOS2.SYS", "COMMAND2.COM", "MSXDOS.SYS", "COMMAND.COM"]),
    "ninguno": ("Ninguno (solo formatear)", None, None),
}

# (clave, texto, [origenes relativos a sd/], carpetas del PATH, carpetas vacias que necesita)
GRUPOS = [
    ("sofarun", "SofaRun (lanzador de ROM, DSK y cintas)", ["extras/SOFARUN"], ["SOFARUN"], ["SAVES", "SETTINGS"]),
    ("mm", "Multi Mente (gestor de ficheros)", ["base/MM"], ["MM"], []),
    ("util", "Utilidades (UTIL: 120 programas)", ["base/UTIL"], ["UTIL"], []),
    ("wifi", "Red WiFi / UNAPI (WIFI: hget, ftp, telnet, sntp...)", ["base/WIFI"], ["WIFI"], []),
    ("fonts", "Fuentes de pantalla (FONTS)", ["base/FONTS"], [], []),
    ("musica", "Música (MoonBlaster Wave y FM, RoboPlay, reproductores de MWM y VGM)", ["base/musica"],
     ["musica", "musica\\roboplay"], []),
    ("hub", "HUB (gestor de paquetes msxhub.com)", ["extras/hub"], ["hub"], []),
    ("ia", "IA (cliente de chat con IA; las claves van en IA\\ia.cfg)", ["extras/IA"], ["IA"], []),
    ("varios", "mapper e indev", ["extras/mapper", "extras/indev.com"], ["mapper"], []),
    ("fpga", "Herramientas FPGA (MXUPDATE: actualizar MSXimus 60K/138K y MSXnano)", ["extras/FPGA"], ["FPGA"], []),
]
SIEMPRE = ["FHUNT", "TMP"]      # FHUNT: el menu descarga del File-Hunter ahi y NO puede crear carpetas

# Maquinas: "fpga" = MSXimus, MSXnano, Goa'uld y MSX Pico (lo de siempre); "ocm" = MSXBOOK, OneChipBook, 1chipMSX y
# demas con OCM-PLD, con el pack de KdL. En un OCM no van varios (indev es de la MSX Pico) ni fpga (MXUPDATE es de
# nuestros cores); musica va desmarcado (MBWave, MBFM y MWM son de OPL4: solo con un cartucho MoonSound o parecido) y
# util tambien (UTILS de KdL ya trae las del OCM). flash = PLDFLASH y SMXFLASH de UTILS, que flashean el FPGA.
MAQUINAS = {"fpga": "MSXimus, MSXnano, Goa'uld o MSX Pico",
            "ocm": "MSXBOOK, OneChipBook o 1chipMSX (OCM-PLD), con el OCM-SDBIOS Pack de KdL"}
NO_EN_OCM = {"varios", "fpga"}
GRUPOS_OCM = [("flash", "Flasheo del FPGA (PLDFLASH, SMXFLASH): ¡con cuidado!", [], [], [])]
DESMARCADOS_OCM = {"util", "musica", "flash"}


def grupos_de(maquina):
    """Los grupos que se ofrecen en esa maquina."""
    if maquina == "ocm":
        return [g for g in GRUPOS if g[0] not in NO_EN_OCM] + GRUPOS_OCM
    return list(GRUPOS)


def grupos_por_defecto(maquina):
    return {g[0] for g in grupos_de(maquina)} - (DESMARCADOS_OCM if maquina == "ocm" else set())


def grupos_en_path(maquina):
    """Los grupos en el orden de sus carpetas en el PATH: el de grupos_de, pero con musica delante. musica y SOFARUN
    llevan las dos un VGMPLAY.COM: el de musica es el 1.4 de Grauw y el de SOFARUN, un 1.2 parcheado que SR.COM llama
    por su ruta; asi VGMPLAY a secas (la linea de ordenes y el .VGM/.VGZ de Multi Mente) es el 1.4. musica\\roboplay va
    en el PATH porque RoboPlay busca sus .PLY junto a ROBOPLAY.COM: llamandolo a secas, la linea de Multi Mente es corta
    y su lista de marcados ($T) baja menos la TPA (RoboPlay usa 0xC000-0xD3FF)."""
    return sorted(grupos_de(maquina), key=lambda g: g[0] != "musica")

# Unidades del MAPDRV del AUTOEXEC para las particiones 2, 3... MSX-DOS 2 y Nextor solo tienen de la A: a la H:, asi
# que la 8 va en B:. Probado en openMSX con Nextor 2.1.4: sin disquetera (como el MSXimus) B: esta libre ("Invalid
# drive") y MAPDRV la monta; con disquetera, MAPDRV le quita la B: hasta reiniciar o hasta MAPDRV B: D.
UNIDADES = "CDEFGHB"

# Opciones del AUTOEXEC con Nextor 3 (beta 2, COMMAND3.COM); con Nextor 2.1.4 y MSX-DOS no se usan.
#   yenslash: YENSLASH ON, la orden INTERNA de COMMAND3.COM (desde la beta 2): barra invertida en vez de yen. La
#             orden interna tiene preferencia sobre el YENSLASH.COM de UTIL, y sin parametros solo dice el estado.
#   bufinsert: SET BUFINSERT=ON, la linea de ordenes empieza en modo insercion.
#   dirk: "" = lo de Nextor 3 (tamanos en K desde 10K); "0" = como MSX-DOS 2 (bytes; los totales en K).
#   btm: AUTOEXEC.BTM en vez de AUTOEXEC.BAT (COMMAND3.COM lo carga entero: admite GOTO, GOSUB, RETURN y END).
OPCIONES_N3 = {"yenslash": True, "bufinsert": False, "dirk": "", "btm": False}


def opciones_n3(opciones=None):
    o = dict(OPCIONES_N3)
    o.update(opciones or {})
    if o["dirk"] not in ("", "0"):
        raise ValueError("DIRK: \"\" o \"0\"")
    return o


def nombre_autoexec(sistema, opciones=None):
    return "AUTOEXEC.BTM" if sistema == "nextor3" and opciones_n3(opciones)["btm"] else "AUTOEXEC.BAT"
EXCLUIR_EXT = (".bak", ".tmp")
EXCLUIR = {"ruvector.db", "thumbs.db", "desktop.ini", "autoexec.bat", "autoexec.btm", "nextor.emu", "_nextor.psf"}


def carpeta_sd():
    """El contenido de la SD: MSXSDMAKER_SD; o la carpeta sd/ junto al .exe (la trae el ZIP de la release: lo que se
    cambie ahi es lo que se copia); o la copia que lleva dentro el .exe (si sd/ falta o no tiene base/); o, sin .exe, la
    carpeta sd/ junto a MSXsdmaker.py."""
    candidatas = [os.environ.get("MSXSDMAKER_SD")]
    if getattr(sys, "frozen", False):
        candidatas.append(os.path.join(os.path.dirname(sys.executable), "sd"))
    if getattr(sys, "_MEIPASS", None):
        candidatas.append(os.path.join(sys._MEIPASS, "sd"))
    candidatas.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sd"))
    for c in candidatas:
        if c and os.path.isdir(os.path.join(c, "base")):
            return os.path.normpath(c)
    raise FileNotFoundError("no encuentro el contenido de la SD (carpeta sd/ con base/, nextor-2.1.4/...)")


def _excluido(nombre):
    n = nombre.lower()
    return n.startswith(".") or n in EXCLUIR or n.endswith(EXCLUIR_EXT)


def _asegurar_dir(padre, nombre):
    d = padre.hijo(nombre)
    if d is None:
        d = Nodo(nombre, es_dir=True)
        padre.hijos.append(d)
    return d


def _meter(padre, ruta, nombre=None):
    """Copia ruta (fichero o carpeta) dentro de padre; un fichero con el mismo nombre (sin mayusculas) se sustituye."""
    nombre = nombre or os.path.basename(ruta)
    if _excluido(nombre):
        return
    if os.path.isdir(ruta):
        d = _asegurar_dir(padre, nombre)
        d.mtime = os.path.getmtime(ruta)
        for n in sorted(os.listdir(ruta), key=str.upper):
            _meter(d, os.path.join(ruta, n))
    else:
        viejo = padre.hijo(nombre)
        if viejo is not None:
            padre.hijos.remove(viejo)
        padre.hijos.append(Nodo(nombre, origen=ruta, mtime=os.path.getmtime(ruta)))


def meter_datos(padre, nombre, datos, mtime=None):
    """Como _meter pero con los datos en memoria (lo que sale del pack de KdL o se genera)."""
    viejo = padre.hijo(nombre)
    if viejo is not None:
        padre.hijos.remove(viejo)
    padre.hijos.append(Nodo(nombre, datos=datos, mtime=mtime))


# Ordenes internas de COMMAND2/COMMAND3: en MMRET.DAT no se buscan como programa.
INTERNAS_MM = set("ALIAS ASSIGN ATDIR ATTRIB BASIC BUFFERS CD CHDIR CLS COPY DATE DEL DIR DISKCOPY ECHO ERA ERASE EXIT "
                  "FIXDISK FORMAT HELP KMODE MD MKDIR MODE MOVE MVDIR PATH PAUSE RAMDISK RD REM REN RENAME RMDIR RNDIR "
                  "SET TIME TYPE UNDEL VER VERIFY VOL YENSLASH".split())


def ajustar_mmret(raiz, grupos, maquina):
    """Quita de MM\\MMRET.DAT las asociaciones cuyo programa no va en la tarjeta: con ellas RETURN solo daria "***
    Unrecognized command"; sin ellas, el fichero cae en la ultima, '.???' (el visor). Como lo lee Multi Mente 2.07: solo
    cuentan las lineas que empiezan por '.' o ':'; la orden va tras los blancos, hasta el primer caracter de control, y
    su programa se busca en la raiz y en las carpetas del PATH (musica\\roboplay incluida)."""
    mm = raiz.hijo("MM")
    nodo = mm.hijo("MMRET.DAT") if mm else None
    if nodo is None:
        return
    datos = nodo.datos if nodo.datos is not None else open(nodo.origen, "rb").read()
    carpetas = ["BIN"] + (["UTILS"] if maquina == "ocm" else [])
    carpetas += [c for clave, _, _, cs, _ in grupos_en_path(maquina) if clave in grupos for c in cs]

    def carpeta(ruta):
        n = raiz
        for p in ruta.split("\\"):
            n = n.hijo(p) if n is not None else None
        return n
    sitios = [raiz] + [d for d in map(carpeta, carpetas) if d is not None]

    def esta(prog):
        if not prog or prog.startswith("$") or prog.upper() in INTERNAS_MM or any(c in prog for c in "%\\:"):
            return True         # $V, $C (el propio .COM o .BAT), BASIC o una ruta: no se toca
        nombres = [prog] if "." in prog else [prog + e for e in (".COM", ".BAT", ".BTM")]
        return any(s.hijo(n) is not None for s in sitios for n in nombres)

    def sin_orden(linea):       # un patron sin orden: MM ejecuta la orden de la linea siguiente
        return linea[:1] in (b".", b":") and len(linea.split(None, 1)) == 1

    lineas = []
    for linea in datos.split(b"\n"):
        partes = linea.split(None, 1)
        if linea[:1] in (b".", b":") and len(partes) > 1:
            orden = re.split(rb"[\x00-\x1f]", partes[1])[0]
            if not esta(orden.split(b" ")[0].decode("ascii", "replace")):
                while lineas and sin_orden(lineas[-1]):     # se van con ella los patrones que caian en esta
                    lineas.pop()
                continue
        lineas.append(linea)
    nuevo = b"\n".join(lineas)
    if nuevo != datos:
        meter_datos(mm, nodo.nombre, nuevo, nodo.mtime)


def arbol(sistema, grupos, particiones, raiz_sd=None, opciones=None, ocm=None):
    """Nodo raiz de la particion de arranque. particiones = cuantas hay en la tarjeta (para el MAPDRV); opciones = las
    de Nextor 3 (OPCIONES_N3); ocm = {"pack": ocm.Pack, "bios": [(nombre, receta)]} para la maquina "ocm" (el
    sistema lo deciden entonces sus BIOS: ocm.sistema_de)."""
    sd = raiz_sd or carpeta_sd()
    raiz = Nodo("", es_dir=True)
    maquina = "ocm" if ocm else "fpga"
    if ocm:
        from . import ocm as _ocm
        sistema = _ocm.sistema_de(ocm["bios"])
    nombre, carpeta, lista = SISTEMAS[sistema]
    if ocm:
        _ocm.poner_sistema(raiz, ocm["pack"], ocm["bios"], "flash" in grupos, Nodo, meter_datos)
    elif carpeta:
        base = os.path.join(sd, carpeta)
        if lista:
            for f in lista:
                _meter(raiz, os.path.join(base, f))
        else:
            for n in sorted(os.listdir(base), key=str.upper):
                _meter(raiz, os.path.join(base, n))
    for clave, _, origenes, _, vacias in grupos_de(maquina):
        if clave not in grupos:
            continue
        for o in origenes:
            _meter(raiz, os.path.join(sd, *o.split("/")))
        for v in vacias:
            _asegurar_dir(raiz, v)
    if "mm" in grupos and sistema != "ninguno":     # sin sistema no hay PATH con el que comparar
        ajustar_mmret(raiz, grupos, maquina)
    if sistema != "ninguno":
        for v in (["TMP"] if ocm else SIEMPRE):
            _asegurar_dir(raiz, v)
        raiz.hijos.append(Nodo(nombre_autoexec(sistema, opciones),
                               datos=autoexec(sistema, grupos, particiones, raiz, opciones, maquina)))
        if ocm:     # REBOOT.BAT: lo ejecuta MSX-DOS al volver de BASIC con CALL SYSTEM (el PATH se pierde)
            meter_datos(raiz, "REBOOT.BAT", autoexec(sistema, grupos, particiones, raiz, opciones, maquina, False))
    return raiz


def autoexec(sistema, grupos, particiones, raiz, opciones=None, maquina="fpga", arranque=True):
    """AUTOEXEC.BAT o .BTM (CRLF y ^Z al final, como los de MSX-DOS 2). %1 = unidad de arranque. arranque=False: el
    REBOOT.BAT (solo PATH, alias y variables)."""
    n3 = sistema == "nextor3"
    ocm = maquina == "ocm"
    o = opciones_n3(opciones)
    def hay(*ruta):
        n = raiz
        for p in ruta:
            n = n.hijo(p) if n else None
        return n is not None

    path = ["A:\\"]
    if hay("bin"):
        path.append("%1\\BIN")
    if ocm:
        path.append("%1\\UTILS")
    for clave, _, _, carpetas, _ in grupos_en_path(maquina):
        if clave in grupos:
            path += ["%1\\" + c for c in carpetas]
    if not arranque:      # REBOOT.BAT: %1 no vale ahi; la de arranque es A:
        path = [p.replace("%1", "A:") for p in path]
    L = ["PATH " + ";".join(path), "SET TIMEZONE=+02:00", "mode 80",
         'ALIAS .BAS = "BASIC "', 'ALIAS .ASC = "BASIC "']
    if "wifi" in grupos and not ocm:      # en el OCM, sin el ESP8266 conectado sntp para el arranque
        L.append("sntp pool.ntp.org /v")
    L.append("set temp %1\\TMP")
    if "mm" in grupos:
        L.append("set MM=%1\\MM")
    if hay("UTIL", "MGSDRV.COM"):       # MGSC (el .MUS de Multi Mente) carga MGSDRV solo si sabe donde esta
        L.append("set MGSDRV=%1\\UTIL\\MGSDRV.COM")
    if "sofarun" in grupos:
        L += ["alias .ROM srom", "alias .DSK sri"]
    if n3:
        if o["yenslash"]:
            L.append("YENSLASH ON")
        if o["bufinsert"]:
            L.append("SET BUFINSERT=ON")
        if o["dirk"]:
            L.append("SET DIRK=" + o["dirk"])
    elif hay("UTIL", "YENSLASH.COM") and not ocm:
        L.append("yenslash")
    if not arranque:
        L = [x.replace("%1", "A:") for x in L if not x.startswith("mode")]
        return ("\r\n".join(L) + "\r\n").encode("ascii") + b"\x1a"
    if hay("FONTS", "ISO-LAT1.FNT"):
        L.append("SET FONT0808=%1\\FONTS\\ISO-LAT1.FNT")
    if hay("UTIL", "LOGIN.COM"):
        L.append("echo Type LOGIN to show system info (not for MSX1!)")
    if hay("UTIL", "DI.COM"):
        L.append("echo Type DI for DIR with long filenames")
    if "sofarun" in grupos:
        L.append("echo Type SR to start Sofarun")
    if "mm" in grupos:
        L.append("echo Type MM to start Multi Mente")
    if "hub" in grupos:
        L.append("echo Type HUBG to start HUB Gui or HUB to CLI")
    if hay("WIFI", "FH.COM") or hay("UTIL", "FH.COM") or hay("UTILS", "FH.COM"):
        L.append("echo Type FH to FileHunter Download")
    if ocm:
        L.append("echo Type BIOS.TXT for the BIOS on this card (SDBIOS n -R)")
    mapdrv = hay("bin", "MAPDRV.COM") or hay("UTIL", "MAPDRV.COM") or hay("UTILS", "MAPDRV.COM")
    donde = "3-2" if ocm else "0"       # OCM: Nextor en el slot 3-2, como en el MAPDRIVE.BAT de KdL
    if particiones > 1:
        letras = UNIDADES[:particiones - 1]
        L.append("echo")
        if ocm and sistema == "msxdos":         # MegaSDHC sin Nextor: no hay MAPDRV
            L.append("echo Partitions 2-%d: only with a Nextor BIOS (MAPDRV)" % particiones)
        elif mapdrv:
            L.append("echo Maped Units " + ",".join(letras))
            for i, u in enumerate(letras):
                L.append("mapdrv %s: %d 1 %s" % (u.lower(), i + 2, donde))
        else:
            L.append("echo Partitions 2-%d: map them with CALL MAPDRV from BASIC" % particiones)
    return ("\r\n".join(L) + "\r\n").encode("ascii") + b"\x1a"


def resumen(raiz):
    """(ficheros, bytes) del arbol."""
    nf = nb = 0
    pila = [raiz]
    while pila:
        d = pila.pop()
        for h in d.hijos:
            if h.es_dir:
                pila.append(h)
            else:
                nf += 1
                nb += len(h.datos) if h.datos is not None else os.path.getsize(h.origen)
    return nf, nb
