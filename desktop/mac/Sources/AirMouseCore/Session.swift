import Foundation
import CoreGraphics

/// Where pointer actions go. The app uses a CGEvent implementation; tests and
/// `--selftest` use `LogOutput`, so nothing here ever touches the real cursor.
public protocol PointerOutput: AnyObject {
    /// Relative move. `dragging` is the held button (moves while a button is down are drags).
    func move(dx: Double, dy: Double, dragging: MouseButton?)
    func button(_ button: MouseButton, down: Bool)
    /// Line-based notches, positive = scroll down.
    func scroll(lines: Int)
    func key(_ key: ArrowKey)
    /// Types unicode text into the focused app.
    func type(_ text: String)
    /// Absolute warp in global display points (top-left origin of the main display).
    func warp(to point: CGPoint)
}

/// One connected phone. Turns decoded messages into pointer output and replies.
/// Not thread-safe: drive it from one queue (the app uses the main queue).
public final class ReceiverSession {
    public private(set) var device: PhoneDevice?
    public private(set) var heldButtons: [MouseButton] = []
    public private(set) var messageCount = 0
    /// Calibration v3: after `placed` the phone is lifted off the glass; its moves are dropped until
    /// `pointed center` (cursor re-centred, then it follows during the corners), or `verify` / `done` / `cancel` / `start`.
    public private(set) var movesBlocked = false
    /// Live counters for About > Diagnostics.
    public private(set) var stats = MessageStats()

    public var onHello: ((PhoneDevice) -> Void)?
    public var onCalib: ((CalibEvent) -> Void)?
    public var onPractice: ((PracticeCommand) -> Void)?

    private let output: PointerOutput
    private let screen: () -> ScreenInfo
    private let clock: () -> TimeInterval

    public init(output: PointerOutput, screen: @escaping () -> ScreenInfo,
                clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.output = output
        self.screen = screen
        self.clock = clock
    }

    /// Handles one raw text frame. Bad JSON / unknown types are ignored (no reply).
    @discardableResult
    public func handle(text: String) -> [OutboundMessage] {
        messageCount += 1
        let msg = ProtocolCodec.decode(text)
        stats.record(MessageStats.kind(of: msg), at: clock())
        guard let msg else { return [] }
        return handle(msg)
    }

    @discardableResult
    public func handle(_ msg: InboundMessage) -> [OutboundMessage] {
        switch msg {
        case .hello(_, let device):
            self.device = device
            onHello?(device)
            return [.screen(screen())]
        case .move(let dx, let dy):
            guard !movesBlocked else { break }
            output.move(dx: dx, dy: dy, dragging: dragButton)
        case .button(let b, let down):
            if down {
                guard !heldButtons.contains(b) else { break }
                heldButtons.append(b)
                output.button(b, down: true)
            } else {
                guard let i = heldButtons.firstIndex(of: b) else { break }
                heldButtons.remove(at: i)
                output.button(b, down: false)
            }
        case .scroll(let dy):
            output.scroll(lines: dy)
        case .key(let k):
            output.key(k)
        case .center:
            output.warp(to: screen().center)
        case .calib(let event):
            switch event {
            // The outline is centred on the main display, so its centre = display centre.
            case .placed: movesBlocked = true; output.warp(to: screen().center)
            case .done: movesBlocked = false; output.warp(to: screen().center)
            // Centre target (first entry and Redo): cursor back to the centre, phone moves blocked until it is tapped.
            case .point(.center): movesBlocked = true; output.warp(to: screen().center)
            case .pointed(.center): movesBlocked = false; output.warp(to: screen().center)
            case .start, .verify, .cancel: movesBlocked = false
            default: break
            }
            onCalib?(event)
        case .text(let s):
            output.type(s)
        case .practice(let c):
            onPractice?(c)
        }
        return []
    }

    /// Phone went away: never leave a button stuck down.
    public func disconnect() {
        movesBlocked = false
        for b in heldButtons.reversed() { output.button(b, down: false) }
        heldButtons.removeAll()
    }

    /// The button a move would currently drag with (nil = plain move).
    public var dragButton: MouseButton? {
        heldButtons.contains(.left) ? .left : heldButtons.first
    }
}

/// Per-peer message counters (by type), last move time and a rolling msg/s. Cheap: O(1) per message.
public struct MessageStats: Equatable, Sendable {
    /// Display order. "other" = unknown type or malformed JSON (ignored by the session).
    public static let kinds = ["move", "button", "scroll", "key", "text", "center", "calib", "practice", "hello", "other"]

    public private(set) var counts: [String: Int] = [:]
    public private(set) var total = 0
    public private(set) var lastMoveAt: TimeInterval?
    public private(set) var lastMessageAt: TimeInterval?
    private var windowStart: TimeInterval?
    private var windowCount = 0
    private var windowRate = 0.0
    /// `move` inter-arrival gaps (arrival time, gap in s) over the last 2 s.
    private var moveArrivals: [Double] = []
    private var moveGaps: [Double] = []
    public static let jitterWindow = 2.0
    /// Times of `move` gaps of 50 ms ..< 1 s (hitches; longer = the person paused) in the last minute.
    private var hitches: [Double] = []

