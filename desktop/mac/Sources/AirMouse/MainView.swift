import SwiftUI
import AirMouseCore

// MARK: - Status

struct StatusCard: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary
            Divider().opacity(0.6)
            VStack(alignment: .leading, spacing: 7) {
                TransportRow(symbol: "wifi", name: "Wi-Fi", detail: wifiDetail.0, color: wifiDetail.1)
                TransportRow(symbol: "dot.radiowaves.left.and.right", name: "Bluetooth", detail: bleDetail.0, color: bleDetail.1)
            }
        }
        .card()
    }

    private var wifiDetail: (String, Color) {
        if let err = model.serverError { return ("Off · \(err)", Theme.error) }
        guard let port = model.port else { return ("Starting…", .secondary) }
        if let p = model.phones.last { return ("Connected to \(p.name)", Theme.success) }
        return ("Listening on port \(String(port))", Theme.blue)
    }

    private var bleDetail: (String, Color) {
        switch model.bluetooth {
        case .off(let why): return ("Off · \(why)", .secondary)
        case .advertising: return ("Advertising as \(BLESpec.localName(macName: model.macName))", Theme.blue)
        case .connected: return ("Connected to \(model.blePhones.last?.name ?? "iPhone")", Theme.success)
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            StatusOrb(connected: model.isConnected, failed: model.serverError != nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        if model.serverError != nil { return "Couldn’t Start" }
        return StatusText.title(connectedTo: model.primaryPhone?.name)
    }

    private var subtitle: String {
        if let err = model.serverError { return err }
        if let phone = model.primaryPhone {
            let extra = model.phones.count > 1 ? " · \(model.phones.count) phones" : ""
            return (phone.model ?? "iPhone") + extra + (model.primaryViaBluetooth ? " · Bluetooth" : " · Wi-Fi") + " · " + StatusText.rate(model.rate)
        }
        return "Open AirMouse on your iPhone and choose this Mac."
    }
}

struct StatusOrb: View {
    var connected: Bool
    var failed: Bool
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = failed ? Theme.error : (connected ? Theme.success : Theme.warning)
        ZStack {
            Circle().fill(color.opacity(0.16))
                .scaleEffect(pulse && !reduceMotion ? 1.18 : 1)
                .opacity(pulse ? 0.5 : 1)
            Circle()
                .fill(connected ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Color.primary.opacity(0.08)))
                .frame(width: 34, height: 34)
            Image(systemName: failed ? "exclamationmark.triangle.fill" : "iphone")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(connected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            Circle().fill(color).frame(width: 11, height: 11)
                .overlay(Circle().stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 2))
                .offset(x: 14, y: 14)
        }
        .frame(width: 46, height: 46)
        .onAppear {
            guard !connected else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

struct TransportRow: View {
    var symbol: String
    var name: String
    var detail: String
    var color: Color
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
                .frame(width: 18)
            Text(name).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
    }
}

// MARK: - Banner

struct BannerRow: View {
    var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone.slash").foregroundStyle(Theme.warning)
                .font(.system(size: 15, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.warning.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.warning.opacity(0.35), lineWidth: 0.5))
    }
}

// MARK: - Menu bar

struct MenuContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private func show(_ section: AppSection) {
        if section == .permissions { model.openSetup() } else { model.section = section }
        openWindow(id: "main")
        NSApp.activate()
    }

    var body: some View {
        Text(StatusText.menuLine(connectedTo: model.primaryPhone?.name, port: model.port))
        if !model.setup.warnings.isEmpty {
            Text("\(model.setup.warnings.count) permission\(model.setup.warnings.count == 1 ? "" : "s") need attention")
        }
        Divider()
        Button("Setup…") { show(.permissions) }
        Button("Calibrate…", action: model.requestCalibration)
        Button("Practice Clicking…", action: model.startPractice)
        Button("Center Cursor", action: model.centerCursor)
        Divider()
        Button("Show AirMouse") { openWindow(id: "main"); NSApp.activate() }
        Divider()
        Button("Quit AirMouse") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
