#!/usr/bin/env python3
"""AVB-aware surgical repack for Xperia 1 VI (pdx245) LOS boot.img.

Splices a new kernel Image into the UNTOUCHED stock boot.img container.
If the new Image is larger than the stock one it would overwrite the
partition's embedded AVB structures (vbmeta struct + AVBf footer at the
end of the payload).  A corrupted/absent vbmeta struct makes libavb bail
out with AVB_SLOT_VERIFY_RESULT_ERROR_INVALID_METADATA, which the boot
loader treats as FATAL even when verification is disabled -> bootloop.

When that happens the embedded vbmeta struct is RELOCATED, byte-for-byte,
to the next page-aligned offset after the new kernel (its signature is
untouched, so the hash in the top-level vbmeta chain descriptor still
verifies) and the AVBf footer's vbmeta_offset/orig_image_size are updated.

Self-test: transform(stock_container, stock_kernel_blob) must return the
stock container byte-for-byte.

Usage: avb_reloc_repack.py --stock boot.img --image Image --out boot_new.img
"""
import argparse
import struct
import sys

PG = 4096


def transform(d, img):
    """Return a new container (bytearray) carrying kernel blob `img`."""
    n = len(d)
    if d[:8] != b"ANDROID!":
        sys.exit("not an ANDROID! image")
    hdrsz = struct.unpack_from("<I", d, 20)[0]
    if hdrsz != 1584:
        sys.exit(f"unsupported header_size {hdrsz} (expect 1584 = GKI v4)")
    if struct.unpack_from("<I", d, 40)[0] != 4:
        sys.exit("header_version != 4")
    kern = struct.unpack_from("<I", d, 8)[0]
    if struct.unpack_from("<I", d, 12)[0]:
        sys.exit("boot.img carries a boot ramdisk; splicing would clobber it")

    if n < 64 or d[n - 64:n - 60] != b"AVBf":
        sys.exit("no AVBf footer at EOF - unsupported container")
    orig, vb_off, vb_size = struct.unpack_from(">3Q", d, n - 64 + 12)
    if vb_off < PG + kern:
        sys.exit(f"footer vbmeta offset {vb_off} inside kernel region")
    vbmeta = bytes(d[vb_off:vb_off + vb_size])
    if vbmeta[:4] != b"AVB0":
        sys.exit(f"embedded vbmeta not AVB0 at {vb_off}")

    koff = PG
    out = bytearray(d)

    if len(img) <= vb_off - koff:
        new_vb_off = vb_off
        out[koff:koff + kern] = bytes(kern)      # wipe old blob area
        out[koff:koff + len(img)] = img
    else:
        new_vb_off = (koff + len(img) + PG - 1) & ~(PG - 1)
        if new_vb_off + vb_size > n:
            sys.exit("relocated vbmeta exceeds partition - kernel far too big")
        # zero from kernel start through old vbmeta end, then rebuild
        out[koff:vb_off + vb_size] = bytes(vb_off + vb_size - koff)
        out[koff:koff + len(img)] = img
        out[new_vb_off:new_vb_off + vb_size] = vbmeta
        struct.pack_into(">2Q", out, n - 64 + 12, new_vb_off, new_vb_off)

    struct.pack_into("<I", out, 8, len(img))
    return out, new_vb_off, vb_off


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stock", required=True)
    ap.add_argument("--image", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    d = open(a.stock, "rb").read()
    img = open(a.image, "rb").read()

    # self-test first: stock blob must round-trip to the stock file
    stock_blob = d[PG:PG + struct.unpack_from("<I", d, 8)[0]]
    t, tnew, torig = transform(d, stock_blob)
    if bytes(t) != d:
        sys.exit("self-test FAILED: stock round-trip not byte-identical")
    print("self-test OK: stock blob round-trips byte-identically")

    out, new_vb_off, vb_off = transform(d, img)
    open(a.out, "wb").write(out)
    print(f"kernel_size {struct.unpack_from('<I', d, 8)[0]} -> {len(img)}  "
          f"vbmeta {hex(vb_off)} -> {hex(new_vb_off)}")
    changed = sum(1 for i in range(len(d)) if out[i] != d[i])
    print(f"changed bytes vs stock: {changed}  size {len(d)}  out {a.out}")


if __name__ == "__main__":
    main()
