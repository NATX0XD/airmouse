import Foundation
import CoreGraphics
import Testing
@testable import AirMouseCore

@Suite struct ScrollTests {
    @Test func decode() {
        #expect(ProtocolCodec.decode(#"{"t":"scroll","dy":12.5,"dx":-3.25,"phase":"move"}"#) == .smoothScroll(dx: -3.25, dy: 12.5, phase: .move))
        #expect(ProtocolCodec.decode(#"{"t":"scroll","dy":4,"phase":"begin"}"#) == .smoothScroll(dx: 0, dy: 4, phase: .begin))
        #expect(ProtocolCodec.decode(#"{"t":"scroll","phase":"end"}"#) == .smoothScroll(dx: 0, dy: 0, phase: .end))
        #expect(ProtocolCodec.decode(#"{"t":"scroll","dy":0,"phase":"momentum"}"#) == .smoothScroll(dx: 0, dy: 0, phase: .momentum))
        #expect(ProtocolCodec.decode(#"{"t":"scroll","dy":3,"phase":"fling"}"#) == nil)
        // Legacy (no phase) unchanged: notches, rounded.
        #expect(ProtocolCodec.decode(#"{"t":"scroll","dy":2.4}"#) == .scroll(dy: 2))
        #expect(ProtocolCodec.decode(#"{"t":"scroll","dy":1e9,"phase":"move"}"#) == .smoothScroll(dx: 0, dy: 4000, phase: .move))
    }

    @Test func sessionRoutesAndCounts() {
        let (s, out) = session()
        s.handle(text: #"{"t":"scroll","dy":2.5,"phase":"move"}"#)
        s.handle(text: #"{"t":"scroll","dy":1}"#)
        #expect(out.lines == ["scroll move +0.0 +2.5", "scroll +1"])
        #expect(s.stats.count("scroll") == 2)
    }

    static func run(_ p: inout ScrollPacer, frames: Int) -> [ScrollFrame] {
        var out: [ScrollFrame] = []
        for _ in 0..<frames { out += p.step(dt: 1.0 / 120) }
        return out
    }

    @Test func gesturePhasesAndTotal() {
        var p = ScrollPacer()
        var all: [ScrollFrame] = []
        p.add(dx: 0, dy: 0, phase: .begin)
        for _ in 0..<10 {                                   // 20 Hz finger moves, 10 pt each
            p.add(dx: 0, dy: 10, phase: .move)
            all += Self.run(&p, frames: 6)
        }
        p.add(dx: 0, dy: 0, phase: .end)
        all += Self.run(&p, frames: 12)
        // momentum fling from the phone, then its final zero
        for v in [8.0, 6, 4, 2] { p.add(dx: 0, dy: v, phase: .momentum); all += Self.run(&p, frames: 6) }
        p.add(dx: 0, dy: 0, phase: .momentum)
        all += Self.run(&p, frames: 12)

        let touch = all.filter { $0.scrollPhase != 0 }
        let momentum = all.filter { $0.momentumPhase != 0 }
        #expect(touch.first?.scrollPhase == ScrollEventPhase.began)
        #expect(touch.last == ScrollFrame(dx: 0, dy: 0, scrollPhase: ScrollEventPhase.ended))
        #expect(touch.dropFirst().dropLast().allSatisfy { $0.scrollPhase == ScrollEventPhase.changed })
        #expect(momentum.first?.momentumPhase == ScrollEventPhase.momentumBegin)
        #expect(momentum.last == ScrollFrame(dx: 0, dy: 0, momentumPhase: ScrollEventPhase.momentumEnd))
        #expect(momentum.dropFirst().dropLast().allSatisfy { $0.momentumPhase == ScrollEventPhase.momentumContinue })
        #expect(all.allSatisfy { $0.scrollPhase == 0 || $0.momentumPhase == 0 })   // never both
        #expect(abs(touch.map(\.dy).reduce(0, +) - 100) < 1e-6)
        #expect(abs(momentum.map(\.dy).reduce(0, +) - 20) < 1e-6)
        #expect(p.isIdle)
    }

    @Test func burstsAreSpreadEvenly() {
        var p = ScrollPacer()
        p.add(dx: 0, dy: 0, phase: .begin)
        var frames: [Double] = []
        for i in 0..<20 {
            // 20 Hz, but packets arrive in pairs every 100 ms
            if i % 2 == 1 { p.add(dx: 0, dy: 15, phase: .move); p.add(dx: 0, dy: 15, phase: .move) }
            for _ in 0..<6 { frames.append(p.step(dt: 1.0 / 120).map(\.dy).reduce(0, +)) }
        }
        let mid = Array(frames[40..<110])
        #expect(mid.max()! < 10)                             // a 30 pt burst never lands in one frame
        #expect(mid.filter { $0 > 0 }.count > 50)
    }

    @Test func noGiveBackAfterEnd() {
        var p = ScrollPacer()
        p.add(dx: 0, dy: 40, phase: .begin)
        p.add(dx: 0, dy: 0, phase: .end)
        let out = Self.run(&p, frames: 120)
        #expect(out.allSatisfy { $0.dy >= 0 })
        #expect(abs(out.map(\.dy).reduce(0, +) - 40) < 1e-6)
        #expect(p.isIdle)
    }

    @Test func newGestureClosesMomentumFirst() {
        var p = ScrollPacer()
        p.add(dx: 0, dy: 5, phase: .momentum)
        _ = Self.run(&p, frames: 2)
        p.add(dx: 0, dy: 1, phase: .begin)                   // finger touches during the fling
        let out = Self.run(&p, frames: 3)
        let endIdx = out.firstIndex { $0.momentumPhase == ScrollEventPhase.momentumEnd }
        let beganIdx = out.firstIndex { $0.scrollPhase == ScrollEventPhase.began }
        #expect(endIdx != nil && beganIdx != nil && endIdx! < beganIdx!)
    }

    @Test func lostEndTimesOut() {
        var p = ScrollPacer()
        p.add(dx: 0, dy: 6, phase: .move)
        let out = Self.run(&p, frames: 140)                 // > 1 s with no end
        #expect(out.last?.scrollPhase == ScrollEventPhase.ended)
        #expect(p.isIdle)
    }

    @Test func legacyNotchesArePhaselessPoints() {
        var p = ScrollPacer()
        p.addLegacy(lines: 2)
        let out = Self.run(&p, frames: 30)
        #expect(out.allSatisfy { $0.scrollPhase == 0 && $0.momentumPhase == 0 })
        #expect(abs(out.map(\.dy).reduce(0, +) - 24) < 1e-6)
        #expect(p.isIdle)
    }
}
