import Foundation
import CoreGraphics
import Testing
@testable import AirMouseCore

private func json(_ s: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
}

@Suite struct TextKeyDecodeTests {
    @Test func text() {
        #expect(ProtocolCodec.decode(#"{"t":"text","s":"Hello, สวัสดี 👋"}"#) == .text("Hello, สวัสดี 👋"))
        #expect(ProtocolCodec.decode(#"{"t":"text","s":""}"#) == nil)
        #expect(ProtocolCodec.decode(#"{"t":"text","s":5}"#) == nil)
        #expect(ProtocolCodec.decode(#"{"t":"text"}"#) == nil)
    }

    @Test func longTextIsCut() {
        let long = String(repeating: "a", count: 5000)
        #expect(ProtocolCodec.decode(#"{"t":"text","s":"\#(long)"}"#) == .text(String(repeating: "a", count: ProtocolCodec.maxText)))
    }

    @Test(arguments: [("up", 126), ("down", 125), ("backspace", 51), ("enter", 36), ("tab", 48),
                      ("escape", 53), ("space", 49), ("left", 123), ("right", 124)])
    func keys(_ k: String, _ code: Int) {
        let m = ProtocolCodec.decode(#"{"t":"key","k":"\#(k)"}"#)
        guard case .key(let key)? = m else { Issue.record("no key for \(k)"); return }
        #expect(key.rawValue == k && Int(key.virtualKey) == code)
        #expect(key.isArrow == ["up", "down", "left", "right"].contains(k))
    }

    @Test func practiceCommands() {
        #expect(ProtocolCodec.decode(#"{"t":"practice","step":"start"}"#) == .practice(.start))
        #expect(ProtocolCodec.decode(#"{"t":"practice","step":"stop"}"#) == .practice(.stop))
        #expect(ProtocolCodec.decode(#"{"t":"practice","step":"result"}"#) == nil)
        #expect(ProtocolCodec.decode(#"{"t":"practice"}"#) == nil)
    }

    @Test func sessionRoutesTextAndPractice() {
        let (s, out) = session()
        var got: [PracticeCommand] = []
        s.onPractice = { got.append($0) }
        s.handle(text: #"{"t":"text","s":"hi"}"#)
        s.handle(text: #"{"t":"key","k":"enter"}"#)
        s.handle(text: #"{"t":"practice","step":"start"}"#)
        s.handle(text: #"{"t":"focus","editable":true}"#) // Mac -> phone only: ignored
        #expect(out.lines == ["type hi", "key enter"])
        #expect(got == [.start])
        #expect(s.stats.count("text") == 1 && s.stats.count("practice") == 1 && s.stats.count("other") == 1)
    }
}

@Suite struct FocusPracticeEncodeTests {
    @Test func focus() throws {
        let o = try json(ProtocolCodec.encode(.focus(editable: true)))
        #expect(o["t"] as? String == "focus" && o["editable"] as? Bool == true)
        #expect(ProtocolCodec.encode(.focus(editable: false)) == #"{"editable":false,"t":"focus"}"#)
    }

    @Test func practiceReports() throws {
        let r = try json(ProtocolCodec.encode(.practice(.result(hits: 10, total: 12, ms: 840))))
        #expect(r["t"] as? String == "practice" && r["step"] as? String == "result")
        #expect(r["hits"] as? Int == 10 && r["total"] as? Int == 12 && r["ms"] as? Int == 840)
        let run = try json(ProtocolCodec.encode(.practice(.running(hits: 3, total: 4))))
        #expect(run["step"] as? String == "running" && run["hits"] as? Int == 3 && run["total"] as? Int == 4 && run["ms"] == nil)
        #expect(ProtocolCodec.encode(.practice(.stopped)) == #"{"step":"stop","t":"practice"}"#)
    }
}

@Suite struct FocusEditabilityTests {
    @Test(arguments: ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"])
    func textRoles(_ role: String) { #expect(FocusEditability.isEditable(role: role)) }

    @Test func others() {
        #expect(!FocusEditability.isEditable(role: nil))
        #expect(!FocusEditability.isEditable(role: ""))
        #expect(!FocusEditability.isEditable(role: "AXButton"))
        #expect(!FocusEditability.isEditable(role: "AXWebArea"))
        #expect(FocusEditability.isEditable(role: "AXWebArea", hasEditableAncestor: true))
        #expect(FocusEditability.isEditable(role: "AXGroup", valueSettable: true))
        #expect(!FocusEditability.isEditable(role: "AXSlider", valueSettable: true))
        #expect(!FocusEditability.isEditable(role: "AXCheckBox", hasEditableAncestor: true, valueSettable: true))
    }
}

@Suite struct TextChunkTests {
    @Test func chunksOf20() {
        let c = TextChunks.split(String(repeating: "x", count: 45))
        #expect(c.map(\.count) == [20, 20, 5])
        #expect(TextChunks.split("").isEmpty)
    }

    @Test func neverSplitsSurrogatePairs() {
        let s = String(repeating: "a", count: 19) + "😀" + "b"
        let c = TextChunks.split(s)
        #expect(c.map(\.count) == [19, 3])
        #expect(c.map { String(decoding: $0, as: UTF16.self) }.joined() == s)
        let thai = "สวัสดีครับ ยินดีต้อนรับสู่ AirMouse 👋🏽"
        #expect(TextChunks.split(thai).allSatisfy { $0.count <= 20 })
        #expect(TextChunks.split(thai).map { String(decoding: $0, as: UTF16.self) }.joined() == thai)
    }
}

@Suite struct PracticeGameTests {
    let size = CGSize(width: 1000, height: 800)

    @Test func layoutInsideMarginsAndSpread() {
        let g = PracticeGame(now: 0, seed: 42)
        #expect(g.targets.count == 10)
        for p in g.targets { #expect((0.1...0.9).contains(p.x) && (0.1...0.9).contains(p.y)) }
        #expect(g.targets == PracticeGame(now: 5, seed: 42).targets)
    }

    @Test func diametersShrink() {
        #expect(PracticeGame.diameter(for: 0) == 64)
        #expect(PracticeGame.diameter(for: 9) == 44)
        let ds = (0..<10).map { PracticeGame.diameter(for: $0) }
        #expect(zip(ds, ds.dropFirst()).allSatisfy { $0 > $1 })
    }

    @Test func hitsMissesAndResult() throws {
        var g = PracticeGame(now: 0, seed: 7)
        let c0 = try #require(g.currentCenter(in: size))
        #expect(g.click(at: CGPoint(x: c0.x + 40, y: c0.y), in: size, now: 0.2) == .miss)
        #expect(g.click(at: CGPoint(x: c0.x + 31, y: c0.y), in: size, now: 0.5) == .hit(index: 0))
        #expect(g.report == .running(hits: 1, total: 2))
        var t = 0.5
        for i in 1..<10 {
            t += 1
            let c = try #require(g.currentCenter(in: size))
            #expect(g.click(at: c, in: size, now: t) == .hit(index: i))
        }
        #expect(g.phase == .finished && g.currentCenter(in: size) == nil)
        #expect(g.click(at: .zero, in: size, now: 99) == .ignored)
        // (0.5 + 9 * 1.0) / 10 = 0.95 s
        #expect(g.report == .result(hits: 10, total: 11, ms: 950))
        #expect(abs(g.accuracy - 10.0 / 11.0) < 1e-9)
    }
}
