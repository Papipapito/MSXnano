"""ocm.py — MSXBOOK, OneChipBook, 1chipMSX y demas maquinas con OCM-PLD: la tarjeta se hace con el OCM-SDBIOS Pack de
KdL, que el usuario deja junto al programa, en la carpeta OCM-SDBIOS (el .7z tal como se descarga, o descomprimido).

MSX SD Maker NO lleva nada del pack: las BIOS llevan ROMs de sistema con derechos de terceros. Del pack salen
  make/roms/            las ROMs con las que se monta OCM-BIOS.DAT (el encadenado de make-sdb.cmd, firmware 2 y 3)
  make/sdcreate/os/     MSXDOS2.SYS, NEXTOR.SYS (2.1), COMMAND2.COM y N3XTOR.ZIP (NEXTOR.SYS 3, COMMAND3.COM, UTILS, HELP)
  make/sdcreate/help/   HELP
  make/sdcreate/utils/  UTILS (OCMINFO, SETSMART, SDBIOS.BTM, XSYS3.BTM...)
  make/make-sdb.cmd     solo para saber que ROM de Nextor usa cada opcion y su version

Lo que exige la IPL-ROM del OCM (ocm_iplrom_fat_driver.asm, OCM-PLD 3.9): tabla de particiones (coge la primera entrada
con sector de inicio distinto de 0, sin mirar el tipo), FAT12/16 en esa particion (FAT32 no), OCM-BIOS.DAT (o .DA0-.DA9:
la primera que encuentra) en la RAIZ, y sus 512 KB SEGUIDOS desde su primer cluster: los lee de un tiron. Si algo falla
arranca en silencio la BIOS de la flash (EPBIOS). Aqui OCM-BIOS.DAT es el primer fichero de la raiz y queda en el
cluster 2, como lo deja el sdcreate.cmd de KdL (RTCSAVE y las IPL anteriores a OCM-PLD 3.9.1 lo necesitan ahi)."""
import hashlib
import io
import os
import re
import sys
import tempfile
import zipfile

K = 1024
CARPETA = "OCM-SDBIOS"          # junto al programa: ahi se deja el pack de KdL

# Cada BIOS se describe con un dict (una "receta"), con las mismas opciones que los menus de make-sdb.cmd mas las
# MSX1 y MSX2 que monta su update-all.cmd:
#   tipo     msx2p (firmware 2: MSX2+, OCM-PLD 3.4 o posterior), turbor (firmware 3, "experimental"), msx2, msx1,
#            msx2p33 (firmware 1: MSX2+ para OCM-PLD 3.0-3.3.3, disco de 64 KB) o vacia (firmware 4: 512 KB de FF, la
#            IPL no la acepta y arranca la BIOS de la flash)
#   disco    nextor214 / nextor3 (las ROM de Nextor del menu Disk-ROM) o megasd1 / megasd2 (MegaSDHC FAT16X, MSX-DOS 2,
#            una o dos ranuras SD)
#   teclado  yen, bsl (barra invertida) o wst (occidental); el turboR no tiene occidental
#   logo     0-9 / A-E (el menu Kanji-ROM) o "propio" (KNCUSTOM.ROM + MSXPPOPT.ROM del ++Logo Toolkit); solo MSX2+
#   wifi     BIOS del ESP8266 en la Option-ROM (MSX2+ y turboR)
#   logo_tr  logo del turboR en la Option-ROM (solo turboR)
#   extra    3 BASIC'n turbo 2.1, 2 BASIC'n plus 2.0, 1 ninguna
# Los bloques (firmware 2 y 3, y MSX1/MSX2): DISK 128K + MAIN 32K + EXTRA 16K + MUSIC 16K + SUB 16K + KANJI 32K +
# OPTION 16K + JIS1 128K + JIS2 128K. Firmware 1: DISK 64K + MAIN + SUB + MUSIC + JIS1 + FREE + KANJI + FREE*2 + EXTRA
# + FREE*2 + 128K de FF.
TIPOS = [("msx2p", "MSX2+ (OCM-PLD 3.4 o posterior)"), ("turbor", "MSX turboR (experimental: Z80, sin R800)"),
         ("msx2", "MSX2"), ("msx1", "MSX1"), ("msx2p33", "MSX2+ para OCM-PLD 3.0 a 3.3.3 (1chipMSX antiguo)"),
         ("vacia", "Vacía: la IPL la rechaza y arranca la BIOS de la flash (EPBIOS)")]
