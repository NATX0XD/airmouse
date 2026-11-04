import Foundation
import CoreGraphics
import Testing
@testable import AirMouseCore

@Suite struct CalibrationV3Tests {
    @Test func decodeAndEncode() {
        #expect(ProtocolCodec.decode(#"{"t":"calib","step":"point","target":"tl"}"#) == .calib(.point(.tl)))
        #expect(ProtocolCodec.decode(#"{"t":"calib","step":"pointed","target":"center"}"#) == .calib(.pointed(.center)))
        #expect(ProtocolCodec.decode(#"{"t":"calib","step":"point","target":"bl"}"#) == .calib(.point(.bl)))
        #expect(ProtocolCodec.decode(#"{"t":"calib","step":"verify"}"#) == .calib(.verify))
        #expect(ProtocolCodec.decode(#"{"t":"calib","step":"point","target":"middle"}"#) == nil)
        #expect(ProtocolCodec.encode(.calibHit(.br)) == #"{"step":"hit","t":"calib","target":"br"}"#)
    }

    @Test func targetPositions() {
        let s = ScreenInfo(w: 1000, h: 500, scale: 2, wMm: 300, hMm: 150, name: "M")
        func eq(_ a: CGPoint, _ x: Double, _ y: Double) -> Bool { abs(a.x - x) < 1e-9 && abs(a.y - y) < 1e-9 }
        #expect(eq(CalibrationGeometry.target(.center, screen: s), 500, 250))
        #expect(eq(CalibrationGeometry.target(.tl, screen: s), 80, 40))
        #expect(eq(CalibrationGeometry.target(.tr, screen: s), 920, 40))
        #expect(eq(CalibrationGeometry.target(.br, screen: s), 920, 460))
        #expect(eq(CalibrationGeometry.target(.bl, screen: s), 80, 460))
        #expect(eq(CalibrationGeometry.target(.left, screen: s), 100, 250))
        #expect(Side.fourCorners == [.center, .tl, .tr, .br, .bl])
    }

    @Test func hitRadius() {
        let s = ScreenInfo(w: 1000, h: 500, scale: 2, wMm: 300, hMm: 150, name: "M")
        #expect(CalibrationGeometry.touching(CGPoint(x: 500, y: 250), screen: s) == [.center])
        #expect(CalibrationGeometry.touching(CGPoint(x: 540, y: 250), screen: s) == [.center]) // exactly 40 pt
        #expect(CalibrationGeometry.touching(CGPoint(x: 540.5, y: 250), screen: s).isEmpty)
        #expect(CalibrationGeometry.touching(CGPoint(x: 80 + 24, y: 40 + 32), screen: s) == [.tl]) // 40 pt diagonal
        #expect(CalibrationGeometry.touching(CGPoint(x: 0, y: 0), screen: s).isEmpty)
    }

    @Test func fourCornerFlowAndVerify() {
        let s = ScreenInfo(w: 1000, h: 500, scale: 2, wMm: 300, hMm: 150, name: "M")
        var st = CalibrationState()
        st.apply(.start); st.apply(.placed)
        for (i, t) in Side.fourCorners.enumerated() {
            st.apply(.point(t))
            #expect(st.step == .point(t) && st.cornerIndex == i && st.stepNumber == 2 && !st.pointed.contains(t))
            st.apply(.pointed(t)); #expect(st.pointed.contains(t))
        }
        #expect(st.cursor(at: CGPoint(x: 500, y: 250), screen: s).isEmpty) // not verifying yet
        st.apply(.verify)
        #expect(st.step == .verify && st.stepNumber == 3 && st.verified)
        #expect(st.cursor(at: CGPoint(x: 505, y: 250), screen: s) == [.center])
        #expect(st.lit == [.center])
        #expect(st.cursor(at: CGPoint(x: 510, y: 250), screen: s).isEmpty) // first time only
        #expect(st.cursor(at: CGPoint(x: 300, y: 250), screen: s).isEmpty && st.lit.isEmpty)
        #expect(st.cursor(at: CGPoint(x: 500, y: 250), screen: s).isEmpty && st.lit == [.center])
        #expect(st.cursor(at: CGPoint(x: 920, y: 460), screen: s) == [.br])
        #expect(st.everLit == [.center, .br])
        st.apply(.done(sensitivity: 1500)); #expect(st.step == .done && st.verified && st.everLit.count == 2)
    }

    @Test func movesBlockedFromPlacedUntilCenterPointed() {
        let (s, out) = session()
        s.handle(text: #"{"t":"move","dx":1,"dy":0}"#)
        s.handle(text: #"{"t":"calib","step":"placed"}"#)
        #expect(s.movesBlocked)
        s.handle(text: #"{"t":"move","dx":50,"dy":9}"#)           // lift-off: dropped
        s.handle(text: #"{"t":"calib","step":"point","target":"center"}"#)
        s.handle(text: #"{"t":"move","dx":5,"dy":5}"#)            // still dropped while aiming at centre
        s.handle(text: #"{"t":"calib","step":"pointed","target":"center"}"#)
        #expect(!s.movesBlocked)
        s.handle(text: #"{"t":"calib","step":"point","target":"tl"}"#)
        s.handle(text: #"{"t":"move","dx":-3,"dy":-2}"#)          // live cursor during corners
        s.handle(text: #"{"t":"calib","step":"pointed","target":"tl"}"#)
        s.handle(text: #"{"t":"calib","step":"verify"}"#)
        s.handle(text: #"{"t":"move","dx":2,"dy":-1}"#)
        #expect(out.lines == ["move +1.0 +0.0", "warp 756,491", "warp 756,491", "warp 756,491", "move -3.0 -2.0", "move +2.0 -1.0"])
        #expect(!s.movesBlocked)
    }

    @Test func blockStaysUntilVerifyForOldPhones() {
        let (s, out) = session()
        s.handle(text: #"{"t":"calib","step":"placed"}"#)
        s.handle(text: #"{"t":"calib","step":"pointed","target":"left"}"#)
        s.handle(text: #"{"t":"move","dx":5,"dy":5}"#)
        #expect(s.movesBlocked && out.lines == ["warp 756,491"])
    }

    @Test(arguments: [#"{"t":"calib","step":"done","sensitivity":1}"#, #"{"t":"calib","step":"cancel"}"#,
                      #"{"t":"calib","step":"start"}"#])
    func blockClearedBy(_ msg: String) {
        let (s, _) = session()
        s.handle(text: #"{"t":"calib","step":"placed"}"#)
        s.handle(text: msg)
        #expect(!s.movesBlocked)
    }

    @Test func redoCentreRecentresAndBlocksAgain() {
        let (s, out) = session()
        for m in [#"{"t":"calib","step":"placed"}"#, #"{"t":"calib","step":"point","target":"center"}"#,
                  #"{"t":"calib","step":"pointed","target":"center"}"#, #"{"t":"calib","step":"point","target":"tl"}"#,
                  #"{"t":"move","dx":-30,"dy":-20}"#,
                  // Redo: back to the centre target
                  #"{"t":"calib","step":"point","target":"center"}"#, #"{"t":"move","dx":9,"dy":9}"#] { s.handle(text: m) }
        #expect(s.movesBlocked)
        #expect(out.lines.suffix(2) == ["move -30.0 -20.0", "warp 756,491"])
        s.handle(text: #"{"t":"calib","step":"pointed","target":"center"}"#)
        s.handle(text: #"{"t":"move","dx":0.25,"dy":-0.5}"#)
        #expect(!s.movesBlocked && out.lines.last == "move +0.2 -0.5")
    }
}
