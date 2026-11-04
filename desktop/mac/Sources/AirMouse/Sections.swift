import SwiftUI
import AirMouseCore

private extension Date {
    var airMouseDate: String {
        formatted(Date.FormatStyle(
            date: .abbreviated,
            time: .omitted,
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: Calendar(identifier: .gregorian)
        ))
    }

    var airMouseDateTime: String {
        formatted(Date.FormatStyle(
            date: .abbreviated,
            time: .shortened,
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: Calendar(identifier: .gregorian)
        ))
    }
}

extension AppSection {
    var title: String {
        switch self {
        case .home: "Home"
        case .pair: "Pair iPhone"
        case .permissions: "Permissions"
        case .calibration: "Calibration"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .pair: "qrcode"
        case .permissions: "lock.shield.fill"
        case .calibration: "scope"
        case .about: "info"
        }
    }

    /// System Settings style: white glyph on a coloured rounded square (readable in both modes).
    var tint: Color {
        switch self {
        case .home: Theme.blue
        case .pair: Theme.indigo
        case .permissions: Theme.warning
        case .calibration: Theme.purple
        case .about: Color(nsColor: .systemGray)
        }
    }
}

struct SidebarIcon: View {
    var section: AppSection
    var body: some View {
        Image(systemName: section.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [section.tint.opacity(0.85), section.tint], startPoint: .top, endPoint: .bottom)))
    }
}

// MARK: - Root (single main window)

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            Group {
            if model.onboarding != nil {
                OnboardingView(model: model)
                    .transition(.opacity)
            } else {
                split
                    .overlayPreferenceValue(TourAnchorKey.self) { anchors in
                        if let tour = model.tour {
                            TourOverlay(tour: tour, anchors: anchors, next: model.tourNext, skip: model.endTour)
                                .transition(.opacity)
                        }
                    }
            }
            }
        }
        .frame(minWidth: 740, minHeight: 600)
        .animation(.easeInOut(duration: 0.3), value: model.onboarding == nil)
        .animation(.easeInOut(duration: 0.25), value: model.tour == nil)
        .onAppear { model.startTourIfNeeded(after: 1.0) }
    }

    private var split: some View {
        NavigationSplitView {
            List(selection: $model.section) {
                Section {
                    ForEach(AppSection.allCases, id: \.self) { s in
                        SidebarRow(section: s, selected: model.section, requiredMissing: requiredMissing)
                            .tag(s)
                            .modifier(TourRowMarker(section: s))
                    }
                } header: {
                    SidebarHeader()
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.visible)
            .navigationSplitViewColumnWidth(min: 164, ideal: 184, max: 220)
            .safeAreaInset(edge: .bottom) { SidebarStatus(model: model) }
        } detail: {
            Group {
                switch model.section {
                case .home: HomePage(model: model)
                case .pair: PairPage(model: model)
                case .permissions: PermissionsPage(model: model)
                case .calibration: CalibrationPage(model: model)
                case .about: AboutPage(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(model.section.title)
        }
        .toolbar(removing: .title) // pages carry their own large titles
        .onChange(of: model.section) { _, s in
            if s == .permissions { model.refreshPermissions(SetupFlow.order) }
        }
    }

    private var requiredMissing: Int { model.setup.warnings.filter { $0.requirement == .required }.count }
}

private struct SidebarRow: View {
    let section: AppSection
    let selected: AppSection
    let requiredMissing: Int

    var body: some View {
        HStack(spacing: 8) {
            SidebarIcon(section: section)
            Text(section.title)
            Spacer(minLength: 4)
            if section == .permissions, requiredMissing > 0 {
                Text("\(requiredMissing)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Circle().fill(Theme.warning))
            }
        }
        .padding(.vertical, 1)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
    }
}

private struct TourRowMarker: ViewModifier {
    var section: AppSection
    func body(content: Content) -> some View {
        switch section {
        case .pair: content.tourTarget(.pairRow)
        case .permissions: content.tourTarget(.permissionsRow)
        default: content
        }
    }
}

private struct SidebarStatus: View {
    var model: AppModel
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(model.isConnected ? Theme.success : Theme.warning).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.isConnected ? "Connected" : "Waiting for iPhone")
                    .font(.system(size: 11, weight: .semibold))
                Text(model.isConnected ? (model.primaryPhone?.name ?? "iPhone") : "Open AirMouse on iPhone")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .padding(.horizontal, 10).padding(.vertical, 8)
    }
}

private struct SidebarHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            AppIconArt(size: 30, withMargin: false)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("AirMouse").font(.system(size: 13, weight: .semibold))
                Text("Mac controller").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

/// Common page frame: large title, subtitle, content column.
struct Page<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 28, weight: .bold))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 4)
                content()
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Home

