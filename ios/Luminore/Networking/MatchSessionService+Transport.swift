import Foundation
import LuminoreCore

extension MatchSessionService {
    func configureTransportCallbacks() {
        transport.onEvent = { [weak self] event in self?.handleTransport(event) }
        transport.onRoomsChanged = { [weak self] rooms in self?.discoveredRooms = rooms }
    }

    func handleTransport(_ event: MatchTransportEvent) {
        switch event {
        case .ready:
            roomCode = transport.roomCode
            if isHost {
                if isAwaitingResumeAssignment {
                    phase = .lobby
                } else if let state = authoritativeGame {
                    phase = state.status == .finished ? .results : .game
                } else {
                    switch room?.descriptor.stage {
                    case .configuration: phase = .configuration
                    case .playing: phase = .game
                    case .results: phase = .results
                    case .lobby, .none: phase = .lobby
                    }
                }
                updateAdvertisement()
            }
        case let .peerConnected(peer):
            if isHost {
                let challenge = PasswordAuthenticator.challenge()
                challenges[peer] = challenge
                pendingPeers.insert(peer)
                send(.challenge(challenge), to: peer)
            } else {
                hostPeer = peer
            }
        case let .peerDisconnected(peer, error):
            peerStopped(peer, error: error)
        case let .message(envelope, peer):
            receive(envelope, from: peer)
        case .hostUnavailable:
            guard !isLeaving else { return }
            if isHost {
                prepareForRelayRecovery()
                return
            }
            hostPeer = nil
            phase = .reconnecting
            scheduleReconnect()
        case .hostAvailable:
            guard !isHost, !isLeaving else { return }
            phase = .connecting
        case let .roomClosed(reason):
            // A relay close (host explicitly closed, or its recovery window
            // expired) is terminal. Preserve the local unfinished-match marker for
            // diagnostics/manual cleanup, but stop every automatic retry.
            isLeaving = true
            reconnectTask?.cancel()
            reconnectTask = nil
            isReconnectLoopActive = false
            hostPeer = nil
            transport.disconnect(closeRoom: false)
            presentedError = NSLocalizedString(reason, comment: "")
            phase = .ended
        case let .failed(message):
            presentedError = NSLocalizedString(message, comment: "")
            if phase == .connecting, room == nil { phase = .ended }
        }
    }

    func receive(_ envelope: WireEnvelope, from peer: TransportPeerID) {
        guard envelope.protocolVersion == WireEnvelope.currentProtocolVersion else {
            send(.error("incompatible_protocol"), to: peer)
            return
        }
        guard !seenMessageIDs.contains(envelope.messageID) else { return }
        let isJoin: Bool
        if case .join = envelope.payload { isJoin = true } else { isJoin = false }
        if !isJoin, let previous = lastIncomingSequence[peer], envelope.sequence <= previous { return }
        seenMessageIDs.insert(envelope.messageID)
        if seenMessageIDs.count > 2_000 { seenMessageIDs.removeAll(keepingCapacity: true) }
        lastIncomingSequence[peer] = envelope.sequence

        if isHost {
            receiveAsHost(envelope, from: peer)
        } else {
            receiveAsClient(envelope, from: peer)
        }
    }

    func receiveAsHost(_ envelope: WireEnvelope, from peer: TransportPeerID) {
        switch envelope.payload {
        case let .join(request):
            handleJoin(request, peer: peer)
        case let .action(action):
            guard peerParticipants[peer] == envelope.senderID else { return }
            apply(action, from: envelope.senderID, allowsPass: true)
        case .leave:
            peerStopped(peer, error: nil)
        default:
            break
        }
    }

