import Foundation
import CoreGraphics

/// Smooth pointer output (spec 5). Network `move` deltas accumulate in `pending`; each display frame drains it
/// **linearly over the expected packet interval** (EWMA of input inter-arrival, so it adapts to 60 Hz Wi-Fi as
/// well as 15-30 Hz BLE): at a steady input rate the pointer moves at constant velocity between packets
/// instead of jumping and stopping. Bursts (several packets at once) are spread over one interval.
///
/// Gap bridging: when the next packet is late, the pointer glides on at the last drain velocity, decaying
/// to 0 over `glideWindow` (1.5x the interval, 60-120 ms). That distance is a debt: late packets repay it
/// first (no overshoot); if none arrive within `debtTimeout` it is paced back, so total output = total input.
public struct MotionPacer: Equatable, Sendable {
    /// Below this length (points) the whole remainder is emitted.
    public static let snap = 0.05
    public static let minInterval = 1.0 / 120
    public static let maxInterval = 0.1
    /// Gaps longer than this are pauses, not packet spacing (not averaged).
    public static let pauseGap = 0.2
    public static let minGlide = 0.06
    public static let maxGlide = 0.12
    /// Slower than this (pt/s) is not worth gliding.
    public static let minGlideSpeed = 20.0

    public private(set) var pendingX = 0.0
    public private(set) var pendingY = 0.0
    /// Extrapolated distance not yet backed by input.
    public private(set) var debtX = 0.0
    public private(set) var debtY = 0.0
    /// EWMA of the input inter-arrival time (s).
    public private(set) var meanInterval = 1.0 / 60
    /// Current drain velocity (pt/s), set on each input: pending / expected interval.
    public private(set) var vx = 0.0
    public private(set) var vy = 0.0
    private var clock = 0.0
    private var lastInputAt: Double?
    private var glideVX = 0.0
    private var glideVY = 0.0
    private var glideStart: Double?
    /// At most one glide per received move (never glide on the give-back).
    private var canGlide = false
    private var intervalSamples = 0
    /// An input arrived since the last frame.
    private var freshInput = false

    /// Scroll uses no glide (a give-back would scroll backwards).
    public var glides = true

    public init(glides: Bool = true) { self.glides = glides }

    /// Nothing to emit and no glide armed (a moving pointer always gets its one glide before idling).
    public var isIdle: Bool {
        pendingX == 0 && pendingY == 0 && debtX == 0 && debtY == 0 && glideStart == nil
            && !(glides && canGlide && hypot(vx, vy) > Self.minGlideSpeed)
    }
    public var isGliding: Bool { glideStart != nil }
    public var glideWindow: Double { min(Self.maxGlide, max(Self.minGlide, 1.5 * meanInterval)) }
    /// No move for this long after a glide: give the glide back.
    public var debtTimeout: Double { max(0.25, 3 * meanInterval) }

    public mutating func add(dx: Double, dy: Double) {
        guard dx.isFinite, dy.isFinite else { return }
        if let last = lastInputAt {
            let gap = clock - last
            if gap > 0, gap < Self.pauseGap {
                let g = min(Self.maxInterval, max(Self.minInterval, gap))
                // First sample sets it (fast lock to BLE's 15-30 Hz), then a gentle EWMA.
                meanInterval = intervalSamples == 0 ? g : meanInterval + (g - meanInterval) * 0.2
                intervalSamples += 1
            }
        }
        lastInputAt = clock
        glideStart = nil
        canGlide = true
        freshInput = true
        // Late packets first repay what the glide already moved.
        pendingX += dx - debtX; pendingY += dy - debtY
        debtX = 0; debtY = 0
        retarget()
    }

    /// Drain what is pending over one expected interval.
    private mutating func retarget() {
        vx = pendingX / meanInterval; vy = pendingY / meanInterval
    }

    public mutating func reset() { self = MotionPacer(glides: glides) }

