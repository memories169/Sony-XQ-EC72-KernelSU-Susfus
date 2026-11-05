#!/usr/bin/env bash
# Build arch/arm64/boot/Image from the EXACT stock config (extracted via
# IKCONFIG from the nightly boot.img) with KSU/SUSFS symbols added on top.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"
export PATH="$CLANG_HOME/bin:$BT_HOME/bin:$PATH"

JOBS="${JOBS:-$(nproc)}"
O=out
MAKE=(make -C "$KERNEL_SRC" "O=$O" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
      LLVM=1 LLVM_IAS=1 ClangLto=0 -j"$JOBS")

mkdir -p "$OUT_DIR" "$KERNEL_SRC/$O"

if [ "${SKIP_CONFIG:-0}" != "1" ]; then
  [ -f "$OUT_DIR/xm6.base.config" ] || die "missing $OUT_DIR/xm6.base.config (run 03)"
  log "Seeding .config from stock IKCONFIG + root fragment"
  python3 - "$OUT_DIR/xm6.base.config" "$OUT_DIR/xm6.fragment" "$KERNEL_SRC/$O/.config" <<'PY'
import re, sys
base, frag, outp = sys.argv[1:4]
frags = {}
for line in open(frag):
    line = line.strip()
    if line and not line.startswith('#') and '=' in line:
        k, v = line.split('=', 1)
        frags[k] = v
# escape hatch for hosts without pahole: XM6_DISABLE_BTF=1 (stock keeps BTF=y)
import os
if os.environ.get('XM6_DISABLE_BTF') == '1':
    frags['CONFIG_DEBUG_INFO_BTF'] = 'n'
base_lines = []
seen = set()
for line in open(base):
    m = re.match(r'(# )?(CONFIG_[A-Za-z0-9_]+)(=.*)?', line)
    if m and m.group(2) in frags:
        continue  # drop, fragment value appended below
    base_lines.append(line)
with open(outp, 'w') as o:
    o.writelines(base_lines)
    o.write('\n# ---- Xm6 root fragment ----\n')
    for k, v in frags.items():
        o.write(f"{k}={v}\n" if v != '""' else f'{k}=""\n')
PY
  "${MAKE[@]}" olddefconfig > "$OUT_DIR/olddefconfig.log" 2>&1 || die "olddefconfig failed"

  # hard sanity checks - these caused the first bootloop
  for sym in CONFIG_ARCH_PINEAPPLE CONFIG_KSU CONFIG_KSU_SUSFS CONFIG_CFI_CLANG \
             CONFIG_MODVERSIONS CONFIG_MODULES; do
    grep -q "^$sym=y" "$KERNEL_SRC/$O/.config" || die "$sym missing in final .config"
  done
  grep -q "^CONFIG_LTO_NONE=y" "$KERNEL_SRC/$O/.config" || die "LTO_NONE missing (stock has no LTO)"

  # proof: final config must equal stock except KSU/SUSFS/BTF deltas
  DIFFS=$(python3 - "$OUT_DIR/xm6.base.config" "$KERNEL_SRC/$O/.config" <<'PY'
import re, sys
def load(p):
    d = {}
    for line in open(p):
        s = line.strip()
        m = re.match(r'(# )?(CONFIG_[A-Za-z0-9_]+)(?:=(.*))?', s)
        if not m: continue
        if m.group(1): d[m.group(2)] = 'n' if 'is not set' in s else None
        elif m.group(2):
            v = m.group(3) or ''
            d[m.group(2)] = v.split(' #')[0]
    return {k: v for k, v in d.items() if v is not None}
a, b = load(sys.argv[1]), load(sys.argv[2])
diffs = [(k, a.get(k), b.get(k)) for k in sorted(set(a) | set(b))
         if a.get(k, '<abs>') != b.get(k, '<abs>')]
HOST_DEP = ('CONFIG_RUST_IS_AVAILABLE', 'CONFIG_CC_HAS_', 'CONFIG_HAVE_',
            'CONFIG_GCC_VERSION', 'CONFIG_CC_VERSION_TEXT', 'CONFIG_CLANG_VERSION',
            'CONFIG_LD_VERSION', 'CONFIG_LD_IS_', 'CONFIG_AS_', 'CONFIG_PAHOLE',
            'CONFIG_DEBUG_INFO_BTF', 'CONFIG_LOCALVERSION', 'CONFIG_LD_HAS_',
            'CONFIG_RUSTC_VERSION', 'CONFIG_RUSTC_HAS_', 'CONFIG_AS_HAS_')
bad = [d for d in diffs if not (d[0].startswith('CONFIG_KSU')
       or d[0].startswith(HOST_DEP))]
for d in bad[:20]: print('UNEXPECTED:', d)
print(len(bad))
PY
) || die "config comparison failed"
  N=$(echo "$DIFFS" | tail -1)
  [ "$N" = 0 ] || { echo "$DIFFS"; die "$N unexpected config deviations from stock"; }
  log "config matches stock (only KSU/SUSFS/BTF deltas) ✔"
fi

REL=$("${MAKE[@]}" -s kernelrelease)
log "kernelrelease: $REL (stock: $EXPECTED_RELEASE)"
[ "$REL" = "$EXPECTED_RELEASE" ] || die "kernelrelease mismatch! vermagic would break stock modules"

log "Building Image with $JOBS jobs"
"${MAKE[@]}" Image 2>&1 | tee "$OUT_DIR/build.log" | grep -vE '^  (CC|AS|AR|LD|GEN|CALL|HOSTCC|HOSTLD|LINK|BTF|OBJCOPY|SORTTAB)' || true
grep -iE "^[^ ]*: error|Error [0-9]" "$OUT_DIR/build.log" && die "compile errors, see $OUT_DIR/build.log"
[ -f "$KERNEL_SRC/$O/arch/arm64/boot/Image" ] || die "Image not produced"

mkdir -p "$DIST_DIR"
cp "$KERNEL_SRC/$O/arch/arm64/boot/Image" "$DIST_DIR/Image"
cp "$KERNEL_SRC/$O/.config" "$DIST_DIR/config"
strings "$DIST_DIR/Image" | grep -m1 'Linux version' | tee "$DIST_DIR/version.txt"
SHA=$(sha256sum "$DIST_DIR/Image" | cut -d' ' -f1)
env_put IMAGE_SHA256 "$SHA"
log "Image ready sha256=$SHA size=$(stat -c%s "$DIST_DIR/Image")"
