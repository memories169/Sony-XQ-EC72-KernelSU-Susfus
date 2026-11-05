#!/usr/bin/env bash
# Repack a boot.img whose kernel section is our new Image.
# 1. unpack stock boot.img with vendored AOSP mkbootimg tools
#    (round-trip verified byte-perfect on pdx245 stock image)
# 2. swap the kernel blob, re-run mkbootimg with the *measured* header fields.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

MKB="$REPO_DIR/tools/mkbootimg"
STOCK="$DOWNLOADS/boot.img"
[ -f "$STOCK" ] || die "missing $STOCK (run 01_fetch_bootimg.sh)"
[ -f "$DIST_DIR/Image" ] || die "missing $DIST_DIR/Image (run 04_build_image.sh)"

rm -rf "$OUT_DIR/unpack"; mkdir -p "$OUT_DIR/unpack" "$DIST_DIR"

ARGS=$(python3 "$MKB/unpack_bootimg.py" --boot_img "$STOCK" --out "$OUT_DIR/unpack" --format mkbootimg)
log "stock mkbootimg args: $ARGS"

# Force our own Image; keep everything else (os version/patch level/cmdline) from stock.
# Drop the --cmdline pair: its value token '' survives shell word-splitting as
# literal two-quote chars (0x27 0x27) landing in boot cmdline bytes 44-45 ->
# the kernel receives garbage parameters. mkbootimg default cmdline is "" anyway.
ARGS_CLEAN=$(ARGS="$ARGS" DIST_IMG="$DIST_DIR/Image" python3 - <<'PYX'
import os
toks = os.environ['ARGS'].split()
out = []
i = 0
while i < len(toks):
    t = toks[i]
    if t == '--cmdline':
        i += 2                     # drop pair: default cmdline is ""
        continue
    if t == '--kernel':
        out += ['--kernel', os.environ['DIST_IMG']]
        i += 2                     # drop stock kernel path too
        continue
    out.append(t)
    i += 1
print(' '.join(out))
PYX
)
log "mkbootimg args: $ARGS_CLEAN"
# shellcheck disable=SC2086
python3 "$MKB/mkbootimg.py" $ARGS_CLEAN \
  --output "$DIST_DIR/boot_Xm6.img"

IMG_KSZ=$(stat -c%s "$DIST_DIR/Image")
HDR_OK=$(python3 - "$DIST_DIR/boot_Xm6.img" "$IMG_KSZ" <<'PY'
import struct, sys
off = 0 if open(sys.argv[1],'rb').read(8) == b'ANDROID!' else -1
assert off == 0, "unexpected boot header magic"
with open(sys.argv[1],'rb') as f:
    f.seek(0); h = struct.unpack('<8s10I', f.read(48))
kern, page, hdrv = h[1], h[8], h[9]
print('ok' if kern == int(sys.argv[2]) else f'kernel_size {kern} != {sys.argv[2]}')
PY
)
[ "$HDR_OK" = ok ] || die "repacked boot.img kernel_size check failed: $HDR_OK"

sha256sum "$DIST_DIR/boot_Xm6.img" > "$DIST_DIR/boot_Xm6.img.sha256"
env_put BOOTIMG_SHA256 "$(cut -d' ' -f1 < "$DIST_DIR/boot_Xm6.img.sha256")"
log "boot_Xm6.img ready: $(stat -c%s "$DIST_DIR/boot_Xm6.img") bytes"
