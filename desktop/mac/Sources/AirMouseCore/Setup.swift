import Foundation

// Spec 2a: permission Setup stepper. Pure state so `swift test` covers it; the app supplies
// real checks through `PermissionChecker`.

public enum PermissionKind: String, CaseIterable, Sendable {
    case accessibility, bluetooth, localNetwork, firewall

    public enum Requirement: Sendable { case required, optional, info }

    public var requirement: Requirement {
        switch self {
        case .accessibility, .localNetwork: .required
        case .bluetooth: .optional
        case .firewall: .info
        }
    }
}

public enum PermissionStatus: Equatable, Sendable {
    case checking
    case granted
    case notDetermined
    case denied
    /// Allowed but not usable right now (e.g. Bluetooth switched off).
    case off(String)
    /// Informational problem (e.g. the firewall blocks AirMouse).
    case attention(String)

    public var isGranted: Bool { self == .granted }
}

public protocol PermissionChecker: AnyObject {
    /// May call back asynchronously (firewall runs a helper process); always on the caller's queue.
    func check(_ kind: PermissionKind, completion: @escaping (PermissionStatus) -> Void)
}

public struct SetupFlow: Equatable, Sendable {
    public static let order: [PermissionKind] = [.accessibility, .bluetooth, .localNetwork, .firewall]

    public private(set) var statuses: [PermissionKind: PermissionStatus] =
        Dictionary(uniqueKeysWithValues: order.map { ($0, .checking) })
    public private(set) var index = 0
    public private(set) var skipped: Set<PermissionKind> = []

    public init() {}

    public var steps: [PermissionKind] { Self.order }
    public var isFinished: Bool { index >= Self.order.count }
    public var current: PermissionKind? { isFinished ? nil : Self.order[index] }
    public func status(_ k: PermissionKind) -> PermissionStatus { statuses[k] ?? .checking }

    public mutating func update(_ k: PermissionKind, _ s: PermissionStatus) { statuses[k] = s }

    /// Refreshes every step through the checker.
    public static func refresh(_ kinds: [PermissionKind] = order, using checker: PermissionChecker,
                               apply: @escaping (PermissionKind, PermissionStatus) -> Void) {
        for k in kinds { checker.check(k) { apply(k, $0) } }
    }

    /// Step counts as done for the checklist (green check).
    public func isSatisfied(_ k: PermissionKind) -> Bool {
        switch k.requirement {
        case .info: if case .attention = status(k) { return false }; return status(k) != .checking
        default: return status(k).isGranted
        }
    }

    /// Continue is enabled once granted; the info step can always continue once checked.
    public func canContinue(_ k: PermissionKind) -> Bool {
        k.requirement == .info ? status(k) != .checking : status(k).isGranted
    }

    /// "Skip for now" only for non-essential steps that are not granted yet.
    public func canSkip(_ k: PermissionKind) -> Bool {
        k.requirement != .required && !isSatisfied(k)
    }

    public mutating func continueStep() {
        guard let k = current, canContinue(k) else { return }
        advance()
    }

    public mutating func skipStep() {
        guard let k = current, canSkip(k) else { return }
        skipped.insert(k)
        advance()
    }

    /// Jump to a given step (e.g. from a warning row in the main window).
    public mutating func open(_ k: PermissionKind) {
        index = Self.order.firstIndex(of: k) ?? 0
    }

    /// "Set Up Later": jump to the summary page, which lists what is still missing.
    public mutating func finishLater() { index = Self.order.count }

    /// Opening Setup from scratch: start at the first step still needing attention.
    public mutating func restart() {
        index = firstPendingIndex ?? 0
    }

    public var firstPendingIndex: Int? {
        Self.order.firstIndex { !isSatisfied($0) }
    }

    public var allRequiredGranted: Bool {
        Self.order.filter { $0.requirement == .required }.allSatisfy { status($0).isGranted }
    }

    /// Everything granted / checked fine, nothing left to show.
    public var allDone: Bool { Self.order.allSatisfy(isSatisfied) }

    /// Rows for the main window, required first. Optional/info only once their check has finished.
    public var warnings: [PermissionKind] {
        Self.order.filter { k in
            let s = status(k)
            guard s != .checking, !isSatisfied(k) else { return false }
            return true
        }.sorted { ($0.requirement == .required ? 0 : 1) < ($1.requirement == .required ? 0 : 1) }
    }

    /// 1-based position for the progress indicator.
    public var stepNumber: Int { min(index, Self.order.count - 1) + 1 }

    private mutating func advance() {
        index += 1
    }

    public static func shouldShowOnLaunch(completedBefore: Bool) -> Bool { !completedBefore }
}

/// Parses `/usr/libexec/ApplicationFirewall/socketfilterfw` output (no sudo needed for reads).
public enum FirewallParser {
    /// `--getglobalstate`: "Firewall is enabled. (State = 1)" / "... disabled. (State = 0)"; State 2 = block all.
    public static func globalState(_ output: String) -> Int? {
        if let r = output.range(of: #"State = (\d)"#, options: .regularExpression) {
            return Int(output[r].filter(\.isNumber))
        }
        if output.localizedCaseInsensitiveContains("disabled") { return 0 }
        if output.localizedCaseInsensitiveContains("enabled") { return 1 }
        return nil
    }

    /// `--getappblocked <path>`: "Incoming connection to … is permitted." / "… is blocked."
    public static func appBlocked(_ output: String) -> Bool? {
        if output.localizedCaseInsensitiveContains("blocked") { return true }
        if output.localizedCaseInsensitiveContains("permitted") { return false }
        return nil
    }

    public static func status(global: String, app: String?) -> PermissionStatus {
        switch globalState(global) {
        case 0?: return .granted
        case 2?: return .attention("The firewall blocks all incoming connections")
        case 1?:
            if let app, appBlocked(app) == true { return .attention("The firewall blocks AirMouse") }
            return .granted
        default: return .granted // cannot read: do not nag
        }
    }
}

/// Sidebar sections of the single main window.
public enum AppSection: String, CaseIterable, Hashable, Sendable {
    case home, pair, permissions, calibration, about

    /// First launch, or a required permission known to be missing -> Permissions; else Home.
    /// (Local Network is only known after a Bonjour browse, so launch uses what is known synchronously.)
    public static func initial(completedSetupBefore: Bool, flow: SetupFlow) -> AppSection {
        if !completedSetupBefore { return .permissions }
        let missing = PermissionKind.allCases.contains {
            $0.requirement == .required && [.denied, .notDetermined].contains(flow.status($0))
                && $0 != .localNetwork
        }
        return missing ? .permissions : .home
    }
}

/// Last calibration result shown on the Calibration page (persisted as JSON in UserDefaults).
public struct CalibrationRecord: Codable, Equatable, Sendable {
    public var sensitivity: Double?
    public var biasOK: Bool
    public var date: Date
    public init(sensitivity: Double?, biasOK: Bool, date: Date) {
        self.sensitivity = sensitivity; self.biasOK = biasOK; self.date = date
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
    public static func decode(_ data: Data?) -> CalibrationRecord? {
        data.flatMap { try? JSONDecoder().decode(CalibrationRecord.self, from: $0) }
    }

    /// Builds the record from the overlay events of one run.
    public static func from(events: [CalibEvent], now: Date) -> CalibrationRecord? {
        guard case .done(let s)? = events.last(where: { if case .done = $0 { return true }; return false }) else { return nil }
        return CalibrationRecord(sensitivity: s, biasOK: events.contains(.placed), date: now)
    }
}
