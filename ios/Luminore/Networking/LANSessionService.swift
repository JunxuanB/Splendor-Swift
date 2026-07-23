@preconcurrency import Network
import Foundation
import LuminoreCore
import SwiftData

/// A returning player with a new account identity, waiting for the host to assign
/// them to one of the saved match's vacant seats.
struct PendingSubstitute: Identifiable, Equatable {
    let id: UUID
    let nickname: String
    let installID: UUID?
}

/// The reconnect maps persisted alongside a saved game so returning players can
/// reclaim their seats after the room is re-hosted. String-keyed for JSON.
struct SavedSessionMaps: Codable {
    var tokens: [String: String]
    var seatInstalls: [String: String]
}

@MainActor
final class LANSessionService: ObservableObject {
    static let serviceType = "_luminore._tcp"

    enum Phase: Equatable {
        case menu
        case connecting
        case lobby
        case configuration
        case game
        case results
        case reconnecting
        case ended
    }

    @Published private(set) var phase: Phase = .menu
    @Published private(set) var room: RoomSnapshot?
    @Published private(set) var game: ClientGameSnapshot?
    @Published private(set) var turnDeadline: Date?
    @Published var presentedError: String?
    /// The host paused the match; both host and clients show the paused cover.
    @Published private(set) var isPaused = false
    /// True on the host after resuming a saved game, until it confirms seat
    /// assignment and continues. While true, unmatched joiners become substitutes.
    @Published private(set) var isAwaitingResumeAssignment = false
    /// Returning players (new identities) waiting to be assigned to a vacant seat.
    @Published private(set) var pendingSubstitutes: [PendingSubstitute] = []
    /// Set when the host saves & suspends the match, or when a client is told the
    /// host suspended it — the UI keeps the rejoin record instead of clearing it.
    @Published private(set) var wasSuspended = false

    let localID: UUID
    let deviceInstallID: UUID
    private(set) var nickname: String
    private(set) var isHost = false

    private let rules = StandardRuleset()
    private let networkQueue = DispatchQueue(label: "com.junxuanb.Luminore.lan-session")
    private var listener: NWListener?
    private var peers: [UUID: LANPeerConnection] = [:]
    private var pendingPeers: [ObjectIdentifier: LANPeerConnection] = [:]
    private var hostPeer: LANPeerConnection?
    private var authoritativeGame: GameState?
    private var roomPassword = ""
    private var joinPassword = ""
    private var savedEndpoint: NWEndpoint?
    private var sessionToken: String?
    private var tokens: [UUID: String] = [:]
    /// Host-side map of participant UUID → the device install that owns that seat.
    /// Combined with `tokens`, this is the reconnect key: a seat can only be
    /// reclaimed by the same device that first took it, so two devices sharing one
    /// account UUID can never silently steal each other's seat.
    private var seatInstalls: [UUID: UUID] = [:]
    private var outgoingSequence: UInt64 = 0
    private var lastIncomingSequence: [UUID: UInt64] = [:]
    private var seenMessageIDs: Set<UUID> = []
    private var turnTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var isReconnectLoopActive = false
    private var isLeaving = false
    /// Host-side: pending substitute participant UUID → its connection, before the
    /// host assigns it to a seat.
    private var substitutePeers: [UUID: LANPeerConnection] = [:]
    private var substituteInstalls: [UUID: UUID] = [:]

    init(localID: UUID, nickname: String, deviceInstallID: UUID = DeviceIdentity.installID) {
        self.localID = localID
        self.nickname = nickname
        self.deviceInstallID = deviceInstallID
    }

    func updateNickname(_ value: String) {
        nickname = value
    }

