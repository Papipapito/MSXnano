"""Prueba definitiva FAT32: ejecuta los BYTES REALES ensamblados de las rutinas
del menu (clus2lba/fatnext/w_is_eoc) en un mini-interprete Z80, sirviendo
sectores desde una imagen FAT32 sintetica, y compara con la verdad."""
import struct, re, sys, os

SEC = 512
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', '..', 'fpga', 'src', 'msxnano_menu', 'out')


def mk32(spc=64, nfats=2, rsvd=32, fatsecs=2048, part_lba=1000000):
    fat = [0] * (fatsecs * 128)
    fat[0] = 0x0FFFFFF8; fat[1] = 0x0FFFFFFF; fat[2] = 0x0FFFFFFF
    chain = [5, 6, 200, 70000, 70001, 65535, 65536, 99999]
    for i, c in enumerate(chain):
        fat[c] = chain[i + 1] if i + 1 < len(chain) else 0x0FFFFFF8
    data_start = rsvd + nfats * fatsecs
    sectors = {}
    fb = b''.join(struct.pack('<I', v) for v in fat)
    for f in range(nfats):
        base = part_lba + rsvd + f * fatsecs
        for s in range(fatsecs):
            sectors[base + s] = fb[s * SEC:(s + 1) * SEC]
    for i, c in enumerate(chain):
        base = part_lba + data_start + (c - 2) * spc
        for s in range(spc):
            sectors[base + s] = bytes([(i * 37 + s + j) % 256 for j in range(SEC)])
    return sectors, part_lba, rsvd, nfats, fatsecs, data_start, chain, spc


sectors, part, rsvd, nfats, fatsecs, data_start, chain, spc = mk32()

code = open(os.path.join(OUT, 'menu_main.z80'), 'rb').read()
mem = bytearray(65536)
mem[0x8000:0x8000 + len(code)] = code

sym_txt = open(os.path.join(OUT, 'menu_main.sym')).read()


def sym(name):
    m = re.search(r'([0-9A-F]{4})h ' + name + r'\b', sym_txt)
    return int(m.group(1), 16)


SD_LBA = sym('SD_LBA'); SD_STATUS = sym('SD_STATUS'); SD_BUF = sym('SD_BUF')
FS32 = sym('FS32'); SPC_SHIFT = sym('SPC_SHIFT'); W_TMP = sym('W_TMP')
FAT_LBA = sym('FAT_LBA'); DATA_LBA = sym('DATA_LBA'); SECPC = sym('SEC_PER_CLUS')
SECLEFT = sym('sec_left')
A_CLUS2LBA = sym('clus2lba'); A_FATNEXT = sym('fatnext')
A_EOC = sym('w_is_eoc'); A_SDREAD = sym('sd_read_sector')


