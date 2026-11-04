import AppKit
import QuartzCore
import ApplicationServices
import CoreGraphics
import SystemConfiguration
import AirMouseCore

enum MacInfo {
    /// "Nattakit's MacBook Pro". SystemConfiguration is instant; Host can block on DNS.
    static var computerName: String {
        if let n = SCDynamicStoreCopyComputerName(nil, nil) as String?, !n.isEmpty { return n }
        return Host.current().localizedName ?? "Mac"
    }

    static let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
}

enum Displays {
    static func mainScreenInfo(name: String) -> ScreenInfo {
        let id = CGMainDisplayID()
        let bounds = CGDisplayBounds(id)
        var scale = 1.0
        if let mode = CGDisplayCopyDisplayMode(id), mode.width > 0 {
            scale = Double(mode.pixelWidth) / Double(mode.width)
        }
        let mm = CGDisplayScreenSize(id)
        return ScreenInfo(w: Int(bounds.width), h: Int(bounds.height), scale: scale,
                          wMm: Double(mm.width), hMm: Double(mm.height), name: name)
    }

    static func allBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [CGDisplayBounds(CGMainDisplayID())] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [CGDisplayBounds(CGMainDisplayID())] }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }
}

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (adds AirMouse to the list) and opens the settings pane.
    static func requestAndOpenSettings() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// System-wide focused UI element via the AX API (needs Accessibility). Main thread only.
@MainActor
enum FocusedElement {
    private static let systemWide: AXUIElement = {
        let e = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(e, 0.15) // never stall the main thread on a hung app
        return e
    }()

    static func isEditable() -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return false }
        let el = ref as! AXUIElement
        AXUIElementSetMessagingTimeout(el, 0.15)
        var roleRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String
        if let role, FocusEditability.textRoles.contains(role) { return true }
        var ancestor: CFTypeRef?
        let hasAncestor = AXUIElementCopyAttributeValue(el, "AXEditableAncestor" as CFString, &ancestor) == .success && ancestor != nil
        var settable = DarwinBoolean(false)
        let valueSettable = AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
        return FocusEditability.isEditable(role: role, hasEditableAncestor: hasAncestor, valueSettable: valueSettable)
    }
}

/// Display-synced frame callback (NSScreen.displayLink, follows the screen's refresh: 120 Hz on ProMotion).
@MainActor
final class FrameTicker: NSObject {
    private var link: CADisplayLink?
    private let onFrame: (Double) -> Void

    init(onFrame: @escaping (Double) -> Void) { self.onFrame = onFrame }

    var running: Bool { link.map { !$0.isPaused } ?? false }

    func start() {
        if link == nil {
            guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
            let l = screen.displayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        link?.isPaused = false
    }

    func pause() { link?.isPaused = true }

    /// Main display changed: rebuild on the next start.
    func invalidate() { link?.invalidate(); link = nil }

    @objc private func tick(_ l: CADisplayLink) {
        let dt = min(1.0 / 24, max(1.0 / 240, l.targetTimestamp - l.timestamp))
        onFrame(dt)
    }
}

/// Real cursor output through CGEvent. Only constructed by the GUI app, never by tests/selftest.
/// Moves go through `MotionPacer` and are posted once per display frame at a sub-pixel position.
@MainActor
final class CGEventOutput: @preconcurrency PointerOutput {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var clicks = ClickCounter(interval: NSEvent.doubleClickInterval)
    private var clickState: [MouseButton: Int] = [:]
    private var pacer = MotionPacer()
    private var scrollPacer = ScrollPacer()
    /// Integer line-delta carry for the legacy DeltaAxis fields.
    private var scrollCarry = CGVector.zero
    private var held: [MouseButton] = []
    /// Our sub-pixel cursor position and the last point we posted (to notice trackpad / other moves).
    private var tracked: CGPoint?
    private var lastPosted: CGPoint?
    private var meter = FrameRateMeter()
    private var ticker: FrameTicker?

