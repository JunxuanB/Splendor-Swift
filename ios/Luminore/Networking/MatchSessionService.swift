import Foundation
import LuminoreCore
import SwiftData

/// A returning player with a new account identity, waiting for the host to assign
/// them to one of the saved match's vacant seats.
struct PendingSubstitute: Identifiable, Equatable {
    let id: UUID
    let nickname: String
    let medalCount: Int
    let installID: UUID?

    init(id: UUID, nickname: String, medalCount: Int = 0, installID: UUID?) {
        self.id = id
        self.nickname = nickname
        self.medalCount = max(0, medalCount)
        self.installID = installID
    }
}

/// The reconnect maps persisted alongside a saved game so returning players can
/// reclaim their seats after the room is re-hosted. String-keyed for JSON.
struct SavedSessionMaps: Codable {
    var tokens: [String: String]
    var seatInstalls: [String: String]
}

@MainActor
final class MatchSessionService: ObservableObject {
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

    @Published var phase: Phase = .menu
    @Published var room: RoomSnapshot?
    @Published var game: ClientGameSnapshot?
    /// Latest host-confirmed action animation. All three transports publish the
    /// same event before their resulting game snapshot is presented.
    @Published var gameAnimationEvent: GameAnimationEvent?
    @Published var discoveredRooms: [DiscoveredMatchRoom] = []
    @Published var roomCode: String?
    @Published var turnDeadline: Date?
    @Published var openingTurnSelection: OpeningTurnSelection?
    @Published var presentedError: String?
    /// Authoritative pause state, mirrored from the game snapshot on clients and
    /// computed on the host. `nil` means the match is running. Drives which cover
    /// (host pause vs. disconnect-wait) is shown. See `isPaused`.
    @Published var matchPause: MatchPause?

    /// Convenience: any pause (host or disconnect) is active.
    var isPaused: Bool { matchPause != nil }
    /// True on the host after resuming a saved game, until it confirms seat
    /// assignment and continues. While true, unmatched joiners become substitutes.
    @Published var isAwaitingResumeAssignment = false
    /// Returning players (new identities) waiting to be assigned to a vacant seat.
    @Published var pendingSubstitutes: [PendingSubstitute] = []
    /// Set when the host saves & suspends the match, or when a client is told the
    /// host suspended it — the UI keeps the rejoin record instead of clearing it.
    @Published var wasSuspended = false

    let localID: UUID
    let deviceInstallID: UUID
    let mode: MultiplayerMode
    var serverURL: URL?
    var nickname: String
    var medalCount: Int
    var isHost = false
    var isPublic = true

    let rules = RulesEngine()
    var transport: any MatchTransport
    var participantPeers: [UUID: TransportPeerID] = [:]
    var peerParticipants: [TransportPeerID: UUID] = [:]
    var pendingPeers: Set<TransportPeerID> = []
    var challenges: [TransportPeerID: AuthChallenge] = [:]
    var hostPeer: TransportPeerID?
    var authoritativeGame: GameState?
    var roomPassword = ""
    var joinPassword = ""
    var sessionToken: String?
    var currentSessionToken: String? { sessionToken }
    var tokens: [UUID: String] = [:]
    /// Host-side map of participant UUID → the device install that owns that seat.
    /// Combined with `tokens`, this is the reconnect key: a seat can only be
    /// reclaimed by the same device that first took it, so two devices sharing one
    /// account UUID can never silently steal each other's seat.
    var seatInstalls: [UUID: UUID] = [:]
    var outgoingSequence: UInt64 = 0
    var lastIncomingSequence: [TransportPeerID: UInt64] = [:]
    var seenMessageIDs: Set<UUID> = []
    var turnTask: Task<Void, Never>?
    var openingTurnTask: Task<Void, Never>?
    /// Host-side task that computes and applies the current bot seat's move.
    /// Cancelled and rescheduled whenever the authoritative game advances.
    var botTask: Task<Void, Never>?
    /// Tutorial-only bot override. These actions are validated against the live
    /// authoritative state before use; normal AI takes over if validation fails.
    var tutorialOpponentID: UUID?
    var tutorialOpponentActions: [GameAction] = []
    var reconnectTask: Task<Void, Never>?
    var animationBroadcastTask: Task<Void, Never>?
    /// Host-side pause truth (the client mirrors `matchPause` from the snapshot).
    /// `hostPaused` is the manual pause; `disconnectGraceUntil` is the deadline of
    /// the active reconnect-wait window. `matchPause` is derived from these.
    var hostPaused = false
    var disconnectGraceUntil: Date?
    var disconnectGraceTask: Task<Void, Never>?
    /// How long the whole match freezes waiting for a dropped player to return
    /// before play continues (skipping seats still absent).
    let disconnectGraceDuration: TimeInterval = 15
    var isReconnectLoopActive = false
    var isLeaving = false
    /// Host-side: pending substitute participant UUID → its connection, before the
    /// host assigns it to a seat.
    var substitutePeers: [UUID: TransportPeerID] = [:]
    var substituteInstalls: [UUID: UUID] = [:]

    init(
        localID: UUID,
        nickname: String,
        medalCount: Int = 0,
        mode: MultiplayerMode = .lan,
        serverURL: URL? = nil,
        deviceInstallID: UUID = DeviceIdentity.installID,
        restoredSessionToken: String? = nil,
        transport: (any MatchTransport)? = nil
    ) {
        self.localID = localID
        self.nickname = nickname
        self.medalCount = max(0, medalCount)
        self.mode = mode
        self.serverURL = serverURL
        self.deviceInstallID = deviceInstallID
        self.sessionToken = restoredSessionToken
        self.transport = transport ?? MatchTransportFactory.make(mode: mode, serverURL: serverURL)
        configureTransportCallbacks()
    }

