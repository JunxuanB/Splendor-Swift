import XCTest
@testable import SplendorUIDemo

@MainActor
final class DuelGameStateTests: XCTestCase {
    // Fixture board (see DuelGameState.makeBoard):
    // row0  0..4  : white blue  nil  red  black
    // row1  5..9  : white blue  green red  black
    // row2 10..14 : white blue  green red  black
    // row3 15..19 : white blue  green nil  black
    // row4 20..24 : pearl pearl pearl gold gold

    func testFixtureShape() {
        let state = DuelGameState()

        XCTAssertEqual(state.board.count, 25)
        XCTAssertEqual(state.market[1]?.count, 5)
        XCTAssertEqual(state.market[2]?.count, 4)
        XCTAssertEqual(state.market[3]?.count, 3)
        XCTAssertEqual(state.royals.count, 4)

        // The three privileges are split between the pool and the two players.
        let total = state.privilegesOnBoard + state.player.privileges + state.opponent.privileges
        XCTAssertEqual(total, DuelRules.totalPrivileges)
    }

    func testLineValidation() {
        let state = DuelGameState()

        XCTAssertTrue(state.isValidLine([5, 6, 7]))     // horizontal
        XCTAssertTrue(state.isValidLine([5, 10, 15]))   // vertical
        XCTAssertTrue(state.isValidLine([5, 11, 17]))   // diagonal ↘

        XCTAssertFalse(state.isValidLine([5, 7]))       // not adjacent
        XCTAssertFalse(state.isValidLine([1, 2]))       // includes empty space
        XCTAssertFalse(state.isValidLine([22, 23]))     // includes gold
        XCTAssertFalse(state.isValidLine([5, 6, 7, 8])) // more than three
    }

    func testTappingBuildsAndRestartsSelection() {
        let state = DuelGameState()

        state.tapCell(5)
        state.tapCell(6)
        state.tapCell(7)
        XCTAssertEqual(state.selection, [5, 6, 7])

        // A tap that cannot extend the line starts a fresh selection.
        state.tapCell(8)
        XCTAssertEqual(state.selection, [8])
    }

    func testTappingSelectedEndpointDeselects() {
        let state = DuelGameState()

        state.tapCell(5)
        state.tapCell(6)
        state.tapCell(6)
        XCTAssertEqual(state.selection, [5])
    }

    func testConfirmTakeEmptiesSpacesAndSpawnsFlights() {
        let state = DuelGameState()

        state.tapCell(5)
        state.tapCell(6)
        state.tapCell(7)
        state.confirmTake()

        XCTAssertNil(state.board[5].token)
        XCTAssertNil(state.board[6].token)
        XCTAssertNil(state.board[7].token)
        XCTAssertEqual(state.flights.count, 3)
        XCTAssertTrue(state.selection.isEmpty)
    }

    func testLandingGemIncrementsPlayerTokens() {
        let state = DuelGameState()
        let before = state.player.tokens[.white, default: 0]

        state.tapCell(5)   // white
        state.tapCell(10)  // white
        state.tapCell(15)  // white
        state.confirmTake()
        for flight in state.flights { state.land(flight) }

        XCTAssertEqual(state.player.tokens[.white], before + 3)
    }

    func testThreeSameColorGrantsOpponentPrivilege() {
        let state = DuelGameState()
        let poolBefore = state.privilegesOnBoard
        let opponentBefore = state.opponent.privileges

        state.tapCell(5)   // white column
        state.tapCell(10)
        state.tapCell(15)
        state.confirmTake()

        XCTAssertEqual(state.opponent.privileges, opponentBefore + 1)
        XCTAssertEqual(state.privilegesOnBoard, poolBefore - 1)
    }

    func testPrivilegeModeTakesASingleToken() {
        let state = DuelGameState()
        XCTAssertEqual(state.player.privileges, 1)

        state.togglePrivilegeMode()
        XCTAssertTrue(state.privilegeMode)

        state.tapCell(5)
        XCTAssertNil(state.board[5].token)
        XCTAssertEqual(state.player.privileges, 0)
        XCTAssertFalse(state.privilegeMode)
        XCTAssertEqual(state.flights.count, 1)
    }