struct HomePage: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ConnectionHero(model: model)
            if let banner = model.banner { BannerRow(text: banner) }
            Grid(horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    DashboardCard(title: "Connection", caption: model.isConnected ? "Connected and ready" : "Waiting for iPhone…", image: "waves", fallback: "wifi") {
                        StatusLine(symbol: "wifi", label: "Wi-Fi", value: model.port == nil ? "Starting…" : (model.isConnected ? "Connected" : "Listening"), tint: Theme.cyan)
                        StatusLine(symbol: "dot.radiowaves.left.and.right", label: "Bluetooth", value: bleLabel, tint: Theme.purple)
                    }.tourTarget(.statusCard)
                    DashboardCard(title: "Calibration", caption: calibrationCaption, image: "gauge", fallback: "speedometer") {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(calibrationValue).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("pt/rad").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        }
                        Button(model.lastCalibration == nil ? "Calibrate" : "Recalibrate", action: model.requestCalibration).buttonStyle(.bordered).controlSize(.large)
                    }
                }
                GridRow {
                    DashboardCard(title: "Practice Clicking", caption: "Point, tap, and build confidence", image: "cursor-click", fallback: "cursorarrow.click") {
                        Button("Start Practice", action: model.startPractice).buttonStyle(.bordered).controlSize(.large).tourTarget(.centerCursor)
                    }
                    DashboardCard(title: "Pair iPhone", caption: "Scan a code or choose this Mac", image: "iphone-remote", fallback: "qrcode.viewfinder") {
                        Button("Open Pairing", action: { model.section = .pair }).buttonStyle(.bordered).controlSize(.large)
                    }.onTapGesture { model.section = .pair }.tourTarget(.pairRow)
                }
                GridRow {
                    DashboardCard(title: "Permissions", caption: model.setup.warnings.isEmpty ? "Everything is ready" : "1 needs attention", image: "shield-check", fallback: "lock.shield.fill") {
                        StatusLine(symbol: model.setup.warnings.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", label: model.setup.warnings.isEmpty ? "All systems go" : "Review setup", value: "", tint: model.setup.warnings.isEmpty ? Theme.success : Theme.warning)
                        Button("Review", action: { model.openSetup() }).buttonStyle(.bordered).controlSize(.large)
                    }.gridCellColumns(2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.banner)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.setup.warnings)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.isConnected)
    }

    private var calibrationValue: String { model.lastCalibration?.sensitivity.map { "\(Int($0.rounded()))" } ?? "—" }
    private var calibrationCaption: String { model.lastCalibration?.date.airMouseDate ?? "Not calibrated yet" }
    private var bleLabel: String { switch model.bluetooth { case .off: "Off"; case .advertising: "Available"; case .connected: "Connected" } }
}

