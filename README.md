# Xm6 KernelSU + SUSFS — Sony Xperia 1 VI (pdx245 / XQ-EC72)

Tự động build lại **kernel LineageOS 24 (android14-6.1) chính chủ của Xperia 1 VI**
và nhúng sẵn **KernelSU** + **SUSFS** ngay trong nhân (in-tree), phát hành dưới 2 dạng:

| Artifact | Dùng khi nào |
|---|---|
| `Xm6_KernelSU_SUSFS-pdx245-*.zip` | Flash qua **custom recovery** (OrangeFox/TWRP) — cách khuyến nghị |
| `boot_Xm6.img` (+ `.sha256`) | Fastboot: `fastboot flash boot_a/b boot_Xm6.img` |

Toàn bộ quy trình chạy trên **GitHub Actions**: mỗi lần build, workflow

1. Hỏi [LineageOS API](https://download.lineageos.org/api/v2/devices/pdx245/builds) lấy **nightly mới nhất** cho `pdx245`, tải `boot.img` + `build-manifest.xml` gốc (verify SHA-256).
2. Đọc đúng commit kernel mà nightly đó dùng (`android_kernel_sony_sm8650`), clone chính xác commit ấy — **không** dùng source lệch phiên bản.
3. Tải đúng toolchain LineageOS dùng: **clang-r596125** (tag `android-17.0.0_r1`) + `kernel-build-tools`.
4. Patch source với [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) `gki-android14-6.1` và [KernelSU (tiann)](https://github.com/tiann/KernelSU) + `10_enable_susfs_for_ksu.patch`.
5. Build `Image` với `gki_defconfig` + fragment `pineapple_GKI.config` + `sony/pineapple_GKI.config` **giống hệt** LineageOS, và **giữ nguyên vermagic** `6.1.177-g72dc53f720ff` nên module stock (wifi/bt dlkm…) vẫn nạp được.
6. Repack `boot_Xm6.img` bằng tool AOSP `mkbootimg` — header/cmdline/ramdisk byte-identical với boot gốc, chỉ swap khối kernel — và đóng gói zip AnyKernel3.

> Vì kernel build từ đúng commit source + đúng clang + đúng config của nightly,
> bạn có thể flash đè lên kernel hiện tại của máy **mà không cần flash lại ROM**
> (boot.img stock và bản build ra cùng source).

## Tình trạng kernel nguồn

- Dòng máy: Xperia 1 VI, SoC SM8650 (pineapple/niobe), `android14-6.1`, kernel `6.1.177`.
- Stock **không bật LTO**, có **CFI** — bản build giữ nguyên như vậy để module gốc hợp lệ.
- `vermagic` được ghim qua `.scmversion` → `6.1.177-g72dc53f720ff SMP preempt mod_unload modversions aarch64` (khớp 100% boot gốc).
- `CONFIG_DEBUG_INFO_BTF` tắt trong bản vá (tránh phụ thuộc pahole trên runner); `IKHEADERS` là module nên .config vẫn xuất ra được.

## Nhân Root: tại sao là tiann KernelSU?

KernelSU-Next đời mới đã chuyển SUSFS sang LKM riêng (cần DDK, không nằm trong Image).
Cấu hình **đã kiểm chứng** (giống các repo [WildKernels](https://github.com/WildKernels/GKI_KernelSU_SUSFS)):

- `tiann/KernelSU` (pinned) + patch chính thức `10_enable_susfs_for_ksu.patch` của susfs4ksu
  → có `CONFIG_KSU_SUSFS*`, SUSFS nằm **trong** nhân, không cần module.
- Manager tương thích: **KernelSU** (tiann), **KernelSU-Next**, **SukiSU Ultra**, **FinaSU** — đều nói chuyện được với in-tree KSU; riêng KernelSU manager gốc là hợp lệ chắc chắn nhất.

SUSFS bật: `SUS_PATH, SUS_MOUNT, SUS_KSTAT, TRY_UMOUNT, SPOOF_UNAME, SPOOF_CMDLINE,
HIDE_SYMBOLS, OPEN_REDIRECT, SUS_MAP, AUTO_ADD_*` (tắt `SUS_OVERLAYFS`, `SUS_SU` — dùng Zygisk Next/SusFS module nếu cần).

## Cài đặt

Yêu cầu: **bootloader đã mở khoá**, đang chạy **LineageOS 24 cho pdx245** (hoặc boot tương thích).

### Cách 1 — recovery
1. Tải `Xm6_KernelSU_SUSFS-pdx245-*.zip` từ trang Releases.
2. Boot vào custom recovery → Install → chọn zip → reboot.

### Cách 2 — fastboot
```bash
# kiểm tra sha256 trước
sha256sum -c boot_Xm6.img.sha256
# flash đúng slot đang active (xem: fastboot getvar current-slot)
fastboot flash boot_a boot_Xm6.img   # hoặc boot_b
fastboot reboot
```

### Vấn đề thường gặp

- **`Unsupported device. Aborting...`** — bản zip trước 05/11/2026 chỉ nhận `pdx245`/`XQ-EC72`,
  trong khi LineageOS pdx245 khai báo `ro.product.device` là SKU EEA (vd. `XQ-EC54`).
  Tải lại zip mới nhất (đã nhận mọi SKU XQ-EC44/54/64/72) hoặc dùng fastboot.
- **`flash_boot failed` / partition không resize được** → dùng fastboot thay recovery:
  `fastboot flash boot_<slot> boot_Xm6.img`
- zip **có chứa sẵn `boot.img`** đã repack (khác các bản AK3 GKI thường chỉ có `Image`):
  đây là chủ ý. Bố trí partition của pdx245 theo chuẩn GKI hdr v4:
  `boot.img` = nhân thuần (**ramdisk rỗng**), `init_boot.img` = ramdisk GKI (first-stage init),
  `dtbo.img` = DTB. KernelSU + SUSFS nằm **trong nhân** nên không cần vá ramdisk ở `init_boot`;
  `init_boot`/`dtbo`/`vendor_boot` giữ nguyên của ROM, zip chỉ thay `boot`.
  Cách của AK3 mẫu (magiskboot vá Image vào boot đang chạy) không dùng được ở đây vì
  chẳng có ramdisk trong boot để vá — vì vậy zip flash nguyên ảnh boot dựng lại từ header stock.
  Nếu muốn, bạn vẫn có thể `fastboot` riêng file `boot.img` extract từ zip.

### Sau khi boot
1. Cài app **KernelSU** (hoặc KernelSU-Next/SukiSU) → phải báo *Đã cài đặt / Đang chạy*.
2. (Tuỳ chọn) cài **Zygisk Next** + module **SusFS Checker** để xác nhận SUSFS: `dmesg | grep -i susfs`.
3. Kiểm tra root: mở app → cấp root cho terminal.

## Rủi ro & lưu ý

- **Bootloader phải unlock** — bảo hành mất, widevine L1 mất (đây là sự thật với mọi kernel tùy chỉnh).
- `boot_Xm6.img` **không còn AVB footer** của bản signed (được tạo lại bằng mkbootimg). Với bootloader đã unlock + `vbmeta` LineageOS (đã `--disable-verity --disable-verification`) thì boot bình thường. Nếu máy bạn còn enforced dm-verity, flash kèm `vbmeta.img` của LineageOS với 2 cờ trên.
- Luôn giữ **boot gốc của đúng nightly đang chạy** (`downloads/boot.img` tải về là bản gốc 100%) để `fastboot flash boot` khôi phục khi cần.
- Kernel flash kiểu này **không tự vá A/B**: khi OTA/đổi nightly, flash lại zip/boot của nightly mới nhất từ repo này.
- Mình **không** chịu trách nhiệm nếu máy bạn bootloop. Đủ kỹ năng cứu máy (edl/fastboot) trước khi flash.

## Build lại thủ công (local)

```bash
git clone https://github.com/memories169/Sony-XQ-EC72-KernelSU-Susfus && cd Sony-XQ-EC72-KernelSU-Susfus
# cần: linux x86_64, git curl python3 bison flex bc rsync cpio zip patch, ~13GB đĩa
for s in scripts/0*.sh; do bash "$s"; done   # chạy lần lượt 01 → 06
# sản phẩm: dist/*.zip, dist/boot_Xm6.img
```
Cấu hình device nằm trong [`configs/pdx245.json`](configs/pdx245.json) (commit pin, fragment, danh sách config KSU/SUSFS). Có thể override commit qua biến môi trường: `KERNEL_COMMIT= SUSFS_COMMIT= KERNELSU_COMMIT=`.

## Ghi công

- [LineageOS](https://download.lineageos.org/devices/pdx245) — kernel nguồn + boot gốc
- [tiann/KernelSU](https://github.com/tiann/KernelSU), [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) — root & ẩn root
- [WildKernels/GKI_KernelSU_SUSFS](https://github.com/WildKernels/GKI_KernelSU_SUSFS) — tham khảo cách tích hợp & AnyKernel3 `gki-2.0`
- AOSP `system/tools/mkbootimg` — repack boot.img (đã verify round-trip byte-perfect với boot pdx245)

## Cấu trúc repo

```
.github/workflows/build.yml   CI: API → toolchain → patch → build → repack → zip → release
configs/pdx245.json           device profile (pins, defconfig, KSU/SUSFS configs)
scripts/01..06*.sh            các bước build (chạy được độc lập local)
tools/mkbootimg/              AOSP unpack_bootimg/mkbootimg/avbtool (vendored)
```