NOMBRE_TIPO = {"msx2p": "MSX2+", "turbor": "turboR", "msx2": "MSX2", "msx1": "MSX1", "msx2p33": "MSX2+ (OCM-PLD 3.0-3.3)",
               "vacia": "vacía (BIOS de la flash)"}
DISCOS = ["nextor214", "nextor3", "megasd1", "megasd2"]
MAIN = {"msx2p": {"yen": "A1WSXYEN.ROM", "bsl": "A1WSXBSL.ROM", "wst": "A1WSXWST.ROM"},
        "turbor": {"yen": "MSXTRYEN.ROM", "bsl": "MSXTRBSL.ROM"},
        "msx2": {"yen": "MSX2-YEN.ROM", "bsl": "MSX2-BSL.ROM", "wst": "MSX2-WST.ROM"},
        "msx1": {"yen": "MSX1-YEN.ROM", "bsl": "MSX1-BSL.ROM", "wst": "MSX1-WST.ROM"}}
MAIN["msx2p33"] = MAIN["msx2p"]
TECLADOS = [("bsl", "\\ barra invertida"), ("yen", "¥ yen (japonés)"), ("wst", "occidental")]
EXTRAS = [("3", "BASIC'n turbo 2.1", "XBASIC21.ROM"), ("2", "BASIC'n plus 2.0", "XBASIC20.ROM"),
          ("1", "ninguna", "FREE16KB.ROM")]
LOGOS = [("2", "MSX++ (el oficial)", "KNMSXPPL.ROM"), ("1", "MSX2+", "KNMFIXV2.ROM"), ("0", "sin logo", "KNNOLOGO.ROM"),
         ("B", "OCM genérico", "KNOCMGV2.ROM"), ("9", "1chipMSX-Kai (HRA!)", "KNMKAI15.ROM"),
         ("3", "Sony", "KNSONYV2.ROM"), ("4", "Philips", "KNPHILV2.ROM"), ("D", "Panasonic", "KNPANAV1.ROM"),
         ("5", "Zemmix Neo (Corea)", "KNZNEOKR.ROM"), ("6", "Zemmix Neo (Brasil)", "KNZNEOBR.ROM"),
         ("7", "SX-1 (8bits4ever)", "KNSX-1V4.ROM"), ("A", "SX-2 (8bits4ever)", "KNSX-2V4.ROM"),
         ("E", "SX-E (8bits4ever)", "KNSX-EV7.ROM"), ("8", "SM-X (Victor Trucco)", "KNSM-XV2.ROM"),
         ("C", "u2-SX (Denjhang)", "KNU2SXV3.ROM"), ("propio", "propio (KNCUSTOM.ROM del ++Logo Toolkit)", "KNCUSTOM.ROM")]
TAMANOS = {"disk": 128 * K, "main": 32 * K, "extra": 16 * K, "music": 16 * K, "sub": 16 * K, "kanji": 32 * K,
           "option": 16 * K, "jis1": 128 * K, "jis2": 128 * K}
DEFECTO = {"tipo": "msx2p", "disco": "nextor214", "teclado": "bsl", "logo": "2", "wifi": True, "logo_tr": True,
           "extra": "3"}
FLASHEO = ("PLDFLASH.COM", "SMXFLASH.COM")      # flashean el FPGA: solo si se piden (grupo "flash")
NOMBRES = ["OCM-BIOS.DAT"] + ["ALT-BIOS.DA%d" % i for i in range(10)]


def que_se_puede(tipo):
    """Que opciones tienen sentido en ese tipo (para la ventana y para normalizar)."""
    return {"discos": ["megasd1", "megasd2"] if tipo == "msx2p33" else [] if tipo == "vacia" else list(DISCOS),
            "teclados": list(MAIN.get(tipo, {})), "logo": tipo in ("msx2p", "msx2p33"),
            "wifi": tipo in ("msx2p", "turbor"), "logo_tr": tipo == "turbor", "extra": tipo != "vacia"}


