# Task 04 — AirMouse Receiver.app

## ผลลัพธ์

สร้าง macOS native app bundle สำหรับ Apple Silicon แล้ว: เปิดหน้าต่าง AirMouse Receiver เพื่อแสดง IP/port, สถานะโทรศัพท์, อัตราข้อความ, ขนาดจอ และสถานะ Accessibility พร้อมปุ่มคัดลอก/เปิดการตั้งค่า/เริ่ม server ใหม่

## Toolkit

เลือก AppKit ผ่าน PyObjC ที่มีอยู่แล้วใน `desktop/.venv` แทน tkinter เพราะไม่ต้องเพิ่ม `python-tk@3.13`, ใช้ native macOS window และเรียก Accessibility API ได้ตรงกว่า ตัว WebSocket server ทำงานใน background thread; UI อ่าน state ผ่าน timer ของ AppKit บน main thread

ใช้ PyInstaller แบบ `--windowed --onedir` เพื่อให้เป็น app bundle รูปแบบปกติของ macOS และเลี่ยงข้อจำกัด one-file bundle ใน PyInstaller รุ่นใหม่

## การใช้งาน

1. เปิด `AirMouse Receiver.app` จาก DMG แล้วลากไป `Applications`
2. ครั้งแรกให้คลิกขวาแอป > **Open** เพราะยังไม่ได้ notarise
3. ใส่ IP:port ที่แสดงในแอปลงในโทรศัพท์
4. ถ้า Accessibility ยังไม่ผ่าน กด **เปิดการตั้งค่า** แล้วอนุญาต `AirMouse Receiver`

ทดสอบโดยไม่เปิด GUI: `desktop/dist/AirMouse Receiver.app/Contents/MacOS/AirMouse Receiver --selftest --port 61234`

สำหรับ dry-run ของ GUI ใช้ `--dry-run` (ไม่ขยับเมาส์) — ผู้ตรวจสามารถเปิดแอปจริงหลัง review ได้

## Verification

- `cd desktop && ../desktop/.venv/bin/python -m unittest -v` — 3 tests ผ่าน
- source `receiver_app.py --selftest` + WebSocket hello — ผ่าน
- build: `./desktop/build.sh` — ผ่าน; สร้าง app, DMG, ZIP และ Windows ZIP
- `codesign --verify --deep --strict "desktop/dist/AirMouse Receiver.app"` — ผ่าน
- ตรวจ `Info.plist`: bundle id `com.nattakit.airmouse.receiver`, version `1.0.0`, display name และ local-network usage description — ผ่าน
- bundled executable `--selftest` + WebSocket hello — `selftest OK: hello handled in dry-run mode`
- mac ZIP ตรวจแล้วมีเฉพาะ `.app` bundle ไม่มี `__MACOSX`, loose binary หรือ `.command`
- ไม่ได้เปิด GUI, ไม่ได้เปิดหน้าต่าง และไม่ขยับเมาส์ระหว่าง verification

## Artifacts

- `web/downloads/AirMouse-Receiver-mac.dmg` — 10.3 MB
- `web/downloads/AirMouse-Receiver-mac.zip` — 9.8 MB
- `web/downloads/AirMouse-Receiver-windows.zip` — 10.8 MB
- `desktop/dist/AirMouse Receiver.app` — ประมาณ 23 MB (onedir bundle)

## ความเสี่ยง/ข้อจำกัด

- แอป ad-hoc signed ยังไม่ notarised: Gatekeeper อาจต้องใช้คลิกขวา > Open ครั้งแรก
- Accessibility permission ผูกกับ bundle identifier และ code signature; การ rebuild แล้ว ad-hoc sign ใหม่อาจต้องอนุญาต Accessibility ซ้ำ
- รองรับเฉพาะ Apple Silicon ตาม requirement; Intel Macs ไม่รองรับ
- ถ้า port 8765 ถูกใช้โดย CLI receiver อยู่ แอปจะแสดงข้อผิดพลาดภาษาไทยแทนการ crash

TASK-04 DONE
