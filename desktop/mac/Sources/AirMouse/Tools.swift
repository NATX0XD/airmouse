import AppKit
import SwiftUI
import AirMouseCore

// MARK: - Headless self test

@MainActor
enum SelfTest {
    static func say(_ s: String) {
        print(s)
        fflush(stdout)
    }

    static func run(port: UInt16, timeout: Double) -> Never {
        let out = LogOutput(sink: { say("out: \($0)") })
        let name = MacInfo.computerName
        let server = AirMouseServer(preferredPort: port, serviceName: nil) {
            let s = ReceiverSession(output: out, screen: { Displays.mainScreenInfo(name: name) })
            s.onCalib = { say("calib: \($0)") }
            s.onHello = { say("hello: \($0.name) \($0.wMm)x\($0.hMm)") }
            return s
        }
        server.log = { say("log: \($0)") }
        server.onState = { st in
            switch st {
            case .listening(let p): say("listening: \(p)")
            case .failed(let e): say("failed: \(e)"); exit(2)
            default: break
            }
        }
        server.onDisconnect = { _ in
            say("selftest: client gone, exiting")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exit(0) }
        }
        server.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { say("selftest: timeout"); exit(3) }
        withExtendedLifetime(server) { dispatchMain() }
    }
}

// MARK: - Offscreen rendering (never ordered front)

