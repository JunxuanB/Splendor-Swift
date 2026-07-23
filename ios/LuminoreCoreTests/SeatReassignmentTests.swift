import XCTest
@testable import LuminoreCore

final class SeatReassignmentTests: XCTestCase {
    private let rules = StandardRuleset()

    private func makeGame(count: Int, seed: UInt64 = 7) throws -> GameState {
        let participants = (0 ..< count).map {
            Participant(id: UUID(), nickname: "Player \($0)", isHost: $0 == 0)
        }
        return try rules.makeGame(participants: participants, configuration: .init(), seed: seed)
    }

    func testReseatedPreservesProgressAndRebindsIdentity() throws {
        var state = try makeGame(count: 3)
        // Give the current player some progress before the substitution.
        let seatID = state.currentPlayer.id
        try rules.apply(.take(tokens: [.diamond: 1, .sapphire: 1, .emerald: 1], returning: [:]), playerID: seatID, to: &state)

        let seatIndex = try XCTUnwrap(state.players.firstIndex { $0.id == seatID })
        let before = state.players[seatIndex]
        let newID = UUID()

        let reseated = before.reseated(as: newID, nickname: "Substitute")
        XCTAssertEqual(reseated.id, newID)
        XCTAssertEqual(reseated.nickname, "Substitute")
        XCTAssertTrue(reseated.isConnected)
        // Progress carries over verbatim.
        XCTAssertEqual(reseated.tokens, before.tokens)
        XCTAssertEqual(reseated.purchasedCards, before.purchasedCards)
        XCTAssertEqual(reseated.reservedCards, before.reservedCards)
        XCTAssertEqual(reseated.prestige, before.prestige)
    }

    func testReseatingCurrentSeatTransfersTurnOwnership() throws {
        var state = try makeGame(count: 2)
        let currentIndex = state.currentPlayerIndex
        let newID = UUID()
        state.players[currentIndex] = state.players[currentIndex].reseated(as: newID, nickname: "Sub")
        // The seat index is unchanged, so the new identity now owns the current turn.
        XCTAssertEqual(state.currentPlayer.id, newID)
    }

    func testFullGameStateSurvivesJSONRoundTripForSaving() throws {
        var state = try makeGame(count: 4)
        try rules.apply(.take(tokens: [.diamond: 1, .sapphire: 1, .ruby: 1], returning: [:]), playerID: state.currentPlayer.id, to: &state)

        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(GameState.self, from: data)

        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.currentPlayerIndex, state.currentPlayerIndex)
        XCTAssertEqual(restored.players.map(\.id), state.players.map(\.id))
    }
}
