import SwiftUI

/// "From Sensor to Cursor": nine-page visual stepper opened from About. Diagrams are drawn in code.
enum SensorPreview { nonisolated(unsafe) static var frozen = false }

/// Drives an animation clock; static (at `still`) under Reduce Motion or in preview renders.
private struct Motion<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    var still: Double = 1.5
    @ViewBuilder var content: (Double) -> Content
    var body: some View {
        if reduce || SensorPreview.frozen { content(still) }
        else { TimelineView(.animation) { content($0.date.timeIntervalSinceReferenceDate) } }
    }
}

private func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
private func noise(_ i: Double) -> Double { let s = sin(i * 12.9898) * 43758.5453; return (s - floor(s)) * 2 - 1 }

struct SensorToCursorView: View {
    var initialPage = 0
    var onClose: () -> Void
    @State private var page = 0
    @State private var loaded = false

    private struct Item { let title: String; let body: String }
    private static let items: [Item] = [
        .init(title: "The gyroscope measures turning speed.", body: "It doesn't know where you point. It only knows how fast you are turning, and it checks 100 times a second, every 10 ms."),
        .init(title: "Three directions, two used.", body: "Turning left or right moves the cursor sideways. Tilting the top up or down moves it up or down. Twisting your wrist is ignored."),
        .init(title: "Removing the drift.", body: "Even lying still, the sensor reads a tiny bit wrong (called bias). During calibration, AirMouse measures it for 2 seconds while the phone rests on the screen, then subtracts it, so the cursor doesn't creep."),
        .init(title: "Calming shaky hands.", body: "A smart filter (the One Euro filter) smooths slow, shaky movement but lets quick moves through instantly. Tiny wobbles are squashed to almost zero."),
        .init(title: "Speed × time = distance.", body: "Turning speed × time × your calibration setting is how many dots the cursor moves. Flicking fast adds a little extra (acceleration)."),
        .init(title: "Calibration sets the scale.", body: "Pointing at 5 dots teaches AirMouse how many dots one degree of turning should be, separately for sideways and up/down."),
        .init(title: "A tiny message to your Mac.", body: "The phone sends a short note like “move 7.9 right, 0.4 up”, only while you hold the pad (Hold to Point) or always (Always On). Bluetooth can't keep up, so notes are combined."),
        .init(title: "The Mac moves the cursor smoothly.", body: "The Mac app gathers the notes and nudges the cursor on every screen refresh, up to 120 times a second. If a note arrives late, the cursor glides instead of stopping."),
        .init(title: "The whole journey.", body: "From a turn of your wrist to a cursor on screen, in seven small steps."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text(Self.items[page].title).font(.system(size: 28, weight: .bold)).multilineTextAlignment(.center)
                        Text(Self.items[page].body).font(.system(size: 15)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).frame(maxWidth: 560).fixedSize(horizontal: false, vertical: true)
                    }
                    diagram.frame(width: 600, height: 270)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.045)))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    if page == 8 {
                        Text("The accelerometer and proximity sensor are only used during calibration; the touchscreen clicks and turns pointing on and off.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 34).padding(.horizontal, 32)
                .id(page)
                .transition(.opacity)
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction).padding(14).help("Close")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Button("Back") { page -= 1 }.opacity(page > 0 ? 1 : 0).disabled(page == 0)
                Spacer()
                HStack(spacing: 7) {
                    ForEach(0..<Self.items.count, id: \.self) { i in
                        Capsule().fill(i == page ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Color.primary.opacity(0.18)))
                            .frame(width: i == page ? 22 : 7, height: 7)
                    }
                }
                Spacer()
                Button { if page == Self.items.count - 1 { onClose() } else { page += 1 } } label: {
                    Text(page == Self.items.count - 1 ? "Done" : "Next").frame(minWidth: 90)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 720, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.25), value: page)
        .onAppear { if !loaded { page = min(max(initialPage, 0), Self.items.count - 1); loaded = true } }
    }

    @ViewBuilder private var diagram: some View {
        switch page {
        case 0: GyroDiagram()
        case 1: DirectionsDiagram()
        case 2: DriftDiagram()
        case 3: SmoothDiagram()
        case 4: EquationDiagram()
        case 5: CalibDiagram()
        case 6: MessagesDiagram()
        case 7: BurstDiagram()
        default: ChainDiagram()
        }
    }
}

// MARK: - Shared pieces