    func updateNickname(_ value: String) {
        nickname = value
    }

    func updateMedalCount(_ value: Int) {
        medalCount = max(0, value)
        guard authoritativeGame == nil, var room,
              let index = room.participants.firstIndex(where: { $0.id == localID })
        else { return }
        room.participants[index].medalCount = medalCount
        room.revision += 1
        self.room = room
        if isHost {
            broadcastRoom()
            updateAdvertisement()
        }
    }

    func updateInternetServer(_ url: URL) {
        guard mode == .internet, phase == .menu else { return }
        transport.disconnect(closeRoom: false)
        serverURL = url
        transport = InternetTransport(serverURL: url)
        configureTransportCallbacks()
    }

    func host(roomName: String, password: String, isPublic: Bool = true) {
        leave()
        isLeaving = false
        wasSuspended = false
        isHost = true
        self.isPublic = isPublic
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
            participants: [Participant(
                id: localID,
                nickname: nickname,
                medalCount: medalCount,
                isHost: true
            )]
        )
        sessionToken = randomToken()
        tokens[localID] = sessionToken
        seatInstalls[localID] = deviceInstallID

        phase = .connecting
        transport.host(room: descriptor, isPublic: isPublic)
    }

    func join(_ discovered: DiscoveredMatchRoom, password: String) {
        leave()
        isLeaving = false
        wasSuspended = false
        isHost = false
        room = RoomSnapshot(descriptor: discovered.descriptor, participants: [])
        joinPassword = password
        phase = .connecting
        transport.join(room: discovered)
    }

    func startBrowsing() { transport.startBrowsing() }
    func stopBrowsing() { transport.stopBrowsing() }

    func resolveRoom(code: String) async throws -> DiscoveredMatchRoom {
        try await transport.resolveRoom(code: code)
    }

    func resolveRoom(id: UUID) async throws -> DiscoveredMatchRoom {
        try await transport.resolveRoom(id: id)
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
        if configuration.mode == .duel,
           room.participants.filter(\.isConnected).count != 2 {
            presentedError = String(localized: "config.duel.requiresTwo")
            return
        }
        room.configuration = configuration
        room.descriptor.maximumPlayers = configuration.mode == .duel ? 2 : 7
        room.revision += 1
        self.room = room
        updateAdvertisement()
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
            openingTurnSelection = OpeningTurnSelection()
            room.participants = connected
            room.descriptor.playerCount = connected.count
            room.descriptor.stage = .playing
            room.revision += 1
            self.room = room
            phase = .game
            updateAdvertisement()
            broadcastRoom()
            scheduleOpeningTurnCompletion()
            broadcastGame()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func submit(_ action: GameAction) {
        guard phase == .game, !isOpeningTurnSelection, game?.currentPlayerID == localID else { return }
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
        openingTurnTask?.cancel()
        botTask?.cancel()
        tutorialOpponentID = nil
        tutorialOpponentActions.removeAll()
        openingTurnSelection = nil
        clearPauseState()
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
        openingTurnTask?.cancel()
        botTask?.cancel()
        tutorialOpponentID = nil
        tutorialOpponentActions.removeAll()
        reconnectTask?.cancel()
        animationBroadcastTask?.cancel()
        disconnectGraceTask?.cancel()
        if !isHost, hostPeer != nil { sendToHost(.leave) }
        hostPeer = nil
        participantPeers.removeAll()
        peerParticipants.removeAll()
        pendingPeers.removeAll()
        challenges.removeAll()
        transport.disconnect(closeRoom: isHost)
        authoritativeGame = nil
        room = nil
        game = nil
        gameAnimationEvent = nil
        turnDeadline = nil
        openingTurnSelection = nil
        phase = .menu
        isHost = false
        clearPauseState()
        isAwaitingResumeAssignment = false
        pendingSubstitutes.removeAll()
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
        guard isHost, phase == .game, !isPaused, !isOpeningTurnSelection else { return }
        hostPaused = true
        turnTask?.cancel()
        botTask?.cancel()
        turnDeadline = nil
        recomputePauseAndBroadcast()
    }

    func resumeGame() {
        guard isHost, hostPaused else { return }
        hostPaused = false
        // If players dropped while the host held the pause, don't jump straight
        // back into play — start a reconnect-wait window for them.
        if hasDisconnectedInGamePlayers {
            beginDisconnectPause()
        } else {
            recomputePause()
            scheduleTurnTimer()
            broadcastGame()
            scheduleBotTurnIfNeeded()
        }
    }

    /// Reset every pause flag (used on leave / return-to-config / resume setup).
    func clearPauseState() {
        matchPause = nil
        hostPaused = false
        disconnectGraceUntil = nil
        disconnectGraceTask?.cancel()
        disconnectGraceTask = nil
    }

    /// True when the match is live and at least one non-host seat is disconnected.
    var hasDisconnectedInGamePlayers: Bool {
        guard authoritativeGame?.status == .playing else { return false }
        return room?.participants.contains { !$0.isConnected && $0.id != localID } ?? false
    }

    /// Call when the app returns to the foreground so a client that dropped while
    /// suspended reconnects immediately instead of waiting out the backoff.
    func applicationDidBecomeActive() {
        guard !isHost, !isLeaving, phase == .reconnecting, hostPeer == nil else { return }
        transport.reconnect()
        scheduleReconnect()
    }

    var isOpeningTurnSelection: Bool {
        guard let selection = openingTurnSelection else { return false }
        return Date() < selection.endsAt
    }
}