def receta(r=None, **cambios):
    """Una receta completa y valida (lo que no tenga sentido en su tipo queda en su valor por defecto)."""
    o = dict(DEFECTO)
    o.update(r or {})
    o.update(cambios)
    if o["tipo"] not in NOMBRE_TIPO:
        raise ValueError("tipo: %s" % ", ".join(NOMBRE_TIPO))
    q = que_se_puede(o["tipo"])
    if q["discos"] and o["disco"] not in q["discos"]:
        raise ValueError("%s solo con: %s" % (NOMBRE_TIPO[o["tipo"]], ", ".join(q["discos"])))
    if q["teclados"] and o["teclado"] not in q["teclados"]:
        raise ValueError("teclado de %s: %s" % (NOMBRE_TIPO[o["tipo"]], ", ".join(q["teclados"])))
    o["logo"] = str(o["logo"]) if o["logo"] == "propio" else str(o["logo"]).upper()
    if o["logo"] not in {c for c, _, _ in LOGOS} or (o["logo"] == "propio" and o["tipo"] != "msx2p"):
        raise ValueError("logo: 0-9 o A-E (los de make-sdb.cmd), o propio (solo MSX2+)")
    if o["extra"] not in {c for c, _, _ in EXTRAS}:
        raise ValueError("extra: 1, 2 o 3")
    o["wifi"], o["logo_tr"] = bool(o["wifi"]), bool(o["logo_tr"])
    return o


def leer_receta(texto):
    """"turbor,nextor3,yen,logo=B,sin-wifi,extra=2" -> receta (para la linea de ordenes)."""
    r = {}
    for t in (x.strip() for x in texto.split(",") if x.strip()):
        tl = t.lower()
        if tl in NOMBRE_TIPO:
            r["tipo"] = tl
        elif tl in DISCOS:
            r["disco"] = tl
        elif tl in ("bsl", "yen", "wst"):
            r["teclado"] = tl
        elif tl in ("wifi", "sin-wifi"):
            r["wifi"] = tl == "wifi"
        elif tl in ("logo-tr", "sin-logo-tr"):
            r["logo_tr"] = tl == "logo-tr"
        elif tl.startswith("logo="):
            r["logo"] = t[5:]
        elif tl.startswith("extra="):
            r["extra"] = t[6:]
        else:
            raise ValueError("no entiendo %r en la BIOS %r" % (t, texto))
    return receta(r)


def por_defecto(sistema="nextor214"):
    """[(nombre, receta)]: la principal (MSX2+ con WiFi) y una turboR de reserva; con Nextor 3, otra con Nextor 2.1.4."""
    lista = [("OCM-BIOS.DAT", receta(disco=sistema)), ("ALT-BIOS.DA1", receta(tipo="turbor", disco=sistema))]
    if sistema == "nextor3":
        lista.append(("ALT-BIOS.DA2", receta(disco="nextor214")))
    return lista


