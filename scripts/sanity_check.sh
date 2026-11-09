#!/usr/bin/env bash
# sanity_check.sh — run locally before pushing: validates repack math against stock
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

log "=== sanity check: repack byte-identity (stock kernel through full pipeline) ==="

# requires out/stock/kernel + out/stock/avb.json (from 01)
[ -f "$OUT_DIR/stock/kernel" ] || die "run scripts/01_fetch_bootimg.sh first"
[ -f "$OUT_DIR/stock/avb.json" ] || die "avb.json missing — 01 failed?"

SALT=$(python3 -c "import json;print(json.load(open('$OUT_DIR/stock/avb.json'))['salt'])")
RBI=$(python3 -c "import json;print(json.load(open('$OUT_DIR/stock/avb.json'))['rollback_index'])")
PROPS=$(python3 -c "
import json
d=json.load(open('$OUT_DIR/stock/avb.json'))['props']
for k,v in d.items(): print(f'--prop {k}:{v}')")

# build payload from STOCK kernel, then sign
python3 tools/mkbootimg/mkbootimg.py \
  --kernel "$OUT_DIR/stock/kernel" --ramdisk "$OUT_DIR/stock/ramdisk" \
  --header_version 4 --os_version 17.0.0 --os_patch_level 2026-11 \
  --cmdline '' --output "$OUT_DIR/sanity.payload.img"

cp "$OUT_DIR/sanity.payload.img" "$OUT_DIR/sanity.signed.img"
# shellcheck disable=SC2086
python3 tools/mkbootimg/avbtool.py add_hash_footer \
  --image "$OUT_DIR/sanity.signed.img" \
  --partition_size 100663296 \
  --partition_name boot \
  --key keys/testkey_rsa4096.pem \
  --algorithm SHA256_RSA4096 \
  --salt "$SALT" \
  --rollback_index "$RBI" \
  $PROPS

if cmp -s "$OUT_DIR/sanity.signed.img" "$DOWNLOADS/boot.img"; then
  log "✔ BYTE-IDENTICAL — repack pipeline is cryptographically correct"
else
  die "✘ MISMATCH — repack pipeline broken; do not release"
fi
