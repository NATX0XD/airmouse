import Foundation

// Protocol v3 (docs/spec-v3.md section 3). JSON over WebSocket, one object per text frame.
// Decoding is deliberately tolerant: unknown `t` values, unknown fields and malformed
// JSON all decode to `nil` (= ignore) instead of throwing.

public enum MouseButton: String, Sendable, CaseIterable { case left, right }

/// `{t:'key', k}` values. (Name kept from v3.0, when only the arrows existed.)
public enum ArrowKey: String, Sendable, CaseIterable {
    case left, right, up, down, backspace, enter, tab, escape, space
    /// macOS virtual key codes (Carbon kVK_*).
    public var virtualKey: UInt16 {
        switch self {
        case .left: 123
        case .right: 124
        case .up: 126
        case .down: 125
        case .backspace: 51
        case .enter: 36
        case .tab: 48
        case .escape: 53
        case .space: 49
        }
    }
    /// Arrow keys carry the numeric-pad + fn flags like a real keyboard.
    public var isArrow: Bool { [.left, .right, .up, .down].contains(self) }
}

/// `scroll.phase` (trackpad-style scrolling): finger down, finger moving, finger up, phone-computed fling.
public enum ScrollPhase: String, Sendable, CaseIterable {
    case begin, move, end, momentum
}

/// `{t:'practice', step:'start'|'stop'}` (phone -> Mac).
public enum PracticeCommand: String, Sendable { case start, stop }

/// `{t:'practice', step:'running'|'result'|'stop', hits?, total?, ms?}` (Mac -> phone).
public enum PracticeReport: Equatable, Sendable {
    /// Practice is on screen. `hits` = targets hit so far, `total` = clicks so far.
    case running(hits: Int, total: Int)
    /// Finished. `hits` = clicks on a target, `total` = all clicks, `ms` = average time per target.
    case result(hits: Int, total: Int, ms: Int)
    /// Closed before the end (Esc / Cancel on the Mac).
    case stopped
}

/// Calibration targets. v3: `center`, `tl`, `tr`, `br`, `bl` (in that order). `left` / `right` = older phones.
public enum Side: String, Sendable, CaseIterable {
    case left, right, center, tl, tr, br, bl
    /// Calibration v3 order (spec 4b).
    public static let fourCorners: [Side] = [.center, .tl, .tr, .br, .bl]

    /// "Centre", "Top-Left Corner" ... (overlay titles).
    public var title: String {
        switch self {
        case .left: "Left Dot"
        case .right: "Right Dot"
        case .center: "Centre"
        case .tl: "Top-Left Corner"
        case .tr: "Top-Right Corner"
        case .br: "Bottom-Right Corner"
        case .bl: "Bottom-Left Corner"
        }
    }
}

public struct PhoneDevice: Equatable, Sendable {
    public static let fallbackWMm = 71.5
    public static let fallbackHMm = 147.5

    public var name: String
    public var model: String?
    public var wMm: Double
    public var hMm: Double

    public init(name: String = "iPhone", model: String? = nil,
                wMm: Double = PhoneDevice.fallbackWMm, hMm: Double = PhoneDevice.fallbackHMm) {
        self.name = name; self.model = model; self.wMm = wMm; self.hMm = hMm
    }
}

public enum CalibEvent: Equatable, Sendable {
    case start
    /// `near` / `upright` (calibration v2, spec 4a) are optional: `nil` = the phone did not say (older app).
    case place(progress: Double, still: Bool, near: Bool? = nil, upright: Bool? = nil)
    case placed
    case point(Side)
    case pointed(Side)
    case done(sensitivity: Double?)
    case cancel
    /// v3: pointing finished; the phone moves the cursor again and the Mac shows the check dots.
    case verify
}

