#!/usr/bin/env python3
"""Genera logo16k.bin (16KB, slot 0-3 pagina 1): pantalla de logo SCREEN 5.

Layout: [magic 'LG'][rutina Z80 @4002][paleta 32B][imagen 256xN, 2px/byte].
El menu la invoca con CALLF 0x8C:4002 tras comprobar el magic con RDSLT.
Uso: python make_logo16k.py <imagen> [color_fondo_hex]
"""
import sys
from PIL import Image

SRC = sys.argv[1] if len(sys.argv) > 1 else 'logo_site.webp'
BG = sys.argv[2] if len(sys.argv) > 2 else 'FFFFFF'
bg = tuple(int(BG[i:i+2], 16) for i in (0, 2, 4))

W, ROM = 256, 16384

# --- rutina Z80 (ensamblada a mano). Se completa LINES/addr tras la imagen ---
def build_code(lines, y0, nbytes):
    pal_addr = 0x4002 + CODE_LEN
    img_addr = pal_addr + 32
    vaddr = y0 * 128
    c = bytearray()
    c += b'\xF3'                                  # di
    c += b'\x3E\x05\xCD\x5F\x00'                  # ld a,5 / call CHGMOD (SCREEN 5)
    c += b'\xF3'                                  # di
    c += b'\xAF\xD3\x99'                          # xor a / out (99),a   (R16=0)
    c += b'\x3E\x90\xD3\x99'                      # ld a,90h / out (99),a
    c += b'\x21' + pal_addr.to_bytes(2,'little')  # ld hl,PAL
    c += b'\x01\x9A\x20'                          # ld bc,209Ah (low 9A, high 20)
    c += b'\xED\xB3'                              # otir (32 bytes de paleta)
    c += b'\xAF\xD3\x99'                          # xor a / out (99),a  (R7 = 0:
    c += b'\x3E\x87\xD3\x99'                      # ld a,87h / out (99),a  borde=fondo)
    c += b'\xAF\xD3\x99'                          # xor a / out (99),a   (R14=0)
    c += b'\x3E\x8E\xD3\x99'                      # ld a,8Eh / out (99),a
    c += bytes([0x3E, vaddr & 0xFF, 0xD3, 0x99])  # ld a,low / out (99),a
    c += bytes([0x3E, ((vaddr >> 8) & 0x3F) | 0x40, 0xD3, 0x99])  # high|40h
    c += b'\x21' + img_addr.to_bytes(2,'little')  # ld hl,IMG
    c += b'\x11' + nbytes.to_bytes(2,'little')    # ld de,NBYTES
    c += b'\x7E\xD3\x98\x23\x1B\x7A\xB3\x20\xF7'  # lp: ld a,(hl)/out(98),a/inc hl/dec de/ld a,d/or e/jr nz,lp
    c += b'\x11\x04\x00'                          # ld de,4  (~2 s de logo)
    c += b'\x01\x00\x00'                          # w1: ld bc,0
    c += b'\x0B\x78\xB1\x20\xFB'                  # w2: dec bc/ld a,b/or c/jr nz,w2
    c += b'\x1B\x7A\xB3\x20\xF6'                  # dec de/ld a,d/or e/jr nz,w1
    c += b'\xC9'                                  # ret
    assert len(c) == CODE_LEN, len(c)
    return c

CODE_LEN = 76

# --- imagen ---
im = Image.open(SRC).convert('RGBA')
flat = Image.new('RGB', im.size, bg)
flat.paste(im, mask=im.split()[3])
# recortar margenes del color de fondo
from PIL import ImageChops
diff = ImageChops.difference(flat, Image.new('RGB', flat.size, bg))
box = diff.getbbox()
flat = flat.crop(box)
# encajar en 256 x lines_max preservando aspecto
lines_max = (ROM - 2 - CODE_LEN - 32) // 128   # bytes libres / 128 por linea
ratio = min(W / flat.width, lines_max / flat.height)
nw, nh = int(flat.width * ratio), int(flat.height * ratio)
flat = flat.resize((nw, nh), Image.LANCZOS)
canvas = Image.new('RGB', (W, nh), bg)
canvas.paste(flat, ((W - nw) // 2, 0))
# cuantizar a 16 colores y ajustar a la paleta MSX 3-3-3
q = canvas.quantize(colors=16, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG)
pal = q.getpalette()[:48]
msxpal = []
for i in range(16):
    r, g, b = pal[i*3:i*3+3]
    msxpal.append((round(r/255*7), round(g/255*7), round(b/255*7)))
# fondo (color del pixel 0,0) debe ser indice 0 (borde usa paleta[0]... R7 lo dejamos)
px = q.load()
bg_idx = px[0, 0]
remap = list(range(16))
remap[0], remap[bg_idx] = remap[bg_idx], remap[0]
inv = [0]*16
for new, old in enumerate(remap): inv[old] = new
msxpal = [msxpal[remap[i]] for i in range(16)]
# bytes de imagen (2 px/byte) ya remapeados
data = bytearray()
for y in range(nh):
    for x in range(0, W, 2):
        a, b2 = inv[px[x, y]], inv[px[x+1, y]]
        data.append((a << 4) | b2)
nbytes = len(data)
y0 = (212 - nh) // 2

rom = bytearray(b'\xFF' * ROM)
rom[0:2] = b'LG'
rom[2:2+CODE_LEN] = build_code(nh, y0, nbytes)
off = 2 + CODE_LEN
for r, g, b2 in msxpal:
    rom[off] = (r << 4) | b2          # byte1 = R..B (formato paleta V9938)
    rom[off+1] = g                    # byte2 = G
    off += 2
rom[off:off+nbytes] = data
open('logo16k.bin', 'wb').write(rom)
# vista previa PNG para revisar la conversion
prev = Image.new('RGB', (W, 212), tuple(c*255//7 for c in msxpal[0]))
shown = Image.new('P', (W, nh)); shown.putpalette(sum([[c[0]*255//7, c[1]*255//7, c[2]*255//7] for c in msxpal], []) + [0]*(768-48))
for y in range(nh):
    for x in range(W): shown.putpixel((x, y), inv[px[x, y]])
prev.paste(shown.convert('RGB'), (0, y0))
prev.resize((512, 424), Image.NEAREST).save('logo16k_preview.png')
print('logo16k.bin: imagen 256x%d, %d bytes, y0=%d, paleta MSX:' % (nh, nbytes, y0))
print(' '.join('%d%d%d' % c for c in msxpal))
