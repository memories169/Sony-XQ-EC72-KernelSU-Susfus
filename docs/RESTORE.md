# Cứu máy / Khôi phục — Xperia 1 VI (pdx245)

## Nguyên tắc vàng
1. **Chỉ bao giờ ghi phân vùng `boot`.** Không flash `init_boot` / `recovery` /
   `vendor_boot` / `dtbo` — recovery của máy KHÔNG chứa kernel (chạy trên kernel
   của `boot`), hỏng boot = hỏng luôn recovery/fastbootd.
2. **Không dùng newflasher** khi chỉ lỗi kernel — nó flash toàn bộ firmware và
   **xóa sạch dữ liệu**.
3. Mọi release của repo này đều kèm `Xm6_RESTORE_stock_boot-*.zip` chứa
   `boot-stock.img` — tải trước khi flash.

## Vào chế độ bootloader fastboot (đèn xanh dương)
Hoạt động kể cả khi kernel hỏng hoàn toàn (chạy trên bootloader, không phụ thuộc
Android):

1. Tắt máy hoàn toàn — nếu máy treo logo: giữ **Power ~15–20 giây**.
2. Nhấn **giữ Volume Up** (Vol+).
3. Cầm giữ Vol+ rồi **cắm cáp USB** vào máy tính.
4. Đèn LED **xanh dương** (hoặc logo ngôi sao) = đã vào fastboot của bootloader.

> Lưu ý: đây KHÔNG phải fastbootd (fastbootd là userspace, chạy trên Android
> recovery — không vào được nếu kernel boot hỏng). Fastboot của bootloader là
> đủ cho mọi thao tác bên dưới.

## Khôi phục boot stock (2 phút, không mất dữ liệu)

```bash
# giải nén Xm6_RESTORE_stock_boot-*.zip, rồi:
fastboot devices                 # phải thấy số serial
fastboot flash boot boot-stock.img
fastboot reboot
```

Nếu máy báo `no partition 'boot'` (một số firmware chia slot):
```bash
fastboot flash boot_a boot-stock.img
fastboot flash boot_b boot-stock.img
```

## Flash kernel tùy chỉnh (cùng cách)

```bash
fastboot flash boot standalone_boot.img   # từ zip AnyKernel3
fastboot reboot
```

Hoặc qua recovery (chỉ khi recovery còn hoạt động): Install → chọn zip AnyKernel3.

## Nếu logo Sony lặp lại (bootloop)

1. Tắt máy: giữ Power ~15–20s.
2. Vào fastboot: **Vol Up + cắm USB** (xem trên).
3. `fastboot flash boot boot-stock.img` → `fastboot reboot`.
