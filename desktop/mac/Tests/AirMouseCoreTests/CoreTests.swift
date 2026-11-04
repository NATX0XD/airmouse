import Foundation
import Testing
import Darwin
@testable import AirMouseCore

let mbp = ScreenInfo(w: 1512, h: 982, scale: 2, wMm: 302.4, hMm: 196.4, name: "Test Mac")

func session() -> (ReceiverSession, LogOutput) {
    let out = LogOutput()
    return (ReceiverSession(output: out, screen: { mbp }), out)
}

@Suite struct DecodeTests {
    @Test func hello() {
        let m = ProtocolCodec.decode(#"{"t":"hello","v":3,"app":"airmouse","device":{"name":"Ghost","model":"iPhone 15","wMm":71.6,"hMm":147.6},"extra":1}"#)
        #expect(m == .hello(version: 3, device: PhoneDevice(name: "Ghost", model: "iPhone 15", wMm: 71.6, hMm: 147.6)))
    }

    @Test func helloWithoutDeviceUsesFallbackSize() {
        guard case .hello(_, let d)? = ProtocolCodec.decode(#"{"t":"hello","v":3,"device":{"wMm":"x"}}"#) else { Issue.record("no hello"); return }
        #expect(d.wMm == PhoneDevice.fallbackWMm && d.hMm == PhoneDevice.fallbackHMm && d.name == "iPhone")
    }

    @Test func everyType() {
        #expect(ProtocolCodec.decode(#"{"t":"move","dx":3,"dy":-2.5}"#) == .move(dx: 3, dy: -2.5))
        #expect(ProtocolCodec.decode(#"{"t":"button","b":"left","down":true}"#) == .button(.left, down: true))
        #expect(ProtocolCodec.decode(#"{"t":"button","b":"right","down":false}"#) == .button(.right, down: false))
        #expect(ProtocolCodec.decode(#"{"t":"scroll","dy":2}"#) == .scroll(dy: 2))
        #expect(ProtocolCodec.decode(#"{"t":"key","k":"right"}"#) == .key(.right))
        #expect(ProtocolCodec.decode(#"{"t":"center"}"#) == .center)
    }

    @Test func calibSteps() {
        let d = { (s: String) in ProtocolCodec.decode(s) }
        #expect(d(#"{"t":"calib","step":"start"}"#) == .calib(.start))
        #expect(d(#"{"t":"calib","step":"place","progress":0.6,"still":true}"#) == .calib(.place(progress: 0.6, still: true)))
        #expect(d(#"{"t":"calib","step":"place","progress":7,"still":false}"#) == .calib(.place(progress: 1, still: false)))
        #expect(d(#"{"t":"calib","step":"placed"}"#) == .calib(.placed))
        #expect(d(#"{"t":"calib","step":"point","target":"left"}"#) == .calib(.point(.left)))
        #expect(d(#"{"t":"calib","step":"pointed","target":"right"}"#) == .calib(.pointed(.right)))
        #expect(d(#"{"t":"calib","step":"done","sensitivity":1234.5}"#) == .calib(.done(sensitivity: 1234.5)))
        #expect(d(#"{"t":"calib","step":"cancel"}"#) == .calib(.cancel))
        #expect(d(#"{"t":"calib","step":"point","target":"up"}"#) == nil)
        #expect(d(#"{"t":"calib","step":"warp"}"#) == nil)
    }

    @Test(arguments: [
        "", "not json", "[1,2]", "{}", #"{"t":5}"#, #"{"t":"move","dx":"3","dy":1}"#,
        #"{"t":"move","dx":true,"dy":1}"#, #"{"t":"button","b":"middle","down":true}"#,
        #"{"t":"key","k":"pageup"}"#, #"{"t":"scroll","dy":0}"#, #"{"t":"teleport","x":1}"#, "{\"t\":\"move\"",
    ])
    func badOrUnknownIsIgnored(_ raw: String) {
        #expect(ProtocolCodec.decode(raw) == nil)
    }

    @Test func clampsHugeValues() {
        #expect(ProtocolCodec.decode(#"{"t":"move","dx":1e12,"dy":-1e12}"#) == .move(dx: 5000, dy: -5000))
        #expect(ProtocolCodec.decode(#"{"t":"scroll","dy":-999}"#) == .scroll(dy: -50))
    }
}

@Suite struct EncodeTests {
    @Test func screenRoundTrips() throws {
        let s = ProtocolCodec.encode(.screen(ScreenInfo(w: 1512, h: 982, scale: 2, wMm: 302.43, hMm: 196.44, name: "Nattakit's MacBook Pro")))
        let o = try #require(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
        #expect(o["t"] as? String == "screen")
        #expect(o["w"] as? Int == 1512 && o["h"] as? Int == 982)
        #expect(o["wMm"] as? Double == 302.4 && o["hMm"] as? Double == 196.4)
        #expect(o["scale"] as? Double == 2)
        #expect(o["name"] as? String == "Nattakit's MacBook Pro")
    }

    @Test func calibMessages() {
        #expect(ProtocolCodec.encode(.calibRequest) == #"{"step":"request","t":"calib"}"#)
        #expect(ProtocolCodec.encode(.calibCancel) == #"{"step":"cancel","t":"calib"}"#)
    }
}

@Suite struct SessionTests {
    @Test func helloRepliesWithScreen() {
        let (s, _) = session()
        var hello: PhoneDevice?
        s.onHello = { hello = $0 }
        let r = s.handle(text: #"{"t":"hello","v":3,"device":{"name":"Ghost"}}"#)
        #expect(r == [.screen(mbp)])
        #expect(hello?.name == "Ghost")
    }

    @Test func moveVsDrag() {
        let (s, out) = session()
        s.handle(text: #"{"t":"move","dx":3,"dy":-2}"#)
        s.handle(text: #"{"t":"button","b":"left","down":true}"#)
        s.handle(text: #"{"t":"move","dx":1,"dy":1}"#)
        s.handle(text: #"{"t":"button","b":"left","down":false}"#)
        s.handle(text: #"{"t":"button","b":"right","down":true}"#)
        s.handle(text: #"{"t":"move","dx":-1,"dy":0}"#)
        s.handle(text: #"{"t":"button","b":"right","down":false}"#)
        s.handle(text: #"{"t":"move","dx":0,"dy":4}"#)
        #expect(out.lines == ["move +3.0 -2.0", "button left down", "drag left +1.0 +1.0", "button left up",
                              "button right down", "drag right -1.0 +0.0", "button right up", "move +0.0 +4.0"])
    }

    @Test func leftWinsDragWhenBothHeld() {
        let (s, out) = session()
        s.handle(text: #"{"t":"button","b":"right","down":true}"#)
        s.handle(text: #"{"t":"button","b":"left","down":true}"#)
        s.handle(text: #"{"t":"move","dx":1,"dy":0}"#)
        #expect(out.lines.last == "drag left +1.0 +0.0")
    }

    @Test func duplicateDownAndStrayUpIgnored() {
        let (s, out) = session()
        s.handle(text: #"{"t":"button","b":"left","down":true}"#)
        s.handle(text: #"{"t":"button","b":"left","down":true}"#)
        s.handle(text: #"{"t":"button","b":"right","down":false}"#)
        #expect(out.lines == ["button left down"])
    }

    @Test func releaseAllOnDisconnect() {
        let (s, out) = session()
        s.handle(text: #"{"t":"button","b":"left","down":true}"#)
        s.handle(text: #"{"t":"button","b":"right","down":true}"#)
        s.disconnect()
        #expect(out.lines == ["button left down", "button right down", "button right up", "button left up"])
        #expect(s.heldButtons.isEmpty)
        s.disconnect()
        #expect(out.lines.count == 4)
    }

    @Test func scrollKeyCenter() {
        let (s, out) = session()
        s.handle(text: #"{"t":"scroll","dy":1}"#)
        s.handle(text: #"{"t":"scroll","dy":-3}"#)
        s.handle(text: #"{"t":"key","k":"left"}"#)
        s.handle(text: #"{"t":"center"}"#)
        #expect(out.lines == ["scroll +1", "scroll -3", "key left", "warp 756,491"])
    }

    @Test func calibForwardedAndWarps() {
        let (s, out) = session()
        var events: [CalibEvent] = []
        s.onCalib = { events.append($0) }
        for raw in [#"{"t":"calib","step":"start"}"#, #"{"t":"calib","step":"placed"}"#, #"{"t":"calib","step":"done","sensitivity":900}"#] {
            s.handle(text: raw)
        }
        #expect(events == [.start, .placed, .done(sensitivity: 900)])
        #expect(out.lines == ["warp 756,491", "warp 756,491"])
    }

    @Test func badJsonCountsButDoesNothing() {
        let (s, out) = session()
        #expect(s.handle(text: "{oops").isEmpty)
        #expect(s.handle(text: #"{"t":"future","x":1}"#).isEmpty)
        #expect(out.lines.isEmpty && s.messageCount == 2)
    }
}

@Suite struct GeometryTests {
    @Test func outlineFromMillimetres() {
        let r = CalibrationGeometry.outlineRect(screen: mbp, phoneWMm: 71.6, phoneHMm: 147.6)
        let ppmm = 1512 / 302.4 // 5 pt/mm
        #expect(abs(r.width - 71.6 * ppmm) < 0.001)
        #expect(abs(r.height - 147.6 * ppmm) < 0.001)
        #expect(abs(r.midX - 756) < 0.001 && abs(r.midY - 491) < 0.001)
        #expect(abs(CalibrationGeometry.cornerRadius(screen: mbp) - 60) < 0.001)
    }

    @Test func outlineShrinksToFitShortDisplays() {
        let short = ScreenInfo(w: 1000, h: 300, scale: 1, wMm: 200, hMm: 60, name: "x")
        let r = CalibrationGeometry.outlineRect(screen: short, phoneWMm: 70, phoneHMm: 140)
        #expect(abs(r.height - 276) < 0.001)
        #expect(abs(r.width / r.height - 0.5) < 0.0001)
    }

    @Test func unknownPhysicalSizeFallsBack() {
        let ext = ScreenInfo(w: 1920, h: 1080, scale: 1, wMm: 0, hMm: 0, name: "x")
        #expect(CalibrationGeometry.pointsPerMm(ext) == CalibrationGeometry.fallbackPointsPerMm)
    }

    @Test func targets() {
        let l = CalibrationGeometry.target(.left, screen: mbp)
        #expect(abs(l.x - 151.2) < 0.0001 && l.y == 491)
        #expect(abs(CalibrationGeometry.target(.right, screen: mbp).x - 1360.8) < 0.0001)
        #expect(abs(CalibrationGeometry.targetDistance(screen: mbp) - 1209.6) < 0.0001)
    }

    @Test func stateMachine() {
        var st = CalibrationState()
        st.apply(.start)
        #expect(st.visible && st.step == .place && st.stepNumber == 1)
        st.apply(.place(progress: 0.6, still: true)); #expect(st.progress == 0.6)
        st.apply(.place(progress: 0.6, still: false)); #expect(st.progress == 0 && !st.still)
        st.apply(.placed); #expect(st.step == .placed && st.progress == 1)
        st.apply(.point(.left)); #expect(st.step == .point(.left) && !st.leftHit && st.stepNumber == 2)
        st.apply(.pointed(.left)); #expect(st.leftHit)
        st.apply(.point(.right)); #expect(st.step == .point(.right) && st.leftHit && !st.rightHit)
        st.apply(.pointed(.right)); #expect(st.rightHit)
        st.apply(.done(sensitivity: 1500)); #expect(st.step == .done && st.sensitivity == 1500)
        st.apply(.cancel); #expect(!st.visible)
        st.apply(.place(progress: 0.3, still: true)); #expect(st.visible && st.step == .place && st.progress == 0.3)
    }
}

@Suite struct SupportTests {
    @Test func qrPayload() {
        let s = PairingPayload.connectURL(host: "192.168.1.42", port: 8765, name: "Nattakit's MacBook Pro")
        #expect(s == "airmouse://connect?host=192.168.1.42&port=8765&name=Nattakit%27s%20MacBook%20Pro")
        let parts = URLComponents(string: s)
        #expect(parts?.queryItems?.first(where: { $0.name == "name" })?.value == "Nattakit's MacBook Pro")
        #expect(PairingPayload.encode("a&b=c ✓") == "a%26b%3Dc%20%E2%9C%93")
    }

    @Test func portFallbackSkipsBusyPort() throws {
        // Hold a real listener on a random high port, then ask for that port.
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { p in
                bind(fd, p, len) == 0 && listen(fd, 1) == 0 && getsockname(fd, p, &len) == 0
            }
        }
        try #require(ok)
        let busy = UInt16(bigEndian: addr.sin_port)
        #expect(!PortPicker.isTCPPortFree(busy))
        let picked = try #require(PortPicker.firstFree(from: busy, count: 10))
        #expect(picked > busy && picked < busy + 10)
    }

    @Test func portFallbackLogic() {
        #expect(PortPicker.firstFree(from: 8765, isFree: { $0 >= 8767 }) == 8767)
        #expect(PortPicker.firstFree(from: 8765, count: 3, isFree: { _ in false }) == nil)
        #expect(PortPicker.candidates(from: 65534, count: 5) == [65534, 65535])
    }

    @Test func addressOrdering() {
        let items = [InterfaceAddress(interface: "bridge0", ip: "10.0.0.1"),
                     InterfaceAddress(interface: "en5", ip: "169.254.3.3"),
                     InterfaceAddress(interface: "en7", ip: "192.168.2.9"),
                     InterfaceAddress(interface: "lo0", ip: "127.0.0.1"),
                     InterfaceAddress(interface: "en0", ip: "172.20.10.3"),
                     InterfaceAddress(interface: "utun4", ip: "100.64.0.2")]
        let ordered = NetworkAddresses.order(items, routedIP: "100.64.0.2").map(\.ip)
        #expect(ordered == ["100.64.0.2", "172.20.10.3", "192.168.2.9", "10.0.0.1", "169.254.3.3"])
    }

    @Test func statusText() {
        #expect(StatusText.title(connectedTo: nil) == "Waiting for your iPhone…")
        #expect(StatusText.title(connectedTo: "Ghost") == "Connected to Ghost")
        #expect(StatusText.rate(59.6) == "60 msg/s")
        #expect(StatusText.endpoint("10.0.0.2", 8766) == "10.0.0.2:8766")
        #expect(StatusText.menuLine(connectedTo: nil, port: 8765) == "Waiting for iPhone · port 8765")
    }

    @Test func clampToDisplays() {
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let ext = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        #expect(PointerMath.clamp(CGPoint(x: 100, y: 100), to: [main, ext]) == CGPoint(x: 100, y: 100))
        #expect(PointerMath.clamp(CGPoint(x: -50, y: 2000), to: [main, ext]) == CGPoint(x: 0, y: 981))
        #expect(PointerMath.clamp(CGPoint(x: 2000, y: -500), to: [main, ext]) == CGPoint(x: 2000, y: -200))
    }

    @Test func clickCounter() {
        var c = ClickCounter()
        let p = CGPoint(x: 10, y: 10)
        #expect(c.press(.left, at: p, time: 0) == 1)
        #expect(c.press(.left, at: p, time: 0.3) == 2)
        #expect(c.press(.left, at: p, time: 0.5) == 3)
        #expect(c.press(.left, at: p, time: 2) == 1)
        #expect(c.press(.right, at: p, time: 2.1) == 1)
        #expect(c.press(.right, at: CGPoint(x: 40, y: 10), time: 2.2) == 1)
    }

    @Test func rateMeter() {
        var m = RateMeter(now: 0)
        m.add(60); m.tick(now: 1)
        #expect(m.rate == 60)
    }
}
