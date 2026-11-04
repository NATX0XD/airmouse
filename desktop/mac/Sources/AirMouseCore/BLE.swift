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
    private let makeSession: (Peer) -> ReceiverSession

    public init(makeSession: @escaping (Peer) -> ReceiverSession) { self.makeSession = makeSession }

    public func session(for peer: Peer) -> ReceiverSession {
        if let s = sessions[peer] { return s }
        let s = makeSession(peer)
        sessions[peer] = s
        return s
    }

    /// One write on rx. Normally one JSON object; newline-separated objects are tolerated too.
    /// Returns encoded notifications to send back on tx.
    public func received(_ value: Data, from peer: Peer) -> [Data] {
        let s = session(for: peer)
        let text = String(decoding: value, as: UTF8.self)
        let parts = text.contains("\n") ? text.split(separator: "\n").map(String.init) : [text]
        return parts.flatMap { s.handle(text: $0) }.map(Self.encode)
    }

    /// Central subscribed to tx: reply with `screen` straight away.
    public func subscribed(_ peer: Peer, screen: ScreenInfo) -> [Data] {
        _ = session(for: peer)
        return [Self.encode(.screen(screen))]
    }

    /// Central unsubscribed / disconnected: release its buttons and forget it.
    public func disconnected(_ peer: Peer) {
        sessions.removeValue(forKey: peer)?.disconnect()
    }

    public static func encode(_ msg: OutboundMessage) -> Data { Data(ProtocolCodec.encode(msg).utf8) }
}
