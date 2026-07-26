import XCTest
@testable import SplendorUIDemo

@MainActor
final class SilkRoadGameStateTests: XCTestCase {
    func testFixtureUsesFourPlusOneMarketLayout() {
        let state = SilkRoadGameState()

        XCTAssertEqual(state.market.count, 3)
        for row in state.market {
            XCTAssertEqual(row.baseCards.count, 4)
            XCTAssertTrue(row.baseCards.allSatisfy { $0.source == .base })
            XCTAssertEqual(row.silkRoadCard.source, .silkRoad)
            XCTAssertEqual(row.silkRoadCard.level, row.level)
        }
        XCTAssertEqual(state.allMarketCards.count, 15)
    }

    func testFixtureKeepsSixPlayerOpponentCarousel() {
        let state = SilkRoadGameState()

        XCTAssertEqual(state.opponents.count, 6)
        state.showPreviousOpponent()
        XCTAssertEqual(state.opponentIndex, 5)
        state.showNextOpponent()
        XCTAssertEqual(state.opponentIndex, 0)
    }

    func testGemSelectionUpdatesBankAndPlayerImmediately() {
        let state = SilkRoadGameState()
        let bankBefore = state.bank[.ruby, default: 0]
        let playerBefore = state.playerTokens[.ruby, default: 0]

        state.toggleGem(.ruby)
        state.confirmGemSelection()

        XCTAssertEqual(state.bank[.ruby], bankBefore - 1)
        XCTAssertEqual(state.playerTokens[.ruby], playerBefore + 1)
        XCTAssertTrue(state.selectedGems.isEmpty)
    }

    func testGoldCannotBeSelectedDirectly() {
        let state = SilkRoadGameState()

        state.toggleGem(.gold)

        XCTAssertFalse(state.hasGemSelection)
    }

    func testCardActionsOnlyProvideDemoFeedback() {
        let state = SilkRoadGameState()
        let card = state.market[0].silkRoadCard
        let marketBefore = state.market

        state.open(card)
        state.reserve(card)

        XCTAssertNil(state.activeSheet)
        XCTAssertEqual(state.market, marketBefore)
        XCTAssertEqual(state.feedbackMessage, "已预留丝绸之路牌（演示）")
    }

    func testExtraCardsExposeCompactEffectDetails() {
        let state = SilkRoadGameState()
        let effects = state.market.compactMap { $0.silkRoadCard.effect }

        XCTAssertEqual(effects.count, 3)
        XCTAssertEqual(Set(effects.map(\.title)).count, 3)
    }
}

