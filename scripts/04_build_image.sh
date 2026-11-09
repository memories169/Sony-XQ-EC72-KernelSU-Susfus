#!/usr/bin/env bash
# 04_build_image.sh — configure from stock IKCONFIG, apply KSU/SUSFS fragment, build Image
set -euo pipefail
source "$(dirname "$0")/common.sh"

CONTROL=0
[ "${1:-}" = "--control" ] && CONTROL=1

require_tools python3

EXP_REL="${XM6_EXPECTED_RELEASE:?run 01 first}"
K_COMMIT="${XM6_KERNEL_COMMIT:?run 03 first}"

DEFCONFIG=$(cfg kernel.defconfig)
UNAME=$(cfg kernel_out.uname)

CLANG_BIN="$(dirname "$CLANG_DIR")/../clang-r596125/bin/clang"
: "${CLANG_BIN:=$CLANG_DIR/bin/clang}"

mkdir -p "$KERNEL_SRC/out"

# ---------- base config: exact stock config from IKCONFIG inside stock Image ----------
IKCONFIG_TOOL="$REPO_ROOT/tools/extract-ikconfig"
[ -f "$IKCONFIG_TOOL" ] || fetch_retry \
  "https://raw.githubusercontent.com/torvalds/linux/v6.1/scripts/extract-ikconfig" "$IKCONFIG_TOOL"
chmod +x "$IKCONFIG_TOOL"

log "extracting stock base config from stock Image (IKCONFIG)..."
"$IKCONFIG_TOOL" "$OUT_DIR/stock/kernel" > "$OUT_DIR/xm6.base.config"
[ -s "$OUT_DIR/xm6.base.config" ] || die "extract-ikconfig returned empty config"
log "base config lines: $(wc -l < "$OUT_DIR/xm6.base.config")"

# sanity: must be a pineapple GKI config
grep -q "^CONFIG_ARCH_PINEAPPLE=y" "$OUT_DIR/xm6.base.config" \
  || die "base config is not pineapple (ARCH_PINEAPPLE missing)"

# ---------- KSU/SUSFS fragment (skipped for CONTROL) ----------
FRAG="$OUT_DIR/xm6.fragment.config"
: > "$FRAG"
if [ "$CONTROL" = "1" ]; then
  log "CONTROL build — fragment = LOCALVERSION pin only"
  cat > "$FRAG" <<'EOF'
CONFIG_LOCALVERSION=""
# CONFIG_LOCALVERSION_AUTO is not set
EOF
else
while IFS='=' read -r k v; do
  [ -n "$k" ] || continue
  echo "$k=$v" >> "$FRAG"
done < <(python3 -c "
import json
d = json.load(open('$REPO_ROOT/configs/pdx245.json'))
for k, v in d['config']['values'].items():
    print(f'{k}={v}')
")

# vermagic pin: force LOCALVERSION empty and a fixed scmversion suffix
echo "" >> "$FRAG"
echo "CONFIG_LOCALVERSION=\"\"" >> "$FRAG"
echo "# CONFIG_LOCALVERSION_AUTO is not set" >> "$FRAG"
fi

# merge: defconfig -> base -> fragment
log "merging: gki_defconfig + stock base + KSU/SUSFS fragment"
make -C "$KERNEL_SRC" O=out ARCH=arm64 gki_defconfig
cp "$OUT_DIR/xm6.base.config" "$KERNEL_SRC/out/.config"
# run olddefconfig to settle symbols from defconfig first
make -C "$KERNEL_SRC" O=out ARCH=arm64 olddefconfig
# apply fragment on top
cat "$FRAG" >> "$KERNEL_SRC/out/.config"
make -C "$KERNEL_SRC" O=out ARCH=arm64 olddefconfig

# BTF off: pahole not available on CI; not needed for boot (stock has BTF off too? verify)
if grep -q "^CONFIG_DEBUG_INFO_BTF=y" "$KERNEL_SRC/out/.config"; then
  log "disabling DEBUG_INFO_BTF (pahole unavailable, matches CONTROL build)"
  "$KERNEL_SRC/scripts/config" --file "$KERNEL_SRC/out/.config" -d DEBUG_INFO_BTF
  echo "# CONFIG_DEBUG_INFO_BTF is not set" >> "$KERNEL_SRC/out/.config"
  make -C "$KERNEL_SRC" O=out ARCH=arm64 olddefconfig
fi

# verify critical gates
if [ "$CONTROL" = "1" ]; then
  # control gate: no KSU anywhere, core GKI intact
  if grep -q "^CONFIG_KSU=y" "$KERNEL_SRC/out/.config"; then
    die "CONTROL build must not have CONFIG_KSU=y"
  fi
  log "control gates OK (no KSU)"
else
  . "$REPO_ROOT/scripts/check_config.sh" "$KERNEL_SRC/out/.config"
fi

# scmversion pin: exact -g<hash> matching the stock kernel release
# setlocalversion reads .scmversion from the SOURCE tree root (line 56), not out/
log "pinning .scmversion for vermagic match"
echo "-g${K_COMMIT:0:12}" > "$KERNEL_SRC/.scmversion"
# also pre-seed the release file so the build does not recompute
mkdir -p "$KERNEL_SRC/out/include/config"
echo "${EXP_REL}" > "$KERNEL_SRC/out/include/config/kernel.release" 2>/dev/null || true

# ---------- build ----------
log "building Image (this takes ~20 min on GH runner)..."
make -C "$KERNEL_SRC" O=out \
  ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
  LLVM=1 LLVM_IAS=1 \
  ClangLto=0 \
  -j"$(nproc)" \
  Image

# copy artifacts
KRES=$(make -C "$KERNEL_SRC" O=out --no-print-directory kernelrelease 2>/dev/null | tail -1)
log "built kernelrelease: $KRES"
[ "$KRES" = "$EXP_REL" ] || die "kernelrelease mismatch: built $KRES != stock $EXP_REL (vermagic must match stock for signed modules)"

cp "$KERNEL_SRC/out/arch/arm64/boot/Image" "$OUT_DIR/Image"
ls -la "$OUT_DIR/Image"
log "step 04 done"
