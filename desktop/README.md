# AirMouse Receiver

ตัวรับบนคอมจะเปิด WebSocket ให้แอปโทรศัพท์เชื่อมต่อ ทั้งสองอุปกรณ์ต้องอยู่ Wi‑Fi เดียวกัน

## รันจาก source

macOS (Apple Silicon):

```sh
cd desktop
/opt/homebrew/bin/python3.13 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python receiver.py --dry-run
```

Windows: ติดตั้ง Python 3.13 จาก python.org แล้วรัน `py -m pip install -r requirements.txt` จากโฟลเดอร์นี้ จากนั้น `py receiver.py --dry-run` (เอา `--dry-run` ออกเมื่อต้องการใช้เมาส์จริง)

คัดลอก IP ที่โปรแกรมแสดงไปใส่ในแอปและใช้ port เดียวกัน (ค่าเริ่มต้น 8765) บน macOS ต้องอนุญาต Terminal ใน System Settings > Privacy & Security > Accessibility

## ทดสอบ

```sh
.venv/bin/python -m unittest -v test_receiver.py
```