    func host(roomName: String, password: String) {
        leave()
        isLeaving = false
        wasSuspended = false
        isHost = true
        roomPassword = password
        let descriptor = RoomDescriptor(
            id: UUID(),
            name: roomName,
            hostNickname: nickname,
            playerCount: 1,
            isPasswordProtected: !password.isEmpty
        )
        room = RoomSnapshot(
            descriptor: descriptor,
            participants: [Participant(id: localID, nickname: nickname, isHost: true)]
        )
        sessionToken = randomToken()
        tokens[localID] = sessionToken
        seatInstalls[localID] = deviceInstallID

        do {
            let listener = try NWListener(using: .tcp)
            listener.service = makeService()
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case let .failed(error) = state {
                    Task { @MainActor in self?.fail(error.localizedDescription) }
                }
            }
            self.listener = listener
            listener.start(queue: networkQueue)
            phase = .lobby
        } catch {
            fail(error.localizedDescription)
        }
    }

    func join(_ discovered: DiscoveredLANRoom, password: String) {
        leave()
        isLeaving = false
        wasSuspended = false
        isHost = false
        room = RoomSnapshot(descriptor: discovered.descriptor, participants: [])
        joinPassword = password
        savedEndpoint = discovered.endpoint
        phase = .connecting
        connectToHost(discovered.endpoint)
    }

    func enterConfiguration() {
        guard isHost, var room, room.participants.filter(\.isConnected).count >= 2 else { return }
        room.descriptor.stage = .configuration
        room.revision += 1
        self.room = room
        phase = .configuration
        updateAdvertisement()
        broadcastRoom()
    }

    func updateConfiguration(_ configuration: GameConfiguration) {
        guard isHost, var room, room.descriptor.stage == .configuration else { return }
        room.configuration = configuration
        room.revision += 1
        self.room = room
        broadcastRoom()
    }

    func startGame() {
        guard isHost, var room else { return }
        let connected = room.participants.filter(\.isConnected)
        guard connected.count >= 2 else { return }
        do {
            authoritativeGame = try rules.makeGame(
                participants: connected,
                configuration: room.configuration,
                seed: UInt64.random(in: .min ... .max)
            )
            room.participants = connected
            room.descriptor.playerCount = connected.count
            room.descriptor.stage = .playing
            room.revision += 1
            self.room = room
            phase = .game
            updateAdvertisement()
            broadcastRoom()
            scheduleTurnTimer()
            broadcastGame()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func submit(_ action: GameAction) {
        guard phase == .game, game?.currentPlayerID == localID else { return }
        if isHost {
            apply(action, from: localID, allowsPass: true)
        } else {
            sendToHost(.action(action))
        }
    }

    func returnToConfiguration() {
        guard isHost, var room else { return }
        authoritativeGame = nil
        game = nil
        isPaused = false
        isAwaitingResumeAssignment = false
        room.participants.removeAll { !$0.isConnected }
        guard room.participants.count >= 2 else {
            room.descriptor.stage = .lobby
            self.room = room
            phase = .lobby
            broadcastRoom()
            updateAdvertisement()
            return
        }
        room.descriptor.stage = .configuration
        room.revision += 1
        self.room = room
        phase = .configuration
        broadcast(.returnToConfiguration)
        broadcastRoom()
        updateAdvertisement()
    }

    func leave() {
        isLeaving = true
        turnTask?.cancel()
        reconnectTask?.cancel()
        if !isHost, hostPeer != nil { sendToHost(.leave) }
        hostPeer?.cancel()
        hostPeer = nil
        peers.values.forEach { $0.cancel() }
        peers.removeAll()
        pendingPeers.values.forEach { $0.cancel() }
        pendingPeers.removeAll()
        listener?.cancel()
        listener = nil
        authoritativeGame = nil
        room = nil
        game = nil
        turnDeadline = nil
        phase = .menu
        isHost = false
        isPaused = false
        isAwaitingResumeAssignment = false
        pendingSubstitutes.removeAll()
        substitutePeers.values.forEach { $0.cancel() }
        substitutePeers.removeAll()
        substituteInstalls.removeAll()
        isReconnectLoopActive = false
        tokens.removeAll()
        seatInstalls.removeAll()
        lastIncomingSequence.removeAll()
        seenMessageIDs.removeAll()
    }

    // MARK: Pause / resume (host authority)

    func pauseGame() {
        guard isHost, phase == .game, !isPaused else { return }
        isPaused = true
        turnTask?.cancel()
        turnDeadline = nil
        broadcast(.setPaused(true))
        broadcastGame()
    }

    func resumeGame() {
        guard isHost, isPaused else { return }
        isPaused = false
        broadcast(.setPaused(false))
        scheduleTurnTimer()
        broadcastGame()
    }

    /// Call when the app returns to the foreground so a client that dropped while
    /// suspended reconnects immediately instead of waiting out the backoff.
    func applicationDidBecomeActive() {
        guard !isHost, !isLeaving, phase == .reconnecting, hostPeer == nil,
              let endpoint = savedEndpoint
        else { return }
        connectToHost(endpoint)
        scheduleReconnect()
    }
}

private extension LANSessionService {
    func accept(_ connection: NWConnection) {
        let peer = LANPeerConnection(
            connection: connection,
            label: "com.junxuanb.Luminore.peer.\(UUID().uuidString)",
            onEnvelope: { [weak self] envelope, peer in
                Task { @MainActor in self?.receive(envelope, from: peer) }
            },
            onStop: { [weak self] peer, error in
                Task { @MainActor in self?.peerStopped(peer, error: error) }
            }
        )
        let challenge = PasswordAuthenticator.challenge()
        peer.challenge = challenge
        pendingPeers[ObjectIdentifier(peer)] = peer
        peer.start()
        send(.challenge(challenge), to: peer)
    }

    func connectToHost(_ endpoint: NWEndpoint) {
        let peer = LANPeerConnection(
            connection: NWConnection(to: endpoint, using: .tcp),
            label: "com.junxuanb.Luminore.host-connection",
            onEnvelope: { [weak self] envelope, peer in
                Task { @MainActor in self?.receive(envelope, from: peer) }
            },
            onStop: { [weak self] peer, error in
                Task { @MainActor in self?.peerStopped(peer, error: error) }
            }
        )
        hostPeer = peer
        peer.start()
    }

    func receive(_ envelope: WireEnvelope, from peer: LANPeerConnection) {
        guard envelope.protocolVersion == WireEnvelope.currentProtocolVersion else {
            send(.error("incompatible_protocol"), to: peer)
            return
        }
        guard !seenMessageIDs.contains(envelope.messageID) else { return }
        if let previous = lastIncomingSequence[envelope.senderID], envelope.sequence <= previous { return }
        seenMessageIDs.insert(envelope.messageID)
        if seenMessageIDs.count > 2_000 { seenMessageIDs.removeAll(keepingCapacity: true) }
        lastIncomingSequence[envelope.senderID] = envelope.sequence

        if isHost {
            receiveAsHost(envelope, from: peer)
        } else {
            receiveAsClient(envelope, from: peer)
        }
    }

    func receiveAsHost(_ envelope: WireEnvelope, from peer: LANPeerConnection) {
        switch envelope.payload {
        case let .join(request):
            handleJoin(request, peer: peer)
        case let .action(action):
            guard peer.participantID == envelope.senderID else { return }
            apply(action, from: envelope.senderID, allowsPass: true)
        case .leave:
            peer.cancel()
        default:
            break
        }
    }

    func receiveAsClient(_ envelope: WireEnvelope, from peer: LANPeerConnection) {
        switch envelope.payload {
        case let .challenge(challenge):
            let request = JoinRequest(
                participantID: localID,
                nickname: nickname,
                authenticationCode: PasswordAuthenticator.code(password: joinPassword, challenge: challenge),
                sessionToken: sessionToken,
                deviceInstallID: deviceInstallID
            )
            send(.join(request), to: peer)
        case let .joinResponse(response):
            guard response.accepted else {
                presentedError = response.reason ?? "join_rejected"
                phase = .ended
                peer.cancel()
                return
            }
            sessionToken = response.sessionToken
        case let .room(snapshot):
            room = snapshot
            switch snapshot.descriptor.stage {
            case .lobby: phase = .lobby
            case .configuration: phase = .configuration
            case .playing: if game != nil { phase = .game }
            case .results: phase = .results
            }
        case let .gameState(snapshot):
            game = snapshot
            if snapshot.status == .finished {
                phase = .results
                turnDeadline = nil
            } else {
                phase = .game
                updateClientDeadline()
            }
        case .returnToConfiguration:
            game = nil
            isPaused = false
            phase = .configuration
        case let .setPaused(paused):
            isPaused = paused
        case .sessionSuspended:
            // Host saved the match and stepped away. Leave gracefully but keep the
            // local rejoin record so the player can resume later.
            wasSuspended = true
            isLeaving = true
            leave()
        case let .error(message):
            presentedError = message
        default:
            break
        }
    }

    func handleJoin(_ request: JoinRequest, peer: LANPeerConnection) {
        guard let challenge = peer.challenge,
              PasswordAuthenticator.verify(request.authenticationCode, password: roomPassword, challenge: challenge),
              var room
        else {
            send(.joinResponse(.init(accepted: false, reason: "wrong_password", sessionToken: nil)), to: peer)
            return
        }

        if let index = room.participants.firstIndex(where: { $0.id == request.participantID }) {
            // Reclaiming a disconnected seat requires both the session token and a
            // matching device install. The install check stops a second device on
            // the same account UUID (shared iCloud / family sharing) from seizing a
            // seat it never held. Legacy clients that send no install fall back to
            // token-only reclaim.
            guard !room.participants[index].isConnected,
                  request.sessionToken == tokens[request.participantID],
                  installMatchesSeat(request)
            else {
                send(.joinResponse(.init(accepted: false, reason: "identity_in_use", sessionToken: nil)), to: peer)
                return
            }
            room.participants[index].isConnected = true
            room.participants[index].nickname = request.nickname
            if let install = request.deviceInstallID { seatInstalls[request.participantID] = install }
            if var state = authoritativeGame {
                rules.setConnection(true, playerID: request.participantID, in: &state)
                authoritativeGame = state
            }
        } else if isAwaitingResumeAssignment {
            // Resuming a saved match: a joiner whose UUID matches no seat is a
            // substitute. Hold the connection until the host assigns it to a vacant
            // seat; don't touch the roster yet.
            peer.participantID = request.participantID
            substitutePeers[request.participantID]?.cancel()
            substitutePeers[request.participantID] = peer
            substituteInstalls[request.participantID] = request.deviceInstallID
            pendingPeers.removeValue(forKey: ObjectIdentifier(peer))
            if !pendingSubstitutes.contains(where: { $0.id == request.participantID }) {
                pendingSubstitutes.append(PendingSubstitute(
                    id: request.participantID,
                    nickname: request.nickname,
                    installID: request.deviceInstallID
                ))
            }
            send(.joinResponse(.init(accepted: true, reason: nil, sessionToken: randomToken())), to: peer)
            return
        } else {
            guard room.descriptor.stage == .lobby, room.participants.count < room.descriptor.maximumPlayers else {
                send(.joinResponse(.init(accepted: false, reason: "room_unavailable", sessionToken: nil)), to: peer)
                return
            }
            room.participants.append(Participant(id: request.participantID, nickname: request.nickname))
            tokens[request.participantID] = randomToken()
            seatInstalls[request.participantID] = request.deviceInstallID
        }

        peer.participantID = request.participantID
        peers[request.participantID]?.cancel()
        peers[request.participantID] = peer
        pendingPeers.removeValue(forKey: ObjectIdentifier(peer))
        room.descriptor.playerCount = room.participants.filter(\.isConnected).count
        room.revision += 1
        self.room = room
        send(.joinResponse(.init(accepted: true, reason: nil, sessionToken: tokens[request.participantID])), to: peer)
        broadcastRoom()
        updateAdvertisement()
        if authoritativeGame != nil {
            sendGame(to: request.participantID)
            if isPaused { send(.setPaused(true), to: peers[request.participantID] ?? peer) }
        }
    }

    func peerStopped(_ peer: LANPeerConnection, error: Error?) {
        if isHost {
            pendingPeers.removeValue(forKey: ObjectIdentifier(peer))
            if let subID = peer.participantID, substitutePeers[subID] === peer {
                substitutePeers.removeValue(forKey: subID)
                substituteInstalls.removeValue(forKey: subID)
                pendingSubstitutes.removeAll { $0.id == subID }
                return
            }
            guard let playerID = peer.participantID, peers[playerID] === peer else { return }
            peers.removeValue(forKey: playerID)
            guard var room, let index = room.participants.firstIndex(where: { $0.id == playerID }) else { return }
            if room.descriptor.stage == .lobby {
                room.participants.remove(at: index)
            } else {
                room.participants[index].isConnected = false
                if var state = authoritativeGame {
                    rules.setConnection(false, playerID: playerID, in: &state)
                    authoritativeGame = state
                }
            }
            room.descriptor.playerCount = room.participants.filter(\.isConnected).count
            room.revision += 1
            self.room = room
            broadcastRoom()
            scheduleTurnTimer()
            broadcastGame()
            updateAdvertisement()
        } else if hostPeer === peer, !isLeaving {
            hostPeer = nil
            phase = .reconnecting
            presentedError = error?.localizedDescription
            scheduleReconnect()
        }
    }

    func apply(_ action: GameAction, from playerID: UUID, allowsPass: Bool) {
        guard var state = authoritativeGame else { return }
        if case .pass = action, !allowsPass { return }
        do {
            try rules.apply(action, playerID: playerID, to: &state)
            authoritativeGame = state
            if state.status == .finished {
                room?.descriptor.stage = .results
                phase = .results
                updateAdvertisement()
            }
            scheduleTurnTimer()
            broadcastGame()
        } catch {
            if playerID == localID {
                presentedError = error.localizedDescription
            } else if let peer = peers[playerID] {
                send(.error(error.localizedDescription), to: peer)
            }
        }
    }

    func broadcastRoom() {
        guard let room else { return }
        broadcast(.room(room))
    }

    func broadcastGame() {
        guard let state = authoritativeGame else { return }
        game = state.snapshot(for: localID, turnDeadline: turnDeadline)
        phase = state.status == .finished ? .results : .game
        for playerID in peers.keys { sendGame(to: playerID) }
    }

    func sendGame(to playerID: UUID) {
        guard let state = authoritativeGame, let peer = peers[playerID] else { return }
        send(.gameState(state.snapshot(for: playerID, turnDeadline: turnDeadline)), to: peer)
    }

    func broadcast(_ message: NetworkMessage) {
        for peer in peers.values { send(message, to: peer) }
    }

    func sendToHost(_ message: NetworkMessage) {
        guard let hostPeer else { return }
        send(message, to: hostPeer)
    }

    func send(_ message: NetworkMessage, to peer: LANPeerConnection) {
        guard let room else { return }
        outgoingSequence &+= 1
        peer.send(WireEnvelope(
            roomID: room.descriptor.id,
            senderID: localID,
            sequence: outgoingSequence,
            payload: message
        ))
    }

    func scheduleTurnTimer() {
        turnTask?.cancel()
        guard isHost, !isPaused, let state = authoritativeGame, state.status == .playing,
              let seconds = state.configuration.turnDurationSeconds
        else {
            turnDeadline = nil
            return
        }
        let playerID = state.currentPlayer.id
        let revision = state.revision
        let graceSeconds = state.configuration.turnGracePeriodEnabled ? 5 : 0
        turnDeadline = Date().addingTimeInterval(TimeInterval(seconds))
        turnTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds + graceSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.authoritativeGame?.revision == revision,
                      self.authoritativeGame?.currentPlayer.id == playerID else { return }
                self.apply(.pass, from: playerID, allowsPass: true)
            }
        }
    }

    func updateClientDeadline() {
        turnDeadline = game?.turnDeadline
    }

    /// Keep retrying the host connection while the client is in `.reconnecting`,
    /// with exponential backoff. Idempotent: a second call while a loop is already
    /// running is a no-op, so repeated `peerStopped` events don't stack loops.
    func scheduleReconnect() {
        guard !isReconnectLoopActive, let endpoint = savedEndpoint else { return }
        isReconnectLoopActive = true
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            var delaySeconds = 1.0
            while !Task.isCancelled {
                let keepGoing = await MainActor.run { () -> Bool in
                    guard let self, !self.isLeaving, self.phase == .reconnecting else {
                        self?.isReconnectLoopActive = false
                        return false
                    }
                    if self.hostPeer == nil { self.connectToHost(endpoint) }
                    return true
                }
                guard keepGoing else { return }
                try? await Task.sleep(for: .seconds(delaySeconds))
                delaySeconds = min(delaySeconds * 2, 8)
            }
            await MainActor.run { self?.isReconnectLoopActive = false }
        }
    }

    func updateAdvertisement() {
        guard listener != nil else { return }
        listener?.service = makeService()
    }

    func makeService() -> NWListener.Service? {
        guard let room else { return nil }
        let record = NWTXTRecord([
            "id": room.descriptor.id.uuidString,
            "name": String(room.descriptor.name.prefix(40)),
            "host": String(room.descriptor.hostNickname.prefix(30)),
            "count": String(room.descriptor.playerCount),
            "max": String(room.descriptor.maximumPlayers),
            "locked": room.descriptor.isPasswordProtected ? "1" : "0",
            "stage": room.descriptor.stage.rawValue,
            "pv": String(WireEnvelope.currentProtocolVersion)
        ])
        return NWListener.Service(name: "Luminore-\(room.descriptor.id.uuidString.prefix(8))", type: Self.serviceType, txtRecord: record)
    }

    func installMatchesSeat(_ request: JoinRequest) -> Bool {
        guard let owner = seatInstalls[request.participantID], let incoming = request.deviceInstallID else {
            return true // one side is unknown (legacy client / never recorded): fall back to token-only.
        }
        return owner == incoming
    }

    func randomToken() -> String {
        UUID().uuidString + UUID().uuidString
    }

    func fail(_ message: String) {
        presentedError = message
        phase = .ended
    }
}

