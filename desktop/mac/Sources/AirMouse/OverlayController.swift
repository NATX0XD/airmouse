import AppKit
import SwiftUI
import AirMouseCore

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Fullscreen calibration overlay on the main display (the one with the menu bar).
@MainActor
final class OverlayController {
    private unowned let model: AppModel
    private var panel: OverlayPanel?
    private var monitors: [Any] = []
    private var showing = false
    var isShowing: Bool { showing }

    init(model: AppModel) { self.model = model }

    func sync() {
        model.calibration.visible ? show() : hide()
    }

    private func show() {
        guard !showing else { return }
        showing = true
        let screen = NSScreen.screens.first ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            panel.animator().alphaValue = 1
        }
        // Esc works whether or not AirMouse is the active app.
        let esc: (NSEvent) -> Bool = { $0.keyCode == 53 }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard esc(e) else { return e }
            MainActor.assumeIsolated { self?.model.cancelCalibrationFromMac() }
            return nil
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard esc(e) else { return }
            MainActor.assumeIsolated { self?.model.cancelCalibrationFromMac() }
        }) { monitors.append(m) }
    }

    private func hide() {
        guard showing, let panel else { return }
        showing = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.showing else { return }
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
        p.contentView = NSHostingView(rootView: OverlayRoot(model: model))
        return p
    }
}

private struct OverlayRoot: View {
    var model: AppModel
    var body: some View {
        OverlayView(state: model.calibration, phone: model.primaryPhone?.device ?? PhoneDevice(),
                    screen: model.screen, onCancel: model.cancelCalibrationFromMac)
    }
}
