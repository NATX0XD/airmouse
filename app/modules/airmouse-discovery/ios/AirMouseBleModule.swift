import CoreBluetooth
import ExpoModulesCore
import Foundation

// Native BLE central for the AirMouse Mac (docs/spec-v3.md 2b, 6).
//
// Why native: ble-plx writes without response only once
// canSendWriteWithoutResponse is true and then waits for
// peripheralIsReady(toSendWriteWithoutResponse:), which can be missed, so its
// queue deadlocked; with response it managed only ~12 Hz. Here:
// - moves are summed into one native slot (no backlog, no JS round trip),
// - control messages keep a FIFO and their order relative to moves,
// - writes go without response while the peripheral can take them, and are
//   flushed again on peripheralIsReady or, as a safety net, a 10 ms poll,
// - every message ends with "\n" and is chunked to
//   maximumWriteValueLength(for: .withoutResponse); the Mac re-joins lines.
public class AirMouseBleModule: Module {
  private let core = BleCore()

  public func definition() -> ModuleDefinition {
    Name("AirMouseBle")
    Events("onBleStatus", "onBleMessage")

    OnCreate {
      self.core.emit = { [weak self] name, body in self?.sendEvent(name, body) }
    }

    // id = remembered peripheral UUID (may be stale), name = Mac name to find it by.
    Function("connect") { (id: String, name: String) in self.core.connect(id: id, name: name) }
    Function("disconnect") { self.core.disconnect() }
    Function("send") { (text: String) in self.core.send(text) }
    Function("sendMove") { (dx: Double, dy: Double) in self.core.sendMove(dx, dy) }
    Function("stats") { () -> [String: Any] in self.core.stats() }

    OnDestroy { self.core.disconnect() }
  }
}

private let serviceUUID = CBUUID(string: "7b0e0010-7d6b-4d9c-9a31-4a2d2f9e0101")
private let rxUUID = CBUUID(string: "7b0e0011-7d6b-4d9c-9a31-4a2d2f9e0101")
private let txUUID = CBUUID(string: "7b0e0012-7d6b-4d9c-9a31-4a2d2f9e0101")

