# AirMouse: Presentation Script (about 5 minutes)

Each part has the English script first, then the Thai translation.

---

## 1. Opening (30 s)

**EN**
Hello everyone. Our project is **AirMouse**. It turns your iPhone into an air mouse for your Mac, like the Magic Remote that comes with LG TVs. You just point the phone at the screen and the cursor follows your hand. No extra hardware is needed: only the sensors already inside the phone.

**TH**
สวัสดีครับ โปรเจกต์ของเราชื่อ **AirMouse** เปลี่ยน iPhone ให้เป็นเมาส์ลอยอากาศสำหรับ Mac เหมือนรีโมต Magic Remote ของทีวี LG แค่ชี้โทรศัพท์ไปที่จอ เคอร์เซอร์ก็ขยับตามมือ ไม่ต้องซื้ออุปกรณ์เพิ่ม ใช้แค่เซนเซอร์ที่มีอยู่ในโทรศัพท์

---

## 2. The problem (30 s)

**EN**
When you give a presentation, or watch a movie on a laptop connected to a TV, you have to walk back to the computer to click. A wireless presenter costs extra money and only does a few things. Almost everyone already carries a smartphone full of motion sensors, so we asked: why not use it?

**TH**
เวลานำเสนองาน หรือดูหนังจากโน้ตบุ๊กที่ต่อเข้าทีวี เราต้องเดินกลับไปที่เครื่องเพื่อคลิก รีโมตพรีเซนต์ก็ต้องซื้อเพิ่ม และทำได้แค่ไม่กี่อย่าง แต่เกือบทุกคนมีสมาร์ตโฟนที่เต็มไปด้วยเซนเซอร์ตรวจจับการเคลื่อนไหวอยู่แล้ว เราเลยคิดว่าทำไมไม่ใช้มันล่ะ

---

## 3. Sensors we use (1 min 15 s)

**EN**
AirMouse uses four sensors on the iPhone:
1. **Gyroscope.** This is the main one. It measures how fast the phone is turning, 100 times per second. Turning left or right moves the cursor sideways, and tilting up or down moves it up or down.
2. **Accelerometer.** It measures gravity, so we know whether the phone is held upright. We use it during calibration to check that the phone is placed flat against the screen.
3. **Proximity sensor.** This is the sensor next to the front camera that turns the screen off during calls. During calibration it tells us the phone is really touching the monitor, so calibration can't start by mistake.
4. **Touchscreen.** You hold the touch pad to point, tap to click, and use buttons for right click, scrolling and typing.

We also use the **camera** to scan a QR code for pairing, and **haptics** (vibration) to give feedback.

**TH**
AirMouse ใช้เซนเซอร์ของ iPhone 4 ตัว
1. **Gyroscope (ไจโรสโคป)** ตัวหลักของโปรเจกต์ วัดว่าโทรศัพท์หมุนเร็วแค่ไหน 100 ครั้งต่อวินาที หมุนซ้าย-ขวา เคอร์เซอร์ไปด้านข้าง เอียงขึ้น-ลง เคอร์เซอร์ขึ้นลง
2. **Accelerometer (ตัววัดความเร่ง)** วัดแรงโน้มถ่วง ทำให้รู้ว่าโทรศัพท์ตั้งตรงอยู่ไหม เราใช้ตอนคาลิเบต เพื่อตรวจว่าทาบโทรศัพท์แนบกับจอจริง
3. **Proximity sensor (เซนเซอร์วัดระยะใกล้)** ตัวที่อยู่ข้างกล้องหน้า ที่ทำให้จอดับตอนคุยโทรศัพท์ ตอนคาลิเบตใช้ตรวจว่าโทรศัพท์แตะจอจริง คาลิเบตจะได้ไม่เริ่มเองโดยไม่ตั้งใจ
4. **Touchscreen (หน้าจอสัมผัส)** กดค้างที่แผงสัมผัสเพื่อชี้ แตะเพื่อคลิก และมีปุ่มคลิกขวา เลื่อนหน้า และพิมพ์

นอกจากนี้ยังใช้ **กล้อง** สแกน QR เพื่อจับคู่ และใช้ **การสั่น (haptics)** เป็นสัญญาณตอบกลับ

---

## 4. How the data flows (1 min)

**EN**
Here is how the data travels:
1. The gyroscope gives a turning speed about 100 times a second.
2. We remove the sensor's small built-in error (we call it bias), then smooth the signal with a **One Euro filter**. It keeps the cursor steady when your hand shakes a little, but still reacts quickly to fast moves.
3. The speed is turned into a small distance in pixels, and the phone sends a short message such as "move 3 right, 1 up" to the Mac, over **Wi-Fi** or **Bluetooth**.
4. On the Mac, our native app receives each message and moves the real cursor, smoothed to the screen's refresh rate, so it doesn't stutter even when Wi-Fi delivers data in bursts.

Everything stays on your local network. Nothing goes to the internet.