# ------------------------------------------------------------------ el pack
class Pack:
    """Un OCM-SDBIOS Pack abierto. Solo se leen make/roms, make/sdcreate, make/make-sdb.cmd y readme.txt (en memoria)."""

    def __init__(self, ruta, ficheros):
        self.ruta = ruta
        self.f = {}              # "make/roms/a1wsxbsl.rom" -> (nombre original, datos, mtime)
        for nombre, (datos, mtime) in ficheros.items():
            self.f[nombre.replace("\\", "/").lower()] = (nombre.replace("\\", "/"), datos, mtime)
        m = re.search(rb"OCM-SDBIOS Pack v([0-9.]+)", self.datos("readme.txt") or b"")
        self.version = m.group(1).decode() if m else "?"
        self.nucleos = self._nucleos()

    def datos(self, ruta):
        e = self.f.get(ruta.lower())
        return e[1] if e else None

    def _nucleos(self):
        """{disco: (rom, texto)} sacado del menu Disk-ROM de make-sdb.cmd (asi se sigue al pack): nextor214, nextor3,
        megasd1 y megasd2."""
        sdb = (self.datos("make/make-sdb.cmd") or b"").decode("latin-1")
        textos = dict(re.findall(r"echo (\d) = ((?:Nextor Kernel|MegaSDHC)[^\r\n]*)", sdb))
        out = {}
        for ident, rom in re.findall(r'if "%ID%"=="(\d)" set DISK=([\w.-]+\.ROM)', sdb, re.I):
            t = textos.get(ident, "")
            m = re.search(r"Nextor Kernel v(\d[\w. ]*?) Single", t)
            if m:
                clave = {"2": "nextor214", "3": "nextor3"}.get(m.group(1)[0])
                texto = "Nextor " + m.group(1)
            elif t.startswith("MegaSDHC"):
                clave = "megasd2" if "Double" in t else "megasd1"
                texto = "MegaSDHC FAT16X (MSX-DOS 2), %s" % ("dos ranuras SD" if "Double" in t else "una ranura SD")
            else:
                continue
            if clave and clave not in out and self.datos("make/roms/" + rom) is not None:
                out[clave] = (rom.upper(), texto)
        return out

    def texto_disco(self, disco):
        return self.nucleos[disco][1] if disco in self.nucleos else disco

    def tiene_propio(self):
        """Logo propio: KNCUSTOM.ROM y MSXPPOPT.ROM en make/roms (los deja ahi el ++Logo Toolkit de KdL)."""
        return self.datos("make/roms/kncustom.rom") is not None and self.datos("make/roms/msxppopt.rom") is not None

    def logo_png(self, codigo):
        """La imagen del logo (make/toolkit/logos/default/<nombre>.png) o None."""
        rom = {c: r for c, _, r in LOGOS}.get(codigo, "")
        nombre = rom[2:-4].lower() if rom.startswith("KN") else ""
        return self.datos("make/toolkit/logos/default/%s.png" % nombre) if nombre else None

    def rom(self, nombre, tam=None):
        d = self.datos("make/roms/" + nombre)
        if d is None:
            raise ValueError("falta make/roms/%s en el pack" % nombre.lower())
        if tam is not None and len(d) != tam:
            raise ValueError("make/roms/%s mide %d bytes y deberían ser %d" % (nombre.lower(), len(d), tam))
        return d

    def carpeta(self, ruta):
        """[(nombre, datos, mtime)] de los ficheros que hay directamente en ruta (p.ej. "make/sdcreate/utils")."""
        pre = ruta.lower().rstrip("/") + "/"
        out = []
        for k, (nombre, datos, mtime) in self.f.items():
            if k.startswith(pre) and "/" not in k[len(pre):]:
                out.append((nombre[len(pre):], datos, mtime))
        return sorted(out, key=lambda x: x[0].upper())

    def n3xtor(self):
        """{ruta dentro de N3XTOR.ZIP: (datos, mtime)}: Nextor 3 de KdL (NEXTOR.SYS, COMMAND3.COM, UTILS/, HELP/)."""
        z = self.datos("make/sdcreate/os/n3xtor.zip")
        if z is None:
            return {}
        out = {}
        with zipfile.ZipFile(io.BytesIO(z)) as zf:
            for i in zf.infolist():
                if not i.is_dir():
                    out[i.filename] = (zf.read(i), _mtime_zip(i))
        return out

    def problemas(self):
        """Lo que impide usar el pack: ROMs que no cuadran con make/roms/_checksum.md5 (lo trae el pack) o que faltan."""
        out = []
        lista = self.datos("make/roms/_checksum.md5")
        if lista is None:
            out.append("no está make/roms/_checksum.md5")
        else:
            for linea in lista.decode("latin-1").splitlines():
                m = re.match(r"([0-9a-fA-F]{32}) \*?(\S.*\.rom)$", linea.strip(), re.I)
                if not m:
                    continue
                d = self.datos("make/roms/" + m.group(2))
                if d is None:
                    out.append("falta make/roms/%s" % m.group(2))
                elif hashlib.md5(d).hexdigest() != m.group(1).lower():
                    out.append("make/roms/%s no coincide con _checksum.md5" % m.group(2))
        for f in ("make/sdcreate/os/msxdos2.sys", "make/sdcreate/os/command2.com", "make/sdcreate/os/nextor.sys",
                  "make/sdcreate/utils/sdbios.btm"):
            if self.datos(f) is None:
                out.append("falta %s" % f)
        if "nextor214" not in self.nucleos:
            out.append("no trae Nextor 2.1.4 (hace falta el pack 3.8.1 o posterior)")
        return out

    def texto(self):
        n = ", ".join(self.nucleos[k][1] for k in ("nextor214", "nextor3") if k in self.nucleos)
        return "OCM-SDBIOS Pack v%s de KdL (%s)" % (self.version, n or "sin Nextor")


