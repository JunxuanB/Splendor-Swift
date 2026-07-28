import XCTest
@testable import LuminoreCore

final class DuelRulesetTests: XCTestCase {
    private let rules = DuelRuleset()

    func testCatalogHasCanonicalCountsAndUniqueIDs() {
        XCTAssertEqual(DuelCatalog.cards.count, 67)
        XCTAssertEqual(DuelCatalog.cards.filter { $0.tier == 1 }.count, 30)
        XCTAssertEqual(DuelCatalog.cards.filter { $0.tier == 2 }.count, 24)
        XCTAssertEqual(DuelCatalog.cards.filter { $0.tier == 3 }.count, 13)
        XCTAssertEqual(Set(DuelCatalog.cards.map(\.id)).count, 67)
        XCTAssertEqual(DuelCatalog.royals.count, 4)
        XCTAssertEqual(DuelRules.tokenSupply[.pearl], 2)
        XCTAssertEqual(DuelRules.tokenSupply[.gold], 3)
    }

    func testSetupUsesOfficialBoardPyramidAndOpeningPrivilege() throws {
        let state = try makeGame(seed: 7)
        let duel = try XCTUnwrap(state.duel)
        XCTAssertEqual(duel.board.compactMap { $0 }.count, 25)
        XCTAssertTrue(duel.bag.isEmpty)
        XCTAssertEqual(duel.market[1]?.count, 5)
        XCTAssertEqual(duel.market[2]?.count, 4)
        XCTAssertEqual(duel.market[3]?.count, 3)
        XCTAssertEqual(duel.privilegesInPool, 2)
        XCTAssertEqual(duel.players[state.startingPlayerIndex].privileges, 0)
        XCTAssertEqual(duel.players[1 - state.startingPlayerIndex].privileges, 1)
    }

    func testOnlyExactlyTwoPlayersAreAccepted() {
        let configuration = GameConfiguration(mode: .duel)
        XCTAssertThrowsError(try rules.makeGame(participants: [participant(0)], configuration: configuration, seed: 1))
        XCTAssertThrowsError(try rules.makeGame(
            participants: [participant(0), participant(1), participant(2)],
            configuration: configuration,
            seed: 1
        ))
    }

    func testTakingThreeIdenticalTokensGivesOpponentOnePrivilege() throws {
        var state = try makeGame()
        let actor = state.currentPlayer.id
        state.duel!.board[0] = .ruby
        state.duel!.board[1] = .ruby
        state.duel!.board[2] = .ruby
        let opponent = 1 - state.currentPlayerIndex
        let before = state.duel!.players[opponent].privileges

        try rules.apply(.duel(.take(boardIndices: [0, 1, 2], returning: [:])), playerID: actor, to: &state)

        XCTAssertEqual(state.duel!.players[opponent].privileges, before + 1)
        XCTAssertEqual(state.duel!.privilegesInPool, 1)
        XCTAssertNil(state.duel!.board[0])
        XCTAssertNotEqual(state.currentPlayer.id, actor)
    }

    func testTakingTwoPearlsGivesExactlyOnePrivilege() throws {
        var state = try makeGame()
        let actor = state.currentPlayer.id
        state.duel!.board[5] = .pearl
        state.duel!.board[6] = .pearl
        state.duel!.board[7] = .diamond
        let opponent = 1 - state.currentPlayerIndex
        let before = state.duel!.players[opponent].privileges
        try rules.apply(.duel(.take(boardIndices: [5, 6, 7], returning: [:])), playerID: actor, to: &state)
        XCTAssertEqual(state.duel!.players[opponent].privileges, before + 1)
    }

    func testInterruptedAndBentSelectionsAreRejectedAtomically() throws {
        var state = try makeGame()
        let original = state
        let actor = state.currentPlayer.id
        state.duel!.board[1] = nil
        let interrupted = state
        XCTAssertThrowsError(try rules.apply(
            .duel(.take(boardIndices: [0, 1, 2], returning: [:])),
            playerID: actor,
            to: &state
        ))
        XCTAssertEqual(state, interrupted)
        state = original
        XCTAssertThrowsError(try rules.apply(
            .duel(.take(boardIndices: [0, 1, 6], returning: [:])),
            playerID: actor,
            to: &state
        ))
        XCTAssertEqual(state, original)
    }

