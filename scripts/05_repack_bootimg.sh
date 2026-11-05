#!/usr/bin/env bash
# Repack boot.img by SPACING OUT a mkbootimg regeneration entirely:
# splice our new Image directly into the untouched stock container.
#
# Why not regenerate with mkbootimg (previous approach):
#   LOS ships boot.img padded to the full 96MiB slot size and carrying an
#   embedded AVB hash footer ('AVBf' at EOF) + vbmeta blob right after the
#   kernel. mkbootimg regeneration drops that tail. The control experiment
#   (unpatched rebuilt kernel in a regenerated container) still bootlooped
#   while stock boots via the exact same fastboot command, so the container
#   tail is the prime suspect. Splicing changes nothing else: self-test
#   (splice stock blob back -> byte-identical file) runs on every build.
#
# NOTE: when the new Image is larger than stock (KSU+SUSFS adds ~192KiB) it
# overwrites the embedded vbmeta; flash the patched vbmeta (flags=3) too:
#   fastboot --disable-verity --disable-verification flash vbmeta vbmeta_pdx245_disable_verification.img
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

STOCK="$DOWNLOADS/boot.img"
[ -f "$STOCK" ] || die "missing $STOCK (run 01_fetch_bootimg.sh)"
[ -f "$DIST_DIR/Image" ] || die "missing $DIST_DIR/Image (run 04_build_image.sh)"

mkdir -p "$DIST_DIR"
python3 "$REPO_DIR/tools/surgical_repack.py" \
  --stock "$STOCK" \
  --image "$DIST_DIR/Image" \
  --out   "$DIST_DIR/boot_Xm6.img"

HDR_OK=$(python3 - "$DIST_DIR/boot_Xm6.img" "$(stat -c%s "$DIST_DIR/Image")" "$STOCK" <<'PY'
import struct, sys
new, ksz, stock = sys.argv[1], int(sys.argv[2]), sys.argv[3]
a = open(new, 'rb').read(48); b = open(stock, 'rb').read(48)
assert a[:8] == b'ANDROID!' == b[:8]
diff = [i for i in range(48) if a[i] != b[i]]
kern = struct.unpack_from('<I', a, 8)[0]
# only kernel_size (bytes 8..12) may differ from the stock header
ok = all(8 <= i < 12 for i in diff) and kern == ksz
print('ok' if ok else f'header delta beyond kernel_size: {diff} kern={kern}')
PY
)
[ "$HDR_OK" = ok ] || die "surgical repack header check failed: $HDR_OK"

sha256sum "$DIST_DIR/boot_Xm6.img" > "$DIST_DIR/boot_Xm6.img.sha256"
env_put BOOTIMG_SHA256 "$(cut -d' ' -f1 < "$DIST_DIR/boot_Xm6.img.sha256")"
log "boot_Xm6.img ready (surgical splice): $(stat -c%s "$DIST_DIR/boot_Xm6.img") bytes"
