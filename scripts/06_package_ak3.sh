#!/usr/bin/env bash
# Build the AnyKernel3 flashable zip around the new Image.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

AK3_REPO="$(cfg .anykernel3.repo)"
AK3_BRANCH="$(cfg .anykernel3.branch)"
AK3_COMMIT="${AK3_COMMIT:-$(cfg .anykernel3.commit)}"

if [ ! -d "$AK3_DIR/.git" ]; then
  log "Cloning AnyKernel3 ($AK3_BRANCH)"
  rm -rf "$AK3_DIR"
  fetch_retry git clone --quiet --branch "$AK3_BRANCH" --single-branch --depth 1 \
    "$AK3_REPO" "$AK3_DIR"
  git -C "$AK3_DIR" checkout --quiet "$AK3_COMMIT" 2>/dev/null || true
fi

cp "$DIST_DIR/Image" "$AK3_DIR/Image"

cat > "$AK3_DIR/anykernel.sh" <<EOF
### AnyKernel3 - Xm6 KernelSU+SUSFS for Xperia 1 VI (pdx245)
## based on osm0sis AnyKernel3 (gki-2.0)

properties() { '
kernel.string=Xm6 KernelSU+SUSFS for Xperia 1 VI (pdx245)
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
do.check_boot_version=0
device.name1=pdx245
device.name2=XQ-EC54
device.name3=XQ-EC72
device.name4=XQ-EC44
device.name5=XQ-EC64
supported.versions=
supported.patchlevels=
'; } # end properties

## boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching - DO NOT REMOVE
. tools/ak3-core.sh

ui_print " " "  -> Xperia 1 VI (pdx245): KernelSU + SUSFS"
ui_print "  -> kernel $EXPECTED_RELEASE"

# The zip ships a complete stock-repacked boot.img (AOSP mkbootimg, header and
# cmdline byte-identical to stock, kernel section swapped for our Image).
# flash_generic handles A/B slots, dynamic partitions and verity-aware resize.
if [ -f boot.img -o -f boot.img.img ]; then
  flash_generic boot
else
  ui_print "  -> no prebuilt boot.img, repacking live boot with Image"
  split_boot
  write_boot
fi

ui_print " " "Done. Reboot, then install a KernelSU manager app."
ui_print " "

EOF

cp "$DIST_DIR/boot_Xm6.img" "$AK3_DIR/boot.img"
rm -rf "$AK3_DIR/.git"

ZIP_NAME="${ZIP_NAME:-Xm6_KernelSU_SUSFS-pdx245-$(date -u +%Y%m%d).zip}"
( cd "$AK3_DIR" && zip -qr9 "$DIST_DIR/$ZIP_NAME" . -x '*.git*' )
sha256sum "$DIST_DIR/$ZIP_NAME" > "$DIST_DIR/$ZIP_NAME.sha256"
env_put ZIP_NAME "$ZIP_NAME"
log "zip ready: $ZIP_NAME ($(stat -c%s "$DIST_DIR/$ZIP_NAME") bytes)"
