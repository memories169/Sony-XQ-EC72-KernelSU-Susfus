#!/usr/bin/env bash
# 05_repack_bootimg.sh — regenerate boot.img: mkbootimg + avbtool re-sign with AOSP testkey
#
# This is the critical fix over the old splice approach: the embedded vbmeta hash
# descriptor covers the first 35,651,584 bytes (header+kernel+padding). Any kernel
# change invalidates it. Instead of splicing, we REGENERATE the payload with
# mkbootimg and RE-SIGN with the AOSP AVB testkey (the same public key LineageOS
# uses to sign pdx245 boot.img — sha1 2597c218...), producing a valid signature
# over the new kernel. Verified byte-identical against stock when the stock
# kernel is used (see README).
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_tools python3

[ -f "$OUT_DIR/Image" ] || die "run 04 first"
[ -f "$OUT_DIR/stock/avb.json" ] || die "run 01 first"

MKBOOT="$REPO_ROOT/tools/mkbootimg/mkbootimg.py"
AVBTOOL="$REPO_ROOT/tools/mkbootimg/avbtool.py"
KEY="$REPO_ROOT/keys/testkey_rsa4096.pem"
[ -f "$KEY" ] || die "missing AVB testkey: $KEY"

PART_SIZE=$(cfg bootimg.avb.partition_size)
ALGO=$(cfg bootimg.avb.algorithm)
HDR_VER=$(cfg bootimg.header_version)
PAGE=$(cfg bootimg.page_size)
OS_VER=$(python3 -c "
import json
d=json.load(open('$OUT_DIR/stock/avb.json'))
# os_version from prop: '17' -> '17.0.0'
print(d['props']['com.android.build.boot.os_version'] + '.0.0')")

# os_patch_level from boot header (v4 reads back via unpack step 01)
OS_PATCH=$(python3 -c "
import re
txt=open('$OUT_DIR/stock/unpack.txt').read()
m=re.search(r'--os_patch_level[ =](\d{4})-(\d{2})', txt)
print(m.group(1)+'-'+m.group(2) if m else '2026-11')")

SALT=$(python3 -c "import json;print(json.load(open('$OUT_DIR/stock/avb.json'))['salt'])")
RBI=$(python3 -c "import json;print(json.load(open('$OUT_DIR/stock/avb.json'))['rollback_index'])")

log "regenerating payload (header v$HDR_VER, page $PAGE, os $OS_VER patch $OS_PATCH)"
python3 "$MKBOOT" \
  --kernel "$OUT_DIR/Image" \
  --ramdisk "$OUT_DIR/stock/ramdisk" \
  --header_version "$HDR_VER" \
  --os_version "$OS_VER" \
  --os_patch_level "$OS_PATCH" \
  --cmdline '' \
  --output "$OUT_DIR/boot.payload.img"

log "re-signing AVB (testkey, salt from stock, rollback $RBI)"
cp "$OUT_DIR/boot.payload.img" "$OUT_DIR/boot.signed.img"
python3 "$AVBTOOL" add_hash_footer \
  --image "$OUT_DIR/boot.signed.img" \
  --partition_size "$PART_SIZE" \
  --partition_name boot \
  --key "$KEY" \
  --algorithm "$ALGO" \
  --salt "$SALT" \
  --rollback_index "$RBI" \
  --prop com.android.build.boot.os_version:"${OS_VER%%.*}" \
  --prop "com.android.build.boot.fingerprint:$(python3 -c "import json;print(json.load(open('$OUT_DIR/stock/avb.json'))['props']['com.android.build.boot.fingerprint'])")" \
  --prop com.android.build.boot.security_patch:"$(python3 -c "import json;print(json.load(open('$OUT_DIR/stock/avb.json'))['props']['com.android.build.boot.security_patch'])")"

# sanity: footer present, self-consistent (vbmeta right after payload, footer inside partition).
# NOTE: offsets need NOT equal stock's — a differently-sized kernel shifts them; the AVBf footer
# records the actual layout and the bootloader follows the footer.
python3 - "$OUT_DIR/boot.signed.img" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
f = d[-64:]
assert f[:4] == b'AVBf', 'missing AVBf footer'
orig_size  = struct.unpack_from('>Q', f, 12)[0]
vb_off     = struct.unpack_from('>Q', f, 20)[0]
vb_size    = struct.unpack_from('>Q', f, 28)[0]
assert orig_size == vb_off, f'payload end {orig_size} != vbmeta offset {vb_off}'
assert d[vb_off:vb_off+4] == b'AVB0', 'vbmeta blob not at recorded offset'
assert vb_off + vb_size < len(d), 'vbmeta out of partition bounds'
print(f'  footer OK: orig_size={orig_size} vbmeta@{vb_off} (size {vb_size})')
PY

# avbtool info on final image
python3 "$AVBTOOL" info_image --image "$OUT_DIR/boot.signed.img" > "$OUT_DIR/boot.avb_info.txt"
grep -E "Public key|Algorithm|Rollback Index:|Image Size|Salt" "$OUT_DIR/boot.avb_info.txt" || true

# byte-diff against stock for the record
if cmp -s "$OUT_DIR/boot.signed.img" "$DOWNLOADS/boot.img"; then
  log "RESULT: byte-identical with stock boot.img (control case)"
else
  ND=$(cmp -l "$OUT_DIR/boot.signed.img" "$DOWNLOADS/boot.img" | wc -l || true)
  log "RESULT: differs from stock in $ND bytes (expected — kernel is patched)"
fi

log "step 05 done: $OUT_DIR/boot.signed.img"
