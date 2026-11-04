import SwiftUI
import AirMouseCore

// MARK: - Swappable illustrations

/// Raster art from `assets-gen/` (copied into Contents/Resources/Illustrations by build.sh) if present,
/// otherwise a code-drawn vector version.
struct Illustration: View {
    enum Kind: String {
        case heroPointing = "hero-pointing"
        case howItWorks = "how-it-works"
    }
    var kind: Kind

    static func raster(_ kind: Kind) -> NSImage? {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Illustrations") else { return nil }
        return NSImage(contentsOf: dir.appendingPathComponent("\(kind.rawValue).png"))
    }

    var body: some View {
        if let img = Self.raster(kind) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
        } else {
            switch kind {
            case .heroPointing: HeroVector()
            case .howItWorks: HowItWorksStrip(style: .large)
            }
        }
    }
}

struct AppIllustration: View {
    var name: String
    var fallback: String
    @State private var floating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if let dir = Bundle.main.resourceURL?.appendingPathComponent("Illustrations"),
               let image = NSImage(contentsOf: dir.appendingPathComponent("\(name).png")) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: fallback).resizable().aspectRatio(contentMode: .fit)
                    .symbolRenderingMode(.hierarchical).foregroundStyle(Theme.cyan, Theme.purple)
            }
        }
        .offset(y: floating && !reduceMotion ? -2 : 0)
        .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: floating)
        .onAppear {
            guard !reduceMotion else { return }
            floating = true
        }
    }
}

/// Phone -> waves -> Mac with cursor.
private struct HeroVector: View {
    var body: some View {
        HStack(spacing: 0) {
            PhoneMock(size: 120)
                .rotationEffect(.degrees(-14))
                .padding(.trailing, 8)
            Waves().frame(width: 110, height: 90)
            LaptopMock(width: 250)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Waves: View {
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .trim(from: 0.40, to: 0.60)
                    .stroke(Theme.aurora, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 40 + CGFloat(i) * 34, height: 40 + CGFloat(i) * 34)
                    .rotationEffect(.degrees(180))
                    .opacity(1 - Double(i) * 0.25)
            }
        }
        .offset(x: -22)
    }
}

struct PhoneMock: View {
    var size: CGFloat // height
    var body: some View {
        let w = size * 0.49
        ZStack {
            RoundedRectangle(cornerRadius: w * 0.2, style: .continuous).fill(Color(hex: 0x1C1C1E))
            RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x0B1A3A), Color(hex: 0x1E1550)], startPoint: .top, endPoint: .bottom))
                .padding(w * 0.05)
            AppIconArt(size: w * 0.42, withMargin: false)
            Capsule().fill(.black).frame(width: w * 0.3, height: w * 0.08).offset(y: -size * 0.43)
        }
        .frame(width: w, height: size)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }
}

private struct LaptopMock: View {
    var width: CGFloat
    var body: some View {
        let h = width * 0.62
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0x1C1C1E))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.blue.opacity(0.85), Theme.indigo, Theme.purple.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(8)
                PointerShape().fill(.white)
                    .overlay(PointerShape().stroke(.black.opacity(0.4), lineWidth: 1))
                    .frame(width: 22, height: 36)
                    .offset(x: 18, y: 6)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
            }
            .frame(width: width * 0.86, height: h)
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                .fill(LinearGradient(colors: [Color(hex: 0xC7C7CC), Color(hex: 0x8E8E93)], startPoint: .top, endPoint: .bottom))
                .frame(width: width, height: 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 8)
    }
}

/// Gyroscope -> Smoothing (One Euro filter) -> Cursor.
struct HowItWorksStrip: View {
    enum Style { case large, compact }
    var style: Style

    private var nodes: [(String, String, String)] {
        style == .large ? [
            ("gyroscope", "Gyroscope", "Measures how fast your iPhone turns"),
            ("waveform.path", "Smoothing", "One Euro filter: steady when slow, quick when fast"),
            ("cursorarrow.rays", "Cursor", "Your Mac moves the pointer to match"),
        ] : [
            ("gyroscope", "Gyroscope", "Turn rate"),
            ("waveform.path", "Smoothing", "One Euro filter"),
            ("cursorarrow.rays", "Cursor", "Pointer moves"),
        ]
    }