    func testPrivilegeThenReplenishOrderAndPrivilegeFallbackTransfer() throws {
        var state = try makeGame()
        let actorIndex = state.currentPlayerIndex
        let opponentIndex = 1 - actorIndex
        let actor = state.currentPlayer.id
        state.duel!.players[actorIndex].privileges = 2
        state.duel!.players[opponentIndex].privileges = 1
        state.duel!.privilegesInPool = 0
        state.duel!.bag = [.diamond]
        state.duel!.board[0] = nil

        try rules.apply(.duel(.spendPrivilege(boardIndex: 1)), playerID: actor, to: &state)
        XCTAssertEqual(state.currentPlayer.id, actor)
        try rules.apply(.duel(.replenish), playerID: actor, to: &state)
        XCTAssertEqual(state.duel!.turnStage, .mandatoryOnly)
        XCTAssertEqual(state.duel!.players[opponentIndex].privileges, 2)
        XCTAssertThrowsError(try rules.apply(.duel(.spendPrivilege(boardIndex: 2)), playerID: actor, to: &state))
    }

    func testReservationTakesSelectedGoldAndIsVisibleInPlayerSnapshots() throws {
        var state = try makeGame()
        let actor = state.currentPlayer.id
        let actorIndex = state.currentPlayerIndex
        let goldIndex = try XCTUnwrap(state.duel!.board.firstIndex(of: .gold))
        let card = try XCTUnwrap(state.duel!.market[1]?.first)
        try rules.apply(
            .duel(.reserve(goldBoardIndex: goldIndex, source: .market(cardID: card.id), returning: [:])),
            playerID: actor,
            to: &state
        )
        XCTAssertEqual(state.duel!.players[actorIndex].tokens[.gold], 1)
        XCTAssertEqual(state.duel!.players[actorIndex].reservedCards.map(\.id), [card.id])
        let actorSnapshot = try XCTUnwrap(state.snapshot(for: actor).duel)
        XCTAssertEqual(actorSnapshot.localReservedCards.map(\.id), [card.id])
        XCTAssertEqual(actorSnapshot.players.first { $0.id == actor }?.reservedCards.map(\.id), [card.id])

        let opponentSnapshot = try XCTUnwrap(
            state.snapshot(for: state.players[1 - actorIndex].id).duel
        )
        XCTAssertTrue(opponentSnapshot.localReservedCards.isEmpty)
        XCTAssertEqual(opponentSnapshot.players.first { $0.id == actor }?.reservedCards.map(\.id), [card.id])
    }

    func testLegacyDuelPlayerSnapshotWithoutReservedCardsStillDecodes() throws {
        let state = try makeGame()
        let data = try JSONEncoder().encode(state.snapshot(for: state.currentPlayer.id))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var duel = try XCTUnwrap(object["duel"] as? [String: Any])
        var players = try XCTUnwrap(duel["players"] as? [[String: Any]])
        players = players.map { player in
            var legacyPlayer = player
            legacyPlayer.removeValue(forKey: "reservedCards")
            return legacyPlayer
        }
        duel["players"] = players
        object["duel"] = duel

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ClientGameSnapshot.self, from: legacyData)

