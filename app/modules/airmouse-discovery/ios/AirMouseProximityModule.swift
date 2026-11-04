import ExpoModulesCore
import UIKit

// Proximity sensor for calibration step 1 (docs/spec-v3.md 4a): the phone is
// held with its screen against the display, which covers the sensor. iOS
// turns the screen off while near; that is expected.
//
// Monitoring is only on while JS asks for it (step 1) and is always switched
// off again by `setEnabled(false)` or when the module is destroyed.
public class AirMouseProximityModule: Module {
  private var observer: NSObjectProtocol?

  public func definition() -> ModuleDefinition {
    Name("AirMouseProximity")
    Events("onProximityChange")

    // Returns true when monitoring is on (false = this device has no sensor).
    AsyncFunction("setEnabled") { (enabled: Bool) -> Bool in
      MainActor.assumeIsolated {
        let device = UIDevice.current
        guard enabled else {
          self.stopMonitoring()
          return false
        }
        device.isProximityMonitoringEnabled = true
        let supported = device.isProximityMonitoringEnabled
        if supported && self.observer == nil {
          self.observer = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification, object: device, queue: .main
          ) { [weak self] _ in
            let near = MainActor.assumeIsolated { UIDevice.current.proximityState }
            self?.sendEvent("onProximityChange", ["near": near])
          }
        }
        return supported
      }
    }.runOnQueue(.main)

    AsyncFunction("isNear") { () -> Bool in
      MainActor.assumeIsolated { UIDevice.current.proximityState }
    }.runOnQueue(.main)

    OnDestroy {
      let o = self.observer
      self.observer = nil
      DispatchQueue.main.async {
        if let o { NotificationCenter.default.removeObserver(o) }
        MainActor.assumeIsolated { UIDevice.current.isProximityMonitoringEnabled = false }
      }
    }
  }

  private func stopMonitoring() {
    if let o = observer {
      NotificationCenter.default.removeObserver(o)
      observer = nil
    }
    MainActor.assumeIsolated { UIDevice.current.isProximityMonitoringEnabled = false }
  }
}
