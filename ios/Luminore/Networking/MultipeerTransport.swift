@preconcurrency import MultipeerConnectivity
import Foundation
import LuminoreCore

@MainActor
final class MultipeerTransport: NSObject, MatchTransport {
    static let serviceType = "luminore-mpc"

    let mode: MultiplayerMode = .nearby
    var roomCode: String? { nil }
    var onEvent: ((MatchTransportEvent) -> Void)?
    var onRoomsChanged: (([DiscoveredMatchRoom]) -> Void)?

    private let localPeer = MCPeerID(displayName: "Luminore-\(DeviceIdentity.installID.uuidString.prefix(12))")
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var descriptor: RoomDescriptor?
    private var discoveredPeers: [UUID: MCPeerID] = [:]
    private var discoveredRooms: [UUID: DiscoveredMatchRoom] = [:]
    private var transportIDs: [MCPeerID: TransportPeerID] = [:]
    private var peersByTransportID: [TransportPeerID: MCPeerID] = [:]
    private var targetRoomID: UUID?
    private var isHosting = false

    func startBrowsing() {
        stopBrowsing()
        let browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: Self.serviceType)
        browser.delegate = self
        self.browser = browser
        browser.startBrowsingForPeers()
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        discoveredPeers.removeAll()
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
        let session = makeSession()
        self.session = session
        let advertiser = MCNearbyServiceAdvertiser(
            peer: localPeer,
            discoveryInfo: Self.discoveryInfo(room),
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()
        onEvent?(.ready)
    }

    func join(room: DiscoveredMatchRoom) {
        guard let peer = discoveredPeers[room.id] else {
            onEvent?(.failed(MatchTransportError.roomNotFound.localizedDescription))
            return
        }
        let existingBrowser = browser
        descriptor = room.descriptor
        targetRoomID = room.id
        isHosting = false
        let session = makeSession()
        self.session = session
        existingBrowser?.invitePeer(peer, to: session, withContext: Data(room.id.uuidString.utf8), timeout: 20)
    }

    func reconnect() {
        guard !isHosting, let targetRoomID else { return }
        if let peer = discoveredPeers[targetRoomID], let session, let browser {
            browser.invitePeer(peer, to: session, withContext: Data(targetRoomID.uuidString.utf8), timeout: 20)
        } else if browser == nil {
            startBrowsing()
        }
    }

    func send(_ envelope: WireEnvelope, to recipient: TransportRecipient) {
        guard let session, let data = try? JSONEncoder().encode(envelope) else { return }
        let peers: [MCPeerID]
        switch recipient {
        case .host:
            peers = isHosting ? [] : session.connectedPeers
        case let .peer(peerID):
            peers = peersByTransportID[peerID].map { [$0] } ?? []
        case .allClients:
            peers = isHosting ? session.connectedPeers : []
        }
        guard !peers.isEmpty else { return }
        do {
            try session.send(data, toPeers: peers, with: .reliable)
        } catch {
            onEvent?(.failed(error.localizedDescription))
        }
    }

    func updateRoom(_ descriptor: RoomDescriptor, isPublic: Bool) {
        _ = isPublic
        self.descriptor = descriptor
        guard isHosting else { return }
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        let replacement = MCNearbyServiceAdvertiser(
            peer: localPeer,
            discoveryInfo: Self.discoveryInfo(descriptor),
            serviceType: Self.serviceType
        )
        replacement.delegate = self
        advertiser = replacement
        replacement.startAdvertisingPeer()
    }

    func disconnect(closeRoom: Bool) {
        _ = closeRoom
        // Browsing has its own view-owned lifetime. In particular,
        // MatchSessionService resets the current session before asking the
        // transport to join a room. Keep the discovered peer alive across that
        // reset so the room selected from the nearby list can still be invited.
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        session?.disconnect()
        session?.delegate = nil
        session = nil
        transportIDs.removeAll()
        peersByTransportID.removeAll()
        descriptor = nil
        targetRoomID = nil
        isHosting = false
    }

    private func makeSession() -> MCSession {
        let session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        return session
    }