        XCTAssertTrue(decoded.duel?.players.allSatisfy(\.reservedCards.isEmpty) == true)
    }

    func testSnapshotIncludesBagTokenCounts() throws {
        var state = try makeGame()
        state.duel!.bag = [.diamond, .diamond, .pearl, .gold]

        let clientSnapshot = state.snapshot(for: state.currentPlayer.id)
        let snapshot = try XCTUnwrap(clientSnapshot.duel)

        XCTAssertEqual(snapshot.bagCount, 4)
        XCTAssertEqual(snapshot.bagTokenCounts, [.diamond: 2, .pearl: 1, .gold: 1])

        let wireData = try JSONEncoder().encode(clientSnapshot)
        let decoded = try JSONDecoder().decode(ClientGameSnapshot.self, from: wireData)
        XCTAssertEqual(decoded.duel?.bagTokenCounts, snapshot.bagTokenCounts)
    }

    func testWildBonusCannotBeFirstCardAndMustCopyOwnedNormalColor() throws {
        var state = try makeGame()
        let actor = state.currentPlayer.id
        let index = state.currentPlayerIndex
        let wild = try XCTUnwrap(DuelCatalog.cards.first { $0.tier == 1 && $0.isWildBonus && $0.crowns == 0 })
        state.duel!.market[1]![0] = wild
        giveExactCost(of: wild, to: index, state: &state)
        let payment = wild.cost
        XCTAssertThrowsError(try rules.apply(
            .duel(.purchase(
                source: .market(cardID: wild.id), payment: payment,
                choices: .init(wildBonusColor: .diamond), returning: [:]
            )), playerID: actor, to: &state
        ))

        let normal = DuelJewelCard(
            id: "owned-white", tier: 1, prestige: 0, crowns: 0,
            bonusColor: .diamond, bonusAmount: 1, cost: [:]
        )
        state.duel!.players[index].purchasedCards.append(DuelOwnedCard(card: normal, assignedWildColor: nil))
        try rules.apply(
            .duel(.purchase(
                source: .market(cardID: wild.id), payment: payment,
                choices: .init(wildBonusColor: .diamond), returning: [:]
            )), playerID: actor, to: &state
        )
        XCTAssertEqual(state.duel!.players[index].bonuses[.diamond], 2)
    }

    func testPearlHasNoDiscountAndGoldMayReplaceIt() throws {
        var state = try makeGame()
        let actor = state.currentPlayer.id
        let index = state.currentPlayerIndex
        let card = DuelJewelCard(
            id: "pearl-cost", tier: 1, prestige: 0, crowns: 0,
            bonusColor: .diamond, bonusAmount: 1, cost: [.pearl: 1]
        )
        state.duel!.market[1]![0] = card
        state.duel!.players[index].tokens = [.gold: 1]
        try rules.apply(
            .duel(.purchase(
                source: .market(cardID: card.id), payment: [.gold: 1], choices: .init(), returning: [:]
            )), playerID: actor, to: &state
        )
        XCTAssertTrue(state.duel!.players[index].purchasedCards.contains { $0.id == card.id })
    }

    func testTimeoutPassAdvancesTurnWithoutChangingResources() throws {
        var state = try makeGame()
        let actor = state.currentPlayer.id
        let duelBefore = state.duel
        try rules.apply(.pass, playerID: actor, to: &state)
        XCTAssertNotEqual(state.currentPlayer.id, actor)
        XCTAssertEqual(state.duel?.board, duelBefore?.board)
        XCTAssertEqual(state.duel?.players, duelBefore?.players)
    }

    func testDuelStateAndActionRoundTripThroughJSON() throws {
        let state = try makeGame()
        let stateData = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(GameState.self, from: stateData), state)
        let action = GameAction.duel(.purchase(
            source: .market(cardID: "x"),
            payment: [.gold: 1],
            choices: .init(wildBonusColor: .ruby, royalID: "r"),
            returning: [.pearl: 1]
        ))
        let actionData = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(GameAction.self, from: actionData), action)
    }

    private func makeGame(seed: UInt64 = 19) throws -> GameState {
        try rules.makeGame(
            participants: [participant(0), participant(1)],
            configuration: GameConfiguration(mode: .duel, turnDurationSeconds: nil),
            seed: seed
        )
    }

    private func participant(_ offset: Int) -> Participant {
        Participant(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", offset + 1))!,
            nickname: "P\(offset)",
            isHost: offset == 0
        )
    }

    private func giveExactCost(of card: DuelJewelCard, to index: Int, state: inout GameState) {
        state.duel!.players[index].tokens = card.cost
    }
}