def _mtime_zip(info):
    import time
    try:
        return time.mktime(info.date_time + (0, 0, -1))
    except (OverflowError, ValueError):
        return None


def _quiero(ruta):
    r = ruta.replace("\\", "/").lower()
    return (r.startswith("make/roms/") or r.startswith("make/sdcreate/") or r == "make/make-sdb.cmd"
            or r == "readme.txt" or (r.startswith("make/toolkit/logos/default/") and r.endswith(".png")))


def abrir(ruta):
    """Pack desde una carpeta (la del pack descomprimido, o una que la contenga) o desde el .7z / .zip descargado."""
    if os.path.isdir(ruta):
        base = _raiz_pack(ruta)
        if base is None:
            raise ValueError("%s no es un OCM-SDBIOS Pack (no tiene make/roms ni make/sdcreate)" % ruta)
        ficheros = {}
        for d, _, ns in os.walk(base):
            for n in ns:
                p = os.path.join(d, n)
                rel = os.path.relpath(p, base).replace("\\", "/")
                if _quiero(rel):
                    with open(p, "rb") as fh:
                        ficheros[rel] = (fh.read(), os.path.getmtime(p))
        return Pack(base, ficheros)
    if ruta.lower().endswith(".zip"):
        with zipfile.ZipFile(ruta) as zf:
            nombres = [i.filename for i in zf.infolist() if not i.is_dir()]
            pre = _prefijo(nombres, ruta)
            ficheros = {i.filename[len(pre):]: (zf.read(i), _mtime_zip(i)) for i in zf.infolist()
                        if not i.is_dir() and i.filename.startswith(pre) and _quiero(i.filename[len(pre):])}
        return Pack(ruta, ficheros)
    if ruta.lower().endswith(".7z"):
        try:
            import py7zr
        except ImportError:
            raise ValueError("para leer el .7z hace falta py7zr; descomprime el pack en la carpeta %s" % CARPETA)
        with py7zr.SevenZipFile(ruta) as z:
            info = {i.filename: i for i in z.list() if not i.is_directory}
            pre = _prefijo(list(info), ruta)
            quiero = [n for n in info if n.startswith(pre) and _quiero(n[len(pre):])]
            with tempfile.TemporaryDirectory(prefix="msxsdmaker_ocm_") as tmp:
                z.extract(path=tmp, targets=quiero)
                ficheros = {}
                for n in quiero:
                    with open(os.path.join(tmp, *n.split("/")), "rb") as fh:
                        t = info[n].creationtime
                        ficheros[n[len(pre):]] = (fh.read(), t.timestamp() if t else None)
        return Pack(ruta, ficheros)
    raise ValueError("%s: el pack tiene que ser una carpeta, un .7z o un .zip" % ruta)


def _prefijo(nombres, ruta):
    """La carpeta del pack dentro del comprimido ("" si make/ esta en la raiz)."""
    for n in nombres:
        if n.lower().endswith("make/make-sdb.cmd"):
            return n[:-len("make/make-sdb.cmd")]
    raise ValueError("%s no es un OCM-SDBIOS Pack (no tiene make/make-sdb.cmd)" % ruta)


