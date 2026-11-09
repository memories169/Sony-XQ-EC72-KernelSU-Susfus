#!/usr/bin/env bash
# 03_setup_source.sh — kernel source (+ optional KSU/SUSFS), wire in
set -euo pipefail
source "$(dirname "$0")/common.sh"

CONTROL=0
[ "${1:-}" = "--control" ] && CONTROL=1
KSU_ONLY=0
[ "${1:-}" = "--ksu-only" ] && KSU_ONLY=1

require_tools git python3 patch

K_REPO=$(cfg kernel.repo)
K_BRANCH=$(cfg kernel.branch)
K_COMMIT=$(cfg kernel.commit)
KSU_REPO=$(cfg kernelsu.repo)
KSU_COMMIT=$(cfg kernelsu.commit)
SUS_REPO=$(cfg susfs.repo)
SUS_BRANCH=$(cfg susfs.branch)
SUS_COMMIT=$(cfg susfs.commit)

# ---------- kernel ----------
if [ -d "$KERNEL_SRC/.git" ]; then
  log "kernel source already cloned"
else
  log "cloning kernel $K_REPO ($K_BRANCH)..."
  git clone --depth 1 --branch "$K_BRANCH" "$K_REPO" "$KERNEL_SRC"
fi
git -C "$KERNEL_SRC" fetch --depth 1 origin "$K_COMMIT" 2>/dev/null || true
git -C "$KERNEL_SRC" checkout -q --detach "$K_COMMIT"
KRES=$(git -C "$KERNEL_SRC" rev-parse HEAD)
[ "$KRES" = "$K_COMMIT" ] || die "kernel checkout mismatch: $KRES != $K_COMMIT"
log "kernel @ ${KRES:0:12}"
env_put XM6_KERNEL_COMMIT "$KRES"

# ---------- SUSFS / KernelSU (skipped for CONTROL build) ----------
if [ "$CONTROL" = "1" ]; then
  log "CONTROL build requested — skipping KernelSU/SUSFS integration"
  env_put XM6_KSU_COMMIT "none"
  env_put XM6_SUSFS_COMMIT "none"
  env_put XM6_SUSFS_VERSION "none"
  log "step 03 done (control): source ready at $KERNEL_SRC"
  exit 0
fi

rm -rf "$SUSFS_DIR"
log "cloning susfs4ksu ($SUS_BRANCH)..."
git clone --depth 1 --branch "$SUS_BRANCH" "$SUS_REPO" "$SUSFS_DIR"
if [ "$SUS_COMMIT" != "auto" ]; then
  git -C "$SUSFS_DIR" fetch --depth 1 origin "$SUS_COMMIT" 2>/dev/null || true
  git -C "$SUSFS_DIR" checkout -q --detach "$SUS_COMMIT"
fi
SUSRES=$(git -C "$SUSFS_DIR" rev-parse HEAD)
SUSVER=$(grep -m1 -oP '(?<=#define SUSFS_VERSION ")[^"]+' \
           "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" 2>/dev/null || echo 'unknown')
log "susfs4ksu @ ${SUSRES:0:12} version $SUSVER"
env_put XM6_SUSFS_COMMIT "$SUSRES"
env_put XM6_SUSFS_VERSION "$SUSVER"

KSU_PATCH="$SUSFS_DIR/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
SUS_PATCH="$SUSFS_DIR/kernel_patches/50_add_susfs_in_gki-android14-6.1.patch"
[ -f "$KSU_PATCH" ] || die "missing KSU susfs patch: $KSU_PATCH"
[ -f "$SUS_PATCH" ] || die "missing kernel susfs patch: $SUS_PATCH"

# ---------- KernelSU ----------
rm -rf "$KSU_DIR"
log "cloning KernelSU @ ${KSU_COMMIT:0:12}..."
git clone --depth 50 "$KSU_REPO" "$KSU_DIR"
git -C "$KSU_DIR" fetch --depth 1 origin "$KSU_COMMIT" 2>/dev/null || true
git -C "$KSU_DIR" checkout -q --detach "$KSU_COMMIT"
KSURES=$(git -C "$KSU_DIR" rev-parse HEAD)
[ "$KSURES" = "$KSU_COMMIT" ] || die "KernelSU checkout mismatch: $KSURES != $KSU_COMMIT"
log "KernelSU @ ${KSURES:0:12}"

# 1) apply 10_enable_susfs_for_ksu.patch INSIDE the KernelSU tree first
#    (KSU-only builds use pristine KSU: the susfs patch requires susfs kernel-side)
if [ "$KSU_ONLY" = "1" ]; then
  log "KSU-ONLY variant: skipping susfs patch on KernelSU"
