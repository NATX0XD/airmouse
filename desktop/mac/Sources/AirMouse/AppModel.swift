import AppKit
@preconcurrency import CoreBluetooth
import Observation
import AirMouseCore

struct PhoneSummary: Identifiable, Equatable {
    let id: Int
    var name: String
    var model: String?
    var device: PhoneDevice
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // Server
    var port: UInt16?
    var serverError: String?
    var phones: [PhoneSummary] = []          // Wi-Fi
    var blePhones: [PhoneSummary] = []       // Bluetooth
    var bluetooth: BluetoothPeripheral.State = .off("Not set up")
    var bluetoothStarted = false
    var rate = 0.0

    // System
    var accessibilityTrusted = true
    var addresses: [InterfaceAddress] = []
    var macName: String
    var screen: ScreenInfo

    // UI
    var calibration = CalibrationState()
    /// Click Practice (nil = closed).
    var practice: PracticeGame?
    var banner: String?
    var copied = false

    // Setup stepper (spec 2a)
    var setup = SetupFlow()
    var firewallDetail = "Checking the firewall…"
    var section: AppSection = .home
    // Onboarding (spec 2) + coach-mark tour
    var onboarding: OnboardingFlow?
    var tour: TourFlow?
    @ObservationIgnored let store = OnboardingStore()
    var setupVisible: Bool { section == .permissions }
    var lastCalibration: CalibrationRecord? = CalibrationRecord.decode(UserDefaults.standard.data(forKey: "lastCalibration.v1"))
    @ObservationIgnored private var calibEvents: [CalibEvent] = []
    @ObservationIgnored var localNetwork: LocalNetworkProbe?
    @ObservationIgnored private var checker: SystemPermissionChecker?
    @ObservationIgnored private var lastFirewallCheck = 0.0
    static let setupDoneKey = "setupCompleted.v1"
    var setupCompletedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: Self.setupDoneKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.setupDoneKey) }
    }

    @ObservationIgnored private var server: AirMouseServer?
    @ObservationIgnored private var ble: BluetoothPeripheral?
    @ObservationIgnored private var output: PointerOutput?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var meter = RateMeter(now: ProcessInfo.processInfo.systemUptime)
    @ObservationIgnored private var timers: [Timer] = []
    @ObservationIgnored private var hideWork: DispatchWorkItem?
    @ObservationIgnored private var bannerWork: DispatchWorkItem?
    @ObservationIgnored var overlay: OverlayController?
    @ObservationIgnored var practiceOverlay: PracticeOverlayController?
    /// Last `focus` sent to the phones (nil = send on the next poll).
    @ObservationIgnored private var lastFocus: Bool?
    /// Calibration v3 verify: polls the real cursor while the check dots are up.
    @ObservationIgnored private var verifyTimer: Timer?

    init() {
        let name = MacInfo.computerName
        macName = name
        screen = Displays.mainScreenInfo(name: name)
    }

    var allPhones: [PhoneSummary] { phones + blePhones }
    var primaryPhone: PhoneSummary? { allPhones.last }
    var isConnected: Bool { primaryPhone != nil }
    var primaryViaBluetooth: Bool { primaryPhone.map { p in blePhones.contains { $0.id == p.id } } ?? false }
    var primaryAddress: InterfaceAddress? { addresses.first }
    var pairingURL: String? {
        guard let ip = primaryAddress?.ip, let port else { return nil }
        return PairingPayload.connectURL(host: ip, port: port, name: macName)
    }

    // MARK: lifecycle (GUI only)

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let out = CGEventOutput()
        output = out
        accessibilityTrusted = Accessibility.isTrusted
        addresses = NetworkAddresses.current()
        overlay = OverlayController(model: self)
        practiceOverlay = PracticeOverlayController(model: self)

        let server = AirMouseServer(preferredPort: PortPicker.defaultPort, serviceName: macName) { [unowned self] in
            ReceiverSession(output: out, screen: { [unowned self] in self.screen })
        }
        server.onState = { [unowned self] st in
            switch st {
            case .listening(let p): port = p; serverError = nil; localNetwork?.start()
            case .failed(let msg): port = nil; serverError = msg
            default: break
            }
        }
        server.onConnect = { [unowned self] client in
            client.session.onHello = { [unowned self] device in
                if let i = phones.firstIndex(where: { $0.id == client.id }) {
                    phones[i].name = device.name; phones[i].model = device.model; phones[i].device = device
                }
                focusAfterHello()
            }
            client.session.onCalib = { [unowned self] event in apply(event) }
            client.session.onPractice = { [unowned self] c in handlePractice(c) }
            phones.append(PhoneSummary(id: client.id, name: "iPhone", model: nil, device: PhoneDevice()))
        }
        server.onDisconnect = { [unowned self] client in
            phones.removeAll { $0.id == client.id }
            if allPhones.isEmpty, calibration.visible { apply(.cancel) }
        }
        server.onMessage = { [unowned self] _ in meter.add() }
        self.server = server
        server.start()
        // Bluetooth starts only when already allowed, or from the Setup step (that shows the prompt in context).
        if CBManager.authorization == .allowedAlways { startBluetooth() }

        let probe = LocalNetworkProbe(serviceName: macName)
        probe.onChange = { [unowned self] in refreshPermissions([.localNetwork]) }
        localNetwork = probe
        checker = SystemPermissionChecker(model: self)
        refreshPermissions(SetupFlow.order)
        if store.shouldShowOnboarding { onboarding = OnboardingFlow() } else { chooseLaunchSection() }

        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { [unowned self] in
                meter.tick(now: ProcessInfo.processInfo.systemUptime)
                if rate != meter.rate { rate = meter.rate }
            }
        })
        // Live permission status: cheap checks every 1.5 s, the firewall helper at most every 6 s while Setup is open.
        timers.append(Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated { [unowned self] in
                var kinds: [PermissionKind] = [.accessibility, .bluetooth, .localNetwork]
                let now = ProcessInfo.processInfo.systemUptime
                if setupVisible, now - lastFirewallCheck > 6 { kinds.append(.firewall) }
                refreshPermissions(kinds)
            }
        })
        // Text-input focus for the phone keyboard: AX poll only while a phone is connected and we are trusted.
        timers.append(Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            MainActor.assumeIsolated { [unowned self] in pollFocus() }
        })
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [unowned self] in
                localNetwork?.restart()
                refreshPermissions(SetupFlow.order)
            }
        }
        timers.append(Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated { [unowned self] in
                let a = NetworkAddresses.current()
                if a != addresses { addresses = a }
            }
        })
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { [unowned self] in screensChanged() }
        }
    }

    func stop() { server?.stop(); ble?.stop() }

    // MARK: permissions

    func refreshPermissions(_ kinds: [PermissionKind]) {
        guard let checker else { return }
        if kinds.contains(.firewall) { lastFirewallCheck = ProcessInfo.processInfo.systemUptime }
        SetupFlow.refresh(kinds, using: checker) { [weak self] k, st in
            guard let self else { return }
            MainActor.assumeIsolated {
                if self.setup.status(k) != st { self.setup.update(k, st) }
                if k == .accessibility, self.accessibilityTrusted != st.isGranted { self.accessibilityTrusted = st.isGranted }
            }
        }
    }

    /// Primary button of a Setup step.
    func grant(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            Accessibility.requestAndOpenSettings()
        case .bluetooth:
            switch setup.status(.bluetooth) {
            case .notDetermined: startBluetooth()
            case .off: SettingsPane.open(SettingsPane.bluetooth)
            default: SettingsPane.open(SettingsPane.bluetoothPrivacy, fallback: SettingsPane.privacy)
            }
        case .localNetwork:
            // The system prompt only appears once (on first browse/listen); after that the pane is the only way.
            localNetwork?.restart()
            SettingsPane.open(SettingsPane.localNetwork, fallback: SettingsPane.privacy)
        case .firewall:
            SettingsPane.open(SettingsPane.firewall)
        }
        refreshPermissions([kind])
    }

    func openSetup(at kind: PermissionKind? = nil) {
        if let kind { setup.open(kind) } else { setup.restart() }
        section = .permissions
        refreshPermissions(SetupFlow.order)
    }

    // MARK: onboarding + tour

    func onboardingNext() {
        guard var f = onboarding else { return }
        f.next()
        if f.isFinished { finishOnboarding() } else { onboarding = f }
    }

    func onboardingBack() { onboarding?.back() }

    func finishOnboarding() {
        onboarding = nil
        store.onboardingDone = true
        setupCompletedBefore = true
        section = .home
        startTourIfNeeded(after: 0.7)
    }

    func showWelcome() { tour = nil; onboarding = OnboardingFlow() }

    func showHowItWorks() { tour = nil; onboarding = OnboardingFlow(pages: [.howItWorks]) }

    func startTourIfNeeded(after delay: Double = 0.7) {
        guard onboarding == nil, store.shouldStartTour, tour == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.onboarding == nil, self.tour == nil, self.store.shouldStartTour else { return }
            self.startTour()
        }
    }

    func startTour() {
        onboarding = nil
        section = .home
        tour = TourFlow()
    }

    func tourNext() {
        guard var t = tour else { return }
        t.next()
        if t.isFinished { endTour() } else { tour = t }
    }

    func endTour() {
        tour = nil
        store.tourDone = true
    }

    /// Called once when the main window first appears.
    func chooseLaunchSection() {
        section = AppSection.initial(completedSetupBefore: setupCompletedBefore, flow: setup)
        if section == .permissions { setup.restart() }
        setupCompletedBefore = true
    }

    func startBluetooth() {
        guard !bluetoothStarted, let out = output else { return }
        bluetoothStarted = true
        let hub = BLEHub<UUID> { [unowned self] _ in
            let s = ReceiverSession(output: out, screen: { [unowned self] in self.screen })
            s.onCalib = { [unowned self] event in apply(event) }
            s.onPractice = { [unowned self] c in handlePractice(c) }
            s.onHello = { [unowned self] _ in focusAfterHello() }
            return s
        }
        let ble = BluetoothPeripheral(localName: BLESpec.localName(macName: macName), screen: { [unowned self] in screen }, hub: hub)
        ble.onState = { [unowned self] st in bluetooth = st; refreshPermissions([.bluetooth]) }
        ble.onMessage = { [unowned self] in meter.add() }
        ble.onPeerChange = { [unowned self, unowned ble] in
            var next: [PhoneSummary] = []
            for (uuid, session) in ble.hub.sessions {
                let id = bleID(uuid)
                let d = session.device ?? PhoneDevice()
                next.append(PhoneSummary(id: id, name: session.device?.name ?? "iPhone", model: d.model, device: d))
            }
            // keep connection order stable
            next.sort { a, b in (blePhones.firstIndex { $0.id == a.id } ?? .max) < (blePhones.firstIndex { $0.id == b.id } ?? .max) }
            if next != blePhones { blePhones = next }
            if allPhones.isEmpty, calibration.visible { apply(.cancel) }
        }
        self.ble = ble
    }

    // MARK: diagnostics (About > Diagnostics, polled ~4 Hz only while visible)

    /// Fixed snapshot for offscreen previews.
    @ObservationIgnored var previewDiagnostics: (now: TimeInterval, peers: [PeerDiagnostics])?
    /// Pointer pacer frame rate (0 = idle). Previews set a fixed value.
    @ObservationIgnored var previewPacerFPS: Double?
    var pacerFPS: Double { previewPacerFPS ?? (output as? CGEventOutput)?.pacerFPS ?? 0 }
    var overlayShowing: Bool { overlay?.isShowing ?? calibration.visible }

    func diagnostics() -> (now: TimeInterval, peers: [PeerDiagnostics]) {
        if let previewDiagnostics { return previewDiagnostics }
        var peers: [PeerDiagnostics] = []
        for c in (server?.clients.values.sorted { $0.id < $1.id } ?? []) {
            peers.append(PeerDiagnostics(id: "wifi-\(c.id)", transport: .wifi, session: c.session))
        }
        for (uuid, session) in (ble?.hub.sessions ?? [:]).sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            var d = PeerDiagnostics(id: "ble-\(uuid.uuidString)", transport: .bluetooth, session: session)
            d.writeHz = ble?.hub.writeRate(uuid, now: ProcessInfo.processInfo.systemUptime)
            peers.append(d)
        }
        return (ProcessInfo.processInfo.systemUptime, peers)
    }

    /// BLE peers get negative ids so they never collide with WebSocket client ids.
    private func bleID(_ uuid: UUID) -> Int { -abs(uuid.hashValue % 1_000_000_000) - 1 }

    private func broadcast(_ msg: OutboundMessage) {
        server?.broadcast(msg)
        ble?.broadcast(msg)
    }

    private func screensChanged() {
        let s = Displays.mainScreenInfo(name: macName)
        guard s != screen else { return }
        screen = s
        broadcast(.screen(s))
    }

    // MARK: calibration

    func apply(_ event: CalibEvent) {
        hideWork?.cancel()
        if event == .start, practice != nil { stopPractice(notifyPhone: true) }
        if event == .start { calibEvents = [] }
        calibEvents.append(event)
        if case .done = event, let r = CalibrationRecord.from(events: calibEvents, now: Date()) {
            lastCalibration = r
            UserDefaults.standard.set(r.encoded(), forKey: "lastCalibration.v1")
        }
        calibration.apply(event)
        overlay?.sync()
        syncVerifyPolling()
        if case .done = event {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.calibration.step == .done else { return }
                self.calibration.visible = false
                self.overlay?.sync()
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
        }
    }

    private func syncVerifyPolling() {
        let want = calibration.visible && calibration.step == .verify
        if want, verifyTimer == nil {
            verifyTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
                MainActor.assumeIsolated { [unowned self] in pollVerifyCursor() }
            }
            pollVerifyCursor()
        } else if !want, let t = verifyTimer {
            t.invalidate()
            verifyTimer = nil
        }
    }

    /// NSEvent.mouseLocation is global Cocoa (bottom-left origin of the main display) -> display-local top-left points.
    private func pollVerifyCursor() {
        guard let main = NSScreen.screens.first else { return }
        let m = NSEvent.mouseLocation
        let p = CGPoint(x: m.x - main.frame.minX, y: main.frame.maxY - m.y)
        var st = calibration
        let fresh = st.cursor(at: p, screen: screen)
        if st != calibration { calibration = st }
        for t in fresh { broadcast(.calibHit(t)) }
    }

    /// Mac-side "Calibrate": the phone opens its flow and drives the overlay.
    func requestCalibration() {
        guard isConnected else {
            showBanner("Connect your iPhone first, then press Calibrate again.")
            return
        }
        broadcast(.calibRequest)
    }

    /// Esc / Cancel on the overlay.
    func cancelCalibrationFromMac() {
        broadcast(.calibCancel)
        apply(.cancel)
    }

    // MARK: focus (Mac -> phone `focus`)

    private func pollFocus() {
        guard isConnected, accessibilityTrusted, Accessibility.isTrusted else { lastFocus = nil; return }
        let editable = FocusedElement.isEditable()
        guard editable != lastFocus else { return }
        lastFocus = editable
        broadcast(.focus(editable: editable))
    }

    /// Spec: send `focus` once right after hello (the reply `screen` goes first).
    private func focusAfterHello() {
        lastFocus = nil
        DispatchQueue.main.async { [weak self] in self?.pollFocus() }
    }

    // MARK: Click Practice

    func startPractice() {
        if calibration.visible { showBanner("Finish calibration first, then try Click Practice."); return }
        practice = PracticeGame(now: ProcessInfo.processInfo.systemUptime)
        practiceOverlay?.sync()
        broadcast(.practice(.running(hits: 0, total: 0)))
    }

    func practiceClick(at p: CGPoint, in size: CGSize) -> PracticeGame.ClickResult {
        guard var g = practice else { return .ignored }
        let r = g.click(at: p, in: size, now: ProcessInfo.processInfo.systemUptime)
        practice = g
        if case .hit = r { broadcast(.practice(g.report)) }
        return r
    }

    /// Esc / Cancel / Done on the Mac, or `stop` from the phone. `stop` goes to the phone only if it ended early.
    func stopPractice(notifyPhone: Bool) {
        guard let g = practice else { return }
        practice = nil
        practiceOverlay?.sync()
        if notifyPhone, g.phase != .finished { broadcast(.practice(.stopped)) }
    }

    private func handlePractice(_ c: PracticeCommand) {
        switch c {
        case .start: startPractice()
        case .stop: stopPractice(notifyPhone: false)
        }
    }

    func centerCursor() {
        output?.warp(to: screen.center)
    }

    func openAccessibilitySettings() { Accessibility.requestAndOpenSettings() }

    func copyAddress() {
        guard let ip = primaryAddress?.ip, let port else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(StatusText.endpoint(ip, port), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.copied = false }
    }

    func showBanner(_ text: String) {
        bannerWork?.cancel()
        banner = text
        let work = DispatchWorkItem { [weak self] in self?.banner = nil }
        bannerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}