private struct ConnectionHero: View {
    var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke((model.isConnected ? Theme.success : Theme.blue).opacity(0.22), lineWidth: 2)
                    .frame(width: 78, height: 78)
                    .scaleEffect(pulse && !reduceMotion ? 1.08 : 1)
                Circle().fill(model.isConnected ? Theme.success.opacity(0.16) : Theme.blue.opacity(0.12))
                    .frame(width: 58, height: 58)
                Image(systemName: model.isConnected ? "iphone.gen3" : "iphone")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(model.isConnected ? Theme.success : Theme.blue)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(model.isConnected ? "Connected to \(model.primaryPhone?.name ?? "iPhone")" : "Waiting for your iPhone")
                    .font(.system(size: 21, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.75)
                if model.isConnected {
                    HStack(spacing: 12) {
                        Label(model.primaryViaBluetooth ? "Bluetooth" : "Wi-Fi", systemImage: model.primaryViaBluetooth ? "dot.radiowaves.left.and.right" : "wifi")
                        Label(String(format: "%.0f moves/s", model.rate), systemImage: "waveform.path.ecg")
                        DiagnosticsBadge(model: model)
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                } else {
                    Text("Open AirMouse on your iPhone to start moving the pointer.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if model.isConnected {
                HStack(spacing: 8) {
                    Button("Calibrate", action: model.requestCalibration).buttonStyle(.borderedProminent).controlSize(.regular).tourTarget(.calibrate)
                    Button("Practice", action: model.startPractice).buttonStyle(.bordered).controlSize(.regular)
                    Button("Center Cursor", action: model.centerCursor).buttonStyle(.bordered).controlSize(.regular)
                }
            } else {
                Button("Pair", action: { model.section = .pair }).buttonStyle(.borderedProminent).controlSize(.regular).tourTarget(.pairRow)
            }
        }
        .padding(16)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            shape.fill(model.isConnected ? AnyShapeStyle(Theme.aurora.opacity(0.16)) : AnyShapeStyle(.regularMaterial))
                .overlay { shape.strokeBorder(model.isConnected ? Theme.indigo.opacity(0.32) : Color.primary.opacity(0.08), lineWidth: 0.5) }
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: model.isConnected)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

private struct DiagnosticsBadge: View {
    var model: AppModel
    var body: some View {
        let peer = model.diagnostics().peers.first
        let interval = peer?.stats.moveInterval(now: model.diagnostics().now)
        let jitter = interval.map { max(0, $0.maxMs - $0.meanMs) } ?? 0
        HStack(spacing: 4) {
            Circle().fill(jitter > 35 ? Theme.warning : Theme.success).frame(width: 6, height: 6)
            Text(interval.map { String(format: "%.0f ms · %.0f jitter", $0.meanMs, jitter) } ?? "— latency")
        }
    }
}

private struct DashboardCard<Content: View>: View {
    var title: String; var caption: String; var image: String; var fallback: String; @ViewBuilder var content: () -> Content
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.78)
                    Text(caption).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.72)
                }
                content().frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 2)
            AppIllustration(name: image, fallback: fallback).frame(width: 62, height: 62).allowsHitTesting(false)
        }
        .padding(13).frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(hovering ? 0.14 : 0.08), radius: hovering ? 14 : 10, y: hovering ? 5 : 3)
        .scaleEffect(hovering && !reduceMotion ? 1.01 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: hovering)
        .onHover { hovering = $0 }
    }
}

private struct StatusLine: View { var symbol: String; var label: String; var value: String; var tint: Color; var body: some View { HStack(spacing: 8) { Image(systemName: symbol).foregroundStyle(tint).frame(width: 18); Text(label).font(.system(size: 13, weight: .medium)); Spacer(); Text(value).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1) } } }

/// Fills Home's lower half: how it works + last calibration, one compact row.
private struct HomeInfoRow: View {
    var model: AppModel
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("How It Works").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                HowItWorksStrip(style: .compact)
            }
            .card()
            Button { model.section = .calibration } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calibration").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    if let r = model.lastCalibration {
                        Text(r.sensitivity.map { "\(Int($0.rounded()))" } ?? "—")
                            .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                        Text("pt/rad · bias \(r.biasOK ? "OK" : "skipped")").font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(r.date.airMouseDate)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "scope").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.purple)
                            .padding(.vertical, 4)
                        Text("Not calibrated yet").font(.system(size: 13, weight: .medium))
                        Text("Uses the default speed").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 130, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .card()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Pair

struct PairPage: View {
    var model: AppModel

