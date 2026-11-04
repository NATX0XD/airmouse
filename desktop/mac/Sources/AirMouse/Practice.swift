import AppKit
import SwiftUI
import AirMouseCore

// MARK: - Controller

/// Click Practice: fullscreen overlay like calibration (same level and look), but it takes mouse clicks.
@MainActor
final class PracticeOverlayController {
    private unowned let model: AppModel
    private var panel: OverlayPanel?
    private var monitors: [Any] = []
    private(set) var isShowing = false

    init(model: AppModel) { self.model = model }

    func sync() { model.practice != nil ? show() : hide() }

    private func show() {
        guard !isShowing else { return }
        isShowing = true
        guard let frame = (NSScreen.screens.first ?? NSScreen.main)?.frame else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            panel.animator().alphaValue = 1
        }
        let esc: (NSEvent) -> Bool = { $0.keyCode == 53 }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard esc(e) else { return e }
            MainActor.assumeIsolated { self?.model.stopPractice(notifyPhone: true) }
            return nil
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard esc(e) else { return }
            MainActor.assumeIsolated { self?.model.stopPractice(notifyPhone: true) }
        }) { monitors.append(m) }
    }

    private func hide() {
        guard isShowing, let panel else { return }
        isShowing = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShowing else { return }
                panel.orderOut(nil)
            }
        })
    }

    private func makePanel() -> OverlayPanel {
        let p = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .black
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none
        p.ignoresMouseEvents = false
        p.acceptsMouseMovedEvents = true
        p.contentView = FirstMouseHostingView(rootView: PracticeRoot(model: model))
        return p
    }
}

/// The first click lands on the target even when AirMouse is not the active app.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct PracticeRoot: View {
    var model: AppModel
    var body: some View {
        if let game = model.practice {
            PracticeView(game: game,
                         onClick: { p, size in model.practiceClick(at: p, in: size) },
                         onCancel: { model.stopPractice(notifyPhone: true) },
                         onRetry: model.startPractice,
                         onDone: { model.stopPractice(notifyPhone: false) })
        } else {
            Color.black
        }
    }
}

// MARK: - View

struct PracticeEffect: Identifiable, Equatable {
    enum Kind { case pop, miss }
    let id = UUID()
    var kind: Kind
    var point: CGPoint
    var diameter: Double
}

struct PracticeView: View {
    var game: PracticeGame
    var onClick: (CGPoint, CGSize) -> PracticeGame.ClickResult
    var onCancel: () -> Void
    var onRetry: () -> Void
    var onDone: () -> Void
    /// Previews pass fixed effects; live clicks add their own.
    var previewEffects: [PracticeEffect] = []

    @State private var effects: [PracticeEffect] = []

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ParticleBackground(focus: game.currentCenter(in: size) ?? CGPoint(x: size.width / 2, y: size.height / 2))
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { v in tap(v.location, size) })

                PracticeHeader(game: game)
                    .frame(width: 640)
                    .position(x: size.width / 2, y: max(70, size.height * 0.075))
                    .allowsHitTesting(false)
                    .opacity(game.phase == .finished ? 0 : 1)

                ForEach(previewEffects + effects) { e in
                    PracticeEffectView(effect: e).position(e.point).allowsHitTesting(false)
                }

                if let c = game.currentCenter(in: size) {
                    PracticeTarget(diameter: game.currentDiameter)
                        .id(game.index)
                        .position(c)
                        .allowsHitTesting(false) // the background takes the click and does the hit test
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if game.phase == .finished {
                    Color.black.opacity(0.35).transition(.opacity)
                    PracticeResultCard(game: game, onRetry: onRetry, onDone: onDone)
                        .position(x: size.width / 2, y: size.height / 2)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                } else {
                    CancelButton(action: onCancel)
                        .position(x: size.width - 120, y: size.height - 44)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: game.index)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: game.phase)
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .onChange(of: game.targets) { _, _ in effects.removeAll() } // Try Again
    }

    private func tap(_ p: CGPoint, _ size: CGSize) {
        let diameter = game.currentDiameter
        let center = game.currentCenter(in: size)
        let effect: PracticeEffect
        switch onClick(p, size) {
        case .hit: effect = PracticeEffect(kind: .pop, point: center ?? p, diameter: diameter)
        case .miss: effect = PracticeEffect(kind: .miss, point: p, diameter: 34)
        case .ignored: return
        }
        effects.append(effect)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { effects.removeAll { $0.id == effect.id } }
    }
}

struct PracticeHeader: View {
    var game: PracticeGame
    var body: some View {
        VStack(spacing: 10) {
            Text("CLICK PRACTICE")
                .font(.system(size: 13, weight: .semibold)).kerning(1.6)
                .foregroundStyle(Theme.cyan)
            Text(game.phase == .finished ? "Done" : "Click Each Circle")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
            Text("Point with your iPhone and tap to click.")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.68))
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    ForEach(0..<game.count, id: \.self) { i in
                        Capsule()
                            .fill(i < game.index ? Theme.cyan : (i == game.index ? .white.opacity(0.85) : .white.opacity(0.18)))
                            .frame(width: i == game.index ? 22 : 8, height: 8)
                            .shadow(color: i < game.index ? Theme.cyan.opacity(0.7) : .clear, radius: 5)
                    }
                }
                Text("\(min(game.index + 1, game.count)) of \(game.count)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .contentTransition(.numericText())
            }
            .padding(.top, 4)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.index)
        }
    }
}

