import SwiftUI
import AirMouseCore

/// Previews render a still frame: no repeating animations, fixed particle time.
private struct StillFrameKey: EnvironmentKey { static let defaultValue: Double? = nil }
extension EnvironmentValues {
    var stillFrameTime: Double? {
        get { self[StillFrameKey.self] }
        set { self[StillFrameKey.self] = newValue }
    }
}

struct OverlayView: View {
    var state: CalibrationState
    var phone: PhoneDevice
    var screen: ScreenInfo
    var onCancel: () -> Void

    var body: some View {
        GeometryReader { geo in
            let s = ScreenInfo(w: Int(geo.size.width), h: Int(geo.size.height), scale: screen.scale,
                               wMm: screen.wMm * (geo.size.width / max(1, Double(screen.w))), hMm: screen.hMm, name: screen.name)
            let outline = CalibrationGeometry.outlineRect(screen: s, phoneWMm: phone.wMm, phoneHMm: phone.hMm)
            let radius = CalibrationGeometry.cornerRadius(screen: s)
            ZStack {
                ParticleBackground(focus: CGPoint(x: outline.midX, y: outline.midY))

                // 1 place
                PhoneOutline(rect: outline, radius: radius, progress: state.progress, still: state.still,
                             placed: state.step == .placed)
                    .opacity(isPlaceStep ? 1 : 0)
                    .scaleEffect(isPlaceStep ? 1 : 0.94)

                // 2 point (v3: one target at a time; older phones: left then right)
                if case .point(let t) = state.step {
                    if t == .right {
                        TurnGuide(from: CalibrationGeometry.target(.left, screen: s), to: CalibrationGeometry.target(.right, screen: s))
                            .transition(.opacity)
                        TargetDot(active: false, hit: true)
                            .position(CalibrationGeometry.target(.left, screen: s))
                    }
                    TargetDot(active: !state.pointed.contains(t), hit: state.pointed.contains(t), labelAbove: Self.labelAbove(t))
                        .id(t)
                        .position(CalibrationGeometry.target(t, screen: s))
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                // 3 verify: all five dots, lit while the real cursor is near
                if state.step == .verify {
                    ForEach(Side.fourCorners, id: \.self) { t in
                        ZStack {
                            Circle().strokeBorder(.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                                .frame(width: CalibrationGeometry.hitRadius * 2, height: CalibrationGeometry.hitRadius * 2)
                            TargetDot(active: !state.everLit.contains(t), hit: state.lit.contains(t), showLabel: state.lit.contains(t),
                                      labelAbove: Self.labelAbove(t))
                        }
                        .position(CalibrationGeometry.target(t, screen: s))
                    }
                    .transition(.opacity)
                }

                // Instructions: left column while placing, top centre while pointing / verifying.
                if isPlaceStep {
                    InstructionBlock(number: 1, title: state.step == .placed ? "Great." : "Turn Your iPhone Around",
                                     message: state.step == .placed ? "Got it. Lift your iPhone away. Next, you’ll point at five dots."
                                        : "Hold it flat against the screen, inside the outline, with the display facing the screen.",
                                     alignment: .leading) {
                        PlaceHintView(hint: state.placeHint).opacity(state.step == .place ? 1 : 0)
                    }
                        .frame(width: max(280, min(460, outline.minX - geo.size.width * 0.07 - 56)), alignment: .leading)
                        .position(x: geo.size.width * 0.07 + max(280, min(460, outline.minX - geo.size.width * 0.07 - 56)) / 2,
                                  y: geo.size.height * 0.5)
                        .transition(.opacity.combined(with: .offset(x: -20)))
                } else if case .point(let t) = state.step {
                    InstructionBlock(number: state.stepNumber, title: t == .right ? "Now Point at the Right Dot" : "Point at the \(t.title)",
                                     message: "Aim, then tap your iPhone.",
                                     alignment: .center) {
                        if let i = state.cornerIndex { TargetProgress(current: i, pointed: state.pointed) }
                    }
                        .id("point")
                        .frame(width: 900)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.27)
                        .transition(.opacity.combined(with: .offset(y: -12)))
                } else if state.step == .verify {
                    InstructionBlock(number: 3, title: "Check Your Pointer",
                                     message: "Point at each dot. They light up when the cursor touches them.",
                                     alignment: .center) {
                        Text("\(state.everLit.count) of 5 reached")
                            .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(state.everLit.count == 5 ? Theme.success : Theme.cyan)
                            .contentTransition(.numericText())
                    }
                        .frame(width: 640)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.27)
                        .transition(.opacity.combined(with: .offset(y: -12)))
                }

                if state.step == .done {
                    DoneCard(sensitivity: state.sensitivity, reached: state.verified ? state.everLit.count : nil)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }

                // Footer (centred so it never covers the bottom corner dots): step indicator + cancel
                if state.step != .done {
                    HStack(spacing: 28) {
                        StepDots(current: state.stepNumber)
                        CancelButton(action: onCancel)
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height - 44)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: state.step)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: state.pointed)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: state.lit)
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    private var isPlaceStep: Bool { state.step == .place || state.step == .placed }
    /// Bottom-row dots put their label above so it stays on screen.
    static func labelAbove(_ t: Side) -> Bool { t == .bl || t == .br }
}

// MARK: - Background

struct ParticleBackground: View {
    var focus: CGPoint
    @Environment(\.stillFrameTime) private var still
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let still {
            ParticleCanvas(time: still, focus: focus)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 40, paused: reduceMotion)) { ctx in
                ParticleCanvas(time: ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000), focus: focus)
            }
        }
    }
}