public enum InboundMessage: Equatable, Sendable {
    case hello(version: Int?, device: PhoneDevice)
    case move(dx: Double, dy: Double)
    case button(MouseButton, down: Bool)
    /// Legacy notches (no `phase`): positive = scroll down.
    case scroll(dy: Int)
    /// Trackpad-style scroll (`phase` present): points, fractional, positive dy = scroll down / dx = right.
    case smoothScroll(dx: Double, dy: Double, phase: ScrollPhase)
    case key(ArrowKey)
    case center
    case calib(CalibEvent)
    /// Unicode text to type into the focused app.
    case text(String)
    case practice(PracticeCommand)
}

public struct ScreenInfo: Equatable, Sendable {
    public var w: Int
    public var h: Int
    public var scale: Double
    public var wMm: Double
    public var hMm: Double
    public var name: String

    public init(w: Int, h: Int, scale: Double, wMm: Double, hMm: Double, name: String) {
        self.w = w; self.h = h; self.scale = scale; self.wMm = wMm; self.hMm = hMm; self.name = name
    }

    public var center: CGPoint { CGPoint(x: Double(w) / 2, y: Double(h) / 2) }
}

public enum OutboundMessage: Equatable, Sendable {
    case screen(ScreenInfo)
    case calibRequest
    case calibCancel
    /// v3 verify: the real cursor reached this dot for the first time.
    case calibHit(Side)
    /// The system-wide focused UI element is (not) a text input.
    case focus(editable: Bool)
    case practice(PracticeReport)
}

public enum ProtocolCodec {
    static let maxMove = 5000.0
    static let maxScroll = 50.0
    static let maxScrollPoints = 4000.0
    /// Longest `text` accepted per message (characters); longer strings are cut.
    public static let maxText = 2000

    public static func decode(_ text: String) -> InboundMessage? {
        decode(Data(text.utf8))
    }

    public static func decode(_ data: Data) -> InboundMessage? {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let m = obj as? [String: Any],
              let t = m["t"] as? String else { return nil }
        switch t {
        case "hello":
            let v = int(m["v"])
            var device = PhoneDevice()
            if let d = m["device"] as? [String: Any] {
                if let name = d["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    device.name = String(name.prefix(80))
                }
                if let model = d["model"] as? String, !model.isEmpty { device.model = String(model.prefix(80)) }
                if let w = number(d["wMm"]), let h = number(d["hMm"]),
                   (20...400).contains(w), (20...400).contains(h) {
                    device.wMm = w; device.hMm = h
                }
            }
            return .hello(version: v, device: device)
        case "move":
            guard let dx = number(m["dx"]), let dy = number(m["dy"]) else { return nil }
            return .move(dx: clamp(dx, maxMove), dy: clamp(dy, maxMove))
        case "button":
            guard let b = (m["b"] as? String).flatMap(MouseButton.init(rawValue:)),
                  let down = bool(m["down"]) else { return nil }
            return .button(b, down: down)
        case "scroll" where m["phase"] is String:
            guard let phase = (m["phase"] as? String).flatMap(ScrollPhase.init(rawValue:)) else { return nil }
            let dy = number(m["dy"]) ?? 0, dx = number(m["dx"]) ?? 0
            return .smoothScroll(dx: clamp(dx, maxScrollPoints), dy: clamp(dy, maxScrollPoints), phase: phase)
        case "scroll":
            guard let dy = number(m["dy"]) else { return nil }
            let lines = Int(clamp(dy, maxScroll).rounded())
            return lines == 0 ? nil : .scroll(dy: lines)
        case "key":
            guard let k = (m["k"] as? String).flatMap(ArrowKey.init(rawValue:)) else { return nil }
            return .key(k)
        case "center":
            return .center
        case "calib":
            return decodeCalib(m).map(InboundMessage.calib)
        case "text":
            guard let str = m["s"] as? String, !str.isEmpty else { return nil }
            return .text(String(str.prefix(maxText)))
        case "practice":
            guard let c = (m["step"] as? String).flatMap(PracticeCommand.init(rawValue:)) else { return nil }
            return .practice(c)
        default:
            return nil
        }
    }

