import XCTest
@testable import LuminoreCore

final class NetworkProtocolTests: XCTestCase {
    func testLengthPrefixedFramerHandlesFragmentationAndStickyPackets() throws {
        let first = Data("first".utf8)
        let second = Data("second-message".utf8)
        var combined = try LengthPrefixedFramer.frame(first)
        combined.append(try LengthPrefixedFramer.frame(second))

        var parser = LengthPrefixedFramer()
        XCTAssertTrue(try parser.append(combined.prefix(3)).isEmpty)
        let frames = try parser.append(combined.dropFirst(3))
        XCTAssertEqual(frames, [first, second])
    }

    func testWireEnvelopeRoundTripPreservesAssociatedPayload() throws {
        let roomID = UUID()
        let senderID = UUID()
        let envelope = WireEnvelope(
            roomID: roomID,
            senderID: senderID,
            sequence: 9,
            payload: .action(.take(tokens: [.ruby: 1, .diamond: 1, .emerald: 1], returning: [:]))
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(WireEnvelope.self, from: data)
        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(decoded.protocolVersion, 1)
    }

    func testVersionedTakeActionFixtureDecodes() throws {
        let json = #"{"messageID":"11111111-1111-1111-1111-111111111111","payload":{"action":{"returning":{},"tokens":{"diamond":1,"emerald":1,"sapphire":1},"type":"take"},"type":"action"},"protocolVersion":1,"roomID":"22222222-2222-2222-2222-222222222222","senderID":"33333333-3333-3333-3333-333333333333","sequence":7}"#
        let envelope = try JSONDecoder().decode(WireEnvelope.self, from: Data(json.utf8))
        XCTAssertEqual(
            envelope.payload,
            .action(.take(tokens: [.diamond: 1, .emerald: 1, .sapphire: 1], returning: [:]))
        )
    }

    func testLegacyJoinRequestWithoutDeviceInstallDecodes() throws {
        // A pre-install-ID (protocol v1) client omits deviceInstallID entirely; it
        // must still decode, with the field defaulting to nil so the host falls back
        // to token-only seat reclaim.
        let json = #"{"participantID":"11111111-1111-1111-1111-111111111111","nickname":"Ang","authenticationCode":"","sessionToken":null}"#
        let request = try JSONDecoder().decode(JoinRequest.self, from: Data(json.utf8))
        XCTAssertNil(request.deviceInstallID)
        XCTAssertEqual(request.nickname, "Ang")
    }

    func testJoinRequestPreservesDeviceInstallAcrossRoundTrip() throws {
        let install = UUID()
        let request = JoinRequest(
            participantID: UUID(),
            nickname: "Nova",
            authenticationCode: Data([1, 2, 3]),
            sessionToken: "token",
            deviceInstallID: install
        )
        let decoded = try JSONDecoder().decode(JoinRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(decoded.deviceInstallID, install)
        XCTAssertEqual(decoded, request)
    }

    func testSetPausedMessageRoundTrips() throws {
        for paused in [true, false] {
            let envelope = WireEnvelope(
                roomID: UUID(),
                senderID: UUID(),
                sequence: 3,
                payload: .setPaused(paused)
            )
            let decoded = try JSONDecoder().decode(WireEnvelope.self, from: JSONEncoder().encode(envelope))
            XCTAssertEqual(decoded.payload, .setPaused(paused))
        }
    }

    func testSessionSuspendedMessageRoundTrips() throws {
        let envelope = WireEnvelope(roomID: UUID(), senderID: UUID(), sequence: 4, payload: .sessionSuspended)
        let decoded = try JSONDecoder().decode(WireEnvelope.self, from: JSONEncoder().encode(envelope))
        XCTAssertEqual(decoded.payload, .sessionSuspended)
    }

    func testFrameRejectsOversizedPayload() {
        XCTAssertThrowsError(try LengthPrefixedFramer.frame(Data(count: LengthPrefixedFramer.maximumFrameSize + 1)))
    }

    func testLegacyConfigurationDefaultsGracePeriodToEnabled() throws {
        let json = #"{"mode":"standard","targetPrestige":15,"turnDurationSeconds":30}"#
        let configuration = try JSONDecoder().decode(GameConfiguration.self, from: Data(json.utf8))
        XCTAssertTrue(configuration.turnGracePeriodEnabled)
    }

    func testDisabledGracePeriodSurvivesRoundTrip() throws {
        let configuration = GameConfiguration(turnGracePeriodEnabled: false)
        let data = try JSONEncoder().encode(configuration)
        XCTAssertFalse(try JSONDecoder().decode(GameConfiguration.self, from: data).turnGracePeriodEnabled)
    }
}
