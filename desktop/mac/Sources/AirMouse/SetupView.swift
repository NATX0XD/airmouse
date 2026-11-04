import SwiftUI
import AirMouseCore

// MARK: - Copy + look per permission

extension PermissionKind {
    var name: String {
        switch self {
        case .accessibility: "Pointer Control"
        case .bluetooth: "Bluetooth"
        case .localNetwork: "Local Network"
        case .firewall: "Firewall"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "cursorarrow.motionlines"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .localNetwork: "wifi"
        case .firewall: "network.badge.shield.half.filled"
        }
    }

    var color: Color {
        switch self {
        case .accessibility: Theme.blue
        case .bluetooth: Theme.indigo
        case .localNetwork: Color(nsColor: .systemTeal)
        case .firewall: Theme.purple
        }
    }

    var title: String {
        switch self {
        case .accessibility: "Allow Pointer Control"
        case .bluetooth: "Connect over Bluetooth"
        case .localNetwork: "Allow Local Network"
        case .firewall: "Check the Firewall"
        }
    }

    var why: String {
        switch self {
        case .accessibility: "AirMouse needs Accessibility access to move the cursor, click and scroll for you."
        case .bluetooth: "Lets your iPhone connect directly, even when you’re not on the same Wi-Fi."
        case .localNetwork: "Lets iPhones on your Wi-Fi find this Mac and connect to it."
        case .firewall: "The macOS firewall can stop your iPhone from reaching AirMouse over Wi-Fi."
        }
    }

    var hint: String {
        switch self {
        case .accessibility: "Click Open Settings, switch on AirMouse, then come back. This page updates by itself."
        case .bluetooth: "macOS will ask once. You can change it later in Privacy & Security › Bluetooth."
        case .localNetwork: "If macOS asked, click Allow. Otherwise switch on AirMouse in Privacy & Security › Local Network."
        case .firewall: "In Network › Firewall › Options, set AirMouse to Allow incoming connections."
        }
    }

    var requirementLabel: String {
        switch requirement {
        case .required: "Required"
        case .optional: "Optional"
        case .info: "Check"
        }
    }

    func actionTitle(for status: PermissionStatus) -> String? {
        switch (self, status) {
        case (_, .granted), (_, .checking): nil
        case (.accessibility, _): "Open Accessibility Settings"
        case (.bluetooth, .notDetermined): "Allow Bluetooth"
        case (.bluetooth, .off): "Open Bluetooth Settings"
        case (.bluetooth, _): "Open Bluetooth Privacy"
        case (.localNetwork, _): "Open Local Network Settings"
        case (.firewall, _): "Open Firewall Settings"
        }
    }

    func statusText(_ s: PermissionStatus, firewall: String) -> String {
        switch s {
        case .checking: return "Checking…"
        case .granted:
            switch self {
            case .accessibility: return "Pointer control is on"
            case .bluetooth: return "Bluetooth is ready"
            case .localNetwork: return "Your iPhone can find this Mac"
            case .firewall: return firewall
            }
        case .notDetermined: return "Waiting for permission…"
        case .denied: return "Not allowed yet"
        case .off(let why), .attention(let why): return why
        }
    }
}

struct PermissionIcon: View {
    var kind: PermissionKind
    var size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [kind.color.opacity(0.85), kind.color], startPoint: .top, endPoint: .bottom))
            Image(systemName: kind.symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: kind.color.opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

struct StatusPill: View {
    var text: String
    var status: PermissionStatus

    var body: some View {
        HStack(spacing: 8) {
            switch status {
            case .checking, .notDetermined:
                ProgressView().controlSize(.small).scaleEffect(0.8).frame(width: 14, height: 14)
            case .granted:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
            case .denied:
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.error)
            case .off, .attention:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            }
            Text(text).font(.system(size: 13, weight: .medium))
                .foregroundStyle(status == .granted ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(status == .granted ? Theme.success.opacity(0.14) : Color.primary.opacity(0.06)))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: status)
    }
}

// MARK: - Main window rows

struct PermissionWarningsCard: View {
    var model: AppModel
    var open: (PermissionKind) -> Void