    private func handlePeer(_ peer: MCPeerID, state: MCSessionState) {
        switch state {
        case .connected:
            let id = transportIDs[peer] ?? TransportPeerID()
            transportIDs[peer] = id
            peersByTransportID[id] = peer
            if !isHosting { onEvent?(.ready) }
            onEvent?(.peerConnected(id))
        case .notConnected:
            guard let id = transportIDs.removeValue(forKey: peer) else { return }
            peersByTransportID.removeValue(forKey: id)
            onEvent?(.peerDisconnected(id, nil))
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    private func handleFoundPeer(_ peer: MCPeerID, info: [String: String]?) {
        guard let descriptor = Self.parseDiscoveryInfo(info) else { return }
        let room = DiscoveredMatchRoom(descriptor: descriptor)
        discoveredPeers[descriptor.id] = peer
        discoveredRooms[descriptor.id] = room
        publishRooms()
        if targetRoomID == descriptor.id, let session, let browser {
            browser.invitePeer(peer, to: session, withContext: Data(descriptor.id.uuidString.utf8), timeout: 20)
        }
    }

    private func publishRooms() {
        onRoomsChanged?(discoveredRooms.values.sorted {
            $0.descriptor.name.localizedStandardCompare($1.descriptor.name) == .orderedAscending
        })
    }

    private nonisolated static func discoveryInfo(_ room: RoomDescriptor) -> [String: String] {
        [
            "id": room.id.uuidString,
            "name": String(room.name.prefix(40)),
            "host": String(room.hostNickname.prefix(30)),
            "count": String(room.playerCount),
            "max": String(room.maximumPlayers),
            "locked": room.isPasswordProtected ? "1" : "0",
            "stage": room.stage.rawValue,
            "pv": String(WireEnvelope.currentProtocolVersion),
        ]
    }

    private nonisolated static func parseDiscoveryInfo(_ info: [String: String]?) -> RoomDescriptor? {
        guard let info,
              let idText = info["id"], let id = UUID(uuidString: idText),
              let name = info["name"], let host = info["host"],
              let countText = info["count"], let count = Int(countText),
              let maximumText = info["max"], let maximum = Int(maximumText),
              let stageText = info["stage"], let stage = RoomStage(rawValue: stageText),
              info["pv"] == String(WireEnvelope.currentProtocolVersion)
        else { return nil }
        return RoomDescriptor(
            id: id,
            name: name,
            hostNickname: host,
            playerCount: count,
            maximumPlayers: maximum,
            isPasswordProtected: info["locked"] == "1",
            stage: stage
        )
    }
}

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // MultipeerConnectivity's invitationHandler is a non-Sendable closure; box it
        // so it can cross into the MainActor task without a Swift 6 data-race error.
        let box = UncheckedSendableBox(invitationHandler)
        Task { @MainActor [weak self] in
            guard let self, self.isHosting, let session = self.session else {
                box.value(false, nil)
                return
            }
            if let context, let requested = String(data: context, encoding: .utf8),
               requested != self.descriptor?.id.uuidString {
                box.value(false, nil)
                return
            }
            box.value(true, session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor [weak self] in self?.onEvent?(.failed(error.localizedDescription)) }
    }
}

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor [weak self] in self?.handleFoundPeer(peerID, info: info) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            guard let self, let roomID = self.discoveredPeers.first(where: { $0.value == peerID })?.key else { return }
            self.discoveredPeers.removeValue(forKey: roomID)
            self.discoveredRooms.removeValue(forKey: roomID)
            self.publishRooms()
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak self] in self?.onEvent?(.failed(error.localizedDescription)) }
    }
}

extension MultipeerTransport: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in self?.handlePeer(peerID, state: state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count <= LengthPrefixedFramer.maximumFrameSize,
              let envelope = try? JSONDecoder().decode(WireEnvelope.self, from: data)
        else { return }
        Task { @MainActor [weak self] in
            guard let self, let id = self.transportIDs[peerID] else { return }
            self.onEvent?(.message(envelope, from: id))
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}


/// Wraps a non-Sendable value (here, MultipeerConnectivity's invitation handler) so it
/// can be captured into a concurrent task. Safe because the handler is only ever
/// invoked on the main actor.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
