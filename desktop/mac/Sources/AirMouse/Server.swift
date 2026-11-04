import Foundation
import Network
import AirMouseCore

/// WebSocket server (Network.framework) + Bonjour `_airmouse._tcp`. Everything runs on the main queue.
@MainActor
final class AirMouseServer {
    enum State: Equatable {
        case idle
        case starting
        case listening(port: UInt16)
        case failed(String)
    }

    @MainActor final class Client {
        let id: Int
        let connection: NWConnection
        let session: ReceiverSession
        let peer: String
        var closed = false
        init(id: Int, connection: NWConnection, session: ReceiverSession, peer: String) {
            self.id = id; self.connection = connection; self.session = session; self.peer = peer
        }
    }

    static let serviceType = "_airmouse._tcp"

    var onState: ((State) -> Void)?
    var onConnect: ((Client) -> Void)?
    var onDisconnect: ((Client) -> Void)?
    var onMessage: ((Client) -> Void)?
    var log: ((String) -> Void)?

    private(set) var state: State = .idle { didSet { if state != oldValue { onState?(state) } } }
    private(set) var clients: [Int: Client] = [:]

    private let preferredPort: UInt16
    private let serviceName: String?
    private let makeSession: () -> ReceiverSession
    private var listener: NWListener?
    private var candidates: [UInt16] = []
    private var nextID = 1

    init(preferredPort: UInt16, serviceName: String?, makeSession: @escaping () -> ReceiverSession) {
        self.preferredPort = preferredPort
        self.serviceName = serviceName
        self.makeSession = makeSession
    }

    func start() {
        state = .starting
        // Pre-check with bind() so a running receiver (e.g. the Python one on 8765) is skipped;
        // listener failures with EADDRINUSE also fall through to the next candidate.
        candidates = PortPicker.candidates(from: preferredPort, count: 20).filter(PortPicker.isTCPPortFree)
        tryNextPort()
    }

    func stop() {
        listener?.cancel(); listener = nil
        for c in clients.values { close(c) }
        state = .idle
    }

    private func tryNextPort() {
        guard !candidates.isEmpty else {
            state = .failed("No free port near \(preferredPort)")
            return
        }
        let port = candidates.removeFirst()
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true // no Nagle batching: every move frame leaves at once
        let params = NWParameters(tls: nil, tcp: tcp)
        params.allowLocalEndpointReuse = false
        params.includePeerToPeer = false
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.maximumMessageSize = 64 * 1024
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)

        let l: NWListener
        do {
            l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        } catch {
            log?("listener on \(port) failed: \(error)")
            tryNextPort(); return
        }
        if let serviceName {
            l.service = NWListener.Service(name: serviceName, type: Self.serviceType, domain: nil,
                                           txtRecord: NWTXTRecord(["v": "3", "app": "airmouse"]))
        }
        l.stateUpdateHandler = { [weak self] st in
            MainActor.assumeIsolated { self?.listenerState(st, listener: l, port: port) }
        }
        l.newConnectionHandler = { [weak self] conn in
            MainActor.assumeIsolated { self?.accept(conn) }
        }
        listener = l
        l.start(queue: .main)
    }

    private func listenerState(_ st: NWListener.State, listener l: NWListener, port: UInt16) {
        guard l === listener else { return }
        switch st {
        case .ready:
            state = .listening(port: l.port?.rawValue ?? port)
        case .failed(let error):
            log?("listener on \(port) failed: \(error)")
            l.cancel(); listener = nil
            if case .posix(let code) = error, code == .EADDRINUSE {
                tryNextPort()
            } else {
                state = .failed(error.localizedDescription)
            }
        case .waiting(let error):
            log?("listener waiting: \(error)")
        default:
            break
        }
    }

    private func accept(_ conn: NWConnection) {
        let session = makeSession()
        let peer: String
        if case .hostPort(let host, _) = conn.endpoint { peer = "\(host)" } else { peer = "\(conn.endpoint)" }
        let client = Client(id: nextID, connection: conn, session: session, peer: peer)
        nextID += 1
        clients[client.id] = client
        conn.stateUpdateHandler = { [weak self] st in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch st {
                case .ready:
                    self.log?("phone connected: \(peer)")
                    self.onConnect?(client)
                case .failed, .cancelled:
                    self.close(client)
                default: break
                }
            }
        }
        conn.start(queue: .main)
        receive(client)
    }

    private func receive(_ client: Client) {
        client.connection.receiveMessage { [weak self] data, context, _, error in
            MainActor.assumeIsolated {
                guard let self, !client.closed else { return }
                if let error {
                    self.log?("receive error: \(error)")
                    self.close(client); return
                }
                let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                switch meta?.opcode {
                case .text?:
                    if let data, let text = String(data: data, encoding: .utf8) {
                        let replies = client.session.handle(text: text)
                        self.onMessage?(client)
                        for r in replies { self.send(r, to: client) }
                    }
                case .close?:
                    self.close(client); return
                case nil:
                    if data == nil { self.close(client); return }
                default:
                    break // binary / ping / pong: ignore
                }
                self.receive(client)
            }
        }
    }

    func send(_ msg: OutboundMessage, to client: Client) {
        guard !client.closed else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "airmouse", metadata: [meta])
        client.connection.send(content: Data(ProtocolCodec.encode(msg).utf8), contentContext: ctx,
                               isComplete: true, completion: .idempotent)
    }

    func broadcast(_ msg: OutboundMessage) {
        for c in clients.values { send(msg, to: c) }
    }

    func close(_ client: Client) {
        guard !client.closed else { return }
        client.closed = true
        client.session.disconnect() // release held buttons
        client.connection.cancel()
        clients[client.id] = nil
        log?("phone disconnected: \(client.peer)")
        onDisconnect?(client)
    }
}