class Z80:
    def __init__(s, m):
        s.m = m; s.a = s.b = s.c = s.d = s.e = s.h = s.l = 0
        s.f = 0; s.sp = 0xF000; s.pc = 0; s.ix = 0

    def ghl(s): return (s.h << 8) | s.l
    def shl(s, v): s.h = (v >> 8) & 0xFF; s.l = v & 0xFF
    def gde(s): return (s.d << 8) | s.e
    def sde(s, v): s.d = (v >> 8) & 0xFF; s.e = v & 0xFF
    def gbc(s): return (s.b << 8) | s.c
    def sbc_(s, v): s.b = (v >> 8) & 0xFF; s.c = v & 0xFF
    def cy(s): return s.f & 1
    def setc(s, c): s.f = (s.f & ~1) | (1 if c else 0)
    def setz(s, z): s.f = (s.f & ~0x40) | (0x40 if z else 0)
    def push(s, v):
        s.sp = (s.sp - 2) & 0xFFFF
        s.m[s.sp] = v & 0xFF; s.m[s.sp + 1] = (v >> 8) & 0xFF
    def pop(s):
        v = s.m[s.sp] | (s.m[s.sp + 1] << 8)
        s.sp = (s.sp + 2) & 0xFFFF
        return v
    def fetch(s):
        b = s.m[s.pc]; s.pc = (s.pc + 1) & 0xFFFF
        return b
    def f16(s):
        lo = s.fetch(); hi = s.fetch()
        return lo | (hi << 8)
    def rel(s, o): return (s.pc + (o - 256 if o > 127 else o)) & 0xFFFF

    def step(s):
        op = s.fetch()
        if op == 0xDD:
            o2 = s.fetch()
            if o2 == 0x21: s.ix = s.f16()
            elif o2 == 0xE5: s.push(s.ix)
            elif o2 == 0xE1: s.ix = s.pop()
            elif o2 == 0x19:
                r = s.ix + s.gde(); s.setc(r > 0xFFFF); s.ix = r & 0xFFFF
            elif o2 == 0x7E:
                d = s.fetch(); s.a = s.m[(s.ix + (d - 256 if d > 127 else d)) & 0xFFFF]
            elif o2 == 0x77:
                d = s.fetch(); s.m[(s.ix + (d - 256 if d > 127 else d)) & 0xFFFF] = s.a
            elif o2 == 0xBE:
                d = s.fetch(); v = s.m[(s.ix + (d - 256 if d > 127 else d)) & 0xFFFF]
                r = s.a - v; s.setc(r < 0); s.setz((r & 0xFF) == 0)
            elif o2 in (0x46, 0x4E, 0x56, 0x5E, 0x66, 0x6E):
                d = s.fetch(); v = s.m[(s.ix + (d - 256 if d > 127 else d)) & 0xFFFF]
                setattr(s, {0x46: 'b', 0x4E: 'c', 0x56: 'd', 0x5E: 'e', 0x66: 'h', 0x6E: 'l'}[o2], v)
            else:
                raise Exception('DD %02X @%04X' % (o2, s.pc - 2))
            return
        if op == 0xED:
            o2 = s.fetch()
            if o2 == 0xB0:
                while True:
                    s.m[s.gde()] = s.m[s.ghl()]
                    s.shl(s.ghl() + 1); s.sde(s.gde() + 1)
                    s.sbc_((s.gbc() - 1) & 0xFFFF)
                    if s.gbc() == 0:
                        break
            elif o2 == 0x6A:
                r = s.ghl() * 2 + s.cy(); s.setc(r > 0xFFFF); s.shl(r & 0xFFFF)
            elif o2 == 0x5A:
                r = s.ghl() + s.gde() + s.cy(); s.setc(r > 0xFFFF); s.shl(r & 0xFFFF)
            elif o2 == 0x52:
                r = s.ghl() - s.gde() - s.cy(); s.setc(r < 0); s.shl(r & 0xFFFF); s.setz((r & 0xFFFF) == 0)
            elif o2 == 0x5B:
                ad = s.f16(); s.sde(s.m[ad] | (s.m[ad + 1] << 8))
            elif o2 == 0x4B:
                ad = s.f16(); s.sbc_(s.m[ad] | (s.m[ad + 1] << 8))
            elif o2 == 0x53:
                ad = s.f16(); s.m[ad] = s.e; s.m[ad + 1] = s.d
            else:
                raise Exception('ED %02X @%04X' % (o2, s.pc - 2))
            return
        if op == 0x3A: s.a = s.m[s.f16()]
        elif op == 0x32: s.m[s.f16()] = s.a
        elif op == 0x2A:
            ad = s.f16(); s.shl(s.m[ad] | (s.m[ad + 1] << 8))
        elif op == 0x22:
            ad = s.f16(); s.m[ad] = s.l; s.m[ad + 1] = s.h
        elif op == 0x01: s.sbc_(s.f16())
        elif op == 0x11: s.sde(s.f16())
        elif op == 0x21: s.shl(s.f16())
        elif op == 0x3E: s.a = s.fetch()
        elif op == 0x06: s.b = s.fetch()
        elif op == 0x0E: s.c = s.fetch()
        elif op == 0x16: s.d = s.fetch()
        elif op == 0x1E: s.e = s.fetch()
        elif op == 0x26: s.h = s.fetch()
        elif op == 0x2E: s.l = s.fetch()
        elif op == 0x7E: s.a = s.m[s.ghl()]
        elif op == 0x77: s.m[s.ghl()] = s.a
        elif op == 0x5E: s.e = s.m[s.ghl()]
        elif op == 0x56: s.d = s.m[s.ghl()]
        elif op == 0x36: s.m[s.ghl()] = s.fetch()
        elif op == 0x23: s.shl(s.ghl() + 1)
        elif op == 0x13: s.sde(s.gde() + 1)
        elif op == 0x2B: s.shl((s.ghl() - 1) & 0xFFFF)
        elif op == 0x29:
            r = s.ghl() * 2; s.setc(r > 0xFFFF); s.shl(r & 0xFFFF)
        elif op == 0x19:
            r = s.ghl() + s.gde(); s.setc(r > 0xFFFF); s.shl(r & 0xFFFF)
        elif op == 0x17:
            c = (s.a >> 7) & 1; s.a = ((s.a << 1) | s.cy()) & 0xFF; s.setc(c)
        elif op == 0x0F:
            c = s.a & 1; s.a = ((s.a >> 1) | (c << 7)) & 0xFF; s.setc(c)
        elif op == 0xE6:
            s.a &= s.fetch(); s.setc(0); s.setz(s.a == 0)
        elif op == 0xB7: s.setc(0); s.setz(s.a == 0)
        elif op == 0xB6:
            s.a |= s.m[s.ghl()]; s.setc(0); s.setz(s.a == 0)
        elif op == 0xB4: s.a |= s.h; s.setc(0); s.setz(s.a == 0)
        elif op == 0xB5: s.a |= s.l; s.setc(0); s.setz(s.a == 0)
        elif op == 0xB3: s.a |= s.e; s.setc(0); s.setz(s.a == 0)
        elif op == 0xFE:
            n = s.fetch(); r = s.a - n; s.setc(r < 0); s.setz((r & 0xFF) == 0)
        elif op == 0x3D: s.a = (s.a - 1) & 0xFF; s.setz(s.a == 0)
        elif op == 0x05: s.b = (s.b - 1) & 0xFF; s.setz(s.b == 0)
        elif op == 0x18: s.pc = s.rel(s.fetch())
        elif op == 0x20:
            o = s.fetch()
            if not (s.f & 0x40): s.pc = s.rel(o)
        elif op == 0x28:
            o = s.fetch()
            if s.f & 0x40: s.pc = s.rel(o)
        elif op == 0x30:
            o = s.fetch()
            if not s.cy(): s.pc = s.rel(o)
        elif op == 0x38:
            o = s.fetch()
            if s.cy(): s.pc = s.rel(o)
        elif op == 0xC3: s.pc = s.f16()
        elif op == 0xC2:
            ad = s.f16()
            if not (s.f & 0x40): s.pc = ad
        elif op == 0xCA:
            ad = s.f16()
            if s.f & 0x40: s.pc = ad
        elif op == 0xD2:
            ad = s.f16()
            if not s.cy(): s.pc = ad
        elif op == 0xDA:
            ad = s.f16()
            if s.cy(): s.pc = ad
        elif op == 0xCD:
            ad = s.f16(); s.push(s.pc); s.pc = ad
        elif op == 0xC9: s.pc = s.pop()
        elif op == 0xC8:
            if s.f & 0x40: s.pc = s.pop()
        elif op == 0xC0:
            if not (s.f & 0x40): s.pc = s.pop()
        elif op == 0xD8:
            if s.cy(): s.pc = s.pop()
        elif op == 0xD0:
            if not s.cy(): s.pc = s.pop()
        elif op == 0x37: s.setc(1)
        elif op == 0xD3: s.fetch()  # out (n),a -> no-op
        elif op == 0x34:
            v = (s.m[s.ghl()] + 1) & 0xFF; s.m[s.ghl()] = v; s.setz(v == 0)
        elif op == 0x35:
            v = (s.m[s.ghl()] - 1) & 0xFF; s.m[s.ghl()] = v; s.setz(v == 0)
        elif op == 0xDB: s.fetch(); s.a = 0xFF  # in a,(n)
        elif op == 0xEB:
            t = s.ghl(); s.shl(s.gde()); s.sde(t)
        elif op == 0xE5: s.push(s.ghl())
        elif op == 0xD5: s.push(s.gde())
        elif op == 0xC5: s.push(s.gbc())
        elif op == 0xE1: s.shl(s.pop())
        elif op == 0xD1: s.sde(s.pop())
        elif op == 0xC1: s.sbc_(s.pop())
        elif op == 0x6F: s.l = s.a
        elif op == 0x67: s.h = s.a
        elif op == 0x7C: s.a = s.h
        elif op == 0x7D: s.a = s.l
        elif op == 0x7A: s.a = s.d
        elif op == 0x7B: s.a = s.e
        elif op == 0x57: s.d = s.a
        elif op == 0x5F: s.e = s.a
        elif op == 0x47: s.b = s.a
        elif op == 0x78: s.a = s.b
        elif op == 0x4F: s.c = s.a
        elif op == 0x79: s.a = s.c
        elif op == 0x48: s.c = s.b
        elif op == 0x41: s.b = s.c
        elif op == 0x10:
            o = s.fetch(); s.b = (s.b - 1) & 0xFF
            if s.b: s.pc = s.rel(o)
        elif op == 0x12: s.m[s.gde()] = s.a
        elif op == 0x1A: s.a = s.m[s.gde()]
        elif op == 0xB8:
            r = s.a - s.b; s.setc(r < 0); s.setz((r & 0xFF) == 0)
        elif op == 0xB9:
            r = s.a - s.c; s.setc(r < 0); s.setz((r & 0xFF) == 0)
        elif op == 0xBA:
            r = s.a - s.d; s.setc(r < 0); s.setz((r & 0xFF) == 0)
        elif op == 0xBB:
            r = s.a - s.e; s.setc(r < 0); s.setz((r & 0xFF) == 0)
        elif op == 0xBE:
            v = s.m[s.ghl()]; r = s.a - v; s.setc(r < 0); s.setz((r & 0xFF) == 0)
        elif op == 0xC6:
            r = s.a + s.fetch(); s.setc(r > 0xFF); s.a = r & 0xFF; s.setz(s.a == 0)
        elif op == 0xD6:
            r = s.a - s.fetch(); s.setc(r < 0); s.a = r & 0xFF; s.setz(s.a == 0)
        elif op == 0x87:
            r = s.a * 2; s.setc(r > 0xFF); s.a = r & 0xFF; s.setz(s.a == 0)
        elif op == 0x3C: s.a = (s.a + 1) & 0xFF; s.setz(s.a == 0)
        elif op == 0x04: s.b = (s.b + 1) & 0xFF; s.setz(s.b == 0)
        elif op == 0x0C: s.c = (s.c + 1) & 0xFF; s.setz(s.c == 0)
        elif op == 0x0D: s.c = (s.c - 1) & 0xFF; s.setz(s.c == 0)
        elif op == 0x15: s.d = (s.d - 1) & 0xFF; s.setz(s.d == 0)
        elif op == 0x1D: s.e = (s.e - 1) & 0xFF; s.setz(s.e == 0)
        elif op == 0x25: s.h = (s.h - 1) & 0xFF; s.setz(s.h == 0)
        elif op == 0x2D: s.l = (s.l - 1) & 0xFF; s.setz(s.l == 0)
        elif op == 0x24: s.h = (s.h + 1) & 0xFF; s.setz(s.h == 0)
        elif op == 0x2C: s.l = (s.l + 1) & 0xFF; s.setz(s.l == 0)
        elif op == 0x70: s.m[s.ghl()] = s.b
        elif op == 0x71: s.m[s.ghl()] = s.c
        elif op == 0x72: s.m[s.ghl()] = s.d
        elif op == 0x73: s.m[s.ghl()] = s.e
        elif op == 0x74: s.m[s.ghl()] = s.h
        elif op == 0x75: s.m[s.ghl()] = s.l
        elif op == 0x46: s.b = s.m[s.ghl()]
        elif op == 0x4E: s.c = s.m[s.ghl()]
        elif op == 0x66: s.h = s.m[s.ghl()]
        elif op == 0x6E: s.l = s.m[s.ghl()]
        elif op == 0x60: s.h = s.b
        elif op == 0x69: s.l = s.c
        elif op == 0x68: s.l = s.b
        elif op == 0x61: s.h = s.c
        elif op == 0x62: s.h = s.d
        elif op == 0x63: s.h = s.e
        elif op == 0x6A: s.l = s.d
        elif op == 0x6B: s.l = s.e
        elif op == 0x44: s.b = s.h
        elif op == 0x45: s.b = s.l
        elif op == 0x4C: s.c = s.h
        elif op == 0x4D: s.c = s.l
        elif op == 0x50: s.d = s.b
        elif op == 0x51: s.d = s.c
        elif op == 0x54: s.d = s.h
        elif op == 0x55: s.d = s.l
        elif op == 0x58: s.e = s.b
        elif op == 0x59: s.e = s.c
        elif op == 0x5D: s.e = s.l
        elif op == 0x65: s.h = s.l
        elif op == 0x6C: s.l = s.h
        elif op == 0xA7: s.setc(0); s.setz(s.a == 0)
        elif op == 0xA0: s.a &= s.b; s.setc(0); s.setz(s.a == 0)
        elif op == 0xA1: s.a &= s.c; s.setc(0); s.setz(s.a == 0)
        elif op == 0xB0: s.a |= s.b; s.setc(0); s.setz(s.a == 0)
        elif op == 0xB1: s.a |= s.c; s.setc(0); s.setz(s.a == 0)
        elif op == 0xB2: s.a |= s.d; s.setc(0); s.setz(s.a == 0)
        elif op == 0xA8: s.a ^= s.b; s.setc(0); s.setz(s.a == 0)
        elif op == 0x07:
            c = (s.a >> 7) & 1; s.a = ((s.a << 1) | c) & 0xFF; s.setc(c)
        elif op == 0x1F:
            c = s.a & 1; s.a = ((s.a >> 1) | (s.cy() << 7)) & 0xFF; s.setc(c)
        elif op == 0xCB:
            o2 = s.fetch()
            if o2 == 0x3C:  # srl h
                c = s.h & 1; s.h >>= 1; s.setc(c)
            elif o2 == 0x3D:  # srl l
                c = s.l & 1; s.l >>= 1; s.setc(c)
            elif o2 == 0x1C:  # rr h
                c = s.h & 1; s.h = (s.h >> 1) | (s.cy() << 7); s.setc(c)
            elif o2 == 0x1D:  # rr l
                c = s.l & 1; s.l = (s.l >> 1) | (s.cy() << 7); s.setc(c)
            elif o2 == 0x3F:  # srl a
                c = s.a & 1; s.a >>= 1; s.setc(c)
            else:
                raise Exception('CB %02X @%04X' % (o2, s.pc - 2))
        elif op == 0x5C: s.e = s.h
        elif op == 0xAF: s.a = 0; s.setz(1); s.setc(0)
        else:
            raise Exception('op %02X @%04X' % (op, s.pc - 1))


