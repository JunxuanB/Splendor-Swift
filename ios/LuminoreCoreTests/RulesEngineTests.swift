import XCTest
@testable import LuminoreCore

final class RulesEngineTests: XCTestCase {
    private let rules = StandardRuleset()

    func testGameSetupDealsMarketAndNoblesForTwoThroughSevenPlayers() throws {
        for count in 2 ... 7 {
            let state = try makeGame(count: count, seed: UInt64(count))
            XCTAssertEqual(state.players.count, count)
            XCTAssertEqual(state.availableNobles.count, count + 1)
            XCTAssertEqual(state.market.values.flatMap { $0 }.count, 12)
            XCTAssertEqual(state.decks[1]?.count, 36)
            XCTAssertEqual(state.decks[2]?.count, 26)
            XCTAssertEqual(state.decks[3]?.count, 16)
        }
    }

    func testTakeThreeDifferentTokensAndAdvanceTurn() throws {
        var state = try makeGame(count: 2)
        let playerID = state.currentPlayer.id
        let nextID = state.players[(state.currentPlayerIndex + 1) % 2].id
        try rules.apply(.take(tokens: [.diamond: 1, .sapphire: 1, .ruby: 1], returning: [:]), playerID: playerID, to: &state)
        let player = try XCTUnwrap(state.players.first { $0.id == playerID })
        XCTAssertEqual(player.tokenCount, 3)
        XCTAssertEqual(state.bank[.diamond], 3)
        XCTAssertEqual(state.currentPlayer.id, nextID)
    }

    func testPlayerMayTakeOnlyOneToken() throws {
        var state = try makeGame(count: 2)
        let id = state.currentPlayer.id
        try rules.apply(.take(tokens: [.diamond: 1], returning: [:]), playerID: id, to: &state)
        XCTAssertEqual(state.players.first { $0.id == id }?.tokens[.diamond], 1)
    }

    func testPlayerMayVoluntarilyPass() throws {
        var state = try makeGame(count: 2)
        let id = state.currentPlayer.id
        let revision = state.revision
        try rules.apply(.pass, playerID: id, to: &state)
        XCTAssertNotEqual(state.currentPlayer.id, id)
        XCTAssertEqual(state.revision, revision + 1)
    }

    func testTakingTwoRequiresFourTokensBeforeTheAction() throws {
        var state = try makeGame(count: 2)
        let playerID = state.currentPlayer.id
        state.bank[.diamond] = 3
        let original = state
        XCTAssertThrowsError(try rules.apply(.take(tokens: [.diamond: 2], returning: [:]), playerID: playerID, to: &state))
        XCTAssertEqual(state, original, "Rejected commands must be atomic")
    }

    func testTokenLimitRequiresExactReturns() throws {
        var state = try makeGame(count: 2)
        let index = state.currentPlayerIndex
        for color in GemColor.purchasableColors { state.players[index].tokens[color] = 2 }
        let id = state.currentPlayer.id
        let picks: [GemColor: Int] = [.diamond: 1, .sapphire: 1, .ruby: 1]
        XCTAssertThrowsError(try rules.apply(.take(tokens: picks, returning: [:]), playerID: id, to: &state))
        try rules.apply(
            .take(tokens: picks, returning: [.diamond: 1, .sapphire: 1, .ruby: 1]),
            playerID: id,
            to: &state
        )
        XCTAssertEqual(state.players[index].tokenCount, 10)
    }

    func testReserveMarketCardAwardsGoldAndRefillsMarket() throws {
        var state = try makeGame(count: 2)
        let playerID = state.currentPlayer.id
        let card = try XCTUnwrap(state.market[1]?.first)
        let deckCount = try XCTUnwrap(state.decks[1]?.count)
        try rules.apply(.reserve(source: .market(cardID: card.id), returning: [:]), playerID: playerID, to: &state)
        let player = try XCTUnwrap(state.players.first { $0.id == playerID })
        XCTAssertEqual(player.reservedCards.first?.id, card.id)
        XCTAssertEqual(player.tokens[.gold], 1)
        XCTAssertEqual(state.market[1]?.count, 4)
        XCTAssertEqual(state.decks[1]?.count, deckCount - 1)
    }

    func testPurchaseUsesChosenColoredAndGoldPayment() throws {
        var state = try makeGame(count: 2)
        let index = state.currentPlayerIndex
        let playerID = state.currentPlayer.id
        let card = try XCTUnwrap(state.market[1]?.first)
        var payment: [GemColor: Int] = [:]
        var usedGold = false
        for color in GemColor.purchasableColors {
            let required = card.cost[color, default: 0]
            if required > 0, !usedGold {
                state.players[index].tokens[color] = max(0, required - 1)
                payment[color] = max(0, required - 1)
                usedGold = true
            } else {
                state.players[index].tokens[color] = required
                payment[color] = required
            }
        }
        state.players[index].tokens[.gold] = usedGold ? 1 : 0
        if usedGold { payment[.gold] = 1 }
        try rules.apply(.purchase(source: .market(cardID: card.id), payment: payment, nobleID: nil), playerID: playerID, to: &state)
        let player = try XCTUnwrap(state.players.first { $0.id == playerID })
        XCTAssertTrue(player.purchasedCards.contains(card))
        XCTAssertEqual(player.tokenCount, 0)
    }

