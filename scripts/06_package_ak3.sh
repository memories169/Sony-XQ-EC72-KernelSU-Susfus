#!/usr/bin/env bash
# 06_package_ak3.sh — AnyKernel3 zip + standalone boot.img + restore package
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_tools zip

[ -f "$OUT_DIR/boot.signed.img" ] || die "run 05 first"

NIGHTLY="${XM6_NIGHTLY:-unknown}"
STAMP=$(echo "$NIGHTLY" | grep -oE '2026[0-9]{4}' | head -1 || echo "$(date +%Y%m%d)")
PREFIX=$(cfg release.zip_prefix)
AK3_REPO=$(cfg anykernel3.repo)
AK3_BRANCH=$(cfg anykernel3.branch)
AK3_COMMIT=$(cfg anykernel3.commit)

# ---------- AnyKernel3 ----------
if [ ! -d "$AK3_DIR/.git" ]; then
  log "cloning AnyKernel3 ($AK3_BRANCH)..."
  git clone --depth 1 --branch "$AK3_BRANCH" "$AK3_REPO" "$AK3_DIR"
  git -C "$AK3_DIR" checkout -q --detach "$AK3_COMMIT" 2>/dev/null || true
fi
# reset any leftovers from previous runs
git -C "$AK3_DIR" checkout -- . 2>/dev/null || true
git -C "$AK3_DIR" clean -fd 2>/dev/null || true

# ---------- anykernel.sh ----------
UNAME=$(cfg kernel_out.uname)
cat > "$AK3_DIR/anykernel.sh" <<EOF
# AnyKernel3 boot.img flasher for Xperia 1 VI (pdx245)
#.writexbytestring /properties by osm0sis @ xda
kernel.string=Pdx245 Xm6 KernelSU-SUSFS

do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=0
do.cleanuponabort=0

device.name1=pdx245
device.name2=XQ-EC54
device.name3=XQ-EC72
device.name4=XQ-EC44
device.name5=XQ-EC64

# Only ever touch the boot partition. Never init_boot/recovery/vendor_boot/dtbo.
block=/dev/block/bootdevice/by-name/boot;
is_slot_device=auto
ramdisk_compression=none

BANNER1="Xm6 KernelSU-SUSFS kernel for Xperia 1 VI (pdx245)"
BANNER2="Flash via TWRP/LOS recovery or fastboot boot.img below."

split_boot=1
flash_boot=1
EOF

# ---------- payload ----------
cp "$OUT_DIR/Image" "$AK3_DIR/Image"
cp "$OUT_DIR/boot.signed.img" "$AK3_DIR/standalone_boot.img"

# zip (AK3 requires files at zip root)
mkdir -p "$DIST_DIR"
ZIP="$DIST_DIR/${PREFIX}-pdx245-${STAMP}.zip"
rm -f "$ZIP"
(cd "$AK3_DIR" && zip -r9 -q "$ZIP" \
  anykernel.sh Image standalone_boot.img \
  -x '*.git*')

# sha256
( cd "$DIST_DIR" && sha256sum "$(basename "$ZIP")" > "$(basename "$ZIP").sha256" )

# ---------- restore package (stock boot.img + fastboot instructions) ----------
RESTORE="$DIST_DIR/Xm6_RESTORE_stock_boot-pdx245-${STAMP}.zip"
rm -f "$RESTORE"
mkdir -p "$OUT_DIR/restore"
cp "$DOWNLOADS/boot.img" "$OUT_DIR/restore/boot-stock.img"
cat > "$OUT_DIR/restore/RESTORE-README.txt" <<'EOF'
Xm6 KernelSU-SUSFS - KHOI PHUC BOOT STOCK (unbrick)
====================================================
Khoi phuc nay ghi dung 1 phan vung: boot. Khong mat du lieu.

