import Foundation
import Testing
@testable import AirMouseCore

@Suite struct BLETests {
    func hub() -> (BLEHub<String>, LogOutput) {
        let out = LogOutput()
        return (BLEHub<String> { _ in ReceiverSession(output: out, screen: { mbp }) }, out)
    }

    @Test func jsonPerWriteRoutesToHandler() throws {
        let (h, out) = hub()
        let replies = h.received(Data(#"{"t":"hello","v":3,"device":{"name":"Ghost"}}"#.utf8), from: "A")
        let first = try #require(replies.first)
        let o = try #require(try JSONSerialization.jsonObject(with: first) as? [String: Any])
        #expect(o["t"] as? String == "screen" && o["wMm"] as? Double == 302.4)
        #expect(h.received(Data(#"{"t":"move","dx":2,"dy":1}"#.utf8), from: "A").isEmpty)
        _ = h.received(Data(#"{"t":"button","b":"left","down":true}"#.utf8), from: "A")
        _ = h.received(Data(#"{"t":"move","dx":1,"dy":0}"#.utf8), from: "A")
        _ = h.received(Data("garbage\u{FF}".utf8), from: "A")
        #expect(out.lines == ["move +2.0 +1.0", "button left down", "drag left +1.0 +0.0"])
        #expect(h.sessions["A"]?.device?.name == "Ghost")
    }

    @Test func newlineSeparatedWritesTolerated() {
        let (h, out) = hub()
        _ = h.received(Data("{\"t\":\"key\",\"k\":\"left\"}\n{\"t\":\"scroll\",\"dy\":1}".utf8), from: "A")
        #expect(out.lines == ["key left", "scroll +1"])
    }

    @Test func subscribeSendsScreenAndDisconnectReleases() {
        let (h, out) = hub()
        let r = h.subscribed("B", screen: mbp)
        #expect(String(decoding: r[0], as: UTF8.self).contains(#""t":"screen""#))
        _ = h.received(Data(#"{"t":"button","b":"right","down":true}"#.utf8), from: "B")
        h.disconnected("B")
        #expect(out.lines == ["button right down", "button right up"])
        #expect(h.sessions.isEmpty)
    }

    @Test func peersAreIndependent() {
        let (h, out) = hub()
        _ = h.received(Data(#"{"t":"button","b":"left","down":true}"#.utf8), from: "A")
        _ = h.received(Data(#"{"t":"move","dx":1,"dy":1}"#.utf8), from: "B")
        #expect(out.lines.last == "move +1.0 +1.0")
    }

    @Test func localName() {
        #expect(BLESpec.localName(macName: "Nattakit's MacBook Pro") == "AirMouse-Nattakit")
        #expect(BLESpec.localName(macName: "Nattakit’s MacBook Air") == "AirMouse-Nattakit")
        #expect(BLESpec.localName(macName: "") == "AirMouse-Mac")
        #expect(BLESpec.localName(macName: "Supercalifragilistic Mac").utf8.count <= 20)
        let thai = BLESpec.localName(macName: "\u{0E13}\u{0E31}\u{0E10} Mac")
        #expect(thai.allSatisfy(\.isASCII) && thai.hasPrefix("AirMouse-"))
    }

    @Test func longWritePartsAreReassembled() {
        let a = Data(#"{"t":"hello","v":3,"#.utf8)
        let b = Data(#""device":{"name":"Ghost"}}"#.utf8)
        let joined = BLEHub<String>.assemble([("A", 0, a), ("A", a.count, b), ("B", 0, Data("x".utf8))])
        #expect(joined.count == 2)
        #expect(joined[0].0 == "A" && joined[0].1 == a + b)
        #expect(joined[1].0 == "B")
        // A part that doesn't continue the previous one starts a new value.
        #expect(BLEHub<String>.assemble([("A", 0, a), ("A", 3, b)]).count == 2)
    }

    @Test func fractionalMoveOverBLE() throws {
        let (h, out) = hub()
        _ = h.received(Data(#"{"t":"move","dx":0.27,"dy":-1.5}"#.utf8), from: "A")
        #expect(out.lines.last == "move +0.3 -1.5") // floats reach the output (log prints 1 dp)
    }

    @Test func newlineFramedChunksAreRejoined() {
        let (h, out) = hub()
        let msg = Data(#"{"t":"button","b":"left","down":true}"#.utf8) + Data([0x0A])
        _ = h.received(msg.prefix(10), from: "A")
        #expect(out.lines.isEmpty)
        _ = h.received(msg.dropFirst(10), from: "A")
        #expect(out.lines == ["button left down"])
        // Two framed messages in one write, then a legacy single-JSON write.
        _ = h.received(Data((#"{"t":"move","dx":1,"dy":0}"# + "\n" + #"{"t":"button","b":"left","down":false}"# + "\n").utf8), from: "A")
        _ = h.received(Data(#"{"t":"move","dx":2,"dy":0}"#.utf8), from: "A")
        #expect(Array(out.lines.suffix(3)) == ["drag left +1.0 +0.0", "button left up", "move +2.0 +0.0"])
    }

    @Test func benchReportsReceiveRate() throws {
        nonisolated(unsafe) var now = 100.0
        let out = LogOutput()
        let h = BLEHub<String>(clock: { now }) { _ in ReceiverSession(output: out, screen: { mbp }) }
        _ = h.received(Data((#"{"t":"bench","step":"start"}"# + "\n").utf8), from: "A")
        for _ in 0..<120 { _ = h.received(Data((#"{"t":"move","dx":0,"dy":0}"# + "\n").utf8), from: "A") }
        now += 2
        let r = try #require(h.received(Data((#"{"t":"bench","step":"end"}"# + "\n").utf8), from: "A").first)
        let o = try #require(try JSONSerialization.jsonObject(with: r) as? [String: Any])
        #expect(o["t"] as? String == "benchResult" && o["moves"] as? Int == 120 && o["hz"] as? Double == 60)
    }
}
