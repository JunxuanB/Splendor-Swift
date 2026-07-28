import XCTest
@testable import LuminoreCore

final class TutorialScenarioTests: XCTestCase {
    private let rules = StandardRuleset()
    private let playerID = UUID()

    private func makeScenario() -> GameState {
        TutorialScenario.standard(playerID: playerID, nickname: "Learner").state
    }

    // MARK: - Board shape

    func testScenarioIsDeterministicSoloBoard() {
        let state = makeScenario()
        XCTAssertEqual(state.players.count, 1)
        let player = state.players[0]
        XCTAssertEqual(player.id, playerID)
        XCTAssertEqual(player.purchasedCards.count, 6, "six pre-owned cards")
        XCTAssertEqual(player.prestige, 4, "pre-owned prestige")
        XCTAssertEqual(player.tokenCount, 4, "four starting tokens")
        XCTAssertEqual(state.availableNobles.count, 1)
        XCTAssertEqual(state.status, .playing)
        XCTAssertEqual(state.currentPlayer.id, playerID)
        XCTAssertEqual(state.configuration.targetPrestige, TutorialScenario.targetPrestige)
        XCTAssertNil(state.configuration.turnDurationSeconds, "no clock in the tutorial")

        // Well-known cards must be present in the market.
        let marketIDs = Set(state.market.values.flatMap { $0 }.map(\.id))
        XCTAssertTrue(marketIDs.contains(TutorialScenario.affordableCardID))
        XCTAssertTrue(marketIDs.contains(TutorialScenario.permanentExampleCardID))
        XCTAssertTrue(marketIDs.contains(TutorialScenario.nobleTriggerCardID))
        XCTAssertTrue(marketIDs.contains(TutorialScenario.reserveTargetID))
    }

    func testScenarioIsCodableRoundTrip() throws {
        let state = makeScenario()
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded, state)
    }

    // MARK: - Scripted walkthrough (mirrors the guided step predicates)

    func testGuidedScriptTeachesEveryCoreActionAndReachesTarget() throws {
        var state = makeScenario()

        // Step "take": 3 different-colored gems.
        try rules.apply(
            .take(tokens: [.diamond: 1, .sapphire: 1, .emerald: 1], returning: [:]),
            playerID: playerID, to: &state
        )
        XCTAssertGreaterThan(local(state).tokenCount, 4, "take step completion")

        // Step "take two": double-tap ruby while four remain in the bank.
        try rules.apply(
            .take(tokens: [.ruby: 2], returning: [:]),
            playerID: playerID, to: &state
        )
        XCTAssertEqual(local(state).tokens[.ruby], 3, "double-take step completion")

        // Step "buy": the affordable card. Should NOT attract the noble yet.
        try rules.apply(
            .purchase(source: .market(cardID: TutorialScenario.affordableCardID),
                      payment: [.sapphire: 1, .onyx: 1], nobleID: nil),
            playerID: playerID, to: &state
        )
        XCTAssertEqual(local(state).purchasedCards.count, 7, "buy step completion")
        XCTAssertEqual(local(state).nobles.count, 0, "noble must not trigger on the first buy")

        // Step "permanent gems": cost 5 diamonds is covered by bonus3 + tokens2.
        let permanentExample = try XCTUnwrap(card(TutorialScenario.permanentExampleCardID, in: state))
        let permanentDecision = try XCTUnwrap(PurchasePlanner.preferredDecision(
            for: permanentExample,
            player: publicSnapshot(local(state)),
            availableNobles: state.availableNobles
        ))
        XCTAssertEqual(local(state).bonuses[.diamond], 3)
        XCTAssertEqual(local(state).tokens[.diamond], 2)
        XCTAssertEqual(permanentDecision.payment, [.diamond: 2])
        try rules.apply(
            .purchase(source: .market(cardID: TutorialScenario.permanentExampleCardID),
                      payment: permanentDecision.payment, nobleID: permanentDecision.nobleID),
            playerID: playerID, to: &state
        )
        XCTAssertEqual(local(state).purchasedCards.count, 8, "discount example completion")
        XCTAssertEqual(local(state).nobles.count, 0, "noble remains one diamond bonus short")

        // Step "reserve": grabs a gold token.
        try rules.apply(
            .reserve(source: .market(cardID: TutorialScenario.reserveTargetID), returning: [:]),
            playerID: playerID, to: &state
        )
        XCTAssertEqual(local(state).reservedCards.count, 1, "reserve step completion")
        XCTAssertGreaterThanOrEqual(local(state).tokens[.gold, default: 0], 1, "reserve grants gold")

        // Step "noble": this spends three rubies plus the wild gold, then visits.
        let decision = try XCTUnwrap(PurchasePlanner.preferredDecision(
            for: try XCTUnwrap(card(TutorialScenario.nobleTriggerCardID, in: state)),
            player: publicSnapshot(local(state)),
            availableNobles: state.availableNobles
        ))
        XCTAssertNotNil(decision.nobleID, "planner should attach the eligible noble")
        XCTAssertEqual(decision.payment, [.ruby: 3, .gold: 1])
        try rules.apply(
            .purchase(source: .market(cardID: TutorialScenario.nobleTriggerCardID),
                      payment: decision.payment, nobleID: decision.nobleID),
            playerID: playerID, to: &state
        )
        XCTAssertEqual(local(state).nobles.count, 1, "noble step completion")
        XCTAssertEqual(local(state).prestige, 9, "4 + card(1) + example(0) + card(1) + noble(3)")
        XCTAssertEqual(state.status, .playing, "still short of the target")

        // Free-play tail: one more prestige card reaches the target and ends the game.
        let filler = try XCTUnwrap(state.market[1]?.first {
            $0.prestige >= 1
                && ![TutorialScenario.affordableCardID, TutorialScenario.nobleTriggerCardID].contains($0.id)
        })
        let fillerDecision = try XCTUnwrap(PurchasePlanner.preferredDecision(
            for: filler, player: publicSnapshot(local(state)), availableNobles: state.availableNobles
        ))
        try rules.apply(
            .purchase(source: .market(cardID: filler.id),
                      payment: fillerDecision.payment, nobleID: fillerDecision.nobleID),
            playerID: playerID, to: &state
        )
        XCTAssertGreaterThanOrEqual(local(state).prestige, TutorialScenario.targetPrestige)
        XCTAssertEqual(state.status, .finished, "reaching the target finishes the solo game")
    }

    // MARK: - Helpers

    private func local(_ state: GameState) -> PlayerState {
        state.players.first { $0.id == playerID }!
    }

    private func card(_ id: String, in state: GameState) -> DevelopmentCard? {
        state.market.values.flatMap { $0 }.first { $0.id == id }
    }

    private func publicSnapshot(_ player: PlayerState) -> PublicPlayerSnapshot {
        PublicPlayerSnapshot(
            id: player.id,
            nickname: player.nickname,
            kind: player.kind,
            medalCount: player.medalCount,
            isConnected: player.isConnected,
            tokens: player.tokens,
            purchasedCards: player.purchasedCards,
            reservedCards: player.reservedCards,
            reservedCardCount: player.reservedCards.count,
            nobles: player.nobles,
            prestige: player.prestige
        )
    }
}