else
  log "applying 10_enable_susfs_for_ksu.patch to KernelSU..."
  git -C "$KSU_DIR" apply --check "$KSU_PATCH" || die "KSU susfs patch does not apply cleanly"
  git -C "$KSU_DIR" apply "$KSU_PATCH"
fi

if [ "$KSU_ONLY" = "1" ]; then
  log "KSU-ONLY variant: skipping kernel susfs patch + files"
else
  # ---------- kernel patches ----------
  log "applying 50_add_susfs_in_gki-android14-6.1.patch to kernel..."
  git -C "$KERNEL_SRC" apply --check "$SUS_PATCH" || die "kernel susfs patch does not apply cleanly"
  git -C "$KERNEL_SRC" apply "$SUS_PATCH"

# copy susfs source files (patch adds build wiring; files live in kernel_patches/)
cp -v "$SUSFS_DIR/kernel_patches/fs/susfs.c"            "$KERNEL_SRC/fs/"
# upstream 2.4.0 bug: the no-log stub block misses the _RL variants while susfs.c calls them
# unconditionally -> undeclared-function errors when CONFIG_KSU_SUSFS_ENABLE_LOG=n. Patch the
# copied file (not the pristine patch source).
python3 - "$KERNEL_SRC/fs/susfs.c" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines(keepends=True)
out, inserted = [], False
for i, ln in enumerate(lines):
    out.append(ln)
    if not inserted and ln.startswith('#define SUSFS_LOGE(fmt'):
        nxt = lines[i + 1].rstrip('\n') if i + 1 < len(lines) else ''
        window = ''.join(lines[i:i + 3])
        if nxt.startswith('#endif') and '_RL' not in window:
            out.append('#define SUSFS_LOGI_RL(fmt, ...)\n')
            out.append('#define SUSFS_LOGE_RL(fmt, ...)\n')
            inserted = True
if inserted:
    open(p, 'w').writelines(out)
    print("susfs.c: added missing _RL no-log stubs")
else:
    print("susfs.c: _RL stubs already present or pattern not found - leaving as-is")
PY
cp -v "$SUSFS_DIR/kernel_patches/include/linux/susfs.h"     "$KERNEL_SRC/include/linux/"
cp -v "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" "$KERNEL_SRC/include/linux/"
fi

# ---------- wire KernelSU into the kernel tree ----------
log "wiring drivers/kernelsu into kernel tree..."
mkdir -p "$KERNEL_SRC/drivers/kernelsu"
cp -a "$KSU_DIR/kernel/." "$KERNEL_SRC/drivers/kernelsu/"
# Upstream ships include/uapi -> ../../uapi (relative to the KSU repo root). In our flat copy
# the anchor is drivers/kernelsu/, so ../.. lands OUTSIDE the kernel tree — repoint the
# symlink at ../uapi (one level up = drivers/kernelsu/uapi, filled right below).
rm -f "$KERNEL_SRC/drivers/kernelsu/include/uapi"
ln -sfn ../uapi "$KERNEL_SRC/drivers/kernelsu/include/uapi"
# KSU sources include "uapi/app_profile.h" and, via -I$(KSU_KERNEL_DIR)/include,
# "uapi/supercall.h". Upstream keeps the canonical uapi/ at the repo root while
# kernel/include/uapi/ holds a partial copy — mirror the union into BOTH places so the
# flat in-tree build resolves every include.
mkdir -p "$KERNEL_SRC/drivers/kernelsu/uapi"
cp -a "$KSU_DIR/uapi/." "$KERNEL_SRC/drivers/kernelsu/uapi/"

# Makefile wiring: append at end (idempotent)
if ! grep -q "obj-\$(CONFIG_KSU)" "$KERNEL_SRC/drivers/Makefile"; then
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$KERNEL_SRC/drivers/Makefile"
fi

# Kconfig wiring: insert source before the final endmenu (idempotent)
if ! grep -q 'source "drivers/kernelsu/Kconfig"' "$KERNEL_SRC/drivers/Kconfig"; then
  python3 - "$KERNEL_SRC/drivers/Kconfig" <<'PY'
import sys
p = sys.argv[1]
txt = open(p).read()
idx = txt.rfind('endmenu')
if idx == -1:
    txt += '\nsource "drivers/kernelsu/Kconfig"\n'
else:
    txt = txt[:idx] + 'source "drivers/kernelsu/Kconfig"\n\n' + txt[idx:]
open(p, 'w').write(txt)
print('Kconfig: kernelsu source inserted before endmenu')
PY
fi

log "step 03 done: source ready at $KERNEL_SRC"
