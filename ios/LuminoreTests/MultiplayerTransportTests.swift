import LuminoreCore
import XCTest
@testable import Luminore

@MainActor
final class MultiplayerTransportTests: XCTestCase {
    func testMedalCountsReachEveryTransportMode() throws {
        for mode in MultiplayerMode.allCases {
            let hostTransport = FakeMatchTransport(mode: mode)
            let clientTransport = FakeMatchTransport(mode: mode)
            hostTransport.other = clientTransport
            clientTransport.other = hostTransport

            let hostID = UUID()
            let clientID = UUID()
            let host = MatchSessionService(
                localID: hostID,
                nickname: "Host",
                medalCount: 18,
                mode: mode,
                transport: hostTransport
            )
            let client = MatchSessionService(
                localID: clientID,
                nickname: "Client",
                medalCount: 7,
                mode: mode,
                transport: clientTransport
            )

            host.host(roomName: "Medals", password: "")
            client.join(
                DiscoveredMatchRoom(descriptor: try XCTUnwrap(host.room?.descriptor)),
                password: ""
            )
            host.enterConfiguration()
            host.startGame()

            let hostPlayers = try XCTUnwrap(host.game?.players)
            let clientPlayers = try XCTUnwrap(client.game?.players)
            XCTAssertEqual(hostPlayers.first { $0.id == hostID }?.medalCount, 18, "mode: \(mode)")
            XCTAssertEqual(hostPlayers.first { $0.id == clientID }?.medalCount, 7, "mode: \(mode)")
            XCTAssertEqual(clientPlayers.first { $0.id == hostID }?.medalCount, 18, "mode: \(mode)")
            XCTAssertEqual(clientPlayers.first { $0.id == clientID }?.medalCount, 7, "mode: \(mode)")
        }
    }

    func testAcceptedAnimationEventsReachEveryTransportMode() throws {
        for mode in MultiplayerMode.allCases {
            let hostTransport = FakeMatchTransport(mode: mode)
            let clientTransport = FakeMatchTransport(mode: mode)
            hostTransport.other = clientTransport
            clientTransport.other = hostTransport

            let host = MatchSessionService(
                localID: UUID(),
                nickname: "Host",
                mode: mode,
                transport: hostTransport
            )
            let client = MatchSessionService(
                localID: UUID(),
                nickname: "Guest",
                mode: mode,
                transport: clientTransport
            )

            host.host(roomName: "Animation", password: "")
            client.join(
                DiscoveredMatchRoom(descriptor: try XCTUnwrap(host.room?.descriptor)),
                password: ""
            )
            host.enterConfiguration()
            host.startGame()
            host.openingTurnSelection = OpeningTurnSelection(
                startedAt: Date().addingTimeInterval(-2),
                endsAt: Date().addingTimeInterval(-1)
            )
            host.scheduleOpeningTurnCompletion()

            let actorID = try XCTUnwrap(host.authoritativeGame?.currentPlayer.id)
            host.apply(.take(tokens: [.diamond: 1], returning: [:]), from: actorID, allowsPass: true)

            let hostEvent = try XCTUnwrap(host.gameAnimationEvent, "host event for \(mode)")
            XCTAssertEqual(client.gameAnimationEvent, hostEvent, "client event for \(mode)")
            XCTAssertEqual(hostEvent.playerID, actorID)
            if case let .take(tokens) = hostEvent.kind {
                XCTAssertEqual(tokens, [.diamond: 1])
            } else {
                XCTFail("wrong animation payload for \(mode)")
            }

            client.leave()
            host.leave()
        }
    }