    func testPreferredPurchaseUsesColoredTokensBeforeGold() {
        let card = DevelopmentCard(
            id: "preferred-payment",
            tier: 1,
            prestige: 0,
            bonus: .emerald,
            cost: [.diamond: 3, .sapphire: 2]
        )
        let existingBonus = DevelopmentCard(
            id: "existing-bonus",
            tier: 1,
            prestige: 0,
            bonus: .diamond,
            cost: [:]
        )
        let player = PublicPlayerSnapshot(
            id: UUID(),
            nickname: "Player",
            kind: .human,
            isConnected: true,
            tokens: [.diamond: 2, .sapphire: 1, .gold: 1],
            purchasedCards: [existingBonus],
            reservedCardCount: 0,
            nobles: [],
            prestige: 0
        )

        let decision = PurchasePlanner.preferredDecision(
            for: card,
            player: player,
            availableNobles: []
        )

        XCTAssertEqual(decision?.payment, [.diamond: 2, .sapphire: 1, .gold: 1])
    }

    func testInvalidPaymentLeavesStateUnchanged() throws {
        var state = try makeGame(count: 2)
        let card = try XCTUnwrap(state.market[3]?.first)
        let id = state.currentPlayer.id
        let original = state
        XCTAssertThrowsError(try rules.apply(.purchase(source: .market(cardID: card.id), payment: [:], nobleID: nil), playerID: id, to: &state))
        XCTAssertEqual(state, original)
    }

    func testDisconnectedPlayersKeepAssetsAndAreSkipped() throws {
        var state = try makeGame(count: 3)
        let disconnectedID = state.currentPlayer.id
        state.players[state.currentPlayerIndex].tokens[.ruby] = 2
        rules.setConnection(false, playerID: disconnectedID, in: &state)
        XCTAssertNotEqual(state.currentPlayer.id, disconnectedID)
        let disconnected = try XCTUnwrap(state.players.first { $0.id == disconnectedID })
        XCTAssertEqual(disconnected.tokens[.ruby], 2)
        XCTAssertFalse(disconnected.isConnected)
    }

    func testFinalRoundFinishesWhenDisconnectedSeatsCrossRoundBoundary() throws {
        var state = try makeGame(count: 3)
        let startingID = state.players[state.startingPlayerIndex].id
        let triggeringIndex = (state.startingPlayerIndex + 1) % state.players.count
        let nextIndex = (state.startingPlayerIndex + 2) % state.players.count
        state.currentPlayerIndex = triggeringIndex
        state.players[triggeringIndex].purchasedCards.append(
            DevelopmentCard(id: "winning-disconnect", tier: 3, prestige: 15, bonus: .ruby, cost: [:])
        )
        state.players[state.startingPlayerIndex].isConnected = false
        state.players[nextIndex].isConnected = false
        let triggerID = state.players[triggeringIndex].id

        try rules.apply(.pass, playerID: triggerID, to: &state)

        XCTAssertEqual(state.status, .finished)
        XCTAssertEqual(state.result?.winnerIDs, [triggerID])
        XCTAssertNotEqual(startingID, triggerID)
    }

    func testNegativeTokenCountsAreRejectedAtomically() throws {
        var state = try makeGame(count: 2)
        let original = state
        XCTAssertThrowsError(
            try rules.apply(
                .take(tokens: [.diamond: 1, .ruby: 1, .emerald: 1], returning: [.gold: -1]),
                playerID: state.currentPlayer.id,
                to: &state
            )
        )
        XCTAssertEqual(state, original)
    }

    func testFinalRoundAndTieBreaker() throws {
        var state = try makeGame(count: 2)
        let triggeringID = state.currentPlayer.id
        state.players[state.currentPlayerIndex].purchasedCards.append(
            DevelopmentCard(id: "winning", tier: 3, prestige: 15, bonus: .ruby, cost: [:])
        )
        try rules.apply(.pass, playerID: triggeringID, to: &state)
        while state.status == .playing {
            try rules.apply(.pass, playerID: state.currentPlayer.id, to: &state)
        }
        XCTAssertEqual(state.result?.winnerIDs, [triggeringID])
        XCTAssertEqual(state.result?.standings.first?.rank, 1)
    }

    func testClientSnapshotOnlyContainsLocalReservedCards() throws {
        var state = try makeGame(count: 2)
        let first = state.players[0].id
        let second = state.players[1].id
        state.players[0].reservedCards = [StandardCatalog.cards[0]]
        state.players[1].reservedCards = [StandardCatalog.cards[1], StandardCatalog.cards[2]]
        let snapshot = state.snapshot(for: first)
        XCTAssertEqual(snapshot.localReservedCards.map(\.id), [StandardCatalog.cards[0].id])
        XCTAssertEqual(snapshot.players.first { $0.id == second }?.reservedCardCount, 2)
    }

    private func makeGame(count: Int, seed: UInt64 = 42) throws -> GameState {
        let participants = (0 ..< count).map {
            Participant(id: UUID(), nickname: "Player \($0)", isHost: $0 == 0)
        }
        return try rules.makeGame(participants: participants, configuration: .init(), seed: seed)
    }
}