@MainActor
enum Previews {
    static func prepareApp() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
    }

    static func write(_ rep: NSBitmapImageRep, _ url: URL) {
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
        print("wrote \(url.path)")
    }

    static func render<V: View>(_ view: V, size: CGSize?, dark: Bool, to url: URL) {
        let host = NSHostingView(rootView: view.environment(\.stillFrameTime, 37.0))
        let s = size ?? host.fittingSize
        host.frame = CGRect(origin: .zero, size: s)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        write(rep, url)
        win.contentView = nil
    }

    static func sampleModel(connected: Bool, accessibility: Bool, banner: Bool = false, bluetooth: Bool = false) -> AppModel {
        let m = AppModel()
        m.macName = "Nattakit’s MacBook Pro"
        m.port = 8765
        m.addresses = [InterfaceAddress(interface: "en0", ip: "192.168.1.42"), InterfaceAddress(interface: "en5", ip: "10.0.0.7")]
        m.accessibilityTrusted = accessibility
        m.firewallDetail = "The firewall is off. Nothing to do."
        m.setup.update(.accessibility, accessibility ? .granted : .notDetermined)
        m.setup.update(.bluetooth, .granted)
        m.setup.update(.localNetwork, accessibility ? .granted : .denied)
        m.setup.update(.firewall, .granted)
        m.bluetooth = .advertising
        if connected {
            let phone = PhoneSummary(id: 1, name: "Ghost", model: "iPhone 15", device: PhoneDevice(name: "Ghost", model: "iPhone 15", wMm: 71.6, hMm: 147.6))
            if bluetooth { m.blePhones = [phone]; m.bluetooth = .connected } else { m.phones = [phone] }
            m.rate = 118
        }
        if banner { m.banner = "Connect your iPhone first, then press Calibrate again." }
        return m
    }

    static func renderAll(to dir: URL) -> Never {
        prepareApp()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func window(_ name: String, _ m: AppModel, _ section: AppSection, dark: Bool) {
            m.section = section
            render(RootView(model: m).background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 900, height: 640), dark: dark,
                   to: dir.appendingPathComponent("window-\(name)-\(dark ? "dark" : "light").png"))
        }
        for dark in [false, true] {
            let ok = sampleModel(connected: true, accessibility: true)
            ok.lastCalibration = CalibrationRecord(sensitivity: 1480, biasOK: true, date: Date(timeIntervalSince1970: 1_793_700_000))
            for s in AppSection.allCases { window(s.rawValue, ok, s, dark: dark) }
            window("home-waiting-missing", sampleModel(connected: false, accessibility: false), .home, dark: dark)
            let missing = sampleModel(connected: false, accessibility: false)
            missing.setup.update(.bluetooth, .notDetermined)
            missing.setup.open(.accessibility)
            window("permissions-missing", missing, .permissions, dark: dark)
        }
        // Onboarding pages + tour steps
        for dark in [false, true] {
            for (i, page) in OnboardingPage.allCases.enumerated() {
                let m = sampleModel(connected: false, accessibility: page != .permissions)
                var f = OnboardingFlow(); for _ in 0..<i { f.next() }
                m.onboarding = f
                if page == .permissions { m.setup.open(.accessibility) }
                window("onboarding-\(i + 1)-\(page.rawValue)", m, .home, dark: dark)
            }
            for (i, step) in TourTarget.allCases.enumerated() {
                let m = sampleModel(connected: true, accessibility: true)
                m.lastCalibration = CalibrationRecord(sensitivity: 1480, biasOK: true, date: Date(timeIntervalSince1970: 1_793_700_000))
                var t = TourFlow(); for _ in 0..<i { t.next() }
                m.tour = t
                window("tour-\(i + 1)-\(step.rawValue)", m, .home, dark: dark)
            }
        }
        // About > From Sensor to Cursor
        SensorPreview.frozen = true
        for dark in [false, true] {
            for i in [0, 2, 4, 6, 8] {
                render(SensorToCursorView(initialPage: i, onClose: {}), size: CGSize(width: 720, height: 620), dark: dark,
                       to: dir.appendingPathComponent("sensor-to-cursor-\(i + 1)-\(dark ? "dark" : "light").png"))
            }
        }
        SensorPreview.frozen = false
        // About > Diagnostics (taller window so the section is in view)
        for dark in [false, true] {
            let m = sampleModel(connected: true, accessibility: true)
            m.calibration.apply(.start)
            m.calibration.apply(.place(progress: 0.65, still: true, near: true, upright: true))
            var wifi = MessageStats(), ble = MessageStats()
            let now = 1000.0
            for i in 0..<240 { wifi.record("move", at: now - 2.4 + Double(i) * 0.01) }
            for (k, n) in [("hello", 1), ("button", 14), ("scroll", 37), ("key", 6), ("center", 2), ("calib", 58), ("other", 1)] {
                for _ in 0..<n { wifi.record(k, at: now - 1.5) }
            }
            for i in 0..<130 { wifi.record("move", at: now - 1.4 + Double(i) * 0.01) }
            ble.record("hello", at: now - 40); for _ in 0..<9 { ble.record("move", at: now - 14) }
            m.previewDiagnostics = (now, [
                PeerDiagnostics(id: "wifi-3", transport: .wifi, name: "Ghost", stats: wifi, dragging: .left),
                PeerDiagnostics(id: "ble-6F1A2C9E-0000-0000-0000-000000000000", transport: .bluetooth, name: "Nattakit’s iPhone", stats: ble, dragging: nil, writeHz: 24),
            ])
            m.section = .about
            m.previewPacerFPS = 120
            render(RootView(model: m).background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 760, height: 1180), dark: dark,
                   to: dir.appendingPathComponent("window-about-diagnostics-\(dark ? "dark" : "light").png"))
            let empty = sampleModel(connected: false, accessibility: true)
            empty.previewDiagnostics = (now, [])
            empty.section = .about
            render(RootView(model: empty).background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 760, height: 860), dark: dark,
                   to: dir.appendingPathComponent("window-about-diagnostics-empty-\(dark ? "dark" : "light").png"))
        }

        let fw = sampleModel(connected: false, accessibility: true)
        fw.setup.update(.firewall, .attention("The firewall blocks AirMouse")); fw.firewallDetail = "AirMouse is blocked."
        fw.setup.open(.firewall)
        window("permissions-firewall", fw, .permissions, dark: false)
        let none = sampleModel(connected: false, accessibility: true)
        none.lastCalibration = nil
        none.banner = "Connect your iPhone first, then press Calibrate again."
        window("calibration-none", none, .calibration, dark: true)

        let screen = ScreenInfo(w: 1512, h: 982, scale: 2, wMm: 302.4, hMm: 196.4, name: "Mac")
        let phone = PhoneDevice(name: "Ghost", model: "iPhone 15", wMm: 71.6, hMm: 147.6)
        func overlay(_ name: String, _ events: [CalibEvent]) {
            var st = CalibrationState()
            events.forEach { st.apply($0) }
            render(OverlayView(state: st, phone: phone, screen: screen, onCancel: {}),
                   size: CGSize(width: 1512, height: 982), dark: true, to: dir.appendingPathComponent("overlay-\(name).png"))
        }
        overlay("1-place", [.start])
        overlay("1-progress", [.start, .place(progress: 0.6, still: true)])
        // Calibration v2 live hints (spec 4a)
        overlay("1-hint-1-bring-closer", [.start, .place(progress: 0, still: true, near: false, upright: false)])
        overlay("1-hint-2-upright", [.start, .place(progress: 0, still: true, near: true, upright: false)])
        overlay("1-hint-3-hold-still", [.start, .place(progress: 0.4, still: false, near: true, upright: true)])
        overlay("1-hint-4-filling", [.start, .place(progress: 0.65, still: true, near: true, upright: true)])
        overlay("1-placed", [.start, .placed])
        overlay("2-left-legacy", [.start, .placed, .point(.left)])
        overlay("3-right-legacy", [.start, .placed, .point(.left), .pointed(.left), .point(.right)])
        overlay("4-done-legacy", [.start, .placed, .point(.left), .pointed(.left), .point(.right), .pointed(.right), .done(sensitivity: 1480)])
        // Calibration v3: five targets, then verify
        var v3: [CalibEvent] = [.start, .placed]
        for (i, t) in Side.fourCorners.enumerated() {
            v3.append(.point(t))
            overlay("v3-2-point-\(i + 1)-\(t.rawValue)", v3)
            v3.append(.pointed(t))
        }
        overlay("v3-2-pointed-bl", v3)
        func verify(_ name: String, _ cursors: [CGPoint], done: Bool) {
            var st = CalibrationState()
            (v3 + [.verify]).forEach { st.apply($0) }
            for c in cursors { _ = st.cursor(at: c, screen: screen) }
            if done { st.apply(.done(sensitivity: 1480)) }
            render(OverlayView(state: st, phone: phone, screen: screen, onCancel: {}),
                   size: CGSize(width: 1512, height: 982), dark: true, to: dir.appendingPathComponent("overlay-\(name).png"))
        }
        let tr = CalibrationGeometry.target(.tr, screen: screen)
        verify("v3-3-verify", [CalibrationGeometry.target(.center, screen: screen), CGPoint(x: tr.x - 12, y: tr.y + 10)], done: false)
        verify("v3-4-done", Side.fourCorners.map { CalibrationGeometry.target($0, screen: screen) }, done: true)

        let wide = ScreenInfo(w: 2560, h: 1080, scale: 1, wMm: 691.7, hMm: 288.8, name: "Mac")
        var st = CalibrationState(); st.apply(.start); st.apply(.place(progress: 0.35, still: true))
        render(OverlayView(state: st, phone: phone, screen: wide, onCancel: {}),
               size: CGSize(width: 2560, height: 1080), dark: true, to: dir.appendingPathComponent("overlay-1-progress-ultrawide.png"))

        // Click Practice (fixed seed so the layout is stable)
        func practice(_ name: String, hits: Int, misses: Int, effects: (PracticeGame, CGSize) -> [PracticeEffect] = { _, _ in [] }) {
            let size = CGSize(width: 1512, height: 982)
            var g = PracticeGame(now: 0, seed: 2026)
            var t = 0.0
            for _ in 0..<misses { g.click(at: CGPoint(x: 1, y: 1), in: size, now: t) }
            for _ in 0..<hits {
                t += 0.84
                if let c = g.currentCenter(in: size) { g.click(at: c, in: size, now: t) }
            }
            render(PracticeView(game: g, onClick: { _, _ in .ignored }, onCancel: {}, onRetry: {}, onDone: {},
                                previewEffects: effects(g, size)),
                   size: size, dark: true, to: dir.appendingPathComponent("practice-\(name).png"))
        }
        practice("1-start", hits: 0, misses: 0)
        practice("2-running", hits: 4, misses: 1) { g, size in
            let prev = PracticeGame.point(g.targets[g.index - 1], in: size)
            let cur = g.currentCenter(in: size) ?? .zero
            return [PracticeEffect(kind: .pop, point: prev, diameter: PracticeGame.diameter(for: g.index - 1)),
                    PracticeEffect(kind: .miss, point: CGPoint(x: cur.x + 90, y: cur.y + 50), diameter: 34)]
        }
        practice("3-result", hits: 10, misses: 2)

        render(AppIconArt(size: 512), size: CGSize(width: 512, height: 512), dark: false, to: dir.appendingPathComponent("icon.png"))
        exit(0)
    }

    static func renderIconset(to dir: URL) -> Never {
        prepareApp()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for mult in [1, 2] {
                let px = base * mult
                let r = ImageRenderer(content: AppIconArt(size: CGFloat(px)))
                r.scale = 1
                guard let cg = r.cgImage else { print("icon render failed \(px)"); exit(1) }
                let name = mult == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                write(NSBitmapImageRep(cgImage: cg), dir.appendingPathComponent(name))
            }
        }
        exit(0)
    }
}
