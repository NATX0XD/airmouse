import SwiftUI
import SceneKit

/// Shared animation timeline: yaw, then pitch, then roll, 4 s each.
enum AxesPose {
    static let seg = 4.0
    struct P { var yaw = 0.0, pitch = 0.0, roll = 0.0; var active = -1; var speed = 0.0 }
    static let rest = P()
    static func at(_ t: Double) -> P {
        let c = t.truncatingRemainder(dividingBy: seg * 3)
        let i = Int(c / seg), u = (c - Double(i) * seg) / seg
        let a = sin(u * 2 * .pi) * 0.55
        var p = P(active: i, speed: abs(cos(u * 2 * .pi)) * 2 * .pi / seg * 0.55 * 180 / .pi)
        switch i { case 0: p.yaw = a; case 1: p.pitch = a; default: p.roll = a }
        return p
    }
}

/// SceneKit iPhone with yaw / pitch / roll rings.
final class PhoneModel {
    let scene = SCNScene()
    let camera = SCNNode()
    private let phone = SCNNode()
    private var rings: [SCNNode] = []
    private static let colors: [NSColor] = [NSColor(Theme.blue), NSColor(Theme.purple), NSColor(white: 0.58, alpha: 1)]

    init() {
        scene.background.contents = NSColor.clear
        // Phone
        let box = SCNBox(width: 0.8, height: 1.65, length: 0.1, chamferRadius: 0.11)
        let metal = SCNMaterial(); metal.diffuse.contents = NSColor(white: 0.72, alpha: 1); metal.lightingModel = .blinn
        metal.specular.contents = NSColor.white
        box.materials = [metal]
        phone.geometry = box
        let screen = SCNPlane(width: 0.73, height: 1.58); screen.cornerRadius = 0.09
        let sm = SCNMaterial(); sm.diffuse.contents = NSColor(white: 0.04, alpha: 1); sm.lightingModel = .constant
        sm.emission.contents = NSColor(red: 0.05, green: 0.1, blue: 0.2, alpha: 1)
        screen.materials = [sm]
        let screenNode = SCNNode(geometry: screen); screenNode.position = SCNVector3(0, 0, 0.0505)
        phone.addChildNode(screenNode)
        let notch = SCNPlane(width: 0.22, height: 0.055); notch.cornerRadius = 0.027
        let nm = SCNMaterial(); nm.diffuse.contents = NSColor(white: 0.17, alpha: 1); nm.lightingModel = .constant
        notch.materials = [nm]
        let notchNode = SCNNode(geometry: notch); notchNode.position = SCNVector3(0, 0.72, 0.052)
        phone.addChildNode(notchNode)
        // Back lens
        let lens = SCNCylinder(radius: 0.09, height: 0.02); lens.materials = [nm]
        let lensNode = SCNNode(geometry: lens); lensNode.eulerAngles.x = .pi / 2; lensNode.position = SCNVector3(-0.2, 0.62, -0.055)
        phone.addChildNode(lensNode)
        scene.rootNode.addChildNode(phone)

        // Rings: axis, basis (u x v = axis), radius
        let defs: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, CGFloat)] = [
            ([0, 1, 0], [0, 0, 1], [1, 0, 0], 0.85),   // yaw
            ([1, 0, 0], [0, 1, 0], [0, 0, 1], 1.0),    // pitch
            ([0, 0, 1], [1, 0, 0], [0, 1, 0], 1.15),   // roll
        ]
        for (i, d) in defs.enumerated() {
            let (axis, u, v, r) = d
            let group = SCNNode()
            let torus = SCNTorus(ringRadius: r, pipeRadius: 0.024)
            let tn = SCNNode(geometry: torus); tn.simdOrientation = simd_quatf(from: [0, 1, 0], to: axis)
            group.addChildNode(tn)
            for a in [Float.pi * 0.25, Float.pi * 1.25] {
                let cone = SCNCone(topRadius: 0, bottomRadius: 0.075, height: 0.22)
                let cn = SCNNode(geometry: cone)
                let rr = Float(r)
                cn.simdPosition = rr * (cos(a) * u + sin(a) * v)
                let tangent = -sin(a) * u + cos(a) * v
                cn.simdOrientation = simd_quatf(from: [0, 1, 0], to: tangent)
                cone.materials = torus.materials
                group.addChildNode(cn)
            }
            let m = SCNMaterial(); m.diffuse.contents = Self.colors[i]; m.lightingModel = .constant
            torus.materials = [m]
            group.childNodes.forEach { $0.geometry?.materials = [m] }
            scene.rootNode.addChildNode(group)
            rings.append(group)
        }
        // Soft floor shadow
        let img = NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            NSGradient(colors: [NSColor(white: 0, alpha: 0.38), NSColor(white: 0, alpha: 0)])?
                .draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
        let plane = SCNPlane(width: 2.4, height: 2.4)
        let shm = SCNMaterial(); shm.diffuse.contents = img; shm.lightingModel = .constant; shm.writesToDepthBuffer = false
        plane.materials = [shm]
        let shadow = SCNNode(geometry: plane); shadow.eulerAngles.x = -.pi / 2; shadow.position = SCNVector3(0, -1.3, 0)
        scene.rootNode.addChildNode(shadow)

        // Lights
        let amb = SCNNode(); amb.light = SCNLight(); amb.light?.type = .ambient; amb.light?.intensity = 450
        scene.rootNode.addChildNode(amb)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 650
        key.eulerAngles = SCNVector3(-0.7, -0.6, 0)
        scene.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .omni; fill.light?.intensity = 350
        fill.position = SCNVector3(2, 1, 4)
        scene.rootNode.addChildNode(fill)

        let cam = SCNCamera(); cam.fieldOfView = 34; cam.zNear = 0.1; cam.zFar = 50
        camera.camera = cam
        camera.position = SCNVector3(2.5, 1.3, 4.7)
        camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera)
        apply(AxesPose.rest)
    }

    func apply(_ p: AxesPose.P) {
        phone.eulerAngles = SCNVector3(p.pitch, p.yaw, p.roll)
        for (i, ring) in rings.enumerated() {
            let on = p.active == i
            let idle = p.active < 0
            ring.opacity = on ? 1 : (idle ? 0.9 : 0.4)
            ring.scale = on ? SCNVector3(1.04, 1.04, 1.04) : SCNVector3(1, 1, 1)
        }
    }

    func snapshot(_ p: AxesPose.P, size: CGSize) -> NSImage? {
        apply(p)
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let r = SCNRenderer(device: device, options: nil)
        r.scene = scene; r.pointOfView = camera
        return r.snapshot(atTime: 0, with: CGSize(width: size.width * 2, height: size.height * 2), antialiasingMode: .multisampling4X)
    }
}