private struct PhoneBody: View {
    var w: CGFloat = 56
    var tint: Color = Theme.blue
    var body: some View {
        RoundedRectangle(cornerRadius: w * 0.2, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.12)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: w * 0.2, style: .continuous).strokeBorder(Color.primary.opacity(0.55), lineWidth: 1.5))
            .overlay(alignment: .top) { Capsule().fill(Color.primary.opacity(0.5)).frame(width: w * 0.3, height: 4).padding(.top, 6) }
            .frame(width: w, height: w * 2.05)
    }
}

/// Curved arrow along an ellipse; angles in degrees, increasing = clockwise on screen.
private struct ArcArrow: Shape {
    var from: Double, to: Double
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), rx = r.width / 2, ry = r.height / 2
        func pt(_ d: Double) -> CGPoint { CGPoint(x: c.x + rx * cos(d * .pi / 180), y: c.y + ry * sin(d * .pi / 180)) }
        var d = from
        p.move(to: pt(d))
        while d < to { d += 4; p.addLine(to: pt(min(d, to))) }
        let tip = pt(to), a = to * .pi / 180
        var tx = -rx * sin(a), ty = ry * cos(a); let l = max(hypot(tx, ty), 0.001); tx /= l; ty /= l
        let nx = -ty, ny = tx
        p.move(to: CGPoint(x: tip.x - tx * 11 + nx * 6, y: tip.y - ty * 11 + ny * 6))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x - tx * 11 - nx * 6, y: tip.y - ty * 11 - ny * 6))
        return p
    }
}

private func chip(_ text: String, _ color: Color) -> some View {
    Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
}

// MARK: - 1 Gyroscope

private struct GyroDiagram: View {
    var body: some View {
        Motion(still: 0.45) { t in
            let sway = sin(t * 1.6) * 7
            let tick = Int(t * 20) % 20
            VStack(spacing: 16) {
                ZStack {
                    ArcArrow(from: 200, to: 520).stroke(Theme.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 190, height: 52).offset(y: 6)
                    ArcArrow(from: -70, to: 250).stroke(Theme.purple, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 58, height: 170)
                    PhoneBody(w: 58).rotationEffect(.degrees(sway)).scaleEffect(x: cos(sway * 0.1), y: 1)
                    Text("yaw").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.blue).offset(x: 112, y: 28)
                    Text("pitch").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.purple).offset(x: 44, y: -80)
                    Text("roll").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.cyan).offset(x: -112, y: -20)
                    ArcArrow(from: 150, to: 450).stroke(Theme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 112, height: 112).opacity(0.9)
                }
                .frame(height: 176)
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        ForEach(0..<20, id: \.self) { i in
                            Capsule().fill(i == tick ? Theme.blue : Color.primary.opacity(0.15)).frame(width: 6, height: i == tick ? 20 : 12)
                        }
                    }
                    chip("100 readings / second", Theme.blue)
                    chip("every 10 ms", Theme.indigo)
                }
            }
        }
    }
}

// MARK: - 2 Directions