    func testAllTransportsUseTheSamePasswordJoinHandshake() {
        for mode in MultiplayerMode.allCases {
            let hostTransport = FakeMatchTransport(mode: mode)
            let clientTransport = FakeMatchTransport(mode: mode)
            hostTransport.other = clientTransport
            clientTransport.other = hostTransport

            let hostID = UUID()
            let clientID = UUID()
            let host = MatchSessionService(
                localID: hostID,
                nickname: "Host",
                mode: mode,
                transport: hostTransport
            )
            let client = MatchSessionService(
                localID: clientID,
                nickname: "Guest",
                mode: mode,
                transport: clientTransport
            )

            host.host(roomName: "Shared Core", password: "opal")
            guard let descriptor = host.room?.descriptor else {
                return XCTFail("Host did not create a room for \(mode)")
            }
            client.join(DiscoveredMatchRoom(descriptor: descriptor), password: "opal")

            XCTAssertEqual(host.phase, .lobby, "host phase for \(mode)")
            XCTAssertEqual(client.phase, .lobby, "client phase for \(mode)")
            XCTAssertEqual(host.room?.participants.map(\.id).sorted(by: uuidSort), [hostID, clientID].sorted(by: uuidSort))
            XCTAssertEqual(client.room?.participants.count, 2)
            XCTAssertNotNil(client.currentSessionToken)

            host.enterConfiguration()
            host.startGame()

            XCTAssertEqual(host.phase, .game, "host game phase for \(mode)")
            XCTAssertEqual(client.phase, .game, "client game phase for \(mode)")
            XCTAssertEqual(host.game?.startingPlayerID, client.game?.startingPlayerID)
            XCTAssertEqual(host.openingTurnSelection, client.openingTurnSelection)
            XCTAssertTrue(host.isOpeningTurnSelection)
            XCTAssertTrue(client.isOpeningTurnSelection)
            XCTAssertNil(host.turnDeadline, "turn timer must wait for roulette for \(mode)")
            XCTAssertNil(client.turnDeadline, "client timer must wait for roulette for \(mode)")

            let revision = host.authoritativeGame?.revision
            if let startingPlayerID = host.game?.startingPlayerID {
                host.apply(.pass, from: startingPlayerID, allowsPass: true)
            }
            XCTAssertEqual(host.authoritativeGame?.revision, revision, "actions are locked during roulette for \(mode)")

            host.openingTurnSelection = OpeningTurnSelection(
                startedAt: Date().addingTimeInterval(-2),
                endsAt: Date().addingTimeInterval(-1)
            )
            host.scheduleOpeningTurnCompletion()
            XCTAssertFalse(host.isOpeningTurnSelection)
            XCTAssertNil(host.openingTurnSelection)
            XCTAssertNil(client.openingTurnSelection)
            XCTAssertNotNil(host.turnDeadline, "host timer starts after roulette for \(mode)")
            XCTAssertNotNil(client.turnDeadline, "client receives timer after roulette for \(mode)")

            client.leave()
            host.leave()
        }
    }

    func testWrongPasswordIsRejectedWithoutLeakingPassword() {
        let hostTransport = FakeMatchTransport(mode: .internet)
        let clientTransport = FakeMatchTransport(mode: .internet)
        hostTransport.other = clientTransport
        clientTransport.other = hostTransport
        let host = MatchSessionService(localID: UUID(), nickname: "Host", mode: .internet, transport: hostTransport)
        let client = MatchSessionService(localID: UUID(), nickname: "Guest", mode: .internet, transport: clientTransport)

        host.host(roomName: "Locked", password: "secret")
        client.join(DiscoveredMatchRoom(descriptor: host.room!.descriptor), password: "incorrect")

        XCTAssertEqual(client.phase, .ended)
        XCTAssertFalse((client.presentedError ?? "").contains("secret"))
        XCTAssertEqual(host.room?.participants.count, 1)
    }

    func testInternetServerURLValidation() throws {
        XCTAssertEqual(
            try InternetServerSettings.normalizedURL(from: " https://relay.example.com/ ").absoluteString,
            "https://relay.example.com"
        )
        XCTAssertEqual(
            try InternetServerSettings.normalizedURL(from: "http://localhost:8787").absoluteString,
            "http://localhost:8787"
        )
        XCTAssertThrowsError(try InternetServerSettings.normalizedURL(from: "http://relay.example.com"))
        XCTAssertThrowsError(try InternetServerSettings.normalizedURL(from: "https://relay.example.com/path"))
    }

    func testRelayApplicationCloseIsTerminal() throws {
        let applicationClose = try XCTUnwrap(URLSessionWebSocketTask.CloseCode(rawValue: 4_000))
        XCTAssertEqual(
            InternetTransport.terminalRoomClosure(
                closeCode: applicationClose,
                closeReason: Data("host_timeout".utf8)
            ),
            "host_timeout"
        )
        XCTAssertEqual(
            InternetTransport.terminalRoomClosure(closeCode: applicationClose, closeReason: Data("other".utf8)),
            "room_closed"
        )
        XCTAssertNil(
            InternetTransport.terminalRoomClosure(closeCode: .goingAway, closeReason: Data("host_timeout".utf8))
        )

        let transport = FakeMatchTransport(mode: .internet)
        let session = MatchSessionService(localID: UUID(), nickname: "Guest", mode: .internet, transport: transport)
        session.phase = .reconnecting
        session.handleTransport(.roomClosed("host_timeout"))

        XCTAssertEqual(session.phase, .ended)
        XCTAssertNotNil(session.presentedError)
        XCTAssertEqual(transport.disconnectCalls, 1)
        XCTAssertFalse(transport.lastCloseRoom)
        XCTAssertTrue(session.isLeaving)
    }