private struct PhoneSceneRep: NSViewRepresentable {
    var animated: Bool
    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        let model = PhoneModel()
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            model.apply(AxesPose.at(Date().timeIntervalSinceReferenceDate))
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SCNView {
        let v = SCNView()
        let model = context.coordinator.model
        v.scene = model.scene
        v.pointOfView = model.camera
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.target = SCNVector3Zero
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        if animated {
            v.delegate = context.coordinator
            v.isPlaying = true
            v.rendersContinuously = true
        }
        return v
    }
    func updateNSView(_ v: SCNView, context: Context) {}
}

/// 3D phone + rings beside a small cursor screen / legend.
struct PhoneAxesView: View {
    enum Mode { case axes, cursor }
    var mode: Mode
    var still: Double = 0.8
    @Environment(\.accessibilityReduceMotion) private var reduce

    private let names: [(String, String, String, Color)] = [
        ("Yaw", "Turn left/right", "cursor moves sideways", Theme.blue),
        ("Pitch", "Tilt up/down", "cursor moves up/down", Theme.purple),
        ("Roll", "Twist", "ignored", Color(white: 0.55)),
    ]

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottom) {
                if SensorPreview.frozen {
                    if let img = PhoneModel().snapshot(AxesPose.at(still), size: CGSize(width: 340, height: 270)) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    }
                } else {
                    PhoneSceneRep(animated: !reduce)
                }
                Text(reduce ? "Drag to rotate" : "Drag to look around").font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity)
            Motion(still: still) { t in
                let p = (reduce && !SensorPreview.frozen) ? AxesPose.rest : AxesPose.at(t)
                panel(p)
            }
            .frame(width: 220)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    @ViewBuilder private func panel(_ p: AxesPose.P) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if mode == .cursor {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                    GeometryReader { g in
                        Image(systemName: "cursorarrow").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(p.active == 2 ? Color.secondary : Theme.blue)
                            .position(x: g.size.width * (0.5 + p.yaw / 0.55 * 0.36), y: g.size.height * (0.5 + p.pitch / 0.55 * 0.34))
                    }
                    Text("Mac screen").font(.system(size: 10)).foregroundStyle(.secondary).frame(maxHeight: .infinity, alignment: .bottom).padding(4)
                }
                .frame(height: 96)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%02d", Int(p.speed.rounded()))).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("°/s turning speed").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                let tick = Int(Date().timeIntervalSinceReferenceDate * 20) % 20
                HStack(spacing: 2) {
                    ForEach(0..<20, id: \.self) { i in
                        Capsule().fill(i == tick && !SensorPreview.frozen ? Theme.blue : Color.primary.opacity(i == 7 ? 0.5 : 0.15)).frame(width: 6, height: 12)
                    }
                }
                Text("100 readings a second, every 10 ms").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(0..<3, id: \.self) { i in
                let on = p.active == i
                HStack(spacing: 8) {
                    Circle().fill(names[i].3).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(mode == .axes ? names[i].0 + ": " + names[i].1.lowercased() : names[i].1)
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(i == 2 ? Color.secondary : Color.primary)
                        if mode == .cursor { Text(names[i].2).font(.system(size: 11)).foregroundStyle(i == 2 ? Color.secondary : names[i].3) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(names[i].3.opacity(on ? 0.18 : 0.04)))
            }
        }
    }
}