z = Z80(mem)


def call(addr):
    z.push(0xFFFF)
    z.pc = addr
    n = 0
    while z.pc != 0xFFFF:
        if z.pc == A_SDREAD:
            lba = struct.unpack('<I', bytes(mem[SD_LBA:SD_LBA + 4]))[0]
            mem[SD_BUF:SD_BUF + SEC] = sectors.get(lba, bytes(SEC))
            mem[SD_STATUS] = 0
            z.pc = z.pop()
            continue
        z.step(); n += 1
        if n > 500000:
            raise Exception('bucle infinito')


def w32(addr, v):
    mem[addr:addr + 4] = struct.pack('<I', v)


mem[FS32] = 1; mem[SPC_SHIFT] = 6; mem[SECPC] = spc
w32(FAT_LBA, part + rsvd)
w32(DATA_LBA, part + rsvd + nfats * fatsecs)

ok = True
# clus2lba para cada cluster de la cadena
for c in chain:
    w32(W_TMP, c)
    call(A_CLUS2LBA)
    lba = struct.unpack('<I', bytes(mem[SD_LBA:SD_LBA + 4]))[0]
    exp = part + data_start + (c - 2) * spc
    if lba != exp:
        print('clus2lba(%d): %d != %d  *** MAL ***' % (c, lba, exp)); ok = False
