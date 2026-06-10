import Foundation
import Network

struct Peer {
    let id: String?
    let name: String
    let endpoint: NWEndpoint
}

/// Advertises this machine over Bonjour, browses for other Holler users on the
/// local network, and sends/receives pings over short-lived TCP connections.
final class PingService {
    static let serviceType = "_holler._tcp"

    private static let idKey = "holler.instanceID"
    private let queue = DispatchQueue(label: "holler.network")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var stopped = false

    let instanceID: String
    private(set) var displayName: String

    /// Called on the main queue with the sorted list of visible peers.
    var onPeersChanged: (([Peer]) -> Void)?
    /// Called on the main queue with the sender's name when a ping arrives.
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

    // MARK: - Advertising / receiving

    private func startListener() {
        guard !stopped else { return }
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        guard let listener = try? NWListener(using: params) else {
            scheduleRestartListener()
            return
        }
        listener.service = NWListener.Service(
            name: displayName,
            type: Self.serviceType,
            domain: nil,
            txtRecord: Self.encodeTXT(["id": instanceID])
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
                        DispatchQueue.main.async { self.onPing?(from) }
                        connection.send(content: Data("ok\n".utf8), completion: .contentProcessed { _ in
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
            if case let .bonjour(txt) = result.metadata {
                id = txt["id"]
            }
            if let id {
                if id == instanceID { continue }
                if !seenIDs.insert(id).inserted { continue }
            }
            peers.append(Peer(id: id, name: name, endpoint: result.endpoint))
        }
        peers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        DispatchQueue.main.async { self.onPeersChanged?(peers) }
    }

    // MARK: - Sending

    /// Connects to a peer, delivers the ping, and waits for its "ok" ack.
    /// Completion runs on the main queue with whether delivery was confirmed.
    func ping(_ peer: Peer, completion: @escaping (Bool) -> Void) {
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let connection = NWConnection(to: peer.endpoint, using: params)
        var finished = false
        func finish(_ ok: Bool) {
            guard !finished else { return }
            finished = true
            connection.cancel()
            DispatchQueue.main.async { completion(ok) }
        }
        connection.stateUpdateHandler = { [displayName, instanceID] state in
            switch state {
            case .ready:
                guard let payload = try? JSONSerialization.data(
                    withJSONObject: ["from": displayName, "id": instanceID]
                ) else {
                    finish(false)
                    return
                }
                connection.send(content: payload + Data("\n".utf8), completion: .contentProcessed { error in
                    if error != nil {
                        finish(false)
                        return
                    }
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 16) { data, _, _, _ in
                        finish(data?.isEmpty == false)
                    }
                })
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 6) { finish(false) }
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
