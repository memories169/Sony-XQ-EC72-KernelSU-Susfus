# Cứu máy / Khôi phục — Xperia 1 VI (pdx245)

## Nguyên tắc vàng
1. **Chỉ bao giờ ghi phân vùng `boot`.** Không flash `init_boot` /
   `init_boot_a` / `init_boot_b` — **pdx245 KHÔNG có phân vùng này**
   (`fastboot flash init_boot` báo `partition size 0` là bình thường, luôn
   thất bại). Kernel nằm trong `boot`. Cũng không đụng `recovery` /
   `vendor_boot` / `dtbo` — hỏng boot = hỏng luôn recovery/fastbootd.
2. **Không dùng newflasher** khi chỉ lỗi kernel — nó flash toàn bộ firmware
   và **xóa sạch dữ liệu**.
3. Mọi release của repo này đều kèm `Xm6_RESTORE_stock_boot-*.zip` chứa
   `boot-stock.img` — tải trước khi flash.

## Cách chính — fastbootd (bắt buộc cho image lớn)

**Bootloader fastboot của Sony từ chối nhận image lớn** (lỗi
`Requested download size is more than max allowed`) — phải vào **fastbootd**
(userspace, chạy trên LOS recovery):

1. Vào recovery:
   - Còn boot được hệ điều hành: **adb reboot recovery**, hoặc Developer
     options → Reboot to recovery.
   - Không boot được: **nhấn giữ Vol Down trong khi cắm USB** (hoặc Power +
     Vol Down) cho tới khi thấy logo recovery.
2. Trong recovery: **Advanced → Reboot to fastboot** (máy hiện chữ
   `FASTBOOTD`).
3. Trên máy tính:
   ```bash
   fastboot devices              # QV770GL2MM …
   fastboot getvar current-slot  # xem slot hiện hành
   fastboot flash boot boot-stock.img   # hoặc standalone_boot.img
   fastboot reboot
   ```
   Nếu báo `no partition boot`: flash cả hai slot:
   ```bash
   fastboot flash boot_a boot-stock.img
   fastboot flash boot_b boot-stock.img
   ```

## Cách dự phòng — bootloader fastboot (đèn xanh dương)

Vào chế độ: tắt máy hoàn toàn (giữ Power ~15–20s) → **giữ Vol Up + cắm USB**
→ đèn LED xanh dương / ngôi sao. `fastboot devices` vẫn thấy máy.

Chỉ dùng khi **không vào được fastbootd**. Giới hạn download size nhỏ:
```bash
fastboot getvar max-download-size   # xem trần cho phép
fastboot flash boot_a boot-stock.img
fastboot flash boot_b boot-stock.img
```
- Nếu lỗi `Requested download size is more than max allowed` trên **cả hai
  slot** → bootloader không nhận được image: buộc phải quay lại đường
  fastbootd ở trên (hoặc newflasher = mất dữ liệu).
- Flash thành công từng slot là đủ: A/B slot dự cho nhau, kernel sai slot
  còn lại vẫn có thể boot bằng slot tốt.

## Flash kernel tùy chỉnh

```bash
# trong fastbootd:
fastboot flash boot standalone_boot.img   # từ zip AnyKernel3
fastboot reboot
```
Hoặc qua recovery (khi recovery còn boot): Install → chọn zip AnyKernel3.

## Nếu logo Sony lặp lại (bootloop)

1. Tắt máy: giữ Power ~15–20s.
2. Giữ **Vol Down + cắm USB** → vào recovery → **Reboot to fastboot**.
3. `fastboot flash boot boot-stock.img` → `fastboot reboot`.
