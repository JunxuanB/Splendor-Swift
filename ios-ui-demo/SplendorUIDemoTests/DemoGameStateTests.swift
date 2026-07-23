import XCTest
@testable import SplendorUIDemo

@MainActor
final class DemoGameStateTests: XCTestCase {
    func testFixtureContainsFullDemoBoard() {
        let state = DemoGameState()

        XCTAssertEqual(state.opponents.count, 6)
        XCTAssertEqual(state.nobles.count, 5)
        XCTAssertEqual(state.market.count, 3)
        XCTAssertEqual(state.market.flatMap { $0 }.count, 12)
    }

    func testOpponentCarouselWrapsInBothDirections() {
        let state = DemoGameState()

        state.showPreviousOpponent()
        XCTAssertEqual(state.opponentIndex, 5)

        state.showNextOpponent()
        XCTAssertEqual(state.opponentIndex, 0)
    }

    func testConfirmingGemSelectionMovesFakeTokenCounts() {
        let state = DemoGameState()
        let bankBefore = state.bank[.ruby, default: 0]
        let playerBefore = state.playerTokens[.ruby, default: 0]

        state.toggleGem(.ruby)
        state.confirmGemSelection()

        XCTAssertEqual(state.bank[.ruby], bankBefore - 1)
        XCTAssertEqual(state.playerTokens[.ruby], playerBefore + 1)
        XCTAssertTrue(state.selectedGems.isEmpty)
    }

    func testSameColorCanBeSelectedTwice() {
        let state = DemoGameState()
        let bankBefore = state.bank[.diamond, default: 0]

        state.toggleGem(.diamond)
        state.toggleGem(.diamond)

        XCTAssertEqual(state.selectedGems[.diamond], 2)
        XCTAssertEqual(state.selectedGemTotal, 2)

        state.confirmGemSelection()
        XCTAssertEqual(state.bank[.diamond], bankBefore - 2)
    }

    func testGoldCannotBeSelectedDirectly() {
        let state = DemoGameState()

        state.toggleGem(.gold)

        XCTAssertFalse(state.hasGemSelection)
    }

    func testCardActionDoesNotMutateDemoData() {
        let state = DemoGameState()
        let bankBefore = state.bank
        let tokensBefore = state.playerTokens

        state.open(state.market[0][0])
        state.performCardAction("已购买该发展卡（演示）")

        XCTAssertNil(state.activeSheet)
        XCTAssertEqual(state.bank, bankBefore)
        XCTAssertEqual(state.playerTokens, tokensBefore)
    }

    func testReservedCardsAreAvailableFromPlayerPanel() {
        let state = DemoGameState()

        XCTAssertEqual(state.playerReservedCards, 2)
        state.openReservedCards()

        XCTAssertEqual(
            state.activeSheet,
            .reservedCards(title: "预留的发展卡", cards: state.reservedCards, allowsPurchase: true)
        )
    }

    func testOpponentReservedCardsMatchDisplayedCount() {
        let state = DemoGameState()

        for opponent in state.opponents {
            XCTAssertEqual(
                state.opponentReservedCards[opponent.id, default: []].count,
                opponent.reservedCards
            )
        }
    }

    func testAffordableCardUsesPermanentBonusesAndTokens() {
        let state = DemoGameState()

        XCTAssertTrue(state.canPurchase(state.market[0][0]))
        XCTAssertFalse(state.canPurchase(state.market[2][1]))
    }
}
