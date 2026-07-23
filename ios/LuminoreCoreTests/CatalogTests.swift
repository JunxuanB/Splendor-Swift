import XCTest
@testable import LuminoreCore

final class CatalogTests: XCTestCase {
    func testStandardCatalogHasCanonicalCountsAndUniqueIDs() {
        XCTAssertEqual(StandardCatalog.cards.count, 90)
        XCTAssertEqual(StandardCatalog.cards.filter { $0.tier == 1 }.count, 40)
        XCTAssertEqual(StandardCatalog.cards.filter { $0.tier == 2 }.count, 30)
        XCTAssertEqual(StandardCatalog.cards.filter { $0.tier == 3 }.count, 20)
        XCTAssertEqual(Set(StandardCatalog.cards.map(\.id)).count, 90)
        XCTAssertEqual(StandardCatalog.nobles.count, 10)
        XCTAssertEqual(Set(StandardCatalog.nobles.map(\.id)).count, 10)
    }

    func testBankScalingForEverySupportedPlayerCount() {
        let expected: [(Int, Int, Int)] = [
            (2, 4, 5), (3, 5, 5), (4, 7, 5),
            (5, 8, 6), (6, 9, 7), (7, 10, 8)
        ]
        for (players, colored, gold) in expected {
            let bank = StandardRuleset.initialBank(playerCount: players)
            XCTAssertTrue(GemColor.purchasableColors.allSatisfy { bank[$0] == colored })
            XCTAssertEqual(bank[.gold], gold)
        }
    }
}
