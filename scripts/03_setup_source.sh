#!/usr/bin/env bash
# Materialise kernel source + KernelSU + SUSFS and wire everything together.
#   1. clone LineageOS/android_kernel_sony_sm8650 at the boot.img-matching commit
#   2. clone susfs4ksu (gki-android14-6.1, pinned) and KernelSU (tiann, pinned)
#   3. copy susfs sources + apply 50_add_susfs patch
#   4. apply the KernelSU enable-susfs patch (gives CONFIG_KSU_SUSFS*)
#   5. wire drivers/kernelsu (symlink, Makefile, Kconfig)
#   6. generate merged defconfig + root fragment
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

KSU_REPO="$(cfg .root.repo)"                 # tiann/KernelSU
KSU_BRANCH="$(cfg .root.branch)"
KSU_COMMIT="${KERNELSU_COMMIT:-$(cfg .root.commit)}"
KSU_PATCH="$(cfg .root.susfs_patch)"
SUSFS_REPO="$(cfg .susfs.repo)"
SUSFS_BRANCH="$(cfg .susfs.branch)"
SUSFS_COMMIT="${SUSFS_COMMIT:-$(cfg .susfs.commit)}"
FAMILY="$(cfg .family)"                      # android14-6.1
DEFCONFIG="$(cfg .device.defconfig)"
FRAGMENTS="$(cfg .device.config_fragments)"
SRC_REPO_URL="https://github.com/$KERNEL_SRC_REPO"
KERNEL_COMMIT="${KERNEL_COMMIT:-$STOCK_KERNEL_COMMIT}"
SUBLEVEL=$(echo "$EXPECTED_RELEASE" | sed -E 's/^[0-9]+\.[0-9]+\.([0-9]+).*/\1/')

mkdir -p "$OUT_DIR"

# ---- 1. kernel source -------------------------------------------------------
if [ ! -d "$KERNEL_SRC/.git" ]; then
  log "Cloning $SRC_REPO_URL @ ${KERNEL_COMMIT:0:12}"
  rm -rf "$KERNEL_SRC"; mkdir -p "$KERNEL_SRC"
  git -C "$KERNEL_SRC" init -q
  git -C "$KERNEL_SRC" remote add origin "$SRC_REPO_URL"
  fetch_retry git -C "$KERNEL_SRC" fetch --depth 1 --no-tags origin "$KERNEL_COMMIT"
  git -C "$KERNEL_SRC" checkout -q FETCH_HEAD
else
  log "kernel source exists, reusing"
fi
[ "$(git -C "$KERNEL_SRC" rev-parse HEAD)" = "$KERNEL_COMMIT" ] || \
  die "kernel source HEAD != $KERNEL_COMMIT (pin/manifest mismatch)"

# ---- 2. susfs4ksu + KernelSU ------------------------------------------------
if [ ! -d "$SUSFS_DIR/.git" ]; then
  log "Cloning susfs4ksu $SUSFS_BRANCH"
  fetch_retry git clone --quiet --branch "$SUSFS_BRANCH" --single-branch --depth 50 \
    "$SUSFS_REPO" "$SUSFS_DIR"
  git -C "$SUSFS_DIR" checkout --quiet "$SUSFS_COMMIT"
fi
git -C "$SUSFS_DIR" rev-parse HEAD | grep -q "^$SUSFS_COMMIT\$" || \
  die "susfs HEAD $(git -C "$SUSFS_DIR" rev-parse HEAD) != pin $SUSFS_COMMIT"

if [ ! -d "$KSU_DIR/.git" ]; then
  log "Cloning $KSU_REPO $KSU_BRANCH"
  fetch_retry git clone --quiet --branch "$KSU_BRANCH" --single-branch --depth 100 \
    "https://github.com/$KSU_REPO.git" "$KSU_DIR"
  git -C "$KSU_DIR" checkout --quiet "$KSU_COMMIT"
fi
[ "$(git -C "$KSU_DIR" rev-parse HEAD)" = "$KSU_COMMIT" ] || \
  die "KernelSU HEAD != pin $KSU_COMMIT"