    func testSuspendCleanupSurvivesSessionRelease() async throws {
        let transport = FakeMatchTransport(mode: .internet)
        var session: MatchSessionService? = MatchSessionService(
            localID: UUID(),
            nickname: "Host",
            mode: .internet,
            transport: transport
        )
        session?.isHost = true
        session?.finishSuspendingAfterFlush()
        session = nil

        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(transport.disconnectCalls, 1)
        XCTAssertTrue(transport.lastCloseRoom)
    }

    func testAssignedSubstituteKeepsTokenAcrossDisconnectAndReconnect() throws {
        let transport = FakeMatchTransport(mode: .internet)
        let hostID = UUID()
        let oldSeatID = UUID()
        let substituteID = UUID()
        let installID = UUID()
        let firstPeer = TransportPeerID("substitute-1")
        let host = MatchSessionService(localID: hostID, nickname: "Host", mode: .internet, transport: transport)
        let participants = [
            Participant(id: hostID, nickname: "Host", isHost: true),
            Participant(id: oldSeatID, nickname: "Away", isConnected: false),
        ]
        var state = try StandardRuleset().makeGame(
            participants: participants,
            configuration: .init(),
            seed: 7
        )
        host.rules.setConnection(false, playerID: oldSeatID, in: &state)
        host.isHost = true
        host.isAwaitingResumeAssignment = true
        host.authoritativeGame = state
        host.room = RoomSnapshot(
            descriptor: RoomDescriptor(
                id: UUID(),
                name: "Saved",
                hostNickname: "Host",
                playerCount: 1,
                isPasswordProtected: false,
                stage: .lobby
            ),
            participants: participants
        )
        host.pendingSubstitutes = [PendingSubstitute(id: substituteID, nickname: "Sub", installID: installID)]
        host.substitutePeers[substituteID] = firstPeer
        host.peerParticipants[firstPeer] = substituteID
        host.tokens[substituteID] = "provisional-token"
        host.seatInstalls[substituteID] = installID

        host.assignSubstitute(seatID: oldSeatID, substituteID: substituteID)

        XCTAssertEqual(host.tokens[substituteID], "provisional-token")
        let tokenConfirmation = try XCTUnwrap(transport.sentEnvelopes.compactMap { envelope -> JoinResponse? in
            if case let .joinResponse(response) = envelope.payload { return response }
            return nil
        }.last)
        XCTAssertTrue(tokenConfirmation.accepted)
        XCTAssertEqual(tokenConfirmation.sessionToken, "provisional-token")

        host.peerStopped(firstPeer, error: nil)
        XCTAssertEqual(host.room?.participants.first(where: { $0.id == substituteID })?.isConnected, false)
        XCTAssertTrue(host.authoritativeGame?.players.contains(where: { $0.id == substituteID }) == true)

        let secondPeer = TransportPeerID("substitute-2")
        let challenge = PasswordAuthenticator.challenge()
        host.challenges[secondPeer] = challenge
        host.handleJoin(
            JoinRequest(
                participantID: substituteID,
                nickname: "Sub",
                authenticationCode: PasswordAuthenticator.code(password: "", challenge: challenge),
                sessionToken: "provisional-token",
                deviceInstallID: installID
            ),
            peer: secondPeer
        )

        XCTAssertEqual(host.room?.participants.first(where: { $0.id == substituteID })?.isConnected, true)
        XCTAssertEqual(host.participantPeers[substituteID], secondPeer)
    }

    func testFinishedWinnerReconnectDoesNotOverwriteSettledMedalCount() throws {
        let transport = FakeMatchTransport(mode: .lan)
        let hostID = UUID()
        let winnerID = UUID()
        let installID = UUID()
        let peer = TransportPeerID("finished-winner")
        let participants = [
            Participant(id: hostID, nickname: "Host", isHost: true),
            Participant(id: winnerID, nickname: "Winner", medalCount: 2, isConnected: false),
        ]
        var state = try StandardRuleset().makeGame(participants: participants, configuration: .init(), seed: 4)
        state.status = .finished
        state.players[1].medalCount = 10

        let host = MatchSessionService(localID: hostID, nickname: "Host", mode: .lan, transport: transport)
        host.isHost = true
        host.authoritativeGame = state
        host.room = RoomSnapshot(
            descriptor: RoomDescriptor(
                id: UUID(), name: "Finished", hostNickname: "Host", playerCount: 1,
                isPasswordProtected: false, stage: .results
            ),
            participants: participants
        )
        host.tokens[winnerID] = "winner-token"
        host.seatInstalls[winnerID] = installID
        let challenge = PasswordAuthenticator.challenge()
        host.challenges[peer] = challenge

        host.handleJoin(
            JoinRequest(
                participantID: winnerID,
                nickname: "Winner",
                medalCount: 2,
                authenticationCode: PasswordAuthenticator.code(password: "", challenge: challenge),
                sessionToken: "winner-token",
                deviceInstallID: installID
            ),
            peer: peer
        )

        XCTAssertEqual(host.authoritativeGame?.players.first { $0.id == winnerID }?.medalCount, 10)
        XCTAssertEqual(host.room?.participants.first { $0.id == winnerID }?.medalCount, 10)
    }

