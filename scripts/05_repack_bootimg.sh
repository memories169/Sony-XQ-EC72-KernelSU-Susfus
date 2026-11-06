#!/usr/bin/env bash
# Repack boot.img WITHOUT regenerating the container: splice our kernel
# Image into the untouched stock LOS boot.img.
#
# Why not regenerate with mkbootimg: LOS ships boot.img padded to the full
# 96MiB slot size carrying an embedded AVB hash footer ('AVBf' at EOF) and
# the signed vbmeta struct right after the kernel.  libavb parses those
# even when the top-level vbmeta has verification disabled; a missing/
# clobbered vbmeta struct returns AVB_SLOT_VERIFY_RESULT_ERROR_INVALID_
# METADATA, which is FATAL -> bootloop.  Both previous failures (mkbootimg
# regeneration, naive splice of an oversized kernel over the vbmeta blob)
# destroyed that struct.  The AVB-aware tool relocates the vbmeta struct
# byte-for-byte behind a larger kernel and fixes the footer pointers.
# Self-test runs on every build: transform(stock, stock blob) must return
# the stock file byte-identical.
#
# Flash order (paired vbmeta for belt+braces verification-off):
#   fastboot flash vbmeta vbmeta_pdx245_disable_verification.img
#   fastboot flash boot  boot_Xm6.img
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

STOCK="$DOWNLOADS/boot.img"
[ -f "$STOCK" ] || die "missing $STOCK (run 01_fetch_bootimg.sh)"
[ -f "$DIST_DIR/Image" ] || die "missing $DIST_DIR/Image (run 04_build_image.sh)"

mkdir -p "$DIST_DIR"
python3 "$REPO_DIR/tools/avb_reloc_repack.py" \
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
[ "$HDR_OK" = ok ] || die "AVB-reloc repack header check failed: $HDR_OK"

sha256sum "$DIST_DIR/boot_Xm6.img" > "$DIST_DIR/boot_Xm6.img.sha256"
env_put BOOTIMG_SHA256 "$(cut -d' ' -f1 < "$DIST_DIR/boot_Xm6.img.sha256")"
log "boot_Xm6.img ready (AVB-aware splice): $(stat -c%s "$DIST_DIR/boot_Xm6.img") bytes"
