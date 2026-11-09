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
Xm6 KernelSU-SUSFS — KHÔI PHỤC BOOT STOCK (unbrick)
====================================================
Khôi phục này ghi đúng 1 phân vùng: boot. Không mất dữ liệu.

Cách 1 — fastboot (khuyên dùng; hoạt động cả khi không vào được hệ thống):
  1. Tắt máy hoàn toàn (giữ Power 10-15s nếu cần).
  2. Giữ nút Volume Up (Vol+) rồi cắm cáp USB vào máy tính
     → đèn LED xanh dương / ngôi sao xanh = bootloader fastboot.
  3. Trên máy tính:
       fastboot devices
       fastboot flash boot boot-stock.img
       fastboot reboot
  4. Xong: máy đã về boot stock của LineageOS. Dữ liệu nguyên vẹn.

Cách 2 — recovery (nếu vẫn boot được recovery):
  TWRP/LOS recovery → Install → chọn zip AnyKernel3 stock (nếu có) hoặc
  dùng dd: dd if=boot-stock.img of=/dev/block/bootdevice/by-name/boot

Lưu ý:
- KHÔNG BAO GIỜ flash init_boot.img hoặc recovery.img khi đổi kernel:
  hai phân vùng này KHÔNG chứa kernel; hỏng boot = hỏng luôn recovery.
- Phân vùng khởi động đôi (A/B): nếu fastboot báo "no boot partition",
  thử: fastboot flash boot_a boot-stock.img ; fastboot flash boot_b boot-stock.img
EOF
(cd "$OUT_DIR/restore" && zip -r9 -q "$RESTORE" boot-stock.img RESTORE-README.txt)
( cd "$DIST_DIR" && sha256sum "$(basename "$RESTORE")" > "$(basename "$RESTORE").sha256" )

# ---------- release notes ----------
if [ "$XM6_KSU_COMMIT" = "none" ] || [ -z "${XM6_KSU_COMMIT:-}" ]; then
  BUILD_DESC="CONTROL (no KernelSU/SUSFS) — diagnostic build"
else
  BUILD_DESC="KernelSU ${XM6_KSU_COMMIT:0:12} + SUSFS ${XM6_SUSFS_VERSION:-?}"
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
