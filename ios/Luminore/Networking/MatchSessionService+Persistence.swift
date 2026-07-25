import Foundation
import LuminoreCore
import SwiftData

// MARK: - Save & resume (host authority)

extension MatchSessionService {
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
                transportRawValue: mode.rawValue,
                serverURLString: serverURL?.absoluteString ?? "",
                isPublic: isPublic,
                sessionToken: sessionToken ?? "",
                statePayload: statePayload,
                sessionPayload: sessionPayload
            ))
            try context.save()
        } catch {
            presentedError = error.localizedDescription
            return
        }
        broadcast(.sessionSuspended)
        finishSuspendingAfterFlush()
    }

    /// Give suspend frames a moment to flush before cancelling connections. The
    /// task intentionally retains the session: SwiftUI dismisses the flow as soon
    /// as `wasSuspended` flips, and a weak capture could otherwise skip cleanup.
    func finishSuspendingAfterFlush() {
        Task { [self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            // Tear down first, then let SwiftUI dismiss. This prevents an immediate
            // tap on “Continue” from racing a still-existing Internet room (409).
            leave()
            wasSuspended = true
        }
    }

    /// Host: reload a saved match, re-host under the original room id, and wait
    /// (paused) for players to reclaim their seats. Substitutes can fill vacancies.
    func resumeSavedGame(_ record: SavedGameRecord) {
        leave()
        isLeaving = false
        wasSuspended = false
        isHost = true
        isPublic = record.isPublic
        roomPassword = ""
        do {
            var state = try JSONDecoder().decode(GameState.self, from: record.statePayload)
            let maps = (try? JSONDecoder().decode(SavedSessionMaps.self, from: record.sessionPayload))
                ?? SavedSessionMaps(tokens: [:], seatInstalls: [:])

            // Everyone returns disconnected except the host on this device.
            let seatIDs = state.players.map(\.id)
            for seatID in seatIDs {
                // Don't skip turns here: seats are reclaimed one by one and the host
                // decides the current player when it taps continue.
                rules.setConnection(seatID == localID, playerID: seatID, skipTurns: false, in: &state)
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
                    medalCount: player.medalCount,
                    isHost: player.id == localID,
                    isConnected: player.isConnected
                )
            }
            // Re-open as a joinable waiting room (stage .lobby) so returning players
            // and substitutes can discover and rejoin. The match only resumes once the
            // host taps continue (see `continueResumedGame`).
            let descriptor = RoomDescriptor(
                id: record.roomID,
                name: record.roomName,
                hostNickname: nickname,
                playerCount: participants.filter(\.isConnected).count,
                isPasswordProtected: false,
                stage: .lobby
            )
            room = RoomSnapshot(descriptor: descriptor, participants: participants, configuration: state.configuration)

            transport.host(room: descriptor, isPublic: isPublic)

            clearPauseState()
            isAwaitingResumeAssignment = true
            phase = .lobby
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

        state.players[seatIndex] = state.players[seatIndex].reseated(
            as: substituteID,
            nickname: substitute.nickname,
            medalCount: substitute.medalCount
        )
        if let duelIndex = state.duel?.players.firstIndex(where: { $0.id == seatID }) {
            state.duel?.players[duelIndex].id = substituteID
        }
        authoritativeGame = state

        if let index = room.participants.firstIndex(where: { $0.id == seatID }) {
            let old = room.participants[index]
            room.participants[index] = Participant(
                id: substituteID,
                nickname: substitute.nickname,
                kind: old.kind,
                medalCount: substitute.medalCount,
                isHost: false,
                isConnected: true
            )
        }
        room.descriptor.playerCount = room.participants.filter(\.isConnected).count
        room.revision += 1
        self.room = room

        let substituteToken = tokens[substituteID] ?? randomToken()
        tokens[substituteID] = substituteToken
        tokens.removeValue(forKey: seatID)
        if let install = substitute.installID { seatInstalls[substituteID] = install }
        seatInstalls.removeValue(forKey: seatID)

        peerParticipants[subPeer] = substituteID
        participantPeers[substituteID] = subPeer
        substitutePeers.removeValue(forKey: substituteID)
        substituteInstalls.removeValue(forKey: substituteID)
        pendingSubstitutes.removeAll { $0.id == substituteID }

        // The substitute may have joined with a provisional credential. Confirm
        // the credential that now owns the assigned seat before play resumes.
        send(.joinResponse(.init(accepted: true, reason: nil, sessionToken: substituteToken)), to: subPeer)
        broadcastRoom()
        updateAdvertisement()
    }

    /// Host: finish the resume waiting-room step and continue play from the saved
    /// state. Any unassigned substitutes are explicitly rejected; unfilled seats stay
    /// disconnected (auto-skipped on their turn).
    func continueResumedGame() {
        guard isHost, isAwaitingResumeAssignment, var room else { return }
        isAwaitingResumeAssignment = false
        for (substituteID, peer) in substitutePeers {
            send(.joinResponse(.init(
                accepted: false,
                reason: "substitute_not_assigned",
                sessionToken: nil
            )), to: peer)
            peerParticipants.removeValue(forKey: peer)
            challenges.removeValue(forKey: peer)
            lastIncomingSequence.removeValue(forKey: peer)
            tokens.removeValue(forKey: substituteID)
            seatInstalls.removeValue(forKey: substituteID)
        }
        substitutePeers.removeAll()
        substituteInstalls.removeAll()
        pendingSubstitutes.removeAll()

        room.descriptor.stage = .playing
        room.revision += 1
        self.room = room
        phase = .game
        clearPauseState()
        // Seats that never came back are simply absent now; if the saved turn lands
        // on one, advance past it so play can start.
        if var state = authoritativeGame, !state.currentPlayer.isConnected {
            rules.skipDisconnectedPlayers(in: &state)
            authoritativeGame = state
        }
        updateAdvertisement()
        broadcastRoom()
        scheduleTurnTimer()
        broadcastGame()
    }
}
