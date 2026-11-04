# AirMouse: Presentation Script (about 5 minutes)

Each English line is followed by its Thai translation. Short sentences, so it is easy to read aloud.

---

## 1. Introduction (แนะนำ) · 30 sec

Hello everyone. Our project is called AirMouse.

สวัสดีครับ โปรเจกต์ของเราชื่อ AirMouse

AirMouse turns your iPhone into an air mouse for your Mac.

AirMouse เปลี่ยน iPhone ให้เป็นเมาส์ลอยอากาศสำหรับ Mac

You point the phone at the screen, and the cursor follows your hand.

แค่ชี้โทรศัพท์ไปที่จอ เคอร์เซอร์ก็ขยับตามมือ

It works like the Magic Remote of an LG TV.

ใช้งานเหมือนรีโมต Magic Remote ของทีวี LG

---

## 2. Problem (ปัญหา) · 30 sec

When we present or watch movies, we must walk back to the computer to click.

เวลานำเสนองานหรือดูหนัง เราต้องเดินกลับไปคลิกที่คอมพิวเตอร์

A presenter remote costs extra money.

รีโมตพรีเซนต์ก็ต้องเสียเงินซื้อเพิ่ม

But everyone already has a smartphone full of sensors.

แต่ทุกคนมีสมาร์ตโฟนที่มีเซนเซอร์อยู่แล้ว

So we use the phone instead.

เราจึงใช้โทรศัพท์แทน

---

## 3. Sensors (เซนเซอร์ที่ใช้) · 40 sec

AirMouse uses four main sensors.

AirMouse ใช้เซนเซอร์หลัก 4 ตัว

First, the gyroscope detects phone rotation and controls the cursor.

ตัวแรก Gyroscope ตรวจจับการหมุนของโทรศัพท์ เพื่อควบคุมเคอร์เซอร์

Second, the accelerometer detects the phone's position using gravity.

ตัวที่สอง Accelerometer ใช้แรงโน้มถ่วงช่วยตรวจสอบทิศทางของโทรศัพท์

Third, the proximity sensor detects nearby objects during calibration.

ตัวที่สาม Proximity sensor ตรวจจับวัตถุที่อยู่ใกล้ ระหว่างการปรับเทียบ

Finally, the touchscreen is used for clicking and scrolling.

สุดท้าย Touchscreen ใช้คลิกและเลื่อนหน้าจอ

We also use the camera to scan a QR code, and vibration for feedback.

นอกจากนี้ยังใช้กล้องสแกน QR code และใช้การสั่นเพื่อตอบสนองผู้ใช้

---

## 4. How It Works (การทำงาน) · 50 sec

The gyroscope sends data about 100 times per second.

Gyroscope ส่งข้อมูลประมาณ 100 ครั้งต่อวินาที

The app removes small sensor errors.

แอปลบค่าคลาดเคลื่อนเล็กๆ ของเซนเซอร์ออก

Then a filter makes the movement smooth, even when your hand shakes.

จากนั้นใช้ตัวกรองทำให้การขยับนิ่ง แม้มือจะสั่นเล็กน้อย

The phone sends small move messages to the Mac by Wi-Fi or Bluetooth.

โทรศัพท์ส่งข้อความการขยับเล็กๆ ไปที่ Mac ผ่าน Wi-Fi หรือ Bluetooth

The Mac app receives them and moves the real cursor.

แอปบน Mac รับข้อความแล้วขยับเคอร์เซอร์จริง

All data stays in your home network.

ข้อมูลทั้งหมดอยู่ในเครือข่ายบ้าน ไม่ออกไปอินเทอร์เน็ต

---

## 5. Calibration (การปรับเทียบ) · 40 sec

Every screen and every distance is different, so we calibrate first.

จอแต่ละจอและระยะนั่งไม่เท่ากัน เราจึงต้องปรับเทียบก่อน

First, hold the phone against the screen.

ขั้นแรก ทาบโทรศัพท์กับหน้าจอ

The sensors check that the phone is close, upright and still.

เซนเซอร์ตรวจว่าโทรศัพท์แนบจอ ตั้งตรง และนิ่ง

Next, point at five dots: the center and the four corners.

ต่อไป ชี้ไปที่จุด 5 จุด คือกลางจอและ 4 มุม

The app learns how far the cursor should move when you turn.

แอปจะเรียนรู้ว่าเมื่อหมุนโทรศัพท์ เคอร์เซอร์ควรขยับไกลแค่ไหน

---

## 6. Features and Demo (ฟีเจอร์และสาธิต) · 1 min

You can type on the phone when you click a text box on the Mac.

คลิกช่องพิมพ์บน Mac แล้วพิมพ์จากโทรศัพท์ได้

You can drag with two fingers, and scroll smoothly.

ลากด้วยสองนิ้ว และเลื่อนหน้าจอได้ลื่น

There is a Click Practice game to test your accuracy.

มีเกม Click Practice ให้ทดสอบความแม่นยำ

Now let me show you a live demo.

ต่อไปขอสาธิตการใช้งานจริงครับ

*(Demo: connect → calibrate → point and click → type → Click Practice)*

*(สาธิต: เชื่อมต่อ → ปรับเทียบ → ชี้และคลิก → พิมพ์ → Click Practice)*

---

## 7. Technology (เทคโนโลยี) · 30 sec

The iPhone app is built with React Native and Expo.

แอป iPhone สร้างด้วย React Native และ Expo

The Mac app is built with Swift and SwiftUI.

แอป Mac สร้างด้วย Swift และ SwiftUI

The hardest part was making the cursor smooth over wireless.

ส่วนที่ยากที่สุดคือทำให้เคอร์เซอร์ลื่นเมื่อส่งแบบไร้สาย

---

## 8. Closing (ปิดท้าย) · 20 sec

AirMouse shows that the sensors in our phones can replace extra hardware.

AirMouse แสดงให้เห็นว่าเซนเซอร์ในโทรศัพท์ใช้แทนอุปกรณ์เสริมได้

Thank you. Any questions?

ขอบคุณครับ มีคำถามไหมครับ
