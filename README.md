# Xm6 KernelSU-SUSFS — Xperia 1 VI (pdx245)

Custom kernel cho **Sony Xperia 1 VI (pdx245)** trên **LineageOS 24.0** (Android 17),
tích hợp **KernelSU (tiann, upstream)** + **SUSFS 2.4.0**.

> ⚠️ **LUÔN tải kèm zip `Xm6_RESTORE_stock_boot-*` trong mỗi release.**
> Nó chứa boot.img stock + hướng dẫn khôi phục — cứu máy trong ~2 phút
> qua fastboot, **không cần newflasher, không mất dữ liệu**.

---

## Vì sao bản cũ bootloop — và bản này khác gì

Phân tích cũ sai ở một điểm: **CONTROL (kernel build lại, không KSU) cũng bootloop**
⇒ lỗi không nằm ở KernelSU, mà ở **cách đóng gói boot.img**.

`boot.img` của pdx245 chứa một **AVB0 vbmeta nhúng** với hash descriptor phủ
35,651,584 byte đầu (header + kernel + padding). Kernel thay đổi ⇒ hash cũ sai
⇒ bootloader từ chối boot (loop ở logo Sony). Các bản cũ **splice** kernel mới
vào container cũ mà giữ nguyên hash ⇒ luôn bootloop, kể cả CONTROL.

**Giải pháp (bản này):** tái tạo boot.img bằng `mkbootimg` + `avbtool add_hash_footer`,
ký bằng **AOSP AVB testkey** (`testkey_rsa4096`) — đúng public key mà LineageOS
dùng để ký boot.img pdx245 (sha1 `2597c218aae470a130f61162feaae70afd97f011`).
Kết quả: boot.img mới có **chữ ký AVB hợp lệ khớp kernel mới**.

Phương pháp được chứng minh bằng thí nghiệm repro: build lại boot.img từ
**kernel stock** bằng pipeline này → **byte-identical 100%** với boot.img gốc
(trên cả 2 nightly 20261031 và 20261107).

---

## Cấu trúc pipeline

| Script | Việc |
|---|---|
| `01_fetch_bootimg.sh` | Tải boot.img từ nightly LOS mới nhất, rút kernel + salt/rollback/props từ embedded vbmeta |
| `02_setup_toolchain.sh` | clang r596125 (bản LOS 24 dùng) + kernel build-tools |
| `03_setup_source.sh` | Clone kernel @ pin, SUSFS `gki-android14-6.1`, KSU tiann @ `019a3c01`; apply `10_enable_susfs_for_ksu` vào KSU, `50_add_susfs_in_gki-android14-6.1` vào kernel; wire `drivers/kernelsu` |
| `04_build_image.sh` | Base config = IKCONFIG từ stock Image (đúng 100% config stock) + fragment chỉ chứa KSU/SUSFS; gate config; build `Image`; vermagic pin `-g72dc53f720ff` |
| `05_repack_bootimg.sh` | `mkbootimg` + `avbtool add_hash_footer` ký testkey — **không splice** |
| `06_package_ak3.sh` | AnyKernel3 zip + `standalone_boot.img` + **restore zip** + release notes |

## Flash

### Cách A — fastboot (khuyên dùng; không cần recovery)

1. **Tắt máy** hoàn toàn (giữ Power ~15s nếu máy treo logo).
2. **Giữ Volume Up** rồi cắm cáp USB vào máy tính → đèn LED **xanh dương** =
   bootloader fastboot (blue star). Đây là chế độ độc lập với boot.img nên
   **luôn vào được kể cả khi kernel hỏng**.
3. Trên máy tính:
   ```bash
   fastboot devices                # phải thấy thiết bị
   fastboot flash boot standalone_boot.img
   fastboot reboot
   ```
   `standalone_boot.img` nằm trong zip AnyKernel3 (hoặc dùng `boot-stock.img`
   từ zip restore để quay về stock).

### Cách B — recovery (nếu LOS recovery vẫn boot được)

Install zip AnyKernel3 (`*.zip` trong release).

## Bootloop? Khôi phục trong 2 phút

1. Tắt máy (giữ Power ~15s).
2. **Volume Up + cắm USB** → fastboot (đèn xanh dương).
3. `fastboot flash boot boot-stock.img` (từ zip restore) → `fastboot reboot`.

**Không dùng newflasher.** Newflasher flash toàn bộ firmware và **xóa dữ liệu** —
chỉ cần `fastboot flash boot` là đủ, mọi thứ khác nguyên vẹn.

## Cấu hình KSU/SUSFS

Kernel được build từ **config stock trích ra từ Image** (IKCONFIG) — chỉ thêm
đúng các symbol KSU/SUSFS. Fragment nằm trong `configs/pdx245.json`
(`config.values`).

Đổi tùy chọn SUSFS: sửa `configs/pdx245.json` → commit → chạy lại workflow.
Để build **CONTROL** (không KSU, dùng để cô lập lỗi bootloop):
workflow_dispatch → tick `build_control`.

## Ghi chú kỹ thuật

- **Kích thước kernel có thể khác stock** — không sao: hash AVB phủ đúng payload
  thật, footer ghi vị trí vbmeta thật; bootloader đọc footer nên chấp nhận mọi
  size hợp lệ (đã chứng minh bằng repro byte-identical khi dùng kernel stock).

- **vermagic pin**: `.scmversion` = `-g<12-ký-tự-hash>` khớp stock
  `6.1.177-g72dc53f720ff` — bắt buộc để kernel module (WiFi/bt v.v.) từ
  `/vendor_dlkm` vẫn load (MODVERSIONS y nhưng vermagic vẫn được check).
- **clang r596125**: bắt buộc để CFI type-hash khớp stock (build bằng clang khác
  sẽ không khởi động được với module ký sẵn).
- **`CONFIG_KSU_SUSFS_SUS_SU=n`**: bắt buộc — SUS_SU gây bootloop trên non-GKI.
- **Recovery của pdx245 không chứa kernel** (`BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE`
  — recovery chạy trên kernel của `boot`): hỏng boot kernel = hỏng luôn
  fastbootd/recovery. Chỉ **bootloader fastboot** là lối thoát độc lập.
- **Không bao giờ flash** `init_boot`/`recovery`/`vendor_boot`/`dtbo` khi chỉ
  đổi kernel.

## Credits

- Kernel: [LineageOS/android_kernel_sony_sm8650](https://github.com/LineageOS/android_kernel_sony_sm8650) (lineage-24.0)
- KernelSU: [tiann/KernelSU](https://github.com/tiann/KernelSU)
- SUSFS: [simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (gki-android14-6.1)
- AnyKernel3: [osm0sis](https://github.com/osm0sis) / [WildKernels gki-2.0](https://github.com/WildKernels/AnyKernel3)
- Cảm hĩnh: [ljh195/xperia-1v-sukisu-builtin](https://github.com/ljh195/xperia-1v-sukisu-builtin) (pdx234)
