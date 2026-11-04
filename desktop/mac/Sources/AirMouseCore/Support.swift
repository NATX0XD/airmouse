import Foundation
import CoreGraphics
import Darwin

// MARK: - Ports

public enum PortPicker {
    public static let defaultPort: UInt16 = 8765

    public static func candidates(from start: UInt16, count: Int = 20) -> [UInt16] {
        (0..<max(1, count)).compactMap { i in
            let p = Int(start) + i
            return p <= Int(UInt16.max) ? UInt16(p) : nil
        }
    }

    public static func firstFree(from start: UInt16, count: Int = 20,
                                 isFree: (UInt16) -> Bool = isTCPPortFree) -> UInt16? {
        candidates(from: start, count: count).first(where: isFree)
    }

    /// True if nothing listens on the wildcard address (IPv4 and IPv6) for `port`.
    /// Binds without SO_REUSEADDR, so a running receiver (e.g. the Python one) makes it fail.
    public static func isTCPPortFree(_ port: UInt16) -> Bool {
        canBind(port, family: AF_INET) && canBind(port, family: AF_INET6)
    }

    static func canBind(_ port: UInt16, family: Int32) -> Bool {
        let fd = socket(family, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return family == AF_INET6 } // no IPv6 stack: not a conflict
        defer { close(fd) }
        if family == AF_INET {
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr = in_addr(s_addr: INADDR_ANY)
            return withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
        } else {
            var addr = sockaddr_in6()
            addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = port.bigEndian
            addr.sin6_addr = in6addr_any
            return withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0
                }
            }
        }
    }
}

// MARK: - QR payload

public enum PairingPayload {
    /// `airmouse://connect?host=<ip>&port=<port>&name=<urlencoded mac name>`
    public static func connectURL(host: String, port: UInt16, name: String) -> String {
        "airmouse://connect?host=\(encode(host))&port=\(port)&name=\(encode(name))"
    }

    /// RFC 3986 unreserved characters only, so `decodeURIComponent` on the phone round-trips.
    public static func encode(_ s: String) -> String {
        var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

// MARK: - Addresses

public struct InterfaceAddress: Equatable, Sendable, Hashable {
    public var interface: String
    public var ip: String
    public init(interface: String, ip: String) { self.interface = interface; self.ip = ip }

    public var isLinkLocal: Bool { ip.hasPrefix("169.254.") }
}

public enum NetworkAddresses {
    /// Routed address first, then Wi-Fi/Ethernet (en*), then the rest; link-local last.
    public static func order(_ items: [InterfaceAddress], routedIP: String?) -> [InterfaceAddress] {
        var seen = Set<String>()
        let unique = items.filter { !$0.ip.hasPrefix("127.") && seen.insert($0.ip).inserted }
        func rank(_ a: InterfaceAddress) -> Int {
            if a.ip == routedIP { return 0 }
            if a.isLinkLocal { return 4 }
            if a.interface == "en0" { return 1 }
            if a.interface.hasPrefix("en") { return 2 }
            return 3
        }
        return unique.enumerated().sorted { l, r in
            let (a, b) = (rank(l.element), rank(r.element))
            return a != b ? a < b : l.offset < r.offset
        }.map(\.element)
    }

    /// Current IPv4 addresses of up interfaces (excluding loopback), ordered.
    public static func current() -> [InterfaceAddress] {
        order(interfaces(), routedIP: routedIPv4())
    }

    static func interfaces() -> [InterfaceAddress] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var out: [InterfaceAddress] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            let flags = Int32(ifa.ifa_flags)
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let len = host.firstIndex(of: 0) ?? host.count
            let ip = String(decoding: host[..<len].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            out.append(InterfaceAddress(interface: String(cString: ifa.ifa_name), ip: ip))
        }
        return out
    }

    /// The source address the default route would use. Connecting a UDP socket sends nothing.
    static func routedIPv4() -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var dst = sockaddr_in()
        dst.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dst.sin_family = sa_family_t(AF_INET)
        dst.sin_port = UInt16(80).bigEndian
        inet_pton(AF_INET, "1.1.1.1", &dst.sin_addr)
        let ok = withUnsafePointer(to: &dst) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
        guard ok else { return nil }
        var local = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) == 0 }
        }
        guard got else { return nil }
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &local.sin_addr, &buf, socklen_t(buf.count)) != nil else { return nil }
        let len2 = buf.firstIndex(of: 0) ?? buf.count
        let ip = String(decoding: buf[..<len2].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return ip == "0.0.0.0" ? nil : ip
    }
}

// MARK: - Status text

public enum StatusText {
    public static let waiting = "Waiting for your iPhone…"

    public static func title(connectedTo name: String?) -> String {
        guard let name, !name.isEmpty else { return waiting }
        return "Connected to \(name)"
    }

    public static func rate(_ perSecond: Double) -> String {
        "\(Int(perSecond.rounded())) msg/s"
    }

    public static func endpoint(_ ip: String, _ port: UInt16) -> String { "\(ip):\(port)" }

    public static func menuLine(connectedTo name: String?, port: UInt16?) -> String {
        if let name, !name.isEmpty { return "Connected to \(name)" }
        guard let port else { return "Starting…" }
        return "Waiting for iPhone · port \(port)"
    }
}

// MARK: - Pointer helpers

public enum PointerMath {
    /// Keeps a point on some display: unchanged if inside one, else snapped to the nearest.
    public static func clamp(_ p: CGPoint, to rects: [CGRect]) -> CGPoint {
        guard !rects.isEmpty else { return p }
        var best = p, bestD = Double.infinity
        for r in rects where !r.isEmpty {
            let q = CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
            if q == p { return p }
            let d = hypot(q.x - p.x, q.y - p.y)
            if d < bestD { bestD = d; best = q }
        }
        return best
    }
}

/// Click count for double/triple clicks (macOS wants kCGMouseEventClickState set).
public struct ClickCounter: Sendable {
    public var interval: TimeInterval
    public var slop: Double
    private var last: (MouseButton, CGPoint, TimeInterval, Int)?

    public init(interval: TimeInterval = 0.5, slop: Double = 6) { self.interval = interval; self.slop = slop }

    public mutating func press(_ b: MouseButton, at p: CGPoint, time: TimeInterval) -> Int {
        var count = 1
        if let (lb, lp, lt, lc) = last, lb == b, time - lt <= interval, hypot(p.x - lp.x, p.y - lp.y) <= slop {
            count = min(lc + 1, 3)
        }
        last = (b, p, time, count)
        return count
    }
}

/// Messages per second over a sliding ~1 s window.
public struct RateMeter: Sendable {
    private var count = 0
    private var since: TimeInterval
    public private(set) var rate = 0.0
    public init(now: TimeInterval) { since = now }
    public mutating func add(_ n: Int = 1) { count += n }
    public mutating func tick(now: TimeInterval) {
        let dt = now - since
        guard dt >= 0.5 else { return }
        rate = Double(count) / dt
        count = 0; since = now
    }
}
