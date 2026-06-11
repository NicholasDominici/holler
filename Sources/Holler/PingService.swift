import Foundation
import Network

struct Peer {
    let id: String?
    let name: String
    let endpoint: NWEndpoint
    let wiredInUntil: Date?

    var isWiredIn: Bool { wiredInUntil.map { $0 > Date() } ?? false }
}

enum PingResult {
    case delivered
    case wiredIn
    case failed
}

/// Advertises this machine over Bonjour, browses for other Holler users on the
/// local network, and sends/receives pings over short-lived TCP connections.
/// Wired In (focus) state is broadcast to peers in the TXT record and enforced
/// on receive: pings arriving while Wired In are suppressed and answered with
/// "focus" instead of "ok".
final class PingService {
    static let serviceType = "_holler._tcp"

    private static let idKey = "holler.instanceID"
    private let queue = DispatchQueue(label: "holler.network")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var stopped = false
    private var wiredInUntil: Date?

    let instanceID: String
    private(set) var displayName: String

    /// Called on the main queue with the sorted list of visible peers.
    var onPeersChanged: (([Peer]) -> Void)?
    /// Called on the main queue with the sender's name when a ping arrives
    /// (never fires while Wired In).
    var onPing: ((String) -> Void)?

    init(displayName: String) {
        self.displayName = displayName
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: Self.idKey) {
            instanceID = existing
        } else {
            instanceID = UUID().uuidString
            defaults.set(instanceID, forKey: Self.idKey)
        }
    }

    func start() {
        queue.async {
            self.startListener()
            self.startBrowser()
        }
    }

    func stop() {
        queue.async {
            self.stopped = true
            self.listener?.cancel()
            self.browser?.cancel()
        }
    }

    func update(displayName: String) {
        queue.async {
            self.displayName = displayName
            self.listener?.cancel()
            self.startListener()
        }
    }

    /// Pass a future date to go Wired In until then, nil to end it.
    /// Restarting the listener republishes the TXT record so peers update.
    func setWiredIn(until: Date?) {
        queue.async {
            self.wiredInUntil = until
            self.listener?.cancel()
            self.startListener()
        }
    }

    // MARK: - Advertising / receiving

    private func startListener() {
        guard !stopped else { return }
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        guard let listener = try? NWListener(using: params) else {
            scheduleRestartListener()
            return
        }
        var txt = ["id": instanceID]
        if let until = wiredInUntil, until > Date() {
            txt["focus"] = String(Int(until.timeIntervalSince1970))
        }
        listener.service = NWListener.Service(
            name: displayName,
            type: Self.serviceType,
            domain: nil,
            txtRecord: Self.encodeTXT(txt)
        )
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleIncoming(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.scheduleRestartListener() }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func scheduleRestartListener() {
        guard !stopped else { return }
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.listener?.cancel()
            self?.startListener()
        }
    }

    private func handleIncoming(_ connection: NWConnection) {
        var buffer = Data()
        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let data { buffer.append(data) }
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[..<newline])
                    if let object = try? JSONSerialization.jsonObject(with: line) as? [String: String],
                       let from = object["from"], !from.isEmpty {
                        let wired = self.wiredInUntil.map { $0 > Date() } ?? false
                        if !wired {
                            DispatchQueue.main.async { self.onPing?(from) }
                        }
                        let reply = wired ? "focus\n" : "ok\n"
                        connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                    } else {
                        connection.cancel()
                    }
                } else if isComplete || error != nil || buffer.count > 8192 {
                    connection.cancel()
                } else {
                    readMore()
                }
            }
        }
        connection.start(queue: queue)
        readMore()
    }

    // MARK: - Browsing

    private func startBrowser() {
        guard !stopped else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil),
            using: params
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.publish(results)
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.scheduleRestartBrowser() }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    private func scheduleRestartBrowser() {
        guard !stopped else { return }
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.browser?.cancel()
            self?.startBrowser()
        }
    }

    private func publish(_ results: Set<NWBrowser.Result>) {
        var peers: [Peer] = []
        var seenIDs = Set<String>()
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            var id: String?
            var wiredInUntil: Date?
            if case let .bonjour(txt) = result.metadata {
                id = txt["id"]
                if let focus = txt["focus"], let epoch = TimeInterval(focus) {
                    let until = Date(timeIntervalSince1970: epoch)
                    if until > Date() { wiredInUntil = until }
                }
            }
            if let id {
                if id == instanceID { continue }
                if !seenIDs.insert(id).inserted { continue }
            }
            peers.append(Peer(id: id, name: name, endpoint: result.endpoint, wiredInUntil: wiredInUntil))
        }
        peers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        DispatchQueue.main.async { self.onPeersChanged?(peers) }
    }

    // MARK: - Sending

    /// Connects to a peer, delivers the ping, and waits for its ack.
    /// Completion runs on the main queue.
    func ping(_ peer: Peer, completion: @escaping (PingResult) -> Void) {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let connection = NWConnection(to: peer.endpoint, using: params)
        var finished = false
        func finish(_ result: PingResult) {
            guard !finished else { return }
            finished = true
            connection.cancel()
            DispatchQueue.main.async { completion(result) }
        }
        connection.stateUpdateHandler = { [displayName, instanceID] state in
            switch state {
            case .ready:
                guard let payload = try? JSONSerialization.data(
                    withJSONObject: ["from": displayName, "id": instanceID]
                ) else {
                    finish(.failed)
                    return
                }
                connection.send(content: payload + Data("\n".utf8), completion: .contentProcessed { error in
                    if error != nil {
                        finish(.failed)
                        return
                    }
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 16) { data, _, _, _ in
                        guard let data, !data.isEmpty else {
                            finish(.failed)
                            return
                        }
                        let reply = String(decoding: data, as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        finish(reply == "focus" ? .wiredIn : .delivered)
                    }
                })
            case .failed, .cancelled:
                finish(.failed)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 6) { finish(.failed) }
    }

    // MARK: - TXT encoding

    private static func encodeTXT(_ entries: [String: String]) -> Data {
        var data = Data()
        for (key, value) in entries {
            let entry = Data("\(key)=\(value)".utf8)
            guard entry.count <= 255 else { continue }
            data.append(UInt8(entry.count))
            data.append(entry)
        }
        return data
    }
}