    var body: some View {
        Page(title: "Pair iPhone", subtitle: "Your iPhone and this Mac need the same Wi-Fi, or use Bluetooth.") {
            HStack(alignment: .top, spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white)
                    if let url = model.pairingURL { QRCodeView(text: url).padding(12) } else { ProgressView() }
                }
                .frame(width: 190, height: 190)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 3)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Scan with AirMouse on your iPhone").font(.system(size: 17, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    StepLine(n: 1, text: "Open AirMouse on your iPhone")
                    StepLine(n: 2, text: "Tap Scan QR Code")
                    StepLine(n: 3, text: "Point the camera at this code")
                    Text("Or pick “\(model.macName)” under Nearby.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Label("Wi-Fi addresses", systemImage: "wifi").font(.system(size: 13, weight: .semibold))
                if let port = model.port, !model.addresses.isEmpty {
                    ForEach(Array(model.addresses.enumerated()), id: \.element) { i, a in
                        AddressRow(address: a, port: port, primary: i == 0, copied: model.copied && i == 0) {
                            copy(StatusText.endpoint(a.ip, port))
                        }
                    }
                } else {
                    Text(model.port == nil ? "The server isn’t running yet." : "No network connection.")
                        .font(.system(size: 13)).foregroundStyle(Theme.warning)
                }
                Divider().padding(.vertical, 2)
                Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right").font(.system(size: 13, weight: .semibold))
                HStack {
                    Text(BLESpec.localName(macName: model.macName))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    Spacer()
                    Text(bluetoothText).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }

    private var bluetoothText: String {
        switch model.bluetooth {
        case .off(let why): "Off · \(why)"
        case .advertising: "Advertising"
        case .connected: "Connected"
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        model.copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { model.copied = false }
    }
}

private struct StepLine: View {
    var n: Int
    var text: String
    var body: some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Circle().fill(Theme.aurora))
            Text(text).font(.system(size: 13))
        }
    }
}

private struct AddressRow: View {
    var address: InterfaceAddress
    var port: UInt16
    var primary: Bool
    var copied: Bool
    var copy: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Text(StatusText.endpoint(address.ip, port)).font(.system(size: 13, weight: .medium, design: .monospaced))
            Text(address.interface == "en0" ? "Wi-Fi" : address.interface)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            if primary { Text("In QR code").font(.system(size: 11)).foregroundStyle(.tertiary) }
            Spacer()
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? Theme.success : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Copy address")
        }
    }
}

// MARK: - Calibration

struct CalibrationPage: View {
    var model: AppModel