    var body: some View {
        let big = style == .large
        HStack(alignment: .top, spacing: big ? 10 : 6) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { i, n in
                if i > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: big ? 16 : 12, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, big ? 22 : 10)
                }
                VStack(spacing: big ? 8 : 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: big ? 16 : 9, style: .continuous).fill(Theme.aurora)
                        Image(systemName: n.0).font(.system(size: big ? 26 : 15, weight: .semibold)).foregroundStyle(.white)
                    }
                    .frame(width: big ? 62 : 32, height: big ? 62 : 32)
                    .shadow(color: Theme.indigo.opacity(0.3), radius: big ? 8 : 4, y: 3)
                    Text(n.1).font(.system(size: big ? 15 : 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.72)
                    Text(n.2).font(.system(size: big ? 13 : 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Onboarding (full-width pages inside the main window)

struct OnboardingView: View {
    var model: AppModel
    @State private var explainerIndex = 0

    var body: some View {
        let flow = model.onboarding ?? OnboardingFlow()
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(spacing: 0) {
            Group {
                switch flow.current {
                case .welcome?: WelcomePage()
                case .howItWorks?: HowItWorksPage(step: explainerIndex)
                case .getIPhone?: GetIPhonePage(model: model)
                case .permissions?: PermissionsPage(model: model, assistant: true)
                case nil: EmptyView()
                }
            }
            .id(flow.index)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider()
            HStack {
                Button("Back") { model.onboardingBack() }
                    .opacity(flow.canGoBack ? 1 : 0)
                    .disabled(!flow.canGoBack)
                Spacer()
                HStack(spacing: 7) {
                    ForEach(0..<flow.pages.count, id: \.self) { i in
                        Capsule().fill(i == flow.index ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Color.primary.opacity(0.18)))
                            .frame(width: i == flow.index ? 22 : 7, height: 7)
                    }
                }
                Spacer()
                Button(action: advance(flow)) {
                    Text(continueTitle(flow)).frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(width: 170)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(.regularMaterial.opacity(0.32))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: flow.index)
        .onChange(of: flow.current) { _, page in if page != .howItWorks { explainerIndex = 0 } }
    }

    private func advance(_ flow: OnboardingFlow) -> () -> Void {
        { if flow.current == .howItWorks && explainerIndex < ExplainerContent.steps.count { explainerIndex += 1 } else { model.onboardingNext() } }
    }

    private func continueTitle(_ f: OnboardingFlow) -> String {
        switch f.current {
        case .welcome?: "Get Started"
        case .howItWorks?: explainerIndex == ExplainerContent.steps.count ? "Done" : "Next"
        case .getIPhone?: "I Already Have It"
        case .permissions?: model.setup.allRequiredGranted ? "Start Using AirMouse" : "Continue Anyway"
        default: "Continue"
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)
            AppIllustration(name: "iphone-remote", fallback: "iphone").frame(width: 250, height: 190)
            VStack(spacing: 8) {
                Text("Welcome to AirMouse").font(.system(size: 34, weight: .bold))
                Text("Turn your iPhone into an air mouse for your Mac.")
                    .font(.system(size: 17)).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                ValuePoint(symbol: "iphone.radiowaves.left.and.right", title: "Point to move", text: "Turn your phone, the cursor follows.")
                ValuePoint(symbol: "hand.tap", title: "Tap to click", text: "Tap, hold and scroll on the screen.")
                ValuePoint(symbol: "wifi", title: "Wi-Fi or Bluetooth", text: "Connect the way that works for you.")
            }
            .frame(maxWidth: 620)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 32)
    }
}

private struct ValuePoint: View {
    var symbol: String
    var title: String
    var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.blue)
                .frame(height: 24)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 112, alignment: .topLeading)
        .card()
    }
}

