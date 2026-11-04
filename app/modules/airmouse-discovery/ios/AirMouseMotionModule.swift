import ExpoModulesCore
import SceneKit
import UIKit

// A real 3D phone for the "From Sensor to Cursor" explainer. The phone is held like a remote:
// long axis points at the Mac, screen up. Axes match motion/engine.ts:
//   yaw   = turn about the vertical axis (cursor sideways)
//   pitch = nose up/down about the short axis (cursor up/down)
//   roll  = twist about the long axis (ignored)
// Angles arrive in radians, positive = turn right / nose up / clockwise seen from behind.
public class AirMouseMotionModule: Module {
  public func definition() -> ModuleDefinition {
    Name("AirMouseMotion")
    View(AirMouseMotionView.self) {
      Prop("yaw") { (view: AirMouseMotionView, v: Double) in view.yaw = v }
      Prop("pitch") { (view: AirMouseMotionView, v: Double) in view.pitch = v }
      Prop("roll") { (view: AirMouseMotionView, v: Double) in view.roll = v }
      Prop("highlight") { (view: AirMouseMotionView, v: String?) in view.highlight = v }
      Prop("dark") { (view: AirMouseMotionView, v: Bool) in view.isDark = v }
    }
  }
}

public class AirMouseMotionView: ExpoView {
  private let scnView = SCNView()
  private let scene = SCNScene()
  private let yawNode = SCNNode()
  private let pitchNode = SCNNode()
  private let rollNode = SCNNode()
  private let floorNode = SCNNode()
  private var rings: [String: SCNNode] = [:]
  private var ringColors: [String: UIColor] = [:]