    func receiveAsClient(_ envelope: WireEnvelope, from peer: TransportPeerID) {
        switch envelope.payload {
        case let .challenge(challenge):
            let request = JoinRequest(
                participantID: localID,
                nickname: nickname,
                medalCount: medalCount,
                authenticationCode: PasswordAuthenticator.code(password: joinPassword, challenge: challenge),
                sessionToken: sessionToken,
                deviceInstallID: deviceInstallID
            )
            send(.join(request), to: peer)
        case let .joinResponse(response):
            guard response.accepted else {
                presentedError = NSLocalizedString(response.reason ?? "join_rejected", comment: "")
                phase = .ended
                transport.disconnect(closeRoom: false)
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
            medalCount = snapshot.players.first(where: { $0.id == localID })?.medalCount ?? medalCount
            // The snapshot is the single source of truth for pause, so a lost
            // setPaused control message can never leave a client stuck paused.
            matchPause = snapshot.pause
            receiveOpeningTurnSelection(snapshot.openingTurnSelection)
            if snapshot.status == .finished {
                phase = .results
                turnDeadline = nil
            } else {
                phase = .game
                updateClientDeadline()
            }
        case let .gameAnimation(animation):
            gameAnimationEvent = animation
        case .returnToConfiguration:
            game = nil
            openingTurnTask?.cancel()
            openingTurnSelection = nil
            clearPauseState()
            phase = .configuration
        case .setPaused:
            // Pause is now reconciled from the game snapshot (see .gameState).
            // The standalone signal is retained for wire compatibility only.
            break
        case .sessionSuspended:
            // Host saved the match and stepped away. Leave gracefully but keep the
            // local rejoin record so the player can resume later.
            wasSuspended = true
            isLeaving = true
            leave()
        case let .error(message):
            presentedError = NSLocalizedString(message, comment: "")
        default:
            break
        }
    }

    func handleJoin(_ request: JoinRequest, peer: TransportPeerID) {
        guard let challenge = challenges[peer],
              PasswordAuthenticator.verify(request.authenticationCode, password: roomPassword, challenge: challenge),
              var room
        else {
            send(.joinResponse(.init(accepted: false, reason: "wrong_password", sessionToken: nil)), to: peer)
            return
        }

        if let index = room.participants.firstIndex(where: { $0.id == request.participantID }) {
            // Reclaiming a disconnected seat normally requires the session token and a
            // matching device install. The install check stops a second device on the
            // same account UUID (shared iCloud / family sharing) from seizing a seat it
            // never held. Legacy clients that send no install fall back to token-only
            // reclaim.
            //
            // Exception: while resuming a saved match, everyone quit long ago and their
            // in-memory tokens are gone — so reclaim by matching UUID alone (this game
            // has no anti-cheat requirement anyway).
            let hasSavedCredentials = tokens[request.participantID] != nil
                || seatInstalls[request.participantID] != nil
            let credentialsOK = (request.sessionToken == tokens[request.participantID] && installMatchesSeat(request))
                || (isAwaitingResumeAssignment && !hasSavedCredentials)
            guard !room.participants[index].isConnected, credentialsOK else {
                send(.joinResponse(.init(accepted: false, reason: "identity_in_use", sessionToken: nil)), to: peer)
                return
            }
            room.participants[index].isConnected = true
            room.participants[index].nickname = request.nickname
            if let install = request.deviceInstallID { seatInstalls[request.participantID] = install }
            if var state = authoritativeGame {
                rules.setConnection(true, playerID: request.participantID, in: &state)
                if let stateIndex = state.players.firstIndex(where: { $0.id == request.participantID }) {
                    if state.status == .finished {
                        // A winner may reconnect before their device has persisted
                        // the final awards. Never let that stale join count overwrite
                        // the host's already-settled terminal state.
                        room.participants[index].medalCount = state.players[stateIndex].medalCount
                    } else {
                        state.players[stateIndex].nickname = request.nickname
                        state.players[stateIndex].medalCount = request.medalCount
                        room.participants[index].medalCount = request.medalCount
                    }
                }
                authoritativeGame = state
            } else {
                room.participants[index].medalCount = request.medalCount
            }
        } else if isAwaitingResumeAssignment {
            // Resuming a saved match: a joiner whose UUID matches no seat is a
            // substitute. Hold the connection until the host assigns it to a vacant
            // seat; don't touch the roster yet.
            let substituteToken = tokens[request.participantID] ?? randomToken()
            tokens[request.participantID] = substituteToken
            substitutePeers[request.participantID] = peer
            substituteInstalls[request.participantID] = request.deviceInstallID
            if let install = request.deviceInstallID { seatInstalls[request.participantID] = install }
            pendingPeers.remove(peer)
            peerParticipants[peer] = request.participantID
            if !pendingSubstitutes.contains(where: { $0.id == request.participantID }) {
                pendingSubstitutes.append(PendingSubstitute(
                    id: request.participantID,
                    nickname: request.nickname,
                    medalCount: request.medalCount,
                    installID: request.deviceInstallID
                ))
            }
            send(.joinResponse(.init(accepted: true, reason: nil, sessionToken: substituteToken)), to: peer)
            // Show the substitute the waiting room so they leave the connecting spinner.
            send(.room(room), to: peer)
            return
        } else {
            guard room.descriptor.stage == .lobby, room.participants.count < room.descriptor.maximumPlayers else {
                send(.joinResponse(.init(accepted: false, reason: "room_unavailable", sessionToken: nil)), to: peer)
                return
            }
            room.participants.append(Participant(
                id: request.participantID,
                nickname: request.nickname,
                medalCount: request.medalCount
            ))
            tokens[request.participantID] = randomToken()
            seatInstalls[request.participantID] = request.deviceInstallID
        }

        peerParticipants[peer] = request.participantID
        participantPeers[request.participantID] = peer
        pendingPeers.remove(peer)
        challenges.removeValue(forKey: peer)
        room.descriptor.playerCount = room.participants.filter(\.isConnected).count
        room.revision += 1
        self.room = room
        send(.joinResponse(.init(accepted: true, reason: nil, sessionToken: tokens[request.participantID])), to: peer)
        broadcastRoom()
        updateAdvertisement()
        // While resuming, keep rejoined players in the waiting lobby until the host
        // continues; only push live game state during an actual in-progress match.
        if authoritativeGame != nil, !isAwaitingResumeAssignment {
            // Ends the reconnect-wait if everyone's back, reschedules the timer,
            // and broadcasts a fresh, consistent snapshot (turn + deadline + pause)
            // to all peers including the one that just returned.
            onParticipantReconnected(request.participantID)
        }
    }

    func prepareForRelayRecovery() {
        turnTask?.cancel()
        turnDeadline = nil
        participantPeers.removeAll()
        peerParticipants.removeAll()
        pendingPeers.removeAll()
        challenges.removeAll()
        guard var room else { return }
        for index in room.participants.indices where room.participants[index].id != localID {
            room.participants[index].isConnected = false
            if var state = authoritativeGame {
                rules.setConnection(false, playerID: room.participants[index].id, skipTurns: false, in: &state)
                authoritativeGame = state
            }
        }
        room.descriptor.playerCount = room.participants.filter(\.isConnected).count
        room.revision += 1
        self.room = room
        // Freeze the match while the relay recovers; reconnecting players resume it.
        if phase == .game, authoritativeGame?.status == .playing {
            beginDisconnectPause()
        }
    }

    func peerStopped(_ peer: TransportPeerID, error: String?) {
        lastIncomingSequence.removeValue(forKey: peer)
        challenges.removeValue(forKey: peer)
        if isHost {
            pendingPeers.remove(peer)
            if let subID = peerParticipants[peer], substitutePeers[subID] == peer {
                substitutePeers.removeValue(forKey: subID)
                substituteInstalls.removeValue(forKey: subID)
                pendingSubstitutes.removeAll { $0.id == subID }
                peerParticipants.removeValue(forKey: peer)
                return
            }
            guard let playerID = peerParticipants.removeValue(forKey: peer), participantPeers[playerID] == peer else { return }
            participantPeers.removeValue(forKey: playerID)
            guard var room, let index = room.participants.firstIndex(where: { $0.id == playerID }) else { return }
            // A normal pre-game lobby can remove leavers. A saved match also uses
            // the lobby stage while seats are reclaimed, but its authoritative game
            // already exists, so removing a seat would destroy resume identity.
            if room.descriptor.stage == .lobby, authoritativeGame == nil {
                room.participants.remove(at: index)
            } else {
                room.participants[index].isConnected = false
                if var state = authoritativeGame {
                    // Only record the drop — do NOT skip the turn yet. A short blip
                    // shouldn't burn the player's turn; the grace pause below owns
                    // when (and whether) their seat is finally skipped.
                    rules.setConnection(false, playerID: playerID, skipTurns: false, in: &state)
                    authoritativeGame = state
                }
            }
            room.descriptor.playerCount = room.participants.filter(\.isConnected).count
            room.revision += 1
            self.room = room
            broadcastRoom()
            updateAdvertisement()
            if phase == .game, authoritativeGame?.status == .playing {
                beginDisconnectPause()
            } else {
                scheduleTurnTimer()
                broadcastGame()
            }
        } else if hostPeer == peer, !isLeaving {
            hostPeer = nil
            phase = .reconnecting
            presentedError = error
            scheduleReconnect()
        }
    }

    func apply(_ action: GameAction, from playerID: UUID, allowsPass: Bool) {
        guard !isOpeningTurnSelection, var state = authoritativeGame else { return }
        if case .pass = action, !allowsPass { return }
        do {
            let previousState = state
            try rules.apply(action, playerID: playerID, to: &state)
            let isDuelOptionalAction: Bool
            if case let .duel(duelAction) = action {
                switch duelAction {
                case .spendPrivilege, .replenish: isDuelOptionalAction = true
                default: isDuelOptionalAction = false
                }
            } else {
                isDuelOptionalAction = false
            }
            let animation = makeAnimationEvent(
                for: action,
                playerID: playerID,
                before: previousState,
                after: state
            )
            authoritativeGame = state
            if state.status == .finished {
                if var room {
                    room.descriptor.stage = .results
                    for index in room.participants.indices {
                        if let player = state.players.first(where: { $0.id == room.participants[index].id }) {
                            room.participants[index].medalCount = player.medalCount
                        }
                    }
                    room.revision += 1
                    self.room = room
                    broadcastRoom()
                }
                medalCount = state.players.first(where: { $0.id == localID })?.medalCount ?? medalCount
                updateAdvertisement()
            }
            if !isDuelOptionalAction {
                turnTask?.cancel()
                turnDeadline = nil
            }
            gameAnimationEvent = animation
            broadcast(.gameAnimation(animation))
            scheduleGameBroadcast(
                after: animation.snapshotDelay,
                revision: state.revision,
                resetsTurnTimer: !isDuelOptionalAction
            )
        } catch {
            if playerID == localID {
                presentedError = error.localizedDescription
            } else if let peer = participantPeers[playerID] {
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
        game = state.snapshot(
            for: localID,
            turnDeadline: turnDeadline,
            openingTurnSelection: openingTurnSelection,
            pause: matchPause
        )
        phase = state.status == .finished ? .results : .game
        for playerID in participantPeers.keys { sendGame(to: playerID) }
    }

    func sendGame(to playerID: UUID) {
        guard let state = authoritativeGame, let peer = participantPeers[playerID] else { return }
        send(.gameState(state.snapshot(
            for: playerID,
            turnDeadline: turnDeadline,
            openingTurnSelection: openingTurnSelection,
            pause: matchPause
        )), to: peer)
    }

    func broadcast(_ message: NetworkMessage) {
        for peer in participantPeers.values { send(message, to: peer) }
    }

    func sendToHost(_ message: NetworkMessage) {
        guard let hostPeer else { return }
        send(message, to: hostPeer)
    }

    func send(_ message: NetworkMessage, to peer: TransportPeerID) {
        guard let room else { return }
        outgoingSequence &+= 1
        transport.send(WireEnvelope(
            roomID: room.descriptor.id,
            senderID: localID,
            sequence: outgoingSequence,
            payload: message
        ), to: isHost ? .peer(peer) : .host)
    }

    func scheduleTurnTimer() {
        turnTask?.cancel()
        guard isHost, !isPaused, !isOpeningTurnSelection,
              let state = authoritativeGame, state.status == .playing,
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

    func scheduleOpeningTurnCompletion() {
        openingTurnTask?.cancel()
        guard let selection = openingTurnSelection else {
            if isHost { scheduleTurnTimer() }
            return
        }
        let remaining = selection.endsAt.timeIntervalSinceNow
        guard remaining > 0 else {
            openingTurnSelection = nil
            if isHost {
                scheduleTurnTimer()
                broadcastGame()
            }
            return
        }
        turnTask?.cancel()
        turnDeadline = nil
        openingTurnTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.openingTurnSelection == selection else { return }
                self.openingTurnSelection = nil
                if self.isHost {
                    self.scheduleTurnTimer()
                    self.broadcastGame()
                }
            }
        }
    }

    func receiveOpeningTurnSelection(_ selection: OpeningTurnSelection?) {
        openingTurnSelection = selection
        scheduleOpeningTurnCompletion()
    }

    /// Keep retrying the host connection while the client is in `.reconnecting`,
    /// with exponential backoff. Idempotent: a second call while a loop is already
    /// running is a no-op, so repeated `peerStopped` events don't stack loops.
    func scheduleReconnect() {
        guard !isReconnectLoopActive else { return }
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
                    if self.hostPeer == nil { self.transport.reconnect() }
                    return true
                }
                guard keepGoing else { return }
                let multiplier = self?.mode == .internet ? Double.random(in: 0.8 ... 1.2) : 1
                try? await Task.sleep(for: .seconds(delaySeconds * multiplier))
                delaySeconds = min(delaySeconds * 2, 30)
            }
            await MainActor.run { self?.isReconnectLoopActive = false }
        }
    }

    // MARK: Disconnect-grace pause (host authority)

    /// Recompute `matchPause` from the host's pause truth (no broadcast). Host
    /// pause takes priority; otherwise an active grace window with at least one
    /// still-absent player becomes a `.disconnect` pause. Must run before
    /// `scheduleTurnTimer()` on any resume, since the timer skips itself while
    /// `isPaused` is true.
    func recomputePause() {
        matchPause = computeHostPause()
    }

    /// Recompute and push the pause state to everyone. Used when the turn timer
    /// is already frozen (pause / disconnect), so no reschedule is needed.
    func recomputePauseAndBroadcast() {
        recomputePause()
        broadcastGame()
    }

    func computeHostPause() -> MatchPause? {
        if hostPaused {
            return MatchPause(reason: .host)
        }
        guard disconnectGraceUntil != nil else { return nil }
        let names = disconnectedPlayerNicknames
        guard !names.isEmpty else {
            // Everyone came back; drop the window.
            disconnectGraceUntil = nil
            return nil
        }
        return MatchPause(
            reason: .disconnect,
            resumeDeadline: disconnectGraceUntil,
            waitingForNicknames: names
        )
    }

    private var disconnectedPlayerNicknames: [String] {
        room?.participants.filter { !$0.isConnected && $0.id != localID }.map(\.nickname) ?? []
    }

    /// A player dropped mid-game: freeze the whole match for a grace window so
    /// they can reconnect before any turn is skipped. Idempotent — a second drop
    /// while already waiting simply refreshes the deadline.
    func beginDisconnectPause() {
        guard isHost, phase == .game, authoritativeGame?.status == .playing, !hostPaused else { return }
        guard hasDisconnectedInGamePlayers else { return }
        disconnectGraceUntil = Date().addingTimeInterval(disconnectGraceDuration)
        turnTask?.cancel()
        turnDeadline = nil
        recomputePauseAndBroadcast()
        startDisconnectGraceTask()
    }

    private func startDisconnectGraceTask() {
        disconnectGraceTask?.cancel()
        guard let deadline = disconnectGraceUntil else { return }
        disconnectGraceTask = Task { [weak self] in
            let remaining = deadline.timeIntervalSinceNow
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.disconnectGraceExpired() }
        }
    }

    /// Grace window elapsed. Any players still absent are now genuinely skipped:
    /// resume play, advancing past the current seat if it is the one that's gone.
    private func disconnectGraceExpired() {
        guard isHost, disconnectGraceUntil != nil else { return }
        disconnectGraceUntil = nil
        disconnectGraceTask = nil
        if var state = authoritativeGame, !state.currentPlayer.isConnected {
            rules.skipDisconnectedPlayers(in: &state)
            authoritativeGame = state
            if state.status == .finished {
                room?.descriptor.stage = .results
                updateAdvertisement()
            }
        }
        // Recompute pause before rescheduling: the timer skips itself while paused.
        recomputePause()
        scheduleTurnTimer()
        broadcastGame()
    }

    /// A previously-dropped player reclaimed their seat. If nobody is left absent,
    /// end the reconnect wait and resume from the exact same turn; otherwise keep
    /// waiting. Broadcasts a fresh snapshot to everyone with a correct deadline.
    func onParticipantReconnected(_ playerID: UUID) {
        if !hasDisconnectedInGamePlayers {
            disconnectGraceUntil = nil
            disconnectGraceTask?.cancel()
            disconnectGraceTask = nil
        }
        recomputePause()
        scheduleTurnTimer()
        broadcastGame()
    }

    func updateAdvertisement() {
        guard let room else { return }
        transport.updateRoom(room.descriptor, isPublic: isPublic)
        roomCode = transport.roomCode
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