struct HowItWorksPage: View {
    var step: Int
    var body: some View {
        if step == 0 { return AnyView(SensorOverviewPage()) }
        let item = ExplainerContent.steps[step - 1]
        return AnyView(VStack(spacing: 20) {
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                Text(item.title).font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center)
                Text(item.body)
                    .font(.system(size: 17)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 560)
            }
            if step == 3 { PhoneAxesView(mode: .cursor, still: 0.8).frame(width: 580, height: 260) }
            else { AppIllustration(name: item.image, fallback: "iphone").frame(width: 400, height: 260) }
            if let fact = item.fact { Text("Fun fact · \(fact)").font(.system(size: 13)).foregroundStyle(Theme.blue) }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 32))
    }
}

private struct SensorOverviewPage: View {
    private let sensors: [(String, String, String, String)] = [
        ("gyroscope", "Gyroscope", "Detects phone rotation and controls the cursor.", "explainer/sensors/gyroscope"),
        ("accelerometer", "Accelerometer", "Detects the phone's position using gravity.", "explainer/sensors/accelerometer"),
        ("proximity", "Proximity sensor", "Detects nearby objects during calibration.", "explainer/sensors/proximity"),
        ("touchscreen", "Touchscreen", "Used for clicking and scrolling.", "explainer/sensors/touchscreen"),
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text("Sensors AirMouse Uses").font(.system(size: 30, weight: .bold)).multilineTextAlignment(.center)
            Text("AirMouse uses four main sensors.")
                .font(.system(size: 17)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(sensors, id: \.1) { sensor in
                    VStack(alignment: .leading, spacing: 5) {
                        AppIllustration(name: sensor.3, fallback: sensor.0).frame(height: 104)
                        Text(sensor.1).font(.system(size: 15, weight: .semibold))
                        Text(sensor.2).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .topLeading).card()
                }
            }
            HStack(spacing: 10) {
                Text("Also used").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Text("Camera · scans the QR code to pair   Haptics · gentle feedback").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 32).frame(maxWidth: 680).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum ExplainerContent {
    struct Step { let title: String; let body: String; let image: String; let fact: String? }
    static let steps: [Step] = [
        .init(title: "Your iPhone feels movement.", body: "Inside your iPhone is a tiny motion sensor called a gyroscope. It notices when you turn or tilt the phone.", image: "explainer/01-gyro", fact: nil),
        .init(title: "It checks 100 times a second.", body: "Every hundredth of a second, AirMouse asks the sensor: “How fast are you turning right now?”", image: "explainer/02-sampling", fact: "That is faster than a blink."),
        .init(title: "Turning becomes moving.", body: "Turn left or right and the pointer moves sideways. Tilt up or down and it moves up or down.", image: "explainer/03-direction", fact: nil),
        .init(title: "Smoothing out shaky hands.", body: "Everyone's hands shake a little. AirMouse filters out tiny wobbles, so the pointer stays steady but still follows quick moves.", image: "explainer/04-smoothing", fact: nil),
        .init(title: "Sending it to your Mac.", body: "The phone sends small messages (“move 3 dots right”) over Wi-Fi or Bluetooth. Nothing leaves your home network.", image: "explainer/05-sending", fact: nil),
        .init(title: "Your Mac moves the pointer.", body: "The AirMouse app on your Mac receives each message and moves the cursor smoothly at your screen's refresh rate.", image: "explainer/06-mac-cursor", fact: nil),
        .init(title: "Calibration makes it accurate.", body: "By pointing at 5 dots, AirMouse learns how far the cursor should move when you turn, for your screen and your distance.", image: "explainer/07-calibration", fact: nil),
        .init(title: "Touch to point, tap to click.", body: "Hold the touch pad to move, tap to click, and use the buttons for right click and scrolling.", image: "explainer/08-touch-click", fact: nil),
    ]
}

private struct GetIPhonePage: View {
    var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            AppIllustration(name: "iphone-remote", fallback: "iphone")
                .frame(width: 170, height: 170)
                .padding(.top, 2)
            Text("Get AirMouse on Your iPhone")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Install AirMouse on your iPhone, then open it.")
                .font(.system(size: 15)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                NumberedLine(n: 1, text: "Install AirMouse on your iPhone")
                NumberedLine(n: 2, text: "Open it and allow Local Network")
                NumberedLine(n: 3, text: "Choose “\(model.macName)” under Nearby")
            }
            .frame(maxWidth: 430, alignment: .leading)
            HStack(spacing: 14) {
                if let url = model.pairingURL {
                    QRCodeView(text: url)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
                        .frame(width: 92, height: 92)
                    Text("Or scan this code in AirMouse on your iPhone.")
                } else {
                    Image(systemName: "qrcode").font(.system(size: 28, weight: .medium)).foregroundStyle(.secondary)
                    Text("The pairing code will appear when this Mac is listening on Wi-Fi.")
                }
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NumberedLine: View {
    var n: Int
    var text: String
    var body: some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(Theme.aurora))
            Text(text).font(.system(size: 14))
        }
    }
}

// MARK: - Coach-mark tour

struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func tourTarget(_ t: TourTarget) -> some View {
        anchorPreference(key: TourAnchorKey.self, value: .bounds) { [t: $0] }
    }
}

