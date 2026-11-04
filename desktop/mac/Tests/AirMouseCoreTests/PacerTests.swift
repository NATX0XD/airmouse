import Foundation
import CoreGraphics
import Testing
@testable import AirMouseCore

@Suite struct PacerTests {
    @Test func fractionalMovesDecode() {
        #expect(ProtocolCodec.decode(#"{"t":"move","dx":0.37,"dy":-1.25}"#) == .move(dx: 0.37, dy: -1.25))
        #expect(ProtocolCodec.decode(#"{"t":"move","dx":3,"dy":-2}"#) == .move(dx: 3, dy: -2))
    }

    /// Constant velocity at `hz` input (with optional arrival jitter), 120 Hz frames. Returns steady-state frame outputs.
    static func steady(hz: Double, speed: Double, jitter: Double = 0, seconds: Double = 2) -> (out: [Double], sent: Double, pacer: MotionPacer) {
        var p = MotionPacer()
        var rng = SeededRandom(seed: 9)
        var out: [Double] = []
        var sent = 0.0
        var k = 0
        var t = 0.0
        let frame = 1.0 / 120
        var queue: [(Double, Double)] = []   // (arrival, dx)
        while t < seconds + 0.6 {
            while Double(k) / hz < seconds, Double(k) / hz <= t {
                let send = Double(k) / hz
                let arrive = send + (jitter > 0 ? Double.random(in: 0...jitter, using: &rng) : 0)
                queue.append((arrive, speed / hz)); k += 1
            }
            queue.sort { $0.0 < $1.0 }
            while let f = queue.first, f.0 <= t { p.add(dx: f.1, dy: 0); sent += f.1; queue.removeFirst() }
            out.append(Double(p.step(dt: frame)?.dx ?? 0))
            t += frame
        }
        for f in queue { sent += f.1; _ = f }
        return (out, sent, p)
    }

