#!/usr/bin/env bash
# Build arch/arm64/boot/Image:
#   gki_defconfig + pineapple/sony fragments + xm6 root fragment
# then assert the produced kernelrelease matches the stock boot.img.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"
export PATH="$CLANG_HOME/bin:$BT_HOME/bin:$PATH"

DEFCONFIG="$(cfg .device.defconfig)"
JOBS="${JOBS:-$(nproc)}"
O=out
MAKE=(make -C "$KERNEL_SRC" "O=$O" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
      LLVM=1 LLVM_IAS=1 ClangLto=0 -j"$JOBS")

mkdir -p "$OUT_DIR"

if [ "${SKIP_CONFIG:-0}" != "1" ]; then
  log "Defconfig: $DEFCONFIG + fragments"
  rm -rf "$KERNEL_SRC/$O"
  "${MAKE[@]}" "$DEFCONFIG"

  FRAGS=()
  while IFS= read -r f; do
    [ -f "$KERNEL_SRC/$f" ] && FRAGS+=("$KERNEL_SRC/$f")
  done < <(python3 -c "import json;print('\n'.join(json.load(open('$DEVICE_CONFIG'))['device']['config_fragments']))")
  FRAGS+=("$OUT_DIR/xm6.fragment")

  "$KERNEL_SRC/scripts/kconfig/merge_config.sh" -m -O "$O" \
    "$KERNEL_SRC/$O/.config" "${FRAGS[@]}" > "$OUT_DIR/merge_config.log" 2>&1 \
    || die "merge_config.sh failed, see $OUT_DIR/merge_config.log"
  "${MAKE[@]}" olddefconfig

  # sanity: root configs survived kconfig resolution
  for sym in CONFIG_KSU CONFIG_KSU_SUSFS CONFIG_KSU_SUSFS_SUS_KSTAT; do
    grep -q "^$sym=y" "$KERNEL_SRC/$O/.config" || die "$sym missing in final .config"
  done
  grep -q "^CONFIG_LTO_NONE=y" "$KERNEL_SRC/$O/.config" || die "LTO_NONE missing (stock has no LTO)"
fi

REL=$("${MAKE[@]}" -s kernelrelease)
log "kernelrelease: $REL (stock: $EXPECTED_RELEASE)"
[ "$REL" = "$EXPECTED_RELEASE" ] || die "kernelrelease mismatch! vermagic would break stock modules"

log "Building Image with $JOBS jobs"
"${MAKE[@]}" Image 2>&1 | tee "$OUT_DIR/build.log" | grep -vE '^  (CC|AS|AR|LD|GEN|CALL|HOSTCC|HOSTLD|LINK|BTF|OBJCOPY|SORTTAB)' || true
[ -f "$KERNEL_SRC/$O/arch/arm64/boot/Image" ] || die "Image not produced"

cp "$KERNEL_SRC/$O/arch/arm64/boot/Image" "$DIST_DIR/Image" 2>/dev/null || { mkdir -p "$DIST_DIR"; cp "$KERNEL_SRC/$O/arch/arm64/boot/Image" "$DIST_DIR/Image"; }
cp "$KERNEL_SRC/$O/.config" "$DIST_DIR/config"
strings "$DIST_DIR/Image" | grep -m1 'Linux version' | tee "$DIST_DIR/version.txt"
SHA=$(sha256sum "$DIST_DIR/Image" | cut -d' ' -f1)
env_put IMAGE_SHA256 "$SHA"
log "Image ready sha256=$SHA size=$(stat -c%s "$DIST_DIR/Image")"
