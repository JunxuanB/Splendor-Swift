import Foundation

public enum DuelCatalog {
    public static let cards: [DuelJewelCard] = parseCards()

    public static let royals: [DuelRoyalCard] = [
        DuelRoyalCard(id: "duel-royal-1", prestige: 3),
        DuelRoyalCard(id: "duel-royal-2", prestige: 2, ability: .takePrivilege),
        DuelRoyalCard(id: "duel-royal-3", prestige: 2, ability: .extraTurn),
        DuelRoyalCard(id: "duel-royal-4", prestige: 2, ability: .stealToken),
    ]
}

private extension DuelCatalog {
    /// Numeric data transcribed from the physical base game and cross-checked
    /// against the MIT-licensed `nicolasloucheu/splendor-duel` catalog.
    /// Source levels run high-to-low, so they are mapped to printed tiers 3...1.
    static let cardRows = """
    1,wild,,3,,,,,,,8,
    1,none,6,,,,8,,,,,
    1,blue,3,2,,,3,,3,,5,1
    1,black,3,2,,,3,,5,3,,1
    1,black,4,,,,2,,,2,6,
    1,green,4,,,,,2,6,2,,
    1,white,4,,,,6,2,,,2,
    1,wild,3,,again,,,,,8,,
    1,red,3,2,,,,5,3,,3,1
    1,green,3,2,,,5,3,,3,,1
    1,white,3,2,,,,3,,5,3,1
    1,red,4,,,,,,2,6,2,
    1,blue,4,,,,2,6,2,,,
    2,green,1,,steal,,3,,,4,,
    2,blue,2,,scroll,,2,4,,,,1
    2,green,2,1,,,2,2,,,2,1
    2,green,1,,,yes,,,,5,2,
    2,white,1,,,yes,,5,2,,,
    2,red,1,,,yes,2,,,,5,
    2,black,2,,scroll,,,,,2,4,1
    2,red,1,,,,2,2,2,,,1
    2,red,2,,scroll,,,,2,4,,1
    2,wild,2,,,,,,6,,,1
    2,white,1,,steal,,,4,,3,,
    2,wild,,2,,,,,6,,,1
    2,wild,,2,,,,6,,,,1
    2,white,2,1,,,,,2,2,2,1
    2,black,2,1,,,,2,2,2,,1
    2,blue,2,1,,,2,,,2,2,1
    2,red,1,,steal,,,3,,,4,
    2,white,2,,scroll,,4,,,,2,1
    2,green,2,,scroll,,,2,4,,,1
    2,blue,1,,steal,,,,4,,3,
    2,black,1,,steal,,4,,3,,,
    2,none,5,,,,,6,,,,1
    2,black,1,,,yes,5,2,,,,
    2,blue,1,,,yes,,,5,2,,
    3,black,,,,,1,1,1,1,,
    3,blue,,,token,,2,,,,2,
    3,red,,,token,,,2,2,,,
    3,black,1,,,,3,,,,,
    3,black,1,,,,,2,2,,,
    3,black,,,token,,,,2,2,,
    3,white,,,token,,,,,2,2,
    3,black,,,again,,2,2,,,,1
    3,green,,1,,,,,,3,,
    3,white,,,again,,,2,2,,,1
    3,wild,1,,,,,2,,2,1,1
    3,green,,,again,,,,,2,2,1
    3,red,,,again,,2,,,,2,1
    3,none,3,,,,,,,4,,1
    3,green,1,,,,3,,,,2,
    3,blue,,,,,1,,1,1,1,
    3,blue,,,again,,,,2,2,,1
    3,wild,1,,,,2,,2,,1,1
    3,green,,,,,1,1,,1,1,
    3,white,,1,,,,3,,,,
    3,red,,,,,1,1,1,,1,
    3,red,,,,,2,3,,,,
    3,blue,1,,,,,,,2,3,
    3,blue,,1,,,,,3,,,
    3,wild,1,,,,,4,,,,1
    3,green,,,token,,2,2,,,,
    3,white,,,,,,1,1,1,1,
    3,red,,1,,,,,,,3,
    3,wild,,1,,,4,,,,,1
    3,white,1,,,,,,2,3,,
    """

    static func parseCards() -> [DuelJewelCard] {
        var tierCounters: [Int: Int] = [:]
        return cardRows.split(separator: "\n").map { line in
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            precondition(fields.count == 12, "Malformed Duel catalog row: \(line)")
            let sourceLevel = Int(fields[0])!
            let tier = 4 - sourceLevel
            tierCounters[tier, default: 0] += 1

            let bonusColor = gemColor(fields[1])
            let isWild = fields[1] == "wild"
            let bonusAmount = fields[1] == "none" ? 0 : (fields[5] == "yes" ? 2 : 1)
            let costs: [DuelTokenColor: Int] = Dictionary(uniqueKeysWithValues: zip(
                [DuelTokenColor.diamond, .sapphire, .emerald, .ruby, .onyx, .pearl],
                fields[6 ... 11].map { Int($0) ?? 0 }
            ))

            return DuelJewelCard(
                id: "duel-t\(tier)-\(tierCounters[tier]!)",
                tier: tier,
                prestige: Int(fields[2]) ?? 0,
                crowns: Int(fields[3]) ?? 0,
                bonusColor: bonusColor,
                bonusAmount: bonusAmount,
                isWildBonus: isWild,
                cost: costs,
                ability: ability(fields[4])
            )
        }
    }

    static func gemColor(_ value: String) -> DuelGemColor? {
        switch value {
        case "white": .diamond
        case "blue": .sapphire
        case "green": .emerald
        case "red": .ruby
        case "black": .onyx
        default: nil
        }
    }

    static func ability(_ value: String) -> DuelCardAbility? {
        switch value {
        case "again": .extraTurn
        case "token": .takeMatchingToken
        case "scroll": .takePrivilege
        case "steal": .stealToken
        default: nil
        }
    }
}