private struct DirectionsDiagram: View {
    var body: some View {
        Motion(still: 0.6) { t in
            let s = sin(t * 1.8)
            HStack(spacing: 14) {
                column("Turn left / right", "Cursor moves sideways", Theme.blue, active: true,
                       cursor: CGPoint(x: 0.5 + 0.34 * s, y: 0.5)) {
                    PhoneBody(w: 40, tint: Theme.blue).scaleEffect(x: cos(s * 0.5), y: 1).offset(x: s * 14)
                }
                column("Tilt up / down", "Cursor moves up and down", Theme.purple, active: true,
                       cursor: CGPoint(x: 0.5, y: 0.5 + 0.3 * s)) {
                    PhoneBody(w: 40, tint: Theme.purple).scaleEffect(x: 1, y: cos(s * 0.5)).offset(y: s * 8)
                }
                column("Twist your wrist", "Ignored", .gray, active: false, cursor: CGPoint(x: 0.5, y: 0.5)) {
                    PhoneBody(w: 40, tint: .gray).rotationEffect(.degrees(s * 22))
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func column<P: View>(_ title: String, _ sub: String, _ color: Color, active: Bool, cursor: CGPoint,
                                 @ViewBuilder phone: () -> P) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                GeometryReader { g in
                    Image(systemName: "cursorarrow").font(.system(size: 16)).foregroundStyle(active ? color : Color.secondary)
                        .position(x: g.size.width * cursor.x, y: g.size.height * cursor.y)
                }
            }
            .frame(height: 72)
            phone().frame(height: 86).opacity(active ? 1 : 0.4)
            VStack(spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(active ? Color.primary : Color.secondary)
                Text(sub).font(.system(size: 12)).foregroundStyle(active ? color : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 3 Drift

private struct DriftDiagram: View {
    var body: some View {
        Motion(still: 4.0) { t in
            let c = t.truncatingRemainder(dividingBy: 9)
            let drifting = c < 3.5, measuring = c >= 3.5 && c < 6
            let prog = measuring ? (c - 3.5) / 2.5 : (c >= 6 ? 1 : 0)
            let bias = c < 3.5 ? 0.03 : (measuring ? 0.03 : 0.0)
            HStack(spacing: 24) {
                Canvas { ctx, size in
                    let box = CGRect(x: 6, y: 6, width: size.width - 12, height: size.height - 12)
                    ctx.fill(Path(roundedRect: box, cornerRadius: 12), with: .color(.primary.opacity(0.06)))
                    ctx.stroke(Path(roundedRect: box, cornerRadius: 12), with: .color(.primary.opacity(0.25)), lineWidth: 1)
                    let home = CGPoint(x: box.midX - 30, y: box.midY - 20)
                    let off = drifting ? ease(c / 3.5) : 0
                    let pos = CGPoint(x: home.x + 70 * off, y: home.y + 38 * off)
                    if drifting {
                        var trail = Path(); trail.move(to: home); trail.addLine(to: pos)
                        ctx.stroke(trail, with: .color(Theme.error.opacity(0.5)), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    }
                    let col: Color = drifting ? Theme.error : Theme.success
                    ctx.fill(Path(ellipseIn: CGRect(x: pos.x - 13, y: pos.y - 13, width: 26, height: 26)), with: .color(col.opacity(0.2)))
                    ctx.fill(Path(ellipseIn: CGRect(x: pos.x - 7, y: pos.y - 7, width: 14, height: 14)), with: .color(col))
                }
                .frame(width: 300, height: 220)
                VStack(alignment: .leading, spacing: 14) {
                    step("1", "Phone lies still", "Cursor creeps by itself", active: drifting, color: Theme.error)
                    step("2", "Calibration measures the bias", "Resting on the screen, 2 seconds", active: measuring, color: Theme.blue)
                    step("3", "Bias is subtracted", "Cursor stays put", active: c >= 6, color: Theme.success)
                    ProgressView(value: prog).tint(Theme.blue).frame(width: 220)
                    Text(String(format: "reading while still: %@%.2f°/s", bias > 0 ? "+" : "", bias))
                        .font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(bias > 0 ? Theme.error : Theme.success)
                }
            }
        }
    }

    private func step(_ n: String, _ title: String, _ sub: String, active: Bool, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(n).font(.system(size: 12, weight: .bold)).foregroundStyle(active ? Color.white : Color.secondary)
                .frame(width: 22, height: 22).background(Circle().fill(active ? color : Color.primary.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(sub).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .opacity(active ? 1 : 0.55)
        }
    }
}

// MARK: - 4 Smoothing

private struct SmoothDiagram: View {
    var body: some View {
        Motion(still: 1.0) { t in
            VStack(spacing: 10) {
                lane("Shaky hands in", Theme.warning, noisy: true, t: t)
                Image(systemName: "arrow.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
                lane("Smoothed out", Theme.success, noisy: false, t: t)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
        }
    }

    private func lane(_ label: String, _ color: Color, noisy: Bool, t: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
            Canvas { ctx, size in
                let mid = size.height / 2
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: mid)); $0.addLine(to: CGPoint(x: size.width, y: mid)) },
                           with: .color(.primary.opacity(0.12)), lineWidth: 1)
                var p = Path()
                var x = 0.0
                while x <= size.width {
                    let u = x / 60 + t * 1.2
                    var v = sin(u) * 0.35
                    let flick = exp(-pow((u.truncatingRemainder(dividingBy: 9) - 6.5) * 1.6, 2))
                    v += flick * 0.55
                    if noisy { v += noise(floor(u * 9)) * 0.16 * (1 - flick * 0.5) }
                    let pt = CGPoint(x: x, y: mid - v * (size.height / 2 - 4))
                    x == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    x += 2
                }
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - 5 Equation

private struct EquationDiagram: View {
    var body: some View {
        Motion(still: 7.0) { t in
            let c = t.truncatingRemainder(dividingBy: 9)
            let n = Int((ease((c - 3.2) / 1.2) * 7).rounded())
            VStack(spacing: 22) {
                HStack(spacing: 10) {
                    term("29°/s", "turning speed", Theme.blue, ease(c / 0.5))
                    op("×", ease((c - 0.8) / 0.4))
                    term("10 ms", "time", Theme.indigo, ease((c - 1.0) / 0.5))
                    op("×", ease((c - 1.8) / 0.4))
                    term("24", "dots per degree", Theme.purple, ease((c - 2.0) / 0.5))
                    op("=", ease((c - 2.8) / 0.4))
                    VStack(spacing: 4) {
                        Text("\(n)").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white).contentTransition(.numericText())
                        Text("dots").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(width: 84, height: 84)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.aurora))
                    .opacity(ease((c - 3.0) / 0.4))
                }
                HStack(spacing: 8) {
                    Text("× 100 per second").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text("about 700 dots in one second").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.blue)
                }
                .opacity(ease((c - 5.0) / 0.6))
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill").foregroundStyle(Theme.warning)
                    Text("Flick fast and you get a little extra (acceleration).").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .opacity(ease((c - 6.0) / 0.6))
            }
        }
    }

    private func term(_ value: String, _ caption: String, _ color: Color, _ o: Double) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(caption).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(width: 98, height: 84)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color.opacity(0.13)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(color.opacity(0.4), lineWidth: 1))
        .opacity(o).scaleEffect(0.92 + 0.08 * o)
    }
    private func op(_ s: String, _ o: Double) -> some View {
        Text(s).font(.system(size: 22, weight: .semibold)).foregroundStyle(.secondary).opacity(o)
    }
}

// MARK: - 6 Calibration

private struct CalibDiagram: View {
    var body: some View {
        Motion(still: 1.2) { t in
            let active = Int(t / 1.2) % 5
            Canvas { ctx, size in
                let screen = CGRect(x: size.width / 2 - 200, y: 18, width: 400, height: 130)
                ctx.fill(Path(roundedRect: screen, cornerRadius: 10), with: .color(.primary.opacity(0.06)))
                ctx.stroke(Path(roundedRect: screen, cornerRadius: 10), with: .color(.primary.opacity(0.3)), lineWidth: 1.2)
                let dots = [CGPoint(x: screen.minX + 36, y: screen.minY + 26), CGPoint(x: screen.maxX - 36, y: screen.minY + 26),
                            CGPoint(x: screen.midX, y: screen.midY),
                            CGPoint(x: screen.minX + 36, y: screen.maxY - 26), CGPoint(x: screen.maxX - 36, y: screen.maxY - 26)]
                let phone = CGPoint(x: size.width / 2, y: size.height - 40)
                for (i, d) in dots.enumerated() {
                    var l = Path(); l.move(to: phone); l.addLine(to: d)
                    let on = i == active
                    ctx.stroke(l, with: .color(on ? Theme.blue : .primary.opacity(0.14)), style: StrokeStyle(lineWidth: on ? 2 : 1, dash: [5, 4]))
                }
                for (i, d) in dots.enumerated() {
                    let on = i == active
                    if on { ctx.fill(Path(ellipseIn: CGRect(x: d.x - 15, y: d.y - 15, width: 30, height: 30)), with: .color(Theme.blue.opacity(0.22))) }
                    ctx.fill(Path(ellipseIn: CGRect(x: d.x - 7, y: d.y - 7, width: 14, height: 14)), with: .color(on ? Theme.blue : Theme.indigo.opacity(0.6)))
                }
                let body = CGRect(x: phone.x - 12, y: phone.y - 8, width: 24, height: 44)
                ctx.fill(Path(roundedRect: body, cornerRadius: 5), with: .color(Theme.blue.opacity(0.3)))
                ctx.stroke(Path(roundedRect: body, cornerRadius: 5), with: .color(.primary.opacity(0.6)), lineWidth: 1.5)
                var arc = Path(); arc.addArc(center: phone, radius: 34, startAngle: .degrees(-128), endAngle: .degrees(-52), clockwise: false)
                ctx.stroke(arc, with: .color(Theme.warning), lineWidth: 2)
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 6) {
                    chip("sideways: dots per degree", Theme.blue)
                    chip("up / down: dots per degree", Theme.purple)
                }
                .padding(14)
            }
            .overlay(alignment: .bottomLeading) {
                Text("° of turn").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.warning).padding(.leading, 220).padding(.bottom, 56)
            }
        }
    }
}

// MARK: - 7 Messages

private struct MessagesDiagram: View {
    var body: some View {
        Motion(still: 0.9) { t in
            VStack(spacing: 14) {
                Text("move 7.9 right, 0.4 up")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.blue.opacity(0.16)))
                    .overlay(Capsule().strokeBorder(Theme.blue.opacity(0.5), lineWidth: 1))
                row("Wi-Fi", "about 100 / second", count: 14, speed: 0.55, big: false, t: t, color: Theme.blue)
                row("Bluetooth", "about 11 / second, combined", count: 4, speed: 0.2, big: true, t: t, color: Theme.purple)
                HStack(spacing: 8) { chip("Hold to Point: only while holding the pad", Theme.indigo); chip("Always On", Theme.success) }
            }
            .padding(.horizontal, 22)
        }
    }

