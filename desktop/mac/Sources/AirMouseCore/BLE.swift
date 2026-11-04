import Foundation

/// Spec 2b: Mac = BLE peripheral, custom GATT service, protocol-v3 JSON per write.
public enum BLESpec {
    public static let service = "7b0e0010-7d6b-4d9c-9a31-4a2d2f9e0101"
    public static let rx = "7b0e0011-7d6b-4d9c-9a31-4a2d2f9e0101" // write / writeWithoutResponse
    public static let tx = "7b0e0012-7d6b-4d9c-9a31-4a2d2f9e0101" // notify
    public static let maxLocalNameBytes = 20

    /// `AirMouse-<short Mac name>`, ASCII, at most 20 bytes ("Nattakit's MacBook Pro" -> "AirMouse-Nattakit").
    public static func localName(macName: String) -> String {
        let prefix = "AirMouse-"
        var first = macName.split(whereSeparator: { $0 == " " }).first.map(String.init) ?? ""
        for suffix in ["'s", "’s"] where first.hasSuffix(suffix) { first.removeLast(suffix.count) }
        let ascii = first.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? first
        var short = String(ascii.unicodeScalars.filter { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") })
        if short.isEmpty { short = "Mac" }
        return String((prefix + short).prefix(maxLocalNameBytes))
    }
}

/// Transport-independent BLE logic: one `ReceiverSession` per subscribed/writing central.
/// The CoreBluetooth layer only forwards raw bytes here, so `swift test` covers it without hardware.
public final class BLEHub<Peer: Hashable> {
    public private(set) var sessions: [Peer: ReceiverSession] = [:]
    /// GATT writes per central (one write may carry several newline-separated messages).
    public private(set) var writeStats: [Peer: MessageStats] = [:]
    private let makeSession: (Peer) -> ReceiverSession
    private let clock: () -> TimeInterval
    /// Newline-framed stream per peer (the native iPhone central chunks long messages).
    private var buffers: [Peer: Data] = [:]
    /// Bluetooth benchmark per peer: start time and moves seen since.
    private var bench: [Peer: (start: TimeInterval, moves: Int)] = [:]
    static var maxBuffer: Int { 16 * 1024 }

    public init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                makeSession: @escaping (Peer) -> ReceiverSession) {
        self.makeSession = makeSession
        self.clock = clock
    }

    /// Writes per second from this central (Diagnostics).
    public func writeRate(_ peer: Peer, now: TimeInterval) -> Double { writeStats[peer]?.rate(now: now) ?? 0 }

    public func session(for peer: Peer) -> ReceiverSession {
        if let s = sessions[peer] { return s }
        let s = makeSession(peer)
        sessions[peer] = s
        return s
    }

    /// One write on rx. Two framings:
    /// - legacy: one complete JSON object per write (newline-separated objects tolerated);
    /// - stream: messages end with "\n" and may be split over several writes
    ///   (the native iPhone central chunks to the max write length).
    /// Returns encoded notifications to send back on tx.
    public func received(_ value: Data, from peer: Peer) -> [Data] {
        let s = session(for: peer)
        writeStats[peer, default: MessageStats()].record("write", at: clock())
        var lines: [Data] = []
        if buffers[peer] == nil, !value.contains(0x0A) {
            if Self.isJSONObject(value) { lines = [value] } else { buffers[peer] = value } // first chunk of a long message
        } else {
            var buf = (buffers[peer] ?? Data()) + value
            while let i = buf.firstIndex(of: 0x0A) {
                let line = buf[buf.startIndex..<i]
                if !line.isEmpty { lines.append(Data(line)) }
                buf = Data(buf[buf.index(after: i)...])
            }
            // Legacy "a\nb" without a final newline: a complete trailing object is a whole message.
            if !buf.isEmpty, Self.isJSONObject(buf) { lines.append(buf); buf = Data() }
            buffers[peer] = buf.isEmpty || buf.count > Self.maxBuffer ? nil : buf
        }
        var replies: [Data] = []
        for line in lines {
            if let r = benchLine(line, from: peer) { replies.append(r); continue }
            replies += s.handle(text: String(decoding: line, as: UTF8.self)).map(Self.encode)
        }
        return replies
    }

    static func isJSONObject(_ d: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: d)) is [String: Any]
    }

    /// `{"t":"bench","step":"start"|"end"}`: count moves in between and answer
    /// `{"t":"benchResult","moves","seconds","hz"}` (Mac-side receive rate).
    /// Moves are still handled normally. nil = not a bench line.
    private func benchLine(_ line: Data, from peer: Peer) -> Data? {
        if line.starts(with: Data(#"{"t":"move""#.utf8)) {
            bench[peer]?.moves += 1
            return nil
        }
        guard line.starts(with: Data(#"{"t":"bench""#.utf8)),
              let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
        if o["step"] as? String == "start" {
            bench[peer] = (clock(), 0)
            return Data(#"{"t":"benchResult","step":"started"}"#.utf8)
        }
        guard let b = bench.removeValue(forKey: peer) else { return Data(#"{"t":"benchResult","moves":0,"seconds":0,"hz":0}"#.utf8) }
        let secs = max(0.001, clock() - b.start)
        let hz = (Double(b.moves) / secs * 10).rounded() / 10
        return Data(#"{"t":"benchResult","moves":\#(b.moves),"seconds":\#((secs * 100).rounded() / 100),"hz":\#(hz)}"#.utf8)
    }

    /// Central subscribed to tx: reply with `screen` straight away.
    public func subscribed(_ peer: Peer, screen: ScreenInfo) -> [Data] {
        _ = session(for: peer)
        return [Self.encode(.screen(screen))]
    }

    /// Central unsubscribed / disconnected: release its buttons and forget it.
    public func disconnected(_ peer: Peer) {
        sessions.removeValue(forKey: peer)?.disconnect()
        writeStats[peer] = nil
        buffers[peer] = nil
        bench[peer] = nil
    }

    public static func encode(_ msg: OutboundMessage) -> Data { Data(ProtocolCodec.encode(msg).utf8) }

    /// A long write (bigger than the ATT MTU) reaches the peripheral as several
    /// requests of one central with growing offsets: glue them back together.
    /// Parts at offset 0 (or not continuing the previous part) start a new value.
    public static func assemble(_ parts: [(Peer, Int, Data)]) -> [(Peer, Data)] {
        var out: [(Peer, Data)] = []
        for (peer, offset, data) in parts {
            if offset > 0, let last = out.last, last.0 == peer, last.1.count == offset {
                out[out.count - 1].1.append(data)
            } else {
                out.append((peer, data))
            }
        }
        return out
    }
}