    func testUnassignedSubstituteIsExplicitlyRejectedBeforeResume() throws {
        let transport = FakeMatchTransport(mode: .nearby)
        let hostID = UUID()
        let guestID = UUID()
        let peer = TransportPeerID("waiting-substitute")
        let host = MatchSessionService(localID: hostID, nickname: "Host", mode: .nearby, transport: transport)
        let participants = [
            Participant(id: hostID, nickname: "Host", isHost: true),
            Participant(id: UUID(), nickname: "Away", isConnected: false),
        ]
        var state = try StandardRuleset().makeGame(participants: participants, configuration: .init(), seed: 9)
        host.rules.setConnection(false, playerID: participants[1].id, in: &state)
        host.isHost = true
        host.isAwaitingResumeAssignment = true
        host.authoritativeGame = state
        host.room = RoomSnapshot(
            descriptor: RoomDescriptor(
                id: UUID(), name: "Saved", hostNickname: "Host", playerCount: 1,
                isPasswordProtected: false, stage: .lobby
            ),
            participants: participants
        )
        host.pendingSubstitutes = [PendingSubstitute(id: guestID, nickname: "Waiting", installID: nil)]
        host.substitutePeers[guestID] = peer
        host.peerParticipants[peer] = guestID
        host.tokens[guestID] = "temporary"

        host.continueResumedGame()

        let rejection = try XCTUnwrap(transport.sentEnvelopes.compactMap { envelope -> JoinResponse? in
            if case let .joinResponse(response) = envelope.payload, !response.accepted { return response }
            return nil
        }.first)
        XCTAssertEqual(rejection.reason, "substitute_not_assigned")
        XCTAssertTrue(host.pendingSubstitutes.isEmpty)
        XCTAssertNil(host.peerParticipants[peer])
        XCTAssertNil(host.tokens[guestID])
    }
}

@MainActor
private final class FakeMatchTransport: MatchTransport {
    let mode: MultiplayerMode
    var roomCode: String? { mode == .internet ? "ABC234" : nil }
    var onEvent: ((MatchTransportEvent) -> Void)?
    var onRoomsChanged: (([DiscoveredMatchRoom]) -> Void)?
    weak var other: FakeMatchTransport?
    private var room: RoomDescriptor?
    private var hosting = false
    var disconnectCalls = 0
    var lastCloseRoom = false
    var sentEnvelopes: [WireEnvelope] = []

    init(mode: MultiplayerMode) {
        self.mode = mode
    }

    func startBrowsing() {
        if let room = other?.room { onRoomsChanged?([DiscoveredMatchRoom(descriptor: room)]) }
    }

    func stopBrowsing() { onRoomsChanged?([]) }

    func resolveRoom(code: String) async throws -> DiscoveredMatchRoom {
        guard code == roomCode, let room = other?.room else { throw MatchTransportError.roomNotFound }
        return DiscoveredMatchRoom(descriptor: room)
    }

    func resolveRoom(id: UUID) async throws -> DiscoveredMatchRoom {
        guard let room = other?.room, room.id == id else { throw MatchTransportError.roomNotFound }
        return DiscoveredMatchRoom(descriptor: room)
    }

    func host(room: RoomDescriptor, isPublic: Bool) {
        _ = isPublic
        self.room = room
        hosting = true
        onEvent?(.ready)
    }

    func join(room: DiscoveredMatchRoom) {
        self.room = room.descriptor
        hosting = false
        onEvent?(.ready)
        onEvent?(.peerConnected(TransportPeerID("host")))
        other?.onEvent?(.peerConnected(TransportPeerID("client")))
    }

    func reconnect() {}

    func send(_ envelope: WireEnvelope, to recipient: TransportRecipient) {
        sentEnvelopes.append(envelope)
        guard let other else { return }
        switch recipient {
        case .host:
            other.onEvent?(.message(envelope, from: TransportPeerID("client")))
        case .peer, .allClients:
            other.onEvent?(.message(envelope, from: TransportPeerID("host")))
        }
    }

    func updateRoom(_ descriptor: RoomDescriptor, isPublic: Bool) {
        _ = isPublic
        room = descriptor
    }

    func disconnect(closeRoom: Bool) {
        disconnectCalls += 1
        lastCloseRoom = closeRoom
        if closeRoom { room = nil }
        hosting = false
    }
}

private func uuidSort(_ lhs: UUID, _ rhs: UUID) -> Bool {
    lhs.uuidString < rhs.uuidString
}