struct PracticeTarget: View {
    var diameter: Double
    @State private var shown = false
    @Environment(\.stillFrameTime) private var still

    var body: some View {
        ZStack {
            Clock { t in
                let k = (t / 1.6).truncatingRemainder(dividingBy: 1)
                Circle().strokeBorder(Theme.cyan, lineWidth: 2)
                    .frame(width: diameter * (1 + 0.6 * k), height: diameter * (1 + 0.6 * k))
                    .opacity(0.7 * (1 - k))
            }
            Circle().fill(Theme.blue.opacity(0.3)).frame(width: diameter * 2, height: diameter * 2).blur(radius: diameter * 0.5)
            Circle().fill(Theme.cyan.opacity(0.35)).frame(width: diameter * 1.35, height: diameter * 1.35).blur(radius: diameter * 0.18)
            Circle()
                .fill(RadialGradient(colors: [.white, Theme.cyan, Theme.cyan.opacity(0.85)], center: .center,
                                     startRadius: 0, endRadius: diameter / 2))
                .frame(width: diameter, height: diameter)
                .shadow(color: Theme.cyan.opacity(0.9), radius: 14)
            Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2).frame(width: diameter, height: diameter)
        }
        .frame(width: diameter * 2.2, height: diameter * 2.2)
    }
}

struct PracticeEffectView: View {
    var effect: PracticeEffect
    @State private var k = 0.0
    @Environment(\.stillFrameTime) private var still

    var body: some View {
        let t = still != nil ? 0.35 : k
        let tint = effect.kind == .pop ? Theme.cyan : Theme.error
        let d = effect.diameter
        ZStack {
            if effect.kind == .pop {
                Circle().fill(RadialGradient(colors: [.white, Theme.cyan.opacity(0.6)], center: .center, startRadius: 0, endRadius: d / 2))
                    .frame(width: d, height: d)
                    .scaleEffect(1 + 0.5 * t).opacity(0.85 * (1 - t))
                ForEach(0..<8, id: \.self) { i in
                    let a = Double(i) / 8 * .pi * 2
                    Circle().fill(Theme.cyan).frame(width: 7, height: 7)
                        .offset(x: cos(a) * d * (0.5 + 0.7 * t), y: sin(a) * d * (0.5 + 0.7 * t))
                        .opacity(1 - t)
                }
            }
            Circle().strokeBorder(tint, lineWidth: effect.kind == .pop ? 3 : 2)
                .frame(width: d, height: d)
                .scaleEffect(1 + (effect.kind == .pop ? 1.2 : 0.9) * t)
                .opacity(1 - t)
            if effect.kind == .miss {
                Circle().fill(tint.opacity(0.5)).frame(width: 8, height: 8).opacity(1 - t)
            }
        }
        .frame(width: d * 3, height: d * 3)
        .onAppear {
            guard still == nil else { return }
            withAnimation(.easeOut(duration: effect.kind == .pop ? 0.5 : 0.6)) { k = 1 }
        }
    }
}

struct PracticeResultCard: View {
    var game: PracticeGame
    var onRetry: () -> Void
    var onDone: () -> Void

    private var title: String {
        switch game.accuracy {
        case 0.9...: "Great Aim"
        case 0.7..<0.9: "Nice Work"
        default: "Keep Practicing"
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Theme.cyan.opacity(0.25)).frame(width: 150, height: 150).blur(radius: 28)
                Circle().fill(LinearGradient(colors: [Color(hex: 0x8FE3FF), Theme.cyan, Theme.blue], startPoint: .top, endPoint: .bottom))
                    .frame(width: 96, height: 96)
                    .shadow(color: Theme.cyan.opacity(0.6), radius: 18)
                Image(systemName: "scope").font(.system(size: 44, weight: .semibold)).foregroundStyle(.white)
            }
            VStack(spacing: 8) {
                Text(title).font(.system(size: 44, weight: .bold)).foregroundStyle(.white)
                Text("You hit all \(game.count) targets.")
                    .font(.system(size: 19)).foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 0) {
                stat("\(game.hits)/\(game.total)", "Hits / Clicks")
                Divider().frame(height: 44).overlay(.white.opacity(0.2))
                stat("\(Int((game.accuracy * 100).rounded()))%", "Accuracy")
                Divider().frame(height: 44).overlay(.white.opacity(0.2))
                stat(String(format: "%.2f s", Double(game.averageMs) / 1000), "Avg per Target")
            }
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.06)))
            HStack(spacing: 12) {
                Button(action: onDone) { Text("Done") }
                    .buttonStyle(OverlaySoftButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(action: onRetry) { Label("Try Again", systemImage: "arrow.clockwise") }
                    .buttonStyle(AuroraButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(36)
        .frame(width: 520)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(hex: 0x0B1220).opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 40, y: 10)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

/// White-on-dark secondary button for the overlays.
struct OverlaySoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.2 : 0.12))
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
