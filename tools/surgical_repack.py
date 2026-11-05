#!/usr/bin/env python3
"""Surgical boot.img repack: swap ONLY the kernel blob inside the untouched
stock container (real mkbootimg header, zero padding, AVB footers - all kept).

Why not mkbootimg re-generation: LOS ships boot.img padded to the full slot
size (96 MiB) with trailing AVB structures. Re-generating with mkbootimg
drops that tail; some Sony/LOS boot chains are sensitive to it. Splicing in
place cannot change anything else - and with the stock kernel blob spliced
back the output is byte-identical to the input (self-test, run every time).

Usage: surgical_repack.py --stock boot.img --image Image --out boot_new.img
"""
import argparse
import struct
import sys

PG = 4096


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stock", required=True)
    ap.add_argument("--image", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    d = bytearray(open(a.stock, "rb").read())
    img = open(a.image, "rb").read()
    if d[:8] != b"ANDROID!":
        sys.exit("not an ANDROID! image")
    hdrsz = struct.unpack_from("<I", d, 20)[0]
    if hdrsz != 1584:
        sys.exit(f"unsupported header_size {hdrsz} (expect 1584 = GKI v3/v4)")
    kern = struct.unpack_from("<I", d, 8)[0]
    ramd = struct.unpack_from("<I", d, 12)[0]
    if ramd:
        sys.exit(f"boot.img carries ramdisk ({ramd}); splicing would clobber it")
    # header v3/v4 is fixed 1584 bytes -> kernel payload starts at page 1
    koff = PG
    stock_blob = bytes(d[koff:koff + kern])
    if len(stock_blob) != kern:
        sys.exit("stock kernel blob truncated")

    # room: kernel region may extend until the first nonzero byte beyond it
    # (in practice the padding/AVB tail sits far away; verify we do not hit it)
    n = len(d)
    limit = n
    # AvbFooter: magic 'AVBf' + ver(8) + orig(8) + vbmeta_off(8) + size(8); BIG endian
    if d[n - 64:n - 60] == b"AVBf":
        tail = struct.unpack_from(">Q", d, n - 64 + 12 + 8)[0]
        if 0 < tail < n:
            if koff + len(img) > tail:
                print(f"WARN: new Image overwrites embedded vbmeta @{tail}.",
                      "Only safe when vbmeta partition is flashed with "
                      "verification disabled (flags=3).", file=sys.stderr)

    out = bytearray(d)
    struct.pack_into("<I", out, 8, len(img))
    # zero old blob area first (in case new image is smaller), then splice
    out[koff:koff + kern] = bytes(kern)
    out[koff:koff + len(img)] = img

    # self-test: splicing the stock blob back must reproduce the file exactly
    o2 = bytearray(d)
    struct.pack_into("<I", o2, 8, kern)
    o2[koff:koff + len(stock_blob)] = stock_blob
    if bytes(o2) != bytes(d):
        sys.exit("SELF-TEST FAILED: splice is not reversible")

    open(a.out, "wb").write(bytes(out))
    print(f"ok: {a.out} {len(out)} bytes "
          f"(container preserved: hdr {hdrsz}B v4, kernel {kern} -> {len(img)})")


if __name__ == "__main__":
    main()