def _raiz_pack(carpeta):
    if os.path.isdir(os.path.join(carpeta, "make", "roms")) and os.path.isdir(os.path.join(carpeta, "make", "sdcreate")):
        return carpeta
    for n in sorted(os.listdir(carpeta), key=_clave_version, reverse=True):
        p = os.path.join(carpeta, n)
        if os.path.isdir(p) and os.path.isdir(os.path.join(p, "make", "roms")):
            return p
    return None


def _clave_version(nombre):
    m = re.search(r"v(\d+)\.(\d+)(?:\.(\d+))?", os.path.basename(nombre))
    return tuple(int(x or 0) for x in m.groups()) if m else (0, 0, 0)


def carpeta_programa():
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def buscar():
    """Ruta del pack: MSXSDMAKER_OCM, o en la carpeta OCM-SDBIOS junto al programa (o junto al programa mismo) un .7z /
    .zip con «SDBIOS» en el nombre o una carpeta con el pack descomprimido; si hay varios, el de version mas alta."""
    env = os.environ.get("MSXSDMAKER_OCM")
    if env and os.path.exists(env):
        return env
    base = carpeta_programa()
    for c in (os.path.join(base, CARPETA), base):
        if not os.path.isdir(c):
            continue
        if c != base and _raiz_pack(c) == c:
            return c
        cand = []
        for n in os.listdir(c):
            p = os.path.join(c, n)
            if os.path.isfile(p) and n.lower().endswith((".7z", ".zip")) and "sdbios" in n.lower():
                cand.append(p)
            elif os.path.isdir(p) and c != base and _raiz_pack(p) == p:
                cand.append(p)
        if cand:
            return max(cand, key=_clave_version)
    return None


# ------------------------------------------------------------------ la BIOS
def construir_dat(pack, r):
    """OCM-BIOS.DAT de 512 KB a partir de una receta, como lo montan make-sdb.cmd (MSX2+, turboR, OCM-PLD 3.0-3.3.3 y
    vacia) y update-all.cmd (MSX1 y MSX2)."""
    r = receta(r)
    t = TAMANOS
    free = pack.rom("FREE16KB.ROM", 16 * K)
    tipo = r["tipo"]
    if tipo == "vacia":
        return free * 32
    if r["disco"] not in pack.nucleos:
        raise ValueError("el pack no trae %s" % r["disco"])
    disco = pack.rom(pack.nucleos[r["disco"]][0])
    if r["disco"].startswith("megasd"):
        if len(disco) != 64 * K:
            raise ValueError("la ROM de MegaSDHC deberia medir 64 KB")
        if tipo != "msx2p33":
            disco += pack.rom("NULL64KB.ROM", 64 * K)
    elif len(disco) != t["disk"]:
        raise ValueError("la ROM de Nextor deberia medir 128 KB")
    main = pack.rom(MAIN[tipo][r["teclado"]], t["main"])
    extra = pack.rom({c: n for c, _, n in EXTRAS}[r["extra"]], t["extra"])
    jis1, jis2 = pack.rom("A1XXJIS1.ROM", t["jis1"]), pack.rom("A1XXJIS2.ROM", t["jis2"])
    logo = {c: n for c, _, n in LOGOS}[r["logo"]]
    if tipo == "msx2p33":
        dat = (disco + main + pack.rom("2PEXTR01.ROM", t["sub"]) + pack.rom("MSX2PMUS.ROM", t["music"]) + jis1 + free
               + pack.rom(logo, t["kanji"]) + free * 2 + extra + free * 2 + free * 8)
    elif tipo in ("msx2p", "turbor"):
        tr = tipo == "turbor"
        if tr:
            kanji = pack.rom("KNMFIXV2.ROM", t["kanji"])
            opcion = {(False, False): "EMPTYOPT.ROM", (False, True): "MSXTROPT.ROM", (True, False): "ESP8266E.ROM",
                      (True, True): "ESP8266M.ROM"}[(r["wifi"], r["logo_tr"])]
        elif r["logo"] == "propio":
            kanji, opcion = pack.rom("KNCUSTOM.ROM", t["kanji"]), "MSXPPOPT.ROM"
        else:
            kanji, opcion = pack.rom(logo, t["kanji"]), "ESP8266E.ROM" if r["wifi"] else "FREE16KB.ROM"
        dat = (disco + main + extra + pack.rom("MSXTRMUS.ROM" if tr else "MSX2PMUS.ROM", t["music"])
               + pack.rom("TREXTRTC.ROM" if tr else "2PEXTRTC.ROM", t["sub"]) + kanji + pack.rom(opcion, t["option"])
               + jis1 + jis2)
    else:                                   # msx1 / msx2 (update-all.cmd)
        dat = (disco + main + extra + pack.rom("MSX2PMUS.ROM", t["music"]) + pack.rom("X2EXTRTC.ROM", t["sub"])
               + pack.rom("KNMFIXV2.ROM", t["kanji"]) + free + jis1 + jis2)
    assert len(dat) == 512 * K, len(dat)
    return dat