CACH CHINH — fastbootd (bat buoc voi Xperia 1 VI):
  Bootloader fastboot cua Sony KHONG cho flash image lon (loi
  "Requested download size is more than max allowed"). Phai vao FASTBOOTD:

  1. Vao recovery cua LineageOS:
     - Neu con vao duoc he thong: Developer options -> Reboot to recovery,
       hoac: adb reboot recovery
     - Neu khong vao duoc he thong: nhan giu Vol Down trong khi cam USB
       (hoac Power + Vol Down) den thay logo recovery.
  2. Trong recovery chon: Advanced -> Reboot to fastboot
     (hoac: Fastboot / Enter fastboot). May hien chu "FASTBOOTD".
  3. Tren may tinh (co the thay QV770GL2MM nhu thuong):
       fastboot devices
       fastboot getvar current-slot        # xem slot dang dung
       fastboot flash boot boot-stock.img
       fastboot reboot
     Neu bao "no partition boot": flash ca hai slot:
       fastboot flash boot_a boot-stock.img
       fastboot flash boot_b boot-stock.img

CACH DU PHONG — bootloader fastboot (den LED xanh duong: giu Vol Up + cam USB):
  Chi DUNG khi fastbootd khong vao duoc. Thu lan luot (thuong phai flash
  TUNG SLOT va image phai nho hon max-download-size):
       fastboot getvar max-download-size    # xem gioi han
       fastboot getvar current-slot
       fastboot flash boot_a boot-stock.img
       fastboot flash boot_b boot-stock.img
  Neu loi "Requested download size is more than max allowed" tren ca hai
  slot thi bootloader khong nhan duoc image — bat buoc phai dua may ve
  recovery/fastbootd (CACH CHINH o tren), hoac dung newflasher (MAT DU LIEU).

LUU Y QUAN TRONG:
- KHONG BAO GIO flash init_boot / init_boot_a / init_boot_b: pdx245 khong
  co phan vung nay (size 0) — that bai la binh thuong, kernel khong nam o day.
- KHONG flash recovery.img / vendor_boot / dtbo khi doi kernel.
- Sau khi ve boot stock nguon: mo lai fastbootd de flash kernel mong muon.

(cd "$OUT_DIR/restore" && zip -r9 -q "$RESTORE" boot-stock.img RESTORE-README.txt)
( cd "$DIST_DIR" && sha256sum "$(basename "$RESTORE")" > "$(basename "$RESTORE").sha256" )

# ---------- release notes ----------
KSU_REF="${XM6_KSU_COMMIT:-none}"
if [ "$KSU_REF" = "none" ] || [ -z "$KSU_REF" ]; then
  BUILD_DESC="CONTROL (no KernelSU/SUSFS) — diagnostic build"
else
  BUILD_DESC="KernelSU ${KSU_REF:0:12} + SUSFS ${XM6_SUSFS_VERSION:-?}"
fi
cat > "$DIST_DIR/RELEASE_NOTES.md" <<EOF
# Xm6 KernelSU-SUSFS for Xperia 1 VI (pdx245) — build $STAMP

Kernel: LOS 24 kernel ${XM6_KERNEL_COMMIT:0:12} + $BUILD_DESC

## Nội dung
- \`$(basename "$ZIP")\` — AnyKernel3 flashable zip (recovery) + standalone boot.img bên trong
- \`$(basename "$RESTORE")\` — boot stock + hướng dẫn khôi phục (LUÔN tải kèm)
- \`*.sha256\` — checksum

## Flash
### Cách 1 — Recovery (cần recovery hoạt động)
Install zip AnyKernel3.

### Cách 2 — fastboot (khuyên dùng, cứu máy được cả khi hệ thống chết)
1. Tắt máy, giữ **Volume Up** + cắm USB → bootloader fastboot (đèn xanh dương).
2. Giải nén zip AnyKernel3, lấy file \`standalone_boot.img\` (hoặc tải zip restore về, đổi tên boot-stock.img):
   \`\`\`
   fastboot flash boot standalone_boot.img
   fastboot reboot
   \`\`\`

## Nếu bootloop
1. Tắt máy (giữ Power ~15s).
2. **Volume Up** + cắm USB → fastboot.
3. \`fastboot flash boot boot-stock.img\` (từ zip restore) → \`fastboot reboot\`.
Không cần newflasher, không mất dữ liệu.
EOF

log "step 06 done:"
ls -la "$DIST_DIR"