print('clus2lba: todos %s (sec_left=%d, esperado %d)' % ('OK' if ok else 'MAL', mem[SECLEFT], spc))

# cadena con fatnext + w_is_eoc (bytes reales)
got = [chain[0]]
w32(W_TMP, chain[0])
while True:
    call(A_FATNEXT)
    v = struct.unpack('<I', bytes(mem[W_TMP:W_TMP + 4]))[0]
    call(A_EOC)
    if z.cy():
        break
    got.append(v)
    if len(got) > 20:
        break
print('cadena Z80 real :', got)
print('cadena esperada :', chain)
print('CADENA:', 'OK' if got == chain else '*** MAL ***')


# ================= TEST 2: scan_current con directorio sintetico =================
SCAN_CURRENT = sym('scan_current')
ENT_ARRAY = sym('ENT_ARRAY'); ENT_COUNT = sym('ENT_COUNT')
FILTER = sym('FILTER'); CUR_CLUS = sym('CUR_CLUS'); FILE_CLUS = sym('FILE_CLUS')

def dirent(name83, attr, clus, size):
    e = bytearray(32)
    e[0:11] = name83; e[11] = attr
    e[20:22] = struct.pack('<H', (clus >> 16) & 0xFFFF)
    e[26:28] = struct.pack('<H', clus & 0xFFFF)
    e[28:32] = struct.pack('<I', size)
    return bytes(e)