// MARK: - Save & resume (host authority)

extension LANSessionService {
    /// Host: serialize the whole match to a local `SavedGameRecord`, tell clients the
    /// session was suspended, and tear down. Resumable later via `resumeSavedGame`.
    func saveAndSuspend(context: ModelContext) {
        guard isHost, let state = authoritativeGame, let room else { return }
        do {
            let statePayload = try JSONEncoder().encode(state)
            let maps = SavedSessionMaps(
                tokens: Dictionary(uniqueKeysWithValues: tokens.map { ($0.key.uuidString, $0.value) }),
                seatInstalls: Dictionary(uniqueKeysWithValues: seatInstalls.map { ($0.key.uuidString, $0.value.uuidString) })
            )
            let sessionPayload = try JSONEncoder().encode(maps)
            let ownerKey = localID.uuidString
            let existing = try context.fetch(
                FetchDescriptor<SavedGameRecord>(predicate: #Predicate { $0.ownerKey == ownerKey })
            )
            existing.forEach(context.delete)
            context.insert(SavedGameRecord(
                ownerKey: ownerKey,
                gameID: state.gameID,
                roomID: room.descriptor.id,
                roomName: room.descriptor.name,
                modeRawValue: state.configuration.mode.rawValue,
                statePayload: statePayload,
                sessionPayload: sessionPayload
            ))
            try context.save()
        } catch {
            presentedError = error.localizedDescription
            return
        }
        wasSuspended = true
        broadcast(.sessionSuspended)
        // Give the suspend frames a moment to flush before cancelling connections.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            await MainActor.run { self?.leave() }
        }
    }