**TH**
ข้อมูลเดินทางแบบนี้
1. Gyroscope ส่งค่าความเร็วการหมุนมาประมาณ 100 ครั้งต่อวินาที
2. เราลบค่าคลาดเคลื่อนเล็กๆ ที่เซนเซอร์มีอยู่ในตัว (เรียกว่า bias) แล้วทำให้สัญญาณนิ่งด้วย **One Euro filter** ช่วยให้เคอร์เซอร์นิ่งเวลามือสั่นเล็กน้อย แต่ยังตอบสนองเร็วเวลาขยับเร็ว
3. ค่าความเร็วถูกแปลงเป็นระยะทางเป็นพิกเซล แล้วโทรศัพท์ส่งข้อความสั้นๆ เช่น "ขยับขวา 3 ขึ้น 1" ไปที่ Mac ผ่าน **Wi-Fi** หรือ **Bluetooth**
4. แอป native ของเราบน Mac รับแต่ละข้อความแล้วขยับเคอร์เซอร์จริง โดยเกลี่ยให้ตรงกับรอบภาพของจอ เคอร์เซอร์จึงไม่สะดุด แม้ Wi-Fi จะส่งข้อมูลมาเป็นก้อนๆ

ข้อมูลทั้งหมดอยู่ในเครือข่ายภายในบ้าน ไม่ออกไปอินเทอร์เน็ต

---

## 5. Calibration (45 s)

**EN**
Every screen size and every sitting distance is different, so we built an Apple TV style calibration:
1. Hold the phone against the screen. The proximity sensor and the accelerometer confirm it's in place, and the gyroscope learns its resting error.
2. Point at five dots, one at a time: the centre and the four corners.
3. From the angles you turned, AirMouse works out how many pixels the cursor should move for each degree you turn, separately for the horizontal and vertical directions.
4. Finally you check the result: the dots light up when the cursor touches them.

**TH**
จอแต่ละขนาดและระยะนั่งของแต่ละคนไม่เท่ากัน เราจึงทำการคาลิเบตแบบ Apple TV
1. ทาบโทรศัพท์บนจอ เซนเซอร์วัดระยะใกล้กับ accelerometer ยืนยันว่าวางถูกที่ และ gyroscope เรียนรู้ค่าคลาดเคลื่อนตอนนิ่ง
2. ชี้ไปที่จุดทีละจุด 5 จุด คือกลางจอและ 4 มุม
3. AirMouse คำนวณจากมุมที่หมุนว่า หมุนไปหนึ่งองศาเคอร์เซอร์ควรขยับกี่พิกเซล แยกแนวนอนกับแนวตั้ง
4. สุดท้ายเช็กผล ชี้โดนจุดไหน จุดนั้นจะติดไฟ

---

## 6. Features and demo (45 s)

**EN**
Other features:
- Typing: when you click a text box on the Mac, a keyboard appears on the phone.
- Hold to Point mode, or Always On mode.
- Click Practice, a game to test your accuracy.
- Drag and drop with two fingers.
- A first-run guide with a permission checklist.

Now let me show you a live demo.
*(Demo: connect, calibrate, point and click, type into a text box, run Click Practice.)*

**TH**
ฟีเจอร์อื่นๆ
- พิมพ์ข้อความได้: คลิกช่องพิมพ์บน Mac แล้วคีย์บอร์ดจะเด้งขึ้นบนโทรศัพท์
- โหมด Hold to Point หรือ Always On
- Click Practice เกมฝึกความแม่นยำในการคลิก
- ลากวางด้วยสองนิ้ว
- หน้าแนะนำการใช้งานครั้งแรก พร้อมรายการตรวจสิทธิ์ที่ต้องอนุญาต

ต่อไปขอสาธิตการใช้งานจริงครับ
*(สาธิต: เชื่อมต่อ, คาลิเบต, ชี้และคลิก, พิมพ์ข้อความ, เล่น Click Practice)*

---

## 7. Tech stack and challenges (30 s)

**EN**
- **iPhone app:** React Native with Expo, plus small native Swift modules for Bonjour discovery, the proximity sensor and Bluetooth.
- **Mac app:** written in Swift and SwiftUI.

The hardest parts were making the cursor smooth over a wireless link, and making Bluetooth reliable. We solved them with sub-pixel movement, smoothing on the Mac, and our own Bluetooth sender.

**TH**
- **แอป iPhone:** React Native กับ Expo และมีโมดูล native ที่เขียนด้วย Swift เล็กๆ สำหรับค้นหาเครื่องด้วย Bonjour, เซนเซอร์วัดระยะใกล้ และ Bluetooth
- **แอป Mac:** เขียนด้วย Swift และ SwiftUI

ส่วนที่ยากที่สุดคือทำให้เคอร์เซอร์ลื่นเมื่อส่งข้อมูลแบบไร้สาย และทำให้ Bluetooth ส่งได้เสถียร เราแก้ด้วยการส่งระยะละเอียดกว่า 1 พิกเซล การเกลี่ยการขยับบน Mac และตัวส่ง Bluetooth ที่เขียนเอง

---

## 8. Closing (15 s)

**EN**
AirMouse shows that the sensors already in our pockets can replace extra hardware. Thank you. Any questions?

**TH**
AirMouse แสดงให้เห็นว่าเซนเซอร์ที่อยู่ในกระเป๋าเราอยู่แล้ว ใช้แทนอุปกรณ์เสริมได้ ขอบคุณครับ มีคำถามไหมครับ
