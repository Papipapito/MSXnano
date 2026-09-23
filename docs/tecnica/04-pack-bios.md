# 04. El pack de BIOS

El **pack** (`pack_bios_msxnano.bin` en la release, `bin/goauld_rom_int.bin` en el repo;
524.294 bytes = 512 KB + 6) es todo lo que el MSX
necesita en ROM, concatenado en un solo fichero que se graba en la flash a `0x200000` y
que el core copia a la SDRAM al arrancar. No tiene cabecera ni índice: **la FPGA sabe qué
hay en cada offset porque está cableado en `top.v`**.

## Anatomía

| Offset | Tamaño | Contenido | Va a SDRAM | Fuente |
|---|---|---|---|---|
| `0x00000` | 128 KB | Kanji JIS1 (`a1xxjis1.rom`) | `0x700000` | propietaria (Panasonic) |
| `0x20000` | 128 KB | Kanji JIS2 (`a1xxjis2.rom`) | `0x720000` | propietaria |
| `0x40000` | 128 KB | **Nextor 2.1.4**: kernel (bancos 0-6) + driver de la WonderTANG (banco 7, desde `0x5C100`) | `0x740000` | kernel de Konamiman (libre) + driver BSD-2 de Luis Antoniosi |
| `0x60000` | 32 KB | BIOS MSX2+ **internacional** (`32k_msx2p_int_fix.bin`) | `0x760000` | propietaria + parche |
| `0x68000` | 16 KB | Sub-ROM MSX2+ | `0x768000` | propietaria |
| `0x6C000` | 16 KB | BIOS **MSX-MUSIC** + **el menú del MSXnano** (desde `+0x760`) | `0x76C000` | mixto: FM propietario, menú del proyecto |
| `0x70000` | 32 KB | Driver kanji (`knmsxppl.rom`) | `0x770000` | propietaria |
| `0x78000` | 16 KB | ROM WiFi UNAPI (`esp8266e.rom`) | `0x778000` | binario heredado del ecosistema ESP8266-UNAPI |
| `0x7C000` | 16 KB | Logo de arranque (`logo16k.bin`, magic `LG`) | `0x77C000` | del proyecto (`make_logo16k.py`) |
| `0x80000` | 6 B | Cola de configuración: `41 42` ("AB") + `config1` + `config2` + turbo de arranque + relleno | registros | del proyecto |

El kanji y la sub-ROM coinciden con las de un **Panasonic FS-A1FX** en la base de datos
de openMSX. La BIOS principal no coincide con ninguna porque está parcheada.

### El parche `int_fix`

Son **49 bytes en 16 tramos** sobre la BIOS japonesa, y es 100 % internacionalización;
no hay correcciones de bugs:

| Dirección | Qué cambia |
|---|---|
| `002Bh-002Ch` | Flags de charset / teclado / BASIC: japonés → internacional |
| `0DC9h`, `0DE3h` | Tablas de símbolos con y sin Shift (reordena `@ [ ] ^ _ \ { } : " ~`) |
| `13F5h` | Cadenas de las teclas de función (`files` → `cont`) |
| `1E9Fh` | Glifo del `5Ch`: **¥ → \\** |
| `7F92h` | Color de borde por defecto 4 → 7 |

Otros puntos de referencia dentro de la BIOS: la fuente (`CGTABL`) en `1BBFh` y la capa
KANA del teclado en `0FB6h` (la candidata para meter la ñ; ver [09](09-pendientes.md)).

## Por qué no está todo en el repo

La BIOS, la sub-ROM, el kanji, el driver kanji y la ROM de MSX-MUSIC son **software con
copyright** (Panasonic/ASCII/Microsoft). El proyecto no tiene derecho a redistribuirlos,
por lo que:

- Los ficheros sueltos están en el `.gitignore`.
- Lo que sí es del proyecto (menú, logo, cola de config, herramientas) tiene fuente en el
  repo `bios-msxnano-msximus`, que es **privado**.
- Los dos packs montados (Nextor 2.1.4 y Nextor 3 beta) van como *assets* de la release,
  por decisión y bajo la responsabilidad del autor. `bin/goauld_rom_int.bin` es el mismo
  pack de Nextor 2.1.4 de la v2.0 (md5 `4dc4e4f5…`, commit `c9f8595` del repo de BIOS).

## Herramientas (en `bios-msxnano-msximus`, privado)

| Herramienta | Qué hace |
|---|---|
| `hacer_packs.py` | Construye los packs de una tacada a partir de una base + el menú recién ensamblado. Para el MSXnano deja la cola de 6 bytes (`config2 = 07`: menú al arrancar OFF, límite de sprites OFF); para el MSXimus recorta la cola |
| `desmontar_pack.py` | Corta un pack por los offsets de la tabla y **verifica reconcatenando** que reproduce el original byte a byte. Así se recuperaron las ROMs que no estaban en disco |
| `insertar_en_pack.py` | Sustituye un bloque (típicamente el menú a `0x6C000` o el logo a `0x7C000`) |
| `tools/patch_nextor_banner.py` | Cambia el banner "WonderTANG" de Nextor por "MSXnano" (offset `0x5C50A` del bloque Nextor) |
| `src/rom/build.bat` (este repo) | El `copy /b` original: reconstruye el pack desde las 10 ROMs sueltas si las tienes |

## Regla de oro: el menú y el logo van a pares

Para que el logo de arranque salga hacen falta **las dos cosas**: el `logo16k` con el
magic `LG` en `0x7C000` **y** un menú que lo llame (`CALLF 8C:4002`, verificable como
`F7 8C 02 40` cerca de `+0x7DF` del bloque `0x6C000`). Un pack con logo pero con un menú
viejo no muestra nada. Los packs de `bin/` de las releases lo cumplen desde la v1.8.

## Cola de configuración

Los 6 bytes finales son los mismos que Ajustes escribe con *Save & Restart*
(`flash_write_din` en `top.v`):

| Byte | Valor | Significado |
|---|---|---|
| 0 | `41` | 'A' |
| 1 | `42` | 'B' — la firma. Sin ella el core ignora el bloque y usa `CONFIG1_DEFAULT` / `CONFIG2_DEFAULT` |
| 2 | `config1` | bit 0 mapper activo · bits 5:4 slot del mapper (`11` = 3-0) · bit 1 Megaram activa · bits 7:6 slot de la Megaram (el OCM la fuerza al 2) · bit 2 segundo SCC · bit 3 scanlines. Por defecto `F3` |
| 3 | `config2` | bit 0 SD activa · bits 2:1 slot de Nextor · **bit 3 libre en el RTL: lo usa el menú como "menú al arrancar"** · bit 4 límite de 8 sprites/línea · bit 5 estéreo. Por defecto `07` |
| 4 | `54` / `00` | 'T' = arrancar en turbo |
| 5 | `FF` | Relleno |

Consecuencia ya dicha en [03](03-mapas-memoria.md): grabar un pack nuevo restaura estos
6 bytes, o sea, **pisa los ajustes guardados**.

## Versión del core vs versión del pack

Desde la v2.0 **nadie lo comprueba**: el menú lee el puerto `0x2F` solo para enseñarlo en
Ajustes (el guardián que avisaba en la v1.9 se quitó a propósito). Pero el mapa de puertos
y el mapa de offsets siguen cableados en los dos lados, y un desajuste puede dar desde
rarezas hasta un menú que no arranca. Los packs de cada release están construidos para el
core de esa release: se graban juntos.