    /// One display frame. Returns the delta to post now (nil = idle; the caller may pause its timer).
    public mutating func step(dt: Double) -> CGVector? {
        let dt = max(0, dt)
        clock += dt
        if isIdle { freshInput = false; return nil }
        let startedEmpty = pendingX == 0 && pendingY == 0 && !freshInput
        freshInput = false

        // Paced part: constant velocity, never past what is pending.
        var ox = 0.0, oy = 0.0
        let len = hypot(pendingX, pendingY)
        if len < Self.snap {
            ox = pendingX; oy = pendingY
        } else {
            let want = hypot(vx, vy) * dt
            // Never slower than draining within 3 intervals (keeps lag bounded if the rate estimate is off).
            var step = min(len, max(want, len * min(1, dt / (3 * meanInterval))))
            if len - step < want * 0.5 { step = len } // no sliver frame before the next packet
            ox = pendingX / len * step; oy = pendingY / len * step
        }
        pendingX -= ox; pendingY -= oy
        if abs(pendingX) < 1e-12 { pendingX = 0 }
        if abs(pendingY) < 1e-12 { pendingY = 0 }

        // Glide: a whole frame passed with nothing pending (next packet early-late or delayed) - keep the
        // velocity instead of stopping; the next packet repays it.
        let age = lastInputAt.map { clock - $0 } ?? .infinity
        if glides, startedEmpty, canGlide, hypot(vx, vy) > Self.minGlideSpeed {
            canGlide = false
            glideStart = clock; glideVX = vx; glideVY = vy
        }
        if let g = glideStart {
            let t = clock - g
            if t < glideWindow {
                let decay = 1 - t / glideWindow
                let ex = glideVX * decay * dt, ey = glideVY * decay * dt
                ox += ex; oy += ey; debtX += ex; debtY += ey
            } else {
                glideStart = nil
            }
        }
        // Nothing came back: give the glide back (paced, via pending).
        if debtX != 0 || debtY != 0, glideStart == nil, age > debtTimeout {
            pendingX -= debtX; pendingY -= debtY
            debtX = 0; debtY = 0
            canGlide = false
            retarget()
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

// MARK: - Scroll

/// CGEvent scroll phase codes (kCGScrollWheelEventScrollPhase / kCGScrollWheelEventMomentumPhase).
public enum ScrollEventPhase {
    public static let began: Int64 = 1
    public static let changed: Int64 = 2
    public static let ended: Int64 = 4
    public static let momentumBegin: Int64 = 1
    public static let momentumContinue: Int64 = 2
    public static let momentumEnd: Int64 = 3
}

/// One scroll CGEvent to post: points (positive dy = scroll down) plus the phase fields.
public struct ScrollFrame: Equatable, Sendable {
    public var dx: Double
    public var dy: Double
    /// kCGScrollWheelEventScrollPhase (0 = none).
    public var scrollPhase: Int64
    /// kCGScrollWheelEventMomentumPhase (0 = none).
    public var momentumPhase: Int64
    public init(dx: Double, dy: Double, scrollPhase: Int64 = 0, momentumPhase: Int64 = 0) {
        self.dx = dx; self.dy = dy; self.scrollPhase = scrollPhase; self.momentumPhase = momentumPhase
    }
}

/// Paces scroll like pointer moves (display frames, linear drain over the input interval, no glide) and turns
/// the phone's `phase` stream into the macOS gesture sequence: began -> changed... -> ended, then
/// momentum begin -> continue... -> end. Legacy notches (no phase) become phase-less pixel scrolls.
public struct ScrollPacer: Equatable, Sendable {
    public enum Gesture: Equatable, Sendable { case none, legacy, touching, momentum }

    /// Points per legacy notch.
    public static let pointsPerLine = 12.0
    /// No scroll message for this long ends an open gesture (lost `end`, momentum without a final zero).
    public static let touchTimeout = 1.0
    public static let momentumTimeout = 0.2

    public private(set) var gesture = Gesture.none
    private var pacer = MotionPacer(glides: false)
    private var began = false          // `began` / momentum begin already posted
    private var endRequested = false
    private var clock = 0.0
    private var lastInputAt = 0.0
    private var queued: [ScrollFrame] = []

    public init() {}

    public var isIdle: Bool { gesture == .none && pacer.isIdle && queued.isEmpty }

    public mutating func addLegacy(lines: Int) {
        if gesture == .touching || gesture == .momentum { closeGesture() }
        gesture = .legacy
        lastInputAt = clock
        pacer.add(dx: 0, dy: Double(lines) * Self.pointsPerLine)
    }

    public mutating func add(dx: Double, dy: Double, phase: ScrollPhase) {
        lastInputAt = clock
        switch phase {
        case .begin:
            if gesture != .none { closeGesture() }
            gesture = .touching; began = false; endRequested = false
        case .move:
            if gesture != .touching { if gesture != .none { closeGesture() }; gesture = .touching; began = false; endRequested = false }
        case .end:
            if gesture != .touching { if gesture != .none { closeGesture() }; gesture = .touching; began = false }
            endRequested = true
        case .momentum:
            if gesture == .touching { closeGesture() }
            if gesture != .momentum { gesture = .momentum; began = false; endRequested = false }
            if dx == 0 && dy == 0 { endRequested = true }
        }
        if dx != 0 || dy != 0 { pacer.add(dx: dx, dy: dy) }
    }

    /// Flush what is pending and close the open gesture now (a new gesture or another kind interrupts it).
    private mutating func closeGesture() {
        let rest = CGVector(dx: pacer.pendingX, dy: pacer.pendingY)
        pacer.reset()
        switch gesture {
        case .touching:
            if rest.dx != 0 || rest.dy != 0 {
                queued.append(ScrollFrame(dx: rest.dx, dy: rest.dy, scrollPhase: began ? ScrollEventPhase.changed : ScrollEventPhase.began))
                began = true
            }
            if began { queued.append(ScrollFrame(dx: 0, dy: 0, scrollPhase: ScrollEventPhase.ended)) }
        case .momentum:
            if rest.dx != 0 || rest.dy != 0 {
                queued.append(ScrollFrame(dx: rest.dx, dy: rest.dy, momentumPhase: began ? ScrollEventPhase.momentumContinue : ScrollEventPhase.momentumBegin))
                began = true
            }
            if began { queued.append(ScrollFrame(dx: 0, dy: 0, momentumPhase: ScrollEventPhase.momentumEnd)) }
        case .legacy:
            if rest.dx != 0 || rest.dy != 0 { queued.append(ScrollFrame(dx: rest.dx, dy: rest.dy)) }
        case .none: break
        }
        gesture = .none; began = false; endRequested = false
    }

    /// One display frame: the scroll events to post now, in order.
    public mutating func step(dt: Double) -> [ScrollFrame] {
        clock += max(0, dt)
        var out = queued
        queued.removeAll()
        if let d = pacer.step(dt: dt), d.dx != 0 || d.dy != 0 {
            switch gesture {
            case .touching:
                out.append(ScrollFrame(dx: d.dx, dy: d.dy, scrollPhase: began ? ScrollEventPhase.changed : ScrollEventPhase.began))
                began = true
            case .momentum:
                out.append(ScrollFrame(dx: d.dx, dy: d.dy, momentumPhase: began ? ScrollEventPhase.momentumContinue : ScrollEventPhase.momentumBegin))
                began = true
            case .legacy, .none:
                out.append(ScrollFrame(dx: d.dx, dy: d.dy))
            }
        }
        let quiet = clock - lastInputAt
        let drained = pacer.isIdle
        switch gesture {
        case .touching where drained && (endRequested || quiet > Self.touchTimeout),
             .momentum where drained && (endRequested || quiet > Self.momentumTimeout),
             .legacy where drained:
            closeGesture()
            out += queued
            queued.removeAll()
        default: break
        }
        return out
    }
}
