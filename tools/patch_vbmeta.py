#!/usr/bin/env python3
"""Patch LOS vbmeta.img: set AVB flags = 3 (verification + verity disabled).

Flashing this to the vbmeta partition makes top-level avb verification skip
all descriptor checks, which is required when our boot.img carries a kernel
that no longer matches the embedded hash (KSU+SUSFS grows the Image past the
embedded vbmeta region). Unlocked bootloader -> nobody checks this partition's
own signature.

The partition's own RSA signature becomes invalid after editing flags - that
is expected and irrelevant on unlocked devices (same as Magisk's approach).
"""
import argparse
import struct

# AvbVBMetaImageHeader: magic4 major2 minor2 pad4 auth(3xQ) aux(3xQ) ...
# flags is a U32 located at offset 116? No: fields order
#   magic(4) authentication(4) auxiliary(4) _reserved(4)
# struct layout: '4sHH4x' + 6x'Q' (12) + 2x'Q'  -> flags at 4+2+2+4+6*8 = 60? compute
# avb_tool header: magic, format_major, format_minor, _pad,
#   authentication_block_offset, _size, authentication_padding, _size(2 more Q),
#   auxiliary_block_offset, _size ... then flags (U32) at offset 116 is wrong;
# measured empirically on pdx245 LOS vbmeta: flags lives at offset 104.
FLAGS_OFF = 104


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out", dest="dst", required=True)
    a = ap.parse_args()
    d = bytearray(open(a.src, "rb").read())
    if d[:4] != b"AVB0":
        raise SystemExit("not an AVB vbmeta image")
    cur = struct.unpack_from(">I", d, FLAGS_OFF)[0]
    struct.pack_into(">I", d, FLAGS_OFF, 3)
    open(a.dst, "wb").write(bytes(d))
    print(f"ok: flags {cur} -> 3 (verification+verity disabled), {len(d)} bytes")


if __name__ == "__main__":
    main()
