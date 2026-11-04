import ExpoModulesCore
import Network
import CoreBluetooth

// Browses Bonjour for `_airmouse._tcp` with NWBrowser and resolves every
// result to an IPv4 host + port by briefly opening a TCP connection to the
// service endpoint (the connection is cancelled as soon as it is ready).
// All state lives on one serial queue.
public class AirMouseDiscoveryModule: Module {
  private let queue = DispatchQueue(label: "airmouse.discovery")
  private var browser: NWBrowser?
  private var services: [String: [String: Any]] = [:]   // keyed by service name
  private var resolving: [String: NWConnection] = [:]
  // Local Network permission has no API: inferred from the browser.
  // "unknown" until the first browse, "granted" once ready or a result
  // arrives, "denied" on kDNSServiceErr_PolicyDenied (-65570).
  private var localNetwork = "unknown"

  public func definition() -> ModuleDefinition {
    Name("AirMouseDiscovery")
    Events("onServicesChanged", "onBrowseError", "onLocalNetworkState")

    Function("localNetworkState") { () -> String in
      self.queue.sync { self.localNetwork }
    }

    // CBManager.authorization is a class property: reading it never prompts.
    Function("bluetoothAuthorization") { () -> String in
      switch CBManager.authorization {
      case .allowedAlways: return "granted"
      case .denied: return "denied"
      case .restricted: return "restricted"
      case .notDetermined: return "unknown"
      @unknown default: return "unknown"
      }
    }

    Function("start") {
      self.queue.async { self.startBrowsing() }
    }

    Function("stop") {
      self.queue.async { self.stopBrowsing() }
    }

    OnDestroy {
      self.queue.sync { self.stopBrowsing() }
    }
  }

  private func startBrowsing() {
    if browser != nil { publish(); return }
    let params = NWParameters()
    params.includePeerToPeer = false
    let b = NWBrowser(for: .bonjour(type: "_airmouse._tcp", domain: nil), using: params)
    b.stateUpdateHandler = { [weak self, weak b] state in
      guard let self, let b else { return }
      switch state {
      case .ready:
        // The browser can report ready before the user answers the prompt or
        // just before a policy denial: confirm after a short grace period.
        self.queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
          guard let self, self.browser === b, self.localNetwork != "denied" else { return }
          if case .ready = b.state { self.setLocalNetwork("granted") }
        }
      case .failed(let error):
        if self.isPolicyDenied(error) { self.setLocalNetwork("denied") }
        self.sendEvent("onBrowseError", ["message": "\(error)"])
        self.stopBrowsing()
      case .waiting(let error):
        // Usually the Local Network permission was denied.
        if self.isPolicyDenied(error) { self.setLocalNetwork("denied") }
        self.sendEvent("onBrowseError", ["message": "\(error)"])
      default:
        break
      }
    }
    b.browseResultsChangedHandler = { [weak self] results, _ in
      self?.update(results)
    }
    browser = b
    b.start(queue: queue)
    publish()
  }

  private func stopBrowsing() {
    browser?.cancel()
    browser = nil
    resolving.values.forEach { $0.cancel() }
    resolving.removeAll()
    services.removeAll()
  }

  private func isPolicyDenied(_ error: NWError) -> Bool {
    if case let .dns(code) = error { return Int(code) == -65570 }
    return false
  }

  private func setLocalNetwork(_ value: String) {
    guard localNetwork != value else { return }
    localNetwork = value
    sendEvent("onLocalNetworkState", ["state": value])
  }

  private func update(_ results: Set<NWBrowser.Result>) {
    if !results.isEmpty { setLocalNetwork("granted") }
    var seen = Set<String>()
    for result in results {
      guard case let .service(name, _, _, _) = result.endpoint else { continue }
      seen.insert(name)
      if services[name] == nil {
        services[name] = ["name": name]
        resolve(name: name, endpoint: result.endpoint)
      }
    }
    for name in services.keys where !seen.contains(name) {
      services.removeValue(forKey: name)
      resolving.removeValue(forKey: name)?.cancel()
    }
    publish()
  }

  private func resolve(name: String, endpoint: NWEndpoint) {
    let params = NWParameters.tcp
    if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
      ip.version = .v4
    }
    let connection = NWConnection(to: endpoint, using: params)
    resolving[name] = connection
    connection.stateUpdateHandler = { [weak self, weak connection] state in
      guard let self, let connection else { return }
      switch state {
      case .ready:
        if case let .hostPort(host, port) = connection.currentPath?.remoteEndpoint {
          var hostText: String
          switch host {
          case .ipv4(let a): hostText = "\(a)"
          case .ipv6(let a): hostText = "\(a)"
          case .name(let n, _): hostText = n
          @unknown default: hostText = "\(host)"
          }
          if let pct = hostText.firstIndex(of: "%") { hostText = String(hostText[..<pct]) }
          if self.services[name] != nil {
            self.services[name] = ["name": name, "host": hostText, "port": Int(port.rawValue)]
            self.publish()
          }
        }
        connection.cancel()
        self.resolving.removeValue(forKey: name)
      case .failed, .cancelled:
        self.resolving.removeValue(forKey: name)
      default:
        break
      }
    }
    connection.start(queue: queue)
  }

  private func publish() {
    let list = services.values.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
    sendEvent("onServicesChanged", ["services": list])
  }
}
