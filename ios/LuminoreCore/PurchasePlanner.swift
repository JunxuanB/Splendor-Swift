import Foundation

public struct PreferredPurchaseDecision: Equatable, Sendable {
    public let payment: [GemColor: Int]
    public let nobleID: String?

    public init(payment: [GemColor: Int], nobleID: String?) {
        self.payment = payment
        self.nobleID = nobleID
    }
}

public enum PurchasePlanner {
    /// Uses every available matching colored token before spending gold.
    /// If several nobles become eligible, their authoritative snapshot order
    /// provides a deterministic default.
    public static func preferredDecision(
        for card: DevelopmentCard,
        player: PublicPlayerSnapshot,
        availableNobles: [NobleTile]
    ) -> PreferredPurchaseDecision? {
        let bonuses = Dictionary(grouping: player.purchasedCards, by: \DevelopmentCard.bonus)
            .mapValues(\.count)
        var payment: [GemColor: Int] = [:]
        var goldNeeded = 0

        for color in GemColor.purchasableColors {
            let required = max(0, card.cost[color, default: 0] - bonuses[color, default: 0])
            let colored = min(required, player.tokens[color, default: 0])
            if colored > 0 { payment[color] = colored }
            goldNeeded += required - colored
        }

        guard goldNeeded <= player.tokens[.gold, default: 0] else { return nil }
        if goldNeeded > 0 { payment[.gold] = goldNeeded }

        var bonusesAfterPurchase = bonuses
        bonusesAfterPurchase[card.bonus, default: 0] += 1
        let nobleID = availableNobles.first { noble in
            noble.requirement.allSatisfy { bonusesAfterPurchase[$0.key, default: 0] >= $0.value }
        }?.id

        return PreferredPurchaseDecision(payment: payment, nobleID: nobleID)
    }
}