private struct ParticleCanvas: View {
    var time: Double
    var focus: CGPoint

    static let particles: [(Double, Double, Double, Double, Double, Double)] = (0..<170).map { i in
        func r(_ k: Int) -> Double { // deterministic hash → 0..1
            let x = sin(Double(i * 7919 + k * 104729) * 12.9898) * 43758.5453
            return x - floor(x)
        }
        // x, y, size, speed, phase, hue (0 cyan … 1 blue)
        return (r(1), r(2), 0.7 + pow(r(3), 2.2) * 2.6, 6 + r(4) * 16, r(5) * .pi * 2, r(6))
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0x02040A), Color(hex: 0x050A18), Color(hex: 0x03060F)]),
                                           startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            // soft light pools (radial gradients, no blur filters: cheap at 40 fps)
            let pools: [(CGPoint, Double, Color, Double)] = [
                (focus, min(w, h) * 0.55, Color(hex: 0x0A84FF), 0.16),
                (CGPoint(x: w * (0.18 + 0.03 * sin(time * 0.05)), y: h * 0.85), w * 0.4, Color(hex: 0x5E5CE6), 0.12),
                (CGPoint(x: w * (0.88 + 0.02 * cos(time * 0.04)), y: h * 0.12), w * 0.32, Color(hex: 0x64D2FF), 0.08),
            ]
            for (c, r, color, a) in pools {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [color.opacity(a), color.opacity(0)]), center: c, startRadius: 0, endRadius: r))
            }
            for p in Self.particles {
                let span = h + 40
                let y = (p.1 * span - time * p.3).truncatingRemainder(dividingBy: span)
                let yy = (y < 0 ? y + span : y) - 20
                let xx = p.0 * w + sin(time * 0.15 + p.4) * 26
                let tw = 0.55 + 0.45 * sin(time * (0.6 + p.5) + p.4)
                let color = p.5 < 0.55 ? Color(hex: 0x64D2FF) : Color(hex: 0x0A84FF)
                let a = (0.28 + 0.62 * tw) * (p.2 > 2 ? 0.75 : 1)
                if p.2 > 1.8 {
                    let hr = p.2 * 5
                    ctx.fill(Path(ellipseIn: CGRect(x: xx - hr, y: yy - hr, width: hr * 2, height: hr * 2)),
                             with: .radialGradient(Gradient(colors: [color.opacity(a * 0.35), color.opacity(0)]),
                                                   center: CGPoint(x: xx, y: yy), startRadius: 0, endRadius: hr))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: xx - p.2 / 2, y: yy - p.2 / 2, width: p.2, height: p.2)), with: .color(color.opacity(a)))
            }
            // vignette
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.55)]), center: CGPoint(x: w / 2, y: h / 2),
                                           startRadius: min(w, h) * 0.45, endRadius: max(w, h) * 0.8))
        }
    }
}

// MARK: - Outline

/// Rounded rectangle path that starts at top-centre and runs clockwise (so `trim` fills like a clock).
struct OutlineShape: Shape {
    var radius: CGFloat
    func path(in r: CGRect) -> Path {
        let rr = min(radius, r.width / 2, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: rr)
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: rr)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: rr)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.midX, y: r.minY), radius: rr)
        p.closeSubpath()
        return p
    }
}

struct PhoneOutline: View {
    var rect: CGRect
    var radius: CGFloat
    var progress: Double
    var still: Bool
    var placed: Bool