    var body: some View {
        Page(title: "Calibration", subtitle: "Teach AirMouse your iPhone and your screen. It takes about 20 seconds.") {
            VStack(spacing: 0) {
                CalibStep(n: 1, symbol: "iphone", title: "Turn your iPhone around",
                          text: "Hold it flat against the screen, display facing in, inside the glowing outline. AirMouse measures the gyroscope’s drift.")
                Divider().padding(.leading, 52)
                CalibStep(n: 2, symbol: "scope", title: "Point at the left dot",
                          text: "Aim like a remote and tap your iPhone’s screen.")
                Divider().padding(.leading, 52)
                CalibStep(n: 3, symbol: "arrow.left.and.right", title: "Point at the right dot",
                          text: "Turn smoothly and tap again. AirMouse sets the pointer speed from how far you turned.")
            }
            .card()

            HStack(spacing: 10) {
                Button(action: model.requestCalibration) { Label("Start Calibration", systemImage: "scope") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button(action: model.startPractice) { Label("Practice Clicking", systemImage: "target") }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .frame(maxWidth: 440)
            if let banner = model.banner { BannerRow(text: banner) }

            VStack(alignment: .leading, spacing: 10) {
                Text("Last Result").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                if let r = model.lastCalibration {
                    HStack(spacing: 0) {
                        Metric(value: r.sensitivity.map { "\(Int($0.rounded()))" } ?? "—", label: "Sensitivity (pt/rad)")
                        Divider().frame(height: 36).padding(.horizontal, 16)
                        Metric(value: r.biasOK ? "OK" : "Skipped", label: "Gyro bias", color: r.biasOK ? Theme.success : .secondary)
                        Divider().frame(height: 36).padding(.horizontal, 16)
                        Metric(value: r.date.airMouseDateTime, label: "Date", small: true)
                        Spacer(minLength: 0)
                    }
                } else {
                    Text("Not calibrated yet. AirMouse uses the default speed until you do.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .card()
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: model.banner)
    }
}

private struct CalibStep: View {
    var n: Int
    var symbol: String
    var title: String
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Theme.aurora)
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(n). \(title)").font(.system(size: 15, weight: .semibold))
                Text(text).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }
}

private struct Metric: View {
    var value: String
    var label: String
    var color: Color = .primary
    var small = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: small ? 15 : 22, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
                .frame(height: 28, alignment: .bottomLeading)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - About

struct AboutPage: View {
    var model: AppModel
    var body: some View {
        Page(title: "About", subtitle: nil) {
            HStack(spacing: 16) {
                AppIconArt(size: 72, withMargin: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AirMouse for Mac").font(.system(size: 22, weight: .bold))
                    Text("Version \(MacInfo.version)").font(.system(size: 13)).foregroundStyle(.secondary)
                    Text("Mobile app course project · KMUTNB").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 4)
            VStack(spacing: 0) {
                InfoRow(label: "Mac name", value: model.macName)
                Divider()
                InfoRow(label: "Port", value: model.port.map { String($0) } ?? "—")
                Divider()
                InfoRow(label: "Bonjour", value: model.port == nil ? "Off" : "On · _airmouse._tcp")
                Divider()
                InfoRow(label: "Bluetooth name", value: BLESpec.localName(macName: model.macName))
                Divider()
                InfoRow(label: "Protocol", value: "v3 · JSON over WebSocket / BLE")
            }
            .card()
            HStack(spacing: 10) {
                Button("Show Welcome", action: model.showWelcome).buttonStyle(SoftButtonStyle()).frame(width: 150)
                Button("Show Tour", action: model.startTour).buttonStyle(SoftButtonStyle()).frame(width: 150)
            }
            DiagnosticsSection(model: model).padding(.top, 8)
        }
    }
}

// MARK: - Diagnostics (spec 4a.4)

/// Live counters. The sessions are not observable, so a 4 Hz timeline polls them only while About is on screen.
struct DiagnosticsSection: View {
    var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Diagnostics").font(.system(size: 17, weight: .semibold))
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Theme.success).frame(width: 7, height: 7)
                    Text("Live").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let snap = model.diagnostics()
                VStack(spacing: 12) {
                    if snap.peers.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "iphone.slash").font(.system(size: 17)).foregroundStyle(.secondary)
                            Text("No iPhone connected. Counters appear when one connects.")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .card()
                    }
                    ForEach(snap.peers) { peer in PeerDiagnosticsCard(peer: peer, now: snap.now) }
                    OverlayDiagnosticsCard(calibration: model.calibration, overlayShowing: model.overlayShowing, rate: model.rate,
                                           pacerFPS: model.pacerFPS)
                    Label("If the pointer hitches every few seconds, turn off AirDrop / Handoff, or use Bluetooth.",
                          systemImage: "lightbulb")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct PeerDiagnosticsCard: View {
    var peer: PeerDiagnostics
    var now: TimeInterval

    private var transportLabel: String {
        switch peer.transport {
        case .wifi: "Wi-Fi · connection #\(peer.id.split(separator: "-").last.map(String.init) ?? "?")"
        case .bluetooth: "Bluetooth · \(peer.id.dropFirst(4).prefix(8))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(peer.transport == .wifi ? Theme.blue : Theme.indigo)
                    Image(systemName: peer.transport == .wifi ? "wifi" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(peer.name).font(.system(size: 15, weight: .semibold))
                    Text(transportLabel).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(String(format: "%.0f", peer.stats.rate(now: now)))
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    Text("msg/s").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 4), alignment: .leading, spacing: 8) {
                ForEach(MessageStats.kinds, id: \.self) { kind in
                    CounterTile(label: kind, value: peer.stats.count(kind), dim: kind == "other")
                }
            }
            HStack(spacing: 0) {
                DiagFact(label: "Last move", value: MessageStats.ago(peer.stats.lastMoveAt, now: now),
                         tint: moveFresh ? Theme.success : nil)
                Divider().frame(height: 30).padding(.horizontal, 14)
                DiagFact(label: "Dragging", value: peer.dragging.map { $0 == .left ? "Left button" : "Right button" } ?? "None",
                         tint: peer.dragging == nil ? nil : Theme.warning)
                Divider().frame(height: 30).padding(.horizontal, 14)
                DiagFact(label: "Total", value: peer.stats.total.formatted())
                Divider().frame(height: 30).padding(.horizontal, 14)
                DiagFact(label: "Gap avg/max · >50 ms per min", value: moveGap,
                         tint: peer.stats.moveInterval(now: now).map { $0.maxMs > 60 ? Theme.warning : Theme.success })
                Spacer(minLength: 0)
            }
        }
        .card()
    }

    private var moveGap: String {
        let hitches = peer.stats.longGaps(now: now)
        guard let j = peer.stats.moveInterval(now: now) else { return "— · \(hitches)" }
        return String(format: "%.1f / %.0f ms · %d", j.meanMs, j.maxMs, hitches)
    }

    private var moveFresh: Bool { peer.stats.lastMoveAt.map { now - $0 < 1 } ?? false }
}

private struct CounterTile: View {
    var label: String
    var value: Int
    var dim = false
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value.formatted())
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(dim && value == 0 ? .secondary : .primary)
                .contentTransition(.numericText())
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

private struct DiagFact: View {
    var label: String
    var value: String
    var tint: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                if let tint { Circle().fill(tint).frame(width: 7, height: 7) }
                Text(value).font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            }
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

private struct OverlayDiagnosticsCard: View {
    var calibration: CalibrationState
    var overlayShowing: Bool
    var rate: Double
    var pacerFPS: Double

    private var stepName: String {
        switch calibration.step {
        case .place: "1 · Place"
        case .placed: "1 · Placed"
        case .point(let t): "2 · Point \(t.rawValue)"
        case .verify: "3 · Verify (\(calibration.everLit.count)/5)"
        case .done: "Done"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DiagRow(label: "Overlay", value: overlayShowing ? "Visible" : "Hidden")
            Divider()
            DiagRow(label: "Calibration step", value: calibration.visible ? stepName : "—")
            if calibration.visible && calibration.step == .place {
                Divider()
                HStack(spacing: 12) {
                    Text("Placement").font(.system(size: 13))
                    Spacer()
                    Text("\(Int((calibration.progress * 100).rounded()))%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    Signal(label: "near", value: calibration.near)
                    Signal(label: "upright", value: calibration.upright)
                    Signal(label: "still", value: calibration.still)
                }
                .padding(.vertical, 8)
                Divider()
                DiagRow(label: "Hint", value: calibration.placeHint.text)
            }
            Divider()
            DiagRow(label: "All peers", value: String(format: "%.0f msg/s", rate))
            Divider()
            DiagRow(label: "Pointer pacer", value: pacerFPS > 0 ? String(format: "%.0f fps (display-synced)", pacerFPS) : "Idle")
        }
        .card()
    }
}

private struct Signal: View {
    var label: String
    var value: Bool?
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: value == true ? "checkmark.circle.fill" : value == false ? "xmark.circle.fill" : "questionmark.circle")
                .foregroundStyle(value == true ? Theme.success : value == false ? Theme.error : .secondary)
            Text(label).foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .medium))
    }
}

private struct DiagRow: View {
    var label: String
    var value: String
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value).font(.system(size: 13).monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct InfoRow: View {
    var label: String
    var value: String
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value).font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(.vertical, 8)
    }
}
