#!/usr/bin/env python3
"""
mkstream - convierte una imagen .cvt (CVT1, de tsx2rom --tape) al formato de
STREAM CVS1 que consume cas_stream.v (descriptores INLINE, orden secuencial),
y genera los ficheros de la simulacion:

  stream.hex    bytes del stream, uno por linea (para $readmemh del TB)
  expected.hex  bytes de payload en orden (lo que el decodificador KCS debe
                recuperar), uno por linea
  (imprime nblk / bytes de payload / bytes de stream para el TB)

CVT1: [0..3]"CVT1" [4..5]nblk(LE) [6..6+4n) descriptores {len(2LE),pilot,pad}
      luego payloads concatenados.
CVS1: "CVS1" + nblk(LE) + por bloque: {len(2LE),pilot,pad} + payload.
"""
import sys, os

def main():
    if len(sys.argv) != 3:
        print("uso: mkstream.py entrada.cvt dir_salida")
        return 1
    src, outdir = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    assert data[0:4] == b"CVT1", "no es un CVT1"
    nblk = data[4] | (data[5] << 8)
    descs = []
    off = 6
    for _ in range(nblk):
        ln = data[off] | (data[off + 1] << 8)
        descs.append((ln, data[off + 2], data[off + 3]))
        off += 4
    stream = bytearray(b"CVS1")
    stream += bytes([nblk & 0xFF, nblk >> 8])
    payload_all = bytearray()
    for (ln, pilot, pad) in descs:
        stream += bytes([ln & 0xFF, ln >> 8, pilot, pad])
        stream += data[off:off + ln]
        payload_all += data[off:off + ln]
        off += ln
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "stream.hex"), "w") as f:
        f.write("\n".join(f"{b:02x}" for b in stream) + "\n")
    with open(os.path.join(outdir, "expected.hex"), "w") as f:
        f.write("\n".join(f"{b:02x}" for b in payload_all) + "\n")
    print(f"nblk={nblk} payload={len(payload_all)} stream={len(stream)}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
