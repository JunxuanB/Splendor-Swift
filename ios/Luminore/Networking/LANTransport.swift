@preconcurrency import Network
import Foundation
import LuminoreCore

@MainActor
final class LANTransport: MatchTransport {
    let mode: MultiplayerMode = .lan
    var roomCode: String? { nil }
    var onEvent: ((MatchTransportEvent) -> Void)?
    var onRoomsChanged: (([DiscoveredMatchRoom]) -> Void)?

    private static let serviceType = "_luminore._tcp"
    private let queue = DispatchQueue(label: "com.junxuanb.Luminore.lan-transport")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [TransportPeerID: LANPeerConnection] = [:]
    private var peerByObject: [ObjectIdentifier: TransportPeerID] = [:]
    private var roomEndpoints: [UUID: NWEndpoint] = [:]
    private var discoveredRooms: [UUID: DiscoveredMatchRoom] = [:]
    private var savedEndpoint: NWEndpoint?
    private var descriptor: RoomDescriptor?
    private var isHosting = false

    func startBrowsing() {
        stopBrowsing()
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let parsed = results.compactMap(Self.parseResult)
            Task { @MainActor in
                guard let self else { return }
                self.roomEndpoints = Dictionary(uniqueKeysWithValues: parsed.map { ($0.room.descriptor.id, $0.endpoint) })
                self.discoveredRooms = Dictionary(uniqueKeysWithValues: parsed.map { ($0.room.id, $0.room) })
                self.onRoomsChanged?(parsed.map(\.room).sorted {
                    $0.descriptor.name.localizedStandardCompare($1.descriptor.name) == .orderedAscending
                })
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case let .failed(error) = state {
                Task { @MainActor in self?.onEvent?(.failed(error.localizedDescription)) }
            }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        roomEndpoints.removeAll()
        discoveredRooms.removeAll()
        onRoomsChanged?([])
    }

    func resolveRoom(code: String) async throws -> DiscoveredMatchRoom {
        _ = code
        throw MatchTransportError.unsupportedRoomCode
    }

    func resolveRoom(id: UUID) async throws -> DiscoveredMatchRoom {
        guard let room = discoveredRooms[id] else { throw MatchTransportError.roomNotFound }
        return room
    }

    func host(room: RoomDescriptor, isPublic: Bool) {
        _ = isPublic
        disconnect(closeRoom: true)
        descriptor = room
        isHosting = true
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = makeService(room)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready: self?.onEvent?(.ready)
                    case let .failed(error): self?.onEvent?(.failed(error.localizedDescription))
                    default: break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            onEvent?(.failed(error.localizedDescription))
        }
    }

    func join(room: DiscoveredMatchRoom) {
        guard let endpoint = roomEndpoints[room.id] else {
            onEvent?(.failed(MatchTransportError.roomNotFound.localizedDescription))
            return
        }
        disconnect(closeRoom: false)
        descriptor = room.descriptor
        savedEndpoint = endpoint
        isHosting = false
        connect(to: endpoint)
    }

    func reconnect() {
        guard !isHosting, connections.isEmpty, let savedEndpoint else { return }
        connect(to: savedEndpoint)
    }

    func send(_ envelope: WireEnvelope, to recipient: TransportRecipient) {
        let targets: [LANPeerConnection]
        switch recipient {
        case .host:
            targets = connections.values.filter { _ in !isHosting }
        case let .peer(peerID):
            targets = connections[peerID].map { [$0] } ?? []
        case .allClients:
            targets = isHosting ? Array(connections.values) : []
        }
        for target in targets { target.send(envelope) }
    }

    func updateRoom(_ descriptor: RoomDescriptor, isPublic: Bool) {
        _ = isPublic
        self.descriptor = descriptor
        if listener != nil { listener?.service = makeService(descriptor) }
    }

    func disconnect(closeRoom: Bool) {
        _ = closeRoom
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        peerByObject.removeAll()
        if closeRoom { savedEndpoint = nil }
        isHosting = false
    }

    private func accept(_ connection: NWConnection) {
        let peerID = TransportPeerID()
        attach(connection, peerID: peerID)
        onEvent?(.peerConnected(peerID))
    }

    private func connect(to endpoint: NWEndpoint) {
        let peerID = TransportPeerID()
        attach(NWConnection(to: endpoint, using: .tcp), peerID: peerID)
        onEvent?(.ready)
        onEvent?(.peerConnected(peerID))
    }

    private func attach(_ connection: NWConnection, peerID: TransportPeerID) {
        let peer = LANPeerConnection(
            connection: connection,
            label: "com.junxuanb.Luminore.lan-peer.\(peerID.rawValue)",
            onEnvelope: { [weak self] envelope, connection in
                Task { @MainActor in
                    guard let self, let id = self.peerByObject[ObjectIdentifier(connection)] else { return }
                    self.onEvent?(.message(envelope, from: id))
                }
            },
            onStop: { [weak self] connection, error in
                Task { @MainActor in
                    guard let self, let id = self.peerByObject.removeValue(forKey: ObjectIdentifier(connection)) else { return }
                    self.connections.removeValue(forKey: id)
                    self.onEvent?(.peerDisconnected(id, error?.localizedDescription))
                }
            }
        )
        connections[peerID] = peer
        peerByObject[ObjectIdentifier(peer)] = peerID
        peer.start()
    }

    private func makeService(_ room: RoomDescriptor) -> NWListener.Service {
        let record = NWTXTRecord([
            "id": room.id.uuidString,
            "name": String(room.name.prefix(40)),
            "host": String(room.hostNickname.prefix(30)),
            "count": String(room.playerCount),
            "max": String(room.maximumPlayers),
            "locked": room.isPasswordProtected ? "1" : "0",
            "stage": room.stage.rawValue,
            "pv": String(WireEnvelope.currentProtocolVersion)
        ])
        return NWListener.Service(
            name: "Luminore-\(room.id.uuidString.prefix(8))",
            type: Self.serviceType,
            txtRecord: record
        )
    }

    private nonisolated static func parseResult(_ result: NWBrowser.Result) -> (room: DiscoveredMatchRoom, endpoint: NWEndpoint)? {
        guard case let .bonjour(record) = result.metadata,
              let idText = record["id"], let id = UUID(uuidString: idText),
              let name = record["name"], let host = record["host"],
              let countText = record["count"], let count = Int(countText),
              let maximumText = record["max"], let maximum = Int(maximumText),
              let stageText = record["stage"], let stage = RoomStage(rawValue: stageText),
              record["pv"] == String(WireEnvelope.currentProtocolVersion)
        else { return nil }
        let descriptor = RoomDescriptor(
            id: id,
            name: name,
            hostNickname: host,
            playerCount: count,
            maximumPlayers: maximum,
            isPasswordProtected: record["locked"] == "1",
            stage: stage
        )
        return (DiscoveredMatchRoom(descriptor: descriptor), result.endpoint)
    }
}