  var yaw = 0.0 { didSet { applyPose() } }
  var pitch = 0.0 { didSet { applyPose() } }
  var roll = 0.0 { didSet { applyPose() } }
  var highlight: String? { didSet { applyHighlight() } }
  var isDark = false { didSet { applyTheme() } }

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    clipsToBounds = true
    backgroundColor = .clear
    buildScene()
    scnView.scene = scene
    scnView.backgroundColor = .clear
    scnView.antialiasingMode = .multisampling4X
    scnView.allowsCameraControl = true
    scnView.defaultCameraController.interactionMode = .orbitTurntable
    scnView.defaultCameraController.inertiaEnabled = true
    addSubview(scnView)
    applyTheme()
    applyHighlight()
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    scnView.frame = bounds
  }

  // MARK: scene

  private func buildScene() {
    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera?.fieldOfView = 36
    camera.position = SCNVector3(2.2, 1.9, 4.4)
    camera.look(at: SCNVector3(0, -0.1, 0))
    scene.rootNode.addChildNode(camera)
    scnView.pointOfView = camera

    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 650
    scene.rootNode.addChildNode(ambient)

    let key = SCNNode()
    key.light = SCNLight()
    key.light?.type = .directional
    key.light?.intensity = 900
    key.light?.castsShadow = true
    key.light?.shadowRadius = 10
    key.light?.shadowSampleCount = 8
    key.light?.shadowColor = UIColor.black.withAlphaComponent(0.4)
    key.eulerAngles = SCNVector3(-Float.pi / 2.6, Float.pi / 6, 0)
    scene.rootNode.addChildNode(key)

    let fill = SCNNode()
    fill.light = SCNLight()
    fill.light?.type = .omni
    fill.light?.intensity = 350
    fill.position = SCNVector3(-3, 1, 3)
    scene.rootNode.addChildNode(fill)

    // Floor disc that catches the phone's shadow.
    let disc = SCNCylinder(radius: 1.7, height: 0.01)
    disc.firstMaterial?.lightingModel = .lambert
    floorNode.geometry = disc
    floorNode.position = SCNVector3(0, -0.95, 0)
    scene.rootNode.addChildNode(floorNode)

    scene.rootNode.addChildNode(yawNode)
    yawNode.addChildNode(pitchNode)
    pitchNode.addChildNode(rollNode)
    rollNode.addChildNode(makePhone())

    // Rings are fixed in the world so they show the axes the phone turns about.
    addRing("yaw", radius: 1.3, color: UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1), tilt: SCNVector3(0, 0, 0))
    addRing("pitch", radius: 1.05, color: UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1), tilt: SCNVector3(0, 0, Float.pi / 2))
    addRing("roll", radius: 0.6, color: UIColor(white: 0.62, alpha: 1), tilt: SCNVector3(Float.pi / 2, 0, 0))
  }

  private func makePhone() -> SCNNode {
    let holder = SCNNode()
    holder.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0) // local +y (long axis) -> forward, local +z -> up

    let box = SCNBox(width: 0.7, height: 1.4, length: 0.09, chamferRadius: 0.07)
    let frame = SCNMaterial()
    frame.lightingModel = .physicallyBased
    frame.diffuse.contents = UIColor(white: 0.62, alpha: 1)
    frame.metalness.contents = 0.9
    frame.roughness.contents = 0.3
    let back = SCNMaterial()
    back.lightingModel = .physicallyBased
    back.diffuse.contents = UIColor(white: 0.2, alpha: 1)
    back.metalness.contents = 0.3
    back.roughness.contents = 0.25
    let front = SCNMaterial()
    front.lightingModel = .physicallyBased
    front.diffuse.contents = UIColor(white: 0.04, alpha: 1)
    front.roughness.contents = 0.1
    box.materials = [front, frame, back, frame, frame, frame]
    let body = SCNNode(geometry: box)
    holder.addChildNode(body)

    // Lit screen, notch (top = nose) and camera bump on the back.
    let screen = SCNPlane(width: 0.6, height: 1.28)
    screen.cornerRadius = 0.06
    let sm = SCNMaterial()
    sm.lightingModel = .constant
    sm.diffuse.contents = UIColor(red: 0.05, green: 0.2, blue: 0.5, alpha: 1)
    screen.materials = [sm]
    let screenNode = SCNNode(geometry: screen)
    screenNode.position = SCNVector3(0, 0, 0.0455)
    holder.addChildNode(screenNode)

    let notch = SCNPlane(width: 0.2, height: 0.05)
    notch.cornerRadius = 0.025
    let nm = SCNMaterial()
    nm.lightingModel = .constant
    nm.diffuse.contents = UIColor.black
    notch.materials = [nm]
    let notchNode = SCNNode(geometry: notch)
    notchNode.position = SCNVector3(0, 0.56, 0.047)
    holder.addChildNode(notchNode)

    let bump = SCNCylinder(radius: 0.13, height: 0.02)
    bump.firstMaterial?.diffuse.contents = UIColor(white: 0.1, alpha: 1)
    let bumpNode = SCNNode(geometry: bump)
    bumpNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
    bumpNode.position = SCNVector3(-0.15, 0.5, -0.055)
    holder.addChildNode(bumpNode)

    // Top-edge marker so "which way is forward" is obvious.
    let tip = SCNCone(topRadius: 0, bottomRadius: 0.1, height: 0.16)
    tip.firstMaterial?.lightingModel = .constant
    tip.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.85)
    let tipNode = SCNNode(geometry: tip)
    tipNode.position = SCNVector3(0, 0.1, 0.047)
    tipNode.scale = SCNVector3(1, 1, 0.05)
    holder.addChildNode(tipNode)
    return holder
  }

  private func addRing(_ name: String, radius: CGFloat, color: UIColor, tilt: SCNVector3) {
    let container = SCNNode()
    container.eulerAngles = tilt
    let torus = SCNTorus(ringRadius: radius, pipeRadius: 0.022)
    let tm = SCNMaterial()
    tm.lightingModel = .constant
    tm.diffuse.contents = color
    torus.materials = [tm]
    container.addChildNode(SCNNode(geometry: torus))
    // Two arrowheads on opposite sides show the turning direction.
    for a in [Float.pi / 2, Float.pi * 3 / 2] {
      let cone = SCNCone(topRadius: 0, bottomRadius: 0.075, height: 0.2)
      let cm = SCNMaterial()
      cm.lightingModel = .constant
      cm.diffuse.contents = color
      cone.materials = [cm]
      let n = SCNNode(geometry: cone)
      let r = Float(radius)
      n.position = SCNVector3(r * cos(a), 0, r * sin(a))
      let tx = -sin(a), tz = cos(a)
      let axis = simd_normalize(simd_float3(tz, 0, -tx))
      n.simdOrientation = simd_quatf(angle: .pi / 2, axis: axis)
      container.addChildNode(n)
    }
    scene.rootNode.addChildNode(container)
    rings[name] = container
    ringColors[name] = color
  }

  // MARK: updates

  private func applyPose() {
    SCNTransaction.begin()
    SCNTransaction.animationDuration = 0.05
    yawNode.eulerAngles.y = Float(-yaw)
    pitchNode.eulerAngles.x = Float(pitch)
    rollNode.eulerAngles.z = Float(-roll)
    SCNTransaction.commit()
  }

  private func applyHighlight() {
    SCNTransaction.begin()
    SCNTransaction.animationDuration = 0.2
    for (name, node) in rings {
      let on = highlight == nil || highlight == name
      let glow = highlight == name
      node.opacity = on ? (name == "roll" ? 0.7 : 1) : 0.25
      let color = ringColors[name] ?? .white
      node.enumerateHierarchy { n, _ in
        n.geometry?.firstMaterial?.emission.contents = glow ? color : UIColor.black
      }
      node.scale = glow ? SCNVector3(1.04, 1.04, 1.04) : SCNVector3(1, 1, 1)
    }
    SCNTransaction.commit()
  }

  private func applyTheme() {
    floorNode.geometry?.firstMaterial?.diffuse.contents = isDark ? UIColor(white: 0.2, alpha: 1) : UIColor(white: 0.9, alpha: 1)
  }
}
