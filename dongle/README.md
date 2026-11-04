# AirMouse ESP32-S3 dongle

สถานะ: firmware compile ผ่านด้วย Arduino-ESP32 core 3.3.12 แล้ว แต่ยังไม่ได้ทดสอบกับบอร์ดจริง

Firmware ใช้ BLE library ที่มากับ Arduino-ESP32 core 3.x (`BLEDevice.h`) เพราะเป็นไลบรารีใน core เดียวกัน ไม่เพิ่ม NimBLE-Arduino dependency และใช้ TinyUSB HID ใน core ผ่าน `USB.h`, `USBHIDMouse` และ `USBHIDKeyboard` รายงานรับได้ครั้งละหลาย report แต่ความยาวต้องหาร 5 ลงตัว

ติดตั้ง core จาก Espressif official board index แล้วดู FQBN/ตัวเลือกจริงด้วย:

```sh
arduino-cli core update-index
arduino-cli core install esp32:esp32
arduino-cli board listall | grep -i esp32s3
arduino-cli board details esp32:esp32:esp32s3
```

จาก `arduino-cli board details -b esp32:esp32:esp32s3` พบว่า USB-OTG (TinyUSB) ใช้ `USBMode=default` (ส่วน Hardware CDC/JTAG คือ `USBMode=hwcdc`) จึงใช้ FQBN นี้:

```sh
arduino-cli compile --fqbn esp32:esp32:esp32s3:USBMode=default dongle/airmouse_dongle
arduino-cli upload -p /dev/cu.usbmodemXXXX --fqbn esp32:esp32:esp32s3:USBMode=default dongle/airmouse_dongle
```

ก่อน flash ให้กด BOOT ค้าง แล้วแตะ RESET หนึ่งครั้ง ปล่อย BOOT จากนั้นเลือก USB port ของ USB-OTG/ดาวน์โหลด เช่น `/dev/cu.usbmodemXXXX` (ชื่อจริงขึ้นกับบอร์ด) แล้วรันคำสั่ง upload ด้านบน