def describir(r, pack=None):
    r = receta(r)
    if r["tipo"] == "vacia":
        return "vacía: arranca la BIOS de la flash (EPBIOS)"
    q = que_se_puede(r["tipo"])
    p = [NOMBRE_TIPO[r["tipo"]], pack.texto_disco(r["disco"]) if pack else r["disco"],
         "teclado " + {"bsl": "\\", "yen": "yen", "wst": "occidental"}[r["teclado"]]]
    if q["logo"]:
        p.append("logo " + {c: x for c, x, _ in LOGOS}[r["logo"]].split(" (")[0])
    if q["wifi"] and r["logo"] != "propio":
        p.append("WiFi" if r["wifi"] else "sin WiFi")
    if q["logo_tr"]:
        p.append("logo turboR" if r["logo_tr"] else "sin logo turboR")
    p.append({c: x for c, x, _ in EXTRAS}[r["extra"]] if r["extra"] != "1" else "sin Extra-ROM")
    return ", ".join(p)


def nextor_de(r):
    """2, 3 o None: que NEXTOR.SYS necesita esa BIOS."""
    return {"nextor214": 2, "nextor3": 3}.get(r["disco"]) if r["tipo"] != "vacia" else None


def sistema_de(lista):
    """El sistema de la tarjeta: el NEXTOR.SYS de la primera BIOS con Nextor (la principal primero), o MSX-DOS 2."""
    for _, r in lista:
        n = nextor_de(receta(r))
        if n:
            return "nextor3" if n == 3 else "nextor214"
    return "msxdos"


def comprobar_lista(lista):
    nombres = [n for n, _ in lista]
    if not lista or nombres[0] != "OCM-BIOS.DAT":
        raise ValueError("la primera BIOS tiene que ser OCM-BIOS.DAT (la que arranca)")
    if len(set(nombres)) != len(nombres) or any(n not in NOMBRES for n in nombres):
        raise ValueError("nombres de BIOS: OCM-BIOS.DAT y ALT-BIOS.DA0 a .DA9, sin repetir")
    if receta(lista[0][1])["tipo"] == "vacia":
        raise ValueError("la principal no puede ser la vacía")


