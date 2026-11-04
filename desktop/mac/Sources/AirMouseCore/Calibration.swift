import Foundation
import CoreGraphics

/// Spec 3 "Calibration geometry": both sides must agree.
public enum CalibrationGeometry {
    public static let cornerRadiusMm = 12.0
    /// Used when CGDisplayScreenSize reports nothing (some external displays):
    /// ~5 pt/mm is what a 14" MacBook Pro uses at its default scaled resolution.
    public static let fallbackPointsPerMm = 5.0

    public static func pointsPerMm(_ screen: ScreenInfo) -> Double {
        guard screen.wMm > 1, screen.w > 0 else { return fallbackPointsPerMm }
        return Double(screen.w) / screen.wMm
    }

    /// Physical-size phone outline centred on the display, in display-local points
    /// (top-left origin). Shrunk uniformly only if it would not fit 92% of the height.
    public static func outlineRect(screen: ScreenInfo, phoneWMm: Double, phoneHMm: Double) -> CGRect {
        let ppmm = pointsPerMm(screen)
        var w = phoneWMm * ppmm, h = phoneHMm * ppmm
        let maxH = Double(screen.h) * 0.92
        if h > maxH { let k = maxH / h; w *= k; h *= k }
        return CGRect(x: (Double(screen.w) - w) / 2, y: (Double(screen.h) - h) / 2, width: w, height: h)
    }

    public static func cornerRadius(screen: ScreenInfo) -> Double { cornerRadiusMm * pointsPerMm(screen) }

    /// Corner targets sit this fraction of the width / height in from the edges (v3).
    public static let cornerInset = 0.08
    /// Verify step: a dot lights while the cursor is within this many points of it.
    public static let hitRadius = 40.0

    /// Target centre in display-local points (top-left origin).
    public static func target(_ side: Side, screen: ScreenInfo) -> CGPoint {
        let (fx, fy) = fraction(side)
        return CGPoint(x: Double(screen.w) * fx, y: Double(screen.h) * fy)
    }

    public static func fraction(_ side: Side) -> (Double, Double) {
        let lo = cornerInset, hi = 1 - cornerInset
        switch side {
        case .left: return (0.1, 0.5)
        case .right: return (0.9, 0.5)
        case .center: return (0.5, 0.5)
        case .tl: return (lo, lo)
        case .tr: return (hi, lo)
        case .br: return (hi, hi)
        case .bl: return (lo, hi)
        }
    }

    /// Verify targets the cursor at `p` is touching (within `hitRadius`).
    public static func touching(_ p: CGPoint, screen: ScreenInfo, targets: [Side] = Side.fourCorners,
                                radius: Double = hitRadius) -> Set<Side> {
        Set(targets.filter { t in
            let c = target(t, screen: screen)
            return hypot(p.x - c.x, p.y - c.y) <= radius
        })
    }

    public static func targetDistance(screen: ScreenInfo) -> Double { 0.8 * Double(screen.w) }
}

/// What the Mac overlay shows. Pure reducer over `CalibEvent`s so it is testable.
public struct CalibrationState: Equatable, Sendable {
    public enum Step: Equatable, Sendable { case place, placed, point(Side), verify, done }

    public var visible = false
    public var step: Step = .place
    public var progress = 0.0
    public var still = true
    /// Calibration v2 placement signals from the phone; `nil` = unknown (older phone app).
    public var near: Bool?
    public var upright: Bool?
    /// Targets the phone reported as `pointed` this run.
    public var pointed: Set<Side> = []
    /// Verify: dots the cursor touches right now, and every dot it has touched this run.
    public var lit: Set<Side> = []
    public var everLit: Set<Side> = []
    /// True once the verify step ran (the result card then shows how many dots were reached).
    public var verified = false
    public var sensitivity: Double?

    public var leftHit: Bool { pointed.contains(.left) }
    public var rightHit: Bool { pointed.contains(.right) }

    public init() {}

    public mutating func apply(_ event: CalibEvent) {
        switch event {
        case .start:
            self = CalibrationState(); visible = true
        case .place(let p, let s, let n, let u):
            if !visible || step != .place { self = CalibrationState(); visible = true }
            still = s; near = n; upright = u
            // Progress only counts while every known signal holds (the ring drains otherwise).
            progress = (s && n != false && u != false) ? p : 0
        case .placed:
            visible = true; step = .placed; progress = 1; still = true
        case .point(let t):
            visible = true; step = .point(t); pointed.remove(t)
            if t == .center { pointed = [] }
            if t == .right { pointed.insert(.left) } // older phones: left is done once right is asked for
        case .pointed(let t):
            pointed.insert(t)
        case .verify:
            visible = true; step = .verify; lit = []; everLit = []; verified = true
        case .done(let s):
            visible = true; step = .done; sensitivity = s
        case .cancel:
            self = CalibrationState()
        }
    }

    /// Live guidance under the step 1 instruction.
    public var placeHint: PlaceHint {
        PlaceHint.select(progress: progress, still: still, near: near, upright: upright)
    }

    /// Verify step: feed the cursor position (display-local points). Returns the dots touched for the first time
    /// (the Mac sends `calib hit` for each).
    public mutating func cursor(at p: CGPoint, screen: ScreenInfo) -> [Side] {
        guard visible, step == .verify else { return [] }
        let now = CalibrationGeometry.touching(p, screen: screen)
        if now != lit { lit = now }
        let fresh = Side.fourCorners.filter { now.contains($0) && !everLit.contains($0) }
        everLit.formUnion(fresh)
        return fresh
    }

    /// 1-based step number shown in the ring (place = 1, point = 2, verify = 3; old right = 3).
    public var stepNumber: Int {
        switch step {
        case .place, .placed: 1
        case .point(.right): 3
        case .point: 2
        case .verify: 3
        case .done: 4
        }
    }

    /// v3 pointing progress: index of the current target in `Side.fourCorners` (nil for old left/right).
    public var cornerIndex: Int? {
        guard case .point(let t) = step else { return nil }
        return Side.fourCorners.firstIndex(of: t)
    }
}

/// Step 1 live hint (spec 4a). The phone's own screen is dark while it is near the glass,
/// so this line on the overlay is the main guide.
public enum PlaceHint: Equatable, Sendable {
    /// No placement signals yet (older phone app, or nothing received): the classic prompt.
    case placeInside
    case bringCloser
    case holdUpright
    case holdStill
    /// Everything holds: the outline fills. Carries the progress 0...1.
    case filling(Double)

    public static func select(progress: Double, still: Bool, near: Bool?, upright: Bool?) -> PlaceHint {
        if near == false { return .bringCloser }
        if upright == false { return .holdUpright }
        if !still { return .holdStill }
        if progress > 0 || (near == true && upright != false) { return .filling(min(1, max(0, progress))) }
        return .placeInside
    }

    public var text: String {
        switch self {
        case .placeInside: "Place your iPhone inside the outline"
        case .bringCloser: "Bring your iPhone to the screen"
        case .holdUpright: "Hold it upright against the display"
        case .holdStill: "Hold still"
        case .filling: "Hold still"
        }
    }

    /// Stable identity for transitions (progress changes must not re-trigger them).
    public var kind: String {
        switch self {
        case .placeInside: "placeInside"
        case .bringCloser: "bringCloser"
        case .holdUpright: "holdUpright"
        case .holdStill: "holdStill"
        case .filling: "filling"
        }
    }

    /// Something the person must fix (warning tint) vs. on track.
    public var needsAction: Bool {
        switch self {
        case .holdUpright, .holdStill: true
        default: false
        }
    }
}
