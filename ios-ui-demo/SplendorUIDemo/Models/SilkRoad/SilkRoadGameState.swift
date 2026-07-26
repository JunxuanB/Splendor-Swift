import Combine
import Foundation

@MainActor
final class SilkRoadGameState: ObservableObject {
    @Published private(set) var opponentIndex = 0
    @Published private(set) var bank: [GemColor: Int]
    @Published private(set) var playerTokens: [GemColor: Int]
    @Published private(set) var selectedGems: [GemColor: Int] = [:]
    @Published var activeSheet: SilkRoadSheet?
    @Published var feedbackMessage: String?

    let targetPrestige = 15
    let playerPrestige = 7
    let playerBonuses: [GemColor: Int]
    let reservedCards: [SilkRoadCard]
    let opponents: [PlayerSnapshot]
    let nobles: [NobleTile]
    let market: [SilkRoadMarketRow]
    let baseDeckCounts = [1: 30, 2: 22, 3: 14]

    init() {
        bank = [
            .diamond: 5, .sapphire: 4, .emerald: 5,
            .ruby: 4, .onyx: 5, .gold: 5,
        ]
        playerTokens = [
            .diamond: 1, .sapphire: 0, .emerald: 2,
            .ruby: 1, .onyx: 0, .gold: 1,
        ]
        playerBonuses = [
            .diamond: 2, .sapphire: 1, .emerald: 3,
            .ruby: 1, .onyx: 2,
        ]
        market = Self.makeMarket()
        reservedCards = [market[0].baseCards[1], market[1].silkRoadCard]
        opponents = Self.makeOpponents()
        nobles = Self.makeNobles()
    }

    var currentOpponent: PlayerSnapshot { opponents[opponentIndex] }
    var hasGemSelection: Bool { !selectedGems.isEmpty }

    var allMarketCards: [SilkRoadCard] {
        market.flatMap { $0.baseCards + [$0.silkRoadCard] }
    }

    func showNextOpponent() {
        guard !opponents.isEmpty else { return }
        opponentIndex = (opponentIndex + 1) % opponents.count
    }

    func showPreviousOpponent() {
        guard !opponents.isEmpty else { return }
        opponentIndex = (opponentIndex - 1 + opponents.count) % opponents.count
    }

    func toggleGem(_ gem: GemColor) {
        guard gem != .gold, bank[gem, default: 0] > 0 else { return }
        let current = selectedGems[gem, default: 0]
        let maximum = min(2, bank[gem, default: 0])
        if current < maximum {
            selectedGems[gem] = current + 1
        } else {
            selectedGems.removeValue(forKey: gem)
        }
    }

    func cancelGemSelection() { selectedGems.removeAll() }

    func confirmGemSelection() {
        guard hasGemSelection else { return }
        var amount = 0
        for (gem, count) in selectedGems where bank[gem, default: 0] >= count {
            bank[gem, default: 0] -= count
            playerTokens[gem, default: 0] += count
            amount += count
        }
        selectedGems.removeAll()
        showFeedback("已拿取 \(amount) 枚宝石")
    }

    func canPurchase(_ card: SilkRoadCard) -> Bool {
        var gold = playerTokens[.gold, default: 0]
        for gem in GemColor.allCases where gem != .gold {
            let required = card.costs[gem, default: 0]
            let available = playerTokens[gem, default: 0] + playerBonuses[gem, default: 0]
            gold -= max(0, required - available)
            if gold < 0 { return false }
        }
        return true
    }

    func open(_ card: SilkRoadCard) { activeSheet = .card(card) }
    func openReservedCards() { activeSheet = .reserved }
    func openRules() { activeSheet = .rules }

    func buy(_ card: SilkRoadCard) {
        activeSheet = nil
        showFeedback(card.source == .silkRoad ? "已购买丝绸之路牌（演示）" : "已购买发展卡（演示）")
    }

    func reserve(_ card: SilkRoadCard) {
        activeSheet = nil
        showFeedback(card.source == .silkRoad ? "已预留丝绸之路牌（演示）" : "已预留发展卡（演示）")
    }

    func showFeedback(_ message: String) { feedbackMessage = message }

    func clearFeedback(ifMatching message: String) {
        if feedbackMessage == message { feedbackMessage = nil }
    }
}

private extension SilkRoadGameState {
    static func makeMarket() -> [SilkRoadMarketRow] {
        [1, 2, 3].map { level in
            let colors: [GemColor] = [.diamond, .sapphire, .emerald, .ruby, .onyx]
            let baseCards = (1...4).map { index in
                SilkRoadCard(
                    id: "silk-base-\(level)-\(index)",
                    level: level,
                    source: .base,
                    prestige: max(0, level + index - 4),
                    bonus: colors[(level + index - 2) % colors.count],
                    costs: [colors[(level + index) % colors.count]: level + index],
                    effect: nil
                )
            }

            let effect = SilkRoadEffect.allCases[level - 1]
            let silkRoadCard = SilkRoadCard(
                id: "silk-extra-\(level)",
                level: level,
                source: .silkRoad,
                prestige: max(0, level - 1),
                bonus: level == 1 ? nil : colors[(level + 1) % colors.count],
                costs: [colors[(level + 2) % colors.count]: level + 2],
                effect: effect
            )
            return SilkRoadMarketRow(level: level, baseCards: baseCards, silkRoadCard: silkRoadCard)
        }
    }

    static func makeOpponents() -> [PlayerSnapshot] {
        let names = ["林墨", "小满", "Aurora", "阿澈", "Nova", "棋手六号"]
        return names.enumerated().map { index, name in
            PlayerSnapshot(
                id: "silk-opponent-\(index)",
                name: name,
                kind: index == 5 ? .bot : .human,
                prestige: [9, 5, 11, 6, 3, 8][index],
                reservedCards: [1, 0, 2, 0, 1, 1][index],
                permanentBonuses: [
                    .diamond: (index + 2) % 4,
                    .sapphire: (index + 1) % 3,
                    .emerald: (index + 3) % 4,
                    .ruby: index % 3,
                    .onyx: (index + 2) % 3,
                ],
                tokens: [
                    .diamond: index % 2,
                    .sapphire: (index + 1) % 2,
                    .emerald: index % 3 == 0 ? 2 : 0,
                    .ruby: 1,
                    .onyx: index % 2,
                    .gold: index % 3 == 0 ? 1 : 0,
                ]
            )
        }
    }

    static func makeNobles() -> [NobleTile] {
        [
            NobleTile(id: "silk-n1", name: "撒马尔罕使节", prestige: 3, requirements: [.diamond: 4, .sapphire: 4]),
            NobleTile(id: "silk-n2", name: "德里工匠", prestige: 3, requirements: [.emerald: 3, .ruby: 3, .onyx: 3]),
            NobleTile(id: "silk-n3", name: "东方商会", prestige: 3, requirements: [.diamond: 3, .ruby: 3, .onyx: 3]),
        ]
    }
}