# ------------------------------------------------------------------ la tarjeta
def poner_sistema(raiz, pack, lista, flasheo, Nodo, meter_datos):
    """Mete en raiz (fatfs.Nodo) las BIOS (las PRIMERAS de la raiz: OCM-BIOS.DAT queda en el cluster 2), el sistema,
    HELP y UTILS del pack. lista = [(nombre, receta)], la principal primero. meter_datos es el de contenido.py.
    Sistema: MSXDOS2.SYS y COMMAND2.COM siempre (MegaSDHC y la BIOS de la flash los usan); NEXTOR.SYS el de la primera
    BIOS con Nextor; si otra lleva el otro Nextor, su NEXTOR.SYS va como N2XTOR.SYS / N3XTOR.SYS para XSYS3.BTM."""
    comprobar_lista(lista)
    datos = [(n, construir_dat(pack, r), describir(r, pack), receta(r)) for n, r in lista]
    for nombre, dat, _, _ in datos:
        meter_datos(raiz, nombre, dat, None)
    os_ = {n.upper(): (d, t) for n, d, t in pack.carpeta("make/sdcreate/os")}
    for f in ("MSXDOS2.SYS", "COMMAND2.COM"):
        meter_datos(raiz, f, *os_[f])
    versiones = [v for v in (nextor_de(r) for _, _, _, r in datos) if v]
    activo = versiones[0] if versiones else None
    n3 = pack.n3xtor() if 3 in versiones else {}
    if 3 in versiones and ("NEXTOR.SYS" not in n3 or "COMMAND3.COM" not in n3):
        raise ValueError("el pack no trae N3XTOR.ZIP con NEXTOR.SYS y COMMAND3.COM (Nextor 3)")
    sys_ = {2: os_["NEXTOR.SYS"], 3: n3.get("NEXTOR.SYS")}
    if activo:
        meter_datos(raiz, "NEXTOR.SYS", *sys_[activo])
        otro = 5 - activo
        if otro in versiones:
            meter_datos(raiz, "N%dXTOR.SYS" % otro, *sys_[otro])
    if 3 in versiones:
        meter_datos(raiz, "COMMAND3.COM", *n3["COMMAND3.COM"])
    help_ = Nodo("HELP", es_dir=True)
    raiz.hijos.append(help_)
    for n, d, t in pack.carpeta("make/sdcreate/help"):
        if n.upper().endswith(".HLP"):              # como sdcreate.cmd: solo los .HLP (no su __readme)
            meter_datos(help_, n, d, t)
    utils = Nodo("UTILS", es_dir=True)
    raiz.hijos.append(utils)
    for n, d, t in pack.carpeta("make/sdcreate/utils"):
        if n.startswith("__") or (n.upper() in FLASHEO and not flasheo):
            continue
        meter_datos(utils, n, d, t)
    if activo == 3:                     # Nextor 3 arranca: sus herramientas y su ayuda encima (lo que pide KdL)
        for ruta, (d, t) in sorted(n3.items()):
            partes = ruta.split("/")
            if len(partes) == 2 and partes[0].upper() in ("UTILS", "HELP"):
                meter_datos(utils if partes[0].upper() == "UTILS" else help_, partes[1], d, t)
    meter_datos(raiz, "BIOS.TXT", texto_bios(pack, datos, activo, versiones), None)
    return datos


def texto_bios(pack, datos, activo, versiones):
    """BIOS.TXT: que BIOS hay y como se cambia (ASCII, CRLF y ^Z como los ficheros de texto de MSX-DOS)."""
    L = ["BIOS de esta tarjeta (%s)" % _ascii(pack.texto()), ""]
    for nombre, _, desc, r in datos:
        L.append("%-13s %s" % (nombre, _ascii(desc)))
        if nombre != "OCM-BIOS.DAT":
            otro = activo and nextor_de(r) and nextor_de(r) != activo
            L.append("%-13s se elige con: %s" % ("", "SDBIOS %s, XSYS3 y reinicio completo (abajo)" % nombre[-1]
                                                 if otro else "SDBIOS %s -R" % nombre[-1]))
    L += ["", "SDBIOS -R vuelve a la principal (OCM-BIOS.DAT).",
          "Si la BIOS no cambia: pulsacion larga del reset o SETSMART -F8FD.",
          "Boton de reset durante el parpadeo inicial: arranca la BIOS de la flash."]
    if activo and len(set(versiones)) > 1:
        # XSYS3 reinicia sin recargar la BIOS (probado en un MSXBOOK, 04/10/2026): hace falta el reinicio completo
        L += ["", "Nextor 2 y Nextor 3 necesitan cada uno su NEXTOR.SYS. Para pasar a una BIOS",
              "con el otro Nextor: SDBIOS n (sin -R), luego XSYS3 (cambia NEXTOR.SYS por",
              "N%dXTOR.SYS) y despues un reinicio completo: pulsacion larga del reset o" % (5 - activo),
              "apagar y encender. Sin el sigue la BIOS de antes y NEXTOR.SYS da el error",
              "de que necesita otro kernel. Para volver: SDBIOS, XSYS3 y reinicio completo."]
    return ("\r\n".join(L) + "\r\n").encode("ascii") + b"\x1a"


def _ascii(t):
    import unicodedata
    return unicodedata.normalize("NFKD", t).encode("ascii", "ignore").decode()
