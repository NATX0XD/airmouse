import Foundation
import Testing
@testable import AirMouseCore

// Spec 4a: placement signals, live hint, diagnostics counters.

@Suite struct PlaceDecodeTests {
    @Test func withNearAndUpright() {
        let m = ProtocolCodec.decode(#"{"t":"calib","step":"place","progress":0.4,"still":true,"near":true,"upright":false}"#)
        #expect(m == .calib(.place(progress: 0.4, still: true, near: true, upright: false)))
    }

    @Test func withoutNewFieldsIsUnknown() {
        let m = ProtocolCodec.decode(#"{"t":"calib","step":"place","progress":0.4,"still":false}"#)
        #expect(m == .calib(.place(progress: 0.4, still: false, near: nil, upright: nil)))
    }

    @Test func onlyNear() {
        let m = ProtocolCodec.decode(#"{"t":"calib","step":"place","progress":0,"still":true,"near":false}"#)
        #expect(m == .calib(.place(progress: 0, still: true, near: false, upright: nil)))
    }

    @Test func numericBoolsAndJunk() {
        #expect(ProtocolCodec.decode(#"{"t":"calib","step":"place","progress":0.2,"still":1,"near":1,"upright":0}"#)
                == .calib(.place(progress: 0.2, still: true, near: true, upright: false)))
        // non-boolean junk = unknown, not a failure
        #expect(ProtocolCodec.decode(#"{"t":"calib","step":"place","progress":0.2,"still":true,"near":"yes","upright":null}"#)
                == .calib(.place(progress: 0.2, still: true, near: nil, upright: nil)))
    }
}

@Suite struct PlaceHintTests {
    func hint(_ p: Double, still: Bool, near: Bool?, upright: Bool?) -> PlaceHint {
        PlaceHint.select(progress: p, still: still, near: near, upright: upright)
    }

    @Test func fourV2States() {
        #expect(hint(0, still: true, near: false, upright: false) == .bringCloser)
        #expect(hint(0, still: true, near: false, upright: true) == .bringCloser)
        #expect(hint(0, still: true, near: true, upright: false) == .holdUpright)
        #expect(hint(0, still: false, near: true, upright: false) == .holdUpright)
        #expect(hint(0.3, still: false, near: true, upright: true) == .holdStill)
        #expect(hint(0.65, still: true, near: true, upright: true) == .filling(0.65))
        #expect(hint(0, still: true, near: true, upright: true) == .filling(0))
    }

    @Test func legacyBehavesAsBefore() {
        #expect(hint(0, still: true, near: nil, upright: nil) == .placeInside)
        #expect(hint(0, still: false, near: nil, upright: nil) == .holdStill)
        #expect(hint(0.5, still: true, near: nil, upright: nil) == .filling(0.5))
    }

    @Test func textsAndKinds() {
        #expect(PlaceHint.bringCloser.text == "Bring your iPhone to the screen")
        #expect(PlaceHint.holdUpright.text == "Hold it upright against the display")
        #expect(PlaceHint.holdStill.text == "Hold still")
        #expect(PlaceHint.filling(0.1).kind == PlaceHint.filling(0.9).kind)
        #expect(PlaceHint.holdUpright.needsAction && !PlaceHint.bringCloser.needsAction)
    }

    @Test func stateDrainsWhenAnySignalFails() {
        var st = CalibrationState(); st.apply(.start)
        #expect(st.placeHint == .placeInside)
        st.apply(.place(progress: 0.5, still: true, near: true, upright: true))
        #expect(st.progress == 0.5 && st.placeHint == .filling(0.5))
        st.apply(.place(progress: 0.5, still: true, near: true, upright: false))
        #expect(st.progress == 0 && st.placeHint == .holdUpright && st.visible && st.step == .place)
        st.apply(.place(progress: 0.5, still: true, near: false, upright: true))
        #expect(st.progress == 0 && st.placeHint == .bringCloser)
        st.apply(.place(progress: 0.5, still: false, near: true, upright: true))
        #expect(st.progress == 0 && st.placeHint == .holdStill)
        st.apply(.placed)
        #expect(st.step == .placed && st.progress == 1)
    }
}

@Suite struct DiagnosticsTests {
    @Test func countsByTypeAndLastMove() {
        var t = 100.0
        let out = LogOutput()
        let s = ReceiverSession(output: out, screen: { mbp }, clock: { t })
        s.handle(text: #"{"t":"hello","v":3}"#)
        t = 101; s.handle(text: #"{"t":"move","dx":1,"dy":2}"#)
        t = 101.5; s.handle(text: #"{"t":"move","dx":1,"dy":2}"#)
        t = 102; s.handle(text: #"{"t":"button","b":"left","down":true}"#)
        s.handle(text: #"{"t":"calib","step":"place","progress":0.1,"still":true,"near":true}"#)
        s.handle(text: #"{"t":"nope"}"#)
        s.handle(text: "not json")
        #expect(s.stats.count("hello") == 1)
        #expect(s.stats.count("move") == 2)
        #expect(s.stats.count("button") == 1)
        #expect(s.stats.count("calib") == 1)
        #expect(s.stats.count("other") == 2)
        #expect(s.stats.count("scroll") == 0)
        #expect(s.stats.total == 7 && s.messageCount == 7)
        #expect(s.stats.lastMoveAt == 101.5)
        #expect(s.dragButton == .left)
        let d = PeerDiagnostics(id: "wifi-1", transport: .wifi, session: s)
        #expect(d.dragging == .left && d.name == "iPhone" && d.stats.total == 7)
    }

    @Test func rateWindowAndQuiet() {
        var st = MessageStats()
        for i in 0...60 { st.record("move", at: 10 + Double(i) / 60) } // 61 messages over 1.0 s
        #expect(abs(st.rate(now: 11) - 61) < 1)
        #expect(st.rate(now: 13.5) == 0) // quiet > 2 s
        #expect(MessageStats().rate(now: 1) == 0)
    }

    @Test func agoText() {
        #expect(MessageStats.ago(nil, now: 5) == "never")
        #expect(MessageStats.ago(9.8, now: 10) == "0.2 s ago")
        #expect(MessageStats.ago(0, now: 14) == "14 s ago")
        #expect(MessageStats.ago(0, now: 200) == "3 min ago")
    }

    @Test func kinds() {
        #expect(MessageStats.kind(of: .move(dx: 0, dy: 0)) == "move")
        #expect(MessageStats.kind(of: .calib(.start)) == "calib")
        #expect(MessageStats.kind(of: nil) == "other")
        #expect(Set(MessageStats.kinds).count == MessageStats.kinds.count)
    }
}