root = bytearray(SEC)
root[0:32]  = dirent(b'GAME    ROM', 0x00, 70000, 0x20000)
root[32:64] = dirent(b'CARPETA    ', 0x10, 131,   0)
root_lba = part + data_start + (2 - 2) * spc
sectors[root_lba] = bytes(root)
for s2 in range(1, spc):
    sectors[root_lba + s2] = bytes(SEC)

w32(CUR_CLUS, 2)
mem[FILTER] = 2
call(SCAN_CURRENT)

n = mem[ENT_COUNT]
print()
print('scan_current: entradas =', n)
for i in range(n):
    r = ENT_ARRAY + i * 80
    typ = mem[r]
    clus = struct.unpack('<I', bytes(mem[r+1:r+5]))[0]
    size = struct.unpack('<I', bytes(mem[r+5:r+9]))[0]
    name = bytes(mem[r+9:r+9+12]).split(b'\x00')[0].decode('ascii', 'replace')
    print('  [%d] type=%d clus=%d size=%d name=%r' % (i, typ, clus, size, name))

ok2 = (n == 2
       and mem[ENT_ARRAY] == 1
       and struct.unpack('<I', bytes(mem[ENT_ARRAY+1:ENT_ARRAY+5]))[0] == 70000
       and struct.unpack('<I', bytes(mem[ENT_ARRAY+5:ENT_ARRAY+9]))[0] == 0x20000
       and mem[ENT_ARRAY+80] == 0
       and struct.unpack('<I', bytes(mem[ENT_ARRAY+81:ENT_ARRAY+85]))[0] == 131)