    static func decodeCalib(_ m: [String: Any]) -> CalibEvent? {
        guard let step = m["step"] as? String else { return nil }
        let target = (m["target"] as? String).flatMap(Side.init(rawValue:))
        switch step {
        case "start": return .start
        case "place":
            let p = min(1, max(0, number(m["progress"]) ?? 0))
            return .place(progress: p, still: bool(m["still"]) ?? true, near: bool(m["near"]), upright: bool(m["upright"]))
        case "placed": return .placed
        case "point": return target.map(CalibEvent.point)
        case "pointed": return target.map(CalibEvent.pointed)
        case "done": return .done(sensitivity: number(m["sensitivity"]))
        case "cancel": return .cancel
        case "verify": return .verify
        default: return nil
        }
    }

    public static func encode(_ msg: OutboundMessage) -> String {
        let obj: [String: Any]
        switch msg {
        case .screen(let s):
            obj = ["t": "screen", "w": s.w, "h": s.h, "scale": round1(s.scale),
                   "wMm": round1(s.wMm), "hMm": round1(s.hMm), "name": s.name]
        case .calibRequest: obj = ["t": "calib", "step": "request"]
        case .calibCancel: obj = ["t": "calib", "step": "cancel"]
        case .calibHit(let s): obj = ["t": "calib", "step": "hit", "target": s.rawValue]
        case .focus(let editable): obj = ["t": "focus", "editable": editable]
        case .practice(.running(let hits, let total)): obj = ["t": "practice", "step": "running", "hits": hits, "total": total]
        case .practice(.result(let hits, let total, let ms)):
            obj = ["t": "practice", "step": "result", "hits": hits, "total": total, "ms": ms]
        case .practice(.stopped): obj = ["t": "practice", "step": "stop"]
        }
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: tolerant scalar helpers

    static func isBool(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }

    static func number(_ any: Any?) -> Double? {
        guard let n = any as? NSNumber, !isBool(n) else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    static func int(_ any: Any?) -> Int? { number(any).map { Int($0) } }

    static func bool(_ any: Any?) -> Bool? {
        guard let n = any as? NSNumber else { return nil }
        return n.doubleValue != 0
    }

    static func clamp(_ v: Double, _ limit: Double) -> Double { min(limit, max(-limit, v)) }
    static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
}

// MARK: - Text typing

public enum TextChunks {
    /// UTF-16 units per CGEvent (`keyboardSetUnicodeString` is reliable up to 20).
    public static let maxUnits = 20

    /// Splits into UTF-16 chunks of at most `max` units without cutting a surrogate pair.
    public static func split(_ s: String, max: Int = maxUnits) -> [[UInt16]] {
        precondition(max >= 2)
        var out: [[UInt16]] = []
        var cur: [UInt16] = []
        for scalar in s.unicodeScalars {
            let units = Array(String(scalar).utf16)
            if cur.count + units.count > max { out.append(cur); cur = [] }
            cur.append(contentsOf: units)
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}

// MARK: - Focused element (Mac -> phone `focus`)

public enum FocusEditability {
    /// AX roles that always take text.
    public static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// Controls whose AXValue is settable but that are not text inputs (would pop the keyboard on a slider).
    public static let nonTextRoles: Set<String> = [
        "AXSlider", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXScrollBar",
        "AXIncrementor", "AXStepper", "AXColorWell", "AXDisclosureTriangle", "AXSplitter", "AXLevelIndicator",
        "AXValueIndicator", "AXSwitch", "AXToggle", "AXTabGroup", "AXOutline", "AXTable", "AXList",
    ]

    /// Pure rule used by the AX poller: a text role, inside an editable web area
    /// (`AXEditableAncestor` present), or a settable AXValue on something that is not a known non-text control.
    public static func isEditable(role: String?, hasEditableAncestor: Bool = false, valueSettable: Bool = false) -> Bool {
        guard let role, !role.isEmpty else { return false }
        if textRoles.contains(role) { return true }
        if nonTextRoles.contains(role) { return false }
        return hasEditableAncestor || valueSettable
    }
}
