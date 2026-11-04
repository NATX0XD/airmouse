@preconcurrency import CoreBluetooth
import Foundation
import OSLog
import AirMouseCore

/// `log stream --predicate 'subsystem == "com.nattakit.airmouse.mac" AND category == "ble"'`
private let bleLog = Logger(subsystem: "com.nattakit.airmouse.mac", category: "ble")

/// BLE peripheral (spec 2b). Raw bytes go to `BLEHub`, which owns protocol handling.
/// Created only by the GUI app (creating CBPeripheralManager may show the Bluetooth prompt).
@MainActor
final class BluetoothPeripheral: NSObject {
    enum State: Equatable { case off(String), advertising, connected }

    var onState: ((State) -> Void)?
    /// (central id, phone name or nil) when a phone appears / says hello / goes away.
    var onPeerChange: (() -> Void)?
    var onMessage: (() -> Void)?

    private(set) var state: State = .off("Starting…") { didSet { if state != oldValue { onState?(state) } } }

    let hub: BLEHub<UUID>
    private let localName: String
    private let screen: () -> ScreenInfo
    private var manager: CBPeripheralManager!
    private var tx: CBMutableCharacteristic?
    private var subscribers: [UUID: CBCentral] = [:]
    private var pending: [(Data, UUID?)] = []
    private var added = false
    private var moveCount = 0
    private var lastMoveLog = Date.distantPast

    init(localName: String, screen: @escaping () -> ScreenInfo, hub: BLEHub<UUID>) {
        self.localName = localName
        self.screen = screen
        self.hub = hub
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    var peers: [UUID] { Array(hub.sessions.keys) }

    func broadcast(_ msg: OutboundMessage) {
        let data = BLEHub<UUID>.encode(msg)
        for id in subscribers.keys { notify(data, to: id) }
    }

    func stop() {
        manager.stopAdvertising()
        manager.removeAllServices()
    }

    // MARK: private

    private func setUp() {
        guard !added else { startAdvertising(); return }
        let rx = CBMutableCharacteristic(type: CBUUID(string: BLESpec.rx),
                                         properties: [.write, .writeWithoutResponse], value: nil, permissions: [.writeable])
        let tx = CBMutableCharacteristic(type: CBUUID(string: BLESpec.tx), properties: [.notify], value: nil, permissions: [.readable])
        let service = CBMutableService(type: CBUUID(string: BLESpec.service), primary: true)
        service.characteristics = [rx, tx]
        self.tx = tx
        manager.add(service)
    }

    private func startAdvertising() {
        guard !manager.isAdvertising else { return }
        manager.startAdvertising([CBAdvertisementDataLocalNameKey: localName,
                                  CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: BLESpec.service)]])
    }

    private func notify(_ data: Data, to id: UUID?) {
        guard let tx else { return }
        let targets = id.flatMap { subscribers[$0] }.map { [$0] }
        if !manager.updateValue(data, for: tx, onSubscribedCentrals: targets) {
            pending.append((data, id)) // queue full: resend in peripheralManagerIsReady
        }
    }

    private func refreshState() {
        guard manager.state == .poweredOn else { return }
        state = hub.sessions.isEmpty ? .advertising : .connected
    }

    fileprivate func handle(_ event: Event) {
        switch event {
        case .power(let s):
            bleLog.info("power state \(s.rawValue, privacy: .public)")
            switch s {
            case .poweredOn: setUp(); refreshState()
            case .poweredOff: state = .off("Bluetooth is off")
            case .unauthorized: state = .off("Not allowed in Privacy settings")
            case .unsupported: state = .off("Not supported on this Mac")
            default: state = .off("Unavailable")
            }
            if s != .poweredOn {
                for id in hub.sessions.keys { hub.disconnected(id) }
                subscribers.removeAll(); onPeerChange?()
            }
        case .added(let error):
            if let error { bleLog.error("add service failed: \(error.localizedDescription, privacy: .public)"); state = .off("Couldn’t start: \(error.localizedDescription)"); return }
            bleLog.info("service added")
            added = true
            startAdvertising()
        case .advertising(let error):
            if let error { bleLog.error("advertise failed: \(error.localizedDescription, privacy: .public)"); state = .off("Couldn’t advertise: \(error.localizedDescription)") } else { bleLog.info("advertising as \(self.localName, privacy: .public)"); refreshState() }
        case .subscribed(let central):
            bleLog.info("subscribed \(central.identifier.uuidString, privacy: .public) maxUpdate=\(central.maximumUpdateValueLength)")
            subscribers[central.identifier] = central
            // ~15 ms connection interval instead of the default 30-50 ms (smoother moves).
            manager.setDesiredConnectionLatency(.low, for: central)
            for d in hub.subscribed(central.identifier, screen: screen()) { notify(d, to: central.identifier) }
            refreshState(); onPeerChange?()
        case .unsubscribed(let id):
            bleLog.info("unsubscribed \(id.uuidString, privacy: .public)")
            subscribers[id] = nil
            hub.disconnected(id)
            refreshState(); onPeerChange?()
        case .writes(let items):
            for (id, value) in items {
                logWrite(value, from: id)
                let isNew = hub.sessions[id] == nil
                let replies = hub.received(value, from: id)
                onMessage?()
                for r in replies { notify(r, to: subscribers[id] == nil ? nil : id) }
                if isNew || hub.sessions[id]?.device != nil { onPeerChange?() }
            }
            refreshState()
        case .ready:
            let queued = pending; pending.removeAll()
            for (d, id) in queued { notify(d, to: id) }
        }
    }

    /// Non-move writes in full, moves as a count every 2 s (they arrive at ~60 Hz).
    private func logWrite(_ value: Data, from id: UUID) {
        let text = String(decoding: value.prefix(160), as: UTF8.self)
        if text.hasPrefix("{\"t\":\"move\"") {
            moveCount += 1
            if Date().timeIntervalSince(lastMoveLog) > 2 {
                bleLog.info("moves \(self.moveCount) (last \(text, privacy: .public))")
                lastMoveLog = Date()
            }
        } else {
            bleLog.info("write \(value.count)B from \(id.uuidString.prefix(8), privacy: .public): \(text, privacy: .public)")
        }
    }

    fileprivate enum Event {
        case power(CBManagerState)
        case added(Error?)
        case advertising(Error?)
        case subscribed(CBCentral)
        case unsubscribed(UUID)
        case writes([(UUID, Data)])
        case ready
    }
}

extension BluetoothPeripheral: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let s = peripheral.state
        MainActor.assumeIsolated { handle(.power(s)) }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        MainActor.assumeIsolated { handle(.added(error)) }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        MainActor.assumeIsolated { handle(.advertising(error)) }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        MainActor.assumeIsolated { handle(.subscribed(central)) }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        let id = central.identifier
        MainActor.assumeIsolated { handle(.unsubscribed(id)) }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        let rx = CBUUID(string: BLESpec.rx)
        let items = BLEHub<UUID>.assemble(requests.compactMap { r -> (UUID, Int, Data)? in
            guard r.characteristic.uuid == rx, let v = r.value else { return nil }
            return (r.central.identifier, r.offset, v)
        })
        // Writes with response need exactly one reply for the batch (first request).
        if let first = requests.first { peripheral.respond(to: first, withResult: .success) }
        MainActor.assumeIsolated { handle(.writes(items)) }
    }

    nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated { handle(.ready) }
    }
}
