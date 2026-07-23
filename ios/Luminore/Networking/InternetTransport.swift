import Foundation
import LuminoreCore

@MainActor
final class InternetTransport: MatchTransport {
    static let relayProtocolVersion = 1

    let mode: MultiplayerMode = .internet
    private(set) var roomCode: String?
    var onEvent: ((MatchTransportEvent) -> Void)?
    var onRoomsChanged: (([DiscoveredMatchRoom]) -> Void)?

    let serverURL: URL
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var browseTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var handshakeTask: Task<Void, Never>?
    private var hostReconnectTask: Task<Void, Never>?
    private var reconnectValidationTask: Task<Void, Never>?
    private var hostOperationTask: Task<Void, Never>?
    private var room: RoomDescriptor?
    private var isPublic = true
    private var isHosting = false
    private var hostToken: String?
    private var isIntentionallyClosing = false
    private var didAnnounceHost = false
    private var didReceiveReady = false

    /// A dedicated session whose request timeout is effectively disabled. A game
    /// socket is long-lived and carries no traffic while a player deliberates on
    /// their turn, yet `URLSessionWebSocketTask` treats `timeoutIntervalForRequest`
    /// as an idle deadline — the shared session's 60s default (or any short value)
    /// tears the socket down mid-turn, surfacing POSIX "Socket is not connected".
    /// Liveness is instead detected by the keepalive ping on an established socket,
    /// and the initial connect is bounded by a per-connection handshake watchdog.
    private let socketSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 86_400
        return URLSession(configuration: configuration)
    }()

    init(serverURL: URL) {
        self.serverURL = serverURL
    }

    func startBrowsing() {
        stopBrowsing()
        browseTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshRooms()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopBrowsing() {
        browseTask?.cancel()
        browseTask = nil
        onRoomsChanged?([])
    }

    func resolveRoom(code: String) async throws -> DiscoveredMatchRoom {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 6 else { throw MatchTransportError.roomNotFound }
        let response: RoomResponse = try await request(path: "v1/rooms/code/\(normalized)")
        guard response.room.hostConnected else { throw MatchTransportError.roomNotFound }
        return DiscoveredMatchRoom(descriptor: response.room.descriptor)
    }

    func resolveRoom(id: UUID) async throws -> DiscoveredMatchRoom {
        let response: RoomResponse = try await request(path: "v1/rooms/\(id.uuidString)")
        guard response.room.hostConnected else { throw MatchTransportError.roomNotFound }
        return DiscoveredMatchRoom(descriptor: response.room.descriptor)
    }

    func host(room: RoomDescriptor, isPublic: Bool) {
        disconnect(closeRoom: true)
        self.room = room
        self.isPublic = isPublic
        isHosting = true
        isIntentionallyClosing = false
        hostOperationTask?.cancel()
        hostOperationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await InternetServerSettings.healthCheck(url: self.serverURL)
                try Task.checkCancellation()
                let body = CreateRoomBody(
                    descriptor: room,
                    isPublic: isPublic,
                    relayProtocolVersion: Self.relayProtocolVersion,
                    gameProtocolVersion: WireEnvelope.currentProtocolVersion
                )
                let created: CreateRoomResponse = try await self.request(path: "v1/rooms", method: "POST", body: body)
                try Task.checkCancellation()
                self.roomCode = created.roomCode
                self.hostToken = created.hostToken
                self.connect()
            } catch {
                if !Task.isCancelled { self.onEvent?(.failed(error.localizedDescription)) }
            }
        }
    }

    func join(room: DiscoveredMatchRoom) {
        disconnect(closeRoom: false)
        self.room = room.descriptor
        isHosting = false
        isIntentionallyClosing = false
        didAnnounceHost = false
        connect()
    }

    func reconnect() {
        guard socket == nil, let room, !isIntentionallyClosing,
              reconnectValidationTask == nil
        else { return }
        reconnectValidationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.reconnectValidationTask = nil }
            do {
                // A client that was offline when the 30-minute alarm fired never
                // receives the 4000 close frame. Resolve first so a deleted room
                // still becomes terminal instead of retrying forever.
                let response: RoomResponse = try await self.request(path: "v1/rooms/\(room.id.uuidString)")
                guard response.room.relayProtocolVersion == Self.relayProtocolVersion,
                      response.room.gameProtocolVersion == WireEnvelope.currentProtocolVersion
                else {
                    self.isIntentionallyClosing = true
                    self.onEvent?(.roomClosed("room_closed"))
                    return
                }
                guard !Task.isCancelled, self.socket == nil, !self.isIntentionallyClosing else { return }
                self.connect()
            } catch MatchTransportError.roomNotFound {
                self.isIntentionallyClosing = true
                self.onEvent?(.roomClosed("room_closed"))
            } catch {
                if !Task.isCancelled { self.onEvent?(.failed(error.localizedDescription)) }
            }
        }
    }

    func send(_ envelope: WireEnvelope, to recipient: TransportRecipient) {
        guard let socket else { return }
        do {
            let payload = try JSONEncoder().encode(envelope).base64EncodedString()
            let frame: ClientSocketFrame
            switch recipient {
            case .host:
                frame = .relay(destination: "host", peerID: nil, payload: payload)
            case let .peer(peer):
                frame = .relay(destination: "peer", peerID: peer.rawValue, payload: payload)
            case .allClients:
                frame = .relay(destination: "broadcast", peerID: nil, payload: payload)
            }
            socket.send(.string(try frame.encodedString())) { [weak self, weak socket] error in
                guard error != nil, let socket else { return }
                Task { @MainActor in self?.handleConnectionDrop(socket) }
            }
        } catch {
            onEvent?(.failed(error.localizedDescription))
        }
    }

    func updateRoom(_ descriptor: RoomDescriptor, isPublic: Bool) {
        room = descriptor
        self.isPublic = isPublic
        guard isHosting, let socket else { return }
        let frame = ClientSocketFrame.roomMetadata(descriptor: descriptor, isPublic: isPublic)
        if let text = try? frame.encodedString() { socket.send(.string(text)) { _ in } }
    }

    func disconnect(closeRoom: Bool) {
        isIntentionallyClosing = true
        hostOperationTask?.cancel()
        reconnectValidationTask?.cancel()
        hostReconnectTask?.cancel()
        handshakeTask?.cancel()
        hostOperationTask = nil
        reconnectValidationTask = nil
        hostReconnectTask = nil
        handshakeTask = nil
        let closingSocket = socket
        if closeRoom, isHosting, let closingSocket,
           let text = try? ClientSocketFrame.closeRoom.encodedString() {
            // Keep this socket alive until the close-room control frame is handed to
            // URLSession. Cancelling immediately can race the send and leave a relay
            // room visible until its reconnect alarm fires.
            closingSocket.send(.string(text)) { _ in
                closingSocket.cancel(with: .normalClosure, reason: nil)
            }
        } else {
            closingSocket?.cancel(with: .goingAway, reason: nil)
        }
        receiveTask?.cancel()
        pingTask?.cancel()
        receiveTask = nil
        pingTask = nil
        socket = nil
        didAnnounceHost = false
        didReceiveReady = false
        if closeRoom {
            room = nil
            roomCode = nil
            hostToken = nil
        }
    }

    private func connect() {
        guard let room else { return }
        receiveTask?.cancel()
        pingTask?.cancel()
        handshakeTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)

        var components = URLComponents(url: serverURL.appending(path: "v1/rooms/\(room.id.uuidString)/connect"), resolvingAgainstBaseURL: false)!
        components.scheme = serverURL.scheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "role", value: isHosting ? "host" : "client")]
        var request = URLRequest(url: components.url!)
        if isHosting, let hostToken { request.setValue("Bearer \(hostToken)", forHTTPHeaderField: "Authorization") }
        let socket = socketSession.webSocketTask(with: request)
        self.socket = socket
        isIntentionallyClosing = false
        didReceiveReady = false
        socket.resume()
        receiveTask = Task { [weak self, weak socket] in
            guard let self, let socket else { return }
            await self.receiveLoop(socket)
        }
        pingTask = Task { [weak self, weak socket] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self, let socket else { return }
                socket.sendPing { error in
                    guard error != nil else { return }
                    Task { @MainActor in self.handleConnectionDrop(socket) }
                }
            }
        }
        // The session request timeout is intentionally disabled, so a stalled
        // handshake (server unreachable after the room resolved) would otherwise
        // hang forever. Bound the connect: if no `ready` arrives, treat it as a
        // drop so the client's reconnect loop / host recovery retries.
        handshakeTask = Task { [weak self, weak socket] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, let socket,
                  self.socket === socket, !self.didReceiveReady else { return }
            self.handleConnectionDrop(socket)
        }
    }

    /// Unified teardown for a socket that dropped without an explicit local close —
    /// a receive error, a keepalive-ping failure, a failed send, or a stalled
    /// handshake. A terminal relay closure stops all retries; any other drop is
    /// reported as a relay outage so the session can reconnect, and the host also
    /// starts re-establishing its own relay socket. A transient drop deliberately
    /// does not surface a raw error alert — the reconnecting UI covers it.
    private func handleConnectionDrop(_ socket: URLSessionWebSocketTask) {
        guard self.socket === socket else { return }
        self.socket = nil
        receiveTask?.cancel()
        pingTask?.cancel()
        handshakeTask?.cancel()
        receiveTask = nil
        pingTask = nil
        handshakeTask = nil
        guard !isIntentionallyClosing else { return }
        didAnnounceHost = false
        didReceiveReady = false
        if let reason = Self.terminalRoomClosure(
            closeCode: socket.closeCode,
            closeReason: socket.closeReason
        ) {
            reconnectValidationTask?.cancel()
            reconnectValidationTask = nil
            isIntentionallyClosing = true
            onEvent?(.roomClosed(reason))
            return
        }
        onEvent?(.hostUnavailable)
        scheduleHostReconnect()
    }

    /// The host owns the room, so nothing else will re-open its relay socket. Make
    /// one delayed re-connect attempt; if it also drops, the resulting
    /// `handleConnectionDrop` schedules the next attempt, giving a self-pacing retry
    /// loop that stops once the socket is live or the room is closed. Clients
    /// reconnect through the session instead, so this is host-only.
    private func scheduleHostReconnect() {
        guard isHosting, !isIntentionallyClosing, socket == nil else { return }
        hostReconnectTask?.cancel()
        hostReconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !self.isIntentionallyClosing, self.socket == nil else { return }
                self.connect()
            }
        }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case let .string(text): data = Data(text.utf8)
                case let .data(bytes): data = bytes
                @unknown default: continue
                }
                let frame = try JSONDecoder().decode(ServerSocketFrame.self, from: data)
                handle(frame)
            }
        } catch {
            handleConnectionDrop(socket)
        }
    }

    private func handle(_ frame: ServerSocketFrame) {
        switch frame.type {
        case "ready":
            didReceiveReady = true
            handshakeTask?.cancel()
            handshakeTask = nil
            onEvent?(.ready)
            if !isHosting { announceHostIfNeeded() }
        case "peerConnected": frame.peerID.map { onEvent?(.peerConnected(TransportPeerID($0))) }
        case "peerDisconnected": frame.peerID.map { onEvent?(.peerDisconnected(TransportPeerID($0), nil)) }
        case "hostUnavailable":
            didAnnounceHost = false
            onEvent?(.hostUnavailable)
        case "hostAvailable":
            onEvent?(.hostAvailable)
            announceHostIfNeeded()
        case "error": onEvent?(.failed(frame.code ?? "server_error"))
        case "relay":
            guard let source = frame.fromPeerID, let payload = frame.payload,
                  let data = Data(base64Encoded: payload),
                  data.count <= LengthPrefixedFramer.maximumFrameSize,
                  let envelope = try? JSONDecoder().decode(WireEnvelope.self, from: data)
            else {
                onEvent?(.failed("invalid_frame"))
                return
            }
            onEvent?(.message(envelope, from: TransportPeerID(source)))
        default: break
        }
    }

    private func announceHostIfNeeded() {
        guard !didAnnounceHost else { return }
        didAnnounceHost = true
        onEvent?(.peerConnected(TransportPeerID("host")))
    }

    /// Cloudflare closes every remaining room socket with application code 4000
    /// after an explicit host close or the 30-minute recovery window. Keep this
    /// mapping separate so the terminal/retry decision is unit-testable.
    static func terminalRoomClosure(
        closeCode: URLSessionWebSocketTask.CloseCode,
        closeReason: Data?
    ) -> String? {
        guard closeCode.rawValue == 4_000 else { return nil }
        let reason = closeReason.map { String(decoding: $0, as: UTF8.self) }
        switch reason {
        case "host_timeout", "host_closed": return reason
        default: return "room_closed"
        }
    }

    private func refreshRooms() async {
        do {
            let response: RoomListResponse = try await request(path: "v1/rooms")
            let compatible = response.rooms.filter {
                $0.hostConnected && $0.relayProtocolVersion == Self.relayProtocolVersion
                    && $0.gameProtocolVersion == WireEnvelope.currentProtocolVersion
            }
            onRoomsChanged?(compatible.map { DiscoveredMatchRoom(descriptor: $0.descriptor) })
        } catch {
            onEvent?(.failed(error.localizedDescription))
        }
    }

    private func request<Response: Decodable>(path: String) async throws -> Response {
        try await request(path: path, method: "GET", body: Optional<EmptyBody>.none)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        var request = URLRequest(url: serverURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MatchTransportError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            if http.statusCode == 404 { throw MatchTransportError.roomNotFound }
            throw MatchTransportError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

private struct EmptyBody: Encodable {}
private struct CreateRoomBody: Encodable {
    let descriptor: RoomDescriptor
    let isPublic: Bool
    let relayProtocolVersion: Int
    let gameProtocolVersion: Int
}
private struct CreateRoomResponse: Decodable {
    let roomCode: String
    let hostToken: String
}
private struct InternetRoomListing: Decodable {
    let descriptor: RoomDescriptor
    let code: String
    let isPublic: Bool
    let hostConnected: Bool
    let relayProtocolVersion: Int
    let gameProtocolVersion: Int
}
private struct RoomListResponse: Decodable { let rooms: [InternetRoomListing] }
private struct RoomResponse: Decodable { let room: InternetRoomListing }

private enum ClientSocketFrame {
    case relay(destination: String, peerID: String?, payload: String)
    case roomMetadata(descriptor: RoomDescriptor, isPublic: Bool)
    case closeRoom

    func encodedString() throws -> String {
        let object: [String: Any]
        switch self {
        case let .relay(destination, peerID, payload):
            var relay: [String: Any] = ["type": "relay", "destination": destination, "payload": payload]
            if let peerID { relay["peerID"] = peerID }
            object = relay
        case let .roomMetadata(descriptor, isPublic):
            let data = try JSONEncoder().encode(descriptor)
            let descriptorObject = try JSONSerialization.jsonObject(with: data)
            object = ["type": "roomMetadata", "descriptor": descriptorObject, "isPublic": isPublic]
        case .closeRoom:
            object = ["type": "closeRoom"]
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}

private struct ServerSocketFrame: Decodable {
    let type: String
    let peerID: String?
    let fromPeerID: String?
    let payload: String?
    let code: String?
}