print('REGISTROS:', 'OK' if ok2 else '*** MAL ***')

# ============== TEST 3: fat_compute_root (montaje BPB) con bytes reales ==============
FCR = sym('fat_compute_root'); PART_LBA_V = sym('PART_LBA')
ROOT_CLUS_V = sym('ROOT_CLUS'); ROOT_LBA_V = sym('ROOT_LBA'); ROOT_SECS_V = sym('ROOT_SECS')

def r32(a): return struct.unpack('<I', bytes(mem[a:a+4]))[0]

print()
# --- BPB FAT32 realista (32GB: SPC=64, rsvd=32, FATSz32=16384, 2 FATs, root=2) ---
bpb = bytearray(SEC)
bpb[13] = 64
bpb[14:16] = struct.pack('<H', 32)
bpb[16] = 2
bpb[17:19] = b'\x00\x00'
bpb[22:24] = b'\x00\x00'
bpb[36:40] = struct.pack('<I', 16384)
bpb[44:48] = struct.pack('<I', 2)
mem[SD_BUF:SD_BUF+SEC] = bpb
PSTART = 4194304            # particion 2 en 2GB
w32(PART_LBA_V, PSTART)
call(FCR)
fl = r32(FAT_LBA); dl = r32(DATA_LBA)
exp_fl = PSTART + 32; exp_dl = PSTART + 32 + 2*16384
print('FAT32 mount: FS32=%d SPC_SHIFT=%d' % (mem[FS32], mem[SPC_SHIFT]))
print('  FAT_LBA  = %d (esperado %d) %s' % (fl, exp_fl, 'OK' if fl == exp_fl else '*** MAL ***'))
print('  DATA_LBA = %d (esperado %d) %s' % (dl, exp_dl, 'OK' if dl == exp_dl else '*** MAL ***'))
print('  ROOT_CLUS= %d (esperado 2) %s' % (r32(ROOT_CLUS_V), 'OK' if r32(ROOT_CLUS_V) == 2 else '*** MAL ***'))

