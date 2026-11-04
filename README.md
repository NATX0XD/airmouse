# AirMouse: ใช้โทรศัพท์เป็นเมาส์ชี้กลางอากาศ

หันโทรศัพท์แล้วเคอร์เซอร์บนคอมขยับตาม เหมือนรีโมต LG Magic Remote ใช้ gyroscope เป็นเซนเซอร์หลัก

```
app/       Expo SDK 58 (iPhone + Android)  gyro -> motion engine -> transport
desktop/   Python receiver สำหรับโหมด WiFi (Mac / PC)
tools/     deploy-ios.sh
dongle/    (เฟส 5) ESP32-S3 รับ BLE แล้วเป็น USB mouse
```

## สถานะ (2026-11-01)
| ส่วน | สถานะ |
|---|---|
| WiFi + receiver (Mac) | ใช้งานได้บน iPhone จริง |
| คาลิเบต (วางนิ่ง / ขอบซ้าย-ขวา / กลางจอ) | เขียนเสร็จ ติดตั้งบน iPhone แล้ว รอทดสอบ |
| สะบัดเปลี่ยนสไลด์ (เฉพาะโหมดแตะค้าง) | เขียนเสร็จ รอทดสอบ |
| ดองเกิล ESP32-S3 (BLE -> USB mouse) | firmware compile ผ่าน แอป build ผ่าน **ยังไม่ทดสอบกับบอร์ดจริง** |
| Android Bluetooth HID | APK build ผ่าน **ยังไม่ทดสอบบน Android จริง** |
| ตัวรับ Windows (zip พกพา) | แพ็กเสร็จ **ยังไม่เคยรันบน Windows** |
| Landing page (`web/`) | เสร็จ ยังไม่ได้ deploy |

ตรวจแล้ว: unit test แอป 21 ข้อ, receiver 2 ชุด, tsc, lint, build iOS, assembleRelease Android, arduino-cli compile
รายละเอียด: `docs/codex/task-0*-report.md`, protocol: `docs/codex/protocol-v2.md`, firmware: `dongle/README.md`, ตัวรับ: `desktop/README.md`

## Landing page / ไฟล์ติดตั้ง
```
desktop/build.sh                 # สร้าง zip ตัวรับ Mac + Windows ลง web/downloads
cp app/dist/AirMouse.apk web/downloads/ && web/update-downloads.sh
cd web && python3 -m http.server 8000   # ดูหน้าเว็บ
```

## รันโหมด WiFi
1. คอม: 
   ```
   cd desktop
   /opt/homebrew/bin/python3.13 -m venv .venv && .venv/bin/pip install -r requirements.txt   # ครั้งแรก
   .venv/bin/python receiver.py          # หรือ --dry-run เพื่อดูอย่างเดียว
   ```
   Mac: เปิดสิทธิ์ Accessibility ให้แอป Terminal ที่ใช้รัน (System Settings > Privacy & Security > Accessibility)
2. โทรศัพท์กับคอมต้องอยู่ WiFi วงเดียวกัน (WiFi มหาวิทยาลัยมักบล็อก ใช้ hotspot)
3. แอป: ใส่ IP ที่ receiver แสดง กด "เชื่อม" แล้วแตะค้างที่แผ่นกลางจอและหันเครื่อง

## ติดตั้งบน iPhone
```
airmouse/tools/deploy-ios.sh
```
ครั้งแรกต้อง Trust ใน Settings > General > VPN & Device Management และกด Allow สิทธิ์ Local Network

## ทดสอบ
```
cd app && npm test && npx tsc --noEmit && npx expo lint
```

## โหมด BLE / HID
เลือกโหมดจากแถบด้านบนของหน้ารีโมตได้ โหมด WiFi ใช้ IP/port และโหมดอื่นจะแสดงปุ่มเชื่อมต่อของตัวเอง BLE ต้องใช้บอร์ด ESP32-S3 ที่แฟลช firmware แล้ว ส่วน HID ใช้ได้เฉพาะ Android 9+ (บางยี่ห้อปิดฟีเจอร์นี้ไว้ ให้ใช้ดองเกิลแทน)

เมื่อ firmware พร้อม ให้เสียบ ESP32-S3 ผ่าน USB-OTG แล้วกด BOOT ค้าง แตะ RESET และปล่อย BOOT จากนั้นใช้คำสั่งใน `dongle/README.md` เพื่อ compile/upload

## หลักการ
- ถือเครื่องแนวตั้ง หัวเครื่องชี้จอ: หันซ้าย-ขวา = gyro แกน Z, ก้ม-เงย = แกน X
- `dx = ความเร็วการหมุน x เวลา x ความไว` เก็บเศษพิกเซลไว้ ทำให้หันช้าๆ ก็ยังขยับ
- One Euro filter: นิ่งเมื่อขยับช้า ไวเมื่อขยับเร็ว
- Clutch: ขยับเฉพาะตอนนิ้วแตะแผ่น แก้ drift ของ gyro
