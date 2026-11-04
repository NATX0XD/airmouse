import Foundation
import CoreGraphics

/// Smooth pointer output (spec 5): network `move` deltas accumulate in `pending`; every display frame
/// emits a fixed fraction of it, so Wi-Fi bursts are spread over a few frames (~15 ms lag at 120 Hz)
/// instead of jumping. Nothing is lost: the remainder is emitted whole once it is tiny.
///
/// Gap bridging: when moves stop arriving for longer than usual (AWDL / Wi-Fi hiccup) while the pointer
/// was moving, it keeps gliding at the recent velocity, decaying to 0 over `extrapolationWindow`. That
/// distance is a debt: late packets repay it first (no overshoot), and if none arrive within `debtTimeout`
/// it is paced back, so the total output always equals the total input.
public struct MotionPacer: Equatable, Sendable {
    /// Fraction of `pending` emitted per frame at the reference rate.
    public static let kAt120 = 0.45
    public static let referenceHz = 120.0
    /// Below this length (points) the whole remainder is emitted.
    public static let snap = 0.05
    /// Longest glide through a gap, seconds (velocity decays linearly to 0).
    public static let extrapolationWindow = 0.06
    /// No move for this long after a glide: give the glide back.
    public static let debtTimeout = 0.25

    public private(set) var pendingX = 0.0
    public private(set) var pendingY = 0.0
    /// Extrapolated distance not yet backed by input.
    public private(set) var debtX = 0.0
    public private(set) var debtY = 0.0
    /// Velocity of the paced output (pt/s), smoothed.
    public private(set) var vx = 0.0
    public private(set) var vy = 0.0
    /// Pacer clock (sum of frame times), last input time and the usual input interval.
    private var clock = 0.0
    private var lastInputAt: Double?
    private var meanInterval = 1.0 / 60
    private var glideVX = 0.0
    private var glideVY = 0.0
    private var glideStart: Double?

    public init() {}

    public var isIdle: Bool { pendingX == 0 && pendingY == 0 && debtX == 0 && debtY == 0 && vx == 0 && vy == 0 }
    public var isGliding: Bool { glideStart != nil }

    public mutating func add(dx: Double, dy: Double) {
        guard dx.isFinite, dy.isFinite else { return }
        if let last = lastInputAt {
            let gap = clock - last
            if gap > 0 { meanInterval += (min(0.04, max(0.004, gap)) - meanInterval) * 0.2 }
        }
        lastInputAt = clock
        glideStart = nil
        // Late packets first repay what the glide already moved.
        pendingX += dx - debtX; pendingY += dy - debtY
        debtX = 0; debtY = 0
    }

    public mutating func reset() { self = MotionPacer() }

    /// Per-frame factor for a frame of `dt` seconds: same time constant at 60 / 120 / any Hz.
    public static func factor(dt: Double) -> Double {
        let frames = max(0, dt) * referenceHz
        return 1 - pow(1 - kAt120, frames)
    }

    /// One display frame. Returns the delta to post now (nil = idle; the caller may pause its timer).
    public mutating func step(dt: Double) -> CGVector? {
        let dt = max(0, dt)
        clock += dt
        if isIdle { lastInputAt = nil; return nil }

        // Paced part.
        var ox = 0.0, oy = 0.0
        if hypot(pendingX, pendingY) < Self.snap {
            ox = pendingX; oy = pendingY
        } else {
            let k = Self.factor(dt: dt)
            ox = pendingX * k; oy = pendingY * k
        }
        pendingX -= ox; pendingY -= oy
        if dt > 0 {
            let a = min(1, dt * 30) // ~33 ms smoothing
            vx += (ox / dt - vx) * a; vy += (oy / dt - vy) * a
        }

        // Glide through a gap.
        let age = lastInputAt.map { clock - $0 } ?? .infinity
        let late = age > max(1.5 * meanInterval, dt * 1.01)
        if late, glideStart == nil, debtX == 0, debtY == 0, hypot(vx, vy) > 1 {
            glideStart = clock; glideVX = vx; glideVY = vy
        }
        if let g = glideStart {
            let t = clock - g
            if t < Self.extrapolationWindow {
                let decay = 1 - t / Self.extrapolationWindow
                let ex = glideVX * decay * dt, ey = glideVY * decay * dt
                ox += ex; oy += ey; debtX += ex; debtY += ey
            } else {
                glideStart = nil
            }
        }
        // Nothing came back: give the glide back (paced, via pending).
        if (debtX != 0 || debtY != 0), glideStart == nil, age > Self.debtTimeout {
            pendingX -= debtX; pendingY -= debtY
            debtX = 0; debtY = 0
        }
        // Settle to idle once everything is spent.
        if pendingX == 0, pendingY == 0, debtX == 0, debtY == 0, glideStart == nil, hypot(vx, vy) < 1 {
            vx = 0; vy = 0
        }
        return CGVector(dx: ox, dy: oy)
    }
}

/// Frames per second of a periodic callback, over ~1 s windows (0 once it stops for a second).
public struct FrameRateMeter: Equatable, Sendable {
    private var windowStart: Double?
    private var frames = 0
    private var last: Double?
    public private(set) var fps = 0.0

    public init() {}

    public mutating func tick(at now: Double) {
        last = now
        guard let start = windowStart else { windowStart = now; frames = 0; return }
        frames += 1
        if now - start >= 1 { fps = Double(frames) / (now - start); windowStart = now; frames = 0 }
    }

    public func rate(now: Double) -> Double {
        guard let last, now - last < 1 else { return 0 }
        return fps
    }
}
