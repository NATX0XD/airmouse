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
    var body: some View {
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("Illustrations"),
           let image = NSImage(contentsOf: dir.appendingPathComponent("\(name).png")) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: fallback).resizable().aspectRatio(contentMode: .fit)
                .symbolRenderingMode(.hierarchical).foregroundStyle(Theme.cyan, Theme.purple)
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

    var body: some View {
        let flow = model.onboarding ?? OnboardingFlow()
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            VStack(spacing: 0) {
            Group {
                switch flow.current {
                case .welcome?: WelcomePage()
                case .howItWorks?: HowItWorksPage()
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
                Button(action: model.onboardingNext) {
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
    }

    private func continueTitle(_ f: OnboardingFlow) -> String {
        switch f.current {
        case .welcome?: "Get Started"
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

private struct HowItWorksPage: View {
    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                Text("How It Works").font(.system(size: 34, weight: .bold))
                Text("AirMouse reads your iPhone’s gyroscope about 100 times a second.")
                    .font(.system(size: 17)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Illustration(kind: .howItWorks).frame(maxWidth: 620)
            Text("Hold the touch pad to point, so the cursor only moves when you want it to.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 32)
    }
}

private struct GetIPhonePage: View {
    var model: AppModel
    var body: some View {
        HStack(spacing: 40) {
            AppIllustration(name: "iphone-remote", fallback: "iphone").frame(width: 190, height: 280)
            VStack(alignment: .leading, spacing: 14) {
                Text("Get AirMouse on Your iPhone").font(.system(size: 28, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Install AirMouse on your iPhone, then open it.")
                    .font(.system(size: 17)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    NumberedLine(n: 1, text: "Install AirMouse on your iPhone")
                    NumberedLine(n: 2, text: "Open it and allow Local Network")
                    NumberedLine(n: 3, text: "Pick “\(model.macName)” or scan the QR code")
                }
                .padding(.top, 4)
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(.tertiary)
                        .frame(width: 64, height: 64)
                        .overlay(Image(systemName: "qrcode").font(.system(size: 24)).foregroundStyle(.tertiary))
                    Text("Download link coming soon. For now AirMouse is installed from Xcode.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: 360, alignment: .leading)
            .card()
        }
        .padding(.horizontal, 40)
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