    static func cv(_ xs: ArraySlice<Double>) -> Double {
        let m = xs.reduce(0, +) / Double(xs.count)
        let v = xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count)
        return sqrt(v) / m
    }

    @Test func twentyHzConstantVelocityIsEven() {
        let (out, sent, p) = Self.steady(hz: 20, speed: 300)
        let mid = out[60..<220]                                   // 0.5 s ... 1.8 s
        #expect(Self.cv(mid) < 0.05)                              // near-constant per-frame output
        #expect(abs(mid.reduce(0, +) / Double(mid.count) - 2.5) < 0.1)   // 300 pt/s at 120 Hz
        #expect(abs(p.meanInterval - 0.05) < 0.003)
        #expect(abs(out.reduce(0, +) - sent) < 1e-6)
    }

    @Test(arguments: [15.0, 30.0, 60.0])
    func otherRatesAreEvenToo(_ hz: Double) {
        let (out, sent, _) = Self.steady(hz: hz, speed: 400)
        #expect(Self.cv(out[60..<220]) < 0.12)
        #expect(abs(out.reduce(0, +) - sent) < 1e-6)
    }

    @Test func jitteredTwentyHzStaysSmooth() {
        // BLE write-with-response: arrivals land 0-20 ms late. No frame should stop dead mid-motion.
        let (out, sent, _) = Self.steady(hz: 20, speed: 300, jitter: 0.02)
        let mid = out[60..<220]
        #expect(mid.allSatisfy { $0 > 0.5 })
        #expect(Self.cv(mid) < 0.4)
        #expect(abs(out.reduce(0, +) - sent) < 1e-6)
    }

    @Test func glideWindowAdapts() {
        var p = MotionPacer()
        #expect(p.glideWindow == 0.06)
        for _ in 0..<40 { p.add(dx: 1, dy: 0); for _ in 0..<8 { _ = p.step(dt: 1.0 / 120) } } // 15 Hz
        #expect(abs(p.meanInterval - 1.0 / 15) < 0.003)
        #expect(abs(p.glideWindow - 0.1) < 0.005)
    }

    @Test func burstyInputIsSpreadAndPreserved() {
        // Wi-Fi style: 4 frames of nothing, then 4 messages at once (8 pt each) — repeated.
        var p = MotionPacer()
        var out: [Double] = []
        var sent = 0.0
        for frame in 0..<320 {
            if frame % 5 == 0, frame < 200 { for _ in 0..<4 { p.add(dx: 8, dy: 0); sent += 8 } }
            out.append(Double(p.step(dt: 1.0 / 120)?.dx ?? 0))
        }
        let total = out.reduce(0, +)
        #expect(abs(total - sent) < 1e-9)               // no drift, nothing lost
        #expect(p.isIdle)
        // Steady state: every frame moves, and no frame carries the whole 32 pt burst.
        let steady = out[60..<195]
        #expect(steady.allSatisfy { $0 > 1 }) // never a stopped frame between bursts
        #expect(steady.max()! < 17) // the 32 pt burst is spread (first frame ~0.45 of pending)
        let mean = steady.reduce(0, +) / Double(steady.count)
        #expect(abs(mean - 32.0 / 5) < 0.5)            // average speed preserved
    }

    @Test func smallRemainderSnapsAndStops() {
        var p = MotionPacer()
        p.add(dx: 0.03, dy: -0.02)
        #expect(p.step(dt: 1.0 / 120) == CGVector(dx: 0.03, dy: -0.02))
        #expect(p.step(dt: 1.0 / 120) == nil)
    }

    @Test func diagonalDistancePreservedAt60Hz() {
        var p = MotionPacer()
        p.add(dx: 100, dy: -50)
        var x = 0.0, y = 0.0, frames = 0
        while let d = p.step(dt: 1.0 / 60) { x += d.dx; y += d.dy; frames += 1 }
        #expect(abs(x - 100) < 1e-9 && abs(y + 50) < 1e-9)
        #expect(frames > 3 && frames < 100) // includes the stop glide and its give-back
    }

    @Test func resetDropsPending() {
        var p = MotionPacer()
        p.add(dx: 50, dy: 50); p.reset()
        #expect(p.step(dt: 1.0 / 120) == nil)
    }

    @Test func frameRateMeter() {
        var m = FrameRateMeter()
        for i in 0...240 { m.tick(at: Double(i) / 120) }
        #expect(abs(m.rate(now: 2.0) - 120) < 1)
        #expect(m.rate(now: 5) == 0)
    }

    @Test func moveInterArrivalStats() {
        var s = MessageStats()
        #expect(s.moveInterval(now: 0) == nil)
        for t in [0.0, 0.010, 0.020, 0.070, 0.080] { s.record("move", at: t) }
        let j = s.moveInterval(now: 0.08)!
        #expect(abs(j.meanMs - 20) < 1e-6 && abs(j.maxMs - 50) < 1e-6)
        s.record("move", at: 3.0)  // old gaps leave the 2 s window
        let k = s.moveInterval(now: 3.0)!
        #expect(abs(k.maxMs - 2920) < 1e-6)
        #expect(s.moveInterval(now: 10) == nil)
    }

    /// Phone sends 4 pt every 1/60 s (240 pt/s). Simulates frames at 120 Hz. Packets in [gapStart, gapStart + gap)
    /// are held back and delivered at once when the gap ends (AWDL spike). Returns per-frame x output.
    static func simulate(gap: Double, gapStart: Double = 0.5, stopAt: Double = 1.0) -> (out: [Double], sent: Double) {
        var p = MotionPacer()
        var out: [Double] = []
        var sent = 0.0
        var held = 0.0
        var nextPacket = 0.0
        let frame = 1.0 / 120
        var t = 0.0
        while t < stopAt + 1.0 {
            while nextPacket <= t + 1e-9, nextPacket < stopAt {
                sent += 4
                if nextPacket >= gapStart && nextPacket < gapStart + gap { held += 4 } else { p.add(dx: 4, dy: 0) }
                nextPacket += 1.0 / 60
            }
            if held > 0, t >= gapStart + gap { p.add(dx: held, dy: 0); held = 0 }
            out.append(Double(p.step(dt: frame)?.dx ?? 0))
            t += frame
        }
        return (out, sent)
    }

    @Test func gapIsBridgedAndTotalPreserved() {
        let (out, sent) = Self.simulate(gap: 0.15)
        #expect(abs(out.reduce(0, +) - sent) < 1e-6)              // total equals input
        #expect(out[0..<120].allSatisfy { $0 > -1e-9 })             // never moves backwards while the phone moves
        // First ~50 ms of the gap: the pointer keeps gliding instead of freezing.
        let gapFrames = Array(out[61..<66])
        #expect(gapFrames.allSatisfy { $0 > 0.3 })
        // Recovery after the burst is spread: no frame jumps like an unpaced 36 pt burst.
        #expect(out.max()! < 16)
        // Steady speed before the gap is untouched (2 pt per 120 Hz frame).
        #expect(abs(out[30..<58].reduce(0, +) / 28 - 2) < 0.2)
    }

    @Test func glideIsGivenBackWhenThePhoneReallyStopped() {
        // Phone stops at 0.5 s (no late packets): the glide must be returned, ending exactly where input says.
        let (out, sent) = Self.simulate(gap: 0, stopAt: 0.5)
        #expect(abs(out.reduce(0, +) - sent) < 1e-6)
        let overshoot = out.indices.map { out[0...$0].reduce(0, +) }.max()! - sent
        #expect(overshoot >= 0 && overshoot < 10)                  // small, temporary
    }

    @Test func steadyInputDoesNotGlide() {
        var p = MotionPacer()
        for f in 0..<120 {
            if f % 2 == 0 { p.add(dx: 4, dy: 0) }
            _ = p.step(dt: 1.0 / 120)
            #expect(!p.isGliding)
        }
    }

    @Test func longGapCounter() {
        var s = MessageStats()
        for t in [0.0, 0.016, 0.2, 0.216, 0.3, 5.0] { s.record("move", at: t) }  // 184 ms + 84 ms hitches; 4.7 s = a pause
        #expect(s.longGaps(now: 5.0) == 2)
        #expect(s.longGaps(now: 70) == 0)
    }
}