// Same rule as bleFraming.ts nameKey: "AirMouse-Nattakit" ~ "Nattakit MacBook".
func airMouseNameKey(_ n: String) -> String {
  var s = n
  if s.hasPrefix("AirMouse-") { s.removeFirst("AirMouse-".count) }
  s = s.replacingOccurrences(of: "'s", with: "").replacingOccurrences(of: "’s", with: "")
  let first = s.split(whereSeparator: { $0 == " " }).first.map(String.init) ?? ""
  return String(first.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" })
}

final class BleCore: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  var emit: ((String, [String: Any]) -> Void)?

  private let queue = DispatchQueue(label: "airmouse.ble", qos: .userInteractive)
  // Created on first connect: creating it shows the Bluetooth permission
  // prompt, which belongs to onboarding, not app launch.
  private var centralManager: CBCentralManager?
  private var central: CBCentralManager {
    if let c = centralManager { return c }
    let c = CBCentralManager(delegate: self, queue: queue)
    centralManager = c
    return c
  }
  private var peripheral: CBPeripheral?
  private var rx: CBCharacteristic?
  private var wanted: (id: String, name: String)?
  private var open = false
  private var scanning = false
  private var seen: [UUID: CBPeripheral] = [:]
  private var attempt = 0

  // Outgoing: control FIFO (already framed) + one summed move slot after it.
  private var fifo: [Data] = []
  private var moveX = 0.0
  private var moveY = 0.0
  private var hasMove = false
  private var chunk: Data? // rest of a message that did not fit one write
  private var poll: DispatchSourceTimer?

  // Counters (Diagnostics / bench).
  private var writes = 0
  private var moves = 0
  private var merged = 0
  private var waits = 0
  private var lastError = ""

  // MARK: JS API (any thread)

  func connect(id: String, name: String) {
    queue.async {
      self.wanted = (id, name)
      self.attempt += 1
      self.status("connecting")
      if self.central.state == .poweredOn { self.start() }
    }
  }

  func disconnect() {
    queue.async {
      self.wanted = nil
      self.attempt += 1
      self.stopScan()
      if let p = self.peripheral { self.centralManager?.cancelPeripheralConnection(p) }
      self.reset()
    }
  }

  func send(_ text: String) {
    queue.async {
      guard self.open else { return }
      self.materializeMove() // a move queued before this message goes first
      self.fifo.append(Data((text + "\n").utf8))
      self.pump()
    }
  }

  func sendMove(_ dx: Double, _ dy: Double) {
    queue.async {
      guard self.open else { return }
      if self.hasMove { self.merged += 1 }
      self.moveX += dx
      self.moveY += dy
      self.hasMove = true
      self.pump()
    }
  }

  func stats() -> [String: Any] {
    queue.sync {
      [
        "open": open, "writes": writes, "moves": moves, "merged": merged, "waits": waits,
        "queued": fifo.count + (hasMove ? 1 : 0), "maxWrite": maxWrite(), "lastError": lastError,
      ]
    }
  }

  // MARK: sending (queue)

  private func maxWrite() -> Int {
    peripheral?.maximumWriteValueLength(for: .withoutResponse) ?? 20
  }

  private func materializeMove() {
    guard hasMove else { return }
    let r = { (v: Double) -> Double in (v * 100).rounded() / 100 }
    let dx = r(moveX), dy = r(moveY)
    hasMove = false
    moveX = 0
    moveY = 0
    fifo.append(Data("{\"t\":\"move\",\"dx\":\(fmt(dx)),\"dy\":\(fmt(dy))}\n".utf8))
    moves += 1
  }

  private func fmt(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
  }

  private func pump() {
    guard open, let p = peripheral, let rx else { return }
    while true {
      if chunk == nil {
        if fifo.isEmpty { materializeMove() }
        if fifo.isEmpty { break }
        chunk = fifo.removeFirst()
      }
      guard p.canSendWriteWithoutResponse else {
        waits += 1
        startPoll()
        return
      }
      let limit = max(20, maxWrite())
      let data = chunk!
      let part = data.prefix(limit)
      p.writeValue(Data(part), for: rx, type: .withoutResponse)
      writes += 1
      chunk = data.count > limit ? Data(data.dropFirst(limit)) : nil
    }
    stopPoll()
  }

  // Safety net in case peripheralIsReady is not delivered.
  private func startPoll() {
    guard poll == nil else { return }
    let t = DispatchSource.makeTimerSource(queue: queue)
    t.schedule(deadline: .now() + .milliseconds(10), repeating: .milliseconds(10))
    t.setEventHandler { [weak self] in self?.pump() }
    t.resume()
    poll = t
  }

  private func stopPoll() {
    poll?.cancel()
    poll = nil
  }

  private func reset() {
    open = false
    rx = nil
    peripheral = nil
    fifo.removeAll()
    chunk = nil
    hasMove = false
    moveX = 0
    moveY = 0
    stopPoll()
  }

  private func status(_ s: String, _ detail: String? = nil, id: String? = nil) {
    var body: [String: Any] = ["status": s]
    if let detail { body["detail"] = detail }
    if let id { body["id"] = id }
    emit?("onBleStatus", body)
  }

  // MARK: connecting (queue)

  private func start() {
    guard let w = wanted, peripheral == nil else { return }
    // 1. Already connected to the system (or to ble-plx): reuse.
    if let p = central.retrieveConnectedPeripherals(withServices: [serviceUUID]).first { return link(p) }
    // 2. Remembered id.
    if let u = UUID(uuidString: w.id), let p = central.retrievePeripherals(withIdentifiers: [u]).first {
      link(p)
      let a = attempt
      queue.asyncAfter(deadline: .now() + 6) { [weak self] in
        guard let self, self.attempt == a, !self.open, self.peripheral === p else { return }
        self.central.cancelPeripheralConnection(p) // stale id (Mac rotated its address): scan instead
        self.peripheral = nil
        self.scan()
      }
      return
    }
    scan()
  }

  private func scan() {
    guard wanted != nil, !scanning else { return }
    scanning = true
    seen.removeAll()
    central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    let a = attempt
    queue.asyncAfter(deadline: .now() + 5) { [weak self] in
      guard let self, self.attempt == a, self.scanning else { return }
      self.stopScan()
      if self.seen.count == 1, let p = self.seen.values.first { return self.link(p) } // the only Mac around
      self.status("error", self.seen.isEmpty ? "No Mac found over Bluetooth." : "Several Macs found; pick one in Connect.")
    }
  }

  private func stopScan() {
    if scanning { centralManager?.stopScan() }
    scanning = false
  }

  private func link(_ p: CBPeripheral) {
    stopScan()
    peripheral = p
    p.delegate = self
    central.connect(p, options: nil)
  }

  func centralManagerDidUpdateState(_ c: CBCentralManager) {
    switch c.state {
    case .poweredOn: start()
    case .poweredOff: reset(); status("error", "Turn on Bluetooth to connect.")
    case .unauthorized: status("error", "Allow Bluetooth for AirMouse in Settings.")
    default: break
    }
  }

  func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
    guard let w = wanted, scanning else { return }
    seen[p.identifier] = p
    let names = [ad[CBAdvertisementDataLocalNameKey] as? String, p.name].compactMap { $0 }
    let want = airMouseNameKey(w.name)
    if !want.isEmpty, names.contains(where: { $0 == w.name || airMouseNameKey($0) == want }) { link(p) }
  }

  func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
    guard p === peripheral else { return }
    p.discoverServices([serviceUUID])
  }

  func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
    guard p === peripheral else { return }
    lastError = error?.localizedDescription ?? "connect failed"
    reset()
    status("closed", lastError)
  }

  func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
    guard p === peripheral else { return }
    if let error { lastError = error.localizedDescription }
    reset()
    status("closed", error?.localizedDescription)
  }

  func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
    guard let s = p.services?.first(where: { $0.uuid == serviceUUID }) else {
      lastError = "AirMouse service missing"
      return central.cancelPeripheralConnection(p)
    }
    p.discoverCharacteristics([rxUUID, txUUID], for: s)
  }

  func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
    let chars = s.characteristics ?? []
    rx = chars.first { $0.uuid == rxUUID }
    guard rx != nil, let tx = chars.first(where: { $0.uuid == txUUID }) else {
      lastError = "AirMouse characteristics missing"
      return central.cancelPeripheralConnection(p)
    }
    p.setNotifyValue(true, for: tx)
  }

  func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
    guard ch.uuid == txUUID else { return }
    if let error {
      lastError = error.localizedDescription
      return central.cancelPeripheralConnection(p)
    }
    open = true
    status("open", nil, id: p.identifier.uuidString)
    pump()
  }

  func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
    guard ch.uuid == txUUID, let v = ch.value, let text = String(data: v, encoding: .utf8) else { return }
    emit?("onBleMessage", ["text": text])
  }

  func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) {
    pump()
  }
}