    var body: some View {
        let kinds = model.setup.warnings
        let required = kinds.contains { $0.requirement == .required }
        VStack(spacing: 0) {
            ForEach(Array(kinds.enumerated()), id: \.element) { i, k in
                if i > 0 { Divider().padding(.leading, 40) }
                Button { open(k) } label: {
                    HStack(spacing: 10) {
                        PermissionIcon(kind: k, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rowTitle(k)).font(.system(size: 13, weight: .semibold))
                            Text(rowDetail(k)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text("Fix").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(k.requirement == .required ? Theme.warning : .secondary)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            shape.fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                .overlay { if required { shape.fill(Theme.warning.opacity(0.07)) } }
                .overlay { shape.strokeBorder(required ? Theme.warning.opacity(0.35) : Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5) }
        }
    }

    private func rowTitle(_ k: PermissionKind) -> String {
        switch (k, model.setup.status(k)) {
        case (.accessibility, _): "Allow pointer control"
        case (.localNetwork, _): "Allow Local Network"
        case (.bluetooth, .off): "Bluetooth is off"
        case (.bluetooth, _): "Bluetooth isn’t set up"
        case (.firewall, _): "Firewall may block your iPhone"
        }
    }

    private func rowDetail(_ k: PermissionKind) -> String {
        switch k {
        case .accessibility: "Required · moves the cursor and clicks"
        case .localNetwork: "Required · for Wi-Fi connections"
        case .bluetooth: "Optional · connect without Wi-Fi"
        case .firewall: model.firewallDetail
        }
    }
}

// MARK: - Permissions page (inline stepper: vertical checklist, selected row expands)

struct PermissionsPage: View {
    var model: AppModel

    var body: some View {
        let flow = model.setup
        let done = flow.steps.filter(flow.isSatisfied).count
        Page(title: "Permissions", subtitle: "AirMouse needs a few permissions to control the pointer and talk to your iPhone.") {
            ProgressHeader(done: done, total: flow.steps.count, ready: flow.allRequiredGranted)
            VStack(spacing: 0) {
                ForEach(Array(flow.steps.enumerated()), id: \.element) { i, k in
                    if i > 0 { Divider().padding(.leading, 56) }
                    PermissionStepRow(model: model, kind: k, number: i + 1, expanded: flow.current == k)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background {
                let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                shape.fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                    .overlay { shape.strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.5) }
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            }
            Text("Status updates by itself while this page is open.")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: model.setup.index)
    }
}

private struct ProgressHeader: View {
    var done: Int
    var total: Int
    var ready: Bool
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 5)
                Circle().trim(from: 0, to: Double(done) / Double(max(1, total)))
                    .stroke(ready ? AnyShapeStyle(Theme.success) : AnyShapeStyle(Theme.aurora), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(done)/\(total)").font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(ready ? (done == total ? "AirMouse Is Ready" : "Ready to Go") : "Almost There")
                    .font(.system(size: 17, weight: .semibold))
                Text(ready ? (done == total ? "Everything is set up." : "The required permissions are on. The rest is optional.")
                           : "Turn on the required permissions below.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: done)
    }
}

private struct PermissionStepRow: View {
    var model: AppModel
    var kind: PermissionKind
    var number: Int
    var expanded: Bool

    var body: some View {
        let flow = model.setup
        let status = flow.status(kind)
        let satisfied = flow.isSatisfied(kind)
        VStack(alignment: .leading, spacing: 0) {
            Button { model.setup.open(kind) } label: {
                HStack(spacing: 12) {
                    PermissionIcon(kind: kind, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(kind.name).font(.system(size: 14, weight: .semibold))
                            Text(kind.requirementLabel).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        if !expanded {
                            Text(kind.statusText(status, firewall: model.firewallDetail))
                                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    trailing(satisfied: satisfied, status: status, skipped: flow.skipped.contains(kind))
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                detail(status: status)
                    .padding(.leading, 42)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }

    @ViewBuilder private func trailing(satisfied: Bool, status: PermissionStatus, skipped: Bool) -> some View {
        if satisfied {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.success)
                .transition(.scale.combined(with: .opacity))
        } else if status == .checking {
            ProgressView().controlSize(.small)
        } else if skipped {
            Text("Skipped").font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            Text(kind.requirement == .required ? "Needed" : "Not set up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(kind.requirement == .required ? Theme.warning : .secondary)
        }
    }

    private func detail(status: PermissionStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kind.why).font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            StatusPill(text: kind.statusText(status, firewall: model.firewallDetail), status: status)
            if kind.actionTitle(for: status) != nil {
                Text(kind.hint).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if let action = kind.actionTitle(for: status) {
                    Button(action: { model.grant(kind) }) {
                        Label(action, systemImage: "arrow.up.forward.app")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(kind.color))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                if model.setup.canSkip(kind) && kind.requirement != .info {
                    Button("Skip for Now") { model.setup.skipStep() }
                        .controlSize(.regular)
                }
                if model.setup.canContinue(kind) {
                    Button(model.setup.stepNumber == model.setup.steps.count ? "Done" : "Continue") { model.setup.continueStep() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}
