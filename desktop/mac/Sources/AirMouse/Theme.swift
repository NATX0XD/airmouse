import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

enum Theme {
    static let blue = Color(hex: 0x0A84FF)
    static let indigo = Color(hex: 0x5E5CE6)
    static let purple = Color(hex: 0xBF5AF2)
    static let cyan = Color(hex: 0x64D2FF)
    static let success = Color(hex: 0x30D158)
    static let warning = Color(hex: 0xFF9F0A)
    static let error = Color(hex: 0xFF453A)

    /// "Aurora", 135° (top-leading → bottom-trailing).
    static let aurora = LinearGradient(colors: [blue, indigo, purple], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cardRadius: CGFloat = 22
    static let buttonRadius: CGFloat = 14
    static let glassFill = Color.black.opacity(0.30)
    static let glassBorder = Color.white.opacity(0.12)
    static let darkAurora = LinearGradient(colors: [Color(hex: 0x090B2A), Color(hex: 0x24135A), Color(hex: 0x100D36)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Theme.darkAurora
            Circle().fill(Theme.blue.opacity(0.18)).frame(width: 420).blur(radius: 90).offset(x: -260, y: -250)
            Circle().fill(Theme.purple.opacity(0.18)).frame(width: 460).blur(radius: 110).offset(x: 270, y: 250)
            Circle().fill(Theme.cyan.opacity(0.08)).frame(width: 300).blur(radius: 90).offset(x: 120, y: -220)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Card

struct CardBackground: ViewModifier {
    var tint: Color?
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(Theme.glassFill))
                    .overlay { if let tint { shape.fill(tint.opacity(0.08)) } }
                    .overlay { shape.strokeBorder(tint?.opacity(0.35) ?? Theme.glassBorder, lineWidth: 0.8) }
                    .shadow(color: Theme.indigo.opacity(0.18), radius: 22, y: 10)
            }
    }
}

extension View {
    func card(tint: Color? = nil) -> some View { modifier(CardBackground(tint: tint)) }
}

// MARK: - Buttons

struct AuroraButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                    .fill(enabled ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Color.secondary.opacity(0.35)))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
                    }
                    .shadow(color: Theme.indigo.opacity(enabled ? (configuration.isPressed ? 0.15 : 0.35) : 0), radius: 10, y: 4)
            }
            .opacity(enabled ? 1 : 0.7)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06))
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - App icon (vector; also rendered to the .icns by build.sh)

/// Classic pointer in a 53 x 86 box, tip at (0, 0).
struct PointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 53, sy = rect.height / 86
        let pts: [(Double, Double)] = [(0, 0), (0, 74), (17.5, 58.5), (29, 85), (41.5, 79.5), (30, 53.5), (53, 53.5)]
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + pts[0].0 * sx, y: rect.minY + pts[0].1 * sy))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: rect.minX + q.0 * sx, y: rect.minY + q.1 * sy)) }
        p.closeSubpath()
        return p
    }
}

struct AppIconArt: View {
    var size: CGFloat
    /// Full macOS icon canvas (with margin + shadow) vs. just the squircle (in-app use).
    var withMargin = true

    var body: some View {
        let body = withMargin ? size * 824 / 1024 : size
        ZStack {
            squircle(body)
                .shadow(color: .black.opacity(withMargin ? 0.28 : 0.18), radius: body * 0.022, y: body * 0.014)
        }
        .frame(width: size, height: size)
    }

    private func squircle(_ b: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: b * 0.225, style: .continuous)
        return ZStack {
            shape.fill(Theme.aurora)
            // soft light from the top-left, depth at the bottom-right
            shape.fill(RadialGradient(colors: [.white.opacity(0.30), .clear], center: UnitPoint(x: 0.2, y: 0.05),
                                      startRadius: 0, endRadius: b * 0.85))
            shape.fill(LinearGradient(colors: [.clear, .black.opacity(0.16)], startPoint: .center, endPoint: .bottomTrailing))
            glyph(b)
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom),
                               lineWidth: max(0.5, b * 0.006))
        }
        .frame(width: b, height: b)
        .clipShape(shape)
    }

    private func glyph(_ b: CGFloat) -> some View {
        let h = b * 0.44, w = h * 53 / 86
        let tip = CGPoint(x: b * 0.455, y: b * 0.36)
        let rayInner = b * 0.075, rayOuter = b * 0.165
        let rays: [Double] = [-90, -135, 180].map { $0 * .pi / 180 }
        return ZStack(alignment: .topLeading) {
            Path { p in
                for a in rays {
                    p.move(to: CGPoint(x: tip.x + cos(a) * rayInner, y: tip.y + sin(a) * rayInner))
                    p.addLine(to: CGPoint(x: tip.x + cos(a) * rayOuter, y: tip.y + sin(a) * rayOuter))
                }
            }
            .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: b * 0.042, lineCap: .round))
            let rect = CGRect(x: tip.x, y: tip.y, width: w, height: h)
            PointerShape().path(in: rect)
                .fill(.white)
                .overlay(PointerShape().path(in: rect).stroke(.white, style: StrokeStyle(lineWidth: b * 0.03, lineJoin: .round)))
        }
        .frame(width: b, height: b, alignment: .topLeading)
        .shadow(color: Color(hex: 0x1B1464).opacity(0.35), radius: b * 0.03, y: b * 0.02)
    }
}

// MARK: - QR

enum QRCode {
    /// Crisp QR: generated at 1 module = 1 pixel, scaled with an integer factor (nearest neighbour).
    static func image(_ text: String, modulePixels: CGFloat = 12) -> CGImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: modulePixels, y: modulePixels))
        return CIContext(options: [.useSoftwareRenderer: true]).createCGImage(scaled, from: scaled.extent)
    }
}

struct QRCodeView: View {
    var text: String
    var body: some View {
        if let img = QRCode.image(text) {
            Image(decorative: img, scale: 1)
                .interpolation(.none)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
        } else {
            Image(systemName: "qrcode").resizable().aspectRatio(1, contentMode: .fit).foregroundStyle(.secondary)
        }
    }
}