extension TourTarget {
    var title: String {
        switch self {
        case .statusCard: "Connection Status"
        case .pairRow: "Pair iPhone"
        case .calibrate: "Calibrate"
        case .centerCursor: "Center Cursor"
        case .permissionsRow: "Permissions"
        case .menuBar: "Menu Bar"
        }
    }

    var sentence: String {
        switch self {
        case .statusCard: "See whether your iPhone is connected, over Wi-Fi or Bluetooth."
        case .pairRow: "Shows the QR code your iPhone scans to connect."
        case .calibrate: "Run this once so the pointer matches how far you turn your phone."
        case .centerCursor: "Lost the pointer? This puts it back in the middle of the screen."
        case .permissionsRow: "If something stops working, look here. An orange badge means a permission is missing."
        case .menuBar: "AirMouse keeps running in the menu bar at the top right, even when this window is closed."
        }
    }
}

/// Rect with a rounded hole; animatable so the spotlight springs between targets.
struct SpotlightShape: Shape {
    var hole: CGRect
    var radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(hole.origin.x, hole.origin.y), .init(hole.width, hole.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        if hole.width > 0 { p.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous) }
        return p
    }
}

struct TourOverlay: View {
    var tour: TourFlow
    var anchors: [TourTarget: Anchor<CGRect>]
    var next: () -> Void
    var skip: () -> Void

    var body: some View {
        GeometryReader { geo in
            let target = tour.current
            let raw = target.flatMap { anchors[$0] }.map { geo[$0] }
            let bounds = CGRect(origin: .zero, size: geo.size).insetBy(dx: 3, dy: 3)
            let hole = raw.map { $0.insetBy(dx: -8, dy: -8).intersection(bounds) }
                ?? CGRect(x: geo.size.width - 40, y: -40, width: 0, height: 0) // menu bar: no cut-out
            let calloutW: CGFloat = 320
            let below = hole.maxY + 190 < geo.size.height
            let cx = min(max(hole.midX, calloutW / 2 + 16), geo.size.width - calloutW / 2 - 16)
            let cy: CGFloat = raw == nil ? 120 : (below ? hole.maxY + 14 + 80 : hole.minY - 14 - 80)
            ZStack {
                SpotlightShape(hole: raw == nil ? .zero : hole, radius: 14)
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    .onTapGesture {} // block the UI underneath
                if raw != nil {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.cyan.opacity(0.9), lineWidth: 2)
                        .shadow(color: Theme.cyan.opacity(0.6), radius: 8)
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                        .allowsHitTesting(false)
                }
                Callout(tour: tour, next: next, skip: skip)
                    .frame(width: calloutW)
                    .position(x: raw == nil ? geo.size.width - calloutW / 2 - 24 : cx, y: cy)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: tour.index)
        }
    }
}

private struct Callout: View {
    var tour: TourFlow
    var next: () -> Void
    var skip: () -> Void
    var body: some View {
        let t = tour.current ?? .statusCard
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if t == .menuBar {
                    Image(systemName: "menubar.arrow.up.rectangle").foregroundStyle(Theme.blue)
                }
                Text(t.title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(tour.stepNumber) of \(tour.total)")
                    .font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(t.sentence).font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Skip Tour", action: skip).buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Button(tour.isLastStep ? "Done" : "Next", action: next)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .windowBackgroundColor).opacity(0.6)))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}