# ---- 3. SUSFS into the kernel tree ------------------------------------------
SUSFS_PATCH_FILE="$SUSFS_DIR/kernel_patches/50_add_susfs_in_gki-$FAMILY.patch"
[ -f "$SUSFS_PATCH_FILE" ] || die "missing $SUSFS_PATCH_FILE"
if ! grep -q 'susfs.o' "$KERNEL_SRC/fs/Makefile" 2>/dev/null; then
  log "Copying susfs sources (fs/susfs.c, include/linux/susfs*.h)"
  cp "$SUSFS_DIR/kernel_patches/fs/"* "$KERNEL_SRC/fs/"
  cp "$SUSFS_DIR/kernel_patches/include/linux/"* "$KERNEL_SRC/include/linux/"
  log "Applying $(basename "$SUSFS_PATCH_FILE")"
  ( cd "$KERNEL_SRC" && patch -p1 --silent --forward < "$SUSFS_PATCH_FILE" )
else
  log "SUSFS already applied, skipping"
fi

# ---- 4. KernelSU with susfs enable patch ------------------------------------
if [ -n "$KSU_PATCH" ] && [ -f "$SUSFS_DIR/$KSU_PATCH" ]; then
  if ! grep -q KSU_SUSFS "$KSU_DIR/kernel/Kconfig"; then
    log "Applying $(basename "$KSU_PATCH") to KernelSU"
    ( cd "$KSU_DIR" && patch -p1 --silent --forward < "$SUSFS_DIR/$KSU_PATCH" )
  else
    log "KernelSU already susfs-enabled, skipping"
  fi
fi

# ---- 5. wire KernelSU into drivers/ ------------------------------------------
ln -sfn "$KSU_DIR/kernel" "$KERNEL_SRC/drivers/kernelsu"
grep -q 'obj-\$(CONFIG_KSU)' "$KERNEL_SRC/drivers/Makefile" || \
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$KERNEL_SRC/drivers/Makefile"
grep -q 'drivers/kernelsu/Kconfig' "$KERNEL_SRC/drivers/Kconfig" || \
  sed -i '$i source "drivers/kernelsu/Kconfig"' "$KERNEL_SRC/drivers/Kconfig"

# ---- 6. build config = EXACT stock config + KSU/SUSFS on top ----------------
# LineageOS embeds its full .config into the stock Image (CONFIG_IKCONFIG).
# We reuse it verbatim so every driver symbol matches the nightly; the only
# additions are CONFIG_KSU* (root fragment). Anything else stays as Sony/LOS shipped.
STOCK_IMG="${STOCK_KERNEL:-$OUT_DIR/stock/kernel}"
[ -f "$STOCK_IMG" ] || die "stock kernel blob missing (run 01_fetch_bootimg.sh)"
log "Extracting stock .config from boot Image (IKCONFIG)"
"$KERNEL_SRC/scripts/extract-ikconfig" "$STOCK_IMG" > "$OUT_DIR/xm6.base.config"
grep -q "^CONFIG_ARCH_PINEAPPLE=y" "$OUT_DIR/xm6.base.config" || \
  die "extracted config lacks ARCH_PINEAPPLE - not a valid LOS pdx245 image"

FRAG="$OUT_DIR/xm6.fragment"
python3 - "$DEVICE_CONFIG" "$FRAG" <<'PYEOF'
import json, sys
conf, out = sys.argv[1], sys.argv[2]
c = json.load(open(conf))["config"]
with open(out, "w") as f:
    f.write("# Xm6 root fragment (KSU/SUSFS only; base = stock IKCONFIG)\n")
    for k, v in c.items():
        f.write(f"{k}={v}\n" if v != "" else f'{k}=""\n')
PYEOF

KERNELRELEASE_SUFFIX="-g${KERNEL_COMMIT:0:12}"
printf '%s\n' "$KERNELRELEASE_SUFFIX" > "$KERNEL_SRC/.scmversion"
env_put KERNELRELEASE_EXPECTED "$(grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL)' "$KERNEL_SRC/Makefile" | cut -d= -f2 | tr -d ' ' | paste -sd. -)$KERNELRELEASE_SUFFIX"
log "wrote .scmversion ($KERNELRELEASE_SUFFIX) - vermagic will match stock"
log "source ready"