    private var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    /// Pacer frames per second (0 while idle). Diagnostics only.
    var pacerFPS: Double { meter.rate(now: ProcessInfo.processInfo.systemUptime) }

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.ticker?.invalidate() }
        }
    }

    /// Where the next paced move starts: our tracked sub-pixel point, unless something else moved the cursor.
    private var origin: CGPoint {
        let real = location
        if let tracked, let lastPosted, hypot(real.x - lastPosted.x, real.y - lastPosted.y) < 1.5 { return tracked }
        return real
    }

    func move(dx: Double, dy: Double, dragging: MouseButton?) {
        pacer.add(dx: dx, dy: dy)
        startTicker()
    }

    private func startTicker() {
        if ticker == nil { ticker = FrameTicker { [weak self] dt in self?.frame(dt: dt) } }
        if ticker?.running != true { ticker?.start() }
    }

    private func frame(dt: Double) {
        meter.tick(at: ProcessInfo.processInfo.systemUptime)
        for f in scrollPacer.step(dt: dt) { postScroll(f) }
        let d = pacer.step(dt: dt)
        if d == nil, scrollPacer.isIdle { ticker?.pause() }
        if let d { postMove(d) }
    }

    private func postMove(_ d: CGVector) {
        let from = origin
        let to = PointerMath.clamp(CGPoint(x: from.x + d.dx, y: from.y + d.dy), to: Displays.allBounds())
        tracked = to
        guard abs(to.x - from.x) > 1e-6 || abs(to.y - from.y) > 1e-6 else { return }
        let drag = held.contains(.left) ? MouseButton.left : held.first
        let type: CGEventType
        let button: CGMouseButton
        switch drag {
        case .left?: type = .leftMouseDragged; button = .left
        case .right?: type = .rightMouseDragged; button = .right
        case nil: type = .mouseMoved; button = .left
        }
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: to, mouseButton: button) else { return }
        e.setIntegerValueField(.mouseEventDeltaX, value: Int64((to.x - from.x).rounded()))
        e.setIntegerValueField(.mouseEventDeltaY, value: Int64((to.y - from.y).rounded()))
        e.setDoubleValueField(.mouseEventDeltaX, value: to.x - from.x)
        e.setDoubleValueField(.mouseEventDeltaY, value: to.y - from.y)
        if let b = drag { e.setIntegerValueField(.mouseEventClickState, value: Int64(clickState[b] ?? 1)) }
        e.post(tap: .cghidEventTap)
        lastPosted = location
    }

    func button(_ b: MouseButton, down: Bool) {
        let p = origin
        if down { if !held.contains(b) { held.append(b) } } else { held.removeAll { $0 == b } }
        let type: CGEventType = switch (b, down) {
        case (.left, true): .leftMouseDown
        case (.left, false): .leftMouseUp
        case (.right, true): .rightMouseDown
        case (.right, false): .rightMouseUp
        }
        if down { clickState[b] = clicks.press(b, at: p, time: ProcessInfo.processInfo.systemUptime) }
        guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p,
                              mouseButton: b == .left ? .left : .right) else { return }
        e.setIntegerValueField(.mouseEventClickState, value: Int64(clickState[b] ?? 1))
        e.post(tap: .cghidEventTap)
    }

    func scroll(lines: Int) {
        scrollPacer.addLegacy(lines: lines)
        startTicker()
    }

    func smoothScroll(dx: Double, dy: Double, phase: ScrollPhase) {
        scrollPacer.add(dx: dx, dy: dy, phase: phase)
        startTicker()
    }

    /// Continuous pixel scroll with fractional point deltas and gesture / momentum phases (Safari etc. then
    /// scroll natively with rubber-banding). Phone: positive dy = scroll down; CG wheel1 positive = up.
    private func postScroll(_ f: ScrollFrame) {
        let wy = -f.dy, wx = -f.dx
        guard let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                              wheel1: Int32(wy.rounded()), wheel2: Int32(wx.rounded()), wheel3: 0) else { return }
        func field(_ raw: UInt32) -> CGEventField? { CGEventField(rawValue: raw) }
        if let c = field(88) { e.setIntegerValueField(c, value: 1) }                          // IsContinuous
        if let p = field(96) { e.setDoubleValueField(p, value: wy) }                          // PointDeltaAxis1
        if let p = field(97) { e.setDoubleValueField(p, value: wx) }                          // PointDeltaAxis2
        if let p = field(93) { e.setDoubleValueField(p, value: wy) }                          // FixedPtDeltaAxis1
        if let p = field(94) { e.setDoubleValueField(p, value: wx) }                          // FixedPtDeltaAxis2
        // Line deltas: integer, carried so slow scrolls still add up.
        scrollCarry.dx += wx / 10; scrollCarry.dy += wy / 10
        let lx = scrollCarry.dx.rounded(.towardZero), ly = scrollCarry.dy.rounded(.towardZero)
        scrollCarry.dx -= lx; scrollCarry.dy -= ly
        if let l = field(11) { e.setIntegerValueField(l, value: Int64(ly)) }                  // DeltaAxis1
        if let l = field(12) { e.setIntegerValueField(l, value: Int64(lx)) }                  // DeltaAxis2
        if let p = field(99) { e.setIntegerValueField(p, value: f.scrollPhase) }              // ScrollPhase
        if let p = field(123) { e.setIntegerValueField(p, value: f.momentumPhase) }           // MomentumPhase
        if f.scrollPhase == ScrollEventPhase.began || f.momentumPhase == ScrollEventPhase.momentumBegin { scrollCarry = .zero }
        e.post(tap: .cghidEventTap)
    }

    func key(_ k: ArrowKey) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: k.virtualKey, keyDown: down) else { continue }
            if k.isArrow { e.flags = [.maskNumericPad, .maskSecondaryFn] } // what a real arrow key carries
            e.post(tap: .cghidEventTap)
        }
    }

    /// Unicode typing: one key down + up per chunk of <= 20 UTF-16 units (no surrogate pair split).
    func type(_ text: String) {
        for var units in TextChunks.split(text) {
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                e.post(tap: .cghidEventTap)
            }
        }
    }

    func warp(to point: CGPoint) {
        pacer.reset()
        let p = PointerMath.clamp(point, to: Displays.allBounds())
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
        tracked = p
        lastPosted = location
    }
}