    /// Host: reload a saved match, re-host under the original room id, and wait
    /// (paused) for players to reclaim their seats. Substitutes can fill vacancies.
    func resumeSavedGame(_ record: SavedGameRecord) {
        leave()
        isLeaving = false
        wasSuspended = false
        isHost = true
        roomPassword = ""
        do {
            var state = try JSONDecoder().decode(GameState.self, from: record.statePayload)
            let maps = (try? JSONDecoder().decode(SavedSessionMaps.self, from: record.sessionPayload))
                ?? SavedSessionMaps(tokens: [:], seatInstalls: [:])

            // Everyone returns disconnected except the host on this device.
            let seatIDs = state.players.map(\.id)
            for seatID in seatIDs {
                rules.setConnection(seatID == localID, playerID: seatID, in: &state)
            }
            authoritativeGame = state

            tokens = Dictionary(uniqueKeysWithValues: maps.tokens.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
            seatInstalls = Dictionary(uniqueKeysWithValues: maps.seatInstalls.compactMap { key, value in
                guard let seat = UUID(uuidString: key), let install = UUID(uuidString: value) else { return nil }
                return (seat, install)
            })
            seatInstalls[localID] = deviceInstallID
            sessionToken = tokens[localID]

            let participants = state.players.map { player in
                Participant(
                    id: player.id,
                    nickname: player.nickname,
                    kind: player.kind,
                    isHost: player.id == localID,
                    isConnected: player.isConnected
                )
            }
            let descriptor = RoomDescriptor(
                id: record.roomID,
                name: record.roomName,
                hostNickname: nickname,
                playerCount: participants.filter(\.isConnected).count,
                isPasswordProtected: false,
                stage: .playing
            )
            room = RoomSnapshot(descriptor: descriptor, participants: participants, configuration: state.configuration)

            let listener = try NWListener(using: .tcp)
            listener.service = makeService()
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] listenerState in
                if case let .failed(error) = listenerState {
                    Task { @MainActor in self?.fail(error.localizedDescription) }
                }
            }
            self.listener = listener
            listener.start(queue: networkQueue)

            isPaused = true
            isAwaitingResumeAssignment = true
            phase = .game
            game = state.snapshot(for: localID, turnDeadline: nil)
        } catch {
            presentedError = error.localizedDescription
            leave()
        }
    }

    /// Host: bind a waiting substitute to a vacant seat, preserving that seat's
    /// in-game progress.
    func assignSubstitute(seatID: UUID, substituteID: UUID) {
        guard isHost, isAwaitingResumeAssignment,
              let substitute = pendingSubstitutes.first(where: { $0.id == substituteID }),
              let subPeer = substitutePeers[substituteID],
              var state = authoritativeGame,
              let seatIndex = state.players.firstIndex(where: { $0.id == seatID }),
              !state.players[seatIndex].isConnected,
              var room
        else { return }

        state.players[seatIndex] = state.players[seatIndex].reseated(as: substituteID, nickname: substitute.nickname)
        authoritativeGame = state

        if let index = room.participants.firstIndex(where: { $0.id == seatID }) {
            let old = room.participants[index]
            room.participants[index] = Participant(
                id: substituteID,
                nickname: substitute.nickname,
                kind: old.kind,
                isHost: false,
                isConnected: true
            )
        }
        room.descriptor.playerCount = room.participants.filter(\.isConnected).count
        room.revision += 1
        self.room = room

        tokens[substituteID] = tokens[seatID] ?? randomToken()
        tokens.removeValue(forKey: seatID)
        if let install = substitute.installID { seatInstalls[substituteID] = install }
        seatInstalls.removeValue(forKey: seatID)

        subPeer.participantID = substituteID
        peers[substituteID]?.cancel()
        peers[substituteID] = subPeer
        substitutePeers.removeValue(forKey: substituteID)
        substituteInstalls.removeValue(forKey: substituteID)
        pendingSubstitutes.removeAll { $0.id == substituteID }

        broadcastRoom()
        updateAdvertisement()
        sendGame(to: substituteID)
        send(.setPaused(true), to: subPeer)
    }

    /// Host: finish the resume-assignment step and continue play. Any unassigned
    /// substitutes are dropped; unfilled seats stay disconnected (auto-skipped).
    func continueResumedGame() {
        guard isHost, isAwaitingResumeAssignment else { return }
        isAwaitingResumeAssignment = false
        substitutePeers.values.forEach { $0.cancel() }
        substitutePeers.removeAll()
        substituteInstalls.removeAll()
        pendingSubstitutes.removeAll()
        resumeGame()
    }
}
