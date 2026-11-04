import AppKit
@preconcurrency import CoreBluetooth
import Network
import AirMouseCore

enum SettingsPane {
    static let accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    static let bluetoothPrivacy = "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
    static let bluetooth = "x-apple.systempreferences:com.apple.BluetoothSettings"
    static let localNetwork = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
    static let privacy = "x-apple.systempreferences:com.apple.preference.security"
    static let firewall = "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall"

    static func open(_ s: String, fallback: String? = nil) {
        if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        if let fallback, let url = URL(string: fallback) { NSWorkspace.shared.open(url) }
    }
}

/// Local Network has no API: browse for our own Bonjour service. Found = granted,
/// browser waiting with PolicyDenied = denied.
@MainActor
final class LocalNetworkProbe {
    private(set) var status: PermissionStatus = .notDetermined
    private var browser: NWBrowser?
    private let serviceName: String
    var onChange: (() -> Void)?

    init(serviceName: String) { self.serviceName = serviceName }

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = false
        let b = NWBrowser(for: .bonjour(type: AirMouseServer.serviceType, domain: nil), using: params)
        let name = serviceName
        b.stateUpdateHandler = { [weak self] st in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch st {
                case .waiting(let e), .failed(let e):
                    if case .dns(let code) = e, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) { self.set(.denied) }
                    if case .failed = st { self.browser?.cancel(); self.browser = nil }
                default: break
                }
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.contains { r in
                if case .service(let n, _, _, _) = r.endpoint { return n == name }
                return false
            }
            MainActor.assumeIsolated { if found || !results.isEmpty { self?.set(.granted) } }
        }
        browser = b
        b.start(queue: .main)
    }

    /// Re-trigger after the user changed the setting.
    func restart() {
        browser?.cancel(); browser = nil
        start()
    }

    private func set(_ s: PermissionStatus) {
        guard s != status else { return }
        status = s
        onChange?()
    }
}

@MainActor
final class SystemPermissionChecker: PermissionChecker {
    unowned let model: AppModel
    init(model: AppModel) { self.model = model }

    nonisolated func check(_ kind: PermissionKind, completion: @escaping (PermissionStatus) -> Void) {
        // Called and completed on the main queue only (see PermissionChecker docs).
        nonisolated(unsafe) let completion = completion
        MainActor.assumeIsolated {
            switch kind {
            case .accessibility:
                completion(Accessibility.isTrusted ? .granted : .notDetermined)
            case .bluetooth:
                completion(bluetoothStatus())
            case .localNetwork:
                completion(model.localNetwork?.status ?? .notDetermined)
            case .firewall:
                let path = Bundle.main.bundlePath
                DispatchQueue.global(qos: .utility).async {
                    let global = Self.run(["--getglobalstate"])
                    let app = FirewallParser.globalState(global) == 1 ? Self.run(["--getappblocked", path]) : nil
                    let status = FirewallParser.status(global: global, app: app)
                    let detail: String = switch FirewallParser.globalState(global) {
                    case 0?: "The firewall is off. Nothing to do."
                    case 1?: status == .granted ? "AirMouse is allowed through the firewall." : "AirMouse is blocked."
                    case 2?: "Blocking all incoming connections."
                    default: "Couldn’t read the firewall state."
                    }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self.model.firewallDetail = detail }
                        completion(status)
                    }
                }
            }
        }
    }

    private func bluetoothStatus() -> PermissionStatus {
        switch CBManager.authorization {
        case .allowedAlways:
            if case .off(let why) = model.bluetooth, model.bluetoothStarted { return .off(why) }
            return .granted
        case .denied, .restricted: return .denied
        default: return .notDetermined
        }
    }

    nonisolated static func run(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/libexec/ApplicationFirewall/socketfilterfw")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
