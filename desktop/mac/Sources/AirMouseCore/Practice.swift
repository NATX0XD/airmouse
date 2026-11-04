import Foundation
import CoreGraphics

/// Small deterministic RNG (SplitMix64) so tests and previews get fixed target layouts.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Click Practice: 10 round targets one at a time. Pure state; the overlay feeds it clicks in view points.
public struct PracticeGame: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case running, finished }
    public enum ClickResult: Equatable, Sendable { case hit(index: Int), miss, ignored }

    public static let targetCount = 10
    public static let margin = 0.1
    public static let startDiameter = 64.0
    public static let endDiameter = 44.0

    /// Target centres, normalised 0...1 inside the 10% margins.
    public let targets: [CGPoint]
    public private(set) var index = 0
    public private(set) var hits = 0
    public private(set) var misses = 0
    public private(set) var phase = Phase.running
    /// Seconds from each target appearing to being hit.
    public private(set) var times: [Double] = []
    private var shownAt: Double

    public init(now: Double, count: Int = PracticeGame.targetCount, seed: UInt64? = nil) {
        if let seed {
            var rng = SeededRandom(seed: seed)
            targets = Self.layout(count: count, using: &rng)
        } else {
            var rng = SystemRandomNumberGenerator()
            targets = Self.layout(count: count, using: &rng)
        }
        shownAt = now
    }

    /// Random points inside the margins; each one at least 0.25 (normalised) away from the previous.
    public static func layout<R: RandomNumberGenerator>(count: Int, using rng: inout R) -> [CGPoint] {
        var out: [CGPoint] = []
        let lo = margin, hi = 1 - margin
        for _ in 0..<count {
            var p = CGPoint.zero
            for _ in 0..<20 {
                p = CGPoint(x: Double.random(in: lo...hi, using: &rng), y: Double.random(in: lo...hi, using: &rng))
                guard let last = out.last else { break }
                if hypot(p.x - last.x, p.y - last.y) >= 0.25 { break }
            }
            out.append(p)
        }
        return out
    }

    public var total: Int { hits + misses }
    public var count: Int { targets.count }

    /// Diameter in points for target `i`: 64 shrinking linearly to 44 on the last one.
    public static func diameter(for i: Int, of count: Int = targetCount) -> Double {
        guard count > 1 else { return startDiameter }
        let k = Double(min(max(i, 0), count - 1)) / Double(count - 1)
        return startDiameter + (endDiameter - startDiameter) * k
    }

    public var currentDiameter: Double { Self.diameter(for: index, of: count) }

    /// Current target centre in view points.
    public func currentCenter(in size: CGSize) -> CGPoint? {
        guard phase == .running, index < targets.count else { return nil }
        return Self.point(targets[index], in: size)
    }

    public static func point(_ n: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: n.x * size.width, y: n.y * size.height)
    }

    /// A click at `p` (view points) on a view of `size`.
    @discardableResult
    public mutating func click(at p: CGPoint, in size: CGSize, now: Double) -> ClickResult {
        guard let c = currentCenter(in: size) else { return .ignored }
        guard hypot(p.x - c.x, p.y - c.y) <= currentDiameter / 2 else { misses += 1; return .miss }
        let hitIndex = index
        hits += 1
        times.append(max(0, now - shownAt))
        index += 1
        shownAt = now
        if index >= targets.count { phase = .finished }
        return .hit(index: hitIndex)
    }

    /// Average time per target in milliseconds (0 before the first hit).
    public var averageMs: Int {
        guard !times.isEmpty else { return 0 }
        return Int((times.reduce(0, +) / Double(times.count) * 1000).rounded())
    }

    /// Hit rate 0...1 (1 when nothing was clicked yet).
    public var accuracy: Double { total == 0 ? 1 : Double(hits) / Double(total) }

    public var report: PracticeReport {
        phase == .finished ? .result(hits: hits, total: total, ms: averageMs) : .running(hits: hits, total: total)
    }
}