# --- BPB FAT16 (regresion: 2GB, SPC=64, rsvd=1, FATSz16=256, root 512 ents) ---
bpb = bytearray(SEC)
bpb[13] = 64
bpb[14:16] = struct.pack('<H', 1)
bpb[16] = 2
bpb[17:19] = struct.pack('<H', 512)
bpb[22:24] = struct.pack('<H', 256)
mem[SD_BUF:SD_BUF+SEC] = bpb
w32(PART_LBA_V, 63)
call(FCR)
fl = r32(FAT_LBA); rl = r32(ROOT_LBA_V); dl = r32(DATA_LBA)
exp_fl = 63 + 1; exp_rl = 64 + 2*256; exp_dl = exp_rl + 32
print('FAT16 mount: FS32=%d SPC_SHIFT=%d ROOT_SECS=%d' % (mem[FS32], mem[SPC_SHIFT], mem[ROOT_SECS_V]))
print('  FAT_LBA  = %d (esperado %d) %s' % (fl, exp_fl, 'OK' if fl == exp_fl else '*** MAL ***'))
print('  ROOT_LBA = %d (esperado %d) %s' % (rl, exp_rl, 'OK' if rl == exp_rl else '*** MAL ***'))
print('  DATA_LBA = %d (esperado %d) %s' % (dl, exp_dl, 'OK' if dl == exp_dl else '*** MAL ***'))

# ============== TEST 4: load_rom end-to-end (megaram reconstruida) ==============
LOAD_ROM = sym('load_rom'); WSM = sym('write_sector_to_megaram')
LOAD_SEG = sym('LOAD_SEG'); LOAD_OFF = sym('LOAD_OFF')

# BIOS stubs: ENASLT(#0024), CHPUT(#00A2), POSIT? (usa CHPUT/calls BIOS)
for stub in (0x0024, 0x00A2, 0x00C6):
    mem[stub] = 0xC9
# POSIT es #00C6? en este menu POSIT = ? — stub generico: cualquier call < 0x4000 -> RET
# (el interprete ya ejecuta C9 alli; rellenar page0 entera de RET por seguridad)
for a2 in range(0x0000, 0x4000):
    mem[a2] = 0xC9