    private func row(_ name: String, _ rate: String, count: Int, speed: Double, big: Bool, t: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone").font(.system(size: 26)).foregroundStyle(color)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1)).frame(height: 2).offset(y: g.size.height / 2 - 1)
                    ForEach(0..<count, id: \.self) { i in
                        let f = (Double(i) / Double(count) + t * speed).truncatingRemainder(dividingBy: 1)
                        Group {
                            if big {
                                RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 26, height: 16)
                                    .overlay(Text("+").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white))
                            } else {
                                Capsule().fill(color).frame(width: 12, height: 8)
                            }
                        }
                        .opacity(min(1, f * 8, (1 - f) * 8))
                        .position(x: 14 + f * (g.size.width - 28), y: g.size.height / 2)
                    }
                }
            }
            .frame(height: 24)
            Image(systemName: "laptopcomputer").font(.system(size: 26)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.system(size: 12, weight: .semibold))
                Text(rate).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)
        }
    }
}

// MARK: - 8 Burst -> even

private struct BurstDiagram: View {
    var body: some View {
        Motion(still: 0.8) { t in
            VStack(spacing: 22) {
                HStack(spacing: 12) {
                    VStack(spacing: 6) {
                        Text("Notes arrive in bursts").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.warning)
                        Canvas { ctx, size in
                            let pattern: [Double] = [0, 0.04, 0.08, 0.12, 0.5, 0.54, 0.86]
                            for p in pattern {
                                let f = (p + t * 0.25).truncatingRemainder(dividingBy: 1)
                                let x = f * size.width
                                ctx.fill(Path(ellipseIn: CGRect(x: x - 6, y: size.height / 2 - 6, width: 12, height: 12)), with: .color(Theme.warning))
                            }
                        }
                        .frame(height: 30)
                    }
                    VStack(spacing: 4) {
                        Image(systemName: "laptopcomputer").font(.system(size: 30)).foregroundStyle(Theme.blue)
                        Text("Mac app").font(.system(size: 11, weight: .semibold))
                        Text("every refresh, up to 120×/s").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .frame(width: 130)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.blue.opacity(0.12)))
                    VStack(spacing: 6) {
                        Text("Cursor moves evenly").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.success)
                        Canvas { ctx, size in
                            for i in 0..<10 {
                                let f = (Double(i) / 10 + t * 0.25).truncatingRemainder(dividingBy: 1)
                                ctx.fill(Path(ellipseIn: CGRect(x: f * size.width - 5, y: size.height / 2 - 5, width: 10, height: 10)), with: .color(Theme.success))
                            }
                        }
                        .frame(height: 30)
                    }
                }
                .padding(.horizontal, 18)
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.swap").foregroundStyle(Theme.indigo)
                    Text("A late note? The cursor glides on instead of stopping.").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 9 Chain

private struct ChainDiagram: View {
    private let nodes: [(String, String, Color)] = [
        ("Gyroscope", "iphone.radiowaves.left.and.right", Theme.blue),
        ("Remove drift", "minus.circle", Theme.indigo),
        ("Smooth", "waveform.path", Theme.purple),
        ("× time × calibration", "multiply.circle", Theme.blue),
        ("Message", "paperplane.fill", Theme.indigo),
        ("Mac smooths", "laptopcomputer", Theme.purple),
        ("Cursor", "cursorarrow", Theme.success),
    ]
    var body: some View {
        Motion(still: 6.2) { t in
            let lit = Int(t / 0.9) % (nodes.count + 2)
            HStack(spacing: 0) {
                ForEach(0..<nodes.count, id: \.self) { i in
                    let on = i <= lit
                    VStack(spacing: 8) {
                        Image(systemName: nodes[i].1).font(.system(size: 22, weight: .medium))
                            .foregroundStyle(on ? Color.white : Color.secondary)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(on ? nodes[i].2 : Color.primary.opacity(0.1)))
                            .scaleEffect(i == lit ? 1.1 : 1)
                        Text(nodes[i].0).font(.system(size: 11, weight: .semibold)).multilineTextAlignment(.center)
                            .frame(width: 74, height: 30, alignment: .top)
                            .foregroundStyle(on ? Color.primary : Color.secondary)
                    }
                    if i < nodes.count - 1 {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(i < lit ? Theme.blue : Color.primary.opacity(0.25)).frame(width: 12)
                            .offset(y: -16)
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: lit)
        }
    }
}