    public init() {}

    public static func kind(of msg: InboundMessage?) -> String {
        switch msg {
        case .hello?: "hello"
        case .move?: "move"
        case .button?: "button"
        case .scroll?: "scroll"
        case .key?: "key"
        case .center?: "center"
        case .calib?: "calib"
        case .text?: "text"
        case .practice?: "practice"
        case nil: "other"
        }
    }

    public mutating func record(_ kind: String, at now: TimeInterval) {
        counts[kind, default: 0] += 1
        total += 1
        lastMessageAt = now
        if kind == "move" {
            if let prev = lastMoveAt {
                moveArrivals.append(now); moveGaps.append(max(0, now - prev))
                if (0.05..<1).contains(now - prev) { hitches.append(now) }
                if let i = hitches.firstIndex(where: { $0 >= now - 60 }), i > 0 { hitches.removeFirst(i) }
            }
            lastMoveAt = now
            let cut = now - Self.jitterWindow
            if let i = moveArrivals.firstIndex(where: { $0 >= cut }), i > 0 {
                moveArrivals.removeFirst(i); moveGaps.removeFirst(i)
            } else if moveArrivals.last.map({ $0 < cut }) ?? false {
                moveArrivals.removeAll(); moveGaps.removeAll()
            }
        }
        guard let start = windowStart else { windowStart = now; windowCount = 1; return }
        windowCount += 1
        if now - start >= 1 {
            windowRate = Double(windowCount) / (now - start)
            windowStart = now; windowCount = 0
        }
    }

    public func count(_ kind: String) -> Int { counts[kind] ?? 0 }

    /// `move` gaps of 50 ms to 1 s in the last minute (Wi-Fi / AWDL hitches).
    public func longGaps(now: TimeInterval) -> Int { hitches.filter { $0 >= now - 60 }.count }

    /// `move` inter-arrival times over the last 2 s, in ms (nil = fewer than 2 moves in the window).
    public func moveInterval(now: TimeInterval) -> (meanMs: Double, maxMs: Double)? {
        let cut = now - Self.jitterWindow
        let gaps = zip(moveArrivals, moveGaps).filter { $0.0 >= cut }.map(\.1)
        guard !gaps.isEmpty else { return nil }
        return (gaps.reduce(0, +) / Double(gaps.count) * 1000, (gaps.max() ?? 0) * 1000)
    }

    /// Messages per second over the last ~1 s window; 0 once the peer has been quiet for 2 s.
    public func rate(now: TimeInterval) -> Double {
        guard let last = lastMessageAt, now - last <= 2 else { return 0 }
        return windowRate
    }

    /// "never", "0.2 s ago", "14 s ago", "3 min ago".
    public static func ago(_ t: TimeInterval?, now: TimeInterval) -> String {
        guard let t else { return "never" }
        let d = max(0, now - t)
        if d < 10 { return String(format: "%.1f s ago", d) }
        if d < 60 { return "\(Int(d)) s ago" }
        return "\(Int(d / 60)) min ago"
    }
}

/// One row of About > Diagnostics.
public struct PeerDiagnostics: Identifiable, Equatable, Sendable {
    public enum Transport: String, Sendable { case wifi = "Wi-Fi", bluetooth = "Bluetooth" }
    public var id: String
    public var transport: Transport
    public var name: String
    public var stats: MessageStats
    public var dragging: MouseButton?
    /// BLE only: GATT writes per second (several moves may share one write).
    public var writeHz: Double?

    public init(id: String, transport: Transport, name: String, stats: MessageStats, dragging: MouseButton?, writeHz: Double? = nil) {
        self.id = id; self.transport = transport; self.name = name; self.stats = stats; self.dragging = dragging; self.writeHz = writeHz
    }

    public init(id: String, transport: Transport, session: ReceiverSession) {
        self.init(id: id, transport: transport, name: session.device?.name ?? "iPhone",
                  stats: session.stats, dragging: session.dragButton)
    }
}

/// Fake output that records (and optionally prints) one line per action.
public final class LogOutput: PointerOutput {
    public private(set) var lines: [String] = []
    public var sink: ((String) -> Void)?

    public init(sink: ((String) -> Void)? = nil) { self.sink = sink }

    private func log(_ s: String) { lines.append(s); sink?(s) }
    private func f(_ v: Double) -> String { String(format: "%+.1f", v) }

    public func move(dx: Double, dy: Double, dragging: MouseButton?) {
        if let b = dragging { log("drag \(b.rawValue) \(f(dx)) \(f(dy))") } else { log("move \(f(dx)) \(f(dy))") }
    }
    public func button(_ button: MouseButton, down: Bool) { log("button \(button.rawValue) \(down ? "down" : "up")") }
    public func scroll(lines: Int) { log("scroll \(lines > 0 ? "+" : "")\(lines)") }
    public func key(_ key: ArrowKey) { log("key \(key.rawValue)") }
    public func type(_ text: String) { log("type \(text)") }
    public func warp(to point: CGPoint) { log("warp \(Int(point.x.rounded())),\(Int(point.y.rounded()))") }
}