# restaurar mount FAT32 del test 1
mem[FS32] = 1; mem[SPC_SHIFT] = 6; mem[SECPC] = spc
w32(FAT_LBA, part + rsvd)
w32(DATA_LBA, part + rsvd + nfats * fatsecs)

# FILE_CLUS = primer cluster de la cadena sintetica (70000 NO esta en la cadena de
# datos del test 1 — usar chain[0]=5 cuya cadena completa esta poblada)
w32(sym('FILE_CLUS'), chain[0])

megaram = {}
pend = {}

def call_load(addr):
    z.push(0xFFFF); z.pc = addr; n = 0
    while z.pc != 0xFFFF:
        if z.pc == A_SDREAD:
            lba = struct.unpack('<I', bytes(mem[SD_LBA:SD_LBA + 4]))[0]
            mem[SD_BUF:SD_BUF + SEC] = sectors.get(lba, bytes(SEC))
            mem[SD_STATUS] = 0
            z.pc = z.pop()
            continue
        if z.pc == WSM:
            seg = mem[LOAD_SEG]
            off = mem[LOAD_OFF] | (mem[LOAD_OFF + 1] << 8)
            pend['dst'] = seg * 8192 + off
        if z.pc == WSM + 999999:
            pass
        z.step(); n += 1
        if 'dst' in pend and z.pc == 0x8000 + 0:
            pass
        if n > 5000000:
            raise Exception('bucle')

# capturar el contenido: en vez de interceptar el retorno, dejamos que la rutina
# REAL escriba en mem[0x4000:0x6000] y tras CADA paso si acaba de ejecutar el LDIR
# es complejo; mas simple: envolver WSM: al entrar, anotar destino; la rutina real
# copia SD_BUF a mem[0x4000+off]; tras su RET (volver a load_rom), volcamos.
# Implementacion: hook en call(): si PC==WSM, ejecutar la rutina en una sub-llamada
# controlada y luego volcar mem[0x4000+off : +512].

def run_until_ret(entry_sp):
    while z.sp != entry_sp:
        if z.pc == A_SDREAD:
            lba = struct.unpack('<I', bytes(mem[SD_LBA:SD_LBA + 4]))[0]
            mem[SD_BUF:SD_BUF + SEC] = sectors.get(lba, bytes(SEC))
            mem[SD_STATUS] = 0
            z.pc = z.pop()
            continue
        z.step()

z.push(0xFFFF); z.pc = LOAD_ROM
steps = 0
while z.pc != 0xFFFF:
    if z.pc == A_SDREAD:
        lba = struct.unpack('<I', bytes(mem[SD_LBA:SD_LBA + 4]))[0]
        mem[SD_BUF:SD_BUF + SEC] = sectors.get(lba, bytes(SEC))
        mem[SD_STATUS] = 0
        z.pc = z.pop()
        continue
    if z.pc == WSM:
        seg = mem[LOAD_SEG]
        off = mem[LOAD_OFF] | (mem[LOAD_OFF + 1] << 8)
        sp_entry = z.sp            # tras el CALL ya esta el retorno en pila
        z.step()                   # primera instr de wsm
        run_until_ret(sp_entry + 2)
        megaram[seg * 8192 + off] = bytes(mem[0x4000 + off:0x4000 + off + 512])
        steps += 1
        continue
    z.step(); steps += 1
    if steps > 5000000:
        raise Exception('bucle')

# comparar con lo esperado (cadena de clusters del fichero sintetico)
expected = b''
for i, c in enumerate(chain):
    base = part + data_start + (c - 2) * spc
    for s3 in range(spc):
        expected += sectors[base + s3]

got = b''.join(megaram[k] for k in sorted(megaram))
print()
print('load_rom: %d sectores escritos, %d bytes (esperados %d)' % (len(megaram), len(got), len(expected)))
print('CONTENIDO MEGARAM:', 'OK' if got == expected else '*** MAL ***')
if got != expected and len(got) == len(expected):
    for i in range(len(got)):
        if got[i] != expected[i]:
            print('primer byte distinto en offset %d (seg %d)' % (i, i // 8192))
            break
