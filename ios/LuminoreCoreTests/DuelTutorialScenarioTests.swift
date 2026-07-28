import XCTest
@testable import LuminoreCore

final class DuelTutorialScenarioTests: XCTestCase {
    private let learnerID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
    private let rules = DuelRuleset()

    func testSetupIsDeterministicTwoSeatTutorial() throws {
        let setup = makeSetup()
        let state = setup.state
        let duel = try XCTUnwrap(state.duel)

        XCTAssertEqual(setup.participants.count, 2)
        XCTAssertEqual(setup.participants[0].kind, .human)
        XCTAssertEqual(setup.participants[1].kind, .bot)
        XCTAssertEqual(setup.scriptedOpponentID, setup.participants[1].id)
        XCTAssertEqual(setup.scriptedOpponentActions.count, 8)
        XCTAssertEqual(state.configuration.mode, .duel)
        XCTAssertNil(state.configuration.turnDurationSeconds)
        XCTAssertEqual(state.currentPlayer.id, learnerID)
        XCTAssertEqual(duel.board.count, 25)
        XCTAssertEqual(duel.board[TutorialScenario.duelGoldIndex], .gold)
        XCTAssertEqual(
            TutorialScenario.duelFirstLine.compactMap { duel.board[$0] },
            [.sapphire, .ruby, .emerald]
        )
        XCTAssertEqual(
            TutorialScenario.duelPearlLine.compactMap { duel.board[$0] },
            [.pearl, .pearl, .onyx]
        )

        let visibleIDs = Set(duel.market.values.flatMap { $0 }.map(\.id))
        XCTAssertTrue(visibleIDs.isSuperset(of: [
            TutorialScenario.duelDoubleBonusCardID,
            TutorialScenario.duelReserveCardID,
            TutorialScenario.duelAbilityCardID,
            TutorialScenario.duelCrownCardID,
            TutorialScenario.duelFinalCardID,
        ]))
        XCTAssertEqual(duel.availableRoyals.map(\.id), [TutorialScenario.duelRoyalID])
    }

    func testStateIsCodableRoundTrip() throws {
        let state = makeSetup().state
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(GameState.self, from: data), state)
    }

    func testGuidedWalkthroughAndFreePlayFinishAreLegal() throws {
        let setup = makeSetup()
        let opponentID = try XCTUnwrap(setup.scriptedOpponentID)
        var state = setup.state

        try apply(.duel(.take(boardIndices: TutorialScenario.duelFirstLine, returning: [:])),
                  by: learnerID, to: &state)
        try apply(setup.scriptedOpponentActions[0], by: opponentID, to: &state)
        XCTAssertEqual(learner(state).privileges, 1)

        try apply(.duel(.spendPrivilege(boardIndex: TutorialScenario.duelPrivilegeTargetIndex)),
                  by: learnerID, to: &state)
        XCTAssertEqual(learner(state).privileges, 0)
        try apply(.duel(.replenish), by: learnerID, to: &state)
        XCTAssertEqual(state.duel?.bag.count, 0)
        XCTAssertEqual(opponent(state).privileges, 1)

        try apply(.duel(.take(boardIndices: TutorialScenario.duelPearlLine, returning: [:])),
                  by: learnerID, to: &state)
        XCTAssertEqual(learner(state).tokens[.pearl], 2)
        XCTAssertEqual(opponent(state).privileges, 2)
        try apply(setup.scriptedOpponentActions[1], by: opponentID, to: &state)
        try apply(setup.scriptedOpponentActions[2], by: opponentID, to: &state)

        try apply(.duel(.purchase(
            source: .market(cardID: TutorialScenario.duelDoubleBonusCardID),
            payment: [.sapphire: 2, .onyx: 1, .pearl: 1],
            choices: .init(),
            returning: [:]
        )), by: learnerID, to: &state)
        XCTAssertEqual(learner(state).bonuses[.diamond], 3)
        try apply(setup.scriptedOpponentActions[3], by: opponentID, to: &state)

        try apply(.duel(.reserve(
            goldBoardIndex: TutorialScenario.duelGoldIndex,
            source: .market(cardID: TutorialScenario.duelReserveCardID),
            returning: [:]
        )), by: learnerID, to: &state)
        XCTAssertEqual(learner(state).reservedCards.map(\.id), [TutorialScenario.duelReserveCardID])
        XCTAssertEqual(learner(state).tokens[.gold], 1)
        try apply(setup.scriptedOpponentActions[4], by: opponentID, to: &state)

        try apply(.duel(.purchase(
            source: .reserved(cardID: TutorialScenario.duelReserveCardID),
            payment: [.ruby: 2, .gold: 1],
            choices: .init(),
            returning: [:]
        )), by: learnerID, to: &state)
        XCTAssertTrue(learner(state).reservedCards.isEmpty)
        try apply(setup.scriptedOpponentActions[5], by: opponentID, to: &state)

        try apply(.duel(.purchase(
            source: .market(cardID: TutorialScenario.duelAbilityCardID),
            payment: [.emerald: 1],
            choices: .init(wildBonusColor: .diamond, stolenToken: .sapphire),
            returning: [:]
        )), by: learnerID, to: &state)
        XCTAssertEqual(opponent(state).tokens[.sapphire, default: 0], 0)
        try apply(setup.scriptedOpponentActions[6], by: opponentID, to: &state)

        try apply(.duel(.purchase(
            source: .market(cardID: TutorialScenario.duelCrownCardID),
            payment: [:],
            choices: .init(royalID: TutorialScenario.duelRoyalID),
            returning: [:]
        )), by: learnerID, to: &state)
        XCTAssertEqual(learner(state).crowns, 3)
        XCTAssertEqual(learner(state).royalCards.map(\.id), [TutorialScenario.duelRoyalID])
        try apply(setup.scriptedOpponentActions[7], by: opponentID, to: &state)

        XCTAssertEqual(learner(state).prestige, 18)
        XCTAssertEqual(state.status, .playing)
        XCTAssertEqual(state.currentPlayer.id, learnerID)

        try apply(.duel(.purchase(
            source: .market(cardID: TutorialScenario.duelFinalCardID),
            payment: [:],
            choices: .init(),
            returning: [:]
        )), by: learnerID, to: &state)
        XCTAssertEqual(learner(state).prestige, DuelRules.targetPrestige)
        XCTAssertEqual(state.status, .finished)
        XCTAssertEqual(state.result?.winnerIDs, [learnerID])
    }

    private func makeSetup() -> TutorialMatchSetup {
        TutorialScenario.duel(playerID: learnerID, nickname: "Learner", opponentNickname: "Tutor")
    }

    private func apply(_ action: GameAction, by playerID: UUID, to state: inout GameState) throws {
        try rules.apply(action, playerID: playerID, to: &state)
    }

    private func learner(_ state: GameState) -> DuelPlayerState {
        state.duel!.players.first { $0.id == learnerID }!
    }

    private func opponent(_ state: GameState) -> DuelPlayerState {
        state.duel!.players.first { $0.id != learnerID }!
    }
}
