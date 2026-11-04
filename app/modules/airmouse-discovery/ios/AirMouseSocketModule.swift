import ExpoModulesCore
import Foundation
import Network

// WebSocket client on Network.framework with TCP_NODELAY (docs/spec-v3.md 6).
// React Native's WebSocket (SocketRocket, prebuilt) leaves Nagle on, which
// bunches the small 100 Hz `move` frames and makes the cursor stutter.
// Several sockets can be open at once, keyed by a JS-chosen id.
public class AirMouseSocketModule: Module {
  private let queue = DispatchQueue(label: "airmouse.socket", qos: .userInteractive)
  private var connections: [String: NWConnection] = [:] // only touched on `queue`

  public func definition() -> ModuleDefinition {
    Name("AirMouseSocket")
    Events("onSocketOpen", "onSocketMessage", "onSocketClose")

    // Synchronous JSI calls: they only hop to the socket queue.
    Function("open") { (id: String, url: String) in
      self.queue.async { self.start(id: id, url: url) }
    }

    Function("send") { (id: String, text: String) in
      self.queue.async {
        guard let c = self.connections[id] else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "text", metadata: [meta])
        c.send(content: Data(text.utf8), contentContext: ctx, isComplete: true, completion: .idempotent)
      }
    }

    Function("close") { (id: String) in
      self.queue.async {
        guard let c = self.connections.removeValue(forKey: id) else { return }
        c.cancel()
      }
    }

    OnDestroy {
      self.queue.async {
        self.connections.values.forEach { $0.cancel() }
        self.connections.removeAll()
      }
    }
  }

  private func start(id: String, url: String) {
    connections.removeValue(forKey: id)?.cancel()
    guard let u = URL(string: url) else {
      sendEvent("onSocketClose", ["id": id, "error": "bad url"])
      return
    }
    let tcp = NWProtocolTCP.Options()
    tcp.noDelay = true
    tcp.connectionTimeout = 6
    let ws = NWProtocolWebSocket.Options()
    ws.autoReplyPing = true
    let params = NWParameters(tls: nil, tcp: tcp)
    params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
    let c = NWConnection(to: .url(u), using: params)
    connections[id] = c
    c.stateUpdateHandler = { [weak self, weak c] state in
      guard let self, let c else { return }
      switch state {
      case .ready:
        self.sendEvent("onSocketOpen", ["id": id])
        self.receive(id: id, on: c)
      case .waiting(let error), .failed(let error):
        // .waiting = unreachable for now: report and let JS retry.
        self.finish(id: id, connection: c, error: error.localizedDescription)
      case .cancelled:
        self.finish(id: id, connection: c, error: nil)
      default:
        break
      }
    }
    c.start(queue: queue)
  }

  private func receive(id: String, on c: NWConnection) {
    c.receiveMessage { [weak self, weak c] data, context, _, error in
      guard let self, let c else { return }
      if let data, !data.isEmpty,
         let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
         meta.opcode == .text, let text = String(data: data, encoding: .utf8) {
        self.sendEvent("onSocketMessage", ["id": id, "text": text])
      }
      if let error {
        self.finish(id: id, connection: c, error: error.localizedDescription)
        return
      }
      if c.state == .ready { self.receive(id: id, on: c) }
    }
  }

  // Reports once per connection. A connection JS closed itself, or one
  // replaced by a newer open() with the same id, ends silently.
  private func finish(id: String, connection c: NWConnection, error: String?) {
    let current = connections[id] === c
    if current { connections.removeValue(forKey: id) }
    if c.state != .cancelled { c.cancel() }
    guard current else { return }
    var body: [String: Any] = ["id": id]
    if let error { body["error"] = error }
    sendEvent("onSocketClose", body)
  }
}