    @State private var breathe = false
    @State private var flash = 0.0
    @Environment(\.stillFrameTime) private var stillFrame
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = OutlineShape(radius: radius)
        let lit = stillFrame != nil ? 0.92 : (breathe ? 1.0 : 0.72)
        let tint = placed ? Theme.success : Theme.cyan
        ZStack {
            shape.fill(RadialGradient(colors: [tint.opacity(0.10), tint.opacity(0.02)], center: .center,
                                      startRadius: 0, endRadius: rect.height * 0.6))
            shape.stroke(placed ? Theme.success : Theme.blue, lineWidth: 18).blur(radius: 34).opacity(0.6 * lit)
            shape.stroke(tint, lineWidth: 6).blur(radius: 8).opacity(0.45 * lit)
            shape.stroke(tint, lineWidth: 2).opacity(0.45 + 0.35 * lit)

            // progress ring: brighter, thicker, white-hot core
            shape.trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 16, lineCap: .round)).blur(radius: 12)
            shape.trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            shape.trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))

            shape.fill(.white).opacity(flash)

            if placed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: min(rect.width * 0.34, 120), weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.success)
                    .shadow(color: Theme.success.opacity(0.8), radius: 24)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            } else {
                Image(systemName: "iphone")
                    .font(.system(size: min(rect.width * 0.2, 64), weight: .ultraLight))
                    .foregroundStyle(Theme.cyan.opacity(0.35))
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .animation(.linear(duration: 0.12), value: progress)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: placed)
        .onAppear {
            guard stillFrame == nil, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true }
        }
        .onChange(of: placed) { _, now in
            guard now else { return }
            flash = 0.9
            withAnimation(.easeOut(duration: 0.55)) { flash = 0 }
        }
    }
}

/// Step 1 live guidance (spec 4a): large, because the phone's own screen is dark while it is near the glass.
struct PlaceHintView: View {
    var hint: PlaceHint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { hint.needsAction ? Theme.warning : Theme.cyan }

    private var symbol: String {
        switch hint {
        case .placeInside: "iphone"
        case .bringCloser: "iphone.radiowaves.left.and.right"
        case .holdUpright: "iphone.gen3"
        case .holdStill: "hand.raised.fill"
        case .filling: "checkmark"
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            row
                .id(hint.kind)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 12)).combined(with: .scale(scale: 0.97, anchor: .leading)),
                    removal: .opacity.combined(with: .offset(y: -8))))
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: hint.kind)
    }

    private var row: some View {
        HStack(spacing: 16) {
            badge.frame(width: 52, height: 52)
            Text(hint.text)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if case .filling(let p) = hint {
                Text("\(Int((p * 100).rounded()))%")
                    .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.cyan)
                    .contentTransition(.numericText())
                    .animation(.linear(duration: 0.12), value: p)
            }
        }
        .padding(.leading, 14).padding(.trailing, 24).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder private var badge: some View {
        ZStack {
            Circle().fill(tint.opacity(0.18))
            if case .filling(let p) = hint {
                Circle().stroke(.white.opacity(0.12), lineWidth: 4).padding(4)
                Circle().trim(from: 0, to: p)
                    .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(4)
                    .animation(.linear(duration: 0.12), value: p)
            }
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(hint.needsAction ? Theme.warning : .white)
        }
    }
}

// MARK: - Instructions

struct InstructionBlock<Extra: View>: View {
    var number: Int
    var title: String
    var message: String
    var alignment: HorizontalAlignment
    @ViewBuilder var extra: () -> Extra

    init(number: Int, title: String, message: String, alignment: HorizontalAlignment,
         @ViewBuilder extra: @escaping () -> Extra = { EmptyView() }) {
        self.number = number; self.title = title; self.message = message; self.alignment = alignment; self.extra = extra
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 18) {
            ZStack {
                Circle().fill(Theme.cyan.opacity(0.10))
                Circle().strokeBorder(Theme.cyan.opacity(0.9), lineWidth: 2)
                    .shadow(color: Theme.cyan.opacity(0.7), radius: 8)
                Text("\(number)")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: alignment, spacing: 12) {
                Text("STEP \(number) OF 3")
                    .font(.system(size: 13, weight: .semibold)).kerning(1.6)
                    .foregroundStyle(Theme.cyan)
                Text(title)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.system(size: 21))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(alignment == .center ? .center : .leading)
            extra().padding(.top, 6)
        }
    }
}

struct StepDots: View {
    var current: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Theme.cyan : .white.opacity(i < current ? 0.55 : 0.2))
                    .frame(width: i == current ? 26 : 8, height: 8)
                    .shadow(color: i == current ? Theme.cyan.opacity(0.8) : .clear, radius: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
    }
}