    func testGoldCannotBeTakenByLine() {
        let state = DuelGameState()

        state.tapCell(23) // gold
        XCTAssertTrue(state.selection.isEmpty)
    }

    func testCanPurchaseUsesBonusesTokensAndGold() {
        let state = DuelGameState()

        let affordable = state.market[1]![0]   // l1-1: blue2 white1
        let unaffordable = state.market[3]![1]  // l3-2: green6 pearl2
        XCTAssertTrue(state.canPurchase(affordable))
        XCTAssertFalse(state.canPurchase(unaffordable))
    }

    func testLandingPurchaseAppliesPointsAndCrowns() {
        let state = DuelGameState()
        let card = state.market[2]![0]  // l2-1: blue bonus, 1 point, 1 crown
        let royalsBefore = state.royals.count

        let flight = DuelFlight(kind: .cardBuy(card), from: .marketCard(card.id), to: .playerScore)
        state.land(flight)

        XCTAssertEqual(state.player.bonuses[.blue], 3)      // was 2
        XCTAssertEqual(state.player.crowns, 3)              // was 2, crossing the 3-crown threshold
        XCTAssertEqual(state.player.points, 6 + 1)          // base + card points only
        XCTAssertEqual(state.pendingRoyalPicks, 1)          // royal is offered, not auto-claimed
        XCTAssertEqual(state.royals.count, royalsBefore)    // still available until chosen
    }

    func testBagCannotFullyRefillBoard() {
        let state = DuelGameState()
        let empties = state.board.filter { $0.token == nil }.count

        // Held tokens mean the bag is smaller than the number of empty spaces,
        // so a refill fills only what the bag holds and leaves spaces empty.
        XCTAssertEqual(state.bagRemaining, 2)
        XCTAssertGreaterThan(empties, state.bagRemaining)
        XCTAssertEqual(state.refillPlan().count, state.bagRemaining)
    }

    func testSpiralStartsCenterGoesDownEndsBottomRight() {
        let order = DuelGameState.spiralOrder
        XCTAssertEqual(order.count, 25)
        XCTAssertEqual(order.first, 12)  // center (2,2)
        XCTAssertEqual(order[1], 17)     // first move is down → (3,2)
        XCTAssertEqual(order.last, 24)   // ends at bottom-right corner (4,4)
    }

    func testCrownGainOffersManualRoyalPick() {
        let state = DuelGameState()
        let card = state.market[2]![0]  // l2-1: 1 crown, crosses 2 → 3
        state.land(DuelFlight(kind: .cardBuy(card), from: .marketCard(card.id), to: .playerScore))

        // Reaching 3 crowns offers a pick rather than auto-claiming.
        XCTAssertEqual(state.pendingRoyalPicks, 1)
        let royalsBefore = state.royals.count
        let pointsBefore = state.player.points

        let royal = state.royals[0]
        state.claimRoyal(royal)

        XCTAssertEqual(state.royals.count, royalsBefore - 1)
        XCTAssertEqual(state.pendingRoyalPicks, 0)
        XCTAssertEqual(state.player.points, pointsBefore + royal.points)
    }

    func testRefillGrantsOpponentPrivilege() {
        let state = DuelGameState()
        let opponentBefore = state.opponent.privileges

        state.refillBoard()

        XCTAssertEqual(state.opponent.privileges, opponentBefore + 1)
    }

    func testReserveFromDeckAddsCardAndGold() {
        let state = DuelGameState()
        let reservedBefore = state.reservedCards.count
        let goldBefore = state.player.tokens[.gold, default: 0]

        state.reserveFromDeck(level: 1)

        XCTAssertEqual(state.reservedCards.count, reservedBefore + 1)
        XCTAssertEqual(state.player.tokens[.gold], goldBefore + 1)
    }
}