struct CancelButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("esc")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
                Text("Cancel").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(.white.opacity(0.10)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Targets

/// Time source: a fixed time in previews, otherwise a display-linked timeline.
struct Clock<Content: View>: View {
    @ViewBuilder var content: (Double) -> Content
    @Environment(\.stillFrameTime) private var still
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if let still { content(still) } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { ctx in
                content(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
            }
        }
    }
}

struct TargetDot: View {
    var active: Bool
    var hit: Bool
    var showLabel = true
    var labelAbove = false

    var body: some View {
        ZStack {
            if active && !hit {
                Clock { t in
                    ZStack {
                        ForEach(0..<2, id: \.self) { i in
                            let k = (t / 1.8 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                            let e = 1 - pow(1 - k, 2.2) // ease-out growth
                            Circle().strokeBorder(Theme.cyan, lineWidth: 2)
                                .frame(width: 34 + 110 * e, height: 34 + 110 * e)
                                .opacity(0.85 * (1 - k))
                        }
                    }
                }
                Circle().fill(Theme.cyan.opacity(0.25)).frame(width: 90, height: 90).blur(radius: 18)
            }
            if hit {
                Circle().strokeBorder(Theme.success.opacity(0.6), lineWidth: 2).frame(width: 74, height: 74)
                Circle().fill(Theme.success.opacity(0.25)).frame(width: 80, height: 80).blur(radius: 16)
            }
            Circle()
                .fill(hit ? AnyShapeStyle(Theme.success) : AnyShapeStyle(RadialGradient(colors: [.white, Theme.cyan], center: .center, startRadius: 0, endRadius: 16)))
                .frame(width: hit ? 40 : 30, height: hit ? 40 : 30)
                .shadow(color: (hit ? Theme.success : Theme.cyan).opacity(0.9), radius: 12)
            if hit {
                Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
            if showLabel {
                Text(hit ? "Got it" : "Point here")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(hit ? Theme.success : .white)
                    .offset(y: labelAbove ? -72 : 72)
            }
        }
        .frame(width: 160, height: 200)
    }
}

/// v3 pointing: five dots, done ones green, the current one cyan and wide.
struct TargetProgress: View {
    var current: Int
    var pointed: Set<Side>
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(Side.fourCorners.enumerated()), id: \.offset) { i, t in
                Capsule()
                    .fill(pointed.contains(t) ? Theme.success : (i == current ? Theme.cyan : .white.opacity(0.2)))
                    .frame(width: i == current ? 26 : 8, height: 8)
                    .shadow(color: i == current ? Theme.cyan.opacity(0.8) : .clear, radius: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
    }
}

struct TurnGuide: View {
    var from: CGPoint
    var to: CGPoint
    var body: some View {
        let a = CGPoint(x: from.x + 70, y: from.y), b = CGPoint(x: to.x - 70, y: to.y)
        ZStack {
            Path { p in p.move(to: a); p.addLine(to: b) }
                .stroke(LinearGradient(colors: [Theme.success.opacity(0.45), Theme.cyan.opacity(0.5)], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 12]))
            Image(systemName: "chevron.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.cyan.opacity(0.6))
                .position(x: (a.x + b.x) / 2, y: a.y)
        }
    }
}

// MARK: - Done

struct DoneCard: View {
    var sensitivity: Double?
    /// v3 verify: dots the cursor reached (nil = no verify step, older phone).
    var reached: Int? = nil
    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Theme.success.opacity(0.28)).frame(width: 170, height: 170).blur(radius: 30)
                Circle().fill(LinearGradient(colors: [Color(hex: 0x4BE37A), Theme.success], startPoint: .top, endPoint: .bottom))
                    .frame(width: 112, height: 112)
                    .shadow(color: Theme.success.opacity(0.6), radius: 20)
                Image(systemName: "checkmark").font(.system(size: 50, weight: .bold)).foregroundStyle(.white)
            }
            Text("You’re All Set")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(.white)
            Text("AirMouse is calibrated. Point, click and present.")
                .font(.system(size: 21))
                .foregroundStyle(.white.opacity(0.72))
            if let reached {
                Label(reached == 5 ? "Your pointer reached all 5 dots" : "Your pointer reached \(reached) of 5 dots",
                      systemImage: reached == 5 ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(reached == 5 ? Theme.success : Theme.warning)
            }
            if let sensitivity {
                Text("Sensitivity \(Int(sensitivity.rounded())) pt/rad")
                    .font(.system(size: 15, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.08)))
            }
        }
    }
}
